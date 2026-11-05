//
//  StockAdjustSheets.swift
//  PawMiawNegocios
//
//  Inventory's other sheets (web inventory/adjust-stock-sheet.tsx,
//  stock-detail-sheet.tsx, stock-settings-sheet.tsx):
//  - a count ("this is what is really on the shelf") or a write-off ("this
//    left the shelf, and why"), for the whole product or one of its lots. The
//    figure the sheet showed goes with it: when someone sold or counted in the
//    meantime the server answers 409 `stock_changed`, the sheet shows the new
//    figure and the person records again. One request id per press.
//  - one product's lots and every movement of its stock;
//  - its stock settings: the low-stock alert and point, the usual order,
//    where it is kept, its barcode, and whether it keeps selling at zero.
//

import SwiftUI

// MARK: - Count and write off

enum StockAdjustKind { case count, waste }

private enum WasteReason: String, CaseIterable, Hashable {
    case expired, damaged, lost, used, other

    var label: String {
        switch self {
        case .expired: L("Expired@lot")
        case .damaged: L("Damaged")
        case .lost: L("Lost or missing")
        case .used: L("Used in the clinic")
        case .other: L("Other")
        }
    }
}

private let wholeProduct = "whole"

struct StockAdjustSheet: View {
    let row: StockRow
    let kind: StockAdjustKind
    let lotId: String?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var chosenLot = wholeProduct
    @State private var quantity = ""
    @State private var reason: WasteReason?
    @State private var note = ""
    @State private var witness = ""
    @State private var saving = false
    @State private var saveError: (message: String, connection: Bool)?
    /// What the server said the shelf (and the chosen lot) holds now, after a `stock_changed`.
    @State private var fresh: (whole: Int?, lotId: String?, lot: Int?)?
    @State private var lastPress: (key: String, id: String)?
    @State private var started = false

    private var today: String { StockRules.today }
    private var shown: StockRow {
        var copy = row
        if let whole = fresh?.whole { copy.quantityOnHand = whole }
        return copy
    }
    private var lots: [StockLot] { shown.lots.filter { $0.quantityOnHand != 0 } }
    private var lot: StockLot? { lots.first { $0.id == chosenLot } }
    private var current: Int {
        if let lot {
            if let fresh, fresh.lotId == lot.id, let value = fresh.lot { return value }
            return lot.quantityOnHand
        }
        return shown.quantityOnHand
    }
    private var available: Int { max(0, current) }
    private var parsed: (value: Int?, problem: StockQuantityProblem?) { StockRules.parseQuantity(quantity, allowZero: kind == .count) }
    private var delta: Int? { parsed.value.map { kind == .count ? $0 - current : -$0 } }
    private var largeDifference: Bool { kind == .count && parsed.value.map { StockRules.isLargeCountDifference(current: current, counted: $0) } == true }
    private var controlled: Bool { shown.controlSchedule?.nonEmpty != nil }
    private var noteRequired: Bool { kind == .waste ? (reason == .other || controlled) : largeDifference }

    var body: some View {
        ProviderModal(
            title: kind == .count ? LF("Count %@", shown.name) : LF("Write off %@", shown.name),
            subtitle: kind == .count ? L("Enter what is really on the shelf. The difference is recorded.") : L("Expired, damaged or lost — it leaves stock with the reason."),
            systemImage: kind == .count ? "clipboard-list" : "trash-2",
            accent: kind == .count ? .aqua : .pink,
            isDirty: reason != nil || !quantity.isEmpty || chosenLot != (lotId ?? wholeProduct),
            form: form,
            primaryTitle: kind == .count ? L("Record count") : L("Write off"),
            primaryVariant: kind == .waste ? .destructive : .primary,
            isWorking: saving,
            primaryIcon: kind == .count ? "clipboard-list" : "trash-2",
            primaryDisabled: kind == .waste && available == 0,
            onPrimary: { Task { await submit() } }
        ) {
            if let saveError { NoticeCard(tone: .problem, title: saveError.message, icon: saveError.connection ? "wifi-off" : "triangle-alert") }
            StockProductCard(row: shown, after: afterValue, afterLabel: kind == .count ? L("after this count") : L("after the write-off"), today: today)
            if shown.quantityOnHand < 0 && kind == .count {
                NoticeCard(tone: .warning, message: shown.quantityOnHand == -1
                            ? L("1 more was sold than the system had. Count what is on the shelf to set it right.")
                            : LF("%@ more were sold than the system had. Count what is on the shelf to set it right.", StockText.count(-shown.quantityOnHand)), icon: "triangle-alert")
            }
            if !lots.isEmpty {
                FormField(label: kind == .count ? L("What are you counting?") : L("Which lot?"), hint: kind == .waste && lot == nil ? L("Taken from what has expired first, then from the lots that expire soonest.") : nil, caps: true) {
                    FlowLayout(spacing: 8) {
                        ForEach(lotOptions, id: \.value) { option in
                            FilterChip(title: option.title, isSelected: chosenLot == option.value, tone: option.color ?? Theme.blue, dot: option.color) {
                                chosenLot = option.value
                            }
                        }
                    }
                }
                .onChange(of: chosenLot) { _, _ in saveError = nil }
            }
            if kind == .waste && available == 0 {
                NoticeCard(tone: .warning, message: lot != nil ? L("Nothing is left in this lot.") : L("There is nothing on the shelf to write off."), icon: "triangle-alert")
            } else {
                PMTextField(kind == .count ? L("Counted") : L("How many"), text: $quantity, key: "quantity", form: form, prompt: "0", hint: quantityHint, caps: true, required: true, number: .large)
            }
            if kind == .waste {
                FormField(label: L("Why"), key: "reason", form: form, caps: true, required: true) {
                    PillPicker(options: WasteReason.allCases.map { (value: $0, title: $0.label) }, choice: $reason)
                }
                .onChange(of: reason) { _, _ in form.clear("reason"); saveError = nil }
            } else if largeDifference {
                NoticeCard(tone: .warning, message: L("This count is far from what the system has. Count again, or say why below."), icon: "triangle-alert")
            }
            PMTextField(L("Note"), text: $note, key: "note", form: form, prompt: kind == .count ? L("e.g. Monthly count, two boxes found in the back") : L("e.g. Dropped on delivery, returned to the supplier"), optional: !noteRequired, multiline: true, caps: true, required: noteRequired, lines: 2...8)
            if kind == .waste && controlled {
                PMTextField(L("Witness"), text: $witness, prompt: L("Who saw it written off"), hint: L("Controlled medicine: the write-off, its reason and its witness go in the controlled register."), optional: true, caps: true)
            }
        }
        .onAppear(perform: start)
    }

    private func start() {
        guard !started else { return }
        started = true
        let firstExpired = kind == .waste ? row.lots.first { $0.quantityOnHand > 0 && StockRules.expiry($0.expiresOn, today: today) == .expired } : nil
        let startLot = row.lots.first { $0.id == (lotId ?? firstExpired?.id) }
        let expired = startLot.map { StockRules.expiry($0.expiresOn, today: today) == .expired } ?? false
        chosenLot = startLot?.id ?? wholeProduct
        // An expired lot is written off whole, unless someone says otherwise.
        if kind == .waste, let startLot, expired { quantity = String(startLot.quantityOnHand) }
        reason = kind == .waste && expired ? .expired : nil
    }

    private var lotOptions: [(value: String, title: String, color: Color?)] {
        let first: String
        if kind == .count {
            first = shown.quantityOnHand < 0
                ? LF("Whole product (%@)", StockText.short(shown.quantityOnHand, withCount: false))
                : LF("Whole product (%@)", StockText.count(shown.quantityOnHand))
        } else {
            first = L("Soonest to expire first")
        }
        return [(value: wholeProduct, title: first, color: nil)] + lots.map { entry in
            let state = StockRules.expiry(entry.expiresOn, today: today)
            var title = "\(entry.lotCode?.nonEmpty ?? L("No lot")) (\(StockText.count(entry.quantityOnHand)))"
            if let expires = entry.expiresOn?.nonEmpty { title += " · \(state == .expired ? L("expired") : L("exp.")) \(StockText.day(expires))" }
            // Expired red, close to expiry yellow, as the web's options.
            let color: Color? = state == .expired ? Theme.destructive : state == .soon ? Theme.lime : nil
            return (value: entry.id, title: title, color: color)
        }
    }

    private var afterValue: Int? {
        guard let delta, quantityProblem(force: false) == nil else { return nil }
        return shown.quantityOnHand + delta
    }

    private var quantityHint: String? {
        if quantityProblem(force: false) != nil { return nil }
        if kind == .count, let delta {
            if current < 0 {
                return current == -1 ? L("The system is 1 short: this count sets it right.") : LF("The system is %@ short: this count sets it right.", StockText.count(-current))
            }
            if delta == 0 { return LF("The system has %@: it matches.", StockText.count(current)) }
            return LF("The system has %@; difference %@.", StockText.count(current), StockText.signed(delta))
        }
        if kind == .waste, let value = parsed.value, let cost = lot?.unitCostAmount ?? shown.unitCostAmount, cost > 0, shown.unitCostAmount != nil {
            return LF("%@ at cost leaves the stock.", Money.format(value * cost))
        }
        if lot != nil { return LF("This lot has %@.", StockText.count(current)) }
        if current < 0 { return current == -1 ? L("The system is 1 short.") : LF("The system is %@ short.", StockText.count(-current)) }
        return LF("The system has %@.", StockText.count(current))
    }

    private func quantityProblem(force: Bool) -> String? {
        if kind == .waste && available == 0 { return nil }
        if let problem = parsed.problem {
            guard force || (quantity.nonEmpty != nil && problem != .required) else { return nil }
            switch problem {
            case .required: return kind == .count ? L("Enter what you counted. Zero if there is none.") : L("Enter how many leave the stock.")
            case .zero: return L("Write off at least one.")
            case .whole: return L("Stock is counted in whole units: no decimals.")
            case .negative: return kind == .count ? L("A count cannot be below zero.") : L("Enter how many leave the stock.")
            case .tooLarge: return L("That number is too large to be right. Check it.")
            case .invalid: return L("Enter the quantity as a number.")
            }
        }
        if kind == .waste, let value = parsed.value, value > available {
            if lot != nil { return available == 1 ? L("Only 1 left in this lot.") : LF("Only %@ left in this lot.", StockText.count(available)) }
            return LF("Only %@ on hand.", StockText.count(available))
        }
        return nil
    }

    private var noteProblem: String? {
        guard noteRequired, note.nonEmpty == nil else { return nil }
        if kind == .waste {
            return controlled && reason != .other ? L("A controlled medicine’s write-off needs a note: say what happened.") : L("Say what happened.")
        }
        return L("This count is far from what the system has. Say why.")
    }

    private func submit() async {
        guard !(kind == .waste && available == 0) else { return }
        guard form.check([
            ("quantity", quantityProblem(force: true)),
            ("reason", kind == .waste && reason == nil ? L("Choose why it leaves the stock.") : nil),
            ("note", noteProblem),
        ]), let value = parsed.value, let inventoryItemId = shown.inventoryItemId, !saving else { return }
        saving = true
        saveError = nil
        defer { saving = false }
        let words: String
        if kind == .waste, let reason {
            words = [reason.label, note.nonEmpty].compactMap { $0 }.joined(separator: " — ")
        } else {
            words = note.nonEmpty ?? L("Stock count")
        }
        let witnessName = kind == .waste && controlled ? witness.nonEmpty : nil
        // The same press sent again keeps its id; anything changed is a new press.
        let key = [kind == .count ? "count" : "waste", lot?.id ?? "", "\(value)", words, witnessName ?? "", "\(current)"].joined(separator: "|")
        let requestId = lastPress?.key == key ? (lastPress?.id ?? StockAPI.newRequestId()) : StockAPI.newRequestId()
        lastPress = (key, requestId)
        var body: [String: Any?] = [
            "kind": kind == .count ? "count" : "waste",
            "quantity": value,
            "lotId": lot?.id,
            "reason": words,
            "expectedOnHand": current,
            "clientRequestId": requestId,
        ]
        if let witnessName { body["witnessName"] = witnessName }
        do {
            let after: StockRow = try await StockAPI.send("POST", "/provider-stock/\(inventoryItemId)/adjust", body: body)
            Toast.show(kind == .count
                ? LF("Count recorded. %@ on hand now.", StockText.count(after.quantityOnHand))
                : value == 1 ? LF("1 unit written off. %@ on hand now.", StockText.count(after.quantityOnHand))
                : LF("%@ written off. %@ on hand now.", StockText.units(value), StockText.count(after.quantityOnHand)))
            onSaved()
            dismiss()
        } catch let refusal as StockRefusal where refusal.code == "stock_changed" {
            // Someone sold or counted meanwhile: the new figure is shown, and the person records again from it.
            let whole = refusal.body["quantityOnHand"]?.int
            let lotNow = refusal.body["lotQuantityOnHand"]?.int
            fresh = (whole, lot?.id, lot != nil ? lotNow : nil)
            let now = lot != nil ? (lotNow ?? whole) : whole
            let nowText = now.map { $0 < 0 ? ($0 == -1 ? L("now 1 is short") : LF("now %@ are short", StockText.count(-$0))) : LF("now %@ on hand", StockText.count($0)) }
            let message: String
            if let nowText {
                message = kind == .count
                    ? LF("The stock changed while this was open: %@. Check your count and record it again.", nowText)
                    : LF("The stock changed while this was open: %@. Check how many and write it off again.", nowText)
            } else {
                message = L("The stock changed while this was open. Check it and record it again.")
            }
            saveError = (message, false)
            Toast.error(message)
        } catch {
            let connection = stockIsConnectionError(error)
            let message = connection
                ? L("We could not reach PawMiaw. Nothing was changed here: check the stock before trying again.")
                : stockErrorText(error, fallback: L("Could not record this."))
            saveError = (message, connection)
            Toast.error(message)
        }
    }
}

// MARK: - One product: lots and history

private enum MovementGroup: Hashable { case all, came, went, counts }

struct StockDetailSheet: View {
    let row: StockRow
    let startOnHistory: Bool
    let canWriteOff: Bool
    let onWriteOff: (String) -> Void
    var onRoute: ((ProviderRoute) -> Void)? = nil

    @State private var history = false
    @State private var group: MovementGroup = .all
    @State private var movements: [StockMovement]?
    @State private var loadError: String?
    @State private var started = false

    private static let movementLimit = 100
    private var today: String { StockRules.today }
    private var lots: [StockLot] { row.lots.filter { $0.quantityOnHand != 0 } }

    var body: some View {
        ProviderModal(title: row.name, subtitle: L("Its lots and everything that moved its stock."), systemImage: "layers", accent: .aqua, cancelTitle: L("Close")) {
            StockProductCard(row: row, today: today)
            let kept = [
                row.storageLocation?.nonEmpty.map { LF("Kept in %@", $0) },
                row.reorderQuantity.flatMap { $0 > 0 ? LF("Usual order: %@", StockText.count($0)) : nil },
                row.allowBackorder ? L("Keeps selling at zero") : nil,
            ]
            if kept.contains(where: { $0 != nil }) {
                StockMetaLine(parts: kept).padding(.horizontal, 4).padding(.top, -8)
            }
            // On a phone the two choices drop their icons, as on the web.
            Segmented(options: [
                .init(false, L("Lots"), icon: "layers", badge: lots.isEmpty ? nil : lots.count),
                .init(true, L("History"), icon: "history"),
            ], selection: $history, look: .raised, label: L("What to see"), fill: true)
            if history { historyPart } else { lotsPart }
        }
        .onAppear {
            guard !started else { return }
            started = true
            history = startOnHistory
        }
        .task(id: history) {
            if history && movements == nil { await loadMovements() }
        }
    }

    @ViewBuilder
    private var lotsPart: some View {
        if lots.isEmpty {
            EmptyState(systemImage: "layers", title: L("No lots on the shelf"), message: L("Receive a delivery with its lot number or expiry date and it is listed here, soonest to expire first."), accent: Theme.aqua)
        } else {
            ListCard(style: .box) {
                ForEach(Array(lots.enumerated()), id: \.element.id) { index, lot in
                    if index > 0 { RowDivider() }
                    lotRow(lot)
                }
            }
            let loose = row.quantityOnHand - lots.reduce(0) { $0 + $1.quantityOnHand }
            if loose != 0 {
                HStack(alignment: .top, spacing: 8) {
                    Glyph("triangle-alert", size: 14).padding(.top, 1)
                    Text(loose > 0
                         ? (loose == 1 ? L("1 more on hand belongs to no lot: received without a lot number or expiry.") : LF("%@ more on hand belong to no lot: received without a lot number or expiry.", StockText.count(loose)))
                         : LF("The lots add up to %@ more than the product has on hand. A count sets it right.", StockText.count(-loose)))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func lotRow(_ lot: StockLot) -> some View {
        let state = StockRules.expiry(lot.expiresOn, today: today)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    FlowLayout(spacing: 8) {
                        Text(lot.lotCode.map { LF("Lot %@", $0) } ?? L("No lot number")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        if state == .expired { Chip(L("Expired@lot"), color: Theme.destructive, percent: 22, dot: true) }
                        if state == .soon { Chip(L("Expiring soon"), color: Theme.lime, percent: 22, dot: true) }
                    }
                    StockMetaLine(parts: [
                        lot.expiresOn.map { state == .expired ? LF("Expired on %@", StockText.day($0)) : LF("Expires %@", StockText.day($0)) } ?? L("No expiry date"),
                        lot.receivedAt.map { LF("received %@", DateText.date(DateText.parse($0))) },
                        lot.unitCostAmount.flatMap { $0 > 0 ? LF("%@ each", Money.format($0)) : nil },
                    ])
                }
                Spacer(minLength: 4)
                Text(StockText.count(lot.quantityOnHand)).font(.brandHeading(20)).monospacedDigit()
                    .foregroundStyle(state == .expired ? Theme.destructive : Theme.inkStrong)
            }
            if canWriteOff && state == .expired && lot.quantityOnHand > 0 {
                PMButton(L("Write off"), systemImage: "trash-2", variant: .outline) { onWriteOff(lot.id) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func loadMovements() async {
        guard let id = row.inventoryItemId else { movements = []; return }
        do {
            movements = try await API.get("/provider-stock/\(id)/movements")
            loadError = nil
        } catch is CancellationError {
        } catch {
            loadError = errorText(error)
        }
    }

    private func inGroup(_ movement: StockMovement) -> Bool {
        switch group {
        case .all: true
        case .came: ["initial", "restock", "return"].contains(movement.movementType)
        case .went: ["sale", "waste"].contains(movement.movementType)
        case .counts: ["correction", "adjustment"].contains(movement.movementType)
        }
    }

    @ViewBuilder
    private var historyPart: some View {
        if let loadError, movements == nil {
            EmptyState(systemImage: "history", title: L("The history could not be loaded."), message: loadError, actionTitle: L("Try again"), action: { Task { await loadMovements() } }, accent: Theme.pink)
        } else if let movements {
            if movements.isEmpty {
                EmptyState(systemImage: "history", title: L("Nothing has moved yet."), accent: Theme.mango)
            } else {
                let listed = movements.filter(inGroup)
                FlowLayout(spacing: 6) {
                    FilterChip(title: L("Everything"), isSelected: group == .all, tone: Theme.blue) { group = .all }
                    FilterChip(title: L("Came in"), isSelected: group == .came, tone: ProviderState.done.color, dot: ProviderState.done.color) { group = .came }
                    FilterChip(title: L("Went out"), isSelected: group == .went, tone: Theme.destructive, dot: Theme.destructive) { group = .went }
                    FilterChip(title: L("Counts"), isSelected: group == .counts, tone: Theme.lime, dot: Theme.lime) { group = .counts }
                }
                if listed.isEmpty {
                    Text(L("No movements of this kind.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    ListCard(style: .box) {
                        ForEach(Array(listed.enumerated()), id: \.element.id) { index, movement in
                            if index > 0 { RowDivider() }
                            movementRow(movement)
                        }
                    }
                }
                Text(movements.count >= Self.movementLimit ? LF("These are the latest %d movements.", Self.movementLimit) : (listed.count == 1 ? L("1 movement") : LF("%d movements", listed.count)))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        } else {
            LoadingState()
        }
    }

    private func movementRow(_ movement: StockMovement) -> some View {
        let delta = movement.quantityDelta ?? 0
        return HStack(alignment: .center, spacing: 12) {
            Text(StockText.signed(delta))
                .font(.brandHeading(18))
                .monospacedDigit()
                .foregroundStyle(delta < 0 ? Theme.destructive : ProviderState.done.color)
                .frame(width: 56, alignment: .trailing)
            VStack(alignment: .leading, spacing: 0) {
                FlowLayout(spacing: 0) {
                    Text(Self.label(movement)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    if let folio = movement.folio?.nonEmpty {
                        Text(" · ").font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        if let invoiceId = movement.invoiceId, let onRoute {
                            // The sale in the Store, or the visit's bill in Invoices.
                            Button(folio) { onRoute(movement.invoiceKind == "sale" ? .sale(invoiceId) : .invoice(invoiceId)) }
                                .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                                .accessibilityLabel(LF("Open %@", folio))
                        } else {
                            Text(folio).font(.system(size: 14, design: .monospaced)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    if let lot = movement.lotCode?.nonEmpty { Text(" · \(LF("Lot %@", lot))").font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                }
                StockMetaLine(parts: [
                    StockText.dateTime(movement.occurredAt),
                    movement.actorName,
                    movement.movementType == "restock" ? movement.unitCostAmount.flatMap { $0 > 0 ? LF("%@ each", Money.format($0)) : nil } : nil,
                ])
                if let notes = movement.notes?.nonEmpty { Text(notes).font(Theme.text(12)).foregroundStyle(Theme.inkStrong).padding(.top, 2) }
            }
            Spacer(minLength: 4)
            Text(LF("→ %@", StockText.count(movement.quantityAfter ?? 0))).font(Theme.text(12)).monospacedDigit().foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// What the movement was. A dose given in the hospital took stock without selling it.
    static func label(_ movement: StockMovement) -> String {
        if movement.sourceType == "hospital_administration" {
            if movement.movementType == "sale" { return L("Given in the hospital") }
            if movement.movementType == "return" { return L("Put back from the hospital") }
        }
        switch movement.movementType {
        case "initial": return L("Starting stock")
        case "restock": return L("Received")
        case "adjustment": return L("Adjusted")
        case "sale": return L("Sold")
        case "return": return L("Returned")
        case "waste": return L("Written off")
        case "correction": return L("Counted@movement")
        default: return movement.movementType
        }
    }
}

// MARK: - Stock settings

struct StockSettingsSheet: View {
    let row: StockRow
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var reorderPoint = ""
    @State private var reorderQuantity = ""
    @State private var storageLocation = ""
    @State private var barcode = ""
    @State private var allowBackorder = false
    @State private var lowStockAlert = true
    @State private var saving = false
    @State private var saveError: (message: String, connection: Bool)?
    @State private var started = false

    private var point: (value: Int?, problem: StockQuantityProblem?) {
        reorderPoint.nonEmpty == nil ? (0, nil) : StockRules.parseQuantity(reorderPoint, allowZero: true)
    }
    private var usual: (value: Int?, problem: StockQuantityProblem?) {
        reorderQuantity.nonEmpty == nil ? (nil, nil) : StockRules.parseQuantity(reorderQuantity, allowZero: true)
    }
    private var effectivePoint: Int { (point.value ?? 0) > 0 ? point.value! : StockRules.defaultLowPoint }
    /// What can still be sold is what the alert goes by.
    private var sellable: Int { row.quantityOnHand - max(0, row.expiredUnits ?? 0) }
    private var changed: Bool {
        allowBackorder != row.allowBackorder || lowStockAlert != (row.lowStockAlert != false)
            || reorderPoint != (row.reorderPoint > 0 ? String(row.reorderPoint) : "")
            || reorderQuantity != (row.reorderQuantity.map { $0 > 0 ? String($0) : "" } ?? "")
            || storageLocation != (row.storageLocation ?? "") || barcode != (row.barcode ?? "")
    }

    var body: some View {
        ProviderModal(title: L("Stock settings"), subtitle: L("When it counts as low, where it is kept and how it is found."), systemImage: "sliders-horizontal", accent: .butter,
                      isDirty: changed, form: form, primaryTitle: L("Save settings"), isWorking: saving, primaryIcon: "save", onPrimary: { Task { await submit() } }) {
            if let saveError { NoticeCard(tone: .problem, title: saveError.message, icon: saveError.connection ? "wifi-off" : "triangle-alert") }
            StockProductCard(row: row)
            ModalSection(title: L("Low stock"), subtitle: L("While it is on, the product shows as low stock here, at the counter and on Home once this few are left to sell.")) {
                ToggleRow(title: L("Mark it low on Home and Inventory"),
                          subtitle: lowStockAlert ? L("Flagged as low at the count below.") : L("Never flagged as low: it only shows once it is out of stock."),
                          isOn: $lowStockAlert)
                if lowStockAlert {
                    PMTextField(L("Low at"), text: $reorderPoint, key: "reorderPoint", form: form, prompt: String(StockRules.defaultLowPoint), hint: pointHint, optional: true, caps: true, strongHint: lowAfter, number: .plain)
                }
                PMTextField(L("Usual order"), text: $reorderQuantity, key: "reorderQuantity", form: form, prompt: L("None"), hint: L("How many units you usually ask the supplier for."), optional: true, caps: true, number: .plain)
            }
            ModalSection(title: L("Finding it")) {
                FormField(label: L("Barcode"), hint: L("A scan at the counter or in a delivery then finds this product."), optional: true, caps: true) {
                    HStack(spacing: 8) {
                        TextField(L("Scan it or type it"), text: $barcode)
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .fieldChrome()
                        BarcodeScanButton { scan in barcode = String(scan.code.prefix(120)) }
                    }
                }
                PMTextField(L("Where it is kept"), text: $storageLocation, prompt: L("e.g. Shelf B, fridge"), optional: true, caps: true)
            }
            ToggleRow(title: L("Keep selling when it runs out"),
                      subtitle: allowBackorder ? L("The counter sells it at zero; the stock goes negative until the next delivery or count.") : L("The counter stops selling it once none is left."),
                      isOn: $allowBackorder)
        }
        .onAppear {
            guard !started else { return }
            started = true
            reorderPoint = row.reorderPoint > 0 ? String(row.reorderPoint) : ""
            reorderQuantity = row.reorderQuantity.map { $0 > 0 ? String($0) : "" } ?? ""
            storageLocation = row.storageLocation ?? ""
            barcode = row.barcode ?? ""
            allowBackorder = row.allowBackorder
            lowStockAlert = row.lowStockAlert != false
        }
    }

    /// With what is left to sell, it would show as low once saved.
    private var lowAfter: Bool { point.problem == nil && lowStockAlert && point.value != nil && sellable <= effectivePoint }

    private var pointHint: String {
        if point.problem != nil { return L("Enter a whole number, or leave it empty.") }
        if lowAfter {
            return LF("With %@ to sell, it will show as low stock.", StockText.count(max(0, sellable)))
        }
        if reorderPoint.nonEmpty != nil, (point.value ?? 0) > 0 { return LF("Low once %@ or fewer are left.", StockText.count(effectivePoint)) }
        return LF("Empty: low once %@ or fewer are left.", StockText.count(StockRules.defaultLowPoint))
    }

    private func submit() async {
        let wholeNumber = L("Enter a whole number, or leave it empty.")
        guard form.check([
            ("reorderPoint", lowStockAlert && point.problem != nil ? wholeNumber : nil),
            ("reorderQuantity", usual.problem != nil ? wholeNumber : nil),
        ]), !saving else { return }
        saving = true
        saveError = nil
        defer { saving = false }
        do {
            try await API.send("PATCH", "/provider-catalog/\(row.catalogItemId)/inventory", body: [
                "lowStockAlert": lowStockAlert,
                "reorderPoint": point.value ?? 0,
                "reorderQuantity": (usual.value ?? 0) > 0 ? usual.value : nil,
                "storageLocation": storageLocation.nonEmpty,
                "barcode": barcode.nonEmpty,
                "allowBackorder": allowBackorder,
            ])
            Toast.show(LF("Stock settings of %@ saved.", row.name))
            onSaved()
            dismiss()
        } catch {
            let connection = stockIsConnectionError(error)
            saveError = (connection
                ? L("We could not reach PawMiaw. Nothing was saved: your changes are still here, try again.")
                : stockErrorText(error, fallback: L("Could not save these settings.")), connection)
            form.apply(error, known: ["reorderPoint": "reorderPoint", "reorderQuantity": "reorderQuantity"])
        }
    }
}
