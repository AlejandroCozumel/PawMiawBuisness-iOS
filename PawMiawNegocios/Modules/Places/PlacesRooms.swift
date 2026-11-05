//
//  PlacesRooms.swift
//  PawMiawNegocios
//
//  Settings → Rooms ("Espacios"), web provider.rooms.tsx → components/app/rooms/rooms-page.tsx:
//  the places visits happen in (consult rooms, grooming tables, baths, the surgery) and
//  the hospital's wards and cages, of the location this device works at. Added one by
//  one or numbered, copied, put in order, taken out of service for some days, archived
//  or (when nothing ever used them) deleted. Only someone who edits the workspace
//  changes them.
//

import SwiftUI

struct RoomsScreen: View {
    var body: some View {
        RequireLocation { PlacesRoomsPage() }
            .providerPage(L("Rooms"), root: true)
    }
}

/// The sheets the page opens.
enum PlacesRoomSheet: Identifiable {
    case new
    case edit(PlacesRoom)
    case copy(PlacesRoom)
    case out(PlacesRoom)
    case archive(PlacesRoom)
    case delete(PlacesRoom)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let room): "edit-\(room.id)"
        case .copy(let room): "copy-\(room.id)"
        case .out(let room): "out-\(room.id)"
        case .archive(let room): "archive-\(room.id)"
        case .delete(let room): "delete-\(room.id)"
        }
    }
}

private extension PlacesRoomFilter {
    /// The filter chip's icon and colour (web rooms-page.tsx `FILTERS`).
    var icon: String {
        switch self {
        case .all: "door-open"
        case .visits: "stethoscope"
        case .hospital: "bed-double"
        case .out: "wrench"
        case .archived: "archive"
        }
    }

    var tone: Color {
        switch self {
        case .all: Theme.blue
        case .visits: PlacesRoomKind.consult.hue.color
        case .hospital: PlacesRoomKind.ward.hue.color
        case .out: ProviderState.problem.color
        case .archived: ProviderState.closed.color
        }
    }
}

private struct PlacesRoomsPage: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var rooms: [PlacesRoom]?
    @State private var usage: [String: PlacesRoomUsage]?
    @State private var services: [PlacesService] = []
    @State private var loadError: String?
    @State private var filter: PlacesRoomFilter = .all
    @State private var sheet: PlacesRoomSheet?
    @State private var goTo: ProviderRoute?
    @State private var busyRoom: String?
    @State private var addingPreset = false

    private var canView: Bool { workspace.can(.appointmentsView) }
    private var canManage: Bool { workspace.can(.workspaceEdit) }
    private var today: String { DateText.dayKey() }
    private var all: [PlacesRoom] { rooms ?? [] }

    var body: some View {
        Group {
            if workspace.current != nil && !canView {
                PageScroll {
                    EmptyState(systemImage: "lock", title: L("You do not have access to rooms."), message: L("Ask the workspace owner to let your role see visits."), panel: true)
                }
            } else {
                page
            }
        }
        .reloadsOnScope { await load() }
        .sheet(item: $sheet) { which in
            sheetView(which)
        }
        .navigationDestination(item: $goTo) { RouteView(route: $0) }
    }

    @ViewBuilder
    private func sheetView(_ which: PlacesRoomSheet) -> some View {
        switch which {
        case .new:
            PlacesRoomSheetView(room: nil, template: nil, templateName: nil, rooms: all, services: services, onSaved: saved)
        case .edit(let room):
            PlacesRoomSheetView(room: room, template: nil, templateName: nil, rooms: all, services: services, onSaved: saved)
        case .copy(let room):
            PlacesRoomSheetView(room: nil, template: room, templateName: PlacesRoomRules.copyName(room.name, existing: all), rooms: all, services: services, onSaved: saved)
        case .out(let room):
            PlacesRoomOutSheet(room: room, today: today, onSaved: saved, onGo: go)
        case .archive(let room):
            PlacesRoomRemoveSheet(room: room, deleting: false, usage: usage?[room.id], usageLoaded: usage != nil, onDone: saved, onGo: go)
        case .delete(let room):
            PlacesRoomRemoveSheet(room: room, deleting: true, usage: usage?[room.id], usageLoaded: usage != nil, onDone: saved, onGo: go)
        }
    }

    private func saved() {
        announceDataChanged()
    }

    /// From a sheet: close it, then open the page that deals with it.
    private func go(_ route: ProviderRoute) {
        sheet = nil
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            goTo = route
        }
    }

    // MARK: Page

    private var page: some View {
        PageScroll(refresh: { await load() }) {
            header
            if rooms == nil && loadError == nil {
                LoadingState()
            } else if loadError != nil, rooms == nil {
                EmptyState(systemImage: "door-open", title: L("The rooms couldn’t load."), message: L("Check your connection and try again."), actionTitle: L("Try again"), action: { Task { await load() } }, accent: Theme.mango, panel: true)
            } else if all.isEmpty {
                emptyRooms
            } else {
                list
            }
            if rooms != nil { related }
        }
    }

    /// The web's `ProviderModuleHeader`: DoorOpen on the default blue, "Add a room", three numbers.
    private var header: some View {
        let counts = PlacesRoomRules.counts(all, today: today)
        let active = all.filter { !$0.isArchived }
        let visitsToday = active.reduce(0) { $0 + (usage?[$1.id]?.visitsToday ?? 0) }
        let out = counts[.out] ?? 0
        let hospital = counts[.hospital] ?? 0
        let subtitle = L("The places visits happen in. Each booking says whether its room is free, and warns before two visits share one.")
        let shownFilter: PlacesRoomFilter = filter != .all && (counts[filter] ?? 0) == 0 ? .all : filter
        return ModuleHeader(
            icon: "door-open",
            title: L("Rooms"),
            subtitle: workspace.multiLocation ? [workspace.selectedLocation?.name, subtitle].compactMap { $0?.nonEmpty }.joined(separator: " · ") : subtitle,
            stats: [
                ModuleStat("rooms", label: L("Rooms"), value: rooms == nil ? "—" : "\(active.count)", hint: hospital > 0 ? LF("%d for the hospital", hospital) : nil, icon: "door-open", accent: Theme.blue),
                ModuleStat("today", label: L("Visits today"), value: usage == nil ? "—" : "\(visitsToday)", hint: L("Booked into a room"), icon: "calendar-days", accent: Theme.aqua),
                ModuleStat("out", label: L("Out of service"), value: rooms == nil ? "—" : "\(out)", hint: out > 0 ? L("Now or planned") : L("All in service"), icon: "wrench", accent: Theme.lime,
                           active: shownFilter == .out,
                           action: out > 0 ? { filter = filter == .out ? .all : .out } : nil),
            ],
            storageKey: "rooms"
        ) {
            if canManage {
                PMButton(L("Add a room"), systemImage: "plus") { sheet = .new }
            }
        }
    }

    private var list: some View {
        let counts = PlacesRoomRules.counts(all, today: today)
        let shownFilter: PlacesRoomFilter = filter != .all && (counts[filter] ?? 0) == 0 ? .all : filter
        let shown = PlacesRoomRules.filter(all, shownFilter, today: today)
        let groups = PlacesRoomRules.groups(shown)
        let orderable = shownFilter == .all || shownFilter == .visits || shownFilter == .hospital
        let options = PlacesRoomFilter.allCases.filter { $0 == .all || (counts[$0] ?? 0) > 0 }
        return VStack(alignment: .leading, spacing: 24) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        let count = counts[option] ?? 0
                        FilterChip(title: option.title, count: count > 0 ? count : nil, isSelected: shownFilter == option, tone: option.tone, icon: option.icon) {
                            filter = filter == option ? .all : option
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            if groups.isEmpty {
                EmptyState(systemImage: "door-open", title: L("No rooms in use"), message: L("Every room is archived. Make one active again, or add a new one."), actionTitle: canManage ? L("Add a room") : nil, action: { sheet = .new }, accent: Theme.aqua, panel: true)
            } else {
                ForEach(groups, id: \.kind) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            PlacesIconBadge(systemImage: group.kind.systemImage, hue: group.kind.hue, size: 28)
                            Text(group.kind.plural).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                            Chip(text: "\(group.rooms.count)", tone: .muted)
                        }
                        .padding(.horizontal, 4)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], spacing: 12) {
                            ForEach(Array(group.rooms.enumerated()), id: \.element.id) { index, room in
                                PlacesRoomCard(
                                    room: room,
                                    usage: usage?[room.id],
                                    out: PlacesRoomRules.outState(room, today: today),
                                    serviceLabel: serviceLabel,
                                    canManage: canManage,
                                    busy: busyRoom == room.id,
                                    canMoveUp: orderable && index > 0,
                                    canMoveDown: orderable && index < group.rooms.count - 1,
                                    onAction: { action in handle(action, room) }
                                )
                            }
                        }
                    }
                }
            }
            countLine(shown: shown.count, filtered: shownFilter != .all)
        }
    }

    /// "4 rooms · See all · Only someone who edits the workspace can change them."
    private func countLine(shown: Int, filtered: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(LP(shown, "%d room", "%d rooms"))
            if filtered {
                Text("·")
                Button(L("See all")) { filter = .all }
                    .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                    .buttonStyle(.plain)
            }
            if !canManage {
                Text("· " + L("Only someone who edits the workspace can change them."))
            }
        }
        .font(Theme.text(14))
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 4)
    }

    private var serviceLabel: [String: String] {
        Dictionary(services.map { ($0.id, $0.label) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Empty

    /// No rooms yet (web `RoomsEmpty`): the empty panel with "Add a room", and why rooms matter with the quick starts.
    private var emptyRooms: some View {
        VStack(alignment: .leading, spacing: 16) {
            EmptyState(
                systemImage: "door-open",
                title: L("No rooms yet"),
                message: canManage
                    ? L("Add your consult rooms, grooming tables and the surgery. Without rooms, only the person is checked when booking.")
                    : L("Ask whoever runs the workspace to add its rooms in Settings."),
                actionTitle: canManage ? L("Add a room") : nil,
                action: { sheet = .new },
                accent: Theme.aqua,
                panel: true
            )
            Card(padding: 20, spacing: 8) {
                Text(L("What rooms do")).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach([
                        L("Booking shows which room is free, and picks one for the service."),
                        L("Two visits never land in the same room by accident: it warns first."),
                        L("The Schedule can show the day room by room."),
                    ], id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(Theme.blue).frame(width: 6, height: 6).padding(.top, 7)
                            Text(line).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                if canManage {
                    StitchedDivider().padding(.top, 8)
                    Text(L("Start with").uppercased()).font(.brandText(11, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.inkSoft).padding(.top, 8)
                    FlowLayout(spacing: 8) {
                        ForEach(PlacesRoomRules.presets(workspace.current?.enabledCategories ?? [])) { preset in
                            FilterChip(title: presetLabel(preset), isSelected: false, tone: preset.kind.hue.color, icon: preset.kind.systemImage) {
                                Task { await addPreset(preset) }
                            }
                            .disabled(addingPreset)
                            .opacity(addingPreset ? 0.5 : 1)
                        }
                    }
                    Text(L("You can rename them, add more or remove them afterwards.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    private func presetLabel(_ preset: PlacesRoomRules.Preset) -> String {
        preset.count == 1
            ? LF("1 %@", L(preset.name).lowercased())
            : LF("%d %@", preset.count, preset.kind.plural.lowercased())
    }

    // MARK: Related places

    /// The other places the business manages (web `RelatedPlaces`), so nobody looks for them here.
    private var related: some View {
        let categories = workspace.current?.enabledCategories ?? []
        let offersStays = categories.contains { $0 == "boarding" || $0 == "daycare" } && workspace.can(.staysView)
        let seesHospital = workspace.can(.hospitalView)
        let hasWards = (PlacesRoomRules.counts(all, today: today)[.hospital] ?? 0) > 0
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], spacing: 12) {
            if offersStays {
                relatedCard(icon: "bed-double", tone: Theme.aqua, title: L("Kennels and suites for stays"),
                            body: L("Where pets sleep or spend the day has its own list, with a nightly and a daycare rate each. It is managed in Stays, not here."),
                            link: L("Open Stays → Rooms & rules"), route: .section(.stays))
            }
            if seesHospital {
                relatedCard(icon: "heart-pulse", tone: Theme.pink, title: L("Hospital wards and cages"),
                            body: hasWards
                                ? L("The wards and cages above are the Hospital’s places: patients are put in them from its board. This page is the only place they are added or changed.")
                                : L("Add a room of kind Ward or Cage here and it shows on the Hospital’s board, to put patients in. This page is the only place they are added or changed."),
                            link: L("Open the Hospital"), route: .section(.hospital))
            }
            relatedCard(icon: "calendar-days", tone: Theme.butter, title: L("The day, room by room"),
                        body: L("The Schedule’s day view can show one column per room: a visit is booked into a room by clicking its column, and moved by dragging it."),
                        link: L("Open the Schedule by room"), route: .schedule(ScheduleFilter(view: "day", by: "rooms")))
        }
    }

    private func relatedCard(icon: String, tone: Color, title: String, body: String, link: String, route: ProviderRoute) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                PlacesIconBadge(systemImage: icon, size: 40, washPercent: 38, tone: tone)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                    Text(body).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    NavigationLink(value: route) {
                        HStack(spacing: 4) {
                            Text(link)
                            Glyph("chevron-right", size: 16)
                        }
                        .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                        .frame(minHeight: 36)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

// MARK: Loading and actions

    private func load() async {
        guard workspace.current != nil, canView, !workspace.allLocationsChosen else { return }
        let location = workspace.locationId
        do {
            let list: [PlacesRoom] = try await API.get("/provider-rooms", query: ["includeArchived": "true", "locationId": location])
            rooms = list
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            // A refresh that fails keeps the list that was there.
            if rooms == nil { loadError = errorText(error) } else { Toast.error(error) }
        }
        // An older server has no usage: the page shows the rooms without it.
        if let answer: [PlacesRoomUsage] = try? await API.get("/provider-rooms/usage", query: ["locationId": location]) {
            usage = Dictionary(answer.map { ($0.roomId, $0) }, uniquingKeysWith: { a, _ in a })
        }
        if let catalog: PlacesServiceCatalog = try? await API.get("/appointment-services", query: ["scope": "provider"]) {
            services = catalog.services ?? []
        }
    }

    enum CardAction { case edit, copy, moveUp, moveDown, out, putBack, archive, delete, reactivate }

    private func handle(_ action: CardAction, _ room: PlacesRoom) {
        switch action {
        case .edit: sheet = .edit(room)
        case .copy: sheet = .copy(room)
        case .out: sheet = .out(room)
        case .archive: sheet = .archive(room)
        case .delete: sheet = .delete(room)
        case .moveUp: Task { await move(room, -1) }
        case .moveDown: Task { await move(room, 1) }
        case .putBack: Task { await patch(room, ["outOfService": nil], success: LF("%@ is back in service.", room.name)) }
        case .reactivate: Task { await patch(room, ["status": "active"], success: LF("%@ is active again.@room", room.name)) }
        }
    }

    private func move(_ room: PlacesRoom, _ direction: Int) async {
        guard let order = PlacesRoomRules.move(all, roomId: room.id, direction: direction) else { return }
        busyRoom = room.id
        defer { busyRoom = nil }
        do {
            try await API.send("PUT", "/provider-rooms/order", body: ["roomIds": order])
        } catch {
            Toast.error(PlacesRoomRules.errorText(error, fallback: L("Could not change the order.")))
        }
        await load()
        announceDataChanged()
    }

    private func patch(_ room: PlacesRoom, _ body: [String: Any?], success: String) async {
        busyRoom = room.id
        defer { busyRoom = nil }
        do {
            let _: PlacesRoomSaved = try await API.patch("/provider-rooms/\(room.id)", body: body)
            Toast.show(success)
            announceDataChanged()
        } catch {
            Toast.error(PlacesRoomRules.errorText(error, fallback: L("Could not save the room.")))
        }
    }

    private func addPreset(_ preset: PlacesRoomRules.Preset) async {
        let names = PlacesRoomRules.numberedNames(L(preset.name), count: preset.count, existing: all)
        addingPreset = true
        defer { addingPreset = false }
        do {
            var body: [String: Any?] = [
                "rooms": names.map { ["name": $0, "kind": preset.kind.rawValue, "capacity": preset.capacity, "serviceIds": [String]()] as [String: Any] },
            ]
            if let location = workspace.locationId { body["locationId"] = location }
            let made: [PlacesRoomSaved] = try await API.post("/provider-rooms/batch", body: body)
            Toast.show(made.count == 1 ? LF("%@ added.@room", made[0].name) : LF("%d rooms added.", made.count))
            announceDataChanged()
        } catch {
            Toast.error(PlacesRoomRules.errorText(error, fallback: L("Could not save the room.")))
        }
    }
}

// MARK: - A room's card

/// One room (web `RoomCard`): its kind's disc, the name in Fredoka, "KIND · HOLDS",
/// what it is for, the note, and how it stands today over a dashed rule; the ⋯
/// menu for whoever edits the workspace.
private struct PlacesRoomCard: View {
    let room: PlacesRoom
    let usage: PlacesRoomUsage?
    let out: PlacesRoomOutState?
    let serviceLabel: [String: String]
    let canManage: Bool
    let busy: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onAction: (PlacesRoomsPage.CardAction) -> Void

    private var kind: PlacesRoomKind { room.kindEntry }
    private var hospital: Bool { room.isHospital }
    private var archived: Bool { room.isArchived }

    private var capacityLine: String {
        hospital ? LP(room.places, "%d patient", "%d patients") : LP(room.places, "%d visit at a time", "%d visits at a time")
    }

    /// What it holds today: visits for a visit room, places taken for a ward or cage.
    private var occupancy: String? {
        guard !archived, let usage else { return nil }
        if hospital {
            let patients = usage.patients ?? 0
            if patients == 0 { return L("Empty now") }
            return room.places == 1 && patients == 1 ? L("Occupied@ward") : LF("%d of %d places taken", patients, room.places)
        }
        return (usage.visitsToday ?? 0) == 0 ? L("No visits today") : LP(usage.visitsToday ?? 0, "%d visit today", "%d visits today")
    }

    private var busyNow: Bool {
        guard !archived, let usage else { return false }
        return hospital ? (usage.patients ?? 0) > 0 : (usage.visitsToday ?? 0) > 0
    }

    private func outLine(_ out: PlacesRoomOutState) -> String {
        if out.state == .scheduled {
            return out.untilDay.map { LF("Out of service %@ – %@", PlacesDay.label(out.fromDay), PlacesDay.label($0)) } ?? LF("Out of service from %@", PlacesDay.label(out.fromDay))
        }
        return out.untilDay.map { LF("Out of service until %@", PlacesDay.label($0)) } ?? L("Out of service · no return date")
    }

    var body: some View {
        Card(spacing: 12) {
            HStack(alignment: .top, spacing: 4) {
                Button { if canManage { onAction(.edit) } } label: {
                    HStack(alignment: .top, spacing: 12) {
                        PlacesIconBadge(systemImage: kind.systemImage, hue: kind.hue, size: 44, muted: archived)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.name).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.leading)
                            Text("\(kind.label) · \(capacityLine)".uppercased())
                                .font(.brandText(12, weight: .bold)).tracking(1.4).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canManage)
                .accessibilityLabel(canManage ? LF("Edit %@", room.name) : room.name)
                if canManage { menu.padding(.top, -4).padding(.trailing, -6) }
            }

            tags

            if let notes = room.notes?.nonEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Glyph("notebook-pen", size: 14).foregroundStyle(Theme.inkSoft).padding(.top, 3)
                    Text(notes).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                }
            }

            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                StitchedDivider()
                HStack(alignment: .center, spacing: 12) {
                    if archived {
                        HStack(spacing: 6) {
                            Glyph("archive", size: 14)
                            Text(L("Archived@room-one"))
                        }
                        .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkSoft)
                    } else if let out {
                        // On now: the amber chip; planned: dashed, unfilled.
                        Chip(text: outLine(out), tone: .warn, icon: "wrench", pending: out.state == .scheduled)
                    } else {
                        HStack(spacing: 6) {
                            Circle().fill(ProviderState.done.color).frame(width: 8, height: 8)
                            Text(L("In service")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        }
                    }
                    Spacer(minLength: 4)
                    if let occupancy {
                        Text(occupancy).font(Theme.text(12, weight: busyNow ? .bold : .regular)).foregroundStyle(busyNow ? Theme.inkStrong : Theme.inkSoft)
                    }
                }
                .padding(.top, 6)
                if let reason = out?.reason, !archived {
                    Text(reason).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .overlay {
            // Out now: the border takes the amber (web: lime 60% over the border).
            if out?.state == .out && !archived {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.mix(Theme.lime, 60, with: Theme.borderSoft), lineWidth: 1)
            }
        }
        .opacity(archived ? 0.8 : 1)
    }

    /// Up to three services by name, then how many more: a room tied to a dozen stays one card tall.
    private var tags: some View {
        let ids = room.services
        return FlowLayout(spacing: 6) {
            if hospital {
                Chip(text: L("Hospitalized patients only"), tone: .online, icon: "heart-pulse")
            } else if ids.isEmpty {
                Chip(text: L("Any service"), tone: .muted)
            } else {
                ForEach(ids.prefix(3), id: \.self) { id in
                    Chip(text: serviceLabel[id] ?? L("A service you no longer offer"), tone: .info)
                }
                if ids.count > 3 { Chip(text: LF("+%d more", ids.count - 3), tone: .muted) }
            }
        }
    }

    private var menu: some View {
        Menu {
            Button { onAction(.edit) } label: { GlyphLabel(L("Edit"), icon: "pencil") }
            Button { onAction(.copy) } label: { GlyphLabel(L("Duplicate"), icon: "copy") }
            if !archived {
                if canMoveUp { Button { onAction(.moveUp) } label: { GlyphLabel(L("Move up"), icon: "arrow-up") } }
                if canMoveDown { Button { onAction(.moveDown) } label: { GlyphLabel(L("Move down"), icon: "arrow-down") } }
                // Visit rooms only: the Hospital's placement doesn't read it yet.
                if !(hospital && out == nil) {
                    Divider()
                    if !hospital {
                        Button { onAction(.out) } label: { GlyphLabel(out != nil ? L("Change the days out of service") : L("Take out of service"), icon: "wrench") }
                    }
                    if out != nil {
                        Button { onAction(.putBack) } label: { GlyphLabel(L("Put back in service"), icon: "rotate-ccw") }
                    }
                }
            }
            Divider()
            if archived {
                Button { onAction(.reactivate) } label: { GlyphLabel(L("Make active again"), icon: "archive-restore") }
            } else {
                Button { onAction(.archive) } label: { GlyphLabel(L("Archive"), icon: "archive") }
            }
            // Only a room nothing ever used: anything with history is archived instead.
            if let usage, usage.hasHistory == false {
                Button(role: .destructive) { onAction(.delete) } label: { GlyphLabel(L("Delete"), icon: "trash-2") }
            }
        } label: {
            if busy {
                ProgressView().controlSize(.small).frame(width: 40, height: 40)
            } else {
                IconCircleLabel(size: 40, bordered: false)
            }
        }
        .accessibilityLabel(LF("Actions for %@", room.name))
    }
}
