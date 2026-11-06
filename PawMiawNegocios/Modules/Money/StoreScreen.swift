//
//  StoreScreen.swift
//  PawMiawNegocios
//
//  Tienda (web: routes/provider.store.tsx): sell at the counter, the sales
//  of the day (or the person's reach), the cash register and the store's
//  settings. One place's page: with "Todas las sedes" it asks which first.
//  Money levels (docs/money-access-levels.md): selling reads today's sales,
//  the front desk the last 7 days and the shifts, business finances any day.
//  The page is the web's: the module header (the register at this device and
//  today's numbers), the Store's toned tabs, then the open tab.
//

import SwiftUI

private enum CashStoreTab: String, Hashable { case sell, sales, register, settings }

struct StoreScreen: View {
    var body: some View {
        RequireLocation { CashStorePage() }
            .providerPage(L("Store"), root: true)
    }
}

private struct CashStorePage: View {
    @EnvironmentObject private var workspace: Workspace
    @StateObject private var device = CashDeviceRegister()
    @State private var tab: CashStoreTab?
    @State private var settings: CashStoreSettings?
    @State private var settingsError: String?
    @State private var todaysSales: [CashSaleSummary] = []
    @State private var owingOnly = false
    /// "Owed on account" counts today's sales: opening it starts the list on today again.
    @State private var salesView = 0

    private var canSell: Bool { workspace.can(.salesSell) }
    private var level: MoneyLevel { workspace.moneyLevel }
    private var canSeeSales: Bool { canSell || level >= .frontDesk }
    private var tabs: [CashStoreTab] {
        var list: [CashStoreTab] = []
        if canSell { list.append(.sell) }
        if canSeeSales { list.append(.sales) }
        if cashCanRunShift(workspace) || workspace.can(.registerManage) || level >= .frontDesk { list.append(.register) }
        list.append(.settings)
        return list
    }
    private var current: CashStoreTab { tab.flatMap { tabs.contains($0) ? $0 : nil } ?? tabs.first ?? .settings }

    var body: some View {
        if !canSeeSales {
            PageScroll { NoAccessState(message: L("Ask the workspace owner to let your role sell.")) }
        } else {
            PageScroll(maxWidth: 1180, refresh: { await load() }) {
                header
                ToneTabs(
                    tabs: tabs.map { ToneTabs<CashStoreTab>.Tab($0, title($0), icon: icon($0)) },
                    selection: Binding(get: { current }, set: { next in
                        // The "Balance due" filter belongs to the Sales tab: leaving it takes it off.
                        if next != .sales { owingOnly = false }
                        tab = next
                    }),
                    label: L("Store")
                )
                if let settings {
                    switch current {
                    case .sell:
                        CashCounter(settings: settings, device: device, openRegister: { tab = .register })
                    case .sales:
                        CashSalesTab(owingOnly: $owingOnly).id(salesView)
                    case .register:
                        CashRegisterTab(device: device)
                    case .settings:
                        CashStoreSettingsTab(settings: settings) { self.settings = $0 }
                    }
                } else if let settingsError {
                    ErrorState(message: settingsError) { await load() }
                } else {
                    LoadingState()
                }
            }
            .modifier(CashKeepsRegister(device: device))
            .reloadsOnScope { await load() }
        }
    }

    private func title(_ tab: CashStoreTab) -> String {
        switch tab {
        case .sell: L("Sell")
        case .sales: L("Sales")
        case .register: L("Register")
        case .settings: L("Settings")
        }
    }

    private func icon(_ tab: CashStoreTab) -> String {
        switch tab {
        case .sell: "shopping-cart"
        case .sales: "receipt"
        case .register: "wallet"
        case .settings: "settings-2"
        }
    }

    // MARK: Header

    private var standing: [CashSaleSummary] { todaysSales.filter { !$0.canceled } }
    private var todayTotal: Int { standing.reduce(0) { $0 + $1.totalAmount - $1.returnedAmount } }
    private var todayReturned: Int { standing.reduce(0) { $0 + $1.returnedAmount } }
    private var todayDue: Int { standing.reduce(0) { $0 + $1.balanceDueAmount } }

    private var header: some View {
        ModuleHeader(
            icon: "shopping-cart",
            title: L("Store"),
            subtitle: L("Sell at the counter — stock, tax and the receipt take care of themselves."),
            stats: settings != nil ? stats : [],
            storageKey: "store"
        ) {
            if let register = device.register {
                if device.registers.count > 1 {
                    Menu {
                        ForEach(device.registers) { entry in
                            Button { device.choose(entry.id) } label: {
                                if entry.id == register.id { GlyphLabel(entry.name, icon: "check") } else { Text(entry.name) }
                            }
                        }
                    } label: {
                        FilterMenuLabel(title: register.name)
                    }
                    .accessibilityLabel(L("Register at this device"))
                }
                Button { owingOnly = false; tab = .register } label: {
                    Chip(text: register.openSessionId != nil ? LF("%@ open", register.name) : LF("%@ closed", register.name), tone: (register.openSessionId != nil) ? .custom(ProviderState.done.color) : .muted, icon: (register.openSessionId != nil) ? "lock-open" : "lock", percent: 16, ink: (register.openSessionId != nil) ? Theme.inkStrong : Theme.inkSoft, border: 60, size: .header)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The web's `storeStats`, one to one.
    private var stats: [ModuleStat] {
        let currency = settings?.currency
        var list: [ModuleStat] = [
            ModuleStat("count", label: L("Sales today"), value: "\(standing.count)",
                       hint: standing.isEmpty ? nil : LF("Average %@", cashMoney(Int((Double(todayTotal) / Double(standing.count)).rounded()), currency)),
                       icon: "receipt", accent: Theme.aqua, active: current == .sales && !owingOnly,
                       action: { owingOnly = false; tab = .sales }),
            ModuleStat("total", label: L("Sold today"), value: cashMoney(todayTotal, currency),
                       hint: todayReturned > 0 ? LF("%@ returned", cashMoney(todayReturned, currency)) : nil,
                       icon: "banknote", accent: ProviderState.done.color),
        ]
        // What the drawer should hold is for register managers only.
        if workspace.can(.registerManage) {
            list.append(ModuleStat("cash", label: L("Cash in the drawer"),
                                   value: device.session.map { cashMoney($0.expectedCash, currency) } ?? L("Closed@register"),
                                   hint: device.session.map { LF("Float %@", cashMoney($0.openingCash, currency)) } ?? L("Open it to take cash"),
                                   icon: "wallet", accent: Theme.mango, attention: device.session?.stale == true,
                                   active: current == .register, action: { owingOnly = false; tab = .register }))
        }
        // "Owed on account" is the front desk's (docs/money-access-levels.md).
        if level >= .frontDesk {
            if todayDue > 0 {
                list.append(ModuleStat("due", label: L("Owed on account"), value: cashMoney(todayDue, currency),
                                       hint: L("From today’s sales — see which"), icon: "coins", accent: Theme.pink,
                                       attention: true, active: current == .sales && owingOnly,
                                       action: {
                                           salesView += 1
                                           owingOnly = true
                                           tab = .sales
                                       }))
            } else {
                list.append(ModuleStat("due", label: L("Owed on account"), value: cashMoney(todayDue, currency),
                                       hint: L("From today’s sales"), icon: "coins", accent: Theme.pink))
            }
        }
        return list
    }

    private func load() async {
        do {
            settings = try await API.get("/provider-store/settings")
            settingsError = nil
        } catch {
            if settings == nil { settingsError = errorText(error) }
        }
        todaysSales = (try? await API.get("/provider-store/sales", query: ["period": "today", "limit": "500", "locationId": workspace.locationId])) ?? todaysSales
    }
}

// MARK: - The Sales tab

/// The sales of a day, a stretch of days or the person's reach (web:
/// store-sales.tsx): find one, open its receipt, take a return or undo a
/// mistake (in the sale's own screen). A folio or a name is looked for in every day.
struct CashSalesTab: View {
    @Binding var owingOnly: Bool
    @EnvironmentObject private var workspace: Workspace
    @State private var sales: [CashSaleSummary] = []
    @State private var loading = true
    @State private var error: String?
    @State private var outsideReach: String?
    @State private var query = ""
    @State private var start: Date = Date()
    @State private var end: Date = Date()
    @State private var method: String?
    @State private var seller = ""
    @State private var shown = 20

    private static let limit = 500
    private static let methodOrder = ["cash", "card", "bank_transfer", "digital_wallet", "other", "credit"]
    private var level: MoneyLevel { workspace.moneyLevel }
    private var reachesDays: Bool { level >= .frontDesk }
    private var firstDay: Date {
        level >= .finances ? .distantPast : DateText.calendar.date(byAdding: .day, value: -(MoneyLevel.frontDeskDays - 1), to: Date()) ?? Date()
    }
    private var startKey: String { DateText.dayKey(start) }
    private var endKey: String { DateText.dayKey(end) }
    private var onToday: Bool { startKey == DateText.dayKey() && endKey == DateText.dayKey() }
    private var searching: Bool { query.nonEmpty != nil }

    private var methods: [String] {
        Self.methodOrder.filter { entry in entry == method || sales.contains { $0.methods.contains(entry) } }
    }
    private var sellers: [String] { Array(Set(sales.compactMap { $0.cashierName?.nonEmpty })).sorted() }
    private var activeSeller: String { sellers.contains(seller) ? seller : "" }
    private var owingCount: Int { sales.filter { !$0.canceled && $0.balanceDueAmount > 0 }.count }
    private var filtering: Bool { method != nil || !activeSeller.isEmpty || owingOnly }

    private var filtered: [CashSaleSummary] {
        sales.filter { sale in
            (method == nil || sale.methods.contains(method!))
                && (activeSeller.isEmpty || sale.cashierName == activeSeller)
                && (!owingOnly || (!sale.canceled && sale.balanceDueAmount > 0))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            if searching {
                Text(level >= .finances ? L("Looking in every day, not only the ones chosen.") : level >= .frontDesk ? L("Looking in the last 7 days, or a whole folio on any day.") : L("Looking in today’s sales, or a whole folio on any day."))
                    .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            }
            if let outsideReach { NoticeCard(tone: .warning, title: outsideReach) }
            if !methods.isEmpty || sellers.count > 1 || owingCount > 0 || owingOnly { filters }
            list
            if !loading, !filtered.isEmpty { totals }
            if sales.count >= Self.limit {
                NoticeCard(tone: .warning, title: LF("These are the latest %d sales; the totals count only them. Choose fewer days to see the rest.", Self.limit))
            }
        }
        .debounced(query) { _ in await load() }
        .onChange(of: startKey) { _, _ in Task { await load() } }
        .onChange(of: endKey) { _, _ in Task { await load() } }
        .onChange(of: owingOnly) { _, _ in shown = 20 }
        .onChange(of: method) { _, _ in shown = 20 }
        .onChange(of: seller) { _, _ in shown = 20 }
        .reloadsOnScope { await load() }
    }

    // MARK: Days and search

    @ViewBuilder private var toolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if reachesDays {
                // The web's From – To field: two days, the second never before the first.
                HStack(spacing: 8) {
                    PillDatePicker(text: CashDay.short(startKey), date: Binding(get: { start }, set: { day in
                        start = clamp(day)
                        if end < start { end = start }
                    }))
                    Text("–").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkSoft)
                    PillDatePicker(text: CashDay.short(endKey), date: Binding(get: { end }, set: { day in
                        end = clamp(day)
                        if start > end { start = end }
                    }))
                    if startKey != endKey {
                        let days = (DateText.calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
                        Text(LP(days, "%d day", "%d days")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
                .opacity(searching ? 0.55 : 1)
                .disabled(searching)
            }
            HStack(spacing: 8) {
                SearchField(prompt: L("Folio or customer"), text: $query)
                if !onToday && !searching {
                    PMButton(L("Today"), systemImage: "calendar-check", variant: .outline) { start = Date(); end = Date() }
                }
            }
        }
    }

    private func clamp(_ day: Date) -> Date {
        min(max(day, firstDay), Date())
    }

    // MARK: Filters

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(methods, id: \.self) { entry in
                    ToneChip(CashText.method(entry), plain: CashText.methodHue(entry).color, dot: CashText.methodHue(entry).color, isOn: method == entry) {
                        method = method == entry ? nil : entry
                    }
                }
                if owingCount > 0 || owingOnly {
                    ToneChip(L("Balance due"), icon: "coins", plain: Theme.mango, isOn: owingOnly) { owingOnly.toggle() }
                }
                if sellers.count > 1 {
                    Menu {
                        Button(L("Everyone who sold")) { seller = "" }
                        ForEach(sellers, id: \.self) { name in Button(name) { seller = name } }
                    } label: {
                        PillField(text: activeSeller.isEmpty ? L("Everyone who sold") : activeSeller)
                    }
                    .accessibilityLabel(L("Sold by"))
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: The list

    @ViewBuilder private var list: some View {
        ListCard {
            if loading && sales.isEmpty {
                LoadingState()
            } else if let error, sales.isEmpty {
                ErrorState(message: error) { await load() }
            } else if filtered.isEmpty {
                EmptyState(systemImage: "receipt",
                           title: outsideReach ?? (searching || filtering ? L("No sales match.") : onToday ? L("No sales yet today.") : startKey == endKey ? L("No sales this day.") : L("No sales on these days.")),
                           message: filtering && !sales.isEmpty ? L("Take a filter off to see the rest.") : nil,
                           accent: Theme.mango)
            } else {
                // Twenty at a time, more as the list scrolls (the owner's rule for full lists).
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(filtered.prefix(shown).enumerated()), id: \.element.id) { index, sale in
                        if index > 0 { RowDivider() }
                        NavigationLink(value: ProviderRoute.sale(sale.id)) {
                            CashSaleRow(sale: sale, withDay: searching || startKey != endKey)
                        }
                        .buttonStyle(.plain)
                        .onAppear { if index >= shown - 3 && shown < filtered.count { shown += 20 } }
                    }
                }
            }
        }
        .opacity(loading && !sales.isEmpty ? 0.7 : 1)
    }

    /// The count and the totals go under the list, as on Home.
    private var totals: some View {
        let standing = filtered.filter { !$0.canceled }
        let returned = standing.reduce(0) { $0 + $1.returnedAmount }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                countText
                Spacer(minLength: 8)
                amounts(sold: standing.reduce(0) { $0 + $1.totalAmount - $1.returnedAmount }, returned: returned)
            }
            VStack(alignment: .leading, spacing: 4) {
                countText
                amounts(sold: standing.reduce(0) { $0 + $1.totalAmount - $1.returnedAmount }, returned: returned)
            }
        }
        .padding(.horizontal, 4)
    }

    private var countText: some View {
        Text(LP(filtered.count, "%d sale", "%d sales")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
    }

    private func amounts(sold: Int, returned: Int) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(L("Sold")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                Text(cashMoney(sold)).font(.brandHeading(16)).monospacedDigit().foregroundStyle(Theme.inkStrong)
            }
            if returned > 0 {
                HStack(spacing: 4) {
                    Text(L("Returned")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    Text(cashMoney(returned)).font(.brandHeading(16)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        var params: [String: String?] = ["limit": "\(Self.limit)", "locationId": workspace.locationId]
        if let q = query.nonEmpty {
            params["q"] = q
        } else if onToday {
            params["period"] = "today"
        } else {
            params["from"] = startKey
            params["to"] = endKey
        }
        do {
            sales = try await API.get("/provider-store/sales", query: params)
            error = nil
            outsideReach = nil
            shown = 20
        } catch let failure as APIError where failure.code == "sales_today_only" || failure.code == "outside_front_desk_days" {
            sales = []
            outsideReach = failure.code == "sales_today_only" ? L("You only see today’s sales.") : L("You only see the sales of the last 7 days.")
        } catch {
            self.error = errorText(error)
        }
    }
}

/// One sale in the list (web `SaleRow`): the folio and its time, who bought
/// and what, how it was paid (each way in its colour), the amount and what
/// happened to it after.
struct CashSaleRow: View {
    let sale: CashSaleSummary
    var withDay: Bool = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sale.folio).font(Theme.text(14, weight: .bold)).monospaced().foregroundStyle(Theme.inkStrong).lineLimit(1)
                Text(withDay ? "\(CashDay.short(String(sale.createdAt.prefix(10)))) · \(DateText.time(sale.createdAt))" : DateText.time(sale.createdAt))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            .frame(width: 88, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                (Text(sale.walkIn ? (sale.customerName ?? L("Walk-in customer")) : (sale.customerName ?? "")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    + Text(sale.petName?.nonEmpty.map { " · \($0)" } ?? "").font(Theme.text(14)).foregroundStyle(Theme.inkSoft))
                    .lineLimit(1)
                FlowLayout(spacing: 8, lineSpacing: 2) {
                    let units = sale.unitCount ?? sale.lineCount ?? 0
                    Text(LP(units, "%d item", "%d items"))
                    ForEach(sale.methods, id: \.self) { method in
                        HStack(spacing: 4) {
                            Circle().fill(CashText.methodHue(method).color).frame(width: 6, height: 6)
                            Text(CashText.method(method))
                        }
                    }
                    if sizeClass == .regular, let cashier = sale.cashierName?.nonEmpty {
                        HStack(spacing: 4) {
                            Glyph("user-round", size: 12)
                            Text(cashier)
                        }
                    }
                }
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text(cashMoney(sale.totalAmount, sale.currency))
                    .font(.brandHeading(18)).monospacedDigit()
                    .foregroundStyle(sale.canceled ? Theme.inkSoft : Theme.inkStrong)
                    .strikethrough(sale.canceled)
                if let state = Self.state(sale) { Chip(text: state.0, tone: state.1) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    /// What happened to the sale after it was rung up; nothing for a plain paid one.
    static func state(_ sale: CashSaleSummary) -> (String, Chip.Tone)? {
        if sale.canceled { return (L("Canceled@sale"), .danger) }
        // A sale left on account whose balance the business forgave ("Perdonar saldo").
        if sale.status == "forgiven" { return (L("Balance forgiven"), .online) }
        if sale.returnedAmount >= sale.totalAmount && sale.totalAmount > 0 { return (L("Returned@sale"), .online) }
        if sale.returnedAmount > 0 { return (L("Part returned"), .online) }
        if sale.balanceDueAmount > 0 { return (L("Balance due"), .warn) }
        return nil
    }
}
