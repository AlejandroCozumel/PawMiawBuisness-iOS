//
//  CashRegisterViews.swift
//  PawMiawNegocios
//
//  The cash drawer (web: store-register.tsx, register/shift-forms.tsx,
//  register/shift-detail.tsx): open a shift with the cash in the drawer,
//  cash in and out with a reason, close it against a count (bills and coins
//  helper, the card terminal, what stays for the next shift, the reason for
//  any difference), and the shifts before.
//

import SwiftUI

// MARK: - Bills and coins

enum CashDenominations {
    struct Piece: Identifiable, Hashable { let id: String; let isBill: Bool; let value: Int }

    private static let sets: [String: (bills: [Int], coins: [Int])] = [
        "MXN": ([100_000, 50_000, 20_000, 10_000, 5_000, 2_000], [2_000, 1_000, 500, 200, 100, 50]),
        "USD": ([10_000, 5_000, 2_000, 1_000, 500, 100], [25, 10, 5, 1]),
        "CAD": ([10_000, 5_000, 2_000, 1_000, 500], [200, 100, 25, 10, 5]),
        "EUR": ([50_000, 20_000, 10_000, 5_000, 2_000, 1_000, 500], [200, 100, 50, 20, 10, 5, 2, 1]),
        "COP": ([10_000_000, 5_000_000, 2_000_000, 1_000_000, 500_000, 200_000], [100_000, 50_000, 20_000, 10_000, 5_000]),
    ]

    static func pieces(_ currency: String) -> [Piece]? {
        guard let set = sets[currency.uppercased()] else { return nil }
        return set.bills.map { Piece(id: "bill:\($0)", isBill: true, value: $0) } + set.coins.map { Piece(id: "coin:\($0)", isBill: false, value: $0) }
    }

    /// "$500", "$0.50".
    static func face(_ cents: Int) -> String {
        cents % 100 == 0 ? "$\((cents / 100).formatted())" : String(format: "$%.2f", Double(cents) / 100)
    }
}

// MARK: - Small parts (web: shift-forms.tsx, shift-detail.tsx)

/// A label over a figure in a bordered box (web `Figure`): 10.6 caps, the
/// value in Fredoka 18, a hint; `strong` takes the blue edge.
private struct CashFigureBox: View {
    let label: String
    let value: String
    var hint: String? = nil
    var strong: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.brandText(10.6, weight: .heavy)).tracking(1.27).foregroundStyle(Theme.inkSoft).lineLimit(1)
            Text(value).font(.brandHeading(18)).monospacedDigit().foregroundStyle(Theme.inkStrong).lineLimit(1).minimumScaleFactor(0.7)
            if let hint { Text(hint).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(strong ? Theme.blue : Theme.borderSoft, lineWidth: 1))
    }
}

/// One line of a shift's summary (web `Line`): the label (and a hint under it), the amount right-aligned.
private struct CashShiftLine<Value: View>: View {
    let label: String
    var hint: String? = nil
    var strong: Bool = false
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                if let hint = hint?.nonEmpty { Text(hint).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
            }
            Spacer(minLength: 8)
            value()
                .font(Theme.text(14, weight: strong ? .heavy : .bold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}

extension CashShiftLine where Value == Text {
    init(_ label: String, _ value: String, hint: String? = nil, strong: Bool = false, tone: Color? = nil) {
        self.init(label: label, hint: hint, strong: strong) { Text(value).foregroundStyle(tone ?? Theme.inkStrong) }
    }
}

/// A caps heading inside a shift's summary, with an optional icon.
private struct CashShiftHeading: View {
    let text: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Glyph(icon, size: 14) }
            Text(text.uppercased())
        }
        .font(.brandText(11.2, weight: .heavy))
        .tracking(1.34)
        .foregroundStyle(Theme.inkSoft)
        .padding(.bottom, 4)
    }
}

// MARK: - A shift's figures

/// The shift at a glance (web `ShiftFigures`): sales, the cash expected, each other
/// method, cash in and out — two to a row, four on a wide screen.
struct CashShiftFigures: View {
    let session: CashSession
    var showExpected: Bool = true
    var showCash: Bool = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let currency = Workspace.shared.currency
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: sizeClass == .regular ? 4 : 2), spacing: 10) {
            CashFigureBox(label: L("Sales"), value: "\(session.saleCount)", hint: cashMoney(session.salesTotal, currency))
            if showExpected {
                CashFigureBox(label: L("Cash expected"), value: cashMoney(session.expectedCash, currency), hint: LF("Starting cash %@", cashMoney(session.openingCash, currency)), strong: true)
            }
            ForEach(session.byMethod.filter { showCash || $0.method != "cash" }, id: \.method) { entry in
                CashFigureBox(label: CashText.method(entry.method), value: cashMoney(entry.payments - entry.refunds, currency),
                              hint: entry.refunds > 0 ? LF("%@ refunded", cashMoney(entry.refunds, currency)) : nil)
            }
            if session.cashIn > 0 || session.cashOut > 0 {
                CashFigureBox(label: L("Cash in / out"), value: "+\(cashMoney(session.cashIn, currency))", hint: "−\(cashMoney(session.cashOut, currency))")
            }
        }
    }
}

/// Everything a shift holds, as it closed or as it stands (web `ShiftDetail`; Store history, Finance › Cortes).
struct CashShiftDetail: View {
    let session: CashSession
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) { opened; cash }.frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 16) { methods; terminal }.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) { opened; cash; methods; terminal }
        }
    }

    private var currency: String { Workspace.shared.currency }
    private var zone: TimeZone { session.zone }

    private var opened: some View {
        VStack(alignment: .leading, spacing: 0) {
            CashShiftHeading(text: L("Opened"), icon: "lock-open")
            CashShiftLine(L("By"), session.openedByName ?? "—")
            CashShiftLine(L("At"), CashDay.when(session.openedAt, zone: zone))
            CashShiftLine(L("Starting cash"), cashMoney(session.openingCash, currency),
                          hint: session.openingExpected.map { LF("The last close left %@", cashMoney($0, currency)) })
            if let difference = session.openingDifference, difference != 0 {
                CashShiftLine(label: L("Against the last close"), hint: session.openingNote) { CashDifferenceText(difference: difference, currency: currency) }
            }
            HStack(spacing: 6) {
                CashShiftHeading(text: session.isOpen ? L("Still open") : L("Closed@shift"), icon: "lock")
                if session.frozen == true { Chip(text: L("Frozen"), tone: .muted, icon: "snowflake").padding(.bottom, 4) }
            }
            .padding(.top, 12)
            if session.isOpen {
                Text(session.stale == true ? L("Open since an earlier day") : L("Open now")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.mango).padding(.vertical, 4)
            } else {
                CashShiftLine(L("By"), session.closedByName ?? "—")
                CashShiftLine(L("At"), CashDay.when(session.closedAt, zone: zone))
            }
        }
    }

    private var cash: some View {
        let cashFigure = session.byMethod.first(where: { $0.method == "cash" })
        return VStack(alignment: .leading, spacing: 0) {
            CashShiftHeading(text: L("Cash"))
            CashShiftLine(L("Starting cash"), cashMoney(session.openingCash, currency))
            CashShiftLine(L("Cash taken"), "+\(cashMoney(cashFigure?.payments ?? 0, currency))")
            if let refunds = cashFigure?.refunds, refunds > 0 { CashShiftLine(L("Cash given back"), "−\(cashMoney(refunds, currency))") }
            ForEach(session.cashMovements) { movement in
                let isIn = movement.kind == "cash_in"
                CashShiftLine(label: isIn ? L("Cash in") : L("Cash out"),
                              hint: [movement.reason, movement.actorName, CashDay.when(movement.createdAt, withDay: false, zone: zone)].compactMap { $0?.nonEmpty }.joined(separator: " · ")) {
                    HStack(spacing: 4) {
                        Glyph(isIn ? "arrow-down-to-line" : "arrow-up-from-line", size: 14)
                        Text("\(isIn ? "+" : "−")\(cashMoney(movement.amount, currency))")
                    }
                    .foregroundStyle(Theme.inkStrong)
                }
            }
            StitchedDivider().padding(.vertical, 4)
            CashShiftLine(L("Expected in the drawer"), cashMoney(session.expectedCash, currency), strong: true)
            if !session.isOpen {
                CashShiftLine(L("Counted"), session.countedCash.map { cashMoney($0, currency) } ?? "—", strong: true)
                CashShiftLine(label: L("Difference")) { CashDifferenceText(difference: session.difference ?? 0, currency: currency) }
                if let left = session.cashLeft, let counted = session.countedCash, left != counted {
                    CashShiftLine(L("Left for the next shift"), cashMoney(left, currency), hint: LF("%@ to the safe or the bank", cashMoney(counted - left, currency)))
                }
            }
            if let pieces = session.denominations, !pieces.isEmpty {
                Text(pieces.sorted { (Int($0.key) ?? 0) > (Int($1.key) ?? 0) }.map { "\(CashDenominations.face(Int($0.key) ?? 0)) × \($0.value)" }.joined(separator: " · "))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).padding(.top, 4)
            }
        }
    }

    private var methods: some View {
        VStack(alignment: .leading, spacing: 0) {
            CashShiftHeading(text: L("By method"))
            if session.byMethod.isEmpty { Text(L("Nothing taken in this shift.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.vertical, 4) }
            ForEach(session.byMethod, id: \.method) { entry in
                CashShiftLine(CashText.method(entry.method), cashMoney(entry.payments - entry.refunds, currency),
                              hint: entry.refunds > 0 ? LF("%@ refunded", cashMoney(entry.refunds, currency)) : nil)
            }
            CashShiftLine(L("Sales in the shift"), "\(session.saleCount) · \(cashMoney(session.salesTotal, currency))")
            if let returns = session.returnCount, returns > 0 { CashShiftLine(L("Returns"), "\(returns)") }
        }
    }

    private var terminal: some View {
        VStack(alignment: .leading, spacing: 0) {
            CashShiftHeading(text: L("Card terminal"))
            CashShiftLine(L("Card recorded"), cashMoney(session.cardTotal, currency))
            CashShiftLine(L("Terminal report"), session.cardTerminalTotal.map { cashMoney($0, currency) } ?? L("Not entered"))
            if let gap = session.cardDifference {
                CashShiftLine(L("Difference"), gap == 0 ? L("Matches") : "\(gap > 0 ? "+" : "−")\(cashMoney(abs(gap), currency))", tone: gap == 0 ? Theme.blue : Theme.mango)
            }
            if let people = session.byPerson, !people.isEmpty {
                CashShiftHeading(text: L("Who charged")).padding(.top, 12)
                ForEach(people, id: \.self) { person in
                    CashShiftLine(person.name ?? "—", cashMoney(person.payments - person.refunds, currency), hint: LP(person.count ?? 0, "%d payment", "%d payments"))
                }
            }
            if let note = session.closingNote?.nonEmpty {
                (Text("\(L("Note")): ").font(Theme.text(14, weight: .bold)) + Text(note).font(Theme.text(14)))
                    .foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - Opening

/// Open a shift (web `OpenShiftSheet`): the starting cash comes filled in with what the
/// last close left; a different figure is kept but flagged, with room to say why.
struct CashOpenShiftSheet: View {
    let register: CashRegister
    var onOpened: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var amount: Int?
    @State private var note = ""
    @State private var working = false
    @State private var seed = 0

    private var suggested: Int? { register.lastCashLeft }

    var body: some View {
        ProviderModal(title: LF("Open %@", register.name), subtitle: L("Count the cash in the drawer to start with."), systemImage: "lock-open", accent: .aqua, isDirty: !note.isEmpty, form: form, primaryTitle: LF("Open with %@", cashMoney(amount ?? 0)), isWorking: working, primaryIcon: "lock-open") {
            save()
        } content: {
            MoneyField(label: L("Starting cash"), cents: $amount, key: "amount", form: form,
                       hint: suggested.map { LF("The last close left %@ in the drawer. Count it and change it if it isn’t there.", cashMoney($0)) } ?? L("Count what is in the drawer now; the close is checked against it."), caps: true)
                .id(seed)
            if let suggested, let amount, amount != suggested {
                // The web's mango box: the difference, then why (optional).
                NoticeCard(tone: .warning, icon: "triangle-alert") {
                    Text(amount < suggested
                         ? LF("%@ less than the last close left.", cashMoney(suggested - amount))
                         : LF("%@ more than the last close left.", cashMoney(amount - suggested)))
                        .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    TextField(L("Why (optional): taken to the bank, change brought in…"), text: $note)
                        .font(Theme.text(14))
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
                        .padding(.top, 4)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { amount = register.lastCashLeft ?? register.defaultOpeningCash; seed += 1 }
    }

    private func save() {
        guard form.check([("amount", amount == nil ? L("Count the cash in the drawer to start with.") : nil)]) else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let _: EmptyResponse = try await API.post("/provider-store/registers/\(register.id)/open", body: ["openingCash": amount ?? 0, "note": note.nonEmpty])
                Toast.show(LF("%@ is open.", register.name))
                NotificationCenter.default.post(name: CashDeviceRegister.changed, object: nil)
                announceDataChanged()
                onOpened()
                dismiss()
            } catch {
                form.apply(error, known: ["openingCash": "amount"])
            }
        }
    }
}

// MARK: - Cash in and out

/// Cash in or out with its why (web `CashSheet`): never more out than the drawer should hold.
struct CashMoveSheet: View {
    let session: CashSession
    let kind: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var amount: Int?
    @State private var reason = ""
    @State private var working = false

    private var out: Bool { kind == "cash_out" }

    var body: some View {
        ProviderModal(title: out ? L("Take cash out") : L("Put cash in"), subtitle: out ? L("A supplier paid in cash, or cash taken to the bank.") : L("Change brought to the drawer, for example."), systemImage: "wallet", accent: .aqua, isDirty: amount != nil || !reason.isEmpty, form: form, primaryTitle: LF("Record %@", cashMoney(amount ?? 0)), isWorking: working, primaryIcon: out ? "arrow-up-from-line" : "arrow-down-to-line") {
            save()
        } content: {
            MoneyField(label: L("Amount"), cents: $amount, key: "amount", form: form, caps: true)
            PMTextField(L("Why (required)"), text: $reason, key: "reason", form: form, prompt: out ? L("Paid the water delivery") : L("Change from the bank"), caps: true)
            // What the drawer should hold once this is recorded.
            if let value = amount, value > 0, !(out && value > max(0, session.expectedCash)) {
                HStack(spacing: 12) {
                    Text(L("Cash expected after this")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    Spacer(minLength: 8)
                    Text(cashMoney(session.expectedCash + (out ? -value : value))).font(.brandHeading(16)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func drawerHolds(_ cents: Int) -> String {
        LF("The drawer should hold %@ in cash: you cannot take out more.", cashMoney(cents))
    }

    private func save() {
        let value = amount ?? 0
        let tooMuch = out && value > max(0, session.expectedCash)
        guard form.check([
            ("amount", value <= 0 ? L("Enter an amount") : tooMuch ? drawerHolds(max(0, session.expectedCash)) : nil),
            ("reason", reason.nonEmpty == nil ? L("Say why the cash goes in or out") : nil),
        ]) else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let _: EmptyResponse = try await API.post("/provider-store/register-sessions/\(session.id)/cash", body: ["kind": kind, "amount": value, "reason": reason.nonEmpty])
                NotificationCenter.default.post(name: CashDeviceRegister.changed, object: nil)
                announceDataChanged()
                dismiss()
            } catch {
                if cashErrorCode(error) == "not_enough_cash" {
                    _ = form.check([("amount", errorText(error))])
                } else {
                    form.apply(error, known: ["amount": "amount", "reason": "reason"])
                }
            }
        }
    }
}

// MARK: - Closing

/// Closing a shift in two steps (web `CloseShiftSheet`): count the drawer (typed,
/// or added up with the bills-and-coins helper) and the card terminal; then review
/// it against what the drawer should hold, keep what stays, and say why when the
/// count is off.
struct CashCloseShiftSheet: View {
    let session: CashSession
    var onClosed: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var reviewing = false
    @State private var typed: Int?
    @State private var counts: [String: String] = [:]
    @State private var helperOpen = false
    @State private var terminal: Int?
    @State private var keepAll = true
    @State private var left: Int?
    @State private var note = ""
    @State private var working = false

    private var currency: String { Workspace.shared.currency }
    private var pieces: [CashDenominations.Piece]? { CashDenominations.pieces(currency) }

    /// The helper's total and what the server takes (value → how many), or nil when nothing is counted.
    private var helper: (total: Int, byValue: [String: Int], pieces: Int)? {
        guard let pieces else { return nil }
        var total = 0, count = 0
        var byValue: [String: Int] = [:]
        for piece in pieces {
            guard let raw = counts[piece.id]?.nonEmpty, let n = Int(raw), n > 0 else { continue }
            byValue[String(piece.value), default: 0] += n
            total += piece.value * n
            count += n
        }
        return count > 0 ? (total, byValue, count) : nil
    }

    private var counted: Int? { helper?.total ?? typed }
    private var difference: Int? { counted.map { $0 - session.expectedCash } }
    private var dirty: Bool { helper != nil || typed != nil || terminal != nil || !note.isEmpty || !keepAll }

    var body: some View {
        ProviderModal(
            title: LF("Close %@", session.registerName),
            subtitle: reviewing ? L("Check the count against what the drawer should hold, then close.") : LF("Opened %@ by %@. Count the cash in the drawer.", CashDay.when(session.openedAt, zone: session.zone), session.openedByName ?? "—"),
            systemImage: "lock", accent: .aqua, isDirty: dirty, form: form,
            primaryTitle: reviewing ? LF("Close %@", session.registerName) : L("Continue"),
            isWorking: working,
            steps: ModalSteps(steps: [(L("Count"), "calculator"), (L("Review"), "clipboard-check")], current: reviewing ? 1 : 0),
            onBack: reviewing ? { reviewing = false } : nil,
            primaryIcon: reviewing ? "lock" : nil
        ) {
            if reviewing { submit() } else { review() }
        } content: {
            if reviewing { reviewStep } else { countStep }
        }
    }

    @ViewBuilder private var countStep: some View {
        if let helper {
            FormField(label: L("Cash counted"), key: "counted", hint: L("From the bills and coins below."), form: form, caps: true) {
                Text(cashMoney(helper.total)).font(Theme.text(20, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fieldChrome()
            }
        } else {
            MoneyField(label: L("Cash counted"), cents: $typed, key: "counted", form: form, hint: L("What the drawer should hold shows in the next step, after the count."), caps: true)
        }
        if let pieces {
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(.easeOut(duration: 0.2)) { helperOpen.toggle() } } label: {
                    HStack(spacing: 8) {
                        Glyph("calculator", size: 16).foregroundStyle(Theme.blue)
                        Text(L("Count bills and coins")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        Spacer(minLength: 8)
                        if let helper { Text(LP(helper.pieces, "%d piece", "%d pieces")).font(Theme.text(12, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkSoft) }
                        Glyph("chevron-down", size: 16).foregroundStyle(Theme.inkSoft).rotationEffect(.degrees(helperOpen ? 180 : 0))
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if helperOpen {
                    RowDivider()
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach([true, false], id: \.self) { bills in
                            VStack(alignment: .leading, spacing: 6) {
                                Text((bills ? L("Bills") : L("Coins")).uppercased()).font(.brandText(10.6, weight: .heavy)).tracking(1.27).foregroundStyle(Theme.inkSoft)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                                    ForEach(pieces.filter { $0.isBill == bills }) { piece in
                                        HStack(spacing: 8) {
                                            Text(CashDenominations.face(piece.value)).font(Theme.text(14, weight: .heavy)).monospacedDigit().foregroundStyle(Theme.inkStrong).frame(width: 56, alignment: .leading)
                                            Text("×").font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                                            TextField("0", text: Binding(get: { counts[piece.id] ?? "" }, set: { counts[piece.id] = $0.filter(\.isNumber) }))
                                                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                                .font(Theme.text(14)).monospacedDigit()
                                                .padding(.horizontal, 8)
                                                .frame(height: 32)
                                                .background(Theme.inputFill, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                                                .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                                                .accessibilityLabel(LF("How many of %@", CashDenominations.face(piece.value)))
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                                    }
                                }
                            }
                        }
                        RowDivider()
                        HStack {
                            Text(L("Total counted")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkSoft)
                            Spacer(minLength: 8)
                            Text(cashMoney(helper?.total ?? 0)).font(.brandHeading(18)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                        }
                        if helper != nil {
                            Button(L("Clear and type the total instead")) { counts = [:] }
                                .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue)
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        }
        // The label says "(optional)" itself, as the web's does.
        MoneyField(label: L("Card terminal total (optional)"), cents: $terminal, hint: L("What the terminal’s own report says for this shift. It is noted with the close, never blocks it."), caps: true)
    }

    @ViewBuilder private var reviewStep: some View {
        if let counted, let difference {
            let threshold = session.alertThreshold ?? 0
            let red = threshold > 0 ? (difference < 0 && abs(difference) > threshold) : difference < 0
            let tone: ProviderState = difference == 0 ? .done : red ? .problem : .waiting
            // Expected against counted (web: the review's first box), in the difference's colour.
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    reviewFigure(L("Expected in the drawer"), cashMoney(session.expectedCash))
                    reviewFigure(L("Counted"), cashMoney(counted))
                }
                Rectangle().fill(Theme.mix(tone.color, 40, with: Theme.borderSoft)).frame(height: 1)
                HStack(spacing: 8) {
                    Text(L("Difference").uppercased()).font(.brandText(10.6, weight: .heavy)).tracking(1.27).foregroundStyle(Theme.inkSoft)
                    Spacer(minLength: 8)
                    Circle().fill(tone.color).frame(width: 8, height: 8)
                    Text(difference == 0 ? L("Exact") : difference < 0 ? LF("Short %@", cashMoney(-difference, currency)) : LF("Over %@", cashMoney(difference, currency)))
                        .font(.brandHeading(20)).monospacedDigit()
                        .foregroundStyle(tone == .problem ? Theme.destructive : Theme.inkStrong)
                }
                .padding(12)
            }
            .background(Theme.wash(tone.color, 10), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(tone.color, 60, with: Theme.borderSoft), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(L("This shift"), caps: true)
                CashShiftFigures(session: session, showExpected: false, showCash: true)
                Text(cardLine).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
            // The web's checkbox row.
            Button { withAnimation(.easeOut(duration: 0.2)) { keepAll.toggle() } } label: {
                HStack(alignment: .top, spacing: 12) {
                    Tick(on: keepAll).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Leave all of it in the drawer for the next shift")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        Text(L("The next shift starts with it. Untick if some goes to the safe or the bank.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(keepAll ? .isSelected : [])
            if !keepAll {
                MoneyField(label: L("Left in the drawer"), cents: $left, key: "left", form: form, caps: true)
            }
            if difference != 0 {
                CashReasonField(kind: .cashDifference, text: $note, key: "note", form: form, hint: LF("The count is off by %@: the owner sees why.", cashMoney(abs(difference))))
            } else {
                PMTextField(L("Note"), text: $note, key: "note", form: form, prompt: L("Anything that explains a difference"), multiline: true, caps: true)
            }
            if threshold > 0, abs(difference) > threshold {
                Text(LF("The difference is over %@: say what happened. The owner is told.", cashMoney(threshold))).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.destructive)
            }
        }
    }

    private func reviewFigure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.brandText(10.6, weight: .heavy)).tracking(1.27).foregroundStyle(Theme.inkSoft).lineLimit(2)
            Text(value).font(.brandHeading(18)).monospacedDigit().foregroundStyle(Theme.inkStrong)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardLine: String {
        var parts = [LF("Card recorded in this shift: %@", cashMoney(session.cardTotal))]
        if let terminal {
            parts.append(LF("the terminal says %@", cashMoney(terminal)))
            let gap = terminal - session.cardTotal
            parts.append(gap == 0 ? L("matches") : gap < 0 ? LF("the terminal shows %@ less", cashMoney(-gap)) : LF("the terminal shows %@ more", cashMoney(gap)))
        }
        return parts.joined(separator: " · ")
    }

    private func review() {
        guard form.check([("counted", counted == nil ? L("Count the drawer first.") : nil)]) else { return }
        reviewing = true
    }

    private func submit() {
        guard let counted else { reviewing = false; return }
        guard form.check([
            ("left", !keepAll && left == nil ? L("Enter an amount") : nil),
            ("note", (difference ?? 0) != 0 && note.nonEmpty == nil ? CashReasonKind.cashDifference.required : nil),
        ]) else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let body: [String: Any?] = [
                    "countedCash": counted,
                    "denominations": helper?.byValue,
                    "cardTerminalTotal": terminal,
                    "cashLeft": keepAll ? nil : left,
                    "note": note.nonEmpty,
                ]
                let _: EmptyResponse = try await API.post("/provider-store/register-sessions/\(session.id)/close", body: body)
                Toast.show(LF("%@ is closed.", session.registerName))
                NotificationCenter.default.post(name: CashDeviceRegister.changed, object: nil)
                announceDataChanged()
                onClosed()
                dismiss()
            } catch {
                if cashAsksReason(error) {
                    _ = form.check([("note", errorText(error))])
                } else {
                    form.apply(error, known: ["note": "note", "countedCash": "counted"])
                }
            }
        }
    }
}

// MARK: - The Register tab

/// The cash drawer at this counter (web `StoreRegister`): open a shift (anyone who sells or
/// takes payments), cash in and out with a reason (register managers), close it against a
/// count; and the shifts before.
struct CashRegisterTab: View {
    @ObservedObject var device: CashDeviceRegister
    @EnvironmentObject private var workspace: Workspace
    @State private var opening = false
    @State private var closing = false
    @State private var moving: String?
    @State private var adding = false
    @State private var newName = ""
    @State private var addingWorking = false

    private var canRun: Bool { cashCanRunShift(workspace) }
    private var canManage: Bool { workspace.can(.registerManage) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let register = device.register {
                statusCard(register)
            } else if device.loaded {
                // A place with no counter yet (a new location): say so instead of an empty tab.
                EmptyState(systemImage: "wallet", title: L("No register here yet"), message: canManage ? L("Add one to open a shift and take cash at this location.") : L("Someone who runs the register can add one for this location."), accent: Theme.mango, panel: true)
            } else {
                LoadingState()
            }
            if canManage { addRegister }
            if workspace.moneyLevel >= .frontDesk {
                CashShiftHistory(anyDay: workspace.moneyLevel >= .finances)
            }
        }
        .sheet(isPresented: $opening) { if let register = device.register { CashOpenShiftSheet(register: register) } }
        .sheet(isPresented: $closing) { if let session = device.session { CashCloseShiftSheet(session: session) } }
        .sheet(item: Binding(get: { moving.map { CashMoveKind(kind: $0) } }, set: { moving = $0?.kind })) { move in
            if let session = device.session { CashMoveSheet(session: session, kind: move.kind) }
        }
    }

    @ViewBuilder private func statusCard(_ register: CashRegister) -> some View {
        let session = device.session
        // Open is green (the stable token); closed is a plain card.
        Card(padding: 16, tint: session != nil ? ProviderState.done.color : nil, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    statusTitle(register, session)
                    Spacer(minLength: 8)
                    statusActions(session)
                }
                VStack(alignment: .leading, spacing: 16) {
                    statusTitle(register, session)
                    statusActions(session)
                }
            }
            if let session, session.stale == true {
                HStack(alignment: .top, spacing: 8) {
                    Glyph("triangle-alert", size: 16).foregroundStyle(Theme.mango).padding(.top, 2)
                    Text(LF("This shift is from %@ and is still open — count it and close it before taking today’s cash.", CashDay.when(session.openedAt, zone: session.zone)))
                        .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(Theme.mango, 18), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            }
            if let session {
                VStack(alignment: .leading, spacing: 12) {
                    CashShiftFigures(session: session)
                    if canManage && !session.cashMovements.isEmpty { movements(session) }
                }
            } else {
                Text(canRun ? L("Open the register with the cash in the drawer to take cash. Card and transfer work either way.") : L("The register is closed. Someone who sells or takes payments can open it.")
                     + (register.lastCashLeft.map { " " + LF("The last close left %@.", cashMoney($0)) } ?? ""))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func statusTitle(_ register: CashRegister, _ session: CashSession?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            IconBadge(icon: session != nil ? "lock-open" : "lock", accent: session != nil ? ProviderState.done.color : Theme.aqua, size: 44, iconSize: 20, ink: .strong)
            VStack(alignment: .leading, spacing: 0) {
                Text(register.name.uppercased()).font(Theme.text(12, weight: .bold)).tracking(1.7).foregroundStyle(Theme.inkSoft).lineLimit(1)
                Text(session != nil ? L("Open@register") : L("Closed@register")).font(.brandHeading(24, relativeTo: .title2)).foregroundStyle(Theme.inkStrong)
                if let session {
                    Text(LF("Since %@ · %@", CashDay.when(session.openedAt, zone: session.zone), session.openedByName ?? "")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    @ViewBuilder private func statusActions(_ session: CashSession?) -> some View {
        if session != nil {
            FlowLayout(spacing: 8) {
                if canManage {
                    PMButton(L("Cash in"), systemImage: "arrow-down-to-line", variant: .outline) { moving = "cash_in" }
                    PMButton(L("Cash out"), systemImage: "arrow-up-from-line", variant: .outline) { moving = "cash_out" }
                }
                if canRun { PMButton(L("Close register"), systemImage: "lock") { closing = true } }
            }
        } else if canRun {
            PMButton(L("Open register"), systemImage: "lock-open") { opening = true }
        }
    }

    /// Cash put in and taken out during the open shift, newest first (web `CashMovements`).
    private func movements(_ session: CashSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Cash in / out").uppercased()).font(.brandText(10.6, weight: .heavy)).tracking(1.27).foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
            ForEach(Array(session.cashMovements.sorted { $0.createdAt > $1.createdAt }.enumerated()), id: \.element.id) { index, movement in
                let out = movement.kind == "cash_out"
                if index > 0 { RowDivider() }
                HStack(spacing: 12) {
                    Glyph(out ? "arrow-up-from-line" : "arrow-down-to-line", size: 14)
                        .foregroundStyle(Theme.inkStrong)
                        .frame(width: 28, height: 28)
                        .background(Theme.wash(out ? Theme.mango : ProviderState.done.color, 24), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(movement.reason?.nonEmpty ?? (out ? L("Cash out") : L("Cash in"))).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Text([CashDay.when(movement.createdAt, withDay: false, zone: session.zone), movement.actorName].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text("\(out ? "−" : "+")\(cashMoney(movement.amount))").font(.brandHeading(16)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    @ViewBuilder private var addRegister: some View {
        if adding {
            HStack(spacing: 8) {
                TextField(L("Name, e.g. Caja estética"), text: $newName)
                    .font(Theme.bodyFont)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(Theme.inputFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
                    .accessibilityLabel(L("Register name"))
                PMButton(L("Add"), isWorking: addingWorking) { add() }.disabled(newName.nonEmpty == nil)
                PMButton(L("Cancel"), variant: .outline) { adding = false; newName = "" }
            }
        } else {
            Button { adding = true } label: {
                HStack(spacing: 6) {
                    Glyph("plus", size: 16)
                    Text(L("Add another register"))
                }
                .font(Theme.text(14, weight: .bold))
                .foregroundStyle(Theme.blue)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private func add() {
        guard let name = newName.nonEmpty else { return }
        addingWorking = true
        Task {
            defer { addingWorking = false }
            do {
                let _: EmptyResponse = try await API.post("/provider-store/registers", body: ["name": name, "locationId": workspace.locationId])
                Toast.show(LF("%@ is ready. Choose it at the top on the device that uses it.", name))
                newName = ""
                adding = false
                await device.load()
            } catch {
                Toast.error(error, fallback: L("Could not add the register."))
            }
        }
    }
}

private struct CashMoveKind: Identifiable { let kind: String; var id: String { kind } }

/// Past shifts, newest first, 20 at a time as the list scrolls; a day narrows them to that day (web `ShiftHistory`).
struct CashShiftHistory: View {
    let anyDay: Bool
    @State private var day: Date?
    @State private var expanded: String?
    @StateObject private var pager = Pager<CashSession> { _, _ in Page(items: [], total: 0) }

    private var today: Date { Date() }
    private var firstDay: Date? {
        anyDay ? nil : DateText.calendar.date(byAdding: .day, value: -(MoneyLevel.frontDeskDays - 1), to: today)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { heading; Spacer(minLength: 8); dayControls }
                VStack(alignment: .leading, spacing: 8) { heading; dayControls }
            }
            ListCard {
                if !pager.loadedOnce && pager.isLoading {
                    LoadingState()
                } else if let error = pager.error, pager.items.isEmpty {
                    ErrorState(message: error) { await pager.reload() }
                } else if pager.items.isEmpty {
                    EmptyState(systemImage: "wallet", title: day != nil ? L("No shifts that day.") : L("No shifts yet."), accent: Theme.mango)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(pager.items.enumerated()), id: \.element.id) { index, session in
                            if index > 0 { RowDivider() }
                            shiftRow(session).onAppear { pager.loadMoreIfNeeded(session) }
                        }
                        PagerFooter(pager: pager)
                    }
                }
            }
            .opacity(pager.isLoading && pager.loadedOnce ? 0.7 : 1)
            if let total = pager.total, total > 0 {
                Text(LP(total, "%d shift", "%d shifts")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.horizontal, 4)
            }
        }
        .task(id: day) {
            let period = day.map { DateText.dayKey($0) }
            pager.fetch = { offset, limit in
                let page: CashSessionPage = try await API.get("/provider-store/register-sessions", query: ["limit": "\(limit)", "offset": "\(offset)", "period": period, "locationId": Workspace.shared.locationId])
                return Page(items: page.items, total: page.total, hasMore: page.hasMore)
            }
            await pager.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pawMiawDataChanged)) { _ in Task { await pager.reload() } }
    }

    private var heading: some View {
        HStack(spacing: 8) {
            Glyph("history", size: 20).foregroundStyle(Theme.blue)
            Text(L("Shifts")).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
        }
    }

    private var dayControls: some View {
        HStack(spacing: 8) {
            PillDatePicker(text: day.map { CashDay.short(DateText.dayKey($0)) } ?? (anyDay ? L("Any day") : L("Last 7 days")),
                           date: Binding(get: { day ?? today }, set: { picked in
                               let lower = firstDay ?? .distantPast
                               day = min(max(picked, lower), today)
                           }))
            if day != nil {
                PMButton(anyDay ? L("Every day") : L("Last 7 days"), systemImage: "x", variant: .outline, size: .compact) { day = nil }
            }
        }
    }

    private func shiftRow(_ session: CashSession) -> some View {
        let open = expanded == session.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { expanded = open ? nil : session.id }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(session.registerName) · \(CashDay.when(session.openedAt, zone: session.zone))").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Text(summary(session)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if session.isOpen {
                        // Open now is green; left open from an earlier day is the amber that asks for a close.
                        let tone = session.stale == true ? Theme.mango : ProviderState.done.color
                        HStack(spacing: 6) {
                            Circle().fill(tone).frame(width: 6, height: 6)
                            Text(L("Open@register"))
                        }
                        .font(Theme.text(12, weight: .heavy))
                        .foregroundStyle(Theme.inkStrong)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Theme.wash(tone, 24), in: Capsule())
                    } else {
                        CashDifferenceText(difference: session.difference ?? 0, currency: Workspace.shared.currency)
                    }
                    Glyph("chevron-down", size: 16).foregroundStyle(Theme.inkSoft).rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(open ? .isSelected : [])
            if open {
                VStack(alignment: .leading, spacing: 12) {
                    CashShiftDetail(session: session)
                    HStack {
                        Spacer(minLength: 0)
                        DocumentButton(title: L("Download PDF"), systemImage: "file-down", path: "/provider-store/register-sessions/\(session.id)/pdf", fileName: "\(session.registerName) \(session.openedDay ?? "")")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.wash(Theme.blue, 4))
                .overlay(alignment: .top) { RowDivider() }
            }
        }
    }

    private func summary(_ session: CashSession) -> String {
        if session.isOpen { return session.stale == true ? L("Still open since an earlier day") : L("Open now") }
        let sales = session.saleCount == 1 ? LF("1 sale · closed by %@", session.closedByName ?? "—") : LF("%d sales · closed by %@", session.saleCount, session.closedByName ?? "—")
        return "\(sales) · " + LF("Counted %@ of %@", cashMoney(session.countedCash ?? 0), cashMoney(session.expectedCash))
    }
}

private struct CashSessionPage: Decodable {
    let items: [CashSession]
    let total: Int
    let hasMore: Bool?
}
