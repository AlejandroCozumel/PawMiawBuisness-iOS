//
//  ConsentsCard.swift
//  PawMiawNegocios
//
//  The consents of an act — a visit, a stay or a home stay (web
//  consents/consents-card.tsx, consent-request-sheet.tsx, consent-sign-sheet.tsx,
//  consent-document.tsx, esign/send-for-signature-sheet.tsx,
//  esign/consent-evidence-sheet.tsx; backend docs/consents-incidents.md). One
//  set for every place that shows consents:
//  - `ConsentsCard`: what must be signed before it starts and whether it is,
//    every consent with where it stands, and its moves — ask for one, enter the
//    amount it names, sign it here, send it for signature, view and print it,
//    its e-signature evidence, withdraw and revoke. Buttons follow the list's
//    `canManage`; a role that can't read consents doesn't see the card.
//  - `ConsentSignSheet`: signing on this device with the client (the e-sign
//    terms, the text, "I have read and agree", the full name and a drawn or
//    typed signature). The hospital's estimate and euthanasia consent use it.
//  - The request, amount, view · print, send (the family's app, a link with an
//    emailed code and WhatsApp, or this device) and evidence sheets.
//  Used by the visit page and the start gate (Schedule), the stay, its check-in
//  and the home stay with its arrival gate (Stays), and the hospital (Hospital).
//

import SwiftUI
import UIKit

// MARK: - What the consents belong to

/// The act a consent belongs to: one of a visit, a stay, a record or a pet (the web's ConsentAct).
struct ConsentAct: Hashable {
    var appointmentId: String? = nil
    var stayId: String? = nil
    var recordId: String? = nil
    var providerClientPetId: String? = nil

    /// The one key the server reads, in its order.
    private var pair: (String, String)? {
        if let appointmentId { return ("appointmentId", appointmentId) }
        if let stayId { return ("stayId", stayId) }
        if let recordId { return ("recordId", recordId) }
        if let providerClientPetId { return ("providerClientPetId", providerClientPetId) }
        return nil
    }

    var isEmpty: Bool { pair == nil }
    var query: [String: String?] { pair.map { [$0.0: $0.1] } ?? [:] }
    var body: [String: Any?] { pair.map { [$0.0: $0.1] } ?? [:] }
    /// As multipart fields (an incident's).
    var fields: [(String, String)] { pair.map { [$0] } ?? [] }
}

/// A pet of a visit or stay as consents and incidents name it (its client-pet id).
struct ActPet: Hashable, Identifiable {
    let id: String
    let name: String
}

/// What the Consents card knows about the act it sits on.
struct ConsentContext {
    let act: ConsentAct
    var businessName: String? = nil
    let clientName: String
    /// The family is on PawMiaw, so a consent can be sent to their app.
    let familyOnApp: Bool
    var clientEmail: String? = nil
    var clientPhone: String? = nil
    var pets: [ActPet] = []
    /// "Boarding · 26 sep – 28 sep", printed on the consent.
    var actLabel: String? = nil
    /// The visit started or the stay checked in: a per-visit consent can't be revoked any more.
    var started = false
    var currency: String? = nil
}

// MARK: - Models (use-consents.ts, esign.ts)

struct ConsentEsignTerms: Codable, Hashable {
    let version: String?
    let language: String?
    let title: String?
    let text: String?
    let reviewNote: String?
}

/// How a document was signed: drawn, typed or uploaded.
struct ConsentSignatureMark: Codable, Hashable {
    let kind: String?
    let text: String?
    let font: String?
    let imageDataUrl: String?
}

struct ConsentIntegrity: Codable, Hashable {
    let snapshotSha256: String?
    let signatureSha256: String?
    let verified: Bool?
}

struct ConsentEvidenceSeal: Codable, Hashable { let status: String?; let sealedAt: String?; let sha256: String? }
struct ConsentEvidenceStamp: Codable, Hashable { let status: String?; let at: String? }

struct ConsentEvidenceSummary: Codable, Hashable {
    let requestId: String?
    let status: String?
    let verifyCode: String?
    let verifyUrl: String?
    let method: String?
    let signedAt: String?
    let seal: ConsentEvidenceSeal?
    let timestamp: ConsentEvidenceStamp?
    let revokedAt: String?
}

/// A consent on a visit, stay, record or pet; the detail adds the signature, the terms and the evidence.
struct Consent: Codable, Identifiable, Hashable {
    let id: String
    let templateId: String?
    let validity: String?
    let validDays: Int?
    let validUntil: String?
    let providerClientPetId: String?
    let petName: String?
    let origin: String?
    let status: String
    let language: String?
    let title: String
    let body: String?
    let needsAmount: Bool?
    let amountCents: Int?
    let currency: String?
    let requestedAt: String?
    let requestedByName: String?
    let sentAt: String?
    let signedAt: String?
    let signedVia: String?
    let signerName: String?
    let signerAccountName: String?
    let witnessName: String?
    let declinedAt: String?
    let declineReason: String?
    let cancelledAt: String?
    let cancelReason: String?
    let revokedAt: String?
    let revokedBySide: String?
    let revokeReason: String?
    let signatureDataUrl: String?
    let mark: ConsentSignatureMark?
    let terms: ConsentEsignTerms?
    let integrity: ConsentIntegrity?
    let evidence: ConsentEvidenceSummary?
    /// After asking or sending: the family was told.
    let notified: Bool?

    var amountText: String? { (amountCents ?? 0) > 0 ? Money.format(amountCents, currency: currency) : nil }
}

struct ConsentLine: Codable, Hashable {
    let templateId: String?
    let title: String?
    let validity: String?
    let satisfied: Bool?
    let consentId: String?
    let status: String?

    init(templateId: String? = nil, title: String?, validity: String? = nil, satisfied: Bool? = false, consentId: String? = nil, status: String? = nil) {
        self.templateId = templateId; self.title = title; self.validity = validity
        self.satisfied = satisfied; self.consentId = consentId; self.status = status
    }
}

struct ConsentRequirement: Codable, Hashable { let lines: [ConsentLine]?; let satisfied: Bool? }

struct ConsentList: Codable, Hashable {
    let items: [Consent]?
    let requirement: ConsentRequirement?
    let canManage: Bool?
    let canOverride: Bool?
}

struct ConsentTemplate: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let language: String?
    let validity: String?
    let validDays: Int?
    let needsAmount: Bool?
    let status: String?
}

struct ConsentEvidenceSigner: Codable, Identifiable, Hashable {
    let id: String
    let role: String?
    let status: String?
    let name: String?
    let maskedEmail: String?
    let method: String?
    let witnessName: String?
    let ip: String?
    let device: String?
    let termsVersion: String?
    let termsAcceptedAt: String?
    let emailVerifiedAt: String?
    let signedAt: String?
    let declinedAt: String?
    let declineReason: String?
    let mark: ConsentSignatureMark?
}

struct ConsentEvidenceEvent: Codable, Hashable {
    let sequence: Int?
    let type: String?
    let at: String?
    let actorType: String?
    let actorName: String?
    let ip: String?
    let hash: String?
}

struct ConsentSigningLink: Codable, Identifiable, Hashable {
    let id: String
    let maskedEmail: String?
    let phone: String?
    let createdAt: String?
    let expiresAt: String?
    let status: String?
    let openedAt: String?
    let verifiedAt: String?
    let createdByName: String?
}

struct ConsentEvidence: Codable {
    let summary: ConsentEvidenceSummary?
    let documentSha256: String?
    let finalEvidenceSha256: String?
    let termsVersion: String?
    let signers: [ConsentEvidenceSigner]?
    let events: [ConsentEvidenceEvent]?
    let links: [ConsentSigningLink]?
    let canSendLink: Bool?
}

struct ConsentVerifyResult: Codable {
    let ok: Bool?
    let checkedAt: String?
    let checks: [String: Bool?]?
    let errors: [String]?
}

struct ConsentCreatedLink: Codable {
    let link: ConsentSigningLink?
    let url: String?
    let whatsappUrl: String?
    let emailSent: Bool?
}

// MARK: - Words (consents-copy.ts)

enum ConsentWords {
    /// "26 sep 2026, 10:30" on the business's clock.
    static func date(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return "—" }
        let f = DateFormatter(); f.locale = .app; f.timeZone = Workspace.shared.timeZone
        f.setLocalizedDateFormatFromTemplate("dMMMyyyyjmm")
        return f.string(from: date)
    }

    static func status(_ status: String) -> String {
        switch status {
        case "draft": L("Needs an amount")
        case "pending": L("Waiting for signature")
        case "signed": L("Signed")
        case "declined": L("Declined")
        case "cancelled": L("Withdrawn")
        case "revoked": L("Revoked")
        default: status
        }
    }

    static func state(_ status: String) -> ProviderState {
        switch status {
        case "draft", "pending": .waiting
        case "signed": .done
        case "declined", "revoked": .problem
        default: .closed
        }
    }

    /// "Each visit or stay", "Once per pet · 365 days", "Once per pet · until revoked".
    static func validity(_ validity: String?, _ days: Int?) -> String {
        if validity != "standing" { return L("Each visit or stay") }
        guard let days, days > 0 else { return L("Once per pet · until revoked") }
        return days == 1 ? L("Once per pet · 1 day") : LF("Once per pet · %d days", days)
    }

    static func via(_ via: String?) -> String {
        switch via {
        case "family_app": L("Signed in the PawMiaw app")
        case "clinic_device": L("Signed at the business, on its device")
        case "email_link": L("Signed through a link, with a code sent by email")
        default: "—"
        }
    }

    private static func reasonSuffix(_ reason: String?) -> String {
        reason?.nonEmpty.map { " — \($0)" } ?? ""
    }

    private static func side(_ side: String?) -> String {
        side == "family" ? L("the family") : L("the business")
    }

    /// One line about where a consent stands: who asked, who signed and how, why it closed.
    static func line(_ consent: Consent) -> String {
        switch consent.status {
        case "draft":
            return L("Waiting for the amount before it can be signed.")
        case "pending":
            if consent.sentAt != nil { return LF("Sent %@", date(consent.sentAt)) }
            let by = consent.requestedByName?.nonEmpty.map { " · \($0)" } ?? (consent.origin == "auto" ? " · " + L("required by the service") : "")
            return LF("Asked %@%@", date(consent.requestedAt), by)
        case "signed":
            let name = consent.signerName?.nonEmpty ?? "—"
            switch consent.signedVia {
            case "clinic_device": return LF("Signed by %@ here · %@", name, date(consent.signedAt))
            case "email_link": return LF("Signed by %@ through a link · %@", name, date(consent.signedAt))
            default: return LF("Signed by %@ in the app · %@", name, date(consent.signedAt))
            }
        case "declined":
            return LF("Declined %@%@", date(consent.declinedAt), reasonSuffix(consent.declineReason))
        case "cancelled":
            return LF("Withdrawn %@%@", date(consent.cancelledAt), reasonSuffix(consent.cancelReason))
        case "revoked":
            return LF("Revoked by %@ %@%@", side(consent.revokedBySide), date(consent.revokedAt), reasonSuffix(consent.revokeReason))
        default:
            return ""
        }
    }

    /// The closing note printed on a consent that no longer counts.
    static func closedNote(_ consent: Consent) -> String? {
        switch consent.status {
        case "revoked": LF("Revoked on %@ by %@%@", date(consent.revokedAt), side(consent.revokedBySide), reasonSuffix(consent.revokeReason))
        case "declined": LF("Declined on %@%@", date(consent.declinedAt), reasonSuffix(consent.declineReason))
        case "cancelled": LF("Withdrawn on %@%@", date(consent.cancelledAt), reasonSuffix(consent.cancelReason))
        default: nil
        }
    }

    /// The server's refusals in words (CONSENT_ERROR_MESSAGES).
    static func error(_ error: Error, fallback: String = "Something went wrong. Try again.") -> String {
        if let api = error as? APIError {
            if api.isOffline { return api.message }
            if let code = api.code, let known = known(code) { return known }
            if api.status == 403 { return L("You don’t have permission to do this.") }
            if api.status == 404 { return L("It wasn’t found. It may have been removed.") }
            if !api.message.isEmpty, api.isRefusal || LocalizationManager.shared.currentLanguage != .spanish { return api.message }
        }
        return L(fallback)
    }

    private static func known(_ code: String) -> String? {
        switch code {
        case "amount_required": L("This consent names an amount — enter it.")
        case "pet_required": L("A consent for each pet — choose which one.")
        case "pet_not_in_act": L("That pet isn’t part of this visit or stay.")
        case "act_closed": L("This visit or stay is over — ask for the consent from the pet’s chart instead.")
        case "act_not_found": L("The visit or stay wasn’t found.")
        case "not_pending": L("This consent is no longer waiting for a signature. Reload to see it.")
        case "already_signed": L("This consent was already signed.")
        case "agreement_required": L("Tick that you read and agree.")
        case "signer_name_required": L("Type the full name of who signs.")
        case "signature_missing", "signature_blank": L("Draw the signature.")
        case "signature_invalid": L("The signature couldn’t be read. Clear it and draw it again.")
        case "signature_too_large": L("The signature image is too large. Clear it and draw it again.")
        case "act_started": L("It already started — a consent can only be revoked before the visit or stay begins.")
        case "not_signed": L("Only a signed consent can be revoked.")
        case "stale": L("Someone else changed this consent. Reload to see it.")
        case "template_missing": L("The template of this consent is gone — ask for a new one.")
        case "cannot_sign": L("An owner or a household admin signs consents.")
        case "forbidden": L("You don’t have permission to do this.")
        default: nil
        }
    }

    /// A refusal carrying these words (and the server's fields), for a ConfirmSheet or `FormState.apply`.
    static func refusal(_ error: Error, fallback: String) -> APIError {
        let api = error as? APIError
        return APIError(status: api?.status ?? 400, message: Self.error(error, fallback: fallback), code: api?.code, fields: api?.fields ?? [:], body: api?.body)
    }

    /// Waiting first (drafts, then pending), then signed, then the closed ones; newest first inside each.
    static func sorted(_ items: [Consent]) -> [Consent] {
        let order = ["draft": 0, "pending": 1, "signed": 2, "declined": 3, "revoked": 4, "cancelled": 5]
        return items.sorted { a, b in
            let left = order[a.status] ?? 9, right = order[b.status] ?? 9
            return left != right ? left < right : (a.requestedAt ?? "") > (b.requestedAt ?? "")
        }
    }
}

// MARK: - Words for the e-signature (esign-copy.ts)

enum ConsentEsignWords {
    static func method(_ method: String?) -> String {
        switch method {
        case "app_session": L("In the PawMiaw app, signed in")
        case "email_code": L("By link, with a code sent by email")
        case "in_person": L("In person, on the business’s device")
        default: method ?? "—"
        }
    }

    static func envelope(_ status: String?) -> String {
        switch status {
        case "pending": L("Waiting for signature")
        case "completed": L("Signed")
        case "declined": L("Declined")
        case "voided": L("Voided")
        case "expired": L("Expired")
        default: status ?? "—"
        }
    }

    static func seal(_ status: String?) -> String {
        switch status {
        case "pending": L("Sealing…")
        case "sealed": L("Sealed")
        case "failed": L("Sealing failed — it is retried")
        default: L("Not sealed yet")
        }
    }

    static func signer(_ status: String?) -> String {
        switch status {
        case "signed": L("Signed")
        case "declined": L("Declined")
        default: L("Waiting")
        }
    }

    static func link(_ status: String?) -> String {
        switch status {
        case "active": L("Active")
        case "used": L("Used")
        case "expired": L("Expired")
        case "revoked": L("Stopped")
        default: status ?? "—"
        }
    }

    static func event(_ type: String?) -> String {
        switch type {
        case "created": L("Signature request created")
        case "sent": L("Sent to the family’s app")
        case "link_created": L("Signing link made")
        case "link_revoked": L("Signing link stopped")
        case "opened": L("Link opened")
        case "code_sent": L("Code sent by email")
        case "code_failed": L("Wrong code entered")
        case "code_locked": L("Too many wrong codes: locked")
        case "code_verified": L("Email confirmed with the code")
        case "viewed": L("Document viewed")
        case "terms_accepted": L("Accepted the terms to sign electronically")
        case "signed": L("Signed")
        case "declined": L("Declined")
        case "completed": L("Every signature in: completed")
        case "voided": L("Request voided")
        case "revoked": L("Consent revoked")
        case "expired": L("Expired")
        case "sealed": L("PDF sealed")
        case "timestamped": L("Timestamp added")
        case "copy_emailed": L("Signed copy emailed")
        case "verified": L("Evidence verified")
        case "signed_before_evidence_v2": L("Signed before the evidence trail (carried over)")
        default: type ?? "—"
        }
    }

    static func actor(_ type: String?, _ name: String?) -> String {
        let role: String
        switch type {
        case "staff": role = L("Staff")
        case "signer": role = L("Signer")
        case "system": role = "PawMiaw"
        case "public": role = L("Visitor")
        default: role = type ?? ""
        }
        return name?.nonEmpty.map { "\($0) (\(role))" } ?? role
    }

    static func check(_ key: String) -> String {
        switch key {
        case "chain": L("Every event is intact and in order")
        case "signers": L("Each signature’s evidence matches")
        case "final": L("The final evidence matches")
        case "terms": L("The signing terms accepted are intact")
        case "document": L("The document still matches what was signed")
        case "signatureImages": L("The signature images are unchanged")
        case "sealedFile": L("The sealed PDF is unchanged")
        case "timestampedFile": L("The timestamped PDF is unchanged")
        default: key
        }
    }

    static let checkOrder = ["chain", "signers", "final", "terms", "document", "signatureImages", "sealedFile", "timestampedFile"]

    /// A hash as people can read it aloud: groups of four.
    static func grouped(_ hash: String?) -> String {
        guard let hash, !hash.isEmpty else { return "—" }
        var out = ""
        for (index, character) in hash.enumerated() {
            if index > 0 && index % 4 == 0 { out.append(" ") }
            out.append(character)
        }
        return out
    }
}

// MARK: - The card

private enum ConsentSheet: Identifiable {
    case request
    case amount(Consent)
    case sign(String)
    case view(String)
    case send(Consent, choice: String?)
    case evidence(Consent)
    case cancel(Consent)
    case revoke(Consent)

    var id: String {
        switch self {
        case .request: "request"
        case .amount(let c): "amount-\(c.id)"
        case .sign(let id): "sign-\(id)"
        case .view(let id): "view-\(id)"
        case .send(let c, let choice): "send-\(c.id)-\(choice ?? "")"
        case .evidence(let c): "evidence-\(c.id)"
        case .cancel(let c): "cancel-\(c.id)"
        case .revoke(let c): "revoke-\(c.id)"
        }
    }
}

/// The consents of a visit, stay or home stay, with their moves.
struct ConsentsCard: View {
    let context: ConsentContext
    /// Inside a page section or another sheet: no card of its own ("Ask for a consent" on top).
    var bare = false
    /// The toast once one is signed here ("Signed. It is kept with the visit or stay.").
    var signedMessage: String = L("Signed. It is kept with the visit or stay.")
    /// Every load, so a gate can see whether everything is signed now.
    var onLoaded: (ConsentList) -> Void = { _ in }

    @State private var list: ConsentList?
    @State private var failed: String?
    @State private var forbidden = false
    @State private var sheet: ConsentSheet?
    /// The sheet that opens once the current one has closed (ask → sign here).
    @State private var next: ConsentSheet?

    private var items: [Consent] { ConsentWords.sorted(list?.items ?? []) }
    private var lines: [ConsentLine] { list?.requirement?.lines ?? [] }
    private var canManage: Bool { list?.canManage == true }
    private var missing: Int { lines.filter { $0.satisfied != true }.count }

    var body: some View {
        Group {
            if forbidden {
                EmptyView()
            } else if bare {
                VStack(alignment: .leading, spacing: 12) {
                    if canManage {
                        HStack {
                            Spacer(minLength: 0)
                            PMButton(L("Ask for a consent"), systemImage: "doc.badge.plus", variant: .outline, size: .compact) { sheet = .request }
                        }
                    }
                    content
                }
            } else {
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(L("Consents"), systemImage: "signature").font(Theme.sectionFont).foregroundStyle(Theme.inkStrong)
                        if missing > 0 { StatusChip(text: missing == 1 ? L("1 missing") : LF("%d missing", missing), state: .waiting) }
                    }
                    content
                    if canManage {
                        PMButton(L("Ask for a consent"), systemImage: "doc.badge.plus", variant: .outline, size: .compact, fullWidth: true) { sheet = .request }
                    }
                }
            }
        }
        .reloadsOnScope { await load() }
        .sheet(item: $sheet, onDismiss: {
            if let upcoming = next { next = nil; sheet = upcoming }
        }) { which in
            sheetView(which)
        }
    }

    @ViewBuilder private var content: some View {
        if list == nil && failed == nil {
            ProgressView().frame(maxWidth: .infinity, minHeight: 56)
        } else if let failed, list == nil {
            HStack(spacing: 10) {
                Text(failed).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                PMButton(L("Try again"), variant: .outline, size: .compact) { Task { await load() } }
            }
        } else {
            if !lines.isEmpty { requirement }
            if items.isEmpty {
                Text(L("No consents on this one. Ask for one when the service needs the family’s signature."))
                    .font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
            } else {
                ForEach(items) { consent in row(consent) }
            }
        }
    }

    private func load() async {
        guard !context.act.isEmpty else { return }
        do {
            let loaded: ConsentList = try await API.get("/provider-consents", query: context.act.query)
            list = loaded
            failed = nil
            onLoaded(loaded)
        } catch is CancellationError {
        } catch {
            // Someone whose role doesn't see consents doesn't see the card.
            if (error as? APIError)?.status == 403 { forbidden = true; return }
            failed = ConsentWords.error(error, fallback: "The consents could not be loaded.")
        }
    }

    // MARK: Requirement

    private var requirement: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Required before it starts").uppercased()).font(.brandText(11, weight: .heavy)).tracking(1).foregroundStyle(Theme.inkSoft)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: line.satisfied == true ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(line.satisfied == true ? ProviderState.done.color : Theme.goldText)
                    Text(line.title ?? "").font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    Spacer(minLength: 6)
                    Text(line.satisfied == true ? L("Signed") : L("Missing")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((missing > 0 ? Theme.mango : ProviderState.done.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke((missing > 0 ? Theme.mango : Theme.borderSoft).opacity(0.6), lineWidth: 1))
    }

    // MARK: A consent

    private func row(_ consent: Consent) -> some View {
        let revocable = consent.status == "signed" && (!context.started || consent.validity == "standing")
        let cancellable = consent.status == "draft" || consent.status == "pending"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "signature").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.inkSoft).frame(width: 18)
                VStack(alignment: .leading, spacing: 6) {
                    Text(consent.title).font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.inkStrong).fixedSize(horizontal: false, vertical: true)
                    FlowLayout(spacing: 6) {
                        StatusChip(text: ConsentWords.status(consent.status), state: ConsentWords.state(consent.status), outlined: consent.status == "draft")
                        if context.pets.count > 1, let pet = consent.petName?.nonEmpty { HueChip(text: pet, hue: .grey, systemImage: "pawprint.fill") }
                        if consent.validity == "standing" { HueChip(text: ConsentWords.validity(consent.validity, consent.validDays), hue: .grey) }
                        if let amount = consent.amountText { HueChip(text: amount, hue: .butter, systemImage: "dollarsign.circle") }
                    }
                    Text(ConsentWords.line(consent)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            FlowLayout(spacing: 8) {
                if canManage && consent.status == "draft" {
                    PMButton(L("Enter amount"), systemImage: "dollarsign.circle", size: .compact) { sheet = .amount(consent) }
                }
                if canManage && consent.status == "pending" {
                    PMButton(L("Sign here"), systemImage: "signature", size: .compact) { sheet = .sign(consent.id) }
                    PMButton(L("Send for signature"), systemImage: "paperplane", variant: .outline, size: .compact) { sheet = .send(consent, choice: nil) }
                }
                if consent.status != "draft" {
                    PMButton(consent.status == "signed" ? L("View · Print") : L("View"), systemImage: "eye", variant: .outline, size: .compact) { sheet = .view(consent.id) }
                    PMButton(L("Evidence"), systemImage: "checkmark.shield", variant: .outline, size: .compact) { sheet = .evidence(consent) }
                }
                if canManage && cancellable {
                    PMButton(L("Withdraw"), systemImage: "xmark.circle", variant: .destructive, size: .compact) { sheet = .cancel(consent) }
                }
                if canManage && revocable {
                    PMButton(L("Revoke"), systemImage: "arrow.uturn.backward", variant: .destructive, size: .compact) { sheet = .revoke(consent) }
                }
            }
            .padding(.leading, 28)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.borderSoft, lineWidth: 1))
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetView(_ which: ConsentSheet) -> some View {
        switch which {
        case .request:
            ConsentRequestSheet(context: context) { consent, here in
                if here && consent.status == "pending" { next = .sign(consent.id) }
            }
        case .amount(let consent):
            ConsentAmountSheet(consent: consent, familyOnApp: context.familyOnApp) { updated, here in
                if here { next = .sign(updated.id) }
            }
        case .sign(let id):
            ConsentSignSheet(consentId: id, businessName: context.businessName, successMessage: signedMessage) { Task { await load() } }
        case .view(let id):
            ConsentViewSheet(consentId: id, context: context)
        case .send(let consent, let choice):
            ConsentSendSheet(consent: consent, context: context, initialChoice: choice) { next = .sign(consent.id) }
        case .evidence(let consent):
            ConsentEvidenceSheet(consent: consent, canManage: canManage) { next = .send(consent, choice: "link") }
        case .cancel(let consent):
            ConfirmSheet(
                title: L("Withdraw this request?"),
                message: LF("“%@” stops waiting for a signature. The family no longer sees it to sign.", consent.title) + " " + L("Any signing link sent for it stops working."),
                confirmTitle: L("Withdraw request"),
                destructive: true,
                askReason: true,
                reasonRequired: false,
                reasonLabel: L("Reason (optional)")
            ) { reason in
                do {
                    let _: Consent = try await API.post("/provider-consents/\(consent.id)/cancel", body: ["reason": reason])
                } catch { throw ConsentWords.refusal(error, fallback: "Could not withdraw it. Try again.") }
                Toast.show(L("Request withdrawn."))
                announceDataChanged()
            }
        case .revoke(let consent):
            ConfirmSheet(
                title: L("Revoke this consent?"),
                message: LF("“%@” stops counting from now on. What was signed stays on record, marked as revoked.", consent.title),
                confirmTitle: L("Revoke consent"),
                destructive: true,
                askReason: true,
                reasonRequired: true,
                reasonLabel: L("e.g. The client changed their mind at the desk")
            ) { reason in
                do {
                    let _: Consent = try await API.post("/provider-consents/\(consent.id)/revoke", body: ["reason": reason ?? ""])
                } catch { throw ConsentWords.refusal(error, fallback: "Could not revoke it. Try again.") }
                Toast.show(L("Consent revoked."))
                announceDataChanged()
            }
        }
    }
}

// MARK: - Ask for a consent

/// "Ask for a consent": one of the business's active templates, its amount when
/// the text names one, which pet (a once-per-pet consent on an act with several),
/// and whether it goes to the family now or is signed here.
struct ConsentRequestSheet: View {
    let context: ConsentContext
    /// The new consent, and whether it is signed here next.
    var onRequested: (Consent, Bool) -> Void = { _, _ in }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var templates: [ConsentTemplate]?
    @State private var failed: String?
    @State private var templateId = ""
    @State private var amount: Int?
    @State private var petId = ""
    @State private var how = "send"
    @State private var notify = true
    @State private var working = false
    @State private var prepared = false

    private var active: [ConsentTemplate] { (templates ?? []).filter { $0.status == nil || $0.status == "active" } }
    private var chosen: ConsentTemplate? { active.first { $0.id == templateId } }
    private var needsPet: Bool { chosen?.validity == "standing" && context.pets.count > 1 }
    private var signsHere: Bool { !context.familyOnApp || how == "here" }

    var body: some View {
        ProviderModal(
            title: L("Ask for a consent"),
            subtitle: context.familyOnApp ? L("The family signs it in their PawMiaw app, or the client signs it here.") : L("The family isn’t on PawMiaw: the client signs it here, on this device."),
            systemImage: "doc.badge.plus",
            accent: .butter,
            isDirty: !templateId.isEmpty,
            form: form,
            primaryTitle: signsHere ? L("Add and sign here") : (notify ? L("Send to the family") : L("Add it")),
            isWorking: working,
            onPrimary: submit
        ) {
            ModalSection(title: L("Which consent")) {
                if templates != nil {
                    if active.isEmpty {
                        NoticeCard(tone: .info, title: L("There are no active consents yet."), message: L("Set them up in Settings"))
                    } else {
                        FormField(label: "", key: "template", form: form) {
                            ChoiceCards(options: active.map { template in
                                (value: template.id, title: template.title,
                                 subtitle: Optional([ConsentWords.validity(template.validity, template.validDays),
                                                     template.needsAmount == true ? L("Names an amount") : nil,
                                                     template.language?.uppercased()].compactMap { $0 }.joined(separator: " · ")))
                            }, selection: Binding(get: { templateId }, set: { templateId = $0; form.clear("template") }))
                        }
                    }
                } else if let failed {
                    ErrorState(message: failed) { await load() }
                } else {
                    LoadingState()
                }
            }
            if chosen?.needsAmount == true {
                ModalSection(title: L("Amount"), subtitle: L("It fills {amount} in the text, e.g. the estimate or the deposit.")) {
                    MoneyField(label: L("Amount"), cents: $amount, key: "amount", form: form)
                }
            }
            if needsPet {
                ModalSection(title: L("For which pet")) {
                    FormField(label: "", key: "pet", form: form) {
                        FlowLayout(spacing: 8) {
                            ForEach(context.pets) { pet in
                                FilterChip(title: pet.name, isSelected: petId == pet.id) { petId = pet.id; form.clear("pet") }
                            }
                        }
                    }
                }
            }
            if context.familyOnApp {
                ModalSection(title: L("How will they sign?")) {
                    ChoiceCards(options: [
                        (value: "send", title: L("In the family’s PawMiaw app"), subtitle: L("They get a notification and sign in the app.")),
                        (value: "here", title: L("On this device"), subtitle: L("The client signs here now, with you as the witness.")),
                    ], selection: $how)
                    if how == "send" {
                        ToggleRow(title: L("Tell the family now"), subtitle: L("A notification with the consent to read and sign."), isOn: $notify)
                    }
                }
            }
        }
        .task {
            if !prepared { prepared = true; notify = context.familyOnApp }
            if templates == nil { await load() }
        }
    }

    private func load() async {
        do {
            templates = try await API.get("/provider-consent-templates", query: ["includeArchived": "false"])
            failed = nil
        } catch {
            failed = ConsentWords.error(error)
        }
    }

    private func submit() {
        guard form.check([
            ("template", chosen == nil ? L("Choose a consent.") : nil),
            ("amount", chosen?.needsAmount == true && (amount ?? 0) <= 0 ? L("Enter the amount this consent names.") : nil),
            ("pet", needsPet && petId.isEmpty ? L("Choose the pet — this consent is signed once for each pet.") : nil),
        ]), let chosen else { return }
        var body = context.act.body
        body["templateId"] = chosen.id
        body["notify"] = !signsHere && notify && context.familyOnApp
        if chosen.needsAmount == true { body["amountCents"] = amount }
        if needsPet { body["providerClientPetId"] = petId }
        let payload = body
        let here = signsHere
        working = true
        Task {
            defer { working = false }
            do {
                let created: Consent = try await API.post("/provider-consents", body: payload)
                Toast.show(created.notified == true ? L("Sent to the family to sign.") : L("Consent added."))
                announceDataChanged()
                onRequested(created, here)
                dismiss()
            } catch {
                form.apply(ConsentWords.refusal(error, fallback: "Could not ask for it. Try again."), known: ["templateId": "template", "amountCents": "amount", "providerClientPetId": "pet"])
            }
        }
    }
}

// MARK: - Enter the amount

/// A consent whose text names an amount waits as a draft until the business
/// enters it; then it goes to the family, or is signed here.
struct ConsentAmountSheet: View {
    let consent: Consent
    let familyOnApp: Bool
    var onReady: (Consent, Bool) -> Void = { _, _ in }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var amount: Int?
    @State private var how = "send"
    @State private var working = false

    private var signsHere: Bool { !familyOnApp || how == "here" }

    var body: some View {
        ProviderModal(
            title: consent.title,
            subtitle: L("This consent names an amount. Enter it before it is signed."),
            systemImage: "dollarsign.circle.fill",
            accent: .butter,
            isDirty: amount != consent.amountCents,
            form: form,
            primaryTitle: signsHere ? L("Save and sign here") : L("Save and send to the family"),
            isWorking: working,
            onPrimary: submit
        ) {
            MoneyField(label: L("Amount"), cents: $amount, key: "amount", form: form)
            if familyOnApp {
                ChoiceCards(options: [
                    (value: "send", title: L("In the family’s PawMiaw app"), subtitle: L("They get a notification and sign in the app.")),
                    (value: "here", title: L("On this device"), subtitle: L("The client signs here now, with you as the witness.")),
                ], selection: $how)
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { if amount == nil { amount = consent.amountCents } }
    }

    private func submit() {
        guard form.check([("amount", (amount ?? 0) <= 0 ? L("Enter the amount this consent names.") : nil)]) else { return }
        let here = signsHere
        working = true
        Task {
            defer { working = false }
            do {
                let updated: Consent = try await API.post("/provider-consents/\(consent.id)/send", body: ["amountCents": amount, "notify": !here])
                Toast.show(updated.notified == true ? L("Sent to the family to sign.") : L("Amount saved. It can be signed now."))
                announceDataChanged()
                onReady(updated, here)
                dismiss()
            } catch {
                form.apply(ConsentWords.refusal(error, fallback: "Could not save the amount. Try again."), known: ["amountCents": "amount"])
            }
        }
    }
}

// MARK: - Sign here

/// Signing a consent on this device with the client, the one sheet every consent
/// uses — a visit's, a stay's, the hospital's estimate and euthanasia consent.
/// Two steps: the terms for signing electronically ("I agree to sign
/// electronically"), then the full text, "I have read and agree", the signer's
/// full name and the signature, drawn on the pad or typed in the signature font.
/// The person signed in is kept as the witness.
struct ConsentSignSheet: View {
    let consentId: String
    var businessName: String? = nil
    /// The toast once it is signed.
    var successMessage: String = L("Signed. It is kept with the visit or stay.")
    var onSigned: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workspace: Workspace
    @StateObject private var form = FormState()
    @State private var consent: Consent?
    @State private var terms: EsignTerms?
    @State private var termsFailed = false
    @State private var failed: String?
    @State private var step = 0
    @State private var termsAccepted = false
    @State private var termsChanged = false
    @State private var agree = false
    @State private var signer = ""
    @State private var mode = "draw"
    @State private var strokes: [[CGPoint]] = []
    @State private var typed = ""
    @State private var saving = false

    private var meta: String {
        [businessName ?? workspace.current?.name, consent?.petName, consent?.amountText,
         consent.map { ConsentWords.validity($0.validity, $0.validDays) }]
            .compactMap { $0?.nonEmpty }.joined(separator: " · ")
    }

    var body: some View {
        ProviderModal(
            title: consent?.title ?? L("Consent"),
            subtitle: meta.nonEmpty,
            systemImage: "signature",
            accent: .butter,
            isDirty: termsAccepted || agree || !signer.isEmpty || !strokes.isEmpty || !typed.isEmpty,
            form: form,
            primaryTitle: consent == nil ? nil : (step == 0 ? L("Continue") : L("Sign")),
            isWorking: saving,
            onPrimary: step == 0 ? continueToSign : sign
        ) {
            if let consent {
                Picker(L("Step"), selection: Binding(get: { step }, set: { if $0 == 0 { step = 0 } else { continueToSign() } })) {
                    Text("1 · " + L("Signing terms")).tag(0)
                    Text("2 · " + L("Read and sign")).tag(1)
                }
                .pickerStyle(.segmented)
                NoticeCard(tone: .info, title: L("Hand the device to the client: they read it, tick that they agree, type their full name and sign. Your name is kept as the witness."))
                if step == 0 {
                    termsStep
                } else {
                    signStep(consent)
                }
            } else if let failed {
                ErrorState(message: failed) { await load() }
            } else {
                LoadingState()
            }
        }
        .task { if consent == nil { await load() } }
    }

    // MARK: Step 1: the terms

    @ViewBuilder private var termsStep: some View {
        EsignTermsPanel(terms: terms, failed: termsFailed, changed: termsChanged,
                        accepted: Binding(get: { termsAccepted }, set: { termsAccepted = $0; form.clear("terms") }),
                        error: form.error("terms")) { Task { await loadTerms() } }
            .id("terms")
    }

    private func paragraphs(_ text: String?) -> [String] {
        (text ?? "").components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    // MARK: Step 2: read and sign

    @ViewBuilder private func signStep(_ consent: Consent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(consent.title).font(Theme.heading(19)).foregroundStyle(Theme.inkStrong)
            Text(consent.body ?? "").font(Theme.text(15)).foregroundStyle(Theme.inkStrong).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.borderSoft, lineWidth: 1))
        .accessibilityLabel(L("The consent’s text"))
        FormField(label: "", key: "agree", form: form) {
            ToggleRow(title: L("I have read and agree"), isOn: Binding(get: { agree }, set: { agree = $0; form.clear("agree") }))
        }
        PMTextField(L("Full name of who signs"), text: $signer, key: "signer", form: form, prompt: L("First and last name"), capitalization: .words)
        FormField(label: L("Signature"), key: "signature", form: form) {
            VStack(alignment: .leading, spacing: 10) {
                Picker(L("Signature"), selection: Binding(get: { mode }, set: { value in
                    mode = value
                    form.clear("signature")
                    if value == "type" && typed.isEmpty, let name = normalizedName(signer) { typed = name }
                })) {
                    Text(L("Draw")).tag("draw")
                    Text(L("Type")).tag("type")
                }
                .pickerStyle(.segmented)
                if mode == "draw" {
                    SignaturePad(strokes: $strokes)
                        .onChange(of: strokes.count) { _, _ in form.clear("signature") }
                    if !strokes.isEmpty {
                        PMButton(L("Clear"), systemImage: "arrow.counterclockwise", variant: .outline, size: .compact) { strokes = [] }
                    }
                } else {
                    PMTextField(L("Typed signature"), text: $typed, prompt: L("Type your signature"), capitalization: .words)
                        .onChange(of: typed) { _, _ in form.clear("signature") }
                    ConsentTypedSignature(text: typed.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        Text(L("The text as you read it, your name, the signature, the time and this device are kept together and can’t be changed afterwards."))
            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
    }

    // MARK: Loading

    private func load() async {
        do {
            let loaded: Consent = try await API.get("/provider-consents/\(consentId)")
            consent = loaded
            failed = nil
            if let given = loaded.terms, let version = given.version {
                terms = EsignTerms(version: version, language: given.language, title: given.title, text: given.text, reviewNote: given.reviewNote)
            } else {
                await loadTerms()
            }
        } catch is CancellationError {
        } catch {
            failed = ConsentWords.error(error)
        }
    }

    private func loadTerms() async {
        let language = consent?.language ?? (LocalizationManager.shared.currentLanguage == .spanish ? "es" : "en")
        let fetched: EsignTerms? = try? await API.get("/esign/terms", query: ["lang": language])
        if let fetched { terms = fetched }
        termsFailed = fetched == nil
    }

    // MARK: Signing

    private func continueToSign() {
        guard terms != nil else { return }
        guard form.check([("terms", termsAccepted ? nil : L("Tick that you agree to sign electronically."))]) else { return }
        termsChanged = false
        step = 1
    }

    private func normalizedName(_ value: String) -> String? {
        let name = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (3...120).contains(name.count) && name.filter(\.isLetter).count >= 3 ? name : nil
    }

    private func sign() {
        guard let version = terms?.version, termsAccepted else {
            step = 0
            _ = form.check([("terms", L("Tick that you agree to sign electronically."))])
            return
        }
        let name = normalizedName(signer)
        let typedText = typed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let png = mode == "draw" ? SignaturePad.pngData(strokes) : nil
        let signatureProblem: String? = mode == "draw"
            ? (png == nil ? L("Draw the signature.") : nil)
            : ((2...80).contains(typedText.count) ? nil : L("Type the signature (2 to 80 characters)."))
        guard form.check([
            ("agree", agree ? nil : L("Tick that you read and agree.")),
            ("signer", name == nil ? L("Type the full name of who signs (at least 3 letters).") : nil),
            ("signature", signatureProblem),
        ]), let name else { return }
        var fields: [(String, String)] = [
            ("signerName", name), ("agree", "true"), ("termsAccepted", "true"), ("termsVersion", version),
            ("signatureKind", mode == "draw" ? "drawn" : "typed"),
            ("device", "PawMiaw Negocios · " + (UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")),
        ]
        var files: [API.UploadFile] = []
        if mode == "draw", let png {
            files.append(API.UploadFile(field: "signature", fileName: "signature.png", mimeType: "image/png", data: png))
        } else {
            fields.append(("typedSignature", typedText))
        }
        let parts = fields, uploads = files
        saving = true
        Task {
            defer { saving = false }
            do {
                let _: EmptyResponse = try await API.multipart("/provider-consents/\(consentId)/sign", fields: parts, files: uploads)
                Toast.show(successMessage)
                announceDataChanged()
                onSigned()
                dismiss()
            } catch {
                await refused(error)
            }
        }
    }

    private func refused(_ error: Error) async {
        let code = (error as? APIError)?.code ?? ""
        switch code {
        case "terms_outdated":
            // The terms moved on while this was open: show the new ones and ask again.
            await load()
            termsAccepted = false
            termsChanged = true
            step = 0
            Toast.error(L("The terms for signing electronically were just updated. Read the new version and accept it to continue."))
        case "terms_required":
            termsAccepted = false
            step = 0
            _ = form.check([("terms", L("Tick that you agree to sign electronically."))])
        case "agreement_required":
            _ = form.check([("agree", L("Tick that you read and agree."))])
        case "signer_name_required":
            _ = form.check([("signer", L("Type the full name of who signs."))])
        case "typed_signature_required":
            _ = form.check([("signature", L("Type the signature (2 to 80 characters)."))])
        case _ where code.hasPrefix("signature_"):
            _ = form.check([("signature", ConsentWords.error(error, fallback: "Could not sign it. Try again."))])
        default:
            Toast.error(ConsentWords.error(error, fallback: "Could not sign it. Try again."))
        }
    }
}

/// A typed signature in the signature font, on a white line (a preview, or a document's mark).
struct ConsentTypedSignature: View {
    let text: String
    var height: CGFloat = 110

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white)
            RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.borderSoft, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            if text.isEmpty {
                Text(L("Your signature shows here")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Color(white: 0.55))
            } else {
                TypedSignature(text: text, size: 34).padding(.horizontal, 4)
            }
            VStack { Spacer(); Rectangle().fill(Color(white: 0.8)).frame(height: 1).padding(.horizontal, 24).padding(.bottom, 22) }
        }
        .frame(height: height)
        .accessibilityLabel(text.isEmpty ? L("Your signature shows here") : text)
    }
}

// MARK: - View · Print

/// The consent as a document: who, what, the text, the signature and its integrity, and the PDF.
struct ConsentViewSheet: View {
    let consentId: String
    let context: ConsentContext

    @State private var consent: Consent?
    @State private var failed: String?

    var body: some View {
        ProviderModal(
            title: consent?.title ?? L("Consent"),
            subtitle: consent.map { ConsentWords.status($0.status) },
            systemImage: "doc.text.fill",
            accent: .sky,
            cancelTitle: L("Close")
        ) {
            if let consent {
                document(consent)
            } else if let failed {
                ErrorState(message: failed) { await load() }
            } else {
                LoadingState()
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            consent = try await API.get("/provider-consents/\(consentId)")
            failed = nil
        } catch is CancellationError {
        } catch {
            failed = ConsentWords.error(error)
        }
    }

    @ViewBuilder private func document(_ consent: Consent) -> some View {
        DocumentButton(title: consent.status == "signed" ? L("Print") : L("Download PDF"), path: "/provider-consents/\(consent.id)/pdf",
                       query: ["lang": LocalizationManager.shared.currentLanguage.rawValue], fileName: consent.title, variant: .primary, size: .compact)
        Card {
            FactRow(label: L("Business"), value: context.businessName ?? Workspace.shared.current?.name)
            FactRow(label: L("Client"), value: context.clientName)
            if let pet = consent.petName { FactRow(label: L("Pet"), value: pet) }
            if let act = context.actLabel { FactRow(label: L("For"), value: act) }
            if let amount = consent.amountText { FactRow(label: L("Amount"), value: amount) }
            FactRow(label: L("Valid"), value: ConsentWords.validity(consent.validity, consent.validDays))
            FactRow(label: L("Asked for"), value: ConsentWords.date(consent.requestedAt))
        }
        Text(ConsentWords.line(consent)).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
        if let note = ConsentWords.closedNote(consent) {
            NoticeCard(tone: .problem, title: note)
        }
        VStack(alignment: .leading, spacing: 10) {
            Text(consent.title).font(Theme.heading(19)).foregroundStyle(Theme.inkStrong)
            Text(consent.body ?? "").font(Theme.text(15)).foregroundStyle(Theme.inkStrong).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.borderSoft, lineWidth: 1))
        ModalSection(title: L("Signature")) {
            if consent.signedAt != nil {
                SignatureMarkView(mark: SignatureMark(kind: (consent.mark?.kind == "typed" ? consent.mark?.text : nil) != nil ? "typed" : "drawn", text: consent.mark?.kind == "typed" ? consent.mark?.text : nil, imageDataUrl: consent.signatureDataUrl ?? consent.mark?.imageDataUrl))
                if let name = consent.signerName { Text(LF("Signature of %@", name)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong) }
                FactRow(label: L("Signed"), value: ConsentWords.date(consent.signedAt))
                FactRow(label: L("How"), value: ConsentWords.via(consent.signedVia))
                if let account = consent.signerAccountName { FactRow(label: L("PawMiaw account"), value: account) }
                if let witness = consent.witnessName { FactRow(label: L("Witness"), value: witness) }
                if let integrity = consent.integrity {
                    Label(integrity.verified == true ? L("Integrity verified: the text and the signature match what was signed.")
                          : integrity.verified == false ? L("Integrity check failed: what is stored no longer matches what was signed.")
                          : L("The integrity could not be checked."),
                          systemImage: integrity.verified == true ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(Theme.text(13, weight: .semibold))
                        .foregroundStyle(integrity.verified == false ? Theme.coralText : Theme.inkSoft)
                    if let hash = integrity.snapshotSha256 {
                        Text("\(L("Fingerprint")): \(ConsentEsignWords.grouped(String(hash.prefix(16))))").font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.inkSoft)
                    }
                }
            } else {
                Text(L("Not signed.")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
            }
        }
        if let evidence = consent.evidence, let code = evidence.verifyCode {
            ModalSection(title: L("Electronic signature")) {
                FactRow(label: L("Verify code"), value: code)
                if let method = evidence.method { FactRow(label: L("How"), value: ConsentEsignWords.method(method)) }
                FactRow(label: L("Sealed PDF"), value: ConsentEsignWords.seal(evidence.seal?.status))
                if let url = evidence.verifyUrl.flatMap(URL.init(string:)) {
                    Link(destination: url) { Label(L("Open the verify page"), systemImage: "checkmark.shield").font(Theme.text(14, weight: .bold)) }
                }
            }
        }
    }
}

// MARK: - Send for signature

/// "Send for signature": in the family's PawMiaw app, by a link the client opens
/// with a code emailed to them (and a WhatsApp message), or on this device now.
struct ConsentSendSheet: View {
    let consent: Consent
    let context: ConsentContext
    var initialChoice: String? = nil
    /// "On this device": this closes and the signing sheet opens.
    var onSignHere: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var choice = "link"
    @State private var email = ""
    @State private var phone = ""
    @State private var days = 7
    @State private var sendEmail = true
    @State private var working = false
    @State private var result: ConsentCreatedLink?
    @State private var started = false

    private var primaryTitle: String {
        if result != nil { return L("Done") }
        switch choice {
        case "device": return L("Sign on this device")
        case "app": return consent.sentAt != nil ? L("Remind the family") : L("Send to the app")
        default: return L("Make the link")
        }
    }

    var body: some View {
        ProviderModal(
            title: L("Send for signature"),
            subtitle: consent.title,
            systemImage: "paperplane.fill",
            accent: .aqua,
            form: form,
            primaryTitle: primaryTitle,
            isWorking: working,
            cancelTitle: result != nil ? L("Close") : L("Cancel"),
            onPrimary: submit
        ) {
            if let result {
                done(result)
            } else {
                ModalSection(title: L("How will they sign?")) {
                    ChoiceCards(options: (context.familyOnApp
                        ? [(value: "app", title: L("In the family’s PawMiaw app"), subtitle: Optional(L("They get a notification and sign in the app.")))]
                        : []) + [
                        (value: "link", title: L("By link"), subtitle: Optional(L("An email with a link; they confirm a 6-digit code and sign from any phone. Share it by WhatsApp too."))),
                        (value: "device", title: L("On this device"), subtitle: Optional(L("The client signs here now, with you as the witness."))),
                    ], selection: $choice)
                    if !context.familyOnApp {
                        Text(L("This family isn’t on PawMiaw.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
                if choice == "link" {
                    ModalSection(title: L("Where to send it")) {
                        PMTextField(L("Client’s email"), text: $email, key: "email", form: form, prompt: L("name@example.com"),
                                    hint: L("The code goes to this email. Empty uses the email on the client’s file."), keyboard: .emailAddress, capitalization: .never, optional: true)
                        PMTextField(L("Phone for WhatsApp (optional)"), text: $phone, key: "phone", form: form, prompt: "+52 55 1234 5678",
                                    hint: L("With a phone you get a “Share by WhatsApp” button. The code still goes by email."), keyboard: .phonePad, capitalization: .never, optional: true)
                        FormField(label: L("The link works for")) {
                            FlowLayout(spacing: 8) {
                                ForEach([1, 3, 7, 14, 30], id: \.self) { option in
                                    FilterChip(title: option == 1 ? L("1 day") : LF("%d days", option), isSelected: days == option) { days = option }
                                }
                            }
                        }
                        ToggleRow(title: L("Email the link now"), subtitle: L("Off: you only copy it or share it by WhatsApp."), isOn: $sendEmail)
                    }
                }
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            choice = initialChoice ?? (context.familyOnApp ? "app" : "link")
            email = context.clientEmail?.trimmingCharacters(in: .whitespaces) ?? ""
            phone = context.clientPhone?.trimmingCharacters(in: .whitespaces) ?? ""
        }
    }

    @ViewBuilder private func done(_ result: ConsentCreatedLink) -> some View {
        let masked = result.link?.maskedEmail ?? ""
        NoticeCard(
            tone: .success,
            title: result.emailSent == true ? LF("Link sent to %@.", masked) : L("The link is ready. It wasn’t emailed: share it yourself."),
            message: LF("It works until %@; the client asks for a code sent to %@ before they can read and sign.", ConsentWords.date(result.link?.expiresAt), masked)
        )
        if let url = result.url {
            ModalSection(title: L("The link")) {
                Text(url).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.inkStrong).lineLimit(2).textSelection(.enabled)
                FlowLayout(spacing: 8) {
                    PMButton(L("Copy"), systemImage: "doc.on.doc", variant: .outline, size: .compact) {
                        UIPasteboard.general.string = url
                        Toast.show(L("Link copied."))
                    }
                    if let share = URL(string: url) {
                        ShareLink(item: share) { Label(L("Share"), systemImage: "square.and.arrow.up") }
                            .buttonStyle(.pm(.outline, size: .compact))
                    }
                    if let whatsapp = result.whatsappUrl.flatMap(URL.init(string:)), whatsapp.scheme == "https" {
                        Link(destination: whatsapp) { Label(L("Share by WhatsApp"), systemImage: "message.fill") }
                            .buttonStyle(.pm(.outline, size: .compact))
                    }
                }
                Text(L("Anyone with the link still needs the code from the client’s email. Making a new link stops this one."))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    /// "+525512345678" from what was typed, or nil when it isn't a phone number.
    private func cleanPhone(_ text: String) -> String? {
        let digits = text.filter(\.isNumber)
        if text.trimmingCharacters(in: .whitespaces).hasPrefix("+") { return (8...15).contains(digits.count) ? "+" + digits : nil }
        if digits.count == 10 { return "+52" + digits }
        return (11...15).contains(digits.count) ? "+" + digits : nil
    }

    private func submit() {
        if result != nil { dismiss(); return }
        switch choice {
        case "device":
            onSignHere()
            dismiss()
        case "app":
            working = true
            Task {
                defer { working = false }
                do {
                    let sent: Consent = try await API.post("/provider-consents/\(consent.id)/send", body: ["notify": true])
                    Toast.show(sent.notified == true ? L("Sent to the family’s app.") : L("Already sent today. The family can sign it from the app."))
                    announceDataChanged()
                    dismiss()
                } catch {
                    Toast.error(ConsentWords.error(error, fallback: "Could not send it. Try again."))
                }
            }
        default:
            let typedEmail = email.trimmingCharacters(in: .whitespaces)
            let typedPhone = phone.trimmingCharacters(in: .whitespaces)
            let phoneValue = typedPhone.isEmpty ? nil : cleanPhone(typedPhone)
            guard form.check([
                ("email", !typedEmail.isEmpty && !(typedEmail.contains("@") && typedEmail.contains(".")) ? L("That email doesn’t look right.") : nil),
                ("phone", !typedPhone.isEmpty && phoneValue == nil ? L("That phone number doesn’t look right. Include the country code, e.g. +52.") : nil),
            ]) else { return }
            var body: [String: Any?] = ["days": days, "sendEmail": sendEmail, "language": consent.language ?? "es"]
            if !typedEmail.isEmpty { body["email"] = typedEmail }
            if let phoneValue { body["phone"] = phoneValue }
            let payload = body
            working = true
            Task {
                defer { working = false }
                do {
                    result = try await API.post("/provider-consents/\(consent.id)/signing-links", body: payload)
                    announceDataChanged()
                } catch {
                    form.apply(ConsentWords.refusal(error, fallback: "Could not make the link. Try again."), known: ["email": "email", "phone": "phone"])
                }
            }
        }
    }
}

// MARK: - Evidence

/// A consent's e-signature as the business sees it: where it stands, who signs and
/// how, the links (and stopping one), the fingerprints, the event trail and "Verify".
struct ConsentEvidenceSheet: View {
    let consent: Consent
    let canManage: Bool
    /// "Send a link": this closes and the send sheet opens on "By link".
    var onSendLink: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var evidence: ConsentEvidence?
    @State private var failed: String?
    @State private var verifying = false
    @State private var result: ConsentVerifyResult?
    @State private var stopping: ConsentSigningLink?

    private var canSend: Bool { canManage && evidence?.canSendLink == true }

    var body: some View {
        ProviderModal(
            title: L("Signature evidence"),
            subtitle: consent.title,
            systemImage: "checkmark.shield.fill",
            accent: .lavender,
            primaryTitle: canSend ? ((evidence?.links ?? []).contains { $0.status == "active" } ? L("Send a new link") : L("Send a link")) : nil,
            cancelTitle: L("Close"),
            onPrimary: canSend ? { onSendLink(); dismiss() } : nil
        ) {
            if let evidence {
                content(evidence)
            } else if let failed {
                ErrorState(message: failed) { await load() }
            } else {
                LoadingState()
            }
        }
        .task { await load() }
        .sheet(item: $stopping) { link in
            ConfirmSheet(
                title: L("Stop this signing link?"),
                message: LF("The link sent to %@ stops working at once. You can send a new one.", link.maskedEmail ?? ""),
                confirmTitle: L("Stop the link"),
                destructive: true,
                askReason: true,
                reasonRequired: false,
                reasonLabel: L("Reason (optional)")
            ) { reason in
                var body: [String: Any?] = [:]
                if let reason { body["reason"] = reason }
                do {
                    let _: EmptyResponse = try await API.post("/provider-signature-links/\(link.id)/revoke", body: body)
                } catch { throw ConsentWords.refusal(error, fallback: "Could not stop the link. Try again.") }
                Toast.show(L("The link was stopped."))
                announceDataChanged()
                await load()
            }
        }
    }

    private func load() async {
        do {
            evidence = try await API.get("/provider-consents/\(consent.id)/evidence")
            failed = nil
        } catch is CancellationError {
        } catch {
            failed = ConsentWords.error(error, fallback: "The evidence could not be loaded.")
        }
    }

    private func verify(_ requestId: String) {
        verifying = true
        Task {
            defer { verifying = false }
            do {
                result = try await API.post("/provider-signatures/\(requestId)/verify", body: [:])
                await load()
            } catch {
                Toast.error(ConsentWords.error(error, fallback: "Could not run the check. Try again."))
            }
        }
    }

    @ViewBuilder private func content(_ evidence: ConsentEvidence) -> some View {
        if let summary = evidence.summary {
            Card {
                HStack {
                    StatusChip(text: ConsentEsignWords.envelope(summary.status), state: summary.status == "completed" ? .done : summary.status == "pending" ? .waiting : .problem)
                    Spacer()
                    if let requestId = summary.requestId {
                        PMButton(L("Verify"), systemImage: "checkmark.shield", size: .compact, isWorking: verifying) { verify(requestId) }
                    }
                }
                if let method = summary.method { FactRow(label: L("How"), value: ConsentEsignWords.method(method)) }
                if summary.signedAt != nil { FactRow(label: L("Signed"), value: ConsentWords.date(summary.signedAt)) }
                if let code = summary.verifyCode { FactRow(label: L("Verify code"), value: code) }
                FactRow(label: L("Sealed PDF"), value: ConsentEsignWords.seal(summary.seal?.status))
                if summary.revokedAt != nil { FactRow(label: L("Revoked"), value: ConsentWords.date(summary.revokedAt)) }
                if let url = summary.verifyUrl.flatMap(URL.init(string:)) {
                    Link(destination: url) { Label(L("Open the verify page"), systemImage: "safari").font(Theme.text(14, weight: .bold)) }
                }
            }
        }
        if let result { verifyPanel(result) }
        ModalSection(title: L("Signers")) {
            let signers = evidence.signers ?? []
            if signers.isEmpty { Text(L("No signer yet.")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft) }
            ForEach(signers) { signer in
                Card(padding: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(signer.name ?? L("Name not given yet")).font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            Text((signer.role == "professional" ? L("Professional") : L("Signer")) + (signer.maskedEmail.map { " · \($0)" } ?? ""))
                                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        StatusChip(text: ConsentEsignWords.signer(signer.status), state: signer.status == "signed" ? .done : signer.status == "pending" ? .waiting : .problem)
                    }
                    SignatureMarkView(mark: SignatureMark(kind: (signer.mark?.kind == "typed" ? signer.mark?.text : nil) != nil ? "typed" : "drawn", text: signer.mark?.kind == "typed" ? signer.mark?.text : nil, imageDataUrl: signer.mark?.imageDataUrl))
                    if let method = signer.method { FactRow(label: L("How"), value: ConsentEsignWords.method(method)) }
                    if let witness = signer.witnessName { FactRow(label: L("Witness"), value: witness) }
                    if signer.emailVerifiedAt != nil { FactRow(label: L("Email code confirmed"), value: ConsentWords.date(signer.emailVerifiedAt)) }
                    if signer.termsAcceptedAt != nil {
                        FactRow(label: L("Accepted the signing terms"), value: ConsentWords.date(signer.termsAcceptedAt) + (signer.termsVersion.map { " · v\($0)" } ?? ""))
                    }
                    if signer.signedAt != nil { FactRow(label: L("Signed"), value: ConsentWords.date(signer.signedAt)) }
                    if signer.declinedAt != nil { FactRow(label: L("Declined"), value: ConsentWords.date(signer.declinedAt) + (signer.declineReason.map { " — \($0)" } ?? "")) }
                    if let ip = signer.ip { FactRow(label: L("IP address"), value: ip) }
                    if let device = signer.device { FactRow(label: L("Device"), value: device) }
                }
            }
        }
        let links = evidence.links ?? []
        if !links.isEmpty {
            ModalSection(title: L("Signing links")) {
                ForEach(links) { link in
                    Card(padding: 12) {
                        HStack(alignment: .top) {
                            Text([link.maskedEmail, link.phone].compactMap { $0 }.joined(separator: " · ")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            Spacer()
                            StatusChip(text: ConsentEsignWords.link(link.status), state: link.status == "active" ? .waiting : link.status == "used" ? .done : .closed)
                        }
                        Text([LF("Made %@", ConsentWords.date(link.createdAt)) + (link.createdByName.map { " · \($0)" } ?? ""),
                              link.status == "active" ? LF("Works until %@", ConsentWords.date(link.expiresAt)) : nil,
                              link.openedAt != nil ? LF("Opened %@", ConsentWords.date(link.openedAt)) : nil,
                              link.verifiedAt != nil ? LF("Code confirmed %@", ConsentWords.date(link.verifiedAt)) : nil].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        if canManage && link.status == "active" {
                            PMButton(L("Stop this link"), systemImage: "xmark.circle", variant: .outline, size: .compact) { stopping = link }
                        }
                    }
                }
            }
        }
        ModalSection(title: L("Fingerprints"), subtitle: L("SHA-256 of what was signed. Any change to the text or the record changes them.")) {
            hashRow(L("Document"), evidence.documentSha256)
            if let final = evidence.finalEvidenceSha256 { hashRow(L("Final evidence"), final) }
            if let sealed = evidence.summary?.seal?.sha256 { hashRow(L("Sealed PDF"), sealed) }
            if let version = evidence.termsVersion { FactRow(label: L("Signing terms"), value: "v\(version)") }
        }
        ModalSection(title: L("Event trail"), subtitle: L("Every step, in order. Each one is chained to the one before, so none can be changed or removed unnoticed.")) {
            let events = (evidence.events ?? []).sorted { ($0.sequence ?? 0) < ($1.sequence ?? 0) }
            if events.isEmpty { Text(L("No events yet.")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft) }
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Theme.blue).frame(width: 9, height: 9).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ConsentEsignWords.event(event.type)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        Text([ConsentWords.date(event.at), ConsentEsignWords.actor(event.actorType, event.actorName), event.ip.map { "IP \($0)" }].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        }
    }

    private func hashRow(_ label: String, _ hash: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
            Text(ConsentEsignWords.grouped(hash)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkStrong).textSelection(.enabled)
        }
    }

    private func verifyPanel(_ result: ConsentVerifyResult) -> some View {
        let checks = result.checks ?? [:]
        let keys = ConsentEsignWords.checkOrder.filter { checks.keys.contains($0) } + checks.keys.filter { !ConsentEsignWords.checkOrder.contains($0) }.sorted()
        return VStack(alignment: .leading, spacing: 8) {
            Label(result.ok == true ? L("Everything matches what was signed.") : L("Something no longer matches what was signed."),
                  systemImage: result.ok == true ? "checkmark.shield.fill" : "questionmark.diamond.fill")
                .font(Theme.text(15, weight: .bold))
                .foregroundStyle(result.ok == true ? ProviderState.done.color : Theme.coralText)
            Text(LF("Checked %@", ConsentWords.date(result.checkedAt))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            ForEach(keys, id: \.self) { key in
                let value = checks[key] ?? nil
                HStack(spacing: 8) {
                    Image(systemName: value == true ? "checkmark.circle.fill" : value == false ? "xmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(value == true ? ProviderState.done.color : value == false ? Theme.coralText : Theme.inkSoft)
                    Text(ConsentEsignWords.check(key)).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    Spacer(minLength: 4)
                    if value == nil { Text(L("Not yet")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                }
            }
            ForEach(result.errors ?? [], id: \.self) { error in
                Text(error).font(Theme.text(12)).foregroundStyle(Theme.coralText)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((result.ok == true ? ProviderState.done.color : Theme.coral).opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
