//
//  SchedLogic.swift
//  PawMiawNegocios
//
//  The Schedule's plumbing: requests whose refusals carry more than a
//  sentence (the conflicts of a double booking, the hours problem, the fee to
//  decide), the business's days and minutes, and the same booking rules the
//  web runs before saving (lib/hours.ts, lib/visit-conflicts.ts,
//  lib/booking-hours.ts). The server checks everything again.
//

import Foundation
import SwiftUI

// MARK: - Requests that read the refusal's body

/// A refused request with its whole body (the conflicts, the hours problem, the fee).
struct SchedFailure: LocalizedError {
    let api: APIError
    let body: JSONValue?

    var errorDescription: String? { api.message }
    var code: String? { api.code }

    @MainActor var conflicts: [SchedConflict]? {
        guard code == "visit_conflict" else { return nil }
        guard let raw = body?["conflicts"], let data = try? JSONEncoder().encode(raw) else { return [] }
        return (try? JSONDecoder().decode([SchedConflict].self, from: data)) ?? []
    }

    @MainActor var hoursProblem: SchedHoursProblem? {
        guard code == "outside_hours" else { return nil }
        let reasons = ["closed_date", "closed_day", "outside_hours", "break", "crosses_days", "time_off", "member_hours"]
        let reason = body?["reason"]?.string ?? ""
        return SchedHoursProblem(
            reason: reasons.contains(reason) ? reason : "outside_hours",
            message: api.message,
            closureLabel: body?["closure"]?["label"]?.string,
            timeOffReason: body?["timeOff"]?["reason"]?.string,
            memberId: body?["memberId"]?.string
        )
    }

    @MainActor var fee: SchedFeeRequired? {
        guard code == "fee_decision_required", let fee = body?["fee"], let amount = fee["amount"]?.int else { return nil }
        return SchedFeeRequired(kind: fee["kind"]?.string ?? "no_show", amount: amount, currency: fee["currency"]?.string,
                                familyAskedAt: fee["familyAskedAt"]?.string, measuredFrom: fee["measuredFrom"]?.string)
    }

    /// The emergency deposit a start waits on (409 `deposit_required`).
    @MainActor var depositGap: SchedDepositDue? {
        guard code == "deposit_required" else { return nil }
        if let deposit = body?["deposit"], let amount = deposit["amount"]?.int {
            return SchedDepositDue(amount: amount, paid: deposit["paid"]?.int ?? 0, currency: deposit["currency"]?.string)
        }
        if let gate = body?["gate"]?["deposit"] {
            return SchedDepositDue(amount: gate["amount"]?.int ?? 0, paid: gate["paid"]?.int ?? 0, currency: nil)
        }
        return SchedDepositDue(amount: 0, paid: 0, currency: nil)
    }

    /// The consents a start was refused for (409 `consent_required`).
    @MainActor var consentGap: [ConsentLine] {
        guard code == "consent_required", let lines = body?["consents"]?.array else { return [] }
        return lines.compactMap { line in
            guard let title = line["title"]?.string else { return nil }
            return ConsentLine(templateId: line["templateId"]?.string, title: title, satisfied: false, consentId: line["consentId"]?.string, status: line["status"]?.string)
        }
    }
}

/// The APIError inside any failure of this module (for forms and toasts).
func schedAPIError(_ error: Error) -> Error {
    (error as? SchedFailure)?.api ?? error
}

func schedErrorText(_ error: Error) -> String {
    errorText(schedAPIError(error))
}

func schedToast(_ error: Error) {
    Toast.error(schedErrorText(error))
}

enum SchedAPI {
    /// Like `API.post/patch`, but a refusal keeps its body (`SchedFailure`, from `APIError.body`).
    static func send<T: Decodable>(_ method: String, _ path: String, body: [String: Any?]? = nil, query: [String: String?] = [:]) async throws -> T {
        do {
            return try API.decode(try await API.data(method, path, query: query, body: try body.map(API.jsonBody)))
        } catch let api as APIError where api.status >= 300 {
            throw SchedFailure(api: api, body: api.body)
        }
    }
}

// MARK: - The business's days

enum SchedDay {
    static var zone: TimeZone { Workspace.shared.timeZone }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = .app
        calendar.firstWeekday = 2
        return calendar
    }

    static var today: String { DateText.dayKey(Date(), zone: zone) }

    static func key(_ date: Date, zone: TimeZone? = nil) -> String { DateText.dayKey(date, zone: zone ?? self.zone) }

    static func key(_ iso: String?) -> String? { DateText.parse(iso).map { key($0) } }

    /// Midnight of a "yyyy-MM-dd" on the business's clock.
    static func start(_ day: String, zone: TimeZone? = nil) -> Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        var calendar = self.calendar
        if let zone { calendar.timeZone = zone }
        guard parts.count == 3 else { return Date() }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? Date()
    }

    /// A day at a minute of that day, as a date.
    static func at(_ day: String, minute: Int, zone: TimeZone? = nil) -> Date {
        start(day, zone: zone).addingTimeInterval(TimeInterval(minute * 60))
    }

    static func addDays(_ day: String, _ count: Int) -> String {
        let date = calendar.date(byAdding: .day, value: count, to: start(day)) ?? start(day)
        return key(date)
    }

    static func minuteOfDay(_ date: Date, zone: TimeZone? = nil) -> Int {
        var calendar = self.calendar
        if let zone { calendar.timeZone = zone }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func weekday(_ day: String) -> String {
        let index = calendar.component(.weekday, from: start(day))
        return ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"][max(0, min(6, index - 1))]
    }

    static func date(fromKey day: String) -> Date { start(day).addingTimeInterval(12 * 3600) }

    /// "10:30 a. m." for a minute of the day.
    static func timeLabel(_ minute: Int) -> String {
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(max(0, min(minute, 1439)) * 60)))
    }

    /// "Miércoles 4 de noviembre" (the year when it isn't this one).
    static func longLabel(_ day: String) -> String {
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = zone
        f.setLocalizedDateFormatFromTemplate(day.prefix(4) == today.prefix(4) ? "EEEEdMMMM" : "EEEEdMMMMyyyy")
        return upperFirst(f.string(from: date(fromKey: day)))
    }

    /// The day of the month, "5" (a week column's disc).
    static func dayNumber(_ day: String) -> String { String(Int(day.suffix(2)) ?? 0) }

    /// "mié 5" (a week column's head).
    static func weekColumnLabel(_ day: String) -> String {
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = zone
        f.setLocalizedDateFormatFromTemplate("EEEd")
        return f.string(from: date(fromKey: day))
    }

    /// "mié 4 nov".
    static func shortLabel(_ day: String) -> String { DateText.day(date(fromKey: day)) }

    /// "4 nov – 10 nov 2026".
    static func weekLabel(_ first: String, _ last: String) -> String {
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = zone
        f.setLocalizedDateFormatFromTemplate("dMMM")
        let g = DateFormatter()
        g.locale = .app
        g.timeZone = zone
        g.setLocalizedDateFormatFromTemplate("dMMMyyyy")
        return "\(f.string(from: date(fromKey: first))) – \(g.string(from: date(fromKey: last)))"
    }

    static func relative(_ day: String) -> String? {
        if day == today { return L("Today") }
        if day == addDays(today, 1) { return L("Tomorrow") }
        if day == addDays(today, -1) { return L("Yesterday") }
        return nil
    }

    static func upperFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// A short duration: "45 min", "1 h 20 min".
    static func duration(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 { return LF("%@ min", String(m)) }
        let h = m / 60, rest = m % 60
        return rest == 0 ? LF("%@ h", String(h)) : LF("%@ h %@ min", String(h), String(rest))
    }

    /// The visit's day in its location's clock: before, today or after.
    static func when(_ startsAt: String, zone: TimeZone) -> String {
        guard let date = DateText.parse(startsAt) else { return "today" }
        let day = key(date, zone: zone), now = key(Date(), zone: zone)
        return day < now ? "past" : day > now ? "future" : "today"
    }
}

// MARK: - Hours

struct SchedMinuteRange: Hashable {
    let start: Int
    let end: Int
}

enum SchedHours {
    static func startMinutes(_ value: String) -> Int? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    /// "23:59" closes at midnight.
    static func endMinutes(_ value: String) -> Int? {
        value == "23:59" ? 1440 : startMinutes(value)
    }

    static func minutes(_ ranges: [SchedRange]) -> [SchedMinuteRange] {
        ranges.compactMap { range in
            guard let start = startMinutes(range.start), let end = endMinutes(range.end) else { return nil }
            return SchedMinuteRange(start: start, end: end)
        }
    }

    static func fits(_ start: Int, _ end: Int, _ ranges: [SchedMinuteRange]) -> Bool {
        ranges.contains { start >= $0.start && end <= $0.end }
    }

    /// A day's open ranges and its closure: the server's load first, then the closures, then the week.
    static func day(_ day: String, load: SchedLoad?, closures: [SchedClosure]?, availability: SchedAvailability?) -> (ranges: [SchedRange], closure: (label: String?, closed: Bool)?) {
        if let loaded = load?.hoursDay(day) {
            let closure = loaded.closure.map { (label: $0.label, closed: $0.closed ?? false) }
            return (loaded.ranges ?? [], closure)
        }
        let covering = (closures ?? []).filter { $0.covers(day) }
        if let closure = covering.first(where: { $0.ranges == nil }) ?? covering.last {
            if let ranges = closure.ranges { return (ranges, (closure.label, false)) }
            return ([], (closure.label, true))
        }
        return (availability?.week(SchedDay.weekday(day)) ?? [], nil)
    }

    /// Whether a person is off during a time for a reason of their own (a day off, their own hours).
    static func personOff(_ person: SchedLoadPerson, start: Date, end: Date) -> Bool {
        guard let day = person.day(SchedDay.key(start)) else { return false }
        if day.timeOff != nil { return true }
        guard person.ownHours == true else { return false }
        let endMinute = SchedDay.key(end) == day.date ? SchedDay.minuteOfDay(end) : 1440
        return !fits(SchedDay.minuteOfDay(start), endMinute, minutes(day.ranges ?? []))
    }

    /// The first open day after `day` (the week and the closures), within 120 days.
    static func nextOpenDay(after day: String, closures: [SchedClosure]?, availability: SchedAvailability?) -> String? {
        for offset in 1...120 {
            let next = SchedDay.addDays(day, offset)
            if !self.day(next, load: nil, closures: closures, availability: availability).ranges.isEmpty { return next }
        }
        return nil
    }

    /// The open day closest to `day` ("¿Cuándo vuelve?"): it, a day after, a day before (never before `notBefore`).
    static func nearestOpenDay(_ day: String, closures: [SchedClosure]?, availability: SchedAvailability?, notBefore: String?) -> String? {
        func opens(_ d: String) -> Bool { !self.day(d, load: nil, closures: closures, availability: availability).ranges.isEmpty }
        if opens(day) { return day }
        for offset in 1...3 {
            let after = SchedDay.addDays(day, offset)
            if opens(after) { return after }
            let before = SchedDay.addDays(day, -offset)
            if (notBefore == nil || before >= notBefore!) && opens(before) { return before }
        }
        return nil
    }

    static func rangesText(_ ranges: [SchedRange]) -> String {
        let parts = minutes(ranges).map { LF("%@ to %@", SchedDay.timeLabel($0.start), SchedDay.timeLabel(min($0.end, 1439))) }
        if parts.count <= 1 { return parts.joined() }
        return LF("%@ and %@", parts.dropLast().joined(separator: ", "), parts.last!)
    }

    /// One line naming the problem ("Closed that day · Navidad", "Ana is off that day").
    static func problemTitle(_ problem: SchedHoursProblem, personName: String?) -> String {
        switch problem.reason {
        case "closed_date":
            return problem.closureLabel.map { LF("Closed that day · %@", $0) } ?? L("Closed that day")
        case "closed_day": return L("Closed that day of the week")
        case "break": return L("In a break between opening hours")
        case "time_off":
            if let personName {
                return problem.timeOffReason.map { LF("%@ is off that day · %@", personName, $0) } ?? LF("%@ is off that day", personName)
            }
            return problem.timeOffReason.map { LF("That person is off that day · %@", $0) } ?? L("That person is off that day")
        case "member_hours":
            return personName.map { LF("%@ doesn’t work then", $0) } ?? L("That person doesn’t work then")
        default: return L("Outside opening hours")
        }
    }

    static func problemBody(_ problem: SchedHoursProblem) -> String {
        if problem.reason == "closed_date" { return "\(L("Families can’t book that day online.")) \(L("Booked anyway, the visit is marked as outside opening hours."))" }
        if problem.reason == "time_off" || problem.reason == "member_hours" {
            return "\(L("They aren’t offered for online booking then, and aren’t counted for whoever is free.")) \(L("Booked anyway, the visit is marked as outside opening hours."))"
        }
        return L("Booked anyway, the visit is marked as outside opening hours.")
    }
}

// MARK: - Double bookings (the server's lib/visit-conflicts.ts)

struct SchedSlot {
    var id: String?
    var start: Date
    var end: Date
    var memberId: String?
    var roomId: String?
    var pets: Int = 1
    var together: Bool = false
    var ignoreIds: [String] = []
}

enum SchedConflicts {
    private static func span(_ visit: SchedLoadVisit) -> (Date, Date)? {
        guard let start = DateText.parse(visit.startsAt) else { return nil }
        let end = DateText.parse(visit.endsAt) ?? start.addingTimeInterval(30 * 60)
        return (start, end)
    }

    private static func overlaps(_ slot: SchedSlot, _ visit: SchedLoadVisit, buffer: Int) -> Bool {
        guard let (start, end) = span(visit) else { return false }
        let b = TimeInterval(max(0, buffer) * 60)
        return slot.start < end.addingTimeInterval(b) && start < slot.end.addingTimeInterval(b)
    }

    private static func peak(_ slot: SchedSlot, _ visits: [SchedLoadVisit], buffer: Int) -> Int {
        let inside = visits.filter { overlaps(slot, $0, buffer: buffer) }
        if inside.count <= 1 { return inside.count }
        let b = TimeInterval(max(0, buffer) * 60)
        var points: [(Date, Int)] = []
        for visit in inside {
            guard let (start, end) = span(visit) else { continue }
            points.append((max(start.addingTimeInterval(-b), slot.start), 1))
            points.append((min(end.addingTimeInterval(b), slot.end.addingTimeInterval(b)), -1))
        }
        points.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        var current = 0, best = 0
        for (_, delta) in points { current += delta; best = max(best, current) }
        return best
    }

    /// Every pet of a session counts once: the session is one booking.
    private static func collapseSessions(_ visits: [SchedLoadVisit]) -> [SchedLoadVisit] {
        var seen = Set<String>()
        return visits.filter { visit in
            guard let session = visit.sessionId else { return true }
            return seen.insert(session).inserted
        }
    }

    private static func asConflict(_ v: SchedLoadVisit) -> SchedConflictVisit {
        SchedConflictVisit(id: v.id, petName: v.petName, startsAt: v.startsAt, endsAt: v.endsAt)
    }

    static func find(_ slot: SchedSlot, load: SchedLoad) -> [SchedConflict] {
        let buffer = load.bufferMinutes ?? 0
        let ignored = Set(([slot.id] + slot.ignoreIds.map { Optional($0) }).compactMap { $0 })
        let others = collapseSessions((load.visits ?? []).filter { visit in
            !ignored.contains(visit.id) && SchedStatus.holding.contains(visit.status) && overlaps(slot, visit, buffer: buffer)
        })
        let extra = max(1, slot.pets) - 1
        func over(_ peak: Int, _ capacity: Int) -> Bool { slot.together && peak == 0 ? false : peak + extra >= capacity }
        var conflicts: [SchedConflict] = []
        let people = load.people ?? []
        if let memberId = slot.memberId {
            let person = people.first { $0.id == memberId }
            let capacity = max(1, person?.capacity ?? 1)
            let theirs = others.filter { $0.memberId == memberId }
            if over(peak(slot, theirs, buffer: buffer), capacity) {
                conflicts.append(SchedConflict(kind: "person", memberId: memberId, name: person?.name, capacity: capacity, visits: theirs.map { asConflict($0) }))
            }
        } else if !people.isEmpty {
            let seats = people.filter { !SchedHours.personOff($0, start: slot.start, end: slot.end) }
            let capacity = seats.reduce(0) { $0 + max(1, $1.capacity ?? 1) }
            if over(peak(slot, others, buffer: buffer), capacity) {
                conflicts.append(SchedConflict(kind: "everyone", capacity: capacity, visits: others.map { asConflict($0) }))
            }
        }
        if let roomId = slot.roomId {
            let room = load.visitRooms.first { $0.id == roomId }
            let capacity = max(1, room?.capacity ?? 1)
            let inRoom = others.filter { $0.roomId == roomId }
            if let room, let out = room.outOn(SchedDay.key(slot.start)) {
                conflicts.append(SchedConflict(kind: "room", roomId: roomId, name: room.name, capacity: capacity, visits: [], outOfService: SchedOutOfServiceNote(untilDay: out.untilDay, reason: out.reason)))
            } else if over(peak(slot, inRoom, buffer: buffer), capacity) {
                conflicts.append(SchedConflict(kind: "room", roomId: roomId, name: room?.name, capacity: capacity, visits: inRoom.map { asConflict($0) }))
            }
        }
        return conflicts
    }

    static func roomIsFree(_ slot: SchedSlot, room: SchedRoom, load: SchedLoad) -> Bool {
        var probe = slot
        probe.roomId = room.id
        probe.memberId = nil
        let only = SchedLoad(visits: load.visits, people: [], rooms: [room], bufferMinutes: load.bufferMinutes, hours: nil)
        return !find(probe, load: only).contains { $0.kind == "room" }
    }

    /// The first free room meant for the service, then the first free general room.
    static func pickFreeRoom(_ slot: SchedSlot, load: SchedLoad, serviceId: String?) -> SchedRoom? {
        let free = load.visitRooms.filter { roomIsFree(slot, room: $0, load: load) }
        if let serviceId, let meant = free.first(where: { ($0.serviceIds ?? []).contains(serviceId) }) { return meant }
        return free.first { ($0.serviceIds ?? []).isEmpty }
    }

    /// A conflict in one sentence (web rooms/room-picker `conflictLine`).
    static func line(_ conflict: SchedConflict) -> String {
        let visits = conflict.visits ?? []
        if conflict.kind == "room", let out = conflict.outOfService {
            let name = conflict.name ?? L("That room")
            let base = out.untilDay.map { LF("%@ is out of service until %@", name, SchedDay.shortLabel($0)) } ?? LF("%@ is out of service", name)
            return out.reason.map { "\(base) (\($0))" } ?? base
        }
        let capacity = conflict.capacity ?? 1
        if visits.isEmpty && conflict.kind == "person" { return LF("%@ takes %@ at once — these pets are more than that", conflict.name ?? L("That person"), String(capacity)) }
        if visits.isEmpty && conflict.kind == "room" { return LF("%@ holds %@ at once — these pets are more than that", conflict.name ?? L("That room"), String(capacity)) }
        var list = visits.prefix(2).map { visit -> String in
            let time = DateText.time(visit.startsAt)
            return visit.petName.map { "\($0) (\(time))" } ?? time
        }.joined(separator: ", ")
        if visits.count > 2 { list += " " + LF("and %@ more", String(visits.count - 2)) }
        switch conflict.kind {
        case "person":
            return capacity > 1
                ? LF("%@ already has %@ pets then (%@) and takes %@ at once", conflict.name ?? L("That person"), String(visits.count), list, String(capacity))
                : LF("%@ is already with %@", conflict.name ?? L("That person"), list)
        case "room":
            return capacity > 1
                ? LF("%@ is full then (%@); it holds %@.", conflict.name ?? L("That room"), list, String(capacity))
                : LF("%@ is taken by %@", conflict.name ?? L("That room"), list)
        case "travel", "service_area":
            return L("The home visit doesn’t leave time to get there, or is outside their area.")
        default:
            return capacity == 0 ? L("Nobody who takes visits works then (days off, their own hours).") : L("Everyone who takes visits is busy then.")
        }
    }
}

// MARK: - Shared reads

enum SchedData {
    /// Everyone on the team (`/provider-workspaces/{clinicId}/members`).
    static func members() async -> [SchedMember] {
        guard let clinic = Workspace.shared.current?.clinicId else { return [] }
        return (try? await API.get("/provider-workspaces/\(clinic)/members")) ?? []
    }

    /// The rooms visits go in at this device's place (wards and cages left out).
    static func rooms(locationId: String?) async -> [SchedRoom] {
        let rooms: [SchedRoom] = (try? await API.get("/provider-rooms", query: ["locationId": locationId])) ?? []
        return rooms.filter { $0.holdsVisits && $0.status != "archived" }.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
    }

    /// The booking settings and week of a place: the location's with several, else the workspace's.
    static func availability(locationId: String?) async -> SchedAvailability? {
        let w = Workspace.shared
        let wanted = locationId ?? (w.multiLocation ? w.selectedLocation?.id : nil)
        if let wanted {
            let answer: SchedLocationsAvailability? = try? await API.get("/provider-locations", query: ["includeArchived": "true"])
            if let found = answer?.locations?.first(where: { $0.id == wanted })?.availability { return found }
        }
        let active: SchedWorkspaceAvailability? = try? await API.get("/provider-workspaces/active")
        return active?.availability
    }

    static func visit(_ id: String) async throws -> SchedAppointment {
        try await API.get("/provider-appointments/\(id)")
    }

    static func visitRecords(_ appointmentId: String) async -> [SchedRecord]? {
        let page: Page<SchedRecord>? = try? await API.get("/provider-records", query: ["limit": "100", "offset": "0", "appointmentId": appointmentId])
        return page?.items
    }

    static func catalog() async -> SchedCatalog? {
        try? await API.get("/appointment-services", query: ["scope": "provider"])
    }

    /// How many clients the business has (nil when it can't be read).
    static func clientsTotal() async -> Int? {
        let page: Page<SchedClient>? = try? await API.get("/provider-clients", query: ["limit": "1", "offset": "0"])
        return page?.total
    }

    /// Visits whose family asked to move or cancel, from today on.
    static func familyAsking(locationId: String?) async -> [SchedAppointment] {
        let from = DateText.iso(SchedDay.start(SchedDay.today))
        let page: Page<SchedAppointment>? = try? await API.get("/provider-appointments", query: ["limit": "20", "offset": "0", "requests": "true", "from": from, "locationId": locationId])
        // Checked here too: an older API ignores the filter and would send every visit.
        return (page?.items ?? []).filter(\.familyAsking)
    }

    static func closures(locationId: String?) async -> [SchedClosure] {
        let answer: SchedClosures? = try? await API.get("/provider-hours/closures", query: ["locationId": locationId])
        return answer?.closures ?? []
    }

    static func load(from: Date, to: Date, locationId: String?) async throws -> SchedLoad {
        try await API.get("/provider-schedule/load", query: ["from": DateText.iso(from), "to": DateText.iso(to), "locationId": locationId])
    }

    static func load(day: String, locationId: String?) async throws -> SchedLoad {
        try await load(from: SchedDay.start(day), to: SchedDay.start(SchedDay.addDays(day, 1)), locationId: locationId)
    }

    /// The clock of a visit's location, else the business's.
    static func zone(of locationId: String?) -> TimeZone {
        let w = Workspace.shared
        if let locationId, let place = w.allLocations.first(where: { $0.id == locationId }),
           let id = place.timezone ?? place.availability?.timezone, let zone = TimeZone(identifier: id) {
            return zone
        }
        return w.timeZone
    }

    /// The people who take visits at a place (nobody given locations = everywhere).
    static func visitTakers(_ members: [SchedMember], locationId: String?) -> [SchedMember] {
        let here = members.filter { $0.worksAt(locationId) && $0.status != "suspended" }
        let takers = here.filter(\.takesVisits)
        return takers.isEmpty ? here : takers
    }
}

// MARK: - Small helpers

/// "52" + 10 digits for a Mexican number, else the digits as they are; nil below 10 digits.
func schedWhatsAppURL(_ phone: String?, message: String? = nil) -> URL? {
    let digits = (phone ?? "").filter(\.isNumber)
    guard digits.count >= 10 else { return nil }
    let number = digits.count == 10 ? "52\(digits)" : digits
    var components = URLComponents(string: "https://wa.me/\(number)")
    if let message { components?.queryItems = [URLQueryItem(name: "text", value: message)] }
    return components?.url
}

func schedPhoneURL(_ phone: String?) -> URL? {
    let cleaned = (phone ?? "").filter { $0.isNumber || $0 == "+" }
    return cleaned.isEmpty ? nil : URL(string: "tel:\(cleaned)")
}

/// "3 años", "5 meses" from a birth date.
func schedAge(_ birthDate: String?) -> String? {
    guard let born = DateText.parse(birthDate) else { return nil }
    let parts = Calendar(identifier: .gregorian).dateComponents([.month], from: born, to: Date())
    let months = max(0, parts.month ?? 0)
    if months < 12 { return LF("%@ mo", String(months)) }
    return LF("%@ yr", String(months / 12))
}

func schedSpeciesLabel(_ species: String?) -> String? {
    switch species?.lowercased() {
    case "dog": L("Dog")
    case "cat": L("Cat")
    case "bird": L("Bird")
    case "rabbit": L("Rabbit")
    case "fish": L("Fish")
    case "reptile": L("Reptile")
    case "other": L("Other")
    case nil, "": nil
    default: species
    }
}

func schedSexLabel(_ sex: String?) -> String? {
    switch sex?.lowercased() {
    case "male": L("Male")
    case "female": L("Female")
    default: nil
    }
}

/// A fresh id for a request that must never run twice (a walk-in).
func schedRequestId() -> String { UUID().uuidString.lowercased() }
