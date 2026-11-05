//
//  HomeParts.swift
//  PawMiawNegocios
//
//  Home's own arrangements of the kit's parts: a section of the board that
//  folds and remembers it (web `HomeStrip`, over the kit's `BoardStrip`), its
//  "Ver todo" line, a plain disc, the day keys, and ‹ Hoy › (the kit's
//  `DayStepper` with Home's wash away from today).
//

import SwiftUI

// MARK: - A section of the board

/// One part of Home's day list (web home-strip.tsx): its band with the dot, the
/// label and the count, an optional link to its page, and the rows under it.
/// The band folds the part; the choice is remembered per part on this device.
struct HomeStrip<Content: View>: View {
    /// Names the part for the remembered choice (`board:now`, `grooming`, `stays`…).
    let storageKey: String
    let title: String
    let count: Int
    var dot: Color = Theme.blue
    var linkTitle: String? = nil
    var link: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    @State private var folded = false

    private var key: String { "pawmiaw.provider.home-strip-collapsed:\(storageKey)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BoardStrip(title: title, count: count, dot: dot, linkTitle: linkTitle, link: link, folded: $folded)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(folded ? LF("Show %@", title) : LF("Hide %@", title))
            if !folded {
                content()
            }
            RowDivider()
        }
        .onAppear { folded = UserDefaults.standard.bool(forKey: key) }
        .onChange(of: folded) { _, value in
            if value { UserDefaults.standard.set(true, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
}

/// "Ver todo · 3 más" under a part Home shows capped (its page has every row).
struct HomeStripMore: View {
    let more: Int
    let route: ProviderRoute
    var title: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            RowDivider()
            NavigationLink(value: route) {
                HStack(spacing: 4) {
                    Text((title ?? L("See everything")) + (more > 0 ? " · " + LF("%d more", more) : ""))
                    Glyph("chevron-right", size: 14)
                }
                .font(Theme.text(12, weight: .bold))
                .foregroundStyle(Theme.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Small controls

/// A plain disc with an icon (the checklist's rows, the relocate banner): any fill, the ink the theme gives.
struct HomeDisc: View {
    let icon: String
    var size: CGFloat = 36
    var iconSize: CGFloat = 16
    var fill: Color = Theme.surfaceMuted
    var ink: Color = Theme.inkStrong

    var body: some View {
        Glyph(icon, size: iconSize)
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
    }
}

// MARK: - The day

/// Days as the server writes them ("2026-11-04"), moved by whole days on the business's calendar.
enum HomeDayKey {
    static func shift(_ day: String, _ days: Int) -> String {
        guard let date = DateText.parse(day), let moved = DateText.calendar.date(byAdding: .day, value: days, to: date) else { return day }
        return DateText.dayKey(moved)
    }

    /// "Sáb 3 oct": weekday, day and month, first letter up.
    static func short(_ day: String) -> String {
        let text = DateText.day(DateText.parse(day))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "Martes, 4 de noviembre".
    static func long(_ day: String?) -> String {
        let text = DateText.longDay(DateText.parse(day) ?? Date())
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "Hoy", "Mañana", "Ayer", or nil for another day.
    static func name(_ day: String, today: String) -> String? {
        if day == today { return L("Today") }
        if day == shift(today, 1) { return L("Tomorrow") }
        if day == shift(today, -1) { return L("Yesterday") }
        return nil
    }
}

/// ‹ Hoy › on Home (web `HomeDaySwitcher`): the kit's `DayStepper`, a day back, a day ahead; on
/// another day the middle says which ("Vie 3 oct") on a blue wash and takes you back to today.
func homeDayStepper(date: String, today: String, onChange: @escaping (String?) -> Void) -> DayStepper {
    func go(_ days: Int) {
        let next = HomeDayKey.shift(date, days)
        onChange(next == today ? nil : next)
    }
    return DayStepper(
        isToday: date == today,
        todayTitle: date == today ? L("Today") : HomeDayKey.short(date),
        washesAway: true,
        previous: { go(-1) },
        today: { onChange(nil) },
        next: { go(1) }
    )
}
