//
//  InboxOlfatoChatModel.swift
//  PawMiawNegocios
//
//  One Olfato AI chat as the server keeps it (web
//  olfato-business/use-olfato-business-chat.ts): reading it, asking, the
//  tools a reply runs, stopping, answering again, rating, renaming and
//  deleting. Nothing is kept on the device: what is on screen before the
//  server answered (a question just sent, a reply on its way) is `local`
//  and gives way to the server's rows as they arrive. Leaving the screen
//  only stops watching: the reply is finished and kept on the server.
//

import Foundation

struct InboxFormRefusal: Equatable {
    let sentence: String
    let question: String
}

private struct InboxStopAnswer: Decodable {
    let stopped: Bool?
    let reply: InboxOlfatoMessageRow?
}

@MainActor
final class InboxOlfatoChatModel: ObservableObject {
    @Published private(set) var chat: InboxOlfatoChat?
    @Published private(set) var messages: [InboxOlfatoMessage] = []
    @Published private(set) var loaded = false
    @Published private(set) var hasOlder = false
    @Published private(set) var loadingOlder = false
    /// A reply this device is following.
    @Published private(set) var live = false
    /// The chat asked for is not there (deleted, or someone else's).
    @Published private(set) var gone = false
    /// The last question refused for what was typed: the box takes it back and says why.
    @Published var formRefusal: InboxFormRefusal?
    /// A title for a chat not made on the server yet.
    @Published private(set) var localTitle: String?

    /// A refusal about who may ask (the notice, the switch, the access): the panel is read again.
    var onGateRefusal: (() -> Void)?

    private let requestedId: String?
    /// A chat about this pet (the provider client pet id), from its chart: a new chat is made about it.
    let petId: String?
    /// The pet's name, for a chat not made on the server yet.
    var petName: String?
    private var newId: String?
    private var task: Task<Void, Never>?
    private var runToken = UUID()
    private var started = false
    private var stopWanted = false
    private var pollTask: Task<Void, Never>?
    private var olderLoaded = false

    convenience init(chatId: String?) {
        self.init(chatId: chatId, petId: nil, petName: nil)
    }

    init(chatId: String?, petId: String?, petName: String?) {
        requestedId = chatId
        self.petId = petId?.nonEmpty
        self.petName = petName
    }

    var chatId: String? { chat?.id ?? requestedId }
    var language: String { LocalizationManager.shared.currentLanguage.rawValue }
    var arrivingElsewhere: Bool { !live && messages.contains { !$0.local && $0.arriving } }
    /// A reply is on its way in this chat: nothing else can be asked in it.
    var busy: Bool { live || arrivingElsewhere }
    var fresh: Bool { loaded && messages.isEmpty }
    var title: String { chat?.displayTitle ?? localTitle ?? "Olfato AI" }

    private func path(_ id: String, _ rest: String = "") -> String {
        "/provider-olfato/chats/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)\(rest)"
    }

    // MARK: Reading

    func load() async {
        guard let id = requestedId, chat == nil || !live else {
            loaded = true
            return
        }
        do {
            let envelope: InboxOlfatoChatEnvelope = try await API.get(path(id))
            chat = envelope.chat
            gone = false
        } catch is CancellationError {
            return
        } catch {
            let refusal = InboxOlfatoRefusal.from(error)
            if refusal.code == "olfato_chat_not_found" || refusal.status == 404 { gone = true }
            note(refusal)
        }
        await loadMessages()
    }

    func loadMessages() async {
        guard let id = chatId, !gone else {
            loaded = true
            return
        }
        do {
            let page: InboxOlfatoMessagesPage = try await API.get(path(id, "/messages"))
            let rows = (page.messages ?? []).map(InboxOlfatoMessage.init)
            messages = merge(rows)
            if !olderLoaded { hasOlder = page.hasOlder ?? false }
        } catch is CancellationError {
            return
        } catch {
            note(InboxOlfatoRefusal.from(error))
        }
        loaded = true
        updatePolling()
    }

    /// A page read from the server laid over what is on screen.
    private func merge(_ page: [InboxOlfatoMessage]) -> [InboxOlfatoMessage] {
        let lowest = page.compactMap(\.seq).min() ?? Int.max
        let older = messages.filter { ($0.seq ?? Int.max) < lowest && !$0.local }
        let known = Set(page.compactMap(\.clientMessageId))
        var local: [InboxOlfatoMessage] = []
        var dropNextReply = false
        for message in messages where message.local {
            if message.isUser {
                dropNextReply = message.clientMessageId.map { known.contains($0) } ?? false
                if !dropNextReply { local.append(message) }
            } else if !dropNextReply {
                local.append(message)
            }
        }
        return older + page + local
    }

    func loadOlder() async {
        guard let id = chatId, !loadingOlder, let lowest = messages.compactMap(\.seq).min() else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page: InboxOlfatoMessagesPage = try await API.get(path(id, "/messages"), query: ["before": "\(lowest)"])
            messages = (page.messages ?? []).map(InboxOlfatoMessage.init) + messages
            hasOlder = page.hasOlder ?? false
            olderLoaded = true
        } catch {
            note(InboxOlfatoRefusal.from(error))
        }
    }

    /// A reply being written elsewhere (another device, or here before the screen was opened) is read again until it ends.
    private func updatePolling() {
        if arrivingElsewhere {
            guard pollTask == nil else { return }
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(1500))
                    guard let self, !Task.isCancelled else { return }
                    await self.loadMessages()
                    if !self.arrivingElsewhere { break }
                }
                self?.pollTask = nil
            }
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    func leave() {
        // Leaving only stops watching: the reply is finished and kept on the server.
        task?.cancel()
        pollTask?.cancel()
        pollTask = nil
    }

    private func note(_ refusal: InboxOlfatoRefusal) {
        if refusal.code == "olfato_chat_not_found" { gone = true }
        if refusal.isGate { onGateRefusal?() }
    }

    // MARK: Writing in place

    private func patch(_ id: String, _ change: (inout InboxOlfatoMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }

    private func markStopped(_ replyId: String) {
        patch(replyId) { message in
            message.status = .stopped
            message.errorCode = nil
            message.tools = message.tools.filter { $0.status != "running" }
        }
    }

    private func markFailed(_ replyId: String, _ refusal: InboxOlfatoRefusal) {
        patch(replyId) { message in
            message.status = .error
            message.errorCode = refusal.code
            message.errorData = refusal.data
            message.tools = message.tools.filter { $0.status != "running" }
        }
    }

    // MARK: Asking

    private func begin(_ work: @escaping (UUID) async -> Void) {
        task?.cancel()
        let token = UUID()
        runToken = token
        live = true
        started = false
        stopWanted = false
        updatePolling()
        task = Task { await work(token) }
    }

    private func end(_ token: UUID) {
        guard runToken == token else { return }
        live = false
        task = nil
        started = false
        stopWanted = false
        updatePolling()
    }

    /// Sends a question; false when nothing was sent (empty, or a reply is on its way).
    @discardableResult
    func ask(_ text: String) -> Bool {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !busy, !gone else { return false }
        let clientMessageId = UUID().uuidString.lowercased()
        let question = InboxOlfatoMessage(id: clientMessageId, isUser: true, content: content, local: true, clientMessageId: clientMessageId)
        let replyId = "reply-\(clientMessageId)"
        let reply = InboxOlfatoMessage(id: replyId, isUser: false, content: "", status: .thinking, local: true)
        let exists = chat != nil
        let id: String
        if let current = chatId, exists || requestedId != nil {
            id = current
        } else {
            id = newId ?? UUID().uuidString.lowercased()
            newId = id
            let line = content.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            localTitle = line.count > 44 ? String(line.prefix(44)) + "…" : line
        }
        messages += [question, reply]
        loaded = true
        begin { [weak self] token in
            await self?.send(chatId: id, exists: exists, question: question, replyId: replyId, token: token)
        }
        return true
    }

    private func send(chatId id: String, exists: Bool, question: InboxOlfatoMessage, replyId: String, token: UUID) async {
        if !exists {
            do {
                // About the pet when it came from a chart; the pet is left out of a business chat, never null.
                var body: [String: Any?] = ["id": id, "way": petId == nil ? "business" : "pet"]
                if let petId { body["providerClientPetId"] = petId }
                let envelope: InboxOlfatoChatEnvelope = try await API.post("/provider-olfato/chats", body: body)
                chat = envelope.chat
                announceDataChanged()
            } catch is CancellationError {
                end(token)
                return
            } catch {
                let refusal = InboxOlfatoRefusal.from(error)
                markFailed(replyId, refusal)
                note(refusal)
                end(token)
                return
            }
            // Stopped (or let go) while the chat was being made: nothing was asked.
            if stopWanted || Task.isCancelled {
                markStopped(replyId)
                end(token)
                return
            }
        }
        await follow(
            path: path(id, "/messages"),
            body: ["clientMessageId": question.clientMessageId ?? question.id, "content": question.content, "language": language],
            question: question,
            replyId: replyId,
            resend: true,
            token: token
        )
    }

    private func follow(path: String, body: [String: Any?], question: InboxOlfatoMessage?, replyId shownReplyId: String, resend: Bool, token: UUID) async {
        var replyId = shownReplyId
        var started = false
        var finished = false
        var failure: InboxOlfatoRefusal?

        for attempt in 0..<(resend ? 2 : 1) {
            failure = nil
            do {
                try await InboxOlfatoStream.run(path, body: body) { event in
                    switch event {
                    case .start(let chat, let questionRow, let replyRow):
                        started = true
                        self.started = true
                        if let chat { self.chat = chat }
                        guard let replyRow else { return }
                        let serverQuestion: InboxOlfatoMessage? = questionRow != nil ? InboxOlfatoMessage(questionRow!) : nil
                        var serverReply = InboxOlfatoMessage(replyRow)
                        serverReply.status = .thinking
                        serverReply.tools = []
                        serverReply.links = []
                        let fromId = replyId
                        replyId = serverReply.id
                        // The server's rows take the place of what stood for them; a reply answered again leaves.
                        self.messages.removeAll { message in
                            message.id == fromId || message.id == question?.id || message.id == serverQuestion?.id || message.id == serverReply.id
                                || (!message.isUser && message.seq != nil && (message.seq ?? 0) >= (serverReply.seq ?? Int.max))
                        }
                        self.messages.removeAll { $0.local }
                        if let serverQuestion { self.messages.append(serverQuestion) }
                        self.messages.append(serverReply)
                        self.loaded = true
                        // Stop was pressed before the server named the reply: it is stopped now.
                        if self.stopWanted { Task { await self.stop() } }
                    case .tool(let tool):
                        self.patch(replyId) { message in
                            if let index = message.tools.firstIndex(where: { $0.id == tool.id }) { message.tools[index] = tool } else { message.tools.append(tool) }
                        }
                    case .text(let text):
                        self.patch(replyId) { message in
                            message.content += text
                            message.status = .streaming
                        }
                    case .replace(let text):
                        self.patch(replyId) { message in
                            message.content = text
                            message.status = text.isEmpty ? .thinking : .streaming
                        }
                    case .done(let chat, let replyRow, let links):
                        finished = true
                        if let chat { self.chat = chat }
                        if let replyRow {
                            var reply = InboxOlfatoMessage(replyRow)
                            if let links, !links.isEmpty { reply.links = links }
                            self.patch(replyId) { $0 = reply }
                        } else {
                            self.patch(replyId) { $0.status = .done }
                        }
                    case .error(let code, let replyRow):
                        finished = true
                        if let replyRow {
                            let reply = InboxOlfatoMessage(replyRow)
                            self.patch(replyId) { message in
                                let toolsSoFar = message.tools.filter { $0.status != "running" }
                                message = reply
                                if message.tools.isEmpty { message.tools = toolsSoFar }
                                message.status = reply.status == .stopped ? .stopped : .error
                                message.errorCode = reply.status == .stopped ? nil : code
                            }
                        } else {
                            // Not kept (the writer crashed, the save failed, or the chat was deleted meanwhile).
                            self.markFailed(replyId, InboxOlfatoRefusal(status: 200, code: code, data: [:]))
                        }
                    }
                }
            } catch is CancellationError {
                end(token)
                return
            } catch {
                failure = InboxOlfatoRefusal.from(error)
            }
            if finished || Task.isCancelled { break }
            // A refusal is an answer: asking again would get the same one.
            if let failure, failure.code != "network" { break }
            if attempt == 0 && resend { try? await Task.sleep(for: .milliseconds(600)) }
        }

        if Task.isCancelled {
            end(token)
            return
        }
        if !finished {
            if let failure, failure.code != "network" {
                if !started && failure.isForm, let question {
                    // Nothing was kept: the question goes back into the box, and the box says why.
                    messages.removeAll { $0.id == question.id || $0.id == replyId }
                    if chat == nil { localTitle = nil }
                    formRefusal = InboxFormRefusal(sentence: InboxOlfatoRefusal.sentence(failure.code, failure.data), question: question.content)
                } else if stopWanted && !started {
                    markStopped(replyId)
                } else {
                    markFailed(replyId, failure)
                }
                note(failure)
            } else if started {
                // The connection dropped; the reply may still be finishing.
                await loadMessages()
            } else if stopWanted {
                markStopped(replyId)
            } else {
                markFailed(replyId, .network())
            }
        }
        end(token)
        announceDataChanged()
    }

    /// Answers the last question again, in place of the reply it got.
    func retry() {
        guard !busy, let last = messages.last, !last.isUser else { return }
        let question = messages.last(where: { $0.isUser })
        // A question that never reached the server is sent again as itself.
        if last.local, let question, question.local, let id = chatId ?? newId {
            patch(last.id) { message in
                message.status = .thinking
                message.errorCode = nil
                message.errorData = [:]
                message.content = ""
                message.tools = []
            }
            let exists = chat != nil
            let replyId = last.id
            begin { [weak self] token in
                await self?.send(chatId: id, exists: exists, question: question, replyId: replyId, token: token)
            }
            return
        }
        guard let id = chat?.id else { return }
        let replyId = "reply-\(UUID().uuidString.lowercased())"
        messages.removeAll { $0.id == last.id }
        messages.append(InboxOlfatoMessage(id: replyId, isUser: false, content: "", status: .thinking, local: true))
        let regenerate = path(id, "/regenerate")
        let language = language
        begin { [weak self] token in
            await self?.follow(path: regenerate, body: ["language": language], question: nil, replyId: replyId, resend: false, token: token)
        }
    }

    /// Stops the reply.
    func stop() async {
        guard let id = chat?.id, !(live && !started) else {
            // The server hasn't named the reply yet: it is stopped the moment it is.
            if live { stopWanted = true }
            return
        }
        do {
            let answer: InboxStopAnswer = try await API.post(path(id, "/stop"))
            if live {
                task?.cancel()
                end(runToken)
            }
            if let reply = answer.reply {
                messages.removeAll { ($0.local && !$0.isUser) || $0.id == reply.id }
                messages.append(InboxOlfatoMessage(reply))
            }
            await loadMessages()
        } catch {
            note(InboxOlfatoRefusal.from(error))
        }
    }

    // MARK: Rating, renaming, deleting

    func rate(_ messageId: String, rating: String?, reason: String?) async throws {
        guard let id = chatId else { return }
        let before = messages.first { $0.id == messageId }?.feedback
        patch(messageId) { $0.feedback = rating.map { InboxOlfatoFeedback(rating: $0, reason: reason) } }
        let endpoint = path(id, "/messages/\(messageId)/feedback")
        do {
            if let rating {
                // The reason is left out, never null, for a thumbs up.
                var body: [String: Any?] = ["rating": rating]
                if let reason { body["reason"] = reason }
                try await API.send("PUT", endpoint, body: body)
            } else {
                try await API.send("DELETE", endpoint)
            }
        } catch {
            patch(messageId) { $0.feedback = before }
            throw error
        }
    }

    func rename(_ title: String) async throws {
        guard let id = chat?.id else { return }
        let envelope: InboxOlfatoChatEnvelope = try await API.patch(path(id), body: ["title": title])
        chat = envelope.chat
        announceDataChanged()
    }

    func delete() async throws {
        guard let id = chat?.id else { return }
        do {
            try await API.send("DELETE", path(id))
        } catch let error as APIError where error.code == "olfato_chat_not_found" || error.status == 404 {
            // Gone already is what was asked for.
        }
        leave()
        gone = true
        announceDataChanged()
    }
}
