//
//  Forms.swift
//  PawMiawNegocios
//
//  Every form fails the same way (the form error standard): each invalid
//  field is marked (red border and its sentence), one toast says what to fix,
//  and the form scrolls to the FIRST invalid field.
//
//      @StateObject private var form = FormState()
//      …
//      PMTextField(L("Name"), text: $name, key: "name", form: form)
//      …
//      guard form.check([("name", name.nonEmpty == nil ? L("Write the client's name.") : nil)]) else { return }
//      do { … } catch { form.apply(error, known: ["name": "name"]) }
//
//  A ProviderModal given the form scrolls for it; a page wraps its fields in
//  `FormScroll(form:)`.
//

import SwiftUI

@MainActor
final class FormState: ObservableObject {
    @Published var errors: [String: String] = [:]
    @Published var scrollTarget: String?

    func error(_ key: String) -> String? { errors[key] }
    func clear(_ key: String) { if errors[key] != nil { errors[key] = nil } }

    /// Runs the rules in the order the fields appear; false (with toast and scroll) when any fails.
    func check(_ rules: [(String, String?)]) -> Bool {
        var found: [String: String] = [:]
        var first: String?
        for (key, message) in rules {
            guard let message else { continue }
            if found[key] == nil { found[key] = message }
            if first == nil { first = key }
        }
        errors = found
        guard let first else { return true }
        Toast.error(found.count == 1 ? (found[first] ?? "") : LF("Check the %d marked fields.", found.count))
        scrollTarget = nil
        scrollTarget = first
        return false
    }

    /// A refused save: the server's sentence for each field it named, under
    /// the form's own key (`known` maps the request's name to the form's key).
    /// Returns true when it placed at least one; the toast says the first.
    @discardableResult
    func apply(_ error: Error, known: [String: String] = [:]) -> Bool {
        guard let api = error as? APIError, !api.fields.isEmpty else {
            Toast.error(error)
            return false
        }
        var placed: [String: String] = [:]
        for (path, sentence) in api.fields.sorted(by: { $0.key < $1.key }) {
            let key = known[path] ?? known.first(where: { path.hasPrefix($0.key + ".") })?.value
            if let key, placed[key] == nil { placed[key] = sentence }
        }
        Toast.error(api.message)
        guard let first = placed.keys.first else { return false }
        errors = placed
        scrollTarget = first
        return true
    }
}

/// Scrolls to a form's first invalid field when it fails.
struct FormScroll<Content: View>: View {
    @ObservedObject var form: FormState
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            content()
                .onChange(of: form.scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .center) }
                }
        }
    }
}

/// A field's label (web `Label`, §6.5): 14 medium, sentence case, "(optional)" after it; with
/// `caps` the Store/Inventory/Pharmacy modals' `FieldLabel` — 12 bold uppercase tracked 0.12em,
/// grey, "· optional" in normal case. The required mark is coral.
struct FieldLabel: View {
    let title: String
    var caps: Bool = false
    var required: Bool = false
    var optional: Bool = false

    init(_ title: String, caps: Bool = false, required: Bool = false, optional: Bool = false) {
        self.title = title
        self.caps = caps
        self.required = required
        self.optional = optional
    }

    var body: some View {
        HStack(spacing: 4) {
            if caps {
                Text(title.uppercased()).font(.brandText(12, weight: .bold)).tracking(12 * 0.12).foregroundStyle(Theme.inkSoft)
            } else {
                Text(title).font(Theme.text(14, weight: .medium)).foregroundStyle(Theme.inkStrong)
            }
            if required { Text("*").font(.brandText(caps ? 12 : 14, weight: .bold)).foregroundStyle(Theme.coral) }
            if optional {
                if caps {
                    Text("· \(L("optional"))").font(.brandText(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                } else {
                    Text(L("(optional)")).font(Theme.text(13)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A field's label, its control and (when invalid) its sentence. `caps`: the uppercase label
/// of the Store/Inventory/Pharmacy modals (6 to the control); `strongHint`: a hint that says a
/// result (14 semibold navy) rather than a help line.
struct FormField<Control: View>: View {
    let label: String
    var key: String? = nil
    var hint: String? = nil
    var form: FormState? = nil
    var optional: Bool = false
    var caps: Bool = false
    var required: Bool = false
    var strongHint: Bool = false
    @ViewBuilder let control: () -> Control

    private var error: String? { key.flatMap { form?.error($0) } }

    var body: some View {
        // The web's Label: 14 medium, sentence case; 8 to the control; errors 12 medium coral.
        VStack(alignment: .leading, spacing: caps ? 6 : 8) {
            FieldLabel(label, caps: caps, required: required, optional: optional)
            control()
            if let error {
                Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral)
            } else if let hint = hint?.nonEmpty {
                Text(hint)
                    .font(Theme.text(strongHint ? 14 : 12, weight: strongHint ? .semibold : .regular))
                    .foregroundStyle(strongHint ? Theme.inkStrong : Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .id(key ?? label)
    }
}

/// The field chrome (web `Input`): 48 pt, 16 corners, a 1 pt grey border; on
/// focus the border turns mango with a 3 pt mango ring; invalid is coral with a
/// coral ring. Text 16, multiline from 112 tall.
struct FieldChrome: ViewModifier {
    var invalid: Bool
    var multiline: Bool = false
    @FocusState private var focused: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous) }

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .font(Theme.bodyFont)
            .foregroundStyle(Theme.inkStrong)
            .padding(.horizontal, 16)
            .padding(.vertical, multiline ? 12 : 0)
            .frame(minHeight: multiline ? 112 : 48, alignment: multiline ? .topLeading : .leading)
            .background(Theme.inputFill, in: shape)
            .overlay(shape.strokeBorder(invalid ? Theme.coral : (focused ? Theme.mango : Theme.borderSoft), lineWidth: 1))
            .overlay {
                if focused || invalid {
                    shape.inset(by: -3).strokeBorder(invalid ? Theme.coral.opacity(0.2) : Theme.mango.opacity(0.5), lineWidth: 3)
                }
            }
            .animation(.easeOut(duration: 0.18), value: focused)
    }
}

extension View {
    func fieldChrome(invalid: Bool = false, multiline: Bool = false) -> some View {
        modifier(FieldChrome(invalid: invalid, multiline: multiline))
    }
}

/// A text field under its label. `caps`/`required`: the Store/Inventory/Pharmacy modals'
/// uppercase label. `number`: a quantity box — bold and tabular (18 for a count or a delivery,
/// 16 with `.plain`), the number pad, a unit after it (`suffix`).
struct PMTextField: View {
    enum Number { case none, large, plain }

    let label: String
    @Binding var text: String
    var key: String? = nil
    var form: FormState? = nil
    var prompt: String? = nil
    var hint: String? = nil
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var optional: Bool = false
    var multiline: Bool = false
    var secure: Bool = false
    var caps: Bool = false
    var required: Bool = false
    var strongHint: Bool = false
    var number: Number = .none
    var suffix: String? = nil
    /// Lines a multiline box shows before it scrolls (3…8 unless told).
    var lines: ClosedRange<Int> = 3...8

    init(_ label: String, text: Binding<String>, key: String? = nil, form: FormState? = nil, prompt: String? = nil, hint: String? = nil, keyboard: UIKeyboardType = .default, capitalization: TextInputAutocapitalization = .sentences, optional: Bool = false, multiline: Bool = false, secure: Bool = false, caps: Bool = false, required: Bool = false, strongHint: Bool = false, number: Number = .none, suffix: String? = nil, lines: ClosedRange<Int> = 3...8) {
        self.label = label
        self._text = text
        self.key = key
        self.form = form
        self.prompt = prompt
        self.hint = hint
        self.keyboard = keyboard
        self.capitalization = capitalization
        self.optional = optional
        self.multiline = multiline
        self.secure = secure
        self.caps = caps
        self.required = required
        self.strongHint = strongHint
        self.number = number
        self.suffix = suffix
        self.lines = lines
    }

    private var invalid: Bool { key.flatMap { form?.error($0) } != nil }

    var body: some View {
        FormField(label: label, key: key, hint: hint, form: form, optional: optional, caps: caps, required: required, strongHint: strongHint) {
            Group {
                if number != .none {
                    HStack(spacing: 6) {
                        TextField(prompt ?? "0", text: $text)
                            .keyboardType(keyboard == .default ? .numberPad : keyboard)
                            .font(Theme.text(number == .large ? 18 : 16, weight: .bold))
                            .monospacedDigit()
                        if let suffix { Text(suffix).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                    }
                } else if secure {
                    SecureField(prompt ?? "", text: $text)
                } else if multiline {
                    TextField(prompt ?? "", text: $text, axis: .vertical).lineLimit(lines)
                } else {
                    TextField(prompt ?? "", text: $text)
                }
            }
            .keyboardType(number != .none ? (keyboard == .default ? .numberPad : keyboard) : keyboard)
            .textInputAutocapitalization(keyboard == .emailAddress ? .never : capitalization)
            .autocorrectionDisabled(keyboard == .emailAddress || keyboard == .phonePad)
            .fieldChrome(invalid: invalid, multiline: multiline)
            .onChange(of: text) { _, _ in if let key { form?.clear(key) } }
        }
    }
}

/// An amount in the business's currency, typed as text and read as cents.
struct MoneyField: View {
    let label: String
    @Binding var cents: Int?
    var key: String? = nil
    var form: FormState? = nil
    var hint: String? = nil
    var optional: Bool = false
    var required: Bool = false
    /// The Store / Inventory / Pharmacy small-caps label.
    var caps: Bool = false
    @State private var text = ""

    var body: some View {
        FormField(label: label, key: key, hint: hint, form: form, optional: optional, caps: caps, required: required) {
            HStack(spacing: 6) {
                Text("$").font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkSoft)
                TextField("0.00", text: $text).keyboardType(.decimalPad)
                Text(Workspace.shared.currency).font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
            }
            .fieldChrome(invalid: key.flatMap { form?.error($0) } != nil)
        }
        .onAppear { if text.isEmpty, let cents { text = Money.input(cents) } }
        // An amount set by code (a total, a suggested price) shows; typing never loops back here.
        .onChange(of: cents) { _, value in
            if Money.parse(text) != value { text = Money.input(value) }
        }
        .onChange(of: text) { _, value in
            cents = Money.parse(value)
            if let key { form?.clear(key) }
        }
    }
}

/// A row with a label and a switch (the web's SwitchCard).
struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        // The web's SwitchCard: a bordered row, the switch at the right.
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                if let subtitle { Text(subtitle).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
            }
        }
        .toggleStyle(PMSwitchStyle())
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }
}

/// A choice among a few values drawn as cards. `.stack` (the modal's yes/no rows,
/// `.provider-modal-toggle`): radio cards one under another, the chosen one on an aqua wash.
/// `.tiles` (web `PetSexButton`, the kg/lb buttons): bordered tiles side by side, 48 tall,
/// an optional icon, the chosen one PAW Blue-edged on MIAW yellow at 24%.
struct ChoiceCards<Value: Hashable>: View {
    enum Layout { case stack, tiles }
    let options: [(value: Value, title: String, subtitle: String?)]
    @Binding var selection: Value
    var layout: Layout = .stack
    /// `.tiles`: each option's icon, in order.
    var icons: [String?] = []

    init(options: [(value: Value, title: String, subtitle: String?)], selection: Binding<Value>) {
        self.options = options
        self._selection = selection
    }

    /// Tiles side by side, each with an optional icon.
    init(tiles: [(value: Value, title: String, icon: String?)], selection: Binding<Value>) {
        self.options = tiles.map { (value: $0.value, title: $0.title, subtitle: nil) }
        self.icons = tiles.map(\.icon)
        self._selection = selection
        self.layout = .tiles
    }

    var body: some View {
        if layout == .tiles { tileRow } else { stack }
    }

    private var tileRow: some View {
        HStack(spacing: 12) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let chosen = option.value == selection
                let shape = RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous)
                Button { selection = option.value } label: {
                    HStack(spacing: 8) {
                        if let icon = icons.indices.contains(index) ? icons[index] : nil { Glyph(icon, size: 16) }
                        Text(option.title).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(Theme.text(14, weight: .semibold))
                    .foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(chosen ? AnyShapeStyle(Theme.wash(Theme.lime, 24)) : AnyShapeStyle(Theme.surface), in: shape)
                    .overlay(shape.strokeBorder(chosen ? Theme.blue : Theme.borderSoft, lineWidth: 2))
                    .contentShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }

    private var stack: some View {
        VStack(spacing: 8) {
            ForEach(options, id: \.value) { option in
                Button { selection = option.value } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Glyph(selection == option.value ? "circle-dot" : "circle", size: 20)
                            .foregroundStyle(selection == option.value ? Theme.blue : Theme.inkSoft)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title).font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            if let subtitle = option.subtitle { Text(subtitle).font(Theme.text(13)).foregroundStyle(Theme.inkSoft) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(selection == option.value ? AnyShapeStyle(Theme.wash(Theme.aqua, 18)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(selection == option.value ? Theme.aqua.opacity(0.7) : Theme.borderSoft, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A picker drawn as a field (menu of options).
struct MenuField<Value: Hashable>: View {
    let label: String
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var key: String? = nil
    var form: FormState? = nil
    var optional: Bool = false

    var required: Bool = false
    var body: some View {
        FormField(label: label, key: key, form: form, optional: optional, required: required) {
            Menu {
                ForEach(options, id: \.value) { option in
                    Button(option.title) { selection = option.value; if let key { form?.clear(key) } }
                }
            } label: {
                HStack {
                    Text(options.first(where: { $0.value == selection })?.title ?? L("Choose")).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    Spacer()
                    Glyph("chevron-down", size: 16).foregroundStyle(Theme.inkSoft)
                }
                .fieldChrome(invalid: key.flatMap { form?.error($0) } != nil)
            }
        }
    }
}

/// The web's switch (ui/switch.tsx): a 32 × 18 track, emerald when on, pale
/// red when off, a white 16 thumb.
struct PMSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.label
            Spacer(minLength: 0)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Theme.switchOn : Theme.switchOff)
                    .frame(width: 32, height: 18.4)
                Circle().fill(.white).frame(width: 16, height: 16).padding(.horizontal, 1.2)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
            }
            .opacity(isEnabled ? 1 : 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture { if isEnabled { withAnimation(.easeOut(duration: 0.18)) { configuration.isOn.toggle() } } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(configuration.isOn ? L("On") : L("Off"))
    }
}
