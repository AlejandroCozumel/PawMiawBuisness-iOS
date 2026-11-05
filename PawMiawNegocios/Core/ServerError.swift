//
//  ServerError.swift
//  PawMiawNegocios
//
//  How the app reads what the backend says when a request fails (the family
//  app's decoder, unchanged): `{ error, code, fields }`, a schema refusal
//  `{ success: false, error: { message | issues } }`, or `{ message }`.
//

import Foundation

nonisolated struct ServerErrorBody: Decodable {
    let error: String
    let code: String?
    let fields: [String: String]

    private enum Keys: String, CodingKey { case error, message, code, issues, fields }
    private struct Issue: Decodable { let message: String? }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        code = try? container.decodeIfPresent(String.self, forKey: .code)
        fields = (try? container.decodeIfPresent([String: String].self, forKey: .fields)) ?? [:]

        var text: String?
        if let plain = try? container.decode(String.self, forKey: .error) {
            text = plain
        } else if let nested = try? container.nestedContainer(keyedBy: Keys.self, forKey: .error) {
            if let issues = try? nested.decode([Issue].self, forKey: .issues),
               let first = issues.compactMap(\.message).first {
                text = first
            } else if let raw = try? nested.decode(String.self, forKey: .message) {
                text = Self.firstIssueMessage(in: raw) ?? raw
            }
        }
        if text == nil { text = try? container.decode(String.self, forKey: .message) }

        guard let text, !text.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "No readable error message"))
        }
        error = text == "Unauthorized" || text == "No autorizado." ? "Your session expired. Please sign in again." : text
    }

    private static func firstIssueMessage(in raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let issues = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return issues.compactMap { $0["message"] as? String }.first
    }
}

extension Notification.Name {
    /// An authenticated request was answered 401: the session may have ended.
    static let pawMiawSessionMayHaveExpired = Notification.Name("pawMiawSessionMayHaveExpired")
    /// Something changed that other screens show (a visit booked, a bill paid): reload.
    static let pawMiawDataChanged = Notification.Name("pawMiawDataChanged")
}
