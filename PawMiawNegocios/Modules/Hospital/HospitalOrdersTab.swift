//
//  HospitalOrdersTab.swift
//  PawMiawNegocios
//
//  The treatment plan (web hospital-orders-tab.tsx): every order, what it
//  says and who wrote or changed it. Vets add, change (each change kept with
//  its reason and the revision it was made on) and stop orders; each order
//  becomes rows on the sheet. An order with doses on the sheet keeps its
//  schedule (`order_has_doses`): stop it and write a new one.
//

import SwiftUI

private enum HospOrderEditing: Identifiable {
    case new
    case change(HospOrder)
    var id: String { if case .change(let order) = self { return order.id }; return "new" }
    var order: HospOrder? { if case .change(let order) = self { return order }; return nil }
}

struct HospOrdersTab: View {
    @ObservedObject var model: HospDetailModel
    let detail: HospDetail
    let canManage: Bool

    @State private var editing: HospOrderEditing?
    @State private var stopping: HospOrder?
    @State private var history: HospOrder?

    var body: some View {
        let active = detail.allOrders.filter { !$0.isStopped }
        let stopped = detail.allOrders.filter(\.isStopped)
        VStack(alignment: .leading, spacing: 16) {
            if canManage && detail.isAdmitted {
                HStack {
                    Spacer()
                    PMButton(L("Add an order"), systemImage: "plus", size: .compact) { editing = .new }
                }
            }
            if detail.allOrders.isEmpty {
                EmptyState(systemImage: "clipboard-list", title: L("No orders yet"),
                           message: detail.isAdmitted ? L("Medicines, fluids, feeding and checks: each becomes rows on the sheet.") : L("Orders are written once the patient is admitted."),
                           accent: Theme.pink, panel: true)
            }
            ForEach([(L("Active"), active), (L("Stopped"), stopped)], id: \.0) { title, list in
                if !list.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(title).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                            Text("\(list.count)").font(Theme.text(12, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                                .padding(.horizontal, 10).padding(.vertical, 2).background(Theme.surfaceMuted, in: Capsule())
                        }
                        Card(padding: 0, spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { index, order in
                                if index > 0 { RowDivider() }
                                row(order)
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $editing) { HospOrderSheet(model: model, detail: detail, order: $0.order) }
        .sheet(item: $history) { HospOrderHistorySheet(detail: detail, order: $0) }
        .sheet(item: $stopping) { order in
            ConfirmSheet(
                title: LF("Stop %@?", order.name.nonEmpty ?? L("this order")),
                message: L("No more doses of it come due. What was already given stays on the sheet."),
                confirmTitle: L("Stop order"),
                destructive: true,
                askReason: true,
                cancelTitle: L("Keep it")
            ) { reason in
                do {
                    try await model.write("/orders/\(order.id)/stop", body: ["reason": reason])
                    Toast.show(L("Order stopped."))
                } catch { throw hospRefusal(error, fallback: "Could not stop it.") }
            }
        }
    }

    private func row(_ order: HospOrder) -> some View {
        let zone = detail.zone
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(HospWords.kind(order.kind).uppercased()).font(.brandText(10.4, weight: .heavy)).tracking(1.04).foregroundStyle(Theme.blue)
                Text(order.name.nonEmpty ?? L("Order")).font(Theme.text(16, weight: .bold)).strikethrough(order.isStopped).foregroundStyle(Theme.inkStrong)
                let line = [HospFmt.orderLine(order).nonEmpty, HospFmt.schedule(order, zone).nonEmpty].compactMap { $0 }.joined(separator: " · ")
                if !line.isEmpty { Text(line).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                Text([
                    LF("From %@", HospFmt.dateTime(order.startsAt, zone)),
                    order.endsAt.map { LF("until %@", HospFmt.dateTime($0, zone)) },
                    order.catalogItem.flatMap { item in order.chargeable == true ? LF("charges %d × %@", order.chargeQuantity ?? 1, item.name ?? "") : nil },
                ].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                if let instructions = order.instructions?.nonEmpty { Text(instructions).font(Theme.text(14)).italic().foregroundStyle(Theme.inkSoft).padding(.top, 2) }
                if order.isStopped {
                    Text(LF("Stopped %@", order.stoppedAt.map { HospFmt.dateTime($0, zone) } ?? "") + (order.stopReason?.nonEmpty.map { " — \($0)" } ?? ""))
                        .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft).padding(.top, 2)
                }
            }
            FlowLayout(spacing: 6) {
                PMButton(L("History"), systemImage: "history", variant: .outline, size: .compact) { history = order }
                if canManage && detail.isAdmitted && !order.isStopped {
                    PMButton(L("Change"), systemImage: "pencil", variant: .outline, size: .compact) { editing = .change(order) }
                    PMButton(L("Stop"), systemImage: "square", variant: .destructive, size: .compact) { stopping = order }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(order.isStopped ? 0.7 : 1)
    }
}

// MARK: - Write or change an order

private struct HospOrderSheet: View {
    @ObservedObject var model: HospDetailModel
    let detail: HospDetail
    let order: HospOrder?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var kind: String? = "medication"
    @State private var item: HospCatalogRef?
    @State private var label = ""
    @State private var dose = ""
    @State private var unit = ""
    @State private var route = ""
    @State private var rate = ""
    @State private var scheduleKind: String? = "times"
    @State private var times = "08:00, 20:00"
    @State private var everyHours = "8"
    @State private var onceAt = Date()
    @State private var startsAt = Date()
    @State private var endsAt: Date?
    @State private var chargeable = true
    @State private var chargeQuantity = "1"
    @State private var instructions = ""
    @State private var reason = ""
    @State private var saving = false
    @State private var filled = false

    var body: some View {
        ProviderModal(
            title: order.map { LF("Change %@", $0.name.nonEmpty ?? L("the order")) } ?? L("New order"),
            subtitle: order.map { LF("Revision %d. The change is kept with your name and reason.", $0.revision ?? 1) } ?? L("Each dose shows up on the sheet to tick."),
            systemImage: "package",
            accent: .aqua,
            isDirty: filled && (!label.isEmpty || item != nil || !instructions.isEmpty || !reason.isEmpty),
            form: form,
            primaryTitle: order == nil ? L("Add order") : L("Save change"),
            isWorking: saving,
            primaryIcon: "save",
            onPrimary: save
        ) {
            ModalSection(title: L("What")) {
                PillPicker(options: HospWords.kinds.map { ($0, HospWords.kind($0)) }, choice: $kind)
                    .accessibilityLabel(L("Kind"))
                if let item {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "").font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            HospHint(text: L("From the Catalog: charged and taken from stock when given"))
                        }
                        Spacer()
                        IconCircleButton(systemImage: "x", label: L("Remove item")) { self.item = nil }
                    }
                    .padding(12)
                    .background(Theme.wash(Theme.aqua, 14), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                } else {
                    HospCatalogSearch(prompt: L("Search the Catalog: medicines, supplies, services"),
                                      emptyText: L("Nothing in the Catalog by that name. Name the order below: it won’t be charged.")) { entry in
                        item = HospCatalogRef(id: entry.id, name: entry.name, itemType: entry.itemType, unitAmount: entry.defaultUnitAmount)
                    }
                }
                PMTextField(L("Name on the sheet"), text: $label, key: "label", form: form,
                            prompt: item?.name ?? L("e.g. Maropitant, Lactated Ringer’s, Walk and check the wound"), required: item == nil)
            }
            ModalSection(title: L("How much and how")) {
                HStack(alignment: .top, spacing: 12) {
                    PMTextField(L("Dose"), text: $dose, key: "dose", form: form, keyboard: .decimalPad, required: kind == "medication", number: .plain)
                    PMTextField(L("Unit"), text: $unit, key: "unit", form: form, prompt: "mg, ml, tab", required: kind == "medication")
                }
                HStack(alignment: .top, spacing: 12) {
                    MenuField(label: L("Route"), options: [("", "—")] + HospWords.routes.map { ($0, HospWords.route($0)) }, selection: $route)
                    PMTextField(L("Rate (ml/h)"), text: $rate, key: "rate", form: form, prompt: kind == "fluid" ? "40" : nil, keyboard: .decimalPad, required: kind == "fluid")
                }
            }
            ModalSection(title: L("When"), required: true) {
                PillPicker(options: HospWords.schedules.map { ($0, HospWords.schedule($0)) }, choice: $scheduleKind)
                    .accessibilityLabel(L("Schedule"))
                switch scheduleKind {
                case "times":
                    let parsed = HospFmt.parseTimesOfDay(times)
                    PMTextField(LF("Times of day (%@)", detail.zone.identifier), text: $times, key: "times", form: form, prompt: "08:00, 14:00, 20:00",
                                hint: parsed.flatMap { $0.isEmpty ? nil : $0.map { HospFmt.timeOfDay($0) }.joined(separator: " · ") } ?? L("24-hour times or with a.m. / p.m., separated by commas."),
                                keyboard: .numbersAndPunctuation, required: true)
                case "every":
                    PMTextField(L("Every (hours)"), text: $everyHours, key: "every", form: form, hint: L("hours, from the start"), keyboard: .numberPad)
                case "once":
                    DateTimeField(label: L("At"), date: $onceAt, zone: detail.zone, required: true)
                default:
                    HospHint(text: L("No set times: it is given with “Give now” when needed."))
                }
                DateTimeField(label: L("Starts"), date: $startsAt, zone: detail.zone, required: true)
                OptionalDateField(label: L("Ends (optional)"), date: $endsAt, placeholder: L("No end date"), zone: detail.zone, min: startsAt, components: [.date, .hourAndMinute], defaultDate: startsAt.addingTimeInterval(86_400))
                if let message = form.error("ends") { Text(message).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral).id("ends") }
            }
            if item != nil {
                ToggleRow(title: L("Charge each dose"), subtitle: L("A line on the running bill for every dose given."), isOn: $chargeable)
                if chargeable {
                    PMTextField(L("Quantity per dose"), text: $chargeQuantity, key: "quantity", form: form, keyboard: .numberPad)
                }
            }
            PMTextField(L("Instructions"), text: $instructions, prompt: L("e.g. Give slowly over 2 minutes; hold if vomiting"), multiline: true)
            if order != nil {
                PMTextField(L("Why it changes"), text: $reason, prompt: L("e.g. Dose adjusted to the new weight"))
            }
        }
        .onAppear(perform: fill)
    }

    private func fill() {
        guard !filled else { return }
        filled = true
        guard let order else { return }
        kind = order.kind ?? "medication"
        item = order.catalogItem
        label = order.label ?? ""
        dose = order.doseAmount.map { HospFmt.number($0) } ?? ""
        unit = order.doseUnit ?? ""
        route = order.route ?? ""
        rate = order.rateMlPerHour.map { HospFmt.number($0) } ?? ""
        scheduleKind = order.scheduleKind ?? "times"
        times = (order.scheduleTimes ?? []).joined(separator: ", ")
        everyHours = order.everyHours.map(String.init) ?? "8"
        onceAt = DateText.parse(order.onceAt) ?? Date()
        startsAt = DateText.parse(order.startsAt) ?? Date()
        endsAt = DateText.parse(order.endsAt)
        chargeable = order.chargeable ?? true
        chargeQuantity = "\(order.chargeQuantity ?? 1)"
        instructions = order.instructions ?? ""
    }

    private func save() {
        let doseValue = HospFmt.read(dose)
        let rateValue = HospFmt.read(rate)
        let parsedTimes = HospFmt.parseTimesOfDay(times)
        let every = Int(everyHours)
        let quantity = Int(chargeQuantity)
        guard form.check([
            ("label", label.nonEmpty == nil && item == nil ? L("Name the order.") : nil),
            ("dose", doseValue.map { $0.isNaN || $0 <= 0 } == true ? L("Enter a dose greater than zero.")
                : (kind == "medication" && doseValue == nil ? L("A medicine needs its dose and unit.") : nil)),
            ("unit", kind == "medication" && unit.nonEmpty == nil ? L("A medicine needs its dose and unit.") : nil),
            ("rate", rateValue.map { $0.isNaN || $0 <= 0 || $0 > 5000 } == true ? L("Enter the rate in ml/h, up to 5000.")
                : (kind == "fluid" && rateValue == nil ? L("Fluids need their rate (ml/h).") : nil)),
            ("times", scheduleKind == "times" ? ((parsedTimes ?? []).isEmpty ? L("Write the times of day, like 08:00, 20:00.") : ((parsedTimes?.count ?? 0) > 24 ? L("At most 24 times a day.") : nil)) : nil),
            ("every", scheduleKind == "every" && !(every.map { (1...72).contains($0) } ?? false) ? L("Every 1 to 72 hours.") : nil),
            ("ends", endsAt.map { $0 <= startsAt } == true ? L("It ends after it starts.") : nil),
            ("quantity", item != nil && chargeable && !(quantity.map { (1...1000).contains($0) } ?? false) ? L("Charge between 1 and 1000 per dose.") : nil),
        ]) else { return }

        let input: [String: Any?] = [
            "kind": kind ?? "medication",
            "label": label.nonEmpty,
            "catalogItemId": item?.id,
            "doseAmount": doseValue,
            "doseUnit": unit.nonEmpty,
            "route": route.nonEmpty,
            "rateMlPerHour": rateValue,
            "scheduleKind": scheduleKind ?? "times",
            "scheduleTimes": scheduleKind == "times" ? parsedTimes : nil,
            "everyHours": scheduleKind == "every" ? every : nil,
            "onceAt": scheduleKind == "once" ? DateText.iso(onceAt) : nil,
            "startsAt": DateText.iso(startsAt),
            "endsAt": endsAt.map { DateText.iso($0) },
            "chargeable": item != nil && chargeable,
            "chargeQuantity": item != nil && chargeable ? (quantity ?? 1) : 1,
            "instructions": instructions.nonEmpty,
        ]
        saving = true
        Task {
            defer { saving = false }
            do {
                if let order {
                    var changes = changed(order, input)
                    if changes.isEmpty { dismiss(); return }
                    changes["reason"] = reason.nonEmpty
                    changes["expectedRevision"] = order.revision
                    try await model.write("/orders/\(order.id)", method: "PATCH", body: changes)
                    Toast.show(L("Order changed."))
                } else {
                    try await model.write("/orders", body: input)
                    Toast.show(L("Order added. Its doses are on the sheet."))
                }
                dismiss()
            } catch {
                if (error as? APIError)?.code == "stale_order" {
                    await model.load()
                    dismiss()
                }
                Toast.error(hospError(error, fallback: "Could not save the order."))
            }
        }
    }

    /// Only what changed (the server keeps each change as an event).
    private func changed(_ order: HospOrder, _ next: [String: Any?]) -> [String: Any?] {
        let before: [String: Any?] = [
            "kind": order.kind, "label": order.label, "catalogItemId": order.catalogItem?.id, "doseAmount": order.doseAmount, "doseUnit": order.doseUnit,
            "route": order.route, "rateMlPerHour": order.rateMlPerHour, "scheduleKind": order.scheduleKind,
            "scheduleTimes": order.scheduleKind == "times" ? order.scheduleTimes : nil,
            "everyHours": order.scheduleKind == "every" ? order.everyHours : nil,
            "onceAt": order.scheduleKind == "once" ? order.onceAt : nil,
            "startsAt": order.startsAt, "endsAt": order.endsAt, "chargeable": order.chargeable, "chargeQuantity": order.chargeQuantity,
            "instructions": order.instructions,
        ]
        var out: [String: Any?] = [:]
        for (key, value) in next {
            let previous = before[key] ?? nil
            let same: Bool
            if ["startsAt", "endsAt", "onceAt"].contains(key) {
                let a = (previous as? String).flatMap { DateText.parse($0) }.map { Int($0.timeIntervalSince1970 / 60) }
                let b = (value as? String).flatMap { DateText.parse($0) }.map { Int($0.timeIntervalSince1970 / 60) }
                same = a == b
            } else {
                same = describe(previous) == describe(value)
            }
            if !same { out[key] = value }
        }
        return out
    }

    private func describe(_ value: Any?) -> String {
        switch value {
        case nil: return "null"
        case let double as Double: return HospFmt.number(double)
        case let int as Int: return String(int)
        case let bool as Bool: return bool ? "true" : "false"
        case let list as [String]: return list.joined(separator: ",")
        case let text as String: return text
        case let some?: return "\(some)"
        }
    }
}

// MARK: - An order's history

private struct HospOrderHistorySheet: View {
    let detail: HospDetail
    let order: HospOrder
    @State private var events: [HospOrderEvent]?
    @State private var error: String?

    var body: some View {
        ProviderModal(title: order.name.nonEmpty ?? L("Order"), subtitle: L("Who wrote, changed or stopped it, and why"), systemImage: "history", accent: .aqua, cancelTitle: L("Close")) {
            if let events {
                if events.isEmpty {
                    EmptyState(systemImage: "history", title: L("No history yet."), accent: Theme.pink)
                } else {
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.action == "created" ? L("Written") : event.action == "stopped" ? L("Stopped") : L("Changed"))
                                .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            + Text(" · \(event.actorName ?? L("Someone")) · \(HospFmt.dateTime(event.createdAt, detail.zone))").font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                            if event.action == "changed", let changes = event.changes?.object {
                                ForEach(changes.keys.sorted(), id: \.self) { field in
                                    let change = changes[field]
                                    (Text("\(fieldLabel(field)): ").font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                                     + Text(show(change?["from"])).font(Theme.text(14)).strikethrough().foregroundStyle(Theme.inkSoft)
                                     + Text(" → ").foregroundStyle(Theme.inkSoft)
                                     + Text(show(change?["to"])).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong))
                                }
                            }
                            if let reason = event.reason?.nonEmpty { Text("“\(reason)”").font(Theme.text(14)).italic().foregroundStyle(Theme.inkSoft) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                    }
                }
            } else if let error {
                ErrorState(message: error) { await load() }
            } else {
                LoadingState()
            }
            StitchedDivider()
            FactRow(label: L("Written by"), value: order.createdByName ?? "—")
            FactRow(label: L("Last changed by"), value: order.updatedByName ?? "—")
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let answer: HospOrderEvents = try await API.get(HospAPI.detailPath(detail.id) + "/orders/\(order.id)/events")
            events = answer.events ?? []
        } catch {
            self.error = errorText(error)
        }
    }

    private func fieldLabel(_ field: String) -> String {
        switch field {
        case "kind": L("Kind")
        case "label": L("Name")
        case "catalogItemId": L("Catalog item")
        case "doseAmount": L("Dose")
        case "doseUnit": L("Unit")
        case "route": L("Route")
        case "rateMlPerHour": L("Rate (ml/h)")
        case "scheduleKind": L("Schedule")
        case "scheduleTimes": L("Times of day")
        case "everyHours": L("Every (h)")
        case "onceAt": L("At")
        case "startsAt": L("Starts")
        case "endsAt": L("Ends")
        case "chargeable": L("Charged")
        case "chargeQuantity": L("Quantity per dose")
        case "instructions": L("Instructions")
        default: field
        }
    }

    private func show(_ value: JSONValue?) -> String {
        guard let value, !value.isNull else { return "—" }
        if let list = value.array { return list.map { $0.string.map { HospFmt.timeOfDay($0) } ?? "" }.joined(separator: ", ") }
        if let flag = value.bool { return flag ? L("Yes") : L("No") }
        if let text = value.string {
            if text.count > 10, text.dropFirst(10).hasPrefix("T"), DateText.parse(text) != nil { return HospFmt.dateTime(text, detail.zone) }
            return text.isEmpty ? "—" : text
        }
        return "—"
    }
}
