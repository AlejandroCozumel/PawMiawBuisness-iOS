//
//  StaffScreen.swift
//  PawMiawNegocios
//
//  The team (web: routes/provider.staff.tsx): who works here and whose access
//  is paused, their role and what was changed for them, where they work and
//  how many pets they take at once, when they were last here; the
//  invitations still waiting (send again, copy a message, cancel); and what
//  each role can do. The numbers on top are filters.
//

import SwiftUI
import UIKit

private enum StaffView: Hashable { case people, invitations, roles }

struct StaffScreen: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var members: [TeamMember] = []
    @State private var invitations: [TeamInvitation] = []
    @State private var roles: [TeamRolePermissions]?
    @State private var membersLoaded = false
    @State private var invitationsLoaded = false
    @State private var error: String?
    @State private var view: StaffView = .people
    @State private var query = ""
    @State private var roleFilter: String?
    @State private var visitsOnly = false
    @State private var suspendedOnly = false
    @State private var inviting = false
    @State private var cancelTarget: TeamOpenInvitation?
    @State private var busyId: String?
    @State private var shownRole = "admin"
    @State private var pushed: ProviderRoute?

    private var canInvite: Bool { workspace.can(.staffInvite) }

    var body: some View {
        Group {
            if !workspace.can(.staffView) {
                PageScroll { NoAccessState(message: L("Ask the workspace owner to let your role see staff.")) }
            } else if workspace.inSetup {
                PageScroll {
                    ModuleHeader(icon: ProviderSection.staff.headerIcon, title: L("Staff"), subtitle: L("Who works here and what each person can do."), accent: ProviderSection.staff.headerAccent, storageKey: "staff")
                    EmptyState(systemImage: "building-2", title: L("Finish workspace setup before adding your team."), message: L("The team belongs to a workspace, so its basics need to be saved first."), accent: Theme.pink, panel: true)
                }
            } else {
                content
            }
        }
        .providerPage(L("Staff"), root: true)
        .reloadsOnScope { await load() }
        .navigationDestination(item: $pushed) { RouteView(route: $0) }
        .sheet(isPresented: $inviting) {
            TeamInviteSheet(
                workspaceName: workspace.current?.name ?? "PawMiaw",
                seatsLeft: seatsLeft,
                memberEmails: memberEmails,
                waitingEmails: waitingEmails,
                locations: workspace.activeLocations,
                roles: roles
            ) { await load() }
        }
        .sheet(item: $cancelTarget) { item in
            TeamConfirmSheet(
                title: item.expired ? L("Remove this invitation?") : L("Cancel this invitation?"),
                message: item.expired ? L("It already ran out; this clears it from the list.") : L("The link in their email stops working, and the seat it held is free. You can invite them again later."),
                confirmTitle: item.expired ? L("Remove invitation") : L("Cancel invitation"),
                cancelTitle: L("Keep it")
            ) {
                try await cancel(item)
            } content: {
                TeamPersonLine(name: item.shownName, detail: [TeamRole.label(item.invitation.role), item.invitation.email].joined(separator: " · "))
            }
        }
    }

    // MARK: Loading

    private func load() async {
        guard let clinicId = workspace.current?.clinicId, workspace.can(.staffView), !workspace.inSetup else { return }
        do {
            members = try await API.get("/provider-workspaces/\(clinicId)/members")
            error = nil
        } catch {
            if members.isEmpty { self.error = errorText(error) }
        }
        membersLoaded = true
        if let list: [TeamInvitation] = try? await API.get("/provider-workspaces/\(clinicId)/invitations") { invitations = list }
        invitationsLoaded = true
        if roles == nil {
            let answer: TeamRolesResponse? = try? await API.get("/provider-workspace-roles")
            roles = answer?.roles
        }
    }

    // MARK: Numbers

    private var memberEmails: Set<String> {
        Set(members.compactMap { $0.email?.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
    }
    private var open: [TeamOpenInvitation] { TeamText.openInvitations(invitations, memberEmails: memberEmails) }
    private var waitingEmails: Set<String> {
        Set(open.filter { !$0.expired }.map { $0.invitation.email.trimmingCharacters(in: .whitespaces).lowercased() })
    }
    private var waiting: Int { waitingEmails.count }
    private var ranOut: Int { open.count - waiting }
    private var takingVisits: [TeamMember] { members.filter(\.takesVisits) }
    private var suspended: [TeamMember] { members.filter(\.isSuspended) }
    private var seatsAtOnce: Int { takingVisits.reduce(0) { $0 + $1.atOnce } }
    private var seatLimit: Int? { workspace.current?.seatLimit }
    /// The plan counts invitations still waiting, and suspended people keep their seat.
    private var seatsUsed: Int { members.count + waiting }
    private var seatsLeft: Int? { seatLimit.map { max(0, $0 - seatsUsed) } }

    private var roleCounts: [String: Int] {
        Dictionary(grouping: members, by: \.roleKey).mapValues(\.count)
    }

    private var needle: String { query.trimmingCharacters(in: .whitespaces).lowercased() }
    private var filtered: Bool { roleFilter != nil || visitsOnly || suspendedOnly || !needle.isEmpty }

    private var shownMembers: [TeamMember] {
        members.filter { member in
            if let roleFilter, member.roleKey != roleFilter { return false }
            if visitsOnly && !member.takesVisits { return false }
            if suspendedOnly && !member.isSuspended { return false }
            guard !needle.isEmpty else { return true }
            return [member.shownName, member.userName, member.email, member.professionalTitle, member.specialty, TeamRole.label(member.role)]
                .contains { $0?.lowercased().contains(needle) ?? false }
        }
        .sorted { a, b in
            if a.isSuspended != b.isSuspended { return !a.isSuspended }
            if a.isMe != b.isMe { return a.isMe }
            if (a.roleKey == "owner") != (b.roleKey == "owner") { return a.roleKey == "owner" }
            return a.shownName.localizedCompare(b.shownName) == .orderedAscending
        }
    }

    private var shownInvitations: [TeamOpenInvitation] {
        open.filter { item in
            if let roleFilter, item.invitation.role != roleFilter { return false }
            guard !needle.isEmpty else { return true }
            return [item.invitation.inviteeName, item.invitation.email].contains { $0?.lowercased().contains(needle) ?? false }
        }
    }

    // MARK: Page

    private var content: some View {
        PageScroll(refresh: { await load() }) {
            header
            VStack(alignment: .leading, spacing: 12) {
                toolbar
                listCard
            }
        }
    }

    private var header: some View {
        ModuleHeader(
            icon: ProviderSection.staff.headerIcon,
            title: L("Staff"),
            subtitle: L("Who works here, what each person can do, and where and when they work."),
            accent: ProviderSection.staff.headerAccent,
            stats: headerStats,
            storageKey: "staff"
        ) {
            if canInvite {
                PMButton(L("Invite someone"), systemImage: "user-plus") { inviting = true }
            }
        }
    }

    private var headerStats: [ModuleStat] {
        let full = seatLimit != nil && seatsLeft == 0
        return [
            ModuleStat("people", label: L("People"), value: membersLoaded ? "\(members.count)" : "—",
                       hint: suspended.isEmpty ? L("Everyone on the team") : LP(suspended.count, "1 suspended", "%d suspended"),
                       icon: "users-round", accent: Theme.pink,
                       active: view == .people && roleFilter == nil && !visitsOnly && !suspendedOnly,
                       action: { view = .people; roleFilter = nil; visitsOnly = false; suspendedOnly = false }),
            ModuleStat("visits", label: L("Take visits"), value: membersLoaded ? "\(takingVisits.count)" : "—",
                       hint: takingVisits.isEmpty ? L("Nobody starts visits yet") : (seatsAtOnce == 1 ? L("One pet at a time") : LF("%d pets at once in all", seatsAtOnce)),
                       icon: "calendar-check", accent: Theme.lime,
                       active: view == .people && visitsOnly,
                       action: { let on = !(visitsOnly && view == .people); view = .people; suspendedOnly = false; visitsOnly = on }),
            ModuleStat("invitations", label: L("Invitations"), value: invitationsLoaded ? "\(waiting)" : "—",
                       hint: ranOut > 0 ? LP(ranOut, "1 ran out", "%d ran out") : (waiting > 0 ? L("Waiting to join") : L("Nobody waiting")),
                       icon: "mail-plus", accent: Theme.aqua, attention: ranOut > 0,
                       active: view == .invitations,
                       action: { view = view == .invitations ? .people : .invitations; visitsOnly = false; suspendedOnly = false }),
            ModuleStat("seats", label: L("Seats"), value: seatLimit.map { LF("%1$d of %2$d", seatsUsed, $0) } ?? "\(seatsUsed)",
                       hint: seatLimit == nil ? L("No limit on your plan") : (full ? L("Plan full · invitations count") : LP(seatsLeft ?? 0, "1 free · invitations count", "%d free · invitations count")),
                       icon: "armchair", accent: Theme.blue, attention: full,
                       action: full && (workspace.current?.canManagePlan ?? false) ? { pushed = .section(.billing) } : nil),
        ]
    }

    /// People | Invitations | Roles, the search, and the filters (web `StaffToolbar`).
    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Segmented(options: [
                .init(StaffView.people, L("People"), icon: "users-round"),
                .init(StaffView.invitations, L("Invitations"), icon: "mail-plus"),
                .init(StaffView.roles, L("Roles"), icon: "key-round"),
            ], selection: Binding(get: { view }, set: { next in
                view = next
                if next != .people { visitsOnly = false; suspendedOnly = false }
            }), look: .solid, label: L("Show"))
            SearchField(prompt: view == .people ? L("Name, email or title") : view == .invitations ? L("Name or email") : L("A permission, like “refund”"), text: $query)
            if view != .roles { filters }
        }
    }

    private var filters: some View {
        let shownRoles = TeamRole.all.filter { (roleCounts[$0] ?? 0) > 0 || roleFilter == $0 }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(shownRoles, id: \.self) { role in
                    FilterChip(title: TeamRole.label(role), count: view == .people ? roleCounts[role] ?? 0 : nil, isSelected: roleFilter == role, tone: TeamRole.hue(role).color, icon: TeamRole.icon(role)) {
                        roleFilter = roleFilter == role ? nil : role
                    }
                }
                if view == .people {
                    Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 24).padding(.horizontal, 4)
                    FilterChip(title: L("Take visits"), count: takingVisits.count, isSelected: visitsOnly, tone: Hue.mint.color, icon: "calendar-check") { visitsOnly.toggle() }
                    if !suspended.isEmpty || suspendedOnly {
                        FilterChip(title: L("Suspended"), count: suspended.count, isSelected: suspendedOnly, tone: ProviderState.closed.color, icon: "circle-pause") { suspendedOnly.toggle() }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func showEveryone() {
        query = ""; roleFilter = nil; visitsOnly = false; suspendedOnly = false
    }

    /// The list's card: 2 pt border, rows edge to edge, a count line at its foot.
    private var listCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch view {
            case .people: peopleList
            case .invitations: invitationsList
            case .roles: rolesPanel
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listCard(.panel)
    }

    private func footLine<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { RowDivider() }
    }

    private func loadFailed(_ title: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.center)
            Text(L("Check your connection and try again.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
            PMButton(L("Try again"), systemImage: "refresh-cw", variant: .outline, size: .compact) { Task { await load() } }
                .padding(.top, 12)
        }
        .padding(.horizontal, 24).padding(.vertical, 48)
        .frame(maxWidth: .infinity)
    }

    // MARK: People

    @ViewBuilder
    private var peopleList: some View {
        if !membersLoaded {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        } else if error != nil, members.isEmpty {
            loadFailed(L("The team couldn’t load."))
        } else if shownMembers.isEmpty {
            EmptyState(
                systemImage: filtered ? "search" : "users-round",
                title: filtered ? (needle.isEmpty ? L("Nobody here with these filters") : LF("Nobody matches “%@”", query.trimmingCharacters(in: .whitespaces))) : L("It’s just you so far"),
                message: filtered ? L("Try another name, or show everyone.") : L("Invite the people you work with. Each joins with their own account and a role."),
                actionTitle: filtered ? L("Show everyone") : (canInvite ? L("Invite someone") : nil),
                action: filtered ? { showEveryone() } : (canInvite ? { inviting = true } : nil),
                accent: Theme.pink
            )
        } else {
            ForEach(shownMembers) { member in
                if member.id != shownMembers.first?.id { RowDivider() }
                NavigationLink(value: ProviderRoute.staffMember(member.id)) {
                    TeamMemberRow(member: member, locations: workspace.activeLocations)
                }
                .buttonStyle(.plain)
            }
            footLine {
                HStack(spacing: 4) {
                    Text(shownMembers.count == members.count ? LP(members.count, "1 person", "%d people") : LF("%1$d of %2$d people", shownMembers.count, members.count))
                    if waiting > 0 {
                        Text("·")
                        Button(LP(waiting, "1 invitation waiting", "%d invitations waiting")) { view = .invitations }
                            .foregroundStyle(Theme.blue).fontWeight(.semibold)
                    }
                }
            }
        }
    }

    // MARK: Invitations

    @ViewBuilder
    private var invitationsList: some View {
        if !invitationsLoaded {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        } else if shownInvitations.isEmpty {
            EmptyState(
                systemImage: filtered ? "search" : "mail-plus",
                title: filtered ? L("No invitation matches") : L("No invitations waiting"),
                message: filtered ? L("Try another name, or show every invitation.") : L("When you invite someone, they wait here until they accept. Invitations last 48 hours."),
                actionTitle: filtered ? L("Show every invitation") : (canInvite ? L("Invite someone") : nil),
                action: filtered ? { query = ""; roleFilter = nil } : (canInvite ? { inviting = true } : nil),
                accent: Theme.pink
            )
        } else {
            HStack(alignment: .top, spacing: 8) {
                Glyph("mail-check", size: 16).padding(.top, 2)
                Text(L("Each person got an email with a button to accept. They join by signing in — or making their account — with that same email. An invitation holds a seat for 48 hours."))
            }
            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wash(Theme.aqua, 8))
            .overlay(alignment: .bottom) { RowDivider() }
            ForEach(shownInvitations) { item in
                if item.id != shownInvitations.first?.id { RowDivider() }
                invitationRow(item)
            }
            footLine {
                Text(shownInvitations.count == open.count ? LP(open.count, "1 invitation", "%d invitations") : LF("%1$d of %2$d invitations", shownInvitations.count, open.count))
            }
        }
    }

    private func invitationRow(_ item: TeamOpenInvitation) -> some View {
        let invitation = item.invitation
        let locations = workspace.activeLocations
        let place = locations.count >= 2 ? TeamText.locationNames(role: invitation.role, ids: invitation.locationIds, locations: locations) : nil
        let when = DateText.parse(invitation.expiresAt).map { TeamText.relative($0) } ?? ""
        let tone = item.expired ? Theme.mango : Theme.aqua
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Avatar(name: item.shownName, size: 40, tint: tone)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.shownName).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text(invitation.email).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                teamRoleChip(invitation.role)
                if let place {
                    HStack(spacing: 4) { Glyph("map-pin", size: 12); Text(place).lineLimit(1) }
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.leading, 52)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(tone).frame(width: 6, height: 6)
                    Text(item.expired ? L("Ran out") : L("Waiting"))
                }
                .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkStrong)
                .padding(.horizontal, 10).frame(height: 24)
                .background(Theme.wash(tone, 18), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.mix(tone, 55, with: Theme.borderSoft), lineWidth: 1))
                Text(item.expired ? LF("Ran out %@", when) : LF("Ends %@", when))
                    .font(Theme.text(14, weight: item.expired ? .semibold : .regular))
                    .foregroundStyle(item.expired ? Theme.destructive : Theme.inkSoft)
                    .lineLimit(1)
                if let inviter = invitation.inviterName.nonEmpty {
                    Text(LF("Invited by %@", inviter)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
            }
            .padding(.leading, 52)
            HStack(spacing: 6) {
                if canInvite {
                    PMButton(L("Send again"), systemImage: "send", variant: .outline, size: .compact, isWorking: busyId == invitation.id) { sendAgain(item) }
                }
                Menu {
                    Button { copyMessage(item) } label: { GlyphLabel(L("Copy a message for them"), icon: "copy") }
                    if canInvite {
                        Divider()
                        Button(role: .destructive) { cancelTarget = item } label: {
                            GlyphLabel(item.expired ? L("Remove from the list") : L("Cancel invitation"), icon: "trash-2")
                        }
                    }
                } label: {
                    IconCircleLabel(bordered: false)
                }
                .accessibilityLabel(LF("More for %@", item.shownName))
            }
            .padding(.leading, 52)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func copyMessage(_ item: TeamOpenInvitation) {
        UIPasteboard.general.string = TeamText.invitationMessage(name: item.invitation.inviteeName, email: item.invitation.email, workspace: workspace.current?.name ?? "PawMiaw")
        Toast.show(LF("Message copied. Send it to %@.", item.invitation.email))
    }

    private func sendAgain(_ item: TeamOpenInvitation) {
        guard let clinicId = workspace.current?.clinicId else { return }
        busyId = item.invitation.id
        Task {
            defer { busyId = nil }
            do {
                try await API.send("POST", "/provider-workspaces/\(clinicId)/invitations/\(item.invitation.id)/resend")
                Toast.show(LF("Sent again to %@. They have 48 more hours.", item.invitation.email))
                await load()
            } catch {
                Toast.error(error)
            }
        }
    }

    private func cancel(_ item: TeamOpenInvitation) async throws {
        guard let clinicId = workspace.current?.clinicId else { return }
        try await API.send("POST", "/provider-workspaces/\(clinicId)/invitations/\(item.invitation.id)/cancel")
        Toast.show(item.expired ? L("Invitation removed.") : L("Invitation cancelled."))
        await load()
    }

    // MARK: Roles

    @ViewBuilder
    private var rolesPanel: some View {
        if roles == nil && !membersLoaded {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        } else if let roles {
            let has = Dictionary(uniqueKeysWithValues: roles.map { ($0.role, Set($0.permissions)) })
            let groups = TeamPermissions.search(query)
            let columns = sizeClass == .regular ? TeamRole.all : [shownRole]
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Five roles come with PawMiaw. A role is where each person starts; what one person needs differently is turned on or off on their page."))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8, alignment: .top)], spacing: 8) {
                    ForEach(TeamRole.all, id: \.self) { role in roleCard(role) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .overlay(alignment: .bottom) { RowDivider() }
            if sizeClass != .regular {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(TeamRole.all, id: \.self) { role in
                            FilterChip(title: TeamRole.label(role), isSelected: shownRole == role, tone: TeamRole.hue(role).color, icon: TeamRole.icon(role)) { shownRole = role }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .overlay(alignment: .bottom) { RowDivider() }
            }
            if groups.isEmpty {
                EmptyState(systemImage: "search", title: LF("No permission matches “%@”.", query.trimmingCharacters(in: .whitespaces)), message: L("Try another word, like “refund”, “records” or “hours”."), actionTitle: L("Show every permission"), action: { query = "" }, accent: Theme.pink)
            } else {
                if columns.count > 1 {
                    HStack(alignment: .bottom, spacing: 8) {
                        Text(L("Permission").uppercased()).font(.brandText(10.6, weight: .heavy)).tracking(1.3).foregroundStyle(Theme.inkSoft)
                        Spacer()
                        ForEach(columns, id: \.self) { role in
                            Text(TeamRole.label(role)).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkStrong).frame(width: 88).multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .overlay(alignment: .bottom) { RowDivider() }
                }
                ForEach(groups, id: \.key) { group in
                    Text(L(group.title).uppercased())
                        .font(.brandText(11.2, weight: .heavy)).tracking(1.3).foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.wash(Theme.surfaceMuted, 55))
                        .overlay(alignment: .bottom) { RowDivider() }
                    ForEach(group.permissions, id: \.key) { permission in
                        HStack(alignment: columns.count > 1 ? .center : .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(L(permission.label)).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                                Text(L(permission.description)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer(minLength: 4)
                            ForEach(columns, id: \.self) { role in
                                let on = has[role]?.contains(permission.key) ?? false
                                mark(on).frame(width: columns.count > 1 ? 88 : 24)
                                    .accessibilityLabel(on ? LF("%@: yes", TeamRole.label(role)) : LF("%@: no", TeamRole.label(role)))
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .overlay(alignment: .bottom) { RowDivider() }
                    }
                }
            }
        } else {
            VStack(spacing: 4) {
                Text(L("The roles couldn’t load.")).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
                Text(L("Check your connection and try again.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                PMButton(L("Try again"), systemImage: "refresh-cw", variant: .outline, size: .compact) {
                    Task {
                        let answer: TeamRolesResponse? = try? await API.get("/provider-workspace-roles")
                        roles = answer?.roles
                    }
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 24).padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
    }

    private func roleCard(_ role: String) -> some View {
        let count = roleCounts[role] ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Glyph(TeamRole.icon(role), size: 14).foregroundStyle(Theme.inkStrong)
                    .frame(width: 28, height: 28)
                    .background(Theme.wash(TeamRole.hue(role).color, 30), in: Circle())
                Text(TeamRole.label(role)).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
            }
            Text(TeamRole.summary(role)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).frame(maxWidth: .infinity, alignment: .leading)
            if count > 0 {
                Button(LP(count, "1 person", "%d people")) {
                    query = ""; view = .people; roleFilter = role; visitsOnly = false; suspendedOnly = false
                }
                .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue)
                .padding(.top, 2)
            } else {
                Text(L("Nobody yet")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).padding(.top, 2)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    /// Yes in the app's green, no as a quiet dash — never by colour alone.
    private func mark(_ on: Bool) -> some View {
        Group {
            if on {
                Glyph("check", size: 14).foregroundStyle(Theme.inkStrong)
                    .frame(width: 24, height: 24).background(Theme.wash(ProviderState.done.color, 30), in: Circle())
            } else {
                Glyph("minus", size: 14).foregroundStyle(Theme.inkSoft.opacity(0.55)).frame(width: 24, height: 24)
            }
        }
    }
}

/// One person of the team (web `MemberRow`, phone layout): who, their role and
/// access, how they take visits and where, when they were here; the row opens them.
struct TeamMemberRow: View {
    let member: TeamMember
    let locations: [ProviderLocation]

    var body: some View {
        let suspended = member.isSuspended
        let place = locations.count >= 2 ? (TeamText.locationNames(role: member.role, ids: member.locationIds, locations: locations) ?? L("Every location")) : nil
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Avatar(name: member.shownName, imageURL: member.image, size: 40, tint: TeamRole.hue(member.role).color)
                    .opacity(suspended ? 0.6 : 1)
                    .grayscale(suspended ? 1 : 0)
                VStack(alignment: .leading, spacing: 2) {
                    FlowLayout(spacing: 8) {
                        Text(member.shownName).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        if member.isMe { Chip(text: L("You"), tone: .custom(Theme.blue), percent: 14, ink: Theme.inkOnBright) }
                        if suspended { teamSuspendedChip() }
                        if member.overSeatLimit == true { Chip(text: L("Over the plan"), tone: .custom(Theme.mango), percent: 24, ink: Theme.inkOnBright) }
                    }
                    Text(member.titleLine.nonEmpty ?? member.email.nonEmpty ?? L("No email")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 0)
                Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
            }
            VStack(alignment: .leading, spacing: 4) {
                teamRoleChip(member.role)
                Text(suspended ? L("No access while suspended") : TeamPermissions.accessLine(member))
                    .font(Theme.text(12, weight: member.hasCustomAccess ? .semibold : .regular))
                    .foregroundStyle(member.hasCustomAccess ? Theme.inkStrong : Theme.inkSoft)
                    .lineLimit(1)
            }
            .padding(.leading, 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(suspended ? L("Not booked while suspended") : (member.takesVisits ? (member.atOnce > 1 ? LF("%d pets at once", member.atOnce) : L("One pet at a time")) : L("Doesn’t take visits")))
                    .font(Theme.text(14, weight: member.takesVisits && !suspended ? .semibold : .regular))
                    .foregroundStyle(member.takesVisits && !suspended ? Theme.inkStrong : Theme.inkSoft)
                if let place {
                    HStack(spacing: 4) { Glyph("map-pin", size: 12); Text(place).lineLimit(1) }
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.leading, 52)
            VStack(alignment: .leading, spacing: 0) {
                Text(member.isMe ? L("Now") : TeamText.lastActive(member.lastActiveAt)).font(Theme.text(14)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                Text(LF("Joined %@", TeamText.shortDate(member.createdAt))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            .padding(.leading, 52)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

/// "Suspendido" beside a name: access paused, still on the team (web `SuspendedChip`): the kit's
/// chip on a red wash with a red pause.
func teamSuspendedChip() -> Chip {
    Chip(text: L("Suspended"), tone: .custom(Theme.destructive), icon: "circle-pause", percent: 10, ink: Theme.inkStrong,
         iconInk: AnyShapeStyle(Theme.destructive), border: 45, size: .medium)
}
