//
//  InvitationsScreen.swift
//  PawMiawNegocios
//
//  Invitations (web: routes/provider.invitations.tsx, invitations/
//  invitation-list.tsx, invitation-sheets.tsx): the link a business sends so
//  a client's family connects their PawMiaw household to the business's
//  record. Who is waiting, who linked, whose link ran out, and who was never
//  asked; resend, revoke, change the email, confirm an acceptance from
//  another account, and "Invitar a PawMiaw" for many.
//
//  The page as the web draws it: the module header (its numbers are the
//  status filter), then one card: the search, the status chips, the rows
//  (20 at a time, infinite scroll) and how many there are.
//

import SwiftUI

enum ClientsInvitationWords {
    static let statuses = ["pending", "awaiting_clinic", "accepted", "expired", "revoked"]

    /// The filter's name (plural in Spanish: "Pendientes").
    static func filterLabel(_ status: String) -> String {
        switch status {
        case "pending": L("Pending@filter")
        case "awaiting_clinic": L("To confirm")
        case "accepted": L("Linked@filter")
        case "expired": L("Expired@filter")
        default: L("Revoked@filter")
        }
    }

    /// One invitation's state (singular in Spanish: "Pendiente").
    static func chipLabel(_ status: String) -> String {
        switch status {
        case "pending": L("Pending@status")
        case "awaiting_clinic": L("To confirm@status")
        case "accepted": L("Linked@status")
        case "expired": L("Expired@status")
        default: L("Revoked@status")
        }
    }

    /// The colours the rest of the workspace uses (web INVITATION_STATE): mango waits, green is done, grey ran out or was stopped.
    static func state(_ status: String) -> ProviderState {
        switch status {
        case "pending", "awaiting_clinic": .waiting
        case "accepted": .done
        default: .closed
        }
    }

    /// The server marks expiry when it lists; a page left open catches up here.
    static func effectiveStatus(_ invitation: ClientsInvitation) -> String {
        guard invitation.status == "pending", let expires = DateText.parse(invitation.expiresAt) else { return invitation.status }
        return expires <= Date() ? "expired" : "pending"
    }

    static func expiringSoon(_ invitation: ClientsInvitation) -> Bool {
        guard effectiveStatus(invitation) == "pending", let expires = DateText.parse(invitation.expiresAt) else { return false }
        return expires.timeIntervalSinceNow <= 48 * 3600
    }

    static func wasEmailed(_ invitation: ClientsInvitation) -> Bool {
        invitation.emailSentAt != nil || invitation.emailStatus == "sent"
    }

    static func name(_ invitation: ClientsInvitation) -> String {
        invitation.recipientName?.nonEmpty ?? invitation.client?.ownerName ?? "—"
    }

    static func acceptedBy(_ invitation: ClientsInvitation) -> String? {
        guard let account = invitation.pendingAcceptance?.account else { return nil }
        return [account.name?.nonEmpty, account.email].compactMap { $0 }.joined(separator: " · ").nonEmpty
    }

    /// The one line that says where the invitation stands in time.
    static func timing(_ invitation: ClientsInvitation) -> String {
        switch effectiveStatus(invitation) {
        case "accepted": return LF("Linked %@", ClientsText.shortDay(invitation.acceptedAt))
        case "revoked":
            if let name = invitation.revokedBy?.name?.nonEmpty { return LF("Revoked %@ by %@", ClientsText.shortDay(invitation.revokedAt), name) }
            return LF("Revoked %@", ClientsText.shortDay(invitation.revokedAt))
        case "awaiting_clinic":
            return acceptedBy(invitation).map { LF("Accepted by %@", $0) } ?? L("Accepted from another account")
        case "expired": return LF("Expired %@", DateText.ago(invitation.expiredAt ?? invitation.expiresAt))
        default: return LF("Expires %@@when", DateText.ago(invitation.expiresAt))
        }
    }

    /// How the timing line reads (web TimingTone): `urgent` a pending one about to run out, `warn` one the clinic confirms.
    enum Tone { case soft, warn, urgent, good }

    static func timingTone(_ invitation: ClientsInvitation) -> Tone {
        switch effectiveStatus(invitation) {
        case "accepted": .good
        case "awaiting_clinic": .warn
        case "pending": expiringSoon(invitation) ? .urgent : .soft
        default: .soft
        }
    }

    /// "Sent 3 oct by Ana" when an email went out; "Link created 3 oct by Ana" when it never did.
    static func sent(_ invitation: ClientsInvitation) -> String {
        let date = ClientsText.shortDay(invitation.createdAt)
        let name = invitation.createdBy?.name?.nonEmpty
        if !wasEmailed(invitation) { return name.map { LF("Link created %@ by %@", date, $0) } ?? LF("Link created %@", date) }
        return name.map { LF("Sent %@ by %@", date, $0) } ?? LF("Sent %@", date)
    }
}

/// One invitation's status as a soft pill with its dot (web `InvitationStatusChip`).
struct ClientsInvitationStatusTag: View {
    let status: String
    var body: some View {
        let state = ClientsInvitationWords.state(status)
        Chip(text: ClientsInvitationWords.chipLabel(status), tone: .custom(state.color), dot: state.color, percent: 24, ink: Theme.inkStrong)
    }
}

struct InvitationsScreen: View {
    var clientId: String? = nil

    @EnvironmentObject private var workspace: Workspace
    @State private var query = ""
    @State private var search = ""
    @State private var status: String?
    @State private var clientFilter: String?
    @State private var counts: [String: Int] = [:]
    @State private var notInvited: Int?
    @State private var expiringSoon = 0
    /// Each client's invitation still open (waiting on the family or on the clinic).
    @State private var openByClient: [String: ClientsInvitation] = [:]
    @State private var bulkOpen = false
    @State private var pickerOpen = false
    @State private var inviteClient: ClientsClient?
    @State private var revoking: ClientsInvitation?
    @State private var reviewing: ClientsInvitation?
    @State private var readdressing: ClientsInvitation?
    @State private var history: ClientsInvitation?
    @State private var resendingId: String?
    @State private var invitingAgainId: String?
    @State private var route: ProviderRoute?
    @StateObject private var pager = Pager<ClientsInvitation> { _, _ in Page(items: [], total: 0) }

    init(clientId: String? = nil) {
        self.clientId = clientId
        _clientFilter = State(initialValue: clientId)
    }

    private var canView: Bool { workspace.can(.clientsView) }
    private var canManage: Bool { workspace.can(.clientsEdit) }
    private var filtered: Bool { status != nil || !search.isEmpty || clientFilter != nil }

    var body: some View {
        Group {
            if workspace.inSetup {
                PageScroll {
                    ModuleHeader(icon: "mail-plus", title: L("Invitations"), subtitle: L("Link your clients’ families to your clinic on PawMiaw."), accent: Theme.aqua, storageKey: "invitations")
                    EmptyState(systemImage: "building-2", title: L("Finish workspace setup before inviting clients."), message: L("Invitations go out in your clinic’s name, so its basics need to be saved first."), accent: Theme.aqua, panel: true)
                }
            } else if !canView {
                PageScroll { NoAccessState(message: L("Ask the workspace owner to let your role see clients.")) }
            } else {
                content
            }
        }
        // From a client's page it is a page pushed over it; from the sidebar, a section.
        .providerPage(L("Invitations"), root: clientId == nil)
        .reloadsOnScope { await reloadAll() }
        .debounced(query) { value in
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard trimmed != search else { return }
            search = trimmed
            await reloadList()
        }
        .navigationDestination(item: $route) { RouteView(route: $0) }
        .sheet(isPresented: $bulkOpen) {
            ClientsBulkInviteSheet { client in
                bulkOpen = false
                Task { try? await Task.sleep(for: .milliseconds(450)); inviteClient = client }
            }
        }
        .sheet(isPresented: $pickerOpen) {
            ClientsInvitePicker(pending: openByClient) { client in
                pickerOpen = false
                Task { try? await Task.sleep(for: .milliseconds(450)); inviteClient = client }
            }
        }
        .sheet(item: $inviteClient, onDismiss: { Task { await reloadAll() } }) { client in ClientsInviteSheet(client: client) }
        .sheet(item: $revoking) { invitation in
            ClientsRevokeInvitationSheet(invitation: invitation) {
                await reloadAll()
                announceDataChanged()
            }
        }
        .sheet(item: $reviewing) { invitation in
            ClientsReviewAcceptanceSheet(invitation: invitation, canManage: canManage) { await reloadAll(); announceDataChanged() }
        }
        .sheet(item: $readdressing) { invitation in
            ClientsReaddressSheet(invitation: invitation) { await reloadAll() }
        }
        .sheet(item: $history) { invitation in ClientsInvitationHistorySheet(invitation: invitation) }
    }

    private var content: some View {
        PageScroll(refresh: { await reloadAll() }) {
            header
            if everCount == 0 && !filtered {
                EmptyState(
                    systemImage: "mail-plus",
                    title: L("No invitations yet"),
                    message: L("Invite a client and their family can link their PawMiaw household to your record — their pets, vaccines and notes stay in step with yours."),
                    actionTitle: canManage ? L("Invite a client") : L("Open clients"),
                    action: { if canManage { pickerOpen = true } else { route = .section(.clients) } },
                    accent: Theme.aqua,
                    panel: true
                )
            } else {
                listCard
            }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        let subtitle = L("When a family links, their own records reach your clinic and what you write reaches them in the app.")
        if canManage {
            ModuleHeader(icon: "mail-plus", title: L("Invitations"), subtitle: subtitle, accent: Theme.aqua, stats: headerStats, storageKey: "invitations") {
                PMButton(L("Invite many"), systemImage: "users-round", variant: .outline) { bulkOpen = true }
                PMButton(L("Invite a client"), systemImage: "user-plus") { pickerOpen = true }
            }
        } else {
            ModuleHeader(icon: "mail-plus", title: L("Invitations"), subtitle: subtitle, accent: Theme.aqua, stats: headerStats, storageKey: "invitations")
        }
    }

    private var headerStats: [ModuleStat] {
        let awaiting = counts["awaiting_clinic"] ?? 0
        var stats: [ModuleStat] = [
            ModuleStat("pending", label: L("Pending@filter"), value: counts["pending"].map(String.init) ?? "—",
                       hint: expiringSoon > 0 ? (expiringSoon == 1 ? L("1 expires within 2 days") : LF("%d expire within 2 days", expiringSoon)) : L("Waiting for the family"),
                       icon: "clock-3", accent: ClientsInvitationWords.state("pending").color,
                       active: status == "pending", action: { toggleStatus("pending") }),
        ]
        if awaiting > 0 || status == "awaiting_clinic" {
            stats.append(ModuleStat("awaiting", label: L("To confirm"), value: "\(awaiting)", hint: L("Accepted from another account"),
                                    icon: "shield-check", accent: ClientsInvitationWords.state("awaiting_clinic").color, attention: awaiting > 0,
                                    active: status == "awaiting_clinic", action: { toggleStatus("awaiting_clinic") }))
        }
        stats.append(ModuleStat("accepted", label: L("Linked@filter"), value: counts["accepted"].map(String.init) ?? "—", hint: L("Families on PawMiaw"),
                                icon: "link-2", accent: ClientsInvitationWords.state("accepted").color,
                                active: status == "accepted", action: { toggleStatus("accepted") }))
        stats.append(ModuleStat("expired", label: L("Expired@filter"), value: counts["expired"].map(String.init) ?? "—",
                                hint: (counts["expired"] ?? 0) > 0 ? L("Invite them again") : L("None ran out"),
                                icon: "mail-plus", accent: ClientsInvitationWords.state("expired").color,
                                active: status == "expired", action: { toggleStatus("expired") }))
        if let notInvited {
            stats.append(ModuleStat("not-invited", label: L("Not invited yet"), value: "\(notInvited)",
                                    hint: notInvited > 0 ? (canManage ? L("Choose who to invite") : L("Families not on PawMiaw")) : L("Everyone has been asked"),
                                    icon: "users-round", accent: Theme.lavender,
                                    action: notInvited > 0 ? { if canManage { bulkOpen = true } else { route = .section(.clients) } } : nil))
        }
        return stats
    }

    // MARK: The card

    private var listCard: some View {
        Card(padding: 0, spacing: 0) {
            VStack(spacing: 0) {
                SearchField(prompt: L("Name or email"), text: $query)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                RowDivider()
                // The statuses in the colours the rows and the header's numbers use.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: L("All"), count: everCount, isSelected: status == nil, tone: Theme.blue) { setStatus(nil) }
                        ForEach(ClientsInvitationWords.statuses, id: \.self) { value in
                            let tone = ClientsInvitationWords.state(value).color
                            FilterChip(title: ClientsInvitationWords.filterLabel(value), count: counts[value], isSelected: status == value, tone: tone, dot: tone) { toggleStatus(value) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                RowDivider()
                if clientFilter != nil {
                    HStack(spacing: 12) {
                        Text(LF("Only %@’s invitations", filterClientName)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Spacer(minLength: 8)
                        Button { clientFilter = nil; Task { await reloadList() } } label: {
                            HStack(spacing: 4) {
                                Glyph("x", size: 14)
                                Text(L("Show all"))
                            }
                            .font(Theme.text(14, weight: .bold))
                            .foregroundStyle(Theme.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.wash(Theme.aqua, 14))
                    RowDivider()
                }
                rows
                // How many, under the list (from the server's total).
                if let total = pager.total, total > 0 {
                    RowDivider()
                    Text(pager.isLoading ? L("Updating…") : LP(total, "%d invitation", "%d invitations"))
                        .font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    /// The rows, 20 at a time, with a hairline between them.
    @ViewBuilder
    private var rows: some View {
        if !pager.loadedOnce && pager.isLoading {
            LoadingState()
        } else if let error = pager.error, pager.items.isEmpty {
            ErrorState(message: error) { await pager.reload() }
        } else if pager.items.isEmpty {
            emptyList
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(pager.items.enumerated()), id: \.element.id) { index, invitation in
                    VStack(spacing: 0) {
                        if index > 0 { RowDivider() }
                        ClientsInvitationRow(
                            invitation: invitation, canManage: canManage,
                            resending: resendingId == invitation.id, invitingAgain: invitingAgainId == invitation.id,
                            offersInviteAgain: offersInviteAgain(invitation),
                            onResend: { resend(invitation) }, onRevoke: { revoking = invitation },
                            onReview: { reviewing = invitation }, onChangeEmail: { readdressing = invitation },
                            onInviteAgain: { inviteAgain(invitation) }, onHistory: { history = invitation },
                            onOpenClient: { route = .client(invitation.providerClientId) }
                        )
                    }
                    .onAppear { pager.loadMoreIfNeeded(invitation) }
                }
                PagerFooter(pager: pager)
            }
        }
    }

    private var emptyList: some View {
        let title: String = {
            if !search.isEmpty { return LF("Nothing matches “%@”", search) }
            if let status { return emptyTitle(status) }
            if clientFilter != nil { return LF("No invitations for %@ yet", filterClientName) }
            return L("No invitations here")
        }()
        let message = !search.isEmpty ? L("Try another name or email, or look at every invitation.") : status.map(emptyBody) ?? L("Invite a client, or look at every invitation.")
        // The web offers "Invite a client" and "Show every invitation"; one action fits here: the way back first.
        let actionTitle: String? = filtered ? L("Show every invitation") : (canManage ? L("Invite a client") : L("Open clients"))
        return EmptyState(systemImage: search.isEmpty ? "mail-plus" : "search", title: title, message: message, actionTitle: actionTitle, action: {
            if filtered {
                query = ""; search = ""; status = nil; clientFilter = nil
                Task { await reloadList() }
            } else if canManage {
                pickerOpen = true
            } else {
                route = .section(.clients)
            }
        }, accent: Theme.aqua)
    }

    private var everCount: Int? {
        let values = ClientsInvitationWords.statuses.compactMap { counts[$0] }
        return values.count == ClientsInvitationWords.statuses.count ? values.reduce(0, +) : nil
    }

    private var filterClientName: String {
        pager.items.first(where: { $0.providerClientId == clientFilter })?.client?.ownerName ?? L("this client")
    }

    private func emptyTitle(_ status: String) -> String {
        switch status {
        case "pending": L("No pending invitations")
        case "awaiting_clinic": L("Nothing waiting for your confirmation")
        case "accepted": L("No linked families yet")
        case "expired": L("No expired invitations")
        default: L("No revoked invitations")
        }
    }

    private func emptyBody(_ status: String) -> String {
        switch status {
        case "pending": L("Nobody is waiting to answer. Invite a client and it shows here until their family links.")
        case "awaiting_clinic": L("When a family accepts from another account than the one you invited, you confirm it here.")
        case "accepted": L("A family shows here once they accept your invitation.")
        case "expired": L("Invitations whose link ran out before the family answered show here, to invite them again.")
        default: L("Invitations you stop before the family answers show here.")
        }
    }

    /// One open invitation per client: an older one that ran out or was revoked offers nothing while a newer one waits.
    private func offersInviteAgain(_ invitation: ClientsInvitation) -> Bool {
        let state = ClientsInvitationWords.effectiveStatus(invitation)
        guard canManage, invitation.client?.householdId == nil, state == "expired" || state == "revoked" else { return false }
        if openByClient[invitation.providerClientId] != nil { return false }
        return invitation.latestForClient != false
    }

    private func toggleStatus(_ value: String) { setStatus(status == value ? nil : value) }

    private func setStatus(_ next: String?) {
        status = next
        Task { await reloadList() }
    }

    // MARK: Loading

    private func reloadAll() async {
        guard canView, !workspace.inSetup else { return }
        async let list: Void = reloadList()
        async let pending: Page<ClientsInvitation>? = ClientsClientPage.fetch(true, "/provider-client-invitations", ["limit": "50", "offset": "0", "status": "pending"])
        async let awaiting: Page<ClientsInvitation>? = ClientsClientPage.fetch(true, "/provider-client-invitations", ["limit": "50", "offset": "0", "status": "awaiting_clinic"])
        async let accepted: Page<ClientsInvitation>? = ClientsClientPage.fetch(true, "/provider-client-invitations", ["limit": "1", "offset": "0", "status": "accepted"])
        async let expired: Page<ClientsInvitation>? = ClientsClientPage.fetch(true, "/provider-client-invitations", ["limit": "1", "offset": "0", "status": "expired"])
        async let revoked: Page<ClientsInvitation>? = ClientsClientPage.fetch(true, "/provider-client-invitations", ["limit": "1", "offset": "0", "status": "revoked"])
        async let never: Page<ClientsClient>? = ClientsClientPage.fetch(true, "/provider-clients", ["limit": "1", "offset": "0", "unlinked": "true", "invitation": "none"])
        let pendingPage = await pending
        let awaitingPage = await awaiting
        var next: [String: Int] = [:]
        next["pending"] = pendingPage?.total
        next["awaiting_clinic"] = awaitingPage?.total
        next["accepted"] = await accepted?.total
        next["expired"] = await expired?.total
        next["revoked"] = await revoked?.total
        counts = next
        let live = (pendingPage?.items ?? []).filter { ClientsInvitationWords.effectiveStatus($0) == "pending" }
        expiringSoon = live.filter(ClientsInvitationWords.expiringSoon).count
        var open: [String: ClientsInvitation] = [:]
        for invitation in live + (awaitingPage?.items ?? []) where open[invitation.providerClientId] == nil {
            open[invitation.providerClientId] = invitation
        }
        openByClient = open
        notInvited = await never?.total
        await list
    }

    private func reloadList() async {
        let statusValue = status
        let q = search.nonEmpty
        let client = clientFilter
        pager.fetch = { offset, limit in
            try await API.get("/provider-client-invitations", query: ["limit": "\(limit)", "offset": "\(offset)", "status": statusValue, "search": q, "providerClientId": client])
        }
        await pager.reload()
    }

    // MARK: Actions

    private func resend(_ invitation: ClientsInvitation) {
        resendingId = invitation.id
        Task {
            defer { resendingId = nil }
            do {
                let _: ClientsInvitation = try await API.post("/provider-client-invitations/\(invitation.id)/resend")
                // The first email it ever gets isn't "again".
                Toast.show(ClientsInvitationWords.wasEmailed(invitation) ? LF("Sent again to %@.", invitation.recipientEmail ?? "") : LF("Sent to %@.", invitation.recipientEmail ?? ""))
                await reloadAll()
            } catch {
                Toast.error(error)
            }
        }
    }

    private func inviteAgain(_ invitation: ClientsInvitation) {
        invitingAgainId = invitation.id
        Task {
            defer { invitingAgainId = nil }
            do {
                inviteClient = try await API.get("/provider-clients/\(invitation.providerClientId)")
            } catch {
                Toast.error(L("Could not open this client. Try again."))
            }
        }
    }
}

// MARK: - A row

/// One invitation (web `InvitationRow`, the phone's stacked card): who it went
/// to, the pets it covers, where it stands, what can be done. The row opens
/// the client (or, waiting for the clinic, the confirmation).
private struct ClientsInvitationRow: View {
    let invitation: ClientsInvitation
    let canManage: Bool
    let resending: Bool
    let invitingAgain: Bool
    let offersInviteAgain: Bool
    let onResend: () -> Void
    let onRevoke: () -> Void
    let onReview: () -> Void
    let onChangeEmail: () -> Void
    let onInviteAgain: () -> Void
    let onHistory: () -> Void
    let onOpenClient: () -> Void

    private var status: String { ClientsInvitationWords.effectiveStatus(invitation) }

    var body: some View {
        let name = ClientsInvitationWords.name(invitation)
        let pending = status == "pending"
        let awaiting = status == "awaiting_clinic"
        let tone = ClientsInvitationWords.timingTone(invitation)
        // What needs someone today gets its colour down the left edge, as on Due.
        let stripe: Color? = awaiting || tone == .urgent ? ClientsInvitationWords.state(status).color : nil
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Avatar(name: name, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    if let email = invitation.recipientEmail?.nonEmpty {
                        Text(email).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                    if let line = clientRecordLine(name) {
                        Text(line).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            Group {
                pets
                VStack(alignment: .leading, spacing: 4) {
                    FlowLayout(spacing: 4) {
                        ClientsInvitationStatusTag(status: status)
                        if pending, let delivery { delivery }
                    }
                    // What is urgent first, then when it went out.
                    if tone == .urgent {
                        Chip(text: ClientsInvitationWords.timing(invitation), tone: .custom(Theme.mango), icon: "clock-3", percent: 30, ink: Theme.inkStrong)
                    } else {
                        Text(ClientsInvitationWords.timing(invitation))
                            .font(Theme.text(14, weight: tone == .warn ? .bold : .regular))
                            .foregroundStyle(tone == .soft ? Theme.inkSoft : Theme.inkStrong)
                            .lineLimit(1)
                    }
                    Text(awaiting ? LF("Invited: %@", invitation.recipientEmail ?? "") : ClientsInvitationWords.sent(invitation))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                actions(pending: pending, awaiting: awaiting, name: name)
            }
            .padding(.leading, 52)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { if let stripe { Rectangle().fill(stripe).frame(width: 6) } }
        .contentShape(Rectangle())
        .onTapGesture { if awaiting { onReview() } else { onOpenClient() } }
    }

    @ViewBuilder
    private var pets: some View {
        let pets = invitation.pets ?? []
        if pets.isEmpty {
            Text(L("No pets on it")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(pets, id: \.providerClientPetId) { pet in
                    let excluded = status == "accepted" && pet.consentDecision == "exclude"
                    let linked = status == "accepted" && (pet.consentDecision == "link_existing" || pet.consentDecision == "create_new")
                    HStack(spacing: 4) {
                        PetChip(name: pet.petName ?? "—", species: pet.petSpecies)
                            .strikethrough(excluded)
                            .opacity(excluded ? 0.55 : 1)
                        if linked { Glyph("check", size: 12).foregroundStyle(ProviderState.done.color) }
                    }
                    .accessibilityHint(excluded ? L("The family chose not to share this pet") : linked ? L("Linked to the family’s pet") : "")
                }
            }
        }
    }

    private func actions(pending: Bool, awaiting: Bool, name: String) -> some View {
        let canRevoke = canManage && (pending || awaiting)
        return FlowLayout(spacing: 6) {
            if awaiting {
                PMButton(canManage ? L("Review") : L("See who"), systemImage: "shield-check", size: .compact, action: onReview)
            } else if offersInviteAgain {
                PMButton(L("Invite again"), systemImage: "rotate-cw", variant: .outline, size: .compact, isWorking: invitingAgain, action: onInviteAgain)
            }
            if pending {
                PMButton(L("Copy link"), systemImage: "copy", variant: .outline, size: .compact) {
                    clientsCopy(invitation.url, done: L("Invitation link copied."))
                }
            }
            if canManage && pending {
                PMButton(ClientsInvitationWords.wasEmailed(invitation) ? L("Resend") : L("Send by email"), systemImage: "mail-plus", variant: .outline, size: .compact, isWorking: resending, action: onResend)
            }
            if canRevoke && pending {
                PMButton(L("Revoke"), systemImage: "trash-2", variant: .destructive, size: .compact, action: onRevoke)
            }
            Menu {
                if canManage && pending { Button { onChangeEmail() } label: { GlyphLabel(L("Change email"), icon: "at-sign") } }
                if pending, let url = invitation.url.flatMap(URL.init(string:)) {
                    ShareLink(item: url) { GlyphLabel(L("Share link"), icon: "share") }
                }
                Button { onOpenClient() } label: { GlyphLabel(L("Open client"), icon: "user-round") }
                Button { onHistory() } label: { GlyphLabel(L("History@invitation"), icon: "history") }
                // A pending invitation has Revoke on the row itself.
                if canRevoke && !pending {
                    Divider()
                    Button(role: .destructive) { onRevoke() } label: { GlyphLabel(L("Revoke"), icon: "trash-2") }
                }
            } label: {
                IconCircleButton(systemImage: "ellipsis", label: LF("More for %@", name)) {}
                    .allowsHitTesting(false)
            }
            .accessibilityLabel(LF("More for %@", name))
        }
    }

    private func clientRecordLine(_ name: String) -> String? {
        guard let clientName = invitation.client?.ownerName?.nonEmpty, clientName.lowercased() != name.lowercased() else { return nil }
        return LF("Client record: %@", clientName)
    }

    /// Whether the email went out, failed, or the link was only copied.
    private var delivery: Chip? {
        switch invitation.emailStatus {
        case "sent": Chip(text: L("Email sent"), tone: .custom(ProviderState.done.color), icon: "mail-check", percent: 16, ink: Theme.inkStrong)
        case "failed": Chip(text: L("Email failed"), tone: .custom(Theme.destructive), icon: "mail-x", percent: 12, ink: Theme.destructive)
        case "queued", "sending": Chip(text: L("Sending email…"), tone: .muted, icon: "mail", ink: Theme.inkSoft, weight: .semibold, outlined: true)
        case "not_attempted", "skipped": Chip(text: L("Link only"), tone: .muted, icon: "link-2", ink: Theme.inkSoft, weight: .semibold, outlined: true)
        default: nil
        }
    }
}

// MARK: - The invitation in a sheet

/// Who an invitation went to and where it stands (web `InvitationSummary`), at the top of the revoke and history sheets.
private struct ClientsInvitationSummary: View {
    let invitation: ClientsInvitation

    var body: some View {
        let status = ClientsInvitationWords.effectiveStatus(invitation)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ClientsInvitationWords.name(invitation)).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    if let email = invitation.recipientEmail { Text(email).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                }
                Spacer(minLength: 8)
                ClientsInvitationStatusTag(status: status)
            }
            VStack(alignment: .leading, spacing: 6) {
                ClientsTermRow(label: L("Pets"), value: (invitation.pets ?? []).compactMap(\.petName).joined(separator: ", ").nonEmpty ?? "—")
                // "Sent" only when an email went out; a link shared by hand was created.
                ClientsTermRow(label: ClientsInvitationWords.wasEmailed(invitation) ? L("Sent@invitation") : L("Created@invitation"),
                               value: ClientsText.dayTime(invitation.createdAt) + (invitation.createdBy?.name?.nonEmpty.map { " · \($0)" } ?? ""))
                if status == "pending" { ClientsTermRow(label: L("Expires@invitation"), value: ClientsText.dayTime(invitation.expiresAt)) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }
}

/// A term and its value in a sheet's box (web `<dl>`): 14 grey label in a fixed column, the value 14 semibold.
private struct ClientsTermRow: View {
    let label: String
    let value: String
    var width: CGFloat = 80
    var icon: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).frame(width: width, alignment: .leading)
            HStack(spacing: 6) {
                if let icon { Glyph(icon, size: 14).foregroundStyle(Theme.inkSoft) }
                Text(value).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Revoke

/// Revoking stops the link from working; the invitation stays in the history.
private struct ClientsRevokeInvitationSheet: View {
    let invitation: ClientsInvitation
    let onRevoked: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        ProviderModal(
            title: L("Revoke this invitation?"),
            subtitle: L("The link stops working. You can invite them again later."),
            systemImage: "triangle-alert",
            accent: .pink,
            primaryTitle: L("Revoke invitation"),
            primaryVariant: .destructive,
            isWorking: working,
            cancelTitle: L("Keep it"),
            primaryIcon: "triangle-alert",
            onPrimary: { revoke() }
        ) {
            ClientsInvitationSummary(invitation: invitation)
            Text(L("If the family opens the link, they’ll see that the invitation is no longer valid.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        }
        .presentationDetents([.medium, .large])
    }

    private func revoke() {
        working = true
        Task {
            defer { working = false }
            do {
                let _: ClientsInvitation = try await API.delete("/provider-client-invitations/\(invitation.id)")
                Toast.show(L("Invitation revoked."))
                await onRevoked()
                dismiss()
            } catch {
                Toast.error(error)
            }
        }
    }
}

// MARK: - Confirm an acceptance from another account

/// Someone accepted from another account than the one invited. Nothing is
/// shared until the clinic says it's the right person: Confirmar links what
/// they chose; "No es esta persona" (a second step) puts it back to waiting.
struct ClientsReviewAcceptanceSheet: View {
    let invitation: ClientsInvitation
    let canManage: Bool
    let onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var approving = false
    @State private var declining = false
    @State private var confirmingDecline = false
    @State private var problem: String?

    private var account: ClientsPendingAccount? { invitation.pendingAcceptance?.account }
    private var who: String { account?.name?.nonEmpty ?? account?.email ?? L("Someone") }

    var body: some View {
        Group {
            if confirmingDecline {
                ProviderModal(
                    title: L("Not this person?"),
                    subtitle: LF("Invitation for %@", invitation.recipientEmail ?? ""),
                    systemImage: "user-round-x",
                    accent: .pink,
                    primaryTitle: L("Yes, it’s not them"),
                    primaryVariant: .destructive,
                    isWorking: declining,
                    onBack: { confirmingDecline = false },
                    primaryIcon: "user-round-x",
                    onPrimary: { decline() }
                ) {
                    Text(LF("Nothing is shared with %@. We’ll tell them the clinic didn’t confirm the connection.", who)).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    Text(LF("The invitation goes back to waiting for %@, and its link keeps working for them.", invitation.recipientEmail ?? "")).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                }
            } else {
                ProviderModal(
                    title: L("Confirm who accepted"),
                    subtitle: LF("Invitation for %@", invitation.recipientEmail ?? ""),
                    systemImage: "shield-check",
                    accent: .coral,
                    primaryTitle: canManage ? L("Confirm") : nil,
                    isWorking: approving,
                    cancelTitle: L("Close"),
                    // "No es esta persona" sits in the footer beside Confirmar (a second step asks first); the web has no Cancel there.
                    secondaryActions: canManage ? [ModalAction(L("It’s not this person"), icon: "user-round-x") { confirmingDecline = true }] : [],
                    primaryIcon: "check",
                    showsCancel: !canManage,
                    onPrimary: canManage ? { approve() } : nil
                ) {
                    Text(LF("%@ accepted from an account other than the email you invited. Nothing is shared until you confirm it’s the right person.", who)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    if let problem {
                        NoticeCard(tone: .problem, title: problem, message: L("Choose “It’s not this person”, then invite the family again so they can choose again."))
                    }
                    accountBox
                    ModalSection(title: L("Their choices"), subtitle: L("Your pets on the invitation, and what the family chose for each.")) {
                        choices
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Who accepted: their account, their household, whom it was sent to, when.
    private var accountBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Avatar(name: account?.name?.nonEmpty ?? account?.email ?? "?", size: 40, tint: Theme.coral)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account?.name?.nonEmpty ?? L("No name on the account")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text(account?.email ?? "—").font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ClientsTermRow(label: L("Household"), value: invitation.pendingAcceptance?.household?.name?.nonEmpty ?? "—", width: 96, icon: "house")
                ClientsTermRow(label: L("Invited"), value: [ClientsInvitationWords.name(invitation), invitation.recipientEmail].compactMap { $0 }.joined(separator: " · "), width: 96)
                if let at = invitation.pendingAcceptance?.requestedAt {
                    ClientsTermRow(label: L("Accepted"), value: ClientsText.dayTime(at), width: 96)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    /// Each pet → what the family chose for it.
    private var choices: some View {
        let pets = invitation.pets ?? []
        return VStack(spacing: 0) {
            ForEach(Array(pets.enumerated()), id: \.element.providerClientPetId) { index, pet in
                if index > 0 { RowDivider() }
                let decision = invitation.pendingAcceptance?.decisions?.first { $0.providerClientPetId == pet.providerClientPetId }
                FlowLayout(spacing: 8, lineSpacing: 4) {
                    Text(pet.petName ?? "—").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    Glyph("arrow-right", size: 14).foregroundStyle(Theme.inkSoft)
                    choiceText(decision)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    @ViewBuilder
    private func choiceText(_ decision: ClientsPendingDecision?) -> some View {
        switch decision?.decision {
        case "link_existing":
            Text(LF("Their %@", decision?.householdPetName ?? L("pet"))).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.blue)
        case "create_new":
            Text(L("A new pet in their PawMiaw")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
        case "exclude":
            Text(L("Not shared")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft).strikethrough(color: Theme.borderSoft)
        default:
            Text(L("No answer")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft).strikethrough(color: Theme.borderSoft)
        }
    }

    private func approve() {
        approving = true
        problem = nil
        Task {
            defer { approving = false }
            do {
                let _: ClientsInvitation = try await API.post("/provider-client-invitations/\(invitation.id)/approve")
                Toast.show(LF("Confirmed. %@ is linked to your clinic.", who))
                await onDone()
                dismiss()
            } catch {
                // The family's choices no longer fit: say why and suggest starting over.
                if (error as? APIError)?.status == 409 { problem = errorText(error) } else { Toast.error(error) }
            }
        }
    }

    private func decline() {
        declining = true
        Task {
            defer { declining = false }
            do {
                let _: ClientsInvitation = try await API.post("/provider-client-invitations/\(invitation.id)/decline")
                Toast.show(LF("Declined. The invitation is waiting for %@ again.", invitation.recipientEmail ?? ""))
                await onDone()
                dismiss()
            } catch {
                Toast.error(error)
            }
        }
    }
}

// MARK: - Change the email of a pending invitation

/// Cambiar correo: a pending invitation goes to someone else. A new link is
/// made (the old one stops working) and the invitation runs at least a week.
struct ClientsReaddressSheet: View {
    let invitation: ClientsInvitation
    let onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var email: String
    @State private var name: String
    @State private var sendEmail: Bool
    @State private var saving = false
    @State private var shareURL: URL?

    init(invitation: ClientsInvitation, onDone: @escaping () async -> Void) {
        self.invitation = invitation
        self.onDone = onDone
        _email = State(initialValue: invitation.recipientEmail ?? "")
        _name = State(initialValue: invitation.recipientName ?? "")
        // As it was shared the first time: an invitation that went by email goes by email, a copied link is copied again.
        _sendEmail = State(initialValue: ClientsInvitationWords.wasEmailed(invitation))
    }

    private var dirty: Bool { email != (invitation.recipientEmail ?? "") || name != (invitation.recipientName ?? "") }

    var body: some View {
        ProviderModal(
            title: L("Change email"),
            subtitle: LF("Invitation for %@", invitation.client?.ownerName ?? ClientsInvitationWords.name(invitation)),
            systemImage: "at-sign",
            accent: .aqua,
            isDirty: dirty && shareURL == nil,
            form: form,
            primaryTitle: sendEmail ? L("Save and send") : L("Save"),
            isWorking: saving,
            primaryIcon: sendEmail ? "mail-plus" : "check"
        ) {
            save()
        } content: {
            PMTextField(L("Email"), text: $email, key: "recipientEmail", form: form, keyboard: .emailAddress)
            PMTextField(L("Name"), text: $name, key: "recipientName", form: form, prompt: invitation.client?.ownerName, capitalization: .words)
            ToggleRow(title: L("Send the invitation email"), subtitle: sendEmail ? L("We email the new link to this address.") : L("We copy the new link for you to share."), isOn: $sendEmail)
            NoticeCard(tone: .custom(Theme.aqua), message: L("A new link is made: the previous one stops working. The invitation stays open at least another week."), icon: nil)
            if let shareURL {
                ShareLink(item: shareURL) { GlyphLabel(L("Share link"), icon: "share") }.buttonStyle(.pm(.outline, fullWidth: true))
            }
        }
    }

    private func save() {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        let sameName = (name.nonEmpty?.trimmingCharacters(in: .whitespaces)) == (invitation.recipientName?.nonEmpty?.trimmingCharacters(in: .whitespaces))
        guard form.check([
            ("recipientEmail", !ClientsText.emailLooksValid(trimmed) ? L("Write a valid email.") : trimmed.lowercased() == invitation.recipientEmail?.lowercased() && sameName ? L("That’s the email it already has.") : nil),
        ]) else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let updated: ClientsInvitation = try await API.patch("/provider-client-invitations/\(invitation.id)", body: ["recipientEmail": trimmed, "recipientName": name.nonEmpty, "sendEmail": sendEmail])
                if sendEmail {
                    Toast.show(LF("Sent to %@. The old link no longer works.", updated.recipientEmail ?? trimmed))
                    await onDone()
                    dismiss()
                } else {
                    clientsCopy(updated.url, done: L("Saved. The new link is copied; the old one no longer works."))
                    shareURL = updated.url.flatMap(URL.init(string:))
                    await onDone()
                    if shareURL == nil { dismiss() }
                }
            } catch {
                form.apply(error, known: ["recipientEmail": "recipientEmail", "recipientName": "recipientName"])
            }
        }
    }
}

// MARK: - Choose a client to invite

/// Choose who to invite (web `InviteClientPicker`): the clients whose family
/// isn't on PawMiaw yet; picking one and Continuar moves on to the
/// invitation itself (email, pets, how long it lasts).
struct ClientsInvitePicker: View {
    /// Each client's invitation still out, to mark them.
    var pending: [String: ClientsInvitation] = [:]
    let onPick: (ClientsClient) -> Void

    @StateObject private var form = FormState()
    @State private var query = ""
    @State private var selected: ClientsClient?
    @StateObject private var pager = Pager<ClientsClient> { _, _ in Page(items: [], total: 0) }

    init(pending: [String: ClientsInvitation] = [:], onPick: @escaping (ClientsClient) -> Void) {
        self.pending = pending
        self.onPick = onPick
    }

    var body: some View {
        ProviderModal(
            title: L("Invite a client"),
            subtitle: L("Choose a client whose family isn’t on PawMiaw yet."),
            systemImage: "mail-plus",
            accent: .aqua,
            form: form,
            primaryTitle: L("Continue"),
            // The web's footer line: what Continue leads to.
            footerSummary: AnyView(
                Text(selected == nil ? L("Pick a client to continue.") : L("Next: the email, the pets and how long the link lasts."))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            ),
            onPrimary: {
                guard form.check([("client", selected == nil ? L("Pick a client to continue.") : nil)]), let selected else { return }
                onPick(selected)
            }
        ) {
            SearchField(prompt: L("Client, pet, email or phone"), text: $query, shape: .field)
            Group {
                if !pager.loadedOnce && pager.isLoading {
                    LoadingState()
                } else if let error = pager.error, pager.items.isEmpty {
                    ErrorState(message: error) { await pager.reload() }
                } else if pager.items.isEmpty {
                    let searched = ClientSearch.query(query)
                    EmptyState(systemImage: searched == nil ? "house" : "search",
                               title: searched.map { LF("No client matches “%@”", $0) } ?? L("Every client is already on PawMiaw"),
                               message: searched == nil ? L("New clients you add show up here until their family links.") : L("Families already linked don’t show here."),
                               accent: Theme.aqua)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(pager.items) { client in
                            row(client).onAppear { pager.loadMoreIfNeeded(client) }
                        }
                        PagerFooter(pager: pager)
                    }
                }
            }
            .id("client")
        }
        .debounced(query) { value in
            // The client search's one rule: the server searches from two letters, 20 at a time.
            let q = ClientSearch.query(value)
            pager.fetch = { offset, limit in
                try await API.get("/provider-clients", query: ["limit": "\(limit)", "offset": "\(offset)", "unlinked": "true", "sort": "name", "search": q])
            }
            await pager.reload()
        }
    }

    private func row(_ client: ClientsClient) -> some View {
        let active = selected?.id == client.id
        let pets = client.allPets.filter { !$0.isArchived }
        let contact = client.ownerEmail?.nonEmpty ?? client.ownerPhone?.nonEmpty ?? L("No email or phone yet")
        let open = pending[client.id]
        return Button {
            selected = active ? nil : client
            form.clear("client")
        } label: {
            HStack(spacing: 12) {
                Avatar(name: client.ownerName, imageURL: client.photoUrl, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(client.ownerName).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text([contact, pets.map(\.petName).joined(separator: ", ").nonEmpty].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    if let open, open.status == "pending" {
                        Chip(text: LF("Invited · expires %@", DateText.ago(open.expiresAt)), tone: .custom(Theme.mango), percent: 24, ink: Theme.inkStrong)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                Tick(on: active, style: .choice)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(active ? AnyShapeStyle(Theme.wash(Theme.blue, 8)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(active ? Theme.blue : Theme.borderSoft, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

// MARK: - One invitation's history

/// Everything that happened to one invitation: sent, resent, opened, accepted, revoked.
private struct ClientsInvitationHistorySheet: View {
    let invitation: ClientsInvitation

    var body: some View {
        ProviderModal(title: L("Invitation history@sheet"), subtitle: invitation.recipientEmail, systemImage: "history", accent: .aqua, cancelTitle: L("Close")) {
            ClientsInvitationSummary(invitation: invitation)
            ModalSection(title: L("What happened")) {
                AuditHistoryCard(entityType: "provider_client_invitation", entityId: invitation.id, title: L("Activity"), description: L("Who sent, resent or revoked it, and when the family answered."), startsOpen: true)
            }
        }
        .presentationDetents([.large])
    }
}
