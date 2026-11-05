//
//  StaysCareToday.swift
//  PawMiawNegocios
//
//  Today's care (web stays-care-today.tsx): every pet staying in, its room,
//  pickup (red when past due and still here), what the stay costs so far,
//  allergies, vaccine issues, the owner's words and belongings, and the day's
//  tasks from its care plan to tick done or skipped as they happen, with when
//  the family last heard from the hotel and the report card a tap away.
//

import SwiftUI

private struct StaysReportTarget: Identifiable {
    let stayId: String
    let pet: StaysPet
    var id: String { pet.id }
}

struct StaysCareTodayView: View {
    let canCare: Bool

    @EnvironmentObject private var workspace: Workspace
    @State private var day: String?
    @State private var board: StaysCareBoard?
    @State private var error: String?
    @State private var reportFor: StaysReportTarget?

    private var shownDay: String? { board?.dayKey ?? day }
    private var tasks: [StaysCareTask] { (board?.pets ?? []).flatMap { $0.tasks ?? [] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if let board {
                if (board.pets ?? []).isEmpty {
                    EmptyState(systemImage: "moon", title: L("No pets staying in"),
                               message: L("Once a pet is checked in, its care plan turns into the day’s tasks here."), accent: Theme.aqua, panel: true)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)], spacing: 16) {
                        ForEach(board.pets ?? []) { pet in petCard(pet) }
                    }
                }
            } else if let error {
                ErrorState(message: error) { await load() }
            } else {
                LoadingState()
            }
        }
        .reloadsOnScope { await load() }
        .onChange(of: day) { _, _ in Task { await load() } }
        .sheet(item: $reportFor) { target in
            StaysReportCardSheet(stayId: target.stayId, pets: [target.pet], familyOnApp: nil, initialPetId: target.pet.id) { Task { await load() } }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IconCircleButton(systemImage: "chevron-left", label: L("Previous day"), tint: Theme.blue) { if let shownDay { day = StaysDay.add(shownDay, -1) } }
                Text(shownDay.map { StaysDay.long($0) } ?? "…")
                    .font(.brandHeading(20)).foregroundStyle(Theme.inkStrong)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(minWidth: 176)
                IconCircleButton(systemImage: "chevron-right", label: L("Next day"), tint: Theme.blue) { if let shownDay { day = StaysDay.add(shownDay, 1) } }
                if day != nil { PMButton(L("Today"), variant: .outline, size: .compact) { day = nil } }
                Spacer(minLength: 0)
            }
            if !tasks.isEmpty {
                let done = tasks.filter { $0.status != "pending" }.count
                let skipped = tasks.filter { $0.status == "skipped" }.count
                HStack(spacing: 12) {
                    // The day's progress (web: a 10 pt bar, the blue over the muted track).
                    ProgressBar(value: Double(done) / Double(max(1, tasks.count)), height: 10, width: 160, track: Theme.surfaceMuted)
                    Text(LF("%d of %d done", done - skipped, tasks.count) + (skipped > 0 ? " · " + LP(skipped, "%d skipped", "%d skipped (plural)") : ""))
                        .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    private func petCard(_ pet: StaysCarePet) -> some View {
        let petTasks = pet.tasks ?? []
        let petDone = petTasks.filter { $0.status != "pending" }.count
        return Card(spacing: 12) {
            NavigationLink(value: ProviderRoute.stay(pet.stayId)) {
                HStack(spacing: 12) {
                    PetAvatar(name: pet.petName, species: pet.petSpecies, photoURL: pet.photoUrl, size: 48)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pet.petName).font(.brandHeading(20)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Text(pet.petBreed ?? StaysWords.petSpecies(pet.petSpecies)).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Chip(text: pet.kind == "daycare" ? L("Day stay")
                            : pet.lateDeparture == true ? LF("Night %d", pet.nightNumber ?? 1)
                            : LF("Night %d of %d", pet.nightNumber ?? 1, pet.totalNights ?? 1), tone: .info)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 1) {
                fact("bed-double", L("Room"), pet.unitName ?? L("No room yet"), hint: nil, late: false)
                fact("log-out", L("Pickup"), "\(StaysDay.format(pet.checkOutDay, "EEEd")) · \(StaysDay.clock(pet.checkOutTime))",
                     hint: pet.lateDeparture == true ? L("Past due · still here") : nil, late: pet.lateDeparture == true)
                fact("wallet", L("Stay"), Money.format(pet.estimatedTotalCents, currency: pet.currency),
                     hint: (pet.rateCents ?? 0) > 0 ? "\(StaysWords.units(pet.kind ?? "boarding", pet.totalNights ?? 1)) × \(Money.short(pet.rateCents))" : L("No rate set"), late: false)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.borderSoft)
            .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))

            if let client = pet.clientName {
                FlowLayout(spacing: 16) {
                    HStack(spacing: 6) {
                        Glyph("user-round", size: 16).foregroundStyle(Theme.inkSoft)
                        Text(client).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    }
                    if let phone = pet.clientPhone?.nonEmpty { PhoneLink(phone: phone) }
                }
            }
            StaysAllergies(allergies: pet.allergies ?? [])
            if let issues = pet.vaccineIssues, !issues.isEmpty {
                FlowLayout(spacing: 6) { ForEach(issues, id: \.key) { StaysVaccineChip(key: $0.key, status: $0.status) } }
            }
            if let words = pet.ownerInstructions?.nonEmpty { StaysNoteBlock(label: L("From the owner"), text: words, tint: Theme.aqua) }
            if let belongings = pet.belongings, !belongings.isEmpty {
                HStack(spacing: 6) {
                    Glyph("backpack", size: 14)
                    Text(belongings.joined(separator: " · "))
                }
                .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            }
            if let notes = pet.careNotes?.nonEmpty { StaysNoteBlock(label: "", text: notes, tint: Theme.mango) }

            HStack(spacing: 6) {
                StaysEyebrow(text: L("Today’s care"))
                if !petTasks.isEmpty { Text("\(petDone)/\(petTasks.count)").font(.brandText(10.9, weight: .heavy)).foregroundStyle(Theme.inkSoft) }
            }
            .padding(.top, 4)
            VStack(spacing: 6) {
                ForEach(petTasks) { task in taskRow(task) }
                if petTasks.isEmpty {
                    NavigationLink(value: ProviderRoute.stay(pet.stayId)) {
                        HStack(spacing: 12) {
                            Glyph("clipboard-list", size: 16).foregroundStyle(Theme.inkSoft)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(L("Nothing planned for today.")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                                Text(L("Meals, medicine and walks come from the care plan set at check-in.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 3])))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            RowDivider().padding(.top, 4)
            HStack {
                lastReport(pet.lastReportAt)
                Spacer(minLength: 6)
                if canCare {
                    PMButton(L("Report card"), systemImage: "message-square-heart", size: .compact) {
                        reportFor = StaysReportTarget(stayId: pet.stayId, pet: StaysPet(id: pet.stayPetId, providerClientPetId: nil, petName: pet.petName, petSpecies: pet.petSpecies, petBreed: pet.petBreed, photoUrl: pet.photoUrl, linkedToHousehold: nil, carePlan: nil, vaccineCheck: nil, vaccinesConfirmedAt: nil, vaccinesConfirmedByName: nil, allergies: nil))
                    }
                }
            }
        }
    }

    private func fact(_ icon: String, _ label: String, _ value: String, hint: String?, late: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Glyph(icon, size: 14)
                Text(label.uppercased()).tracking(10.2 * 0.12).lineLimit(1)
            }
            .font(.brandText(10.2, weight: .heavy)).foregroundStyle(Theme.inkSoft)
            Text(value).font(Theme.text(14, weight: .bold)).foregroundStyle(late ? Theme.destructive : Theme.inkStrong).lineLimit(1).minimumScaleFactor(0.8)
            if let hint { Text(hint).font(Theme.text(11.2, weight: late ? .bold : .regular)).foregroundStyle(late ? Theme.destructive : Theme.inkSoft).lineLimit(1) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface)
    }

    private func taskRow(_ task: StaysCareTask) -> some View {
        let finished = task.status != "pending"
        return HStack(spacing: 12) {
            Glyph(StaysWords.taskIcon(task.kind), size: 16).foregroundStyle(Theme.blue)
            Text(task.time.map { StaysDay.clock($0) } ?? "—").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkSoft).monospacedDigit().frame(width: 76, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.label ?? "").font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong).strikethrough(task.status == "skipped").lineLimit(2)
                if finished, let name = task.doneByName {
                    Text(task.status == "done" ? LF("Done by %@", name) : LF("Skipped by %@", name)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer(minLength: 4)
            if canCare {
                if finished {
                    PMButton(L("Undo"), variant: .outline, size: .compact) { mark(task.id, "pending") }
                } else {
                    IconCircleButton(systemImage: "skip-forward", label: L("Skip"), tint: Theme.inkSoft) { mark(task.id, "skipped") }
                    IconCircleButton(systemImage: "check", label: L("Done"), tint: Theme.blue) { mark(task.id, "done") }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(task.status == "done" ? AnyShapeStyle(Theme.wash(Theme.lime, 30)) : task.status == "skipped" ? AnyShapeStyle(Theme.surfaceMuted) : AnyShapeStyle(Color.clear),
                    in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(task.status == "pending" ? Theme.borderSoft : Color.clear, lineWidth: 1))
        .opacity(task.status == "skipped" ? 0.7 : 1)
    }

    /// When the family last heard from the hotel — a nudge when it has been a while.
    private func lastReport(_ at: String?) -> some View {
        let hours = DateText.parse(at).map { Date().timeIntervalSince($0) / 3600 }
        let stale = hours == nil || (hours ?? 0) >= 24
        let text: String
        if let hours {
            if hours < 1 { text = LF("Last report card %d min ago", max(1, Int((hours * 60).rounded()))) }
            else if hours < 24 { text = LF("Last report card %d h ago", Int(hours.rounded())) }
            else { text = LF("Last report card %d d ago", Int(hours / 24)) }
        } else {
            text = L("No report card sent yet")
        }
        return HStack(spacing: 6) {
            Glyph("message-square-heart", size: 14)
            Text(text)
        }
        .font(Theme.text(12, weight: .semibold)).foregroundStyle(stale ? Theme.goldText : Theme.inkSoft)
    }

    // MARK: Work

    private func load() async {
        do {
            board = try await API.get("/provider-stay-care", query: ["day": day, "locationId": workspace.locationId])
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = errorText(error)
        }
    }

    /// Ticked on the spot: the board changes before the server answers, and goes back if it refuses.
    private func mark(_ taskId: String, _ status: String) {
        let previous = board
        if var next = board {
            next.pets = next.pets?.map { pet in
                var pet = pet
                pet.tasks = pet.tasks?.map { task in var task = task; if task.id == taskId { task.status = status }; return task }
                return pet
            }
            board = next
        }
        Task {
            do {
                try await API.send("PATCH", "/provider-stay-tasks/\(taskId)", body: ["status": status])
                await load()
            } catch {
                board = previous
                Toast.error(error, fallback: L("Could not save that."))
            }
        }
    }
}
