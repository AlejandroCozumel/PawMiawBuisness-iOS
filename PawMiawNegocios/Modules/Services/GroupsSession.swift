//
//  GroupsSession.swift
//  PawMiawNegocios
//
//  One group walk or class (web: groups/session-sheet.tsx, session-roster.tsx,
//  session-form-sheet.tsx, group-report-sheet.tsx): who has a place and who
//  waits, the roster run from here (arrival or pickup, "didn't come", the
//  pickup order), adding pets, the waitlist, planning or changing it,
//  cancelling it (each family is told) and every dog's report on one screen.
//

import SwiftUI

// MARK: - The session

/// A group walk or class (web `SessionSheet`, a page here): its facts, who has a
/// place (run from here), adding pets and the waitlist; changing it or cancelling
/// it (each family is told) from its header.
struct SvcSessionScreen: View {
    let sessionId: String

    @EnvironmentObject private var workspace: Workspace
    @State private var session: SvcSessionDetail?
    @State private var failed: String?
    @State private var members: [SvcMember] = []
    @State private var editing = false
    @State private var cancelling = false
    @State private var pushed: SvcSessionRoute?

    var body: some View {
        PageScroll(refresh: { await load() }) {
            if let session {
                header(session)
                SvcSessionFacts(session: session)
                petsCard(session)
                if session.active && !session.started && workspace.can(.appointmentsCreate) {
                    SvcAddPets(session: session) { await load() }
                }
                if let waitlist = session.waitlist, !waitlist.isEmpty {
                    SvcWaitlist(session: session, entries: waitlist, canManage: session.active && workspace.can(.appointmentsCreate)) { await load() }
                }
            } else if failed != nil {
                SvcLoadError(message: L("This session couldn’t be loaded.")) { await load() }
            } else {
                LoadingState()
            }
        }
        .providerPage(session?.serviceLabel ?? L("Group session"))
        .navigationDestination(item: $pushed) { route in
            switch route {
            case .session(let id): SvcSessionScreen(sessionId: id)
            case .provider(let provider): RouteView(route: provider)
            }
        }
        .sheet(isPresented: $editing) {
            if let session { SvcSessionFormSheet(session: session, people: svcSessionLeaders(members, workspace: workspace)) { _ in Task { await load() } } }
        }
        .sheet(isPresented: $cancelling) {
            if let session {
                ConfirmSheet(title: LF("Cancel %@?", session.serviceLabel), message: L("Every pet’s visit is cancelled and each family is told, with the reason."), confirmTitle: L("Cancel the session"), destructive: true, askReason: true, reasonRequired: true, reasonLabel: L("Why is it cancelled?"), cancelTitle: L("Keep it"), confirmIcon: "calendar-x-2") { reason in
                    let result: SvcSessionCancelResult = try await API.post("/provider-sessions/\(session.id)/cancel", body: ["reason": reason ?? ""])
                    let told = result.notifiedFamilies ?? 0
                    Toast.show(told > 0 ? LF("Session cancelled. %d families were told.", told) : L("Session cancelled."))
                    announceDataChanged()
                    await load()
                }
            }
        }
        .reloadsOnScope { await load() }
        .task { members = await svcLoadMembers(workspace) }
    }

    /// The sheet's head as the page's: the session, its day and time, and what can be done to it before it starts.
    private func header(_ session: SvcSessionDetail) -> some View {
        ModuleHeader(icon: "users-round", title: session.serviceLabel,
                     subtitle: "\(DateText.dayTime(session.startsAt)) – \(DateText.time(session.endsAt))",
                     accent: Theme.aqua, storageKey: "group-session") {
            if session.active && !session.started {
                if workspace.can(.appointmentsEdit) {
                    PMButton(L("Edit"), systemImage: "pencil", variant: .outline) { editing = true }
                }
                if workspace.can(.appointmentsCancel) {
                    PMButton(L("Cancel the session"), systemImage: "calendar-x-2", variant: .destructive) { cancelling = true }
                }
            }
        }
    }

    /// "Pets · 3/6": the roster, and the session's next move under it.
    private func petsCard(_ session: SvcSessionDetail) -> some View {
        SectionCard(L("Pets") + " · " + session.placesText,
                    subtitle: session.active && session.booked > 0 && !session.started ? (session.isPickup ? L("Mark each dog as picked up; the walk starts with them.") : L("Mark who arrived; the session starts with them.")) : nil,
                    icon: "users-round", accent: Theme.aqua) {
            if session.pets.isEmpty {
                EmptyState(systemImage: "users-round", title: L("No pets yet."), accent: Theme.blue)
            } else {
                SvcSessionRoster(session: session, boxed: false, push: { pushed = $0 }) { await load() }
            }
            if session.active && workspace.can(.appointmentsComplete) && (session.withThem + session.doneCount + session.arrived + session.booked) > 0 {
                RowDivider()
                SvcSessionMoveButtons(session: session, canRun: true) { await load() }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(12)
            }
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

/// The session at a glance (web `SessionFacts`): who is in it and how many places
/// are left, then who leads it, where, the price, whether families book it online.
private struct SvcSessionFacts: View {
    let session: SvcSessionDetail
    @EnvironmentObject private var workspace: Workspace

    var body: some View {
        Card(padding: 16) {
            HStack(spacing: 12) {
                if session.staying.isEmpty {
                    Glyph("users-round", size: 20).foregroundStyle(Theme.inkSoft).frame(width: 40, height: 40).background(Theme.surfaceMuted, in: Circle())
                } else {
                    PetStack(pets: session.staying.map { ($0.name, $0.species, $0.photoUrl) }, size: 40, max: 3)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.placesText).font(.brandHeading(24)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    Eyebrow(placesLeftText, size: 12)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wash(Theme.aqua, 16), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            FlowLayout(spacing: 6) {
                if let leader = session.assignedMember?.name { fact(leader, icon: "user-round") }
                if let room = session.room { fact(room, icon: "door-open") }
                if session.isPickup { fact(L("Picked up at home"), icon: "house") }
                else if let point = session.meetingPoint?.nonEmpty { fact(point, icon: "map-pin") }
                if let price = session.priceAmount { fact(LF("%@ per pet", Money.format(price, currency: workspace.currency))) }
                // "Online" only when families really can: the session's switch and its location's online booking.
                if session.onlineBookingOpen ?? session.onlineBooking ?? false {
                    Chip(text: L("Online"), tone: .custom(Theme.lime), percent: 30, size: .medium)
                } else {
                    fact(L("Only here"))
                }
                if let waiting = session.waitlistCount, waiting > 0 {
                    Chip(text: LF("%d waiting", waiting), tone: .custom(Theme.mango), icon: "hourglass", percent: 25, size: .medium)
                }
                if !session.active {
                    Chip(text: L("Session · Cancelled") + (session.cancelReason.map { " · \($0)" } ?? ""), tone: .custom(Theme.destructive), percent: 12, ink: Theme.destructive, size: .medium)
                }
            }
            if let notes = session.notes?.nonEmpty { Text(notes).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
        }
    }

    private func fact(_ text: String, icon: String? = nil) -> some View {
        Chip(text: text, tone: .custom(Theme.surfaceMuted), icon: icon, percent: 100, ink: Theme.inkSoft, size: .medium)
    }

    private var placesLeftText: String {
        guard session.capacity != nil else { return LP(session.size, "1 pet", "%d pets") }
        let left = session.placesLeft ?? 0
        if left <= 0 { return L("Full") }
        return left == 1 ? L("1 place left") : LF("%d places left", left)
    }
}

// MARK: - The roster

/// Who has a place, run from here (web `SessionRoster`): arrival (or the pickup, with
/// "on my way" and the address), the ones who didn't come, the pickup order and each
/// pet's report. The name opens its visit. `boxed`: its own bordered box (a card's body).
struct SvcSessionRoster: View {
    let session: SvcSessionDetail
    var boxed: Bool = true
    let push: (SvcSessionRoute) -> Void
    let reload: () async -> Void

    @EnvironmentObject private var workspace: Workspace
    @State private var missed: SvcMissedTarget?
    @State private var onMyWay: SvcOnMyWayTarget?
    @State private var working: String?

    init(session: SvcSessionDetail, boxed: Bool = true, push: @escaping (SvcSessionRoute) -> Void, reload: @escaping () async -> Void) {
        self.session = session
        self.boxed = boxed
        self.push = push
        self.reload = reload
    }

    private var rows: [SvcSessionPet] { session.rosterRows }
    private var stops: [SvcSessionPet] { rows.filter { !$0.gone } }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                if row.id != rows.first?.id { RowDivider() }
                rowView(row)
            }
        }
        .background {
            if boxed { RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).fill(Theme.surface) }
        }
        .overlay {
            if boxed { RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1) }
        }
        .sheet(item: $missed) { target in
            SchedMissedSheet(appointmentId: target.id, petName: target.petName, clientName: target.clientName, subtitle: target.subtitle, mode: target.mode,
                             cancelledText: L("Taken out. The place is open.")) { Task { await reload() } }
        }
        .sheet(item: $onMyWay) { target in SvcOnMyWaySheet(target: target) { Task { await reload() } } }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "checked_in": session.isPickup ? L("Picked up") : L("Roster · Here")
        case "in_progress": session.isPickup ? L("On the walk") : L("In class")
        case "completed": L("Roster · Done")
        case "no_show": L("Didn’t come")
        case "cancelled", "canceled": L("Session · Cancelled")
        default: L("Roster · Booked")
        }
    }

    private func rowView(_ row: SvcSessionPet) -> some View {
        let entry = session.entry(row.appointmentId)
        let stop = session.isPickup && !row.gone ? (stops.firstIndex { $0.id == row.id }.map { $0 + 1 }) : nil
        let withThem = row.status == "in_progress" || row.status == "completed"
        let gaps = entry?.reportMissing ?? []
        let canCheckIn = session.active && workspace.can(.appointmentsCheckIn) && row.status == "scheduled"
        let started = (DateText.parse(session.startsAt) ?? .distantFuture) <= Date()
        let canMenu = session.active && !row.gone && (workspace.can(.appointmentsCancel) || (session.isPickup && workspace.can(.appointmentsEdit))) && (row.status == "scheduled" || row.status == "checked_in")
        return HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                PetAvatar(name: row.name, species: row.species, photoURL: row.photoUrl, size: 40)
                if let stop {
                    Text("\(stop)").font(.brandText(10.4, weight: .heavy)).monospacedDigit().foregroundStyle(.white)
                        .frame(width: 20, height: 20).background(Theme.blueFixed, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                        .offset(x: 4, y: 4)
                        .accessibilityLabel(LF("Stop %d", stop))
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                FlowLayout(spacing: 8) {
                    Button { push(.provider(.appointment(row.appointmentId))) } label: {
                        Text(row.name).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).strikethrough(row.gone)
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 6) {
                        Circle().fill(ProviderState.appointment(row.status).color).frame(width: 8, height: 8)
                        Text(statusLabel(row.status) + (row.status == "checked_in" ? (entry?.arrivedAt.map { " · " + DateText.time($0) } ?? "") : ""))
                    }
                    .font(.brandText(11.2, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.surfaceMuted, in: Capsule())
                }
                Text(row.clientName).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                let allergies = entry?.allergies ?? []
                if !allergies.isEmpty || withThem || (entry?.onMyWayAt != nil && row.status == "scheduled") {
                    FlowLayout(spacing: 6) {
                        if !allergies.isEmpty {
                            Chip(text: LF("Allergy: %@", allergies.joined(separator: ", ")), tone: .danger, icon: "triangle-alert")
                        }
                        if withThem {
                            if gaps.isEmpty { Chip(text: L("Report done"), tone: .good, icon: "clipboard-check") }
                            else { Chip(text: LF("Report: %@", SvcReportText.fieldsText(gaps)), tone: .warn, icon: "clipboard-list") }
                        }
                        if let onMyWayAt = entry?.onMyWayAt, row.status == "scheduled" {
                            Chip(text: LF("On the way since %@", DateText.time(onMyWayAt)), tone: .muted, icon: "navigation")
                        }
                    }
                    .padding(.top, 6)
                }
                if session.isPickup && !row.gone {
                    if let address = entry?.address?.nonEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Glyph("map-pin", size: 14).foregroundStyle(Theme.blue).padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(address).foregroundStyle(Theme.inkStrong)
                                if let access = entry?.accessNotes?.nonEmpty {
                                    HStack(spacing: 4) {
                                        Glyph("key-round", size: 12)
                                        Text(access)
                                    }
                                    .foregroundStyle(Theme.inkSoft)
                                }
                            }
                        }
                        .font(Theme.text(12))
                        .padding(.top, 6)
                    } else {
                        FlowLayout(spacing: 6) {
                            Glyph("map-pin", size: 14).foregroundStyle(Theme.mango)
                            Text(L("No address to pick up from.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                            Button { push(.provider(.client(row.providerClientId))) } label: {
                                Text(L("Add it in the client")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 6)
                    }
                }
                if canCheckIn {
                    FlowLayout(spacing: 6) {
                        if session.isPickup, entry?.address?.nonEmpty != nil, entry?.onMyWayAt == nil {
                            PMButton(L("On my way"), systemImage: "navigation", variant: .outline, size: .compact) {
                                let client = SvcClientRef(id: row.providerClientId, name: row.clientName, firstName: NameText.firstName(row.clientName), phone: entry?.clientPhone, onPawMiaw: entry?.familyOnApp)
                                onMyWay = SvcOnMyWayTarget(id: row.appointmentId, appointmentId: row.appointmentId, client: client, petNames: row.name)
                            }
                        }
                        PMButton(session.isPickup ? L("Picked up") : L("Arrived"), systemImage: session.isPickup ? "badge-check" : "door-open", size: .compact, isWorking: working == row.id) { arrived(row) }
                            .disabled(working != nil)
                        if started {
                            PMButton(L("Didn’t come"), systemImage: "circle-slash", variant: .outline, size: .compact) {
                                missed = SvcMissedTarget(id: row.appointmentId, petName: row.name, clientName: row.clientName, subtitle: "\(session.serviceLabel) · \(row.clientName)", mode: "no_show")
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if canMenu {
                Menu {
                    if session.isPickup && workspace.can(.appointmentsEdit), let stop {
                        if stop > 1 { Button { move(row, by: -1) } label: { GlyphLabel(L("Pick up earlier"), icon: "arrow-up") } }
                        if stop < stops.count { Button { move(row, by: 1) } label: { GlyphLabel(L("Pick up later"), icon: "arrow-down") } }
                    }
                    if workspace.can(.appointmentsCancel) {
                        Button(role: .destructive) {
                            missed = SvcMissedTarget(id: row.appointmentId, petName: row.name, clientName: row.clientName, subtitle: LF("Take %@ out of %@?", row.name, session.serviceLabel), mode: "cancel")
                        } label: { GlyphLabel(L("Take the pet out"), icon: "x") }
                    }
                } label: {
                    IconCircleLabel(size: 32, bordered: false)
                }
                .accessibilityLabel(LF("More for %@", row.name))
            }
        }
        .padding(12)
        .opacity(row.gone ? 0.6 : 1)
    }

    private func arrived(_ row: SvcSessionPet) {
        working = row.id
        let underWay = rows.contains { $0.status == "in_progress" }
        Task {
            defer { working = nil }
            do {
                let _: SvcIgnored = try await API.post("/provider-appointments/\(row.appointmentId)/check-in", body: [:])
                // Late, once the others started: they join the walk or the class right away.
                if underWay && workspace.can(.appointmentsComplete) {
                    let _: SvcIgnored = try await API.post("/provider-sessions/\(session.id)/start", body: [:])
                    Toast.show(session.isPickup ? LF("%@ picked up and on the walk.", row.name) : LF("%@ is here and in the class.", row.name))
                } else {
                    Toast.show(session.isPickup ? LF("%@ picked up.", row.name) : LF("%@ is here.", row.name))
                }
                announceDataChanged()
                await reload()
            } catch {
                Toast.error(error)
            }
        }
    }

    private func move(_ row: SvcSessionPet, by step: Int) {
        var order = stops.map(\.appointmentId)
        guard let at = order.firstIndex(of: row.appointmentId), order.indices.contains(at + step) else { return }
        order.swapAt(at, at + step)
        Task {
            do {
                let _: SvcIgnored = try await API.post("/provider-sessions/\(session.id)/pickups", body: ["order": order])
                await reload()
            } catch {
                Toast.error(error)
            }
        }
    }
}

// MARK: - Add pets

/// Give a client's pets a place (web `AddPets`): find the client, tick the pets — with the one
/// client-and-pet picker (server search from 2 letters, 20 at a time). Full → add anyway, or the waitlist.
private struct SvcAddPets: View {
    let session: SvcSessionDetail
    let reload: () async -> Void

    @State private var client: PickedClient?
    @State private var picked: [String] = []
    @State private var full: Int?
    @State private var working = false

    private var dogsOnly: Bool { session.serviceCategory == "walker" || session.serviceCategory == "trainer" }

    var body: some View {
        SectionCard(L("Add pets"), icon: "plus", accent: Theme.aqua) {
            VStack(alignment: .leading, spacing: 12) {
                ClientPetPicker(client: Binding(get: { client }, set: { client = $0; full = nil }),
                                petIds: Binding(get: { picked }, set: { picked = $0; full = nil }),
                                pets: .several, label: L("Find a client"), petNote: note)
                if let client, !(client.activePets.isEmpty) { actions }
            }
            .padding(16)
        }
    }

    /// Why a pet can't be given a place, or that it waits already (web: the check, the hourglass).
    private func note(_ pet: PickedPet) -> (text: String, disabled: Bool)? {
        if session.staying.contains(where: { $0.providerClientPetId == pet.id }) { return (L("Already in this session"), true) }
        if dogsOnly && pet.petSpecies?.trimmingCharacters(in: .whitespaces).lowercased() != "dog" { return (L("Group walks and classes are for dogs."), true) }
        if (session.waitlist ?? []).contains(where: { $0.providerClientPetId == pet.id }) { return (L("On the waitlist"), false) }
        return nil
    }

    @ViewBuilder private var actions: some View {
        if let full {
            VStack(alignment: .leading, spacing: 8) {
                Text(full > 0 ? LF("Only %d places left.", full) : LF("%@ is full — add them anyway, or put them on the waitlist.", session.serviceLabel))
                    .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                FlowLayout(spacing: 8) {
                    PMButton(L("Put on the waitlist"), systemImage: "list-plus", variant: .outline, size: .compact, isWorking: working) { Task { await waitlist() } }
                    PMButton(L("Add anyway"), systemImage: "plus", size: .compact, isWorking: working) { Task { await give(allowOver: true) } }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wash(Theme.mango, 18), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        } else {
            HStack {
                Spacer(minLength: 0)
                PMButton(L("Give them a place"), systemImage: "plus", size: .compact, isWorking: working) { Task { await give(allowOver: false) } }
                    .disabled(picked.isEmpty)
            }
        }
    }

    private func reset() {
        client = nil
        picked = []
        full = nil
    }

    private func give(allowOver: Bool) async {
        guard let client, !picked.isEmpty else { return }
        working = true
        defer { working = false }
        do {
            var body: [String: Any?] = ["providerClientId": client.id, "providerClientPetIds": picked]
            if allowOver { body["allowOverCapacity"] = true }
            let _: SvcIgnored = try await SvcAPI.send("POST", "/provider-sessions/\(session.id)/pets", body: body)
            Toast.show(LF("Added to %@.", session.serviceLabel))
            reset()
            announceDataChanged()
            await reload()
        } catch {
            if svcCode(error) == "session_full" {
                full = (error as? SvcRefusal)?.body?["placesLeft"]?.int ?? 0
                return
            }
            Toast.error(svcMessage(error))
        }
    }

    private func waitlist() async {
        guard let client else { return }
        working = true
        defer { working = false }
        do {
            for pet in picked {
                let _: SvcIgnored = try await API.post("/provider-sessions/\(session.id)/waitlist", body: ["providerClientId": client.id, "providerClientPetId": pet])
            }
            // Only a family on the app with online booking gets told; the rest are called.
            Toast.show(client.householdId != nil && (session.onlineBookingOpen ?? session.onlineBooking ?? false) ? L("On the waitlist. They are told when a place opens.") : L("On the waitlist. Call them when a place opens."))
            reset()
            announceDataChanged()
            await reload()
        } catch {
            Toast.error(error)
        }
    }
}

// MARK: - Waitlist

/// Who waits for a place (web `Waitlist`): give it, or take them off the list.
private struct SvcWaitlist: View {
    let session: SvcSessionDetail
    let entries: [SvcWaitEntry]
    let canManage: Bool
    let reload: () async -> Void
    @State private var working: String?

    var body: some View {
        SectionCard(L("Waitlist") + " · \(entries.count)", icon: "hourglass", accent: Theme.mango) {
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    if entry.id != entries.first?.id { RowDivider() }
                    FlowLayout(spacing: 12) {
                        HStack(spacing: 12) {
                            PetAvatar(name: entry.petName, photoURL: entry.petPhotoUrl, size: 32)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(entry.petName).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                HStack(spacing: 4) {
                                    Glyph("clock-3", size: 12)
                                    Text((entry.status == "notified" ? L("Told a place opened") : (session.placesLeft ?? 0) > 0 ? L("A place is free: give it, or call the family") : LF("Waiting since %@", DateText.dayTime(entry.createdAt))) + " · " + entry.clientName)
                                        .lineLimit(2)
                                }
                                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                            }
                        }
                        if canManage {
                            HStack(spacing: 6) {
                                PMButton(L("Take off the list"), variant: .outline, size: .compact) { Task { await act(entry, give: false) } }
                                    .disabled(working != nil)
                                PMButton(L("Give the place"), size: .compact, isWorking: working == entry.id) { Task { await act(entry, give: true) } }
                                    .disabled(session.full == true)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func act(_ entry: SvcWaitEntry, give: Bool) async {
        working = entry.id
        defer { working = nil }
        do {
            if give {
                let _: SvcIgnored = try await API.post("/provider-sessions/\(session.id)/pets", body: ["providerClientId": entry.providerClientId, "providerClientPetIds": [entry.providerClientPetId]])
                Toast.show(LF("Added to %@.", session.serviceLabel))
            } else {
                let _: SvcIgnored = try await API.delete("/provider-sessions/\(session.id)/waitlist/\(entry.id)")
            }
            announceDataChanged()
            await reload()
        } catch {
            Toast.error(error)
        }
    }
}

// MARK: - Plan or change a session

/// Its time, who leads it, the room, how many places, the price per pet, and whether families book a
/// place from the app (web `SessionFormSheet`). A clash or the hours are said and saved only on purpose.
struct SvcSessionFormSheet: View {
    let session: SvcSessionDetail?
    let people: [SvcMember]
    let onSaved: (String) -> Void

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var category = "walker"
    /// The catalog service it charges (a group walk or class, another of the business's, or "another" named by hand).
    @State private var serviceId = "group_walk"
    @State private var catalog: [SvcCatalogService] = []
    @State private var everyService: [SvcCatalogService] = []
    @State private var priced: [SvcPricedService] = []
    /// Whether this location takes online bookings (nil: not known).
    @State private var onlineOpen: Bool?
    @State private var label = ""
    @State private var startMode = "meeting_point"
    @State private var meetingPoint = ""
    @State private var date = Date()
    @State private var start = Date()
    @State private var length = 60
    @State private var memberId = ""
    @State private var roomId = ""
    @State private var rooms: [SvcRoom] = []
    @State private var capacity = "6"
    @State private var price: Int?
    @State private var online = true
    @State private var notes = ""
    @State private var clash: String?
    @State private var clashOk = false
    @State private var hours: String?
    @State private var hoursOk = false
    @State private var working = false
    @State private var ready = false
    @State private var loadedPeople: [SvcMember] = []
    @StateObject private var form = FormState()

    private static let lengths = [30, 45, 60, 90, 120, 180]
    /// One family's services — a drop-in at home, an assessment, a consult — aren't run as a group.
    private static let notGrouped: Set<String> = ["walker_drop_in", "training_assessment", "behavior_consult"]

    /// The leaders given, else the ones loaded here (the page's list may still be on its way).
    private var leaders: [SvcMember] { people.isEmpty ? loadedPeople : people }

    private var leadService: String { category == "trainer" ? "group_class" : "group_walk" }
    private var otherService: String { category == "trainer" ? "training_other" : "walk_other" }

    /// The services of this kind: the group walk or class first, the business's own, "another" last —
    /// the group service and "another" stay on offer even if the business never picked them.
    private var services: [SvcCatalogService] {
        let own = catalog.filter { $0.category == category && !Self.notGrouped.contains($0.id) }
        let always = [leadService, otherService].filter { id in !own.contains { $0.id == id } }.compactMap { id in everyService.first { $0.id == id } }
        func rank(_ id: String) -> Int { id == leadService ? 0 : id == otherService ? 2 : 1 }
        return Array((own + always).enumerated()).sorted { (rank($0.element.id), $0.offset) < (rank($1.element.id), $1.offset) }.map(\.element)
    }

    /// As the bill prices it: the service's Catalog price, else a Catalog service with the session's or the service's name.
    private func priceOf(_ service: SvcCatalogService?, name: String) -> Int? {
        if let billing = service?.defaultBillingItem, billing.active == true { return billing.defaultUnitAmount ?? 0 }
        let names = [name, service?.label ?? ""].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        for entry in names {
            if let item = priced.first(where: { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == entry }) { return item.defaultUnitAmount ?? 0 }
        }
        return nil
    }

    private var catalogAmount: Int? { priceOf(services.first { $0.id == serviceId }, name: label) }

    var body: some View {
        ProviderModal(title: session?.serviceLabel ?? L("New group session"),
                      subtitle: session.map { DateText.dayTime($0.startsAt) } ?? L("A group walk or class at one time, with places that pets of different families take."),
                      systemImage: "users-round", accent: .aqua, isDirty: ready, form: form,
                      primaryTitle: clash != nil && clashOk ? L("Plan it anyway") : (session == nil ? L("Plan the session") : L("Save changes")),
                      isWorking: working, cancelTitle: L("Back"), primaryIcon: "calendar-plus", onPrimary: submit) {
            ModalSection(title: L("What it is"), required: true) {
                FlowLayout(spacing: 8) {
                    SvcChoiceChip(title: L("A walk"), isSelected: category == "walker", wash: true, height: 36) { choose("walker") }
                    SvcChoiceChip(title: L("A class"), isSelected: category == "trainer", wash: true, height: 36) { choose("trainer") }
                }
                if !services.isEmpty {
                    // Web OptionCardGrid: each service a card, a dog for a walk, a cap for a class.
                    FormField(label: L("Service it charges"), required: true) {
                        OptionCards(options: serviceOptions, selection: Binding(get: { serviceId }, set: { chooseService($0) }))
                    }
                }
                PMTextField(L("Name families see"), text: $label, key: "label", form: form, prompt: category == "trainer" ? L("Puppy class, agility…") : L("Beach walk, hike…"), required: true)
            }
            ModalSection(title: L("How it starts"), required: true) {
                ChoiceCards(options: startOptions, selection: $startMode)
                if startMode == "meeting_point" || category != "walker" {
                    TextField(L("Parque México, north gate"), text: $meetingPoint).fieldChrome()
                        .accessibilityLabel(L("Meeting point"))
                } else {
                    Text(L("Each dog is picked up at its client’s address; a client with none is marked so you can add it.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            ModalSection(title: L("When")) {
                DateTimeField(label: L("Date"), date: $date, components: [.date], required: true)
                DateTimeField(label: L("Starts"), date: $start, components: [.hourAndMinute], key: "start", form: form, required: true)
                MenuField(label: L("Length"), options: lengthOptions, selection: $length, required: true)
            }
            // Web: each its own section, the select under the section's title.
            ModalSection(title: L("Who leads it"), required: true) {
                StaysPlainMenu(options: leaderOptions, selection: $memberId, accessibility: L("Who leads it"), key: "member", form: form)
            }
            ModalSection(title: L("Room or place")) {
                StaysPlainMenu(options: roomOptions, selection: $roomId, accessibility: L("Room or place"))
            }
            ModalSection(title: L("Places"), subtitle: L("How many pets it takes"), required: true) {
                StaysPlainField(prompt: "6", text: Binding(get: { capacity }, set: { capacity = String($0.filter(\.isNumber).prefix(3)) }), key: "capacity", form: form, keyboard: .numberPad)
                    .frame(width: 112)
                    .accessibilityLabel(L("Places"))
            }
            ModalSection(title: L("Price per pet"),
                         subtitle: catalogAmount.map { LF("Empty: %@, the service’s price in the Catalog.", Money.format($0, currency: workspace.currency)) } ?? L("This service has no price in the Catalog: set one here, or it is charged at 0.")) {
                StaysPlainMoney(cents: $price, prompt: "0.00", currency: workspace.currency, key: "price", form: form)
                    .frame(maxWidth: 220)
                    .accessibilityLabel(L("Price per pet"))
            }
            VStack(alignment: .leading, spacing: 6) {
                ToggleRow(title: L("Families book a place from the app"), subtitle: L("Families linked to you see it and take a place until it’s full."), isOn: $online)
                if online && onlineOpen == false {
                    Text(L("This location doesn’t take online bookings yet: families see it once it is on in Availability.")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                }
            }
            ModalSection(title: L("Notes")) {
                StaysPlainField(prompt: "", text: $notes, multiline: true, lines: 2...6)
                    .accessibilityLabel(L("Notes"))
            }
            if let hours {
                VStack(alignment: .leading, spacing: 8) {
                    NoticeCard(tone: .warning, title: hours)
                    ToggleRow(title: L("Plan it anyway"), isOn: $hoursOk)
                }
                .id("hours")
            }
            if let clash {
                VStack(alignment: .leading, spacing: 8) {
                    NoticeCard(tone: .warning, title: L("Double booking"), message: clash)
                    ToggleRow(title: L("Book it anyway — I know they overlap"), isOn: $clashOk)
                }
                .id("clash")
            }
        }
        .task { await setUp() }
    }

    /// A walk or a class: the group service of that kind, its name when it wasn't named by hand, an hour long.
    private func choose(_ value: String) {
        let wasDefault = label.isEmpty || services.contains { $0.label == label } || label == L("Group walk") || label == L("Group class")
        category = value
        serviceId = value == "trainer" ? "group_class" : "group_walk"
        if value != "walker" { startMode = "meeting_point" }
        if wasDefault { label = value == "trainer" ? L("Group class") : L("Group walk") }
        length = 60
    }

    private var serviceOptions: [OptionCard<String>] {
        services.map { service in
            let other = service.id == otherService
            // "Another" is priced by the name typed for it, once it is the one chosen.
            let amount = priceOf(service, name: other ? (serviceId == service.id ? label : "") : service.label)
            let title: String = other ? (category == "trainer" ? L("Another class") : L("Another walk")) : service.label
            let first: String = other ? L("You name it") : LF("%d min", service.minutes ?? 60)
            let second: String = amount.map { LF("%@ per pet", Money.format($0, currency: workspace.currency)) } ?? L("No price in the Catalog")
            return OptionCard(service.id, title: title, description: first + " · " + second,
                              icon: category == "trainer" ? "graduation-cap" : "dog",
                              accent: category == "trainer" ? Theme.lavender : Theme.aqua)
        }
    }

    /// Choosing a service names the session after it (unless it was named by hand) and sets its usual length.
    private func chooseService(_ id: String) {
        let next = services.first { $0.id == id }
        let named = label.trimmingCharacters(in: .whitespaces).isEmpty || services.contains { $0.label == label } || label == L("Group walk") || label == L("Group class")
        serviceId = id
        // "Another" is named by hand: its name field starts empty, the length stays.
        if id == otherService {
            if named { label = "" }
            return
        }
        if let next, named { label = next.label }
        if let minutes = next?.minutes, minutes >= 15 { length = minutes }
    }

    private var lengthOptions: [(value: Int, title: String)] {
        let list = Self.lengths.contains(length) ? Self.lengths : (Self.lengths + [length]).sorted()
        return list.map { minutes -> (value: Int, title: String) in (minutes, LF("%d min", minutes)) }
    }

    private var leaderOptions: [(value: String, title: String)] {
        leaders.map { member -> (value: String, title: String) in (member.id, member.shownName) }
    }

    private var roomOptions: [(value: String, title: String)] {
        let usable = rooms.filter { ($0.status ?? "active") == "active" || $0.id == roomId }
        return [("", L("No room"))] + usable.map { room -> (value: String, title: String) in (room.id, room.name) }
    }

    private var startOptions: [(value: String, title: String, subtitle: String?)] {
        var out: [(value: String, title: String, subtitle: String?)] = [("meeting_point", L("At a meeting point"), L("Families bring their dogs to the place and time."))]
        if category == "walker" { out.append(("pickup", L("Picked up at home"), L("The walker collects each dog at its address, in an order you set."))) }
        return out
    }

    private func setUp() async {
        guard !ready else { return }
        let calendar = DateText.calendar
        if let session {
            category = session.serviceCategory ?? "walker"
            serviceId = session.serviceId ?? ""
            label = session.serviceLabel
            startMode = session.startMode ?? "meeting_point"
            meetingPoint = session.meetingPoint ?? ""
            let startDate = DateText.parse(session.startsAt) ?? Date()
            date = startDate
            start = startDate
            length = max(15, SvcTime.minutesBetween(session.startsAt, session.endsAt))
            memberId = session.assignedMember?.id ?? ""
            roomId = session.roomId ?? ""
            capacity = String(session.capacity ?? 1)
            price = session.priceAmount
            online = session.onlineBooking ?? true
            notes = session.notes ?? ""
        } else {
            label = L("Group walk")
            let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
            start = nine
            if people.isEmpty { loadedPeople = svcSessionLeaders(await svcLoadMembers(workspace), workspace: workspace) }
            memberId = leaders.first { $0.isCurrentMember == true && !workspace.can(.appointmentsAssignAnyone) }?.id ?? leaders.first?.id ?? ""
        }
        let loaded: [SvcRoom] = (try? await API.get("/provider-rooms", query: ["locationId": session?.locationId ?? workspace.locationId])) ?? []
        rooms = loaded.filter { $0.kind != "ward" && $0.kind != "cage" }
        ready = true
        // Every service there is (a group walk or class stays on offer even if the business never picked it),
        // the Catalog's priced services, and whether this location takes online bookings.
        catalog = await SvcServices.load("provider")
        everyService = await SvcServices.load("all")
        let page: Page<SvcPricedService>? = try? await API.get("/provider-catalog", query: ["limit": "100", "offset": "0", "itemType": "service", "active": "true"])
        priced = page?.items ?? []
        onlineOpen = await svcLocationTakesOnlineBookings(session?.locationId ?? workspace.locationId)
    }

    /// The day from the date picker and the clock from the time picker, on the business's calendar.
    private func startsAt() -> Date? {
        let calendar = DateText.calendar
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let time = calendar.dateComponents([.hour, .minute], from: start)
        var parts = DateComponents()
        parts.year = day.year; parts.month = day.month; parts.day = day.day; parts.hour = time.hour; parts.minute = time.minute
        return calendar.date(from: parts)
    }

    private func submit() {
        let places = Int(capacity.trimmingCharacters(in: .whitespaces))
        guard form.check([
            ("label", label.nonEmpty == nil ? L("Name the session first.") : nil),
            ("start", startsAt() == nil ? L("Choose a date and time.") : nil),
            ("member", memberId.isEmpty ? L("Choose a person") : nil),
            ("capacity", (places ?? 0) < 1 ? L("Choose how many places it has.") : nil),
            // A clash or the hours are saved only once confirmed: said, and scrolled to.
            ("hours", hours != nil && !hoursOk ? L("Confirm below to plan it anyway, or change the time.") : nil),
            ("clash", clash != nil && !clashOk ? L("Confirm below to plan it anyway, or change the time.") : nil),
        ]) else { return }
        guard let begins = startsAt() else { return }
        working = true
        let isPickup = startMode == "pickup" && category == "walker"
        var body: [String: Any?] = [
            "serviceCategory": category,
            "serviceLabel": label.nonEmpty,
            "startMode": isPickup ? "pickup" : "meeting_point",
            "meetingPoint": isPickup ? nil : meetingPoint.nonEmpty,
            "startsAt": DateText.iso(begins),
            "endsAt": DateText.iso(begins.addingTimeInterval(Double(length) * 60)),
            "assignedOrganizationMemberId": memberId.isEmpty ? nil : memberId,
            "roomId": roomId.isEmpty ? nil : roomId,
            "capacity": places,
            "priceAmount": price,
            "onlineBooking": online,
            "notes": notes.nonEmpty,
        ]
        if let chosen = serviceId.nonEmpty { body["serviceId"] = chosen }
        if clash != nil && clashOk { body["allowDoubleBooking"] = true }
        if hours != nil && hoursOk { body["outsideHours"] = true }
        if session == nil, let location = workspace.locationId { body["locationId"] = location }
        Task {
            defer { working = false }
            do {
                let saved: SvcSessionDetail = try await SvcAPI.send(session == nil ? "POST" : "PATCH", session.map { "/provider-sessions/\($0.id)" } ?? "/provider-sessions", body: body)
                Toast.show(session == nil ? L("Session planned.") : L("Session saved."))
                announceDataChanged()
                dismiss()
                onSaved(saved.id)
            } catch {
                switch svcCode(error) {
                case "start_in_past":
                    form.errors = ["start": (error as? SvcRefusal)?.api.field("startsAt") ?? svcMessage(error)]
                    form.scrollTarget = "start"
                    Toast.error(svcMessage(error))
                case "visit_conflict":
                    clash = svcMessage(error)
                    clashOk = false
                case "outside_hours":
                    hours = svcMessage(error)
                    hoursOk = false
                default:
                    form.apply(svcAPIError(error), known: ["serviceLabel": "label", "startsAt": "start", "capacity": "capacity", "priceAmount": "price", "assignedOrganizationMemberId": "member"])
                }
            }
        }
    }
}

// MARK: - Every dog's report on one screen

/// Every dog's report on one screen (web `GroupReportSheet`): what was the same for
/// the whole group set once for everyone, then each dog's own. Each report is still
/// the pet's own and reaches its family on its visit.
struct SvcGroupReportSheet: View {
    let session: SvcSessionDetail
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [String: SvcReport] = [:]
    @State private var originals: [String: SvcReport] = [:]
    @State private var skillsForAll = ""
    @State private var homeworkForAll = ""
    @State private var groupPhoto: String?
    @State private var saving = false
    @State private var full: SvcReportTarget?

    private var kind: String? { SvcReportText.kind(for: session.serviceCategory) }
    private var pets: [SvcSessionPet] { session.rosterRows.filter { $0.status == "in_progress" || $0.status == "completed" } }

    var body: some View {
        ProviderModal(title: L("Group report"), subtitle: "\(session.serviceLabel) · " + LP(pets.count, "1 pet", "%d pets"), systemImage: "clipboard-check", accent: .aqua,
                      isDirty: drafts != originals, primaryTitle: L("Save the reports"), isWorking: saving, cancelTitle: L("Back"),
                      primaryIcon: "clipboard-check", primaryDisabled: pets.isEmpty, onPrimary: save) {
            if pets.isEmpty || kind == nil || kind == "groom" {
                Text(L("Reports open once the session starts.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            } else {
                ModalSection(title: L("For everyone"), subtitle: L("Fills every dog’s report; change any dog below.")) {
                    MenuField(label: L("Behaviour"), options: [("", L("Choose for everyone"))] + SvcReportText.behaviours.map { ($0, SvcReportText.option($0)) },
                              selection: Binding(get: { "" }, set: { value in if !value.isEmpty { forAll { $0.behaviour = value } } }))
                    if kind == "walk" {
                        PMButton(L("Everyone peed"), variant: .outline, fullWidth: true) { forAll { $0.pee = true } }
                    } else {
                        MenuField(label: L("Progress"), options: [("", L("Choose for everyone"))] + SvcReportText.progress.map { ($0, SvcReportText.option($0)) },
                                  selection: Binding(get: { "" }, set: { value in if !value.isEmpty { forAll { $0.progress = value } } }))
                        FormField(label: L("Skills practised (comma between them)")) {
                            HStack(spacing: 8) {
                                TextField(L("Sit, stay, recall"), text: $skillsForAll).fieldChrome()
                                PMButton(L("Add to all"), variant: .outline) {
                                    let skills = svcSplitSkills(skillsForAll)
                                    forAll { report in for skill in skills where !report.skills.contains(skill) { report.skills.append(skill) } }
                                    skillsForAll = ""
                                }
                                .disabled(skillsForAll.nonEmpty == nil)
                            }
                        }
                        // Every dog's homework follows what is typed here.
                        PMTextField(L("Homework"), text: Binding(get: { homeworkForAll }, set: { value in homeworkForAll = value; forAll { $0.homework = value.nonEmpty } }), prompt: L("The same for everyone"))
                    }
                    if let first = pets.first {
                        VStack(alignment: .leading, spacing: 4) {
                            SvcPhotoSlot(label: L("Group photo"), url: groupPhoto, disabled: false, appointmentId: first.appointmentId) { url in
                                // Removing it takes it off the dogs that still have it, not their own photos.
                                let previous = groupPhoto
                                groupPhoto = url
                                if let url { forAll { $0.photoUrl = url } }
                                else if let previous { forAll { if $0.photoUrl == previous { $0.photoUrl = nil } } }
                            }
                            .frame(maxWidth: 224)
                            Text(L("One photo for every dog’s report.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                ModalSection(title: L("Each dog")) {
                    VStack(spacing: 12) {
                        ForEach(pets) { pet in dogCard(pet) }
                    }
                    HStack(spacing: 6) {
                        Glyph("users-round", size: 14)
                        Text(L("Each family sees only their own dog’s report."))
                    }
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .onAppear(perform: setUp)
        .sheet(item: $full) { target in SvcReportSheet(target: target, onSaved: onSaved) }
    }


    /// One dog (web: the "Each dog" item): its fields as selects, a note and its photo; mango-edged while something it must have is missing.
    private func dogCard(_ pet: SvcSessionPet) -> some View {
        let report = drafts[pet.appointmentId] ?? SvcReport(kind: kind ?? "walk")
        let missing = SvcReportText.missing(session.serviceCategory, report)
        let required = SvcReportText.required(session.serviceCategory, report)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PetAvatar(name: pet.name, species: pet.species, photoURL: pet.photoUrl, size: 32)
                Text(pet.name).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                Spacer(minLength: 8)
                if !missing.isEmpty {
                    Text(LF("Missing: %@", SvcReportText.fieldsText(missing))).font(Theme.text(11.2, weight: .bold)).foregroundStyle(Theme.inkSoft)
                }
            }
            // The fields the report must have carry the red mark (web `Field required`).
            if report.kind == "walk" {
                FormField(label: L("Pee"), required: required.contains("pee")) {
                    StaysPlainMenu(options: [("", "—"), ("yes", L("Yes")), ("no", L("No"))],
                                   selection: Binding(get: { report.pee.map { $0 ? "yes" : "no" } ?? "" }, set: { value in edit(pet) { $0.pee = value.isEmpty ? nil : value == "yes" } }), accessibility: L("Pee"))
                }
                FormField(label: L("Poop")) {
                    StaysPlainMenu(options: [("", "—")] + SvcReportText.stool.map { ($0, SvcReportText.option($0)) },
                                   selection: Binding(get: { report.poop ?? "" }, set: { value in edit(pet) { $0.poop = value.nonEmpty } }), accessibility: L("Poop"))
                }
            } else {
                FormField(label: L("Skills"), required: required.contains("skills")) {
                    SvcSkillsField(skills: report.skills) { skills in edit(pet) { $0.skills = skills } }
                }
                FormField(label: L("Progress"), required: required.contains("progress")) {
                    StaysPlainMenu(options: [("", "—")] + SvcReportText.progress.map { ($0, SvcReportText.option($0)) },
                                   selection: Binding(get: { report.progress ?? "" }, set: { value in edit(pet) { $0.progress = value.nonEmpty } }), accessibility: L("Progress"))
                }
            }
            FormField(label: L("Behaviour"), required: required.contains("behaviour")) {
                StaysPlainMenu(options: [("", "—")] + SvcReportText.behaviours.map { ($0, SvcReportText.option($0)) },
                               selection: Binding(get: { report.behaviour ?? "" }, set: { value in edit(pet) { $0.behaviour = value.nonEmpty } }), accessibility: L("Behaviour"))
            }
            TextField(L("A note for the family"), text: Binding(get: { report.note ?? "" }, set: { value in edit(pet) { $0.note = value.isEmpty ? nil : value } }))
                .fieldChrome()
            SvcPhotoSlot(label: L("Photo"), url: report.photoUrl, disabled: false, appointmentId: pet.appointmentId) { url in edit(pet) { $0.photoUrl = url } }
                .frame(maxWidth: 224)
            PMButton(L("Full report"), systemImage: "clipboard-pen", variant: .outline, size: .compact) {
                full = SvcReportTarget(subtitle: "\(pet.name) · \(session.serviceLabel)", pets: [SvcReportPet(id: pet.appointmentId, name: pet.name)], canWrite: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(missing.isEmpty ? AnyShapeStyle(Theme.borderSoft) : AnyShapeStyle(Theme.mix(Theme.mango, 55, with: Theme.borderSoft)), lineWidth: 1))
    }

    private func setUp() {
        guard let kind, drafts.isEmpty else { return }
        var next: [String: SvcReport] = [:]
        for pet in pets {
            let stored = session.entry(pet.appointmentId)?.report
            next[pet.appointmentId] = stored?.kind == kind ? stored! : SvcReport(kind: kind)
        }
        drafts = next
        originals = next
        // Opening on saved reports: the homework they share shows here.
        let homeworks = Set(next.values.map { $0.homework ?? "" })
        homeworkForAll = homeworks.count == 1 ? (homeworks.first ?? "") : ""
    }

    private func edit(_ pet: SvcSessionPet, _ change: (inout SvcReport) -> Void) {
        var report = drafts[pet.appointmentId] ?? SvcReport(kind: kind ?? "walk")
        change(&report)
        drafts[pet.appointmentId] = report
    }

    private func forAll(_ change: (inout SvcReport) -> Void) {
        for key in drafts.keys {
            var report = drafts[key]!
            change(&report)
            drafts[key] = report
        }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            var count = 0
            do {
                for pet in pets {
                    guard let draft = drafts[pet.appointmentId], draft != originals[pet.appointmentId] else { continue }
                    let _: SvcIgnored = try await API.put("/provider-appointments/\(pet.appointmentId)/report", json: draft)
                    originals[pet.appointmentId] = draft
                    count += 1
                }
                Toast.show(count > 0 ? LF("Reports saved for %d pets.", count) : L("Nothing changed."))
                announceDataChanged()
                onSaved()
                dismiss()
            } catch {
                Toast.error(error)
            }
        }
    }
}

/// A dog's skills typed with commas between them: the text stays as typed, the report gets the list.
private struct SvcSkillsField: View {
    let skills: [String]
    let onChange: ([String]) -> Void
    @State private var text = ""

    var body: some View {
        TextField(L("Sit, stay, recall"), text: $text)
            .fieldChrome()
            .onAppear { text = skills.joined(separator: ", ") }
            .onChange(of: text) { _, value in
                let next = svcSplitSkills(value)
                if next != skills { onChange(next) }
            }
            // "Add to all" changed the list from outside.
            .onChange(of: skills) { _, next in
                if svcSplitSkills(text) != next { text = next.joined(separator: ", ") }
            }
    }
}

/// "Sit, stay , recall" → ["Sit", "stay", "recall"]: no blanks, no repeats, 20 at most.
func svcSplitSkills(_ text: String) -> [String] {
    var out: [String] = []
    for part in text.split(separator: ",") {
        let skill = part.trimmingCharacters(in: .whitespaces)
        if !skill.isEmpty && !out.contains(skill) { out.append(skill) }
    }
    return Array(out.prefix(20))
}
