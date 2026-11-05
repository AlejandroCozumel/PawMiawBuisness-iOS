//
//  TeamMemberHours.swift
//  PawMiawNegocios
//
//  A person's hours at each location they work at — the location's opening
//  hours or a week of their own, always inside the location's — and their
//  days off (web: components/app/staff/member-hours-card.tsx). Adding days
//  off says first how many of their visits are booked then; nothing is
//  cancelled.
//

import SwiftUI

/// Their hours, one card per location they work at.
struct TeamMemberHoursCards: View {
    let member: TeamMember
    let hours: TeamMemberHours?
    let error: String?
    let canEdit: Bool
    let onSaved: (TeamMemberHours) -> Void
    let retry: () async -> Void

    var body: some View {
        let locations = hours?.locations ?? []
        if locations.isEmpty {
            TeamPanel(title: L("Their hours"), subtitle: LF("When %@ takes visits.", member.shownName), systemImage: "clock-3", tint: Theme.aqua) {
                if let error {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(error).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        PMButton(L("Try again"), variant: .outline, size: .compact) { Task { await retry() } }
                    }
                } else if hours == nil {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 64)
                } else {
                    Text(LF("%@ doesn’t work at any open location.", member.shownName)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
        } else {
            ForEach(locations, id: \.locationId) { entry in
                TeamLocationHoursCard(member: member, entry: entry, multi: locations.count > 1, canEdit: canEdit, onSaved: onSaved)
            }
        }
    }
}

private struct TeamLocationHoursCard: View {
    let member: TeamMember
    let entry: TeamMemberLocationHours
    let multi: Bool
    let canEdit: Bool
    let onSaved: (TeamMemberHours) -> Void

    @State private var mode: Bool? // true = the location's hours
    @State private var draft: [TeamDay]?
    @State private var saving = false
    @StateObject private var flash = TeamSavedFlash()

    private var savedUsesLocation: Bool { entry.usesLocationHours ?? true }
    private var usesLocation: Bool { mode ?? savedUsesLocation }
    private var locationWeek: [TeamDay] { TeamHours.ordered(entry.locationWeeklySchedule ?? []) }
    private var savedOwn: [TeamDay] { TeamHours.ordered(savedUsesLocation ? (entry.locationWeeklySchedule ?? []) : (entry.weeklySchedule ?? [])) }
    private var ownWeek: [TeamDay] { draft ?? savedOwn }
    private var dirty: Bool { usesLocation != savedUsesLocation || (!usesLocation && !TeamHours.sameWeek(ownWeek, entry.weeklySchedule ?? [])) }
    private var valid: Bool { usesLocation || ownWeek.allSatisfy { TeamHours.dayIsValid($0) } }

    /// Days their own hours run outside the location's: they can't be booked online then.
    private var outside: [String] {
        guard !usesLocation else { return [] }
        return ownWeek.filter { day in
            let ranges = TeamHours.ranges(day)
            guard !ranges.isEmpty else { return false }
            let open = TeamHours.minuteRanges(TeamHours.ranges(locationWeek.first(where: { $0.day == day.day })))
            let inside = TeamHours.intersect(TeamHours.minuteRanges(ranges), open).reduce(0) { $0 + ($1.end - $1.start) }
            return TeamHours.minutes(ranges) > inside
        }.map(\.day)
    }

    var body: some View {
        let name = member.shownName
        TeamSaveSection(
            title: multi ? LF("Their hours at %@", entry.name ?? "") : L("Their hours"),
            subtitle: usesLocation ? LF("%@ works the location’s opening hours.", name) : LF("%@ works their own hours. They only count inside the location’s opening hours.", name),
            systemImage: "clock-3",
            tint: Theme.aqua,
            state: flash.state(saving: saving, dirty: dirty, valid: valid),
            saveLabel: L("Save hours"),
            invalidText: L("Some hours end before they start or overlap. Fix them to save."),
            readOnlyText: canEdit ? nil : L("Only someone who can edit staff roles changes this."),
            onSave: canEdit ? { save() } : nil,
            onDiscard: { mode = nil; draft = nil }
        ) {
            if canEdit {
                ChoiceCards(options: [
                    (true, L("Works the location’s hours"), L("Follows the opening hours, and any change to them.")),
                    (false, L("Own hours"), L("A week of their own: part-time, a late shift, a split day.")),
                ], selection: Binding(get: { usesLocation }, set: { flash.clear(); mode = $0 }))
                .disabled(saving)
            }
            if !canEdit || usesLocation {
                TeamWeekList(week: canEdit ? locationWeek : (usesLocation ? locationWeek : ownWeek))
            } else {
                Text(L("The light band is the location’s hours.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                PMButton(L("Start from the location’s hours"), systemImage: "rotate-ccw", variant: .outline, size: .compact) {
                    flash.clear(); draft = locationWeek
                }
                .disabled(saving)
                TeamWeekEditor(
                    schedule: Binding(get: { ownWeek }, set: { flash.clear(); draft = $0 }),
                    guide: locationWeek,
                    disabled: saving,
                    closedHint: L("Not working: families can’t book them online this day."),
                    openWord: L("Working"),
                    closedWord: L("Day off")
                )
                if !outside.isEmpty {
                    NoticeCard(tone: .warning, message: LF("On %@ some of these hours fall outside the location’s. They can’t be booked online then.", outside.map { TeamHours.dayShort($0) }.joined(separator: ", ")), icon: "triangle-alert")
                }
            }
        }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                var body: [String: Any?] = ["locationId": entry.locationId, "usesLocationHours": usesLocation]
                if !usesLocation { body["weeklySchedule"] = TeamHours.body(ownWeek) }
                let updated: TeamMemberHours = try await API.put("/provider-hours/members/\(member.id)", body: body)
                mode = nil; draft = nil
                onSaved(updated)
                flash.mark()
                announceDataChanged()
            } catch {
                Toast.error(error)
            }
        }
    }
}

/// A person's days off from today on, each removable, and a sheet to add more.
struct TeamMemberTimeOffCard: View {
    let member: TeamMember
    let hours: TeamMemberHours?
    let canEdit: Bool
    let reload: () async -> Void

    @State private var adding = false
    @State private var removing: TeamTimeOff?

    private var zone: String? { hours?.locations?.first(where: { $0.isPrimary ?? false })?.timezone ?? hours?.locations?.first?.timezone }

    var body: some View {
        let today = TeamDays.today(zone)
        let upcoming = TeamDays.sortSpans(hours?.timeOff ?? [], today: today, start: \.startDay, end: \.endDay).current
        TeamPanel(
            title: L("Days off"),
            subtitle: LF("Vacation, sick days, a course. Families can’t book %@ online those days, “whoever is free” skips them, and booking them asks your team to confirm.", member.shownName),
            systemImage: "calendar-minus",
            tint: Theme.pink
        ) {
            if canEdit {
                PMButton(L("Add days off"), systemImage: "calendar-plus", size: .compact, fullWidth: true) { adding = true }
            }
        } content: {
            if hours == nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 64)
            } else if upcoming.isEmpty {
                EmptyState(systemImage: "calendar-minus", title: L("No days off coming up."), accent: Theme.pink)
            } else {
                ForEach(upcoming) { item in
                    TeamDayTileRow(
                        startDay: item.startDay,
                        title: item.reason.nonEmpty ?? L("Day off"),
                        detail: TeamDays.rangeLabel(item.startDay, item.endDay, today: today) + (TeamDays.count(item.startDay, item.endDay) > 1 ? " · " + LF("%d days", TeamDays.count(item.startDay, item.endDay)) : ""),
                        tint: Theme.pink,
                        badge: item.startDay <= today ? L("Off today") : nil,
                        onRemove: canEdit ? { removing = item } : nil
                    )
                }
            }
        }
        .sheet(isPresented: $adding) {
            TeamTimeOffSheet(member: member, today: today) { await reload() }
        }
        .sheet(item: $removing) { item in
            TeamConfirmSheet(title: L("Remove these days off?"), message: LF("%@ can be booked those days again.", member.shownName), confirmTitle: L("Remove"), cancelTitle: L("Keep them")) {
                try await API.send("DELETE", "/provider-hours/time-off/\(item.id)")
                Toast.show(LF("Removed. %@ can be booked those days again.", member.shownName))
                await reload()
                announceDataChanged()
            } content: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.reason.nonEmpty ?? L("Day off")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    Text(TeamDays.rangeLabel(item.startDay, item.endDay, today: today)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            }
        }
    }
}

/// A date as a small calendar tile with its title and line (days off, closed dates).
struct TeamDayTileRow: View {
    let startDay: String
    let title: String
    let detail: String
    var tint: Color = Theme.pink
    var badge: String? = nil
    var extraBadge: String? = nil
    var faded: Bool = false
    var onEdit: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    var body: some View {
        let tile = TeamDays.tile(startDay)
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(tile.month).font(.brandText(9.9, weight: .heavy)).tracking(0.8).foregroundStyle(Theme.inkSoft)
                Text(tile.day).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
            }
            .frame(width: 48)
            .padding(.vertical, 6)
            .background(Theme.wash(tint, 18), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                FlowLayout(spacing: 8) {
                    Text(title).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    if let badge { Chip(text: badge, tone: .custom(Theme.blue), percent: 14, ink: Theme.inkOnBright) }
                    if let extraBadge {
                        HStack(spacing: 4) { Glyph("repeat", size: 12); Text(extraBadge) }
                            .font(.brandText(11.2, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Theme.wash(Theme.aqua, 22), in: Capsule())
                    }
                }
                Text(detail).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
            if let onEdit { IconCircleButton(systemImage: "pencil", label: LF("Change %@", title), bordered: false, action: onEdit) }
            if let onRemove { IconCircleButton(systemImage: "trash-2", label: LF("Remove %@", title), bordered: false, action: onRemove) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        .opacity(faded ? 0.7 : 1)
    }
}

/// What is already booked on the days being closed or given off — said before saving.
struct TeamBookedNotice: View {
    let conflicts: TeamHoursConflicts?
    let loading: Bool
    let today: String
    /// Days off: the person's name, to say "their". nil for a location's closed date.
    var person: String? = nil
    /// Where "See them in the Schedule" opens: the person's list, or the first day booked.
    var scheduleFilter: ScheduleFilter? = nil

    @State private var showingSchedule = false

    var body: some View {
        content
            .sheet(isPresented: $showingSchedule) {
                if let scheduleFilter {
                    NavigationStack {
                        RouteView(route: .schedule(scheduleFilter))
                            .providerRoutes()
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button(L("Close")) { showingSchedule = false }
                                }
                            }
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Checking what is booked those days…")) }
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        } else if let data = conflicts {
            let visits = data.visits ?? 0, stays = data.stays ?? 0
            VStack(alignment: .leading, spacing: 8) {
                if visits > 0 || stays > 0 {
                    let visitsText = person.map { name in visits == 1 ? LF("%@ has 1 visit booked those days.", name) : LF("%1$@ has %2$d visits booked those days.", name, visits) }
                        ?? LP(visits, "1 visit is booked those days.", "%d visits are booked those days.")
                    let staysText = stays > 0 ? LP(stays, "1 stay arrives or leaves then.", "%d stays arrive or leave then.") : ""
                    VStack(alignment: .leading, spacing: 6) {
                        Text([visits > 0 ? visitsText : nil, staysText.nonEmpty].compactMap { $0 }.joined(separator: " "))
                            .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                        Text(person != nil ? L("Saving doesn’t cancel or move them: they stay with this person until you give them to someone else.") : L("Saving doesn’t cancel or move them: they stay booked until you move them or tell the family."))
                            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        if visits > 0 && scheduleFilter != nil {
                            // Over this sheet, like the web's new tab: what is being typed here stays.
                            Button { showingSchedule = true } label: {
                                HStack(spacing: 6) {
                                    Glyph("calendar-days", size: 16)
                                    Text(visits == 1 ? L("See it in the Schedule") : L("See them in the Schedule"))
                                }
                                .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.wash(Theme.mango, 12), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.mango, 55, with: Theme.borderSoft), lineWidth: 1))
                } else {
                    HStack(spacing: 8) {
                        Glyph("circle-check", size: 16).foregroundStyle(ProviderState.done.color)
                        Text(person.map { LF("%@ has nothing booked those days.", $0) } ?? L("Nothing is booked those days."))
                    }
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                if let covered = data.covered, !covered.isEmpty {
                    (Text(person != nil ? L("Already off:") : L("Already on the list:")).fontWeight(.semibold).foregroundColor(Theme.inkStrong)
                        + Text(" " + covered.map { [$0.label.nonEmpty, TeamDays.rangeLabel($0.startDay, $0.endDay, today: today)].compactMap { $0 }.joined(separator: " · ") }.joined(separator: "; ")))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }
}

/// Days off for a person: a day or a stretch, why (optional), and what is booked then.
private struct TeamTimeOffSheet: View {
    let member: TeamMember
    let today: String
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var firstDay = ""
    @State private var lastDay = ""
    @State private var oneDay = true
    @State private var reason = ""
    @State private var conflicts: TeamHoursConflicts?
    @State private var checking = false
    @State private var saving = false

    private var startDay: String { firstDay.isEmpty ? today : firstDay }
    private var endDay: String { oneDay ? startDay : (lastDay.isEmpty ? startDay : lastDay) }
    private var spanError: String? {
        if endDay < startDay { return L("The last day comes before the first.") }
        if TeamDays.count(startDay, endDay) > 366 { return L("Choose a year at most.") }
        return nil
    }
    private var alreadyOff: Bool {
        (conflicts?.covered ?? []).contains { $0.startDay <= startDay && endDay <= $0.endDay }
    }

    var body: some View {
        let name = member.shownName
        ProviderModal(title: LF("Days off for %@", name), subtitle: L("They won’t be offered online those days."), systemImage: "calendar-minus", accent: .pink, isDirty: true, form: form, primaryTitle: L("Add days off"), isWorking: saving, primaryIcon: "calendar-plus", onPrimary: { save() }) {
            ModalSection(title: L("Dates"), subtitle: L("Whole days.")) {
                ToggleRow(title: L("1 day"), isOn: $oneDay)
                DayField(label: L("First day"), day: Binding(get: { startDay }, set: { firstDay = $0; form.clear("dates") }), min: today)
                if !oneDay {
                    DayField(label: L("Last day"), day: Binding(get: { endDay }, set: { lastDay = $0; form.clear("dates") }), min: startDay)
                    Text(LF("%d days", max(1, TeamDays.count(startDay, endDay)))).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                if let error = form.error("dates") {
                    Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral).id("dates")
                } else {
                    Color.clear.frame(height: 0).id("dates")
                }
                if spanError == nil {
                    TeamBookedNotice(conflicts: conflicts, loading: checking, today: today, person: name, scheduleFilter: ScheduleFilter(memberId: member.id, view: "list"))
                }
            }
            // The web's "Reason (optional)" part: the field under it, its label read aloud only.
            ModalSection(title: L("Reason") + " " + L("(optional)")) {
                TextField(L("e.g. Vacation"), text: $reason)
                    .fieldChrome()
                    .accessibilityLabel(L("Reason"))
                FlowLayout(spacing: 6) {
                    ForEach(["Vacation", "Sick", "Course", "Personal"], id: \.self) { key in
                        let text = L(key)
                        FilterChip(title: text, isSelected: reason.trimmingCharacters(in: .whitespaces) == text, solid: true) {
                            reason = reason.trimmingCharacters(in: .whitespaces) == text ? "" : text
                        }
                    }
                }
                Text(L("The team sees the reason when booking; families never do.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
        }
        .task(id: "\(startDay)|\(endDay)") { await check() }
        .onChange(of: firstDay) { _, value in if !lastDay.isEmpty && lastDay < value { lastDay = value } }
    }

    private func check() async {
        guard spanError == nil else { conflicts = nil; return }
        checking = true
        defer { checking = false }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        conflicts = try? await API.get("/provider-hours/conflicts", query: ["startDay": startDay, "endDay": endDay, "memberId": member.id])
    }

    private func save() {
        guard form.check([("dates", spanError ?? (alreadyOff ? L("They are already off those days.") : nil))]) else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let result: TeamTimeOffSaved = try await API.post("/provider-hours/members/\(member.id)/time-off", body: ["startDay": startDay, "endDay": endDay, "reason": reason.nonEmpty])
                let visits = result.visits ?? 0
                if visits > 0 {
                    Toast.show(LP(visits, "Saved. They have 1 visit booked those days — reassign it from the Schedule.", "Saved. They have %d visits booked those days — reassign them from the Schedule."))
                } else {
                    Toast.show(LF("Days off saved for %@.", member.shownName))
                }
                await onSaved()
                announceDataChanged()
                dismiss()
            } catch {
                form.apply(error, known: ["startDay": "dates", "endDay": "dates"])
            }
        }
    }
}

