//
//  TeamHours.swift
//  PawMiawNegocios
//
//  Opening hours as the web reasons about them (lib/hours.ts,
//  components/app/availability/hours-model.ts): a day has any number of
//  ranges ("HH:MM", "23:59" = midnight); the week in a few words; the
//  labels for lengths, notice and how far ahead; and the week editor the
//  location's Availability and a person's own hours both use.
//

import SwiftUI

enum TeamHours {
    static let dayKeys = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    static let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday"]
    static let weekend = ["saturday", "sunday"]

    // MARK: Days

    static func ranges(_ day: TeamDay?) -> [TeamTimeRange] {
        guard let day, day.enabled else { return [] }
        if let ranges = day.ranges, !ranges.isEmpty { return ranges }
        if let start = day.startTime, let end = day.endTime { return [TeamTimeRange(start: start, end: end)] }
        return []
    }

    static func day(_ key: String, _ ranges: [TeamTimeRange]) -> TeamDay {
        guard let first = ranges.first, let last = ranges.last else {
            return TeamDay(day: key, enabled: false, startTime: nil, endTime: nil, ranges: [])
        }
        return TeamDay(day: key, enabled: true, startTime: first.start, endTime: last.end, ranges: ranges)
    }

    /// The seven days in order, each with its ranges (a missing day is closed).
    static func ordered(_ schedule: [TeamDay]) -> [TeamDay] {
        dayKeys.map { key in day(key, ranges(schedule.first(where: { $0.day == key }))) }
    }

    static let nineToFive = [TeamTimeRange(start: "09:00", end: "17:00")]

    static var defaultWeek: [TeamDay] {
        dayKeys.map { weekend.contains($0) ? day($0, []) : day($0, nineToFive) }
    }

    /// The week as the server takes it: ranges in order, the span filled in.
    static func forSave(_ schedule: [TeamDay]) -> [TeamDay] {
        ordered(schedule).map { day($0.day, sorted(ranges($0))) }
    }

    static func body(_ schedule: [TeamDay]) -> [[String: Any]] {
        forSave(schedule).map { day in
            var out: [String: Any] = ["day": day.day, "enabled": day.enabled, "ranges": (day.ranges ?? []).map { ["start": $0.start, "end": $0.end] }]
            out["startTime"] = day.startTime ?? NSNull()
            out["endTime"] = day.endTime ?? NSNull()
            return out
        }
    }

    // MARK: Minutes

    static func isTime(_ value: String) -> Bool {
        let parts = value.split(separator: ":")
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return false }
        return (0...23).contains(h) && (0...59).contains(m)
    }

    static func startMinutes(_ value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : 0
    }

    static func endMinutes(_ value: String) -> Int { value == "23:59" ? 1440 : startMinutes(value) }

    static func time(_ minutes: Int) -> String {
        if minutes >= 1440 { return "23:59" }
        let m = max(0, minutes)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    static func minuteRanges(_ ranges: [TeamTimeRange]) -> [(start: Int, end: Int)] {
        ranges.filter { isTime($0.start) && isTime($0.end) }.map { (startMinutes($0.start), endMinutes($0.end)) }
    }

    static func sorted(_ ranges: [TeamTimeRange]) -> [TeamTimeRange] { ranges.sorted { $0.start < $1.start } }

    static func minutes(_ ranges: [TeamTimeRange]) -> Int {
        minuteRanges(ranges).reduce(0) { $0 + max(0, $1.end - $1.start) }
    }

    static func intersect(_ a: [(start: Int, end: Int)], _ b: [(start: Int, end: Int)]) -> [(start: Int, end: Int)] {
        var out: [(start: Int, end: Int)] = []
        for left in a { for right in b {
            let start = max(left.start, right.start), end = min(left.end, right.end)
            if end > start { out.append((start, end)) }
        } }
        return out.sorted { $0.start < $1.start }
    }

    enum Problem { case empty, invalidTime, endBeforeStart, overlap }

    static func problem(_ ranges: [TeamTimeRange]) -> Problem? {
        let list = sorted(ranges)
        if list.isEmpty { return .empty }
        var previousEnd = -1
        for range in list {
            if !isTime(range.start) || !isTime(range.end) { return .invalidTime }
            let start = startMinutes(range.start), end = endMinutes(range.end)
            if end <= start { return .endBeforeStart }
            if start < previousEnd { return .overlap }
            previousEnd = end
        }
        return nil
    }

    static func problemText(_ problem: Problem) -> String {
        switch problem {
        case .empty: L("Add hours, or close the day.")
        case .invalidTime: L("Pick each time from the list.")
        case .endBeforeStart: L("A range ends before it starts. Pick a later end.")
        case .overlap: L("Two ranges overlap. Move one so they don’t.")
        }
    }

    /// Which rows of a day are wrong.
    static func flags(_ ranges: [TeamTimeRange]) -> [Bool] {
        ranges.enumerated().map { index, range in
            guard isTime(range.start), isTime(range.end) else { return true }
            let start = startMinutes(range.start), end = endMinutes(range.end)
            if end <= start { return true }
            return ranges.enumerated().contains { other, o in
                guard other != index, isTime(o.start), isTime(o.end) else { return false }
                let os = startMinutes(o.start), oe = endMinutes(o.end)
                return oe > os && start < oe && os < end
            }
        }
    }

    static func dayIsValid(_ day: TeamDay) -> Bool { !day.enabled || problem(ranges(day)) == nil }

    static func dayMinutes(_ day: TeamDay) -> Int { day.enabled && dayIsValid(day) ? minutes(ranges(day)) : 0 }

    static func sameRanges(_ a: [TeamTimeRange], _ b: [TeamTimeRange]) -> Bool { sorted(a) == sorted(b) }

    static func sameWeek(_ a: [TeamDay], _ b: [TeamDay]) -> Bool {
        zip(ordered(a), ordered(b)).allSatisfy { sameRanges(ranges($0), ranges($1)) }
    }

    static func stats(_ schedule: [TeamDay]) -> (openDays: Int, hours: Double) {
        let week = ordered(schedule)
        let minutes = week.reduce(0) { $0 + dayMinutes($1) }
        return (week.filter(\.enabled).count, (Double(minutes) / 60 * 10).rounded() / 10)
    }

    /// The next range to add to a day: after the last, keeping a gap for a break.
    static func next(_ ranges: [TeamTimeRange]) -> TeamTimeRange? {
        let list = minuteRanges(sorted(ranges))
        guard let last = list.last, let first = list.first else { return TeamTimeRange(start: "09:00", end: "17:00") }
        let start = last.end + 120
        if start + 60 <= 1440 { return TeamTimeRange(start: time(start), end: time(min(start + 240, 1440))) }
        if first.start >= 120 { return TeamTimeRange(start: time(max(0, first.start - 180)), end: time(first.start - 60)) }
        return nil
    }

    /// A break in the widest range: "9–20" becomes "9–14" and "16–20".
    static func addBreak(_ ranges: [TeamTimeRange]) -> [TeamTimeRange]? {
        let list = minuteRanges(sorted(ranges))
        guard let widest = list.max(by: { ($0.end - $0.start) < ($1.end - $1.start) }), widest.end - widest.start >= 180 else { return nil }
        let middle = Int((Double(widest.start + widest.end) / 2 / 15).rounded()) * 15
        var out: [(start: Int, end: Int)] = []
        var split = false
        for range in list {
            if !split && range.start == widest.start && range.end == widest.end {
                out.append((range.start, middle - 60)); out.append((middle + 60, range.end)); split = true
            } else { out.append(range) }
        }
        return out.map { TeamTimeRange(start: time($0.start), end: time($0.end)) }
    }

    // MARK: Words

    private static let reference: Date = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 12))!
    }()

    private static func weekdayText(_ key: String, _ template: String) -> String {
        let index = dayKeys.firstIndex(of: key) ?? 0
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate(template)
        let text = f.string(from: reference.addingTimeInterval(Double(index) * 86_400)).replacingOccurrences(of: ".", with: "")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func dayName(_ key: String) -> String { weekdayText(key, "EEEE") }
    static func dayShort(_ key: String) -> String { weekdayText(key, "EEE") }

    /// "9:00 a. m."
    static func clock(_ value: String) -> String {
        guard isTime(value) else { return value }
        let m = startMinutes(value)
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        let date = c.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: m / 60, minute: m % 60))!
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: date)
    }

    static func endClock(_ value: String) -> String { value == "23:59" ? L("Midnight") : clock(value) }

    /// "9:00 a. m.–2:00 p. m., 4:00 p. m.–8:00 p. m."
    static func rangesLabel(_ ranges: [TeamTimeRange]) -> String {
        sorted(ranges).map { "\(clock($0.start))–\(endClock($0.end))" }.joined(separator: ", ")
    }

    /// Runs of days with the same hours: "Lun–Vie 9:00–17:00 · Sáb–Dom cerrado".
    static func summary(_ schedule: [TeamDay]) -> [(days: String, hours: String, open: Bool)] {
        let week = ordered(schedule)
        func key(_ day: TeamDay) -> String { day.enabled ? sorted(ranges(day)).map { "\($0.start)-\($0.end)" }.joined(separator: ",") : "closed" }
        var runs: [(from: String, to: String, day: TeamDay)] = []
        for day in week {
            if let last = runs.last, key(last.day) == key(day) { runs[runs.count - 1].to = day.day }
            else { runs.append((day.day, day.day, day)) }
        }
        return runs.map { run in
            let days = run.from == run.to ? dayShort(run.from) : "\(dayShort(run.from))–\(dayShort(run.to))"
            return (days, run.day.enabled ? rangesLabel(ranges(run.day)) : L("closed"), run.day.enabled)
        }
    }

    static func duration(_ minutes: Int) -> String {
        if minutes == 0 { return L("None") }
        if minutes < 60 { return LF("%d min", minutes) }
        let hours = minutes / 60, rest = minutes % 60
        if rest == 0 { return LP(hours, "1 hour", "%d hours") }
        return LF("%1$d h %2$d min", hours, rest)
    }

    static func notice(_ minutes: Int) -> String {
        if minutes == 0 { return L("None") }
        if minutes % 1440 == 0 { return LP(minutes / 1440, "1 day", "%d days") }
        return duration(minutes)
    }

    static func horizon(_ days: Int?) -> String {
        guard let days else { return L("No limit") }
        if days % 365 == 0 { return LP(days / 365, "1 year", "%d years") }
        if days % 30 == 0 { return LP(days / 30, "1 month", "%d months") }
        if days % 7 == 0 { return LP(days / 7, "1 week", "%d weeks") }
        return LP(days, "1 day", "%d days")
    }

    static let durationOptions = [15, 30, 45, 60, 75, 90, 105, 120, 135, 150, 165, 180]
    static let bufferOptions = [0, 15, 30, 45, 60]
    static let noticeOptions = [0, 30, 60, 120, 180, 240, 720, 1440, 2880]
    static let horizonOptions = [7, 14, 30, 60, 90, 180, 365]
    static let lateCancelOptions = [2, 4, 12, 24, 48, 72]

    /// The options, with a saved value that isn't one of them kept in order.
    static func withSaved(_ options: [Int], _ value: Int) -> [Int] {
        options.contains(value) ? options : (options + [value]).sorted()
    }

    /// Every quarter hour of the day.
    static let startTimes: [String] = (0..<96).map { time($0 * 15) }
    /// Every quarter hour after midnight, and "Midnight".
    static let endTimes: [String] = (1..<96).map { time($0 * 15) } + ["23:59"]

    // MARK: Time zones

    /// "Ciudad de México (UTC−6)": the web's `timeZoneLabel`, the same words as the time zone picker.
    static func zoneLabel(_ identifier: String) -> String { PlacesTimeZones.label(identifier) }
}

// MARK: - The week editor

/// A week of hours: each day open or closed, one or more ranges when open,
/// a bar over the day, and "Copy to…" to give other days the same hours.
struct TeamWeekEditor: View {
    @Binding var schedule: [TeamDay]
    var guide: [TeamDay]? = nil
    var disabled: Bool = false
    var closedHint: String
    var openWord: String = L("Open")
    var closedWord: String = L("Closed")

    @State private var copyFrom: String?
    @State private var remembered: [String: [TeamTimeRange]] = [:]

    private var week: [TeamDay] { TeamHours.ordered(schedule) }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(week, id: \.day) { day in
                if day.day != week.first?.day { RowDivider() }
                dayRow(day)
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    private func setRanges(_ key: String, _ ranges: [TeamTimeRange]) {
        schedule = week.map { $0.day == key ? TeamHours.day(key, ranges) : $0 }
    }

    private func toggle(_ day: TeamDay, _ open: Bool) {
        if !open {
            remembered[day.day] = TeamHours.ranges(day)
            setRanges(day.day, [])
            return
        }
        let fromGuide = TeamHours.ranges(guide.flatMap { TeamHours.ordered($0).first(where: { $0.day == day.day }) })
        let back = remembered[day.day] ?? []
        setRanges(day.day, !back.isEmpty ? back : (!fromGuide.isEmpty ? fromGuide : TeamHours.nineToFive))
    }

    @ViewBuilder
    private func dayRow(_ day: TeamDay) -> some View {
        let valid = TeamHours.dayIsValid(day)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(TeamHours.dayName(day.day)).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    Text(day.enabled ? (valid ? TeamHours.duration(TeamHours.dayMinutes(day)) : L("Check the times")) : closedWord)
                        .font(Theme.text(12)).foregroundStyle(valid ? Theme.inkSoft : Theme.destructive)
                }
                Spacer()
                Toggle(isOn: Binding(get: { day.enabled }, set: { toggle(day, $0) })) { EmptyView() }
                    .toggleStyle(PMSwitchStyle())
                    .fixedSize()
                    .disabled(disabled)
                    .accessibilityLabel(LF("%@ open", TeamHours.dayName(day.day)))
                Text(day.enabled ? openWord : closedWord).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    .frame(minWidth: 56, alignment: .leading)
            }
            if day.enabled {
                TeamRangesEditor(ranges: Binding(get: { TeamHours.ranges(day) }, set: { setRanges(day.day, $0) }), guide: TeamHours.ranges(guide.flatMap { TeamHours.ordered($0).first(where: { $0.day == day.day }) }), disabled: disabled)
            } else {
                Text(closedHint).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            if !disabled {
                Button {
                    withAnimation { copyFrom = copyFrom == day.day ? nil : day.day }
                } label: {
                    HStack(spacing: 6) {
                        Glyph("copy", size: 14)
                        Text(L("Copy to…"))
                        Glyph("chevron-down", size: 14).rotationEffect(.degrees(copyFrom == day.day ? 180 : 0))
                    }
                    .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                    .frame(height: 36)
                }
                .buttonStyle(.plain)
                if copyFrom == day.day {
                    TeamCopyPanel(from: day) { targets in
                        let ranges = TeamHours.ranges(day)
                        schedule = week.map { targets.contains($0.day) ? TeamHours.day($0.day, ranges) : $0 }
                        copyFrom = nil
                    } onCancel: { copyFrom = nil }
                }
            }
        }
        .padding(12)
        .background(day.enabled ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.wash(Theme.surfaceMuted, 45)))
    }
}

private struct TeamCopyPanel: View {
    let from: TeamDay
    let onApply: (Set<String>) -> Void
    let onCancel: () -> Void
    @State private var targets: Set<String> = []

    var body: some View {
        let others = TeamHours.dayKeys.filter { $0 != from.day }
        VStack(alignment: .leading, spacing: 10) {
            Text(LF("Give these days %1$@’s hours (%2$@):", TeamHours.dayName(from.day), from.enabled ? TeamHours.rangesLabel(TeamHours.ranges(from)) : L("Closed")))
                .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
            HStack(spacing: 8) {
                FilterChip(title: L("Weekdays"), isSelected: false) { targets = Set(TeamHours.weekdays.filter { $0 != from.day }) }
                FilterChip(title: L("Every day"), isSelected: false) { targets = Set(others) }
                FilterChip(title: L("None"), isSelected: false) { targets = [] }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(others, id: \.self) { day in
                        FilterChip(title: TeamHours.dayShort(day), isSelected: targets.contains(day)) {
                            if targets.contains(day) { targets.remove(day) } else { targets.insert(day) }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                PMButton(L("Cancel"), variant: .outline, size: .compact, action: onCancel)
                PMButton(targets.isEmpty ? L("Copy") : LP(targets.count, "Copy to 1 day", "Copy to %d days"), size: .compact) { onApply(targets) }
                    .disabled(targets.isEmpty)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }
}

/// One day's hours: a start–end pair per range, add a break or more hours, × to take one away.
struct TeamRangesEditor: View {
    @Binding var ranges: [TeamTimeRange]
    var guide: [TeamTimeRange]? = nil
    var disabled: Bool = false

    var body: some View {
        let flags = TeamHours.flags(ranges)
        let problem = TeamHours.problem(ranges)
        let split = TeamHours.addBreak(ranges)
        let more = ranges.count < 12 ? TeamHours.next(ranges) : nil
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(ranges.enumerated()), id: \.offset) { index, range in
                HStack(spacing: 6) {
                    TeamTimeMenu(value: Binding(get: { range.start }, set: { update(index, start: $0) }), options: TeamHours.startTimes, invalid: flags[safe: index] ?? false, label: { TeamHours.clock($0) })
                    Text("–").foregroundStyle(Theme.inkSoft)
                    TeamTimeMenu(value: Binding(get: { range.end }, set: { update(index, end: $0) }), options: TeamHours.endTimes, invalid: flags[safe: index] ?? false, label: { TeamHours.endClock($0) })
                    if ranges.count > 1 && !disabled {
                        IconCircleButton(systemImage: "x", label: L("Remove these hours"), bordered: false) { ranges.remove(at: index) }
                    }
                }
                .disabled(disabled)
            }
            if !disabled {
                HStack(spacing: 16) {
                    Button { if let split { ranges = split } } label: { GlyphLabel(L("Add a break"), icon: "coffee", size: 14) }
                        .disabled(split == nil)
                    Button { if let more { ranges = TeamHours.sorted(ranges + [more]) } } label: { GlyphLabel(L("Add hours"), icon: "plus", size: 14) }
                        .disabled(more == nil)
                }
                .font(Theme.text(14, weight: .bold))
                .foregroundStyle(Theme.blue)
                .buttonStyle(.plain)
            }
            if let problem {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TeamHours.problemText(problem)).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral)
                    if problem == .endBeforeStart {
                        Text(L("Open past midnight? End this day at Midnight and start the next one at 12:00 AM.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            TeamRangesBar(ranges: ranges, guide: guide)
        }
    }

    private func update(_ index: Int, start: String? = nil, end: String? = nil) {
        guard ranges.indices.contains(index) else { return }
        if let start { ranges[index].start = start }
        if let end { ranges[index].end = end }
    }
}

/// A time picked from the day's quarter hours, drawn as a field.
struct TeamTimeMenu: View {
    @Binding var value: String
    let options: [String]
    var invalid: Bool = false
    let label: (String) -> String

    var body: some View {
        Menu {
            Picker("", selection: $value) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
        } label: {
            // The web's NativeSelect: 16 corners, a grey border (coral when wrong), the chevron at the right.
            HStack(spacing: 4) {
                Text(label(value)).font(Theme.text(14)).foregroundStyle(Theme.inkStrong).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Glyph("chevron-down", size: 16).foregroundStyle(Theme.inkSoft)
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(maxWidth: 160, minHeight: 40)
            .background(Theme.inputFill, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous).strokeBorder(invalid ? Theme.coral : Theme.borderSoft, lineWidth: 1))
        }
    }
}

/// Where the open hours sit in the day, 0 to 24, the guide drawn faintly under them.
struct TeamRangesBar: View {
    let ranges: [TeamTimeRange]
    var guide: [TeamTimeRange]? = nil
    var showHours: Bool = true

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.inkSoft.opacity(0.12))
                    ForEach(Array(TeamHours.minuteRanges(guide ?? []).enumerated()), id: \.offset) { _, range in
                        Rectangle().fill(Theme.blue.opacity(0.22))
                            .frame(width: max(0, CGFloat(range.end - range.start) / 1440 * width))
                            .offset(x: CGFloat(range.start) / 1440 * width)
                    }
                    ForEach([0.25, 0.5, 0.75], id: \.self) { mark in
                        Rectangle().fill(Theme.borderSoft).frame(width: 1).offset(x: mark * width)
                    }
                    ForEach(Array(TeamHours.minuteRanges(ranges).filter { $0.end > $0.start }.enumerated()), id: \.offset) { _, range in
                        Capsule().fill(Theme.blue)
                            .frame(width: max(2, CGFloat(range.end - range.start) / 1440 * width))
                            .offset(x: CGFloat(range.start) / 1440 * width)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            if showHours {
                HStack {
                    ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                        Text("\(hour)").font(Theme.text(10, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        if hour != 24 { Spacer(minLength: 0) }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The week in runs ("Lun–Vie 9:00–17:00"), for reading.
struct TeamWeekList: View {
    let week: [TeamDay]
    var closedWord: String = L("Day off")

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(TeamHours.summary(week).enumerated()), id: \.offset) { _, run in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(run.days).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong).frame(width: 90, alignment: .leading)
                    Text(run.open ? run.hours : closedWord).font(Theme.text(14)).foregroundStyle(run.open ? Theme.inkStrong : Theme.inkSoft)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
