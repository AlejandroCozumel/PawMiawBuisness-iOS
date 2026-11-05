//
//  StaffMemberScreen.swift
//  PawMiawNegocios
//
//  One person on the team (web: routes/provider.staff.$memberId.tsx): who
//  they are, what they can do, how they take visits and where, their hours
//  and days off, what is coming up, and suspending or removing them.
//  Nobody changes their own access, the owner's, or a suspended person's.
//  The server rewrites every profile field and both override lists on each
//  save, so every save sends the whole person with only its part changed.
//

import SwiftUI

struct StaffMemberScreen: View {
    let memberId: String

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var member: TeamMember?
    @State private var roles: [TeamRolePermissions]?
    @State private var loadError: String?
    @State private var notFound = false
    @State private var upcoming: [TeamVisit] = []
    @State private var upcomingTotal = 0
    @State private var upcomingLoading = true
    @State private var upcomingFailed = false
    @State private var booked: Int?
    @State private var online: TeamOnlineSettings?
    @State private var onlineLoaded = false
    @State private var hours: TeamMemberHours?
    @State private var hoursError: String?
    @State private var accessOpen = false
    @State private var suspendOpen = false
    @State private var removeOpen = false
    @State private var reactivating = false
    @State private var removed = false
    /// "See them in the Schedule" from a sheet: the sheet closes, then the Schedule opens with this person.
    @State private var scheduleAfterSheet = false
    @State private var showSchedule = false
    @State private var pushed: ProviderRoute?

    private var clinicId: String? { workspace.current?.clinicId }
    private var canEdit: Bool { workspace.can(.staffEditRoles) }
    private var canRemove: Bool { workspace.can(.staffRemove) }
    private var canSeeVisits: Bool { workspace.can(.appointmentsView) }

    var body: some View {
        Group {
            if !workspace.can(.staffView) {
                PageScroll { NoAccessState(message: L("Ask the workspace owner to let your role see staff.")) }
            } else if let member {
                page(member)
            } else if notFound {
                PageScroll {
                    EmptyState(systemImage: "user-round", title: L("This person isn’t on the team"), message: L("They may have been removed, or the link is from another workspace."), actionTitle: L("Back to the team"), action: { dismiss() }, accent: Theme.pink, panel: true)
                }
            } else if loadError != nil {
                PageScroll {
                    EmptyState(systemImage: "user-round", title: L("This person couldn’t load."), message: L("Check your connection and try again."), actionTitle: L("Try again"), action: { Task { await load() } }, accent: Theme.pink, panel: true)
                }
            } else {
                LoadingState()
            }
        }
        .providerPage(member?.shownName ?? L("Team member"))
        .reloadsOnScope { await load() }
        .navigationDestination(item: $pushed) { RouteView(route: $0) }
    }

    // MARK: Loading

    private func load() async {
        guard let clinicId, workspace.can(.staffView) else { return }
        do {
            let loaded: TeamMember = try await API.get("/provider-workspaces/\(clinicId)/members/\(memberId)")
            member = loaded
            loadError = nil
            notFound = false
        } catch let error as APIError where error.status == 404 {
            notFound = true
            return
        } catch {
            if member == nil { loadError = errorText(error) }
            return
        }
        if roles == nil {
            let answer: TeamRolesResponse? = try? await API.get("/provider-workspace-roles")
            roles = answer?.roles
        }
        await loadVisits()
        online = try? await API.get("/provider-online-booking/settings")
        onlineLoaded = true
        await loadHours()
    }

    private func loadVisits() async {
        guard canSeeVisits else { return }
        let from = DateText.iso(Date())
        do {
            let page: Page<TeamVisit> = try await API.get("/provider-appointments", query: ["limit": "6", "offset": "0", "from": from, "assignedOrganizationMemberId": memberId])
            upcoming = Array(page.items.filter { $0.status != "cancelled" && $0.status != "no_show" }.prefix(5))
            upcomingTotal = page.total ?? page.items.count
            upcomingFailed = false
        } catch {
            upcomingFailed = true
        }
        upcomingLoading = false
        let scheduled: Page<TeamVisit>? = try? await API.get("/provider-appointments", query: ["limit": "1", "offset": "0", "from": from, "status": "scheduled", "assignedOrganizationMemberId": memberId])
        booked = scheduled?.total
    }

    private func loadHours() async {
        do {
            hours = try await API.get("/provider-hours/members/\(memberId)")
            hoursError = nil
        } catch {
            hoursError = errorText(error)
        }
    }

    // MARK: Saving

    private struct Changes {
        var role: String?
        var allow: [String]?
        var deny: [String]?
        var profile: TeamProfileFields?
        var maxConcurrentVisits: Int?
        var locationIds: [String]?
    }

    private func save(_ changes: Changes) async throws {
        guard let clinicId, let member else { return }
        func text(_ value: String?) -> String? { value?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
        var body: [String: Any?] = [
            "role": changes.role ?? member.roleKey,
            "permissionAllow": changes.allow ?? member.allow,
            "permissionDeny": changes.deny ?? member.deny,
            "displayName": text(changes.profile?.displayName ?? member.displayName),
            "professionalTitle": text(changes.profile?.professionalTitle ?? member.professionalTitle),
            "specialty": text(changes.profile?.specialty ?? member.specialty),
            // Written before credentials had their own card: kept as it is, never edited here.
            "credentialLabel": text(member.credentialLabel),
            "credentialValue": text(member.credentialValue),
            "profileNotes": text(changes.profile?.profileNotes ?? member.profileNotes),
        ]
        if let value = changes.maxConcurrentVisits { body["maxConcurrentVisits"] = value }
        // Sent only when changed: left out, the server keeps where they work.
        if let ids = changes.locationIds { body["locationIds"] = ids }
        let updated: TeamMember = try await API.patch("/provider-workspaces/\(clinicId)/members/\(member.id)", body: body)
        self.member = updated
        await Workspace.shared.refresh()
        announceDataChanged()
    }

    private func change(_ action: String) async throws {
        guard let clinicId, let member else { return }
        let updated: TeamMember = try await API.post("/provider-workspaces/\(clinicId)/members/\(member.id)/\(action)")
        self.member = updated
        await Workspace.shared.refresh()
        announceDataChanged()
    }

    private func reactivate() {
        guard let member else { return }
        reactivating = true
        Task {
            defer { reactivating = false }
            do {
                try await change("reactivate")
                Toast.show(LF("%@ has their access back, as it was.", member.shownName))
            } catch { Toast.error(error) }
        }
    }

    // MARK: Page

    @ViewBuilder
    private func page(_ member: TeamMember) -> some View {
        let suspended = member.isSuspended
        let isOwner = member.roleKey == "owner"
        // Nobody changes their own access, the owner's, or — until they are back — a suspended person's.
        let canEditAccess = canEdit && !isOwner && !member.isMe && !suspended
        let canPause = canRemove && !member.isMe && !isOwner
        let defaults = TeamPermissions.roleDefaults(roles, member.roleKey)
        let waitingAccess = suspended ? defaults.map { TeamPermissions.effective(defaults: $0, allow: member.allow, deny: member.deny) } : nil
        let wouldTakeVisits = suspended ? (waitingAccess?.contains(Permission.appointmentsComplete.rawValue) ?? false) : member.takesVisits
        let prescribes = workspace.offers(.vet, .emergency)
        let signs = (suspended ? (waitingAccess ?? []) : member.effective).contains(Permission.recordsApprove.rawValue)
        let credentialsShown = prescribes ? (member.roleKey == "vet" || signs) : member.roleKey != "receptionist"
        let locations = workspace.activeLocations

        ScrollViewReader { proxy in
            PageScroll(refresh: { await load() }) {
                header(member, suspended: suspended, isOwner: isOwner, wouldTakeVisits: wouldTakeVisits, proxy: proxy)
                if suspended { suspendedNotice(member, canPause: canPause) }

                TeamMemberProfileCard(member: member, canEdit: canEdit, credentialsShown: credentialsShown) { fields in
                    try await save(Changes(profile: fields))
                } onUploadPhoto: { data in
                    guard let clinicId else { return }
                    let _: EmptyResponse = try await API.upload("/provider-workspaces/\(clinicId)/members/\(member.id)/photo", fileField: "photo", fileName: "photo.jpg", mimeType: "image/jpeg", fileData: data)
                    await load()
                }

                TeamMemberAccessCard(member: member, canEdit: canEditAccess, roleAccess: waitingAccess) { accessOpen = true }
                    .id("access")
                if canEdit && member.isMe && !isOwner {
                    Text(L("This is your own access: someone else who can change roles has to change it.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 4).padding(.top, -8)
                }

                if credentialsShown {
                    TeamCredentialsCard(memberId: member.id, isSelf: member.isMe, canEdit: canEdit, prescribing: prescribes, memberName: member.shownName)
                }
                // The professional signature printed on what this person signs: only on their own page.
                if member.isMe {
                    MySignatureCard(suggestedName: member.shownName)
                }

                TeamMemberVisitsCard(member: member, canEdit: canEdit, takesVisits: wouldTakeVisits) { value in
                    try await save(Changes(maxConcurrentVisits: value))
                }
                .id("visits")

                if wouldTakeVisits {
                    TeamMemberOnlineCard(memberId: member.id, name: member.shownName, canEdit: canEdit || workspace.can(.workspaceEdit), settings: online, loaded: onlineLoaded) { online = $0 }
                    TeamServiceAreaCard(memberId: member.id, name: member.shownName, canEdit: canEdit)
                }
                if locations.count >= 2 {
                    TeamMemberLocationsCard(member: member, locations: locations, canEdit: canEdit) { ids in
                        try await save(Changes(locationIds: ids))
                    }
                }
                if wouldTakeVisits {
                    TeamMemberHoursCards(member: member, hours: hours, error: hoursError, canEdit: canEdit, onSaved: { hours = $0 }, retry: { await loadHours() })
                    if workspace.can(.workspaceEdit) {
                        NavigationLink(value: ProviderRoute.section(.availability)) {
                            Text(L("Change the opening hours")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                    }
                    TeamMemberTimeOffCard(member: member, hours: hours, canEdit: canEdit, reload: loadHours)
                }
                if canSeeVisits {
                    TeamMemberUpcomingCard(name: member.shownName, visits: upcoming, total: upcomingTotal, loading: upcomingLoading, failed: upcomingFailed, memberId: member.id)
                }
                // Their questions to Olfato AI: whoever reads the team's use, and the person themself (the server's rule).
                if TeamOlfatoAccess.seesTeam(workspace) || member.isMe {
                    TeamMemberOlfatoCard(memberId: member.id, isSelf: member.isMe, name: member.shownName, seesTeam: TeamOlfatoAccess.seesTeam(workspace))
                }

                if canPause {
                    onTheTeam(member, suspended: suspended)
                } else if member.isMe {
                    Text(isOwner ? L("This is you, the owner. The owner can’t be suspended, removed or changed to another role.") : L("This is you. To leave the workspace, ask the owner to remove you."))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.horizontal, 4)
                } else if isOwner {
                    Text(L("The owner can’t be suspended, removed or changed to another role.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.horizontal, 4)
                }

                AuditHistoryCard(entityType: "clinic_member", entityId: member.id, title: L("History"), description: L("Every change to this person’s profile, role, permissions, hours and days off, and who made it."), collapsible: false, emptyText: L("No changes yet."))
            }
        }
        .sheet(isPresented: $accessOpen) {
            TeamAccessSheet(member: member, roles: roles, actorPermissions: workspace.current?.effectivePermissions ?? [], actorManagesPlan: workspace.current?.canManagePlan ?? false) { role, allow, deny in
                try await save(Changes(role: role, allow: allow, deny: deny))
            }
        }
        .navigationDestination(isPresented: $showSchedule) {
            RouteView(route: .schedule(Self.agenda(member.id)))
        }
        .sheet(isPresented: $suspendOpen, onDismiss: openScheduleIfAsked) {
            TeamConfirmSheet(title: LF("Suspend %@?", member.shownName), message: L("Their access stops right away. Nothing is erased, and you can give it back whenever you want."), confirmTitle: L("Suspend access"), cancelTitle: L("Keep them active")) {
                try await change("suspend")
                Toast.show(LF("%@ is suspended. Reactivate them here whenever you want.", member.shownName))
            } content: {
                TeamPersonLine(name: member.shownName, image: member.image, detail: [TeamRole.label(member.role), member.email].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                TeamConsequences(lines: [
                    L("They can’t open this workspace, and stop getting its notices."),
                    L("Families can’t book them online, and the Schedule stops offering them for new visits."),
                    L("Their role, permissions, hours and days off wait as they are."),
                    L("They keep their seat on the plan."),
                ])
                bookedNotice(kind: "suspend")
            }
        }
        .sheet(isPresented: $removeOpen, onDismiss: { if removed { dismiss() } else { openScheduleIfAsked() } }) {
            TeamConfirmSheet(title: LF("Remove %@?", member.shownName), message: L("They leave the team and lose this workspace right away."), confirmTitle: L("Remove from the team"), cancelTitle: L("Keep them")) {
                guard let clinicId else { return }
                try await API.send("DELETE", "/provider-workspaces/\(clinicId)/members/\(member.id)")
                Toast.show(LF("%@ is no longer on the team.", member.shownName))
                removed = true
                await Workspace.shared.refresh()
                announceDataChanged()
            } content: {
                TeamPersonLine(name: member.shownName, image: member.image, detail: [TeamRole.label(member.role), member.email].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                TeamConsequences(lines: [
                    L("They can no longer open visits, clients, records or money here."),
                    L("What they wrote and signed stays in the records."),
                    L("Their own hours and days off are erased, and their seat on the plan is free again."),
                    L("You can invite them again later; they would start from the role you choose then."),
                ])
                bookedNotice(kind: "remove")
                Text(L("Coming back soon? Suspend them instead: nothing is lost.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    /// The Schedule's list of what is coming up for this person (the web's `agendaSearch`).
    static func agenda(_ memberId: String) -> ScheduleFilter {
        ScheduleFilter(memberId: memberId, view: "list")
    }

    private func openScheduleIfAsked() {
        guard scheduleAfterSheet else { return }
        scheduleAfterSheet = false
        showSchedule = true
    }

    /// Their visits still to come, with the way to them (web `BookedVisitsNotice`).
    @ViewBuilder
    private func bookedNotice(kind: String) -> some View {
        if let visits = booked, visits > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text(kind == "remove"
                     ? LP(visits, "They still have 1 visit coming up. It will be left with nobody: give it to someone else first.", "They still have %d visits coming up. They will be left with nobody: give them to someone else first.")
                     : LP(visits, "They still have 1 visit coming up. It stays booked with them: give it to someone else, or keep it for when they are back.", "They still have %d visits coming up. They stay booked with them: give them to someone else, or keep them for when they are back."))
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                Button {
                    scheduleAfterSheet = true
                    suspendOpen = false
                    removeOpen = false
                } label: {
                    HStack(spacing: 6) {
                        Glyph("calendar-days", size: 16)
                        Text(visits == 1 ? L("See it in the Schedule") : L("See them in the Schedule"))
                    }
                    .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wash(Theme.mango, 12), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.mango, 55, with: Theme.borderSoft), lineWidth: 1))
        }
    }

    private func header(_ member: TeamMember, suspended: Bool, isOwner: Bool, wouldTakeVisits: Bool, proxy: ScrollViewProxy) -> some View {
        let canEditAccess = canEdit && !isOwner && !member.isMe && !suspended
        let canPause = canRemove && !member.isMe && !isOwner
        let tone = TeamRole.hue(member.role).color
        var stats: [ModuleStat] = [
            ModuleStat("role", label: L("Role"), value: TeamRole.label(member.role),
                       hint: suspended ? L("No access while suspended") : isOwner ? L("Full access") : (member.hasCustomAccess ? L("Fine-tuned for them") : L("The role’s access")),
                       icon: "shield-check", accent: tone, action: { withAnimation { proxy.scrollTo("access", anchor: .top) } }),
            ModuleStat("capacity", label: L("Pets at once"), value: wouldTakeVisits ? "\(member.atOnce)" : "—",
                       hint: suspended ? L("Not booked while suspended") : (member.takesVisits ? L("Before a double booking") : L("Doesn’t take visits")),
                       icon: "layers", accent: Theme.mango, action: { withAnimation { proxy.scrollTo("visits", anchor: .top) } }),
        ]
        if canSeeVisits {
            stats.append(ModuleStat("booked", label: L("Coming up"), value: booked.map(String.init) ?? "—", hint: L("Booked visits"),
                                    icon: "calendar-days", accent: Theme.aqua, attention: suspended && (booked ?? 0) > 0,
                                    action: { pushed = .schedule(Self.agenda(member.id)) }))
        }
        stats.append(ModuleStat("active", label: L("Last active"), value: member.isMe ? L("Now") : TeamText.lastActive(member.lastActiveAt),
                                hint: member.isMe ? L("This is you") : LF("Joined %@", TeamText.shortDate(member.createdAt)),
                                icon: "activity", accent: Theme.pink))
        let subtitle = member.titleLine.nonEmpty.map { [$0, member.email].compactMap { $0?.nonEmpty }.joined(separator: " · ") } ?? member.email.nonEmpty ?? TeamRole.label(member.role)
        return ModuleHeader(
            icon: "user-round",
            title: member.shownName,
            subtitle: subtitle,
            accent: tone,
            // The person's photo (or initials) fills the header's round, whatever size it is drawn at.
            media: AnyView(GeometryReader { box in Avatar(name: member.shownName, imageURL: member.image, size: box.size.width, tint: Theme.aqua) }),
            stats: stats,
            storageKey: "staff-member"
        ) {
            if canEditAccess {
                PMButton(L("Change access"), systemImage: "shield-check") { accessOpen = true }
            } else if suspended && canPause {
                PMButton(L("Reactivate"), systemImage: "circle-play", isWorking: reactivating) { reactivate() }
            }
        }
    }

    private func suspendedNotice(_ member: TeamMember, canPause: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                FlowLayout(spacing: 8) {
                    teamSuspendedChip()
                    if let since = member.suspendedAt {
                        Text(LF("Since %@", TeamText.shortDate(since))).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                    }
                }
                Text(LF("%@ can’t open this workspace and isn’t offered for new visits. Their role, permissions, hours and days off wait as they are.", member.shownName))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                if canSeeVisits, let booked, booked > 0 {
                    Button { pushed = .schedule(Self.agenda(member.id)) } label: {
                        Text(LP(booked, "1 visit is still booked with them", "%d visits are still booked with them")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            if canPause {
                PMButton(L("Reactivate"), systemImage: "circle-play", isWorking: reactivating) { reactivate() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(Theme.destructive, 6), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.mix(Theme.destructive, 40, with: Theme.borderSoft), lineWidth: 2))
    }

    /// "En el equipo": suspend or remove (web: the card with the coral edge).
    private func onTheTeam(_ member: TeamMember, suspended: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("On the team")).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { RowDivider() }
            if !suspended {
                teamAction(L("Suspend access"), L("For a leave or while something is sorted out. They can’t get in; nothing is erased, and you give it back with one tap.")) {
                    PMButton(L("Suspend"), systemImage: "circle-pause", variant: .outline, size: .compact) { suspendOpen = true }
                }
                RowDivider()
            }
            teamAction(L("Remove from the team"), L("For someone who no longer works here. They lose access right away; you can invite them again later.")) {
                PMButton(L("Remove"), systemImage: "user-minus", variant: .destructive, size: .compact) { removeOpen = true }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.mix(Theme.destructive, 30, with: Theme.borderSoft), lineWidth: 1))
        .cardShadow()
    }

    private func teamAction<Action: View>(_ title: String, _ text: String, @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                Text(text).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            action()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
