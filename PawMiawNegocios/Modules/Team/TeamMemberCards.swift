//
//  TeamMemberCards.swift
//  PawMiawNegocios
//
//  The cards of a person's page (web: components/app/staff/member-*.tsx):
//  their profile, what they can do, how many pets at once, online booking
//  ("Recibe reservas en línea", "Servicios que hace"), where they work,
//  where they go for home visits, and what is coming up for them. Each card
//  that edits saves on its own.
//

import SwiftUI
import PhotosUI

// MARK: - Profile

struct TeamProfileFields: Equatable {
    var displayName = ""
    var professionalTitle = ""
    var specialty = ""
    var profileNotes = ""

    init() {}
    init(_ member: TeamMember) {
        displayName = member.displayName ?? ""
        professionalTitle = member.professionalTitle ?? ""
        specialty = member.specialty ?? ""
        profileNotes = member.profileNotes ?? ""
    }

    func same(_ other: TeamProfileFields) -> Bool {
        displayName.trimmingCharacters(in: .whitespaces) == other.displayName.trimmingCharacters(in: .whitespaces)
            && professionalTitle.trimmingCharacters(in: .whitespaces) == other.professionalTitle.trimmingCharacters(in: .whitespaces)
            && specialty.trimmingCharacters(in: .whitespaces) == other.specialty.trimmingCharacters(in: .whitespaces)
            && profileNotes.trimmingCharacters(in: .whitespacesAndNewlines) == other.profileNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Who they are to the clinic and its families: the name shown, photo, title, specialty, notes.
struct TeamMemberProfileCard: View {
    let member: TeamMember
    let canEdit: Bool
    let credentialsShown: Bool
    let onSave: (TeamProfileFields) async throws -> Void
    let onUploadPhoto: (Data) async throws -> Void

    @State private var draft = TeamProfileFields()
    @State private var started = false
    @State private var photo = PhotoDraft()
    @State private var saving = false
    @StateObject private var flash = TeamSavedFlash()

    private var saved: TeamProfileFields { TeamProfileFields(member) }
    private var dirty: Bool { !draft.same(saved) || photo.data != nil }

    var body: some View {
        TeamSaveSection(
            title: L("Profile"),
            subtitle: L("How they appear to the team and to families: on visits, records and report cards."),
            systemImage: "id-card",
            tint: Theme.aqua,
            state: flash.state(saving: saving, dirty: dirty),
            saveLabel: L("Save profile"),
            readOnlyText: canEdit ? nil : L("Only someone who can edit staff roles changes profiles."),
            onSave: canEdit ? { save() } : nil,
            onDiscard: { draft = saved; photo = PhotoDraft() }
        ) {
            PhotoField(label: L("Photo"), hint: photo.data != nil ? L("New photo chosen — save to keep it.") : L("JPG, PNG or WebP, up to 3 MB."), currentURL: member.image, draft: $photo, shape: .circle, allowsRemove: false)
                .disabled(!canEdit || saving)
            PMTextField(L("Name shown"), text: $draft.displayName, prompt: member.userName.nonEmpty ?? L("Their account name"), hint: LF("Leave empty to use their account name (%@).", member.userName.nonEmpty ?? member.email.nonEmpty ?? "—"), capitalization: .words)
                .disabled(!canEdit || saving)
            FormField(label: L("Email"), hint: L("Their sign-in email; only they can change it.")) {
                Text(member.email ?? "—").font(Theme.bodyFont).foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fieldChrome()
            }
            PMTextField(L("Title"), text: $draft.professionalTitle, prompt: L("Veterinarian, groomer, trainer…"))
                .disabled(!canEdit || saving)
            PMTextField(L("Specialty"), text: $draft.specialty, prompt: L("Dermatology, behaviour, cats…"))
                .disabled(!canEdit || saving)
            PMTextField(L("Notes for the team"), text: $draft.profileNotes, prompt: L("Languages, what they focus on, anything the team should know."), hint: L("Only the team sees these."), multiline: true)
                .disabled(!canEdit || saving)
            if credentialsShown {
                NoticeCard(tone: .info, title: L("Professional credentials"), message: member.credentialValue.nonEmpty.map { value in
                    LF("A licence was written here before: %@. Add it under Professional credentials so it is checked and counts for prescriptions.", [member.credentialLabel.nonEmpty, value].compactMap { $0 }.joined(separator: " "))
                } ?? L("Their cédula or licence goes under Professional credentials, where it is checked and counts for prescriptions."))
            }
        }
        .onAppear { if !started { draft = saved; started = true } }
        .onChange(of: member) { old, new in
            if draft.same(TeamProfileFields(old)) { draft = TeamProfileFields(new) }
        }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                if !draft.same(saved) { try await onSave(draft) }
            } catch {
                Toast.error(error)
                return
            }
            if let data = photo.data {
                do {
                    try await onUploadPhoto(data)
                    photo = PhotoDraft()
                } catch {
                    Toast.error(LF("The details were saved, but the photo didn’t upload: %@", errorText(error)))
                    return
                }
            }
            flash.mark()
        }
    }
}

// MARK: - Role and access

/// What this person can do, read the way a person would say it.
struct TeamMemberAccessCard: View {
    let member: TeamMember
    let canEdit: Bool
    /// What they can do once active again, for someone suspended.
    let roleAccess: [String]?
    let onEdit: () -> Void
    @State private var everyOpen = false

    var body: some View {
        let effective = member.isSuspended ? (roleAccess ?? []) : member.effective
        let groups = TeamPermissions.byGroup(effective)
        let some = groups.filter { !$0.on.isEmpty }
        let none = groups.filter { $0.on.isEmpty }
        let limits = TeamPermissions.limits(effective)
        let added = Set(member.allow), removed = Set(member.deny)
        TeamPanel(
            title: L("Role and access"),
            subtitle: member.isSuspended ? LF("What waits for %@ once they are reactivated.", member.shownName) : LF("What %@ can see and do in this workspace.", member.shownName),
            systemImage: "shield-check",
            tint: Theme.lime
        ) {
            if canEdit {
                PMButton(L("Change access"), systemImage: "shield-check", variant: .outline, size: .compact, action: onEdit)
            }
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    teamRoleChip(member.role, large: true)
                    Text(TeamRole.summary(member.role)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                if !limits.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(limits, id: \.self) { limit in
                            HStack(alignment: .top, spacing: 8) {
                                Glyph("eye-off", size: 16).foregroundStyle(Theme.inkSoft).padding(.top, 2)
                                Text(limit).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                            }
                        }
                    }
                }
                if member.roleKey != "owner" && (!added.isEmpty || !removed.isEmpty) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LF("Changed just for %@", member.shownName)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        FlowLayout(spacing: 6) {
                            ForEach(member.allow, id: \.self) { permissionPill(TeamPermissions.label($0), icon: "plus", tone: Theme.blue, percent: 14) }
                            ForEach(member.deny, id: \.self) { permissionPill(TeamPermissions.label($0), icon: "minus", tone: Theme.destructive, percent: 12) }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.wash(Theme.mango, 9), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.mango, 50, with: Theme.borderSoft), lineWidth: 1))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8, alignment: .top)], spacing: 8) {
                    ForEach(some, id: \.group.key) { entry in
                        let all = entry.on.count == entry.group.permissions.count
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(L(entry.group.title)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(all ? L("Everything") : LF("%1$d of %2$d", entry.on.count, entry.group.permissions.count))
                                    .font(Theme.text(11.2, weight: .bold))
                                    .foregroundStyle(all ? Theme.inkStrong : Theme.inkSoft)
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(all ? AnyShapeStyle(Theme.wash(Theme.blue, 14)) : AnyShapeStyle(Theme.surfaceMuted), in: Capsule())
                            }
                            Text(entry.on.map { L($0.label) }.joined(separator: " · ")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                    }
                }
                if !none.isEmpty {
                    (Text(L("No access to:")).fontWeight(.semibold).foregroundColor(Theme.inkStrong) + Text(" " + none.map { L($0.group.title) }.joined(separator: ", ")))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                everyPermission(groups: groups, effective: effective, added: added, removed: removed)
            }
        }
    }

    private func permissionPill(_ text: String, icon: String, tone: Color, percent: Double) -> some View {
        HStack(spacing: 4) {
            Glyph(icon, size: 12)
            Text(text).lineLimit(1)
        }
        .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkStrong)
        .padding(.horizontal, 10).padding(.vertical, 2)
        .background(Theme.wash(tone, percent), in: Capsule())
    }

    /// "Cada permiso": every permission, folded away (web: the bordered collapse).
    private func everyPermission(groups: [(group: TeamPermissionGroup, on: [TeamPermissionInfo], off: [TeamPermissionInfo])], effective: [String], added: Set<String>, removed: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.2)) { everyOpen.toggle() } } label: {
                HStack(spacing: 10) {
                    Glyph("chevron-down", size: 16).rotationEffect(.degrees(everyOpen ? 0 : -90)).foregroundStyle(Theme.inkSoft)
                    Text(L("Every permission")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    Spacer()
                    Text(LF("%d on", effective.count)).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if everyOpen {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(groups, id: \.group.key) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L(entry.group.title).uppercased()).font(.brandText(11.2, weight: .heavy)).tracking(1.3).foregroundStyle(Theme.inkSoft)
                            ForEach(entry.group.permissions, id: \.key) { permission in
                                let on = effective.contains(permission.key)
                                HStack(alignment: .top, spacing: 8) {
                                    Glyph(on ? "check" : "x", size: 16).foregroundStyle(on ? Theme.blue : Theme.inkSoft).padding(.top, 2)
                                    FlowLayout(spacing: 6) {
                                        Text(L(permission.label)).font(Theme.text(14)).foregroundStyle(on ? Theme.inkStrong : Theme.inkSoft)
                                        if added.contains(permission.key) { Chip(text: L("added for them"), tone: .custom(Theme.lime), percent: 100, ink: Theme.inkOnBright, weight: .heavy) }
                                        if removed.contains(permission.key) { Chip(text: L("taken away for them"), tone: .custom(Theme.lime), percent: 100, ink: Theme.inkOnBright, weight: .heavy) }
                                    }
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityValue(on ? L("On") : L("Off"))
                            }
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { RowDivider() }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }
}

// MARK: - Visits

/// How many pets they take at once (the double-booking rule reads it).
struct TeamMemberVisitsCard: View {
    let member: TeamMember
    let canEdit: Bool
    let takesVisits: Bool
    let onSave: (Int) async throws -> Void
    @State private var value = 1
    @State private var saving = false
    @StateObject private var flash = TeamSavedFlash()

    var body: some View {
        TeamSaveSection(
            title: L("Visits"),
            subtitle: takesVisits ? LF("How %@ takes visits.", member.shownName) : LF("%@’s role doesn’t start or finish visits, so the Schedule doesn’t give them a column.", member.shownName),
            systemImage: "calendar-clock",
            tint: Theme.mango,
            state: flash.state(saving: saving, dirty: value != member.atOnce),
            readOnlyText: canEdit ? nil : L("Only someone who can edit staff roles changes this."),
            onSave: canEdit ? { save() } : nil,
            onDiscard: { value = member.atOnce }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                words
                TeamCountStepper(value: $value, disabled: !canEdit || saving)
            }
        }
        .onAppear { value = member.atOnce }
        .onChange(of: member.atOnce) { old, new in if value == old { value = new } }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("Pets at once")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
            Text(L("How many visits this person takes at the same time. A vet sees one; a groomer drying one dog while bathing another takes two. More than this is warned as a double booking."))
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do { try await onSave(value); flash.mark() } catch { Toast.error(error) }
        }
    }
}

// MARK: - Online booking

/// "Recibe reservas en línea" and "Servicios que hace" (backend docs/online-booking.md §4).
struct TeamMemberOnlineCard: View {
    let memberId: String
    let name: String
    let canEdit: Bool
    let settings: TeamOnlineSettings?
    /// The settings were asked for (nil after that: this reader can't see them).
    var loaded: Bool = true
    let onSaved: (TeamOnlineSettings) -> Void

    @State private var takes: Bool??
    @State private var serviceIds: [String]?
    @State private var pickingSome = false
    @State private var saving = false
    @State private var error: String?
    @StateObject private var flash = TeamSavedFlash()

    private var member: TeamOnlineMember? { settings?.team?.first(where: { $0.memberId == memberId }) }

    var body: some View {
        if let member {
            card(member)
        } else if settings == nil && !loaded {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func card(_ member: TeamOnlineMember) -> some View {
        let roleDefault = member.roleDefault ?? false
        let ownSwitch: Bool? = takes ?? member.takesOnlineBookings
        let isOn = ownSwitch ?? roleDefault
        let ids = serviceIds ?? member.serviceIds ?? []
        let savedIds = member.serviceIds ?? []
        let changed = (takes != nil && takes! != member.takesOnlineBookings) || (serviceIds != nil && Set(ids) != Set(savedIds))
        let dirty = changed || (pickingSome && ids.isEmpty && savedIds.isEmpty && isOn)
        let services = (settings?.services ?? []).filter { $0.onlineBookable ?? false }
        let chooseSome = !ids.isEmpty || pickingSome
        TeamSaveSection(
            title: L("Online booking"),
            subtitle: LF("Whether families can book a time with %@ from the app, and for what.", name),
            systemImage: "globe",
            tint: Theme.lavender,
            state: flash.state(saving: saving, dirty: dirty),
            readOnlyText: canEdit ? nil : L("Only someone who can edit staff roles changes this."),
            onSave: canEdit ? { save(takes: ownSwitch, ids: ids) } : nil,
            onDiscard: { takes = nil; serviceIds = nil; pickingSome = false; error = nil }
        ) {
            ToggleRow(
                title: L("Takes online bookings"),
                subtitle: ownSwitch == nil
                    ? (roleDefault ? LF("Yes, as their role says. Families can book a time with %@.", name) : L("No, as their role says (the front desk and admins don’t take visits)."))
                    : (isOn ? LF("Families can book a time with %@.", name) : LF("Families never get %@ when they book.", name)),
                isOn: Binding(get: { isOn }, set: { checked in error = nil; takes = .some(checked == roleDefault ? nil : checked) })
            )
            .disabled(!canEdit || (member.suspended ?? false))
            if member.suspended ?? false {
                Text(L("Suspended: never offered to families until they are back.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            if isOn {
                Text(L("Services they do")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                ChoiceCards(options: [
                    ("all", L("Every service their role does"), (member.signsRecords ?? false) ? L("Consults and emergencies too: they sign records.") : L("Consults and emergencies only go to someone who signs records.")),
                    ("some", L("Only these"), L("Families get them only for the services ticked.")),
                ], selection: Binding(get: { chooseSome ? "some" : "all" }, set: { next in
                    error = nil
                    if next == "all" { pickingSome = false; serviceIds = [] } else { pickingSome = true }
                }))
                .disabled(!canEdit)
                if chooseSome {
                    VStack(alignment: .leading, spacing: 4) {
                        if services.isEmpty {
                            Text(L("No service is booked online yet.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                            NavigationLink { TeamSettingsSectionScreen(section: "services") } label: {
                                Text(L("Choose them in Settings")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(services, id: \.serviceId) { service in
                            let on = ids.contains(service.serviceId)
                            Button {
                                error = nil
                                serviceIds = on ? ids.filter { $0 != service.serviceId } : ids + [service.serviceId]
                            } label: {
                                HStack(spacing: 10) {
                                    Tick(on: on)
                                    Text(service.label).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                                    Spacer(minLength: 0)
                                }
                                .frame(minHeight: 40)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!canEdit)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(error != nil ? Theme.destructive : Theme.borderSoft, lineWidth: error != nil ? 2 : 1))
                    if let error { Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
                }
            }
            let summary = offerSummary(offered: member.offered ?? false, dirty: dirty, takes: isOn)
            Text(summary.text).font(Theme.text(14, weight: summary.strong ? .semibold : .regular)).foregroundStyle(summary.strong ? Theme.inkStrong : Theme.inkSoft)
        }
    }

    /// Whether families are offered the person; a change not saved yet says so ("Sin guardar…").
    private func offerSummary(offered: Bool, dirty: Bool, takes: Bool) -> (text: String, strong: Bool) {
        if dirty && !takes { return (LF("Not saved yet: once you save, families won’t be offered %@.", name), true) }
        if dirty { return (L("Not saved yet: what families are offered changes once you save."), true) }
        return offered ? (LF("Families are offered %@ now, at the locations where they work.", name), false) : (LF("Families aren’t offered %@ now.", name), true)
    }

    private func save(takes: Bool?, ids: [String]) {
        if pickingSome && ids.isEmpty {
            error = L("Tick at least one service, or choose every service.")
            Toast.error(error ?? "")
            return
        }
        saving = true
        Task {
            defer { saving = false }
            do {
                let updated: TeamOnlineSettings = try await API.put("/provider-online-booking/team/\(memberId)", body: ["takesOnlineBookings": takes, "serviceIds": ids])
                self.takes = nil; serviceIds = nil; pickingSome = false
                onSaved(updated)
                flash.mark()
                announceDataChanged()
            } catch {
                Toast.error(error)
            }
        }
    }
}

// MARK: - Locations

/// Where this person works; none ticked means every location.
struct TeamMemberLocationsCard: View {
    let member: TeamMember
    let locations: [ProviderLocation]
    let canEdit: Bool
    let onSave: ([String]) async throws -> Void
    @State private var value: [String] = []
    @State private var saving = false
    @StateObject private var flash = TeamSavedFlash()

    private var saved: [String] {
        let active = Set(locations.map(\.id))
        return (member.locationIds ?? []).filter { active.contains($0) }
    }

    var body: some View {
        TeamSaveSection(
            title: L("Locations"),
            subtitle: value.isEmpty ? LF("%@ works at every location.", member.shownName) : LF("Where %@ works. Their Schedule column, registers and “today” follow it.", member.shownName),
            systemImage: "map-pin",
            tint: Theme.aqua,
            state: flash.state(saving: saving, dirty: Set(value) != Set(saved)),
            readOnlyText: canEdit ? nil : L("Only someone who can edit staff roles changes this."),
            onSave: canEdit ? { save() } : nil,
            onDiscard: { value = saved }
        ) {
            TeamLocationChoiceList(locations: locations, value: $value, disabled: !canEdit || saving)
        }
        .onAppear { value = saved }
        .onChange(of: member.locationIds ?? []) { _, _ in value = saved }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                // Every one ticked is the same as none: say "everywhere", so a new location includes them too.
                try await onSave(value.count == locations.count ? [] : value)
                flash.mark()
            } catch { Toast.error(error) }
        }
    }
}

// MARK: - Home visits area

private struct TeamServiceArea: Decodable {
    let postalCodes: [String]?
    let zones: [String]?
    let travelMinutes: Int?
}

/// Where a person goes for home visits, and the time they need between two homes.
struct TeamServiceAreaCard: View {
    let memberId: String
    let name: String
    let canEdit: Bool
    @State private var area: TeamServiceArea?
    @State private var failed = false
    @State private var postal = ""
    @State private var zones = ""
    @State private var travel = ""
    @State private var saving = false
    @StateObject private var flash = TeamSavedFlash()

    private func list(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private var travelValue: (ok: Bool, value: Int?) {
        let trimmed = travel.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return (true, nil) }
        guard let n = Int(trimmed), (0...180).contains(n) else { return (false, nil) }
        return (true, n)
    }
    private var dirty: Bool {
        guard let area else { return false }
        return list(postal) != (area.postalCodes ?? []) || list(zones) != (area.zones ?? []) || (travelValue.ok ? travelValue.value : -1) != area.travelMinutes
    }

    var body: some View {
        let anywhere = list(postal).isEmpty && list(zones).isEmpty
        TeamSaveSection(
            title: L("Home visits"),
            subtitle: anywhere ? LF("%@ goes anywhere. Add postal codes or zones to warn when a home visit is outside them.", name) : LF("Where %@ goes for walks, sitting and visits at home.", name),
            systemImage: "route",
            tint: Theme.mango,
            state: flash.state(saving: saving, dirty: dirty, valid: travelValue.ok),
            invalidText: LF("Travel time goes from 0 to %d minutes.", 180),
            readOnlyText: canEdit ? nil : L("Only someone who can edit staff roles changes this."),
            onSave: canEdit ? { save() } : nil,
            onDiscard: { fill() }
        ) {
            if area == nil {
                if failed { Text(L("Couldn’t load the service area.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) } else { ProgressView().frame(maxWidth: .infinity, minHeight: 64) }
            } else {
                PMTextField(L("Postal codes"), text: $postal, prompt: "06700, 067*", hint: L("Exact (06700) or every code that starts the same (067*). Enter or a comma adds one."), keyboard: .numbersAndPunctuation)
                    .disabled(!canEdit || saving)
                PMTextField(L("Zones"), text: $zones, prompt: L("Condesa, Roma Norte"), hint: L("Neighbourhoods by name, as they appear in addresses (Condesa, Roma Norte)."))
                    .disabled(!canEdit || saving)
                PMTextField(L("Travel time between homes"), text: $travel, prompt: "20", hint: L("Kept free between two home visits at different addresses. Empty: none."), keyboard: .numberPad)
                    .disabled(!canEdit || saving)
            }
        }
        .task(id: memberId) { await load() }
    }

    private func load() async {
        do {
            area = try await API.get("/provider-members/\(memberId)/service-area")
            fill()
        } catch { failed = true }
    }

    private func fill() {
        postal = (area?.postalCodes ?? []).joined(separator: ", ")
        zones = (area?.zones ?? []).joined(separator: ", ")
        travel = area?.travelMinutes.map(String.init) ?? ""
    }

    private func save() {
        guard travelValue.ok else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                area = try await API.put("/provider-members/\(memberId)/service-area", body: ["postalCodes": list(postal), "zones": list(zones), "travelMinutes": travelValue.value])
                fill()
                flash.mark()
            } catch { Toast.error(error) }
        }
    }
}

// MARK: - Coming up

/// Their next visits, each opening its visit page.
struct TeamMemberUpcomingCard: View {
    let name: String
    let visits: [TeamVisit]
    let total: Int
    let loading: Bool
    let failed: Bool
    /// The person, so "Open in the Schedule" opens their list.
    var memberId: String? = nil

    var body: some View {
        TeamPanel(title: L("Coming up"), subtitle: LF("Visits booked with %@.", name), systemImage: "calendar-days", tint: Theme.aqua) {
            if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 64)
            } else if failed {
                Text(L("Their visits couldn’t load. Try again in a moment.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            } else if visits.isEmpty {
                EmptyState(systemImage: "calendar-days", title: LF("Nothing booked with %@ from today on.", name), accent: Theme.pink)
            } else {
                VStack(spacing: 0) {
                    ForEach(visits) { visit in
                        if visit.id != visits.first?.id { RowDivider() }
                        NavigationLink(value: ProviderRoute.appointment(visit.id)) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text([visit.petName, visit.serviceLabel].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                                        .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                    Text([DateText.dayTime(visit.startsAt), visit.clientName.nonEmpty].compactMap { $0 }.joined(separator: " · "))
                                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(Self.statusLabel(visit.status))
                                    .font(Theme.text(11.2, weight: .bold)).foregroundStyle(Theme.inkSoft)
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Theme.surfaceMuted, in: Capsule())
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let memberId {
                NavigationLink(value: ProviderRoute.schedule(ScheduleFilter(memberId: memberId, view: "list"))) {
                    Text(total > visits.count ? LF("See all %d in the Schedule", total) : L("Open in the Schedule")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                }
                .buttonStyle(.plain)
            } else if total > visits.count {
                NavigationLink(value: ProviderRoute.section(.appointments)) {
                    Text(LF("See all %d in the Schedule", total)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    static func statusLabel(_ status: String?) -> String {
        switch status {
        case "requested": L("To confirm")
        case "scheduled": L("Booked")
        case "checked_in": L("Checked in")
        case "in_progress": L("In the visit")
        case "completed": L("Finished")
        case "cancelled": L("Cancelled")
        case "no_show": L("Didn’t come")
        default: status ?? ""
        }
    }
}
