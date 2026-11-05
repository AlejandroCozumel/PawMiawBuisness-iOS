//
//  StaysScreen.swift
//  PawMiawNegocios
//
//  Estancias (web provider.stays.tsx): one place's boarding, daycare and home
//  stays. The module header (BedDouble, the brand blue) with "Nueva estancia"
//  / "Nueva estancia en casa" and its numbers (home stay visits today, in
//  tonight of the places, arriving and leaving today with the late ones
//  counted in and flagged, requests waiting), then the page tabs (board,
//  today's care, rooms and house rules, requests) with the board's ‹ Hoy ›.
//  A pet still here past its day keeps its room and shows red everywhere
//  (backend docs/stays-late-and-dates.md).
//

import SwiftUI

struct StaysScreen: View {
    @EnvironmentObject private var workspace: Workspace

    var body: some View {
        Group {
            if workspace.current != nil && !workspace.can(.staysView) {
                PageScroll { NoAccessState(message: L("Ask the workspace owner to give your role access to stays.")) }
            } else {
                RequireLocation { StaysPageView() }
            }
        }
        .providerPage(L("Stays"), root: true)
    }
}

enum StaysTab: Hashable { case board, today, rooms, requests }

/// What a booking sheet starts from: a room and a day (or nothing chosen yet).
struct StaysBookingPreset: Identifiable {
    let id = UUID()
    var unitId: String?
    var day: String
    var home: Bool = false
}

private struct StaysPageView: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var tab: StaysTab = .board
    @State private var fromDay = StaysDay.add(StaysDay.today(), -1)
    @State private var page: StaysPage?
    @State private var units: [StaysUnit] = []
    @State private var held: [StaysStay] = []
    @State private var familyWaiting = 0
    @State private var homeVisits: [StaysHomeDayVisit] = []
    @State private var error: String?
    @State private var booking: StaysBookingPreset?
    @State private var pushed: ProviderRoute?

    private var days: Int { sizeClass == .regular ? 14 : 7 }
    private var compact: Bool { sizeClass != .regular }
    private var canManage: Bool { workspace.can(.staysManage) }
    private var offersSitting: Bool { workspace.offers(.sitter) }
    /// Rooms, check-in and the care board: boarding and daycare (or a stays business without sitting).
    private var offersRooms: Bool { workspace.offers(.boarding, .daycare) || !offersSitting }
    private var today: String { page?.today ?? StaysDay.today() }
    private var stays: [StaysStay] { page?.items ?? [] }

    var body: some View {
        PageScroll(maxWidth: 1180, refresh: { await load() }) {
            header
            controls
            switch tab {
            case .board: boardTab
            case .today: StaysCareTodayView(canCare: workspace.can(.staysCare))
            case .rooms: StaysRoomsView(canManage: canManage)
            case .requests: StaysRequestsView(held: held)
            }
        }
        .sheet(item: $booking) { preset in
            if preset.home {
                StaysHomeBookingSheet(presetDay: preset.day) { Task { await load() } }
            } else {
                StaysBookingSheet(preset: preset) { Task { await load() } }
            }
        }
        .navigationDestination(item: $pushed) { RouteView(route: $0) }
        .reloadsOnScope { await load() }
        .onChange(of: fromDay) { _, _ in Task { await loadBoard() } }
        .onChange(of: days) { _, _ in Task { await loadBoard() } }
    }

    // MARK: Header and numbers

    private var header: some View {
        ModuleHeader(
            icon: "bed-double",
            title: L("Stays"),
            subtitle: StaysDay.long(today).capitalizedFirst,
            stats: headerStats,
            storageKey: "stays"
        ) {
            if canManage {
                if offersRooms {
                    PMButton(L("New stay"), systemImage: "plus") { booking = StaysBookingPreset(unitId: nil, day: today) }
                }
                if offersSitting {
                    PMButton(L("New home stay"), systemImage: "house") { booking = StaysBookingPreset(unitId: nil, day: today, home: true) }
                }
            }
        }
    }

    private var summary: (tonight: Int, arriving: Int, leaving: Int, lateIn: Int, lateOut: Int) {
        var tonight = 0, arriving = 0, leaving = 0, lateIn = 0, lateOut = 0
        for stay in stays where StaysDay.isRoomHolding(stay.status) && !stay.isHome {
            let pets = stay.petCount
            // A pet still here past its day holds its room tonight too.
            if stay.kind == "boarding" && StaysDay.occupied(kind: stay.kind, from: stay.checkInDay, to: stay.heldUntilDay ?? stay.checkOutDay).contains(today) { tonight += pets }
            if stay.lateArrival == true { lateIn += pets }
            else if stay.checkInDay == today && stay.status != "checked_in" { arriving += pets }
            if stay.lateDeparture == true { lateOut += pets }
            else if stay.checkOutDay == today && stay.status == "checked_in" { leaving += pets }
        }
        return (tonight, arriving, leaving, lateIn, lateOut)
    }

    /// Tonight's places are the rooms that take a night: a playroom is for the day.
    private var capacity: Int {
        units.filter { StaysDay.roomTakes(unitKind: $0.unitKind, stayKind: "boarding") }.reduce(0) { $0 + $1.seats }
    }

    private var headerStats: [ModuleStat] {
        let s = summary
        let requests = held.count + familyWaiting
        var stats: [ModuleStat] = []
        if offersSitting {
            let done = homeVisits.filter { $0.status == "done" }.count
            stats.append(ModuleStat("home", label: L("Home stay visits today"), value: String(homeVisits.count),
                                    hint: homeVisits.isEmpty ? nil : LP(done, "%d done", "%d done (plural)"),
                                    icon: "house", accent: Theme.aqua,
                                    attention: homeVisits.contains { $0.status == "missed" || $0.late == true },
                                    // They are run from Domicilio.
                                    action: { pushed = .section(.homeVisits) }))
        }
        if offersRooms {
            stats.append(ModuleStat("tonight", label: L("In tonight"), value: capacity > 0 ? "\(s.tonight) / \(capacity)" : "\(s.tonight)",
                                    hint: capacity > 0 ? LF("%d places free", max(0, capacity - s.tonight)) : nil,
                                    icon: "bed-double", accent: Theme.lime))
            // Late ones are still today's to do: counted in, flagged.
            stats.append(ModuleStat("arriving", label: L("Arriving today"), value: String(s.arriving + s.lateIn),
                                    hint: s.lateIn > 0 ? LF("%d arriving late", s.lateIn) : nil,
                                    icon: "log-in", accent: Theme.aqua, attention: s.lateIn > 0))
            stats.append(ModuleStat("leaving", label: L("Leaving today"), value: String(s.leaving + s.lateOut),
                                    hint: s.lateOut > 0 ? LF("%d still here past their day", s.lateOut) : nil,
                                    icon: "log-out", accent: Theme.mango, attention: s.lateOut > 0))
        }
        stats.append(ModuleStat("requests", label: L("Requests"), value: String(requests),
                                hint: requests > 0 ? L("Waiting for an answer") : nil,
                                icon: "mail-question-mark", accent: Theme.pink, attention: requests > 0,
                                active: tab == .requests, action: { tab = .requests }))
        return stats
    }

    // MARK: Tabs and the board's days

    private var tabs: [ToneTabs<StaysTab>.Tab] {
        var list: [ToneTabs<StaysTab>.Tab] = [.init(.board, L("Board"), icon: "calendar-range")]
        if offersRooms {
            list.append(.init(.today, L("Today’s care"), icon: "clipboard-check"))
            list.append(.init(.rooms, L("Rooms & rules"), icon: "settings-2"))
        }
        // The requests waiting from families, in the tab's pink bubble.
        list.append(.init(.requests, L("Requests"), icon: "mail-question-mark", count: familyWaiting))
        return list
    }

    private var tabBar: some View {
        ToneTabs(tabs: tabs, selection: $tab, look: .solid, label: L("Stays"))
    }

    private var dayStepper: some View {
        HStack(spacing: 8) {
            IconCircleButton(systemImage: "chevron-left", label: L("Earlier"), tint: Theme.blue) { fromDay = StaysDay.add(fromDay, -days) }
            PMButton(L("Today"), variant: .outline, size: .compact) { fromDay = StaysDay.add(StaysDay.today(), -1) }
            IconCircleButton(systemImage: "chevron-right", label: L("Later"), tint: Theme.blue) { fromDay = StaysDay.add(fromDay, days) }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if compact {
            VStack(alignment: .leading, spacing: 12) {
                tabBar
                if tab == .board { dayStepper }
            }
        } else {
            HStack(spacing: 12) {
                tabBar
                Spacer(minLength: 0)
                if tab == .board { dayStepper }
            }
        }
    }

    @ViewBuilder
    private var boardTab: some View {
        if let page {
            VStack(alignment: .leading, spacing: 24) {
                StaysBoardView(units: units, stays: page.items ?? [], fromDay: fromDay, days: days, today: today,
                               canBook: canManage, offersRooms: offersRooms, offersSitting: offersSitting) { preset in
                    booking = preset
                }
                StaysTodayMovements(stays: page.items ?? [], today: today)
            }
        } else if let error {
            ErrorState(message: error) { await load() }
        } else {
            LoadingState()
        }
    }

    // MARK: Loading

    private func loadBoard() async {
        let to = StaysDay.add(fromDay, days - 1)
        do {
            page = try await API.get("/provider-stays", query: ["from": fromDay, "to": to, "locationId": workspace.locationId])
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = errorText(error)
        }
    }

    private func load() async {
        let location = workspace.locationId
        let today = StaysDay.today()
        let seesOnline = workspace.can(.appointmentsView)
        let sitting = offersSitting
        async let unitsCall: [StaysUnit]? = try? await API.get("/provider-stays/units", query: ["locationId": location])
        async let heldCall: StaysPage? = try? await API.get("/provider-stays", query: ["from": StaysDay.add(today, -1), "to": StaysDay.add(today, 365), "status": "requested", "locationId": location])
        async let requestsCall: StaysRequestList? = try? await API.get("/provider-requests", query: ["scope": "open", "locationId": location])
        async let onlineCall: StaysOnlineList? = seesOnline ? try? await API.get("/provider-online-booking/requests", query: ["locationId": location]) : nil
        async let homeCall: StaysHomeDay? = sitting ? try? await API.get("/provider-homestays/visits", query: ["locationId": location]) : nil
        await loadBoard()
        units = (await unitsCall) ?? units
        held = (await heldCall)?.items ?? []
        let stayKinds: Set<String> = ["boarding", "daycare", "homestay"]
        let families = ((await requestsCall)?.items ?? []).filter { stayKinds.contains($0.kind) && $0.shownStatus == "pending" }.count
        familyWaiting = families + ((await onlineCall)?.count ?? 0)
        homeVisits = ((await homeCall)?.visits ?? []).filter { $0.status != "cancelled" }
    }
}

// MARK: - Today's arrivals and departures

/// Who comes and goes today; an earlier day's arrival not in yet, or departure not gone yet, first and in red.
private struct StaysTodayMovements: View {
    let stays: [StaysStay]
    let today: String

    // Home stays have no arrivals at the front desk: their visits are Domicilio's.
    private var arrivals: [StaysStay] {
        stays.filter { !$0.isHome && (($0.checkInDay == today && ($0.status == "confirmed" || $0.status == "requested")) || $0.lateArrival == true) }
            .sorted { ($0.lateArrival == true ? 1 : 0) > ($1.lateArrival == true ? 1 : 0) }
    }

    private var departures: [StaysStay] {
        stays.filter { !$0.isHome && $0.status == "checked_in" && ($0.checkOutDay == today || $0.lateDeparture == true) }
            .sorted { ($0.lateDeparture == true ? 1 : 0) > ($1.lateDeparture == true ? 1 : 0) }
    }

    var body: some View {
        if !arrivals.isEmpty || !departures.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)], spacing: 16) {
                group(L("Arriving today"), arrivals, departure: false)
                group(L("Leaving today"), departures, departure: true)
            }
        }
    }

    private func group(_ title: String, _ list: [StaysStay], departure: Bool) -> some View {
        Card(spacing: 8) {
            StaysEyebrow(text: title).padding(.bottom, 4)
            if list.isEmpty { Text(L("No one")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
            ForEach(list) { stay in
                NavigationLink(value: ProviderRoute.stay(stay.id)) {
                    StaysTintedRow(tint: stay.late != nil ? ProviderState.problem.color : (departure ? Theme.mango : Theme.aqua),
                                   edge: stay.late != nil ? ProviderState.problem.color : nil) {
                        PetStack(pets: stay.petList.map { ($0.petName, $0.petSpecies, $0.photoUrl) }, size: 40, max: 3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stay.petNames).font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            Text("\(stay.clientName ?? "") · \(stay.unitName ?? L("No room yet"))").font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                            StaysLateLine(stay: stay)
                        }
                        Spacer(minLength: 6)
                        Text(StaysDay.clock(departure ? stay.checkOutTime : stay.checkInTime)).font(.brandHeading(18)).foregroundStyle(Theme.inkStrong)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

fileprivate extension String {
    /// "Jueves 1 de octubre" from "jueves 1 de octubre".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
