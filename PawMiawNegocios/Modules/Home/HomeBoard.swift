//
//  HomeBoard.swift
//  PawMiawNegocios
//
//  The day's board (web components/app/today/today-board.tsx): families on
//  their way with an emergency first; ‹ Hoy › on a phone's own line; the
//  "Hoy" header with the day's activities as tiles (or, for a business that
//  only sees visits, the visits' four numbers as the agenda's filter); the
//  Agenda card — Todos | Mías and "⋯", the state tabs, a service filter, the
//  sections ("AHORA", "POR COBRAR", "PRÓXIMAS", grooms, stays, the hospital,
//  home visits) and "Listo · 3" — and "Te necesita" beside it (below it on a
//  phone). Home is a summary: each part shows a few rows and "Ver todo"
//  opens its page.
//

import SwiftUI

/// Rows each part of the board shows before "Ver todo".
enum HomeCap {
    static let rows = 5
}

struct HomeBoard: View {
    let today: HomeToday
    @ObservedObject var model: HomeModel
    let open: (ProviderRoute) -> Void
    /// ‹ Hoy ›: another day opens in place; nil when this role can't see the agenda.
    var changeDay: ((String?) -> Void)? = nil

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(HomeActions.self) private var actions: HomeActions?
    @State private var lens: HomeLens = .everyone
    @State private var filter: HomeLane?
    @State private var saved: HomeActivity?
    @State private var service: String?
    @State private var showDone = false
    @State private var width: CGFloat = 0

    private var permissions: HomePermissions { HomePermissions(workspace) }
    private var categories: [String] { workspace.current?.enabledCategories ?? [] }
    private var memberId: String? { today.viewer?.memberId }
    private var activityKey: String? { HomeActivityStore.key(workspace.current?.clinicId, memberId) }
    private var phone: Bool { sizeClass != .regular }
    /// The agenda and "Te necesita" side by side once there is room (web `xl`).
    private var sideBySide: Bool { width >= 940 }

    /// Booking takes creating visits and seeing clients; a walk-in also checking in.
    private var canBook: Bool { permissions.create && permissions.clients }
    private var canWalkIn: Bool { canBook && permissions.checkIn }

    // MARK: Modules and activity

    private var modules: [HomeActivity] {
        let sent = (today.hub?.modules ?? ["appointments"]).compactMap(HomeActivity.init(rawValue:))
        return sent.filter { !($0 == .grooming && model.groomingFailed) }
    }

    private var options: [HomeActivity] { HomeActivity.options(modules) }
    /// With more than one activity the header chooses the activity and the agenda has its own state tabs.
    private var hubHeader: Bool { options.count > 1 }

    private var activity: HomeActivity {
        if let saved, options.contains(saved) { return saved }
        if let stored = HomeActivityStore.read(activityKey), options.contains(stored) { return stored }
        return options.first ?? .all
    }

    private var showsVisits: Bool { modules.contains(.appointments) && activity.shows(.appointments) }
    private var entries: [HomeHubEntry] { today.hub?.entries ?? [] }
    private var allVisits: [HomeVisit] { today.allVisits }

    /// Under Todos, a patient whose visit is still on the agenda shows once — as the visit.
    private func hubEntries(for activity: HomeActivity) -> [HomeHubEntry] {
        let onAgenda = Set(allVisits.filter { [.upcoming, .waiting, .inService].contains($0.laneValue) }.map(\.id))
        return entries.filter { entry in
            guard let module = HomeActivity(rawValue: entry.module ?? ""), activity.shows(module) else { return false }
            if activity == .all, let source = entry.sourceAppointmentId, onAgenda.contains(source) { return false }
            return true
        }
    }

    private var hospitalized: Set<String> {
        Set(entries.filter { $0.module == "hospital" }.compactMap(\.sourceAppointmentId))
    }

    private func count(_ option: HomeActivity) -> Int {
        let seen = allVisits.filter { $0.laneValue != .missed }
        switch option {
        case .all: return seen.count + hubEntries(for: .all).count
        case .appointments: return seen.count
        case .grooming: return seen.filter { $0.serviceCategory == "groomer" }.count
        case .home: return model.homeVisits?.counts?.total ?? entries.filter { $0.module == "home" }.count
        default: return entries.filter { $0.module == option.rawValue }.count
        }
    }

    /// The tile's second line: the one thing about that activity worth knowing at a glance.
    private func hint(_ option: HomeActivity) -> String? {
        let counts = today.counts
        switch option {
        case .appointments:
            if let late = counts?.late, late > 0 { return LF("%d running late", late) }
            if let missed = counts?.missed, missed > 0 { return LF("%d missed@home", missed) }
            return nil
        case .grooming:
            let needing = groomsNeeding.count
            if needing > 0 { return LF("%d need you", needing) }
            let ready = (model.grooming?.items ?? []).filter { $0.groomStage == "ready" }.count
            return ready > 0 ? LF("%d ready for pickup", ready) : nil
        case .stays:
            let of = entries.filter { $0.module == "stays" }
            let late = of.filter { $0.late == true }.count
            let leaving = of.filter { $0.status == "leaving" }.count
            if late > 0 { return LF("%d late@stays", late) }
            return leaving > 0 ? LF("%d leaving today", leaving) : nil
        case .hospital:
            let due = entries.filter { $0.module == "hospital" }.reduce(0) { $0 + ($1.attention ?? 0) }
            if due == 0 { return nil }
            return due == 1 ? L("1 treatment needs someone") : LF("%d treatments need someone", due)
        case .home:
            let late = model.homeVisits?.counts?.late ?? entries.filter { $0.module == "home" && $0.late == true }.count
            return late > 0 ? LF("%d late@stays", late) : nil
        case .all:
            return nil
        }
    }

    private func attention(_ option: HomeActivity) -> Bool {
        switch option {
        case .appointments: return (today.counts?.late ?? 0) > 0
        case .grooming: return !groomsNeeding.isEmpty
        case .all: return false
        case .home:
            if let late = model.homeVisits?.counts?.late { return late > 0 }
            return entries.contains { $0.module == "home" && $0.late == true }
        default: return entries.contains { $0.module == option.rawValue && $0.late == true }
        }
    }

    /// Only a tile the person picks is remembered; a switch made for them (a visit filter) lasts until they leave.
    private func pick(_ option: HomeActivity, remember: Bool = true) {
        saved = option
        if remember { HomeActivityStore.save(activityKey, option) }
        if option != .appointments { service = nil }
    }

    private func pickFilter(_ next: HomeLane?) {
        filter = next
        if !showsVisits { pick(.appointments, remember: false) }
    }

    // MARK: Visits

    private var showsLens: Bool { today.viewer?.seesAllVisits == true && permissions.start && memberId != nil }

    private var serviceOptions: [String] {
        var seen: [String] = []
        for visit in allVisits { if let category = visit.serviceCategory, !seen.contains(category) { seen.append(category) } }
        return seen
    }

    private var activeService: String? {
        guard activity == .appointments, let service, serviceOptions.contains(service) else { return nil }
        return service
    }

    private func visible(_ visit: HomeVisit) -> Bool {
        let mine = lens == .everyone || visit.assigned?.id == nil || visit.assigned?.id == memberId
        return mine && (activeService == nil || visit.serviceCategory == activeService)
    }

    private func lane(_ key: HomeLane) -> [HomeVisit] { today.lane(key).filter(visible) }

    private var groomsNeeding: [HomeGroomItem] { (model.grooming?.items ?? []).filter { $0.attention != nil } }
    private var lateHomeVisits: [HomeHomeVisit] { (model.homeVisits?.items ?? []).filter { $0.late == true } }

    private var longestWait: Int? { today.lane(.waiting).compactMap(\.waitingMinutes).max() }

    // MARK: Body

    var body: some View {
        let needs = HomeNeedsYou(today: today, model: model, permissions: permissions, grooms: groomsNeeding, lateHome: lateHomeVisits, open: open)
        VStack(alignment: .leading, spacing: 16) {
            let arrivals = (today.arrivals ?? []).filter(\.isOpen)
            if !arrivals.isEmpty {
                HomeArrivalsBlock(arrivals: arrivals, canAct: permissions.checkIn)
            }
            // A phone: the day switcher on its own line (the header's buttons stay on one).
            if phone, let switcher { switcher }
            header
            if sideBySide {
                HStack(alignment: .top, spacing: 16) {
                    board.frame(maxWidth: .infinity, alignment: .top)
                    if needs.hasAnything { needs.frame(width: 352) }
                }
            } else {
                board
                if needs.hasAnything { needs }
            }
            // "All clear" only when it is: never under a late visit or a groom that needs someone.
            if !needs.hasAnything {
                HStack(spacing: 6) {
                    Glyph("badge-check", size: 16).foregroundStyle(Theme.blue)
                    Text(L("All clear. Nothing else needs you today.")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                }
                .padding(.horizontal, 4)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .opacity(model.loading && model.today == nil ? 0.7 : 1)
    }

    private var switcher: DayStepper? {
        guard let changeDay, let date = today.date else { return nil }
        return homeDayStepper(date: date, today: date, onChange: changeDay)
    }

    // MARK: The "Hoy" header

    @ViewBuilder
    private var header: some View {
        let hasActions = canBook || (!phone && switcher != nil)
        if hasActions {
            ModuleHeader(icon: "calendar-clock", title: L("Today"), subtitle: HomeDayKey.long(today.date), accent: Theme.blue, stats: stats, storageKey: "home") {
                if !phone, let switcher { switcher }
                if canWalkIn, let actions {
                    PMButton(L("Walk-in"), systemImage: "zap", variant: .outline) { actions.walkIn() }
                }
                if canBook, let actions {
                    PMButton(L("New appointment"), systemImage: "calendar-plus") { actions.newAppointment() }
                }
            }
        } else {
            ModuleHeader(icon: "calendar-clock", title: L("Today"), subtitle: HomeDayKey.long(today.date), accent: Theme.blue, stats: stats, storageKey: "home")
        }
    }

    private var stats: [ModuleStat] {
        if hubHeader {
            // What the day holds, by activity. The visit states live in the agenda.
            return options.map { option in
                ModuleStat(option.rawValue, label: option.label, value: "\(count(option))", hint: hint(option), icon: option.icon,
                           accent: option.accent, attention: attention(option), active: activity == option,
                           action: { pick(option); filter = nil })
            }
        }
        guard modules.contains(.appointments) else { return [] }
        // Only visits here: the header's numbers are the agenda's filter.
        let counts = today.counts
        let late = counts?.late ?? 0, missed = counts?.missed ?? 0
        return [
            ModuleStat("visits", label: L("Visits today"), value: "\(counts?.total ?? 0)",
                       hint: late > 0 ? LF("%d running late", late) : (missed > 0 ? LF("%d missed@home", missed) : nil),
                       icon: "calendar-clock", accent: Theme.aqua, attention: late > 0, active: filter == nil, action: { pickFilter(nil) }),
            ModuleStat("waiting", label: L("Waiting@home"), value: "\(counts?.waiting ?? 0)", hint: longestWait.map { LF("Longest %d min", $0) },
                       icon: "clock-3", accent: Theme.mango, attention: (longestWait ?? 0) >= 20, active: filter == .waiting,
                       action: { pickFilter(filter == .waiting ? nil : .waiting) }),
            ModuleStat("in", label: HomeText.inServiceTitle(categories), value: "\(counts?.inService ?? 0)", icon: "stethoscope", accent: Theme.blue,
                       active: filter == .inService, action: { pickFilter(filter == .inService ? nil : .inService) }),
            ModuleStat("pay", label: L("To pay"), value: "\(counts?.toPay ?? 0)",
                       hint: today.collectedToday.map { LF("%@ collected today", Money.format($0, currency: today.currency)) },
                       icon: "hand-coins", accent: Theme.pink, active: filter == .toPay,
                       action: { pickFilter(filter == .toPay ? nil : .toPay) }),
        ]
    }

    // MARK: The Agenda card

    private var boardTitle: String {
        if let filter { return filter == .inService ? HomeText.inServiceTitle(categories) : (filter == .waiting ? L("Waiting@home") : L("To pay")) }
        return activity == .all || activity == .appointments ? L("Schedule@home") : activity.label
    }

    @ViewBuilder
    private var boardTrailing: some View {
        HStack(spacing: 6) {
            if filter != nil && !hubHeader {
                Button { filter = nil } label: { Chip(text: L("See everything"), tone: .muted, icon: "x") }
                    .buttonStyle(.plain)
            }
            if showsLens && showsVisits {
                Segmented(options: [.init(HomeLens.everyone, L("Everyone@home")), .init(HomeLens.mine, L("Mine"))], selection: $lens, look: .raised, label: L("Whose"))
            }
            if permissions.reassign && showsVisits, let actions, let date = today.date {
                Menu {
                    Button { actions.reassignDay(date) } label: { GlyphLabel(L("Someone is off? Move their day"), icon: "users") }
                } label: {
                    IconCircleLabel(size: 32, bordered: false)
                }
            }
        }
    }

    private var board: some View {
        SectionCard(title: boardTitle, trailing: { boardTrailing }) {
            VStack(alignment: .leading, spacing: 0) {
                if hubHeader && showsVisits {
                    // Where each visit is: the agenda's own tabs, under its title.
                    StatusTabs(options: [
                        (value: HomeLaneFilter.all, title: L("Everything"), count: Optional(today.counts?.total ?? 0)),
                        (value: HomeLaneFilter.waiting, title: L("Waiting@home"), count: Optional(today.counts?.waiting ?? 0)),
                        (value: HomeLaneFilter.inService, title: HomeText.inServiceTitle(categories), count: Optional(today.counts?.inService ?? 0)),
                        (value: HomeLaneFilter.toPay, title: L("To pay"), count: Optional(today.counts?.toPay ?? 0)),
                    ], selection: Binding(get: { HomeLaneFilter(filter) }, set: { filter = $0.lane }))
                    RowDivider()
                }
                if activity == .appointments && serviceOptions.count > 1 {
                    StatusTabs(options: [(value: String?.none, title: L("Every service"), count: Int?.none)]
                               + serviceOptions.map { (value: Optional($0), title: HomeServiceName.label($0), count: Int?.none) },
                               selection: Binding(get: { activeService }, set: { service = $0 }))
                    RowDivider()
                }
                if showsVisits { visitGroups }
                if modules.contains(.grooming) && activity.shows(.grooming) && filter == nil {
                    // Under Todos the grooms are agenda rows already: only their stage counts. Under Estética, each one with its next step.
                    HomeGroomingSection(data: model.grooming, full: activity == .grooming)
                }
                ForEach([HomeActivity.stays, .hospital, .home], id: \.self) { module in
                    if modules.contains(module) && activity.shows(module) && filter == nil {
                        // Under its own tile Domicilio is the Home visits day list, with "Llegué" and "Terminar".
                        if module == .home && activity == .home && model.homeVisitsDay != nil {
                            HomeHomeVisitsSection(day: model.homeVisitsDay)
                        } else {
                            HomeHubSection(module: module, entries: hubEntries(for: activity).filter { $0.module == module.rawValue }, memberId: memberId, showEmpty: activity == module)
                        }
                    }
                }
                if activity == .all && !showsVisits && hubEntries(for: .all).isEmpty {
                    EmptyState(systemImage: "badge-check", title: L("Nothing here right now."), accent: Theme.blue)
                }
                if filter == nil && showsVisits {
                    doneSection
                }
            }
        }
    }

    private struct VisitGroup: Identifiable {
        let id: String
        let title: String
        let color: Color
        let visits: [HomeFoldedVisit]
        let sessions: [HomeSession]
    }

    /// The agenda in the order the day needs it: who is here now, who pays, who comes next.
    private var groups: [VisitGroup] {
        let inSession: (HomeVisit) -> Bool = { visit in
            visit.group?.kind == "session" && [.upcoming, .waiting, .inService].contains(visit.laneValue)
        }
        let sessions = (today.sessions ?? []).filter { $0.status == "active" }
        func sessionKey(_ session: HomeSession) -> (group: String, lane: HomeLane)? {
            let staying = session.staying
            let live = staying.contains { $0.status == "in_progress" || $0.status == "checked_in" }
            let ahead = staying.contains { $0.status == "scheduled" } || staying.isEmpty
            let lane: HomeLane = staying.contains { $0.status == "in_progress" } ? .inService : (live ? .waiting : .upcoming)
            if let filter, filter != lane { return nil }
            return live ? ("now", lane) : (ahead ? ("upcoming", lane) : nil)
        }
        let definitions: [(String, String, Color, [HomeLane])] = [
            ("now", L("Now@home"), Theme.blue, [.inService, .waiting]),
            ("to_pay", L("To pay"), Theme.pink, [.toPay]),
            ("upcoming", L("Upcoming@home"), Theme.aqua, [.upcoming]),
        ]
        return definitions.compactMap { key, title, color, lanes in
            if let filter, !lanes.contains(filter) { return nil }
            let visits = lanes.flatMap { lane($0) }.filter { (filter == nil || $0.laneValue == filter) && !inSession($0) }
            let folded = HomeFold.together(HomeFold.sorted(visits))
            let groupSessions = sessions.filter { sessionKey($0)?.group == key }
            guard !folded.isEmpty || !groupSessions.isEmpty else { return nil }
            return VisitGroup(id: key, title: title, color: color, visits: folded, sessions: groupSessions)
        }
    }

    private enum GroupRow: Identifiable {
        case session(HomeSession)
        case visit(HomeFoldedVisit)
        var id: String {
            switch self {
            case .session(let session): "session-\(session.id)"
            case .visit(let folded): folded.id
            }
        }
    }

    @ViewBuilder
    private var visitGroups: some View {
        let groups = groups
        if groups.isEmpty {
            // Under Todos, the other activities below speak for the day.
            let hubShown = activity == .all && !hubEntries(for: .all).isEmpty
            if !hubShown {
                let nothingToday = filter == nil && lane(.done).count + lane(.missed).count == 0
                VStack(spacing: 0) {
                    EmptyState(
                        systemImage: nothingToday ? "calendar-clock" : "badge-check",
                        title: nothingToday ? L("Nothing booked for today") : (filter == nil ? L("Everyone has been seen") : HomeBoard.emptyText(filter)),
                        message: nothingToday ? L("Walk-ins and new bookings show up here as they come.") : L("Finished visits are below."),
                        accent: Theme.blue
                    )
                    if nothingToday {
                        FlowLayout(spacing: 8) {
                            if canWalkIn, let actions {
                                PMButton(L("Walk-in"), systemImage: "zap", variant: .outline, size: .header) { actions.walkIn() }
                            }
                            if canBook, let actions {
                                PMButton(L("New appointment"), systemImage: "calendar-plus", size: .header) { actions.newAppointment() }
                            }
                            NavigationLink(value: ProviderRoute.section(.schedule)) {
                                PMButtonContent(title: L("Open the schedule"), icon: "calendar-days", variant: .link, size: .slim)
                            }
                            .buttonStyle(.pm(.link, size: .slim))
                        }
                        .padding(.top, -12)
                        .padding(.bottom, 24)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            ForEach(groups) { group in
                let rows = group.sessions.map(GroupRow.session) + group.visits.map(GroupRow.visit)
                HomeStrip(storageKey: "board:\(group.id)", title: group.title, count: rows.count, dot: group.color) {
                    RowList(items: Array(rows.prefix(HomeCap.rows))) { row in
                        switch row {
                        case .session(let session):
                            HomeSessionRow(session: session, stateLabel: HomeText.laneLabel(sessionLane(session), categories: categories))
                        case .visit(let folded):
                            HomeVisitRow(
                                visit: folded.visit,
                                together: folded.together,
                                stateLabel: stateLabel(folded.visit),
                                hospitalized: hospitalized.contains(folded.visit.id),
                                compact: false,
                                permissions: permissions,
                                categories: categories,
                                open: open
                            )
                        }
                    }
                    if rows.count > HomeCap.rows {
                        HomeStripMore(more: rows.count - HomeCap.rows, route: .section(.schedule))
                    }
                }
            }
        }
    }

    private func sessionLane(_ session: HomeSession) -> HomeLane {
        let staying = session.staying
        if staying.contains(where: { $0.status == "in_progress" }) { return .inService }
        if staying.contains(where: { $0.status == "checked_in" }) { return .waiting }
        return .upcoming
    }

    /// The row's one-word state (a groom under way says its stage itself, in the row).
    private func stateLabel(_ visit: HomeVisit) -> String {
        HomeText.laneLabel(visit.laneValue, categories: categories)
    }

    static func emptyText(_ lane: HomeLane?) -> String {
        switch lane {
        case .upcoming: L("Nobody else is booked today.")
        case .waiting: L("Nobody is waiting.")
        case .inService: L("Nobody is in right now.")
        case .toPay: L("Nothing waiting at the desk.")
        default: L("Nothing here right now.")
        }
    }

    /// "Listo · 3 · Sin realizar: 1": the day's finished and missed visits, folded.
    @ViewBuilder
    private var doneSection: some View {
        let done = lane(.done)
        let missed = lane(.missed)
        if done.count + missed.count > 0 {
            VStack(alignment: .leading, spacing: 0) {
                RowDivider()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showDone.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        (Text(L("Done@home") + " · \(done.count)").font(Theme.text(14, weight: .heavy)).foregroundColor(Theme.inkStrong)
                         + Text(missed.isEmpty ? "" : " · " + LF("%d missed@home", missed.count)).font(Theme.text(14, weight: .bold)).foregroundColor(Theme.inkSoft))
                        Spacer(minLength: 0)
                        Glyph("chevron-down", size: 16)
                            .foregroundStyle(Theme.inkSoft)
                            .rotationEffect(.degrees(showDone ? 180 : 0))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(showDone ? .isSelected : [])
                if showDone {
                    let rows = HomeFold.together(HomeFold.sorted(done + missed))
                    RowDivider()
                    RowList(items: Array(rows.prefix(HomeCap.rows * 2))) { folded in
                        HomeVisitRow(visit: folded.visit, together: folded.together, stateLabel: stateLabel(folded.visit), hospitalized: false, compact: true, permissions: permissions, categories: categories, open: open)
                    }
                    if rows.count > HomeCap.rows * 2 {
                        HomeStripMore(more: rows.count - HomeCap.rows * 2, route: .section(.appointments))
                    }
                }
            }
        }
    }
}

enum HomeLens: Hashable { case everyone, mine }

/// The agenda's state tabs: everything, or one lane.
enum HomeLaneFilter: Hashable {
    case all, waiting, inService, toPay

    init(_ lane: HomeLane?) {
        switch lane {
        case .waiting: self = .waiting
        case .inService: self = .inService
        case .toPay: self = .toPay
        default: self = .all
        }
    }

    var lane: HomeLane? {
        switch self {
        case .all: nil
        case .waiting: .waiting
        case .inService: .inService
        case .toPay: .toPay
        }
    }
}

/// A visit and the family's other pets booked with it in the same step of the day: one row.
struct HomeFoldedVisit: Identifiable {
    let visit: HomeVisit
    var together: [HomeVisit]
    var id: String { visit.id }
}

enum HomeFold {
    private static func triageRank(_ priority: String?) -> Int {
        switch priority {
        case "critical": 0
        case "urgent": 1
        case "stable": 2
        default: 3
        }
    }

    /// In a group: the visit under way first, then the longest wait (by triage), then by time.
    static func sorted(_ visits: [HomeVisit]) -> [HomeVisit] {
        visits.sorted { left, right in
            if left.laneValue.order != right.laneValue.order { return left.laneValue.order < right.laneValue.order }
            if left.laneValue == .waiting {
                let a = triageRank(left.triagePriority), b = triageRank(right.triagePriority)
                if a != b { return a < b }
                return (left.waitingMinutes ?? 0) > (right.waitingMinutes ?? 0)
            }
            return (left.startsAt ?? "") < (right.startsAt ?? "")
        }
    }

    static func together(_ visits: [HomeVisit]) -> [HomeFoldedVisit] {
        var out: [HomeFoldedVisit] = []
        var index: [String: Int] = [:]
        for visit in visits {
            guard let group = visit.group, group.kind == "household", visit.laneValue != .missed else {
                out.append(HomeFoldedVisit(visit: visit, together: []))
                continue
            }
            let key = "\(group.id):\(visit.laneValue.rawValue)"
            if let lead = index[key] {
                out[lead].together.append(visit)
            } else {
                index[key] = out.count
                out.append(HomeFoldedVisit(visit: visit, together: []))
            }
        }
        return out
    }
}

/// A service category's name (lib/service-provider-display.ts).
enum HomeServiceName {
    static func label(_ category: String) -> String {
        switch category {
        case "vet": L("Veterinary clinic")
        case "emergency": L("Emergency")
        case "groomer": L("Grooming")
        case "boarding": L("Boarding")
        case "daycare": L("Daycare")
        case "sitter": L("Pet sitting")
        case "walker": L("Dog walking")
        case "trainer": L("Training")
        default: L("Other")
        }
    }
}
