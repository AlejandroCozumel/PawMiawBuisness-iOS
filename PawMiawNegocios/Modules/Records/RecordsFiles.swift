//
//  RecordsFiles.swift
//  PawMiawNegocios
//
//  A record's photos and documents (web records-page/record-detail.tsx
//  AttachmentsCard). Files are read through the API with the session — the
//  download address needs it — then a photo shows as its thumbnail and any
//  file opens in Quick Look.
//

import SwiftUI
import UIKit

@MainActor
final class RecordsFileStore {
    static let shared = RecordsFileStore()
    private let images = NSCache<NSString, UIImage>()

    /// A photo's image, kept while the app runs.
    func image(for url: String) async -> UIImage? {
        if let hit = images.object(forKey: url as NSString) { return hit }
        guard let data = try? await RecordsAPI.fileData(url), let image = UIImage(data: data) else { return nil }
        images.setObject(image, forKey: url as NSString)
        return image
    }

    /// The file on this device (the app's own temporary folder, protected), for Quick Look.
    func localFile(_ attachment: RecordsAttachment) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("records-files", isDirectory: true)
            .appendingPathComponent(attachment.id, isDirectory: true)
        let file = folder.appendingPathComponent(Self.safeName(attachment))
        if FileManager.default.fileExists(atPath: file.path) { return file }
        let data = try await RecordsAPI.fileData(attachment.url)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        return file
    }

    private static func safeName(_ attachment: RecordsAttachment) -> String {
        var name = attachment.fileName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = "file" }
        if !name.contains(".") {
            switch attachment.mimeType?.lowercased() {
            case "application/pdf": name += ".pdf"
            case "image/png": name += ".png"
            case "image/heic": name += ".heic"
            case "image/webp": name += ".webp"
            case "image/gif": name += ".gif"
            case let mime? where mime.hasPrefix("image/"): name += ".jpg"
            default: break
            }
        }
        return name
    }
}

/// A photo read with the session; a placeholder while it loads.
struct RecordsAuthImage: View {
    let url: String
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Theme.surfaceMuted
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                Glyph("image", size: 22).foregroundStyle(Theme.inkSoft)
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            image = await RecordsFileStore.shared.image(for: url)
            failed = image == nil
        }
    }
}

