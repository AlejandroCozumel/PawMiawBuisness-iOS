//
//  ClientsModels.swift
//  PawMiawNegocios
//
//  The shapes the Clients module reads, mirroring the web's hooks
//  (use-provider-clients.ts, use-patient-chart.ts, use-provider-client-
//  invitations.ts, use-provider-care.ts, use-client-addresses.ts,
//  use-client-closing.ts). Everything that can be absent is Optional, so an
//  older or newer server never breaks a screen.
//

import Foundation

// MARK: - People and pets

struct ClientsActor: Codable, Hashable {
    let id: String?
    let name: String?
}

struct ClientsClosingStamp: Codable, Hashable {
    let at: String?
    let byName: String?
    let reason: String?
    let note: String?
    let signatureId: String?
}

struct ClientsMoveLink: Codable, Hashable {
    let petId: String
    let clientId: String
    let clientName: String?
}

struct ClientsPet: Codable, Identifiable, Hashable {
    let id: String
    let providerClientId: String?
    /// The family's pet it is linked to, when the family is on PawMiaw.
    let petId: String?
    let preferredMember: ClientsActor?
    let petName: String
    let petSpecies: String?
    let petBreed: String?
    let sex: String?
    let birthDate: String?
    let photoUrl: String?
    /// Grams.
    let weight: Double?
    let isNeutered: Bool?
    let microchipNumber: String?
    let notes: String?
    let profileSource: String?
    let profileLastSyncedAt: String?
    let status: String?
    let deceasedAt: String?
    let closing: ClientsClosingStamp?
    let movedTo: ClientsMoveLink?
    let movedFrom: ClientsMoveLink?

    var isArchived: Bool { status == "archived" }
    var isActive: Bool { (status ?? "active") == "active" }
    var isLinked: Bool { petId?.nonEmpty != nil }
}

struct ClientsClientActivity: Codable, Hashable {
    let lastVisitAt: String?
    let nextVisitAt: String?
    /// Null without money level 1.
    let owedAmount: Int?
    let currency: String?
}

struct ClientsClient: Codable, Identifiable, Hashable {
    let id: String
    let householdId: String?
    let selfLinkDeclined: Bool?
    let ownerFirstName: String?
    let ownerLastName: String?
    let ownerName: String
    let linkedAccountName: String?
    let businessLinkedAt: String?
    let canBookOnline: Bool?
    let ownerEmail: String?
    let recipientLanguage: String?
    let ownerPhone: String?
    let photoUrl: String?
    let notes: String?
    let status: String?
    let closing: ClientsClosingStamp?
    let petCount: Int?
    let pets: [ClientsPet]?
    let assignedMember: ClientsActor?
    let activity: ClientsClientActivity?
    let createdAt: String?

    var allPets: [ClientsPet] { pets ?? [] }
    var isArchived: Bool { status == "archived" }
    var isLinked: Bool { householdId?.nonEmpty != nil }
}

struct ClientsDirectorySummary: Codable {
    let clients: Int?
    let pets: Int?
    let dueThisWeek: Int?
    let owing: Int?
    let archived: Int?
}

struct ClientsRowClient: Codable, Hashable {
    let id: String
    let name: String?
    let phone: String?
    let photoUrl: String?
    let onPawMiaw: Bool?
}

struct ClientsPetActivity: Codable, Hashable {
    let lastVisitAt: String?
    let nextVisitAt: String?
    let nextDueAt: String?
    let nextDueTitle: String?
    let allergies: [String]?
}

/// A pet with its owner on the row: the Patients view and the directory's pets.
struct ClientsPatientRow: Codable, Identifiable, Hashable {
    let id: String
    let petName: String
    let petSpecies: String?
    let petBreed: String?
    let sex: String?
    let birthDate: String?
    let photoUrl: String?
    let microchipNumber: String?
    let linked: Bool?
    let vaccinesOverdue: Bool?
    let status: String?
    let deceasedAt: String?
    let client: ClientsRowClient
    let activity: ClientsPetActivity?
}

struct ClientsPatientsSummary: Codable {
    let pets: Int?
    let vaccinesOverdue: Int?
    let seenLast30Days: Int?
    let linked: Int?
    let archived: Int?
}

struct ClientsMember: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let email: String?
    let isCurrentMember: Bool?

    var label: String { name?.nonEmpty ?? email?.nonEmpty ?? L("Unnamed staff") }
}

// MARK: - The client page's other parts

struct ClientsAppointment: Codable, Identifiable, Hashable {
    let id: String
    let providerClientId: String?
    let providerClientPetId: String?
    let serviceLabel: String?
    let startsAt: String?
    let status: String?
    let petName: String?
    let petSpecies: String?
    let petPhotoUrl: String?
    let assignedMember: ClientsActor?
    let onlineBooking: Bool?
}

struct ClientsInvoice: Codable, Identifiable, Hashable {
    let id: String
    let invoiceNumber: String?
    let status: String?
    let currency: String?
    let totalAmount: Int?
    let balanceDueAmount: Int?
    let issuedAt: String?
    let createdAt: String?
    let petName: String?
}

struct ClientsInvoicePage: Decodable {
    let items: [ClientsInvoice]
    let total: Int?
}

struct ClientsAccount: Codable {
    let credit: Int?
    let currency: String?
    let owed: Int?
    let overdue: Int?
}

struct ClientsFollowUp: Codable, Identifiable, Hashable {
    let id: String
    let title: String?
    let followUpType: String?
    let status: String?
    let dueAt: String?
    let assignedMember: ClientsActor?
}

// MARK: - Addresses

struct ClientsVaultState: Codable, Hashable {
    let hasVault: Bool?
    let fields: [String]?
}

struct ClientsAddress: Codable, Identifiable, Hashable {
    let id: String
    let source: String?
    let label: String?
    let line1: String?
    let line2: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let country: String?
    let reference: String?
    let latitude: Double?
    let longitude: Double?
    let isDefault: Bool?
    let status: String?
    let formatted: String?
    let mapsUrl: String?
    let vault: ClientsVaultState?

    var isBusiness: Bool { source == "business" }
    var name: String { label?.nonEmpty ?? line1 ?? "" }
}

struct ClientsEmergencyContact: Codable, Hashable {
    let name: String?
    let phone: String?
    let relationship: String?

    var isEmpty: Bool { name?.nonEmpty == nil && phone?.nonEmpty == nil }
}

struct ClientsHome: Codable {
    let addresses: [ClientsAddress]?
    let emergencyContact: ClientsEmergencyContact?
    let familyEmergencyContact: ClientsEmergencyContact?
    let linked: Bool?
    let familyVaultShared: Bool?
    let canEdit: Bool?
    let canManageVault: Bool?
}

// MARK: - The patient chart

struct ClientsChartPet: Codable, Hashable {
    let id: String
    let clientId: String?
    let name: String
    let species: String?
    let breed: String?
    let sex: String?
    let birthDate: String?
    let photoUrl: String?
    let weightGrams: Double?
    let isNeutered: Bool?
    let microchipNumber: String?
    let notes: String?
    let status: String?
    let deceasedAt: String?
    let closing: ClientsClosingStamp?
    let movedTo: ClientsMoveLink?
    let movedFrom: ClientsMoveLink?
    let clientArchived: Bool?
    let linked: Bool?
}

struct ClientsChartClient: Codable, Hashable {
    let id: String
    let name: String
    let phone: String?
    let email: String?
    let photoUrl: String?
    let onPawMiaw: Bool?
    let householdId: String?
}

struct ClientsChartAlert: Codable, Hashable {
    let kind: String
    let label: String
    let detail: String?
    let source: String?
    let recordId: String?
}

struct ClientsSummaryEntry: Codable, Hashable {
    let label: String?
    let name: String?
    let detail: String?
    let dose: String?
    let endDay: String?
    let source: String?
    let recordId: String?
    let at: String?
    let draft: Bool?
}

struct ClientsVaccineLine: Codable, Hashable {
    let name: String
    let lastGivenAt: String?
    let nextDueDay: String?
    let status: String?
    let source: String?
    let recordId: String?
    let doses: Int?
}

struct ClientsLabLine: Codable, Hashable {
    let id: String
    let name: String?
    let result: String?
    let at: String?
    let source: String?
    let draft: Bool?
}

struct ClientsChartSummary: Codable, Hashable {
    let allergies: [ClientsSummaryEntry]?
    let problems: [ClientsSummaryEntry]?
    let medications: [ClientsSummaryEntry]?
    let vaccines: [ClientsVaccineLine]?
    let labs: [ClientsLabLine]?
}

struct ClientsWeightPoint: Codable, Hashable {
    let id: String?
    let at: String
    let grams: Double
    let used: Bool?
}

struct ClientsHomeWeights: Codable, Hashable {
    let latestId: String?
    let latestGrams: Double?
    let latestAt: String?
    let latestUsed: Bool?
    let trend: [ClientsWeightPoint]?
}

struct ClientsChartWeights: Codable, Hashable {
    let latestGrams: Double?
    let latestAt: String?
    let trend: [ClientsWeightPoint]?
    let home: ClientsHomeWeights?
    let differs: Bool?
}

struct ClientsCare: Codable, Hashable {
    let handlingTags: [String]?
    let careNotes: String?
    let groomStyle: String?
    let rebookEveryWeeks: Int?
    let nextGroomDueAt: String?
}

struct ClientsNextVisit: Codable, Hashable {
    let id: String
    let startsAt: String?
    let serviceLabel: String?
    let status: String?
}

struct ClientsBalance: Codable, Hashable {
    let client: Int?
    let pet: Int?
    let currency: String?
}

struct ClientsChartActivity: Codable, Hashable {
    let lastVisitAt: String?
    let nextVisit: ClientsNextVisit?
    let balance: ClientsBalance?
}

struct ClientsChartCounts: Codable, Hashable {
    let toSign: Int?
    let openFollowUps: Int?
}

struct ClientsShareAccess: Codable, Hashable {
    let canView: Bool?
    let shareScope: String?
    let sharedSince: String?
}

struct ClientsChartViewer: Codable, Hashable {
    let seesRecords: Bool?
    let seesVisits: Bool?
    let seesDrafts: Bool?
    let seesInternalNotes: Bool?
    let canSign: Bool?
    let seesBilling: Bool?
    let seesFollowUps: Bool?
}

struct ClientsChart: Codable, Hashable {
    let pet: ClientsChartPet
    let client: ClientsChartClient
    let alerts: [ClientsChartAlert]?
    let summary: ClientsChartSummary?
    let weights: ClientsChartWeights?
    let care: ClientsCare?
    let activity: ClientsChartActivity?
    let counts: ClientsChartCounts?
    let sharedHistoryAccess: ClientsShareAccess?
    let viewer: ClientsChartViewer?
    let today: String?

    var isArchived: Bool { pet.status == "archived" }
    var died: Bool { pet.deceasedAt?.nonEmpty != nil }
}

// MARK: - The history

struct ClientsAttachment: Codable, Hashable, Identifiable {
    let id: String
    let fileName: String?
    let url: String?
    let mimeType: String?
}

struct ClientsPersonRef: Codable, Hashable {
    let id: String?
    let name: String?
}

struct ClientsChartRecord: Codable, Hashable, Identifiable {
    let id: String
    let appointmentId: String?
    let recordType: String?
    let title: String?
    let summary: String?
    let details: String?
    let internalNote: String?
    let payload: [String: JSONValue]?
    let eventAt: String?
    let status: String?
    let signedAt: String?
    let signedBy: ClientsPersonRef?
    let createdBy: ClientsPersonRef?
    let amendedAt: String?
    let attachments: [ClientsAttachment]?
    let actionable: Bool?
    let carriedOver: Bool?
}

struct ClientsChartWeight: Codable, Hashable, Identifiable {
    let id: String
    let grams: Double
    let recordedAt: String?
    let source: String?
    let notes: String?
    let loggedBy: String?
    let sharedWithOwner: Bool?
    let from: String?
}

struct ClientsPlaceRef: Codable, Hashable {
    let id: String?
    let name: String?
}

struct ClientsChartVisit: Codable, Hashable, Identifiable {
    let id: String
    let serviceLabel: String?
    let serviceCategory: String?
    let status: String?
    let startsAt: String?
    let notes: String?
    let arrivalNote: String?
    let groomRequestSummary: String?
    let report: JSONValue?
    let assigned: ClientsPersonRef?
    let location: ClientsPlaceRef?
    let actionable: Bool?
    let carriedOver: Bool?
    let records: [ClientsChartRecord]?
    let weights: [ClientsChartWeight]?
}

struct ClientsFamilyRecord: Codable, Hashable, Identifiable {
    let id: String
    let recordType: String?
    let title: String?
    let summary: String?
    let details: String?
    let payload: [String: JSONValue]?
    let eventAt: String?
    let nextDueAt: String?
    let createdAt: String?
    let by: String?
    let attachments: [ClientsAttachment]?
}

struct ClientsTimelineItem: Codable, Hashable, Identifiable {
    let key: String
    let kind: String
    let at: String?
    let visit: ClientsChartVisit?
    let record: ClientsChartRecord?
    let familyRecord: ClientsFamilyRecord?
    let weight: ClientsChartWeight?
    let incident: JSONValue?
    let consent: JSONValue?

    var id: String { key }
}

struct ClientsTimelineSources: Codable, Hashable {
    let visits: Bool?
    let clinicRecords: Bool?
    let family: Bool?
    let weights: Bool?
    let grooming: Bool?
}

struct ClientsTimelinePage: Codable {
    let items: [ClientsTimelineItem]
    let nextCursor: String?
    let filters: [String]?
    let sources: ClientsTimelineSources?
}

// MARK: - Invitations

struct ClientsInvitationPet: Codable, Hashable {
    let providerClientPetId: String
    let petName: String?
    let petSpecies: String?
    let householdPetId: String?
    let consentDecision: String?
}

struct ClientsInvitationClient: Codable, Hashable {
    let id: String
    let ownerName: String?
    let ownerEmail: String?
    let ownerPhone: String?
    let householdId: String?
}

struct ClientsPendingAccount: Codable, Hashable {
    let id: String?
    let name: String?
    let email: String?
}

struct ClientsPendingHousehold: Codable, Hashable {
    let id: String?
    let name: String?
}

struct ClientsPendingDecision: Codable, Hashable {
    let providerClientPetId: String?
    let decision: String?
    let householdPetName: String?
}

struct ClientsPendingAcceptance: Codable, Hashable {
    let account: ClientsPendingAccount?
    let household: ClientsPendingHousehold?
    let requestedAt: String?
    let decisions: [ClientsPendingDecision]?
}

struct ClientsInvitation: Codable, Identifiable, Hashable {
    let id: String
    let providerClientId: String
    let householdId: String?
    let recipientEmail: String?
    let recipientName: String?
    let message: String?
    let status: String
    let emailStatus: String?
    let emailSentAt: String?
    let url: String?
    let expiresAt: String?
    let acceptedAt: String?
    let revokedAt: String?
    let expiredAt: String?
    let createdAt: String?
    let updatedAt: String?
    let latestForClient: Bool?
    let createdBy: ClientsActor?
    let revokedBy: ClientsActor?
    let client: ClientsInvitationClient?
    let pets: [ClientsInvitationPet]?
    let pendingAcceptance: ClientsPendingAcceptance?
}

struct ClientsBulkSent: Codable, Hashable {
    let clientId: String
    let invitationId: String?
}

struct ClientsBulkSkipped: Codable, Hashable {
    let clientId: String
    let reason: String
}

struct ClientsBulkResult: Codable {
    let sent: [ClientsBulkSent]
    let skipped: [ClientsBulkSkipped]
}

// MARK: - Due

struct ClientsDuePet: Codable, Hashable {
    let id: String
    let name: String
    let species: String?
    let photoUrl: String?
}

struct ClientsDueClient: Codable, Hashable {
    let id: String
    let name: String
    let firstName: String?
    let phone: String?
    let onPawMiaw: Bool?
}

struct ClientsDueService: Codable, Hashable {
    let category: String?
    let id: String?
    let label: String?
}

struct ClientsDueContact: Codable, Hashable {
    let channel: String?
    let at: String?
}

struct ClientsFamilyNotice: Codable, Hashable {
    let asked: Bool?
    let sentAt: String?
}

struct ClientsDueItem: Codable, Identifiable, Hashable {
    let key: String
    let reason: String
    let title: String?
    let dueAt: String
    let days: Int?
    let bucket: String
    let followUpId: String?
    let nextVisit: ClientsNextVisit?
    let missedVisitAt: String?
    let service: ClientsDueService?
    let snoozedUntil: String?
    let familyNotice: ClientsFamilyNotice?
    let pet: ClientsDuePet
    let client: ClientsDueClient
    let lastVisitAt: String?
    let lastContact: ClientsDueContact?

    var id: String { key }
}

struct ClientsDueCounts: Codable, Hashable {
    let overdue: Int?
    let thisWeek: Int?
    let later: Int?
    let total: Int?
}

struct ClientsDueList: Codable {
    let now: String?
    let windowDays: Int?
    let counts: ClientsDueCounts?
    let items: [ClientsDueItem]
}

struct ClientsRemindResult: Codable {
    let channel: String?
    let message: String?
    let link: String?
    let sentTo: Int?
}

// MARK: - Archiving

struct ClientsClosingPreviewPet: Codable, Hashable {
    let id: String
    let name: String?
    let blockers: [String]?
}

struct ClientsClosingVisit: Codable, Hashable, Identifiable {
    let id: String
    let petName: String?
    let startsAt: String?
    let serviceLabel: String?
}

struct ClientsClosingPreview: Codable {
    let pets: [ClientsClosingPreviewPet]?
    let upcomingVisits: [ClientsClosingVisit]?
    let openFollowUps: Int?
    let invitationsRevoked: Int?
}

struct ClientsClosingResult: Codable {
    let client: ClientsClient?
    let visitsCancelled: Int?
    let followUpsCancelled: Int?
    let invitationsRevoked: Int?
    let followUpsReopened: Int?
}

struct ClientsOnlineBookingAnswer: Codable {
    let clientId: String?
    let allowed: Bool?
    let client: ClientsClient?
}

/// One pet of a client, resolved for the chart (a route that only carries the pet).
struct ClientsPetOwnerRef: Decodable {
    let providerClientId: String?
}
