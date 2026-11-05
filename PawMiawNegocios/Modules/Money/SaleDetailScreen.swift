//
//  SaleDetailScreen.swift
//  PawMiawNegocios
//
//  One counter sale (web: store-sales.tsx SaleDetailSheet, store-receipt.tsx):
//  its receipt, its returns, and what can be done with it — a return (back on
//  the shelf or written off, the money back the way it came) or a cancel for
//  a sale made by mistake. Both need their reason (docs/money-access-levels.md).
//  A page here: the web sheet's header (Receipt, "Sale F-0001", what is still
//  due) and its footer's actions as the header's buttons.
//

import SwiftUI

struct SaleDetailScreen: View {
    let saleId: String
    @EnvironmentObject private var workspace: Workspace
    @StateObject private var loader: Loader<CashSale>
    @State private var footer: String?
    @State private var returning = false
    @State private var canceling = false

    init(saleId: String) {
        self.saleId = saleId
        _loader = StateObject(wrappedValue: Loader<CashSale> { try await API.get("/provider-store/sales/\(saleId)") })
    }

    private var title: String { loader.value.map { LF("Sale %@", $0.folio) } ?? L("Sale") }

    var body: some View {
        PageScroll(refresh: { await loader.load() }) {
            if let sale = loader.value {
                header(sale)
                content(sale)
            } else {
                ModuleHeader(icon: "receipt", title: title, accent: Theme.aqua, storageKey: "sale")
                LoadedContent(loader: loader) { _ in EmptyView() }
            }
        }
        .providerPage(title)
        .reloadsOnScope {
            await loader.load()
            let settings: CashStoreSettings? = try? await API.get("/provider-store/settings")
            footer = settings?.receiptFooter
        }
        .sheet(isPresented: $returning) {
            if let sale = loader.value { CashReturnSheet(sale: sale) { await loader.load() } }
        }
        .sheet(isPresented: $canceling) {
            if let sale = loader.value {
                ConfirmSheet(
                    title: LF("Cancel %@?", sale.folio),
                    message: L("For a sale made by mistake: everything goes back on the shelf and its payments are voided. Cash can only be undone while its register is open — after that, make a return."),
                    confirmTitle: L("Cancel sale"), destructive: true, askReason: true, reasonRequired: true,
                    reasonLabel: CashReasonKind.cancel.label, cancelTitle: L("Keep it"), confirmIcon: "ban"
                ) { reason in
                    let _: EmptyResponse = try await API.post("/provider-store/sales/\(sale.id)/cancel", body: ["reason": reason])
                    Toast.show(LF("Sale %@ canceled. Stock is back and its payments voided.", sale.folio))
                    NotificationCenter.default.post(name: CashDeviceRegister.changed, object: nil)
                    announceDataChanged()
                    await loader.load()
                }
            }
        }
    }

    // MARK: Header

    private func header(_ sale: CashSale) -> some View {
        let canRefund = workspace.can(.salesRefund) && sale.status != "canceled"
        // Returns are for counter sales: a visit's or a stay's bill is refunded from the bill.
        let returnable = sale.kind != "invoice" && sale.status != "draft" && sale.lines.contains { $0.quantity > $0.returnedQuantity }
        let cancelable = sale.returns.isEmpty
        return ModuleHeader(
            icon: "receipt",
            title: LF("Sale %@", sale.folio),
            subtitle: sale.balanceDueAmount > 0 ? LF("%@ still due", cashMoney(sale.balanceDueAmount, sale.currency)) : CashDay.when(sale.createdAt),
            accent: Theme.aqua,
            storageKey: "sale"
        ) {
            DocumentButton(title: L("Download PDF"), systemImage: "file-down", path: "/provider-store/sales/\(sale.id)/pdf", fileName: sale.folio)
            if canRefund && cancelable {
                PMButton(L("Cancel sale"), systemImage: "ban", variant: .destructive) { canceling = true }
            }
            if canRefund && returnable {
                PMButton(L("Return items"), systemImage: "undo-2") { returning = true }
            }
        }
    }

    // MARK: Content

    @ViewBuilder private func content(_ sale: CashSale) -> some View {
        if let reason = sale.cancelReason?.nonEmpty {
            NoticeCard(tone: .problem, title: L("Canceled@sale"), message: "“\(reason)”" + (sale.canceledAt.map { " · " + CashDay.when($0) } ?? ""))
        }
        CashReceiptView(sale: sale, footer: footer)
        if !sale.returns.isEmpty {
            VStack(spacing: 8) {
                ForEach(sale.returns) { entry in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(L("Return")) \(entry.folio)").font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            Text([entry.refundAmount > 0 ? "−\(cashMoney(entry.refundAmount, sale.currency))" : L("credited"), entry.reason, entry.createdAt.map { CashDay.when($0) }].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        DocumentButton(title: "PDF", systemImage: "file-down", path: "/provider-store/sales/\(sale.id)/returns/\(entry.id)/pdf", fileName: entry.folio)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
            }
            .frame(maxWidth: 352)
            .frame(maxWidth: .infinity)
        }
        if let clientId = sale.providerClientId, !sale.walkIn, workspace.can(.clientsView) {
            NavigationLink(value: ProviderRoute.client(clientId)) {
                HStack(spacing: 6) {
                    Glyph("user-round", size: 16)
                    Text(L("Open client"))
                }
            }
            .buttonStyle(.pm(.outline, size: .compact))
            .frame(maxWidth: .infinity)
        }
    }
}

/// A sale as a ticket (web `StoreReceipt`): what was bought, the tax inside
/// it, how it was paid and what came back, in the receipt's fixed-width type.
struct CashReceiptView: View {
    let sale: CashSale
    var footer: String? = nil
    @EnvironmentObject private var workspace: Workspace

    var body: some View {
        let currency = sale.currency
        let payments = sale.payments.filter { $0.kind == "payment" && $0.voidedAt == nil }
        let rates = Array(Set(sale.lines.filter { ($0.taxAmount ?? 0) > 0 }.compactMap(\.taxRateBps))).sorted().map(cashRate).joined(separator: ", ")
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 2) {
                Text(workspace.current?.name ?? "").font(.brandHeading(18)).multilineTextAlignment(.center)
                if let phone = workspace.current?.phone?.nonEmpty { Text(phone).foregroundStyle(Theme.inkSoft) }
                Text(sale.folio).font(Theme.text(14, weight: .bold)).tracking(0.35).padding(.top, 8)
                Text(CashDay.when(sale.createdAt)).foregroundStyle(Theme.inkSoft)
                if sale.status == "canceled" {
                    Text(L("Canceled@sale"))
                        .font(Theme.text(12, weight: .bold))
                        .foregroundStyle(Theme.inkOnBright)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                        .background(Theme.pink, in: Capsule())
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
            if sale.walkIn || sale.customerName != nil || sale.petName != nil || sale.cashierName != nil {
                section {
                    if sale.walkIn || sale.customerName != nil {
                        Text("\(L("Customer")): \(sale.walkIn ? (sale.customerName ?? L("Walk-in customer")) : (sale.customerName ?? ""))")
                    }
                    if let pet = sale.petName { Text("\(L("Pet")): \(pet)") }
                    if let cashier = sale.cashierName { Text("\(L("Served by")): \(cashier)") }
                }
            }
            section(spacing: 8) {
                ForEach(sale.lines) { line in
                    VStack(alignment: .leading, spacing: 0) {
                        row("\(line.quantity) × \(line.label)", cashMoney(line.quantity * line.unitAmount, currency))
                        if line.quantity > 1 { detail(LF("%@ each", cashMoney(line.unitAmount, currency))) }
                        if let discount = line.discountAmount, discount > 0 { row("  \(L("Discount"))", "−\(cashMoney(discount, currency))", muted: true) }
                        if let folio = line.prescriptionFolio { detail(LF("Prescription %@", folio)) }
                        ForEach(Array((line.lots ?? []).enumerated()), id: \.offset) { _, lot in
                            detail("\(L("Lot")) \(lot.lotCode ?? "—")" + (lot.expiresOn.map { " · \(L("exp.")) \(CashDay.short($0))" } ?? "") + ((line.lots?.count ?? 0) > 1 ? " · \(lot.quantity ?? 0)" : ""))
                        }
                        if line.returnedQuantity > 0 { detail(LP(line.returnedQuantity, "%d returned", "%d returned")) }
                    }
                }
            }
            section {
                if sale.discountAmount > 0 { row(L("Discounts"), "−\(cashMoney(sale.discountAmount, currency))") }
                row(L("Total"), cashMoney(sale.totalAmount, currency), strong: true)
                if sale.taxAmount > 0 {
                    row(sale.pricesIncludeTax == true ? LF("Tax included (%@)", rates) : LF("Tax (%@)", rates), cashMoney(sale.taxAmount, currency))
                }
            }
            section {
                ForEach(payments) { payment in
                    row(CashText.method(payment.method), cashMoney(payment.amount, currency))
                    if let tendered = payment.tenderedAmount, let change = payment.changeAmount, change > 0 {
                        row("  \(L("Handed over"))", cashMoney(tendered, currency), muted: true)
                        row("  \(L("Change"))", cashMoney(change, currency), muted: true)
                    }
                    if let reference = payment.reference?.nonEmpty { detail("\(L("Ref.")) \(reference)") }
                }
                ForEach(sale.returns) { entry in
                    row("\(L("Return")) \(entry.folio)", entry.refundAmount > 0 ? "−\(cashMoney(entry.refundAmount, currency))" : L("credited"), muted: true)
                }
                if sale.balanceDueAmount > 0 { row(L("Balance due"), cashMoney(sale.balanceDueAmount, currency), strong: true) }
            }
            if let footer = footer?.nonEmpty {
                section {
                    Text(footer).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
            }
        }
        .font(Theme.text(12.8))
        .monospaced()
        .foregroundStyle(Theme.inkStrong)
        .padding(20)
        .frame(maxWidth: 352)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        .frame(maxWidth: .infinity)
    }

    /// A part of the ticket under a dashed rule.
    private func section<Content: View>(spacing: CGFloat = 4, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StitchedDivider()
            VStack(alignment: .leading, spacing: spacing) { content() }
        }
    }

    private func row(_ label: String, _ value: String, strong: Bool = false, muted: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
            Spacer(minLength: 8)
            Text(value)
        }
        .font(strong ? Theme.text(14, weight: .bold) : Theme.text(12.8))
        .foregroundStyle(muted ? Theme.inkSoft : Theme.inkStrong)
    }

    private func detail(_ text: String) -> some View {
        Text("  " + text).foregroundStyle(Theme.inkSoft)
    }
}

/// A return from a counter sale (web `ReturnSheet`): what comes back, whether
/// it goes back on the shelf, how the money goes back (the way it came unless
/// said otherwise), and why.
struct CashReturnSheet: View {
    let sale: CashSale
    let onDone: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var device = CashDeviceRegister()
    @StateObject private var form = FormState()
    @State private var quantities: [String: Int] = [:]
    @State private var restock: [String: Bool] = [:]
    @State private var method = "cash"
    @State private var reference = ""
    @State private var reason = ""
    @State private var working = false

    private var paidBy: String { sale.payments.first { $0.kind == "payment" && $0.voidedAt == nil }?.method ?? "cash" }
    /// Credit on account only for a client ("Público en general" has no account).
    private var methods: [String] { sale.walkIn ? CashText.methods : CashText.methods + ["credit"] }
    private var lines: [CashSaleLine] { sale.lines.filter { $0.quantity > $0.returnedQuantity } }
    /// What the units coming back are worth, as the server works it out.
    private var value: Int {
        lines.reduce(0) { sum, line in
            let count = quantities[line.id] ?? 0
            guard count > 0, line.quantity > 0 else { return sum }
            let before = Int((Double(line.totalAmount * line.returnedQuantity) / Double(line.quantity)).rounded())
            let after = Int((Double(line.totalAmount * (line.returnedQuantity + count)) / Double(line.quantity)).rounded())
            return sum + after - before
        }
    }
    private var refund: Int {
        let owedAfter = max(0, sale.totalAmount - sale.returnedAmount - value)
        return max(0, min(value, sale.amountPaid - owedAfter))
    }
    private var chosen: [(String, Int)] { quantities.filter { $0.value > 0 }.map { ($0.key, $0.value) } }

    var body: some View {
        ProviderModal(title: LF("Return from %@", sale.folio), subtitle: L("Each item comes back at what was paid for it. Opened medicine does not go back on the shelf."), systemImage: "rotate-ccw", accent: .aqua, isDirty: !chosen.isEmpty || !reason.isEmpty, form: form, primaryTitle: refund > 0 ? LF("Refund %@", cashMoney(refund, sale.currency)) : L("Take the return"), isWorking: working, cancelTitle: L("Back"), primaryIcon: "undo-2") {
            submit()
        } content: {
            if !sale.walkIn, let name = sale.customerName {
                CashContextPills(client: name, pets: sale.petName.map { [$0] } ?? [])
            }
            ModalSection(title: L("What comes back")) {
                VStack(spacing: 8) {
                    ForEach(lines) { line in lineRow(line) }
                }
                if let error = form.error("lines") { Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
            }
            .id("lines")
            if refund > 0 {
                ModalSection(title: LF("Refund %@ by", cashMoney(refund, sale.currency))) {
                    FlowLayout(spacing: 8) {
                        ForEach(methods, id: \.self) { option in
                            CashMethodPill(title: CashText.method(option), isOn: method == option) { method = option; form.clear("method") }
                        }
                    }
                    if method != paidBy {
                        Text(LF("It was paid by %@: giving it back another way goes on the day’s exceptions.", CashText.method(paidBy).lowercased()))
                            .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    }
                    if let error = form.error("method") { Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
                    if method != "cash" && method != "credit" {
                        PMTextField(L("Terminal reference (optional)"), text: $reference, optional: true)
                    }
                    CashRegisterGate(device: device, wantsCash: method == "cash", giving: true)
                }
                .id("method")
            } else if value > 0 {
                Text(L("Nothing to give back: it comes off what the client still owes."))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            }
            ModalSection(title: L("Why")) {
                CashReasonField(kind: .return, text: $reason, form: form)
            }
        }
        .modifier(CashKeepsRegister(device: device))
        .onAppear {
            restock = Dictionary(uniqueKeysWithValues: sale.lines.map { ($0.id, $0.itemType == "product") })
            method = paidBy
        }
    }

    private func lineRow(_ line: CashSaleLine) -> some View {
        let left = line.quantity - line.returnedQuantity
        let count = quantities[line.id] ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.label).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text(LP(left, "%d can come back", "%d can come back")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 8)
                CashQuantityStepper(quantity: count, lessDisabled: count <= 0, moreDisabled: count >= left,
                                    less: { quantities[line.id] = max(0, count - 1); form.clear("lines") },
                                    more: { quantities[line.id] = min(left, count + 1); form.clear("lines") })
            }
            // Only what was counted out of the stock can go back into it.
            if count > 0 && line.itemType == "product" && line.tracksStock != false {
                ToggleRow(title: L("Goes back on the shelf"), subtitle: (restock[line.id] ?? true) ? L("It returns to stock, to be sold again.") : L("Written off (opened or damaged)"), isOn: Binding(get: { restock[line.id] ?? true }, set: { restock[line.id] = $0 }))
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(count > 0 ? Theme.blue : Theme.borderSoft, lineWidth: 2))
    }

    private func submit() {
        guard form.check([
            ("lines", chosen.isEmpty ? L("Choose what is coming back.") : nil),
            ("method", method == "cash" && refund > 0 && device.sessionId == nil ? L("Open the register to give cash back") : nil),
            ("reason", reason.nonEmpty == nil ? CashReasonKind.return.required : nil),
        ]) else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let body: [String: Any?] = [
                    "lines": chosen.map { ["lineItemId": $0.0, "quantity": $0.1, "restock": restock[$0.0] ?? true] as [String: Any] },
                    "refundMethod": method,
                    "reference": reference.nonEmpty,
                    "reason": reason.nonEmpty,
                    "registerSessionId": device.sessionId,
                ]
                let _: EmptyResponse = try await API.post("/provider-store/sales/\(sale.id)/returns", body: body)
                Toast.show(refund <= 0 ? L("Return done. It came off the balance.")
                    : method == "cash" ? LF("Return done. Give back %@.", cashMoney(refund, sale.currency))
                    : method == "credit" ? LF("Return done. %@ stays as credit on the account.", cashMoney(refund, sale.currency))
                    : LF("Return recorded. Refund %@ by %@.", cashMoney(refund, sale.currency), CashText.method(method).lowercased()))
                NotificationCenter.default.post(name: CashDeviceRegister.changed, object: nil)
                announceDataChanged()
                await onDone()
                dismiss()
            } catch {
                if cashAsksReason(error) {
                    _ = form.check([("reason", errorText(error))])
                } else if cashErrorCode(error) == "not_enough_cash" {
                    _ = form.check([("method", errorText(error))])
                } else {
                    form.apply(error, known: ["reason": "reason"])
                }
            }
        }
    }
}
