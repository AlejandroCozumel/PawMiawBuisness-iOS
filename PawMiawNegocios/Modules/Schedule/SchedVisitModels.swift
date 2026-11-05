//
//  SchedVisitModels.swift
//  PawMiawNegocios
//
//  What the visit page's side cards read (web: hospital/visit-triage-card,
//  visits/visit-chart, consents, incidents, visit-updates-card,
//  care/groom-request-staff): the triage, the chart in short, the consents,
//  the incidents, the notes to the family, the owner's grooming request, the
//  pet's open hospitalization — and the multipart and photo helpers their
//  forms use. Every field that can be missing is Optional.
//

import Foundation
import UIKit

// MARK: - Triage (`/provider-visits/{id}/triage`)

struct SchedVitals: Codable, Hashable {
    let id: String?
    let recordedAt: String?
    let temperatureC: Double?
    let heartRate: Double?
    let respiratoryRate: Double?
    let painScore: Double?
    let weightGrams: Double?
    let mucousMembranes: String?
    let crtSeconds: Double?
}

struct SchedDepositDue: Codable, Hashable {
    let amount: Int?
    let paid: Int?
    let currency: String?

    var owed: Int { max(0, (amount ?? 0) - (paid ?? 0)) }
}

struct SchedTriage: Codable, Hashable {
    let appointmentId: String?
    let triagePriority: String?
    let triageReason: String?
    let triagedAt: String?
    let afterHours: Bool?
    let vitals: [SchedVitals]?
    let depositDue: SchedDepositDue?

    var isEmpty: Bool { triagePriority == nil && afterHours != true && (vitals ?? []).isEmpty }
}

/// A pet's hospitalizations (`/provider-hospital/hospitalizations?providerClientPetId=`).
struct SchedHospStay: Decodable, Hashable {
    let id: String
    let status: String?

    var open: Bool { status == "admitted" || status == "pending" }
}

struct SchedHospStays: Decodable { let hospitalizations: [SchedHospStay]? }

/// What the admission answers (only what the visit page reads).
struct SchedAdmitted: Decodable {
    struct Patient: Decodable { let name: String? }
    struct Client: Decodable { let onPawMiaw: Bool? }
    struct Refusal: Decodable { let code: String?; let error: String? }
    struct Asked: Decodable { let consentId: String? }
    let id: String
    let status: String?
    let patient: Patient?
    let client: Client?
    let admitError: Refusal?
    let consentError: String?
    let consentRequest: Asked?
}

// MARK: - The chart in short (`/provider-client-pets/{id}/chart-summary`)

struct SchedChartRecord: Codable, Hashable, Identifiable {
    let id: String
    let appointmentId: String?
    let recordType: String?
    let title: String?
    let summary: String?
    let eventAt: String?
    let followUpAt: String?
    let payload: JSONValue?

    func text(_ key: String) -> String? { payload?[key]?.string?.nonEmpty }
}

struct SchedChartSummary: Decodable {
    struct Access: Decodable { let canView: Bool? }
    struct Highlights: Decodable { let latestWeight: SchedChartRecord? }
    struct Sections: Decodable {
        let currentProblems: [SchedChartRecord]?
        let currentMedications: [SchedChartRecord]?
        let allergies: [SchedChartRecord]?
        let vaccines: [SchedChartRecord]?
        let recentRecords: [SchedChartRecord]?
        let ownerRecords: [SchedChartRecord]?
    }
    let sharedHistoryAccess: Access?
    let highlights: Highlights?
    let sections: Sections?
}

// MARK: - Notes to the family (`/provider-appointments/{id}/updates`)

struct SchedVisitUpdate: Codable, Hashable, Identifiable {
    let id: String
    let message: String?
    let mood: String?
    let photoUrl: String?
    let authorName: String?
    let createdAt: String?
}

// MARK: - The owner's grooming request (`/provider-appointments/{id}/groom-request`)

/// What is sent (PUT, and `groomRequests[]` on a booking).
struct SchedGroomInput: Equatable {
    var sameAsLastTime = false
    var services: [String] = []
    var style: String?
    var styleText = ""
    var length = ""
    var areas: [String] = []
    var photoUrls: [String] = []
    var note = ""
    var extrasUpToCents: Int?
    var extras: [String] = []
    var pickupMinute: Int?

    var isEmpty: Bool {
        !sameAsLastTime && services.isEmpty && style == nil && styleText.nonEmpty == nil && length.nonEmpty == nil
            && areas.isEmpty && photoUrls.isEmpty && note.nonEmpty == nil && (extrasUpToCents ?? 0) <= 0 && extras.isEmpty && pickupMinute == nil
    }

    var pickupTime: String? { pickupMinute.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) } }

    /// A clean body: trimmed text, nulls for blanks.
    var body: [String: Any?] {
        [
            "sameAsLastTime": sameAsLastTime,
            "services": services,
            "style": style,
            "styleText": styleText.nonEmpty,
            "length": length.nonEmpty,
            "areas": areas,
            "photoUrls": photoUrls,
            "note": note.nonEmpty,
            "extrasUpToCents": (extrasUpToCents ?? 0) > 0 ? extrasUpToCents : nil,
            "extras": extras,
            "pickupTime": pickupTime,
        ]
    }

    static func empty(_ last: SchedGroomLastTime?) -> SchedGroomInput {
        var input = SchedGroomInput()
        input.sameAsLastTime = last?.exists ?? false
        return input
    }

    static func from(_ request: SchedGroomRequest?, last: SchedGroomLastTime?) -> SchedGroomInput {
        guard let request else { return empty(last) }
        var input = SchedGroomInput()
        input.sameAsLastTime = request.sameAsLastTime ?? false
        input.services = request.services ?? []
        input.style = request.style
        input.styleText = request.styleText ?? ""
        input.length = request.length ?? ""
        input.areas = request.areas ?? []
        input.photoUrls = request.photoUrls ?? []
        input.note = request.note ?? ""
        input.extrasUpToCents = request.extrasUpToCents
        input.extras = request.extras ?? []
        input.pickupMinute = request.pickupTime.flatMap { SchedHours.startMinutes($0) }
        return input
    }
}

struct SchedGroomLastTime: Codable, Hashable {
    let appointmentId: String?
    let at: String?
    let services: [String]?
    let style: String?
    let styleText: String?
    let length: String?
    let careStyle: String?
    let careTools: String?

    var exists: Bool { appointmentId != nil || careStyle?.nonEmpty != nil || careTools?.nonEmpty != nil }
}

struct SchedGroomStamp: Codable, Hashable {
    let side: String?
    let name: String?
    let at: String?
}

struct SchedGroomRequest: Codable, Hashable {
    let sameAsLastTime: Bool?
    let services: [String]?
    let style: String?
    let styleText: String?
    let length: String?
    let areas: [String]?
    let photoUrls: [String]?
    let note: String?
    let extrasUpToCents: Int?
    let extras: [String]?
    let pickupTime: String?
    let setBy: SchedGroomStamp?
    let checkIn: SchedGroomStamp?
}

struct SchedGroomWanted: Codable, Hashable {
    let services: [String]?
    let style: String?
    let styleText: String?
    let length: String?
}

struct SchedGroomExtras: Codable, Hashable {
    let authorizedCents: Int?
    let chargedCents: Int?
    let status: String?
    let overByCents: Int?
    let currency: String?
}

struct SchedGroomView: Decodable {
    let appointmentId: String
    let isGroom: Bool?
    let request: SchedGroomRequest?
    let wanted: SchedGroomWanted?
    let lastTime: SchedGroomLastTime?
    let prefill: SvcReport?
    let extras: SchedGroomExtras?
    let staffMayEdit: Bool?
}

/// The care card's part the booking reads: "same as last time" and the currency.
struct SchedCareForGroom: Decodable {
    let lastGroom: SchedGroomLastTime?
    let currency: String?
}

