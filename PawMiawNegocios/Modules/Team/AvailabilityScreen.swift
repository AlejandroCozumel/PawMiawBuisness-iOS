//
//  AvailabilityScreen.swift
//  PawMiawNegocios
//
//  Availability of one location (web: routes/provider.availability.tsx), in
//  the order it adds up: the opening hours (a week editor, the time zone),
//  the booking rules with online booking (on/off, "Yo confirmo cada
//  reserva" / "Se confirman solas", notice, how far ahead, "Las familias
//  cancelan solas hasta…"), what families see this week, closed dates, and
//  the team's hours. Each part saves on its own.
//

import SwiftUI

private struct TeamHoursDraft: Equatable {
    var timezone: String
    var week: [TeamDay]
}

private struct TeamBookingRules: Equatable {
    var duration: Int
    var buffer: Int
    var allowOnline: Bool
    var confirmByDefault: Bool
    var afterHours: Bool
    var notice: Int
    var horizon: Int?
    var confirmMode: String
    /// The business's late-cancel window (the store's policy); nil = not set (families read 24 h).
    var lateCancel: Int?
}

struct AvailabilityScreen: View {
    var body: some View {
        RequireLocation { TeamAvailabilityPage() }
            .providerPage(L("Availability"), root: true)
    }
}

private struct TeamAvailabilityPage: View {
    @EnvironmentObject private var workspace: Workspace

    @State private var server: TeamAvailability?
    @State private var loadError: String?
    @State private var online: TeamOnlineSettings?
    @State private var closures: [TeamClosure] = []
    @State private var closuresLoaded = false
    @State private var closuresError: String?
    @State private var people: [TeamMember] = []
    @State private var teamHours: [String: TeamMemberHours] = [:]
    @State private var teamReady = false
    @State private var hoursDraft: TeamHoursDraft?
    @State private var rulesDraft: TeamBookingRules?
    @State private var savingPart: String?
    @State private var copying = false
    @State private var pickingZone = false
    @State private var loadedFor: String??
    @StateObject private var hoursFlash = TeamSavedFlash()
    @StateObject private var rulesFlash = TeamSavedFlash()

    private var clinicId: String? { workspace.current?.clinicId }
    private var locationId: String? { workspace.locationId }
    private var canSeeStaff: Bool { workspace.can(.staffView) }
    private var otherLocations: [ProviderLocation] {
        workspace.activeLocations.filter { $0.id != workspace.selectedLocation?.id }
    }

    private var savedHours: TeamHoursDraft? {
        server.map { TeamHoursDraft(timezone: $0.timezone ?? "UTC", week: TeamHours.ordered($0.weeklySchedule ?? [])) }
    }
    private var savedRules: TeamBookingRules? {
        server.map { s in
            TeamBookingRules(
                duration: s.defaultAppointmentDurationMinutes ?? 30,
                buffer: s.defaultBufferMinutes ?? 0,
                allowOnline: s.allowOnlineBooking ?? false,
                confirmByDefault: s.requestAppointmentConfirmationByDefault ?? true,
                afterHours: s.allowAfterHoursBooking ?? true,
                notice: s.minBookingNoticeMinutes ?? 0,
                horizon: s.bookingHorizonDays,
                confirmMode: s.onlineConfirmMode ?? "approve",
                lateCancel: online?.lateCancelWindowHours
            )
        }
    }
    private var hours: TeamHoursDraft? { hoursDraft ?? savedHours }
    private var rules: TeamBookingRules? { rulesDraft ?? savedRules }
    private var hoursDirty: Bool { hoursDraft != nil && savedHours != nil && !(hoursDraft!.timezone == savedHours!.timezone && TeamHours.sameWeek(hoursDraft!.week, savedHours!.week)) }
    private var rulesDirty: Bool { rulesDraft != nil && rulesDraft != savedRules }

    var body: some View {
        Group {
            if !workspace.can(.workspaceEdit) {
                PageScroll { NoAccessState(message: L("Opening hours and booking rules are changed by someone who can edit the workspace. Ask the owner.")) }
            } else if workspace.inSetup {
                PageScroll {
                    header(stats: [])
                    EmptyState(systemImage: "building-2", title: L("Finish workspace setup before setting your hours."), message: L("Opening hours belong to a workspace, so its basics need to be saved first."), accent: Theme.aqua, panel: true)
                }
            } else if let hours, let rules {
                page(hours: hours, rules: rules)
            } else if loadError != nil {
                PageScroll {
                    header(stats: [])
                    VStack(spacing: 4) {
                        Text(L("The hours couldn’t load.")).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
                        Text(L("Check your connection and try again.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        PMButton(L("Try again"), systemImage: "refresh-cw", variant: .outline, size: .compact) { Task { await load() } }.padding(.top, 12)
                    }
                    .padding(.horizontal, 24).padding(.vertical, 48)
                    .frame(maxWidth: .infinity)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
            } else {
                PageScroll {
                    header(stats: [])
                    LoadingState()
                }
            }
        }
        .reloadsOnScope { await load() }
        // Leaving with unsaved hours or rules asks first.
        .modifier(TeamLeaveGuard(
            dirty: hoursDirty || rulesDirty,
            message: hoursDirty && rulesDirty
                ? L("The opening hours and the booking rules have changes that aren’t saved.")
                : hoursDirty ? L("The opening hours have changes that aren’t saved.") : L("The booking rules have changes that aren’t saved."),
            systemImage: "clock-3"
        ))
        .sheet(isPresented: $pickingZone) {
            TeamTimeZonePicker(selection: hours?.timezone ?? "UTC") { zone in
                if let hours { hoursFlash.clear(); hoursDraft = TeamHoursDraft(timezone: zone, week: hours.week) }
            }
        }
    }

    // MARK: Loading

    private func load() async {
        guard let clinicId, workspace.can(.workspaceEdit), !workspace.inSetup, !workspace.allLocationsChosen else { return }
        // Another location's hours start from what it has saved, not from this one's draft.
        if loadedFor != .some(locationId) {
            hoursDraft = nil
            rulesDraft = nil
            loadedFor = .some(locationId)
        }
        do {
            server = try await API.get("/provider-workspaces/\(clinicId)/availability", query: ["locationId": locationId])
            loadError = nil
        } catch {
            if server == nil { loadError = errorText(error) }
        }
        online = try? await API.get("/provider-online-booking/settings")
        await loadClosures()
        await loadTeam()
    }

    private func loadClosures() async {
        do {
            let answer: TeamClosuresResponse = try await API.get("/provider-hours/closures", query: ["locationId": locationId])
            closures = answer.closures
            closuresError = nil
        } catch {
            closuresError = errorText(error)
        }
        closuresLoaded = true
    }

    private func loadTeam() async {
        guard canSeeStaff, let clinicId else { return }
        guard let members: [TeamMember] = try? await API.get("/provider-workspaces/\(clinicId)/members") else { return }
        people = members.filter(\.takesVisits).sorted { $0.shownName.localizedCompare($1.shownName) == .orderedAscending }
        var found: [String: TeamMemberHours] = [:]
        for person in people {
            if let entry: TeamMemberHours = try? await API.get("/provider-hours/members/\(person.id)") { found[person.id] = entry }
        }
        teamHours = found
        teamReady = true
    }

    // MARK: Saving

    private func availabilityBody(hours: TeamHoursDraft?, rules: TeamBookingRules?) -> [String: Any?] {
        guard let server, let savedRules else { return [:] }
        let r = rules ?? savedRules
        var body: [String: Any?] = [
            "timezone": hours?.timezone ?? server.timezone ?? "UTC",
            "defaultAppointmentDurationMinutes": r.duration,
            "allowAfterHoursBooking": r.afterHours,
            "allowOnlineBooking": r.allowOnline,
            "requestAppointmentConfirmationByDefault": r.confirmByDefault,
            "defaultBufferMinutes": r.buffer,
            "minBookingNoticeMinutes": r.notice,
            "bookingHorizonDays": r.horizon,
            "onlineConfirmMode": r.confirmMode,
            "weeklySchedule": TeamHours.body(hours?.week ?? (server.weeklySchedule ?? [])),
        ]
        // The window is the business's, kept in the store's policy: sent only when it changed.
        if let rules, rules.lateCancel != savedRules.lateCancel { body["lateCancelWindowHours"] = rules.lateCancel }
        return body
    }

    private func save(_ part: String) {
        guard let clinicId else { return }
        let body = part == "hours" ? availabilityBody(hours: hoursDraft, rules: nil) : availabilityBody(hours: nil, rules: rulesDraft)
        var path = "/provider-workspaces/\(clinicId)/availability"
        if let locationId, let encoded = locationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { path += "?locationId=\(encoded)" }
        savingPart = part
        Task {
            defer { savingPart = nil }
            do {
                let updated: TeamAvailability = try await API.patch(path, body: body)
                server = updated
                if part == "hours" { hoursDraft = nil; hoursFlash.mark() } else {
                    online = try? await API.get("/provider-online-booking/settings")
                    rulesDraft = nil
                    rulesFlash.mark()
                }
                await Workspace.shared.refresh()
                announceDataChanged()
            } catch {
                Toast.error(error)
            }
        }
    }

    /// The week of another location, as a draft to look over and save here.
    private func copyWeek(from other: ProviderLocation) {
        guard let clinicId, let hours else { return }
        copying = true
        Task {
            defer { copying = false }
            do {
                let theirs: TeamAvailability = try await API.get("/provider-workspaces/\(clinicId)/availability", query: ["locationId": other.id])
                hoursFlash.clear()
                hoursDraft = TeamHoursDraft(timezone: hours.timezone, week: TeamHours.ordered(theirs.weeklySchedule ?? []))
                Toast.show(LF("%@’s week is here to look over. Save to keep it.", other.name))
            } catch { Toast.error(error) }
        }
    }

    // MARK: Page

    private func page(hours: TeamHoursDraft, rules: TeamBookingRules) -> some View {
        let stats = TeamHours.stats(hours.week)
        let summary = TeamHours.summary(hours.week)
        let today = TeamDays.today(hours.timezone)
        let nextClosure = TeamDays.sortSpans(closures.map { c -> (TeamClosure, String, String) in let n = TeamClosureMath.occurrence(c, from: today); return (c, n.startDay, n.endDay) }, today: today, start: { $0.1 }, end: { $0.2 }).current.first
        let checksHours = !rules.afterHours
        return ScrollViewReader { proxy in
            PageScroll(refresh: { await load() }) {
                header(stats: [
                    ModuleStat("open", label: L("Open days"), value: LF("%d of 7", stats.openDays),
                               hint: summary.filter(\.open).map(\.days).joined(separator: ", ").nonEmpty ?? L("Closed every day"),
                               icon: "calendar-check", accent: Theme.aqua, attention: stats.openDays == 0, action: { go(proxy, "hours") }),
                    ModuleStat("hours", label: L("Hours a week"), value: LF("%@ h", stats.hours.formatted()), hint: TeamHours.zoneLabel(hours.timezone),
                               icon: "hourglass", accent: Theme.blue, action: { go(proxy, "hours") }),
                    ModuleStat("closed", label: L("Next closed date"), value: !closuresLoaded || closuresError != nil ? "—" : (nextClosure.map { TeamDays.short($0.1) } ?? L("None")),
                               hint: nextClosure.map { $0.0.label.nonEmpty ?? TeamClosureMath.hoursText($0.0.ranges) } ?? (closuresLoaded ? L("Nothing coming up") : nil),
                               icon: "calendar-off", accent: Theme.pink, action: { go(proxy, "closures") }),
                    ModuleStat("buffer", label: L("Between visits"), value: rules.buffer == 0 ? L("No gap") : TeamHours.duration(rules.buffer),
                               hint: LF("Visits last %@", TeamHours.duration(rules.duration)),
                               icon: "calendar-clock", accent: Theme.mango, action: { go(proxy, "rules") }),
                    ModuleStat("online", label: L("Online booking"), value: rules.allowOnline ? L("On") : L("Off"),
                               hint: rules.allowOnline ? confirmModeLabel(rules.confirmMode) : (checksHours ? L("Hours are checked") : L("Hours are a guide")),
                               icon: "globe", accent: Theme.lime, action: { go(proxy, "rules") }),
                ])
                howItWorks(proxy)
                openingHours(hours, checksHours: checksHours).id("hours")
                bookingRules(rules).id("rules")
                TeamWeekPreviewCard(
                    days: preview(hours: hours, rules: rules, today: today),
                    online: rules.allowOnline,
                    notice: rules.notice,
                    horizon: rules.horizon,
                    canSeeStaff: canSeeStaff,
                    unsaved: hoursDirty || rulesDirty
                )
                .id("preview")
                TeamClosuresCard(
                    locationId: locationId,
                    timeZone: server?.timezone ?? hours.timezone,
                    weeklySchedule: savedHours?.week ?? hours.week,
                    canEdit: true,
                    otherLocations: otherLocations,
                    closures: closures,
                    loaded: closuresLoaded,
                    error: closuresError,
                    reload: { await loadClosures() }
                )
                .id("closures")
                teamCard(today: today).id("team")
                if let clinicId {
                    AuditHistoryCard(entityType: "clinic_availability", entityId: clinicId, title: L("History"), description: L("Every change to the hours and booking rules."), collapsible: false, emptyText: L("No changes yet."))
                }
            }
        }
    }

    /// The page's module header (web `ProviderModuleHeader`, Clock3 on aqua).
    private func header(stats: [ModuleStat]) -> some View {
        let subtitle: String = {
            if workspace.multiLocation, let selected = workspace.selectedLocation {
                return LF("Hours of %@", selected.name) + " · " + (workspace.canSwitchLocation ? L("Each location keeps its own. Switch location in the top bar to edit another.") : L("Each location keeps its own."))
            }
            return L("When you are open and how visits are booked. The Schedule, online booking and the double-booking check all read this.")
        }()
        return ModuleHeader(icon: ProviderSection.availability.headerIcon, title: L("Availability"), subtitle: subtitle,
                            accent: ProviderSection.availability.headerAccent, stats: stats, storageKey: "availability")
    }

    private func go(_ proxy: ScrollViewProxy, _ id: String) {
        withAnimation { proxy.scrollTo(id, anchor: .top) }
    }

    private func confirmModeLabel(_ mode: String) -> String {
        mode == "instant" ? L("They confirm themselves") : L("I confirm each booking")
    }

    private func howItWorks(_ proxy: ScrollViewProxy) -> some View {
        let steps: [(id: String, icon: String, tint: Color, title: String, body: String)] = [
            ("hours", "clock-3", Theme.aqua, L("Opening hours"), L("When this location is open. Everything else happens inside them.")),
            ("team", "users-round", Theme.pink, L("Each person’s hours"), L("The location’s, or their own inside them. Hours of their own outside opening hours don’t count.")),
            ("closures", "calendar-off", Theme.mango, L("Exceptions"), L("Closed dates and special hours for the place; days off for a person.")),
            ("preview", "eye", Theme.lime, L("What families see"), L("Times when the place is open and someone is working, after the notice you ask for.")),
        ]
        return Card(padding: 8, spacing: 4) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 4, alignment: .top)], spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Button { go(proxy, step.id) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Glyph(step.icon, size: 16).foregroundStyle(Theme.inkStrong)
                                .frame(width: 36, height: 36).background(Theme.wash(step.tint, 30), in: Circle())
                            VStack(alignment: .leading, spacing: 0) {
                                (Text("\(index + 1).").monospacedDigit().foregroundColor(Theme.inkSoft) + Text(" " + step.title).foregroundColor(Theme.inkStrong))
                                    .font(Theme.text(14, weight: .bold))
                                Text(step.body).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Opening hours

    private func openingHours(_ hours: TeamHoursDraft, checksHours: Bool) -> some View {
        let saving = savingPart == "hours"
        let valid = hours.week.allSatisfy { TeamHours.dayIsValid($0) }
        let device = TimeZone.current.identifier
        return TeamSaveSection(
            title: L("Opening hours"),
            subtitle: L("Open time in the Schedule, and the only times families can book online."),
            systemImage: "clock-3",
            tint: Theme.aqua,
            state: hoursFlash.state(saving: saving, dirty: hoursDirty, valid: valid),
            saveLabel: L("Save hours"),
            invalidText: L("Some hours end before they start or overlap. Fix them to save."),
            onSave: { save("hours") },
            onDiscard: { hoursDraft = nil }
        ) {
            // The web's TimezoneField, in the card's header.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Glyph("earth", size: 14)
                    Text(L("Time zone").uppercased()).tracking(1.4)
                }
                .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                Button { pickingZone = true } label: {
                    PillField(text: TeamHours.zoneLabel(hours.timezone), icon: "chevrons-up-down", height: 40)
                }
                .buttonStyle(.plain)
                .disabled(saving)
                if device != hours.timezone && !saving {
                    Button {
                        hoursFlash.clear(); hoursDraft = TeamHoursDraft(timezone: device, week: hours.week)
                    } label: {
                        Text(LF("Use this device’s (%@)", TeamHours.zoneLabel(device))).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue).multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        } content: {
            if let savedHours, hoursDraft != nil, hoursDraft?.timezone != savedHours.timezone {
                NoticeCard(tone: .warning, message: L("Changing the time zone doesn’t move what is booked: each visit keeps its moment, so it will read at a different hour here. Check the Schedule after saving."), icon: "triangle-alert")
            }
            FlowLayout(spacing: 8) {
                PMButton(L("Close weekends"), variant: .outline, size: .compact) {
                    hoursFlash.clear()
                    hoursDraft = TeamHoursDraft(timezone: hours.timezone, week: hours.week.map { TeamHours.weekend.contains($0.day) ? TeamHours.day($0.day, []) : $0 })
                }
                PMButton(L("Start over: weekdays 9 to 5"), variant: .outline, size: .compact) {
                    hoursFlash.clear()
                    hoursDraft = TeamHoursDraft(timezone: hours.timezone, week: TeamHours.defaultWeek)
                }
                if !otherLocations.isEmpty {
                    Menu {
                        ForEach(otherLocations) { other in Button(other.name) { copyWeek(from: other) } }
                    } label: {
                        HStack(spacing: 6) {
                            Glyph("copy", size: 14)
                            Text(L("Copy from another location"))
                        }
                        .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                        .padding(.horizontal, 12).frame(height: 36)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
                    }
                    .disabled(copying)
                }
            }
            .disabled(saving)
            TeamWeekEditor(
                schedule: Binding(get: { hours.week }, set: { week in hoursFlash.clear(); hoursDraft = TeamHoursDraft(timezone: hours.timezone, week: week) }),
                disabled: saving,
                closedHint: checksHours ? L("Closed: booking this day asks staff to confirm, and families can’t book it online.") : L("Closed: grey in the Schedule, and families can’t book it online.")
            )
            Text(L("For a lunch break or a split shift, add a break or more hours to a day. Changing the hours doesn’t move or cancel visits already booked: check the Schedule for any left outside them."))
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        }
    }

    // MARK: Booking rules

    private func bookingRules(_ rules: TeamBookingRules) -> some View {
        let saving = savingPart == "rules"
        func set(_ change: (inout TeamBookingRules) -> Void) {
            var next = rules
            change(&next)
            rulesFlash.clear()
            rulesDraft = next
        }
        return TeamSaveSection(
            title: L("Booking rules"),
            subtitle: L("How new visits are made, by your team and by families."),
            systemImage: "settings-2",
            tint: Theme.mango,
            state: rulesFlash.state(saving: saving, dirty: rulesDirty),
            saveLabel: L("Save rules"),
            onSave: { save("rules") },
            onDiscard: { rulesDraft = nil }
        ) {
            Group {
                MenuField(label: L("Usual visit length"), options: TeamHours.withSaved(TeamHours.durationOptions, rules.duration).map { ($0, TeamHours.duration($0)) }, selection: Binding(get: { rules.duration }, set: { v in set { $0.duration = v } }))
                Text(L("New visits start at this length; each one can still be changed.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Time between visits")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    Text(L("Kept free after each visit to clean up. Double bookings and free times online count it.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    FlowLayout(spacing: 6) {
                        ForEach(TeamHours.bufferOptions, id: \.self) { minutes in
                            FilterChip(title: minutes == 0 ? L("None") : TeamHours.duration(minutes), isSelected: rules.buffer == minutes) { set { $0.buffer = minutes } }
                        }
                    }
                }
                ToggleRow(
                    title: L("Families can ask for visits online"),
                    subtitle: rules.confirmMode == "instant"
                        ? L("Linked families book a free time from the PawMiaw app, inside opening hours. It lands in the Schedule already confirmed, like any other visit.")
                        : L("Linked families book a free time from the PawMiaw app, inside opening hours. It arrives as a request on Home and in the Schedule, holding its time until you answer it."),
                    isOn: Binding(get: { rules.allowOnline }, set: { v in set { $0.allowOnline = v } })
                )
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("How bookings are confirmed")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    ChoiceCards(options: [
                        ("approve", L("I confirm each booking"), L("The time is held while you answer: confirm it, move it or decline it. With no answer it is released.")),
                        ("instant", L("They confirm themselves"), L("A booking goes straight into the Schedule, like one your team made.")),
                    ], selection: Binding(get: { rules.confirmMode }, set: { v in set { $0.confirmMode = v } }))
                    MenuField(label: L("Minimum notice for online booking"), options: TeamHours.withSaved(TeamHours.noticeOptions, rules.notice).map { ($0, TeamHours.notice($0)) }, selection: Binding(get: { rules.notice }, set: { v in set { $0.notice = v } }))
                    Text(L("How long before a visit families can still book it.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    MenuField(label: L("How far ahead families can book"), options: [(-1, TeamHours.horizon(nil))] + (rules.horizon.map { TeamHours.withSaved(TeamHours.horizonOptions, $0) } ?? TeamHours.horizonOptions).map { ($0, TeamHours.horizon($0)) }, selection: Binding(get: { rules.horizon ?? -1 }, set: { v in set { $0.horizon = v < 0 ? nil : v } }))
                    Text(L("The latest day families see free times for.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    let window = rules.lateCancel ?? (online?.familyCancelWindowHours ?? 24)
                    MenuField(label: L("Families cancel by themselves until"), options: TeamHours.withSaved(TeamHours.lateCancelOptions, window).map { ($0, LP($0, "1 hour before", "%d hours before")) }, selection: Binding(get: { window }, set: { v in set { $0.lateCancel = v } }))
                    Text(L("After that they ask you, and a late cancellation can carry your fee. One window for the whole business: it is also the late-cancel window in Store › Missed visits."))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    Text(rules.allowOnline ? L("These two only apply to families booking online and to the link to ask for another time. Your team can always book any time.") : L("Online booking is off, so these wait until it’s on. They never limit your team."))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
                .padding(12)
                .background(rules.allowOnline ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.wash(Theme.surfaceMuted, 45)), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                ToggleRow(title: L("Ask families to confirm new visits"), subtitle: L("A new visit emails the family a link to confirm or ask for another time. It can be switched off on each visit."), isOn: Binding(get: { rules.confirmByDefault }, set: { v in set { $0.confirmByDefault = v } }))
                ToggleRow(title: L("Check opening hours when booking"), subtitle: rules.afterHours ? L("Off: the hours are only a guide; staff can book any time without a question.") : L("On: a visit outside the hours asks staff to confirm, and is marked as booked out of hours."), isOn: Binding(get: { !rules.afterHours }, set: { v in set { $0.afterHours = !v } }))
                if workspace.offers(.emergency) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 8) {
                            Glyph("siren", size: 16).padding(.top, 2)
                            Text(L("Emergencies don’t follow these rules: who is on call and the out-of-hours charge are set in the Hospital."))
                        }
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        if workspace.can(.hospitalView) {
                            NavigationLink(value: ProviderRoute.section(.hospital)) {
                                Text(L("See who is on call")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 24)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.wash(Theme.surfaceMuted, 45), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
            }
            .disabled(saving)
        }
    }

    // MARK: The team

    private func teamCard(today: String) -> some View {
        TeamPanel(
            title: L("Your team’s hours"),
            subtitle: L("Everyone who takes visits works these opening hours unless they have their own. Each person’s own hours and days off are set on their page; they can’t be booked online outside the location’s hours."),
            systemImage: "users-round",
            tint: Theme.pink
        ) {
            if !canSeeStaff {
                Text(L("Your role can’t see the team list.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            } else if people.isEmpty {
                if teamReady {
                    EmptyState(systemImage: "users-round", title: L("Nobody takes visits yet. A person takes visits when their role can start and finish them."))
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 64)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(people) { member in
                        if member.id != people.first?.id { RowDivider() }
                        NavigationLink(value: ProviderRoute.staffMember(member.id)) {
                            HStack(spacing: 12) {
                                Avatar(name: member.shownName, imageURL: member.image, size: 36, tint: Theme.aqua)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(member.shownName).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                    Text(member.atOnce > 1 ? LF("%d pets at once", member.atOnce) : L("One pet at a time")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                                    if let hint = hint(for: member.id, today: today) {
                                        Text(hint).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(LP(people.count, "1 person takes visits", "%d people take visits")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            if canSeeStaff {
                NavigationLink(value: ProviderRoute.section(.staff)) {
                    Text(L("Change who takes visits and how many at once")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "Own hours · Off 24 dic – 26 dic".
    private func hint(for memberId: String, today: String) -> String? {
        guard let entry = teamHours[memberId] else { return nil }
        let here = entry.locations?.first { locationId != nil ? $0.locationId == locationId : ($0.isPrimary ?? false) }
        var parts: [String] = []
        if let here { parts.append((here.usesLocationHours ?? true) ? L("The location’s hours") : L("Own hours")) }
        if let next = TeamDays.sortSpans(entry.timeOff ?? [], today: today, start: \.startDay, end: \.endDay).current.first {
            parts.append(next.startDay <= today ? L("Off today") : LF("Off %@", TeamDays.rangeLabel(next.startDay, next.endDay, today: today)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: What families see

    private func preview(hours: TeamHoursDraft, rules: TeamBookingRules, today: String) -> [TeamPreviewDay] {
        let zone = TimeZone(identifier: hours.timezone) ?? .current
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let now = calendar.dateComponents([.hour, .minute], from: Date())
        let earliest = (now.hour ?? 0) * 60 + (now.minute ?? 0) + max(0, rules.notice)
        // Who works here, as "what families see" counts them; nil until the team's hours are in.
        let persons: [(own: [TeamDay]?, timeOff: [TeamTimeOff])]? = canSeeStaff && teamReady ? people.compactMap { member in
            guard let entry = teamHours[member.id], let here = entry.locations?.first(where: { locationId != nil ? $0.locationId == locationId : ($0.isPrimary ?? false) }) else { return nil }
            return ((here.usesLocationHours ?? true) ? nil : (here.weeklySchedule ?? []), entry.timeOff ?? [])
        } : nil
        return (0..<7).map { index in
            let date = TeamDays.add(today, index)
            let closure = TeamClosureMath.on(date, closures)
            let open = closure.map { $0.ranges ?? [] } ?? TeamHours.ranges(hours.week.first(where: { $0.day == TeamDays.weekday(date) }))
            let openMinutes = TeamHours.minuteRanges(open).sorted { $0.start < $1.start }
            let count: Int? = persons.map { list in
                openMinutes.isEmpty ? 0 : list.filter { person in
                    if person.timeOff.contains(where: { $0.startDay <= date && date <= $0.endDay }) { return false }
                    guard let own = person.own else { return true }
                    let theirs = TeamHours.minuteRanges(TeamHours.ranges(own.first(where: { $0.day == TeamDays.weekday(date) })))
                    return !TeamHours.intersect(openMinutes, theirs).isEmpty
                }.count
            }
            var day = TeamPreviewDay(date: date, open: open, bookable: [], closureLabel: closure?.label, closureClosed: closure.map { $0.ranges == nil }, why: nil, people: count)
            if openMinutes.isEmpty { day.why = closure != nil ? .closedDate : .closedDay; return day }
            if let horizon = rules.horizon, index > horizon { day.why = .horizon; return day }
            let from = earliest - index * 1440
            let left = from <= 0 ? openMinutes : TeamHours.intersect(openMinutes, [(min(from, 1440), 1440)])
            if left.isEmpty { day.why = index == 0 && rules.notice == 0 ? .over : .notice; return day }
            if count == 0 { day.why = .nobody; return day }
            day.bookable = left.map { TeamTimeRange(start: TeamHours.time($0.start), end: TeamHours.time($0.end)) }
            return day
        }
    }
}

struct TeamPreviewDay {
    enum Why { case closedDay, closedDate, notice, horizon, over, nobody }
    let date: String
    let open: [TeamTimeRange]
    var bookable: [TeamTimeRange]
    let closureLabel: String?
    let closureClosed: Bool?
    var why: Why?
    let people: Int?
}

/// "What families see this week": when each of the next days can be booked online, and why not.
struct TeamWeekPreviewCard: View {
    let days: [TeamPreviewDay]
    let online: Bool
    let notice: Int
    let horizon: Int?
    let canSeeStaff: Bool
    let unsaved: Bool

    var body: some View {
        TeamPanel(
            title: L("What families see this week"),
            subtitle: online ? L("The days and hours a family can ask for online, from today.") : L("Online booking is off: families can’t book a time themselves. This is what they would see with it on."),
            systemImage: "eye",
            tint: Theme.lime
        ) {
            if unsaved {
                Text(L("With the changes you haven’t saved yet."))
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.wash(Theme.mango, 12), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.mango, 55, with: Theme.borderSoft), lineWidth: 1))
            }
            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    if index > 0 { RowDivider() }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            HStack(spacing: 6) {
                                Text(index == 0 ? L("Today") : TeamDays.weekdayLabel(day.date)).foregroundStyle(Theme.inkStrong)
                                if index == 0 { Text(TeamDays.weekdayLabel(day.date)).fontWeight(.medium).foregroundStyle(Theme.inkSoft) }
                            }
                            .font(Theme.text(14, weight: .bold)).lineLimit(1)
                            Spacer(minLength: 0)
                            if let people = day.people, !day.open.isEmpty {
                                HStack(spacing: 4) {
                                    Glyph("users-round", size: 14)
                                    Text(people == 0 ? L("Nobody working") : LP(people, "1 person", "%d people"))
                                }
                                .font(Theme.text(12, weight: .semibold)).foregroundStyle(people == 0 ? Theme.destructive : Theme.inkSoft)
                            }
                        }
                        Text(line(day)).font(Theme.text(14)).foregroundStyle(day.bookable.isEmpty ? Theme.inkSoft : Theme.inkStrong)
                        if !day.bookable.isEmpty { TeamRangesBar(ranges: day.bookable, guide: day.open, showHours: false).padding(.top, 4) }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            .opacity(online ? 1 : 0.8)
            HStack(alignment: .top, spacing: 8) {
                Glyph("globe", size: 16).padding(.top, 2)
                Text(rulesLine + " " + L("The free times they are offered also leave out what is already booked."))
            }
            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            if canSeeStaff && days.contains(where: { $0.why == .nobody }) {
                NavigationLink(value: ProviderRoute.section(.staff)) {
                    (Text(L("A day is open with nobody working when everyone who takes visits is off or has other hours.")) + Text(" ") + Text(L("See who takes visits")).bold().foregroundColor(Theme.blue))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rulesLine: String {
        if notice > 0 {
            return horizon != nil
                ? LF("Families book at least %1$@ before, and up to %2$@ ahead.", TeamHours.notice(notice), TeamHours.horizon(horizon))
                : LF("Families book at least %@ before, as far ahead as they like.", TeamHours.notice(notice))
        }
        return horizon != nil ? LF("Families book up to the last minute, and up to %@ ahead.", TeamHours.horizon(horizon)) : L("Families book up to the last minute, as far ahead as they like.")
    }

    private func line(_ day: TeamPreviewDay) -> String {
        if !day.bookable.isEmpty {
            let special = day.closureClosed == false ? " · " + (day.closureLabel.nonEmpty ?? L("Special hours")) : ""
            return TeamHours.rangesLabel(day.bookable) + special
        }
        switch day.why {
        case .closedDay?: return L("Closed")
        case .closedDate?: return day.closureLabel.nonEmpty.map { LF("Closed · %@", $0) } ?? L("Closed that day")
        case .notice?: return L("Too soon to book online")
        case .horizon?: return L("Further ahead than families can book")
        case .over?: return L("Already closed today")
        case .nobody?: return L("Open, but nobody takes visits")
        case nil: return L("Closed")
        }
    }
}

/// The clock the hours are in (web `TimezoneField`): the one time zone picker, with this
/// device's zone one tap away when it differs (also the setup checklist's).
struct TeamTimeZonePicker: View {
    let selection: String
    let onPick: (String) -> Void

    var body: some View {
        let device = TimeZone.current.identifier
        PlacesTimeZonePicker(selection: selection, suggestions: device != selection ? [device] : [], notes: [device: L("This device’s time zone")], onPick: onPick)
    }
}
