//
//  HomeWelcome.swift
//  PawMiawNegocios
//
//  The welcome for someone invited to the workspace (web
//  member-onboarding/, backend docs/member-onboarding.md): a hello from the
//  business and who invited them, their steps by role — you (name as it
//  prints, photo, phone), language and alerts, where and how you work, the
//  signature adopted once, the credentials — and a done page that says what
//  was left for later. Never a wall: "Más tarde" closes it and Home offers it
//  back as reminders. Server: `/provider-member-onboarding`.
//

import SwiftUI
import PhotosUI

// MARK: - The state (GET /provider-member-onboarding)

struct HomeWelcomeState: Decodable {
    struct Step: Decodable, Hashable { let id: String; let done: Bool?; let skipped: Bool? }
    struct Welcome: Decodable {
        let businessName: String?
        let logoUrl: String?
        let categories: [String]?
        let country: String?
        let invitedByName: String?
        let role: String?
    }
    struct Profile: Decodable {
        let displayName: String?
        let accountName: String?
        let professionalTitle: String?
        let email: String?
        let phone: String?
        let photoUrl: String?
    }
    struct Preferences: Decodable { let language: String?; let languageChosen: Bool? }
    struct Place: Decodable, Identifiable { let id: String; let name: String?; let isPrimary: Bool? }
    struct Work: Decodable {
        let role: String?
        let permissions: [String]?
        let locations: [Place]?
        let everyLocation: Bool?
        let locationCount: Int?
    }
    struct Adoption: Decodable { let termsVersion: String?; let acceptedAt: String?; let current: Bool? }
    struct Signature: Decodable {
        let needed: Bool?
        let saved: SignatureMark?
        let adoption: Adoption?
        let adopted: Bool?
    }
    struct Credential: Decodable, Identifiable {
        struct Label: Decodable { let es: String?; let en: String? }
        let id: String
        let type: String
        let label: Label?
        let number: String?
        let region: String?
        let issuer: String?
        let title: String?
        let expiresOn: String?
        let status: String?
        let verified: Bool?
    }
    struct Credentials: Decodable {
        let kind: String?
        let country: String?
        let required: String?
        let offered: [String]?
        let businessAddress: String?
        let canPrescribe: Bool?
        let items: [Credential]?
    }

    let applicable: Bool?
    let show: Bool?
    let status: String?
    let joinedBefore: Bool?
    let steps: [Step]?
    let currentStep: String?
    let welcome: Welcome?
    let profile: Profile?
    let preferences: Preferences?
    let work: Work?
    let signature: Signature?
    let credentials: Credentials?
    let reminders: [HomeMemberReminder]?

    var stepIds: [String] { (steps ?? []).map(\.id) }
    var businessName: String { welcome?.businessName ?? Workspace.shared.current?.name ?? "PawMiaw" }

    /// Hi to the person, not to their title: the account's first name.
    var firstName: String {
        let name = profile?.accountName?.nonEmpty ?? profile?.displayName ?? ""
        return name.split(separator: " ").first.map(String.init) ?? ""
    }

    /// The name a document prints: what they typed, else the account's.
    static func printedName(_ typed: String, _ account: String?) -> String {
        let clean = typed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return clean.isEmpty ? (account ?? "").trimmingCharacters(in: .whitespaces) : clean
    }
}

/// The welcome's words and rules (web lib/member-onboarding.ts).
enum HomeWelcomeText {
    static func stepLabel(_ step: String) -> String {
        switch step {
        case "profile": L("You")
        case "preferences": L("Alerts")
        case "work": L("Your role")
        case "signature": L("Signature")
        default: L("Credentials")
        }
    }

    static func stepPromise(_ step: String) -> String {
        switch step {
        case "profile": L("Your name as it prints, a photo and your phone")
        case "preferences": L("Your language and which alerts reach you")
        case "work": L("Your role, what it lets you do and where")
        case "signature": L("Your signature, adopted once: then signing is one tap")
        default: L("Your license and certifications")
        }
    }

    /// The web's `STEP_ICON` (Lucide).
    static func stepIcon(_ step: String) -> String {
        switch step {
        case "profile": "user-round"
        case "preferences": "bell-ring"
        case "work": "map-pin"
        case "signature": "file-pen-line"
        default: "id-card"
        }
    }

    /// The role said for the business: a groomer business's support staff are its groomers.
    static func roleLabel(_ role: String?, _ categories: [String]) -> String {
        switch role {
        case "owner": return L("Owner")
        case "admin": return L("Admin")
        case "receptionist": return L("Front desk")
        default: break
        }
        let clinic = categories.contains("vet") || categories.contains("emergency")
        if clinic { return role == "vet" ? L("Vet") : L("Vet tech / assistant") }
        if categories.contains("groomer") { return L("Groomer") }
        if categories.contains("walker") { return L("Walker") }
        if categories.contains("trainer") { return L("Trainer") }
        if categories.contains("sitter") { return L("Sitter") }
        if categories.contains("boarding") || categories.contains("daycare") { return L("Caregiver") }
        return role == "vet" ? L("Vet") : L("Support staff")
    }

    static func titlePrompt(_ role: String?, _ categories: [String], _ country: String?) -> String {
        let clinic = categories.contains("vet") || categories.contains("emergency")
        if clinic && role == "vet" { return country == "MX" ? L("e.g. Médico Veterinario Zootecnista") : L("e.g. DVM") }
        if clinic && role == "support_staff" { return country == "US" ? L("e.g. Registered Veterinary Technician") : L("e.g. Vet assistant") }
        if categories.contains("groomer") { return L("e.g. Certified groomer") }
        return L("e.g. Front desk")
    }

    /// What someone with these permissions can do, one plain line each.
    static func abilities(_ permissions: [String]) -> [(icon: String, text: String)] {
        func has(_ p: String) -> Bool { permissions.contains(p) }
        var lines: [(String, String)] = []
        if has("appointments.create") || has("appointments.view") {
            lines.append(("calendar", has("appointments.assign_anyone") ? L("See and book visits for the whole team") : has("appointments.create") ? L("See and book your visits") : L("See the day’s visits")))
        }
        if has("appointments.check_in") || has("appointments.complete") {
            lines.append(("stethoscope", has("appointments.complete") ? L("Check pets in, start and finish visits") : L("Check pets in when they arrive")))
        }
        if has("records.create") { lines.append(("note.text", has("records.approve") ? L("Write clinical notes and records") : L("Write notes for the vet to sign"))) }
        if has("records.approve") { lines.append(("signature", L("Sign records, prescriptions and discharges"))) }
        if has("clients.view") { lines.append(("pawprint.fill", has("clients.assign_anyone") ? L("See every client and their pets") : L("See your clients and their pets"))) }
        if has("billing.record_payment") { lines.append(("creditcard.fill", has("billing.apply_discount") ? L("Charge visits, take payments and give discounts") : L("Charge visits and take payments"))) }
        if has("sales.sell") { lines.append(("bag.fill", has("sales.refund") ? L("Sell at the counter and take returns") : L("Sell at the counter"))) }
        if has("stays.care") || has("stays.manage") { lines.append(("bed.double.fill", has("stays.manage") ? L("Book stays and care for the pets staying in") : L("Care for the pets staying in"))) }
        if has("hospital.care") || has("hospital.manage") { lines.append(("cross.case.fill", has("hospital.manage") ? L("Admit, treat and discharge hospital patients") : L("Give treatments and record vitals in the hospital"))) }
        if has("inventory.adjust") || has("inventory.receive") { lines.append(("shippingbox.fill", L("Receive and count stock"))) }
        if has("staff.invite") || has("staff.edit_roles") { lines.append(("person.3.fill", L("Invite people and set what they can do"))) }
        if has("workspace.edit") { lines.append(("gearshape.fill", L("Change the workspace settings"))) }
        return lines.map { (icon: $0.0, text: $0.1) }
    }

    /// What stays with someone else — so nobody looks for a button that isn't theirs.
    static func handledByOthers(_ permissions: [String]) -> [String] {
        func has(_ p: String) -> Bool { permissions.contains(p) }
        var lines: [String] = []
        if !has("records.approve") && has("records.create") { lines.append(L("Signing records and prescriptions (a vet does)")) }
        if !has("billing.record_payment") && !has("sales.sell") { lines.append(L("Taking payments")) }
        if !has("sales.refund") && has("sales.sell") { lines.append(L("Refunds")) }
        if !has("staff.invite") { lines.append(L("Inviting people")) }
        if !has("billing.manage") { lines.append(L("The plan and billing")) }
        return lines
    }

    static func credentialNoun(_ type: String?) -> String {
        switch type {
        case "cedula_profesional": L("your cédula profesional")
        case "state_license": L("your state license")
        default: L("your professional license")
        }
    }

    static func optionalWhy(_ type: String) -> String? {
        switch type {
        case "dea": L("Only to prescribe controlled substances.")
        case "state_controlled": L("Some states ask for it, besides the DEA, for controlled substances.")
        case "usda_accreditation": L("For official health certificates.")
        case "vet_tech_license": L("Your RVT, LVT or CVT and the state.")
        case "certification": L("Courses and certifications families trust. Shown on your profile.")
        case "other_license": L("The license your country issues to practise.")
        default: nil
        }
    }

    /// The categories of alerts this person's role can see (security alerts always reach them).
    static func alertCategories(_ permissions: [String]) -> [String] {
        let needs: [(String, String)] = [
            ("appointments", "notifications.appointments"),
            ("provider_follow_ups", "notifications.provider_followups"),
            ("records_documentation", "notifications.records_documentation"),
            ("billing", "notifications.billing"),
            ("client_messages", "notifications.client_messages"),
        ]
        return needs.filter { permissions.contains($0.1) }.map(\.0)
    }

    static func alertCopy(_ category: String) -> (title: String, body: String) {
        switch category {
        case "appointments": (L("Visits@alerts"), L("New bookings, arrivals, changes and no-shows."))
        case "provider_follow_ups": (L("Follow-ups"), L("Callbacks, rechecks and lab results to review."))
        case "records_documentation": (L("Records@alerts"), L("Notes waiting for a signature and missing paperwork."))
        case "billing": (L("Money@alerts"), L("Bills to send and payments due."))
        default: (L("Messages@alerts"), L("Families writing to the business."))
        }
    }
}

// MARK: - The welcome

struct HomeWelcomeScreen: View {
    let onClose: () -> Void

    @State private var state: HomeWelcomeState
    @State private var stage: Stage
    @State private var step: String
    @State private var leaving = false

    private enum Stage { case hello, steps, done }

    init(state: HomeWelcomeState, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _state = State(initialValue: state)
        _stage = State(initialValue: state.status == "new" ? .hello : (state.status == "completed" ? .done : .steps))
        _step = State(initialValue: state.currentStep ?? state.stepIds.first ?? "profile")
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Color.clear.frame(height: 0).id("top")
                        switch stage {
                        case .hello: hello
                        case .done: done
                        case .steps: stepView
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                // Every step starts at the top, not where the last one ended.
                .onChange(of: step) { _, _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
                .onChange(of: stage) { _, _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
    }

    /// The business it is for, and "Más tarde" (web: an inline line on the page, a ghost button).
    private var topBar: some View {
        HStack(spacing: 10) {
            HomeBusinessMark(name: state.businessName, logoURL: state.welcome?.logoUrl, size: 32)
            Text(state.businessName).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
            Spacer()
            if stage != .done {
                if leaving {
                    ProgressView().controlSize(.small).padding(.horizontal, 12)
                } else {
                    PMButton(L("Later"), variant: .link, size: .slim, tint: Theme.inkStrong) { later() }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Hello

    private var hello: some View {
        let categories = state.welcome?.categories ?? []
        let label = HomeWelcomeText.roleLabel(state.welcome?.role, categories)
        // Mid-sentence in Spanish the role reads in lower case ("como veterinario").
        let role = LocalizationManager.shared.currentLanguage == .spanish ? label.prefix(1).lowercased() + label.dropFirst() : label
        let minutes = state.stepIds.contains("signature") || state.stepIds.contains("credentials") ? 3 : 1
        return VStack(alignment: .leading, spacing: 18) {
            HomeBusinessMark(name: state.businessName, logoURL: state.welcome?.logoUrl, size: 96)
            Text((state.joinedBefore == true ? L("New in your workspace") : L("Welcome to the team")).uppercased())
                .font(.brandText(12, weight: .bold)).tracking(1.68).foregroundStyle(Theme.blue)
            Text(state.firstName.isEmpty ? L("Hi!") : LF("Hi, %@!", state.firstName))
                .font(.brandHeading(38, relativeTo: .largeTitle)).foregroundStyle(Theme.inkStrong)
            Text(state.joinedBefore == true
                 ? LF("%@ now has a short welcome for its team. Finish your profile once and everything you sign carries it.", state.businessName)
                 : state.welcome?.invitedByName.map { LF("%@ invited you to %@ as %@.", $0, state.businessName, String(role)) } ?? LF("You joined %@ as %@.", state.businessName, String(role)))
                .font(Theme.text(18)).foregroundStyle(Theme.inkSoft)
            HStack(spacing: 12) {
                PMButton(state.status == "new" ? L("Let’s start") : L("Pick up where I left off"), systemImage: "arrow.right") {
                    step = state.currentStep ?? state.stepIds.first ?? "profile"
                    stage = .steps
                }
                GlyphLabel(minutes <= 1 ? L("Under a minute") : LF("About %d minutes", minutes), icon: "clock")
                    .font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
            }
            Card {
                ForEach(Array((state.steps ?? []).enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { StitchedDivider() }
                    HStack(alignment: .top, spacing: 12) {
                        if entry.done == true {
                            HomeDisc(icon: "check", size: 40, iconSize: 20, fill: Theme.blueFixed, ink: .white)
                        } else {
                            IconBadge(icon: HomeWelcomeText.stepIcon(entry.id), accent: Theme.blue, size: 40, iconSize: 20, ink: .accent, washPercent: 10)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(index + 1). \(HomeWelcomeText.stepPromise(entry.id))").font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            if entry.id == "signature" { Text(L("Because your role signs records and prescriptions.")).font(Theme.captionFont).foregroundStyle(Theme.inkSoft) }
                            if entry.id == "credentials" { Text(L("All optional, except what the law asks to prescribe.")).font(Theme.captionFont).foregroundStyle(Theme.inkSoft) }
                        }
                    }
                }
            }
        }
    }

    // MARK: Done

    private var done: some View {
        let waiting = (state.reminders ?? []).filter { $0.id != "finish" }
        return VStack(spacing: 16) {
            IconBadge(icon: "party-popper", accent: Theme.lime, size: 80, iconSize: 36, ink: .strong, washPercent: 45)
            Text(state.firstName.isEmpty ? L("All set!") : LF("All set, %@!", state.firstName))
                .font(.brandHeading(34, relativeTo: .largeTitle)).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.center)
            Text(LF("Your profile at %@ is ready.", state.businessName)).font(Theme.text(17)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
            VStack(spacing: 8) {
                ForEach(state.steps ?? [], id: \.id) { entry in
                    HStack(spacing: 10) {
                        if entry.done == true {
                            HomeDisc(icon: "check", size: 28, iconSize: 16, fill: Theme.blueFixed, ink: .white)
                        } else {
                            Glyph("clock", size: 14).foregroundStyle(Theme.inkSoft)
                                .frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 2, dash: [4, 3])))
                        }
                        Text(HomeWelcomeText.stepPromise(entry.id)).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                        Spacer(minLength: 0)
                        if entry.done != true { Text(L("Later")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft) }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
            }
            .frame(maxWidth: 460)
            if !waiting.isEmpty {
                Text(L("What you left for later waits on your Home. Nothing is blocked: only signing asks for it, right there."))
                    .font(Theme.smallFont).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center).frame(maxWidth: 460)
            }
            PMButton(L("Go to my Home"), systemImage: "arrow.right") { onClose() }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: The steps

    @ViewBuilder
    private var stepView: some View {
        HomeWelcomeProgress(state: state, step: step)
        switch step {
        case "profile":
            HomeWelcomeProfileStep(state: state, onSaved: { state = $0 }, onDone: { advance("profile", "done") }, onSkip: { advance("profile", "skip") })
        case "preferences":
            HomeWelcomePreferencesStep(state: state, onDone: { await advanceAsync("preferences", "done") }, onBack: { back("preferences") }, onSkip: { advance("preferences", "skip") })
        case "work":
            HomeWelcomeWorkStep(state: state, onDone: { await advanceAsync("work", "done") }, onBack: { back("work") })
        case "signature":
            HomeWelcomeSignatureStep(state: state, onDone: { await advanceAsync("signature", "done") }, onBack: { back("signature") }, onSkip: { advance("signature", "skip") })
        default:
            HomeWelcomeCredentialsStep(state: state, last: nextStep(after: "credentials") == nil, onReload: { await reload() }, onDone: { await advanceAsync("credentials", "done") }, onBack: { back("credentials") }, onSkip: { advance("credentials", "skip") })
        }
    }

    private func nextStep(after current: String) -> String? {
        let ids = state.stepIds
        guard let index = ids.firstIndex(of: current), index + 1 < ids.count else { return nil }
        return ids[index + 1]
    }

    private func back(_ current: String) {
        let ids = state.stepIds
        if let index = ids.firstIndex(of: current), index > 0 { step = ids[index - 1] } else { stage = .hello }
    }

    private func advance(_ from: String, _ action: String) {
        Task { await advanceAsync(from, action) }
    }

    /// Marks the step (the profile's save marks it itself), then the next one, or the done page.
    private func advanceAsync(_ from: String, _ action: String) async {
        do {
            if action == "skip" || from != "profile" {
                state = try await API.post("/provider-member-onboarding/steps/\(from)", body: ["action": action])
            }
            if let next = nextStep(after: from) {
                step = next
                return
            }
            state = try await API.post("/provider-member-onboarding/finish", body: [:])
            stage = .done
            announceDataChanged()
        } catch {
            Toast.error(errorText(error, fallback: L("Could not save this step.")))
        }
    }

    private func reload() async {
        if let fresh: HomeWelcomeState = try? await API.get("/provider-member-onboarding"), fresh.applicable == true { state = fresh }
    }

    private func later() {
        leaving = true
        Task {
            defer { leaving = false }
            do {
                let _: EmptyResponse = try await API.post("/provider-member-onboarding/dismiss", body: [:])
                announceDataChanged()
                onClose()
            } catch {
                Toast.error(errorText(error, fallback: L("Could not save. Try again.")))
            }
        }
    }
}

/// The business the person joined: its logo, or its initials (web `BusinessMark`: a tile, 32 / 48 / 96, chip / box / card corners).
struct HomeBusinessMark: View {
    let name: String
    let logoURL: String?
    var size: CGFloat = 48

    private var radius: CGFloat { size >= 96 ? Theme.cardRadius : (size >= 48 ? Theme.boxRadius : Theme.chipRadius) }

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap { $0.first.map { String($0).uppercased() } }.joined()
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(Theme.surface)
            if let url = APIConfig.assetURL(logoURL) {
                AsyncImage(url: url) { image in image.resizable().scaledToFit().padding(4) } placeholder: { Color.clear }
            } else {
                Text(initials.isEmpty ? "P" : initials).font(.brandHeading(size >= 96 ? 30 : (size >= 48 ? 16 : 12), relativeTo: .headline)).foregroundStyle(Theme.blue)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.borderSoft, lineWidth: 1))
        .cardShadow()
    }
}

/// One pip per step the person gets, done ones ticked (web `MemberProgress`).
private struct HomeWelcomeProgress: View {
    let state: HomeWelcomeState
    let step: String

    var body: some View {
        let steps = state.steps ?? []
        let active = steps.firstIndex { $0.id == step } ?? 0
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, entry in
                let current = index == active
                let done = entry.done == true && !current
                VStack(spacing: 6) {
                    ZStack {
                        Circle().fill(current || done ? Theme.blueFixed : (entry.skipped == true ? Color.clear : Theme.surfaceMuted))
                        if entry.skipped == true && !done && !current {
                            Circle().strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        }
                        if done {
                            Glyph("check", size: 16).foregroundStyle(.white)
                        } else {
                            Text("\(index + 1)").font(Theme.text(12, weight: .bold)).foregroundStyle(current ? .white : Theme.inkSoft)
                        }
                    }
                    .frame(width: 28, height: 28)
                    Text(HomeWelcomeText.stepLabel(entry.id)).font(Theme.text(11.2, weight: .bold)).foregroundStyle(current ? Theme.inkStrong : Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.8)
                    Rectangle().fill(index <= active || entry.done == true ? Theme.blue : Theme.borderSoft).frame(height: 2).padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LF("Step %d of %d", active + 1, steps.count))
    }
}

/// A step's frame: "Paso N de M", its title and why, the questions, and Back / For later / Next.
struct HomeWelcomeStepFrame<Content: View, Aside: View>: View {
    let state: HomeWelcomeState
    let step: String
    let title: String
    let description: String
    let nextLabel: String
    var busy: Bool = false
    var nextDisabled: Bool = false
    var note: String? = nil
    let onNext: () -> Void
    var onBack: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @ViewBuilder let aside: () -> Aside

    var body: some View {
        let ids = state.stepIds
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(LF("Step %d of %d", (ids.firstIndex(of: step) ?? 0) + 1, ids.count).uppercased())
                    .font(.brandText(12, weight: .bold)).tracking(1.68).foregroundStyle(Theme.blue)
                Text(title).font(.brandHeading(30, relativeTo: .largeTitle)).foregroundStyle(Theme.inkStrong)
                Text(description).font(Theme.text(16)).foregroundStyle(Theme.inkSoft)
            }
            content()
            aside()
            HStack(spacing: 8) {
                if let onBack {
                    PMButton(L("Back"), systemImage: "arrow.left", variant: .outline, size: .compact, action: onBack).disabled(busy)
                }
                Spacer(minLength: 0)
                if let onSkip {
                    PMButton(L("For later"), variant: .link, size: .slim, tint: Theme.inkStrong, action: onSkip).disabled(busy)
                }
                PMButton(busy ? L("Saving…") : nextLabel, systemImage: busy ? nil : "arrow.right", size: .compact, isWorking: busy, action: onNext)
                    .disabled(nextDisabled)
            }
            if let note { Text(note).font(Theme.smallFont).foregroundStyle(Theme.inkSoft) }
        }
    }
}

extension HomeWelcomeStepFrame where Aside == EmptyView {
    init(state: HomeWelcomeState, step: String, title: String, description: String, nextLabel: String, busy: Bool = false, nextDisabled: Bool = false, note: String? = nil, onNext: @escaping () -> Void, onBack: (() -> Void)? = nil, onSkip: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(state: state, step: step, title: title, description: description, nextLabel: nextLabel, busy: busy, nextDisabled: nextDisabled, note: note, onNext: onNext, onBack: onBack, onSkip: onSkip, content: content, aside: { EmptyView() })
    }
}

/// A titled block inside a step (the web's SetupBlock).
struct HomeWelcomeBlock<Content: View>: View {
    let systemImage: String
    let title: String
    var hint: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        Card {
            HStack(spacing: 10) {
                IconBadge(icon: systemImage, accent: Theme.blue, size: 32, iconSize: 16, ink: .accent, washPercent: 10)
                Text(title).font(Theme.sectionFont).foregroundStyle(Theme.inkStrong)
            }
            if let hint { Text(hint).font(Theme.smallFont).foregroundStyle(Theme.inkSoft) }
            content()
        }
    }
}

// MARK: - 1. You

private struct HomeWelcomeProfileStep: View {
    let state: HomeWelcomeState
    let onSaved: (HomeWelcomeState) -> Void
    let onDone: () -> Void
    let onSkip: () -> Void

    @StateObject private var form = FormState()
    @State private var name = ""
    @State private var title = ""
    @State private var phone = ""
    @State private var photo = PhotoDraft()
    @State private var uploading = false
    @State private var saving = false
    @State private var started = false

    private struct Uploaded: Decodable { let photoUrl: String? }
    @State private var photoURL: String?

    var body: some View {
        let categories = state.welcome?.categories ?? []
        let role = HomeWelcomeText.roleLabel(state.welcome?.role, categories)
        let shown = HomeWelcomeState.printedName(name, state.profile?.accountName)
        HomeWelcomeStepFrame(state: state, step: "profile", title: L("You, on the team"),
                             description: L("How your name prints on prescriptions, receipts and reports, and a photo so the team and families recognise you."),
                             nextLabel: L("Save and continue"), busy: saving, onNext: save, onSkip: onSkip) {
            FormScroll(form: form) {
                VStack(alignment: .leading, spacing: 16) {
                    HomeWelcomeBlock(systemImage: "person.fill", title: L("Photo and name")) {
                        // The photo goes up as soon as it is chosen (the welcome saves it on its own).
                        PhotoField(label: L("Photo"), hint: L("Optional. JPG, PNG or WebP up to 3 MB."), currentURL: photoURL ?? state.profile?.photoUrl, draft: $photo, shape: .circle, allowsRemove: false)
                            .disabled(uploading)
                        PMTextField(L("Name as it prints on documents"), text: $name, key: "name", form: form, hint: L("With your title if you use one, the way you sign."), capitalization: .words, required: true)
                        PMTextField(L("Title"), text: $title, prompt: HomeWelcomeText.titlePrompt(state.welcome?.role, categories, state.welcome?.country), hint: L("Optional. Printed under your name."), optional: true)
                    }
                    HomeWelcomeBlock(systemImage: "phone.fill", title: L("Phone"), hint: L("So the team can reach you. It is your account’s number.")) {
                        PMTextField(L("Mobile phone"), text: $phone, key: "phone", form: form, keyboard: .phonePad, optional: true)
                    }
                    // How it prints: the line under a signature.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("How it prints").uppercased()).font(.brandText(10, weight: .heavy)).tracking(1.4).foregroundStyle(Theme.inkSoft)
                        Rectangle().fill(Theme.borderSoft).frame(height: 1).padding(.top, 22)
                        Text(shown.isEmpty ? "—" : shown).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Text(title.nonEmpty ?? role).font(Theme.smallFont).foregroundStyle(Theme.inkSoft).lineLimit(1)
                        Text(state.businessName).font(Theme.captionFont).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.borderSoft, lineWidth: 1))
                    .accessibilityLabel(L("How your name prints"))
                }
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            name = state.profile?.displayName ?? state.profile?.accountName ?? ""
            title = state.profile?.professionalTitle ?? ""
            phone = state.profile?.phone ?? ""
        }
        .onChange(of: photo.data) { _, data in
            guard let data else { return }
            Task { await upload(data) }
        }
    }

    private func upload(_ data: Data) async {
        uploading = true
        defer { uploading = false; photo = PhotoDraft() }
        do {
            let result: Uploaded = try await ImageUpload.upload(data, to: "/provider-member-onboarding/photo")
            photoURL = result.photoUrl
            announceDataChanged()
        } catch {
            Toast.error(errorText(error, fallback: L("Could not upload the photo.")))
        }
    }

    private func save() {
        let clean = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let digits = phone.filter(\.isNumber)
        guard form.check([
            ("name", clean.count < 2 ? L("Type your name as it should print.") : nil),
            ("phone", !phone.trimmingCharacters(in: .whitespaces).isEmpty && digits.count < 10 ? L("Finish the phone number, or leave it empty.") : nil),
        ]) else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let next: HomeWelcomeState = try await API.put("/provider-member-onboarding/profile", body: ["displayName": clean, "professionalTitle": title.nonEmpty, "phone": phone.nonEmpty])
                onSaved(next)
                announceDataChanged()
                onDone()
            } catch {
                form.apply(error, known: ["displayName": "name", "phone": "phone"])
            }
        }
    }
}

// MARK: - 2. Language and alerts

private struct HomeWelcomePreferencesStep: View {
    let state: HomeWelcomeState
    let onDone: () async -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    @EnvironmentObject private var workspace: Workspace
    @State private var language = "es"
    @State private var channels: [String: (inApp: Bool, email: Bool)] = [:]
    @State private var saved: [String: TeamNotificationPreference] = [:]
    @State private var timezone: String?
    @State private var loaded = false
    @State private var busy = false
    @State private var started = false

    private var categories: [String] { HomeWelcomeText.alertCategories(state.work?.permissions ?? []) }

    var body: some View {
        HomeWelcomeStepFrame(state: state, step: "preferences", title: L("Language and alerts"),
                             description: L("Choose the language you work in and which alerts from this workspace reach you. You can change both any time in Settings."),
                             nextLabel: L("Save and continue"), busy: busy, onNext: save, onBack: onBack, onSkip: onSkip) {
            HomeWelcomeBlock(systemImage: "character.bubble.fill", title: L("Your language"), hint: L("For the app and the emails PawMiaw sends you. Families keep their own.")) {
                ChoiceCards(options: [("es", "Español", L("México y Latinoamérica")), ("en", "English", L("United States"))], selection: $language)
            }
            HomeWelcomeBlock(systemImage: "bell.fill", title: L("Alerts from this workspace"), hint: L("Only what your role handles. Security alerts always reach you.")) {
                if !loaded {
                    ProgressView().frame(maxWidth: .infinity)
                } else if categories.isEmpty {
                    Text(L("Your role gets no workspace alerts yet. Security alerts always reach you.")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                } else {
                    ForEach(categories, id: \.self) { category in
                        let copy = HomeWelcomeText.alertCopy(category)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(copy.title).font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            Text(copy.body).font(Theme.text(13)).foregroundStyle(Theme.inkSoft)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                                ToggleRow(title: L("In app"), isOn: binding(category, email: false))
                                ToggleRow(title: L("Email"), isOn: binding(category, email: true))
                            }
                        }
                        if category != categories.last { StitchedDivider() }
                    }
                }
            }
            // This device's push: shown, marked, not built yet (as on the web).
            HStack(alignment: .top, spacing: 12) {
                HomeDisc(icon: "smartphone", size: 40, iconSize: 20, fill: Theme.surface, ink: Theme.inkSoft)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(L("This device")).font(Theme.sectionFont).foregroundStyle(Theme.inkStrong)
                        HueChip(text: L("Coming soon"), hue: .grey, systemImage: "bell")
                    }
                    Text(L("Push notifications on this computer or phone. For now alerts arrive in the app and by email.")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.borderSoft, style: StrokeStyle(lineWidth: 1.5, dash: [5])))
        }
        .task {
            guard !started else { return }
            started = true
            language = state.preferences?.language ?? LocalizationManager.shared.currentLanguage.rawValue
            await load()
        }
    }

    private func binding(_ category: String, email: Bool) -> Binding<Bool> {
        Binding(
            get: { email ? (channels[category]?.email ?? false) : (channels[category]?.inApp ?? true) },
            set: { value in
                var current = channels[category] ?? (inApp: true, email: false)
                if email { current.email = value } else { current.inApp = value }
                channels[category] = current
            }
        )
    }

    private func load() async {
        defer { loaded = true }
        guard let clinicId = workspace.current?.clinicId else { return }
        let answer: TeamNotificationPreferences? = try? await API.get("/notification-preferences", query: ["contextType": "provider_workspace", "contextId": clinicId])
        let items = answer?.items ?? []
        saved = Dictionary(items.map { ($0.category, $0) }, uniquingKeysWith: { first, _ in first })
        timezone = items.first?.timezone
        for category in categories {
            let item = saved[category]
            channels[category] = (item?.inAppEnabled ?? true, item?.emailEnabled ?? (category == "appointments" || category == "provider_follow_ups"))
        }
    }

    private func save() {
        guard let clinicId = workspace.current?.clinicId else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                if !categories.isEmpty {
                    let rows: [[String: Any]] = categories.map { category in
                        let item = saved[category]
                        let chosen = channels[category] ?? (inApp: true, email: false)
                        let leads = item?.reminderLeadTimes ?? []
                        return ["category": category, "inAppEnabled": chosen.inApp, "emailEnabled": chosen.email, "pushEnabled": item?.pushEnabled ?? true, "smsEnabled": false, "reminderLeadTimes": leads.isEmpty ? [24 * 60, 0] : leads]
                    }
                    let _: EmptyResponse = try await API.put("/notification-preferences", body: [
                        "contextType": "provider_workspace", "contextId": clinicId,
                        "timezone": timezone ?? TimeZone.current.identifier, "categories": rows,
                    ])
                }
                if state.preferences?.languageChosen != true || state.preferences?.language != language {
                    let _: EmptyResponse = try await API.patch("/users/me/preferences", body: ["preferredLanguage": language])
                }
                // Saved before the language changes: the welcome picks up at the next step.
                await onDone()
                if let chosen = AppLanguage(rawValue: language), chosen != LocalizationManager.shared.currentLanguage {
                    LocalizationManager.shared.setLanguage(chosen)
                }
            } catch {
                Toast.error(errorText(error, fallback: L("Could not save this step.")))
            }
        }
    }
}

// MARK: - 3. Where and how you work

private struct HomeWelcomeWorkStep: View {
    let state: HomeWelcomeState
    let onDone: () async -> Void
    let onBack: () -> Void
    @State private var busy = false

    var body: some View {
        let permissions = state.work?.permissions ?? []
        let can = HomeWelcomeText.abilities(permissions)
        let others = HomeWelcomeText.handledByOthers(permissions)
        let role = HomeWelcomeText.roleLabel(state.work?.role ?? state.welcome?.role, state.welcome?.categories ?? [])
        let places = state.work?.locations ?? []
        let count = state.work?.locationCount ?? places.count
        HomeWelcomeStepFrame(state: state, step: "work", title: L("Where and how you work"),
                             description: LF("What your role at %@ lets you do. Nothing to fill in: just check it looks right.", state.businessName),
                             nextLabel: L("Looks right"), busy: busy,
                             note: state.welcome?.invitedByName.map { LF("Something off? Ask %@ to change it on the Staff page.", $0) } ?? L("Something off? Ask the owner to change it on the Staff page."),
                             onNext: { busy = true; Task { await onDone(); busy = false } }, onBack: onBack) {
            HStack(spacing: 14) {
                Glyph("user-cog", size: 24).foregroundStyle(.white)
                    .frame(width: 56, height: 56).background(Theme.blueFixed, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Your role").uppercased()).font(.brandText(11, weight: .heavy)).tracking(1.2).foregroundStyle(Theme.inkSoft)
                    Text(role).font(.brandHeading(24, relativeTo: .title2)).foregroundStyle(Theme.inkStrong)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProviderState.done.wash, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            HomeWelcomeBlock(systemImage: "checkmark.seal.fill", title: L("What you can do")) {
                if can.isEmpty {
                    Text(L("Your role can’t do anything yet. Ask the owner to give it permissions.")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 8)], spacing: 8) {
                        ForEach(can, id: \.text) { line in
                            HStack(alignment: .top, spacing: 10) {
                                HomeDisc(icon: line.icon, size: 28, iconSize: 14, fill: Theme.surface, ink: Theme.blue)
                                Text(line.text).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                        }
                    }
                }
                if !others.isEmpty {
                    Text(L("Someone else handles").uppercased()).font(.brandText(11, weight: .heavy)).tracking(1.2).foregroundStyle(Theme.inkSoft).padding(.top, 6)
                    Text(others.joined(separator: " · ")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                }
            }
            HomeWelcomeBlock(systemImage: "mappin.and.ellipse", title: L("Where you work")) {
                if state.work?.everyLocation == true {
                    GlyphLabel(count > 1 ? LF("Every location (%d)", count) : LF("At %@", places.first?.name ?? state.businessName), icon: "check")
                        .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                }
                if state.work?.everyLocation != true || count > 1 {
                    FlowLayout(spacing: 8) {
                        ForEach(places) { place in
                            HueChip(text: (place.name ?? "—") + (place.isPrimary == true ? " · " + L("main") : ""), hue: .grey, systemImage: "mappin")
                        }
                    }
                }
                if state.work?.everyLocation != true {
                    Text(L("You see the visits, bills and stays of these locations.")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }
}
