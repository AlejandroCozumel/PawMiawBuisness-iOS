//
//  StaysBoard.swift
//  PawMiawNegocios
//
//  The board (web stays-board.tsx): a row per room (and "No room yet", and a
//  row per sitter for home stays), a column per day, each stay a bar from
//  mid-arrival to mid-departure in the first lane free for its days. A pet
//  still here past its day runs on to the night its room is still held, with
//  a red edge and "Debía salir el …". Tapping an empty day books it.
//

import SwiftUI

// The web's grid: a 8.5rem room column, 3.6rem days, 2.9rem lanes (a 2.4rem bar).
private let dayWidth: CGFloat = 57.6
private let laneHeight: CGFloat = 46.4
private let barHeight: CGFloat = 38.4
private let labelWidth: CGFloat = 136
private let headerHeight: CGFloat = 64

private struct StaysPlaced: Identifiable {
    let stay: StaysStay
    let lane: Int
    let start: Double
    let end: Double
    var id: String { stay.id }
}

private struct StaysBoardRow: Identifiable {
    let id: String
    let unit: StaysUnit?
    /// A home stay row: the sitter's id ("" for nobody yet) and name.
    let home: (sitterId: String, name: String?)?
    let placed: [StaysPlaced]
    let lanes: Int

    var height: CGFloat { CGFloat(lanes) * laneHeight + 17.6 }
}

struct StaysBoardView: View {
    let units: [StaysUnit]
    let stays: [StaysStay]
    let fromDay: String
    let days: Int
    let today: String
    let canBook: Bool
    let offersRooms: Bool
    let offersSitting: Bool
    let onBook: (StaysBookingPreset) -> Void

    private var dayKeys: [String] { (0..<days).map { StaysDay.add(fromDay, $0) } }

    /// Stays in one row as bars, each in the first lane free for its days.
    private func place(_ list: [StaysStay]) -> (placed: [StaysPlaced], lanes: Int) {
        let sorted = list.sorted { ($0.checkInDay, $0.checkInTime ?? "") < ($1.checkInDay, $1.checkInTime ?? "") }
        var laneEnds: [Double] = []
        var placed: [StaysPlaced] = []
        for stay in sorted {
            let startIndex = Double(StaysDay.between(fromDay, stay.checkInDay))
            let start = stay.isDaycare ? startIndex + 0.08 : startIndex + 0.5
            let endDay = stay.lateDeparture == true ? (stay.heldUntilDay ?? stay.checkOutDay) : stay.checkOutDay
            let end = stay.isDaycare
                ? startIndex + 0.92
                : Double(max(StaysDay.between(fromDay, endDay), Int(startIndex) + 1)) + 0.5
            if end <= 0 || start >= Double(days) { continue }
            var lane = laneEnds.firstIndex { $0 <= start + 0.001 } ?? -1
            if lane == -1 { lane = laneEnds.count; laneEnds.append(end) } else { laneEnds[lane] = end }
            placed.append(StaysPlaced(stay: stay, lane: lane, start: max(0, start), end: min(Double(days), end)))
        }
        return (placed, max(1, laneEnds.count))
    }

    private var rows: [StaysBoardRow] {
        let visible = stays.filter { $0.status != "cancelled" }
        var byUnit: [String: [StaysStay]] = [:]
        var unassigned: [StaysStay] = []
        var bySitter: [String: (name: String?, stays: [StaysStay])] = [:]
        let unitIds = Set(units.map(\.id))
        for stay in visible {
            if stay.isHome {
                let sitter = stay.home?.sitterMemberId ?? ""
                var entry = bySitter[sitter] ?? (stay.home?.sitterName, [])
                entry.stays.append(stay)
                bySitter[sitter] = entry
                continue
            }
            if let unit = stay.unitId, unitIds.contains(unit) { byUnit[unit, default: []].append(stay) } else { unassigned.append(stay) }
        }
        var result: [StaysBoardRow] = []
        if offersRooms {
            for unit in units {
                let laid = place(byUnit[unit.id] ?? [])
                result.append(StaysBoardRow(id: unit.id, unit: unit, home: nil, placed: laid.placed, lanes: laid.lanes))
            }
        }
        if !unassigned.isEmpty {
            let laid = place(unassigned)
            result.append(StaysBoardRow(id: "unassigned", unit: nil, home: nil, placed: laid.placed, lanes: laid.lanes))
        }
        let sitters = bySitter.sorted { a, b in
            if a.key.isEmpty { return false }
            if b.key.isEmpty { return true }
            return (a.value.name ?? "").localizedCompare(b.value.name ?? "") == .orderedAscending
        }
        for (sitter, entry) in sitters {
            let laid = place(entry.stays)
            result.append(StaysBoardRow(id: "home-\(sitter)", unit: nil, home: (sitter, entry.name), placed: laid.placed, lanes: laid.lanes))
        }
        if sitters.isEmpty && offersSitting {
            result.append(StaysBoardRow(id: "home-", unit: nil, home: ("", nil), placed: [], lanes: 1))
        }
        return result
    }

    var body: some View {
        let rows = self.rows
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                // The rooms' column stays put while the days scroll.
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("Rooms").uppercased()).font(.brandText(12, weight: .bold)).tracking(12 * 0.14).foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .frame(width: labelWidth, height: headerHeight, alignment: .bottomLeading)
                    ForEach(rows) { row in
                        label(row)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(width: labelWidth, height: row.height, alignment: .leading)
                            .overlay(alignment: .top) { Rectangle().fill(Theme.borderSoft).frame(height: 1) }
                    }
                }
                .frame(width: labelWidth)
                .background(Theme.surface)
                .overlay(alignment: .trailing) { Rectangle().fill(Theme.borderSoft).frame(width: 1) }

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        ForEach(rows) { row in
                            lane(row)
                                .overlay(alignment: .top) { Rectangle().fill(Theme.borderSoft).frame(height: 1) }
                        }
                    }
                }
            }
            if units.isEmpty && offersRooms {
                EmptyState(systemImage: "bed-double", title: L("Add your rooms to see the board"),
                           message: L("Kennels, suites and cat condos, with how many pets each holds and what a night costs."), accent: Theme.aqua)
            }
        }
        .listCard()
    }

    private var header: some View {
        HStack(spacing: 0) {
            ForEach(dayKeys, id: \.self) { day in
                VStack(spacing: 2) {
                    Text(StaysDay.format(day, "EEE").uppercased()).font(.brandText(10.9, weight: .bold)).tracking(10.9 * 0.1).foregroundStyle(Theme.inkSoft)
                    Text(StaysDay.format(day, "d"))
                        .font(.brandHeading(16))
                        .foregroundStyle(day == today ? Theme.onBlue : Theme.inkStrong)
                        .frame(width: 32, height: 32)
                        .background(day == today ? Theme.blue : Color.clear, in: Circle())
                }
                .padding(.bottom, 8)
                .frame(width: dayWidth, height: headerHeight, alignment: .bottom)
                .background(StaysDay.isWeekend(day) ? Theme.aqua.opacity(0.07) : Color.clear)
            }
        }
        .frame(height: headerHeight)
    }

    @ViewBuilder
    private func label(_ row: StaysBoardRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let home = row.home {
                HStack(spacing: 6) {
                    Glyph("house", size: 16).foregroundStyle(Theme.blue)
                    Text(home.sitterId.isEmpty ? L("No sitter yet") : (home.name ?? L("Sitter"))).lineLimit(1)
                }
                .font(.brandHeading(16)).foregroundStyle(Theme.inkStrong)
                Text(L("Home sitting")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            } else if let unit = row.unit {
                Text(unit.name).font(.brandHeading(16)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                Text(StaysWords.unitKind(unit.kind) + (unit.seats > 1 ? " · " + LF("%d pets", unit.seats) : ""))
                    .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            } else {
                Text(L("No room yet")).font(.brandHeading(16)).foregroundStyle(Theme.mango)
                Text(L("Assign one from the stay")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(2)
            }
        }
    }

    private func lane(_ row: StaysBoardRow) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(dayKeys, id: \.self) { day in
                    Button {
                        onBook(StaysBookingPreset(unitId: row.unit?.id, day: day, home: row.home != nil))
                    } label: {
                        Rectangle()
                            .fill(day == today ? Theme.blue.opacity(0.06) : Color.clear)
                            .frame(width: dayWidth, height: row.height)
                            .overlay(alignment: .trailing) { Rectangle().fill(Theme.borderSoft.opacity(0.6)).frame(width: 1) }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // A day already past can't take a new stay.
                    .disabled(!canBook || day < today)
                    .accessibilityLabel(row.home != nil
                        ? LF("Book a home stay on %@", StaysDay.short(day))
                        : LF("Book %@ on %@", row.unit?.name ?? L("a room"), StaysDay.short(day)))
                }
            }
            ForEach(row.placed) { placed in
                NavigationLink(value: ProviderRoute.stay(placed.stay.id)) {
                    StaysBar(stay: placed.stay)
                        .frame(width: max(30, CGFloat(placed.end - placed.start) * dayWidth), height: barHeight)
                }
                .buttonStyle(.plain)
                .offset(x: CGFloat(placed.start) * dayWidth, y: 8.8 + CGFloat(placed.lane) * laneHeight)
            }
        }
        .frame(width: CGFloat(days) * dayWidth, height: row.height, alignment: .topLeading)
    }
}

/// One stay on the board (web `StayBar`): its pets' faces, their names (a sun
/// for daycare, a house for a home stay) and either the family and the
/// estimate or the late line; the status at 30% (48% once in), a 2 pt edge,
/// dashed while it is a request, faded once it is over.
private struct StaysBar: View {
    let stay: StaysStay

    private var state: ProviderState { ProviderState.stay(stay.status) }
    private var faded: Bool { stay.status == "checked_out" || stay.status == "no_show" }
    private var edge: Color { stay.late != nil ? Theme.destructive : (stay.status == "checked_in" ? Theme.blue : state.color) }

    var body: some View {
        HStack(spacing: 6) {
            PetStack(pets: stay.petList.map { ($0.petName, $0.petSpecies, $0.photoUrl) }, size: 28, max: 3)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    if stay.isDaycare { Glyph("sun", size: 12) }
                    if stay.isHome { Glyph("house", size: 12) }
                    Text(stay.petNames).lineLimit(1)
                }
                .font(Theme.text(12.8, weight: .bold))
                .foregroundStyle(Theme.inkStrong)
                if let late = stay.late {
                    Text(late == .departure ? LF("Was due out %@", StaysDay.dayMonth(stay.checkOutDay)) : LF("Was due in %@", StaysDay.dayMonth(stay.checkInDay)))
                        .font(Theme.text(10.9, weight: .bold)).foregroundStyle(Theme.destructive).lineLimit(1)
                } else {
                    Text("\(stay.clientName ?? "") · \(stay.isHome ? (stay.home?.addressText ?? "") : Money.short(stay.estimatedTotalCents))")
                        .font(Theme.text(10.9, weight: .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(maxHeight: .infinity)
        .background(Theme.wash(state.color, stay.status == "checked_in" ? 48 : 30), in: Capsule())
        .overlay {
            Capsule().strokeBorder(edge, style: StrokeStyle(lineWidth: 2, dash: stay.status == "requested" ? [5, 3] : []))
        }
        .clipShape(Capsule())
        .shadow(color: Theme.navy.opacity(0.08), radius: 1.5, y: 1)
        .opacity(faded ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stay.petNames) · \(stay.clientName ?? "")")
    }
}
