//
//  Segmented.swift
//  PawMiawNegocios
//
//  The web's pill controls: the segmented switch (a view: Día/Semana/Lista,
//  chosen = PAW Blue; page tabs: Clientes/Pacientes, chosen = raised white),
//  the day stepper (‹ Hoy ›) and a pill that opens a picker (a date, a person).
//  Never a system segmented Picker on a business screen.
//

import SwiftUI

struct Segmented<Value: Hashable>: View {
    enum Look {
        /// A view switch (provider.schedule.tsx): a 42 pt track, the chosen option in PAW Blue.
        case solid
        /// Page tabs and switches beside a 40 pt search (provider.clients.tsx, record-bits
        /// `Segmented`, catalog-bits `CatalogSegmented`): a 40 pt track, the chosen option raised
        /// in white, or filled with its tone's deep shade when it has one.
        case raised
    }

    struct Option {
        let value: Value
        let title: String
        var icon: String? = nil
        /// A quiet count after the title (web `CatalogSegmented` count; hidden on a phone).
        var count: Int? = nil
        /// A count bubble that stays on a phone (web record-bits `badge`): red when `attention`,
        /// a mango wash when it only waits.
        var badge: Int? = nil
        var attention: Bool = false
        /// The option wears its own colour (web `tonedTabClass`): its icon on a tinted chip,
        /// filled with the tone's deep shade under white ink while chosen.
        var tone: ChipTone? = nil
    }

    let options: [Option]
    @Binding var selection: Value
    var look: Look = .solid
    var label: String = ""
    /// Phones: the options share the full width and drop their plain icons (web `fill`).
    var fill: Bool = false

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var wide: Bool { sizeClass == .regular }
    private var stretches: Bool { fill && !wide }

    var body: some View {
        HStack(spacing: look == .solid ? 4 : 0) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = option.value }
                } label: {
                    SegmentLabel(option: option, chosen: option.value == selection, look: look, wide: wide, stretches: stretches)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title.isEmpty ? (option.icon ?? "") : option.title)
                .accessibilityAddTraits(option.value == selection ? .isSelected : [])
            }
        }
        .padding(4)
        .frame(maxWidth: stretches ? .infinity : nil)
        .background(Theme.surfaceMuted, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
        .fixedSize(horizontal: !stretches, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

private struct SegmentLabel<Value: Hashable>: View {
    let option: Segmented<Value>.Option
    let chosen: Bool
    let look: Segmented<Value>.Look
    let wide: Bool
    let stretches: Bool

    private var solid: Bool { look == .solid }

    private var ink: Color {
        guard chosen else { return Theme.inkSoft }
        if option.tone != nil { return .white }
        return solid ? Theme.onBlue : Theme.inkStrong
    }

    private var fill: AnyShapeStyle {
        if let tone = option.tone { return AnyShapeStyle(tone.fill) }
        return solid ? AnyShapeStyle(Theme.blue) : AnyShapeStyle(Theme.surface)
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon = option.icon {
                if let tone = option.tone {
                    ToneIcon(icon: icon, tone: tone, selected: chosen)
                } else if !stretches {
                    Glyph(icon, size: 16)
                }
            }
            if !option.title.isEmpty { Text(option.title).lineLimit(1).minimumScaleFactor(stretches ? 0.8 : 1) }
            if wide, let count = option.count {
                Text("\(count)")
                    .font(.brandText(11.2, weight: .heavy))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .foregroundStyle(chosen && option.tone != nil ? Color.white : Theme.inkStrong)
                    .background(countFill, in: Capsule())
            }
            if let badge = option.badge, badge > 0 {
                Text(badge > 99 ? "99+" : "\(badge)")
                    .font(.brandText(10.9, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(option.attention ? Color.white : Theme.inkStrong)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(option.attention ? AnyShapeStyle(Theme.destructive) : AnyShapeStyle(Theme.wash(Theme.mango, 40)), in: Capsule())
            }
        }
        .font(.brandText(14, weight: .bold))
        .padding(.leading, option.tone != nil && option.icon != nil && wide ? 8 : gutter)
        .padding(.trailing, gutter)
        .frame(maxWidth: stretches ? .infinity : nil)
        .frame(height: 32)
        .foregroundStyle(ink)
        .background {
            if chosen {
                Capsule().fill(fill)
                    .shadow(color: Theme.navy.opacity(0.1), radius: 1.5, y: 1)
            }
        }
        .contentShape(Capsule())
    }

    /// 14 in a view switch, 16 in page tabs, 10 when the options share a phone's width.
    private var gutter: CGFloat { stretches ? 10 : (solid ? 14 : 16) }

    private var countFill: AnyShapeStyle {
        if chosen { return option.tone != nil ? AnyShapeStyle(Color.white.opacity(0.2)) : AnyShapeStyle(Theme.wash(Theme.blue, 14)) }
        return AnyShapeStyle(Theme.inkSoft.opacity(0.12))
    }
}

extension Segmented.Option {
    init(_ value: Value, _ title: String, icon: String? = nil, count: Int? = nil, badge: Int? = nil, attention: Bool = false, tone: ChipTone? = nil) {
        self.value = value
        self.title = title
        self.icon = icon
        self.count = count
        self.badge = badge
        self.attention = attention
        self.tone = tone
    }
}

/// A page's tab bar (web: the tab bars of Estancias, Hospital, Estética, Paseos, Domicilio —
/// `.solid` — and of the Store, Pharmacy, Finance — `.toned`, store-tabs.tsx / `PharmacyTabs`):
/// a white capsule with a 2 pt edge hugging its tabs. `.solid`: the open tab PAW Blue under its
/// ink, a pink count bubble. `.toned`: each tab's icon on a 28 chip of its tone, the open one
/// filled with the tone's deep shade under white, the count bubble swapping colours. On a phone
/// the tabs that aren't open show only their icon (and count).
struct ToneTabs<Value: Hashable>: View {
    enum Look { case solid, toned }

    struct Tab {
        let value: Value
        let title: String
        let icon: String
        var tone: ChipTone = .page
        var count: Int? = nil
    }

    let tabs: [Tab]
    @Binding var selection: Value
    var look: Look = .toned
    /// `.solid` tabs: 40 (Estética, Paseos, Hospital, Estancias) or 44 (Domicilio, read on the street).
    var height: CGFloat = 40
    var label: String = ""
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: look == .toned ? 2 : 0) {
                ForEach(tabs, id: \.value) { tab in
                    let chosen = tab.value == selection
                    let iconOnly = !chosen && sizeClass != .regular
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { selection = tab.value }
                    } label: {
                        Group {
                            if look == .toned { toned(tab, chosen: chosen, iconOnly: iconOnly) } else { solid(tab, chosen: chosen, iconOnly: iconOnly) }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.count.map { $0 > 0 ? LF("%@, %d waiting", tab.title, $0) : tab.title } ?? tab.title)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            .padding(4)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 2))
            .padding(1)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func toned(_ tab: Tab, chosen: Bool, iconOnly: Bool) -> some View {
        HStack(spacing: 8) {
            ToneIcon(icon: tab.icon, tone: tab.tone, selected: chosen, size: 28, glyph: 16)
            if !iconOnly { Text(tab.title).lineLimit(1) }
            if let count = tab.count, count > 0 { ToneCount(count: count, tone: tab.tone, selected: chosen) }
        }
        .font(.brandText(14, weight: .bold))
        .foregroundStyle(chosen ? Color.white : Theme.inkSoft)
        .padding(.leading, 10)
        .padding(.trailing, iconOnly ? 10 : 16)
        .frame(minWidth: 44, minHeight: 44)
        .background {
            if chosen { Capsule().fill(tab.tone.fill).shadow(color: Theme.navy.opacity(0.1), radius: 1.5, y: 1) }
        }
    }

    private func solid(_ tab: Tab, chosen: Bool, iconOnly: Bool) -> some View {
        HStack(spacing: 8) {
            Glyph(tab.icon, size: 16)
            if !iconOnly { Text(tab.title).lineLimit(1) }
            if let count = tab.count, count > 0 {
                Text("\(count)")
                    .font(.brandText(12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkOnBright)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Theme.pink, in: Capsule())
            }
        }
        .font(.brandText(14, weight: .bold))
        .foregroundStyle(chosen ? Theme.onBlue : Theme.inkSoft)
        .padding(.horizontal, iconOnly ? 12 : 16)
        .frame(minHeight: height)
        .background {
            if chosen { Capsule().fill(Theme.blue).shadow(color: Theme.navy.opacity(0.1), radius: 1.5, y: 1) }
        }
    }
}

extension ToneTabs.Tab {
    init(_ value: Value, _ title: String, icon: String, tone: ChipTone = .page, count: Int? = nil) {
        self.value = value
        self.title = title
        self.icon = icon
        self.tone = tone
        self.count = count
    }
}

/// ‹ Hoy › (web `HomeDaySwitcher`, home-day.tsx, and the Schedule's date navigator): one
/// 42 pt pill, 32 blue arrows, the middle "Today" grey while it is today. Away from today
/// the middle names the day (`todayTitle`) and takes you back; with `washesAway` (Home) it
/// sits on a PAW Blue wash, as the web's Home does, else it is plain blue text (Agenda).
struct DayStepper: View {
    let isToday: Bool
    var todayTitle: String = L("Today")
    /// Home: away from today the middle is a blue-washed capsule, at least 88 wide.
    var washesAway: Bool = false
    let previous: () -> Void
    let today: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            arrow("chevron-left", label: L("Previous day"), action: previous)
            Button(action: today) {
                Text(todayTitle)
                    .font(.brandText(14, weight: .bold))
                    .foregroundStyle(isToday ? Theme.inkSoft : Theme.blue)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(minWidth: washesAway ? 88 : nil)
                    .frame(height: 32)
                    .background(washesAway && !isToday ? AnyShapeStyle(Theme.wash(Theme.blue, 12)) : AnyShapeStyle(Color.clear), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isToday)
            .accessibilityHint(isToday ? "" : L("Back to today"))
            arrow("chevron-right", label: L("Next day"), action: next)
        }
        .padding(4)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
        .fixedSize()
    }

    private func arrow(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Glyph(icon, size: 16).foregroundStyle(Theme.blue).frame(width: 32, height: 32).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A pill that shows a value and opens a picker: a date, a person, a sort
/// (web: the rounded-full select and date triggers). Use as a `Menu` label,
/// or put a `DatePicker` over it with `PillDatePicker`.
struct PillField: View {
    let text: String
    var icon: String? = "chevron-down"
    var leadingIcon: String? = nil
    var placeholder: Bool = false
    var height: CGFloat = 40

    var body: some View {
        HStack(spacing: 8) {
            if let leadingIcon { Glyph(leadingIcon, size: 16).foregroundStyle(Theme.inkSoft) }
            Text(text)
                .font(.brandText(15, weight: .semibold))
                .foregroundStyle(placeholder ? Theme.inkSoft : Theme.inkStrong)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let icon { Glyph(icon, size: 16).foregroundStyle(Theme.inkSoft) }
        }
        .padding(.horizontal, 16)
        .frame(height: height)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// A day chosen from a pill: the pill shows the day, the system calendar
/// opens over it (the date picker itself is invisible).
struct PillDatePicker: View {
    let text: String
    @Binding var date: Date
    var zone: TimeZone? = nil

    var body: some View {
        // The system picker sits under the pill (which draws over it and lets
        // touches through), stretched to take a tap anywhere on the pill.
        ZStack {
            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .environment(\.timeZone, zone ?? .current)
                .scaleEffect(x: 2.4, y: 1.3)
            PillField(text: text, icon: "calendar")
                .allowsHitTesting(false)
        }
        .fixedSize()
        .clipShape(Capsule())
    }
}
