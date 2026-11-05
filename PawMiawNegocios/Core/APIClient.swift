//
//  APIClient.swift
//  PawMiawNegocios
//
//  Every request to the backend goes through `API`. It signs the request with
//  the session's Bearer token, asks for the app's language, and turns a failed
//  answer into an `APIError` carrying the server's own sentence (and, for a
//  refused form, the sentence for each field).
//
//  Usage:
//      let page: Page<Client> = try await API.get("/provider-clients", query: ["limit": "20", "offset": "0"])
//      let saved: Client = try await API.post("/provider-clients", body: ["name": name, "phone": nil])
//      let saved: Client = try await API.post("/provider-clients", json: someEncodable)
//      try await API.send("DELETE", "/provider-clients/\(id)")
//
//  Bodies given as `[String: Any?]` drop nothing: a nil value is sent as JSON
//  null, which is how the backend clears a field. Leave the key out to keep it.
//

import Foundation

struct APIError: LocalizedError, Equatable {
    let status: Int
    let message: String
    let code: String?
    /// The server's sentence for each refused field, under the request's own name for it.
    let fields: [String: String]
    /// The whole refusal as the server sent it, for what some screens read beyond the
    /// sentence (a visit's conflicts, the hours problem, a fee to decide, places left).
    var body: JSONValue? = nil

    var errorDescription: String? { message }

    /// The request never reached the server (offline, timed out).
    var isOffline: Bool { status == 0 }
    /// Refused by the server (4xx): retrying the same request cannot work.
    var isRefusal: Bool { (400..<500).contains(status) }

    static func offline() -> APIError {
        APIError(status: 0, message: L("You're offline. Check your connection and try again."), code: "offline", fields: [:])
    }

    /// The sentence for one field of a refused form.
    func field(_ names: String...) -> String? {
        for name in names { if let text = fields[name], !text.isEmpty { return text } }
        return nil
    }
}

/// What a screen shows after a failed action: the server's sentence when it
/// refused the request, else the screen's own fallback.
func errorText(_ error: Error, fallback: String = L("Something went wrong. Try again.")) -> String {
    if let api = error as? APIError {
        if api.isOffline { return api.message }
        if !api.message.isEmpty { return api.message }
    }
    return fallback
}

struct EmptyResponse: Decodable {}

/// Any JSON value, for answers whose shape a screen only reads in part.
enum JSONValue: Codable, Hashable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    subscript(key: String) -> JSONValue? { if case .object(let o) = self { return o[key] }; return nil }
    var string: String? { if case .string(let v) = self { return v }; if case .number(let n) = self { return n.formatted() }; return nil }
    var double: Double? { if case .number(let v) = self { return v }; if case .string(let s) = self { return Double(s) }; return nil }
    var int: Int? { double.map { Int($0) } }
    var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    var array: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    var object: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    var isNull: Bool { if case .null = self { return true }; return false }
}

enum API {
    static let decoder: JSONDecoder = JSONDecoder()
    static let encoder: JSONEncoder = JSONEncoder()

    // MARK: Decoding calls

    static func get<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        try decode(try await data("GET", path, query: query, body: nil))
    }

    static func post<T: Decodable>(_ path: String, body: [String: Any?] = [:], query: [String: String?] = [:]) async throws -> T {
        try decode(try await data("POST", path, query: query, body: try jsonBody(body)))
    }

    static func post<T: Decodable, B: Encodable>(_ path: String, json: B, query: [String: String?] = [:]) async throws -> T {
        try decode(try await data("POST", path, query: query, body: try encoder.encode(json)))
    }

    static func put<T: Decodable>(_ path: String, body: [String: Any?] = [:]) async throws -> T {
        try decode(try await data("PUT", path, query: [:], body: try jsonBody(body)))
    }

    static func put<T: Decodable, B: Encodable>(_ path: String, json: B) async throws -> T {
        try decode(try await data("PUT", path, query: [:], body: try encoder.encode(json)))
    }

    static func patch<T: Decodable>(_ path: String, body: [String: Any?] = [:]) async throws -> T {
        try decode(try await data("PATCH", path, query: [:], body: try jsonBody(body)))
    }

    static func patch<T: Decodable, B: Encodable>(_ path: String, json: B) async throws -> T {
        try decode(try await data("PATCH", path, query: [:], body: try encoder.encode(json)))
    }

    static func delete<T: Decodable>(_ path: String, body: [String: Any?]? = nil, query: [String: String?] = [:]) async throws -> T {
        try decode(try await data("DELETE", path, query: query, body: try body.map(jsonBody)))
    }

    /// A request whose answer the caller does not read.
    static func send(_ method: String, _ path: String, body: [String: Any?]? = nil, query: [String: String?] = [:]) async throws {
        _ = try await data(method, path, query: query, body: try body.map(jsonBody))
    }

    /// A multipart upload (a photo, a document). `fields` go as plain text parts.
    static func upload<T: Decodable>(_ path: String, method: String = "POST", fileField: String = "file", fileName: String, mimeType: String, fileData: Data, fields: [String: String] = [:]) async throws -> T {
        let boundary = "PawMiaw-\(UUID().uuidString)"
        var body = Data()
        func line(_ s: String) { body.append(s.data(using: .utf8)!) }
        for (key, value) in fields {
            line("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")
        }
        line("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        line("\r\n--\(boundary)--\r\n")
        return try decode(try await data(method, path, query: [:], body: body, contentType: "multipart/form-data; boundary=\(boundary)"))
    }

    /// One file of a multipart request.
    struct UploadFile {
        var field: String
        var fileName: String
        var mimeType: String
        var data: Data
    }

    /// A multipart request with text fields and any number of files (photos of an
    /// incident, a signature with its scan). Fields go first, in order.
    static func multipart<T: Decodable>(_ path: String, method: String = "POST", fields: [(String, String)] = [], files: [UploadFile]) async throws -> T {
        let boundary = "PawMiaw-\(UUID().uuidString)"
        var body = Data()
        func line(_ s: String) { body.append(s.data(using: .utf8)!) }
        for (key, value) in fields {
            line("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")
        }
        for file in files {
            line("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(file.fileName)\"\r\nContent-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            line("\r\n")
        }
        line("--\(boundary)--\r\n")
        return try decode(try await data(method, path, query: [:], body: body, contentType: "multipart/form-data; boundary=\(boundary)"))
    }

    // MARK: Plumbing

    static func url(_ path: String, query: [String: String?] = [:]) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var components = URLComponents(url: APIConfig.baseURL.appendingPathComponent(""), resolvingAgainstBaseURL: false)!
        let parts = trimmed.split(separator: "?", maxSplits: 1).map(String.init)
        components.path = APIConfig.baseURL.path + "/" + parts[0]
        var items: [URLQueryItem] = []
        if parts.count > 1 { items += URLComponents(string: "?" + parts[1])?.queryItems ?? [] }
        for (key, value) in query.sorted(by: { $0.key < $1.key }) {
            if let value { items.append(URLQueryItem(name: key, value: value)) }
        }
        components.queryItems = items.isEmpty ? nil : items
        return components.url!
    }

    static func request(_ method: String, _ path: String, query: [String: String?] = [:]) -> URLRequest {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let language = LocalizationManager.shared.currentLanguage.rawValue
        request.setValue(language, forHTTPHeaderField: "Accept-Language")
        request.setValue(language, forHTTPHeaderField: "X-Preferred-Language")
        if let token = SessionToken.current {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            #if DEBUG
            // A design-review session must not be overridden by the stored sign-in's cookie.
            if ProcessInfo.processInfo.environment["PAWMIAW_DEBUG_SESSION_TOKEN"]?.isEmpty == false { request.httpShouldHandleCookies = false }
            #endif
        }
        return request
    }

    @discardableResult
    static func data(_ method: String, _ path: String, query: [String: String?], body: Data?, contentType: String = "application/json") async throws -> Data {
        var request = request(method, path, query: query)
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await APIConfig.urlSession.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw APIError.offline()
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.offline() }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401, SessionToken.current != nil {
                NotificationCenter.default.post(name: .pawMiawSessionMayHaveExpired, object: nil)
            }
            throw errorFrom(data: data, status: http.statusCode)
        }
        return data
    }

    static func decode<T: Decodable>(_ data: Data) throws -> T {
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        do {
            return try decoder.decode(T.self, from: data.isEmpty ? Data("{}".utf8) : data)
        } catch {
            #if DEBUG
            print("[API] decode \(T.self) failed: \(error)")
            #endif
            throw APIError(status: 200, message: L("The server's answer could not be read. Update the app or try again."), code: "decode_failed", fields: [:])
        }
    }

    static func jsonBody(_ body: [String: Any?]) throws -> Data {
        try JSONSerialization.data(withJSONObject: sanitize(body))
    }

    private static func sanitize(_ value: Any?) -> Any {
        switch value {
        case nil: return NSNull()
        case let dict as [String: Any?]: return dict.mapValues { sanitize($0) }
        case let dict as [String: Any]: return dict.mapValues { sanitize($0) }
        case let array as [Any?]: return array.map { sanitize($0) }
        case let array as [Any]: return array.map { sanitize($0) }
        case let date as Date: return ISO8601DateFormatter().string(from: date)
        case let decimal as Decimal: return NSDecimalNumber(decimal: decimal)
        case let some?:
            if case Optional<Any>.none = some as Any? { return NSNull() }
            return some
        }
    }

    static func errorFrom(data: Data, status: Int) -> APIError {
        let raw = try? decoder.decode(JSONValue.self, from: data)
        if let body = try? decoder.decode(ServerErrorBody.self, from: data) {
            return APIError(status: status, message: body.error, code: body.code, fields: body.fields, body: raw)
        }
        let fallback: String
        switch status {
        case 401: fallback = L("Your session expired. Please sign in again.")
        case 403: fallback = L("Your role can't do this. Ask the owner of the business.")
        case 404: fallback = L("This was not found. It may have been removed.")
        case 429: fallback = L("Too many tries. Wait a moment and try again.")
        default: fallback = L("Something went wrong. Try again.")
        }
        return APIError(status: status, message: fallback, code: nil, fields: [:], body: raw)
    }

    /// Downloads a file the server makes (a PDF, a CSV) with the session, into a
    /// temporary file named for people ("Recibo V-000123.pdf"), for Quick Look or sharing.
    static func download(_ path: String, query: [String: String?] = [:], fileName: String, ext: String = "pdf") async throws -> URL {
        let trimmed = path.hasPrefix("/api/") ? String(path.dropFirst(4)) : path
        let data = try await data("GET", trimmed, query: query, body: nil)
        let safe = fileName.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-").nonEmpty ?? "PawMiaw"
        let name = safe.lowercased().hasSuffix(".\(ext)") ? safe : "\(safe).\(ext)"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name)
        try data.write(to: file, options: .atomic)
        return file
    }
}

/// A page of a list the server pages (`limit` + `offset`), in the shapes the
/// provider endpoints answer with: `{ items|data|rows|…, total }`.
struct Page<T: Decodable>: Decodable {
    let items: [T]
    let total: Int?
    let hasMore: Bool?

    private struct AnyKey: CodingKey {
        var stringValue: String; var intValue: Int?
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    /// Keys a page's rows come under, tried in order.
    static var itemKeys: [String] {
        ["items", "data", "rows", "results", "clients", "appointments", "records", "invoices", "sales", "products", "patients", "pets", "stays", "notifications", "followUps", "members", "entries", "chats", "messages"]
    }

    init(items: [T], total: Int?, hasMore: Bool? = nil) {
        self.items = items; self.total = total; self.hasMore = hasMore
    }

    init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([T].self) {
            items = array; total = array.count; hasMore = false
            return
        }
        let c = try decoder.container(keyedBy: AnyKey.self)
        var found: [T]?
        for key in Self.itemKeys {
            let k = AnyKey(stringValue: key)
            if c.contains(k), let rows = try? c.decode([T].self, forKey: k) { found = rows; break }
        }
        guard let found else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "No page rows"))
        }
        items = found
        total = (try? c.decodeIfPresent(Int.self, forKey: AnyKey(stringValue: "total")))
            ?? (try? c.decodeIfPresent(Int.self, forKey: AnyKey(stringValue: "count")))
        hasMore = try? c.decodeIfPresent(Bool.self, forKey: AnyKey(stringValue: "hasMore"))
    }
}
