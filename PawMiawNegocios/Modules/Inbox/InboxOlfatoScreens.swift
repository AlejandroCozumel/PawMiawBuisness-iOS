//
//  InboxOlfatoScreens.swift
//  PawMiawNegocios
//
//  Olfato AI for businesses (web routes/provider.olfato*.tsx,
//  olfato-business-page.tsx, -gates.tsx, olfato-chat-list.tsx,
//  olfato-chat-dialogs.tsx): the person's chats, newest first by day, 20 at
//  a time; a chat; a new chat. The notice is the whole page until someone
//  who edits the workspace confirms it; a support session, the person's
//  access, the switch and the server each say why nothing can be asked,
//  and earlier chats stay readable then. Chats are private to whoever asked.
//

import SwiftUI

// MARK: - The chats

@MainActor
final class InboxOlfatoChatListModel: ObservableObject {
    @Published private(set) var chats: [InboxOlfatoChat] = []
    @Published private(set) var ready = false
    @Published private(set) var failed = false
    @Published private(set) var loadingMore = false
    private var cursor: String?
    /// One way in ("business" or "pet") and one pet's chats; nil lists every chat of the person.
    private let way: String?
    private let petId: String?
    var hasMore: Bool { cursor != nil }

    init(way: String? = nil, petId: String? = nil) {
        self.way = way
        self.petId = petId
    }

    private func query(_ cursor: String? = nil) -> [String: String?] {
        ["limit": "20", "way": way, "petId": petId, "cursor": cursor]
    }

    func load() async {
        do {
            let page: InboxOlfatoChatList = try await API.get("/provider-olfato/chats", query: query())
            let fresh = page.chats ?? []
            let freshIds = Set(fresh.map(\.id))
            let oldest = fresh.last?.sortDate ?? .distantFuture
            // The newest page, then older ones already shown.
            chats = fresh + chats.filter { !freshIds.contains($0.id) && $0.sortDate <= oldest }
            if cursor == nil || chats.count <= fresh.count { cursor = page.nextCursor }
            failed = false
        } catch is CancellationError {
            return
        } catch {
            failed = true
        }
        ready = true
    }

    func loadMore() async {
        guard let cursor, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page: InboxOlfatoChatList = try await API.get("/provider-olfato/chats", query: query(cursor))
            let known = Set(chats.map(\.id))
            chats += (page.chats ?? []).filter { !known.contains($0.id) }
            self.cursor = page.nextCursor
        } catch {
            failed = true
        }
    }

    func replace(_ chat: InboxOlfatoChat) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) { chats[index] = chat }
    }

    func remove(_ id: String) { chats.removeAll { $0.id == id } }
}

/// Olfato AI (`/provider/olfato`): a chat not begun, with "Tus chats" a tap away.
struct OlfatoScreen: View {
    var body: some View {
        InboxOlfatoPage(chatId: nil, root: true)
    }
}

/// One of the person's chats, by its id (`/provider/olfato/<id>`).
struct OlfatoChatScreen: View {
    let chatId: String

    var body: some View {
        InboxOlfatoPage(chatId: chatId, root: false)
    }
}

/// The web's one Olfato AI page (olfato-business-page.tsx): no module header, a 56 pt chat bar (the
/// vet-coat corgi, the chat's name, what it is about, its ⋯ and "Nuevo chat"), the open chat with
/// the rest of the screen, and the person's chats in a panel from the left ("Tus chats" — the web's
/// sidebar, a sheet of its own outside the shell). Opening another chat swaps it in place; a reply
/// still being written is finished and kept on the server. The notice, a support session and a
/// closed workspace are the whole page; earlier chats stay readable when nothing new can be asked.
struct InboxOlfatoPage: View {
    let root: Bool

    @EnvironmentObject private var workspace: Workspace
    @StateObject private var viewer = InboxOlfatoViewer()
    @StateObject private var list = InboxOlfatoChatListModel()
    @State private var model: InboxOlfatoChatModel
    @State private var listOpen = false
    @State private var renaming: InboxOlfatoChat?
    @State private var deleting: InboxOlfatoChat?
    @State private var loadedOnce = false

    init(chatId: String?, root: Bool) {
        self.root = root
        _model = State(initialValue: InboxOlfatoChatModel(chatId: chatId))
    }

    private var gate: InboxOlfatoGate { viewer.gate }
    private var canEditWorkspace: Bool { workspace.can(.workspaceEdit) }

    var body: some View {
        content
            .providerPage(root ? "Olfato AI" : model.title, root: root)
            .reloadsOnScope {
                await viewer.load()
                if viewer.gate.readable { await list.load() }
            }
            .onAppear {
                // Back on the chat: read it again, unless a reply is being followed here.
                if loadedOnce && !model.live { Task { await model.loadMessages() } }
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
        case .notice:
            InboxOlfatoNoticeGate(canConfirm: canEditWorkspace) {
                await viewer.load()
                await list.load()
            }
        case .privateSession, .error:
            InboxOlfatoGatePage(gate: gate, canEditWorkspace: canEditWorkspace) { await viewer.load() }
        default:
            if gate != .ready && list.ready && list.chats.isEmpty && model.chatId == nil {
                // Nothing can be asked, and nothing earlier to read: the reason is the page.
                InboxOlfatoGatePage(gate: gate, canEditWorkspace: canEditWorkspace, retry: nil)
            } else {
                chatPage
            }
        }
    }

    private var chatPage: some View {
        VStack(spacing: 0) {
            InboxOlfatoChatBar(
                title: model.chat != nil || model.localTitle != nil ? model.title : "Olfato AI",
                petLine: model.chat?.way == "pet" ? model.chat?.about : nil,
                subtitle: L("About your business"),
                onChats: { withAnimation(.easeOut(duration: 0.22)) { listOpen = true } },
                menu: model.chat.map { chat in (rename: { renaming = chat }, delete: { deleting = chat }) },
                onNew: begun ? { startNew() } : nil
            )
            if model.gone {
                PageScroll {
                    EmptyState(systemImage: "message-square-warning", title: L("That chat is not here any more."), message: L("Only you can read your chats, for 90 days."), panel: true)
                }
            } else {
                InboxOlfatoThread(model: model, viewer: viewer, canEditWorkspace: canEditWorkspace)
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .task(id: ObjectIdentifier(model)) {
            let panel = viewer
            model.onGateRefusal = { [weak panel] in Task { await panel?.load() } }
            await model.load()
            loadedOnce = true
        }
        .onChange(of: model.chatId) { old, new in
            // The first question gave the chat its id: it joins the list.
            if old == nil, new != nil { Task { await list.load() } }
        }
        .overlay {
            InboxOlfatoDrawer(isOpen: $listOpen) {
                InboxOlfatoChatListView(
                    list: list,
                    activeId: model.chatId,
                    searchable: true,
                    onOpen: { id in
                        open(id)
                        withAnimation(.easeOut(duration: 0.22)) { listOpen = false }
                    },
                    onRename: { renaming = $0 },
                    onDelete: { deleting = $0 }
                ) {
                    if gate == .ready {
                        PMButton(L("New chat"), systemImage: "message-square-plus", fullWidth: true) {
                            startNew()
                            withAnimation(.easeOut(duration: 0.22)) { listOpen = false }
                        }
                    }
                }
            }
        }
    }

    private var begun: Bool { model.chat != nil || !model.messages.isEmpty || model.gone }

    // MARK: Moving between chats

    private func open(_ id: String) {
        guard id != model.chatId else { return }
        // Only stops watching: a reply still being written is finished and kept on the server.
        model.leave()
        model = InboxOlfatoChatModel(chatId: id)
    }

    private func startNew() {
        guard begun else { return }
        model.leave()
        model = InboxOlfatoChatModel(chatId: nil)
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
            // The open chat deleted: a chat not begun takes its place.
            model = InboxOlfatoChatModel(chatId: nil)
        } else {
            do {
                try await API.send("DELETE", "/provider-olfato/chats/\(chat.id)")
            } catch let error as APIError where error.code == "olfato_chat_not_found" || error.status == 404 {
                // Gone already is what was asked for.
            }
            list.remove(chat.id)
        }
    }
}

// MARK: - The chat bar

/// The bar over a chat (web olfato-business-page header): 56 tall, white, a hairline under it; "Tus chats"
/// (a 40 ghost circle), the vet-coat corgi at 28, the chat's name in Fredoka 18 and what it is about in
/// 12, the chat's ⋯, and "Nuevo chat" (a 40 button; its icon alone on a phone).
struct InboxOlfatoChatBar: View {
    let title: String
    /// "About Luna" for a chat about a pet (with the paw); else `subtitle`.
    var petLine: String? = nil
    var subtitle: String
    var onChats: (() -> Void)? = nil
    var menu: (rename: () -> Void, delete: () -> Void)? = nil
    var onNew: (() -> Void)? = nil
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        HStack(spacing: 8) {
            if let onChats {
                Button(action: onChats) {
                    Glyph("panel-left", size: 16).foregroundStyle(Theme.inkStrong).frame(width: 40, height: 40).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Your chats"))
            }
            Image("OlfatoFace").resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                if let petLine {
                    HStack(spacing: 4) {
                        Glyph("paw-print", size: 12)
                        Text(petLine).lineLimit(1)
                    }
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                } else {
                    Text(subtitle).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let menu {
                Menu {
                    Button(action: menu.rename) { GlyphLabel(L("Rename"), icon: "pencil") }
                    Button(role: .destructive, action: menu.delete) { GlyphLabel(L("Delete"), icon: "trash-2") }
                } label: {
                    IconCircleLabel(size: 40, bordered: false)
                }
                .accessibilityLabel(LF("More for “%@”", title))
            }
            if let onNew {
                if sizeClass == .regular {
                    PMButton(L("New chat"), systemImage: "message-square-plus", size: .compact, action: onNew)
                } else {
                    Button(action: onNew) { Glyph("message-square-plus", size: 16) }
                        .buttonStyle(.pm(.primary, size: .compact))
                        .accessibilityLabel(L("New chat"))
                }
            }
        }
        .padding(.horizontal, sizeClass == .regular ? 16 : 12)
        .frame(minHeight: 56)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { RowDivider() }
    }
}

// MARK: - Tus chats

/// The chats' panel from the left (web: the sidebar's sheet, min(22 rem, 88% of the width)) over a veil.
private struct InboxOlfatoDrawer<Content: View>: View {
    @Binding var isOpen: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                if isOpen {
                    Theme.inkStrong.opacity(0.28)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.easeOut(duration: 0.22)) { isOpen = false } }
                        .transition(.opacity)
                        .accessibilityLabel(L("Close"))
                        .accessibilityAddTraits(.isButton)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(L("Your chats")).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                            Spacer()
                            Button { withAnimation(.easeOut(duration: 0.22)) { isOpen = false } } label: {
                                Glyph("x", size: 16).foregroundStyle(Theme.inkSoft).frame(width: 40, height: 40).contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L("Close"))
                        }
                        .padding(.leading, 16)
                        .padding(.trailing, 8)
                        .frame(minHeight: 56)
                        RowDivider()
                        content()
                    }
                    .frame(width: min(352, proxy.size.width * 0.88))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Theme.surface.ignoresSafeArea())
                    .overlay(alignment: .trailing) { Rectangle().fill(Theme.borderSoft).frame(width: 1).ignoresSafeArea() }
                    .shadow(color: Theme.navy.opacity(0.14), radius: 24, x: 12)
                    .transition(.move(edge: .leading))
                }
            }
        }
        .allowsHitTesting(isOpen)
    }
}

/// The person's chats, newest first under "Hoy / Ayer / Esta semana / Antes", 20 at a time with the
/// next page as the end nears (web `OlfatoChatList`): a search by name, each chat's name and when,
/// its pet when it is about one, and its ⋯ (rename, delete).
struct InboxOlfatoChatListView<Top: View>: View {
    @ObservedObject var list: InboxOlfatoChatListModel
    let activeId: String?
    var showPets = true
    var searchable = false
    let onOpen: (String) -> Void
    let onRename: (InboxOlfatoChat) -> Void
    let onDelete: (InboxOlfatoChat) -> Void
    @ViewBuilder var top: () -> Top

    @State private var query = ""

    private func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
    }

    private var sorted: [InboxOlfatoChat] { list.chats.sorted { $0.sortDate > $1.sortDate } }

    private var shown: [InboxOlfatoChat] {
        let needle = folded(query)
        guard !needle.isEmpty else { return sorted }
        return sorted.filter { folded($0.displayTitle).contains(needle) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    top()
                    if searchable {
                        SearchField(prompt: L("Search your chats"), text: $query, height: 40)
                    }
                }
                .padding(12)
                Group {
                    if !list.ready {
                        LoadingState(text: L("Loading your chats"))
                    } else if list.failed && list.chats.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Your chats could not be loaded.")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                            PMButton(L("Try again"), variant: .outline, size: .compact) { Task { await list.load() } }
                        }
                        .padding(.horizontal, 16)
                    } else if list.chats.isEmpty {
                        Text(L("Your chats will be listed here. Only you can read them, for 90 days."))
                            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.horizontal, 16)
                    } else if shown.isEmpty {
                        Text(LF("No chat matches “%@”.", query.trimmingCharacters(in: .whitespaces)))
                            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.horizontal, 16)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(InboxChatDay.groups(shown), id: \.day) { group in
                                Text(group.day.label.uppercased())
                                    .font(.brandText(12, weight: .bold)).tracking(0.3)
                                    .foregroundStyle(Theme.inkSoft)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 4)
                                    .padding(.bottom, 6)
                                VStack(spacing: 2) {
                                    ForEach(group.chats) { chat in
                                        InboxChatRow(chat: chat, showsAbout: showPets, selected: chat.id == activeId,
                                                     onOpen: { onOpen(chat.id) }, onRename: { onRename(chat) }, onDelete: { onDelete(chat) })
                                            .onAppear { if chat.id == shown.last?.id { Task { await list.loadMore() } } }
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.bottom, 8)
                            }
                        }
                    }
                }
                if list.hasMore || (list.failed && !list.chats.isEmpty) {
                    PMButton(list.loadingMore ? L("Loading…") : (list.failed ? L("Try again") : L("Show more")), systemImage: "chevron-down",
                             variant: .outline, size: .compact, fullWidth: true, isWorking: list.loadingMore) {
                        Task { await list.loadMore() }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await list.load() }
    }
}

extension InboxOlfatoChatListView where Top == EmptyView {
    init(list: InboxOlfatoChatListModel, activeId: String?, showPets: Bool = true, searchable: Bool = false,
         onOpen: @escaping (String) -> Void, onRename: @escaping (InboxOlfatoChat) -> Void, onDelete: @escaping (InboxOlfatoChat) -> Void) {
        self.init(list: list, activeId: activeId, showPets: showPets, searchable: searchable, onOpen: onOpen, onRename: onRename, onDelete: onDelete, top: { EmptyView() })
    }
}

/// Chats under their day in the business's calendar: today, yesterday, the rest of this week, before.
enum InboxChatDay: Int, CaseIterable {
    case today, yesterday, week, earlier

    var label: String {
        switch self {
        case .today: L("Today")
        case .yesterday: L("Yesterday")
        case .week: L("This week")
        case .earlier: L("Earlier")
        }
    }

    static func groups(_ chats: [InboxOlfatoChat]) -> [(day: InboxChatDay, chats: [InboxOlfatoChat])] {
        let calendar = DateText.calendar
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let sinceMonday = (weekday + 5) % 7
        var groups: [InboxChatDay: [InboxOlfatoChat]] = [:]
        for chat in chats {
            let day = calendar.startOfDay(for: chat.sortDate)
            let ago = calendar.dateComponents([.day], from: day, to: today).day ?? Int.max
            let group: InboxChatDay = ago <= 0 ? .today : (ago == 1 ? .yesterday : (ago <= sinceMonday ? .week : .earlier))
            groups[group, default: []].append(chat)
        }
        return allCases.compactMap { day in groups[day].map { (day, $0) } }
    }
}

/// One chat in the list (web `OlfatoChatList` row): its name in 14, under it the pet (when it is about
/// one) and when, or "Respondiendo…"; the open one on surface-muted; its ⋯ beside it.
struct InboxChatRow: View {
    let chat: InboxOlfatoChat
    /// The pet under the title; a pet's own list leaves it out.
    var showsAbout = true
    var selected = false
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    private var when: String {
        let date = chat.sortDate
        return DateText.calendar.isDateInToday(date) ? DateText.time(date) : DateText.date(date)
    }

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.displayTitle).font(Theme.text(14, weight: selected ? .bold : .regular)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    HStack(spacing: 4) {
                        if showsAbout && chat.way == "pet" {
                            Glyph("paw-print", size: 12)
                            Text(chat.petName?.nonEmpty ?? L("a pet")).lineLimit(1)
                            Text("·")
                        }
                        Text(chat.replying == true ? L("Answering…") : when)
                    }
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.inkSoft)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(selected ? Theme.surfaceMuted : Color.clear, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            Menu {
                Button(action: onRename) { GlyphLabel(L("Rename"), icon: "pencil") }
                Button(role: .destructive, action: onDelete) { GlyphLabel(L("Delete"), icon: "trash-2") }
            } label: {
                IconCircleLabel(size: 40, bordered: false)
            }
            .accessibilityLabel(LF("More for “%@”", chat.displayTitle))
        }
    }
}

// MARK: - Rename and delete

struct InboxRenameChatSheet: View {
    let title: String
    let save: (String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var value = ""
    @State private var saving = false

    var body: some View {
        ProviderModal(title: L("Rename chat"), subtitle: L("Only you see this name."), systemImage: "pencil", accent: .aqua, isDirty: value != title, form: form, primaryTitle: L("Save"), isWorking: saving) {
            let next = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard form.check([
                ("title", next.isEmpty ? L("Write a name for the chat.") : (next.count > 80 ? LF("Keep it under %d characters.", 80) : nil)),
            ]) else { return }
            saving = true
            Task {
                defer { saving = false }
                do {
                    try await save(next)
                    dismiss()
                } catch {
                    form.apply(error, known: ["title": "title"])
                }
            }
        } content: {
            PMTextField(L("Name of the chat"), text: $value, key: "title", form: form)
        }
        .presentationDetents([.medium])
        .onAppear { value = title }
    }
}

struct InboxDeleteChatSheet: View {
    let title: String
    let delete: () async throws -> Void

    var body: some View {
        ConfirmSheet(
            title: L("Delete this chat?"),
            message: LF("“%@” is deleted for good, its questions and answers with it. The log of who asked stays, without the text.", title),
            confirmTitle: L("Delete"),
            destructive: true
        ) { _ in
            do {
                try await delete()
            } catch {
                Toast.error(L("The chat could not be deleted. Try again."))
                throw error
            }
        }
    }
}

// MARK: - Gates

/// A gate as the whole page: nothing to read yet, and nothing can be asked.
struct InboxOlfatoGatePage: View {
    let gate: InboxOlfatoGate
    let canEditWorkspace: Bool
    var retry: (() async -> Void)?

    var body: some View {
        PageScroll {
            VStack(spacing: 12) {
                Image("OlfatoAI").resizable().scaledToFit().frame(width: 96, height: 96).accessibilityHidden(true)
                Text(gate == .privateSession ? L("Chats are private.") : "Olfato AI")
                    .font(.brandHeading(24, relativeTo: .title2)).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.center)
                Text(gate.sentence).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                if gate == .off && canEditWorkspace {
                    NavigationLink(value: ProviderRoute.section(.settings)) {
                        HStack(spacing: 6) { Glyph("settings", size: 16); Text(L("Turn it on in Settings")) }
                    }
                    .buttonStyle(.pm(.primary))
                    .padding(.top, 8)
                }
                if gate == .error, let retry {
                    PMButton(L("Try again"), variant: .outline) { Task { await retry() } }
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: 576)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
    }
}

/// The notice as the whole page. Someone who edits the workspace reads it and confirms it here; anyone else
/// is told the business has to.
struct InboxOlfatoNoticeGate: View {
    let canConfirm: Bool
    let confirmed: () async -> Void
    @State private var checked = false
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        PageScroll(maxWidth: 1000) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(canConfirm ? L("Before your team uses the chat") : L("Your business has to accept the Olfato AI notice."))
                        .font(.brandHeading(24, relativeTo: .title2)).foregroundStyle(Theme.inkStrong)
                    Text(canConfirm
                         ? L("The Olfato AI notice changed: it now covers the chat too. Read it and confirm it to use Olfato AI.")
                         : L("Someone who edits the workspace, an owner or an admin, confirms it in Settings › Olfato AI. Until then the chat waits."))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
                Image("OlfatoAI").resizable().scaledToFit().frame(width: 80, height: 80).accessibilityHidden(true)
            }
            if canConfirm {
                OlfatoNotice(minimumWidth: 300)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $checked) {
                        Text(L("I’ve read this and our clients are informed as our policies require"))
                            .font(Theme.text(15, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    }
                    .toggleStyle(PMSwitchStyle())
                    .onChange(of: checked) { _, value in if value { error = nil } }
                    if let error {
                        Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral)
                    }
                }
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous).strokeBorder(error != nil ? Theme.coral : Theme.borderSoft, lineWidth: 1))
                .overlay { if error != nil { RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous).inset(by: -3).strokeBorder(Theme.coral.opacity(0.2), lineWidth: 3) } }
                HStack {
                    Spacer()
                    PMButton(L("Confirm and open the chat"), isWorking: saving) { Task { await confirm() } }
                }
            }
        }
    }

    private func confirm() async {
        guard checked else {
            let sentence = L("Tick the confirmation to use the chat.")
            error = sentence
            Toast.error(sentence)
            return
        }
        saving = true
        defer { saving = false }
        do {
            // The notice alone: the switch stays as the business left it.
            try await API.send("PUT", "/provider-patients/ai-summary-settings", body: ["acknowledged": true])
            Toast.show(L("Confirmed. Your team can use Olfato AI."))
            await confirmed()
            announceDataChanged()
        } catch {
            Toast.error(error, fallback: L("It could not be saved. Try again."))
        }
    }
}
