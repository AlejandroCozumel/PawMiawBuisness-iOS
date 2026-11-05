//
//  SchedBookingSheet.swift
//  PawMiawNegocios
//
//  Booking a visit, editing (moving) one, or a walk-in ("Sin cita") — the
//  web's provider-appointment-sheet.tsx in three steps: the client and the
//  pet (several of a family booked together), the service from the catalog,
//  then the details — the person, the day, the start times the day's hours
//  leave (taken ones marked), "Outside opening hours", the room, the
//  family's confirmation and notes. A double booking or a time outside the
//  hours is booked only once confirmed, as the server's rule.
//

import SwiftUI

struct SchedBookingDraft: Identifiable {
    enum Mode { case appointment, walkIn }

    let id = UUID()
    var mode: Mode = .appointment
    /// Editing (moving) this visit.
    var appointment: SchedAppointment? = nil
    var day: String? = nil
    var startMinute: Int? = nil
    var durationMinutes: Int? = nil
    var memberId: String? = nil
    var roomId: String? = nil
    var clientId: String? = nil
    var petId: String? = nil
    /// The catalog service to book (a prefill).
    var serviceId: String? = nil
    var notes: String? = nil
    /// The Due list's follow-up this visit answers: tied to it once booked.
    var followUpId: String? = nil
}

struct SchedBookingSheet: View {
    let draft: SchedBookingDraft
    /// A walk-in that starts, stopped by a consent or a deposit: shown once this sheet is gone.
    var onGate: (SchedGatePrompt) -> Void = { _ in }
    /// A new visit booked (the first of a repeating one), before the sheet closes.
    var onBooked: ((SchedAppointment) async -> Void)? = nil
    /// Shown as a page (`BookVisitScreen`): a gate opens over it instead of closing it first.
    var staysOnGate = false

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()

    @State private var step = 0
    @State private var client: SchedClient?
    @State private var petIds: [String] = []
    @State private var catalog: SchedCatalog?
    @State private var category = ""
    @State private var serviceId = ""
    @State private var serviceLabel = ""
    @State private var labelFromService = true
    @State private var date = Date()
    @State private var assignee = ""
    @State private var duration = 30
    @State private var startMinute: Int?
    @State private var slotTouched = false
    @State private var afterHours = false
    @State private var roomId: String?
    @State private var roomTouched = false
    @State private var notes = ""
    @State private var requestConfirmation = true
    @State private var doubleBookConfirmed = false
    @State private var serverConflicts: [SchedConflict]?
    @State private var serverHours: SchedHoursProblem?
    @State private var hoursConfirmed = false
    @State private var togetherConfirmed = false
    @State private var walkInStart = false
    @State private var walkInWeight = ""
    @State private var walkInRequestId = schedRequestId()
    @State private var members: [SchedMember] = []
    @State private var availability: SchedAvailability?
    @State private var closures: [SchedClosure] = []
    @State private var load: SchedLoad?
    @State private var loadingDay = false
    @State private var prepared = false
    @State private var working = false
    @State private var repeatDraft = SchedRepeatDraft()
    @State private var groomRequests: [String: SchedGroomInput] = [:]
    @State private var atClientHome = false
    @State private var serviceAddressId: String?
    @State private var accessNotes = ""
    @State private var addressError: String?
    @State private var walkInTriage = SchedTriageDraft()
    @State private var triageInvalid: SchedTriageDraft.Missing?

    private static let durations = Array(stride(from: 15, through: 180, by: 15))

    private var editing: SchedAppointment? { draft.appointment }
    private var walkIn: Bool { draft.mode == .walkIn }
    private var canAssignAnyone: Bool { workspace.can(.appointmentsAssignAnyone) }
    private var locationId: String? { editing?.locationId ?? workspace.locationId }
    private var dayKey: String { SchedDay.key(date) }
    private var me: SchedMember? { members.first(where: \.isMe) }
    private var pets: [SchedClientPet] { client?.bookablePets ?? [] }
    private var petId: String? { petIds.first }
    private var extraPetIds: [String] { Array(petIds.dropFirst()) }
    private var canBookTogether: Bool { editing == nil && !walkIn && pets.count > 1 }
    private var services: [SchedCatalogService] {
        (catalog?.services ?? []).filter { ($0.id != "group_walk" && $0.id != "group_class") || $0.id == editing?.serviceId }
    }
    private var categories: [SchedCatalogCategory] { catalog?.categories ?? [] }
    private var service: SchedCatalogService? { services.first { $0.id == serviceId } }
    private var serviceOptional: Bool { editing != nil && editing?.serviceId == nil }
    private var homeService: Bool { service?.isHome ?? (category == "walker" || category == "sitter") }
    /// Any other service can be made at home too: the switch says so (web lib/visit-repeat.ts `offersAtClientHome`).
    private var canBeAtClientHome: Bool { editing == nil && !walkIn && !homeService && ["vet", "groomer", "trainer", "other"].contains(category) }
    private var homeVisit: Bool { !walkIn && (homeService || (canBeAtClientHome && atClientHome)) }
    /// A new home visit asks where it happens.
    private var askAddress: Bool { homeVisit && editing == nil }
    /// Grooming: what the owner asked for, one per pet booked.
    private var groomBooking: Bool { editing == nil && !walkIn && category == "groomer" }
    /// An emergency walk-in at a clinic is triaged as it comes in.
    private var walkInVetCare: Bool { walkIn && workspace.offers(.vet, .emergency) }
    private var bookedPets: [(id: String, name: String)] { petIds.compactMap { id in pets.first { $0.id == id }.map { (id, $0.petName) } } }
    private var clientHasEmail: Bool { client?.ownerEmail?.nonEmpty != nil }

    var body: some View {
        ProviderModal(
            title: walkIn ? L("Walk-in") : (editing != nil ? L("Edit appointment") : L("Add appointment")),
            subtitle: walkIn ? L("Here now without an appointment, or an emergency. They go straight to the waiting room.") : L("Choose the client, the pet, the service and the time."),
            systemImage: walkIn ? "zap" : "calendar-days",
            accent: walkIn ? .pink : .butter,
            isDirty: editing == nil && (client != nil || slotTouched || roomTouched),
            form: form,
            primaryTitle: primaryTitle,
            isWorking: working,
            steps: ModalSteps(steps: [(L("Client"), "user-round"), (L("Service"), "clipboard-list"), walkIn ? (L("Walk-in"), "zap") : (L("Appointment"), "calendar-days")], current: step),
            onBack: step > 0 ? { step -= 1 } : nil,
            onPrimary: { primary() }
        ) {
            if step > 0 {
                HStack(spacing: 10) {
                    if let client {
                        Avatar(name: client.ownerName, imageURL: client.photoUrl, size: 30)
                        Text([client.ownerName, petNames].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                            .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    }
                }
            }
            switch step {
            case 0: selectionStep
            case 1: serviceStep
            default: detailsStep
            }
        }
        .presentationDetents([.large])
        .task { await prepare() }
        .task(id: "\(dayKey)|\(step)") { await loadDay() }
        .onChange(of: assignee) { _, _ in resetChecks() }
        .onChange(of: duration) { _, _ in resetChecks() }
        .onChange(of: startMinute) { _, _ in resetChecks() }
        .onChange(of: roomId) { _, _ in resetChecks() }
        .onChange(of: serviceId) { _, _ in applyService() }
    }

    private var petNames: String? {
        let names = petIds.compactMap { id in pets.first { $0.id == id }?.petName }
        return names.isEmpty ? nil : schedNames(names)
    }

    private var primaryTitle: String {
        switch step {
        case 0, 1: return L("Continue")
        default:
            if walkIn { return walkInStart ? L("Start now") : L("Add to the waiting room") }
            return editing != nil ? L("Save appointment") : L("Add appointment")
        }
    }

    // MARK: Step 1: client and pet

    @ViewBuilder private var selectionStep: some View {
        ModalSection(title: L("Client + pet"), systemImage: "user-round") {
            // The one client-and-pet picker (search from 2 letters, 20 at a time, the chosen one on top).
            ClientPetPicker(
                client: Binding(get: { client.map(SchedClientBridge.picked) }, set: { client = $0.map(SchedClientBridge.sched) }),
                petIds: $petIds,
                pets: canBookTogether ? .several : .one,
                petRequired: true,
                key: "client",
                petKey: "pet",
                form: form,
                petHint: canBookTogether ? L("Tap more than one to book them together: the same time and person, one bill, a report each.") : nil
            )
        }
    }

    // MARK: Step 2: service

    @ViewBuilder private var serviceStep: some View {
        ModalSection(title: L("Service"), systemImage: "paw-print", tint: Theme.butter) {
            if catalog == nil {
                LoadingState(text: L("Loading services…"))
            } else if category.isEmpty || !categories.contains(where: { $0.id == category }) {
                // The web's option cards: each kind of service with its icon and colour.
                FormField(label: L("Service category"), key: "category", form: form, required: true) {
                    OptionCards(options: categories.map {
                        OptionCard($0.id, title: $0.label, description: $0.description, icon: Hue.categoryIcon($0.id), accent: Hue.category($0.id).color)
                    }, selection: Binding(get: { category }, set: { pickCategory($0) }), invalid: form.error("category") != nil)
                }
            } else {
                let meta = categories.first { $0.id == category }
                let options = services.filter { $0.category == category }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        FieldLabel(LF("Services · %@", meta?.label ?? ""), required: true)
                        Spacer(minLength: 8)
                        if categories.count > 1 {
                            PMButton(L("Change"), trailingIcon: "chevron-down", variant: .link, size: .small) { pickCategory("") }
                        }
                    }
                    if let description = meta?.description?.nonEmpty {
                        Text(description).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    }
                    if options.isEmpty {
                        NoticeCard(tone: .info, title: LF("No %@ services are switched on", meta?.label ?? ""), message: workspace.can(.workspaceEdit) ? L("Turn services on in Settings › Services, then book.") : L("Ask an owner or admin to turn services on in Settings."))
                    } else {
                        OptionCards(options: options.map {
                            OptionCard($0.id, title: $0.label, description: $0.description, icon: Hue.categoryIcon(category), accent: Hue.category(category).color)
                        }, selection: Binding(get: { serviceId.nonEmpty }, set: { value in
                            guard let value else { return }
                            serviceId = value
                            form.clear("service")
                            // A short beat on the chosen card before the next step slides in, as the web's confirm blink.
                            Task { try? await Task.sleep(for: .milliseconds(220)); step = 2 }
                        }), invalid: form.error("service") != nil)
                    }
                    if let error = form.error("service") { Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
                }
                .id("service")
            }
        }
    }

    private func pickCategory(_ value: String) {
        category = value
        serviceId = ""
        form.clear("category")
        form.clear("service")
    }

    private func applyService() {
        guard let service else { return }
        if serviceLabel.nonEmpty == nil || labelFromService { serviceLabel = service.label; labelFromService = true }
        // A new booking takes its service's own length, unless one was dragged in or chosen.
        if editing == nil, !walkIn, draft.durationMinutes == nil, !slotTouched, let minutes = service.minutes {
            duration = Self.durations.min(by: { abs($0 - minutes) < abs($1 - minutes) }) ?? duration
        }
    }

    // MARK: Step 3: details

    @ViewBuilder private var detailsStep: some View {
        ModalSection(title: L("Visit details"), systemImage: "calendar-days") {
            PMTextField(L("Visit or service"), text: Binding(get: { serviceLabel }, set: { serviceLabel = $0; labelFromService = false }), key: "serviceLabel", form: form, prompt: service?.label ?? L("e.g. Annual checkup"), required: true)
            if !walkIn {
                DateTimeField(label: L("Date"), date: Binding(get: { date }, set: { changeDate($0) }), zone: SchedDay.zone,
                              min: editing == nil ? SchedDay.start(SchedDay.today) : nil, components: [.date], key: "date", form: form, required: true)
            }
            if canAssignAnyone {
                MenuField(label: L("Assignee"), options: assigneeOptions, selection: $assignee, key: "assignee", form: form, required: true)
            } else {
                FactRow(label: L("Assignee"), value: editing?.assignedMember?.name ?? me.map { LF("%@ (You)", $0.label) } ?? L("You"))
                Text(editing?.assignedMember?.id != nil && editing?.assignedMember?.id != me?.id ? L("Only admins or scheduling staff can reassign this visit.") : L("Your current role books this visit under your own seat."))
                    .font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
            }
            MenuField(label: walkIn ? L("Length") : L("Duration"), options: Self.durations.map { ($0, SchedDay.duration($0)) }, selection: $duration, required: !walkIn)
        }
        if walkIn {
            ModalSection(title: L("Arrival"), systemImage: "zap", tint: Theme.butter) {
                ToggleRow(title: L("Start right away"), subtitle: L("Straight in, without waiting — for an emergency."), isOn: $walkInStart)
                PMTextField(L("Weight (kg)"), text: $walkInWeight, key: "weight", form: form, prompt: "12.4", keyboard: .decimalPad, optional: true)
                if walkInVetCare {
                    SchedTriageFields(draft: $walkInTriage, invalid: triageInvalid)
                        .onChange(of: walkInTriage) { _, _ in triageInvalid = nil }
                }
            }
        } else {
            timeSection
        }
        if canBeAtClientHome {
            ToggleRow(title: L("At the client’s home"), subtitle: L("The visit happens at one of the client’s addresses."), isOn: $atClientHome)
        }
        if !homeVisit {
            MenuField(label: L("Room"), options: roomOptions, selection: Binding(get: { roomId }, set: { roomId = $0; roomTouched = true }), optional: true)
        } else if askAddress, let client {
            ModalSection(title: L("At the client’s home"), systemImage: "house") {
                SchedAddressPicker(clientId: client.id, addressId: Binding(get: { serviceAddressId }, set: { serviceAddressId = $0; addressError = nil }), accessNotes: $accessNotes, error: addressError)
            }
        } else {
            NoticeCard(tone: .info, title: L("At the client’s home"), message: L("It happens at the client’s default address; change it on the visit if it is another one."))
        }
        if groomBooking && !bookedPets.isEmpty {
            SchedBookingGroomRequests(pets: bookedPets, values: $groomRequests, familyOnApp: client?.householdId != nil)
        }
        if let problem = shownHoursProblem, !afterHours {
            SchedHoursWarning(problem: problem, personName: members.first { $0.id == (problem.memberId ?? assignee) }?.label, confirmed: $hoursConfirmed)
        }
        if let together = takenTogether, shownConflicts.isEmpty {
            NoticeCard(tone: .warning, title: LF("%@ takes %@ at once", together.person, String(together.capacity)), message: LF("You are booking %@ together.", schedNames(together.pets)))
            ToggleRow(title: LF("Confirm that %@ takes the %@ pets together.", together.person, String(together.pets.count)), isOn: $togetherConfirmed)
        }
        SchedConflictWarning(conflicts: shownConflicts, confirmed: $doubleBookConfirmed)
        ModalSection(title: walkIn ? L("Why they came") : L("Notes"), systemImage: "notebook-pen", tint: Theme.surfaceMuted) {
            PMTextField(walkIn ? L("Why they came") : L("Notes"), text: $notes, prompt: categories.first { $0.id == category }?.reasonPlaceholder, hint: walkIn ? nil : L("Only your team sees these notes. To tell the family something, send them a note from the visit."), multiline: true)
        }
        // Last: a repeat is decided once the first visit is set. Only walks, sitting, classes and daycare repeat.
        if editing == nil && !walkIn && bookingRepeats {
            ModalSection(title: L("Does this visit repeat?"), systemImage: "repeat", tint: Theme.surfaceMuted) {
                FormField(label: "", key: "repeat", form: form) {
                    SchedRepeatFields(draft: $repeatDraft, firstDay: dayKey, category: category, invalid: form.error("repeat") != nil)
                }
            }
        }
    }

    /// Only a walk, sitting, class or daycare repeats (web lib/visit-repeat.ts).
    private var bookingRepeats: Bool { ["walker", "sitter", "trainer", "daycare"].contains(category) }

    private var assigneeOptions: [(value: String, title: String)] {
        let takers = SchedData.visitTakers(members, locationId: locationId)
        let list = takers.contains(where: { $0.id == assignee }) || assignee.isEmpty ? takers : takers + members.filter { $0.id == assignee }
        let people = list.map { ($0.id, $0.isMe ? LF("%@ (You)", $0.label) : $0.label) }
        return walkIn ? [("", L("Whoever is free"))] + people : (assignee.isEmpty ? [("", L("Choose assignee"))] : []) + people
    }

    private var roomOptions: [(value: String?, title: String)] {
        let rooms = load?.visitRooms ?? []
        let slot = currentSlot
        return [(nil, L("No room"))] + rooms.map { room in
            let free = slot.flatMap { s in load.map { SchedConflicts.roomIsFree(s, room: room, load: $0) } } ?? true
            return (Optional(room.id), free ? room.name : "\(room.name) · \(L("taken"))")
        }
    }

    // MARK: The time

    private var dayHours: (ranges: [SchedRange], closure: (label: String?, closed: Bool)?) {
        SchedHours.day(dayKey, load: load, closures: closures, availability: availability)
    }
    private var openRanges: [SchedMinuteRange] { SchedHours.minutes(dayHours.ranges) }
    private var dayClosed: Bool { !walkIn && openRanges.isEmpty }
    private var nowMinuteFloor: Int { dayKey == SchedDay.today ? SchedDay.minuteOfDay(Date()) : (dayKey < SchedDay.today ? 1440 : -1) }

    private var openStarts: [Int] {
        var starts: [Int] = []
        for range in openRanges {
            var minute = range.start
            while minute + duration <= range.end {
                if minute >= nowMinuteFloor || editing != nil && dayKey < SchedDay.today { starts.append(minute) }
                minute += 15
            }
        }
        return starts
    }

    private var afterHoursStarts: [Int] {
        let first = min(6 * 60, openRanges.map(\.start).min() ?? 6 * 60)
        let last = max(22 * 60, openRanges.map { $0.end - duration }.max() ?? 22 * 60)
        var set = Set<Int>()
        var minute = first / 15 * 15
        while minute <= last {
            if minute >= 0 && minute + duration <= 1440 && minute >= nowMinuteFloor { set.insert(minute) }
            minute += 15
        }
        if let startMinute { set.insert(startMinute) }
        return set.sorted()
    }

    private func slot(at minute: Int) -> SchedSlot {
        let start = SchedDay.at(dayKey, minute: minute)
        return SchedSlot(id: editing?.id, start: start, end: start.addingTimeInterval(TimeInterval(duration * 60)), memberId: assignee.nonEmpty, roomId: nil, pets: groupSeats.pets, together: groupSeats.together, ignoreIds: groupSeats.ignore)
    }

    private var groupSeats: (pets: Int, together: Bool, ignore: [String]) {
        if walkIn { return (1, false, []) }
        if let editing, editing.group?.kind == "household" {
            let others = (editing.group?.stayingPets ?? []).filter { $0.appointmentId != editing.id }.map(\.appointmentId)
            return (1 + others.count, true, others)
        }
        return (1 + extraPetIds.count, !extraPetIds.isEmpty, [])
    }

    private var busyStarts: Set<Int> {
        guard let load else { return [] }
        return Set(openStarts.filter { !SchedConflicts.find(slot(at: $0), load: load).isEmpty })
    }

    private var offStarts: Set<Int> {
        guard let person = load?.people?.first(where: { $0.id == assignee }) else { return [] }
        return Set(openStarts.filter { minute in
            let s = slot(at: minute)
            return SchedHours.personOff(person, start: s.start, end: s.end)
        })
    }

    private var currentSlot: SchedSlot? {
        if walkIn {
            let now = Date()
            return SchedSlot(id: nil, start: now, end: now.addingTimeInterval(TimeInterval(duration * 60)), memberId: assignee.nonEmpty, roomId: roomId)
        }
        guard let startMinute else { return nil }
        var s = slot(at: startMinute)
        s.roomId = roomId
        return s
    }

    private var localConflicts: [SchedConflict] {
        guard let load, let currentSlot else { return [] }
        return SchedConflicts.find(currentSlot, load: load)
    }
    private var shownConflicts: [SchedConflict] { localConflicts.isEmpty ? (serverConflicts ?? []) : localConflicts }

    private var localHoursProblem: SchedHoursProblem? {
        guard !walkIn, let currentSlot else { return nil }
        if let closure = load?.hoursDay(dayKey)?.closure, closure.closed == true {
            return SchedHoursProblem(reason: "closed_date", message: "", closureLabel: closure.label, timeOffReason: nil, memberId: nil)
        }
        guard let person = load?.people?.first(where: { $0.id == assignee }) else { return nil }
        if let off = person.day(dayKey)?.timeOff {
            return SchedHoursProblem(reason: "time_off", message: "", closureLabel: nil, timeOffReason: off.reason, memberId: person.id)
        }
        if person.ownHours == true && SchedHours.personOff(person, start: currentSlot.start, end: currentSlot.end) {
            return SchedHoursProblem(reason: "member_hours", message: "", closureLabel: nil, timeOffReason: nil, memberId: person.id)
        }
        return nil
    }
    private var shownHoursProblem: SchedHoursProblem? { localHoursProblem ?? serverHours }

    /// More of the family's pets than the person takes at once.
    private var takenTogether: (person: String, capacity: Int, pets: [String])? {
        guard !walkIn, editing == nil, !extraPetIds.isEmpty, !assignee.isEmpty, let person = load?.people?.first(where: { $0.id == assignee }) else { return nil }
        let capacity = max(1, person.capacity ?? 1)
        let names = petIds.compactMap { id in pets.first { $0.id == id }?.petName }
        return names.count > capacity ? (person.name ?? "", capacity, names) : nil
    }

    @ViewBuilder private var timeSection: some View {
        ModalSection(title: L("Schedule and confirmation"), systemImage: "clock-3", tint: Theme.butter) {
            if let closure = dayHours.closure, !closure.closed, !openRanges.isEmpty {
                Text("\(closure.label.map { LF("Special hours · %@", $0) } ?? L("Special hours")) · \(SchedHours.rangesText(dayHours.ranges))").font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
            } else if !openRanges.isEmpty {
                Text(LF("Hours this day: %@", SchedHours.rangesText(dayHours.ranges))).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
            }
            if (dayClosed || (openStarts.isEmpty && !loadingDay && !assignee.isEmpty)) && !afterHours {
                let next = SchedHours.nextOpenDay(after: dayKey, closures: closures, availability: availability)
                let title: String = !dayClosed
                    ? (openRanges.allSatisfy { SchedDay.at(dayKey, minute: min($0.end, 1439)) <= Date() } ? L("Opening hours have ended for this day.") : L("No remaining start times fit this visit."))
                    : (dayHours.closure?.label.map { LF("The clinic is closed on %@ · %@", SchedDay.shortLabel(dayKey), $0) } ?? LF("The clinic is closed on %@", SchedDay.shortLabel(dayKey)))
                NoticeCard(tone: .warning, title: title, message: next == nil ? L("No open day in the next months.") : nil, actionTitle: next.map { LF("Go to %@", SchedDay.shortLabel($0)) }, action: next.map { day in { changeDate(SchedDay.date(fromKey: day)) } })
            }
            if loadingDay && load == nil {
                ProgressView().frame(maxWidth: .infinity)
            } else if afterHours {
                MenuField(label: L("Start time"), options: afterHoursStarts.map { ($0, slotLabel($0, inHours: SchedHours.fits($0, $0 + duration, openRanges))) }, selection: startBinding, key: "startTime", form: form)
            } else if !openStarts.isEmpty {
                MenuField(label: L("Available start time"), options: openStarts.map { ($0, slotLabel($0, inHours: true)) }, selection: startBinding, key: "startTime", form: form)
                Text(summaryText).font(Theme.captionFont).foregroundStyle(busyStarts.count == openStarts.count ? Theme.coralText : Theme.inkSoft)
            }
            if let startMinute {
                Text(LF("Ends at %@", SchedDay.timeLabel(min(startMinute + duration, 1439)))).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
            }
            ToggleRow(title: L("Outside opening hours"), subtitle: L("Any time, for an emergency or a special case. It is noted on the visit."), isOn: $afterHours)
            if editing == nil {
                ToggleRow(title: L("Request client confirmation"), subtitle: clientHasEmail ? L("Send an email and app notification after this appointment is created.") : L("Add a client email before sending confirmation requests."), isOn: Binding(get: { requestConfirmation && clientHasEmail }, set: { requestConfirmation = $0 }))
                    .disabled(!clientHasEmail)
            }
        }
    }

    private var startBinding: Binding<Int?> {
        Binding(get: { startMinute }, set: { value in
            startMinute = value
            slotTouched = true
            form.clear("startTime")
        })
    }

    private func slotLabel(_ minute: Int, inHours: Bool) -> String {
        var text = LF("%@ · ends %@", SchedDay.timeLabel(minute), SchedDay.timeLabel(min(minute + duration, 1439)))
        if afterHours && !inHours { text += " · " + L("Outside opening hours").lowercased() }
        if busyStarts.contains(minute) { text += " · " + L("taken") } else if offStarts.contains(minute) { text += " · " + L("not working") }
        return text
    }

    private var summaryText: String {
        let busy = busyStarts.count, all = openStarts.count
        var text = busy == all && all > 0 ? L("Every start time this day is taken — choose one to double book, or another day.")
            : busy > 0 ? LF("%@ free · %@ taken (marked)", String(all - busy), String(busy))
            : LF("%@ free start times", String(all))
        if let buffer = load?.bufferMinutes ?? availability?.defaultBufferMinutes, buffer > 0 {
            text += LF(" · includes %@ buffer after each visit", SchedDay.duration(buffer))
        }
        return text
    }

    private func changeDate(_ value: Date) {
        guard SchedDay.key(value) != dayKey else { return }
        date = value
        startMinute = nil
        slotTouched = false
        afterHours = false
        form.clear("date")
        form.clear("startTime")
        resetChecks()
    }

    private func resetChecks() {
        doubleBookConfirmed = false
        serverConflicts = nil
        serverHours = nil
        hoursConfirmed = false
    }

    // MARK: Loading

    private func prepare() async {
        guard !prepared else { return }
        prepared = true
        let location = locationId
        async let people = SchedData.members()
        async let book = SchedData.catalog()
        async let week = SchedData.availability(locationId: editing?.locationId)
        async let closed = SchedData.closures(locationId: location)
        members = await people
        catalog = await book
        availability = await week
        closures = await closed
        if let editing {
            await applyEditing(editing)
        } else {
            applyNew()
        }
        if !canAssignAnyone && assignee.isEmpty { assignee = editing?.assignedMember?.id ?? me?.id ?? "" }
    }

    private func applyEditing(_ visit: SchedAppointment) async {
        step = 2
        if let found: SchedClient = try? await API.get("/provider-clients/\(visit.providerClientId)") { client = found }
        petIds = [visit.providerClientPetId]
        category = visit.serviceCategory ?? services.first { $0.id == visit.serviceId }?.category ?? "other"
        serviceId = visit.serviceId ?? ""
        serviceLabel = visit.serviceLabel
        labelFromService = false
        if let start = visit.start {
            date = start
            startMinute = SchedDay.minuteOfDay(start)
        }
        duration = Self.durations.contains(visit.lengthMinutes) ? visit.lengthMinutes : (availability?.defaultAppointmentDurationMinutes ?? 30)
        afterHours = visit.hoursOverride == true
        roomId = visit.roomId
        roomTouched = true
        slotTouched = true
        notes = visit.notes ?? ""
        assignee = visit.assignedMember?.id ?? ""
    }

    private func applyNew() {
        if let day = draft.day { date = SchedDay.date(fromKey: max(day, SchedDay.today)) }
        duration = draft.durationMinutes.map { d in Self.durations.min(by: { abs($0 - d) < abs($1 - d) }) ?? 30 } ?? (availability?.defaultAppointmentDurationMinutes ?? 30)
        if let minute = draft.startMinute {
            startMinute = minute
            slotTouched = true
            let open = SchedHours.minutes(SchedHours.day(dayKey, load: nil, closures: closures, availability: availability).ranges)
            afterHours = !SchedHours.fits(minute, minute + duration, open)
        }
        roomId = draft.roomId
        roomTouched = draft.roomId != nil
        assignee = draft.memberId ?? (walkIn ? "" : me?.id ?? "")
        requestConfirmation = availability?.requestAppointmentConfirmationByDefault ?? true
        if categories.count == 1 { category = categories[0].id }
        if let notes = draft.notes?.nonEmpty { self.notes = notes }
        // A service the asking screen chose: its category and the service picked.
        if let wanted = draft.serviceId, let found = services.first(where: { $0.id == wanted }) {
            category = found.category
            serviceId = found.id
        }
        if let clientId = draft.clientId {
            Task {
                if let found: SchedClient = try? await API.get("/provider-clients/\(clientId)") {
                    client = found
                    petIds = draft.petId.map { [$0] } ?? (found.bookablePets.count == 1 ? [found.bookablePets[0].id] : [])
                    if !petIds.isEmpty { step = serviceId.isEmpty ? 1 : 2 }
                }
            }
        }
    }


    private func loadDay() async {
        guard step == 2 else { return }
        loadingDay = true
        defer { loadingDay = false }
        load = try? await SchedData.load(day: dayKey, locationId: locationId)
        pickDefaults()
    }

    /// The sheet's own pick moves to the first free time; a room for the time, the service's first.
    private func pickDefaults() {
        guard let load else { return }
        if !walkIn && !afterHours && !slotTouched {
            let free = openStarts.first { !busyStarts.contains($0) && !offStarts.contains($0) } ?? openStarts.first
            if startMinute == nil || busyStarts.contains(startMinute!) || offStarts.contains(startMinute!) || !openStarts.contains(startMinute!) {
                startMinute = free
            }
        }
        if !homeService && !roomTouched, let slot = currentSlot, !load.visitRooms.isEmpty {
            roomId = SchedConflicts.pickFreeRoom(slot, load: load, serviceId: serviceId.nonEmpty)?.id
        }
    }

    // MARK: Saving

    private func primary() {
        switch step {
        case 0:
            guard form.check([
                ("client", client == nil ? L("Choose the client first.") : nil),
                ("pet", client != nil && petId == nil ? L("Choose the pet first.") : nil),
            ]) else { return }
            if category.isEmpty, categories.count == 1 { category = categories[0].id }
            step = serviceId.isEmpty ? 1 : 2
        case 1:
            guard form.check([
                ("category", category.isEmpty ? L("Choose the service category first.") : nil),
                ("service", serviceId.isEmpty && !serviceOptional ? L("Choose the service first.") : nil),
            ]) else { return }
            step = 2
        default:
            walkIn ? saveWalkIn() : save()
        }
    }

    private func save() {
        let hoursTitle = shownHoursProblem.map { problem in SchedHours.problemTitle(problem, personName: members.first { $0.id == (problem.memberId ?? assignee) }?.label) }
        var timeError: String?
        if startMinute == nil { timeError = afterHours ? L("Choose the start time first.") : L("Choose one of the available start times first.") }
        else if !shownConflicts.isEmpty && !doubleBookConfirmed { timeError = L("This time is taken — confirm the double booking below, or choose another time.") }
        else if let together = takenTogether, !togetherConfirmed { timeError = LF("Confirm that %@ takes the %@ pets together.", together.person, String(together.pets.count)) }
        else if let hoursTitle, !afterHours, !hoursConfirmed { timeError = LF("%@ — confirm below to book it anyway, or choose another time.", hoursTitle) }
        else if let startMinute, SchedDay.at(dayKey, minute: startMinute) < Date(), editing == nil { timeError = L("Choose a current or future appointment time.") }
        let repeatProblem: String? = editing == nil && bookingRepeats && repeatDraft.on && repeatDraft.mode == "weekdays"
            && SchedRepeat.untilProblem(dayKey, repeatDraft.until ?? SchedRepeat.defaultUntil(dayKey)) ? L("Choose an end date within 26 weeks of the first visit") : nil
        guard form.check([
            ("serviceLabel", serviceLabel.nonEmpty == nil ? L("Add the visit or service name first.") : nil),
            ("date", editing == nil && dayKey < SchedDay.today ? L("Choose today or a future day for a new appointment.") : nil),
            ("assignee", assignee.isEmpty ? L("Choose the assignee first.") : nil),
            ("startTime", timeError),
            ("repeat", repeatProblem),
        ]) else { return }
        guard let client, let petId, let startMinute else { return }
        let start = SchedDay.at(dayKey, minute: startMinute)
        let end = start.addingTimeInterval(TimeInterval(duration * 60))
        var body: [String: Any?] = [
            "providerClientId": client.id,
            "providerClientPetId": petId,
            "assignedOrganizationMemberId": assignee.nonEmpty,
            "serviceCategory": category.nonEmpty,
            "serviceId": serviceId.nonEmpty,
            "serviceLabel": serviceLabel.nonEmpty,
            "startsAt": DateText.iso(start),
            "endsAt": DateText.iso(end),
            "notes": notes.nonEmpty,
            "outsideHours": afterHours || hoursConfirmed,
            "allowDoubleBooking": doubleBookConfirmed,
        ]
        let editingId = editing?.id
        if let editing {
            if roomId != editing.roomId { body["roomId"] = roomId }
        } else {
            if !extraPetIds.isEmpty {
                body["providerClientPetIds"] = petIds
                body["petsTogether"] = true
            }
            body["roomId"] = homeVisit ? nil : roomId
            body["status"] = "scheduled"
            body["requestConfirmation"] = requestConfirmation && clientHasEmail
            if let location = workspace.locationId { body["locationId"] = location }
            // None chosen (the addresses couldn't be read): the server takes the client's default, or answers address_required.
            if askAddress {
                body["serviceAddressId"] = serviceAddressId
                body["accessNotes"] = accessNotes.nonEmpty
            }
            if bookingRepeats, let repeating = SchedRepeat.body(repeatDraft, first: dayKey) { body["repeat"] = repeating }
            if groomBooking {
                let requests = SchedBookingGroomRequests.payload(groomRequests, petIds: petIds)
                if !requests.isEmpty { body["groomRequests"] = requests }
            }
        }
        let payload = body
        let names = petNames
        let followUpId = draft.followUpId
        let booked = onBooked
        let linksFollowUps = workspace.can(.followupsEdit) || workspace.can(.followupsComplete)
        working = true
        Task {
            defer { working = false }
            do {
                if let editingId {
                    let _: SchedAppointment = try await SchedAPI.send("PATCH", "/provider-appointments/\(editingId)", body: payload)
                    Toast.show(L("Appointment updated."))
                } else {
                    let created: SchedAppointment = try await SchedAPI.send("POST", "/provider-appointments", body: payload)
                    // The visit booked for a follow-up is tied to it: it leaves Due until that visit.
                    var linked: Bool?
                    if let followUpId, linksFollowUps {
                        do {
                            let _: EmptyResponse = try await API.patch("/provider-follow-ups/\(followUpId)", body: ["providerAppointmentId": created.id, "status": "scheduled"])
                            linked = true
                        } catch {
                            linked = false
                        }
                    }
                    if let series = created.series {
                        let skipped = series.skipped ?? []
                        let count = series.created ?? 0
                        if skipped.contains(where: { ($0.reason ?? "").contains("120") }) {
                            Toast.show("\(LF("%@ visits booked, %@ skipped", String(count), String(skipped.count))) · \(L("Past the limit of 120 visits"))")
                        } else if !skipped.isEmpty {
                            Toast.show(LF("%@ visits booked; %@ dates were skipped (closed or taken).", String(count), String(skipped.count)))
                        } else {
                            Toast.show(LF("%@ visits booked.", String(count)))
                        }
                    } else if linked == true {
                        Toast.show(L("Booked. It is off the list until that visit."))
                    } else if linked == false {
                        Toast.error(L("The visit is booked, but the follow-up was not linked to it."))
                    } else if let together = created.together, !together.isEmpty {
                        Toast.show(LF("Booked %@ together.", names ?? created.petName))
                    } else if created.confirmationStatus == "pending" {
                        Toast.show(L("Appointment created and confirmation sent."))
                    } else if created.confirmationStatus == "delivery_failed" {
                        Toast.error(L("Appointment created, but the confirmation email failed."))
                    } else {
                        Toast.show(L("Appointment created."))
                    }
                    await booked?(created)
                }
                announceDataChanged()
                dismiss()
            } catch {
                handle(error)
            }
        }
    }

    private func saveWalkIn() {
        let typed = walkInWeight.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let kg = typed.isEmpty ? nil : Double(typed)
        guard form.check([
            ("serviceLabel", serviceLabel.nonEmpty == nil ? L("Add the visit or service name first.") : nil),
            ("weight", !typed.isEmpty && (kg == nil || kg! <= 0 || kg! > 200) ? L("Enter the weight in kg, like 12.4") : nil),
        ]) else { return }
        // Why they came is asked once: the visit's reason stands in for the triage's when that's left blank.
        let triaged: (value: [String: Any?]?, missing: SchedTriageDraft.Missing?) = walkInVetCare ? walkInTriage.parsed(fallbackReason: notes) : (nil, nil)
        if let missing = triaged.missing {
            triageInvalid = missing
            Toast.error(SchedTriageDraft.missingText(missing))
            return
        }
        guard let client, let petId else { return }
        var body: [String: Any?] = [
            "providerClientId": client.id,
            "providerClientPetId": petId,
            "serviceCategory": category.nonEmpty,
            "serviceId": serviceId.nonEmpty,
            "serviceLabel": serviceLabel.nonEmpty,
            "durationMinutes": duration,
            "arrivalNote": notes.nonEmpty,
            "roomId": roomId,
            "weightGrams": kg.map { Int(($0 * 1000).rounded()) },
            "clientRequestId": walkInRequestId,
        ]
        if let triage = triaged.value { body["triage"] = triage }
        if canAssignAnyone { body["assignedOrganizationMemberId"] = assignee.nonEmpty }
        if let location = workspace.locationId { body["locationId"] = location }
        let base = body
        let pet = pets.first { $0.id == petId }?.petName ?? ""
        func arrive(_ start: Bool, _ extra: [String: Any?]) async throws {
            var payload = base
            payload["start"] = start
            for (key, value) in extra { payload[key] = value }
            let result: SchedMoveResponse = try await SchedAPI.send("POST", "/provider-appointments/walk-in", body: payload)
            announceDataChanged()
            Toast.show(result.appointment?.status == "in_progress" ? LF("%@ is in.", pet) : LF("%@ is waiting.", pet))
        }
        let starts = walkInStart
        let owner = client
        working = true
        Task {
            defer { working = false }
            do {
                try await arrive(starts, [:])
                walkInRequestId = schedRequestId()
                dismiss()
            } catch {
                // A deposit taken here goes with the walk-in: the visit is created checked in, the deposit recorded on it, and it starts.
                if starts, let prompt = SchedGatePrompt.from(error, petName: pet, verb: "start", attempt: { try await arrive(true, $0) }, onDone: {}, fallback: { try await arrive(false, [:]) },
                                                            clientId: owner.id, clientName: owner.ownerName,
                                                            takeDeposit: { payment, override in
                                                                var extra = override
                                                                extra["deposit"] = payment
                                                                try await arrive(true, extra)
                                                            }) {
                    if !staysOnGate { dismiss() }
                    onGate(prompt)
                    return
                }
                handle(error)
            }
        }
    }

    private func handle(_ error: Error) {
        guard let failure = error as? SchedFailure else { schedToast(error); return }
        if failure.code == "start_in_past" {
            _ = form.check([("startTime", failure.api.field("startsAt") ?? failure.api.message)])
            return
        }
        if let problem = failure.hoursProblem {
            serverHours = problem
            hoursConfirmed = false
            Toast.error(SchedHours.problemTitle(problem, personName: members.first { $0.id == (problem.memberId ?? assignee) }?.label))
            return
        }
        if let conflicts = failure.conflicts {
            serverConflicts = conflicts
            doubleBookConfirmed = false
            Toast.error(L("Double booking — read the warning and confirm to book anyway."))
            return
        }
        if ["address_required", "address_not_found", "address_archived"].contains(failure.code ?? "") {
            addressError = failure.api.message
            Toast.error(failure.api.message)
            return
        }
        if ["not_grooming", "invalid_groom_request", "empty_request"].contains(failure.code ?? "") || (failure.code ?? "").hasPrefix("groom") {
            Toast.error(failure.api.message)
            return
        }
        let placed = form.apply(failure.api, known: [
            "providerClientId": "client", "providerClientPetId": "pet", "serviceLabel": "serviceLabel",
            "startsAt": "startTime", "endsAt": "startTime", "assignedOrganizationMemberId": "assignee", "weightGrams": "weight",
        ])
        if placed, form.errors["client"] != nil || form.errors["pet"] != nil { step = 0 }
    }
}

/// The booking's client type and the shared picker's, the same fields both ways.
enum SchedClientBridge {
    static func picked(_ c: SchedClient) -> PickedClient {
        PickedClient(id: c.id, ownerName: c.ownerName, ownerEmail: c.ownerEmail, ownerPhone: c.ownerPhone, householdId: c.householdId,
                     photoUrl: c.photoUrl, status: c.status,
                     pets: (c.pets ?? []).map { PickedPet(id: $0.id, petName: $0.petName, petSpecies: $0.petSpecies, petBreed: $0.petBreed, photoUrl: $0.photoUrl, status: $0.status, microchipNumber: $0.microchipNumber, weight: $0.weight) })
    }

    static func sched(_ c: PickedClient) -> SchedClient {
        SchedClient(id: c.id, householdId: c.householdId, ownerName: c.name, ownerEmail: c.ownerEmail, ownerPhone: c.ownerPhone, photoUrl: c.photoUrl, status: c.status,
                    pets: (c.pets ?? []).map { SchedClientPet(id: $0.id, petName: $0.name, petSpecies: $0.petSpecies, petBreed: $0.petBreed, photoUrl: $0.photoUrl, status: $0.status, microchipNumber: $0.microchipNumber, weight: $0.weight) })
    }
}
