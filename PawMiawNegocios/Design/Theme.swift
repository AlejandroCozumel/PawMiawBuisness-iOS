//
//  Theme.swift
//  PawMiawNegocios
//
//  The colours of the business side, from the family app's AuthTheme (the
//  same brand values) and the web's provider tokens (styles.css): the
//  canvas, ink, borders, the brand blue, and the six status states every
//  provider screen shares (lib/provider-colors.ts).
//

import SwiftUI
import UIKit

/// A colour of two appearances that answers to the colour scheme alone
/// (the family app's `SchemeColor`: cheaper than a dynamic UIColor).
nonisolated private struct SchemeColor: ShapeStyle, Hashable {
    let light: Color.Resolved
    let dark: Color.Resolved
    private let identity = Identity()
    private final class Identity: Sendable {}

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        environment.colorScheme == .dark ? dark : light
    }
    static func == (lhs: SchemeColor, rhs: SchemeColor) -> Bool { lhs.identity === rhs.identity }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(identity)) }
}

extension Color {
    /// A colour from 0–255 components, one for light and one for dark.
    static func scheme(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        func resolved(_ c: (Double, Double, Double)) -> Color.Resolved {
            Color.Resolved(colorSpace: .sRGB, red: Float(c.0 / 255), green: Float(c.1 / 255), blue: Float(c.2 / 255), opacity: 1)
        }
        return Color(SchemeColor(light: resolved(light), dark: resolved(dark)))
    }

    /// "#RRGGBB".
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

enum Theme {
    // MARK: Surfaces and ink (AuthTheme, web --canvas/--surface/--ink-*)
    static let canvas = Color.scheme(light: (245, 247, 251), dark: (18, 18, 20))          // --provider-canvas
    static let surface = Color.scheme(light: (255, 255, 255), dark: (28, 28, 30))
    static let surfaceMuted = Color.scheme(light: (245, 248, 251), dark: (36, 36, 40))
    static let borderSoft = Color.scheme(light: (220, 228, 237), dark: (58, 58, 64))
    static let borderStrong = Color.scheme(light: (191, 204, 220), dark: (84, 84, 92))
    static let inkStrong = Color.scheme(light: (16, 34, 59), dark: (242, 242, 247))
    static let inkSoft = Color.scheme(light: (102, 117, 138), dark: (174, 174, 184))
    static let inputBorder = Color.scheme(light: (220, 228, 237), dark: (58, 58, 64))      // = --border-soft (inputs are grey)
    static let inputFill = Color.scheme(light: (255, 255, 255), dark: (34, 34, 37))        // --input over the surface in dark
    static let switchOn = Color.scheme(light: (5, 150, 105), dark: (16, 185, 129))         // emerald-600 / 500
    static let switchOff = Color.scheme(light: (254, 202, 202), dark: (124, 66, 66))        // red-200 / red-400 40%
    static let petFace = Color(red: 241 / 255, green: 228 / 255, blue: 208 / 255)         // --pet-face
    static let petFaceInk = Color(red: 61 / 255, green: 31 / 255, blue: 20 / 255)          // --pet-face-ink (cocoa)
    /// --destructive: the red of errors and late, paler in dark.
    static let destructive = Color.scheme(light: (214, 60, 47), dark: (255, 138, 111))

    // MARK: Brand (styles.css: --brand-*; PAW Blue flips to Sky Blue in dark, as on the web)
    static let blue = Color.scheme(light: (0, 106, 252), dark: (154, 206, 250))            // --brand-teal
    static let blueFixed = Color(red: 0, green: 106 / 255, blue: 252 / 255)                // --brand-teal-fixed
    static let blueStrong = Color.scheme(light: (0, 84, 202), dark: (198, 227, 253))       // --brand-teal-strong
    /// Ink on a PAW Blue fill (--on-brand-teal / --selected-accent-ink).
    static let onBlue = Color.scheme(light: (255, 253, 249), dark: (16, 34, 59))
    static let blueText = Color.scheme(light: (0, 106, 252), dark: (154, 206, 250))
    static let blueWash = Color.scheme(light: (234, 244, 255), dark: (24, 42, 66))
    static let mango = Color(red: 252 / 255, green: 165 / 255, blue: 31 / 255)             // --brand-mango
    static let lime = Color(red: 253 / 255, green: 180 / 255, blue: 14 / 255)              // --brand-lime (MIAW Yellow)
    static let coral = Color(red: 214 / 255, green: 60 / 255, blue: 47 / 255)              // --destructive
    static let coralText = Color.scheme(light: (178, 38, 28), dark: (255, 163, 152))
    static let coralWash = Color.scheme(light: (253, 236, 234), dark: (64, 30, 28))
    static let gold = Color(red: 216 / 255, green: 154 / 255, blue: 22 / 255)
    static let goldText = Color.scheme(light: (185, 125, 6), dark: (216, 154, 22))
    static let navy = Color(red: 16 / 255, green: 34 / 255, blue: 59 / 255)
    static let butter = Color(red: 255 / 255, green: 224 / 255, blue: 122 / 255)           // --brand-butter
    static let aqua = Color(red: 154 / 255, green: 206 / 255, blue: 250 / 255)            // --brand-aqua
    static let pink = Color(red: 245 / 255, green: 194 / 255, blue: 217 / 255)            // --brand-pink
    static let lavender = Color(red: 220 / 255, green: 203 / 255, blue: 255 / 255)        // --brand-lavender
    static let apricot = Color(red: 255 / 255, green: 193 / 255, blue: 143 / 255)         // --brand-apricot
    static let cocoa = Color(red: 61 / 255, green: 31 / 255, blue: 20 / 255)              // --brand-cocoa
    /// Ink on a bright pastel fill: navy in both themes (--accent-card-ink).
    static let inkOnBright = Color(red: 16 / 255, green: 34 / 255, blue: 59 / 255)

    /// `color-mix(in srgb, color p%, var(--surface))`: a wash of a colour over the surface.
    static func wash(_ color: Color, _ percent: Double) -> some ShapeStyle { WashStyle(color: color, amount: percent / 100) }

    // MARK: Type
    static func heading(_ size: CGFloat, relativeTo style: Font.TextStyle = .title3) -> Font { .brandHeading(size, relativeTo: style) }
    static func text(_ size: CGFloat = 16, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font { .brandText(size, weight: weight, relativeTo: style) }

    static let titleFont = Font.brandHeading(24, relativeTo: .title2)
    static let sectionFont = Font.brandHeading(19, relativeTo: .title3)
    static let bodyFont = Font.brandText(16, relativeTo: .body)
    static let rowTitleFont = Font.brandText(16, weight: .bold, relativeTo: .body)
    static let captionFont = Font.brandText(13, weight: .semibold, relativeTo: .caption)
    static let smallFont = Font.brandText(14, relativeTo: .subheadline)

    // MARK: Sidebar (styles.css --provider-sidebar-*)
    static let sidebarBackground = Color.scheme(light: (245, 250, 254), dark: (28, 28, 30))
    static let sidebarBorder = Color.scheme(light: (189, 211, 239), dark: (58, 58, 64))
    static let sidebarActive = Color.scheme(light: (0, 106, 252), dark: (76, 94, 111))
    static let sidebarActiveBorder = Color.scheme(light: (177, 158, 85), dark: (127, 160, 190))
    static let sidebarActiveInk = Color.scheme(light: (255, 253, 249), dark: (242, 242, 247))
    static let sidebarControl = Color.scheme(light: (239, 247, 254), dark: (36, 36, 40))
    static let sidebarControlBorder = Color.scheme(light: (194, 213, 239), dark: (58, 58, 64))

    // MARK: Shape (styles/radius.css; --organic is 0, so every corner is even)
    static let cardRadius: CGFloat = 28      // --radius-card: cards, panels, modals, the module header
    static let boxRadius: CGFloat = 16       // --radius-box: a bordered box or row inside a card, a menu
    static let fieldRadius: CGFloat = 16     // --radius-field: inputs, selects, switch cards
    static let chipRadius: CGFloat = 14      // --radius-chip: small tiles, toggles, compact chips
    static let tickRadius: CGFloat = 6       // --radius-tick: checkboxes, swatches
    static let buttonRadius: CGFloat = 24    // --radius-button

    // MARK: Shadow (--shadow-card / --shadow-floating)
    static let cardShadow = Color.scheme(light: (16, 34, 59), dark: (0, 0, 0))
}

/// The six states every provider status is drawn in (lib/provider-colors.ts):
/// upcoming light blue · waiting mango · active blue · done green ·
/// problem red · closed grey. The same colour on every screen.
enum ProviderState: String, CaseIterable {
    case upcoming, waiting, active, done, problem, closed

    var color: Color {
        switch self {
        case .upcoming: Color(hex: "#9acefa")
        case .waiting: Color(hex: "#fca51f")
        case .active: Color.scheme(light: (0, 106, 252), dark: (91, 157, 255))
        case .done: Color.scheme(light: (48, 164, 108), dark: (76, 195, 138))
        case .problem: Color.scheme(light: (214, 60, 47), dark: (255, 122, 107))
        case .closed: Color.scheme(light: (102, 117, 138), dark: (139, 150, 168))
        }
    }

    /// Ink on the state's solid colour.
    var ink: Color {
        switch self {
        case .upcoming, .waiting: Theme.inkOnBright
        case .active, .problem, .closed: Color.scheme(light: (255, 255, 255), dark: (16, 34, 59))
        case .done: Theme.inkOnBright
        }
    }

    /// A pale wash for a row or card behind ink-strong text.
    var wash: Color { color.opacity(0.14) }

    // The web's status tables.
    static func appointment(_ status: String?) -> ProviderState {
        switch status {
        case "requested", "checked_in": .waiting
        case "scheduled": .upcoming
        case "in_progress": .active
        case "completed": .done
        case "no_show": .problem
        default: .closed
        }
    }

    static func hospital(_ status: String?) -> ProviderState {
        switch status {
        case "pending": .waiting
        case "admitted": .active
        case "discharged": .done
        default: .closed
        }
    }

    static func slot(_ state: String?) -> ProviderState {
        switch state {
        case "upcoming", "due": .upcoming
        case "late": .waiting
        case "missed": .problem
        case "given", "given_late": .done
        default: .closed
        }
    }

    static func stay(_ status: String?) -> ProviderState {
        switch status {
        case "requested": .waiting
        case "confirmed": .upcoming
        case "checked_in": .active
        case "no_show": .problem
        default: .closed
        }
    }

    static func groom(_ stage: String?) -> ProviderState {
        switch stage {
        case "scheduled": .upcoming
        case "waiting": .waiting
        case "bath", "styling": .active
        case "ready": .done
        default: .closed
        }
    }

    static func invoice(_ status: String?) -> ProviderState {
        switch status {
        case "draft", "review": .upcoming
        case "unpriced", "ready_for_payment", "open", "partially_paid": .waiting
        case "overdue", "late": .problem
        case "paid": .done
        default: .closed
        }
    }

    static func vaccine(_ status: String?) -> ProviderState {
        switch status {
        case "current": .done
        case "expires_during_stay": .waiting
        default: .problem
        }
    }

    static func confirmation(_ status: String?) -> ProviderState {
        switch status {
        case "confirmed": .done
        case "pending", "sent", "reschedule_requested": .waiting
        case "declined", "cancelled": .problem
        default: .closed
        }
    }
}

/// Category hues (a service, a room, a role, a payment method): the family
/// app's hues, so a thing is the same colour on both sides and never looks
/// like a status (`--hue-*`).
enum Hue: String, CaseIterable {
    case sky, lavender, mint, peach, butter, teal, periwinkle, grey

    var color: Color {
        switch self {
        case .sky: Color(hex: "#5aa9f5")
        case .lavender: Color(hex: "#c08ae8")
        case .mint: Color(hex: "#86cf8e")
        case .peach: Color(hex: "#ff9447")
        case .butter: Color(hex: "#ffd43b")
        case .teal: Color(hex: "#35c3be")
        case .periwinkle: Color(hex: "#8b93f7")
        case .grey: Color(hex: "#c9d2dd")
        }
    }

    var ink: Color {
        switch self {
        case .sky: Color.scheme(light: (13, 79, 148), dark: (176, 212, 250))
        case .lavender: Color.scheme(light: (91, 45, 166), dark: (226, 204, 247))
        case .mint: Color.scheme(light: (27, 102, 48), dark: (191, 232, 195))
        case .peach: Color.scheme(light: (147, 64, 10), dark: (255, 193, 143))
        case .butter: Color.scheme(light: (111, 82, 0), dark: (255, 224, 122))
        case .teal: Color.scheme(light: (12, 95, 92), dark: (165, 228, 224))
        case .periwinkle: Color.scheme(light: (52, 60, 168), dark: (201, 204, 252))
        case .grey: Color.scheme(light: (59, 70, 86), dark: (213, 220, 230))
        }
    }

    /// A stable hue for any key (a service id, a room name).
    static func stable(_ key: String) -> Hue {
        let all: [Hue] = [.sky, .lavender, .mint, .peach, .butter, .teal, .periwinkle]
        let sum = key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return all[sum % all.count]
    }

    /// A business category's hue (web PROVIDER_CATEGORY_HUE): medical blue, groomer
    /// lavender, walker peach, sitter mint, trainer butter, daycare teal, boarding periwinkle.
    static func category(_ category: String?) -> Hue {
        switch category {
        case "vet", "emergency", "pharmacy": .sky
        case "groomer": .lavender
        case "walker": .peach
        case "sitter": .mint
        case "trainer": .butter
        case "daycare": .teal
        case "boarding": .periwinkle
        default: .grey
        }
    }

    /// A business category's icon (web PROVIDER_CATEGORY_ICONS).
    static func categoryIcon(_ category: String?) -> String {
        switch category {
        case "vet": "stethoscope"
        case "groomer": "scissors"
        case "walker": "dog"
        case "sitter": "house"
        case "trainer": "dumbbell"
        case "daycare", "boarding": "building-2"
        case "pharmacy": "package"
        case "emergency": "siren"
        default: "ellipsis"
        }
    }
}

/// A colour a toned chip, tab or segment can wear (web `ChipTone`, lib/provider-colors.ts):
/// the colour it tints with while quiet, and the deep shade it is filled with under white
/// ink while chosen (`TONE_FILLS`, light / dark). The one table of those shades.
enum ChipTone: Hashable {
    /// `PAGE_TAB_TONE`: the page tabs' selection blue.
    case page
    case hue(Hue)
    case state(ProviderState)
    /// `EXPIRED_TONE`: the red of "out", deepened with cocoa.
    case expired

    static let upcoming = ChipTone.state(.upcoming)
    static let waiting = ChipTone.state(.waiting)
    static let active = ChipTone.state(.active)
    static let done = ChipTone.state(.done)
    static let problem = ChipTone.state(.problem)
    static let closed = ChipTone.state(.closed)
    static let sky = ChipTone.hue(.sky)

    /// The tone itself (`--tab-tone`).
    var color: Color {
        switch self {
        case .page: Theme.blue
        case .hue(let hue): hue.color
        case .state(let state): state.color
        // color-mix(in srgb, var(--destructive) 55%, var(--brand-cocoa))
        case .expired: Color.scheme(light: (145, 47, 35), dark: (168, 90, 70))
        }
    }

    /// The deep shade a chosen tab or chip is filled with (`--tab-fill` / `--tab-fill-dark`).
    var fill: Color {
        switch self {
        case .page: Color.scheme(light: (0, 84, 202), dark: (31, 99, 173))
        case .hue(let hue):
            switch hue {
            case .sky: Color.scheme(light: (13, 79, 148), dark: (31, 99, 173))
            case .teal: Color.scheme(light: (12, 95, 92), dark: (18, 122, 118))
            case .mint: Color.scheme(light: (27, 102, 48), dark: (35, 122, 58))
            case .butter: Color.scheme(light: (111, 82, 0), dark: (125, 93, 0))
            case .peach: Color.scheme(light: (147, 64, 10), dark: (163, 74, 16))
            case .lavender: Color.scheme(light: (91, 45, 166), dark: (107, 61, 187))
            case .periwinkle: Color.scheme(light: (52, 60, 168), dark: (64, 72, 189))
            case .grey: Color.scheme(light: (59, 70, 86), dark: (74, 86, 104))
            }
        case .state(let state):
            switch state {
            case .upcoming: Color.scheme(light: (27, 111, 179), dark: (26, 115, 192))
            case .waiting: Color.scheme(light: (173, 87, 0), dark: (184, 92, 0))
            case .active: Color.scheme(light: (0, 84, 202), dark: (31, 99, 173))
            case .done: Color.scheme(light: (26, 127, 79), dark: (33, 131, 88))
            case .problem: Color.scheme(light: (200, 55, 43), dark: (204, 65, 48))
            case .closed: Color.scheme(light: (74, 86, 104), dark: (82, 94, 112))
            }
        case .expired: Color.scheme(light: (122, 31, 31), dark: (190, 59, 83))
        }
    }
}

/// A colour mixed over another in sRGB (`color-mix(in srgb, c p%, base)`); the base defaults to the surface.
private struct WashStyle: ShapeStyle {
    let color: Color
    let amount: Double
    var base: Color = Theme.surface

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        let c = color.resolve(in: environment)
        let s = base.resolve(in: environment)
        let a = Float(amount)
        return Color.Resolved(colorSpace: .sRGB, red: s.red + (c.red - s.red) * a, green: s.green + (c.green - s.green) * a, blue: s.blue + (c.blue - s.blue) * a, opacity: 1)
    }
}

extension Theme {
    /// `color-mix(in srgb, a p%, b)`.
    static func mix(_ a: Color, _ percent: Double, with b: Color) -> some ShapeStyle { WashStyle(color: a, amount: percent / 100, base: b) }
}

extension View {
    /// The web's `--shadow-card` (0 18 36, navy 8%; black 32% in dark).
    func cardShadow() -> some View {
        modifier(CardShadow())
    }
}

private struct CardShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.shadow(color: scheme == .dark ? .black.opacity(0.32) : Theme.navy.opacity(0.08), radius: 18, x: 0, y: 18)
    }
}
