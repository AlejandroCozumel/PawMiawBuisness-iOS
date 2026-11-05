//
//  HomeRequests.swift
//  PawMiawNegocios
//
//  Families' requests answered from Home (web requests/provider-requests.tsx,
//  backend docs/family-requests.md). Hotel stays, daycare and home stays are
//  the Stays module's own list and sheets (`StaysRequestsView`), and the
//  online bookings beside them answer on their visit. A program (training
//  sessions) is answered here: confirm by booking its weekly sessions,
//  propose another start or decline with a reason; the family is told.
//

import SwiftUI

/// The programs families asked for, as cards that open their answer.
struct HomeProgramRequests: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var open: [StaysRequest] = []
    @State private var answered: [StaysRequest] = []
    @State private var showAnswered = false
    @State private var focused: StaysRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            group(L("Programs waiting for you"), open.filter { $0.shownStatus == "pending" })
            group(L("Programs waiting for the family"), open.filter { $0.shownStatus == "proposed" })
            group(L("Programs with dates passed"), open.filter { $0.shownStatus == "expired" })
            if !open.isEmpty || !answered.isEmpty {
                PMButton(showAnswered ? L("Hide answered programs") : L("Show answered programs"), variant: .outline, size: .compact) { showAnswered.toggle() }
            }
            if showAnswered { group(L("Answered programs"), answered) }
        }
        .reloadsOnScope { await load() }
        .onChange(of: showAnswered) { _, _ in Task { await load() } }
        .sheet(item: $focused) { HomeProgramRequestSheet(request: $0) }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [StaysRequest]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                StaysEyebrow(text: title)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 10, alignment: .top)], spacing: 10) {
                    ForEach(items) { request in
                        Button { focused = request } label: { HomeProgramCard(request: request) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func load() async {
        let location = workspace.locationId
        let list: StaysRequestList? = try? await API.get("/provider-requests", query: ["scope": "open", "locationId": location])
        open = (list?.items ?? []).filter { $0.kind == "program" }
        if showAnswered {
            let all: StaysRequestList? = try? await API.get("/provider-requests", query: ["scope": "all", "locationId": location])
            answered = (all?.items ?? []).filter { $0.kind == "program" && !["pending", "proposed"].contains($0.status) }
        }
        if let current = focused { focused = (open + answered).first { $0.id == current.id } ?? current }
    }
}

private struct HomeProgramCard: View {
    let request: StaysRequest

    var body: some View {
        let status = StaysWords.requestStatus(request)
        Card {
            HStack(alignment: .top, spacing: 10) {
                Glyph(StaysWords.requestKindIcon(request.kind), size: 20).foregroundStyle(Theme.blue)
                    .frame(width: 40, height: 40).background(Theme.wash(Theme.blue, 14), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.petNames).font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text("\(request.clientName ?? L("A family")) · \(StaysWords.requestKind(request.kind))").font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 4)
                StatusChip(text: status.0, state: status.1)
            }
            HStack(spacing: 8) {
                Glyph("calendar-range", size: 16).foregroundStyle(Theme.inkSoft)
                Text(StaysWords.requestRange(request.kind, request.startDay, request.endDay)).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
            }
            if request.status == "proposed", let start = request.proposedStartDay {
                Text(LF("You proposed %@", StaysWords.requestRange(request.kind, start, request.proposedEndDay ?? start))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
            if let program = request.program?.nonEmpty { Text(program).font(Theme.smallFont).foregroundStyle(Theme.inkStrong).lineLimit(2) }
            if let notes = request.notes?.nonEmpty { Text("“\(notes)”").font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(2) }
        }
    }
}

private enum HomeAnswerMode: Hashable { case confirm, propose, decline }

/// One program request: what was asked, and the three answers.
struct HomeProgramRequestSheet: View {
    let request: StaysRequest

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var mode: HomeAnswerMode = .confirm
    @State private var services: [SchedCatalogService] = []
    @State private var members: [SchedMember] = []
    @State private var serviceId = ""
    @State private var memberId = ""
    @State private var firstDay = ""
    @State private var time = "09:00"
    @State private var sessions = 1
    @State private var duration = 60
    @State private var message = ""
    @State private var startDay = ""
    @State private var reason = ""
    @State private var working = false
    @State private var started = false

    private static let lengths = [30, 45, 60, 90, 120, 180, 240, 480, 720]

    private var expired: Bool { request.shownStatus == "expired" }
    private var canAnswer: Bool { request.status == "pending" && workspace.can(.appointmentsCreate) }

    private var modalTitle: String { "\(StaysWords.requestKind(request.kind)) · \(request.petNames)" }
    private var modalSubtitle: String { "\(request.clientName ?? L("A family")) · \(StaysWords.requestRange(request.kind, request.startDay, request.endDay))" }
    private var answer: (() -> Void)? { canAnswer ? { submit() } : nil }
    private var answerOptions: [Segmented<HomeAnswerMode>.Option] {
        var options: [Segmented<HomeAnswerMode>.Option] = expired ? [] : [.init(.confirm, L("Confirm"), icon: "check")]
        options.append(.init(.propose, L("Other dates"), icon: "calendar-clock"))
        options.append(.init(.decline, L("Decline"), icon: "circle-x"))
        return options
    }

    var body: some View {
        let status = StaysWords.requestStatus(request)
        let variant: ButtonVariant = mode == .decline ? .destructive : .primary
        ProviderModal(title: modalTitle, subtitle: modalSubtitle, systemImage: StaysWords.requestKindIcon(request.kind), accent: .aqua,
                      isDirty: !message.isEmpty || !reason.isEmpty, form: form, primaryTitle: canAnswer ? primaryTitle : nil, primaryVariant: variant,
                      isWorking: working, cancelTitle: canAnswer ? L("Cancel") : L("Close"), onPrimary: answer) {
            StatusChip(text: status.0, state: status.1)
            ModalSection(title: L("What they asked for")) {
                FactRow(label: L("Start"), value: StaysWords.requestRange(request.kind, request.startDay, request.endDay))
                if request.familyAcceptedAt != nil {
                    Text(L("The family accepted these dates you proposed.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.blueText)
                }
                FactRow(label: L("Family"), value: request.clientName ?? L("A family"))
                if let phone = request.clientPhone?.nonEmpty { PhoneLink(phone: phone) }
                if let program = request.program?.nonEmpty { FactRow(label: L("What they are looking for"), value: program) }
                if let place = request.location?.name { FactRow(label: L("Location"), value: place) }
                if let notes = request.notes?.nonEmpty { StaysNoteBlock(label: L("Notes"), text: "“\(notes)”") }
            }
            outcome
            if canAnswer {
                // The web's answer panel: the three answers as one switch (the online bookings' too), on a pale blue card.
                VStack(alignment: .leading, spacing: 16) {
                    Segmented(options: answerOptions, selection: $mode, label: L("Answer"))
                    switch mode {
                    case .confirm: confirmForm
                    case .propose: proposeForm
                    case .decline: declineForm
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(Theme.blue, 5), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            } else if request.status == "pending" {
                Text(L("Someone with access to book this can answer it.")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
            }
        }
        .presentationDetents([.large])
        .task { await start() }
    }

    private var primaryTitle: String {
        switch mode {
        case .confirm: L("Confirm and book")
        case .propose: L("Send these dates")
        case .decline: L("Decline request")
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
            NoticeCard(tone: .success, title: L("Confirmed"), message: (request.appointmentIds ?? []).isEmpty ? nil : LP((request.appointmentIds ?? []).count, "%d visit booked.", "%d visits booked."))
        default:
            EmptyView()
        }
    }

    private var visits: [[String: Any]] {
        (0..<max(1, min(12, sessions))).map { index in
            ["date": StaysDay.add(firstDay, index * 7), "startTime": time, "durationMinutes": duration]
        }
    }

    private var serviceOptions: [(value: String, title: String)] {
        if services.isEmpty { return [(value: "", title: StaysWords.requestKind(request.kind))] }
        return services.map { (value: $0.id, title: $0.label) }
    }

    private var memberOptions: [(value: String, title: String)] {
        [(value: "", title: L("Decide later"))] + members.map { (value: $0.id, title: $0.label) }
    }

    private var sessionOptions: [(value: Int, title: String)] { (1...12).map { (value: $0, title: String($0)) } }

    private var lengthOptions: [(value: Int, title: String)] {
        Array(Set(Self.lengths + [duration])).sorted().map { (value: $0, title: Self.minutesLabel($0)) }
    }

    private var serviceBinding: Binding<String> {
        Binding(get: { serviceId }, set: { id in
            serviceId = id
            if let minutes = services.first(where: { $0.id == id })?.minutes { duration = minutes }
        })
    }

    private var totalLine: String {
        let pets = (request.pets ?? []).count
        let total = visits.count * max(1, pets)
        let first = total == 1 ? L("1 visit will be booked.") : LF("%d visits will be booked.", total)
        return pets > 1 ? first + " " + L("One per pet, at the same time.") : first
    }

    @ViewBuilder
    private var confirmForm: some View {
        MenuField(label: L("Service"), options: serviceOptions, selection: serviceBinding)
        MenuField(label: L("Who goes"), options: memberOptions, selection: $memberId)
        DayField(label: L("First session"), day: $firstDay, min: StaysDay.today(), key: "firstDay", form: form)
        TimeField(label: L("Time"), value: $time)
        MenuField(label: L("Weekly sessions"), options: sessionOptions, selection: $sessions)
        MenuField(label: L("Length of each visit"), options: lengthOptions, selection: $duration)
        PMTextField(L("A line for the family (optional)"), text: $message)
        Text(totalLine).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
    }

    @ViewBuilder
    private var proposeForm: some View {
        DayField(label: L("Start"), day: $startDay, min: StaysDay.today(), key: "dates", form: form)
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

    static func minutesLabel(_ minutes: Int) -> String {
        if minutes < 60 { return LF("%d min", minutes) }
        if minutes % 60 == 0 { return minutes == 60 ? L("1 hour") : LF("%d hours", minutes / 60) }
        return LF("%@ h", String(format: "%.1f", Double(minutes) / 60))
    }

    private func start() async {
        guard !started else { return }
        started = true
        mode = expired ? .propose : .confirm
        let today = StaysDay.today()
        firstDay = request.startDay < today ? today : request.startDay
        startDay = firstDay
        guard canAnswer else { return }
        async let catalogCall = SchedData.catalog()
        async let teamCall = SchedData.members()
        let catalog = await catalogCall
        services = (catalog?.services ?? []).filter { $0.category == "trainer" }
        members = (await teamCall).filter { $0.status != "suspended" }
        if serviceId.isEmpty, let first = services.first {
            serviceId = first.id
            if let minutes = first.minutes { duration = minutes }
        }
    }

    private func submit() {
        switch mode {
        case .confirm:
            guard form.check([("firstDay", firstDay < StaysDay.today() ? L("Choose a date from today on.") : nil)]) else { return }
            run(success: L("Confirmed. The visits are in the schedule and the family has been told.")) {
                try await API.send("POST", "/provider-requests/\(request.id)/confirm", body: [
                    "serviceId": serviceId.nonEmpty, "memberId": memberId.nonEmpty, "visits": visits, "message": message.nonEmpty,
                ])
            }
        case .propose:
            guard form.check([("dates", startDay < StaysDay.today() ? L("Choose a date from today on.") : nil)]) else { return }
            run(success: L("Dates sent to the family.")) {
                try await API.send("POST", "/provider-requests/\(request.id)/propose", body: ["startDay": startDay, "endDay": startDay, "message": message.nonEmpty])
            }
        case .decline:
            let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard form.check([("reason", why.count < 2 ? L("Tell the family why.") : nil)]) else { return }
            run(success: L("Declined. The family has been told why.")) {
                try await API.send("POST", "/provider-requests/\(request.id)/decline", body: ["reason": why])
            }
        }
    }

    private func run(success: String, _ work: @escaping @MainActor () async throws -> Void) {
        working = true
        Task {
            defer { working = false }
            do {
                try await work()
                Toast.show(success)
                announceDataChanged()
                dismiss()
            } catch {
                Toast.error(StaysWords.requestError(error))
            }
        }
    }
}
