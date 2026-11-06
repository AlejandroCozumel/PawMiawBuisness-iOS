//
//  InvoicesScreen.swift
//  PawMiawNegocios
//
//  Cuentas (web: routes/provider.invoices.tsx, invoices-page/*): every bill —
//  visits, stays, hospital, counter sales, deposits and bills made by hand —
//  in one ledger, and "Por cobrar", the finished work still to charge. Every
//  filter, count and total is the server's. The page is the front desk's
//  (money level 2); "Cobrado este mes" and a list's totals are level 3.
//

import SwiftUI

// MARK: - The rules of a bill (invoices-page/invoice-model.ts)

enum CashBillRules {
    static let kinds = ["visit", "stay", "hospital", "sale", "deposit", "other"]
    static let collectible = ["ready_for_payment", "open", "partially_paid", "overdue"]

    static func kind(_ bill: CashInvoice) -> String {
        if let origin = bill.origin, kinds.contains(origin) { return origin }
        let source = bill.createdFromSourceType ?? ""
        if bill.kind == "sale" || source == "store" { return "sale" }
        if bill.kind == "deposit" || source == "deposit" || source.hasSuffix("_deposit") { return "deposit" }
        if source == "stay" { return "stay" }
        if source == "hospitalization" { return "hospital" }
        if bill.providerAppointmentId != nil || source == "provider_appointment" || source == "appointment_fee" { return "visit" }
        return "other"
    }

    static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "visit": L("Visit")
        case "stay": L("Stay")
        case "hospital": L("Hospital")
        case "sale": L("Store sale")
        case "deposit": L("Deposit")
        default: L("Manual bill")
        }
    }

    static func kindFilter(_ kind: String) -> String {
        switch kind {
        case "visit": L("Visits")
        case "stay": L("Stays")
        case "hospital": L("Hospital")
        case "sale": L("Store")
        case "deposit": L("Deposits")
        default: L("Manual")
        }
    }

    static func kindHue(_ kind: String) -> Hue {
        switch kind {
        case "visit": .sky
        case "stay": .periwinkle
        case "hospital": .teal
        case "sale": .peach
        case "deposit": .mint
        default: .grey
        }
    }

    /// The kind's Lucide icon (web invoice-bits `KIND_ICONS`).
    static func kindIcon(_ kind: String) -> String {
        switch kind {
        case "visit": "stethoscope"
        case "stay": "bed-double"
        case "hospital": "siren"
        case "sale": "shopping-bag"
        case "deposit": "piggy-bank"
        default: "file-text"
        }
    }

    /// The kind's toned-chip colour (web `KIND_META[kind].accent`).
    static func kindTone(_ kind: String) -> ChipTone { .hue(kindHue(kind)) }

    /// What made the bill, to open it.
    static func source(_ bill: CashInvoice) -> ProviderRoute? {
        let kind = kind(bill)
        let from = bill.createdFromSourceType ?? ""
        let id = bill.createdFromSourceId
        if kind == "sale" { return .sale(bill.id) }
        if kind == "stay" || from == "stay_deposit" { return id.map { .stay($0) } }
        if kind == "hospital" || from == "hospitalization_deposit" { return id.map { .hospitalization($0) } }
        if from == "appointment_deposit" { return id.map { .appointment($0) } }
        if let visit = bill.providerAppointmentId { return .appointment(visit) }
        return nil
    }

    /// Which sources this person may open (web `sourceAllowed`): a sale is the Store's
    /// (sales.sell or any money level); a visit, stay or hospitalization whoever sees visits.
    @MainActor static func sourceAllowed(_ route: ProviderRoute, _ w: Workspace) -> Bool {
        if case .sale = route { return w.can(.salesSell) || w.moneyLevel >= .charging }
        return w.can(.appointmentsView)
    }

    static func sourceLabel(_ route: ProviderRoute) -> String {
        switch route {
        case .stay: L("Open the stay")
        case .hospitalization: L("Open the hospitalization")
        case .sale: L("Open the sale in the Store")
        default: L("Open the visit")
        }
    }

    static func isWalkIn(_ bill: CashInvoice) -> Bool { kind(bill) == "sale" && bill.clientName.trimmingCharacters(in: .whitespaces) == "Público en general" }
    static func isCollectible(_ bill: CashInvoice) -> Bool { bill.balanceDueAmount > 0 && collectible.contains(bill.status) }
    static func dueDay(_ bill: CashInvoice) -> String { DateText.dayKey(DateText.parse(bill.dueAt ?? bill.issuedAt ?? bill.createdAt) ?? Date()) }
    static func billDay(_ bill: CashInvoice) -> String { DateText.dayKey(DateText.parse(bill.issuedAt ?? bill.createdAt) ?? Date()) }
    static func isOverdue(_ bill: CashInvoice, today: String) -> Bool { isCollectible(bill) && dueDay(bill) < today }

    static func daysLate(_ bill: CashInvoice, today: String) -> Int {
        guard let due = CashDay.date(dueDay(bill)), let now = CashDay.date(today) else { return 0 }
        return max(0, DateText.calendar.dateComponents([.day], from: due, to: now).day ?? 0)
    }

    /// Paid, and then all of it came back (a sale returned in full, a bill refunded in full).
    static func fullyGivenBack(_ bill: CashInvoice) -> Bool { bill.status == "paid" && bill.totalAmount > 0 && bill.refunded >= bill.totalAmount }

    /// "25 sep" — with the year when it isn't this year's (web `invoiceDay`).
    static func day(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return "" }
        let f = DateFormatter(); f.locale = .app; f.timeZone = Workspace.shared.timeZone
        let sameYear = DateText.calendar.component(.year, from: date) == DateText.calendar.component(.year, from: Date())
        f.setLocalizedDateFormatFromTemplate(sameYear ? "dMMM" : "dMMMyyyy")
        return f.string(from: date)
    }

    /// "Martes, 4 de noviembre" — the day a group of bills belongs to (web `invoiceWeekday`).
    static func weekday(_ key: String) -> String {
        guard let date = CashDay.date(key) else { return key }
        let f = DateFormatter(); f.locale = .app; f.timeZone = Workspace.shared.timeZone
        let sameYear = DateText.calendar.component(.year, from: date) == DateText.calendar.component(.year, from: Date())
        f.setLocalizedDateFormatFromTemplate(sameYear ? "EEEEdMMMM" : "EEEEdMMMMyyyy")
        let text = f.string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "25 sep 2026, 4:30 p. m." (web `invoiceDateTime`).
    static func dateTime(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return "" }
        let f = DateFormatter(); f.locale = .app; f.timeZone = Workspace.shared.timeZone
        f.setLocalizedDateFormatFromTemplate("dMMMyyyyjmm")
        return f.string(from: date)
    }

    /// The line under the status: how late, when it is due, what a draft still needs (web `statusHint`).
    static func statusHint(_ bill: CashInvoice, today: String, canFinalize: Bool) -> (text: String, late: Bool)? {
        if isOverdue(bill, today: today) {
            let late = daysLate(bill, today: today)
            return (late == 0 ? L("Marked overdue") : CashText.daysLate(late), true)
        }
        if isCollectible(bill) { return bill.dueAt.map { (LF("Due %@", day($0)), false) } }
        if bill.status == "draft" {
            if lineCount(bill) == 0 { return (L("No items yet"), false) }
            if bill.totalAmount <= 0 { return (L("No price yet"), false) }
            return (canFinalize ? L("Ready to send") : L("Waiting for review"), false)
        }
        if fullyGivenBack(bill) { return nil }
        if bill.status == "forgiven" { return bill.forgivenAt.map { (LF("Forgiven %@@date", day($0)), false) } }
        if bill.status == "paid" {
            let paid = bill.allPayments.filter { !$0.voided && !$0.isRefund }.compactMap(\.paidAt).sorted().last
            return paid.map { (LF("Paid %@@date", day($0)), false) }
        }
        return nil
    }

    static func lineCount(_ bill: CashInvoice) -> Int { bill.lines.isEmpty ? (bill.lineItemCount ?? 0) : bill.lines.count }
    static func draftNeedsPrice(_ bill: CashInvoice) -> Bool { bill.status == "draft" && (lineCount(bill) == 0 || bill.totalAmount <= 0) }
    static func netTotal(_ bill: CashInvoice) -> Int { max(0, bill.totalAmount - bill.refunded) }

    /// The chip a bill wears: late wins; a draft says when it lacks a price.
    static func chip(_ bill: CashInvoice, today: String, canFinalize: Bool) -> (String, ProviderState) {
        if isOverdue(bill, today: today) { return (L("Overdue@status"), .problem) }
        if draftNeedsPrice(bill) { return (L("Needs a price@status"), .waiting) }
        if bill.status == "draft" { return (canFinalize ? L("Draft@status") : L("In review@status"), .upcoming) }
        if fullyGivenBack(bill) {
            return (kind(bill) == "sale" ? L("Returned@status") : L("Refunded@status"), .closed)
        }
        switch bill.status {
        case "ready_for_payment", "open", "overdue": return (L("Unpaid@status"), .waiting)
        case "partially_paid": return (L("Part paid@status"), .waiting)
        case "paid": return (L("Paid@status"), .done)
        // What was left on it was forgiven: "Saldo perdonado" (the family reads the same).
        case "forgiven": return (L("Forgiven@status"), .closed)
        default: return (L("Canceled@status"), .closed)
        }
    }

    // What this person may do with a bill.
    @MainActor static func canEdit(_ bill: CashInvoice, _ w: Workspace) -> Bool {
        guard w.can(.billingEditInvoice) else { return false }
        let kind = kind(bill)
        // A forgiven bill is closed: the server refuses an edit (`bill_forgiven`).
        if kind == "sale" || kind == "deposit" || bill.status == "canceled" || bill.status == "forgiven" { return false }
        if bill.status == "paid" && !w.isOwnerOrAdmin { return false }
        if bill.status != "draft" && !w.can(.billingFinalizeInvoice) { return false }
        return true
    }

    @MainActor static func canSendToDesk(_ bill: CashInvoice, _ w: Workspace) -> Bool {
        w.can(.billingFinalizeInvoice) && bill.status == "draft" && kind(bill) != "sale" && lineCount(bill) > 0 && bill.totalAmount > 0
    }

    @MainActor static func canRecordPayment(_ bill: CashInvoice, _ w: Workspace) -> Bool {
        w.can(.billingRecordPayment) && bill.balanceDueAmount > 0 && bill.status != "canceled" && bill.status != "draft" && bill.status != "forgiven" && kind(bill) != "deposit"
    }

    /// "Perdonar saldo", as the server allows it (POST /provider-invoices/{id}/forgive): billing.waive_visit,
    /// a bill out of draft with a balance, never canceled or already forgiven, never a deposit (refunded
    /// instead). A counter sale left on account can be forgiven.
    @MainActor static func canForgive(_ bill: CashInvoice, _ w: Workspace) -> Bool {
        w.can(.billingWaiveVisit) && forgiveBlocker(bill) == nil
    }

    /// What stops a bill from being forgiven, in the server's own codes (its 409s); nil when nothing does.
    static func forgiveBlocker(_ bill: CashInvoice) -> String? {
        if bill.status == "draft" { return "bill_draft" }
        if bill.status == "canceled" { return "bill_canceled" }
        if bill.status == "forgiven" { return "bill_forgiven" }
        if kind(bill) == "deposit" { return "deposit" }
        if bill.balanceDueAmount <= 0 { return "nothing_owed" }
        return nil
    }

    /// Why "Perdonar saldo" was refused, in words that say what to do instead.
    static func forgiveRefusalText(_ code: String) -> String? {
        switch code {
        case "reason_required": L("Say why the balance is forgiven.")
        case "forgive_forbidden": L("You can’t forgive balances. Ask an owner or admin.")
        case "bill_draft": L("A draft isn’t owed yet: send it to the desk or cancel it.")
        case "bill_canceled": L("This bill was canceled: there is nothing to forgive.")
        case "bill_forgiven": L("This balance was already forgiven.")
        case "deposit": L("A deposit isn’t forgiven: give it back with a refund.")
        case "nothing_owed": L("Nothing is owed on this bill.")
        case "stale_bill": L("Someone changed this bill a moment ago — look at it again before forgiving it.")
        default: nil
        }
    }

    /// "Cobrar en la Tienda, con productos": the bill goes to the counter, to charge it with products from the shelf.
    @MainActor static func canCollectAtStore(_ bill: CashInvoice, _ w: Workspace) -> Bool {
        w.can(.salesSell) && w.can(.billingRecordPayment) && isCollectible(bill) && kind(bill) != "deposit"
    }

    static func storeCheckout(_ bill: CashInvoice) -> ProviderRoute {
        .storeCheckout(StorePrefill(clientId: bill.providerClientId, petId: bill.providerClientPetId, invoiceId: bill.id))
    }

    @MainActor static func canRefund(_ bill: CashInvoice, _ w: Workspace) -> Bool {
        w.canAny(.salesRefund, .billingManage) && kind(bill) != "sale" && bill.status != "draft" && bill.status != "canceled" && (bill.amountPaid > 0 || bill.balanceDueAmount > 0)
    }

    @MainActor static func canCancel(_ bill: CashInvoice, _ w: Workspace) -> Bool {
        guard w.can(.billingEditInvoice) else { return false }
        let kind = kind(bill)
        if kind == "sale" || kind == "deposit" || bill.status == "canceled" || bill.status == "forgiven" || bill.amountPaid > 0 { return false }
        return bill.status == "draft" || w.can(.billingFinalizeInvoice)
    }

    @MainActor static func canBillAgain(_ bill: CashInvoice, _ w: Workspace) -> Bool {
        let kind = kind(bill)
        return w.can(.billingCreateInvoice) && kind != "sale" && kind != "deposit" && lineCount(bill) > 0 && !isWalkIn(bill)
    }

    enum Next { case collect, send, edit }

    @MainActor static func next(_ bill: CashInvoice, _ w: Workspace) -> Next? {
        if isCollectible(bill) && canRecordPayment(bill, w) { return .collect }
        if canSendToDesk(bill, w) { return .send }
        if bill.status == "draft" && canEdit(bill, w) { return .edit }
        return nil
    }

    /// Draft → at the desk.
    static func sendToDesk(_ bill: CashInvoice) async throws -> CashInvoice {
        try await API.post("/provider-invoices/\(bill.id)/send-to-desk", body: bill.revision.map { ["expectedRevision": $0] } ?? [:])
    }
}

// MARK: - The page

private enum CashInvoiceFilter: String, CaseIterable {
    case due, overdue, desk, partial, draft, unpriced, paid, forgiven, canceled

    var label: String {
        switch self {
        case .due: L("With a balance")
        case .overdue: L("Overdue")
        case .desk: L("Unpaid")
        case .partial: L("Part paid")
        case .draft: L("Drafts")
        case .unpriced: L("Needs a price")
        case .paid: L("Paid@filter")
        case .forgiven: L("Forgiven@filter")
        case .canceled: L("Canceled@filter")
        }
    }

    /// The chip's colour while quiet and its fill while on (web `FILTER_META`).
    var tone: ChipTone {
        switch self {
        case .due, .desk, .partial, .unpriced: .state(.waiting)
        case .overdue: .state(.problem)
        case .draft: .state(.upcoming)
        case .paid: .state(.done)
        case .forgiven, .canceled: .state(.closed)
        }
    }

    /// Oldest debt first rather than newest bill first: the rows are not grouped by day.
    var byDebt: Bool { [.due, .overdue, .desk, .partial].contains(self) }

    var query: [String: String?] {
        switch self {
        case .due: ["withBalance": "true", "sort": "due"]
        case .overdue: ["overdue": "true", "sort": "due"]
        case .desk: ["statuses": "ready_for_payment,open", "withBalance": "true", "sort": "due"]
        case .partial: ["statuses": "partially_paid", "sort": "due"]
        case .draft: ["statuses": "draft"]
        case .unpriced: ["needsPrice": "true"]
        case .paid: ["statuses": "paid"]
        // "Saldo perdonado" (docs/family-money.md §1).
        case .forgiven: ["statuses": "forgiven"]
        case .canceled: ["statuses": "canceled"]
        }
    }

    var empty: (String, String) {
        switch self {
        case .due: (L("Nothing waiting to be paid"), L("Every bill that went to the desk has been paid."))
        case .overdue: (L("Nothing is late"), L("No bill is past its due date."))
        case .draft: (L("No drafts"), L("Bills still being built show up here until they go to the desk."))
        case .unpriced: (L("Every draft has its prices"), L("A draft with a line at $0 that isn’t a courtesy waits here for its price."))
        case .desk: (L("No unpaid bills"), L("Bills sent to be charged, with nothing paid yet, wait here."))
        case .partial: (L("No part-paid bills"), L("Bills with some of the money in show up here."))
        case .paid: (L("No paid bills here"), L("Paid bills show up here once the money is in."))
        case .forgiven: (L("No forgiven balances"), L("Bills whose balance you forgave show up here."))
        case .canceled: (L("No canceled bills"), L("Bills canceled by mistake or on purpose show up here."))
        }
    }
}

@MainActor
private final class CashInvoicesModel: ObservableObject {
    @Published var search = ""
    @Published var filter: CashInvoiceFilter?
    @Published var kind: String?
    @Published var period: String?
    @Published var charging = false
    @Published var summary: CashInvoiceSummary?
    @Published var totals: CashInvoiceTotals?
    @Published var today: String = CashDay.today
    @Published var queue: CashChargingQueue?
    @Published var outsideDays = false
    @Published var collected: Int?
    var openedOnQueue = false
    var withTotals = false

    lazy var pager = Pager<CashInvoice> { [weak self] offset, limit in
        guard let self else { return Page(items: [], total: 0) }
        return try await self.fetch(offset: offset, limit: limit)
    }

    lazy var chargingPager = Pager<CashChargingItem> { [weak self] offset, limit in
        let queue: CashChargingQueue = try await API.get("/provider-charging", query: ["limit": "\(limit)", "offset": "\(offset)", "locationId": Workspace.shared.listLocationFilter])
        self?.queue = queue
        return Page(items: queue.items, total: queue.count)
    }

    private func fetch(offset: Int, limit: Int) async throws -> Page<CashInvoice> {
        var query: [String: String?] = ["limit": "\(limit)", "offset": "\(offset)", "search": search.nonEmpty, "origin": kind, "locationId": Workspace.shared.listLocationFilter]
        if let filter { query.merge(filter.query) { _, new in new } }
        if let period {
            if filter == .paid { query["paidPeriod"] = period } else { query["period"] = period }
        }
        if withTotals { query["totals"] = "true" }
        do {
            let page: CashInvoicePage = try await API.get("/provider-invoices", query: query)
            outsideDays = false
            totals = page.totals
            if let day = page.today { today = day }
            return Page(items: page.items, total: page.total, hasMore: page.hasMore)
        } catch let error as APIError where error.code == "outside_front_desk_days" {
            outsideDays = true
            return Page(items: [], total: 0)
        }
    }

    func loadNumbers() async {
        let numbers: CashInvoicePage? = try? await API.get("/provider-invoices", query: ["limit": "1", "offset": "0", "summary": "true", "locationId": Workspace.shared.listLocationFilter])
        summary = numbers?.summary
        if let day = numbers?.today { today = day }
        let queue: CashChargingQueue? = try? await API.get("/provider-charging", query: ["limit": "0", "offset": "0", "locationId": Workspace.shared.listLocationFilter])
        if let queue { self.queue = queue }
        // Open on "Por cobrar" when there is something to charge (and nothing else was chosen).
        if !openedOnQueue {
            openedOnQueue = true
            if (queue?.count ?? 0) > 0 && filter == nil && kind == nil && search.isEmpty && period == nil { charging = true }
        }
    }
}

/// What a bill's row (or its ⋯ menu) asks the page to do.
enum CashBillAction {
    case open, pay, storeCollect, send, edit, source(ProviderRoute), client, again, refund, forgive, cancel
}

struct InvoicesScreen: View {
    @EnvironmentObject private var workspace: Workspace
    @StateObject private var model = CashInvoicesModel()
    @State private var creating = false
    @State private var paying: CashInvoice?
    @State private var pushed: ProviderRoute?
    @State private var editing: CashInvoice?
    @State private var template: CashInvoice?
    @State private var refunding: CashInvoice?
    @State private var canceling: CashInvoice?
    /// "Perdonar saldo" from a row's menu.
    @State private var forgiving: CashInvoice?
    @State private var sendingId: String?
    /// A bill saved with "Charge it now": its payment opens once the editor has left.
    @State private var pendingPay: CashInvoice?
    /// A bill saved without charging: it opens once the editor has left (the web opens its sheet).
    @State private var pendingOpen: String?

    private var level: MoneyLevel { workspace.moneyLevel }
    private var canSell: Bool { workspace.can(.salesSell) }
    private var canCreate: Bool { workspace.can(.billingCreateInvoice) }

    var body: some View {
        Group {
            if level < .frontDesk {
                PageScroll { NoAccessState(message: L("Ask the workspace owner to give you front desk money or business finances.")) }
            } else {
                page
            }
        }
        .providerPage(L("Invoices"), root: true)
        .sheet(isPresented: $creating, onDismiss: presentPending) {
            CashInvoiceEditorSheet(bill: nil, template: nil) { saved, charge in afterSave(saved, charge) }
        }
        .sheet(item: $editing, onDismiss: presentPending) { bill in
            CashInvoiceEditorSheet(bill: bill, template: nil) { saved, charge in afterSave(saved, charge) }
        }
        .sheet(item: $template, onDismiss: presentPending) { bill in
            CashInvoiceEditorSheet(bill: nil, template: bill) { saved, charge in afterSave(saved, charge) }
        }
        .sheet(item: $paying) { bill in CashInvoicePaySheet(bill: bill) { Task { await reload() } } }
        .sheet(item: $refunding) { bill in CashRefundSheet(bill: bill) { Task { await reload() } } }
        .sheet(item: $canceling) { bill in CashCancelBillSheet(bill: bill) { Task { await reload() } } }
        .sheet(item: $forgiving) { bill in CashForgiveBillSheet(invoiceId: bill.id, listed: bill) { Task { await reload() } } }
        .navigationDestination(item: $pushed) { RouteView(route: $0) }
    }

    private func afterSave(_ bill: CashInvoice, _ charge: Bool) {
        if charge { pendingPay = bill } else { pendingOpen = bill.id }
        Task { await reload() }
    }

    private func presentPending() {
        if let bill = pendingPay { pendingPay = nil; paying = bill }
        else if let id = pendingOpen { pendingOpen = nil; pushed = .invoice(id) }
    }

    private var page: some View {
        PageScroll(maxWidth: 980, refresh: { await reload() }) {
            header
            if !model.charging {
                SearchField(prompt: L("Folio, client or pet"), text: $model.search)
                ScrollView(.horizontal, showsIndicators: false) {
                    Segmented(options: kindOptions, selection: Binding(get: { model.kind ?? "all" }, set: { model.kind = $0 == "all" ? nil : $0 }), look: .raised, label: L("Where the bill came from"))
                        .padding(.vertical, 1)
                }
            }
            filters
            if workspace.multiLocation { LocationMenu() }
            notes
            if model.charging {
                chargingList
            } else {
                billsList
            }
        }
        .reloadsOnScope { await reload() }
        .debounced(model.search) { _ in await model.pager.reload() }
        .onChange(of: model.filter) { _, _ in Task { await model.pager.reload() } }
        .onChange(of: model.kind) { _, _ in Task { await model.pager.reload() } }
        .onChange(of: model.period) { _, _ in Task { await model.pager.reload() } }
        .onChange(of: model.charging) { _, on in Task { if on { await model.chargingPager.reload() } else { await model.pager.reload() } } }
    }

    private var kindOptions: [Segmented<String>.Option] {
        var options = [Segmented<String>.Option("all", L("All@kind"))]
        for kind in CashBillRules.kinds {
            options.append(Segmented<String>.Option(kind, CashBillRules.kindFilter(kind), icon: CashBillRules.kindIcon(kind), tone: CashBillRules.kindTone(kind)))
        }
        return options
    }

    private var filtered: Bool { model.filter != nil || model.kind != nil || model.search.nonEmpty != nil || model.period != nil || model.charging }

    private func clear() {
        model.search = ""
        model.filter = nil
        model.kind = nil
        model.period = nil
        model.charging = false
    }

    private func reload() async {
        model.withTotals = level >= .finances
        await model.loadNumbers()
        if model.charging { await model.chargingPager.reload() } else { await model.pager.reload() }
        if level >= .finances {
            let dashboard: CashDashboard? = try? await API.get("/provider-finance/dashboard", query: ["period": "this_month", "locationId": workspace.listLocationFilter])
            model.collected = dashboard?.totals.collected
        } else {
            let close: CashDayClose? = try? await API.get("/provider-finance/day-close", query: ["day": "today", "locationId": workspace.listLocationFilter])
            model.collected = close?.totals.net
        }
    }

    // MARK: Header

    private var header: some View {
        ModuleHeader(
            icon: "receipt",
            title: L("Invoices"),
            subtitle: L("Visit bills, stays, store sales and deposits — what is waiting to be paid and what came in."),
            stats: stats,
            storageKey: "invoices"
        ) {
            if canSell {
                PMButton(L("Sell at the counter"), systemImage: "shopping-cart", variant: .outline) { pushed = .section(.store) }
            }
            if canCreate {
                PMButton(L("New bill"), systemImage: "plus") { creating = true }
            }
        }
    }

    private var stats: [ModuleStat] {
        let summary = model.summary
        let named = level >= .finances ? "this_month" : "today"
        let collectedOn = model.filter == .paid && model.period == named && !model.charging
        return [
            ModuleStat("due", label: L("Owed to you"), value: summary.map { cashMoney($0.due.amount) } ?? "—",
                       hint: summary.map { $0.due.count == 0 ? L("Nothing waiting to be paid") : LP($0.due.count, "%d bill with a balance", "%d bills with a balance") } ?? L("Sent and waiting to be paid"),
                       icon: "hand-coins", accent: Theme.pink, active: model.filter == .due && !model.charging) { toggle(.due) },
            ModuleStat("overdue", label: L("Overdue"), value: summary.map { cashMoney($0.overdue.amount) } ?? "—",
                       hint: summary.map { $0.overdue.count > 0 ? LP($0.overdue.count, "%d bill past its day", "%d bills past their day") : L("Nothing late") } ?? L("Past their due date"),
                       icon: "alarm-clock", accent: Theme.destructive, attention: (summary?.overdue.amount ?? 0) > 0,
                       active: model.filter == .overdue && !model.charging) { toggle(.overdue) },
            ModuleStat("drafts", label: L("Drafts"), value: summary.map { "\($0.draft.count)" } ?? "—",
                       hint: (summary?.draft.needsPrice ?? 0) > 0
                           ? LP(summary?.draft.needsPrice ?? 0, "%d still needs a price", "%d still need a price")
                           : workspace.can(.billingFinalizeInvoice) ? L("Send them to the desk when ready") : L("Waiting for someone to review"),
                       icon: "pen-line", accent: Theme.aqua, attention: (summary?.draft.needsPrice ?? 0) > 0,
                       active: (model.filter == .draft || model.filter == .unpriced) && !model.charging) {
                // With drafts still to price, the number opens those: they are what holds a charge back.
                toggle((summary?.draft.needsPrice ?? 0) > 0 && model.filter != .draft ? .unpriced : .draft)
            },
            ModuleStat("collected", label: level >= .finances ? L("Collected this month") : L("Collected today"), value: model.collected.map { cashMoney($0) } ?? "—",
                       hint: L("Payments less refunds · see who paid"), icon: "banknote", accent: ProviderState.done.color, active: collectedOn) {
                if collectedOn { model.filter = nil; model.period = nil } else { model.charging = false; model.filter = .paid; model.period = named }
            },
        ]
    }

    private func toggle(_ filter: CashInvoiceFilter) {
        model.charging = false
        model.filter = model.filter == filter ? nil : filter
    }

    // MARK: Filters

    private var filters: some View {
        let summary = model.summary
        let counts: [CashInvoiceFilter: Int?] = [.due: summary?.due.count, .overdue: summary?.overdue.count, .desk: summary?.desk.count, .partial: summary?.partial.count, .draft: summary?.draft.count, .unpriced: summary?.draft.needsPrice]
        let chargingLate = (model.queue?.earlierDays?.count ?? 0) > 0
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !model.charging { periodMenu }
                // "Por cobrar": finished work of any day still to charge, red while one is from an earlier day.
                ToneChip(L("To charge"), icon: "receipt", tone: .state(chargingLate ? .problem : .waiting), count: model.queue?.count, isOn: model.charging) {
                    model.charging.toggle()
                    if model.charging { model.filter = nil }
                }
                ForEach(CashInvoiceFilter.allCases, id: \.self) { filter in
                    ToneChip(filter.label, tone: filter.tone, count: counts[filter] ?? nil, dot: true, isOn: model.filter == filter && !model.charging) { toggle(filter) }
                }
                if filtered {
                    Button(L("Clear filters")) { clear() }
                        .font(Theme.text(14, weight: .bold))
                        .foregroundStyle(Theme.blue)
                        .padding(.horizontal, 8)
                        .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var periodMenu: some View {
        let named: [(String, String)] = level >= .finances
            ? [("today", L("Today")), ("yesterday", L("Yesterday")), ("this_week", L("This week")), ("this_month", L("This month")), ("last_30", L("Last 30 days")), ("last_month", L("Last month")), ("this_year", L("This year"))]
            : [("today", L("Today")), ("yesterday", L("Yesterday"))]
        return Menu {
            Section(model.filter == .paid ? L("Day it was paid") : L("Bill date")) {
                Button(L("Any date")) { model.period = nil }
                ForEach(named, id: \.0) { entry in Button(entry.1) { model.period = entry.0 } }
            }
            if level < .finances {
                Text(L("Only the last 7 days: older days are for business finances."))
            }
        } label: {
            FilterChip(title: named.first { $0.0 == model.period }?.1 ?? L("Any date"), isSelected: model.period != nil, icon: "calendar-range") {}
                .allowsHitTesting(false)
        }
        .accessibilityLabel(model.filter == .paid ? L("Day it was paid") : L("Bill date"))
    }

    // MARK: Notes over the list

    @ViewBuilder private var notes: some View {
        if model.charging {
            let late = model.queue?.earlierDays?.count ?? 0
            (Text(L("Finished visits, stays, hospital stays and home stays of any day not charged yet: no bill, a draft, or at the desk and not charged. Once charged, what clients still owe is in “Owed to you”."))
                + (late > 0 ? Text(" " + LF("%d from earlier days", late)).fontWeight(.bold).foregroundColor(Theme.destructive) : Text("")))
                .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 4)
        } else {
            if model.period != nil {
                note(model.filter == .paid ? L("Bills paid on these days.") : L("Bills dated on these days."))
            }
            if model.kind == "sale" && (canSell || level >= .charging) {
                VStack(alignment: .leading, spacing: 4) {
                    note(L("Counter sales are the Store’s: its Sales tab has each day’s sales, their returns and receipts."))
                    Button(L("Open the Store’s sales")) { pushed = .section(.store) }
                        .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue).buttonStyle(.plain)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft).padding(.horizontal, 4)
    }

    // MARK: The bills

    private var billsList: some View {
        CashPagerObserver(pager: model.pager) { pager in billsCard(pager) }
    }

    @ViewBuilder private func billsCard(_ pager: Pager<CashInvoice>) -> some View {
        ListCard {
            if model.outsideDays {
                EmptyState(systemImage: "triangle-alert", title: L("Only the last 7 days: older days are for business finances."), actionTitle: L("Clear filters"), action: { clear() }, accent: Theme.pink)
            } else {
                CashBillRowsView(pager: pager, today: model.today, byDebt: model.filter?.byDebt ?? false, sendingId: sendingId, onAction: act) {
                    let needle = model.search.nonEmpty
                    let empty = needle == nil ? model.filter.map(\.empty) : nil
                    let listFiltered = model.filter != nil || model.kind != nil || needle != nil || model.period != nil
                    EmptyState(systemImage: "receipt",
                               title: needle.map { LF("Nothing matches “%@”", $0) } ?? empty?.0 ?? (listFiltered ? L("No bills match these filters") : L("No bills yet")),
                               message: needle != nil ? L("Try another folio, client or pet, or clear the filters.") : empty?.1 ?? (listFiltered ? L("Try another search, or clear the filters.") : L("Visit bills, store sales and deposits land here. Start one by hand, or finish a visit and send it to the desk.")),
                               actionTitle: listFiltered ? L("Show every bill") : canCreate ? L("New bill") : nil,
                               action: listFiltered ? { clear() } : canCreate ? { creating = true } : nil,
                               accent: Theme.lime)
                }
            }
        }
        if !model.outsideDays, let total = pager.total, total > 0 {
            listFooter(total)
        }
    }

    /// The count and, for business finances, what the whole filtered list adds up to (the server's).
    private func listFooter(_ total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LP(total, "%d bill", "%d bills")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            if level >= .finances, let totals = model.totals, totals.standingCount > 0 {
                FlowLayout(spacing: 12, lineSpacing: 4) {
                    footerFigure(L("Billed"), totals.billedAmount)
                    footerFigure(L("Paid@amount"), totals.paidAmount)
                    footerFigure(L("Balance"), totals.balanceAmount)
                    // Drafts are billed but neither paid nor owed yet: said apart, so the figures add up.
                    if let drafts = totals.draftAmount, drafts > 0 { footerFigure(L("In drafts"), drafts) }
                    // Forgiven is out of billed, neither paid nor owed: said apart, so the figures still add up.
                    if let forgiven = totals.forgivenAmount, forgiven > 0 { footerFigure(L("Forgiven@amount"), forgiven) }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func footerFigure(_ label: String, _ amount: Int) -> some View {
        HStack(spacing: 4) {
            Text(label).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            Text(cashMoney(amount)).font(.brandHeading(16)).monospacedDigit().foregroundStyle(Theme.inkStrong)
        }
    }

    // MARK: Por cobrar

    private var chargingList: some View {
        CashPagerObserver(pager: model.chargingPager) { pager in chargingCard(pager) }
    }

    @ViewBuilder private func chargingCard(_ pager: Pager<CashChargingItem>) -> some View {
        ListCard {
            if !pager.loadedOnce && pager.isLoading {
                LoadingState()
            } else if let error = pager.error, pager.items.isEmpty {
                EmptyState(systemImage: "triangle-alert", title: L("What is left to charge could not be loaded"), message: error, actionTitle: L("Try again"), action: { Task { await pager.reload() } }, accent: Theme.pink)
            } else if pager.items.isEmpty {
                EmptyState(systemImage: "receipt", title: L("Nothing left to charge"), message: L("Everything finished is charged, given without charging, or owed on an account."), actionTitle: L("Show every bill"), action: { clear() }, accent: Theme.lime)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(pager.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { RowDivider() }
                        CashChargingRow(item: item, today: model.today, canCharge: workspace.can(.billingRecordPayment)) { pay in openCharging(item, pay: pay) }
                            .onAppear { pager.loadMoreIfNeeded(item) }
                    }
                    PagerFooter(pager: pager)
                }
            }
        }
        if let total = model.queue?.count, total > 0, !pager.items.isEmpty {
            HStack(spacing: 4) {
                Text(LP(total, "%d to charge", "%d to charge")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                if let amount = model.queue?.amount, amount > 0 {
                    Text("·").foregroundStyle(Theme.inkSoft)
                    Text(cashMoney(amount, pager.items.first(where: { $0.currency != nil })?.currency)).font(.brandHeading(16)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    /// A visit opens its visit; a bill opens the bill (or, asked to charge, its payment); else the stay or hospital stay.
    private func openCharging(_ item: CashChargingItem, pay: Bool) {
        if pay, let id = item.invoiceId {
            Task {
                if let full: CashInvoice = try? await API.get("/provider-invoices/\(id)") { paying = full } else { Toast.error(L("That bill could not be found.")) }
            }
            return
        }
        pushed = CashChargingRow.route(item)
    }

    // MARK: A bill's actions

    private func act(_ action: CashBillAction, on bill: CashInvoice) {
        switch action {
        case .open: pushed = .invoice(bill.id)
        case .pay: paying = bill
        case .storeCollect: pushed = CashBillRules.storeCheckout(bill)
        case .source(let route): pushed = route
        case .client: pushed = .client(bill.providerClientId)
        case .refund: refunding = bill
        case .forgive: forgiving = bill
        case .cancel: canceling = bill
        case .send:
            sendingId = bill.id
            Task {
                defer { sendingId = nil }
                do {
                    let sent = try await CashBillRules.sendToDesk(bill)
                    Toast.show(LF("%@ is at the desk to be charged.", sent.invoiceNumber))
                    announceDataChanged()
                } catch {
                    Toast.error(error)
                }
            }
        case .edit, .again:
            // A list row carries no lines: the editor reads the whole bill.
            Task {
                guard let full: CashInvoice = try? await API.get("/provider-invoices/\(bill.id)") else { Toast.error(L("That bill could not be found.")); return }
                if case .edit = action { editing = full } else { template = full }
            }
        }
    }
}

/// Redraws a part of the page as its pager loads (the page itself watches only its model).
private struct CashPagerObserver<Item: Decodable & Identifiable, Content: View>: View {
    @ObservedObject var pager: Pager<Item>
    @ViewBuilder let content: (Pager<Item>) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) { content(pager) }
    }
}

/// The bills of the list in their card: under their day (newest first), or one
/// after another with their day when the list reads debts oldest first.
private struct CashBillRowsView<Empty: View>: View {
    @ObservedObject var pager: Pager<CashInvoice>
    let today: String
    let byDebt: Bool
    let sendingId: String?
    let onAction: (CashBillAction, CashInvoice) -> Void
    @ViewBuilder let empty: () -> Empty

    var body: some View {
        if !pager.loadedOnce && pager.isLoading {
            LoadingState()
        } else if let error = pager.error, pager.items.isEmpty {
            EmptyState(systemImage: "triangle-alert", title: L("The bills could not be loaded"), message: error.nonEmpty ?? L("Check the connection and try again."), actionTitle: L("Try again"), action: { Task { await pager.reload() } }, accent: Theme.pink)
        } else if pager.items.isEmpty {
            empty()
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(pager.items.enumerated()), id: \.element.id) { index, bill in
                    let day = CashBillRules.billDay(bill)
                    let newDay = !byDebt && (index == 0 || CashBillRules.billDay(pager.items[index - 1]) != day)
                    if index > 0 { RowDivider() }
                    if newDay {
                        DayBand(title: day == today ? L("Today") : CashBillRules.weekday(day), trailing: LP(pager.items.filter { CashBillRules.billDay($0) == day }.count, "%d bill", "%d bills"), style: .bills)
                        RowDivider()
                    }
                    CashInvoiceRow(bill: bill, today: today, showDay: byDebt, sending: sendingId == bill.id) { onAction($0, bill) }
                        .onAppear { pager.loadMoreIfNeeded(bill) }
                }
                PagerFooter(pager: pager)
            }
        }
    }
}

// MARK: - A bill's row

/// One bill (web `InvoiceRow`, its phone card): who it is for and what it comes
/// to, its folio, where it came from and its day, where it stands, and the next
/// thing to do with the ⋯ menu. The row opens the bill.
struct CashInvoiceRow: View {
    let bill: CashInvoice
    let today: String
    var showDay: Bool = false
    var sending: Bool = false
    let onAction: (CashBillAction) -> Void
    @EnvironmentObject private var workspace: Workspace

    private var money: (Int) -> String { { cashMoney($0, bill.currency) } }

    var body: some View {
        let kind = CashBillRules.kind(bill)
        let walkIn = CashBillRules.isWalkIn(bill)
        let late = CashBillRules.isOverdue(bill, today: today)
        let canceled = bill.status == "canceled"
        let draft = bill.status == "draft"
        let owes = !canceled && !draft && bill.balanceDueAmount > 0
        let canFinalize = workspace.can(.billingFinalizeInvoice)
        let chip = CashBillRules.chip(bill, today: today, canFinalize: canFinalize)
        let hint = CashBillRules.statusHint(bill, today: today, canFinalize: canFinalize)
        let items = CashBillRules.lineCount(bill)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                CashBillAvatar(petName: bill.petName, photoURL: bill.petPhotoUrl, species: bill.petSpecies)
                VStack(alignment: .leading, spacing: 2) {
                    Text(walkIn ? (bill.customerName?.nonEmpty ?? L("Walk-in customer")) : bill.clientName)
                        .font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text(bill.petName?.nonEmpty ?? (walkIn ? L("Counter sale") : L("No pet on it")))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(money(canceled ? bill.totalAmount : CashBillRules.netTotal(bill)))
                        .font(.brandHeading(16)).monospacedDigit()
                        .strikethrough(canceled)
                        .foregroundStyle(canceled ? Theme.inkSoft : Theme.inkStrong)
                    if owes {
                        Text(LF("Owes %@", money(bill.balanceDueAmount))).font(Theme.text(12, weight: .bold)).monospacedDigit()
                            .foregroundStyle(late ? Theme.destructive : Theme.inkStrong)
                        if bill.amountPaid > 0 {
                            Text(LF("Paid %@", money(bill.amountPaid))).font(Theme.text(12)).monospacedDigit().foregroundStyle(Theme.inkSoft)
                        }
                    }
                    if !canceled && bill.refunded > 0 {
                        Text(LF("%@ returned", money(bill.refunded))).font(Theme.text(12)).monospacedDigit().foregroundStyle(Theme.inkSoft)
                    }
                }
                .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(bill.invoiceNumber).font(Theme.text(12.8, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong).lineLimit(1)
                    CashBillKindChip(kind: kind)
                }
                Text((showDay ? CashBillRules.day(bill.issuedAt ?? bill.createdAt) + " · " : "") + LP(items, "%d item@bill", "%d items@bill"))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            HStack(spacing: 8) {
                CashInvoiceStatusChip(text: chip.0, state: chip.1)
                if let hint {
                    Text(hint.text).font(Theme.text(12, weight: hint.late ? .bold : .regular)).foregroundStyle(hint.late ? Theme.destructive : Theme.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 8)
                primary
                menu(kind: kind, walkIn: walkIn)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onAction(.open) }
        .accessibilityAction(named: Text(LF("Open %@", bill.invoiceNumber))) { onAction(.open) }
    }

    @ViewBuilder private var primary: some View {
        switch CashBillRules.next(bill, workspace) {
        case .collect: PMButton(L("Charge"), systemImage: "hand-coins", size: .compact) { onAction(.pay) }
        case .send: PMButton(L("To the desk"), systemImage: "send", size: .compact, isWorking: sending) { onAction(.send) }
        case .edit: PMButton(L("Edit"), systemImage: "pencil", variant: .outline, size: .compact) { onAction(.edit) }
        case nil: EmptyView()
        }
    }

    private func menu(kind: String, walkIn: Bool) -> some View {
        let source = CashBillRules.source(bill).flatMap { CashBillRules.sourceAllowed($0, workspace) ? $0 : nil }
        let refund = CashBillRules.canRefund(bill, workspace)
        let cancel = CashBillRules.canCancel(bill, workspace)
        let forgive = CashBillRules.canForgive(bill, workspace)
        return Menu {
            Button { onAction(.open) } label: { GlyphLabel(L("Open the bill"), icon: "file-text") }
            if CashBillRules.canRecordPayment(bill, workspace) {
                Button { onAction(.pay) } label: { GlyphLabel(L("Take a payment"), icon: "coins") }
            }
            if CashBillRules.canCollectAtStore(bill, workspace) {
                Button { onAction(.storeCollect) } label: { GlyphLabel(L("Charge at the Store, with products"), icon: "shopping-cart") }
            }
            if CashBillRules.canSendToDesk(bill, workspace) {
                Button { onAction(.send) } label: { GlyphLabel(L("Send to the desk"), icon: "send") }
            }
            if CashBillRules.canEdit(bill, workspace) {
                Button { onAction(.edit) } label: { GlyphLabel(L("Edit the bill"), icon: "pencil") }
            }
            if let source {
                Button { onAction(.source(source)) } label: { GlyphLabel(CashBillRules.sourceLabel(source), icon: "external-link") }
            }
            if workspace.can(.clientsView) && !walkIn {
                Button { onAction(.client) } label: { GlyphLabel(L("Open client"), icon: "user-round") }
            }
            if CashBillRules.canBillAgain(bill, workspace) {
                Button { onAction(.again) } label: { GlyphLabel(L("Bill again"), icon: "copy") }
            }
            if refund || forgive || cancel { Divider() }
            if refund {
                Button(role: .destructive) { onAction(.refund) } label: { GlyphLabel(L("Refund or credit note"), icon: "undo-2") }
            }
            if forgive {
                Button(role: .destructive) { onAction(.forgive) } label: { GlyphLabel(L("Forgive the balance"), icon: "hand-heart") }
            }
            if cancel {
                Button(role: .destructive) { onAction(.cancel) } label: { GlyphLabel(L("Cancel the bill"), icon: "ban") }
            }
        } label: {
            IconCircleLabel(size: 32)
        }
        .accessibilityLabel(LF("More for %@", bill.invoiceNumber))
    }
}

/// One bill's status (web `InvoiceStatusChip`): a 24 capsule tinted with the
/// state, its edge at 55%, a 6 dot, 12 bold; late reads red.
struct CashInvoiceStatusChip: View {
    let text: String
    let state: ProviderState

    private var late: Bool { state == .problem }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(state.color).frame(width: 6, height: 6)
            Text(text).lineLimit(1)
        }
        .font(Theme.text(12, weight: .bold))
        .foregroundStyle(late ? Theme.destructive : Theme.inkStrong)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Theme.wash(state.color, late ? 10 : 18), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.mix(state.color, 55, with: Theme.borderSoft), lineWidth: 1))
        .fixedSize()
    }
}

/// Where a bill came from (web `KindChip`): its icon in the kind's hue and its name, on the hue's wash.
struct CashBillKindChip: View {
    let kind: String

    var body: some View {
        let hue = CashBillRules.kindHue(kind)
        HStack(spacing: 4) {
            Glyph(CashBillRules.kindIcon(kind), size: 14).foregroundStyle(Theme.mix(hue.color, 60, with: Theme.inkStrong))
            Text(CashBillRules.kindLabel(kind)).lineLimit(1)
        }
        .font(Theme.text(11.2, weight: .heavy))
        .foregroundStyle(Theme.inkStrong)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Theme.wash(hue.color, 18), in: Capsule())
    }
}

/// Who a bill is for, as a picture (web `BillAvatar`): the pet, or a person on butter for a bill with no pet.
struct CashBillAvatar: View {
    let petName: String?
    var photoURL: String? = nil
    var species: String? = nil
    var size: CGFloat = 40

    var body: some View {
        if let petName = petName?.nonEmpty {
            PetAvatar(name: petName, species: species, photoURL: photoURL, size: size)
        } else {
            Glyph("user-round", size: size / 2)
                .foregroundStyle(Theme.inkStrong)
                .frame(width: size, height: size)
                .background(Theme.wash(Theme.butter, 45), in: Circle())
        }
    }
}

// MARK: - Por cobrar

/// One finished visit, stay, hospital stay or home stay still to charge (web
/// `ChargingRow`): what it was and for whom, its day (red from an earlier day),
/// where its bill stands and what is left. A bill at the desk offers "Charge".
struct CashChargingRow: View {
    let item: CashChargingItem
    let today: String
    var canCharge: Bool = false
    let onOpen: (_ pay: Bool) -> Void

    static func route(_ item: CashChargingItem) -> ProviderRoute {
        if item.source == "visit", let visit = item.appointmentId { return .appointment(visit) }
        if let bill = item.invoiceId { return .invoice(bill) }
        return item.source == "hospital" ? .hospitalization(item.sourceId) : .stay(item.sourceId)
    }

    private var what: String {
        switch item.source {
        case "visit": item.serviceLabel ?? ""
        case "stay": L("Stay")
        case "hospital": L("Hospital")
        default: L("Home stay")
        }
    }

    private var stage: (String, ProviderState) {
        switch item.state {
        case "needs_price": (L("Needs a price"), .waiting)
        case "unsent": (L("Being built"), .active)
        case "ready": (L("Ready to charge"), .waiting)
        default: (L("No bill yet"), .closed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                CashBillAvatar(petName: item.petName)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\((item.petNames ?? [item.petName]).joined(separator: ", ")) · \(what)").font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text([item.clientName, item.vetName].compactMap { $0?.nonEmpty }.joined(separator: " · ")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(item.earlierDay ? "\(CashBillRules.day(item.day)) · \(DateText.time(item.at))" : "\(L("Today")) · \(DateText.time(item.at))")
                    .font(Theme.text(12, weight: item.earlierDay ? .bold : .regular)).monospacedDigit()
                    .foregroundStyle(item.earlierDay ? Theme.destructive : Theme.inkSoft)
                    .lineLimit(1)
            }
            HStack(spacing: 12) {
                CashBillStageBadge(text: stage.0, state: stage.1)
                Spacer(minLength: 8)
                Text(item.amount.map { cashMoney($0, item.currency) } ?? "—").font(.brandHeading(16)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                if canCharge && item.state == "ready" {
                    PMButton(L("Charge"), systemImage: "hand-coins", variant: .outline, size: .compact) { onOpen(true) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onOpen(false) }
    }
}

/// Where a bill stands, in a few words (web `StageBadge`): a capsule on the state's 22% wash, 12 bold navy.
struct CashBillStageBadge: View {
    let text: String
    let state: ProviderState

    var body: some View {
        Text(text)
            .font(Theme.text(12, weight: .bold))
            .foregroundStyle(Theme.inkStrong)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.wash(state.color, 22), in: Capsule())
    }
}
