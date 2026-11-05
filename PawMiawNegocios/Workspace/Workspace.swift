//
//  Workspace.swift
//  PawMiawNegocios
//
//  The business this person is working in, the place ("sede") this device
//  works at, and what the person may do there. One object for the whole app:
//  screens read `@EnvironmentObject var workspace: Workspace`, and code that
//  isn't a view reads `Workspace.shared`.
//
//  Locations follow the web (hooks/use-provider-locations.ts): each business
//  remembers the place chosen on this device; with one active place nothing
//  is sent (`locationId == nil`); owners and admins with two or more may
//  choose "Todas las sedes", and then pages that belong to one place ask
//  which one first (`RequireLocation`).
//

import Foundation
import SwiftUI

struct WorkspaceAvailability: Codable, Hashable {
    let timezone: String?
}

struct ProviderWorkspace: Codable, Identifiable, Hashable {
    let clinicId: String
    let organizationId: String
    let name: String
    let slug: String?
    let email: String?
    let phone: String?
    let address: String?
    let availability: WorkspaceAvailability?
    let enabledCategories: [String]
    let status: String?
    let role: String?
    let plan: String?
    let billingStatus: String?
    let billingProvider: String?
    let seatLimit: Int?
    let locationLimit: Int?
    let trialEndsAt: String?
    let currentPeriodEndsAt: String?
    let isActive: Bool?
    let effectivePermissions: [String]
    let canManagePlan: Bool?
    let logoUrl: String?
    let setupCompletedAt: String?
    let needsRegionConfirmation: Bool?
    let country: String?
    let clientLanguage: String?
    let offersHomeVisits: Bool?

    var id: String { clinicId }
}

struct ProviderLocation: Codable, Identifiable, Hashable {
    let id: String
    let clinicId: String?
    let name: String
    let isPrimary: Bool
    let status: String
    let sortOrder: Int?
    let timezone: String?
    let address: String?
    let phone: String?
    let email: String?
    let photoUrl: String?
    let availability: WorkspaceAvailability?
}

struct LocationPlan: Codable, Hashable {
    let allowsMultiple: Bool?
    let requiredPlan: String?
    let plan: String?
    let limit: Int?
    let used: Int?
    let paused: Int?
    let canAdd: Bool?
    let reason: String?
    let addonAvailable: Bool?
    let talkToSales: Bool?
}

struct ProviderLocationsResponse: Codable {
    let locations: [ProviderLocation]
    let memberLocationIds: [String]?
    let openShiftLocationIds: [String]?
    let plan: LocationPlan?
}

private struct StoreSettingsCurrency: Decodable { let currency: String? }

@MainActor
final class Workspace: ObservableObject {
    static let shared = Workspace()

    enum Phase: Equatable { case idle, loading, none, choosing, ready, failed(String) }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var workspaces: [ProviderWorkspace] = []
    @Published private(set) var current: ProviderWorkspace?
    @Published private(set) var locationsResponse: ProviderLocationsResponse?
    @Published private(set) var storedLocationId: String?
    @Published private(set) var currency: String = "MXN"
    /// Bumped whenever the business or the place changes: screens reload on it.
    @Published private(set) var scopeVersion = 0

    static let allLocations = "all"

    // MARK: Permissions

    private var permissionSet: Set<String> { Set(current?.effectivePermissions ?? []) }

    func can(_ permission: Permission) -> Bool { permissionSet.contains(permission.rawValue) }
    func canAll(_ permissions: Permission...) -> Bool { permissions.allSatisfy(can) }
    func canAny(_ permissions: Permission...) -> Bool { permissions.contains(where: can) }

    var moneyLevel: MoneyLevel { MoneyLevel.of(permissionSet) }
    var role: WorkspaceRole? { current?.role.flatMap(WorkspaceRole.init(rawValue:)) }
    var isOwnerOrAdmin: Bool { role == .owner || role == .admin }

    func offers(_ categories: BusinessCategory...) -> Bool {
        let enabled = Set(current?.enabledCategories ?? [])
        return categories.contains { enabled.contains($0.rawValue) }
    }

    var offersHomeVisits: Bool { current?.offersHomeVisits ?? false }
    /// Setup essentials not finished: the server refuses money, invitations and bookings.
    var inSetup: Bool { current != nil && current?.setupCompletedAt == nil }

    // MARK: Locations

    var allLocations: [ProviderLocation] { locationsResponse?.locations ?? [] }

    var activeLocations: [ProviderLocation] {
        Self.sorted(allLocations.filter { $0.status == "active" })
    }

    /// Active places this member may choose from, primary first.
    var memberLocations: [ProviderLocation] {
        let active = activeLocations
        guard let ids = locationsResponse?.memberLocationIds, !ids.isEmpty else { return active }
        let theirs = active.filter { ids.contains($0.id) }
        return theirs.isEmpty ? active : theirs
    }

    /// The business has two or more active places.
    var multiLocation: Bool { activeLocations.count >= 2 }
    var canSeeAllLocations: Bool { multiLocation && isOwnerOrAdmin }
    /// "Todas las sedes" is chosen.
    var allLocationsChosen: Bool { canSeeAllLocations && storedLocationId == Self.allLocations }
    var canSwitchLocation: Bool { memberLocations.count >= 2 || canSeeAllLocations }

    var selectedLocation: ProviderLocation? {
        if let id = storedLocationId, id != Self.allLocations, let found = memberLocations.first(where: { $0.id == id }) { return found }
        return memberLocations.first
    }

    /// What location-scoped requests send: nil with one place, or with "Todas las sedes".
    var locationId: String? {
        if allLocationsChosen { return nil }
        return multiLocation ? selectedLocation?.id : nil
    }

    /// A business-wide list's filter value: the place, "all", or nothing with one place.
    var listLocationFilter: String? {
        guard multiLocation else { return nil }
        return allLocationsChosen ? Self.allLocations : selectedLocation?.id
    }

    /// The business's clock: the place's, else the workspace's.
    var timeZone: TimeZone {
        let id = (multiLocation ? (selectedLocation?.timezone ?? selectedLocation?.availability?.timezone) : nil)
            ?? current?.availability?.timezone
        return id.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    func setLocation(_ id: String) {
        storedLocationId = id
        if let clinic = current?.clinicId { UserDefaults.standard.set(id, forKey: Self.locationKey(clinic)) }
        scopeVersion += 1
    }

    func setAllLocations() { setLocation(Self.allLocations) }

    private static func locationKey(_ clinicId: String) -> String { "pawmiaw_negocios_location_\(clinicId)" }

    static func sorted(_ locations: [ProviderLocation]) -> [ProviderLocation] {
        locations.sorted { a, b in
            if a.isPrimary != b.isPrimary { return a.isPrimary }
            if (a.sortOrder ?? 0) != (b.sortOrder ?? 0) { return (a.sortOrder ?? 0) < (b.sortOrder ?? 0) }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    // MARK: Loading

    func load() async {
        if current == nil { phase = .loading }
        do {
            let list: [ProviderWorkspace] = try await API.get("/provider-workspaces")
            let active: ProviderWorkspace? = try? await API.get("/provider-workspaces/active")
            workspaces = list
            let resolved = active ?? list.first(where: { $0.isActive == true }) ?? (list.count == 1 ? list[0] : nil)
            if list.isEmpty {
                current = nil
                phase = .none
            } else if let resolved {
                await enter(resolved)
            } else {
                phase = .choosing
            }
        } catch {
            phase = current == nil ? .failed(errorText(error)) : .ready
        }
    }

    /// Re-reads the current business (permissions, plan) without leaving the screen.
    func refresh() async {
        guard let id = current?.clinicId else { return }
        if let list: [ProviderWorkspace] = try? await API.get("/provider-workspaces") {
            workspaces = list
            if let updated = list.first(where: { $0.clinicId == id }) { current = updated }
        }
        await loadLocations()
    }

    func choose(_ workspace: ProviderWorkspace) async {
        phase = .loading
        do {
            let active: ProviderWorkspace? = try await API.post("/provider-workspaces/active", body: ["clinicId": workspace.clinicId, "organizationId": workspace.organizationId])
            await enter(active ?? workspace)
        } catch {
            phase = .failed(errorText(error))
        }
    }

    func leaveToChooser() {
        phase = workspaces.isEmpty ? .none : .choosing
    }

    private func enter(_ workspace: ProviderWorkspace) async {
        current = workspace
        storedLocationId = UserDefaults.standard.string(forKey: Self.locationKey(workspace.clinicId))
        await loadLocations()
        if let settings: StoreSettingsCurrency = try? await API.get("/provider-store/settings"), let code = settings.currency?.nonEmpty {
            currency = code
        }
        scopeVersion += 1
        phase = .ready
    }

    private func loadLocations() async {
        locationsResponse = try? await API.get("/provider-locations", query: ["includeArchived": "true"])
    }

    func reset() {
        workspaces = []
        current = nil
        locationsResponse = nil
        storedLocationId = nil
        phase = .idle
    }
}
