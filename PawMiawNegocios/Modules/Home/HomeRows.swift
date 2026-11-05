//
//  HomeRows.swift
//  PawMiawNegocios
//
//  The rows of Home's board (web visit-row.tsx, home-hub.tsx, the session
//  row of today-board.tsx, hospital/arrivals-block.tsx): the 3 pt edge in
//  the state's colour, the time column with the state under it, who and
//  what, the facts as small chips, and the one next step. A row opens what
//  it is about; the "⋯" holds the rest. Check-in, finish, charging,
//  cancelling and rebooking are the Agenda's sheets, opened over Home.
//

import SwiftUI

// MARK: - A visit

struct HomeVisitRow: View {
    let visit: HomeVisit
    let together: [HomeVisit]
    let stateLabel: String
    let hospitalized: Bool
    let compact: Bool
    let permissions: HomePermissions
    let categories: [String]
    let open: (ProviderRoute) -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(HomeActions.self) private var actions: HomeActions?
    @State private var working = false
    @State private var topHeight: CGFloat = 0

    private enum Action {
        case navigate(String, String)
        case route(String, String, ProviderRoute)
        case call(String, String, () -> Void)
        case run(String, String, path: String, body: [String: Any?], success: String)
    }

    private var phone: Bool { sizeClass != .regular }
    private var tone: Color { HomeText.laneColor(visit) }
    private var clock: (text: String, color: Color)? { HomeText.clock(visit) }
    private var busy: Bool { working || (actions?.isBusy(visit.id) ?? false) }
    /// A row ahead of its arrival checks in on a tap; once they are here it opens the visit.
    private var checksInOnTap: Bool { visit.laneValue == .upcoming && permissions.checkIn && actions != nil }

    /// A groom under way says where it is ("En baño") instead of the generic state (lib/groom-stages.ts `groomStageInProgress`).
    private var groomState: (label: String, tone: Color)? {
        guard visit.status == "in_progress", visit.serviceCategory == nil || visit.serviceCategory == "groomer",
              let stage = visit.groomStage, ["bath", "styling", "ready"].contains(stage) else { return nil }
        let simple = actions?.simpleStages ?? false
        return (HomeText.groomStage(SvcGroomStage.shown(stage, simple: simple), simple: simple), ProviderState.groom(SvcGroomStage.shown(stage, simple: simple)).color)
    }

    var body: some View {
        EdgeRow(edge: tone, time: DateText.time(visit.startsAt), timeNote: clock?.text ?? groomState?.label ?? stateLabel,
                timeNoteColor: clock?.color ?? tone, dimmed: visit.laneValue == .missed || compact) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    avatar
                    details.frame(maxWidth: .infinity, alignment: .leading)
                    if !phone { actionLine }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
                // A phone: the step on its own line, under the words (indented past the time).
                if phone { actionLine }
            }
            // The time column stays centred on the row's first line, not on the step under it.
            .alignmentGuide(VerticalAlignment.center) { d in phone && topHeight > 0 ? topHeight / 2 : d[VerticalAlignment.center] }
        }
        .onTapGesture { openRow() }
        .accessibilityAction(named: checksInOnTap ? L("Check in@visit") : L("Open visit")) { openRow() }
    }

    private func openRow() {
        if checksInOnTap, let actions { actions.checkIn(visit.id) } else { open(.appointment(visit.id)) }
    }

    @ViewBuilder
    private var avatar: some View {
        if together.isEmpty {
            PetAvatar(name: visit.petName, species: visit.pet?.species, photoURL: visit.pet?.photoUrl, size: 40)
        } else {
            PetStack(pets: ([visit] + together).map { (name: $0.petName, species: $0.pet?.species, photo: $0.pet?.photoUrl) }, size: 40)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text(HomeText.names([visit.petName] + together.map(\.petName))).font(Theme.text(16, weight: .bold)).foregroundColor(Theme.inkStrong)
             + Text(" · " + (visit.serviceLabel ?? "")).font(Theme.text(16)).foregroundColor(Theme.inkSoft))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(people).font(Theme.text(12.8)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                if visit.client?.onPawMiaw == false && !compact {
                    Glyph("bell-off", size: 14)
                        .foregroundStyle(Theme.inkSoft)
                        .opacity(0.6)
                        .accessibilityLabel(L("Not on PawMiaw"))
                }
            }
            .padding(.top, 2)
            if !compact, let note = visit.arrivalNote?.nonEmpty, [.waiting, .inService].contains(visit.laneValue) {
                Text(note).font(Theme.text(12)).italic().foregroundStyle(Theme.inkSoft).lineLimit(1).padding(.top, 2)
            }
            let shown = chips
            if !shown.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(shown) { chip in chip.view }
                }
                .padding(.top, 6)
            }
        }
    }

    /// Who, with whom, where — plain text, not tags.
    private var people: String {
        let client = visit.client?.name ?? ""
        let assigned: String? = {
            if compact { return nil }
            guard let person = visit.assigned else { return L("Whoever is free") }
            let name = person.name ?? "—"
            return name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(client.trimmingCharacters(in: .whitespaces)) == .orderedSame ? nil : LF("with %@", name)
        }()
        return [client.nonEmpty, assigned, compact ? nil : visit.room?.nonEmpty].compactMap { $0 }.joined(separator: " · ")
    }

    private var chips: [HomeChipSpec] {
        var list: [HomeChipSpec] = []
        if compact {
            if visit.laneValue == .missed { list.append(.chip(visit.status == "no_show" ? L("No-show") : L("Cancelled@visit"), .danger)) }
            if visit.fee?.decision == "charged" { list.append(.chip(L("Fee charged"), .warn)) }
            if visit.fee?.decision == "waived" { list.append(.chip(L("Fee waived"), .muted)) }
            if visit.billing == "paid" {
                list.append(.chip((visit.invoice?.totalAmount ?? 1) == 0 ? L("Nothing to charge") : L("Paid@bill"), .good, icon: "circle-dollar-sign"))
            }
            if visit.billing == "no_charge" { list.append(.chip(L("No charge"), .good)) }
            if visit.laneValue == .done && (visit.notesCount?.drafts ?? 0) > 0 { list.append(.chip(L("Note to sign"), .warn, icon: "notebook-pen")) }
            if visit.bookedOnline == true { list.append(.chip(L("Online@booking"), .online, icon: "globe")) }
            return list
        }
        // The clock takes the state's place under the time, so a groom's stage is said here.
        if let groomState, clock != nil { list.append(.stage(groomState.label, groomState.tone, icon: "scissors")) }
        if let priority = visit.triagePriority, [.waiting, .inService, .upcoming].contains(visit.laneValue) {
            list.append(.chip(HomeTriage.label(priority).uppercased(), priority == "critical" ? .danger : (priority == "urgent" ? .warn : .good), icon: "siren"))
        }
        if let reason = visit.triageReason?.nonEmpty, [.waiting, .inService].contains(visit.laneValue) {
            list.append(.chip(reason, visit.triagePriority == "critical" ? .danger : .warn))
        }
        if visit.afterHours == true { list.append(.chip(L("After hours"), .info, icon: "moon")) }
        if let minutes = visit.pickupPassedMinutes {
            list.append(.chip(LF("Still in your care · pickup was %@ ago", HomeText.shortDuration(minutes)), .danger, icon: "clock"))
            if visit.familyAttendance == "attended" { list.append(.chip(L("The family says it is home"), .warn, icon: "house")) }
        }
        if hospitalized { list.append(.chip(L("Hospitalized"), .danger, icon: "hospital")) }
        if let allergies = visit.pet?.allergies, !allergies.isEmpty {
            list.append(.chip(LF("Allergy: %@", allergies.joined(separator: ", ")), .danger, icon: "triangle-alert"))
        }
        if visit.confirmationStatus == "reschedule_requested" { list.append(.chip(L("Asked to reschedule"), .warn)) }
        if visit.confirmationStatus == "cancellation_requested" { list.append(.chip(L("Asked to cancel"), .warn)) }
        if visit.bookedOnline == true { list.append(.chip(L("Online@booking"), .online, icon: "globe")) }
        if visit.hoursOverride == true { list.append(.chip(L("After hours"), .muted, icon: "moon-star")) }
        if (visit.notesCount?.drafts ?? 0) > 0 { list.append(.chip(L("Note to sign"), .warn, icon: "notebook-pen")) }
        if let bill = HomeText.billChip(visit) { list.append(.chip(bill.text, bill.tone, icon: "circle-dollar-sign")) }
        if visit.billing == "no_charge" { list.append(.chip(L("No charge"), .good)) }
        return list
    }

    // MARK: The next step

    /// One step per row: arrive, start, finish (or check out), price, collect, send to the desk, book again.
    private var primary: Action? {
        switch visit.laneValue {
        case .upcoming:
            guard permissions.checkIn else { return nil }
            if let actions { return .call(L("Check in@visit"), "arrow-right-to-line") { actions.checkIn(visit.id) } }
            return .navigate(L("Check in@visit"), "arrow-right-to-line")
        case .waiting:
            guard permissions.start else { return nil }
            if let actions { return .call(L("Start@visit"), "play") { actions.start(visit.id, petName: visit.petName) } }
            return .run(L("Start@visit"), "play", path: "/provider-appointments/\(visit.id)/start", body: [:], success: LF("%@ is in.", visit.petName))
        case .inService:
            // Whoever takes payments checks a visit out so it can be charged; the note stays with the visit's person.
            guard permissions.start || permissions.takePayment else { return nil }
            let title = permissions.start ? L("Finish@visit") : L("Check out@visit")
            let image = permissions.start ? "badge-check" : "log-out"
            if let actions { return .call(title, image) { actions.finish(visit.id) } }
            return .navigate(title, image)
        case .toPay:
            // The bill opens in Cuentas: price it, charge it, or send it to the desk — by permission, not role.
            if visit.billing == "needs_price" || visit.billing == "needs_bill" {
                guard permissions.price && permissions.billView else { return nil }
                return .route(L("Price it"), "clipboard-pen", visit.invoice.map { ProviderRoute.invoice($0.id) } ?? .appointment(visit.id))
            }
            guard let invoice = visit.invoice else { return nil }
            let draft = invoice.status == "draft"
            if permissions.takePayment && permissions.billView && (!draft || permissions.billSend) {
                let amount = draft ? (invoice.totalAmount ?? 0) - (invoice.amountPaid ?? 0) : (invoice.balanceDueAmount ?? 0)
                return .route(LF("Collect %@", Money.format(amount, currency: invoice.currency)), "hand-coins", .invoice(invoice.id))
            }
            if draft && permissions.billSend {
                return .run(L("Send to the desk"), "send", path: "/provider-invoices/\(invoice.id)/send-to-desk", body: [:], success: L("Sent to the desk to charge."))
            }
            return nil
        case .missed:
            guard permissions.edit else { return nil }
            if let actions { return .call(L("Book again"), "calendar-plus") { actions.rebook(visit.id) } }
            return .navigate(L("Book again"), "calendar-plus")
        case .done:
            return nil
        }
    }

    /// The step (an outline 36 pt button, the width of the line on a phone) and the "⋯".
    private var actionLine: some View {
        HStack(spacing: 4) {
            if let action = primary {
                actionView(action)
            } else if phone {
                Spacer(minLength: 0)
            }
            menu
        }
    }

    @ViewBuilder
    private func actionView(_ action: Action) -> some View {
        switch action {
        case .navigate(let title, let icon):
            NavigationLink(value: ProviderRoute.appointment(visit.id)) { PMButtonContent(title: title, icon: icon) }
                .buttonStyle(.pm(.outline, size: .header, fullWidth: phone))
        case .route(let title, let icon, let route):
            NavigationLink(value: route) { PMButtonContent(title: title, icon: icon) }
                .buttonStyle(.pm(.outline, size: .header, fullWidth: phone))
        case .call(let title, let icon, let action):
            PMButton(title, systemImage: icon, variant: .outline, size: .header, fullWidth: phone, isWorking: busy, action: action)
        case .run(let title, let icon, let path, let body, let success):
            PMButton(title, systemImage: icon, variant: .outline, size: .header, fullWidth: phone, isWorking: busy) {
                run(path, body: body, success: success, openOnRefusal: true)
            }
        }
    }

    private var menu: some View {
        Menu {
            Button { open(.appointment(visit.id)) } label: { GlyphLabel(L("Open visit"), icon: "stethoscope") }
            if permissions.clients, let clientId = visit.client?.id {
                Button { open(.client(clientId)) } label: { GlyphLabel(L("Open client"), icon: "user-round") }
            }
            if permissions.clients, let petId = visit.pet?.id {
                Button { open(.patientChart(petId: petId)) } label: { GlyphLabel(L("See chart"), icon: "paw-print") }
            }
            if let url = ContactLinks.phone(visit.client?.phone) {
                Button { openURL(url) } label: { GlyphLabel(LF("Call %@", NameText.firstName(visit.client?.name)), icon: "phone") }
            }
            if visit.laneValue == .waiting && permissions.checkIn {
                Button { move("undo-arrival", success: L("Back to upcoming.")) } label: { GlyphLabel(L("Undo arrival"), icon: "undo-2") }
            }
            if (visit.laneValue == .toPay || (visit.laneValue == .done && visit.invoice != nil)) && permissions.billView, let invoice = visit.invoice {
                Button { open(.invoice(invoice.id)) } label: { GlyphLabel(L("See the bill"), icon: "receipt") }
            }
            if visit.laneValue == .toPay && permissions.start && (visit.invoice?.amountPaid ?? 0) == 0 {
                Button { move("reopen", success: L("Back with the vet.")) } label: { GlyphLabel(L("Reopen visit"), icon: "rotate-ccw") }
            }
            if let actions {
                let late = visit.laneValue == .upcoming && permissions.checkIn && (visit.lateMinutes ?? 0) > 0
                let cancels = (visit.laneValue == .upcoming || visit.laneValue == .waiting) && permissions.cancel
                if late || cancels { Divider() }
                if late {
                    Button(role: .destructive) { actions.noShow(visit.id) } label: { GlyphLabel(L("They didn’t come"), icon: "triangle-alert") }
                }
                if cancels {
                    Button(role: .destructive) { actions.cancel(visit.id) } label: { GlyphLabel(L("Cancel visit"), icon: "triangle-alert") }
                }
            }
        } label: {
            IconCircleLabel(bordered: false)
        }
        .disabled(busy)
    }

    private func move(_ step: String, success: String) {
        let path = "/provider-appointments/\(visit.id)/\(step)"
        if let actions { actions.run(visit.id, path, success: success) } else { run(path, success: success) }
    }

    private func run(_ path: String, body: [String: Any?] = [:], success: String, openOnRefusal: Bool = false) {
        working = true
        Task {
            defer { working = false }
            do {
                try await API.send("POST", path, body: body)
                Toast.show(success)
                announceDataChanged()
            } catch {
                Toast.error(error)
                // A start that waits on a consent or a deposit is answered on the visit page.
                if openOnRefusal, (error as? APIError)?.isRefusal == true { open(.appointment(visit.id)) }
            }
        }
    }
}

/// One fact on a row: the kit's small chip, or a groom's stage pill.
enum HomeChipSpec: Identifiable {
    case chip(String, Chip.Tone, icon: String? = nil)
    case stage(String, Color, icon: String? = nil, count: Int? = nil)

    var id: String {
        switch self {
        case .chip(let text, _, let icon): "chip-\(text)-\(icon ?? "")"
        case .stage(let text, _, _, _): "stage-\(text)"
        }
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .chip(let text, let tone, let icon): Chip(text: text, tone: tone, icon: icon)
        case .stage(let text, let tone, let icon, let count): Chip(text: text, tone: .custom(tone), icon: icon, dot: icon == nil ? tone : nil, count: count)
        }
    }
}

enum HomeTriage {
    static func label(_ priority: String) -> String {
        switch priority {
        case "critical": L("Critical")
        case "urgent": L("Urgent@triage")
        case "stable": L("Stable")
        default: priority
        }
    }
}

// MARK: - A group walk or class

struct HomeSessionRow: View {
    let session: HomeSession
    let stateLabel: String

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(HomeActions.self) private var actions: HomeActions?
    @State private var opened = false
    @State private var topHeight: CGFloat = 0

    private var phone: Bool { sizeClass != .regular }

    /// It starts with whoever arrived; nobody marked yet is "take the register" in the session.
    private var next: String? {
        guard workspace.can(.appointmentsComplete) else { return nil }
        let staying = session.staying
        if staying.contains(where: { $0.status == "in_progress" }) { return "finish" }
        if staying.contains(where: { $0.status == "checked_in" }) { return "start" }
        if staying.contains(where: { $0.status == "scheduled" }) { return "register" }
        return nil
    }

    private var arrived: Int { session.staying.filter { $0.status == "checked_in" }.count }

    var body: some View {
        EdgeRow(edge: Theme.blue, time: DateText.time(session.startsAt), timeNote: stateLabel, timeNoteColor: Theme.blue) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    if session.staying.isEmpty {
                        HomeDisc(icon: "users", size: 40, iconSize: 16, fill: Theme.surfaceMuted, ink: Theme.inkSoft)
                    } else {
                        PetStack(pets: session.staying.map { (name: $0.name ?? "", species: $0.species, photo: $0.photoUrl) }, size: 40)
                    }
                    details.frame(maxWidth: .infinity, alignment: .leading)
                    if !phone, let next { step(next) }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
                if phone, let next { step(next) }
            }
            .alignmentGuide(VerticalAlignment.center) { d in phone && next != nil && topHeight > 0 ? topHeight / 2 : d[VerticalAlignment.center] }
        }
        .onTapGesture { opened = true }
        .navigationDestination(isPresented: $opened) { SvcSessionScreen(sessionId: session.id) }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text(session.serviceLabel ?? "").font(Theme.text(16, weight: .bold)).foregroundColor(Theme.inkStrong)
             + Text(" · " + places).font(Theme.text(16)).foregroundColor(Theme.inkSoft))
                .lineLimit(1)
            Text(session.staying.isEmpty ? L("Nobody here yet") : session.staying.compactMap(\.name).joined(separator: ", "))
                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            FlowLayout(spacing: 6) {
                Chip(text: L("Group session"), tone: .info, icon: "users")
                if let name = session.assignedMember?.name { Chip(text: name, icon: "user-round") }
                if let room = session.room?.nonEmpty { Chip(text: room, icon: "door-open") }
                if session.startMode == "pickup" {
                    Chip(text: L("Picked up at home"), icon: "house")
                } else if let point = session.meetingPoint?.nonEmpty {
                    Chip(text: point, icon: "map-pin")
                }
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func step(_ next: String) -> some View {
        let busy = actions?.isBusy(session.id) ?? false
        switch next {
        case "register":
            PMButton(L("Take the register"), systemImage: "list-checks", variant: .outline, size: .compact, fullWidth: phone) { opened = true }
        case "start":
            PMButton(session.startMode == "pickup" ? LF("Start the walk with %d", arrived) : LF("Start with those here (%d)", arrived), systemImage: "play", size: .header, fullWidth: phone, isWorking: busy) {
                actions?.moveSession(session.id, "start")
            }
        default:
            PMButton(L("Finish for everyone"), systemImage: "badge-check", size: .header, fullWidth: phone, isWorking: busy) {
                actions?.moveSession(session.id, "finish")
            }
        }
    }

    private var places: String {
        let size = session.size ?? session.staying.count
        if let capacity = session.capacity { return "\(size)/\(capacity)" }
        return "\(size)"
    }
}

// MARK: - Stays, hospital patients and home stays' visits

struct HomeHubSection: View {
    let module: HomeActivity
    let entries: [HomeHubEntry]
    let memberId: String?
    let showEmpty: Bool

    @Environment(HomeActions.self) private var actions: HomeActions?

    private var link: String {
        switch module {
        case .hospital: L("Open the hospital")
        case .home: L("Open home visits")
        default: L("Open stays")
        }
    }

    var body: some View {
        if entries.isEmpty {
            if showEmpty {
                VStack(spacing: 0) {
                    EmptyState(systemImage: module.icon, title: emptyTitle, message: emptyBody, accent: Theme.blue)
                    NavigationLink(value: ProviderRoute.section(module.section)) {
                        PMButtonContent(title: link, trailingIcon: "chevron-right", variant: .link, size: .slim)
                    }
                    .buttonStyle(.pm(.link, size: .slim))
                    .padding(.top, -12)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            HomeStrip(storageKey: module.rawValue, title: module.label, count: entries.count, dot: module.accent, linkTitle: link, link: openPage) {
                RowList(items: Array(entries.prefix(HomeCap.rows))) { entry in
                    HomeHubRow(entry: entry, memberId: memberId)
                }
                if entries.count > HomeCap.rows {
                    HomeStripMore(more: entries.count - HomeCap.rows, route: .section(module.section))
                }
            }
        }
    }

    /// The part's own page, from the strip's link.
    private var openPage: (() -> Void)? {
        guard let actions else { return nil }
        let section = module.section
        return { actions.route = .section(section) }
    }

    private var emptyTitle: String {
        switch module {
        case .hospital: L("Nobody in the hospital")
        case .home: L("No home visits today")
        default: L("Nothing in stays today")
        }
    }

    private var emptyBody: String {
        switch module {
        case .hospital: L("Admitted patients and those waiting for a bed show up here.")
        case .home: L("The day's visits to families' homes show up here.")
        default: L("Arrivals, pets in house and departures show up here.")
        }
    }
}

private struct HomeHubRow: View {
    let entry: HomeHubEntry
    let memberId: String?

    private var route: ProviderRoute {
        entry.module == "hospital" ? .hospitalization(entry.entityId ?? entry.id) : .stay(entry.entityId ?? entry.id)
    }

    private var kind: String {
        switch entry.kind {
        case "boarding": L("Boarding")
        case "daycare": L("Daycare")
        case "home_sitting": L("Home sitting")
        case "meet_greet": L("Meet & greet")
        case "visit": L("Home visit")
        case "overnight": L("Overnight")
        case "hospital": L("Hospitalized")
        default: entry.kind ?? ""
        }
    }

    /// The card's one-word state and its colour (home-hub.tsx `entryState`).
    private var state: (label: String, tone: Color) {
        if entry.module == "hospital" {
            return entry.status == "pending" ? (L("Waiting for admission"), Theme.mango) : (L("Admitted"), Theme.pink)
        }
        if entry.module == "home" && entry.kind != "home_sitting" {
            switch entry.status {
            case "in_progress": return (L("Under way"), Theme.blue)
            case "done": return (L("Done@hub"), Theme.inkSoft)
            case "missed": return (L("Missed@hub"), Theme.destructive)
            default: return entry.late == true ? (L("Running late"), Theme.destructive) : (L("Planned"), Theme.aqua)
            }
        }
        switch entry.status {
        case "confirmed": return entry.late == true ? (L("Late arrival"), Theme.destructive) : (L("Arriving"), Theme.aqua)
        case "leaving": return entry.late == true ? (L("Check-out past due"), Theme.destructive) : (L("Leaving today"), Theme.pink)
        case "checked_out": return (L("Left today"), Theme.inkSoft)
        default: return (L("In house"), Theme.blue)
        }
    }

    private var lateStay: Bool {
        entry.module != "hospital" && entry.late == true && (entry.status == "leaving" || entry.status == "confirmed")
    }

    /// The next thing on the clock, or the day a pet in house leaves; a stay a day late shows the day it was due.
    private var when: String {
        if let starts = entry.startsAt { return lateStay ? DateText.day(starts) : DateText.time(starts) }
        if let ends = entry.endsAt { return DateText.day(ends) }
        return "—"
    }

    private var details: String {
        [
            entry.clientName?.nonEmpty,
            entry.module == "hospital" && entry.startsAt != nil ? LF("Next dose %@", DateText.time(entry.startsAt)) : nil,
            entry.startsAt == nil && entry.endsAt != nil ? LF("Leaves %@", DateText.day(entry.endsAt)) : nil,
            entry.room?.nonEmpty,
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private var chips: [HomeChipSpec] {
        var list: [HomeChipSpec] = []
        if entry.module == "hospital", let attention = entry.attention, attention > 0 {
            list.append(.chip(attention == 1 ? L("1 treatment needs someone") : LF("%d treatments need someone", attention),
                              entry.late == true ? .danger : .warn, icon: entry.late == true ? "triangle-alert" : "clock-3"))
        }
        if lateStay, let starts = entry.startsAt {
            list.append(.chip(entry.status == "leaving" ? LF("Was due out %@ · still here", DateText.day(starts)) : LF("Was due in %@ · not here yet", DateText.day(starts)), .danger, icon: "triangle-alert"))
        }
        if entry.module == "home" && entry.kind != "home_sitting" && entry.assignedId == nil { list.append(.chip(L("Nobody assigned"), .info)) }
        if let assigned = entry.assignedId, assigned == memberId { list.append(.chip(L("Assigned to you"), .info)) }
        return list
    }

    var body: some View {
        let pets = entry.pets ?? []
        let names = pets.compactMap(\.name).joined(separator: ", ")
        let done = entry.status == "done" || entry.status == "checked_out"
        NavigationLink(value: route) {
            EdgeRow(edge: done ? Theme.borderSoft : state.tone, time: when, timeNote: state.label, timeNoteColor: state.tone, showsChevron: true, dimmed: done) {
                HStack(alignment: .center, spacing: 12) {
                    if pets.count > 1 {
                        PetStack(pets: pets.map { (name: $0.name ?? "", species: $0.species, photo: $0.photoUrl) }, size: 40)
                    } else {
                        PetAvatar(name: pets.first?.name ?? kind, species: pets.first?.species, photoURL: pets.first?.photoUrl, size: 40)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        (Text(names.isEmpty ? "—" : names).font(Theme.text(16, weight: .bold)).foregroundColor(Theme.inkStrong)
                         + Text(" · " + kind).font(Theme.text(16)).foregroundColor(Theme.inkSoft))
                            .lineLimit(1)
                        if !details.isEmpty {
                            Text(details).font(Theme.text(12.8)).foregroundStyle(Theme.inkSoft).lineLimit(1).padding(.top, 2)
                        }
                        let shown = chips
                        if !shown.isEmpty {
                            FlowLayout(spacing: 6) { ForEach(shown) { $0.view } }.padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(L("Open@needs")): \(names) · \(kind)")
    }
}

// MARK: - Grooming

/// The day's grooms by stage (web home-hub.tsx `GroomingSection`). Under Todos only the stage counts (the grooms
/// are agenda rows already); under Estética, every groom not handed over yet, with its next step.
struct HomeGroomingSection: View {
    let data: HomeGroomingToday?
    let full: Bool

    @Environment(HomeActions.self) private var actions: HomeActions?

    private static let rowOrder: [String: Int] = ["ready": 0, "styling": 1, "bath": 2, "waiting": 3, "scheduled": 4, "done": 5]

    private var simple: Bool { actions?.simpleStages ?? false }

    private var items: [HomeGroomItem] {
        (data?.items ?? []).filter { SvcGroomStage.all.contains($0.groomStage ?? "") }
    }

    private var open: [HomeGroomItem] {
        items.filter { $0.groomStage != "done" }.sorted {
            let a = Self.rowOrder[$0.groomStage ?? ""] ?? 9, b = Self.rowOrder[$1.groomStage ?? ""] ?? 9
            return a != b ? a < b : ($0.startsAt ?? "") < ($1.startsAt ?? "")
        }
    }

    /// Counted from the rows shown, so the pills and the list never disagree; simple stages fold cut & dry into the bath.
    private var counts: [(stage: String, count: Int)] {
        SvcGroomStage.visible(simple: simple).compactMap { stage in
            let count = items.filter { SvcGroomStage.shown($0.groomStage ?? "", simple: simple) == stage }.count
            return count > 0 ? (stage, count) : nil
        }
    }

    private var openBoard: (() -> Void)? {
        guard let actions else { return nil }
        return { actions.route = .section(.grooming) }
    }

    var body: some View {
        if data == nil {
            if full { LoadingState() }
        } else if items.isEmpty {
            if full {
                VStack(spacing: 0) {
                    EmptyState(systemImage: "scissors", title: L("Nothing in grooming today"), message: L("The day's grooms show up here, stage by stage."), accent: Theme.blue)
                    NavigationLink(value: ProviderRoute.section(.grooming)) {
                        PMButtonContent(title: L("Open grooming"), trailingIcon: "chevron-right", variant: .link, size: .slim)
                    }
                    .buttonStyle(.pm(.link, size: .slim))
                    .padding(.top, -12)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            HomeStrip(storageKey: "grooming", title: HomeActivity.grooming.label, count: items.count, dot: HomeActivity.grooming.accent,
                      linkTitle: L("Open grooming"), link: openBoard) {
                FlowLayout(spacing: 6) {
                    ForEach(counts, id: \.stage) { entry in
                        Chip(text: SvcGroomStage.label(entry.stage, simple: simple), tone: .custom(ProviderState.groom(entry.stage).color), dot: ProviderState.groom(entry.stage).color, count: entry.count)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityLabel(L("Stages of today's grooms"))
                if full {
                    RowDivider()
                    if open.isEmpty {
                        HStack(spacing: 6) {
                            Glyph("check-check", size: 16).foregroundStyle(Theme.blue)
                            Text(L("Every groom today has been handed over.")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    } else {
                        RowList(items: Array(open.prefix(HomeCap.rows))) { item in
                            HomeGroomRow(item: item)
                        }
                        if open.count > HomeCap.rows {
                            HomeStripMore(more: open.count - HomeCap.rows, route: .section(.grooming))
                        }
                    }
                }
            }
        }
    }
}

/// One groom on Home, laid out like a visit row: when, who, its stage, and the one step it takes next.
private struct HomeGroomRow: View {
    let item: HomeGroomItem

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(HomeActions.self) private var actions: HomeActions?
    @State private var topHeight: CGFloat = 0

    private var phone: Bool { sizeClass != .regular }
    private var stage: String { item.groomStage ?? "scheduled" }
    private var simple: Bool { actions?.simpleStages ?? false }
    private var busy: Bool { actions?.isBusy(item.appointmentId) ?? false }
    private var canMove: Bool { workspace.can(.appointmentsComplete) && actions != nil }
    private var tone: Color { ProviderState.groom(SvcGroomStage.shown(stage, simple: simple)).color }
    private var channels: [String] {
        [item.client?.phone?.nonEmpty != nil ? "whatsapp" : nil, item.client?.onPawMiaw == true ? "app" : nil].compactMap { $0 }
    }

    var body: some View {
        EdgeRow(edge: tone, time: DateText.time(item.startsAt)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    PetAvatar(name: item.pet?.name, species: item.pet?.species, photoURL: item.pet?.photoUrl, size: 40)
                    details.frame(maxWidth: .infinity, alignment: .leading)
                    if !phone, let actions { buttons(actions) }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
                if phone, let actions { buttons(actions) }
            }
            .alignmentGuide(VerticalAlignment.center) { d in phone && actions != nil && topHeight > 0 ? topHeight / 2 : d[VerticalAlignment.center] }
        }
        .onTapGesture { openVisit() }
        .accessibilityAction(named: L("Open@needs")) { openVisit() }
    }

    private func openVisit() { actions?.route = .appointment(item.appointmentId) }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text(item.pet?.name ?? "—").font(Theme.text(16, weight: .bold)).foregroundColor(Theme.inkStrong)
             + Text(" · " + (item.serviceLabel ?? "")).font(Theme.text(16)).foregroundColor(Theme.inkSoft))
                .lineLimit(1)
            let details = [item.client?.name, item.groomer?.name.map { LF("with %@", $0) }, item.requestSummary].compactMap { $0?.nonEmpty }.joined(separator: " · ")
            if !details.isEmpty { Text(details).font(Theme.text(12.8)).foregroundStyle(Theme.inkSoft).lineLimit(1).padding(.top, 2) }
            FlowLayout(spacing: 6) {
                Chip(text: actions == nil ? HomeText.groomStage(stage) : SvcGroomStage.label(stage, simple: simple), tone: .custom(tone), dot: tone)
                // Already told: so nobody messages the same family twice.
                if stage == "ready", let told = item.readyNotifiedAt {
                    Chip(text: LF("Notified %@", DateText.time(told)), tone: .muted, icon: "check-check")
                }
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func buttons(_ actions: HomeActions) -> some View {
        let next = SvcGroomStage.next(stage, simple: simple)
        let pet = item.pet?.name ?? "—"
        FlowLayout(spacing: 6) {
            if stage == "scheduled" && workspace.can(.appointmentsCheckIn) {
                PMButton(L("Check in@visit"), systemImage: "arrow-right-to-line", variant: .outline, size: .compact, isWorking: busy) { actions.checkIn(item.appointmentId) }
            }
            if canMove, let next {
                Button {
                    actions.moveGroom(item.appointmentId, petName: pet, to: next)
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(ProviderState.groom(next).color).frame(width: 8, height: 8)
                        Text(SvcGroomStage.moveLabel(to: next, from: stage, simple: simple))
                    }
                }
                .buttonStyle(.pm(.outline, size: .compact))
                .disabled(busy)
            }
            if stage == "ready" && canMove && !channels.isEmpty {
                if channels.count == 1, let channel = channels.first {
                    PMButton(L("Notify"), systemImage: channel == "whatsapp" ? "message-circle" : "smartphone", variant: .outline, size: .compact, isWorking: busy) {
                        actions.tellReady(item.appointmentId, petName: pet, clientName: item.client?.name, channel: channel)
                    }
                } else {
                    Menu {
                        Button { actions.tellReady(item.appointmentId, petName: pet, clientName: item.client?.name, channel: "whatsapp") } label: { GlyphLabel("WhatsApp", icon: "message-circle") }
                        Button { actions.tellReady(item.appointmentId, petName: pet, clientName: item.client?.name, channel: "app") } label: { GlyphLabel("PawMiaw", icon: "smartphone") }
                    } label: {
                        PMButtonContent(title: L("Notify"), icon: "bell-ring")
                    }
                    .buttonStyle(.pm(.outline, size: .compact))
                    .disabled(busy)
                }
            }
            if stage == "ready" {
                // Handing the pet over is finishing the visit: its page has the report, the finish and the bill.
                PMButton(L("Hand over and charge"), systemImage: "hand-coins", size: .compact) { openVisit() }
            }
        }
    }
}

// MARK: - Families on their way with an emergency

/// Families on their way with an emergency ("voy en camino", web hospital/arrivals-block.tsx), at the top of Home.
struct HomeArrivalsBlock: View {
    let arrivals: [HomeArrival]
    let canAct: Bool

    var body: some View {
        Card(padding: 0, tint: Theme.destructive, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                IconBadge(icon: "siren", accent: Theme.destructive, size: 32, iconSize: 16, ink: .onAccent)
                Text(L("On the way")).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                CountBadge(count: arrivals.count)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            RowDivider(color: Theme.destructive.opacity(0.25))
            ForEach(Array(arrivals.enumerated()), id: \.element.id) { index, arrival in
                if index > 0 { RowDivider(color: Theme.destructive.opacity(0.18)) }
                HomeArrivalRow(arrival: arrival, canAct: canAct)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }
}

private struct HomeArrivalRow: View {
    let arrival: HomeArrival
    let canAct: Bool
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var workspace: Workspace
    @Environment(HomeActions.self) private var actions: HomeActions?
    @State private var answering = false
    @State private var dismissing = false

    private var minutesAway: Int {
        guard let eta = DateText.parse(arrival.etaAt) else { return arrival.minutesAway ?? 0 }
        return Int((eta.timeIntervalSinceNow / 60).rounded())
    }

    /// "In 12 min", "Any minute now", "12 min past their ETA".
    private var etaText: String {
        let minutes = minutesAway
        if minutes > 1 { return LF("In %d min", minutes) }
        if minutes >= -2 { return L("Any minute now") }
        return LF("%d min past their ETA", abs(minutes))
    }

    private var petName: String { arrival.pet?.name ?? L("A pet") }
    private var acknowledged: Bool { arrival.status == "acknowledged" }
    private var late: Bool { minutesAway < -2 }

    var body: some View {
        EdgeRow(edge: late ? Theme.mango : (acknowledged ? ProviderState.done.color : Theme.destructive)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    PetAvatar(name: petName, species: arrival.pet?.species, photoURL: arrival.pet?.photoUrl, size: 48)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(petName).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Text([arrival.client?.name ?? L("A family"), arrival.linked == false ? L("not a client yet") : nil, LF("ETA %@", DateText.time(arrival.etaAt))].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                        FlowLayout(spacing: 6) {
                            Chip(text: etaText, tone: late ? .warn : .danger, icon: "car")
                            if acknowledged { Chip(text: L("Answered"), tone: .good, icon: "check-check") }
                            if arrival.afterHours == true {
                                Chip(text: arrival.routedTo == "on_call" ? L("After hours · sent to on call") : L("After hours"), tone: .info, icon: "moon")
                            }
                        }
                        .padding(.top, 6)
                        if let message = arrival.message?.nonEmpty {
                            Text("“\(message)”").font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong).padding(.top, 6)
                        }
                        if acknowledged, let reply = arrival.replyMessage?.nonEmpty {
                            Text(LF("You answered: “%@”", reply) + (arrival.acknowledgedByName.map { " · \($0)" } ?? ""))
                                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).padding(.top, 4)
                        }
                        FlowLayout(spacing: 8) {
                            if let phone = arrival.contactPhone?.nonEmpty, let url = ContactLinks.phone(phone) {
                                PMButton(phone, systemImage: "phone", variant: .outline, size: .header) { openURL(url) }
                            }
                            if let card = arrival.emergencyCard?.url, let url = URL(string: card) {
                                PMButton(L("Emergency card"), systemImage: "external-link", variant: .outline, size: .header) { openURL(url) }
                            } else {
                                Text(L("No emergency card shared")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).frame(minHeight: 36)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if canAct {
                    FlowLayout(spacing: 8) {
                        if !acknowledged {
                            PMButton(L("We’re expecting you"), systemImage: "phone-call", variant: .outline, size: .compact) { answering = true }
                        }
                        if workspace.canAll(.appointmentsCreate, .clientsView), let actions {
                            // "Ya llegaron": the walk-in opens with what is known, as an emergency.
                            PMButton(L("They’re here"), systemImage: "siren", size: .compact, isWorking: actions.isBusy(arrival.id)) { actions.arrived(arrival) }
                        }
                        PMButton(L("Dismiss"), systemImage: "x", variant: .link, size: .slim, tint: Theme.inkStrong) { dismissing = true }
                    }
                    .padding(.leading, 60)
                }
            }
            .padding(.trailing, 4)
        }
        .sheet(isPresented: $answering) {
            HomeAcknowledgeSheet(arrival: arrival, petName: petName)
        }
        .sheet(isPresented: $dismissing) {
            ConfirmSheet(
                title: LF("Take %@ off Home?", petName),
                message: L("Use it when they went elsewhere or it was a mistake. The family isn’t told."),
                confirmTitle: L("Dismiss"),
                destructive: true,
                askReason: true,
                reasonRequired: false,
                cancelTitle: L("Keep it")
            ) { reason in
                try await API.send("POST", "/provider-hospital/arrivals/\(arrival.id)/dismiss", body: ["reason": reason])
                Toast.show(L("Taken off Home."))
                announceDataChanged()
            }
        }
    }
}

private struct HomeAcknowledgeSheet: View {
    let arrival: HomeArrival
    let petName: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var reply = ""
    @State private var sending = false

    var body: some View {
        ProviderModal(title: L("“We’re expecting you”"), subtitle: L("The family hears it right away in their app."), systemImage: "phone-call", accent: .lime, isDirty: !reply.isEmpty, form: form, primaryTitle: L("Send@arrival"), isWorking: sending, primaryIcon: "check-check") {
            sending = true
            Task {
                defer { sending = false }
                do {
                    try await API.send("POST", "/provider-hospital/arrivals/\(arrival.id)/acknowledge", body: ["reply": reply.nonEmpty])
                    Toast.show(L("The family knows you’re expecting them."))
                    announceDataChanged()
                    dismiss()
                } catch {
                    form.apply(error, known: ["reply": "reply"])
                }
            }
        } content: {
            PMTextField(L("A line for them (optional)"), text: $reply, key: "reply", form: form, prompt: LF("e.g. Come in through the emergency door; keep %@ warm.", petName), multiline: true)
        }
        .presentationDetents([.medium, .large])
    }
}
