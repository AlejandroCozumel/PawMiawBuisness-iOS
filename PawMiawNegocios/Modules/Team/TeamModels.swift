//
//  TeamModels.swift
//  PawMiawNegocios
//
//  The shapes the Team module reads and writes, mirroring the web's hooks:
//  members and invitations (use-provider-workspaces.ts), what each role can
//  do (use-provider-staff.ts), opening hours, closed dates and each person's
//  hours (use-provider-hours.ts, lib/provider-availability.ts), online
//  booking (use-provider-online-booking.ts), the business's setup and store
//  settings, notification preferences, and the account's sessions and
//  password. Every field that can be missing is optional.
//

import Foundation

// MARK: - Team

struct TeamMember: Codable, Identifiable, Hashable {
    let id: String
    let userId: String?
    let name: String?
    let userName: String?
    let email: String?
    let image: String?
    let displayName: String?
    let professionalTitle: String?
    let specialty: String?
    let credentialLabel: String?
    let credentialValue: String?
    let profileNotes: String?
    let maxConcurrentVisits: Int?
    let locationIds: [String]?
    let role: String?
    let permissionAllow: [String]?
    let permissionDeny: [String]?
    let effectivePermissions: [String]?
    let createdAt: String?
    let isCurrentMember: Bool?
    let status: String?
    let suspendedAt: String?
    let lastActiveAt: String?
    let overSeatLimit: Bool?

    var roleKey: String { role ?? "" }
    var allow: [String] { permissionAllow ?? [] }
    var deny: [String] { permissionDeny ?? [] }
    var effective: [String] { effectivePermissions ?? [] }
    var isMe: Bool { isCurrentMember ?? false }
    var atOnce: Int { max(1, maxConcurrentVisits ?? 1) }

    /// The name shown: the one set for the team, the account's, else the email.
    var shownName: String {
        displayName.nonEmpty ?? name.nonEmpty ?? userName.nonEmpty ?? email.nonEmpty ?? L("Unnamed")
    }

    /// "Veterinarian · Dermatology".
    var titleLine: String {
        [professionalTitle.nonEmpty, specialty.nonEmpty].compactMap { $0 }.joined(separator: " · ")
    }

    /// Starts and finishes visits (the Schedule gives them a column).
    var takesVisits: Bool { effective.contains(Permission.appointmentsComplete.rawValue) }
    var isSuspended: Bool { status == "suspended" }
    var hasCustomAccess: Bool { roleKey != "owner" && (!allow.isEmpty || !deny.isEmpty) }
}

struct TeamInvitation: Codable, Identifiable, Hashable {
    let id: String
    let inviteeName: String?
    let email: String
    let role: String?
    let status: String?
    let inviterName: String?
    let expiresAt: String?
    let locationIds: [String]?
}

/// An invitation still worth showing: waiting, or run out.
struct TeamOpenInvitation: Identifiable, Hashable {
    let invitation: TeamInvitation
    let expired: Bool
    var id: String { invitation.id }
    var shownName: String { invitation.inviteeName.nonEmpty ?? invitation.email }
}

struct TeamRolePermissions: Codable, Hashable {
    let role: String
    let permissions: [String]
}

struct TeamRolesResponse: Codable {
    let roles: [TeamRolePermissions]
}

// MARK: - Hours

struct TeamTimeRange: Codable, Hashable {
    var start: String
    var end: String
}

/// One weekday: open or closed, with one or more ranges.
struct TeamDay: Codable, Hashable {
    var day: String
    var enabled: Bool
    var startTime: String?
    var endTime: String?
    var ranges: [TeamTimeRange]?

    init(day: String, enabled: Bool, startTime: String?, endTime: String?, ranges: [TeamTimeRange]?) {
        self.day = day
        self.enabled = enabled
        self.startTime = startTime
        self.endTime = endTime
        self.ranges = ranges
    }

    private enum Keys: String, CodingKey { case day, enabled, startTime, endTime, ranges }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        day = (try? c.decode(String.self, forKey: .day)) ?? "monday"
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? false
        startTime = try? c.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try? c.decodeIfPresent(String.self, forKey: .endTime)
        ranges = try? c.decodeIfPresent([TeamTimeRange].self, forKey: .ranges)
    }
}

/// A location's hours and booking rules (`/provider-workspaces/:id/availability`).
struct TeamAvailability: Decodable {
    let timezone: String?
    let defaultAppointmentDurationMinutes: Int?
    let allowAfterHoursBooking: Bool?
    let allowOnlineBooking: Bool?
    let requestAppointmentConfirmationByDefault: Bool?
    let defaultBufferMinutes: Int?
    let minBookingNoticeMinutes: Int?
    let bookingHorizonDays: Int?
    let onlineConfirmMode: String?
    let weeklySchedule: [TeamDay]?
}

struct TeamClosure: Codable, Identifiable, Hashable {
    let id: String
    let locationId: String?
    let startDay: String
    let endDay: String
    let label: String?
    /// nil = closed all day; else the special hours of those dates.
    let ranges: [TeamTimeRange]?
    let repeatsYearly: Bool?
    let nextStartDay: String?
    let nextEndDay: String?
    let createdAt: String?
}

struct TeamClosuresResponse: Decodable {
    let locationId: String?
    let closures: [TeamClosure]
}

/// What is already booked on some days (nothing is cancelled).
struct TeamBookedThen: Decodable {
    let visits: Int?
    let firstDay: String?
    let stays: Int?
}

struct TeamClosureSaved: Decodable {
    let closure: TeamClosure
    let visits: Int?
    let firstDay: String?
    let stays: Int?
}

struct TeamHoursConflicts: Decodable {
    struct Covered: Decodable, Hashable {
        let id: String
        let startDay: String
        let endDay: String
        let label: String?
        let closed: Bool?
    }
    let visits: Int?
    let firstDay: String?
    let stays: Int?
    let covered: [Covered]?
}

struct TeamTimeOff: Codable, Identifiable, Hashable {
    let id: String
    let memberId: String?
    let startDay: String
    let endDay: String
    let reason: String?
    let createdAt: String?
}

struct TeamTimeOffSaved: Decodable {
    let timeOff: TeamTimeOff
    let visits: Int?
}

struct TeamMemberLocationHours: Codable, Hashable {
    let locationId: String
    let name: String?
    let isPrimary: Bool?
    let timezone: String?
    let usesLocationHours: Bool?
    let weeklySchedule: [TeamDay]?
    let locationWeeklySchedule: [TeamDay]?
}

struct TeamMemberHours: Codable, Hashable {
    let memberId: String
    let locations: [TeamMemberLocationHours]?
    let timeOff: [TeamTimeOff]?
}

// MARK: - Online booking

struct TeamOnlineLocation: Decodable, Hashable {
    let id: String
    let name: String?
    let isPrimary: Bool?
    let status: String?
    let allowOnlineBooking: Bool?
    let onlineConfirmMode: String?
    let pendingRequests: Int?
}

struct TeamOnlineService: Decodable, Hashable {
    let serviceId: String
    let label: String
    let category: String?
    let durationMinutes: Int?
    let onlineBookable: Bool?
}

struct TeamOnlineMember: Decodable, Hashable {
    let memberId: String
    let name: String?
    let role: String?
    let suspended: Bool?
    let doesVisits: Bool?
    /// Their own switch; nil = what their role says (`roleDefault`).
    let takesOnlineBookings: Bool?
    let roleDefault: Bool?
    /// Families are offered this person now.
    let offered: Bool?
    /// "Servicios que hace"; [] = every bookable service their role can do.
    let serviceIds: [String]?
    let signsRecords: Bool?
}

struct TeamOnlineSettings: Decodable {
    let locations: [TeamOnlineLocation]?
    /// The store policy's value; nil = not set (families read 24 h).
    let lateCancelWindowHours: Int?
    let familyCancelWindowHours: Int?
    let services: [TeamOnlineService]?
    let team: [TeamOnlineMember]?
    let ready: Bool?
}

// MARK: - Visits (a person's "Coming up")

struct TeamVisit: Decodable, Identifiable, Hashable {
    let id: String
    let petName: String?
    let serviceLabel: String?
    let clientName: String?
    let startsAt: String?
    let status: String?
}

// MARK: - Business setup and settings

struct TeamSetupService: Decodable, Hashable {
    let serviceId: String
    let category: String?
    let defaultDurationMinutes: Int?
    let offered: Bool?
    let suggested: Bool?
    let durationMinutes: Int?
}

struct TeamSetupState: Decodable {
    struct Business: Decodable {
        let name: String?
        let email: String?
        let phone: String?
        let logoUrl: String?
        let enabledCategories: [String]?
        let services: [TeamSetupService]?
    }
    struct Region: Decodable {
        let country: String?
        let currency: String?
        let currencyLocked: Bool?
        let defaultTaxRateBps: Int?
        let pricesIncludeTax: Bool?
        let clientLanguage: String?
    }
    struct Legal: Decodable {
        let legalName: String?
        let taxId: String?
        let taxRegime: String?
        let receiptLogoUrl: String?
    }
    let canEdit: Bool?
    let canEditRegion: Bool?
    let business: Business?
    let region: Region?
    let legal: Legal?
    let senasicaRegistration: String?
}

/// `/appointment-services`: the kinds of care and their services.
struct TeamServiceCatalog: Decodable {
    struct Category: Decodable, Hashable {
        let id: String
        let label: String?
        let description: String?
    }
    struct Service: Decodable, Hashable {
        let id: String
        let category: String
        let label: String
        let description: String?
        let defaultDurationMinutes: JSONValue?

        var defaultMinutes: Int { defaultDurationMinutes?.int ?? 30 }
    }
    let categories: [Category]?
    let services: [Service]?
}

/// The store's settings (`/provider-store/settings`), kept whole so a save sends back what it
/// did not change. The one model Home's setup sheets and Team's Settings read and save.
struct TeamStoreSettings {
    var raw: [String: JSONValue]

    static func load() async throws -> TeamStoreSettings {
        let raw: [String: JSONValue] = try await API.get("/provider-store/settings")
        return TeamStoreSettings(raw: raw)
    }

    /// Sends the settings whole with `changes` over them (nil clears a value): the receipt line,
    /// fees and everything else the Store saves stay as they are.
    func save(_ changes: [String: JSONValue?], announce: Bool = true) async throws {
        var next = raw
        next["currencyLocked"] = nil
        next["currencyLockedReason"] = nil
        for (key, value) in changes { next[key] = value ?? .null }
        let _: EmptyResponse = try await API.put("/provider-store/settings", json: next)
        if announce { announceDataChanged() }
    }

    /// Cents as the settings carry them (null for none).
    static func cents(_ value: Int?) -> JSONValue { value.map { .number(Double($0)) } ?? .null }

    var currency: String { raw["currency"]?.string ?? Workspace.shared.currency }
    var currencyLocked: Bool { raw["currencyLocked"]?.bool ?? false }
    var defaultTaxRateBps: Int { raw["defaultTaxRateBps"]?.int ?? 0 }
    var pricesIncludeTax: Bool { raw["pricesIncludeTax"]?.bool ?? false }
    var cashDifferenceAlertAmount: Int? {
        guard let value = raw["cashDifferenceAlertAmount"], !value.isNull else { return nil }
        return value.int
    }
}

// MARK: - Notifications

struct TeamNotificationPreference: Decodable, Hashable {
    let category: String
    let inAppEnabled: Bool?
    let emailEnabled: Bool?
    let emailLocked: Bool?
    let pushEnabled: Bool?
    let timezone: String?
    let reminderLeadTimes: [Int]?
}

struct TeamNotificationChannel: Decodable, Hashable {
    let key: String
    let label: String?
    let availableNow: Bool?
}

struct TeamNotificationPreferences: Decodable {
    let items: [TeamNotificationPreference]?
    let channels: [TeamNotificationChannel]?
}

struct TeamMarketingEmail: Decodable {
    let enabled: Bool?
}

// MARK: - Account

struct TeamUserProfile: Decodable {
    let id: String?
    let name: String?
    let email: String?
    let phone: String?
    let image: String?
}

struct TeamUserSession: Decodable, Identifiable, Hashable {
    let id: String
    let deviceLabel: String?
    let browserLabel: String?
    let platformLabel: String?
    let ipAddress: String?
    let locationLabel: String?
    let createdAt: String?
    let lastActiveAt: String?
    let expiresAt: String?
    let isCurrent: Bool?
}

struct TeamSessionsResponse: Decodable {
    let sessions: [TeamUserSession]
}

struct TeamPasswordStatus: Decodable {
    let hasPassword: Bool?
    let socialProviders: [String]?
}

struct TeamPasswordResult: Decodable {
    let created: Bool?
    let otherSessionsSignedOut: Int?
}

struct TeamPasswordCodeSent: Decodable {
    let email: String?
}
