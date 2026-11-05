//
//  TeamClosures.swift
//  PawMiawNegocios
//
//  A location's closed dates and special hours, once or every year (web:
//  components/app/availability/closures-card.tsx). A closed date has no
//  online slots and booking it asks the team to confirm; special hours
//  replace the week on those dates. Before saving, the sheet says what is
//  already booked then — nothing is cancelled.
//

import SwiftUI

enum TeamClosureMath {
    private static func isReal(_ key: String) -> Bool {
        guard let date = TeamDays.date(key) else { return false }
        return TeamDays.key(utc: date) == key
    }

    /// The days a closure next covers from `fromDay`: its own, or a yearly one's next time.
    static func occurrence(_ closure: TeamClosure, from fromDay: String) -> (startDay: String, endDay: String) {
        if !(closure.repeatsYearly ?? false) || closure.endDay >= fromDay { return (closure.startDay, closure.endDay) }
        let length = TeamDays.count(closure.startDay, closure.endDay) - 1
        let firstYear = (Int(fromDay.prefix(4)) ?? 2026) - 1
        for year in firstYear...(firstYear + 9) {
            let start = String(format: "%04d", year) + closure.startDay.dropFirst(4)
            guard isReal(start), start >= closure.startDay else { continue }
            let end = TeamDays.add(start, length)
            if end >= fromDay { return (start, end) }
        }
        return (closure.startDay, closure.endDay)
    }

    static func covers(_ closure: TeamClosure, _ date: String) -> Bool {
        if !(closure.repeatsYearly ?? false) { return closure.startDay <= date && date <= closure.endDay }
        let monthDay = String(date.dropFirst(5)), from = String(closure.startDay.dropFirst(5)), to = String(closure.endDay.dropFirst(5))
        let inside = from <= to ? (from <= monthDay && monthDay <= to) : (monthDay >= from || monthDay <= to)
        return date >= closure.startDay && inside
    }

    /// The closure covering a date, as the server picks it: a closed one wins, then the latest listed.
    static func on(_ date: String, _ closures: [TeamClosure]) -> TeamClosure? {
        let covering = closures.filter { covers($0, date) }
        return covering.first(where: { $0.ranges == nil }) ?? covering.last
    }

    /// "Closed all day" or "Special hours 10:00–14:00".
    static func hoursText(_ ranges: [TeamTimeRange]?) -> String {
        if let ranges, !ranges.isEmpty { return LF("Special hours %@", TeamHours.rangesLabel(ranges)) }
        return L("Closed all day")
    }
}

/// A closed date as it shows: the days it next covers.
private struct TeamShownClosure: Identifiable {
    let closure: TeamClosure
    let startDay: String
    let endDay: String
    var id: String { closure.id }
}

struct TeamClosuresCard: View {
    let locationId: String?
    let timeZone: String?
    let weeklySchedule: [TeamDay]
    let canEdit: Bool
    let otherLocations: [ProviderLocation]
    let closures: [TeamClosure]
    let loaded: Bool
    let error: String?
    let reload: () async -> Void

    @State private var showPast = false
    @State private var past: [TeamClosure]?
    @State private var editing: TeamClosure?
    @State private var adding = false
    @State private var removing: TeamShownClosure?

    private var today: String { TeamDays.today(timeZone) }

    private func shown(_ list: [TeamClosure]) -> [TeamShownClosure] {
        list.map { closure in
            let next = TeamClosureMath.occurrence(closure, from: today)
            return TeamShownClosure(closure: closure, startDay: next.startDay, endDay: next.endDay)
        }
    }

    var body: some View {
        let current = TeamDays.sortSpans(shown(closures), today: today, start: \.startDay, end: \.endDay).current
        let pastShown = TeamDays.sortSpans(shown((past ?? []).filter { !($0.repeatsYearly ?? false) }), today: today, start: \.startDay, end: \.endDay).past
        TeamPanel(
            title: L("Closed dates"),
            subtitle: L("Holidays and days you close, or keep special hours. Families can’t book a closed date online, and booking it asks your team to confirm."),
            systemImage: "calendar-off",
            tint: Theme.pink
        ) {
            if canEdit {
                PMButton(L("Add a closed date"), systemImage: "calendar-plus", size: .compact, fullWidth: true) { adding = true }
            }
        } content: {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, minHeight: 64)
            } else if let error {
                VStack(alignment: .leading, spacing: 12) {
                    Text(error).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    PMButton(L("Try again"), variant: .outline, size: .compact) { Task { await reload() } }
                }
            } else {
                if current.isEmpty {
                    EmptyState(systemImage: "calendar-off", title: L("No closed dates coming up. Add holidays before families book them."))
                } else {
                    VStack(spacing: 8) {
                        ForEach(current) { item in row(item, editable: true) }
                    }
                    Text(LP(current.count, "1 date coming up", "%d dates coming up")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                if showPast {
                    Text(L("Past").uppercased()).font(.brandText(10.9, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.inkSoft)
                    if past == nil {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 48)
                    } else if pastShown.isEmpty {
                        Text(L("Nothing earlier.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(pastShown) { item in row(item, editable: false) }
                        }
                    }
                }
                Button {
                    showPast.toggle()
                    if showPast && past == nil { Task { await loadPast() } }
                } label: {
                    HStack(spacing: 6) {
                        Glyph("history", size: 14)
                        Text(showPast ? L("Hide past dates") : L("Show past dates"))
                    }
                    .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $adding) {
            TeamClosureSheet(closure: nil, locationId: locationId, today: today, weeklySchedule: weeklySchedule, otherLocations: otherLocations) { await reload(); past = nil }
        }
        .sheet(item: $editing) { closure in
            TeamClosureSheet(closure: closure, locationId: locationId, today: today, weeklySchedule: weeklySchedule, otherLocations: otherLocations) { await reload(); past = nil }
        }
        .sheet(item: $removing) { item in
            let label = item.closure.label.nonEmpty ?? TeamDays.rangeLabel(item.startDay, item.endDay, today: today)
            TeamConfirmSheet(
                title: L("Remove this date?"),
                message: (item.closure.repeatsYearly ?? false) ? L("It stops coming back every year, and those dates keep the usual week.") : L("Those dates go back to the usual week."),
                confirmTitle: L("Remove"),
                cancelTitle: L("Keep it")
            ) {
                try await API.send("DELETE", "/provider-hours/closures/\(item.closure.id)")
                Toast.show(L("Removed. Those dates keep the usual week."))
                await reload()
                if past != nil { await loadPast() }
                announceDataChanged()
            } content: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(label).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    let detail = [item.closure.label.nonEmpty == nil ? nil : TeamDays.rangeLabel(item.startDay, item.endDay, today: today), TeamClosureMath.hoursText(item.closure.ranges), (item.closure.repeatsYearly ?? false) ? L("Every year") : nil].compactMap { $0 }.joined(separator: " · ")
                    if !detail.isEmpty { Text(detail).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            }
        }
    }

    private func row(_ item: TeamShownClosure, editable: Bool) -> some View {
        let dates = TeamDays.rangeLabel(item.startDay, item.endDay, today: today)
        let days = TeamDays.count(item.startDay, item.endDay)
        let special = !(item.closure.ranges ?? []).isEmpty
        let now = item.startDay <= today && today <= item.endDay
        let past = item.endDay < today
        let detail = [item.closure.label.nonEmpty == nil ? nil : dates, days > 1 ? LF("%d days", days) : nil, TeamClosureMath.hoursText(item.closure.ranges)].compactMap { $0 }.joined(separator: " · ")
        return TeamDayTileRow(
            startDay: item.startDay,
            title: item.closure.label.nonEmpty ?? dates,
            detail: detail,
            tint: special ? Theme.mango : Theme.pink,
            badge: now ? L("Today") : nil,
            extraBadge: (item.closure.repeatsYearly ?? false) ? L("Every year") : nil,
            faded: past,
            onEdit: canEdit && editable ? { editing = item.closure } : nil,
            onRemove: canEdit ? { removing = item } : nil
        )
    }

    private func loadPast() async {
        let answer: TeamClosuresResponse? = try? await API.get("/provider-hours/closures", query: ["locationId": locationId, "includePast": "true"])
        past = answer?.closures ?? []
    }
}

/// Add or change a closed date: the days, every year or once, its name,
/// closed or special hours, and the other locations to close too.
private struct TeamClosureSheet: View {
    let closure: TeamClosure?
    let locationId: String?
    let today: String
    let weeklySchedule: [TeamDay]
    let otherLocations: [ProviderLocation]
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var firstDay = ""
    @State private var lastDay = ""
    @State private var oneDay = true
    @State private var label = ""
    @State private var yearly = false
    @State private var special = false
    @State private var ranges: [TeamTimeRange] = []
    @State private var alsoAt: [String] = []
    @State private var conflicts: TeamHoursConflicts?
    @State private var checking = false
    @State private var saving = false
    @State private var started = false

    private var startDay: String { firstDay.isEmpty ? today : firstDay }
    private var endDay: String { oneDay ? startDay : (lastDay.isEmpty ? startDay : lastDay) }
    private var days: Int { TeamDays.count(startDay, endDay) }
    private var spanError: String? {
        if endDay < startDay { return L("The last day comes before the first.") }
        if yearly && days > 31 { return L("A date that repeats every year can last a month at most.") }
        if days > 366 { return L("Choose a year at most.") }
        return nil
    }

    var body: some View {
        ProviderModal(
            title: closure == nil ? L("Add a closed date") : L("Change this date"),
            subtitle: L("A holiday, a day you close, or a day with special hours."),
            systemImage: "calendar-off",
            accent: .pink,
            isDirty: closure == nil,
            form: form,
            primaryTitle: closure == nil ? L("Add date") : L("Save changes"),
            isWorking: saving,
            primaryIcon: "calendar-off",
            onPrimary: { save() }
        ) {
            ModalSection(title: L("Dates")) {
                ToggleRow(title: L("1 day"), isOn: $oneDay)
                DayField(label: L("First day"), day: Binding(get: { startDay }, set: { firstDay = $0; form.clear("dates") }), min: closure == nil ? today : nil)
                if !oneDay {
                    DayField(label: L("Last day"), day: Binding(get: { endDay }, set: { lastDay = $0; form.clear("dates") }), min: startDay)
                    Text(LF("%d days", max(1, days))).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                if let error = form.error("dates") {
                    Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral).id("dates")
                } else {
                    Color.clear.frame(height: 0).id("dates")
                }
                ToggleRow(title: L("Every year"), subtitle: days > 31 ? L("Only for a month at most.") : L("It comes back on the same days each year: Christmas, New Year. Not for holidays that change date."), isOn: $yearly)
                if spanError == nil {
                    TeamBookedNotice(conflicts: conflicts, loading: checking, today: today, scheduleFilter: ScheduleFilter(day: conflicts?.firstDay, view: "day"))
                }
            }
            // The web's "Name (optional)" part: the field under it, its label read aloud only.
            ModalSection(title: L("Name") + " " + L("(optional)")) {
                TextField(L("e.g. Christmas"), text: $label)
                    .fieldChrome()
                    .accessibilityLabel(L("Name"))
            }
            ModalSection(title: L("Hours those days")) {
                ChoiceCards(options: [
                    (false, L("Closed all day"), L("No online booking; booking a visit asks your team to confirm.")),
                    (true, L("Special hours"), L("These hours replace the usual week on those dates.")),
                ], selection: Binding(get: { special }, set: { chooseSpecial($0) }))
                if special {
                    TeamRangesEditor(ranges: $ranges)
                        .padding(12)
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                    Color.clear.frame(height: 0).id("ranges")
                }
            }
            if closure == nil && !otherLocations.isEmpty {
                ModalSection(title: L("Also at"), subtitle: L("The same days and hours at your other locations. Each keeps its own copy to change later.")) {
                    ForEach(otherLocations) { location in
                        let on = alsoAt.contains(location.id)
                        Button {
                            alsoAt = on ? alsoAt.filter { $0 != location.id } : alsoAt + [location.id]
                        } label: {
                            // The web's checkbox rows: a 20 tick, the name, a 1 pt box.
                            HStack(spacing: 12) {
                                Tick(on: on)
                                Text(location.name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear { start() }
        .task(id: "\(startDay)|\(endDay)") { await check() }
        .onChange(of: firstDay) { _, value in if !lastDay.isEmpty && lastDay < value { lastDay = value } }
    }

    private func start() {
        guard !started else { return }
        started = true
        if let closure {
            firstDay = closure.startDay
            lastDay = closure.endDay
            oneDay = closure.startDay == closure.endDay
            label = closure.label ?? ""
            yearly = closure.repeatsYearly ?? false
            special = !(closure.ranges ?? []).isEmpty
            ranges = closure.ranges ?? []
        }
    }

    private func chooseSpecial(_ next: Bool) {
        special = next
        if next && ranges.isEmpty {
            // Start from that weekday's hours, when it has some.
            let weekday = TeamHours.ranges(weeklySchedule.first(where: { $0.day == TeamDays.weekday(startDay) }))
            ranges = weekday.isEmpty ? [TeamTimeRange(start: "10:00", end: "14:00")] : weekday
        }
    }

    private func check() async {
        guard spanError == nil else { conflicts = nil; return }
        checking = true
        defer { checking = false }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        conflicts = try? await API.get("/provider-hours/conflicts", query: ["startDay": startDay, "endDay": endDay, "locationId": locationId, "ignoreId": closure?.id])
    }

    private func save() {
        let hoursProblem = special ? TeamHours.problem(ranges).map { TeamHours.problemText($0) } : nil
        guard form.check([("dates", spanError), ("ranges", hoursProblem)]) else { return }
        var values: [String: Any?] = [
            "startDay": startDay,
            "endDay": endDay,
            "label": label.nonEmpty,
            "ranges": special ? TeamHours.sorted(ranges).map { ["start": $0.start, "end": $0.end] } : nil,
            "repeatsYearly": yearly,
        ]
        saving = true
        Task {
            defer { saving = false }
            do {
                let result: TeamClosureSaved
                if let closure {
                    result = try await API.patch("/provider-hours/closures/\(closure.id)", body: values)
                } else {
                    if let locationId { values["locationId"] = locationId }
                    result = try await API.post("/provider-hours/closures", body: values)
                }
                // The same days at the other locations chosen; one that fails is said, the rest stand.
                var failed: [String] = []
                for other in alsoAt {
                    var copy = values
                    copy["locationId"] = other
                    do { let _: TeamClosureSaved = try await API.post("/provider-hours/closures", body: copy) }
                    catch { failed.append(otherLocations.first(where: { $0.id == other })?.name ?? other) }
                }
                await onSaved()
                announceDataChanged()
                if !failed.isEmpty {
                    Toast.error(LF("Saved here, but not at %@. Add it there from that location’s Availability.", failed.joined(separator: ", ")))
                } else if (result.visits ?? 0) > 0 {
                    Toast.show(LP(result.visits ?? 0, "Saved. 1 visit is still booked on those days — move it from the Schedule.", "Saved. %d visits are still booked on those days — move them from the Schedule."))
                } else {
                    Toast.show((result.closure.ranges ?? []).isEmpty ? L("Closed date saved.") : L("Special hours saved."))
                }
                dismiss()
            } catch {
                form.apply(error, known: ["startDay": "dates", "endDay": "dates", "ranges": "ranges"])
            }
        }
    }
}
