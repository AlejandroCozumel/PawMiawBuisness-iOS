//
//  SchedAgendaViews.swift
//  PawMiawNegocios
//
//  The Agenda's time grid (web agenda/agenda-grid.tsx): people or rooms side
//  by side for one day, or the seven days of a week, under a 72 pt time
//  gutter in 30-minute slots 64 tall. Closed time is grey, open time a person
//  doesn't work is hatched with why, today has the red "now" line. A visit is
//  a block in its status colour (a 4 pt edge, washed while someone waits, is
//  with them or is done; a requested online booking is dashed as
//  "Por confirmar"); visits that overlap sit side by side, as photos when the
//  column is too narrow, then "+N". Tap empty time to book there. The grid
//  scrolls both ways inside its card with the column heads on top. No drag
//  here: the edit sheet moves a visit.
//

import SwiftUI

/// A pet drawn on a block (a family's pets or a session's places).
struct SchedBlockPet: Hashable {
    let name: String
    let species: String?
    let photo: String?
}

/// One thing on the Agenda: a visit, a family's pets booked together, or a group session.
struct SchedBlock: Identifiable, Hashable {
    let id: String
    let appointmentId: String?
    let sessionId: String?
    let start: Date
    let end: Date
    let status: String
    let title: String
    let service: String
    let client: String?
    let memberId: String?
    let memberName: String?
    let roomId: String?
    let room: String?
    let photo: String?
    let species: String?
    let online: Bool
    let doubleBooked: Bool
    let asking: Bool
    let repeats: Bool
    let places: String?
    /// Pets booked together (a family's, a session's): drawn as a stack.
    var pets: [SchedBlockPet] = []

    var requested: Bool { status == "requested" }
    var gone: Bool { SchedStatus.gone.contains(status) }
    var day: String { SchedDay.key(start) }
    var isSession: Bool { sessionId != nil }
    /// What the block says first: the pet(s), or the session and its places.
    var heading: String { isSession ? [service, places].compactMap { $0 }.joined(separator: " · ") : title }

    static func visit(_ a: SchedAppointment, title: String? = nil, pets: [SchedBlockPet] = []) -> SchedBlock? {
        guard let start = a.start else { return nil }
        return SchedBlock(id: a.id, appointmentId: a.id, sessionId: nil, start: start, end: a.end ?? start.addingTimeInterval(30 * 60), status: a.status,
                          title: title ?? a.petName, service: a.serviceLabel, client: a.clientName, memberId: a.assignedMember?.id, memberName: a.assignedMember?.name,
                          roomId: a.roomId, room: a.room, photo: a.petPhotoUrl, species: a.petSpecies, online: a.bookedOnline == true,
                          doubleBooked: a.doubleBooked == true, asking: a.familyAsking, repeats: a.seriesId != nil, places: nil, pets: pets)
    }

    static func session(_ s: SchedSession, fallback: SchedAppointment? = nil) -> SchedBlock? {
        guard let start = DateText.parse(s.startsAt) ?? fallback?.start else { return nil }
        let staying = s.stayingPets
        let status = staying.contains { $0.status == "in_progress" } ? "in_progress"
            : (!staying.isEmpty && staying.allSatisfy { $0.status == "completed" }) ? "completed"
            : staying.contains { $0.status == "checked_in" } ? "checked_in" : "scheduled"
        let label = s.serviceLabel ?? fallback?.serviceLabel ?? L("Group session")
        return SchedBlock(id: "session:\(s.id)", appointmentId: nil, sessionId: s.id, start: start, end: DateText.parse(s.endsAt) ?? start.addingTimeInterval(60 * 60), status: status,
                          title: label, service: label, client: nil, memberId: s.assignedMember?.id ?? fallback?.assignedMember?.id, memberName: s.assignedMember?.name ?? fallback?.assignedMember?.name,
                          roomId: s.roomId ?? fallback?.roomId, room: s.room ?? fallback?.room, photo: nil, species: nil, online: s.onlineBookingOpen == true,
                          doubleBooked: s.doubleBooked == true, asking: false, repeats: false, places: s.placesLabel,
                          pets: staying.map { SchedBlockPet(name: $0.name ?? "", species: $0.species, photo: $0.photoUrl) })
    }

    /// The visits as the Agenda draws them: a session once, a family's pets booked together once,
    /// sessions nobody joined yet still holding their time (web lib/group-visits.ts `foldAgendaVisits`).
    static func fold(_ appointments: [SchedAppointment], sessions: [SchedSession]) -> [SchedBlock] {
        var out: [SchedBlock] = []
        var seen = Set<String>()
        let sessionById = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for a in appointments {
            if let group = a.group, a.isGone, group.isSession || !group.stayingPets.isEmpty { continue }
            guard let group = a.group, !a.isGone else {
                if let block = visit(a) { out.append(block) }
                continue
            }
            if group.isSession {
                guard seen.insert(group.id).inserted else { continue }
                if let block = session(sessionById[group.id] ?? group, fallback: a) { out.append(block) }
                continue
            }
            let staying = group.stayingPets
            if staying.count < 2 {
                if let block = visit(a) { out.append(block) }
                continue
            }
            guard seen.insert(group.id).inserted else { continue }
            let pets = staying.map { SchedBlockPet(name: $0.name ?? "", species: $0.species, photo: $0.photoUrl) }
            if let block = visit(a, title: schedNames(staying.compactMap(\.name)), pets: pets) { out.append(block) }
        }
        for s in sessions where s.status == "active" && !seen.contains(s.id) {
            seen.insert(s.id)
            if let block = session(s) { out.append(block) }
        }
        return out.sorted { $0.start < $1.start }
    }
}

/// A column of the grid: a person, nobody yet, a room, or one day of the week.
struct SchedColumn: Identifiable, Hashable {
    enum Kind: Hashable { case person, unassigned, room, day }
    let id: String
    let title: String
    var detail: String? = nil
    let kind: Kind
    var memberId: String? = nil
    var roomId: String? = nil
    let day: String
    /// The location's open ranges that day.
    let open: [SchedMinuteRange]
    /// A person's working ranges that day (nil = the location's hours).
    var working: [SchedMinuteRange]? = nil
    var offNote: String? = nil
    var image: String? = nil
    /// Who a visit booked from this column is for (web `createMemberId`); nil = nobody can book here.
    var createMemberId: String? = nil

    var isToday: Bool { day == SchedDay.today }

    func holds(_ block: SchedBlock) -> Bool {
        switch kind {
        case .day: block.day == day
        case .room: block.roomId == roomId
        case .unassigned: block.memberId == nil
        case .person: block.memberId == memberId
        }
    }

    var bookRoomId: String? { kind == .room ? roomId : nil }
}

// MARK: - The grid's arithmetic (web lib/agenda.ts)

enum SchedGrid {
    static let slotMinutes = 30
    static let slotHeight: CGFloat = 64
    static let gutter: CGFloat = 72
    static let photoSlot: CGFloat = 30

    struct Range: Hashable {
        let min: Int
        let max: Int
        var rows: [Int] { Array(stride(from: min, to: max, by: slotMinutes)) }
    }

    struct Place { let lane: Int; let lanes: Int; let cluster: Int }

    struct Fit { let photo: Bool; let slots: Int; let shown: Int }

    static func minutes(_ block: SchedBlock) -> (start: Int, end: Int) {
        let start = SchedDay.minuteOfDay(block.start)
        let raw = SchedDay.minuteOfDay(block.end)
        return (start, raw <= start ? start + slotMinutes : raw)
    }

    /// The rows to draw: the opening hours, stretched to fit any visit outside them.
    static func range(_ blocks: [SchedBlock], open: [SchedMinuteRange]) -> Range {
        var low = open.map(\.start).min() ?? 9 * 60
        var high = open.map { Swift.min($0.end, 1439) }.max() ?? 17 * 60
        for block in blocks {
            let start = SchedDay.minuteOfDay(block.start)
            let end = SchedDay.minuteOfDay(block.end)
            low = Swift.min(low, start)
            high = Swift.max(high, end < start ? 1440 : end)
        }
        low = (low / slotMinutes) * slotMinutes
        high = Swift.min(1440, Int((Double(high) / Double(slotMinutes)).rounded(.up)) * slotMinutes)
        if high <= low { high = low + slotMinutes }
        return Range(min: low, max: high)
    }

    static func position(_ block: SchedBlock, min: Int) -> (top: CGFloat, height: CGFloat) {
        let span = minutes(block)
        let top = CGFloat(span.start - min) / CGFloat(slotMinutes) * slotHeight
        let height = Swift.max(CGFloat(span.end - span.start) / CGFloat(slotMinutes) * slotHeight, 40)
        return (top, height)
    }

    /// Overlapping visits in one column sit side by side.
    static func lanes(_ blocks: [SchedBlock]) -> [String: Place] {
        var out: [String: Place] = [:]
        var cluster: [(id: String, lane: Int)] = []
        var laneEnds: [Date] = []
        var clusterEnd = Date.distantPast
        var index = 0
        func close() {
            for entry in cluster { out[entry.id] = Place(lane: entry.lane, lanes: Swift.max(1, laneEnds.count), cluster: index) }
            if !cluster.isEmpty { index += 1 }
            cluster = []
            laneEnds = []
        }
        for block in blocks.sorted(by: { $0.start < $1.start }) {
            if block.start >= clusterEnd { close() }
            if let lane = laneEnds.firstIndex(where: { $0 <= block.start }) {
                laneEnds[lane] = block.end
                cluster.append((block.id, lane))
            } else {
                cluster.append((block.id, laneEnds.count))
                laneEnds.append(block.end)
            }
            clusterEnd = Swift.max(clusterEnd, block.end)
        }
        close()
        return out
    }

    /// Cards while each has room for a name, else photos, else photos and "+N".
    static func fit(lanes: Int, width: CGFloat, cardMin: CGFloat) -> Fit {
        let usable = width > 0 ? width - 8 : .infinity
        if usable / CGFloat(lanes) >= cardMin { return Fit(photo: false, slots: lanes, shown: lanes) }
        if usable / CGFloat(lanes) >= photoSlot { return Fit(photo: true, slots: lanes, shown: lanes) }
        let slots = Swift.max(2, Int(usable / photoSlot))
        return Fit(photo: true, slots: slots, shown: slots - 1)
    }

    /// The gaps between ranges inside [from, to): what the grid greys out.
    static func gaps(_ ranges: [SchedMinuteRange], from: Int, to: Int) -> [SchedMinuteRange] {
        var out: [SchedMinuteRange] = []
        var cursor = from
        for range in ranges.sorted(by: { $0.start < $1.start }) {
            if range.start > cursor { out.append(SchedMinuteRange(start: cursor, end: Swift.min(range.start, to))) }
            cursor = Swift.max(cursor, range.end)
        }
        if cursor < to { out.append(SchedMinuteRange(start: cursor, end: to)) }
        return out.filter { $0.end > $0.start }
    }

    static func intersect(_ a: [SchedMinuteRange], _ b: [SchedMinuteRange]) -> [SchedMinuteRange] {
        var out: [SchedMinuteRange] = []
        for left in a {
            for right in b {
                let start = Swift.max(left.start, right.start), end = Swift.min(left.end, right.end)
                if end > start { out.append(SchedMinuteRange(start: start, end: end)) }
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    static func y(_ minute: Int, _ range: Range) -> CGFloat { CGFloat(minute - range.min) / CGFloat(slotMinutes) * slotHeight }
}

// MARK: - The grid

struct SchedAgendaGrid: View {
    let columns: [SchedColumn]
    let blocks: [SchedBlock]
    let range: SchedGrid.Range
    /// The week: narrower columns, a block says less.
    var compact = false
    let canCreate: Bool
    /// The block's second line: its room on a person's column, its person on a room's.
    let secondary: (SchedBlock) -> String?
    let onOpen: (SchedBlock) -> Void
    let onCreate: (SchedColumn, Int) -> Void

    @State private var width: CGFloat = 0
    @State private var scrolledFor: String?

    private static let headHeight: CGFloat = 57

    /// A closed day with nothing on it (the week's "Cerrado") is narrow, so the open days get the room.
    private var narrow: Set<String> {
        Set(columns.filter { col in col.kind == .day && col.open.isEmpty && !blocks.contains { col.holds($0) } }.map(\.id))
    }

    private var widths: [CGFloat] {
        let minimum: CGFloat = compact ? 144 : 224
        let shut = narrow
        let weights = columns.map { shut.contains($0.id) ? 0.45 : 1.0 }
        let total = max(weights.reduce(0, +), 0.01)
        let unit = max(0, width - SchedGrid.gutter) / CGFloat(total)
        return columns.indices.map { i in
            max(shut.contains(columns[i].id) ? 96 : minimum, unit * CGFloat(weights[i]))
        }
    }

    private var bodyHeight: CGFloat { CGFloat(range.rows.count) * SchedGrid.slotHeight }

    /// Where the grid opens: now when today is shown and open, else the first visit.
    private var scrollMinute: Int? {
        let now = SchedDay.minuteOfDay(Date())
        if columns.contains(where: \.isToday) && now >= range.min && now < range.max { return now }
        return blocks.filter { !$0.gone }.map { SchedDay.minuteOfDay($0.start) }.min()
    }

    var body: some View {
        let widths = self.widths
        let shut = narrow
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        HStack(alignment: .top, spacing: 0) {
                            gutter
                            ForEach(Array(columns.enumerated()), id: \.element.id) { index, col in
                                columnBody(col, width: widths[index])
                            }
                        }
                    } header: {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: SchedGrid.gutter, height: Self.headHeight)
                            ForEach(Array(columns.enumerated()), id: \.element.id) { index, col in
                                SchedColumnHead(column: col, compact: compact, narrow: shut.contains(col.id))
                                    .frame(width: widths[index], height: Self.headHeight)
                            }
                        }
                        .background(Theme.surface)
                        .overlay(alignment: .bottom) { RowDivider() }
                    }
                }
            }
            .containerRelativeFrame(.vertical) { length, _ in
                min(Self.headHeight + bodyHeight, max(320, min(length * 0.75, 896)))
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .task(id: "\(range.min)|\(columns.map(\.id).joined())") {
                let key = "\(range.min)|\(columns.map(\.id).joined())"
                guard scrolledFor != key else { return }
                scrolledFor = key
                guard let minute = scrollMinute else { return }
                let target = (minute / SchedGrid.slotMinutes) * SchedGrid.slotMinutes - SchedGrid.slotMinutes
                guard target > range.min else { return }
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo("row-\(target)", anchor: UnitPoint(x: 0, y: 0)) }
            }
        }
    }

    // MARK: Gutter

    private var gutter: some View {
        VStack(spacing: 0) {
            ForEach(range.rows, id: \.self) { minute in
                Text(minute % 60 == 0 ? SchedDay.timeLabel(minute) : "")
                    .font(Theme.text(11.2, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .frame(width: SchedGrid.gutter, height: SchedGrid.slotHeight, alignment: .topTrailing)
                    .overlay(alignment: .bottom) { RowDivider() }
                    .id("row-\(minute)")
            }
        }
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.borderSoft).frame(width: 1) }
    }

    // MARK: A column

    private func columnBody(_ col: SchedColumn, width: CGFloat) -> some View {
        let inColumn = blocks.filter { col.holds($0) }
        let lanes = SchedGrid.lanes(inColumn)
        var fits: [Int: SchedGrid.Fit] = [:]
        var hidden: [Int: [SchedBlock]] = [:]
        for block in inColumn {
            guard let place = lanes[block.id] else { continue }
            if fits[place.cluster] == nil { fits[place.cluster] = SchedGrid.fit(lanes: place.lanes, width: width, cardMin: compact ? 84 : 96) }
            if place.lane >= fits[place.cluster]!.shown { hidden[place.cluster, default: []].append(block) }
        }
        let closed = SchedGrid.gaps(col.open, from: range.min, to: range.max)
        let off = col.working.map { SchedGrid.intersect(col.open, SchedGrid.gaps($0, from: range.min, to: range.max)) } ?? []
        let creatable = canCreate && col.createMemberId != nil

        return ZStack(alignment: .topLeading) {
            ForEach(closed, id: \.start) { gap in
                Rectangle().fill(Theme.wash(Theme.inkSoft, 9))
                    .frame(width: width, height: SchedGrid.y(gap.end, range) - SchedGrid.y(gap.start, range))
                    .offset(y: SchedGrid.y(gap.start, range))
                    .allowsHitTesting(false)
            }
            ForEach(off, id: \.start) { gap in
                SchedOffTime(note: gap.end - gap.start >= SchedGrid.slotMinutes ? col.offNote : nil)
                    .frame(width: width, height: SchedGrid.y(gap.end, range) - SchedGrid.y(gap.start, range))
                    .offset(y: SchedGrid.y(gap.start, range))
                    .allowsHitTesting(false)
            }
            ForEach(range.rows, id: \.self) { minute in
                SchedGridSlot(minute: minute, creatable: creatable) { onCreate(col, minute) }
                    .frame(width: width, height: SchedGrid.slotHeight)
                    .offset(y: SchedGrid.y(minute, range))
            }
            if col.isToday {
                TimelineView(.everyMinute) { context in
                    let now = SchedDay.minuteOfDay(context.date)
                    if now >= range.min && now < range.max {
                        HStack(spacing: 0) {
                            Circle().fill(Theme.destructive).frame(width: 8, height: 8).offset(x: -4)
                            Rectangle().fill(Theme.destructive).frame(height: 1).padding(.leading, -4)
                        }
                        .frame(width: width, height: 8)
                        .offset(y: SchedGrid.y(now, range) - 4)
                        .allowsHitTesting(false)
                    }
                }
            }
            ForEach(inColumn) { block in
                let place = lanes[block.id] ?? SchedGrid.Place(lane: 0, lanes: 1, cluster: -1)
                let fit = fits[place.cluster] ?? SchedGrid.Fit(photo: false, slots: 1, shown: 1)
                if place.lane < fit.shown {
                    let spot = SchedGrid.position(block, min: range.min)
                    let inset: CGFloat = fit.photo ? 1.6 : 4
                    let laneWidth = width / CGFloat(fit.slots)
                    SchedGridBlock(block: block, height: spot.height - 4, lanes: fit.slots, photoOnly: fit.photo, compact: compact, secondary: secondary(block)) { onOpen(block) }
                        .frame(width: max(0, laneWidth - inset * 2), height: max(0, spot.height - 4))
                        .offset(x: CGFloat(place.lane) * laneWidth + inset, y: spot.top + 2)
                }
            }
            ForEach(hidden.keys.sorted(), id: \.self) { cluster in
                let rest = hidden[cluster] ?? []
                let fit = fits[cluster]!
                let group = inColumn.filter { lanes[$0.id]?.cluster == cluster }
                let top = group.map { SchedGrid.position($0, min: range.min).top }.min() ?? 0
                let laneWidth = width / CGFloat(fit.slots)
                SchedMoreVisits(visits: rest, onOpen: onOpen)
                    .frame(minWidth: max(28, laneWidth - 4.8), alignment: .trailing)
                    .offset(x: width - max(28, laneWidth - 4.8) - 4, y: top + 2)
            }
        }
        .frame(width: width, height: bodyHeight, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.borderSoft).frame(width: 1) }
    }
}

// MARK: - The grid's pieces

/// A column's head: who or what (a 32 disc), and a small uppercase detail.
private struct SchedColumnHead: View {
    let column: SchedColumn
    let compact: Bool
    let narrow: Bool

    private var todayInWeek: Bool { column.isToday && compact }

    var body: some View {
        HStack(spacing: 10) {
            if !narrow { disc }
            VStack(alignment: .leading, spacing: 1) {
                Text(column.title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                if let detail = column.detail?.nonEmpty {
                    Text(detail.uppercased()).font(Theme.text(11.2, weight: .semibold)).tracking(0.9).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, narrow ? 8 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(todayInWeek ? AnyShapeStyle(Theme.wash(Theme.blue, 8)) : AnyShapeStyle(Theme.surface))
        .overlay(alignment: .leading) { Rectangle().fill(Theme.borderSoft).frame(width: 1) }
    }

    @ViewBuilder private var disc: some View {
        switch column.kind {
        case .day:
            Text(SchedDay.dayNumber(column.day))
                .font(Theme.text(12, weight: .bold))
                .foregroundStyle(todayInWeek ? Theme.onBlue : Theme.inkStrong)
                .frame(width: 32, height: 32)
                .background(todayInWeek ? AnyShapeStyle(Theme.blue) : AnyShapeStyle(Theme.wash(Theme.aqua, 25)), in: Circle())
        case .person:
            if column.image?.nonEmpty != nil {
                Avatar(name: column.title, imageURL: column.image, size: 32)
            } else {
                IconBadge(icon: "user-round", accent: Theme.aqua, size: 32, iconSize: 16, ink: .strong, washPercent: 25)
            }
        case .room:
            IconBadge(icon: "door-open", accent: Theme.aqua, size: 32, iconSize: 16, ink: .strong, washPercent: 25)
        case .unassigned:
            IconBadge(icon: "users-round", accent: Theme.aqua, size: 32, iconSize: 16, ink: .strong, washPercent: 25)
        }
    }
}

/// A half hour of a column: the line under it (solid or dashed, as on the web) and a tap that books it.
private struct SchedGridSlot: View {
    let minute: Int
    let creatable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(SchedSlotStyle())
        .disabled(!creatable)
        .overlay(alignment: .bottom) {
            if minute % 60 == 0 {
                RowDivider()
            } else {
                SchedDashedLine().stroke(Theme.borderSoft.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3])).frame(height: 1)
            }
        }
        .accessibilityLabel(creatable ? LF("Book at %@", SchedDay.timeLabel(minute)) : "")
        .accessibilityHidden(!creatable)
    }
}

private struct SchedSlotStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.wash(Theme.blue, 18) : Theme.wash(Theme.blue, 0))
    }
}

private struct SchedDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
    }
}

/// Open time a person doesn't work: pink hatching, and why (a day off, not working).
private struct SchedOffTime: View {
    let note: String?

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .style(Theme.wash(Theme.inkSoft, 5)))
            let step: CGFloat = 14 * 1.4142
            var x: CGFloat = 0
            while x < size.width + size.height {
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x - size.height, y: size.height))
                context.stroke(line, with: .style(Theme.wash(Theme.pink, 26)), lineWidth: 6 * 1.4142)
                x += step
            }
        }
        .overlay(alignment: .topLeading) {
            if let note {
                Text(note)
                    .font(Theme.text(10.9, weight: .bold))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.surface, in: Capsule())
                    .shadow(color: Theme.navy.opacity(0.1), radius: 1.5, y: 1)
                    .padding(6)
            }
        }
        .clipped()
    }
}

/// A visit on the grid (web `VisitBlock`).
private struct SchedGridBlock: View {
    let block: SchedBlock
    let height: CGFloat
    let lanes: Int
    let photoOnly: Bool
    let compact: Bool
    let secondary: String?
    let action: () -> Void

    private var state: ProviderState { ProviderState.appointment(block.status) }
    private var short: Bool { height + 4 < 64 }
    private var showPhoto: Bool { height + 4 >= 28 && lanes <= (compact ? 2 : 3) }
    private var edge: Color { block.doubleBooked ? Theme.destructive : (state == .closed ? Theme.borderSoft : state.color) }
    private var times: String { "\(DateText.time(block.start))–\(DateText.time(block.end))" }

    var body: some View {
        Button(action: action) {
            Group {
                if photoOnly {
                    photo(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.vertical, 4)
                } else {
                    card
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(background)
            .overlay(alignment: .leading) {
                if !block.requested { Rectangle().fill(edge).frame(width: 4) }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            .overlay {
                if block.requested {
                    RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                        .strokeBorder(edge, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                } else {
                    RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                        .strokeBorder(block.doubleBooked ? Theme.destructive : Theme.borderSoft, lineWidth: 1)
                }
            }
            .modifier(SchedBlockShadow(on: !block.requested))
            .opacity(block.gone ? 0.5 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(block.heading) · \(block.service) · \(times)\(block.requested ? " · " + L("To confirm") : "")")
    }

    private var background: AnyShapeStyle {
        if block.requested || state == .closed { return AnyShapeStyle(Theme.surface) }
        switch state {
        case .waiting, .active, .done: return AnyShapeStyle(Theme.wash(state.color, 12))
        default: return AnyShapeStyle(Theme.surface)
        }
    }

    private var card: some View {
        HStack(alignment: short ? .center : .top, spacing: compact ? 6 : 8) {
            if showPhoto { photo(compact || short ? 20 : 28) }
            VStack(alignment: .leading, spacing: 1) {
                titleLine
                if !short {
                    lineTwo.font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                if block.doubleBooked { Glyph("triangle-alert", size: 14).foregroundStyle(Theme.destructive).accessibilityLabel(L("Double booked")) }
                if block.asking { Glyph("message-circle-question", size: 14).foregroundStyle(Theme.pink).accessibilityLabel(L("The family asked for a change")) }
                if block.repeats { Glyph("repeat", size: 12).foregroundStyle(Theme.inkSoft).accessibilityLabel(L("Repeats")) }
                if block.requested && short { Glyph("clock-3", size: 12).foregroundStyle(Theme.inkStrong) }
                if block.online { Glyph("globe", size: 12).foregroundStyle(Theme.inkSoft).accessibilityLabel(L("Booked online")) }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
    }

    private var titleLine: some View {
        var text = Text(block.heading).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
        if !compact && !block.isSession {
            text = text + Text(" · \(block.service)").font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        }
        return text.strikethrough(block.gone).lineLimit(1)
    }

    private var lineTwo: Text {
        var text = Text("")
        if block.requested { text = Text(L("To confirm") + " · ").bold().foregroundStyle(Theme.inkStrong) }
        text = text + Text(times)
        if let secondary = secondary?.nonEmpty, !compact { text = text + Text(" · \(secondary)") }
        return text
    }

    @ViewBuilder private func photo(_ size: CGFloat) -> some View {
        if block.isSession || block.pets.count > 1 {
            if block.pets.isEmpty {
                Glyph("users-round", size: 14).foregroundStyle(Theme.inkSoft).frame(width: size, height: size)
            } else {
                PetStack(pets: block.pets.map { ($0.name, $0.species, $0.photo) }, size: size, max: photoOnly ? 1 : (compact ? 2 : 3))
            }
        } else {
            PetAvatar(name: block.title, species: block.species, photoURL: block.photo, size: size)
                .opacity(block.gone && photoOnly ? 0.7 : 1)
        }
    }
}

private struct SchedBlockShadow: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.cardShadow() } else { content }
    }
}

/// The visits of a crowded group that don't fit even as photos: "+N", opening the list of them.
private struct SchedMoreVisits: View {
    let visits: [SchedBlock]
    let onOpen: (SchedBlock) -> Void

    var body: some View {
        Menu {
            ForEach(visits) { block in
                Button { onOpen(block) } label: {
                    Text("\(block.heading) · \(block.service)\n\(DateText.time(block.start))–\(DateText.time(block.end))\(block.client.map { " · " + $0 } ?? "")")
                }
            }
        } label: {
            Text("+\(visits.count)")
                .font(Theme.text(11.5, weight: .heavy))
                .foregroundStyle(Theme.onBlue)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .frame(minWidth: 28)
                .background(Theme.blue, in: Capsule())
                .cardShadow()
        }
        .accessibilityLabel(LF("%@ more visits", String(visits.count)))
    }
}

// MARK: - Around the grid

/// A strip across the top of the grid's card (web: the day's closure or special hours).
struct SchedDayStrip: View {
    enum Tone { case special, closed, quiet }
    let tone: Tone
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Glyph("calendar-plus", size: 16)
            Text(text).font(Theme.text(14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tone == .quiet ? Theme.inkSoft : Theme.inkStrong)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill)
        .overlay(alignment: .bottom) { RowDivider() }
    }

    private var fill: AnyShapeStyle {
        switch tone {
        case .special: AnyShapeStyle(Theme.wash(Theme.mango, 12))
        case .closed: AnyShapeStyle(Theme.wash(Theme.pink, 12))
        case .quiet: AnyShapeStyle(Theme.surfaceMuted)
        }
    }
}

/// "Familias pidiendo un cambio" (web provider.schedule.tsx): a pink card, an
/// eyebrow, then the families' visits as white rows (two across on an iPad).
struct SchedAskingCard: View {
    let visits: [SchedAppointment]
    let onOpen: (SchedAppointment) -> Void
    let onSeeAll: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Glyph("message-circle-question", size: 16)
                Text(L("Families asking for a change").uppercased()).font(Theme.text(12, weight: .heavy)).tracking(1.44)
            }
            .foregroundStyle(Theme.inkStrong)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: sizeClass == .regular ? 2 : 1), spacing: 8) {
                ForEach(visits.prefix(4)) { visit in
                    Button { onOpen(visit) } label: { row(visit) }.buttonStyle(.plain)
                }
            }
            if visits.count > 4 {
                Button(action: onSeeAll) {
                    Text(LF("See all %@", String(visits.count))).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(Theme.pink, 8), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.mix(Theme.pink, 40, with: Theme.borderSoft), lineWidth: 1))
    }

    private func row(_ visit: SchedAppointment) -> some View {
        HStack(spacing: 12) {
            PetAvatar(name: visit.petName, species: visit.petSpecies, photoURL: visit.petPhotoUrl, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(visit.petName) · \(visit.confirmationStatus == "cancellation_requested" ? L("wants to cancel") : L("wants to move it"))")
                    .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                Text([DateText.dayTime(visit.start), visit.confirmationPreferredTime.map { LF("prefers %@", $0) }].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            Spacer(minLength: 0)
            Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .shadow(color: Theme.navy.opacity(0.08), radius: 1.5, y: 1)
        .contentShape(Rectangle())
    }
}
