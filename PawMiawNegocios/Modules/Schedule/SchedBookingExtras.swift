//
//  SchedBookingExtras.swift
//  PawMiawNegocios
//
//  The booking sheet's optional parts (web provider-appointment-sheet.tsx):
//  "Does this visit repeat?" (lib/visit-repeat.ts, booking-repeat-fields.tsx),
//  where a home visit happens (addresses/visit-address-picker.tsx), and the
//  emergency triage at arrival (hospital/triage-fields.tsx), which the
//  walk-in, the check-in and the visit's triage card share.
//

import SwiftUI

// MARK: - Repeating bookings

/// A repeating booking: every N weeks a number of times, or on chosen weekdays until a day.
struct SchedRepeatDraft: Equatable {
    var on = false
    /// A preset's id, or "custom" for "Other…".
    var choice = "custom"
    /// "weeks" or "weekdays".
    var mode = "weeks"
    var everyWeeks = 1
    var occurrences = 8
    /// ISO weekdays, 1 (Monday) … 7 (Sunday).
    var weekdays: [Int] = []
    /// "yyyy-MM-dd", inclusive; nil = four weeks after the first visit.
    var until: String?
}

enum SchedRepeat {
    static let maxWeeks = 26
    static let maxVisits = 120

    struct Preset { let id: String; let label: String; let mode: String; let everyWeeks: Int; let occurrences: Int; var weekdays: [Int] = [] }

    /// Only a walk, sitting, class or daycare repeats; anyone else says when it comes back on finishing.
    static func repeats(_ category: String?) -> Bool { ["walker", "sitter", "trainer", "daycare"].contains(category ?? "") }

    static func presets(_ category: String?) -> [Preset] {
        let weekly = { (n: Int) in Preset(id: "weekly", label: L("Every week"), mode: "weeks", everyWeeks: 1, occurrences: n) }
        let every = { (weeks: Int, n: Int) in Preset(id: "every-\(weeks)", label: weeks == 2 ? L("Every 2 weeks") : L("Every 4 weeks"), mode: "weeks", everyWeeks: weeks, occurrences: n) }
        let weekdays = Preset(id: "weekdays", label: L("Monday to Friday"), mode: "weekdays", everyWeeks: 1, occurrences: 0, weekdays: [1, 2, 3, 4, 5])
        switch category {
        case "walker", "sitter", "daycare": return [weekdays, weekly(8), every(2, 6)]
        case "trainer": return [weekly(6), every(2, 6)]
        default: return [weekly(4), every(2, 4), every(4, 3)]
        }
    }

    /// 1 Monday … 7 Sunday.
    static func isoWeekday(_ day: String) -> Int {
        let weekday = SchedDay.calendar.component(.weekday, from: SchedDay.start(day))
        return ((weekday + 5) % 7) + 1
    }

    static func defaultUntil(_ first: String) -> String { SchedDay.addDays(first, 28) }
    static func lastUntil(_ first: String) -> String { SchedDay.addDays(first, maxWeeks * 7) }

    /// The chosen weekdays with the first visit's day always in, in week order.
    static func weekdays(_ chosen: [Int], first: String) -> [Int] {
        Array(Set(chosen + [isoWeekday(first)])).filter { (1...7).contains($0) }.sorted()
    }

    static func untilProblem(_ first: String, _ until: String) -> Bool {
        until < first || until > lastUntil(first)
    }

    /// The days the repeat books, the first visit included (as the server counts them).
    static func dates(_ draft: SchedRepeatDraft, first: String) -> [String] {
        guard draft.on else { return [] }
        let every = max(1, min(maxWeeks, draft.everyWeeks))
        if draft.mode == "weeks" {
            let count = max(2, min(52, draft.occurrences))
            return (0..<count).map { SchedDay.addDays(first, $0 * every * 7) }
        }
        let until = draft.until ?? defaultUntil(first)
        guard !untilProblem(first, until) else { return [] }
        let chosen = weekdays(draft.weekdays, first: first)
        let monday = SchedDay.addDays(first, 1 - isoWeekday(first))
        var days: [String] = []
        var week = 0
        while days.count < maxVisits {
            let start = SchedDay.addDays(monday, week * 7)
            if start > until { break }
            for weekday in chosen {
                let day = SchedDay.addDays(start, weekday - 1)
                if day < first || day > until { continue }
                if days.count < maxVisits { days.append(day) }
            }
            week += every
        }
        return days
    }

    /// What `repeat` carries on the booking; nil when it doesn't repeat.
    static func body(_ draft: SchedRepeatDraft, first: String) -> [String: Any]? {
        guard draft.on else { return nil }
        let every = max(1, min(maxWeeks, draft.everyWeeks))
        if draft.mode == "weekdays" {
            return ["everyWeeks": every, "weekdays": weekdays(draft.weekdays, first: first), "until": draft.until ?? defaultUntil(first)]
        }
        return ["everyWeeks": every, "occurrences": max(2, min(52, draft.occurrences))]
    }

    static func weekdayLabel(_ weekday: Int) -> String {
        switch weekday {
        case 1: L("Mon")
        case 2: L("Tue")
        case 3: L("Wed")
        case 4: L("Thu")
        case 5: L("Fri")
        case 6: L("Sat")
        default: L("Sun")
        }
    }
}

/// "Does this visit repeat?": no, the service's usual rhythms, or "Other…" with every option. The dates it books are listed.
struct SchedRepeatFields: View {
    @Binding var draft: SchedRepeatDraft
    /// The first visit's day.
    let firstDay: String
    let category: String?
    var invalid = false

    private static let shown = 8

    private var presets: [SchedRepeat.Preset] { SchedRepeat.presets(category) }
    private var choice: String {
        guard draft.on else { return "none" }
        return presets.contains { $0.id == draft.choice } ? draft.choice : "custom"
    }
    private var until: String { draft.until ?? SchedRepeat.defaultUntil(firstDay) }
    private var dates: [String] { SchedRepeat.dates(draft, first: firstDay) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 8) {
                FilterChip(title: L("Does not repeat"), isSelected: choice == "none") { draft.on = false }
                ForEach(presets, id: \.id) { preset in
                    FilterChip(title: preset.label, isSelected: choice == preset.id) { pick(preset) }
                }
                FilterChip(title: L("Other…"), isSelected: choice == "custom") {
                    draft.on = true
                    draft.choice = "custom"
                }
            }
            if draft.on {
                VStack(alignment: .leading, spacing: 12) {
                    if choice == "custom" {
                        Segmented(options: [
                            .init("weeks", L("Every N weeks")),
                            .init("weekdays", L("On these days")),
                        ], selection: $draft.mode, look: .raised, label: L("Repeat"))
                        if draft.mode == "weekdays" { weekdayChips }
                        Stepper(value: $draft.everyWeeks, in: 1...SchedRepeat.maxWeeks) {
                            Text("\(L("Every")) \(draft.everyWeeks) \(L("week(s)"))").font(Theme.text(15, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                        }
                    }
                    if draft.mode == "weeks" {
                        Stepper(value: $draft.occurrences, in: 2...52) {
                            Text(choice == "custom" ? "\(draft.occurrences) \(L("visits in all"))" : "\(L("How many times")): \(draft.occurrences)")
                                .font(Theme.text(15, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                        }
                    } else {
                        untilField
                    }
                    datesList
                }
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(invalid ? Theme.coral : Theme.borderSoft, lineWidth: invalid ? 2 : 1))
            }
        }
    }

    private var weekdayChips: some View {
        let chosen = SchedRepeat.weekdays(draft.weekdays, first: firstDay)
        let locked = SchedRepeat.isoWeekday(firstDay)
        return FlowLayout(spacing: 6) {
            ForEach(1...7, id: \.self) { weekday in
                FilterChip(title: SchedRepeat.weekdayLabel(weekday), isSelected: chosen.contains(weekday)) {
                    guard weekday != locked else { return }
                    var next = chosen
                    if next.contains(weekday) { next.removeAll { $0 == weekday } } else { next.append(weekday) }
                    draft.weekdays = SchedRepeat.weekdays(next, first: firstDay)
                }
            }
        }
    }

    private var untilField: some View {
        VStack(alignment: .leading, spacing: 4) {
            DayField(label: L("Until"), day: Binding(get: { until }, set: { draft.until = $0 }), min: firstDay, max: SchedRepeat.lastUntil(firstDay))
            if SchedRepeat.untilProblem(firstDay, until) {
                Text(L("Choose an end date within 26 weeks of the first visit")).font(Theme.text(13, weight: .semibold)).foregroundStyle(Theme.coralText)
            } else if draft.mode == "weekdays" {
                let days = SchedRepeat.weekdays(draft.weekdays, first: firstDay).map(SchedRepeat.weekdayLabel).joined(separator: ", ")
                Text(LF("%@ visits · %@ · until %@", String(dates.count), days, SchedDay.shortLabel(until))).font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    @ViewBuilder private var datesList: some View {
        if !dates.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                FlowLayout(spacing: 6) {
                    ForEach(dates.prefix(Self.shown), id: \.self) { day in
                        Text(SchedDay.shortLabel(day)).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.blueWash, in: Capsule())
                    }
                    if dates.count > Self.shown {
                        Text(LF("and %@ more", String(dates.count - Self.shown))).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    }
                }
                Text(LF("%@ visits are booked now. Days that are closed or already taken are skipped.", String(dates.count))).font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func pick(_ preset: SchedRepeat.Preset) {
        draft.on = true
        draft.choice = preset.id
        draft.mode = preset.mode
        draft.everyWeeks = preset.everyWeeks
        if preset.mode == "weeks" { draft.occurrences = preset.occurrences }
        draft.weekdays = preset.weekdays
        if preset.mode == "weekdays" && draft.until == nil { draft.until = SchedRepeat.defaultUntil(firstDay) }
    }
}

// MARK: - Where a home visit happens

/// The client's addresses (the family's and the business's) as cards, the default first; a new
/// one added without leaving the booking; and the arrival notes that travel with the visit.
struct SchedAddressPicker: View {
    let clientId: String
    @Binding var addressId: String?
    @Binding var accessNotes: String
    var error: String? = nil

    @EnvironmentObject private var workspace: Workspace
    @State private var home: ClientsHome?
    @State private var failed = false
    @State private var adding = false

    private var addresses: [ClientsAddress] {
        (home?.addresses ?? []).filter { $0.status != "archived" }
            .sorted { ($0.isDefault == true ? 0 : 1, $0.name) < ($1.isDefault == true ? 0 : 1, $1.name) }
    }
    private var canEdit: Bool { workspace.can(.clientsEdit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Where")).font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.inkStrong)
                Spacer()
                if canEdit && !addresses.isEmpty {
                    Button { adding = true } label: { HStack(spacing: 4) { Glyph("plus", size: 14); Text(L("New address")) } }
                        .font(Theme.text(13, weight: .bold)).foregroundStyle(Theme.blue)
                }
            }
            if failed && home == nil {
                NoticeCard(tone: .warning, title: L("Couldn’t load the addresses."), actionTitle: L("Try again")) { Task { await load(selectNew: false) } }
            } else if home == nil {
                ProgressView().frame(maxWidth: .infinity)
            } else if addresses.isEmpty {
                NoticeCard(tone: .info, title: L("No address yet"),
                           message: canEdit ? L("A home visit needs the client’s address. Add it here.") : L("Ask someone who can edit clients to add the address."),
                           actionTitle: canEdit ? L("Add address") : nil, action: canEdit ? { adding = true } : nil)
            } else {
                VStack(spacing: 8) {
                    ForEach(addresses) { address in option(address) }
                }
            }
            if let error { Text(error).font(Theme.text(13, weight: .semibold)).foregroundStyle(Theme.coral) }
            PMTextField(L("Arrival & access notes"), text: $accessNotes, prompt: L("Ring the side door; the dog barks but is friendly."), hint: L("Travels with this visit. Codes and keys go in the address’s access details."), optional: true, multiline: true)
        }
        .task(id: clientId) { await load(selectNew: false) }
        .sheet(isPresented: $adding) {
            ClientsAddressSheet(clientId: clientId, address: nil, makeDefault: addresses.isEmpty) { await load(selectNew: true) }
        }
    }

    private func option(_ address: ClientsAddress) -> some View {
        let active = addressId == address.id
        return Button { addressId = address.id } label: {
            HStack(alignment: .top, spacing: 10) {
                Glyph(active ? "circle-dot" : "circle", size: 20).foregroundStyle(active ? Theme.blue : Theme.inkSoft)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(address.label?.nonEmpty ?? L("Address")).font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        if address.isDefault == true { Chip(text: L("Default"), tone: .good, icon: "star") }
                        if address.source == "family" { Chip(text: L("From the family"), tone: .online) }
                    }
                    Text(address.formatted ?? address.line1 ?? "—").font(Theme.smallFont).foregroundStyle(Theme.inkStrong)
                    if let reference = address.reference?.nonEmpty { Text(reference).font(Theme.captionFont).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                    if address.vault?.hasVault == true {
                        HStack(spacing: 4) { Glyph("key-round", size: 12); Text(L("Access details written")) }.font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(active ? AnyShapeStyle(Theme.wash(Theme.aqua, 18)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(active ? Theme.aqua.opacity(0.7) : Theme.borderSoft, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    /// The default is chosen first; a choice that is no longer the client's falls back to it. A new one is chosen.
    private func load(selectNew: Bool) async {
        let before = Set(addresses.map(\.id))
        do {
            let loaded: ClientsHome = try await API.get("/provider-clients/\(clientId)/home")
            home = loaded
            failed = false
        } catch is CancellationError {
            return
        } catch {
            failed = true
            return
        }
        let now = addresses
        if selectNew, let added = now.first(where: { !before.contains($0.id) }) {
            addressId = added.id
            Toast.show(L("Address added."))
            return
        }
        if let addressId, now.contains(where: { $0.id == addressId }) { return }
        addressId = now.first(where: { $0.isDefault == true })?.id ?? now.first?.id
    }
}

// MARK: - Emergency triage

/// The triage typed at arrival (a walk-in, a check-in) or on the visit.
struct SchedTriageDraft: Equatable {
    var on = false
    var priority: String?
    var reason = ""
    var vitals = HospVitalsDraft()

    enum Missing: Equatable { case priority, reason, vital(HospVitalsDraft.Field) }

    /// What is sent (nil when it isn't an emergency), or what is missing. The visit's reason stands in for a blank one.
    func parsed(fallbackReason: String = "") -> (value: [String: Any?]?, missing: Missing?) {
        guard on else { return (nil, nil) }
        guard let priority else { return (nil, .priority) }
        let why = reason.nonEmpty ?? fallbackReason.nonEmpty
        guard let why else { return (nil, .reason) }
        switch vitals.parsed() {
        case .failure(let problem): return (nil, .vital(problem.field))
        case .success(let values): return (["priority": priority, "reason": why, "vitals": values], nil)
        }
    }

    static func missingText(_ missing: Missing) -> String {
        switch missing {
        case .priority: L("Choose the triage: critical, urgent or stable.")
        case .reason: L("Say why the patient came in.")
        case .vital(let field): LF("Check %@.", HospVitalsDraft.label(field))
        }
    }
}

/// "Emergency" at arrival: the switch, then the priority, why they came and quick vitals.
struct SchedTriageFields: View {
    @Binding var draft: SchedTriageDraft
    /// Always an emergency (the triage sheet): no switch.
    var lockOn = false
    var invalid: SchedTriageDraft.Missing? = nil
    @State private var showVitals = false

    private var shown: Bool { draft.on || lockOn }
    private var vitalInvalid: HospVitalsDraft.Field? {
        if case .vital(let field) = invalid { return field }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !lockOn {
                ToggleRow(title: L("Emergency"), subtitle: L("Triage it: the waiting room goes by priority."), isOn: $draft.on)
            }
            if shown {
                FormField(label: L("Triage")) {
                    PillPicker(options: HospWords.priorities.map { ($0, HospWords.triage($0)) }, choice: Binding(get: { draft.priority }, set: { draft.priority = $0; draft.on = true }))
                }
                if invalid == .priority { Text(SchedTriageDraft.missingText(.priority)).font(Theme.text(13, weight: .semibold)).foregroundStyle(Theme.coral) }
                PMTextField(L("Why"), text: Binding(get: { draft.reason }, set: { draft.reason = $0; draft.on = true }), prompt: L("Why they came, e.g. Hit by a car, breathing fast"))
                if invalid == .reason { Text(SchedTriageDraft.missingText(.reason)).font(Theme.text(13, weight: .semibold)).foregroundStyle(Theme.coral) }
                DisclosureGroup(isExpanded: Binding(get: { showVitals || vitalInvalid != nil }, set: { showVitals = $0 })) {
                    HospVitalsFields(draft: $draft.vitals, invalid: vitalInvalid).padding(.top, 8)
                } label: {
                    Text(L("Quick vitals")).font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.inkStrong)
                }
                .tint(Theme.inkStrong)
            }
        }
        .padding(shown ? 12 : 0)
        .background(shown ? AnyShapeStyle(Theme.wash(Theme.pink, 14)) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
    }
}
