//
//  CashCounter.swift
//  PawMiawNegocios
//
//  The counter (web: store/store-pos.tsx, store-customer.tsx, payment-step.tsx):
//  find what is bought, say who buys it (a walk-in or a client and their pet),
//  pick the client's open bills to pay with it, take the money however it
//  comes and hand over the receipt. Stock, tax and the folio are the server's.
//  A code is scanned with the camera, typed, or sent by a USB/Bluetooth
//  scanner into the search field (Return); a card's pencil fixes its name,
//  price, tax, barcode and count without leaving the counter. Another screen
//  can send a sale here already filled in (`StorePrefill`): a Pharmacy
//  hand-over, a bill to charge with products, a client.
//

import SwiftUI

struct CashCartLine: Identifiable, Equatable {
    var product: CashProduct
    var quantity: Int
    /// A price typed at the counter; nil keeps the catalog's.
    var unitAmount: Int?
    var prescriptionItemId: String?
    var reason: String = ""

    var id: String { product.catalogItemId }
    var unit: Int { unitAmount ?? product.unitAmount }
    /// Priced below the catalog's: it needs its why.
    var lowered: Bool { unit < product.unitAmount }
}

/// The counter's arithmetic (the server's `store-rules.ts`): the ticket discount
/// shared over the lines by weight, tax inside or on top of the prices.
enum CashSaleMath {
    struct Totals { var lines: [Int]; var gross: Int; var discount: Int; var tax: Int; var total: Int }

    static func share(_ amount: Int, _ weights: [Int]) -> [Int] {
        let total = weights.reduce(0) { $0 + max(0, $1) }
        guard amount > 0, total > 0 else { return weights.map { _ in 0 } }
        let exact = weights.map { Double(max(0, $0)) * Double(amount) / Double(total) }
        var floors = exact.map { Int($0.rounded(.down)) }
        var left = amount - floors.reduce(0, +)
        let order = exact.enumerated().sorted { ($0.element - Double(floors[$0.offset])) > ($1.element - Double(floors[$1.offset])) }.map(\.offset)
        for index in order where left > 0 { floors[index] += 1; left -= 1 }
        return floors
    }

    static func totals(_ lines: [CashCartLine], ticketDiscount: Int, pricesIncludeTax: Bool) -> Totals {
        let gross = lines.map { max(0, $0.quantity) * max(0, $0.unit) }
        let pool = gross.reduce(0, +)
        let shares = share(min(pool, max(0, ticketDiscount)), gross)
        var lineTotals: [Int] = []
        var tax = 0, discount = 0, total = 0
        for (index, line) in lines.enumerated() {
            let after = gross[index] - shares[index]
            let rate = line.product.rate
            let lineTax: Int
            let lineTotal: Int
            if pricesIncludeTax {
                lineTax = rate > 0 && after > 0 ? Int((Double(after * rate) / Double(10_000 + rate)).rounded()) : 0
                lineTotal = after
            } else {
                lineTax = rate > 0 ? Int((Double(after * rate) / 10_000).rounded()) : 0
                lineTotal = after + lineTax
            }
            lineTotals.append(lineTotal)
            tax += lineTax; discount += shares[index]; total += lineTotal
        }
        return Totals(lines: lineTotals, gross: pool, discount: discount, tax: tax, total: total)
    }
}

/// What a finished charge leaves: the sale's receipt and each bill settled with it.
struct CashChargeDone: Identifiable {
    let id = UUID()
    var sale: CashSale?
    var checkout: CashCheckoutResult?
    var stockMoved: Bool
    /// Where the receipt went, and the client's own email (to send it now or again).
    var emailedTo: String? = nil
    var clientEmail: String? = nil
}

struct CashCounter: View {
    let settings: CashStoreSettings
    @ObservedObject var device: CashDeviceRegister
    let openRegister: () -> Void
    /// A sale another screen sends here already filled in; applied once.
    var prefill: StorePrefill? = nil
    /// After a prefilled sale is charged and its receipt closed.
    var onCharged: (() -> Void)? = nil
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var query = ""
    @State private var type = "product"
    @State private var products: [CashProduct] = []
    @State private var otherMatches = 0
    @State private var loadingProducts = true
    @State private var productsError: String?
    @State private var cart: [CashCartLine] = []
    @State private var client: PickedClient?
    @State private var petId: String?
    @State private var walkInName = ""
    @State private var account: CashAccount?
    @State private var billIds: Set<String> = []
    @State private var ticketDiscount: Int?
    @State private var discountReason = ""
    @StateObject private var form = FormState()
    @State private var picking = false
    @State private var paying = false
    @State private var clearing = false
    @State private var pricing: CashCartLine?
    @State private var done: CashChargeDone?
    /// The receipt waits for the payment sheet to leave before it shows.
    @State private var pendingDone: CashChargeDone?
    @State private var scrollToSale = 0
    @State private var resets = 0
    @State private var prefillApplied = false
    /// Bills sent here to charge: said so when one was paid meanwhile.
    @State private var pendingBills: [String]?
    @State private var lookingUp = false
    @State private var ambiguous: CashAmbiguousCode?
    @State private var editing: CashProduct?
    @State private var showCatalog = false
    @State private var catalogItemId: String?
    /// A prefilled sale was charged: closing its receipt goes back.
    @State private var chargedPrefill = false

    private var canOverridePrice: Bool { workspace.can(.salesOverridePrice) }
    private var canEditCatalog: Bool { workspace.can(.catalogEdit) }
    private var canDiscount: Bool { workspace.can(.billingApplyDiscount) }
    private var canCollectBills: Bool { workspace.can(.billingRecordPayment) }
    private var canDispenseControlled: Bool { workspace.can(.pharmacyDispenseControlled) }
    private var typeKey: String { "pawmiaw.store.sell-type:\(workspace.current?.clinicId ?? "")" }

    private var openBills: [CashAccount.Open] { canCollectBills ? account?.open ?? [] : [] }
    private var selectedBills: [CashAccount.Open] { openBills.filter { billIds.contains($0.id) } }
    private var billsTotal: Int { selectedBills.reduce(0) { $0 + $1.balanceDueAmount } }
    private var credit: Int { client != nil ? account?.credit ?? 0 : 0 }
    private var totals: CashSaleMath.Totals { CashSaleMath.totals(cart, ticketDiscount: ticketDiscount ?? 0, pricesIncludeTax: settings.pricesIncludeTax) }
    private var grandTotal: Int { totals.total + billsTotal }
    private var ticketNeedsReason: Bool { cashDiscountNeedsReason(min(ticketDiscount ?? 0, totals.gross), of: totals.gross) }
    private var saleReason: String? { ticketNeedsReason ? discountReason.nonEmpty : nil }
    private var needsPatient: CashCartLine? { cart.first { $0.product.needsPrescription && (client == nil || petId == nil) } }
    private var needsPrescription: CashCartLine? { needsPatient == nil ? cart.first { $0.product.needsPrescription && $0.prescriptionItemId == nil } : nil }
    private var needsVet: CashCartLine? { canDispenseControlled ? nil : cart.first { $0.product.controlSchedule != nil } }
    private var needsPrice: CashCartLine? { cart.first { $0.unit <= 0 } }
    private var blocked: Bool { (cart.isEmpty && selectedBills.isEmpty) || needsPatient != nil || needsPrescription != nil || needsVet != nil || needsPrice != nil }

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 20) {
                        productsColumn.frame(maxWidth: .infinity)
                        saleColumn.frame(width: 400)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        // On a phone the sale is under the list: once it has something, the way down to it is at the top.
                        if !cart.isEmpty || !selectedBills.isEmpty { jumpBar(proxy) }
                        productsColumn
                        saleColumn
                    }
                }
            }
            .onChange(of: scrollToSale) { _, _ in withAnimation { proxy.scrollTo("cash-sale", anchor: .top) } }
        }
        .task(id: "\(query)|\(type)") {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await loadProducts()
        }
        .task(id: client?.id) { await loadAccount() }
        .task { await applyPrefill() }
        .onAppear { type = UserDefaults.standard.string(forKey: typeKey) ?? "product" }
        .sheet(item: $ambiguous) { found in
            CashAmbiguousCodeSheet(found: found) { product in
                add(product)
                query = ""
            }
        }
        .sheet(item: $editing, onDismiss: {
            // The Catalog opens once the quick edit has left.
            if catalogItemId != nil && !showCatalog { showCatalog = true }
        }) { product in
            CashQuickEditSheet(product: product, settings: settings, onSaved: { saved in
                for index in cart.indices where cart[index].id == saved.catalogItemId {
                    cart[index].product = CashQuickEdit.apply(saved, to: cart[index].product)
                }
                if let index = products.firstIndex(where: { $0.catalogItemId == saved.catalogItemId }) {
                    products[index] = CashQuickEdit.apply(saved, to: products[index])
                }
            }, onOpenCatalog: { catalogItemId = product.catalogItemId })
        }
        .navigationDestination(isPresented: Binding(get: { showCatalog }, set: { showCatalog = $0; if !$0 { catalogItemId = nil } })) { CatalogScreen(openItemId: catalogItemId) }
        .sheet(isPresented: $picking) {
            CashWhoIsBuyingSheet(client: client, petId: petId) { chosen, pet in
                if chosen.id != client?.id { billIds = [] }
                client = chosen
                petId = pet
            }
        }
        .sheet(isPresented: $paying, onDismiss: {
            if let pending = pendingDone { pendingDone = nil; done = pending }
        }) {
            CashCounterPaySheet(total: grandTotal, credit: credit, client: client, petId: petId, device: device, automaticReceipts: settings.emailReceipts != false) { payments, delivery in
                try await charge(payments: payments, delivery: delivery)
            }
        }
        .sheet(item: $pricing) { line in
            CashLinePriceSheet(line: line) { price in
                if let index = cart.firstIndex(where: { $0.id == line.id }) {
                    cart[index].unitAmount = price == cart[index].product.unitAmount ? nil : price
                }
            }
        }
        .sheet(item: $done, onDismiss: {
            // A sale another screen sent here: once charged and its receipt closed, back to that screen.
            if chargedPrefill { chargedPrefill = false; onCharged?() }
        }) { result in CashChargeDoneSheet(done: result, settings: settings) }
        .sheet(isPresented: $clearing) {
            ConfirmSheet(title: L("Clear this sale?"), message: L("Everything in it comes off, and it goes back to a walk-in customer. Nothing has been charged."), confirmTitle: L("Clear the sale"), destructive: true, cancelTitle: L("Keep it")) { _ in reset() }
        }
    }

    // MARK: Products

    /// The search (a scanner types here and presses Return; the scan mark opens the camera),
    /// what the list shows, and the cards (web: store-product-grid.tsx).
    @ViewBuilder private var productsColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                BarcodeSearchField(prompt: L("Search or scan a product"), text: $query,
                                   onSubmit: { Task { await handleScan(nil, format: nil) } },
                                   onScan: { scan in Task { await handleScan(scan.code, format: scan.format) } })
                Segmented(options: [
                    .init("product", L("Products"), icon: "package", tone: .hue(.peach)),
                    .init("service", L("Services"), icon: "briefcase-medical", tone: .hue(.sky)),
                    .init("all", L("All@kind"), icon: "layout-grid", tone: .page),
                ], selection: Binding(get: { type }, set: { type = $0; UserDefaults.standard.set($0, forKey: typeKey) }), look: .raised, label: L("What to list"))
            }
            if loadingProducts && products.isEmpty {
                LoadingState()
            } else if let productsError, products.isEmpty {
                ErrorState(message: productsError) { await loadProducts() }
            } else if products.isEmpty {
                emptyProducts
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 256), spacing: 10, alignment: .top)], spacing: 10) {
                    ForEach(products) { product in
                        CashProductCard(product: product, inCart: cart.first { $0.id == product.id }?.quantity ?? 0, canEdit: canEditCatalog,
                                        onAdd: { add(product) }, onEdit: { editing = product })
                    }
                }
            }
        }
    }

    @ViewBuilder private var emptyProducts: some View {
        let other: String? = type == "product" ? "service" : type == "service" ? "product" : nil
        let switchTitle: String? = other.flatMap { other in
            guard otherMatches > 0 else { return nil }
            if query.nonEmpty != nil {
                return other == "service" ? LP(otherMatches, "%d service matches", "%d services match") : LP(otherMatches, "%d product matches", "%d products match")
            }
            return other == "service" ? L("See services") : L("See products")
        }
        if let q = query.nonEmpty {
            EmptyState(systemImage: "search",
                       title: type == "product" ? LF("No product matches “%@”", q) : type == "service" ? LF("No service matches “%@”", q) : LF("Nothing matches “%@”", q),
                       message: switchTitle != nil ? (other == "service" ? L("It is listed under Services.") : L("It is listed under Products.")) : L("Check the spelling, or scan the barcode."),
                       actionTitle: switchTitle, action: switchTitle != nil ? { if let other { type = other } } : nil,
                       accent: Theme.mango, panel: true)
        } else {
            let manages = workspace.canAny(.catalogCreate, .catalogEdit)
            EmptyState(systemImage: type == "service" ? "briefcase-medical" : "package",
                       title: type == "product" ? L("No products to sell yet") : type == "service" ? L("No services to sell yet") : L("Your catalog is empty"),
                       message: manages
                           ? (type == "product" ? L("Add what you sell at the counter — food, medicine, accessories — in the Catalog, and it shows up here.") : L("Add products and services in the Catalog to sell them here."))
                           : L("Whoever manages the Catalog adds what is sold here."),
                       actionTitle: manages ? (type == "service" ? L("Add services in the Catalog") : L("Add products in the Catalog")) : switchTitle,
                       action: manages ? { showCatalog = true } : (switchTitle != nil ? { if let other { type = other } } : nil),
                       accent: Theme.mango, panel: true)
        }
    }

    /// The way down to the sale on a phone (web: the sticky "N items · total ↓" bar).
    private func jumpBar(_ proxy: ScrollViewProxy) -> some View {
        Button { scrollToSale += 1 } label: {
            HStack(spacing: 12) {
                Glyph("shopping-cart", size: 16).foregroundStyle(Theme.blue)
                Text(LP(cart.reduce(0) { $0 + $1.quantity }, "%d item", "%d items")).font(Theme.text(14, weight: .bold)).lineLimit(1)
                Spacer(minLength: 8)
                Text(cashMoney(grandTotal, settings.currency)).font(.brandHeading(16)).monospacedDigit()
                Glyph("arrow-down", size: 16)
            }
            .foregroundStyle(Theme.inkStrong)
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.blue, lineWidth: 2))
            .cardShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("See the sale"))
    }

    // MARK: The sale

    /// The sale (web: the counter's aside): who buys, what they already owe,
    /// the cart, then the totals and Charge on a pale blue band.
    @ViewBuilder private var saleColumn: some View {
        FormScroll(form: form) {
            VStack(alignment: .leading, spacing: 0) {
                customerSection
                    .padding(16)
                if !openBills.isEmpty {
                    RowDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        eyebrow(L("Also owes"))
                        ForEach(openBills) { bill in billRow(bill) }
                    }
                    .padding(16)
                }
                RowDivider()
                VStack(alignment: .leading, spacing: 8) {
                    if cart.isEmpty {
                        EmptyState(systemImage: "shopping-cart", title: selectedBills.isEmpty ? L("Tap a product to add it.") : L("Anything else from the counter? Tap a product."), accent: Theme.mango)
                    } else {
                        ForEach(Array(cart.enumerated()), id: \.element.id) { index, line in
                            cartRow(index: index, line: line)
                        }
                    }
                }
                .padding(16)
                RowDivider()
                VStack(alignment: .leading, spacing: 8) { totalsSection }
                    .padding(16)
                    .background(Theme.wash(Theme.aqua, 10))
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 2))
            .cardShadow()
            .id("cash-sale")
        }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased()).font(.brandText(10.9, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.inkSoft)
    }

    /// Who is buying (web `StoreCustomer`): a walk-in with an optional name, or a client and which pet.
    @ViewBuilder private var customerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(client != nil ? AnyShapeStyle(Theme.wash(Theme.mango, 35)) : AnyShapeStyle(Theme.surfaceMuted))
                    if let photo = client?.photoUrl, APIConfig.assetURL(photo) != nil {
                        Avatar(name: client?.ownerName, imageURL: photo, size: 40)
                    } else {
                        Glyph("user-round", size: 20).foregroundStyle(Theme.inkStrong)
                    }
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    eyebrow(L("Customer"))
                    Text(client?.ownerName ?? L("Walk-in customer")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                }
                Spacer(minLength: 4)
                if workspace.can(.clientsView) {
                    if client == nil {
                        PMButton(L("Choose client"), systemImage: "user-round-search", variant: .outline) { picking = true }
                    } else {
                        IconCircleButton(systemImage: "user-round-search", label: L("Change client"), tint: Theme.blue) { picking = true }
                    }
                }
                if client != nil {
                    IconCircleButton(systemImage: "x", label: L("Back to walk-in")) { client = nil; petId = nil; billIds = [] }
                }
            }
            if let client {
                let pets = client.activePets
                if !pets.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(pets) { pet in petPill(pet) }
                    }
                }
                HStack(alignment: .center, spacing: 8) {
                    if client.householdId != nil {
                        TagChip(text: L("Family linked"), icon: "link-2", linked: true)
                        Text(L("Uses PawMiaw: the receipt goes to their app, and medicines to the pet’s cabinet.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    } else {
                        TagChip(text: L("Clinic-only"), icon: "building-2")
                    }
                }
            } else {
                TextField(L("Name on the receipt (optional)"), text: $walkInName)
                    .font(Theme.bodyFont)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(Theme.inputFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
            }
        }
    }

    private func petPill(_ pet: PickedPet) -> some View {
        let on = petId == pet.id
        return Button { petId = on ? nil : pet.id } label: {
            HStack(spacing: 8) {
                PetAvatar(name: pet.name, species: pet.petSpecies, photoURL: pet.photoUrl, size: 32)
                Text(pet.name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                if on { Glyph("check", size: 16).foregroundStyle(Theme.blue) }
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .padding(.vertical, 4)
            .frame(minHeight: 44)
            .background(on ? AnyShapeStyle(Theme.wash(Theme.aqua, 22)) : AnyShapeStyle(Color.clear), in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Theme.blue : Theme.borderSoft, lineWidth: 2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// What the client already owes — visits, stays, fees — picked to pay now (web `OpenBills`).
    private func billRow(_ bill: CashAccount.Open) -> some View {
        let on = billIds.contains(bill.id)
        return Button {
            if on { billIds.remove(bill.id) } else { billIds.insert(bill.id) }
        } label: {
            HStack(spacing: 12) {
                Glyph(on ? "square-check" : "square", size: 20).foregroundStyle(on ? Theme.blue : Theme.borderSoft)
                VStack(alignment: .leading, spacing: 2) {
                    Text([CashBills.sourceTitle(bill.source), bill.petName].compactMap { $0?.nonEmpty }.joined(separator: " · ")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text([bill.folio, bill.daysOverdue > 0 ? CashText.daysLate(bill.daysOverdue) : nil, bill.amountPaid > 0 ? LF("%@ paid", cashMoney(bill.amountPaid, settings.currency)) : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 8)
                Text(cashMoney(bill.balanceDueAmount, settings.currency)).font(.brandHeading(16)).monospacedDigit().foregroundStyle(Theme.inkStrong)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(on ? AnyShapeStyle(Theme.wash(Theme.blue, 8)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(on ? Theme.blue : Theme.borderSoft, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// A line of the sale (web `CartRow`): the name and its total, the prescription it is
    /// sold against, how many, the price each (typed for this sale when allowed), its why.
    @ViewBuilder private func cartRow(index: Int, line: CashCartLine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(line.product.name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(cashMoney(totals.lines[safe: index] ?? 0, settings.currency)).font(.brandHeading(16)).monospacedDigit().foregroundStyle(Theme.inkStrong)
            }
            if !canDispenseControlled && line.product.controlSchedule != nil {
                Text(L("Controlled: a vet hands it over.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.destructive)
            }
            if (line.product.needsPrescription || line.prescriptionItemId != nil) && petId != nil {
                CashPrescriptionPicker(petId: petId, catalogItemId: line.product.catalogItemId, selection: Binding(get: { cart[safe: index]?.prescriptionItemId }, set: { value in if cart.indices.contains(index) { cart[index].prescriptionItemId = value } }), quantity: line.quantity)
            }
            HStack(spacing: 8) {
                CashQuantityStepper(quantity: line.quantity, lessIcon: line.quantity == 1 ? "trash-2" : "minus",
                                    lessLabel: line.quantity == 1 ? LF("Remove %@", line.product.name) : L("One less"),
                                    less: { setQuantity(index, line.quantity - 1) }, more: { setQuantity(index, line.quantity + 1) })
                Spacer(minLength: 8)
                Button { if canOverridePrice { pricing = line } } label: {
                    HStack(spacing: 4) {
                        if line.unit > 0 {
                            Text(LF("%@ each", cashMoney(line.unit, settings.currency)))
                                .underline(canOverridePrice, pattern: .dot)
                        } else {
                            Text(L("No price")).foregroundStyle(Theme.destructive)
                        }
                        if line.unitAmount != nil && line.unitAmount != line.product.unitAmount {
                            Text(cashMoney(line.product.unitAmount, settings.currency)).strikethrough().foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .font(Theme.text(12, weight: .semibold))
                    .foregroundStyle(canOverridePrice ? Theme.blue : Theme.inkSoft)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(!canOverridePrice)
                .accessibilityHint(canOverridePrice ? L("Change the price for this sale") : "")
            }
            if line.lowered {
                CashReasonField(kind: .priceLowered, text: Binding(get: { cart[safe: index]?.reason ?? "" }, set: { value in if cart.indices.contains(index) { cart[index].reason = value } }), key: "line-\(line.id)", form: form)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    @ViewBuilder private var totalsSection: some View {
        let currency = settings.currency
        if canDiscount && !cart.isEmpty {
            MoneyField(label: L("Discount"), cents: $ticketDiscount, key: "discount-amount", form: form, optional: true)
                .id("discount-\(resets)")
        }
        if ticketNeedsReason {
            CashReasonField(kind: .discount, text: $discountReason, key: "discount", form: form)
        }
        if !selectedBills.isEmpty && !cart.isEmpty {
            totalRow(L("Bills"), cashMoney(billsTotal, currency))
            totalRow(L("Counter"), cashMoney(totals.total, currency))
        }
        if totals.discount > 0 { totalRow(L("Discounts"), "−\(cashMoney(totals.discount, currency))") }
        if totals.tax > 0 {
            let rates = Array(Set(cart.map(\.product.rate).filter { $0 > 0 })).sorted().map(cashRate).joined(separator: ", ")
            totalRow(settings.pricesIncludeTax ? LF("Tax included (%@)", rates) : LF("Tax (%@)", rates), cashMoney(totals.tax, currency))
        }
        HStack(alignment: .lastTextBaseline) {
            Text(L("Total").uppercased()).font(Theme.text(14, weight: .bold)).tracking(1.7).foregroundStyle(Theme.inkSoft)
            Spacer(minLength: 8)
            Text(cashMoney(grandTotal, currency)).font(.brandHeading(30, relativeTo: .title)).monospacedDigit().foregroundStyle(Theme.inkStrong).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.top, 4)
        if credit > 0 {
            HStack(spacing: 8) {
                Glyph("piggy-bank", size: 16).foregroundStyle(Theme.blue)
                Text(LF("%@ of credit on account.", cashMoney(credit, currency)))
            }
            .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
        }
        if let line = needsPatient { NoticeCard(tone: .warning, title: LF("%@ needs a prescription — choose the client and the pet.", line.product.name)) }
        if let line = needsPrescription { NoticeCard(tone: .warning, title: LF("Choose the prescription for %@.", line.product.name)) }
        if let line = needsVet { NoticeCard(tone: .warning, title: LF("%@ is a controlled medicine: ask a vet to hand it over.", line.product.name)) }
        if let line = needsPrice { NoticeCard(tone: .warning, title: LF("%@ has no price: type one before charging.", line.product.name)) }
        if device.sessionId == nil {
            HStack(spacing: 8) {
                Glyph("lock", size: 16)
                Text(L("The register is closed: you can take card or transfer, not cash.")).frame(maxWidth: .infinity, alignment: .leading)
                if cashCanRunShift(workspace) {
                    PMButton(L("Open register"), systemImage: "lock-open", variant: .outline, size: .compact, action: openRegister)
                }
            }
            .font(Theme.text(12, weight: .semibold))
            .foregroundStyle(Theme.inkSoft)
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        }
        HStack(spacing: 8) {
            if !cart.isEmpty || !selectedBills.isEmpty {
                // One line goes at once; more than that asks first.
                IconCircleButton(systemImage: "trash-2", label: L("Clear the sale"), tint: Theme.blue) {
                    if cart.count > 1 || !selectedBills.isEmpty { clearing = true } else { reset() }
                }
            }
            PMButton(LF("Charge %@", cashMoney(grandTotal, currency)), systemImage: "banknote", fullWidth: true) {
                if checkReasons() { paying = true }
            }
            .disabled(blocked)
        }
        .padding(.top, 4)
    }

    private func totalRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 8)
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(Theme.text(14))
        .foregroundStyle(Theme.inkSoft)
    }

    // MARK: Actions

    private func loadProducts() async {
        loadingProducts = true
        defer { loadingProducts = false }
        let listed = type == "all" ? nil : type
        do {
            let found: [CashProduct] = try await API.get("/provider-store/products", query: ["q": query.nonEmpty, "type": listed])
            products = listed.map { kind in found.filter { $0.itemType == kind } } ?? found
            productsError = nil
            // Fresh catalog figures for what is already in the sale (a price typed stays as typed).
            for (index, line) in cart.enumerated() {
                if let latest = found.first(where: { $0.catalogItemId == line.id }) { cart[index].product = latest }
            }
            otherMatches = 0
            if products.isEmpty, let listed, query.nonEmpty != nil {
                let other = listed == "product" ? "service" : "product"
                let more: [CashProduct]? = try? await API.get("/provider-store/products", query: ["q": query.nonEmpty, "type": other])
                otherMatches = more?.filter { $0.itemType == other }.count ?? 0
            }
        } catch {
            productsError = errorText(error)
        }
    }

    private func loadAccount() async {
        guard let client, workspace.moneyLevel >= .charging else { account = nil; return }
        account = try? await API.get("/provider-finance/clients/\(client.id)/account")
        // Say so when a bill sent here was paid meanwhile.
        if let pending = pendingBills, let account {
            let gone = pending.filter { id in !account.open.contains { $0.id == id } }
            if !gone.isEmpty { Toast.show(gone.count == 1 ? L("That bill is already paid or closed.") : L("Some of those bills are already paid or closed.")) }
            pendingBills = nil
        }
    }

    /// A code scanned (the camera hands it over) or typed and Return: looked up in every
    /// type, with its other spellings; two products with it ask which; typed by hand,
    /// Return adds the only match of the type listed.
    private func handleScan(_ scanned: String?, format: String?) async {
        guard let code = (scanned ?? query).nonEmpty, !lookingUp else { return }
        lookingUp = true
        defer { lookingUp = false }
        if scanned != nil { query = code }
        let search: (String) async throws -> [CashProduct] = { text in try await API.get("/provider-store/products", query: ["q": text]) }
        guard let found = try? await Barcode.findByCode(code, format: format, barcode: { $0.barcode }, sku: { $0.sku }, key: { $0.catalogItemId }, search: search) else { return }
        if found.matches.count > 1 {
            ambiguous = CashAmbiguousCode(code: code, products: found.matches)
            return
        }
        let listed = type == "all" ? found.found : found.found.filter { $0.itemType == type }
        if let match = found.exact ?? (listed.count == 1 ? listed[0] : nil) {
            add(match)
            query = ""
        }
    }

    // MARK: A sale sent here filled in

    /// The client and pet chosen, a hand-over's medicines against their prescription
    /// lines, the bills sent to charge selected — once. The sale is still what moves
    /// stock, money and the log.
    private func applyPrefill() async {
        guard let prefill, !prefillApplied else { return }
        prefillApplied = true
        var clientId = prefill.clientId
        var petWanted = prefill.petId
        var lines = prefill.lines
        if lines.isEmpty, let rx = prefill.prescriptionId, let handOver = try? await CashHandOver.load(rx) {
            lines = handOver.lines
            clientId = clientId ?? handOver.clientId
            petWanted = petWanted ?? handOver.petId
        }
        if let clientId {
            guard let loaded: PickedClient = try? await API.get("/provider-clients/\(clientId)") else {
                Toast.error(L("That client could not be found."))
                return
            }
            let pets = loaded.activePets
            client = loaded
            if let petWanted, pets.contains(where: { $0.id == petWanted }) {
                petId = petWanted
            } else if pets.count == 1 {
                petId = pets[0].id
            }
        }
        if !lines.isEmpty {
            await addLines(lines)
        } else {
            var bills = prefill.invoiceId.map { [$0] } ?? []
            if bills.isEmpty, let visit = prefill.appointmentId {
                let page: Page<CashInvoice>? = try? await API.get("/provider-invoices", query: ["providerAppointmentId": visit, "limit": "20", "offset": "0"])
                bills = (page?.items ?? []).filter { CashBillRules.isCollectible($0) && CashBillRules.kind($0) != "deposit" }.map(\.id)
            }
            if !bills.isEmpty {
                billIds = Set(bills)
                pendingBills = bills
                if account != nil { await loadAccount() }
            }
        }
    }

    /// Each medicine of a hand-over in the sale, against its prescription line, as much as the shelf holds.
    private func addLines(_ lines: [StorePrefill.Line]) async {
        let ids = Array(Set(lines.map(\.catalogItemId)))
        guard let found: [CashProduct] = try? await API.get("/provider-store/products", query: ["ids": ids.joined(separator: ",")]) else {
            Toast.error(L("The medicines of that prescription could not be loaded. Add them from the list."))
            return
        }
        var next: [CashCartLine] = []
        for line in lines {
            guard let product = found.first(where: { $0.catalogItemId == line.catalogItemId }) else {
                Toast.error(L("A medicine of that prescription is no longer sold here."))
                continue
            }
            var quantity = max(1, Int(line.quantity.rounded(.up)))
            if let available = product.stock?.available, product.stock?.allowBackorder != true {
                if available <= 0 {
                    Toast.error(Self.outOfStock(product))
                    continue
                }
                if quantity > available {
                    Toast.show(Self.onlyLeft(available, product.name))
                    quantity = available
                }
            }
            if let index = next.firstIndex(where: { $0.id == product.catalogItemId }) {
                next[index].quantity += quantity
            } else {
                next.append(CashCartLine(product: product, quantity: quantity, unitAmount: nil, prescriptionItemId: line.prescriptionItemId))
            }
        }
        billIds = []
        cart = next
    }

    private func add(_ product: CashProduct) {
        if product.unitAmount <= 0 && !canOverridePrice {
            Toast.error(LF("%@ has no price — put one in the Catalog before selling it.", product.name))
            return
        }
        let inCart = cart.first { $0.id == product.id }?.quantity ?? 0
        if let available = product.stock?.available, product.stock?.allowBackorder != true, inCart + 1 > available {
            Toast.error(available <= 0 ? Self.outOfStock(product) : Self.onlyLeft(available, product.name))
            return
        }
        if let index = cart.firstIndex(where: { $0.id == product.id }) {
            cart[index].quantity += 1
        } else {
            cart.append(CashCartLine(product: product, quantity: 1, unitAmount: nil))
            if product.unitAmount <= 0 { pricing = cart.last }
        }
    }

    private func setQuantity(_ index: Int, _ quantity: Int) {
        guard cart.indices.contains(index) else { return }
        if quantity <= 0 { cart.remove(at: index); return }
        let line = cart[index]
        if let available = line.product.stock?.available, line.product.stock?.allowBackorder != true, quantity > available {
            Toast.error(Self.onlyLeft(available, line.product.name))
            return
        }
        cart[index].quantity = quantity
    }

    static func outOfStock(_ product: CashProduct) -> String {
        (product.stock?.expiredUnits ?? 0) > 0 ? LF("%@: what is on the shelf has expired", product.name) : LF("%@ is out of stock", product.name)
    }

    static func onlyLeft(_ count: Int, _ name: String) -> String {
        count == 1 ? LF("Only 1 left of %@", name) : LF("Only %d left of %@", count, name)
    }

    /// Every missing reason marked, the first scrolled to (docs/money-access-levels.md).
    private func checkReasons() -> Bool {
        var rules: [(String, String?)] = []
        for line in cart where line.lowered {
            rules.append(("line-\(line.id)", line.reason.nonEmpty == nil && saleReason == nil ? CashReasonKind.priceLowered.required : nil))
        }
        rules.append(("discount", ticketNeedsReason && saleReason == nil ? CashReasonKind.discount.required : nil))
        return form.check(rules)
    }

    private func reset() {
        cart = []
        client = nil
        petId = nil
        billIds = []
        walkInName = ""
        ticketDiscount = nil
        discountReason = ""
        form.errors = [:]
        query = ""
        resets += 1
    }

    /// The charge last sent and its request id: sent again unchanged, it keeps the id so it is never charged twice.
    @State private var lastCharge: (key: String, id: String)?

    private func charge(payments: [[String: Any?]], delivery: [String: Any?]) async throws {
        let lines: [[String: Any?]] = cart.map { line in
            var entry: [String: Any?] = ["catalogItemId": line.product.catalogItemId, "quantity": line.quantity, "unitAmount": line.unitAmount]
            if let rx = line.prescriptionItemId { entry["prescriptionItemId"] = rx }
            if line.lowered, let reason = line.reason.nonEmpty { entry["adjustmentReason"] = reason }
            return entry
        }
        let key = "\(client?.id ?? "")|\(petId ?? "")|\(walkInName)|\(selectedBills.map(\.id))|\(cart.map { "\($0.id):\($0.quantity):\($0.unit)" })|\(ticketDiscount ?? 0)|\(payments.count)|\(device.sessionId ?? "")"
        let requestId = lastCharge?.key == key ? lastCharge!.id : cashRequestId()
        lastCharge = (key, requestId)
        let stockMoved = cart.contains { $0.product.stock != nil }
        let usesCredit = payments.contains { ($0["method"] as? String) == "credit" }
        do {
            if let client, !selectedBills.isEmpty || usesCredit {
                var body: [String: Any?] = [
                    "clientRequestId": requestId,
                    "providerClientId": client.id,
                    "providerClientPetId": petId,
                    "invoiceIds": selectedBills.map(\.id),
                    "lines": lines,
                    "ticketDiscount": (ticketDiscount ?? 0) > 0 ? ticketDiscount : nil,
                    "discountReason": saleReason,
                    "payments": payments,
                    "registerSessionId": device.sessionId,
                    "note": nil,
                ]
                body.merge(delivery) { _, new in new }
                let result: CashCheckoutResult = try await API.post("/provider-store/checkout", body: body)
                var sale: CashSale?
                if let saleId = result.saleId { sale = try? await API.get("/provider-store/sales/\(saleId)") }
                pendingDone = CashChargeDone(sale: sale, checkout: result, stockMoved: stockMoved, emailedTo: result.receipt?.emailedTo, clientEmail: client.ownerEmail)
            } else {
                var body: [String: Any?] = [
                    "clientRequestId": requestId,
                    "registerSessionId": device.sessionId,
                    "providerClientId": client?.id,
                    "providerClientPetId": petId,
                    "customerName": client == nil ? walkInName.nonEmpty : nil,
                    "lines": lines,
                    "ticketDiscount": (ticketDiscount ?? 0) > 0 ? ticketDiscount : nil,
                    "discountReason": saleReason,
                    "payments": payments,
                    "note": nil,
                ]
                body.merge(delivery) { _, new in new }
                if client == nil { body["saveReceiptEmail"] = false }
                let sale: CashSale = try await API.post("/provider-store/sales", body: body)
                pendingDone = CashChargeDone(sale: sale, checkout: nil, stockMoved: stockMoved, emailedTo: (delivery["receiptEmail"] ?? nil) as? String, clientEmail: client?.ownerEmail)
            }
            lastCharge = nil
            if prefill != nil && onCharged != nil { chargedPrefill = true }
            reset()
            NotificationCenter.default.post(name: CashDeviceRegister.changed, object: nil)
            announceDataChanged()
        } catch {
            if error is APIError { lastCharge = nil }
            if cashAsksReason(error) {
                paying = false
                let message = errorText(error)
                let key = ticketNeedsReason ? "discount" : (cart.first { $0.lowered }.map { "line-\($0.id)" } ?? "discount")
                _ = form.check([(key, message)])
                throw CashHandled()
            }
            // Refusals the counter can point at; the server's sentence is already in the reader's language.
            switch cashErrorCode(error) {
            case "pet_archived":
                petId = nil
                Toast.error(error, fallback: L("This pet is archived: restore it to sell for it."))
                throw CashHandled()
            case "pack_base_archived":
                Toast.error(error, fallback: L("A pack in the sale draws on a product that is archived: take it out of the sale."))
                throw CashHandled()
            case "location_not_assigned":
                Toast.error(error, fallback: L("You do not work at this register’s location."))
                throw CashHandled()
            default:
                throw error
            }
        }
    }
}

/// An error the counter already showed (under its field): the sheet stays quiet.
struct CashHandled: Error {}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Shared pieces of the Store's sheets

/// − count + in a 2 pt capsule, 44 pt targets (web: the cart line's and the return's quantity).
struct CashQuantityStepper: View {
    let quantity: Int
    var lessIcon: String = "minus"
    var lessLabel: String = L("One less")
    var lessDisabled: Bool = false
    var moreDisabled: Bool = false
    let less: () -> Void
    let more: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: less) { Glyph(lessIcon, size: 16).frame(width: 44, height: 44).contentShape(Circle()) }
                .buttonStyle(.plain)
                .disabled(lessDisabled)
                .opacity(lessDisabled ? 0.4 : 1)
                .accessibilityLabel(lessLabel)
            Text("\(quantity)").font(Theme.text(14, weight: .bold)).monospacedDigit().frame(minWidth: 28)
            Button(action: more) { Glyph("plus", size: 16).frame(width: 44, height: 44).contentShape(Circle()) }
                .buttonStyle(.plain)
                .disabled(moreDisabled)
                .opacity(moreDisabled ? 0.4 : 1)
                .accessibilityLabel(L("One more"))
        }
        .foregroundStyle(Theme.inkStrong)
        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 2))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Quantity"))
    }
}

/// Who a sheet is about, under its header (web `ModalContextPills`): the client
/// and the pet as soft 32 pt pills, and the client's link to PawMiaw.
struct CashContextPills: View {
    let client: String?
    var linked: Bool? = nil
    var pets: [String] = []

    /// The shared pills (web `ModalContextPills`).
    var body: some View { ContextPills(client: client, linked: linked, pets: pets) }
}

/// One thing to sell (web `ProductCard`): its photo or a small tinted icon, the
/// name, the price and — for products — what is left. The whole card adds it;
/// the pencil (people who edit the catalog) opens the quick edit.
struct CashProductCard: View {
    let product: CashProduct
    var inCart: Int = 0
    var canEdit: Bool = false
    let onAdd: () -> Void
    var onEdit: () -> Void = {}

    private var tone: Hue { product.isService ? .sky : .peach }
    private var icon: String {
        if product.isService { return "briefcase-medical" }
        switch product.productKind {
        case "medication": return "pill"
        case "food": return "paw-print"
        case "supply": return "boxes"
        case "accessory": return "shopping-bag"
        case "other": return "sparkles"
        default: return "package"
        }
    }

    var body: some View {
        Button(action: onAdd) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).fill(Theme.wash(tone.color, 24))
                    Glyph(icon, size: 20).foregroundStyle(Theme.inkStrong)
                    if let url = APIConfig.assetURL(product.photoUrl) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                        }
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(2).multilineTextAlignment(.leading)
                    FlowLayout(spacing: 8, lineSpacing: 4) {
                        if product.unitAmount > 0 {
                            Text(cashMoney(product.unitAmount, product.currency)).font(.brandHeading(16)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                        } else {
                            Chip(text: L("No price"), tone: .warn)
                        }
                        if stockLevel != nil {
                            stockTag
                        } else {
                            HueChip(text: product.isService ? L("Service") : L("Product"), hue: tone)
                        }
                        if product.needsPrescription { Chip(text: "Rx", tone: .warn).accessibilityLabel(L("Prescription only")) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if canEdit || !stockOut {
                    HStack(spacing: 6) {
                        // The pencil's slot: the button itself sits over it.
                        if canEdit { Color.clear.frame(width: 36, height: 36) }
                        if !stockOut {
                            Glyph("plus", size: 16)
                                .foregroundStyle(inCart > 0 ? Theme.onBlue : Theme.inkStrong)
                                .frame(width: 32, height: 32)
                                .background(inCart > 0 ? AnyShapeStyle(Theme.blue) : AnyShapeStyle(Theme.wash(Theme.blue, 14)), in: Circle())
                                .overlay(alignment: .topTrailing) {
                                    if inCart > 0 { CountBadge(count: inCart, color: Theme.inkStrong).offset(x: 8, y: -8) }
                                }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(inCart > 0 ? Theme.blue : Theme.borderSoft, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(stockOut)
        .opacity(stockOut ? 0.6 : 1)
        .overlay(alignment: .bottomTrailing) {
            if canEdit {
                IconCircleButton(systemImage: "pencil", label: LF("Edit %@", product.name), action: onEdit)
                    .padding(.trailing, stockOut ? 10 : 10 + 32 + 6)
                    .padding(.bottom, 10)
            }
        }
        .contextMenu {
            if canEdit {
                Button(action: onEdit) { GlyphLabel(LF("Edit %@", product.name), icon: "pencil") }
            }
        }
    }

    private var stockOut: Bool { stockLevel == "out" && product.stock?.allowBackorder != true }

    /// Out, low or in stock — Inventory's own rule; nil when the stock is not counted.
    private var stockLevel: String? {
        guard let stock = product.stock, let available = stock.available else { return nil }
        if available <= 0 || stock.outOfStock == true { return "out" }
        if stock.lowStockAlert == false { return "in" }
        if let low = stock.lowStock, (stock.reorderPoint ?? 0) > 0 || stock.outOfStock != nil { return low ? "low" : "in" }
        return available <= 3 ? "low" : "in"
    }

    /// The stock in three tones: red out, mango low, green in stock.
    @ViewBuilder private var stockTag: some View {
        if let level = stockLevel, let available = product.stock?.available {
            switch level {
            case "out": Chip(text: product.stock?.allowBackorder == true ? L("On backorder") : (product.stock?.expiredUnits ?? 0) > 0 ? L("Expired") : L("Out of stock"), tone: .danger)
            case "low": Chip(text: LP(available, "%d left", "%d left"), tone: .warn)
            default: HueChip(text: LF("%d in stock", available), hue: .mint)
            }
        }
    }
}

// MARK: - Sheets

/// "Who is buying?": the client, and the pet when it is for one of them.
struct CashWhoIsBuyingSheet: View {
    let client: PickedClient?
    let petId: String?
    let onChoose: (PickedClient, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: PickedClient?
    @State private var pet: String?
    @StateObject private var form = FormState()

    var body: some View {
        ProviderModal(title: L("Who is buying?"), subtitle: L("Choose the client, and the pet when it is for one of them. A prescription needs both."), systemImage: "user-round-search", accent: .aqua, isDirty: chosen?.id != client?.id || pet != petId, form: form, primaryTitle: L("Use this client"), primaryIcon: "check") {
            guard form.check([("client", chosen == nil ? L("Choose the client first.") : nil)]), let chosen else { return }
            onChoose(chosen, pet)
            dismiss()
        } content: {
            ClientPetPicker(client: $chosen, petIds: Binding(get: { pet.map { [$0] } ?? [] }, set: { pet = $0.first }), form: form)
        }
        .onAppear { chosen = client; pet = petId }
    }
}

/// A price typed at the counter for this sale only.
struct CashLinePriceSheet: View {
    let line: CashCartLine
    let onSave: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var price: Int?
    @State private var seed = 0
    @StateObject private var form = FormState()

    var body: some View {
        ProviderModal(title: L("Type a price"), subtitle: line.product.name, systemImage: "tag", accent: .butter, isDirty: price != line.unitAmount, form: form, primaryTitle: L("OK")) {
            guard form.check([("price", (price ?? 0) <= 0 ? L("Enter an amount") : nil)]) else { return }
            onSave(price ?? 0)
            dismiss()
        } content: {
            MoneyField(label: L("Change the price for this sale"), cents: $price, key: "price", form: form,
                       hint: line.product.unitAmount > 0 ? LF("Catalog price %@", cashMoney(line.product.unitAmount)) : nil)
                .id(seed)
        }
        .presentationDetents([.medium])
        .onAppear { price = line.unit > 0 ? line.unit : nil; seed += 1 }
    }
}

/// The payment step of the counter (web `PaymentSheet`): who pays, the tenders,
/// the register, the receipt.
struct CashCounterPaySheet: View {
    let total: Int
    let credit: Int
    let client: PickedClient?
    let petId: String?
    @ObservedObject var device: CashDeviceRegister
    let automaticReceipts: Bool
    let onSubmit: ([[String: Any?]], [String: Any?]) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tenders = CashTenders()
    @State private var working = false
    @State private var email = ""
    @State private var sendReceipt = false

    private var registerOpen: Bool { device.sessionId != nil && !device.stale }

    var body: some View {
        ProviderModal(
            title: LF("Charge %@", cashMoney(total)),
            subtitle: L("Split it across methods if the customer pays part in cash and part by card."),
            systemImage: "credit-card", accent: .aqua, isDirty: false,
            primaryTitle: tenders.remaining > 0 && client != nil ? LF("Charge %@ · %@ on account", cashMoney(tenders.paid), cashMoney(tenders.remaining)) : L("Complete sale"),
            isWorking: working, cancelTitle: L("Back"), primaryIcon: "banknote"
        ) {
            submit()
        } content: {
            if let client {
                CashContextPills(client: client.name, linked: client.householdId != nil, pets: client.activePets.filter { $0.id == petId }.map(\.name))
            }
            CashTendersView(state: tenders, registerOpen: registerOpen)
            CashRegisterGate(device: device, wantsCash: tenders.wantsCash)
            CashReceiptEmailField(clientEmail: client?.ownerEmail, automatic: automaticReceipts, email: $email, send: $sendReceipt)
        }
        .onAppear { tenders.start(total: total, credit: credit, registerOpen: device.sessionId != nil, allowBalance: client != nil, currency: nil) }
    }

    private func submit() {
        if let problem = tenders.problem(registerOpen: registerOpen) { Toast.error(problem); return }
        working = true
        Task {
            defer { working = false }
            do {
                try await onSubmit(tenders.payments(), CashReceiptEmailField.delivery(clientEmail: client?.ownerEmail, typed: email, send: sendReceipt, canSave: client != nil))
                dismiss()
            } catch is CashHandled {
                dismiss()
            } catch {
                Toast.error(error, fallback: L("Could not complete the sale."))
            }
        }
    }
}

/// What the family paid (web `DoneSheet`): each bill settled with it, the receipt ready to
/// send, the sale's ticket and its PDF.
struct CashChargeDoneSheet: View {
    let done: CashChargeDone
    let settings: CashStoreSettings
    @Environment(\.dismiss) private var dismiss

    /// The sale and each bill this payment produced a receipt for.
    private var documents: [CashReceiptDocument] {
        var list: [CashReceiptDocument] = done.sale.map { [CashReceiptDocument(id: $0.id, folio: $0.folio)] } ?? []
        for bill in done.checkout?.invoices ?? [] where bill.paid > 0 && bill.id != done.sale?.id { list.append(CashReceiptDocument(id: bill.id, folio: bill.folio)) }
        return list
    }

    private var change: Int {
        if let checkout = done.checkout { return checkout.change }
        return done.sale?.payments.reduce(0) { $0 + ($1.changeAmount ?? 0) } ?? 0
    }

    var body: some View {
        ProviderModal(
            title: done.checkout.map { LF("Paid %@", cashMoney($0.paid, settings.currency)) } ?? LF("Sale %@", done.sale?.folio ?? ""),
            subtitle: change > 0 ? LF("Change to hand back: %@", cashMoney(change, settings.currency))
                : (done.checkout?.balanceLeft ?? 0) > 0 ? LF("%@ stays on their account.", cashMoney(done.checkout?.balanceLeft ?? 0, settings.currency))
                : done.stockMoved ? L("Paid. Stock is updated.") : L("Paid."),
            // The web's footer has no Cancel: "New sale" is the way out (a swipe closes it too).
            systemImage: "shopping-cart", accent: .aqua, primaryTitle: L("New sale"), primaryIcon: "plus", showsCancel: false, onPrimary: { dismiss() }
        ) {
            if let bills = done.checkout?.invoices, !bills.isEmpty {
                VStack(spacing: 6) {
                    ForEach(bills, id: \.id) { bill in
                        HStack(spacing: 12) {
                            HStack(spacing: 6) {
                                Glyph("file-text", size: 16).foregroundStyle(Theme.inkSoft)
                                Text(bill.folio).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            }
                            Spacer(minLength: 8)
                            Text(cashMoney(bill.paid, settings.currency) + (bill.balance > 0 ? " · " + LF("%@ left", cashMoney(bill.balance, settings.currency)) : " · " + L("paid")))
                                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                .padding(16)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            }
            CashReceiptReady(documents: documents, emailedTo: done.emailedTo, clientEmail: done.clientEmail, pdfSkip: done.sale?.id)
            if let sale = done.sale {
                CashReceiptView(sale: sale, footer: settings.receiptFooter)
                DocumentButton(title: L("Download PDF"), systemImage: "file-down", path: "/provider-store/sales/\(sale.id)/pdf", fileName: sale.folio, fullWidth: true)
            }
        }
    }
}

/// The open bills' words at the counter.
enum CashBills {
    static func sourceTitle(_ source: String) -> String {
        switch source {
        case "visit": L("Visit")
        case "stay": L("Stay")
        case "hospital": L("Hospitalization")
        case "store": L("Store")
        default: L("Other@source")
        }
    }
}

/// After the payment: the receipt is ready — where it was emailed (or that it wasn't),
/// each bill's PDF one tap away, and emailing it now or again (web: receipt-delivery.tsx ReceiptReady).
struct CashReceiptDocument: Identifiable, Hashable {
    let id: String
    let folio: String
}

struct CashReceiptReady: View {
    let documents: [CashReceiptDocument]
    let emailedTo: String?
    let clientEmail: String?
    /// A document whose PDF is shown elsewhere (the sale's, under its receipt).
    var pdfSkip: String? = nil
    @State private var sentTo: String?
    @State private var composing = false
    @State private var address = ""
    @State private var sending = false
    @State private var started = false

    var body: some View {
        if !documents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Glyph("receipt-text", size: 16)
                        .foregroundStyle(Theme.inkStrong)
                        .frame(width: 36, height: 36)
                        .background(Theme.wash(Theme.butter, 55), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Receipt ready")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        Text(sentTo.map { LF("Emailed to %@.", $0) } ?? (clientEmail?.nonEmpty != nil ? L("Not emailed.") : L("The client has no email.")))
                            .font(Theme.text(12, weight: sentTo != nil ? .semibold : .regular)).foregroundStyle(sentTo != nil ? Theme.blue : Theme.inkSoft)
                    }
                }
                FlowLayout(spacing: 8) {
                    // The sale's own PDF is under its receipt; the bills paid with it open here, made fresh.
                    ForEach(documents.filter { $0.id != pdfSkip }) { document in
                        DocumentButton(title: documents.count > 1 ? "\(L("Open PDF")) · \(document.folio)" : L("Open PDF"), systemImage: "external-link", path: "/provider-invoices/\(document.id)/pdf", fileName: document.folio) {
                            let _: EmptyResponse = try await API.post("/provider-invoices/\(document.id)/pdf")
                        }
                    }
                    if !composing {
                        PMButton(sentTo != nil ? L("Send again") : L("Email it"), systemImage: "mail", variant: .outline, size: .compact) { composing = true }
                    }
                }
                if composing {
                    HStack(alignment: .center, spacing: 8) {
                        TextField(L("name@example.com"), text: $address)
                            .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(Theme.bodyFont)
                            .padding(.horizontal, 16)
                            .frame(height: 48)
                            .background(Theme.inputFill, in: Capsule())
                            .overlay(Capsule().strokeBorder(!address.isEmpty && !valid ? Theme.coral : Theme.borderSoft, lineWidth: 1))
                            .accessibilityLabel(L("Email for the receipt"))
                        PMButton(L("Send"), systemImage: "send", size: .compact, isWorking: sending) { send() }
                            .disabled(!valid)
                        IconCircleButton(systemImage: "x", label: L("Cancel")) { composing = false }
                    }
                    if !address.isEmpty && !valid {
                        Text(L("That email doesn’t look right.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.destructive)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1.5))
            .onAppear {
                guard !started else { return }
                started = true
                sentTo = emailedTo
                address = emailedTo ?? clientEmail ?? ""
            }
        }
    }

    private var valid: Bool { address.trimmingCharacters(in: .whitespaces).range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil }

    private func send() {
        let to = address.trimmingCharacters(in: .whitespaces)
        guard valid else { return }
        sending = true
        Task {
            defer { sending = false }
            do {
                for document in documents {
                    try await API.send("POST", "/provider-invoices/\(document.id)/send-receipt", body: ["email": to, "save": clientEmail?.nonEmpty == nil])
                }
                sentTo = to
                composing = false
                Toast.show(LF("Receipt sent to %@.", to))
            } catch {
                Toast.error(error, fallback: L("The receipt couldn’t be sent."))
            }
        }
    }
}
