//
//  PlacesRoomSheets.swift
//  PawMiawNegocios
//
//  The Rooms page's sheets (web components/app/rooms/room-sheet.tsx,
//  room-out-sheet.tsx, room-archive-sheet.tsx): add or change a room (a new one
//  is two steps, its kind then its details, and may add several numbered at
//  once), take a visit room out of service for some days, and archive or delete.
//

import SwiftUI

private extension PlacesRoomKind {
    /// The sheet's colour: the kind's own hue, as on the web (`ROOM_KIND_HUE`).
    var accent: ModalAccent {
        switch self {
        case .consult: .hue(.sky)
        case .surgery: .peach
        case .treatment: .hue(.butter)
        case .ward, .cage: .hue(.periwinkle)
        case .grooming: .hue(.lavender)
        case .bath: .hue(.teal)
        case .other: .hue(.grey)
        }
    }
}

// MARK: - Add or change a room

struct PlacesRoomSheetView: View {
    let room: PlacesRoom?
    let template: PlacesRoom?
    let templateName: String?
    let rooms: [PlacesRoom]
    let services: [PlacesService]
    let onSaved: () -> Void

    private enum Step { case kind, details }

    private struct Snapshot: Equatable {
        var kind: PlacesRoomKind?
        var name: String
        var count: Int
        var capacity: Int
        var serviceIds: [String]
        var notes: String
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var step: Step
    @State private var draft: Snapshot
    @State private var saving = false
    private let initial: Snapshot

    init(room: PlacesRoom?, template: PlacesRoom?, templateName: String?, rooms: [PlacesRoom], services: [PlacesService], onSaved: @escaping () -> Void) {
        self.room = room
        self.template = template
        self.templateName = templateName
        self.rooms = rooms
        self.services = services
        self.onSaved = onSaved
        let from = room ?? template
        let start = Snapshot(
            kind: from.map(\.kindEntry),
            name: room?.name ?? templateName ?? "",
            count: 1,
            capacity: from?.places ?? 1,
            serviceIds: from?.services ?? [],
            notes: from?.notes ?? ""
        )
        initial = start
        _draft = State(initialValue: start)
        _step = State(initialValue: room != nil || template != nil ? .details : .kind)
    }

    private var editing: Bool { room != nil }
    private var hospital: Bool { draft.kind?.isHospital ?? false }
    private var names: [String] { PlacesRoomRules.numberedNames(draft.name, count: editing ? 1 : draft.count, existing: rooms) }
    private var dirty: Bool { draft != initial || (!editing && template == nil && step == .details) }
    /// Services it was tied to that the business no longer offers: still listed, so they can be unticked.
    private var gone: [String] { draft.serviceIds.filter { id in !services.contains { $0.id == id } } }

    private var title: String {
        if let room { return LF("Edit %@", room.name) }
        if let template { return LF("Copy of %@", template.name) }
        return L("Add a room")
    }

    private var subtitle: String {
        hospital
            ? L("A place for hospitalized patients. It never shows in the Schedule or when placing a visit.")
            : L("A place visits happen in. Two visits never share it unless it holds more than one.")
    }

    private var primaryTitle: String {
        if step == .kind { return L("Continue") }
        if editing { return L("Save room") }
        return names.count > 1 ? LF("Add %d rooms", names.count) : L("Add room")
    }

    var body: some View {
        ProviderModal(
            title: title,
            subtitle: subtitle,
            systemImage: draft.kind?.systemImage ?? "door-open",
            accent: draft.kind?.accent ?? .aqua,
            isDirty: dirty,
            form: form,
            primaryTitle: primaryTitle,
            isWorking: saving,
            steps: editing ? nil : ModalSteps([L("Kind"), L("Details")], current: step == .kind ? 0 : 1),
            // A new room past its kind goes back to it; a copy starts on its details.
            onBack: !editing && template == nil && step == .details ? { step = .kind } : nil,
            primaryIcon: step == .kind ? nil : (editing ? "save" : "plus"),
            onPrimary: primary
        ) {
            if step == .kind { kindStep } else { details }
        }
    }

    // MARK: Steps

    /// What kind of place (web `OptionCardGrid`): a card per kind with its icon, name and line, in the web's order.
    private var kindStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("What kind of place is it?")).font(.brandHeading(16.8, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                Text(L("Visits are booked into consult rooms, tables and baths. Wards and cages hold hospitalized patients only.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            .id("kind")
            OptionCards(options: PlacesRoomKind.allCases.map { kind in
                OptionCard(kind, title: kind.label, description: kind.hint, icon: kind.systemImage, accent: kind.hue.color)
            }, selection: Binding(get: { draft.kind }, set: { next in if let next { choose(next) } }), invalid: form.error("kind") != nil)
        }
    }

    @ViewBuilder
    private var details: some View {
        if !editing, let kind = draft.kind {
            // What it is about, once chosen: the kind (tap to change it), where it goes, what it copies.
            FlowLayout(spacing: 6) {
                Button { step = .kind } label: { Chip(text: kind.label, tone: .muted, icon: kind.systemImage) }
                    .buttonStyle(.plain)
                    .accessibilityHint(L("Back"))
                if Workspace.shared.multiLocation, let place = Workspace.shared.selectedLocation {
                    Chip(text: place.name, tone: .muted, icon: "map-pin")
                }
                if let template { Chip(text: LF("Copy of %@", template.name), tone: .muted, icon: "copy") }
            }
        }

        if editing {
            ModalSection(title: L("What kind of place"), systemImage: "door-open", tint: Theme.borderSoft) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(PlacesRoomKind.allCases) { kind in
                        let on = draft.kind == kind
                        Button { choose(kind) } label: {
                            HStack(spacing: 8) {
                                PlacesIconBadge(systemImage: kind.systemImage, hue: kind.hue, size: 32, washPercent: on ? 38 : 20)
                                Text(kind.label).font(Theme.text(14, weight: .bold)).foregroundStyle(on ? Theme.inkStrong : Theme.inkSoft).lineLimit(2).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(on ? Theme.inkStrong : Theme.borderSoft, lineWidth: 2))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(saving)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }

        PMTextField(L("Name"), text: $draft.name, key: "name", form: form, prompt: hospital ? L("e.g. Ward A, Cage 3") : L("e.g. Consult room 1, Grooming table"), capitalization: .words, required: true)

        FormField(label: hospital ? L("Patients at once") : L("Visits at once"),
                  hint: hospital
                    ? L("How many hospitalized patients it holds. A cage holds one; a ward holds as many as it has places.")
                    : L("How many pets can be seen in it at the same time. A consult room holds one; a big grooming area may hold two or three.")) {
            PlacesCountStepper(label: hospital ? L("Patients at once") : L("Visits at once"), value: $draft.capacity, range: 1...PlacesRoomRules.capacityMax)
                .frame(minHeight: 48)
        }

        if !editing {
            ModalSection(title: L("How many like this"), systemImage: "users-round", tint: Theme.butter) {
                PlacesCountStepper(label: L("How many like this"), value: $draft.count, range: 1...PlacesRoomRules.copiesMax)
                Text(namesPreview).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
        }

        if hospital {
            Text(L("Wards and cages hold hospitalized patients only: they never show in the schedule or when placing a visit."))
                .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(Theme.pink, 14), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        } else if !services.isEmpty || !gone.isEmpty {
            ModalSection(title: L("Used for"), subtitle: L("Pick the services that happen here and it is chosen first for them. Leave it empty if anything can happen here."), systemImage: "stethoscope", tint: Theme.borderSoft) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(services + gone.map { PlacesService(id: $0, label: L("A service you no longer offer")) }) { service in
                        let id = service.id
                        let on = draft.serviceIds.contains(id)
                        Button {
                            if on { draft.serviceIds.removeAll { $0 == id } } else { draft.serviceIds.append(id) }
                        } label: {
                            HStack(spacing: 12) {
                                Tick(on: on)
                                Text(service.label).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 6)
                            .frame(minHeight: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(saving)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                Text(draft.serviceIds.isEmpty ? L("Any service") : LP(draft.serviceIds.count, "%d service chosen", "%d services chosen"))
                    .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
            }
        }

        PMTextField(L("Note for the team"), text: $draft.notes, key: "notes", form: form, prompt: L("e.g. The big scale is here. Keep the door closed for cats."), multiline: true)
    }

    private var namesPreview: String {
        if draft.count == 1 { return L("One room. Raise it to add several at once, numbered for you.") }
        let list = names
        guard !list.isEmpty else { return L("Type the name and they are numbered for you.") }
        let shown = list.count > 4 ? "\(list.prefix(3).joined(separator: ", ")) … \(list[list.count - 1])" : list.joined(separator: ", ")
        return LF("It adds: %@", shown)
    }

    // MARK: Actions

    private func choose(_ kind: PlacesRoomKind) {
        draft.kind = kind
        form.clear("kind")
        // A cage holds one patient; wards and cages are never "for" a service.
        if kind == .cage { draft.capacity = 1 }
        if kind.isHospital { draft.serviceIds = [] }
        if step == .kind { step = .details }
    }

    private func primary() {
        if step == .kind {
            // Nothing chosen yet: said like any invalid field, never a greyed button.
            guard form.check([("kind", draft.kind == nil ? L("What kind of place is it?") : nil)]) else { return }
            step = .details
            return
        }
        guard let kind = draft.kind else { step = .kind; return }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = names
        let nameProblem: String? = name.isEmpty
            ? L("Give the room a name.")
            : (list.count == 1 && PlacesRoomRules.nameTaken(list[0], rooms: rooms, except: room?.id) ? LF("There is already a room called %@ here.", list[0]) : nil)
        guard form.check([("name", nameProblem)]) else { return }

        var values: [String: Any?] = [
            "kind": kind.rawValue,
            "capacity": draft.capacity,
            "serviceIds": kind.isHospital ? [String]() : draft.serviceIds,
            "notes": draft.notes.nonEmpty,
        ]
        saving = true
        Task {
            defer { saving = false }
            do {
                if let room {
                    values["name"] = name
                    let _: PlacesRoomSaved = try await API.patch("/provider-rooms/\(room.id)", body: values)
                    Toast.show(L("Room saved."))
                } else if list.count > 1 {
                    let rows: [[String: Any?]] = list.map { entry in
                        var row = values
                        row["name"] = entry
                        return row
                    }
                    var body: [String: Any?] = ["rooms": rows]
                    if let location = Workspace.shared.locationId { body["locationId"] = location }
                    let made: [PlacesRoomSaved] = try await API.post("/provider-rooms/batch", body: body)
                    Toast.show(LF("%d rooms added.", made.count))
                } else {
                    values["name"] = name
                    if let location = Workspace.shared.locationId { values["locationId"] = location }
                    let saved: PlacesRoomSaved = try await API.post("/provider-rooms", body: values)
                    Toast.show(LF("%@ added.@room", saved.name))
                }
                onSaved()
                dismiss()
            } catch {
                if let api = error as? APIError, api.code == "room_name_taken" {
                    _ = form.check([("name", LF("There is already a room called %@ here.", name))])
                    return
                }
                Toast.error(PlacesRoomRules.errorText(error, fallback: L("Could not save the room.")))
            }
        }
    }
}

// MARK: - Out of service

struct PlacesRoomOutSheet: View {
    let room: PlacesRoom
    let today: String
    let onSaved: () -> Void
    let onGo: (ProviderRoute) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fromDate: Date
    @State private var untilDate: Date
    @State private var openEnded: Bool
    @State private var reason: String
    @State private var touched = false
    @State private var visits: PlacesRoomOutVisits?
    @State private var checking = false
    @State private var saving = false
    private let current: PlacesRoomOutState?

    init(room: PlacesRoom, today: String, onSaved: @escaping () -> Void, onGo: @escaping (ProviderRoute) -> Void) {
        self.room = room
        self.today = today
        self.onSaved = onSaved
        self.onGo = onGo
        let state = PlacesRoomRules.outState(room, today: today)
        current = state
        _fromDate = State(initialValue: PlacesDay.date(state?.fromDay ?? today))
        _untilDate = State(initialValue: PlacesDay.date(state?.untilDay ?? state?.fromDay ?? today))
        _openEnded = State(initialValue: state != nil && state?.untilDay == nil)
        _reason = State(initialValue: state?.reason ?? "")
    }

    private var fromDay: String { PlacesDay.key(fromDate) }
    private var untilDay: String? { openEnded ? nil : PlacesDay.key(max(untilDate, fromDate)) }
    private var minFrom: Date {
        if let current, current.state == .out, current.fromDay < today { return PlacesDay.date(current.fromDay) }
        return PlacesDay.date(today)
    }
    private var dayCount: Int {
        let calendar = DateText.calendar
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: fromDate), to: calendar.startOfDay(for: max(untilDate, fromDate))).day ?? 0
        return days + 1
    }

    var body: some View {
        ProviderModal(
            title: current != nil ? LF("%@ is out of service", room.name) : LF("Take %@ out of service", room.name),
            subtitle: L("For maintenance or a repair. Nothing is cancelled: visits already booked in it stay, and booking into it those days asks first."),
            systemImage: "wrench",
            accent: .lime,
            isDirty: touched,
            primaryTitle: current != nil ? L("Save days") : L("Take out of service"),
            isWorking: saving,
            secondaryActions: current != nil ? [ModalAction(L("Put back in service"), icon: "rotate-ccw", isWorking: saving) { putBack() }] : [],
            primaryIcon: "wrench",
            onPrimary: save
        ) {
            DateTimeField(label: L("From"), date: Binding(get: { fromDate }, set: { fromDate = $0; if untilDate < $0 { untilDate = $0 }; touched = true }), min: minFrom, components: [.date])
            if !openEnded {
                DateTimeField(label: L("Until"), date: Binding(get: { untilDate }, set: { untilDate = $0; touched = true }), min: fromDate, components: [.date],
                              hint: dayCount == 1 ? L("1 day") : LF("%d days", dayCount))
            }

            ToggleRow(title: L("No return date yet"), subtitle: L("It stays out until you put it back in service."), isOn: Binding(get: { openEnded }, set: { openEnded = $0; touched = true }))

            PMTextField(L("Why (optional)"), text: Binding(get: { reason }, set: { reason = $0; touched = true }), prompt: L("e.g. Painting, the table is being repaired"))

            visitsNotice

        }
        .task(id: "\(fromDay)|\(untilDay ?? "open")") { await check() }
    }

    /// What is still booked in it then: said and linked, never moved for anyone.
    @ViewBuilder
    private var visitsNotice: some View {
        if checking && visits == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("Checking what is booked in it…")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
        } else if let visits, let count = visits.count, count > 0 {
            PlacesConsequenceRow(
                systemImage: "calendar-clock",
                text: visits.firstDay.map { LF("The first is on %@. They keep their room until you move them from the Schedule.", PlacesDay.label($0)) } ?? L("They keep their room until you move them from the Schedule."),
                title: count == 1 ? L("1 visit is still booked in it those days.") : LF("%d visits are still booked in it those days.", count),
                actionTitle: L("See them in the Schedule"),
                action: { onGo(.schedule(ScheduleFilter(roomId: room.id, view: "list"))) }
            )
        } else if visits != nil {
            HStack(spacing: 8) {
                Glyph("calendar-check-2", size: 16).foregroundStyle(ProviderState.done.color)
                Text(L("Nothing is booked in it those days.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func check() async {
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        checking = true
        defer { checking = false }
        let answer: PlacesRoomOutVisits? = try? await API.get("/provider-rooms/\(room.id)/out-of-service-visits", query: ["fromDay": fromDay, "untilDay": untilDay])
        guard !Task.isCancelled else { return }
        visits = answer
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                let out: [String: Any?] = ["fromDay": fromDay, "untilDay": untilDay, "reason": reason.nonEmpty]
                let saved: PlacesRoomSaved = try await API.patch("/provider-rooms/\(room.id)", body: ["outOfService": out])
                let left = saved.visitsWhileOut?.count ?? 0
                Toast.show(left > 0
                    ? (left == 1 ? LF("%@ is out of service. 1 visit is still booked in it then.", room.name) : LF("%@ is out of service. %d visits are still booked in it then.", room.name, left))
                    : LF("%@ is out of service.", room.name))
                onSaved()
                dismiss()
            } catch {
                Toast.error(PlacesRoomRules.errorText(error, fallback: L("Could not save the room.")))
            }
        }
    }

    private func putBack() {
        saving = true
        Task {
            defer { saving = false }
            do {
                let _: PlacesRoomSaved = try await API.patch("/provider-rooms/\(room.id)", body: ["outOfService": nil])
                Toast.show(LF("%@ is back in service.", room.name))
                onSaved()
                dismiss()
            } catch {
                Toast.error(PlacesRoomRules.errorText(error, fallback: L("Could not save the room.")))
            }
        }
    }
}

// MARK: - Archive or delete

struct PlacesRoomRemoveSheet: View {
    let room: PlacesRoom
    let deleting: Bool
    let usage: PlacesRoomUsage?
    let usageLoaded: Bool
    let onDone: () -> Void
    let onGo: (ProviderRoute) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    private var patients: Int { usage?.patients ?? 0 }

    var body: some View {
        Group {
            if patients > 0 {
                // Patients in it: neither archived nor deleted — one thing to do first, with the way there.
                ProviderModal(
                    title: LF("%@ has patients in it", room.name),
                    subtitle: patients == 1
                        ? L("1 hospitalized patient is in it. Move the patient to another ward or cage first; then it can be archived.")
                        : LF("%d hospitalized patients are in it. Move them to another ward or cage first; then it can be archived.", patients),
                    systemImage: "bed-double",
                    accent: .pink,
                    primaryTitle: L("Open the Hospital"),
                    cancelTitle: L("Close"),
                    primaryIcon: "bed-double",
                    onPrimary: { onGo(.section(.hospital)) }
                ) {
                    // A question with nothing under it: the sheet fits its header and buttons.
                    EmptyView()
                }
            } else if deleting {
                // Never used, so nothing to read before: the kit's plain confirm.
                ConfirmSheet(
                    title: LF("Delete %@?", room.name),
                    message: L("Nothing was ever booked in it, so it is removed for good. This can’t be undone."),
                    confirmTitle: L("Delete room"),
                    destructive: true,
                    cancelTitle: L("Keep it@room")
                ) { _ in
                    try await remove()
                }
            } else {
                // The web's ProviderConfirmSheet with what archiving leaves behind under it.
                ProviderModal(
                    title: LF("Archive %@?", room.name),
                    subtitle: L("It leaves the booking sheet and the Schedule’s columns, and can’t be booked."),
                    systemImage: "triangle-alert",
                    accent: .pink,
                    primaryTitle: L("Archive room"),
                    primaryVariant: .destructive,
                    isWorking: working,
                    cancelTitle: L("Keep it@room"),
                    primaryIcon: "triangle-alert",
                    onPrimary: confirm
                ) {
                    if let usage {
                        if let upcoming = usage.upcomingVisits, upcoming > 0 {
                            PlacesConsequenceRow(
                                systemImage: "calendar-clock",
                                text: upcoming == 1
                                    ? L("1 visit is still booked in it. It keeps the room’s name; nothing is cancelled or moved for you.")
                                    : LF("%d visits are still booked in it. They keep the room’s name; nothing is cancelled or moved for you.", upcoming),
                                actionTitle: L("See them in the Schedule"),
                                action: { onGo(.schedule(ScheduleFilter(roomId: room.id, view: "list"))) }
                            )
                        }
                        if usage.hasHistory == true {
                            PlacesConsequenceRow(systemImage: "history", text: L("Past visits keep it, and you can make it active again any time."))
                        }
                    } else if !usageLoaded {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L("Checking what is booked in it…")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    /// Deleting, for the plain confirm: it was used since the page loaded — say so and offer
    /// archiving instead (the sheet closes); any other refusal stays on the sheet in the room's words.
    private func remove() async throws {
        do {
            try await API.send("DELETE", "/provider-rooms/\(room.id)")
            Toast.show(LF("%@ was deleted.", room.name))
            onDone()
        } catch let api as APIError where api.code == "room_has_history" {
            Toast.error(LF("%@ has visits or patients in its history, so it can’t be deleted. Archive it instead.", room.name))
            onDone()
        } catch {
            throw APIError(status: (error as? APIError)?.status ?? 0, message: PlacesRoomRules.errorText(error, fallback: L("Could not delete the room.")), code: nil, fields: [:])
        }
    }

    private func confirm() {
        working = true
        Task {
            defer { working = false }
            do {
                let _: PlacesRoomSaved = try await API.patch("/provider-rooms/\(room.id)", body: ["status": "archived"])
                Toast.show(LF("%@ was archived.", room.name))
                onDone()
                dismiss()
            } catch {
                Toast.error(PlacesRoomRules.errorText(error, fallback: L("Could not archive the room.")))
            }
        }
    }
}
