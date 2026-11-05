//
//  PlacesSwitcher.swift
//  PawMiawNegocios
//
//  The place switcher's whole menu (web locations/workspace-switcher.tsx), as
//  a drop-in for the shell's `LocationMenu`: the business's locations — with
//  one, that location as the current place; with several, "All locations"
//  for owners and admins, each location (paused ones shown but not chosen,
//  "Register open" while a register is open there) and "To relocate (n)" —
//  then "Add a location" for owners and admins (or what the plan asks for
//  instead: an extra location, the Business plan, or talk to us), "See
//  locations" and "Business settings" for whoever the sidebar lets into those
//  pages, and the other businesses this person belongs to.
//
//  The pages it opens go through `onOpen` when the host navigates itself (the
//  shell pushes `PlacesSwitcherDestination.route` or shows `.view`);
//  without one they open in a sheet with their own navigation.
//

import SwiftUI

/// Where the switcher takes someone.
enum PlacesSwitcherDestination: Identifiable, Hashable {
    /// Locations, opened on its "add a location" sheet (or the plan's message).
    case addLocation
    case locations
    case settings
    case relocate

    var id: Self { self }

    /// The route for a host that pushes routes (adding a location has none: use `view`).
    var route: ProviderRoute {
        switch self {
        case .addLocation, .locations: .section(.locations)
        case .settings: .section(.settings)
        case .relocate: .section(.relocate)
        }
    }

    /// The screen itself.
    @ViewBuilder
    var view: some View {
        switch self {
        case .addLocation: LocationsScreen(add: true)
        case .locations: LocationsScreen()
        case .settings: SettingsScreen()
        case .relocate: RelocateScreen()
        }
    }
}

struct PlacesSwitcherMenu: View {
    /// The host opens the page; nil = the switcher opens it in a sheet.
    var onOpen: ((PlacesSwitcherDestination) -> Void)? = nil
    /// The sidebar's header (web workspace-switcher): the business's mark, its name, the place.
    var sidebar: Bool = false

    @EnvironmentObject private var workspace: Workspace
    @State private var toRelocate = 0
    @State private var opened: PlacesSwitcherDestination?

    private var name: String { workspace.current?.name.trimmingCharacters(in: .whitespaces).nonEmpty ?? L("Provider workspace") }
    private var others: [ProviderWorkspace] { workspace.workspaces.filter { $0.clinicId != workspace.current?.clinicId } }
    /// Owners and admins who edit the business add locations, whatever how many it has today.
    private var canAddLocations: Bool { workspace.can(.workspaceEdit) && workspace.isOwnerOrAdmin }
    private var canRelocate: Bool { workspace.canSeeAllLocations && workspace.can(.appointmentsView) }
    /// The pages the sidebar lets this person into.
    private var showsLocations: Bool { ProviderSection.locations.isVisible(in: workspace, olfatoShown: false, pharmacyShown: false) }
    private var showsSettings: Bool { ProviderSection.settings.isVisible(in: workspace, olfatoShown: false, pharmacyShown: false) }
    /// Owners and admins see every open (and paused) place; everyone else theirs.
    private var choices: [ProviderLocation] {
        workspace.canSeeAllLocations
            ? Workspace.sorted(workspace.allLocations.filter { $0.status == "active" || $0.status == "paused" })
            : workspace.memberLocations
    }
    /// A real choice of place: several, and this person may move between them.
    private var chooser: Bool { workspace.multiLocation && workspace.canSwitchLocation }
    private var current: ProviderLocation? { workspace.allLocationsChosen ? nil : workspace.selectedLocation }
    private var placeLabel: String? { workspace.allLocationsChosen ? L("All locations") : current?.name }
    private var openShift: Set<String> { Set(workspace.locationsResponse?.openShiftLocationIds ?? []) }
    private var actionable: Bool { chooser || canAddLocations || showsLocations || showsSettings || !others.isEmpty }

    var body: some View {
        Group {
            if sidebar {
                if actionable { Menu { menu } label: { sidebarFace(chevron: true) } } else { sidebarFace(chevron: false) }
            } else if actionable {
                Menu { menu } label: { face(chevron: true) }
                    .accessibilityLabel(LF("%@. Change location or workspace", placeLabel.map { "\(name) · \($0)" } ?? name))
            } else if placeLabel != nil {
                face(chevron: false)
            }
        }
        .task(id: "\(workspace.current?.clinicId ?? "")-\(canRelocate)-\(workspace.scopeVersion)") { await loadRelocations() }
        .sheet(item: $opened) { destination in
            NavigationStack {
                destination.view
                    .providerRoutes()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button(L("Close")) { opened = nil } }
                    }
            }
        }
    }

    /// The place as a pill (the top bar), web `MobileSwitcherRow`.
    private func face(chevron: Bool) -> some View {
        HStack(spacing: 6) {
            Glyph(workspace.allLocationsChosen ? "layers" : "map-pin", size: 14).foregroundStyle(Theme.inkSoft)
            Text(placeLabel ?? name).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
            if chevron { Glyph("chevrons-up-down", size: 14).foregroundStyle(Theme.inkSoft.opacity(0.7)) }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    /// The sidebar's header row: the mark (40), the name in Fredoka 16, the place under it.
    private func sidebarFace(chevron: Bool) -> some View {
        HStack(spacing: 12) {
            BusinessMarkView(name: name, logoURL: workspace.current?.logoUrl, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.brandHeading(16)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                if let placeLabel {
                    HStack(spacing: 4) {
                        Glyph(workspace.allLocationsChosen ? "layers" : "map-pin", size: 12)
                        Text(placeLabel).lineLimit(1)
                    }
                    .font(Theme.text(12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer(minLength: 4)
            if chevron { Glyph("chevrons-up-down", size: 16).foregroundStyle(Theme.inkSoft.opacity(0.7)) }
        }
        .padding(8)
        .contentShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
    }

    @ViewBuilder
    private var menu: some View {
        Section(chooser ? LF("Locations of %@", name) : LF("Location of %@", name)) {
            if chooser {
                if workspace.canSeeAllLocations {
                    Button(action: chooseAll) {
                        Label {
                            Text(L("All locations"))
                            Text(L("Finance, invoices and clients across the business"))
                        } icon: {
                            Glyph(workspace.allLocationsChosen ? "check" : "layers")
                        }
                    }
                }
                ForEach(choices) { location in
                    let chosen = !workspace.allLocationsChosen && location.id == workspace.selectedLocation?.id
                    Button { choose(location) } label: { row(location, chosen: chosen) }
                        .disabled(location.status == "paused")
                }
                if canRelocate && toRelocate > 0 {
                    Button { open(.relocate) } label: {
                        GlyphLabel(LF("To relocate (%d)", toRelocate), icon: "arrow-right-left")
                    }
                }
            } else if let current {
                // The one place: where this device works, not a choice.
                Button {} label: { row(current, chosen: true) }
                    .disabled(true)
            }
            if canAddLocations {
                let path = addPath
                Button { open(.addLocation) } label: {
                    if path == .add {
                        GlyphLabel(L("Add a location"), icon: "plus")
                    } else {
                        Label {
                            Text(addPathTitle(path))
                            Text(addPathHint(path))
                        } icon: {
                            Glyph("sparkles")
                        }
                    }
                }
            }
            if showsLocations {
                Button { open(.locations) } label: { GlyphLabel(L("See locations"), icon: "map") }
            }
            if showsSettings {
                Button { open(.settings) } label: { GlyphLabel(L("Business settings"), icon: "settings") }
            }
        }
        if !others.isEmpty {
            Section(L("Your other businesses")) {
                ForEach(others) { other in
                    Button { chooseWorkspace(other) } label: { GlyphLabel(other.name.trimmingCharacters(in: .whitespaces).nonEmpty ?? L("Provider workspace"), icon: "building-2") }
                }
            }
        }
    }

    /// A location in the menu: its name, "Main", "Paused", its address, and "Register open".
    private func row(_ location: ProviderLocation, chosen: Bool) -> some View {
        let paused = location.status == "paused"
        let tags = [location.isPrimary && workspace.multiLocation ? L("Main") : nil, paused ? L("Paused") : nil].compactMap { $0 }
        let detail = [paused ? L("Takes no new visits") : (location.address?.nonEmpty ?? L("No address yet")), openShift.contains(location.id) ? L("Register open") : nil]
            .compactMap { $0 }.joined(separator: " · ")
        return Label {
            Text(([location.name] + tags).joined(separator: " · "))
            Text(detail)
        } icon: {
            Glyph(chosen ? "check" : (openShift.contains(location.id) ? "circle-dot" : "map-pin"))
        }
    }

    // MARK: The plan's way to another location

    private var addPath: PlacesAddPath {
        let active = workspace.activeLocations
        let plan = workspace.locationsResponse?.plan
        let canAdd = active.isEmpty || (plan.map { $0.canAdd ?? $0.allowsMultiple ?? false } ?? false)
        if canAdd { return .add }
        if plan?.addonAvailable == true { return .buyAddon }
        if plan?.talkToSales == true { return .talkToSales }
        return .upgrade
    }

    private func addPathTitle(_ path: PlacesAddPath) -> String {
        switch path {
        case .buyAddon: L("Add a location to your plan")
        case .talkToSales: L("More locations: talk to us")
        default: L("Available on the Business plan")
        }
    }

    private func addPathHint(_ path: PlacesAddPath) -> String {
        switch path {
        case .buyAddon: L("An extra location, from Subscription")
        case .talkToSales: L("Enterprise is a quote from our team")
        default: L("Starter is for one place")
        }
    }

    // MARK: Actions

    private func open(_ destination: PlacesSwitcherDestination) {
        if let onOpen { onOpen(destination) } else { opened = destination }
    }

    private func choose(_ location: ProviderLocation) {
        guard location.status == "active" else { return }
        if !workspace.allLocationsChosen && location.id == workspace.selectedLocation?.id { return }
        workspace.setLocation(location.id)
        Toast.show(LF("Now showing %@.", location.name))
    }

    private func chooseAll() {
        guard !workspace.allLocationsChosen else { return }
        workspace.setAllLocations()
        Toast.show(L("Now showing every location."))
    }

    private func chooseWorkspace(_ other: ProviderWorkspace) {
        Task {
            await workspace.choose(other)
            if workspace.current?.clinicId == other.clinicId {
                Toast.show(LF("Now working in %@.", other.name))
            } else {
                Toast.error(L("That workspace couldn’t open. Try again."))
            }
        }
    }

    private func loadRelocations() async {
        guard canRelocate && workspace.multiLocation else { toRelocate = 0; return }
        if let answer: PlacesRelocations = try? await API.get("/provider-locations/relocate") {
            toRelocate = answer.visits?.count ?? 0
        }
    }
}
