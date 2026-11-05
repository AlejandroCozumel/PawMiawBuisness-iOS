//
//  HospitalBits.swift
//  PawMiawNegocios
//
//  The hospital's small shared pieces (web hospital-bits.tsx, vitals-fields.tsx):
//  the triage, condition and status chips, the attention chips, a dose cell
//  on the sheet and its legend, the quick vitals fields, the pill choices and
//  the date fields its sheets use. Built on the Design pieces.
//

import SwiftUI

// MARK: - Chips

enum HospTone {
    /// --triage-critical / urgent / stable, on the provider status scale.
    static func triage(_ priority: String?) -> Color {
        switch priority {
        case "critical": ProviderState.problem.color
        case "urgent": ProviderState.waiting.color
        default: ProviderState.done.color
        }
    }

    /// conditionColor (lib/hospital.ts).
    static func condition(_ condition: String?) -> Color {
        switch condition {
        case "improving": Theme.blue
        case "stable": Theme.aqua
        case "guarded": Theme.mango
        default: Theme.destructive
        }
    }

    /// STATUS_TONE: the hospitalization's state colour.
    static func status(_ status: String?) -> Color { ProviderState.hospital(status).color }
}

struct HospTriageBadge: View {
    let priority: String
    var body: some View {
        Chip(text: HospWords.triage(priority), tone: .custom(HospTone.triage(priority)), icon: "siren", percent: priority == "critical" ? 14 : 22, ink: priority == "critical" ? Theme.destructive : Theme.inkStrong, ring: true)
    }
}

struct HospConditionBadge: View {
    let condition: String
    var body: some View { Chip(text: HospWords.condition(condition), tone: .custom(HospTone.condition(condition)), dot: HospTone.condition(condition), percent: 24) }
}

struct HospStatusChip: View {
    let status: String?
    var body: some View { Chip(text: HospWords.status(status), tone: .custom(HospTone.status(status)), dot: HospTone.status(status), percent: 22) }
}

struct HospAllergyChip: View {
    let allergies: [String]
    var body: some View {
        if !allergies.isEmpty {
            Chip(text: LF("Allergy: %@", allergies.joined(separator: ", ")), tone: .danger, icon: "triangle-alert")
        }
    }
}

/// Due / late / missed counts as small chips (nothing when all are zero).
struct HospAttentionChips: View {
    let attention: HospAttention?
    var body: some View {
        let a = attention
        if let a, a.m > 0 { Chip(text: LP(a.m, "1 missed", "%d missed"), tone: .danger, icon: "triangle-alert") }
        if let a, a.l > 0 { Chip(text: LP(a.l, "1 late", "%d late"), tone: .warn, icon: "clock-3") }
        if let a, a.d > 0 { Chip(text: LP(a.d, "1 due", "%d due"), tone: .info, icon: "syringe") }
    }
}

/// Rounds signed today (green) or still to sign (muted).
struct HospRoundsChip: View {
    let signed: Bool
    var body: some View {
        if signed {
            Chip(text: L("Rounds signed"), tone: .custom(ProviderState.done.color), icon: "shield-check", percent: 18)
        } else {
            Chip(text: L("Rounds to sign"), tone: .muted, icon: "shield-question-mark")
        }
    }
}

// MARK: - The sheet's cells

/// A dose on the sheet: its time and where it stands (ProviderState.slot).
struct HospSlotCell: View {
    let state: String
    let time: String
    var detail: String? = nil
    var dashed: Bool = false
    var action: (() -> Void)? = nil

    private var tone: ProviderState { ProviderState.slot(state) }
    private var done: Bool { state == "given" || state == "given_late" }
    private var background: AnyShapeStyle {
        switch state {
        case "upcoming": AnyShapeStyle(Theme.surface)
        case "given", "given_late": AnyShapeStyle(tone.color)
        case "due": AnyShapeStyle(Theme.wash(tone.color, 38))
        case "late": AnyShapeStyle(Theme.wash(tone.color, 40))
        case "missed": AnyShapeStyle(Theme.wash(tone.color, 18))
        default: AnyShapeStyle(Theme.wash(tone.color, 16))
        }
    }
    private var border: Color {
        switch state {
        case "upcoming": Theme.borderSoft
        case "given_late": ProviderState.waiting.color
        default: tone.color
        }
    }

    var body: some View {
        Button { action?() } label: {
            VStack(spacing: 2) {
                Text(time)
                    .font(.brandHeading(14, relativeTo: .subheadline))
                    .strikethrough(state == "not_given")
                    .foregroundStyle(done ? tone.ink : Theme.inkStrong)
                Text((detail ?? HospWords.slot(state)).uppercased())
                    .font(.brandText(9.9, weight: .heavy))
                    .tracking(9.9 * 0.06)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(done ? tone.ink : (state == "missed" ? Theme.destructive : Theme.inkSoft))
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 68, minHeight: 48)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                    .stroke(border, style: StrokeStyle(lineWidth: state == "given_late" ? 3 : 2, dash: dashed ? [4, 3] : []))
            )
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityLabel("\(time) · \(HospWords.slot(state))")
    }
}

/// The legend under the sheet.
struct HospSlotLegend: View {
    var body: some View {
        FlowLayout(spacing: 12) {
            ForEach(HospWords.slotStates, id: \.self) { state in
                HStack(spacing: 6) {
                    let tone = ProviderState.slot(state)
                    RoundedRectangle(cornerRadius: Theme.tickRadius, style: .continuous)
                        .fill(state == "upcoming" ? AnyShapeStyle(Theme.surface) : (state == "given" || state == "given_late" ? AnyShapeStyle(tone.color) : AnyShapeStyle(Theme.wash(tone.color, 30))))
                        .overlay(RoundedRectangle(cornerRadius: Theme.tickRadius, style: .continuous).strokeBorder(state == "upcoming" ? Theme.borderSoft : (state == "given_late" ? ProviderState.waiting.color : tone.color), lineWidth: 2))
                        .frame(width: 14, height: 14)
                    Text(HospWords.slot(state)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }
}

// MARK: - Vitals fields

/// Quick vitals: temperature, heart and breathing rate, pain, weight, capillary refill and gums.
struct HospVitalsFields: View {
    @Binding var draft: HospVitalsDraft
    var invalid: HospVitalsDraft.Field? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], alignment: .leading, spacing: 12) {
                field(.temperatureC, $draft.temperatureC, "38.5", .decimalPad)
                field(.heartRate, $draft.heartRate, "110", .numberPad)
                field(.respiratoryRate, $draft.respiratoryRate, "24", .numberPad)
                field(.painScore, $draft.painScore, "0–10", .numberPad)
                field(.weightKg, $draft.weightKg, "12.4", .decimalPad)
                field(.crtSeconds, $draft.crtSeconds, "< 2", .decimalPad)
            }
            FormField(label: L("Gums")) {
                PillPicker(
                    options: HospWords.mucousOptions.map { ($0, HospWords.mucous($0)) },
                    choice: Binding(get: { draft.mucousMembranes.nonEmpty }, set: { draft.mucousMembranes = $0 ?? "" }),
                    allowsNone: true
                )
            }
        }
    }

    private func field(_ key: HospVitalsDraft.Field, _ text: Binding<String>, _ prompt: String, _ keyboard: UIKeyboardType) -> some View {
        FormField(label: HospVitalsDraft.label(key)) {
            TextField(prompt, text: text)
                .keyboardType(keyboard)
                .fieldChrome(invalid: invalid == key)
        }
    }
}

// MARK: - Small helpers

/// A line of quiet text (a hint under a group).
struct HospHint: View {
    let text: String
    var body: some View { Text(text).font(Theme.text(13)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true) }
}

/// A group's heading on the board (web `SectionTitle`): a 28 disc of the
/// tone at 22% with the icon, the words in 14 extrabold, how many in a pill.
struct HospGroupTitle: View {
    let title: String
    var systemImage: String? = nil
    var count: Int? = nil
    var tone: Color = Theme.blue

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Glyph(systemImage, size: 16)
                    .foregroundStyle(Theme.inkStrong)
                    .frame(width: 28, height: 28)
                    .background(Theme.wash(tone, 22), in: Circle())
            }
            Text(title).font(Theme.text(14, weight: .heavy)).foregroundStyle(Theme.inkStrong)
            if let count {
                Text("\(count)").font(Theme.text(12, weight: .heavy)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.surfaceMuted, in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }
}

/// A titled group inside a settings card (web hospital-admin `GroupTitle`):
/// a 16 blue icon, the title in Fredoka 18, an optional hint and aside.
struct HospCardGroup<Aside: View>: View {
    let title: String
    let icon: String
    var hint: String? = nil
    @ViewBuilder var aside: () -> Aside

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Glyph(icon, size: 16).foregroundStyle(Theme.blue)
                Text(title).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                Spacer(minLength: 8)
                aside()
            }
            if let hint { Text(hint).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
        }
    }
}

extension HospCardGroup where Aside == EmptyView {
    init(title: String, icon: String, hint: String? = nil) {
        self.init(title: title, icon: icon, hint: hint, aside: { EmptyView() })
    }
}

/// The hospital's 60-second refresh while a ward screen is open (doses fall due).
struct HospEveryMinute: ViewModifier {
    let action: () async -> Void

    func body(content: Content) -> some View {
        content.task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await action()
            }
        }
    }
}

/// One more pill after a sheet's client and pet (web `MedicalPill tone="soft"` inside
/// `ModalContextPills`): the triage, the place, the vet, an order.
func hospContextPill(_ text: String, icon: String) -> some View {
    Chip(text: text, tone: .muted, icon: icon, weight: .semibold, size: .large)
}

// MARK: - Catalog search

/// The Catalog searched inside a sheet (an order, a medicine to take home), by the one search
/// rule: the server searches 250 ms after typing stops, from 2 characters, 20 at a time as the
/// list scrolls, with the server's count. A pick clears the search.
struct HospCatalogSearch: View {
    let prompt: String
    var itemType: String? = nil
    var showsPrice: Bool = true
    /// Said when nothing matches (nil: nothing is said).
    var emptyText: String? = nil
    let onPick: (HospCatalogItem) -> Void

    @State private var text = ""
    @State private var found: [HospCatalogItem] = []
    @State private var total: Int?
    @State private var hasMore = false
    @State private var loading = false
    @State private var asked: String?

    private var query: String? { ClientSearch.query(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SearchField(prompt: prompt, text: $text, shape: .field)
            if let query {
                if asked != query || (loading && found.isEmpty) {
                    ProgressView().tint(Theme.blue).frame(maxWidth: .infinity).padding(.vertical, 6)
                } else if found.isEmpty {
                    if let emptyText { HospHint(text: emptyText) }
                } else {
                    let count = total ?? found.count
                    Text((count == 1 ? LF("%@ result", "1") : LF("%@ results", String(count))).uppercased())
                        .font(Theme.text(12)).tracking(1.4).foregroundStyle(Theme.inkSoft)
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(found) { item in row(item) }
                            LoadMoreRow(hasMore: hasMore, busy: loading) { Task { await load(reset: false) } }
                        }
                    }
                    .frame(maxHeight: 260)
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .debounced(text) { _ in await load(reset: true) }
    }

    private func row(_ item: HospCatalogItem) -> some View {
        Button {
            onPick(item)
            text = ""
        } label: {
            HStack(spacing: 12) {
                Text(item.name).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(2)
                Spacer(minLength: 8)
                if showsPrice {
                    Text((item.defaultUnitAmount ?? 0) > 0 ? Money.format(item.defaultUnitAmount, currency: item.currency) : L("No price"))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func load(reset: Bool) async {
        guard let query else {
            found = []
            total = nil
            hasMore = false
            asked = nil
            return
        }
        loading = true
        defer { loading = false }
        let offset = reset ? 0 : found.count
        let page = try? await HospAPI.catalogPage(search: query, itemType: itemType, offset: offset)
        // A slower answer for an older search never replaces a newer one.
        guard query == self.query else { return }
        let items = page?.items ?? []
        found = reset ? items : found + items.filter { item in !found.contains { $0.id == item.id } }
        total = page?.total
        hasMore = page?.hasMore ?? (items.count == ClientSearch.pageSize)
        asked = query
    }
}
