//
//  ClientsInviteSheets.swift
//  PawMiawNegocios
//
//  Inviting a client's family to PawMiaw (web: provider-client-household-
//  invite-sheet.tsx, invitations/bulk-invite-sheet.tsx). One client: the
//  email, the pets and how long the link lasts; sent by email, or the link
//  only, to share by WhatsApp ("Su enlace"). Many at once ("Invitar a
//  PawMiaw"): the clients never invited, 20 at a time, each its own
//  invitation; then who was sent and who was skipped and why.
//

import SwiftUI

struct ClientsInviteSheet: View {
    let client: ClientsClient

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var name: String
    @State private var email: String
    @State private var language: String
    @State private var days = 7
    @State private var message = ""
    @State private var selected: Set<String>
    @State private var invitations: [ClientsInvitation] = []
    @State private var loaded = false
    @State private var saving = false
    @State private var resending = false
    @State private var created: ClientsInvitation?
    @State private var reviewing: ClientsInvitation?
    @State private var readdressing: ClientsInvitation?

    init(client: ClientsClient) {
        self.client = client
        _name = State(initialValue: client.ownerName)
        _email = State(initialValue: client.ownerEmail ?? "")
        _language = State(initialValue: client.recipientLanguage ?? "")
        _selected = State(initialValue: Set(client.allPets.filter { $0.isActive && !$0.isLinked }.map(\.id)))
    }

    /// Active pets are offered; one already linked to a family's pet is shown but can't be chosen (unlink it first).
    private var activePets: [ClientsPet] { client.allPets.filter(\.isActive) }
    private var selectable: [ClientsPet] { activePets.filter { !$0.isLinked } }
    private var nothingToOffer: Bool { selectable.isEmpty }
    /// Still open: waiting on the family (not run out), or on the clinic's confirmation.
    private var open: ClientsInvitation? {
        invitations.first { $0.status == "awaiting_clinic" || ($0.status == "pending" && (DateText.parse($0.expiresAt).map { $0 > Date() } ?? false)) }
    }
    private var activePending: ClientsInvitation? { open?.status == "pending" ? open : nil }
    private var awaiting: ClientsInvitation? { open?.status == "awaiting_clinic" ? open : nil }
    /// Nothing to send: someone accepted and waits on the clinic, or no pet is left to offer.
    private var onlyClose: Bool { awaiting != nil || (activePending == nil && nothingToOffer) }

    var body: some View {
        if let created {
            ProviderModal(title: L("Invite customer to connect"), systemImage: "link-2", accent: .aqua, cancelTitle: L("Done")) {
                NoticeCard(tone: .success, title: created.emailStatus == "sent" || created.emailSentAt != nil ? L("Invite email sent and link copied.") : L("Invite link created and copied."), message: LF("Invitation for %@", created.recipientEmail ?? ""))
                if let url = created.url.flatMap(URL.init(string:)) {
                    Text(L("Send their link by WhatsApp or any app.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    ShareLink(item: url) { GlyphLabel(L("Their link"), icon: "share") }.buttonStyle(.pm(.primary, fullWidth: true))
                }
            }
        } else {
            editor
        }
    }

    private var editor: some View {
        ProviderModal(
            title: L("Invite customer to connect"),
            subtitle: L("Send a secure link so the customer can approve the household and pet match."),
            systemImage: "link-2",
            accent: .aqua,
            isDirty: !message.isEmpty || email != (client.ownerEmail ?? ""),
            form: form,
            primaryTitle: onlyClose ? nil : activePending != nil ? L("Resend invite") : L("Send email invite"),
            // The duplicate check runs first: nothing is sent before it answers.
            isWorking: saving || resending || !loaded,
            cancelTitle: onlyClose ? L("Close") : L("Cancel"),
            secondaryActions: footerActions,
            primaryIcon: "mail-plus",
            onPrimary: onlyClose ? nil : {
                if let activePending { resend(activePending) } else { create(sendEmail: true) }
            }
        ) {
            formContent
        }
        .task { await loadInvitations() }
        .sheet(item: $reviewing) { invitation in
            ClientsReviewAcceptanceSheet(invitation: invitation, canManage: true) { await loadInvitations(); announceDataChanged() }
        }
        .sheet(item: $readdressing) { invitation in
            ClientsReaddressSheet(invitation: invitation) { await loadInvitations(); announceDataChanged() }
        }
    }

    /// The web footer's other way: the link only (copied, to share by hand), or the open one's link.
    private var footerActions: [ModalAction] {
        if onlyClose { return [] }
        if let pending = activePending {
            return [ModalAction(L("Copy existing link"), icon: "copy", disabled: resending) { clientsCopy(pending.url, done: L("Existing invite link copied.")) }]
        }
        return [ModalAction(L("Copy link only"), icon: "copy", disabled: saving || !loaded) { create(sendEmail: false) }]
    }

    @ViewBuilder
    private var formContent: some View {
        // Whose invitation this is, as every create modal says it; the pets are chosen below.
        ContextPills(client: client.ownerName, linked: client.isLinked)
        if client.isLinked {
            clientsQuietNote(title: L("Already linked"), nothingToOffer ? L("Every pet of this client is already linked. To link a different pet, unlink one first, then invite again.") : L("This client’s family is already linked. Send another invitation only to add a pet to the same household."))
        }
        if let open {
            openNotice(open)
        }
        ModalSection(title: L("Recipient"), subtitle: L("Email locked on accept"), systemImage: "user-round") {
            PMTextField(L("Customer name"), text: $name, key: "recipientName", form: form, prompt: L("Customer name"), capitalization: .words, required: true)
            PMTextField(L("Customer email"), text: $email, key: "recipientEmail", form: form, prompt: "customer@example.com", keyboard: .emailAddress, required: true)
            MenuField(label: L("Expiration"), options: [3, 7, 14, 30].map { ($0, LF("%d days", $0)) }, selection: $days)
        }
        petSelector
        VStack(alignment: .leading, spacing: 8) {
            MenuField(label: L("Recipient email language"), options: [("", L("Automatic")), ("en", L("English")), ("es", L("Spanish"))], selection: $language)
            Text(L("For people without an account. Existing accounts keep their saved language.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
        PMTextField(L("Message"), text: $message, prompt: L("Optional note shown on the customer approval page."), multiline: true)
    }

    /// The open invitation (web: the blue-edged box): what to do with it instead of a second one.
    /// Its link is copied from the footer ("Copy existing link"), as on the web.
    private func openNotice(_ invitation: ClientsInvitation) -> some View {
        let awaitingClinic = invitation.status == "awaiting_clinic"
        return NoticeCard(
            tone: .custom(Theme.aqua),
            title: awaitingClinic ? L("Someone accepted the open invitation") : L("Active invite already exists"),
            icon: nil
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(awaitingClinic
                     ? LF("They used another account than %@. Confirm or decline it in Invitations before inviting again.", invitation.recipientEmail ?? "")
                     : LF("Sent to %@. It expires %@. Use the existing link or resend it instead of creating a duplicate.", invitation.recipientEmail ?? "", ClientsText.dayTime(invitation.expiresAt)))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                FlowLayout(spacing: 8) {
                    if awaitingClinic {
                        PMButton(L("Review it"), systemImage: "shield-check", size: .compact) { reviewing = invitation }
                    } else {
                        PMButton(L("Change its email"), systemImage: "at-sign", variant: .outline, size: .compact) { readdressing = invitation }
                        if let url = invitation.url.flatMap(URL.init(string:)) {
                            ShareLink(item: url) { GlyphLabel(L("Their link"), icon: "share") }.buttonStyle(.pm(.outline, size: .compact))
                        }
                    }
                }
            }
        }
    }

    /// "Mascotas a incluir" (web `ProviderClientPetSelector`): a card per active pet, a linked one shown but not choosable.
    private var petSelector: some View {
        let error = form.error("pets")
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                FieldLabel(L("Pets to include"), required: true)
                Text(L("Choose which provider-side pet profiles this customer should approve.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
            if activePets.isEmpty {
                Text(L("This client has no pets available for invitation."))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 16).padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(activePets) { pet in petCard(pet) }
                }
            }
            if let error { Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
        }
        .padding(error == nil ? 0 : 12)
        .overlay {
            if error != nil {
                RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.destructive.opacity(0.7), lineWidth: 1)
            }
        }
        .id("pets")
    }

    private func petCard(_ pet: ClientsPet) -> some View {
        let linked = pet.isLinked
        let active = !linked && selected.contains(pet.id)
        let kind = [ClientsText.species(pet.petSpecies).nonEmpty, pet.petBreed?.nonEmpty].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? L("Pet profile")
        let note = linked ? L("Already linked@pet") : pet.microchipNumber?.nonEmpty.map { LF("Microchip %@", $0) } ?? L("No microchip saved")
        return Button {
            if active { selected.remove(pet.id) } else { selected.insert(pet.id) }
            form.clear("pets")
        } label: {
            HStack(spacing: 12) {
                PetAvatar(name: pet.petName, species: pet.petSpecies, photoURL: pet.photoUrl, size: 48)
                    .overlay(Circle().strokeBorder(Theme.blue, lineWidth: 2))
                VStack(alignment: .leading, spacing: 1) {
                    Text(pet.petName).font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text(kind).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    Text(note).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 0)
                if linked {
                    Glyph("link-2", size: 20).foregroundStyle(Theme.blue)
                } else {
                    Tick(on: active)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(active ? AnyShapeStyle(Theme.wash(Theme.aqua, 18)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous)
                    .strokeBorder(active ? Theme.blue : Theme.borderSoft, style: StrokeStyle(lineWidth: 2, dash: linked ? [5, 4] : []))
            }
            .opacity(linked ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(linked)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func loadInvitations() async {
        if let page: Page<ClientsInvitation> = try? await API.get("/provider-client-invitations", query: ["limit": "10", "offset": "0", "providerClientId": client.id]) {
            invitations = page.items
        }
        loaded = true
    }

    private func create(sendEmail: Bool) {
        if nothingToOffer {
            Toast.show(L("Every active pet of this client is already linked."))
            return
        }
        if open != nil {
            Toast.show(L("This client already has an active invite."))
            return
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let chosen = selectable.map(\.id).filter { selected.contains($0) }
        guard form.check([
            ("recipientName", name.nonEmpty == nil ? L("Add the customer name.") : nil),
            ("recipientEmail", trimmedEmail.isEmpty ? L("Add the customer email.") : !ClientsText.emailLooksValid(trimmedEmail) ? L("Write a valid email.") : nil),
            ("pets", chosen.isEmpty ? L("Choose at least one pet to include.") : nil),
        ]) else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let invitation: ClientsInvitation = try await API.post("/provider-clients/\(client.id)/household-link-invitations", body: [
                    "recipientEmail": trimmedEmail,
                    "recipientLanguage": language.nonEmpty,
                    "recipientName": name.trimmingCharacters(in: .whitespaces),
                    "providerClientPetIds": chosen,
                    "expiresInDays": days,
                    "message": message.nonEmpty,
                    "sendEmail": sendEmail,
                ])
                if let url = invitation.url { UIPasteboard.general.string = url }
                Toast.show(sendEmail ? L("Invite email sent and link copied.") : L("Invite link created and copied."))
                announceDataChanged()
                created = invitation
            } catch {
                let code = (error as? APIError)?.code
                if code == "already_pending" {
                    // Someone sent one meanwhile: show it instead of a second invitation.
                    await loadInvitations()
                    Toast.error(L("This client already has an active invite."))
                } else if code == "pets_already_linked" {
                    _ = form.check([("pets", L("One of these pets is already linked to a family in PawMiaw. Leave it out, or unlink it first."))])
                } else {
                    form.apply(error, known: ["recipientEmail": "recipientEmail", "recipientName": "recipientName", "providerClientPetIds": "pets"])
                }
            }
        }
    }

    private func resend(_ invitation: ClientsInvitation) {
        resending = true
        Task {
            defer { resending = false }
            do {
                let _: ClientsInvitation = try await API.post("/provider-client-invitations/\(invitation.id)/resend")
                Toast.show(L("Existing invite email resent."))
                announceDataChanged()
            } catch {
                Toast.error(error, fallback: L("Could not resend the existing invitation."))
            }
        }
    }
}

// MARK: - "Invitar a PawMiaw" for many

struct ClientsBulkInviteSheet: View {
    /// One client's own invitation (its link to share): the sheet closes and that one opens.
    let onInviteOne: (ClientsClient) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @StateObject private var pager = Pager<ClientsClient> { _, _ in Page(items: [], total: 0) }
    @State private var query = ""
    @State private var chosen: [String: ClientsClient] = [:]
    @State private var sending = false
    @State private var result: (outcome: ClientsBulkResult, clients: [String: ClientsClient])?

    private static let limit = 100

    var body: some View {
        if let result {
            // The web's result footer: one "Done", no Cancel.
            ProviderModal(title: L("Invite to PawMiaw"), systemImage: "mail-plus", accent: .aqua, primaryTitle: L("Done"), primaryIcon: "check", showsCancel: false, onPrimary: { dismiss() }) {
                outcome(result.outcome, clients: result.clients)
            }
        } else {
            ProviderModal(
                title: L("Invite to PawMiaw"),
                subtitle: L("Each family gets its own invitation by email. Once they link, they see what you write and can book online with you."),
                systemImage: "mail-plus",
                accent: .aqua,
                isDirty: !chosen.isEmpty,
                form: form,
                primaryTitle: chosen.isEmpty ? L("Invite") : chosen.count == 1 ? L("Invite 1 client") : LF("Invite %d clients", chosen.count),
                isWorking: sending,
                primaryIcon: "send"
            ) {
                submit()
            } content: {
                picker
            }
            .debounced(query) { value in
                // The clients list's rule: the server searches from two letters.
                let q = ClientSearch.query(value)
                pager.fetch = { offset, limit in
                    try await API.get("/provider-clients", query: ["limit": "\(limit)", "offset": "\(offset)", "unlinked": "true", "invitation": "none", "sort": "name", "search": q])
                }
                await pager.reload()
            }
        }
    }

    @ViewBuilder
    private var picker: some View {
        let withEmail = pager.items.filter { $0.ownerEmail?.nonEmpty != nil }
        let allShown = !withEmail.isEmpty && withEmail.allSatisfy { chosen[$0.id] != nil }
        let error = form.error("list")
        SearchField(prompt: L("Name, email or phone"), text: $query, shape: .field)
        FlowLayout(spacing: 8) {
            Group {
                if let total = pager.total {
                    Text(total == 1 ? L("1 client not invited yet") : LF("%d clients not invited yet", total)).bold().foregroundColor(Theme.inkStrong)
                        + Text(chosen.isEmpty ? "" : " · \(chosen.count == 1 ? L("1 ticked") : LF("%d ticked", chosen.count))").foregroundColor(Theme.inkSoft)
                } else {
                    Text("—").bold().foregroundColor(Theme.inkStrong)
                }
            }
            .font(Theme.text(14))
            if !withEmail.isEmpty {
                PMButton(allShown ? (withEmail.count == 1 ? L("Untick the one shown") : LF("Untick the %d shown", withEmail.count)) : (withEmail.count == 1 ? L("Tick the one shown") : LF("Tick the %d shown", withEmail.count)), variant: .outline, size: .compact) {
                    form.clear("list")
                    if allShown { withEmail.forEach { chosen[$0.id] = nil } } else { withEmail.forEach { chosen[$0.id] = $0 } }
                }
            }
        }
        if let error { Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
        list(invalid: error != nil)
            .id("list")
        Text(LF("Up to %d at a time. Clients with no email are invited one by one: copy their link and send it by WhatsApp.", Self.limit)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
    }

    /// The clients never invited, in one bordered box, 20 at a time.
    private func list(invalid: Bool) -> some View {
        Group {
            if !pager.loadedOnce && pager.isLoading {
                LoadingState()
            } else if let error = pager.error, pager.items.isEmpty {
                ErrorState(message: error) { await pager.reload() }
            } else if pager.items.isEmpty {
                let searched = ClientSearch.query(query)
                EmptyState(systemImage: searched == nil ? "users-round" : "search", title: searched.map { LF("Nobody not invited matches “%@”", $0) } ?? L("Everyone has been invited"), message: searched == nil ? L("Clients whose family isn’t on PawMiaw and was never invited show here.") : nil, accent: Theme.aqua)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(pager.items.enumerated()), id: \.element.id) { index, client in
                        VStack(spacing: 0) {
                            if index > 0 { RowDivider() }
                            row(client, invalid: invalid)
                        }
                        .onAppear { pager.loadMoreIfNeeded(client) }
                    }
                    PagerFooter(pager: pager)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(invalid ? Theme.coral : Theme.borderSoft, lineWidth: 1))
    }

    private func row(_ client: ClientsClient, invalid: Bool) -> some View {
        let email = client.ownerEmail?.nonEmpty
        let on = chosen[client.id] != nil
        return HStack(spacing: 12) {
            Button {
                guard email != nil else { return }
                form.clear("list")
                chosen[client.id] = on ? nil : client
            } label: {
                HStack(spacing: 12) {
                    Tick(on: on, invalid: invalid).opacity(email == nil ? 0.5 : 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(client.ownerName).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Text([email ?? L("No email"), client.allPets.map(\.petName).joined(separator: ", ").nonEmpty].compactMap { $0 }.joined(separator: " · ")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(email == nil)
            .accessibilityAddTraits(on ? .isSelected : [])
            if email == nil {
                PMButton(L("Their link"), systemImage: "link-2", variant: .outline, size: .compact) {
                    dismiss()
                    onInviteOne(client)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(on ? AnyShapeStyle(Theme.wash(Theme.blue, 6)) : AnyShapeStyle(Theme.surface))
    }

    private func submit() {
        guard form.check([
            ("list", chosen.isEmpty ? L("Tick who to invite.") : chosen.count > Self.limit ? LF("Up to %d at a time: untick some.", Self.limit) : nil),
        ]) else { return }
        let picked = chosen
        sending = true
        Task {
            defer { sending = false }
            do {
                let outcome: ClientsBulkResult = try await API.post("/provider-client-invitations/bulk", body: ["clientIds": Array(picked.keys)])
                result = (outcome, picked)
                chosen = [:]
                if !outcome.sent.isEmpty { Toast.show(outcome.sent.count == 1 ? L("1 invitation sent.") : LF("%d invitations sent.", outcome.sent.count)) }
                announceDataChanged()
            } catch {
                Toast.error(error)
            }
        }
    }

    /// Who was sent and who was skipped, and why; a client with no email can still get their link.
    @ViewBuilder
    private func outcome(_ outcome: ClientsBulkResult, clients: [String: ClientsClient]) -> some View {
        let name = { (id: String) in clients[id]?.ownerName ?? L("A client") }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Glyph("send", size: 16).foregroundStyle(Theme.blue)
                Text(outcome.sent.count == 1 ? L("1 invitation sent") : LF("%d invitations sent", outcome.sent.count)).font(Theme.text(14, weight: .heavy)).foregroundStyle(Theme.inkStrong)
            }
            if outcome.sent.isEmpty {
                Text(L("None went out.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            } else {
                FlowLayout(spacing: 6) { ForEach(outcome.sent, id: \.clientId) { Chip(text: name($0.clientId), tone: .custom(Theme.blue), percent: 10, ink: Theme.inkStrong, weight: .semibold, size: .wide) } }
            }
        }
        if !outcome.skipped.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Glyph("circle-slash", size: 16).foregroundStyle(Theme.inkSoft)
                    Text(outcome.skipped.count == 1 ? L("1 not sent") : LF("%d not sent", outcome.skipped.count)).font(Theme.text(14, weight: .heavy)).foregroundStyle(Theme.inkStrong)
                }
                VStack(spacing: 0) {
                    ForEach(Array(outcome.skipped.enumerated()), id: \.element.clientId) { index, entry in
                        if index > 0 { RowDivider() }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(name(entry.clientId)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                Text(skipReason(entry.reason)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            if entry.reason == "no_email", let client = clients[entry.clientId] {
                                PMButton(L("Their link"), systemImage: "link-2", variant: .outline, size: .compact) {
                                    dismiss()
                                    onInviteOne(client)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            }
        }
    }

    private func skipReason(_ reason: String) -> String {
        switch reason {
        case "no_email": L("No email: send their link by WhatsApp")
        case "already_linked": L("Already on PawMiaw with you")
        case "pending_invitation": L("Already invited, waiting for them")
        case "archived": L("Archived client")
        default: reason
        }
    }
}
