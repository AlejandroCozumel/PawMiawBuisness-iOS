//
//  DateFields.swift
//  PawMiawNegocios
//
//  The app's date and time fields, on the business's clock:
//  - `DayField`: a calendar day as "yyyy-MM-dd" (a stay's nights, a lot's expiry),
//    optionally empty and clearable.
//  - `DateTimeField`: a moment (a dose given, an admission).
//  - `OptionalDateField`: a moment that may stay empty until chosen.
//  - `TimeField`: an "HH:mm" picked from the day's quarter hours.
//

import SwiftUI

/// "yyyy-MM-dd" ↔ a Date at noon, read without a time zone shift.
private enum DayKey {
    static let utc = TimeZone(identifier: "UTC")!
    static func date(_ day: String) -> Date? {
        DateText.dayFormatter(utc).date(from: String(day.prefix(10))).map { $0.addingTimeInterval(12 * 3600) }
    }
    static func key(_ date: Date) -> String { DateText.dayFormatter(utc).string(from: date) }
    static var today: String { DateText.dayKey() }
}

struct DayField: View {
    let label: String
    @Binding var day: String
    var min: String? = nil
    var max: String? = nil
    var key: String? = nil
    var form: FormState? = nil
    var hint: String? = nil
    var optional: Bool = false
    /// Empty is allowed: shows "Choose the date" and a clear button.
    var clearable: Bool = false
    var emptyTitle: String = L("Choose the date")
    /// With `clearable`, the ✕ that empties it again (off for a required day that starts empty).
    var showsClear: Bool = true

    /// The red * (web RequiredMark).
    var required: Bool = false
    var body: some View {
        let lower = min.flatMap(DayKey.date) ?? .distantPast
        let upper = Swift.max(lower, max.flatMap(DayKey.date) ?? .distantFuture)
        return FormField(label: label, key: key, hint: hint, form: form, optional: optional, required: required) {
            HStack(spacing: 8) {
                Image(systemName: "calendar").foregroundStyle(Theme.inkSoft)
                if day.isEmpty && clearable {
                    Button(emptyTitle) {
                        let today = DayKey.today
                        day = min.map { Swift.max($0, today) } ?? today
                        if let key { form?.clear(key) }
                    }
                    .foregroundStyle(Theme.blueText)
                    Spacer(minLength: 0)
                } else {
                    DatePicker("", selection: Binding(get: { DayKey.date(day) ?? Date() }, set: { day = DayKey.key($0); if let key { form?.clear(key) } }), in: lower...upper, displayedComponents: .date)
                        .labelsHidden()
                        .tint(Theme.blue)
                        .environment(\.timeZone, DayKey.utc)
                        .environment(\.locale, .app)
                    Spacer(minLength: 0)
                    if clearable && showsClear {
                        Button { day = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkSoft) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L("Clear the date"))
                    }
                }
            }
            .fieldChrome(invalid: key.flatMap { form?.error($0) } != nil)
        }
    }
}

struct DateTimeField: View {
    let label: String
    @Binding var date: Date
    var zone: TimeZone? = nil
    var min: Date? = nil
    var max: Date? = nil
    var components: DatePickerComponents = [.date, .hourAndMinute]
    var key: String? = nil
    var form: FormState? = nil
    var hint: String? = nil

    /// The red * (web RequiredMark).
    var required: Bool = false
    var body: some View {
        FormField(label: label, key: key, hint: hint, form: form, required: required) {
            HStack {
                DatePicker("", selection: Binding(get: { date }, set: { date = $0; if let key { form?.clear(key) } }), in: (min ?? .distantPast)...(max ?? .distantFuture), displayedComponents: components)
                    .labelsHidden()
                    .tint(Theme.blue)
                Spacer(minLength: 0)
            }
            .fieldChrome(invalid: key.flatMap { form?.error($0) } != nil)
            .environment(\.timeZone, zone ?? Workspace.shared.timeZone)
            .environment(\.locale, .app)
        }
    }
}

struct OptionalDateField: View {
    let label: String
    @Binding var date: Date?
    var placeholder: String = L("Choose the date")
    var zone: TimeZone? = nil
    var min: Date? = nil
    var max: Date? = nil
    var components: DatePickerComponents = [.date]
    /// Where the picker starts when chosen (clamped to min/max).
    var defaultDate: Date = Date()
    var key: String? = nil
    var form: FormState? = nil
    var hint: String? = nil
    var optional: Bool = true

    /// The red * (web RequiredMark).
    var required: Bool = false
    var body: some View {
        FormField(label: label, key: key, hint: hint, form: form, optional: optional, required: required) {
            HStack(spacing: 8) {
                if let value = date {
                    DatePicker("", selection: Binding(get: { value }, set: { date = $0; if let key { form?.clear(key) } }), in: (min ?? .distantPast)...(max ?? .distantFuture), displayedComponents: components)
                        .labelsHidden()
                        .tint(Theme.blue)
                    Spacer(minLength: 0)
                    Button { date = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkSoft) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Clear the date"))
                } else {
                    Button {
                        var start = defaultDate
                        if let min { start = Swift.max(start, min) }
                        if let max { start = Swift.min(start, max) }
                        date = start
                        if let key { form?.clear(key) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar").foregroundStyle(Theme.blueText)
                            Text(placeholder).foregroundStyle(Theme.inkSoft)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .fieldChrome(invalid: key.flatMap { form?.error($0) } != nil)
            .environment(\.timeZone, zone ?? Workspace.shared.timeZone)
            .environment(\.locale, .app)
        }
    }
}

/// An "HH:mm" from the day's quarter hours (`from`…`to`), shown on the app's clock style.
struct TimeField: View {
    let label: String
    @Binding var value: String
    var from: String = "06:00"
    var to: String = "22:00"
    var stepMinutes: Int = 15
    var allowsEmpty: Bool = false
    var emptyTitle: String = L("No set time")
    var key: String? = nil
    var form: FormState? = nil
    var optional: Bool = false

    /// The red * (web RequiredMark).
    var required: Bool = false
    var body: some View {
        var options: [(value: String, title: String)] = Self.times(from: from, to: to, step: stepMinutes).map { ($0, Self.clock($0)) }
        if !value.isEmpty, !options.contains(where: { $0.value == value }) { options.insert((value, Self.clock(value)), at: 0) }
        if allowsEmpty { options.insert(("", emptyTitle), at: 0) }
        return MenuField(label: label, options: options, selection: $value, key: key, form: form, optional: optional, required: required)
    }

    static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    static func hhmm(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    static func times(from: String, to: String, step: Int = 15) -> [String] {
        guard let start = minutes(from), let end = minutes(to), step > 0, start <= end else { return [] }
        return stride(from: start, through: end, by: step).map(hhmm)
    }

    /// "14:30" → "2:30 p. m." in the app's language.
    static func clock(_ hhmm: String) -> String {
        guard let total = minutes(hhmm) else { return hhmm }
        var parts = DateComponents()
        parts.hour = total / 60
        parts.minute = total % 60
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(from: parts) else { return hhmm }
        return DateText.time(date, zone: TimeZone(identifier: "UTC")!)
    }
}
