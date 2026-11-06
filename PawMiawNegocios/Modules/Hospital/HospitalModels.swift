//
//  HospitalModels.swift
//  PawMiawNegocios
//
//  The hospital's shapes (web hooks/use-provider-hospital.ts): the ward
//  board, one hospitalization with its treatment sheet, orders, vitals,
//  updates, rounds, the running bill and the end; on call and the settings.
//  Every field the server could leave out is optional.
//

import Foundation

// MARK: - Pieces

struct HospVitals: Codable, Identifiable, Hashable {
    let id: String
    let recordedAt: String?
    let notes: String?
    /// "triage" (the quick vitals at arrival) or "hospital".
    let source: String?
    let recordedByName: String?
    let voided: Bool?
    let temperatureC: Double?
    let heartRate: Double?
    let respiratoryRate: Double?
    let painScore: Double?
    let weightGrams: Double?
    let mucousMembranes: String?
    let crtSeconds: Double?
}

struct HospRoomRef: Codable, Hashable {
    let id: String
    let name: String?
    let kind: String?
}

struct HospPatient: Codable, Hashable {
    let providerClientPetId: String?
    let name: String?
    let species: String?
    let breed: String?
    let photoUrl: String?
    let weightGrams: Double?
    let allergies: [String]?
    let petId: String?
    let deceasedAt: String?
}

struct HospClientRef: Codable, Hashable {
    let id: String
    let name: String?
    let phone: String?
    let onPawMiaw: Bool?
}

struct HospPersonRef: Codable, Hashable {
    let id: String
    let name: String?
    let image: String?
}

struct HospAttention: Codable, Hashable {
    let due: Int?
    let late: Int?
    let missed: Int?
    var d: Int { due ?? 0 }
    var l: Int { late ?? 0 }
    var m: Int { missed ?? 0 }
}

struct HospOpenDose: Codable, Hashable {
    let orderId: String?
    let label: String?
    let scheduledFor: String?
    let state: String?
}

struct HospGateConsent: Codable, Hashable {
    let required: Bool?
    let consentId: String?
    let status: String?
    let title: String?
    let amountCents: Int?
    let satisfied: Bool?
    /// missing | unsigned | amount_changed
    let reason: String?
}

struct HospGateDeposit: Codable, Hashable {
    let amount: Int?
    let paid: Int?
    let satisfied: Bool?
    let waivedByTriage: Bool?
}

/// What admission waits on: the signed estimate and the deposit.
struct HospGate: Codable, Hashable {
    let consent: HospGateConsent?
    let deposit: HospGateDeposit?
    let ready: Bool?
}

/// A board row or a patient's hospitalization (a waiting one carries its gate).
struct HospSummary: Codable, Identifiable, Hashable {
    let id: String
    let status: String?
    let emergency: Bool?
    let triagePriority: String?
    let reason: String?
    let internalNote: String?
    let locationId: String?
    let room: HospRoomRef?
    let cageLabel: String?
    let patient: HospPatient?
    let client: HospClientRef?
    let attending: HospPersonRef?
    let appointmentId: String?
    let requestedAt: String?
    let admittedAt: String?
    let endedAt: String?
    let dayNumber: Int?
    let condition: String?
    let attention: HospAttention?
    let nextDueAt: String?
    let lastVitals: HospVitals?
    let roundsSignedToday: Bool?
    let estimateAmount: Int?
    let depositAmount: Int?
    let currency: String?
    let billTotal: Int?
    let gate: HospGate?
}

struct HospWardRoom: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let kind: String?
    let capacity: Int?
    let locationId: String?
    let occupied: Int?
}

struct HospBoardCounts: Codable, Hashable {
    let pending: Int?
    let admitted: Int?
    let due: Int?
    let late: Int?
    let missed: Int?
    let roundsPending: Int?
}

struct HospBoard: Codable {
    let now: String?
    let patients: [HospSummary]?
    let recent: [HospSummary]?
    let rooms: [HospWardRoom]?
    let counts: HospBoardCounts?
}

// MARK: - The sheet

struct HospAdministration: Codable, Identifiable, Hashable {
    let id: String
    let orderId: String?
    let scheduledFor: String?
    let dayKey: String?
    /// given | not_given
    let status: String?
    let givenAt: String?
    let doseAmount: Double?
    let doseUnit: String?
    let notGivenReason: String?
    let initials: String?
    let notes: String?
    let givenByName: String?
    let chargedAmount: Int?
    let voidedAt: String?
    let voidReason: String?
}

struct HospSheetSlot: Codable, Hashable, Identifiable {
    let scheduledFor: String
    /// upcoming | due | late | missed | given | given_late | not_given
    let state: String?
    let administration: HospAdministration?
    var id: String { scheduledFor }
}

struct HospSheetRow: Codable, Hashable, Identifiable {
    let orderId: String
    let slots: [HospSheetSlot]?
    let extra: [HospAdministration]?
    let voided: [HospAdministration]?
    var id: String { orderId }
}

struct HospSheet: Codable, Hashable {
    let day: String?
    let days: [String]?
    let today: String?
    let rows: [HospSheetRow]?
}

struct HospCatalogRef: Codable, Hashable {
    let id: String
    let name: String?
    let itemType: String?
    let unitAmount: Int?
}

struct HospOrder: Codable, Identifiable, Hashable {
    let id: String
    /// medication | fluid | feeding | monitoring | procedure | other
    let kind: String?
    let label: String?
    let catalogItem: HospCatalogRef?
    let doseAmount: Double?
    let doseUnit: String?
    let route: String?
    let rateMlPerHour: Double?
    /// times | every | once | prn
    let scheduleKind: String?
    let scheduleTimes: [String]?
    let everyHours: Int?
    let onceAt: String?
    let startsAt: String?
    let endsAt: String?
    let chargeable: Bool?
    let chargeQuantity: Int?
    let instructions: String?
    /// active | stopped
    let status: String?
    let stoppedAt: String?
    let stopReason: String?
    let revision: Int?
    let createdByName: String?
    let updatedByName: String?
    let createdAt: String?
    let updatedAt: String?

    /// Its label, else its catalog item.
    var name: String { label?.nonEmpty ?? catalogItem?.name ?? "" }
    var isStopped: Bool { status == "stopped" }
}

struct HospUpdate: Codable, Identifiable, Hashable {
    let id: String
    let message: String?
    let condition: String?
    let photoUrl: String?
    /// owner | internal
    let visibility: String?
    let authorName: String?
    let createdAt: String?
}

struct HospRound: Codable, Identifiable, Hashable {
    let id: String
    let day: String?
    let note: String?
    let signedByName: String?
    let signedAt: String?
}

struct HospTakeHome: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let catalogItemId: String?
    let doseAmount: Double?
    let doseUnit: String?
    let route: String?
    let everyHours: Int?
    let durationDays: Int?
    let quantity: Int?
    let instructions: String?
    let directions: String?
}

struct HospBillLine: Codable, Identifiable, Hashable {
    let id: String
    let label: String?
    let description: String?
    let quantity: Double?
    let unitAmount: Int?
    let total: Int?
    let sourceType: String?
    let courtesy: Bool?

    /// The zero-price rule: one unpriced line keeps the bill a draft.
    var needsPrice: Bool { (unitAmount ?? 0) <= 0 && courtesy != true }
}

struct HospEarlierBill: Codable, Identifiable, Hashable {
    let id: String
    let status: String?
    let totalAmount: Int?
}

struct HospDailyFee: Codable, Hashable {
    let itemId: String?
    let name: String?
    let unitAmount: Int?
}

struct HospBill: Codable, Hashable {
    let invoiceId: String?
    let status: String?
    let lines: [HospBillLine]?
    let totalAmount: Int?
    let taxAmount: Int?
    let pricesIncludeTax: Bool?
    let earlierBills: [HospEarlierBill]?
    let depositsPaid: Int?
    let currency: String?
    let dailyFee: HospDailyFee?
}

struct HospEnd: Codable, Hashable {
    /// discharged | transferred | deceased
    let kind: String?
    let at: String?
    let byName: String?
    let diagnosis: String?
    let summary: String?
    let instructions: String?
    let followUpAt: String?
    let followUpId: String?
    let transferDestination: String?
    let transferReason: String?
    let deathCause: String?
    let deathConsentId: String?
    let deathOverrideReason: String?
    let aftercare: String?
    let aftercareNote: String?
    let undoableUntil: String?
}

struct HospDeathUndone: Codable, Hashable {
    let at: String?
    let reason: String?
}

struct HospSettingsInline: Codable, Hashable {
    let lateGraceMinutes: Int?
    let missedAfterMinutes: Int?
}

struct HospPrescriptionResult: Codable, Hashable {
    struct Entry: Codable, Hashable { let id: String?; let folio: String? }
    let ok: Bool?
    let code: String?
    let error: String?
    let prescriptions: [Entry]?
}

struct HospDischargeResult: Codable, Hashable {
    let id: String?
    let records: Int?
    let cabinetItems: Int?
    let followUpId: String?
    let prescription: HospPrescriptionResult?
}

struct HospAdmitError: Codable, Hashable {
    let error: String?
    let code: String?
}

struct HospConsentRequest: Codable, Hashable {
    let consentId: String?
    let notified: Bool?
}

/// One hospitalization: the summary's facts and the whole record.
struct HospDetail: Codable, Identifiable, Hashable {
    let id: String
    let status: String?
    let emergency: Bool?
    let triagePriority: String?
    let reason: String?
    let internalNote: String?
    let locationId: String?
    let room: HospRoomRef?
    let cageLabel: String?
    let patient: HospPatient?
    let client: HospClientRef?
    let attending: HospPersonRef?
    let appointmentId: String?
    let requestedAt: String?
    let admittedAt: String?
    let endedAt: String?
    let dayNumber: Int?
    let condition: String?
    let attention: HospAttention?
    let openDoses: [HospOpenDose]?
    let nextDueAt: String?
    let lastVitals: HospVitals?
    let roundsSignedToday: Bool?
    let estimateAmount: Int?
    let depositAmount: Int?
    let currency: String?
    let billTotal: Int?

    let gate: HospGate?
    let consentOverrideReason: String?
    let depositOverrideReason: String?
    let gateOverriddenByName: String?
    let admittedByName: String?
    let cancelReason: String?
    let settings: HospSettingsInline?
    let timeZone: String?
    let orders: [HospOrder]?
    let sheet: HospSheet?
    let vitals: [HospVitals]?
    let updates: [HospUpdate]?
    let rounds: [HospRound]?
    let takeHome: [HospTakeHome]?
    let end: HospEnd?
    let deathUndone: HospDeathUndone?
    let estimateConsentId: String?
    let deathConsentId: String?
    let bill: HospBill?
    // Only on the create answer.
    let consentRequest: HospConsentRequest?
    let consentError: String?
    let admitError: HospAdmitError?
    // Only on the discharge answer.
    let discharge: HospDischargeResult?

    var zone: TimeZone { timeZone.flatMap(TimeZone.init(identifier:)) ?? Workspace.shared.timeZone }
    var petName: String { patient?.name?.nonEmpty ?? L("Patient") }
    var isAdmitted: Bool { status == "admitted" }
    var isPending: Bool { status == "pending" }
    var allOrders: [HospOrder] { orders ?? [] }
    var money: String { currency ?? Workspace.shared.currency }
}

struct HospOrderEvent: Codable, Identifiable, Hashable {
    let id: String
    /// created | changed | stopped
    let action: String?
    let changes: JSONValue?
    let reason: String?
    let actorName: String?
    let createdAt: String?
}

struct HospOrderEvents: Codable { let events: [HospOrderEvent]? }

struct HospSettings: Codable, Hashable {
    let lateGraceMinutes: Int?
    let missedAfterMinutes: Int?
    let feeGraceMinutes: Int?
    let visitingInfo: String?
    let dailyFeeItemId: String?
    let emergencyDepositAmount: Int?
    let afterHoursSurchargeItemId: String?
    let currency: String?
}

struct HospOnCallShift: Codable, Identifiable, Hashable {
    let id: String
    let locationId: String?
    let locationName: String?
    let member: HospPersonRef?
    let startsAt: String?
    let endsAt: String?
    let note: String?
}

struct HospOnCallList: Codable {
    let shifts: [HospOnCallShift]?
    let now: [HospOnCallShift]?
}

// MARK: - Shared lookups (members, rooms, catalog, clients, consents)

struct HospMember: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let userName: String?
    let email: String?
    let image: String?
    let displayName: String?
    let role: String?
    let effectivePermissions: [String]?
    let isCurrentMember: Bool?
    let locationIds: [String]?

    var label: String { displayName?.nonEmpty ?? name?.nonEmpty ?? userName?.nonEmpty ?? email ?? "" }
    func can(_ permission: Permission) -> Bool { (effectivePermissions ?? []).contains(permission.rawValue) }
}

struct HospRoom: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let kind: String?
    let capacity: Int?
    let status: String?
    let locationId: String?

    var isHospital: Bool { kind == "ward" || kind == "cage" }
}

struct HospCatalogItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let itemType: String?
    let defaultUnitAmount: Int?
    let currency: String?
}

struct HospClientPet: Codable, Identifiable, Hashable {
    let id: String
    let petName: String?
    let petSpecies: String?
    let photoUrl: String?
    let status: String?
}

struct HospClient: Codable, Identifiable, Hashable {
    let id: String
    let ownerName: String?
    let ownerPhone: String?
    let householdId: String?
    let pets: [HospClientPet]?
}

struct HospConsentTerms: Codable, Hashable {
    let version: String?
    let title: String?
    let text: String?
}

struct HospConsent: Codable, Identifiable, Hashable {
    let id: String
    let status: String?
    let title: String?
    let body: String?
    let petName: String?
    let amountCents: Int?
    let currency: String?
    let terms: HospConsentTerms?
}

struct HospConsentAsked: Codable { let consentId: String?; let notified: Bool?; let status: String? }

struct HospRegister: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let openSessionId: String?
    let locationId: String?
}


// MARK: - The API

enum HospAPI {
    static func detailPath(_ id: String) -> String {
        "/provider-hospital/hospitalizations/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)"
    }

    /// Every write answers the detail; other screens hear about it.
    @discardableResult
    static func write(_ id: String, _ path: String, method: String = "POST", body: [String: Any?] = [:]) async throws -> HospDetail {
        let data = try await API.data(method, detailPath(id) + path, query: [:], body: try API.jsonBody(body))
        let detail: HospDetail = try API.decode(data)
        announceDataChanged()
        return detail
    }

    static func members() async -> [HospMember] {
        guard let clinic = Workspace.shared.current?.clinicId else { return [] }
        return (try? await API.get("/provider-workspaces/\(clinic)/members")) ?? []
    }

    static func wards(locationId: String?) async -> [HospRoom] {
        let rooms: [HospRoom] = (try? await API.get("/provider-rooms", query: ["locationId": locationId])) ?? []
        return rooms.filter(\.isHospital)
    }

    /// A page of the Catalog's active items matching `search` (20 at a time, the server's total).
    static func catalogPage(search: String, itemType: String? = nil, offset: Int) async throws -> Page<HospCatalogItem> {
        try await API.get("/provider-catalog", query: [
            "limit": String(ClientSearch.pageSize), "offset": String(offset), "search": search, "itemType": itemType, "active": "true",
        ])
    }

    static func catalog(search: String, itemType: String? = nil, limit: Int = 8) async -> [HospCatalogItem] {
        let page: Page<HospCatalogItem>? = try? await API.get("/provider-catalog", query: [
            "limit": "\(limit)", "offset": "0", "search": search.nonEmpty, "itemType": itemType, "active": "true",
        ])
        return page?.items ?? []
    }

    static func askConsent(_ id: String, kind: String, notify: Bool) async throws -> HospConsentAsked {
        let answer: HospConsentAsked = try await API.post(detailPath(id) + "/consents", body: ["kind": kind, "notify": notify])
        announceDataChanged()
        return answer
    }
}

// MARK: - Words for the server's values (hospital-copy.ts)

enum HospWords {
    static func status(_ value: String?) -> String {
        switch value {
        case "pending": L("Waiting for admission")
        case "admitted": L("Hospitalized")
        case "discharged": L("Discharged")
        case "transferred": L("Transferred")
        case "deceased": L("Passed away")
        case "cancelled": L("Cancelled")
        default: value ?? ""
        }
    }

    static func triage(_ value: String?) -> String {
        switch value {
        case "critical": L("Critical")
        case "urgent": L("Urgent")
        case "stable": L("Stable")
        default: value ?? ""
        }
    }

    static func condition(_ value: String?) -> String {
        switch value {
        case "improving": L("Improving")
        case "stable": L("Stable")
        case "guarded": L("Guarded")
        case "critical": L("Critical")
        default: value ?? ""
        }
    }

    static func kind(_ value: String?) -> String {
        switch value {
        case "medication": L("Medicine")
        case "fluid": L("Fluids")
        case "feeding": L("Feeding")
        case "monitoring": L("Monitoring")
        case "procedure": L("Procedure")
        case "other": L("Other")
        default: value ?? ""
        }
    }

    static func route(_ value: String?) -> String {
        switch value {
        case "oral": L("Oral")
        case "iv": L("IV")
        case "sc": L("Subcutaneous")
        case "im": L("Intramuscular")
        case "topical": L("Topical")
        case "ophthalmic": L("Eye")
        case "otic": L("Ear")
        case "inhaled": L("Inhaled")
        case "rectal": L("Rectal")
        case "other": L("Other route")
        default: value ?? ""
        }
    }

    static func schedule(_ value: String?) -> String {
        switch value {
        case "times": L("At set times")
        case "every": L("Every few hours")
        case "once": L("Once")
        case "prn": L("As needed")
        default: value ?? ""
        }
    }

    static func notGiven(_ value: String?) -> String {
        switch value {
        case "refused": L("Refused it")
        case "vomited": L("Vomited")
        case "held_by_vet": L("Held by the vet")
        case "fasting": L("Fasting")
        case "unavailable": L("Not available")
        case "other": L("Other reason")
        default: value ?? ""
        }
    }

    static func slot(_ value: String?) -> String {
        switch value {
        case "upcoming": L("Upcoming")
        case "due": L("Due now")
        case "late": L("Late")
        case "missed": L("Missed")
        case "given": L("Given")
        case "given_late": L("Given late")
        case "not_given": L("Not given")
        default: value ?? ""
        }
    }

    static func mucous(_ value: String?) -> String {
        switch value {
        case "pink": L("Pink")
        case "pale": L("Pale")
        case "white": L("White")
        case "cyanotic": L("Blue (cyanotic)")
        case "icteric": L("Yellow (icteric)")
        case "injected": L("Red (injected)")
        case "muddy": L("Muddy")
        default: value ?? ""
        }
    }

    static func deathCause(_ value: String?) -> String {
        switch value {
        case "euthanasia": L("Euthanasia")
        case "natural": L("Natural causes")
        case "unknown": L("Unknown")
        default: value ?? ""
        }
    }

    static func aftercare(_ value: String?) -> String {
        switch value {
        case "cremation_individual": L("Individual cremation")
        case "cremation_communal": L("Communal cremation")
        case "burial": L("Burial")
        case "family_takes": L("The family takes them home")
        case "other": L("Other")
        default: value ?? ""
        }
    }

    /// A bill's status, the Invoices page's words.
    static func invoiceStatus(_ value: String?) -> String {
        switch value {
        case "draft": L("Draft")
        case "review": L("In review")
        case "unpriced": L("Needs a price")
        case "ready_for_payment", "open": L("Unpaid")
        case "partially_paid": L("Part paid")
        case "overdue", "late": L("Overdue")
        case "paid": L("Paid")
        case "returned": L("Returned")
        case "refunded": L("Refunded")
        case "canceled", "cancelled", "void": L("Canceled")
        case "forgiven": L("Balance forgiven")
        default: value ?? ""
        }
    }

    static let kinds = ["medication", "fluid", "feeding", "monitoring", "procedure", "other"]
    static let routes = ["oral", "iv", "sc", "im", "topical", "ophthalmic", "otic", "inhaled", "rectal", "other"]
    static let homeRoutes = ["oral", "topical", "ophthalmic", "otic", "sc", "im", "iv", "inhaled", "rectal", "other"]
    static let schedules = ["times", "every", "once", "prn"]
    static let reasons = ["refused", "vomited", "held_by_vet", "fasting", "unavailable", "other"]
    static let slotStates = ["upcoming", "due", "late", "missed", "given", "given_late", "not_given"]
    static let mucousOptions = ["pink", "pale", "white", "cyanotic", "icteric", "injected", "muddy"]
    static let priorities = ["critical", "urgent", "stable"]
    static let conditions = ["improving", "stable", "guarded", "critical"]
    static let causes = ["natural", "euthanasia", "unknown"]
    static let aftercares = ["cremation_individual", "cremation_communal", "burial", "family_takes", "other"]

    /// Triage in the six states: critical red, urgent mango, stable green.
    static func triageState(_ value: String?) -> ProviderState {
        switch value {
        case "critical": .problem
        case "urgent": .waiting
        case "stable": .done
        default: .closed
        }
    }

    static func conditionState(_ value: String?) -> ProviderState {
        switch value {
        case "improving": .active
        case "stable": .upcoming
        case "guarded": .waiting
        case "critical": .problem
        default: .closed
        }
    }
}

// MARK: - The server's refusals (hospitalError)

/// A refusal from the hospital endpoints, in the reader's language.
func hospError(_ error: Error, fallback: String = "Something went wrong. Try again.") -> String {
    if let api = error as? APIError {
        if api.isOffline { return api.message }
        if api.code == "room_full" && LocalizationManager.shared.currentLanguage != .spanish, !api.message.isEmpty { return api.message }
        if api.code == "forbidden", !api.message.isEmpty { return L(api.message) }
        if let code = api.code, let known = hospKnownError(code) { return known }
        if !api.message.isEmpty, api.isRefusal || LocalizationManager.shared.currentLanguage != .spanish { return api.message }
    }
    return L(fallback)
}

/// The same words, for a refusal sent back inside an answer (`{ code, error }`).
func hospRefusalText(code: String?, error: String?, fallback: String) -> String {
    if let code, let known = hospKnownError(code) { return known }
    if let error = error?.nonEmpty, LocalizationManager.shared.currentLanguage != .spanish { return error }
    return L(fallback)
}

/// The refusal carrying the hospital's own words (for a ConfirmSheet, which shows the error's message).
func hospRefusal(_ error: Error, fallback: String) -> APIError {
    let api = error as? APIError
    return APIError(status: api?.status ?? 400, message: hospError(error, fallback: fallback), code: api?.code, fields: [:])
}

private func hospKnownError(_ code: String) -> String? {
    switch code {
    case "not_found": L("This hospitalization was not found.")
    case "patient_not_found": L("That patient was not found.")
    case "patient_deceased": L("This patient is recorded as deceased.")
    case "reason_required": L("Say why.")
    case "invalid_priority": L("Choose critical, urgent or stable.")
    case "invalid_amount": L("Enter a valid amount.")
    case "deposit_over_estimate": L("The deposit can’t be more than the estimate.")
    case "visit_not_found": L("That visit was not found.")
    case "visit_mismatch": L("That visit is for another pet.")
    case "visit_closed": L("That visit is closed.")
    case "room_not_found": L("That ward or cage was not found.")
    case "not_hospital_room": L("That room is not a ward or a cage — mark it as one in Settings → Rooms.")
    case "invalid_location": L("That location can’t take it.")
    case "room_full": L("That ward or cage is full.")
    case "invalid_member": L("That person is not on your team.")
    case "already_hospitalized": L("This patient is already in the hospital.")
    case "estimate_required": L("Enter the estimate before asking the family to sign it.")
    case "template_missing": L("There is no consent template for this — add one in Settings → Consents.")
    case "hospitalization_closed": L("This hospitalization is over.")
    case "not_pending": L("Only a hospitalization not admitted yet can be cancelled — discharge the patient instead.")
    case "not_admitted": L("The patient isn’t admitted.")
    case "consent_required": L("The family hasn’t signed the consent yet.")
    case "deposit_required": L("The deposit hasn’t been paid yet.")
    case "override_forbidden": L("Only owners and admins can go ahead without it.")
    case "deposit_override_forbidden": L("Only owners and admins can start before the deposit is paid.")
    case "override_reason_required": L("Say why you go ahead without it.")
    case "invalid_kind": L("Choose what kind of order it is.")
    case "invalid_schedule": L("Choose when it is given.")
    case "invalid_route": L("Choose the route from the list.")
    case "invalid_item": L("That item is not in your catalog.")
    case "label_required": L("Name the order.")
    case "invalid_dose": L("Enter a dose greater than zero.")
    case "dose_required": L("A medicine needs its dose and unit.")
    case "rate_required": L("Fluids need their rate (ml/h).")
    case "invalid_time": L("Use a valid date and time.")
    case "too_many_times": L("At most 24 times a day.")
    case "invalid_quantity": L("Charge between 1 and 1000 per dose.")
    case "order_not_found": L("That order was not found.")
    case "order_stopped": L("This order was stopped — write a new one.")
    case "stale_order": L("Someone changed this order in the meantime — review it again.")
    case "invalid_status": L("Given or not given?")
    case "future_time": L("That time is in the future.")
    case "before_admission": L("That time is before the admission.")
    case "not_scheduled": L("That time is not on this order’s schedule.")
    case "already_recorded": L("This dose is already on the sheet.")
    case "open_doses": L("Some doses on the sheet aren’t marked yet. Mark each as given or not given before the patient leaves.")
    case "order_has_doses": L("This order already has doses on the sheet. Stop it and write the new schedule as a new order.")
    case "not_due_yet": L("This dose isn’t due yet. Mark it when it is given, or use Extra dose.")
    case "administration_not_found": L("That dose is not on the sheet.")
    case "vitals_not_found": L("Those vitals were not found.")
    case "invalid_vitals": L("Check the vitals: one is out of range.")
    case "message_required": L("Write the update.")
    case "invalid_condition": L("Choose the condition from the list.")
    case "invalid_photo": L("Use a jpg, png or webp photo.")
    case "photo_too_large": L("The photo is too large (5 MB max).")
    case "photo_upload_failed": L("The photo could not be uploaded — try again.")
    case "invalid_day": L("Choose a valid day.")
    case "future_day": L("Rounds are signed for today or an earlier day.")
    case "already_signed": L("Rounds for that day are already signed.")
    case "summary_required": L("Write the discharge summary.")
    case "too_many_items": L("At most 20 medicines to take home.")
    case "take_home_name_required": L("Name each medicine to take home.")
    case "invalid_cause": L("Choose euthanasia, natural or unknown.")
    case "invalid_aftercare": L("Choose the aftercare from the list.")
    case "undo_window_passed": L("It can only be undone within 24 hours.")
    case "shift_overlap": L("That person is already on call then.")
    case "invalid_shift": L("Check the shift: it ends after it starts and lasts at most 7 days.")
    case "shift_past": L("That shift is already over.")
    case "invalid_range": L("Use a valid range.")
    case "hospital_room": L("Wards and cages hold hospitalized patients only — choose a room for visits.")
    case "forbidden": L("You don’t have access to this.")
    case "member_required": L("Only a team member can sign a prescription.")
    case "credential_required": L("Add your professional license to your profile to sign prescriptions.")
    case "prescriptions_unavailable": L("Prescriptions are not available yet.")
    case "prescription_failed": L("The prescription could not be written.")
    default: nil
    }
}

// MARK: - Times, numbers, typed values (lib/hospital.ts)

enum HospFmt {
    /// "2:00 p.m." on the hospital's clock.
    static func clock(_ iso: String?, _ zone: TimeZone) -> String { DateText.time(DateText.parse(iso), zone: zone) }

    /// "4 nov, 2:00 p.m."
    static func dateTime(_ iso: String?, _ zone: TimeZone) -> String {
        guard let date = DateText.parse(iso) else { return "" }
        return format(date, "dMMMjmm", zone)
    }

    static func dateTime(_ date: Date, _ zone: TimeZone) -> String { format(date, "dMMMjmm", zone) }

    /// A day key (yyyy-MM-dd) as "mié 4 nov" (or the long "miércoles 4 de noviembre", or "4 nov").
    static func day(_ key: String?, style: DayStyle = .short, zone: TimeZone) -> String {
        guard let key, let date = dayDate(key, zone) else { return key ?? "" }
        switch style {
        case .short: return format(date, "EEEdMMM", zone)
        case .long: return format(date, "EEEEdMMMM", zone)
        case .compact: return format(date, "dMMM", zone)
        }
    }

    enum DayStyle { case short, long, compact }

    /// Noon of a day key on a clock.
    static func dayDate(_ key: String, _ zone: TimeZone) -> Date? {
        DateText.dayFormatter(zone).date(from: String(key.prefix(10))).map { $0.addingTimeInterval(12 * 3600) }
    }

    /// The day key an instant falls on, on a clock.
    static func dayKey(_ iso: String?, _ zone: TimeZone) -> String? {
        DateText.parse(iso).map { DateText.dayKey($0, zone: zone) }
    }

    /// "14:00" said the way the sheet says times ("2:00 p.m.").
    static func timeOfDay(_ value: String) -> String {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return value }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: h, minute: m)) else { return value }
        return format(date, "jmm", TimeZone(identifier: "UTC")!)
    }

    private static func format(_ date: Date, _ template: String, _ zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = zone
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }

    /// A number as people write it: "38.5", "110".
    static func number(_ value: Double?, digits: Int = 3) -> String {
        guard let value else { return "" }
        if value == value.rounded() { return String(Int(value)) }
        let f = NumberFormatter()
        f.locale = .app
        f.maximumFractionDigits = digits
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// "5 mg".
    static func dose(_ amount: Double?, _ unit: String?) -> String {
        guard let amount else { return "" }
        let text = number(amount)
        return unit?.nonEmpty.map { "\(text) \($0)" } ?? text
    }

    /// A number typed with a comma or a point: nil when empty, .nan when not a number.
    static func read(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed) ?? .nan
    }

    /// Dose, route and rate on one line.
    static func orderLine(_ order: HospOrder) -> String {
        [
            dose(order.doseAmount, order.doseUnit).nonEmpty,
            order.route.map { HospWords.route($0) },
            order.rateMlPerHour.map { LF("%@ ml/h", number($0)) },
        ].compactMap { $0 }.joined(separator: " · ")
    }

    /// What an order's schedule says, in words.
    static func schedule(_ order: HospOrder, _ zone: TimeZone) -> String {
        switch order.scheduleKind {
        case "times":
            let times = order.scheduleTimes ?? []
            return times.isEmpty ? L("At set times") : times.map { timeOfDay($0) }.joined(separator: " · ")
        case "every": return LF("Every %@ h", order.everyHours.map(String.init) ?? "?")
        case "once": return order.onceAt != nil ? LF("Once, %@", dateTime(order.onceAt, zone)) : L("Once")
        case "prn": return L("As needed")
        default: return ""
        }
    }

    /// Times of day typed as "8:00, 20:00", "08 20" or "8 am, 2:30 p.m." → sorted HH:MM; nil when one is not a time.
    static func parseTimesOfDay(_ text: String) -> [String]? {
        var joined = text.lowercased()
        if let regex = try? NSRegularExpression(pattern: "\\s*([ap])\\.?\\s?m\\.?(?![a-z])") {
            joined = regex.stringByReplacingMatches(in: joined, range: NSRange(joined.startIndex..., in: joined), withTemplate: "$1m")
        }
        let parts = joined.components(separatedBy: CharacterSet(charactersIn: " ,;\n\t")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if parts.isEmpty { return [] }
        guard let regex = try? NSRegularExpression(pattern: "^(\\d{1,2})(?::?(\\d{2}))?(am|pm)?$") else { return nil }
        var out = Set<String>()
        for part in parts {
            guard let match = regex.firstMatch(in: part, range: NSRange(part.startIndex..., in: part)) else { return nil }
            func group(_ i: Int) -> String? {
                guard let range = Range(match.range(at: i), in: part) else { return nil }
                return String(part[range])
            }
            var hours = Int(group(1) ?? "") ?? 0
            let minutes = Int(group(2) ?? "0") ?? 0
            if let half = group(3) {
                if hours < 1 || hours > 12 { return nil }
                hours = (hours % 12) + (half == "pm" ? 12 : 0)
            }
            if hours > 23 || minutes > 59 { return nil }
            out.insert(String(format: "%02d:%02d", hours, minutes))
        }
        return out.sorted()
    }

    /// Out of the usual range for a dog or cat (a hint on the table, never a diagnosis).
    static func outOfRange(_ metric: HospMetric, _ value: Double, species: String?) -> Bool {
        let cat = species?.lowercased() == "cat"
        switch metric {
        case .temperatureC: return value < 37.5 || value > 39.4
        case .heartRate: return cat ? (value < 120 || value > 220) : (value < 60 || value > 160)
        case .respiratoryRate: return cat ? (value < 16 || value > 40) : (value < 10 || value > 40)
        case .painScore: return value >= 4
        case .weightGrams: return false
        }
    }
}

enum HospMetric: String, CaseIterable, Identifiable {
    case temperatureC, heartRate, respiratoryRate, painScore, weightGrams
    var id: String { rawValue }

    var title: String {
        switch self {
        case .temperatureC: L("Temperature")
        case .heartRate: L("Heart rate")
        case .respiratoryRate: L("Breathing")
        case .painScore: L("Pain")
        case .weightGrams: L("Weight")
        }
    }

    var unit: String {
        switch self {
        case .temperatureC: "°C"
        case .heartRate: "bpm"
        case .respiratoryRate: "/min"
        case .painScore: "/10"
        case .weightGrams: "kg"
        }
    }

    var hue: Hue {
        switch self {
        case .temperatureC: .peach
        case .heartRate: .lavender
        case .respiratoryRate: .sky
        case .painScore: .butter
        case .weightGrams: .mint
        }
    }

    func value(_ vitals: HospVitals) -> Double? {
        switch self {
        case .temperatureC: vitals.temperatureC
        case .heartRate: vitals.heartRate
        case .respiratoryRate: vitals.respiratoryRate
        case .painScore: vitals.painScore
        case .weightGrams: vitals.weightGrams.map { ($0 / 10).rounded() / 100 }
        }
    }
}

/// Vitals typed in a form (VitalsDraft): every field optional, each checked for its range.
struct HospVitalsDraft: Equatable {
    var temperatureC = ""
    var heartRate = ""
    var respiratoryRate = ""
    var painScore = ""
    var weightKg = ""
    var mucousMembranes = ""
    var crtSeconds = ""

    enum Field: String { case temperatureC, heartRate, respiratoryRate, painScore, weightKg, mucousMembranes, crtSeconds }

    static func label(_ field: Field) -> String {
        switch field {
        case .temperatureC: L("Temperature (°C)")
        case .heartRate: L("Heart rate (bpm)")
        case .respiratoryRate: L("Breaths (/min)")
        case .painScore: L("Pain (0–10)")
        case .weightKg: L("Weight (kg)")
        case .mucousMembranes: L("Gums")
        case .crtSeconds: L("CRT (s)")
        }
    }

    /// The vitals to send (nil when nothing was typed), or the first wrong field.
    func parsed() -> Result<[String: Any]?, HospVitalsError> {
        var out: [String: Any] = [:]
        let checks: [(Field, String, Double, Double, Bool)] = [
            (.temperatureC, temperatureC, 25, 45, false),
            (.heartRate, heartRate, 10, 400, true),
            (.respiratoryRate, respiratoryRate, 2, 200, true),
            (.painScore, painScore, 0, 10, true),
            (.crtSeconds, crtSeconds, 0, 10, false),
        ]
        for (field, text, min, max, whole) in checks {
            guard let value = HospFmt.read(text) else { continue }
            if value.isNaN || value < min || value > max || (whole && value != value.rounded()) { return .failure(HospVitalsError(field: field)) }
            out[field.rawValue] = whole ? Int(value) as Any : value as Any
        }
        if let weight = HospFmt.read(weightKg) {
            if weight.isNaN || weight <= 0 || weight > 200 { return .failure(HospVitalsError(field: .weightKg)) }
            out["weightGrams"] = Int((weight * 1000).rounded())
        }
        if let gums = mucousMembranes.nonEmpty { out["mucousMembranes"] = gums }
        return .success(out.isEmpty ? nil : out)
    }
}

struct HospVitalsError: Error { let field: HospVitalsDraft.Field }
