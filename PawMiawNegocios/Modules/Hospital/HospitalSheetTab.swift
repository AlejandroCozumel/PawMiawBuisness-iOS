//
//  HospitalSheetTab.swift
//  PawMiawNegocios
//
//  The treatment sheet of one day (web hospital-sheet-tab.tsx): a row per
//  order, each scheduled dose a cell in its state (ProviderState.slot); tap
//  one to mark it given or not given (with the web's reasons), at its real
//  time and dose, or to strike a wrong mark out. "Give now" / "Extra dose"
//  records a dose off schedule. A dose more than an hour ahead isn't marked
//  yet; a stopped order's missed doses still are (docs/hospital-sheet-and-notices.md).
//

import SwiftUI

private struct HospTicking: Identifiable {
    let order: HospOrder
    let slot: HospSheetSlot?
    var id: String { order.id + (slot?.scheduledFor ?? "-now") }
}

private struct HospViewing: Identifiable {
    let order: HospOrder
    let entry: HospAdministration
    var id: String { entry.id }
}

struct HospSheetTab: View {
    @ObservedObject var model: HospDetailModel
    let detail: HospDetail
    let canCare: Bool
    let canManage: Bool
    let onOrders: () -> Void
    let onPrint: () -> Void

    @State private var ticking: HospTicking?
    @State private var viewing: HospViewing?
    @State private var showVoided = false

    private var zone: TimeZone { detail.zone }
    private var orders: [String: HospOrder] { Dictionary(detail.allOrders.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var rows: [HospSheetRow] { (detail.sheet?.rows ?? []).filter { orders[$0.orderId] != nil } }
    private var day: String { detail.sheet?.day ?? detail.sheet?.today ?? "" }
    private var isToday: Bool { day == detail.sheet?.today }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array((detail.sheet?.days ?? []).enumerated()), id: \.element) { index, entry in
                        let on = entry == day
                        Button {
                            model.day = entry == detail.sheet?.today ? nil : entry
                        } label: {
                            VStack(spacing: 2) {
                                Text((entry == detail.sheet?.today ? L("Today") : LF("Day %d", index + 1)).uppercased())
                                    .font(.brandText(9.9, weight: .heavy)).tracking(0.99)
                                    .foregroundStyle(on ? Theme.onBlue.opacity(0.9) : Theme.inkSoft)
                                Text(HospFmt.day(entry, style: .compact, zone: zone)).font(Theme.text(14, weight: .bold)).foregroundStyle(on ? Theme.onBlue : Theme.inkStrong)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .frame(minWidth: 72)
                            .background(on ? Theme.blue : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(on ? Theme.blue : Theme.borderSoft, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            PMButton(L("Day’s sheet PDF"), systemImage: "printer", variant: .outline, size: .compact, action: onPrint)

            if rows.isEmpty {
                // Waiting or in: the plan is still to write. Once it ended, there was simply none.
                if detail.isAdmitted || detail.isPending {
                    EmptyState(systemImage: "syringe", title: L("No treatment yet"),
                               message: detail.isPending ? L("The treatment plan is written once the patient is admitted.")
                                : canManage ? L("Write the treatment plan in Orders: each dose shows up here to tick.")
                                : L("The vet writes the treatment plan; each dose shows up here to tick."),
                               actionTitle: detail.isAdmitted && canManage ? L("Write the orders") : nil,
                               action: detail.isAdmitted && canManage ? onOrders : nil,
                               accent: Theme.pink, panel: true)
                } else {
                    EmptyState(systemImage: "syringe", title: L("No treatment on this day"), message: L("No order had a dose on this day."), accent: Theme.pink, panel: true)
                }
            } else {
                // One card, a row per order (web: the sheet's panel).
                Card(padding: 0, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if let order = orders[row.orderId] {
                            if index > 0 { RowDivider() }
                            orderRow(order, row)
                        }
                    }
                }
            }

            HospSlotLegend()

            let voided = rows.flatMap { row in (row.voided ?? []).map { (row.orderId, $0) } }
            if !voided.isEmpty {
                Card(padding: 0, spacing: 0) {
                    Button { withAnimation { showVoided.toggle() } } label: {
                        HStack {
                            Text(voided.count == 1 ? L("1 struck out") : LF("%d struck out", voided.count)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            Spacer()
                            Glyph("chevron-down", size: 16).rotationEffect(.degrees(showVoided ? 180 : 0)).foregroundStyle(Theme.inkSoft)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showVoided {
                        RowDivider()
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(voided, id: \.1.id) { orderId, entry in
                                (Text("\(orders[orderId]?.name ?? "") · \(HospFmt.clock(entry.scheduledFor ?? entry.givenAt, zone))").bold().strikethrough().foregroundStyle(Theme.inkStrong)
                                    + Text(" — " + [entry.voidReason, entry.givenByName].compactMap { $0?.nonEmpty }.joined(separator: " · ")).foregroundStyle(Theme.inkSoft))
                                    .font(Theme.text(14))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .sheet(item: $ticking) { HospTickSheet(model: model, detail: detail, order: $0.order, slot: $0.slot) }
        .sheet(item: $viewing) { HospTickViewSheet(model: model, detail: detail, order: $0.order, entry: $0.entry, canCare: canCare, canManage: canManage) }
    }

    private func orderRow(_ order: HospOrder, _ row: HospSheetRow) -> some View {
        let stopped = order.isStopped
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(HospWords.kind(order.kind).uppercased()).font(.brandText(10.4, weight: .heavy)).tracking(1.04).foregroundStyle(Theme.blue)
                    if stopped { Chip(text: L("Stopped"), tone: .muted) }
                }
                Text(order.name.nonEmpty ?? L("Order")).font(Theme.text(16, weight: .bold)).strikethrough(stopped).foregroundStyle(Theme.inkStrong).lineLimit(1)
                let line = [HospFmt.orderLine(order).nonEmpty, HospFmt.schedule(order, zone).nonEmpty].compactMap { $0 }.joined(separator: " · ")
                if !line.isEmpty { Text(line).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                if let instructions = order.instructions?.nonEmpty { Text(instructions).font(Theme.text(12)).italic().foregroundStyle(Theme.inkSoft).lineLimit(2) }
            }
            FlowLayout(spacing: 6) {
                ForEach(row.slots ?? []) { slot in
                    let state = slot.state ?? "upcoming"
                    HospSlotCell(
                        state: state,
                        time: HospFmt.clock(slot.scheduledFor, zone),
                        detail: slot.administration.flatMap { a in a.initials?.nonEmpty ?? (a.status == "given" ? HospFmt.clock(a.givenAt, zone) : nil) },
                        action: action(order, slot, state)
                    )
                }
                ForEach(row.extra ?? []) { entry in
                    HospExtraCell(time: HospFmt.clock(entry.givenAt, zone),
                                  word: entry.status != "given" ? L("Not given") : order.scheduleKind == "prn" ? L("Given") : L("Extra")) {
                        viewing = HospViewing(order: order, entry: entry)
                    }
                }
                if (row.slots ?? []).isEmpty && (row.extra ?? []).isEmpty {
                    Text(order.scheduleKind == "prn" ? L("Nothing given yet") : L("No doses this day")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        .frame(minHeight: 48)
                }
                if canCare && detail.isAdmitted && !stopped && isToday {
                    Button { ticking = HospTicking(order: order, slot: nil) } label: {
                        HStack(spacing: 4) {
                            Glyph("plus", size: 14)
                            Text(order.scheduleKind == "prn" ? L("Give now") : L("Extra dose"))
                        }
                        .font(Theme.text(12, weight: .bold))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(stopped ? 0.6 : 1)
    }

    private func action(_ order: HospOrder, _ slot: HospSheetSlot, _ state: String) -> (() -> Void)? {
        if let entry = slot.administration { return { viewing = HospViewing(order: order, entry: entry) } }
        guard canCare && detail.isAdmitted && (!order.isStopped || state == "missed") else { return nil }
        if state == "upcoming", let at = DateText.parse(slot.scheduledFor), at.timeIntervalSinceNow > 3600 { return nil }
        return { ticking = HospTicking(order: order, slot: slot) }
    }
}

// MARK: - Mark a dose

private struct HospTickSheet: View {
    @ObservedObject var model: HospDetailModel
    let detail: HospDetail
    let order: HospOrder
    let slot: HospSheetSlot?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var status: String? = "given"
    @State private var givenAt = Date()
    @State private var dose = ""
    @State private var unit = ""
    @State private var reason: String?
    @State private var initials = ""
    @State private var notes = ""
    @State private var withVitals = false
    @State private var vitals = HospVitalsDraft()
    @State private var invalidVital: HospVitalsDraft.Field?
    @State private var saving = false

    private var given: Bool { status != "not_given" }

    var body: some View {
        ProviderModal(
            title: order.name.nonEmpty ?? L("Dose"),
            subtitle: slot.map { LF("Scheduled %@", HospFmt.dateTime($0.scheduledFor, detail.zone)) } ?? (order.scheduleKind == "prn" ? L("As needed") : L("Off schedule")),
            systemImage: "syringe",
            accent: .lime,
            isDirty: !notes.isEmpty || !initials.isEmpty || reason != nil,
            form: form,
            primaryTitle: given ? L("Record as given") : L("Record as not given"),
            isWorking: saving,
            primaryIcon: "syringe",
            onPrimary: save
        ) {
            Text([HospFmt.orderLine(order).nonEmpty, HospFmt.schedule(order, detail.zone).nonEmpty, order.instructions?.nonEmpty].compactMap { $0 }.joined(separator: "\n"))
                .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(Theme.aqua, 16), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            PillPicker(options: [("given", L("Given")), ("not_given", L("Not given"))], choice: $status)
                .accessibilityLabel(L("Given or not"))
            if !given {
                // Web: the "Why *" part, its choice under the title.
                ModalSection(title: L("Why"), required: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        PillPicker(options: HospWords.reasons.map { ($0, HospWords.notGiven($0)) }, choice: Binding(get: { reason }, set: { reason = $0; form.clear("reason") }))
                            .accessibilityLabel(L("Why"))
                        if let error = form.error("reason") { Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
                    }
                    .id("reason")
                }
            }
            DateTimeField(label: given ? L("Given at") : L("When"), date: $givenAt, zone: detail.zone, max: Date(), key: "givenAt", form: form)
            if given {
                HStack(alignment: .top, spacing: 12) {
                    PMTextField(L("Dose"), text: $dose, key: "dose", form: form, keyboard: .decimalPad, number: .plain)
                    PMTextField(L("Unit"), text: $unit, prompt: "mg, ml, tab")
                }
            }
            PMTextField(L("Initials"), text: $initials, prompt: L("Yours by default"), capitalization: .characters)
                .onChange(of: initials) { _, value in
                    let next = String(value.uppercased().prefix(6))
                    if next != value { initials = next }
                }
            PMTextField(L("Note"), text: $notes, prompt: given ? L("e.g. Took it with food") : L("e.g. Vomited an hour before; try again at the next dose"), multiline: true)
            if let item = order.catalogItem, order.chargeable == true, given {
                HospHint(text: LF("Goes on the bill (%d × %@) and leaves the shelf.", order.chargeQuantity ?? 1, item.name ?? ""))
            }
            // Web: a box that opens on "Add vitals ⌄", the fields under a hairline.
            VStack(spacing: 0) {
                Button { withAnimation(.easeOut(duration: 0.18)) { withVitals.toggle() } } label: {
                    HStack {
                        Text(L("Add vitals")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        Spacer()
                        Glyph("chevron-down", size: 16).foregroundStyle(Theme.inkSoft).rotationEffect(.degrees(withVitals ? 180 : 0))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(withVitals ? .isSelected : [])
                if withVitals {
                    RowDivider()
                    HospVitalsFields(draft: $vitals, invalid: invalidVital)
                        .onChange(of: vitals) { _, _ in invalidVital = nil }
                        .padding(16)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        }
        .onAppear {
            dose = order.doseAmount.map { HospFmt.number($0) } ?? ""
            unit = order.doseUnit ?? ""
        }
    }

    private func save() {
        let amount = HospFmt.read(dose)
        guard form.check([
            ("reason", !given && reason == nil ? L("Say why it wasn’t given.") : nil),
            ("givenAt", givenAt.timeIntervalSinceNow > 60 ? L("That time is in the future.") : nil),
            ("dose", given && amount.map { $0.isNaN || $0 <= 0 } == true ? L("Enter a dose greater than zero.") : nil),
        ]) else { return }
        var vitalsBody: [String: Any]? = nil
        if withVitals {
            switch vitals.parsed() {
            case .failure(let problem):
                invalidVital = problem.field
                Toast.error(LF("Check %@.", HospVitalsDraft.label(problem.field)))
                return
            case .success(let value): vitalsBody = value
            }
        }
        saving = true
        Task {
            defer { saving = false }
            do {
                try await model.write("/administrations", body: [
                    "orderId": order.id,
                    "scheduledFor": slot?.scheduledFor,
                    "status": given ? "given" : "not_given",
                    "givenAt": DateText.iso(givenAt),
                    "doseAmount": given ? amount : nil,
                    "doseUnit": given ? unit.nonEmpty : nil,
                    "notGivenReason": given ? nil : reason,
                    "initials": initials.nonEmpty,
                    "notes": notes.nonEmpty,
                    "vitals": vitalsBody,
                ])
                let name = order.name.nonEmpty ?? L("Dose")
                Toast.show(given ? LF("%@ ticked as given.", name) : LF("%@ marked as not given.", name))
                dismiss()
            } catch {
                Toast.error(hospError(error, fallback: "Could not record it."))
            }
        }
    }
}

// MARK: - A marked dose

private struct HospTickViewSheet: View {
    @ObservedObject var model: HospDetailModel
    let detail: HospDetail
    let order: HospOrder
    let entry: HospAdministration
    let canCare: Bool
    let canManage: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var striking = false

    private var canStrike: Bool { canCare && detail.isAdmitted && entry.voidedAt == nil }

    var body: some View {
        ProviderModal(
            title: order.name.nonEmpty ?? L("Dose"),
            subtitle: entry.scheduledFor.map { LF("Scheduled %@", HospFmt.dateTime($0, detail.zone)) } ?? (order.scheduleKind == "prn" ? L("As needed") : L("Off schedule")),
            systemImage: "syringe",
            accent: .lime,
            cancelTitle: L("Close"),
            // Web: Close, and "Strike out" written in red beside it.
            secondaryActions: canStrike ? [ModalAction(L("Strike out"), icon: "undo-2", tint: Theme.destructive) { striking = true }] : []
        ) {
            FactRow(label: L("Status"), value: entry.status == "given" ? L("Given") : "\(L("Not given")) · \(HospWords.notGiven(entry.notGivenReason))")
            FactRow(label: L("At"), value: HospFmt.dateTime(entry.givenAt, detail.zone))
            FactRow(label: L("Dose"), value: HospFmt.dose(entry.doseAmount, entry.doseUnit).nonEmpty ?? "—")
            FactRow(label: L("By"), value: [entry.givenByName, entry.initials.map { "(\($0))" }].compactMap { $0?.nonEmpty }.joined(separator: " ").nonEmpty ?? "—")
            if let notes = entry.notes?.nonEmpty { FactRow(label: L("Note"), value: notes) }
            if !canManage { HospHint(text: L("Only the person who ticked it, or a vet, can strike it out.")) }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $striking) {
            ConfirmSheet(
                title: L("Strike this tick out?"),
                message: L("It stays on record, crossed out with your reason. Its charge comes off the open bill and the stock goes back."),
                confirmTitle: L("Strike out"),
                destructive: true,
                askReason: true,
                reasonRequired: true,
                cancelTitle: L("Keep it")
            ) { reason in
                do {
                    try await model.write("/administrations/\(entry.id)/void", body: ["reason": reason ?? ""])
                    Toast.show(L("Struck out."))
                    dismiss()
                } catch { throw hospRefusal(error, fallback: "Could not strike it out.") }
            }
        }
    }
}

/// A dose off schedule on the sheet (web: the dashed blue cell).
private struct HospExtraCell: View {
    let time: String
    let word: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(time).font(.brandHeading(14, relativeTo: .subheadline)).foregroundStyle(Theme.inkStrong)
                Text(word.uppercased()).font(.brandText(9.9, weight: .heavy)).foregroundStyle(Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 68, minHeight: 48)
            .background(Theme.wash(Theme.blue, 16), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.blue, style: StrokeStyle(lineWidth: 2, dash: [4, 3])))
        }
        .buttonStyle(.plain)
    }
}
