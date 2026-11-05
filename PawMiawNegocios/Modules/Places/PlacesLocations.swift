//
//  PlacesLocations.swift
//  PawMiawNegocios
//
//  Settings → Locations ("Sedes"), web provider.locations.tsx →
//  components/app/locations/locations-page.tsx: the places the business works
//  from. A card says where the place is, its clock, who works there and what it
//  has (each a way in), and what still holds it open. How many can be active is
//  the plan's: past it the add button says what to do (a "Sede adicional",
//  another plan, or talk to us) and opens the web for the plan; locations the
//  plan paused are listed with their state. The main location is never
//  archived, and no location is archived while it still holds something.
//  Opened from the switcher's "Add a location" (`LocationsScreen(add: true)`,
//  PlacesSwitcher.swift), it starts on the new location's sheet — or the
//  plan's message — once the list is known.
//

import SwiftUI

struct LocationsScreen: View {
    /// Opened from the switcher's "Add a location": the new location's sheet — or the plan's
    /// message when the plan holds no more — once the list (and so the plan) is known.
    var add: Bool = false

    var body: some View {
        PlacesLocationsPage(add: add)
            .providerPage(L("Locations"), root: true)
    }
}

/// Where each thing a location has or holds is dealt with.
enum PlacesDestination {
    case agenda, register, stays, hospital, relocate, staff, rooms, hours

    var route: ProviderRoute {
        switch self {
        case .agenda: .schedule(ScheduleFilter(view: "list"))
        case .register: .section(.store)
        case .stays: .section(.stays)
        case .hospital: .section(.hospital)
        case .relocate: .section(.relocate)
        case .staff: .section(.staff)
        case .rooms: .section(.rooms)
        case .hours: .section(.availability)
        }
    }
}

enum PlacesLocationSheetKind: Identifiable {
    case new
    case edit(PlacesLocation)
    case archive(PlacesLocation)
    case primary(PlacesLocation)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let location): "edit-\(location.id)"
        case .archive(let location): "archive-\(location.id)"
        case .primary(let location): "primary-\(location.id)"
        }
    }
}

/// After any change to the locations: the switcher, every screen, this list.
@MainActor
func placesLocationsChanged() async {
    await Workspace.shared.refresh()
    announceDataChanged()
}

private struct PlacesLocationsPage: View {
    var add: Bool = false

    @EnvironmentObject private var workspace: Workspace
    @State private var addHandled = false
    @Environment(\.openURL) private var openURL
    @State private var answer: PlacesLocationsAnswer?
    @State private var loadError: String?
    @State private var planNotice = false
    @State private var showArchived = false
    @State private var sheet: PlacesLocationSheetKind?
    @State private var goTo: ProviderRoute?
    @State private var reactivating: String?

    private var canEdit: Bool { workspace.can(.workspaceEdit) }
    /// The plan is the owner's.
    private var canManagePlan: Bool { workspace.current?.canManagePlan ?? workspace.can(.billingManage) }
    private var all: [PlacesLocation] { answer?.locations ?? [] }
    private var active: [PlacesLocation] { PlacesLocationRules.active(all) }
    private var paused: [PlacesLocation] { PlacesLocationRules.paused(all) }
    private var archived: [PlacesLocation] { PlacesLocationRules.archived(all) }
    private var plan: PlacesLocationPlan? { answer?.plan }
    private var path: PlacesAddPath { PlacesLocationRules.addPath(all, plan: plan) }
    private var limit: Int? { plan?.limit ?? ((plan?.allowsMultiple ?? false) ? nil : 1) }
    /// One place: no "main", no "this device", no order to speak of.
    private var several: Bool { active.count + paused.count > 1 }

    private func stats(_ id: String) -> PlacesLocationStats? { answer?.stats?.first { $0.locationId == id } }

    var body: some View {
        Group {
            if workspace.current != nil && !canEdit {
                PageScroll {
                    EmptyState(systemImage: "lock", title: L("You do not have access to the locations."), message: L("Locations are changed by someone who can edit the workspace. Ask the owner."), panel: true)
                }
            } else {
                page
            }
        }
        .reloadsOnScope { await load() }
        .sheet(item: $sheet) { which in
            switch which {
            case .new:
                PlacesLocationSheet(location: nil, active: active, all: all, upcomingVisits: 0, onPlanRequired: { planNotice = true })
            case .edit(let location):
                PlacesLocationSheet(location: location, active: active, all: all, upcomingVisits: stats(location.id)?.futureAppointments ?? 0, onPlanRequired: { planNotice = true })
            case .archive(let location):
                PlacesLocationArchiveSheet(location: location, locations: all, stats: stats(location.id), statsLoaded: answer?.stats != nil, onGo: { go(location, $0) }, onPlanRequired: { planNotice = true }, onRefresh: { Task { await load() } })
            case .primary(let location):
                PlacesMakePrimarySheet(location: location)
            }
        }
        .navigationDestination(item: $goTo) { RouteView(route: $0) }
    }

    private func startAdding() {
        if path == .add {
            planNotice = false
            sheet = .new
        } else {
            withAnimation { planNotice = true }
        }
    }

    // MARK: Page

    private var page: some View {
        PageScroll(refresh: { await load() }) {
            header

            if planNotice { planNoticeCard.transition(.opacity) }

            if answer == nil && loadError == nil {
                LoadingState()
            } else if loadError != nil, answer == nil {
                EmptyState(systemImage: "map-pin", title: L("The locations couldn’t load."), message: L("Check your connection and try again."), actionTitle: L("Try again"), action: { Task { await load() } }, accent: Theme.mango, panel: true)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // Two columns either way: several places side by side, or the one place beside what belongs to the whole business.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 12, alignment: .top)], spacing: 12) {
                        ForEach(active) { location in
                            card(location,
                                 onArchive: { sheet = .archive(location) },
                                 onMakePrimary: location.primary || active.count < 2 ? nil : { sheet = .primary(location) })
                        }
                        if !several { sharedByAll(several: false) }
                    }
                    Text((active.count == 1 ? L("1 active location") : LF("%d active locations", active.count)) + (several ? " · " + L("The main one comes first.") : ""))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 4)
                }

                if !paused.isEmpty { pausedSection }
                if !archived.isEmpty { archivedSection }
                if several { sharedByAll(several: true) }
            }
        }
    }

    /// The web's `ProviderModuleHeader`: MapPin on the default blue, "Add a location", three numbers.
    private var header: some View {
        ModuleHeader(
            icon: "map-pin",
            title: L("Locations"),
            subtitle: several
                ? L("Each location keeps its own hours, rooms, registers, visits and stays. Clients, the catalog, prices and the team are shared by all of them.")
                : L("Where the business works from: its address, its clock and how to reach it. Add another location when you open a second place."),
            stats: [
                ModuleStat("active", label: L("Active@locations"), value: answer == nil ? "—" : "\(active.count)", hint: paused.isEmpty ? nil : LF("%d paused", paused.count), icon: "map-pin", accent: Theme.blue),
                ModuleStat("archived", label: L("Archived@locations"), value: answer == nil ? "—" : "\(archived.count)",
                           hint: archived.isEmpty ? nil : (showArchived ? L("Hide them") : L("Show them")),
                           icon: "archive", accent: Theme.mango, active: showArchived,
                           action: archived.isEmpty ? nil : { withAnimation { showArchived.toggle() } }),
                ModuleStat("plan", label: L("Your plan"), value: answer == nil ? "—" : (limit.map { LF("%d of %d", active.count, $0) } ?? L("Several")),
                           hint: answer == nil ? nil : (path == .add ? L("Active locations it holds") : L("All in use")),
                           icon: "sparkles", accent: Theme.pink,
                           action: path == .add ? nil : { withAnimation { planNotice.toggle() } }),
            ],
            storageKey: "locations"
        ) {
            if canEdit && answer != nil {
                PMButton(L("Add a location"), systemImage: "plus", action: startAdding)
            }
        }
    }

    private var pausedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Glyph("circle-pause", size: 16)
                Text(LF("Paused (%d)", paused.count).uppercased()).tracking(1.6)
            }
            .font(.brandText(12, weight: .heavy)).foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 4)
            Text(L("Over the plan’s limit. Their history stays, but they take no new visits, shifts or stays. They come back on their own when the plan holds them again."))
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(paused) { location in
                    card(location, here: false, onArchive: { sheet = .archive(location) }, onReactivate: { Task { await reactivate(location) } })
                }
            }
            .padding(.top, 8)
        }
        .padding(.top, 8)
    }

    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation { showArchived.toggle() } } label: {
                HStack(spacing: 8) {
                    Glyph("chevron-down", size: 16).rotationEffect(.degrees(showArchived ? 0 : -90))
                    Text(LF("Archived (%d)", archived.count).uppercased()).tracking(1.6)
                }
                .font(.brandText(12, weight: .heavy))
                .foregroundStyle(Theme.inkSoft)
                .frame(minHeight: 40)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(showArchived ? .isSelected : [])
            if showArchived {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(archived) { location in
                        card(location, here: false, onReactivate: { Task { await reactivate(location) } })
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func card(_ location: PlacesLocation, here: Bool? = nil, onArchive: (() -> Void)? = nil, onReactivate: (() -> Void)? = nil, onMakePrimary: (() -> Void)? = nil) -> some View {
        PlacesLocationCard(
            location: location,
            stats: stats(location.id),
            several: several,
            here: here ?? (workspace.multiLocation && workspace.selectedLocation?.id == location.id),
            busy: reactivating == location.id,
            onEdit: { sheet = .edit(location) },
            onGo: { go(location, $0) },
            onArchive: onArchive,
            onReactivate: onReactivate,
            onMakePrimary: onMakePrimary
        )
    }

    /// What a location does not keep for itself, and where that is set (web `SharedByAll`).
    private func sharedByAll(several: Bool) -> some View {
        Card(padding: 20, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(several ? L("Shared by every location") : L("Set for the whole business")).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                Text(L("The legal name and tax details, the currency and tax, the services you offer, the catalog and its prices are the business’s, not a location’s. They are in Settings and the Catalog."))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            NavigationLink(value: ProviderRoute.section(.settings)) { Text(L("Open Settings")) }
                .buttonStyle(.pm(.outline, size: .compact))
        }
    }

    // MARK: The plan's message

    /// What the add button says when the plan holds no more (web `PlanNotice`): pink 10%, a white disc with the sparkles.
    private var planNoticeCard: some View {
        let title: String
        let body: String
        switch path {
        case .buyAddon:
            title = L("Add a location to your plan")
            body = LF("Your plan holds %d active locations. An extra location adds one more, with its own users, from Subscription.", limit ?? 1)
        case .talkToSales:
            title = L("Your plan is at its locations")
            body = LF("Your plan holds %d active locations, the most you can add here. For more, Enterprise is a quote from our team.", limit ?? 1)
        default:
            title = L("Another location needs the Business plan")
            body = L("Starter is for one place. On Business each location keeps its own hours, rooms, registers and schedule, and every location shares the same clients.")
        }
        let ask = canManagePlan || path == .talkToSales ? "" : " " + L("Ask the workspace owner to change the plan.")
        return Card(tint: Theme.pink) {
            HStack(alignment: .top, spacing: 12) {
                Glyph("sparkles", size: 20).foregroundStyle(Theme.blue)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                    Text(body + ask).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
            HStack(spacing: 8) {
                PMButton(L("Not now"), variant: .outline, size: .compact) { withAnimation { planNotice = false } }
                if path == .talkToSales {
                    PMButton(L("Talk to us"), systemImage: "mail", size: .compact) {
                        let subject = L("PawMiaw Enterprise").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "mailto:\(PlacesLocationRules.supportEmail)?subject=\(subject)") { openURL(url) }
                    }
                } else if canManagePlan {
                    // Plans are bought on the web: the app opens the business's Subscription page there.
                    PMButton(path == .buyAddon ? L("Go to Subscription") : L("See plans"), systemImage: "sparkles", size: .compact) {
                        openURL(APIConfig.webOrigin.appendingPathComponent("provider/billing"))
                    }
                }
            }
        }
    }

    // MARK: Loading and actions

    private func load() async {
        guard workspace.current != nil, canEdit else { return }
        do {
            answer = try await API.get("/provider-locations", query: ["includeArchived": "true", "withStats": "true"])
            loadError = nil
            // "Add a location" from the switcher: once the list (and so the plan) is known.
            if add && !addHandled {
                addHandled = true
                startAdding()
            }
        } catch is CancellationError {
        } catch {
            if answer == nil { loadError = errorText(error) } else { Toast.error(error) }
        }
    }

    private func reactivate(_ location: PlacesLocation) async {
        reactivating = location.id
        defer { reactivating = nil }
        do {
            let _: PlacesLocation = try await API.patch("/provider-locations/\(location.id)", body: ["status": "active"])
            Toast.show(LF("%@ is active again.@location", location.name))
            await placesLocationsChanged()
        } catch {
            if let api = error as? APIError, api.code == "location_plan_required" || api.code == "location_limit_reached" {
                withAnimation { planNotice = true }
            }
            Toast.error(PlacesLocationRules.errorText(error, name: location.name, limit: limit, talkToSales: plan?.talkToSales ?? false, requiredPlan: plan?.requiredPlan))
        }
    }

    /// The pages of one place follow the location this device works at: switch to it, say so, and go.
    private func go(_ location: PlacesLocation, _ to: PlacesDestination) {
        let fromSheet = sheet != nil
        sheet = nil
        if to != .relocate && to != .staff && workspace.multiLocation && workspace.selectedLocation?.id != location.id && workspace.memberLocations.contains(where: { $0.id == location.id }) {
            workspace.setLocation(location.id)
            Toast.show(LF("Now showing %@.", location.name))
        }
        if fromSheet {
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                goTo = to.route
            }
        } else {
            goTo = to.route
        }
    }
}

// MARK: - A location's card

/// One location (web `LocationCard`): where it is, its clock and contact, who works
/// there and what it has — each with a way in — what it still holds, and its actions.
private struct PlacesLocationCard: View {
    let location: PlacesLocation
    let stats: PlacesLocationStats?
    /// The business has more than one open location: "Main", "This device" and the links that switch place mean something.
    let several: Bool
    let here: Bool
    let busy: Bool
    let onEdit: () -> Void
    let onGo: (PlacesDestination) -> Void
    let onArchive: (() -> Void)?
    let onReactivate: (() -> Void)?
    let onMakePrimary: (() -> Void)?

    @State private var mainOpen = false

    private var open: Bool { location.isActive }

    var body: some View {
        Card(padding: 16, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                PlacesLocationThumb(photoUrl: location.photoUrl, isPrimary: location.primary, size: location.photoUrl == nil ? 44 : 56)
                    .accessibilityLabel(LF("Photo of %@", location.name))
                VStack(alignment: .leading, spacing: 4) {
                    Text(location.name).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
                    if (several && location.primary) || here || location.isArchived || location.isPaused {
                        FlowLayout(spacing: 6) {
                            if several && location.primary { TagChip(text: L("Main"), linked: true) }
                            if here { Chip(text: L("This device"), tone: .info) }
                            if location.isArchived { Chip(text: L("Archived@location-one"), tone: .muted) }
                            if location.isPaused { Chip(text: L("Paused"), tone: .warn) }
                        }
                    }
                    // A long address wraps, three lines at most; the whole of it is in the sheet.
                    Text(location.address?.nonEmpty ?? L("No address yet")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(3)
                }
                Spacer(minLength: 0)
            }

            FlowLayout(spacing: 16, lineSpacing: 4) {
                fact("earth", PlacesTimeZones.cityName(location.zone) + (open ? " · " + LF("%@ now", PlacesLocationRules.clock(location.zone)) : ""))
                if let days = location.openDays, !location.isArchived {
                    fact("clock-3", days == 1 ? L("1 day open") : LF("%d days open", days))
                }
                if let phone = location.phone?.nonEmpty { fact("phone", phone) }
                if let email = location.email?.nonEmpty { fact("mail", email) }
            }

            if let stats, !location.isArchived {
                FlowLayout(spacing: 8) {
                    countLink("users-round", LP(stats.staff ?? 0, "%d person", "%d people"), to: .staff, enabled: true)
                    countLink("door-open", LP(stats.rooms ?? 0, "%d room", "%d rooms"), to: .rooms, enabled: open)
                    countLink("store", LP(stats.registers ?? 0, "%d register", "%d registers"), to: .register, enabled: open)
                    if (stats.stayUnits ?? 0) > 0 {
                        countLink("bed-double", (stats.stayUnits ?? 0) == 1 ? L("1 kennel or suite") : LF("%d kennels and suites", stats.stayUnits ?? 0), to: .stays, enabled: open)
                    }
                }
            }

            let holds = PlacesLocationRules.blockers(stats)
            if !holds.isEmpty {
                FlowLayout(spacing: 12, lineSpacing: 4) {
                    ForEach(holds, id: \.blocker) { entry in
                        HStack(spacing: 4) {
                            Glyph(entry.blocker == .hospitalPatients ? "bed-double" : entry.blocker.systemImage, size: 14)
                            Text(holdText(entry.blocker, entry.count))
                        }
                    }
                }
                .font(.brandText(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
            }

            if several && location.primary && open {
                VStack(alignment: .leading, spacing: 0) {
                    Button { withAnimation(.easeOut(duration: 0.2)) { mainOpen.toggle() } } label: {
                        HStack(spacing: 8) {
                            Glyph("star", size: 14).foregroundStyle(Theme.blue)
                            Text(L("What being the main location means")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            Spacer(minLength: 0)
                            Glyph("chevron-down", size: 16).foregroundStyle(Theme.inkSoft).rotationEffect(.degrees(mainOpen ? 180 : 0))
                        }
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(mainOpen ? .isSelected : [])
                    if mainOpen { PlacesMainMeans().padding(.top, 4).padding(.bottom, 6) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.wash(Theme.blue, 7), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            }

            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 12) {
                RowDivider()
                FlowLayout(spacing: 8) {
                    PMButton(L("Edit"), systemImage: "pencil", variant: .outline, size: .compact, action: onEdit)
                    if open {
                        PMButton(L("Opening hours"), systemImage: "clock-3", variant: .outline, size: .compact) { onGo(.hours) }
                    }
                    if let onMakePrimary {
                        PMButton(L("Make main"), systemImage: "star", variant: .outline, size: .compact, action: onMakePrimary)
                    }
                    if let onArchive {
                        PMButton(L("Archive"), systemImage: "archive", variant: .outline, size: .compact, action: onArchive)
                    }
                    if let onReactivate {
                        PMButton(L("Make active again"), systemImage: "rotate-ccw", variant: .outline, size: .compact, isWorking: busy, action: onReactivate)
                    }
                }
            }
        }
        .overlay {
            if here {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.blue, lineWidth: 1)
            }
        }
        .opacity(location.isArchived || location.isPaused ? 0.85 : 1)
    }

    private func fact(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Glyph(icon, size: 14)
            Text(text).lineLimit(1)
        }
        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
    }

    /// A number of something a location has, that opens it (or just says it, when the place takes nothing new).
    @ViewBuilder
    private func countLink(_ icon: String, _ text: String, to: PlacesDestination, enabled: Bool) -> some View {
        FilterChip(title: text, isSelected: false, tone: Theme.inkSoft, icon: icon) { if enabled { onGo(to) } }
            .allowsHitTesting(enabled)
    }

    private func holdText(_ blocker: PlacesLocationBlocker, _ count: Int) -> String {
        switch blocker {
        case .futureAppointments: return count == 1 ? L("1 visit to come") : LF("%d visits to come", count)
        case .openRegisterSessions: return count == 1 ? L("Register open") : LF("%d registers open", count)
        case .activeStays: return count == 1 ? L("1 stay booked or in") : LF("%d stays booked or in", count)
        case .hospitalPatients: return count == 1 ? L("1 hospital patient") : LF("%d hospital patients", count)
        }
    }
}

/// What being the main location drives, said the same way on its card and before changing it.
struct PlacesMainMeans: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach([
                L("Families book here online unless they choose another location."),
                L("Its clock is the business’s day for what belongs to every location: Finance, follow-ups and reminders."),
                L("Its address and phone are the business’s on documents that belong to no single location."),
                L("It always stays active if the plan ever holds fewer locations."),
            ], id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Glyph("star", size: 14).foregroundStyle(Theme.blue).padding(.top, 2)
                    Text(line).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                }
            }
        }
    }
}

// MARK: - Make it the main one

/// The web's ProviderConfirmSheet: pink, the triangle, what the main location drives.
private struct PlacesMakePrimarySheet: View {
    let location: PlacesLocation
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        ProviderModal(
            title: LF("Make %@ the main location?", location.name),
            subtitle: L("Everything already booked keeps its place. This changes what the business uses by default:"),
            systemImage: "triangle-alert",
            accent: .pink,
            primaryTitle: L("Make it the main one"),
            primaryVariant: .destructive,
            isWorking: working,
            cancelTitle: L("Not now"),
            primaryIcon: "triangle-alert",
            onPrimary: confirm
        ) {
            PlacesMainMeans()
        }
        .presentationDetents([.medium, .large])
    }

    private func confirm() {
        working = true
        Task {
            defer { working = false }
            do {
                try await API.send("POST", "/provider-locations/\(location.id)/make-primary")
                Toast.show(LF("%@ is now the main location.", location.name))
                await placesLocationsChanged()
                dismiss()
            } catch {
                Toast.error(PlacesLocationRules.errorText(error, name: location.name))
            }
        }
    }
}

// MARK: - Archive, or why it can't be yet

private struct PlacesLocationArchiveSheet: View {
    let location: PlacesLocation
    let locations: [PlacesLocation]
    let stats: PlacesLocationStats?
    let statsLoaded: Bool
    let onGo: (PlacesDestination) -> Void
    let onPlanRequired: () -> Void
    let onRefresh: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    private var refusal: PlacesArchiveRefusal? { PlacesLocationRules.archiveRefusal(location, locations: locations, stats: stats) }

    var body: some View {
        Group {
            if let refusal {
                // Why it can't be yet (web: butter, the lock, the way to each thing in the way).
                ProviderModal(title: refusalTitle(refusal), subtitle: refusalText(refusal), systemImage: "lock", accent: .butter, cancelTitle: L("Close")) {
                    if refusal == .inUse {
                        VStack(spacing: 8) {
                            ForEach(PlacesLocationRules.blockers(stats), id: \.blocker) { entry in
                                blockerRow(entry.blocker, entry.count)
                            }
                        }
                    }
                }
            } else {
                // The web's ProviderConfirmSheet: pink, the triangle, the danger action.
                ProviderModal(
                    title: LF("Archive %@?", location.name),
                    subtitle: L("It leaves the location menu and can’t take new visits, stays or sales. Its history stays, and you can make it active again later."),
                    systemImage: "triangle-alert",
                    accent: .pink,
                    primaryTitle: L("Archive location"),
                    primaryVariant: .destructive,
                    isWorking: working,
                    cancelTitle: L("Keep it@location"),
                    primaryIcon: "triangle-alert",
                    onPrimary: confirm
                ) {
                    if let stats {
                        ForEach(consequences(stats), id: \.self) { line in
                            PlacesConsequenceRow(systemImage: line.icon, text: line.text)
                        }
                        PlacesConsequenceRow(systemImage: "history", text: L("Its visits, sales and Cortes del día stay in the history of every screen."))
                    } else if !statsLoaded {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L("Checking what it still holds…")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func refusalTitle(_ refusal: PlacesArchiveRefusal) -> String {
        switch refusal {
        case .primary: L("The main location can’t be archived")
        case .lastActive: L("A business needs one active location")
        case .inUse: LF("%@ can’t be archived yet", location.name)
        }
    }

    private func refusalText(_ refusal: PlacesArchiveRefusal) -> String {
        switch refusal {
        case .primary: LF("Families book here by default and the business’s clock and contact are its own. Make another location the main one first; then %@ can be archived.", location.name)
        case .lastActive: LF("%@ is the only one. Add another location first, or keep working from this one.", location.name)
        case .inUse: L("It still holds what is below. Finish or move each one first: nothing is cancelled or moved for you.")
        }
    }

    private func blockerRow(_ blocker: PlacesLocationBlocker, _ count: Int) -> some View {
        // A paused location's visits are moved from "Por reubicar", not its Agenda.
        let to: PlacesDestination
        let title: String
        let action: String
        switch blocker {
        case .futureAppointments:
            to = location.isPaused ? .relocate : .agenda
            title = count == 1 ? L("1 visit still to come") : LF("%d visits still to come", count)
            action = location.isPaused ? L("Open “To relocate”") : L("Open the Schedule")
        case .openRegisterSessions:
            to = .register
            title = count == 1 ? L("1 register shift open") : LF("%d register shifts open", count)
            action = L("Open the register")
        case .activeStays:
            to = .stays
            title = count == 1 ? L("1 stay booked or in progress") : LF("%d stays booked or in progress", count)
            action = L("Open Stays")
        case .hospitalPatients:
            to = .hospital
            title = count == 1 ? L("1 patient in the hospital") : LF("%d patients in the hospital", count)
            action = L("Open the Hospital")
        }
        // A row that opens where it is dealt with (web: a 36 lime disc, the count, the way there in blue).
        return Button { onGo(to) } label: {
            HStack(spacing: 12) {
                PlacesIconBadge(systemImage: blocker.systemImage, size: 36, washPercent: 24, tone: Theme.lime)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    Text(action).font(Theme.text(14)).foregroundStyle(Theme.blue)
                }
                Spacer(minLength: 0)
                Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private struct Line: Hashable { let icon: String; let text: String }

    /// What archiving a location that holds nothing takes with it.
    private func consequences(_ stats: PlacesLocationStats) -> [Line] {
        var lines: [Line] = []
        let onlyHere = stats.staffOnlyHere ?? 0
        if onlyHere > 0 {
            lines.append(Line(icon: "users-round", text: onlyHere == 1
                ? L("1 person works only here. They will work at every location until you place them at another.")
                : LF("%d people work only here. They will work at every location until you place them at another.", onlyHere)))
        }
        var things: [String] = []
        if let rooms = stats.rooms, rooms > 0 { things.append(LP(rooms, "%d room", "%d rooms")) }
        if let registers = stats.registers, registers > 0 { things.append(LP(registers, "%d register", "%d registers")) }
        if let units = stats.stayUnits, units > 0 { things.append(units == 1 ? L("1 kennel or suite") : LF("%d kennels and suites", units)) }
        if !things.isEmpty {
            lines.append(Line(icon: "door-open", text: LF("What it has (%@) leaves with it, and is there again if you make it active.", things.joined(separator: ", "))))
        }
        return lines
    }

    private func confirm() {
        working = true
        Task {
            defer { working = false }
            do {
                let _: PlacesLocation = try await API.patch("/provider-locations/\(location.id)", body: ["status": "archived"])
                Toast.show(LF("%@ archived.", location.name))
                await placesLocationsChanged()
                dismiss()
            } catch {
                if let api = error as? APIError {
                    if api.code == "location_plan_required" || api.code == "location_limit_reached" { onPlanRequired() }
                    // It took something on since the page loaded: read it again, so the sheet says what.
                    if api.code == "location_in_use" { onRefresh() }
                }
                Toast.error(PlacesLocationRules.errorText(error, name: location.name))
            }
        }
    }
}
