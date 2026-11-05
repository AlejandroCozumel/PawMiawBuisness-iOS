//
//  RecordsText.swift
//  PawMiawNegocios
//
//  The words of the Records pages that depend on a value (lib/records-copy.ts,
//  lib/due-words.ts): days, follow-up kinds and states, how late something
//  is, and the titles and notes the system writes on a follow-up, read in the
//  language of the screen whichever one they were stored in. Days are read on
//  the business's clock.
//

import SwiftUI

enum RecordsText {
    static var isSpanish: Bool { LocalizationManager.shared.currentLanguage == .spanish }

    /// "lun 29 sep" → "Lun 29 sep" (the web's `first-letter:uppercase`).
    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// The text with what was searched for marked in MIAW Yellow at 55% (web `Highlight`).
    static func highlight(_ text: String, _ needle: String) -> AttributedString {
        var result = AttributedString(text)
        let wanted = needle.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty, let range = result.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive]) else { return result }
        result[range].backgroundColor = Theme.lime.opacity(0.55)
        return result
    }

    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = Workspace.shared.timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static func sameYear(_ date: Date) -> Bool {
        DateText.calendar.component(.year, from: date) == DateText.calendar.component(.year, from: Date())
    }

    /// "25 sep" — with the year when it isn't this year's.
    static func day(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return "—" }
        return formatter(sameYear(date) ? "dMMM" : "dMMMyyyy").string(from: date)
    }

    /// "25 de septiembre de 2026".
    static func longDate(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return "—" }
        return formatter("dMMMMyyyy").string(from: date)
    }

    /// "25 sep 2026, 10:30".
    static func dateTime(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return "—" }
        return formatter("dMMMyyyyjmm").string(from: date)
    }

    /// "10:30": the time a record was written at; nil for one saved with only its day (noon sharp).
    static func time(_ iso: String?) -> String? {
        guard let iso, iso.count > 10, let date = DateText.parse(iso) else { return nil }
        let parts = DateText.calendar.dateComponents([.hour, .minute, .second], from: date)
        if parts.hour == 12 && parts.minute == 0 && parts.second == 0 { return nil }
        return DateText.time(date)
    }

    /// The day something falls on, as yyyy-MM-dd: what the lists group by.
    static func dayKey(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return "" }
        return DateText.dayKey(date)
    }

    /// Whole calendar days from today to that day; negative once it is past.
    static func daysUntil(_ iso: String?) -> Int {
        guard let date = DateText.parse(iso) else { return 0 }
        let calendar = DateText.calendar
        let from = calendar.startOfDay(for: Date())
        let to = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// A day's heading in a list: "Hoy", "Ayer", "Mañana", else "lun 29 sep" (with the year when it isn't this year's).
    static func dayHeading(_ key: String) -> String {
        guard !key.isEmpty, let date = DateText.parse(key) else { return "—" }
        switch daysUntil(key) {
        case 0: return L("Today")
        case -1: return L("Yesterday")
        case 1: return L("Tomorrow")
        default:
            let text = formatter(sameYear(date) ? "EEEdMMM" : "EEEdMMMyyyy").string(from: date)
            return isSpanish ? text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " de ", with: " ") : text
        }
    }

    /// "Toca hoy", "Vencido hace 3 días", "Toca en 5 días" (due-words `dueWords`).
    static func dueLabel(_ iso: String?) -> String {
        let days = daysUntil(iso)
        switch days {
        case 0: return L("Due today")
        case -1: return L("Due yesterday")
        case 1: return L("Due tomorrow")
        default: return days < 0 ? LF("%d days overdue", -days) : LF("Due in %d days", days)
        }
    }

    /// Late, within the week (today and the six days after), or later: red, mango, light blue.
    static func urgency(_ iso: String?) -> ProviderState {
        let days = daysUntil(iso)
        if days < 0 { return .problem }
        return days <= 6 ? .waiting : .upcoming
    }

    // MARK: Records

    /// Draft (only the team sees it), signed, corrected after it was signed.
    static func statusState(_ record: RecordsRecord) -> ProviderState { record.isDraft ? .waiting : .done }

    /// "Perro · Schnauzer": what tells two pets of one name apart.
    static func petKind(species: String?, breed: String?) -> String {
        let raw = species?.trimmingCharacters(in: .whitespaces) ?? ""
        let names = ["dog": "Dog", "cat": "Cat", "bird": "Bird", "rabbit": "Rabbit", "fish": "Fish", "reptile": "Reptile", "small_pet": "Small pet", "other": "Other"]
        let name = names[raw.lowercased()].map { L($0) } ?? raw
        return [name, breed?.nonEmpty ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "Rosa · 25 sep 2026, 10:30" — who did something and when.
    static func actorLine(_ name: String?, _ at: String?) -> String {
        let who = name?.nonEmpty ?? L("someone on the team")
        guard let at, DateText.parse(at) != nil else { return who }
        return LF("%@ · %@", who, dateTime(at))
    }

    static func clinicalStateLabel(_ state: String) -> String {
        switch state {
        case "active": L("Active@state")
        case "monitoring": L("Monitoring")
        case "resolved": L("Resolved")
        case "completed": L("Completed@state")
        case "stopped": L("Stopped")
        case "inactive": L("Inactive@state")
        default: state
        }
    }

    // MARK: Follow-ups

    static func followUpTypeLabel(_ type: String?) -> String {
        switch type {
        case "care_follow_up": L("Care follow-up")
        case "callback": L("Callback")
        case "recheck": L("Recheck")
        case "lab_review": L("Lab review")
        case "medication_review": L("Medication review")
        case "vaccine_due": L("Vaccine due")
        case "documentation_needed": L("Documentation needed")
        case "billing_follow_up": L("Billing follow-up")
        case "return_visit": L("Return visit")
        default: L("Other")
        }
    }

    static func followUpStatusLabel(_ status: String?) -> String {
        switch status {
        case "open": L("Open@status")
        case "contacted": L("Reminder sent")
        case "scheduled": L("Visit booked")
        case "done": L("Done")
        case "snoozed": L("Snoozed")
        case "canceled": L("Canceled")
        default: (status ?? "").replacingOccurrences(of: "_", with: " ")
        }
    }

    /// Where a follow-up stands, in the six states.
    static func followUpState(_ status: String?) -> ProviderState {
        switch status {
        case "open": .waiting
        case "contacted": .active
        case "scheduled", "snoozed": .upcoming
        case "done": .done
        default: .closed
        }
    }

    /// The team's own work (a note to write, a bill to chase): nothing in it is for the family.
    static func isInternalFollowUp(_ type: String?) -> Bool {
        type == "documentation_needed" || type == "billing_follow_up"
    }

    static let resolutionReasons: [String: String] = [
        "linked_record_added": "Linked record added",
        "client_left_before_exam": "Client left before exam",
        "duplicate_task": "Duplicate task",
        "service_did_not_require_clinical_documentation": "Service did not require clinical documentation",
        "created_in_error": "Created in error",
        "follow_up_date_cleared": "Follow-up date cleared",
        "other": "Other",
    ]

    /// How a closed follow-up was closed: "Cancelado: Pendiente duplicado".
    static func resolutionLabel(_ followUp: RecordsFollowUp) -> String? {
        guard let type = followUp.resolutionType?.nonEmpty else { return nil }
        let typeText: String
        switch type {
        case "completed": typeText = L("Completed@state")
        case "completed_with_record": typeText = L("Completed with record")
        case "resolved_without_record": typeText = L("Resolved without record")
        case "canceled": typeText = L("Canceled")
        default: typeText = type.replacingOccurrences(of: "_", with: " ")
        }
        guard let reason = followUp.resolutionReason?.nonEmpty else { return typeText }
        let reasonText = resolutionReasons[reason].map { L($0) } ?? reason.replacingOccurrences(of: "_", with: " ")
        return LF("%@: %@", typeText, reasonText)
    }

    private struct SystemTitle {
        let patterns: [String]
        let en: (String) -> String
        let es: (String) -> String
    }

    /// The titles the system gives a follow-up, in English and in Spanish (backend lib/follow-up-words.ts).
    private static let systemTitles: [SystemTitle] = [
        SystemTitle(patterns: [#"^Documentation needed: (.+)$"#, #"^Falta documentar: (.+)$"#], en: { "Documentation needed: \($0)" }, es: { "Falta documentar: \($0)" }),
        SystemTitle(patterns: [#"^Report to finish: (.+)$"#, #"^Reporte por terminar: (.+)$"#], en: { "Report to finish: \($0)" }, es: { "Reporte por terminar: \($0)" }),
        SystemTitle(patterns: [#"^Follow up: (.+)$"#, #"^Seguimiento: (.+)$"#], en: { "Follow up: \($0)" }, es: { "Seguimiento: \($0)" }),
        SystemTitle(patterns: [#"^(.+) due$"#, #"^Toca: (.+)$"#], en: { "\($0) due" }, es: { "Toca: \($0)" }),
        SystemTitle(patterns: [#"^(Post-hospitalization recheck)$"#, #"^(Revisión tras la hospitalización)$"#], en: { _ in "Post-hospitalization recheck" }, es: { _ in "Revisión tras la hospitalización" }),
    ]

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let group = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[group]).trimmingCharacters(in: .whitespaces)
    }

    /// A follow-up's title in the reader's language ("Rabies booster due" ↔ "Toca: Rabies booster").
    static func followUpTitle(_ title: String?) -> String {
        let text = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        for system in systemTitles {
            for pattern in system.patterns {
                if let subject = firstMatch(pattern, in: text) {
                    return isSpanish ? system.es(subject) : system.en(subject)
                }
            }
        }
        return text
    }

    private static let reportGaps: [String: String] = [
        "services": "servicios", "servicios": "services", "style": "corte", "corte": "style",
        "behaviour": "comportamiento", "comportamiento": "behaviour", "skills": "habilidades", "habilidades": "skills",
        "progress": "avance", "avance": "progress", "pee": "pipí", "pipí": "pee", "ate": "comida", "comida": "ate",
        "water": "agua", "agua": "water",
    ]

    /// The note the system writes under a task it makes, in the reader's language; a typed note as typed.
    static func followUpNote(_ note: String?) -> String? {
        guard let text = note?.nonEmpty else { return nil }
        let pattern = #"^(?:Fill in the visit's report|Completa el reporte de la visita) \((.+?)\)(?:: the family reads it)?\.$"#
        if let gapsText = firstMatch(pattern, in: text) {
            let english = text.hasPrefix("Fill")
            let gaps = gapsText.components(separatedBy: ", ").map { gap in english == !isSpanish ? gap : (reportGaps[gap] ?? gap) }.joined(separator: ", ")
            return isSpanish ? "Completa el reporte de la visita (\(gaps))." : "Fill in the visit's report (\(gaps))."
        }
        let added = ["Add the medical record for this completed visit.", "Add the linked medical record for this completed visit.", "Agrega el registro médico de esta visita terminada."]
        if added.contains(text) {
            return isSpanish ? "Agrega el registro médico de esta visita terminada." : "Add the medical record for this completed visit."
        }
        return text
    }

    // MARK: Visits

    static func visitStatusLabel(_ status: String?) -> String {
        switch status {
        case "requested": L("To confirm")
        case "scheduled": L("Booked@visit")
        case "checked_in": L("Waiting")
        case "in_progress": L("In the visit")
        case "completed": L("Finished@visit")
        case "cancelled": L("Cancelled@visit")
        case "no_show": L("Didn’t come")
        default: (status ?? "").replacingOccurrences(of: "_", with: " ")
        }
    }

    // MARK: The pet

    static func sexLabel(_ sex: String?) -> String? {
        switch sex {
        case "male": L("Male")
        case "female": L("Female")
        case nil: nil
        default: sex?.nonEmpty
        }
    }

    static func ageLabel(_ birthDate: String?) -> String? {
        guard let born = DateText.parse(birthDate) else { return nil }
        let calendar = DateText.calendar
        let months = max(0, calendar.dateComponents([.month], from: born, to: Date()).month ?? 0)
        if months < 12 { return months == 1 ? L("1 month") : LF("%d months", months) }
        let years = months / 12
        return years == 1 ? L("1 year") : LF("%d years", years)
    }

    /// "Perro · Schnauzer · Hembra · 3 años · 6.4 kg".
    static func petProfile(_ record: RecordsRecord) -> String {
        var parts: [String] = []
        let species = petKind(species: record.petSpecies, breed: nil)
        if !species.isEmpty { parts.append(species) }
        if let breed = record.petBreed?.nonEmpty { parts.append(breed) }
        if let sex = sexLabel(record.petSex) { parts.append(sex) }
        if let age = ageLabel(record.petBirthDate) { parts.append(age) }
        if let grams = record.petWeight, grams > 0 { parts.append(String(format: "%.1f kg", grams / 1000)) }
        return parts.joined(separator: " · ")
    }
}
