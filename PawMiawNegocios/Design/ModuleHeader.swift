//
//  ModuleHeader.swift
//  PawMiawNegocios
//
//  The top of every business page, the web's `ProviderModuleHeader`
//  (provider-module-header.tsx): one card with the page's icon on its colour,
//  the title, one line of context, the page's main actions as 36 pt buttons,
//  and the numbers that matter today as tiles, two by two on a phone, in one
//  row on an iPad. A wash of the page's colour runs in from the left. It folds
//  into one slim row (the numbers become chips): an iPhone starts folded, an
//  iPad open, and once someone folds or opens a page's header that choice is
//  remembered for the page (`storageKey`).
//
//  A page never draws its own title block or stat tiles: it passes them here.
//

import SwiftUI

/// The round icon well every provider card and header uses (web `IconBadge`;
/// the provider workspace draws them round).
struct IconBadge: View {
    enum Ink { case onAccent, strong, accent }

    let icon: String
    var accent: Color = Theme.blue
    var size: CGFloat = 44
    var iconSize: CGFloat? = nil
    var ink: Ink = .onAccent
    /// A wash of the accent (an empty state's well, a card's icon) instead of the solid fill.
    var washPercent: Double? = nil

    var body: some View {
        ZStack {
            if let washPercent {
                Circle().fill(Theme.wash(accent, washPercent))
            } else {
                Circle().fill(accent)
                Circle().strokeBorder(accent, lineWidth: 1)
            }
            Glyph(icon, size: iconSize ?? (size * 0.45))
                .foregroundStyle(inkColor)
        }
        .frame(width: size, height: size)
    }

    private var inkColor: Color {
        switch ink {
        case .onAccent: Theme.onBlue
        case .strong: Theme.inkOnBright
        case .accent: accent
        }
    }
}

/// One number in a module header (web `ProviderModuleStat`).
struct ModuleStat: Identifiable {
    let id: String
    let label: String
    let value: String
    var hint: String? = nil
    var icon: String
    var accent: Color = Theme.blue
    /// The number needs acting on (low stock, requests): it reads red.
    var attention: Bool = false
    /// A filter that is on.
    var active: Bool = false
    /// Quieter: a step still to come, nothing in it yet.
    var muted: Bool = false
    /// Makes the stat a filter.
    var action: (() -> Void)? = nil

    init(_ id: String, label: String, value: String, hint: String? = nil, icon: String, accent: Color = Theme.blue, attention: Bool = false, active: Bool = false, muted: Bool = false, action: (() -> Void)? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.hint = hint
        self.icon = icon
        self.accent = accent
        self.attention = attention
        self.active = active
        self.muted = muted
        self.action = action
    }
}

struct ModuleHeader<Actions: View, Footer: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var accent: Color = Theme.blue
    /// A photo in place of the icon (a pet, a person).
    var media: AnyView? = nil
    /// Badges beside the title (a client's status, a record's state, a patient's triage): wraps
    /// under the title on a phone.
    var titleAccessory: AnyView? = nil
    var stats: [ModuleStat] = []
    /// `row`: the actions get a line of their own under the title (a page with many).
    var actionsOnRow: Bool = false
    /// The key the folded state is remembered under (the page).
    var storageKey: String? = nil
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var footer: () -> Footer

    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The fold chosen by a tap on this screen; nil until then.
    @State private var tapped: Bool? = nil

    private var wide: Bool { sizeClass == .regular }

    private var foldKey: String? { storageKey.map { "header-collapsed:\($0)" } }

    /// Folded or open (web provider-module-header.tsx): what the person chose for this page
    /// (remembered once they fold or open it), else the screen's default — folded on an
    /// iPhone, open on an iPad. Read while drawing, so a phone never shows it open first.
    private var collapsed: Bool {
        if let tapped { return tapped }
        if let foldKey, let stored = UserDefaults.standard.object(forKey: foldKey) as? Bool { return stored }
        return !wide
    }

    private func setCollapsed(_ value: Bool) {
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.34)) { tapped = value }
        if let foldKey { UserDefaults.standard.set(value, forKey: foldKey) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if collapsed { folded } else { open }
            footer()
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        .cardShadow()
    }

    // MARK: Open

    private var open: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if wide {
                    HStack(alignment: .center, spacing: 16) {
                        lead(size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .center, spacing: 10) {
                                Text(title).font(.brandHeading(24, relativeTo: .title2)).foregroundStyle(Theme.inkStrong).lineLimit(2)
                                if let titleAccessory { titleAccessory }
                            }
                            if let subtitle = subtitle?.nonEmpty {
                                Text(subtitle).font(.brandText(14, weight: .medium)).foregroundStyle(Theme.inkSoft)
                            }
                        }
                        Spacer(minLength: 12)
                        if !actionsOnRow { actionRow(scrolls: false) }
                        toggleButton
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        lead(size: 36)
                        Text(title).font(.brandHeading(20, relativeTo: .title2)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Spacer(minLength: 8)
                        toggleButton
                    }
                    if let titleAccessory {
                        FlowLayout(spacing: 6) { titleAccessory }
                            .padding(.top, -4)
                    }
                    if let subtitle = subtitle?.nonEmpty {
                        Text(subtitle).font(.brandText(13, weight: .medium)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                            .padding(.top, -4)
                    }
                    if !actionsOnRow, Actions.self != EmptyView.self { actionRow(scrolls: true).padding(.horizontal, -16) }
                }
            }
            .padding(.horizontal, wide ? 24 : 16)
            .padding(.vertical, wide ? 16 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(openWash)

            if actionsOnRow, Actions.self != EmptyView.self {
                Rectangle().fill(Theme.borderSoft).frame(height: 1)
                actionRow(scrolls: true)
                    .padding(.vertical, 10)
                    .background(Theme.surface)
            }

            if !stats.isEmpty {
                Rectangle().fill(Theme.borderSoft).frame(height: 1)
                statGrid
            }
        }
    }

    private var openWash: LinearGradient {
        // linear-gradient(105deg, accent 13% → accent 4% at 45% → surface at 80%)
        LinearGradient(
            stops: [
                .init(color: accent.opacity(0.13), location: 0),
                .init(color: accent.opacity(0.04), location: 0.45),
                .init(color: accent.opacity(0), location: 0.8),
            ],
            startPoint: UnitPoint(x: 0, y: 0.37),
            endPoint: UnitPoint(x: 1, y: 0.63)
        )
    }

    @ViewBuilder
    private func lead(size: CGFloat) -> some View {
        if let media {
            media
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.surface, lineWidth: wide ? 4 : 2))
        } else {
            IconBadge(icon: icon, accent: accent, size: size, iconSize: size >= 56 ? 24 : 18)
                .shadow(color: Theme.navy.opacity(0.08), radius: 1, y: 1)
        }
    }

    @ViewBuilder
    private func actionRow(scrolls: Bool) -> some View {
        if scrolls {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { actions() }
                    .padding(.horizontal, 16)
            }
            .environment(\.headerButtons, true)
        } else {
            HStack(spacing: 8) { actions() }
                .environment(\.headerButtons, true)
        }
    }

    private var toggleButton: some View {
        Button {
            setCollapsed(!collapsed)
        } label: {
            Glyph("chevron-up", size: 16)
                .rotationEffect(.degrees(collapsed ? 180 : 0))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.borderSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collapsed ? L("Show summary") : L("Hide summary"))
    }

    // MARK: Numbers

    private var statGrid: some View {
        let columns: Int = {
            if wide { return stats.count >= 4 ? min(stats.count, 5) : stats.count }
            return stats.count == 3 ? 3 : 2
        }()
        let rows = stride(from: 0, to: stats.count, by: columns).map { Array(stats[$0..<min($0 + columns, stats.count)]) }
        return VStack(spacing: 1) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 1) {
                    ForEach(rows[index]) { stat in
                        StatCell(stat: stat, dense: stats.count == 3 && !wide, wide: wide)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(Theme.borderSoft)
    }

    // MARK: Folded

    private var folded: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    setCollapsed(false)
                } label: {
                    HStack(spacing: 12) {
                        lead(size: wide ? 40 : 36)
                        Text(title).font(.brandHeading(20, relativeTo: .title2)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 8)
                if wide { actionRow(scrolls: false) }
                toggleButton
            }
            if !stats.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(stats) { StatChip(stat: $0) } }
                        .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
            }
            if !wide, Actions.self != EmptyView.self { actionRow(scrolls: true).padding(.horizontal, -16) }
        }
        .padding(.horizontal, wide ? 20 : 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(stops: [.init(color: accent.opacity(0.10), location: 0), .init(color: accent.opacity(0), location: 0.35)],
                           startPoint: UnitPoint(x: 0, y: 0.37), endPoint: UnitPoint(x: 1, y: 0.63))
        )
    }
}

extension ModuleHeader where Footer == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil, accent: Color = Theme.blue, media: AnyView? = nil, titleAccessory: AnyView? = nil, stats: [ModuleStat] = [], actionsOnRow: Bool = false, storageKey: String? = nil, @ViewBuilder actions: @escaping () -> Actions) {
        self.init(icon: icon, title: title, subtitle: subtitle, accent: accent, media: media, titleAccessory: titleAccessory, stats: stats, actionsOnRow: actionsOnRow, storageKey: storageKey, actions: actions, footer: { EmptyView() })
    }
}

extension ModuleHeader where Actions == EmptyView, Footer == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil, accent: Color = Theme.blue, media: AnyView? = nil, titleAccessory: AnyView? = nil, stats: [ModuleStat] = [], storageKey: String? = nil) {
        self.init(icon: icon, title: title, subtitle: subtitle, accent: accent, media: media, titleAccessory: titleAccessory, stats: stats, actionsOnRow: false, storageKey: storageKey, actions: { EmptyView() }, footer: { EmptyView() })
    }
}

/// A stat tile in the open header.
private struct StatCell: View {
    let stat: ModuleStat
    let dense: Bool
    let wide: Bool

    var body: some View {
        if let action = stat.action {
            Button(action: action) { tile }.buttonStyle(.plain)
                .accessibilityAddTraits(stat.active ? .isSelected : [])
        } else {
            tile
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: wide ? 8 : 6) {
                if !dense {
                    IconBadge(icon: stat.icon, accent: stat.accent, size: wide ? 28 : 20, iconSize: wide ? 14 : 12, ink: .strong)
                }
                Text(stat.label.uppercased())
                    .font(.brandText(wide ? 10.5 : 9.6, weight: .heavy))
                    .tracking(wide ? 1.05 : 0.4)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(wide ? 2 : 1)
                    .padding(.top, wide ? 6 : 2)
            }
            .opacity(stat.muted ? 0.55 : 1)
            Text(stat.value)
                .font(.brandHeading(wide ? 24 : 18, relativeTo: .title3))
                .foregroundStyle(stat.attention ? Theme.coral : Theme.inkStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, wide ? 8 : 4)
                .opacity(stat.muted ? 0.55 : 1)
            if let hint = stat.hint?.nonEmpty {
                Text(hint)
                    .font(.brandText(wide ? 12 : 11.2))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(wide ? 2 : 1)
                    .padding(.top, 2)
                    .opacity(stat.muted ? 0.55 : 1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, wide ? 16 : 12)
        .padding(.vertical, wide ? 14 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(stat.active ? AnyShapeStyle(Theme.wash(Theme.surfaceMuted, 70)) : AnyShapeStyle(Theme.surface))
        .overlay(alignment: .bottom) {
            Rectangle().fill(stat.accent).frame(height: 3).opacity(stat.active ? 1 : 0)
        }
        .contentShape(Rectangle())
    }
}

/// A stat folded to one line: its dot, label and value.
private struct StatChip: View {
    let stat: ModuleStat

    var body: some View {
        if let action = stat.action {
            Button(action: action) { chip }.buttonStyle(.plain)
        } else {
            chip
        }
    }

    private var chip: some View {
        HStack(spacing: 6) {
            Circle().fill(stat.accent).frame(width: 8, height: 8)
            Text(stat.label).font(.brandText(12, weight: .bold)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            Text(stat.value).font(.brandHeading(14)).foregroundStyle(stat.attention ? Theme.coral : Theme.inkStrong).lineLimit(1)
        }
        .opacity(stat.muted ? 0.6 : 1)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(stat.active ? AnyShapeStyle(Theme.wash(Theme.blue, 10)) : AnyShapeStyle(Theme.surface), in: Capsule())
        .overlay(Capsule().strokeBorder(stat.active ? Theme.blue : Theme.borderSoft, lineWidth: 1))
    }
}

// MARK: - Header buttons

private struct HeaderButtonsKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Inside a module header: every `PMButton` is the header's 36 pt size.
    var headerButtons: Bool {
        get { self[HeaderButtonsKey.self] }
        set { self[HeaderButtonsKey.self] = newValue }
    }
}
