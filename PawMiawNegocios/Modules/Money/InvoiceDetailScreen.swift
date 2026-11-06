//
//  InvoiceDetailScreen.swift
//  PawMiawNegocios
//
//  One bill (web: provider-invoice-detail-sheet.tsx, provider-invoice-payment-sheet.tsx,
//  visits/visit-money-sheets RefundSheet, invoices-page/cancel-invoice-sheet.tsx):
//  its lines, tax, discount, payments and credit notes, and what can be done
//  with it — charge it, send it to the desk, edit it, refund or credit it,
//  forgive what is left ("Perdonar saldo", web invoices-page/forgive-invoice-
//  sheet.tsx, paw-miaw-backend docs/family-money.md §1), cancel it, bill it
//  again, open or email its receipt. A forgiven bill says what was forgiven,
//  when, by whom and why, and takes no payment, edit or cancel. Level 1 (the
//  bill in front of you) reads it; each action follows its own permission.
//

import SwiftUI

struct InvoiceDetailScreen: View {
    let invoiceId: String
    @EnvironmentObject private var workspace: Workspace
    @StateObject private var loader: Loader<CashInvoice>
    @State private var clientEmail: String?
    @State private var paying = false
    @State private var editing = false
    @State private var again = false
    @State private var refunding = false
    @State private var canceling = false
    @State private var forgiving = false
    @State private var emailing = false
    @State private var sending = false
    @State private var pendingPay = false

    init(invoiceId: String) {
        self.invoiceId = invoiceId
        _loader = StateObject(wrappedValue: Loader<CashInvoice> { try await API.get("/provider-invoices/\(invoiceId)") })
    }

    var body: some View {
        PageScroll(refresh: { await loader.load() }) {
            if workspace.moneyLevel < .charging {
                NoAccessState()
            } else {
                LoadedContent(loader: loader) { bill in content(bill) }
            }
        }
        .providerPage(loader.value?.invoiceNumber ?? L("Bill"))
        .reloadsOnScope { await load() }
        .sheet(isPresented: $paying) { if let bill = loader.value { CashInvoicePaySheet(bill: bill) { Task { await loader.load() } } } }
        .sheet(isPresented: $editing, onDismiss: {
            if pendingPay { pendingPay = false; paying = true }
        }) {
            if let bill = loader.value {
                CashInvoiceEditorSheet(bill: bill, template: nil) { _, charge in
                    pendingPay = charge
                    Task { await loader.load() }
                }
            }
        }
        .sheet(isPresented: $again) {
            if let bill = loader.value {
                CashInvoiceEditorSheet(bill: nil, template: bill) { _, _ in Task { await loader.load() } }
            }
        }
        .sheet(isPresented: $refunding) { if let bill = loader.value { CashRefundSheet(bill: bill) { Task { await loader.load() } } } }
        .sheet(isPresented: $emailing) {
            if let bill = loader.value { CashSendReceiptSheet(bill: bill, clientEmail: clientEmail) }
        }
        .sheet(isPresented: $canceling) {
            if let bill = loader.value { CashCancelBillSheet(bill: bill) { Task { await loader.load() } } }
        }
        .sheet(isPresented: $forgiving) {
            if let bill = loader.value { CashForgiveBillSheet(invoiceId: bill.id, listed: bill) { Task { await loader.load() } } }
        }
    }

    private func load() async {
        await loader.load()
        if let bill = loader.value, !CashBillRules.isWalkIn(bill), workspace.can(.clientsView) {
            let client: PickedClient? = try? await API.get("/provider-clients/\(bill.providerClientId)")
            clientEmail = client?.ownerEmail
        }
    }

    @ViewBuilder private func content(_ bill: CashInvoice) -> some View {
        header(bill)
        summary(bill)
        lines(bill)
        payments(bill)
        if let notes = bill.creditNotes, !notes.isEmpty {
            // A credit note hands no money back, so it is not among the payments: each is listed here with why.
            SectionCard(L("Credit notes"), subtitle: L("Taken off what was owed; no money was handed back."), icon: "receipt-text", accent: Theme.aqua) {
                ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                    if index > 0 { RowDivider() }
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Credit note")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            Text([note.createdAt.map { CashBillRules.day($0) }, note.byName?.nonEmpty].compactMap { $0 }.joined(separator: " · "))
                                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                            if let reason = note.reason?.nonEmpty { Text(reason).font(Theme.text(12)).foregroundStyle(Theme.inkStrong).padding(.top, 2) }
                        }
                        Spacer(minLength: 8)
                        Text("−\(cashMoney(note.amount, bill.currency))").font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        if bill.status != "canceled" { receipt(bill) }
        if bill.billingNote?.nonEmpty != nil || bill.notes?.nonEmpty != nil {
            SectionCard(L("Notes"), icon: "notebook-text", accent: Theme.aqua) {
                VStack(alignment: .leading, spacing: 8) {
                    if let note = bill.billingNote?.nonEmpty { noteBlock(L("Billing note"), note) }
                    if let note = bill.notes?.nonEmpty { noteBlock(L("Internal notes"), note) }
                }
                .padding(16)
            }
        }
        details(bill)
        AuditHistoryCard(entityType: "provider_invoice", entityId: bill.id, title: L("History"), description: L("Every change to this bill, its PDF and its payments."))
    }

    // MARK: Header (the web sheet's title and footer actions)

    private func header(_ bill: CashInvoice) -> some View {
        let kind = CashBillRules.kind(bill)
        return ModuleHeader(
            icon: CashBillRules.kindIcon(kind),
            title: bill.invoiceNumber,
            subtitle: LF("%@ · issued %@", CashBillRules.kindLabel(kind), CashBillRules.day(bill.issuedAt ?? bill.createdAt)),
            accent: CashBillRules.kindHue(kind).color,
            storageKey: "invoice"
        ) {
            if CashBillRules.canEdit(bill, workspace) {
                PMButton(L("Edit the bill"), systemImage: "pencil", variant: .outline) { editing = true }
            }
            if CashBillRules.canSendToDesk(bill, workspace) {
                PMButton(L("Send to the desk"), systemImage: "send", isWorking: sending) { sendToDesk(bill) }
            }
            if CashBillRules.canRecordPayment(bill, workspace) {
                PMButton(LF("Charge %@", cashMoney(bill.balanceDueAmount, bill.currency)), systemImage: "coins") { paying = true }
            }
        }
    }

    // MARK: Who, where it came from, where it stands

    @ViewBuilder private func summary(_ bill: CashInvoice) -> some View {
        let kind = CashBillRules.kind(bill)
        let today = CashDay.today
        let late = CashBillRules.isOverdue(bill, today: today)
        let draft = bill.status == "draft"
        let canceled = bill.status == "canceled"
        let forgiven = bill.status == "forgiven"
        let canFinalize = workspace.can(.billingFinalizeInvoice)
        let chip = CashBillRules.chip(bill, today: today, canFinalize: canFinalize)
        let walkIn = CashBillRules.isWalkIn(bill)
        let money = { (cents: Int) in cashMoney(cents, bill.currency) }
        Card(padding: 16, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                CashBillAvatar(petName: bill.petName, photoURL: bill.petPhotoUrl, species: bill.petSpecies, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(walkIn ? (bill.customerName?.nonEmpty ?? L("Walk-in customer")) : bill.clientName)
                        .font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text(bill.petName?.nonEmpty ?? (walkIn ? L("Counter sale") : L("No pet on it")))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    CashInvoiceStatusChip(text: chip.0, state: chip.1)
                    CashBillKindChip(kind: kind)
                }
            }
            CashMoneyCells(cells: [
                .init(label: L("Total"), value: money(canceled ? bill.totalAmount : CashBillRules.netTotal(bill)), tone: canceled ? .soft : .strong, struck: canceled),
                .init(label: L("Paid@amount"), value: money(bill.amountPaid), tone: bill.amountPaid > 0 ? .strong : .soft),
                .init(label: L("Balance"), value: draft || canceled ? "—" : money(bill.balanceDueAmount),
                      tone: draft || canceled || bill.balanceDueAmount <= 0 ? .soft : late ? .late : .strong),
            ], stacksOnPhone: true)
            if canceled {
                VStack(alignment: .leading, spacing: 2) {
                    Text((bill.canceledAt.map { LF("Canceled %@", CashBillRules.dateTime($0)) } ?? L("Canceled@status")) + (bill.canceledBy?.name?.nonEmpty.map { " · \($0)" } ?? ""))
                        .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    if let reason = bill.cancelReason?.nonEmpty { Text(reason).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            } else if forgiven {
                // "Saldo perdonado {monto} · {fecha} · {quién}", then why: the business's own record of it.
                VStack(alignment: .leading, spacing: 2) {
                    Text([
                        LF("Balance forgiven %@", money(bill.forgivenAmount ?? 0)),
                        bill.forgivenAt.map { CashBillRules.dateTime($0) },
                        bill.forgivenBy?.name?.nonEmpty,
                    ].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    if let reason = bill.forgivenReason?.nonEmpty { Text("“\(reason)”").font(Theme.text(14)).foregroundStyle(Theme.inkStrong) }
                    Text(L("The family sees “Balance forgiven” in its receipts; the reason stays with your team."))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            } else if late {
                let days = CashBillRules.daysLate(bill, today: today)
                Text((days == 0 ? L("Marked overdue") : CashText.daysLate(days)) + (bill.dueAt.map { " · " + LF("Due %@", CashBillRules.day($0)) } ?? ""))
                    .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.destructive)
            } else if draft {
                summaryNote(bill.lines.contains { $0.unitAmount <= 0 && $0.courtesy != true } || bill.lines.isEmpty
                    ? L("A draft waiting for a price: every line needs one, or to be marked as a courtesy, before it can be charged.")
                    : canFinalize ? L("A draft — only your team sees it. Send it to the desk when it is ready to charge.") : L("A draft — someone who can finalize bills sends it to the desk."))
            } else if kind == "deposit" {
                summaryNote(L("A deposit becomes credit on the client’s account and is spent at checkout."))
            } else if kind == "sale" {
                summaryNote(L("A counter sale changes with a return or a cancel in the Store, not here."))
            } else if workspace.can(.billingEditInvoice) && bill.amountPaid > 0 {
                summaryNote(L("It has payments: to cancel it, give the money back first with a refund."))
            }
            links(bill)
        }
    }

    private func summaryNote(_ text: String) -> some View {
        Text(text).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
    }

    /// Where the bill goes from here (web: the sheet's link chips).
    @ViewBuilder private func links(_ bill: CashInvoice) -> some View {
        let source = CashBillRules.source(bill).flatMap { CashBillRules.sourceAllowed($0, workspace) ? $0 : nil }
        let openClient = workspace.can(.clientsView) && !CashBillRules.isWalkIn(bill)
        let store = CashBillRules.canCollectAtStore(bill, workspace)
        let billAgain = CashBillRules.canBillAgain(bill, workspace)
        let refund = CashBillRules.canRefund(bill, workspace)
        let cancel = CashBillRules.canCancel(bill, workspace)
        let forgive = CashBillRules.canForgive(bill, workspace)
        if source != nil || openClient || store || billAgain || refund || forgive || cancel {
            FlowLayout(spacing: 6) {
                if let source {
                    NavigationLink(value: source) { CashLinkChip(title: CashBillRules.sourceLabel(source), icon: "external-link") }.buttonStyle(.plain)
                }
                if openClient {
                    NavigationLink(value: ProviderRoute.client(bill.providerClientId)) { CashLinkChip(title: L("Open client"), icon: "user-round") }.buttonStyle(.plain)
                }
                if store {
                    NavigationLink(value: CashBillRules.storeCheckout(bill)) { CashLinkChip(title: L("Charge at the Store, with products"), icon: "shopping-cart") }.buttonStyle(.plain)
                }
                if billAgain {
                    Button { again = true } label: { CashLinkChip(title: L("Bill again"), icon: "copy") }.buttonStyle(.plain)
                }
                if refund {
                    Button { refunding = true } label: { CashLinkChip(title: L("Refund or credit note"), icon: "undo-2", danger: true) }.buttonStyle(.plain)
                }
                if forgive {
                    Button { forgiving = true } label: { CashLinkChip(title: L("Forgive the balance"), icon: "hand-heart", danger: true) }.buttonStyle(.plain)
                }
                if cancel {
                    Button { canceling = true } label: { CashLinkChip(title: L("Cancel the bill"), icon: "ban", danger: true) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func sendToDesk(_ bill: CashInvoice) {
        sending = true
        Task {
            defer { sending = false }
            do {
                let sent = try await CashBillRules.sendToDesk(bill)
                Toast.show(LF("%@ is at the desk to be charged.", sent.invoiceNumber))
                announceDataChanged()
                await loader.load()
            } catch {
                Toast.error(error)
            }
        }
    }

    // MARK: What it charges

    @ViewBuilder private func lines(_ bill: CashInvoice) -> some View {
        let money = { (cents: Int) in cashMoney(cents, bill.currency) }
        let draft = bill.status == "draft"
        let isSale = CashBillRules.kind(bill) == "sale"
        SectionCard(L("What it charges"), icon: "file-text", accent: Theme.aqua) {
            if bill.lines.isEmpty {
                Text(L("No items yet.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(16)
            }
            ForEach(Array(bill.lines.enumerated()), id: \.element.id) { index, line in
                if index > 0 { RowDivider() }
                lineRow(line, draft: draft, money: money)
            }
            if !bill.lines.isEmpty { RowDivider() }
            VStack(alignment: .leading, spacing: 4) {
                CashBillTotalRow(label: L("Subtotal"), value: money(bill.subtotalAmount))
                if bill.discountAmount > 0 { CashBillTotalRow(label: L("Discount"), value: "−\(money(bill.discountAmount))") }
                if bill.taxAmount > 0 { CashBillTotalRow(label: bill.pricesIncludeTax == true ? L("Tax (included in the prices)") : L("Tax"), value: money(bill.taxAmount)) }
                CashBillTotalRow(label: L("Total"), value: money(bill.totalAmount), strong: true)
                let returned = bill.refunded
                if returned > 0 {
                    // Money given back shows as a payment below; a credit note does not, so each is said by name when a bill has both.
                    let moneyBack = min(returned, bill.allPayments.filter { $0.isRefund && !$0.voided }.reduce(0) { $0 + $1.amount })
                    let credited = max(0, returned - moneyBack)
                    if !isSale && moneyBack > 0 && credited > 0 {
                        CashBillTotalRow(label: L("Refunded"), value: "−\(money(moneyBack))")
                        CashBillTotalRow(label: L("Credit notes"), value: "−\(money(credited))")
                    } else {
                        CashBillTotalRow(label: isSale ? L("Returned") : moneyBack > 0 ? L("Refunded") : credited > 0 ? L("Credit notes") : L("Refunded or credited"), value: "−\(money(returned))")
                    }
                }
                if let forgiven = bill.forgivenAmount, forgiven > 0 {
                    CashBillTotalRow(label: L("Forgiven@amount"), value: "−\(money(forgiven))")
                }
                if !draft && bill.status != "canceled" {
                    CashBillTotalRow(label: L("Paid@amount"), value: money(bill.amountPaid))
                    CashBillTotalRow(label: L("Balance"), value: money(bill.balanceDueAmount), strong: true)
                }
                if let reason = bill.discountReason?.nonEmpty {
                    (Text("\(L("Why the discount")): ").fontWeight(.bold) + Text(reason))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.wash(Theme.mango, 14), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                        .padding(.top, 8)
                }
            }
            .padding(16)
        }
    }

    /// One line: what it is, how many at what price, and what stands out about it (web `LineRow`).
    private func lineRow(_ line: CashInvoiceLine, draft: Bool, money: @escaping (Int) -> String) -> some View {
        let listed = line.listUnitAmount ?? line.catalogItem?.defaultUnitAmount
        let overridden = listed != nil && listed != line.unitAmount && line.unitAmount > 0
        let unpriced = draft && line.unitAmount <= 0 && line.courtesy != true
        return HStack(alignment: .top, spacing: 12) {
            Glyph(line.itemType == "product" ? "package" : "stethoscope", size: 14)
                .foregroundStyle(Theme.inkStrong)
                .frame(width: 28, height: 28)
                .background(Theme.wash(Theme.aqua, 18), in: Circle())
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.label).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                Text(LF("%d × %@", line.quantity, money(line.unitAmount))
                     + (overridden ? " · " + LF("Catalog price %@", money(listed ?? 0)) + (line.priceOverriddenBy?.name?.nonEmpty.map { " · \($0)" } ?? "") : ""))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                if let description = line.description?.nonEmpty {
                    Text(description).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).padding(.top, 2)
                }
                if unpriced || line.courtesy == true || line.changedAfterSent == true {
                    FlowLayout(spacing: 4) {
                        if unpriced { CashLineFlag(text: L("Needs a price"), tone: Theme.destructive, danger: true) }
                        if line.courtesy == true { CashLineFlag(text: L("Courtesy"), tone: Theme.pink) }
                        if line.changedAfterSent == true { CashLineFlag(text: L("Changed after it went to the desk"), tone: Theme.mango) }
                    }
                    .padding(.top, 4)
                }
                if let reason = line.adjustmentReason?.nonEmpty {
                    Text("“\(reason)”").font(Theme.text(12)).foregroundStyle(Theme.inkStrong).padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            Text(money(line.quantity * line.unitAmount)).font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Payments

    @ViewBuilder private func payments(_ bill: CashInvoice) -> some View {
        SectionCard(L("Payments"), icon: "coins", accent: Theme.pink) {
            if bill.allPayments.isEmpty {
                Text(L("No payments yet.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(16)
            }
            ForEach(Array(bill.allPayments.enumerated()), id: \.element.id) { index, payment in
                if index > 0 { RowDivider() }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text((payment.isRefund ? "\(L("Refund")) · " : "") + (payment.method == "credit" ? L("From their deposit") : CashText.method(payment.method)))
                                .strikethrough(payment.voided)
                                .foregroundStyle(payment.voided ? Theme.inkSoft : Theme.inkStrong)
                            if payment.voided {
                                Text(L("Voided")).font(Theme.text(11.2, weight: .bold)).foregroundStyle(Theme.inkSoft)
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Theme.inkSoft.opacity(0.14), in: Capsule())
                            }
                        }
                        .font(Theme.text(14, weight: .bold))
                        Text([payment.paidAt.map { CashBillRules.day($0) }, payment.reference?.nonEmpty, payment.collectedBy?.name?.nonEmpty].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        if let notes = payment.notes?.nonEmpty { Text(notes).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).padding(.top, 2) }
                    }
                    Spacer(minLength: 8)
                    Text("\(payment.isRefund ? "−" : "")\(cashMoney(payment.amount, payment.currency ?? bill.currency))")
                        .font(Theme.text(14, weight: .bold)).monospacedDigit()
                        .strikethrough(payment.voided)
                        .foregroundStyle(payment.voided ? Theme.inkSoft : Theme.inkStrong)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: Receipt

    private func receipt(_ bill: CashInvoice) -> some View {
        let hasReceipt = bill.status != "draft" && bill.amountPaid > 0
        return SectionCard(hasReceipt ? L("Receipt") : L("The bill as a PDF"),
                           subtitle: hasReceipt ? L("What the client is handed: the bill with its payments. It is not a tax invoice (CFDI).") : L("The bill as it stands, to show or send before it is paid. The receipt comes with the first payment."),
                           icon: "receipt-text", accent: Theme.aqua) {
            FlowLayout(spacing: 8) {
                DocumentButton(title: L("Open or print the PDF"), systemImage: "external-link", path: "/provider-invoices/\(bill.id)/pdf", fileName: bill.invoiceNumber) {
                    // The server drops the stored PDF whenever the bill changes: none kept = make a fresh one.
                    if bill.pdfUrl == nil { let _: EmptyResponse = try await API.post("/provider-invoices/\(bill.id)/pdf") }
                }
                if hasReceipt { PMButton(L("Email the receipt"), systemImage: "mail", variant: .outline, size: .compact) { emailing = true } }
                if CashBillRules.kind(bill) == "deposit" {
                    DocumentButton(title: L("Deposit receipt"), systemImage: "file-down", path: "/provider-finance/deposits/\(bill.id)/pdf", fileName: bill.invoiceNumber)
                }
            }
            .padding(16)
        }
    }

    // MARK: Notes and details

    private func noteBlock(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
            Text(text).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    private func details(_ bill: CashInvoice) -> some View {
        var rows: [(String, String)] = [
            (L("Issued"), bill.issuedAt.map { CashBillRules.day($0) } ?? L("Not set")),
            (L("Due"), bill.dueAt.map { CashBillRules.day($0) } ?? L("Not set")),
            (L("Made by"), bill.createdBy?.name?.nonEmpty ?? L("Someone on the team")),
        ]
        if let name = bill.finalizedBy?.name?.nonEmpty { rows.append((L("Sent to the desk by"), name)) }
        if let name = bill.assignedMember?.name?.nonEmpty { rows.append((L("Assigned to"), name)) }
        rows.append((L("Last changed"), [bill.updatedAt.map { CashBillRules.dateTime($0) }, bill.updatedBy?.name?.nonEmpty].compactMap { $0 }.joined(separator: " · ")))
        return SectionCard(L("Details"), icon: "info", accent: Theme.aqua) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { RowDivider() }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.0.uppercased()).font(Theme.text(12, weight: .bold)).tracking(0.96).foregroundStyle(Theme.inkSoft)
                    Spacer(minLength: 8)
                    Text(row.1.nonEmpty ?? "—").font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }
}

// MARK: - Pieces of a bill

/// Total · Paid · Balance in hairline cells (web `MoneyCell` / `SheetMoney`):
/// a micro-label and the amount in Fredoka; on a phone the bill's page reads
/// them one per row (label left, amount right).
struct CashMoneyCells: View {
    enum Tone { case strong, soft, late }
    struct Cell { let label: String; let value: String; var tone: Tone = .strong; var struck: Bool = false }

    let cells: [Cell]
    var stacksOnPhone: Bool = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let stacked = stacksOnPhone && sizeClass != .regular
        Group {
            if stacked {
                VStack(spacing: 1) { ForEach(cells.indices, id: \.self) { cell(cells[$0], row: true) } }
            } else {
                HStack(spacing: 1) { ForEach(cells.indices, id: \.self) { cell(cells[$0], row: false) } }
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(Theme.borderSoft)
        .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    @ViewBuilder private func cell(_ cell: Cell, row: Bool) -> some View {
        let label = Text(cell.label.uppercased()).font(Theme.text(10.6, weight: .heavy)).tracking(1.06).foregroundStyle(Theme.inkSoft)
        let value = Text(cell.value).font(.brandHeading(row ? 16 : 18)).monospacedDigit().strikethrough(cell.struck)
            .foregroundStyle(cell.tone == .late ? Theme.destructive : cell.tone == .soft ? Theme.inkSoft : Theme.inkStrong)
            .lineLimit(1).minimumScaleFactor(0.7)
        Group {
            if row {
                HStack(alignment: .firstTextBaseline, spacing: 12) { label; Spacer(minLength: 8); value }
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 4) { label.lineLimit(1); value }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 12)
        .background(Theme.surface)
    }
}

/// A label and an amount in a bill's totals (web `TotalRow`): grey and semibold,
/// or bold with the amount in Fredoka 18 for the total and the balance.
struct CashBillTotalRow: View {
    let label: String
    let value: String
    var strong: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(Theme.text(14, weight: strong ? .bold : .regular)).foregroundStyle(strong ? Theme.inkStrong : Theme.inkSoft)
            Spacer(minLength: 8)
            Text(value).font(strong ? .brandHeading(18) : Theme.text(14, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
        }
    }
}

/// What stands out about a line (web `LineFlag`): a 20 capsule with the tone's edge and wash.
private struct CashLineFlag: View {
    let text: String
    let tone: Color
    var danger: Bool = false

    var body: some View {
        Text(text)
            .font(Theme.text(10.9, weight: .heavy))
            .foregroundStyle(danger ? Theme.destructive : Theme.inkStrong)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Theme.wash(tone, 12), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.mix(tone, 45, with: Theme.borderSoft), lineWidth: 1))
    }
}

/// A place a bill links to (web `LINK_CHIP`): a 36 capsule with a grey edge, 12 bold; red for a refund or a cancel.
private struct CashLinkChip: View {
    let title: String
    let icon: String
    var danger: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Glyph(icon, size: 14)
            Text(title).lineLimit(1)
        }
        .font(Theme.text(12, weight: .bold))
        .foregroundStyle(danger ? Theme.destructive : Theme.inkStrong)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
        .contentShape(Capsule())
    }
}

// MARK: - Canceling a bill

/// Canceling a bill, asked with its reason (web `CancelInvoiceSheet`): always
/// POST /provider-invoices/{id}/cancel; a canceled bill is never opened again.
struct CashCancelBillSheet: View {
    let bill: CashInvoice
    var onDone: () -> Void = {}

    /// What else the cancel undoes (web: the list under the reason).
    private var consequences: [String] {
        var list: [String] = []
        if bill.status != "draft" && bill.lines.contains(where: { $0.itemType == "product" }) { list.append(L("Its products go back on the shelf.")) }
        if bill.lines.contains(where: { $0.prescriptionItemId != nil }) { list.append(L("What it dispensed goes back to the prescription.")) }
        if CashBillRules.kind(bill) == "visit" { list.append(L("The visit itself stays as it is.")) }
        return list
    }

    var body: some View {
        ConfirmSheet(
            title: LF("Cancel %@?", bill.invoiceNumber),
            message: ([bill.status == "draft"
                ? L("This draft leaves the list of bills to charge and stays in the list as canceled. It can’t be opened again: to charge it again, use “Bill again”.")
                : L("It leaves what the client owes and stays in the list as canceled. It can’t be opened again: to charge it again, use “Bill again”.")] + consequences).joined(separator: "\n\n"),
            confirmTitle: L("Cancel the bill"), destructive: true, askReason: true, reasonRequired: true, reasonLabel: L("Why is it canceled?"), cancelTitle: L("Keep it")
        ) { reason in
            var body: [String: Any?] = ["reason": reason]
            if let revision = bill.revision { body["expectedRevision"] = revision }
            do {
                let canceled: CashInvoice = try await API.post("/provider-invoices/\(bill.id)/cancel", body: body)
                Toast.show(LF("%@ was canceled.", canceled.invoiceNumber))
                announceDataChanged()
                onDone()
            } catch let error as APIError where error.code == "stale_bill" {
                onDone()
                throw APIError(status: 409, message: L("Someone changed this bill a moment ago — look at it again before canceling."), code: error.code, fields: [:])
            }
        }
    }
}

// MARK: - Forgiving what is left

/// "Perdonar saldo" (web invoices-page/forgive-invoice-sheet.tsx, paw-miaw-backend
/// docs/family-money.md §1 and §6): what is left on a bill out of draft is forgiven, with a
/// reason the business keeps (the family only reads "Saldo perdonado"). Said before it is
/// done: the amount, that it is an exception in Cortes, that it leaves Te deben and is not
/// income, and that what was paid stays paid. Permission `billing.waive_visit`; callers only
/// offer it to those who have it. Opened from a bill (Cuentas' row and the bill's page), from a
/// visit whose fee the family disputes and from Home's "Te necesita": the bill is read in full
/// here, so its id is enough. POST /provider-invoices/{id}/forgive with the bill's revision.
struct CashForgiveBillSheet: View {
    let invoiceId: String
    /// A copy the caller already has (a list row), shown while the bill is read.
    var listed: CashInvoice? = nil
    var onDone: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var bill: CashInvoice?
    @State private var reason = ""
    @State private var working = false
    @State private var failed = false

    private var shown: CashInvoice? { bill ?? (listed?.id == invoiceId ? listed : nil) }
    private var blocker: String? { shown.flatMap { CashBillRules.forgiveBlocker($0) } }

    var body: some View {
        let amount = shown.map { cashMoney($0.balanceDueAmount, $0.currency) } ?? ""
        let ready = shown != nil && blocker == nil
        ProviderModal(
            title: ready ? LF("Forgive %1$@ of %2$@?", amount, shown?.invoiceNumber ?? "") : L("Forgive the balance"),
            subtitle: L("It is recorded as an exception in Cortes. The family sees “Balance forgiven”."),
            systemImage: "hand-heart", accent: .pink, isDirty: !reason.isEmpty, form: form,
            primaryTitle: ready ? LF("Forgive %@", amount) : L("Forgive the balance"), primaryVariant: .destructive,
            isWorking: working, cancelTitle: L("Keep charging"), primaryIcon: "hand-heart", primaryDisabled: shown == nil
        ) {
            confirm()
        } content: {
            if let shown {
                if let blocker {
                    Text(CashBillRules.forgiveRefusalText(blocker) ?? L("This bill can’t be forgiven now."))
                        .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.destructive)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("It leaves what the client owes, Te deben and To charge, and doesn’t count as income."))
                        if shown.amountPaid > 0 {
                            Text(LF("What was paid (%@) stays paid.", cashMoney(shown.amountPaid, shown.currency)))
                        }
                    }
                    .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                    PMTextField(L("Why is it forgiven?"), text: $reason, key: "reason", form: form, prompt: L("e.g. The family moved away, a courtesy, a dispute settled"), hint: L("Only your team sees the reason."), multiline: true, required: true, lines: 2...5)
                }
            } else if failed {
                ErrorState(message: L("That bill could not be found.")) { await load() }
            } else {
                LoadingState()
            }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    private func load() async {
        do {
            bill = try await API.get("/provider-invoices/\(invoiceId)")
            failed = false
        } catch {
            if shown == nil { failed = true }
        }
    }

    private func confirm() {
        guard let shown else { return }
        if let blocker {
            Toast.error(CashBillRules.forgiveRefusalText(blocker) ?? L("This bill can’t be forgiven now."))
            return
        }
        guard form.check([("reason", reason.nonEmpty == nil ? L("Say why the balance is forgiven.") : nil)]) else { return }
        var body: [String: Any?] = ["reason": reason.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let revision = shown.revision { body["expectedRevision"] = revision }
        working = true
        Task {
            defer { working = false }
            do {
                let forgiven: CashInvoice = try await API.post("/provider-invoices/\(shown.id)/forgive", body: body)
                Toast.show(LF("%1$@ of %2$@ forgiven.", cashMoney(forgiven.forgivenAmount ?? shown.balanceDueAmount, shown.currency), shown.invoiceNumber))
                announceDataChanged()
                onDone()
                dismiss()
            } catch let error as APIError {
                if error.code == "reason_required" {
                    _ = form.check([("reason", L("Say why the balance is forgiven."))])
                } else if error.code == "stale_bill" {
                    Toast.error(CashBillRules.forgiveRefusalText("stale_bill") ?? error.message)
                    onDone()
                    dismiss()
                } else if let code = error.code, let text = CashBillRules.forgiveRefusalText(code) {
                    Toast.error(text)
                } else {
                    Toast.error(errorText(error, fallback: L("Could not forgive the balance.")))
                }
            } catch {
                Toast.error(errorText(error, fallback: L("Could not forgive the balance.")))
            }
        }
    }
}

// MARK: - Charging a bill

/// Taking money on one bill: today through the one checkout (methods split,
/// change, credit on account, the register), or a payment that arrived on an
/// earlier day (recorded on that day, out of today's shift).
struct CashInvoicePaySheet: View {
    let bill: CashInvoice
    var onSaved: () -> Void = {}
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var device = CashDeviceRegister()
    @StateObject private var tenders = CashTenders()
    @StateObject private var form = FormState()
    @State private var account: CashAccount?
    @State private var clientEmail: String?
    @State private var clientLinked: Bool?
    @State private var earlier = false
    @State private var amount: Int?
    @State private var method = "bank_transfer"
    @State private var paidOn = Date()
    @State private var reference = ""
    @State private var notes = ""
    @State private var email = ""
    @State private var sendReceipt = false
    @State private var working = false
    @State private var done: (paid: Int, change: Int, left: Int, emailedTo: String?)?
    @State private var requestId = cashRequestId()
    @State private var seed = 0

    private var balance: Int { bill.balanceDueAmount }
    private var registerOpen: Bool { device.sessionId != nil && !device.stale }
    private var walkIn: Bool { CashBillRules.isWalkIn(bill) }
    private var firstDay: Date {
        workspace.moneyLevel >= .finances ? .distantPast : DateText.calendar.date(byAdding: .day, value: -MoneyLevel.frontDeskDays, to: Date()) ?? Date()
    }
    private var yesterday: Date { DateText.calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date() }

    var body: some View {
        ProviderModal(
            title: LF("Charge %@", bill.invoiceNumber),
            subtitle: done == nil ? LF("%@ to collect", cashMoney(balance, bill.currency)) : nil,
            systemImage: "coins", accent: .pink, isDirty: done == nil && (earlier || tenders.paid != balance), form: form,
            primaryTitle: done != nil ? L("Done") : earlier ? L("Record the payment") : tenders.remaining > 0 && tenders.paid > 0 ? LF("Charge %@ · %@ stays owed", cashMoney(tenders.paid, bill.currency), cashMoney(tenders.remaining, bill.currency)) : LF("Charge %@", cashMoney(tenders.paid, bill.currency)),
            // Paid: the web's footer is only "Done".
            isWorking: working, cancelTitle: L("Back"), primaryIcon: done != nil ? nil : "banknote", showsCancel: done == nil
        ) {
            if done != nil { onSaved(); dismiss() } else if earlier { recordEarlier() } else { chargeToday() }
        } content: {
            // Who it is for (web `ModalContextPills`).
            ContextPills(client: walkIn ? (bill.customerName?.nonEmpty ?? L("Walk-in customer")) : bill.clientName, linked: walkIn ? nil : clientLinked, pets: bill.petName?.nonEmpty.map { [$0] } ?? [])
            if let done {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Glyph("circle-check", size: 20).foregroundStyle(ProviderState.done.color)
                        Text(LF("Paid %@", cashMoney(done.paid, bill.currency))).font(.brandHeading(20)).foregroundStyle(Theme.inkStrong)
                    }
                    if done.change > 0 {
                        Text(LF("Change to hand back: %@", cashMoney(done.change, bill.currency))).font(.brandHeading(24)).foregroundStyle(Theme.inkStrong)
                    }
                    Text(done.left > 0 ? LF("%@ still owed on %@.", cashMoney(done.left, bill.currency), bill.invoiceNumber) : LF("%@ is paid in full.", bill.invoiceNumber))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    // The receipt, ready (web `ReceiptReady`): where it went, its PDF, sending it now.
                    CashReceiptReady(documents: [CashReceiptDocument(id: bill.id, folio: bill.invoiceNumber)], emailedTo: done.emailedTo, clientEmail: clientEmail)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(ProviderState.done.color, 14), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            } else if balance <= 0 {
                Text(L("Nothing is owed on this bill any more.")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            } else {
                CashMoneyCells(cells: [
                    .init(label: L("Total"), value: cashMoney(CashBillRules.netTotal(bill), bill.currency)),
                    .init(label: L("Paid@amount"), value: cashMoney(bill.amountPaid, bill.currency), tone: bill.amountPaid == 0 ? .soft : .strong),
                    .init(label: L("Balance"), value: cashMoney(balance, bill.currency)),
                ])
                if earlier {
                    ModalSection(title: L("How much")) {
                        MoneyField(label: L("Amount"), cents: $amount, key: "amount", form: form)
                            .id(seed)
                    }
                    ModalSection(title: L("How they paid")) {
                        FlowLayout(spacing: 6) {
                            ForEach(["card", "bank_transfer", "digital_wallet", "other"], id: \.self) { option in
                                CashMethodPill(title: CashText.method(option), isOn: method == option) { method = option }
                            }
                        }
                        DateTimeField(label: L("Paid on"), date: $paidOn, min: firstDay, max: yesterday, components: [.date], key: "paidAt", form: form,
                                      hint: workspace.moneyLevel < .finances ? L("Up to 7 days back: older days need business finances.") : nil, required: true)
                        PMTextField(L("Reference"), text: $reference, prompt: L("Authorization or transfer number"))
                        Text(L("It is recorded on that day and stays out of today’s register shift. Cash is always recorded on the day it is taken."))
                            .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    }
                    ModalSection(title: L("Notes")) {
                        PMTextField(L("Notes"), text: $notes, prompt: L("Anything the team should know about this payment."), multiline: true)
                    }
                } else {
                    ModalSection(title: L("How they pay"), subtitle: L("Split it across methods, or take a part now: the rest stays owed on this bill.")) {
                        CashTendersView(state: tenders, registerOpen: registerOpen)
                        CashRegisterGate(device: device, wantsCash: tenders.wantsCash)
                    }
                }
                CashReceiptEmailField(clientEmail: clientEmail, automatic: true, email: $email, send: $sendReceipt)
                ToggleRow(title: L("It was paid on an earlier day"), subtitle: L("A transfer or a card payment that arrived before today."), isOn: $earlier)
            }
        }
        .modifier(CashKeepsRegister(device: device))
        .task {
            await device.load()
            if !walkIn {
                account = try? await API.get("/provider-finance/clients/\(bill.providerClientId)/account")
                if workspace.can(.clientsView) {
                    let client: PickedClient? = try? await API.get("/provider-clients/\(bill.providerClientId)")
                    clientEmail = client?.ownerEmail
                    clientLinked = client.map { $0.householdId != nil }
                }
            }
            tenders.start(total: balance, credit: account?.credit ?? 0, registerOpen: device.sessionId != nil, allowBalance: true, currency: bill.currency)
            amount = balance
            seed += 1
            paidOn = yesterday
        }
    }

    private func chargeToday() {
        if let problem = tenders.problem(registerOpen: registerOpen) { Toast.error(problem); return }
        let payments = tenders.payments()
        guard !payments.isEmpty else { Toast.error(L("Enter the amount paid.")); return }
        working = true
        Task {
            defer { working = false }
            do {
                var body: [String: Any?] = [
                    "clientRequestId": tenders.requestId,
                    "providerClientId": bill.providerClientId,
                    "providerClientPetId": bill.providerClientPetId,
                    "invoiceIds": [bill.id],
                    "lines": [Any](),
                    "ticketDiscount": nil,
                    "discountReason": nil,
                    "payments": payments,
                    "registerSessionId": device.sessionId,
                    "note": nil,
                ]
                body.merge(CashReceiptEmailField.delivery(clientEmail: clientEmail, typed: email, send: sendReceipt, canSave: !walkIn)) { _, new in new }
                let result: CashCheckoutResult = try await API.post("/provider-store/checkout", body: body)
                let left = result.invoices.first { $0.id == bill.id }?.balance ?? result.balanceLeft
                done = (result.paid, result.change, left, result.receipt?.emailedTo)
                NotificationCenter.default.post(name: CashDeviceRegister.changed, object: nil)
                announceDataChanged()
            } catch {
                Toast.error(error, fallback: L("Could not record this payment."))
            }
        }
    }

    private func recordEarlier() {
        let value = amount ?? 0
        guard form.check([
            ("amount", value <= 0 ? L("Enter the amount paid.") : value > balance ? LF("That is more than the %@ still owed.", cashMoney(balance, bill.currency)) : nil),
            ("paidAt", DateText.dayKey(paidOn) >= CashDay.today ? L("Choose a day before today — today’s payments are taken above.") : nil),
        ]) else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let updated: CashInvoice = try await API.post("/provider-invoices/\(bill.id)/payments", body: [
                    "amount": value,
                    "currency": bill.currency,
                    "method": method,
                    "reference": reference.nonEmpty,
                    "notes": notes.nonEmpty,
                    "paidAt": DateText.dayKey(paidOn),
                    "registerSessionId": nil,
                    "clientRequestId": requestId,
                ])
                done = (value, 0, updated.balanceDueAmount, updated.receiptEmailedTo)
                announceDataChanged()
            } catch {
                form.apply(error, known: ["amount": "amount", "paidAt": "paidAt"])
            }
        }
    }
}

// MARK: - Refund or credit note

struct CashRefundSheet: View {
    let bill: CashInvoice
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @StateObject private var device = CashDeviceRegister()
    @StateObject private var form = FormState()
    @State private var moneyBack = true
    @State private var amount: Int?
    @State private var method = "cash"
    @State private var reason = ""
    @State private var working = false
    @State private var seed = 0

    var body: some View {
        ProviderModal(title: LF("Refund on %@", bill.invoiceNumber), subtitle: LF("Paid %@ · owes %@", cashMoney(bill.amountPaid, bill.currency), cashMoney(bill.balanceDueAmount, bill.currency)), systemImage: "undo-2", accent: .pink, isDirty: !reason.isEmpty, form: form, primaryTitle: moneyBack ? L("Give money back") : L("Take it off the bill"), primaryVariant: .destructive, isWorking: working, cancelTitle: L("Back")) {
            submit()
        } content: {
            ChoiceCards(options: [
                (value: true, title: L("Money back"), subtitle: L("They get money back from what they paid.")),
                (value: false, title: L("Credit note"), subtitle: L("They owe less; nothing is handed back.")),
            ], selection: Binding(get: { moneyBack }, set: { next in
                if next && bill.amountPaid == 0 { return }
                if !next && bill.balanceDueAmount == 0 { return }
                moneyBack = next
                amount = next ? bill.amountPaid : bill.balanceDueAmount
                seed += 1
            }))
            MoneyField(label: L("Amount"), cents: $amount, key: "amount", form: form)
                .id(seed)
            if moneyBack {
                FlowLayout(spacing: 8) {
                    ForEach(CashText.methods, id: \.self) { option in
                        CashMethodPill(title: CashText.method(option), isOn: method == option) { method = option }
                    }
                }
                .accessibilityLabel(L("Method"))
                CashRegisterGate(device: device, wantsCash: method == "cash", giving: true)
            }
            CashReasonField(kind: .refund, text: $reason, form: form)
        }
        .modifier(CashKeepsRegister(device: device))
        .onAppear {
            moneyBack = bill.amountPaid > 0
            amount = moneyBack ? bill.amountPaid : bill.balanceDueAmount
            seed += 1
            let paidWith = bill.allPayments.last { !$0.isRefund && !$0.voided && $0.method != "credit" }?.method
            method = paidWith.flatMap { CashText.methods.contains($0) ? $0 : nil } ?? "cash"
        }
    }

    private func submit() {
        let value = amount ?? 0
        guard form.check([
            ("amount", value <= 0 ? L("Enter the amount") : nil),
            ("reason", reason.nonEmpty == nil ? CashReasonKind.refund.required : nil),
        ]) else { return }
        if moneyBack && method == "cash" && device.sessionId == nil {
            Toast.error(L("Open the register to give cash back"))
            return
        }
        working = true
        Task {
            defer { working = false }
            do {
                struct Done: Decodable { let id: String }
                let _: Done = try await API.post("/provider-finance/invoices/\(bill.id)/refund", body: [
                    "amount": value,
                    "moneyBack": moneyBack,
                    "method": moneyBack ? method : nil,
                    "reason": reason.nonEmpty,
                    "registerSessionId": moneyBack ? device.sessionId : nil,
                ])
                Toast.show(moneyBack ? LF("%@ given back.", cashMoney(value, bill.currency)) : LF("%@ taken off the bill.", cashMoney(value, bill.currency)))
                NotificationCenter.default.post(name: CashDeviceRegister.changed, object: nil)
                announceDataChanged()
                onDone()
                dismiss()
            } catch {
                if cashAsksReason(error) { _ = form.check([("reason", errorText(error))]) } else { form.apply(error, known: ["amount": "amount", "reason": "reason"]) }
            }
        }
    }
}

// MARK: - Email the receipt

struct CashSendReceiptSheet: View {
    let bill: CashInvoice
    let clientEmail: String?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var email = ""
    @State private var working = false

    var body: some View {
        ProviderModal(title: L("Email the receipt"), subtitle: bill.invoiceNumber, systemImage: "mail", accent: .aqua, isDirty: email != (clientEmail ?? ""), form: form, primaryTitle: L("Send"), isWorking: working, primaryIcon: "send") {
            send()
        } content: {
            PMTextField(L("Email for the receipt"), text: $email, key: "email", form: form, prompt: L("name@example.com"), keyboard: .emailAddress)
            if clientEmail?.nonEmpty == nil && !CashBillRules.isWalkIn(bill) {
                Text(L("This client has no email: the one you write is saved on the client.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
        .presentationDetents([.medium])
        .onAppear { email = clientEmail ?? "" }
    }

    private func send() {
        let to = email.trimmingCharacters(in: .whitespaces)
        let valid = to.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
        guard form.check([("email", valid ? nil : L("That email doesn’t look right."))]) else { return }
        working = true
        Task {
            defer { working = false }
            do {
                struct Sent: Decodable { let sentTo: String }
                let sent: Sent = try await API.post("/provider-invoices/\(bill.id)/send-receipt", body: ["email": to, "save": clientEmail?.nonEmpty == nil && !CashBillRules.isWalkIn(bill)])
                Toast.show(LF("Receipt sent to %@.", sent.sentTo))
                dismiss()
            } catch {
                form.apply(error, known: ["email": "email"])
            }
        }
    }
}
