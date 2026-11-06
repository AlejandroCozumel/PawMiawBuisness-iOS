//
//  StaysModels.swift
//  PawMiawNegocios
//
//  Stays (boarding, daycare and home stays): the shapes the web's hooks read
//  (use-provider-stays.ts, use-provider-homestays.ts, use-family-requests.ts,
//  use-provider-online-booking.ts), the requests they send, and the small
//  helpers every stays screen shares (days, clock times, words). The rules
//  live on the server (stay-rules.ts); backend docs/stays-late-and-dates.md
//  and docs/charging-flow.md.
//

import SwiftUI
import UIKit

// MARK: - Settings and rooms

struct StaysSettings: Codable, Hashable {
    var checkInTime: String?
    var checkOutTime: String?
    var daycareStartTime: String?
    var daycareEndTime: String?
    var requiredVaccines: [String]?
    var currency: String?
}

struct StaysUnit: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let kind: String?
    let species: String?
    let capacity: Int?
    let nightlyRateCents: Int?
    let dayRateCents: Int?
    let notes: String?
    let photoUrl: String?
    let sortOrder: Int?
    let status: String?
    let locationId: String?

    var unitKind: String { kind ?? "kennel" }
    var seats: Int { max(1, capacity ?? 1) }
}

// MARK: - A stay

struct StaysCareItem: Codable, Hashable, Identifiable {
    var key: String
    var kind: String
    var label: String
    var time: String?
    var source: String?
    var sourceRoutineId: String?

    var id: String { key }

    /// The JSON the server takes (`null` for an empty time).
    var body: [String: Any?] {
        ["key": key, "kind": kind, "label": label, "time": time?.nonEmpty, "source": source ?? "front_desk", "sourceRoutineId": sourceRoutineId]
    }
}

struct StaysCarePlan: Codable, Hashable {
    var items: [StaysCareItem]?
    var notes: String?
}

struct StaysVaccineCheck: Codable, Hashable {
    let key: String
    let status: String
    let matchedName: String?
    let validUntil: String?
    let assumedOneYear: Bool?
}

struct StaysPet: Codable, Identifiable, Hashable {
    let id: String
    let providerClientPetId: String?
    let petName: String
    let petSpecies: String?
    let petBreed: String?
    let photoUrl: String?
    let linkedToHousehold: Bool?
    let carePlan: StaysCarePlan?
    let vaccineCheck: [StaysVaccineCheck]?
    let vaccinesConfirmedAt: String?
    let vaccinesConfirmedByName: String?
    let allergies: [String]?
}

struct StaysUpdate: Codable, Identifiable, Hashable {
    let id: String
    let stayPetId: String?
    let kind: String?
    let visibility: String?
    let message: String?
    let mood: String?
    let photoUrl: String?
    let authorName: String?
    let visitId: String?
    let createdAt: String?
}

struct StaysContact: Codable, Hashable {
    let name: String?
    let phone: String?
    let relationship: String?
}

/// A home stay on the board and in lists (`home` on a summary).
struct StaysHomeSummary: Codable, Hashable {
    let sitterMemberId: String?
    let sitterName: String?
    /// A line on the list; an object on the full home stay (read with `addressText`).
    let address: JSONValue?
    let mode: String?
    let priceUnit: String?
    let units: Int?

    var addressText: String? { address?.string ?? address?["formatted"]?.string }
}

/// A stay as the list and the detail send it (the detail adds `updates`).
struct StaysStay: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let status: String
    let providerClientId: String?
    let clientName: String?
    let clientPhone: String?
    let clientEmail: String?
    let unitId: String?
    let unitName: String?
    let unitKind: String?
    let checkInDay: String
    let checkInTime: String?
    let checkOutDay: String
    let checkOutTime: String?
    let checkedInAt: String?
    let checkedOutAt: String?
    let today: String?
    let lateArrival: Bool?
    let lateDeparture: Bool?
    let heldUntilDay: String?
    let rateCents: Int?
    let currency: String?
    let billableUnits: Int?
    let estimatedTotalCents: Int?
    let ownerInstructions: String?
    let internalNotes: String?
    let belongings: [String]?
    let emergencyContact: StaysContact?
    let cancellationReason: String?
    let invoiceId: String?
    let createdAt: String?
    let pets: [StaysPet]?
    let home: StaysHomeSummary?
    let updates: [StaysUpdate]?

    var petList: [StaysPet] { pets ?? [] }
    var petNames: String { petList.map(\.petName).joined(separator: ", ") }
    var petCount: Int { max(1, petList.count) }
    var isHome: Bool { kind == "home_sitting" }
    var isDaycare: Bool { kind == "daycare" }
    var isOpen: Bool { ["requested", "confirmed", "checked_in"].contains(status) }
    var familyOnApp: Bool { petList.contains { $0.linkedToHousehold == true } }
    var rate: Int { rateCents ?? 0 }
    var stayCurrency: String { currency ?? Workspace.shared.currency }

    /// A day late either way (stays-late-and-dates.md).
    var late: StaysLate? {
        if lateDeparture == true { return .departure }
        if lateArrival == true { return .arrival }
        return nil
    }
}

enum StaysLate { case arrival, departure }

struct StaysPage: Codable {
    let today: String?
    let items: [StaysStay]?
}

struct StaysIntakePet: Codable, Hashable, Identifiable {
    let stayPetId: String
    let petName: String?
    let linkedToHousehold: Bool?
    let canReadRoutines: Bool?
    let canReadVaccines: Bool?
    let vaccines: [StaysVaccineCheck]?
    let suggestedCare: [StaysCareItem]?
    let allergies: [String]?
    let carePlan: StaysCarePlan?

    var id: String { stayPetId }
}

struct StaysIntake: Codable {
    let stayId: String?
    let pets: [StaysIntakePet]?
    let suggestedEmergencyContact: StaysContact?
}

// MARK: - The day's care

struct StaysCareTask: Codable, Identifiable, Hashable {
    let id: String
    let kind: String?
    let label: String?
    let time: String?
    var status: String
    let doneAt: String?
    let doneByName: String?
    let note: String?
}

struct StaysVaccineIssue: Codable, Hashable {
    let key: String
    let status: String
}

struct StaysCarePet: Codable, Identifiable, Hashable {
    let stayId: String
    let stayPetId: String
    let petName: String
    let petSpecies: String?
    let petBreed: String?
    let photoUrl: String?
    let kind: String?
    let unitName: String?
    let checkInDay: String?
    let checkOutDay: String?
    let checkOutTime: String?
    let lateDeparture: Bool?
    let nightNumber: Int?
    let totalNights: Int?
    let clientName: String?
    let clientPhone: String?
    let rateCents: Int?
    let currency: String?
    let estimatedTotalCents: Int?
    let ownerInstructions: String?
    let belongings: [String]?
    let vaccineIssues: [StaysVaccineIssue]?
    let allergies: [String]?
    let lastReportAt: String?
    let careNotes: String?
    var tasks: [StaysCareTask]?

    var id: String { stayPetId }
}

struct StaysCareBoard: Codable {
    let dayKey: String?
    var pets: [StaysCarePet]?
}

// MARK: - Home stays

struct StaysHomeMember: Codable, Hashable {
    let memberId: String?
    let name: String?
    let photoUrl: String?
}

struct StaysHomeVisit: Codable, Identifiable, Hashable {
    let id: String
    let stayId: String?
    let kind: String?
    let dayKey: String
    let startsAt: String
    let endsAt: String?
    let status: String?
    let late: Bool?
    let sitter: StaysHomeMember?
    let arrivedAt: String?
    let arrivedByName: String?
    let leftAt: String?
    let leftByName: String?
    let missedAt: String?
    let noAccessAt: String?
    let note: String?
    let cancelReason: String?
    let doubleBooked: Bool?
}

struct StaysHomeAddress: Codable, Hashable {
    let label: String?
    let formatted: String?
    let reference: String?
    let mapsUrl: String?
    let source: String?
    let shared: Bool?
}

struct StaysHomeToday: Codable, Hashable {
    let dayKey: String?
    let total: Int?
    let done: Int?
    let inProgress: Int?
    let missed: Int?
}

struct StaysKeyHolder: Codable, Hashable { let memberId: String?; let name: String? }

struct StaysKeyEvent: Codable, Identifiable, Hashable {
    let id: String
    let action: String?
    let holderName: String?
    let label: String?
    let note: String?
    let occurredAt: String?
    let byName: String?
}

struct StaysHomeKeys: Codable, Hashable {
    let state: String?
    let holder: StaysKeyHolder?
    let label: String?
    let since: String?
    let events: [StaysKeyEvent]?
}

struct StaysVisitPlan: Codable, Hashable {
    let times: [String]?
    let durationMinutes: Int?
    let overnightStart: String?
    let overnightEnd: String?
}

struct StaysHouseTask: Codable, Hashable {
    let key: String?
    let label: String?
    let time: String?
}

struct StaysCatalogRef: Codable, Hashable { let id: String?; let name: String?; let priceCents: Int? }

struct StaysHomeDetail: Codable, Hashable {
    let address: StaysHomeAddress?
    let addressId: String?
    let accessNotes: String?
    let sitter: StaysHomeMember?
    let mode: String?
    let plan: StaysVisitPlan?
    let priceUnit: String?
    let rateCents: Int?
    let catalogItem: StaysCatalogRef?
    let units: Int?
    let estimatedTotalCents: Int?
    let depositCents: Int?
    let depositPaidCents: Int?
    let vetAuthorizationCents: Int?
    let houseRules: String?
    let houseTasks: [StaysHouseTask]?
    let quoteSentAt: String?
    let quoteAcceptedAt: String?
    let timeZone: String?
    let today: StaysHomeToday?
    let visits: [StaysHomeVisit]?
    let keys: StaysHomeKeys?
    let emergencyContact: StaysContact?
    let familyEmergencyContact: StaysContact?
    /// The family's access details for the address: what they hold and whether this person may open them.
    let vault: StaysHomeVault?
    let serviceId: String?

    var zone: TimeZone { timeZone.flatMap(TimeZone.init(identifier:)) ?? Workspace.shared.timeZone }
    var depositOwed: Int { max(0, (depositCents ?? 0) - (depositPaidCents ?? 0)) }
}

struct StaysVaultWindow: Codable, Hashable {
    let opensAt: String?
    let closesAt: String?
    let open: Bool?
}

/// The access details of a home stay's address (never their contents: those come from the audited reveal).
struct StaysHomeVault: Codable, Hashable {
    let hasVault: Bool?
    let fields: [String]?
    let window: StaysVaultWindow?
    let windows: [StaysVaultWindow]?
    let canReveal: Bool?
    /// An owner or admin outside the stay may open them, saying why (the family is shown it).
    let canEmergency: Bool?
    let reason: String?
    let assigned: Bool?
    let open: Bool?
}

/// One item of a visit's checklist: a pet's care or a house task.
struct StaysChecklistTask: Codable, Identifiable, Hashable {
    let id: String
    let label: String?
    let time: String?
    let status: String?
    let doneAt: String?
    let doneByName: String?
    let note: String?
    let kind: String?
}

struct StaysVisitPet: Codable, Hashable {
    let stayPetId: String?
    let petName: String?
    let photoUrl: String?
    let careNotes: String?
    let tasks: [StaysChecklistTask]?
}

struct StaysVisitReport: Codable, Identifiable, Hashable {
    let id: String
    let message: String?
    let mood: String?
    let photoUrl: String?
    let stayPetId: String?
    let createdAt: String?
}

/// What a visit's detail adds to the visit (`/provider-homestays/{id}/visits/{visitId}`).
struct StaysVisitExtras: Codable {
    let pets: [StaysVisitPet]?
    let houseTasks: [StaysChecklistTask]?
    let houseRules: String?
    let reports: [StaysVisitReport]?
    let pendingTasks: Int?
}

/// The home stay's own `home` (from `/provider-homestays/{id}`), read beside the stay itself.
struct StaysHomeEnvelope: Codable { let home: StaysHomeDetail? }

/// A day's home visits (the header's "Visitas de cuidado en casa hoy").
struct StaysHomeDayVisit: Codable, Identifiable, Hashable {
    let id: String
    let status: String?
    let late: Bool?
}

struct StaysHomeDay: Codable {
    let dayKey: String?
    let visits: [StaysHomeDayVisit]?
}

// MARK: - Families' requests and online bookings

struct StaysNamed: Codable, Hashable { let id: String?; let name: String? }

struct StaysRequestPet: Codable, Hashable {
    let petId: String?
    let providerClientPetId: String?
    let name: String?
    let species: String?
    let photoUrl: String?
    let vaccines: [StaysVaccineCheck]?
}

struct StaysRequest: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let status: String
    let displayStatus: String?
    let startDay: String
    let endDay: String
    let proposedStartDay: String?
    let proposedEndDay: String?
    let notes: String?
    let address: String?
    let program: String?
    let depositPercent: Int?
    let providerMessage: String?
    let familyAcceptedAt: String?
    let respondedAt: String?
    let cancelledAt: String?
    let stayIds: [String]?
    let appointmentIds: [String]?
    let providerClientId: String?
    let locationId: String?
    let clientName: String?
    let clientPhone: String?
    let location: StaysNamed?
    let createdAt: String?
    let pets: [StaysRequestPet]?

    var shownStatus: String { displayStatus ?? status }
    var petNames: String { (pets ?? []).compactMap(\.name).joined(separator: ", ") }
    var isStayKind: Bool { kind == "boarding" || kind == "daycare" }
}

struct StaysRequestList: Codable { let items: [StaysRequest]? }

/// A service of the business's visit catalog (`/appointment-services?scope=provider`), for a program's sessions.
struct StaysProgramService: Codable, Identifiable, Hashable {
    let id: String
    let label: String?
    let category: String?
    let defaultDurationMinutes: JSONValue?
}

struct StaysProgramCatalog: Codable { let services: [StaysProgramService]? }

struct StaysOnlineClient: Codable, Hashable { let id: String?; let name: String?; let phone: String? }
struct StaysOnlinePet: Codable, Hashable { let appointmentId: String?; let providerClientPetId: String?; let name: String?; let species: String?; let photoUrl: String? }

struct StaysOnlineRequest: Codable, Identifiable, Hashable {
    /// "request" or "reschedule" (a family asks to move a confirmed booking); none from an older server.
    let kind: String?
    let appointmentId: String
    /// A reschedule: the visit's time now (the time asked for is in `rescheduleProposal`).
    let startsAt: String?
    let serviceLabel: String?
    let atHome: Bool?
    let notes: String?
    /// A reschedule: when the ask expires.
    let releasesAt: String?
    let client: StaysOnlineClient?
    let pets: [StaysOnlinePet]?
    let rescheduleProposal: SchedRescheduleProposal?

    var id: String { appointmentId }
    var isReschedule: Bool { kind == "reschedule" }
}

struct StaysOnlineList: Codable {
    let count: Int?
    let items: [StaysOnlineRequest]?
}

// MARK: - Pickers

struct StaysMember: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let userName: String?
    let displayName: String?
    let email: String?
    let image: String?
    let effectivePermissions: [String]?
    let status: String?
    let isCurrentMember: Bool?

    var label: String { displayName?.nonEmpty ?? name?.nonEmpty ?? userName?.nonEmpty ?? email ?? "" }
    var canCare: Bool { (effectivePermissions ?? []).contains(Permission.staysCare.rawValue) && status != "suspended" }
}

struct StaysInvoiceTotal: Codable { let totalAmount: Int? }

struct StaysClientAddress: Codable, Identifiable, Hashable {
    let id: String
    let label: String?
    let formatted: String?
    let isDefault: Bool?
    let status: String?
}

struct StaysClientHome: Codable { let addresses: [StaysClientAddress]? }

// MARK: - A stay as consents and incidents see it

enum StaysActs {
    /// A stay's pets as consents and incidents name them (their client-pet ids).
    static func pets(of stay: StaysStay) -> [ActPet] {
        stay.petList.compactMap { pet in pet.providerClientPetId.map { ActPet(id: $0, name: pet.petName) } }
    }

    /// What a stay's Consents card knows: boarding, daycare or a home stay.
    static func consentContext(_ stay: StaysStay, businessName: String?) -> ConsentContext {
        let kind = stay.isHome ? L("Home sitting") : stay.isDaycare ? L("Daycare") : L("Boarding")
        let days = stay.isDaycare ? StaysDay.short(stay.checkInDay) : "\(StaysDay.short(stay.checkInDay)) – \(StaysDay.short(stay.checkOutDay))"
        return ConsentContext(
            act: ConsentAct(stayId: stay.id),
            businessName: businessName,
            clientName: stay.clientName ?? "",
            familyOnApp: stay.familyOnApp,
            clientEmail: stay.clientEmail,
            clientPhone: stay.clientPhone,
            pets: pets(of: stay),
            actLabel: "\(kind) · \(days)",
            started: stay.status == "checked_in" || stay.status == "checked_out",
            currency: stay.stayCurrency
        )
    }
}

// MARK: - Requests to the server

enum StaysAPI {
    /// A home stay's full detail: the stay and its `home`, from one answer.
    static func homeStay(_ id: String) async throws -> (StaysStay, StaysHomeDetail?) {
        let data = try await API.data("GET", "/provider-homestays/\(id)", query: [:], body: nil)
        let stay: StaysStay = try API.decode(data)
        let envelope: StaysHomeEnvelope = (try? API.decode(data)) ?? StaysHomeEnvelope(home: nil)
        return (stay, envelope.home)
    }
}

// MARK: - Days and clock times

enum StaysDay {
    private static let utc = TimeZone(identifier: "UTC")!

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    /// Noon UTC of a "yyyy-MM-dd" day: the calendar day, never shifted by a clock.
    static func date(_ key: String) -> Date? {
        keyFormatter.date(from: String(key.prefix(10))).map { $0.addingTimeInterval(12 * 3600) }
    }

    static func key(_ date: Date) -> String { keyFormatter.string(from: date) }

    /// Today on the business's clock.
    static func today() -> String { DateText.dayKey() }

    static func add(_ key: String, _ days: Int) -> String {
        guard let date = date(key) else { return key }
        return Self.key(date.addingTimeInterval(Double(days) * 86_400))
    }

    static func between(_ from: String, _ to: String) -> Int {
        guard let a = date(from), let b = date(to) else { return 0 }
        return Int(((b.timeIntervalSince(a)) / 86_400).rounded())
    }

    static func format(_ key: String?, _ template: String = "EEEdMMM") -> String {
        guard let key, let date = date(key) else { return "—" }
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = utc
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }

    /// "jue 1 oct".
    static func short(_ key: String?) -> String { format(key) }
    /// "1 oct".
    static func dayMonth(_ key: String?) -> String { format(key, "dMMM") }
    /// "jueves 1 de octubre".
    static func long(_ key: String?) -> String { format(key, "EEEEdMMMM") }

    static func isWeekend(_ key: String) -> Bool {
        guard let date = date(key) else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = utc
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    /// "2:00 p.m." from "14:00".
    /// Minutes after midnight of a "HH:mm" clock time.
    static func minutes(_ value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        return parts.count >= 2 ? parts[0] * 60 + parts[1] : 0
    }

    static func clock(_ value: String?) -> String {
        guard let value, value.count >= 4 else { return "" }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return value }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = utc
        guard let date = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: parts[0], minute: parts[1])) else { return value }
        let f = DateFormatter(); f.locale = .app; f.timeZone = utc; f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: date)
    }

    /// "18:30" on a clock, from an instant.
    /// "HH:mm" of a moment on a place's clock (the value a time field holds).
    static func clockKey(_ iso: String?, zone: TimeZone) -> String {
        guard let date = DateText.parse(iso) else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func clockAt(_ iso: String?, zone: TimeZone) -> String {
        DateText.time(DateText.parse(iso), zone: zone)
    }

    /// Clock times every `step` minutes between two "HH:MM".
    static func times(from: String = "00:00", to: String = "23:45", step: Int = 15) -> [String] {
        func minutes(_ s: String) -> Int { let p = s.split(separator: ":").compactMap { Int($0) }; return p.count == 2 ? p[0] * 60 + p[1] : 0 }
        return stride(from: minutes(from), through: minutes(to), by: step).map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }
    }

    /// Nights (or days of daycare) a stay counts, as on the server.
    static func nights(kind: String, from: String, to: String) -> Int {
        kind == "daycare" ? max(1, between(from, to) + 1) : max(1, between(from, to))
    }

    /// Nights (or the day) a stay holds its room.
    static func occupied(kind: String, from: String, to: String) -> [String] {
        let length = kind == "daycare" ? 1 : max(between(from, to), 1)
        return (0..<length).map { add(from, $0) }
    }

    static func isRoomHolding(_ status: String) -> Bool { ["requested", "confirmed", "checked_in"].contains(status) }

    /// A playroom takes daycare, never a night.
    static func roomTakes(unitKind: String, stayKind: String) -> Bool { stayKind != "boarding" || unitKind != "playroom" }

    /// The first day a room would be over capacity with this booking, or nil.
    static func firstFullDay(capacity: Int, stays: [StaysStay], unitId: String, kind: String, from: String, to: String, pets: Int, ignore: String? = nil) -> String? {
        var load: [String: Int] = [:]
        for stay in stays where stay.unitId == unitId && stay.id != ignore && isRoomHolding(stay.status) {
            for day in occupied(kind: stay.kind, from: stay.checkInDay, to: stay.heldUntilDay ?? stay.checkOutDay) {
                load[day, default: 0] += stay.petCount
            }
        }
        for day in occupied(kind: kind, from: from, to: to) where (load[day] ?? 0) + pets > capacity { return day }
        return nil
    }
}

// MARK: - Words

enum StaysWords {
    static func kind(_ kind: String) -> String {
        switch kind {
        case "daycare": L("Daycare")
        case "home_sitting": L("Home sitting")
        default: L("Boarding")
        }
    }

    static func status(_ status: String) -> String {
        switch status {
        case "requested": L("Requested")
        case "confirmed": L("Confirmed")
        case "checked_in": L("Staying")
        case "checked_out": L("Checked out")
        case "cancelled": L("Cancelled (stay)")
        case "no_show": L("No-show")
        default: status
        }
    }

    static func unitKind(_ kind: String?) -> String {
        switch kind {
        case "suite": L("Suite")
        case "condo": L("Cat condo")
        case "run": L("Run")
        case "playroom": L("Playroom")
        default: L("Kennel")
        }
    }

    static let unitKinds = ["kennel", "suite", "condo", "run", "playroom"]

    static func species(_ species: String?) -> String {
        switch species {
        case "any": L("All pet types")
        case "dog": L("Dogs")
        case "cat": L("Cats")
        case "bird": L("Birds")
        case "rabbit": L("Rabbits")
        case "fish": L("Fish")
        case "reptile": L("Reptiles")
        case "small_pet": L("Small pets (hamsters, guinea pigs, etc.)")
        default: L("Other animals")
        }
    }

    static let speciesKeys = ["any", "dog", "cat", "bird", "rabbit", "fish", "reptile", "small_pet", "other"]

    static func petSpecies(_ species: String?) -> String {
        switch species?.lowercased() {
        case "cat": L("Cat")
        case "dog": L("Dog")
        default: (species ?? "").capitalized
        }
    }

    static func vaccine(_ key: String) -> String {
        switch key {
        case "rabies": L("Rabies")
        case "dhpp": L("DHPP (distemper, parvo)")
        case "bordetella": L("Bordetella (kennel cough)")
        case "canine_influenza": L("Canine influenza")
        case "fvrcp": L("FVRCP (feline triple)")
        case "felv": L("FeLV (feline leukemia)")
        default: key
        }
    }

    /// "Rabia" without the explanation in brackets.
    static func vaccineShort(_ key: String) -> String {
        vaccine(key).components(separatedBy: " (").first ?? vaccine(key)
    }

    static let vaccineKeys = ["rabies", "dhpp", "bordetella", "canine_influenza", "fvrcp", "felv"]

    static func vaccineSpecies(_ key: String) -> String {
        switch key {
        case "rabies": "both"
        case "fvrcp", "felv": "cat"
        default: "dog"
        }
    }

    static func vaccineStatus(_ status: String) -> String {
        switch status {
        case "current": L("Up to date")
        case "expires_during_stay": L("Expires during the stay")
        case "expired": L("Expired")
        default: L("Not on file")
        }
    }

    static func task(_ kind: String) -> String {
        switch kind {
        case "meal": L("Meal")
        case "medication": L("Medication")
        case "walk": L("Walk")
        case "play": L("Play")
        default: L("Care")
        }
    }

    static let taskKinds = ["meal", "medication", "walk", "play", "custom"]

    static func taskIcon(_ kind: String?) -> String {
        switch kind {
        // The web's TASK_ICONS (care-plan-editor.tsx).
        case "meal": "utensils-crossed"
        case "medication": "pill"
        case "walk": "footprints"
        case "play": "bone"
        default: "heart-handshake"
        }
    }

    static let moods: [(value: String, emoji: String, label: String)] = [
        ("happy", "😊", "Happy"), ("playful", "🎾", "Playful"), ("calm", "😌", "Calm"), ("shy", "🙈", "Shy"), ("tired", "😴", "Sleepy"),
    ]

    static func mood(_ value: String?) -> (emoji: String, label: String)? {
        moods.first { $0.value == value }.map { ($0.emoji, L($0.label)) }
    }

    /// "in 3 hours", "in 40 min", "now": how long until an online booking is released.
    static func releaseIn(_ releasesAt: String?) -> String? {
        guard let date = DateText.parse(releasesAt) else { return nil }
        let minutes = Int((date.timeIntervalSinceNow / 60).rounded())
        if minutes <= 1 { return L("now") }
        if minutes < 60 { return LF("in %@ min", String(minutes)) }
        let hours = Int((Double(minutes) / 60).rounded())
        return hours == 1 ? L("in 1 hour") : LF("in %@ hours", String(hours))
    }

    /// "3 nights" / "1 day".
    static func units(_ kind: String, _ count: Int) -> String {
        kind == "daycare" ? LP(count, "%d day", "%d days") : LP(count, "%d night", "%d nights")
    }

    static func requestKind(_ kind: String) -> String {
        switch kind {
        case "boarding": L("Hotel stay")
        case "daycare": L("Daycare")
        case "homestay": L("Home stay")
        default: L("Program")
        }
    }

    static func requestKindIcon(_ kind: String) -> String {
        switch kind {
        case "daycare": "sun.max.fill"
        case "homestay": "house.fill"
        case "program": "graduationcap.fill"
        default: "bed.double.fill"
        }
    }

    /// The request's status as the business reads it, in one of the six states.
    static func requestStatus(_ request: StaysRequest) -> (String, ProviderState) {
        switch request.shownStatus {
        case "pending": request.familyAcceptedAt != nil ? (L("Dates accepted"), .done) : (L("New"), .waiting)
        case "proposed": (L("Waiting for the family"), .upcoming)
        case "confirmed": (L("Confirmed"), .done)
        case "declined": (L("Declined"), .closed)
        case "cancelled": (L("Cancelled (stay)"), .closed)
        case "expired": (L("Dates passed"), .closed)
        default: (request.shownStatus, .closed)
        }
    }

    /// "jue 1 oct – dom 4 oct", or one day.
    static func requestRange(_ kind: String, _ start: String, _ end: String) -> String {
        kind == "program" || start == end ? StaysDay.short(start) : "\(StaysDay.short(start)) – \(StaysDay.short(end))"
    }

    static func requestLength(_ kind: String, _ start: String, _ end: String) -> String? {
        if kind == "program" { return nil }
        if kind == "boarding" { return LP(max(1, StaysDay.between(start, end)), "%d night", "%d nights") }
        return LP(StaysDay.between(start, end) + 1, "%d day", "%d days")
    }

    static func homeVisitKind(_ kind: String?) -> String {
        switch kind {
        case "overnight": L("Night")
        case "meet_greet": L("Meet & greet")
        default: L("Visit")
        }
    }

    static func homeVisitStatus(_ status: String?) -> (String, ProviderState) {
        switch status {
        case "in_progress": (L("In progress"), .active)
        case "done": (L("Done"), .done)
        case "missed": (L("Missed visit"), .problem)
        case "cancelled": (L("Cancelled (stay)"), .closed)
        default: (L("Planned"), .upcoming)
        }
    }

    static func homeStatus(_ stay: StaysStay, quoteSent: Bool) -> String {
        switch stay.status {
        case "requested": quoteSent ? L("Quote sent") : L("Not confirmed")
        case "confirmed": L("Confirmed")
        case "checked_in": L("Under way")
        case "checked_out": L("Finished")
        case "cancelled": L("Cancelled (stay)")
        case "no_show": L("No-show")
        default: L("Not confirmed")
        }
    }

    static func keysState(_ keys: StaysHomeKeys?) -> String {
        switch keys?.state {
        case "with_sitter": LF("With %@", keys?.holder?.name ?? L("the sitter"))
        case "lockbox": L("In the lockbox")
        case "returned": L("Returned to the family")
        default: L("Not received yet")
        }
    }

    static func keyAction(_ event: StaysKeyEvent) -> String {
        switch event.action {
        case "received": LF("Received by %@", event.holderName ?? L("the sitter"))
        case "transferred": LF("Passed on to %@", event.holderName ?? L("the sitter"))
        case "lockbox": L("Left in the lockbox")
        default: L("Returned to the family")
        }
    }

    /// A refusal from the home stays routes, in the reader's words.
    static func homeError(_ error: Error, fallback: String) -> String {
        guard let api = error as? APIError else { return errorText(error, fallback: L(fallback)) }
        let known: [String: String] = [
            "address_required": "Choose the client’s address. Add one if they have none yet.",
            "pets_required": "Choose at least one pet.",
            "invalid_dates": "Choose valid dates: the family comes back after they leave.",
            "too_long": "A home stay lasts 60 days at most.",
            "overnight_needs_a_night": "An overnight stay needs at least one night. Choose a later return day, or plan visits instead.",
            "times_required": "Add at least one visit time.",
            "too_many_times": "Up to six visits a day.",
            "invalid_duration": "Visits last between 15 minutes and 4 hours.",
            "invalid_overnight": "A night starts in the evening and ends the next morning.",
            "visits_overlap": "Two visits of the same day overlap, or a daytime visit runs into the night.",
            "no_visits": "Those dates and times leave no visit to make. Check the times against when the family leaves and comes back.",
            "invalid_member": "Choose someone from your team.",
            "member_cannot_care": "That person can’t look after stays. Give them “Care and report cards” in Staff first.",
            "member_not_at_location": "That person doesn’t work at this location.",
            "visit_conflict": "The sitter is busy then. Check the warning and book it anyway if you meant to.",
            "stay_closed": "This home stay is closed.",
            "not_a_quote": "Only a home stay not yet confirmed can be sent as a quote.",
            "price_required": "Set the price before sending the quote.",
            "deposit_required": "The deposit isn’t in yet. Take it first, or confirm without it.",
            "deposit_waive_forbidden": "Only owners and admins can confirm without the deposit.",
            "stale": "Someone else just changed this. It has been refreshed — try again.",
            "keys_out": "The keys are still out. Record them returned, or say they will be returned later.",
            "not_started": "The stay hasn’t started yet. Mark the first visit’s arrival, or cancel it.",
            "quote_closed": "This quote was already answered.",
        ]
        if let code = api.code, let sentence = known[code] { return L(sentence) }
        if api.status >= 500 { return L(fallback) }
        return api.message.isEmpty ? L(fallback) : api.message
    }

    /// A family request refusal, in the reader's words (lib/family-requests.ts).
    static func requestError(_ error: Error) -> String {
        guard let api = error as? APIError else { return errorText(error) }
        let known: [String: String] = [
            "already_booked": "There is already a stay booked for these dates.",
            "request_closed": "This request already changed. Refresh to see it.",
            "dates_passed": "These dates have passed. Propose new dates instead.",
            "same_dates": "Those are the dates the family asked for. Confirm the request instead.",
            "visits_required": "Add at least one visit.",
            "client_missing": "This family’s pets are not on a client file yet.",
            "service_not_offered": "That service is not offered. Choose another.",
            "reason_required": "Tell the family why.",
            "past_date": "Choose a date from today on.",
            "too_long": "That is longer than can be asked for at once.",
            "same_day_boarding": "A hotel stay needs at least one night.",
            "invalid_dates": "Choose valid dates, the first one before the last.",
        ]
        if let code = api.code, let sentence = known[code] { return L(sentence) }
        return errorText(error)
    }
}

// MARK: - Small shared views

/// An uppercase label over a group (the web's small teal eyebrow: 12 bold, tracked 0.14em).
struct StaysEyebrow: View {
    let text: String
    var tint: Color = Theme.blueText
    var body: some View {
        Text(text.uppercased()).font(.brandText(12, weight: .bold)).tracking(12 * 0.14).foregroundStyle(tint)
    }
}

/// A red line for a pet a day late (stays-late-and-dates.md).
struct StaysLateLine: View {
    let stay: StaysStay
    var body: some View {
        if let late = stay.late {
            Text(late == .departure ? LF("Was due out %@", StaysDay.short(stay.checkOutDay)) : LF("Was due in %@", StaysDay.short(stay.checkInDay)))
                .font(Theme.text(12, weight: .bold))
                .foregroundStyle(Theme.destructive)
                .lineLimit(1)
        }
    }
}

/// A row inside a card washed in a colour (web: a `rounded-box` row at the
/// accent's 16%, with a 3 pt left edge when it needs someone).
struct StaysTintedRow<Content: View>: View {
    var tint: Color
    var percent: Double = 16
    var edge: Color? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) { content() }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wash(tint, percent))
            .overlay(alignment: .leading) { if let edge { Rectangle().fill(edge).frame(width: 3) } }
            .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// A sheet's field with no label of its own (web: an `Input`/`Textarea` whose placeholder says
/// what goes in, under a section title that names it): the input chrome and, when invalid, its
/// sentence under it.
struct StaysPlainField: View {
    let prompt: String
    @Binding var text: String
    var key: String? = nil
    var form: FormState? = nil
    var keyboard: UIKeyboardType = .default
    var multiline: Bool = false
    var lines: ClosedRange<Int> = 3...8

    private var error: String? { key.flatMap { form?.error($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if multiline {
                    TextField(prompt, text: $text, axis: .vertical).lineLimit(lines)
                } else {
                    TextField(prompt, text: $text)
                }
            }
            .keyboardType(keyboard)
            .fieldChrome(invalid: error != nil, multiline: multiline)
            .onChange(of: text) { _, _ in if let key { form?.clear(key) } }
            if let error { Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
        }
        .id(key ?? prompt)
    }
}

/// A sheet's select with no label of its own (web: a `NativeSelect` under a section title that
/// names it): the input chrome with a chevron, a menu of the options.
struct StaysPlainMenu<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var accessibility: String = ""
    var key: String? = nil
    var form: FormState? = nil

    private var error: String? { key.flatMap { form?.error($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                .fieldChrome(invalid: error != nil)
            }
            .accessibilityLabel(accessibility)
            if let error { Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
        }
        .id(key ?? accessibility)
    }
}

/// An amount with no label of its own (web: a bare decimal input, "0.00"), typed as text and read
/// as cents; the currency after it when given.
struct StaysPlainMoney: View {
    @Binding var cents: Int?
    var prompt: String = "0"
    var currency: String? = nil
    var key: String? = nil
    var form: FormState? = nil
    @State private var text = ""

    private var error: String? { key.flatMap { form?.error($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(prompt, text: $text)
                    .keyboardType(.decimalPad)
                    .fieldChrome(invalid: error != nil)
                if let currency { Text(currency).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkSoft) }
            }
            if let error { Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
        }
        .id(key ?? "money")
        .onAppear { if text.isEmpty, let cents { text = Money.input(cents) } }
        .onChange(of: cents) { _, value in if Money.parse(text) != value { text = Money.input(value) } }
        .onChange(of: text) { _, value in
            cents = Money.parse(value)
            if let key { form?.clear(key) }
        }
    }
}

/// A checkbox line in a sheet (web: a `label` with the `Checkbox`, an optional teal icon and the
/// words): bordered, or on the muted fill (`muted`), the whole line toggles it.
struct StaysTickRow: View {
    let title: String
    var icon: String? = nil
    var muted: Bool = false
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 12) {
                Tick(on: isOn)
                HStack(spacing: 8) {
                    if let icon { Glyph(icon, size: 16).foregroundStyle(Theme.blueText) }
                    Text(title).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, muted ? 12 : 10)
            .background(muted ? Theme.surfaceMuted : Color.clear, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay {
                if !muted { RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}

/// A fact in a bordered box with a small uppercase label (web home-stay-bits `SummaryTile`).
struct StaysSummaryTile<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(Theme.text(10.9, weight: .bold)).tracking(10.9 * 0.14).foregroundStyle(Theme.inkSoft)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }
}

/// A vaccine against the stay rules, in its state's colour.
struct StaysVaccineChip: View {
    let key: String
    let status: String
    var body: some View {
        StatusChip(text: "\(StaysWords.vaccineShort(key)): \(StaysWords.vaccineStatus(status))", state: ProviderState.vaccine(status), outlined: status != "current")
    }
}

/// The clinic's allergies on file (web: a chip-cornered box, destructive 9%,
/// TriangleAlert in red, "Alergias:" bold).
struct StaysAllergies: View {
    let allergies: [String]
    var body: some View {
        if !allergies.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Glyph("triangle-alert", size: 16).foregroundStyle(Theme.destructive).padding(.top, 2)
                (Text(L("Allergies") + ": ").bold() + Text(allergies.joined(separator: ", ")))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wash(Theme.destructive, 9), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
        }
    }
}

/// A labelled block of text (web `NoteBlock`: a bordered box, the label in
/// 12 bold uppercase). With a tint it is the care board's washed note (the
/// owner's words in aqua with its 4 pt edge, the plan's notes in mango).
struct StaysNoteBlock: View {
    let label: String
    let text: String
    var tint: Color? = nil

    var body: some View {
        Group {
            if let tint {
                (label.isEmpty ? Text(text) : Text(label + ": ").bold() + Text(text))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.wash(tint, 14))
                    .overlay(alignment: .leading) { if tint == Theme.aqua { Rectangle().fill(tint).frame(width: 4) } }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label.uppercased()).font(.brandText(12, weight: .bold)).tracking(12 * 0.12).foregroundStyle(Theme.inkSoft)
                    Text(text).font(Theme.text(14)).foregroundStyle(Theme.inkStrong).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            }
        }
    }
}

