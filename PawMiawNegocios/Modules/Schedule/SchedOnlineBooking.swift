//
//  SchedOnlineBooking.swift
//  PawMiawNegocios
//
//  A booking a family made online that waits for the business
//  (paw-miaw-backend docs/online-booking.md §2, §9, §12.5; web
//  online-booking/online-request.tsx): its facts and the three answers —
//  Confirmar, Cambiar hora y confirmar (a free time by the staff booking
//  rule, from the schedule's load) and Rechazar with a reason the family
//  reads. Pets booked together are answered together; the server acts on
//  all of them and tells the family.
//
//  A family's ask to move a confirmed online booking ("Cambio de hora", §13)
//  is answered in the same places with two of those answers: Aceptar (the
//  visit moves to the time asked for) and Rechazar with a reason (it keeps
//  its time).
//

import SwiftUI

/// What the answers need of a request, from the inbox's item or from the visit itself.
struct SchedAnswerTarget: Hashable {
    /// A family's ask to move a confirmed visit, not a booking to confirm.
    let reschedule: Bool
    /// The time asked for (an ask); the visit's own time stays in `startsAt`/`endsAt`.
    let proposal: SchedRescheduleProposal?
    let appointmentId: String
    let startsAt: String
    let endsAt: String?
    let memberId: String?
    let memberName: String?
    let roomId: String?
    let room: String?
    let locationId: String?
    let serviceLabel: String
    let atHome: Bool
    let notes: String?
    let releasesAt: String?
    let clientName: String
    let clientPhone: String?
    let pets: [SchedRequestPet]

    init(request: SchedOnlineRequest) {
        reschedule = request.isReschedule
        proposal = request.isReschedule ? request.rescheduleProposal : nil
        appointmentId = request.appointmentId
        startsAt = request.startsAt
        endsAt = request.endsAt
        memberId = request.assigned?.id
        memberName = request.assigned?.name
        roomId = nil
        room = request.room
        locationId = request.locationId
        serviceLabel = request.serviceLabel
        atHome = request.atHome ?? false
        notes = request.notes
        releasesAt = request.releasesAt
        clientName = request.client.name
        clientPhone = request.client.phone
        pets = request.pets
    }

    init(appointment a: SchedAppointment) {
        reschedule = !a.isRequested && a.rescheduleProposal != nil
        proposal = reschedule ? a.rescheduleProposal : nil
        appointmentId = a.id
        startsAt = a.startsAt
        endsAt = a.endsAt
        memberId = a.assignedMember?.id
        memberName = a.assignedMember?.name
        roomId = a.roomId
        room = a.room
        locationId = a.locationId
        serviceLabel = a.serviceLabel
        atHome = a.atHome ?? false
        notes = a.notes
        releasesAt = reschedule ? a.rescheduleProposal?.releasesAt : a.onlineRequest?.releasesAt
        clientName = a.clientName
        clientPhone = a.clientPhone
        // A family's pets booked together are answered together: the others still waiting with it
        // (a request's are still requested; an ask's are still booked, and move with it).
        let together = a.group?.kind == "household" ? (a.group?.pets ?? []).filter { $0.status == a.status } : []
        pets = together.isEmpty
            ? [SchedRequestPet(appointmentId: a.id, providerClientPetId: a.providerClientPetId, name: a.petName, species: a.petSpecies, photoUrl: a.petPhotoUrl)]
            : together.map { SchedRequestPet(appointmentId: $0.appointmentId, providerClientPetId: $0.providerClientPetId, name: $0.name ?? "", species: $0.species, photoUrl: $0.photoUrl) }
    }

    var lengthMinutes: Int {
        guard let start = DateText.parse(startsAt), let end = DateText.parse(endsAt), end > start else { return 30 }
        return max(15, Int(end.timeIntervalSince(start) / 60))
    }
}

enum SchedOnlineText {
    /// "Miércoles 4 de noviembre · 10:00–10:30".
    static func when(_ startsAt: String, _ endsAt: String?) -> String {
        let start = DateText.parse(startsAt)
        let end = DateText.parse(endsAt).map { "–" + DateText.time($0) } ?? ""
        return "\(SchedDay.upperFirst(DateText.longDay(start))) · \(DateText.time(start))\(end)"
    }

    /// "en 3 horas", "en 40 min", "ahora".
    static func releaseIn(_ releasesAt: String?) -> String? {
        guard let date = DateText.parse(releasesAt) else { return nil }
        let minutes = Int((date.timeIntervalSinceNow / 60).rounded())
        if minutes <= 1 { return L("now") }
        if minutes < 60 { return LF("in %@ min", String(minutes)) }
        let hours = Int((Double(minutes) / 60).rounded())
        return hours == 1 ? L("in 1 hour") : LF("in %@ hours", String(hours))
    }

    /// "Hoy, 10:00 a.m. → Mañana, 11:30 a.m."; the day once when both are on it ("Hoy, 10:00 a.m. → 11:30 a.m.").
    static func move(_ from: String, _ to: String?) -> String {
        let sameDay = SchedDay.key(from) != nil && SchedDay.key(from) == SchedDay.key(to)
        return "\(DateText.dayTime(from)) → \(sameDay ? DateText.time(to) : DateText.dayTime(to))"
    }

    /// "Cambio de hora: Hoy, 10:00 a.m. → Mañana, 11:30 a.m." (the visit's time now → the time asked for).
    static func change(_ from: String, _ to: String?) -> String {
        LF("Change of time: %@", move(from, to))
    }

    /// The inbox's title: bookings to confirm, changes of time to answer, or both
    /// (`asks`: the changes of time among the items read).
    static func inboxTitle(count: Int, asks: Int) -> String {
        if asks == 0 { return count == 1 ? L("1 online booking to confirm") : LF("%@ online bookings to confirm", String(count)) }
        if asks == count { return LP(count, "%d change of time to answer", "%d changes of time to answer") }
        return LF("%d online bookings and changes of time to answer", count)
    }
}

// MARK: - Facts

/// The request as the family sent it: who, which pets, what, when, where, and their note
/// (web `OnlineRequestFacts`: a sheet section of pet chips, fact boxes, the note, the hold).
struct SchedRequestFacts: View {
    let target: SchedAnswerTarget
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(target.reschedule ? L("What they ask") : L("What they booked")).font(.brandHeading(16.8, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
            FlowLayout(spacing: 8) {
                ForEach(target.pets, id: \.appointmentId) { pet in
                    HStack(spacing: 8) {
                        PetAvatar(name: pet.name, species: pet.species, photoURL: pet.photoUrl, size: 32)
                        Text(pet.name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    }
                    .padding(.vertical, 4).padding(.leading, 4).padding(.trailing, 12)
                    .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: sizeClass == .regular ? 2 : 1), spacing: 12) {
                if target.reschedule {
                    // An ask: the visit's time now, then the time asked for (and who would see them then).
                    SchedFactBox(icon: "calendar-clock", label: L("Now")) {
                        Text(SchedOnlineText.when(target.startsAt, target.endsAt))
                        Text(target.serviceLabel).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                    SchedFactBox(icon: "calendar-check", label: L("Asks for")) {
                        Text(target.proposal.map { SchedOnlineText.when($0.startsAt, $0.endsAt) } ?? "—")
                    }
                } else {
                    SchedFactBox(icon: "calendar-clock", label: L("When")) {
                        Text(SchedOnlineText.when(target.startsAt, target.endsAt))
                        Text(target.serviceLabel).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
                SchedFactBox(icon: "phone", label: L("Family")) {
                    Text(target.clientName)
                    if let phone = target.clientPhone, let url = schedPhoneURL(phone) {
                        Link(phone, destination: url).font(Theme.text(12)).foregroundStyle(Theme.blue)
                    }
                }
                SchedFactBox(icon: "user-round", label: L("With")) {
                    let who = target.reschedule ? target.proposal?.assigned?.name : target.memberName
                    let room = target.reschedule ? target.proposal?.room : target.room
                    Text(who ?? L("Whoever is free"))
                    if let room { Text(room).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                }
                if target.atHome {
                    SchedFactBox(icon: "house", label: L("Where")) { Text(L("At the family’s home")) }
                }
            }
            if let notes = target.notes?.nonEmpty {
                Text("“\(notes)”").font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            }
            if let release = SchedOnlineText.releaseIn(target.releasesAt) {
                HStack(alignment: .top, spacing: 8) {
                    Glyph("clock-3", size: 16).padding(.top, 2)
                    Text(target.reschedule
                         ? LF("The new time is held for them and the visit stays where it is. With no answer the ask expires %@, and the family is told.", release)
                         : LF("The time is held for them. With no answer it is released %@, and the family is told.", release))
                }
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
        }
    }
}

/// One fact of a request (web `Fact`): a bordered box, the icon, an uppercase label, the value.
struct SchedFactBox<Content: View>: View {
    let icon: String
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Glyph(icon, size: 16).foregroundStyle(Theme.inkSoft).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased()).font(Theme.text(12, weight: .bold)).tracking(1.44).foregroundStyle(Theme.inkSoft)
                VStack(alignment: .leading, spacing: 0) { content() }
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }
}

// MARK: - The three answers

struct SchedRequestAnswer: View {
    let target: SchedAnswerTarget
    var onDone: () -> Void = {}

    private enum Mode: String, Hashable { case confirm, change, decline }

    @EnvironmentObject private var workspace: Workspace
    @StateObject private var form = FormState()
    @State private var mode: Mode = .confirm
    @State private var startsAt: String?
    @State private var memberId: String?
    @State private var reason = ""
    @State private var working = false
    @State private var pickerVersion = 0

    private var quickReasons: [String] {
        target.reschedule
            ? [L("We are full at that time."), L("Nobody who does it is free then."), L("Call us and we’ll find another time.")]
            : [L("We are full at that time."), L("That service needs a call first."), L("We can’t see this pet for that.")]
    }

    /// A request's three answers; an ask's two (Aceptar, Rechazar).
    private var options: [Segmented<Mode>.Option] {
        target.reschedule
            ? [.init(Mode.confirm, L("Accept"), icon: "check"), .init(Mode.decline, L("Decline"), icon: "circle-x")]
            : [.init(Mode.confirm, L("Confirm"), icon: "check"), .init(Mode.change, L("Other time"), icon: "calendar-clock"), .init(Mode.decline, L("Decline"), icon: "circle-x")]
    }

    var body: some View {
        if !workspace.can(.appointmentsCreate) {
            Text(L("Someone who books visits can answer it.")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
        } else {
            // The web's answer panel: the answers as one switch, on a pale blue card.
            FormScroll(form: form) {
                VStack(alignment: .leading, spacing: 16) {
                    Segmented(options: options, selection: $mode, label: L("Answer"))
                    switch mode {
                    case .confirm where target.reschedule:
                        let asked = target.proposal.map { SchedOnlineText.when($0.startsAt, $0.endsAt) } ?? "—"
                        Text(LF("The visit moves to %@, and the family is told.", asked) + told)
                            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        PMButton(L("Accept"), systemImage: "check", fullWidth: true, isWorking: working) { accept() }
                    case .confirm:
                        Text(L("It becomes a visit in the Schedule at the time they chose, and the family is told it is confirmed.") + told)
                            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        PMButton(L("Confirm"), systemImage: "check", fullWidth: true, isWorking: working) { confirm() }
                    case .change:
                        Text(L("Pick a free time: the family is told the new time and may cancel it whenever they like.") + told)
                            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        SchedFreeTimePicker(target: target, memberId: $memberId, canChooseMember: workspace.can(.appointmentsAssignAnyone), value: $startsAt, form: form)
                            .id(pickerVersion)
                        PMButton(L("Change time and confirm"), systemImage: "calendar-clock", fullWidth: true, isWorking: working) { change() }
                    case .decline:
                        FlowLayout(spacing: 8) {
                            ForEach(quickReasons, id: \.self) { quick in
                                FilterChip(title: quick, isSelected: reason == quick) { reason = quick }
                            }
                        }
                        PMTextField(L("Why (optional, the family reads it)"), text: $reason, key: "reason", form: form, multiline: true)
                        Text(target.reschedule
                             ? L("The visit keeps its time, the time they asked for is freed, and the family is told.")
                             : L("The time is freed and the family is told, with a way to book another time."))
                            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        PMButton(L("Decline"), systemImage: "circle-x", variant: .destructive, fullWidth: true, isWorking: working) {
                            if target.reschedule { declineChange() } else { decline() }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(Theme.blue, 5), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            }
            .onAppear { if memberId == nil { memberId = target.memberId } }
        }
    }

    private var told: String { target.pets.count > 1 ? " " + L("Every pet booked with it is answered too.") : "" }

    private func run(_ success: String, _ action: @escaping @MainActor () async throws -> Void) {
        working = true
        Task {
            defer { working = false }
            do {
                try await action()
                announceDataChanged()
                Toast.show(success)
                onDone()
            } catch {
                if mode == .change, (error as? SchedFailure)?.conflicts != nil {
                    startsAt = nil
                    pickerVersion += 1
                    _ = form.check([("startsAt", L("That time was just taken. Pick another free time."))])
                    return
                }
                if mode == .change, let field = (schedAPIError(error) as? APIError)?.field("startsAt") {
                    _ = form.check([("startsAt", field)])
                    return
                }
                schedToast(error)
                // Nothing waits any more (answered, released or withdrawn meanwhile): the list drops it.
                if (error as? SchedFailure)?.code == "not_a_reschedule" {
                    announceDataChanged()
                    onDone()
                }
            }
        }
    }

    /// One of the three answers (each answers `{ appointmentId, status, startsAt }`).
    private static func answer(_ path: String, body: [String: Any?]) async throws {
        let _: SchedOnlineAnswer = try await SchedAPI.send("POST", path, body: body)
    }

    private func confirm() {
        let id = target.appointmentId
        run(L("Confirmed. The family has been told.")) {
            try await Self.answer("/provider-appointments/\(id)/online/confirm", body: [:])
        }
    }

    private func change() {
        guard let startsAt, let start = DateText.parse(startsAt) else {
            _ = form.check([("startsAt", L("Pick the new time."))])
            return
        }
        let end = start.addingTimeInterval(TimeInterval(target.lengthMinutes * 60))
        var body: [String: Any?] = ["startsAt": DateText.iso(start), "endsAt": DateText.iso(end)]
        if memberId != target.memberId { body["assignedOrganizationMemberId"] = memberId }
        let id = target.appointmentId, payload = body
        run(LF("Moved to %@ and confirmed. The family has been told.", SchedOnlineText.when(DateText.iso(start), DateText.iso(end)))) {
            try await Self.answer("/provider-appointments/\(id)/online/change-and-confirm", body: payload)
        }
    }

    private func decline() {
        let id = target.appointmentId, why = reason.nonEmpty
        run(L("Declined. The family has been told.")) {
            try await Self.answer("/provider-appointments/\(id)/online/decline", body: ["reason": why])
        }
    }

    /// An ask's Aceptar: the visit (and every pet booked with it) moves to the time asked for.
    private func accept() {
        let id = target.appointmentId
        let asked = target.proposal.map { SchedOnlineText.when($0.startsAt, $0.endsAt) }
        run(asked.map { LF("Moved to %@. The family has been told.", $0) } ?? L("Change accepted. The family has been told.")) {
            try await Self.answer("/provider-appointments/\(id)/online/accept-reschedule", body: [:])
        }
    }

    /// An ask's Rechazar, with the reason the family reads: the visit keeps its time.
    private func declineChange() {
        let id = target.appointmentId, why = reason.nonEmpty
        run(L("Change declined. The visit keeps its time and the family has been told.")) {
            try await Self.answer("/provider-appointments/\(id)/online/decline-reschedule", body: ["reason": why])
        }
    }
}

// MARK: - Free times

/// The free times of one day for the request, by the rule staff booking uses: opening
/// hours and closures, the person's own hours and days off, pets at once, the room,
/// the buffer. The request's own time (and its pets) never compete with it.
struct SchedFreeTimePicker: View {
    let target: SchedAnswerTarget
    @Binding var memberId: String?
    let canChooseMember: Bool
    @Binding var value: String?
    @ObservedObject var form: FormState

    @State private var day = SchedDay.today
    @State private var load: SchedLoad?
    @State private var loading = false
    @State private var people: [SchedMember] = []
    @State private var prepared = false

    private var today: String { SchedDay.today }

    var body: some View {
        FormField(label: L("Free times"), key: "startsAt", form: form) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 6) {
                    IconCircleButton(systemImage: "chevron-left", label: L("Previous day"), tint: Theme.blue) {
                        let previous = SchedDay.addDays(day, -1)
                        if previous >= today { day = previous }
                    }
                    .disabled(day <= today)
                    .opacity(day <= today ? 0.4 : 1)
                    .padding(.bottom, 6)
                    DayField(label: L("Day"), day: Binding(get: { day }, set: { day = max(today, $0) }), min: today)
                    IconCircleButton(systemImage: "chevron-right", label: L("Next day"), tint: Theme.blue) { day = SchedDay.addDays(day, 1) }
                        .padding(.bottom, 6)
                }
                if canChooseMember && !people.isEmpty {
                    MenuField(label: L("With"), options: [(nil, L("Whoever is free"))] + people.map { (Optional($0.id), $0.label) }, selection: Binding(get: { memberId }, set: { memberId = $0; value = nil }))
                }
                Text(LF("Free times · %@", DateText.longDay(SchedDay.date(fromKey: day))).uppercased())
                    .font(Theme.text(12, weight: .bold)).tracking(1.44).foregroundStyle(Theme.inkSoft)
                slotsView
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(form.error("startsAt") != nil ? Theme.coral : Theme.borderSoft, lineWidth: 1))
        }
        .task(id: day) { await loadDay() }
        .task {
            guard !prepared else { return }
            prepared = true
            if let asked = SchedDay.key(target.startsAt), asked > today { day = asked }
            if canChooseMember {
                let everyone = await SchedData.members()
                people = everyone.filter { $0.takesVisits && $0.worksAt(target.locationId) }
            }
        }
    }

    @ViewBuilder private var slotsView: some View {
        if loading && load == nil {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
        } else if let result = slots {
            if result.list.isEmpty {
                Text(result.closed ? (result.closureLabel.map { LF("Closed that day: %@.", $0) } ?? L("Closed that day.")) : result.off ? L("That person is off that day.") : L("No free time left that day. Try the next one."))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(result.list, id: \.start) { slot in
                        FilterChip(title: SchedDay.timeLabel(slot.minute), isSelected: value == slot.start) {
                            value = slot.start
                            form.clear("startsAt")
                        }
                    }
                }
            }
        }
    }

    private struct Slots { let closed: Bool; let closureLabel: String?; let off: Bool; let list: [(minute: Int, start: String)] }

    private var slots: Slots? {
        guard let load else { return nil }
        let dayHours = load.hoursDay(day)
        let open = SchedHours.minutes(dayHours?.ranges ?? [])
        let person = memberId.flatMap { id in load.people?.first { $0.id == id } }
        let theirDay = person?.day(day)
        let ranges = theirDay.map { $0.timeOff != nil ? [] : SchedHours.minutes($0.ranges ?? []) } ?? open
        let nowMinute = day == today ? SchedDay.minuteOfDay(Date()) : -1
        let length = max(15, target.lengthMinutes)
        let ignore = target.pets.map(\.appointmentId)
        var list: [(minute: Int, start: String)] = []
        for span in ranges {
            var minute = Int((Double(span.start) / 15).rounded(.up)) * 15
            while minute + length <= span.end {
                defer { minute += 15 }
                if minute <= nowMinute { continue }
                if !SchedHours.fits(minute, minute + length, open) { continue }
                let start = SchedDay.at(day, minute: minute)
                let slot = SchedSlot(id: target.appointmentId, start: start, end: start.addingTimeInterval(TimeInterval(length * 60)), memberId: memberId, roomId: target.roomId, pets: ignore.count, ignoreIds: ignore)
                if SchedConflicts.find(slot, load: load).isEmpty { list.append((minute, DateText.iso(start))) }
            }
        }
        return Slots(closed: open.isEmpty, closureLabel: dayHours?.closure?.label, off: theirDay?.timeOff != nil, list: list)
    }

    private func loadDay() async {
        loading = true
        defer { loading = false }
        load = try? await SchedData.load(day: day, locationId: target.locationId ?? Workspace.shared.locationId)
    }
}

// MARK: - The inbox

/// A request in the inbox (web `OnlineRequestCard`): a dashed waiting card with the pets,
/// what and when, who booked, and when it is released. An ask to move a visit reads
/// "Cambio de hora: {now} → {asked for}" and when the ask expires.
struct SchedRequestCard: View {
    let request: SchedOnlineRequest
    let onOpen: () -> Void

    private var soon: Bool { (DateText.parse(request.releasesAt)?.timeIntervalSinceNow ?? .infinity) < 2 * 3600 }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    PetStack(pets: request.pets.map { ($0.name, $0.species, $0.photoUrl) }, size: 40, max: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(request.pets.map(\.name).joined(separator: ", ")).font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Text("\(request.client.name) · \(request.serviceLabel)").font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if request.isReschedule { SchedRescheduleMark() } else { SchedPendingMark() }
                }
                HStack(alignment: .top, spacing: 8) {
                    Glyph("calendar-clock", size: 16).foregroundStyle(Theme.inkSoft).padding(.top, 1)
                    if request.isReschedule {
                        Text(SchedOnlineText.change(request.startsAt, request.rescheduleProposal?.startsAt)).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(SchedOnlineText.when(request.startsAt, request.endsAt)).lineLimit(1)
                    }
                }
                .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                FlowLayout(spacing: 12, lineSpacing: 4) {
                    let who = request.isReschedule ? request.rescheduleProposal?.assigned?.name : request.assigned?.name
                    HStack(spacing: 4) { Glyph("user-round", size: 12); Text(who ?? L("Whoever is free")) }
                    if request.atHome == true { HStack(spacing: 4) { Glyph("map-pin", size: 12); Text(L("At the family’s home")) } }
                    if let release = SchedOnlineText.releaseIn(request.releasesAt) {
                        HStack(spacing: 4) { Glyph("clock-3", size: 12); Text(request.isReschedule ? LF("Expires %@@ask", release) : LF("Released %@", release)) }
                            .foregroundStyle(soon ? Theme.destructive : Theme.inkSoft)
                            .fontWeight(soon ? .bold : .regular)
                    }
                }
                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                if let notes = request.notes?.nonEmpty {
                    Text("“\(notes)”").font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.mix(ProviderState.waiting.color, 70, with: Theme.borderSoft), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .cardShadow()
        }
        .buttonStyle(.plain)
    }
}

/// The visit page of a requested visit (web `OnlineRequestPanel`): what the family booked
/// and the three answers, on a dashed card. No check-in, start, note or bill until it is confirmed.
struct SchedRequestPanel: View {
    let target: SchedAnswerTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if target.reschedule { SchedRescheduleMark() } else { SchedPendingMark() }
                    SchedOnlineMark()
                }
                if target.reschedule {
                    Text(L("The family asks to move this visit")).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
                    Text(SchedOnlineText.change(target.startsAt, target.proposal?.startsAt)).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    Text(L("It stays at its time until you answer. Accept and it moves; decline and it stays.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                } else {
                    Text(L("A family booked this online")).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
                    Text(L("It holds its time but isn’t a visit yet: no check-in, start or bill until you confirm it.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
            SchedRequestFacts(target: target)
            SchedRequestAnswer(target: target)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.mix(ProviderState.waiting.color, 70, with: Theme.borderSoft), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
    }
}

/// One request in a sheet: its facts and the three answers.
struct SchedRequestSheet: View {
    let request: SchedOnlineRequest
    /// Opens the visit page (the sheet has no navigation of its own).
    var onOpenVisit: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let target = SchedAnswerTarget(request: request)
        let when = target.reschedule ? SchedOnlineText.change(target.startsAt, target.proposal?.startsAt) : SchedOnlineText.when(target.startsAt, target.endsAt)
        ProviderModal(title: "\(target.serviceLabel) · \(target.pets.map(\.name).joined(separator: ", "))", subtitle: "\(target.clientName) · \(when)", systemImage: "globe", accent: .aqua, cancelTitle: L("Close")) {
            HStack(spacing: 8) {
                if target.reschedule { SchedRescheduleMark() } else { SchedPendingMark() }
                SchedOnlineMark()
            }
            SchedRequestFacts(target: target)
            if let onOpenVisit {
                PMButton(L("Open the visit"), systemImage: "square-arrow-out-up-right", variant: .outline, size: .compact) {
                    dismiss()
                    onOpenVisit(target.appointmentId)
                }
            }
            SchedRequestAnswer(target: target) { dismiss() }
        }
        .presentationDetents([.large])
    }
}

/// Families' online bookings waiting for an answer, and their asks to move one
/// (the server's count of both: pets booked together once).
struct SchedRequestsInbox: View {
    let list: SchedOnlineRequestList
    let onOpen: (SchedOnlineRequest) -> Void

    var body: some View {
        let count = list.count ?? 0
        if count > 0 {
            PageSection(SchedOnlineText.inboxTitle(count: count, asks: (list.items ?? []).filter(\.isReschedule).count), subtitle: L("Booked online, waiting for you")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 10)], spacing: 10) {
                    ForEach(list.items ?? []) { request in
                        SchedRequestCard(request: request) { onOpen(request) }
                    }
                }
            }
        }
    }
}
