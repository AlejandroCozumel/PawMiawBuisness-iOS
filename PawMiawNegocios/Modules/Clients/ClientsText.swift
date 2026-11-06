//
//  ClientsText.swift
//  PawMiawNegocios
//
//  The words and small rules the Clients screens share, as the web's copy
//  files say them (patient-chart-copy.ts, records-copy.ts, due-words.ts,
//  copy/client-closing.ts, lib/phone.ts).
//

import Foundation
import SwiftUI

enum ClientsText {
    // MARK: Pets

    static func species(_ species: String?) -> String {
        switch species {
        case "dog": L("Dog")
        case "cat": L("Cat")
        case "bird": L("Bird")
        case "rabbit": L("Rabbit")
        case "fish": L("Fish")
        case "reptile": L("Reptile")
        case "small_pet": L("Small pet")
        case "other": L("Other@species")
        case nil: "—"
        default: species ?? "—"
        }
    }

    static let speciesOptions: [(value: String, title: String)] = ["dog", "cat", "bird", "rabbit", "fish", "reptile", "small_pet", "other"].map { ($0, species($0)) }

    static func sex(_ sex: String?) -> String? {
        switch sex {
        case "male": L("Male")
        case "female": L("Female")
        default: nil
        }
    }

    /// "3 años", "8 meses" from a birth date.
    static func age(_ birthDate: String?) -> String? {
        guard let birthDate, let born = DateText.parse(String(birthDate.prefix(10))), born <= Date() else { return nil }
        let parts = Calendar(identifier: .gregorian).dateComponents([.month], from: born, to: Date())
        let months = parts.month ?? 0
        if months < 1 { return L("Newborn") }
        if months < 12 { return LP(months, "%d month", "%d months") }
        let years = months / 12
        return LP(years, "%d year", "%d years")
    }

    /// "12.4 kg".
    static func weight(_ grams: Double?) -> String? {
        guard let grams, grams > 0 else { return nil }
        let kilograms = grams / 1000
        let formatter = NumberFormatter()
        formatter.locale = .app
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = kilograms >= 10 ? 1 : 2
        return "\(formatter.string(from: NSNumber(value: kilograms)) ?? String(format: "%.1f", kilograms)) kg"
    }

    /// Kilograms typed by a person ("12.5", "12,5") to grams.
    static func grams(fromKilograms text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0 else { return nil }
        return Int((value * 1000).rounded())
    }

    static func kilogramsInput(_ grams: Double?) -> String {
        guard let grams, grams > 0 else { return "" }
        let kilograms = grams / 1000
        return kilograms.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(kilograms)) : String(format: "%.2f", kilograms).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }

    /// "Perro · Beagle · Hembra · 12.4 kg".
    static func profileLine(_ pet: ClientsPet) -> String {
        [species(pet.petSpecies), pet.petBreed?.nonEmpty, sex(pet.sex), weight(pet.weight)].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Days

    /// "3 oct", with the year when it is not this one.
    static func shortDay(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return "—" }
        let sameYear = DateText.calendar.component(.year, from: date) == DateText.calendar.component(.year, from: Date())
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = Workspace.shared.timeZone
        f.setLocalizedDateFormatFromTemplate(sameYear ? "dMMM" : "dMMMyyyy")
        return f.string(from: date)
    }

    /// "25 sep 2026, 10:30".
    static func dayTime(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return "—" }
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = Workspace.shared.timeZone
        f.setLocalizedDateFormatFromTemplate("dMMMyyyyjmm")
        return f.string(from: date)
    }

    /// "Hoy", "Mañana", or the short day.
    static func relativeShortDay(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return "—" }
        let calendar = DateText.calendar
        if calendar.isDateInToday(date) { return L("Today") }
        if calendar.isDateInTomorrow(date) { return L("Tomorrow") }
        return shortDay(iso)
    }

    static func isPast(_ iso: String?) -> Bool {
        guard let date = DateText.parse(iso) else { return false }
        return date < Date()
    }

    // MARK: Contact

    static func mailURL(_ email: String?) -> URL? {
        guard let email = email?.nonEmpty else { return nil }
        return URL(string: "mailto:\(email)")
    }

    /// A phone loosely checked: empty, or enough digits to be dialled.
    static func phoneLooksValid(_ phone: String) -> Bool {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        let digits = trimmed.filter(\.isNumber)
        let allowed = trimmed.allSatisfy { $0.isNumber || " +-().".contains($0) }
        return allowed && digits.count >= 8 && digits.count <= 15
    }

    static func emailLooksValid(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    // MARK: Follow-ups and records

    /// A follow-up's title in the reader's language ("Rabies booster due" ↔ "Toca: Rabies booster").
    static func followUpTitle(_ title: String?) -> String {
        let text = (title ?? "").trimmingCharacters(in: .whitespaces)
        let spanish = LocalizationManager.shared.currentLanguage == .spanish
        let patterns: [(String, String, (String) -> String, (String) -> String)] = [
            (#"^Documentation needed: (.+)$"#, #"^Falta documentar: (.+)$"#, { "Documentation needed: \($0)" }, { "Falta documentar: \($0)" }),
            (#"^Report to finish: (.+)$"#, #"^Reporte por terminar: (.+)$"#, { "Report to finish: \($0)" }, { "Reporte por terminar: \($0)" }),
            (#"^Follow up: (.+)$"#, #"^Seguimiento: (.+)$"#, { "Follow up: \($0)" }, { "Seguimiento: \($0)" }),
            (#"^(.+) due$"#, #"^Toca: (.+)$"#, { "\($0) due" }, { "Toca: \($0)" }),
        ]
        for (en, es, toEnglish, toSpanish) in patterns {
            for pattern in [en, es] {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                   let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let range = Range(match.range(at: 1), in: text) {
                    let subject = String(text[range]).trimmingCharacters(in: .whitespaces)
                    return spanish ? toSpanish(subject) : toEnglish(subject)
                }
            }
        }
        if text.caseInsensitiveCompare("Post-hospitalization recheck") == .orderedSame || text.caseInsensitiveCompare("Revisión tras la hospitalización") == .orderedSame {
            return spanish ? "Revisión tras la hospitalización" : "Post-hospitalization recheck"
        }
        return text
    }

    /// "Due today", "3 days overdue", "Due in 5 days".
    static func dueWords(_ days: Int) -> String {
        switch days {
        case 0: return L("Due today")
        case -1: return L("Due yesterday")
        case 1: return L("Due tomorrow")
        default: return days < 0 ? LF("%d days overdue", -days) : LF("Due in %d days", days)
        }
    }

    static func daysUntil(_ iso: String) -> Int {
        guard let date = DateText.parse(iso) else { return 0 }
        let calendar = DateText.calendar
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
    }

    static func recordType(_ type: String?) -> String {
        switch type {
        case "vaccination": L("Vaccine")
        case "vet_visit": L("Vet visit")
        case "medication": L("Medicine")
        case "surgery": L("Surgery")
        case "diagnosis": L("Diagnosis")
        case "lab_result": L("Lab result")
        case "deworming": L("Deworming")
        case "weight_check": L("Weight")
        case "allergy": L("Allergy")
        default: L("Note")
        }
    }

    static func followUpType(_ type: String?) -> String {
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

    static func followUpStatus(_ status: String?) -> String {
        switch status {
        case "open": L("Open@followup")
        case "contacted": L("Reminder sent")
        case "scheduled": L("Visit booked")
        case "done": L("Done@followup")
        case "snoozed": L("Snoozed")
        case "canceled": L("Canceled")
        default: status ?? "—"
        }
    }

    static func visitStatus(_ status: String?) -> String {
        switch status {
        case "requested": L("To confirm")
        case "checked_in": L("Waiting")
        case "in_progress": L("In progress")
        case "completed": L("Done@visit")
        case "no_show": L("No-show")
        case "scheduled": L("Booked")
        case "cancelled": L("Cancelled")
        default: status ?? "—"
        }
    }

    static func invoiceStatus(_ status: String?) -> String {
        switch status {
        case "draft": L("Draft")
        case "ready_for_payment": L("To pay")
        case "open": L("Open@invoice")
        case "partially_paid": L("Partly paid")
        case "paid": L("Paid")
        case "overdue": L("Overdue@status")
        case "canceled": L("Cancelled")
        case "forgiven": L("Balance forgiven")
        default: status ?? "—"
        }
    }

    static func vaccineStatus(_ status: String?) -> String {
        switch status {
        case "overdue": L("Overdue@status")
        case "due_soon": L("Due soon")
        case "current": L("Up to date")
        default: L("No next dose")
        }
    }

    /// A chart vaccine's state in the six status colours.
    static func vaccineState(_ status: String?) -> ProviderState {
        switch status {
        case "due_soon": .waiting
        case "no_date", nil: .closed
        default: ProviderState.vaccine(status)
        }
    }

    // MARK: Archiving

    /// A client's or pet's state word where it is not simply active (web `statusLabel`).
    static func clientStatus(_ status: String?) -> String {
        switch status {
        case "lead": return L("Lead")
        case "active": return L("Active")
        case "archived": return L("Archived")
        case "inactive": return L("Inactive")
        case "deceased": return L("Deceased")
        default:
            guard let status, let first = status.first else { return "" }
            return (String(first).uppercased() + status.dropFirst()).replacingOccurrences(of: "_", with: " ")
        }
    }

    static func closingReason(_ reason: String?) -> String? {
        switch reason {
        case nil: nil
        case "rehomed": L("Has a new family")
        case "moved": L("Moved away")
        case "no_longer_comes": L("No longer comes")
        case "other_provider": L("Goes somewhere else")
        case "other": L("Other")
        case "deceased": L("Died")
        case "client_archived": L("Archived with the client")
        default: reason
        }
    }

    /// The name as typed is the record's own, whatever the case, accents or spaces.
    static func typedNameMatches(_ typed: String, _ name: String) -> Bool {
        func fold(_ value: String) -> String {
            let plain = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
            let letters = plain.map { ($0.isLetter && $0.isASCII) || $0.isNumber || $0 == " " ? String($0) : " " }.joined()
            return letters.split(separator: " ").joined(separator: " ")
        }
        let wanted = fold(name)
        if wanted.isEmpty { return !name.trimmingCharacters(in: .whitespaces).isEmpty && typed.trimmingCharacters(in: .whitespaces).lowercased() == name.trimmingCharacters(in: .whitespaces).lowercased() }
        return fold(typed) == wanted
    }

    static func blocker(_ code: String, name: String) -> String {
        switch code {
        case "visit_in_progress": LF("%@ has a visit in progress. Finish it first.", name)
        case "in_hospital": LF("%@ is in the hospital. Discharge it first; a death there is recorded on the hospitalization.", name)
        case "on_stay": LF("%@ is on a stay. Check it out first.", name)
        case "stay_booked": LF("%@ has a stay booked. Cancel it first.", name)
        default: code
        }
    }
}

/// The members of the business (for "Anyone / Unassigned" and the preferred vet).
enum ClientsMembers {
    static func load() async -> [ClientsMember] {
        guard let clinic = Workspace.shared.current?.clinicId else { return [] }
        return (try? await API.get("/provider-workspaces/\(clinic)/members")) ?? []
    }
}

/// Copies text to the pasteboard with the toast the web shows.
@MainActor
func clientsCopy(_ text: String?, done: String) {
    guard let text = text?.nonEmpty else { return }
    UIPasteboard.general.string = text
    Toast.show(done)
}
