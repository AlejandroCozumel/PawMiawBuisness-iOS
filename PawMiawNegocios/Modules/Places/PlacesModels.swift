//
//  PlacesModels.swift
//  PawMiawNegocios
//
//  The shapes and rules of the Places module: rooms (web hooks/use-provider-rooms.ts,
//  lib/rooms.ts), locations (hooks/use-provider-locations.ts, lib/provider-locations.ts)
//  and the visits waiting to move from a paused location ("Por reubicar").
//

import Foundation
import SwiftUI

// MARK: - Rooms

struct PlacesRoomOut: Codable, Hashable {
    let fromDay: String
    let untilDay: String?
    let reason: String?
}

struct PlacesRoom: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let kind: String
    let capacity: Int?
    let serviceIds: [String]?
    let sortOrder: Int?
    let status: String?
    let locationId: String?
    let notes: String?
    let outOfService: PlacesRoomOut?

    var kindEntry: PlacesRoomKind { PlacesRoomKind.of(kind) }
    var isHospital: Bool { kindEntry.isHospital }
    var isArchived: Bool { status == "archived" }
    var places: Int { max(1, capacity ?? 1) }
    var services: [String] { serviceIds ?? [] }
}

/// What a room holds (`GET /provider-rooms/usage`).
struct PlacesRoomUsage: Decodable, Hashable {
    let roomId: String
    let upcomingVisits: Int?
    let visitsToday: Int?
    let patients: Int?
    let hasHistory: Bool?
}

/// Visits still booked in a room on days it is out of service.
struct PlacesRoomOutVisits: Decodable, Hashable {
    let count: Int?
    let firstDay: String?
}

/// A saved room, with what is still booked in it while out of service.
struct PlacesRoomSaved: Decodable {
    let id: String
    let name: String
    let visitsWhileOut: PlacesRoomOutVisits?
}

struct PlacesService: Decodable, Hashable, Identifiable {
    let id: String
    let label: String
}

struct PlacesServiceCatalog: Decodable {
    let services: [PlacesService]?
}

/// The kinds of room, in one place: icon, name (one and several), what it is for, its hue.
enum PlacesRoomKind: String, CaseIterable, Identifiable {
    case consult, grooming, bath, surgery, treatment, ward, cage, other

    var id: String { rawValue }

    /// The order the groups are listed in.
    static let order: [PlacesRoomKind] = [.consult, .surgery, .treatment, .grooming, .bath, .other, .ward, .cage]

    static func of(_ raw: String?) -> PlacesRoomKind { raw.flatMap(PlacesRoomKind.init(rawValue:)) ?? .other }

    var isHospital: Bool { self == .ward || self == .cage }

    var label: String {
        switch self {
        case .consult: L("Consult room")
        case .grooming: L("Grooming table")
        case .bath: L("Bath")
        case .surgery: L("Surgery")
        case .treatment: L("Treatment")
        case .ward: L("Ward")
        case .cage: L("Cage")
        case .other: L("Other@room")
        }
    }

    var plural: String {
        switch self {
        case .consult: L("Consult rooms")
        case .grooming: L("Grooming tables")
        case .bath: L("Baths")
        case .surgery: L("Surgeries")
        case .treatment: L("Treatment rooms")
        case .ward: L("Wards")
        case .cage: L("Cages")
        case .other: L("Other rooms")
        }
    }

    var hint: String {
        switch self {
        case .consult: L("Check-ups, vaccines, any visit with the vet.")
        case .grooming: L("Cuts and styling. It can hold two or three at once.")
        case .bath: L("The tub or the wash station.")
        case .surgery: L("The operating room.")
        case .treatment: L("Procedures, X-rays, the lab.")
        case .ward: L("Hospitalized patients: as many as it has places.")
        case .cage: L("One hospitalized patient.")
        case .other: L("A training area, the garden, anything else.")
        }
    }

    /// The kind's Lucide icon (web room-kinds.tsx).
    var systemImage: String {
        switch self {
        case .consult: "stethoscope"
        case .grooming: "scissors"
        case .bath: "bath"
        case .surgery: "heart-pulse"
        case .treatment: "syringe"
        case .ward: "bed-double"
        case .cage: "grid-2x2"
        case .other: "door-open"
        }
    }

    var hue: Hue {
        switch self {
        case .consult: .sky
        case .surgery: .peach
        case .treatment: .butter
        case .ward, .cage: .periwinkle
        case .grooming: .lavender
        case .bath: .teal
        case .other: .grey
        }
    }
}

enum PlacesRoomFilter: String, CaseIterable, Hashable {
    case all, visits, hospital, out, archived

    var title: String {
        switch self {
        case .all: L("All@rooms")
        case .visits: L("For visits")
        case .hospital: L("Hospital")
        case .out: L("Out of service")
        case .archived: L("Archived@rooms")
        }
    }
}

/// Where a room's out-of-service stretch stands today: on, still to come, or nothing.
struct PlacesRoomOutState: Hashable {
    enum State { case out, scheduled }
    let state: State
    let fromDay: String
    let untilDay: String?
    let reason: String?
}

/// The Rooms page's rules (web lib/rooms.ts), free of views.
enum PlacesRoomRules {
    static let nameMax = 60
    static let notesMax = 500
    static let capacityMax = 20
    static let copiesMax = 12

    static func outState(_ room: PlacesRoom, today: String) -> PlacesRoomOutState? {
        guard let out = room.outOfService, !out.fromDay.isEmpty else { return nil }
        if let until = out.untilDay, today > until { return nil }
        return PlacesRoomOutState(state: today < out.fromDay ? .scheduled : .out, fromDay: out.fromDay, untilDay: out.untilDay, reason: out.reason?.nonEmpty)
    }

    private static func fold(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func nameTaken(_ name: String, rooms: [PlacesRoom], except: String? = nil) -> Bool {
        let wanted = fold(name)
        guard !wanted.isEmpty else { return false }
        return rooms.contains { $0.id != except && !$0.isArchived && fold($0.name) == wanted }
    }

    /// "Suite 2" → ("Suite", 2); "Suite" → ("Suite", nil).
    static func splitNumbered(_ name: String) -> (stem: String, number: Int?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var digits = ""
        for character in trimmed.reversed() {
            if character.isNumber, digits.count < 3 { digits.insert(character, at: digits.startIndex) } else { break }
        }
        guard !digits.isEmpty else { return (trimmed, nil) }
        let stem = String(trimmed.dropLast(digits.count)).trimmingCharacters(in: .whitespaces)
        guard !stem.isEmpty, let number = Int(digits) else { return (trimmed, nil) }
        return (stem, number)
    }

    /// The names of `count` numbered rooms from a name, skipping numbers already taken.
    static func numberedNames(_ name: String, count: Int, existing: [PlacesRoom]) -> [String] {
        let total = max(1, min(copiesMax, count))
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return [] }
        if total == 1 { return [typed] }
        let (stem, number) = splitNumbered(typed)
        var names: [String] = []
        var next = number ?? 1
        var guardCount = 0
        while names.count < total && guardCount < 2000 {
            let candidate = String("\(stem) \(next)".prefix(nameMax))
            if !nameTaken(candidate, rooms: existing) && !names.contains(where: { fold($0) == fold(candidate) }) { names.append(candidate) }
            next += 1
            guardCount += 1
        }
        return names
    }

    /// A copy's starting name: the next free number after its own.
    static func copyName(_ name: String, existing: [PlacesRoom]) -> String {
        let (stem, number) = splitNumbered(name)
        for next in ((number ?? 1) + 1)..<1000 {
            let candidate = String("\(stem) \(next)".prefix(nameMax))
            if !nameTaken(candidate, rooms: existing) { return candidate }
        }
        return name
    }

    static func counts(_ rooms: [PlacesRoom], today: String) -> [PlacesRoomFilter: Int] {
        let active = rooms.filter { !$0.isArchived }
        return [
            .all: active.count,
            .visits: active.filter { !$0.isHospital }.count,
            .hospital: active.filter(\.isHospital).count,
            .out: active.filter { outState($0, today: today) != nil }.count,
            .archived: rooms.filter(\.isArchived).count,
        ]
    }

    static func filter(_ rooms: [PlacesRoom], _ filter: PlacesRoomFilter, today: String) -> [PlacesRoom] {
        if filter == .archived { return rooms.filter(\.isArchived) }
        let active = rooms.filter { !$0.isArchived }
        switch filter {
        case .visits: return active.filter { !$0.isHospital }
        case .hospital: return active.filter(\.isHospital)
        case .out: return active.filter { outState($0, today: today) != nil }
        default: return active
        }
    }

    static func sorted(_ rooms: [PlacesRoom]) -> [PlacesRoom] {
        rooms.sorted { a, b in
            if (a.sortOrder ?? 0) != (b.sortOrder ?? 0) { return (a.sortOrder ?? 0) < (b.sortOrder ?? 0) }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    static func groups(_ rooms: [PlacesRoom]) -> [(kind: PlacesRoomKind, rooms: [PlacesRoom])] {
        let ordered = sorted(rooms)
        return PlacesRoomKind.order.compactMap { kind in
            let inKind = ordered.filter { $0.kindEntry == kind }
            return inKind.isEmpty ? nil : (kind, inKind)
        }
    }

    /// The whole list's order after one room moves up or down among its kind; nil when it can't.
    static func move(_ rooms: [PlacesRoom], roomId: String, direction: Int) -> [String]? {
        let ordered = groups(rooms).flatMap(\.rooms)
        guard let moving = ordered.first(where: { $0.id == roomId }) else { return nil }
        let group = ordered.filter { $0.kindEntry == moving.kindEntry && $0.isArchived == moving.isArchived }
        guard let at = group.firstIndex(where: { $0.id == roomId }) else { return nil }
        let target = at + direction
        guard group.indices.contains(target) else { return nil }
        var ids = ordered.map(\.id)
        guard let a = ids.firstIndex(of: roomId), let b = ids.firstIndex(of: group[target].id) else { return nil }
        ids.swapAt(a, b)
        return ids
    }

    struct Preset: Identifiable, Hashable {
        let id: String
        let kind: PlacesRoomKind
        /// English name stem, translated by `L`.
        let name: String
        let count: Int
        let capacity: Int
    }

    /// Quick starts for a business with no rooms, from what it offers.
    static func presets(_ categories: [String]) -> [Preset] {
        var presets: [Preset] = []
        if categories.contains("vet") || categories.contains("emergency") {
            presets.append(Preset(id: "consult-2", kind: .consult, name: "Consult room", count: 2, capacity: 1))
            presets.append(Preset(id: "surgery-1", kind: .surgery, name: "Surgery", count: 1, capacity: 1))
        }
        if categories.contains("groomer") {
            presets.append(Preset(id: "grooming-1", kind: .grooming, name: "Grooming table", count: 1, capacity: 1))
            presets.append(Preset(id: "bath-1", kind: .bath, name: "Bath", count: 1, capacity: 1))
        }
        if presets.isEmpty { presets.append(Preset(id: "consult-1", kind: .consult, name: "Consult room", count: 1, capacity: 1)) }
        return presets
    }

    /// The server's refusals about rooms in words.
    static func errorText(_ error: Error, fallback: String) -> String {
        if let api = error as? APIError {
            switch api.code {
            case "room_name_taken": return L("There is already a room with that name here.")
            case "room_has_patients": return L("This room has hospitalized patients in it. Move them to another ward or cage first.")
            case "room_kind_in_use": return L("This room still has visits to come. Move them to another room before making it a ward or cage.")
            case "room_has_history": return L("This room has visits or patients in its history, so it can’t be deleted. Archive it instead.")
            case "invalid_dates": return L("Choose days from today on, the last one after the first, a year at most.")
            case "location_paused": return L("That location is paused: the plan no longer includes it.")
            default: break
            }
        }
        return Self.serverText(error, fallback: fallback)
    }

    static func serverText(_ error: Error, fallback: String) -> String {
        guard let api = error as? APIError, !api.message.isEmpty else { return fallback }
        return L(api.message)
    }
}

// MARK: - Days

enum PlacesDay {
    /// "lun 5 oct" for a "YYYY-MM-DD" day, with the year when it isn't this one.
    static func label(_ day: String) -> String {
        guard let date = DateText.parse(day) else { return day }
        let zone = Workspace.shared.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        let formatter = DateFormatter()
        formatter.locale = .app
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "EEEdMMM" : "EEEdMMMyyyy")
        return formatter.string(from: date)
    }

    /// A "YYYY-MM-DD" day as a date at noon on the business's clock.
    static func date(_ day: String) -> Date { DateText.parse(day) ?? Date() }

    static func key(_ date: Date) -> String { DateText.dayKey(date) }
}

// MARK: - Locations

struct PlacesAvailabilityDay: Codable, Hashable {
    let day: String?
    let enabled: Bool?
}

struct PlacesAvailability: Codable, Hashable {
    let timezone: String?
    let weeklySchedule: [PlacesAvailabilityDay]?
}

struct PlacesLocation: Codable, Identifiable, Hashable {
    let id: String
    let clinicId: String?
    let name: String
    let isPrimary: Bool?
    let status: String?
    let sortOrder: Int?
    let pausedAt: String?
    let timezone: String?
    let address: String?
    let phone: String?
    let email: String?
    let photoUrl: String?
    let receiptLogoUrl: String?
    let receiptName: String?
    let availability: PlacesAvailability?

    var primary: Bool { isPrimary ?? false }
    var isActive: Bool { (status ?? "active") == "active" }
    var isPaused: Bool { status == "paused" }
    var isArchived: Bool { status == "archived" }
    var zone: String { timezone?.nonEmpty ?? availability?.timezone?.nonEmpty ?? "UTC" }
    var openDays: Int? { availability?.weeklySchedule.map { $0.filter { $0.enabled == true }.count } }
}

struct PlacesLocationPlan: Decodable, Hashable {
    let allowsMultiple: Bool?
    let requiredPlan: String?
    let plan: String?
    let limit: Int?
    let used: Int?
    let paused: Int?
    let canAdd: Bool?
    let reason: String?
    let addonAvailable: Bool?
    let talkToSales: Bool?
}

/// What a location has and still holds (`withStats=true`).
struct PlacesLocationStats: Decodable, Hashable {
    let locationId: String
    let staff: Int?
    let staffOnlyHere: Int?
    let rooms: Int?
    let registers: Int?
    let stayUnits: Int?
    let futureAppointments: Int?
    let openRegisterSessions: Int?
    let activeStays: Int?
    let hospitalPatients: Int?
}

struct PlacesLocationsAnswer: Decodable {
    let stats: [PlacesLocationStats]?
    let locations: [PlacesLocation]
    let memberLocationIds: [String]?
    let plan: PlacesLocationPlan?
}

enum PlacesAddPath { case add, buyAddon, upgrade, talkToSales }

/// What still holds a location open, in the order it is said.
enum PlacesLocationBlocker: String, CaseIterable, Identifiable {
    case futureAppointments, openRegisterSessions, activeStays, hospitalPatients
    var id: String { rawValue }

    func count(_ stats: PlacesLocationStats?) -> Int {
        guard let stats else { return 0 }
        switch self {
        case .futureAppointments: return stats.futureAppointments ?? 0
        case .openRegisterSessions: return stats.openRegisterSessions ?? 0
        case .activeStays: return stats.activeStays ?? 0
        case .hospitalPatients: return stats.hospitalPatients ?? 0
        }
    }

    /// Its Lucide icon (web location-archive-sheet.tsx `BLOCKERS`).
    var systemImage: String {
        switch self {
        case .futureAppointments: "calendar-clock"
        case .openRegisterSessions: "store"
        case .activeStays: "bed-double"
        case .hospitalPatients: "heart-pulse"
        }
    }
}

enum PlacesArchiveRefusal { case primary, lastActive, inUse }

enum PlacesLocationRules {
    static let supportEmail = "contact@pawmiaw.com"

    static func sorted(_ locations: [PlacesLocation]) -> [PlacesLocation] {
        locations.sorted { a, b in
            if a.primary != b.primary { return a.primary }
            if (a.sortOrder ?? 0) != (b.sortOrder ?? 0) { return (a.sortOrder ?? 0) < (b.sortOrder ?? 0) }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    static func active(_ locations: [PlacesLocation]) -> [PlacesLocation] { sorted(locations.filter(\.isActive)) }
    static func paused(_ locations: [PlacesLocation]) -> [PlacesLocation] { sorted(locations.filter(\.isPaused)) }
    static func archived(_ locations: [PlacesLocation]) -> [PlacesLocation] { sorted(locations.filter(\.isArchived)) }

    static func canAdd(_ locations: [PlacesLocation], plan: PlacesLocationPlan?) -> Bool {
        if active(locations).isEmpty { return true }
        guard let plan else { return false }
        if let canAdd = plan.canAdd { return canAdd }
        return plan.allowsMultiple ?? false
    }

    static func addPath(_ locations: [PlacesLocation], plan: PlacesLocationPlan?) -> PlacesAddPath {
        if canAdd(locations, plan: plan) { return .add }
        if plan?.addonAvailable == true { return .buyAddon }
        if plan?.talkToSales == true { return .talkToSales }
        return .upgrade
    }

    static func nameTaken(_ name: String, locations: [PlacesLocation], except: String?) -> Bool {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return false }
        return locations.contains { $0.id != except && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted }
    }

    struct Hold: Hashable { let blocker: PlacesLocationBlocker; let count: Int }

    static func blockers(_ stats: PlacesLocationStats?) -> [Hold] {
        PlacesLocationBlocker.allCases.map { Hold(blocker: $0, count: $0.count(stats)) }.filter { $0.count > 0 }
    }

    static func archiveRefusal(_ location: PlacesLocation, locations: [PlacesLocation], stats: PlacesLocationStats?) -> PlacesArchiveRefusal? {
        if location.isActive && active(locations).count <= 1 { return .lastActive }
        if location.primary { return .primary }
        return blockers(stats).isEmpty ? nil : .inUse
    }

    /// "Mexico City" from "America/Mexico_City".
    static func city(_ zone: String) -> String {
        (zone.split(separator: "/").last.map(String.init) ?? zone).replacingOccurrences(of: "_", with: " ")
    }

    /// The time it is now at a location, on its own clock.
    static func clock(_ zone: String, at date: Date = Date()) -> String {
        DateText.time(date, zone: TimeZone(identifier: zone) ?? .current)
    }

    /// Minutes the clock moves (new − old) now.
    static func shiftMinutes(from: String, to: String, at date: Date = Date()) -> Int {
        guard let a = TimeZone(identifier: from), let b = TimeZone(identifier: to) else { return 0 }
        return (b.secondsFromGMT(for: date) - a.secondsFromGMT(for: date)) / 60
    }

    /// "1 hour later", "2 hours earlier", "1 h 30 min later".
    static func shiftLabel(_ minutes: Int) -> String {
        let later = minutes > 0
        let total = abs(minutes)
        let hours = total / 60
        let rest = total % 60
        if hours > 0 && rest > 0 { return LF(later ? "%d h %d min later" : "%d h %d min earlier", hours, rest) }
        if hours > 0 {
            if hours == 1 { return L(later ? "1 hour later" : "1 hour earlier") }
            return LF(later ? "%d hours later" : "%d hours earlier", hours)
        }
        return LF(later ? "%d minutes later" : "%d minutes earlier", rest)
    }

    /// The server's refusals (plan, name, time zone, archiving) in words.
    static func errorText(_ error: Error, name: String? = nil, limit: Int? = nil, talkToSales: Bool = false, requiredPlan: String? = nil) -> String {
        if let api = error as? APIError {
            switch api.code {
            case "location_plan_required":
                return requiredPlan == "pro" ? L("Another location needs the Business plan.") : L("Add an extra location to your plan in Subscription.")
            case "location_limit_reached":
                return talkToSales
                    ? LF("Your plan holds %d active locations. For more, talk to us about Enterprise.", limit ?? 1)
                    : LF("Your plan holds %d active locations. Add an extra location in Subscription.", limit ?? 1)
            case "location_paused":
                return name.map { LF("%@ is paused: the plan no longer includes it.", $0) } ?? L("That location is paused: the plan no longer includes it.")
            case "location_archived": return L("That location is archived.")
            case "keep_primary_required": return L("The main location always stays. Make another one the main location first.")
            case "location_name_taken": return L("Another location already has that name.")
            case "invalid_timezone": return L("Choose a valid time zone.")
            case "location_is_primary": return L("The main location can’t be archived.")
            case "location_last_active": return L("A business needs at least one active location.")
            case "invalid_location": return L("That location isn’t active in this business.")
            case "location_not_assigned": return L("You don’t work at that location.")
            default: break
            }
        }
        return PlacesRoomRules.serverText(error, fallback: L("Something went wrong. Try again."))
    }
}

// MARK: - Time zones

enum PlacesTimeZones {
    static let common = [
        "America/Mexico_City", "America/Cancun", "America/Merida", "America/Monterrey", "America/Chihuahua", "America/Mazatlan", "America/Hermosillo", "America/Tijuana",
        "America/Bogota", "America/Lima", "America/Santiago", "America/Argentina/Buenos_Aires", "America/Guatemala", "America/Costa_Rica",
        "America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles", "America/Toronto", "Europe/Madrid",
    ]

    private static let cityNames: [String: (es: String, en: String?)] = [
        "America/Mexico_City": ("Ciudad de México", nil),
        "America/Cancun": ("Cancún", "Cancún"),
        "America/Merida": ("Mérida", "Mérida"),
        "America/Mazatlan": ("Mazatlán", "Mazatlán"),
        "America/Ciudad_Juarez": ("Ciudad Juárez", "Ciudad Juárez"),
        "America/Bahia_Banderas": ("Bahía de Banderas", "Bahía de Banderas"),
        "America/Bogota": ("Bogotá", "Bogotá"),
        "America/Panama": ("Panamá", nil),
        "America/Asuncion": ("Asunción", "Asunción"),
        "America/Argentina/Cordoba": ("Córdoba", "Córdoba"),
        "America/Argentina/Tucuman": ("Tucumán", "Tucumán"),
        "America/New_York": ("Nueva York", nil),
        "America/Los_Angeles": ("Los Ángeles", nil),
        "America/Sao_Paulo": ("São Paulo", "São Paulo"),
        "Europe/London": ("Londres", nil),
    ]

    static func cityName(_ zone: String) -> String {
        if let known = cityNames[zone] {
            return LocalizationManager.shared.currentLanguage == .spanish ? known.es : (known.en ?? PlacesLocationRules.city(zone))
        }
        return PlacesLocationRules.city(zone)
    }

    static func offsetLabel(_ zone: String, at date: Date = Date()) -> String? {
        guard let tz = TimeZone(identifier: zone) else { return nil }
        let minutes = tz.secondsFromGMT(for: date) / 60
        if minutes == 0 { return "UTC" }
        let absolute = abs(minutes)
        let rest = absolute % 60
        return "UTC\(minutes < 0 ? "−" : "+")\(absolute / 60)\(rest > 0 ? String(format: ":%02d", rest) : "")"
    }

    /// "Cancún (UTC−5)".
    static func label(_ zone: String) -> String {
        if zone == "UTC" { return "UTC" }
        let city = cityName(zone)
        return offsetLabel(zone).map { "\(city) (\($0))" } ?? city
    }

    static func search(_ query: String, limit: Int = 60) -> [String] {
        let zones = TimeZone.knownTimeZoneIdentifiers
        let words = fold(query).split(separator: " ").map(String.init)
        if words.isEmpty { return common.filter { zones.contains($0) } }
        return zones.filter { zone in
            let haystack = fold(zone.replacingOccurrences(of: "_", with: " ") + " " + cityName(zone) + " " + (cityNames[zone]?.es ?? ""))
            return words.allSatisfy { haystack.contains($0) }
        }
        .prefix(limit).map { $0 }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
    }
}

// MARK: - Relocations

struct PlacesRelocationVisit: Decodable, Identifiable, Hashable {
    let id: String
    let startsAt: String
    let endsAt: String?
    let status: String?
    let locationId: String?
    let locationName: String?
    let roomId: String?
    let room: String?
    let serviceLabel: String?
    let assignedOrganizationMemberId: String?
    let assignedName: String?
    let providerClientId: String?
    let providerClientPetId: String?
    let clientName: String?
    let petName: String?
    let seriesId: String?

    var pet: String { petName?.nonEmpty ?? L("another visit") }
}

struct PlacesRelocations: Decodable {
    let visits: [PlacesRelocationVisit]?
}

struct PlacesRelocateAnswer: Decodable {
    let appointmentId: String?
    let locationId: String?
    let doubleBooked: Bool?
    let hoursOverride: Bool?
    let memberWorksThere: Bool?
}

/// A visit's time on a place's clock ("mar 30 sep, 10:00").
enum PlacesWhen {
    static func text(_ iso: String, zone: String?) -> String {
        guard let date = DateText.parse(iso) else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = .app
        formatter.timeZone = zone.flatMap(TimeZone.init(identifier:)) ?? Workspace.shared.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMMjmm")
        return formatter.string(from: date)
    }

    static func time(_ iso: String?, zone: String?) -> String {
        DateText.time(DateText.parse(iso), zone: zone.flatMap(TimeZone.init(identifier:)))
    }
}

// MARK: - Refusals with their whole body

struct PlacesConflictVisit: Decodable, Hashable {
    let id: String?
    let petName: String?
    let startsAt: String?
    let endsAt: String?
}

struct PlacesConflictOut: Decodable, Hashable {
    let untilDay: String?
    let reason: String?
}

/// One double booking the server named (lib/visit-conflicts.ts).
struct PlacesConflict: Decodable, Hashable {
    let kind: String
    let name: String?
    let capacity: Int?
    let visits: [PlacesConflictVisit]?
    let outOfService: PlacesConflictOut?
    let travelMinutes: Int?
    let postalCode: String?
}

struct PlacesRefusalBody: Decodable {
    struct Closure: Decodable { let label: String? }
    struct TimeOff: Decodable { let reason: String? }
    let error: String?
    let code: String?
    let conflicts: [PlacesConflict]?
    let reason: String?
    let closure: Closure?
    let timeOff: TimeOff?
    let memberId: String?
}

/// A refused request with the server's whole body (conflicts, the hours problem), which `APIError` doesn't keep.
struct PlacesRefusal: Error {
    let api: APIError
    let body: PlacesRefusalBody?
}

enum PlacesAPI {
    /// A POST whose refusal keeps the server's whole body: `API.post`, with the refusal's
    /// `APIError.body` read as `PlacesRefusalBody`. Offline stays an `APIError`.
    static func post<T: Decodable>(_ path: String, body: [String: Any?]) async throws -> T {
        do {
            return try await API.post(path, body: body)
        } catch let error as APIError where !error.isOffline && error.code != "decode_failed" {
            let refusal = error.body.flatMap { try? API.decoder.decode(PlacesRefusalBody.self, from: API.encoder.encode($0)) }
            throw PlacesRefusal(api: error, body: refusal)
        }
    }
}

/// What stopped one visit from moving: someone or a room taken, the place's hours, or anything else.
struct PlacesHoursProblem: Hashable {
    let reason: String
    let closureLabel: String?
    let timeOffReason: String?

    /// "Closed that day · Navidad", "Dra. Ana is off that day · Vacaciones".
    func title(person: String?) -> String {
        switch reason {
        case "closed_date":
            return closureLabel.map { LF("Closed that day · %@", $0) } ?? L("Closed that day")
        case "closed_day": return L("Closed that day of the week")
        case "break": return L("In a break between opening hours")
        case "time_off":
            if let person = person?.nonEmpty {
                return timeOffReason.map { LF("%@ is off that day · %@", person, $0) } ?? LF("%@ is off that day", person)
            }
            return timeOffReason.map { LF("That person is off that day · %@", $0) } ?? L("That person is off that day")
        case "member_hours":
            return person?.nonEmpty.map { LF("%@ doesn’t work then", $0) } ?? L("That person doesn’t work then")
        default: return L("Outside opening hours")
        }
    }
}

extension PlacesRefusal {
    var conflicts: [PlacesConflict]? { api.code == "visit_conflict" ? (body?.conflicts ?? []) : nil }
    var hours: PlacesHoursProblem? {
        guard api.code == "outside_hours" else { return nil }
        return PlacesHoursProblem(reason: body?.reason ?? "outside_hours", closureLabel: body?.closure?.label?.nonEmpty, timeOffReason: body?.timeOff?.reason?.nonEmpty)
    }
}

/// One line per conflict, in the person's words (web room-picker `conflictLine`).
enum PlacesConflictText {
    private static func visitLine(_ visit: PlacesConflictVisit, zone: String?) -> String {
        let pet = visit.petName?.nonEmpty ?? L("another visit")
        let start = PlacesWhen.time(visit.startsAt, zone: zone)
        if let end = visit.endsAt { return "\(pet) \(start)–\(PlacesWhen.time(end, zone: zone))" }
        return "\(pet) \(start)"
    }

    static func line(_ conflict: PlacesConflict, zone: String?) -> String {
        let visits = conflict.visits ?? []
        let capacity = conflict.capacity ?? 1
        if conflict.kind == "room", let out = conflict.outOfService {
            let name = conflict.name?.nonEmpty ?? L("That room")
            let line = out.untilDay.map { LF("%@ is out of service until %@", name, PlacesDay.label($0)) } ?? LF("%@ is out of service", name)
            return out.reason?.nonEmpty.map { "\(line) (\($0))" } ?? line
        }
        if visits.isEmpty && conflict.kind == "person" { return LF("%@ takes %d at once — these pets are more than that", conflict.name?.nonEmpty ?? L("That person"), capacity) }
        if visits.isEmpty && conflict.kind == "room" { return LF("%@ holds %d at once — these pets are more than that", conflict.name?.nonEmpty ?? L("That room"), capacity) }
        var listed = visits.prefix(2).map { visitLine($0, zone: zone) }.joined(separator: ", ")
        if visits.count > 2 { listed += " " + LF("and %d more", visits.count - 2) }
        switch conflict.kind {
        case "person":
            let name = conflict.name?.nonEmpty ?? L("That person")
            return capacity > 1 ? LF("%@ already has %d pets then (%@) and takes %d at once", name, visits.count, listed, capacity) : LF("%@ is already with %@", name, listed)
        case "room":
            let name = conflict.name?.nonEmpty ?? L("That room")
            return capacity > 1 ? LF("%@ is full then (%@); it holds %d.", name, listed, capacity) : LF("%@ is taken by %@", name, listed)
        case "service_area":
            let name = conflict.name?.nonEmpty ?? L("That person")
            return conflict.postalCode?.nonEmpty.map { LF("%@ is outside %@’s service area", $0, name) } ?? LF("That address is outside %@’s service area", name)
        case "travel":
            let name = conflict.name?.nonEmpty ?? L("That person")
            if let minutes = conflict.travelMinutes, minutes > 0 {
                return listed.isEmpty ? LF("%@ needs %d min to get there from another home visit", name, minutes) : LF("%@ needs %d min to get there from %@", name, minutes, listed)
            }
            return listed.isEmpty ? LF("%@ is at another address then", name) : LF("%@ is at another address then: %@", name, listed)
        default:
            return capacity == 0 ? L("Nobody who takes visits works then (days off, their own hours).") : L("Everyone who takes visits is busy then.")
        }
    }
}

// MARK: - Small shared pieces

/// A room kind's (or a related place's) round icon on a wash of its colour
/// (web: `color-mix(tone 26%, surface)`, navy glyph): the kit's `IconBadge`.
struct PlacesIconBadge: View {
    let systemImage: String
    var hue: Hue = .sky
    var size: CGFloat = 44
    var muted: Bool = false
    /// The wash of the colour behind the glyph (26 on a room, 38 on a related place).
    var washPercent: Double = 26
    /// Another colour than the hue (a related place's brand tone).
    var tone: Color? = nil

    var body: some View {
        IconBadge(icon: systemImage, accent: tone ?? hue.color, size: size, iconSize: size * 0.45, ink: .strong, washPercent: washPercent)
            .grayscale(muted ? 1 : 0)
    }
}

/// The double-booking warning with its "book anyway" confirmation (web room-picker
/// `ConflictWarning`): a box of the destructive colour at 8% with a 2 pt border,
/// a red 40 disc with the triangle, the Fredoka title, one line per conflict,
/// and the confirmation on a white row.
struct PlacesConflictWarning: View {
    let conflicts: [PlacesConflict]
    let zone: String?
    @Binding var confirmed: Bool

    private var onlyHome: Bool { conflicts.allSatisfy { $0.kind == "travel" || $0.kind == "service_area" } }
    private var onlyOut: Bool { conflicts.allSatisfy { $0.kind == "room" && $0.outOfService != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(icon: "triangle-alert", accent: Theme.destructive, size: 40, iconSize: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(onlyHome ? L("Check the home visit") : onlyOut ? L("Room out of service") : L("Double booking"))
                        .font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                    ForEach(Array(conflicts.enumerated()), id: \.offset) { _, conflict in
                        Text(PlacesConflictText.line(conflict, zone: zone)).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    }
                }
            }
            ToggleRow(title: onlyHome ? L("Book it anyway — I know") : onlyOut ? L("Book it anyway — I know it is out of service") : L("Book it anyway — I know they overlap"), isOn: $confirmed)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(Theme.destructive, 8), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.destructive, 55, with: Theme.borderSoft), lineWidth: 2))
    }
}

/// A photo of a location (web: `size-14 rounded-card`), or its pin — the store
/// for the main one — in blue on an aqua 25% disc.
struct PlacesLocationThumb: View {
    let photoUrl: String?
    var isPrimary: Bool = false
    var size: CGFloat = 48

    var body: some View {
        if let url = APIConfig.assetURL(photoUrl) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(Theme.wash(Theme.aqua, 25))
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        } else {
            Glyph(isPrimary ? "store" : "map-pin", size: 20)
                .foregroundStyle(Theme.blue)
                .frame(width: 44, height: 44)
                .background(Theme.wash(Theme.aqua, 25), in: Circle())
                .frame(width: size, height: size)
        }
    }
}

/// A plus/minus count, the web's CountStepper.
struct PlacesCountStepper: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...20

    var body: some View {
        HStack(spacing: 12) {
            IconCircleButton(systemImage: "minus", label: L("One less")) { if value > range.lowerBound { value -= 1 } }
                .disabled(value <= range.lowerBound)
                .opacity(value <= range.lowerBound ? 0.4 : 1)
            Text("\(value)")
                .font(.brandHeading(22, relativeTo: .title3))
                .foregroundStyle(Theme.inkStrong)
                .frame(minWidth: 36)
                .accessibilityLabel(LF("%@: %d", label, value))
            IconCircleButton(systemImage: "plus", label: L("One more")) { if value < range.upperBound { value += 1 } }
                .disabled(value >= range.upperBound)
                .opacity(value >= range.upperBound ? 0.4 : 1)
        }
    }
}

/// A line to read before saying yes (what archiving leaves behind, what is
/// still booked), with an optional way there: the web's lime box — 16 corners,
/// a 1.5 pt border of lime 55%, lime 10% fill, a 16 icon, 14 navy text, an
/// underlined bold link.
struct PlacesConsequenceRow: View {
    let systemImage: String
    let text: String
    /// A bold first line (the web's `font-bold` count), the text then reads soft under it.
    var title: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Glyph(systemImage, size: 16).foregroundStyle(Theme.inkStrong).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                if let title { Text(title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong) }
                Text(text).font(Theme.text(14)).foregroundStyle(title == nil ? Theme.inkStrong : Theme.inkSoft)
                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle).font(Theme.text(14, weight: .bold)).underline().foregroundStyle(Theme.inkStrong)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.wash(Theme.lime, 10), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.lime, 55, with: Theme.borderSoft), lineWidth: 1.5))
    }
}

