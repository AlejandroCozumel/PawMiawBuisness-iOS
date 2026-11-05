//
//  TeamShared.swift
//  PawMiawNegocios
//
//  Pieces the Team module's pages share, built from the Design components:
//  a card that saves on its own (the web's SaveSection, "Cambios sin
//  guardar" until saved), a titled panel, a confirmation with content, the
//  "where they work" list, a stat with its hint, and opening a page of the
//  web. (The change history is the shared AuditHistoryCard.)
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - A card that saves on its own

enum TeamSaveState { case clean, dirty, saving, saved, invalid }

/// "Saved" for a few seconds after a save, then quiet again.
@MainActor
final class TeamSavedFlash: ObservableObject {
    @Published private(set) var on = false
    private var task: Task<Void, Never>?

    func mark() {
        on = true
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.on = false
        }
    }

    func clear() { on = false; task?.cancel() }

    func state(saving: Bool, dirty: Bool, valid: Bool = true) -> TeamSaveState {
        if saving { return .saving }
        if dirty { return valid ? .dirty : .invalid }
        return on ? .saved : .clean
    }
}

/// The look a Team card wears. `.card` is the web's `SaveSection` / `MemberPanel`
/// (Availability, a staff member's page, the account): a solid 40 icon badge,
/// a Fredoka 20 title, a hairline under the header. `.settings` is the web's
/// `SettingsPanel` (Settings' sections): the header washed with the accent from
/// the left, the icon on a 24% wash, a "Cambios sin guardar" chip by the title,
/// and the Save / Discard bar only while something is unsaved.
enum TeamCardLook { case card, settings }

/// The header every Team card wears: the icon badge, the title, what it is for,
/// and something small on the right (stacked under it on a phone).
struct TeamCardHeader<Aside: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String
    var tint: Color = Theme.blue
    var look: TeamCardLook = .card
    /// Settings only: "Cambios sin guardar" / "Guardado" beside the title.
    var saveState: TeamSaveState? = nil
    @ViewBuilder var aside: () -> Aside

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: 12) { lead; Spacer(minLength: 8); aside() }
            } else {
                VStack(alignment: .leading, spacing: 12) { lead; aside() }
            }
        }
        .padding(.horizontal, sizeClass == .regular ? (look == .settings ? 24 : 20) : 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if look == .settings {
                // linear-gradient(105deg, accent 9% → surface 60%)
                LinearGradient(stops: [.init(color: tint.opacity(0.09), location: 0), .init(color: tint.opacity(0), location: 0.6)],
                               startPoint: UnitPoint(x: 0, y: 0.37), endPoint: UnitPoint(x: 1, y: 0.63))
            }
        }
        .overlay(alignment: .bottom) { RowDivider() }
    }

    @ViewBuilder
    private var lead: some View {
        if look == .settings {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Group {
                        // Olfato AI wears its corgi in a vet coat, as on the web.
                        if systemImage == "olfato" {
                            Image("OlfatoFace").resizable().scaledToFit().padding(4)
                        } else {
                            Glyph(systemImage, size: 20)
                        }
                    }
                    .foregroundStyle(Theme.inkStrong)
                    .frame(width: 40, height: 40)
                    .background(Theme.wash(tint, 24), in: Circle())
                    Text(title).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong).lineLimit(2)
                    if let saveState { TeamSaveStateChip(state: saveState) }
                }
                if let subtitle = subtitle?.nonEmpty { Text(subtitle).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if systemImage == "olfato" {
                        // Olfato AI wears its corgi in a vet coat, on its colour.
                        Image("OlfatoFace").resizable().scaledToFit().padding(5)
                            .frame(width: 40, height: 40)
                            .background(tint, in: Circle())
                    } else {
                        IconBadge(icon: systemImage, accent: tint, size: 40, iconSize: 16, ink: tint == Theme.blue ? .onAccent : .strong)
                    }
                }
                .overlay(Circle().strokeBorder(Theme.blue, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
                    if let subtitle = subtitle?.nonEmpty { Text(subtitle).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                }
            }
        }
    }
}

extension TeamCardHeader where Aside == EmptyView {
    init(title: String, subtitle: String? = nil, systemImage: String, tint: Color = Theme.blue, look: TeamCardLook = .card, saveState: TeamSaveState? = nil) {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint, look: look, saveState: saveState, aside: { EmptyView() })
    }
}

/// "Cambios sin guardar" / "Guardado" beside a Settings section's title (web `SaveStateChip`).
struct TeamSaveStateChip: View {
    let state: TeamSaveState

    var body: some View {
        switch state {
        case .dirty, .invalid, .saving:
            HStack(spacing: 6) {
                Circle().fill(Theme.mango).frame(width: 8, height: 8)
                Text(L("Unsaved changes"))
            }
            .modifier(Pill(fill: Theme.mango, percent: 22))
        case .saved:
            HStack(spacing: 6) {
                Glyph("circle-check", size: 14).foregroundStyle(ProviderState.done.color)
                Text(L("Saved"))
            }
            .modifier(Pill(fill: ProviderState.done.color, percent: 20))
        case .clean:
            EmptyView()
        }
    }

    private struct Pill: ViewModifier {
        let fill: Color
        let percent: Double
        func body(content: Content) -> some View {
            content
                .font(Theme.text(12, weight: .heavy))
                .foregroundStyle(Theme.inkStrong)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Theme.wash(fill, percent), in: Capsule())
        }
    }
}

/// The card frame every Team card shares: the standard card (28 corners, a
/// hairline border, the card shadow), clipped so its strips run edge to edge.
private struct TeamCardFrame: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .listCard()
    }
}

/// A titled card for the parts that don't save in place (the web's
/// `MemberPanel`, or a `SettingsPanel` with no save bar).
struct TeamPanel<Content: View, Action: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String
    var tint: Color = Theme.blue
    var look: TeamCardLook = .card
    /// Settings: why this person can only look, in a strip under the header.
    var readOnlyNote: String? = nil
    @ViewBuilder var action: () -> Action
    @ViewBuilder let content: () -> Content

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TeamCardHeader(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint, look: look, aside: action)
            if let readOnlyNote { TeamReadOnlyStrip(text: readOnlyNote) }
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(.horizontal, sizeClass == .regular ? (look == .settings ? 24 : 20) : 16)
                .padding(.vertical, look == .settings ? 20 : 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(TeamCardFrame())
    }
}

extension TeamPanel where Action == EmptyView {
    init(title: String, subtitle: String? = nil, systemImage: String, tint: Color = Theme.blue, look: TeamCardLook = .card, readOnlyNote: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint, look: look, readOnlyNote: readOnlyNote, action: { EmptyView() }, content: content)
    }
}

/// The read-only strip under a Settings card's header (web `data-read-only-note`).
struct TeamReadOnlyStrip: View {
    let text: String
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        HStack(spacing: 8) {
            Glyph("lock", size: 16)
            Text(text)
        }
        .font(Theme.text(14, weight: .semibold))
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, sizeClass == .regular ? 24 : 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted)
        .overlay(alignment: .bottom) { RowDivider() }
    }
}

/// A card that saves on its own. `.card` (the web's `SaveSection`): the fields,
/// then a footer saying whether there is something to save ("Cambios sin
/// guardar") with Discard and Save; read-only readers see why instead.
/// `.settings` (the web's `SettingsPanel`): the read-only note under the title,
/// and the Save / Discard bar only while something is unsaved (or always,
/// waiting disabled, with `floatingBar: false`).
struct TeamSaveSection<Content: View, Aside: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String
    var tint: Color = Theme.blue
    var look: TeamCardLook = .card
    /// Settings: the bar shows only while something is unsaved (the web's `saveBar="when-dirty"`).
    var floatingBar: Bool = true
    let state: TeamSaveState
    var saveLabel: String = L("Save")
    var invalidText: String? = nil
    var readOnlyText: String? = nil
    var onSave: (() -> Void)? = nil
    var onDiscard: (() -> Void)? = nil
    @ViewBuilder var aside: () -> Aside
    @ViewBuilder let content: () -> Content

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var wide: Bool { sizeClass == .regular }
    private var gutter: CGFloat { wide ? (look == .settings ? 24 : 20) : 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TeamCardHeader(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint, look: look,
                           saveState: look == .settings && readOnlyText == nil ? state : nil, aside: aside)
            if look == .settings, let readOnlyText { TeamReadOnlyStrip(text: readOnlyText) }
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(.horizontal, gutter)
                .padding(.vertical, look == .settings ? 20 : 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            if look == .settings {
                if readOnlyText == nil, let onSave, !floatingBar || state == .dirty || state == .invalid || state == .saving {
                    settingsBar(onSave)
                }
            } else if let readOnlyText {
                Text(readOnlyText)
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, gutter).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.wash(Theme.surfaceMuted, 50))
                    .overlay(alignment: .top) { RowDivider() }
            } else if let onSave {
                cardFooter(onSave)
            }
        }
        .modifier(TeamCardFrame())
        // A page that guards leaving reads which of its cards have unsaved changes.
        .preference(key: TeamUnsavedKey.self, value: readOnlyText == nil && onSave != nil && (state == .dirty || state == .invalid) ? [title] : [])
    }

    // MARK: SaveSection's footer

    private func cardFooter(_ onSave: @escaping () -> Void) -> some View {
        Group {
            if wide {
                HStack(spacing: 8) { status; Spacer(minLength: 8); cardButtons(onSave) }
            } else {
                VStack(alignment: .leading, spacing: 8) { status; HStack(spacing: 8) { cardButtons(onSave) } }
            }
        }
        .padding(.horizontal, gutter)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(footerFill)
        .overlay(alignment: .top) { Rectangle().fill(footerBorder).frame(height: 1) }
    }

    private var footerFill: AnyShapeStyle {
        switch state {
        case .dirty, .saving: AnyShapeStyle(Theme.wash(Theme.mango, 10))
        case .invalid: AnyShapeStyle(Theme.wash(Theme.destructive, 6))
        default: AnyShapeStyle(Theme.wash(Theme.surfaceMuted, 50))
        }
    }

    private var footerBorder: AnyShapeStyle {
        switch state {
        case .dirty, .saving: AnyShapeStyle(Theme.mix(Theme.mango, 45, with: Theme.borderSoft))
        case .invalid: AnyShapeStyle(Theme.mix(Theme.destructive, 35, with: Theme.borderSoft))
        default: AnyShapeStyle(Theme.borderSoft)
        }
    }

    @ViewBuilder
    private var status: some View {
        HStack(spacing: 8) {
            switch state {
            case .saved:
                Glyph("check", size: 16).foregroundStyle(Theme.blue)
                Text(L("Saved"))
            case .dirty:
                Circle().fill(Theme.mango).frame(width: 8, height: 8)
                Text(L("Unsaved changes"))
            case .saving:
                ProgressView().controlSize(.small)
                Text(L("Saving…"))
            case .invalid:
                Text(invalidText ?? L("Fix the marked fields to save.")).foregroundStyle(Theme.destructive)
            case .clean:
                Text(L("Up to date")).font(Theme.text(14, weight: .medium)).foregroundStyle(Theme.inkSoft)
            }
        }
        .font(Theme.text(14, weight: .semibold))
        .foregroundStyle(Theme.inkStrong)
    }

    @ViewBuilder
    private func cardButtons(_ onSave: @escaping () -> Void) -> some View {
        if let onDiscard, state == .dirty || state == .invalid {
            PMButton(L("Discard"), variant: .outline, size: .compact, fullWidth: !wide, action: onDiscard)
        }
        PMButton(saveLabel, systemImage: "save", size: .compact, fullWidth: !wide, isWorking: state == .saving, action: onSave)
            .disabled(state != .dirty)
    }

    // MARK: SettingsPanel's bar

    private func settingsBar(_ onSave: @escaping () -> Void) -> some View {
        let busy = state == .saving
        let enabled = floatingBar ? !busy : (state == .dirty && !busy)
        return Group {
            if wide {
                HStack(spacing: 8) {
                    if floatingBar {
                        HStack(spacing: 8) {
                            Circle().fill(Theme.mango).frame(width: 8, height: 8)
                            Text(busy ? L("Saving…") : L("Unsaved changes"))
                        }
                        .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    }
                    Spacer(minLength: 8)
                    if let onDiscard { PMButton(L("Discard"), variant: .outline, action: onDiscard).disabled(!enabled) }
                    PMButton(busy ? L("Saving…") : saveLabel, systemImage: "save", isWorking: busy, action: onSave).disabled(!enabled)
                }
            } else {
                // A phone: the buttons stacked, Save on top.
                VStack(spacing: 8) {
                    PMButton(busy ? L("Saving…") : saveLabel, systemImage: "save", fullWidth: true, isWorking: busy, action: onSave).disabled(!enabled)
                    if let onDiscard { PMButton(L("Discard"), variant: .outline, fullWidth: true, action: onDiscard).disabled(!enabled) }
                }
            }
        }
        .padding(.horizontal, gutter)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(floatingBar ? AnyShapeStyle(Theme.wash(Theme.mango, 12)) : AnyShapeStyle(Theme.surfaceMuted))
        .overlay(alignment: .top) { Rectangle().fill(floatingBar ? AnyShapeStyle(Theme.mix(Theme.mango, 45, with: Theme.borderSoft)) : AnyShapeStyle(Theme.borderSoft)).frame(height: 1) }
    }
}

extension TeamSaveSection where Aside == EmptyView {
    init(title: String, subtitle: String? = nil, systemImage: String, tint: Color = Theme.blue, look: TeamCardLook = .card, floatingBar: Bool = true, state: TeamSaveState, saveLabel: String = L("Save"), invalidText: String? = nil, readOnlyText: String? = nil, onSave: (() -> Void)? = nil, onDiscard: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint, look: look, floatingBar: floatingBar, state: state, saveLabel: saveLabel, invalidText: invalidText, readOnlyText: readOnlyText, onSave: onSave, onDiscard: onDiscard, aside: { EmptyView() }, content: content)
    }
}

// MARK: - Confirmations with content

/// A serious yes/no with something to read in it (web `ProviderConfirmSheet` with children):
/// the pink header with the warning, the description under the title, a person line or the
/// consequences in the body, the red action beside the sheet's own cancel words. A plain
/// question with nothing in its body is the kit's `ConfirmSheet`.
struct TeamConfirmSheet<Content: View>: View {
    let title: String
    var message: String? = nil
    let confirmTitle: String
    var cancelTitle: String = L("Cancel")
    let action: () async throws -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        ProviderModal(title: title, subtitle: message, systemImage: "triangle-alert", accent: .pink, primaryTitle: confirmTitle, primaryVariant: .destructive, isWorking: working, cancelTitle: cancelTitle, primaryIcon: "triangle-alert") {
            working = true
            Task {
                defer { working = false }
                do {
                    try await action()
                    dismiss()
                } catch {
                    Toast.error(error)
                }
            }
        } content: {
            content()
        }
        .presentationDetents([.medium, .large])
    }
}

/// What an action does, as a bulleted list (14, soft).
struct TeamConsequences: View {
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                    Text(line)
                }
                .font(Theme.text(14))
                .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.leading, 4)
    }
}

/// A person in a sheet (web `PersonLine`): their 44 face, name and a line, in a bordered box.
struct TeamPersonLine: View {
    let name: String
    var image: String? = nil
    let detail: String
    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: name, imageURL: image, size: 44, tint: Theme.aqua)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                Text(detail).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }
}

// MARK: - A tick

// MARK: - Where someone works

/// "Every location" (which includes any added later), or the ones ticked. Empty means everywhere.
struct TeamLocationChoiceList: View {
    let locations: [ProviderLocation]
    @Binding var value: [String]
    var disabled: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            row(on: value.isEmpty, round: true, title: L("Every location"), subtitle: L("Including any added later.")) { value = [] }
            ForEach(locations) { location in
                let on = value.contains(location.id)
                row(on: on, round: false, title: location.name, subtitle: location.address) {
                    value = on ? value.filter { $0 != location.id } : value + [location.id]
                }
            }
        }
        .disabled(disabled)
    }

    private func row(on: Bool, round: Bool, title: String, subtitle: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Tick(on: on, style: .choice)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    if let subtitle = subtitle?.nonEmpty { Text(subtitle).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(on ? AnyShapeStyle(Theme.wash(Theme.blue, 10)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(on ? Theme.blue : Theme.borderSoft, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stats

// MARK: - A number with − and +

struct TeamCountStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...10
    var disabled: Bool = false

    var body: some View {
        // The web's stepper: one bordered capsule, two 36 round buttons, the number in Fredoka 24.
        HStack(spacing: 8) {
            step("minus", label: L("One less")) { value = max(range.lowerBound, value - 1) }
                .disabled(disabled || value <= range.lowerBound)
            Text("\(value)").font(.brandHeading(24, relativeTo: .title2)).foregroundStyle(Theme.inkStrong).frame(minWidth: 32)
                .accessibilityLabel(L("Pets at once"))
            step("plus", label: L("One more")) { value = min(range.upperBound, value + 1) }
                .disabled(disabled || value >= range.upperBound)
        }
        .padding(4)
        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    private func step(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Glyph(icon, size: 16).foregroundStyle(Theme.inkStrong)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(TeamStepButtonStyle())
        .accessibilityLabel(label)
    }
}

private struct TeamStepButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.surfaceMuted : Color.clear, in: Circle())
            .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - A small "Changed" tag

// MARK: - The web

enum TeamWeb {
    /// A page of the web workspace, for what is done there.
    static func url(_ path: String, query: [String: String] = [:]) -> URL {
        var components = URLComponents(url: APIConfig.webOrigin.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) } }
        return components.url!
    }
}

/// A row that opens a page of the web, saying so.
struct TeamWebRow: View {
    let title: String
    let detail: String
    var systemImage: String = "globe"
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(url) } label: {
            HStack(spacing: 12) {
                Glyph(systemImage, size: 16)
                    .foregroundStyle(Theme.blue)
                    .frame(width: 36, height: 36)
                    .background(Theme.surfaceMuted, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    Text(detail).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 8)
                Glyph("external-link", size: 16).foregroundStyle(Theme.inkSoft)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Days ("YYYY-MM-DD")

enum TeamDays {
    private static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Noon UTC of a day key, for formatting and arithmetic.
    static func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    static func key(utc date: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    /// The day a DatePicker shows (the device's calendar) as a key.
    static func key(picked date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    /// A key as the date a DatePicker should show.
    static func picked(_ key: String) -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) ?? Date()
    }

    static func add(_ key: String, _ days: Int) -> String {
        guard let date = date(key), let next = utc.date(byAdding: .day, value: days, to: date) else { return key }
        return Self.key(utc: next)
    }

    /// Days from `start` to `end`, both counted.
    static func count(_ start: String, _ end: String) -> Int {
        guard let a = date(start), let b = date(end) else { return 1 }
        return Int((b.timeIntervalSince(a) / 86_400).rounded()) + 1
    }

    /// Today in a time zone.
    static func today(_ zone: String?) -> String {
        DateText.dayKey(Date(), zone: zone.flatMap(TimeZone.init(identifier:)) ?? Workspace.shared.timeZone)
    }

    /// "monday"… of a day key.
    static func weekday(_ key: String) -> String {
        guard let date = date(key) else { return "monday" }
        let index = utc.component(.weekday, from: date) // 1 = Sunday
        return ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"][index - 1]
    }

    private static func format(_ key: String, _ template: String) -> String {
        guard let date = date(key) else { return key }
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    /// "Jue 25 dic" · "Mié 24 dic – Vie 26 dic" (the year only when it isn't this one).
    static func rangeLabel(_ start: String, _ end: String?, today: String) -> String {
        let last = (end ?? start) > start ? (end ?? start) : start
        let showYear = start.prefix(4) != today.prefix(4) || last.prefix(4) != today.prefix(4)
        let template = showYear ? "EEEdMMMyyyy" : "EEEdMMM"
        let text = last == start ? format(start, template) : "\(format(start, template)) – \(format(last, template))"
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "DIC" over "25".
    static func tile(_ key: String) -> (month: String, day: String) {
        (format(key, "MMM").uppercased(), String(Int(key.suffix(2)) ?? 1))
    }

    /// "25 dic".
    static func short(_ key: String) -> String { format(key, "dMMM") }

    /// "Mié 4 nov".
    static func weekdayLabel(_ key: String) -> String {
        let text = format(key, "EEEdMMM")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Upcoming (soonest first) and past (most recent first).
    static func sortSpans<T>(_ spans: [T], today: String, start: (T) -> String, end: (T) -> String) -> (current: [T], past: [T]) {
        let current = spans.filter { end($0) >= today }.sorted { (start($0), end($0)) < (start($1), end($1)) }
        let past = spans.filter { end($0) < today }.sorted { start($0) > start($1) }
        return (current, past)
    }
}
