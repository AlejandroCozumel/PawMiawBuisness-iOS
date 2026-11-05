//
//  CashCSV.swift
//  PawMiawNegocios
//
//  Spreadsheets made from what the app read with the person's session (web:
//  lib/finance.ts `toCsv`, `exportFileName`, `downloadCsv`): UTF-8 with the
//  byte-order mark Excel needs for accents, comma-separated, CRLF lines.
//  On a phone the file is handed to the share sheet (Files, Mail, AirDrop…).
//

import SwiftUI
import UIKit

enum CashCSV {
    /// One cell, quoted when it holds a separator, a quote or a line break.
    static func cell(_ value: String?) -> String {
        guard let text = value else { return "" }
        if text.contains(where: { $0 == "\"" || $0 == "," || $0 == "\n" || $0 == ";" || $0 == "\r" }) {
            return "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return text
    }

    /// Cents as a plain number spreadsheets read: 1234.50
    static func money(_ cents: Int?) -> String {
        guard let cents else { return "" }
        let sign = cents < 0 ? "-" : ""
        let value = abs(cents)
        return "\(sign)\(value / 100).\(String(format: "%02d", value % 100))"
    }

    static func make(header: [String], rows: [[String?]]) -> String {
        ([header.map { cell($0) }] + rows.map { $0.map(cell) }).map { $0.joined(separator: ",") }.joined(separator: "\r\n")
    }

    /// "pagos_2026-11-01_2026-11-30.csv": the slug of what it is and the days it covers.
    static func fileName(_ what: String, from: String, to: String, ext: String = "csv") -> String {
        let folded = what.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var slug = ""
        var dash = false
        for character in folded {
            if character.isASCII && (character.isLetter || character.isNumber) {
                slug.append(character)
                dash = false
            } else if !dash && !slug.isEmpty {
                slug.append("-")
                dash = true
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return "\(slug)_\(from == to ? from : "\(from)_\(to)").\(ext)"
    }

    /// "2026-11-04 09:02" on the business's clock.
    static func dateTime(_ iso: String?, zone: TimeZone? = nil) -> String {
        guard let date = DateText.parse(iso) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone ?? Workspace.shared.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    /// The file on this device, ready to share.
    static func write(_ csv: String, name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("csv", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(("\u{FEFF}" + csv).utf8).write(to: url, options: .atomic)
        return url
    }
}

/// A file made, waiting for the share sheet.
struct CashSharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// "Exportar CSV": makes the file (it may read more pages first) and opens the share sheet.
struct CashCSVButton: View {
    var title: String = L("Export CSV")
    var disabled: Bool = false
    /// The file's name and its text.
    let make: () async throws -> (String, String)
    @State private var working = false
    @State private var file: CashSharedFile?

    var body: some View {
        PMButton(title, systemImage: "download", variant: .outline, size: .compact, isWorking: working) { export() }
            .disabled(disabled)
            .sheet(item: $file) { shared in
                ShareSheet(items: [shared.url])
                    .presentationDetents([.medium, .large])
            }
    }

    private func export() {
        working = true
        Task {
            defer { working = false }
            do {
                let (name, csv) = try await make()
                file = CashSharedFile(url: try CashCSV.write(csv, name: name))
            } catch {
                Toast.error(L("The file could not be made. Try again."))
            }
        }
    }
}

