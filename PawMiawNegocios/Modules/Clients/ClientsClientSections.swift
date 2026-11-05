//
//  ClientsClientSections.swift
//  PawMiawNegocios
//
//  The parts of a client's page below the pets (web: client-page/,
//  addresses/client-home-section.tsx, online-booking/client-online-booking.tsx):
//  the link to the family on PawMiaw with "Puede reservar en línea", the
//  visits, the account (money level 1 or more) and the home & contact.
//

import SwiftUI

// MARK: - The family on PawMiaw

/// "Familia vinculada" / "Invitación pendiente" (web `ClientLinkStatus`): who is
/// linked, "Puede reservar en línea", the open invitation's link and email,
/// unlinking a pet. The name the family uses on PawMiaw, when it differs,
/// opens the card with "Usar este nombre" (the web shows it under the
/// header's title, which takes text only here).
struct ClientsLinkCard: View {
    @ObservedObject var page: ClientsClientPage
    let client: ClientsClient
    let canManage: Bool
    var renaming: Bool = false
    /// "Usar este nombre": the family's own name from PawMiaw becomes the client's name.
    var onUseLinkedName: ((String) -> Void)? = nil
    let onOpenInvitations: () -> Void
    /// "Desvincular a {mascota}": the unlink sheet for one linked pet.
    var onUnlink: ((ClientsPet) -> Void)? = nil

    @State private var savingBooking: Bool?
    @State private var resending = false
    @State private var confirmRevoke = false

    /// The family calls themselves something else in PawMiaw ("José" here, "Alejandro Pérez" there).
    private var linkedName: String? {
        guard client.isLinked, let name = client.linkedAccountName?.nonEmpty else { return nil }
        let fold = { (text: String) in text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespaces) }
        return fold(name) == fold(client.ownerName) ? nil : name
    }

    var body: some View {
        let pending = page.pendingInvitation
        if client.isLinked || pending != nil {
            Card(spacing: 12) {
                if let linkedName {
                    HStack(spacing: 8) {
                        (Text("\(L("On PawMiaw:")) ").foregroundStyle(Theme.inkSoft) + Text(linkedName).bold().foregroundStyle(Theme.inkStrong))
                            .font(Theme.text(14))
                        if canManage, let onUseLinkedName {
                            PMButton(L("Use this name"), variant: .outline, size: .compact, isWorking: renaming) { onUseLinkedName(linkedName) }
                        }
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(client.isLinked ? L("Family linked") : L("Invitation pending"))
                            .font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                        if client.isLinked {
                            let linkedPets = client.allPets.filter { $0.isActive && $0.isLinked }.map(\.petName).joined(separator: ", ")
                            Text(LF("Linked pets: %@", linkedPets.nonEmpty ?? "—")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        } else if let pending {
                            let sent = pending.emailStatus == "sent" ? LF("Invitation sent to %@", pending.recipientEmail ?? "—") : LF("Invitation link created for %@", pending.recipientEmail ?? "—")
                            Text("\(sent) · \(LF("Expires %@", ClientsText.dayTime(pending.expiresAt)))").font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    Spacer(minLength: 8)
                    PMButton(L("Invitation history"), variant: .outline, size: .compact, action: onOpenInvitations)
                }
                // "Puede reservar en línea": a family that connected by itself books only once you allow it (docs/online-booking.md §1).
                if client.isLinked && !client.isArchived {
                    let allowed = savingBooking ?? client.canBookOnline ?? (client.businessLinkedAt != nil)
                    VStack(alignment: .leading, spacing: 6) {
                        ToggleRow(
                            title: L("Can book online"),
                            subtitle: allowed ? L("They book visits with you from the app, inside your hours.") : L("A family that connected by itself can’t book until you allow it."),
                            isOn: Binding(get: { allowed }, set: { setOnlineBooking($0) })
                        )
                        .disabled(!canManage || savingBooking != nil)
                        if !canManage {
                            Text(L("Only someone who edits clients changes this.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                if client.isLinked && canManage, let onUnlink {
                    let linked = client.allPets.filter { $0.isActive && $0.isLinked }
                    if !linked.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(linked) { pet in
                                PMButton(LF("Unlink %@", pet.petName), systemImage: "link-2-off", variant: .outline, size: .compact) { onUnlink(pet) }
                            }
                        }
                    }
                }
                if let pending, canManage {
                    FlowLayout(spacing: 8) {
                        PMButton(L("Copy invitation link"), systemImage: "copy", variant: .outline, size: .compact) { clientsCopy(pending.url, done: L("Invitation link copied.")) }
                        if let url = pending.url.flatMap(URL.init(string:)) {
                            ShareLink(item: url) { GlyphLabel(L("Share link"), icon: "share") }
                                .buttonStyle(.pm(.outline, size: .compact))
                        }
                        PMButton(pending.emailStatus == "sent" ? L("Resend email") : L("Send by email"), systemImage: pending.emailStatus == "sent" ? "rotate-cw" : "mail-plus", variant: .outline, size: .compact, isWorking: resending) { resend(pending) }
                        PMButton(L("Revoke invitation"), variant: .outline, size: .compact) { confirmRevoke = true }
                    }
                }
            }
            .sheet(isPresented: $confirmRevoke) {
                if let pending {
                    ConfirmSheet(title: L("Revoke invitation"), message: L("The link stops working. The family can be invited again."), confirmTitle: L("Confirm revoke"), destructive: true) { _ in
                        let _: ClientsInvitation = try await API.delete("/provider-client-invitations/\(pending.id)")
                        Toast.show(L("Invitation revoked."))
                        await reload()
                    }
                }
            }
        }
    }

    private func reload() async {
        let id = client.id
        if let page: Page<ClientsInvitation> = try? await API.get("/provider-client-invitations", query: ["limit": "10", "offset": "0", "providerClientId": id]) {
            self.page.invitations = page.items
        }
        announceDataChanged()
    }

    private func resend(_ invitation: ClientsInvitation) {
        resending = true
        Task {
            defer { resending = false }
            do {
                let _: ClientsInvitation = try await API.post("/provider-client-invitations/\(invitation.id)/resend")
                // "Again" only when it had gone out before.
                Toast.show(invitation.emailStatus == "sent" ? L("Invitation email sent again.") : L("Invitation email sent."))
                await reload()
            } catch {
                Toast.error(error, fallback: L("Could not resend the invitation."))
            }
        }
    }

    private func setOnlineBooking(_ allowed: Bool) {
        savingBooking = allowed
        Task {
            defer { savingBooking = nil }
            do {
                let answer: ClientsOnlineBookingAnswer = try await API.put("/provider-clients/\(client.id)/online-booking", body: ["allowed": allowed])
                if let updated = answer.client { page.client = updated }
                Toast.show(allowed ? LF("%@ can book online now.", client.ownerName) : LF("%@ can’t book online anymore.", client.ownerName))
                announceDataChanged()
            } catch {
                Toast.error(error)
            }
        }
    }
}

// MARK: - A section card's band and figures

/// A band across a section card (web: the grey sub-heading strip, "Próximas", "Últimas cuentas"): 14 bold on the muted surface.
private struct ClientsCardBand<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceMuted)
            RowDivider()
        }
    }
}

extension ClientsCardBand where Trailing == EmptyView {
    init(title: String) { self.init(title: title, trailing: { EmptyView() }) }
}

/// A section card's header actions on their own row: beside the title on an
/// iPad, under it on a phone (the web's header row wraps).
private struct ClientsSectionActions<Actions: View>: View {
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) { actions(); Spacer(minLength: 0) }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            RowDivider()
        }
    }
}

// MARK: - Visits

/// The client's visits across all their pets (web `ClientVisits`): what is
/// coming and the last few that happened. Each row opens its visit.
struct ClientsVisitsSection: View {
    @ObservedObject var page: ClientsClientPage
    var clientName: String = ""
    let onBook: (() -> Void)?

    private var empty: Bool { page.visitsLoaded && !page.visitsFailed && page.upcoming.isEmpty && page.earlier.isEmpty }

    var body: some View {
        SectionCard(title: L("Visits"), subtitle: L("Upcoming and recent visits of all their pets."), icon: "calendar-days", accent: Theme.aqua) {
            if !empty, let onBook { PMButton(L("Book"), systemImage: "calendar-plus", variant: .outline, size: .compact, action: onBook) }
        } content: {
            if !page.visitsLoaded {
                LoadingState()
            } else if page.visitsFailed {
                Text(L("Could not load the visits.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    .padding(16)
            } else if empty {
                EmptyState(systemImage: "calendar-days", title: L("No visits yet"), message: onBook != nil ? L("Book the first visit and it will show up here.") : nil,
                           actionTitle: onBook != nil ? L("Book a visit") : nil, action: onBook, accent: Theme.mango)
            } else {
                group(L("Upcoming"), page.upcoming, empty: L("Nothing booked ahead."), last: page.earlier.isEmpty)
                if !page.earlier.isEmpty { group(L("Earlier"), page.earlier, empty: nil, last: true) }
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ visits: [ClientsAppointment], empty: String?, last: Bool) -> some View {
        ClientsCardBand(title: title)
        if visits.isEmpty, let empty {
            Text(empty).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 16).padding(.vertical, 12)
            if !last { RowDivider() }
        }
        ForEach(visits) { visit in
            NavigationLink(value: ProviderRoute.appointment(visit.id)) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(ClientsText.relativeShortDay(visit.startsAt)).font(.brandHeading(15.2)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Text(DateText.time(visit.startsAt)).font(Theme.text(12)).monospacedDigit().foregroundStyle(Theme.inkSoft)
                    }
                    .frame(width: 64, alignment: .leading)
                    PetAvatar(name: visit.petName, species: visit.petSpecies, photoURL: visit.petPhotoUrl, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(visit.petName ?? "—").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Text("\(visit.serviceLabel ?? "—") · \(visit.assignedMember?.name?.nonEmpty ?? L("Nobody assigned"))").font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                        // On a phone the pills go under the visit.
                        FlowLayout(spacing: 4) {
                            StatusChip(text: ClientsText.visitStatus(visit.status), state: ProviderState.appointment(visit.status))
                            if visit.onlineBooking == true { Chip(text: L("Online"), tone: .online, icon: "globe") }
                        }
                        .padding(.top, 4)
                    }
                    Spacer(minLength: 8)
                    Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !last || visit.id != visits.last?.id { RowDivider() }
        }
    }
}

// MARK: - Account

/// The client's money in one place (web `ClientAccountSection`): what they
/// owe, what is late, their credit and their latest bills. "Cobrar" only when
/// something is owed.
struct ClientsAccountSection: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject var page: ClientsClientPage
    let client: ClientsClient

    @State private var collecting: ClientsCollectTarget?
    @State private var openingAccount = false

    var body: some View {
        let account = page.account
        let money = { (cents: Int) in Money.format(cents, currency: account?.currency) }
        let owed = account?.owed ?? 0
        let overdue = account?.overdue ?? 0
        let credit = account?.credit ?? 0
        let loading = account == nil && !page.billsLoaded
        SectionCard(title: L("Account"), subtitle: L("What they owe, their credit and their latest bills."), icon: "badge-dollar-sign", accent: Theme.aqua) {
            if sizeClass == .regular { actions(owed: owed) }
        } content: {
            if sizeClass != .regular { ClientsSectionActions { actions(owed: owed) } }
            HStack(spacing: 0) {
                figure(L("Owes"), loading: loading, tone: owed > 0 ? Theme.pink : nil) {
                    owed > 0 ? AnyView(amount(money(owed))) : AnyView(quiet(L("Nothing owed")))
                }
                Rectangle().fill(Theme.borderSoft).frame(width: 1)
                figure(L("Overdue"), loading: loading, tone: overdue > 0 ? Theme.destructive : nil) {
                    overdue > 0 ? AnyView(amount(money(overdue), danger: true)) : AnyView(quiet(L("Nothing overdue")))
                }
                Rectangle().fill(Theme.borderSoft).frame(width: 1)
                figure(L("Credit"), loading: loading, tone: credit > 0 ? Theme.lime : nil) {
                    credit > 0 ? AnyView(amount(money(credit))) : AnyView(quiet(L("No credit")))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            RowDivider()
            ClientsCardBand(title: L("Latest bills")) {
                if page.billsTotal > page.bills.count && workspace.moneyLevel >= .frontDesk {
                    NavigationLink(value: ProviderRoute.section(.invoices)) {
                        Text(L("See all bills")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !page.billsLoaded {
                LoadingState()
            } else if page.bills.isEmpty {
                HStack(spacing: 8) {
                    Glyph("receipt-text", size: 16)
                    Text(L("No bills yet"))
                }
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                .padding(16)
            } else {
                ForEach(Array(page.bills.enumerated()), id: \.element.id) { index, invoice in
                    if index > 0 { RowDivider() }
                    NavigationLink(value: ProviderRoute.invoice(invoice.id)) {
                        ClientsBillRow(invoice: invoice)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $collecting) { target in
            CashCollectSheet(account: target.account) { Task { await reload() } }
        }
    }

    @ViewBuilder
    private func actions(owed: Int) -> some View {
        if owed > 0 && workspace.can(.salesSell) {
            // The Store's counter collects the client's open bills.
            NavigationLink(value: ProviderRoute.storeCheckout(StorePrefill(clientId: client.id))) { GlyphLabel(L("Collect"), icon: "hand-coins") }
                .buttonStyle(.pm(.primary, size: .compact))
        } else if owed > 0 && workspace.can(.billingRecordPayment) {
            // Without the Store: one payment, applied to the oldest debt first (the account's own sheet).
            PMButton(L("Collect"), systemImage: "hand-coins", size: .compact, isWorking: openingAccount) { collect() }
        }
        NavigationLink { CashAccountScreen(clientId: client.id) } label: { Text(L("See account")) }
            .buttonStyle(.pm(.outline, size: .compact))
    }

    /// One of the three figures (web `Figure`): its uppercase label and the amount in
    /// Fredoka, washed in its colour when there is something; quiet words when not.
    private func figure(_ label: String, loading: Bool, tone: Color?, @ViewBuilder value: () -> AnyView) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.brandText(10.6, weight: .heavy)).tracking(1.06).foregroundStyle(Theme.inkSoft).lineLimit(1)
            if loading {
                ProgressView().controlSize(.small)
            } else {
                value()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tone.map { AnyShapeStyle(Theme.wash($0, 9)) } ?? AnyShapeStyle(Theme.surface))
    }

    private func amount(_ text: String, danger: Bool = false) -> some View {
        Text(text).font(.brandHeading(18)).foregroundStyle(danger ? Theme.destructive : Theme.inkStrong).lineLimit(2).minimumScaleFactor(0.7)
    }

    private func quiet(_ text: String) -> some View {
        Text(text).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
    }

    private func collect() {
        openingAccount = true
        Task {
            defer { openingAccount = false }
            do {
                collecting = ClientsCollectTarget(account: try await API.get("/provider-finance/clients/\(client.id)/account"))
            } catch {
                Toast.error(error, fallback: L("This account could not be loaded."))
            }
        }
    }

    private func reload() async {
        page.account = try? await API.get("/provider-finance/clients/\(client.id)/account")
        announceDataChanged()
    }
}

/// The account a payment is taken on (Money's collect sheet).
private struct ClientsCollectTarget: Identifiable {
    let id = UUID()
    let account: CashAccount
}

/// One bill (web `BillRow`): its number and state, the day and pet, the total
/// in Fredoka and what is left to pay.
struct ClientsBillRow: View {
    let invoice: ClientsInvoice

    var body: some View {
        let pending = (invoice.balanceDueAmount ?? 0) > 0 && !["paid", "canceled", "draft"].contains(invoice.status ?? "")
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                FlowLayout(spacing: 8) {
                    Text(invoice.invoiceNumber ?? "—").font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong).lineLimit(1)
                    StatusChip(text: ClientsText.invoiceStatus(invoice.status), state: ProviderState.invoice(invoice.status))
                }
                Text([ClientsText.shortDay(invoice.issuedAt ?? invoice.createdAt), invoice.petName].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Money.format(invoice.totalAmount, currency: invoice.currency)).font(.brandHeading(15.2)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                if pending && invoice.balanceDueAmount != invoice.totalAmount {
                    Text(LF("%@ to pay", Money.format(invoice.balanceDueAmount, currency: invoice.currency))).font(Theme.text(12)).monospacedDigit().foregroundStyle(Theme.inkSoft)
                }
            }
            Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Home & contact

/// A client's home on their page (web `ClientHomeSection`): the addresses home
/// visits go to (the family's, read-only and tagged, and the business's own),
/// which access details each has, and the emergency contacts.
struct ClientsHomeSection: View {
    @ObservedObject var page: ClientsClientPage
    @Environment(\.openURL) private var openURL

    @State private var editing: ClientsAddressEdit?
    @State private var removing: ClientsAddress?
    @State private var editingContact = false
    @State private var revealing: ClientsVaultRevealTarget?
    @State private var writingVault: ClientsVaultRevealTarget?
    /// Opened access details, by address: on screen only, never kept.
    @State private var revealed: [String: ClientsRevealedVault] = [:]

    var body: some View {
        let home = page.home
        let addresses = (home?.addresses ?? []).filter { $0.status != "archived" }.sorted { ($0.isDefault == true ? 0 : 1, $0.name) < ($1.isDefault == true ? 0 : 1, $1.name) }
        let canEdit = home?.canEdit ?? false
        SectionCard(title: L("Home & contact"), subtitle: L("Where home visits go, how to get in, and who to call."), icon: "map-pin", accent: Theme.aqua) {
            if canEdit && !addresses.isEmpty && addresses.filter(\.isBusiness).count < 20 {
                PMButton(L("Add address"), systemImage: "plus", variant: .outline, size: .compact) { editing = ClientsAddressEdit(address: nil, first: false) }
            }
        } content: {
            if page.homeFailed && home == nil {
                HStack(spacing: 12) {
                    Text(L("Couldn’t load the addresses.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    Spacer(minLength: 8)
                    PMButton(L("Try again"), variant: .outline, size: .compact) { Task { await reload() } }
                }
                .padding(16)
            } else if let home {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 12) {
                            if addresses.isEmpty {
                                ClientsHomeTile(icon: "map-pin", tone: Theme.lime, empty: true) {
                                    if canEdit { PMButton(L("Add"), systemImage: "plus", variant: .outline, size: .compact) { editing = ClientsAddressEdit(address: nil, first: true) } }
                                } content: {
                                    ClientsTileLabel(text: L("Address"))
                                    Text(L("No address yet")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                                    if home.linked == true {
                                        Text(L("Add one here, or the family can add theirs in PawMiaw — it shows here as soon as they do.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                                    }
                                }
                            }
                            ForEach(addresses) { address in addressTile(address, home: home, canEdit: canEdit) }
                            if home.linked == true && addresses.contains(where: { $0.source == "family" }) {
                                Text(L("Addresses from the family are theirs: they change them in PawMiaw, and this page follows.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                            }
                        }
                        emergencyTile(home, canEdit: canEdit)
                    }
                }
                .padding(16)
                // Only where there is something to open; "the family can see who" only when the family is on PawMiaw.
                if home.canManageVault == true && addresses.contains(where: { $0.vault?.hasVault == true }) {
                    RowDivider()
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Glyph("shield-check", size: 14).foregroundStyle(Theme.blue)
                        Text(home.linked == true ? L("Opening these is recorded and the family is told each time.") : L("Opening these is recorded."))
                    }
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
            } else {
                LoadingState()
            }
        }
        .sheet(item: $editing) { edit in
            ClientsAddressSheet(clientId: page.clientId, address: edit.address, makeDefault: edit.first) { await reload() }
        }
        .sheet(item: $removing) { address in
            ClientsRemoveAddressSheet(address: address) {
                let result: ClientsArchivedAddress = try await API.delete("/provider-clients/\(page.clientId)/addresses/\(address.id)")
                revealed[address.id] = nil
                Toast.show("\(L("Address removed.")) \(ClientsAddressWords.upcoming(result.upcomingVisits ?? 0))")
                await reload()
            }
        }
        .sheet(isPresented: $editingContact) {
            ClientsEmergencySheet(clientId: page.clientId, contact: home?.emergencyContact) { await reload() }
        }
        .sheet(item: $revealing) { target in
            ClientsVaultRevealSheet(clientId: page.clientId, address: target.address) { vault in revealed[target.address.id] = vault }
        }
        .sheet(item: $writingVault) { target in
            ClientsVaultEditorSheet(clientId: page.clientId, address: target.address) {
                revealed[target.address.id] = nil
                await reload()
            }
        }
    }

    private func reload() async {
        if let answer: ClientsHome = try? await API.get("/provider-clients/\(page.clientId)/home") {
            page.home = answer
            page.homeFailed = false
        }
    }

    /// One address (web: the address tile): its name with Default / From the
    /// family, the full line, the reference, Maps, the ⋯ for the business's
    /// own; under a dashed rule, which access details it has.
    private func addressTile(_ address: ClientsAddress, home: ClientsHome, canEdit: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    FlowLayout(spacing: 8) {
                        HStack(spacing: 6) {
                            Glyph("map-pin", size: 16).foregroundStyle(Theme.blue)
                            Text(address.label?.nonEmpty ?? L("Address")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        }
                        if address.isDefault == true { Chip(text: L("Default"), tone: .good, icon: "star") }
                        if address.source == "family" { Chip(text: L("From the family"), tone: .online, icon: "heart-handshake") }
                    }
                    Text(address.formatted ?? address.line1 ?? "—").font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    if let reference = address.reference?.nonEmpty { Text(reference).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                    if let maps = address.mapsUrl.flatMap(URL.init(string:)) {
                        Button { openURL(maps) } label: {
                            HStack(spacing: 4) {
                                Glyph("navigation", size: 14)
                                Text(L("Open in Maps"))
                            }
                            .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                Spacer(minLength: 8)
                if canEdit && address.isBusiness {
                    Menu {
                        Button { editing = ClientsAddressEdit(address: address, first: false) } label: { GlyphLabel(L("Edit address"), icon: "pencil") }
                        if address.isDefault != true {
                            Button { makeDefault(address) } label: { GlyphLabel(L("Make default"), icon: "star") }
                        }
                        Divider()
                        Button(role: .destructive) { removing = address } label: { GlyphLabel(L("Remove address"), icon: "archive") }
                    } label: {
                        IconCircleButton(systemImage: "ellipsis", label: LF("More for %@", address.name)) {}
                            .allowsHitTesting(false)
                    }
                    .accessibilityLabel(LF("More for %@", address.name))
                }
            }
            StitchedDivider()
            ClientsVaultStrip(
                clientId: page.clientId, address: address, home: home, revealed: revealed[address.id],
                onReveal: { revealing = ClientsVaultRevealTarget(address: address) },
                onEdit: { writingVault = ClientsVaultRevealTarget(address: address) },
                onHide: { revealed[address.id] = nil }
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    /// Who to call (web: the emergency tile): the business's contact, and the family's under a dashed rule.
    @ViewBuilder
    private func emergencyTile(_ home: ClientsHome, canEdit: Bool) -> some View {
        let has = home.emergencyContact.map { !$0.isEmpty } ?? false
        let familyHas = home.linked == true && (home.familyEmergencyContact.map { !$0.isEmpty } ?? false)
        if home.linked == true {
            ClientsHomeTile(icon: "phone-call", tone: Theme.blue, empty: !has && !familyHas) {
                emergencyAction(has: has, canEdit: canEdit)
            } content: {
                contactView(L("Emergency contact"), home.emergencyContact, empty: L("None yet"), family: false)
            } below: {
                contactView(L("The family’s emergency contact"), home.familyEmergencyContact, empty: L("The family hasn’t added one"), family: true)
            }
        } else {
            ClientsHomeTile(icon: "phone-call", tone: Theme.blue, empty: !has) {
                emergencyAction(has: has, canEdit: canEdit)
            } content: {
                contactView(L("Emergency contact"), home.emergencyContact, empty: L("None yet"), family: false)
            }
        }
    }

    @ViewBuilder
    private func emergencyAction(has: Bool, canEdit: Bool) -> some View {
        if canEdit { PMButton(has ? L("Edit") : L("Add"), systemImage: has ? "pencil" : "plus", variant: .outline, size: .compact) { editingContact = true } }
    }

    @ViewBuilder
    private func contactView(_ title: String, _ contact: ClientsEmergencyContact?, empty: String, family: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ClientsTileLabel(text: title)
                if family { Chip(text: L("From the family"), tone: .online, icon: "heart-handshake") }
            }
            if let contact, !contact.isEmpty {
                FlowLayout(spacing: 8) {
                    if let name = contact.name?.nonEmpty { Text(name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong) }
                    if let relation = contact.relationship?.nonEmpty { Text("· \(relation)").font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                    if let phone = contact.phone?.nonEmpty, let tel = ContactLinks.phone(phone) {
                        PMButton(phone, systemImage: "phone", variant: .outline, size: .compact) { openURL(tel) }
                    }
                }
            } else {
                Text(empty).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func makeDefault(_ address: ClientsAddress) {
        Task {
            do {
                let _: ClientsAddress = try await API.patch("/provider-clients/\(page.clientId)/addresses/\(address.id)", body: ClientsAddressWords.body(address, isDefault: true))
                Toast.show(LF("%@ is the default address now.", address.name))
                await reload()
            } catch {
                Toast.error(error)
            }
        }
    }
}

/// One half of the home card (web `HomeTile`): a 36 disc of its colour at 30%,
/// what it holds, its one action top right; dashed while it is empty; an
/// optional part under a dashed rule.
private struct ClientsHomeTile<Action: View, Content: View, Below: View>: View {
    let icon: String
    let tone: Color
    var empty: Bool = false
    @ViewBuilder var action: () -> Action
    @ViewBuilder var content: () -> Content
    @ViewBuilder var below: () -> Below

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(icon: icon, accent: tone, size: 36, iconSize: 16, ink: .strong, washPercent: 30)
                VStack(alignment: .leading, spacing: 4) { content() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                action()
            }
            if Below.self != EmptyView.self {
                VStack(alignment: .leading, spacing: 0) {
                    StitchedDivider().padding(.bottom, 12)
                    below().padding(.leading, 48)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous)
                .strokeBorder(empty ? AnyShapeStyle(Theme.mix(Theme.blue, 30, with: Theme.borderSoft)) : AnyShapeStyle(Theme.borderSoft),
                              style: StrokeStyle(lineWidth: 1, dash: empty ? [5, 4] : []))
        }
    }
}

extension ClientsHomeTile where Below == EmptyView {
    init(icon: String, tone: Color, empty: Bool = false, @ViewBuilder action: @escaping () -> Action, @ViewBuilder content: @escaping () -> Content) {
        self.init(icon: icon, tone: tone, empty: empty, action: action, content: content, below: { EmptyView() })
    }
}

/// A tile's uppercase label (web `TILE_LABEL`): 10.6 extrabold, tracked, grey.
private struct ClientsTileLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.brandText(10.6, weight: .heavy)).tracking(1.06).foregroundStyle(Theme.inkSoft)
    }
}

struct ClientsAddressEdit: Identifiable {
    let id = UUID()
    let address: ClientsAddress?
    let first: Bool
}

struct ClientsArchivedAddress: Decodable {
    let upcomingVisits: Int?
}

enum ClientsAddressWords {
    static func vaultField(_ field: String) -> String {
        switch field {
        case "keys": L("Keys")
        case "gateCode": L("Gate code")
        case "alarmCode": L("Alarm code")
        case "wifiName": L("Wi-Fi network")
        case "wifiPassword": L("Wi-Fi password")
        case "parking": L("Parking")
        case "houseRules": L("House rules")
        case "hidingSpots": L("Where the pets hide")
        default: L("Anything else")
        }
    }

    static func upcoming(_ count: Int) -> String {
        if count <= 0 { return L("No upcoming visits are booked there.") }
        return count == 1 ? L("1 upcoming visit is booked there. It keeps the address as it was booked.") : LF("%d upcoming visits are booked there. They keep the address as they were booked.", count)
    }

    static func body(_ address: ClientsAddress, isDefault: Bool) -> [String: Any?] {
        [
            "label": address.label, "line1": address.line1 ?? "", "line2": address.line2, "city": address.city, "state": address.state,
            "postalCode": address.postalCode, "country": address.country, "reference": address.reference,
            "latitude": address.latitude, "longitude": address.longitude, "isDefault": isDefault,
        ]
    }
}

/// The business's own address for a client (the family's come from PawMiaw).
struct ClientsAddressSheet: View {
    let clientId: String
    let address: ClientsAddress?
    let makeDefault: Bool
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var label: String
    @State private var line1: String
    @State private var line2: String
    @State private var city: String
    @State private var state: String
    @State private var postalCode: String
    @State private var country: String
    @State private var reference: String
    @State private var isDefault: Bool
    @State private var saving = false

    init(clientId: String, address: ClientsAddress?, makeDefault: Bool, onSaved: @escaping () async -> Void) {
        self.clientId = clientId
        self.address = address
        self.makeDefault = makeDefault
        self.onSaved = onSaved
        _label = State(initialValue: address?.label ?? "")
        _line1 = State(initialValue: address?.line1 ?? "")
        _line2 = State(initialValue: address?.line2 ?? "")
        _city = State(initialValue: address?.city ?? "")
        _state = State(initialValue: address?.state ?? "")
        _postalCode = State(initialValue: address?.postalCode ?? "")
        _country = State(initialValue: address?.country ?? (Workspace.shared.current?.country ?? "MX"))
        _reference = State(initialValue: address?.reference ?? "")
        _isDefault = State(initialValue: address?.isDefault ?? makeDefault)
    }

    private var dirty: Bool {
        label != (address?.label ?? "") || line1 != (address?.line1 ?? "") || line2 != (address?.line2 ?? "") || city != (address?.city ?? "")
            || state != (address?.state ?? "") || postalCode != (address?.postalCode ?? "") || reference != (address?.reference ?? "")
    }

    var body: some View {
        ProviderModal(title: address == nil ? L("Add address") : L("Edit address"), subtitle: L("The business’s own address for this client. The family’s come from PawMiaw."), systemImage: "map-pin", accent: .aqua, isDirty: dirty, form: form, primaryTitle: address == nil ? L("Add address") : L("Save address"), isWorking: saving, primaryIcon: "save") {
            save()
        } content: {
            ModalSection(title: L("Address"), systemImage: "map-pin") {
                PMTextField(L("Name"), text: $label, key: "label", form: form, prompt: L("Home, Office, Grandma’s…"), capitalization: .words)
                PMTextField(L("Street and number"), text: $line1, key: "line1", form: form, prompt: L("Av. Juárez 120"), capitalization: .words, required: true)
                PMTextField(L("Apartment, neighbourhood"), text: $line2, key: "line2", form: form, prompt: L("Int. 4, Col. Centro"), capitalization: .words)
                HStack(alignment: .top, spacing: 10) {
                    PMTextField(L("City"), text: $city, key: "city", form: form, capitalization: .words)
                    PMTextField(L("State"), text: $state, key: "state", form: form, capitalization: .words)
                }
                HStack(alignment: .top, spacing: 10) {
                    PMTextField(L("Postal code"), text: $postalCode, key: "postalCode", form: form, keyboard: .numbersAndPunctuation)
                    PMTextField(L("Country"), text: $country, key: "country", form: form, prompt: "MX", capitalization: .characters)
                }
                PMTextField(L("How to recognise it"), text: $reference, key: "reference", form: form, prompt: L("Green gate next to the pharmacy, ring twice"), multiline: true)
            }
            // The default one stays the default until another is made it.
            ToggleRow(title: L("Default address"), subtitle: L("Home visits start from it."), isOn: $isDefault)
                .disabled(address?.isDefault == true)
            // Not ported yet: placing the spot (a maps link or the current location); an edited address keeps its spot.
        }
    }

    private func save() {
        let code = country.trimmingCharacters(in: .whitespaces)
        guard form.check([
            ("line1", line1.nonEmpty == nil ? L("Add the street and number.") : nil),
            ("country", !code.isEmpty && code.count != 2 ? L("Use the two-letter country code (MX, US…).") : nil),
        ]) else { return }
        saving = true
        Task {
            defer { saving = false }
            let body: [String: Any?] = [
                "label": label.nonEmpty, "line1": line1.trimmingCharacters(in: .whitespaces), "line2": line2.nonEmpty,
                "city": city.nonEmpty, "state": state.nonEmpty, "postalCode": postalCode.nonEmpty, "country": code.nonEmpty?.uppercased(),
                "reference": reference.nonEmpty, "latitude": address?.latitude, "longitude": address?.longitude, "isDefault": isDefault,
            ]
            do {
                if let address {
                    let _: ClientsAddress = try await API.patch("/provider-clients/\(clientId)/addresses/\(address.id)", body: body)
                    Toast.show(L("Address saved."))
                } else {
                    let _: ClientsAddress = try await API.post("/provider-clients/\(clientId)/addresses", body: body)
                    Toast.show(L("Address added."))
                }
                await onSaved()
                dismiss()
            } catch {
                form.apply(error, known: ["label": "label", "line1": "line1", "line2": "line2", "city": "city", "state": "state", "postalCode": "postalCode", "country": "country", "reference": "reference"])
            }
        }
    }
}

/// Who to call if something happens and the client can't be reached.
struct ClientsEmergencySheet: View {
    let clientId: String
    let contact: ClientsEmergencyContact?
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var name: String
    @State private var phone: String
    @State private var relationship: String
    @State private var saving = false

    init(clientId: String, contact: ClientsEmergencyContact?, onSaved: @escaping () async -> Void) {
        self.clientId = clientId
        self.contact = contact
        self.onSaved = onSaved
        _name = State(initialValue: contact?.name ?? "")
        _phone = State(initialValue: contact?.phone ?? "")
        _relationship = State(initialValue: contact?.relationship ?? "")
    }

    var body: some View {
        ProviderModal(
            title: L("Emergency contact"), subtitle: L("Who to call if something happens and the client can’t be reached."), systemImage: "phone-call", accent: .aqua,
            isDirty: name != (contact?.name ?? "") || phone != (contact?.phone ?? "") || relationship != (contact?.relationship ?? ""),
            form: form, primaryTitle: L("Save"), isWorking: saving,
            // Web: "Quitar" in the footer once there is one to remove.
            secondaryActions: !(contact?.isEmpty ?? true) ? [ModalAction(L("Remove"), variant: .ghost, tint: Theme.destructive) { remove() }] : [],
            primaryIcon: "save"
        ) {
            save()
        } content: {
            PMTextField(L("Name"), text: $name, key: "name", form: form, capitalization: .words)
            PMTextField(L("Phone"), text: $phone, key: "phone", form: form, keyboard: .phonePad)
            PMTextField(L("Relationship"), text: $relationship, key: "relationship", form: form, prompt: L("Sister, neighbour, friend…"))
        }
    }

    private func remove() {
        name = ""
        phone = ""
        relationship = ""
        form.errors = [:]
        save()
    }

    private func save() {
        let hadOne = !(contact?.isEmpty ?? true)
        guard form.check([
            ("name", !hadOne && name.nonEmpty == nil && phone.nonEmpty == nil ? L("Write who to call: a name or a phone.") : nil),
            ("phone", ClientsText.phoneLooksValid(phone) ? nil : L("That phone number doesn’t look complete.")),
        ]) else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let _: EmptyResponse = try await API.put("/provider-clients/\(clientId)/emergency-contact", body: ["name": name.nonEmpty, "phone": phone.nonEmpty, "relationship": relationship.nonEmpty])
                Toast.show(name.nonEmpty != nil || phone.nonEmpty != nil ? L("Emergency contact saved.") : L("Emergency contact removed."))
                await onSaved()
                dismiss()
            } catch {
                form.apply(error, known: ["name": "name", "phone": "phone", "relationship": "relationship"])
            }
        }
    }
}

/// "¿Quitar esta dirección?" (web: the coral sheet with the address under the title): it leaves the
/// list, its access details are erased, visits booked there keep it.
private struct ClientsRemoveAddressSheet: View {
    let address: ClientsAddress
    let remove: () async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        ProviderModal(title: L("Remove this address?"), subtitle: address.formatted ?? address.name, systemImage: "archive", accent: .coral, primaryTitle: L("Remove address"), primaryVariant: .destructive, isWorking: working, cancelTitle: L("Keep it"), primaryIcon: "archive") {
            working = true
            Task {
                defer { working = false }
                do {
                    try await remove()
                    dismiss()
                } catch {
                    Toast.error(error)
                }
            }
        } content: {
            Text(L("It leaves the list and can’t be chosen for new visits. Its access details are erased. Visits already booked there keep the address they were booked with."))
                .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
        }
        .presentationDetents([.medium, .large])
    }
}
