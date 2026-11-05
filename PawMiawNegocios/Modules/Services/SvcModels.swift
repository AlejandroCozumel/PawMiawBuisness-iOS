//
//  SvcModels.swift
//  PawMiawNegocios
//
//  The Services module's shapes (Estética, Domicilio, Paseos y clases), from
//  the web's hooks: use-provider-grooming.ts, use-provider-home-visits.ts,
//  use-provider-sessions.ts, use-provider-care.ts. Anything that may be
//  absent is Optional, so an older or newer server never breaks a screen.
//

import Foundation

// MARK: - Shared references

struct SvcPetRef: Codable, Hashable {
    let id: String
    let name: String
    let species: String?
    let breed: String?
    let photoUrl: String?
}

struct SvcClientRef: Codable, Hashable {
    let id: String
    let name: String
    let firstName: String?
    let phone: String?
    let onPawMiaw: Bool?

    var shortName: String { firstName?.nonEmpty ?? name }
}

struct SvcPersonRef: Codable, Hashable {
    let id: String
    let name: String?
}

/// What a groom's or home visit's bill needs: none, needs_price, unpaid, paid, no_charge.
enum SvcBilling {
    static func label(_ billing: String?) -> String? {
        switch billing {
        case "needs_price": L("Needs a price")
        case "unpaid": L("Unpaid")
        case "paid": L("Paid")
        case "no_charge": L("No charge")
        default: nil
        }
    }

    static func state(_ billing: String?) -> ProviderState {
        switch billing {
        case "paid": .done
        case "no_charge": .closed
        default: .waiting
        }
    }
}

// MARK: - Grooming

struct SvcGroomItem: Codable, Identifiable, Hashable {
    let appointmentId: String
    let status: String?
    let groomStage: String
    let startsAt: String
    let carriedOver: Bool?
    let arrivedAt: String?
    let serviceLabel: String?
    let pet: SvcPetRef
    let client: SvcClientRef
    let groomer: SvcPersonRef?
    let requestSummary: String?
    let handlingTags: [String]?
    let careNotes: String?
    let usualStyle: String?
    let readyNotifiedAt: String?
    let readyChannel: String?
    let readySince: String?
    let attention: String?
    let hasAfterPhoto: Bool?
    let billing: String?

    var id: String { appointmentId }
}

struct SvcGroomingToday: Codable {
    let date: String
    let timeZone: String?
    let counts: [String: Int]?
    let items: [SvcGroomItem]
    let needsSomeone: Int?

    func count(_ stage: String) -> Int { counts?[stage] ?? 0 }
    var total: Int { SvcGroomStage.all.reduce(0) { $0 + count($1) } }
    var inProgress: Int { count("bath") + count("styling") }
    var ready: Int { count("ready") }
}

struct SvcGroomPetRow: Codable, Identifiable, Hashable {
    let pet: SvcPetRef
    let client: SvcClientRef
    let lastGroomAt: String?
    let lastServiceLabel: String?
    let groomCount: Int?
    let usualStyle: String?
    let handlingTags: [String]?
    let rebookEveryWeeks: Int?
    let effectiveRebookWeeks: Int?
    let nextGroomDueAt: String?
    let nextBookedAt: String?
    let lastAfterPhotoUrl: String?

    var id: String { pet.id }
}

struct SvcGroomPetCounts: Codable, Hashable {
    let pets: Int?
    let overdue: Int?
    let soon: Int?
}

struct SvcGroomPetsPage: Codable {
    let total: Int?
    let counts: SvcGroomPetCounts?
    let items: [SvcGroomPetRow]
}

struct SvcGroomHistoryItem: Codable, Identifiable, Hashable {
    let appointmentId: String
    let at: String
    let status: String?
    let serviceLabel: String?
    let groomerName: String?
    let requestSummary: String?
    let report: SvcReport?

    var id: String { appointmentId }
}

struct SvcGroomHistory: Codable { let items: [SvcGroomHistoryItem] }

struct SvcGroomingSettings: Codable, Equatable {
    var defaultRebookWeeks: Int?
    var readyMessage: String?
    var simpleStages: Bool
}

struct SvcGroomReadyResult: Decodable {
    let id: String?
    let groomStage: String?
    let link: String?
}

/// The care card a groomer or walker keeps about a pet (`/provider-client-pets/{id}/care`).
struct SvcCareProfile: Codable, Hashable {
    let providerClientPetId: String
    let groomStyle: String?
    let groomTools: String?
    let groomProducts: String?
    let handlingTags: [String]?
    let careNotes: String?
    let rebookEveryWeeks: Int?
    let effectiveRebookWeeks: Int?
    let updatedAt: String?
    let lastGroomAt: String?
    let nextGroomDueAt: String?
    let nextBookedAt: String?
    /// The last visits' reports, newest first (a groom's "last time").
    var lastReports: [SvcCareLastReport]? = nil
}

struct SvcCareLastReport: Codable, Hashable {
    let appointmentId: String?
    let at: String?
    let serviceLabel: String?
    let report: SvcReport?
}

// MARK: - Due back (grooming rows of /provider-due)

struct SvcDueItem: Codable, Identifiable, Hashable {
    let key: String
    let reason: String
    let title: String?
    let dueAt: String
    let days: Int?
    let bucket: String
    let followUpId: String?
    let nextVisit: SvcDueNextVisit?
    let pet: SvcPetRef
    let client: SvcClientRef
    let lastVisitAt: String?
    let lastContact: SvcDueContact?
    /// A visit booked for it that didn't happen (or was cancelled): why it is here again.
    var missedVisitAt: String? = nil
    /// Put off until this day.
    var snoozedUntil: String? = nil
    /// PawMiaw tells the family a week before, once.
    var familyNotice: SvcDueFamilyNotice? = nil

    var id: String { key }
}

struct SvcDueFamilyNotice: Codable, Hashable { let asked: Bool?; let sentAt: String? }

struct SvcDueNextVisit: Codable, Hashable { let id: String; let startsAt: String; let serviceLabel: String? }
struct SvcDueContact: Codable, Hashable { let channel: String; let at: String }

struct SvcDueList: Codable {
    let now: String?
    let windowDays: Int?
    let items: [SvcDueItem]
}

struct SvcRemindResult: Decodable { let channel: String?; let link: String?; let sentTo: Int? }

// MARK: - Home visits (Domicilio)

struct SvcStampSummary: Codable, Hashable {
    let status: String
    let recordedAt: String?
    let distanceM: Double?
    let far: Bool?
}

struct SvcHomeVisitPet: Codable, Identifiable, Hashable {
    let id: String
    let appointmentId: String?
    let name: String
    let species: String?
    let breed: String?
    let photoUrl: String?
    let handlingTags: [String]?
    let careNotes: String?
    let allergies: [String]?
}

struct SvcMapLinks: Codable, Hashable { let google: String?; let apple: String?; let waze: String? }

struct SvcHomeAddress: Codable, Hashable {
    let label: String?
    let line: String?
    let formatted: String?
    let reference: String?
    let hasCoordinates: Bool?
    let shared: Bool?
    let maps: SvcMapLinks?
}

struct SvcHomeAccess: Codable, Hashable {
    let notes: String?
    let hasVault: Bool?
    let fields: [String]?
    let canReveal: Bool?
    let canEmergency: Bool?
    let reason: String?
}

struct SvcOnMyWayState: Codable, Hashable {
    let offered: Bool?
    let at: String?
    let channel: String?
    let minutes: Int?
}

struct SvcHomeActions: Codable, Hashable {
    let onMyWay: Bool?
    let arrive: Bool?
    let finish: Bool?
    let reassign: Bool?
}

struct SvcChecklistCount: Codable, Hashable { let done: Int; let total: Int }
struct SvcRoutePresence: Codable, Hashable { let tracking: Bool?; let points: Int? }
struct SvcStamps: Codable, Hashable { let arrive: SvcStampSummary?; let finish: SvcStampSummary? }

struct SvcHomeVisitItem: Codable, Identifiable, Hashable {
    let id: String
    let source: String
    let appointmentId: String?
    let stayId: String?
    let stayVisitId: String?
    let kind: String?
    let status: String
    var phase: String
    let startsAt: String
    let endsAt: String?
    let bookedMinutes: Int?
    var arrivedAt: String?
    var finishedAt: String?
    var late: Bool?
    var lateMinutes: Int?
    var runningLong: Bool?
    let shortVisit: Bool?
    let serviceCategory: String?
    let serviceId: String?
    let serviceLabel: String?
    let reportKind: String?
    let hasReport: Bool?
    let reportMissing: [String]?
    let pets: [SvcHomeVisitPet]
    let client: SvcClientRef
    let assigned: SvcPersonRef?
    let address: SvcHomeAddress?
    let access: SvcHomeAccess?
    let instructions: String?
    let checklist: SvcChecklistCount?
    let onMyWay: SvcOnMyWayState?
    let billing: String?
    let stamps: SvcStamps?
    var actions: SvcHomeActions?
    /// Walks with routes on: whether it is recording and how many points it has.
    var route: SvcRoutePresence? = nil

    var isStay: Bool { source == "stay_visit" }
    var petNames: String { pets.map(\.name).joined(separator: ", ").nonEmpty ?? "—" }
    var closed: Bool { phase == "done" || phase == "missed" }

    /// What the visit is: an appointment's own label; a home stay's visit by its kind.
    var serviceText: String {
        guard isStay else { return serviceLabel?.nonEmpty ?? "—" }
        switch kind {
        case "meet_greet": return L("Meet & greet")
        case "overnight": return L("Overnight")
        default: return L("Drop-in")
        }
    }
}

struct SvcHomeViewer: Codable, Hashable {
    let memberId: String?
    let seesAll: Bool?
    let isManager: Bool?
    let canAct: Bool?
    let canStayCare: Bool?
    let canReassign: Bool?
    let seesBilling: Bool?
}

struct SvcHomeDaySettings: Codable, Hashable {
    let lateAfterMinutes: Int?
    let shortVisitPercent: Int?
    let locationStamps: Bool?
    let walkRoutes: Bool?
    let onMyWayCategories: [String]?
}

struct SvcHomeCounts: Codable, Hashable {
    let total: Int?
    let upcoming: Int?
    let inProgress: Int?
    let done: Int?
    let missed: Int?
    let late: Int?
    let runningLong: Int?
}

struct SvcHomePerson: Codable, Hashable, Identifiable {
    let memberId: String?
    let name: String?
    let image: String?
    let total: Int
    let done: Int
    let inProgress: Int
    let late: Int

    var key: String { memberId ?? "unassigned" }
    var id: String { key }
}

struct SvcHomeVisitsDay: Codable {
    let date: String
    let timeZone: String?
    let now: String?
    let isToday: Bool?
    let viewer: SvcHomeViewer?
    let settings: SvcHomeDaySettings?
    let counts: SvcHomeCounts?
    let people: [SvcHomePerson]?
    let items: [SvcHomeVisitItem]
}

struct SvcHomeVisitSettings: Codable, Equatable {
    var autoStartedNotice: Bool?
    var onMyWayMessage: String?
    var onMyWayCategories: [String]?
    var lateAfterMinutes: Int?
    var shortVisitPercent: Int?
    var locationStamps: Bool?
    var farFromAddressMeters: Int?
    var walkRoutes: Bool?
    var locationRetentionDays: Int?
    var locationDisclosure: SvcDisclosure?
}

struct SvcDisclosure: Codable, Equatable { let version: Int?; let acknowledgedAt: String?; let acknowledgedByName: String? }

struct SvcStamp: Codable, Hashable {
    let status: String
    let latitude: Double?
    let longitude: Double?
    let accuracyM: Double?
    let capturedAt: String?
    let recordedAt: String?
    let recordedByName: String?
    let distanceM: Double?
    let far: Bool?
    let mapsUrl: String?
}

struct SvcHomeVisitCheck: Codable {
    let bookedMinutes: Int?
    let actualMinutes: Int?
    let shortVisit: Bool?
    let shortVisitPercent: Int?
    let address: SvcCheckAddress?
    let stamps: SvcCheckStamps?
}

struct SvcCheckAddress: Codable { let formatted: String?; let hasCoordinates: Bool? }
struct SvcCheckStamps: Codable { let arrive: SvcStamp?; let finish: SvcStamp? }

struct SvcOnMyWayResult: Decodable { let link: String?; let sentTo: Int? }

struct SvcVaultReveal: Decodable {
    let vault: [String: String]
    let revealedAt: String?
}

// MARK: - Sessions (Paseos y clases)

struct SvcSessionPet: Codable, Hashable, Identifiable {
    let appointmentId: String
    let providerClientPetId: String
    let providerClientId: String
    let name: String
    let species: String?
    let photoUrl: String?
    let status: String
    let clientName: String

    var id: String { appointmentId }
    var gone: Bool { ["cancelled", "canceled", "no_show"].contains(status) }
}

struct SvcSession: Codable, Identifiable, Hashable {
    let id: String
    let kind: String?
    let status: String
    let serviceLabel: String
    let serviceCategory: String?
    let serviceId: String?
    let startsAt: String
    let endsAt: String
    let capacity: Int?
    let priceAmount: Int?
    let onlineBooking: Bool?
    let onlineBookingOpen: Bool?
    let size: Int
    let pets: [SvcSessionPet]
    let locationId: String?
    let assignedMember: SvcPersonRef?
    let roomId: String?
    let room: String?
    let notes: String?
    let cancelReason: String?
    let placesLeft: Int?
    let full: Bool?
    let waitlistCount: Int?
    let startMode: String?
    let meetingPoint: String?
    let reportsMissing: Int?

    var staying: [SvcSessionPet] { pets.filter { !$0.gone } }
    var isPickup: Bool { startMode == "pickup" }
    var active: Bool { status == "active" }
    var placesText: String { capacity.map { "\(size)/\($0)" } ?? "\(size)" }
}

struct SvcRosterEntry: Codable, Hashable {
    let appointmentId: String
    let status: String?
    let arrivedAt: String?
    let startedAt: String?
    let finishedAt: String?
    let onMyWayAt: String?
    let address: String?
    let serviceAddressId: String?
    let accessNotes: String?
    let pickupOrder: Int?
    let clientPhone: String?
    let familyOnApp: Bool?
    let allergies: [String]?
    let report: SvcReport?
    let reportMissing: [String]?
}

struct SvcWaitEntry: Codable, Hashable, Identifiable {
    let id: String
    let status: String
    let createdAt: String
    let notifiedAt: String?
    let providerClientId: String
    let providerClientPetId: String
    let petName: String
    let petPhotoUrl: String?
    let clientName: String
}

struct SvcSessionDetail: Codable, Identifiable {
    let id: String
    let status: String
    let serviceLabel: String
    let serviceCategory: String?
    let serviceId: String?
    let startsAt: String
    let endsAt: String
    let capacity: Int?
    let priceAmount: Int?
    let onlineBooking: Bool?
    let onlineBookingOpen: Bool?
    let size: Int
    let pets: [SvcSessionPet]
    let locationId: String?
    let assignedMember: SvcPersonRef?
    let roomId: String?
    let room: String?
    let notes: String?
    let cancelReason: String?
    let placesLeft: Int?
    let full: Bool?
    let waitlistCount: Int?
    let startMode: String?
    let meetingPoint: String?
    let reportsMissing: Int?
    let roster: [SvcRosterEntry]?
    let waitlist: [SvcWaitEntry]?

    var staying: [SvcSessionPet] { pets.filter { !$0.gone } }
    var isPickup: Bool { startMode == "pickup" }
    var active: Bool { status == "active" }
    var placesText: String { capacity.map { "\(size)/\($0)" } ?? "\(size)" }
    func entry(_ appointmentId: String) -> SvcRosterEntry? { roster?.first { $0.appointmentId == appointmentId } }

    var booked: Int { staying.filter { $0.status == "scheduled" }.count }
    var arrived: Int { staying.filter { $0.status == "checked_in" }.count }
    var withThem: Int { staying.filter { $0.status == "in_progress" }.count }
    var doneCount: Int { staying.filter { $0.status == "completed" }.count }
    var started: Bool { staying.contains { $0.status == "in_progress" || $0.status == "completed" } }

    /// The pets in the order they're seen: a pickup walk's stops first, those who left last.
    var rosterRows: [SvcSessionPet] {
        let indexed = Array(pets.enumerated())
        return indexed.sorted { a, b in
            let goneA = a.element.gone ? 1 : 0, goneB = b.element.gone ? 1 : 0
            if goneA != goneB { return goneA < goneB }
            if isPickup {
                let oa = entry(a.element.appointmentId)?.pickupOrder ?? Int.max
                let ob = entry(b.element.appointmentId)?.pickupOrder ?? Int.max
                if oa != ob { return oa < ob }
            }
            return a.offset < b.offset
        }.map(\.element)
    }
}

struct SvcSessionMoveResult: Decodable {
    let moved: [String]?
    let skipped: [SvcSkipped]?
}

struct SvcSkipped: Decodable { let appointmentId: String?; let error: String? }

struct SvcSessionCancelResult: Decodable { let notifiedFamilies: Int? }

struct SvcRoom: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String?
    let kind: String?
}

// MARK: - People and clients

struct SvcMember: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let userName: String?
    let email: String?
    let image: String?
    let displayName: String?
    let effectivePermissions: [String]?
    let locationIds: [String]?
    let isCurrentMember: Bool?
    let status: String?

    var shownName: String { displayName?.nonEmpty ?? name?.nonEmpty ?? userName?.nonEmpty ?? email?.nonEmpty ?? L("Someone") }
    func can(_ permission: Permission) -> Bool { (effectivePermissions ?? []).contains(permission.rawValue) }
}

struct SvcClientPetLite: Decodable, Identifiable, Hashable {
    let id: String
    let petName: String
    let petSpecies: String?
    let photoUrl: String?
    let status: String?
}

struct SvcClientLite: Decodable, Identifiable, Hashable {
    let id: String
    let ownerName: String
    let ownerPhone: String?
    let householdId: String?
    let pets: [SvcClientPetLite]?
}

// MARK: - A visit, as its report and its finish need it

struct SvcAppointment: Decodable, Identifiable {
    let id: String
    let status: String
    let serviceCategory: String?
    let serviceLabel: String?
    let petName: String?
    let clientName: String?
    let clientPhone: String?
    let clientHouseholdId: String?
    let startedAt: String?
    let report: SvcReport?
    let reportKind: String?
    let reportUpdatedAt: String?
}

struct SvcUploadResult: Decodable { let url: String }
struct SvcIgnored: Decodable {}

// MARK: - The report at the end of a visit (lib/service-reports.ts)

/// One struct for the three kinds (groom, walk, training): only the kind's
/// own fields are sent, and a walk's route (drawn by the server) never is.
struct SvcReport: Codable, Hashable {
    var kind: String
    // Groom
    var services: [String] = []
    var style: String?
    var styleKind: String?
    var length: String?
    var differenceNote: String?
    var coat: String?
    var skin: [String] = []
    var beforePhotoUrl: String?
    var afterPhotoUrl: String?
    // Walk
    var minutes: Int?
    var distanceKm: Double?
    var pee: Bool?
    var poop: String?
    var water: Bool?
    var ate: String?
    var medsGiven: Bool?
    var route: JSONValue?
    // Training
    var skills: [String] = []
    var progress: String?
    var homework: String?
    // All
    var behaviour: String?
    var photoUrl: String?
    var note: String?

    init(kind: String) { self.kind = kind }

    private enum K: String, CodingKey {
        case kind, services, style, styleKind, length, differenceNote, coat, skin, beforePhotoUrl, afterPhotoUrl
        case minutes, distanceKm, pee, poop, water, ate, medsGiven, route, skills, progress, homework, behaviour, photoUrl, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "groom"
        services = (try? c.decodeIfPresent([String].self, forKey: .services)) ?? []
        style = try? c.decodeIfPresent(String.self, forKey: .style)
        styleKind = try? c.decodeIfPresent(String.self, forKey: .styleKind)
        length = try? c.decodeIfPresent(String.self, forKey: .length)
        differenceNote = try? c.decodeIfPresent(String.self, forKey: .differenceNote)
        coat = try? c.decodeIfPresent(String.self, forKey: .coat)
        skin = (try? c.decodeIfPresent([String].self, forKey: .skin)) ?? []
        beforePhotoUrl = try? c.decodeIfPresent(String.self, forKey: .beforePhotoUrl)
        afterPhotoUrl = try? c.decodeIfPresent(String.self, forKey: .afterPhotoUrl)
        let rawMinutes: Double? = try? c.decodeIfPresent(Double.self, forKey: .minutes)
        minutes = rawMinutes.map { Int($0) }
        distanceKm = try? c.decodeIfPresent(Double.self, forKey: .distanceKm)
        pee = try? c.decodeIfPresent(Bool.self, forKey: .pee)
        poop = try? c.decodeIfPresent(String.self, forKey: .poop)
        water = try? c.decodeIfPresent(Bool.self, forKey: .water)
        ate = try? c.decodeIfPresent(String.self, forKey: .ate)
        medsGiven = try? c.decodeIfPresent(Bool.self, forKey: .medsGiven)
        route = try? c.decodeIfPresent(JSONValue.self, forKey: .route)
        skills = (try? c.decodeIfPresent([String].self, forKey: .skills)) ?? []
        progress = try? c.decodeIfPresent(String.self, forKey: .progress)
        homework = try? c.decodeIfPresent(String.self, forKey: .homework)
        behaviour = try? c.decodeIfPresent(String.self, forKey: .behaviour)
        photoUrl = try? c.decodeIfPresent(String.self, forKey: .photoUrl)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(kind, forKey: .kind)
        switch kind {
        case "groom":
            try c.encode(services, forKey: .services)
            try c.encodeIfPresent(style, forKey: .style)
            try c.encodeIfPresent(styleKind, forKey: .styleKind)
            try c.encodeIfPresent(length, forKey: .length)
            try c.encodeIfPresent(differenceNote, forKey: .differenceNote)
            try c.encodeIfPresent(coat, forKey: .coat)
            try c.encode(skin, forKey: .skin)
            try c.encodeIfPresent(beforePhotoUrl, forKey: .beforePhotoUrl)
            try c.encodeIfPresent(afterPhotoUrl, forKey: .afterPhotoUrl)
        case "walk":
            try c.encodeIfPresent(minutes, forKey: .minutes)
            try c.encodeIfPresent(distanceKm, forKey: .distanceKm)
            try c.encodeIfPresent(pee, forKey: .pee)
            try c.encodeIfPresent(poop, forKey: .poop)
            try c.encodeIfPresent(water, forKey: .water)
            try c.encodeIfPresent(ate, forKey: .ate)
            try c.encodeIfPresent(medsGiven, forKey: .medsGiven)
            try c.encodeIfPresent(photoUrl, forKey: .photoUrl)
        default:
            try c.encode(skills, forKey: .skills)
            try c.encodeIfPresent(progress, forKey: .progress)
            try c.encodeIfPresent(homework, forKey: .homework)
            try c.encodeIfPresent(photoUrl, forKey: .photoUrl)
        }
        try c.encodeIfPresent(behaviour, forKey: .behaviour)
        try c.encodeIfPresent(note, forKey: .note)
    }
}
