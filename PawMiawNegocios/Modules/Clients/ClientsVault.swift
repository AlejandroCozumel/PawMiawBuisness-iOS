//
//  ClientsVault.swift
//  PawMiawNegocios
//
//  An address's access details (web: addresses/vault-sheets.tsx and the
//  vault strip of client-home-section.tsx; PawMiawIos docs/client-
//  addresses.md). Only owners and admins write the business's and open them
//  outside a visit: the business's any time, a family's only as an emergency
//  with a reason the family is shown. Every opening is recorded; what opens
//  stays on screen five minutes at most, one field at a time for a minute.
//

import SwiftUI

enum ClientsVaultWords {
    static let fields = ["keys", "gateCode", "alarmCode", "wifiName", "wifiPassword", "parking", "houseRules", "hidingSpots", "notes"]
    /// Single-line, monospaced and copyable.
    static let codes: Set<String> = ["gateCode", "alarmCode", "wifiName", "wifiPassword"]
    static let revealSeconds: TimeInterval = 5 * 60
    static let fieldSeconds = 60

    static func placeholder(_ field: String) -> String {
        switch field {
        case "keys": L("Where the keys are, a lockbox and its code, who has a copy")
        case "gateCode": L("The building or gate code")
        case "alarmCode": L("The code, and how to arm it")
        case "wifiName": L("The network’s name")
        case "wifiPassword": L("For sending photos and reports")
        case "parking": L("Where to park, a visitor spot, the tower")
        case "houseRules": L("Shoes off, rooms that stay closed, the neighbours")
        case "hidingSpots": L("Under the bed, behind the washing machine…")
        default: L("Whatever helps someone get in and find everything")
        }
    }

    /// A refusal from the address routes, in the reader's words.
    static func error(_ error: Error) -> String {
        guard let api = error as? APIError else { return L("Something went wrong. Try again.") }
        switch api.code {
        case "vault_owner_only": return L("Only the owners and admins open access details outside a visit. The person assigned sees them from the visit.")
        case "vault_family_off": return L("The family hasn’t shared its access details with your business.")
        case "vault_emergency_reason": return L("Outside a visit, say what happened before opening them. The family is shown it.")
        case "vault_empty": return L("No access details were written for this address.")
        case "vault_unavailable": return L("Access details aren’t available right now. Try again later.")
        case "vault_unreadable": return L("The access details couldn’t be read. Ask for them to be written again.")
        case "vault_impersonation": return L("Support sessions can’t open access details.")
        case "address_family_owned": return L("The family keeps this address; they change it in PawMiaw.")
        case "address_archived": return L("That address was removed. Choose another one.")
        case "address_not_found": return L("That address isn’t there anymore. Choose another one.")
        case "client_not_found": return L("That client isn’t here anymore.")
        case "forbidden": return L("You don’t have permission to do that.")
        default:
            if api.status == 403 { return L("You don’t have permission to do that.") }
            return api.message.nonEmpty ?? L("Something went wrong. Try again.")
        }
    }
}

/// What an opening returns: the filled fields, and when it opened.
struct ClientsRevealedVault: Hashable {
    let values: [String: String]
    let revealedAt: Date
}

private struct ClientsRevealAnswer: Decodable {
    let vault: [String: String?]?
    let revealedAt: String?
}

enum ClientsVaultAPI {
    static func reveal(clientId: String, addressId: String, emergencyReason: String?) async throws -> ClientsRevealedVault {
        var body: [String: Any?] = [:]
        if let emergencyReason { body["emergencyReason"] = emergencyReason }
        let answer: ClientsRevealAnswer = try await API.post("/provider-clients/\(clientId)/addresses/\(addressId)/access/reveal", body: body)
        var values: [String: String] = [:]
        for (key, value) in answer.vault ?? [:] { if let value = value?.nonEmpty { values[key] = value } }
        return ClientsRevealedVault(values: values, revealedAt: DateText.parse(answer.revealedAt) ?? Date())
    }
}

// MARK: - The strip under an address

struct ClientsVaultStrip: View {
    let clientId: String
    let address: ClientsAddress
    let home: ClientsHome
    let revealed: ClientsRevealedVault?
    let onReveal: () -> Void
    let onEdit: () -> Void
    let onHide: () -> Void

    var body: some View {
        let fields = ClientsVaultWords.fields.filter { (address.vault?.fields ?? []).contains($0) }
        let hasVault = address.vault?.hasVault == true || !fields.isEmpty
        let family = address.source == "family"
        let canManage = home.canManageVault == true
        VStack(alignment: .leading, spacing: 8) {
            if fields.isEmpty {
                Text(address.isBusiness ? L("No access details yet") : L("The family hasn’t written access details")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            } else {
                FlowLayout(spacing: 6) { ForEach(fields, id: \.self) { Chip(text: ClientsAddressWords.vaultField($0), tone: .muted, icon: "lock") } }
                    .accessibilityLabel(L("Access details written"))
            }
            if canManage && (address.isBusiness || hasVault) && revealed == nil {
                FlowLayout(spacing: 8) {
                    if address.isBusiness {
                        PMButton(hasVault ? L("Edit access details") : L("Add access details"), systemImage: "key-round", variant: .outline, size: .compact, action: onEdit)
                    }
                    if hasVault && (address.isBusiness || home.familyVaultShared == true) {
                        if family {
                            PMButton(L("Emergency opening"), systemImage: "triangle-alert", variant: .destructive, size: .compact, action: onReveal)
                        } else {
                            PMButton(L("Show access details"), systemImage: "eye", variant: .outline, size: .compact, action: onReveal)
                        }
                    }
                }
            }
            if family && hasVault {
                Text(home.familyVaultShared == false ? L("The family hasn’t shared its access details with your business.") : L("Whoever does a home visit sees them from the visit, 30 minutes before it starts."))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
            if let revealed {
                ClientsRevealedVaultView(vault: revealed, family: family, linked: home.linked == true, onHide: onHide)
            }
        }
    }
}

/// The opened details: each value hidden until its eye is pressed, for a minute; all of it hides after five.
struct ClientsRevealedVaultView: View {
    let vault: ClientsRevealedVault
    let family: Bool
    let linked: Bool
    let onHide: () -> Void

    @State private var shownField: String?
    @State private var shownAt = Date()
    @State private var copied: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let hideAt = vault.revealedAt.addingTimeInterval(ClientsVaultWords.revealSeconds)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    HStack(spacing: 6) {
                        Glyph("key-round", size: 16).foregroundStyle(Theme.blue)
                        Text(L("Access details")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    }
                    .frame(minHeight: 36)
                    Spacer()
                    PMButton(L("Hide"), systemImage: "eye-off", size: .header, action: onHide)
                }
                let filled = ClientsVaultWords.fields.filter { vault.values[$0] != nil }
                if filled.isEmpty {
                    Text(L("No access details were written for this address.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                ForEach(filled, id: \.self) { field in row(field, now: now) }
                let minutes = max(1, Int(ceil(hideAt.timeIntervalSince(now) / 60)))
                Text(LF("Hides by itself in %1$d min (at %2$@).", minutes, DateText.time(hideAt))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                Text(family && linked ? L("Opening these is recorded and the family is told each time.") : L("Opening these is recorded.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
            .padding(12)
            .background(Theme.wash(Theme.blue, 6), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.blue, 45, with: Theme.borderSoft), lineWidth: 2))
            .onChange(of: now >= hideAt) { _, over in if over { onHide() } }
        }
    }

    private func row(_ field: String, now: Date) -> some View {
        let value = vault.values[field] ?? ""
        let left = ClientsVaultWords.fieldSeconds - Int(now.timeIntervalSince(shownAt))
        let visible = shownField == field && left > 0
        let label = ClientsAddressWords.vaultField(field)
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
            HStack(alignment: .top, spacing: 8) {
                if visible {
                    Text(value).font(ClientsVaultWords.codes.contains(field) ? .system(size: 15, design: .monospaced) : Theme.text(15)).foregroundStyle(Theme.inkStrong).textSelection(.enabled)
                } else {
                    Text("••••").font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.inkSoft).accessibilityLabel(L("Hidden"))
                }
                Spacer(minLength: 6)
                if visible && ClientsVaultWords.codes.contains(field) {
                    Button(copied == field ? L("Copied") : L("Copy")) {
                        UIPasteboard.general.string = value
                        copied = field
                        Task { try? await Task.sleep(for: .milliseconds(1500)); if copied == field { copied = nil } }
                    }
                    .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue)
                    .buttonStyle(.plain)
                    .frame(minHeight: 36)
                    .accessibilityLabel(LF("Copy %@", label))
                }
                IconCircleButton(systemImage: visible ? "eye-off" : "eye", label: visible ? LF("Hide %@", label) : LF("Show %@", label)) {
                    if visible { shownField = nil } else { shownField = field; shownAt = Date() }
                }
            }
            if visible { Text(LF("Hides in %d s", left)).font(Theme.text(11)).foregroundStyle(Theme.inkSoft) }
        }
    }
}

// MARK: - Opening them

struct ClientsVaultRevealTarget: Identifiable {
    var id: String { address.id }
    let address: ClientsAddress
}

struct ClientsVaultRevealSheet: View {
    let clientId: String
    let address: ClientsAddress
    let onRevealed: (ClientsRevealedVault) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var reason = ""
    @State private var working = false

    private var emergency: Bool { address.source == "family" }

    var body: some View {
        ProviderModal(
            title: emergency ? L("Emergency opening") : L("Show access details?"),
            subtitle: address.name,
            systemImage: emergency ? "triangle-alert" : "key-round",
            accent: emergency ? .coral : .aqua,
            isDirty: !reason.isEmpty, form: form,
            primaryTitle: emergency ? L("Open in an emergency") : L("Show them"),
            primaryVariant: emergency ? .destructive : .primary,
            isWorking: working,
            primaryIcon: "eye"
        ) {
            open()
        } content: {
            if emergency {
                NoticeCard(tone: .problem, title: L("There is no visit now. Open them only if something is wrong, and say why: the family is told right away, with your words."), message: L("They stay on screen for 5 minutes at most, then hide again."))
                PMTextField(L("What happened?"), text: $reason, key: "reason", form: form, prompt: L("Luna isn’t answering and we are on our way"), multiline: true)
            } else {
                NoticeCard(tone: .info, title: L("Opening these is recorded."), message: L("They stay on screen for 5 minutes at most, then hide again."), icon: "shield-check")
            }
        }
        .presentationDetents(emergency ? [.medium, .large] : [.medium])
    }

    private func open() {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if emergency {
            guard form.check([("reason", trimmed.count < 10 ? L("Say what happened, in a sentence.") : nil)]) else { return }
        }
        working = true
        Task {
            defer { working = false }
            do {
                let vault = try await ClientsVaultAPI.reveal(clientId: clientId, addressId: address.id, emergencyReason: emergency ? trimmed : nil)
                onRevealed(vault)
                dismiss()
            } catch {
                if (error as? APIError)?.code == "vault_emergency_reason" {
                    _ = form.check([("reason", ClientsVaultWords.error(error))])
                } else {
                    Toast.error(ClientsVaultWords.error(error))
                }
            }
        }
    }
}

// MARK: - Writing them (the business's own addresses)

struct ClientsVaultEditorSheet: View {
    let clientId: String
    let address: ClientsAddress
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var values: [String: String] = [:]
    @State private var original: [String: String] = [:]
    @State private var needsOpening: Bool
    @State private var opening = false
    @State private var openProblem: String?
    @State private var saving = false

    init(clientId: String, address: ClientsAddress, onSaved: @escaping () async -> Void) {
        self.clientId = clientId
        self.address = address
        self.onSaved = onSaved
        let has = address.vault?.hasVault == true || !(address.vault?.fields ?? []).isEmpty
        _needsOpening = State(initialValue: has)
    }

    var body: some View {
        ProviderModal(
            title: L("Access details"), subtitle: address.name, systemImage: "lock-keyhole", accent: .aqua,
            isDirty: values != original, form: form,
            primaryTitle: needsOpening ? L("Open them to edit") : L("Save access details"),
            isWorking: saving || opening,
            primaryIcon: needsOpening ? "eye" : "save"
        ) {
            if needsOpening { openFirst() } else { save() }
        } content: {
            NoticeCard(tone: .info, title: L("Only the person doing a home visit sees these, from 30 minutes before until it ends. Owners and admins can open them too."), message: L("They are stored encrypted, and every opening is recorded."), icon: "shield-check")
            if needsOpening {
                if let openProblem {
                    NoticeCard(tone: .problem, title: openProblem, actionTitle: L("Try again")) { openFirst() }
                } else {
                    NoticeCard(tone: .info, title: L("To change them, open them first."), message: L("Opening these is recorded."))
                }
            } else {
                ForEach(ClientsVaultWords.fields, id: \.self) { field in
                    PMTextField(
                        ClientsAddressWords.vaultField(field),
                        text: Binding(get: { values[field] ?? "" }, set: { values[field] = $0; form.clear(field) }),
                        key: field, form: form, prompt: ClientsVaultWords.placeholder(field),
                        capitalization: ClientsVaultWords.codes.contains(field) ? .never : .sentences,
                        multiline: !ClientsVaultWords.codes.contains(field)
                    )
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Editing what is written starts with an opening (recorded as the owner's or admin's).
    private func openFirst() {
        opening = true
        openProblem = nil
        Task {
            defer { opening = false }
            do {
                let vault = try await ClientsVaultAPI.reveal(clientId: clientId, addressId: address.id, emergencyReason: nil)
                values = vault.values
                original = vault.values
                needsOpening = false
            } catch {
                openProblem = ClientsVaultWords.error(error)
            }
        }
    }

    private func save() {
        guard form.check(ClientsVaultWords.fields.map { field in
            (field, (values[field] ?? "").count > 1000 ? LF("Up to %d characters.", 1000) : nil)
        }) else { return }
        saving = true
        Task {
            defer { saving = false }
            var body: [String: Any?] = [:]
            for field in ClientsVaultWords.fields { body[field] = values[field]?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
            do {
                let _: EmptyResponse = try await API.put("/provider-clients/\(clientId)/addresses/\(address.id)/access", body: body)
                Toast.show(L("Access details saved."))
                await onSaved()
                dismiss()
            } catch {
                if !form.apply(error, known: Dictionary(uniqueKeysWithValues: ClientsVaultWords.fields.map { ($0, $0) })) {
                    Toast.error(ClientsVaultWords.error(error))
                }
            }
        }
    }
}
