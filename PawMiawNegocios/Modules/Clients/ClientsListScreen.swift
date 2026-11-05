//
//  ClientsListScreen.swift
//  PawMiawNegocios
//
//  Clientes y pacientes (web: routes/provider.clients.tsx): the families and
//  their pets on one page, seen by client (every pet on the row) or by
//  patient (every pet, its owner on the row). Patients is the same page in
//  its Patients view (web: provider.patients.tsx redirects there).
//
//  As on the web: the module header (lime, its numbers are the filters),
//  then one card — Clientes/Pacientes tabs, the search and the sort, the
//  wash filter chips, the "Vencen esta semana" strip — and the rows. A phone
//  reads the web's table as rows: avatar, name and tags, the pets as chips
//  under them, then the table's other columns in its uppercase head style.
//  20 at a time with infinite scroll (not the web's pages); every number is
//  the server's.
//

import SwiftUI

enum ClientsDirectoryView: String, Hashable { case clients, patients }

private enum ClientsQuickFilter: String, Hashable { case leads, active, owing, due, archived }

private enum ClientsSort: String, CaseIterable { case recent, name, last_visit }

struct ClientsScreen: View {
    @AppStorage("pawmiaw.provider.clients.view") private var storedView = ClientsDirectoryView.clients.rawValue

    var body: some View {
        ClientsDirectory(initialView: ClientsDirectoryView(rawValue: storedView) ?? .clients) { storedView = $0.rawValue }
    }
}

/// Pacientes: the directory in its Patients view.
struct PatientsScreen: View {
    var body: some View {
        ClientsDirectory(initialView: .patients) { _ in }
    }
}

private struct ClientsDirectory: View {
    let initialView: ClientsDirectoryView
    let remember: (ClientsDirectoryView) -> Void

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var view: ClientsDirectoryView
    @State private var query = ""
    @State private var search = ""
    @State private var sort: ClientsSort = .recent
    // Clients: one quick filter at a time, and who looks after them.
    @State private var filter: ClientsQuickFilter?
    @State private var assignee = "all"
    // Patients: the filters add up.
    @State private var species: String?
    @State private var lastVisit: String?
    @State private var vaccinesOverdue = false
    @State private var linked: Bool?
    @State private var archivedPets = false

    @State private var summary: ClientsDirectorySummary?
    @State private var patientSummary: ClientsPatientsSummary?
    @State private var members: [ClientsMember] = []
    @State private var creating = false
    @State private var bulkInviting = false
    @State private var inviteOne: ClientsClient?
    @State private var openClient: String?
    @State private var route: ProviderRoute?
    @State private var suggestions: [ClientsMatchSuggestion] = []
    @State private var reviewingMatches = false

    @StateObject private var clients = Pager<ClientsClient> { _, _ in Page(items: [], total: 0) }
    @StateObject private var patients = Pager<ClientsPatientRow> { _, _ in Page(items: [], total: 0) }

    init(initialView: ClientsDirectoryView, remember: @escaping (ClientsDirectoryView) -> Void) {
        self.initialView = initialView
        self.remember = remember
        _view = State(initialValue: initialView)
    }

    private var canAssignAnyone: Bool { workspace.can(.clientsAssignAnyone) }
    private var canView: Bool { workspace.can(.clientsView) && (workspace.can(.clientsAssignSelf) || canAssignAnyone) }
    private var canCreate: Bool { workspace.can(.clientsCreate) && workspace.can(.petsCreate) && (workspace.can(.clientsAssignSelf) || canAssignAnyone) }
    private var canEditClients: Bool { workspace.can(.clientsEdit) }
    /// What a client owes is money, level 1 (docs/money-access-levels.md).
    private var canSeeOwed: Bool { workspace.moneyLevel >= .charging }
    private var needle: String { search.trimmingCharacters(in: .whitespaces) }
    private var patientQuickFiltered: Bool { lastVisit != nil || vaccinesOverdue || linked != nil || archivedPets }
    private var patientFiltered: Bool { patientQuickFiltered || species != nil }
    private var noClientsYet: Bool { summary?.clients == 0 }

    var body: some View {
        Group {
            if workspace.inSetup {
                PageScroll {
                    EmptyState(systemImage: "loader-circle", title: L("Finish workspace setup before opening clients."), message: L("The client directory belongs to a workspace. Finish its basics first."), accent: Theme.lime, panel: true)
                }
            } else if !canView {
                PageScroll { NoAccessState(message: L("Ask the workspace owner to let your role see clients.")) }
            } else {
                content
            }
        }
        .providerPage(L("Clients & patients"), root: true)
        .sheet(isPresented: $creating) {
            ClientsCreateSheet(onOpenClient: { id in
                Task { try? await Task.sleep(for: .milliseconds(350)); openClient = id }
            }) { client in openClient = client.id }
        }
        .sheet(isPresented: $bulkInviting) {
            ClientsBulkInviteSheet { client in
                bulkInviting = false
                Task { try? await Task.sleep(for: .milliseconds(450)); inviteOne = client }
            }
        }
        .sheet(item: $inviteOne) { client in ClientsInviteSheet(client: client) }
        .sheet(isPresented: $reviewingMatches) {
            ClientsMatchReviewSheet(suggestions: suggestions, canEdit: canEditClients, onAnswered: { suggestions = await ClientsMatches.load() })
        }
        .navigationDestination(item: $openClient) { id in ClientDetailScreen(clientId: id) }
        .navigationDestination(item: $route) { RouteView(route: $0) }
        .reloadsOnScope { await reloadAll() }
        // The client search's one rule: the server searches from two letters, 250 ms after typing.
        .debounced(query) { value in
            let next = ClientSearch.query(value) ?? ""
            guard next != search else { return }
            search = next
            await reloadList()
        }
    }

    // MARK: Page

    private var content: some View {
        PageScroll(refresh: { await reloadAll() }) {
            header
            if noClientsYet {
                EmptyState(systemImage: "paw-print", title: L("Add your first client and pet"),
                           message: L("Create the first provider client and pet here. After that, appointments, records, invoices, and care history can start from the same profile."),
                           actionTitle: canCreate ? L("Add client and pet") : nil, action: { creating = true }, accent: Theme.lime, panel: true)
            } else {
                directoryCard
            }
        }
    }

    /// The web's `ProviderModuleHeader`: lime, "Invitar a PawMiaw" and "Agregar cliente y mascota",
    /// and the numbers that follow the view (each one is the filter it names).
    private var header: some View {
        ModuleHeader(
            icon: "users-round",
            title: L("Clients & patients"),
            subtitle: L("Families and their pets — look them up by either."),
            accent: Theme.lime,
            stats: headerStats,
            storageKey: "clients"
        ) {
            if canEditClients && !noClientsYet {
                PMButton(L("Invite to PawMiaw"), systemImage: "mail-plus", variant: .outline) { bulkInviting = true }
            }
            if canCreate {
                PMButton(L("Add client and pet"), systemImage: "users-round") { creating = true }
            }
        }
    }

    private var headerStats: [ModuleStat] {
        var stats: [ModuleStat] = []
        if view == .clients, let summary {
            stats.append(ModuleStat("clients", label: L("Clients"), value: "\(summary.clients ?? 0)", icon: "users-round", accent: Theme.lime,
                                    active: filter == nil, action: { setFilter(nil) }))
            stats.append(ModuleStat("patients", label: L("Patients"), value: "\(summary.pets ?? 0)", icon: "paw-print", accent: Theme.aqua,
                                    action: { switchView(.patients) }))
            let due = summary.dueThisWeek ?? 0
            stats.append(ModuleStat("due", label: L("Due this week"), value: "\(due)", hint: L("Vaccines, rechecks and follow-ups"), icon: "bell-ring", accent: Theme.mango,
                                    attention: due > 0, active: filter == .due, action: { toggle(.due) }))
            if canSeeOwed, let owing = summary.owing {
                stats.append(ModuleStat("owing", label: L("Owe money"), value: "\(owing)", icon: "circle-dollar-sign", accent: Theme.pink,
                                        attention: owing > 0, active: filter == .owing, action: { toggle(.owing) }))
            }
        } else if view == .patients, let summary = patientSummary {
            let pets = summary.pets ?? 0
            stats.append(ModuleStat("patients", label: L("Patients"), value: "\(pets)", icon: "paw-print", accent: Theme.aqua,
                                    active: !patientFiltered && needle.isEmpty, action: { clearPatientFilters() }))
            let overdue = summary.vaccinesOverdue ?? 0
            stats.append(ModuleStat("vaccines", label: L("Vaccines overdue"), value: "\(overdue)", icon: "syringe", accent: Theme.mango,
                                    attention: overdue > 0, active: vaccinesOverdue, action: { vaccinesOverdue.toggle(); reload() }))
            stats.append(ModuleStat("recent", label: L("Seen in 30 days"), value: "\(summary.seenLast30Days ?? 0)", icon: "calendar-check", accent: Theme.blue,
                                    active: lastVisit == "30d", action: { lastVisit = lastVisit == "30d" ? nil : "30d"; reload() }))
            let onPawMiaw = summary.linked ?? 0
            stats.append(ModuleStat("linked", label: L("On PawMiaw"), value: "\(onPawMiaw)",
                                    hint: pets > 0 ? LF("%d%% of patients", Int((Double(onPawMiaw) / Double(pets) * 100).rounded())) : nil,
                                    icon: "link-2", accent: Theme.lime, active: linked == true, action: { linked = linked == true ? nil : true; reload() }))
        }
        if !suggestions.isEmpty, !stats.isEmpty {
            // The same family or pet entered twice: the whole business's open suggestions.
            stats.append(ModuleStat("matches", label: L("Possible matches"), value: "\(suggestions.count)",
                                    hint: canEditClients ? L("Same family or pet twice? Review them") : L("Same family or pet twice?"),
                                    icon: "git-merge", accent: Theme.coral, attention: true, active: reviewingMatches, action: { reviewingMatches = true }))
        }
        return stats
    }

    // MARK: The card: toolbar, filters, rows, count

    private var directoryCard: some View {
        Card(padding: 0, spacing: 0) {
            toolbarRow
            RowDivider()
            filterRow
            RowDivider()
            if filter == .due && view == .clients {
                dueStrip
                RowDivider()
            }
            list
        }
    }

    /// Clientes/Pacientes, the search, the sort (stacked on a phone, one line on an iPad).
    private var toolbarRow: some View {
        let tabs = Segmented(options: [
            .init(ClientsDirectoryView.clients, L("Clients"), icon: "users-round"),
            .init(ClientsDirectoryView.patients, L("Patients"), icon: "paw-print"),
        ], selection: Binding(get: { view }, set: { switchView($0) }), look: .raised, label: L("View"))
        let field = SearchField(prompt: view == .clients ? L("Client, pet, email or phone") : L("Pet, owner, phone or microchip"), text: $query, height: 40)
        return Group {
            if sizeClass == .regular {
                HStack(spacing: 12) { tabs; field; sortMenu }
            } else {
                VStack(alignment: .leading, spacing: 12) { tabs; field; sortMenu }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var sortMenu: some View {
        Menu {
            Picker(L("Sort"), selection: Binding(get: { sort }, set: { sort = $0; reload() })) {
                Text(L("Recently added")).tag(ClientsSort.recent)
                Text(L("Name")).tag(ClientsSort.name)
                Text(L("Last visit")).tag(ClientsSort.last_visit)
            }
        } label: {
            PillField(text: sortTitle, height: 40)
        }
        .disabled(!needle.isEmpty)
        .opacity(needle.isEmpty ? 1 : 0.5)
        .accessibilityLabel(L("Sort"))
    }

    private var sortTitle: String {
        switch sort {
        case .recent: L("Recently added")
        case .name: L("Name")
        case .last_visit: L("Last visit")
        }
    }

    /// The quick filters in the colours the rows and the header's numbers use;
    /// then who looks after them (clients) or which pets (patients).
    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if view == .clients { clientChips } else { patientChips }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .padding(.vertical, 10)
    }

    private var chipRule: some View {
        Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 24).padding(.horizontal, 4)
    }

    @ViewBuilder
    private var clientChips: some View {
        FilterChip(title: L("All"), isSelected: filter == nil, tone: Theme.blue) { setFilter(nil) }
        FilterChip(title: L("Leads"), isSelected: filter == .leads, tone: Theme.lavender, dot: Theme.lavender) { toggle(.leads) }
        FilterChip(title: L("Active clients"), isSelected: filter == .active, tone: Theme.lime, dot: Theme.lime) { toggle(.active) }
        if canSeeOwed {
            FilterChip(title: L("Owe money"), isSelected: filter == .owing, tone: Theme.pink, icon: "circle-dollar-sign") { toggle(.owing) }
        }
        FilterChip(title: L("Due this week"), isSelected: filter == .due, tone: Theme.mango, icon: "bell-ring") { toggle(.due) }
        // The archived ones are off every other filter: this is where they are found (and restored from their page).
        if (summary?.archived ?? 0) > 0 || filter == .archived {
            FilterChip(title: L("Archived"), isSelected: filter == .archived, tone: Theme.inkSoft, icon: "archive") { toggle(.archived) }
        }
        if canAssignAnyone {
            chipRule
            Menu {
                Picker(L("Assignee"), selection: Binding(get: { assignee }, set: { assignee = $0; reload() })) {
                    Text(L("Anyone")).tag("all")
                    Text(L("Unassigned")).tag("unassigned")
                    ForEach(members) { member in
                        Text(member.isCurrentMember == true ? "\(member.label) (\(L("You")))" : member.label).tag(member.id)
                    }
                }
            } label: {
                FilterMenuLabel(title: assigneeTitle, selected: assignee != "all")
            }
            .accessibilityLabel(L("Assignee"))
        }
    }

    private var assigneeTitle: String {
        switch assignee {
        case "all": L("Anyone")
        case "unassigned": L("Unassigned")
        default: members.first(where: { $0.id == assignee })?.label ?? L("Anyone")
        }
    }

    @ViewBuilder
    private var patientChips: some View {
        FilterChip(title: L("All"), isSelected: !patientQuickFiltered, tone: Theme.aqua) {
            lastVisit = nil; vaccinesOverdue = false; linked = nil; archivedPets = false; reload()
        }
        FilterChip(title: L("Vaccines overdue"), isSelected: vaccinesOverdue, tone: Theme.mango, icon: "syringe") { vaccinesOverdue.toggle(); reload() }
        FilterChip(title: L("Seen in 30 days"), isSelected: lastVisit == "30d", tone: Theme.blue, icon: "calendar-check") { lastVisit = lastVisit == "30d" ? nil : "30d"; reload() }
        FilterChip(title: L("On PawMiaw"), isSelected: linked == true, tone: Theme.lime, icon: "link-2") { linked = linked == true ? nil : true; reload() }
        FilterChip(title: L("Not on PawMiaw"), isSelected: linked == false, tone: Theme.lavender, dot: Theme.lavender) { linked = linked == false ? nil : false; reload() }
        if (patientSummary?.archived ?? 0) > 0 || archivedPets {
            FilterChip(title: L("Archived"), isSelected: archivedPets, tone: Theme.inkSoft, icon: "archive") { archivedPets.toggle(); reload() }
        }
        chipRule
        Segmented(options: [
            .init("", L("All")),
            .init("dog", L("Dogs")),
            .init("cat", L("Cats")),
            .init("other", L("Others")),
        ], selection: Binding(get: { species ?? "" }, set: { species = $0.isEmpty ? nil : $0; reload() }), look: .raised, label: L("Species"))
        // The other last-visit ranges ("over a year ago", "never seen") are rarer than a chip each deserves.
        Menu {
            Picker(L("Last visit"), selection: Binding(get: { lastVisit ?? "" }, set: { lastVisit = $0.isEmpty ? nil : $0; reload() })) {
                Text(L("Any last visit")).tag("")
                ForEach(Self.ranges, id: \.0) { range in Text(range.1).tag(range.0) }
            }
        } label: {
            FilterMenuLabel(title: lastVisit.flatMap { key in Self.ranges.first(where: { $0.0 == key })?.1 } ?? L("Any last visit"), selected: lastVisit != nil)
        }
        .accessibilityLabel(L("Last visit"))
    }

    private static var ranges: [(String, String)] {
        [("30d", L("Last 30 days")), ("90d", L("Last 3 months")), ("1y", L("Last year")), ("over_1y", L("Over a year ago")), ("never", L("Never seen"))]
    }

    /// "Vencen esta semana": a mango band with the way to Due.
    private var dueStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Clients with a vaccine, recheck or follow-up due within a week, or overdue."))
                .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
            Button { route = .section(.due) } label: {
                HStack(spacing: 4) {
                    Text(L("Remind and book from Due"))
                    Glyph("chevron-right", size: 16)
                }
                .font(Theme.text(14, weight: .bold))
                .foregroundStyle(Theme.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(Theme.mango, 12))
    }

    // MARK: Rows

    @ViewBuilder
    private var list: some View {
        if view == .clients {
            ClientsCardRows(pager: clients, empty: { clientsEmpty }) { client in
                ClientsClientRow(client: client, needle: needle.lowercased(), showOwed: canSeeOwed) { openClient = client.id }
            }
            countFooter(clients.total, isLoading: clients.isLoading, loaded: clients.loadedOnce && !clients.items.isEmpty) { LP($0, "%d client", "%d clients") }
        } else {
            ClientsCardRows(pager: patients, empty: { patientsEmpty }) { pet in
                ClientsPatientRowView(pet: pet) { route = .clientPet(clientId: pet.client.id, petId: pet.id) }
            }
            countFooter(patients.total, isLoading: patients.isLoading, loaded: patients.loadedOnce && !patients.items.isEmpty) { LP($0, "%d patient", "%d patients") }
        }
    }

    /// How many, under the list (as the Agenda does): the server's total.
    @ViewBuilder
    private func countFooter(_ total: Int?, isLoading: Bool, loaded: Bool, text: (Int) -> String) -> some View {
        if loaded, let total, total > 0 {
            RowDivider()
            Text(isLoading ? L("Updating…") : text(total))
                .font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var clientsEmpty: some View {
        let title: String
        if !needle.isEmpty { title = LF("Nothing matches “%@”", needle) }
        else {
            switch filter {
            case .owing: title = L("Nobody owes money")
            case .due: title = L("Nobody is due this week")
            case .leads: title = L("No leads right now")
            case .active: title = L("No active clients yet")
            case .archived: title = L("Nobody is archived")
            case nil: title = L("Nobody here yet")
            }
        }
        let message: String
        if filter == .leads || filter == .active, needle.isEmpty { message = L("A lead becomes active after a first visit, stay or payment.") }
        else if filter == .archived, needle.isEmpty { message = L("Archived clients and pets show here. They can be restored from their page.") }
        else if filter != nil { message = L("Try another filter, or show everyone.") }
        else { message = L("Try the pet’s name, or switch to Patients.") }
        let icon = !needle.isEmpty ? "search" : filter == .owing ? "circle-dollar-sign" : filter == .due ? "bell-ring" : "users-round"
        return EmptyState(systemImage: icon, title: title, message: message, actionTitle: filter != nil ? L("Show everyone") : nil, action: { setFilter(nil) }, accent: Theme.lime)
    }

    private var patientsEmpty: some View {
        let searching = !needle.isEmpty || patientFiltered
        return EmptyState(
            systemImage: needle.isEmpty ? "paw-print" : "search",
            title: !needle.isEmpty ? LF("Nothing matches “%@”", needle) : patientFiltered ? L("No pets match these filters") : L("No patients yet"),
            message: searching ? L("Try the owner’s name, a phone or the microchip, or clear the filters.") : L("Pets appear here when you add a client or a family connects."),
            actionTitle: searching ? L("Clear filters") : nil,
            action: { clearPatientFilters() },
            accent: Theme.lime
        )
    }

    // MARK: Filters

    private func toggle(_ next: ClientsQuickFilter) { setFilter(filter == next ? nil : next) }

    private func setFilter(_ next: ClientsQuickFilter?) {
        filter = next
        reload()
    }

    private func switchView(_ next: ClientsDirectoryView) {
        guard next != view else { return }
        view = next
        remember(next)
        if next == .patients { filter = nil } else { species = nil; lastVisit = nil; vaccinesOverdue = false; linked = nil; archivedPets = false }
        Task { await reloadAll() }
    }

    private func clearPatientFilters() {
        query = ""; search = ""
        species = nil; lastVisit = nil; vaccinesOverdue = false; linked = nil; archivedPets = false
        reload()
    }

    private func reload() { Task { await reloadList() } }

    // MARK: Loading

    private func reloadAll() async {
        guard canView, !workspace.inSetup else { return }
        async let list: Void = reloadList()
        if view == .clients {
            summary = try? await API.get("/provider-directory/summary")
        } else {
            if summary == nil { summary = try? await API.get("/provider-directory/summary") }
            patientSummary = try? await API.get("/provider-patients/summary")
        }
        if canAssignAnyone, members.isEmpty { members = await ClientsMembers.load() }
        suggestions = await ClientsMatches.load()
        await list
    }

    private func reloadList() async {
        let location = workspace.listLocationFilter
        let q = needle.nonEmpty
        let sortValue = sort.rawValue
        if view == .clients {
            let status: String? = switch filter {
            case .leads: "lead"
            case .active: "active"
            case .archived: "archived"
            default: nil
            }
            let owing = filter == .owing && canSeeOwed
            let due = filter == .due
            let assigned = canAssignAnyone && assignee != "all" && assignee != "unassigned" ? assignee : nil
            let unassigned = canAssignAnyone && assignee == "unassigned"
            clients.fetch = { offset, limit in
                try await API.get("/provider-clients", query: [
                    "limit": "\(limit)", "offset": "\(offset)", "search": q, "sort": sortValue,
                    "owing": owing ? "true" : nil, "due": due ? "true" : nil, "status": status,
                    "includeArchived": q != nil ? "true" : nil,
                    "assignedOrganizationMemberId": assigned, "unassigned": unassigned ? "true" : nil,
                    "locationId": location,
                ])
            }
            await clients.reload()
        } else {
            let speciesValue = species
            let lastVisitValue = lastVisit
            let vaccines = vaccinesOverdue
            let archived = archivedPets
            let linkedValue = linked
            patients.fetch = { offset, limit in
                try await API.get("/provider-patients", query: [
                    "limit": "\(limit)", "offset": "\(offset)", "search": q, "sort": sortValue,
                    "species": speciesValue, "lastVisit": lastVisitValue,
                    "vaccines": vaccines ? "overdue" : nil, "archived": archived ? "true" : nil,
                    "linked": linkedValue.map { $0 ? "true" : "false" }, "locationId": location,
                ])
            }
            await patients.reload()
        }
    }
}

// MARK: - Rows inside a card

/// A paged list drawn inside a card: rows edge to edge with hairlines between
/// them, 20 at a time with infinite scroll (the kit's `PagedContent` spaces
/// its rows apart as cards; this one is the web's table body).
private struct ClientsCardRows<Item: Decodable & Identifiable, Row: View, Empty: View>: View {
    @ObservedObject var pager: Pager<Item>
    @ViewBuilder let empty: () -> Empty
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        if !pager.loadedOnce && pager.isLoading {
            LoadingState()
        } else if let error = pager.error, pager.items.isEmpty {
            ErrorState(message: error) { await pager.reload() }
        } else if pager.items.isEmpty {
            empty()
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(pager.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowDivider() }
                    row(item).onAppear { pager.loadMoreIfNeeded(item) }
                }
                PagerFooter(pager: pager)
            }
        }
    }
}

/// One of the table's columns under a phone row: its uppercase head, then the value.
private struct ClientsRowFact<Value: View>: View {
    let label: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.brandText(10.6, weight: .heavy))
                .tracking(1.27)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
                .fixedSize()
            value()
        }
    }
}

// MARK: - Shared pieces (the client's status, the PawMiaw badge, a pet chip)

/// "Prospecto" / "Archivado": shown only when a client is not simply active (web
/// `ClientStatusPill`): the kit's tag in the status's tone, a lead lavender, the rest grey.
func clientsStatusTag(_ status: String?, deceased: Bool = false) -> TagChip? {
    let text: String? = switch status {
    case "lead": L("Lead")
    case "archived": deceased ? L("Deceased") : L("Archived")
    case "inactive": L("Inactive")
    default: nil
    }
    return text.map { TagChip(text: $0, tone: status == "lead" ? Theme.lavender : Theme.borderSoft) }
}

/// "Familia vinculada" / "Solo en la clínica" (web provider-client-link-badge, xs): the one badge
/// for whether a client's family is on PawMiaw, on Clients' pages and on Records'.
struct ClientsLinkBadge: View {
    let linked: Bool
    var body: some View {
        TagChip(text: linked ? L("Linked household") : L("Clinic-only"), icon: linked ? "link-2" : "building-2", linked: linked)
            .accessibilityHint(linked ? L("This client is attached to a real Paw Miaw household.") : L("This client only exists inside this clinic workspace."))
    }
}

// MARK: - A client row

/// One row per family (web `ClientRows`): the 40 initials, the name in 14
/// bold, the status pill and the PawMiaw badge; every pet as a chip that opens
/// its chart; then the table's other columns. The whole row opens the client.
private struct ClientsClientRow: View {
    let client: ClientsClient
    let needle: String
    let showOwed: Bool
    let open: () -> Void

    var body: some View {
        // An archived client's pets are archived with it: they are still its pets.
        let pets = client.isArchived ? client.allPets : client.allPets.filter { !$0.isArchived }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Avatar(name: client.ownerName, imageURL: client.photoUrl, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(client.ownerName).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    FlowLayout(spacing: 4) {
                        clientsStatusTag(client.status)
                        ClientsLinkBadge(linked: client.isLinked)
                    }
                }
                Spacer(minLength: 8)
                Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
            }
            VStack(alignment: .leading, spacing: 10) {
                if pets.isEmpty {
                    Text("—").font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(pets) { pet in
                            NavigationLink(value: ProviderRoute.clientPet(clientId: client.id, petId: pet.id)) {
                                PetChip(name: pet.petName, species: pet.petSpecies, photoURL: pet.photoUrl, highlighted: !needle.isEmpty && pet.petName.lowercased().contains(needle))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint([ClientsText.species(pet.petSpecies), pet.petBreed?.nonEmpty].compactMap { $0 }.joined(separator: " · "))
                        }
                    }
                }
                // The table's columns: each head reads in full ("ÚLTIMA VISITA"); they wrap rather than cut.
                HStack(alignment: .top, spacing: 12) {
                    FlowLayout(spacing: 16, lineSpacing: 8) {
                        ClientsRowFact(label: L("Last visit")) {
                            Text(client.activity?.lastVisitAt == nil ? "—" : ClientsText.shortDay(client.activity?.lastVisitAt))
                                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        }
                        ClientsRowFact(label: L("Next visit")) {
                            if let next = client.activity?.nextVisitAt {
                                Text(ClientsText.shortDay(next)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            } else {
                                Text("—").font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                            }
                        }
                        if showOwed {
                            ClientsRowFact(label: L("Owes")) {
                                if let owed = client.activity?.owedAmount, owed > 0 {
                                    Text(Money.format(owed, currency: client.activity?.currency)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.destructive)
                                } else {
                                    Text("—").font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ContactButtons(phone: client.ownerPhone)
                }
                if let notes = client.notes?.nonEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Glyph("sticky-note", size: 12)
                        Text(notes).lineLimit(2)
                    }
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.leading, 52)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityAction(named: LF("Open %@", client.ownerName), open)
    }
}

// MARK: - A patient row

/// One row per patient, its owner under it (web `PatientRows`): the 40 face,
/// the name in 14 bold with "Alergia", "Archivada" and "Vacuna vencida", the
/// profile line; then the owner and the table's other columns. The row opens
/// the chart; the owner opens the client.
private struct ClientsPatientRowView: View {
    let pet: ClientsPatientRow
    let open: () -> Void

    var body: some View {
        let activity = pet.activity
        let next = ClientsNext.of(activity)
        let allergies = activity?.allergies ?? []
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                PetAvatar(name: pet.petName, species: pet.petSpecies, photoURL: pet.photoUrl, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    FlowLayout(spacing: 6) {
                        Text(pet.petName).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        if !allergies.isEmpty {
                            Chip(text: L("Allergy"), tone: .danger, icon: "triangle-alert")
                                .accessibilityValue(allergies.joined(separator: ", "))
                        }
                        if pet.status == "archived" {
                            Chip(text: pet.deceasedAt != nil ? L("Deceased") : L("Archived"), tone: .muted, icon: "archive")
                        }
                        if pet.vaccinesOverdue == true {
                            Chip(text: L("Vaccine overdue"), tone: .warn, icon: "syringe")
                        }
                    }
                    let line = [ClientsText.species(pet.petSpecies), pet.petBreed?.nonEmpty, ClientsText.age(pet.birthDate), pet.microchipNumber.map { LF("Chip %@", $0) }].compactMap { $0 }.joined(separator: " · ")
                    if !line.isEmpty {
                        Text(line).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    NavigationLink(value: ProviderRoute.client(pet.client.id)) {
                        HStack(spacing: 8) {
                            Avatar(name: pet.client.name, imageURL: pet.client.photoUrl, size: 28)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(pet.client.name ?? "—").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                if pet.linked == true {
                                    HStack(spacing: 4) {
                                        Glyph("link-2", size: 12)
                                        Text("PawMiaw")
                                    }
                                    .font(Theme.text(12, weight: .bold))
                                    .foregroundStyle(Theme.blue)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    ContactButtons(phone: pet.client.phone)
                }
                FlowLayout(spacing: 16, lineSpacing: 8) {
                    ClientsRowFact(label: L("Last visit")) {
                        Text(activity?.lastVisitAt == nil ? L("Never") : ClientsText.shortDay(activity?.lastVisitAt))
                            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    }
                    ClientsRowFact(label: L("Coming up")) {
                        if let next {
                            (Text(ClientsText.shortDay(next.at)).font(Theme.text(14, weight: .bold)).foregroundStyle(next.late ? Theme.destructive : Theme.inkStrong)
                             + Text(" · \(next.what)").font(Theme.text(14)).foregroundStyle(Theme.inkSoft))
                                .lineLimit(1)
                        } else {
                            Text("—").font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
            .padding(.leading, 52)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityAction(named: LF("Open %@", pet.petName), open)
    }
}

/// What comes next for a pet: its next visit or the next thing due, whichever is sooner.
enum ClientsNext {
    struct Entry { let at: String; let what: String; let isVisit: Bool; let late: Bool }

    static func of(_ activity: ClientsPetActivity?) -> Entry? {
        guard let activity else { return nil }
        if let visit = activity.nextVisitAt, activity.nextDueAt == nil || visit < (activity.nextDueAt ?? "") {
            return Entry(at: visit, what: L("Visit"), isVisit: true, late: false)
        }
        if let due = activity.nextDueAt {
            let what = activity.nextDueTitle.map { ClientsText.followUpTitle($0) } ?? L("Follow-up")
            return Entry(at: due, what: what, isVisit: false, late: ClientsText.isPast(due))
        }
        return nil
    }
}
