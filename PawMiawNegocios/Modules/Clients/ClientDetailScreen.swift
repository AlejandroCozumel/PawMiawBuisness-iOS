//
//  ClientDetailScreen.swift
//  PawMiawNegocios
//
//  A client's page (web: routes/provider.clients.$clientId.tsx): who they
//  are and how to reach them, the numbers that matter, the link to their
//  family on PawMiaw, their pets (each opens its chart), their visits, their
//  account (by money level), where they live and who to call. Delete means
//  archive: the client is archived with its pets and can be restored.
//

import SwiftUI

@MainActor
final class ClientsClientPage: ObservableObject {
    let clientId: String
    @Published var client: ClientsClient?
    @Published var error: String?
    @Published var notFound = false
    @Published var petActivity: [String: ClientsPetActivity] = [:]
    @Published var activityKnown = false
    @Published var account: ClientsAccount?
    @Published var invitations: [ClientsInvitation] = []
    @Published var upcoming: [ClientsAppointment] = []
    @Published var earlier: [ClientsAppointment] = []
    @Published var visitsLoaded = false
    @Published var visitsFailed = false
    @Published var bills: [ClientsInvoice] = []
    @Published var billsTotal = 0
    @Published var billsLoaded = false
    @Published var home: ClientsHome?
    @Published var homeFailed = false
    /// The open match suggestions that touch this client or one of its pets.
    @Published var suggestions: [ClientsMatchSuggestion] = []
    /// The client's stays (with "stays.view").
    @Published var stays = ClientsStaySplit()

    init(clientId: String) { self.clientId = clientId }

    func loadSuggestions() async {
        suggestions = ClientsMatches.related(await ClientsMatches.load(), clientId: clientId)
    }

    func load(canUseDirectory: Bool, money: Bool, visits: Bool) async {
        let id = clientId
        do {
            client = try await API.get("/provider-clients/\(id)")
            error = nil
        } catch is CancellationError {
            return
        } catch {
            if (error as? APIError)?.status == 404 { notFound = true }
            self.error = errorText(error)
            return
        }
        async let directory: Page<ClientsPatientRow>? = Self.fetch(canUseDirectory, "/provider-directory/pets", ["limit": "50", "offset": "0", "clientId": id])
        async let accountAnswer: ClientsAccount? = Self.fetch(money, "/provider-finance/clients/\(id)/account")
        async let invites: Page<ClientsInvitation>? = Self.fetch(true, "/provider-client-invitations", ["limit": "10", "offset": "0", "providerClientId": id])
        async let homeAnswer: ClientsHome? = Self.fetch(true, "/provider-clients/\(id)/home")
        async let billsAnswer: ClientsInvoicePage? = Self.fetch(money, "/provider-invoices", ["limit": "5", "offset": "0", "providerClientId": id])
        if visits { await loadVisits() }

        if let page = await directory {
            var byPet: [String: ClientsPetActivity] = [:]
            for row in page.items where row.client.id == id { if let activity = row.activity { byPet[row.id] = activity } }
            petActivity = byPet
            activityKnown = true
        }
        account = await accountAnswer
        invitations = (await invites)?.items ?? []
        if let answer = await homeAnswer { home = answer; homeFailed = false } else { homeFailed = true }
        if let page = await billsAnswer { bills = page.items; billsTotal = page.total ?? page.items.count }
        billsLoaded = true
    }

    /// One optional read: nil when it isn't asked for or it fails.
    static func fetch<T: Decodable>(_ enabled: Bool, _ path: String, _ query: [String: String?] = [:]) async -> T? {
        guard enabled else { return nil }
        return try? await API.get(path, query: query)
    }

    /// Upcoming starts with today, earlier ends now (the Agenda's list).
    func loadVisits() async {
        let id = clientId
        let todayStart = DateText.iso(DateText.calendar.startOfDay(for: Date()))
        let now = DateText.iso(Date())
        do {
            async let ahead: Page<ClientsAppointment> = API.get("/provider-appointments", query: ["limit": "12", "offset": "0", "providerClientId": id, "from": todayStart])
            async let before: Page<ClientsAppointment> = API.get("/provider-appointments", query: ["limit": "12", "offset": "0", "providerClientId": id, "to": now, "order": "desc"])
            let over: Set<String> = ["completed", "cancelled", "no_show"]
            let next = try await ahead.items.filter { !over.contains($0.status ?? "") }.prefix(5)
            let shown = Set(next.map(\.id))
            upcoming = Array(next)
            earlier = Array(try await before.items.filter { !shown.contains($0.id) }.prefix(5))
            visitsFailed = false
        } catch {
            visitsFailed = true
        }
        visitsLoaded = true
    }

    /// The open invitation: waiting on the family (not run out).
    var pendingInvitation: ClientsInvitation? {
        invitations.first { $0.status == "pending" && (DateText.parse($0.expiresAt).map { $0 > Date() } ?? true) }
    }
}

struct ClientDetailScreen: View {
    let clientId: String

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var page: ClientsClientPage

    @State private var editing = false
    @State private var addingPet = false
    @State private var inviting = false
    @State private var editingPet: ClientsPet?
    @State private var closing: ClientsClosingTarget?
    @State private var restoring: ClientsRestoreTarget?
    @State private var pushed: ClientsPush?
    @State private var route: ProviderRoute?
    @State private var renaming = false
    @State private var reviewingMatches = false
    @State private var mergingClient = false
    @State private var mergingPet: ClientsMergePetSource?
    @State private var movingPet: ClientsMoveTarget?
    @State private var unlinkingPet: ClientsUnlinkTarget?

    init(clientId: String) {
        self.clientId = clientId
        _page = StateObject(wrappedValue: ClientsClientPage(clientId: clientId))
    }

    private var canUseDirectory: Bool { workspace.can(.clientsView) && (workspace.can(.clientsAssignSelf) || workspace.can(.clientsAssignAnyone)) }
    private var canBook: Bool { workspace.can(.appointmentsCreate) && (workspace.can(.appointmentsAssignSelf) || workspace.can(.appointmentsAssignAnyone)) }
    private var canAddRecords: Bool { workspace.can(.recordsCreate) && (workspace.can(.recordsAssignSelf) || workspace.can(.recordsAssignAnyone)) }
    private var seesMoney: Bool { workspace.moneyLevel >= .charging }
    private var wide: Bool { sizeClass == .regular }

    var body: some View {
        Group {
            if !workspace.can(.clientsView) {
                PageScroll { NoAccessState(message: L("This provider workspace is active, but your current role does not include the client detail surface.")) }
            } else if let client = page.client {
                content(client)
            } else if page.notFound {
                PageScroll {
                    EmptyState(systemImage: "users-round", title: L("Client not found"), message: L("This provider client either does not exist anymore or belongs to a different provider workspace."),
                               actionTitle: L("Back to clients"), action: { route = .section(.clients) }, accent: Theme.lime, panel: true)
                }
            } else if let error = page.error {
                PageScroll { ErrorState(message: error) { await load() } }
            } else {
                PageScroll { LoadingState() }
            }
        }
        .providerPage(page.client?.ownerName ?? L("Client"))
        .reloadsOnScope { await load() }
        .sheet(isPresented: $editing) {
            if let client = page.client {
                ClientsEditClientSheet(client: client, onOpenClient: { id in
                    Task { try? await Task.sleep(for: .milliseconds(350)); route = .client(id) }
                }) { page.client = $0 }
            }
        }
        .sheet(isPresented: $addingPet) { if let client = page.client { ClientsAddPetSheet(client: client) { page.client = $0 } } }
        .sheet(isPresented: $inviting) { if let client = page.client { ClientsInviteSheet(client: client) } }
        .sheet(item: $editingPet) { pet in ClientsEditPetSheet(clientName: page.client?.ownerName ?? "", pet: pet) }
        .sheet(item: $closing) { target in ClientsClosingSheet(target: target) { result in if let client = result.client { page.client = client } } }
        .sheet(item: $restoring) { target in ClientsRestoreSheet(target: target) { result in if let client = result.client { page.client = client } } }
        .navigationDestination(item: $pushed) { push in push.view }
        .navigationDestination(item: $route) { RouteView(route: $0) }
        .sheet(isPresented: $reviewingMatches) {
            if let client = page.client {
                ClientsMatchReviewSheet(
                    suggestions: page.suggestions, canEdit: workspace.can(.clientsEdit),
                    subtitle: LF("Records that may be the same as %@ or one of their pets.", client.ownerName),
                    onMerged: { suggestion, targetId in
                        // This page's client went into the other one: open the one that stayed.
                        if !suggestion.isPet && suggestion.source.id == client.id {
                            reviewingMatches = false
                            Task { try? await Task.sleep(for: .milliseconds(400)); route = .client(targetId) }
                        }
                    },
                    onAnswered: { await load() }
                )
            }
        }
        .sheet(isPresented: $mergingClient) {
            if let client = page.client {
                ClientsMergeClientSheet(client: client) { targetId in
                    Task { try? await Task.sleep(for: .milliseconds(400)); route = .client(targetId) }
                }
            }
        }
        .sheet(item: $mergingPet) { source in
            ClientsMergePetSheet(source: source, ownPets: page.client?.allPets ?? [], canSearchOthers: canUseDirectory) { clientId, petId in
                Task { try? await Task.sleep(for: .milliseconds(400)); route = .clientPet(clientId: clientId, petId: petId) }
            }
        }
        .sheet(item: $movingPet) { target in
            ClientsMovePetSheet(target: target) { clientId, petId in
                Task { await load(); try? await Task.sleep(for: .milliseconds(300)); route = .clientPet(clientId: clientId, petId: petId) }
            }
        }
        .sheet(item: $unlinkingPet) { target in
            ClientsUnlinkPetSheet(target: target) { await load() }
        }
    }

    private func load() async {
        await page.load(canUseDirectory: canUseDirectory, money: seesMoney, visits: workspace.can(.appointmentsView))
        if workspace.can(.clientsView) { await page.loadSuggestions() }
        if workspace.can(.staysView) { page.stays = await ClientsStaysSection.load(clientId: clientId) }
    }

    /// The pet a combine starts from.
    private func mergeSource(_ client: ClientsClient, _ pet: ClientsPet) -> ClientsMergePetSource {
        ClientsMergePetSource(clientId: client.id, clientName: client.ownerName, petId: pet.id, name: pet.petName, species: pet.petSpecies, breed: pet.petBreed, photoUrl: pet.photoUrl, linked: pet.isLinked, householdPetId: pet.petId, details: ClientsPetDetails.of(pet, createdAt: nil))
    }

    // MARK: Page

    /// Laid out as the web's client page: the header (who they are, how to
    /// reach them, the numbers that matter, each one jumping to its part), the
    /// archive stamp, the family on PawMiaw, possible duplicates, the pets,
    /// the visits, the account, stays, home & contact, care cards, history.
    private func content(_ client: ClientsClient) -> some View {
        ScrollViewReader { proxy in
            PageScroll(refresh: { await load() }) {
                header(client, proxy: proxy)
                if client.isArchived {
                    ClientsClosingBanner(name: client.ownerName, stamp: client.closing, deceasedAt: nil, hint: nil, onRestore: workspace.can(.clientsEdit) ? { restoring = .client(id: client.id, name: client.ownerName) } : nil)
                }
                ClientsLinkCard(page: page, client: client, canManage: workspace.can(.clientsEdit), renaming: renaming, onUseLinkedName: { name in useLinkedName(client, name) }, onOpenInvitations: { pushed = .invitations(client.id) }, onUnlink: { pet in
                    unlinkingPet = ClientsUnlinkTarget(clientId: client.id, clientName: client.ownerName, petId: pet.id, petName: pet.petName)
                })
                if !page.suggestions.isEmpty {
                    ClientsMatchBanner(suggestions: page.suggestions, clientId: client.id, canEdit: workspace.can(.clientsEdit)) { reviewingMatches = true }
                }
                petsCard(client).id("client-pets")
                if workspace.can(.appointmentsView) {
                    ClientsVisitsSection(page: page, clientName: client.ownerName, onBook: canBook && !client.isArchived ? { route = .bookVisit(BookingPrefill(clientId: client.id)) } : nil)
                        .id("client-visits")
                }
                if seesMoney {
                    ClientsAccountSection(page: page, client: client).id("client-account")
                }
                if workspace.can(.staysView) {
                    ClientsStaysSection(stays: page.stays)
                }
                ClientsHomeSection(page: page)
                careCards(client)
                AuditHistoryCard(entityType: "provider_client", entityId: client.id, description: L("Secondary audit trail for this client, linked pets, records, billing, and staff actions."))
            }
        }
    }

    /// The care card of each pet, for businesses that groom, walk, sit, train or keep daycare.
    @ViewBuilder
    private func careCards(_ client: ClientsClient) -> some View {
        let pets = client.allPets.filter { !$0.isArchived }
        if workspace.offers(.groomer, .walker, .sitter, .trainer, .daycare) && !pets.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)], spacing: 16) {
                ForEach(pets) { pet in
                    SvcCareCard(petId: pet.id, petName: pet.petName, canEdit: workspace.can(.petsEdit) || workspace.can(.appointmentsComplete))
                }
            }
        }
    }

    // MARK: Header

    /// The web's `ProviderModuleHeader` for a client: lime, their photo or
    /// initials, their name, how to reach them, the actions on their own row
    /// (Agendar, Llamar, WhatsApp | Agregar mascota, Vincular familia, Editar, ⋯)
    /// and the numbers. The header's subtitle is text only here, so the status
    /// pill and the PawMiaw badge open the actions row.
    private func header(_ client: ClientsClient, proxy: ScrollViewProxy) -> some View {
        let phone = client.ownerPhone?.nonEmpty
        let email = client.ownerEmail?.nonEmpty
        let contact = [phone, email].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? L("No contact details yet")
        let book = canBook && !client.isArchived
        let tel = ContactLinks.phone(phone)
        let whatsapp = ContactLinks.whatsApp(phone)
        return ModuleHeader(
            icon: "users-round",
            title: client.ownerName,
            subtitle: contact,
            accent: Theme.lime,
            media: AnyView(Avatar(name: client.ownerName, imageURL: client.photoUrl, size: wide ? 56 : 36)),
            titleAccessory: AnyView(HStack(spacing: 6) {
                if (client.status ?? "active") != "active" { StatusChip(text: client.isArchived ? L("Archived") : ClientsText.clientStatus(client.status), brand: Theme.lime) }
                ClientsLinkBadge(linked: client.isLinked)
            }),
            stats: stats(client, proxy: proxy),
            actionsOnRow: true,
            storageKey: "client",
            actions: { headerActions(client, book: book, tel: tel, whatsapp: whatsapp) },
            footer: {
                // Unlinked (by the family or by the business): when, and that what they owe from before stays theirs.
                if DisconnectedMark.text(at: client.disconnectedAt, by: client.disconnectedBy) != nil {
                    RowDivider()
                    DisconnectedMark(at: client.disconnectedAt, by: client.disconnectedBy, withDetail: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        )
    }

    @ViewBuilder private func headerActions(_ client: ClientsClient, book: Bool, tel: URL?, whatsapp: URL?) -> some View {
        // Booking is the one filled button; then reaching the family, then what you do with the client.
        if book {
            PMButton(L("Book a visit"), systemImage: "calendar-plus") { route = .bookVisit(BookingPrefill(clientId: client.id)) }
        }
        if let tel {
            PMButton(L("Call"), systemImage: "phone", variant: .outline) { openURL(tel) }
        }
        if let whatsapp {
            PMButton(L("WhatsApp"), systemImage: "message-circle", variant: .outline) { openURL(whatsapp) }
        }
        if tel != nil || whatsapp != nil { ChipRule() }
        if workspace.can(.petsCreate) && !client.isArchived {
            PMButton(L("Add pet"), systemImage: "paw-print", variant: .outline) { addingPet = true }
        }
        if workspace.can(.clientsEdit) && !client.isLinked && !client.isArchived {
            PMButton(L("Link household"), systemImage: "link-2", variant: .outline) { inviting = true }
        }
        if workspace.can(.clientsEdit) {
            PMButton(L("Edit client"), systemImage: "pencil", variant: .outline) { editing = true }
        }
        moreMenu(client)
    }

    private func moreMenu(_ client: ClientsClient) -> some View {
        Menu {
            // One way to link at a time: the button while the family isn't linked, the menu item after.
            let unlinkedPets = client.allPets.filter { $0.isActive && !$0.isLinked }
            if workspace.can(.clientsEdit) && client.isLinked && !unlinkedPets.isEmpty {
                Button { inviting = true } label: { GlyphLabel(LF("Invite to link %@", unlinkedPets.map(\.petName).joined(separator: ", ")), icon: "link-2") }
            }
            Button { pushed = .invitations(client.id) } label: { GlyphLabel(L("Invitations"), icon: "mail-plus") }
            if workspace.can(.clientsEdit) {
                Divider()
                Button { mergingClient = true } label: { GlyphLabel(L("Combine with another client"), icon: "git-merge") }
                if client.isArchived {
                    Button { restoring = .client(id: client.id, name: client.ownerName) } label: { GlyphLabel(L("Restore"), icon: "rotate-ccw") }
                } else {
                    Button(role: .destructive) {
                        let owed = seesMoney && (page.account?.owed ?? 0) > 0 ? Money.format(page.account?.owed, currency: page.account?.currency) : nil
                        closing = .archiveClient(id: client.id, name: client.ownerName, firstName: client.ownerFirstName?.nonEmpty ?? client.ownerName, owed: owed)
                    } label: { GlyphLabel(L("Archive client"), icon: "archive") }
                }
            }
        } label: {
            IconCircleButton(systemImage: "ellipsis", label: LF("More for %@", client.ownerName)) {}
                .allowsHitTesting(false)
        }
        .accessibilityLabel(LF("More for %@", client.ownerName))
    }

    /// The header's numbers (web `stats`): each one jumps to its part of the page.
    private func stats(_ client: ClientsClient, proxy: ScrollViewProxy) -> [ModuleStat] {
        let active = client.allPets.filter { !$0.isArchived }
        let archivedCount = client.allPets.count - active.count
        let known = page.activityKnown || active.isEmpty
        let last = active.compactMap { pet in page.petActivity[pet.id]?.lastVisitAt.map { ($0, pet.petName) } }.max { $0.0 < $1.0 }
        let next = active.compactMap { pet in page.petActivity[pet.id]?.nextVisitAt.map { ($0, pet.petName) } }.min { $0.0 < $1.0 }
        let due = active.compactMap { pet -> (String, String, String)? in
            guard let activity = page.petActivity[pet.id], let at = activity.nextDueAt else { return nil }
            return (at, pet.petName, activity.nextDueTitle.map { ClientsText.followUpTitle($0) } ?? L("Follow-up"))
        }.min { $0.0 < $1.0 }
        // Pets that are all archived are still its pets: "none yet" would be untrue.
        let petsHint = active.isEmpty
            ? (archivedCount > 0 ? LP(archivedCount, "%d archived", "%d archived") : L("No pets yet"))
            : ([active.map(\.petName).joined(separator: ", "), archivedCount > 0 ? LP(archivedCount, "%d archived", "%d archived") : nil].compactMap { $0 }.joined(separator: " · "))
        let visitsSection = workspace.can(.appointmentsView) ? "client-visits" : "client-pets"
        let jump = { (id: String) in withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .top) } }

        var stats: [ModuleStat] = [
            ModuleStat("pets", label: L("Pets"), value: "\(active.count)", hint: petsHint, icon: "paw-print", accent: Theme.aqua, action: { jump("client-pets") }),
            ModuleStat("last", label: L("Last visit"), value: known ? (last.map { ClientsText.shortDay($0.0) } ?? L("None yet")) : "—",
                       hint: known ? (last?.1 ?? L("First visit still to come")) : nil, icon: "stethoscope", accent: Theme.lime, action: { jump(visitsSection) }),
            ModuleStat("next", label: L("Next visit"), value: known ? (next.map { ClientsText.shortDay($0.0) } ?? L("Not booked")) : "—",
                       hint: known ? (next.map { "\($0.1) · \(DateText.time($0.0))" } ?? due.map { LF("Due %@: %@", ClientsText.shortDay($0.0), "\($0.2) (\($0.1))") } ?? L("Nothing on the calendar")) : nil,
                       icon: "calendar-days", accent: Theme.mango, attention: known && next == nil && ClientsText.isPast(due?.0), action: { jump(visitsSection) }),
        ]
        if seesMoney {
            let owed = page.account?.owed
            let money = { (cents: Int) in Money.format(cents, currency: page.account?.currency) }
            let hint: String? = {
                guard let account = page.account else { return nil }
                if (account.overdue ?? 0) > 0 { return LF("%@ overdue", money(account.overdue ?? 0)) }
                if (account.credit ?? 0) > 0 { return LF("%@ in credit", money(account.credit ?? 0)) }
                return (owed ?? 0) > 0 ? L("Nothing overdue") : L("Nothing owed")
            }()
            stats.append(ModuleStat("balance", label: L("Balance"), value: owed.map { money($0) } ?? "—", hint: hint, icon: "badge-dollar-sign", accent: Theme.pink,
                                    attention: (owed ?? 0) > 0, action: { jump("client-account") }))
        } else {
            stats.append(ModuleStat("balance", label: L("Balance"), value: "—", hint: L("Billing permission required"), icon: "badge-dollar-sign", accent: Theme.pink))
        }
        return stats
    }

    // MARK: Pets

    /// The pets card (web: the "Mascotas" section): the client's notes on a
    /// mango band, then one row per pet; archived ones last and faded.
    private func petsCard(_ client: ClientsClient) -> some View {
        let pets = client.allPets.sorted { ($0.isArchived ? 1 : 0) < ($1.isArchived ? 1 : 0) }
        let activeCount = pets.filter { !$0.isArchived }.count
        return SectionCard(title: L("Pets"), subtitle: L("Each pet has its own chart: records, visits and follow-ups."), icon: "paw-print", accent: Theme.aqua) {
            Text("\(activeCount)").font(.brandHeading(16)).monospacedDigit().foregroundStyle(Theme.inkSoft)
        } content: {
            if let notes = client.notes?.nonEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Glyph("sticky-note", size: 16).foregroundStyle(Theme.inkSoft).padding(.top, 2)
                    (Text("\(L("Client notes")): ").bold() + Text(notes))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(Theme.mango, 10))
                RowDivider()
            }
            if pets.isEmpty {
                EmptyState(systemImage: "paw-print", title: L("No pets yet"), message: L("Add the first pet so visits, records and care stay with the right pet."),
                           actionTitle: workspace.can(.petsCreate) ? L("Add pet") : nil, action: { addingPet = true }, accent: Theme.lime)
            } else {
                ForEach(Array(pets.enumerated()), id: \.element.id) { index, pet in
                    if index > 0 { RowDivider() }
                    ClientsPetRow(
                        client: client, pet: pet, activity: page.petActivity[pet.id], wide: wide,
                        canBook: canBook && pet.isActive && !client.isArchived,
                        canAddRecord: canAddRecords, canEdit: workspace.can(.petsEdit),
                        onOpen: { route = .clientPet(clientId: client.id, petId: pet.id) },
                        onBook: { route = .bookVisit(BookingPrefill(clientId: client.id, petId: pet.id)) },
                        onRecord: { route = .newRecord(RecordPrefill(clientId: client.id, petId: pet.id)) },
                        onEdit: { editingPet = pet },
                        onCombine: workspace.can(.petsEdit) ? { mergingPet = mergeSource(client, pet) } : nil,
                        onMove: workspace.can(.petsEdit) && workspace.isOwnerOrAdmin && pet.isActive && !client.isArchived
                            ? { movingPet = ClientsMoveTarget(clientId: client.id, clientName: client.ownerName, petId: pet.id, name: pet.petName, linked: pet.isLinked) } : nil,
                        onUnlink: workspace.can(.clientsEdit) && pet.isLinked
                            ? { unlinkingPet = ClientsUnlinkTarget(clientId: client.id, clientName: client.ownerName, petId: pet.id, petName: pet.petName) } : nil,
                        onClose: { kind in closing = kind == .death ? .petDeath(clientId: client.id, petId: pet.id, name: pet.petName) : .archivePet(clientId: client.id, petId: pet.id, name: pet.petName) },
                        // A pet archived with its client comes back with the client; one that changed family is moved back from its new record.
                        onRestore: client.isArchived || pet.closing?.reason == "client_archived" || pet.movedTo != nil ? nil : { restoring = .pet(id: pet.id, name: pet.petName, deceased: pet.deceasedAt != nil) }
                    )
                }
            }
        }
    }

    private func useLinkedName(_ client: ClientsClient, _ name: String) {
        let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
        renaming = true
        Task {
            defer { renaming = false }
            do {
                let saved: ClientsClient = try await API.patch("/provider-clients/\(client.id)", body: [
                    "ownerFirstName": parts.first ?? name,
                    "ownerLastName": parts.count > 1 ? parts[1] : nil,
                    "ownerEmail": client.ownerEmail,
                    "recipientLanguage": client.recipientLanguage,
                    "ownerPhone": client.ownerPhone,
                    "notes": client.notes,
                ])
                page.client = saved
                Toast.show(LF("The client is now called %@.", name))
                announceDataChanged()
            } catch {
                Toast.error(error, fallback: L("Could not change the name."))
            }
        }
    }
}

/// Where a client page goes from its own buttons.
enum ClientsPush: Hashable {
    case section(ProviderSection)
    case invitations(String)

    @ViewBuilder
    var view: some View {
        switch self {
        case .section(let section): SectionView(section: section)
        case .invitations(let clientId): InvitationsScreen(clientId: clientId)
        }
    }
}

// MARK: - A pet on the client's page

/// One pet on the client's page (web `ClientPetRow`): its 48 face, the name
/// with the allergy, its state and the PawMiaw link, the profile line, the
/// vet and chip, where it moved, its notes and what's next; Agendar,
/// Registro and Editar on their own line (sharing it), ⋯ for the rest.
/// The row opens the chart.
private struct ClientsPetRow: View {
    enum CloseKind { case archive, death }

    let client: ClientsClient
    let pet: ClientsPet
    let activity: ClientsPetActivity?
    let wide: Bool
    let canBook: Bool
    let canAddRecord: Bool
    let canEdit: Bool
    let onOpen: () -> Void
    let onBook: () -> Void
    let onRecord: () -> Void
    let onEdit: () -> Void
    let onCombine: (() -> Void)?
    let onMove: (() -> Void)?
    let onUnlink: (() -> Void)?
    let onClose: (CloseKind) -> Void
    let onRestore: (() -> Void)?

    var body: some View {
        let next = ClientsNext.of(activity)
        let allergies = activity?.allergies ?? []
        let died = pet.deceasedAt != nil
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                PetAvatar(name: pet.petName, species: pet.petSpecies, photoURL: pet.photoUrl, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    FlowLayout(spacing: 6) {
                        Text(pet.petName).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        if !allergies.isEmpty {
                            // What it is allergic to is read here, not behind a hover.
                            Chip(text: "\(L("Allergy")): \(allergies.joined(separator: ", "))", tone: .danger, icon: "triangle-alert")
                        }
                        if !pet.isActive {
                            StatusChip(text: died ? L("Deceased") : pet.isArchived ? L("Archived") : ClientsText.clientStatus(pet.status), brand: Theme.lime, small: true)
                        }
                        if pet.isLinked {
                            Glyph("link-2", size: 14).foregroundStyle(Theme.blue)
                                .accessibilityLabel(L("Linked to the family’s PawMiaw profile"))
                        }
                    }
                    Text(ClientsText.profileLine(pet).nonEmpty ?? L("No profile details yet"))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    if let meta { Text(meta).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                    // It changed family: where it is now, or where it came from.
                    if let moved = pet.movedTo {
                        NavigationLink(value: ProviderRoute.clientPet(clientId: moved.clientId, petId: moved.petId)) {
                            HStack(spacing: 6) {
                                Glyph("arrow-right-left", size: 12).foregroundStyle(Theme.inkStrong)
                                Text(LF("Now with %@", moved.clientName ?? "—")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    } else if let from = pet.movedFrom, !pet.isArchived {
                        HStack(spacing: 6) {
                            Glyph("arrow-right-left", size: 12)
                            Text(LF("Came from %@", from.clientName ?? "—")).lineLimit(1)
                        }
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        .padding(.top, 2)
                    }
                    if let notes = pet.notes?.nonEmpty {
                        HStack(spacing: 6) {
                            Glyph("sticky-note", size: 12)
                            Text(notes).lineLimit(1)
                        }
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        .padding(.top, 2)
                    }
                    // On a phone, what's next goes under the pet; wider screens give it a column.
                    if !pet.isArchived && !wide, let next {
                        (Text("\(L("Next")): ").foregroundStyle(Theme.inkStrong)
                         + Text(ClientsText.shortDay(next.at)).bold().foregroundStyle(ClientsText.isPast(next.at) ? Theme.destructive : Theme.inkStrong)
                         + Text(" · \(next.what)").foregroundStyle(Theme.inkSoft))
                            .font(Theme.text(12)).lineLimit(1)
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: 8)
                if wide && !pet.isArchived {
                    column(L("Last visit"), width: 112) {
                        Text(activity?.lastVisitAt == nil ? "—" : ClientsText.shortDay(activity?.lastVisitAt)).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    }
                    column(L("Next"), width: 176) {
                        if let next {
                            (Text(ClientsText.shortDay(next.at)).bold().foregroundStyle(ClientsText.isPast(next.at) ? Theme.destructive : Theme.inkStrong)
                             + Text(" · \(next.what)").foregroundStyle(Theme.inkSoft))
                                .font(Theme.text(14)).lineLimit(1)
                        } else {
                            Text("—").font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                if wide { actions }
                Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
            }
            if !wide && (canBook || canAddRecord || canEdit || onUnlink != nil) {
                actions
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .opacity(pet.isArchived ? 0.6 : 1)
        .accessibilityAction(named: LF("Open %@ chart", pet.petName), onOpen)
    }

    /// Book, Record, Edit (labelled, sharing the line on a phone) and ⋯.
    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 6) {
            if canBook { PMButton(L("Book"), systemImage: "calendar-plus", variant: .outline, size: .compact, fullWidth: !wide, action: onBook).accessibilityLabel(LF("Book a visit for %@", pet.petName)) }
            if canAddRecord { PMButton(L("Record"), systemImage: "plus", variant: .outline, size: .compact, fullWidth: !wide, action: onRecord).accessibilityLabel(LF("Add record for %@", pet.petName)) }
            if canEdit { PMButton(L("Edit"), systemImage: "pencil", variant: .outline, size: .compact, fullWidth: !wide, action: onEdit).accessibilityLabel(LF("Edit %@", pet.petName)) }
            if canEdit || onUnlink != nil { menu }
        }
    }

    private var menu: some View {
        let died = pet.deceasedAt != nil
        return Menu {
            if let onCombine {
                Button { onCombine() } label: { GlyphLabel(L("Combine with another pet"), icon: "git-merge") }
            }
            if let onMove {
                Button { onMove() } label: { GlyphLabel(L("Move to another client"), icon: "arrow-right-left") }
            }
            if canEdit && pet.isArchived, let onRestore {
                Button { onRestore() } label: { GlyphLabel(L("Restore"), icon: "rotate-ccw") }
            }
            if let onUnlink {
                if canEdit { Divider() }
                Button(role: .destructive) { onUnlink() } label: { GlyphLabel(L("Unlink from the family"), icon: "link-2-off") }
            }
            if canEdit && !died && pet.movedTo == nil {
                Divider()
                if !pet.isArchived {
                    Button(role: .destructive) { onClose(.archive) } label: { GlyphLabel(L("Archive pet"), icon: "archive") }
                }
                Button(role: .destructive) { onClose(.death) } label: { GlyphLabel(L("Record that it died"), icon: "flower-2") }
            }
        } label: {
            IconCircleButton(systemImage: "ellipsis", label: LF("More for %@", pet.petName)) {}
                .allowsHitTesting(false)
        }
        .accessibilityLabel(LF("More for %@", pet.petName))
    }

    private func column<Content: View>(_ label: String, width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.brandText(10.6, weight: .heavy)).tracking(1.06).foregroundStyle(Theme.inkSoft).lineLimit(1)
            content()
        }
        .frame(width: width, alignment: .leading)
    }

    private var meta: String? {
        [
            pet.preferredMember?.name?.nonEmpty.map { LF("Vet: %@", $0) },
            pet.microchipNumber?.nonEmpty.map { LF("Chip ··%@", String($0.suffix(6))) },
        ].compactMap { $0 }.joined(separator: " · ").nonEmpty
    }
}
