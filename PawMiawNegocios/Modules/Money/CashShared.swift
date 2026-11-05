//
//  CashShared.swift
//  PawMiawNegocios
//
//  Pieces every money screen shares: payment methods and their words, the
//  reasons a risky move needs (docs/money-access-levels.md), the counter this
//  device works at, the payment step, PDFs, the client picker and small rows.
//

import SwiftUI
import QuickLook

// MARK: - Words

enum CashText {
    static let methods: [String] = ["cash", "card", "bank_transfer", "digital_wallet", "other"]

    static func method(_ method: String?) -> String {
        switch method {
        case "cash": L("Cash")
        case "card": L("Card")
        case "bank_transfer": L("Transfer")
        case "digital_wallet": L("Wallet")
        case "credit": L("Credit on account")
        case "other": L("Other@method")
        default: method ?? "—"
        }
    }

    static func methodHue(_ method: String?) -> Hue {
        switch method {
        case "cash": .mint
        case "card": .sky
        case "bank_transfer": .periwinkle
        case "digital_wallet": .lavender
        case "credit": .butter
        default: .grey
        }
    }

    /// Where money came from in Finance (`FinanceSource`, plus deposits on the day close).
    static func source(_ source: String?) -> String {
        switch source {
        case "store": L("Store")
        case "visit": L("Visits")
        case "stay": L("Stays")
        case "hospital": L("Hospital")
        case "deposit": L("Deposits")
        default: L("Other@source")
        }
    }

    static func sourceHue(_ source: String?) -> Hue {
        switch source {
        case "visit": .sky
        case "stay": .periwinkle
        case "hospital": .teal
        case "store": .peach
        case "deposit": .mint
        default: .grey
        }
    }

    static func aging(_ bucket: String) -> String {
        switch bucket {
        case "current": L("Not due yet")
        case "d1_30": L("1–30 days late")
        case "d31_60": L("31–60 days late")
        default: L("Over 60 days late")
        }
    }

    static let agingBuckets = ["current", "d1_30", "d31_60", "d61_plus"]

    static func daysLate(_ days: Int) -> String {
        LP(days, "%d day late", "%d days late")
    }
}

/// Days as the server names them ("yyyy-MM-dd", the business's calendar).
enum CashDay {
    static func date(_ key: String) -> Date? { DateText.parse(key) }

    static func shift(_ key: String, _ days: Int) -> String {
        guard let date = date(key), let moved = DateText.calendar.date(byAdding: .day, value: days, to: date) else { return key }
        return DateText.dayKey(moved)
    }

    static var today: String { DateText.dayKey() }

    /// The first day the front desk still reads (the last 7 days, today included).
    static func frontDeskFirst(_ today: String) -> String { shift(today, -(MoneyLevel.frontDeskDays - 1)) }

    /// "4 nov" / "mié 4 nov 2026".
    static func short(_ key: String?) -> String {
        guard let key, let date = date(key) else { return "—" }
        let f = DateFormatter(); f.locale = .app; f.timeZone = Workspace.shared.timeZone
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f.string(from: date)
    }

    static func long(_ key: String?) -> String {
        guard let key, let date = date(key) else { return "—" }
        let f = DateFormatter(); f.locale = .app; f.timeZone = Workspace.shared.timeZone
        f.setLocalizedDateFormatFromTemplate("EEEdMMMyyyy")
        return f.string(from: date)
    }

    static func range(_ from: String, _ to: String) -> String {
        from == to ? long(from) : "\(short(from)) – \(long(to))"
    }

    /// A moment on a clock: "mié 4 nov, 9:02 a.m." or only the time.
    static func when(_ iso: String?, withDay: Bool = true, zone: TimeZone? = nil) -> String {
        guard let date = DateText.parse(iso) else { return "—" }
        let f = DateFormatter(); f.locale = .app; f.timeZone = zone ?? Workspace.shared.timeZone
        f.setLocalizedDateFormatFromTemplate(withDay ? "EEEdMMMjmm" : "jmm")
        return f.string(from: date)
    }
}

func cashRequestId() -> String { UUID().uuidString.lowercased() }

/// "$1,234.50 MXN" in a document's own currency.
func cashMoney(_ cents: Int?, _ currency: String? = nil) -> String { Money.format(cents, currency: currency) }

/// "16%" from basis points.
func cashRate(_ bps: Int) -> String {
    let percent = Double(bps) / 100
    return percent.rounded() == percent ? "\(Int(percent))%" : String(format: "%.2f%%", percent)
}

func cashAsksReason(_ error: Error) -> Bool { (error as? APIError)?.code == "reason_required" }
func cashErrorCode(_ error: Error) -> String? { (error as? APIError)?.code }

// MARK: - Reasons (docs/money-access-levels.md)

/// Why a money move needs its reason: the shared "why" field's words.
enum CashReasonKind {
    case discount, courtesy, priceLowered, `return`, cancel, refund, cashDifference

    var label: String {
        switch self {
        case .discount: L("Why the discount")
        case .courtesy: L("Why it is free")
        case .priceLowered: L("Why the lower price")
        case .return: L("Why it comes back")
        case .cancel: L("Why it is canceled")
        case .refund: L("Why the money goes back")
        case .cashDifference: L("Why the drawer does not match")
        }
    }

    var placeholder: String {
        switch self {
        case .discount: L("e.g. Rescue, a loyal client")
        case .courtesy: L("e.g. Follow-up included, a staff pet")
        case .priceLowered: L("e.g. Price agreed with the owner")
        case .return: L("e.g. Wrong size, the pet did not like it")
        case .cancel: L("e.g. Charged twice, wrong product")
        case .refund: L("e.g. Charged twice, service not given")
        case .cashDifference: L("e.g. Change given wrong, a payment not recorded")
        }
    }

    var hint: String? {
        switch self {
        case .discount: L("It is 10% or more, so the owner sees why.")
        case .courtesy: L("Given for free on purpose: the owner sees why.")
        case .priceLowered: L("Below the catalog’s price: the owner sees why.")
        default: nil
        }
    }

    /// The sentence when the field is left empty (the server says the same).
    var required: String {
        switch self {
        case .discount: L("Write why this discount is given: it is 10% or more.")
        case .courtesy: L("Write why this line is given for free.")
        case .priceLowered: L("Write why the price is below the catalog’s.")
        case .return: L("Write why it is coming back.")
        case .cancel: L("Write why the sale is canceled.")
        case .refund: L("Write why the money goes back.")
        case .cashDifference: L("Write why the drawer does not match.")
        }
    }
}

/// A discount of 10% or more of what it is taken from needs a reason.
func cashDiscountNeedsReason(_ discount: Int, of before: Int) -> Bool {
    guard discount > 0, before > 0 else { return false }
    return discount * 100 >= before * 10
}

/// The one "why" field of every money move (web `ReasonField`): one line, the label with
/// its red mark (a required reason, as the web's default), the kind's hint under it.
struct CashReasonField: View {
    let kind: CashReasonKind
    @Binding var text: String
    var key: String = "reason"
    var form: FormState? = nil
    var hint: String? = nil
    var required: Bool = true

    var body: some View {
        PMTextField(kind.label, text: $text, key: key, form: form, prompt: kind.placeholder, hint: hint ?? kind.hint, required: required)
    }
}

// MARK: - Small rows

/// A label and an amount on one line (totals, summaries).
struct CashTotalLine: View {
    let label: String
    let value: String
    var strong: Bool = false
    var tone: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(strong ? Theme.text(15, weight: .bold) : Theme.smallFont).foregroundStyle(strong ? Theme.inkStrong : Theme.inkSoft)
            Spacer(minLength: 8)
            Text(value).font(strong ? Theme.text(17, weight: .heavy) : Theme.text(15, weight: .semibold)).foregroundStyle(tone ?? Theme.inkStrong).monospacedDigit()
        }
    }
}

/// An uppercase caption over a group.
struct CashCaption: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.brandText(12, weight: .bold)).tracking(1.44).foregroundStyle(Theme.inkSoft)
    }
}

/// A difference of a count: "Exact", "Short $X", "Over $X".
struct CashDifferenceText: View {
    let difference: Int
    let currency: String?

    var body: some View {
        // Web `DifferenceLabel`: exact in blue, short in red, over in mango.
        if difference == 0 {
            Text(L("Exact")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
        } else if difference < 0 {
            Text(LF("Short %@", cashMoney(-difference, currency))).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.destructive)
        } else {
            Text(LF("Over %@", cashMoney(difference, currency))).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.mango)
        }
    }
}

// MARK: - The counter this device works at

/// The register this device works at (chosen in the Store, remembered on the
/// device) and its open shift. Every place that takes money sends this shift;
/// cash with no shift is refused by the server.
@MainActor
final class CashDeviceRegister: ObservableObject {
    @Published private(set) var registers: [CashRegister] = []
    @Published private(set) var session: CashSession?
    @Published private(set) var loaded = false
    @Published private(set) var registerId: String? = UserDefaults.standard.string(forKey: CashDeviceRegister.key)

    private static let key = "pawmiaw.store.register"
    static let changed = Notification.Name("pawmiaw.cash.register-changed")

    var register: CashRegister? { registers.first(where: { $0.id == registerId }) ?? registers.first }
    var sessionId: String? { register?.openSessionId }
    /// The open shift was opened on an earlier day: it is counted and closed before today's cash.
    var stale: Bool { register?.openSession?.stale ?? session?.stale ?? false }

    func choose(_ id: String) {
        registerId = id
        UserDefaults.standard.set(id, forKey: Self.key)
        NotificationCenter.default.post(name: Self.changed, object: nil)
        Task { await loadSession() }
    }

    func load() async {
        let location = Workspace.shared.locationId
        do {
            let listed: [CashRegister] = try await API.get("/provider-store/registers", query: ["locationId": location])
            registers = location.map { place in listed.filter { ($0.locationId ?? place) == place } } ?? listed
        } catch {
            registers = []
        }
        registerId = UserDefaults.standard.string(forKey: Self.key)
        await loadSession()
        loaded = true
    }

    func loadSession() async {
        guard let id = sessionId else { session = nil; return }
        session = try? await API.get("/provider-store/register-sessions/\(id)")
    }
}

/// Keeps a device register fresh: on appear, on scope changes, and when another screen changes it.
struct CashKeepsRegister: ViewModifier {
    let device: CashDeviceRegister

    func body(content: Content) -> some View {
        content
            .reloadsOnScope { await device.load() }
            .onReceive(NotificationCenter.default.publisher(for: CashDeviceRegister.changed)) { _ in
                Task { await device.load() }
            }
    }
}

/// Who may open (and close) a shift: whoever sells or takes payments, or runs the register.
@MainActor func cashCanRunShift(_ w: Workspace) -> Bool {
    w.canAny(.salesSell, .billingRecordPayment, .registerManage)
}

/// What stands between a person and taking (or giving back) cash: a shift
/// from an earlier day still open, or no shift open at this counter. It opens
/// the shift in place; the close of an old shift is in the Store's register.
struct CashRegisterGate: View {
    @ObservedObject var device: CashDeviceRegister
    let wantsCash: Bool
    var giving: Bool = false
    @EnvironmentObject private var workspace: Workspace
    @State private var openingCash: Int?
    @State private var opening = false
    @State private var closing = false
    @State private var seed = 0

    var body: some View {
        if let register = device.register {
            if device.stale, let session = device.session {
                NoticeCard(
                    tone: .warning,
                    title: LF("%@ from %@ is still open — count it and close it.", register.name, CashDay.when(session.openedAt, zone: session.zone)),
                    message: LF("Opened by %@. Today’s cash belongs in today’s shift.", session.openedByName ?? "—"),
                    actionTitle: cashCanRunShift(workspace) ? L("Count and close") : nil,
                    action: cashCanRunShift(workspace) ? { closing = true } : nil
                )
                .sheet(isPresented: $closing) {
                    CashCloseShiftSheet(session: session) { Task { await device.load() } }
                }
            } else if wantsCash && device.sessionId == nil {
                if cashCanRunShift(workspace) {
                    // Web `OpenShiftForm compact`: a mango 16% box, the sentence 12 bold, the amount and Open side by side.
                    VStack(alignment: .leading, spacing: 12) {
                        Text(giving ? LF("%@ is closed. Open it to give cash back:", register.name) : LF("%@ is closed. Open it to take cash:", register.name))
                            .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        HStack(alignment: .bottom, spacing: 8) {
                            MoneyField(label: L("Starting cash"), cents: $openingCash)
                                .id(seed)
                            PMButton(L("Open@verb"), systemImage: "lock-open", size: .compact, isWorking: opening) { open(register) }
                                .padding(.bottom, 4)
                        }
                    }
                    .padding(12)
                    .background(Theme.wash(Theme.mango, 16), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .onAppear { openingCash = register.lastCashLeft ?? register.defaultOpeningCash; seed += 1 }
                } else {
                    NoticeCard(tone: .info, title: giving
                        ? L("Cash back comes out of an open register, and it’s closed. Someone who sells or takes payments can open it — card and transfer work now.")
                        : L("Cash goes into an open register, and it’s closed. Someone who sells or takes payments can open it — card and transfer work now."))
                }
            }
        }
    }

    private func open(_ register: CashRegister) {
        opening = true
        Task {
            defer { opening = false }
            do {
                let _: EmptyResponse = try await API.post("/provider-store/registers/\(register.id)/open", body: ["openingCash": openingCash ?? 0, "note": nil])
                Toast.show(LF("%@ is open.", register.name))
                await device.load()
                NotificationCenter.default.post(name: CashDeviceRegister.changed, object: nil)
            } catch {
                Toast.error(error, fallback: L("Could not open the register."))
            }
        }
    }
}

// MARK: - The payment step

/// The tenders being typed (cash, card, transfer, wallet, credit on account),
/// split across methods, the change to hand back and what stays owed. One way
/// to take money: the counter and a bill both use it. The server counts.
@MainActor
final class CashTenders: ObservableObject {
    struct Tender: Identifiable {
        let id = UUID()
        var method: String
        var amount: Int?
        var tendered: Int?
        var reference: String = ""
        /// Bumped when a quick-cash chip fills "Handed over", so its field shows the new figure.
        var revision = 0
    }

    @Published var tenders: [Tender] = []
    private(set) var requestId = cashRequestId()
    var total = 0
    var credit = 0
    var allowBalance = false
    var currency: String?

    func start(total: Int, credit: Int, registerOpen: Bool, allowBalance: Bool, currency: String?) {
        self.total = total
        self.credit = credit
        self.allowBalance = allowBalance
        self.currency = currency
        requestId = cashRequestId()
        let fallback = registerOpen ? "cash" : "card"
        let fromCredit = min(credit, total)
        if fromCredit > 0 {
            tenders = [Tender(method: "credit", amount: fromCredit)]
            if total > fromCredit { tenders.append(Tender(method: fallback, amount: total - fromCredit)) }
        } else {
            tenders = [Tender(method: fallback, amount: total)]
        }
    }

    var methods: [String] { CashText.methods + (credit > 0 ? ["credit"] : []) }
    var paid: Int { tenders.reduce(0) { $0 + ($1.amount ?? 0) } }
    var remaining: Int { total - paid }
    var change: Int {
        tenders.reduce(0) { sum, tender in
            guard tender.method == "cash", let handed = tender.tendered, let amount = tender.amount, handed > amount else { return sum }
            return sum + handed - amount
        }
    }
    var wantsCash: Bool { tenders.contains { $0.method == "cash" && ($0.amount ?? 0) > 0 } }
    private var creditUsed: Int { tenders.filter { $0.method == "credit" }.reduce(0) { $0 + ($1.amount ?? 0) } }

    func problem(registerOpen: Bool) -> String? {
        let shortCash = tenders.contains { $0.method == "cash" && $0.tendered != nil && ($0.tendered ?? 0) < ($0.amount ?? 0) }
        if creditUsed > credit { return LF("They have %@ of credit", cashMoney(credit, currency)) }
        if remaining < 0 { return L("The payments add up to more than the sale") }
        if remaining > 0 && !allowBalance { return L("Collect the full amount — or choose a client to leave a balance") }
        if shortCash { return L("They handed over less than the cash amount") }
        if wantsCash && !registerOpen { return L("Open the register to take cash") }
        return nil
    }

    func add() {
        let method = tenders.contains { $0.method == "card" } ? "cash" : "card"
        tenders.append(Tender(method: method, amount: max(0, remaining)))
    }

    func remove(_ id: UUID) { tenders.removeAll { $0.id == id } }

    /// What the server takes: `[{ method, amount, tendered, reference }]`.
    func payments() -> [[String: Any?]] {
        tenders.compactMap { tender in
            guard let amount = tender.amount, amount > 0 else { return nil }
            return [
                "method": tender.method,
                "amount": amount,
                "tendered": tender.method == "cash" ? tender.tendered : nil,
                "reference": tender.method == "credit" ? nil : tender.reference.nonEmpty,
            ]
        }
    }

    /// Notes a customer is likely to hand over for this amount: exact, then round figures.
    static func quickCash(_ amount: Int) -> [Int] {
        guard amount > 0 else { return [] }
        var options: [Int] = [amount]
        for step in [5000, 10_000, 20_000, 50_000, 100_000] {
            let rounded = Int((Double(amount) / Double(step)).rounded(.up)) * step
            if rounded > amount && !options.contains(rounded) { options.append(rounded) }
            if options.count >= 4 { break }
        }
        return options.sorted()
    }
}

/// The tenders, one box each, "add another payment" and the summary with the change
/// (web `PaymentTenders`, payment-step.tsx): method pills 44 tall, the amount and what
/// was handed over side by side, quick-cash pills, then the "Summary" part.
struct CashTendersView: View {
    @ObservedObject var state: CashTenders
    let registerOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach($state.tenders) { $tender in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 8) {
                        FlowLayout(spacing: 8) {
                            ForEach(state.methods, id: \.self) { method in
                                CashMethodPill(title: CashText.method(method), isOn: tender.method == method) { tender.method = method }
                            }
                        }
                        if state.tenders.count > 1 {
                            Button { state.remove(tender.id) } label: {
                                Glyph("x", size: 16).foregroundStyle(Theme.inkSoft).frame(width: 44, height: 44).contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L("Remove payment"))
                        }
                    }
                    MoneyField(label: L("Amount"), cents: $tender.amount, caps: true)
                        .id("\(tender.id)-\(tender.method)-amount")
                    if tender.method == "credit" {
                        Text(LF("From their deposits: %@ available.", cashMoney(state.credit, state.currency))).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    } else if tender.method == "cash" {
                        MoneyField(label: L("Handed over"), cents: $tender.tendered, caps: true)
                            .id("\(tender.id)-tendered-\(tender.revision)")
                        let quick = CashTenders.quickCash(tender.amount ?? 0)
                        if !quick.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(quick, id: \.self) { value in
                                    Button { tender.tendered = value; tender.revision += 1 } label: {
                                        Text(cashMoney(value, state.currency))
                                            .font(Theme.text(14, weight: .bold)).monospacedDigit()
                                            .foregroundStyle(Theme.inkStrong)
                                            .padding(.horizontal, 16)
                                            .frame(minHeight: 44)
                                            .background(tender.tendered == value ? AnyShapeStyle(Theme.wash(Theme.aqua, 30)) : AnyShapeStyle(Theme.surfaceMuted), in: Capsule())
                                            .contentShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        PMTextField(L("Terminal reference"), text: $tender.reference, prompt: L("Optional"), caps: true)
                    }
                }
                .padding(16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 2))
            }
            if state.remaining > 0 {
                PMButton(LF("Add another payment (%@ left)", cashMoney(state.remaining, state.currency)), systemImage: "plus", variant: .outline, fullWidth: true) { state.add() }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Summary")).font(.brandHeading(16.8, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                VStack(spacing: 4) {
                    summaryLine(L("Total"), cashMoney(state.total, state.currency), bold: true)
                    summaryLine(L("Paid now"), cashMoney(state.paid, state.currency), bold: true)
                    if state.remaining > 0 { summaryLine(L("Left on the account"), cashMoney(state.remaining, state.currency)).foregroundStyle(Theme.inkSoft) }
                    if state.change > 0 {
                        HStack {
                            Text(L("Change"))
                            Spacer(minLength: 12)
                            Text(cashMoney(state.change, state.currency)).monospacedDigit()
                        }
                        .font(.brandHeading(24, relativeTo: .title2))
                        .foregroundStyle(Theme.blue)
                        .padding(.top, 8)
                    }
                }
                .padding(16)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                if let problem = state.problem(registerOpen: registerOpen) {
                    Text(problem).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.destructive)
                }
            }
        }
    }

    private func summaryLine(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 12)
            Text(value).fontWeight(bold ? .bold : .regular).monospacedDigit()
        }
        .font(Theme.text(14))
        .foregroundStyle(Theme.inkStrong)
    }
}

/// A payment method to choose (web: the payment step's method buttons): 44
/// tall for a counter, a 2 pt edge; chosen = PAW Blue filled.
struct CashMethodPill: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.text(14, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(isOn ? Theme.onBlue : Theme.inkSoft)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(isOn ? AnyShapeStyle(Theme.blue) : AnyShapeStyle(Color.clear), in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? Theme.blue : Theme.borderSoft, lineWidth: 2))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - PDFs

// MARK: - Who is it for

/// The pet's prescription a prescription-only product is sold against.
struct CashPrescriptionPicker: View {
    let petId: String?
    let catalogItemId: String
    @Binding var selection: String?
    var quantity: Int = 1
    /// A cart line (nothing handed out yet) picks the only exact match by itself and drops a
    /// choice that no longer fits; a bill line never does: this very bill may have used it up.
    var autoPick: Bool = true
    @State private var items: [CashDispensable] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if petId == nil {
                warning(L("Needs a prescription — choose the client and the pet."))
            } else if loaded && items.isEmpty && selection == nil {
                warning(L("No valid prescription for this pet — a vet prescribes it first."))
            } else {
                Menu {
                    Button(L("Choose the prescription")) { selection = nil }
                    ForEach(items) { item in
                        Button([item.folio, item.medicineName, item.remaining.map { LF("%d left", $0) }, item.prescriberName].compactMap { $0?.nonEmpty }.joined(separator: " · ")) {
                            selection = item.prescriptionItemId
                        }
                    }
                } label: {
                    // Web: a small NativeSelect (40, radius 16, grey edge, chevron at the right).
                    HStack {
                        Text(chosenTitle).font(Theme.text(14)).foregroundStyle(selection == nil ? Theme.inkSoft : Theme.inkStrong).lineLimit(1)
                        Spacer()
                        Glyph("chevron-down", size: 16).foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(Theme.inputFill, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
                if let chosen = items.first(where: { $0.prescriptionItemId == selection }) {
                    // A pack sold against a line written for what it holds counts its size.
                    let perSale = max(1, chosen.unitsPerSale ?? 1)
                    if let left = chosen.remaining, quantity * perSale > left {
                        Text(perSale > 1 ? LF("Only %d left on this prescription, and each one sold counts %d.", left, perSale) : LF("Only %d left on this prescription.", left))
                            .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.destructive)
                    } else if perSale > 1, let left = chosen.remaining {
                        Text(LF("Each one sold counts %d of the %d left.", perSale, left)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    } else if let valid = chosen.validUntil {
                        Text(LF("Valid until %@", CashDay.long(String(valid.prefix(10))))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        }
        .task(id: petId) { await load() }
    }

    private func warning(_ text: String) -> some View {
        HStack(spacing: 6) {
            Glyph("file-exclamation-point", size: 14)
            Text(text)
        }
        .font(Theme.text(12, weight: .semibold))
        .foregroundStyle(Theme.destructive)
    }

    private var chosenTitle: String {
        if !loaded { return L("Loading prescriptions…") }
        guard let selection else { return L("Choose the prescription") }
        guard let item = items.first(where: { $0.prescriptionItemId == selection }) else { return L("The prescription it was dispensed against") }
        return [item.folio, item.medicineName].compactMap { $0?.nonEmpty }.joined(separator: " · ")
    }

    private func load() async {
        guard let petId else { items = []; loaded = true; return }
        let list: CashDispensableList? = try? await API.get("/provider-prescriptions/dispensable", query: ["providerClientPetId": petId, "catalogItemId": catalogItemId])
        items = list?.items ?? []
        loaded = true
        guard autoPick else { return }
        let exact = items.filter { $0.exactProduct == true }
        if selection == nil, exact.count == 1 { selection = exact[0].prescriptionItemId }
        // A choice that no longer fits (another pet, used up) is dropped.
        if let chosen = selection, list != nil, !items.contains(where: { $0.prescriptionItemId == chosen }) { selection = nil }
    }
}

/// The email a receipt goes to: the client's, or one typed here.
struct CashReceiptEmailField: View {
    let clientEmail: String?
    let automatic: Bool
    @Binding var email: String
    @Binding var send: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToggleRow(title: L("Email the receipt"), subtitle: clientEmail?.nonEmpty.map { LF("To %@", $0) } ?? L("Type an email to send it once."), isOn: $send)
            if send && clientEmail?.nonEmpty == nil {
                PMTextField(L("Email for the receipt"), text: $email, prompt: L("name@example.com"), keyboard: .emailAddress)
            }
        }
        .onAppear { send = automatic && clientEmail?.nonEmpty != nil }
    }

    /// `receiptEmail` / `saveReceiptEmail` as the server takes them.
    static func delivery(clientEmail: String?, typed: String, send: Bool, canSave: Bool) -> [String: Any?] {
        guard send else { return ["receiptEmail": nil] }
        if let own = clientEmail?.nonEmpty { return ["receiptEmail": own] }
        guard let typed = typed.nonEmpty else { return ["receiptEmail": nil] }
        return ["receiptEmail": typed, "saveReceiptEmail": canSave]
    }
}
