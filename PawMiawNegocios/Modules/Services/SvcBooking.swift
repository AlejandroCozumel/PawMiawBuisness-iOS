//
//  SvcBooking.swift
//  PawMiawNegocios
//
//  The catalog of services as the three pages use it (web:
//  hooks/use-appointment-service-catalog.ts, the Catalog's priced services),
//  and what "New groom", "New visit" and "Book" hand to the Agenda's booking
//  (`ProviderRoute.bookVisit`), filled in with what the screen knows.
//

import Foundation

struct SvcCatalogBilling: Codable, Hashable {
    let id: String?
    let name: String?
    let currency: String?
    let defaultUnitAmount: Int?
    let active: Bool?
}

/// One service a business can book (`/appointment-services`).
struct SvcCatalogService: Codable, Hashable, Identifiable {
    let id: String
    let category: String
    let label: String
    let description: String?
    let defaultDurationMinutes: JSONValue?
    let defaultBillingItem: SvcCatalogBilling?

    var minutes: Int? { defaultDurationMinutes?.double.map { Int($0) }.flatMap { $0 > 0 ? $0 : nil } }
}

private struct SvcCatalogAnswer: Decodable { let services: [SvcCatalogService]? }

/// A priced Catalog service (`/provider-catalog?itemType=service`): a session named like it charges its price.
struct SvcPricedService: Decodable, Hashable {
    let name: String
    let defaultUnitAmount: Int?
}

@MainActor
enum SvcServices {
    private static var lists: [String: (at: Date, services: [SvcCatalogService])] = [:]

    /// The business's services (`provider`) or every one there is (`all`), kept 15 minutes as the web does.
    @discardableResult
    static func load(_ scope: String) async -> [SvcCatalogService] {
        if let kept = lists[scope], Date().timeIntervalSince(kept.at) < 15 * 60 { return kept.services }
        let answer: SvcCatalogAnswer? = try? await API.get("/appointment-services", query: ["scope": scope == "provider" ? "provider" : nil])
        guard let services = answer?.services else { return lists[scope]?.services ?? [] }
        lists[scope] = (Date(), services)
        return services
    }

    static func cached(_ scope: String) -> [SvcCatalogService] { lists[scope]?.services ?? [] }

    /// The business's service of a kind to book: the one named like the last visit's, else its first.
    /// Group walks and classes are planned as sessions, never booked one by one.
    static func pick(category: String?, label: String? = nil) -> String? {
        guard let category else { return nil }
        let own = cached("provider").filter { $0.category == category && !["group_walk", "group_class"].contains($0.id) }
        if let label = label?.trimmingCharacters(in: .whitespaces).lowercased(), !label.isEmpty,
           let named = own.first(where: { $0.label.lowercased() == label }) {
            return named.id
        }
        return own.first?.id
    }
}

enum SvcBook {
    /// The kind of visit a home-visit business books: walks first, then sitting.
    @MainActor
    static func homeCategory(_ workspace: Workspace) -> String? {
        workspace.offers(.walker) ? "walker" : workspace.offers(.sitter) ? "sitter" : nil
    }

    /// A groom for a pet (or for nobody yet), on its last service when the catalog has it.
    @MainActor
    static func groom(clientId: String? = nil, petId: String? = nil, lastService: String? = nil, day: String? = nil, followUpId: String? = nil) -> ProviderRoute {
        .bookVisit(BookingPrefill(clientId: clientId, petId: petId, serviceId: SvcServices.pick(category: "groomer", label: lastService), day: day, followUpId: followUpId))
    }
}

// MARK: - Online booking at this place

private struct SvcOnlineAvailability: Decodable { let allowOnlineBooking: Bool? }
private struct SvcOnlineLocation: Decodable { let id: String; let availability: SvcOnlineAvailability? }
private struct SvcOnlineLocations: Decodable { let locations: [SvcOnlineLocation]? }
private struct SvcOnlineWorkspace: Decodable { let availability: SvcOnlineAvailability? }

/// Whether families can book online at this place (Disponibilidad); nil when it couldn't be read.
@MainActor
func svcLocationTakesOnlineBookings(_ locationId: String?) async -> Bool? {
    if let locationId, Workspace.shared.multiLocation {
        let answer: SvcOnlineLocations? = try? await API.get("/provider-locations", query: ["includeArchived": "true"])
        if let found = answer?.locations?.first(where: { $0.id == locationId }) { return found.availability?.allowOnlineBooking ?? false }
    }
    let active: SvcOnlineWorkspace? = try? await API.get("/provider-workspaces/active")
    return active?.availability?.allowOnlineBooking
}
