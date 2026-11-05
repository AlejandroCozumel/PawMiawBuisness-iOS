//
//  Components.swift
//  PawMiawNegocios
//
//  The shared pieces every business screen is built from. One component per
//  control, one look: a screen never draws its own card, chip or empty state.
//

import SwiftUI

// MARK: - Page

/// A page's scrolling column: the provider canvas, a readable width on iPad,
/// pull to refresh.
struct PageScroll<Content: View>: View {
    var spacing: CGFloat = 20
    var maxWidth: CGFloat = 820
    var refresh: (() async -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content() }
                .frame(maxWidth: maxWidth, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas.ignoresSafeArea())
        .refreshable { await refresh?() }
    }
}

// MARK: - Card

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    /// An attention card (web: "Por cobrar" coral, "Quedaron abiertas" mango): a wash of the tone and its border.
    var tint: Color? = nil
    var spacing: CGFloat = 12
    /// No shadow (a card inside a card, a sheet's box; web `rounded-card border` without `shadow-card`).
    var flat: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.map { AnyShapeStyle(Theme.wash($0, 14)) } ?? AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(tint?.opacity(0.75) ?? Theme.borderSoft, lineWidth: tint == nil ? 1 : 2))
            .modifier(CardShadowUnlessFlat(flat: flat))
    }
}

private struct CardShadowUnlessFlat: ViewModifier {
    let flat: Bool
    func body(content: Content) -> some View {
        if flat { content } else { content.cardShadow() }
    }
}

/// A titled group of a page: the title, an optional count or action, then its card(s).
struct PageSection<Content: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                    if let subtitle { Text(subtitle).font(Theme.text(13)).foregroundStyle(Theme.inkSoft) }
                }
                Spacer(minLength: 8)
                trailing()
            }
            content()
        }
    }
}

extension PageSection where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
        self.content = content
    }
}

/// A row inside a card: leading view, title + lines, trailing view, chevron when it opens something.
struct ListRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var detail: String? = nil
    var showsChevron: Bool = false
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leading()
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.rowTitleFont).foregroundStyle(Theme.inkStrong).lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(Theme.smallFont).foregroundStyle(Theme.inkSoft).lineLimit(2)
                }
                if let detail, !detail.isEmpty {
                    Text(detail).font(Theme.captionFont).foregroundStyle(Theme.inkSoft).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            trailing()
            if showsChevron {
                Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

extension ListRow where Leading == EmptyView, Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, detail: String? = nil, showsChevron: Bool = false) {
        self.init(title: title, subtitle: subtitle, detail: detail, showsChevron: showsChevron, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

/// A dashed divider: the provider modal's "stitched" rule (2 pt), or a 1 pt `border-dashed`
/// hairline (a tinted head's foot) with `lineWidth: 1`.
struct StitchedDivider: View {
    var lineWidth: CGFloat = 2
    var color: Color = Theme.borderSoft

    var body: some View {
        Line()
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, dash: lineWidth < 2 ? [4, 3] : [6, 5]))
            .frame(height: lineWidth)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

/// "Label: value" in a fact list.
struct FactRow: View {
    let label: String
    let value: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
            Spacer(minLength: 8)
            Text(value?.nonEmpty ?? "—").font(Theme.text(15, weight: .semibold)).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Chips

/// A status (web `ProviderStatusChip`): uppercase, tracked, a 2 pt edge. One of the six
/// states (fill = edge = the state's colour, its ink), or a brand tone (lime, mango, aqua,
/// pink: the brand fill with a 2 pt PAW Blue edge and navy ink — a client "ARCHIVADO").
struct StatusChip: View {
    let text: String
    var state: ProviderState = .closed
    /// Drawn outlined and dashed: not a visit yet (a requested booking).
    var outlined: Bool = false
    /// A brand fill instead of a state (`tone="lime"` on the web).
    var brand: Color? = nil
    /// The small size of a row (9.9 pt, as a tag).
    var small: Bool = false

    init(text: String, state: ProviderState, outlined: Bool = false, small: Bool = false) {
        self.text = text
        self.state = state
        self.outlined = outlined
        self.small = small
    }

    init(text: String, brand: Color, small: Bool = false) {
        self.text = text
        self.brand = brand
        self.small = small
    }

    var body: some View {
        Text(text.uppercased())
            .font(.brandText(small ? 9.9 : 11.5, weight: .bold))
            .tracking(small ? 1.2 : 1.4)
            .lineLimit(1)
            .padding(.horizontal, small ? 8 : 12)
            .padding(.vertical, small ? 1 : 4)
            .foregroundStyle(brand != nil ? Theme.inkOnBright : outlined ? Theme.inkStrong : state.ink)
            .background(fill, in: Capsule())
            .overlay {
                if let brand {
                    Capsule().strokeBorder(brand == Theme.blue ? Theme.lime : Theme.blueFixed, lineWidth: 2)
                } else if outlined {
                    Capsule().strokeBorder(state.color, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                } else {
                    Capsule().strokeBorder(state.color, lineWidth: 2)
                }
            }
    }

    private var fill: AnyShapeStyle {
        if let brand { return AnyShapeStyle(brand) }
        return outlined ? AnyShapeStyle(state.wash) : AnyShapeStyle(state.color)
    }
}

/// A category (a service, a room, a role): a hue, never a status colour. The icon is the
/// web's Lucide one (an SF name maps to it).
struct HueChip: View {
    let text: String
    var hue: Hue = .grey
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Glyph(systemImage, size: 12) }
            Text(text).lineLimit(1)
        }
        .font(.brandText(12, weight: .bold))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .foregroundStyle(hue.ink)
        .background(hue.color.opacity(0.22), in: Capsule())
    }
}

/// The one small pill of a row, in any tone (web visit-row `Chip`, `HubChip`, agenda-list
/// `Pill`, inventory `TonePill`, record `StatusPill`/`RecordTypeChip`, hospital `PILL`,
/// grooming `StagePill`, `RxChip`, `StatusTag`, home-visit `StatePill`, `RoleChip`): a capsule,
/// the tone's wash, navy words. The fixed tones are §9.3's; `.custom` takes any colour at
/// `percent` (24 unless told). A 6 dot, an icon, a count, a 1 pt edge, a dashed "pending"
/// edge, or the triage ring may join it. Sizes: `.small` 11.2 (a row's chip), `.medium` 12
/// at 24 tall (a tag beside a title), `.large` 12.8 at 28 (a state pill), `.wide` 14 at 28,
/// `.header` 14 at 36 (a state shown among a module header's actions: the Store's register).
struct Chip: View {
    enum Tone: Equatable {
        case muted, danger, warn, good, info, online
        /// Any colour (a status, a hue, a stage) washed at `percent`.
        case custom(Color)
    }
    enum Size { case small, medium, large, wide, header }

    let text: String
    var tone: Tone = .muted
    var icon: String? = nil
    /// Dashed and unfilled: waiting for an answer (a requested booking).
    var pending: Bool = false
    /// A 6 pt dot before the words.
    var dot: Color? = nil
    /// A number after the words.
    var count: Int? = nil
    /// The wash of a custom tone (100 = the solid colour).
    var percent: Double? = nil
    /// The words' ink (navy unless the tone says otherwise).
    var ink: Color? = nil
    /// The icon's ink and size when it wears the tone (a record's kind).
    var iconInk: AnyShapeStyle? = nil
    var iconSize: CGFloat? = nil
    var weight: Font.Weight = .bold
    /// A 1 pt edge of the tone at this percent over the border colour.
    var border: Double? = nil
    /// No fill, a 1 pt grey outline (an email that is only a link).
    var outlined: Bool = false
    /// The triage badge: a 1 pt ring of the tone, extrabold uppercase, tracked.
    var ring: Bool = false
    var size: Size = .small

    init(text: String, tone: Tone = .muted, icon: String? = nil, pending: Bool = false, dot: Color? = nil, count: Int? = nil, percent: Double? = nil, ink: Color? = nil, iconInk: AnyShapeStyle? = nil, iconSize: CGFloat? = nil, weight: Font.Weight = .bold, border: Double? = nil, outlined: Bool = false, ring: Bool = false, size: Size = .small) {
        self.text = text
        self.tone = tone
        self.icon = icon
        self.pending = pending
        self.dot = dot
        self.count = count
        self.percent = percent
        self.ink = ink
        self.iconInk = iconInk
        self.iconSize = iconSize
        self.weight = weight
        self.border = border
        self.outlined = outlined
        self.ring = ring
        self.size = size
    }

    /// A chip of a status or hue colour (`.custom(color)`).
    init(_ text: String, color: Color, percent: Double = 24, icon: String? = nil, dot: Bool = false, size: Size = .small) {
        self.init(text: text, tone: .custom(color), icon: icon, dot: dot ? color : nil, percent: percent, size: size)
    }

    private var fontSize: CGFloat {
        switch size {
        case .small: 11.2
        case .medium: 12
        case .large: 12.8
        case .wide, .header: 14
        }
    }

    var body: some View {
        HStack(spacing: size == .small ? 4 : size == .header ? 8 : 6) {
            if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
            if let icon {
                Glyph(icon, size: iconSize ?? (size == .small ? 12 : size == .header ? 16 : 14))
                    .modifier(ChipIconInk(color: iconInk))
            }
            Text(ring ? text.uppercased() : text).lineLimit(1)
            if let count { Text("\(count)").monospacedDigit() }
        }
        .font(.brandText(fontSize, weight: ring ? .heavy : weight))
        .tracking(ring ? fontSize * 0.08 : 0)
        .foregroundStyle(ink ?? defaultInk)
        .padding(.horizontal, size == .small ? 8 : size == .wide ? 12 : size == .header ? 14 : 10)
        .padding(.vertical, size == .small ? 2 : 0)
        .frame(minHeight: size == .medium ? 24 : size == .small ? nil : size == .header ? 36 : 28)
        .background(pending || outlined ? AnyShapeStyle(Color.clear) : fill, in: Capsule())
        .overlay {
            if pending {
                Capsule().strokeBorder(ProviderState.waiting.color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            } else if outlined {
                Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1)
            } else if ring {
                Capsule().strokeBorder(color, lineWidth: 1)
            } else if let border {
                Capsule().strokeBorder(Theme.mix(color, border, with: Theme.borderSoft), lineWidth: size == .large || size == .header ? 1.5 : 1)
            }
        }
    }

    /// The tone's own colour (its dot, edge and ring).
    private var color: Color {
        switch tone {
        case .muted: Theme.inkSoft
        case .danger: Theme.destructive
        case .warn: Theme.mango
        case .good: Theme.lime
        case .info: Theme.aqua
        case .online: Theme.lavender
        case .custom(let color): color
        }
    }

    private var fill: AnyShapeStyle {
        switch tone {
        case .muted: AnyShapeStyle(Theme.surfaceMuted)
        case .danger: AnyShapeStyle(Theme.wash(Theme.destructive, 12))
        case .warn: AnyShapeStyle(Theme.wash(Theme.mango, 25))
        case .good: AnyShapeStyle(Theme.wash(Theme.lime, 30))
        case .info: AnyShapeStyle(Theme.wash(Theme.aqua, 22))
        case .online: AnyShapeStyle(Theme.wash(Theme.lavender, 30))
        case .custom(let color):
            (percent ?? 24) >= 100 ? AnyShapeStyle(color) : AnyShapeStyle(Theme.wash(color, percent ?? 24))
        }
    }

    private var defaultInk: Color {
        switch tone {
        case .muted: Theme.inkSoft
        case .danger: Theme.destructive
        case .custom: (percent ?? 24) >= 100 ? Theme.inkOnBright : Theme.inkStrong
        default: Theme.inkStrong
        }
    }
}

private struct ChipIconInk: ViewModifier {
    let color: AnyShapeStyle?
    func body(content: Content) -> some View {
        if let color { content.foregroundStyle(color) } else { content }
    }
}

/// An outlined tag on a row (web `ProviderClientLinkBadge`, `ClientStatusPill`): uppercase,
/// tracked. "SOLO EN LA CLÍNICA" is grey and empty, "FAMILIA VINCULADA" blue; with a `tone`
/// it is a status pill ("PROSPECTO" lavender, "ARCHIVADO" grey: the tone at 24% with a 70%
/// edge). Sizes: `.xs` 9.9 (a row), `.sm` 10.9, `.header` 12 at 32 tall (a sheet's context).
struct TagChip: View {
    enum Size { case xs, sm, header }
    let text: String
    var icon: String? = nil
    var linked: Bool = false
    /// A status pill's colour (lavender for a lead, the border colour for the rest).
    var tone: Color? = nil
    var size: Size = .xs

    var body: some View {
        HStack(spacing: tone == nil ? 6 : 4) {
            if let icon { Glyph(icon, size: size == .xs ? 12 : 14) }
            Text(text.uppercased()).lineLimit(1)
        }
        .font(.brandText(fontSize, weight: linked || tone != nil ? .bold : .semibold))
        .tracking(fontSize * 0.12)
        .foregroundStyle(tone != nil ? Theme.inkStrong : linked ? Theme.blueStrong : Theme.inkSoft)
        .padding(.horizontal, size == .xs ? 8 : size == .sm ? 10 : 12)
        .padding(.vertical, size == .xs ? 2 : size == .sm ? 4 : 0)
        .frame(minHeight: size == .header ? 32 : nil)
        .background(fill, in: Capsule())
        .overlay(Capsule().strokeBorder(edge, lineWidth: 1))
    }

    private var fontSize: CGFloat {
        switch size {
        case .xs: 9.9
        case .sm: 10.9
        case .header: 12
        }
    }

    private var fill: AnyShapeStyle {
        if let tone { return AnyShapeStyle(Theme.wash(tone, 24)) }
        return linked ? AnyShapeStyle(Theme.wash(Theme.blue, 12)) : AnyShapeStyle(Color.clear)
    }

    private var edge: AnyShapeStyle {
        if let tone { return AnyShapeStyle(Theme.mix(tone, 70, with: Theme.borderSoft)) }
        return linked ? AnyShapeStyle(Theme.mix(Theme.blue, 55, with: Theme.borderSoft)) : AnyShapeStyle(Theme.borderSoft)
    }
}

/// A count badge (a sidebar number, a tab's waiting work).
struct CountBadge: View {
    let count: Int
    var color: Color = Theme.destructive
    /// The bell caps at "9+", the sidebar at "99+".
    var cap: Int = 99
    var body: some View {
        if count > 0 {
            Text(count > cap ? "\(cap)+" : "\(count)")
                .font(.brandText(10.9, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(color, in: Capsule())
        }
    }
}

/// A filter in a row of filters (web `FilterChip`, the wash chip): 36 tall,
/// 1.5 pt border, 14 bold. Off: white, grey border, grey text. On: the chip's
/// colour at 26% with a deeper border of it and navy text. A dot, an icon or a
/// face may lead; a count (12 extrabold, grey) may follow. `solid` is the
/// notification feed's filter (a 2 pt edge, solid PAW Blue when on). With `onRemove`
/// it is the chip of a choice made elsewhere ("Luna · Carmen ✕"), always on.
struct FilterChip: View {
    let title: String
    var count: Int? = nil
    let isSelected: Bool
    var tone: Color = Theme.blue
    var dot: Color? = nil
    var icon: String? = nil
    var solid: Bool = false
    var face: AnyView? = nil
    var onRemove: (() -> Void)? = nil
    var removeLabel: String = L("Remove")
    let action: () -> Void

    init(title: String, count: Int? = nil, isSelected: Bool, tone: Color = Theme.blue, dot: Color? = nil, icon: String? = nil, solid: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.count = count
        self.isSelected = isSelected
        self.tone = tone
        self.dot = dot
        self.icon = icon
        self.solid = solid
        self.action = action
    }

    /// The chip of a choice made elsewhere: a face, the words and a ✕ that undoes it.
    init(title: String, face: AnyView? = nil, removeLabel: String, onRemove: @escaping () -> Void) {
        self.title = title
        self.isSelected = true
        self.face = face
        self.removeLabel = removeLabel
        self.onRemove = onRemove
        self.action = {}
    }

    var body: some View {
        if let onRemove {
            HStack(spacing: 6) {
                if let face { face.frame(width: 28, height: 28).clipShape(Circle()) }
                Text(title).lineLimit(1)
                Button(action: onRemove) {
                    Glyph("x", size: 14).frame(width: 28, height: 28).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(removeLabel)
            }
            .font(.brandText(14, weight: .bold))
            .foregroundStyle(Theme.inkStrong)
            .padding(.leading, face == nil ? 12 : 4)
            .padding(.trailing, 4)
            .frame(height: 36)
            .background(Theme.wash(tone, 26), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.mix(tone, 75, with: Theme.inkStrong), lineWidth: 1.5))
            .accessibilityElement(children: .contain)
        } else {
            Button(action: action) {
                HStack(spacing: 6) {
                    if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                    if let icon { Glyph(icon, size: 14).foregroundStyle(solid ? AnyShapeStyle(.foreground) : AnyShapeStyle(Theme.mix(tone, 70, with: Theme.inkStrong))) }
                    Text(title).lineLimit(1)
                    if let count { countView(count) }
                }
                .font(.brandText(14, weight: .bold))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .foregroundStyle(ink)
                .background(fill, in: Capsule())
                .overlay(Capsule().strokeBorder(edge, lineWidth: solid ? 2 : 1.5))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    @ViewBuilder
    private func countView(_ count: Int) -> some View {
        if solid {
            Text("\(count)")
                .font(.brandText(12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Theme.onBlue : Theme.inkStrong)
                .padding(.horizontal, 6)
                .background(isSelected ? Theme.onBlue.opacity(0.2) : Theme.inkSoft.opacity(0.12), in: Capsule())
        } else if count > 0 {
            Text(count > 99 ? "99+" : "\(count)").font(.brandText(12, weight: .heavy)).monospacedDigit().foregroundStyle(Theme.inkSoft)
        }
    }

    private var ink: Color {
        if solid { return isSelected ? Theme.onBlue : Theme.inkSoft }
        return isSelected ? Theme.inkStrong : Theme.inkSoft
    }

    private var fill: AnyShapeStyle {
        if solid { return isSelected ? AnyShapeStyle(Theme.blue) : AnyShapeStyle(Theme.surface) }
        return isSelected ? AnyShapeStyle(Theme.wash(tone, 26)) : AnyShapeStyle(Theme.surface)
    }

    private var edge: AnyShapeStyle {
        if solid { return isSelected ? AnyShapeStyle(Theme.blue) : AnyShapeStyle(Theme.borderSoft) }
        return isSelected ? AnyShapeStyle(Theme.mix(tone, 75, with: Theme.inkStrong)) : AnyShapeStyle(Theme.borderSoft)
    }
}

// MARK: - Toned chips (web catalog-bits.tsx, §5.3 B and C)

/// The icon of a toned tab or chip on its small round chip (web `TonedTabIcon`): quiet, the
/// tone's 24% wash with the deep shade (dark: the tone lightened); chosen, a white veil on
/// the fill. `dot` draws an 8 pt dot instead of an icon.
struct ToneIcon: View {
    let icon: String
    let tone: ChipTone
    let selected: Bool
    var size: CGFloat = 24
    var glyph: CGFloat = 14
    var dot: Bool = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if dot { Circle().frame(width: 8, height: 8) } else { Glyph(icon, size: glyph) }
        }
        .foregroundStyle(selected ? AnyShapeStyle(Color.white) : quiet)
        .frame(width: size, height: size)
        .background(selected ? AnyShapeStyle(Color.white.opacity(0.2)) : AnyShapeStyle(Theme.wash(tone.color, 24)), in: Circle())
    }

    private var quiet: AnyShapeStyle {
        scheme == .dark ? AnyShapeStyle(Theme.mix(tone.color, 70, with: Theme.inkStrong)) : AnyShapeStyle(tone.fill)
    }
}

/// The count on a toned chip or tab: white on the deep shade while quiet, the deep shade on
/// white while on (20 tall, 10.9 extrabold).
struct ToneCount: View {
    let count: Int
    let tone: ChipTone
    let selected: Bool

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.brandText(10.9, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(selected ? tone.fill : Color.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(selected ? Color.white : tone.fill, in: Capsule())
    }
}

/// A filter that is on or off in its own colour (web `CatalogFilterChip`, §5.3): 40 tall,
/// 1 pt edge, 14 bold. Toned (B): quiet it is white with only its icon chip tinted; on, the
/// tone's deep shade under white. Plain (C, `plain:`): on = the colour's edge, its 12% wash and
/// navy words, the count on the colour.
struct ToneChip: View {
    let title: String
    var icon: String? = nil
    var tone: ChipTone = .page
    var count: Int? = nil
    /// An 8 pt dot in the icon chip instead of an icon (the bills' status chips).
    var dot: Bool = false
    /// The plain chip's colour (C); nil = toned (B).
    var plain: Color? = nil
    /// The plain chip's leading dot (a payment method).
    var plainDot: Color? = nil
    /// The plain chip's count ink on a bright colour (mango, lime): navy instead of white.
    var countInk: Color = .white
    let isOn: Bool
    let action: () -> Void

    /// Toned (B).
    init(_ title: String, icon: String? = nil, tone: ChipTone = .page, count: Int? = nil, dot: Bool = false, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.icon = dot ? (icon ?? "circle") : icon
        self.tone = tone
        self.count = count
        self.dot = dot
        self.isOn = isOn
        self.action = action
    }

    /// Plain (C).
    init(_ title: String, icon: String? = nil, plain: Color, dot: Color? = nil, count: Int? = nil, countInk: Color = .white, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.plain = plain
        self.plainDot = dot
        self.count = count
        self.countInk = countInk
        self.isOn = isOn
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let plain { plainBody(plain) } else { tonedBody }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var tonedBody: some View {
        HStack(spacing: 6) {
            if let icon { ToneIcon(icon: icon, tone: tone, selected: isOn, dot: dot) }
            Text(title).lineLimit(1)
            if let count, count > 0 { ToneCount(count: count, tone: tone, selected: isOn) }
        }
        .font(.brandText(14, weight: .bold))
        .foregroundStyle(isOn ? Color.white : Theme.inkSoft)
        .padding(.leading, icon == nil ? 14 : 8)
        .padding(.trailing, 14)
        .frame(height: 40)
        .background(isOn ? AnyShapeStyle(tone.fill) : AnyShapeStyle(Theme.surface), in: Capsule())
        .overlay(Capsule().strokeBorder(isOn ? AnyShapeStyle(tone.fill) : AnyShapeStyle(Theme.borderSoft), lineWidth: 1))
        .shadow(color: isOn ? Theme.navy.opacity(0.1) : .clear, radius: 1.5, y: 1)
    }

    private func plainBody(_ color: Color) -> some View {
        HStack(spacing: 6) {
            if let plainDot { Circle().fill(plainDot).frame(width: 8, height: 8) }
            if let icon { Glyph(icon, size: 16) }
            Text(title).lineLimit(1)
            if let count, count > 0 {
                Text("\(count)").font(.brandText(10.9, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(countInk)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(color, in: Capsule())
            }
        }
        .font(.brandText(14, weight: .bold))
        .foregroundStyle(isOn ? Theme.inkStrong : Theme.inkSoft)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(isOn ? AnyShapeStyle(Theme.wash(color, 12)) : AnyShapeStyle(Theme.surface), in: Capsule())
        .overlay(Capsule().strokeBorder(isOn ? AnyShapeStyle(color) : AnyShapeStyle(Theme.borderSoft), lineWidth: 1))
    }
}

/// A menu that filters, drawn as a toned chip (web `CatalogMenuChip`): a `Menu`'s label.
struct ToneMenuLabel: View {
    let title: String
    var icon: String? = nil
    var tone: ChipTone = .page
    var isOn: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if let icon { ToneIcon(icon: icon, tone: tone, selected: isOn) }
            Text(title).lineLimit(1)
            Glyph("chevron-down", size: 14).opacity(0.8)
        }
        .font(.brandText(14, weight: .bold))
        .foregroundStyle(isOn ? Color.white : Theme.inkSoft)
        .padding(.leading, icon == nil ? 14 : 8)
        .padding(.trailing, 12)
        .frame(height: 40)
        .background(isOn ? AnyShapeStyle(tone.fill) : AnyShapeStyle(Theme.surface), in: Capsule())
        .overlay(Capsule().strokeBorder(isOn ? AnyShapeStyle(tone.fill) : AnyShapeStyle(Theme.borderSoft), lineWidth: 1))
    }
}

/// The 1 × 24 rule between a chip row's groups (web: before a select in a chip row).
struct ChipRule: View {
    var body: some View { Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 24).padding(.horizontal, 4) }
}

/// A filter that opens a menu (a person, a room, a location, a sort): a 36 pt
/// bold capsule with a chevron, used as a `Menu`'s label.
struct FilterMenuLabel: View {
    let title: String
    var selected: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title).lineLimit(1)
            Glyph("chevron-down", size: 16).foregroundStyle(Theme.inkSoft)
        }
        .font(.brandText(14, weight: .bold))
        .foregroundStyle(Theme.inkStrong)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: 36)
        .background(selected ? AnyShapeStyle(Theme.wash(Theme.blue, 12)) : AnyShapeStyle(Theme.surface), in: Capsule())
        .overlay(Capsule().strokeBorder(selected ? Theme.blue : Theme.borderSoft, lineWidth: 1))
    }
}

/// The status tabs of a board (web: "Todo 0 · En espera 0 …"): 32 tall, 12
/// bold; the chosen one filled navy (white in dark) with the surface's ink.
struct StatusTabs<Value: Hashable>: View {
    let options: [(value: Value, title: String, count: Int?)]
    @Binding var selection: Value

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(options, id: \.value) { option in
                    let chosen = option.value == selection
                    Button { selection = option.value } label: {
                        HStack(spacing: 6) {
                            Text(option.title)
                            if let count = option.count {
                                Text("\(count)").monospacedDigit().foregroundStyle(chosen ? Theme.surface.opacity(0.8) : Theme.inkStrong)
                            }
                        }
                        .font(.brandText(12, weight: .bold))
                        .foregroundStyle(chosen ? Theme.surface : Theme.inkSoft)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(chosen ? Theme.inkStrong : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

/// A horizontal, scrolling row of filter chips over a value.
struct FilterBar<Value: Hashable>: View {
    let options: [(value: Value, title: String, count: Int?)]
    @Binding var selection: Value

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.value) { option in
                    FilterChip(title: option.title, count: option.count, isSelected: selection == option.value) { selection = option.value }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - States

struct LoadingState: View {
    var text: String? = nil
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large).tint(Theme.blue)
            if let text { Text(text).font(Theme.smallFont).foregroundStyle(Theme.inkSoft) }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

/// The one empty state (web `ProviderEmptyState`): a round tinted well with
/// the icon, a heading, a line of help and the actions. `panel` is a dashed
/// card for a page or section that is all empty; `inline` sits inside a card.
struct EmptyState: View {
    var systemImage: String = "tray"
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var accent: Color = Theme.aqua
    var panel: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            IconBadge(icon: systemImage, accent: accent, size: 56, iconSize: 28, ink: .strong, washPercent: 22)
            Text(title)
                .font(.brandHeading(20, relativeTo: .title3))
                .foregroundStyle(Theme.inkStrong)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            if let message = message?.nonEmpty {
                Text(message).font(.brandText(14)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                    .frame(maxWidth: 512)
                    .padding(.top, 4)
            }
            if let actionTitle, let action {
                PMButton(actionTitle, size: .header, action: action).padding(.top, 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, panel ? 36 : 28)
        .frame(maxWidth: .infinity)
        .background {
            if panel {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.surface)
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            }
        }
    }
}

struct ErrorState: View {
    let message: String
    var retry: (() async -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Glyph("triangle-alert", size: 24).foregroundStyle(Theme.coral)
            Text(message).font(Theme.bodyFont).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.center)
            if let retry { PMButton(L("Try again"), variant: .outline, size: .compact) { Task { await retry() } } }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

/// What a person sees where their role can't open something.
struct NoAccessState: View {
    var message: String = L("Your role can't see this. Ask the owner of the business.")
    var body: some View {
        EmptyState(systemImage: "lock.fill", title: L("Not for your role"), message: message)
    }
}

/// A notice (web `Notice` of inventory-bits / pharmacy, `RxNotice`, Home's page banners,
/// the hospital page's notice). Three looks:
/// - `.inline` (§3.5): 16 corners, a 1.5 pt edge of the state at 55%, its wash at 10%, 14 type.
///   With a title the icon sits on the title's line and the message runs below; without one
///   the icon leads the message (or the custom content).
/// - `.banner` (§3.5 page banner, the clock check, families' requests, a legal note): a 1 pt
///   edge at 45%, the wash at 14%, 16/12 padding, the title's sentence bold and the message
///   after it, and one primary action.
/// - `.page` (the hospital page's notice): a card-round band, the wash at 10% with a 2 pt edge at
///   45%, a 40 white disc with the icon, the title bold with its byline, the content under it.
/// `icon`: "" = the tone's own, nil = none.
struct NoticeCard: View {
    enum Tone: Equatable {
        case info, warning, problem, success
        /// A prescription's "all good": MIAW yellow.
        case lime
        case custom(Color)
    }
    enum Look { case inline, banner, page }

    let tone: Tone
    var title: String? = nil
    var message: String? = nil
    var icon: String? = ""
    var look: Look = .inline
    /// Who did it, after the title (`.page`).
    var byline: String? = nil
    var actionTitle: String? = nil
    var actionVariant: ButtonVariant = .outline
    var isWorking: Bool = false
    var action: (() -> Void)? = nil
    var content: AnyView? = nil

    init(tone: Tone, title: String? = nil, message: String? = nil, icon: String? = "", look: Look = .inline, byline: String? = nil, actionTitle: String? = nil, actionVariant: ButtonVariant = .outline, isWorking: Bool = false, action: (() -> Void)? = nil) {
        self.tone = tone
        self.title = title
        self.message = message
        self.icon = icon
        self.look = look
        self.byline = byline
        self.actionTitle = actionTitle
        self.actionVariant = actionVariant
        self.isWorking = isWorking
        self.action = action
    }

    /// A notice with its own content (a list, a button row) under or beside the title.
    init<Content: View>(tone: Tone, title: String? = nil, icon: String? = "", look: Look = .inline, byline: String? = nil, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.title = title
        self.icon = icon
        self.look = look
        self.byline = byline
        self.content = AnyView(content())
    }

    private var color: Color {
        switch tone {
        case .info: ProviderState.upcoming.color
        case .warning: ProviderState.waiting.color
        case .problem: ProviderState.problem.color
        case .success: ProviderState.done.color
        case .lime: Theme.lime
        case .custom(let color): color
        }
    }

    private var glyph: String? {
        guard let icon else { return nil }
        if !icon.isEmpty { return icon }
        switch tone {
        case .info, .custom: return "info"
        case .warning: return "circle-alert"
        case .problem: return "triangle-alert"
        case .success, .lime: return "circle-check"
        }
    }

    private var iconInk: Color {
        if case .problem = tone, look == .inline { return Theme.destructive }
        return Theme.inkStrong
    }

    var body: some View {
        switch look {
        case .inline: inline
        case .banner: banner
        case .page: page
        }
    }

    private var box: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous) }

    @ViewBuilder
    private var actionButton: some View {
        if let actionTitle, let action {
            PMButton(actionTitle, variant: actionVariant, size: .compact, isWorking: isWorking, action: action)
        }
    }

    private var inline: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = title?.nonEmpty {
                HStack(alignment: .top, spacing: 10) {
                    if let glyph { Glyph(glyph, size: 16).foregroundStyle(iconInk).padding(.top, 2) }
                    Text(title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).fixedSize(horizontal: false, vertical: true)
                }
                if let message = message?.nonEmpty { Text(message).font(Theme.text(14)).foregroundStyle(Theme.inkStrong).fixedSize(horizontal: false, vertical: true) }
                if let content { content.font(Theme.text(14)).foregroundStyle(Theme.inkStrong) }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    if let glyph { Glyph(glyph, size: 16).foregroundStyle(iconInk).padding(.top, 2) }
                    VStack(alignment: .leading, spacing: 2) {
                        if let message = message?.nonEmpty { Text(message).fixedSize(horizontal: false, vertical: true) }
                        if let content { content }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(Theme.text(14))
                .foregroundStyle(Theme.inkStrong)
            }
            actionButton.padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(color, 10), in: box)
        .overlay(box.strokeBorder(Theme.mix(color, 55, with: Theme.borderSoft), lineWidth: 1.5))
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                if let glyph { Glyph(glyph, size: 16).foregroundStyle(Theme.inkStrong).padding(.top, 2) }
                VStack(alignment: .leading, spacing: 4) {
                    (Text(title ?? "").font(Theme.text(14, weight: .bold)) + Text((title?.nonEmpty != nil && message?.nonEmpty != nil ? " " : "") + (message ?? "")).font(Theme.text(14)))
                        .foregroundStyle(Theme.inkStrong)
                        .fixedSize(horizontal: false, vertical: true)
                    if let content { content.font(Theme.text(14)).foregroundStyle(Theme.inkStrong) }
                }
            }
            if let actionTitle, let action {
                PMButton(actionTitle, size: .compact, isWorking: isWorking, action: action)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(color, 14), in: box)
        .overlay(box.strokeBorder(Theme.mix(color, 45, with: Theme.borderSoft), lineWidth: 1))
    }

    private var page: some View {
        HStack(alignment: .top, spacing: 12) {
            if let glyph {
                Glyph(glyph, size: 20)
                    .foregroundStyle(Theme.inkStrong)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface, in: Circle())
                    .shadow(color: Theme.navy.opacity(0.08), radius: 1.5, y: 1)
            }
            VStack(alignment: .leading, spacing: 4) {
                (Text(title ?? "").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    + Text(byline.map { " · \($0)" } ?? "").font(Theme.text(14)).foregroundStyle(Theme.inkSoft))
                    .fixedSize(horizontal: false, vertical: true)
                if let message = message?.nonEmpty { Text(message).font(Theme.text(14)).foregroundStyle(Theme.inkStrong) }
                if let content { content.font(Theme.text(14)) }
                actionButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Theme.wash(color, 10), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.mix(color, 45, with: Theme.borderSoft), lineWidth: 2))
    }
}

/// A micro-label (web: the eyebrows — 0.62–0.75rem extrabold uppercase, tracked 0.1–0.12em,
/// ink-soft): over a box, a section, a table's column.
struct Eyebrow: View {
    let text: String
    var size: CGFloat = 10.9
    var color: Color = Theme.inkSoft
    var tracking: Double = 0.1

    init(_ text: String, size: CGFloat = 10.9, color: Color = Theme.inkSoft, tracking: Double = 0.1) {
        self.text = text
        self.size = size
        self.color = color
        self.tracking = tracking
    }

    var body: some View {
        Text(text.uppercased()).font(.brandText(size, weight: .heavy)).tracking(size * tracking).foregroundStyle(color)
    }
}

/// A part's heading on the canvas or in a column (web pharmacy-bits `SectionHeading`, a board's
/// stage, a due bucket): an optional state dot, the title (Fredoka 18, or 14 extrabold as a
/// `.label`), a count bubble, a hint under it, and an action below.
struct SectionHeading<Action: View>: View {
    enum Style { case heading, label }
    let title: String
    var count: Int? = nil
    var hint: String? = nil
    var dot: Color? = nil
    var style: Style = .heading
    /// The bubble's fill: muted on the canvas, white on a muted column.
    var bubble: Color = Theme.surfaceMuted
    /// Show the bubble at 0 too (a stage column).
    var showsZero: Bool = false
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if let dot { Circle().fill(dot).frame(width: 10, height: 10) }
                    Text(title)
                        .font(style == .heading ? .brandHeading(18, relativeTo: .headline) : Theme.text(14, weight: .heavy))
                        .foregroundStyle(Theme.inkStrong)
                        .lineLimit(style == .label ? 1 : nil)
                    if let count, count > 0 || showsZero {
                        Text("\(count)")
                            .font(.brandText(12, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkStrong)
                            .padding(.horizontal, 8)
                            .frame(minWidth: 24, minHeight: style == .heading ? 24 : 20)
                            .background(bubble, in: Capsule())
                    }
                }
                if let hint = hint?.nonEmpty {
                    Text(hint).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
            }
            action()
        }
    }
}

extension SectionHeading where Action == EmptyView {
    init(title: String, count: Int? = nil, hint: String? = nil, dot: Color? = nil, style: Style = .heading, bubble: Color = Theme.surfaceMuted, showsZero: Bool = false) {
        self.init(title: title, count: count, hint: hint, dot: dot, style: style, bubble: bubble, showsZero: showsZero, action: { EmptyView() })
    }
}

/// A bar that fills (web: the setup checklist's 8 pt bar, the day's care 10 pt bar, Finance's
/// `ShareBar`): PAW Blue (or a share's tone) over a track (blue 14%, the muted surface or white);
/// a fixed width or the space it gets.
struct ProgressBar: View {
    /// 0…1.
    let value: Double
    var height: CGFloat = 8
    var width: CGFloat? = nil
    var track: Color? = nil
    var fill: Color = Theme.blue
    var label: String? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Theme.wash(Theme.blue, 14)))
                Capsule().fill(fill).frame(width: proxy.size.width * CGFloat(max(0, min(1, value))))
            }
        }
        .frame(width: width, height: height)
        .accessibilityElement()
        .accessibilityLabel(label ?? "")
        .accessibilityValue("\(Int((max(0, min(1, value)) * 100).rounded()))%")
    }
}

/// A tick. `.checkbox` (web `ui/checkbox`): 20, the tick's corners, a 1.5 pt soft-ink edge
/// (red when invalid); on = PAW Blue with a white check, `mixed` = blue with a dash.
/// `.choice` (web location-choice / services-section `Tick`): 24, a 2 pt grey edge, the box's
/// corners (round at that size), blue with a check when on. `.radio` (web `ChoiceGroup`'s
/// mark, a role choice): a 20 circle with a 2 pt grey edge, blue with a 12 check when on.
struct Tick: View {
    enum Style { case checkbox, choice, radio }
    let on: Bool
    var mixed: Bool = false
    var invalid: Bool = false
    var style: Style = .checkbox

    private var size: CGFloat { style == .choice ? 24 : 20 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style == .checkbox ? Theme.tickRadius : min(Theme.boxRadius, size / 2), style: .continuous)
        ZStack {
            shape.fill(on || mixed ? AnyShapeStyle(Theme.blue) : AnyShapeStyle(Theme.surface))
            shape.strokeBorder(edge, lineWidth: style == .checkbox ? 1.5 : 2)
            if on {
                Glyph("check", size: style == .radio ? 12 : 14).foregroundStyle(Theme.onBlue)
            } else if mixed {
                Glyph("minus", size: 14).foregroundStyle(Theme.onBlue)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var edge: Color {
        if on || mixed { return Theme.blue }
        if invalid { return Theme.destructive }
        return style == .checkbox ? Theme.inkSoft : Theme.borderSoft
    }
}

// MARK: - People and pets

/// A person or a client: their photo, else the first letters on MIAW yellow
/// at 25% (web: the clients list's 40 pt initials, 14 bold navy).
struct Avatar: View {
    let name: String?
    var imageURL: String? = nil
    var size: CGFloat = 40
    /// The colour washed behind the initials instead of the clients' yellow (a staff role's).
    var tint: Color? = nil

    var body: some View {
        ZStack {
            Circle().fill(Theme.wash(tint ?? Theme.lime, 25))
            Text(NameText.firstLetters(name)).font(.brandText(size * 0.35, weight: .bold)).foregroundStyle(Theme.inkStrong)
            if let url = APIConfig.assetURL(imageURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                }
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// A pet's face (web `PetAvatar`): its photo, else the species' line icon in
/// cocoa on the warm pet-face circle, half the size. Same in dark.
struct PetAvatar: View {
    let name: String?
    var species: String? = nil
    var photoURL: String? = nil
    var size: CGFloat = 40

    private var glyph: String {
        switch species?.lowercased() {
        case "cat": "cat"
        case "bird": "bird"
        case "fish": "fish"
        case "rabbit": "rabbit"
        case "reptile", "turtle": "turtle"
        case "rodent", "hamster", "rat": "rat"
        case "dog": "dog"
        default: "paw-print"
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(Theme.petFace)
            Glyph(glyph, size: size * 0.5).foregroundStyle(Theme.petFaceInk)
            if let url = APIConfig.assetURL(photoURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                }
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// A pet as a chip (the clients list's pets): its 24 face and its name.
struct PetChip: View {
    let name: String
    var species: String? = nil
    var photoURL: String? = nil
    var highlighted: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            PetAvatar(name: name, species: species, photoURL: photoURL, size: 24)
            Text(name).font(.brandText(12, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
        }
        .padding(.leading, 2)
        .padding(.trailing, 10)
        .padding(.vertical, 2)
        .background(highlighted ? AnyShapeStyle(Theme.wash(Theme.blue, 12)) : AnyShapeStyle(Theme.surface), in: Capsule())
        .overlay(Capsule().strokeBorder(highlighted ? Theme.blue : Theme.borderSoft, lineWidth: 1))
    }
}

// MARK: - Locations

/// Pages that belong to one place (Home, the Agenda, Stays, Rooms,
/// Availability, the register) never mix places: with "Todas las sedes"
/// chosen they ask which one first.
struct RequireLocation<Content: View>: View {
    @EnvironmentObject private var workspace: Workspace
    @ViewBuilder let content: () -> Content

    var body: some View {
        if workspace.allLocationsChosen {
            PageScroll {
                Card {
                    HStack(spacing: 10) {
                        Glyph("layers", size: 20).foregroundStyle(Theme.blue)
                        Text(L("Choose a location")).font(Theme.titleFont).foregroundStyle(Theme.inkStrong)
                    }
                    Text(L("You are looking at every location. This page belongs to one place: its day, its schedule and its register."))
                        .font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                    ForEach(workspace.memberLocations) { location in
                        Button {
                            workspace.setLocation(location.id)
                            Toast.show(LF("Now showing %@.", location.name))
                        } label: {
                            ListRow(title: location.name, subtitle: location.address, showsChevron: true, leading: {
                                Glyph("map-pin", size: 20).foregroundStyle(Theme.blue)
                            }, trailing: {
                                if location.isPrimary { HueChip(text: L("Main"), hue: .sky) }
                            })
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            content()
        }
    }
}

// MARK: - Search

/// The search field used inside pages (lists use `.searchable` where they own the bar).
struct SearchField: View {
    /// `capsule`: a page's or a card toolbar's search (web ProviderToolbarSearchField);
    /// `field`: inside a sheet, the input's 16 corners (web client-pet-picker).
    enum Shape { case capsule, field }

    let prompt: String
    @Binding var text: String
    var height: CGFloat = 48
    var shape: Shape = .capsule
    @FocusState private var focused: Bool

    private var outline: AnyShape {
        shape == .capsule ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
    }

    var body: some View {
        HStack(spacing: 12) {
            Glyph("search", size: 16).foregroundStyle(Theme.inkSoft)
            TextField(prompt, text: $text)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.inkStrong)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Glyph("x", size: 16).foregroundStyle(Theme.inkSoft) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Clear"))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: height)
        .background(Theme.inputFill, in: outline)
        .overlay(outline.stroke(focused ? Theme.mango : Theme.borderSoft, lineWidth: 1))
        .overlay {
            if focused {
                (shape == .capsule ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: Theme.boxRadius + 3, style: .continuous)))
                    .stroke(Theme.mango.opacity(0.5), lineWidth: 3)
                    .padding(-3)
            }
        }
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}

/// Waits a moment after typing stops before running `action` (a search).
struct Debounced: ViewModifier {
    let value: String
    var delay: Duration = .milliseconds(250)
    let action: (String) async -> Void

    func body(content: Content) -> some View {
        content.task(id: value) {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await action(value)
        }
    }
}

extension View {
    func debounced(_ value: String, action: @escaping (String) async -> Void) -> some View {
        modifier(Debounced(value: value, action: action))
    }

    /// Reloads when the business or the place changes, or another screen changed data.
    func reloadsOnScope(_ action: @escaping () async -> Void) -> some View {
        modifier(ScopeReload(action: action))
    }
}

private struct ScopeReload: ViewModifier {
    @EnvironmentObject private var workspace: Workspace
    let action: () async -> Void

    func body(content: Content) -> some View {
        content
            .task(id: workspace.scopeVersion) { await action() }
            .onReceive(NotificationCenter.default.publisher(for: .pawMiawDataChanged)) { _ in
                Task { await action() }
            }
    }
}

/// Tell every screen that data changed (they reload on `reloadsOnScope`).
func announceDataChanged() {
    NotificationCenter.default.post(name: .pawMiawDataChanged, object: nil)
}

// MARK: - Cards of a page

/// The standard card with a header row (web: `rounded-card` with a header
/// padded 16/12 over a hairline): an optional icon disc, the title in Fredoka
/// 18, a trailing control; the content below runs edge to edge, so rows and
/// strips can draw their own dividers.
struct SectionCard<Trailing: View, Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var accent: Color = Theme.aqua
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                if let icon { IconBadge(icon: icon, accent: accent, size: 32, iconSize: 16, ink: .strong, washPercent: 35) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong).lineLimit(2)
                    if let subtitle = subtitle?.nonEmpty { Text(subtitle).font(Theme.text(13)).foregroundStyle(Theme.inkSoft) }
                }
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Rectangle().fill(Theme.borderSoft).frame(height: 1)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        .cardShadow()
    }
}

extension SectionCard where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, icon: String? = nil, accent: Color = Theme.aqua, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, subtitle: subtitle, icon: icon, accent: accent, trailing: { EmptyView() }, content: content)
    }
}

/// A hairline between the rows of a card.
struct RowDivider: View {
    var color: Color = Theme.borderSoft
    var body: some View { Rectangle().fill(color).frame(height: 1) }
}

/// A "Te necesita" block (web `Block`, today-board.tsx): a 28 disc and a
/// 14 extrabold title, the count at the right, rows between tinted hairlines,
/// a "Ver todo · 3 más" link. Amber or red attention washes the card in its
/// colour with a 2 pt border.
struct NeedsCard<Content: View>: View {
    enum Attention { case none, amber, red }
    let title: String
    let icon: String
    var count: Int? = nil
    var hint: String? = nil
    var tone: Color = Theme.aqua
    var attention: Attention = .none
    /// "3 más": the rows not shown; with `seeAll` it reads "Ver todo · 3 más".
    var more: Int = 0
    var seeAll: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    private var attentionColor: Color? {
        switch attention {
        case .none: nil
        case .amber: Theme.mango
        case .red: Theme.destructive
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Glyph(icon, size: 16)
                    .foregroundStyle(Theme.inkStrong)
                    .frame(width: 28, height: 28)
                    .background(Theme.wash(attentionColor ?? tone, attentionColor == nil ? 20 : 35), in: Circle())
                Text(title).font(Theme.text(14, weight: .heavy)).foregroundStyle(Theme.inkStrong).lineLimit(2)
                Spacer(minLength: 8)
                if let count { Text("\(count)").font(Theme.text(14, weight: .heavy)).monospacedDigit().foregroundStyle(Theme.inkStrong) }
            }
            if let hint = hint?.nonEmpty {
                Text(hint).font(Theme.text(12, weight: attention == .red ? .bold : .regular))
                    .foregroundStyle(attention == .red ? Theme.destructive : Theme.inkSoft)
            }
            content()
                .environment(\.needsDivider, attentionColor.map { $0.opacity(0.35) } ?? Theme.borderSoft)
            if more > 0 {
                if let seeAll {
                    Button(action: seeAll) {
                        Text("\(L("See all")) · \(LF("%@ more", String(more)))").font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                } else {
                    Text(LF("%@ more", String(more))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).padding(.top, 8)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(attentionColor.map { AnyShapeStyle(Theme.wash($0, 12)) } ?? AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(attentionColor?.opacity(0.7) ?? Theme.borderSoft, lineWidth: attentionColor == nil ? 1 : 2))
        .cardShadow()
    }
}

private struct NeedsDividerKey: EnvironmentKey { static let defaultValue: Color = Theme.borderSoft }
extension EnvironmentValues {
    /// The divider colour inside a `NeedsCard` (tinted under attention).
    var needsDivider: Color {
        get { self[NeedsDividerKey.self] }
        set { self[NeedsDividerKey.self] = newValue }
    }
}

/// One row of a `NeedsCard`: a 14 bold title, a 12 hint, a trailing control,
/// over the card's divider.
struct NeedsRow<Trailing: View>: View {
    let title: String
    var hint: String? = nil
    var first: Bool = false
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.needsDivider) private var divider

    var body: some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(divider).frame(height: 1) }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    if let hint = hint?.nonEmpty { Text(hint).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(2) }
                }
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.vertical, 6)
        }
    }
}

/// A one-line card that opens a page (web `LinkLine`): a 32 disc, a 14 bold
/// title, a 12 hint (red and bold when it needs someone).
struct LinkLine: View {
    let title: String
    let icon: String
    var hint: String? = nil
    var attention: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Glyph(icon, size: 16)
                .foregroundStyle(attention ? Theme.destructive : Theme.blue)
                .frame(width: 32, height: 32)
                .background(attention ? AnyShapeStyle(Theme.wash(Theme.destructive, 12)) : AnyShapeStyle(Theme.surfaceMuted), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                if let hint = hint?.nonEmpty {
                    Text(hint).font(Theme.text(12, weight: attention ? .bold : .regular)).foregroundStyle(attention ? Theme.destructive : Theme.inkSoft)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        .cardShadow()
        .contentShape(Rectangle())
    }
}

/// A band that opens a section of a board (web `HomeStrip`): an 8 dot, the
/// label and count in 11.2 extrabold uppercase, an optional link, a chevron.
struct BoardStrip: View {
    let title: String
    var count: Int? = nil
    var dot: Color = Theme.blue
    var linkTitle: String? = nil
    var link: (() -> Void)? = nil
    var folded: Binding<Bool>? = nil

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(title.uppercased()).tracking(1.3)
            if let count { Text("\(count)").monospacedDigit() }
            if let linkTitle, let link {
                Button(action: link) {
                    HStack(spacing: 2) {
                        Text(linkTitle)
                        Glyph("chevron-right", size: 14)
                    }
                    .font(Theme.text(12, weight: .bold))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            if let folded {
                Glyph("chevron-down", size: 16).rotationEffect(.degrees(folded.wrappedValue ? -90 : 0)).foregroundStyle(Theme.inkSoft)
            }
        }
        .font(.brandText(11.2, weight: .heavy))
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 29)
        .background(Theme.wash(Theme.surfaceMuted, 55))
        .contentShape(Rectangle())
        .onTapGesture { if let folded { withAnimation(.easeOut(duration: 0.2)) { folded.wrappedValue.toggle() } } }
    }
}

/// A row of a board or list with a 3 pt edge in its state's colour (web
/// `VisitRow` geometry): an 84 pt time column (Fredoka 15.2 time, an 11.2 bold
/// state word), then the rest, then an optional chevron.
struct EdgeRow<Content: View>: View {
    var edge: Color = Theme.borderSoft
    var time: String? = nil
    var timeNote: String? = nil
    var timeNoteColor: Color? = nil
    var showsChevron: Bool = false
    var dimmed: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if time != nil || timeNote != nil {
                VStack(alignment: .leading, spacing: 2) {
                    Text(time ?? "—").font(.brandHeading(15.2)).monospacedDigit().foregroundStyle(Theme.inkStrong).lineLimit(1)
                    if let timeNote { Text(timeNote).font(Theme.text(11.2, weight: .bold)).foregroundStyle(timeNoteColor ?? edge).lineLimit(2) }
                }
                .frame(width: 84, alignment: .leading)
            }
            content()
            if showsChevron { Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft) }
        }
        .padding(.leading, 13)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(edge).frame(width: 3) }
        .opacity(dimmed ? 0.75 : 1)
        .contentShape(Rectangle())
    }
}
