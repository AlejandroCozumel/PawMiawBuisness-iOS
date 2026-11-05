//
//  StockInventory.swift
//  PawMiawNegocios
//
//  Inventario (web provider.inventory.tsx → components/app/inventory/inventory-page.tsx):
//  stock by product — what is on the shelf, its lots and expiry, what it is
//  worth at cost (business finances only), what is low. Deliveries, counts,
//  write-offs and each product's stock settings are recorded here; sales,
//  returns and visits move the stock on their own. Stock is the whole
//  business's, not a location's. The search takes a name, a SKU or a
//  barcode, typed or read with the camera.
//
//  The page is the web's: the module header with its four numbers (the low
//  and expiring ones filter the list), the search, the toned filter chips,
//  then one panel of rows. The list shows 20 rows and adds 20 as it is
//  scrolled (the owner's rule); the counts are of the whole list.
//

import SwiftUI

struct InventoryScreen: View {
    var body: some View {
        StockInventoryPage(root: true)
    }
}

/// The sheets Inventory opens.
enum StockInventorySheet: Identifiable {
    case receive(StockRow?)
    case count(StockRow)
    case waste(StockRow, lotId: String?)
    case detail(StockRow, history: Bool)
    case settings(StockRow)

    var id: String {
        switch self {
        case .receive(let row): "receive-\(row?.catalogItemId ?? "new")"
        case .count(let row): "count-\(row.catalogItemId)"
        case .waste(let row, let lot): "waste-\(row.catalogItemId)-\(lot ?? "")"
        case .detail(let row, let history): "detail-\(row.catalogItemId)-\(history)"
        case .settings(let row): "settings-\(row.catalogItemId)"
        }
    }
}

/// Inventory itself; the Pharmacy opens it on low or expiring medicines.
struct StockInventoryPage: View {
    var initialFilter: StockFilter = .all
    var initialMedicinesOnly: Bool = false
    /// The section's own page (under the shell's bar), or opened from the Pharmacy.
    var root: Bool = false

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var whole: [StockRow]?
    @State private var found: [StockRow]?
    @State private var loadError: String?
    @State private var query = ""
    @State private var searched = ""
    @State private var filter: StockFilter = .all
    @State private var medicinesOnly = false
    @State private var shownCount = stockPageSize
    @State private var sheet: StockInventorySheet?
    @State private var goTo: ProviderRoute?
    @State private var started = false

    private var canView: Bool { workspace.can(.inventoryView) }
    private var canReceive: Bool { workspace.can(.inventoryReceive) }
    private var canCount: Bool { workspace.can(.inventoryCount) }
    private var canEdit: Bool { workspace.can(.inventoryEdit) }
    private var readOnly: Bool { !canReceive && !canCount && !canEdit }
    private var today: String { StockRules.today }

    /// A product whose stock is no longer counted keeps its record; it is not Inventory's to list.
    private func shown(_ rows: [StockRow]?) -> [StockRow] {
        (rows ?? []).filter { $0.tracked != false && (!medicinesOnly || StockRules.isMedicine($0)) }
    }

    private var rows: [StockRow] { shown(searched.isEmpty ? whole : found) }
    private var wholeRows: [StockRow] { shown(whole) }
    private var listed: [StockRow] { rows.filter { StockRules.matches($0, filter, today: today) } }

    /// What rows are worth at cost; nil when the cost is not this person's to see.
    private func value(_ rows: [StockRow]) -> Int? {
        var total = 0
        for row in rows {
            guard let amount = row.stockValueAmount else { return nil }
            total += amount
        }
        return total
    }

    private var seesCost: Bool { workspace.moneyLevel >= .finances && value(wholeRows) != nil }

    var body: some View {
        Group {
            if workspace.current != nil && !canView {
                PageScroll {
                    EmptyState(systemImage: "lock", title: L("You do not have access to inventory."), message: L("Ask the workspace owner to let your role see stock."), panel: true)
                }
            } else {
                page
            }
        }
        .providerPage(L("Inventory"), root: root)
        .onAppear {
            guard !started else { return }
            started = true
            filter = initialFilter
            medicinesOnly = initialMedicinesOnly
        }
        .reloadsOnScope { await load() }
        .debounced(query) { text in
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard trimmed != searched else { return }
            searched = trimmed
            await search()
        }
        .onChange(of: filter) { _, _ in shownCount = stockPageSize }
        .onChange(of: searched) { _, _ in shownCount = stockPageSize }
        .onChange(of: medicinesOnly) { _, _ in shownCount = stockPageSize }
        .sheet(item: $sheet) { which in sheetView(which) }
        .navigationDestination(item: $goTo) { RouteView(route: $0) }
    }

    @ViewBuilder
    private func sheetView(_ which: StockInventorySheet) -> some View {
        switch which {
        case .receive(let row):
            StockReceiveSheet(preset: row.map(fresh), severalLocations: workspace.multiLocation, onSaved: saved)
        case .count(let row):
            StockAdjustSheet(row: fresh(row), kind: .count, lotId: nil, onSaved: saved)
        case .waste(let row, let lot):
            StockAdjustSheet(row: fresh(row), kind: .waste, lotId: lot, onSaved: saved)
        case .detail(let row, let history):
            StockDetailSheet(row: fresh(row), startOnHistory: history, canWriteOff: canCount, onWriteOff: { lot in
                sheet = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    sheet = .waste(row, lotId: lot)
                }
            }, onRoute: { route in
                sheet = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    goTo = route
                }
            })
        case .settings(let row):
            StockSettingsSheet(row: fresh(row), onSaved: saved)
        }
    }

    /// The sheets read the row as the list has it now, so a save elsewhere shows.
    private func fresh(_ row: StockRow) -> StockRow {
        (whole ?? []).first { $0.catalogItemId == row.catalogItemId } ?? row
    }

    private func saved() {
        announceDataChanged()
    }

    private func load() async {
        guard canView else { return }
        do {
            whole = try await API.get("/provider-stock")
            loadError = nil
            if !searched.isEmpty { await search() }
        } catch is CancellationError {
        } catch {
            loadError = errorText(error)
        }
    }

    /// A code read by the camera is searched as the product keeps it: the GTIN-14 of a label with a
    /// leading 0 is the EAN-13 under the bars, and an EAN-13 with a leading 0 is a UPC-A.
    private func searchScanned(_ scan: BarcodeScan) async {
        query = scan.code
        guard let found = try? await Barcode.findByCode(scan.code, format: scan.format, barcode: { $0.barcode }, sku: { $0.sku }, key: { $0.catalogItemId }, search: { text in
            let rows: [StockRow] = try await API.get("/provider-stock", query: ["q": text])
            return rows
        }) else { return }
        if let barcode = found.exact?.barcode, barcode != scan.code, Barcode.same(barcode, scan.code) { query = barcode }
    }

    private func search() async {
        guard !searched.isEmpty else { found = nil; return }
        do {
            found = try await API.get("/provider-stock", query: ["q": searched])
        } catch is CancellationError {
        } catch {
            loadError = errorText(error)
        }
    }

    // MARK: Page

    private var page: some View {
        PageScroll(refresh: { await load() }) {
            header
            VStack(alignment: .leading, spacing: 22.4) {
                if readOnly && workspace.current != nil { readOnlyNote }
                VStack(alignment: .leading, spacing: 8) {
                    BarcodeSearchField(prompt: L("Product, SKU or barcode"), text: $query, onScan: { scan in Task { await searchScanned(scan) } })
                    filters
                }
                ListCard(style: .panel) { content }
                    .padding(.top, 16)
                footer
            }
        }
    }

    // MARK: Header (web ProviderModuleHeader: Boxes, teal)

    private var header: some View {
        ModuleHeader(
            icon: ProviderSection.inventory.headerIcon,
            title: L("Inventory"),
            subtitle: L("Every sale, return and visit moves this stock."),
            accent: ProviderSection.inventory.headerAccent,
            stats: headerStats,
            storageKey: "inventory"
        ) {
            if canReceive {
                PMButton(L("Receive delivery"), systemImage: "package-plus") { sheet = .receive(nil) }
            }
        }
    }

    private var headerStats: [ModuleStat] {
        let all = wholeRows
        let loaded = whole != nil
        let out = all.filter { StockRules.matches($0, .out, today: today) }.count
        let low = all.filter { StockRules.matches($0, .low, today: today) }.count
        let expiring = all.filter { StockRules.hasExpiringLot($0.lots, today: today) }.count
        let expired = all.filter { StockRules.expiredUnits($0.lots, today: today) > 0 }.count
        var stats: [ModuleStat] = [
            ModuleStat("products", label: L("Products"), value: loaded ? "\(all.count)" : "—",
                       hint: out > 0 ? (out == 1 ? L("1 out of stock") : LF("%d out of stock", out)) : nil,
                       icon: "boxes", accent: Theme.aqua),
            ModuleStat("low", label: L("Low stock"), value: loaded ? "\(low)" : "—",
                       hint: loaded ? (low > 0 ? L("Tap to see them") : L("All stocked")) : nil,
                       icon: "triangle-alert", accent: Theme.lime, attention: low > 0, active: filter == .low,
                       action: { toggle(.low) }),
            ModuleStat("expiring", label: LF("Expiring in %d days", StockRules.expiringDays), value: loaded ? "\(expiring)" : "—",
                       hint: loaded ? (expired > 0 ? (expired == 1 ? L("1 already expired") : LF("%d already expired", expired)) : expiring > 0 ? L("Sell or use these first") : L("Nothing close")) : nil,
                       icon: "calendar-clock", accent: Theme.pink, attention: expired > 0, active: filter == .expiring,
                       action: { toggle(.expiring) }),
        ]
        if seesCost, let total = value(all) {
            stats.append(ModuleStat("value", label: L("Stock value at cost"), value: Money.format(total), icon: "scale", accent: ProviderState.done.color))
        }
        return stats
    }

    private func toggle(_ next: StockFilter) { filter = filter == next ? .all : next }

    /// The web's quiet note for a role that can only look.
    private var readOnlyNote: some View {
        HStack(spacing: 8) {
            Glyph("eye", size: 16)
            Text(L("You can see the stock. Your role cannot receive, count or change it.")).fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.text(14))
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    /// Each filter in its own colour, also while it is off: the one its header tile or status pill wears.
    private var filters: some View {
        let today = today
        let counted: (StockFilter) -> Int = { f in rows.filter { StockRules.matches($0, f, today: today) }.count }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ToneChip(L("All"), icon: "layout-grid", tone: .page, isOn: filter == .all) { filter = .all }
                ToneChip(L("Low stock"), icon: "triangle-alert", tone: .waiting, count: counted(.low), isOn: filter == .low) { toggle(.low) }
                ToneChip(L("Out of stock"), icon: "ban", tone: .problem, count: counted(.out), isOn: filter == .out) { toggle(.out) }
                ToneChip(L("Expiring soon"), icon: "calendar-clock", tone: .waiting, count: counted(.expiring), isOn: filter == .expiring) { toggle(.expiring) }
                ToneChip(L("Expired@lot"), icon: "calendar-x", tone: .expired, count: counted(.expired), isOn: filter == .expired) { toggle(.expired) }
                ChipRule()
                ToneChip(L("Medicines only"), icon: "pill", tone: .sky, isOn: medicinesOnly) { medicinesOnly.toggle() }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: The list

    @ViewBuilder
    private var content: some View {
        if whole == nil && loadError == nil {
            LoadingState()
        } else if let loadError, whole == nil {
            EmptyState(systemImage: "boxes", title: L("The stock could not be loaded."), message: loadError, actionTitle: L("Try again"), action: { Task { await load() } }, accent: Theme.pink)
        } else if listed.isEmpty {
            if rows.isEmpty && searched.isEmpty {
                EmptyState(systemImage: "boxes", title: L("No stock yet"),
                           message: canReceive ? L("Receive a delivery to start counting a product’s stock.") : L("Once someone receives a delivery, the product’s stock is listed here."),
                           actionTitle: canReceive ? L("Receive delivery") : nil, action: canReceive ? { sheet = .receive(nil) } : nil, accent: Theme.mango)
            } else if rows.isEmpty {
                EmptyState(systemImage: "boxes", title: LF("No product matches “%@”.", searched), message: L("Search by its name, its SKU or its barcode."), accent: Theme.mango)
            } else {
                EmptyState(systemImage: "boxes", title: emptyTitle, actionTitle: filter != .all ? L("Show all") : nil, action: filter != .all ? { filter = .all } : nil, accent: Theme.mango)
            }
        } else {
            let visible = Array(listed.prefix(shownCount))
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { RowDivider() }
                    StockLineRow(row: row, today: today, seesCost: seesCost, wide: sizeClass == .regular,
                                 onOpen: { sheet = .detail(row, history: row.lots.isEmpty) },
                                 onReceive: canReceive ? { sheet = .receive(row) } : nil,
                                 onCount: canCount && row.inventoryItemId != nil ? { sheet = .count(row) } : nil,
                                 onWaste: canCount && row.inventoryItemId != nil ? { sheet = .waste(row, lotId: nil) } : nil,
                                 onSettings: canEdit ? { sheet = .settings(row) } : nil)
                }
                LoadMoreRow(hasMore: visible.count < listed.count) { shownCount += stockPageSize }
            }
        }
    }

    /// The count and the value go under the list, as on Home.
    @ViewBuilder
    private var footer: some View {
        if whole != nil && !listed.isEmpty {
            let shownRows = min(shownCount, listed.count)
            HStack(alignment: .firstTextBaseline) {
                Text(shownRows < listed.count ? LF("Showing %d of %d", shownRows, listed.count) : (listed.count == 1 ? L("1 product") : LF("%d products", listed.count)))
                Spacer(minLength: 16)
                if seesCost, let listedValue = value(listed) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(L("At cost"))
                        Text(Money.format(listedValue)).font(.brandHeading(16)).foregroundStyle(Theme.inkStrong)
                    }
                }
            }
            .font(Theme.text(14))
            .foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 4)
            .padding(.top, -10)
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .low: L("Nothing is low on stock.")
        case .out: L("Nothing is out of stock.")
        case .expiring: LF("Nothing expires in the next %d days.", StockRules.expiringDays)
        case .expired: L("Nothing on the shelf has expired.")
        case .all: L("Nothing here.")
        }
    }
}

/// A round outline icon button (web `Button variant="outline" size="icon"`, 44 on a phone, 40 on
/// an iPad): the kit's IconCircleButton is the quiet grey ⋯, not this blue action.
struct StockIconButton: View {
    let icon: String
    let label: String
    var size: CGFloat = 44
    var destructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Glyph(icon, size: 16)
                .foregroundStyle(destructive ? Theme.destructive : Theme.blue)
                .frame(width: size, height: size)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(destructive ? Theme.destructive : Theme.blue, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// One product's row (web `StockLine`): its photo, name, lots; then what is on the shelf and its
/// state, its value at cost (iPad), and the four actions.
private struct StockLineRow: View {
    let row: StockRow
    let today: String
    let seesCost: Bool
    let wide: Bool
    let onOpen: () -> Void
    let onReceive: (() -> Void)?
    let onCount: (() -> Void)?
    let onWaste: (() -> Void)?
    let onSettings: (() -> Void)?

    var body: some View {
        let state = StockRules.state(row, today: today)
        let expired = StockRules.expiredUnits(row.lots, today: today)
        let sellable = StockRules.sellable(row, today: today)
        let pack = row.packs.first { $0.stockUnits > 1 }
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpen) {
                HStack(alignment: .center, spacing: 12) {
                    StockProductThumb(photoUrl: row.photoUrl, productKind: row.productKind)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.name).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Text(StockText.detail(row).nonEmpty ?? L("No SKU")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                        if !row.lots.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(row.lots.prefix(3)) { lot in
                                    stockLotChip(code: lot.lotCode, quantity: lot.quantityOnHand, expiresOn: lot.expiresOn, today: today)
                                }
                                if row.lots.count > 3 {
                                    Text(LF("+%d more", row.lots.count - 3)).font(.brandText(11.2, weight: .bold)).foregroundStyle(Theme.inkSoft)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LF("Open %@: lots and history", row.name))

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    // The number and its pill side by side; stacked when four actions leave no room.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) { onHand(state); stockStateChip(row, today: today) }
                        VStack(alignment: .leading, spacing: 4) { onHand(state); stockStateChip(row, today: today) }
                    }
                    StockMetaLine(parts: [
                        row.reorderPoint > 0 && row.lowStockAlert != false ? LF("Reorder at %@", StockText.count(row.reorderPoint)) : nil,
                        expired > 0 && sellable > 0 ? LF("%@ to sell", StockText.count(sellable)) : nil,
                        expired > 0 && state != .expired ? (expired == 1 ? L("1 expired") : LF("%@ expired", StockText.count(expired))) : nil,
                        pack.map { LF("= %@ × pack of %d", StockText.count(max(0, row.quantityOnHand) / $0.stockUnits), $0.stockUnits) },
                    ])
                }
                Spacer(minLength: 0)
                if wide, seesCost, let value = row.stockValueAmount, let cost = row.unitCostAmount {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Money.format(value)).font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                        Text(LF("%@ each", Money.format(cost))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                    .frame(width: 112, alignment: .trailing)
                }
                if onReceive != nil || onCount != nil || onWaste != nil || onSettings != nil {
                    HStack(spacing: 6) {
                        let size: CGFloat = wide ? 40 : 44
                        if let onReceive { StockIconButton(icon: "package-plus", label: LF("Receive %@", row.name), size: size, action: onReceive) }
                        if let onCount { StockIconButton(icon: "clipboard-list", label: LF("Count %@", row.name), size: size, action: onCount) }
                        if let onWaste { StockIconButton(icon: "trash-2", label: LF("Write off %@", row.name), size: size, action: onWaste) }
                        if let onSettings { StockIconButton(icon: "sliders-horizontal", label: LF("Stock settings of %@", row.name), size: size, action: onSettings) }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func onHand(_ state: StockState) -> some View {
        Text(StockText.onHand(row.quantityOnHand))
            .font(.brandHeading(24))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(state == .inStock ? AnyShapeStyle(Theme.inkStrong) : AnyShapeStyle(Theme.mix(state.tone, 70, with: Theme.inkStrong)))
    }
}
