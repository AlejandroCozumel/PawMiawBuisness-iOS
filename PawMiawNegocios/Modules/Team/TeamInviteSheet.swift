//
//  TeamInviteSheet.swift
//  PawMiawNegocios
//
//  Invite someone to the team in steps (web: staff-invite-sheet.tsx): who
//  they are, their role, where they work (a business with several
//  locations) and a last look. PawMiaw emails the invitation; once sent the
//  sheet hands over a message to send by another way. They accept with that
//  email within 48 hours.
//

import SwiftUI
import UIKit

private enum InviteStep: Hashable { case who, role, place, review }

struct TeamInviteSheet: View {
    let workspaceName: String
    /// Free seats on the plan, counting invitations still waiting; nil with no cap.
    let seatsLeft: Int?
    let memberEmails: Set<String>
    let waitingEmails: Set<String>
    /// Active locations, primary first; with two or more the sheet asks where they work.
    let locations: [ProviderLocation]
    let roles: [TeamRolePermissions]?
    let onSent: () async -> Void

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var step: InviteStep = .who
    @State private var name = ""
    @State private var email = ""
    @State private var role = "support_staff"
    @State private var locationIds: [String] = []
    @State private var pending = false
    @State private var sent: TeamInvitation?
    @State private var copied = false
    @State private var formError: String?

    private var asksWhere: Bool { locations.count >= 2 && role != "admin" }
    private var steps: [InviteStep] { asksWhere ? [.who, .role, .place, .review] : [.who, .role, .review] }
    private var index: Int { steps.firstIndex(of: step) ?? 0 }
    private var full: Bool { (seatsLeft ?? 1) <= 0 }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var everywhere: Bool { !asksWhere || locationIds.isEmpty || locationIds.count == locations.count }
    private var whereText: String {
        everywhere ? L("Every location") : locations.filter { locationIds.contains($0.id) }.map(\.name).joined(separator: ", ")
    }

    var body: some View {
        ProviderModal(
            title: sent == nil ? L("Invite someone") : L("Invitation sent"),
            subtitle: sent.map { LF("We emailed %@.", $0.email) } ?? L("They join with their own PawMiaw account and the role you choose."),
            systemImage: sent == nil ? "mail-plus" : "circle-check",
            accent: .aqua,
            isDirty: sent == nil && (index > 0 || !trimmedName.isEmpty || !trimmedEmail.isEmpty),
            form: form,
            primaryTitle: primaryTitle,
            isWorking: pending,
            steps: sent == nil ? ModalSteps(steps.map(label), icons: steps.map(stepIcon), current: index) : nil,
            onBack: sent == nil && index > 0 ? { withAnimation { step = steps[index - 1] } } : nil,
            // Once sent, the web's footer: "Invite someone else" beside "Done", no Cancel.
            secondaryActions: sent == nil ? [] : [ModalAction(L("Invite someone else")) { startOver() }],
            primaryIcon: sent == nil && step == .review ? "send" : nil,
            // The seats left sit over the buttons on the first step, as on the web.
            footerSummary: sent == nil && step == .who ? seatsText.map { AnyView(Text($0).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)) } : nil,
            showsCancel: sent == nil,
            onPrimary: { primary() }
        ) {
            if let sent { sentView(sent) } else { stepView }
        }
    }

    private var primaryTitle: String {
        if sent != nil { return L("Done") }
        switch step {
        case .review: return L("Send invitation")
        // Every step forward is "Continue" (the owner's rule); the last keeps its own words.
        default: return L("Continue")
        }
    }

    private func primary() {
        if sent != nil { dismiss(); return }
        if full {
            Toast.error(L("Every seat on your plan is taken, counting invitations still waiting. Upgrade the plan, cancel an invitation or remove someone first."))
            return
        }
        if step == .review { invite(); return }
        if step == .who && !checkWho() { return }
        if let following = steps[safe: index + 1] { withAnimation { step = following } }
    }

    private func checkWho() -> Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        var emailError: String?
        if trimmedEmail.isEmpty { emailError = L("Add their email.") }
        else if trimmedEmail.range(of: pattern, options: .regularExpression) == nil { emailError = L("That doesn’t look like an email.") }
        else if memberEmails.contains(trimmedEmail) { emailError = L("This person is already on the team.") }
        else if waitingEmails.contains(trimmedEmail) { emailError = L("This email already has an invitation waiting. Send it again from Invitations.") }
        return form.check([("name", trimmedName.isEmpty ? L("Add their name.") : nil), ("email", emailError)])
    }

    private func invite() {
        guard let clinicId = workspace.current?.clinicId else { return }
        pending = true
        formError = nil
        Task {
            defer { pending = false }
            do {
                let invitation: TeamInvitation = try await API.post("/provider-workspaces/\(clinicId)/invitations", body: [
                    "name": trimmedName,
                    "email": trimmedEmail,
                    "role": role,
                    "locationIds": everywhere ? [String]() : locationIds,
                ])
                sent = invitation
                await onSent()
                announceDataChanged()
            } catch {
                formError = errorText(error)
                Toast.error(error)
            }
        }
    }

    private func startOver() {
        step = .who; name = ""; email = ""; role = "support_staff"; locationIds = []
        sent = nil; copied = false; formError = nil
        form.errors = [:]
    }

    // MARK: Steps

    @ViewBuilder
    private var stepView: some View {
        if index > 0 {
            FlowLayout(spacing: 6) {
                Chip(text: trimmedName, icon: "user-round")
                Chip(text: trimmedEmail)
                if step == .place || step == .review { Chip(text: TeamRole.label(role), icon: "key-round") }
            }
        }
        switch step {
        case .who: whoStep
        case .role: roleStep
        case .place: placeStep
        case .review: reviewStep
        }
    }

    private func stepIcon(_ step: InviteStep) -> String {
        switch step {
        case .who: "user-round"
        case .role: "key-round"
        case .place: "map-pin"
        case .review: "clipboard-check"
        }
    }

    private func label(_ step: InviteStep) -> String {
        switch step {
        case .who: L("Who")
        case .role: L("Role")
        case .place: L("Where")
        case .review: L("Review")
        }
    }

    @ViewBuilder
    private var whoStep: some View {
        PMTextField(L("Name"), text: $name, key: "name", form: form, prompt: L("e.g. Dr. Ana López"), capitalization: .words, required: true)
        PMTextField(L("Email"), text: $email, key: "email", form: form, prompt: "ana@example.com", keyboard: .emailAddress, required: true)
        Text(L("Use the email they will sign in with. Someone who already uses PawMiaw for their own pets joins with that same account."))
            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        if full {
            Text(L("Every seat on your plan is taken, counting invitations still waiting. Upgrade the plan, cancel an invitation or remove someone first."))
                .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(Theme.destructive, 6), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.destructive, 40, with: Theme.borderSoft), lineWidth: 1))
        }
    }

    /// "3 seats left on your plan." (web `seatsText`): nil with no cap.
    private var seatsText: String? {
        guard let seatsLeft else { return nil }
        return full ? L("No seats left on your plan.") : LP(seatsLeft, "1 seat left on your plan.", "%d seats left on your plan.")
    }

    @ViewBuilder
    private var roleStep: some View {
        VStack(spacing: 8) {
            ForEach(TeamRole.assignable, id: \.self) { option in
                TeamRoleChoice(role: option, selected: role == option) { role = option }
            }
        }
        TeamRoleAccessSummary(role: role, roles: roles)
        Text(L("The role sets what they can do. You can fine-tune it on their page once they join."))
            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
    }

    @ViewBuilder
    private var placeStep: some View {
        Text(L("Their Schedule column, registers and “today” follow where they work. Clients are shared by every location."))
            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        TeamLocationChoiceList(locations: locations, value: $locationIds)
    }

    @ViewBuilder
    private var reviewStep: some View {
        VStack(spacing: 0) {
            reviewRow(L("Who"), title: trimmedName, detail: trimmedEmail) { step = .who }
            RowDivider()
            reviewRow(L("Role"), title: TeamRole.label(role), detail: TeamRole.summary(role)) { step = .role }
            if locations.count >= 2 {
                RowDivider()
                reviewRow(L("Where"), title: whereText, detail: role == "admin" ? L("Admins work at every location.") : nil, change: asksWhere ? { step = .place } : nil)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        Text(L("We email them the invitation. It lasts 48 hours and holds a seat on your plan until they accept or it runs out."))
            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        if let formError {
            Text(formError)
                .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.destructive)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(Theme.destructive, 6), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.destructive, 40, with: Theme.borderSoft), lineWidth: 1))
        }
    }

    private func reviewRow(_ label: String, title: String, detail: String?, change: (() -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label.uppercased()).font(.brandText(10.9, weight: .heavy)).tracking(1.3).foregroundStyle(Theme.inkSoft).frame(width: 64, alignment: .leading).padding(.top, 2)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                if let detail { Text(detail).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
            }
            Spacer(minLength: 0)
            if let change {
                Button(L("Change")) { withAnimation { change() } }.font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Sent

    @ViewBuilder
    private func sentView(_ sent: TeamInvitation) -> some View {
        let message = TeamText.invitationMessage(name: sent.inviteeName, email: sent.email, workspace: workspaceName)
        VStack(alignment: .leading, spacing: 4) {
            Text(LF("%@ has 48 hours to accept", sent.inviteeName.nonEmpty ?? sent.email)).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
            Text(LF("The email has a button to accept. With a PawMiaw account under %1$@ they sign in; without one they make it with that same email. Then they join as %2$@.", sent.email, TeamRole.label(sent.role)))
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(ProviderState.done.color, 9), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(ProviderState.done.color, 45, with: Theme.borderSoft), lineWidth: 1))
        ModalSection(title: L("Tell them yourself too"), subtitle: L("Emails get lost. This says the same, to send by WhatsApp or however you talk.")) {
            Text(message)
                .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            PMButton(copied ? L("Copied") : L("Copy message"), systemImage: copied ? "check" : "copy", variant: .outline, size: .modal, fullWidth: true) {
                UIPasteboard.general.string = message
                copied = true
                Toast.show(L("Message copied."))
            }
        }
        Text(L("Until they accept, the invitation waits in Invitations, where you can send it again or cancel it."))
            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
    }
}

/// A role's access area by area ("Agenda y visitas · Todo"), from what the server says the role gives.
struct TeamRoleAccessSummary: View {
    let role: String
    let roles: [TeamRolePermissions]?

    var body: some View {
        if let defaults = TeamPermissions.roleDefaults(roles, role) {
            let groups = TeamPermissions.byGroup(defaults)
            let some = groups.filter { !$0.on.isEmpty }
            let none = groups.filter { $0.on.isEmpty }
            VStack(alignment: .leading, spacing: 8) {
                Text(LF("What %@ can do", TeamRole.label(role))).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                FlowLayout(spacing: 6) {
                    ForEach(some, id: \.group.key) { entry in
                        HStack(spacing: 6) {
                            Text(L(entry.group.title)).foregroundStyle(Theme.inkStrong)
                            Text(entry.on.count == entry.group.permissions.count ? L("Everything") : LF("%1$d of %2$d", entry.on.count, entry.group.permissions.count)).foregroundStyle(Theme.inkSoft)
                        }
                        .font(Theme.text(12, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
                    }
                }
                if !none.isEmpty {
                    (Text(L("No access to:")).fontWeight(.semibold).foregroundColor(Theme.inkStrong) + Text(" " + none.map { L($0.group.title) }.joined(separator: ", ")))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wash(Theme.surfaceMuted, 45), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        }
    }
}

/// A role to pick (web `RoleChoice`): its icon on the role's hue, the name and
/// what it does, a round tick; blue border and a blue wash when chosen.
struct TeamRoleChoice: View {
    let role: String
    let selected: Bool
    var disabledReason: String? = nil
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Glyph(TeamRole.icon(role), size: 16).foregroundStyle(Theme.inkStrong)
                    .frame(width: 36, height: 36)
                    .background(Theme.wash(TeamRole.hue(role).color, 30), in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(TeamRole.label(role)).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    Text(TeamRole.summary(role)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.leading)
                    if let disabledReason {
                        Text(disabledReason).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkStrong).padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
                Tick(on: selected, style: .radio).padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(selected ? AnyShapeStyle(Theme.wash(Theme.blue, 8)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(selected ? Theme.blue : Theme.borderSoft, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(disabledReason != nil ? 0.6 : 1)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
