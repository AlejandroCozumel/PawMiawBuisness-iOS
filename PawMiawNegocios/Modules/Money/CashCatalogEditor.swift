//
//  CashCatalogEditor.swift
//  PawMiawNegocios
//
//  Add or edit one catalog item (web: provider-catalog-sheet.tsx,
//  catalog-page/catalog-form.ts, catalog-sheet-sections.tsx): its photo,
//  name, category, SKU, kind of product (and, for a medicine, its group or
//  controlled class), price and tax, and — for a product — its stock: counted
//  on the shelf, or drawn from another product as a pack. A new product and
//  its stock go in one request with one request id per sheet, so a save whose
//  answer was lost never makes the item twice; a later save carries on with
//  the item this sheet already made.
//
//  The SKU and the barcode can be scanned (Design/BarcodeScanner.swift); a
//  code another item already has is said before saving, and a scanned SKU can
//  be the barcode too. A delivery opens it to create the product that just
//  arrived (`init(initialBarcode:onCreated:)`, web receive-stock-sheet.tsx →
//  ProviderCatalogSheet preset "product"): it starts with the scanned code as
//  its barcode, loads its own categories and settings, and hands the saved
//  item back so the delivery carries on receiving it.
//

import SwiftUI

struct CashCatalogEditorSheet: View {
    let item: CashCatalogItem?
    /// The kind it opens on; nil asks first (web: the "New item" button's first step).
    let kind: String?
    let duplicateOf: CashCatalogItem?
    let categories: [CashCategory]
    let settings: CashStoreSettings?
    let onSaved: () -> Void
    /// A new product starts with this barcode (a scanned code no product had).
    var initialBarcode: String? = nil
    /// The item as the server saved it, before the sheet closes (for whoever carries on with it).
    var onCreated: ((CashCatalogItem) -> Void)? = nil
    /// Opened from a delivery: a product, its lists loaded here, and words about carrying on receiving it.
    var forDelivery: Bool = false
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var name = ""
    @State private var categoryId = ""
    @State private var sku = ""
    @State private var price: Int?
    @State private var description = ""
    @State private var active = true
    @State private var taxTreatment = "default"
    @State private var taxRate = ""
    @State private var productKind = ""
    @State private var requiresPrescription = false
    @State private var controlSchedule: String?
    @State private var trackInventory = false
    @State private var barcode = ""
    @State private var storageLocation = ""
    @State private var unitCost: Int?
    @State private var quantity = ""
    @State private var countedFrom: Int?
    @State private var lowStockAlert = true
    @State private var reorderPoint = "3"
    @State private var reorderQuantity = ""
    @State private var allowBackorder = false
    @State private var packId: String?
    @State private var packName: String?
    @State private var packUnits = 1
    @State private var pickingPack = false
    @State private var photo = PhotoDraft()
    @State private var newCategory = ""
    @State private var addingCategory = false
    @State private var extraCategories: [CashCategory] = []
    @State private var working = false
    @State private var started = false
    /// A SKU the camera read: offered as the barcode too.
    @State private var skuScanned: String?
    /// Another item with the SKU or the barcode typed or scanned here, said before saving.
    @State private var skuTwin: (code: String, name: String)?
    @State private var barcodeTwin: (code: String, name: String)?
    @State private var loadedCategories: [CashCategory] = []
    @State private var loadedSettings: CashStoreSettings?
    @State private var requestId = "catalog-\(cashRequestId())"
    @State private var stockRequest: (key: String, id: String)?
    /// The item this sheet already made: a second save carries on with it.
    @State private var madeId: String?
    /// The kind chosen on the first step of a "New item".
    @State private var chosenKind: String?
    /// The part of a new item shown ("kind", "details", "price", "stock").
    @State private var step = "details"
    /// The item is saved but its stock settings are not: the button tries that part again.
    @State private var partlySaved = false

    /// The kind being written: the one it opened on, or the one chosen.
    private var itemKind: String { kind ?? chosenKind ?? "service" }
    private var kindChosen: Bool { kind != nil || chosenKind != nil }
    private var isProduct: Bool { itemKind == "product" }
    private var canEditInventory: Bool { workspace.can(.inventoryEdit) }
    private var isPack: Bool { isProduct && packId != nil }
    private var packPending: Bool { isProduct && pickingPack && packId == nil }
    private var tracksOwnStock: Bool { isProduct && trackInventory && !isPack && !packPending }
    private var medication: Bool { isProduct && productKind == "medication" }
    private var controlled: Bool { medication && controlSchedule != nil }
    private var mexico: Bool { workspace.current?.country?.uppercased() == "MX" }
    private var seesCost: Bool { workspace.moneyLevel >= .finances || workspace.can(.catalogEdit) }
    private var storeSettings: CashStoreSettings? { settings ?? loadedSettings }
    private var typeCategories: [CashCategory] { (categories + loadedCategories + extraCategories).filter { $0.itemType == itemKind && ($0.active || $0.id == categoryId) } }

    /// A new item's steps (web: "kind" unless the caller fixed it, then its parts); an item being edited has none.
    private var sections: [String] { isProduct ? ["details", "price", "stock"] : ["details", "price"] }
    private var steps: [String] { item != nil ? [] : (kind == nil ? ["kind"] : []) + sections }
    private var stepIndex: Int { max(0, steps.firstIndex(of: step) ?? 0) }
    private var isLastStep: Bool { item != nil || stepIndex == steps.count - 1 }
    private var choosing: Bool { item == nil && step == "kind" }

    private func stepName(_ value: String) -> String {
        switch value {
        case "kind": L("Kind")
        case "details": L("What it is")
        case "price": L("Price and tax")
        default: L("Stock")
        }
    }

    private func stepIcon(_ value: String) -> String {
        switch value {
        case "kind": "shapes"
        case "details": "tag"
        case "price": "banknote"
        default: "boxes"
        }
    }

    private var primaryTitle: String {
        guard isLastStep && !choosing else { return L("Continue") }
        if partlySaved { return L("Try again") }
        return item == nil && madeId == nil ? (isProduct ? L("Add product") : L("Add service")) : L("Save changes")
    }

    var body: some View {
        ProviderModal(
            title: item.map { LF("Edit %@", $0.name) } ?? (!kindChosen ? L("New item") : isProduct ? L("New product") : L("New service")),
            subtitle: !kindChosen ? L("A service or a product: choose which, then fill in its details.")
                : isProduct ? L("Its price and tax, what kind of product it is, and the stock behind it.")
                : L("What a visit, a groom or a night costs, ready for invoices and the counter."),
            systemImage: kindChosen ? CashCatalogLook.kindIcon(itemKind) : "plus",
            accent: kindChosen ? .hue(CashCatalogLook.hue(itemKind)) : .butter,
            isDirty: started && (dirty || chosenKind != nil || (item == nil && stepIndex > 0)), form: form,
            primaryTitle: primaryTitle,
            isWorking: working,
            cancelTitle: partlySaved ? L("Close") : L("Cancel"),
            steps: steps.count > 1 ? ModalSteps(steps: steps.map { (stepName($0), stepIcon($0)) }, current: stepIndex) : nil,
            onBack: item == nil && stepIndex > 0 ? { step = steps[stepIndex - 1] } : nil,
            primaryIcon: isLastStep && !choosing ? (partlySaved ? "rotate-cw" : item != nil ? "save" : "plus") : nil,
            primaryDisabled: choosing && !kindChosen,
            onPrimary: { primary() }
        ) {
            if !started {
                LoadingState()
            } else if choosing {
                kindStep
            } else {
                contextPills
                if item != nil { jumps }
                if forDelivery {
                    Text(L("It is added to the Catalog and you carry on receiving it.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                if item != nil {
                    detailsSection
                    priceSection
                    if isProduct { stockSection }
                    availabilitySection
                } else {
                    switch step {
                    case "price": priceSection
                    case "stock": stockSection
                    default: detailsSection
                    }
                    if isLastStep { availabilitySection }
                }
            }
        }
        .onAppear(perform: start)
        .task { await loadLists() }
    }

    /// Next (web `goNext`): the step's own fields are checked before the next one opens.
    private func primary() {
        if choosing {
            if kindChosen { step = "details" }
            return
        }
        guard !isLastStep else { save(); return }
        guard form.check(rules.filter { $0.section == step }.map { ($0.key, $0.message) }) else { return }
        step = steps[stepIndex + 1]
    }

    /// Editing is one page: these bring each part into view (web: the row of jumps).
    private var jumps: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sections + ["availability"], id: \.self) { section in
                    FilterChip(title: section == "availability" ? L("Availability") : stepName(section), isSelected: false) {
                        form.scrollTarget = nil
                        form.scrollTarget = "section-\(section)"
                    }
                }
            }
        }
        .accessibilityLabel(L("Jump to a section"))
    }

    /// "What are you adding?" (web `CatalogKindStep`, an `OptionCardGrid`): a service or a product; a tap opens its form.
    private var kindStep: some View {
        ModalSection(title: L("What are you adding?"), subtitle: L("Each kind has its own details: a product has stock.")) {
            OptionCards(options: ["service", "product"].map { type in
                OptionCard(type, title: type == "product" ? L("Product") : L("Service"),
                           description: type == "product" ? L("Food, medicine or supplies, with stock") : L("A visit, a groom, a night — what you charge for"),
                           icon: CashCatalogLook.kindIcon(type), accent: CashCatalogLook.hue(type).color)
            }, selection: Binding(get: { kindChosen ? itemKind : nil }, set: { next in
                guard let type = next else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    if chosenKind != nil && chosenKind != type {
                        // Categories belong to services or to products.
                        categoryId = ""
                        addingCategory = false
                        newCategory = ""
                    }
                    if type != "product" { pickingPack = false }
                    chosenKind = type
                    if type == "product" { trackInventory = true }
                    step = "details"
                }
            }))
        }
    }

    /// What it is about (web `ModalContextPills`): the kind and, when editing or copying, the item.
    private var contextPills: some View {
        FlowLayout(spacing: 6) {
            Chip(text: isProduct ? L("Product") : L("Service"), tone: .muted, icon: CashCatalogLook.kindIcon(itemKind))
            if let item {
                Chip(text: item.name, tone: .muted)
            } else if let typed = name.nonEmpty, step != "details" {
                Chip(text: typed.trimmingCharacters(in: .whitespacesAndNewlines), tone: .muted)
            }
            if let duplicateOf {
                Chip(text: LF("Copy of %@", duplicateOf.name), tone: .muted, icon: "copy")
            }
        }
    }

    private var dirty: Bool {
        name != (item?.name ?? "") || price != (item.map { $0.defaultUnitAmount > 0 ? $0.defaultUnitAmount : nil } ?? nil) || !description.isEmpty && description != (item?.description ?? "")
            || sku != (item?.sku ?? "") || !photo.isEmpty || packId != item?.stockCatalogItemId
            || barcode != (item?.inventory?.barcode ?? (item == nil ? initialBarcode ?? "" : ""))
    }

    @ViewBuilder private var detailsSection: some View {
        ModalSection(title: L("What it is")) {
            PhotoField(label: L("Photo"), hint: L("JPG, PNG or WebP, up to 3 MB."), currentURL: item?.photoUrl, draft: $photo, removeTitle: L("Remove the new photo"), removeSavedTitle: L("Remove photo"), removedNote: L("The photo is removed when you save."))
            PMTextField(L("Name"), text: $name, key: "name", form: form, prompt: isProduct ? L("e.g. Hypoallergenic dog food 2 kg") : L("e.g. Annual wellness exam"), required: true)
            FormField(label: L("Category"), key: "category", form: form) {
                Menu {
                    Button(L("Uncategorized")) { categoryId = "" }
                    ForEach(typeCategories) { entry in Button(entry.active ? entry.name : "\(entry.name) (\(L("inactive")))") { categoryId = entry.id } }
                    Divider()
                    Button { addingCategory = true } label: { GlyphLabel(L("+ New category"), icon: "plus") }
                } label: {
                    HStack {
                        Text(typeCategories.first { $0.id == categoryId }?.name ?? L("Uncategorized")).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                        Spacer()
                        Glyph("chevron-down", size: 16).foregroundStyle(Theme.inkSoft)
                    }
                    .fieldChrome()
                }
            }
            if addingCategory {
                PMTextField(isProduct ? L("New product category") : L("New service category"), text: $newCategory, key: "categoryName", form: form,
                            prompt: isProduct ? L("e.g. Food") : L("e.g. Grooming"), required: true)
                HStack(spacing: 8) {
                    PMButton(L("Cancel"), variant: .outline, size: .compact, fullWidth: true) { addingCategory = false; newCategory = "" }
                    PMButton(L("Save category"), systemImage: "plus", size: .compact, fullWidth: true) { saveCategory() }
                }
            }
            if isProduct {
                BarcodeField(label: L("SKU"), text: $sku, key: "sku", form: form, prompt: L("e.g. DF-2KG"), hint: L("Optional. Search finds it too."), capitalization: .characters) { scan in
                    skuScanned = scan.code
                    Task { await checkTwin(scan.code, format: scan.format, sku: true) }
                }
                if let skuTwin, skuTwin.code == sku {
                    NoticeCard(tone: .warning, title: LF("%@ already uses this SKU.", skuTwin.name),
                               message: L("Two items cannot share a SKU: change it, or it will not be saved."))
                }
                if let scanned = skuScanned, scanned == sku, tracksOwnStock && canEditInventory {
                    if barcode.trimmingCharacters(in: .whitespaces).isEmpty {
                        HStack(spacing: 6) {
                            Text(LF("Scanned %@.", scanned)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                            Button(L("Also use it as the barcode")) { barcode = scanned; Task { await checkTwin(scanned, format: nil, sku: false) } }
                                .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue)
                                .frame(minHeight: 40)
                        }
                    } else if barcode == scanned {
                        HStack(spacing: 6) {
                            Glyph("check", size: 14)
                            Text(L("It is the barcode too."))
                        }
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
            } else {
                PMTextField(L("Internal code"), text: $sku, key: "sku", form: form, prompt: L("e.g. CONS-01"), hint: L("Optional. Search finds it too."), capitalization: .characters)
            }
            if isProduct {
                CashProductKindField(kind: Binding(get: { productKind }, set: { productKind = $0; if $0 != "medication" { controlSchedule = nil; requiresPrescription = false } }))
                if medication {
                    if mexico { mexicoGroups } else { controlledField }
                }
            }
            PMTextField(L("Description"), text: $description, prompt: L("Optional notes for the team: what it includes, when to offer it."), multiline: true)
        }
        .id("section-details")
    }

    /// The price, in the business currency, and how it is taxed (web `CatalogPriceSection`).
    @ViewBuilder private var priceSection: some View {
        let keepsNoPrice = item?.defaultUnitAmount == 0
        let lead = keepsNoPrice && price == nil ? L("No price yet: it will be asked for when charging. Add one here to stop asking.")
            : L("What staff see first on an invoice or at the counter. It can be changed on each sale.")
        ModalSection(title: L("Price and tax")) {
            MoneyField(label: L("Price"), cents: $price, key: "price", form: form,
                       hint: lead + " " + LF("In %@, the business currency, set in Settings.", storeSettings?.currency ?? workspace.currency), required: !keepsNoPrice)
            CashTaxField(treatment: $taxTreatment, rate: $taxRate, price: price, settings: storeSettings, form: form)
        }
        .id("section-price")
    }

    /// Whether it is offered on new sales (web `CatalogAvailabilitySection`).
    private var availabilitySection: some View {
        ModalSection(title: L("Availability")) {
            ToggleRow(title: active ? L("Active") : L("Archived"),
                      subtitle: active ? L("Offered on new invoices, visits and at the counter.") : L("Hidden from new sales. Past invoices keep it, and you can turn it back on any time."),
                      isOn: $active)
        }
        .id("section-availability")
    }

    /// Mexico: the box says Grupo I, II or III — one choice sets both rules (web `MexicoGroupField`).
    @ViewBuilder private var mexicoGroups: some View {
        let current = controlSchedule == "mx_group_1" ? "group_1" : requiresPrescription ? "group_2" : "group_3"
        let groups: [(value: String, title: String, body: String, tone: Color)] = [
            ("group_1", L("Group I · quantified prescription"), L("Controlled: sold only against its own prescription on the official pad, and every unit goes to the control log."), Theme.destructive),
            ("group_2", L("Group II · simple prescription"), L("Prescription only: sold to a client for a specific pet, never over the counter to a walk-in."), Theme.pink),
            ("group_3", L("Group III · free sale"), L("Sold over the counter, with no prescription."), ProviderState.done.color),
        ]
        FormField(label: L("Group (NOM-064)"), hint: L("It is printed on the box: it decides whether it needs a prescription and whether it is controlled.")) {
            VStack(spacing: 8) {
                ForEach(groups, id: \.value) { group in
                    let chosen = current == group.value
                    Button {
                        controlSchedule = group.value == "group_1" ? "mx_group_1" : nil
                        requiresPrescription = group.value != "group_3"
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Circle().fill(group.tone).frame(width: 8, height: 8)
                                Text(group.title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            }
                            Text(group.body).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.leading)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(chosen ? AnyShapeStyle(Theme.wash(group.tone, 12)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(chosen ? AnyShapeStyle(Theme.mix(group.tone, 60, with: Theme.inkStrong)) : AnyShapeStyle(Theme.borderSoft), lineWidth: 2))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder private var controlledField: some View {
        ToggleRow(title: L("Prescription only"), subtitle: controlled ? L("A controlled medicine: always prescription-only.") : L("Only sold to a client for a specific pet, never over the counter to a walk-in."),
                  isOn: Binding(get: { requiresPrescription || controlled }, set: { requiresPrescription = $0 }))
        MenuField(label: L("Controlled medicine"), options: [(value: "", title: L("Not controlled"))] + CashCatalogText.schedules.map { (value: $0, title: CashCatalogText.schedule($0)) },
                  selection: Binding(get: { controlSchedule ?? "" }, set: { controlSchedule = $0.nonEmpty; if $0.nonEmpty != nil { requiresPrescription = true } }))
        Text(L("Sold only against a controlled prescription; every unit goes to the control log.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
    }

    @ViewBuilder private var stockSection: some View {
        ModalSection(title: L("Stock")) {
            CashPackField(stockItemId: $packId, stockItemName: $packName, units: $packUnits, picking: $pickingPack, excludeId: item?.id, form: form)
            if !isPack && !pickingPack {
                ToggleRow(title: L("Track stock"), subtitle: L("Count what is on the shelf, get a warning at the reorder point, and log every sale and delivery."), isOn: Binding(get: { trackInventory }, set: { trackInventory = $0; form.clear("trackInventory") }))
                    .id("trackInventory")
                if let error = form.error("trackInventory") { Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
            }
            if forDelivery && tracksOwnStock && !canEditInventory {
                Text(L("Its stock settings are set by someone who can change Inventory. Receiving this delivery starts counting it."))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
            if tracksOwnStock && canEditInventory {
                if controlled {
                    NoticeCard(tone: .custom(Theme.pink), title: L("Controlled medicine: its stock is not typed here."),
                               message: item?.inventory != nil ? L("It is received, counted and written off in Inventory, where each unit has its lot and expiry for the controlled register.")
                                   : L("Save it, then receive it in Inventory with its lot and expiry: that is what opens its controlled register."), icon: nil)
                    PMTextField(item?.inventory == nil ? L("Starting quantity") : L("Quantity on hand"), text: .constant("\(item?.inventory?.quantityOnHand ?? 0)"))
                        .disabled(true)
                } else {
                    PMTextField(item?.inventory == nil ? L("Starting quantity") : L("Quantity on hand"), text: $quantity, key: "quantity", form: form, prompt: "12",
                                hint: forDelivery ? L("What is on the shelf before this delivery: usually 0.") : item?.inventory != nil ? L("Changing it records a count.") : nil, keyboard: .numberPad, required: true)
                }
                if lowStockAlert {
                    PMTextField(L("Reorder point"), text: $reorderPoint, key: "reorderPoint", form: form, prompt: "3", hint: L("At or below this, it shows as needing restocking."), keyboard: .numberPad, required: true)
                }
                PMTextField(L("Reorder quantity"), text: $reorderQuantity, key: "reorderQuantity", form: form, prompt: "12", hint: L("How many you usually order."), keyboard: .numberPad)
                if seesCost { MoneyField(label: L("Unit cost"), cents: $unitCost, key: "unitCost", form: form, hint: L("What you pay per unit; it values your stock.")) }
                BarcodeField(label: L("Barcode"), text: $barcode, key: "barcode", form: form, prompt: L("Scan or type it")) { scan in
                    Task { await checkTwin(scan.code, format: scan.format, sku: false) }
                }
                if let barcodeTwin, barcodeTwin.code == barcode, form.error("barcode") == nil {
                    NoticeCard(tone: .warning, title: LF("%@ already has this barcode.", barcodeTwin.name),
                               message: L("Two products cannot share a barcode: change it, or it will not be saved."))
                }
                PMTextField(L("Where it is kept"), text: $storageLocation, prompt: L("e.g. Front shelf A2"))
                ToggleRow(title: L("Mark it low on Home and Inventory"),
                          subtitle: lowStockAlert ? L("It shows as needing restocking at the reorder point, here, at the counter and on Home.") : L("Never flagged as low: it only shows once it is out of stock."),
                          isOn: Binding(get: { lowStockAlert }, set: { on in
                              lowStockAlert = on
                              if on && reorderPoint.trimmingCharacters(in: .whitespaces).isEmpty { reorderPoint = "3" }
                              form.clear("reorderPoint")
                          }))
                ToggleRow(title: L("Allow backorders"), subtitle: L("Keep selling when the count reaches zero. Leave it off to stop at zero."), isOn: $allowBackorder)
            } else if tracksOwnStock && !forDelivery {
                Text(L("Stock is tracked for this product, but your role cannot change stock settings here."))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1.5))
            }
        }
        .id("section-stock")
    }

    private func start() {
        guard !started else { return }
        step = kind == nil && item == nil ? "kind" : "details"
        let source = item ?? duplicateOf
        name = item?.name ?? duplicateOf.map { String(LF("%@ (copy)", $0.name).prefix(140)) } ?? ""
        categoryId = source?.category?.id ?? ""
        sku = item?.sku ?? ""
        price = source.flatMap { $0.defaultUnitAmount > 0 ? $0.defaultUnitAmount : nil }
        description = source?.description ?? ""
        active = item?.active ?? true
        taxTreatment = source?.taxTreatment ?? "default"
        taxRate = source?.taxTreatment == "standard" ? CashCatalogRules.rateText(source?.taxRateBps) : ""
        productKind = source?.productKind ?? ""
        requiresPrescription = source?.requiresPrescription ?? false
        controlSchedule = source?.controlSchedule
        trackInventory = source?.trackInventory ?? (kind == "product")
        packId = source?.stockCatalogItemId
        packUnits = max(1, source?.stockUnits ?? 1)
        if let inventory = item?.inventory {
            barcode = inventory.barcode ?? ""
            storageLocation = inventory.storageLocation ?? ""
            unitCost = inventory.unitCostAmount
            quantity = "\(inventory.quantityOnHand)"
            countedFrom = inventory.quantityOnHand
            lowStockAlert = inventory.lowStockAlert != false
            reorderPoint = "\(inventory.reorderPoint > 0 ? inventory.reorderPoint : 3)"
            reorderQuantity = inventory.reorderQuantity.map(String.init) ?? ""
            allowBackorder = inventory.allowBackorder
        } else if item == nil, let initialBarcode = initialBarcode?.nonEmpty {
            barcode = initialBarcode
            Task { await checkTwin(initialBarcode, format: nil, sku: false) }
        }
        started = true
    }

    /// Opened from a delivery: the categories and the Store's tax settings, which the Catalog would have handed over.
    private func loadLists() async {
        guard forDelivery else { return }
        if categories.isEmpty, let list: CashCategoryList = try? await API.get("/provider-catalog/categories") { loadedCategories = list.items }
        if settings == nil { loadedSettings = try? await API.get("/provider-store/settings") }
    }

    /// Another item already has this code: said here, before the server refuses it on save
    /// (web useDuplicateCode). A barcode is looked up in each of its spellings; no warning is better than a wrong one.
    private func checkTwin(_ code: String, format: String?, sku isSku: Bool) async {
        if isSku { skuTwin = nil } else { barcodeTwin = nil }
        let own = item?.id ?? madeId
        let search: (String) async throws -> [CashProduct] = { text in try await API.get("/provider-store/products", query: ["q": text]) }
        if isSku {
            guard let found = try? await search(code).first(where: { $0.catalogItemId != own && $0.sku?.trimmingCharacters(in: .whitespaces) == code }) else { return }
            if sku == code { skuTwin = (code, found.name) }
            return
        }
        for variant in Barcode.variants(code, format: format) {
            guard let rows = try? await search(variant) else { return }
            if let found = rows.first(where: { $0.catalogItemId != own && Barcode.same($0.barcode, variant) }) {
                if barcode == code { barcodeTwin = (code, found.name) }
                return
            }
        }
    }

    private func saveCategory() {
        guard let text = newCategory.nonEmpty else { _ = form.check([("categoryName", L("Add the category name first."))]); return }
        Task {
            do {
                let created: CashCategory = try await API.post("/provider-catalog/categories", body: ["itemType": itemKind, "name": text, "active": true])
                extraCategories.append(created)
                categoryId = created.id
                addingCategory = false
                newCategory = ""
                Toast.show(LF("%@ is ready to use.", created.name))
            } catch {
                form.apply(error, known: ["name": "categoryName"])
            }
        }
    }

    /// What is checked, part by part (web `validateCatalogForm` + `SECTION_OF_ERROR`), in the order the fields appear.
    private var rules: [(section: String, key: String, message: String?)] {
        let ownRate = taxTreatment == "standard" ? CashCatalogRules.rateBps(taxRate) : nil
        let stockChecked = tracksOwnStock && canEditInventory
        return [
            ("details", "name", name.nonEmpty == nil ? L("Add the name first.") : nil),
            ("details", "categoryName", addingCategory ? (newCategory.nonEmpty == nil ? L("Add the category name first.") : L("Save the new category first or cancel it before saving this item.")) : nil),
            ("price", "price", CashCatalogRules.priceError(price, item: item)),
            ("price", "taxRate", taxTreatment == "standard" && ownRate == nil ? L("Enter a tax rate from 0 to 100.") : nil),
            ("stock", "packProduct", packPending ? L("Choose the product this pack draws on, or turn the pack off.") : nil),
            ("stock", "quantity", stockChecked && !controlled ? (quantity.isEmpty ? L("Add the starting quantity on hand.") : Int(quantity) == nil ? L("Add a valid stock count.") : nil) : nil),
            ("stock", "reorderPoint", stockChecked && lowStockAlert && Int(reorderPoint) == nil ? L("Add the reorder point.") : nil),
            ("stock", "reorderQuantity", stockChecked && !reorderQuantity.isEmpty && Int(reorderQuantity) == nil ? L("Add a valid reorder quantity.") : nil),
        ]
    }

    private func save() {
        let ownRate = taxTreatment == "standard" ? CashCatalogRules.rateBps(taxRate) : nil
        let stockChecked = tracksOwnStock && canEditInventory
        let existing = item?.id ?? madeId
        let checks = rules
        // A new item goes back to the first step that has something to fix.
        if item == nil, let first = checks.first(where: { $0.message != nil }), sections.contains(first.section) { step = first.section }
        guard form.check(checks.map { ($0.key, $0.message) }) else { return }
        let payload: [String: Any?] = [
            "itemType": itemKind,
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "providerCatalogCategoryId": categoryId.nonEmpty,
            "sku": sku.nonEmpty,
            "defaultUnitAmount": price ?? 0,
            "description": description.nonEmpty,
            "active": active,
            "trackInventory": isProduct && !isPack ? trackInventory : false,
            "productKind": isProduct ? productKind.nonEmpty : nil,
            "taxTreatment": taxTreatment,
            "taxRateBps": ownRate,
            "requiresPrescription": medication ? (requiresPrescription || controlled) : false,
            "controlSchedule": medication ? controlSchedule : nil,
            "stockCatalogItemId": isProduct ? packId : nil,
            "stockUnits": isPack ? packUnits : 1,
        ]
        var inventory: [String: Any?]? = nil
        if stockChecked {
            var stock: [String: Any?] = [
                "barcode": barcode.nonEmpty,
                "storageLocation": storageLocation.nonEmpty,
                "quantityOnHand": controlled ? (item?.inventory?.quantityOnHand ?? 0) : Int(quantity) ?? 0,
                "reorderPoint": lowStockAlert ? Int(reorderPoint) ?? 0 : 0,
                "lowStockAlert": lowStockAlert,
                "reorderQuantity": Int(reorderQuantity),
                "allowBackorder": allowBackorder,
            ]
            if seesCost { stock["unitCostAmount"] = unitCost }
            if item?.inventory != nil {
                // With stock set up, a count is what differs from what the form showed; the same figures keep their id.
                stock["countedFrom"] = countedFrom ?? item?.inventory?.quantityOnHand
                let key = "\(stock["quantityOnHand"] as? Int ?? 0)|\(countedFrom ?? 0)"
                if stockRequest?.key != key { stockRequest = (key, "catalog-\(cashRequestId())") }
                stock["clientRequestId"] = stockRequest?.id
            }
            inventory = stock
        }
        working = true
        Task {
            defer { working = false }
            do {
                var savedJSON: JSONValue
                if let existing {
                    savedJSON = try await API.patch("/provider-catalog/\(existing)", body: payload)
                } else {
                    var body = payload
                    body["clientRequestId"] = requestId
                    if let inventory { body["inventory"] = inventory }
                    savedJSON = try await API.post("/provider-catalog", body: body)
                    madeId = savedJSON["id"]?.string
                }
                guard let savedId = savedJSON["id"]?.string ?? existing else { throw APIError.offline() }
                if existing != nil, let inventory {
                    do {
                        let _: EmptyResponse = try await API.patch("/provider-catalog/\(savedId)/inventory", body: inventory)
                    } catch {
                        if showStockRefusal(error) { return }
                        // The item is saved; only its stock settings are not. Trying again carries on from here.
                        partlySaved = true
                        announceDataChanged()
                        onSaved()
                        Toast.error(L("Saved the product, but its stock could not be set. Try again."))
                        return
                    }
                }
                partlySaved = false
                await applyPhoto(itemId: savedId)
                Toast.show(item == nil ? LF("%@ was added to the catalog.", name) : LF("%@ was updated.", name))
                if let onCreated {
                    // As saved, photo included; the save's own answer when that can't be read.
                    let fresh: CashCatalogItem? = (try? await API.get("/provider-catalog/\(savedId)"))
                        ?? (try? API.decoder.decode(CashCatalogItem.self, from: API.encoder.encode(savedJSON)))
                    if let fresh { onCreated(fresh) }
                }
                announceDataChanged()
                onSaved()
                dismiss()
            } catch {
                if showStockRefusal(error) { return }
                if cashErrorCode(error) == "sku_taken" {
                    if item == nil { step = "details" }
                    _ = form.check([("sku", errorText(error))])
                    return
                }
                if existing == nil, (error as? APIError)?.isOffline == true {
                    // The request id makes a second try safe.
                    Toast.error(L("We could not reach PawMiaw, so this may not be saved. Try again — it is never added twice."))
                    return
                }
                form.apply(error, known: ["name": "name", "sku": "sku", "defaultUnitAmount": "price", "taxRateBps": "taxRate", "barcode": "barcode", "quantityOnHand": "quantity", "reorderPoint": "reorderPoint", "stockCatalogItemId": "packProduct"])
            }
        }
    }

    /// Sends the photo picked (or takes the saved one away) once the item exists.
    private func applyPhoto(itemId: String) async {
        if let data = photo.data {
            do {
                let _: EmptyResponse = try await ImageUpload.upload(data, to: "/provider-catalog/\(itemId)/photo")
            } catch {
                Toast.error(L("The item was saved, but the photo did not upload. You can add it again later."))
            }
        } else if photo.removed && item?.photoUrl != nil {
            do {
                try await API.send("DELETE", "/provider-catalog/\(itemId)/photo")
            } catch {
                Toast.error(L("The item was saved, but its photo could not be removed. Try again later."))
            }
        }
    }

    /// A refusal about the stock part, under its field: a barcode another product has, a
    /// count from a figure the shelf no longer holds (the new one is counted from next), units still on the shelf.
    private func showStockRefusal(_ error: Error) -> Bool {
        guard let refusal = CashCatalogRules.stockRefusal(error) else { return false }
        if item == nil, sections.contains("stock") { step = "stock" }
        var field = refusal.0
        if field == "trackInventory" && (pickingPack || packId != nil) { field = "packProduct" }
        if field == "quantity", let id = item?.id ?? madeId {
            stockRequest = nil
            Task {
                if let fresh: CashCatalogItem = try? await API.get("/provider-catalog/\(id)") { countedFrom = fresh.inventory?.quantityOnHand }
            }
        }
        _ = form.check([(field, refusal.1)])
        return true
    }
}

extension CashCatalogEditorSheet {
    /// "Crear el producto" from a delivery: a new product starting with the code that matched
    /// nothing, handed back once saved so the delivery carries on receiving it.
    init(initialBarcode: String?, onCreated: @escaping (CashCatalogItem) -> Void) {
        self.init(item: nil, kind: "product", duplicateOf: nil, categories: [], settings: nil, onSaved: {},
                  initialBarcode: initialBarcode, onCreated: onCreated, forDelivery: true)
    }
}

/// The catalog's words for controlled classes.
enum CashCatalogText {
    static let schedules = ["mx_group_1", "us_c2", "us_c3", "us_c4", "us_c5", "controlled_other"]

    static func schedule(_ value: String) -> String {
        switch value {
        case "mx_group_1": L("Group I (quantified prescription)")
        case "us_c2": L("Schedule II (C-II)")
        case "us_c3": L("Schedule III (C-III)")
        case "us_c4": L("Schedule IV (C-IV)")
        case "us_c5": L("Schedule V (C-V)")
        default: L("Controlled")
        }
    }
}

/// What kind of product it is (web `ProductKindField`): one of a row of
/// choices, each with its icon on a chip in its colour; a second tap clears it.
private struct CashProductKindField: View {
    @Binding var kind: String

    private static let kinds = ["medication", "food", "supply", "accessory", "other"]

    var body: some View {
        FormField(label: L("Kind of product"), hint: kind == "medication" ? L("Sold to a PawMiaw family for their pet, a medication lands in the pet’s cabinet with its lot and expiry.") : nil, optional: true) {
            FlowLayout(spacing: 8) {
                ForEach(Self.kinds, id: \.self) { value in
                    let chosen = kind == value
                    let tone = CashCatalogLook.productHue(value).color
                    Button { kind = chosen ? "" : value } label: {
                        HStack(spacing: 8) {
                            Glyph(CashCatalogLook.productIcon(value), size: 16)
                                .foregroundStyle(chosen ? Theme.inkOnBright : Theme.inkStrong)
                                .frame(width: 32, height: 32)
                                .background(chosen ? AnyShapeStyle(tone) : AnyShapeStyle(Theme.wash(tone, 26)), in: Circle())
                            Text(title(value)).lineLimit(1)
                            if chosen { Glyph("check", size: 16) }
                        }
                        .font(Theme.text(14, weight: .bold))
                        .foregroundStyle(chosen ? Theme.inkStrong : Theme.inkSoft)
                        .padding(.leading, 8)
                        .padding(.trailing, 14)
                        .frame(height: 48)
                        .background(chosen ? AnyShapeStyle(Theme.wash(tone, 18)) : AnyShapeStyle(Theme.surface), in: Capsule())
                        .overlay(Capsule().strokeBorder(chosen ? AnyShapeStyle(Theme.mix(tone, 60, with: Theme.inkStrong)) : AnyShapeStyle(Theme.borderSoft), lineWidth: 2))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
        }
    }

    private func title(_ value: String) -> String {
        switch value {
        case "medication": L("Medication")
        case "food": L("Food")
        case "supply": L("Supply")
        case "accessory": L("Accessory")
        default: L("Other@product")
        }
    }
}
