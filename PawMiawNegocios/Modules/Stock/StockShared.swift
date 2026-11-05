//
//  StockShared.swift
//  PawMiawNegocios
//
//  What Inventory and the Pharmacy share: requests that keep the server's
//  whole refusal (a 409 `stock_changed` says what the shelf holds now; a
//  `credential_required` says which prescription waits), Inventory's rules
//  (web lib/inventory.ts) and the small pieces every stock screen draws (web
//  inventory-bits.tsx).
//

import SwiftUI
import UIKit

// MARK: - Requests

/// A refused request with the server's whole body, beside the usual `APIError`.
struct StockRefusal: LocalizedError {
    let api: APIError
    let body: [String: JSONValue]
    var errorDescription: String? { api.message }
    var code: String? { api.code }
    var status: Int { api.status }
}

/// The sentence for a failed action, whichever way it failed.
func stockErrorText(_ error: Error, fallback: String = L("Something went wrong. Try again.")) -> String {
    if let refusal = error as? StockRefusal { return errorText(refusal.api, fallback: fallback) }
    return errorText(error, fallback: fallback)
}

/// The request never reached the server (offline, timed out): nothing says whether it was kept.
func stockIsConnectionError(_ error: Error) -> Bool {
    if let refusal = error as? StockRefusal { return refusal.api.isOffline }
    if let api = error as? APIError { return api.isOffline }
    return !(error is CancellationError)
}

enum StockAPI {
    /// A request whose refusal keeps the server's body (`StockRefusal`): `API` with the refusal's
    /// `APIError.body` read into the stock screens' shape. Offline stays an `APIError`.
    static func send<T: Decodable>(_ method: String, _ path: String, body: [String: Any?]? = nil, query: [String: String?] = [:]) async throws -> T {
        let data: Data
        do {
            data = try await API.data(method, path, query: query, body: try body.map(API.jsonBody))
        } catch let error as APIError where !error.isOffline {
            throw StockRefusal(api: error, body: error.body?.object ?? [:])
        }
        return try API.decode(data)
    }

    /// One id per press of Save: sent again (a retry), the server never writes twice.
    static func newRequestId() -> String { UUID().uuidString.lowercased() }
}

// MARK: - Inventory rules (web lib/inventory.ts)

enum StockState { case untracked, count, out, expired, low, inStock }
enum StockExpiry { case none, expired, soon, ok }
enum StockFilter: String, CaseIterable { case all, low, out, expiring, expired }
enum StockQuantityProblem { case required, whole, negative, zero, invalid, tooLarge }

enum StockRules {
    /// A lot with this many days left, or fewer, is "expiring soon".
    static let expiringDays = 60
    /// The most one delivery, count or write-off can hold (the server's limit).
    static let maxQuantity = 1_000_000
    /// The highest cost per unit, in cents.
    static let maxCostCents = 1_000_000_000
    static let noteMax = 300
    static let lotCodeMax = 80
    /// The count a product is low at when none was set for it (the server's default).
    static let defaultLowPoint = 3

    /// The business's day (its clock, as the server judges a lot expired).
    static var today: String { DateText.dayKey() }

    static func addDays(_ day: String, _ days: Int) -> String {
        let formatter = DateText.dayFormatter(TimeZone(identifier: "UTC")!)
        guard let date = formatter.date(from: String(day.prefix(10))) else { return day }
        return formatter.string(from: date.addingTimeInterval(TimeInterval(days) * 86_400))
    }

    static func daysBetween(_ from: String, _ to: String) -> Int {
        let formatter = DateText.dayFormatter(TimeZone(identifier: "UTC")!)
        guard let a = formatter.date(from: String(from.prefix(10))), let b = formatter.date(from: String(to.prefix(10))) else { return 0 }
        return Int((b.timeIntervalSince(a) / 86_400).rounded())
    }

    /// A lot expires at the end of its day: one dated today is still good today.
    static func expiry(_ expiresOn: String?, today: String) -> StockExpiry {
        guard let raw = expiresOn?.nonEmpty else { return .none }
        let day = String(raw.prefix(10))
        if day < today { return .expired }
        return day <= addDays(today, expiringDays) ? .soon : .ok
    }

    static func expiredUnits(_ lots: [StockLot], today: String) -> Int {
        lots.reduce(0) { $0 + ($1.quantityOnHand > 0 && expiry($1.expiresOn, today: today) == .expired ? $1.quantityOnHand : 0) }
    }

    static func hasExpiringLot(_ lots: [StockLot], today: String) -> Bool {
        lots.contains { $0.quantityOnHand > 0 && expiry($0.expiresOn, today: today) == .soon }
    }

    /// What can still be sold: the server's `sellableUnits`, or worked out from the lots.
    static func sellable(_ row: StockRow, today: String) -> Int {
        row.sellableUnits ?? (row.quantityOnHand - expiredUnits(row.lots, today: today))
    }

    /// "Agotado": nothing left to sell.
    static func isOut(_ row: StockRow, today: String) -> Bool {
        row.outOfStock ?? (sellable(row, today: today) <= 0)
    }

    /// "Poco inventario": the server's `lowStock` while its alert is on, never while out.
    static func isLow(_ row: StockRow, today: String) -> Bool {
        row.lowStock && row.lowStockAlert != false && !isOut(row, today: today)
    }

    static func state(_ row: StockRow, today: String) -> StockState {
        if row.tracked == false { return .untracked }
        if row.quantityOnHand < 0 { return .count }
        if row.quantityOnHand == 0 { return .out }
        if isOut(row, today: today) { return .expired }
        if isLow(row, today: today) { return .low }
        return .inStock
    }

    static func matches(_ row: StockRow, _ filter: StockFilter, today: String) -> Bool {
        switch filter {
        case .all: true
        case .out: isOut(row, today: today)
        case .low: isLow(row, today: today)
        case .expiring: hasExpiringLot(row.lots, today: today)
        case .expired: expiredUnits(row.lots, today: today) > 0
        }
    }

    /// A medicine: its kind says so, or it needs a prescription, or it is controlled.
    static func isMedicine(_ row: StockRow) -> Bool {
        row.productKind == "medication" || row.requiresPrescription == true || (row.controlSchedule?.nonEmpty != nil)
    }

    static func requiresLotAndExpiry(_ row: StockRow) -> Bool { row.controlSchedule?.nonEmpty != nil }

    /// A quantity typed by a person, in whole units.
    static func parseQuantity(_ text: String, allowZero: Bool = false, max: Int = maxQuantity) -> (value: Int?, problem: StockQuantityProblem?) {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        if cleaned.isEmpty { return (nil, .required) }
        if cleaned.hasPrefix("-"), cleaned.dropFirst().first?.isNumber == true { return (nil, .negative) }
        if cleaned.range(of: #"^\d+[.,]\d+$"#, options: .regularExpression) != nil { return (nil, .whole) }
        guard cleaned.range(of: #"^\d+$"#, options: .regularExpression) != nil else { return (nil, .invalid) }
        guard let value = Int(cleaned), value <= max else { return (nil, .tooLarge) }
        if value == 0 && !allowZero { return (nil, .zero) }
        return (value, nil)
    }

    /// A count far from what the system has needs a word about why.
    static func isLargeCountDifference(current: Int, counted: Int) -> Bool {
        let difference = abs(counted - current)
        if difference >= 10 { return true }
        return difference >= 3 && Double(difference) >= Double(abs(current)) * 0.2
    }

    static func averageCostAfter(onHand: Int, currentCost: Int, received: Int, receivedCost: Int) -> Int {
        let existing = Swift.max(0, onHand)
        if received <= 0 { return currentCost }
        if existing == 0 { return receivedCost }
        return Int((Double(existing * currentCost + received * receivedCost) / Double(existing + received)).rounded())
    }

    static func lotsWithCode(_ lots: [StockLot], _ code: String) -> [StockLot] {
        let wanted = code.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return [] }
        return lots.filter { $0.quantityOnHand > 0 && ($0.lotCode ?? "").trimmingCharacters(in: .whitespaces).lowercased() == wanted }
    }
}

// MARK: - Words

enum StockText {
    static func count(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .app
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// "1 unit" / "24 units".
    static func units(_ value: Int) -> String {
        abs(value) == 1 ? L("1 unit") : LF("%@ units", count(value))
    }

    /// A shelf below zero is never shown as stock: "Faltan 2 — necesita un conteo".
    static func short(_ onHand: Int, withCount: Bool = true) -> String {
        let n = count(abs(onHand))
        if !withCount { return abs(onHand) == 1 ? L("1 short") : LF("%@ short", n) }
        return abs(onHand) == 1 ? L("1 short — it needs a count") : LF("%@ short — it needs a count", n)
    }

    static func onHand(_ value: Int) -> String { value < 0 ? short(value, withCount: false) : count(value) }

    /// "4 nov 2026" for a "yyyy-MM-dd" day, the same day wherever the reader is.
    static func day(_ value: String?) -> String {
        guard let raw = value?.nonEmpty else { return "—" }
        if raw.count == 10 {
            let parse = DateText.dayFormatter(TimeZone(identifier: "UTC")!)
            guard let date = parse.date(from: raw) else { return raw }
            return DateText.date(date, zone: TimeZone(identifier: "UTC")!)
        }
        return DateText.date(DateText.parse(raw))
    }

    /// "4 nov 2026, 10:30 a.m."
    static func dateTime(_ value: String?) -> String {
        guard let date = DateText.parse(value) else { return "—" }
        return "\(DateText.date(date)), \(DateText.time(date))"
    }

    static func kind(_ kind: String?) -> String? {
        switch kind {
        case "medication": L("Medication")
        case "food": L("Food")
        case "supply": L("Supply")
        case "accessory": L("Accessory")
        case "other": L("Other")
        default: nil
        }
    }

    /// Kind · SKU · barcode.
    static func detail(_ row: StockRow) -> String {
        [kind(row.productKind), row.sku, row.barcode].compactMap { $0?.nonEmpty }.joined(separator: " · ")
    }

    static func money(_ cents: Int?) -> String { Money.format(cents) }

    static func signed(_ value: Int) -> String { value > 0 ? "+\(count(value))" : "−\(count(-value))" }
}


// MARK: - Pieces (web inventory-bits.tsx, pharmacy-bits.tsx, catalog-bits.tsx)
//
// Every control is the kit's (ToneChip, Chip, NoticeCard, ListCard, FormField with
// `caps`, PMButton `.ghost` / `.link`); what is here maps Stock's data onto them.

extension StockState {
    var providerState: ProviderState {
        switch self {
        case .inStock: .done
        case .low: .waiting
        case .out, .count, .expired: .problem
        case .untracked: .closed
        }
    }

    /// The pill's colour: the status colours, expired a maroon deeper than "out".
    var tone: Color { self == .expired ? ChipTone.expired.color : providerState.color }

    var label: String {
        switch self {
        case .inStock: L("In stock")
        case .low: L("Low stock")
        case .out: L("Out of stock")
        case .expired: L("All expired")
        case .count: L("Count needed")
        case .untracked: L("Not counted yet")
        }
    }
}

extension StockExpiry {
    var providerState: ProviderState {
        switch self {
        case .expired: .problem
        case .soon: .waiting
        case .ok, .none: .closed
        }
    }
}

/// A product's stock state as the kit's pill (web `StockStatePill`: `TonePill`, the tone at 22%, its dot).
func stockStateChip(_ row: StockRow, today: String = StockRules.today) -> Chip {
    let state = StockRules.state(row, today: today)
    return Chip(state.label, color: state.tone, percent: 22, dot: true)
}

/// A lot: its number, what is left and when it expires — red once expired, amber when close.
func stockLotChip(code: String?, quantity: Int, expiresOn: String?, today: String = StockRules.today) -> Chip {
    let state = StockRules.expiry(expiresOn, today: today)
    var text = "\(code?.nonEmpty ?? L("No lot")) · \(StockText.count(quantity))"
    if let expiresOn = expiresOn?.nonEmpty {
        text += " · \(state == .expired ? L("expired") : L("exp.")) \(StockText.day(expiresOn))"
    }
    return Chip(text, color: state.providerState.color, percent: 22, dot: true)
}

/// The product's photo, or its kind's icon on the Catalog's product colour (peach).
struct StockProductThumb: View {
    let photoUrl: String?
    let productKind: String?
    var size: CGFloat = 48

    private var icon: String {
        switch productKind {
        case "medication": "pill"
        case "food": "paw-print"
        case "supply": "boxes"
        case "accessory": "shopping-bag"
        case "other": "sparkles"
        default: "package"
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).fill(Theme.wash(Hue.peach.color, 24))
            Glyph(icon, size: 20).foregroundStyle(Theme.mix(Theme.mango, 70, with: Theme.inkStrong))
            if let url = APIConfig.assetURL(photoUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
    }
}

/// The product a sheet is about (web `ProductStockCard`): photo, name, its state, what is on the
/// shelf — and what will be once saved.
struct StockProductCard: View {
    let row: StockRow
    var after: Int? = nil
    var afterLabel: String? = nil
    var today: String = StockRules.today

    var body: some View {
        let changes = after != nil && after != row.quantityOnHand
        let detail = StockText.detail(row)
        HStack(alignment: .center, spacing: 12) {
            StockProductThumb(photoUrl: row.photoUrl, productKind: row.productKind, size: 56)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.name).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(2)
                if !detail.isEmpty { Text(detail).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                FlowLayout(spacing: 8) {
                    stockStateChip(row, today: today)
                    if row.reorderPoint > 0 && row.lowStockAlert != false {
                        Text(LF("Reorder at %@", StockText.count(row.reorderPoint))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Text(StockText.onHand(row.quantityOnHand))
                        .font(.brandHeading(changes || row.quantityOnHand < 0 ? 18 : 24))
                        .foregroundStyle(changes || row.quantityOnHand < 0 ? Theme.inkSoft : Theme.inkStrong)
                    if changes, let after {
                        Glyph("arrow-right", size: 16).foregroundStyle(Theme.inkSoft)
                        Text(StockText.onHand(after)).font(.brandHeading(24)).foregroundStyle(Theme.inkStrong)
                    }
                }
                .monospacedDigit()
                Text(changes ? (afterLabel ?? L("on hand after")) : row.quantityOnHand < 0 ? L("it needs a count") : L("on hand"))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 2))
    }
}

/// A small line of facts under a row ("Reorder at 3 · 2 expired").
struct StockMetaLine: View {
    let parts: [String?]
    var body: some View {
        let text = parts.compactMap { $0?.nonEmpty }.joined(separator: " · ")
        if !text.isEmpty {
            Text(text).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A day typed in those modals (web `DatePickerField`, 48 tall, the calendar at the right): empty
/// until chosen. The kit's DayField carries the sentence-case label; this one sits in a `FormField(caps: true)`.
struct StockDayControl: View {
    @Binding var day: String
    var invalid: Bool = false
    var placeholder: String = L("Choose the date")
    var onChange: () -> Void = {}

    private static let utc = TimeZone(identifier: "UTC")!

    var body: some View {
        HStack(spacing: 12) {
            if day.isEmpty {
                Button {
                    day = StockRules.today
                    onChange()
                } label: {
                    HStack {
                        Text(placeholder).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                DatePicker("", selection: Binding(get: { DateText.dayFormatter(Self.utc).date(from: day) ?? Date() }, set: {
                    day = DateText.dayFormatter(Self.utc).string(from: $0)
                    onChange()
                }), displayedComponents: .date)
                    .labelsHidden()
                    .tint(Theme.blue)
                    .environment(\.timeZone, Self.utc)
                    .environment(\.locale, .app)
                Spacer(minLength: 0)
            }
            Glyph("calendar-days", size: 16).foregroundStyle(Theme.inkSoft)
        }
        .fieldChrome(invalid: invalid)
    }
}

/// One line of a review box: what, then its value at the right (web `ReviewRow`).
struct StockReviewRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: () -> Value
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label).foregroundStyle(Theme.inkSoft)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) { value() }
                .foregroundStyle(Theme.inkStrong)
                .multilineTextAlignment(.trailing)
        }
        .font(Theme.text(14))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// How many rows a list shows at first, and adds as it is scrolled.
let stockPageSize = 20
