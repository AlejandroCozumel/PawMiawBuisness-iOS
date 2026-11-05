//
//  FinanceScreen.swift
//  PawMiawNegocios
//
//  Finanzas (web: routes/provider.finance.tsx, finance/*): money across the
//  store, visits and stays. The page is the front desk's (money level 2: who
//  owes and the day close); the period's figures, payments and reports are
//  business finances (level 3). Business-wide: it reads the list's location
//  filter (`workspace.listLocationFilter`). Who owes, the payments and the
//  reports export as CSV (CashFinanceExports.swift) to the share sheet.
//
//  Drawn as the web draws it: the module header with the period's four
//  figures, the toned page tabs, the period pill and the source chips, then
//  each tab's cards (finance-overview, -collections, -payments, -cortes,
//  -reports).
//

import SwiftUI
import Charts

enum CashFinanceTab: String, Hashable { case overview, collections, payments, cortes, reports }

struct FinanceScreen: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var tab: CashFinanceTab?
    @State private var period = "this_month"
    @State private var source: String?
    @State private var dashboard: CashDashboard?
    @State private var dashboardError: String?
    @State private var paymentKind: String?
    @State private var paymentMethod: String?
    @State private var reportGroup = "item"
    @State private var owing = "all"
    @State private var corteDay: String?
    @State private var openClient: CashFinAccountTarget?

    private var level: MoneyLevel { workspace.moneyLevel }
    private var tabs: [CashFinanceTab] { level >= .finances ? [.overview, .collections, .payments, .cortes, .reports] : level >= .frontDesk ? [.collections, .cortes] : [] }
    private var current: CashFinanceTab { tab.flatMap { tabs.contains($0) ? $0 : nil } ?? tabs.first ?? .collections }
    /// Receivables are what is owed today, and the day's close has its own day: neither follows the period.
    private var periodMatters: Bool { current != .collections && current != .cortes }

    var body: some View {
        Group {
            if level < .frontDesk {
                PageScroll { NoAccessState(message: L("Ask the workspace owner to give you front desk money or business finances.")) }
            } else {
                page
            }
        }
        .providerPage(L("Finance"), root: true)
        .navigationDestination(item: $openClient) { target in CashAccountScreen(clientId: target.id, collect: target.collect) }
    }

    private var page: some View {
        PageScroll(maxWidth: 1000, refresh: { await loadDashboard() }) {
            header
            controls
            content
        }
        .reloadsOnScope { await loadDashboard() }
        .onChange(of: period) { _, _ in Task { await loadDashboard() } }
        .onChange(of: source) { _, _ in Task { await loadDashboard() } }
    }

    // MARK: Header (web ProviderModuleHeader: Banknote on the stable green)

    private var header: some View {
        ModuleHeader(
            icon: "banknote",
            title: L("Finance"),
            subtitle: subtitle,
            accent: ProviderState.done.color,
            stats: stats,
            storageKey: "finance"
        )
    }

    private var subtitle: String {
        if level < .finances { return L("Who owes you and the day close") }
        guard let dashboard, let resolved = dashboard.period else { return L("What came in, what was sold and what you are owed") }
        let range = CashDay.range(resolved.from, resolved.to)
        if !periodMatters { return range }
        return dashboard.days.count == 1 ? LF("%@ · compared with the day before", range) : LF("%@ · compared with the %d days before", range, dashboard.days.count)
    }

    /// The month's tiles are business finances: the front desk sees no period figures.
    private var stats: [ModuleStat] {
        guard level >= .finances, let totals = dashboard?.totals else { return [] }
        let money = { (cents: Int) in cashMoney(cents, dashboard?.currency) }
        return [
            ModuleStat("collected", label: L("Collected"), value: money(totals.collected),
                       hint: CashFinDelta.hint(CashFinDelta.percent(totals.collected, totals.previousCollected), L("Money in, less refunds")),
                       icon: "banknote", accent: ProviderState.done.color,
                       active: current == .payments && paymentKind == nil,
                       action: { follow(.payments, kind: nil) }),
            ModuleStat("sold", label: L("Sold"), value: money(totals.invoiced),
                       hint: CashFinDelta.hint(CashFinDelta.percent(totals.invoiced, totals.previousInvoiced), L("Made, paid or not")),
                       icon: "receipt", accent: Theme.aqua,
                       active: current == .reports,
                       action: { tab = .reports }),
            ModuleStat("owed", label: L("Owed to you"), value: money(totals.owed),
                       hint: totals.overdue > 0 ? LF("%@ past due", money(totals.overdue)) : LP(totals.clientsOwing, "%d client · as of today", "%d clients · as of today"),
                       icon: "calendar-clock", accent: Theme.pink, attention: totals.overdue > 0,
                       active: current == .collections,
                       action: { owing = "all"; tab = .collections }),
            ModuleStat("refunds", label: L("Refunds"), value: money(totals.refunded),
                       hint: totals.refundCount.map { LP($0, "%d refund, already taken off", "%d refunds, already taken off") } ?? L("Given back, already taken off"),
                       icon: "undo-2", accent: Theme.mango,
                       active: current == .payments && paymentKind == "refund",
                       action: { follow(.payments, kind: "refund") }),
        ]
    }

    private func follow(_ next: CashFinanceTab, kind: String?) {
        paymentKind = kind
        paymentMethod = nil
        tab = next
    }

    // MARK: Tabs, period and sources

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToneTabs(tabs: tabs.map { ToneTabs<CashFinanceTab>.Tab($0, title($0), icon: icon($0)) },
                          selection: Binding(get: { current }, set: { tab = $0 }), label: L("Finance"))
            if periodMatters {
                HStack(spacing: 8) {
                    CashFinPeriodMenu(period: $period, resolved: dashboard?.period)
                    if let resolved = dashboard?.period {
                        // The period on one page, for the owner or the accountant.
                        DocumentButton(title: L("Summary PDF"), systemImage: "file-down", path: "/provider-finance/summary/pdf",
                                       query: ["from": resolved.from, "to": resolved.to, "source": source, "locationId": workspace.listLocationFilter],
                                       fileName: "\(L("finance summary")) \(resolved.from)")
                    }
                    Spacer(minLength: 0)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["store", "visit", "stay", "hospital", "other"], id: \.self) { entry in
                            ToneChip(CashText.source(entry), tone: .hue(CashText.sourceHue(entry)), isOn: source == entry) {
                                source = source == entry ? nil : entry
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
            LocationMenu()
        }
    }

    private func title(_ tab: CashFinanceTab) -> String {
        switch tab {
        case .overview: L("Overview")
        case .collections: L("Owed to you")
        case .payments: L("Payments")
        case .cortes: L("Day close")
        case .reports: L("Reports")
        }
    }

    private func icon(_ tab: CashFinanceTab) -> String {
        switch tab {
        case .overview: "layout-dashboard"
        case .collections: "hand-coins"
        case .payments: "wallet"
        case .cortes: "scale"
        case .reports: "chart-column"
        }
    }

    // MARK: The tab

    @ViewBuilder private var content: some View {
        switch current {
        case .overview:
            if let dashboard {
                CashFinanceOverview(
                    dashboard: dashboard,
                    source: $source,
                    onTab: { tab = $0 },
                    onReport: { reportGroup = $0; tab = .reports },
                    onPayments: { method in paymentMethod = method; paymentKind = nil; tab = .payments },
                    onOwing: { bucket in owing = bucket; tab = .collections },
                    onCorte: { day in corteDay = day; tab = .cortes },
                    onClient: { openClient = CashFinAccountTarget(id: $0) }
                )
            } else if let dashboardError {
                CashFinError(title: L("Finance could not be loaded."), message: dashboardError) { await loadDashboard() }
            } else {
                LoadingState()
            }
        case .collections:
            CashFinanceCollections(filter: $owing) { id, collect in openClient = CashFinAccountTarget(id: id, collect: collect) }
        case .payments:
            if let resolved = dashboard?.period {
                CashFinancePayments(from: resolved.from, to: resolved.to, source: source, zone: dashboard?.timeZone.flatMap(TimeZone.init(identifier:)), kind: $paymentKind, method: $paymentMethod, onClient: { openClient = CashFinAccountTarget(id: $0) })
            } else if let dashboardError {
                CashFinError(title: L("Finance could not be loaded."), message: dashboardError) { await loadDashboard() }
            } else {
                LoadingState()
            }
        case .cortes:
            CashFinanceCortes(day: $corteDay)
        case .reports:
            if let resolved = dashboard?.period {
                CashFinanceReports(from: resolved.from, to: resolved.to, source: source, group: $reportGroup)
            } else if let dashboardError {
                CashFinError(title: L("Finance could not be loaded."), message: dashboardError) { await loadDashboard() }
            } else {
                LoadingState()
            }
        }
    }

    private func loadDashboard() async {
        guard level >= .finances else { return }
        do {
            dashboard = try await API.get("/provider-finance/dashboard", query: ["period": period, "source": source, "locationId": workspace.listLocationFilter])
            dashboardError = nil
        } catch {
            if dashboard == nil { dashboardError = errorText(error) }
        }
    }
}

/// The account a figure or a row opens; `collect` goes straight to "Collect" (a row's button).
struct CashFinAccountTarget: Hashable, Identifiable {
    let id: String
    var collect: Bool = false
}

// MARK: - Small pieces (web finance-bits.tsx)

enum CashFinDelta {
    static func percent(_ current: Int, _ previous: Int) -> Int? {
        if previous == 0 { return current == 0 ? 0 : nil }
        return Int((Double(current - previous) / Double(abs(previous)) * 100).rounded())
    }

    /// The change as the header's hint reads it ("+12% · Money in, less refunds"): the header's
    /// hint is one line of text, so the web's DeltaPill becomes its words.
    static func hint(_ change: Int?, _ text: String) -> String {
        "\(label(change)) · \(text)"
    }

    static func label(_ change: Int?) -> String {
        guard let change else { return L("New") }
        if change == 0 { return "0%" }
        return "\(change > 0 ? "+" : "−")\(abs(change))%"
    }
}

/// A change against the period before, as a pill (web `DeltaPill`): the arrow and the sign say the
/// direction; `neutral` takes no side (tax).
struct CashFinDeltaPill: View {
    let change: Int?
    var neutral: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            if let change {
                Glyph(change == 0 ? "minus" : change > 0 ? "arrow-up-right" : "arrow-down-right", size: 14)
            }
            Text(CashFinDelta.label(change)).monospacedDigit()
        }
        .font(.brandText(12, weight: change == nil ? .bold : .heavy))
        .foregroundStyle(ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(fill, in: Capsule())
    }

    private var good: Bool? {
        guard let change, change != 0, !neutral else { return nil }
        return change > 0
    }

    private var fill: AnyShapeStyle {
        switch good {
        case .some(true): AnyShapeStyle(Theme.wash(ProviderState.done.color, 22))
        case .some(false): AnyShapeStyle(Theme.wash(Theme.destructive, 14))
        case .none: AnyShapeStyle(Theme.surfaceMuted)
        }
    }

    private var ink: AnyShapeStyle {
        if change == nil { return AnyShapeStyle(Theme.inkSoft) }
        switch good {
        case .some(true): return AnyShapeStyle(Theme.inkStrong)
        case .some(false): return AnyShapeStyle(Theme.mix(Theme.destructive, 78, with: Theme.inkStrong))
        case .none: return AnyShapeStyle(Theme.mix(Theme.inkSoft, 75, with: Theme.inkStrong))
        }
    }
}

/// A titled card on the overview (web `FinanceCard`): a quiet icon, the title in Fredoka 18, one
/// line on how to read it, and something to do with it at the right.
struct CashFinCard<Action: View, Content: View>: View {
    let title: String
    var hint: String? = nil
    var icon: String? = nil
    @ViewBuilder var action: () -> Action
    @ViewBuilder let content: () -> Content

    var body: some View {
        Card(padding: 16, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    if let icon { Glyph(icon, size: 16).foregroundStyle(Theme.inkSoft).padding(.top, 3) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                        if let hint = hint?.nonEmpty { Text(hint).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                    }
                }
                Spacer(minLength: 8)
                action()
            }
            VStack(alignment: .leading, spacing: 0) { content() }
        }
    }
}

extension CashFinCard where Action == EmptyView {
    init(_ title: String, hint: String? = nil, icon: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, hint: hint, icon: icon, action: { EmptyView() }, content: content)
    }
}

/// "Ver todo →": a card's quiet link (web `CardLink`).
struct CashFinCardLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { CashFinCardLinkLabel(title: title) }.buttonStyle(.plain)
    }
}

struct CashFinCardLinkLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Glyph("arrow-right", size: 14)
        }
        .font(Theme.text(12, weight: .bold))
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .contentShape(Capsule())
    }
}

/// A figure inside a card (web `MiniStat`): on a phone the name at the left and the figure at the right.
struct CashFinMiniStat: View {
    let label: String
    let value: String
    var attention: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label.uppercased()).font(.brandText(10.2, weight: .heavy)).tracking(1).foregroundStyle(Theme.inkSoft)
            Spacer(minLength: 8)
            Text(value).font(.brandHeading(18)).monospacedDigit().foregroundStyle(attention ? Theme.destructive : Theme.inkStrong)
        }
    }
}

/// A breakdown's last line: what the rows add up to (web `TotalRow`).
struct CashFinTotalRow: View {
    let label: String
    var detail: String? = nil
    let value: String

    var body: some View {
        VStack(spacing: 0) {
            RowDivider()
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                (Text(label).fontWeight(.heavy) + Text(detail.map { " · \($0)" } ?? "").fontWeight(.regular).foregroundColor(Theme.inkSoft))
                    .foregroundStyle(Theme.inkStrong)
                Spacer(minLength: 8)
                Text(value).fontWeight(.heavy).monospacedDigit().foregroundStyle(Theme.inkStrong)
            }
            .font(Theme.text(14))
            .padding(.top, 12)
        }
        .padding(.top, 12)
    }
}

/// A figure in a bordered box (web finance `Stat`: payments' and the account's figures).
struct CashFinStatBox: View {
    let label: String
    let value: String
    var hint: String? = nil
    var attention: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased()).font(.brandText(10.6, weight: .heavy)).tracking(1.06).foregroundStyle(Theme.inkSoft).lineLimit(2)
            Text(value).font(.brandHeading(18)).monospacedDigit().foregroundStyle(attention ? Theme.destructive : Theme.inkStrong)
                .lineLimit(1).minimumScaleFactor(0.6).padding(.top, 4)
            if let hint = hint?.nonEmpty { Text(hint).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).padding(.top, 2) }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }
}

/// Views two by two (four in a row on an iPad), each row as tall as its tallest.
struct CashFinGrid: View {
    let items: [AnyView]
    var columns: Int = 2
    var spacing: CGFloat = 12

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
        VStack(spacing: spacing) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(rows[index].indices, id: \.self) { column in rows[index][column].frame(maxWidth: .infinity, maxHeight: .infinity) }
                    ForEach(0..<(columns - rows[index].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// "12 pagos" / "Mostrando 25 de 140" under a list (web `ListCount`), with an optional total at the right.
struct CashFinListCount: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(text).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            Spacer(minLength: 8)
            if let trailing { Text(trailing).font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong).multilineTextAlignment(.trailing) }
        }
        .padding(.horizontal, 4)
    }
}

/// A list that could not be loaded (web `FinanceError`): what happened and a way to try again.
struct CashFinError: View {
    var title: String = L("This could not be loaded.")
    var message: String? = nil
    let retry: () async -> Void

    var body: some View {
        ListCard {
            VStack(spacing: 0) {
                EmptyState(systemImage: "circle-alert", title: title, message: L("Check your connection and try again. Nothing was changed."), accent: Theme.pink)
                PMButton(L("Try again"), variant: .outline) { Task { await retry() } }
                    .padding(.bottom, 24)
            }
        }
    }
}

/// Finance's period, one compact control (web `FinancePeriodMenu`): a 40 capsule in a tint of the
/// page blue, the calendar-range glyph, the period's name and a chevron.
struct CashFinPeriodMenu: View {
    @Binding var period: String
    var resolved: CashResolvedPeriod? = nil

    static var periods: [(String, String)] {
        [("today", L("Today")), ("yesterday", L("Yesterday")), ("this_week", L("This week")), ("this_month", L("This month")), ("last_month", L("Last month")), ("last_30", L("Last 30 days")), ("this_year", L("This year"))]
    }

    var body: some View {
        Menu {
            ForEach(Self.periods, id: \.0) { entry in
                Button { period = entry.0 } label: {
                    if period == entry.0 { GlyphLabel(entry.1, icon: "check") } else { Text(entry.1) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Glyph("calendar-range", size: 16)
                Text(Self.periods.first { $0.0 == period }?.1 ?? L("This month")).lineLimit(1)
                Glyph("chevron-down", size: 14)
            }
            .font(Theme.text(14, weight: .bold))
            .foregroundStyle(Theme.inkStrong)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Theme.wash(Theme.blue, 14), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.mix(Theme.blue, 75, with: Theme.inkStrong), lineWidth: 1.5))
        }
        .accessibilityLabel(resolved.map { "\(L("Period")): \(CashDay.range($0.from, $0.to))" } ?? L("Period"))
    }
}

/// A row with a bar for its share of the total (web: the overview's method and source rows).
struct CashBarRow: View {
    let title: String
    var detail: String? = nil
    let amount: String
    let share: Double
    var tone: Color = Theme.blue
    var active: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                (Text(title).fontWeight(.bold) + Text(detail.map { " · \($0)" } ?? "").fontWeight(.regular).foregroundColor(Theme.inkSoft))
                    .foregroundStyle(Theme.inkStrong)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(amount).fontWeight(.bold).monospacedDigit().foregroundStyle(Theme.inkStrong)
            }
            .font(Theme.text(14))
            ProgressBar(value: share, height: 6, track: Theme.surfaceMuted, fill: tone)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(active ? AnyShapeStyle(Theme.surfaceMuted) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
        .overlay { if active { RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.inkStrong, lineWidth: 2) } }
        .contentShape(Rectangle())
    }
}

// MARK: - Overview (level 3)

struct CashFinanceOverview: View {
    let dashboard: CashDashboard
    @Binding var source: String?
    let onTab: (CashFinanceTab) -> Void
    let onReport: (String) -> Void
    let onPayments: (String?) -> Void
    let onOwing: (String) -> Void
    let onCorte: (String?) -> Void
    let onClient: (String) -> Void
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var money: (Int) -> String { { cashMoney($0, dashboard.currency) } }
    private var wide: Bool { sizeClass == .regular }

    var body: some View {
        let totals = dashboard.totals
        VStack(alignment: .leading, spacing: 16) {
            CashFinGrid(items: tiles(totals), columns: wide ? 4 : 2)
            if dashboard.locationId == nil, let places = dashboard.byLocation, places.count >= 2 {
                CashFinCard(L("By location"), hint: L("Collected and sold at each location"), icon: "map-pin") { locations(places) }
            }
            trend
            CashFinCard(L("How they paid"), hint: L("Collected by method, refunds taken off. Tap one to see its payments."), icon: "wallet") { methods }
            CashFinCard(L("Where it comes from"), hint: source.map { LF("Showing %@ only", CashText.source($0)) } ?? L("Sold by area. Tap one to see only that."), icon: "receipt") { sources }
            receivables
            cashCard
            CashFinCard(title: L("Best sellers"), hint: L("Products and services by what they brought in"), icon: "trophy", action: {
                CashFinCardLink(title: L("See all")) { onReport("item") }
            }) { topItems }
            CashFinCard(L("Top clients"), hint: L("Who bought the most in this period, and what they have paid"), icon: "user-round") { topClients }
            CashFinCard(title: L("Who sold"), hint: L("By who made each sale or bill — not who performed the service"), icon: "users", action: {
                CashFinCardLink(title: L("See all")) { onReport("staff") }
            }) {
                people(rows: dashboard.staff.map { ($0.name, $0.image, $0.revenue ?? 0, $0.documents ?? 0) }, total: totals.invoiced,
                       count: { LP($0, "%d sale or bill", "%d sales and bills") }, empty: L("No sales yet in this period."), totalLabel: L("Sold"))
            }
            CashFinCard(L("Who collected"), hint: L("By who took each payment, refunds taken off"), icon: "banknote") {
                people(rows: (dashboard.collectors ?? []).map { ($0.name, $0.image, $0.collected ?? 0, $0.payments ?? 0) }, total: totals.collected,
                       count: { LP($0, "%d payment", "%d payments") }, empty: L("No payments in this period."), totalLabel: L("Collected"))
            }
            deposits
            if workspace.can(.inventoryView), let inventory = dashboard.inventory { shelf(inventory) }
        }
    }

    // MARK: The four tiles that explain the header

    private func tiles(_ totals: CashDashboard.Totals) -> [AnyView] {
        let cash = dashboard.cash
        let off = (cash?.short ?? 0) + (cash?.over ?? 0)
        let cashValue: String = cash.map { c in off == 0 ? L("None") : c.short > 0 ? "−\(money(c.short))" : "+\(money(c.over))" } ?? "—"
        let cashHint: String = {
            guard let cash else { return L("Counts that did not match the drawer") }
            if cash.closedShifts == 0 { return L("No shift was closed in this period") }
            if off == 0 { return cash.closedShifts == 1 ? L("1 shift closed, counted exact") : LF("%d shifts closed, all exact", cash.closedShifts) }
            if cash.short > 0 && cash.over > 0 { return LF("Short in total; %@ over on other shifts", money(cash.over)) }
            if cash.short > 0 { return cash.closedShifts == 1 ? L("Cash missing at close, on the one shift") : LF("Cash missing at close, %d of %d shifts", cash.shiftsWithDifference, cash.closedShifts) }
            return cash.closedShifts == 1 ? L("Cash left over at close, on the one shift") : LF("Cash left over at close, %d of %d shifts", cash.shiftsWithDifference, cash.closedShifts)
        }()
        let marginRate = totals.marginRevenue > 0 ? Int((Double(totals.margin) / Double(totals.marginRevenue) * 100).rounded()) : nil
        return [
            AnyView(CashFinTile(icon: "percent", accent: Theme.butter, label: L("Tax in what was sold"), value: totals.tax.map(money) ?? "—",
                                change: totals.tax.flatMap { tax in totals.previousTax.flatMap { CashFinDelta.percent(tax, $0) } }, hasChange: totals.tax != nil && totals.previousTax != nil, neutral: true,
                                hint: totals.subtotal.map { LF("%@ before tax", money($0)) } ?? L("Tax inside the period’s sales"),
                                action: { onReport("item") })),
            AnyView(CashFinTile(icon: "scale", accent: Theme.mango, label: L("Register differences"), value: cashValue, attention: (cash?.short ?? 0) > 0,
                                hint: cashHint, action: { onCorte(cash?.items.first?.day) })),
            AnyView(CashFinTile(icon: "coins", accent: Theme.aqua, label: L("Average ticket"), value: totals.documents > 0 ? money(totals.averageTicket) : "—",
                                change: totals.documents > 0 ? CashFinDelta.percent(totals.averageTicket, totals.previousAverageTicket) : nil, hasChange: totals.documents > 0,
                                hint: LP(totals.documents, "Sold ÷ %d sale or bill", "Sold ÷ %d sales and bills"))),
            AnyView(CashFinTile(icon: "trophy", accent: Theme.pink, label: L("Margin"), value: totals.marginRevenue > 0 ? money(totals.margin) : "—",
                                change: totals.marginRevenue > 0 ? CashFinDelta.percent(totals.margin, totals.previousMargin) : nil, hasChange: totals.marginRevenue > 0,
                                hint: marginRate.map { LF("%d%% on products with a cost, before tax", $0) } ?? L("Needs products with a cost"))),
        ]
    }

    // MARK: By location

    private func locations(_ places: [CashDashboard.Place]) -> some View {
        let total = places.reduce(0) { $0 + max(0, $1.invoiced) }
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                ForEach(places, id: \.locationId) { place in
                    let share = total > 0 ? Double(max(0, place.invoiced)) / Double(total) : 0
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            (Text(place.name).font(Theme.text(14, weight: .bold)) + Text(place.status == "paused" ? "  · \(L("Paused"))" : "").font(Theme.text(12, weight: .semibold)).foregroundColor(Theme.inkSoft))
                                .foregroundStyle(Theme.inkStrong).lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(Int((share * 100).rounded()))%").font(Theme.text(12, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkSoft)
                        }
                        ProgressBar(value: share, height: 8, track: Theme.surfaceMuted).padding(.top, 6)
                        HStack(alignment: .top, spacing: 8) {
                            figure(L("Collected"), money(place.collected))
                            figure(L("Sold"), money(place.invoiced))
                        }
                        .padding(.top, 8)
                    }
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
            }
            Text(LF("%d locations · %@ collected · %@ sold", places.count, money(dashboard.totals.collected), money(dashboard.totals.invoiced)))
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.horizontal, 4)
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            Text(value).font(Theme.text(12, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Trend

    private var trend: some View { CashFinTrend(dashboard: dashboard) }

    // MARK: Methods and sources

    @ViewBuilder private var methods: some View {
        if dashboard.methods.isEmpty {
            EmptyState(systemImage: "banknote", title: L("No payments in this period."), accent: Theme.lime)
        } else {
            let top = Double(max(1, dashboard.methods.map { max(0, $0.amount) }.max() ?? 1))
            let count = dashboard.methods.reduce(0) { $0 + $1.count }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(dashboard.methods, id: \.method) { row in
                    Button { onPayments(row.method) } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            CashBarRow(title: CashText.method(row.method), detail: LP(row.count, "%d payment", "%d payments"), amount: money(row.amount), share: Double(max(0, row.amount)) / top)
                            if let refunds = row.refunds, refunds > 0 {
                                Text(LF("%@ refunded, already taken off", money(refunds))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).padding(.horizontal, 10).padding(.top, -4).padding(.bottom, 6)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            CashFinTotalRow(label: L("Collected"), detail: LP(count, "%d payment", "%d payments"), value: money(dashboard.totals.collected))
        }
    }

    @ViewBuilder private var sources: some View {
        let rows = dashboard.sources.filter { $0.invoiced > 0 || $0.source == source }
        let total = dashboard.sources.reduce(0) { $0 + $1.invoiced }
        if total == 0 {
            EmptyState(systemImage: "receipt", title: L("No sales yet in this period."), accent: Theme.lime)
        } else {
            let documents = dashboard.sources.reduce(0) { $0 + $1.documents }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows, id: \.source) { row in
                    Button { source = source == row.source ? nil : row.source } label: {
                        CashBarRow(title: CashText.source(row.source), detail: LP(row.documents, "%d sale or bill", "%d sales and bills"), amount: money(row.invoiced),
                                   share: total > 0 ? Double(row.invoiced) / Double(total) : 0, tone: CashText.sourceHue(row.source).color, active: source == row.source)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(source == row.source ? .isSelected : [])
                }
            }
            CashFinTotalRow(label: L("Sold"), detail: LP(documents, "%d sale or bill", "%d sales and bills"), value: money(total))
        }
    }

    // MARK: Best sellers, top clients, people

    @ViewBuilder private var topItems: some View {
        if dashboard.topItems.isEmpty {
            EmptyState(systemImage: "trophy", title: L("No sales yet in this period."), accent: Theme.lime)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(dashboard.topItems.enumerated()), id: \.offset) { index, item in
                    if index > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(Theme.text(12, weight: .heavy)).foregroundStyle(Theme.inkStrong)
                            .frame(width: 28, height: 28).background(Theme.surfaceMuted, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            HStack(spacing: 4) {
                                if item.itemType == "product" { Glyph("package", size: 12) }
                                Text(LF("%d sold", item.quantity) + (item.margin.map { " · " + LF("margin %@", money($0)) } ?? ""))
                            }
                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer(minLength: 8)
                        Text(money(item.revenue)).font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }

    @ViewBuilder private var topClients: some View {
        let rows = dashboard.topClients ?? []
        if rows.isEmpty {
            EmptyState(systemImage: "user-round", title: L("No sales yet in this period."), accent: Theme.lime)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.providerClientId) { index, row in
                    if index > 0 { RowDivider() }
                    let name = row.walkIn ? L("Walk-in sales") : row.name
                    let line = HStack(spacing: 12) {
                        Avatar(name: name, imageURL: row.walkIn ? nil : row.photoUrl, size: 36, tint: row.walkIn ? Theme.surfaceMuted : Theme.aqua)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            Text(LP(row.documents, "%d sale or bill", "%d sales and bills") + " · " + LF("%@ paid in the period", money(row.collected)))
                                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer(minLength: 8)
                        Text(money(row.invoiced)).font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    // The counter's public is not one person: no account to open.
                    if row.walkIn {
                        line
                    } else {
                        Button { onClient(row.providerClientId) } label: { line }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private func people(rows: [(String?, String?, Int, Int)], total: Int, count: @escaping (Int) -> String, empty: String, totalLabel: String) -> some View {
        if rows.isEmpty {
            EmptyState(systemImage: "users", title: empty, accent: Theme.lime)
        } else {
            let top = Double(max(1, rows.map { max(0, $0.2) }.max() ?? 1))
            let listed = rows.reduce(0) { $0 + $1.2 }
            VStack(spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    let name = row.0 ?? L("Someone who left")
                    HStack(spacing: 12) {
                        Avatar(name: name, imageURL: row.1, size: 36, tint: Theme.aqua)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(money(row.2)).font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                            }
                            HStack(spacing: 8) {
                                ProgressBar(value: Double(max(0, row.2)) / top, height: 6, track: Theme.surfaceMuted)
                                Text(count(row.3)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).fixedSize()
                            }
                        }
                    }
                }
            }
            CashFinTotalRow(label: totalLabel, detail: listed != total ? LF("others not listed: %@", money(total - listed)) : nil, value: money(total))
        }
    }

    // MARK: Owed to you (as of today)

    private var receivables: some View {
        let totals = dashboard.totals
        return CashFinCard(title: L("Owed to you"), hint: L("As of today, whatever the period: sales and bills not paid in full."), icon: "calendar-clock", action: {
            CashFinCardLink(title: L("See who")) { onOwing("all") }
        }) {
            if totals.owed == 0 {
                EmptyState(systemImage: "calendar-clock", title: L("Nobody owes you anything."), accent: Theme.lime)
            } else {
                if let aging = dashboard.aging {
                    CashFinGrid(items: CashText.agingBuckets.map { bucket in
                        AnyView(Button { onOwing(bucket) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Circle().fill(CashFinAging.tone(bucket)).frame(width: 8, height: 8)
                                    Text(CashText.aging(bucket)).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                                }
                                Text(money(aging[bucket] ?? 0)).font(.brandHeading(16)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled((aging[bucket] ?? 0) == 0)
                        .opacity((aging[bucket] ?? 0) == 0 ? 0.6 : 1))
                    }, columns: 2, spacing: 8)
                } else {
                    VStack(spacing: 8) {
                        CashFinMiniStat(label: L("Owed today"), value: money(totals.owed))
                        CashFinMiniStat(label: L("Overdue"), value: money(totals.overdue), attention: totals.overdue > 0)
                    }
                }
                CashFinTotalRow(label: L("Owed to you"), detail: LP(totals.clientsOwing, "%d client", "%d clients"), value: money(totals.owed))
            }
        }
    }

    // MARK: Register

    private var cashCard: some View {
        let cash = dashboard.cash
        return CashFinCard(title: L("Register"), hint: L("Shifts closed in this period and what their count was off by."), icon: "scale", action: {
            if cashCanRunShift(workspace) {
                NavigationLink(value: ProviderRoute.section(.store)) { CashFinCardLinkLabel(title: L("Open the register")) }.buttonStyle(.plain)
            }
        }) {
            if let cash, cash.closedShifts > 0 {
                VStack(spacing: 8) {
                    CashFinMiniStat(label: L("Shifts closed"), value: "\(cash.closedShifts)")
                    CashFinMiniStat(label: L("Cash missing"), value: cash.short > 0 ? "−\(money(cash.short))" : money(0), attention: cash.short > 0)
                    CashFinMiniStat(label: L("Cash left over"), value: cash.over > 0 ? "+\(money(cash.over))" : money(0))
                }
                if !cash.items.isEmpty {
                    VStack(spacing: 0) {
                        RowDivider()
                        ForEach(Array(cash.items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { RowDivider() }
                            Button { onCorte(item.day) } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.registerName).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                        Text([item.day.map { CashDay.long($0) }, item.closedByName].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    Text(item.difference < 0 ? LF("%@ short", money(abs(item.difference))) : LF("%@ over", money(item.difference)))
                                        .font(Theme.text(14, weight: .bold)).monospacedDigit()
                                        .foregroundStyle(item.difference < 0 ? Theme.destructive : Theme.inkStrong)
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 12)
                }
                Text(cash.shiftsWithDifference == 0 ? L("Every count matched the drawer.") : LP(cash.shiftsWithDifference, "%d shift did not match", "%d shifts did not match"))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.top, 12)
            } else {
                EmptyState(systemImage: "scale", title: L("No shift was closed in this period"),
                           message: (cash?.openShifts ?? 0) > 0 ? LP(cash?.openShifts ?? 0, "%d shift is open now.", "%d shifts are open now.") : nil, accent: Theme.mango)
            }
        }
    }

    // MARK: Deposits

    @ViewBuilder private var deposits: some View {
        let totals = dashboard.totals
        if let received = totals.depositsReceived {
            CashFinCard(title: L("Deposits"), hint: L("A deposit counts as collected the day it comes in. Spending it later pays the bill without adding to Collected."), icon: "piggy-bank", action: {
                if (totals.creditHeld ?? 0) > 0 { CashFinCardLink(title: L("See who")) { onOwing("all") } }
            }) {
                VStack(spacing: 8) {
                    CashFinMiniStat(label: L("Received in the period"), value: money(received))
                    CashFinMiniStat(label: L("Spent on bills"), value: money(totals.creditApplied ?? 0))
                    CashFinMiniStat(label: L("Held today"), value: money(totals.creditHeld ?? 0))
                }
                if let clients = totals.creditClients, clients > 0 {
                    Text(LP(clients, "%d client holds credit", "%d clients hold credit")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.top, 12)
                }
            }
        }
    }

    // MARK: On the shelf

    private func shelf(_ inventory: CashDashboard.Inventory) -> some View {
        NavigationLink(value: ProviderRoute.section(.inventory)) {
            Card(padding: 16, spacing: 16) {
                HStack(spacing: 12) {
                    IconBadge(icon: "boxes", accent: Theme.aqua, size: 40, iconSize: 18, ink: .strong)
                    Text(L("On the shelf")).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                    Spacer(minLength: 8)
                    Glyph("arrow-right", size: 16).foregroundStyle(Theme.inkSoft)
                }
                VStack(spacing: 8) {
                    CashFinMiniStat(label: L("Stock at cost"), value: money(inventory.valueAmount))
                    CashFinMiniStat(label: L("Low or out"), value: "\(inventory.lowStock + inventory.outOfStock)", attention: inventory.outOfStock > 0)
                    CashFinMiniStat(label: (inventory.expired ?? 0) > 0 ? L("Expired or expiring") : LF("Expiring in %d days", inventory.expiringDays ?? 30),
                                    value: "\(inventory.expiringSoon + (inventory.expired ?? 0))", attention: inventory.expiringSoon + (inventory.expired ?? 0) > 0)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// How late a balance is: green to red (web `AGING_TONE`).
enum CashFinAging {
    static func tone(_ bucket: String) -> Color {
        switch bucket {
        case "current": ProviderState.done.color
        case "d1_30": Hue.butter.color
        case "d31_60": ProviderState.waiting.color
        default: ProviderState.problem.color
        }
    }
}

/// A figure on the overview (web `Tile`): its badge, how it moved, its name, one line on how to read
/// it, and where it leads.
private struct CashFinTile: View {
    let icon: String
    let accent: Color
    let label: String
    let value: String
    var change: Int? = nil
    /// The figure has a comparison (a nil `change` then reads "New").
    var hasChange: Bool = false
    var neutral: Bool = false
    var attention: Bool = false
    let hint: String
    var action: (() -> Void)? = nil
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if let action {
            Button(action: action) { tile }.buttonStyle(.plain)
        } else {
            tile
        }
    }

    private var tile: some View {
        Card(padding: 16, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    IconBadge(icon: icon, accent: accent, size: 32, iconSize: 16, ink: .strong)
                    Spacer(minLength: 4)
                    if hasChange {
                        CashFinDeltaPill(change: change, neutral: neutral)
                    } else if action != nil {
                        Glyph("arrow-right", size: 16).foregroundStyle(Theme.inkSoft)
                    }
                }
                Text(label.uppercased()).font(.brandText(10.9, weight: .heavy)).tracking(1.09).foregroundStyle(Theme.inkSoft).lineLimit(2)
                    .padding(.top, 12)
                Text(value).font(.brandHeading(sizeClass == .regular ? 24 : 18)).monospacedDigit()
                    .foregroundStyle(attention ? Theme.destructive : Theme.inkStrong)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.top, 4)
                Text(hint).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).padding(.top, 4)
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .contentShape(Rectangle())
    }
}

/// Collected (bars) and sold (a line) by day, week or month, or the same as a table (web `Trend`).
private struct CashFinTrend: View {
    let dashboard: CashDashboard
    @State private var asTable = false

    private struct Row: Identifiable { let key: String; let label: String; let date: Date; var collected: Int; var sold: Int; var id: String { key } }

    /// Days as they are, or folded into weeks or months when there are too many to read as bars.
    private var bucketed: (bucket: String, rows: [Row]) {
        let days = dashboard.days
        let bucket = days.count > 120 ? "month" : days.count > 45 ? "week" : "day"
        var order: [String] = []
        var map: [String: Row] = [:]
        for (index, day) in days.enumerated() {
            let key = bucket == "month" ? String(day.day.prefix(7)) : bucket == "week" ? days[index - (index % 7)].day : day.day
            if map[key] == nil {
                let first = bucket == "month" ? "\(key)-15" : key
                let date = CashDay.date(first) ?? Date()
                let label: String = {
                    let f = DateFormatter(); f.locale = .app; f.timeZone = Workspace.shared.timeZone
                    f.setLocalizedDateFormatFromTemplate(bucket == "month" ? "MMMyy" : "dMMM")
                    return f.string(from: date)
                }()
                map[key] = Row(key: key, label: label, date: date, collected: 0, sold: 0)
                order.append(key)
            }
            map[key]?.collected += day.collected
            map[key]?.sold += day.invoiced
        }
        return (bucket, order.compactMap { map[$0] })
    }

    private static let collectedTone = Color.scheme(light: (26, 127, 79), dark: (48, 164, 108))
    private static let soldTone = Color.scheme(light: (27, 111, 179), dark: (74, 147, 224))

    var body: some View {
        let result = bucketed
        let bucket = result.bucket
        let rows = result.rows
        let empty = rows.allSatisfy { $0.collected == 0 && $0.sold == 0 }
        let title = bucket == "month" ? L("Collected and sold by month") : bucket == "week" ? L("Collected and sold by week") : L("Collected and sold by day")
        let money = { (cents: Int) in cashMoney(cents, dashboard.currency) }
        CashFinCard(title: title, hint: L("Bars: money that came in. Line: what was sold. A gap between them is money still owed, or an older debt paid."), icon: "chart-column", action: {
            if !empty {
                Button { asTable.toggle() } label: {
                    HStack(spacing: 6) {
                        Glyph(asTable ? "chart-column" : "table-2", size: 14)
                        Text(asTable ? L("See as a chart") : L("See as a table"))
                    }
                    .font(Theme.text(12, weight: .bold))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(asTable ? .isSelected : [])
            }
        }) {
            if empty {
                EmptyState(systemImage: "chart-column", title: L("Nothing sold or collected in this period."), accent: Theme.lime)
            } else if asTable {
                table(rows, bucket: bucket, money: money)
            } else {
                Chart {
                    ForEach(rows) { row in
                        BarMark(x: .value(L("Day"), row.label), y: .value(L("Collected"), Double(row.collected) / 100), width: .ratio(0.6))
                            .foregroundStyle(Self.collectedTone)
                            .cornerRadius(4)
                        LineMark(x: .value(L("Day"), row.label), y: .value(L("Sold"), Double(row.sold) / 100))
                            .foregroundStyle(Self.soldTone)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        if rows.count <= 31 {
                            PointMark(x: .value(L("Day"), row.label), y: .value(L("Sold"), Double(row.sold) / 100))
                                .foregroundStyle(Self.soldTone)
                                .symbolSize(28)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Theme.borderSoft)
                        AxisValueLabel().font(Theme.text(11)).foregroundStyle(Theme.inkSoft)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in AxisValueLabel().font(Theme.text(11)).foregroundStyle(Theme.inkSoft) }
                }
                .frame(height: 288)
                FlowLayout(spacing: 16) {
                    legend(bar: true, text: L("Collected"), value: money(dashboard.totals.collected))
                    legend(bar: false, text: L("Sold"), value: money(dashboard.totals.invoiced))
                }
                .padding(.top, 12)
            }
        }
    }

    private func legend(bar: Bool, text: String, value: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: Theme.tickRadius / 2, style: .continuous)
                .fill(bar ? Self.collectedTone : Self.soldTone)
                .frame(width: bar ? 8 : 16, height: bar ? 12 : 2)
            (Text("\(text) · ") + Text(value).foregroundColor(Theme.inkStrong)).monospacedDigit()
        }
        .font(Theme.text(12, weight: .bold))
        .foregroundStyle(Theme.inkSoft)
    }

    private func table(_ rows: [Row], bucket: String, money: @escaping (Int) -> String) -> some View {
        let first = bucket == "month" ? L("Month") : bucket == "week" ? L("Week of") : L("Day")
        return VStack(spacing: 0) {
            line(first, L("Collected"), L("Sold"), head: true)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        RowDivider()
                        line(row.label, money(row.collected), money(row.sold))
                    }
                }
            }
            .frame(maxHeight: 280)
            Rectangle().fill(Theme.borderSoft).frame(height: 2)
            line(L("Total"), money(dashboard.totals.collected), money(dashboard.totals.invoiced), total: true)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    private func line(_ a: String, _ b: String, _ c: String, head: Bool = false, total: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(head ? a.uppercased() : a).fontWeight(head ? .heavy : .bold).frame(maxWidth: .infinity, alignment: .leading)
            Text(head ? b.uppercased() : b).fontWeight(head ? .heavy : total ? .heavy : .regular).frame(maxWidth: .infinity, alignment: .trailing)
            Text(head ? c.uppercased() : c).fontWeight(head ? .heavy : total ? .heavy : .regular).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(head ? Font.brandText(10.6) : Theme.text(14))
        .tracking(head ? 1.06 : 0)
        .monospacedDigit()
        .foregroundStyle(head ? Theme.inkSoft : Theme.inkStrong)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, head || total ? 8 : 6)
    }
}

// MARK: - Payments (level 3)

struct CashFinancePayments: View {
    let from: String
    let to: String
    let source: String?
    var zone: TimeZone? = nil
    @Binding var kind: String?
    @Binding var method: String?
    let onClient: (String) -> Void
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var search = ""
    @State private var summary: CashLedgerPage.Summary?
    @StateObject private var pager = Pager<CashLedgerItem> { _, _ in Page(items: [], total: 0) }

    private var filtered: Bool { method != nil || kind != nil || search.nonEmpty != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let summary { figures(summary) }
            SearchField(prompt: L("Client, pet, folio or reference"), text: $search)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CashText.methods + ["credit"], id: \.self) { entry in
                        ToneChip(CashText.method(entry), icon: Self.methodIcon(entry), tone: .hue(CashText.methodHue(entry)), isOn: method == entry) {
                            method = method == entry ? nil : entry
                        }
                    }
                    ToneChip(L("Refunds only"), icon: "undo-2", tone: .state(.problem), isOn: kind == "refund") { kind = kind == "refund" ? nil : "refund" }
                }
                .padding(.vertical, 1)
            }
            HStack {
                CashCSVButton(disabled: (pager.total ?? 0) == 0) { try await exportPayments() }
                Spacer(minLength: 0)
            }
            list
            if let total = pager.total, total > 0 {
                CashFinListCount(text: pager.items.count < total ? LF("Showing %d of %d", pager.items.count, total) : LP(total, "%d movement", "%d movements"))
            }
        }
        .task(id: "\(from)|\(to)|\(source ?? "")|\(kind ?? "")|\(method ?? "")|\(search)|\(workspace.scopeVersion)") {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let query: [String: String?] = ["search": search.nonEmpty, "method": method, "source": source, "kind": kind, "startDate": from, "endDate": to, "locationId": workspace.listLocationFilter]
            pager.fetch = { offset, limit in
                var q = query
                q["limit"] = "\(limit)"
                q["offset"] = "\(offset)"
                let page: CashLedgerPage = try await API.get("/provider-finance/payments", query: q)
                summary = page.summary
                return Page(items: page.items, total: page.total, hasMore: page.hasMore)
            }
            await pager.reload()
        }
    }

    static func methodIcon(_ method: String) -> String {
        switch method {
        case "cash": "banknote"
        case "card": "credit-card"
        case "bank_transfer": "landmark"
        case "digital_wallet": "smartphone"
        case "credit": "piggy-bank"
        default: "sparkles"
        }
    }

    private func figures(_ summary: CashLedgerPage.Summary) -> some View {
        let money = { (cents: Int) in cashMoney(cents) }
        let items = [
            AnyView(CashFinStatBox(label: L("Net collected"), value: money(summary.totalAmount), hint: filtered ? L("With these filters") : L("Payments less refunds"))),
            AnyView(CashFinStatBox(label: L("Payments"), value: summary.paymentCount.map(String.init) ?? "—", hint: LF("%@ came in", money(summary.totalAmount + summary.refundedAmount)))),
            AnyView(CashFinStatBox(label: L("Refunds"), value: summary.refundCount.map(String.init) ?? money(summary.refundedAmount),
                                   hint: summary.refundedAmount > 0 ? LF("%@ given back", money(summary.refundedAmount)) : L("Nothing given back"))),
            AnyView(CashFinStatBox(label: L("Credit on account applied"), value: money(summary.creditAppliedAmount ?? 0), hint: L("Deposits spent on bills. Not added: counted when they came in."))),
        ]
        return CashFinGrid(items: items, columns: sizeClass == .regular ? 4 : 2)
    }

    @ViewBuilder private var list: some View {
        if !pager.loadedOnce && pager.isLoading {
            LoadingState()
        } else if let error = pager.error, pager.items.isEmpty {
            CashFinError(title: L("The payments could not be loaded."), message: error) { await pager.reload() }
        } else if pager.items.isEmpty {
            ListCard {
                EmptyState(systemImage: "wallet", title: filtered ? L("No payments match these filters.") : L("No payments in this period."),
                           message: filtered ? nil : L("Try a longer period, or another location."),
                           actionTitle: filtered ? L("Clear filters") : nil, action: { search = ""; method = nil; kind = nil }, accent: Theme.lime)
            }
        } else {
            ListCard {
                LazyVStack(spacing: 0) {
                    ForEach(Array(pager.items.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { RowDivider() }
                        Button { if let id = row.providerClientId { onClient(id) } } label: { paymentRow(row) }
                            .buttonStyle(.plain)
                            .disabled(row.providerClientId == nil)
                            .onAppear { pager.loadMoreIfNeeded(row) }
                    }
                    PagerFooter(pager: pager)
                }
            }
        }
    }

    /// Every row of the period under these filters, 100 at a time.
    private func exportPayments() async throws -> (String, String) {
        var rows: [CashLedgerItem] = []
        var offset = 0
        while offset < 20_000 {
            let query: [String: String?] = ["limit": "100", "offset": "\(offset)", "startDate": from, "endDate": to, "search": search.nonEmpty, "method": method, "source": source, "kind": kind, "locationId": workspace.listLocationFilter]
            let chunk: CashLedgerPage = try await API.get("/provider-finance/payments", query: query)
            rows += chunk.items
            if !chunk.hasMore || chunk.items.isEmpty { break }
            offset += 100
        }
        return (CashCSV.fileName(L("payments"), from: from, to: to), CashFinanceCSV.payments(rows, zone: workspace.timeZone))
    }

    private func paymentRow(_ row: CashLedgerItem) -> some View {
        let refund = row.kind == "refund"
        let credit = row.method == "credit"
        let details: [String] = [
            refund ? L("Refund") : credit ? L("Credit on account applied") : L("Payment"),
            row.invoiceNumber,
            row.source.map { CashText.source($0) },
            CashText.method(row.method) + (row.reference?.nonEmpty.map { " · \($0)" } ?? ""),
            row.paidAt.map { CashDay.when($0, zone: zone) },
            row.collectedBy?.name,
        ].compactMap { $0?.nonEmpty }
        return HStack(spacing: 12) {
            Glyph(refund ? "undo-2" : credit ? "piggy-bank" : "wallet", size: 16)
                .foregroundStyle(refund ? Theme.destructive : credit ? Theme.inkSoft : Theme.inkStrong)
                .frame(width: 36, height: 36)
                .background(refund ? AnyShapeStyle(Theme.wash(Theme.destructive, 12)) : credit ? AnyShapeStyle(Theme.surfaceMuted) : AnyShapeStyle(Theme.wash(ProviderState.done.color, 22)), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                (Text(row.clientName).fontWeight(.bold) + Text(row.petName?.nonEmpty.map { " · \($0)" } ?? "").fontWeight(.regular).foregroundColor(Theme.inkSoft))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                Text(details.joined(separator: "  ")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(refund ? "−" : "")\(cashMoney(row.amount))").font(Theme.text(14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(refund && !credit ? Theme.destructive : credit ? Theme.inkSoft : Theme.inkStrong)
                if credit {
                    Text(L("Not added to the total")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                } else if !refund, let late = row.daysLate, late > 0 {
                    Text(CashText.daysLate(late)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Reports (level 3)

struct CashFinanceReports: View {
    let from: String
    let to: String
    let source: String?
    @Binding var group: String
    @EnvironmentObject private var workspace: Workspace
    @State private var report: CashSalesReport?
    @State private var error: String?
    @State private var loading = false

    private var groups: [(key: String, label: String, icon: String)] {
        var list = [("item", L("Product or service"), "package"), ("category", L("Category"), "shapes"), ("staff", L("Who sold"), "users"), ("day", L("Day"), "calendar-days"), ("source", L("Source"), "layers")]
        if workspace.listLocationFilter == Workspace.allLocations { list.append(("location", L("Location"), "map-pin")) }
        return list.map { (key: $0.0, label: $0.1, icon: $0.2) }
    }

    private var groupLabel: String { groups.first { $0.key == group }?.label ?? L("Product or service") }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            accountant
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(groups, id: \.key) { entry in
                        ToneChip(entry.label, icon: entry.icon, tone: .page, isOn: group == entry.key) { group = entry.key }
                    }
                }
                .padding(.vertical, 1)
            }
            HStack {
                CashCSVButton(disabled: report?.rows.isEmpty ?? true) {
                    guard let report else { throw CancellationError() }
                    return (CashCSV.fileName("\(L("sales")) \(groupLabel)", from: from, to: to), CashFinanceCSV.sales(report, group: groupLabel, label: { label($0, report) }, margin: workspace.moneyLevel >= .finances))
                }
                Spacer(minLength: 0)
            }
            if let report {
                table(report)
                if !report.rows.isEmpty {
                    CashFinListCount(text: LP(report.rows.count, "%d row", "%d rows"),
                                     trailing: report.totals.documents == 1
                                        ? LF("%@ sold in 1 sale or bill", cashMoney(report.totals.revenue, report.currency))
                                        : LF("%@ sold in %d sales and bills", cashMoney(report.totals.revenue, report.currency), report.totals.documents))
                }
                Text(L("Sold includes tax and leaves out returns and credit notes; a bill’s discount and tax are shared over its lines, so the rows add up to the total. Cost and margin count only products with a cost, before tax."))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            } else if let error {
                CashFinError(title: L("The report could not be loaded."), message: error) { await load() }
            } else {
                LoadingState()
            }
        }
        .task(id: "\(from)|\(to)|\(source ?? "")|\(group)|\(workspace.scopeVersion)") { await load() }
    }

    /// "For your accountant": every sale and bill of the period, one per row.
    private var accountant: some View {
        Card(padding: 16, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Glyph("file-spreadsheet", size: 20).foregroundStyle(Theme.inkSoft).padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("For your accountant")).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                    Text(L("Every sale and bill of the period, one per row: date, folio, client, subtotal, tax, total, method and reference."))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
            CashCSVButton(title: L("Export sales and bills"), disabled: (report?.totals.documents ?? 0) == 0) {
                let documents: CashDocumentsReport = try await API.get("/provider-finance/reports/documents", query: ["from": from, "to": to, "source": source, "locationId": workspace.listLocationFilter])
                return (CashCSV.fileName(L("sales and bills"), from: from, to: to), CashFinanceCSV.documents(documents))
            }
        }
    }

    @ViewBuilder private func table(_ report: CashSalesReport) -> some View {
        ListCard {
            if report.rows.isEmpty {
                EmptyState(systemImage: "chart-column", title: L("No sales yet in this period."), message: L("Try a longer period, or another location."), accent: Theme.lime)
            } else {
                let top = Double(max(1, report.rows.map(\.revenue).max() ?? 1))
                let showQuantity = group == "item" || group == "category"
                let money = { (cents: Int) in cashMoney(cents, report.currency) }
                VStack(spacing: 0) {
                    ForEach(Array(report.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { RowDivider() }
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(label(row, report)).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(money(row.revenue)).font(Theme.text(16, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                            }
                            ProgressBar(value: Double(row.revenue) / top, height: 6, track: Theme.surfaceMuted).padding(.top, 6)
                            Text([
                                LP(row.documents, "%d sale or bill", "%d sales and bills"),
                                showQuantity && row.key != "unitemized" ? LF("%d sold", row.quantity) : nil,
                                (row.tax ?? 0) > 0 ? LF("%@ tax", money(row.tax ?? 0)) : nil,
                                row.margin.map { LF("margin %@", money($0)) },
                            ].compactMap { $0 }.joined(separator: " · "))
                                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).padding(.top, 4)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    Rectangle().fill(Theme.borderSoft).frame(height: 2)
                    VStack(spacing: 6) {
                        totalLine(L("Total"), money(report.totals.revenue))
                        if report.totals.costed == true || report.totals.cost > 0 {
                            totalLine(L("Cost"), money(report.totals.cost), soft: true)
                            totalLine(L("Margin"), money(report.totals.margin), soft: true)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func totalLine(_ label: String, _ value: String, soft: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 8)
            Text(value).monospacedDigit()
        }
        .font(Theme.text(soft ? 14 : 16, weight: soft ? .bold : .heavy))
        .foregroundStyle(soft ? Theme.inkSoft : Theme.inkStrong)
    }

    private func label(_ row: CashSalesReport.Row, _ report: CashSalesReport) -> String {
        if row.key == "unitemized" { return L("Bills without line items") }
        if report.groupBy == "source" { return CashText.source(row.key) }
        if report.groupBy == "day" { return CashDay.long(row.key) }
        if report.groupBy == "category" && row.label.isEmpty { return row.detail == "product" ? L("Products without a category") : L("Services without a category") }
        if report.groupBy == "staff" && row.label.isEmpty { return L("Someone who left") }
        if report.groupBy == "location" && row.label.isEmpty { return L("Main location") }
        return row.label
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            report = try await API.get("/provider-finance/reports/sales", query: ["from": from, "to": to, "groupBy": group, "source": source, "locationId": workspace.listLocationFilter])
            error = nil
        } catch {
            self.error = errorText(error)
        }
    }
}
