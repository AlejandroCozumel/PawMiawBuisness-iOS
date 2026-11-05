//
//  OptionCards.swift
//  PawMiawNegocios
//
//  The web's OptionCardGrid (option-card-grid.tsx): a choice drawn as cards,
//  each with its icon in a round badge, a Fredoka title and a line under it.
//  Chosen: the card washes in its colour (22%), takes PAW Blue's 2 pt edge,
//  its badge fills, and a blue check sits on its corner. An option that can't
//  be chosen is dashed and muted with the reason under it. One column on a
//  phone, two on an iPad. Services, record types, room kinds, catalog kinds.
//

import SwiftUI

struct OptionCard<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var description: String? = nil
    var icon: String = "circle"
    /// The card's colour (web `accentColor`; MIAW yellow when not given).
    var accent: Color = Theme.lime
    /// Shown but not choosable, with why.
    var unavailableReason: String? = nil

    var id: Value { value }

    init(_ value: Value, title: String, description: String? = nil, icon: String = "circle", accent: Color = Theme.lime, unavailableReason: String? = nil) {
        self.value = value
        self.title = title
        self.description = description
        self.icon = icon
        self.accent = accent
        self.unavailableReason = unavailableReason
    }
}

struct OptionCards<Value: Hashable>: View {
    let options: [OptionCard<Value>]
    @Binding var selection: Value?
    /// The field is invalid: unchosen cards take the coral edge.
    var invalid: Bool = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: sizeClass == .regular ? 2 : 1), spacing: 12) {
            ForEach(options) { option in
                if let reason = option.unavailableReason {
                    unavailable(option, reason: reason)
                } else {
                    card(option)
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: selection)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous) }

    private func card(_ option: OptionCard<Value>) -> some View {
        let chosen = selection == option.value
        return Button { selection = option.value } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().fill(chosen ? AnyShapeStyle(option.accent) : AnyShapeStyle(Theme.wash(option.accent, 22)))
                    Glyph(option.icon, size: 20).foregroundStyle(chosen ? Theme.blue : Theme.inkStrong)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title).font(.brandHeading(16.8, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                        .fixedSize(horizontal: false, vertical: true)
                    if let description = option.description?.nonEmpty {
                        Text(description).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(chosen ? AnyShapeStyle(Theme.wash(option.accent, 22)) : AnyShapeStyle(Theme.surface), in: shape)
            .overlay(shape.strokeBorder(chosen ? Theme.blue : invalid ? Theme.coral : Theme.borderSoft, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                if chosen {
                    Glyph("check", size: 14)
                        .foregroundStyle(Theme.onBlue)
                        .frame(width: 24, height: 24)
                        .background(Theme.blue, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                        .offset(x: 6, y: -6)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func unavailable(_ option: OptionCard<Value>, reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Glyph(option.icon, size: 20).foregroundStyle(Theme.inkSoft)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title).font(.brandHeading(16.8, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                    if let description = option.description?.nonEmpty {
                        Text(description).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    }
                }
                Spacer(minLength: 0)
            }
            .opacity(0.6)
            Text(reason).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: shape)
        .overlay(shape.strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
        .accessibilityElement(children: .combine)
        .accessibilityHint(reason)
    }
}

extension OptionCards {
    /// A non-optional selection (a choice that always has a value).
    init(options: [OptionCard<Value>], selection: Binding<Value>, invalid: Bool = false) {
        self.options = options
        self._selection = Binding<Value?>(get: { selection.wrappedValue }, set: { if let value = $0 { selection.wrappedValue = value } })
        self.invalid = invalid
    }
}
