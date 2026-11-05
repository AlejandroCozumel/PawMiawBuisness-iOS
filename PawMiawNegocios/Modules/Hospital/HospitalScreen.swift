//
//  HospitalScreen.swift
//  PawMiawNegocios
//
//  The hospital (web provider.hospital.tsx + hospital-board.tsx): one place's
//  ward. The module header with its numbers (patients in of the beds, waiting
//  for admission, doses needing someone, rounds to sign) and "Admit a
//  patient", the page tabs, then the board (waiting patients and what they
//  wait on, patients in by ward or cage, who left lately), who is on call, and
//  the hospital's rules. A missed dose stays on the board as one notice per
//  patient until it is marked (backend docs/hospital-sheet-and-notices.md).
//

import SwiftUI

struct HospitalScreen: View {
    @EnvironmentObject private var workspace: Workspace

    private var vetCare: Bool { workspace.offers(.vet, .emergency) }

    var body: some View {
        Group {
            if workspace.current != nil && !(workspace.can(.hospitalView) && vetCare) {
                PageScroll {
                    NoAccessState(message: vetCare
                        ? L("Ask the workspace owner to give your role access to the hospital.")
                        : L("The hospital is for businesses that offer veterinary care."))
                }
            } else {
                RequireLocation { HospWardPage() }
            }
        }
        .providerPage(L("Hospital"), root: true)
    }
}

private enum HospWardTab: Hashable { case board, onCall, settings }

private struct HospWardPage: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var board: HospBoard?
    @State private var error: String?
    @State private var tab: HospWardTab = .board
    @State private var admitting = false
    @State private var opened: HospOpened?

    private var canManage: Bool { workspace.can(.hospitalManage) }

    var body: some View {
        PageScroll(maxWidth: 1100, refresh: { await load() }) {
            header
            ToneTabs(tabs: tabs, selection: $tab, look: .solid)
            switch tab {
            case .board:
                if let board {
                    HospBoardView(board: board, zone: workspace.timeZone, canManage: canManage, canSetUpRooms: workspace.can(.workspaceEdit)) { admitting = true }
                } else if let error {
                    ErrorState(message: error) { await load() }
                } else {
                    LoadingState()
                }
            case .onCall:
                HospOnCallPanel(canManage: canManage)
            case .settings:
                HospSettingsPanel(canEdit: canManage)
            }
        }
        .reloadsOnScope { await load() }
        .modifier(HospEveryMinute { await load() })
        .sheet(isPresented: $admitting) {
            HospAdmitSheet { opened = $0 }
        }
        .navigationDestination(item: $opened) { HospDetailPage(id: $0.id, signFirst: $0.signConsentId, admitAfterSigning: $0.admitAfterSigning) }
    }

    private var tabs: [ToneTabs<HospWardTab>.Tab] {
        var list: [ToneTabs<HospWardTab>.Tab] = [.init(.board, L("Ward"), icon: "bed-double"), .init(.onCall, L("On call"), icon: "phone-call")]
        if canManage { list.append(.init(.settings, L("Settings"), icon: "settings-2")) }
        return list
    }

    // MARK: Header

    private var header: some View {
        let subtitle = workspace.multiLocation ? workspace.selectedLocation?.name : nil
        return ModuleHeader(
            icon: "bed-double",
            title: L("Hospital"),
            subtitle: subtitle ?? L("Patients in, their treatment sheet and who is on call"),
            accent: Theme.pink,
            stats: stats,
            storageKey: "hospital"
        ) {
            if canManage {
                PMButton(L("Admit a patient"), systemImage: "plus") { admitting = true }
            }
        }
    }

    private var stats: [ModuleStat] {
        let counts = board?.counts
        let beds = (board?.rooms ?? []).reduce(0) { $0 + ($1.capacity ?? 0) }
        let admitted = counts?.admitted ?? 0
        let missed = counts?.missed ?? 0, late = counts?.late ?? 0
        let needing = (counts?.due ?? 0) + late + missed
        return [
            ModuleStat("in", label: L("In the hospital"), value: beds > 0 ? "\(admitted) / \(beds)" : "\(admitted)",
                       hint: beds > 0 ? LP(max(0, beds - admitted), "1 place free", "%d places free") : nil,
                       icon: "bed-double", accent: Theme.pink),
            ModuleStat("pending", label: L("Waiting for admission"), value: "\(counts?.pending ?? 0)",
                       icon: "circle-dashed", accent: Theme.mango, attention: (counts?.pending ?? 0) > 0),
            ModuleStat("doses", label: L("Doses needing someone"), value: "\(needing)",
                       hint: missed > 0 ? LP(missed, "1 missed", "%d missed") : late > 0 ? LP(late, "1 late", "%d late") : nil,
                       icon: "syringe", accent: Theme.aqua, attention: missed + late > 0),
            ModuleStat("rounds", label: L("Rounds to sign today"), value: "\(counts?.roundsPending ?? 0)",
                       icon: "shield-question-mark", accent: Theme.lime),
        ]
    }

    private func load() async {
        do {
            board = try await API.get("/provider-hospital/board", query: ["locationId": workspace.locationId])
            error = nil
        } catch is CancellationError {
        } catch {
            if board == nil { self.error = errorText(error) }
        }
    }
}

// MARK: - The board

private struct HospBoardView: View {
    let board: HospBoard
    let zone: TimeZone
    let canManage: Bool
    let canSetUpRooms: Bool
    let onAdmit: () -> Void

    private var patients: [HospSummary] { board.patients ?? [] }
    private var rooms: [HospWardRoom] { board.rooms ?? [] }
    private var pending: [HospSummary] { patients.filter { $0.status == "pending" } }
    private var admitted: [HospSummary] { patients.filter { $0.status == "admitted" } }
    private var unplaced: [HospSummary] {
        admitted.filter { patient in patient.room == nil || !rooms.contains(where: { $0.id == patient.room?.id }) }
    }
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // One notice per patient while a dose is missed: it goes once each is marked.
            let missing = admitted.filter { ($0.attention?.m ?? 0) > 0 }
            if !missing.isEmpty {
                VStack(spacing: 10) {
                    ForEach(missing) { patient in
                        let missed = patient.attention?.m ?? 0
                        let name = patient.patient?.name?.nonEmpty ?? L("A patient")
                        NavigationLink(value: ProviderRoute.hospitalization(patient.id)) {
                            NoticeCard(
                                tone: .problem,
                                title: missed == 1 ? LF("Missed treatment: %@", name) : LF("%d treatments not marked: %@", missed, name),
                                message: missed == 1 ? L("Mark it or note why it wasn’t given.") : L("Mark them or note why they weren’t given.")
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !pending.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HospGroupTitle(title: L("Waiting for admission"), systemImage: "circle-dashed", count: pending.count, tone: Theme.mango)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(pending) { patient in
                            NavigationLink(value: ProviderRoute.hospitalization(patient.id)) { HospPendingCard(patient: patient) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }

            if admitted.isEmpty && rooms.isEmpty {
                VStack(spacing: 12) {
                    EmptyState(systemImage: "bed-double", title: L("No patients in the hospital"),
                               message: L("Admit one from a visit or with “Admit a patient”. Add wards and cages in Settings → Rooms."),
                               actionTitle: canManage ? L("Admit a patient") : nil, action: canManage ? onAdmit : nil,
                               accent: Theme.pink, panel: true)
                    if canSetUpRooms {
                        NavigationLink(value: ProviderRoute.section(.rooms)) {
                            HStack(spacing: 6) {
                                Glyph("settings-2", size: 16)
                                Text(L("Add wards and cages"))
                            }
                        }
                        .buttonStyle(.pm(.outline, size: .compact))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HospGroupTitle(title: L("In the hospital"), systemImage: "bed-double", count: admitted.count, tone: Theme.pink)
                    ForEach(rooms) { room in
                        HospWardGroup(room: room, patients: admitted.filter { $0.room?.id == room.id }, zone: zone)
                    }
                    if !unplaced.isEmpty {
                        HospWardGroup(room: nil, patients: unplaced, zone: zone)
                    }
                }
            }

            if let recent = board.recent, !recent.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HospGroupTitle(title: L("Recently left"), systemImage: "circle-check", count: recent.count, tone: ProviderState.done.color)
                    Card(padding: 0, spacing: 0) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, patient in
                            if index > 0 { RowDivider() }
                            NavigationLink(value: ProviderRoute.hospitalization(patient.id)) {
                                HStack(spacing: 12) {
                                    PetAvatar(name: patient.patient?.name, species: patient.patient?.species, photoURL: patient.patient?.photoUrl, size: 32)
                                        .grayscale(patient.status == "deceased" ? 1 : 0)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(patient.patient?.name?.nonEmpty ?? L("Patient")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                        let line = [patient.client?.name, patient.endedAt.map { HospFmt.dateTime($0, zone) }].compactMap { $0?.nonEmpty }.joined(separator: " · ")
                                        if !line.isEmpty { Text(line).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                                    }
                                    Spacer(minLength: 8)
                                    HospStatusChip(status: patient.status)
                                    Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

/// A ward or cage (web `WardGroup`): the page's card, its name and how full it
/// is, the patients in it on a muted band.
private struct HospWardGroup: View {
    let room: HospWardRoom?
    let patients: [HospSummary]
    let zone: TimeZone

    var body: some View {
        SectionCard(title: room?.name ?? L("Not placed in a ward"), trailing: {
            if let room {
                let occupied = room.occupied ?? 0, capacity = room.capacity ?? 0
                let over = occupied > capacity, full = occupied >= capacity
                let tone = over ? Theme.destructive : full ? Theme.mango : ProviderState.done.color
                HStack(spacing: 8) {
                    Text((room.kind == "cage" ? L("Cage") : L("Ward")).uppercased())
                        .font(Theme.text(11.2, weight: .heavy)).tracking(11.2 * 0.1).foregroundStyle(Theme.inkSoft)
                    HStack(spacing: 6) {
                        Circle().fill(tone).frame(width: 6, height: 6)
                        Text(LF("%d of %d", occupied, capacity)).monospacedDigit()
                    }
                    .font(Theme.text(12, weight: .heavy))
                    .foregroundStyle(over ? Theme.destructive : Theme.inkStrong)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(Theme.wash(tone, over ? 14 : 22), in: Capsule())
                }
            }
        }) {
            Group {
                if patients.isEmpty {
                    // A free bed, dashed.
                    HStack(spacing: 8) {
                        Glyph("bed-double", size: 16)
                        Text(L("Empty"))
                    }
                    .font(Theme.text(14, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 12, alignment: .top)], spacing: 12) {
                        ForEach(patients) { patient in
                            NavigationLink(value: ProviderRoute.hospitalization(patient.id)) { HospPatientCard(patient: patient, zone: zone) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.mix(Theme.surfaceMuted, 45, with: Theme.surface))
        }
    }
}

/// One card for every patient on the board (web `CARD`): a box with a
/// 1.5 pt border and a 4 pt left edge in the colour of what it needs.
private struct HospBoardBox: ViewModifier {
    let edge: Color
    var waiting: Bool = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous) }

    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(waiting ? AnyShapeStyle(Theme.wash(Theme.mango, 6)) : AnyShapeStyle(Theme.surface), in: shape)
            .overlay {
                if waiting {
                    shape.strokeBorder(Theme.mix(Theme.mango, 60, with: Theme.borderSoft), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                } else {
                    shape.strokeBorder(Theme.borderSoft, lineWidth: 1.5)
                }
            }
            .overlay(alignment: .leading) { Rectangle().fill(edge).frame(width: 4) }
            .clipShape(shape)
            .shadow(color: Theme.navy.opacity(0.08), radius: 1.5, y: 1)
            .contentShape(Rectangle())
    }
}

/// The pet, who it belongs to and where it sleeps.
private struct HospCardHead<Aside: View>: View {
    let patient: HospSummary
    let place: String?
    @ViewBuilder var aside: () -> Aside

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PetAvatar(name: patient.patient?.name, species: patient.patient?.species, photoURL: patient.patient?.photoUrl, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(patient.patient?.name?.nonEmpty ?? L("Patient")).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                let line = [patient.client?.name, place].compactMap { $0?.nonEmpty }.joined(separator: " · ")
                if !line.isEmpty { Text(line).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
            }
            Spacer(minLength: 4)
            aside()
        }
    }
}

/// A patient in: what it is, how it is, the next dose and the last vitals; the edge says what needs someone.
private struct HospPatientCard: View {
    let patient: HospSummary
    let zone: TimeZone

    private var edge: Color {
        let a = patient.attention
        if (a?.m ?? 0) > 0 { return Theme.destructive }
        if (a?.l ?? 0) > 0 { return Theme.mango }
        if (a?.d ?? 0) > 0 { return Theme.aqua }
        return Theme.borderSoft
    }

    private var vitalsLine: String {
        guard let v = patient.lastVitals else { return "" }
        return [
            v.temperatureC.map { "\(HospFmt.number($0)) °C" },
            v.heartRate.map { LF("HR %@", HospFmt.number($0)) },
            v.respiratoryRate.map { LF("RR %@", HospFmt.number($0)) },
            v.painScore.map { LF("Pain %@", HospFmt.number($0)) },
        ].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HospCardHead(patient: patient, place: patient.cageLabel.map { LF("Cage %@", $0) }) {
                if let day = patient.dayNumber {
                    VStack(spacing: 2) {
                        Text(L("Day").uppercased()).font(Theme.text(9.6, weight: .heavy)).tracking(0.96).foregroundStyle(Theme.inkSoft)
                        Text("\(day)").font(.brandHeading(20, relativeTo: .title3)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.wash(Theme.pink, 16), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                }
            }
            FlowLayout(spacing: 6) {
                if let priority = patient.triagePriority { HospTriageBadge(priority: priority) }
                if let condition = patient.condition { HospConditionBadge(condition: condition) }
                HospAllergyChip(allergies: patient.patient?.allergies ?? [])
                HospAttentionChips(attention: patient.attention)
                HospRoundsChip(signed: patient.roundsSignedToday == true)
            }
            if let reason = patient.reason?.nonEmpty {
                Text(reason).font(Theme.text(14)).foregroundStyle(Theme.inkStrong).lineLimit(2)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    HospFootLine(icon: "stethoscope", text: patient.attending?.name ?? L("No attending vet"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HospFootLine(icon: "clock-3", text: patient.nextDueAt.map { LF("Next %@", HospFmt.clock($0, zone)) } ?? L("Nothing scheduled"), strong: patient.nextDueAt != nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let vitals = patient.lastVitals {
                    HStack(spacing: 6) {
                        HospFootLine(icon: "thermometer", text: vitalsLine)
                        Spacer(minLength: 4)
                        Text(HospFmt.clock(vitals.recordedAt, zone)).font(Theme.text(12)).monospacedDigit().foregroundStyle(Theme.inkSoft)
                    }
                } else {
                    HospFootLine(icon: "heart-pulse", text: L("No vitals yet"))
                }
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { RowDivider() }
        }
        .modifier(HospBoardBox(edge: edge))
    }
}

/// One line of a card's foot: a 14 icon and 12 words.
private struct HospFootLine: View {
    let icon: String
    let text: String
    var strong: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Glyph(icon, size: 14)
            Text(text).lineLimit(1)
        }
        .font(Theme.text(12, weight: strong ? .bold : .regular))
        .foregroundStyle(strong ? Theme.inkStrong : Theme.inkSoft)
    }
}

/// A patient waiting for admission, with what it waits on ticked off.
private struct HospPendingCard: View {
    let patient: HospSummary

    private var money: String? { patient.currency }

    var body: some View {
        let gate = patient.gate
        let estimate = patient.estimateAmount ?? 0
        let deposit = patient.depositAmount ?? 0
        VStack(alignment: .leading, spacing: 12) {
            HospCardHead(patient: patient, place: patient.room?.name) { EmptyView() }
            if patient.triagePriority != nil || !(patient.patient?.allergies ?? []).isEmpty {
                FlowLayout(spacing: 6) {
                    if let priority = patient.triagePriority { HospTriageBadge(priority: priority) }
                    HospAllergyChip(allergies: patient.patient?.allergies ?? [])
                }
            }
            if let reason = patient.reason?.nonEmpty {
                Text(reason).font(Theme.text(14)).foregroundStyle(Theme.inkStrong).lineLimit(2)
            }
            VStack(alignment: .leading, spacing: 6) {
                HospGateLine(
                    ok: gate.map { $0.consent?.satisfied ?? false } ?? (estimate <= 0),
                    loading: gate == nil && estimate > 0,
                    systemImage: "shield-check",
                    text: estimate <= 0 ? L("No estimate to sign")
                        : gate?.consent?.satisfied == true ? L("Estimate signed")
                        : gate?.consent?.reason == "amount_changed" ? L("The estimate went up: sign again") : L("Estimate not signed yet")
                )
                HospGateLine(
                    ok: gate.map { $0.deposit?.satisfied ?? false } ?? (deposit <= 0),
                    loading: gate == nil && deposit > 0,
                    systemImage: "piggy-bank",
                    text: deposit <= 0 ? L("No deposit")
                        : gate?.deposit?.waivedByTriage == true ? L("Deposit waived: critical emergency")
                        : gate.map { LF("Deposit %@ of %@", Money.format($0.deposit?.paid ?? 0, currency: money), Money.format($0.deposit?.amount ?? 0, currency: money)) }
                        ?? LF("Deposit %@", Money.format(deposit, currency: money))
                )
                if gate?.ready == true {
                    HStack(spacing: 6) {
                        Glyph("bed-double", size: 16)
                        Text(L("Ready to admit"))
                        Spacer()
                        Glyph("chevron-right", size: 16)
                    }
                    .font(Theme.text(14, weight: .heavy))
                    .foregroundStyle(Theme.blue)
                    .padding(.top, 4)
                }
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(Theme.mix(Theme.mango, 35, with: Theme.borderSoft)).frame(height: 1) }
        }
        .modifier(HospBoardBox(edge: Theme.mango, waiting: true))
    }
}

/// One thing admission waits on, ticked when done (web `GateLine`).
struct HospGateLine: View {
    let ok: Bool
    var loading: Bool = false
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if loading {
                    ProgressView().controlSize(.mini).tint(Theme.inkSoft)
                } else {
                    Glyph(ok ? "check" : systemImage, size: 12)
                        .foregroundStyle(ok ? ProviderState.done.color : Theme.inkStrong)
                }
            }
            .frame(width: 20, height: 20)
            .background(loading ? AnyShapeStyle(Theme.surfaceMuted) : ok ? AnyShapeStyle(Theme.wash(ProviderState.done.color, 18)) : AnyShapeStyle(Theme.wash(Theme.mango, 28)), in: Circle())
            Text(text).font(Theme.text(12, weight: .bold)).foregroundStyle(loading ? Theme.inkSoft : Theme.inkStrong)
        }
    }
}
