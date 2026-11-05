//
//  Formatting.swift
//  PawMiawNegocios
//
//  Money, dates and names, formatted the way the web's business side shows
//  them. Amounts travel in cents; dates as ISO-8601 strings; a business's
//  day is read on its own clock (`Workspace.shared.timeZone`).
//

import Foundation

enum Money {
    /// "$1,234.50 MXN" — the web's `formatMoney`.
    static func format(_ cents: Int?, currency: String? = nil) -> String {
        let value = Double(cents ?? 0) / 100
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: LocalizationManager.shared.currentLanguage == .spanish ? "es_MX" : "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        let code = (currency ?? Workspace.shared.currency).uppercased()
        return "$\(number) \(code)"
    }

    /// "$1,234.50" without the currency, for tight rows.
    static func short(_ cents: Int?) -> String {
        let value = Double(cents ?? 0) / 100
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "$" + (formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value))
    }

    /// An amount typed by a person ("123.50", "1,500", "$12") to cents; nil when it can't be read.
    static func parse(_ text: String) -> Int? {
        var cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "").replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }
        // "1.500,00" → "1500.00"; "1,500.00" → "1500.00"; "12,5" → "12.5"
        if let comma = cleaned.lastIndex(of: ","), let dot = cleaned.lastIndex(of: ".") {
            if comma > dot { cleaned = cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
            else { cleaned = cleaned.replacingOccurrences(of: ",", with: "") }
        } else if cleaned.contains(",") {
            let parts = cleaned.split(separator: ",")
            cleaned = parts.count == 2 && parts[1].count <= 2 ? parts.joined(separator: ".") : cleaned.replacingOccurrences(of: ",", with: "")
        }
        guard let value = Decimal(string: cleaned), value >= 0 else { return nil }
        return NSDecimalNumber(decimal: value * 100).rounding(accordingToBehavior: nil).intValue
    }

    /// Cents as the text a money field starts with ("123.50").
    static func input(_ cents: Int?) -> String {
        guard let cents else { return "" }
        return String(format: "%.2f", Double(cents) / 100)
    }
}

enum DateText {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    /// An ISO timestamp, a "yyyy-MM-dd" day (noon on the business's clock) or epoch seconds/ms.
    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = isoFractional.date(from: value) ?? isoPlain.date(from: value) { return date }
        if value.count == 10, let day = dayFormatter(Workspace.shared.timeZone).date(from: value) {
            return day.addingTimeInterval(12 * 3600)
        }
        if let number = Double(value) { return Date(timeIntervalSince1970: number > 1e12 ? number / 1000 : number) }
        // "2026-11-04 10:00:00" (SQLite)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: value)
    }

    static func iso(_ date: Date) -> String { isoFractional.string(from: date) }

    static func dayFormatter(_ zone: TimeZone) -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "yyyy-MM-dd"; return f
    }

    /// "2026-11-04" on the business's clock.
    static func dayKey(_ date: Date = Date(), zone: TimeZone? = nil) -> String {
        dayFormatter(zone ?? Workspace.shared.timeZone).string(from: date)
    }

    private static func format(_ date: Date, _ template: String, zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = zone
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }

    /// "10:30 a.m."
    static func time(_ date: Date?, zone: TimeZone? = nil) -> String {
        guard let date else { return "—" }
        return format(date, "jmm", zone: zone ?? Workspace.shared.timeZone)
    }
    static func time(_ iso: String?) -> String { time(parse(iso)) }

    /// "mié 4 nov"
    static func day(_ date: Date?, zone: TimeZone? = nil) -> String {
        guard let date else { return "—" }
        return format(date, "EEEdMMM", zone: zone ?? Workspace.shared.timeZone)
    }
    static func day(_ iso: String?) -> String { day(parse(iso)) }

    /// "miércoles 4 de noviembre"
    static func longDay(_ date: Date?, zone: TimeZone? = nil) -> String {
        guard let date else { return "—" }
        return format(date, "EEEEdMMMM", zone: zone ?? Workspace.shared.timeZone)
    }

    /// "4 nov 2026"
    static func date(_ date: Date?, zone: TimeZone? = nil) -> String {
        guard let date else { return "—" }
        return format(date, "dMMMyyyy", zone: zone ?? Workspace.shared.timeZone)
    }
    static func date(_ iso: String?) -> String { date(parse(iso)) }

    /// "mié 4 nov, 10:30 a.m." — or "Hoy, 10:30 a.m." / "Mañana, …".
    static func dayTime(_ date: Date?, zone: TimeZone? = nil) -> String {
        guard let date else { return "—" }
        return "\(relativeDay(date, zone: zone)), \(time(date, zone: zone))"
    }
    static func dayTime(_ iso: String?) -> String { dayTime(parse(iso)) }

    /// "Hoy", "Mañana", "Ayer" or the short day.
    static func relativeDay(_ date: Date, zone: TimeZone? = nil) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone ?? Workspace.shared.timeZone
        if calendar.isDateInToday(date) { return L("Today") }
        if calendar.isDateInTomorrow(date) { return L("Tomorrow") }
        if calendar.isDateInYesterday(date) { return L("Yesterday") }
        return day(date, zone: zone)
    }

    /// "hace 5 min" / "in 2 h".
    static func ago(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = RelativeDateTimeFormatter(); f.locale = .app; f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
    static func ago(_ iso: String?) -> String { ago(parse(iso)) }

    /// The business's calendar (its clock, Monday first).
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Workspace.shared.timeZone
        calendar.firstWeekday = 2
        calendar.locale = .app
        return calendar
    }
}

enum NameText {
    /// "MG" from "María García".
    static func initials(_ name: String?) -> String {
        let words = (name ?? "").split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    /// The first two letters of a name ("Prueba Destino" → "PR"), as the web's client avatars draw them.
    static func firstLetters(_ name: String?) -> String {
        let letters = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).filter { $0.isLetter }.prefix(2)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    static func firstName(_ name: String?) -> String {
        (name ?? "").split(separator: " ").first.map(String.init) ?? ""
    }
}

extension String {
    /// nil for an empty or blank string.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? { self?.nonEmpty }
}
