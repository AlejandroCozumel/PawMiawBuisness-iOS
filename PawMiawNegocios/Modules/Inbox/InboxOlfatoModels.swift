//
//  InboxOlfatoModels.swift
//  PawMiawNegocios
//
//  Olfato AI's chat for businesses as the server keeps it (paw-miaw-backend
//  docs/olfato-business-chat-plan.md §10, routes/provider-olfato.ts; web
//  components/app/olfato-business/olfato-business-api.ts and
//  hooks/use-olfato-business.ts): the panel of what this person can ask
//  about, the chats, their messages, and a reply as it arrives over
//  server-sent events. The server decides who may ask and what a reply is;
//  nothing here decides anything.
//

import Foundation

// MARK: - The panel (GET /provider-olfato/viewer)

/// A text the server words in both languages.
struct InboxOlfatoWords: Decodable, Hashable {
    let es: String?
    let en: String?

    var text: String {
        LocalizationManager.shared.currentLanguage == .spanish ? (es ?? en ?? "") : (en ?? es ?? "")
    }

    /// In `language`; the other when that one is missing (lib/olfato-business-copy.ts `olfatoWordsIn`).
    func text(in language: InboxOlfatoLanguage) -> String {
        let first = language == .es ? es : en
        let other = language == .es ? en : es
        return first?.nonEmpty ?? other ?? ""
    }
}

// MARK: - The language a reply is written in

/// The language one reply is written in, as the server decides it (paw-miaw-backend
/// lib/olfato-business/chat/language.ts, kept word for word in the web's lib/olfato-business-copy.ts
/// `olfatoReplyLanguage`): the one its question is written in, else the app's. What belongs to the
/// reply (its "Revisando…", lock chips and "Ver en …") follows it, so an English answer ends with
/// "See in Finances" even in the Spanish app; the buttons around it are the app's.
enum InboxOlfatoLanguage: String, Hashable {
    case es, en

    /// The app's language, as the chat names it.
    static var app: InboxOlfatoLanguage { LocalizationManager.shared.currentLanguage == .spanish ? .es : .en }

    private static let spanishWords: Set<String> = Set("qué que cuánto cuánta cuántos cuántas cuanto cuantos como cómo cuál cual cuáles quién quien quiénes quienes dónde donde cuándo cuando el la los las lo de del al y o en es son está están estan hay hubo tiene tienen tenemos tengo tuvimos hoy ayer mañana semana mes año por para con sin una un unos unas mi mis su sus tu tus me te le nos dame dime muestra muéstrame puedes podrías hola gracias cobramos vendimos facturamos vino vinieron debe deben quedó sin pagar cita citas mascota mascotas dueña dueño cliente clientes también sí no".split(separator: " ").map(String.init))
    private static let englishWords: Set<String> = Set("what whats how much many who whom which when where why is are was were did do does done we our us you your i my me this that these those today yesterday tomorrow week month year the a an of for with without in on at to from by bill billed sales sold show give tell list owe owes owed has have had any pet pets client clients visit visits appointment please hi hello thanks yes and or".split(separator: " ").map(String.init))
    private static let letters = Set("abcdefghijklmnopqrstuvwxyzáéíóúüñ")
    private static let spanishMarks = Set("¿¡ñáéíóú")

    /// The language a question is written in; a tie is the app's.
    static func of(question: String, app: InboxOlfatoLanguage = .app) -> InboxOlfatoLanguage {
        let text = question.lowercased()
        var es = text.contains(where: { spanishMarks.contains($0) }) ? 2 : 0
        var en = 0
        var word = ""
        func count() {
            if spanishWords.contains(word) { es += 1 }
            if englishWords.contains(word) { en += 1 }
            word = ""
        }
        for character in text {
            if letters.contains(character) { word.append(character) } else if !word.isEmpty { count() }
        }
        if !word.isEmpty { count() }
        if es == en { return app }
        return es > en ? .es : .en
    }

    /// The reply at `index`: its question's language (the question before it), else — the question is on
    /// an older page not read yet — the reply's own words (olfato-business-thread.tsx `replyLanguageOf`).
    static func ofReply(_ messages: [InboxOlfatoMessage], at index: Int) -> InboxOlfatoLanguage {
        var at = min(index, messages.count) - 1
        while at >= 0 {
            if messages[at].isUser { return of(question: messages[at].content) }
            at -= 1
        }
        return of(question: index < messages.count ? messages[index].content : "")
    }

    private static var tables: [InboxOlfatoLanguage: [String: String]] = [:]

    /// This module's words in this language (then the shared ones), read once.
    private var words: [String: String] {
        if let table = Self.tables[self] { return table }
        var table: [String: String] = [:]
        for name in ["Inbox", "Localizable"] {
            guard let path = Bundle.main.path(forResource: name, ofType: "strings", inDirectory: nil, forLocalization: rawValue),
                  let dict = NSDictionary(contentsOfFile: path) as? [String: String] else { continue }
            table.merge(dict) { kept, _ in kept }
        }
        Self.tables[self] = table
        return table
    }

    /// A sentence of the chat in this language (the key is the English, as with `L`).
    func text(_ key: String) -> String {
        if let value = words[key] { return value }
        // "Open@olfato" → "Open": a key's context is never shown.
        guard let at = key.lastIndex(of: "@"), at != key.startIndex else { return key }
        let context = key[key.index(after: at)...]
        guard !context.isEmpty, context.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return key }
        return String(key[..<at])
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: self == .es ? "es_MX" : "en_US"), arguments: arguments)
    }
}

struct InboxOlfatoArea: Decodable, Identifiable {
    let key: String
    let label: InboxOlfatoWords?
    let open: Bool?
    let offered: Bool?
    let reason: InboxOlfatoWords?
    let notes: [InboxOlfatoWords]?
    var id: String { key }
}

struct InboxOlfatoChatGateStatus: Decodable {
    let available: Bool?
    let workspaceOn: Bool?
    let noticeOutdated: Bool?
    let acknowledged: Bool?
    let canSend: Bool?
    let refusal: String?
    let maxMessageChars: Int?
}

struct InboxOlfatoPanel: Decodable {
    let canChat: Bool?
    let moneyLevel: Int?
    let areas: [InboxOlfatoArea]?
    let scope: [InboxOlfatoWords]?
    let today: String?
    let timeZone: String?
    let chat: InboxOlfatoChatGateStatus?

    var offeredAreas: (open: [InboxOlfatoArea], closed: [InboxOlfatoArea]) {
        let offered = (areas ?? []).filter { $0.offered == true }
        return (offered.filter { $0.open == true }, offered.filter { $0.open != true })
    }
}

/// What stands before the chat (lib/olfato-business-refusals.ts `olfatoChatGate`).
enum InboxOlfatoGate: Equatable {
    case loading, error, unavailable, privateSession, offForYou, notice, off, ready

    static func of(_ chat: InboxOlfatoChatGateStatus?, failed: Bool) -> InboxOlfatoGate {
        guard let chat else { return failed ? .error : .loading }
        switch chat.refusal {
        case "olfato_unavailable": return .unavailable
        case "olfato_private": return .privateSession
        case "olfato_chat_off_for_you": return .offForYou
        case "olfato_notice_required": return .notice
        case "olfato_off": return chat.noticeOutdated == true ? .notice : .off
        default: return chat.canSend == true ? .ready : .unavailable
        }
    }

    /// Earlier chats stay readable; nothing new can be asked.
    var readable: Bool { self == .ready || self == .off || self == .offForYou || self == .unavailable }

    var sentence: String {
        switch self {
        case .notice: InboxOlfatoRefusal.sentence("olfato_notice_required")
        case .error: L("Olfato AI could not be loaded.")
        case .unavailable: InboxOlfatoRefusal.sentence("olfato_unavailable")
        case .privateSession: InboxOlfatoRefusal.sentence("olfato_private")
        case .offForYou: InboxOlfatoRefusal.sentence("olfato_chat_off_for_you")
        case .off: InboxOlfatoRefusal.sentence("olfato_off")
        case .loading, .ready: ""
        }
    }
}

/// Reads the panel; both Olfato AI screens own one.
@MainActor
final class InboxOlfatoViewer: ObservableObject {
    @Published private(set) var panel: InboxOlfatoPanel?
    @Published private(set) var failed = false

    var gate: InboxOlfatoGate { InboxOlfatoGate.of(panel?.chat, failed: failed) }

    /// "Preguntar a Olfato" belongs on a pet's chart (web `useOlfatoChatEntry().shown`): the chat is
    /// available and on for the business. The caller also checks `workspace.can(.olfatoChat)`.
    var showsEntry: Bool { panel?.chat?.available == true && panel?.chat?.workspaceOn == true }

    func load() async {
        do {
            panel = try await API.get("/provider-olfato/viewer")
            failed = false
        } catch is CancellationError {
        } catch {
            failed = panel == nil
        }
    }
}

// MARK: - Chats and messages

struct InboxOlfatoChat: Decodable, Identifiable, Hashable {
    let id: String
    let way: String?
    let petId: String?
    let petName: String?
    let title: String?
    let messageCount: Int?
    let lastMessageAt: String?
    let deleteAfter: String?
    let createdAt: String?
    let updatedAt: String?
    let replying: Bool?

    var sortDate: Date { DateText.parse(lastMessageAt ?? updatedAt) ?? .distantPast }
    var displayTitle: String { title?.nonEmpty ?? L("New chat") }
    /// About a pet that is no longer one this person can open.
    var petGone: Bool { way == "pet" && petId == nil }

    var about: String {
        if way == "pet" {
            return petGone ? L("About a pet you can no longer open") : LF("About %@", petName?.nonEmpty ?? L("a pet"))
        }
        return L("About your business")
    }
}

struct InboxOlfatoChatList: Decodable {
    let chats: [InboxOlfatoChat]?
    let nextCursor: String?
}

struct InboxOlfatoChatEnvelope: Decodable {
    let chat: InboxOlfatoChat
}

struct InboxOlfatoTool: Decodable, Hashable {
    let id: String?
    let name: String?
    let area: String?
    let areaLabel: InboxOlfatoWords?
    let status: String?

    var areaName: String { areaLabel?.text.nonEmpty ?? L("the business") }

    /// The area's name in the reply's language.
    func areaName(in language: InboxOlfatoLanguage) -> String {
        areaLabel?.text(in: language).nonEmpty ?? language.text("the business")
    }
}

/// A screen an answer came from ("Ver en …").
struct InboxOlfatoLink: Decodable, Hashable {
    let to: String?
    let params: [String: String]?
    let search: [String: JSONValue]?
    let label: InboxOlfatoWords?

    /// Only the provider's own screens; `$clientId` filled from the params.
    var route: ProviderRoute? {
        guard var path = to, path.hasPrefix("/provider"), !path.contains("..") else { return nil }
        for (key, value) in params ?? [:] { path = path.replacingOccurrences(of: "$\(key)", with: value) }
        guard !path.contains("$") else { return nil }
        var query: [String: String] = [:]
        for (key, value) in search ?? [:] { if let text = value.string { query[key] = text } }
        return InboxRoutes.route(path: path, query: query)
    }
}

struct InboxOlfatoFeedback: Decodable, Hashable {
    let rating: String?
    let reason: String?
}

struct InboxOlfatoMessageRow: Decodable {
    let id: String
    let seq: Int?
    let role: String?
    let content: String?
    let status: String?
    let errorCode: String?
    let truncated: Bool?
    let clientMessageId: String?
    let tools: [InboxOlfatoTool]?
    let links: [InboxOlfatoLink]?
    let feedback: InboxOlfatoFeedback?
}

struct InboxOlfatoMessagesPage: Decodable {
    let messages: [InboxOlfatoMessageRow]?
    let hasOlder: Bool?
}

/// A message as the thread shows it. What is on screen before the server answered is `local`.
struct InboxOlfatoMessage: Identifiable, Equatable {
    enum Status: String { case thinking, streaming, done, stopped, error }

    var id: String
    var isUser: Bool
    var content: String
    var status: Status = .done
    var errorCode: String?
    var errorData: [String: JSONValue] = [:]
    var truncated = false
    var feedback: InboxOlfatoFeedback?
    var tools: [InboxOlfatoTool] = []
    var links: [InboxOlfatoLink] = []
    var seq: Int?
    var local = false
    var clientMessageId: String?

    init(id: String, isUser: Bool, content: String, status: Status = .done, local: Bool = false, clientMessageId: String? = nil) {
        self.id = id
        self.isUser = isUser
        self.content = content
        self.status = status
        self.local = local
        self.clientMessageId = clientMessageId
    }

    init(_ row: InboxOlfatoMessageRow) {
        id = row.id
        isUser = row.role == "user"
        content = row.content ?? ""
        seq = row.seq
        clientMessageId = row.clientMessageId
        if !isUser {
            switch row.status {
            case "streaming": status = content.isEmpty ? .thinking : .streaming
            case "stopped": status = .stopped
            case "error": status = .error
            default: status = .done
            }
            errorCode = row.status == "error" ? (row.errorCode ?? "internal") : nil
            truncated = row.truncated ?? false
            feedback = row.feedback
            tools = row.tools ?? []
            links = row.links ?? []
        }
    }

    var arriving: Bool { status == .thinking || status == .streaming }
}

// MARK: - Refusals (lib/olfato-business-refusals.ts)

struct InboxOlfatoRefusal: Error {
    let status: Int
    let code: String
    let data: [String: JSONValue]

    static let gateCodes: Set<String> = ["olfato_unavailable", "olfato_private", "olfato_chat_off_for_you", "olfato_off", "olfato_notice_required"]
    static let formCodes: Set<String> = ["olfato_too_long", "olfato_empty"]

    static func network() -> InboxOlfatoRefusal { InboxOlfatoRefusal(status: 0, code: "network", data: [:]) }

    var isGate: Bool { Self.gateCodes.contains(code) }
    var isForm: Bool { Self.formCodes.contains(code) }

    /// From a failed answer's body: `{ error, code, retryAfterSeconds, maxChars… }`.
    static func from(_ body: Data, status: Int, retryAfter: String?) -> InboxOlfatoRefusal {
        var data = (try? API.decoder.decode([String: JSONValue].self, from: body)) ?? [:]
        if !data.keys.contains("retryAfterSeconds"), let wait = retryAfter.flatMap({ Double($0) }), wait > 0 { data["retryAfterSeconds"] = .number(wait) }
        let code = data["code"]?.string ?? (status == 401 ? "unauthorized" : "olfato_failed")
        return InboxOlfatoRefusal(status: status, code: code, data: data)
    }

    static func from(_ error: Error) -> InboxOlfatoRefusal {
        if let refusal = error as? InboxOlfatoRefusal { return refusal }
        if let api = error as? APIError, !api.isOffline {
            return InboxOlfatoRefusal(status: api.status, code: api.code ?? "olfato_failed", data: ["error": .string(api.message)])
        }
        return network()
    }

    /// "en 2 h", "en 15 min".
    static func wait(_ seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        if minutes < 60 { return LF("%d min@wait", minutes) }
        return LF("%d h@wait", Int((Double(minutes) / 60).rounded(.up)))
    }

    /// What the person reads for a refusal or a reply's error code.
    static func sentence(_ code: String?, _ data: [String: JSONValue] = [:]) -> String {
        switch code {
        case "olfato_too_long":
            if let max = data["maxChars"]?.int { return LF("That question is too long. Keep it under %d characters.", max) }
            return L("That question is too long. Shorten it and try again.")
        case "olfato_limit":
            if let wait = data["retryAfterSeconds"]?.double { return LF("You have asked a lot of questions today. Try again in %@.", Self.wait(wait)) }
            return L("You have asked a lot of questions today. Try again later.")
        case "olfato_unavailable", "provider_configuration": return L("Olfato AI is not available right now.")
        case "olfato_private": return L("Olfato AI chats are private and are not available in a support session.")
        case "olfato_chat_off_for_you": return L("Your access doesn’t include Olfato AI. Ask an owner or an admin.")
        case "olfato_off": return L("Olfato AI is turned off for this business.")
        case "olfato_notice_required": return L("Your business has to accept the Olfato AI notice.")
        case "olfato_empty": return L("Write a question first.")
        case "olfato_busy": return L("Olfato AI is still answering. Wait for it to finish.")
        case "olfato_chat_not_found": return L("That chat is not here any more.")
        case "olfato_pet_not_found": return L("That pet is not one you can open.")
        case "olfato_pet_required": return L("Choose the pet this chat is about.")
        case "olfato_nothing_to_answer": return L("There is no question to answer in this chat yet.")
        case "olfato_not_rateable": return L("Only a finished reply can be rated.")
        case "olfato_invalid": return L("That request could not be read.")
        case "network": return L("Not sent. Check your connection and try again.")
        case "provider_unavailable": return L("Olfato AI could not answer right now. Try again in a moment.")
        case "provider_rate_limited": return L("Olfato AI is very busy right now. Try again in a moment.")
        case "refused": return L("I can’t help with that request. Try asking it another way.")
        case "empty_reply": return L("No reply came back. Try again.")
        case "interrupted": return L("The reply was interrupted. Answer again.")
        case "no_access": return L("Your access changed before the answer. Ask again.")
        default: return L("I could not answer. Try again.")
        }
    }

    /// Asking again won't change these.
    static func retryHelps(_ code: String?) -> Bool {
        guard let code else { return true }
        return code != "refused" && code != "olfato_chat_not_found" && code != "olfato_pet_not_found" && !gateCodes.contains(code)
    }
}

// MARK: - A reply as it arrives

/// One server-sent event of a question or "answer again": `start`, any `tool`, `text`, `replace`, then `done` or `error`.
enum InboxOlfatoEvent {
    case start(chat: InboxOlfatoChat?, question: InboxOlfatoMessageRow?, reply: InboxOlfatoMessageRow?)
    case tool(InboxOlfatoTool)
    case text(String)
    case replace(String)
    case done(chat: InboxOlfatoChat?, reply: InboxOlfatoMessageRow?, links: [InboxOlfatoLink]?)
    case error(code: String, reply: InboxOlfatoMessageRow?)
}

private struct InboxStartData: Decodable { let chat: InboxOlfatoChat?; let question: InboxOlfatoMessageRow?; let reply: InboxOlfatoMessageRow? }
private struct InboxTextData: Decodable { let text: String? }
private struct InboxDoneData: Decodable { let chat: InboxOlfatoChat?; let reply: InboxOlfatoMessageRow?; let links: [InboxOlfatoLink]? }
private struct InboxErrorData: Decodable { let code: JSONValue?; let reply: InboxOlfatoMessageRow? }

enum InboxOlfatoStream {
    /// POSTs a question (or "answer again") and calls `onEvent` for each event as it arrives, reading the
    /// response's bytes (`text/event-stream`). Returns when the stream ends; a refusal is thrown as
    /// `InboxOlfatoRefusal`, a dropped connection as its `network` code.
    static func run(_ path: String, body: [String: Any?], onEvent: @MainActor (InboxOlfatoEvent) -> Void) async throws {
        var request = API.request("POST", path)
        request.httpBody = try API.jsonBody(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 120

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await APIConfig.urlSession.bytes(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw InboxOlfatoRefusal.network()
        }
        guard let http = response as? HTTPURLResponse else { throw InboxOlfatoRefusal.network() }
        guard (200..<300).contains(http.statusCode) else {
            var data = Data()
            do { for try await byte in bytes { data.append(byte) } } catch {}
            if http.statusCode == 401 { NotificationCenter.default.post(name: .pawMiawSessionMayHaveExpired, object: nil) }
            throw InboxOlfatoRefusal.from(data, status: http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        }

        var line = Data()
        var name = ""
        var payload = ""
        func flush() {
            defer { name = ""; payload = "" }
            guard !name.isEmpty, let event = decode(name, payload) else { return }
            onEvent(event)
        }
        do {
            for try await byte in bytes {
                if byte == 0x0A {
                    var text = String(decoding: line, as: UTF8.self)
                    if text.hasSuffix("\r") { text.removeLast() }
                    line.removeAll(keepingCapacity: true)
                    if text.isEmpty {
                        flush()
                    } else if text.hasPrefix("event:") {
                        name = String(text.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    } else if text.hasPrefix("data:") {
                        payload += String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    }
                } else {
                    line.append(byte)
                }
            }
            flush()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw InboxOlfatoRefusal.network()
        }
    }

    private static func decode(_ name: String, _ payload: String) -> InboxOlfatoEvent? {
        let data = Data((payload.isEmpty ? "{}" : payload).utf8)
        let decoder = API.decoder
        switch name {
        case "start":
            guard let start = try? decoder.decode(InboxStartData.self, from: data) else { return nil }
            return .start(chat: start.chat, question: start.question, reply: start.reply)
        case "tool":
            guard let tool = try? decoder.decode(InboxOlfatoTool.self, from: data), tool.id != nil, tool.name != nil,
                  ["running", "done", "closed", "failed"].contains(tool.status ?? "") else { return nil }
            return .tool(tool)
        case "text":
            guard let text = try? decoder.decode(InboxTextData.self, from: data).text else { return nil }
            return .text(text)
        case "replace":
            return .replace((try? decoder.decode(InboxTextData.self, from: data).text) ?? "")
        case "done":
            let done = try? decoder.decode(InboxDoneData.self, from: data)
            return .done(chat: done?.chat, reply: done?.reply, links: done?.links)
        case "error":
            let failure = try? decoder.decode(InboxErrorData.self, from: data)
            return .error(code: failure?.code?.string ?? "internal", reply: failure?.reply)
        default:
            return nil
        }
    }
}
