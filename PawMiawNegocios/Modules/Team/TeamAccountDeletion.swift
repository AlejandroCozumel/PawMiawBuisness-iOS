//
//  TeamAccountDeletion.swift
//  PawMiawNegocios
//
//  Deleting the account, start to finish, as the business workspace draws it
//  (web: components/app/account-deletion-panel.tsx, account-deletion-
//  households.ts; hooks/use-account-deletion.ts; backend
//  routes/account-deletion.ts): what it would remove, what happens to each
//  household another adult could keep and to each pet a Familia could take,
//  the word typed before the code is emailed, the code, the box ticked, and
//  scheduling it. A deletion already scheduled is said in the card's place,
//  with the way to cancel it. Once scheduled the person stays signed in, as
//  on the web, and sees the pending deletion with its Cancel.
//

import SwiftUI

// MARK: - Shapes

struct TeamDeletionHousehold: Decodable, Identifiable, Hashable {
    struct Person: Decodable, Hashable { let name: String?; let role: String? }
    struct Successor: Decodable, Hashable { let userId: String; let name: String? }
    let id: String
    let name: String?
    let memberCount: Int?
    let petCount: Int?
    let recordCount: Int?
    let fileCount: Int?
    let members: [Person]?
    let successors: [Successor]?
}

struct TeamDeletionPetTransfer: Decodable, Hashable {
    struct Candidate: Decodable, Hashable { let userId: String; let name: String?; let email: String? }
    let petId: String
    let petName: String?
    let candidates: [Candidate]?
}

struct TeamDeletionImpact: Decodable {
    struct Named: Decodable, Hashable { let id: String?; let name: String?; let role: String? }
    let userId: String?
    let email: String?
    let displayName: String?
    let ownedHouseholds: [TeamDeletionHousehold]?
    let joinedHouseholds: [Named]?
    let providerWorkspaces: [Named]?
    let hasAppleAccount: Bool?
    let requiresAppleReauthorization: Bool?
    let hasActiveAppleSubscription: Bool?
    let hasActiveWebSubscription: Bool?
    let gracePeriodHours: Int?
    let petTransfers: [TeamDeletionPetTransfer]?
    let transferHoldEndsAt: String?
}

struct TeamDeletionStatus: Decodable {
    struct Snapshot: Decodable { let ownedHouseholds: [TeamDeletionHousehold]? }
    struct Handover: Decodable, Hashable { let householdId: String; let householdName: String?; let toUserId: String?; let toName: String? }
    /// none, pending, executing, completed, cancelled or failed.
    let status: String?
    let stage: String?
    let requestedAt: String?
    let scheduledFor: String?
    let impact: Snapshot?
    let handover: [Handover]?
}

// MARK: - Words

enum TeamDeletionWords {
    /// The answer "delete it for everyone", beside the ids of the adults who could keep it.
    static let deleteForEveryone = "delete-for-everyone"
    /// A pet not given to anyone closes with its household.
    static let keepNoOne = "keep-no-one"

    /// The word typed before the code is emailed: "ELIMINAR", "DELETE". The server takes either.
    static var word: String { L("DELETE") }

    /// A household's name as the reader sees it: the server's own English names read in Spanish.
    static func household(_ name: String?) -> String {
        let name = name ?? ""
        guard LocalizationManager.shared.currentLanguage == .spanish else { return name }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased() == "my household" { return "Mi hogar" }
        if let match = trimmed.wholeMatch(of: #/(?i)(.+?)(?:['’]s|['’]) household/#) {
            let owner = String(match.output.1).trimmingCharacters(in: .whitespaces)
            if !owner.isEmpty { return "Hogar de \(owner)" }
        }
        return name
    }

    /// "Carmen", "Carmen y Luis", "Ana, Luis y 3 personas más".
    static func people(_ names: [String]) -> String {
        let shown = names.count > 3 ? Array(names.prefix(2)) + [LF("%d more people", names.count - 2)] : names
        let formatter = ListFormatter()
        formatter.locale = .app
        return formatter.string(from: shown) ?? shown.joined(separator: ", ")
    }

    /// Who loses a household that is deleted for everyone, by name.
    static func accessLoss(_ household: TeamDeletionHousehold) -> String {
        let names = (household.members ?? []).compactMap { $0.name?.nonEmpty }
        if names.isEmpty { return L("Nobody else has access to this household.") }
        return names.count == 1
            ? LF("%1$@ loses access to %2$@.", people(names), self.household(household.name))
            : LF("%1$@ lose access to %2$@.", people(names), self.household(household.name))
    }

    /// What was decided for a household, in a line; nil while it is still to be chosen.
    static func outcome(_ household: TeamDeletionHousehold, _ answer: String?) -> String? {
        if let successor = household.successors?.first(where: { $0.userId == answer }) {
            return LF("%1$@ goes to %2$@", self.household(household.name), successor.name ?? "")
        }
        if !(household.successors ?? []).isEmpty && answer != deleteForEveryone { return nil }
        return LF("%@ is deleted for everyone", self.household(household.name))
    }

    /// What a scheduled deletion will do to each household its owner has.
    static func scheduledOutcomes(_ status: TeamDeletionStatus?) -> [String] {
        let handover = status?.handover ?? []
        return (status?.impact?.ownedHouseholds ?? []).map { household in
            if let plan = handover.first(where: { $0.householdId == household.id }) {
                return LF("%1$@ will go to %2$@.", self.household(household.name), plan.toName ?? "")
            }
            return LF("%@ will be deleted for everyone.", self.household(household.name))
        }
    }

    static func summary(_ graceHours: Int?) -> String {
        let first = L("Schedule permanent deletion of your account. The households you own are deleted with it, unless you leave one to another adult.")
        if let graceHours {
            return "\(first) \(L("You have")) \(graceHours) \(L("hours to cancel from PawMiaw or the security email."))"
        }
        return "\(first) \(L("You can cancel from PawMiaw or the security email during the cancellation window."))"
    }

    static func scheduledSummary(_ scheduledFor: String?, executing: Bool) -> String {
        if executing { return L("Deletion has started and can no longer be cancelled.") }
        if let date = DateText.parse(scheduledFor) {
            let formatter = DateFormatter()
            formatter.locale = .app
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            return "\(L("Your account remains frozen until permanent deletion on")) \(formatter.string(from: date))."
        }
        return L("Your account is frozen during the cancellation period.")
    }

    static func counts(_ household: TeamDeletionHousehold) -> String {
        [
            LP(household.petCount ?? 0, "%d pet", "%d pets"),
            LP(household.memberCount ?? 0, "%d member", "%d members"),
            LP(household.recordCount ?? 0, "%d record", "%d records"),
        ].joined(separator: ", ")
    }
}

// MARK: - The panel

/// The business workspace's picture of deleting the account: a panel that opens its review.
struct TeamAccountDeletionPanel: View {
    @EnvironmentObject private var session: SessionStore
    @State private var status: TeamDeletionStatus?
    @State private var statusLoaded = false
    @State private var expanded = false
    @State private var impact: TeamDeletionImpact?
    @State private var impactLoading = false
    @State private var impactFailed = false
    @State private var gateOpen = false
    @State private var codeSent = false
    @State private var code = ""
    @State private var acknowledged = false
    @State private var householdAnswers: [String: String] = [:]
    @State private var householdErrors: [String: String] = [:]
    @State private var petAnswers: [String: String] = [:]
    @State private var sending = false
    @State private var scheduling = false
    @State private var cancelling = false

    private var isPending: Bool { status?.status == "pending" }
    private var isExecuting: Bool { status?.status == "executing" || status?.status == "failed" }
    private var graceHours: Int? { impact?.gracePeriodHours }
    private var appleBlocks: Bool { impact?.requiresAppleReauthorization == true }
    private var canSubmit: Bool { code.count == 6 && codeSent && acknowledged && !appleBlocks }

    var body: some View {
        Group {
            if !statusLoaded {
                TeamPanel(title: L("Delete account"), systemImage: "trash-2", tint: Theme.coral) {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 100)
                }
            } else if isPending || isExecuting {
                pending
            } else {
                panel
            }
        }
        .task { await loadStatus() }
        .sheet(isPresented: $gateOpen) {
            // The typed word that stands before the code is emailed (web `AccountDeletionSendGate`):
            // the coral band with the bin, where the code goes and the time to cancel, the word to type.
            let email = impact?.email ?? session.user?.email ?? ""
            ConfirmSheet(
                title: L("Confirm before we email the code"),
                message: LF("Type %@ to receive the deletion code. Nothing is deleted yet — you still confirm on the next step.", TeamDeletionWords.word),
                confirmTitle: L("Email verification code"),
                destructive: true,
                accent: .coral,
                icon: "trash-2",
                confirmWord: TeamDeletionWords.word,
                confirmHint: ([email.nonEmpty.map { "\(L("Code goes to")): \($0)" }] + [graceHours.map { "\(L("Time to cancel")): \($0) \(L("hours"))" }]).compactMap { $0 }.joined(separator: " · ").nonEmpty
            ) { _ in
                try await sendCode(first: true)
            }
        }
    }

    // MARK: Scheduled

    private var pending: some View {
        let outcomes = TeamDeletionWords.scheduledOutcomes(status)
        return TeamPanel(title: isExecuting ? L("Permanent deletion is in progress") : L("Account deletion scheduled"),
                         subtitle: TeamDeletionWords.scheduledSummary(status?.scheduledFor, executing: isExecuting),
                         systemImage: "clock-3", tint: Theme.coral) {
            if !isExecuting {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(outcomes, id: \.self) { line in Text(line).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                }
                PMButton(L("Cancel account deletion"), isWorking: cancelling) { cancelDeletion() }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.coral, lineWidth: 2))
    }

    // MARK: Not scheduled

    private var panel: some View {
        TeamPanel(title: L("Delete account"), subtitle: TeamDeletionWords.summary(graceHours), systemImage: "trash-2", tint: Theme.coral) {
            if expanded {
                Text((codeSent ? L("Step 2 of 2 · Confirm with the code we emailed you") : L("Step 1 of 2 · Review what permanent deletion removes")).uppercased())
                    .font(Theme.text(12, weight: .bold)).tracking(0.6).foregroundStyle(Theme.destructive)
                VStack(alignment: .leading, spacing: 16) { steps }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            } else {
                PMButton(L("Review account deletion"), systemImage: "trash-2", variant: .destructive) {
                    expanded = true
                    Task { await loadImpact() }
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.mix(Theme.coral, 58, with: Theme.borderSoft), lineWidth: 2))
    }

    @ViewBuilder
    private var steps: some View {
        if impactLoading && impact == nil {
            HStack(spacing: 8) {
                ProgressView()
                Text(L("Calculating everything affected by deletion…")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
        } else if let impact {
            boundary(impact)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Paid access is stopped according to the store or billing provider. Deleting your account does not create an automatic or prorated refund."))
                if impact.hasActiveAppleSubscription == true {
                    Text(L("Apple subscriptions remain managed in App Store Subscriptions and may need to be cancelled there."))
                }
            }
            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            if appleBlocks {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Sign in with Apple again so PawMiaw can revoke your Apple authorization when deletion completes.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    // Not ported: Sign in with Apple isn't set up in this app; the web asks for it and finishes the deletion there.
                    TeamWebRow(title: L("Continue with Apple"), detail: L("Opens on the web."), systemImage: "apple.logo", url: TeamWeb.url("provider/account/security"))
                }
                .padding(16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 2))
            }
            if !codeSent {
                PMButton(L("Email verification code"), systemImage: "mail", variant: .destructive, isWorking: sending) { openGate() }
                    .disabled(sending || appleBlocks)
            } else {
                codeStep(impact)
            }
        } else if impactFailed {
            Text(L("Deletion impact could not be loaded.")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.destructive)
            PMButton(L("Try again"), variant: .outline, size: .compact) { Task { await loadImpact() } }
        }
    }

    private func boundary(_ impact: TeamDeletionImpact) -> some View {
        let owned = impact.ownedHouseholds ?? []
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Glyph("triangle-alert", size: 16).foregroundStyle(Theme.coral)
                Text(L("This is the permanent deletion boundary"))
            }
            .font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
            if owned.isEmpty {
                Text(L("You do not own a household.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            } else {
                ForEach(owned) { household in
                    VStack(alignment: .leading, spacing: 8) {
                        (Text(TeamDeletionWords.household(household.name)).bold().foregroundColor(Theme.inkStrong) + Text(" — " + TeamDeletionWords.counts(household)))
                            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        fate(household)
                    }
                    .id("household-\(household.id)")
                }
            }
            if !(impact.petTransfers ?? []).isEmpty { petTransfers(impact) }
            if !(impact.joinedHouseholds ?? []).isEmpty {
                TeamIconLine(icon: "users", tint: Theme.blue, text: L("Households you only joined will remain. Your membership and personal content will be removed."))
            }
            if !(impact.providerWorkspaces ?? []).isEmpty {
                TeamIconLine(icon: "users", tint: Theme.blue, text: L("Provider workspace records remain business-owned. Your personal profile and staff membership will be removed."))
            }
            TeamIconLine(icon: "clock-3", tint: Theme.coral, text: "\(L("Permanent deletion begins after")) \(impact.gracePeriodHours ?? 0) \(L("hours. Until then, your account is frozen and you can cancel from the app or the security email."))")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.coral, lineWidth: 2))
    }

    /// What happens to one household the person owns: theirs to decide when another adult has full access.
    @ViewBuilder
    private func fate(_ household: TeamDeletionHousehold) -> some View {
        let name = TeamDeletionWords.household(household.name)
        let successors = household.successors ?? []
        if !successors.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(LF("What happens to %@?", name), caps: true, required: true)
                ChoiceCards(
                    options: successors.map { person in
                        (person.userId, LF("Leave %1$@ to %2$@", name, person.name ?? ""), LF("%@ becomes its owner. The household keeps its pets, records and members, and moves to the free plan: Premium is yours and does not transfer.", person.name ?? ""))
                    } + [(TeamDeletionWords.deleteForEveryone, LF("Delete %@ for everyone", name), TeamDeletionWords.accessLoss(household))],
                    selection: Binding(get: { householdAnswers[household.id] ?? "" }, set: { value in
                        householdAnswers[household.id] = value
                        householdErrors[household.id] = nil
                    })
                )
                .disabled(scheduling)
                if let error = householdErrors[household.id] {
                    Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(LF("%@ is deleted for everyone.", name) + " " + TeamDeletionWords.accessLoss(household)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                if !(household.members ?? []).isEmpty {
                    Text(L("To leave it to someone, that person needs full access to the household.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    /// "Dar a Luna a Tomás": who gets each pet a Familia could keep, or nobody.
    private func petTransfers(_ impact: TeamDeletionImpact) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RowDivider()
            Text(L("Give a pet to someone who will keep it")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
            Text(L("They are told at once and have until the deletion runs to accept. A pet nobody accepts closes with the household.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            ForEach(impact.petTransfers ?? [], id: \.petId) { pet in
                let petName = pet.petName ?? L("a pet")
                Text(LF("What happens to %@?", petName)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                ChoiceCards(
                    options: (pet.candidates ?? []).map { person in
                        (person.userId, LF("Give %1$@ to %2$@", petName, person.name ?? ""), LF("%1$@ moves to %2$@’s family with all of the history, once %3$@ accepts.", petName, person.name ?? "", person.email ?? ""))
                    } + [(TeamDeletionWords.keepNoOne, LF("Do not give %@", petName), LF("%@ closes with the household.", petName))],
                    selection: Binding(get: { petAnswers[pet.petId] ?? "" }, set: { petAnswers[pet.petId] = $0 })
                )
                .disabled(scheduling)
            }
            ForEach(holdLines(impact), id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Glyph("clock-3", size: 16).foregroundStyle(Theme.coral).padding(.top, 2)
                    Text(line)
                }
                .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
            }
        }
    }

    /// A pet given during the password hold moves the deletion to the hold's end.
    private func holdLines(_ impact: TeamDeletionImpact) -> [String] {
        guard let hold = DateText.parse(impact.transferHoldEndsAt) else { return [] }
        let usual = Date().addingTimeInterval(Double(impact.gracePeriodHours ?? 0) * 3600)
        guard hold > usual else { return [] }
        let formatter = DateFormatter()
        formatter.locale = .app
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return (impact.petTransfers ?? []).compactMap { pet in
            guard let person = pet.candidates?.first(where: { $0.userId == petAnswers[pet.petId] }) else { return nil }
            return LF("Your account will be deleted on %1$@, when %2$@ can go to %3$@.", formatter.string(from: hold), pet.petName ?? "", person.name ?? "")
        }
    }

    private func codeStep(_ impact: TeamDeletionImpact) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            PMTextField(L("Six-digit email code"), text: Binding(get: { code }, set: { code = String($0.filter(\.isNumber).prefix(6)) }), keyboard: .numberPad)
                .textContentType(.oneTimeCode)
                .disabled(scheduling)
            Button { Task { try? await sendCode(first: false) } } label: {
                HStack(spacing: 6) {
                    Glyph("rotate-cw", size: 14)
                    Text(L("Resend code"))
                }
                .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
            }
            .buttonStyle(.plain)
            .disabled(sending || scheduling)
            ForEach(holdLines(impact), id: \.self) { line in
                Text(line).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
            }
            let outcomes = (impact.ownedHouseholds ?? []).compactMap { TeamDeletionWords.outcome($0, householdAnswers[$0.id]) }
            ForEach(outcomes, id: \.self) { line in
                Text(line).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
            }
            HStack(spacing: 6) {
                Glyph("circle-check", size: 16).foregroundStyle(ProviderState.done.color)
                Text(LF("%@ confirmed", TeamDeletionWords.word))
            }
            .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.wash(ProviderState.done.color, 18), in: Capsule())
            Button { acknowledged.toggle() } label: {
                HStack(alignment: .top, spacing: 12) {
                    Tick(on: acknowledged).padding(.top, 2)
                    Text(L("I understand deletion is permanent after it begins and PawMiaw does not issue an automatic or prorated subscription refund."))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(scheduling)
            FlowLayout(spacing: 10) {
                PMButton(L("Schedule permanent deletion"), systemImage: "trash-2", variant: .destructive, isWorking: scheduling) { schedule() }
                    .disabled(!canSubmit || scheduling)
                Text("\(impact.gracePeriodHours ?? 0) \(L("hours to cancel"))")
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
            }
        }
    }

    // MARK: Actions

    private func loadStatus() async {
        status = try? await API.get("/users/me/account-deletion")
        statusLoaded = true
    }

    private func loadImpact() async {
        impactLoading = true
        defer { impactLoading = false }
        do {
            impact = try await API.get("/users/me/account-deletion/impact")
            impactFailed = false
        } catch {
            impactFailed = impact == nil
        }
    }

    /// Every household another adult could keep needs its answer first; nothing is answered for the person.
    private func reportUnanswered() -> Bool {
        var errors: [String: String] = [:]
        for household in impact?.ownedHouseholds ?? [] where !(household.successors ?? []).isEmpty {
            if TeamDeletionWords.outcome(household, householdAnswers[household.id]) == nil {
                errors[household.id] = LF("Choose what happens to %@.", TeamDeletionWords.household(household.name))
            }
        }
        householdErrors = errors
        if let first = errors.values.first {
            Toast.error(errors.count == 1 ? first : LF("Check the %d marked fields.", errors.count))
            return true
        }
        return false
    }

    /// The word is asked only once every household has its answer.
    private func openGate() {
        if reportUnanswered() { return }
        gateOpen = true
    }

    private func sendCode(first: Bool) async throws {
        sending = true
        defer { sending = false }
        do {
            try await API.send("POST", "/users/me/account-deletion/verification")
            if first { codeSent = true }
            Toast.show(first ? L("A verification code was sent to your email.") : L("A new code was sent to your email."))
        } catch {
            let message = errorText(error, fallback: L("The code could not be sent."))
            if first { throw APIError(status: (error as? APIError)?.status ?? 0, message: message, code: nil, fields: [:]) }
            Toast.error(message)
        }
    }

    private func schedule() {
        // Who can take a household over may have changed since the first step.
        if reportUnanswered() { return }
        guard let impact else { return }
        var handover: [String: String] = [:]
        for household in impact.ownedHouseholds ?? [] {
            if let answer = householdAnswers[household.id], household.successors?.contains(where: { $0.userId == answer }) == true { handover[household.id] = answer }
        }
        var given: [String: String] = [:]
        for pet in impact.petTransfers ?? [] {
            if let answer = petAnswers[pet.petId], pet.candidates?.contains(where: { $0.userId == answer }) == true { given[pet.petId] = answer }
        }
        var body: [String: Any?] = ["verificationCode": code, "confirmation": TeamDeletionWords.word, "acknowledgeNoAutomaticRefund": true]
        if !handover.isEmpty { body["handover"] = handover }
        if !given.isEmpty { body["petTransfers"] = given }
        scheduling = true
        Task {
            defer { scheduling = false }
            do {
                let _: EmptyResponse = try await API.post("/users/me/account-deletion", body: body)
                Toast.show(L("Account deletion was scheduled. Check your email for the cancellation link."))
                // Like the web: still signed in, the card turns into the scheduled deletion and the way to cancel it.
                expanded = false
                codeSent = false
                code = ""
                acknowledged = false
                self.impact = nil
                await loadStatus()
                announceDataChanged()
            } catch let error as APIError where error.code == "HANDOVER_NOT_ALLOWED" {
                await handoverRefused(error.message, sent: handover)
            } catch {
                Toast.error(errorText(error, fallback: L("Account deletion could not be scheduled.")))
            }
        }
    }

    /// The adult chosen for a household can no longer take it: who can is read again and those
    /// households are asked again, with the server's sentence under them. The code is not spent.
    private func handoverRefused(_ sentence: String, sent: [String: String]) async {
        await loadImpact()
        let fresh = impact?.ownedHouseholds ?? []
        let stale = sent.keys.filter { id in
            !(fresh.first { $0.id == id }?.successors?.contains { $0.userId == sent[id] } ?? false)
        }
        let refused = stale.isEmpty ? Array(sent.keys) : stale
        for id in refused {
            householdAnswers[id] = nil
            householdErrors[id] = sentence
        }
        Toast.error(sentence)
    }

    private func cancelDeletion() {
        cancelling = true
        Task {
            defer { cancelling = false }
            do {
                status = try await API.post("/users/me/account-deletion/cancel")
                Toast.show(L("Account deletion was cancelled."))
                expanded = false
                codeSent = false
                code = ""
                acknowledged = false
                impact = nil
                await loadStatus()
            } catch {
                Toast.error(errorText(error, fallback: L("Deletion could not be cancelled.")))
            }
        }
    }
}

/// A line with a small coloured icon before it (the deletion review's facts).
private struct TeamIconLine: View {
    let icon: String
    var tint: Color = Theme.blue
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Glyph(icon, size: 16).foregroundStyle(tint).padding(.top, 2)
            Text(text)
        }
        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
    }
}
