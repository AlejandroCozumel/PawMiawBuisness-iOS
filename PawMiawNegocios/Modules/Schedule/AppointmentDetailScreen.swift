//
//  AppointmentDetailScreen.swift
//  PawMiawNegocios
//
//  One visit (web provider.appointments.$appointmentId.tsx), built around
//  its next step: the pet (its chart one tap away), what it came for and
//  when, who it is with and where, the visit's four steps, what the family
//  asked, then — by status — the online request's three answers, the
//  arrival, the waiting room, or the note, what else was recorded, the
//  closing card and the bill (money level 1 and up). Every move the web
//  offers: check in, start, finish with the charge choice, "Sí vino", no-show,
//  cancel with its reason, edit and move, book again, undo, reopen. Around
//  it: the owner's grooming request, the groom/walk/training report, the
//  care card, the triage, the chart with "+" to record into the visit, the
//  consents (signed here) and the emergency deposit, the incidents, the
//  prescriptions, the notes to the family, the history of changes,
//  hospitalizing and "Add to calendar".
//

import SwiftUI

private enum SchedVisitSheet: Identifiable {
    case edit, checkIn, otherDay, finish, recordPast, noShow, cancel, rebook, walkIn, stopSeries, calendar
    /// "Perdonar el cargo" on a no-show the family disputes: its fee bill (docs/family-money.md §5).
    case forgiveFee(String)
    case gate(SchedGatePrompt)
    case admit(SchedAdmitPreset)
    case deposit(SchedDepositDue)

    var id: String {
        switch self {
        case .gate(let prompt): "gate-\(prompt.id)"
        case .forgiveFee(let id): "forgive-\(id)"
        case .admit(let preset): "admit-\(preset.id)"
        case .deposit: "deposit"
        case .calendar: "calendar"
        case .edit: "edit"
        case .checkIn: "checkIn"
        case .otherDay: "otherDay"
        case .finish: "finish"
        case .recordPast: "recordPast"
        case .noShow: "noShow"
        case .cancel: "cancel"
        case .rebook: "rebook"
        case .walkIn: "walkIn"
        case .stopSeries: "stopSeries"
        }
    }
}

struct AppointmentDetailScreen: View {
    let appointmentId: String

    @EnvironmentObject private var workspace: Workspace
    @State private var appointment: SchedAppointment?
    @State private var loadError: String?
    @State private var records: [SchedRecord] = []
    @State private var invoice: SchedInvoice?
    @State private var members: [SchedMember] = []
    @State private var sheet: SchedVisitSheet?
    @State private var pushed: ProviderRoute?
    @State private var busy = false
    @State private var tick = Date()
    @State private var simpleStages = false
    @State private var reportMissing: [String]?
    @State private var hospStays: [SchedHospStay] = []
    /// A disputed no-show's fee bill ("Sí fuimos"): "Perdonar el cargo" only while something is left on it.
    @State private var disputedFee: CashInvoice?
    @State private var dismissing = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if !workspace.can(.appointmentsView) {
                PageScroll { NoAccessState(message: L("Ask the workspace owner to let your role see visits.")) }
            } else if let appointment {
                page(appointment)
            } else if let loadError {
                PageScroll { ErrorState(message: loadError) { await load() } }
            } else {
                PageScroll { LoadingState() }
            }
        }
        .providerPage(appointment?.petName ?? L("Visit"))
        .reloadsOnScope { await load() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                tick = Date()
            }
        }
        .sheet(item: $sheet) { item in
            if let appointment { sheetView(item, appointment) }
        }
        .navigationDestination(item: $pushed) { RouteView(route: $0) }
    }

    // MARK: Loading

    private func load() async {
        guard workspace.can(.appointmentsView) else { return }
        let id = appointmentId
        let readsRecords = workspace.can(.recordsView)
        let readsBills = workspace.moneyLevel >= .charging
        do {
            async let visit = SchedData.visit(id)
            async let notes: [SchedRecord]? = readsRecords ? await SchedData.visitRecords(id) : nil
            async let team = SchedData.members()
            async let bill: SchedInvoice? = readsBills ? await Self.bill(for: id) : nil
            appointment = try await visit
            records = (await notes) ?? []
            members = await team
            invoice = await bill
            loadError = nil
            disputedFee = nil
            if let a = appointment, workspace.can(.billingWaiveVisit), a.status == "no_show", a.disputedAt != nil, a.feeDecision == "charged", let fee = a.feeInvoiceId {
                disputedFee = try? await API.get("/provider-invoices/\(fee)")
            }
            if appointment?.serviceCategory == "groomer", appointment?.groomStage != nil {
                let settings: SchedGroomSettings? = try? await API.get("/provider-grooming/settings")
                simpleStages = settings?.simpleStages ?? false
            }
            // A pet already in the hospital (or waiting for a bed) isn't hospitalized twice: the visit opens that stay.
            if let pet = appointment?.providerClientPetId, workspace.can(.hospitalView), workspace.offers(.vet, .emergency) {
                let stays: SchedHospStays? = try? await API.get("/provider-hospital/hospitalizations", query: ["providerClientPetId": pet])
                hospStays = stays?.hospitalizations ?? []
            }
        } catch is CancellationError {
        } catch {
            if appointment == nil { loadError = (error as? APIError)?.status == 404 ? L("This visit was not found.") : errorText(error) }
            else { Toast.error(error) }
        }
    }

    /// The visit's bill, whole: its latest from the bills list, then read on its own.
    private static func bill(for appointmentId: String) async -> SchedInvoice? {
        let page: Page<SchedInvoiceSummary>? = try? await API.get("/provider-invoices", query: ["limit": "10", "offset": "0", "providerAppointmentId": appointmentId])
        guard let latest = page?.items.sorted(by: { ($0.createdAt ?? "") > ($1.createdAt ?? "") }).first else { return nil }
        return try? await API.get("/provider-invoices/\(latest.id)")
    }

    private func reloadRecords() async {
        guard workspace.can(.recordsView) else { return }
        let page: Page<SchedRecord>? = try? await API.get("/provider-records", query: ["limit": "100", "offset": "0", "appointmentId": appointmentId])
        records = page?.items ?? records
    }

    // MARK: What the visit is now

    private struct Facts {
        let status: String
        let writable: Bool
        let waiting: Bool
        let missed: Bool
        let drafts: [SchedRecord]
        let signedCount: Int
        let written: Bool
        let signer: (memberId: String, name: String)?
        let dayWhen: String
        let late: Bool
        let stage: SchedBillStage
        let collectAmount: Int
        let canCollect: Bool
        let collects: Bool
        let readsBills: Bool
        let checkIn: Bool
        let start: Bool
        let cancel: Bool
        let edit: Bool
        let checksOut: Bool
        let openSinceEarlierDay: Bool
        let theyCame: Bool
        let paid: Bool
        let reportMissing: [String]
        let openStay: SchedHospStay?
        let canHospitalize: Bool
    }

    private func facts(_ a: SchedAppointment) -> Facts {
        let w = workspace
        let drafts = records.filter { $0.isDraft && $0.hasWords }
        let me = members.first(where: \.isMe)
        let readsBills = w.moneyLevel >= .charging
        let stage = SchedBillStage.of(visitStatus: a.status, noCharge: a.noCharge == true, invoice: invoice)
        let collect = invoice.map { $0.status == "draft" ? ($0.totalAmount ?? 0) - ($0.amountPaid ?? 0) : ($0.balanceDueAmount ?? 0) } ?? 0
        let dayWhen = SchedDay.when(a.startsAt, zone: SchedData.zone(of: a.locationId))
        let start = w.can(.appointmentsComplete)
        let openEarlier = dayWhen == "past" && (a.status == "checked_in" || a.status == "in_progress")
        let within = (a.start.map { Date().timeIntervalSince($0) } ?? 0) <= 31 * 86_400
        return Facts(
            status: a.status,
            writable: a.status == "in_progress" || a.status == "completed",
            waiting: a.status == "checked_in",
            missed: a.isGone,
            drafts: drafts,
            signedCount: records.filter(\.isSigned).count,
            written: records.contains(where: \.hasWords),
            signer: w.can(.recordsApprove) ? me.map { ($0.id, $0.label) } : nil,
            dayWhen: dayWhen,
            late: a.status == "scheduled" && (a.start ?? .distantFuture) < Date(),
            stage: stage,
            collectAmount: collect,
            canCollect: w.can(.billingRecordPayment) && readsBills && [.building, .ready, .partPaid].contains(stage) && collect > 0,
            collects: (w.can(.billingRecordPayment) || w.can(.billingEditInvoice)) && readsBills,
            readsBills: readsBills,
            checkIn: w.can(.appointmentsCheckIn),
            start: start,
            cancel: w.can(.appointmentsCancel),
            edit: w.can(.appointmentsEdit),
            checksOut: !start && w.can(.billingRecordPayment),
            openSinceEarlierDay: openEarlier,
            theyCame: openEarlier && start && within,
            paid: (invoice?.amountPaid ?? 0) > 0,
            reportMissing: a.reportKind != nil ? (reportMissing ?? SvcReportText.missing(a.serviceCategory, a.report)) : [],
            openStay: hospStays.first(where: \.open),
            canHospitalize: !hospStays.contains(where: \.open) && w.can(.hospitalManage) && w.offers(.vet, .emergency) && ["checked_in", "in_progress", "completed"].contains(a.status)
        )
    }

    private struct Primary { let title: String; let systemImage: String; let action: () -> Void }

    /// The header always holds the visit's next step: arrive, start, finish, sign, collect.
    private func primary(_ a: SchedAppointment, _ f: Facts) -> Primary? {
        if f.openSinceEarlierDay {
            return f.theyCame ? Primary(title: L("They came"), systemImage: "badge-check") { sheet = .recordPast } : nil
        }
        if f.status == "scheduled" && f.checkIn { return Primary(title: L("Check in"), systemImage: "log-in") { arrive(f) } }
        if f.status == "checked_in" && f.start { return Primary(title: L("Start"), systemImage: "play") { startVisit(a) } }
        if f.status == "in_progress" && (f.start || f.checksOut) {
            return Primary(title: f.checksOut ? L("Check out") : L("Finish the visit"), systemImage: f.checksOut ? "log-out" : "badge-check") { sheet = .finish }
        }
        if f.status == "completed" && !f.drafts.isEmpty && f.signer != nil { return Primary(title: L("Sign now"), systemImage: "pen-line") { signAll(a, f.drafts) } }
        if f.status == "completed" && f.canCollect, let invoice {
            return Primary(title: LF("Collect %@", Money.format(f.collectAmount, currency: invoice.currency)), systemImage: "hand-coins") { pushed = .invoice(invoice.id) }
        }
        if f.missed && f.edit { return Primary(title: L("Book again"), systemImage: "calendar-plus") { sheet = .rebook } }
        return nil
    }

    // MARK: The page

    /// The web's order: the header (the next step, the four steps, the family, the
    /// banners); on a phone the work first (the request, the arrival, the waiting room,
    /// or the note and the bill), the chart after; on an iPad the chart beside the work.
    private func page(_ a: SchedAppointment) -> some View {
        let f = facts(a)
        _ = tick
        return PageScroll(maxWidth: sizeClass == .regular ? 1600 : 820, refresh: { await load() }) {
            header(a, f)
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) { sideCards(a, f) }
                        .frame(width: 272)
                    VStack(alignment: .leading, spacing: 16) { center(a, f) }
                        .frame(maxWidth: .infinity)
                }
            } else {
                center(a, f)
                sideCards(a, f)
            }
            bookingCard(a, f)
            AuditHistoryCard(entityType: "provider_appointment", entityId: a.id, title: L("History of changes"), description: L("Every change to this visit, who made it and when."))
        }
    }

    /// The visit's work by status: the online request's answers, the arrival, the waiting room, or the note and the bill.
    /// A family's ask to move it ("Cambio de hora") is answered first; the visit stays booked meanwhile.
    @ViewBuilder private func center(_ a: SchedAppointment, _ f: Facts) -> some View {
        if !a.isRequested && a.rescheduleProposal != nil {
            SchedRequestPanel(target: SchedAnswerTarget(appointment: a))
        }
        if a.isRequested {
            SchedRequestPanel(target: SchedAnswerTarget(appointment: a))
        } else if f.status == "scheduled" {
            SchedArrivalLock(appointment: a, late: f.late, dayWhen: f.dayWhen, canStart: f.start, onArrive: f.checkIn ? { arrive(f) } : nil)
        } else if f.waiting {
            SchedWaitingLock(appointment: a, onStart: f.start ? { startVisit(a) } : nil, starting: busy)
        } else {
            work(a, f)
        }
    }

    /// What the web shows beside the visit: the request, the group, the care card, the triage,
    /// the chart, the consents and the incidents.
    @ViewBuilder private func sideCards(_ a: SchedAppointment, _ f: Facts) -> some View {
        let w = workspace
        if a.reportKind == "groom" {
            SchedGroomRequestCard(appointmentId: a.id, petName: a.petName, canEdit: w.canAny(.appointmentsCreate, .appointmentsCheckIn, .appointmentsComplete))
        }
        SchedVisitGroupCard(appointment: a)
        if a.reportKind != nil {
            SvcCareCard(petId: a.providerClientPetId, petName: a.petName, canEdit: w.canAny(.petsEdit, .appointmentsComplete))
        }
        // Only a clinical visit is triaged: a groom, a walk or a class isn't, even where the workspace also does vet care.
        if w.offers(.vet, .emergency) && a.isClinical && w.canAny(.appointmentsCheckIn, .hospitalView) {
            SchedTriageCard(
                appointmentId: a.id,
                canEdit: w.can(.appointmentsCheckIn) && ["scheduled", "checked_in", "in_progress"].contains(a.status),
                onHospitalize: f.canHospitalize ? { triage in hospitalize(a, triage) } : nil,
                hospitalization: f.openStay,
                onTakeDeposit: f.readsBills && w.can(.billingRecordPayment) && !a.isGone ? { due in sheet = .deposit(due) } : nil
            )
        }
        if w.canAny(.recordsView, .clientsView) {
            SchedVisitChart(appointmentId: a.id, petId: a.providerClientPetId, petWeightGrams: a.petWeight,
                            canLogWeight: w.can(.appointmentsEdit) && (f.writable || f.waiting),
                            onAdd: f.writable && w.can(.recordsCreate) ? { type in addRecord(a, type) } : nil)
        }
        ConsentsCard(context: ConsentContext(act: ConsentAct(appointmentId: a.id), businessName: w.current?.name, clientName: a.clientName,
                                             familyOnApp: a.clientHouseholdId != nil, clientEmail: a.clientEmail, clientPhone: a.clientPhone,
                                             pets: [ActPet(id: a.providerClientPetId, name: a.petName)],
                                             actLabel: "\(a.serviceLabel) · \(DateText.dayTime(a.startsAt))", started: f.writable))
        IncidentsCard(act: ConsentAct(appointmentId: a.id), pets: [ActPet(id: a.providerClientPetId, name: a.petName)], familyName: a.clientName,
                      recordable: ["checked_in", "in_progress", "completed"].contains(a.status))
    }

    @ViewBuilder private func work(_ a: SchedAppointment, _ f: Facts) -> some View {
        if f.status == "completed" && !f.drafts.isEmpty && f.signer == nil {
            SchedToSignBanner(count: f.drafts.count, vetName: a.assignedMember?.name)
        }
        let canRead = workspace.can(.recordsView)
        if a.reportKind != nil {
            SchedVisitReportCard(appointment: a, canWrite: workspace.can(.appointmentsComplete) && !f.missed) { reportMissing = $0 }
            if let closing = closing(a, f) { closing }
        } else if canRead {
            SchedVisitNote(appointment: a, records: records,
                           canWrite: (workspace.can(.recordsCreate) || workspace.can(.recordsEdit)) && !f.missed,
                           canSign: workspace.can(.recordsApprove) && !f.missed && f.status == "completed",
                           signsOnFinish: f.signer != nil,
                           noteRequired: a.isClinical,
                           onChanged: { await reloadRecords() })
            if let closing = closing(a, f) { closing }
        } else if let closing = closing(a, f) {
            closing
        }
        if canRead {
            let noteType = a.serviceCategory.map { ["vet", "emergency", "pharmacy"].contains($0) ? "vet_visit" : "note" } ?? "vet_visit"
            let note = records.filter { $0.recordType == noteType }.sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }.first
            let others = records.filter { $0.id != note?.id || a.reportKind != nil }
            if !others.isEmpty || f.writable {
                SchedVisitRecords(records: others, canSign: workspace.can(.recordsApprove) && !f.missed, onChanged: { await reloadRecords() },
                                  onAdd: f.writable && workspace.can(.recordsCreate) ? { addRecord(a, nil) } : nil)
            }
        }
        // Prescriptions written at this visit (docs/prescriptions.md).
        if a.isClinical {
            SchedVisitPrescriptions(appointment: a)
        }
        SchedVisitUpdatesCard(appointment: a, canSend: workspace.can(.appointmentsComplete))
        if f.readsBills {
            SchedVisitBillCard(appointment: a, invoice: invoice, stage: f.stage, collectAmount: f.collectAmount, canCollect: f.canCollect)
        }
    }

    /// The closing card under the note: the same next step as the header, with what it waits for.
    private func closing(_ a: SchedAppointment, _ f: Facts) -> SchedVisitClosing? {
        var checks: [SchedClosingCheck] = []
        let canRead = workspace.can(.recordsView)
        if a.reportKind != nil && (f.status == "in_progress" || f.status == "completed") {
            checks.append(f.reportMissing.isEmpty
                ? SchedClosingCheck(id: "report", label: L("Report"), value: L("Filled in"), state: .ok)
                : SchedClosingCheck(id: "report", label: L("Report"), value: LF("Missing: %@", SvcReportText.fieldsText(f.reportMissing)), state: .warn))
        }
        if canRead && a.reportKind == nil {
            checks.append(f.written
                ? SchedClosingCheck(id: "note", label: L("Note"), value: L("Written"), state: .ok)
                : SchedClosingCheck(id: "note", label: L("Note"), value: a.isClinical ? L("Not written yet") : L("No note yet"), state: a.isClinical ? .warn : .pending))
        }
        if f.readsBills {
            let currency = invoice?.currency
            let check: SchedClosingCheck
            switch f.stage {
            case .needsPrice: check = SchedClosingCheck(id: "bill", label: L("Bill"), value: L("Needs a price"), state: .pending)
            case .noBill: check = SchedClosingCheck(id: "bill", label: L("Bill"), value: L("No bill yet"), state: .pending)
            case .noCharge: check = SchedClosingCheck(id: "bill", label: L("Bill"), value: L("No charge"), state: .ok)
            case .paid, .covered: check = SchedClosingCheck(id: "bill", label: L("Bill"), value: L("Paid"), state: .ok)
            case .forgiven: check = SchedClosingCheck(id: "bill", label: L("Bill"), value: L("Balance forgiven"), state: .ok)
            default: check = SchedClosingCheck(id: "bill", label: L("Bill"), value: Money.format(f.stage == .building ? invoice?.totalAmount : f.collectAmount, currency: currency), state: .ok)
            }
            checks.append(check)
        }
        if canRead && a.reportKind == nil && (f.written || !f.drafts.isEmpty) {
            if f.drafts.isEmpty {
                checks.append(SchedClosingCheck(id: "sign", label: L("Signature"), value: L("Notes signed"), state: .ok))
            } else {
                let value = f.signer != nil ? (f.status == "completed" ? L("Sign it now") : L("Signed when you finish")) : (a.assignedMember?.name.map { LF("Waiting for %@", $0) } ?? L("Waiting for a vet"))
                checks.append(SchedClosingCheck(id: "sign", label: L("Signature"), value: value, state: f.status == "completed" ? .missing : .pending))
            }
        }
        if f.openSinceEarlierDay {
            guard f.theyCame && f.status == "in_progress" else { return nil }
            return SchedVisitClosing(title: L("Ready to finish?"), checks: checks, actionTitle: L("They came"), actionImage: "badge-check") { sheet = .recordPast }
        }
        if f.status == "in_progress" && (f.start || f.checksOut) {
            return SchedVisitClosing(title: L("Ready to finish?"), checks: checks, actionTitle: f.checksOut ? L("Check out") : L("Finish the visit"), actionImage: f.checksOut ? "log-out" : "badge-check") { sheet = .finish }
        }
        if f.status == "completed", let next = primary(a, f) {
            return SchedVisitClosing(title: L("Still to do"), checks: checks, actionTitle: next.title, actionImage: next.systemImage, action: next.action)
        }
        return nil
    }

    // MARK: Header

    /// The shared page header (web `ProviderModuleHeader` on the visit): the pet (its photo
    /// opens the chart), what it came for, the next step and ⋯; the visit's steps as its
    /// numbers; the groom's stage bar, the family's line and the banners as its footer.
    private func header(_ a: SchedAppointment, _ f: Facts) -> some View {
        let dateLabel = SchedDay.upperFirst(DateText.longDay(a.start))
        return ModuleHeader(
            icon: "paw-print",
            title: a.petName,
            subtitle: "\(a.serviceLabel) · \(dateLabel)",
            accent: Theme.aqua,
            media: AnyView(petMedia(a)),
            stats: journey(a, f).map(\.stat),
            actionsOnRow: false,
            storageKey: "visit",
            actions: {
                if let next = primary(a, f) {
                    PMButton(next.title, systemImage: next.systemImage, isWorking: busy, action: next.action)
                }
                menu(a)
            },
            footer: { headerFooter(a, f) }
        )
    }

    @ViewBuilder private func petMedia(_ a: SchedAppointment) -> some View {
        // The header draws its lead 36 round on a phone, 56 on an iPad.
        let face = PetAvatar(name: a.petName, species: a.petSpecies, photoURL: a.petPhotoUrl, size: sizeClass == .regular ? 56 : 36)
        if workspace.can(.clientsView) {
            NavigationLink(value: ProviderRoute.patientChart(petId: a.providerClientPetId)) { face }
                .buttonStyle(.plain)
                .accessibilityLabel(LF("Open %@’s chart", a.petName))
        } else {
            face
        }
    }

    @ViewBuilder private func headerFooter(_ a: SchedAppointment, _ f: Facts) -> some View {
        // A groom that is here: where it is, moved in one tap, and telling the family once it is ready.
        if a.serviceCategory == "groomer", a.groomStage != nil, f.waiting || f.status == "in_progress", f.start {
            RowDivider()
            SchedGroomStageBar(appointment: a, simple: simpleStages) { prompt in sheet = .gate(prompt) }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        RowDivider()
        VStack(alignment: .leading, spacing: 8) {
            let about = [schedSpeciesLabel(a.petSpecies), a.petBreed, schedAge(a.petBirthDate), schedSexLabel(a.petSex)].compactMap { $0?.nonEmpty }
            if !about.isEmpty {
                Text(about.joined(separator: " · ")).font(Theme.text(13, weight: .medium)).foregroundStyle(Theme.inkSoft)
            }
            FlowLayout(spacing: 12, lineSpacing: 8) {
                clientName(a)
                if let phone = a.clientPhone { Text(phone).font(Theme.text(14)).monospacedDigit().foregroundStyle(Theme.inkSoft) }
                // Reaching the family: two equal buttons, not tags.
                if a.clientPhone != nil {
                    HStack(spacing: 8) {
                        if let call = schedPhoneURL(a.clientPhone) {
                            Link(destination: call) { HStack(spacing: 6) { Glyph("phone", size: 14); Text(L("Call")) } }.buttonStyle(.pm(.outline, size: .header))
                        }
                        if let whatsapp = schedWhatsAppURL(a.clientPhone) {
                            Link(destination: whatsapp) { HStack(spacing: 6) { Glyph("message-circle", size: 14); Text("WhatsApp") } }.buttonStyle(.pm(.outline, size: .header))
                        }
                    }
                }
                if !(a.assignedMember?.name.map { schedSameName($0, a.clientName) } ?? false) {
                    Text("· " + (a.assignedMember?.name.map { LF("with %@", $0) } ?? L("Whoever is free"))).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                if let room = a.room { Text("· " + room).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                if a.isRequested { SchedPendingMark() } else if a.rescheduleProposal != nil { SchedRescheduleMark() }
                if a.bookedOnline == true { SchedOnlineMark() }
                if let moved = a.movedFromStartsAt { Text("· " + LF("You moved it from %@", DateText.time(moved))).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                if a.hoursOverride == true { Chip(text: L("After hours"), icon: "moon-star") }
                if a.seriesId != nil { Chip(text: L("Repeats"), icon: "repeat") }
                if a.doubleBooked == true { Chip(text: L("Double booked"), tone: .danger, icon: "triangle-alert") }
                if a.atHome == true { Chip(text: L("At the client’s home"), tone: .info, icon: "house") }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        if SchedVisitBanners.any(a) {
            let forgive = workspace.can(.billingWaiveVisit)
            RowDivider()
            SchedVisitBanners(
                appointment: a,
                onEdit: f.edit ? { sheet = .edit } : nil,
                onCancel: f.cancel ? { sheet = .cancel } : nil,
                onKeep: f.edit ? { keepAsBooked(a) } : nil,
                // The fee charged for the no-show the family disputes: forgiven from here (its bill decides whether anything is left).
                onForgiveFee: forgive && disputedFee != nil && disputedFee.map { CashBillRules.forgiveBlocker($0) == nil } == true
                    ? { if let id = a.feeInvoiceId { sheet = .forgiveFee(id) } } : nil,
                onDismissDispute: (f.edit || forgive) && a.disputeDismissedAt == nil ? { dismissDispute(a) } : nil,
                dismissing: dismissing
            )
        }
    }

    @ViewBuilder private func clientName(_ a: SchedAppointment) -> some View {
        let label = HStack(spacing: 6) {
            Glyph("user-round", size: 16).foregroundStyle(Theme.inkSoft)
            Text(a.clientName).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
        }
        if workspace.can(.clientsView) {
            NavigationLink(value: ProviderRoute.client(a.providerClientId)) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }

    // MARK: The journey

    private func journey(_ a: SchedAppointment, _ f: Facts) -> [SchedJourneyStep] {
        var steps: [SchedJourneyStep] = []
        let since = { (iso: String?) -> Int in max(0, Int(Date().timeIntervalSince(DateText.parse(iso) ?? Date()) / 60)) }
        let booked = DateText.time(a.start)
        if a.isRequested {
            steps.append(.init(id: "arrival", label: L("Arrival"), value: booked, extra: L("To confirm"), state: .next, systemImage: "door-open"))
        } else if let arrived = a.arrivedAt {
            steps.append(.init(id: "arrival", label: L("Arrival"), value: DateText.time(arrived), extra: LF("Booked %@", booked), state: .done, systemImage: "door-open"))
        } else if f.missed {
            steps.append(.init(id: "arrival", label: L("Arrival"), value: a.status == "no_show" ? L("No-show") : L("Cancelled"), state: .attention, systemImage: "door-open"))
        } else if f.dayWhen != "today" && f.status == "scheduled" {
            steps.append(.init(id: "arrival", label: L("Arrival"), value: DateText.day(a.start), extra: f.dayWhen == "past" ? L("Never checked in") : LF("Booked %@", booked), state: f.dayWhen == "past" ? .attention : .next, systemImage: "door-open"))
        } else if f.late {
            steps.append(.init(id: "arrival", label: L("Arrival"), value: LF("%@ late", SchedDay.duration(since(a.startsAt))), extra: LF("Booked %@", booked), state: .attention, systemImage: "door-open"))
        } else {
            steps.append(.init(id: "arrival", label: L("Arrival"), value: booked, extra: L("Booked"), state: .now, systemImage: "door-open"))
        }
        let vetCare = workspace.offers(.vet, .emergency)
        let visitLabel = a.serviceCategory == "groomer" ? L("Grooming") : (a.isClinical && vetCare ? L("Consult") : L("Service"))
        if f.status == "completed", let finished = a.finishedAt {
            let length = a.startedAt.map { start in SchedDay.duration(max(0, Int((DateText.parse(finished) ?? Date()).timeIntervalSince(DateText.parse(start) ?? Date()) / 60))) }
            steps.append(.init(id: "visit", label: visitLabel, value: DateText.time(finished), extra: length, state: .done, systemImage: "stethoscope"))
        } else if f.status == "in_progress" {
            if let stage = groomStageText(a) {
                steps.append(.init(id: "visit", label: visitLabel, value: stage, extra: LF("In for %@", SchedDay.duration(since(a.startedAt))), state: .now, systemImage: "stethoscope"))
            } else {
                steps.append(.init(id: "visit", label: visitLabel, value: LF("In for %@", SchedDay.duration(since(a.startedAt))), extra: a.startedAt.map { LF("Started %@", DateText.time($0)) }, state: .now, systemImage: "stethoscope"))
            }
        } else if f.waiting {
            if let stage = groomStageText(a) {
                steps.append(.init(id: "visit", label: visitLabel, value: stage, extra: LF("Waits %@", SchedDay.duration(since(a.arrivedAt))), state: .now, systemImage: "stethoscope"))
            } else {
                steps.append(.init(id: "visit", label: visitLabel, value: LF("Waits %@", SchedDay.duration(since(a.arrivedAt))), state: .now, systemImage: "stethoscope"))
            }
        } else {
            steps.append(.init(id: "visit", label: visitLabel, value: "—", state: f.missed ? .skip : .next, systemImage: "stethoscope"))
        }
        if workspace.can(.recordsView) && a.reportKind == nil {
            let signer = f.signer != nil
            if !f.drafts.isEmpty && f.status == "completed" {
                steps.append(.init(id: "sign", label: L("Signature"), value: LF("%@ to sign", String(f.drafts.count)), extra: signer ? L("Sign it now") : (a.assignedMember?.name.map { LF("Waiting for %@", $0) } ?? L("Waiting for a vet")), state: .attention, systemImage: "pen-line"))
            } else if !f.drafts.isEmpty {
                steps.append(.init(id: "sign", label: L("Signature"), value: L("Draft saved"), extra: signer ? L("Signed when you finish") : L("A vet signs it"), state: .next, systemImage: "pen-line"))
            } else if f.signedCount > 0 {
                steps.append(.init(id: "sign", label: L("Signature"), value: L("Notes signed"), state: .done, systemImage: "pen-line"))
            } else {
                steps.append(.init(id: "sign", label: L("Signature"), value: L("No note yet"), extra: a.isClinical && f.writable ? L("Best written before finishing") : nil, state: f.missed ? .skip : .next, systemImage: "pen-line"))
            }
        }
        if f.readsBills {
            let currency = invoice?.currency
            let completed = f.status == "completed"
            switch f.stage {
            case .paid: steps.append(.init(id: "pay", label: L("Payment"), value: L("Paid"), extra: invoice.map { Money.format($0.totalAmount, currency: currency) }, state: .done, systemImage: "circle-dollar-sign"))
            case .covered: steps.append(.init(id: "pay", label: L("Payment"), value: L("Nothing to charge"), state: .done, systemImage: "circle-dollar-sign"))
            case .forgiven: steps.append(.init(id: "pay", label: L("Payment"), value: L("Balance forgiven"), extra: invoice?.forgivenAmount.flatMap { $0 > 0 ? Money.format($0, currency: currency) : nil }, state: .done, systemImage: "circle-dollar-sign"))
            case .noCharge: steps.append(.init(id: "pay", label: L("Payment"), value: L("No charge"), state: .done, systemImage: "circle-dollar-sign"))
            case .ready, .partPaid: steps.append(.init(id: "pay", label: L("Payment"), value: Money.format(f.collectAmount, currency: currency), extra: L("To pay"), state: .attention, systemImage: "circle-dollar-sign"))
            case .building: steps.append(.init(id: "pay", label: L("Payment"), value: Money.format(invoice?.totalAmount, currency: currency), extra: completed ? L("To pay") : L("On the bill"), state: completed ? .attention : .next, systemImage: "circle-dollar-sign"))
            case .needsPrice: steps.append(.init(id: "pay", label: L("Payment"), value: L("Needs a price"), state: completed ? .attention : .next, systemImage: "circle-dollar-sign"))
            case .noBill: steps.append(.init(id: "pay", label: L("Payment"), value: L("No bill yet"), state: .next, systemImage: "circle-dollar-sign"))
            default: steps.append(.init(id: "pay", label: L("Payment"), value: "—", state: f.missed ? .skip : .next, systemImage: "circle-dollar-sign"))
            }
        }
        return steps
    }

    // MARK: The booking

    /// What was booked, and the client, pet and chart one tap away (not on the web's page; kept).
    private func bookingCard(_ a: SchedAppointment, _ f: Facts) -> some View {
        SectionCard(title: L("The booking"), icon: "calendar-days", accent: Theme.aqua) {
            if f.edit && (f.status == "scheduled" || f.status == "checked_in") {
                PMButton(L("Edit booking"), systemImage: "pencil", variant: .outline, size: .header) { sheet = .edit }
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                FactRow(label: L("When"), value: "\(SchedDay.upperFirst(DateText.longDay(a.start))) · \(DateText.time(a.start))\(a.end.map { "–" + DateText.time($0) } ?? "")")
                FactRow(label: L("Service"), value: a.serviceLabel)
                FactRow(label: L("Person"), value: a.assignedMember?.name ?? L("Whoever is free"))
                FactRow(label: L("Room"), value: a.room)
                FactRow(label: L("Status"), value: SchedStatus.label(a.status))
                if let confirmation = SchedStatus.confirmationLabel(a.confirmationStatus) {
                    FactRow(label: L("Confirmation"), value: confirmation)
                }
                if a.bookedOnline == true { FactRow(label: L("Booked"), value: L("Booked online")) }
                else if let by = a.createdBy?.name { FactRow(label: L("Booked by"), value: by) }
                if let notes = a.notes?.nonEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Notes")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                        Text(notes).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    }
                }
                if let access = a.accessNotes?.nonEmpty { FactRow(label: L("Access notes"), value: access) }
            }
            .padding(16)
            if workspace.can(.clientsView) {
                RowDivider()
                linkRow(L("Client"), title: a.clientName, route: .client(a.providerClientId)) {
                    Avatar(name: a.clientName, imageURL: a.clientPhotoUrl, size: 32)
                }
                RowDivider()
                linkRow(L("Pet"), title: a.petName, route: .clientPet(clientId: a.providerClientId, petId: a.providerClientPetId)) {
                    PetAvatar(name: a.petName, species: a.petSpecies, photoURL: a.petPhotoUrl, size: 32)
                }
                RowDivider()
                linkRow(L("Allergies, weight, vaccines and history"), title: L("Patient chart"), route: .patientChart(petId: a.providerClientPetId)) {
                    IconBadge(icon: "file-text", accent: Theme.aqua, size: 32, iconSize: 16, ink: .strong, washPercent: 35)
                }
            }
        }
    }

    private func linkRow<Lead: View>(_ hint: String, title: String, route: ProviderRoute, @ViewBuilder lead: () -> Lead) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                lead()
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text(hint).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 8)
                Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: The menu

    /// The header's ⋯ (web: the visit's dropdown): the less common moves, the risky ones last in red.
    private func menu(_ a: SchedAppointment) -> some View {
        let f = facts(a)
        let late = f.status == "scheduled" && f.late && f.checkIn
        let cancels = (f.status == "scheduled" || f.status == "checked_in") && f.cancel
        let stops = a.seriesId != nil && f.status == "scheduled" && f.cancel
        return Menu {
            if f.edit && (f.status == "scheduled" || f.status == "checked_in") {
                Button { sheet = .edit } label: { GlyphLabel(L("Edit booking"), icon: "pencil") }
            }
            if f.edit && f.status == "scheduled" && a.clientEmail?.nonEmpty != nil {
                Button { askToConfirm(a) } label: { GlyphLabel(L("Ask them to confirm"), icon: "mail-check") }
            }
            Button { sheet = .calendar } label: { GlyphLabel(L("Add to calendar"), icon: "download") }
            if f.status == "checked_in" && f.checkIn {
                Button { move(a, "undo-arrival", L("Back to upcoming.")) } label: { GlyphLabel(L("Undo arrival"), icon: "undo-2") }
            }
            if f.status == "completed" && f.start && !f.paid {
                Button { move(a, "reopen", L("Back with the vet.")) } label: { GlyphLabel(L("Reopen visit"), icon: "rotate-ccw") }
            }
            // Hospitalizing is rare on a routine visit: it lives here unless triage makes it urgent.
            if f.canHospitalize {
                Button { hospitalize(a, nil) } label: { GlyphLabel(L("Hospitalize"), icon: "bed-double") }
            }
            if let stay = f.openStay {
                Button { pushed = .hospitalization(stay.id) } label: { GlyphLabel(L("Open the hospitalization"), icon: "bed-double") }
            }
            if workspace.can(.appointmentsCreate) && workspace.can(.clientsView) && !a.isRequested {
                Button { sheet = .walkIn } label: { GlyphLabel(L("Walk-in"), icon: "zap") }
            }
            if late || cancels || stops { Divider() }
            if late {
                Button(role: .destructive) { sheet = .noShow } label: { GlyphLabel(L("They didn’t come"), icon: "circle-slash") }
            }
            if cancels {
                Button(role: .destructive) { sheet = .cancel } label: { GlyphLabel(L("Cancel visit"), icon: "calendar-x-2") }
            }
            if stops {
                Button(role: .destructive) { sheet = .stopSeries } label: { GlyphLabel(L("Stop repeating from here"), icon: "repeat") }
            }
        } label: {
            IconCircleLabel()
        }
        .accessibilityLabel(L("More"))
    }

    /// A groom's stage as the journey's middle step ("Estética · En baño").
    private func groomStageText(_ a: SchedAppointment) -> String? {
        guard a.serviceCategory == "groomer", let stage = a.groomStage else { return nil }
        return SchedGroomStageBar.label(simpleStages && stage == "styling" ? "bath" : stage, simple: simpleStages)
    }

    // MARK: Sheets

    @ViewBuilder private func sheetView(_ item: SchedVisitSheet, _ a: SchedAppointment) -> some View {
        let f = facts(a)
        switch item {
        case .edit:
            SchedBookingSheet(draft: SchedBookingDraft(appointment: a))
        case .walkIn:
            SchedBookingSheet(draft: SchedBookingDraft(mode: .walkIn, clientId: a.providerClientId, petId: a.providerClientPetId)) { prompt in showGate(prompt) }
        case .checkIn:
            SchedCheckInSheet(appointment: a, canStart: f.start) { prompt in showGate(prompt) }
        case .otherDay:
            SchedOtherDaySheet(
                appointment: a,
                when: f.dayWhen == "past" ? "past" : "future",
                canMove: f.edit,
                onMoved: { Task { await load(); sheet = .checkIn } },
                onNoShow: f.checkIn ? { sheet = .noShow } : nil,
                onWalkIn: workspace.can(.appointmentsCreate) && workspace.can(.clientsView) ? { sheet = .walkIn } : nil,
                onRecordPast: f.theyCame || (f.start && f.dayWhen == "past" && (a.start.map { Date().timeIntervalSince($0) } ?? 0) <= 31 * 86_400) ? { sheet = .recordPast } : nil
            )
        case .finish:
            SchedFinishSheet(appointment: a, drafts: f.drafts.count, signed: f.signedCount, invoice: invoice, signer: f.signer, collects: f.collects, onAfter: { _ in openBillAfterClosing() }, onEarlierDay: f.start ? { reopenAs(.recordPast) } : nil)
        case .recordPast:
            SchedRecordPastSheet(appointment: a, invoice: invoice, collects: f.collects) { _ in openBillAfterClosing() }
        case .noShow:
            SchedMissedSheet(appointment: a, mode: "no_show")
        case .cancel:
            SchedMissedSheet(appointment: a, mode: "cancel")
        case .rebook:
            SchedRebookSheet(appointment: a)
        case .stopSeries:
            ConfirmSheet(title: L("Stop repeating from here"), message: L("Cancel this visit and every later one of the repeating booking?"), confirmTitle: L("Stop repeating"), destructive: true) { _ in
                let result: SchedStopSeriesResult = try await API.post("/provider-appointments/\(a.id)/stop-series", body: ["reason": nil])
                announceDataChanged()
                Toast.show(LF("%@ visits cancelled.", String(result.cancelled ?? 0)))
            }
        case .gate(let prompt):
            SchedGateSheet(prompt: prompt)
        case .forgiveFee(let id):
            CashForgiveBillSheet(invoiceId: id, listed: disputedFee) { Task { await load() } }
        case .calendar:
            SchedCalendarSheet(appointment: a)
        case .admit(let preset):
            SchedAdmitSheet(preset: preset) { id in
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    pushed = .hospitalization(id)
                }
            }
        case .deposit(let due):
            DepositSheet(clientId: a.providerClientId, clientName: a.clientName, appointmentId: a.id, owed: due.owed, currency: due.currency,
                         label: LF("Emergency deposit · %@", a.petName), explanation: L("It stays as credit on their account and is used when they pay the visit."))
        }
    }

    /// Hospitalize the visit's patient, with what the triage said (docs/hospitalization.md).
    private func hospitalize(_ a: SchedAppointment, _ triage: SchedTriage?) {
        sheet = .admit(SchedAdmitPreset(appointmentId: a.id, clientName: a.clientName, familyOnApp: a.clientHouseholdId != nil,
                                        petId: a.providerClientPetId, petName: a.petName, priority: triage?.triagePriority, reason: triage?.triageReason))
    }

    /// A record into this visit (a vaccine, an allergy, a diagnosis, a medicine, or any).
    private func addRecord(_ a: SchedAppointment, _ type: String?) {
        pushed = .newRecord(RecordPrefill(clientId: a.providerClientId, petId: a.providerClientPetId, appointmentId: a.id, recordType: type))
    }

    private func showGate(_ prompt: SchedGatePrompt) {
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            sheet = .gate(prompt)
        }
    }

    private func reopenAs(_ next: SchedVisitSheet) {
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            sheet = next
        }
    }

    /// After "Charge now" or "Put the price myself": the bill, in Cuentas.
    private func openBillAfterClosing() {
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            let bill = await Self.bill(for: appointmentId)
            invoice = bill
            if let bill { pushed = .invoice(bill.id) }
        }
    }

    // MARK: Actions

    /// Only today's visits check in: on another day, "Check in" first offers to move it to today.
    private func arrive(_ f: Facts) {
        sheet = f.dayWhen == "today" ? .checkIn : .otherDay
    }

    private func startVisit(_ a: SchedAppointment) {
        busy = true
        Task {
            defer { busy = false }
            await SchedVisitOps.startWithGate(a) { prompt in sheet = .gate(prompt) }
            await load()
        }
    }

    private func signAll(_ a: SchedAppointment, _ drafts: [SchedRecord]) {
        busy = true
        Task {
            defer { busy = false }
            do {
                for draft in drafts { try await API.send("POST", "/provider-records/\(draft.id)/sign", body: [:]) }
                Toast.show(a.clientHouseholdId != nil ? L("Signed. The family can see it now.") : L("Signed. It is part of the chart now."))
                announceDataChanged()
            } catch { Toast.error(error) }
        }
    }

    /// "Descartar" a family's "Sí fuimos": off Home's "Te necesita"; the answer stays on the visit.
    private func dismissDispute(_ a: SchedAppointment) {
        guard !dismissing else { return }
        dismissing = true
        Task {
            defer { dismissing = false }
            do {
                let _: SchedDisputeDismissed = try await API.post("/provider-appointments/\(a.id)/dispute/dismiss")
                Toast.show(L("Dismissed. Their answer stays on the visit."))
                announceDataChanged()
                await load()
            } catch let error as APIError where error.code == "no_dispute" {
                Toast.error(L("The family has not answered this visit"))
            } catch {
                schedToast(error)
            }
        }
    }

    private func keepAsBooked(_ a: SchedAppointment) {
        Task {
            do {
                let _: SchedAppointment = try await API.patch("/provider-appointments/\(a.id)", body: ["confirmationStatus": "confirmed"])
                Toast.show(L("Kept as booked."))
                announceDataChanged()
            } catch { Toast.error(error) }
        }
    }

    private func askToConfirm(_ a: SchedAppointment) {
        Task {
            do {
                let result: SchedConfirmationResult = try await API.post("/provider-appointments/\(a.id)/confirmation-request")
                if result.emailStatus == "failed" { Toast.error(result.errorMessage ?? L("The confirmation email failed.")) }
                else { Toast.show(L("Confirmation request sent.")) }
                announceDataChanged()
            } catch { Toast.error(error) }
        }
    }

    private func move(_ a: SchedAppointment, _ path: String, _ success: String) {
        Task {
            do {
                let _: SchedMoveResponse = try await SchedAPI.send("POST", "/provider-appointments/\(a.id)/\(path)", body: [:])
                Toast.show(success)
                announceDataChanged()
            } catch { schedToast(error) }
        }
    }
}
