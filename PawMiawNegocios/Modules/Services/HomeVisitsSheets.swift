//
//  HomeVisitsSheets.swift
//  PawMiawNegocios
//
//  Domicilio's sheets and its settings (web: home-visits/reassign-sheet.tsx,
//  visit-check.tsx, addresses/vault-sheets.tsx, stays/home-stay-visit-sheet.tsx
//  for a home stay's visit — leave, couldn't get in, missed — the day moved
//  to someone else, and home-visits-settings.tsx).
//

import SwiftUI

// MARK: - Reassign one visit

/// Give one visit to someone else (web `ReassignSheet`): whose visit it is, the people
/// who can take it; a clash is said and booked only on purpose.
struct SvcReassignSheet: View {
    let item: SvcHomeVisitItem
    let members: [SvcMember]

    @Environment(\.dismiss) private var dismiss
    @State private var memberId = ""
    @State private var clash: String?
    @State private var anyway = false
    @State private var working = false

    /// People who work visits (or look after stays), other than who has it now.
    private var candidates: [SvcMember] {
        members.filter { $0.can(item.isStay ? .staysCare : .appointmentsComplete) && $0.id != item.assigned?.id }
    }

    var body: some View {
        ProviderModal(title: L("Reassign"), subtitle: L("Give this visit to"), systemImage: "user-round-cog", accent: .lavender, isDirty: !memberId.isEmpty, primaryTitle: L("Reassign"), isWorking: working, primaryIcon: "user-round-cog", onPrimary: submit) {
            ContextPills(client: item.client.name, pets: item.pets.map(\.name))
            if candidates.isEmpty {
                Text(L("Nobody else can take this visit."))
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            } else {
                ChoiceCards(options: candidates.map { member -> (value: String, title: String, subtitle: String?) in (member.id, member.shownName, nil) }, selection: Binding(get: { memberId }, set: { memberId = $0; clash = nil; anyway = false }))
            }
            if let clash {
                NoticeCard(tone: .warning, title: L("Double booking"), message: clash)
                ToggleRow(title: L("Book it anyway — I know they overlap"), isOn: $anyway)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() {
        guard !memberId.isEmpty else { Toast.error(L("Choose a person")); return }
        guard clash == nil || anyway else { Toast.error(L("Book it anyway — I know they overlap")); return }
        working = true
        Task {
            defer { working = false }
            do {
                if item.isStay, let stay = item.stayId, let visit = item.stayVisitId {
                    var body: [String: Any?] = ["memberId": memberId]
                    if anyway { body["allowDoubleBooking"] = true }
                    let _: SvcIgnored = try await SvcAPI.send("PATCH", "/provider-homestays/\(stay)/visits/\(visit)", body: body)
                } else if let id = item.appointmentId {
                    var body: [String: Any?] = ["assignedOrganizationMemberId": memberId]
                    if anyway { body["allowDoubleBooking"] = true }
                    let _: SvcIgnored = try await SvcAPI.send("PATCH", "/provider-appointments/\(id)", body: body)
                }
                Toast.show(LF("Visit reassigned to %@.", members.first { $0.id == memberId }?.shownName ?? "—"))
                announceDataChanged()
                dismiss()
            } catch {
                if svcCode(error) == "visit_conflict" {
                    clash = svcMessage(error)
                    anyway = false
                    return
                }
                Toast.error(svcMessage(error, codes: SvcRefusals.homeVisits))
            }
        }
    }
}

// MARK: - Where it was recorded (owners and admins)

/// Where a visit's arrival and finish were recorded (web `VisitCheckSheet`), for owners
/// and admins: the distance from the address, else the point, else why there is none.
struct SvcVisitCheckSheet: View {
    let item: SvcHomeVisitItem
    let timeZone: String?
    let locationOn: Bool

    @State private var check: SvcHomeVisitCheck?
    @State private var failed: String?

    var body: some View {
        ProviderModal(title: L("Where it was recorded"), subtitle: "\(item.petNames) · \(item.serviceText)", systemImage: "locate-fixed", accent: .lavender, cancelTitle: L("Close")) {
            HStack(spacing: 6) {
                Glyph("shield-check", size: 14).foregroundStyle(Theme.blue)
                Text(L("Only owners and admins see this."))
            }
            .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
            if let check {
                if let booked = check.bookedMinutes, let actual = check.actualMinutes {
                    Chip(text: check.shortVisit == true ? LF("Short visit · %d of %d min", actual, booked) : LF("Lasted %d of %d min", actual, booked), tone: .custom(check.shortVisit == true ? Theme.mango : ProviderState.done.color), icon: check.shortVisit == true ? "timer-off" : nil, percent: (check.shortVisit == true) ? 26 : 16, weight: .heavy, border: (check.shortVisit == true) ? 80 : 55, size: .large)
                }
                if !locationOn && check.stamps?.arrive == nil && check.stamps?.finish == nil {
                    // Nothing was ever saved for this visit and the business records none: said, not two empty boxes.
                    HStack(alignment: .top, spacing: 8) {
                        Glyph("locate-fixed", size: 16).padding(.top, 1)
                        Text(L("This business doesn’t record location on home visits. It is turned on in Settings."))
                    }
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                } else {
                    stampBlock(L("Arrival"), "arrive", check.stamps?.arrive)
                    stampBlock(L("Departure"), "finish", check.stamps?.finish)
                    if check.address?.hasCoordinates == false {
                        Text(L("The address has no map point, so the distance can’t be measured.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    }
                }
            } else if failed != nil {
                SvcLoadError(message: L("Where this visit was recorded couldn’t be loaded.")) { await load() }
            } else {
                LoadingState()
            }
        }
        .task { await load() }
    }

    private func stampBlock(_ title: String, _ kind: String, _ stamp: SvcStamp?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(title)
            if let stamp, let line = SvcHomeRules.stampLine(kind, SvcStampSummary(status: stamp.status, recordedAt: stamp.recordedAt, distanceM: stamp.distanceM, far: stamp.far), isManager: true) {
                Chip(text: line.text, tone: .custom(SvcHomeRules.stampTone(warn: line.warn, muted: line.muted)), icon: "locate-fixed", percent: (line.warn) ? 26 : 16, weight: .heavy, border: (line.warn) ? 80 : 55, size: .large)
                Text(stamp.recordedByName.map { LF("Recorded by %@ at %@", $0, SvcTime.clock(stamp.recordedAt, timeZone)) } ?? LF("Recorded at %@", SvcTime.clock(stamp.recordedAt, timeZone)))
                    .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                if stamp.status == "ok", let lat = stamp.latitude, let lng = stamp.longitude {
                    Text(String(format: "%.6f, %.6f", lat, lng)).font(.system(size: 14, design: .monospaced)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    if let accuracy = stamp.accuracyM { Text(LF("Accuracy ±%d m", Int(accuracy.rounded()))).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft) }
                    if let maps = stamp.mapsUrl {
                        PMButton(L("Open in maps"), systemImage: "external-link", variant: .outline, size: .modal, fullWidth: true) { svcOpen(maps) }
                    }
                }
            } else {
                Text(L("Nothing recorded")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1.5))
    }

    private func load() async {
        do {
            let query: [String: String?] = item.isStay ? ["stayVisitId": item.stayVisitId] : ["appointmentId": item.appointmentId]
            check = try await API.get("/provider-home-visits/check", query: query)
            failed = nil
        } catch is CancellationError {
        } catch {
            failed = L("Where this visit was recorded couldn’t be loaded.")
        }
    }
}

// MARK: - The access details: an audited reveal, five minutes on screen

struct SvcRevealConfirmSheet: View {
    let item: SvcHomeVisitItem
    let emergency: Bool
    let onRevealed: (SvcVaultReveal) -> Void

    var body: some View {
        ConfirmSheet(
            title: emergency ? L("Emergency opening") : L("Show access details?"),
            message: (emergency
                      ? L("There is no visit now. Open them only if something is wrong, and say why: the family is told right away, with your words.")
                      : L("Opening these is recorded.")) + " " + L("They stay on screen for 5 minutes at most, then hide again."),
            confirmTitle: emergency ? L("Open in an emergency") : L("Show them"),
            destructive: emergency,
            askReason: emergency,
            reasonRequired: emergency,
            reasonLabel: L("What happened?"),
            // Web RevealConfirmSheet: teal with the key, coral with the triangle in an emergency.
            accent: emergency ? .coral : .aqua,
            icon: emergency ? "triangle-alert" : "key-round",
            confirmIcon: "eye"
        ) { reason in
            let path: String
            if item.isStay, let stay = item.stayId {
                path = "/provider-homestays/\(stay)/vault/reveal"
            } else {
                path = "/provider-appointments/\(item.appointmentId ?? "")/access/reveal"
            }
            let body: [String: Any?] = emergency ? ["emergencyReason": reason] : [:]
            let result: SvcVaultReveal = try await API.post(path, body: body)
            onRevealed(result)
        }
    }
}

struct SvcVaultSheet: View {
    let item: SvcHomeVisitItem
    let reveal: SvcVaultReveal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ProviderModal(title: L("Arrival & access"), subtitle: item.address?.label?.nonEmpty ?? item.address?.line, systemImage: "key-round", accent: .aqua, cancelTitle: L("Hide")) {
            let fields = SvcVault.fields.filter { reveal.vault[$0]?.nonEmpty != nil }
            VStack(spacing: 0) {
                ForEach(fields, id: \.self) { field in
                    if field != fields.first { RowDivider() }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(SvcVault.label(field)).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                        Text(reveal.vault[field] ?? "").font(Theme.text(17, weight: .bold)).foregroundStyle(Theme.inkStrong).textSelection(.enabled)
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text(L("They stay on screen for 5 minutes at most, then hide again.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
        .task {
            try? await Task.sleep(for: .seconds(300))
            if !Task.isCancelled { dismiss() }
        }
    }
}

// MARK: - A home stay's visit: leave, couldn't get in, missed

/// Domicilio's card (and Home) open a home stay's visit move by its card: the one move sheet
/// a stay's visit uses (Stays' StaysVisitMoveSheet), with the card's window and checklist.
struct SvcStayMoveSheet: View {
    let item: SvcHomeVisitItem
    /// "leave", "no-access" or "missed".
    let move: String
    let timeZone: String?
    /// Leaving from Domicilio: where the phone was, as its Finish records it.
    var locate: (() async -> VisitPosition)? = nil

    var body: some View {
        StaysVisitMoveSheet(stayId: item.stayId ?? "", visitId: item.stayVisitId ?? "", move: move,
                            when: "\(item.petNames) · \(SvcHomeRules.window(item, timeZone))",
                            checklist: item.checklist.map { (done: $0.done, total: $0.total) }, locate: locate)
    }
}

// MARK: - Move someone's day

/// Someone is off (web `ReassignDaySheet`): their visits that day go to another person, or to whoever is free.
struct SvcMoveDaySheet: View {
    let date: String
    let people: [SvcHomePerson]
    let members: [SvcMember]
    let initialFrom: String?

    @Environment(\.dismiss) private var dismiss
    @State private var from = ""
    @State private var to = "free"
    @State private var working = false
    @StateObject private var form = FormState()

    private var fromOptions: [(value: String, title: String)] {
        [("", L("Choose a person"))] + people.compactMap { person in person.memberId.map { ($0, person.name ?? "—") } }
    }

    private var toOptions: [(value: String, title: String)] {
        [("free", L("Whoever is free"))] + members.filter { $0.can(.appointmentsComplete) && $0.id != from }.map { ($0.id, $0.shownName) }
    }

    var body: some View {
        ProviderModal(title: L("Move someone’s day"), subtitle: L("Someone is off: their visits today go to another person, or to whoever is free."), systemImage: "users", accent: .aqua, isDirty: !from.isEmpty, form: form, primaryTitle: L("Move visits"), isWorking: working, cancelTitle: L("Back"), onPrimary: submit) {
            Text(svcCapitalized(SvcTime.dayLong(date))).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkSoft)
            MenuField(label: L("From"), options: fromOptions, selection: $from, key: "from", form: form)
            MenuField(label: L("To"), options: toOptions, selection: $to)
        }
        .presentationDetents([.medium, .large])
        .onAppear { if let initialFrom { from = initialFrom } }
    }

    private func submit() {
        guard form.check([("from", from.isEmpty ? L("Choose a person") : nil)]) else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let result: [String: JSONValue] = try await API.post("/provider-appointments/reassign", body: ["date": date, "fromMemberId": from, "toMemberId": to == "free" ? nil : to])
                let moved = result["moved"]?.int ?? 0, skipped = result["skipped"]?.int ?? 0, off = result["off"]?.int ?? 0
                if off > 0 { Toast.show(LF("%d visits moved; %d stay put because the other person is off then (a day off or their own hours).", moved, off)) }
                else if skipped > 0 { Toast.show(LF("%d visits moved; %d stay put (under way, or the other person is busy then).", moved, skipped)) }
                else { Toast.show(LF("%d visits moved.", moved)) }
                announceDataChanged()
                dismiss()
            } catch {
                form.apply(error, known: ["fromMemberId": "from"])
            }
        }
    }
}

// MARK: - Settings

/// How home visits work here (web `HomeVisitsSettingsPanel`): what the family is told,
/// when a visit is late or short, and what is saved about where it happened.
struct SvcHomeVisitSettingsTab: View {
    let canManage: Bool
    let businessName: String

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var saved: SvcHomeVisitSettings?
    @State private var failed: String?
    @State private var autoStarted = true
    @State private var categories: [String] = []
    @State private var message = ""
    @State private var late = ""
    @State private var short = ""
    @State private var far = ""
    @State private var retention = ""
    @State private var working = false
    @State private var confirming: String?
    @StateObject private var form = FormState()

    private static let categoryOptions: [(value: String, title: String)] = [("vet", "Vet"), ("groomer", "Grooming"), ("trainer", "Training"), ("walker", "Walks"), ("sitter", "Sitting"), ("other", "Other")]
    private static let standard = "Hi {client}, this is {business}: we’re on our way to see {pet}.[ We’ll be there in about {minutes} minutes.]"

    private func number(_ text: String, _ range: ClosedRange<Int>) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), range.contains(value) else { return nil }
        return value
    }

    private var dirty: Bool {
        guard let saved else { return false }
        return autoStarted != (saved.autoStartedNotice ?? true) || Set(categories) != Set(saved.onMyWayCategories ?? []) || message.nonEmpty != saved.onMyWayMessage?.nonEmpty
            || late != (saved.lateAfterMinutes.map(String.init) ?? "") || short != (saved.shortVisitPercent.map(String.init) ?? "")
            || far != (saved.farFromAddressMeters.map(String.init) ?? "") || retention != (saved.locationRetentionDays.map(String.init) ?? "")
    }

    var body: some View {
        if let saved {
            FormScroll(form: form) {
                SettingsCard(icon: "house", tone: Theme.aqua, title: L("How home visits work"),
                                hint: canManage ? L("For the whole business: what the family is told, when a visit is late and what is saved about where it happened.") : L("Set by whoever manages the business. You can read it here."),
                                note: canManage ? nil : L("Only someone who edits the workspace can change this.")) {
                    if sizeClass == .regular {
                        HStack(alignment: .top, spacing: 16) {
                            noticesRule
                            VStack(spacing: 16) { lateRule; locationRule(saved) }
                        }
                    } else {
                        VStack(spacing: 16) { noticesRule; lateRule; locationRule(saved) }
                    }
                } footer: {
                    if canManage {
                        SaveBar(dirty: dirty, working: working, onDiscard: { reset(saved) }, onSave: { save(saved) })
                    }
                }
            }
            .sheet(item: Binding(get: { confirming.map { SvcIdentified(id: $0) } }, set: { confirming = $0?.id })) { key in
                SvcLocationDisclosureSheet(kind: key.id, days: saved.locationRetentionDays ?? 90) {
                    try await setLocation(key.id, on: true, acknowledged: true)
                }
            }
        } else if failed != nil {
            SvcLoadError(message: L("The settings couldn’t be loaded.")) { await load() }
        } else {
            LoadingState().task { await load() }
        }
    }

    private var noticesRule: some View {
        SettingsRule(icon: "bell-ring", tone: Theme.aqua, title: L("Notices"), hint: L("What the family hears about a visit to their home.")) {
            ToggleRow(title: L("Tell the family when a home visit starts"), subtitle: L("They get a notice in PawMiaw when you press “I’ve arrived”."), isOn: $autoStarted)
                .disabled(!canManage)
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Offer “On my way” for")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                FlowLayout(spacing: 6) {
                    ForEach(Self.categoryOptions, id: \.value) { option in
                        let on = categories.contains(option.value)
                        FilterChip(title: L(option.title), isSelected: on, tone: Theme.blue, icon: on ? "check" : nil) {
                            if on { categories.removeAll { $0 == option.value } } else { categories.append(option.value) }
                        }
                        .disabled(!canManage)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L("“On my way” message")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                TextField(L(Self.standard), text: $message, axis: .vertical).lineLimit(3...8).fieldChrome(multiline: true).disabled(!canManage)
                Text(L("Use {pet}, {client}, {business} and {minutes}. Text in [brackets] is sent only when you say how long.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                if canManage {
                    SvcPlaceholderRow(placeholders: ["{pet}", "{client}", "{business}", "{minutes}"], onAdd: { message += $0 },
                                      extra: message.nonEmpty != nil ? (L("Use the standard message"), { message = "" }) : nil)
                }
                SvcMessagePreview(text: preview, standard: message.nonEmpty == nil).padding(.top, 6)
            }
        }
    }

    private var lateRule: some View {
        SettingsRule(icon: "timer-off", tone: Theme.mango, title: L("Late and short visits"), hint: L("When the page flags a visit. Only owners and admins see short visits.")) {
            numberRow("late", before: L("A visit is late after"), after: L("minutes"), text: $late, range: 5...120)
            numberRow("short", before: L("Flag a visit that lasted less than"), after: L("% of its booked time"), text: $short, range: 10...90)
        }
    }

    private func locationRule(_ saved: SvcHomeVisitSettings) -> some View {
        SettingsRule(icon: "locate-fixed", tone: Theme.lavender, title: L("Location"), hint: L("Off unless you turn it on. Read what it saves before you do.")) {
            ToggleRow(title: L("Save the location at arrival and finish"), subtitle: L("Where the phone is at those two presses. Never in between."), isOn: locationBinding("locationStamps", saved.locationStamps ?? false))
                .disabled(!canManage || working)
            numberRow("far", before: L("“Far from the address” beyond"), after: L("meters"), text: $far, range: 100...5000)
            ToggleRow(title: L("Record the route of walks"), subtitle: L("The family sees it drawn as a line in the walk’s report. It may have gaps: the browser stops recording when the phone locks."), isOn: locationBinding("walkRoutes", saved.walkRoutes ?? false))
                .disabled(!canManage || working)
            numberRow("retention", before: L("Delete locations after"), after: L("days"), text: $retention, range: 30...365)
            VStack(alignment: .leading, spacing: 8) {
                Text(disclosure(saved.locationRetentionDays ?? 90)).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                if let disclosure = saved.locationDisclosure, let at = disclosure.acknowledgedAt {
                    HStack(spacing: 6) {
                        Glyph("shield-check", size: 14).foregroundStyle(Theme.blue)
                        Text(disclosure.acknowledgedByName.map { LF("Confirmed by %@ on %@", $0, DateText.date(at)) } ?? LF("Confirmed on %@", DateText.date(at)))
                    }
                    .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        }
    }

    /// "A visit is late after [15] minutes" (web `NumberRow`): the range said in red while it is out of it.
    private func numberRow(_ key: String, before: String, after: String, text: Binding<String>, range: ClosedRange<Int>) -> some View {
        let valid = number(text.wrappedValue, range) != nil
        return FlowLayout(spacing: 8) {
            Text(before).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
            TextField("", text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = String($0.filter(\.isNumber).prefix(4)); form.clear(key) }))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .fieldChrome(invalid: form.error(key) != nil || !valid)
                .frame(width: 80)
                .disabled(!canManage)
            Text(after).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
            if !valid { Text(LF("From %d to %d", range.lowerBound, range.upperBound)).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.destructive) }
        }
        .id(key)
    }

    private func disclosure(_ days: Int) -> String {
        LF("When this is on, PawMiaw saves where the phone is at the moment someone presses Arrive and Finish on a home visit — not before, not after, and never in the background. During a walk with routes on, the path is recorded while the page stays open. Only owners and admins see locations; families only ever see the walk drawn as a line, without a map or an address. Locations are deleted after %d days. Tell your team before turning this on.", days)
    }

    private var preview: String {
        // The text in [brackets] goes only when "how long" is said; the preview says 10 minutes.
        (message.nonEmpty ?? L(Self.standard))
            .replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "{pet}", with: "Rocky").replacingOccurrences(of: "{client}", with: "Carlos")
            .replacingOccurrences(of: "{business}", with: businessName.nonEmpty ?? L("your business")).replacingOccurrences(of: "{minutes}", with: "10")
    }

    /// A location switch: off at once; on only with the acknowledgement on file (asked for when it isn't).
    private func locationBinding(_ key: String, _ value: Bool) -> Binding<Bool> {
        Binding(get: { value }, set: { on in
            if on && saved?.locationDisclosure?.acknowledgedAt == nil {
                confirming = key
                return
            }
            Task {
                do { try await setLocation(key, on: on, acknowledged: false) } catch { Toast.error(svcMessage(error, codes: SvcRefusals.homeVisits)) }
            }
        })
    }

    private func setLocation(_ key: String, on: Bool, acknowledged: Bool) async throws {
        var body: [String: Any?] = [key: on]
        if on && acknowledged { body["acknowledgeLocation"] = true }
        let result: SvcHomeVisitSettings = try await API.put("/provider-home-visits/settings", body: body)
        saved = result
        Toast.show(on ? (key == "locationStamps" ? L("Location turned on. Your team was told.") : L("Walk routes turned on. Your team was told.")) : L("Settings saved."))
        announceDataChanged()
    }

    private func reset(_ settings: SvcHomeVisitSettings) {
        autoStarted = settings.autoStartedNotice ?? true
        categories = settings.onMyWayCategories ?? []
        message = settings.onMyWayMessage ?? ""
        late = settings.lateAfterMinutes.map(String.init) ?? ""
        short = settings.shortVisitPercent.map(String.init) ?? ""
        far = settings.farFromAddressMeters.map(String.init) ?? ""
        retention = settings.locationRetentionDays.map(String.init) ?? ""
    }

    private func load() async {
        do {
            let loaded: SvcHomeVisitSettings = try await API.get("/provider-home-visits/settings")
            saved = loaded
            reset(loaded)
            failed = nil
        } catch is CancellationError {
        } catch {
            failed = L("The settings couldn’t be loaded.")
        }
    }

    private func save(_ settings: SvcHomeVisitSettings) {
        let lateValue = number(late, 5...120), shortValue = number(short, 10...90), farValue = number(far, 100...5000), retentionValue = number(retention, 30...365)
        guard form.check([
            ("late", lateValue == nil ? LF("From %d to %d", 5, 120) : nil),
            ("short", shortValue == nil ? LF("From %d to %d", 10, 90) : nil),
            ("far", farValue == nil ? LF("From %d to %d", 100, 5000) : nil),
            ("retention", retentionValue == nil ? LF("From %d to %d", 30, 365) : nil),
        ]) else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let result: SvcHomeVisitSettings = try await API.put("/provider-home-visits/settings", body: [
                    "autoStartedNotice": autoStarted,
                    "onMyWayCategories": Self.categoryOptions.map(\.value).filter(categories.contains),
                    "onMyWayMessage": message.nonEmpty,
                    "lateAfterMinutes": lateValue, "shortVisitPercent": shortValue,
                    "farFromAddressMeters": farValue, "locationRetentionDays": retentionValue,
                ])
                saved = result
                reset(result)
                Toast.show(L("Settings saved."))
                announceDataChanged()
            } catch {
                form.apply(error, known: ["lateAfterMinutes": "late", "shortVisitPercent": "short", "farFromAddressMeters": "far", "locationRetentionDays": "retention"])
            }
        }
    }
}

/// Before location is turned on (web `LocationDisclosureSheet`): what it saves, who sees it
/// and for how long, and a box to tick — the team was told. Without the tick there is no "Turn on".
private struct SvcLocationDisclosureSheet: View {
    let kind: String
    let days: Int
    let turnOn: () async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var told = false
    @State private var working = false

    var body: some View {
        ProviderModal(title: kind == "walkRoutes" ? L("Turn on walk routes?") : L("Turn on location?"), subtitle: L("Your team is told in PawMiaw as soon as you turn it on."),
                      systemImage: "locate-fixed", accent: .lavender, primaryTitle: L("Turn on"), isWorking: working,
                      primaryIcon: "locate-fixed", primaryDisabled: !told, onPrimary: confirm) {
            Text(LF("When this is on, PawMiaw saves where the phone is at the moment someone presses Arrive and Finish on a home visit — not before, not after, and never in the background. During a walk with routes on, the path is recorded while the page stays open. Only owners and admins see locations; families only ever see the walk drawn as a line, without a map or an address. Locations are deleted after %d days. Tell your team before turning this on.", days))
                .font(Theme.text(15.2)).foregroundStyle(Theme.inkStrong)
            // Web: a checkbox in a bordered row.
            StaysTickRow(title: L("I’ve told my team"), isOn: $told)
        }
        .presentationDetents([.medium, .large])
    }

    private func confirm() {
        working = true
        Task {
            defer { working = false }
            do {
                try await turnOn()
                dismiss()
            } catch {
                Toast.error(svcMessage(error, codes: SvcRefusals.homeVisits))
            }
        }
    }
}

/// A plain string as a sheet's item.
struct SvcIdentified: Identifiable { let id: String }
