//
//  ProviderModal.swift
//  PawMiawNegocios
//
//  Every sheet of the business side (web: components/app/provider-modal):
//  the header takes the modal's accent colour with its icon in a pebble, the
//  body is white with stitched dividers, there is no ✕. Cancel closes; a
//  swipe closes at once when nothing changed, and while something did the
//  sheet stays and Cancel asks "¿Descartar los cambios?".
//
//      .sheet(isPresented: $adding) {
//          ProviderModal(title: L("New client"), systemImage: "person.badge.plus", accent: .aqua,
//                        isDirty: !name.isEmpty, form: form, primaryTitle: L("Save"), isWorking: saving) {
//              save()
//          } content: { … fields … }
//      }
//

import SwiftUI
import UIKit

/// The colour a sheet's header takes (web `accent` of `ProviderModal`).
enum ModalAccent: Equatable {
    case butter, aqua, pink, lavender, mint, coral, mango, lime
    /// `--brand-sky` (#eaf4ff): the settings history's pale blue.
    case sky
    /// `--ink-soft`: a quiet, grey sheet (a death recorded, a stay ended).
    case grey
    /// `--hue-peach`: an orange category (a surgery room, a sale).
    case peach
    /// Any category hue (a room's kind, a role): `ROOM_KIND_HUE`, `ROLE_HUE`.
    case hue(Hue)
    /// `--brand-teal`: PAW Blue (a visit's "Sí vino", a sheet about the business itself).
    case blue

    var color: Color {
        switch self {
        case .butter: Theme.butter
        case .aqua: Theme.aqua
        case .pink: Theme.pink
        case .lavender: Theme.lavender
        case .mint: Hue.mint.color
        case .coral: Theme.coral
        case .sky: Theme.blueWash
        case .mango: Theme.mango
        case .lime: Theme.lime
        case .grey: Theme.inkSoft
        case .peach: Hue.peach.color
        case .hue(let hue): hue.color
        case .blue: Theme.blue
        }
    }

    var ink: Color { self == .coral ? .white : Theme.inkOnBright }
}

/// A button of a sheet's footer besides its primary action and Cancel (web
/// `ProviderModalAction intent="secondary" | "danger"`): "Archive", "Admit without the gate".
struct ModalAction: Identifiable {
    let id = UUID()
    let title: String
    var icon: String? = nil
    var variant: ButtonVariant = .outline
    var isWorking: Bool = false
    var disabled: Bool = false
    /// The words' ink (web: a secondary action written in red, "Admit without the gate").
    var tint: Color? = nil
    let action: () -> Void

    init(_ title: String, icon: String? = nil, variant: ButtonVariant = .outline, isWorking: Bool = false, disabled: Bool = false, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.variant = variant
        self.isWorking = isWorking
        self.disabled = disabled
        self.tint = tint
        self.action = action
    }
}

/// A multi-step sheet's steps (web `ProviderModalSteps`): a 27 dot per step — "01" on white
/// (or the step's icon), PAW Blue with a check once done — the current one blue inside a 34
/// white capsule with its name; 10 pt connectors between them, blue once done. Pass it to
/// `ProviderModal(steps:)`, which shows it on its own row under the title.
struct ModalSteps: View {
    let steps: [String]
    /// Icons in place of the numbers (web `icons`).
    var icons: [String]? = nil
    let current: Int

    init(_ steps: [String], icons: [String]? = nil, current: Int) {
        self.steps = steps
        self.icons = icons
        self.current = current
    }

    /// Steps given as (title, icon) pairs.
    init(steps: [(title: String, icon: String)], current: Int) {
        self.steps = steps.map(\.title)
        self.icons = steps.map(\.icon)
        self.current = current
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(steps.indices, id: \.self) { index in
                if index > 0 {
                    Capsule().fill(index <= current ? AnyShapeStyle(Theme.blue) : AnyShapeStyle(Theme.inkStrong.opacity(0.18)))
                        .frame(width: 10.4, height: 2)
                }
                step(index)
            }
        }
        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.42), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LF("Step %d of %d", current + 1, steps.count) + (steps.indices.contains(current) ? ". " + steps[current] : ""))
    }

    private func step(_ index: Int) -> some View {
        let isCurrent = index == current
        return HStack(spacing: 6.4) {
            dot(index)
            if isCurrent {
                Text(steps[index]).font(.brandText(12.5, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
            }
        }
        .padding(.leading, 3.2)
        .padding(.trailing, isCurrent ? 13.6 : 3.2)
        .frame(height: 33.6)
        .background(isCurrent ? Theme.surface : Color.clear, in: Capsule())
        .overlay { if isCurrent { Capsule().strokeBorder(Theme.inkStrong.opacity(0.1), lineWidth: 1.5) } }
    }

    private func dot(_ index: Int) -> some View {
        let lit = index <= current
        return ZStack {
            Circle().fill(lit ? AnyShapeStyle(Theme.blue) : AnyShapeStyle(Theme.surface))
            if !lit { Circle().strokeBorder(Theme.inkStrong.opacity(0.14), lineWidth: 1.5) }
            if index < current {
                Glyph("check", size: 16).foregroundStyle(Theme.onBlue)
            } else if let icon = icons?[safe: index] {
                Glyph(icon, size: 14.4).foregroundStyle(lit ? Theme.onBlue : Theme.inkSoft)
            } else {
                Text(String(format: "%02d", index + 1)).font(.brandText(10.9, weight: .heavy)).foregroundStyle(lit ? Theme.onBlue : Theme.inkSoft)
            }
        }
        .frame(width: 27.2, height: 27.2)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

struct ProviderModal<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String = "square.and.pencil"
    var accent: ModalAccent = .aqua
    var isDirty: Bool = false
    var form: FormState? = nil
    var primaryTitle: String? = nil
    var primaryVariant: ButtonVariant = .primary
    var isWorking: Bool = false
    var cancelTitle: String = L("Cancel")
    /// A multi-step sheet's steps: on their own row under the title, as on the web.
    var steps: ModalSteps? = nil
    /// Past the first step: the footer's Cancel becomes "‹ Back" and calls this.
    var onBack: (() -> Void)? = nil
    /// More footer buttons, between the primary action and Cancel ("Archive", "Without the gate").
    var secondaryActions: [ModalAction] = []
    /// The primary action's icon (a check, a save disk), when the web's has one.
    var primaryIcon: String? = nil
    var primaryDisabled: Bool = false
    /// A line over the footer's buttons (a total, the vaccines' state), as the web's footer carries it.
    var footerSummary: AnyView? = nil
    /// False where the web's footer has no Cancel (a sheet whose work is done: "Done", "Invite someone else").
    var showsCancel: Bool = true
    /// A photo in the pebble instead of the icon (a pet's sheet).
    var pebbleImageURL: String? = nil
    /// False for a question with nothing between its header and its answer: the sheet fits them.
    var showsBody: Bool = true
    var onPrimary: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    @Environment(\.modalAsPage) private var asPage
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDiscard = false
    @State private var stepDirection: CGFloat = 1
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @StateObject private var fallbackForm = FormState()

    init(title: String, subtitle: String? = nil, systemImage: String = "square.and.pencil", accent: ModalAccent = .aqua, isDirty: Bool = false, form: FormState? = nil, primaryTitle: String? = nil, primaryVariant: ButtonVariant = .primary, isWorking: Bool = false, cancelTitle: String = L("Cancel"), steps: ModalSteps? = nil, onBack: (() -> Void)? = nil, secondaryActions: [ModalAction] = [], primaryIcon: String? = nil, primaryDisabled: Bool = false, footerSummary: AnyView? = nil, showsCancel: Bool = true, pebbleImageURL: String? = nil, showsBody: Bool = true, onPrimary: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accent = accent
        self.isDirty = isDirty
        self.form = form
        self.primaryTitle = primaryTitle
        self.primaryVariant = primaryVariant
        self.isWorking = isWorking
        self.cancelTitle = cancelTitle
        self.steps = steps
        self.onBack = onBack
        self.secondaryActions = secondaryActions
        self.primaryIcon = primaryIcon
        self.primaryDisabled = primaryDisabled
        self.footerSummary = footerSummary
        self.showsCancel = showsCancel
        self.pebbleImageURL = pebbleImageURL
        self.showsBody = showsBody
        self.onPrimary = onPrimary
        self.content = content
    }


    /// A question with nothing between its header and its answer (a confirm, "Discard the changes?").
    private var hasBody: Bool { showsBody && Content.self != EmptyView.self }

    var body: some View {
        VStack(spacing: 0) {
            header
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            if hasBody { scrollBody }
            footer
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
            // No body: the buttons sit right under the title; spare height goes under them.
            if !hasBody { Spacer(minLength: 0) }
        }
        // A sheet with no body is exactly its header and footer, 16 pt under the buttons.
        .modifier(FitsWithoutBody(fits: !hasBody, height: headerHeight + footerHeight))
        .background(Theme.surface.ignoresSafeArea())
        // The footer runs to the bottom edge (its own 24 under the buttons), not above the home indicator's gap.
        .ignoresSafeArea(.container, edges: hasBody ? .bottom : [])
        // The sheet's tinted header is its top: never a system bar over it, whether it was
        // presented in a NavigationStack or opened as a page (booking, a record, the checkout).
        .toolbar(.hidden, for: .navigationBar)
        .interactiveDismissDisabled(isDirty || isWorking)
        // A refused swipe (the sheet has changes) asks, as the web does: UIKit tells the sheet's delegate.
        .background(DismissAttemptReader { if isDirty && !isWorking { confirmDiscard = true } })
        // The handle is drawn in the tinted header, as on the web.
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(Theme.cardRadius)
        .presentationBackground(Theme.surface)
        .onChange(of: steps?.current) { old, new in
            stepDirection = (new ?? 0) >= (old ?? 0) ? 1 : -1
        }
        // The web's discard card: pink, the eraser, "Keep editing" beside "Discard".
        .sheet(isPresented: $confirmDiscard) {
            DiscardChangesSheet { confirmDiscard = false; dismiss() }
        }
    }

    private var scrollBody: some View {
            ScrollView {
                FormScroll(form: form ?? fallbackForm) {
                    // A step change slides, as the web's ProviderModalStage: in from 20 pt
                    // on the side it comes from, out 12 pt the other way, 220 ms.
                    VStack(alignment: .leading, spacing: 16) { content() }
                        .id(steps?.current ?? 0)
                        .transition(.asymmetric(
                            insertion: .offset(x: 20 * stepDirection).combined(with: .opacity),
                            removal: .offset(x: -12 * stepDirection).combined(with: .opacity)
                        ))
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .padding(.bottom, 16)
                        .frame(maxWidth: 704, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }
            }
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22), value: steps?.current)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.surface)
    }

    /// The web's header: the accent at 26% over the surface, a grab handle,
    /// a tilted pebble (accent 72%) with the icon, the title in Fredoka 20,
    /// the steps on their own row, a 1.5 pt rule of the accent under it.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // A sheet opened as a page can't be swiped away: no handle.
            if !asPage {
                Capsule().fill(Theme.inkStrong.opacity(0.22)).frame(width: 41.6, height: 4.8).padding(.top, 8)
                    .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 12) {
                titleRow
                if let steps { steps }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(Rectangle().fill(Theme.wash(accent.color, 26)).ignoresSafeArea(edges: asPage ? .top : []))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.mix(accent.color, 45, with: Theme.borderSoft)).frame(height: 1.5)
        }
    }

    private var titleRow: some View {
            HStack(alignment: .center, spacing: 13.6) {
                ZStack {
                    Circle().fill(Theme.wash(accent.color, 72))
                    Glyph(systemImage, size: 20.8)
                        .foregroundStyle(accent == .coral ? Theme.destructive : Theme.inkStrong)
                        .rotationEffect(.degrees(4))
                    if let url = APIConfig.assetURL(pebbleImageURL) {
                        AsyncImage(url: url) { phase in if let image = phase.image { image.resizable().scaledToFill() } }
                            .clipShape(Circle())
                            .rotationEffect(.degrees(4))
                    }
                }
                .frame(width: 38.4, height: 38.4)
                .rotationEffect(.degrees(-4))
                VStack(alignment: .leading, spacing: 4.8) {
                    Text(title).font(.brandHeading(20, relativeTo: .title3)).tracking(-0.2).foregroundStyle(Theme.inkStrong).lineLimit(2)
                    if let subtitle { Text(subtitle).font(Theme.text(13.1)).foregroundStyle(Theme.inkStrong.opacity(0.72)).lineLimit(3) }
                }
                Spacer(minLength: 0)
            }
    }

    /// Stacked, full width, the main action on top (44 pt), then the other actions, then
    /// Cancel (or "‹ Back" past the first step), over a 1.5 pt rule.
    /// The footer (owner, 2026-11-04): two buttons share one row, half each —
    /// Cancel or Back on the left, the action on the right; three or more stack,
    /// the action on top. The bar runs to the sheet's bottom edge with 24 under
    /// it, as the family app's sheets do, instead of floating above the home
    /// indicator's gap.
    private var footer: some View {
        let leadingCount = onBack != nil || showsCancel ? 1 : 0
        let buttonCount = (primaryTitle != nil && onPrimary != nil ? 1 : 0) + secondaryActions.count + leadingCount
        return VStack(alignment: .leading, spacing: 12) {
            if let footerSummary { footerSummary }
            if buttonCount == 2 {
                HStack(spacing: 12) {
                    // Cancel or Back on the left; with neither, the one other action takes its place.
                    if leadingCount == 1 {
                        leading
                    } else if let extra = secondaryActions.first {
                        PMButton(extra.title, systemImage: extra.icon, variant: extra.variant, size: .modal, fullWidth: true, isWorking: extra.isWorking, tint: extra.tint, action: extra.action)
                            .disabled(extra.disabled || isWorking)
                    }
                    primary
                }
            } else {
                VStack(spacing: 12) {
                    primary
                    ForEach(secondaryActions) { extra in
                        PMButton(extra.title, systemImage: extra.icon, variant: extra.variant, size: .modal, fullWidth: true, isWorking: extra.isWorking, tint: extra.tint, action: extra.action)
                            .disabled(extra.disabled || isWorking)
                    }
                    leading
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14.4)
        .padding(.bottom, hasBody ? 24 : 16)
        .frame(maxWidth: 704)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderSoft).frame(height: 1.5) }
    }

    @ViewBuilder private var primary: some View {
        if let primaryTitle, let onPrimary {
            PMButton(primaryTitle, systemImage: primaryIcon, variant: primaryVariant, size: .modal, fullWidth: true, isWorking: isWorking, action: onPrimary)
                .disabled(primaryDisabled)
        }
    }

    /// Back on a later step, else Cancel (which asks before dropping changes).
    @ViewBuilder private var leading: some View {
        if let onBack {
            PMButton(L("Back"), systemImage: "chevron-left", variant: .outline, size: .modal, fullWidth: true, action: onBack)
                .disabled(isWorking)
        } else if showsCancel {
            PMButton(cancelTitle, variant: .outline, size: .modal, fullWidth: true) {
                if isDirty { confirmDiscard = true } else { dismiss() }
            }
            .disabled(isWorking)
        }
    }
}

/// A titled part inside a modal (web `ProviderModalSection`): the title in
/// Fredoka 16.8 beside a 30 pt rounded icon chip, the fields, and a 2 pt
/// dashed rule before the next part.
struct ModalSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: Color = Theme.aqua
    /// The red * after the title (a part the web marks required, "Why *").
    var required: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14.4) {
            HStack(alignment: .center, spacing: 9.6) {
                if let systemImage {
                    Glyph(systemImage, size: 16)
                        .foregroundStyle(Theme.inkStrong)
                        .frame(width: 30.4, height: 30.4)
                        .background(Theme.wash(tint, 45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    (Text(title).foregroundColor(Theme.inkStrong) + Text(required ? " *" : "").foregroundColor(Theme.coral))
                        .font(.brandHeading(16.8, relativeTo: .headline))
                    if let subtitle { Text(subtitle).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                }
            }
            content()
            StitchedDivider().padding(.top, 8)
        }
    }
}

/// Every plain yes/no (web `ProviderConfirmSheet`): a compact sheet with the
/// pink header and the triangle, the question's words under the title, Cancel
/// (or the sheet's own words: "Keep it", "Not now") beside the red action.
/// Optionally a reason (money actions while the owner is away) or a word to
/// type before the action unlocks (`confirmWord`, web "Enter DELETE to continue").
struct ConfirmSheet: View {
    let title: String
    var message: String? = nil
    var confirmTitle: String
    var destructive: Bool = false
    /// Ask for a reason; `reasonRequired` refuses an empty one.
    var askReason: Bool = false
    var reasonRequired: Bool = false
    var reasonLabel: String = L("Reason")
    var cancelTitle: String = L("Cancel")
    /// The header's colour and icon: the web's pink and triangle unless the sheet says otherwise.
    var accent: ModalAccent = .pink
    var icon: String = "triangle-alert"
    var confirmIcon: String? = nil
    /// A word to type before the action unlocks.
    var confirmWord: String? = nil
    var confirmHint: String? = nil
    let action: (String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var typed = ""
    @State private var working = false
    @StateObject private var form = FormState()

    private var typedMatches: Bool {
        guard let confirmWord else { return true }
        return typed.trimmingCharacters(in: .whitespaces).uppercased() == confirmWord.uppercased()
    }

    var body: some View {
        ProviderModal(title: title, subtitle: message, systemImage: icon, accent: accent, isDirty: !reason.isEmpty, form: form,
                      primaryTitle: confirmTitle, primaryVariant: destructive ? .destructive : .primary, isWorking: working,
                      cancelTitle: cancelTitle, primaryIcon: confirmIcon ?? (destructive ? "triangle-alert" : nil),
                      primaryDisabled: !typedMatches, showsBody: askReason || confirmWord != nil) {
            if askReason && reasonRequired {
                guard form.check([("reason", reason.nonEmpty == nil ? L("Write the reason.") : nil)]) else { return }
            }
            working = true
            Task {
                defer { working = false }
                do {
                    try await action(reason.nonEmpty)
                    dismiss()
                } catch {
                    form.apply(error, known: ["reason": "reason"])
                }
            }
        } content: {
            if askReason {
                PMTextField(reasonLabel, text: $reason, key: "reason", form: form, optional: !reasonRequired, multiline: true)
            }
            if let confirmWord {
                VStack(alignment: .leading, spacing: 8) {
                    Text(LF("Enter %@ to continue", confirmWord)).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    if let confirmHint { Text(confirmHint).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                    TextField(confirmWord, text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .fieldChrome()
                }
            }
        }
        .modifier(ConfirmDetents(hasBody: askReason || confirmWord != nil))
    }
}

/// A confirm with a reason or a typed word takes room; a plain one fits itself (ProviderModal).
private struct ConfirmDetents: ViewModifier {
    let hasBody: Bool
    func body(content: Content) -> some View {
        if hasBody { content.presentationDetents([.medium, .large]) } else { content }
    }
}

/// The bottom inset a fitted sheet had last time (the home indicator's strip and the
/// floating card's margin), so the next one opens at its height straight away.
@MainActor enum SheetFit {
    static var lastInset: CGFloat = 0
}

/// A sheet with no body is as tall as its header and footer. iOS keeps a band under
/// a sheet's content (the home indicator, the floating card's margin): read at the
/// sheet's root, it is taken off the height asked for, and the content runs over it,
/// so what sits under the buttons is only their own 16 pt.
private struct FitsWithoutBody: ViewModifier {
    let fits: Bool
    let height: CGFloat
    @State private var inset: CGFloat = SheetFit.lastInset

    func body(content: Content) -> some View {
        if fits {
            GeometryReader { proxy in
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .onAppear { remember(proxy.safeAreaInsets.bottom) }
                    .onChange(of: proxy.safeAreaInsets.bottom) { _, value in remember(value) }
            }
            .presentationDetents(height > 0 ? [.height(max(height - inset, 60))] : [.medium])
        } else {
            content
        }
    }

    private func remember(_ value: CGFloat) {
        guard value > 0, abs(value - inset) > 0.5 else { return }
        inset = value
        SheetFit.lastInset = value
    }
}

private struct ModalAsPageKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// A `ProviderModal` shown as a pushed page (a booking, a record or the checkout opened
    /// from another screen): its header runs under the status bar and has no grab handle.
    var modalAsPage: Bool {
        get { self[ModalAsPageKey.self] }
        set { self[ModalAsPageKey.self] = newValue }
    }
}

/// "¿Descartar los cambios?" (web `ProviderConfirmModal` for discarding): a
/// compact pink sheet over the one being left; Keep editing closes it,
/// Discard closes both.
struct DiscardChangesSheet: View {
    let discard: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ProviderModal(title: L("Discard the changes?"), subtitle: L("What you wrote here won't be saved."), systemImage: "eraser", accent: .pink,
                      primaryTitle: L("Discard"), primaryVariant: .destructive, cancelTitle: L("Keep editing"), onPrimary: discard) {
            EmptyView()
        }
    }
}

/// Hears a swipe down that UIKit refused (`interactiveDismissDisabled`):
/// UIKit calls the presentation controller's delegate's
/// `presentationControllerDidAttemptToDismiss`. SwiftUI leaves that delegate
/// empty, so this one stands there for the life of the sheet.
private struct DismissAttemptReader: UIViewControllerRepresentable {
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> Reader { Reader(onAttempt: onAttempt) }
    func updateUIViewController(_ reader: Reader, context: Context) {
        reader.onAttempt = onAttempt
        reader.install()
    }

    final class Reader: UIViewController {
        var onAttempt: () -> Void

        init(onAttempt: @escaping () -> Void) {
            self.onAttempt = onAttempt
            super.init(nibName: nil, bundle: nil)
            view.isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }

        /// The sheet's own controller: the nearest ancestor UIKit presented.
        private var sheetController: UIPresentationController? {
            var current: UIViewController? = self
            while let node = current {
                if node.presentingViewController != nil, node.parent == nil { return node.presentationController }
                current = node.parent
            }
            return presentationController
        }

        func install() {
            guard let controller = sheetController else { return }
            if let existing = objc_getAssociatedObject(controller, &Reader.proxyKey) as? Proxy {
                existing.attempted = { [weak self] in self?.onAttempt() }
                if controller.delegate !== existing { existing.original = controller.delegate; controller.delegate = existing }
                return
            }
            let next = Proxy(original: controller.delegate) { [weak self] in self?.onAttempt() }
            objc_setAssociatedObject(controller, &Reader.proxyKey, next, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            controller.delegate = next
        }

        nonisolated(unsafe) static var proxyKey: UInt8 = 0
    }

    final class Proxy: NSObject, UIAdaptivePresentationControllerDelegate {
        weak var original: UIAdaptivePresentationControllerDelegate?
        var attempted: () -> Void

        init(original: UIAdaptivePresentationControllerDelegate?, attempted: @escaping () -> Void) {
            self.original = original
            self.attempted = attempted
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            attempted()
            original?.presentationControllerDidAttemptToDismiss?(presentationController)
        }

        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            original?.responds(to: aSelector) == true ? original : super.forwardingTarget(for: aSelector)
        }
    }
}
