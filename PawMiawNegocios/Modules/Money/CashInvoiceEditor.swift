//
//  CashInvoiceEditor.swift
//  PawMiawNegocios
//
//  A bill made or changed by hand (web: provider-invoice-sheet.tsx,
//  invoices-page/invoice-editor-model.ts, bill-item-search.tsx): who it is
//  for, what it charges (from the catalog or typed), its discount and date,
//  its notes and where it goes (charge now, pay later, keep as a draft).
//  A courtesy or a price below the catalog's, and a discount of 10 % or more,
//  need their reason. Tax is the server's, line by line. A prescription-only
//  product's line chooses the pet's prescription it is dispensed against; when
//  the server asks for one the editor finds which lines need it.
//

import SwiftUI

private struct CashLineDraft: Identifiable, Equatable {
    struct Saved: Equatable { let unit: Int; let courtesy: Bool; let catalogId: String?; let reason: String? }
    let key: String
    var id: String?
    var catalogId: String?
    var itemType: String
    var label: String
    var description: String
    var quantity: Int?
    var unitAmount: Int?
    var sourceType: String?
    var sourceId: String?
    var courtesy: Bool
    var prescriptionItemId: String?
    var keepsPrescription: Bool
    /// A prescription-only (or controlled) product: the line picks the pet's prescription.
    var needsPrescription: Bool = false
    var listUnitAmount: Int?
    var reason: String
    var saved: Saved?

    var unit: Int { unitAmount ?? 0 }
    var total: Int { max(0, quantity ?? 0) * unit }
    var unpriced: Bool { unit <= 0 && !courtesy }

    /// Why this line needs a reason now: given free on purpose, or priced below the catalog's — when that is new.
    var reasonKind: CashReasonKind? {
        let free = courtesy && unit <= 0
        let kind: CashReasonKind? = free ? .courtesy : (listUnitAmount.map { unit > 0 && unit < $0 } == true ? .priceLowered : nil)
        guard let kind else { return nil }
        if let saved, saved.catalogId == catalogId, saved.unit == unit, saved.courtesy == free { return nil }
        return kind
    }

    var reasonTyped: Bool { reason.nonEmpty != nil && reason.nonEmpty != saved?.reason?.nonEmpty }

    static func empty(_ type: String = "service") -> CashLineDraft {
        CashLineDraft(key: UUID().uuidString, id: nil, catalogId: nil, itemType: type, label: "", description: "", quantity: 1, unitAmount: nil, sourceType: nil, sourceId: nil, courtesy: false, prescriptionItemId: nil, keepsPrescription: false, listUnitAmount: nil, reason: "", saved: nil)
    }

    static func from(_ line: CashInvoiceLine, copy: Bool) -> CashLineDraft {
        let needs = (line.requiresPrescription ?? false) || line.controlSchedule != nil
        if copy {
            return CashLineDraft(key: UUID().uuidString, id: nil, catalogId: line.providerCatalogItemId, itemType: line.itemType, label: line.label, description: line.description ?? "", quantity: line.quantity, unitAmount: line.unitAmount > 0 ? line.unitAmount : nil, sourceType: nil, sourceId: nil, courtesy: line.courtesy ?? false, prescriptionItemId: nil, keepsPrescription: false, needsPrescription: needs, listUnitAmount: line.catalogItem?.defaultUnitAmount ?? line.listUnitAmount, reason: "", saved: nil)
        }
        return CashLineDraft(key: line.id, id: line.id, catalogId: line.providerCatalogItemId, itemType: line.itemType, label: line.label, description: line.description ?? "", quantity: line.quantity, unitAmount: line.unitAmount > 0 || line.courtesy == true ? line.unitAmount : nil, sourceType: line.sourceType, sourceId: line.sourceId, courtesy: line.courtesy ?? false, prescriptionItemId: line.prescriptionItemId, keepsPrescription: true, needsPrescription: needs, listUnitAmount: line.listUnitAmount, reason: line.adjustmentReason ?? "",
                             saved: Saved(unit: line.unitAmount, courtesy: (line.courtesy ?? false) && line.unitAmount <= 0, catalogId: line.providerCatalogItemId, reason: line.adjustmentReason))
    }

    func payload(_ index: Int) -> [String: Any?] {
        var entry: [String: Any?] = [
            "providerCatalogItemId": catalogId,
            "itemType": itemType,
            "label": label.trimmingCharacters(in: .whitespacesAndNewlines),
            "description": description.nonEmpty,
            "quantity": quantity ?? 1,
            "unitAmount": unit,
            "sortOrder": index,
            "sourceType": sourceType,
            "sourceId": sourceId,
            "courtesy": courtesy && unit == 0,
        ]
        if let id { entry["id"] = id }
        if !keepsPrescription || prescriptionItemId != nil || needsPrescription { entry["prescriptionItemId"] = prescriptionItemId }
        if reasonKind != nil || reasonTyped { entry["adjustmentReason"] = reason.nonEmpty }
        return entry
    }
}

/// A service or product found for a bill line.
private struct CashFoundItem: Identifiable, Hashable {
    let id: String
    let itemType: String
    let name: String
    let unitAmount: Int
    let needsPrescription: Bool
    var sku: String? = nil
    /// Units on the shelf, for a tracked product.
    var available: Int? = nil
}

struct CashInvoiceEditorSheet: View {
    let bill: CashInvoice?
    let template: CashInvoice?
    /// The saved bill, and whether to go straight to taking its payment.
    let onSaved: (CashInvoice, Bool) -> Void
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var client: PickedClient?
    @State private var petId: String?
    @State private var lines: [CashLineDraft] = []
    @State private var discount: Int?
    @State private var discountReason = ""
    @State private var billingNote = ""
    @State private var notes = ""
    @State private var issuedAt = Date()
    @State private var dueAt = Date()
    @State private var destination = "draft"
    @State private var search = ""
    @State private var found: [CashFoundItem] = []
    @State private var foundTotal: Int?
    @State private var foundMore = false
    @State private var finding = false
    @State private var searchFailed = false
    @State private var shownFound = CashInvoiceEditorSheet.pageSize
    @State private var working = false
    @State private var changed = false
    @State private var loaded = false
    @State private var step: Step = .who

    /// The web's three steps: who it is for, the bill, where it goes.
    enum Step { case who, bill, next }
    private static let pageSize = ClientSearch.pageSize

    private var isEdit: Bool { bill != nil }
    private var canDiscount: Bool { workspace.can(.billingApplyDiscount) }
    private var canPay: Bool { workspace.can(.billingRecordPayment) }
    private var clientLocked: Bool { bill.map { $0.amountPaid > 0 || $0.refunded > 0 } ?? false }
    private var dateLocked: Bool { bill.map { $0.status != "draft" } ?? false }
    /// A visit's, a stay's or the hospital's bill keeps its client, and so does one money moved on.
    private var canChangeWho: Bool { bill.map { CashBillRules.kind($0) == "other" && !clientLocked } ?? true }
    /// Money already on it settles its status by itself.
    private var statusSettled: Bool { bill.map { !["draft", "ready_for_payment", "open"].contains($0.status) } ?? false }
    /// Where it goes is asked of whoever may take a bill out of draft, while its status isn't settled.
    private var asksDestination: Bool { workspace.can(.billingFinalizeInvoice) && !statusSettled }
    private var steps: [Step] { (canChangeWho ? [.who] : []) + [.bill] + (asksDestination ? [.next] : []) }
    private var stepIndex: Int { steps.firstIndex(of: step) ?? 0 }
    private var lastStep: Step { steps.last ?? .bill }
    private var subtotal: Int { lines.reduce(0) { $0 + $1.total } }
    private var total: Int { max(0, subtotal - (discount ?? 0)) }
    private var unpriced: Int { lines.filter(\.unpriced).count }
    private var chargeable: Bool { !lines.isEmpty && unpriced == 0 && total > 0 }
    private var discountNeedsReason: Bool { cashDiscountNeedsReason(discount ?? 0, of: subtotal) }

    var body: some View {
        ProviderModal(
            title: !isEdit ? (template != nil ? L("Bill again") : L("New bill")) : bill?.status == "draft" ? L("Finish the bill") : L("Edit the bill"),
            subtitle: !isEdit ? L("A bill made by hand, for what isn’t a visit, a stay or a counter sale.") : LF("%@ · what it charges, its discount and where it goes.", bill?.invoiceNumber ?? ""),
            systemImage: "file-text", accent: .aqua, isDirty: changed, form: form,
            primaryTitle: primaryTitle, isWorking: working,
            steps: steps.count > 1 ? ModalSteps(steps: steps.map(stepName), current: stepIndex) : nil,
            onBack: stepIndex > 0 ? { step = steps[stepIndex - 1] } : nil,
            onPrimary: { next() }
        ) {
            if !loaded {
                LoadingState(text: L("Loading the bill…"))
            } else {
                if step != .who, let name = client?.name.nonEmpty ?? bill?.clientName {
                    ContextPills(client: name, linked: client.map { $0.householdId != nil }, pets: petName.map { [$0] } ?? [])
                }
                switch step {
                case .who: whoStep
                case .bill: billStep
                case .next: destinationStep
                }
            }
        }
        .task { await start() }
        .task(id: "\(ClientSearch.query(search) ?? "")|\(step == .bill)") {
            // From two letters, 250 ms after typing stops; under that nothing is searched.
            guard step == .bill, let query = ClientSearch.query(search) else { found = []; foundTotal = nil; foundMore = false; searchFailed = false; return }
            try? await Task.sleep(for: ClientSearch.debounce)
            guard !Task.isCancelled else { return }
            await find(query, reset: true)
        }
    }

    private func stepName(_ entry: Step) -> (title: String, icon: String) {
        switch entry {
        case .who: (L("Client and pet"), "user-round")
        case .bill: (L("The bill"), "file-text")
        case .next: (L("Where it goes"), "circle-dollar-sign")
        }
    }

    private var petName: String? {
        guard let petId else { return nil }
        return client?.activePets.first { $0.id == petId }?.name.nonEmpty ?? (petId == bill?.providerClientPetId ? bill?.petName : nil)
    }

    private var primaryTitle: String {
        guard step == lastStep else { return L("Continue") }
        guard asksDestination else { return statusSettled ? L("Save the bill") : L("Save as a draft") }
        switch destination {
        case "ready_for_payment": return canPay ? L("Save and charge") : L("Save and send to the desk")
        case "open": return L("Save to pay later")
        default: return L("Save as a draft")
        }
    }

    // MARK: Step 1: who

    @ViewBuilder private var whoStep: some View {
        ClientPetPicker(client: Binding(get: { client }, set: { next in
            // A prescription belongs to a pet: another client's lines choose theirs again.
            if next?.id != client?.id { clearPrescriptions() }
            client = next
            changed = true
        }), petIds: Binding(get: { petId.map { [$0] } ?? [] }, set: { ids in
            let next = ids.first
            if next != petId { clearPrescriptions() }
            petId = next
            changed = true
        }), form: form, petHint: L("Leave the pet out for a charge that isn’t for one in particular."))
    }

    // MARK: Step 2: the bill

    @ViewBuilder private var billStep: some View {
        ModalSection(title: L("What it charges"), systemImage: "file-text", tint: Theme.aqua) {
            VStack(alignment: .leading, spacing: 12) {
                if lines.isEmpty {
                    Text(L("Nothing on the bill yet. Find a service or product below, or type a line by hand."))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 12).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                }
                ForEach($lines) { $line in lineEditor($line) }
                itemSearch
                if let error = form.error("lines") { Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
            }
        }
        .id("lines")
        ModalSection(title: L("Discount and total"), systemImage: "circle-dollar-sign", tint: Theme.butter) {
            if canDiscount {
                MoneyField(label: L("Discount"), cents: Binding(get: { discount }, set: { discount = $0; changed = true }), key: "discount", form: form)
                if discountNeedsReason { CashReasonField(kind: .discount, text: $discountReason, key: "discountReason", form: form) }
            } else if (discount ?? 0) > 0 {
                FactRow(label: L("Discount"), value: cashMoney(discount))
                Text(L("You can see the discount here, but your role cannot change it.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
            if dateLocked {
                FactRow(label: L("Bill date"), value: DateText.date(issuedAt))
                Text(L("Fixed once the bill left draft: it is the day its money counts.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            } else {
                DateTimeField(label: L("Bill date"), date: Binding(get: { issuedAt }, set: { issuedAt = $0; changed = true }), components: [.date], key: "issuedAt", form: form, required: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                CashBillTotalRow(label: L("Subtotal"), value: cashMoney(subtotal))
                if (discount ?? 0) > 0 { CashBillTotalRow(label: L("Discount"), value: "−\(cashMoney(discount))") }
                CashBillTotalRow(label: L("Before tax"), value: cashMoney(total), strong: true)
                if let bill, bill.refunded > 0 { CashBillTotalRow(label: L("Refunded or credited"), value: "−\(cashMoney(bill.refunded))") }
                if let bill, bill.amountPaid > 0 { CashBillTotalRow(label: L("Paid@amount"), value: cashMoney(bill.amountPaid)) }
                Text(L("Tax is added line by line when it is saved, at each item’s rate.") + " " + LF("In %@, the business currency.", workspace.currency) + (unpriced > 0 ? " " + LP(unpriced, "%d line still needs a price.", "%d lines still need a price.") : ""))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        }
        ModalSection(title: L("Notes"), systemImage: "file-text", tint: Theme.surfaceMuted) {
            PMTextField(L("Billing note"), text: $billingNote, prompt: L("For the desk: what to check, how to follow up."), multiline: true)
            PMTextField(L("Internal notes"), text: $notes, prompt: L("Anything the clinic should keep on the bill itself."), multiline: true)
            Text(L("Neither note is printed on the client’s receipt.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
    }

    // MARK: Step 3: where it goes

    @ViewBuilder private var destinationStep: some View {
        // The question with its red mark, what it comes to, then the three ways (web `OptionCardGrid`).
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel(L("Where does this bill go?"), required: true)
            Text(LF("%@ before tax for %@.", cashMoney(total), client?.name.nonEmpty ?? bill?.clientName ?? "") + " " + L("Once it leaves draft, its products leave the shelf and its medicines count against their prescription."))
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        OptionCards(options: destinationOptions, selection: Binding(get: { destination }, set: { next in
            destination = next
            form.clear("dueAt")
            changed = true
        }))
        if destination == "open" {
            // The family's receipt says it, and they are reminded the day before (docs/family-money.md §3).
            DateTimeField(label: L("Pay by"), date: $dueAt, min: issuedAt, components: [.date], key: "dueAt", form: form, hint: L("The family sees this date and is reminded the day before."), required: true)
        }
    }

    /// Finding what to put on the bill (web `BillItemSearch`): a dashed box with the
    /// search (scan too, for whoever sells), "Type a line by hand", and what was found.
    private var itemSearch: some View {
        VStack(alignment: .leading, spacing: 8) {
            if workspace.can(.salesSell) {
                // What the Store sells can be scanned: the code goes in the search.
                BarcodeSearchField(prompt: L("Service or product: name, SKU or barcode"), text: $search, onScan: { scan in search = scan.code })
            } else {
                SearchField(prompt: L("Service or product: name or SKU"), text: $search)
            }
            PMButton(L("Type a line by hand"), systemImage: "pen-line", variant: .outline, fullWidth: true) {
                lines.append(.empty())
                changed = true
                form.clear("lines")
            }
            if ClientSearch.query(search) != nil {
                if searchFailed {
                    Text(L("The search didn’t answer. Try again, or type the line by hand."))
                        .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.destructive).padding(.horizontal, 4).padding(.vertical, 8)
                } else if found.isEmpty && !finding {
                    Text(L("Nothing in the catalog matches. Type the line by hand, or add it to the Catalog first."))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.horizontal, 4).padding(.vertical, 8)
                } else if !found.isEmpty {
                    let count = foundTotal ?? found.count
                    Eyebrow(count == 1 ? LF("%@ result", "1") : LF("%@ results", String(count)))
                    let shown = Array(found.prefix(shownFound))
                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { RowDivider() }
                            Button { addFound(item) } label: { foundRow(item) }.buttonStyle(.plain)
                                .onAppear { if item.id == shown.last?.id { Task { await more() } } }
                        }
                        LoadMoreRow(hasMore: found.count > shownFound || foundMore, busy: finding) { Task { await more() } }
                    }
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    private func foundRow(_ item: CashFoundItem) -> some View {
        let details: [String?] = [
            item.itemType == "product" ? L("Product") : L("Service"),
            item.sku?.nonEmpty,
            item.available.map { LP($0, "%d on the shelf", "%d on the shelf") },
            item.needsPrescription ? L("Needs a prescription") : nil,
        ]
        return HStack(spacing: 12) {
            Glyph(item.itemType == "product" ? "package" : "briefcase-medical", size: 16)
                .foregroundStyle(Theme.inkStrong)
                .frame(width: 32, height: 32)
                .background(Theme.wash(Theme.aqua, 22), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                Text(details.compactMap { $0 }.joined(separator: " · ")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(item.unitAmount > 0 ? cashMoney(item.unitAmount) : L("No price")).font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    /// The three ways (web `destinationOptions`): charging and paying later need a priced bill with something to charge.
    private var destinationOptions: [OptionCard<String>] {
        let unavailable: String? = chargeable ? nil : unpriced > 0 ? L("A line still needs a price.") : L("There is nothing to charge yet.")
        return [
            OptionCard("ready_for_payment", title: canPay ? L("Charge it now") : L("Send to the desk"), description: canPay ? L("Save the bill and go straight to taking the payment.") : L("Save it ready for the desk to charge."),
                       icon: canPay ? "coins" : "send", accent: Theme.pink, unavailableReason: unavailable),
            OptionCard("open", title: L("Pay later"), description: L("Save it with its balance owed, and choose the day it should be paid by."),
                       icon: "circle-dollar-sign", accent: Theme.mango, unavailableReason: unavailable),
            OptionCard("draft", title: L("Keep as a draft"), description: L("Only your team sees it. Nothing is charged, and its products stay on the shelf."),
                       icon: "file-text", accent: Theme.aqua),
        ]
    }

    /// One line (web `LineEditor`): what is charged, how many, at what price; then its
    /// kind, a courtesy, its total and ✕; the reason and prescription it may need; a note.
    @ViewBuilder private func lineEditor(_ line: Binding<CashLineDraft>) -> some View {
        let value = line.wrappedValue
        let key = value.key
        VStack(alignment: .leading, spacing: 12) {
            PMTextField(L("What is charged"), text: line.label, key: "label-\(key)", form: form, prompt: L("e.g. Annual wellness exam"), required: true)
            HStack(alignment: .top, spacing: 12) {
                FormField(label: L("Qty"), key: "qty-\(key)", form: form, required: true) {
                    TextField("1", text: Binding(get: { value.quantity.map(String.init) ?? "" }, set: { line.wrappedValue.quantity = Int($0.filter(\.isNumber)); changed = true; form.clear("qty-\(key)") }))
                        .keyboardType(.numberPad).multilineTextAlignment(.center).monospacedDigit()
                        .fieldChrome(invalid: form.error("qty-\(key)") != nil)
                }
                .frame(width: 88)
                MoneyField(label: L("Unit price"), cents: Binding(get: { value.unitAmount }, set: { line.wrappedValue.unitAmount = $0; changed = true }), key: "price-\(key)", form: form)
                    .disabled(value.courtesy && value.unit <= 0)
            }
            FlowLayout(spacing: 8, lineSpacing: 8) {
                if value.catalogId != nil {
                    HStack(spacing: 4) {
                        Glyph(value.itemType == "product" ? "package" : "stethoscope", size: 12)
                        Text(value.itemType == "product" ? L("Catalog product") : L("Catalog service"))
                    }
                    .font(Theme.text(11.2, weight: .heavy))
                    .foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Theme.wash(Theme.aqua, 18), in: Capsule())
                } else {
                    Segmented(options: [.init("service", L("Service")), .init("product", L("Product"))], selection: Binding(get: { value.itemType }, set: { line.wrappedValue.itemType = $0; changed = true }), look: .raised, label: L("Type"))
                }
                if let listed = value.listUnitAmount, listed > 0, value.unit > 0, listed != value.unit {
                    Text(LF("Catalog price %@", cashMoney(listed))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
                if value.unpriced {
                    Text(L("Needs a price")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.destructive)
                }
                if value.unit <= 0 || value.courtesy {
                    Toggle(isOn: Binding(get: { value.courtesy }, set: {
                        line.wrappedValue.courtesy = $0
                        line.wrappedValue.unitAmount = $0 ? 0 : nil
                        changed = true
                    })) {
                        Text(L("Courtesy")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    }
                    .toggleStyle(PMSwitchStyle())
                    .fixedSize()
                    .accessibilityHint(L("Given on purpose for $0: it doesn’t hold the bill for a price."))
                }
            }
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                Text(cashMoney(value.total)).font(.brandHeading(16)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    .accessibilityLabel(L("Line total"))
                IconCircleButton(systemImage: "trash-2", label: L("Remove")) {
                    lines.removeAll { $0.key == key }
                    changed = true
                }
            }
            if let kind = value.reasonKind {
                CashReasonField(kind: kind, text: line.reason, key: "reason-\(key)", form: form)
            }
            if value.needsPrescription, let catalogId = value.catalogId {
                FormField(label: L("Prescription"), key: "rx-\(key)", form: form) {
                    CashPrescriptionPicker(petId: petId, catalogItemId: catalogId, selection: Binding(get: { line.wrappedValue.prescriptionItemId }, set: {
                        line.wrappedValue.prescriptionItemId = $0
                        changed = true
                        form.clear("rx-\(key)")
                    }), quantity: value.quantity ?? 1, autoPick: false)
                }
            }
            TextField(L("A note on this line (optional)"), text: Binding(get: { value.description }, set: { line.wrappedValue.description = $0; changed = true }))
                .font(Theme.text(14))
                .fieldChrome()
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    // MARK: Loading

    private func start() async {
        guard !loaded else { return }
        let source = bill ?? template
        if let bill {
            lines = bill.lines.map { CashLineDraft.from($0, copy: false) }
            discount = bill.discountAmount > 0 ? bill.discountAmount : nil
            discountReason = bill.discountReason ?? ""
            billingNote = bill.billingNote ?? ""
            notes = bill.notes ?? ""
            issuedAt = DateText.parse(bill.issuedAt) ?? Date()
            dueAt = DateText.parse(bill.dueAt) ?? issuedAt
            destination = ["ready_for_payment", "open"].contains(bill.status) ? bill.status : "draft"
            petId = bill.providerClientPetId
        } else if let template {
            lines = template.lines.map { CashLineDraft.from($0, copy: true) }
            petId = template.providerClientPetId
        }
        if let source, !CashBillRules.isWalkIn(source) {
            client = try? await API.get("/provider-clients/\(source.providerClientId)")
        }
        step = steps.first ?? .bill
        loaded = true
    }

    /// The search (web `BillItemSearch`), 20 at a time: whoever sells searches the Store (barcode,
    /// stock; one list, shown 20 at a time), anyone else the Catalog (pages of 20 with its count).
    private func find(_ text: String, reset: Bool) async {
        finding = true
        defer { finding = false }
        if workspace.can(.salesSell) {
            do {
                let products: [CashProduct] = try await API.get("/provider-store/products", query: ["q": text])
                guard ClientSearch.query(search) == text else { return }
                found = products.map { CashFoundItem(id: $0.catalogItemId, itemType: $0.itemType, name: $0.name, unitAmount: $0.unitAmount, needsPrescription: $0.needsPrescription || $0.controlSchedule != nil, sku: $0.sku, available: $0.stock?.available) }
                foundTotal = products.count
                foundMore = false
                shownFound = Self.pageSize
                searchFailed = false
            } catch {
                searchFailed = true
            }
        } else {
            let offset = reset ? 0 : found.count
            do {
                let page: Page<CashCatalogItem> = try await API.get("/provider-catalog", query: ["limit": String(Self.pageSize), "offset": String(offset), "search": text, "active": "true"])
                guard ClientSearch.query(search) == text else { return }
                let items = page.items.map { CashFoundItem(id: $0.id, itemType: $0.itemType, name: $0.name, unitAmount: $0.defaultUnitAmount, needsPrescription: $0.requiresPrescription || $0.controlSchedule != nil, sku: $0.sku, available: $0.trackInventory ? $0.inventory?.quantityOnHand : nil) }
                found = reset ? items : found + items.filter { item in !found.contains { $0.id == item.id } }
                foundTotal = page.total
                foundMore = page.hasMore ?? (page.total.map { found.count < $0 } ?? (items.count == Self.pageSize))
                shownFound = found.count
                searchFailed = false
            } catch {
                if reset { searchFailed = true }
            }
        }
    }

    /// The next 20: more of the Store's list on screen, or the Catalog's next page.
    private func more() async {
        guard !finding else { return }
        if found.count > shownFound {
            shownFound += Self.pageSize
        } else if foundMore, let query = ClientSearch.query(search) {
            await find(query, reset: false)
        }
    }

    private func clearPrescriptions() {
        for index in lines.indices where lines[index].needsPrescription { lines[index].prescriptionItemId = nil }
    }

    /// The server asked for a prescription: the lines that need one show their picker,
    /// and the first without a choice is marked (its products are read again to know which).
    private func markPrescriptions(_ message: String) async {
        let unknown = lines.filter { !$0.needsPrescription && $0.itemType == "product" }.compactMap(\.catalogId)
        if !unknown.isEmpty, let products: [CashProduct] = try? await API.get("/provider-store/products", query: ["ids": unknown.joined(separator: ",")]) {
            for index in lines.indices {
                if let id = lines[index].catalogId, let product = products.first(where: { $0.catalogItemId == id }), product.needsPrescription || product.controlSchedule != nil {
                    lines[index].needsPrescription = true
                }
            }
        }
        let target = lines.first { $0.needsPrescription && $0.prescriptionItemId == nil } ?? lines.first { $0.needsPrescription }
        _ = form.check([(target.map { "rx-\($0.key)" } ?? "lines", message)])
    }

    private func addFound(_ item: CashFoundItem) {
        // The same catalog item again is one more of it, not a second line.
        if let index = lines.firstIndex(where: { $0.catalogId == item.id && !$0.courtesy }), let quantity = lines[index].quantity, quantity > 0 {
            lines[index].quantity = quantity + 1
            search = ""
            found = []
            changed = true
            form.clear("lines")
            return
        }
        var line = CashLineDraft.empty(item.itemType)
        line.catalogId = item.id
        line.label = item.name
        line.unitAmount = item.unitAmount > 0 ? item.unitAmount : nil
        line.listUnitAmount = item.unitAmount
        line.needsPrescription = item.needsPrescription && item.itemType == "product"
        lines.append(line)
        search = ""
        found = []
        changed = true
        form.clear("lines")
    }

    // MARK: Saving

    /// The footer's main button: on to the next step, or the save on the last one.
    private func next() {
        switch step {
        case .who:
            guard passes([("client", client == nil && bill == nil ? L("Choose the client first.") : nil)]) else { return }
            step = .bill
        case .bill where lastStep == .next:
            guard passes(billRules(nil)) else { return }
            // Nothing to charge yet: it can only stay a draft.
            if unpriced > 0 || total <= 0 { destination = "draft" } else if destination == "draft" && !isEdit { destination = "ready_for_payment" }
            step = .next
        default:
            save()
        }
    }

    /// The bill step's own checks, in the order its fields show; `target` also holds it to what leaving draft needs.
    private func billRules(_ target: String?) -> [(String, String?)] {
        var rules: [(String, String?)] = []
        if lines.isEmpty && (!isEdit || (target != nil && target != "draft")) { rules.append(("lines", L("Add at least one line to the bill."))) }
        for line in lines {
            rules.append(("label-\(line.key)", line.label.nonEmpty == nil ? L("Give the line a name.") : nil))
            rules.append(("qty-\(line.key)", (line.quantity ?? 0) < 1 || (line.quantity ?? 0) > 9999 ? L("A whole number, 1 or more.") : nil))
        }
        if let target, target != "draft", unpriced > 0 { rules.append(("lines", L("Put a price on every line, or mark it as a courtesy, before charging."))) }
        for line in lines where line.reasonKind != nil {
            rules.append(("reason-\(line.key)", line.reason.nonEmpty == nil ? line.reasonKind!.required : nil))
        }
        if (discount ?? 0) > subtotal { rules.append(("discount", LF("The discount is more than the bill adds up to (%@).", cashMoney(subtotal)))) }
        if canDiscount && discountNeedsReason { rules.append(("discountReason", discountReason.nonEmpty == nil ? CashReasonKind.discount.required : nil)) }
        if let target, target != "draft", total <= 0 { rules.append(("lines", L("A bill that adds up to nothing stays a draft: there is nothing to charge."))) }
        if target == "open" && DateText.dayKey(dueAt) < DateText.dayKey(issuedAt) { rules.append(("dueAt", L("The day to pay by can’t be before the bill’s date."))) }
        return rules
    }

    /// Which step shows a field.
    private func stepOf(_ key: String) -> Step {
        key == "client" ? .who : key == "dueAt" || key == "destination" ? .next : .bill
    }

    /// The form rule across steps: every invalid field marked, one toast, and the step with the
    /// first one opened and scrolled to.
    private func passes(_ rules: [(String, String?)]) -> Bool {
        guard let first = rules.first(where: { $0.1 != nil })?.0 else { return form.check(rules) }
        let target = stepOf(first)
        if target != step && steps.contains(target) {
            step = target
            // Once that step is drawn, so the scroll finds its field.
            DispatchQueue.main.async { _ = form.check(rules) }
        } else {
            _ = form.check(rules)
        }
        return false
    }

    /// A refusal the server placed on a field: its step opens and scrolls to it.
    private func reveal() {
        guard let target = form.scrollTarget, steps.contains(stepOf(target)), stepOf(target) != step else { return }
        step = stepOf(target)
        DispatchQueue.main.async { form.scrollTarget = nil; form.scrollTarget = target }
    }

    private func save() {
        let target: String? = asksDestination ? destination : statusSettled ? nil : "draft"
        var rules: [(String, String?)] = []
        if canChangeWho { rules.append(("client", client == nil && bill == nil ? L("Choose the client first.") : nil)) }
        rules += billRules(statusSettled ? "ready_for_payment" : target)
        guard passes(rules) else { return }

        var input: [String: Any?] = [
            "providerClientId": client?.id ?? bill?.providerClientId,
            "providerClientPetId": petId,
            "billingNote": billingNote.nonEmpty,
            "notes": notes.nonEmpty,
            "lineItems": lines.enumerated().map { $0.element.payload($0.offset) },
        ]
        if let target { input["status"] = target }
        if !dateLocked { input["issuedAt"] = DateText.dayKey(issuedAt) }
        if target == "ready_for_payment" { input["dueAt"] = CashDay.today } else if target == "open" { input["dueAt"] = DateText.dayKey(dueAt) }
        if let revision = bill?.revision { input["expectedRevision"] = revision }
        if bill == nil, let place = workspace.locationId { input["locationId"] = place }
        if canDiscount {
            input["discountAmount"] = discount ?? 0
            input["discountReason"] = (discount ?? 0) > 0 ? discountReason.nonEmpty : nil
        }
        working = true
        Task {
            defer { working = false }
            do {
                let saved: CashInvoice = bill != nil
                    ? try await API.patch("/provider-invoices/\(bill!.id)", body: input)
                    : try await API.post("/provider-invoices", body: input)
                if let target, target != "draft", saved.status == "draft" {
                    Toast.show(L("Saved as a draft: a line still needs a price."))
                } else {
                    Toast.show(bill != nil ? L("Bill saved.") : L("Bill created."))
                }
                announceDataChanged()
                onSaved(saved, target == "ready_for_payment" && canPay && saved.status != "draft")
                dismiss()
            } catch {
                switch cashErrorCode(error) {
                case "stale_bill":
                    Toast.error(L("Someone changed this bill while you were editing. Here it is as it stands now — make your change again."))
                case "reason_required":
                    let key = lines.first { $0.reasonKind != nil }.map { "reason-\($0.key)" } ?? "discountReason"
                    _ = passes([(key, errorText(error))])
                case "discount_too_big":
                    _ = passes([("discount", LF("The discount is more than the bill adds up to (%@).", cashMoney(subtotal)))])
                case let code? where code.hasPrefix("prescription_"):
                    if step != .bill { step = .bill }
                    await markPrescriptions(errorText(error))
                default:
                    if form.apply(error, known: ["providerClientId": "client", "discountAmount": "discount", "discountReason": "discountReason", "issuedAt": "issuedAt", "dueAt": "dueAt", "lineItems": "lines"]) { reveal() }
                }
            }
        }
    }
}
