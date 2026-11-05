//
//  ImageUpload.swift
//  PawMiawNegocios
//
//  A picked or taken photo, ready for the server: at most 1600 px on its
//  long side, JPEG, under the server's size limit.
//

import SwiftUI
import PhotosUI
import UIKit

enum ImageUpload {
    /// The server refuses images over 3 MB.
    static let maxBytes = 3 * 1024 * 1024

    static func jpeg(_ image: UIImage, maxSide: CGFloat = 1600, maxBytes: Int = ImageUpload.maxBytes) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        var quality: CGFloat = 0.85
        var out = resized.jpegData(compressionQuality: quality)
        while let current = out, current.count > maxBytes, quality > 0.3 {
            quality -= 0.15
            out = resized.jpegData(compressionQuality: quality)
        }
        return out
    }

    static func jpeg(from data: Data, maxSide: CGFloat = 1600) -> Data? {
        UIImage(data: data).flatMap { jpeg($0, maxSide: maxSide) }
    }

    /// A PhotosPicker item as upload-ready JPEG data.
    static func load(_ item: PhotosPickerItem?) async -> Data? {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return jpeg(from: data)
    }

    /// Sends it as the multipart field the endpoint names (`photo`, `file`, `logo`…).
    static func upload<T: Decodable>(_ data: Data, to path: String, field: String = "photo", method: String = "POST", fields: [String: String] = [:]) async throws -> T {
        try await API.upload(path, method: method, fileField: field, fileName: "\(field).jpg", mimeType: "image/jpeg", fileData: data, fields: fields)
    }
}

/// A photo being chosen in a form: the new one (and its preview), or the saved one removed.
struct PhotoDraft: Equatable {
    var data: Data? = nil
    var preview: UIImage? = nil
    /// The saved photo is to be removed on save.
    var removed = false

    var isEmpty: Bool { data == nil && !removed }
}
