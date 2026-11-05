//
//  StockReceiveSheet.swift
//  PawMiawNegocios
//
//  Recibir mercancía (web inventory/receive-stock-sheet.tsx + stock-product-picker.tsx):
//  which product (skipped when it opens from a product's row), what arrived —
//  how many, by unit or by pack, what it cost, its lot and expiry, who
//  delivered it — and a review of what it does to the shelf and its cost.
//  "Save and receive another" keeps the supplier and the invoice for the next
//  product of the same delivery. One request id per delivery typed: a retry
//  never receives it twice. The product is searched by name, SKU or barcode,
//  or scanned (a hardware scanner types its code and presses Return; the scan
//  mark reads it with the camera): a GS1 label also fills the lot and the
//  expiry. A code no product has can become a new Catalog product, with that
//  barcode already on it, and the delivery carries on with it.
//

import SwiftUI

private enum ReceiveStep: Int { case product, receipt, review }
private enum CostMode: Hashable { case each, total }

struct StockReceiveSheet: View {
    let preset: StockRow?
    var severalLocations: Bool = false
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var product: StockRow?
    @State private var fixed = false
    @State private var step: ReceiveStep = .product
    @State private var started = false

    @State private var quantity = ""
    @State private var unitsPerPack = 1
    @State private var costText = ""
    @State private var costMode: CostMode = .each
    @State private var lotCode = ""
    @State private var expiresOn = ""
    @State private var expiredConfirmed = false
    @State private var supplier = ""
    @State private var invoiceRef = ""
    @State private var note = ""

    @State private var saving = false
    @State private var saveError: (message: String, gone: Bool, connection: Bool)?
    @State private var received: [(key: String, name: String, units: Int, onHand: Int)] = []
    @State private var requestId = StockAPI.newRequestId()

    // The picker.
    @State private var search = ""
    @State private var products: [StockRow]?
    @State private var productsError: String?
    /// How many the list asks for: 20 more each time its last row shows (the server sends up to 100).
    @State private var productLimit = StockReceiveSheet.pageSize
    @State private var loadingMore = false
    /// A code that was scanned (or typed and entered) and belongs to no product, with what else its label said.
    @State private var unknownCode: (code: String, lot: String?, expiresOn: String?)?
    @State private var looking = false
    /// A new product: with the code that matched nothing (and its label's lot and expiry) when there is one.
    @State private var creating: StockCreateTarget?
    /// The lot and expiry a scanned label filled in: said so next to each, until it is changed.
    @State private var fromLabel: (lot: String?, expiresOn: String?) = (nil, nil)

    @EnvironmentObject private var workspace: Workspace
    private var canCreate: Bool { workspace.can(.catalogCreate) }

    private static let pageSize = 20
    private static let pageMax = 100
    private var today: String { StockRules.today }
    private var byPack: Bool { unitsPerPack > 1 }
    private var mustHaveLot: Bool { product.map { StockRules.requiresLotAndExpiry($0) } ?? false }

    var body: some View {
        ProviderModal(
            title: title,
            subtitle: L("What arrived, what it cost, and the lot and expiry date on the box."),
            systemImage: "package-check",
            accent: .aqua,
            isDirty: step != .product || (product != nil && !fixed) || !received.isEmpty,
            form: form,
            primaryTitle: primaryTitle,
            isWorking: saving,
            cancelTitle: received.isEmpty ? L("Cancel") : L("Done"),
            steps: ModalSteps(steps: stepList, current: stepIndex),
            onBack: stepBack,
            secondaryActions: step == .review ? [ModalAction(L("Save and receive another"), isWorking: saving) { Task { await submit(another: true) } }] : [],
            primaryIcon: step == .review ? "package-plus" : nil,
            onPrimary: primary
        ) {
            switch step {
            case .product: productStep
            case .receipt: receiptStep
            case .review: reviewStep
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            if let preset {
                product = preset
                fixed = true
                step = .receipt
            }
        }
        // The server searches from two characters, 250 ms after typing stops; under that, every product.
        .task(id: "\(ClientSearch.query(search) ?? "")|\(step == .product)") {
            guard step == .product else { return }
            if products != nil { try? await Task.sleep(for: ClientSearch.debounce) }
            guard !Task.isCancelled else { return }
            productLimit = Self.pageSize
            await loadProducts()
        }
        .sheet(item: $creating) { target in
            CashCatalogEditorSheet(initialBarcode: target.barcode) { created in
                // A pack or a service has no stock of its own to receive.
                if created.itemType == "product", created.stockCatalogItemId == nil {
                    choose(Self.receivable(created), lot: target.lot, expiresOn: target.expiresOn)
                }
            }
        }
    }

    private var title: String {
        if let product, step != .product { return LF("Receive %@", product.name) }
        return L("Receive delivery")
    }

    /// The product step is left out when the sheet opened on a product.
    private var stepList: [(title: String, icon: String)] {
        let all: [(title: String, icon: String)] = [(L("Product"), "package-search"), (L("What arrived"), "package-plus"), (L("Review"), "clipboard-check")]
        return fixed ? Array(all.dropFirst()) : all
    }

    private var stepIndex: Int { fixed ? step.rawValue - 1 : step.rawValue }

    private var primaryTitle: String {
        step == .review ? L("Receive stock") : L("Continue")
    }

    private func primary() {
        switch step {
        case .product:
            guard form.check([("product", product == nil ? L("Choose the product that arrived.") : nil)]) else { return }
            step = .receipt
        case .receipt: goReview()
        case .review: Task { await submit(another: false) }
        }
    }

    // MARK: The product

    private func loadProducts() async {
        do {
            products = try await searchProducts(ClientSearch.query(search) ?? "", limit: productLimit)
            productsError = nil
        } catch is CancellationError {
        } catch {
            productsError = errorText(error)
        }
    }

    /// The next 20, once the list's last row shows (the server answers up to 100 at once).
    private var hasMoreProducts: Bool {
        guard let products else { return false }
        return products.count >= productLimit && productLimit < Self.pageMax
    }

    private func loadMoreProducts() async {
        guard hasMoreProducts, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        productLimit = min(Self.pageMax, productLimit + Self.pageSize)
        await loadProducts()
    }

    /// Every product that keeps stock, by name, SKU or exact barcode.
    private func searchProducts(_ text: String, limit: Int? = nil) async throws -> [StockRow] {
        do {
            return try await API.get("/provider-stock/products", query: ["q": text.nonEmpty, "limit": limit.map(String.init)])
        } catch let error as APIError where error.status == 404 {
            return try await API.get("/provider-stock", query: ["q": text.nonEmpty])
        }
    }

    /// A scanner types the code and presses Return faster than the list can follow: the code is looked
    /// up right then. The camera hands its code over (`scan`) and it is looked up the same way. A code is
    /// the same code with or without its leading 0 (GTIN-14, EAN-13, UPC-A): each spelling is tried.
    private func lookUp(_ scan: BarcodeScan?) async {
        let code = (scan?.code ?? search).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !looking else { return }
        looking = true
        defer { looking = false }
        if scan != nil { search = code }
        do {
            let found = try await Barcode.findByCode(code, format: scan?.format, barcode: { $0.barcode }, sku: { $0.sku }, key: { $0.catalogItemId }) { text in
                try await searchProducts(text)
            }
            let match = found.exact ?? (found.matches.isEmpty && found.found.count == 1 ? found.found[0] : nil)
            if let match {
                unknownCode = nil
                search = ""
                choose(match, lot: scan?.lot, expiresOn: scan?.expiresOn)
            } else if found.matches.count > 1 {
                // The code is on more than one product: the list shows them all, and the person picks.
                unknownCode = nil
                search = found.code
                products = found.matches
                Toast.show(LF("%d products have this code. Choose which one arrived.", found.matches.count))
            } else if found.found.isEmpty {
                unknownCode = (code, scan?.lot, scan?.expiresOn)
            }
        } catch {
            // The list below says what went wrong.
        }
    }

    @ViewBuilder
    private var productStep: some View {
        if !received.isEmpty {
            NoticeCard(tone: .success, icon: "package-check") {
                Text(received.count == 1 ? L("1 product received in this delivery") : LF("%d products received in this delivery", received.count)).bold()
                ForEach(received, id: \.key) { entry in
                    Text(entry.onHand < 0
                         ? LF("%@: +%@ · %@", entry.name, StockText.count(entry.units), StockText.short(entry.onHand, withCount: false))
                         : LF("%@: +%@ · %@ on hand", entry.name, StockText.count(entry.units), StockText.count(entry.onHand)))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        BarcodeSearchField(prompt: L("Search by name, SKU or barcode — or scan it"),
                             text: Binding(get: { search }, set: { search = $0; unknownCode = nil }),
                             onSubmit: { Task { await lookUp(nil) } },
                             onScan: { scan in Task { await lookUp(scan) } })
            .id("product")
        if let error = form.error("product") {
            Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral)
        }
        if let unknown = unknownCode {
            let creatable = canCreate && Barcode.looksLikeCode(unknown.code)
            NoticeCard(tone: .lime, icon: nil) {
                Text(LF("No product has the code %@.", unknown.code)).bold()
                Text(canCreate
                     ? L("Search it by name — and add its barcode in the Catalog so the next scan finds it — or create it.")
                     : L("Search it by name. Someone who manages the Catalog can add its barcode."))
                    .foregroundStyle(Theme.inkSoft)
                if creatable {
                    PMButton(L("Create the product with this barcode"), systemImage: "plus", variant: .outline) {
                        creating = StockCreateTarget(barcode: unknown.code, lot: unknown.lot, expiresOn: unknown.expiresOn)
                    }
                    .padding(.top, 8)
                }
            }
        }
        if products == nil && productsError == nil {
            LoadingState()
        } else if let productsError, (products ?? []).isEmpty {
            EmptyState(systemImage: "package-search", title: L("The products could not be loaded."), message: productsError, actionTitle: L("Try again"), action: { Task { await loadProducts() } }, accent: Theme.pink)
        } else if (products ?? []).isEmpty {
            if search.trimmingCharacters(in: .whitespaces).isEmpty {
                EmptyState(systemImage: "package-plus", title: L("There are no products yet"),
                           message: canCreate ? L("Stock is kept for the products of your Catalog. Create the first one to receive it.") : L("Stock is kept for the products of the Catalog. Ask someone who manages it to add them."),
                           actionTitle: canCreate ? L("Create the product") : nil, action: canCreate ? { creating = StockCreateTarget() } : nil, accent: Theme.mango)
            } else {
                EmptyState(systemImage: "package-search", title: LF("No product matches “%@”.", search.trimmingCharacters(in: .whitespaces)),
                           message: canCreate ? L("Check the spelling, or create it: it is added to the Catalog and you carry on here.") : L("Check the spelling. Someone who manages the Catalog can add it."),
                           actionTitle: canCreate ? L("Create the product") : nil, action: canCreate ? { creating = StockCreateTarget() } : nil, accent: Theme.mango)
            }
        } else {
            ListCard(style: .box) {
                ForEach(Array((products ?? []).enumerated()), id: \.element.id) { index, row in
                    if index > 0 { RowDivider() }
                    Button { choose(row) } label: { productRow(row) }.buttonStyle(.plain)
                }
                LoadMoreRow(hasMore: hasMoreProducts, busy: loadingMore) { Task { await loadMoreProducts() } }
            }
            if canCreate {
                HStack(spacing: 8) {
                    Text(L("Can’t find it?")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    PMButton(L("Create the product"), variant: .link, size: .modal) { creating = StockCreateTarget() }
                }
            }
        }
    }

    private func productRow(_ row: StockRow) -> some View {
        let selected = row.catalogItemId == product?.catalogItemId
        let detail = ([StockText.detail(row).nonEmpty] + row.packs.map { LF("pack of %d", $0.stockUnits) }).compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 12) {
            StockProductThumb(photoUrl: row.photoUrl, productKind: row.productKind, size: 44)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.name).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                Text(detail.nonEmpty ?? L("No SKU")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                if row.tracked != false { Text(StockText.onHand(row.quantityOnHand)).font(.brandHeading(18)).monospacedDigit().foregroundStyle(Theme.inkStrong) }
                stockStateChip(row, today: today)
            }
            if selected { Glyph("check", size: 16).foregroundStyle(Theme.blue) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .background(selected ? AnyShapeStyle(Theme.wash(Theme.aqua, 22)) : AnyShapeStyle(Theme.surface))
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func choose(_ next: StockRow) { choose(next, lot: nil, expiresOn: nil) }

    /// A product just added to the Catalog, as the picker would have listed it (nothing on the shelf yet).
    private static func receivable(_ item: CashCatalogItem) -> StockRow {
        let inventory = item.inventory
        var row = StockRow(
            inventoryItemId: inventory?.id,
            catalogItemId: item.id,
            name: item.name,
            sku: item.sku,
            barcode: inventory?.barcode,
            photoUrl: item.photoUrl,
            productKind: item.productKind,
            quantityOnHand: inventory?.quantityOnHand ?? 0,
            reorderPoint: inventory?.reorderPoint ?? 0,
            // Null below business finances: the cost on file is not shown.
            unitCostAmount: inventory == nil ? 0 : inventory?.unitCostAmount,
            lowStock: inventory?.lowStock ?? false,
            lots: [],
            packs: [],
            tracked: inventory != nil && item.trackInventory,
            controlSchedule: item.controlSchedule
        )
        row.unitAmount = item.defaultUnitAmount
        row.allowBackorder = inventory?.allowBackorder ?? false
        row.requiresPrescription = item.requiresPrescription || item.controlSchedule?.nonEmpty != nil
        row.storageLocation = inventory?.storageLocation
        row.reorderQuantity = inventory?.reorderQuantity
        row.lowStockAlert = inventory?.lowStockAlert
        row.trackLots = false
        return row
    }

    /// The product chosen and, when its label was scanned, the lot and expiry it carried —
    /// filled in only where nothing was entered.
    private func choose(_ next: StockRow, lot scannedLot: String?, expiresOn scannedExpiry: String?) {
        let other = next.catalogItemId != product?.catalogItemId
        if other {
            requestId = StockAPI.newRequestId()
            // The supplier and its invoice belong to the delivery, not to the product.
            quantity = ""; unitsPerPack = 1; costText = ""; costMode = .each
            lotCode = ""; expiresOn = ""; expiredConfirmed = false; note = ""
            fromLabel = (nil, nil)
        }
        let lot = scannedLot?.nonEmpty.map { String($0.prefix(StockRules.lotCodeMax)) }
        if let lot, lotCode.trimmingCharacters(in: .whitespaces).isEmpty {
            lotCode = lot
            fromLabel.lot = lot
        }
        if let expiry = scannedExpiry?.nonEmpty, expiresOn.isEmpty {
            expiresOn = expiry
            expiredConfirmed = false
            fromLabel.expiresOn = expiry
        }
        unknownCode = nil
        product = next
        form.errors = [:]
        saveError = nil
        step = .receipt
    }

    // MARK: What arrived (web lib/inventory.ts readReceipt)

    private struct Figures {
        let units: Int
        let unitCost: Int?
        let totalCost: Int?
        let onHandAfter: Int
        let costAfter: Int?
    }

    private var parsedQuantity: (value: Int?, problem: StockQuantityProblem?) {
        StockRules.parseQuantity(quantity, max: StockRules.maxQuantity / max(1, unitsPerPack))
    }

    private var units: Int { (parsedQuantity.value ?? 0) * max(1, unitsPerPack) }

    /// The cost of one unit in cents: nil when not said (the current cost stays); `invalid` when it can't be read.
    private var unitCost: (value: Int?, invalid: Bool, tooLarge: Bool) {
        guard costText.nonEmpty != nil else { return (nil, false, false) }
        guard let amount = Money.parse(costText) else { return (nil, true, false) }
        let cost: Int?
        if costMode == .total { cost = units > 0 ? Int((Double(amount) / Double(units)).rounded()) : nil }
        else { cost = Int((Double(amount) / Double(max(1, unitsPerPack))).rounded()) }
        return (cost, false, (cost ?? 0) > StockRules.maxCostCents)
    }

    private var receiptNote: String {
        [supplier.nonEmpty.map { "\(L("Supplier")): \($0)" }, invoiceRef.nonEmpty.map { "\(L("Supplier invoice")): \($0)" }, note.nonEmpty]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var figures: Figures? {
        guard let product, units > 0 else { return nil }
        let cost = unitCost.value
        let costAfter: Int?
        if let current = product.unitCostAmount {
            costAfter = StockRules.averageCostAfter(onHand: product.quantityOnHand, currentCost: current, received: units, receivedCost: cost ?? current)
        } else {
            costAfter = max(0, product.quantityOnHand) == 0 ? cost : nil
        }
        return Figures(units: units, unitCost: cost, totalCost: cost.map { $0 * units }, onHandAfter: product.quantityOnHand + units, costAfter: costAfter)
    }

    private var expiresIn: Int? { expiresOn.isEmpty ? nil : StockRules.daysBetween(today, expiresOn) }

    private func quantityProblemText(_ problem: StockQuantityProblem) -> String {
        switch problem {
        case .required, .zero: byPack ? L("Enter how many packs arrived.") : L("Enter how many arrived.")
        case .whole: L("Stock is counted in whole units: no decimals.")
        case .negative: L("A delivery adds stock. To take stock out, write it off.")
        case .tooLarge: LF("That is more than one delivery can hold (%@ units). Check the number.", StockText.count(StockRules.maxQuantity / max(1, unitsPerPack) * max(1, unitsPerPack)))
        case .invalid: L("Enter the quantity as a number.")
        }
    }

    private func checkReceipt() -> Bool {
        let cost = unitCost
        return form.check([
            ("quantity", parsedQuantity.problem.map(quantityProblemText)),
            ("cost", cost.invalid ? L("Enter the cost as an amount, like 125.50.") : cost.tooLarge ? L("That cost is too high to be right. Check it.") : nil),
            ("lotCode", lotCode.count > StockRules.lotCodeMax ? LF("Up to %d characters.", StockRules.lotCodeMax) : (mustHaveLot && lotCode.nonEmpty == nil ? L("Enter the lot number printed on the box.") : nil)),
            ("expiresOn", mustHaveLot && expiresOn.isEmpty ? L("Choose the expiry date on the box.") : (!expiresOn.isEmpty && expiresOn < today && !expiredConfirmed ? L("Confirm that it arrived expired, or correct the date.") : nil)),
            ("note", receiptNote.count > StockRules.noteMax ? L("The supplier, the invoice and the note are too long together. Shorten the note.") : nil),
        ])
    }

    private func goReview() {
        guard checkReceipt(), figures != nil else { return }
        saveError = nil
        step = .review
    }

    @ViewBuilder
    private var receiptStep: some View {
        if let product {
            StockProductCard(row: product, after: figures?.onHandAfter, afterLabel: L("after this delivery"), today: today)
            if product.tracked == false {
                NoticeCard(tone: .info, message: L("The stock of this product is not counted yet. Receiving this delivery starts counting it."), icon: "info")
            }
            if product.quantityOnHand < 0 {
                NoticeCard(tone: .warning, message: product.quantityOnHand == -1
                            ? L("1 more was sold than the system had. A count after this delivery sets it right.")
                            : LF("%@ more were sold than the system had. A count after this delivery sets it right.", StockText.count(-product.quantityOnHand)), icon: "triangle-alert")
            }

            ModalSection(title: L("What arrived")) {
                let packs = product.packs.filter { $0.stockUnits > 1 }
                if !packs.isEmpty {
                    FormField(label: L("Receive by"), caps: true) {
                        FlowLayout(spacing: 8) {
                            FilterChip(title: L("Single units"), isSelected: unitsPerPack == 1) { unitsPerPack = 1 }
                            ForEach(packs, id: \.catalogItemId) { pack in
                                FilterChip(title: LF("%@ (×%d)", pack.name, pack.stockUnits), isSelected: unitsPerPack == pack.stockUnits) { unitsPerPack = pack.stockUnits }
                            }
                        }
                    }
                }
                PMTextField(byPack ? L("How many packs") : L("Quantity"), text: $quantity, key: "quantity", form: form, prompt: "0", hint: byPack && figures != nil
                                    ? LF("%@ × %d = %@", packsLabel(units / max(1, unitsPerPack)), unitsPerPack, StockText.units(units))
                                    : (byPack ? LF("Each pack adds %d units to the stock.", unitsPerPack) : L("Whole units, as they are sold or used.")), caps: true, required: true, strongHint: byPack && figures != nil, number: .large)
                FormField(label: costMode == .total ? L("Total cost") : byPack ? L("Cost per pack") : L("Cost per unit"), key: "cost", hint: costHint(product), form: form, optional: true, caps: true, strongHint: costHintIsResult) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("$").font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkSoft)
                            TextField("0.00", text: $costText).keyboardType(.decimalPad)
                            Text(workspace.currency).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        }
                        .fieldChrome(invalid: form.error("cost") != nil)
                        .onChange(of: costText) { _, _ in form.clear("cost") }
                    }
                }
                PillPicker(options: [(value: CostMode.each, title: byPack ? L("Per pack") : L("Per unit")), (value: CostMode.total, title: L("Whole delivery"))], selection: $costMode)
                    .accessibilityLabel(L("The cost is"))
            }

            ModalSection(title: L("Lot and expiry"), subtitle: L("With a lot or an expiry, the store sells the soonest-expiring stock first and never sells it once expired.")) {
                if mustHaveLot {
                    NoticeCard(tone: .info, title: L("Controlled medicine: its lot and its expiry date are required."), message: L("What is dispensed is recorded in the Pharmacy log"), icon: "shield-alert")
                }
                VStack(alignment: .leading, spacing: 6) {
                    PMTextField(L("Lot number"), text: $lotCode, key: "lotCode", form: form, prompt: L("As printed on the box"), capitalization: .characters, optional: !mustHaveLot, caps: true, required: mustHaveLot)
                    if let lot = fromLabel.lot, lot == lotCode { fromLabelHint }
                }
                FormField(label: L("Expiry date"), key: "expiresOn", form: form, optional: !mustHaveLot, caps: true, required: mustHaveLot) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Empty until chosen ("Choose the date"), even where it is required.
                        StockDayControl(day: $expiresOn, invalid: form.error("expiresOn") != nil) { form.clear("expiresOn") }
                            .onChange(of: expiresOn) { _, _ in expiredConfirmed = false }
                        if let expiry = fromLabel.expiresOn, expiry == expiresOn { fromLabelHint }
                        if !expiresOn.isEmpty && !mustHaveLot {
                            HStack {
                                Spacer()
                                Button(L("Clear the date")) { expiresOn = ""; expiredConfirmed = false }
                                    .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue)
                            }
                        }
                    }
                }
                if let days = expiresIn, days < 0 {
                    NoticeCard(tone: .problem, icon: "triangle-alert") {
                        Text(LF("This date has already passed (%@).", StockText.day(expiresOn))).bold()
                        Text(L("Expired stock is counted but never sold: it waits to be written off or sent back.")).foregroundStyle(Theme.inkSoft)
                        // The web's checkbox row.
                        Button { expiredConfirmed.toggle() } label: {
                            HStack(spacing: 12) {
                                Tick(on: expiredConfirmed, invalid: form.error("expiresOn") != nil)
                                Text(L("It arrived expired — receive it anyway")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(expiredConfirmed ? .isSelected : [])
                        .padding(.top, 8)
                        .onChange(of: expiredConfirmed) { _, _ in form.clear("expiresOn") }
                    }
                } else if let days = expiresIn, days <= StockRules.expiringDays {
                    NoticeCard(tone: .warning, message: days == 0 ? L("It expires today: it can be sold only today.") : days == 1 ? L("It expires tomorrow.") : LF("It expires in %d days: it will show as expiring soon.", days), icon: "calendar-clock")
                } else if expiresOn.isEmpty && !mustHaveLot && StockRules.isMedicine(product) {
                    Text(L("Medicines should carry their expiry date: without it the store cannot stop selling them once expired."))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
                let sameLot = StockRules.lotsWithCode(product.lots, lotCode)
                if !sameLot.isEmpty {
                    NoticeCard(tone: .info, message: LF("Lot %@ is already on the shelf (%@ left). This delivery is kept as its own entry under the same number.", lotCode.trimmingCharacters(in: .whitespaces), StockText.count(sameLot.reduce(0) { $0 + $1.quantityOnHand })), icon: "info")
                }
            }

            ModalSection(title: L("Who delivered it"), subtitle: L("Kept with the movement, so the history says where each delivery came from.")) {
                PMTextField(L("Supplier"), text: $supplier, optional: true, caps: true)
                PMTextField(L("Supplier invoice"), text: $invoiceRef, prompt: L("Its number or folio"), optional: true, caps: true)
                PMTextField(L("Note"), text: $note, key: "note", form: form, prompt: L("Anything worth remembering about this delivery"), optional: true, multiline: true, caps: true, lines: 2...8)
            }
        }
    }

    /// Says a value came from the scanned label, so it is checked against the box rather than trusted blindly.
    private var fromLabelHint: some View {
        HStack(spacing: 4) {
            Glyph("scan-line", size: 14).foregroundStyle(Theme.blue)
            Text(L("From the label"))
        }
        .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
    }

    /// The cost's line says a result (per unit · in all) rather than help.
    private var costHintIsResult: Bool {
        guard costText.nonEmpty != nil, let figures, let unit = figures.unitCost, unit > 0 else { return false }
        return figures.totalCost != nil
    }

    private func costHint(_ product: StockRow) -> String? {
        if costText.nonEmpty == nil {
            if let cost = product.unitCostAmount {
                return cost > 0 ? LF("Left empty, the cost stays at %@ per unit.", Money.format(cost)) : L("Left empty, this stock is kept without a cost. You can receive the next one with it.")
            }
            return L("Left empty, the cost on file stays as it is.")
        }
        if let figures, figures.unitCost == 0 { return L("No cost: a sample, a bonus or a donation. It brings the average cost of the stock down.") }
        if let figures, let unit = figures.unitCost, let total = figures.totalCost { return LF("%@ per unit · %@ in all", Money.format(unit), Money.format(total)) }
        if costMode == .total { return L("Enter the quantity to work out the cost of each unit.") }
        return nil
    }

    private func packsLabel(_ count: Int) -> String { count == 1 ? L("1 pack") : LF("%@ packs", StockText.count(count)) }

    /// The footer's "‹ Back" past the first step (web: `steps[index - 1]`).
    private var stepBack: (() -> Void)? {
        if step == .product || (fixed && step == .receipt) { return nil }
        return {
            saveError = nil
            step = step == .review ? .receipt : .product
        }
    }

    // MARK: Review

    @ViewBuilder
    private var reviewStep: some View {
        if let product, let figures {
            FlowLayout(spacing: 8) {
                Chip(text: product.name, tone: .muted, icon: "package")
                if let supplier = supplier.nonEmpty { Chip(text: supplier, tone: .muted) }
            }
            if let saveError {
                NoticeCard(tone: .problem, icon: saveError.connection ? "wifi-off" : "triangle-alert") {
                    Text(saveError.message).bold()
                    if saveError.gone {
                        PMButton(L("Choose another product"), variant: .link, size: .modal) {
                            self.saveError = nil; self.fixed = false; self.product = nil; self.step = .product
                        }
                    }
                }
            }
            StockProductCard(row: product, after: figures.onHandAfter, afterLabel: L("after this delivery"), today: today)
            ListCard(style: .box) {
                StockReviewRow(label: L("Arrives")) {
                    Text("+" + StockText.units(figures.units)).bold()
                    if byPack {
                        Text(LF("%@ × %d = %@", packsLabel(figures.units / max(1, unitsPerPack)), unitsPerPack, StockText.units(figures.units))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
                RowDivider()
                StockReviewRow(label: L("On hand")) {
                    Text(LF("%@ → %@", StockText.onHand(product.quantityOnHand), StockText.onHand(figures.onHandAfter)))
                }
                RowDivider()
                StockReviewRow(label: L("Cost")) {
                    if let unit = figures.unitCost, unit > 0 {
                        Text(Money.format(figures.totalCost ?? 0)).bold()
                        Text(LF("%@ per unit", Money.format(unit))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    } else {
                        Text(costLine(product, figures))
                    }
                }
                if figures.unitCost != nil, let current = product.unitCostAmount, let after = figures.costAfter, after != current, product.quantityOnHand > 0 {
                    RowDivider()
                    StockReviewRow(label: L("Average cost")) {
                        Text(LF("%@ → %@", Money.format(current), Money.format(after)))
                        Text(L("What each unit on the shelf costs, on average, after this delivery.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
                RowDivider()
                StockReviewRow(label: L("Lot and expiry")) {
                    Text(lotLine)
                    if let days = expiresIn, days < 0 {
                        Text(L("Already expired: it will not be sold.")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.destructive)
                    }
                }
                if let line = receiptNote.nonEmpty {
                    RowDivider()
                    StockReviewRow(label: L("Delivery")) { Text(line) }
                }
            }
            if product.tracked == false {
                NoticeCard(tone: .info, message: L("From now on, the stock of this product is counted."), icon: "info")
            }
            if severalLocations {
                HStack(alignment: .top, spacing: 8) {
                    Glyph("map-pin", size: 14).padding(.top, 1)
                    Text(L("Stock is counted for the whole business, not for each location."))
                }
                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func costLine(_ product: StockRow, _ figures: Figures) -> String {
        guard let unit = figures.unitCost else {
            if let current = product.unitCostAmount, current > 0 { return LF("Not entered — stays at %@ per unit", Money.format(current)) }
            return L("Not entered")
        }
        if unit == 0 { return L("No cost (sample or donation)") }
        return LF("%@ per unit", Money.format(unit))
    }

    private var lotLine: String {
        let lot = lotCode.nonEmpty
        if lot == nil && expiresOn.isEmpty { return L("None — sold with the rest of the stock, in any order") }
        let expiry: String? = expiresOn.isEmpty ? nil : ((expiresIn ?? 0) < 0 ? LF("expired on %@", StockText.day(expiresOn)) : LF("expires %@", StockText.day(expiresOn)))
        return [lot.map { LF("Lot %@", $0) }, expiry].compactMap { $0 }.joined(separator: " · ")
    }

    private func submit(another: Bool) async {
        guard let product, let figures, !saving else { return }
        saving = true
        saveError = nil
        defer { saving = false }
        do {
            let row: StockRow = try await StockAPI.send("POST", "/provider-stock/receive", body: [
                "catalogItemId": product.catalogItemId,
                "quantity": figures.units,
                "unitCostAmount": figures.unitCost,
                "lotCode": lotCode.nonEmpty,
                "expiresOn": expiresOn.nonEmpty,
                "note": receiptNote.nonEmpty,
                "clientRequestId": requestId,
            ])
            Toast.show(row.quantityOnHand < 0
                ? LF("%@ of %@ received. %@.", StockText.units(figures.units), product.name, StockText.short(row.quantityOnHand))
                : figures.units == 1
                    ? LF("1 unit of %@ received. %@ on hand now.", product.name, StockText.count(row.quantityOnHand))
                    : LF("%@ of %@ received. %@ on hand now.", StockText.units(figures.units), product.name, StockText.count(row.quantityOnHand)))
            onSaved()
            if !another {
                dismiss()
                return
            }
            received.append((requestId, product.name, figures.units, row.quantityOnHand))
            quantity = ""; unitsPerPack = 1; costText = ""; costMode = .each
            lotCode = ""; expiresOn = ""; expiredConfirmed = false; note = ""
            self.product = nil
            fixed = false
            search = ""
            products = nil
            productLimit = Self.pageSize
            unknownCode = nil
            fromLabel = (nil, nil)
            step = .product
            requestId = StockAPI.newRequestId()
            await loadProducts()
        } catch let refusal as StockRefusal where refusal.code == "controlled_lot_required" {
            // It became a controlled medicine while this was open: its lot and expiry are asked for, under their fields.
            self.product?.controlSchedule = product.controlSchedule?.nonEmpty ?? "controlled"
            step = .receipt
            let message = refusal.api.message.nonEmpty ?? L("A controlled medicine is received with its lot number and expiry date.")
            let field = refusal.body["field"]?.string == "expiresOn" ? "expiresOn" : "lotCode"
            form.errors = [field: message]
            form.scrollTarget = nil
            form.scrollTarget = field
            Toast.error(message)
        } catch {
            let gone = (error as? StockRefusal).map { $0.code == "product_archived" || $0.status == 404 } ?? false
            let connection = stockIsConnectionError(error)
            saveError = (connection
                ? L("We could not reach PawMiaw, so this may not be saved. Your delivery is still here: try again — it is never added twice.")
                : stockErrorText(error, fallback: L("Could not record the delivery.")), gone, connection)
            Toast.error(saveError?.message ?? "")
        }
    }
}

/// A new product to create from the delivery: the code that matched nothing and what its label said.
struct StockCreateTarget: Identifiable {
    let id = UUID()
    var barcode: String? = nil
    var lot: String? = nil
    var expiresOn: String? = nil
}
