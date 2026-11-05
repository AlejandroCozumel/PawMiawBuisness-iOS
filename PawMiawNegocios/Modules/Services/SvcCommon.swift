//
//  SvcCommon.swift
//  PawMiawNegocios
//
//  What the three Services pages share: requests whose refusals carry more
//  than a sentence (a fee to decide, places left, a clash), times on the
//  day's clock, the groom stages, the handling chips, the report's words,
//  a wrapping layout for chips and the "start anyway" gate.
//

import SwiftUI
import UIKit

// MARK: - Requests that read the refusal's body

/// A refusal with its whole body (a fee to decide, places left, a clash).
struct SvcRefusal: LocalizedError {
    let api: APIError
    let body: JSONValue?
    var code: String? { api.code }
    var errorDescription: String? { api.message }
}

enum SvcAPI {
    /// Like `API.post`, but a refusal throws `SvcRefusal` with the server's body (`APIError.body`).
    static func send<T: Decodable>(_ method: String, _ path: String, body: [String: Any?]? = nil, query: [String: String?] = [:]) async throws -> T {
        do {
            return try API.decode(try await API.data(method, path, query: query, body: try body.map(API.jsonBody)))
        } catch let api as APIError where api.status >= 300 {
            throw SvcRefusal(api: api, body: api.body)
        }
    }
}

/// The refusal's code, from either kind of error.
func svcCode(_ error: Error) -> String? {
    if let refusal = error as? SvcRefusal { return refusal.code }
    return (error as? APIError)?.code
}

/// What a screen says after a failed action: this module's words for a known code, else the server's.
func svcMessage(_ error: Error, codes: [String: String] = [:]) -> String {
    if let code = svcCode(error), let sentence = codes[code] ?? SvcRefusals.common[code] { return L(sentence) }
    if let refusal = error as? SvcRefusal { return errorText(refusal.api) }
    return errorText(error)
}

/// The `APIError` inside, for `FormState.apply`.
func svcAPIError(_ error: Error) -> Error {
    (error as? SvcRefusal)?.api ?? error
}

enum SvcRefusals {
    static let common: [String: String] = [
        "consent_required": "A consent this visit needs isn’t signed yet.",
        "deposit_required": "The emergency deposit hasn’t been taken yet.",
    ]
    static let grooming: [String: String] = [
        "no_phone": "This client has no phone. Add one to write on WhatsApp, or tell them in PawMiaw.",
        "not_on_app": "This family isn’t on PawMiaw yet. Tell them by WhatsApp, or invite them.",
        "not_a_groom": "This visit isn’t a groom.",
        "visit_not_open": "This visit isn’t open: check the pet in first, or it was already finished.",
    ]
    static let homeVisits: [String: String] = [
        "not_a_home_visit": "Only home visits have this",
        "on_my_way_not_offered": "“On my way” isn't offered for this service",
        "visit_not_scheduled": "This visit already started or isn't today",
        "visit_not_open": "This visit is over — it can't be started now",
        "disclosure_required": "Confirm that your team was told before turning on location",
        "invalid_day": "Choose a day within the last week or the next 30 days",
        "no_phone": "This client has no phone. Add one to write on WhatsApp, or tell them in PawMiaw.",
        "not_on_app": "This family isn’t on PawMiaw yet. Tell them by WhatsApp.",
    ]
}

/// The language the server writes to the family in when it has nothing better.
var svcLocale: String { LocalizationManager.shared.currentLanguage == .spanish ? "es" : "en" }

/// "Miércoles 4 de noviembre": the first letter up, the rest as written.
func svcCapitalized(_ text: String) -> String {
    guard let first = text.first else { return text }
    return first.uppercased() + text.dropFirst()
}

/// Opens a link the server made (WhatsApp with the message, Maps). Phone and WhatsApp links
/// from a number are `ContactLinks`.
@MainActor
func svcOpen(_ link: String?) {
    guard let link, let url = URL(string: link) else { return }
    UIApplication.shared.open(url)
}

// MARK: - Time on the day's clock

enum SvcTime {
    static func zone(_ id: String?) -> TimeZone {
        id.flatMap(TimeZone.init(identifier:)) ?? Workspace.shared.timeZone
    }

    /// "2:10 p.m." on the day's clock.
    static func clock(_ iso: String?, _ zoneId: String?) -> String {
        DateText.time(DateText.parse(iso), zone: zone(zoneId))
    }

    /// "12 sep" (the year when it's another year).
    static func day(_ iso: String?, withYear: Bool = false) -> String {
        guard let date = DateText.parse(iso) else { return "—" }
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = Workspace.shared.timeZone
        let thisYear = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date())
        f.setLocalizedDateFormatFromTemplate(withYear || !thisYear ? "dMMMyyyy" : "dMMM")
        return f.string(from: date)
    }

    /// "Wed, Nov 5" / "Mié 5 nov": a day heading of a list (web `visitDay`, standalone).
    static func shortDay(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return "—" }
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = Workspace.shared.timeZone
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return svcCapitalized(f.string(from: date).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " de ", with: " "))
    }

    /// "jueves, 1 de octubre" for a day key.
    static func dayLong(_ dayKey: String) -> String {
        guard let date = DateText.parse(dayKey) else { return dayKey }
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = Workspace.shared.timeZone
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f.string(from: date)
    }

    /// "35 min", "2 h 10 min": how long since a moment.
    static func waited(_ since: String?) -> String {
        guard let date = DateText.parse(since) else { return "" }
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 60 { return LF("%d min", minutes) }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? LF("%d h", hours) : LF("%d h %d min", hours, rest)
    }

    static func minutesBetween(_ from: String?, _ to: String?) -> Int {
        guard let a = DateText.parse(from), let b = DateText.parse(to) else { return 0 }
        return max(0, Int(b.timeIntervalSince(a) / 60))
    }

    /// A day key moved by whole days.
    static func shift(_ dayKey: String, by days: Int) -> String {
        guard let date = DateText.parse(dayKey) else { return dayKey }
        return DateText.dayKey(date.addingTimeInterval(Double(days) * 86_400))
    }

    static func daysBetween(_ from: String, _ to: String) -> Int {
        guard let a = DateText.parse(from), let b = DateText.parse(to) else { return 0 }
        return Int((b.timeIntervalSince(a) / 86_400).rounded())
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

    /// Whole calendar days from today to a due date (negative once late).
    static func daysUntil(_ iso: String?) -> Int? {
        guard let date = DateText.parse(iso) else { return nil }
        let calendar = DateText.calendar
        let a = calendar.startOfDay(for: Date()), b = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: a, to: b).day
    }

    static func cadence(_ weeks: Int) -> String {
        weeks == 1 ? L("every week") : LF("every %d weeks", weeks)
    }
}

// MARK: - Groom stages (lib/groom-stages.ts)

enum SvcGroomStage {
    static let all = ["scheduled", "waiting", "bath", "styling", "ready", "done"]

    static func shown(_ stage: String, simple: Bool) -> String { simple && stage == "styling" ? "bath" : stage }
    static func visible(simple: Bool) -> [String] { all.filter { !(simple && $0 == "styling") } }

    static func label(_ stage: String, simple: Bool) -> String {
        switch shown(stage, simple: simple) {
        case "scheduled": L("Groom stage · Scheduled")
        case "waiting": L("Groom stage · Waiting")
        case "bath": simple ? L("Groom stage · In progress") : L("Groom stage · Bath")
        case "styling": L("Groom stage · Cut & dry")
        case "ready": L("Ready for pickup")
        default: L("Groom stage · Done")
        }
    }

    /// Where a groom goes next by hand; nil before it arrives and once ready.
    static func next(_ stage: String, simple: Bool) -> String? {
        switch stage {
        case "waiting": "bath"
        case "bath": simple ? "ready" : "styling"
        case "styling": "ready"
        default: nil
        }
    }

    /// One step back for a slip of the finger; a started groom never goes back to waiting.
    static func previous(_ stage: String, simple: Bool) -> String? {
        switch stage {
        case "styling": "bath"
        case "ready": simple ? "bath" : "styling"
        default: nil
        }
    }

    static func moveLabel(to target: String, from stage: String, simple: Bool) -> String {
        if stage == "waiting" && simple { return L("Start") }
        switch target {
        case "waiting": return L("Back to waiting")
        case "bath": return L("Start bath")
        case "styling": return L("To cut & dry")
        default: return L("Ready for pickup")
        }
    }
}

// MARK: - Handling (the care card's tags)

enum SvcHandling {
    /// What can hurt someone or lose the pet.
    static let warn: Set<String> = ["bites", "muzzle", "reactive_dogs", "escape_artist"]
    static let all = ["nervous", "bites", "muzzle", "senior", "puppy", "matted", "sensitive_skin", "reactive_dogs", "escape_artist"]
}

// MARK: - The report's words (lib/service-reports.ts)

enum SvcReportText {
    static let groomServices = ["bath", "haircut", "nails", "ears", "teeth", "glands", "deshedding", "dematting", "flea_bath"]
    static let coats = ["good", "matted", "shedding", "dry", "oily"]
    static let skins = ["ok", "dry", "irritated", "parasites", "lump", "wound"]
    static let behaviours = ["great", "nervous", "difficult"]
    static let eating = ["all", "some", "none"]
    static let stool = ["normal", "soft", "diarrhea"]
    static let progress = ["starting", "improving", "solid"]
    static let styles = ["puppy", "shave", "breed", "tidy", "other"]

    /// One option's label in the reader's language.
    static func option(_ value: String) -> String {
        let english: [String: String] = [
            "bath": "Bath (service)", "haircut": "Haircut", "nails": "Nails", "ears": "Ears", "teeth": "Teeth", "glands": "Glands",
            "deshedding": "Deshedding", "dematting": "Dematting", "flea_bath": "Flea bath",
            "good": "Coat · Good", "matted": "Matted", "shedding": "Shedding", "dry": "Coat · Dry", "oily": "Oily",
            "ok": "All clear", "irritated": "Irritated", "parasites": "Fleas or ticks", "lump": "A lump", "wound": "A wound",
            "great": "Calm", "nervous": "Nervous", "difficult": "Difficult",
            "starting": "Starting", "improving": "Improving", "solid": "Solid",
            "bites": "Bites", "muzzle": "Muzzle", "senior": "Senior", "puppy": "Puppy", "sensitive_skin": "Sensitive skin",
            "reactive_dogs": "Reactive with dogs", "escape_artist": "Escape artist",
            "all": "Ate everything", "some": "Ate some", "none": "Didn't eat",
            "normal": "Stool · Normal", "soft": "Stool · Soft", "diarrhea": "Diarrhea",
        ]
        return L(english[value] ?? value)
    }

    static func style(_ value: String) -> String {
        switch value {
        case "puppy": L("Puppy cut")
        case "shave": L("Shave")
        case "breed": L("Breed standard")
        case "tidy": L("Just a tidy")
        default: L("Style · Other")
        }
    }

    static func kind(for category: String?) -> String? {
        switch category {
        case "groomer": "groom"
        case "walker", "sitter", "daycare": "walk"
        case "trainer": "training"
        default: nil
        }
    }

    static func title(_ kind: String, category: String?) -> String {
        switch kind {
        case "groom": L("Groom report")
        case "training": L("Training report")
        default: category == "walker" ? L("Walk report") : L("Visit report")
        }
    }

    /// What a visit's report still needs before the visit is finished (mirrors the server).
    static func missing(_ category: String?, _ report: SvcReport?) -> [String] {
        guard let kind = kind(for: category) else { return [] }
        var out: [String] = []
        switch kind {
        case "groom":
            let groom = report?.kind == "groom" ? report : nil
            if groom?.services.isEmpty ?? true { out.append("services") }
            if let groom, groom.services.contains("haircut"), groom.styleKind == nil, groom.style?.nonEmpty == nil { out.append("style") }
            if groom?.behaviour == nil { out.append("behaviour") }
        case "training":
            let training = report?.kind == "training" ? report : nil
            if training?.skills.isEmpty ?? true { out.append("skills") }
            if training?.progress == nil { out.append("progress") }
        default:
            let walk = report?.kind == "walk" ? report : nil
            if category == "walker" {
                if walk?.pee == nil { out.append("pee") }
                if walk?.behaviour == nil { out.append("behaviour") }
            } else if category == "sitter" {
                if walk?.ate == nil { out.append("ate") }
                if walk?.water == nil { out.append("water") }
            } else if walk?.behaviour == nil {
                out.append("behaviour")
            }
        }
        return out
    }

    /// The fields this report must have (an asterisk), filled or not.
    static func required(_ category: String?, _ report: SvcReport?) -> Set<String> {
        var base = Set(missing(category, nil))
        if report?.kind == "groom", report?.services.contains("haircut") == true { base.insert("style") }
        return base
    }

    static func fieldLabel(_ field: String) -> String {
        switch field {
        case "services": L("Services")
        case "style": L("Style")
        case "behaviour": L("Behaviour")
        case "pee": L("Pee")
        case "ate": L("Food")
        case "water": L("Water")
        case "skills": L("Practised")
        case "progress": L("Progress")
        default: field
        }
    }

    static func fieldsText(_ fields: [String]) -> String { fields.map { fieldLabel($0) }.joined(separator: ", ") }

    /// The report as rows to read; photos and the note apart.
    static func rows(_ report: SvcReport) -> [(label: String, value: String, concern: Bool)] {
        var rows: [(String, String, Bool)] = []
        switch report.kind {
        case "groom":
            if !report.services.isEmpty { rows.append((L("Services"), report.services.map { option($0) }.joined(separator: ", "), false)) }
            let cut = [report.styleKind.flatMap { $0 == "other" ? nil : style($0) }, report.style?.nonEmpty].compactMap { $0 }.joined(separator: " — ")
            if !cut.isEmpty { rows.append((L("Cut"), cut, false)) }
            if let length = report.length?.nonEmpty { rows.append((L("Report · Length"), length, false)) }
            if let coat = report.coat { rows.append((L("Coat"), option(coat), coat == "matted")) }
            if !report.skin.isEmpty { rows.append((L("Skin"), report.skin.map { option($0) }.joined(separator: ", "), report.skin.contains { $0 != "ok" })) }
        case "walk":
            if let minutes = report.minutes, minutes > 0 { rows.append((L("Time"), LF("%d min", minutes), false)) }
            if let km = report.distanceKm, km > 0 { rows.append((L("Distance"), "\(km.formatted()) km", false)) }
            if let pee = report.pee { rows.append((L("Pee"), pee ? L("Yes") : L("No"), false)) }
            if let poop = report.poop { rows.append((L("Poop"), option(poop), poop == "diarrhea")) }
            if let water = report.water { rows.append((L("Water"), water ? L("Yes") : L("No"), false)) }
            if let ate = report.ate { rows.append((L("Food"), option(ate), ate == "none")) }
            if let meds = report.medsGiven { rows.append((L("Medicine"), meds ? L("Given") : L("Not given"), false)) }
        default:
            if !report.skills.isEmpty { rows.append((L("Practised"), report.skills.joined(separator: ", "), false)) }
            if let progress = report.progress { rows.append((L("Progress"), option(progress), false)) }
            if let homework = report.homework?.nonEmpty { rows.append((L("Homework"), homework, false)) }
        }
        if let behaviour = report.behaviour { rows.append((L("Behaviour"), option(behaviour), behaviour == "difficult")) }
        return rows.map { (label: $0.0, value: $0.1, concern: $0.2) }
    }

    static func photos(_ report: SvcReport) -> [(label: String, url: String)] {
        if report.kind == "groom" {
            return [report.beforePhotoUrl.map { (L("Before"), $0) }, report.afterPhotoUrl.map { (L("After"), $0) }].compactMap { $0 }.map { (label: $0.0, url: $0.1) }
        }
        return report.photoUrl.map { [(label: L("Photo"), url: $0)] } ?? []
    }

    static func hasContent(_ report: SvcReport?) -> Bool {
        guard let report else { return false }
        return !rows(report).isEmpty || !photos(report).isEmpty || report.note?.nonEmpty != nil
    }
}

/// A report to read (web `ReportView`): "Worth a look" when something is, the rows
/// (label 12 bold, value 14; a worry bold red), the photos and the note.
struct SvcReportView: View {
    let report: SvcReport
    var compact: Bool = false

    var body: some View {
        let rows = SvcReportText.rows(report)
        VStack(alignment: .leading, spacing: 12) {
            if rows.contains(where: \.concern) {
                HStack(spacing: 6) {
                    Glyph("triangle-alert", size: 14)
                    Eyebrow(L("Worth a look"), size: 12, color: Theme.destructive)
                }
                .foregroundStyle(Theme.destructive)
            }
            if let route = report.route { WalkRouteView(route: route) }
            if !rows.isEmpty {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            Text(row.label).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                                .frame(minWidth: compact ? nil : 96, alignment: .leading)
                            Text(row.value).font(Theme.text(14, weight: row.concern ? .bold : .regular))
                                .foregroundStyle(row.concern ? Theme.destructive : Theme.inkStrong)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            if report.kind == "groom", let why = report.differenceNote?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Glyph("shuffle", size: 14)
                        Eyebrow(L("What changed"), size: 12, color: Theme.inkStrong)
                    }
                    Text(why).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(Theme.mango, 16), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            }
            let photos = SvcReportText.photos(report)
            if !photos.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: photos.count > 1 ? 2 : 1), spacing: 8) {
                    ForEach(photos, id: \.url) { photo in
                        VStack(alignment: .leading, spacing: 0) {
                            AsyncImage(url: APIConfig.assetURL(photo.url)) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() } else { Theme.surfaceMuted }
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(compact ? 1 : 4 / 3, contentMode: .fit)
                            .clipped()
                            if photos.count > 1 {
                                Text(photo.label).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft).padding(.horizontal, 8).padding(.vertical, 4)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                    }
                }
            }
            if let note = report.note?.nonEmpty {
                Text(note).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            }
        }
    }
}

// MARK: - Staff

/// The business's people, for reassigning and leading a session.
@MainActor
func svcLoadMembers(_ workspace: Workspace) async -> [SvcMember] {
    guard let clinic = workspace.current?.clinicId else { return [] }
    let members: [SvcMember] = (try? await API.get("/provider-workspaces/\(clinic)/members")) ?? []
    return members.filter { $0.status != "suspended" }
}

// MARK: - "Start anyway" (a consent or a deposit stopped a start)

/// A start the server refused for a missing consent or deposit, waiting on an owner's or admin's reason.
struct SvcStartGateRequest: Identifiable {
    let id = UUID()
    let code: String
    let petName: String
    /// The start again, with the override in the body.
    let run: (_ override: [String: Any?]) async throws -> Void
}

struct SvcStartGateSheet: View {
    let request: SvcStartGateRequest
    let onDone: () -> Void

    var body: some View {
        ConfirmSheet(
            title: L("Start anyway?"),
            message: (request.code == "deposit_required" ? L("The emergency deposit hasn’t been taken yet.") : L("A consent this visit needs isn’t signed yet."))
                + " " + LF("Starting %@ without it is recorded with your reason.", request.petName),
            confirmTitle: L("Start anyway"),
            // Web ConsentReasonSheet: the red action, "Not now" beside it.
            destructive: true,
            askReason: true,
            reasonRequired: true,
            reasonLabel: L("Why start now"),
            cancelTitle: L("Not now")
        ) { reason in
            let flag = request.code == "deposit_required" ? "overrideDeposit" : "overrideConsent"
            try await request.run([flag: true, "overrideReason": reason ?? ""])
            onDone()
        }
    }
}

/// Whether a refusal is the consent or deposit gate.
func svcIsStartGate(_ error: Error) -> String? {
    guard let code = svcCode(error), code == "consent_required" || code == "deposit_required" else { return nil }
    return code
}
