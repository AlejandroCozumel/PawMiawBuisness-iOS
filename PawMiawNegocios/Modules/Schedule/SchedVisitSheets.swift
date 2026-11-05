//
//  SchedVisitSheets.swift
//  PawMiawNegocios
//
//  A visit's moves, each a sheet (web visits/visit-sheets.tsx): check in,
//  a visit on another day moved to now, finish ("Terminar") with the one
//  charge choice of docs/charging-flow.md and "¿Cuándo vuelve?", "Sí vino"
//  for a visit left open (docs/business-visits-left-open.md), no-show and
//  cancel with the fee decision, and booking a missed visit again.
//

import SwiftUI

// MARK: - Check in

struct SchedCheckInSheet: View {
    let appointment: SchedAppointment
    let canStart: Bool
    /// A start stopped by a consent or a deposit: the caller shows the gate once this sheet is gone.
    var onGate: (SchedGatePrompt) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var weight = ""
    @State private var note = ""
    @State private var roomId: String?
    @State private var startNow = false
    @State private var load: SchedLoad?
    @State private var working = false
    @State private var prepared = false
    @State private var triage = SchedTriageDraft()
    @State private var triageInvalid: SchedTriageDraft.Missing?
    private let now = Date()

    private var booked: String? { (appointment.arrivalNote ?? appointment.notes)?.nonEmpty }
    /// Triage is for a clinical visit at a clinic: a groom, a walk or a class checked in there has none.
    private var vetCare: Bool { Workspace.shared.offers(.vet, .emergency) && appointment.isClinical }
    private var lastKg: String? {
        guard let grams = appointment.petWeight, grams > 0 else { return nil }
        return String(format: "%.1f", (grams / 100).rounded() / 10)
    }

    private var groomVisit: Bool { appointment.serviceCategory == "groomer" }
    /// Today's weight against the last on file: "+0.4 kg", mango from a 10% change.
    private var weightChange: (kg: Double, percent: Double)? {
        guard let lastKg, let last = Double(lastKg), last > 0,
              let typed = Double(weight.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) else { return nil }
        return (((typed - last) * 10).rounded() / 10, (typed - last) / last * 100)
    }

    var body: some View {
        ProviderModal(title: L("Check in"), subtitle: "\(appointment.petName) · \(appointment.serviceLabel) · \(appointment.clientName)", systemImage: "arrow-right-to-line", accent: .butter, isDirty: !weight.isEmpty || !note.isEmpty, form: form,
                      primaryTitle: startNow ? L("Check in and start") : L("Check in"), isWorking: working,
                      // A clinical visit shows the visit's journey: arrival, chart, signature, payment.
                      steps: vetCare ? ModalSteps(steps: [(L("Arrival"), "arrow-right-to-line"), (L("Chart"), "book-open-text"), (L("Signature"), "pen-line"), (L("Payment"), "hand-coins")], current: 0) : nil,
                      primaryIcon: startNow ? "play" : "arrow-right-to-line",
                      pebbleImageURL: appointment.petPhotoUrl) {
            submit()
        } content: {
            ModalSection(title: L("At the desk"), systemImage: "scale") {
                Text(vetCare ? L("What the vet should know before walking in.") : groomVisit ? L("What the groomer should know before starting.") : L("What whoever takes the visit should know before starting."))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                PMTextField(L("Weight today (kg)"), text: $weight, key: "weight", form: form, prompt: lastKg ?? "12.4", keyboard: .decimalPad)
                if let lastKg {
                    HStack(spacing: 8) {
                        Text(LF("Last on file: %@ kg", lastKg)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        if weight.isEmpty {
                            PMButton(L("Same"), variant: .outline, size: .small) { weight = lastKg }
                        } else if let change = weightChange {
                            Chip(text: "\(change.kg > 0 ? "+" : "")\(String(format: "%.1f", change.kg)) kg", tone: abs(change.percent) >= 10 ? .custom(Theme.mango) : .muted, percent: 25)
                        }
                    }
                }
                MenuField(label: L("Room"), options: roomOptions, selection: $roomId, optional: true)
            }
            ModalSection(title: L("Arrival notes"), systemImage: "notebook-pen", tint: Theme.butter) {
                if let booked {
                    (Text(L("When booking:")).bold() + Text(" " + booked))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                }
                SchedBareField(prompt: L("Why they came, what they brought…"), text: $note, form: form)
                if vetCare {
                    SchedTriageFields(draft: $triage, invalid: triageInvalid)
                        .onChange(of: triage) { _, _ in triageInvalid = nil }
                }
            }
            if canStart {
                ToggleRow(title: L("Start right away"), subtitle: startNow ? L("Skip the waiting room — you take the visit now.") : L("They wait in the waiting room until someone starts the visit."), isOn: $startNow)
            }
        }
        .task {
            guard !prepared else { return }
            prepared = true
            roomId = appointment.roomId
            startNow = canStart
            load = try? await SchedData.load(from: now, to: now.addingTimeInterval(2 * 3600), locationId: appointment.locationId ?? Workspace.shared.locationId)
            if roomId == nil, let name = appointment.room, let named = load?.visitRooms.first(where: { $0.name == name }) { roomId = named.id }
        }
    }

    private var roomOptions: [(value: String?, title: String)] {
        let rooms = load?.visitRooms ?? []
        let slot = SchedSlot(id: appointment.id, start: now, end: now.addingTimeInterval(30 * 60), memberId: nil, roomId: nil)
        return [(nil, L("No room"))] + rooms.map { room in
            let free = load.map { SchedConflicts.roomIsFree(slot, room: room, load: $0) } ?? true
            return (Optional(room.id), free ? room.name : "\(room.name) · \(L("taken"))")
        }
    }

    private func submit() {
        let typed = weight.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let kg = typed.isEmpty ? nil : Double(typed)
        let badWeight = !typed.isEmpty && (kg == nil || kg! <= 0 || kg! > 200)
        guard form.check([("weight", badWeight ? L("Enter the weight in kg, like 12.4") : nil)]) else { return }
        let arrivalNote = [booked, note.nonEmpty].compactMap { $0 }.joined(separator: "\n").nonEmpty
        // Why they came is asked once: the arrival note stands in for the triage's reason when that's left blank.
        let triaged: (value: [String: Any?]?, missing: SchedTriageDraft.Missing?) = vetCare ? triage.parsed(fallbackReason: arrivalNote ?? "") : (nil, nil)
        if let missing = triaged.missing {
            triageInvalid = missing
            Toast.error(SchedTriageDraft.missingText(missing))
            return
        }
        var body: [String: Any?] = ["arrivalNote": arrivalNote, "weightGrams": kg.map { Int(($0 * 1000).rounded()) }]
        if let value = triaged.value { body["triage"] = value }
        if let roomId { body["roomId"] = roomId }
        let id = appointment.id, pet = appointment.petName, base = body
        func send(_ start: Bool, _ extra: [String: Any?]) async throws {
            var payload = base
            payload["start"] = start
            for (key, value) in extra { payload[key] = value }
            let _: SchedMoveResponse = try await SchedAPI.send("POST", "/provider-appointments/\(id)/check-in", body: payload)
            announceDataChanged()
        }
        working = true
        Task {
            defer { working = false }
            do {
                try await send(startNow, [:])
                Toast.show(startNow ? LF("%@ is in.", pet) : LF("%@ is waiting.", pet))
                dismiss()
            } catch {
                if startNow, let prompt = SchedGatePrompt.from(error, visit: appointment, verb: "start",
                                                                attempt: { try await send(true, $0) },
                                                                onDone: { Toast.show(LF("%@ is in.", pet)) },
                                                                fallback: { try await send(false, [:]); Toast.show(LF("%@ is waiting.", pet)) }) {
                    dismiss()
                    onGate(prompt)
                } else {
                    form.apply(schedAPIError(error), known: ["weightGrams": "weight"])
                }
            }
        }
    }
}

// MARK: - A visit on another day

/// "Check in" on a visit that isn't today's: it says which day it is and moves it to now first.
struct SchedOtherDaySheet: View {
    let appointment: SchedAppointment
    /// "past" or "future".
    let when: String
    let canMove: Bool
    let onMoved: () -> Void
    var onNoShow: (() -> Void)? = nil
    var onWalkIn: (() -> Void)? = nil
    var onRecordPast: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var conflicts: [SchedConflict] = []
    @State private var confirmed = false
    @State private var hours: SchedHoursProblem?
    @State private var outside = false
    @State private var working = false
    private let now = Date()

    private var day: String { DateText.day(appointment.start) }
    private var target: (start: Date, end: Date) {
        let start = Calendar.current.date(bySetting: .second, value: 0, of: now) ?? now
        return (start, start.addingTimeInterval(TimeInterval(appointment.lengthMinutes * 60)))
    }
    private var waits: Bool { (!conflicts.isEmpty && !confirmed) || (hours != nil && !outside) }

    var body: some View {
        ProviderModal(title: when == "future" ? LF("This visit is on %@", day) : LF("This visit was on %@", day),
                      subtitle: "\(appointment.petName) · \(appointment.serviceLabel) · \(appointment.clientName)",
                      systemImage: "calendar-clock", accent: .butter,
                      primaryTitle: canMove ? L("Move to today and check in") : nil,
                      isWorking: working,
                      cancelTitle: when == "future" ? LF("Keep it on %@", day) : L("Back"),
                      primaryIcon: "arrow-right-to-line",
                      onPrimary: canMove ? { move() } : nil) {
            HStack(spacing: 10) {
                dayBox(L("Booked for"), DateText.longDay(appointment.start), DateText.time(appointment.start), moving: false)
                Glyph("arrow-right", size: 20).foregroundStyle(Theme.inkSoft)
                dayBox(L("Moves to"), L("Today"), DateText.time(target.start), moving: true)
            }
            Text(when == "future"
                 ? LF("Only today’s visits check in. If %@ is here for this visit, move it to now: its %@ time is freed.", appointment.petName, day)
                 : LF("Nobody checked %@ in that day. If they’re here now, move the visit to today.", appointment.petName))
                .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
            if !appointment.togetherPets.isEmpty {
                HStack(spacing: 6) {
                    Glyph("users", size: 14)
                    Text(LF("%@ move too: they’re booked together.", schedNames(appointment.togetherPets.compactMap(\.name))))
                }
                .font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
            }
            if !canMove {
                NoticeCard(tone: .warning, message: L("Moving a visit takes permission to edit bookings. Ask the front desk or an admin."), icon: nil)
            }
            if when == "future", let onWalkIn {
                SchedWayRow(title: L("Here for something else, or an emergency?"), hint: LF("Book a walk-in for today. This visit stays on %@.", day), actionTitle: L("Walk-in"), icon: "zap", action: onWalkIn)
            }
            if when == "past", let onRecordPast {
                SchedWayRow(title: L("It did happen?"), hint: L("Record it as done with the times it had."), actionTitle: L("They came"), icon: "badge-check", action: onRecordPast)
            }
            if when == "past", let onNoShow {
                SchedWayRow(title: L("They never came?"), hint: L("Mark it a no-show and the day is closed."), actionTitle: L("They didn’t come"), icon: "circle-slash", action: onNoShow)
            }
            if let hours { SchedHoursWarning(problem: hours, confirmed: $outside) }
            SchedConflictWarning(conflicts: conflicts, confirmed: $confirmed)
        }
    }

    /// One side of the move: the booked day, and today (in blue).
    private func dayBox(_ label: String, _ day: String, _ time: String, moving: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(Theme.text(11.2, weight: .heavy)).tracking(1.1).foregroundStyle(moving ? Theme.blue : Theme.inkSoft)
            Text(day).font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.inkStrong)
            Text(time).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(moving ? Theme.surface : Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(moving ? Theme.blue : Theme.borderSoft, lineWidth: moving ? 2 : 1))
    }

    private func move() {
        guard !waits else {
            Toast.error(L("Confirm the warning below to move it anyway."))
            return
        }
        var body: [String: Any?] = ["startsAt": DateText.iso(target.start), "endsAt": DateText.iso(target.end)]
        if outside { body["outsideHours"] = true }
        if confirmed { body["allowDoubleBooking"] = true }
        working = true
        Task {
            defer { working = false }
            do {
                let _: SchedAppointment = try await SchedAPI.send("PATCH", "/provider-appointments/\(appointment.id)", body: body)
                announceDataChanged()
                Toast.show(LF("Moved to today. Now check %@ in.", appointment.petName))
                onMoved()
            } catch let failure as SchedFailure {
                if let taken = failure.conflicts { conflicts = taken; confirmed = false; Toast.error(failure.api.message) }
                else if let problem = failure.hoursProblem { hours = problem; outside = false; Toast.error(failure.api.message) }
                else { schedToast(failure) }
            } catch { schedToast(error) }
        }
    }
}

// MARK: - The charge choice ("Terminar" and "Sí vino")

enum SchedChargeMode: String, Hashable {
    case desk, collect, price, noCharge

    static func modes(pay: Bool, price: Bool, waive: Bool, collects: Bool, billReady: Bool?) -> [SchedChargeMode] {
        var modes: [SchedChargeMode] = [.desk]
        if collects && pay && billReady != false { modes.append(.collect) }
        if collects && price && billReady != true { modes.append(.price) }
        if waive { modes.append(.noCharge) }
        return modes
    }

    func actionTitle(record: Bool, signs: Bool = false) -> String {
        if record {
            switch self {
            case .collect: return L("Record and charge")
            case .price: return L("Record and price it")
            case .noCharge: return L("Record, no charge")
            case .desk: return L("Record and send to the desk")
            }
        }
        if signs {
            switch self {
            case .collect: return L("Finish, sign and charge")
            case .price: return L("Finish, sign and price it")
            case .noCharge: return L("Finish and sign")
            case .desk: return L("Finish, sign and send to the desk")
            }
        }
        switch self {
        case .collect: return L("Finish and charge")
        case .price: return L("Finish and price it")
        case .noCharge: return L("Finish, no charge")
        case .desk: return L("Finish and send to the desk")
        }
    }

    /// What happened to the bill, from the move's answer: the toast's second sentence.
    func outcome(_ bill: SchedMoveBill?) -> String {
        switch self {
        case .noCharge: return L("No charge.")
        case .collect: return L("Its bill is open to charge.")
        case .price: return L("Its bill is open to put the price.")
        case .desk:
            guard let bill else { return L("The front desk has it to charge.") }
            if bill.status == "paid" { return L("Nothing to charge.") }
            if bill.status == "draft" { return L("The bill waits for a price before it is charged.") }
            return L("The bill went to the front desk to charge.")
        }
    }

    func body(reason: String) -> [String: Any?] {
        self == .noCharge ? ["noCharge": true, "noChargeReason": reason.nonEmpty] : ["noCharge": false]
    }
}

/// The charge part of "Terminar" and "Sí vino": one look, one set of rules.
struct SchedChargeChoice: View {
    let modes: [SchedChargeMode]
    @Binding var mode: SchedChargeMode
    @Binding var reason: String
    let invoice: SchedInvoice?
    @ObservedObject var form: FormState

    var body: some View {
        ModalSection(title: L("Charges")) {
            // The web's choice cards: each way with its icon and colour.
            OptionCards(options: modes.map { OptionCard($0, title: title($0), description: hint($0), icon: icon($0), accent: accent($0)) }, selection: $mode)
            if mode == .noCharge {
                PMTextField(L("Why no charge"), text: $reason, key: "noChargeReason", form: form, prompt: L("e.g. Recheck included, a rescue"), hint: L("The owner sees why on the day’s exceptions."))
            }
        }
    }

    private func title(_ mode: SchedChargeMode) -> String {
        switch mode {
        case .desk: L("Send to the front desk to pay")
        case .collect: L("Charge now")
        case .price: L("Put the price myself")
        case .noCharge: L("No charge")
        }
    }

    private func icon(_ mode: SchedChargeMode) -> String {
        switch mode {
        case .desk: "send"
        case .collect: "hand-coins"
        case .price: "tag"
        case .noCharge: "circle-slash"
        }
    }

    /// The web's tones: the desk mango while the bill still needs a price (someone else finishes it).
    private func accent(_ mode: SchedChargeMode) -> Color {
        let lines = invoice?.lineItems ?? []
        let notReady = (invoice != nil && lines.isEmpty) || lines.contains(where: \.needsPrice)
        switch mode {
        case .desk: return notReady ? Theme.mango : Theme.aqua
        case .collect: return Theme.pink
        case .price: return Theme.mango
        case .noCharge: return Theme.aqua
        }
    }

    private func hint(_ mode: SchedChargeMode) -> String {
        let lines = invoice?.lineItems ?? []
        let unpriced = lines.filter(\.needsPrice).count
        let currency = invoice?.currency
        let total = invoice?.totalAmount ?? 0
        switch mode {
        case .desk:
            if invoice != nil && lines.isEmpty { return L("No charges on the bill yet. The front desk adds them and sets the price before charging.") }
            if unpriced == 1 { return L("1 line has no price yet. The front desk sets it before charging.") }
            if unpriced > 1 { return LF("%@ lines have no price yet. The front desk sets them before charging.", String(unpriced)) }
            return total > 0 ? LF("The bill so far: %@. The desk can adjust it.", Money.format(total, currency: currency)) : L("The visit’s charges go to the desk; they can adjust them.")
        case .collect:
            return total > 0 ? LF("The payment opens next: %@.", Money.format(total, currency: currency)) : L("The payment opens next.")
        case .price: return L("Its bill opens next. Once every line has a price it goes to the desk by itself.")
        case .noCharge: return L("A courtesy or a warranty recheck. Nothing to pay.")
        }
    }

    /// "No cobrar" without its reason stops before anything is sent.
    static func missingReason(_ mode: SchedChargeMode, _ reason: String) -> String? {
        mode == .noCharge && reason.nonEmpty == nil ? L("Write why it is finished without charging.") : nil
    }

    /// A refusal about not charging, said under the reason; false for any other.
    static func refusal(_ error: Error, form: FormState) -> Bool {
        guard let failure = error as? SchedFailure else { return false }
        let message: String?
        switch failure.code {
        case "reason_required": message = L("Write why it is finished without charging.")
        case "no_charge_paid": message = L("A payment is already on this visit’s bill: give it back before finishing without charging.")
        case "no_charge_forbidden": message = L("You can’t finish a visit without charging. Send it to the desk instead.")
        default: message = nil
        }
        guard let message else { return false }
        _ = form.check([("noChargeReason", message)])
        return true
    }
}

// MARK: - "¿Cuándo vuelve?"

struct SchedComeBack: Equatable {
    /// "none", a preset's id, or "date".
    var choice = "none"
    var date = Date()
    var remindFamily = true
    var touched = false

    struct Preset { let id: String; let label: String; let weeks: Int?; let months: Int? }

    static func presets(_ category: String?) -> [Preset] {
        func w(_ n: Int, _ label: String) -> Preset { Preset(id: "w\(n)", label: label, weeks: n, months: nil) }
        func m(_ n: Int, _ label: String) -> Preset { Preset(id: "m\(n)", label: label, weeks: nil, months: n) }
        if category == "groomer" { return [w(4, L("In 4 weeks")), w(6, L("In 6 weeks")), w(8, L("In 8 weeks")), w(10, L("In 10 weeks"))] }
        if category == nil || category == "vet" || category == "emergency" {
            return [w(1, L("In 1 week")), w(2, L("In 2 weeks")), w(3, L("In 3 weeks")), m(1, L("In 1 month")), m(3, L("In 3 months")), m(6, L("In 6 months")), m(12, L("In 1 year"))]
        }
        return [w(2, L("In 2 weeks")), m(1, L("In 1 month")), m(3, L("In 3 months")), m(6, L("In 6 months"))]
    }

    /// Walks, sitting, classes, daycare and boarding repeat instead.
    static func asks(_ category: String?) -> Bool {
        !["walker", "sitter", "trainer", "daycare", "boarding", "pharmacy"].contains(category ?? "")
    }

    struct Resolved { let target: String; let on: String; let moved: Bool; let noneOpen: Bool; let weeks: Int; let noticeAhead: Bool }

    func resolve(category: String?, availability: SchedAvailability?, closures: [SchedClosure]) -> Resolved? {
        guard choice != "none" else { return nil }
        let today = SchedDay.today
        let base = SchedDay.start(today)
        let preset = Self.presets(category).first { $0.id == choice }
        let target: String
        if let preset {
            let date = preset.weeks.map { SchedDay.calendar.date(byAdding: .day, value: $0 * 7, to: base) } ?? SchedDay.calendar.date(byAdding: .month, value: preset.months ?? 1, to: base)
            target = SchedDay.key(date ?? base)
        } else {
            target = SchedDay.key(date)
        }
        let tomorrow = SchedDay.addDays(today, 1)
        let open = SchedHours.nearestOpenDay(target, closures: closures, availability: availability, notBefore: tomorrow)
        let on = open ?? target
        let days = SchedDay.calendar.dateComponents([.day], from: base, to: SchedDay.start(on)).day ?? 0
        let weeks = preset?.weeks ?? (preset?.months.map { Int((Double($0) * 30.44 / 7).rounded()) } ?? min(52, max(1, Int((Double(days) / 7).rounded()))))
        return Resolved(target: target, on: on, moved: open != nil && open != target, noneOpen: open == nil, weeks: weeks, noticeAhead: days >= 9)
    }

    /// What the finish sends: a day, null ("No need" chosen on purpose), or nothing (leave it out).
    func input(category: String?, availability: SchedAvailability?, closures: [SchedClosure], familyOnApp: Bool) -> Any?? {
        guard let resolved = resolve(category: category, availability: availability, closures: closures) else {
            return touched && choice == "none" ? .some(nil) : .none
        }
        let body: [String: Any?] = [
            "on": resolved.on,
            "weeks": category == "groomer" ? resolved.weeks : nil,
            "remindFamily": category != "groomer" && familyOnApp && remindFamily && resolved.noticeAhead,
        ]
        return .some(body)
    }
}

struct SchedComeBackFields: View {
    @Binding var value: SchedComeBack
    let category: String?
    let availability: SchedAvailability?
    let closures: [SchedClosure]
    let familyOnApp: Bool
    let clientName: String
    var alsoFor: [String] = []

    var body: some View {
        let resolved = value.resolve(category: category, availability: availability, closures: closures)
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: L("No need"), isSelected: value.choice == "none") { pick("none") }
                    ForEach(SchedComeBack.presets(category), id: \.id) { preset in
                        FilterChip(title: preset.label, isSelected: value.choice == preset.id) { pick(preset.id) }
                    }
                    FilterChip(title: L("Another day…"), isSelected: value.choice == "date") { pick("date") }
                }
                .padding(.vertical, 2)
            }
            if value.choice == "date" {
                DateTimeField(label: L("Choose a day"), date: Binding(get: { value.date }, set: { value.date = $0; value.touched = true }), zone: SchedDay.zone,
                              min: Date().addingTimeInterval(86_400), components: [.date])
            }
            if let resolved {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Glyph(resolved.moved ? "calendar-x" : "calendar-check", size: 16).foregroundStyle(resolved.moved ? Theme.mango : Theme.blue).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sentence(resolved)).font(Theme.text(15, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                            Text(category == "groomer"
                                 ? L("It becomes this pet’s grooming rhythm: Due shows them when it’s time.")
                                 : resolved.noticeAhead
                                    ? L("It goes to Due with this service. You get a notice a week before, and again if nothing is booked 3 days after.")
                                    : L("It goes to Due with this service. You get a notice if nothing is booked 3 days after."))
                                .font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    if category != "groomer" {
                        if !resolved.noticeAhead {
                            Text(LF("It’s within a week: tell %@ now, before they leave.", clientName)).font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
                        } else if familyOnApp {
                            ToggleRow(title: LF("Remind %@ a week before", clientName), subtitle: L("Once, in PawMiaw, with a button to pick a time. Not if it’s already booked."), isOn: $value.remindFamily)
                        } else {
                            Text(LF("%@ isn’t on PawMiaw: remind them by WhatsApp from Due.", clientName)).font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            }
        }
    }

    private func pick(_ choice: String) {
        value.choice = choice
        value.touched = true
    }

    private func sentence(_ resolved: SchedComeBack.Resolved) -> String {
        var text = resolved.moved
            ? LF("%@ is closed: it comes back on %@.", SchedDay.shortLabel(resolved.target), SchedDay.shortLabel(resolved.on))
            : LF("Comes back on %@.", SchedDay.shortLabel(resolved.on))
        if resolved.noneOpen { text += " " + L("Nothing is open around that day; pick the day when booking.") }
        if !alsoFor.isEmpty { text += " " + LF("Also for %@.", alsoFor.joined(separator: ", ")) }
        return text
    }
}

// MARK: - Finish ("Terminar")

/// The visit page's (and Home's) "Terminar": the one finish sheet (Services' SvcFinishSheet), with what
/// the page already knows — the drafts and who signs, the bill, and where the charge goes next.
struct SchedFinishSheet: View {
    let appointment: SchedAppointment
    let drafts: Int
    let signed: Int
    let invoice: SchedInvoice?
    /// The person finishing, when they can sign (owner, admin, vet).
    let signer: (memberId: String, name: String)?
    /// The bill can be opened from here to charge or to price it.
    let collects: Bool
    /// After finishing with "Charge now" or "Put the price myself".
    let onAfter: (SchedChargeMode) -> Void
    /// Left open since an earlier day: "Sí vino" instead.
    var onEarlierDay: (() -> Void)? = nil

    var body: some View {
        let a = appointment
        SvcFinishSheet(
            target: SvcFinishTarget(id: a.id, petName: a.petName, serviceLabel: a.serviceLabel, serviceCategory: a.serviceCategory,
                                    clientName: a.clientName, familyOnApp: a.clientHouseholdId != nil,
                                    assignedId: a.assignedMember?.id, assignedName: a.assignedMember?.name,
                                    together: a.togetherPets.compactMap(\.name), locationId: a.locationId),
            onFinished: {},
            prepare: a.atHome == true ? { ["at": DateText.iso(Date())] } : nil,
            invoice: invoice,
            known: SvcFinishKnown(drafts: drafts, signed: signed, signer: signer),
            collects: collects,
            onAfter: onAfter,
            onEarlierDay: onEarlierDay
        )
    }
}

// MARK: - "Sí vino"

/// Records a visit nobody closed on its day as done, with the times it had (the last 30 days).
struct SchedRecordPastSheet: View {
    let appointment: SchedAppointment
    let invoice: SchedInvoice?
    let collects: Bool
    let onAfter: (SchedChargeMode) -> Void

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var start = 9 * 60
    @State private var end = 9 * 60 + 30
    @State private var mode: SchedChargeMode = .desk
    @State private var reason = ""
    @State private var working = false
    @State private var prepared = false

    private var zone: TimeZone { SchedData.zone(of: appointment.locationId) }
    private var day: String { appointment.start.map { SchedDay.key($0, zone: zone) } ?? SchedDay.today }
    private var quarters: [Int] { Array(stride(from: 0, to: 1440, by: 15)) }
    private func at(_ minute: Int) -> Date { SchedDay.at(day, minute: min(minute, 1439), zone: zone) }
    private var problem: String? {
        if end <= start { return L("The end must be after the start.") }
        if at(end) > Date() { return L("The end can't be later than now") }
        return nil
    }
    private var modes: [SchedChargeMode] {
        let ready: Bool? = invoice.map { lines in !(lines.lineItems ?? []).isEmpty && !(lines.lineItems ?? []).contains(where: \.needsPrice) }
        return SchedChargeMode.modes(pay: workspace.can(.billingRecordPayment), price: workspace.can(.billingEditInvoice), waive: workspace.can(.billingWaiveVisit), collects: collects, billReady: ready)
    }

    var body: some View {
        ProviderModal(title: LF("%@ came on %@", appointment.petName, DateText.day(appointment.start)), subtitle: "\(appointment.serviceLabel) · \(appointment.clientName)", systemImage: "badge-check", accent: .blue, isDirty: !reason.isEmpty, form: form, primaryTitle: mode.actionTitle(record: true), isWorking: working, cancelTitle: L("Back"), primaryIcon: "badge-check") {
            submit()
        } content: {
            if let answer = appointment.familyAttendance {
                Text(answer == "attended" ? L("The family says they went.") : L("The family says they didn’t go."))
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            }
            Text(L("Nobody closed this visit that day. Say when it really was: its bill opens and the family sees it in the history."))
                .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
            HStack(alignment: .top, spacing: 12) {
                MenuField(label: L("Started"), options: quarters.map { ($0, DateText.time(at($0), zone: zone)) }, selection: Binding(get: { start }, set: { value in
                    let length = max(15, end - start)
                    start = value
                    end = min(1439, value + length)
                }))
                MenuField(label: L("Ended"), options: (quarters.filter { $0 > start } + [1439]).map { ($0, DateText.time(at($0), zone: zone)) }, selection: $end)
            }
            if let problem { Text(problem).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.destructive) }
            SchedChargeChoice(modes: modes, mode: $mode, reason: $reason, invoice: invoice, form: form)
        }
        .onAppear {
            guard !prepared else { return }
            prepared = true
            let booked = DateText.parse(appointment.startedAt ?? appointment.startsAt) ?? Date()
            let minute = Int((Double(SchedDay.minuteOfDay(booked, zone: zone)) / 15).rounded()) * 15
            start = min(1425, minute)
            end = min(1439, start + max(15, Int((Double(appointment.lengthMinutes) / 15).rounded()) * 15))
        }
    }

    private func submit() {
        if let problem { Toast.error(problem); return }
        guard form.check([("noChargeReason", SchedChargeChoice.missingReason(mode, reason))]) else { return }
        var body = mode.body(reason: reason)
        body["startedAt"] = DateText.iso(at(start))
        body["finishedAt"] = DateText.iso(at(end))
        let chosen = mode, pet = appointment.petName, id = appointment.id
        working = true
        Task {
            defer { working = false }
            do {
                let result: SchedMoveResponse = try await SchedAPI.send("POST", "/provider-appointments/\(id)/record-past", body: body)
                announceDataChanged()
                Toast.show("\(LF("Recorded. %@’s family will see it in the history.", pet)) \(chosen.outcome(result.bill))")
                dismiss()
                if chosen == .collect || chosen == .price { onAfter(chosen) }
            } catch {
                if SchedChargeChoice.refusal(error, form: form) { return }
                schedToast(error)
            }
        }
    }
}

// MARK: - No-show and cancel (with the fee choice)

/// "Didn't come" and cancelling — a visit, or a pet taken out of a session — with the reason and the
/// fee when the server asks for a decision; a family's other pets booked with it go too unless only
/// this one is chosen. The visit page, Home and Paseos y clases use it.
struct SchedMissedSheet: View {
    let appointmentId: String
    let petName: String
    let clientName: String
    let subtitle: String
    /// "no_show" or "cancel".
    let mode: String
    /// The family's other pets booked with it.
    var together: [String] = []
    /// The toast once cancelled ("Visit cancelled.", or a session's "Taken out. The place is open.").
    var cancelledText: String = L("Visit cancelled.")
    var onDone: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var reason = ""
    @State private var fee: SchedFeeRequired?
    @State private var decision = "charge"
    @State private var feeNote = ""
    @State private var onlyThisPet = false
    @State private var working = false

    init(appointment: SchedAppointment, mode: String) {
        let when = SchedDay.key(appointment.startsAt) == SchedDay.today ? DateText.time(appointment.start) : DateText.dayTime(appointment.start)
        self.init(appointmentId: appointment.id, petName: appointment.petName, clientName: appointment.clientName,
                  subtitle: "\(appointment.serviceLabel) · \(when) · \(appointment.clientName)", mode: mode,
                  together: appointment.togetherPets.compactMap(\.name))
    }

    init(appointmentId: String, petName: String, clientName: String, subtitle: String, mode: String, together: [String] = [],
         cancelledText: String = L("Visit cancelled."), onDone: @escaping () -> Void = {}) {
        self.appointmentId = appointmentId
        self.petName = petName
        self.clientName = clientName
        self.subtitle = subtitle
        self.mode = mode
        self.together = together
        self.cancelledText = cancelledText
        self.onDone = onDone
    }

    var body: some View {
        ProviderModal(title: mode == "no_show" ? LF("%@ didn’t come", petName) : L("Cancel the visit"), subtitle: subtitle, systemImage: mode == "no_show" ? "circle-slash" : "calendar-x-2", accent: .pink, isDirty: !reason.isEmpty || !feeNote.isEmpty, form: form, primaryTitle: mode == "no_show" ? L("Mark no-show") : L("Cancel visit"), primaryVariant: .destructive, isWorking: working, cancelTitle: L("Back")) {
            submit()
        } content: {
            if !together.isEmpty {
                OptionCards(options: [
                    OptionCard(false, title: L("The whole family"), description: schedNames([petName] + together), icon: "users", accent: Theme.pink),
                    OptionCard(true, title: L("Only this pet"), description: L("The others stay as they are."), icon: "circle-slash", accent: Theme.pink),
                ], selection: $onlyThisPet)
            }
            if mode == "cancel" {
                ModalSection(title: L("Why"), required: true) {
                    SchedBareField(prompt: L("The family called, the pet is sick…"), text: $reason, key: "reason", form: form)
                }
            } else {
                Text(L("The visit stays in the history as a no-show. You can rebook it later.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            if let fee {
                let amount = Money.format(fee.amount, currency: fee.currency)
                ModalSection(title: fee.kind == "no_show" ? L("No-show fee") : L("Late cancellation fee"), subtitle: LF("You decide: charge %@ to their account, or waive it.", amount)) {
                    OptionCards(options: [
                        OptionCard("charge", title: LF("Charge %@", amount), description: L("It goes on their account to collect."), icon: "hand-coins", accent: Theme.mango),
                        OptionCard("waive", title: L("Waive it"), description: L("Nothing is charged; the reason is kept."), icon: "badge-check", accent: Theme.aqua),
                    ], selection: $decision)
                    if decision == "waive" {
                        SchedBareField(prompt: L("Why it is waived (first time, emergency…)"), text: $feeNote, key: "feeNote", form: form, multiline: false)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() {
        guard form.check([
            ("reason", mode == "cancel" && reason.nonEmpty == nil ? L("Say why the visit is cancelled") : nil),
            ("feeNote", fee != nil && decision == "waive" && feeNote.nonEmpty == nil ? L("Say why the fee is waived") : nil),
        ]) else { return }
        var body: [String: Any?] = [:]
        if fee != nil { body["fee"] = ["decision": decision, "note": feeNote.nonEmpty] as [String: Any?] }
        if !together.isEmpty { body["onlyThisPet"] = onlyThisPet }
        if mode == "cancel" { body["reason"] = reason.nonEmpty }
        let path = mode == "no_show" ? "no-show" : "cancel"
        working = true
        Task {
            defer { working = false }
            do {
                let result: SchedMoveResponse = try await SchedAPI.send("POST", "/provider-appointments/\(appointmentId)/\(path)", body: body)
                announceDataChanged()
                Toast.show(result.feeInvoiceId != nil
                           ? LF("Done. The fee is on %@’s account.", clientName)
                           : mode == "no_show" ? LF("%@ marked as no-show.", petName) : cancelledText)
                onDone()
                dismiss()
            } catch {
                if let wanted = (error as? SchedFailure)?.fee {
                    fee = wanted
                    Toast.show(L("Decide about the fee, then confirm."))
                    return
                }
                form.apply(schedAPIError(error), known: ["reason": "reason", "fee.note": "feeNote"])
            }
        }
    }
}

// MARK: - Book again

struct SchedRebookSheet: View {
    let appointment: SchedAppointment

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var day = Date().addingTimeInterval(86_400)
    @State private var minute = 10 * 60
    @State private var length = 30
    @State private var outside = false
    @State private var conflicts: [SchedConflict] = []
    @State private var confirmed = false
    @State private var hours: SchedHoursProblem?
    @State private var working = false
    @State private var prepared = false

    private let lengths = [15, 30, 45, 60, 90, 120]

    var body: some View {
        ProviderModal(title: LF("Book %@ again", appointment.petName), subtitle: appointment.serviceLabel, systemImage: "calendar-clock", accent: .aqua, form: form, primaryTitle: L("Book again"), isWorking: working, cancelTitle: L("Back")) {
            submit()
        } content: {
            DateTimeField(label: L("Day"), date: $day, zone: SchedDay.zone, min: Date(), components: [.date])
            HStack(alignment: .top, spacing: 12) {
                MenuField(label: L("Time"), options: stride(from: 0, to: 1440, by: 15).map { ($0, SchedDay.timeLabel($0)) }, selection: $minute, key: "startsAt", form: form)
                MenuField(label: L("Length"), options: lengths.map { ($0, LF("%@ min", String($0))) }, selection: $length)
            }
            ToggleRow(title: L("Outside opening hours"), isOn: $outside)
            if let hours { SchedHoursWarning(problem: hours, confirmed: $outside) }
            SchedConflictWarning(conflicts: conflicts, confirmed: $confirmed)
        }
        .onAppear {
            guard !prepared else { return }
            prepared = true
            if let start = appointment.start { minute = SchedDay.minuteOfDay(start) / 15 * 15 }
            length = lengths.contains(appointment.lengthMinutes) ? appointment.lengthMinutes : 30
        }
        .onChange(of: day) { _, _ in resetWarnings() }
        .onChange(of: minute) { _, _ in resetWarnings() }
        .onChange(of: length) { _, _ in resetWarnings() }
    }

    private func resetWarnings() {
        conflicts = []
        confirmed = false
        hours = nil
    }

    private func submit() {
        if !conflicts.isEmpty && !confirmed {
            Toast.error(L("Double booking — read the warning and confirm to book anyway."))
            return
        }
        let start = SchedDay.at(SchedDay.key(day), minute: minute)
        let end = start.addingTimeInterval(TimeInterval(length * 60))
        let body: [String: Any?] = ["startsAt": DateText.iso(start), "endsAt": DateText.iso(end), "outsideHours": outside, "allowDoubleBooking": confirmed]
        working = true
        Task {
            defer { working = false }
            do {
                let _: SchedMoveResponse = try await SchedAPI.send("POST", "/provider-appointments/\(appointment.id)/rebook", body: body)
                announceDataChanged()
                Toast.show(LF("Booked again: %@", DateText.dayTime(start)))
                dismiss()
            } catch let failure as SchedFailure {
                if failure.code == "start_in_past" {
                    _ = form.check([("startsAt", failure.api.field("startsAt") ?? failure.api.message)])
                } else if let taken = failure.conflicts {
                    conflicts = taken
                    confirmed = false
                    Toast.error(failure.api.message)
                } else if let problem = failure.hoursProblem {
                    hours = problem
                    outside = false
                    Toast.error(failure.api.message)
                } else {
                    schedToast(failure)
                }
            } catch { schedToast(error) }
        }
    }
}
