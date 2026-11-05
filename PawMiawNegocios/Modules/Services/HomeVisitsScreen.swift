//
//  HomeVisitsScreen.swift
//  PawMiawNegocios
//
//  Domicilio (web: routes/provider.home-visits.tsx, components/app/home-visits/):
//  the day's visits to families' homes in the order they are made — walks,
//  drop-ins, home appointments and the visits of home stays — read on a phone
//  at the door. One route, one runner: arriving is the visit's start and
//  finishing its finish, with its report and its bill. Late visits per
//  backend docs/home-visits-late-and-notices.md (the notices clear on the
//  server when someone arrives, the visit moves or is undone).
//  Arrive and Finish go through this phone's outbox (SvcOutbox.swift), so
//  they work with no signal; the place at those presses and a walk's route
//  are recorded only when the business turned that on (SvcLocation.swift).
//

import SwiftUI

struct HomeVisitsScreen: View {
    var body: some View {
        RequireLocation { SvcHomeVisitsPage() }
            .providerPage(L("Home visits"), root: true)
    }
}

enum SvcHomeTab: Hashable { case today, team, settings }

/// One sheet of the page at a time.
enum SvcHomeSheet: Identifiable {
    case onMyWay(SvcOnMyWayTarget)
    case report(SvcReportTarget)
    case finish(SvcFinishTarget)
    case reassign(SvcHomeVisitItem)
    case check(SvcHomeVisitItem)
    case reveal(SvcHomeVisitItem, emergency: Bool)
    case vault(SvcHomeVisitItem, SvcVaultReveal)
    case stayMove(SvcHomeVisitItem, String)
    case moveDay
    case gate(SvcStartGateRequest)
    /// A home stay's visit, run in its own sheet (optionally opening on "leave" or the report card).
    case stayVisit(SvcHomeVisitItem, String?)

    var id: String {
        switch self {
        case .onMyWay(let target): "omw-\(target.id)"
        case .report(let target): "report-\(target.id)"
        case .finish(let target): "finish-\(target.id)"
        case .reassign(let item): "reassign-\(item.id)"
        case .check(let item): "check-\(item.id)"
        case .reveal(let item, let emergency): "reveal-\(item.id)-\(emergency)"
        case .vault(let item, _): "vault-\(item.id)"
        case .stayMove(let item, let move): "stay-\(item.id)-\(move)"
        case .moveDay: "move-day"
        case .gate(let request): "gate-\(request.id)"
        case .stayVisit(let item, let start): "stay-visit-\(item.id)-\(start ?? "")"
        }
    }
}

/// The outbox belongs to the business and the person: found here, then the page.
private struct SvcHomeVisitsPage: View {
    @EnvironmentObject private var workspace: Workspace
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        SvcHomeVisitsContent(outbox: SvcOutbox.store(clinicId: workspace.current?.clinicId, userId: session.user?.id),
                             clinicId: workspace.current?.clinicId, userId: session.user?.id)
    }
}

private struct SvcHomeVisitsContent: View {
    @ObservedObject var outbox: SvcOutbox
    let clinicId: String?
    let userId: String?

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject private var connectivity = SvcConnectivity.shared
    @StateObject private var tracker = SvcWalkTracker()
    @State private var tab: SvcHomeTab = .today
    @State private var dayKey: String?
    @State private var member: String?
    @State private var day: SvcHomeVisitsDay?
    /// The time of the list shown from this phone's copy (no signal); nil when it is live.
    @State private var cachedAt: String?
    @State private var failed: String?
    @State private var members: [SvcMember] = []
    @State private var lastPosition: [String: VisitPosition] = [:]
    @State private var sheet: SvcHomeSheet?
    @State private var pushed: ProviderRoute?
    @State private var sessionPushed: SvcSessionRoute?
    @AppStorage("pawmiaw_negocios_home_location_notice") private var noticeSeen = false

    private var canView: Bool { workspace.canAny(.appointmentsView, .staysView) }
    private var canBook: Bool { workspace.canAll(.appointmentsCreate, .clientsView) }
    private var seesAll: Bool { day?.viewer?.seesAll ?? false }
    private var lateAfter: Int { day?.settings?.lateAfterMinutes ?? 15 }
    private var isToday: Bool { day?.isToday ?? false }
    private var stamps: Bool { day?.settings?.locationStamps ?? false }
    private var walkRoutes: Bool { day?.settings?.walkRoutes ?? false }
    private var online: Bool { connectivity.online }
    /// The plain day (today, everyone): the one kept on the phone.
    private var plain: Bool { dayKey == nil && member == nil }

    /// The day's visits with this phone's unsent presses already shown on them.
    private var items: [SvcHomeVisitItem] { outbox.apply(day?.items ?? []) }

    var body: some View {
        if !canView {
            PageScroll { NoAccessState(message: L("Ask the workspace owner to let your role see appointments or stays.")) }
        } else {
            page
        }
    }

    private var tabs: [ToneTabs<SvcHomeTab>.Tab] {
        var out: [ToneTabs<SvcHomeTab>.Tab] = [.init(value: .today, title: L("Today"), icon: "calendar-days")]
        if seesAll || tab == .team { out.append(.init(value: .team, title: L("Team"), icon: "users-round")) }
        out.append(.init(value: .settings, title: L("Settings"), icon: "settings-2"))
        return out
    }

    private var page: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            PageScroll(refresh: { await load() }) {
                header(now: context.date)
                tabRow
                switch tab {
                case .today: todayView(now: context.date)
                case .team:
                    if seesAll {
                        SvcTeamProgress(people: day?.people ?? [], selected: member, canMoveDay: day?.viewer?.canReassign ?? false, onSelect: { key in
                            member = key
                            tab = .today
                        }, onMoveDay: { sheet = .moveDay })
                    } else {
                        EmptyState(systemImage: "users-round", title: L("Your role can’t see this."), message: L("Only whoever sees everyone’s visits has the team’s day."), accent: Theme.aqua, panel: true)
                    }
                case .settings:
                    SvcHomeVisitSettingsTab(canManage: workspace.can(.workspaceEdit), businessName: workspace.current?.name ?? "")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if tab == .today, let day, isToday, let bar = barVisit(items) {
                    SvcNextVisitBar(item: bar, timeZone: day.timeZone, pressing: outbox.pending[bar.id]?.holdsNextPress == true, onArrive: { arrive(bar) }, onFinish: { finish(bar) }, onOnMyWay: { onMyWay(bar) }, onOpenVisit: { open(bar) })
                }
            }
        }
        .navigationDestination(item: $pushed) { RouteView(route: $0) }
        .navigationDestination(item: $sessionPushed) { route in
            switch route {
            case .session(let id): SvcSessionScreen(sessionId: id)
            case .provider(let provider): RouteView(route: provider)
            }
        }
        .sheet(item: $sheet) { current in sheetView(current) }
        .onReceive(NotificationCenter.default.publisher(for: .pawMiawDataChanged)) { _ in Task { await load() } }
        // The signal is back: the day is read again at once (what was pressed meanwhile goes on its own).
        .onChange(of: online) { _, now in if now { Task { await load() } } }
        .task(id: "\(dayKey ?? "today")|\(member ?? "all")|\(workspace.scopeVersion)") {
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await load()
            }
        }
        .task {
            members = await svcLoadMembers(workspace)
            await SvcServices.load("provider")
        }
        // The walk this phone records: open, routes on, and Arrive was pressed here.
        .task(id: trackedKey) { followWalk() }
        .onAppear { followWalk() }
        .onDisappear { if pushed == nil && sessionPushed == nil && sheet == nil { tracker.stop() } }
    }

    /// The tabs, and on a phone the page's overflow with "New visit" (the header keeps to its three numbers there).
    private var tabRow: some View {
        HStack(spacing: 12) {
            ToneTabs(tabs: tabs, selection: $tab, look: .solid, height: 44)
            Spacer(minLength: 0)
            if canBook && sizeClass != .regular {
                Menu {
                    Button { pushed = newVisit() } label: { GlyphLabel(L("New visit"), icon: "plus") }
                } label: {
                    Glyph("ellipsis", size: 20)
                        .foregroundStyle(Theme.inkStrong)
                        .frame(width: 48, height: 48)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.borderSoft, lineWidth: 2))
                }
                .accessibilityLabel(L("More options"))
            }
        }
    }

    // MARK: Header

    private func header(now: Date) -> some View {
        let shown = items
        let done = shown.filter { $0.phase == "done" }.count
        let inProgress = shown.filter { $0.phase == "in_progress" }.count
        let late = shown.filter { SvcHomeRules.late($0, now: now, lateAfter: lateAfter, isToday: isToday).late }.count
        let next = shown.filter { ["upcoming", "on_my_way"].contains($0.phase) }.sorted { $0.startsAt < $1.startsAt }.first
        return ModuleHeader(
            icon: "house",
            title: L("Home visits"),
            subtitle: day.map { svcCapitalized(SvcTime.dayLong($0.date)) } ?? L("The day’s visits to families’ homes, in order"),
            accent: Theme.aqua,
            stats: [
                ModuleStat("visits", label: L("Visits"), value: day == nil ? "—" : "\(done)/\(shown.count)", hint: inProgress > 0 ? LF("%d in progress", inProgress) : nil, icon: "list-checks", accent: Theme.aqua),
                ModuleStat("next", label: L("Next"), value: next.map { SvcTime.clock($0.startsAt, day?.timeZone) } ?? "—", hint: next?.petNames, icon: "clock-3", accent: Theme.blue),
                ModuleStat("late", label: L("Home visit · Late"), value: day == nil ? "—" : "\(late)", icon: "triangle-alert", accent: Theme.pink, attention: late > 0),
            ],
            storageKey: "home-visits"
        ) {
            // Phones keep the header to the three numbers: "New visit" is in the page's overflow there.
            if canBook && sizeClass == .regular {
                PMButton(L("New visit"), systemImage: "plus") { pushed = newVisit() }
            }
        }
    }

    // MARK: Today

    @ViewBuilder private func todayView(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SvcOfflineBanner(online: online, waiting: outbox.waiting.count, failed: outbox.failed.count, cachedAt: cachedAt)
            if let day {
                let today = SvcHomeRules.todayKey(day)
                let shown = items
                SvcDaySwitcher(day: day.date, today: today) { next in dayKey = next == today ? nil : next }
                let people = seesAll ? (day.people ?? []) : []
                if !people.isEmpty || member != nil {
                    personChips(day, people)
                }
                if (day.settings?.locationStamps == true || day.settings?.walkRoutes == true) && day.viewer?.canAct == true && !noticeSeen {
                    NoticeCard(tone: .info, title: L("Location is recorded on home visits"), message: L("Your location is saved when you arrive and finish. Only owners and admins see it."), actionTitle: L("Got it")) { noticeSeen = true }
                }
                if shown.isEmpty {
                    EmptyState(systemImage: "house", title: seesAll && member == nil ? L("No home visits this day") : L("No home visits for you this day"), message: L("Walks, drop-ins and home appointments show up here in the order you’ll make them."),
                               actionTitle: canBook ? L("New visit") : nil, action: { pushed = newVisit() }, accent: Theme.aqua, panel: true)
                } else {
                    let next = shown.first { $0.actions?.arrive == true }
                    let pending = outbox.pending
                    let refused = outbox.failed
                    VStack(spacing: 14) {
                        ForEach(shown) { item in
                            SvcVisitCard(item: item, day: day, now: now, highlight: isToday && next?.id == item.id, pressing: pending[item.id]?.holdsNextPress == true, handlers: handlers,
                                         pending: pending[item.id], failed: refused.filter { $0.itemId == item.id },
                                         tracker: tracker.appointmentId != nil && tracker.appointmentId == item.appointmentId ? tracker : nil,
                                         lastPosition: lastPosition[item.id])
                        }
                    }
                    // The count sits under the list, as on Home.
                    Text(LF("%d of %d done", shown.filter { $0.phase == "done" }.count, shown.count))
                        .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkSoft).frame(maxWidth: .infinity)
                }
                // Below the list: the day's group walks and classes, which live on their own page.
                if workspace.offers(.walker, .trainer) {
                    SvcGroupSessionsPointer(dayKey: day.date, timeZone: day.timeZone, push: { sessionPushed = $0 })
                }
            } else if failed != nil {
                SvcLoadError(message: online ? L("The home visits couldn’t be loaded.") : L("The home visits couldn’t be loaded.") + " " + L("Open this page with a connection before you head out."), compact: false) { await load() }
            } else {
                LoadingState()
            }
        }
    }

    /// Whose visits (web `PersonChip`s): everyone, only mine, then each person with how far they are.
    private func personChips(_ day: SvcHomeVisitsDay, _ people: [SvcHomePerson]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: L("Everyone"), isSelected: member == nil, tone: Theme.blue, icon: "users-round") { member = nil }
                if let me = day.viewer?.memberId {
                    FilterChip(title: L("Only mine"), isSelected: member == me, tone: Theme.aqua, icon: "user-round") { member = me }
                }
                ForEach(people.filter { $0.memberId != day.viewer?.memberId }) { person in
                    FilterChip(title: (person.memberId == nil ? L("Unassigned") : (person.name ?? "—")) + "  " + LF("%d of %d", person.done, person.total),
                               isSelected: member == person.key, tone: person.memberId == nil ? Theme.mango : Theme.lavender, icon: "user-round") { member = person.key }
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// The visit under way, else the next one this person can arrive at (never one whose press was refused).
    private func barVisit(_ items: [SvcHomeVisitItem]) -> SvcHomeVisitItem? {
        let blocked = Set(outbox.failed.map(\.itemId))
        let open = items.filter { !blocked.contains($0.id) }
        return open.first { $0.phase == "in_progress" && $0.actions?.finish == true }
            ?? open.filter { $0.actions?.arrive == true }.sorted { $0.startsAt < $1.startsAt }.first
    }

    /// "New visit": the kind this business does at home, on the day shown, for the person shown.
    private func newVisit() -> ProviderRoute {
        let person = member.flatMap { $0 == "unassigned" ? nil : $0 }
        return .bookVisit(BookingPrefill(serviceId: SvcServices.pick(category: SvcBook.homeCategory(workspace)), day: day?.date ?? dayKey, memberId: person))
    }

    // MARK: Loading

    private func load() async {
        do {
            let loaded: SvcHomeVisitsDay = try await API.get("/provider-home-visits/today", query: ["locationId": workspace.locationId, "day": dayKey, "memberId": member])
            day = loaded
            cachedAt = nil
            failed = nil
            // Today's list as it last loaded is kept on this phone, for when the signal drops.
            if plain { SvcDayCache.save(loaded, clinicId: clinicId, userId: userId) }
        } catch is CancellationError {
        } catch {
            let offline = (error as? APIError)?.isOffline == true
            if (day == nil || cachedAt != nil), offline, plain, let kept = SvcDayCache.read(clinicId: clinicId, userId: userId) {
                day = kept.day
                cachedAt = SvcTime.clock(kept.savedAt, kept.day.timeZone)
                failed = nil
                return
            }
            if day == nil {
                failed = offline ? errorText(error) + " " + L("Open this page with a connection before you head out.") : errorText(error)
            } else if !offline {
                Toast.error(error)
            }
        }
    }

    // MARK: The walk's route

    private var trackedItem: SvcHomeVisitItem? {
        guard walkRoutes else { return nil }
        return items.first { item in
            guard item.phase == "in_progress", SvcHomeRules.isWalk(item), let id = item.appointmentId else { return false }
            return SvcWalkTracking.isTracking(id)
        }
    }

    private var trackedKey: String {
        "\(trackedItem?.appointmentId ?? "none")|" + items.map { "\($0.id):\($0.phase)" }.joined(separator: ",")
    }

    private func followWalk() {
        // A walk that is no longer open stops being this phone's to record (one still waiting keeps its flag a moment).
        for item in items {
            guard let id = item.appointmentId, item.phase != "in_progress", let age = SvcWalkTracking.age(id) else { continue }
            if item.closed || age > 120 { SvcWalkTracking.clear(id) }
        }
        let tracked = trackedItem
        tracker.follow(appointmentId: tracked?.appointmentId, itemId: tracked?.id, outbox: outbox)
    }

    // MARK: Actions

    private var handlers: SvcVisitHandlers {
        SvcVisitHandlers(
            arrive: arrive, finish: finish, onMyWay: onMyWay, report: report,
            reassign: { item in connected { sheet = .reassign(item) } }, check: { item in connected { sheet = .check(item) } },
            reveal: { item in connected { sheet = .reveal(item, emergency: false) } }, emergency: { item in connected { sheet = .reveal(item, emergency: true) } },
            open: open, stayMove: { item, move in
                if move == "undo" { Task { await stayMove(item, "undo", body: [:]) } } else { sheet = .stayMove(item, move) }
            }, push: { pushed = $0 },
            retry: { outbox.retry($0) },
            discard: { id in
                // An arrival that is forgotten is no longer this phone's walk to record.
                if let entry = outbox.entries.first(where: { $0.id == id }), entry.kind == "arrive",
                   let appointmentId = day?.items.first(where: { $0.id == entry.itemId })?.appointmentId {
                    SvcWalkTracking.clear(appointmentId)
                }
                outbox.discard(id)
            },
            reviewConsents: reviewConsents)
    }

    /// Everything but Arrive and Finish needs a connection: said once, nothing opens.
    private func connected(_ action: () -> Void) {
        guard online else { Toast.error(L("This needs a connection.")); return }
        action()
    }

    private func open(_ item: SvcHomeVisitItem) {
        if item.isStay {
            if item.stayVisitId != nil { connected { sheet = .stayVisit(item, nil) } }
            else if let stay = item.stayId { pushed = .stay(stay) }
        } else if let id = item.appointmentId {
            pushed = .appointment(id)
        }
    }

    /// The place of this press, when the business records it: asked now, awaited 8 s at most, never in the way.
    private func stampPosition(_ itemId: String) -> (() async -> VisitPosition)? {
        guard stamps else { return nil }
        return {
            let answer = await VisitLocator.shared.position()
            lastPosition[itemId] = answer
            return answer
        }
    }

    /// "I've arrived": the visit's start, from the door, with the time it was pressed — saved on the phone first, sent in order.
    private func arrive(_ item: SvcHomeVisitItem) {
        if item.isStay {
            guard let stay = item.stayId, let visit = item.stayVisitId else { return }
            outbox.add(kind: "stay_arrive", itemId: item.id, path: "/provider-homestays/\(stay)/visits/\(visit)/arrive", position: stampPosition(item.id))
            return
        }
        guard let id = item.appointmentId else { return }
        // This phone records the walk's route from here on.
        if walkRoutes && SvcHomeRules.isWalk(item) { SvcWalkTracking.mark(id) }
        outbox.add(kind: "arrive", itemId: item.id, path: "/provider-appointments/\(id)/home-arrive", position: stampPosition(item.id))
    }

    /// Finish. With signal: a stay's visit leaves with its note; a walk, sitting, groom or class closes with the charge choice;
    /// a vet visit on its page. Without: saved now and sent to the desk with the time it was pressed.
    private func finish(_ item: SvcHomeVisitItem) {
        let waiting = outbox.pending[item.id] != nil
        if item.isStay {
            guard let stay = item.stayId, let visit = item.stayVisitId else { return }
            if online && !waiting { sheet = .stayMove(item, "leave"); return }
            outbox.add(kind: "stay_leave", itemId: item.id, path: "/provider-homestays/\(stay)/visits/\(visit)/leave", position: stampPosition(item.id))
            return
        }
        guard let id = item.appointmentId else { return }
        // A clinical visit closes with its note, on its page.
        guard SvcHomeRules.finishesHere(item.serviceCategory) else { connected { open(item) }; return }
        if online && !waiting {
            sheet = .finish(finishTarget(item, id))
            return
        }
        if tracker.appointmentId == id { tracker.handOverNow() }
        outbox.add(kind: "finish", itemId: item.id, path: "/provider-appointments/\(id)/finish", position: stampPosition(item.id))
    }

    private func finishTarget(_ item: SvcHomeVisitItem, _ id: String) -> SvcFinishTarget {
        let lead = item.pets.first { $0.appointmentId == item.appointmentId } ?? item.pets.first
        var target = SvcFinishTarget(id: id, petName: lead?.name ?? item.petNames, serviceLabel: item.serviceText, serviceCategory: item.serviceCategory, reportMissing: item.reportMissing ?? [])
        target.clientName = item.client.name
        target.familyOnApp = item.client.onPawMiaw == true
        target.assignedId = item.assigned?.id
        target.assignedName = item.assigned?.name
        // The family's other pets booked with it finish with it.
        target.together = item.pets.filter { $0.appointmentId != nil && $0.appointmentId != item.appointmentId }.map(\.name)
        target.locationId = workspace.locationId
        return target
    }

    private func onMyWay(_ item: SvcHomeVisitItem) {
        guard let id = item.appointmentId else { return }
        connected { sheet = .onMyWay(SvcOnMyWayTarget(id: item.id, appointmentId: id, client: item.client, petNames: item.petNames)) }
    }

    private func report(_ item: SvcHomeVisitItem) {
        connected {
            if item.isStay {
                // A home stay's report card is written in its visit's own sheet.
                sheet = .stayVisit(item, "report")
                return
            }
            let pets = item.pets.compactMap { pet in pet.appointmentId.map { SvcReportPet(id: $0, name: pet.name) } }
            let list = pets.isEmpty ? (item.appointmentId.map { [SvcReportPet(id: $0, name: item.petNames)] } ?? []) : pets
            sheet = .report(SvcReportTarget(subtitle: "\(item.petNames) · \(item.serviceText)", pets: list, canWrite: day?.viewer?.canAct ?? false))
        }
    }

    /// A consent or a deposit stopped a saved arrival: owners and admins start anyway with a reason (the press time kept); others open the visit.
    private func reviewConsents(_ entry: SvcOutboxEntry, _ item: SvcHomeVisitItem) {
        guard online else { Toast.error(L("This needs a connection.")); return }
        guard workspace.isOwnerOrAdmin else { open(item); return }
        let box = outbox
        sheet = .gate(SvcStartGateRequest(code: entry.errorCode ?? "consent_required", petName: item.petNames) { override in
            var body = entry.body
            for (key, value) in override { body[key] = svcJSON(value) }
            _ = try await API.data("POST", entry.path, query: [:], body: try JSONEncoder().encode(body))
            box.resolve(entry.id)
            announceDataChanged()
        })
    }

    private func stayMove(_ item: SvcHomeVisitItem, _ move: String, body: [String: Any?]) async {
        guard let stay = item.stayId, let visit = item.stayVisitId else { return }
        do {
            let _: SvcIgnored = try await API.post("/provider-homestays/\(stay)/visits/\(visit)/\(move)", body: body)
            Toast.show(move == "undo" ? L("Undone.") : L("Saved"))
            announceDataChanged()
        } catch {
            Toast.error(error)
        }
    }

    /// Whoever takes payment goes on to the visit, where its bill is; "Fill it in now" opens the report here.
    /// The finish carries the press time, where the phone was and the last of a walk's route.
    private func finishSheet(_ target: SvcFinishTarget) -> SvcFinishSheet {
        let item: SvcHomeVisitItem? = items.first { $0.appointmentId == target.id }
        var openReport: (() -> Void)? = nil
        if let item { openReport = { report(item) } }
        var openVisit: (() -> Void)? = nil
        if (day?.viewer?.seesBilling ?? false) || workspace.moneyLevel >= .charging {
            let id = target.id
            openVisit = { pushed = .appointment(id) }
        }
        let itemId = item?.id ?? target.id
        let locate = stampPosition(itemId)
        let walk = tracker.appointmentId == target.id ? tracker : nil
        return SvcFinishSheet(target: target, onOpenReport: openReport, onOpenVisit: openVisit, onFinished: {}, prepare: {
            var extra: [String: Any?] = ["at": DateText.iso(Date())]
            let place: Task<VisitPosition, Never>? = locate.map { ask in Task { await ask() } }
            if let walk { await walk.flushNow(timeout: 5) }
            if let position = await place?.value { extra["position"] = position.body }
            return extra
        })
    }

    @ViewBuilder private func sheetView(_ current: SvcHomeSheet) -> some View {
        switch current {
        case .onMyWay(let target):
            SvcOnMyWaySheet(target: target)
        case .report(let target):
            SvcReportSheet(target: target)
        case .finish(let target):
            finishSheet(target)
        case .reassign(let item):
            SvcReassignSheet(item: item, members: members)
        case .check(let item):
            SvcVisitCheckSheet(item: item, timeZone: day?.timeZone, locationOn: day?.settings?.locationStamps == true || day?.settings?.walkRoutes == true)
        case .reveal(let item, let emergency):
            SvcRevealConfirmSheet(item: item, emergency: emergency) { result in
                sheet = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    sheet = .vault(item, result)
                }
            }
        case .vault(let item, let result):
            SvcVaultSheet(item: item, reveal: result)
        case .stayMove(let item, let move):
            SvcStayMoveSheet(item: item, move: move, timeZone: day?.timeZone, locate: move == "leave" ? stampPosition(item.id) : nil)
        case .moveDay:
            SvcMoveDaySheet(date: day?.date ?? DateText.dayKey(), people: day?.people ?? [], members: members, initialFrom: member == "unassigned" ? nil : member)
        case .gate(let request):
            SvcStartGateSheet(request: request) {}
        case .stayVisit(let item, let start):
            StaysHomeVisitSheet(stayId: item.stayId ?? "", visitId: item.stayVisitId ?? "", startWith: start, onArrive: { arrive(item) },
                                locate: stampPosition(item.id), onOpenStay: {
                                  guard let stay = item.stayId else { return }
                                  Task { @MainActor in
                                      try? await Task.sleep(for: .milliseconds(350))
                                      pushed = .stay(stay)
                                  }
                              })
        }
    }
}

/// A simple value as JSON, for a press's body.
func svcJSON(_ value: Any?) -> JSONValue {
    switch value {
    case nil: return .null
    case let bool as Bool: return .bool(bool)
    case let int as Int: return .number(Double(int))
    case let double as Double: return .number(double)
    case let string as String: return .string(string)
    case let json as JSONValue: return json
    case let some?:
        if case Optional<Any>.none = some as Any? { return .null }
        return .string(String(describing: some))
    }
}

// MARK: - Rules (lib/home-visits.ts)

enum SvcHomeRules {
    /// Not arrived, and the start passed by more than the business allows. Only today's visits are late.
    static func late(_ item: SvcHomeVisitItem, now: Date, lateAfter: Int, isToday: Bool) -> (late: Bool, minutes: Int) {
        guard isToday, ["upcoming", "on_my_way"].contains(item.phase), let start = DateText.parse(item.startsAt) else { return (false, 0) }
        let late = now > start.addingTimeInterval(Double(lateAfter) * 60)
        return (late, late ? Int(now.timeIntervalSince(start) / 60) : 0)
    }

    /// There longer than booked plus the allowance, counted from the arrival: a late arrival is late, not long.
    static func runningLong(_ item: SvcHomeVisitItem, now: Date, lateAfter: Int) -> Bool {
        guard item.phase == "in_progress", let start = DateText.parse(item.startsAt) else { return false }
        let booked = DateText.parse(item.endsAt).map { max(0, $0.timeIntervalSince(start)) } ?? 30 * 60
        let from = DateText.parse(item.arrivedAt) ?? start
        return now > from.addingTimeInterval(booked + Double(lateAfter) * 60)
    }

    /// A walk: the only visit whose route is recorded.
    static func isWalk(_ item: SvcHomeVisitItem) -> Bool { item.source == "appointment" && item.serviceCategory == "walker" }

    /// Finishing without the visit page is for visits that close with a report, not a clinical note.
    static func finishesHere(_ category: String?) -> Bool {
        ["walker", "sitter", "groomer", "trainer"].contains(category ?? "")
    }

    /// Today's key on the business's clock, when the server shows another day.
    static func todayKey(_ day: SvcHomeVisitsDay) -> String {
        if day.isToday == true { return day.date }
        return DateText.dayKey(DateText.parse(day.now) ?? Date(), zone: SvcTime.zone(day.timeZone))
    }

    /// "0:07", "1:25 h": the clock a walker glances at.
    static func timer(_ arrivedAt: String?, now: Date) -> String {
        guard let arrived = DateText.parse(arrivedAt) else { return "0:00" }
        let seconds = max(0, Int(now.timeIntervalSince(arrived)))
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60
        return hours > 0 ? String(format: "%d:%02d h", hours, minutes) : String(format: "%d:%02d", minutes, seconds % 60)
    }

    static func window(_ item: SvcHomeVisitItem, _ timeZone: String?) -> String {
        let start = SvcTime.clock(item.startsAt, timeZone)
        return item.endsAt.map { "\(start) – \(SvcTime.clock($0, timeZone))" } ?? start
    }

    /// A stamp in a line: a manager reads the distance; the person who recorded it only whether it was saved. Never a coordinate.
    /// `warn`: far from the address (mango, strong); `muted`: nothing usable was saved (grey).
    static func stampLine(_ kind: String, _ stamp: SvcStampSummary?, isManager: Bool) -> (text: String, warn: Bool, muted: Bool)? {
        guard let stamp else { return nil }
        guard isManager else { return stamp.status == "ok" ? (L("Location saved"), false, false) : (L("No location was saved"), false, true) }
        if stamp.status == "expired" { return (LF("Location deleted after %d days", 90), false, true) }
        if stamp.status != "ok" { return (noLocation(stamp.status), false, true) }
        guard let distance = stamp.distanceM else { return (L("Location saved"), false, false) }
        let text = formatDistance(distance)
        if stamp.far == true { return (LF("Far from the address · %@", text), true, false) }
        return (kind == "arrive" ? LF("Arrived %@ from the address", text) : LF("Finished %@ from the address", text), false, false)
    }

    /// The colour of a stamp's line (web `STAMP_TONE`).
    static func stampTone(warn: Bool, muted: Bool) -> Color {
        warn ? Theme.mango : muted ? Theme.borderStrong : ProviderState.done.color
    }

    static func noLocation(_ status: String) -> String {
        switch status {
        case "denied": L("No location: permission denied")
        case "unavailable": L("No location: not available")
        case "timeout": L("No location: it took too long")
        case "unsupported": L("No location: this browser can’t give it")
        case "inaccurate", "stale": L("No location: too imprecise")
        case "not_sent": L("No location: recorded from another app")
        default: L("No location was saved")
        }
    }

    static func formatDistance(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", (meters / 100).rounded() / 10)
    }
}

// MARK: - Day switcher

/// ‹ Yesterday · Today · Tomorrow › (web `DaySwitcher`), within the week back and the 30 days ahead the server lists.
private struct SvcDaySwitcher: View {
    let day: String
    let today: String
    let onDay: (String) -> Void

    private func label(_ key: String) -> String {
        switch SvcTime.daysBetween(today, key) {
        case 0: L("Today")
        case -1: L("Yesterday")
        case 1: L("Tomorrow")
        default: DateText.day(DateText.parse(key))
        }
    }

    /// The server lists a week back and 30 days ahead.
    private func inRange(_ key: String) -> Bool { (-7...30).contains(SvcTime.daysBetween(today, key)) }

    var body: some View {
        let previous = SvcTime.shift(day, by: -1), next = SvcTime.shift(day, by: 1)
        HStack(spacing: 8) {
            arrow("chevron-left", label: L("Previous day") + ": " + label(previous)) { onDay(previous) }
                .disabled(!inRange(previous))
            VStack(spacing: 0) {
                Text(label(day)).font(.brandHeading(21.6)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                Text(svcCapitalized(SvcTime.dayLong(day))).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            if day != today { PMButton(L("Today"), variant: .outline) { onDay(today) } }
            arrow("chevron-right", label: L("Next day") + ": " + label(next)) { onDay(next) }
                .disabled(!inRange(next))
        }
    }

    /// A 48 outline button with only its chevron (web: `Button variant="outline" size-12 px-0`).
    private func arrow(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Glyph(icon, size: 20).frame(width: 16) }
            .buttonStyle(.pm(.outline))
            .accessibilityLabel(label)
    }
}

// MARK: - The team's day

/// The team's day (web `TeamProgress`), for whoever sees everyone's visits: one row per
/// person with how far they are, who is at a visit now and who is late. A tap shows only
/// that person's visits; "Move the day" hands someone's whole day to another person.
private struct SvcTeamProgress: View {
    let people: [SvcHomePerson]
    let selected: String?
    let canMoveDay: Bool
    let onSelect: (String?) -> Void
    let onMoveDay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Glyph("users-round", size: 20)
                    .foregroundStyle(Theme.inkStrong)
                    .frame(width: 40, height: 40)
                    .background(Theme.wash(Theme.lavender, 55), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("The team’s day")).font(.brandHeading(20)).foregroundStyle(Theme.inkStrong)
                    Text(L("Tap a person to see only their visits.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.wash(Theme.lavender, 22))
            .overlay(alignment: .bottom) {
                StitchedDivider(lineWidth: 1)
            }
            if people.isEmpty {
                Text(L("Nobody has home visits this day."))
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 32)
            } else {
                ForEach(people) { person in
                    if person.id != people.first?.id { RowDivider() }
                    row(person)
                }
                if canMoveDay {
                    RowDivider()
                    PMButton(L("Move the day to someone else"), systemImage: "arrow-right-left", variant: .outline, fullWidth: true, action: onMoveDay)
                        .padding(12)
                }
            }
        }
        .listCard()
    }

    private func row(_ person: SvcHomePerson) -> some View {
        let active = selected == person.key
        let share = person.total > 0 ? Double(person.done) / Double(person.total) : 0
        return Button { onSelect(active ? nil : person.key) } label: {
            HStack(spacing: 12) {
                if person.image != nil {
                    Avatar(name: person.name, imageURL: person.image, size: 40)
                } else {
                    Glyph("user-round", size: 20).foregroundStyle(Theme.inkSoft).frame(width: 40, height: 40).background(Theme.surfaceMuted, in: Circle())
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(person.memberId == nil ? L("Unassigned") : (person.name ?? "—")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(LF("%d of %d", person.done, person.total)).font(Theme.text(14, weight: .heavy)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.surfaceMuted)
                            Capsule().fill(ProviderState.done.color).frame(width: proxy.size.width * share)
                        }
                    }
                    .frame(height: 8)
                    if person.inProgress > 0 || person.late > 0 {
                        HStack(spacing: 12) {
                            if person.inProgress > 0 { Text(LF("%d in progress", person.inProgress)).foregroundStyle(Theme.blue) }
                            if person.late > 0 { Text(LF("%d late", person.late)).foregroundStyle(Theme.destructive) }
                        }
                        .font(Theme.text(12, weight: .bold))
                    }
                }
                Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            .background(active ? AnyShapeStyle(Theme.wash(Theme.blue, 10)) : AnyShapeStyle(Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

// MARK: - The bar that never scrolls away

/// The action that never scrolls away (web `NextVisitBar`): Finish for the visit under
/// way (with its clock), else Arrive for the next one (and "On my way" when it is offered).
private struct SvcNextVisitBar: View {
    let item: SvcHomeVisitItem
    let timeZone: String?
    let pressing: Bool
    let onArrive: () -> Void
    let onFinish: () -> Void
    let onOnMyWay: () -> Void
    let onOpenVisit: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let inProgress = item.phase == "in_progress"
            let elapsed = SvcTime.minutesBetween(item.arrivedAt, DateText.iso(context.date))
            let over = inProgress && (item.bookedMinutes.map { elapsed > $0 } ?? false)
            HStack(spacing: 12) {
                if let lead = item.pets.first {
                    PetAvatar(name: lead.name, species: lead.species, photoURL: lead.photoUrl, size: 40)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.petNames).font(.brandHeading(16.8)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text(inProgress
                         ? SvcHomeRules.timer(item.arrivedAt, now: context.date) + " · " + (item.bookedMinutes.map { LF("%d of %d min", elapsed, $0) } ?? L("Home visit · In progress"))
                         : L("Next") + " · " + SvcTime.clock(item.startsAt, timeZone))
                        .font(Theme.text(12, weight: .bold)).monospacedDigit()
                        .foregroundStyle(over ? Theme.inkStrong : Theme.inkSoft).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !inProgress && item.actions?.onMyWay == true && item.onMyWay?.at == nil {
                    Button(action: onOnMyWay) { Glyph("navigation", size: 20).frame(width: 24) }
                        .buttonStyle(.pm(.outline))
                        .accessibilityLabel(L("On my way"))
                }
                if inProgress {
                    if item.isStay || SvcHomeRules.finishesHere(item.serviceCategory) {
                        PMButton(item.isStay ? L("Leave") : L("Finish"), systemImage: item.isStay ? "log-out" : "badge-check", isWorking: pressing, action: onFinish)
                    } else {
                        PMButton(L("Open visit"), systemImage: "external-link", action: onOpenVisit)
                    }
                } else {
                    PMButton(L("I’ve arrived"), systemImage: "door-open", isWorking: pressing, action: onArrive)
                }
            }
            .padding(10)
            .padding(.leading, 2)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(over ? Theme.mango : Theme.blue, lineWidth: 2))
            .shadow(color: Theme.navy.opacity(0.14), radius: 24, y: 24)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: 820)
        }
    }
}
