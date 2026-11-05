//
//  SchedModels.swift
//  PawMiawNegocios
//
//  The Schedule module's shapes, mirroring the web's hooks
//  (use-provider-appointments.ts, use-provider-visits.ts,
//  use-provider-online-booking.ts, use-provider-rooms.ts, lib/hours.ts,
//  use-provider-sessions.ts, use-provider-invoices.ts). Every field that can
//  be absent or null is Optional, so an older or newer server never breaks a
//  screen.
//

import Foundation

// MARK: - Visits

struct SchedAssigned: Codable, Hashable {
    let id: String?
    let name: String?
}

struct SchedActor: Codable, Hashable {
    let name: String?
}

struct SchedGroupPet: Codable, Hashable {
    let appointmentId: String
    let providerClientPetId: String?
    let providerClientId: String?
    let name: String?
    let species: String?
    let photoUrl: String?
    let status: String?
    let clientName: String?
}

/// Pets booked together: a family's (`household`) or a session's places. Sessions
/// (`GET /provider-sessions`) read the same shape with their own extra fields.
struct SchedVisitGroup: Codable, Hashable, Identifiable {
    let id: String
    let kind: String?
    let status: String?
    let serviceLabel: String?
    let serviceCategory: String?
    let serviceId: String?
    let startsAt: String?
    let endsAt: String?
    let capacity: Int?
    let priceAmount: Int?
    let onlineBooking: Bool?
    let onlineBookingOpen: Bool?
    let size: Int?
    let pets: [SchedGroupPet]?
    // A session's own fields (AgendaSession).
    let locationId: String?
    let assignedMember: SchedAssigned?
    let roomId: String?
    let room: String?
    let notes: String?
    let doubleBooked: Bool?
    let placesLeft: Int?
    let full: Bool?
    let waitlistCount: Int?

    var isSession: Bool { kind == "session" }

    /// Everyone still booked (not cancelled, not a no-show), first booked first.
    var stayingPets: [SchedGroupPet] {
        (pets ?? []).filter { !SchedStatus.gone.contains($0.status ?? "") }
    }

    /// "3/6" places, or "3".
    var placesLabel: String {
        let taken = size ?? stayingPets.count
        if let capacity { return "\(taken)/\(capacity)" }
        return "\(taken)"
    }
}

struct SchedOnlineRequestClock: Codable, Hashable {
    let releasesAt: String?
}

struct SchedSeriesResult: Codable, Hashable {
    let id: String?
    let created: Int?
    let skipped: [SchedSeriesSkip]?
}

struct SchedSeriesSkip: Codable, Hashable {
    let startsAt: String?
    let reason: String?
}

/// A business visit (`ProviderAppointment`).
struct SchedAppointment: Codable, Identifiable, Hashable {
    let id: String
    let clinicId: String?
    let providerClientId: String
    let providerClientPetId: String
    let serviceCategory: String?
    let serviceId: String?
    let serviceLabel: String
    let startsAt: String
    let endsAt: String?
    let room: String?
    let notes: String?
    let status: String
    let confirmationStatus: String?
    let confirmationNote: String?
    let confirmationPreferredTime: String?
    let clientName: String
    let clientEmail: String?
    let clientPhone: String?
    let clientHouseholdId: String?
    let clientPhotoUrl: String?
    let petName: String
    let petSpecies: String?
    let petBreed: String?
    let petSex: String?
    let petBirthDate: String?
    /// Grams.
    let petWeight: Double?
    let petPhotoUrl: String?
    let assignedMember: SchedAssigned?
    let createdBy: SchedActor?
    let createdAt: String?
    let updatedAt: String?
    let arrivedAt: String?
    let startedAt: String?
    let finishedAt: String?
    let arrivalNote: String?
    let hoursOverride: Bool?
    let roomId: String?
    let doubleBooked: Bool?
    let locationId: String?
    let noCharge: Bool?
    let noChargeReason: String?
    let cancelReason: String?
    let feeKind: String?
    let feeDecision: String?
    let feeInvoiceId: String?
    let feeNote: String?
    let reportKind: String?
    let groomStage: String?
    let groomReadyNotifiedAt: String?
    let groomReadyChannel: String?
    let familyAttendance: String?
    let seriesId: String?
    let atHome: Bool?
    let accessNotes: String?
    let groupId: String?
    let group: SchedVisitGroup?
    let together: [String]?
    let series: SchedSeriesResult?
    /// A family booked it from the app ("En línea").
    let bookedOnline: Bool?
    /// While it is a request ("Por confirmar"): when its time is released.
    let onlineRequest: SchedOnlineRequestClock?
    let onlineOutcome: String?
    let declineReason: String?
    let movedFromStartsAt: String?
    /// The groom, walk or training report (`reportKind` says which).
    let report: SvcReport?
    let reportUpdatedAt: String?
    /// The client's address a home visit happens at.
    let serviceAddressId: String?

    var start: Date? { DateText.parse(startsAt) }
    var groomReadyNotifiedAtValue: String? { groomStage == "ready" ? groomReadyNotifiedAt : nil }
    var end: Date? { DateText.parse(endsAt) }
    var isRequested: Bool { status == "requested" }
    var isGone: Bool { SchedStatus.gone.contains(status) }
    /// The family asked to move or cancel it.
    var familyAsking: Bool {
        status == "scheduled" && (confirmationStatus == "reschedule_requested" || confirmationStatus == "cancellation_requested")
    }
    /// A clinical visit (a vet's or an emergency), as the web reads it.
    var isClinical: Bool { serviceCategory == nil || serviceCategory == "vet" || serviceCategory == "emergency" }
    /// The family's other pets booked with it (household) still in the same state.
    var togetherPets: [SchedGroupPet] {
        guard let group, group.kind == "household" else { return [] }
        return (group.pets ?? []).filter { $0.appointmentId != id && $0.status == status }
    }
    var lengthMinutes: Int {
        guard let start, let end, end > start else { return 30 }
        return max(15, Int(end.timeIntervalSince(start) / 60))
    }
}

/// What a visit's move answers (check in, start, finish, no-show, cancel, "Sí vino").
struct SchedMoveResponse: Decodable {
    let appointment: SchedAppointment?
    let feeInvoiceId: String?
    let together: [String]?
    let bill: SchedMoveBill?
}

struct SchedMoveBill: Decodable {
    let status: String?
    let unpricedLines: Int?
}

struct SchedStopSeriesResult: Decodable { let cancelled: Int?; let kept: Int? }
struct SchedConfirmationResult: Decodable { let emailStatus: String?; let errorMessage: String? }

// MARK: - Statuses

enum SchedStatus {
    static let all = ["requested", "scheduled", "checked_in", "in_progress", "completed", "cancelled", "no_show"]
    static let gone = ["cancelled", "canceled", "no_show"]
    /// What holds its time (the server's `HOLDING_STATUSES`).
    static let holding = ["requested", "scheduled", "checked_in", "in_progress"]

    /// The list's word for a status (web agenda-list `STATUS_LABELS`).
    static func label(_ status: String?) -> String {
        switch status {
        case "requested": L("To confirm")
        case "scheduled": L("Booked")
        case "checked_in": L("Waiting")
        case "in_progress": L("In the visit")
        case "completed": L("Finished")
        case "cancelled", "canceled": L("Cancelled")
        case "no_show": L("Didn’t come")
        default: status ?? ""
        }
    }

    static func confirmationLabel(_ status: String?) -> String? {
        switch status {
        case "pending": L("Waiting for their answer")
        case "confirmed": L("Confirmed")
        case "reschedule_requested": L("Asked to move it")
        case "cancellation_requested": L("Asked to cancel")
        case "delivery_failed": L("The confirmation did not reach them")
        case "declined": L("The family declined this visit")
        case "expired": L("The confirmation expired")
        default: nil
        }
    }
}

// MARK: - People, rooms, hours

struct SchedMember: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let userName: String?
    let email: String?
    let image: String?
    let displayName: String?
    let professionalTitle: String?
    let maxConcurrentVisits: Int?
    let locationIds: [String]?
    let role: String?
    let effectivePermissions: [String]?
    let isCurrentMember: Bool?
    let status: String?

    var label: String { displayName?.nonEmpty ?? name?.nonEmpty ?? email?.nonEmpty ?? L("Someone") }
    var takesVisits: Bool { (effectivePermissions ?? []).contains(Permission.appointmentsComplete.rawValue) }
    var isMe: Bool { isCurrentMember == true }
    func worksAt(_ locationId: String?) -> Bool {
        guard let locationId, let ids = locationIds, !ids.isEmpty else { return true }
        return ids.contains(locationId)
    }
}

struct SchedRoomOut: Codable, Hashable {
    let fromDay: String?
    let untilDay: String?
    let reason: String?
}

struct SchedRoom: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let kind: String?
    let capacity: Int?
    let serviceIds: [String]?
    let sortOrder: Int?
    let status: String?
    let locationId: String?
    let outOfService: SchedRoomOut?

    /// Wards and cages hold hospitalized patients, never visits.
    var holdsVisits: Bool { kind != "ward" && kind != "cage" }

    func outOn(_ day: String) -> SchedRoomOut? {
        guard let out = outOfService, let from = out.fromDay, day >= from else { return nil }
        if let until = out.untilDay, day > until { return nil }
        return out
    }
}

struct SchedRange: Codable, Hashable {
    let start: String
    let end: String
}

struct SchedClosureMark: Codable, Hashable {
    let id: String?
    let label: String?
    let closed: Bool?
}

struct SchedLoadDay: Codable, Hashable {
    let date: String
    let ranges: [SchedRange]?
    let closure: SchedClosureMark?
}

struct SchedLoadHours: Codable, Hashable {
    let timeZone: String?
    let checksHours: Bool?
    let days: [SchedLoadDay]?
}

struct SchedTimeOff: Codable, Hashable {
    let id: String?
    let reason: String?
}

struct SchedLoadPersonDay: Codable, Hashable {
    let date: String
    let ranges: [SchedRange]?
    let timeOff: SchedTimeOff?
}

struct SchedLoadPerson: Codable, Hashable, Identifiable {
    let id: String
    let name: String?
    let capacity: Int?
    let ownHours: Bool?
    let days: [SchedLoadPersonDay]?

    func day(_ key: String) -> SchedLoadPersonDay? { days?.first { $0.date == key } }
}

struct SchedLoadVisit: Codable, Hashable {
    let id: String
    let startsAt: String
    let endsAt: String?
    let status: String
    let memberId: String?
    let roomId: String?
    let locationId: String?
    let petName: String?
    let sessionId: String?
}

/// Who and what is taken between two times (`GET /provider-schedule/load`).
struct SchedLoad: Codable, Hashable {
    let visits: [SchedLoadVisit]?
    let people: [SchedLoadPerson]?
    let rooms: [SchedRoom]?
    let bufferMinutes: Int?
    let hours: SchedLoadHours?

    func hoursDay(_ key: String) -> SchedLoadDay? { hours?.days?.first { $0.date == key } }
    var visitRooms: [SchedRoom] { (rooms ?? []).filter(\.holdsVisits) }
}

struct SchedWeekDay: Codable, Hashable {
    let day: String
    let enabled: Bool?
    let startTime: String?
    let endTime: String?
    let ranges: [SchedRange]?

    /// A day's ranges: `ranges` when sent, else its one span.
    var dayRanges: [SchedRange] {
        guard enabled == true else { return [] }
        if let ranges, !ranges.isEmpty { return ranges }
        if let startTime, let endTime { return [SchedRange(start: startTime, end: endTime)] }
        return []
    }
}

/// A place's booking settings and week (the workspace's or a location's `availability`).
struct SchedAvailability: Codable, Hashable {
    let timezone: String?
    let defaultAppointmentDurationMinutes: Int?
    let allowAfterHoursBooking: Bool?
    let requestAppointmentConfirmationByDefault: Bool?
    let defaultBufferMinutes: Int?
    let weeklySchedule: [SchedWeekDay]?

    func week(_ weekday: String) -> [SchedRange] {
        weeklySchedule?.first { $0.day == weekday }?.dayRanges ?? []
    }
}

struct SchedWorkspaceAvailability: Decodable { let availability: SchedAvailability? }
struct SchedLocationAvailability: Decodable { let id: String; let timezone: String?; let availability: SchedAvailability? }
struct SchedLocationsAvailability: Decodable { let locations: [SchedLocationAvailability]? }

struct SchedClosure: Codable, Hashable {
    let id: String?
    let startDay: String
    let endDay: String
    let label: String?
    let ranges: [SchedRange]?
    let repeatsYearly: Bool?

    func covers(_ day: String) -> Bool {
        if repeatsYearly != true { return startDay <= day && day <= endDay }
        guard day >= startDay else { return false }
        let from = String(startDay.dropFirst(5)), to = String(endDay.dropFirst(5)), md = String(day.dropFirst(5))
        return from <= to ? (from <= md && md <= to) : (md >= from || md <= to)
    }
}

struct SchedClosures: Decodable { let closures: [SchedClosure]? }

// MARK: - Sessions (group walks and classes)

typealias SchedSession = SchedVisitGroup

// MARK: - Online booking

struct SchedRequestPet: Codable, Hashable {
    let appointmentId: String
    let providerClientPetId: String?
    let name: String
    let species: String?
    let photoUrl: String?
}

struct SchedRequestClient: Codable, Hashable {
    let id: String?
    let name: String
    let phone: String?
}

/// One booking a family made online, waiting for an answer.
struct SchedOnlineRequest: Codable, Hashable, Identifiable {
    let appointmentId: String
    let groupId: String?
    let startsAt: String
    let endsAt: String?
    let serviceLabel: String
    let serviceId: String?
    let serviceCategory: String?
    let locationId: String?
    let assigned: SchedAssigned?
    let room: String?
    let atHome: Bool?
    let notes: String?
    let requestedAt: String?
    let releasesAt: String?
    let client: SchedRequestClient
    let pets: [SchedRequestPet]

    var id: String { appointmentId }
}

struct SchedOnlineRequestList: Codable, Hashable {
    let count: Int?
    let items: [SchedOnlineRequest]?
}

struct SchedOnlineAnswer: Decodable {
    let appointmentId: String?
    let status: String?
    let startsAt: String?
}

// MARK: - Clients (the booking sheet's picker)

struct SchedClientPet: Codable, Identifiable, Hashable {
    let id: String
    let petName: String
    let petSpecies: String?
    let petBreed: String?
    let photoUrl: String?
    let status: String?
    let microchipNumber: String?
    let weight: Double?
}

struct SchedClient: Codable, Identifiable, Hashable {
    let id: String
    let householdId: String?
    let ownerName: String
    let ownerEmail: String?
    let ownerPhone: String?
    let photoUrl: String?
    let status: String?
    let pets: [SchedClientPet]?

    var bookablePets: [SchedClientPet] { (pets ?? []).filter { $0.status != "archived" } }
}

// MARK: - The service catalog

struct SchedCatalogCategory: Codable, Hashable, Identifiable {
    let id: String
    let label: String
    let description: String?
    let reasonLabel: String?
    let reasonPlaceholder: String?
}

struct SchedCatalogService: Codable, Hashable, Identifiable {
    let id: String
    let category: String
    let label: String
    let description: String?
    let formTemplate: String?
    let atHome: Bool?
    let defaultDurationMinutes: JSONValue?

    var minutes: Int? { defaultDurationMinutes?.double.map { Int($0) }.flatMap { $0 > 0 ? $0 : nil } }
    var isHome: Bool { atHome == true || formTemplate == "home" }
}

struct SchedCatalog: Codable, Hashable {
    let categories: [SchedCatalogCategory]?
    let services: [SchedCatalogService]?
}

// MARK: - Records and the bill

struct SchedRecord: Codable, Identifiable, Hashable {
    let id: String
    let appointmentId: String?
    let recordType: String?
    let title: String?
    let summary: String?
    let details: String?
    let internalNote: String?
    let status: String?
    let eventAt: String?
    let createdAt: String?
    let updatedAt: String?
    let signedAt: String?
    let signedBy: SchedActor?
    let revision: Int?

    /// Every record counts; the visit's own note only once it has words.
    var hasWords: Bool {
        guard recordType == "vet_visit" || recordType == "note" else { return true }
        return [details, summary, internalNote].contains { $0?.nonEmpty != nil }
    }
    var isDraft: Bool { status == "draft" }
    var isSigned: Bool { status == "active" }
}

struct SchedInvoiceLine: Codable, Identifiable, Hashable {
    let id: String
    let label: String?
    let quantity: Double?
    let unitAmount: Int?
    let lineTotalAmount: Int?
    let courtesy: Bool?
    let itemType: String?

    /// A line nobody priced: $0 and not given on purpose.
    var needsPrice: Bool { (unitAmount ?? 0) <= 0 && courtesy != true }
}

struct SchedInvoiceSummary: Codable, Identifiable, Hashable {
    let id: String
    let createdAt: String?
}

struct SchedInvoice: Codable, Identifiable, Hashable {
    let id: String
    let invoiceNumber: String?
    let status: String
    let currency: String?
    let subtotalAmount: Int?
    let discountAmount: Int?
    let taxAmount: Int?
    let totalAmount: Int?
    let amountPaid: Int?
    let balanceDueAmount: Int?
    let createdAt: String?
    let updatedAt: String?
    let lineItems: [SchedInvoiceLine]?
}

/// Where a visit's bill stands (web lib/visit-bill.ts `billStage`).
enum SchedBillStage: String {
    case notStarted, noCharge, canceled, noBill, needsPrice, building, ready, partPaid, paid, covered

    static func of(visitStatus: String, noCharge: Bool, invoice: SchedInvoice?) -> SchedBillStage {
        guard let invoice else {
            if noCharge { return .noCharge }
            if visitStatus == "scheduled" || visitStatus == "checked_in" || visitStatus == "requested" { return .notStarted }
            if SchedStatus.gone.contains(visitStatus) { return .canceled }
            return .noBill
        }
        let total = invoice.totalAmount ?? 0, paid = invoice.amountPaid ?? 0, balance = invoice.balanceDueAmount ?? 0
        if invoice.status == "canceled" {
            if noCharge { return .noCharge }
            return paid <= 0 && (visitStatus == "in_progress" || visitStatus == "completed") ? .noBill : .canceled
        }
        if invoice.status == "paid" || (invoice.status != "draft" && balance <= 0) {
            return total == 0 ? .covered : .paid
        }
        if invoice.status == "draft" {
            return total > 0 && !(invoice.lineItems ?? []).contains(where: \.needsPrice) ? .building : .needsPrice
        }
        if paid > 0 { return .partPaid }
        return .ready
    }

    var label: String {
        switch self {
        case .notStarted: L("Not started")
        case .noCharge: L("No charge")
        case .canceled: L("Canceled")
        case .noBill: L("No bill yet")
        case .needsPrice: L("Needs a price")
        case .building: L("Being built")
        case .ready: L("Ready to charge")
        case .partPaid: L("Part paid")
        case .paid: L("Paid")
        case .covered: L("Nothing to charge")
        }
    }

    var state: ProviderState {
        switch self {
        case .notStarted, .noCharge, .canceled, .noBill: .closed
        case .needsPrice, .ready, .partPaid: .waiting
        case .building: .active
        case .paid, .covered: .done
        }
    }
}

// MARK: - Conflicts and hours problems (from a refused save)

struct SchedConflictVisit: Codable, Hashable {
    let id: String?
    let petName: String?
    let startsAt: String?
    let endsAt: String?
}

struct SchedOutOfServiceNote: Codable, Hashable {
    let untilDay: String?
    let reason: String?
}

/// A double booking (the server's 409 `visit_conflict`, or the same rule worked out here).
struct SchedConflict: Codable, Hashable {
    let kind: String
    var memberId: String? = nil
    var roomId: String? = nil
    var name: String? = nil
    var capacity: Int? = nil
    var visits: [SchedConflictVisit]? = nil
    var outOfService: SchedOutOfServiceNote? = nil
    var travelMinutes: Int? = nil
}

/// What the hours say about a visit (the server's 400 `outside_hours`).
struct SchedHoursProblem: Hashable {
    let reason: String
    let message: String
    let closureLabel: String?
    let timeOffReason: String?
    let memberId: String?
}

/// The fee the server wants a decision on (409 `fee_decision_required`).
struct SchedFeeRequired: Hashable {
    let kind: String
    let amount: Int
    let currency: String?
}
