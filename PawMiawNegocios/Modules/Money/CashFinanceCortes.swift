//
//  CashFinanceCortes.swift
//  PawMiawNegocios
//
//  Cortes del día (web: finance/finance-cortes.tsx): one day's money by
//  method, where it came from, who charged, what went back, every register
//  shift, and "Excepciones del día" — refunds, returns, cancels, big
//  discounts, courtesies, lower prices, cash in and out, drawer differences —
//  who, when, how much and why. The front desk reads the last 7 days; business
//  finances any day (docs/money-access-levels.md).
//
//  The web's print (an 80 mm ticket or a page) is the browser's; here the
//  day's close PDF is the printable copy (Quick Look prints it).
//

import SwiftUI

struct CashFinanceCortes: View {
    /// The day shown; nil is today (the overview's register rows set it).
    @Binding var day: String?
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var data: CashDayClose?
    @State private var exceptions: CashExceptions?
    @State private var error: String?
    @State private var exceptionsError: String?
    @State private var expanded: String?

    private var today: String { data?.today ?? CashDay.today }
    private var current: String { day ?? data?.day ?? today }
    private var firstDay: String? { workspace.moneyLevel >= .finances ? nil : CashDay.frontDeskFirst(today) }
    private var wide: Bool { sizeClass == .regular }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            dayBar
            if let data {
                Text(data.isToday ? "\(L("Today")) · \(Self.dayTitle(data.day))" : Self.dayTitle(data.day))
                    .font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 4)
                close(data)
            } else if let error {
                CashFinError(title: L("Could not load this day."), message: error) { await load() }
            } else {
                LoadingState()
            }
        }
        .task(id: "\(day ?? "today")|\(workspace.scopeVersion)") { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .pawMiawDataChanged)) { _ in Task { await load() } }
    }

    /// "Sábado, 3 de octubre de 2026": only the first letter raised.
    static func dayTitle(_ key: String) -> String {
        guard let date = CashDay.date(key) else { return key }
        let f = DateFormatter(); f.locale = .app; f.timeZone = Workspace.shared.timeZone
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMMyyyy")
        let text = f.string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    // MARK: Day bar (web: ‹ date › · Today · PDF)

    private var dayBar: some View {
        FlowLayout(spacing: 8) {
            HStack(spacing: 8) {
                IconCircleButton(systemImage: "chevron-left", label: L("Day before")) { go(CashDay.shift(current, -1)) }
                    .disabled(firstDay.map { current <= $0 } ?? false)
                dayPill
                IconCircleButton(systemImage: "chevron-right", label: L("Day after")) { go(CashDay.shift(current, 1)) }
                    .disabled(current >= today)
                if data?.isToday == false {
                    PMButton(L("Today"), variant: .outline, size: .compact) { day = nil }
                }
            }
            DocumentButton(title: L("Download PDF"), systemImage: "file-down", path: "/provider-finance/day-close/pdf",
                           query: ["day": current, "locationId": workspace.listLocationFilter], fileName: "\(L("Day close report")) \(current)")
                .disabled(data == nil)
        }
    }

    /// The day as a 40 pt pill over the system calendar, held to the days this level reads
    /// (the kit's `PillDatePicker` takes no range).
    private var dayPill: some View {
        let lower = firstDay.flatMap(CashDay.date) ?? .distantPast
        let upper = Swift.max(lower, CashDay.date(today) ?? Date())
        return ZStack {
            DatePicker("", selection: Binding(get: { CashDay.date(current) ?? Date() }, set: { go(DateText.dayKey($0)) }), in: lower...upper, displayedComponents: .date)
                .labelsHidden()
                .environment(\.timeZone, Workspace.shared.timeZone)
                .scaleEffect(x: 2.4, y: 1.3)
            PillField(text: CashDay.short(current), icon: "calendar-days")
                .allowsHitTesting(false)
        }
        .fixedSize()
        .clipShape(Capsule())
        .accessibilityLabel(L("Day"))
    }

    private func go(_ next: String) {
        // Today is the default, and stays "today" as the days turn.
        day = next >= today ? nil : next
    }

    private func load() async {
        let query: [String: String?] = ["day": day ?? "today", "locationId": workspace.listLocationFilter]
        async let close: CashDayClose = API.get("/provider-finance/day-close", query: query)
        async let list: CashExceptions = API.get("/provider-finance/exceptions", query: query)
        do {
            data = try await close
            error = nil
        } catch {
            if data == nil || day != nil { data = nil; self.error = errorText(error) }
        }
        do {
            exceptions = try await list
            exceptionsError = nil
        } catch {
            exceptions = nil
            exceptionsError = errorText(error)
        }
    }

    // MARK: The close

    @ViewBuilder private func close(_ data: CashDayClose) -> some View {
        let money = { (cents: Int) in cashMoney(cents, data.currency) }
        if let places = data.byLocation, places.count >= 2 { byLocation(places, money) }
        CashFinGrid(items: stats(data, money), columns: wide ? 4 : 2)
        methodsPanel(data, money)
        sourcesPanel(data, money)
        peoplePanel(data, money)
        if !data.refundItems.isEmpty {
            panel(L("Refunds"), icon: "undo-2") { refundList(data.refundItems, data, asCredit: false) }
        }
        if let credits = data.creditRefundItems, !credits.isEmpty {
            panel(L("Given back as credit on the account"), icon: "wallet", aside: {
                Text(L("Not money: it stays on the client’s account.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            }) { refundList(credits, data, asCredit: true) }
        }
        shiftsPanel(data, money)
        exceptionsPanel
    }

    private func stats(_ data: CashDayClose, _ money: @escaping (Int) -> String) -> [AnyView] {
        let totals = data.shiftTotals
        let card = data.byMethod.first { $0.method == "card" }
        let cashHint: Text = {
            if totals.shifts == 0 { return Text(L("No register shifts")) }
            if totals.open > 0 { return Text(LP(totals.open, "%d shift still open", "%d shifts still open")) }
            return Text("\(L("Counted")) ") + differenceText(totals.cashDifference, data.currency)
        }()
        return [
            AnyView(CashFinCorteStat(icon: "banknote", accent: Theme.lime, label: L("Money in, net"), value: money(data.totals.net),
                                     hint: Text(LP(data.totals.payments, "%d payment", "%d payments")))),
            AnyView(CashFinCorteStat(icon: "wallet", accent: Theme.mango, label: L("Cash"), value: money(data.byMethod.first { $0.method == "cash" }?.net ?? 0),
                                     hint: cashHint, bad: totals.shifts > 0 && totals.open == 0 && totals.cashDifference < 0)),
            AnyView(CashFinCorteStat(icon: "credit-card", accent: Theme.aqua, label: L("Card"), value: money(card?.net ?? 0),
                                     hint: Text(totals.cardTerminalTotal.map { terminal in totals.cardDifference == 0 ? L("Matches the terminal") : LF("Terminal %@", money(terminal)) } ?? L("Terminal not entered")))),
            AnyView(CashFinCorteStat(icon: "undo-2", accent: Theme.pink, label: L("Given back"), value: money(data.totals.refunded),
                                     hint: Text(LP(data.totals.refunds, "%d refund", "%d refunds")))),
        ]
    }

    /// The web's `DifferenceLabel` inside a line: exact in blue, short in red, over in mango.
    private func differenceText(_ difference: Int, _ currency: String) -> Text {
        if difference == 0 { return Text(L("Exact")).fontWeight(.bold).foregroundColor(Theme.blue) }
        if difference < 0 { return Text(LF("Short %@", cashMoney(-difference, currency))).fontWeight(.bold).foregroundColor(Theme.destructive) }
        return Text(LF("Over %@", cashMoney(difference, currency))).fontWeight(.bold).foregroundColor(Theme.mango)
    }

    // MARK: Panels (web `Panel`: a card with a titled head over a hairline)

    private func panel<Aside: View, Content: View>(_ title: String, icon: String, @ViewBuilder aside: @escaping () -> Aside, @ViewBuilder content: @escaping () -> Content) -> some View {
        SectionCard(title: title, icon: icon, accent: Theme.blue, trailing: aside) {
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    private func panel<Content: View>(_ title: String, icon: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        panel(title, icon: icon, aside: { EmptyView() }, content: content)
    }

    private func byLocation(_ places: [CashDayClose.Place], _ money: @escaping (Int) -> String) -> some View {
        panel(L("By location"), icon: "map-pin") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                ForEach(places, id: \.locationId) { place in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(place.name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Text(money(place.net)).font(.brandHeading(20)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                        Text(LP(place.payments, "%d payment", "%d payments") + (place.openShifts > 0 ? " · " + LP(place.openShifts, "%d shift still open", "%d shifts still open") : ""))
                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
            }
        }
    }

    private func methodsPanel(_ data: CashDayClose, _ money: @escaping (Int) -> String) -> some View {
        panel(L("Money in by method"), icon: "scale") {
            VStack(spacing: 0) {
                methodLine(L("Method"), L("In"), L("Back@money"), L("Net"), head: true)
                ForEach(Array(data.byMethod.enumerated()), id: \.element.method) { index, row in
                    if index > 0 { RowDivider() }
                    methodLine(CashText.method(row.method), money(row.payments), row.refunds > 0 ? "−\(money(row.refunds))" : "—", money(row.net), dim: row.count == 0)
                }
                RowDivider()
                methodLine(L("Total"), money(data.totals.collected), data.totals.refunded > 0 ? "−\(money(data.totals.refunded))" : "—", money(data.totals.net), total: true)
            }
            (Text("\(L("Credit on account")): ").fontWeight(.bold).foregroundColor(Theme.inkStrong)
                + Text(data.credit.spent > 0 || data.credit.returned > 0
                       ? LF("%@ spent from deposits%@ — not new money, it was counted when the deposit came in.", money(data.credit.spent), data.credit.returned > 0 ? LF(", %@ given back as credit", money(data.credit.returned)) : "")
                       : L("none used today.")))
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                .padding(.top, 12)
            if let outside = data.outsideShifts, outside.count > 0 {
                Text(LF("%@ was taken with no register shift open (card or transfer).", money(outside.net))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).padding(.top, 8)
            }
        }
    }

    private func methodLine(_ method: String, _ paid: String, _ back: String, _ net: String, head: Bool = false, total: Bool = false, dim: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(head ? method.uppercased() : method).fontWeight(head || total ? .heavy : .bold).frame(maxWidth: .infinity, alignment: .leading)
            Text(head ? paid.uppercased() : paid).fontWeight(head ? .heavy : total ? .bold : .regular).frame(maxWidth: .infinity, alignment: .trailing)
            if wide { Text(head ? back.uppercased() : back).fontWeight(head ? .heavy : .regular).frame(maxWidth: .infinity, alignment: .trailing) }
            Text(head ? net.uppercased() : net).fontWeight(.heavy).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(head ? Font.brandText(10.6) : Theme.text(14))
        .tracking(head ? 1.27 : 0)
        .foregroundStyle(head || dim ? Theme.inkSoft : Theme.inkStrong)
        .monospacedDigit()
        .lineLimit(1)
        .padding(.vertical, head ? 0 : 6)
        .padding(.bottom, head ? 6 : 0)
        .padding(.top, total ? 2 : 0)
    }

    private func sourcesPanel(_ data: CashDayClose, _ money: @escaping (Int) -> String) -> some View {
        panel(L("Where it came from"), icon: "banknote") {
            if data.bySource.isEmpty {
                EmptyState(systemImage: "banknote", title: L("Nothing came in this day."), accent: Theme.lime)
            } else {
                VStack(spacing: 8) {
                    ForEach(data.bySource, id: \.source) { row in
                        let tone = row.source == "deposit" ? Theme.lime : CashText.sourceHue(row.source).color
                        let share = data.totals.net > 0 ? max(0, Double(row.net) / Double(data.totals.net)) : 0
                        VStack(spacing: 4) {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: Theme.tickRadius / 2, style: .continuous).fill(tone).frame(width: 10, height: 10)
                                Text(CashText.source(row.source)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                                Spacer(minLength: 8)
                                (Text(money(row.net)).font(Theme.text(14, weight: .bold)) + Text(" · \(row.count)").font(Theme.text(12)).foregroundColor(Theme.inkSoft))
                                    .monospacedDigit().foregroundStyle(Theme.inkStrong)
                            }
                            ProgressBar(value: share, height: 6, track: Theme.surfaceMuted, fill: tone)
                        }
                    }
                }
            }
        }
    }

    private func peoplePanel(_ data: CashDayClose, _ money: @escaping (Int) -> String) -> some View {
        panel(L("Who charged"), icon: "users") {
            if data.byPerson.isEmpty {
                EmptyState(systemImage: "users", title: L("Nobody charged this day."), accent: Theme.lime)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(data.byPerson.enumerated()), id: \.offset) { index, person in
                        if index > 0 { RowDivider() }
                        HStack(spacing: 12) {
                            Text(person.name ?? "—").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            Spacer(minLength: 8)
                            (Text(money(person.net ?? (person.payments - person.refunds))).font(Theme.text(14, weight: .bold))
                                + Text(" · \(LP(person.count ?? 0, "%d movement", "%d movements"))").font(Theme.text(12)).foregroundColor(Theme.inkSoft))
                                .monospacedDigit().foregroundStyle(Theme.inkStrong)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    /// Refunds of the day: money handed back (with a minus), or credit left on the account (no money moved).
    private func refundList(_ items: [CashDayClose.Refund], _ data: CashDayClose, asCredit: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { RowDivider() }
                NavigationLink(value: ProviderRoute.invoice(item.invoiceId)) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            (Text(item.clientName ?? L("Walk-in")).font(Theme.text(14, weight: .bold)) + Text(" \(item.folio)").font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.inkSoft))
                                .foregroundStyle(Theme.inkStrong).lineLimit(1)
                            Text([asCredit ? nil : CashText.method(item.method), item.by, CashDay.when(item.at, withDay: false, zone: data.timeZone.flatMap(TimeZone.init(identifier:))), Self.refundReason(item.reason)].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Text(asCredit ? cashMoney(item.amount, data.currency) : "−\(cashMoney(item.amount, data.currency))")
                            .font(Theme.text(14, weight: .bold)).monospacedDigit()
                            .foregroundStyle(asCredit ? Theme.inkStrong : Theme.destructive)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A return's old note "Refund D-000001" reads by its folio.
    static func refundReason(_ reason: String?) -> String? {
        guard let text = reason?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.hasPrefix("Refund D-"), text.dropFirst(7).allSatisfy({ $0 == "D" || $0 == "-" || $0.isNumber }) { return LF("Return %@", String(text.dropFirst(7))) }
        if text.hasPrefix("D-"), text.dropFirst(2).allSatisfy(\.isNumber) { return LF("Return %@", text) }
        return text
    }

    // MARK: Register shifts

    private func shiftsPanel(_ data: CashDayClose, _ money: @escaping (Int) -> String) -> some View {
        let totals = data.shiftTotals
        return SectionCard(title: L("Register shifts"), icon: "wallet", accent: Theme.blue) {
            if cashCanRunShift(workspace) {
                NavigationLink(value: ProviderRoute.section(.store)) { CashFinCardLinkLabel(title: L("Open the register")) }.buttonStyle(.plain)
            }
        } content: {
            if totals.shifts > 0 {
                Text(LF("Expected %@ · counted %@", money(totals.cashExpected), money(totals.cashCounted)))
                    .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                RowDivider()
            }
            if data.shifts.isEmpty {
                EmptyState(systemImage: "wallet", title: L("No register was open this day."), accent: Theme.lime)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(data.shifts.enumerated()), id: \.element.id) { index, shift in
                        if index > 0 { RowDivider() }
                        shiftRow(shift, data)
                    }
                }
            }
        }
    }

    private func shiftRow(_ shift: CashSession, _ data: CashDayClose) -> some View {
        let open = expanded == shift.id
        return VStack(spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.2)) { expanded = open ? nil : shift.id } } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(shift.registerName).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Text(shift.isOpen
                             ? LF("%@ by %@ · still open", CashDay.when(shift.openedAt, zone: shift.zone), shift.openedByName ?? "—")
                             : LF("%@ by %@ → %@ by %@", CashDay.when(shift.openedAt, zone: shift.zone), shift.openedByName ?? "—", CashDay.when(shift.closedAt, zone: shift.zone), shift.closedByName ?? "—"))
                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 1) {
                        if shift.isOpen {
                            Text(L("Open@register")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.mango)
                        } else {
                            CashDifferenceText(difference: shift.difference ?? 0, currency: data.currency)
                        }
                        Text(cashMoney(shift.countedCash ?? shift.expectedCash, data.currency)).font(Theme.text(12)).monospacedDigit().foregroundStyle(Theme.inkSoft)
                    }
                    Glyph("chevron-down", size: 16).foregroundStyle(Theme.inkSoft).rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(open ? .isSelected : [])
            if open {
                VStack(alignment: .trailing, spacing: 12) {
                    CashShiftDetail(session: shift)
                    DocumentButton(title: L("Download PDF"), systemImage: "file-down", path: "/provider-store/register-sessions/\(shift.id)/pdf", fileName: "\(shift.registerName) \(shift.openedDay ?? "")")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(Theme.blue, 4))
                .overlay(alignment: .top) { RowDivider() }
            }
        }
        .id(shift.id)
    }

    // MARK: Excepciones del día

    private static var groups: [(String, String)] { [
        ("refund", L("Refunds")), ("credit_note", L("Credit notes")), ("return", L("Returns")), ("refund_other_method", L("Refunded another way than paid")),
        // "Saldo perdonado": what was left on a bill, forgiven by the business; each row opens the bill.
        ("cancel", L("Cancellations")), ("forgiven", L("Balances forgiven")), ("discount", L("Discounts")), ("courtesy", L("Courtesies")), ("price_lowered", L("Lower prices")),
        ("no_charge", L("Visits without charge")), ("stay_no_bill", L("Check-outs without a bill")), ("cash_in", L("Cash in")), ("cash_out", L("Cash out")),
        ("cash_difference", L("Drawer differences")), ("backdated_payment", L("Backdated payments")),
    ] }

    @ViewBuilder private var exceptionsPanel: some View {
        if let exceptions {
            let present = Self.groups.compactMap { group -> (String, [CashException], Int)? in
                let items = exceptions.items.filter { $0.kind == group.0 }
                // The server's count for the kind, never below the rows shown.
                return items.isEmpty ? nil : (group.1, items, max(exceptions.counts?[group.0] ?? 0, items.count))
            }
            panel(L("Exceptions of the day"), icon: "triangle-alert", aside: {
                if exceptions.withoutReason > 0 {
                    Text(LP(exceptions.withoutReason, "%d without a reason", "%d without a reason")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.destructive)
                }
            }) {
                if present.isEmpty {
                    EmptyState(systemImage: "triangle-alert", title: L("Nothing out of the ordinary this day."), accent: Theme.lime)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L("Refunds, returns, cancels, big discounts, courtesies, lower prices, cash in and out, drawer differences and backdated payments: who, when, how much and why."))
                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        ForEach(present, id: \.0) { group in
                            CashExceptionGroup(title: group.0, count: group.2, items: group.1, currency: exceptions.currency, day: exceptions.day, zone: exceptions.timeZone.flatMap(TimeZone.init(identifier:))) { shiftId in
                                withAnimation { expanded = shiftId }
                            }
                        }
                    }
                }
            }
        } else if let exceptionsError {
            CashFinError(title: L("The exceptions could not be loaded."), message: exceptionsError) { await load() }
        } else {
            LoadingState()
        }
    }
}

/// A figure of the day (web cortes `Stat`): a tinted 24 icon disc beside the name, the amount, a line.
private struct CashFinCorteStat: View {
    let icon: String
    let accent: Color
    let label: String
    let value: String
    let hint: Text
    var bad: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Glyph(icon, size: 14).foregroundStyle(Theme.inkStrong)
                    .frame(width: 24, height: 24)
                    .background(Theme.wash(accent, 24), in: Circle())
                Text(label.uppercased()).font(.brandText(10.6, weight: .heavy)).tracking(1.27).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            Text(value).font(.brandHeading(20)).monospacedDigit().foregroundStyle(bad ? Theme.destructive : Theme.inkStrong)
                .lineLimit(1).minimumScaleFactor(0.6).padding(.top, 6)
            hint.font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        .cardShadow()
    }
}

/// One kind of exception: its first rows, then "Ver N más".
private struct CashExceptionGroup: View {
    let title: String
    /// The server's count for the kind (`counts`), never below the rows shown.
    var count: Int? = nil
    let items: [CashException]
    let currency: String
    let day: String
    let zone: TimeZone?
    let onShift: (String) -> Void
    @State private var all = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title) · \(count ?? items.count)".uppercased()).font(.brandText(10.6, weight: .heavy)).tracking(1.27).foregroundStyle(Theme.inkSoft)
            VStack(spacing: 0) {
                ForEach(Array((all ? items : Array(items.prefix(5))).enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowDivider() }
                    row(item)
                }
            }
            if !all && items.count > 5 {
                Button { all = true } label: {
                    Text(LF("Show %d more", items.count - 5)).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                        .padding(.horizontal, 12).frame(height: 40).contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sign(_ item: CashException) -> String {
        if item.direction == "in" || item.direction == "over" { return "+" }
        if item.direction == "out" || item.direction == "short" { return "−" }
        if item.kind == "backdated_payment" { return "+" }
        return ["discount", "courtesy", "price_lowered", "no_charge", "stay_no_bill"].contains(item.kind) ? "" : "−"
    }

    private func route(_ item: CashException) -> ProviderRoute? {
        switch item.link.to {
        case "sale": .sale(item.link.id)
        case "invoice": .invoice(item.link.id)
        case "visit": .appointment(item.link.id)
        case "stay": .stay(item.link.id)
        default: nil
        }
    }

    @ViewBuilder private func row(_ item: CashException) -> some View {
        let who = [item.clientName, item.petName].compactMap { $0?.nonEmpty }.joined(separator: " · ")
        let what = [who.nonEmpty ?? item.registerName ?? (item.documentKind == "sale" ? L("Walk-in") : nil), item.lineLabel].compactMap { $0?.nonEmpty }.joined(separator: " — ")
        let details: [String?] = [
            CashDay.when(item.at, withDay: false, zone: zone),
            item.actorName.map { LF("By %@", $0) },
            item.kind == "refund_other_method" && !(item.paidWith ?? []).isEmpty ? LF("Paid with %@", (item.paidWith ?? []).map { CashText.method($0) }.joined(separator: ", ")) : nil,
            item.method.map { CashText.method($0) },
            item.kind == "backdated_payment" ? item.paidOn.map { LF("Dated %@", CashDay.short($0)) } : nil,
            item.visitOn.flatMap { $0 != day ? LF("Visit of %@", CashDay.short($0)) : nil },
        ]
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                (Text(what.nonEmpty ?? "—").font(Theme.text(14, weight: .bold)) + Text(item.documentFolio.map { " \($0)" } ?? "").font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.inkSoft))
                    .foregroundStyle(Theme.inkStrong).lineLimit(1)
                Text(details.compactMap { $0 }.joined(separator: " · ")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                if let reason = item.reason?.nonEmpty {
                    Text("“\(reason)”").font(Theme.text(12)).foregroundStyle(Theme.inkStrong)
                } else {
                    Text(L("No reason")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.destructive)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(sign(item))\(cashMoney(item.amount, currency))").font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                if let target = route(item) {
                    NavigationLink(value: target) { CashFinCardLinkLabel(title: L("Open@link")) }.buttonStyle(.plain)
                } else if item.link.to == "session" {
                    Button { onShift(item.link.id) } label: { CashFinCardLinkLabel(title: L("Open@link")) }.buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
