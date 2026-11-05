//
//  SettingsScreen.swift
//  PawMiawNegocios
//
//  Settings (web: routes/provider.settings.tsx): how the business shows up
//  to families (name, logo, contact, address), what it offers, the country,
//  clock and money it runs on, what prints on its documents, and this
//  person's own alerts. Each section saves on its own. Staff, hours, rooms,
//  locations and the plan have their own pages and are linked. Someone who
//  cannot edit the workspace reads it, and is told so.
//

import SwiftUI
import PhotosUI

/// What Settings reads once and its sections share.
@MainActor
final class TeamSettingsModel: ObservableObject {
    @Published var setup: TeamSetupState?
    @Published var setupFailed = false
    @Published var catalog: TeamServiceCatalog?
    @Published var offeredCatalog: TeamServiceCatalog?
    @Published var catalogFailed = false
    @Published var store: TeamStoreSettings?
    @Published var storeFailed = false
    @Published var memberCount: Int?
    /// The open days of the week, for Availability's line.
    @Published var openDays: Int?
    /// Every room the Rooms page lists (the hospital's too), for its line.
    @Published var roomCount: Int?
    @Published var loaded = false

    func load(_ workspace: Workspace) async {
        guard let clinicId = workspace.current?.clinicId else { return }
        let canEdit = workspace.can(.workspaceEdit)
        do {
            catalog = try await API.get("/appointment-services")
            catalogFailed = false
        } catch { catalogFailed = catalog == nil }
        if canEdit {
            do { setup = try await API.get("/provider-setup"); setupFailed = false } catch { setupFailed = setup == nil }
        } else {
            offeredCatalog = try? await API.get("/appointment-services", query: ["scope": "provider"])
        }
        if TeamSettingsModel.canSeeMoney(workspace) {
            do {
                store = try await TeamStoreSettings.load()
                storeFailed = false
            } catch { storeFailed = store == nil }
        }
        if workspace.can(.staffView) {
            let members: [TeamMember]? = try? await API.get("/provider-workspaces/\(clinicId)/members")
            memberCount = members?.count
        }
        if canEdit, let availability: TeamAvailability = try? await API.get("/provider-workspaces/\(clinicId)/availability", query: ["locationId": workspace.locationId]) {
            openDays = (availability.weeklySchedule ?? []).filter(\.enabled).count
        }
        if workspace.can(.appointmentsView) {
            let rooms: [JSONValue]? = try? await API.get("/provider-rooms", query: ["locationId": workspace.locationId])
            roomCount = rooms?.count
        }
        loaded = true
    }

    /// The store's settings answer anyone who sells, keeps the catalog or the stock.
    static func canSeeMoney(_ workspace: Workspace) -> Bool {
        workspace.canAny(.salesSell, .catalogView, .inventoryView)
    }

    /// Whatever settings changed: the workspace, the currency other screens show.
    func saved(_ workspace: Workspace) async {
        await load(workspace)
        await Workspace.shared.refresh()
        announceDataChanged()
    }
}

private enum TeamSettingsSection: String, CaseIterable, Hashable, Identifiable {
    case profile, contact, services, regional, legal, consents, ai, notifications, history
    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: L("Business profile")
        case .contact: L("Contact and address")
        case .services: L("Services you offer")
        case .regional: L("Region and money")
        case .legal: L("Legal details")
        case .consents: L("Consents")
        case .ai: "Olfato AI"
        case .notifications: L("Your notifications")
        case .history: L("Change history")
        }
    }

    /// The web's icon for the section (settings rail).
    var icon: String {
        switch self {
        case .profile: "building-2"
        case .contact: "mail"
        case .services: "tags"
        case .regional: "earth"
        case .legal: "landmark"
        case .consents: "file-pen-line"
        case .ai: "olfato"
        case .notifications: "bell"
        case .history: "history"
        }
    }
}

/// Who may open what in Settings (the web's rules, provider.settings.tsx).
@MainActor
private enum TeamSettingsAccess {
    static func canSeePlan(_ workspace: Workspace) -> Bool {
        (workspace.current?.canManagePlan ?? false) || workspace.moneyLevel >= .finances
    }
    static func canSeeConsents(_ workspace: Workspace) -> Bool {
        workspace.canAny(.appointmentsView, .staysView, .recordsView, .workspaceEdit)
    }
    /// Olfato AI: the switch for whoever reads records or edits the workspace; the team's use for owners,
    /// admins and whoever manages roles or money.
    static func canOpenAi(_ workspace: Workspace) -> Bool {
        workspace.canAny(.recordsView, .workspaceEdit) || TeamOlfatoAccess.seesTeam(workspace)
    }
    static func canSeeHistory(_ workspace: Workspace) -> Bool {
        workspace.can(.workspaceEdit) || workspace.isOwnerOrAdmin
    }

    static func planLine(_ current: ProviderWorkspace) -> String {
        let plan: String? = switch current.plan {
        case "basic": "Basic"
        case "pro": "Pro"
        case "enterprise": "Enterprise"
        default: nil
        }
        let status: String = switch current.billingStatus {
        case "trialing": L("Trial")
        case "active": L("Active")
        case "past_due": L("Payment due")
        case "canceled": L("Cancelled")
        case "expired": L("Expired")
        case "grace_period": L("Grace period")
        default: L("No plan")
        }
        return plan.map { LF("%1$@ plan · %2$@", $0, status) } ?? status
    }

    static func city(_ zone: String) -> String {
        zone.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone
    }
}

/// Settings' module header (web: `ProviderModuleHeader` with the Settings icon
/// and its four numbers; the kinds of care and the time zone open their section).
private struct TeamSettingsHeader: View {
    @ObservedObject var model: TeamSettingsModel
    var showsStats: Bool = true
    /// The section shown under it (its number reads as chosen).
    var open: TeamSettingsSection? = nil
    var onOpen: ((TeamSettingsSection) -> Void)? = nil
    @EnvironmentObject private var workspace: Workspace

    var body: some View {
        ModuleHeader(
            icon: "settings",
            title: L("Settings"),
            subtitle: L("How your business shows up to families, what it offers, and the clock and money it runs on."),
            accent: ProviderSection.settings.headerAccent,
            stats: showsStats ? stats : [],
            storageKey: "settings"
        )
    }

    private var stats: [ModuleStat] {
        guard let current = workspace.current else { return [] }
        let timezone = current.availability?.timezone ?? "UTC"
        let names = current.enabledCategories.map { id in
            model.catalog?.categories?.first(where: { $0.id == id })?.label ?? BusinessCategory(rawValue: id)?.label ?? id
        }
        var stats = [
            ModuleStat("services", label: L("Kinds of care"), value: "\(current.enabledCategories.count)",
                       hint: names.prefix(3).joined(separator: ", ") + (names.count > 3 ? "…" : ""),
                       icon: "tags", accent: Theme.lime, active: open == .services, action: onOpen.map { go in { go(.services) } }),
            ModuleStat("timezone", label: L("Time zone"), value: TeamSettingsAccess.city(timezone), hint: TeamHours.zoneLabel(timezone),
                       icon: "earth", accent: Theme.aqua, active: open == .regional, action: onOpen.map { go in { go(.regional) } }),
        ]
        if TeamSettingsModel.canSeeMoney(workspace) {
            stats.append(ModuleStat("money", label: L("Currency and tax"), value: model.store?.currency ?? "—",
                                    hint: model.store.map { LF("%1$@%% tax, %2$@", (Double($0.defaultTaxRateBps) / 100).formatted(), $0.pricesIncludeTax ? L("in the price") : L("added on top")) },
                                    icon: "coins", accent: Theme.mango, action: onOpen.map { go in { go(.regional) } }))
        }
        stats.append(ModuleStat("role", label: L("Your role"), value: TeamRole.label(current.role),
                                hint: TeamSettingsAccess.canSeePlan(workspace) ? TeamSettingsAccess.planLine(current) : nil,
                                icon: "shield-check", accent: Theme.pink))
        return stats
    }
}

/// "You can look, not change." over a section, for whoever can't edit the workspace.
private struct TeamReadOnlyBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Glyph("lock", size: 16).foregroundStyle(Theme.inkSoft).padding(.top, 2)
            (Text(L("You can look, not change.")).bold() + Text(" ") + Text(L("The business settings are changed by the owner or someone who edits the workspace. Your notifications are yours to set.")))
                .font(Theme.text(14))
                .foregroundStyle(Theme.inkStrong)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }
}

/// One of Settings' two lists (web `SettingsNav`): "En esta página" (the sections)
/// and "Con su propia página" (the settings that have a page of their own).
private struct TeamSettingsNavCard<Rows: View>: View {
    let label: String
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.brandText(10.9, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            VStack(spacing: 0) { rows() }
                .padding(6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        .cardShadow()
    }
}

/// A row of the Settings lists: a 36 disc with the icon, the name, a line, and
/// a chevron (a section) or an arrow (a page of its own).
private struct TeamSettingsNavRow: View {
    let title: String
    let hint: String?
    let icon: String
    var external: Bool = false
    var current: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if icon == "olfato" {
                    Image("OlfatoFace").resizable().scaledToFit().frame(width: 18, height: 18)
                } else {
                    Glyph(icon, size: 16)
                }
            }
            .foregroundStyle(current ? Theme.onBlue : (external ? Theme.inkSoft : Theme.blue))
            .frame(width: 36, height: 36)
            .background(current ? AnyShapeStyle(Theme.blue) : AnyShapeStyle(Theme.surfaceMuted), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                if let hint = hint?.nonEmpty { Text(hint).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
            }
            Spacer(minLength: 8)
            Glyph(external ? "arrow-up-right" : "chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .background(current ? AnyShapeStyle(Theme.wash(Theme.blue, 12)) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct SettingsScreen: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var model = TeamSettingsModel()
    @State private var opened: TeamSettingsSection?
    /// iPad: the section beside the rail (the web shows the first one when none is chosen).
    @State private var railSection: TeamSettingsSection = .profile
    @State private var railUnsaved: [String] = []
    /// iPad: a section asked for while the open one has unsaved changes.
    @State private var pendingSection: TeamSettingsSection?

    private var canEdit: Bool { workspace.can(.workspaceEdit) }

    var body: some View {
        Group {
            if workspace.inSetup {
                PageScroll {
                    TeamSettingsHeader(model: model, showsStats: false)
                    EmptyState(systemImage: "building-2", title: L("Finish workspace setup first."), message: L("Save the business basics and opening hours, then its settings live here."), accent: Theme.aqua, panel: true)
                }
            } else if let current = workspace.current {
                page(current)
            } else {
                LoadingState()
            }
        }
        .providerPage(L("Settings"), root: true)
        .reloadsOnScope { await model.load(workspace) }
        .navigationDestination(item: $opened) { TeamSettingsSectionPage(section: $0, model: model) }
        .sheet(item: $pendingSection) { next in
            ConfirmSheet(
                title: L("Leave without saving?"),
                message: LF("Your changes to %@ are not saved yet.", railUnsaved.joined(separator: ", ")),
                confirmTitle: L("Leave without saving"),
                destructive: true,
                cancelTitle: L("Keep editing")
            ) { _ in
                railUnsaved = []
                railSection = next
            }
        }
    }

    /// Opens a section: pushed on a phone; beside the rail on an iPad, asking first when the open one has unsaved changes.
    private func open(_ section: TeamSettingsSection) {
        guard sizeClass == .regular else { opened = section; return }
        guard section != railSection else { return }
        if railUnsaved.isEmpty { railSection = section } else { pendingSection = section }
    }

    private func page(_ current: ProviderWorkspace) -> AnyView {
        let timezone = current.availability?.timezone ?? "UTC"
        let city = TeamSettingsAccess.city(timezone)
        if sizeClass == .regular {
            // The web from 768: the rail on the left, the open section beside it.
            return AnyView(PageScroll(maxWidth: 1200, refresh: { await model.load(workspace) }) {
                TeamSettingsHeader(model: model, open: railSection) { open($0) }
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 16) { navCards(current, city: city) }
                        .frame(width: 272)
                    VStack(alignment: .leading, spacing: 12) {
                        if !canEdit { TeamReadOnlyBanner() }
                        TeamSettingsSectionBody(section: railSection, model: model)
                    }
                    .id(railSection)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .onPreferenceChange(TeamUnsavedKey.self) { railUnsaved = $0 }
                }
            })
        }
        return AnyView(PageScroll(refresh: { await model.load(workspace) }) {
            TeamSettingsHeader(model: model) { open($0) }
            navCards(current, city: city)
        })
    }

    @ViewBuilder
    private func navCards(_ current: ProviderWorkspace, city: String) -> some View {
            TeamSettingsNavCard(label: L("On this page")) {
                row(.profile, hint: current.name)
                row(.contact, hint: current.email.nonEmpty ?? current.phone.nonEmpty ?? L("No contact yet"))
                row(.services, hint: LP(current.enabledCategories.count, "1 kind of care", "%d kinds of care"))
                row(.regional, hint: [city, model.store?.currency].compactMap { $0 }.joined(separator: " · "))
                row(.legal, hint: model.setup?.legal?.taxId.nonEmpty ?? L("What prints on your documents"))
                if TeamSettingsAccess.canSeeConsents(workspace) { row(.consents, hint: L("What families sign")) }
                if TeamSettingsAccess.canOpenAi(workspace) { row(.ai, hint: L("A brief on each chart")) }
                row(.notifications, hint: L("Just for you"))
                if TeamSettingsAccess.canSeeHistory(workspace) { row(.history, hint: L("Who changed what")) }
            }
            links(current)
    }

    private func row(_ section: TeamSettingsSection, hint: String) -> some View {
        Button { open(section) } label: {
            TeamSettingsNavRow(title: section.title, hint: hint, icon: section.icon, current: sizeClass == .regular && railSection == section)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func links(_ current: ProviderWorkspace) -> some View {
        let canSeeStaff = workspace.can(.staffView)
        let canSeeRooms = workspace.can(.appointmentsView)
        let canSeePlan = TeamSettingsAccess.canSeePlan(workspace)
        if canSeeStaff || canEdit || canSeeRooms || canSeePlan {
            TeamSettingsNavCard(label: L("With their own page")) {
                if canSeeStaff {
                    link(.staff, L("Staff and access"), hint: model.memberCount.map { LP($0, "1 person", "%d people") } ?? L("Roles and permissions"), icon: "user-round")
                }
                if canEdit {
                    link(.availability, L("Availability"), hint: model.openDays.map { LP($0, "1 day open", "%d days open") } ?? L("When you are open and how visits are booked."), icon: "clock-3")
                }
                if canSeeRooms {
                    link(.rooms, L("Rooms"), hint: model.roomCount.map { LP($0, "1 room", "%d rooms") } ?? L("Where visits happen"), icon: "door-open")
                }
                if canEdit {
                    link(.locations, L("Locations"), hint: LP(workspace.activeLocations.count, "1 active", "%d active"), icon: "map-pin")
                }
                if canSeePlan {
                    link(.billing, L("Subscription"), hint: TeamSettingsAccess.planLine(current), icon: "circle-dollar-sign")
                }
            }
        }
    }

    private func link(_ section: ProviderSection, _ title: String, hint: String, icon: String) -> some View {
        NavigationLink(value: ProviderRoute.section(section)) {
            TeamSettingsNavRow(title: title, hint: hint, icon: icon, external: true)
        }
        .buttonStyle(.plain)
    }
}

/// One Settings section opened from another page (a staff member's online card → Services).
struct TeamSettingsSectionScreen: View {
    /// "profile", "contact", "services", "regional", "legal", "consents", "ai", "notifications" or "history".
    let section: String
    @StateObject private var model = TeamSettingsModel()

    var body: some View {
        TeamSettingsSectionPage(section: TeamSettingsSection(rawValue: section) ?? .services, model: model)
    }
}

/// One section of Settings on its own page: Settings' header on top (the web
/// keeps it over the open section), the read-only note, then the section.
private struct TeamSettingsSectionPage: View {
    let section: TeamSettingsSection
    @ObservedObject var model: TeamSettingsModel
    @EnvironmentObject private var workspace: Workspace
    /// The cards on this page with changes that aren't saved (their titles).
    @State private var unsaved: [String] = []

    var body: some View {
        PageScroll(refresh: { await model.load(workspace) }) {
            TeamSettingsHeader(model: model, open: section)
            if !workspace.can(.workspaceEdit) {
                TeamReadOnlyBanner()
            }
            TeamSettingsSectionBody(section: section, model: model)
        }
        .providerPage(section.title)
        .onPreferenceChange(TeamUnsavedKey.self) { unsaved = $0 }
        // Leaving with unsaved changes asks first (switching sections on the web keeps drafts; here each is a page).
        .modifier(TeamLeaveGuard(dirty: !unsaved.isEmpty, message: LF("Your changes to %@ are not saved yet.", unsaved.joined(separator: ", "))))
        .task { if !model.loaded { await model.load(workspace) } }
    }
}

/// One Settings section's cards (a page of its own on a phone, beside the rail on an iPad).
private struct TeamSettingsSectionBody: View {
    let section: TeamSettingsSection
    @ObservedObject var model: TeamSettingsModel
    @EnvironmentObject private var workspace: Workspace

    var body: some View {
        switch section {
        case .profile: TeamProfileSection(model: model)
        case .contact: TeamContactSection(model: model)
        case .services:
            TeamServicesSection(model: model)
            if workspace.can(.workspaceEdit) { TeamOnlineServicesPanel() }
        case .regional: TeamRegionSection(model: model)
        case .legal: TeamLegalSection(model: model)
        case .consents:
            TeamConsentTemplatesSection(model: model)
        case .ai:
            TeamOlfatoSections()
        case .notifications:
            TeamNotificationsSection()
        case .history:
            if let clinicId = workspace.current?.clinicId {
                AuditHistoryCard(
                    entityType: "clinic",
                    entityId: clinicId,
                    title: L("Change history"),
                    description: L("Who changed the business profile, contact, services, region and money, legal details and Olfato AI, and when."),
                    collapsible: false,
                    emptyText: L("Each save in Settings is listed here, with who made it."),
                    // The parts a change belongs to, by the server's action names (web: settings-history.ts).
                    areas: [
                        AuditArea(key: "profile", label: L("Business profile"), actions: ["clinic.profile.updated", "clinic.logo.updated", "clinic.logo.removed", "clinic.settings.updated"]),
                        AuditArea(key: "contact", label: L("Contact and address"), actions: ["clinic.contact.updated"]),
                        AuditArea(key: "services", label: L("Services you offer"), actions: ["clinic.services.updated"]),
                        AuditArea(key: "regional", label: L("Region and money"), actions: ["clinic.region.updated", "provider_store.settings.updated"]),
                        AuditArea(key: "legal", label: L("Legal details"), actions: ["clinic.legal.updated"]),
                        AuditArea(key: "ai", label: "Olfato AI", actions: ["provider_patient_summary.settings.updated"]),
                    ],
                    openArea: { key in AnyView(TeamSettingsSectionScreen(section: key)) }
                )
            }
        }
    }
}

// MARK: - Business profile

/// The business name and logo, and how families see the business. Both save together.
private struct TeamProfileSection: View {
    @ObservedObject var model: TeamSettingsModel
    @EnvironmentObject private var workspace: Workspace
    @StateObject private var form = FormState()
    @StateObject private var flash = TeamSavedFlash()
    @State private var name = ""
    @State private var started = false
    @State private var logo = PhotoDraft()
    @State private var saving = false

    private var canEdit: Bool { workspace.can(.workspaceEdit) }
    private var savedName: String { workspace.current?.name ?? "" }
    private var dirty: Bool { name.trimmingCharacters(in: .whitespaces) != savedName.trimmingCharacters(in: .whitespaces) || !logo.isEmpty }

    var body: some View {
        let current = workspace.current
        TeamSaveSection(
            title: L("Business profile"),
            subtitle: L("The name and logo families see on visits, bills and messages. Your own account stays separate."),
            systemImage: "building-2",
            tint: Theme.blue,
            look: .settings,
            state: flash.state(saving: saving, dirty: dirty),
            saveLabel: L("Save profile"),
            readOnlyText: canEdit ? nil : L("Only someone who edits the workspace can change this."),
            onSave: canEdit ? { save() } : nil,
            onDiscard: { name = savedName; logo = PhotoDraft(); form.errors = [:] }
        ) {
            FormScroll(form: form) {
                VStack(alignment: .leading, spacing: 16) {
                    PhotoField(label: L("Logo"), hint: canEdit ? L("JPG, PNG or WebP, up to 3 MB. A square one looks best.") : nil, currentURL: current?.logoUrl, draft: $logo,
                               shape: .rounded, allowsRemove: canEdit, addTitle: L("Add a logo"), changeTitle: L("Change logo"), removeTitle: L("Remove the logo"),
                               removedNote: L("The logo is removed when you save."))
                        .disabled(!canEdit || saving)
                    PMTextField(L("Business name"), text: $name, key: "name", form: form, prompt: L("e.g. Veterinaria Luna"), hint: L("As families know you, not the registered legal name."), capitalization: .words, required: true)
                        .disabled(!canEdit || saving)
                    preview(current)
                }
            }
        }
        .onAppear { if !started { name = savedName; started = true } }
        .onChange(of: savedName) { old, new in if name == old { name = new } }
    }

    @ViewBuilder
    private func logoView(_ current: ProviderWorkspace?) -> some View {
        if let image = logo.preview {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.borderSoft, lineWidth: 1))
        } else if !logo.removed, current?.logoUrl != nil {
            Avatar(name: current?.name, imageURL: current?.logoUrl, size: 44)
                .overlay(Circle().strokeBorder(Theme.borderSoft, lineWidth: 1))
        } else {
            IconBadge(icon: "building-2", accent: Theme.blue, size: 44, iconSize: 20)
        }
    }

    /// "How families see you" (web: the preview box beside the fields).
    private func preview(_ current: ProviderWorkspace?) -> some View {
        let rows: [(icon: String, value: String, empty: String)] = [
            ("mail", current?.email ?? "", L("No email yet")),
            ("phone", current?.phone ?? "", L("No phone yet")),
            ("map-pin", current?.address ?? "", L("No address yet")),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            Text(L("How families see you").uppercased()).font(.brandText(10.9, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.inkSoft)
            HStack(spacing: 12) {
                logoView(current)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.nonEmpty ?? current?.name ?? "").font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text(LF("Your role: %@", TeamRole.label(current?.role))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.icon) { row in
                    let value = row.value.trimmingCharacters(in: .whitespaces)
                    HStack(spacing: 8) {
                        Glyph(row.icon, size: 16).foregroundStyle(Theme.blue)
                        Text(value.nonEmpty ?? row.empty)
                            .italic(value.isEmpty)
                            .foregroundStyle(value.isEmpty ? Theme.inkSoft : Theme.inkStrong)
                            .lineLimit(1)
                    }
                    .font(Theme.text(14))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard form.check([("name", trimmed.isEmpty ? L("Add the business name.") : (trimmed.count > 120 ? L("Keep the name under 120 characters.") : nil))]) else { return }
        guard let clinicId = workspace.current?.clinicId else { return }
        saving = true
        Task {
            defer { saving = false }
            // The logo first: if it is refused the name is still unsaved, and Save can be pressed again.
            do {
                if let data = logo.data {
                    let _: EmptyResponse = try await ImageUpload.upload(data, to: "/provider-setup/logo", field: "logo")
                } else if logo.removed {
                    try await API.send("DELETE", "/provider-setup/logo")
                }
                logo = PhotoDraft()
            } catch {
                Toast.error(errorText(error, fallback: L("Could not upload the logo.")))
                return
            }
            if trimmed != savedName {
                do {
                    let _: EmptyResponse = try await API.patch("/provider-workspaces/\(clinicId)", body: ["name": trimmed])
                } catch {
                    form.apply(error, known: ["name": "name"])
                    return
                }
            }
            await model.saved(workspace)
            flash.mark()
        }
    }
}

// MARK: - Contact and address

private struct TeamContactSection: View {
    @ObservedObject var model: TeamSettingsModel
    @EnvironmentObject private var workspace: Workspace
    @StateObject private var form = FormState()
    @StateObject private var flash = TeamSavedFlash()
    @State private var email = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var started = false
    @State private var saving = false

    private var canEdit: Bool { workspace.can(.workspaceEdit) }
    private var saved: (String, String, String) {
        (workspace.current?.email ?? "", workspace.current?.phone ?? "", workspace.current?.address ?? "")
    }
    private var dirty: Bool {
        email.trimmingCharacters(in: .whitespaces) != saved.0.trimmingCharacters(in: .whitespaces)
            || phone.trimmingCharacters(in: .whitespaces) != saved.1.trimmingCharacters(in: .whitespaces)
            || address.trimmingCharacters(in: .whitespaces) != saved.2.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        TeamSaveSection(
            title: L("Contact and address"),
            subtitle: L("How families reach you and where you work. Add at least an email or a phone."),
            systemImage: "mail",
            tint: Theme.aqua,
            look: .settings,
            state: flash.state(saving: saving, dirty: dirty),
            saveLabel: L("Save contact"),
            readOnlyText: canEdit ? nil : L("Only someone who edits the workspace can change this."),
            onSave: canEdit ? { save() } : nil,
            onDiscard: { fill() }
        ) {
            FormScroll(form: form) {
                VStack(alignment: .leading, spacing: 16) {
                    PMTextField(L("Email"), text: $email, key: "email", form: form, prompt: "hola@veterinarialuna.mx", keyboard: .emailAddress)
                    PMTextField(L("Phone"), text: $phone, key: "phone", form: form, keyboard: .phonePad)
                    PMTextField(L("Address or area you serve"), text: $address, key: "address", form: form, prompt: L("e.g. Av. Juárez 120, Centro — or Condesa and Roma"), hint: L("A street address, or the neighbourhoods you visit if you go to the pet."), required: true)
                    if canEdit {
                        NavigationLink(value: ProviderRoute.section(.locations)) {
                            (Text(L("This is your main location’s phone and address. Other locations have their own in")) + Text(" ") + Text(L("Locations")).fontWeight(.semibold).foregroundColor(Theme.blue) + Text("."))
                                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .disabled(!canEdit || saving)
            }
        }
        .onAppear { if !started { fill(); started = true } }
    }

    private func fill() {
        email = saved.0; phone = saved.1; address = saved.2
        form.errors = [:]
    }

    private func save() {
        let e = email.trimmingCharacters(in: .whitespaces), p = phone.trimmingCharacters(in: .whitespaces), a = address.trimmingCharacters(in: .whitespaces)
        let digits = p.filter(\.isNumber).count
        var emailError: String? = nil
        if !e.isEmpty && e.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) == nil { emailError = L("Check the email address.") }
        if e.isEmpty && p.isEmpty { emailError = L("Add an email or a phone so families can reach you.") }
        let phoneError = !p.isEmpty && (digits < 8 || digits > 15) ? L("Finish the phone number, or leave it empty.") : nil
        let addressError = a.isEmpty ? L("Add the address or the area you serve.") : (a.count < 5 ? L("Write at least 5 characters.") : (a.count > 240 ? L("Keep the address under 240 characters.") : nil))
        guard form.check([("email", emailError), ("phone", phoneError), ("address", addressError)]) else { return }
        guard let clinicId = workspace.current?.clinicId else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                // The server needs the name on every change; send the saved one.
                let _: EmptyResponse = try await API.patch("/provider-workspaces/\(clinicId)", body: ["name": workspace.current?.name ?? "", "email": e.nonEmpty, "phone": p.nonEmpty, "address": a])
                await model.saved(workspace)
                flash.mark()
            } catch {
                form.apply(error, known: ["email": "email", "phone": "phone", "address": "address"])
            }
        }
    }
}
