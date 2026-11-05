//
//  ScheduleScreen.swift
//  PawMiawNegocios
//
//  The Agenda (web provider.schedule.tsx): one place's visits by day (by
//  person or by room), by week, or as a list to find any visit. Its numbers
//  (visits, the next free time, families asking for a change, online
//  bookings to confirm, double bookings), the families asking for a change,
//  the online requests inbox with its three answers, booking a visit or a
//  walk-in, a group session (Paseos y clases' own form), and moving a visit
//  through its edit sheet (no dragging here). Opened from another screen it
//  starts on that screen's day, person, room and view (`ScheduleFilter`).
//

import SwiftUI

struct ScheduleScreen: View {
    /// Opened on a day, a person or a room, in a view (`ProviderRoute.schedule`).
    var filter = ScheduleFilter()
    @EnvironmentObject private var workspace: Workspace

    var body: some View {
        Group {
            if workspace.can(.appointmentsView) {
                RequireLocation { SchedAgendaPage(filter: filter).id(filter) }
            } else {
                PageScroll { NoAccessState(message: L("Ask the workspace owner to let your role see visits.")) }
            }
        }
        .providerPage(L("Schedule"), root: true)
    }
}

private struct SchedAgendaPage: View {
    let filter: ScheduleFilter
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass

    @AppStorage("pawmiaw.negocios.agenda.view") private var storedView = "day"
    @AppStorage("pawmiaw.negocios.agenda.by") private var by = "staff"
    @AppStorage("pawmiaw.negocios.agenda.cancelled") private var showCancelled = false
    /// A view the asking screen chose (web: the URL's), not remembered as the person's own.
    @State private var chosenView: String?
    @State private var day = SchedDay.today
    @State private var person = ""

    @State private var appointments: [SchedAppointment] = []
    @State private var sessions: [SchedSession] = []
    @State private var load: SchedLoad?
    @State private var loadedRange: String?
    @State private var rangeError: String?
    @State private var members: [SchedMember] = []
    @State private var rooms: [SchedRoom] = []
    @State private var availability: SchedAvailability?
    @State private var asking: [SchedAppointment] = []
    @State private var online: SchedOnlineRequestList?
    @State private var hasClients: Bool?

    @State private var listFilters = SchedListFilters()
    @StateObject private var listPager = SchedVisitList.makePager()
    @State private var listTotal: Int?
    @State private var listDoubled: Int?

    @State private var booking: SchedBookingDraft?
    @State private var openRequest: SchedOnlineRequest?
    @State private var gate: SchedGatePrompt?
    @State private var pushed: ProviderRoute?
    @State private var filterApplied = false
    @State private var planningSession = false
    @State private var openedSession: String?

    // MARK: What is shown

    private var view: String { chosenView ?? storedView }
    private var today: String { SchedDay.today }
    private var rangeDays: [String] { view == "week" ? (0..<7).map { SchedDay.addDays(day, $0) } : [day] }
    private var rangeKey: String { "\(view)|\(rangeDays.first ?? "")|\(person)|\(workspace.locationId ?? "")|\(workspace.scopeVersion)" }
    private var canAssignAnyone: Bool { workspace.can(.appointmentsAssignAnyone) }
    private var canCreate: Bool { workspace.can(.appointmentsCreate) && (canAssignAnyone || workspace.can(.appointmentsAssignSelf)) }
    private var me: SchedMember? { members.first(where: \.isMe) }

    /// People who take visits here; someone who sees only their own sees just themselves.
    private var people: [SchedMember] {
        let takers = SchedData.visitTakers(members, locationId: workspace.locationId)
        return canAssignAnyone ? takers : takers.filter(\.isMe)
    }

    private var blocks: [SchedBlock] {
        let shownSessions = sessions.filter { s in
            person.isEmpty || (person == "none" ? s.assignedMember == nil : s.assignedMember?.id == person)
        }
        let days = Set(rangeDays)
        return SchedBlock.fold(appointments, sessions: shownSessions).filter { days.contains($0.day) }
    }
    private var shownBlocks: [SchedBlock] { showCancelled ? blocks : blocks.filter { !$0.gone } }
    private var cancelledCount: Int { blocks.filter(\.gone).count }
    private var activeCount: Int { appointments.filter { !$0.isGone }.count }
    private var doubledCount: Int { appointments.filter { !$0.isGone && $0.doubleBooked == true }.count }
    private var onlineWaiting: Int { online?.count ?? 0 }

    private func openFor(_ day: String) -> (ranges: [SchedRange], closure: (label: String?, closed: Bool)?) {
        SchedHours.day(day, load: load, closures: nil, availability: availability)
    }

    private func workFor(_ memberId: String, _ day: String) -> (working: [SchedMinuteRange]?, offNote: String?) {
        guard let entry = load?.people?.first(where: { $0.id == memberId })?.day(day) else { return (nil, nil) }
        let note = entry.timeOff.map { off in off.reason.map { LF("Off · %@", $0) } ?? L("Day off") } ?? L("Not working")
        return (entry.timeOff != nil ? [] : SchedHours.minutes(entry.ranges ?? []), note)
    }

    private func closedNote(_ day: String) -> String? {
        let hours = openFor(day)
        if let closure = hours.closure {
            if closure.closed { return closure.label.map { LF("Closed · %@", $0) } ?? L("Closed") }
            return closure.label.map { LF("Special hours · %@", $0) } ?? L("Special hours")
        }
        return hours.ranges.isEmpty ? L("Closed") : nil
    }

    private var byRooms: Bool { view == "day" && by == "rooms" && !rooms.isEmpty }
    /// Who a visit booked from the grid is for, unless the column says.
    private var creator: String? { !person.isEmpty && person != "none" ? person : me?.id }

    private var columns: [SchedColumn] {
        if view == "week" {
            return rangeDays.map { key in
                SchedColumn(id: "day:\(key)", title: SchedDay.weekColumnLabel(key), detail: closedNote(key), kind: .day, day: key,
                            open: SchedHours.minutes(openFor(key).ranges), createMemberId: creator)
            }
        }
        let open = SchedHours.minutes(openFor(day).ranges)
        if byRooms {
            var list = rooms.map { room in
                SchedColumn(id: "room:\(room.id)", title: room.name, detail: (room.capacity ?? 1) > 1 ? LF("%@ at once", String(room.capacity ?? 1)) : nil, kind: .room, roomId: room.id, day: day, open: open, createMemberId: creator)
            }
            if appointments.contains(where: { $0.roomId == nil }) {
                list.append(SchedColumn(id: "room:none", title: L("No room"), kind: .room, roomId: nil, day: day, open: open, createMemberId: creator))
            }
            return list
        }
        let shown = !person.isEmpty && person != "none" ? people.filter { $0.id == person } : people
        var list = shown.map { member -> SchedColumn in
            let work = workFor(member.id, day)
            let detail = (member.maxConcurrentVisits ?? 1) > 1 ? LF("%@ at once", String(member.maxConcurrentVisits ?? 1)) : member.professionalTitle
            return SchedColumn(id: "person:\(member.id)", title: member.label, detail: detail, kind: .person, memberId: member.id, day: day, open: open, working: work.working, offNote: work.offNote, image: member.image, createMemberId: member.id)
        }
        if canAssignAnyone && (person == "none" || (person.isEmpty && appointments.contains { $0.assignedMember?.id == nil })) {
            list.append(SchedColumn(id: "person:none", title: L("Nobody yet"), detail: L("Whoever is free"), kind: .unassigned, day: day, open: open, createMemberId: creator))
        }
        return list
    }

    /// The rows the grid draws: the days' opening hours, stretched to the visits shown.
    private var gridRange: SchedGrid.Range {
        SchedGrid.range(shownBlocks, open: rangeDays.flatMap { SchedHours.minutes(openFor($0).ranges) })
    }

    /// The first start, inside the open ranges (the chosen person's working ones), where someone is free.
    private var nextFree: Int? {
        guard view == "day", let load, day >= today else { return nil }
        let open = SchedHours.minutes(openFor(day).ranges)
        guard !open.isEmpty else { return nil }
        let named = !person.isEmpty && person != "none" ? person : nil
        let ranges = named.flatMap { workFor($0, day).working } ?? open
        let length = availability?.defaultAppointmentDurationMinutes ?? 30
        let earliest = day == today ? Int((Double(SchedDay.minuteOfDay(Date())) / 15).rounded(.up)) * 15 : 0
        for range in ranges {
            var minute = max(range.start, earliest)
            while minute + length <= range.end {
                let start = SchedDay.at(day, minute: minute)
                let slot = SchedSlot(id: nil, start: start, end: start.addingTimeInterval(TimeInterval(length * 60)), memberId: named, roomId: nil)
                if SchedConflicts.find(slot, load: load).isEmpty { return minute }
                minute += 15
            }
        }
        return -1
    }

    // MARK: Body

    var body: some View {
        PageScroll(maxWidth: sizeClass == .regular ? 1600 : 820, refresh: { await reloadAll() }) {
            header
            controls
            if view != "list" && !asking.isEmpty {
                SchedAskingCard(visits: asking, onOpen: { pushed = .appointment($0.id) }, onSeeAll: { openList(only: "requests") })
            }
            if view != "list", let online, (online.count ?? 0) > 0 {
                SchedRequestsInbox(list: online) { openRequest = $0 }
            }
            if hasClients == false {
                EmptyState(systemImage: "paw-print", title: L("Add your first client and pet"), message: L("Visits are booked for a client’s pet. Add one in Clients first."),
                           actionTitle: workspace.can(.clientsView) ? L("Go to Clients") : nil, action: { pushed = .section(.clients) }, accent: Theme.lime, panel: true)
            } else if view == "list" {
                SchedVisitList(pager: listPager, filters: $listFilters, members: people, rooms: rooms) { total, doubled in
                    listTotal = total
                    listDoubled = doubled
                }
            } else {
                gridCard
            }
        }
        .onAppear { applyFilter() }
        .reloadsOnScope { await reloadAll() }
        .task(id: rangeKey) { await loadRange() }
        .sheet(item: $booking) { draft in
            SchedBookingSheet(draft: draft) { prompt in
                Task { try? await Task.sleep(for: .milliseconds(450)); gate = prompt }
            }
        }
        .sheet(item: $openRequest) { request in
            SchedRequestSheet(request: request) { id in
                Task { try? await Task.sleep(for: .milliseconds(400)); pushed = .appointment(id) }
            }
        }
        .sheet(item: $gate) { SchedGateSheet(prompt: $0) }
        .sheet(isPresented: $planningSession) {
            SvcSessionFormSheet(session: nil, people: []) { id in
                Task { try? await Task.sleep(for: .milliseconds(450)); openedSession = id }
            }
        }
        .navigationDestination(item: $pushed) { RouteView(route: $0) }
        .navigationDestination(item: $openedSession) { SvcSessionScreen(sessionId: $0) }
    }

    /// The asking screen's day, view, person and room, once.
    private func applyFilter() {
        guard !filterApplied else { return }
        filterApplied = true
        if let wanted = filter.day, wanted.count == 10 { day = wanted }
        if let wanted = filter.view, ["day", "week", "list"].contains(wanted) { chosenView = wanted }
        if let grouping = filter.by, ["staff", "rooms"].contains(grouping), view != "list" { by = grouping }
        if let room = filter.roomId {
            if view == "list" { listFilters.room = room } else { by = "rooms" }
        }
        if let member = filter.memberId {
            if view == "list" { listFilters.person = member }
            if canAssignAnyone { person = member }
            if filter.roomId == nil && view != "list" { by = "staff" }
        }
    }

    // MARK: Header and numbers

    private var header: some View {
        let dateText = view == "list"
            ? L("Every visit, upcoming and past.")
            : view == "week" ? SchedDay.weekLabel(rangeDays.first ?? day, rangeDays.last ?? day) : SchedDay.longLabel(day)
        let place = workspace.multiLocation ? workspace.selectedLocation?.name : nil
        return ModuleHeader(
            icon: "calendar-days",
            title: L("Schedule"),
            subtitle: [dateText, place].compactMap { $0?.nonEmpty }.joined(separator: " · "),
            stats: headerStats,
            storageKey: "schedule"
        ) {
            if canCreate {
                if workspace.offers(.walker, .trainer) {
                    PMButton(L("Group session"), systemImage: "users-round", variant: .outline) { planningSession = true }
                }
                if hasClients != false {
                    PMButton(L("New visit"), systemImage: "plus") { book(day: view == "list" ? today : day) }
                }
            }
        }
    }

    private var headerStats: [ModuleStat] {
        var stats: [ModuleStat] = [
            ModuleStat("visits", label: view == "week" ? L("Visits in these 7 days") : view == "day" ? (day == today ? L("Visits today") : L("Visits that day")) : L("Visits"),
                       value: view == "list" ? (listTotal.map(String.init) ?? "—") : String(activeCount), icon: "calendar-days", accent: Theme.aqua),
        ]
        if view != "list" {
            let free = nextFree
            stats.append(ModuleStat("free", label: L("Next free time"), value: nextFreeValue, hint: nextFreeHint, icon: "clock-3", accent: Theme.lime,
                                    attention: free == -1,
                                    action: free.map { $0 >= 0 } == true && canCreate ? {
                                        book(day: day, minute: free, memberId: !person.isEmpty && person != "none" ? person : nil)
                                    } : nil))
        }
        stats.append(ModuleStat("requests", label: L("Asked for a change"), value: String(asking.count), hint: asking.isEmpty ? nil : L("Families waiting on you"),
                                icon: "message-circle-question", accent: Theme.pink, attention: !asking.isEmpty,
                                active: view == "list" && listFilters.only == "requests", action: { openList(only: "requests") }))
        if onlineWaiting > 0 || (view == "list" && listFilters.status == "requested") {
            stats.append(ModuleStat("online", label: L("To confirm"), value: String(onlineWaiting), hint: L("Booked online, waiting for you"),
                                    icon: "globe", accent: ProviderState.waiting.color, attention: onlineWaiting > 0,
                                    active: view == "list" && listFilters.status == "requested", action: { openList(status: "requested") }))
        }
        if let doubled = view == "list" ? listDoubled : doubledCount {
            stats.append(ModuleStat("double", label: L("Double booked"), value: String(doubled), hint: L("Booked over another on purpose"),
                                    icon: "triangle-alert", accent: Theme.mango, attention: doubled > 0,
                                    active: view == "list" && listFilters.only == "double", action: { openList(only: "double") }))
        }
        return stats
    }

    private var nextFreeValue: String {
        if view == "day" && day < today { return "—" }
        if view == "day" && load != nil && openFor(day).ranges.isEmpty { return L("Closed") }
        guard let nextFree else { return "—" }
        return nextFree == -1 ? L("Full") : SchedDay.timeLabel(nextFree)
    }

    private var nextFreeHint: String? {
        if let nextFree, nextFree >= 0 { return L("Tap to book it") }
        if view != "day" { return L("On the day view") }
        if day < today { return L("This day is over") }
        if load != nil && openFor(day).ranges.isEmpty { return L("Pick another day") }
        return nil
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Segmented(options: [
                .init("day", L("Day"), icon: "rows-3"),
                .init("week", L("Week"), icon: "calendar-days"),
                .init("list", L("List"), icon: "list"),
            ], selection: Binding(get: { view }, set: { switchView($0) }), label: L("View"))
            if view != "list" {
                HStack(spacing: 8) {
                    DayStepper(isToday: day == today, previous: { day = SchedDay.addDays(day, view == "week" ? -7 : -1) }, today: { day = today }, next: { day = SchedDay.addDays(day, view == "week" ? 7 : 1) })
                    PillDatePicker(text: view == "week" ? SchedDay.weekLabel(rangeDays.first ?? day, rangeDays.last ?? day) : SchedDay.shortLabel(day),
                                   date: Binding(get: { SchedDay.date(fromKey: day) }, set: { day = SchedDay.key($0) }), zone: SchedDay.zone)
                    Spacer(minLength: 0)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if canAssignAnyone && people.count > 1 {
                            Menu {
                                Button(L("Everyone")) { person = "" }
                                ForEach(people) { member in Button(member.label) { person = member.id } }
                                Button(L("Nobody yet")) { person = "none" }
                            } label: {
                                PillField(text: person.isEmpty ? L("Everyone") : person == "none" ? L("Nobody yet") : (people.first { $0.id == person }?.label ?? L("Someone")), height: 40)
                            }
                        }
                        if view == "day" && !rooms.isEmpty {
                            Segmented(options: [.init("staff", L("Staff"), icon: "users-round"), .init("rooms", L("Rooms"), icon: "door-open")],
                                      selection: $by, label: L("Show the day by"))
                        }
                        if cancelledCount > 0 || showCancelled {
                            PMButton(showCancelled ? L("Hide cancelled") : LF("Show cancelled (%@)", String(cancelledCount)), systemImage: showCancelled ? "eye-off" : "eye", variant: .outline, size: .compact) { showCancelled.toggle() }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func switchView(_ next: String) {
        chosenView = nil
        storedView = next
        if next == "list" { listTotal = nil; listDoubled = nil }
    }

    private func openList(only: String? = nil, status: String? = nil) {
        var filters = SchedListFilters()
        if let only { filters.only = view == "list" && listFilters.only == only ? "" : only }
        if let status { filters.status = view == "list" && listFilters.status == status ? "" : status }
        filters.when = "upcoming"
        listFilters = filters
        switchView("list")
    }

    // MARK: The day and the week

    /// The grid's card (web: a standard card around `AgendaGrid`): the day's closure or
    /// special hours as a strip on top, then the grid.
    private var gridCard: some View {
        VStack(spacing: 0) {
            if let rangeError, loadedRange == nil {
                ErrorState(message: rangeError) { await loadRange() }
            } else if loadedRange == nil {
                LoadingState()
            } else if columns.isEmpty {
                EmptyState(systemImage: "users-round", title: L("Nobody takes visits in this workspace yet."), accent: Theme.blue)
            } else {
                dayStrip
                SchedAgendaGrid(
                    columns: columns,
                    blocks: shownBlocks,
                    range: gridRange,
                    compact: view == "week",
                    canCreate: canCreate && hasClients != false,
                    secondary: { block in byRooms ? block.memberName : block.room },
                    onOpen: open,
                    onCreate: { column, minute in
                        book(day: column.day, minute: minute, memberId: column.createMemberId, roomId: column.bookRoomId)
                    }
                )
                .opacity(loadedRange == rangeKey ? 1 : 0.6)
                .animation(.easeOut(duration: 0.2), value: loadedRange == rangeKey)
            }
        }
        .frame(maxWidth: .infinity)
        .listCard()
    }

    @ViewBuilder private var dayStrip: some View {
        let hours = openFor(day)
        if view == "day" {
            if let closure = hours.closure, !closure.closed {
                SchedDayStrip(tone: .special, text: LF("%@: %@.", closedNote(day) ?? "", SchedHours.rangesText(hours.ranges)))
            } else if hours.closure?.closed == true {
                SchedDayStrip(tone: .closed, text: LF("%@ — families can’t book online, and a visit booked now asks to confirm.", closedNote(day) ?? ""))
            } else if load != nil && hours.ranges.isEmpty {
                SchedDayStrip(tone: .quiet, text: L("Closed on this day — a visit booked now is marked outside opening hours."))
            }
        }
    }

    /// A visit opens its page; a session opens as one (its pets, its places, its waitlist).
    private func open(_ block: SchedBlock) {
        if let id = block.appointmentId {
            pushed = .appointment(id)
        } else if let session = block.sessionId {
            openedSession = session
        } else {
            pushed = .section(.groups)
        }
    }

    // MARK: Booking

    private func book(day: String, minute: Int? = nil, memberId: String? = nil, roomId: String? = nil) {
        guard canCreate else { return }
        let creator = !person.isEmpty && person != "none" ? person : me?.id
        booking = SchedBookingDraft(day: day, startMinute: minute, memberId: memberId ?? creator, roomId: roomId)
    }

    // MARK: Loading

    private func reloadAll() async {
        guard workspace.can(.appointmentsView) else { return }
        let location = workspace.locationId
        let readsClients = workspace.can(.clientsView)
        async let team = SchedData.members()
        async let places = SchedData.rooms(locationId: location)
        async let week = SchedData.availability(locationId: nil)
        async let clientsTotal: Int? = readsClients ? await SchedData.clientsTotal() : nil
        async let inbox: Void = loadInbox()
        members = await team
        rooms = await places
        availability = await week
        if readsClients { hasClients = ((await clientsTotal) ?? 1) > 0 } else { hasClients = nil }
        await inbox
        // The first load is the range task's; after that (another screen changed something) it is read again here.
        if loadedRange == rangeKey { await loadRange() }
        if view == "list" && listPager.loadedOnce { await listPager.reload() }
    }

    private func loadInbox() async {
        let location = workspace.locationId
        async let changes = SchedData.familyAsking(locationId: location)
        async let requests: SchedOnlineRequestList? = try? await API.get("/provider-online-booking/requests", query: ["locationId": location])
        asking = await changes
        online = await requests
    }

    private func loadRange() async {
        guard view != "list" else { return }
        let key = rangeKey
        let days = rangeDays
        let from = SchedDay.start(days.first ?? day)
        let to = SchedDay.start(SchedDay.addDays(days.last ?? day, 1))
        let location = workspace.locationId
        let who = person
        let groups = workspace.offers(.walker, .trainer)
        do {
            async let visits = Self.visits(from: from, to: to, person: who, locationId: location)
            async let groupSessions: [SchedSession] = groups ? ((try? await API.get("/provider-sessions", query: ["from": DateText.iso(from), "to": DateText.iso(to), "locationId": location])) ?? []) : []
            async let taken: SchedLoad? = try? await SchedData.load(from: from, to: to, locationId: location)
            let loadedVisits = try await visits
            let loadedSessions = await groupSessions
            let loadedLoad = await taken
            guard key == rangeKey else { return }
            appointments = loadedVisits
            sessions = loadedSessions
            load = loadedLoad
            loadedRange = key
            rangeError = nil
        } catch is CancellationError {
        } catch {
            rangeError = errorText(error)
            if loadedRange != nil { Toast.error(error) }
        }
    }

    /// Every visit between two times, a hundred at a time until there are no more.
    private static func visits(from: Date, to: Date, person: String, locationId: String?) async throws -> [SchedAppointment] {
        var items: [SchedAppointment] = []
        var offset = 0
        while offset < 2000 {
            var query: [String: String?] = ["limit": "100", "offset": "\(offset)", "from": DateText.iso(from), "to": DateText.iso(to), "locationId": locationId]
            if person == "none" { query["unassigned"] = "true" } else if !person.isEmpty { query["assignedOrganizationMemberId"] = person }
            let page: Page<SchedAppointment> = try await API.get("/provider-appointments", query: query)
            items += page.items
            if page.hasMore != true || page.items.count < 100 { break }
            offset += 100
        }
        return items
    }
}
