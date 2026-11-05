//
//  HomeWelcomeSigning.swift
//  PawMiawNegocios
//
//  The welcome's last two steps (web member-onboarding/signature-step.tsx,
//  credentials-step.tsx): the signature adopted once — drawn, typed or a
//  scan, with the professional e-sign terms accepted one time, so every
//  later "Firmar" is one tap (backend docs/e-signatures.md, "Adopt once") —
//  and the credentials by the business's country: the one the law asks to
//  prescribe first, the optional ones after, each added with Team's
//  credential sheet. The capture, the terms and the save are the shared
//  `SignatureCapture` pieces. Also used from Home's reminders.
//

import SwiftUI

// MARK: - 4. The signature, adopted once

struct HomeWelcomeSignatureStep: View {
    let state: HomeWelcomeState
    let onDone: () async -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    @StateObject private var form = FormState()
    @State private var terms: EsignTerms?
    @State private var termsFailed = false
    @State private var termsChanged = false
    @State private var accepted = false
    @State private var termsError: String?
    @State private var replacing = false
    @State private var draft = SignatureDraft()
    @State private var busy = false
    @State private var started = false

    private var saved: SignatureMark? { state.signature?.saved }
    private var adopted: Bool { state.signature?.adopted == true }
    private var language: String { LocalizationManager.shared.currentLanguage.rawValue }

    var body: some View {
        let name = HomeWelcomeState.printedName(state.profile?.displayName ?? "", state.profile?.accountName)
        HomeWelcomeStepFrame(state: state, step: "signature", title: L("Your signature, adopted once"),
                             description: L("Draw it, type it or upload a scan, and accept signing electronically. You do this once."),
                             nextLabel: adopted && !replacing ? L("Continue") : L("Adopt my signature"), busy: busy,
                             nextDisabled: !adopted && terms == nil,
                             note: adopted ? nil : L("Skipping it is fine: you can still sign, but your documents carry no signature image until you adopt one."),
                             onNext: next, onBack: onBack, onSkip: adopted ? nil : onSkip) {
            HomeWelcomeBlock(systemImage: "pencil.and.scribble", title: L("Your signature"), hint: L("As you sign on paper. A scan on white paper works too: PawMiaw trims it and clears the background.")) {
                if let saved, !replacing {
                    SignatureMarkView(mark: saved, name: name, height: 110)
                    Text(name).font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
                    if let created = saved.createdAt { Text(LF("Saved %@", DateText.date(created))).font(Theme.captionFont).foregroundStyle(Theme.inkSoft) }
                    PMButton(L("Change"), systemImage: "pencil", variant: .outline, size: .compact) { replacing = true; form.clear("signature") }
                } else {
                    SignatureCapture(modes: SignatureCaptureMode.professional, draft: $draft, suggestedText: name, label: nil, form: form)
                    if saved != nil {
                        PMButton(L("Keep the saved one"), variant: .outline, size: .compact) { replacing = false; form.clear("signature") }
                    }
                }
            }
            if adopted && !replacing {
                HStack(alignment: .top, spacing: 10) {
                    Glyph("badge-check", size: 16).foregroundStyle(Theme.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Adopted")).font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        if let at = state.signature?.adoption?.acceptedAt {
                            Text(LF("You accepted signing electronically on %@. Signing is one tap.", DateText.date(at))).font(Theme.smallFont).foregroundStyle(Theme.inkStrong)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.blueWash, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            } else {
                HomeWelcomeBlock(systemImage: "doc.text.fill", title: L("Signing electronically"), hint: L("Read it once. It is what makes one tap your signature.")) {
                    EsignTermsPanel(terms: terms, failed: termsFailed, changed: termsChanged, accepted: Binding(get: { accepted }, set: { accepted = $0; termsError = nil }), error: termsError) {
                        Task { await loadTerms() }
                    }
                }
            }
            Card {
                GlyphLabel(L("Then, one tap"), icon: "zap").font(Theme.sectionFont).foregroundStyle(Theme.inkStrong)
                Text(L("Prescriptions, signed records and discharges carry this signature when you press Sign. No drawing and no terms each time; each document keeps its own copy and the record of this acceptance."))
                    .font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
            }
        }
        .task {
            guard !started else { return }
            started = true
            replacing = saved == nil
            draft.typed = name
            await loadTerms()
        }
    }

    private func loadTerms() async {
        termsFailed = false
        do {
            terms = try await ProfessionalSignature.terms(language: language)
        } catch {
            termsFailed = true
        }
    }

    private func next() {
        // Already adopted and nothing new: on to the next step.
        if adopted && !replacing {
            busy = true
            Task { await onDone(); busy = false }
            return
        }
        guard accepted else {
            termsError = L("Accept signing electronically to adopt your signature.")
            Toast.error(L("Accept signing electronically to adopt your signature."))
            return
        }
        guard let terms else { return }
        var signature: CapturedSignature?
        if replacing || saved == nil {
            guard form.check([("signature", draft.problem())]) else { return }
            signature = draft.captured()
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                if let signature {
                    try await ProfessionalSignature.save(signature, terms: terms, language: language)
                } else {
                    try await ProfessionalSignature.adopt(terms: terms, language: language)
                }
                Toast.show(L("Your signature is adopted. Signing is one tap from now on."))
                announceDataChanged()
                await onDone()
            } catch let api as APIError where api.code == "terms_outdated" {
                termsChanged = true
                accepted = false
                await loadTerms()
            } catch let api as APIError where api.code?.hasPrefix("signature_") == true || api.code == "typed_signature_required" {
                _ = form.check([("signature", SignatureRules.message(api, fallback: api.message))])
            } catch {
                Toast.error(errorText(error, fallback: L("Could not save your signature.")))
            }
        }
    }
}

// MARK: - 5. Credentials

struct HomeWelcomeCredentialsStep: View {
    let state: HomeWelcomeState
    let last: Bool
    let onReload: () async -> Void
    let onDone: () async -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    @State private var adding: String?
    @State private var busy = false

    private var credentials: HomeWelcomeState.Credentials? { state.credentials }
    private var prescriber: Bool { credentials?.kind == "prescriber" }

    var body: some View {
        let required = credentials?.required
        let items = credentials?.items ?? []
        let requiredItems = required.map { type in items.filter { $0.type == type } } ?? []
        let otherItems = items.filter { item in !requiredItems.contains { $0.id == item.id } }
        let optional = (credentials?.offered ?? []).filter { $0 != required }
        let canPrescribe = credentials?.canPrescribe == true
        let title = prescriber ? L("Your credentials") : (credentials?.kind == "vet_tech" ? L("Your license and certifications") : L("Your certifications"))
        let description = prescriber
            ? (required.map { LF("Add %@ to sign prescriptions here. The rest is optional.", HomeWelcomeText.credentialNoun($0)) } ?? L("Add your professional license to sign prescriptions. The rest is optional."))
            : L("Optional. What you add shows on your profile in this workspace.")
        HomeWelcomeStepFrame(state: state, step: "credentials", title: title, description: description,
                             nextLabel: last ? L("Finish") : L("Save and continue"), busy: busy,
                             note: prescriber && !canPrescribe ? L("Without it you work as usual; the first prescription you sign asks for it right there.") : nil,
                             onNext: { busy = true; Task { await onDone(); busy = false } }, onBack: onBack,
                             onSkip: prescriber && !canPrescribe ? onSkip : nil) {
            if prescriber, let required {
                Card(tint: canPrescribe ? Theme.blue : nil) {
                    HStack(alignment: .top, spacing: 12) {
                        if canPrescribe {
                            HomeDisc(icon: "badge-check", size: 40, iconSize: 20, fill: Theme.blueFixed, ink: .white)
                        } else {
                            IconBadge(icon: "id-card", accent: Theme.blue, size: 40, iconSize: 20, ink: .accent, washPercent: 10)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(TeamCredentialRules.label(required)).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                            Text(canPrescribe ? L("You can sign prescriptions here.") : L("Needed to prescribe in this country.")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer(minLength: 0)
                        if requiredItems.isEmpty {
                            PMButton(L("Add"), systemImage: "plus", size: .compact) { adding = required }
                        }
                    }
                    ForEach(requiredItems) { HomeCredentialRow(credential: $0) }
                }
            }
            if prescriber && required == nil {
                NoticeCard(tone: .info, title: L("The workspace has no country yet, so any professional license lets you prescribe."))
            }
            HomeWelcomeBlock(systemImage: "award", title: prescriber ? L("Optional") : L("What you can add"), hint: prescriber ? L("Only if they apply to you.") : nil) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 8)], spacing: 8) {
                    ForEach(optional, id: \.self) { type in
                        Button { adding = type } label: {
                            HStack(alignment: .top, spacing: 10) {
                                HomeDisc(icon: type == "certification" ? "award" : "plus", size: 30, iconSize: 16, ink: Theme.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(TeamCredentialRules.label(type)).font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.inkStrong)
                                    if let why = HomeWelcomeText.optionalWhy(type) { Text(why).font(Theme.text(13)).foregroundStyle(Theme.inkSoft) }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1.5, dash: [5])))
                        }
                        .buttonStyle(.plain)
                    }
                }
                ForEach(otherItems) { HomeCredentialRow(credential: $0) }
            }
            Text(L("The prescription fields and wording follow public sources (NOM-064-ZOO-2000 in Mexico; the AVMA, the DEA and state boards in the United States). Have a professional review them before you rely on them."))
                .font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
        }
        .sheet(item: Binding(get: { adding.map(HomeCredentialAsk.init) }, set: { adding = $0?.type })) { ask in
            TeamCredentialSheet(memberId: "me", isSelf: true, country: credentials?.country, businessAddress: credentials?.businessAddress, types: [ask.type]) {
                await onReload()
            }
        }
    }
}

struct HomeCredentialAsk: Identifiable {
    let type: String
    var id: String { type }
}

private struct HomeCredentialRow: View {
    let credential: HomeWelcomeState.Credential

    var body: some View {
        let name = credential.type == "certification" ? (credential.title?.nonEmpty ?? TeamCredentialRules.label(credential.type)) : TeamCredentialRules.label(credential.type)
        HStack(spacing: 8) {
            Glyph("badge-check", size: 16).foregroundStyle(Theme.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                let line = [[credential.region, credential.number].compactMap { $0?.nonEmpty }.joined(separator: " ").nonEmpty, credential.issuer?.nonEmpty, credential.expiresOn.map { LF("Expires %@", DateText.date($0)) }].compactMap { $0 }
                if !line.isEmpty { Text(line.joined(separator: " · ")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
            }
            Spacer(minLength: 0)
            TeamCredentialStatusChip(status: credential.status, verified: credential.verified)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }
}
