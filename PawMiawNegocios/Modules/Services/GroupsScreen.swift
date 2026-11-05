//
//  GroupsScreen.swift
//  PawMiawNegocios
//
//  Paseos y clases (web: routes/provider.groups.tsx, components/app/groups/):
//  the day's group walks and classes run from here — who has a place, who
//  arrived or was picked up, the start and the finish for everyone, each
//  dog's report — then what is coming and what still needs its reports.
//  Each pet is still its own visit with its own bill.
//

import SwiftUI

struct GroupsScreen: View {
    var body: some View {
        SvcGroupsPage()
            .providerPage(L("Walks & classes"), root: true)
    }
}

private enum SvcGroupsTab: Hashable { case today, upcoming, past }

private struct SvcGroupsPage: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var tab: SvcGroupsTab = .today
    @State private var today: [SvcSession]?
    @State private var upcoming: [SvcSession]?
    @State private var past: [SvcSession]?
    @State private var failed: String?
    @State private var members: [SvcMember] = []
    @State private var planning = false
    @State private var pushed: SvcSessionRoute?

    private var canView: Bool { workspace.can(.appointmentsView) }
    private var canPlan: Bool { workspace.can(.appointmentsCreate) }

    var body: some View {
        if !canView {
            PageScroll { NoAccessState(message: L("Ask the workspace owner to let your role see appointments.")) }
        } else {
            page
        }
    }

    private var page: some View {
        PageScroll(refresh: { await load() }) {
            header
            ToneTabs(tabs: [
                .init(value: .today, title: L("Today"), icon: "calendar-days"),
                .init(value: .upcoming, title: L("Coming up"), icon: "calendar-clock"),
                .init(value: .past, title: L("Past"), icon: "history"),
            ], selection: $tab, look: .solid)

            switch tab {
            case .today:
                if let today {
                    if today.isEmpty {
                        EmptyState(systemImage: "dog", title: L("No group walks or classes today."), message: L("Plan one: families can take a place from the app, and you add the rest."),
                                   actionTitle: canPlan ? L("New session") : nil, action: { planning = true }, accent: Theme.lime, panel: true)
                    } else {
                        VStack(spacing: 16) {
                            ForEach(today) { session in
                                SvcTodaySessionCard(sessionId: session.id, push: { pushed = $0 })
                            }
                        }
                    }
                } else if failed != nil {
                    SvcLoadError(message: L("The sessions couldn’t be loaded.")) { await load() }
                } else {
                    LoadingState()
                }
            case .upcoming:
                SvcSessionDays(sessions: upcoming, past: false, canPlan: canPlan, onPlan: { planning = true }, onOpen: { pushed = .session($0) })
            case .past:
                SvcSessionDays(sessions: past, past: true, canPlan: false, onPlan: {}, onOpen: { pushed = .session($0) })
            }
        }
        .navigationDestination(item: $pushed) { route in
            switch route {
            case .session(let id): SvcSessionScreen(sessionId: id)
            case .provider(let provider): RouteView(route: provider)
            }
        }
        .sheet(isPresented: $planning) {
            SvcSessionFormSheet(session: nil, people: svcSessionLeaders(members, workspace: workspace)) { saved in pushed = .session(saved) }
        }
        .reloadsOnScope { await load() }
        .task { members = await svcLoadMembers(workspace) }
    }

    // MARK: Header

    private var header: some View {
        let todayList = today ?? []
        let dogs = todayList.reduce(0) { $0 + $1.size }
        let waiting = (todayList + (upcoming ?? [])).reduce(0) { $0 + ($1.waitlistCount ?? 0) }
        let reports = (todayList + (past ?? [])).reduce(0) { $0 + ($1.reportsMissing ?? 0) }
        return ModuleHeader(
            icon: "users-round",
            title: L("Walks & classes"),
            subtitle: L("Group walks and classes: who comes, who arrived and their reports"),
            accent: Theme.lime,
            stats: [
                ModuleStat("today", label: L("Today"), value: today.map { "\($0.count)" } ?? "—", hint: today == nil ? nil : LP(dogs, "1 dog", "%d dogs"),
                           icon: "calendar-days", accent: Theme.lime, active: tab == .today, action: { tab = .today }),
                ModuleStat("waiting", label: L("Waitlist"), value: upcoming == nil ? "—" : "\(waiting)", icon: "hourglass", accent: Theme.mango,
                           attention: waiting > 0, active: tab == .upcoming, action: { tab = .upcoming }),
                ModuleStat("reports", label: L("Reports to fill"), value: past == nil ? "—" : "\(reports)", icon: "clipboard-list", accent: Theme.pink,
                           attention: reports > 0, active: tab == .past, action: { tab = .past }),
            ],
            storageKey: "groups"
        ) {
            if canPlan {
                PMButton(L("New session"), systemImage: "plus") { planning = true }
            }
        }
    }

    /// Today, the next two weeks, the last two weeks (the server takes up to two months at a time).
    private func load() async {
        let calendar = DateText.calendar
        let start = calendar.startOfDay(for: Date())
        func day(_ offset: Int) -> String { DateText.iso(calendar.date(byAdding: .day, value: offset, to: start) ?? start) }
        func fetch(_ from: String, _ to: String) async throws -> [SvcSession] {
            try await API.get("/provider-sessions", query: ["from": from, "to": to, "locationId": workspace.locationId])
        }
        do {
            today = try await fetch(day(0), day(1))
            failed = nil
        } catch is CancellationError {
            return
        } catch {
            if today == nil { failed = errorText(error) }
        }
        upcoming = (try? await fetch(day(1), day(15))) ?? upcoming
        past = (try? await fetch(day(-14), day(0))) ?? past
    }
}

/// Where the page pushes: a session of its own, or a visit, a client.
enum SvcSessionRoute: Hashable {
    case session(String)
    case provider(ProviderRoute)
}

/// Who can lead a session: the people who take visits here (only oneself for someone who sees just their own).
@MainActor
func svcSessionLeaders(_ members: [SvcMember], workspace: Workspace) -> [SvcMember] {
    let here = workspace.locationId.map { location in members.filter { ($0.locationIds ?? []).isEmpty || ($0.locationIds ?? []).contains(location) } } ?? members
    let takers = here.filter { $0.can(.appointmentsComplete) }
    let anyone = workspace.can(.appointmentsAssignAnyone)
    return (takers.isEmpty ? here : takers).filter { anyone || $0.isCurrentMember == true }
}

// MARK: - Sessions by day

/// Sessions by day (web `SessionDays`): what's coming (with places and the
/// waitlist), or what passed (with reports to fill), one card per day.
private struct SvcSessionDays: View {
    let sessions: [SvcSession]?
    let past: Bool
    let canPlan: Bool
    let onPlan: () -> Void
    let onOpen: (String) -> Void

    var body: some View {
        if let sessions {
            if sessions.isEmpty {
                EmptyState(systemImage: past ? "history" : "calendar-clock",
                           title: past ? L("No group walks or classes in the last two weeks.") : L("Nothing planned for the next two weeks."),
                           actionTitle: !past && canPlan ? L("New session") : nil, action: onPlan, accent: Theme.lime, panel: true)
            } else {
                let days = Dictionary(grouping: sessions) { DateText.dayKey(DateText.parse($0.startsAt) ?? Date()) }
                let keys: [String] = past ? days.keys.sorted(by: >) : days.keys.sorted()
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(keys, id: \.self) { key in
                        let list = (days[key] ?? []).sorted { past ? $0.startsAt > $1.startsAt : $0.startsAt < $1.startsAt }
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(SvcTime.shortDay(list.first?.startsAt), size: 12)
                            VStack(spacing: 0) {
                                ForEach(list) { session in
                                    if session.id != list.first?.id { RowDivider() }
                                    Button { onOpen(session.id) } label: { row(session) }.buttonStyle(.plain)
                                }
                            }
                            .listCard()
                        }
                    }
                }
            }
        } else {
            LoadingState()
        }
    }

    private func row(_ session: SvcSession) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(DateText.time(session.startsAt)).font(.brandHeading(14)).monospacedDigit().foregroundStyle(Theme.inkStrong).frame(width: 72, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.serviceLabel).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                FlowLayout(spacing: 8) {
                    if let leader = session.assignedMember?.name { meta("user-round", leader) }
                    if session.isPickup { meta("house", L("Picked up at home")) }
                    else if let point = session.meetingPoint?.nonEmpty { meta("map-pin", point) }
                    if !session.active { Text(L("Session · Cancelled")).foregroundStyle(Theme.destructive) }
                }
                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PetStack(pets: session.staying.map { ($0.name, $0.species, $0.photoUrl) }, size: 32, max: 3)
            VStack(alignment: .trailing, spacing: 0) {
                Text(session.placesText).monospacedDigit().foregroundStyle(Theme.inkStrong)
                if past, let missing = session.reportsMissing, missing > 0 {
                    Text(LF("%d reports to fill", missing)).foregroundStyle(Theme.pink)
                } else if let waiting = session.waitlistCount, waiting > 0 {
                    Text(LF("%d waiting", waiting)).foregroundStyle(Theme.inkSoft)
                }
            }
            .font(Theme.text(12, weight: .bold))
            Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(session.active ? 1 : 0.6)
        .contentShape(Rectangle())
    }

    private func meta(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Glyph(icon, size: 12)
            Text(text).lineLimit(1)
        }
    }
}

// MARK: - One of today's sessions, run where it shows

/// One of the day's sessions, run where it shows (web `TodaySessionCard`, on
/// Walks & classes and on Domicilio for a walk that picks its dogs up): its dogs,
/// who arrived or was picked up, the start and finish, and the group report.
struct SvcTodaySessionCard: View {
    let sessionId: String
    let push: (SvcSessionRoute) -> Void

    @EnvironmentObject private var workspace: Workspace
    @State private var session: SvcSessionDetail?
    @State private var failed: String?

    var body: some View {
        Group {
            if let session {
                card(session)
            } else if failed != nil {
                SvcLoadError(message: L("This session couldn’t be loaded.")) { await load() }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 192)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            }
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .pawMiawDataChanged)) { _ in Task { await load() } }
    }

    private func card(_ session: SvcSessionDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Glyph(session.serviceCategory == "trainer" ? "graduation-cap" : "dog", size: 20)
                    .foregroundStyle(Theme.inkStrong)
                    .frame(width: 44, height: 44)
                    .background(Theme.wash(Theme.lime, 35), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.serviceLabel).font(.brandHeading(18)).foregroundStyle(Theme.inkStrong)
                    Text("\(DateText.time(session.startsAt)) – \(DateText.time(session.endsAt))" + (session.assignedMember?.name.map { " · \($0)" } ?? ""))
                        .font(Theme.text(14)).monospacedDigit().foregroundStyle(Theme.inkSoft)
                    FlowLayout(spacing: 12) {
                        if session.isPickup { meta("house", LF("Picked up at home · %d stops", session.staying.count)) }
                        else if let point = session.meetingPoint?.nonEmpty { meta("map-pin", point) }
                        meta("users-round", session.placesText)
                        if let waiting = session.waitlistCount, waiting > 0 { meta("hourglass", LF("%d waiting", waiting)) }
                        if !session.active { Text(L("Session · Cancelled")).foregroundStyle(Theme.destructive) }
                    }
                    .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PMButton(L("Details"), systemImage: "chevron-right", variant: .outline, size: .header) { push(.session(session.id)) }
            }
            .padding(16)
            RowDivider()
            VStack(alignment: .leading, spacing: 8) {
                if session.pets.isEmpty {
                    Text(L("No pets yet. Add them from the details, or families take a place from the app.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                } else {
                    if session.active && session.booked > 0 && session.withThem + session.doneCount == 0 {
                        Text(session.isPickup ? LF("%d of %d picked up", session.arrived, session.booked + session.arrived) : LF("%d of %d here", session.arrived, session.booked + session.arrived))
                            .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    }
                    SvcSessionRoster(session: session, push: push) { await load() }
                }
            }
            .padding(16)
            if session.active && workspace.can(.appointmentsComplete) && (session.withThem + session.doneCount + session.arrived + session.booked) > 0 {
                RowDivider()
                SvcSessionMoveButtons(session: session, canRun: true) { await load() }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(12)
            }
        }
        .listCard()
        .opacity(session.active ? 1 : 0.7)
    }

    private func meta(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Glyph(icon, size: 14)
            Text(text).lineLimit(1)
        }
    }

    private func load() async {
        do {
            session = try await API.get("/provider-sessions/\(sessionId)")
            failed = nil
        } catch is CancellationError {
        } catch {
            failed = errorText(error)
        }
    }
}

// MARK: - The day's group sessions on Domicilio

/// The day's group walks and classes on Domicilio, the day's route (web: groups/group-sessions-pointer.tsx).
/// A walk that picks its dogs up is part of the route: its stops in order, "on my way", picked up, the start
/// and the finish, right here. One that meets somewhere is a line that opens Walks & classes.
struct SvcGroupSessionsPointer: View {
    let dayKey: String
    let timeZone: String?
    let push: (SvcSessionRoute) -> Void

    @EnvironmentObject private var workspace: Workspace
    @State private var sessions: [SvcSession] = []

    var body: some View {
        let active = sessions.filter(\.active)
        let pickups = active.filter(\.isPickup)
        let meeting = active.filter { !$0.isPickup }
        VStack(alignment: .leading, spacing: 12) {
            if !pickups.isEmpty {
                Text(L("Group walks with pickup").uppercased()).font(.brandText(12, weight: .heavy)).tracking(12 * 0.14).foregroundStyle(Theme.blue)
                ForEach(pickups) { session in SvcTodaySessionCard(sessionId: session.id, push: push) }
            }
            if !meeting.isEmpty {
                let dogs = meeting.reduce(0) { $0 + $1.staying.count }
                Button { push(.provider(.section(.groups))) } label: {
                    HStack(spacing: 12) {
                        Glyph("dog", size: 20).foregroundStyle(Theme.blue)
                            .frame(width: 40, height: 40).background(Theme.wash(Theme.aqua, 22), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meeting.count == 1 ? L("A group session at a meeting point") : LF("%d group sessions at a meeting point", meeting.count))
                                .font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            Text(LF("Dogs: %d. Arrivals and reports are in Walks & classes.", dogs)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Glyph("chevron-right", size: 20).foregroundStyle(Theme.inkSoft)
                    }
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.blue, 45, with: Theme.borderSoft), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: "\(dayKey)|\(workspace.scopeVersion)") { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .pawMiawDataChanged)) { _ in Task { await load() } }
    }

    /// The business's day, midnight to midnight on its clock.
    private func load() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = SvcTime.zone(timeZone)
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        if let loaded: [SvcSession] = try? await API.get("/provider-sessions", query: ["from": DateText.iso(start), "to": DateText.iso(end), "locationId": workspace.locationId]) {
            sessions = loaded
        }
    }
}

// MARK: - A session's next move

/// A session's next move (web `SessionMoveButtons`): start with the pets that
/// arrived (or "everyone came"), finish for every pet with them, and the group report.
struct SvcSessionMoveButtons: View {
    let session: SvcSessionDetail
    let canRun: Bool
    let reload: () async -> Void

    @State private var working = false
    @State private var reporting = false

    var body: some View {
        if session.active && canRun {
            FlowLayout(spacing: 8) {
                if session.withThem + session.doneCount > 0 {
                    PMButton(L("Group report"), systemImage: "clipboard-check", variant: .outline) { reporting = true }
                }
                if session.withThem > 0 {
                    // Arrived after the start (marked from somewhere else): bring them in before finishing.
                    if session.arrived > 0 {
                        PMButton(LF("Bring in the late ones (%d)", session.arrived), systemImage: "play", variant: .outline) { run("start") }.disabled(working)
                    }
                    PMButton(L("Finish for everyone"), systemImage: "badge-check", isWorking: working) { run("finish") }
                } else if session.arrived + session.booked > 0 {
                    // Starts with whoever arrived; "everyone came" checks the rest in on the way.
                    if session.booked > 0 {
                        let total = session.arrived + session.booked
                        PMButton(session.isPickup
                                 ? (session.arrived > 0 ? LF("All picked up: start all %d", total) : L("All picked up: start"))
                                 : (session.arrived > 0 ? LF("Everyone came: start all %d", total) : L("Everyone came: start")),
                                 systemImage: "play", variant: .outline) { run("start", everyone: true) }
                            .disabled(working)
                    }
                    if session.arrived > 0 {
                        PMButton(session.isPickup ? LF("Start the walk with %d", session.arrived) : LF("Start with those here (%d)", session.arrived), systemImage: "play", isWorking: working) { run("start") }
                    }
                }
            }
            .sheet(isPresented: $reporting) {
                SvcGroupReportSheet(session: session) { Task { await reload() } }
            }
        }
    }

    private func run(_ action: String, everyone: Bool = false) {
        working = true
        Task {
            defer { working = false }
            do {
                let result: SvcSessionMoveResult = try await SvcAPI.send("POST", "/provider-sessions/\(session.id)/\(action)", body: everyone ? ["everyone": true] : [:])
                let moved = result.moved?.count ?? 0
                if action == "start" {
                    Toast.show(moved == 1 ? L("Started with 1 pet.") : LF("Started with %d pets.", moved))
                } else {
                    Toast.show(moved == 1 ? L("Finished for 1 pet. Its family has its bill.") : LF("Finished for %d pets. Each family has its own bill.", moved))
                }
                if let skipped = result.skipped?.first?.error { Toast.error(skipped) }
                announceDataChanged()
                await reload()
            } catch {
                Toast.error(svcCode(error) == "nobody_arrived" ? L("Mark who arrived first, or start with everyone.") : svcMessage(error))
            }
        }
    }
}
