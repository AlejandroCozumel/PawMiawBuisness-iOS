//
//  TeamAccessSheet.swift
//  PawMiawNegocios
//
//  Change someone's role and, when the role is nearly right, single
//  permissions just for them (web: staff-access-sheet.tsx). Every permission
//  starts where the role puts it; one moved away is marked and can be put
//  back. The server refuses what the sheet greys out: more than the person
//  saving has, and "Money settings and the plan" by anyone but the owner.
//

import SwiftUI

struct TeamAccessSheet: View {
    let member: TeamMember
    let roles: [TeamRolePermissions]?
    /// What the person saving can do: nobody hands out more than they have.
    let actorPermissions: [String]
    let actorManagesPlan: Bool
    let onSave: (_ role: String, _ allow: [String], _ deny: [String]) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var role = ""
    @State private var wanted: [String] = []
    @State private var query = ""
    @State private var openGroups: Set<String> = []
    @State private var pending = false
    @State private var error: String?
    @State private var started = false

    private var name: String { member.shownName }
    private var defaults: [String]? { TeamPermissions.roleDefaults(roles, role) }
    private var mine: Set<String> { Set(actorPermissions) }
    private var had: Set<String> { Set(member.effective) }
    private var overrides: (allow: [String], deny: [String]) {
        defaults.map { TeamPermissions.overrides(defaults: $0, wanted: wanted) } ?? (member.allow, member.deny)
    }
    private var changedCount: Int { overrides.allow.count + overrides.deny.count }
    private var dirty: Bool {
        role != member.roleKey || Set(overrides.allow) != Set(member.allow) || Set(overrides.deny) != Set(member.deny)
    }
    private var teamPowers: Bool { role != "admin" && overrides.allow.contains { TeamPermissions.teamAdmin.contains($0) } }

    var body: some View {
        ProviderModal(
            title: LF("Access for %@", name),
            subtitle: L("Pick the role that fits. Fine-tune only when the role is nearly right."),
            systemImage: "shield-check",
            accent: .butter,
            isDirty: dirty,
            primaryTitle: L("Save access"),
            isWorking: pending,
            primaryIcon: "shield-check",
            onPrimary: { save() }
        ) {
            ModalSection(title: L("Role")) {
                VStack(spacing: 8) {
                    ForEach(TeamRole.assignable, id: \.self) { option in
                        let beyond = roleBlocked(option)
                        TeamRoleChoice(role: option, selected: role == option, disabledReason: beyond ? L("More access than your own, so you can’t give it.") : nil) {
                            if beyond { Toast.error(L("More access than your own, so you can’t give it.")); return }
                            chooseRole(option)
                        }
                    }
                }
            }
            ModalSection(title: LF("Permissions for %@", name), subtitle: L("Each one starts where the role puts it. Change only what this person needs differently.")) {
                if let defaults {
                    permissions(defaults)
                } else {
                    NoticeCard(tone: .warning, message: L("What each role gives couldn’t load, so only the role can be changed now. Close this and try again in a moment."), icon: "triangle-alert")
                }
            }
            if let error {
                Text(error)
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.destructive)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.wash(Theme.destructive, 6), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.destructive, 40, with: Theme.borderSoft), lineWidth: 1))
            }
        }
        .onAppear { start() }
    }

    private func start() {
        guard !started else { return }
        started = true
        role = member.roleKey
        if let saved = TeamPermissions.roleDefaults(roles, member.roleKey) {
            wanted = TeamPermissions.effective(defaults: saved, allow: member.allow, deny: member.deny)
        } else {
            wanted = member.effective
        }
        // Start with the areas that already have something changed open.
        let changed = Set(member.allow + member.deny)
        openGroups = Set(TeamPermissions.groups.filter { $0.permissions.contains { changed.contains($0.key) } }.map(\.key))
    }

    private func chooseRole(_ next: String) {
        // What was changed for them stays changed under the new role.
        if defaults != nil, let nextDefaults = TeamPermissions.roleDefaults(roles, next) {
            let current = overrides
            wanted = TeamPermissions.effective(defaults: nextDefaults, allow: current.allow, deny: current.deny)
        }
        role = next
    }

    private func roleBlocked(_ option: String) -> Bool {
        guard option != member.roleKey, let optionDefaults = TeamPermissions.roleDefaults(roles, option) else { return false }
        return optionDefaults.contains { !mine.contains($0) && !had.contains($0) }
    }

    /// Why a permission can't be turned on by this person, if it can't.
    private func blocked(_ permission: String) -> String? {
        if wanted.contains(permission) || had.contains(permission) { return nil }
        if permission == "billing.manage" && !actorManagesPlan { return L("Only the owner turns this on for one person: it also lets them change the plan.") }
        if !mine.contains(permission) { return L("You don’t have this permission, so you can’t give it.") }
        return nil
    }

    private func toggle(_ permission: String, _ on: Bool) {
        if on { if !wanted.contains(permission) { wanted.append(permission) } } else { wanted.removeAll { $0 == permission } }
    }

    @ViewBuilder
    private func permissions(_ defaults: [String]) -> some View {
        let base = Set(defaults)
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let groups = TeamPermissions.search(query)
        SearchField(prompt: L("A permission, like “refund”"), text: $query, shape: .field)
        HStack(spacing: 8) {
            if changedCount == 0 {
                Text(L("Exactly what the role gives.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            } else {
                Chip(text: LP(changedCount, "1 changed", "%d changed"), tone: .custom(Theme.lime), percent: 100, ink: Theme.inkOnBright, weight: .heavy)
                Button { wanted = defaults } label: {
                    HStack(spacing: 6) {
                        Glyph("rotate-ccw", size: 14)
                        Text(L("Back to the role’s access"))
                    }
                    .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                    .padding(.horizontal, 10).frame(height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        if teamPowers {
            NoticeCard(tone: .warning, message: L("With these, someone who isn’t an Admin can change permissions and suspend people. Inviting, changing a role and removing someone still need an Admin or the Owner."), icon: "triangle-alert")
        }
        if groups.isEmpty {
            Text(LF("No permission matches “%@”.", query.trimmingCharacters(in: .whitespaces)))
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                .padding(.horizontal, 16).padding(.vertical, 24).frame(maxWidth: .infinity)
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        ForEach(groups, id: \.key) { group in
            let on = group.permissions.filter { wanted.contains($0.key) }.count
            let groupChanged = group.permissions.filter { base.contains($0.key) != wanted.contains($0.key) }.count
            let groupOpen = searching || openGroups.contains(group.key)
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if openGroups.contains(group.key) { openGroups.remove(group.key) } else { openGroups.insert(group.key) }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Glyph("chevron-down", size: 16).rotationEffect(.degrees(groupOpen ? 0 : -90)).foregroundStyle(Theme.inkSoft)
                        Text(L(group.title)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Spacer(minLength: 4)
                        if groupChanged > 0 { Chip(text: LP(groupChanged, "1 changed", "%d changed"), tone: .custom(Theme.lime), percent: 100, ink: Theme.inkOnBright, weight: .heavy) }
                        Text(LF("%1$d of %2$d", on, group.permissions.count)).font(Theme.text(12, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(searching)
                if groupOpen {
                    VStack(spacing: 0) {
                        ForEach(group.permissions, id: \.key) { permission in
                            RowDivider()
                            row(permission, base: base)
                        }
                    }
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        }
    }

    private func row(_ permission: TeamPermissionInfo, base: Set<String>) -> some View {
        let isOn = wanted.contains(permission.key)
        let fromRole = base.contains(permission.key)
        let changed = isOn != fromRole
        let why = isOn ? nil : blocked(permission.key)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                FlowLayout(spacing: 8) {
                    Text(L(permission.label)).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    if changed {
                        Chip(text: isOn ? L("Turned on for them") : L("Turned off for them"), tone: .custom(Theme.lime), percent: 100, ink: Theme.inkOnBright, weight: .heavy)
                    } else {
                        Text(fromRole ? L("From the role") : L("Not in the role")).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    }
                }
                Text(L(permission.description)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                if let why { Text(why).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkStrong) }
            }
            Spacer(minLength: 4)
            if changed {
                Button { toggle(permission.key, fromRole) } label: {
                    Glyph("rotate-ccw", size: 14).foregroundStyle(Theme.inkSoft).frame(width: 32, height: 32).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LF("Put “%@” back as the role has it", L(permission.label)))
            }
            Toggle(isOn: Binding(get: { isOn }, set: { toggle(permission.key, $0) })) { EmptyView() }
                .toggleStyle(PMSwitchStyle())
                .fixedSize()
                .padding(.top, 6)
                .disabled(pending || why != nil)
                .accessibilityLabel(L(permission.label))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(changed ? AnyShapeStyle(Theme.wash(Theme.lime, 9)) : AnyShapeStyle(Color.clear))
    }

    private func save() {
        guard dirty else { dismiss(); return }
        pending = true
        error = nil
        let current = overrides
        Task {
            defer { pending = false }
            do {
                try await onSave(role, current.allow, current.deny)
                Toast.show(LF("Access saved for %@.", name))
                dismiss()
            } catch {
                self.error = errorText(error)
                Toast.error(error)
            }
        }
    }
}

