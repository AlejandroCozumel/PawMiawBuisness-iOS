//
//  RecordsModels.swift
//  PawMiawNegocios
//
//  The Records module's shapes (web hooks/use-provider-records.ts,
//  use-provider-follow-ups.ts) and the endpoints the web hooks call:
//  GET/POST /provider-records, GET/PATCH /provider-records/{id},
//  POST …/sign, POST …/discard, attachments, GET/PATCH /provider-follow-ups,
//  POST …/remind, the team (/provider-workspaces/{id}/members) and the
//  record's history (/audit-events).
//

import Foundation

// MARK: - Shapes

struct RecordsActor: Codable, Hashable {
    let id: String?
    let name: String?
    let image: String?
}

struct RecordsMemberRef: Codable, Hashable {
    let id: String?
    let name: String?
}

struct RecordsAttachment: Codable, Hashable, Identifiable {
    let id: String
    let fileName: String
    let url: String
    let mimeType: String?
    let fileSizeBytes: Double?
    let createdAt: String?

    /// A photo opens large; anything else is a document (the web's `isImage`).
    var isImage: Bool {
        if let mime = mimeType?.lowercased(), !mime.isEmpty { return mime.hasPrefix("image/") }
        let lower = fileName.lowercased()
        return [".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic"].contains { lower.hasSuffix($0) }
    }

    /// "PDF", "DOCX": the tile's label for a document.
    var fileExtension: String {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return "" }
        return String(fileName[fileName.index(after: dot)...].prefix(4)).uppercased()
    }

    /// "240 KB", "1.2 MB".
    var sizeText: String? {
        guard let bytes = fileSizeBytes, bytes > 0 else { return nil }
        if bytes < 1024 * 1024 { return "\(max(1, Int((bytes / 1024).rounded()))) KB" }
        return String(format: "%.1f MB", bytes / (1024 * 1024))
    }
}

/// A record (web `ProviderRecord`). Signed = `active`, shared with a family on PawMiaw.
struct RecordsRecord: Codable, Identifiable, Hashable {
    let id: String
    let clinicId: String?
    let appointmentId: String?
    let providerClientId: String
    let providerClientPetId: String
    let recordType: String?
    let title: String?
    let summary: String?
    let details: String?
    let internalNote: String?
    let payload: [String: JSONValue]?
    let eventAt: String?
    let followUpAt: String?
    let status: String?
    let attachments: [RecordsAttachment]?
    let clientName: String?
    let clientEmail: String?
    let clientPhone: String?
    let clientHouseholdId: String?
    let clientPhotoUrl: String?
    let petName: String?
    let petSpecies: String?
    let petBreed: String?
    let petSex: String?
    let petBirthDate: String?
    /// Grams.
    let petWeight: Double?
    let petIsNeutered: Bool?
    let petMicrochipNumber: String?
    let petPhotoUrl: String?
    let assignedMember: RecordsMemberRef?
    let createdBy: RecordsActor?
    let updatedBy: RecordsActor?
    let createdAt: String?
    let updatedAt: String?
    let signedAt: String?
    let signedBy: RecordsActor?
    let amendedAt: String?
    let revision: Int?

    var kind: RecordsKind { RecordsKind.of(recordType) }
    var isDraft: Bool { status == "draft" }
    var isSigned: Bool { status == "active" }
    var files: [RecordsAttachment] { attachments ?? [] }
    var titleText: String { title?.nonEmpty ?? kind.label }
    var petText: String { petName?.nonEmpty ?? "—" }
    var clientText: String { clientName?.nonEmpty ?? "—" }
    var onPawMiaw: Bool { clientHouseholdId?.nonEmpty != nil }
    /// Nothing written and nothing attached: the only kind of draft the server lets go (discard).
    var isEmptyDraft: Bool {
        isDraft && summary.nonEmpty == nil && details.nonEmpty == nil && internalNote.nonEmpty == nil && files.isEmpty
    }

    var petFilter: RecordsPetFilter {
        RecordsPetFilter(id: providerClientPetId, clientId: providerClientId, name: petText, clientName: clientText, species: petSpecies, photoUrl: petPhotoUrl)
    }

    func payloadText(_ key: String) -> String? {
        guard let value = payload?[key] else { return nil }
        return value.string?.nonEmpty
    }
}

/// A follow-up (web `ProviderFollowUp`): a recheck, a call, a vaccine due, or a visit's paperwork.
struct RecordsFollowUp: Codable, Identifiable, Hashable {
    let id: String
    let providerRecordId: String?
    let providerAppointmentId: String?
    let providerClientId: String
    let providerClientPetId: String
    let followUpType: String?
    let title: String?
    let note: String?
    let dueAt: String?
    let status: String?
    let completedAt: String?
    let resolutionType: String?
    let resolutionReason: String?
    let resolvedAt: String?
    let outcomeNote: String?
    let clientName: String?
    let clientPhotoUrl: String?
    let petName: String?
    let petSpecies: String?
    let petBreed: String?
    let petPhotoUrl: String?
    let recordTitle: String?
    let recordType: String?
    let appointmentStartsAt: String?
    let appointmentServiceLabel: String?
    let assignedMember: RecordsMemberRef?

    /// Still to act on: open, reminded, or put off.
    var isPending: Bool { ["open", "contacted", "snoozed"].contains(status ?? "open") }
    /// A finished visit's paperwork: it closes itself when the note or report exists (docs/visit-paperwork.md).
    var isVisitPaperwork: Bool { followUpType == "documentation_needed" && providerAppointmentId?.nonEmpty != nil }
    var isOverdue: Bool { isPending && RecordsText.daysUntil(dueAt) < 0 }

    var petFilter: RecordsPetFilter {
        RecordsPetFilter(id: providerClientPetId, clientId: providerClientId, name: petName?.nonEmpty ?? "—", clientName: clientName?.nonEmpty ?? "—", species: petSpecies, photoUrl: petPhotoUrl)
    }
}

/// The pet a list is narrowed to: enough to name it and open its chart.
struct RecordsPetFilter: Hashable {
    let id: String
    let clientId: String
    let name: String
    let clientName: String
    let species: String?
    let photoUrl: String?
}

/// A person on the team, as the assignee pickers and the "whose" filter read them.
struct RecordsMember: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let displayName: String?
    let email: String?
    let role: String?
    let status: String?
    let isCurrentMember: Bool?

    var plainName: String { name?.nonEmpty ?? email?.nonEmpty ?? L("Unnamed staff") }
    /// "Ana (tú)" for the reader.
    var label: String { isCurrentMember == true ? LF("%@ (You)", plainName) : plainName }
}

struct RecordsClientPet: Codable, Identifiable, Hashable {
    let id: String
    let petName: String?
    let petSpecies: String?
    let petBreed: String?
    let photoUrl: String?
    let microchipNumber: String?
    let status: String?
}

struct RecordsClient: Codable, Identifiable, Hashable {
    let id: String
    let ownerName: String?
    let ownerEmail: String?
    let ownerPhone: String?
    let householdId: String?
    let photoUrl: String?
    let petCount: Int?
    let pets: [RecordsClientPet]?
    let status: String?

    var activePets: [RecordsClientPet] { (pets ?? []).filter { $0.status != "archived" } }
}

/// The visit a record was written at (only what the record's page shows).
struct RecordsAppointment: Codable, Hashable {
    let id: String
    let serviceLabel: String?
    let status: String?
    let startsAt: String?
    let room: String?
    let assignedMember: RecordsMemberRef?
}

struct RecordsRemindResult: Decodable {
    let channel: String?
    let message: String?
    let link: String?
    let sentTo: Int?
}

/// A page of a list as this module keeps it: its rows and the server's total. (Not the shared
/// `Page`, so a page can be read in one task and used in another.)
struct RecordsChunk<Item> {
    let items: [Item]
    let total: Int?
    let hasMore: Bool?

    init(_ page: Page<Item>) where Item: Decodable {
        items = page.items
        total = page.total
        hasMore = page.hasMore
    }

}

extension RecordsChunk where Item: Decodable {
    var page: Page<Item> { Page(items: items, total: total, hasMore: hasMore) }
}

// MARK: - Endpoints

enum RecordsAPI {
    /// GET /provider-records with the web's filters (nil values are dropped).
    static func records(
        limit: Int, offset: Int,
        status: String? = nil, readyToSign: Bool = false, unfinished: Bool = false,
        search: String? = nil, recordType: String? = nil,
        member: String? = nil, unassigned: Bool = false,
        location: String? = nil, pet: String? = nil, from: String? = nil, to: String? = nil,
        appointmentId: String? = nil
    ) async throws -> RecordsChunk<RecordsRecord> {
        let page: Page<RecordsRecord> = try await API.get("/provider-records", query: [
            "limit": "\(min(limit, 100))",
            "offset": "\(offset)",
            "status": status,
            "readyToSign": readyToSign ? "true" : nil,
            "unfinished": unfinished ? "true" : nil,
            "search": search?.nonEmpty,
            "recordType": recordType,
            "assignedOrganizationMemberId": member,
            "unassigned": unassigned ? "true" : nil,
            "locationId": location,
            "providerClientPetId": pet,
            "from": from,
            "to": to,
            "appointmentId": appointmentId,
        ])
        return RecordsChunk(page)
    }

    /// GET /provider-follow-ups. `to_do` (open or reminded) falls back to `open` on an older server.
    static func followUps(
        limit: Int, offset: Int,
        status: String = "to_do", kind: String? = nil,
        search: String? = nil, recordType: String? = nil,
        member: String? = nil, unassigned: Bool = false,
        pet: String? = nil, record: String? = nil,
        dueFrom: String? = nil, dueTo: String? = nil
    ) async throws -> RecordsChunk<RecordsFollowUp> {
        func fetch(_ statusParam: String) async throws -> RecordsChunk<RecordsFollowUp> {
            let page: Page<RecordsFollowUp> =
            try await API.get("/provider-follow-ups", query: [
                "limit": "\(min(limit, 100))",
                "offset": "\(offset)",
                "status": statusParam,
                "kind": kind,
                "search": search?.nonEmpty,
                "recordType": recordType,
                "assignedOrganizationMemberId": member,
                "unassigned": unassigned ? "true" : nil,
                "providerClientPetId": pet,
                "providerRecordId": record,
                "dueFrom": dueFrom,
                "dueTo": dueTo,
            ])
            return RecordsChunk(page)
        }
        do {
            return try await fetch(status)
        } catch let error as APIError where status == "to_do" && error.status == 400 {
            return try await fetch("open")
        }
    }

    static func record(_ id: String) async throws -> RecordsRecord {
        try await API.get("/provider-records/\(id)")
    }

    static func sign(_ id: String) async throws -> RecordsRecord? {
        let data = try await API.data("POST", "/provider-records/\(id)/sign", query: [:], body: Data("{}".utf8))
        return try? API.decoder.decode(RecordsRecord.self, from: data)
    }

    static func discard(_ id: String) async throws {
        try await API.send("POST", "/provider-records/\(id)/discard")
    }

    static func update(_ id: String, body: [String: Any?]) async throws -> RecordsRecord {
        try await API.patch("/provider-records/\(id)", body: body)
    }

    static func updateFollowUp(_ id: String, body: [String: Any?]) async throws -> RecordsFollowUp {
        try await API.patch("/provider-follow-ups/\(id)", body: body)
    }

    static func remind(_ id: String, channel: String) async throws -> RecordsRemindResult {
        let locale = LocalizationManager.shared.currentLanguage == .spanish ? "es" : "en"
        return try await API.post("/provider-follow-ups/\(id)/remind", body: ["channel": channel, "locale": locale])
    }

    static func members(clinicId: String) async throws -> [RecordsMember] {
        try await API.get("/provider-workspaces/\(clinicId)/members")
    }

    static func clients(limit: Int, search: String? = nil, member: String? = nil, unassigned: Bool = false) async throws -> RecordsChunk<RecordsClient> {
        let page: Page<RecordsClient> = try await API.get("/provider-clients", query: [
            "limit": "\(min(limit, 50))",
            "offset": "0",
            "search": search?.nonEmpty,
            "assignedOrganizationMemberId": member,
            "unassigned": unassigned ? "true" : nil,
        ])
        return RecordsChunk(page)
    }

    static func client(_ id: String) async throws -> RecordsClient {
        try await API.get("/provider-clients/\(id)")
    }

    static func appointment(_ id: String) async throws -> RecordsAppointment {
        try await API.get("/provider-appointments/\(id)")
    }

    /// A record's file, signed with the session (the web reads it through its cookie).
    static func fileData(_ url: String) async throws -> Data {
        if url.hasPrefix("http") {
            guard let absolute = URL(string: url) else { throw APIError.offline() }
            var request = URLRequest(url: absolute)
            if let token = SessionToken.current { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            let (data, response) = try await APIConfig.urlSession.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw API.errorFrom(data: data, status: http.statusCode)
            }
            return data
        }
        let path = url.hasPrefix("/api/") ? String(url.dropFirst(4)) : url
        return try await API.data("GET", path, query: [:], body: nil)
    }
}

/// A saved JSON value as the plain value JSONSerialization sends back (an unknown payload entry kept on save).
func recordsPlainValue(_ value: JSONValue) -> Any? {
    switch value {
    case .string(let v): return v
    case .number(let v): return v
    case .bool(let v): return v
    case .null: return nil
    case .array(let v): return v.map { recordsPlainValue($0) }
    case .object(let v): return v.mapValues { recordsPlainValue($0) }
    }
}

/// A request started now, on the main actor, and read later: several run at once
/// without leaving the main actor (the shapes here decode on it).
func recordsStart<T: Sendable>(_ run: Bool = true, _ work: @escaping @MainActor () async throws -> T) -> Task<T?, Never> {
    Task { run ? try? await work() : nil }
}
