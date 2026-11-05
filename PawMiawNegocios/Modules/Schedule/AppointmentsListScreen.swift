//
//  AppointmentsListScreen.swift
//  PawMiawNegocios
//
//  Every visit, to find one (web: the Agenda's List view; /provider/appointments
//  lands there): by pet, client or service, upcoming or past, by status (with
//  "Por confirmar"), person or room, and the ones that need a look (asked for
//  a change, double booked, "En línea"). One card: the search and the
//  Upcoming/Past/All switch, the filter chips, then the visits under their
//  day, 20 at a time with infinite scroll, and the server's count at the foot.
//  Each opens its visit page; today's booked ones check in (and waiting ones
//  start) from the row.
//

import SwiftUI

struct SchedListFilters: Equatable {
    var q = ""
    /// upcoming · past · all
    var when = "upcoming"
    /// "" = any status.
    var status = ""
    /// "" = everyone, "none" = nobody yet, else a member id.
    var person = ""
    var room = ""
    /// "" · double · requests · online
    var only = ""
}

/// "Citas": the web redirects /provider/appointments to the Agenda's List view; so does this.
struct AppointmentsListScreen: View {
    var body: some View {
        ScheduleScreen(filter: ScheduleFilter(view: "list"))
    }
}

/// The list itself, shared by the Appointments screen and the Agenda's List view.
struct SchedVisitList: View {
    @ObservedObject var pager: Pager<SchedAppointment>
    @Binding var filters: SchedListFilters
    let members: [SchedMember]
    let rooms: [SchedRoom]
    /// The header's numbers for these filters (the Agenda): every visit, and the double booked among them.
    var onCounts: ((Int?, Int?) -> Void)? = nil

    @EnvironmentObject private var workspace: Workspace
    @State private var checkingIn: SchedAppointment?
    @State private var gate: SchedGatePrompt?
    @State private var loadedSearch = ""
    @State private var opened: String?

    static func makePager() -> Pager<SchedAppointment> {
        Pager<SchedAppointment> { _, _ in Page(items: [], total: 0, hasMore: false) }
    }

    private var filterKey: String {
        [filters.when, filters.status, filters.person, filters.room, filters.only, workspace.locationId ?? "", String(workspace.scopeVersion)].joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The search and Upcoming · Past · All.
            VStack(alignment: .leading, spacing: 12) {
                SearchField(prompt: L("Pet, client or service"), text: $filters.q)
                Segmented(options: [
                    .init("upcoming", L("Upcoming")),
                    .init("past", L("Past")),
                    .init("all", L("All")),
                ], selection: $filters.when, label: L("When"))
            }
            .padding(16)
            RowDivider()
            // Status in the colours the rows use; then who, where, and what needs a look.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: L("Any status"), isSelected: filters.status.isEmpty, tone: Theme.blue) { filters.status = "" }
                    ForEach(SchedStatus.all, id: \.self) { status in
                        let tone = ProviderState.appointment(status).color
                        FilterChip(title: SchedStatus.label(status), isSelected: filters.status == status, tone: tone, dot: tone) {
                            filters.status = filters.status == status ? "" : status
                        }
                    }
                    Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 24).padding(.horizontal, 4)
                    if members.count > 1 { personMenu }
                    if !rooms.isEmpty { roomMenu }
                    FilterChip(title: L("Asked for a change"), isSelected: filters.only == "requests", tone: Theme.pink, icon: "message-circle-question") { toggleOnly("requests") }
                    FilterChip(title: L("Double booked"), isSelected: filters.only == "double", tone: Theme.mango, icon: "triangle-alert") { toggleOnly("double") }
                    FilterChip(title: L("Online"), isSelected: filters.only == "online", tone: Theme.lavender, icon: "globe") { toggleOnly("online") }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            RowDivider()

            content

            if !pager.items.isEmpty, let total = pager.total {
                RowDivider()
                Text(pager.isLoading ? L("Updating…") : LP(total, "1 visit", "%d visits"))
                    .font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listCard()
        .task(id: filterKey) { await reload(debounce: false) }
        .debounced(filters.q) { value in
            guard ClientSearch.query(value) != ClientSearch.query(loadedSearch) else { return }
            await reload(debounce: true)
        }
        .sheet(item: $checkingIn) { visit in
            SchedCheckInSheet(appointment: visit, canStart: workspace.can(.appointmentsComplete)) { prompt in
                Task { try? await Task.sleep(for: .milliseconds(450)); gate = prompt }
            }
        }
        .sheet(item: $gate) { SchedGateSheet(prompt: $0) }
        .navigationDestination(item: $opened) { AppointmentDetailScreen(appointmentId: $0) }
    }

    @ViewBuilder private var content: some View {
        if !pager.loadedOnce {
            LoadingState()
        } else if pager.error != nil, pager.items.isEmpty {
            // A failed load is said as one, never as "nothing matches".
            EmptyState(systemImage: "triangle-alert", title: L("The visits didn’t load"), message: L("Check the connection and try again."),
                       actionTitle: L("Try again"), action: { Task { await pager.reload() } }, accent: Theme.mango)
        } else if pager.items.isEmpty {
            EmptyState(systemImage: "search", title: L("No visits match"), message: L("Try another search, or clear the filters."), accent: Theme.blue)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(pager.items.enumerated()), id: \.element.id) { index, visit in
                    let day = SchedDay.key(visit.startsAt) ?? ""
                    let startsDay = index == 0 || SchedDay.key(pager.items[index - 1].startsAt) != day
                    if startsDay {
                        schedDayBand(day)
                    } else {
                        RowDivider()
                    }
                    SchedVisitRow(
                        appointment: visit,
                        action: SchedRowAction.next(for: visit, canCheckIn: workspace.can(.appointmentsCheckIn), canStart: workspace.can(.appointmentsComplete)),
                        canOpenChart: workspace.can(.clientsView),
                        onAction: { act(visit, $0) }
                    )
                    .onAppear { pager.loadMoreIfNeeded(visit) }
                }
                PagerFooter(pager: pager)
            }
        }
    }

    private var personMenu: some View {
        Menu {
            Button(L("Everyone")) { filters.person = "" }
            ForEach(members) { member in Button(member.label) { filters.person = member.id } }
            Button(L("Nobody yet")) { filters.person = "none" }
        } label: {
            FilterMenuLabel(title: filters.person.isEmpty ? L("Everyone") : filters.person == "none" ? L("Nobody yet") : (members.first { $0.id == filters.person }?.label ?? L("Someone")), selected: !filters.person.isEmpty)
        }
    }

    private var roomMenu: some View {
        Menu {
            Button(L("Any room")) { filters.room = "" }
            ForEach(rooms) { room in Button(room.name) { filters.room = room.id } }
        } label: {
            FilterMenuLabel(title: filters.room.isEmpty ? L("Any room") : (rooms.first { $0.id == filters.room }?.name ?? L("Room")), selected: !filters.room.isEmpty)
        }
    }

    private func toggleOnly(_ value: String) {
        filters.only = filters.only == value ? "" : value
    }

    private func act(_ visit: SchedAppointment, _ action: SchedRowAction) {
        switch action {
        case .checkIn: checkingIn = visit
        case .start: Task { await SchedVisitOps.startWithGate(visit) { gate = $0 } }
        // Answering and finishing happen on the visit's page.
        case .open, .answer, .finish: opened = visit.id
        }
    }

    private func baseQuery() -> [String: String?] {
        let f = filters
        var query: [String: String?] = ["locationId": workspace.locationId]
        if f.when == "upcoming" {
            query["from"] = DateText.iso(SchedDay.start(SchedDay.today))
            query["hideMissed"] = "true"
        }
        if f.when == "past" {
            query["to"] = DateText.iso(Date())
            query["order"] = "desc"
        }
        // The search rule of every list: the server searches from two characters.
        if let q = ClientSearch.query(f.q) { query["search"] = q }
        if !f.status.isEmpty { query["status"] = f.status }
        if f.person == "none" { query["unassigned"] = "true" } else if !f.person.isEmpty { query["assignedOrganizationMemberId"] = f.person }
        if !f.room.isEmpty { query["roomId"] = f.room }
        return query
    }

    private func reload(debounce: Bool) async {
        loadedSearch = filters.q
        var query = baseQuery()
        switch filters.only {
        case "double": query["doubleBooked"] = "true"
        case "requests": query["requests"] = "true"
        case "online": query["online"] = "true"
        default: break
        }
        let fixed = query
        pager.fetch = { offset, limit in
            var q = fixed
            q["limit"] = "\(limit)"
            q["offset"] = "\(offset)"
            return try await API.get("/provider-appointments", query: q)
        }
        await pager.reload()
        guard let onCounts else { return }
        if filters.only == "double" {
            onCounts(pager.total, pager.total)
        } else {
            var q = baseQuery()
            q["limit"] = "1"
            q["offset"] = "0"
            q["doubleBooked"] = "true"
            let doubled: Page<SchedAppointment>? = try? await API.get("/provider-appointments", query: q)
            onCounts(pager.total, doubled?.total)
        }
    }
}

