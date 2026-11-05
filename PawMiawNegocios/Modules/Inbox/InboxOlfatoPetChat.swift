//
//  InboxOlfatoPetChat.swift
//  PawMiawNegocios
//
//  The pet way into Olfato AI (web olfato-business/olfato-pet-drawer.tsx):
//  "Preguntar a Olfato" on a pet's chart opens the same chat as the Olfato AI
//  page, about this pet. The notice and the other gates stand first; then a
//  chat not begun ("¿Qué quieres saber de Luna?", the pet's questions, the
//  panel folded into one line), made on the server about the pet (`way: pet`,
//  the provider client pet id) with its first question. This person's earlier
//  chats about the pet are a tap away ("Chats anteriores"), and "Nuevo chat"
//  starts over. Chats are private to whoever asked, for 90 days.
//

import SwiftUI

/// A new Olfato AI chat about one pet, or one of the earlier ones about it. `petId` is the provider client pet id.
struct OlfatoPetChatScreen: View {
    let petId: String

    @EnvironmentObject private var workspace: Workspace
    @StateObject private var viewer = InboxOlfatoViewer()
    @StateObject private var list: InboxOlfatoChatListModel
    /// The open chat; a new one (nil id) until a question makes it.
    @State private var model: InboxOlfatoChatModel
    @State private var petName: String?
    @State private var lookedUp = false
    @State private var showingList = false
    @State private var renaming: InboxOlfatoChat?
    @State private var deleting: InboxOlfatoChat?

    init(petId: String) {
        self.petId = petId
        _list = StateObject(wrappedValue: InboxOlfatoChatListModel(way: "pet", petId: petId))
        _model = State(initialValue: InboxOlfatoChatModel(chatId: nil, petId: petId, petName: nil))
    }

    private var gate: InboxOlfatoGate { viewer.gate }
    private var canEditWorkspace: Bool { workspace.can(.workspaceEdit) }
    private var pet: InboxOlfatoPetRef { InboxOlfatoPetRef(id: petId, name: petName ?? L("this pet")) }
    private var askTitle: String { petName.map { LF("Ask Olfato about %@", $0) } ?? L("Ask Olfato") }

    var body: some View {
        content
            .reloadsOnScope {
                await viewer.load()
                if viewer.gate.readable { await list.load() }
                await findName()
            }
            .navigationDestination(isPresented: $showingList) {
                InboxOlfatoPetChatList(
                    list: list,
                    pet: pet,
                    activeId: model.chatId,
                    canStart: gate == .ready,
                    onOpen: open,
                    onNew: startNew,
                    rename: rename,
                    delete: delete
                )
            }
            .sheet(item: $renaming) { chat in
                InboxRenameChatSheet(title: chat.displayTitle) { title in try await rename(chat, title) }
            }
            .sheet(item: $deleting) { chat in
                InboxDeleteChatSheet(title: chat.displayTitle) { try await delete(chat) }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch gate {
        case .loading:
            PageScroll { LoadingState(text: L("Loading Olfato AI")) }
                .providerPage(askTitle)
        case .notice:
            InboxOlfatoNoticeGate(canConfirm: canEditWorkspace) {
                await viewer.load()
                await list.load()
            }
            .providerPage(askTitle)
        case .privateSession, .error:
            InboxOlfatoGatePage(gate: gate, canEditWorkspace: canEditWorkspace) { await viewer.load() }
                .providerPage(askTitle)
        default:
            if gate != .ready && list.ready && list.chats.isEmpty {
                // Nothing to read and nothing can be asked: why, as the whole page.
                InboxOlfatoGatePage(gate: gate, canEditWorkspace: canEditWorkspace, retry: nil)
                    .providerPage(askTitle)
            } else if !lookedUp {
                PageScroll { LoadingState(text: L("Loading the chat")) }
                    .providerPage(askTitle)
            } else {
                InboxOlfatoPetThreadView(
                    model: model,
                    viewer: viewer,
                    pet: pet,
                    canEditWorkspace: canEditWorkspace,
                    earlier: list.chats.count,
                    moreEarlier: list.hasMore,
                    onList: { showingList = true },
                    onNew: startNew,
                    onRename: { renaming = $0 },
                    onDelete: { deleting = $0 }
                )
            }
        }
    }

    // MARK: The pet's name

    /// From an earlier chat about it, else from its records, visits or client (there is no route for one pet).
    private func findName() async {
        if petName == nil, let named = list.chats.first(where: { $0.petId == petId })?.petName?.nonEmpty {
            petName = named
        }
        if petName == nil && !lookedUp {
            petName = await RecordsPetLookup.find(petId).petName
        }
        lookedUp = true
        model.petName = petName
    }

    // MARK: Moving between chats

    private func open(_ id: String) {
        guard id != model.chatId else { return }
        // Only stops watching: a reply still being written is finished and kept on the server.
        model.leave()
        model = InboxOlfatoChatModel(chatId: id, petId: petId, petName: petName)
    }

    private func startNew() {
        guard model.chat != nil || !model.messages.isEmpty || model.gone else { return }
        model.leave()
        model = InboxOlfatoChatModel(chatId: nil, petId: petId, petName: petName)
    }

    private func rename(_ chat: InboxOlfatoChat, _ title: String) async throws {
        if chat.id == model.chat?.id {
            try await model.rename(title)
            if let renamed = model.chat { list.replace(renamed) }
        } else {
            let envelope: InboxOlfatoChatEnvelope = try await API.patch("/provider-olfato/chats/\(chat.id)", body: ["title": title])
            list.replace(envelope.chat)
        }
    }

    private func delete(_ chat: InboxOlfatoChat) async throws {
        if chat.id == model.chat?.id {
            try await model.delete()
            list.remove(chat.id)
            model = InboxOlfatoChatModel(chatId: nil, petId: petId, petName: petName)
        } else {
            do {
                try await API.send("DELETE", "/provider-olfato/chats/\(chat.id)")
            } catch let error as APIError where error.code == "olfato_chat_not_found" || error.status == 404 {
                // Gone already is what was asked for.
            }
            list.remove(chat.id)
            if chat.id == model.chatId { model = InboxOlfatoChatModel(chatId: nil, petId: petId, petName: petName) }
        }
    }
}

// MARK: - The chat

/// The open chat about the pet: its name and menu above, "Chats anteriores" and "Nuevo chat", then the thread.
private struct InboxOlfatoPetThreadView: View {
    @ObservedObject var model: InboxOlfatoChatModel
    @ObservedObject var viewer: InboxOlfatoViewer
    let pet: InboxOlfatoPetRef
    let canEditWorkspace: Bool
    let earlier: Int
    let moreEarlier: Bool
    let onList: () -> Void
    let onNew: () -> Void
    let onRename: (InboxOlfatoChat) -> Void
    let onDelete: (InboxOlfatoChat) -> Void

    private var title: String { model.chat?.displayTitle ?? model.localTitle ?? LF("Ask Olfato about %@", pet.name) }
    private var begun: Bool { model.chat != nil || !model.messages.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            bar
            if model.gone {
                PageScroll {
                    EmptyState(systemImage: "message-square-warning", title: L("That chat is not here any more."), message: L("Only you can read your chats, for 90 days."), panel: true)
                }
            } else {
                InboxOlfatoThread(model: model, viewer: viewer, canEditWorkspace: canEditWorkspace, pet: pet, compact: true)
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .providerPage(title)
        .task(id: ObjectIdentifier(model)) {
            let panel = viewer
            model.onGateRefusal = { [weak panel] in Task { await panel?.load() } }
            await model.load()
        }
    }

    /// The drawer's header (web olfato-pet-drawer): the corgi, the chat's name, "Only you can read…", its ⋯;
    /// under it "Chats anteriores (3)" and "Nuevo chat" while chats can be read.
    private var bar: some View {
        VStack(spacing: 0) {
            InboxOlfatoChatBar(
                title: title,
                subtitle: L("Only you can read your chats, for 90 days."),
                menu: model.gone ? nil : model.chat.map { chat in (rename: { onRename(chat) }, delete: { onDelete(chat) }) }
            )
            if viewer.gate.readable && (earlier > 0 || begun || model.gone) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if earlier > 0 {
                            PMButton(LF("Earlier chats (%@)", moreEarlier ? "\(earlier)+" : "\(earlier)"), systemImage: "history", variant: .outline, size: .header, action: onList)
                        }
                        if begun || model.gone {
                            // A reply still being written is finished and kept on the server.
                            PMButton(L("New chat"), systemImage: "message-square-plus", variant: .outline, size: .header, action: onNew)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(Theme.surface)
                .overlay(alignment: .bottom) { RowDivider() }
            }
        }
    }
}

// MARK: - The earlier chats about the pet

private struct InboxOlfatoPetChatList: View {
    @ObservedObject var list: InboxOlfatoChatListModel
    let pet: InboxOlfatoPetRef
    let activeId: String?
    let canStart: Bool
    let onOpen: (String) -> Void
    let onNew: () -> Void
    let rename: (InboxOlfatoChat, String) async throws -> Void
    let delete: (InboxOlfatoChat) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var renaming: InboxOlfatoChat?
    @State private var deleting: InboxOlfatoChat?

    var body: some View {
        InboxOlfatoChatListView(
            list: list,
            activeId: activeId,
            showPets: false,
            onOpen: { id in
                onOpen(id)
                dismiss()
            },
            onRename: { renaming = $0 },
            onDelete: { deleting = $0 }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image("OlfatoFace").resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
                    Text(L("Only you can read your chats, for 90 days.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
                if canStart {
                    PMButton(LF("New chat about %@", pet.name), systemImage: "message-square-plus", fullWidth: true) {
                        onNew()
                        dismiss()
                    }
                }
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .providerPage(LF("Earlier chats about %@", pet.name))
        .sheet(item: $renaming) { chat in
            InboxRenameChatSheet(title: chat.displayTitle) { title in try await rename(chat, title) }
        }
        .sheet(item: $deleting) { chat in
            InboxDeleteChatSheet(title: chat.displayTitle) { try await delete(chat) }
        }
    }
}
