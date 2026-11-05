//
//  Buttons.swift
//  PawMiawNegocios
//
//  The one button of the business side (web: the shared `Button`, variants
//  default/outline/destructive, sizes default 48 pt / compact 40 pt). Never
//  repaint a button's height, corners or colour on a screen: pick a variant
//  and a size. Small round icon controls are not action buttons.
//

import SwiftUI

/// primary (solid PAW Blue), outline (2 pt blue edge), destructive (2 pt red edge on its
/// wash), ghost (no edge, no fill, ink-strong: web `variant="ghost"`), link (blue bold words,
/// no edge, no fill: the web's inline links, "Abrir la agenda", "Ver todo").
enum ButtonVariant { case primary, outline, destructive, ghost, link }
/// regular 48 pt (h-12), modal 44 pt (a sheet's footer, h-11), compact 40 pt (a toolbar's
/// or a row's, h-10), header 36 pt (a module header's actions, an empty state's on a
/// phone), slim 32 pt (a board's links, h-8), small 28 pt (web `size="sm"`, h-7: 12.8 text,
/// 14 icon — a settings card's save bar).
enum ButtonSize { case regular, compact, header, modal, slim, small }

struct PMButtonStyle: ButtonStyle {
    var variant: ButtonVariant = .primary
    var size: ButtonSize = .regular
    var fullWidth: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    private var height: CGFloat {
        switch size {
        case .regular: 48
        case .modal: 44
        case .compact: 40
        case .header: 36
        case .slim: 32
        case .small: 28
        }
    }

    private var padding: CGFloat {
        // A link sits in the text's line: no inset, except the board's 32 pt links (web `h-8 px-3`).
        if variant == .link { return size == .slim ? 12 : 0 }
        return switch size {
        case .header: 14
        case .modal: 20
        case .slim: 12
        case .small: 10
        default: 16
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // text-sm font-medium, as on the web (sm: 0.8rem); a link is bold.
            .font(.brandText(size == .small ? 12.8 : 14, weight: variant == .link ? .bold : .semibold))
            .lineLimit(1)
            // A long label in a half-width footer button shrinks a little before it would cut.
            .minimumScaleFactor(0.8)
            .padding(.horizontal, padding)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .circular))
            .overlay {
                switch variant {
                case .outline: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .circular).strokeBorder(Theme.blue, lineWidth: 2)
                case .destructive: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .circular).strokeBorder(Theme.coral, lineWidth: 2)
                case .primary, .ghost, .link: EmptyView()
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch variant {
        case .primary: Theme.onBlue
        case .outline, .link: Theme.blue
        case .destructive: Theme.coral
        case .ghost: Theme.inkStrong
        }
    }

    private var background: AnyShapeStyle {
        switch variant {
        case .primary: AnyShapeStyle(Theme.blue)
        case .outline: AnyShapeStyle(Theme.surface)
        case .destructive: AnyShapeStyle(Theme.coral.opacity(0.1))
        case .ghost, .link: AnyShapeStyle(Color.clear)
        }
    }
}

extension ButtonStyle where Self == PMButtonStyle {
    static func pm(_ variant: ButtonVariant = .primary, size: ButtonSize = .regular, fullWidth: Bool = false) -> PMButtonStyle {
        PMButtonStyle(variant: variant, size: size, fullWidth: fullWidth)
    }
}

/// A button with a title, an optional icon (leading, or trailing with `trailingIcon`) and a
/// working state.
struct PMButton: View {
    let title: String
    var systemImage: String? = nil
    var trailingIcon: String? = nil
    var variant: ButtonVariant = .primary
    var size: ButtonSize = .regular
    var fullWidth: Bool = false
    var isWorking: Bool = false
    /// Paints a ghost or link button's words (a destructive ghost: "Rechazar"; a grey link).
    var tint: Color? = nil
    let action: () -> Void
    @Environment(\.headerButtons) private var inHeader

    init(_ title: String, systemImage: String? = nil, trailingIcon: String? = nil, variant: ButtonVariant = .primary, size: ButtonSize = .regular, fullWidth: Bool = false, isWorking: Bool = false, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.trailingIcon = trailingIcon
        self.variant = variant
        self.size = size
        self.fullWidth = fullWidth
        self.isWorking = isWorking
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            PMButtonContent(title: title, icon: systemImage, trailingIcon: trailingIcon, isWorking: isWorking, variant: variant, size: size, tint: tint)
        }
        .buttonStyle(.pm(variant, size: inHeader && (variant != .link && variant != .ghost) ? .header : size, fullWidth: fullWidth))
        .disabled(isWorking)
    }
}

/// A button's inside (its icon, words and working spinner): also the label of a
/// `NavigationLink` or `Menu` drawn with `.buttonStyle(.pm(…))`.
struct PMButtonContent: View {
    let title: String
    var icon: String? = nil
    var trailingIcon: String? = nil
    var isWorking: Bool = false
    var variant: ButtonVariant = .primary
    var size: ButtonSize = .regular
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            if isWorking {
                ProgressView().tint(spinnerTint).controlSize(.small)
            } else if let icon {
                Glyph(icon, size: size == .small ? 14 : 16)
            }
            Text(title)
            if let trailingIcon { Glyph(trailingIcon, size: size == .small ? 14 : 16) }
        }
        .modifier(OptionalTint(color: tint))
    }

    private var spinnerTint: Color {
        switch variant {
        case .primary: Theme.onBlue
        case .outline, .link: Theme.blue
        case .destructive: Theme.coral
        case .ghost: tint ?? Theme.inkStrong
        }
    }
}

private struct OptionalTint: ViewModifier {
    let color: Color?
    func body(content: Content) -> some View {
        if let color { content.foregroundStyle(color) } else { content }
    }
}

/// The round icon control's look (web: the 36 round "More" trigger, a row's +, a ghost
/// icon button): the glyph in ink-soft on a white circle with a hairline, or bare with
/// `bordered: false`. The label of a `Menu` (⋯) as well as of `IconCircleButton`.
struct IconCircleLabel: View {
    var systemImage: String = "ellipsis"
    var size: CGFloat = 36
    var tint: Color = Theme.inkSoft
    /// false: no ring and no fill (web `variant="ghost" size="icon"`, Home's ⋯).
    var bordered: Bool = true

    var body: some View {
        Glyph(systemImage, size: 16)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(bordered ? AnyShapeStyle(Theme.surface) : AnyShapeStyle(Color.clear), in: Circle())
            .overlay { if bordered { Circle().strokeBorder(Theme.borderSoft, lineWidth: 1) } }
            .contentShape(Circle())
    }
}

/// A small round icon control (a row's +, a corner ✕): not an action button.
struct IconCircleButton: View {
    let systemImage: String
    var label: String
    var tint: Color = Theme.inkSoft
    var size: CGFloat = 36
    var bordered: Bool = true
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    init(systemImage: String, label: String, tint: Color = Theme.inkSoft, size: CGFloat = 36, bordered: Bool = true, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.tint = tint
        self.size = size
        self.bordered = bordered
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            IconCircleLabel(systemImage: systemImage, size: size, tint: tint, bordered: bordered)
                .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
