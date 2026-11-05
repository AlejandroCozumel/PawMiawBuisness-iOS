//
//  PlacesRelocate.swift
//  PawMiawNegocios
//
//  "Por reubicar" (web provider.relocate.tsx → components/app/locations/relocate-page.tsx):
//  visits still to come at locations the plan paused. Each moves to an open
//  location at the same time — checked like a booking (the server names who or
//  which room is taken, or the hours, and it moves only on purpose) — or is
//  cancelled with a notice to the family. Several move at once. Never cancelled
//  silently.
//

import SwiftUI

struct RelocateScreen: View {
    var body: some View {
        PlacesRelocatePage()
            .providerPage(L("To relocate"), root: true)
    }
}

private struct PlacesMoveBatch: Identifiable {
    let id = UUID()
    let visits: [PlacesRelocationVisit]
}

private struct PlacesRelocatePage: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var visits: [PlacesRelocationVisit]?
    @State private var loadError: String?
    @State private var selected: Set<String> = []
    @State private var moving: PlacesMoveBatch?
    @State private var cancelling: PlacesRelocationVisit?

    /// Owners and admins move or cancel visits at a paused location (the web's "Todas las sedes" people).
    private var canSee: Bool { workspace.isOwnerOrAdmin && workspace.can(.appointmentsView) }
    private var canMove: Bool { workspace.can(.appointmentsEdit) }
    private var canCancel: Bool { workspace.can(.appointmentsCancel) }
    private var list: [PlacesRelocationVisit] { visits ?? [] }
    private var chosen: [PlacesRelocationVisit] { list.filter { selected.contains($0.id) } }

    private func zone(_ id: String?) -> String? {
        guard let id, let place = workspace.allLocations.first(where: { $0.id == id }) else { return nil }
        return place.timezone?.nonEmpty ?? place.availability?.timezone
    }

    var body: some View {
        Group {
            if workspace.current != nil && !canSee {
                PageScroll {
                    EmptyState(systemImage: "lock", title: L("Only owners and admins relocate visits."), message: L("Visits at a paused location are moved or cancelled by the workspace owner or an admin."), panel: true)
                }
            } else {
                page
            }
        }
        .reloadsOnScope { await load() }
        .sheet(item: $moving) { batch in
            PlacesMoveSheet(visits: batch.visits, targets: workspace.memberLocations, zoneOf: zone) { moved in
                selected.subtract(moved)
                Task { await load() }
            }
        }
        .sheet(item: $cancelling) { visit in
            PlacesCancelRelocationSheet(visit: visit, when: PlacesWhen.text(visit.startsAt, zone: zone(visit.locationId))) {
                selected.remove(visit.id)
                Task { await load() }
            }
        }
    }

    private var page: some View {
        PageScroll(refresh: { await load() }) {
            header

            if !chosen.isEmpty && canMove { selectionBar }

            if visits == nil && loadError == nil {
                LoadingState()
            } else if let loadError, visits == nil {
                ErrorState(message: loadError) { await load() }
            } else if list.isEmpty {
                EmptyState(systemImage: "check", title: L("Nothing to relocate"), message: L("Every visit to come is at an open location."), accent: Theme.mango, panel: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if canMove {
                        Button {
                            selected = chosen.count == list.count ? [] : Set(list.map(\.id))
                        } label: {
                            HStack(spacing: 12) {
                                Tick(on: chosen.count == list.count, mixed: !chosen.isEmpty && chosen.count < list.count)
                                Text(L("Select every visit").uppercased()).font(.brandText(12, weight: .heavy)).tracking(1.6).foregroundStyle(Theme.inkSoft)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Select every visit"))
                    }
                    LazyVStack(spacing: 8) {
                        ForEach(list) { visit in row(visit) }
                    }
                }
            }
        }
    }

    /// The web's `ProviderModuleHeader`: ArrowRightLeft on mango, the visits and the paused places.
    private var header: some View {
        let places = Array(Set(list.compactMap { $0.locationName?.nonEmpty })).sorted()
        let pausedCount = workspace.allLocations.filter { $0.status == "paused" }.count
        return ModuleHeader(
            icon: "arrow-right-left",
            title: L("To relocate"),
            subtitle: L("Visits still to come at locations the plan paused. Move each to an open location at the same time, or cancel it and the family is told."),
            accent: Theme.mango,
            stats: [
                ModuleStat("visits", label: L("Visits"), value: visits == nil ? "—" : "\(list.count)", icon: "calendar-x-2", accent: Theme.mango, attention: !list.isEmpty),
                ModuleStat("paused", label: L("Paused"), value: visits == nil ? "—" : "\(pausedCount)", hint: places.isEmpty ? nil : places.joined(separator: ", "), icon: "circle-pause", accent: Theme.pink),
            ],
            storageKey: "relocate"
        )
    }

    /// What is chosen, and what to do with it (web: a white capsule bar with the card shadow).
    private var selectionBar: some View {
        HStack(spacing: 6) {
            Text(chosen.count == 1 ? L("1 selected") : LF("%d selected", chosen.count))
                .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
            Spacer(minLength: 4)
            PMButton(L("Clear"), systemImage: "x", variant: .outline, size: .compact) { selected = [] }
            PMButton(L("Move to…"), systemImage: "arrow-right-left", size: .compact) { moving = PlacesMoveBatch(visits: chosen) }
        }
        .padding(6)
        .padding(.leading, 10)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
        .cardShadow()
    }

    private func row(_ visit: PlacesRelocationVisit) -> some View {
        let on = selected.contains(visit.id)
        return Card(padding: 12, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if canMove {
                    Button {
                        if on { selected.remove(visit.id) } else { selected.insert(visit.id) }
                    } label: {
                        Tick(on: on).padding(.top, 4).frame(minWidth: 28, minHeight: 28, alignment: .top).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LF("Select %@", visit.pet))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(PlacesWhen.text(visit.startsAt, zone: zone(visit.locationId))).font(Theme.text(14, weight: .heavy)).foregroundStyle(Theme.blue)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(visit.pet).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                        if let client = visit.clientName?.nonEmpty { Text("· \(client)").font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft) }
                    }
                    .lineLimit(1)
                    FlowLayout(spacing: 12, lineSpacing: 2) {
                        if let service = visit.serviceLabel?.nonEmpty { Text(service).lineLimit(1) }
                        if let person = visit.assignedName?.nonEmpty {
                            HStack(spacing: 4) { Glyph("user-round", size: 12); Text(person) }
                        }
                        if let place = visit.locationName?.nonEmpty {
                            HStack(spacing: 4) { Glyph("circle-pause", size: 12); Text(place) }
                                .fontWeight(.bold).foregroundStyle(Theme.inkStrong)
                        }
                    }
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            if canCancel || canMove {
                HStack(spacing: 8) {
                    if canCancel {
                        PMButton(L("Cancel and notify"), systemImage: "calendar-x-2", variant: .outline, size: .compact, fullWidth: true) { cancelling = visit }
                    }
                    if canMove {
                        PMButton(L("Move to…"), systemImage: "arrow-right-left", variant: .outline, size: .compact, fullWidth: true) { moving = PlacesMoveBatch(visits: [visit]) }
                    }
                }
            }
        }
        .overlay {
            if on { RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.blue, lineWidth: 1) }
        }
    }

    private func load() async {
        guard workspace.current != nil, canSee else { return }
        do {
            let answer: PlacesRelocations = try await API.get("/provider-locations/relocate")
            visits = answer.visits ?? []
            loadError = nil
            selected.formIntersection(Set((answer.visits ?? []).map(\.id)))
        } catch is CancellationError {
        } catch {
            if visits == nil { loadError = errorText(error) } else { Toast.error(error) }
        }
    }
}

// MARK: - Move

/// What stopped one visit from moving.
private struct PlacesMoveRefusal: Identifiable {
    let visit: PlacesRelocationVisit
    let conflicts: [PlacesConflict]?
    let hours: PlacesHoursProblem?
    let message: String?
    var id: String { visit.id }
}

/// Where the visits go: an open location, same time. What the server refuses
/// (a person or room taken, the new place's hours) is listed per visit and
/// moves only on purpose.
private struct PlacesMoveSheet: View {
    let visits: [PlacesRelocationVisit]
    let targets: [ProviderLocation]
    let zoneOf: (String?) -> String?
    let onMoved: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var target: String?
    @State private var refusals: [PlacesMoveRefusal] = []
    @State private var confirmed = false
    @State private var running = false

    private var destination: ProviderLocation? { targets.first { $0.id == target } }
    private var pending: [PlacesRelocationVisit] { refusals.isEmpty ? visits : refusals.map(\.visit) }
    private var overridable: Bool { !refusals.isEmpty && refusals.allSatisfy { $0.conflicts != nil || $0.hours != nil } }
    private var needsConfirm: Bool { refusals.contains { !($0.conflicts ?? []).isEmpty } }

    private var title: String {
        pending.count == 1 ? LF("Move %@ to…", pending.first?.pet ?? "") : LF("Move %d visits to…", pending.count)
    }

    private var primaryTitle: String? {
        if !refusals.isEmpty { return overridable ? L("Move anyway") : nil }
        return destination.map { LF("Move to %@", $0.name) } ?? L("Choose a location")
    }

    var body: some View {
        ProviderModal(
            title: title,
            subtitle: L("Same day and time, at an open location."),
            systemImage: "arrow-right-left",
            accent: .aqua,
            isDirty: target != nil && refusals.isEmpty,
            primaryTitle: primaryTitle,
            isWorking: running,
            primaryIcon: "arrow-right-left",
            onPrimary: primary
        ) {
            if refusals.isEmpty { choices } else { refused }
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 8) {
            if targets.isEmpty {
                Text(L("There is no open location to move them to.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            ForEach(targets) { place in
                let on = place.id == target
                Button { target = place.id } label: {
                    HStack(spacing: 12) {
                        PlacesLocationThumb(photoUrl: place.photoUrl, isPrimary: place.isPrimary, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            HStack(spacing: 4) {
                                Glyph("map-pin", size: 12)
                                Text(place.address?.nonEmpty ?? L("No address yet")).lineLimit(1)
                            }
                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                            if visits.count == 1, let first = visits.first, let there = place.timezone, there != zoneOf(first.locationId) {
                                Text(LF("There: %@", PlacesWhen.text(first.startsAt, zone: there))).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                            }
                        }
                        Spacer(minLength: 0)
                        if on { Glyph("check", size: 20).foregroundStyle(Theme.blue) }
                    }
                    .padding(12)
                    .background(on ? AnyShapeStyle(Theme.wash(Theme.blue, 8)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(on ? Theme.blue : Theme.borderSoft, lineWidth: 2))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(running)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var refused: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(refusals.count == 1 ? LF("This visit couldn’t move to %@:", destination?.name ?? "") : LF("These visits couldn’t move to %@:", destination?.name ?? ""))
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            ForEach(refusals) { refusal in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(refusal.visit.pet) · \(PlacesWhen.text(refusal.visit.startsAt, zone: destination?.timezone ?? zoneOf(refusal.visit.locationId)))")
                        .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    if let hours = refusal.hours {
                        HStack(alignment: .top, spacing: 6) {
                            Glyph("moon-star", size: 16).padding(.top, 1)
                            Text(hours.title(person: refusal.visit.assignedName))
                        }
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    }
                    if let message = refusal.message {
                        Text(message).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.destructive)
                    }
                    if let conflicts = refusal.conflicts, !conflicts.isEmpty {
                        PlacesConflictWarning(conflicts: conflicts, zone: destination?.timezone, confirmed: $confirmed)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            }
            if overridable {
                Text(L("Moved anyway, each visit is marked as double-booked or outside opening hours.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func primary() {
        guard let destination else {
            Toast.error(L("Choose a location"))
            return
        }
        let anyway = !refusals.isEmpty
        if anyway && needsConfirm && !confirmed {
            Toast.error(L("Double booking — read the warning and confirm to book anyway."))
            return
        }
        running = true
        Task {
            defer { running = false }
            var failed: [PlacesMoveRefusal] = []
            var moved: [String] = []
            var elsewhere: [String] = []
            for visit in pending {
                var body: [String: Any?] = ["appointmentId": visit.id, "locationId": destination.id]
                if anyway {
                    body["allowDoubleBooking"] = true
                    body["outsideHours"] = true
                }
                do {
                    let answer: PlacesRelocateAnswer = try await PlacesAPI.post("/provider-locations/relocate", body: body)
                    moved.append(visit.id)
                    if answer.memberWorksThere == false, let person = visit.assignedName?.nonEmpty { elsewhere.append(person) }
                } catch let refusal as PlacesRefusal {
                    let conflicts = refusal.conflicts
                    let hours = refusal.hours
                    failed.append(PlacesMoveRefusal(visit: visit, conflicts: conflicts, hours: hours,
                                                   message: conflicts != nil || hours != nil ? nil : PlacesLocationRules.errorText(refusal.api, name: destination.name)))
                } catch {
                    failed.append(PlacesMoveRefusal(visit: visit, conflicts: nil, hours: nil, message: PlacesLocationRules.errorText(error, name: destination.name)))
                }
            }
            if !moved.isEmpty {
                onMoved(moved)
                announceDataChanged()
                Toast.show(moved.count == 1 ? LF("1 visit moved to %@. The family was told.", destination.name) : LF("%d visits moved to %@. The families were told.", moved.count, destination.name))
            }
            for person in Array(Set(elsewhere)).sorted() {
                Toast.show(LF("%@ doesn’t work at %@. Change who takes it from the Schedule if needed.", person, destination.name))
            }
            if failed.isEmpty {
                dismiss()
                return
            }
            refusals = failed
            confirmed = false
        }
    }
}

// MARK: - Cancel

/// Cancel one visit at a paused location: the usual cancel (no late fee), with a notice to the family.
private struct PlacesCancelRelocationSheet: View {
    let visit: PlacesRelocationVisit
    let when: String
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var working = false

    var body: some View {
        ProviderModal(
            title: LF("Cancel %@’s visit?", visit.pet),
            subtitle: LF("%@ at %@. The family is told the location no longer takes visits. No late-cancellation fee.", when, visit.locationName ?? ""),
            systemImage: "triangle-alert",
            accent: .pink,
            isDirty: !reason.isEmpty,
            primaryTitle: L("Cancel and notify"),
            primaryVariant: .destructive,
            isWorking: working,
            cancelTitle: L("Keep it@location"),
            primaryIcon: "triangle-alert",
            onPrimary: confirm
        ) {
            PMTextField(L("Message to the family"), text: $reason, prompt: L("e.g. We moved to our Polanco location — call us to book again."), optional: true, multiline: true)
        }
        .presentationDetents([.medium, .large])
    }

    private func confirm() {
        working = true
        Task {
            defer { working = false }
            do {
                var body: [String: Any?] = ["appointmentId": visit.id]
                if let text = reason.nonEmpty { body["reason"] = text }
                try await API.send("POST", "/provider-locations/relocate/cancel", body: body)
                Toast.show(LF("%@’s visit was cancelled. The family was told.", visit.pet))
                announceDataChanged()
                onDone()
                dismiss()
            } catch {
                Toast.error(PlacesLocationRules.errorText(error, name: visit.locationName))
            }
        }
    }
}
