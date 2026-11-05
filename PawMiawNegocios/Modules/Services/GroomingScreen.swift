//
//  GroomingScreen.swift
//  PawMiawNegocios
//
//  Estética (web: routes/provider.grooming.tsx, components/app/grooming/):
//  the day's grooms by stage, the pets groomed here, who is due back and how
//  this business grooms. A groom is a visit: arriving, handing over and
//  charging stay on the visit's page (`ProviderRoute.appointment`).
//  What needs someone (backend docs/grooming-board.md) is flagged on the card.
//

import SwiftUI

struct GroomingScreen: View {
    var body: some View {
        RequireLocation { SvcGroomingPage() }
            .providerPage(L("Grooming"), root: true)
    }
}

private enum SvcGroomTab: String, Hashable { case today, pets, due, settings }

private struct SvcGroomingPage: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var tab: SvcGroomTab = .today
    @State private var today: SvcGroomingToday?
    @State private var todayError: String?
    @State private var settings: SvcGroomingSettings?
    @State private var overdue: Int?
    @State private var busyId: String?
    @State private var gate: SvcStartGateRequest?
    @State private var pushed: ProviderRoute?
    @State private var reportTarget: SvcReportTarget?

    private var canView: Bool { workspace.can(.appointmentsView) }
    private var canSeePets: Bool { workspace.can(.clientsView) }
    private var canSeeDue: Bool { workspace.canAny(.followupsView, .appointmentsCreate) }
    private var canStage: Bool { workspace.can(.appointmentsComplete) }
    private var canBook: Bool { workspace.canAll(.appointmentsCreate, .clientsView) }
    private var canRemind: Bool { workspace.canAny(.followupsEdit, .appointmentsCreate) }
    private var canEditCard: Bool { workspace.canAny(.petsEdit, .appointmentsComplete) }
    private var simple: Bool { settings?.simpleStages ?? false }

    var body: some View {
        if !canView {
            PageScroll { NoAccessState(message: L("Ask the workspace owner to let your role see appointments.")) }
        } else {
            page
        }
    }

    private var tabs: [ToneTabs<SvcGroomTab>.Tab] {
        var out: [ToneTabs<SvcGroomTab>.Tab] = [.init(value: .today, title: L("Today"), icon: "calendar-days")]
        if canSeePets { out.append(.init(value: .pets, title: L("Pets"), icon: "paw-print")) }
        if canSeeDue { out.append(.init(value: .due, title: L("Due back"), icon: "bell-ring", count: overdue)) }
        out.append(.init(value: .settings, title: L("Settings"), icon: "settings-2"))
        return out
    }

    private var page: some View {
        PageScroll(refresh: { await load() }) {
            header
            if let today, (today.needsSomeone ?? 0) > 0 {
                NoticeCard(tone: .problem, title: LP(today.needsSomeone ?? 0, "%d groom needs someone", "%d grooms need someone"), message: L("Here from an earlier day, ready with nobody told, or a pickup running late: each card says which."))
            }
            ToneTabs(tabs: tabs, selection: $tab, look: .solid)

            switch tab {
            case .today:
                if let today {
                    SvcGroomBoard(today: today, simple: simple, canStage: canStage, busyId: busyId, push: { pushed = $0 }, onNewGroom: canBook ? { pushed = SvcBook.groom(day: today.date) } : nil, onReport: { item in
                        reportTarget = SvcReportTarget(subtitle: "\(item.pet.name) · \(item.serviceLabel ?? "")", pets: [SvcReportPet(id: item.id, name: item.pet.name)], canWrite: canStage)
                    }, onMove: { item, stage in Task { await move(item, to: stage) } }, onTell: { item, channel in Task { await tell(item, channel) } })
                } else if todayError != nil {
                    SvcLoadError(message: L("Today’s grooms couldn’t be loaded.")) { await load() }
                } else {
                    LoadingState()
                }
            case .pets:
                SvcGroomPetsTab(canBook: canBook, canEditCard: canEditCard, canRemind: canRemind, push: { pushed = $0 })
            case .due:
                SvcGroomDueTab(canRemind: canRemind, canBook: canBook, push: { pushed = $0 })
            case .settings:
                SvcGroomSettingsTab(canManage: workspace.can(.workspaceEdit), businessName: workspace.current?.name ?? "")
            }
        }
        .navigationDestination(item: $pushed) { RouteView(route: $0) }
        .sheet(item: $gate) { request in
            SvcStartGateSheet(request: request) { announceDataChanged() }
        }
        .sheet(item: $reportTarget) { target in SvcReportSheet(target: target) }
        .reloadsOnScope { await load() }
        .task(id: workspace.scopeVersion) {
            // The board follows the day as the web's does (every minute).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await load()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        ModuleHeader(
            icon: "scissors",
            title: L("Grooming"),
            subtitle: today.map { svcCapitalized(SvcTime.dayLong($0.date)) } ?? L("The day’s grooms, the pets you groom and who is due back"),
            accent: Theme.pink,
            stats: stats,
            storageKey: "grooming"
        ) {
            if canBook {
                // The Agenda's booking, on grooming and today.
                PMButton(L("New groom"), systemImage: "plus") { pushed = SvcBook.groom(day: today?.date) }
            }
        }
    }

    private var stats: [ModuleStat] {
        let done = today?.count("done") ?? 0, waiting = today?.count("waiting") ?? 0
        var out: [ModuleStat] = [
            ModuleStat("today", label: L("Today’s grooms"), value: today.map { "\($0.total)" } ?? "—", hint: done > 0 ? LF("%d done", done) : nil, icon: "scissors", accent: Theme.pink),
            ModuleStat("progress", label: L("In progress"), value: today.map { "\($0.inProgress)" } ?? "—", hint: waiting > 0 ? LF("%d waiting", waiting) : nil, icon: "shower-head", accent: Theme.aqua),
            ModuleStat("ready", label: L("Ready for pickup"), value: today.map { "\($0.ready)" } ?? "—", icon: "package-check", accent: Theme.lime, attention: (today?.ready ?? 0) > 0),
        ]
        if canSeePets {
            out.append(ModuleStat("due", label: L("Due back"), value: overdue.map(String.init) ?? "—", hint: (overdue ?? 0) > 0 ? L("Overdue") : nil, icon: "bell-ring", accent: Theme.mango,
                                  attention: (overdue ?? 0) > 0, active: canSeeDue && tab == .due, action: canSeeDue ? { tab = .due } : nil))
        }
        return out
    }

    // MARK: Loading and moves

    private func load() async {
        do {
            today = try await API.get("/provider-grooming/today", query: ["locationId": workspace.locationId])
            todayError = nil
        } catch is CancellationError {
        } catch {
            if today == nil { todayError = errorText(error) }
        }
        if let loaded: SvcGroomingSettings = try? await API.get("/provider-grooming/settings") { settings = loaded }
        if canBook { await SvcServices.load("provider") }
        if canSeePets, let page: SvcGroomPetsPage = try? await API.get("/provider-grooming/pets", query: ["size": "1"]) {
            overdue = page.counts?.overdue
        }
    }

    /// Moving out of the waiting room starts the visit: a missing consent or deposit asks here (owners and admins can start anyway).
    private func move(_ item: SvcGroomItem, to stage: String) async {
        busyId = item.id
        defer { busyId = nil }
        do {
            let _: SvcIgnored = try await SvcAPI.send("PATCH", "/provider-appointments/\(item.id)/groom-stage", body: ["stage": stage])
            announceDataChanged()
        } catch {
            if let code = svcIsStartGate(error) {
                if workspace.isOwnerOrAdmin {
                    let id = item.id
                    gate = SvcStartGateRequest(code: code, petName: item.pet.name) { override in
                        let _: SvcIgnored = try await API.post("/provider-appointments/\(id)/start", body: override)
                        // A started groom is in the bath already.
                        if stage != "bath" { let _: SvcIgnored = try await API.patch("/provider-appointments/\(id)/groom-stage", body: ["stage": stage]) }
                    }
                } else {
                    Toast.error(svcMessage(error) + " " + L("Open the visit to see what it needs."))
                }
                return
            }
            Toast.error(svcMessage(error, codes: SvcRefusals.grooming))
        }
    }

    /// "Ready" told to the family once per Ready (the server keeps the stamp): in PawMiaw, or WhatsApp opened with the message.
    private func tell(_ item: SvcGroomItem, _ channel: String) async {
        busyId = item.id
        defer { busyId = nil }
        do {
            let result: SvcGroomReadyResult = try await SvcAPI.send("POST", "/provider-appointments/\(item.id)/groom-ready", body: ["channel": channel, "locale": svcLocale])
            if channel == "whatsapp", let link = result.link {
                svcOpen(link)
                Toast.show(L("WhatsApp is open with the message: send it from there."))
            } else {
                Toast.show(LF("%@ was told in PawMiaw that %@ is ready.", item.client.shortName, item.pet.name))
            }
            announceDataChanged()
        } catch {
            Toast.error(svcMessage(error, codes: SvcRefusals.grooming))
        }
    }
}

// MARK: - The board

/// The day's grooms by stage (web grooming-board.tsx): each stage a muted column
/// with its dot and count, its grooms as cards; done folds at the end, one line each.
private struct SvcGroomBoard: View {
    let today: SvcGroomingToday
    let simple: Bool
    let canStage: Bool
    let busyId: String?
    let push: (ProviderRoute) -> Void
    /// "New groom" in the empty state; nil when the member can't book.
    let onNewGroom: (() -> Void)?
    let onReport: (SvcGroomItem) -> Void
    let onMove: (SvcGroomItem, String) -> Void
    let onTell: (SvcGroomItem, String) -> Void
    @State private var showDone = false

    private var columns: [(stage: String, items: [SvcGroomItem])] {
        let stages = SvcGroomStage.visible(simple: simple)
        var grouped: [String: [SvcGroomItem]] = [:]
        for item in today.items {
            let stage = SvcGroomStage.shown(item.groomStage, simple: simple)
            grouped[stages.contains(stage) ? stage : "scheduled", default: []].append(item)
        }
        return stages.map { stage in
            (stage, (grouped[stage] ?? []).sorted { ($0.startsAt, $0.pet.name) < ($1.startsAt, $1.pet.name) })
        }
    }

    var body: some View {
        if today.items.isEmpty {
            EmptyState(systemImage: "scissors", title: L("No grooms today"), message: L("Today’s baths and haircuts appear here, each in its stage: waiting, in the bath, ready for pickup."),
                       actionTitle: onNewGroom == nil ? nil : L("New groom"), action: onNewGroom, accent: Theme.pink, panel: true)
        } else {
            let all = columns
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(all.filter { $0.stage != "done" }, id: \.stage) { column in stageColumn(column.stage, column.items) }
                }
                let done = all.first { $0.stage == "done" }?.items ?? []
                if !done.isEmpty { doneFold(done) }
            }
        }
    }

    private func stageColumn(_ stage: String, _ items: [SvcGroomItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: SvcGroomStage.label(stage, simple: simple), count: items.count, dot: ProviderState.groom(stage).color, style: .label, bubble: Theme.surface, showsZero: true)
                .padding(.horizontal, 14)
                .padding(.top, 12)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                if items.isEmpty {
                    Text(L("Nobody here"))
                        .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                } else {
                    ForEach(items) { item in
                        SvcGroomCard(item: item, simple: simple, timeZone: today.timeZone, canStage: canStage, busy: busyId == item.id, push: push, onReport: { onReport(item) }, onMove: { onMove(item, $0) }, onTell: { onTell(item, $0) })
                    }
                }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(Theme.surfaceMuted, 45), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(SvcGroomStage.label(stage, simple: simple))
    }

    /// Done is the quiet end of the day: folded, one line each.
    private func doneFold(_ done: [SvcGroomItem]) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showDone.toggle() }
            } label: {
                HStack(spacing: 8) {
                    SectionHeading(title: SvcGroomStage.label("done", simple: simple), count: done.count, dot: ProviderState.groom("done").color, style: .label, bubble: Theme.surfaceMuted, showsZero: true)
                    Spacer(minLength: 8)
                    Glyph("chevron-down", size: 16).foregroundStyle(Theme.inkSoft).rotationEffect(.degrees(showDone ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showDone {
                ForEach(done) { item in
                    RowDivider()
                    HStack(spacing: 12) {
                        Button { push(.patientChart(petId: item.pet.id)) } label: {
                            PetAvatar(name: item.pet.name, species: item.pet.species, photoURL: item.pet.photoUrl, size: 32)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 0) {
                            Button { push(.patientChart(petId: item.pet.id)) } label: {
                                Text(item.pet.name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            Text([item.serviceLabel, item.client.name, item.groomer?.name].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        SvcGroomBillingChip(billing: item.billing)
                        Button { push(.appointment(item.id)) } label: {
                            Text(L("Open visit")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        .listCard()
    }
}

/// Where a groom's bill stands (web `BillingChip`): its state's colour at 24%, a receipt.
private struct SvcGroomBillingChip: View {
    let billing: String?

    var body: some View {
        if let label = SvcBilling.label(billing) {
            Chip(text: label, tone: .custom(SvcBilling.state(billing).color), icon: "receipt", percent: 24)
        }
    }
}

// MARK: - One groom

/// A groom's card (web `GroomCard`): a 4 pt edge in its stage's colour, the pet
/// (photo and name open the chart), when and who, what needs someone, what was
/// asked, how to handle the pet, and one button for the next stage.
private struct SvcGroomCard: View {
    let item: SvcGroomItem
    let simple: Bool
    let timeZone: String?
    let canStage: Bool
    let busy: Bool
    let push: (ProviderRoute) -> Void
    let onReport: () -> Void
    let onMove: (String) -> Void
    let onTell: (String) -> Void

    private var stage: String { SvcGroomStage.shown(item.groomStage, simple: simple) }
    private var next: String? { SvcGroomStage.next(stage, simple: simple) }
    private var previous: String? { SvcGroomStage.previous(stage, simple: simple) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            top
            VStack(alignment: .leading, spacing: 4) {
                meta("clock-3", (item.carriedOver == true ? SvcTime.day(item.startsAt) + " · " : "") + SvcTime.clock(item.startsAt, timeZone) + " · " + (item.serviceLabel ?? ""), strong: true)
                meta("user-round", item.groomer?.name?.nonEmpty ?? L("No groomer yet"))
            }

            if let attention = item.attention {
                // What needs someone now: it stays until the pet goes home or the family is told.
                Chip(text: attentionText(attention), tone: .danger, icon: "triangle-alert")
            } else if item.carriedOver == true {
                // Booked for an earlier day and never handed over: it stays on the board until it goes home.
                Chip(text: L("Here since an earlier day"), tone: .custom(Theme.mango), icon: "clock-3", percent: 28)
            }

            if let asked = item.requestSummary?.nonEmpty {
                // What the owner asked for, in their words: the groomer reads it before the first cut.
                SvcAskedBox(text: asked)
            } else if let usual = item.usualStyle?.nonEmpty {
                (Text(L("Usual:") + " ").bold().foregroundStyle(Theme.inkSoft) + Text(usual).foregroundStyle(Theme.inkStrong))
                    .font(Theme.text(14)).lineLimit(2)
            }

            SvcHandlingChips(tags: item.handlingTags ?? [])
            if let notes = item.careNotes?.nonEmpty {
                Text(notes).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(2)
            }

            if stage == "ready" {
                FlowLayout(spacing: 6) {
                    if let told = item.readyNotifiedAt {
                        // Already told: so nobody messages the same family twice. The app delivers its notice;
                        // WhatsApp only opens with the message written — sending it is the person's.
                        Chip(text: item.readyChannel == "app"
                                    ? LF("Ready · told %@ · %@", stamp(told), "PawMiaw")
                                    : LF("Ready · WhatsApp opened %@", stamp(told)), tone: .custom(ProviderState.done.color), icon: "check-check", percent: 16)
                    } else {
                        Chip(text: L("Not told yet"), tone: .custom(Theme.mango), percent: 28)
                    }
                    SvcGroomBillingChip(billing: item.billing)
                }
            }

            footer
        }
        .padding(.vertical, 14)
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(alignment: .leading) { Rectangle().fill(ProviderState.groom(stage).color).frame(width: 4) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.borderSoft, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        .opacity(busy ? 0.85 : 1)
    }

    private var top: some View {
        HStack(alignment: .top, spacing: 10) {
            // The pet's photo and name open its chart, as everywhere.
            Button { push(.patientChart(petId: item.pet.id)) } label: {
                PetAvatar(name: item.pet.name, species: item.pet.species, photoURL: item.pet.photoUrl, size: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LF("Open %@’s chart", item.pet.name))
            VStack(alignment: .leading, spacing: 0) {
                Button { push(.patientChart(petId: item.pet.id)) } label: {
                    Text(item.pet.name).font(.brandHeading(18)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                }
                .buttonStyle(.plain)
                Text([item.client.name, item.pet.breed].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                if canStage, let previous {
                    Button { onMove(previous) } label: { GlyphLabel(LF("Back to %@", SvcGroomStage.label(previous, simple: simple)), icon: "undo-2") }
                }
                if ["bath", "styling", "ready"].contains(stage) {
                    // The report the family gets at the end of the groom (notes, before and after photos).
                    Button(action: onReport) { GlyphLabel(item.hasAfterPhoto == true ? L("Report") : L("Write report"), icon: "clipboard-pen") }
                }
                Button { push(.appointment(item.id)) } label: { GlyphLabel(L("Open visit"), icon: "external-link") }
            } label: {
                IconCircleLabel(size: 32, bordered: false)
            }
            .padding(.top, -4)
            .padding(.trailing, -4)
            .accessibilityLabel(LF("More for %@", item.pet.name))
        }
    }

    private func meta(_ icon: String, _ text: String, strong: Bool = false) -> some View {
        HStack(spacing: 6) {
            Glyph(icon, size: 14)
            Text(text).lineLimit(1)
        }
        .font(Theme.text(12, weight: strong ? .bold : .regular))
        .foregroundStyle(strong ? Theme.inkStrong : Theme.inkSoft)
    }

    /// The next stage, and at Ready telling the family and handing over (where it's charged).
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            RowDivider()
            FlowLayout(spacing: 8) {
                if stage == "scheduled" {
                    // Arrival (and its consents) is the visit's own step.
                    PMButton(L("Check in"), systemImage: "door-open", size: .header) { push(.appointment(item.id)) }
                }
                if let next, canStage {
                    PMButton(SvcGroomStage.moveLabel(to: next, from: stage, simple: simple), systemImage: "arrow-right", size: .header, isWorking: busy) { onMove(next) }
                }
                if stage == "ready" && !canStage {
                    PMButton(L("Hand over & charge"), systemImage: "receipt", size: .header) { push(.appointment(item.id)) }
                }
            }
            if stage == "ready" && canStage {
                FlowLayout(spacing: 8) {
                    Eyebrow(item.readyNotifiedAt != nil ? L("Tell again") : L("Tell them"), size: 12)
                    if item.client.phone?.nonEmpty != nil {
                        PMButton(L("WhatsApp"), systemImage: "message-circle", variant: .outline, size: .header) { onTell("whatsapp") }.disabled(busy)
                    }
                    if item.client.onPawMiaw == true {
                        PMButton("PawMiaw", systemImage: "smartphone", variant: .outline, size: .header) { onTell("app") }.disabled(busy)
                    }
                    if item.client.phone?.nonEmpty == nil && item.client.onPawMiaw != true {
                        Text(L("No phone, and not on PawMiaw.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
                // Handing the pet over is finishing the visit, and that is where it's charged.
                PMButton(L("Hand over & charge"), systemImage: "receipt", size: .header) { push(.appointment(item.id)) }
            }
            if !canStage && next != nil {
                Text(L("Your role can’t move grooms between stages.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func attentionText(_ attention: String) -> String {
        switch attention {
        case "carried_over": LF("Here since %@ · never handed over", SvcTime.day(item.startsAt))
        case "not_told": LF("Ready %@ ago · family not told", SvcTime.waited(item.readySince))
        default: LF("Ready %@ ago · not picked up", SvcTime.waited(item.readySince))
        }
    }

    /// When the family was told: the time, with its day when that wasn't today.
    private func stamp(_ iso: String) -> String {
        let time = SvcTime.clock(iso, timeZone)
        guard let date = DateText.parse(iso) else { return time }
        return DateText.dayKey(date, zone: SvcTime.zone(timeZone)) == DateText.dayKey(Date(), zone: SvcTime.zone(timeZone)) ? time : "\(SvcTime.day(iso)), \(time)"
    }
}
