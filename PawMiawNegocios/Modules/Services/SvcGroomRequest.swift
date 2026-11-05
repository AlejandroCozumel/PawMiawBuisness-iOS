//
//  SvcGroomRequest.swift
//  PawMiawNegocios
//
//  "Lo que pidió el dueño" in the groom's report (web: care/visit-report.tsx,
//  lib/groom-request.ts, hooks/use-groom-request.ts): the report starts from
//  what the owner asked for, says live where it differs ("Distinto a lo que
//  se pidió", with why), and offers to keep the cut as the pet's usual style
//  on the care card — only ever when someone taps it.
//

import SwiftUI

// MARK: - Shapes (GET /provider-appointments/{id}/groom-request)

/// What to do, with "same as last time" already filled in by the server.
struct SvcGroomWanted: Codable, Hashable {
    let services: [String]?
    let style: String?
    let styleText: String?
    let length: String?
}

struct SvcGroomStyleOffer: Codable, Hashable {
    let requested: Bool?
    let done: Bool?
}

struct SvcGroomRequestView: Decodable {
    let appointmentId: String
    let isGroom: Bool?
    /// Only whether there is one matters here (the visit page shows it whole).
    let request: JSONValue?
    let wanted: SvcGroomWanted?
    /// The report as the request says it: what a report with nothing yet starts from.
    let prefill: SvcReport?
    let careStyle: String?
    let careTools: String?
    let styleOffer: SvcGroomStyleOffer?

    var hasRequest: Bool { request.map { !$0.isNull } ?? false }
}

struct SvcUsualStyleResult: Decodable {
    let groomStyle: String
    let groomTools: String?
}

/// Where the report differs from what was asked.
struct SvcGroomDifferences {
    let notDone: [String]
    let added: [String]
    let style: (requested: String, done: String)?
    let length: (requested: String, done: String)?
    let any: Bool
}

// MARK: - Rules (mirrors lib/groom-request.ts)

enum SvcGroomAsk {
    /// The cut in words: "Puppy cut — round ears", or the free text alone.
    static func cutText(_ style: String?, _ text: String?) -> String? {
        let label = style.flatMap { $0 == "other" ? nil : SvcReportText.style($0) }
        let detail = text?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        // Words that already open with the cut ("Corte cachorro, cara redonda") say it once.
        if let label, let detail, detail.lowercased().hasPrefix(label.lowercased()) { return detail }
        if let label, let detail { return "\(label) — \(detail)" }
        return label ?? detail
    }

    /// "Bath, Haircut · Puppy cut — round ears · #7".
    static func summary(_ wanted: SvcGroomWanted) -> String {
        [(wanted.services ?? []).map { SvcReportText.option($0) }.joined(separator: ", ").nonEmpty,
         cutText(wanted.style, wanted.styleText),
         wanted.length?.nonEmpty].compactMap { $0 }.joined(separator: " · ")
    }

    /// The same comparison the server makes, live while the report is written.
    static func compare(_ wanted: SvcGroomWanted?, _ report: SvcReport) -> SvcGroomDifferences? {
        guard let wanted, report.kind == "groom" else { return nil }
        // A report that says nothing about services, cut or length can't be compared;
        // services left blank are unknown, not "not done".
        let comparable = !report.services.isEmpty || report.styleKind != nil || report.length?.trimmingCharacters(in: .whitespaces).nonEmpty != nil
        if !comparable && report.differenceNote?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty == nil { return nil }
        let asked = wanted.services ?? []
        let notDone = report.services.isEmpty ? [] : asked.filter { !report.services.contains($0) }
        let added = report.services.filter { !asked.contains($0) }
        var style: (requested: String, done: String)?
        if let requested = wanted.style, let done = report.styleKind, requested != done { style = (requested, done) }
        func normal(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespaces).lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        var length: (requested: String, done: String)?
        if let requested = wanted.length?.nonEmpty, let done = report.length?.trimmingCharacters(in: .whitespaces).nonEmpty, normal(requested) != normal(done) {
            length = (requested, done)
        }
        return SvcGroomDifferences(notDone: notDone, added: added, style: style, length: length,
                                   any: !notDone.isEmpty || !added.isEmpty || style != nil || length != nil)
    }

    /// The differences as sentences ("Asked for a shave, did a puppy cut").
    static func lines(_ differences: SvcGroomDifferences) -> [String] {
        var out: [String] = []
        if let style = differences.style {
            out.append(LF("Asked for %@, did %@", SvcReportText.style(style.requested).lowercased(), SvcReportText.style(style.done).lowercased()))
        }
        if let length = differences.length { out.append(LF("Length: asked %@, done %@", length.requested, length.done)) }
        if !differences.notDone.isEmpty { out.append(LF("Not done: %@", differences.notDone.map { SvcReportText.option($0) }.joined(separator: ", "))) }
        if !differences.added.isEmpty { out.append(LF("Also done: %@", differences.added.map { SvcReportText.option($0) }.joined(separator: ", "))) }
        return out
    }

    /// The cut's words in both languages, so a card written in either counts.
    private static let styleWords: [String: [String]] = [
        "puppy": ["Puppy cut", "Corte cachorro"],
        "shave": ["Shave", "Rapado"],
        "breed": ["Breed standard", "Estándar de la raza"],
        "tidy": ["Just a tidy", "Solo emparejar"],
    ]

    /// A cut the care card doesn't already say, worth offering to keep (mirrors the server's `styleIsNewForCard`).
    static func styleIsNewForCard(_ card: String?, style: String?, text: String?) -> Bool {
        let detail = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if style == nil && detail.isEmpty { return false }
        let saved = card?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if saved.isEmpty { return true }
        if !detail.isEmpty && !saved.contains(detail) { return true }
        if let style, style != "other" {
            let words = (styleWords[style] ?? []).map { $0.lowercased() }
            if !words.contains(where: { saved.contains($0) }) { return true }
        }
        return false
    }
}

// MARK: - The pieces the report form shows

/// "Pidieron: …", the request in one line above the groom's fields.
struct SvcGroomAskedLine: View {
    let wanted: SvcGroomWanted

    var body: some View {
        let summary = SvcGroomAsk.summary(wanted)
        if !summary.isEmpty {
            Text(LF("Asked: %@", summary)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
    }
}

/// "Distinto a lo que se pidió" (web: the mango box in the groom's report): the lines, and why (the family reads both).
struct SvcGroomDifferenceBox: View {
    let differences: SvcGroomDifferences
    @Binding var note: String
    let editable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Glyph("shuffle", size: 14)
                Eyebrow(L("Different from what was asked"), size: 12, color: Theme.inkStrong)
            }
            .foregroundStyle(Theme.inkStrong)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SvcGroomAsk.lines(differences), id: \.self) { line in
                    Text(line).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Why is it different?")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                TextField(L("e.g. it was matted, so a puppy cut instead of a shave"), text: $note, axis: .vertical)
                    .lineLimit(2...6)
                    .fieldChrome(multiline: true)
                    .disabled(!editable)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(Theme.mango, 12), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.mango, 60, with: Theme.borderSoft), lineWidth: 2))
    }
}

/// "Guardar como su estilo habitual": the cut done (or, before the report says one, the cut
/// asked for) kept on the care card. Offered only when it's new for the card.
struct SvcUsualStyleOffer: View {
    let view: SvcGroomRequestView
    let report: SvcReport
    /// The report on screen isn't the one saved: "done" reads the saved report, so it is saved first.
    let unsaved: Bool
    let saveFirst: () async -> Bool
    let onSaved: () async -> Void

    @State private var working = false

    private var doneCut: Bool { report.styleKind != nil || report.style?.trimmingCharacters(in: .whitespaces).nonEmpty != nil }
    private var offered: Bool {
        doneCut
            ? (view.styleOffer?.done == true || SvcGroomAsk.styleIsNewForCard(view.careStyle, style: report.styleKind, text: report.style))
            : view.styleOffer?.requested == true
    }

    var body: some View {
        if offered {
            FlowLayout(spacing: 8) {
                Text(L("Keep the cut asked for, or the one done, on the care card for next time."))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                PMButton(L("Save as their usual style"), systemImage: "bookmark-plus", variant: .outline, size: .header, isWorking: working) { keep() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
    }

    private func keep() {
        let from = doneCut ? "done" : "requested"
        working = true
        Task {
            defer { working = false }
            if from == "done" && unsaved {
                guard await saveFirst() else { return }
            }
            do {
                let result: SvcUsualStyleResult = try await API.post("/provider-appointments/\(view.appointmentId)/groom-request/usual-style", body: ["from": from, "language": svcLocale])
                Toast.show(LF("Their usual style is now: %@", result.groomStyle))
                announceDataChanged()
                await onSaved()
            } catch {
                Toast.error(error)
            }
        }
    }
}
