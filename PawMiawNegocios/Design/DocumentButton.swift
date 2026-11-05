//
//  DocumentButton.swift
//  PawMiawNegocios
//
//  A file the server makes (a receipt PDF, a report CSV, a prescription):
//  downloaded with the session, then shown in Quick Look, which shares and
//  prints it. The one way the app opens a server document.
//

import SwiftUI
import QuickLook

struct DocumentButton: View {
    let title: String
    var systemImage: String = "doc.richtext"
    /// The API path (`/provider-store/sales/{id}/pdf`).
    let path: String
    var query: [String: String?] = [:]
    /// The name people see when they share it ("Recibo V-000123").
    let fileName: String
    /// "pdf" or "csv".
    var ext: String = "pdf"
    var variant: ButtonVariant = .outline
    var size: ButtonSize = .compact
    var fullWidth: Bool = false
    /// Runs before the download (a bill makes its PDF first).
    var prepare: (() async throws -> Void)? = nil

    @State private var working = false
    @State private var url: URL?

    var body: some View {
        PMButton(title, systemImage: systemImage, variant: variant, size: size, fullWidth: fullWidth, isWorking: working) { open() }
            .quickLookPreview($url)
    }

    private func open() {
        working = true
        Task {
            defer { working = false }
            do {
                try await prepare?()
                url = try await API.download(path, query: query, fileName: fileName, ext: ext)
            } catch {
                Toast.error(error, fallback: L("The file could not be opened. Try again."))
            }
        }
    }
}
