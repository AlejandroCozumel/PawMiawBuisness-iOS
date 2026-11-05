//
//  HomeModels.swift
//  PawMiawNegocios
//
//  What Home reads, as the web's hooks type it: the day's board
//  (`GET /provider-today`, hooks/use-provider-visits.ts), another day
//  (`GET /provider-day`), the grooming and home-visits day lists, the setup
//  checklist, an invited member's reminders, visits to relocate and families'
//  requests. Every field that may be absent is optional, so a missing one
//  never breaks the board.
//

import Foundation

// MARK: - The day (GET /provider-today)

struct HomeToday: Decodable {
    let date: String?
    let timeZone: String?
    let now: String?
    let currency: String?
    let viewer: HomeViewer?
    let counts: HomeCounts?
    /** finance.desk: what was collected today; null below. */
    let collectedToday: Int?
    /** finance.view: how many exceptions yesterday had; null below. */
    let exceptionsYesterday: Int?
    let registers: [HomeRegisterShift]?
    let lanes: [String: [HomeVisit]]?
    let sessions: [HomeSession]?
    let needsYou: HomeNeeds?
    let arrivals: [HomeArrival]?
    let hospital: HomeHospitalCounts?
    let hub: HomeHub?

    func lane(_ key: HomeLane) -> [HomeVisit] { lanes?[key.rawValue] ?? [] }
    var allVisits: [HomeVisit] { HomeLane.allCases.flatMap { lane($0) } }
}

enum HomeLane: String, CaseIterable {
    case upcoming, waiting, inService = "in_service", toPay = "to_pay", done, missed

    var order: Int {
        switch self {
        case .inService: 0
        case .waiting: 1
        case .toPay: 2
        case .upcoming: 3
        case .done: 4
        case .missed: 5
        }
    }
}

struct HomeViewer: Decodable {
    let memberId: String?
    let seesAllVisits: Bool?
}

struct HomeCounts: Decodable {
    let total: Int?
    let upcoming: Int?
    let late: Int?
    let waiting: Int?
    let inService: Int?
    let toPay: Int?
    let done: Int?
    let missed: Int?
}

struct HomeRegisterShift: Decodable, Identifiable {
    let sessionId: String
    let registerId: String?
    let registerName: String?
    let openedAt: String?
    let openedByName: String?
    let stale: Bool?
    var id: String { sessionId }
}

struct HomePetRef: Decodable, Hashable {
    let id: String?
    let name: String?
    let species: String?
    let breed: String?
    let photoUrl: String?
    let allergies: [String]?
}

struct HomeClientRef: Decodable, Hashable {
    let id: String?
    let name: String?
    let phone: String?
    let onPawMiaw: Bool?
}

struct HomePersonRef: Decodable, Hashable {
    let id: String?
    let name: String?
}

struct HomeVisitFee: Decodable {
    let kind: String?
    let decision: String?
}

struct HomeVisitInvoice: Decodable {
    let id: String
    let status: String?
    let totalAmount: Int?
    let amountPaid: Int?
    let balanceDueAmount: Int?
    let currency: String?
    let lineCount: Int?
    let unpricedLines: Int?
    let sentBy: HomePersonRef?
}

struct HomeNotesCount: Decodable {
    let drafts: Int?
    let signed: Int?
}

struct HomeVisitGroup: Decodable {
    let id: String
    let kind: String?
    let status: String?
    let pets: [HomeGroupPet]?
}

struct HomeGroupPet: Decodable {
    let appointmentId: String?
    let name: String?
    let photoUrl: String?
    let species: String?
    let status: String?
}

/// A visit's card on Home's board (`TodayVisit`).
struct HomeVisit: Decodable, Identifiable {
    let id: String
    let lane: String?
    let billing: String?
    let status: String?
    let startsAt: String?
    let endsAt: String?
    let lateMinutes: Int?
    let waitingMinutes: Int?
    let inServiceMinutes: Int?
    let pickupPassedMinutes: Int?
    let familyAttendance: String?
    let serviceLabel: String?
    let serviceCategory: String?
    let room: String?
    let notes: String?
    let arrivalNote: String?
    let hoursOverride: Bool?
    let confirmationStatus: String?
    let fee: HomeVisitFee?
    let pet: HomePetRef?
    let client: HomeClientRef?
    let assigned: HomePersonRef?
    let invoice: HomeVisitInvoice?
    let notesCount: HomeNotesCount?
    let group: HomeVisitGroup?
    let triagePriority: String?
    let triageReason: String?
    let afterHours: Bool?
    let groomStage: String?
    let bookedOnline: Bool?

    var laneValue: HomeLane { HomeLane(rawValue: lane ?? "") ?? .upcoming }
    var petName: String { pet?.name ?? "—" }
}

/// A group walk or class on Home (`AgendaSession`).
struct HomeSession: Decodable, Identifiable {
    let id: String
    let status: String?
    let startsAt: String?
    let serviceLabel: String?
    let size: Int?
    let capacity: Int?
    let room: String?
    let meetingPoint: String?
    let startMode: String?
    let assignedMember: HomePersonRef?
    let pets: [HomeGroupPet]?

    /// Everyone still booked (not cancelled, not a no-show).
    var staying: [HomeGroupPet] {
        (pets ?? []).filter { !["cancelled", "canceled", "no_show"].contains($0.status ?? "") }
    }
}

struct HomeHospitalCounts: Decodable {
    let admitted: Int?
    let pending: Int?
    let due: Int?
    let late: Int?
    let missed: Int?
}

struct HomeHub: Decodable {
    let modules: [String]?
    let entries: [HomeHubEntry]?
}

struct HomeHubPet: Decodable {
    let name: String?
    let species: String?
    let photoUrl: String?
}

/// A stay, home-stay visit or hospital patient on Home.
struct HomeHubEntry: Decodable, Identifiable {
    let id: String
    let entityId: String?
    let module: String?
    let kind: String?
    let status: String?
    let pets: [HomeHubPet]?
    let clientName: String?
    let startsAt: String?
    let endsAt: String?
    let room: String?
    let assignedId: String?
    let attention: Int?
    let late: Bool?
    let sourceAppointmentId: String?
}

/// A family on its way with an emergency ("voy en camino").
struct HomeArrival: Decodable, Identifiable {
    let id: String
    let status: String?
    let etaAt: String?
    let minutesAway: Int?
    let message: String?
    let contactPhone: String?
    let afterHours: Bool?
    let routedTo: String?
    let pet: HomeArrivalPet?
    let client: HomePersonRef?
    let linked: Bool?
    let emergencyCard: HomeArrivalCard?
    let acknowledgedByName: String?
    let replyMessage: String?

    var isOpen: Bool { status == "on_the_way" || status == "acknowledged" }
}

struct HomeArrivalPet: Decodable {
    let petId: String?
    let name: String?
    let species: String?
    let photoUrl: String?
    let providerClientPetId: String?
}

struct HomeArrivalCard: Decodable {
    let url: String?
}

// MARK: - Needs you

struct HomeNeeds: Decodable {
    let notesToSign: HomeNotesToSign?
    let unfinished: HomeUnfinished?
    let requests: HomeVisitRequests?
    let followUps: HomeFollowUps?
    let charging: HomeChargingSummary?
    let money: HomeMoneyOwed?
    let stays: HomeStayCounts?
    let stock: HomeStockCounts?
    let due: HomeDueCounts?
    let onlineRequests: HomeOnlineRequestList?
}

struct HomeNotesToSign: Decodable {
    let count: Int?
    let items: [HomeNoteToSign]?
}

struct HomeNoteToSign: Decodable, Identifiable {
    let recordId: String
    let title: String?
    let petName: String?
    let appointmentId: String?
    let author: String?
    let updatedAt: String?
    var id: String { recordId }
}

struct HomeUnfinished: Decodable {
    let count: Int?
    let items: [HomeUnfinishedVisit]?
}

struct HomeUnfinishedVisit: Decodable, Identifiable {
    let id: String
    let status: String?
    let startsAt: String?
    let petName: String?
    let clientName: String?
    let serviceLabel: String?
    let familyAttendance: String?
}

struct HomeVisitRequests: Decodable {
    let count: Int?
    let items: [HomeVisitRequest]?
}

struct HomeVisitRequest: Decodable, Identifiable {
    let id: String
    let kind: String?
    let startsAt: String?
    let petName: String?
    let clientName: String?
    let preferredTime: String?
}

struct HomeFollowUps: Decodable {
    let dueToday: Int?
    let overdue: Int?
    let documentation: Int?
    let later: Int?
    let items: [HomeFollowUp]?
}

struct HomeFollowUp: Decodable, Identifiable {
    let id: String
    let title: String?
    let type: String?
    let dueAt: String?
    let petName: String?
    let clientName: String?
    let overdue: Bool?
}

/// "Por cobrar" (hooks/use-charging-queue.ts): the front desk's queue, or what this person prices.
struct HomeChargingSummary: Decodable {
    let scope: String?
    let count: Int?
    let amount: Int?
    let earlierDays: HomeEarlierDays?
    let items: [HomeChargingItem]?
}

struct HomeEarlierDays: Decodable {
    let count: Int?
    let oldestDay: String?
}

struct HomeChargingItem: Decodable, Identifiable {
    let source: String?
    let sourceId: String?
    let appointmentId: String?
    let invoiceId: String?
    let state: String?
    let petName: String?
    let petNames: [String]?
    let clientName: String?
    let serviceLabel: String?
    let at: String?
    let day: String?
    let earlierDay: Bool?
    let vetName: String?
    let amount: Int?
    let currency: String?

    var id: String { invoiceId ?? sourceId ?? "\(petName ?? "")-\(at ?? "")" }
}

struct HomeMoneyOwed: Decodable {
    let owed: Int?
    let overdue: Int?
    let clients: Int?
    let promisesDue: Int?
    let promisesBroken: Int?
    let atDesk: HomeAtDesk?
}

struct HomeAtDesk: Decodable {
    let count: Int?
    let amount: Int?
}

struct HomeStayCounts: Decodable {
    let arriving: Int?
    let leaving: Int?
    let inHouse: Int?
    let lateArrivals: Int?
    let lateDepartures: Int?
}

struct HomeStockCounts: Decodable {
    let low: Int?
    let out: Int?
    let expiring: Int?
    let expired: Int?
}

struct HomeDueCounts: Decodable {
    let overdue: Int?
    let thisWeek: Int?
}

/// Families' online bookings waiting for an answer (`GET /provider-online-booking/requests`).
struct HomeOnlineRequestList: Decodable {
    let count: Int?
    let items: [HomeOnlineRequest]?
}

struct HomeOnlineRequest: Decodable, Identifiable {
    let appointmentId: String
    let startsAt: String?
    let endsAt: String?
    let serviceLabel: String?
    let notes: String?
    let releasesAt: String?
    let atHome: Bool?
    let client: HomeClientRef?
    let pets: [HomeOnlinePet]?
    var id: String { appointmentId }
}

struct HomeOnlinePet: Decodable {
    let appointmentId: String?
    let name: String?
    let species: String?
    let photoUrl: String?
}

// MARK: - Grooming and home visits (their day lists)

struct HomeGroomingToday: Decodable {
    let items: [HomeGroomItem]?
    let needsSomeone: Int?
}

struct HomeGroomItem: Decodable, Identifiable {
    let appointmentId: String
    let groomStage: String?
    let startsAt: String?
    let serviceLabel: String?
    let pet: HomePetRef?
    let client: HomeClientRef?
    let groomer: HomePersonRef?
    let requestSummary: String?
    let readyNotifiedAt: String?
    let attention: String?
    var id: String { appointmentId }
}

struct HomeVisitsDay: Decodable {
    let counts: HomeVisitsDayCounts?
    let items: [HomeHomeVisit]?
}

struct HomeVisitsDayCounts: Decodable {
    let total: Int?
    let late: Int?
}

struct HomeHomeVisit: Decodable, Identifiable {
    let id: String
    let late: Bool?
    let lateMinutes: Int?
    let pets: [HomeHubPet]?
}

// MARK: - Another day (GET /provider-day)

struct HomeOtherDay: Decodable {
    let date: String?
    let today: String?
    let mode: String?
    let currency: String?
    let counts: HomeOtherDayCounts?
    let collected: Int?
    let visits: [HomeDayVisit]?
    let stays: HomeDayStays?
}

struct HomeOtherDayCounts: Decodable {
    let total: Int?
    let missed: Int?
    let unconfirmed: Int?
    let consentsMissing: Int?
    let needsPrice: Int?
    let firstVisits: Int?
    let doubleBooked: Int?
    let done: Int?
    let unpaid: Int?
    let unpaidAmount: Int?
    let uncharged: Int?
    let notesToSign: Int?
    let reportsMissing: Int?
}

struct HomeDayVisit: Decodable, Identifiable {
    let id: String
    let status: String?
    let startsAt: String?
    let serviceLabel: String?
    let room: String?
    let pet: HomePetRef?
    let client: HomeClientRef?
    let assigned: HomePersonRef?
    let confirmationStatus: String?
    let doubleBooked: Bool?
    let bookedOnline: Bool?
    let prep: HomeDayPrep?
    let recap: HomeDayRecap?
}

struct HomeDayPrep: Decodable {
    let confirmation: String?
    let consentsMissing: [String]?
    let needsPrice: Bool?
    let groomRequest: Bool?
    let firstVisit: Bool?
}

struct HomeDayRecap: Decodable {
    let balanceDue: Int?
    let billStatus: String?
    let currency: String?
    let notesToSign: Int?
    let reportMissing: [String]?
}

struct HomeDayStays: Decodable {
    let arriving: [HomeDayStay]?
    let leaving: [HomeDayStay]?
}

struct HomeDayStay: Decodable, Identifiable {
    let id: String
    let kind: String?
    let status: String?
    let clientName: String?
    let pets: [String]?
    let unitName: String?
    let checkInDay: String?
    let checkInTime: String?
    let checkOutDay: String?
    let checkOutTime: String?
    let late: Bool?
}

// MARK: - Setup, reminders, relocations, requests

/// `GET /provider-setup/checklist`.
struct HomeChecklist: Decodable {
    let percent: Int?
    let complete: Bool?
    let items: [HomeChecklistItem]?
}

struct HomeChecklistItem: Decodable, Identifiable {
    let id: String
    let done: Bool?
    let dismissed: Bool?
    let why: String?
    let count: Int?
    let members: [HomeChecklistMember]?
    let mine: Bool?
}

struct HomeChecklistMember: Decodable, Identifiable {
    let memberId: String
    let name: String?
    let role: String?
    let gaps: [String]?
    var id: String { memberId }
}

/// `GET /provider-member-onboarding` (only the parts Home reads).
struct HomeMemberOnboarding: Decodable {
    let applicable: Bool?
    let show: Bool?
    let reminders: [HomeMemberReminder]?
}

struct HomeMemberReminder: Decodable, Identifiable {
    let id: String
    let credentialType: String?
}

/// `GET /provider-locations/relocate`.
struct HomeRelocations: Decodable {
    let visits: [HomeRelocationVisit]?
}

struct HomeRelocationVisit: Decodable, Identifiable {
    let id: String
    let locationName: String?
}

/// `GET /provider-requests?scope=open`: families asking for stays, home stays and programs.
struct HomeFamilyRequestList: Decodable {
    let items: [HomeFamilyRequest]?
}

struct HomeFamilyRequest: Decodable, Identifiable {
    let id: String
    let kind: String?
    let status: String?
    let displayStatus: String?
    let startDay: String?
    let endDay: String?
    let proposedStartDay: String?
    let proposedEndDay: String?
    let notes: String?
    let program: String?
    let depositPercent: Int?
    let familyAcceptedAt: String?
    let clientName: String?
    let clientPhone: String?
    let providerClientId: String?
    let stayIds: [String]?
    let appointmentIds: [String]?
    let pets: [HomeFamilyRequestPet]?
}

struct HomeFamilyRequestPet: Decodable {
    let name: String?
    let species: String?
    let photoUrl: String?
    let providerClientPetId: String?
}
