//
//  InboxOlfatoThread.swift
//  PawMiawNegocios
//
//  One Olfato AI chat (web olfato-business-thread.tsx and
//  olfato-business-reply.tsx): a chat not begun opens on "Lo que puedo ver
//  contigo" and a few questions from the areas open to this person; then
//  the questions and replies (the tools each ran, its lock chips and its
//  "Ver en …" links); the box at the bottom, with stop while a reply is
//  written. When the person can't ask now, the box gives way to why.
//

import SwiftUI
import UIKit

/// A pet a chat is about (its provider client pet id and name).
struct InboxOlfatoPetRef: Hashable {
    let id: String
    let name: String
}

struct InboxOlfatoThread: View {
    @ObservedObject var model: InboxOlfatoChatModel
    @ObservedObject var viewer: InboxOlfatoViewer
    let canEditWorkspace: Bool
    /// A chat about this pet (from its chart): its own welcome, questions and box.
    var pet: InboxOlfatoPetRef? = nil
    /// From a chart: "Lo que puedo ver contigo" folds into one line.
    var compact = false

    @State private var draft = ""
    @State private var problem: String?
    @FocusState private var focused: Bool
    /// The view follows a reply to its end, unless the reader scrolled away from it.
    @State private var pinned = true
    /// Far enough from the end to offer "Ir al último mensaje".
    @State private var below = false
    /// The reader's finger is on the list (a reply growing never unpins it; only the reader's scroll does).
    @State private var readerScrolling = false
    @State private var gap: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var gate: InboxOlfatoGate { viewer.gate }
    private var ready: Bool { gate == .ready }
    private var maxChars: Int { viewer.panel?.chat?.maxMessageChars ?? 2000 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !model.loaded {
                        LoadingState(text: L("Loading the chat"))
                    } else if model.messages.isEmpty {
                        fresh
                    } else {
                        if model.hasOlder {
                            PMButton(L("Show earlier messages"), systemImage: "chevron-up", variant: .outline, size: .compact, isWorking: model.loadingOlder) {
                                Task { await model.loadOlder() }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                            if message.isUser {
                                InboxOlfatoQuestion(text: message.content)
                            } else {
                                InboxOlfatoReply(
                                    message: message,
                                    language: InboxOlfatoLanguage.ofReply(model.messages, at: index),
                                    last: index == model.messages.count - 1,
                                    canAsk: ready && !model.busy,
                                    panel: viewer.panel,
                                    retry: { model.retry() },
                                    rate: { rating, reason in try await model.rate(message.id, rating: rating, reason: reason) }
                                )
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id("olfato-bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas.ignoresSafeArea())
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height - geometry.visibleRect.maxY
            } action: { _, distance in
                gap = distance
                below = distance > 96
                if readerScrolling { pinned = distance < 48 }
            }
            .onScrollPhaseChange { _, phase in
                let reader = phase == .tracking || phase == .interacting || phase == .decelerating
                if readerScrolling && !reader { pinned = gap < 48 }
                readerScrolling = reader
            }
            .onChange(of: model.messages.count) { _, _ in follow(proxy) }
            .onChange(of: model.messages.last?.content) { _, _ in follow(proxy, animated: false) }
            .onChange(of: model.messages.last?.status) { _, _ in follow(proxy) }
            .onChange(of: model.chatId) { old, _ in
                // Another chat is read from its end, and the box starts over; a chat that just got its id
                // is the one being asked, and what is typed stays.
                if old != nil {
                    draft = ""
                    problem = nil
                }
                pinned = true
                follow(proxy, animated: false)
            }
            .onAppear { follow(proxy, animated: false) }
            .overlay(alignment: .bottom) {
                if below && !pinned && !model.messages.isEmpty {
                    Button {
                        pinned = true
                        follow(proxy)
                    } label: {
                        Glyph("arrow-down", size: 16)
                            .foregroundStyle(Theme.blue)
                            .frame(width: 40, height: 40)
                            .background(Theme.surface, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.blue, lineWidth: 2))
                            .cardShadow()
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                    .accessibilityLabel(L("Go to the latest message"))
                    .transition(.opacity)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .onChange(of: model.formRefusal) { _, refusal in
            guard let refusal else { return }
            // A question refused for what was typed comes back into the box, which says why.
            draft = refusal.question
            problem = refusal.sentence
            Toast.error(refusal.sentence)
            focused = true
            model.formRefusal = nil
        }
    }

    private func follow(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard pinned else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("olfato-bottom", anchor: .bottom) }
        } else {
            proxy.scrollTo("olfato-bottom", anchor: .bottom)
        }
    }

    // MARK: A chat not begun

    private var fresh: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image("OlfatoAI").resizable().scaledToFit().frame(width: compact ? 56 : 80, height: compact ? 56 : 80).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pet.map { LF("What do you want to know about %@?", $0.name) } ?? L("What do you want to know?"))
                        .font(.brandHeading(compact ? 20 : 24, relativeTo: .title2)).foregroundStyle(Theme.inkStrong)
                    Text(pet.map { LF("I read %@’s chart with your access. I only read: I never change anything.", $0.name) }
                         ?? L("Ask about your patients or your business. I answer only from what you can already see, and I never change anything."))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.top, compact ? 4 : 16)
            if let panel = viewer.panel { InboxOlfatoAccessPanel(panel: panel, compact: compact) }
            let suggestions = InboxOlfatoSuggestions.list(viewer.panel, pet: pet)
            if ready && !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Try asking").uppercased()).font(.brandText(12, weight: .bold)).tracking(0.3).foregroundStyle(Theme.inkSoft)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: sizeClass == .regular ? 2 : 1), spacing: 8) {
                        ForEach(suggestions, id: \.self) { text in
                            PMButton(text, variant: .outline, fullWidth: true) { ask(text) }
                                .disabled(model.busy)
                        }
                    }
                }
            }
        }
    }

    // MARK: The box

    private var composer: some View {
        VStack(spacing: 6) {
            if ready {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(pet.map { LF("Ask about %@…", $0.name) } ?? L("Ask about your patients or your business…"), text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($focused)
                        .font(Theme.bodyFont)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .accessibilityLabel(L("Question for Olfato AI"))
                        .onChange(of: draft) { _, _ in if problem != nil { problem = nil } }
                    if model.busy {
                        roundButton("square", label: L("Stop the reply"), filled: false) { Task { await model.stop() } }
                    } else {
                        roundButton("arrow-up", label: L("Send@olfato"), filled: true) { ask(draft) }
                            .disabled(draft.nonEmpty == nil)
                    }
                }
                .padding(6)
                .padding(.leading, -2)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(problem != nil || tooLong ? Theme.destructive : Theme.borderSoft, lineWidth: 1))
                .overlay { if focused { RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).inset(by: -3).strokeBorder(Theme.mango.opacity(0.4), lineWidth: 3) } }
                .cardShadow()
                HStack(alignment: .top) {
                    if let problem {
                        Text(problem).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.destructive)
                    } else {
                        Text(L("Olfato AI can get things wrong. Check the record before acting.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 8)
                    if draft.count > Int(Double(maxChars) * 0.8) {
                        Text(LF("%d of %d characters", draft.count, maxChars))
                            .font(Theme.text(12, weight: tooLong ? .bold : .regular))
                            .foregroundStyle(tooLong ? Theme.destructive : Theme.inkSoft)
                    }
                }
                .padding(.horizontal, 4)
            } else {
                InboxOlfatoLockedBar(gate: gate, canEditWorkspace: canEditWorkspace)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: 768)
        .frame(maxWidth: .infinity)
        .background(Theme.canvas.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { RowDivider() }
    }

    private var tooLong: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).count > maxChars }

    private func roundButton(_ systemImage: String, label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Glyph(systemImage, size: filled ? 16 : 14)
                .foregroundStyle(filled ? Theme.onBlue : Theme.blue)
                .frame(width: 40, height: 40)
                .background(filled ? Theme.blue : Theme.surface, in: Circle())
                .overlay { if !filled { Circle().strokeBorder(Theme.blue, lineWidth: 2) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func ask(_ question: String) {
        guard ready, !model.busy else { return }
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return refuse(InboxOlfatoRefusal.sentence("olfato_empty")) }
        if text.count > maxChars { return refuse(InboxOlfatoRefusal.sentence("olfato_too_long", ["maxChars": .number(Double(maxChars))])) }
        pinned = true
        if model.ask(text) {
            draft = ""
            problem = nil
            focused = false
        }
    }

    private func refuse(_ sentence: String) {
        problem = sentence
        Toast.error(sentence)
        focused = true
    }
}

/// In the box's place: earlier chats stay readable, nothing new is asked.
struct InboxOlfatoLockedBar: View {
    let gate: InboxOlfatoGate
    let canEditWorkspace: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Glyph("lock", size: 16).foregroundStyle(Theme.inkSoft).padding(.top, 2)
                Text(gate.sentence).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
            }
            if gate == .off && canEditWorkspace {
                NavigationLink(value: ProviderRoute.section(.settings)) { Text(L("Turn it on in Settings")) }
                    .buttonStyle(.pm(.outline, size: .compact))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }
}

/// "Lo que puedo ver contigo": the areas open (with what each is limited to), the areas closed with why,
/// and what every answer is limited to. Built by the server from the person's permissions.
struct InboxOlfatoAccessPanel: View {
    let panel: InboxOlfatoPanel
    /// In a pet's chat: one line, opened on demand.
    var compact = false

    @State private var expanded = false

    var body: some View {
        let areas = panel.offeredAreas
        Card {
            if compact {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack {
                        heading
                        Spacer(minLength: 6)
                        Text(LF("%d open · %d closed", areas.open.count, areas.closed.count)).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        Glyph("chevron-down", size: 16)
                            .foregroundStyle(Theme.inkSoft)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(expanded ? .isSelected : [])
                if expanded { details(areas) }
            } else {
                HStack {
                    heading
                    Spacer()
                    Text(LF("%d open · %d closed", areas.open.count, areas.closed.count)).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                }
                details(areas)
            }
        }
    }

    private var heading: some View {
        HStack(spacing: 8) {
            Image("OlfatoFace").resizable().scaledToFit().padding(2)
                .frame(width: 28, height: 28)
                .background(Theme.wash(Theme.aqua, 24), in: Circle())
                .accessibilityHidden(true)
            Text(L("What I can see with you")).font(.brandHeading(16, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
        }
    }

    @ViewBuilder
    private func details(_ areas: (open: [InboxOlfatoArea], closed: [InboxOlfatoArea])) -> some View {
            ForEach(panel.scope ?? [], id: \.self) { note in
                HStack(alignment: .top, spacing: 6) {
                    Glyph("map-pin", size: 14).padding(.top, 2)
                    Text(note.text)
                }
                .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
            }
            if !areas.open.isEmpty {
                Text(L("I can see").uppercased()).font(.brandText(12, weight: .bold)).tracking(0.3).foregroundStyle(Theme.inkSoft)
                FlowLayout(spacing: 6) {
                    ForEach(areas.open) { area in
                        let label = ([area.label?.text ?? area.key] + (area.notes ?? []).map(\.text)).joined(separator: " · ")
                        HStack(spacing: 4) {
                            Glyph("check", size: 12)
                            Text(label)
                        }
                        .font(Theme.text(12, weight: .semibold))
                        .foregroundStyle(Theme.inkStrong)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .frame(minHeight: 28)
                        .background(Theme.wash(ProviderState.done.color, 10), in: Capsule())
                        .overlay(Capsule().strokeBorder(ProviderState.done.color, lineWidth: 1))
                    }
                }
            }
            if !areas.closed.isEmpty {
                Text(L("Closed with your access").uppercased()).font(.brandText(12, weight: .bold)).tracking(0.3).foregroundStyle(Theme.inkSoft)
                ForEach(areas.closed) { area in
                    HStack(alignment: .top, spacing: 8) {
                        Glyph("lock", size: 14).foregroundStyle(Theme.inkStrong).padding(.top, 2)
                        (Text(area.label?.text ?? area.key).bold() + Text(area.reason.map { ": \($0.text)" } ?? "").foregroundColor(Theme.inkSoft))
                            .font(Theme.text(14))
                            .foregroundStyle(Theme.inkStrong)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.wash(ProviderState.waiting.color, 10), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(ProviderState.waiting.color, lineWidth: 1))
                }
            }
    }
}

/// A wrapping row of chips (the same layout as Home's).

/// Questions to start from, only from the areas open to this person (lib/olfato-business-suggestions.ts).
enum InboxOlfatoSuggestions {
    private static let business: [(String, String)] = [
        ("today", "What do we have today?"),
        ("finances", "How much did we collect this week?"),
        ("front_desk", "Who owes us money?"),
        ("inventory", "What is running low?"),
        ("hospital", "Who is in the hospital right now?"),
        ("agenda", "How many visits do we have this week?"),
        ("follow_ups", "Which follow-ups are still to do?"),
        ("incidents", "What incidents were there this week?"),
        ("stays", "Who checks out of their stay today?"),
        ("grooming", "How is grooming going today?"),
        ("pharmacy", "Which prescriptions are waiting?"),
        ("clients", "How many patients do we have?"),
        ("team", "Who is working today?"),
    ]

    /// About one pet (from its chart).
    private static let pet: [(String, String)] = [
        ("records", "What did we give %@ last time?"),
        ("records", "Does %@ have anything pending?"),
        ("records", "How has %@’s weight changed?"),
        ("clients", "When was %@’s last visit?"),
        ("front_desk", "Does %@’s family owe anything?"),
    ]

    static func list(_ panel: InboxOlfatoPanel?, max: Int = 4) -> [String] {
        list(panel, pet: nil, max: max)
    }

    static func list(_ panel: InboxOlfatoPanel?, pet ref: InboxOlfatoPetRef?, max: Int = 4) -> [String] {
        let open = Set((panel?.areas ?? []).filter { $0.open == true && $0.offered == true }.map(\.key))
        guard let ref else { return business.filter { open.contains($0.0) }.prefix(max).map { L($0.1) } }
        return pet.filter { open.contains($0.0) }.prefix(max).map { LF($0.1, ref.name) }
    }
}

// MARK: - A question and a reply

private struct InboxOlfatoQuestion: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            // The web's bubble: rounded-[1.25rem] with rounded-br-md, aqua 22%, 15.2 type.
            Text(text)
                .font(Theme.text(15.2))
                .foregroundStyle(Theme.inkStrong)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.wash(Theme.aqua, 22), in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20, style: .continuous))
                .textSelection(.enabled)
        }
    }
}

struct InboxOlfatoReply: View {
    let message: InboxOlfatoMessage
    /// The language the reply is written in (its question's): its tools, lock chips and links follow it.
    var language: InboxOlfatoLanguage = .app
    let last: Bool
    let canAsk: Bool
    let panel: InboxOlfatoPanel?
    let retry: () -> Void
    let rate: (String?, String?) async throws -> Void

    @State private var copied = false
    @State private var askingWhy = false
    @State private var saving = false
    @State private var reason: String?
    @State private var reasonMissing = false

    /// Why a reply was bad, from the server's fixed list (web olfato-business-reply.tsx REASONS).
    private static let reasons: [(value: String, title: String)] = [
        ("incorrect", "It is wrong"),
        ("incomplete", "Something is missing"),
        ("closed_wrongly", "It said I had no access, and I do"),
        ("unhelpful", "It did not help"),
        ("other", "Something else"),
    ]

    private func byArea(_ status: String) -> [InboxOlfatoTool] {
        var seen: [String: InboxOlfatoTool] = [:]
        var order: [String] = []
        for tool in message.tools where tool.status == status {
            let key = tool.area ?? tool.name ?? ""
            if seen[key] == nil { seen[key] = tool; order.append(key) }
        }
        return order.compactMap { seen[$0] }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image("OlfatoFace")
                .resizable()
                .scaledToFit()
                .padding(3)
                .frame(width: 32, height: 32)
                .background(Theme.blueWash, in: Circle())
                .opacity(message.arriving ? 0.6 : 1)
                .animation(message.arriving ? .easeInOut(duration: 0.8).repeatForever() : .default, value: message.arriving)
            VStack(alignment: .leading, spacing: 10) {
                let running = message.tools.filter { $0.status == "running" }
                if !running.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(running, id: \.self) { tool in
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.mini)
                                Text(language.format("Checking %@…", tool.areaName(in: language)))
                            }
                            .font(Theme.text(12, weight: .semibold))
                            .foregroundStyle(Theme.inkStrong)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.surfaceMuted, in: Capsule())
                        }
                    }
                }
                if message.arriving && message.content.isEmpty && running.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L("Olfato AI is thinking")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    }
                }
                if !message.content.isEmpty {
                    InboxReplyText(content: message.content)
                }
                if !message.arriving { settled }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var settled: some View {
        if message.status == .stopped {
            HStack(spacing: 4) { Glyph("circle-stop", size: 14); Text(L("Reply stopped.")) }.font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
        }
        if message.truncated {
            HStack(alignment: .top, spacing: 4) { Glyph("triangle-alert", size: 14).padding(.top, 1); Text(L("The reply was cut short. Answer again to get it whole.")) }.font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
        }
        if message.status == .error {
            NoticeCard(tone: .problem, title: InboxOlfatoRefusal.sentence(message.errorCode, message.errorData))
        }
        let closed = byArea("closed")
        if !closed.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(closed, id: \.self) { tool in
                    let reason = panel?.areas?.first { $0.key == tool.area }?.reason?.text(in: language)
                    StatusChip(text: language.format("I couldn’t see %@ with your access", tool.areaName(in: language)), state: .waiting, outlined: true)
                        .accessibilityHint(reason ?? "")
                }
            }
        }
        let failed = byArea("failed")
        if !failed.isEmpty {
            Text(language.format("I couldn’t read %@ this time.", failed.map { $0.areaName(in: language) }.joined(separator: ", "))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
        let read = byArea("done")
        if !read.isEmpty {
            Text(language.format("Read: %@", read.map { $0.areaName(in: language) }.joined(separator: ", "))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
        let links = message.links.filter { $0.route != nil }
        if !links.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(links, id: \.self) { link in
                    if let route = link.route {
                        NavigationLink(value: route) {
                            HStack(spacing: 6) { Text(link.label?.text(in: language).nonEmpty ?? language.text("Open@olfato")); Glyph("arrow-right", size: 16) }
                        }
                        .buttonStyle(.pm(.outline, size: .compact))
                    }
                }
            }
        }
        HStack(spacing: 6) {
            if !message.content.isEmpty {
                IconCircleButton(systemImage: copied ? "check" : "copy", label: L("Copy reply")) {
                    UIPasteboard.general.string = InboxReplyText.plain(message.content)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        copied = false
                    }
                }
            }
            if last && canAsk && InboxOlfatoRefusal.retryHelps(message.errorCode) {
                IconCircleButton(systemImage: "refresh-cw", label: L("Answer again"), action: retry)
            }
            if message.status == .done && !message.local {
                let rating = message.feedback?.rating
                IconCircleButton(systemImage: "thumbs-up", label: L("Good reply"), tint: rating == "up" ? Theme.blue : Theme.inkSoft) {
                    save(rating == "up" ? nil : "up", nil)
                }
                .disabled(saving)
                IconCircleButton(systemImage: "thumbs-down", label: L("Bad reply"), tint: rating == "down" ? Theme.blue : Theme.inkSoft) {
                    if rating == "down" {
                        save(nil, nil)
                    } else {
                        reason = nil
                        reasonMissing = false
                        askingWhy.toggle()
                    }
                }
                .disabled(saving)
            }
        }
        // Down asks why under the reply, in a small box (web: the inline form, not a dialog).
        if askingWhy { whyBox }
    }

    private var whyBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("What was wrong with it?")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
            FlowLayout(spacing: 6) {
                ForEach(Self.reasons, id: \.value) { option in
                    FilterChip(title: L(option.title), isSelected: reason == option.value, solid: true) {
                        reason = option.value
                        reasonMissing = false
                    }
                }
            }
            .accessibilityLabel(L("What was wrong with it?"))
            if reasonMissing && reason == nil {
                Text(L("Choose what was wrong with the reply.")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.destructive)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                PMButton(L("Cancel"), variant: .outline, size: .compact) { askingWhy = false }
                PMButton(saving ? L("Saving…") : L("Send"), size: .compact, isWorking: saving) {
                    guard let reason else {
                        reasonMissing = true
                        Toast.error(L("Choose what was wrong with the reply."))
                        return
                    }
                    save("down", reason)
                }
                .disabled(saving)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    private func save(_ rating: String?, _ reason: String?) {
        saving = true
        Task {
            defer { saving = false }
            do {
                try await rate(rating, reason)
                askingWhy = false
            } catch {
                Toast.error(L("It could not be saved. Try again."))
            }
        }
    }
}

/// A reply read into paragraphs, headings, lists, table rows and **bold** — text only, never HTML
/// (olfato-business/business-reply-text.ts).
struct InboxReplyText: View {
    let content: String

    private struct Span: Hashable { let text: String; let bold: Bool }
    private enum Block: Hashable {
        case paragraph([Span])
        case heading([Span])
        case list(ordered: Bool, items: [[Span]])
        case table([[[Span]]])
    }

    /// One line's pieces. A `**` still open (the reply is arriving) is bold to the end.
    private static func spans(_ line: String) -> [Span] {
        line.components(separatedBy: "**").enumerated().compactMap { index, part in
            var text = part.replacingOccurrences(of: "(^|\\s)[_*](\\S)", with: "$1$2", options: .regularExpression)
            text = text.replacingOccurrences(of: "(\\S)[_*](?=\\s|$|[.,;:!?])", with: "$1", options: .regularExpression)
            text = text.replacingOccurrences(of: "`", with: "")
            return text.isEmpty ? nil : Span(text: text, bold: index % 2 == 1)
        }
    }

    private static func matches(_ line: String, _ pattern: String) -> Bool {
        line.range(of: pattern, options: .regularExpression) != nil
    }

    private static func strip(_ line: String, _ pattern: String) -> String {
        line.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private static func blocks(_ content: String) -> [Block] {
        var blocks: [Block] = []
        let bullet = "^(?:[-*•]\\s+|[-*•]$)", numbered = "^\\d{1,3}[.)]\\s+", heading = "^#{1,6}\\s+"
        let rule = "^\\|?\\s*:?-{2,}:?\\s*(\\|\\s*:?-{2,}:?\\s*)*\\|?$"
        for raw in content.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if matches(line, rule) && line.contains("-") { continue }
            if line.hasPrefix("|") {
                var trimmed = line
                if trimmed.hasPrefix("|") { trimmed.removeFirst() }
                if trimmed.hasSuffix("|") { trimmed.removeLast() }
                let row = trimmed.components(separatedBy: "|").map { spans($0.trimmingCharacters(in: .whitespaces)) }
                if case .table(var rows)? = blocks.last {
                    rows.append(row)
                    blocks[blocks.count - 1] = .table(rows)
                } else {
                    blocks.append(.table([row]))
                }
            } else if matches(line, bullet) || matches(line, numbered) {
                let ordered = matches(line, numbered)
                let item = spans(strip(line, ordered ? numbered : bullet))
                if case .list(let wasOrdered, var items)? = blocks.last, wasOrdered == ordered {
                    items.append(item)
                    blocks[blocks.count - 1] = .list(ordered: ordered, items: items)
                } else {
                    blocks.append(.list(ordered: ordered, items: [item]))
                }
            } else if matches(line, heading) {
                blocks.append(.heading(spans(strip(line, heading))))
            } else {
                blocks.append(.paragraph(spans(line)))
            }
        }
        return blocks
    }

    /// A reply as plain text, for copying.
    static func plain(_ content: String) -> String {
        content.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression)
    }

    private func text(_ spans: [Span]) -> Text {
        spans.reduce(Text("")) { result, span in result + Text(span.text).fontWeight(span.bold ? .bold : .regular) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.blocks(content).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let spans):
                    text(spans).font(Theme.bodyFont).foregroundStyle(Theme.inkStrong)
                case .heading(let spans):
                    text(spans).font(.brandHeading(17, relativeTo: .headline)).foregroundStyle(Theme.inkStrong).padding(.top, 2)
                case .list(let ordered, let items):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(ordered ? "\(index + 1)." : "•").font(Theme.bodyFont).foregroundStyle(Theme.inkSoft)
                                text(item).font(Theme.bodyFont).foregroundStyle(Theme.inkStrong)
                            }
                        }
                    }
                case .table(let rows):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                GridRow {
                                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                        text(cell).font(Theme.text(14, weight: index == 0 ? .semibold : .regular)).foregroundStyle(Theme.inkStrong)
                                    }
                                }
                                if index < rows.count - 1 { RowDivider() }
                            }
                        }
                        .padding(10)
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
            }
        }
        .textSelection(.enabled)
    }
}
