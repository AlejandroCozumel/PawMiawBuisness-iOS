//
//  HomeActions.swift
//  PawMiawNegocios
//
//  What Home's rows and cards do in place (web today-board.tsx `SheetState`,
//  home-hub.tsx, hospital/arrivals-block.tsx): a visit's steps open the
//  Agenda's own sheets over Home — check in (or move a visit of another day
//  to now), start with the consent and deposit gate, finish with the one
//  charge choice, "Sí vino", no-show, cancel, book again — and the bill opens
//  in Cuentas. The same place answers an online booking, moves someone's day,
//  starts or finishes a group session, moves a groom's stage, a home visit's
//  "Llegué" and "Terminar", and "Ya llegaron" on an emergency arrival.
//  Rows reach it through the environment (`@Environment(HomeActions.self)`).
//

import SwiftUI
import Observation

/// A visit made ready for "Terminar" or "Sí vino": what the sheet needs to know.
struct HomeFinishContext {
    let appointment: SchedAppointment
    let drafts: Int
    let signed: Int
    let invoice: SchedInvoice?
    let signer: (memberId: String, name: String)?
    let collects: Bool
}

/// One sheet over Home at a time.
enum HomeSheet: Identifiable {
    case checkIn(SchedAppointment)
    case otherDay(SchedAppointment, when: String)
    case finish(HomeFinishContext)
    case recordPast(HomeFinishContext)
    case missed(SchedAppointment, mode: String)
    case rebook(SchedAppointment)
    case gate(SchedGatePrompt)
    case svcGate(SvcStartGateRequest)
    case online(SchedOnlineRequest)
    case reassign(date: String, people: [SvcHomePerson], members: [SvcMember])
    case homeFinish(SvcFinishTarget)
    case homeReport(SvcReportTarget)
    case stayLeave(SvcHomeVisitItem, timeZone: String?)
    case program(StaysRequest)
    case setup(HomeSetupSheet)
    case closeShift(CashSession)

    var id: String {
        switch self {
        case .checkIn(let a): "check-in-\(a.id)"
        case .otherDay(let a, let when): "other-day-\(a.id)-\(when)"
        case .finish(let context): "finish-\(context.appointment.id)"
        case .recordPast(let context): "record-past-\(context.appointment.id)"
        case .missed(let a, let mode): "\(mode)-\(a.id)"
        case .rebook(let a): "rebook-\(a.id)"
        case .gate(let prompt): "gate-\(prompt.id)"
        case .svcGate(let request): "svc-gate-\(request.id)"
        case .online(let request): "online-\(request.appointmentId)"
        case .reassign(let date, _, _): "reassign-\(date)"
        case .homeFinish(let target): "home-finish-\(target.id)"
        case .homeReport(let target): "home-report-\(target.id)"
        case .stayLeave(let item, _): "stay-leave-\(item.id)"
        case .program(let request): "program-\(request.id)"
        case .setup(let sheet): "setup-\(sheet.id)"
        case .closeShift(let session): "close-shift-\(session.id)"
        }
    }
}

@MainActor
@Observable
final class HomeActions {
    /// The sheet open over Home.
    var sheet: HomeSheet?
    /// Where Home goes next (a bill after "Charge now", a visit, the booking).
    var route: ProviderRoute?
    /// Rows waiting on their visit to load or a step to answer.
    var busy: Set<String> = []
    /// The grooming settings' "simple stages" (no separate cut & dry).
    var simpleStages = false
    /// An invited member's welcome, shown over everything until they leave it.
    var welcome: HomeWelcomeState?
    var showsWelcome = false

    @ObservationIgnored private var members: [SchedMember]?

    private var workspace: Workspace { Workspace.shared }

    func isBusy(_ id: String) -> Bool { busy.contains(id) }

    // MARK: Loading a visit

    private func withVisit(_ id: String, _ then: @escaping (SchedAppointment) async -> Void) {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        Task {
            defer { busy.remove(id) }
            do {
                let appointment = try await SchedData.visit(id)
                await then(appointment)
            } catch is CancellationError {
            } catch {
                Toast.error(error)
            }
        }
    }

    /// The visit's bill, whole: its latest from the bills list, then read on its own.
    static func bill(for appointmentId: String) async -> SchedInvoice? {
        let page: Page<SchedInvoiceSummary>? = try? await API.get("/provider-invoices", query: ["limit": "10", "offset": "0", "providerAppointmentId": appointmentId])
        guard let latest = page?.items.sorted(by: { ($0.createdAt ?? "") > ($1.createdAt ?? "") }).first else { return nil }
        return try? await API.get("/provider-invoices/\(latest.id)")
    }

    private func context(_ appointment: SchedAppointment) async -> HomeFinishContext {
        let w = workspace
        let readsRecords = w.can(.recordsView)
        let readsBills = w.moneyLevel >= .charging
        async let notes: [SchedRecord]? = readsRecords ? await SchedData.visitRecords(appointment.id) : nil
        async let bill: SchedInvoice? = readsBills ? await Self.bill(for: appointment.id) : nil
        if members == nil { members = await SchedData.members() }
        let records = (await notes) ?? []
        let me = members?.first(where: \.isMe)
        return HomeFinishContext(
            appointment: appointment,
            drafts: records.filter { $0.isDraft && $0.hasWords }.count,
            signed: records.filter(\.isSigned).count,
            invoice: await bill,
            signer: w.can(.recordsApprove) ? me.map { ($0.id, $0.label) } : nil,
            collects: (w.can(.billingRecordPayment) || w.can(.billingEditInvoice)) && readsBills
        )
    }

    // MARK: A visit's steps

    /// Only today's visits check in: on another day, it first offers to move the visit to now.
    func checkIn(_ id: String) {
        withVisit(id) { [weak self] a in
            let when = SchedDay.when(a.startsAt, zone: SchedData.zone(of: a.locationId))
            self?.sheet = when == "today" ? .checkIn(a) : .otherDay(a, when: when == "past" ? "past" : "future")
        }
    }

    /// "Empezar": a missing consent or deposit asks for its reason here.
    func start(_ id: String, petName: String) {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        Task {
            defer { busy.remove(id) }
            do {
                try await SchedVisitOps.start(id)
                Toast.show(LF("%@ is in.", petName))
            } catch {
                if let prompt = SchedGatePrompt.from(error, petName: petName, verb: "start",
                                                     attempt: { extra in try await SchedVisitOps.start(id, extra: extra) },
                                                     onDone: { Toast.show(LF("%@ is in.", petName)) }) {
                    sheet = .gate(prompt)
                } else {
                    schedToast(error)
                }
            }
        }
    }

    /// "Terminar" (or "Dar salida" for whoever charges): the charge choice, the signature and "¿Cuándo vuelve?".
    func finish(_ id: String) {
        withVisit(id) { [weak self] a in
            guard let self else { return }
            let context = await self.context(a)
            self.sheet = .finish(context)
        }
    }

    /// "Sí vino": a visit nobody closed on its day, recorded with the times it had.
    func recordPast(_ id: String) {
        withVisit(id) { [weak self] a in
            guard let self else { return }
            let context = await self.context(a)
            self.sheet = .recordPast(context)
        }
    }

    func noShow(_ id: String) { withVisit(id) { [weak self] a in self?.sheet = .missed(a, mode: "no_show") } }
    func cancel(_ id: String) { withVisit(id) { [weak self] a in self?.sheet = .missed(a, mode: "cancel") } }
    func rebook(_ id: String) { withVisit(id) { [weak self] a in self?.sheet = .rebook(a) } }

    /// A move that only needs a press (undo the arrival, reopen, send to the desk).
    func run(_ id: String, _ path: String, success: String) {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        Task {
            defer { busy.remove(id) }
            do {
                let _: SchedMoveResponse = try await SchedAPI.send("POST", path, body: [:])
                Toast.show(success)
                announceDataChanged()
            } catch {
                schedToast(error)
            }
        }
    }

    /// A family's online booking answered over Home (Confirmar, Cambiar hora y confirmar, Rechazar).
    func answerOnline(_ appointmentId: String) {
        guard !busy.contains(appointmentId) else { return }
        busy.insert(appointmentId)
        Task {
            defer { busy.remove(appointmentId) }
            let list: SchedOnlineRequestList? = try? await API.get("/provider-online-booking/requests", query: ["locationId": workspace.locationId])
            let found = (list?.items ?? []).first { request in
                request.appointmentId == appointmentId || request.pets.contains { $0.appointmentId == appointmentId }
            }
            if let found { sheet = .online(found) } else { route = .appointment(appointmentId) }
        }
    }

    /// The welcome, at the step the server says (a reminder resumes it at its own step).
    func openWelcome(_ state: HomeWelcomeState) {
        welcome = state
        showsWelcome = true
    }

    /// "Adopt my signature", "Add it", "Continue": the welcome reopened at that step.
    func resumeWelcome(step: String?) {
        guard !busy.contains("welcome") else { return }
        busy.insert("welcome")
        Task {
            defer { busy.remove("welcome") }
            do {
                let state: HomeWelcomeState = try await API.post("/provider-member-onboarding/resume", body: ["step": step])
                openWelcome(state)
            } catch {
                Toast.error(errorText(error, fallback: L("Could not open it. Try again.")))
            }
        }
    }

    /// "Contar y cerrar" on a register shift left open from an earlier day: the register's own close, over Home.
    func closeShift(_ sessionId: String) {
        let key = "shift-\(sessionId)"
        guard !busy.contains(key) else { return }
        busy.insert(key)
        Task {
            defer { busy.remove(key) }
            do {
                let session: CashSession = try await API.get("/provider-store/register-sessions/\(sessionId)")
                sheet = .closeShift(session)
            } catch {
                Toast.error(error)
            }
        }
    }

    // MARK: New visits

    func newAppointment(day: String? = nil) {
        route = .bookVisit(BookingPrefill(day: day))
    }

    func walkIn(clientId: String? = nil, petId: String? = nil, notes: String? = nil) {
        route = .bookVisit(BookingPrefill(clientId: clientId, petId: petId, notes: notes, walkIn: true))
    }

    /// "Ya llegaron" on a family's "voy en camino": the warning leaves Home and the walk-in opens with what is known.
    func arrived(_ arrival: HomeArrival) {
        guard !busy.contains(arrival.id) else { return }
        busy.insert(arrival.id)
        Task {
            defer { busy.remove(arrival.id) }
            do {
                try await API.send("POST", "/provider-hospital/arrivals/\(arrival.id)/arrived", body: ["appointmentId": nil])
                announceDataChanged()
                // Not ported yet: the booking hand-off carries no `onTheWayId`, so the warning is closed here first.
                let linked = arrival.linked == true
                walkIn(clientId: linked ? arrival.client?.id : nil, petId: linked ? arrival.pet?.providerClientPetId : nil, notes: arrival.message?.nonEmpty)
            } catch {
                Toast.error(error)
            }
        }
    }

    // MARK: The day, sessions, grooms and home visits

    /// "¿Alguien faltó? Mueve su día": everyone who takes visits, from one person to another or whoever is free.
    func reassignDay(_ date: String) {
        guard !busy.contains("reassign") else { return }
        busy.insert("reassign")
        Task {
            defer { busy.remove("reassign") }
            let team = await svcLoadMembers(workspace)
            let people = team.map { SvcHomePerson(memberId: $0.id, name: $0.shownName, image: $0.image, total: 0, done: 0, inProgress: 0, late: 0) }
            sheet = .reassign(date: date, people: people, members: team)
        }
    }

    /// A session's start with whoever arrived, or its finish for everyone with them.
    func moveSession(_ id: String, _ action: String) {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        Task {
            defer { busy.remove(id) }
            do {
                let result: SvcSessionMoveResult = try await SvcAPI.send("POST", "/provider-sessions/\(id)/\(action)", body: [:])
                let moved = result.moved?.count ?? 0
                if action == "start" {
                    Toast.show(moved == 1 ? L("Started with 1 pet.") : LF("Started with %d pets.", moved))
                } else {
                    Toast.show(moved == 1 ? L("Finished for 1 pet. Its family has its bill.") : LF("Finished for %d pets. Each family has its own bill.", moved))
                }
                if let skipped = result.skipped?.first?.error { Toast.error(skipped) }
                announceDataChanged()
            } catch {
                Toast.error(svcCode(error) == "nobody_arrived" ? L("Mark who arrived first, or start with everyone.") : svcMessage(error))
            }
        }
    }

    /// A groom to its next stage. Out of the waiting room it starts the visit: a missing consent or deposit asks here.
    func moveGroom(_ id: String, petName: String, to stage: String) {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        Task {
            defer { busy.remove(id) }
            do {
                let _: SvcIgnored = try await SvcAPI.send("PATCH", "/provider-appointments/\(id)/groom-stage", body: ["stage": stage])
                Toast.show("\(petName) · \(SvcGroomStage.label(stage, simple: simpleStages))")
                announceDataChanged()
            } catch {
                if let code = svcIsStartGate(error) {
                    if workspace.isOwnerOrAdmin {
                        sheet = .svcGate(SvcStartGateRequest(code: code, petName: petName) { override in
                            let _: SvcIgnored = try await API.post("/provider-appointments/\(id)/start", body: override)
                            // A started groom is in the bath already.
                            if stage != "bath" { let _: SvcIgnored = try await API.patch("/provider-appointments/\(id)/groom-stage", body: ["stage": stage]) }
                            announceDataChanged()
                        })
                    } else {
                        Toast.error(svcMessage(error) + " " + L("Open the visit to see what it needs."))
                    }
                    return
                }
                Toast.error(svcMessage(error, codes: SvcRefusals.grooming))
            }
        }
    }

    /// "Ready" told to the family once per Ready: in PawMiaw, or WhatsApp opened with the message.
    func tellReady(_ id: String, petName: String, clientName: String?, channel: String) {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        Task {
            defer { busy.remove(id) }
            do {
                let result: SvcGroomReadyResult = try await SvcAPI.send("POST", "/provider-appointments/\(id)/groom-ready", body: ["channel": channel, "locale": LocalizationManager.shared.currentLanguage.rawValue])
                if channel == "whatsapp", let link = result.link {
                    svcOpen(link)
                    Toast.show(L("WhatsApp is open with the message: send it from there."))
                } else {
                    Toast.show(LF("%@ was told in PawMiaw that %@ is ready.", NameText.firstName(clientName), petName))
                }
                announceDataChanged()
            } catch {
                Toast.error(svcMessage(error, codes: SvcRefusals.grooming))
            }
        }
    }

    /// "Llegué": the home visit's start, from the door, with the time it was pressed.
    func arriveHome(_ item: SvcHomeVisitItem) {
        let at = DateText.iso(Date())
        let path: String
        if item.isStay {
            guard let stay = item.stayId, let visit = item.stayVisitId else { return }
            path = "/provider-homestays/\(stay)/visits/\(visit)/arrive"
        } else {
            guard let id = item.appointmentId else { return }
            path = "/provider-appointments/\(id)/home-arrive"
        }
        guard !busy.contains(item.id) else { return }
        busy.insert(item.id)
        Task {
            defer { busy.remove(item.id) }
            do {
                let _: SvcIgnored = try await SvcAPI.send("POST", path, body: ["at": at])
                announceDataChanged()
            } catch {
                if let code = svcIsStartGate(error) {
                    if workspace.isOwnerOrAdmin {
                        sheet = .svcGate(SvcStartGateRequest(code: code, petName: item.petNames) { override in
                            var body = override
                            body["at"] = at
                            let _: SvcIgnored = try await API.post(path, body: body)
                            announceDataChanged()
                        })
                    } else {
                        Toast.error(svcMessage(error) + " " + L("Open the visit to see what it needs."))
                    }
                    return
                }
                Toast.error(svcMessage(error, codes: SvcRefusals.homeVisits))
            }
        }
    }

    /// "Terminar": a home stay's visit leaves the home; a walk, sitting, groom or class closes here; a vet visit on its page.
    func finishHome(_ item: SvcHomeVisitItem, timeZone: String?, canWrite: Bool) {
        if item.isStay {
            sheet = .stayLeave(item, timeZone: timeZone)
            return
        }
        guard let id = item.appointmentId else { return }
        guard SvcHomeRules.finishesHere(item.serviceCategory) else {
            route = .appointment(id)
            return
        }
        let lead = item.pets.first { $0.appointmentId == item.appointmentId } ?? item.pets.first
        homeItems[id] = (item, canWrite)
        sheet = .homeFinish(SvcFinishTarget(id: id, petName: lead?.name ?? item.petNames, serviceLabel: item.serviceText, serviceCategory: item.serviceCategory, reportMissing: item.reportMissing ?? []))
    }

    @ObservationIgnored private var homeItems: [String: (item: SvcHomeVisitItem, canWrite: Bool)] = [:]

    private func report(for appointmentId: String) -> SvcReportTarget? {
        guard let entry = homeItems[appointmentId] else { return nil }
        let item = entry.item
        let pets = item.pets.compactMap { pet in pet.appointmentId.map { SvcReportPet(id: $0, name: pet.name) } }
        let list = pets.isEmpty ? [SvcReportPet(id: appointmentId, name: item.petNames)] : pets
        return SvcReportTarget(subtitle: "\(item.petNames) · \(item.serviceText)", pets: list, canWrite: entry.canWrite)
    }

    // MARK: Moving between sheets

    /// The next sheet once this one has gone.
    func next(_ sheet: HomeSheet) {
        self.sheet = nil
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            self.sheet = sheet
        }
    }

    /// Somewhere to go once the sheet has gone.
    func go(_ route: ProviderRoute) {
        sheet = nil
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            self.route = route
        }
    }

    /// After "Charge now" or "Put the price myself": the visit's bill, in Cuentas.
    func openBill(after appointmentId: String) {
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            if let bill = await Self.bill(for: appointmentId) {
                route = .invoice(bill.id)
            } else {
                route = .appointment(appointmentId)
            }
        }
    }

    // MARK: The sheets

    @ViewBuilder
    func view(for sheet: HomeSheet) -> some View {
        let w = workspace
        switch sheet {
        case .checkIn(let a):
            SchedCheckInSheet(appointment: a, canStart: w.can(.appointmentsComplete)) { [weak self] prompt in self?.next(.gate(prompt)) }
        case .otherDay(let a, let when):
            let within = (a.start.map { Date().timeIntervalSince($0) } ?? 0) <= 31 * 86_400
            SchedOtherDaySheet(
                appointment: a,
                when: when,
                canMove: w.can(.appointmentsEdit),
                onMoved: { [weak self] in self?.sheet = nil; self?.checkInAfterMove(a.id) },
                onNoShow: w.can(.appointmentsCheckIn) ? { [weak self] in self?.sheet = .missed(a, mode: "no_show") } : nil,
                onWalkIn: w.canAll(.appointmentsCreate, .clientsView) ? { [weak self] in self?.sheet = nil; self?.walkInLater(a) } : nil,
                onRecordPast: when == "past" && within && w.can(.appointmentsComplete) ? { [weak self] in self?.sheet = nil; self?.recordPastLater(a.id) } : nil
            )
        case .finish(let c):
            SchedFinishSheet(appointment: c.appointment, drafts: c.drafts, signed: c.signed, invoice: c.invoice, signer: c.signer, collects: c.collects,
                             onAfter: { [weak self] _ in self?.openBill(after: c.appointment.id) },
                             onEarlierDay: w.can(.appointmentsComplete) ? { [weak self] in self?.recordPastLater(c.appointment.id) } : nil)
        case .recordPast(let c):
            SchedRecordPastSheet(appointment: c.appointment, invoice: c.invoice, collects: c.collects) { [weak self] _ in self?.openBill(after: c.appointment.id) }
        case .missed(let a, let mode):
            SchedMissedSheet(appointment: a, mode: mode)
        case .rebook(let a):
            SchedRebookSheet(appointment: a)
        case .gate(let prompt):
            SchedGateSheet(prompt: prompt)
        case .svcGate(let request):
            SvcStartGateSheet(request: request) {}
        case .online(let request):
            SchedRequestSheet(request: request) { [weak self] id in self?.go(.appointment(id)) }
        case .reassign(let date, let people, let members):
            SvcMoveDaySheet(date: date, people: people, members: members, initialFrom: nil)
        case .homeFinish(let target):
            let report = self.report(for: target.id)
            SvcFinishSheet(
                target: target,
                extraBody: ["at": DateText.iso(Date())],
                onOpenReport: report == nil ? nil : { [weak self] in if let report { self?.next(.homeReport(report)) } },
                onOpenVisit: w.moneyLevel >= .charging ? { [weak self] in self?.openBill(after: target.id) } : nil,
                onFinished: {}
            )
        case .homeReport(let target):
            SvcReportSheet(target: target)
        case .stayLeave(let item, let timeZone):
            SvcStayMoveSheet(item: item, move: "leave", timeZone: timeZone)
        case .program(let request):
            HomeProgramRequestSheet(request: request)
        case .setup(let setup):
            setup.view(actions: self)
        case .closeShift(let session):
            CashCloseShiftSheet(session: session) { announceDataChanged() }
        }
    }

    private func checkInAfterMove(_ id: String) {
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            checkIn(id)
        }
    }

    private func recordPastLater(_ id: String) {
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            recordPast(id)
        }
    }

    private func walkInLater(_ a: SchedAppointment) {
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            walkIn(clientId: a.providerClientId, petId: a.providerClientPetId)
        }
    }
}

/// Hosts Home's sheets and where they lead, and hands the actions to every row below.
struct HomeActionsHost: ViewModifier {
    @Bindable var actions: HomeActions

    func body(content: Content) -> some View {
        content
            .environment(actions)
            .sheet(item: $actions.sheet) { sheet in actions.view(for: sheet) }
            .navigationDestination(item: $actions.route) { RouteView(route: $0) }
            .fullScreenCover(isPresented: $actions.showsWelcome, onDismiss: { announceDataChanged() }) {
                if let welcome = actions.welcome {
                    HomeWelcomeScreen(state: welcome) { actions.showsWelcome = false }
                }
            }
    }
}
