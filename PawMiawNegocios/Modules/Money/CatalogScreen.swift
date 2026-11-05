//
//  CatalogScreen.swift
//  PawMiawNegocios
//
//  Catálogo (web: routes/provider.catalog.tsx, catalog-page/catalog-screen.tsx,
//  catalog-rows.tsx, catalog-categories-panel.tsx): the services and products
//  the business charges for — their prices, tax, categories and stock. The
//  module header counts each kind and what needs restocking (those numbers
//  filter the list); one card holds the kind switch, the search, the filter
//  chips and sort, the bulk bar and the rows; below, the categories and what
//  each kind of visit charges by default (CashServiceDefaults.swift). The
//  editor is CashCatalogEditor.swift; bulk changes CashCatalogBulk.swift;
//  CSV import CashCatalogCSV.swift.
//

import SwiftUI

private enum CashCatalogSort: String, CaseIterable { case name, recent, price, priceDesc, stock }

/// What a catalog item looks like everywhere (web catalog-bits.tsx): its
/// kind's colour (services sky, products peach), its icon, its stock.
enum CashCatalogLook {
    static func hue(_ itemType: String) -> Hue { itemType == "product" ? .peach : .sky }
    static func tone(_ itemType: String) -> ChipTone { .hue(hue(itemType)) }

    /// A product kind's icon (web `KIND_ICONS`); a service's briefcase.
    static func productIcon(_ kind: String?) -> String {
        switch kind {
        case "medication": "pill"
        case "food": "paw-print"
        case "supply": "boxes"
        case "accessory": "shopping-bag"
        case "other": "sparkles"
        default: "package"
        }
    }

    static func icon(_ item: CashCatalogItem) -> String {
        item.isProduct ? productIcon(item.productKind) : "briefcase-medical"
    }

    static func kindIcon(_ itemType: String) -> String { itemType == "product" ? "package" : "briefcase-medical" }

    /// A product kind's colour (web `PRODUCT_KIND_HUE`).
    static func productHue(_ kind: String) -> Hue {
        switch kind {
        case "medication": .sky
        case "food": .butter
        case "supply": .teal
        case "accessory": .lavender
        default: .grey
        }
    }

    /// Where an item's stock stands (web `stockState`).
    enum Stock {
        case none, untracked, setup
        case pack(units: Int)
        case out(quantity: Int, reorderPoint: Int, backorder: Bool)
        case expired(quantity: Int)
        case low(quantity: Int, reorderPoint: Int, expired: Int)
        case ok(quantity: Int, location: String?, expired: Int)
    }

    static func stock(_ item: CashCatalogItem) -> Stock {
        guard item.isProduct else { return .none }
        if item.isPack { return .pack(units: item.stockUnits ?? 1) }
        guard item.trackInventory else { return .untracked }
        guard let inventory = item.inventory else { return .setup }
        if inventory.quantityOnHand <= 0 {
            return .out(quantity: inventory.quantityOnHand, reorderPoint: inventory.lowStockAlert == false ? 0 : inventory.reorderPoint, backorder: inventory.allowBackorder)
        }
        let expired = max(0, inventory.expiredUnits ?? 0)
        if expired >= inventory.quantityOnHand { return .expired(quantity: inventory.quantityOnHand) }
        if inventory.lowStock && inventory.reorderPoint > 0 && inventory.lowStockAlert != false {
            return .low(quantity: inventory.quantityOnHand, reorderPoint: inventory.reorderPoint, expired: expired)
        }
        return .ok(quantity: inventory.quantityOnHand, location: inventory.storageLocation?.nonEmpty, expired: expired)
    }

    /// Nothing left to sell, or at the reorder point: a reason to reorder.
    static func needsRestock(_ item: CashCatalogItem) -> Bool {
        switch stock(item) {
        case .low, .out, .expired: true
        default: false
        }
    }

    /// The short line under a price: tax in it, on top of it, or not charged (web `taxNote`).
    static func taxNote(_ item: CashCatalogItem, _ settings: CashStoreSettings?) -> String {
        if item.taxTreatment == "exempt" { return L("Tax exempt") }
        let rate: Int?
        switch item.taxTreatment {
        case "zero": rate = 0
        case "standard": rate = item.taxRateBps ?? 0
        default: rate = settings?.defaultTaxRateBps
        }
        guard let rate else { return L("Standard tax") }
        if rate == 0 { return L("0% tax") }
        if settings?.pricesIncludeTax ?? true { return LF("Incl. %@ tax", cashRate(rate)) }
        return LF("+ %@ tax", cashRate(rate))
    }
}

struct CatalogScreen: View {
    /// Open this item's editor once the catalog is read (the counter's "Open in the Catalog").
    var openItemId: String? = nil
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var items: [CashCatalogItem] = []
    @State private var total = 0
    @State private var categories: [CashCategory] = []
    @State private var categoryMeta: [String: CashCategoryMeta] = [:]
    @State private var categoriesLoaded = false
    @State private var settings: CashStoreSettings?
    @State private var services: CashServiceCatalog?
    @State private var loading = true
    @State private var error: String?
    @State private var view = "all"
    @State private var search = ""
    @State private var category: String?
    @State private var archived = false
    @State private var lowOnly = false
    @State private var noPrice = false
    /// The sort asked for; nil is the usual one (name, or the emptiest shelf on "Needs restocking").
    @State private var sortChoice: CashCatalogSort?
    @State private var shown = 20
    @State private var creating: String?
    @State private var editing: CashCatalogItem?
    @State private var duplicating: CashCatalogItem?
    @State private var archiving: CashCatalogItem?
    @State private var pricing: CashCatalogItem?
    /// On a phone the ticks show only while choosing (an iPad always shows them).
    @State private var selecting = false
    @State private var picked: Set<String> = []
    @State private var bulk: String?
    @State private var managing = false
    @State private var importing = false
    @State private var exported: CashSharedFile?
    @State private var pushed: ProviderRoute?
    @State private var openedItem = false
    /// The one item a link opened, for someone who cannot edit it: listed alone.
    @State private var focusId: String?

    private var canEdit: Bool { workspace.can(.catalogEdit) }
    private var canCreate: Bool { workspace.can(.catalogCreate) }
    private var canViewInventory: Bool { workspace.can(.inventoryView) }
    private var canReceive: Bool { canViewInventory && workspace.can(.inventoryReceive) }
    private var wide: Bool { sizeClass == .regular }
    private var ticks: Bool { canEdit && (wide || selecting) }

    private static func fold(_ text: String) -> String { text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).trimmingCharacters(in: .whitespaces) }

    /// Out, low or expired: a reason to reorder (Inventory's rule).
    static func needsRestock(_ item: CashCatalogItem) -> Bool { CashCatalogLook.needsRestock(item) }

    private var sort: CashCatalogSort { sortChoice ?? (lowOnly ? .stock : .name) }
    private var needle: String { Self.fold(search) }
    private var viewType: String? { view == "products" ? "product" : view == "services" ? "service" : nil }
    private var focusItem: CashCatalogItem? { focusId.flatMap { id in items.first { $0.id == id } } }

    private var listed: [CashCatalogItem] {
        if let focusItem { return [focusItem] }
        let needle = self.needle
        let rows = items.filter { item in
            (archived ? !item.active : item.active)
                && (view == "all" || item.itemType == viewType)
                && (!lowOnly || CashCatalogLook.needsRestock(item))
                && (!noPrice || (item.active && item.defaultUnitAmount == 0))
                && (category == nil || (category == "none" ? item.category == nil : item.category?.id == category))
                && (needle.isEmpty || [item.name, item.description, item.sku, item.inventory?.barcode, item.inventory?.storageLocation, item.category?.name].compactMap { $0 }.contains { Self.fold($0).contains(needle) })
        }
        let byName: (CashCatalogItem, CashCatalogItem) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        switch sort {
        case .name: return rows.sorted(by: byName)
        case .recent: return rows.sorted { ($0.updatedAt ?? "") == ($1.updatedAt ?? "") ? byName($0, $1) : ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
        case .price: return rows.sorted { $0.defaultUnitAmount == $1.defaultUnitAmount ? byName($0, $1) : $0.defaultUnitAmount < $1.defaultUnitAmount }
        case .priceDesc: return rows.sorted { $0.defaultUnitAmount == $1.defaultUnitAmount ? byName($0, $1) : $0.defaultUnitAmount > $1.defaultUnitAmount }
        case .stock:
            func key(_ item: CashCatalogItem) -> Int {
                switch CashCatalogLook.stock(item) {
                case .expired: 0
                case .out(let quantity, _, _), .low(let quantity, _, _), .ok(let quantity, _, _): quantity
                case .setup: -1
                default: Int.max
                }
            }
            return rows.sorted { key($0) == key($1) ? byName($0, $1) : key($0) < key($1) }
        }
    }

    private var selected: [CashCatalogItem] { canEdit ? listed.filter { picked.contains($0.id) } : [] }
    /// The kinds of visit that bill each item by default.
    private var visitsByItem: [String: [String]] {
        var map: [String: [String]] = [:]
        for service in services?.services ?? [] { if let id = service.defaultBillingItem?.id { map[id, default: []].append(service.label) } }
        return map
    }
    /// The active packs that draw on each product.
    private var packsByItem: [String: Int] {
        var map: [String: Int] = [:]
        for item in items where item.active && item.isPack { if let base = item.stockCatalogItemId { map[base, default: 0] += 1 } }
        return map
    }
    /// Items a visit bills by default or an active pack draws on.
    private var leanedOn: Set<String> { Set(visitsByItem.keys).union(packsByItem.keys) }
    private var hasFilters: Bool { narrowed || sortChoice != nil }
    private var narrowed: Bool { !search.isEmpty || category != nil || lowOnly || noPrice || archived || view != "all" }
    private var filterKey: String { "\(view)|\(search)|\(category ?? "")|\(archived)|\(lowOnly)|\(noPrice)|\(sort.rawValue)|\(focusId ?? "")" }

    private struct Summary {
        var services = 0, products = 0, restock = 0, out = 0, tracked = 0, archived = 0, archivedServices = 0, noPrice = 0
    }

    private var summary: Summary {
        var s = Summary()
        for item in items {
            guard item.active else {
                s.archived += 1
                if item.itemType == "service" { s.archivedServices += 1 }
                continue
            }
            if item.defaultUnitAmount == 0 { s.noPrice += 1 }
            if item.itemType == "service" { s.services += 1; continue }
            s.products += 1
            if item.trackInventory && !item.isPack { s.tracked += 1 }
            if CashCatalogLook.needsRestock(item) {
                s.restock += 1
                if case .out = CashCatalogLook.stock(item) { s.out += 1 }
            }
        }
        return s
    }

    var body: some View {
        Group {
            if !workspace.can(.catalogView) {
                PageScroll {
                    ModuleHeader(icon: "package", title: L("Catalog"), subtitle: L("What you charge for and what you sell — prices, tax and stock in one place."), accent: Theme.mango, storageKey: "catalog")
                    NoAccessState(message: L("This workspace is active, but your role does not include the catalog. Ask the workspace owner for access."))
                }
            } else {
                page
            }
        }
        .providerPage(L("Catalog"), root: true)
        .sheet(item: Binding(get: { creating.map { CashKind(kind: $0) } }, set: { creating = $0?.kind })) { kind in
            CashCatalogEditorSheet(item: nil, kind: kind.kind == "ask" ? nil : kind.kind, duplicateOf: nil, categories: categories, settings: settings) { Task { await load() } }
        }
        .sheet(item: $editing) { item in
            CashCatalogEditorSheet(item: item, kind: item.itemType, duplicateOf: nil, categories: categories, settings: settings) { Task { await load() } }
        }
        .sheet(item: $duplicating) { item in
            CashCatalogEditorSheet(item: nil, kind: item.itemType, duplicateOf: item, categories: categories, settings: settings) { Task { await load() } }
        }
        .sheet(item: $archiving) { item in CashArchiveSheet(item: item, visits: visitsByItem[item.id] ?? []) { Task { await load() } } }
        .sheet(item: $pricing) { item in CashCatalogPriceSheet(item: item, settings: settings) { Task { await load() } } }
        .sheet(item: Binding(get: { bulk.map { CashKind(kind: $0) } }, set: { bulk = $0?.kind })) { action in
            let done = { picked = []; selecting = false; Task { await load() } }
            switch action.kind {
            case "category": CashBulkCategorySheet(items: selected, categories: categories, onDone: done)
            case "price": CashBulkPriceSheet(items: selected, settings: settings, onDone: done)
            default: CashBulkArchiveSheet(items: selected, leanedOn: leanedOn, onDone: done)
            }
        }
        .sheet(isPresented: $managing) {
            CashCategoryManagerSheet(categories: categories, items: items, startType: viewType ?? "service") { Task { await load() } }
        }
        .sheet(isPresented: $importing) {
            CashCatalogImportSheet(items: items, categories: categories) { Task { await load() } }
        }
        .sheet(item: $exported) { file in ShareSheet(items: [file.url]).presentationDetents([.medium, .large]) }
        .navigationDestination(item: $pushed) { RouteView(route: $0) }
    }

    // MARK: Page

    private var page: some View {
        PageScroll(maxWidth: wide ? 1180 : 820, refresh: { await load() }) {
            header
            VStack(alignment: .leading, spacing: 12) {
                if !canEdit && !canCreate { readOnlyNote }
                listCard
                if !loading && !listed.isEmpty {
                    let rows = listed.count
                    Text(rows > shown ? LF("Showing %d of %d", min(shown, rows), rows) : LP(rows, "%d item", "%d items"))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 4)
                }
            }
            if wide {
                HStack(alignment: .top, spacing: 16) {
                    categoriesPanel.frame(width: 336)
                    defaultsPanel
                }
            } else {
                categoriesPanel
                defaultsPanel
            }
        }
        .reloadsOnScope { await load() }
        .onChange(of: filterKey) { _, _ in shown = 20 }
    }

    // MARK: Header

    private var header: some View {
        let s = summary
        return ModuleHeader(
            icon: "package",
            title: L("Catalog"),
            subtitle: L("What you charge for and what you sell — prices, tax and stock in one place."),
            accent: Theme.mango,
            stats: [
                ModuleStat("services", label: L("Services"), value: loading && items.isEmpty ? "—" : "\(s.services)",
                           hint: s.archivedServices > 0 ? LP(s.archivedServices, "%d archived@one", "%d archived") : L("Visits, grooming, stays…"),
                           icon: "briefcase-medical", accent: Hue.sky.color,
                           active: view == "services" && !lowOnly, action: { toggleView("services") }),
                ModuleStat("products", label: L("Products"), value: loading && items.isEmpty ? "—" : "\(s.products)",
                           hint: s.tracked > 0 ? LF("%d tracked in stock", s.tracked) : L("None tracked in stock yet"),
                           icon: "package", accent: Hue.peach.color,
                           active: view == "products" && !lowOnly, action: { toggleView("products") }),
                ModuleStat("restock", label: L("Needs restocking"), value: loading && items.isEmpty ? "—" : "\(s.restock)",
                           hint: s.out > 0 ? LP(s.out, "%d out of stock@one", "%d out of stock") : s.restock > 0 ? L("Running low") : s.tracked > 0 ? L("Stock looks healthy") : L("No products track stock"),
                           icon: "triangle-alert", accent: Theme.lime, attention: s.restock > 0,
                           active: lowOnly, action: { toggleRestock() }),
            ],
            storageKey: "catalog"
        ) {
            if canViewInventory {
                PMButton(L("Inventory"), systemImage: "warehouse", variant: .outline) { pushed = .section(.inventory) }
            }
            if !items.isEmpty || canCreate {
                Menu {
                    if !items.isEmpty {
                        Button { export(items) } label: { GlyphLabel(LF("Export the whole catalog (%d)", items.count), icon: "download") }
                    }
                    if narrowed && !listed.isEmpty && listed.count < items.count {
                        Button { export(listed) } label: { GlyphLabel(LF("Export this list (%d)", listed.count), icon: "download") }
                    }
                    if canCreate {
                        Button { importing = true } label: { GlyphLabel(L("Import from a CSV file"), icon: "file-up") }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Glyph("file-spreadsheet", size: 16)
                        Text(L("Spreadsheet"))
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.pm(.outline, size: .header))
                .accessibilityLabel(L("Import or export the catalog"))
            }
            if canCreate {
                // The editor's first step asks what it is: a service or a product.
                PMButton(L("New item"), systemImage: "plus") { creating = "ask" }
            }
        }
    }

    private var readOnlyNote: some View {
        HStack(spacing: 8) {
            Glyph("eye", size: 16)
            Text(L("You can see the catalog. Your role cannot add or change items."))
        }
        .font(Theme.text(14))
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    // MARK: The list card

    private var listCard: some View {
        let rows = listed
        return ListCard {
            CardToolbar {
                kindSwitch
                SearchField(prompt: L("Name, SKU, barcode or category"), text: $search)
                    .accessibilityLabel(L("Search the catalog"))
            }
            filterRow
            if focusItem != nil {
                band(fill: Theme.wash(Theme.butter, 22)) {
                    Text(L("Showing the item you opened.")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    Spacer(minLength: 8)
                    linkButton(L("Show the whole catalog")) { focusId = nil }
                }
            }
            if !selected.isEmpty { bulkBar }
            if lowOnly && !rows.isEmpty {
                band(fill: Theme.wash(Theme.mango, 12)) {
                    Text(L("Products at or below their reorder point")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    Spacer(minLength: 8)
                    if canViewInventory { linkButton(L("See them in Inventory")) { pushed = .section(.inventory) } }
                }
            }
            if total > items.count {
                band(fill: Theme.wash(Theme.lime, 14)) {
                    Text(LF("Showing the first %d of %d items.", items.count, total)).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    Spacer(minLength: 0)
                }
            }
            if loading && items.isEmpty {
                LoadingState()
            } else if rows.isEmpty {
                emptyState
            } else {
                rowsList(rows)
            }
        }
    }

    private var kindSwitch: some View {
        let scoped = items.filter { archived ? !$0.active : $0.active }
        return Segmented(options: [
            .init("all", L("All"), count: scoped.count),
            .init("services", L("Services"), icon: "briefcase-medical", count: scoped.filter { $0.itemType == "service" }.count, tone: CashCatalogLook.tone("service")),
            .init("products", L("Products"), icon: "package", count: scoped.filter { $0.itemType == "product" }.count, tone: CashCatalogLook.tone("product")),
        ], selection: Binding(get: { view }, set: { changeView($0) }), look: .raised, label: L("Show"), fill: !wide)
    }

    private var filterRow: some View {
        let s = summary
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Menu { categoryMenu } label: {
                            ToneMenuLabel(title: category == nil ? L("Category") : categoryLabel, icon: "tags", tone: .page, isOn: category != nil)
                        }
                        .accessibilityLabel(category == nil ? L("Category") : "\(L("Category")): \(categoryLabel)")
                        if view != "services" {
                            ToneChip(L("Needs restocking"), icon: "triangle-alert", tone: .state(.waiting), count: s.restock, isOn: lowOnly) { toggleRestock() }
                        }
                        if s.noPrice > 0 || noPrice {
                            ToneChip(L("No price"), icon: "tag", tone: .state(.waiting), count: s.noPrice, isOn: noPrice) { toggleNoPrice() }
                        }
                        if s.archived > 0 || archived {
                            ToneChip(L("Archived@filter"), icon: "archive", tone: .state(.closed), count: s.archived, isOn: archived) { toggleArchived() }
                        }
                        Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 24).padding(.horizontal, 2)
                        Menu {
                            Picker(L("Sort"), selection: Binding(get: { sort }, set: { changeSort($0) })) {
                                ForEach(CashCatalogSort.allCases, id: \.self) { entry in Text(sortTitle(entry)).tag(entry) }
                            }
                            .pickerStyle(.inline)
                        } label: {
                            ToneMenuLabel(title: sort != .name ? sortTitle(sort) : L("Sort"), icon: "arrow-up-down", tone: .page, isOn: sort != .name)
                        }
                        .accessibilityLabel(L("Sort"))
                    }
                    .padding(.vertical, 2)
                }
                if canEdit && !wide && !items.isEmpty {
                    textLink(selecting ? L("Done@select") : L("Select")) {
                        selecting.toggle()
                        if !selecting { picked = [] }
                    }
                }
                if hasFilters {
                    textLink(L("Clear filters")) { clearFilters() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            RowDivider()
        }
    }

    @ViewBuilder private var categoryMenu: some View {
        let shownCategories = categories
            .filter { viewType == nil || $0.itemType == viewType }
            .sorted { ($0.active ? 0 : 1, $0.name.lowercased()) < ($1.active ? 0 : 1, $1.name.lowercased()) }
        let counts = categoryCounts
        let binding = Binding<String>(get: { category ?? "" }, set: { category = $0.nonEmpty })
        Picker(L("Category"), selection: binding) {
            Text(L("Every category")).tag("")
            Text(L("Uncategorized")).tag("none")
        }
        .pickerStyle(.inline)
        ForEach(["service", "product"], id: \.self) { type in
            let group = shownCategories.filter { $0.itemType == type }
            if !group.isEmpty {
                Section(type == "product" ? L("Products") : L("Services")) {
                    Picker(type == "product" ? L("Products") : L("Services"), selection: binding) {
                        ForEach(group) { entry in
                            Text("\(entry.name) · \(entry.active ? String(counts[entry.id] ?? 0) : L("inactive"))").tag(entry.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
        }
    }

    private var categoryLabel: String {
        category == "none" ? L("Uncategorized") : categories.first { $0.id == category }?.name ?? L("Category")
    }

    /// Items per category id; "none:service" and "none:product" count the uncategorized ones.
    private var categoryCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for item in items where item.active { counts[item.category?.id ?? "none:\(item.itemType)", default: 0] += 1 }
        return counts
    }

    private var bulkBar: some View {
        let chosen = selected
        let active = chosen.filter(\.active).count
        let archivedCount = chosen.count - active
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(LP(chosen.count, "%d selected@one", "%d selected")).font(Theme.text(14, weight: .heavy)).foregroundStyle(Theme.inkStrong)
                    Spacer(minLength: 8)
                    Button { picked = [] } label: {
                        HStack(spacing: 4) {
                            Glyph("x", size: 16)
                            Text(L("Clear selection"))
                        }
                        .font(Theme.text(14, weight: .bold))
                        .foregroundStyle(Theme.blue)
                        .frame(minHeight: 36)
                    }
                    .buttonStyle(.plain)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        PMButton(L("Change category"), systemImage: "tags", variant: .outline, size: .header) { bulk = "category" }
                        PMButton(L("Change prices"), systemImage: "percent", variant: .outline, size: .header) { bulk = "price" }
                        if active > 0 { PMButton(L("Archive"), systemImage: "archive", variant: .outline, size: .header) { bulk = "archive" } }
                        if archivedCount > 0 { PMButton(L("Restore"), systemImage: "archive-restore", variant: .outline, size: .header) { restoreSelected() } }
                        PMButton(L("Export CSV"), systemImage: "download", variant: .outline, size: .header) { export(chosen) }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.wash(Theme.blue, 9))
            RowDivider()
        }
    }

    @ViewBuilder private func rowsList(_ rows: [CashCatalogItem]) -> some View {
        let all = rows.count
        let ticked = rows.filter { picked.contains($0.id) }.count
        let byId = Dictionary(items.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let visits = visitsByItem
        let packs = packsByItem
        if wide {
            wideHead(allTicked: ticked == all ? true : ticked > 0 ? nil : false, rows: rows)
        } else if ticks {
            Button { picked = ticked == all ? [] : Set(rows.map(\.id)) } label: {
                HStack(spacing: 12) {
                    Tick(on: ticked == all, mixed: ticked > 0 && ticked != all)
                    Text(ticked == all ? L("Clear selection") : L("Select every item listed")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            RowDivider()
        }
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.prefix(shown).enumerated()), id: \.element.id) { index, item in
                if index > 0 { RowDivider() }
                CashCatalogRow(
                    item: item, settings: settings, needle: needle, showKind: view == "all", wide: wide,
                    packSourceName: item.stockCatalogItemId.flatMap { byId[$0] },
                    visits: visits[item.id] ?? [], packs: packs[item.id] ?? 0,
                    selected: ticks ? picked.contains(item.id) : nil,
                    highlighted: focusId == item.id,
                    onSelect: { if picked.contains(item.id) { picked.remove(item.id) } else { picked.insert(item.id) } },
                    onOpen: canEdit ? { editing = item } : nil,
                    onPrice: canEdit ? { pricing = item } : nil,
                    onDuplicate: canCreate ? { duplicating = item } : nil,
                    onArchive: canEdit ? { archiving = item } : nil,
                    onRestore: canEdit ? { restore(item) } : nil,
                    onReceive: canReceive ? { pushed = .section(.inventory) } : nil,
                    onHistory: canViewInventory ? { pushed = .section(.inventory) } : nil
                )
                .onAppear { if index >= shown - 3 && shown < rows.count { shown += 20 } }
            }
        }
    }

    /// The column heads on a wide screen (web: md+ grid head).
    private func wideHead(allTicked: Bool?, rows: [CashCatalogItem]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                if ticks {
                    Button { picked = allTicked == true ? [] : Set(rows.map(\.id)) } label: { Tick(on: allTicked == true, mixed: allTicked == nil) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Select every item listed"))
                }
                headButton(L("Item"), active: sort == .name) { changeSort(.name) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(L("Category").uppercased()).frame(width: CashCatalogRow.categoryWidth, alignment: .leading)
                headButton(L("Price"), active: sort == .price || sort == .priceDesc, down: sort == .priceDesc) { changeSort(sort == .price ? .priceDesc : .price) }
                    .frame(width: CashCatalogRow.priceWidth, alignment: .trailing)
                Group {
                    if view != "services" {
                        headButton(detailHeading, active: sort == .stock) { changeSort(.stock) }
                    } else {
                        Text(detailHeading.uppercased())
                    }
                }
                .frame(width: CashCatalogRow.detailWidth, alignment: .leading)
                Color.clear.frame(width: 40, height: 1)
            }
            .font(.brandText(10.6, weight: .heavy))
            .tracking(1.27)
            .foregroundStyle(Theme.inkSoft)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.wash(Theme.surfaceMuted, 55))
            RowDivider()
        }
    }

    private var detailHeading: String {
        view == "services" ? L("Charged on") : view == "products" ? L("Stock") : L("Stock or visits")
    }

    private func headButton(_ title: String, active: Bool, down: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title.uppercased())
                Glyph(down ? "arrow-down" : "arrow-up", size: 12).opacity(active ? 1 : 0)
            }
            .foregroundStyle(active ? Theme.inkStrong : Theme.inkSoft)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LF("Sort by %@", title.lowercased()))
    }

    // MARK: Empty

    @ViewBuilder private var emptyState: some View {
        if let error {
            EmptyState(systemImage: "triangle-alert", title: L("The catalog did not load"), message: error, actionTitle: L("Try again"), action: { Task { await load() } }, accent: Theme.destructive)
        } else if items.isEmpty {
            VStack(spacing: 0) {
                EmptyState(systemImage: "package", title: L("Your catalog is empty"),
                           message: L("Add what you charge for — consults, grooms, nights — and what you sell, so visits, invoices and the store start from the same prices."),
                           accent: Theme.mango)
                if canCreate {
                    FlowLayout(spacing: 8) {
                        PMButton(L("New service"), systemImage: "briefcase-medical", size: .header) { creating = "service" }
                        PMButton(L("New product"), systemImage: "package", variant: .outline, size: .header) { creating = "product" }
                        PMButton(L("Import from a CSV file"), systemImage: "file-up", variant: .outline, size: .header) { importing = true }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                    .padding(.top, -12)
                }
            }
        } else if !needle.isEmpty {
            EmptyState(systemImage: "search", title: LF("Nothing matches “%@”", search.trimmingCharacters(in: .whitespaces)), message: L("Try a name, SKU or barcode, or clear the filters."),
                       actionTitle: L("Clear filters"), action: { clearFilters() }, accent: Theme.mango)
        } else if lowOnly {
            EmptyState(systemImage: "package-check", title: L("Nothing needs restocking"), message: L("Every tracked product is above its reorder point."),
                       actionTitle: L("Show all products"), action: { toggleRestock() }, accent: Theme.lime)
        } else if noPrice {
            EmptyState(systemImage: "tag", title: L("Everything has a price"), message: L("No item on sale is waiting for one."),
                       actionTitle: L("Show every item"), action: { toggleNoPrice() }, accent: Theme.lime)
        } else if archived {
            EmptyState(systemImage: "archive", title: L("Nothing archived"), message: L("Archived items stay on past invoices but are not offered for new ones."),
                       actionTitle: L("Show active items"), action: { toggleArchived() }, accent: Theme.mango)
        } else if category == nil && view == "services" {
            EmptyState(systemImage: "briefcase-medical", title: L("No services yet"),
                       message: L("A service is what you charge for a visit: a consult, a groom, a night. Each kind of visit can start its bill with one."),
                       actionTitle: canCreate ? L("New service") : nil, action: canCreate ? { creating = "service" } : nil, accent: Theme.aqua)
        } else if category == nil && view == "products" {
            EmptyState(systemImage: "package", title: L("No products yet"),
                       message: L("A product is what you sell over the counter or use on a visit: food, medicine, supplies. Its stock can be counted."),
                       actionTitle: canCreate ? L("New product") : nil, action: canCreate ? { creating = "product" } : nil, accent: Theme.mango)
        } else {
            EmptyState(systemImage: "layout-grid", title: L("No items match these filters"), message: L("Try another category or view, or clear the filters."),
                       actionTitle: L("Clear filters"), action: { clearFilters() }, accent: Theme.mango)
        }
    }

    // MARK: Below the list

    private var categoriesPanel: some View {
        CashCatalogCategoriesPanel(
            categories: categories, meta: categoryMeta, counts: categoryCounts, loading: !categoriesLoaded,
            activeCategory: category, activeType: viewType, canManage: canCreate || canEdit,
            onPick: { id, type in
                if category == id && (id != "none" || viewType == type) { category = nil; return }
                let next = type == "product" ? "products" : "services"
                if next != "products" { lowOnly = false }
                focusId = nil
                view = next
                category = id
            },
            onManage: { managing = true }
        )
    }

    private var defaultsPanel: some View {
        CashServiceDefaultsPanel(catalog: services, billingItems: items.filter { $0.itemType == "service" && $0.active }, canEdit: canEdit) { await loadServices() }
    }

    // MARK: Small pieces

    private func band<Content: View>(fill: some ShapeStyle, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) { content() }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fill)
            RowDivider()
        }
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Glyph("chevron-right", size: 16)
            }
            .font(Theme.text(14, weight: .bold))
            .foregroundStyle(Theme.blue)
        }
        .buttonStyle(.plain)
    }

    private func textLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue).lineLimit(1).frame(minHeight: 40)
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func sortTitle(_ sort: CashCatalogSort) -> String {
        switch sort {
        case .name: L("Name A–Z")
        case .recent: L("Recently updated")
        case .price: L("Price, low to high")
        case .priceDesc: L("Price, high to low")
        case .stock: L("Stock, lowest first")
        }
    }

    // MARK: Filters (web catalog-screen.tsx)

    private func changeView(_ next: String, clearStock: Bool = false) {
        let nextType: String? = next == "products" ? "product" : next == "services" ? "service" : nil
        // A category of the other kind would empty the list; drop it.
        if let current = category, current != "none", let type = categories.first(where: { $0.id == current })?.itemType, let nextType, type != nextType { category = nil }
        let keepStock = !clearStock && (next == "products" || next == "all")
        if !keepStock {
            lowOnly = false
            if sortChoice == .stock { sortChoice = nil }
        }
        focusId = nil
        view = next
    }

    private func toggleView(_ next: String) {
        if view == next && !lowOnly { changeView("all") } else { changeView(next, clearStock: true) }
    }

    private func toggleRestock() {
        focusId = nil
        if lowOnly {
            lowOnly = false
        } else {
            lowOnly = true
            view = "products"
            archived = false
            noPrice = false
        }
        sortChoice = nil
    }

    private func toggleNoPrice() {
        focusId = nil
        noPrice.toggle()
        if noPrice { archived = false }
    }

    private func toggleArchived() {
        focusId = nil
        archived.toggle()
        if archived {
            lowOnly = false
            noPrice = false
            if sortChoice == .stock { sortChoice = nil }
        }
    }

    private func changeSort(_ next: CashCatalogSort) {
        // The usual order needs no choice of its own.
        sortChoice = next == (lowOnly ? .stock : .name) ? nil : next
    }

    private func clearFilters() {
        search = ""
        category = nil
        lowOnly = false
        noPrice = false
        archived = false
        view = "all"
        sortChoice = nil
        focusId = nil
    }

    // MARK: Loading and actions

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let first: Page<CashCatalogItem> = try await API.get("/provider-catalog", query: ["limit": "100", "offset": "0"])
            var all = first.items
            let pages = min(20, Int((Double(first.total ?? all.count) / 100).rounded(.up)))
            if pages > 1 {
                for page in 1..<pages {
                    let more: Page<CashCatalogItem> = try await API.get("/provider-catalog", query: ["limit": "100", "offset": "\(page * 100)"])
                    let known = Set(all.map(\.id))
                    all += more.items.filter { !known.contains($0.id) }
                }
            }
            items = all
            total = first.total ?? all.count
            picked = picked.filter { id in all.contains { $0.id == id } }
            error = nil
            if let openItemId, !openedItem {
                openedItem = true
                if canEdit, let item = all.first(where: { $0.id == openItemId }) {
                    editing = item
                } else if all.contains(where: { $0.id == openItemId }) {
                    focusId = openItemId
                } else {
                    Toast.error(L("That item is no longer in the catalog."))
                }
            }
        } catch {
            self.error = errorText(error, fallback: L("Could not load the catalog. Try again."))
        }
        if let list: CashCategoryEntryList = try? await API.get("/provider-catalog/categories") {
            categories = list.items.map { CashCategory(id: $0.id, itemType: $0.itemType, name: $0.name, active: $0.active) }
            categoryMeta = Dictionary(list.items.map { ($0.id, CashCategoryMeta(createdAt: $0.createdAt, createdBy: $0.createdBy?.name)) }, uniquingKeysWith: { first, _ in first })
        }
        categoriesLoaded = true
        settings = (try? await API.get("/provider-store/settings")) ?? settings
        await loadServices()
    }

    private func loadServices() async {
        services = (try? await API.get("/appointment-services", query: ["scope": "provider"])) ?? services
    }

    private func restore(_ item: CashCatalogItem) {
        Task {
            do {
                let _: EmptyResponse = try await API.patch("/provider-catalog/\(item.id)", body: ["active": true])
                Toast.show(LF("%@ is on sale again.", item.name))
                announceDataChanged()
                await load()
            } catch {
                Toast.error(error, fallback: L("Could not restore this item. Try again."))
            }
        }
    }

    private func restoreSelected() {
        let targets = selected.filter { !$0.active }
        Task {
            let outcome = await CashCatalogBulk.run(targets.map { ($0, ["active": true]) }) { _ in }
            if outcome.done > 0 { Toast.show(LP(outcome.done, "%d item restored.", "%d items restored.")) }
            if !outcome.failed.isEmpty {
                Toast.error(LP(outcome.failed.count, "%d item could not be changed.", "%d items could not be changed."))
            } else {
                picked = []
                selecting = false
            }
            await load()
        }
    }

    private func export(_ list: [CashCatalogItem]) {
        do {
            let url = try CashCSV.write(CashCatalogCSV.export(list, all: items), name: CashCatalogCSV.exportName())
            Toast.show(LP(list.count, "%d item exported.", "%d items exported."))
            exported = CashSharedFile(url: url)
        } catch {
            Toast.error(L("The file could not be made. Try again."))
        }
    }
}

private struct CashKind: Identifiable { let kind: String; var id: String { kind } }

/// A category as the list endpoint returns it, with when and by whom it was added.
private struct CashCategoryEntry: Decodable {
    struct Person: Decodable { let name: String? }
    let id: String
    let itemType: String
    let name: String
    let active: Bool
    let createdAt: String?
    let createdBy: Person?
}

private struct CashCategoryEntryList: Decodable { let items: [CashCategoryEntry] }

private struct CashCategoryMeta {
    let createdAt: String?
    let createdBy: String?
}

// MARK: - The tick

// MARK: - A row

/// One catalog item (web `CatalogRow`): its tile, name and code, its flags,
/// its price and tax, and — by kind — its stock or the visits that charge it,
/// with a ⋯ menu of quick actions. A phone stacks it; an iPad lays columns.
struct CashCatalogRow: View {
    static let categoryWidth: CGFloat = 170
    static let priceWidth: CGFloat = 152
    static let detailWidth: CGFloat = 220

    let item: CashCatalogItem
    let settings: CashStoreSettings?
    var needle: String = ""
    var showKind: Bool = false
    var wide: Bool = false
    var packSourceName: String? = nil
    var visits: [String] = []
    var packs: Int = 0
    /// Ticked or not; nil when there are no ticks.
    var selected: Bool? = nil
    var highlighted: Bool = false
    var onSelect: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil
    var onPrice: (() -> Void)? = nil
    var onDuplicate: (() -> Void)? = nil
    var onArchive: (() -> Void)? = nil
    var onRestore: (() -> Void)? = nil
    var onReceive: (() -> Void)? = nil
    var onHistory: (() -> Void)? = nil

    private var noPrice: Bool { item.active && item.defaultUnitAmount == 0 }
    private var ownStock: Bool { item.isProduct && item.trackInventory && !item.isPack }
    private var code: String? { item.sku?.nonEmpty ?? item.inventory?.barcode?.nonEmpty }

    var body: some View {
        Group {
            if wide { wideBody } else { phoneBody }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowFill)
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
        .accessibilityAction(named: Text(LF("Edit %@", item.name))) { onOpen?() }
    }

    private var rowFill: AnyShapeStyle {
        if highlighted { return AnyShapeStyle(Theme.wash(Theme.butter, 22)) }
        if selected == true { return AnyShapeStyle(Theme.wash(Theme.blue, 7)) }
        return AnyShapeStyle(Color.clear)
    }

    private var phoneBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let selected { tick(selected).padding(.top, 12) }
                identity
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) { price }
            }
            HStack(alignment: .center, spacing: 12) {
                categoryText
                Spacer(minLength: 8)
                detail.multilineTextAlignment(.trailing)
                menu.padding(.trailing, -8)
            }
            .padding(.leading, 56 + (selected != nil ? 32 : 0))
        }
    }

    private var wideBody: some View {
        HStack(alignment: .center, spacing: 16) {
            if let selected { tick(selected) }
            identity.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                categoryText
                flags
            }
            .frame(width: Self.categoryWidth, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) { price }
                .frame(width: Self.priceWidth, alignment: .trailing)
            detail.frame(width: Self.detailWidth, alignment: .leading)
            menu.frame(width: 40)
        }
    }

    private func tick(_ on: Bool) -> some View {
        Button { onSelect?() } label: { Tick(on: on == true, mixed: on == nil).frame(width: 20, height: 20).padding(6).contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .padding(-6)
            .accessibilityLabel(LF("Select %@", item.name))
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: 12) {
            CashCatalogThumb(item: item)
            VStack(alignment: .leading, spacing: 2) {
                Text(cashCatalogHighlight(item.name, needle))
                    .font(Theme.text(16, weight: .bold))
                    .foregroundStyle(item.active ? Theme.inkStrong : Theme.inkSoft)
                    .lineLimit(wide ? 1 : 2)
                    .multilineTextAlignment(.leading)
                let second = item.description?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                if code != nil || second != nil {
                    (Text(code.map { cashCatalogHighlight($0.uppercased(), needle) } ?? AttributedString("")).font(Theme.text(12, weight: .semibold)).tracking(0.7)
                        + Text(code != nil && second != nil ? " · " : "")
                        + Text(second.map { cashCatalogHighlight($0, needle) } ?? AttributedString("")))
                        .font(Theme.text(12))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
                if !wide { flags.padding(.top, 2) }
            }
        }
    }

    @ViewBuilder private var flags: some View {
        if showKind || !item.active || item.requiresPrescription {
            HStack(spacing: 4) {
                if showKind { CashCatalogKindChip(itemType: item.itemType) }
                if !item.active { CashCatalogFlag(text: L("Archived")) }
                if item.requiresPrescription { CashCatalogFlag(text: L("Rx"), tone: Theme.pink).accessibilityLabel(L("Prescription only")) }
            }
        }
    }

    private var categoryText: some View {
        Text(item.category.map { cashCatalogHighlight($0.name, needle) } ?? AttributedString(L("Uncategorized")))
            .font(Theme.text(14, weight: item.category != nil ? .semibold : .regular))
            .foregroundStyle(item.category != nil ? Theme.inkStrong : Theme.inkSoft)
            .lineLimit(1)
    }

    @ViewBuilder private var price: some View {
        if noPrice {
            if let onPrice {
                Button(action: onPrice) {
                    HStack(spacing: 6) {
                        Glyph("tag", size: 14)
                        Text(L("Set price"))
                    }
                    .font(Theme.text(12, weight: .heavy))
                    .foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 12)
                    .frame(height: wide ? 32 : 36)
                    .background(Theme.wash(Theme.mango, 14), in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.mix(Theme.mango, 55, with: Theme.borderSoft), lineWidth: 1))
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LF("Set the price of %@", item.name))
            } else {
                Text(L("No price")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                Text(L("Asked when charging")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        } else {
            Text(cashMoney(item.defaultUnitAmount, item.currency))
                .font(.brandHeading(16, relativeTo: .body))
                .monospacedDigit()
                .foregroundStyle(item.active ? Theme.inkStrong : Theme.inkSoft)
                .lineLimit(1)
            Text(CashCatalogLook.taxNote(item, settings)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
        }
    }

    @ViewBuilder private var detail: some View {
        if item.isProduct {
            VStack(alignment: wide ? .leading : .trailing, spacing: 2) {
                CashCatalogStockPill(state: CashCatalogLook.stock(item), sourceName: packSourceName, alignTrailing: !wide)
                if packs > 0 {
                    Text(LP(packs, "Also sold as %d pack", "Also sold as %d packs")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
            }
        } else if !visits.isEmpty {
            VStack(alignment: wide ? .leading : .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    Glyph("calendar-check-2", size: 14).foregroundStyle(Theme.inkSoft)
                    Text(visits.count > 2 ? LF("%@ and %d more", visits[0], visits.count - 1) : visits.joined(separator: ", "))
                        .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                }
                Text(visits.count == 1 ? L("This visit starts its bill with it") : L("These visits start their bill with it"))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
        } else if wide {
            Text("—").font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        }
    }

    @ViewBuilder private var menu: some View {
        let entries = menuEntries
        if entries.isEmpty {
            Color.clear.frame(width: 40, height: 40)
        } else {
            Menu {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    if entry.separated && index > 0 { Divider() }
                    Button(role: nil) { entry.run() } label: { GlyphLabel(entry.title, icon: entry.icon) }
                }
            } label: {
                IconCircleLabel(size: 40, bordered: false)
            }
            .accessibilityLabel(LF("Actions for %@", item.name))
        }
    }

    private var menuEntries: [(title: String, icon: String, separated: Bool, run: () -> Void)] {
        var list: [(title: String, icon: String, separated: Bool, run: () -> Void)] = []
        if let onOpen { list.append((L("Edit"), "pencil", false, onOpen)) }
        if let onPrice { list.append((noPrice ? L("Set price") : L("Change price"), "tag", false, onPrice)) }
        if let onDuplicate { list.append((L("Duplicate"), "copy", false, onDuplicate)) }
        let receives = ownStock && item.active && onReceive != nil
        if receives, let onReceive { list.append((L("Receive stock"), "package-plus", true, onReceive)) }
        if ownStock && item.inventory != nil, let onHistory { list.append((L("Stock history"), "history", !receives, onHistory)) }
        if item.active, let onArchive { list.append((L("Archive"), "archive", true, onArchive)) }
        if !item.active, let onRestore { list.append((L("Restore"), "archive-restore", true, onRestore)) }
        return list
    }
}

/// The text with what was searched for marked in MIAW yellow (web `Highlight`).
/// Matching ignores case and accents.
func cashCatalogHighlight(_ text: String, _ needle: String) -> AttributedString {
    var out = AttributedString(text)
    guard !needle.isEmpty else { return out }
    let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    // Folding can change the length of a string with combining marks; only mark when it didn't.
    guard folded.count == text.count, let range = folded.range(of: needle) else { return out }
    let start = folded.distance(from: folded.startIndex, to: range.lowerBound)
    let length = folded.distance(from: range.lowerBound, to: range.upperBound)
    let lower = out.characters.index(out.startIndex, offsetBy: start)
    let upper = out.characters.index(lower, offsetBy: length)
    out[lower..<upper].backgroundColor = Theme.lime.opacity(0.55)
    return out
}

/// The item's photo, or its kind's icon on a tile tinted with the kind's colour (web `ItemThumb`).
struct CashCatalogThumb: View {
    let item: CashCatalogItem
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).fill(Theme.wash(CashCatalogLook.hue(item.itemType).color, 24))
            Glyph(CashCatalogLook.icon(item), size: 20).foregroundStyle(Theme.inkStrong)
            if let url = APIConfig.assetURL(item.photoUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .opacity(item.active ? 1 : 0.55)
        .grayscale(item.active ? 0 : 1)
        .accessibilityHidden(true)
    }
}

/// Service or Product, with its colour (web `KindChip`): 20 tall, a 6 dot.
struct CashCatalogKindChip: View {
    let itemType: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(CashCatalogLook.hue(itemType).color).frame(width: 6, height: 6)
            Text(itemType == "product" ? L("Product") : L("Service"))
        }
        .font(.brandText(10.9, weight: .heavy))
        .foregroundStyle(Theme.inkStrong)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Theme.wash(CashCatalogLook.hue(itemType).color, 22), in: Capsule())
    }
}

/// A small flag next to a name (web `Flag`): Archived, Rx.
struct CashCatalogFlag: View {
    let text: String
    var tone: Color = Theme.inkSoft

    var body: some View {
        Text(text)
            .font(.brandText(10.9, weight: .heavy))
            .foregroundStyle(Theme.inkStrong)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Theme.wash(tone, 10), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.mix(tone, 45, with: Theme.borderSoft), lineWidth: 1))
    }
}

/// Where the stock stands (web `StockPill`): a coloured pill for tracked
/// products with a line under it, a quiet line otherwise.
struct CashCatalogStockPill: View {
    let state: CashCatalogLook.Stock
    var sourceName: String? = nil
    var alignTrailing: Bool = false

    var body: some View {
        switch state {
        case .none:
            EmptyView()
        case .untracked:
            Text(L("Not tracked")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        case .pack(let units):
            VStack(alignment: alignTrailing ? .trailing : .leading, spacing: 0) {
                Text(LF("Pack of %d", units)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                Text(sourceName.map { LF("Draws on %@", $0) } ?? L("Draws on another product")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
        default:
            VStack(alignment: alignTrailing ? .trailing : .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(tone).frame(width: 6, height: 6)
                    Text(label)
                }
                .font(Theme.text(12, weight: .heavy))
                .foregroundStyle(isOut ? Theme.destructive : Theme.inkStrong)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Theme.wash(tone, 20), in: Capsule())
                if let hint { Text(hint).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
            }
        }
    }

    private var isOut: Bool { if case .out = state { true } else { false } }

    private var tone: Color {
        switch state {
        case .out: ProviderState.problem.color
        case .expired: ChipTone.expired.color
        case .low, .setup: ProviderState.waiting.color
        default: ProviderState.done.color
        }
    }

    private var label: String {
        switch state {
        case .setup: L("Stock not set up")
        case .out: L("Out of stock")
        case .expired: L("All expired")
        case .low(let quantity, _, _): quantity == 1 ? LF("%d left@one", quantity) : LF("%d left", quantity)
        case .ok(let quantity, _, _): LF("%d in stock", quantity)
        default: ""
        }
    }

    private var hint: String? {
        switch state {
        case .out(let quantity, let reorderPoint, let backorder):
            if quantity < 0 { return LP(-quantity, "%d short — it needs a count@one", "%d short — it needs a count") }
            if backorder { return L("Backorders allowed") }
            return reorderPoint > 0 ? LF("Reorder at %d", reorderPoint) : nil
        case .expired(let quantity):
            return LP(quantity, "%d on the shelf, none to sell@one", "%d on the shelf, none to sell")
        case .low(let quantity, let reorderPoint, let expired):
            return [expired > 0 ? LF("%d to sell", quantity - expired) : nil, LF("Reorder at %d", reorderPoint)].compactMap { $0 }.joined(separator: " · ")
        case .ok(let quantity, let location, let expired):
            return [expired > 0 ? LF("%d to sell", quantity - expired) : nil, location].compactMap { $0 }.joined(separator: " · ").nonEmpty
        case .setup:
            return L("Add the count to start tracking")
        default:
            return nil
        }
    }
}

// MARK: - Categories

/// The categories that group the catalog, services and products apart, with
/// how many items each holds (web `CatalogCategoriesPanel`). Picking one
/// filters the list above; "Manage" opens the manager.
private struct CashCatalogCategoriesPanel: View {
    let categories: [CashCategory]
    let meta: [String: CashCategoryMeta]
    let counts: [String: Int]
    let loading: Bool
    let activeCategory: String?
    let activeType: String?
    let canManage: Bool
    let onPick: (String, String) -> Void
    let onManage: () -> Void

    var body: some View {
        SectionCard(title: L("Categories"), subtitle: L("Group items so the list, invoices and the store stay tidy."), icon: "tags", accent: Theme.blue) {
            if canManage {
                PMButton(L("Manage"), systemImage: "settings-2", variant: .outline, size: .compact, action: onManage)
            }
        } content: {
            Group {
                if loading {
                    LoadingState()
                } else if categories.isEmpty {
                    EmptyState(systemImage: "tags", title: L("No categories yet"),
                               message: L("Items without one show as Uncategorized. Add categories such as Grooming, Food or Medicines."),
                               actionTitle: canManage ? L("Add categories") : nil, action: canManage ? onManage : nil, accent: Theme.mango)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(["service", "product"], id: \.self) { type in group(type) }
                    }
                    .padding(16)
                }
            }
        }
    }

    @ViewBuilder private func group(_ type: String) -> some View {
        let list = categories.filter { $0.itemType == type }.sorted { ($0.active ? 0 : 1, $0.name.lowercased()) < ($1.active ? 0 : 1, $1.name.lowercased()) }
        let uncategorized = counts["none:\(type)"] ?? 0
        if !list.isEmpty || uncategorized > 0 {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(CashCatalogLook.hue(type).color).frame(width: 6, height: 6)
                    Text((type == "product" ? L("Product categories") : L("Service categories")).uppercased())
                        .font(.brandText(10.6, weight: .heavy)).tracking(1.27).foregroundStyle(Theme.inkSoft)
                }
                VStack(spacing: 4) {
                    ForEach(list) { category in
                        row(name: category.name, count: counts[category.id] ?? 0, active: activeCategory == category.id, archived: !category.active,
                            meta: metaLine(category.id)) { onPick(category.id, type) }
                    }
                    if uncategorized > 0 {
                        row(name: L("Uncategorized"), count: uncategorized, active: activeCategory == "none" && (activeType == nil || activeType == type), quiet: true) { onPick("none", type) }
                    }
                }
            }
        }
    }

    private func metaLine(_ id: String) -> String? {
        guard let entry = meta[id], let created = entry.createdAt else { return nil }
        return LF("Added %@", DateText.date(created)) + (entry.createdBy?.nonEmpty.map { " · \($0)" } ?? "")
    }

    private func row(name: String, count: Int, active: Bool, archived: Bool = false, quiet: Bool = false, meta: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(Theme.text(14, weight: .bold))
                        .italic(quiet)
                        .foregroundStyle(quiet || archived ? Theme.inkSoft : Theme.inkStrong)
                        .lineLimit(1)
                    if let meta { Text(meta).font(Theme.text(11.2)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                }
                Spacer(minLength: 8)
                if archived {
                    Text(L("Inactive")).font(.brandText(10.6, weight: .heavy)).foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 8)
                        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
                Text("\(count)")
                    .font(Theme.text(12, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(Theme.inkSoft.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(active ? AnyShapeStyle(Theme.wash(Theme.blue, 10)) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(active ? Theme.blue : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Archiving an item: what still leans on it, then the yes (web `CatalogArchiveSheet`).
struct CashArchiveSheet: View {
    let item: CashCatalogItem
    /// The kinds of visit that start their bill with it.
    var visits: [String] = []
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var usage: CashCatalogUsage?
    @State private var loaded = false
    @State private var working = false

    init(item: CashCatalogItem, visits: [String] = [], onDone: @escaping () -> Void) {
        self.item = item
        self.visits = visits
        self.onDone = onDone
    }

    var body: some View {
        ProviderModal(title: LF("Archive %@?", item.name), subtitle: L("It stops being offered on new bills, visits and at the counter. Past bills keep it, and you can restore it any time."),
                      systemImage: "triangle-alert", accent: .pink, primaryTitle: L("Archive"), primaryVariant: .destructive, isWorking: working, primaryIcon: "triangle-alert") {
            archive()
        } content: {
            let lines = warnings
            if !lines.isEmpty || !loaded {
                VStack(alignment: .leading, spacing: 8) {
                    if !lines.isEmpty { Text(L("Before you archive it")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong) }
                    ForEach(lines, id: \.text) { line in
                        NoticeCard(tone: .custom(Theme.lime), message: line.text, icon: line.icon)
                    }
                    if !loaded {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L("Checking where it is used…")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            usage = try? await API.get("/provider-catalog/\(item.id)/usage")
            loaded = true
        }
    }

    /// Up to three names, then "and 2 more".
    private func names(_ list: [String]) -> String {
        list.count <= 3 ? list.joined(separator: ", ") : LF("%@ and %d more", list.prefix(3).joined(separator: ", "), list.count - 3)
    }

    private var warnings: [(icon: String, text: String)] {
        var lines: [(icon: String, text: String)] = []
        if !visits.isEmpty {
            lines.append(("calendar-check-2", visits.count == 1
                ? LF("%@ starts its bill with it. That visit will start without a price, and families will not see one, until you choose another item under “What each visit charges”.", names(visits))
                : LF("%@ start their bill with it. Those visits will start without a price, and families will not see one, until you choose another item under “What each visit charges”.", names(visits))))
        }
        if let usage {
            let packs = usage.packs.map(\.name)
            if !packs.isEmpty {
                lines.append(("boxes", packs.count == 1
                    ? LF("The pack %@ draws on its stock. Archive that pack first, or change the product it draws on.", names(packs))
                    : LF("The packs %@ draw on its stock. Archive those packs first, or change the product they draw on.", names(packs))))
            }
            if usage.stockOnHand > 0 {
                lines.append(("boxes", LP(usage.stockOnHand, "%d is still on the shelf. It leaves Inventory with the product and comes back when you restore it.", "%d are still on the shelf. They leave Inventory with the product and come back when you restore it.")))
            }
            if let rx = usage.prescriptions, rx > 0 {
                lines.append(("file-text", LP(rx, "%d signed prescription still has fills of it left. Archived, it is no longer offered to fill them.", "%d signed prescriptions still have fills of it left. Archived, it is no longer offered to fill them.")))
            }
            if let orders = usage.hospitalOrders, orders > 0 {
                lines.append(("bed-double", LP(orders, "%d active hospital order gives it. Check that order before you archive it.", "%d active hospital orders give it. Check those orders before you archive it.")))
            }
            if usage.openBills > 0 {
                lines.append(("receipt-text", LP(usage.openBills, "%d bill in progress has it. The bill keeps its line.", "%d bills in progress have it. Those bills keep their line.")))
            }
        } else if item.trackInventory && !item.isPack, let onShelf = item.inventory?.quantityOnHand, onShelf > 0 {
            lines.append(("boxes", LP(onShelf, "%d is still on the shelf. It leaves Inventory with the product and comes back when you restore it.", "%d are still on the shelf. They leave Inventory with the product and come back when you restore it.")))
        }
        return lines
    }

    private func archive() {
        if let usage, !usage.packs.isEmpty {
            Toast.error(L("Packs draw on this product: archive them or change what they draw on first."))
            return
        }
        working = true
        Task {
            defer { working = false }
            do {
                let _: EmptyResponse = try await API.patch("/provider-catalog/\(item.id)", body: ["active": false])
                Toast.show(LF("%@ was archived.", item.name))
                announceDataChanged()
                onDone()
                dismiss()
            } catch {
                Toast.error(error, fallback: L("Could not archive this item. Try again."))
            }
        }
    }
}
