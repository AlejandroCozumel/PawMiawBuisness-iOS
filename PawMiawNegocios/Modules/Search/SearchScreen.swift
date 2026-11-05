//
//  SearchScreen.swift
//  PawMiawNegocios
//
//  The workspace's global search (web components/app/search/provider-search.tsx,
//  the palette): the search box with Cerrar on top, then — before typing — what
//  this device remembers, the quick actions and the pages this member may open;
//  once typed, patients, patients in the hospital, clients, visits and bills
//  from `GET /provider-search` (each group only when the role opens it, with
//  "see all" when there are more), then the actions that match. Under two
//  characters nothing is asked; the last answer stays while the next loads.
//  Return opens the highlighted row (the first one); a hardware keyboard's
//  ↑ ↓ move it and Esc closes.
//

import SwiftUI

struct SearchScreen: View {
    /// Where the chosen row leads; nil = closed without choosing.
    let onLeave: (SearchDestination?) -> Void

    @EnvironmentObject private var workspace: Workspace
    @EnvironmentObject private var session: SessionStore
    @State private var text = ""
    @State private var debounced = ""
    @State private var response: SearchResponse?
    /// Whose answer it is: another business's never shows.
    @State private var responseClinic: String?
    @State private var fetching = false
    /// The words whose search failed (after one retry).
    @State private var failedQuery: String?
    @State private var retries = 0
    @State private var recents = SearchRecents()
    /// The highlighted row; nil = the first.
    @State private var activeKey: String?
    @FocusState private var fieldFocused: Bool

    private var clinicId: String? { workspace.current?.clinicId }
    private var storageKey: String { SearchRecents.key(userId: session.user?.id, clinicId: clinicId) }
    private var allowed: Set<SearchResultGroup> { SearchRules.allowedGroups(workspace) }
    private var canSearch: Bool { !allowed.isEmpty }
    private var typed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var debouncedQuery: String? { SearchText.searchable(debounced) }
    private var fetchKey: String { "\(clinicId ?? "")|\(debouncedQuery ?? "")|\(retries)" }

    /// An answer for other words (kept while the next one loads) still shows; one for no words doesn't.
    private var results: SearchResponse? {
        guard SearchText.searchable(text) != nil, canSearch, responseClinic == clinicId else { return nil }
        return response
    }

    private var waiting: Bool {
        SearchText.searchable(text) != nil && canSearch && (typed != debounced.trimmingCharacters(in: .whitespacesAndNewlines) || fetching)
    }

    private var isError: Bool { failedQuery != nil && failedQuery == debouncedQuery }

    private var groups: [SearchOptionGroup] {
        let visible = SearchRecents(items: recents.items.filter { allowed.contains($0.kind.group) }, queries: recents.queries)
        return SearchRules.groups(
            text: text,
            results: results,
            actions: SearchRules.availableActions(workspace),
            recents: visible,
            moreGroups: SearchRules.moreGroups(workspace),
            translated: { L($0) }
        )
    }

    var body: some View {
        let groups = self.groups
        let options = groups.flatMap(\.options)
        let activeID = options.first(where: { $0.id == activeKey })?.id ?? options.first?.id

        VStack(spacing: 0) {
            header(options: options, activeID: activeID)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        status
                        ForEach(groups) { group in
                            groupView(group, activeID: activeID)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: activeKey) { _, key in
                    if let key { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(key) } }
                }
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .onChange(of: text) { _, value in
            if value.count > 100 { text = String(value.prefix(100)) }
            // A new text starts at the top.
            activeKey = nil
        }
        // Keeps the highlighted row when the list changes under it (results arriving), else the first.
        .onChange(of: options.map(\.id)) { _, ids in
            if let key = activeKey, !ids.contains(key) { activeKey = nil }
        }
        .task(id: text) {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            debounced = text
        }
        .task(id: fetchKey) { await fetch() }
        .task(id: storageKey) { recents = SearchRecents.read(storageKey) }
        .task {
            // After the cover has slid in, so the keyboard comes up with it.
            try? await Task.sleep(for: .milliseconds(350))
            fieldFocused = true
        }
    }

    // MARK: The box

    private func header(options: [SearchOption], activeID: String?) -> some View {
        HStack(spacing: 8) {
            SearchField(prompt: L("Search patients, clients, visits, invoices…"), text: $text)
                .focused($fieldFocused)
                .submitLabel(.go)
                .onSubmit {
                    if let option = options.first(where: { $0.id == activeID }) { choose(option) }
                }
                .overlay(alignment: .leading) {
                    // While it looks, a spinner stands where the magnifier is.
                    if waiting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.blue)
                            .frame(width: 18, height: 18)
                            .background(Theme.inputFill, in: Circle())
                            .padding(.leading, 15)
                            .allowsHitTesting(false)
                    }
                }
                .onKeyPress(.downArrow) {
                    move(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    move(-1)
                    return .handled
                }
            Button { onLeave(nil) } label: {
                Text(L("Close"))
                    .font(Theme.text(14, weight: .bold))
                    .foregroundStyle(Theme.blueText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSoft).frame(height: 1) }
    }

    // MARK: Above the rows

    @ViewBuilder private var status: some View {
        let query = SearchText.searchable(typed)
        if !canSearch && !typed.isEmpty {
            notice(L("Your role can’t search patients, clients, visits or invoices. Actions and pages still show here."))
        } else if !typed.isEmpty && query == nil {
            notice(L("Type at least 2 characters to search patients, clients, visits and invoices."))
        } else if query != nil && isError && results == nil {
            VStack(spacing: 4) {
                Text(L("Search isn’t available right now."))
                    .font(Theme.text(14))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                Button { retries += 1 } label: {
                    Text(L("Try again")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blueText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        } else if waiting && results == nil {
            SearchLoadingRows()
        } else if query != nil && canSearch && !waiting && !isError && !(results?.hasResults ?? false) {
            EmptyState(
                systemImage: "search",
                title: LF("No results for “%@”", typed),
                message: L("Try a name, a phone number, a microchip or a folio."),
                accent: Theme.aqua
            )
        }
    }

    private func notice(_ message: String) -> some View {
        Text(message)
            .font(Theme.text(14))
            .foregroundStyle(Theme.inkSoft)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
    }

    // MARK: The groups

    private func groupView(_ group: SearchOptionGroup, activeID: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(group.id.title.uppercased())
                    .font(Theme.text(10.9, weight: .heavy))
                    .tracking(10.9 * 0.14)
                    .foregroundStyle(Theme.inkSoft)
                Spacer(minLength: 0)
                if group.id == .recent {
                    Button {
                        recents = SearchRecents()
                        recents.write(storageKey)
                    } label: {
                        Text(L("Clear"))
                            .font(Theme.text(12, weight: .bold))
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            ForEach(group.options) { option in
                SearchOptionRow(option: option, active: option.id == activeID) { choose(option) }
                    .id(option.id)
            }
        }
        .padding(.top, 8)
    }

    // MARK: Choosing

    private func move(_ step: Int) {
        let options = groups.flatMap(\.options)
        guard !options.isEmpty else { return }
        let current = options.firstIndex { $0.id == activeKey } ?? 0
        activeKey = options[(current + step + options.count) % options.count].id
    }

    private func choose(_ option: SearchOption) {
        guard let destination = SearchRules.destination(of: option, workspace: workspace) else { return }
        if case .query(let query) = destination {
            text = query
            return
        }
        remember(option)
        onLeave(destination)
    }

    private func remember(_ option: SearchOption) {
        var next = recents
        if let item = option.recent { next = next.remembering(item) }
        if let query = debouncedQuery {
            switch option {
            case .recentItem, .action: break
            default: next = next.remembering(query: query)
            }
        }
        guard next != recents else { return }
        recents = next
        next.write(storageKey)
    }

    // MARK: Asking the server

    private func fetch() async {
        guard canSearch, let query = debouncedQuery else {
            fetching = false
            return
        }
        fetching = true
        failedQuery = nil
        // One retry, as the web's query does.
        for attempt in 0..<2 {
            do {
                let answer: SearchResponse = try await API.get("/provider-search", query: ["q": query, "limit": String(SearchText.limit)])
                guard !Task.isCancelled else { return }
                response = answer
                responseClinic = clinicId
                fetching = false
                return
            } catch {
                if Task.isCancelled { return }
                if attempt == 0 {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                }
            }
        }
        response = nil
        failedQuery = query
        fetching = false
    }
}

// MARK: - One row

private struct SearchOptionRow: View {
    let option: SearchOption
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.wash(Theme.blue, 12))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder private var content: some View {
        switch option {
        case .pet(let pet): petRow(pet)
        case .hospital(let patient): hospitalRow(patient)
        case .client(let client): clientRow(client)
        case .visit(let visit): visitRow(visit)
        case .invoice(let invoice): invoiceRow(invoice)
        case .more(let group, let query):
            SearchRow(title: Self.moreTitle(group, query)) { tile("arrow-right") }
        case .recentQuery(let query):
            SearchRow(title: query) { tile("history") }
        case .recentItem(let item): recentRow(item)
        case .action(let action):
            SearchRow(title: L(action.label)) {
                tile(action.icon)
            } trailing: {
                if action.kind == .page { Glyph("arrow-right", size: 16).foregroundStyle(Theme.inkSoft) }
            }
        }
    }

    // A patient: the face, "Perro · Mestizo · Dueño: Ana", the microchip when it matched.
    private func petRow(_ pet: SearchPet) -> some View {
        let subtitle = [Self.species(pet.species), pet.breed, pet.ownerName?.nonEmpty.map { LF("Owner: %@", $0) }]
        return SearchRow(title: pet.name, subtitle: Self.joined(subtitle)) {
            PetAvatar(name: pet.name, species: pet.species, photoURL: pet.photoUrl, size: 36)
        } trailing: {
            if pet.matchedBy == "microchip", let chip = pet.microchip?.nonEmpty { Chip(text: LF("Microchip %@", chip), tone: .info) }
            if pet.status == "archived" { Chip(text: L("Archived")) }
        }
    }

    // A patient waiting for admission or in the hospital.
    private func hospitalRow(_ patient: SearchHospitalPatient) -> some View {
        let place = Self.joined([patient.roomName, patient.cageLabel?.nonEmpty.map { LF("Cage %@", $0) }])
        let state = patient.status == "pending" ? L("Waiting for admission") : L("In the hospital")
        return SearchRow(title: patient.petName, subtitle: Self.joined([state, place, patient.clientName, patient.locationName])) {
            PetAvatar(name: patient.petName, species: patient.petSpecies, photoURL: patient.petPhotoUrl, size: 36)
        } trailing: {
            switch patient.triagePriority {
            case "critical": Chip(text: L("Critical"), tone: .danger)
            case "urgent": Chip(text: L("Urgent"), tone: .danger)
            case "stable": Chip(text: L("Stable"))
            default: if patient.emergency == true { Chip(text: L("Emergency"), tone: .danger) }
            }
            if patient.status == "pending" { Chip(text: L("To admit")) }
        }
    }

    // A client: initials, the contact that matched, their pets.
    private func clientRow(_ client: SearchClient) -> some View {
        let contact = client.matchedBy == "email" ? (client.email?.nonEmpty ?? client.phone?.nonEmpty) : (client.phone?.nonEmpty ?? client.email?.nonEmpty)
        let names = (client.pets ?? []).map(\.name)
        let extra = (client.petCount ?? names.count) - names.count
        let pets = names.isEmpty ? L("No pets yet") : extra > 0 ? LF("%@ +%d", names.joined(separator: ", "), extra) : names.joined(separator: ", ")
        return SearchRow(title: client.name) {
            Avatar(name: client.name, imageURL: client.photoUrl, size: 36, tint: Theme.aqua)
        } subtitle: {
            HStack(spacing: 2) {
                if let contact { Text(verbatim: "\(contact) · ") }
                Glyph("paw-print", size: 12)
                Text(pets)
            }
        } trailing: {
            if client.status == "archived" { Chip(text: L("Archived")) }
        }
    }

    // A visit: "Kira · Consulta", when (in its place's clock), who, where.
    private func visitRow(_ visit: SearchVisit) -> some View {
        let when = SearchText.visitWhen(visit.startsAt, timeZone: visit.timeZone)
        return SearchRow(title: Self.joined([visit.petName, visit.serviceLabel]), subtitle: Self.joined([when, visit.clientName, visit.locationName])) {
            PetAvatar(name: visit.petName, species: visit.petSpecies, photoURL: visit.petPhotoUrl, size: 36)
        } trailing: {
            if let status = Self.visitStatus(visit.status) {
                Chip(text: status.text, tone: status.tone)
            } else if visit.upcoming == true {
                Chip(text: L("Upcoming"), tone: .info)
            }
        }
    }

    // A bill: folio and client, its kind and day, the total, what is still owed or its state.
    private func invoiceRow(_ invoice: SearchInvoice) -> some View {
        let kind = invoice.kind == "sale" ? L("Store sale") : invoice.kind == "deposit" ? L("Deposit") : L("Bill")
        let day = invoice.date.flatMap { DateText.parse($0) }.map { DateText.date($0) }
        let balance = invoice.balanceDueAmount ?? 0
        let owes = balance > 0 && !["paid", "canceled", "draft"].contains(invoice.status ?? "")
        return SearchRow(title: Self.joined([invoice.folio, invoice.clientName]), subtitle: Self.joined([kind, day, invoice.petName, invoice.locationName])) {
            tile("receipt")
        } trailing: {
            Text(Money.format(invoice.totalAmount, currency: invoice.currency))
                .font(Theme.text(14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.inkStrong)
                .lineLimit(1)
            if owes {
                Chip(text: LF("Owes %@", Money.format(balance, currency: invoice.currency)), tone: .danger)
            } else if let status = Self.invoiceStatus(invoice.status) {
                Chip(text: status.text, tone: status.tone)
            }
        }
    }

    // Something opened before on this device.
    private func recentRow(_ item: SearchRecentItem) -> some View {
        let kind: String = switch item.kind {
        case .pet: L("Patient")
        case .hospital: L("In the hospital")
        case .client: L("Client")
        case .visit: L("Visit")
        case .invoice: L("Invoice")
        }
        return SearchRow(title: item.title, subtitle: Self.joined([kind, item.subtitle])) {
            switch item.kind {
            case .pet, .hospital: PetAvatar(name: item.title, species: item.species, photoURL: item.photoUrl, size: 36)
            case .client: Avatar(name: item.title, imageURL: item.photoUrl, size: 36, tint: Theme.aqua)
            case .visit: tile("calendar-days")
            case .invoice: tile("receipt")
            }
        }
    }

    /// The web's icon tile: the icon in PAW Blue on a 10% wash of it, 36 round.
    private func tile(_ icon: String) -> some View {
        IconBadge(icon: icon, accent: Theme.blue, size: 36, iconSize: 16, ink: .accent, washPercent: 10)
    }

    // MARK: Words

    private static func joined(_ parts: [String?]) -> String {
        parts.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static func moreTitle(_ group: SearchResultGroup, _ query: String) -> String {
        switch group {
        case .pets: LF("All patients matching “%@”", query)
        case .hospital: L("Everyone in the hospital")
        case .clients: LF("All clients matching “%@”", query)
        case .visits: LF("All visits matching “%@”", query)
        case .invoices: LF("All invoices matching “%@”", query)
        }
    }

    private static func species(_ value: String?) -> String {
        switch value {
        case "dog": L("Dog")
        case "cat": L("Cat")
        case "bird": L("Bird")
        case "rabbit": L("Rabbit")
        case "fish": L("Fish")
        case "reptile": L("Reptile")
        case "small_pet": L("Small pet")
        default: L("Other")
        }
    }

    private static func visitStatus(_ status: String?) -> (text: String, tone: Chip.Tone)? {
        switch status {
        case "checked_in": return (L("Arrived"), .info)
        case "in_progress": return (L("In progress"), .info)
        case "completed": return (L("Completed"), .muted)
        case "cancelled": return (L("Cancelled"), .danger)
        case "no_show": return (L("No-show"), .danger)
        default: return nil
        }
    }

    /// As Cuentas names a bill's state: the client hasn't paid it yet ("Te deben" counts it).
    private static func invoiceStatus(_ status: String?) -> (text: String, tone: Chip.Tone)? {
        switch status {
        case "draft": return (L("Draft"), .muted)
        case "ready_for_payment", "open": return (L("Unpaid"), .danger)
        case "partially_paid": return (L("Part paid"), .danger)
        case "overdue": return (L("Overdue"), .danger)
        case "paid": return (L("Paid"), .info)
        case "canceled": return (L("Canceled"), .muted)
        default: return nil
        }
    }
}

/// A row's frame (web `Row`): the 36 icon, the title (14 bold) over its line (12), the chips at the end.
private struct SearchRow<Icon: View, Subtitle: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let subtitle: () -> Subtitle
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            icon()
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Theme.text(14, weight: .bold))
                    .foregroundStyle(Theme.inkStrong)
                    .lineLimit(1)
                subtitle()
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) { trailing() }
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

extension SearchRow where Subtitle == EmptyView, Trailing == EmptyView {
    init(title: String, @ViewBuilder icon: @escaping () -> Icon) {
        self.init(title: title, icon: icon, subtitle: { EmptyView() }, trailing: { EmptyView() })
    }
}

extension SearchRow where Subtitle == EmptyView {
    init(title: String, @ViewBuilder icon: @escaping () -> Icon, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(title: title, icon: icon, subtitle: { EmptyView() }, trailing: trailing)
    }
}

extension SearchRow where Subtitle == SearchRowLine {
    init(title: String, subtitle: String, @ViewBuilder icon: @escaping () -> Icon, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(title: title, icon: icon, subtitle: { SearchRowLine(text: subtitle) }, trailing: trailing)
    }
}

extension SearchRow where Subtitle == SearchRowLine, Trailing == EmptyView {
    init(title: String, subtitle: String, @ViewBuilder icon: @escaping () -> Icon) {
        self.init(title: title, icon: icon, subtitle: { SearchRowLine(text: subtitle) }, trailing: { EmptyView() })
    }
}

/// A row's second line; none when it says nothing.
private struct SearchRowLine: View {
    let text: String
    var body: some View {
        if !text.isEmpty { Text(text) }
    }
}

/// While the first answer loads (web `LoadingRows`): three rows of soft blue shapes.
private struct SearchLoadingRows: View {
    @State private var dim = false

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle().fill(Theme.wash(Theme.blue, 10)).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(Theme.wash(Theme.blue, 10)).frame(width: 120, height: 12)
                        Capsule().fill(Theme.wash(Theme.blue, 7)).frame(width: 180, height: 10)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 12)
        .opacity(dim ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dim)
        .onAppear { dim = true }
        .accessibilityHidden(true)
    }
}
