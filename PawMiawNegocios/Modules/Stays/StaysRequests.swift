//
//  StaysRequests.swift
//  PawMiawNegocios
//
//  The Requests tab (web provider.stays.tsx HeldStays + requests/
//  provider-requests.tsx): stays held as a request or a quote, visits
//  families booked online waiting for an answer (answered on the visit), and
//  families' requests for a hotel stay, daycare or a home stay — waiting for
//  you, waiting for the family, dates passed, and the answered ones. One
//  request opens to confirm it (booking the stay, or planning the home stay),
//  propose other dates or decline it with a reason; the family is told.
//

import SwiftUI

private let stayRequestKinds: Set<String> = ["boarding", "daycare", "homestay"]

struct StaysRequestsView: View {
    let held: [StaysStay]

    @EnvironmentObject private var workspace: Workspace
    @State private var open: [StaysRequest] = []
    @State private var answered: [StaysRequest] = []
    @State private var online: StaysOnlineList?
    @State private var loaded = false
    @State private var error: String?
    @State private var showAnswered = false
    @State private var focused: StaysRequest?
    @State private var openStay: String?

    private var waiting: [StaysRequest] {
        open.filter { $0.shownStatus == "pending" }
            .sorted { a, b in
                if (a.familyAcceptedAt != nil) != (b.familyAcceptedAt != nil) { return a.familyAcceptedAt != nil }
                return a.startDay < b.startDay
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !held.isEmpty { heldCard }
            if !loaded {
                LoadingState()
            } else if let error {
                ErrorState(message: error) { await load() }
            } else {
                if open.isEmpty && (online?.items ?? []).isEmpty {
                    EmptyState(systemImage: "mail-question-mark", title: L("No requests waiting"),
                               message: L("Families linked to you can ask for stays, home stays and programs from their app. Their requests show up here."),
                               accent: Theme.aqua, panel: true)
                }
                onlineGroup
                group(L("Waiting for you"), nil, waiting)
                group(L("Waiting for the family"), nil, open.filter { $0.shownStatus == "proposed" })
                group(L("Dates passed"), L("Propose new dates or decline them."), open.filter { $0.shownStatus == "expired" })
                PMButton(showAnswered ? L("Hide answered") : L("Show answered"), variant: .outline) { showAnswered.toggle() }
                if showAnswered {
                    if answered.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            StaysEyebrow(text: L("Answered"))
                            EmptyState(systemImage: "check", title: L("Nothing answered yet."), accent: Theme.aqua)
                        }
                    }
                    group(L("Answered"), nil, answered)
                }
            }
        }
        .reloadsOnScope { await load() }
        .onChange(of: showAnswered) { _, _ in Task { await load() } }
        .sheet(item: $focused) { request in
            StaysRequestSheet(request: request) { stayId in openStay = stayId }
        }
        .navigationDestination(item: $openStay) { StayDetailScreen(stayId: $0) }
    }

    // MARK: Held stays

    /// Stays held as a request or sent as a quote, still to confirm: each opens to confirm or cancel it.
    private var heldCard: some View {
        Card(spacing: 8) {
            StaysEyebrow(text: L("Held, not confirmed yet")).padding(.bottom, 4)
            ForEach(held) { stay in
                NavigationLink(value: ProviderRoute.stay(stay.id)) {
                    StaysTintedRow(tint: Theme.mango, percent: 14) {
                        PetStack(pets: stay.petList.map { ($0.petName, $0.petSpecies, $0.photoUrl) }, size: 40, max: 3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(stay.petNames) · \(StaysWords.kind(stay.kind))").font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            Text("\(range(stay)) · \(stay.clientName ?? "")\(stay.unitName.map { " · \($0)" } ?? "")").font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(L("Open")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func range(_ stay: StaysStay) -> String {
        if stay.isDaycare || stay.checkInDay == stay.checkOutDay { return StaysDay.short(stay.checkInDay) }
        return "\(StaysDay.dayMonth(stay.checkInDay)) – \(StaysDay.dayMonth(stay.checkOutDay))"
    }

    // MARK: Online bookings

    @ViewBuilder
    private var onlineGroup: some View {
        let items = online?.items ?? []
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                let count = online?.count ?? items.count
                VStack(alignment: .leading, spacing: 4) {
                    StaysEyebrow(text: LP(count, "%d online booking to confirm", "%d online bookings to confirm"))
                    Text(L("Their time is held until you answer. Pets booked together are answered together.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(items) { request in
                        // The visit's own page answers it (Confirmar, Cambiar hora y confirmar, Rechazar).
                        NavigationLink(value: ProviderRoute.appointment(request.appointmentId)) { onlineCard(request) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// A visit a family booked online (web `OnlineRequestCard`): its time held, a dashed waiting edge.
    private func onlineCard(_ request: StaysOnlineRequest) -> some View {
        let soon = DateText.parse(request.releasesAt).map { $0.timeIntervalSinceNow < 2 * 3600 } ?? false
        return Card(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                PetStack(pets: (request.pets ?? []).map { ($0.name ?? "", $0.species, $0.photoUrl) }, size: 40, max: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text((request.pets ?? []).compactMap(\.name).joined(separator: ", ")).font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text("\(request.client?.name ?? "") · \(request.serviceLabel ?? "")").font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 4)
                Chip(text: L("To confirm"), icon: "clock-3", pending: true)
            }
            HStack(spacing: 8) {
                Glyph("calendar-clock", size: 16).foregroundStyle(Theme.inkSoft)
                Text(DateText.dayTime(request.startsAt)).lineLimit(1)
            }
            .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
            FlowLayout(spacing: 12) {
                Chip(text: L("Online"), tone: .online, icon: "globe")
                if request.atHome == true {
                    HStack(spacing: 4) { Glyph("map-pin", size: 12); Text(L("At the family’s home")) }
                }
                if let release = StaysWords.releaseIn(request.releasesAt) {
                    HStack(spacing: 4) { Glyph("clock-3", size: 12); Text(LF("Released %@", release)) }
                        .fontWeight(soon ? .bold : .regular)
                        .foregroundStyle(soon ? Theme.destructive : Theme.inkSoft)
                }
            }
            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            if let notes = request.notes?.nonEmpty { Text("“\(notes)”").font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(2) }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(Theme.mix(ProviderState.waiting.color, 70, with: Theme.borderSoft), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
    }

    // MARK: Families' requests

    @ViewBuilder
    private func group(_ title: String, _ hint: String?, _ requests: [StaysRequest]) -> some View {
        if !requests.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    StaysEyebrow(text: title)
                    if let hint { Text(hint).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(requests) { request in
                        Button { focused = request } label: { StaysRequestCard(request: request) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func load() async {
        let location = workspace.locationId
        do {
            let list: StaysRequestList = try await API.get("/provider-requests", query: ["scope": "open", "locationId": location])
            open = (list.items ?? []).filter { stayRequestKinds.contains($0.kind) }
            if showAnswered {
                let all: StaysRequestList? = try? await API.get("/provider-requests", query: ["scope": "all", "locationId": location])
                answered = (all?.items ?? []).filter { stayRequestKinds.contains($0.kind) && !["pending", "proposed"].contains($0.status) }
            }
            if workspace.can(.appointmentsView) {
                online = try? await API.get("/provider-online-booking/requests", query: ["locationId": location])
            }
            if let current = focused { focused = (open + answered).first { $0.id == current.id } ?? current }
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = errorText(error)
        }
        loaded = true
    }
}

private struct StaysRequestCard: View {
    let request: StaysRequest

    var body: some View {
        let status = StaysWords.requestStatus(request)
        let vaccineIssues = (request.pets ?? []).reduce(0) { $0 + ($1.vaccines ?? []).filter { $0.status != "current" }.count }
        Card(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(icon: StaysWords.requestKindIcon(request.kind), accent: Theme.blue, size: 40, iconSize: 20, ink: .accent, washPercent: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(request.petNames).font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text("\(request.clientName ?? L("A family")) · \(StaysWords.requestKind(request.kind))").font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 4)
                StatusChip(text: status.0, state: status.1)
            }
            HStack(spacing: 8) {
                Glyph("calendar-range", size: 16).foregroundStyle(Theme.inkSoft)
                Text(StaysWords.requestRange(request.kind, request.startDay, request.endDay)).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                if let length = StaysWords.requestLength(request.kind, request.startDay, request.endDay) {
                    Text("· \(length)").font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
            if request.status == "proposed", let start = request.proposedStartDay {
                Text(LF("You proposed %@", StaysWords.requestRange(request.kind, start, request.proposedEndDay ?? start))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
            if let notes = request.notes?.nonEmpty { Text("“\(notes)”").font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(2) }
            if vaccineIssues > 0 || (request.depositPercent ?? 0) > 0 {
                FlowLayout(spacing: 8) {
                    if vaccineIssues > 0 { Chip(text: LP(vaccineIssues, "%d vaccine to check", "%d vaccines to check"), tone: .danger, icon: "syringe") }
                    if let deposit = request.depositPercent, deposit > 0 { Chip(text: LF("Deposit %d%%", deposit), tone: .warn, icon: "wallet") }
                }
            }
        }
    }
}

// MARK: - One request

private enum StaysAnswerMode: Hashable { case confirm, propose, decline }

private struct StaysRequestSheet: View {
    let request: StaysRequest
    let onOpenStay: (String) -> Void

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var mode: StaysAnswerMode = .confirm
    @State private var working = false
    // Confirm a stay
    @State private var units: [StaysUnit] = []
    @State private var rangeStays: [StaysStay] = []
    @State private var settings: StaysSettings?
    @State private var unitId: String?
    @State private var rate: Int?
    @State private var message = ""
    // Confirm a home stay
    @State private var plan = StaysHomePlan()
    @State private var sitterId = ""
    @State private var sitters: [StaysMember] = []
    @State private var sendQuote = false
    @State private var conflict = false
    @State private var bookAnyway = false
    // Confirm a program's sessions
    @State private var services: [StaysProgramService] = []
    @State private var serviceId = ""
    @State private var members: [StaysMember] = []
    @State private var memberId = ""
    @State private var firstDay = ""
    @State private var sessionTime = "09:00"
    @State private var sessions = 1
    @State private var duration = 60
    // Other dates
    @State private var startDay = ""
    @State private var endDay = ""
    // Decline
    @State private var reason = ""
    @State private var started = false

    private var expired: Bool { request.shownStatus == "expired" }
    private var canAnswer: Bool {
        request.status == "pending" && (request.kind == "program" ? workspace.can(.appointmentsCreate) : workspace.can(.staysManage))
    }

    var body: some View {
        let status = StaysWords.requestStatus(request)
        ProviderModal(title: "\(StaysWords.requestKind(request.kind)) · \(request.petNames)",
                      subtitle: "\(request.clientName ?? L("A family")) · \(StaysWords.requestRange(request.kind, request.startDay, request.endDay))",
                      systemImage: StaysWords.requestKindIcon(request.kind), accent: .aqua, isDirty: !message.isEmpty || !reason.isEmpty, form: form,
                      primaryTitle: answerTitle, primaryVariant: mode == .decline ? .destructive : .primary,
                      isWorking: working, cancelTitle: canAnswer ? L("Cancel") : L("Close"), primaryIcon: answerIcon, onPrimary: answerAction) {
            HStack(spacing: 8) {
                StatusChip(text: status.0, state: status.1)
                if let created = request.createdAt { Text(LF("Asked %@", StaysDay.short(String(created.prefix(10))))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
            }
            facts
            if request.isStayKind && (request.pets ?? []).contains(where: { !($0.vaccines ?? []).isEmpty }) { vaccines }
            outcome
            if canAnswer {
                // The answer in its own bordered box (web: a card under the facts), the three answers as one
                // switch (web AnswerModeSwitch): icons on a phone, words beside them on the chosen one.
                Card(padding: 16, spacing: 20, flat: true) {
                    Segmented(options: (expired ? [] : [Segmented<StaysAnswerMode>.Option(.confirm, mode == .confirm ? L("Confirm") : "", icon: "check")])
                              + [Segmented<StaysAnswerMode>.Option(.propose, mode == .propose ? L("Other dates") : "", icon: "calendar-clock"),
                                 Segmented<StaysAnswerMode>.Option(.decline, mode == .decline ? L("Decline") : "", icon: "circle-x")],
                              selection: $mode, label: L("Answer"))
                    switch mode {
                    case .confirm:
                        if request.isStayKind { confirmStayForm }
                        else if request.kind == "homestay" { confirmHomeForm }
                        else { confirmProgramForm }
                    case .propose: proposeForm
                    case .decline: declineForm
                    }
                }
            } else if request.status == "pending" {
                Text(L("Someone with access to book this can answer it.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
        }
        .task { await start() }
        .onChange(of: sitterId) { _, _ in conflict = false; bookAnyway = false }
    }

    private var answerTitle: String? { canAnswer ? primaryTitle : nil }

    /// Web: a check on every answer, a send on a quote.
    private var answerIcon: String? {
        guard canAnswer else { return nil }
        return mode == .confirm && request.kind == "homestay" && sendQuote && !conflict ? "send" : "check"
    }

    private var answerAction: (() -> Void)? {
        guard canAnswer else { return nil }
        return { submit() }
    }

    private var primaryTitle: String {
        switch mode {
        case .confirm: request.kind == "homestay" ? (conflict ? L("Book anyway") : sendQuote ? L("Send quote") : L("Confirm and book")) : L("Confirm and book")
        case .propose: L("Send these dates")
        case .decline: L("Decline request")
        }
    }

    // MARK: What was asked

    private var facts: some View {
        ModalSection(title: L("What they asked for")) {
            FactRow(label: request.kind == "program" ? L("Start") : L("Dates"),
                    value: StaysWords.requestRange(request.kind, request.startDay, request.endDay) + (StaysWords.requestLength(request.kind, request.startDay, request.endDay).map { " · \($0)" } ?? ""))
            if request.familyAcceptedAt != nil {
                Text(L("The family accepted these dates you proposed.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.blueText)
            }
            FactRow(label: L("Family"), value: request.clientName ?? L("A family"))
            if let phone = request.clientPhone?.nonEmpty { PhoneLink(phone: phone) }
            if let address = request.address?.nonEmpty { FactRow(label: L("Where"), value: address) }
            if let program = request.program?.nonEmpty { FactRow(label: L("What they are looking for"), value: program) }
            if let deposit = request.depositPercent, deposit > 0 {
                FactRow(label: L("Deposit"), value: LF("%d%% of the stay, as your store settings ask. Take it from the stay once it is confirmed.", deposit))
            }
            if let place = request.location?.name { FactRow(label: L("Location"), value: place) }
            if let notes = request.notes?.nonEmpty { StaysNoteBlock(label: L("Notes"), text: "“\(notes)”") }
        }
    }

    private var vaccines: some View {
        ModalSection(title: L("Vaccines"), subtitle: L("Against your stay rules, from what the family and your records show. You can confirm a paper certificate at check-in.")) {
            ForEach(Array((request.pets ?? []).enumerated()), id: \.offset) { _, pet in
                VStack(alignment: .leading, spacing: 8) {
                    Text(pet.name ?? "").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    if (pet.vaccines ?? []).isEmpty { Text(L("None required for this pet.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                    ForEach(pet.vaccines ?? [], id: \.key) { vaccine in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(StaysWords.vaccine(vaccine.key)).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                                Text(vaccine.matchedName.map { name in name + (vaccine.validUntil.map { " · " + LF("valid until %@", StaysDay.format(String($0.prefix(10)), "dMMMyyyy")) } ?? "") } ?? L("No record found"))
                                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            StatusChip(text: StaysWords.vaccineStatus(vaccine.status), state: ProviderState.vaccine(vaccine.status))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var outcome: some View {
        switch request.status {
        case "proposed":
            let start = request.proposedStartDay ?? request.startDay
            NoticeCard(tone: .info, title: LF("You proposed %@", StaysWords.requestRange(request.kind, start, request.proposedEndDay ?? start)),
                       message: (request.providerMessage?.nonEmpty.map { "“\($0)” " } ?? "") + L("Waiting for the family to accept or cancel."))
        case "declined":
            NoticeCard(tone: .problem, title: L("Declined"), message: request.providerMessage.map { "“\($0)”" })
        case "cancelled":
            NoticeCard(tone: .info, title: L("The family cancelled this request"))
        case "confirmed":
            VStack(alignment: .leading, spacing: 8) {
                NoticeCard(tone: .success, title: L("Confirmed"),
                           message: (request.appointmentIds ?? []).isEmpty ? nil : LP((request.appointmentIds ?? []).count, "%d visit booked.", "%d visits booked."))
                FlowLayout(spacing: 6) {
                    ForEach(Array((request.stayIds ?? []).enumerated()), id: \.offset) { index, stayId in
                        PMButton((request.stayIds ?? []).count == 1 ? L("Open the stay") : LF("Day %d", index + 1), systemImage: "bed-double", variant: .outline, size: .compact) {
                            dismiss()
                            onOpenStay(stayId)
                        }
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: Answers

    private struct RoomChoice: Identifiable { let unit: StaysUnit; let detail: String; let available: Bool; var id: String { unit.id } }

    private var roomChoices: [RoomChoice] {
        let kind = request.kind
        let species = (request.pets ?? []).map { ($0.species ?? "").lowercased() }
        let petCount = max(1, (request.pets ?? []).count)
        return units.map { unit in
            let wrongSpecies = species.contains { unit.species != "any" && !$0.isEmpty && $0 != unit.species }
            let tooSmall = (request.pets ?? []).count > unit.seats
            let days: [String] = kind == "daycare"
                ? (0...max(0, min(30, StaysDay.between(request.startDay, request.endDay)))).map { StaysDay.add(request.startDay, $0) }
                : [request.startDay]
            let fullOn = days.lazy.compactMap { day in
                StaysDay.firstFullDay(capacity: unit.seats, stays: rangeStays, unitId: unit.id, kind: kind, from: day, to: kind == "daycare" ? day : request.endDay, pets: petCount)
            }.first
            let unitRate = kind == "daycare" ? unit.dayRateCents : unit.nightlyRateCents
            let detail = wrongSpecies ? L("Not for this species")
                : tooSmall ? LF("Holds %d", unit.seats)
                : fullOn.map { LF("Full on %@", StaysDay.short($0)) }
                ?? "\(StaysWords.unitKind(unit.kind)) · \(Money.format(unitRate, currency: settings?.currency))"
            return RoomChoice(unit: unit, detail: detail, available: !wrongSpecies && !tooSmall && fullOn == nil)
        }
    }

    @ViewBuilder
    private var confirmStayForm: some View {
        FormField(label: L("Room")) {
            // A room that doesn't fit says why and stays unchosen.
            ChoiceCards(options: [(value: Optional<String>.none, title: L("Decide later"), subtitle: Optional(L("Assign a room before arrival")))]
                        + roomChoices.map { (value: Optional($0.unit.id), title: $0.unit.name, subtitle: Optional($0.detail)) },
                        selection: Binding(get: { unitId }, set: { id in
                            if let id, let choice = roomChoices.first(where: { $0.unit.id == id }), !choice.available { Toast.error(choice.detail) } else { unitId = id }
                        }))
        }
        MoneyField(label: request.kind == "daycare" ? L("Price per pet per day") : L("Price per pet per night"), cents: $rate,
                   hint: L("The room’s rate"))
        PMTextField(L("A line for the family (optional)"), text: $message, prompt: L("e.g. See you on Friday!"))
        if request.kind == "daycare" && request.startDay != request.endDay {
            Text(L("Daycare is booked as one day stay per day.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
    }

    @ViewBuilder
    private var confirmHomeForm: some View {
        MenuField(label: L("Sitter"), options: [(value: "", title: L("Decide later"))] + sitters.map { (value: $0.id, title: $0.label) }, selection: $sitterId, key: "sitter", form: form)
        if request.address?.nonEmpty == nil {
            NoticeCard(tone: .warning, title: L("The family didn’t say where. The home stay uses the family’s default address; add one on the client if they have none."))
        }
        StaysHomePlanForm(plan: $plan, lockDays: true, form: form)
        PMTextField(L("A line for the family (optional)"), text: $message)
        if conflict { StaysHomeTeam.conflictNotice(confirmed: $bookAnyway) }
        ToggleRow(title: L("Send as a quote"), subtitle: L("The family accepts it in the app"), isOn: $sendQuote)
    }

    /// A program's sessions: the first, then one a week (family-requests.ts programVisits).
    private var programVisits: [[String: Any?]] {
        (0..<max(1, min(12, sessions))).map { index in
            ["date": StaysDay.add(firstDay, index * 7), "startTime": sessionTime, "durationMinutes": duration]
        }
    }

    @ViewBuilder
    private var confirmProgramForm: some View {
        MenuField(label: L("Service"), options: services.isEmpty ? [(value: "", title: StaysWords.requestKind(request.kind))] : services.map { (value: $0.id, title: $0.label ?? "") },
                  selection: Binding(get: { serviceId }, set: { id in
                      serviceId = id
                      if let minutes = services.first(where: { $0.id == id })?.defaultDurationMinutes?.int, minutes > 0 { duration = minutes }
                  }))
        MenuField(label: L("Who goes"), options: [(value: "", title: L("Decide later"))] + members.map { (value: $0.id, title: $0.label) }, selection: $memberId)
        DayField(label: L("First session"), day: $firstDay, min: StaysDay.today(), key: "firstSession", form: form)
        TimeField(label: L("Time"), value: $sessionTime, from: "06:00", to: "22:00")
        MenuField(label: L("Weekly sessions"), options: (1...12).map { (value: $0, title: "\($0)") }, selection: $sessions)
        MenuField(label: L("Length of each visit"), options: Array(Set([30, 45, 60, 90, 120, 180, 240, 480, 720, duration])).sorted().map { (value: $0, title: StaysHomePlanForm.minutesText($0)) }, selection: $duration)
        PMTextField(L("A line for the family (optional)"), text: $message)
        let total = programVisits.count * max(1, (request.pets ?? []).count)
        (Text(total == 1 ? L("1 visit will be booked.") : LF("%d visits will be booked.", total))
         + Text((request.pets ?? []).count > 1 ? " " + L("One per pet, at the same time.") : "").foregroundColor(Theme.inkSoft))
            .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
    }

    @ViewBuilder
    private var proposeForm: some View {
        let single = request.kind == "program"
        DayField(label: single ? L("Start") : request.kind == "boarding" ? L("Check-in") : L("From"), day: Binding(get: { startDay }, set: { value in
            startDay = value
            let gap = request.kind == "boarding" ? 1 : 0
            if endDay < value || (request.kind == "boarding" && endDay <= value) { endDay = StaysDay.add(value, gap) }
            form.clear("dates")
        }), min: StaysDay.today(), key: "dates", form: form)
        if !single {
            DayField(label: request.kind == "boarding" ? L("Check-out") : L("Last day"), day: $endDay, min: startDay)
        }
        PMTextField(L("A line for the family (optional)"), text: $message, prompt: L("e.g. We are full that weekend, the next one is free."), multiline: true)
    }

    @ViewBuilder
    private var declineForm: some View {
        FlowLayout(spacing: 6) {
            ForEach(["We are full on those dates.", "We can’t take this pet.", "We don’t offer that at the moment."], id: \.self) { quick in
                FilterChip(title: L(quick), isSelected: reason == L(quick)) { reason = L(quick); form.clear("reason") }
            }
        }
        PMTextField(L("Why (the family reads this)"), text: $reason, key: "reason", form: form, multiline: true)
    }

    // MARK: Work

    private func start() async {
        guard !started else { return }
        started = true
        mode = expired ? .propose : .confirm
        let today = StaysDay.today()
        startDay = request.startDay < today ? today : request.startDay
        endDay = request.endDay < today ? StaysDay.add(today, request.kind == "boarding" ? 1 : 0) : request.endDay
        // An overnight stay needs a night: a one-day request is planned as visits.
        plan = StaysHomePlan(day: request.startDay, mode: request.endDay > request.startDay ? "overnight" : "visits")
        plan.checkInDay = request.startDay
        plan.checkOutDay = request.endDay
        guard canAnswer else { return }
        if request.isStayKind {
            async let unitsCall: [StaysUnit]? = try? await API.get("/provider-stays/units", query: ["locationId": workspace.locationId])
            async let settingsCall: StaysSettings? = try? await API.get("/provider-stays/settings")
            async let rangeCall: StaysPage? = try? await API.get("/provider-stays", query: ["from": request.startDay, "to": request.endDay, "locationId": workspace.locationId])
            units = (await unitsCall) ?? []
            settings = await settingsCall
            rangeStays = (await rangeCall)?.items ?? []
        } else if request.kind == "homestay", let clinic = workspace.current?.clinicId {
            let members: [StaysMember]? = try? await API.get("/provider-workspaces/\(clinic)/members")
            sitters = (members ?? []).filter(\.canCare)
        } else if request.kind == "program" {
            firstDay = startDay
            let catalog: StaysProgramCatalog? = try? await API.get("/appointment-services", query: ["scope": "provider"])
            services = (catalog?.services ?? []).filter { $0.category == "trainer" }
            if let first = services.first {
                serviceId = first.id
                if let minutes = first.defaultDurationMinutes?.int, minutes > 0 { duration = minutes }
            }
            members = await StaysHomeTeam.members().filter { $0.status != "suspended" }
        }
    }

    private func submit() {
        switch mode {
        case .confirm:
            if request.isStayKind { confirmStay() }
            else if request.kind == "homestay" { confirmHome() }
            else { confirmProgram() }
        case .propose: propose()
        case .decline: decline()
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        working = true
        Task {
            defer { working = false }
            do {
                try await work()
                announceDataChanged()
                dismiss()
            } catch let api as APIError where api.code == "visit_conflict" {
                conflict = true
                bookAnyway = false
            } catch {
                let text = request.kind == "homestay" && mode == .confirm ? StaysWords.homeError(error, fallback: "Something went wrong. Try again.") : StaysWords.requestError(error)
                Toast.error(text)
            }
        }
    }

    private func confirmProgram() {
        guard form.check([("firstSession", firstDay < StaysDay.today() ? L("Choose a date from today on.") : nil)]) else { return }
        run {
            try await API.send("POST", "/provider-requests/\(request.id)/confirm", body: [
                "serviceId": serviceId.nonEmpty, "memberId": memberId.nonEmpty, "visits": programVisits, "message": message.nonEmpty,
            ])
            Toast.show(L("Confirmed. The visits are in the schedule and the family has been told."))
        }
    }

    private func confirmStay() {
        run {
            try await API.send("POST", "/provider-requests/\(request.id)/confirm", body: ["unitId": unitId, "rateCents": rate, "message": message.nonEmpty])
            Toast.show(L("Confirmed. The family has been told."))
        }
    }

    private func confirmHome() {
        if conflict && !bookAnyway {
            Toast.error(L("The sitter is busy then. Check the warning and book it anyway if you meant to."))
            return
        }
        guard form.check(plan.problems) else { return }
        run {
            var home: [String: Any?] = [
                "mode": plan.mode, "plan": plan.planBody, "checkInTime": plan.checkInTime, "checkOutTime": plan.checkOutTime,
                "priceUnit": plan.priceUnit, "catalogItemId": plan.catalogItemId, "vetAuthorizationCents": plan.vetAuthorization,
                "houseRules": plan.houseRules.nonEmpty, "houseTasks": plan.houseTasksBody, "meetGreet": plan.meetGreetBody(sitterId: sitterId.nonEmpty),
                "sendQuote": sendQuote,
            ]
            if let deposit = plan.deposit { home["depositCents"] = deposit }
            if bookAnyway { home["allowDoubleBooking"] = true }
            var body: [String: Any?] = ["memberId": sitterId.nonEmpty, "message": message.nonEmpty, "homestay": home]
            if let rate = plan.rate { body["rateCents"] = rate }
            try await API.send("POST", "/provider-requests/\(request.id)/confirm", body: body)
            Toast.show(sendQuote ? L("Quote sent. The family answers it in the app.") : L("Confirmed. The home stay is booked and the family has been told."))
        }
    }

    private func propose() {
        let end = request.kind == "program" ? startDay : endDay
        var problem: String?
        if startDay < StaysDay.today() { problem = L("Choose a date from today on.") }
        else if end < startDay { problem = L("Choose valid dates, the first one before the last.") }
        else if request.kind == "boarding" && end == startDay { problem = L("A hotel stay needs at least one night.") }
        guard form.check([("dates", problem)]) else { return }
        run {
            try await API.send("POST", "/provider-requests/\(request.id)/propose", body: ["startDay": startDay, "endDay": end, "message": message.nonEmpty])
            Toast.show(L("Dates sent to the family."))
        }
    }

    private func decline() {
        guard form.check([("reason", reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 ? L("Tell the family why.") : nil)]) else { return }
        run {
            try await API.send("POST", "/provider-requests/\(request.id)/decline", body: ["reason": reason.trimmingCharacters(in: .whitespacesAndNewlines)])
            Toast.show(L("Declined. The family has been told why."))
        }
    }
}
