//
//  SvcPieces.swift
//  PawMiawNegocios
//
//  The few web pieces only the Services pages draw (the tab bar, chips, the
//  settings card, the save bar and the context pills are the kit's): the care
//  card's handling tags, the report's choice chip, the "Asked for" box, the
//  "couldn't load" line and the message preview.
//

import SwiftUI

// MARK: - Chips

/// The care card's handling tags (web `HandlingChips`): what can hurt someone or
/// lose the pet first, in red with the shield; a nervous pet in mango; the rest pink.
struct SvcHandlingChips: View {
    let tags: [String]
    /// The home visit's card shows them a size up.
    var large: Bool = false

    var body: some View {
        if !tags.isEmpty {
            FlowLayout(spacing: 4) {
                ForEach(tags.sorted { SvcHandling.warn.contains($0) && !SvcHandling.warn.contains($1) }, id: \.self) { tag in
                    let warn = SvcHandling.warn.contains(tag)
                    HStack(spacing: 4) {
                        if warn { Glyph("shield-alert", size: 12) }
                        Text(SvcReportText.option(tag)).lineLimit(1)
                    }
                    .font(.brandText(large ? 12.5 : 10.9, weight: .heavy))
                    .foregroundStyle(warn ? Theme.destructive : Theme.inkStrong)
                    .padding(.horizontal, large ? 10 : 8)
                    .padding(.vertical, large ? 4 : 2)
                    .background(warn ? AnyShapeStyle(Theme.wash(Theme.destructive, 12)) : tag == "nervous" ? AnyShapeStyle(Theme.wash(Theme.mango, 32)) : AnyShapeStyle(Theme.wash(Theme.pink, 22)), in: Capsule())
                }
            }
        }
    }
}

/// One choice of a report or a care card (web: the `min-h-8` option buttons):
/// 32 tall, a 2 pt border; chosen = solid PAW Blue, or red for a worry ("Diarrhea", "Bites").
/// `wash`: chosen = a blue border on an aqua wash (a session's "A walk / A class").
struct SvcChoiceChip: View {
    let title: String
    let isSelected: Bool
    var danger: Bool = false
    var wash: Bool = false
    var height: CGFloat = 32
    let action: () -> Void

    private var ink: Color {
        guard isSelected else { return Theme.inkSoft }
        if danger { return Theme.destructive }
        return wash ? Theme.inkStrong : Theme.onBlue
    }

    private var fill: AnyShapeStyle {
        guard isSelected, !danger else { return AnyShapeStyle(Color.clear) }
        return wash ? AnyShapeStyle(Theme.wash(Theme.aqua, 18)) : AnyShapeStyle(Theme.blue)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.brandText(14, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, wash ? 14 : 12)
                .frame(minHeight: height)
                .foregroundStyle(ink)
                .background(fill, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? (danger ? Theme.destructive : Theme.blue) : Theme.borderSoft, lineWidth: 2))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// What the owner asked the groomer for, in their words (web: the aqua "Asked for" box).
struct SvcAskedBox: View {
    let text: String
    var lineLimit: Int? = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Eyebrow(L("Asked for"), size: 9.9)
            Text(text).font(Theme.text(14)).foregroundStyle(Theme.inkStrong).lineLimit(lineLimit)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(Theme.aqua, 14), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
    }
}

/// A list that could not load (web `GroomLoadError` / `VisitsLoadError`): one line
/// and a way to try again on a dashed card, never a blank page.
struct SvcLoadError: View {
    let message: String
    var compact: Bool = true
    let retry: () async -> Void
    @State private var retrying = false

    var body: some View {
        VStack(spacing: 8) {
            Text(message).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
            PMButton(L("Try again"), systemImage: "rotate-cw", variant: .outline, size: compact ? .compact : .regular, isWorking: retrying) {
                Task {
                    retrying = true
                    await retry()
                    retrying = false
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}

// MARK: - Settings

/// The message as it lands in the chat: a bubble in WhatsApp's green (web: the settings' preview).
struct SvcMessagePreview: View {
    let text: String
    let standard: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(standard ? L("Preview · standard message") : L("Preview"), size: 10.6)
            Text(text)
                .font(Theme.text(14))
                .foregroundStyle(Theme.inkStrong)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.wash(ProviderState.done.color, 18), in: UnevenRoundedRectangle(topLeadingRadius: 17.6, bottomLeadingRadius: 4.8, bottomTrailingRadius: 17.6, topTrailingRadius: 17.6, style: .continuous))
        }
    }
}

/// The "Add:" row of a message's placeholders ({pet}, {client}…), each a small mono pill.
struct SvcPlaceholderRow: View {
    let placeholders: [String]
    let onAdd: (String) -> Void
    var trailing: String? = nil
    var extra: (title: String, action: () -> Void)? = nil

    var body: some View {
        FlowLayout(spacing: 6) {
            Text(L("Add:")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            ForEach(placeholders, id: \.self) { token in
                Button { onAdd(token) } label: {
                    Text(token)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.inkStrong)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 28)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            if let extra {
                Button(action: extra.action) {
                    Text(extra.title).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue).padding(.horizontal, 10).frame(minHeight: 28)
                }
                .buttonStyle(.plain)
            }
            if let trailing { Text(trailing).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
        }
    }
}
