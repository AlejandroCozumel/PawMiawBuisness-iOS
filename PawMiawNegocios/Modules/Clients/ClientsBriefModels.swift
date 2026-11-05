//
//  ClientsBriefModels.swift
//  PawMiawNegocios
//
//  The Olfato AI brief of a pet's chart (web: hooks/use-patient-summary.ts,
//  patient-chart/chart-ai-summary.tsx, docs/patient-summaries.md): its
//  shapes, the states the server can be in and the words for them. The
//  brief is plain JSON, asked for again while it is being written.
//

import Foundation
import SwiftUI

struct ClientsBriefItem: Decodable, Hashable {
    let text: String
    let sourceIds: [String]?
    let unverified: Bool?
}

struct ClientsBriefSection: Decodable, Hashable {
    let key: String
    let items: [ClientsBriefItem]?
}

struct ClientsBriefText: Decodable, Hashable {
    let language: String?
    let sections: [ClientsBriefSection]?

    func items(_ key: String) -> [ClientsBriefItem] { sections?.first { $0.key == key }?.items ?? [] }
}

struct ClientsBriefPending: Decodable, Hashable {
    let kind: String?
    let title: String?
    let dueDay: String?
    let source: String?
    let recordId: String?
    let followUpId: String?
}

struct ClientsBriefWarning: Decodable, Hashable, Identifiable {
    let id: String
    let kind: String?
    let origin: String?
    let label: String?
    let detail: String?
    let sourceId: String?
    let covered: Bool?
}

struct ClientsBriefWeightFact: Decodable, Hashable {
    let kg: Double?
    let day: String?
    let sourceId: String?
}

struct ClientsBriefWeights: Decodable, Hashable {
    let latest: ClientsBriefWeightFact?
    let previous: ClientsBriefWeightFact?
    let changeKg: Double?
    let outlier: String?
}

struct ClientsBriefMedication: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let dose: String?
    let route: String?
    let everyHours: Double?
    let durationDays: Double?
    let said: String?
    let origin: String?
    let day: String?
    let endsOn: String?
    let sourceId: String?
    let covered: Bool?
    /// A treatment: "given" or "course".
    let event: String?
}

struct ClientsBriefCareFact: Decodable, Hashable, Identifiable {
    let id: String
    let key: String?
    let value: String?
    let weeks: Int?
    let sourceId: String?
    let covered: Bool?
}

struct ClientsBriefConflict: Decodable, Hashable, Identifiable {
    let id: String
    let kind: String?
    let sourceIds: [String]?
    let values: [String: String]?
}

struct ClientsBriefRead: Decodable, Hashable {
    struct Documents: Decodable, Hashable { let unreadable: Int?; let partial: Int?; let processing: Int? }
    struct Excluded: Decodable, Hashable {
        let omitted: Int?
        let documents: Documents?
        let visitsInProgress: Int?
        let photos: Int?
        let family: String?
        let familySince: String?
        let restricted: Bool?
    }
    let from: String?
    let to: String?
    let counts: [String: Int]?
    let excluded: Excluded?
}

struct ClientsBriefRating: Decodable, Hashable {
    let rating: String?
    let reasons: [String]?
    let comment: String?
}

struct ClientsBriefSource: Decodable, Hashable, Identifiable {
    let id: String
    let kind: String?
    let title: String?
    let at: String?
    let date: String?
    let data: JSONValue?
    let attachmentId: String?
    let page: Int?
}

struct ClientsBriefDiagnostics: Decodable, Hashable {
    let errorCode: String?
    let version: String?
    let attempts: Int?
    let runId: String?
    let model: String?
    let at: String?
    let inputTokens: Int?
    let outputTokens: Int?
}

struct ClientsBriefCoverage: Decodable, Hashable {
    let records: Int?
    let included: Int?
    let truncated: Bool?
    let documents: Int?
    let ready: Int?
    let pending: Int?
    let failed: Int?
}

struct ClientsBriefDocument: Decodable, Hashable, Identifiable {
    let id: String
    let status: String?
    let title: String?
}

struct ClientsBriefRecent: Decodable, Hashable {
    let since: String?
    let basis: String?
}

struct ClientsBrief: Decodable, Hashable {
    let status: String
    let language: String?
    let sourceRevision: String?
    let inputRevision: String?
    let generatedAt: String?
    let coveredThrough: String?
    let summary: ClientsBriefText?
    let nothingReason: String?
    let warnings: [ClientsBriefWarning]?
    let weights: ClientsBriefWeights?
    let conflicts: [ClientsBriefConflict]?
    let currentMedications: [ClientsBriefMedication]?
    let recentTreatment: [ClientsBriefMedication]?
    let careFacts: [ClientsBriefCareFact]?
    let recent: ClientsBriefRecent?
    let partial: Bool?
    let diagnostics: ClientsBriefDiagnostics?
    let pending: [ClientsBriefPending]?
    let pendingMore: Int?
    let today: String?
    let read: ClientsBriefRead?
    let rating: ClientsBriefRating?
    let canEnable: Bool?
    let sources: [ClientsBriefSource]?
    let coverage: ClientsBriefCoverage?
    let documents: [ClientsBriefDocument]?
    let errorCode: String?
    let retryAt: String?
    let delayed: Bool?

    /// What a rating is about: the summary on screen.
    var revision: String? { inputRevision ?? sourceRevision }
}

struct ClientsBriefSettings: Decodable {
    let noticeOutdated: Bool?
}

// MARK: - Words

enum ClientsBriefWords {
    static let tabs = ["problems", "medications", "labs", "weight", "milestones", "care"]

    static func tab(_ key: String) -> String {
        switch key {
        case "problems": L("Problems")
        case "medications": L("Medications")
        case "labs": L("Labs")
        case "weight": L("Weight")
        case "milestones": L("Milestones")
        default: L("Care & handling")
        }
    }

    static func pendingKind(_ kind: String?) -> String {
        switch kind {
        case "vaccine": L("Vaccine")
        case "reminder": L("Reminder")
        default: L("Follow-up")
        }
    }

    /// "Vence en 3 días", "Vencido hace 2 días": against the business's today.
    static func pendingDue(_ day: String?, today: String?) -> (text: String, late: Bool, today: Bool) {
        guard let day = day.flatMap(dayDate), let now = (today.flatMap(dayDate) ?? dayDate(DateText.dayKey())) else { return ("—", false, false) }
        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: now, to: day).day ?? 0
        if days < 0 {
            let late = -days
            if late == 1 { return (L("Overdue by 1 day"), true, false) }
            if late <= 60 { return (LF("Overdue by %d days", late), true, false) }
            return (LF("Overdue since %@", ClientsText.shortDay(DateText.iso(day))), true, false)
        }
        if days == 0 { return (L("Due today@brief"), false, true) }
        if days == 1 { return (L("Due tomorrow@brief"), false, false) }
        return (LF("Due in %d days@brief", days), false, false)
    }

    static func dayDate(_ day: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(day.prefix(10)))
    }

    /// "1 oct, 12:27", with the year only when it isn't this one.
    static func stamp(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return "—" }
        let sameYear = DateText.calendar.component(.year, from: date) == DateText.calendar.component(.year, from: Date())
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = Workspace.shared.timeZone
        f.setLocalizedDateFormatFromTemplate(sameYear ? "dMMMjmm" : "dMMMyyyyjmm")
        return f.string(from: date)
    }

    /// ISO days written inside a bullet ("2026-09-27 19:30") read as "27 sep, 19:30".
    static func datesInText(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{4}-\d{2}-\d{2})(?:[ T](\d{2}):(\d{2}))?\b"#) else { return text }
        var result = text
        // Days and times in the text are read and printed on one clock (UTC), so they show as written.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: text), let dayRange = Range(match.range(at: 1), in: text), let day = dayDate(String(text[dayRange])) else { continue }
            let f = DateFormatter()
            f.locale = .app
            f.timeZone = TimeZone(identifier: "UTC")
            let sameYear = utc.component(.year, from: day) == Calendar(identifier: .gregorian).component(.year, from: Date())
            f.setLocalizedDateFormatFromTemplate(sameYear ? "dMMM" : "dMMMyyyy")
            var shown = f.string(from: day)
            if let h = Range(match.range(at: 2), in: text), let m = Range(match.range(at: 3), in: text),
               let hours = Int(text[h]), let minutes = Int(text[m]) {
                // Built on the phone's clock and printed on UTC, "19:30" showed shifted by the phone's offset.
                var parts = DateComponents(); parts.hour = hours; parts.minute = minutes
                let tf = DateFormatter(); tf.locale = .app; tf.timeZone = utc.timeZone; tf.setLocalizedDateFormatFromTemplate("jmm")
                if let time = utc.date(from: parts) { shown += ", \(tf.string(from: time))" }
            }
            result.replaceSubrange(Range(NSRange(whole, in: text), in: result) ?? whole, with: shown)
        }
        return result
    }

    static func kg(_ kg: Double?) -> String {
        guard let kg else { return "—" }
        return "\(kg.formatted(.number.precision(.fractionLength(0...2)).locale(.app))) kg"
    }

    static func change(_ kg: Double) -> String {
        let sign = kg > 0 ? "+" : kg < 0 ? "−" : ""
        return "\(sign)\(abs(kg).formatted(.number.precision(.fractionLength(0...2)).locale(.app))) kg"
    }

    static func warningPrefix(_ w: ClientsBriefWarning) -> String? {
        if w.origin == "note" { return L("Noted in a record") }
        switch w.kind {
        case "allergy": return L("Allergy")
        case "problem": return L("Problem")
        default: return nil
        }
    }

    static func warningText(_ w: ClientsBriefWarning) -> String {
        if w.origin == "care_card" { return SvcReportText.option(w.label ?? "") }
        if w.origin == "note" { return "“\(w.label ?? "")”" }
        if w.kind == "allergy", let detail = w.detail?.nonEmpty { return "\(w.label ?? "") — \(detail)" }
        return w.label ?? "—"
    }

    static func conflictText(_ c: ClientsBriefConflict) -> String {
        let v = c.values ?? [:]
        let day = { (value: String?) -> String in value.flatMap { $0.count >= 10 ? ClientsText.shortDay($0) : $0 } ?? "—" }
        switch c.kind {
        case "neuter": return LF("The profile says not neutered, and a record notes a spay or neuter: “%@”", v["recorded"] ?? "")
        case "allergy_medication":
            let family = v["match"] == "family"
            if v["from"] == "note" {
                return family ? LF("A record says “%1$@”, and %2$@, of the same family, was recorded after it.", v["allergen"] ?? "", v["medication"] ?? "")
                    : LF("A record says “%1$@”, and %2$@ was recorded after it.", v["allergen"] ?? "", v["medication"] ?? "")
            }
            return family ? LF("An allergy to %1$@ is on record, and %2$@, of the same family, was recorded after it.", v["allergen"] ?? "", v["medication"] ?? "")
                : LF("An allergy to %1$@ is on record, and %2$@ was recorded after it.", v["allergen"] ?? "", v["medication"] ?? "")
        case "dose": return LF("Two active records give %1$@ at different doses: %2$@ and %3$@.", v["medication"] ?? "", v["first"] ?? "", v["second"] ?? "")
        case "birth_date": return LF("The profile says born %1$@; a record says %2$@.", day(v["profile"]), day(v["recorded"]))
        default: return v.values.joined(separator: " · ")
        }
    }

    /// "Amoxicilina 250 mg · oral · cada 12 h · por 7 días".
    static func medicationLine(_ m: ClientsBriefMedication) -> (title: String, detail: String) {
        let title = [m.name, m.dose].compactMap { $0?.nonEmpty }.joined(separator: " ")
        let days = m.durationDays.map { Int($0) }
        let detail = [
            m.route?.nonEmpty,
            m.everyHours.map { LF("every %@ h", $0.formatted(.number.precision(.fractionLength(0...1)))) },
            days.map { $0 == 1 ? L("for 1 day") : LF("for %d days", $0) },
        ].compactMap { $0 }.joined(separator: " · ")
        return (title, detail)
    }

    static func medicationSource(_ m: ClientsBriefMedication) -> String {
        let date = m.day.map { ClientsText.shortDay($0) }
        if m.event == "given" { return date.map { LF("Dose given on %@", $0) } ?? L("Dose given") }
        if m.event == "course" { return date.map { LF("Prescribed %@; the course has ended", $0) } ?? L("A course that has ended") }
        switch m.origin {
        case "prescription": return date.map { LF("Prescribed %@", $0) } ?? L("On a prescription")
        case "note": return date.map { LF("Noted in a record on %@", $0) } ?? L("Noted in a record")
        default: return date.map { LF("Medication record of %@", $0) } ?? L("Medication record")
        }
    }

    static func careLabel(_ key: String?) -> String {
        switch key {
        case "usual_cut": L("Usual cut")
        case "blade_or_length": L("Blade or length")
        case "rebook_every_weeks": L("Comes back")
        case "products": L("Products")
        default: L("Care notes")
        }
    }

    static func failure(_ code: String?, time: String?) -> String {
        switch code {
        case "provider_configuration": return L("Olfato AI can’t write summaries right now. Everything else in the chart works as usual. If this continues, contact support.")
        case "summary_refused", "invalid_citation", "invalid_summary", "ungrounded_summary":
            return time.map { LF("We couldn’t write a summary we can stand behind for this chart, so none is shown. You can try again at %@.", $0) }
                ?? L("We couldn’t write a summary we can stand behind for this chart, so none is shown. You can try again.")
        default:
            return time.map { LF("We couldn’t write the summary this time. You can try again at %@.", $0) } ?? L("We couldn’t write the summary this time. Try again in a few minutes.")
        }
    }

    /// "1 oct to 3 nov · 4 visits · 12 records · care card".
    static func readLine(_ read: ClientsBriefRead) -> String {
        let range: String = {
            switch (read.from, read.to) {
            case let (from?, to?) where from.prefix(10) != to.prefix(10): return LF("%1$@ to %2$@", ClientsText.shortDay(from), ClientsText.shortDay(to))
            case let (from?, _): return ClientsText.shortDay(from)
            case let (nil, to?): return ClientsText.shortDay(to)
            default: return L("nothing dated")
            }
        }()
        let counts = read.counts ?? [:]
        let parts: [(String, String, String)] = [
            ("visits", "%d visit", "%d visits"), ("records", "%d record", "%d records"), ("prescriptions", "%d prescription", "%d prescriptions"),
            ("weights", "%d weight", "%d weights"), ("documents", "%d document", "%d documents"), ("followUps", "%d follow-up", "%d follow-ups"),
            ("hospital", "%d hospital entry", "%d hospital entries"), ("stays", "%d stay", "%d stays"),
        ]
        var words = [range]
        for (key, one, other) in parts { if let n = counts[key], n > 0 { words.append(LP(n, one, other)) } }
        if (counts["careCard"] ?? 0) > 0 { words.append(L("care card")) }
        return words.joined(separator: " · ")
    }

    static func exclusions(_ read: ClientsBriefRead?) -> [String] {
        guard let x = read?.excluded else { return [] }
        var lines: [String] = []
        if let n = x.omitted, n > 0 { lines.append(n == 1 ? L("1 older entry was left out because this chart is longer than one summary can read. The History has everything.") : LF("%d older entries were left out because this chart is longer than one summary can read. The History has everything.", n)) }
        if let n = x.documents?.unreadable, n > 0 { lines.append(n == 1 ? L("1 attached document couldn’t be read.") : LF("%d attached documents couldn’t be read.", n)) }
        if let n = x.documents?.partial, n > 0 { lines.append(n == 1 ? L("1 attached document could only be read in part.") : LF("%d attached documents could only be read in part.", n)) }
        if let n = x.documents?.processing, n > 0 { lines.append(n == 1 ? L("1 attached document is still being read.") : LF("%d attached documents are still being read.", n)) }
        if let n = x.visitsInProgress, n > 0 { lines.append(n == 1 ? L("1 visit still under way isn’t included until it is finished.") : LF("%d visits still under way aren’t included until they are finished.", n)) }
        if (x.photos ?? 0) > 0 { lines.append(L("Photos attached to visit reports aren’t read.")) }
        switch x.family {
        case "not_shared": lines.append(L("The family’s own records aren’t shared with this business."))
        case "partial": lines.append(x.familySince.map { LF("The family shares its records from %@ on; earlier ones aren’t included.", ClientsText.shortDay($0)) } ?? L("The family shares only its newer records; earlier ones aren’t included."))
        default: break
        }
        if x.restricted == true { lines.append(L("Some records aren’t visible to you, so they aren’t in this summary.")) }
        return lines
    }

    static func documentStatus(_ status: String?) -> String {
        switch status {
        case "ready": L("Read@document")
        case "review": L("Partly readable")
        case "pending", "processing": L("Processing")
        default: L("Could not be read")
        }
    }

    static func sourceKind(_ kind: String?) -> String? {
        switch kind {
        case "visit": L("Visit")
        case "clinic_record": L("Record")
        case "family_record": L("Family record")
        case "prescription": L("Prescription")
        case "weight": L("Weight")
        case "family_weight": L("Weight at home")
        case "care_card": L("Care card@brief")
        case "follow_up": L("Follow-up")
        case "document": L("Document")
        case "hospitalization", "hospital_order", "administration", "hospital_note", "hospital_round": L("Hospital")
        case "vitals": L("Vital signs")
        case "stay": L("Stay")
        case "pet": L("Pet")
        default: nil
        }
    }

    static func sourceTitle(_ source: ClientsBriefSource) -> String {
        switch source.title {
        case "Care card": L("Care card@brief")
        case "Prescription": L("Prescription")
        case "Weight": L("Weight")
        case "Weight at home": L("Weight at home")
        case "Hospital update": L("Hospital update")
        case "Hospital rounds": L("Hospital rounds")
        case "Vital signs": L("Vital signs")
        case "Boarding": L("Boarding")
        case "Daycare": L("Daycare")
        case "Home sitting": L("Home sitting")
        default: source.title?.nonEmpty ?? sourceKind(source.kind) ?? L("Source")
        }
    }
}
