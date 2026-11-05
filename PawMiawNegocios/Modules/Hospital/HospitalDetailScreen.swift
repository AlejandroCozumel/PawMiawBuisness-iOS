//
//  HospitalDetailScreen.swift
//  PawMiawNegocios
//
//  One hospitalized patient (web provider.hospital.$hospitalizationId.tsx +
//  hospital-detail-view.tsx): the pet and its family, where it stands, the
//  gate while it waits (the estimate signed, the deposit paid, Admit), the
//  estimate still to sign once in, how it ended, then the treatment sheet,
//  orders, vitals, updates to the family, rounds and the running bill; and
//  discharge, transfer, death (and undoing it) for whoever manages the
//  hospital.
//

import SwiftUI
import QuickLook

struct HospitalDetailScreen: View {
    let hospitalizationId: String

    var body: some View {
        HospDetailPage(id: hospitalizationId)
    }
}

/// The page's data: the detail on one day of the sheet; every write answers the detail.
@MainActor
final class HospDetailModel: ObservableObject {
    let id: String
    @Published var detail: HospDetail?
    @Published var error: String?
    @Published var notFound = false
    /// The sheet's day (nil = today).
    @Published var day: String?

    init(id: String) { self.id = id }

    func load() async {
        do {
            let loaded: HospDetail = try await API.get(HospAPI.detailPath(id), query: ["day": day])
            detail = loaded
            error = nil
        } catch is CancellationError {
        } catch {
            if detail == nil {
                notFound = (error as? APIError)?.code == "not_found" || (error as? APIError)?.status == 404
                self.error = errorText(error)
            }
        }
    }

    @discardableResult
    func write(_ path: String, method: String = "POST", body: [String: Any?] = [:]) async throws -> HospDetail {
        let answer = try await HospAPI.write(id, path, method: method, body: body)
        if day == nil || answer.sheet?.day == day { detail = answer }
        return answer
    }
}

enum HospDetailTab: Hashable { case sheet, orders, vitals, updates, rounds, bill }

/// What the page opens over itself.
enum HospDetailSheet: Identifiable {
    case discharge, transfer, death, undoDeath, placement, deposit
    case sign(String, admitAfter: Bool)

    var id: String {
        switch self {
        case .discharge: "discharge"
        case .transfer: "transfer"
        case .death: "death"
        case .undoDeath: "undo"
        case .placement: "placement"
        case .deposit: "deposit"
        case .sign(let id, _): "sign-\(id)"
        }
    }
}

struct HospDetailPage: View {
    let id: String
    var signFirst: String? = nil
    var admitAfterSigning: Bool = false

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var model: HospDetailModel
    @State private var tab: HospDetailTab = .sheet
    @State private var sheet: HospDetailSheet?
    /// A PDF downloaded for Quick Look (the same way DocumentButton opens one: share and print from there).
    @State private var pdf: URL?
    @State private var openedSign = false

    init(id: String, signFirst: String? = nil, admitAfterSigning: Bool = false) {
        self.id = id
        self.signFirst = signFirst
        self.admitAfterSigning = admitAfterSigning
        _model = StateObject(wrappedValue: HospDetailModel(id: id))
    }

    private var canManage: Bool { workspace.can(.hospitalManage) }
    private var canCare: Bool { workspace.can(.hospitalCare) }
    private var canOverride: Bool { workspace.isOwnerOrAdmin }
    private var seesBill: Bool { workspace.moneyLevel >= .charging }

    var body: some View {
        Group {
            if workspace.current != nil && !workspace.can(.hospitalView) {
                PageScroll { NoAccessState(message: L("Ask the workspace owner to give your role access to the hospital.")) }
            } else if let detail = model.detail {
                content(detail)
            } else if model.error != nil {
                PageScroll {
                    EmptyState(systemImage: "bed-double", title: model.notFound ? L("This hospitalization was not found.") : L("This hospitalization can’t be opened."),
                               message: L("It may be at another location, or it was removed."), accent: Theme.pink, panel: true)
                    if !model.notFound { ErrorState(message: model.error ?? "") { await model.load() } }
                }
            } else {
                PageScroll { LoadingState() }
            }
        }
        .providerPage(model.detail?.petName ?? L("Hospitalization"))
        .reloadsOnScope { await model.load() }
        .modifier(HospEveryMinute { await model.load() })
        .onChange(of: model.day) { _, _ in Task { await model.load() } }
        .onChange(of: model.detail?.id) { _, _ in
            if let signFirst, !openedSign { openedSign = true; sheet = .sign(signFirst, admitAfter: admitAfterSigning) }
        }
        .sheet(item: $sheet) { which in
            if let detail = model.detail { sheetView(which, detail) }
        }
        .quickLookPreview($pdf)
    }

    // MARK: Header actions (web: the module header's actions)

    @ViewBuilder private func headerActions(_ detail: HospDetail) -> some View {
        let undoable = detail.end?.kind == "deceased" && (DateText.parse(detail.end?.undoableUntil).map { $0 > Date() } ?? false)
        if detail.isAdmitted && canManage {
            PMButton(L("Discharge"), systemImage: "heart-handshake") { sheet = .discharge }
            Menu {
                Button { sheet = .placement } label: { GlyphLabel(L("Ward, vet and estimate"), icon: "pencil") }
                Button { sheetPDF(detail) } label: { GlyphLabel(L("Print the day’s sheet"), icon: "printer") }
                Button { sheet = .transfer } label: { GlyphLabel(L("Transfer"), icon: "arrow-right-left") }
                Divider()
                Button(role: .destructive) { sheet = .death } label: { GlyphLabel(L("Record a death"), icon: "feather") }
            } label: {
                IconCircleLabel()
            }
            .accessibilityLabel(L("More"))
        }
        if detail.isPending && canManage {
            PMButton(L("Change"), systemImage: "pencil", variant: .outline) { sheet = .placement }
        }
        if detail.end != nil {
            PMButton(detail.end?.kind == "discharged" ? L("Discharge PDF") : L("Discharge summary"), systemImage: "file-down", variant: .outline) { dischargePDF(detail) }
        }
        if !detail.isAdmitted && !detail.isPending && detail.end == nil {
            PMButton(L("Day’s sheet PDF"), systemImage: "printer", variant: .outline) { sheetPDF(detail) }
        }
        if undoable && canOverride {
            PMButton(L("Undo"), systemImage: "rotate-ccw", variant: .outline) { sheet = .undoDeath }
        }
    }

    private func sheetPDF(_ detail: HospDetail) {
        let day = detail.sheet?.day ?? detail.sheet?.today ?? DateText.dayKey(Date(), zone: detail.zone)
        openPDF(HospAPI.detailPath(detail.id) + "/sheet/pdf", query: ["day": day], fileName: "\(L("Sheet")) \(detail.petName) \(day)")
    }

    private func dischargePDF(_ detail: HospDetail) {
        openPDF(HospAPI.detailPath(detail.id) + "/discharge/pdf", fileName: "\(L("Discharge summary")) \(detail.petName)")
    }

    private func openPDF(_ path: String, query: [String: String?] = [:], fileName: String) {
        Task {
            do {
                pdf = try await API.download(path, query: query, fileName: fileName)
            } catch {
                Toast.error(error, fallback: L("The file could not be opened. Try again."))
            }
        }
    }

    // MARK: Page

    private func content(_ detail: HospDetail) -> some View {
        PageScroll(maxWidth: 1100, refresh: { await model.load() }) {
            HospDetailHeader(detail: detail, canOpenChart: workspace.can(.clientsView)) { headerActions(detail) }
            if detail.isPending {
                HospGatePanel(model: model, detail: detail, canManage: canManage, canOverride: canOverride,
                              canTakeDeposit: workspace.can(.billingRecordPayment)) { sheet = $0 }
            }
            if detail.isAdmitted {
                HospEstimateToSign(detail: detail, canManage: canManage) { sheet = $0 }
                // Missed until marked: the patient's one notice, gone once each dose is marked.
                if let missed = detail.attention?.m, missed > 0 {
                    NoticeCard(
                        tone: .problem,
                        title: missed == 1 ? LF("Missed treatment: %@", detail.petName) : LF("%d treatments not marked: %@", missed, detail.petName),
                        message: missed == 1 ? L("Mark it or note why it wasn’t given.") : L("Mark them or note why they weren’t given."),
                        actionTitle: tab == .sheet ? nil : L("Open the sheet")
                    ) { tab = .sheet }
                }
            }
            HospEndBanner(detail: detail)
            if detail.status != "cancelled" {
                ToneTabs(tabs: tabs, selection: $tab, look: .solid)
                switch tab {
                case .sheet:
                    HospSheetTab(model: model, detail: detail, canCare: canCare, canManage: canManage,
                                 onOrders: { tab = .orders }, onPrint: { sheetPDF(detail) })
                case .orders:
                    HospOrdersTab(model: model, detail: detail, canManage: canManage)
                case .vitals:
                    HospVitalsTab(model: model, detail: detail, canCare: canCare)
                case .updates:
                    HospUpdatesTab(model: model, detail: detail, canCare: canCare)
                case .rounds:
                    HospRoundsTab(model: model, detail: detail, canManage: canManage)
                case .bill:
                    HospBillTab(detail: detail, canManage: canManage)
                }
            }
        }
    }

    private var tabs: [ToneTabs<HospDetailTab>.Tab] {
        var list: [ToneTabs<HospDetailTab>.Tab] = [
            .init(.sheet, L("Sheet"), icon: "syringe"), .init(.orders, L("Orders"), icon: "clipboard-list"), .init(.vitals, L("Vitals"), icon: "activity"),
            .init(.updates, L("Updates"), icon: "message-square-text"), .init(.rounds, L("Rounds"), icon: "shield-check"),
        ]
        if seesBill { list.append(.init(.bill, L("Bill"), icon: "receipt")) }
        return list
    }

    @ViewBuilder private func sheetView(_ which: HospDetailSheet, _ detail: HospDetail) -> some View {
        switch which {
        case .discharge:
            HospDischargeSheet(model: model, detail: detail) { day in
                model.day = day == detail.sheet?.today ? nil : day
                tab = .sheet
            } onPDF: { dischargePDF(detail) }
        case .transfer:
            HospTransferSheet(model: model, detail: detail)
        case .death:
            HospDeathSheet(model: model, detail: detail, canOverride: canOverride)
        case .undoDeath:
            ConfirmSheet(
                title: L("Undo the recorded death?"),
                message: LF("%@ is admitted again and the paused routines resume. Cancelled reminders and visits stay cancelled.", detail.patient?.name ?? L("The patient")),
                confirmTitle: L("Undo"),
                destructive: true,
                askReason: true,
                reasonRequired: true,
                cancelTitle: L("Keep it")
            ) { reason in
                do {
                    try await model.write("/death/undo", body: ["reason": reason ?? ""])
                    Toast.show(L("Undone. The patient is admitted again."))
                } catch { throw hospRefusal(error, fallback: "Could not undo it.") }
            }
        case .placement:
            HospPlacementSheet(model: model, detail: detail)
        case .deposit:
            if let client = detail.client {
                let gate = detail.gate?.deposit
                let owed = max(0, (gate?.amount ?? 0) - (gate?.paid ?? 0))
                DepositSheet(clientId: client.id, clientName: client.name ?? "", hospitalizationId: detail.id, owed: owed > 0 ? owed : nil,
                             currency: detail.money, label: LF("Hospitalization deposit · %@", detail.petName),
                             explanation: L("It stays as credit on their account and is used when they pay the hospital bill.")) {
                    await model.load()
                }
            } else {
                ProviderModal(title: L("Take a deposit"), systemImage: "hand-coins", accent: .lime) {
                    ErrorState(message: L("This hospitalization was not found.")) { await model.load() }
                }
            }
        case .sign(let consentId, let admitAfter):
            ConsentSignSheet(consentId: consentId, businessName: workspace.current?.name, successMessage: L("Signed. It is kept with the hospitalization.")) {
                Task { await model.load() }
                if admitAfter { Task { await admitAfterSign(detail) } }
            }
        }
    }

    /// Signed here with "Admit now" on: the patient goes in when nothing else is owed.
    private func admitAfterSign(_ detail: HospDetail) async {
        do {
            let answer = try await model.write("/admit")
            Toast.show(answer.client?.onPawMiaw == true ? LF("%@ is in the hospital. The family has been told.", answer.petName) : LF("%@ is in the hospital.", answer.petName))
        } catch {
            let code = (error as? APIError)?.code
            if code == "deposit_required" { Toast.show(LF("%@ is waiting for admission.", detail.petName) + " " + L("Take the deposit, then admit.")) }
            else if code != "consent_required" { Toast.error(hospError(error, fallback: "Could not admit the patient.")) }
        }
    }
}

// MARK: - Header

/// The page's module header (web hospital-detail-view): the pet's photo (it
/// opens the chart), its name, what it is; where it stands as four numbers;
/// the reason, the family and the allergies in the footer.
private struct HospDetailHeader<Actions: View>: View {
    let detail: HospDetail
    let canOpenChart: Bool
    @ViewBuilder let actions: () -> Actions
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var aboutPet: String {
        let weight = detail.patient?.weightGrams.map { LF("%@ kg", HospFmt.number($0 / 1000, digits: 2)) }
        return [detail.patient?.species.map(speciesWord), detail.patient?.breed, weight].compactMap { $0?.nonEmpty }.joined(separator: " · ")
    }

    private var stats: [ModuleStat] {
        let zone = detail.zone
        return [
            ModuleStat("status", label: L("Status"), value: HospWords.status(detail.status),
                       hint: detail.admittedAt != nil ? LF("Since %@", HospFmt.dateTime(detail.admittedAt, zone)) : LF("Asked %@", HospFmt.dateTime(detail.requestedAt, zone)),
                       icon: "activity", accent: HospTone.status(detail.status), active: true),
            ModuleStat("day", label: L("Day"), value: detail.dayNumber.map(String.init) ?? "—",
                       hint: detail.isAdmitted ? detail.nextDueAt.map { LF("Next %@", HospFmt.clock($0, zone)) } : nil,
                       icon: "calendar-check", accent: Theme.mango),
            ModuleStat("where", label: L("Ward"), value: detail.room?.name ?? L("Not placed"),
                       hint: detail.cageLabel.map { LF("Cage %@", $0) }, icon: "bed-double", accent: Theme.aqua, muted: detail.room == nil),
            ModuleStat("vet", label: L("Vet"), value: detail.attending?.name ?? "—",
                       hint: detail.condition.map { HospWords.condition($0) }, icon: "stethoscope", accent: Theme.lime, muted: detail.attending == nil),
        ]
    }

    var body: some View {
        ModuleHeader(
            icon: "paw-print",
            title: detail.petName,
            subtitle: aboutPet.nonEmpty,
            accent: Theme.pink,
            media: AnyView(chartLink {
                // The header's photo well: 36 on a phone, 56 wider.
                PetAvatar(name: detail.petName, species: detail.patient?.species, photoURL: detail.patient?.photoUrl, size: sizeClass == .regular ? 56 : 36)
                    .grayscale(detail.status == "deceased" ? 1 : 0)
            }),
            stats: stats,
            storageKey: "hospital-patient",
            actions: actions,
            footer: { footer }
        )
    }

    @ViewBuilder private var footer: some View {
        let triage = detail.triagePriority.flatMap { detail.isAdmitted || detail.isPending ? $0 : nil }
        let reason = detail.reason?.nonEmpty
        let allergies = detail.patient?.allergies ?? []
        if triage != nil || reason != nil || detail.client != nil || !allergies.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if triage != nil || reason != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        if let triage { HospTriageBadge(priority: triage) }
                        if let reason { Text(reason).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(2) }
                    }
                }
                if detail.client != nil || !allergies.isEmpty {
                    FlowLayout(spacing: 8) {
                        if let client = detail.client {
                            clientName(client)
                            if let phone = client.phone?.nonEmpty, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                                Link(destination: url) {
                                    HStack(spacing: 6) {
                                        Glyph("phone", size: 14)
                                        Text(phone).monospacedDigit()
                                    }
                                }
                                .buttonStyle(.pm(.outline, size: .compact))
                            }
                        }
                        HospAllergyChip(allergies: allergies)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { RowDivider() }
        }
    }

    @ViewBuilder private func clientName(_ client: HospClientRef) -> some View {
        let label = HStack(spacing: 6) {
            Glyph("user-round", size: 16).foregroundStyle(Theme.inkSoft)
            Text(client.name ?? "").font(Theme.text(14, weight: .bold)).lineLimit(1)
        }
        if canOpenChart {
            NavigationLink(value: ProviderRoute.client(client.id)) { label.foregroundStyle(Theme.blue) }
                .buttonStyle(.plain)
                .frame(minHeight: 40)
        } else {
            label.foregroundStyle(Theme.inkStrong).frame(minHeight: 40)
        }
    }

    @ViewBuilder private func chartLink<Label: View>(@ViewBuilder _ label: () -> Label) -> some View {
        if canOpenChart, let client = detail.client?.id, let pet = detail.patient?.providerClientPetId {
            NavigationLink(value: ProviderRoute.clientPet(clientId: client, petId: pet)) { label() }.buttonStyle(.plain)
        } else {
            label()
        }
    }

    private func speciesWord(_ species: String) -> String {
        switch species.lowercased() {
        case "dog": L("Dog")
        case "cat": L("Cat")
        case "bird": L("Bird")
        case "rabbit": L("Rabbit")
        case "fish": L("Fish")
        case "reptile": L("Reptile")
        default: species
        }
    }
}

// MARK: - The gate (waiting for admission)

private struct HospGatePanel: View {
    @ObservedObject var model: HospDetailModel
    let detail: HospDetail
    let canManage: Bool
    let canOverride: Bool
    let canTakeDeposit: Bool
    let open: (HospDetailSheet) -> Void

    @State private var admitting = false
    @State private var asking = false
    @State private var overriding = false
    @State private var roomFull: String?
    @State private var cancelling = false

    var body: some View {
        let gate = detail.gate
        let consent = gate?.consent
        let deposit = gate?.deposit
        let currency = detail.money
        let amount = deposit?.amount ?? 0, paid = deposit?.paid ?? 0
        let owed = max(0, amount - paid)
        let pending = consent?.required == true && consent?.consentId != nil && consent?.status == "pending"
        let estimate = Money.format(detail.estimateAmount ?? 0, currency: currency)
        let done = (consent?.satisfied == true ? 1 : 0) + (deposit?.satisfied == true ? 1 : 0)

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Before admission").uppercased()).font(Theme.text(12, weight: .bold)).tracking(12 * 0.14).foregroundStyle(Theme.blue)
                    Text(gate?.ready == true ? L("Ready to admit") : LF("%@ is waiting for admission", detail.petName))
                        .font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
                }
                Spacer(minLength: 8)
                Chip(text: LF("%d of %d ready", done, 2), tone: .custom(gate?.ready == true ? ProviderState.done.color : Theme.mango), dot: gate?.ready == true ? ProviderState.done.color : Theme.mango, percent: 22)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)], spacing: 12) {
                gateCard(ok: consent?.satisfied == true, icon: consent?.satisfied == true ? "shield-check" : "shield-alert", title: L("Hospitalization estimate"),
                         line: consent?.required != true ? L("No estimate: nothing to sign.")
                            : consent?.satisfied == true ? LF("Signed for %@.", Money.format(consent?.amountCents ?? detail.estimateAmount ?? 0, currency: currency))
                            : consent?.reason == "amount_changed" ? LF("The estimate went up to %@ since it was signed: ask again.", estimate)
                            : consent?.reason == "missing" ? LF("Not asked yet (%@).", estimate)
                            : consent?.status == "declined" ? L("The family declined it.")
                            : LF("Waiting for the family’s signature (%@).", estimate)) {
                    if consent?.required == true && consent?.satisfied != true && canManage {
                        FlowLayout(spacing: 8) {
                            PMButton(L("Sign here"), systemImage: "pen-line", size: .compact, isWorking: asking) {
                                if pending, let id = consent?.consentId { open(.sign(id, admitAfter: false)) } else { Task { await ask(notify: false) } }
                            }
                            if detail.client?.onPawMiaw == true {
                                PMButton(pending ? L("Send again") : L("Send to the family"), systemImage: "send", variant: .outline, size: .compact, isWorking: asking) {
                                    Task { await ask(notify: true) }
                                }
                            }
                        }
                    }
                }
                gateCard(ok: deposit?.satisfied == true, icon: "piggy-bank", title: L("Deposit"),
                         line: amount <= 0 ? L("No deposit asked.")
                            : deposit?.waivedByTriage == true ? L("Waived: a critical emergency is never held back by money.")
                            : deposit?.satisfied == true ? LF("Paid: %@ of %@.", Money.format(paid, currency: currency), Money.format(amount, currency: currency))
                            : LF("%@ paid of %@ — %@ to go.", Money.format(paid, currency: currency), Money.format(amount, currency: currency), Money.format(owed, currency: currency))) {
                    if deposit?.satisfied != true && canTakeDeposit && detail.client != nil {
                        PMButton(L("Take the deposit"), systemImage: "hand-coins", size: .compact) { open(.deposit) }
                    }
                }
            }
            if canManage {
                // Phone: stacked, the admission on top (web flex-col-reverse).
                VStack(spacing: 8) {
                    PMButton(LF("Admit %@", detail.petName), systemImage: "bed-double", fullWidth: true, isWorking: admitting) { Task { await admit([:]) } }
                        .disabled(gate?.ready != true)
                    if gate?.ready != true && canOverride {
                        PMButton(L("Admit anyway"), variant: .outline, fullWidth: true) { overriding = true }
                    }
                    PMButton(L("Cancel admission"), systemImage: "circle-x", variant: .destructive, fullWidth: true) { cancelling = true }
                }
                .padding(.top, 16)
                .overlay(alignment: .top) { Rectangle().fill(Theme.mix(Theme.mango, 40, with: Theme.borderSoft)).frame(height: 1) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(Theme.mango, 8), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.mix(Theme.mango, 60, with: Theme.borderSoft), style: StrokeStyle(lineWidth: 2, dash: [7, 5])))
        .cardShadow()
        .sheet(isPresented: $overriding) {
            let consentOK = consent?.satisfied == true, depositOK = deposit?.satisfied == true
            ConfirmSheet(
                title: !consentOK && !depositOK ? L("Admit without the signed estimate or the deposit?")
                    : !consentOK ? L("Admit without the signed estimate?") : L("Admit before the deposit is paid?"),
                message: L("Only owners and admins can. It is written down with your name and the reason."),
                confirmTitle: L("Admit anyway"),
                destructive: true,
                askReason: true,
                reasonRequired: true,
                cancelTitle: L("Not now")
            ) { reason in
                try await admitOrThrow(["overrideConsent": !consentOK, "overrideDeposit": !depositOK, "overrideReason": reason ?? ""])
            }
        }
        .sheet(isPresented: Binding(get: { roomFull != nil }, set: { if !$0 { roomFull = nil } })) {
            ConfirmSheet(title: L("Place the patient anyway?"), message: roomFull, confirmTitle: L("Place anyway"), destructive: true) { _ in
                try await admitOrThrow(["allowOverCapacity": true])
            }
        }
        .sheet(isPresented: $cancelling) {
            ConfirmSheet(
                title: L("Cancel this admission?"),
                message: LF("%@ leaves the board and the unsigned estimate is withdrawn.", detail.petName),
                confirmTitle: L("Cancel admission"),
                destructive: true,
                askReason: true,
                reasonRequired: true,
                cancelTitle: L("Keep it")
            ) { reason in
                do {
                    try await model.write("/cancel", body: ["reason": reason ?? ""])
                    Toast.show(L("Admission cancelled."))
                } catch { throw hospRefusal(error, fallback: "Could not cancel it.") }
            }
        }
    }

    /// One thing admission waits on (web `GateCard`): a 40 disc (green with a
    /// check badge when done, mango while it waits), the title and its line.
    private func gateCard<Actions: View>(ok: Bool, icon: String, title: String, line: String, @ViewBuilder actions: () -> Actions) -> some View {
        let tone = ok ? ProviderState.done.color : Theme.mango
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Glyph(icon, size: 20)
                    .foregroundStyle(ok ? ProviderState.done.color : Theme.inkStrong)
                    .frame(width: 40, height: 40)
                    .background(Theme.wash(tone, ok ? 18 : 30), in: Circle())
                    .overlay(alignment: .bottomTrailing) {
                        if ok {
                            Glyph("check", size: 10)
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(ProviderState.done.color, in: Circle())
                                .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                                .offset(x: 2, y: 2)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    Text(line).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
            }
            actions()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(tone, ok ? 45 : 60, with: Theme.borderSoft), lineWidth: 1.5))
    }

    private func ask(notify: Bool) async {
        asking = true
        defer { asking = false }
        do {
            let answer = try await HospAPI.askConsent(detail.id, kind: "estimate", notify: notify)
            await model.load()
            if notify {
                Toast.show(answer.notified == true ? L("Sent to the family to sign.") : L("Asked. The family isn’t on the app: sign it here with them."))
            } else if let id = answer.consentId {
                open(.sign(id, admitAfter: false))
            }
        } catch {
            Toast.error(hospError(error, fallback: "Could not ask for the signature."))
        }
    }

    private func admit(_ extra: [String: Any?]) async {
        do { try await admitOrThrow(extra) } catch {
            if (error as? APIError)?.code == "room_full" { roomFull = hospError(error) } else { Toast.error(hospError(error, fallback: "Could not admit the patient.")) }
        }
    }

    private func admitOrThrow(_ extra: [String: Any?]) async throws {
        admitting = true
        defer { admitting = false }
        do {
            let answer = try await model.write("/admit", body: extra)
            Toast.show(answer.client?.onPawMiaw == true ? LF("%@ is in the hospital. The family has been told.", detail.petName) : LF("%@ is in the hospital.", detail.petName))
            overriding = false
            roomFull = nil
        } catch {
            if (error as? APIError)?.code == "room_full", roomFull == nil, !overriding { throw error }
            throw hospRefusal(error, fallback: "Could not admit the patient.")
        }
    }
}

// MARK: - The estimate still to sign (patient in)

private struct HospEstimateToSign: View {
    let detail: HospDetail
    let canManage: Bool
    let open: (HospDetailSheet) -> Void
    @State private var asking = false

    var body: some View {
        if let consent = detail.gate?.consent, consent.required == true, consent.satisfied != true {
            let pending = consent.status == "pending" && consent.consentId != nil
            let amount = Money.format(detail.estimateAmount ?? 0, currency: detail.money)
            let title = consent.reason == "amount_changed"
                ? (consent.amountCents.map { LF("The estimate went up to %@; the family signed %@.", amount, Money.format($0, currency: detail.money)) }
                    ?? LF("The estimate went up to %@ since it was signed.", amount))
                : consent.status == "declined" ? LF("The family declined the estimate of %@.", amount) : LF("The estimate of %@ isn’t signed yet.", amount)
            NoticeCard(tone: .custom(Theme.mango), title: title, icon: "shield-alert", look: .page) {
                Text(pending ? L("Waiting for the family’s signature.") : L("Ask the family to sign it.")).foregroundStyle(Theme.inkSoft)
                if canManage {
                    FlowLayout(spacing: 8) {
                        PMButton(L("Sign here"), systemImage: "pen-line", size: .compact, isWorking: asking) {
                            if pending, let id = consent.consentId { open(.sign(id, admitAfter: false)) } else { Task { await ask(false) } }
                        }
                        if detail.client?.onPawMiaw == true {
                            PMButton(pending ? L("Send again") : L("Send to the family"), systemImage: "send", variant: .outline, size: .compact, isWorking: asking) {
                                Task { await ask(true) }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func ask(_ notify: Bool) async {
        asking = true
        defer { asking = false }
        do {
            let answer = try await HospAPI.askConsent(detail.id, kind: "estimate", notify: notify)
            if notify { Toast.show(answer.notified == true ? L("Sent to the family to sign.") : L("Asked. The family isn’t on the app: sign it here with them.")) }
            else if let id = answer.consentId { open(.sign(id, admitAfter: false)) }
        } catch {
            Toast.error(hospError(error, fallback: "Could not ask for the signature."))
        }
    }
}

// MARK: - How it ended

private struct HospEndBanner: View {
    let detail: HospDetail

    var body: some View {
        let zone = detail.zone
        let override = (detail.consentOverrideReason ?? detail.depositOverrideReason).map {
            LF("Admitted without the gate by %@: %@", detail.gateOverriddenByName ?? "", $0)
        }
        if detail.status == "cancelled" {
            NoticeCard(tone: .custom(Theme.inkSoft), title: L("Cancelled before admission."), icon: "circle-x", look: .page) {
                if let reason = detail.cancelReason?.nonEmpty { Text(reason).foregroundStyle(Theme.inkSoft) }
            }
        } else if let end = detail.end {
            let at = end.at.map { HospFmt.dateTime($0, zone) } ?? ""
            let title: String = {
                switch end.kind {
                case "discharged": return LF("Discharged %@", at)
                case "transferred": return LF("Transferred to %@ %@", end.transferDestination ?? "", at)
                default: return LF("Passed away %@", at)
                }
            }()
            let icon = end.kind == "discharged" ? "heart-handshake" : end.kind == "transferred" ? "arrow-right-left" : "feather"
            NoticeCard(tone: .custom(HospTone.status(end.kind)), title: title, icon: icon, look: .page, byline: end.byName?.nonEmpty) {
                if end.kind == "discharged" {
                    if let diagnosis = end.diagnosis?.nonEmpty { Text("\(L("Diagnosis")): \(diagnosis)").foregroundStyle(Theme.inkStrong) }
                    if let summary = end.summary?.nonEmpty { Text(summary).foregroundStyle(Theme.inkSoft) }
                    if let care = end.instructions?.nonEmpty {
                        (Text("\(L("Care at home")): ").bold().foregroundStyle(Theme.inkStrong) + Text(care).foregroundStyle(Theme.inkSoft))
                    }
                    if let followUp = end.followUpAt {
                        HStack(spacing: 6) {
                            Glyph("calendar-check", size: 16).foregroundStyle(Theme.inkSoft)
                            Text(LF("Recheck on %@", HospFmt.day(String(followUp.prefix(10)), style: .long, zone: zone))).foregroundStyle(Theme.inkStrong)
                        }
                    }
                    // What went home with the family: the medicines.
                    if let items = detail.takeHome, !items.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(items) { item in
                                HStack(alignment: .top, spacing: 6) {
                                    Glyph("pill", size: 16).foregroundStyle(Theme.inkSoft).padding(.top, 2)
                                    (Text(item.name ?? "").bold().foregroundStyle(Theme.inkStrong)
                                        + Text(takeHomeLine(item).map { " · \($0)" } ?? "").foregroundStyle(Theme.inkSoft))
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                } else if end.kind == "transferred" {
                    if let reason = end.transferReason?.nonEmpty { Text(reason).foregroundStyle(Theme.inkSoft) }
                } else {
                    let parts = deathLine(end)
                    if !parts.isEmpty { Text(parts).foregroundStyle(Theme.inkSoft) }
                }
                if let override { Text(override).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
            }
        } else {
            // Both can be true of one stay (admitted without the gate, then a death recorded by mistake): say both.
            let undone = detail.deathUndone.map { LF("A recorded death was undone %@: %@", HospFmt.dateTime($0.at, zone), $0.reason ?? "") }
            if let override { NoticeCard(tone: .custom(Theme.mango), title: override, icon: "triangle-alert", look: .page) }
            if let undone { NoticeCard(tone: .custom(Theme.mango), title: undone, icon: "rotate-ccw", look: .page) }
        }
    }

    private func deathLine(_ end: HospEnd) -> String {
        var parts = [end.deathCause.map { HospWords.deathCause($0) }, end.aftercare.map { HospWords.aftercare($0) }, end.aftercareNote].compactMap { $0?.nonEmpty }.joined(separator: " · ")
        if let reason = end.deathOverrideReason?.nonEmpty { parts += (parts.isEmpty ? "" : " · ") + LF("Recorded without the signed consent: %@", reason) }
        return parts
    }

    /// "1 tab · Oral · every 12 h · 7 days. With food".
    private func takeHomeLine(_ item: HospTakeHome) -> String? {
        let parts = [
            HospFmt.dose(item.doseAmount, item.doseUnit).nonEmpty,
            item.route.map { HospWords.route($0) },
            item.everyHours.map { LF("every %@ h", String($0)) },
            item.durationDays.map { $0 == 1 ? L("1 day") : LF("%d days", $0) },
        ].compactMap { $0 }.joined(separator: " · ")
        return [parts.nonEmpty, item.instructions?.nonEmpty].compactMap { $0 }.joined(separator: ". ").nonEmpty
    }
}
