//
//  StaysHomeStaySheets.swift
//  PawMiawNegocios
//
//  A home stay's own sheets (web home-stay-action-sheets.tsx, home-stay-sheet.tsx
//  AccessCard; docs/homestays.md): give the stay to another sitter, change its
//  dates and plan (the price or a catalog service, the house's rules and tasks,
//  the address and notes), record the keys, add a visit, and the access card —
//  where it happens, the arrival notes, the access details opened on purpose
//  (an audited reveal, hidden again after five minutes) and whom to call.
//

import SwiftUI

// MARK: - The team

enum StaysHomeTeam {
    /// The business's team (to choose a sitter or who has the keys).
    static func members() async -> [StaysMember] {
        guard let clinic = Workspace.shared.current?.clinicId else { return [] }
        return (try? await API.get("/provider-workspaces/\(clinic)/members")) ?? []
    }

    /// "Double booking": the sitter already has visits then (web `HomeConflictNotice`: the red
    /// notice with its "Book it anyway — I know" box inside).
    static func conflictNotice(confirmed: Binding<Bool>) -> some View {
        NoticeCard(tone: .problem, title: L("Double booking"), icon: "triangle-alert", look: .inline) {
            Text(L("The sitter already has visits then, or can’t get there in time.")).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
            StaysTickRow(title: L("Book it anyway — I know"), isOn: confirmed)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        }
        .id("conflict")
    }
}

// MARK: - Give the stay to another sitter

struct StaysHomeReassignSheet: View {
    let stay: StaysStay
    let home: StaysHomeDetail

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var members: [StaysMember] = []
    @State private var memberId = ""
    @State private var reason = ""
    @State private var conflict = false
    @State private var overlapOk = false
    @State private var working = false

    private var sitters: [StaysMember] { members.filter { $0.canCare && $0.id != home.sitter?.memberId } }

    var body: some View {
        ProviderModal(
            title: L("Give the stay to another sitter"),
            subtitle: home.sitter?.name.map { LF("Now: %@", $0) } ?? L("Nobody assigned yet"),
            systemImage: "user-round-cog",
            accent: .aqua,
            isDirty: !memberId.isEmpty || !reason.isEmpty,
            form: form,
            primaryTitle: conflict ? L("Give it anyway") : L("Give the stay"),
            isWorking: working,
            primaryIcon: "user-round-cog",
            onPrimary: submit
        ) {
            Text(L("Every visit still to make passes to them. A visit under way stays with whoever is there.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            MenuField(label: L("New sitter"), options: [(value: "", title: L("Choose someone"))] + sitters.map { (value: $0.id, title: $0.label) },
                      selection: Binding(get: { memberId }, set: { memberId = $0; conflict = false; overlapOk = false }), key: "member", form: form)
            PMTextField(L("Why (the family reads it)"), text: $reason, prompt: L("e.g. Laura is sick"))
            if conflict { StaysHomeTeam.conflictNotice(confirmed: $overlapOk) }
        }
        .presentationDetents([.medium, .large])
        .task { if members.isEmpty { members = await StaysHomeTeam.members() } }
    }

    private func submit() {
        guard form.check([("member", memberId.isEmpty ? L("Choose who takes over.") : nil)]) else { return }
        if conflict && !overlapOk { Toast.error(L("The sitter is busy then. Check the warning and book it anyway if you meant to.")); return }
        working = true
        Task {
            defer { working = false }
            struct Moved: Decodable { let moved: Int? }
            var body: [String: Any?] = ["memberId": memberId, "reason": reason.nonEmpty]
            if overlapOk { body["allowDoubleBooking"] = true }
            do {
                let result: Moved = try await API.post("/provider-homestays/\(stay.id)/reassign", body: body)
                let moved = result.moved ?? 0
                Toast.show(stay.familyOnApp
                    ? (moved == 1 ? L("1 visit passed on. The family and the new sitter have been told.") : LF("%d visits passed on. The family and the new sitter have been told.", moved))
                    : (moved == 1 ? L("1 visit passed on. The new sitter has been told.") : LF("%d visits passed on. The new sitter has been told.", moved)))
                announceDataChanged()
                dismiss()
            } catch let api as APIError where api.code == "visit_conflict" {
                conflict = true
                overlapOk = false
            } catch let api as APIError where ["same_sitter", "invalid_member", "member_cannot_care", "member_not_at_location"].contains(api.code ?? "") {
                _ = form.check([("member", StaysWords.homeError(api, fallback: "Could not change the sitter."))])
            } catch {
                Toast.error(StaysWords.homeError(error, fallback: "Could not change the sitter."))
            }
        }
    }
}

// MARK: - Change the home stay

struct StaysHomeEditSheet: View {
    let stay: StaysStay
    let home: StaysHomeDetail

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var plan = StaysHomePlan()
    @State private var original = StaysHomePlan()
    @State private var addressId: String?
    @State private var accessNotes = ""
    @State private var ownerInstructions = ""
    @State private var internalNotes = ""
    @State private var conflict = false
    @State private var overlapOk = false
    @State private var working = false
    @State private var started = false

    private var hasStarted: Bool { stay.status == "checked_in" }

    var body: some View {
        ProviderModal(
            title: L("Change the home stay"),
            subtitle: L("Extend or shorten it, change the plan, the price or the house. Visits already made stay."),
            systemImage: "calendar-plus",
            accent: .aqua,
            isDirty: started && plan != original,
            form: form,
            primaryTitle: conflict ? L("Save anyway") : L("Save"),
            isWorking: working,
            primaryIcon: "save",
            onPrimary: submit
        ) {
            if stay.status == "requested" && home.quoteSentAt != nil {
                NoticeCard(tone: .warning, title: L("The quote was sent. Changing the price, dates or plan withdraws it; send it again after saving."))
            }
            StaysHomePlanForm(plan: $plan, form: form, showMeetGreet: false, startedDay: hasStarted ? stay.checkInDay : nil, editing: true)
            ModalSection(title: L("At their home"), subtitle: hasStarted ? L("The stay has started at this address.") : nil) {
                if !hasStarted, let clientId = stay.providerClientId {
                    // The one address picker of every visit at a client's home (with its arrival notes).
                    SchedAddressPicker(clientId: clientId,
                                       addressId: Binding(get: { addressId }, set: { addressId = $0; conflict = false; form.clear("address") }),
                                       accessNotes: $accessNotes, error: form.error("address"))
                        .id("address")
                } else {
                    PMTextField(L("Arrival & access notes"), text: $accessNotes, multiline: true)
                }
            }
            ModalSection(title: L("Notes")) {
                PMTextField(L("What the family asked for"), text: $ownerInstructions, multiline: true)
                PMTextField(L("Note for the team"), text: $internalNotes, multiline: true)
            }
            if conflict { StaysHomeTeam.conflictNotice(confirmed: $overlapOk) }
        }
        .onAppear {
            guard !started else { return }
            started = true
            plan = StaysHomePlan(stay: stay, home: home)
            original = plan
            addressId = home.addressId
            accessNotes = home.accessNotes ?? ""
            ownerInstructions = stay.ownerInstructions ?? ""
            internalNotes = stay.internalNotes ?? ""
        }
        .onChange(of: plan) { _, _ in conflict = false; overlapOk = false }
    }

    private func submit() {
        let rules = plan.problems.filter { $0.0 != "meetGreet" }
        guard form.check(rules) else { return }
        if conflict && !overlapOk { Toast.error(L("The sitter is busy then. Check the warning and book it anyway if you meant to.")); return }
        working = true
        Task {
            defer { working = false }
            var body = plan.body(sitterId: nil)
            body.removeValue(forKey: "meetGreet")
            body["depositCents"] = plan.deposit
            if !hasStarted, let addressId, addressId != home.addressId { body["addressId"] = addressId }
            body["accessNotes"] = accessNotes.nonEmpty
            body["ownerInstructions"] = ownerInstructions.nonEmpty
            body["internalNotes"] = internalNotes.nonEmpty
            if overlapOk { body["allowDoubleBooking"] = true }
            do {
                let data = try await API.data("PATCH", "/provider-homestays/\(stay.id)", query: [:], body: try API.jsonBody(body))
                let saved: StaysHomeEnvelope? = try? API.decode(data)
                Toast.show(stay.status == "requested" && home.quoteSentAt != nil && saved?.home != nil && saved?.home?.quoteSentAt == nil
                    ? L("Saved. The quote was withdrawn — send it again.")
                    : L("Home stay updated. The visits were laid out again."))
                announceDataChanged()
                dismiss()
            } catch let api as APIError {
                let code = api.code ?? ""
                if code == "visit_conflict" {
                    conflict = true
                    overlapOk = false
                } else if ["invalid_dates", "too_long", "overnight_needs_a_night", "already_started", "visits_outside"].contains(code) {
                    _ = form.check([("dates", StaysWords.homeError(api, fallback: "Could not change this home stay."))])
                } else if ["times_required", "too_many_times", "invalid_time", "invalid_duration", "invalid_overnight", "visits_overlap", "no_visits"].contains(code) {
                    _ = form.check([("plan", StaysWords.homeError(api, fallback: "Could not change this home stay."))])
                } else if ["address_required", "address_not_found", "address_archived"].contains(code) {
                    _ = form.check([("address", StaysWords.homeError(api, fallback: "Could not change this home stay."))])
                } else {
                    Toast.error(StaysWords.homeError(api, fallback: "Could not change this home stay."))
                }
            } catch {
                Toast.error(StaysWords.homeError(error, fallback: "Could not change this home stay."))
            }
        }
    }
}

// MARK: - The keys

struct StaysHomeKeysSheet: View {
    let stay: StaysStay
    let home: StaysHomeDetail

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var members: [StaysMember] = []
    @State private var action = ""
    @State private var holder = ""
    @State private var label = ""
    @State private var note = ""
    @State private var working = false
    @State private var started = false

    private var out: Bool { home.keys?.state == "with_sitter" || home.keys?.state == "lockbox" }
    private var actions: [String] { out ? ["transferred", "lockbox", "returned"] : ["received"] }
    private var needsHolder: Bool { action == "received" || action == "transferred" }

    private func title(_ action: String) -> String {
        switch action {
        case "received": L("Received")
        case "transferred": L("Passed on")
        case "lockbox": L("In the lockbox")
        default: L("Returned")
        }
    }

    var body: some View {
        ProviderModal(
            title: L("The keys"),
            subtitle: StaysWords.keysState(home.keys),
            systemImage: "key-round",
            accent: .aqua,
            isDirty: !note.isEmpty || label != (home.keys?.label ?? ""),
            form: form,
            primaryTitle: L("Record"),
            isWorking: working,
            primaryIcon: "key-round",
            onPrimary: submit
        ) {
            ChoiceCards(options: actions.map { (value: $0, title: title($0), subtitle: nil) },
                        selection: Binding(get: { action }, set: { value in
                            action = value
                            if value == "transferred" { holder = "" }
                            form.clear("holder")
                        }))
            if needsHolder {
                MenuField(label: action == "received" ? L("Who has them") : L("Passed on to"),
                          options: [(value: "", title: L("Choose someone"))] + members.filter { action != "transferred" || $0.id != home.keys?.holder?.memberId }.map { (value: $0.id, title: $0.label) },
                          selection: $holder, key: "holder", form: form)
            }
            PMTextField(L("Which keys"), text: $label, prompt: L("e.g. Front door + gate, blue tag"))
            PMTextField(L("Note (optional)"), text: $note)
        }
        .presentationDetents([.medium, .large])
        .task {
            if members.isEmpty { members = await StaysHomeTeam.members().filter { $0.status != "suspended" } }
            guard !started else { return }
            started = true
            action = out ? "returned" : "received"
            holder = out ? "" : (home.sitter?.memberId ?? members.first { $0.isCurrentMember == true }?.id ?? "")
            label = home.keys?.label ?? ""
        }
    }

    private func submit() {
        guard form.check([("holder", needsHolder && holder.isEmpty ? L("Say who has the keys.") : nil)]) else { return }
        working = true
        Task {
            defer { working = false }
            var body: [String: Any?] = ["action": action, "label": label.nonEmpty, "note": note.nonEmpty]
            if needsHolder { body["holderMemberId"] = holder }
            do {
                try await API.send("POST", "/provider-homestays/\(stay.id)/keys", body: body)
                Toast.show(L("Keys recorded."))
                announceDataChanged()
                dismiss()
            } catch let api as APIError where ["holder_required", "same_holder", "invalid_member", "keys_not_out"].contains(api.code ?? "") {
                _ = form.check([("holder", StaysWords.homeError(api, fallback: "Could not record the keys."))])
            } catch {
                Toast.error(StaysWords.homeError(error, fallback: "Could not record the keys."))
            }
        }
    }
}

// MARK: - Add a visit

struct StaysHomeAddVisitSheet: View {
    let stay: StaysStay
    let home: StaysHomeDetail

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var members: [StaysMember] = []
    @State private var kind = "visit"
    @State private var date = ""
    @State private var startTime = "12:00"
    @State private var minutes = 45
    @State private var memberId = ""
    @State private var conflict = false
    @State private var overlapOk = false
    @State private var working = false

    var body: some View {
        ProviderModal(
            title: L("Add a visit"),
            subtitle: stay.petNames,
            systemImage: "calendar-plus",
            accent: .aqua,
            form: form,
            primaryTitle: conflict ? L("Add anyway") : L("Add"),
            isWorking: working,
            primaryIcon: "plus",
            onPrimary: submit
        ) {
            ChoiceCards(options: ["visit", "overnight", "meet_greet"].map { (value: $0, title: StaysWords.homeVisitKind($0), subtitle: Optional<String>.none) },
                       selection: Binding(get: { kind }, set: { value in
                           kind = value
                           if value == "overnight" { startTime = home.plan?.overnightStart ?? "20:00" }
                           reset()
                       }))
            DayField(label: L("Day"), day: Binding(get: { date }, set: { date = $0; reset() }), key: "date", form: form)
            TimeField(label: kind == "overnight" ? L("Arrives in the evening") : L("Time"), value: Binding(get: { startTime }, set: { startTime = $0; reset() }), from: "05:00", to: "23:45")
            if kind == "overnight" {
                FactRow(label: L("Leaves the next morning"), value: StaysDay.clock(home.plan?.overnightEnd ?? "08:00"))
            } else {
                MenuField(label: L("Length"), options: Array(Set([15, 20, 30, 45, 60, 90, 120, 180, 240, minutes])).sorted().map { (value: $0, title: StaysHomePlanForm.minutesText($0)) },
                          selection: Binding(get: { minutes }, set: { minutes = $0; reset() }))
            }
            MenuField(label: L("Sitter"), options: [(value: "", title: L("Decide later"))] + members.filter(\.canCare).map { (value: $0.id, title: $0.label) },
                      selection: Binding(get: { memberId }, set: { memberId = $0; reset() }))
            if conflict { StaysHomeTeam.conflictNotice(confirmed: $overlapOk) }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            guard date.isEmpty else { return }
            let today = home.today?.dayKey ?? StaysDay.today()
            date = today > stay.checkInDay && today <= stay.checkOutDay ? today : stay.checkInDay
            minutes = home.plan?.durationMinutes ?? 45
            memberId = home.sitter?.memberId ?? ""
        }
        .task { if members.isEmpty { members = await StaysHomeTeam.members() } }
    }

    private func reset() { conflict = false; overlapOk = false; form.clear("date") }

    private func submit() {
        if conflict && !overlapOk { Toast.error(L("The sitter is busy then. Check the warning and book it anyway if you meant to.")); return }
        working = true
        Task {
            defer { working = false }
            var body: [String: Any?] = ["kind": kind, "date": date, "startTime": startTime, "memberId": memberId.nonEmpty]
            if kind == "overnight" { body["endTime"] = home.plan?.overnightEnd ?? "08:00" } else { body["durationMinutes"] = minutes }
            if overlapOk { body["allowDoubleBooking"] = true }
            do {
                try await API.send("POST", "/provider-homestays/\(stay.id)/visits", body: body)
                Toast.show(LF("%@ added.", StaysWords.homeVisitKind(kind)))
                announceDataChanged()
                dismiss()
            } catch let api as APIError where api.code == "visit_conflict" {
                conflict = true
                overlapOk = false
            } catch {
                _ = form.check([("date", StaysWords.homeError(error, fallback: "Could not add this visit."))])
            }
        }
    }
}

// MARK: - Where, and getting in

/// Where the stay happens, the arrival notes, the access details (when this person may
/// open them: an audited reveal) and whom to call.
struct StaysHomeAccessCard: View {
    let stay: StaysStay
    let home: StaysHomeDetail

    @State private var asking: Bool?
    @State private var revealed: SvcVaultReveal?
    @State private var revealedAt = Date()
    @State private var now = Date()

    private var family: Bool { home.address?.source == "family" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let address = home.address {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let label = address.label?.nonEmpty { Text(label).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong) }
                        if address.source == "family" { TagChip(text: L("From the family"), icon: "link-2", linked: true) }
                    }
                    Text(address.formatted ?? "").font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    if let reference = address.reference?.nonEmpty { Text(reference).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                    if let maps = address.mapsUrl.flatMap(URL.init(string:)) {
                        Link(destination: maps) {
                            HStack(spacing: 4) { Glyph("map-pin", size: 14); Text(L("Open in Maps")) }
                                .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue)
                        }
                    }
                }
                if address.shared == false {
                    HStack(alignment: .top, spacing: 6) {
                        Glyph("triangle-alert", size: 14).padding(.top, 1)
                        Text(L("This address is no longer shared. This is how it was when the stay was booked."))
                    }
                    .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.wash(Theme.mango, 18), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                }
            } else {
                HStack(spacing: 6) {
                    Glyph("map-pin", size: 16).foregroundStyle(Theme.blue)
                    Text(L("No address on this stay"))
                }
                .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
            }
            if let notes = home.accessNotes?.nonEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Arrival & access notes").uppercased()).font(.brandText(10.6, weight: .heavy)).tracking(10.6 * 0.1).foregroundStyle(Theme.inkSoft)
                    Text(notes).font(Theme.text(14)).foregroundStyle(Theme.inkStrong).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(Theme.mango, 12), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            }
            if home.address != nil { accessDetails }
            RowDivider()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                contact(L("Emergency contact"), home.emergencyContact, empty: L("None yet"))
                if let familyContact = home.familyEmergencyContact, familyContact.name?.nonEmpty != nil {
                    contact(L("The family’s emergency contact"), familyContact, empty: "")
                }
            }
        }
        .sheet(item: Binding(get: { asking.map { StaysRevealAsk(emergency: $0) } }, set: { asking = $0?.emergency })) { ask in
            ConfirmSheet(
                title: ask.emergency ? L("Emergency opening") : L("Show access details?"),
                message: (ask.emergency
                          ? L("There is no visit now. Open them only if something is wrong, and say why: the family is told right away, with your words.")
                          : family ? L("Opening these is recorded and the family is told each time.") : L("Opening these is recorded."))
                    + " " + L("They stay on screen for 5 minutes at most, then hide again."),
                confirmTitle: ask.emergency ? L("Open in an emergency") : L("Show them"),
                destructive: ask.emergency,
                askReason: ask.emergency,
                reasonRequired: ask.emergency,
                reasonLabel: L("What happened?"),
                // Web RevealConfirmSheet: teal with the key, coral with the triangle in an emergency.
                accent: ask.emergency ? .coral : .aqua,
                icon: ask.emergency ? "triangle-alert" : "key-round",
                confirmIcon: "eye"
            ) { reason in
                let body: [String: Any?] = ask.emergency ? ["emergencyReason": reason] : [:]
                do {
                    let result: SvcVaultReveal = try await API.post("/provider-homestays/\(stay.id)/vault/reveal", body: body)
                    revealed = result
                    revealedAt = Date()
                } catch {
                    throw APIError(status: (error as? APIError)?.status ?? 400, message: StaysWords.homeError(error, fallback: "Could not open the access details."), code: nil, fields: [:])
                }
            }
        }
    }

    // MARK: Access details

    @ViewBuilder private var accessDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Glyph("key-round", size: 16).foregroundStyle(Theme.blue)
                Text(L("Access details"))
            }
            .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
            if let revealed {
                revealedView(revealed)
            } else {
                let fields = home.vault?.fields ?? []
                if !fields.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(fields, id: \.self) { Chip(text: SvcVault.label($0), tone: .muted, icon: "lock") }
                    }
                }
                vaultState
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    @ViewBuilder private var vaultState: some View {
        let vault = home.vault
        if vault?.canReveal == true {
            PMButton(L("Show access details"), systemImage: "eye", size: .compact) { asking = false }
            if vault?.reason == "assigned_in_window", let closes = vault?.window?.closesAt {
                Text(LF("Open for the stay’s sitters until %@.", DateText.dayTime(DateText.parse(closes), zone: home.zone))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
            Text(family ? L("Opening these is recorded and the family is told each time.") : L("Opening these is recorded.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        } else {
            switch vault?.reason {
            case "window_closed":
                let next = (vault?.window?.open == false ? vault?.window : nil)
                    ?? (vault?.windows ?? []).first { (DateText.parse($0.opensAt) ?? .distantPast) > Date() }
                HStack(alignment: .top, spacing: 6) {
                    Glyph("clock-3", size: 14).foregroundStyle(Theme.blue).padding(.top, 1)
                    Text(next?.opensAt.map { LF("They open %@ — 30 minutes before the first visit.", DateText.dayTime(DateText.parse($0), zone: home.zone)) }
                         ?? L("Closed — they open 30 minutes before the first visit and close 30 minutes after the stay ends."))
                }
                .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                if vault?.canEmergency == true {
                    PMButton(L("Emergency opening"), systemImage: "triangle-alert", variant: .destructive, size: .compact) { asking = true }
                }
            case "family_off": quiet(L("The family hasn’t shared its access details with your business."))
            case "not_assigned": quiet(L("Only the stay’s sitters see them."))
            case "no_vault": quiet(family ? L("The family hasn’t written access details.") : L("No access details were written for this address."))
            case "not_shared": quiet(L("This address is no longer shared."))
            case "unavailable": quiet(L("Not available right now."))
            default: EmptyView()
            }
        }
    }

    private func quiet(_ text: String) -> some View {
        Text(text).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
    }

    private func revealedView(_ reveal: SvcVaultReveal) -> some View {
        let left = max(1, Int(ceil((revealedAt.addingTimeInterval(300).timeIntervalSince(now)) / 60)))
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(SvcVault.fields.filter { reveal.vault[$0]?.nonEmpty != nil }, id: \.self) { field in
                VStack(alignment: .leading, spacing: 2) {
                    Text(SvcVault.label(field)).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    Text(reveal.vault[field] ?? "").font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).textSelection(.enabled)
                }
            }
            HStack {
                Text(LF("Hides by itself in %d min (at %@).", left, DateText.time(revealedAt.addingTimeInterval(300), zone: home.zone))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                Spacer()
                PMButton(L("Hide"), systemImage: "eye-off", variant: .outline, size: .compact) { revealed = nil }
            }
        }
        .task(id: revealedAt) {
            // Counted on this device from when they arrived; they hide themselves after five minutes.
            while !Task.isCancelled && Date() < revealedAt.addingTimeInterval(300) {
                try? await Task.sleep(for: .seconds(15))
                now = Date()
            }
            if !Task.isCancelled { revealed = nil }
        }
    }

    private func contact(_ title: String, _ contact: StaysContact?, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            StaysEyebrow(text: title, tint: Theme.inkSoft)
            if let contact, let name = contact.name?.nonEmpty {
                Text(name + (contact.relationship?.nonEmpty.map { " · \($0)" } ?? "")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                if let phone = contact.phone?.nonEmpty { PhoneLink(phone: phone) }
            } else {
                Text(empty).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
        }
    }
}

private struct StaysRevealAsk: Identifiable {
    let emergency: Bool
    var id: Bool { emergency }
}
