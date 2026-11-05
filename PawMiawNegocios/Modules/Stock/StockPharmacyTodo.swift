//
//  StockPharmacyTodo.swift
//  PawMiawNegocios
//
//  The Pharmacy's "Por hacer" (web pharmacy/todo-tab.tsx, pharmacy-sheets.tsx):
//  what is ready to hand over, the refill requests waiting on the clinic and
//  the drafts nobody signed yet, oldest first; every refill request ever made
//  one tap away ("All requests"); and the sheets a refill needs — decline with
//  the reason the family reads, picked up outside a sale, logged for a client
//  who phoned.
//
//  Handing over is a sale at the Store (what moves stock, money and the log):
//  "Hand over" opens the Store's counter with the client, the pet and each
//  medicine against its prescription line already in the cart (web
//  lib/pharmacy.ts handOverSearch).
//

import SwiftUI

enum StockTodoFocus: Hashable { case all, handover, refills, drafts }

/// Handing over through the Store (web lib/pharmacy.ts `handOverSearch`).
enum StockHandOver {
    /// The Store's counter for a hand-over: the client, the pet and each medicine with the
    /// prescription line it is dispensed against. Nil when nothing on it can be sold (free
    /// text, nothing left).
    static func prefill(clientId: String?, petId: String?, prescriptionId: String?, lines: [StockHandOverLine]) -> StorePrefill? {
        let sellable = lines.filter { $0.block == nil && $0.catalogItemId?.isEmpty == false && ($0.quantity ?? 0) > 0 }
        guard !sellable.isEmpty, let clientId = clientId?.nonEmpty, let petId = petId?.nonEmpty else { return nil }
        return StorePrefill(
            clientId: clientId,
            petId: petId,
            lines: sellable.map { StorePrefill.Line(catalogItemId: $0.catalogItemId ?? "", quantity: Double($0.quantity ?? 0), prescriptionItemId: $0.prescriptionItemId) },
            prescriptionId: prescriptionId
        )
    }

    /// What can be handed over from a prescription now, as the Store's counter.
    static func prefill(_ p: StockPrescription) -> StorePrefill? {
        guard p.isSigned else { return nil }
        let lines = p.items.map { item in
            StockHandOverLine(
                prescriptionItemId: item.id,
                medicineName: item.medicineName,
                strength: item.strength,
                quantityUnit: item.quantityUnit,
                controlSchedule: item.controlSchedule,
                catalogItemId: item.product?.active == true ? item.catalogItemId : nil,
                productName: item.product?.name,
                remaining: item.fill?.remaining ?? 0,
                quantity: item.nextFill ?? 0,
                // An older server doesn't say: a line with a Catalog product and something left can be sold.
                block: item.handOverBlock ?? ((item.catalogItemId != nil && (item.fill?.remaining ?? 0) > 0) ? nil : "not_in_catalog")
            )
        }
        return prefill(clientId: p.providerClientId, petId: p.providerClientPetId, prescriptionId: p.id, lines: lines)
    }

    static func route(_ prefill: StorePrefill?) -> ProviderRoute {
        prefill.map { ProviderRoute.storeCheckout($0) } ?? .section(.store)
    }
}

/// The lists load 20 at a time and add 20 as they are scrolled (the owner's rule; the web shows 25 and "Show more").
private let pharmacyPage = stockPageSize

struct StockTodoTab: View {
    @Binding var focus: StockTodoFocus
    let counts: StockPharmacyCounts?
    let rights: StockRxRights
    let onOpen: (String) -> Void
    let onNew: (() -> Void)?
    let onLogRefill: (() -> Void)?

    @State private var handOverLimit = pharmacyPage
    @State private var refillLimit = pharmacyPage
    @State private var draftLimit = pharmacyPage
    @State private var handOver: StockHandOverPage?
    @State private var refills: StockRefillPage?
    @State private var drafts: StockPrescriptionPage?
    @State private var loadError: String?
    @State private var history = false
    @State private var busy = false
    @State private var loadingMore = false
    @State private var declining: StockRefillRequest?
    @State private var pickingUp: (id: String, label: String)?
    @State private var finishing: StockPrescription?
    @State private var credential: (request: StockRefillRequest, ready: Bool, type: String?)?

    private var canApprove: Bool { refills?.canApprove ?? rights.canSign }
    private var canMarkReady: Bool { refills?.canMarkReady ?? (rights.canSign || rights.canSell) }

    var body: some View {
        Group {
            if history {
                StockRequestHistory(rights: rights, onBack: { history = false }, onOpen: onOpen)
            } else {
                content
            }
        }
        .reloadsOnScope { await load() }
        .sheet(item: Binding(get: { declining }, set: { declining = $0 })) { request in
            ConfirmSheet(title: L("Decline this refill?"),
                         message: [request.medicineName, request.petName].compactMap { $0?.nonEmpty }.joined(separator: " · "),
                         confirmTitle: request.familyLinked != false ? L("Decline and tell the family") : L("Decline"),
                         destructive: true, askReason: true, reasonRequired: true, reasonLabel: L("Why@refill"), cancelTitle: L("Back@rx")) { reason in
                try await answer(request.id, decision: "decline", reason: reason)
                Toast.show(request.familyLinked != false ? L("Declined. The family was told why.") : L("Declined."))
                await load()
                announceDataChanged()
            }
        }
        .sheet(isPresented: Binding(get: { pickingUp != nil }, set: { if !$0 { pickingUp = nil } })) {
            if let target = pickingUp {
                ConfirmSheet(title: L("Mark as picked up?"),
                             message: L("For a medicine handed over outside a PawMiaw sale. Nothing is sold here: stock, money and the dispensing log stay as they are.") + "\n" + target.label,
                             confirmTitle: L("Mark as picked up"), destructive: true, askReason: true, reasonRequired: false, reasonLabel: L("Note"), cancelTitle: L("Back@rx")) { note in
                    try await answer(target.id, decision: "picked_up", note: note)
                    Toast.show(L("Marked as picked up."))
                    await load()
                    announceDataChanged()
                }
            }
        }
        .sheet(item: Binding(get: { finishing }, set: { finishing = $0 })) { draft in
            StockPrescriptionSheet(pet: StockRxPet(clientId: draft.providerClientId, petId: draft.providerClientPetId, petName: draft.petName ?? "", species: draft.petSpecies, photoUrl: draft.petPhotoUrl, clientName: draft.clientName),
                                   draft: draft) { saved in onOpen(saved.id) }
        }
        .sheet(isPresented: Binding(get: { credential != nil }, set: { if !$0 { credential = nil } })) {
            if let pending = credential {
                TeamCredentialSheet(memberId: "me", isSelf: true, country: Workspace.shared.current?.country, businessAddress: Workspace.shared.current?.address, types: (pending.type).map { [$0] }, reason: pending.type == "cedula_profesional" ? L("To renew it, add your cédula profesional: renewing signs a new prescription.")
                                        : pending.type == "state_license" ? L("To renew it, add your state license: renewing signs a new prescription.")
                                        : L("Renewing it signs a new prescription: add your professional credential first.")) {
                    let request = pending.request
                    let ready = pending.ready
                    credential = nil
                    Task { await approve(request, ready: ready) }
                }
            }
        }
    }

    private func load() async {
        do {
            async let a: StockHandOverPage = API.get("/provider-pharmacy/hand-over", query: ["limit": "\(handOverLimit)"])
            async let b: StockRefillPage = API.get("/provider-prescriptions/refill-requests", query: ["status": "waiting", "limit": "\(refillLimit)"])
            async let c: StockPrescriptionPage = API.get("/provider-prescriptions", query: ["state": "draft", "limit": "\(draftLimit)"])
            let (x, y, z) = try await (a, b, c)
            handOver = x; refills = y; drafts = z
            loadError = nil
        } catch is CancellationError {
        } catch {
            loadError = errorText(error)
        }
    }

    private func answer(_ requestId: String, decision: String, reason: String? = nil, ready: Bool? = nil, note: String? = nil) async throws {
        var body: [String: Any?] = ["decision": decision, "reason": reason]
        if let ready { body["ready"] = ready }
        if decision == "picked_up" { body["note"] = note }
        do {
            let _: EmptyResponse = try await StockAPI.send("POST", "/provider-prescriptions/refill-requests/\(requestId)", body: body)
        } catch let refusal as StockRefusal {
            throw APIError(status: refusal.status, message: StockRxWords.error(refusal), code: refusal.code, fields: refusal.api.fields)
        }
    }

    private func approve(_ request: StockRefillRequest, ready: Bool) async {
        busy = true
        defer { busy = false }
        do {
            let result: [String: JSONValue] = try await StockAPI.send("POST", "/provider-prescriptions/refill-requests/\(request.id)", body: ["decision": "approve", "reason": nil, "ready": ready])
            let told = request.familyLinked != false
            Toast.show(result["status"]?.string == "ready"
                       ? (told ? L("The family was told it’s ready for pickup.") : L("Ready for pickup."))
                       : (told ? L("Approved. The family was told.") : L("Approved.")))
            await load()
            announceDataChanged()
        } catch let refusal as StockRefusal where refusal.code == "credential_required" || refusal.code == "dea_required" {
            credential = (request, ready, refusal.code == "dea_required" ? "dea" : refusal.body["requiredType"]?.string)
        } catch {
            Toast.error(StockRxWords.error(error))
        }
    }

    private func markReady(_ request: StockRefillRequest) async {
        busy = true
        defer { busy = false }
        do {
            try await answer(request.id, decision: "ready")
            Toast.show(request.familyLinked != false ? L("The family was told it’s ready for pickup.") : L("Ready for pickup."))
            await load()
            announceDataChanged()
        } catch {
            Toast.error(error)
        }
    }

    private func more(_ grow: () -> Void) {
        guard !loadingMore else { return }
        grow()
        loadingMore = true
        Task {
            await load()
            loadingMore = false
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        let tally = (handover: counts?.toHandOver ?? handOver?.total ?? 0, refills: counts?.refillsWaiting ?? refills?.total ?? 0, drafts: counts?.draftsToSign ?? drafts?.total ?? 0)
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ToneChip(L("All@rx"), icon: "layout-grid", tone: .page, isOn: focus == .all) { focus = .all }
                    ToneChip(L("To hand over"), icon: "package-check", tone: .waiting, count: tally.handover, isOn: focus == .handover) { focus = focus == .handover ? .all : .handover }
                    ToneChip(L("Refills waiting"), icon: "bell-ring", tone: .waiting, count: tally.refills, isOn: focus == .refills) { focus = focus == .refills ? .all : .refills }
                    ToneChip(L("Drafts to sign"), icon: "pen-line", tone: .upcoming, count: tally.drafts, isOn: focus == .drafts) { focus = focus == .drafts ? .all : .drafts }
                }
                .padding(.vertical, 2)
            }
            FlowLayout(spacing: 8) {
                if let onLogRefill { PMButton(L("Log a refill request"), systemImage: "bell-plus", variant: .outline, size: .compact, action: onLogRefill) }
                PMButton(L("All requests"), systemImage: "history", variant: .ghost, size: .modal) { history = true }
            }
        }
        if handOver == nil && refills == nil && drafts == nil {
            if let loadError { ErrorState(message: loadError) { await load() } } else { LoadingState() }
        } else if (handOver?.total ?? 0) == 0 && (refills?.total ?? 0) == 0 && (drafts?.total ?? drafts?.items.count ?? 0) == 0 {
            EmptyState(systemImage: "clipboard-check", title: L("Nothing waiting."), message: L("Refill requests, drafts to sign and medicines ready to hand over show here."),
                       actionTitle: onNew != nil ? L("New prescription") : (onLogRefill != nil ? L("Log a refill request") : nil), action: onNew ?? onLogRefill, accent: Theme.mango, panel: true)
        } else {
            if focus == .all || focus == .handover { handOverSection }
            if focus == .all || focus == .refills { refillSection }
            if focus == .all || focus == .drafts { draftSection }
        }
    }

    private var handOverSection: some View {
        let rows = handOver?.items ?? []
        let total = handOver?.total ?? rows.count
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: L("Ready to hand over"), count: total, hint: L("Refills marked ready, and prescriptions signed to be handed out at the visit. The sale at the Store is what moves stock, money and the log."))
            ListCard(style: .panel) {
                if rows.isEmpty {
                    EmptyState(systemImage: "package-check", title: L("Nothing ready to hand over."), accent: Theme.mango)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { RowDivider() }
                        handOverRow(row)
                    }
                }
                LoadMoreRow(hasMore: total > rows.count, busy: loadingMore) { more { handOverLimit += pharmacyPage } }
            }
            ListCount(shown: rows.count, total: total, one: L("1 to hand over"), many: L("%d to hand over")).padding(.top, 4)
        }
    }

    private enum Gate { case ok, noProduct, controlled, cannotSell }

    private func gate(controlled: Bool, lines: [StockHandOverLine]) -> Gate {
        if !lines.contains(where: { $0.block == nil && $0.catalogItemId != nil }) { return .noProduct }
        if !rights.canSell { return .cannotSell }
        if controlled && !rights.canHandOverControlled { return .controlled }
        return .ok
    }

    private func gateNote(_ gate: Gate) -> String? {
        switch gate {
        case .noProduct: StockRxWords.block("not_in_catalog")
        case .controlled: L("A controlled medicine is handed over by a vet. Ask one to do it.")
        case .cannotSell: L("Someone who sells hands it over at the Store.")
        case .ok: nil
        }
    }

    /// "Medicine · strength" in bold, then what it is in the quiet ink (web: the row's medicine line).
    private func medicineLine(_ name: String?, _ strength: String?, _ rest: String) -> some View {
        (Text([name, strength].compactMap { $0?.nonEmpty }.joined(separator: " · ")).bold().foregroundColor(Theme.inkStrong)
         + Text(" · " + rest).foregroundColor(Theme.inkSoft))
            .font(Theme.text(14))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The small facts under it: its pills, then "folio · refill · waiting 2 days".
    private func factsLine<Pills: View>(_ words: [String?], @ViewBuilder pills: () -> Pills) -> some View {
        FlowLayout(spacing: 8) {
            pills()
            let text = words.compactMap { $0?.nonEmpty }.joined(separator: " · ")
            if !text.isEmpty { Text(text).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
        }
    }

    private func reason(_ text: String) -> some View {
        Text(text).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
    }

    /// A row's button as a link to another page (the visit, the Store), at the row's 44.
    private func linkLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Glyph(icon, size: 16)
            Text(title)
        }
    }

    private func handOverRow(_ row: StockHandOverRow) -> some View {
        let lines = row.lines ?? []
        let gate = gate(controlled: row.controlled == true, lines: lines)
        return VStack(alignment: .leading, spacing: 12) {
            StockPetLine(petName: row.petName, species: row.petSpecies, photoUrl: row.petPhotoUrl, clientName: row.clientName)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.prescriptionItemId) { line in
                    medicineLine(line.medicineName, line.strength, StockRxWords.block(line.block) ?? LF("%d to hand over, %d left", line.quantity ?? 0, line.remaining ?? 0))
                }
                factsLine([row.folio, row.kind == "refill" ? L("refill") : L("signed to hand out"), StockRxWords.waiting(row.since),
                           row.origin == "staff" ? (row.requestedByName.map { LF("asked by %@", $0) } ?? L("logged by the clinic")) : nil]) {
                    if row.kind == "refill" { StockRefillPill(status: "ready") } else { StockRxStatePill(state: "active") }
                    if row.controlled == true { StockControlledChip() }
                }
                if let note = gateNote(gate) { reason(note) }
            }
            FlowLayout(spacing: 8) {
                if row.bill != nil, let appointmentId = row.appointmentId {
                    NavigationLink(value: ProviderRoute.appointment(appointmentId)) { linkLabel(L("Charge the visit’s bill"), icon: "receipt-text") }
                        .buttonStyle(.pm(.primary, size: .modal))
                } else if gate != .noProduct {
                    let prefill = StockHandOver.prefill(clientId: row.providerClientId, petId: row.providerClientPetId, prescriptionId: row.prescriptionId, lines: lines)
                    NavigationLink(value: StockHandOver.route(prefill)) { linkLabel(L("Hand over"), icon: "shopping-cart") }
                        .buttonStyle(.pm(.primary, size: .modal))
                        .disabled(gate != .ok || prefill == nil)
                }
                if let requestId = row.requestId, canMarkReady {
                    PMButton(L("Mark as picked up"), systemImage: "check", variant: .outline, size: .modal) {
                        pickingUp = (requestId, [lines.first?.medicineName, row.petName].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                    }
                }
                PMButton(L("Open prescription"), systemImage: "file-text", variant: .ghost, size: .modal) { onOpen(row.prescriptionId) }
                StockChartLink(clientId: row.providerClientId, petId: row.providerClientPetId, canViewClients: rights.canViewClients)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var refillSection: some View {
        let rows = refills?.items ?? []
        let total = refills?.total ?? rows.count
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: L("Refills waiting"), count: total, hint: L("Asked for by families in their app, or logged here for a client who phoned."))
            ListCard(style: .panel) {
                if rows.isEmpty {
                    EmptyState(systemImage: "bell-ring", title: L("No refill requests waiting."), accent: Theme.mango)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, request in
                        if index > 0 { RowDivider() }
                        refillRow(request)
                    }
                }
                LoadMoreRow(hasMore: total > rows.count, busy: loadingMore) { more { refillLimit += pharmacyPage } }
            }
            ListCount(shown: rows.count, total: total, one: L("1 request"), many: L("%d requests")).padding(.top, 4)
        }
    }

    private func refillRow(_ request: StockRefillRequest) -> some View {
        let target = request.handOver
        let line = target.map { StockHandOverLine(prescriptionItemId: $0.prescriptionItemId ?? "", medicineName: request.medicineName, strength: request.strength, quantityUnit: nil, controlSchedule: request.controlSchedule, catalogItemId: $0.catalogItemId, productName: $0.productName, remaining: $0.remaining, quantity: $0.quantity, block: $0.block) }
        let gate = line.map { gate(controlled: request.controlSchedule?.nonEmpty != nil, lines: [$0]) } ?? .noProduct
        return VStack(alignment: .leading, spacing: 12) {
            StockPetLine(petName: request.petName, species: request.petSpecies, photoUrl: request.petPhotoUrl, clientName: request.clientName)
            VStack(alignment: .leading, spacing: 4) {
                medicineLine(request.medicineName, request.strength, request.needsRenewal == true
                    ? LF("nothing left on %@: approving renews it", request.folio ?? "")
                    : LF("%d left on %@, valid until %@", request.remaining ?? 0, request.folio ?? "", StockText.day(request.validUntil)))
                factsLine([
                    request.requestedByName.map { LF("asked by %@", $0) },
                    request.origin == "staff" ? (request.loggedByName.map { LF("logged by %@", $0) } ?? L("logged by the clinic")) : nil,
                    StockRxWords.waiting(request.createdAt),
                ]) {
                    StockRefillPill(status: request.status)
                    if let schedule = StockRxWords.schedule(request.controlSchedule) { StockControlledChip(label: schedule) }
                }
                if let note = request.note?.nonEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Glyph("message-square-text", size: 16).foregroundStyle(Theme.inkSoft).padding(.top, 2)
                        Text("“\(note)”").font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    }
                }
                if request.status == "approved", gate == .noProduct || gate == .controlled, let text = gateNote(gate) { reason(text) }
            }
            FlowLayout(spacing: 8) {
                if request.status == "pending" && canApprove {
                    PMButton(request.needsRenewal == true ? L("Renew and approve") : L("Approve"), systemImage: "check", size: .modal, isWorking: busy) {
                        Task { await approve(request, ready: false) }
                    }
                    PMButton(L("Approve — ready"), systemImage: "package-check", variant: .outline, size: .modal) {
                        Task { await approve(request, ready: true) }
                    }
                    .disabled(busy)
                    PMButton(L("Decline"), systemImage: "x", variant: .ghost, size: .modal, tint: Theme.destructive) { declining = request }
                        .disabled(busy)
                }
                if request.status == "approved" {
                    if canMarkReady {
                        PMButton(L("Ready for pickup"), systemImage: "package-check", size: .modal, isWorking: busy) { Task { await markReady(request) } }
                    }
                    if target != nil && gate != .noProduct {
                        let prefill = StockHandOver.prefill(clientId: request.providerClientId, petId: request.providerClientPetId, prescriptionId: request.prescriptionId, lines: line.map { [$0] } ?? [])
                        NavigationLink(value: StockHandOver.route(prefill)) { linkLabel(L("Hand over"), icon: "shopping-cart") }
                            .buttonStyle(.pm(.outline, size: .modal))
                            .disabled(gate != .ok || prefill == nil)
                    }
                    if canMarkReady {
                        PMButton(L("Mark as picked up"), systemImage: "check", variant: .outline, size: .modal) {
                            pickingUp = (request.id, [request.medicineName, request.petName].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                        }
                        .disabled(busy)
                    }
                }
                PMButton(L("Open prescription"), systemImage: "file-text", variant: .ghost, size: .modal) { onOpen(request.renewalPrescriptionId ?? request.prescriptionId) }
                StockChartLink(clientId: request.providerClientId, petId: request.providerClientPetId, canViewClients: rights.canViewClients)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var draftSection: some View {
        let rows = drafts?.items ?? []
        let total = drafts?.total ?? rows.count
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: L("Drafts to sign"), count: total, hint: L("Written and not signed yet — from a visit, a chart or a hospital discharge. Nothing is printed or shared until a vet signs."))
            ListCard(style: .panel) {
                if rows.isEmpty {
                    EmptyState(systemImage: "pen-line", title: L("No drafts waiting for a signature."), accent: Theme.mango)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, draft in
                        if index > 0 { RowDivider() }
                        VStack(alignment: .leading, spacing: 12) {
                            StockPetLine(petName: draft.petName, species: draft.petSpecies, photoUrl: draft.petPhotoUrl, clientName: draft.clientName, breed: draft.petBreed)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.medicines).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                                factsLine([draft.origin == "visit" ? L("from a visit") : nil, StockRxWords.waiting(draft.createdAt)]) {
                                    StockRxStatePill(state: "draft")
                                    if draft.controlled == true { StockControlledChip() }
                                    if draft.origin == "discharge" { StockRxChip(text: L("Hospital discharge"), tone: Hue.sky.color) }
                                    if draft.origin == "renewal" { StockRxChip(text: L("Renewal"), tone: Hue.sky.color) }
                                }
                            }
                            FlowLayout(spacing: 8) {
                                if rights.canSign || rights.canWrite {
                                    PMButton(rights.canSign ? L("Finish and sign") : L("Finish the draft"), systemImage: "pen-line", size: .modal) { finishing = draft }
                                }
                                PMButton(L("Open prescription"), systemImage: "file-text", variant: .ghost, size: .modal) { onOpen(draft.id) }
                                StockChartLink(clientId: draft.providerClientId, petId: draft.providerClientPetId, canViewClients: rights.canViewClients)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
                LoadMoreRow(hasMore: total > rows.count, busy: loadingMore) { more { draftLimit += pharmacyPage } }
            }
            ListCount(shown: rows.count, total: total, one: L("1 draft"), many: L("%d drafts")).padding(.top, 4)
        }
    }
}

// MARK: - Every refill request

private struct StockRequestHistory: View {
    let rights: StockRxRights
    let onBack: () -> Void
    let onOpen: (String) -> Void

    @State private var query = ""
    @State private var searched = ""
    @State private var limit = pharmacyPage
    @State private var page: StockRefillPage?
    @State private var loadError: String?
    @State private var loadingMore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                PMButton(L("Back to To do"), systemImage: "arrow-left", variant: .outline, size: .compact, action: onBack)
                SearchField(prompt: L("Folio, medicine, pet or client"), text: $query)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionHeading(title: L("All refill requests"), count: page?.total ?? page?.items.count, hint: L("Answered ones too: approved, picked up, declined and withdrawn."))
                ListCard(style: .panel) {
                    if page == nil {
                        if let loadError { ErrorState(message: loadError) { await load() } } else { LoadingState() }
                    } else if let page, page.items.isEmpty {
                        EmptyState(systemImage: "bell-ring", title: searched.isEmpty ? L("No refill requests yet.") : L("No request matches that."),
                                   message: searched.isEmpty ? L("A family asks for one from a prescription in their app; the clinic can log one for a client who phoned.") : nil, accent: Theme.mango)
                    } else if let page {
                        ForEach(Self.groups(page.items), id: \.key) { group in
                            DayBand(title: StockText.day(group.day), style: .caps)
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, request in
                                if index > 0 { RowDivider() }
                                row(request)
                            }
                            RowDivider()
                        }
                        let total = page.total ?? page.items.count
                        LoadMoreRow(hasMore: total > page.items.count, busy: loadingMore) {
                            guard !loadingMore else { return }
                            limit += pharmacyPage
                            loadingMore = true
                            Task { await load(); loadingMore = false }
                        }
                    }
                }
                if let page { ListCount(shown: page.items.count, total: page.total ?? page.items.count, one: L("1 request"), many: L("%d requests")).padding(.top, 4) }
            }
        }
        .task { await load() }
        .debounced(query) { text in
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard trimmed != searched else { return }
            searched = trimmed
            limit = pharmacyPage
            await load()
        }
    }

    /// Rows under the day they were asked for, in the order they came (web `groupByDay`).
    static func groups(_ items: [StockRefillRequest]) -> [(key: String, day: String, items: [StockRefillRequest])] {
        var groups: [(key: String, day: String, items: [StockRefillRequest])] = []
        for item in items {
            let day = DateText.parse(item.createdAt).map { DateText.dayFormatter(Workspace.shared.timeZone).string(from: $0) } ?? ""
            if let last = groups.last, last.day == day {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append(("\(day)-\(groups.count)", day, [item]))
            }
        }
        return groups
    }

    private func load() async {
        do {
            page = try await API.get("/provider-prescriptions/refill-requests", query: ["status": "all", "limit": "\(limit)", "q": searched.nonEmpty])
            loadError = nil
        } catch is CancellationError {
        } catch {
            loadError = errorText(error)
        }
    }

    private func row(_ request: StockRefillRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StockPetLine(petName: request.petName, species: request.petSpecies, photoUrl: request.petPhotoUrl, clientName: request.clientName)
            VStack(alignment: .leading, spacing: 4) {
                Text([request.medicineName, request.strength].compactMap { $0?.nonEmpty }.joined(separator: " · ")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                FlowLayout(spacing: 8) {
                    StockRefillPill(status: request.status)
                    Text([
                        request.folio,
                        request.requestedByName.map { LF("asked by %@", $0) },
                        request.origin == "staff" ? L("logged by the clinic") : nil,
                        StockText.dateTime(request.createdAt),
                        request.pickupSource == "manual" ? L("handed over outside a sale") : nil,
                    ].compactMap { $0?.nonEmpty }.joined(separator: " · ")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
                if let reason = request.declineReason?.nonEmpty { Text(LF("Reason: %@", reason)).font(Theme.text(14)).foregroundStyle(Theme.inkStrong) }
            }
            FlowLayout(spacing: 8) {
                PMButton(L("Open prescription"), systemImage: "file-text", variant: .ghost, size: .modal) { onOpen(request.renewalPrescriptionId ?? request.prescriptionId) }
                StockChartLink(clientId: request.providerClientId, petId: request.providerClientPetId, canViewClients: rights.canViewClients)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Log a refill request

/// For a client who phoned or came by, or a family that isn't on PawMiaw: which prescription, which medicine, who asked.
struct StockLogRefillSheet: View {
    /// Opened from a prescription: it is already chosen.
    let prescription: StockPrescription?
    var onSaved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var chosen: StockPrescription?
    @State private var itemId: String?
    @State private var who = ""
    @State private var note = ""
    @State private var query = ""
    @State private var found: [StockPrescription]?
    /// What the server holds beyond the rows loaded (20 at a time, more as the list scrolls).
    @State private var hasMore = false
    @State private var loadingMore = false
    @State private var saving = false
    @State private var started = false

    var body: some View {
        ProviderModal(title: L("Log a refill request"), subtitle: L("For a client who phoned or came by, or a family that isn’t on PawMiaw."), systemImage: "bell-plus", accent: .butter,
                      isDirty: (chosen != nil && prescription == nil) || !who.isEmpty || !note.isEmpty, form: form,
                      primaryTitle: chosen != nil ? L("Log request") : nil, isWorking: saving,
                      onBack: chosen != nil && prescription == nil ? { self.chosen = nil; itemId = nil } : nil,
                      primaryIcon: "bell-plus",
                      onPrimary: chosen != nil ? { Task { await save() } } : nil) {
            if let chosen {
                ContextPills(client: chosen.clientName?.nonEmpty, pets: [chosen.petName?.nonEmpty].compactMap { $0 })
                FormField(label: L("Which medicine?"), key: "item", form: form) {
                    VStack(spacing: 8) {
                        ForEach(chosen.items) { item in
                            let on = item.id == itemId
                            Button { itemId = item.id; form.clear("item") } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text([item.medicineName, item.strength].compactMap { $0?.nonEmpty }.joined(separator: " · ")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                                        Text((item.fill?.remaining ?? 0) > 0
                                             ? LF("%d left on %@", item.fill?.remaining ?? 0, chosen.folio ?? "")
                                             : LF("Nothing left on %@: approving it renews the prescription.", chosen.folio ?? ""))
                                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                                    }
                                    Spacer()
                                    if on { Glyph("package-check", size: 20).foregroundStyle(Theme.blue) }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .frame(minHeight: 48)
                                .background(on ? AnyShapeStyle(Theme.wash(Theme.aqua, 16)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(on ? Theme.blue : Theme.borderSoft, lineWidth: 2))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
                PMTextField(L("Who asked"), text: $who, prompt: L("e.g. Ana, by phone"), hint: L("When it wasn’t the client themselves, or to remember how they asked."), optional: true)
                PMTextField(L("Note for the vet"), text: $note, optional: true, multiline: true)
            } else {
                SearchField(prompt: L("Folio, medicine, pet or client"), text: $query, shape: .field)
                if let found {
                    let signed = found.filter(\.isSigned)
                    if signed.isEmpty {
                        NoticeCard(tone: .info, message: query.isEmpty ? L("No signed prescriptions yet.") : L("No signed prescription matches that."), icon: nil)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(signed) { entry in
                                Button { choose(entry) } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(entry.medicines).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                            Text([entry.folio, entry.petName, entry.clientName, entry.signedAt.map { StockText.day($0) }].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                                                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                                        }
                                        Spacer(minLength: 8)
                                        StockRxStatePill(state: entry.state)
                                        Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .frame(minHeight: 56)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 2))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            LoadMoreRow(hasMore: hasMore, busy: loadingMore) { Task { await loadMore() } }
                        }
                    }
                } else {
                    LoadingState()
                }
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            if let prescription { choose(prescription) }
        }
        // The server searches from two characters, 250 ms after typing stops; 20 at a time.
        .task(id: ClientSearch.query(query) ?? "") {
            guard chosen == nil else { return }
            if found != nil { try? await Task.sleep(for: ClientSearch.debounce) }
            guard !Task.isCancelled else { return }
            await loadPage(reset: true)
        }
    }

    private func loadPage(reset: Bool) async {
        let offset = reset ? 0 : (found?.count ?? 0)
        let page: StockPrescriptionPage? = try? await API.get("/provider-prescriptions", query: [
            "q": ClientSearch.query(query), "state": nil, "limit": "\(ClientSearch.pageSize)", "offset": offset > 0 ? "\(offset)" : nil,
        ])
        guard !Task.isCancelled else { return }
        let items = page?.items ?? []
        found = reset ? items : (found ?? []) + items
        hasMore = page?.hasMore ?? (page.map { ($0.total ?? 0) > offset + items.count } ?? false)
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        await loadPage(reset: false)
    }

    private func choose(_ entry: StockPrescription) {
        chosen = entry
        itemId = entry.items.count == 1 ? entry.items.first?.id : nil
    }

    private func save() async {
        guard let chosen, form.check([("item", itemId == nil ? L("Choose the medicine.") : nil)]), let itemId, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            let _: EmptyResponse = try await StockAPI.send("POST", "/provider-prescriptions/\(chosen.id)/refill-requests", body: [
                "prescriptionItemId": itemId,
                "note": note.nonEmpty,
                "requestedByName": who.nonEmpty,
            ])
            Toast.show(L("Refill request logged. A vet answers it in To do."))
            onSaved?()
            announceDataChanged()
            dismiss()
        } catch {
            Toast.error(StockRxWords.error(error))
        }
    }
}
