//
//  StaysHomeVisit.swift
//  PawMiawNegocios
//
//  One visit (or night) of a home stay, run one way wherever it is opened —
//  the stay's visit rows and Domicilio (web home-stay-visit-sheet.tsx,
//  stay-visit-runner.tsx, home-stay-arrival.tsx): what the sitter does there —
//  each pet's care and the house's tasks, ticked as they happen — the house
//  rules, the report cards written at it, and every move: arrive (through the
//  consent gate the stay requires on the first arrival: the vet
//  authorization), leave with a note, undo or reopen, couldn't get in, cancel,
//  mark missed, move it or give it to someone else. Arrive and leave carry the
//  press time and, when the business records location, where the phone was
//  (Core/VisitLocation.swift); from Domicilio arriving goes through its outbox.
//

import SwiftUI

private enum StaysVisitSheetKind: String, Identifiable {
    case leave, cancel, missed, noAccess = "no-access", change, report, gate
    var id: String { rawValue }
}

struct StaysHomeVisitSheet: View {
    let stayId: String
    let visitId: String
    /// Opened to leave the home or write the report card right away (Domicilio's Finish and Report).
    var startWith: String? = nil
    /// Domicilio's "I've arrived": through its outbox, with the press time and place. Nil: arrive here.
    var onArrive: (() -> Void)? = nil
    /// Where the phone is at a press (Domicilio's stamp). Nil: this sheet stamps when the business records location.
    var locate: (() async -> VisitPosition)? = nil
    /// "Open the home stay" (shown when the sheet is opened from elsewhere).
    var onOpenStay: (() -> Void)? = nil

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var stay: StaysStay?
    @State private var home: StaysHomeDetail?
    @State private var visit: StaysHomeVisit?
    @State private var extras: StaysVisitExtras?
    @State private var failed: String?
    @State private var meId: String?
    @State private var stamps = false
    @State private var sheet: StaysVisitSheetKind?
    @State private var working = false
    @State private var started = false

    /// From the stay's page: the stay and its home are already loaded.
    init(stay: StaysStay, home: StaysHomeDetail, visitId: String) {
        self.stayId = stay.id
        self.visitId = visitId
        _stay = State(initialValue: stay)
        _home = State(initialValue: home)
    }

    /// From anywhere else (Domicilio): by its ids, the stay read here.
    init(stayId: String, visitId: String, startWith: String? = nil, onArrive: (() -> Void)? = nil,
         locate: (() async -> VisitPosition)? = nil, onOpenStay: (() -> Void)? = nil) {
        self.stayId = stayId
        self.visitId = visitId
        self.startWith = startWith
        self.onArrive = onArrive
        self.locate = locate
        self.onOpenStay = onOpenStay
    }

    private var zone: TimeZone { home?.zone ?? Workspace.shared.timeZone }
    private var shown: StaysHomeVisit? { visit ?? home?.visits?.first { $0.id == visitId } }
    /// The place of a press: Domicilio's, else this sheet's own when the business records it.
    private var stamp: (() async -> VisitPosition)? { locate ?? VisitLocation.stamp(stamps) }

    var body: some View {
        ProviderModal(
            // Over the stay it says the visit; on its own (from Domicilio) whose visit it is, as on the web.
            title: shown.map { visit in
                onOpenStay != nil && stay != nil
                    ? "\(stay?.petNames ?? "") · \(StaysWords.homeVisitKind(visit.kind))"
                    : "\(StaysWords.homeVisitKind(visit.kind)) · \(StaysDay.short(visit.dayKey))"
            } ?? L("Visit"),
            subtitle: shown.map { visit in
                onOpenStay != nil
                    ? [StaysDay.short(visit.dayKey), Self.timeText(visit, zone: zone), stay?.clientName].compactMap { $0?.nonEmpty }.joined(separator: " · ")
                    : [Self.timeText(visit, zone: zone), visit.sitter?.name ?? L("No sitter yet")].compactMap { $0.nonEmpty }.joined(separator: " · ")
            },
            systemImage: shown?.kind == "overnight" ? "moon-star" : "house",
            accent: .aqua,
            cancelTitle: L("Close")
        ) {
            if let visit = shown, let stay {
                content(visit, stay)
            } else if let failed {
                ErrorState(message: failed) { await load() }
            } else {
                LoadingState()
            }
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .pawMiawDataChanged)) { _ in Task { await load() } }
        .sheet(item: $sheet) { which in
            if let visit = shown, let stay { moveSheet(which, visit, stay) }
        }
    }

    // MARK: Loading

    private func load() async {
        do {
            // The stay moves with its visits (the first arrival starts it): read again each time.
            let (loaded, detail) = try await StaysAPI.homeStay(stayId)
            stay = loaded
            if let detail { home = detail }
            let data = try await API.data("GET", "/provider-homestays/\(stayId)/visits/\(visitId)", query: [:], body: nil)
            visit = try API.decode(data)
            extras = try? API.decode(data)
            failed = nil
        } catch is CancellationError {
            return
        } catch {
            if shown == nil { failed = StaysWords.homeError(error, fallback: "Couldn’t load this visit.") }
        }
        if meId == nil { meId = await StaysHomeTeam.members().first { $0.isCurrentMember == true }?.id }
        if locate == nil && !stamps { stamps = await VisitLocation.stampsOn() }
        if !started {
            started = true
            if startWith == "leave" && shown?.status == "in_progress" { sheet = .leave }
            if startWith == "report" && stay?.status == "checked_in" { sheet = .report }
        }
    }

    // MARK: Rules

    private var canManage: Bool { workspace.can(.staysManage) }

    private func canAct(_ visit: StaysHomeVisit) -> Bool {
        let theirs = visit.sitter == nil || visit.sitter?.memberId == meId
        return workspace.can(.staysCare) && (workspace.isOwnerOrAdmin || canManage || theirs)
    }

    private func stayOpen(_ visit: StaysHomeVisit, _ stay: StaysStay) -> Bool {
        stay.status == "confirmed" || stay.status == "checked_in" || (stay.status == "requested" && visit.kind == "meet_greet")
    }

    /// Arriving opens three hours before the visit.
    private func arrivalOpens(_ visit: StaysHomeVisit) -> Date? {
        DateText.parse(visit.startsAt).map { $0.addingTimeInterval(-3 * 3600) }
    }

    static func timeText(_ visit: StaysHomeVisit, zone: TimeZone) -> String {
        let start = StaysDay.clockAt(visit.startsAt, zone: zone)
        let end = StaysDay.clockAt(visit.endsAt, zone: zone)
        if visit.kind == "overnight", let a = DateText.parse(visit.startsAt), let b = DateText.parse(visit.endsAt),
           DateText.dayKey(a, zone: zone) != DateText.dayKey(b, zone: zone) {
            return LF("%@ – %@ next morning", start, end)
        }
        return "\(start) – \(end)"
    }

    private var pendingTasks: [String] {
        ((extras?.pets ?? []).flatMap { $0.tasks ?? [] } + (extras?.houseTasks ?? [])).filter { $0.status == "pending" }.compactMap(\.label)
    }

    // MARK: Content

    @ViewBuilder private func content(_ visit: StaysHomeVisit, _ stay: StaysStay) -> some View {
        let status = visit.status ?? "planned"
        let state = StaysWords.homeVisitStatus(status)
        FlowLayout(spacing: 8) {
            StaysHomeVisitChips(visit: visit, status: state)
        }
        if visit.arrivedAt != nil || visit.leftAt != nil {
            Text([visit.arrivedAt.map { LF("Arrived %@", StaysDay.clockAt($0, zone: zone)) + (visit.arrivedByName.map { " · \($0)" } ?? "") },
                  visit.leftAt.map { LF("Left %@", StaysDay.clockAt($0, zone: zone)) }].compactMap { $0 }.joined(separator: " · "))
                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
        moves(visit, stay, status: status)
        if let onOpenStay {
            // From Domicilio: the way to the whole stay (its plan, keys, house, bill).
            Button(action: { dismiss(); onOpenStay() }) {
                HStack(spacing: 6) {
                    Glyph("house", size: 16)
                    Text(L("Open the home stay"))
                }
                .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
            }
            .buttonStyle(.plain)
        }
        if !canAct(visit) && workspace.can(.staysCare), let name = visit.sitter?.name {
            Text(LF("This is %@’s visit.", name)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        }
        if let note = visit.note?.nonEmpty { StaysNoteBlock(label: L("Note from the visit"), text: note) }
        if let reason = visit.cancelReason?.nonEmpty { StaysNoteBlock(label: L("Why it was cancelled"), text: reason) }
        checklist(visit, status: status)
        if let rules = extras?.houseRules?.nonEmpty { StaysNoteBlock(label: L("House rules"), text: rules, tint: Theme.mango) }
        let reports = extras?.reports ?? []
        if !reports.isEmpty {
            ModalSection(title: L("Report cards from this visit")) {
                ForEach(reports) { report in
                    VStack(alignment: .leading, spacing: 0) {
                        if let url = APIConfig.assetURL(report.photoUrl) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() } else { Theme.surfaceMuted }
                            }
                            .frame(maxWidth: .infinity).frame(height: 180).clipped()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            if let mood = StaysWords.mood(report.mood) { Text(mood.emoji) }
                            Text(report.message ?? "").font(Theme.text(14)).foregroundStyle(Theme.inkStrong).fixedSize(horizontal: false, vertical: true)
                            Text(StaysDay.clockAt(report.createdAt, zone: zone)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
            }
        }
    }

    @ViewBuilder private func moves(_ visit: StaysHomeVisit, _ stay: StaysStay, status: String) -> some View {
        let act = canAct(visit)
        FlowLayout(spacing: 8) {
            if act && stayOpen(visit, stay) && (status == "planned" || status == "missed") {
                if status == "planned", let opens = arrivalOpens(visit), opens > Date() {
                    Text(LF("You can mark the arrival from %@.", StaysDay.clockAt(DateText.iso(opens), zone: zone)))
                        .font(Theme.text(13, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                } else {
                    PMButton(status == "missed" ? L("Arrived after all") : L("Arrive"), systemImage: "log-in", size: .compact, isWorking: working) { arrivePressed(visit, stay) }
                }
            }
            if act && status == "in_progress" {
                PMButton(L("Leave"), systemImage: "log-out", size: .compact) { sheet = .leave }
            }
            if act && (status == "in_progress" || status == "done") && stay.status == "checked_in" {
                PMButton(L("Report card"), systemImage: "message-square-heart", size: .compact) { sheet = .report }
            }
            if act && stayOpen(visit, stay) && ["planned", "missed", "in_progress"].contains(status) {
                PMButton(L("Couldn’t get in"), systemImage: "door-closed", variant: .outline, size: .compact) { sheet = .noAccess }
            }
            if act && ["in_progress", "done", "missed"].contains(status) && !(status == "missed" && !canManage) {
                PMButton(status == "missed" ? L("Reopen") : L("Undo"), systemImage: "undo-2", variant: .outline, size: .compact, isWorking: working) { undo(visit) }
            }
            if canManage && status == "planned" {
                PMButton(L("Move or give to someone else"), systemImage: "pencil", variant: .outline, size: .compact) { sheet = .change }
                PMButton(L("Mark missed"), systemImage: "user-x", variant: .outline, size: .compact) { sheet = .missed }
            }
            if canManage && (status == "planned" || status == "missed") {
                PMButton(L("Cancel visit"), systemImage: "circle-x", variant: .outline, size: .compact) { sheet = .cancel }
            }
        }
    }

    // MARK: Checklist

    @ViewBuilder private func checklist(_ visit: StaysHomeVisit, status: String) -> some View {
        let pets = (extras?.pets ?? []).filter { !($0.tasks ?? []).isEmpty || $0.careNotes?.nonEmpty != nil }
        let house = extras?.houseTasks ?? []
        let all = (extras?.pets ?? []).flatMap { $0.tasks ?? [] } + house
        let done = all.filter { $0.status != "pending" && $0.status != nil }.count
        let enabled = canAct(visit) && status == "in_progress"
        ModalSection(title: L("Checklist"),
                     subtitle: status == "planned" || status == "missed" ? L("Tick it once you arrive.") : (all.isEmpty ? nil : LF("%d of %d done", done, all.count))) {
            if extras == nil {
                ProgressView().frame(maxWidth: .infinity)
            } else if all.isEmpty {
                EmptyState(systemImage: "clipboard-list", title: L("Nothing planned at this visit."), accent: Theme.aqua)
            } else {
                ForEach(Array(pets.enumerated()), id: \.offset) { _, pet in
                    Card(padding: 12, spacing: 8) {
                        HStack(spacing: 8) {
                            PetAvatar(name: pet.petName, species: nil, photoURL: pet.photoUrl, size: 28)
                            Text(pet.petName ?? "").font(.brandHeading(18)).foregroundStyle(Theme.inkStrong)
                        }
                        if let notes = pet.careNotes?.nonEmpty { Text(notes).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                        ForEach(pet.tasks ?? []) { task in row(task, scope: "pet", enabled: enabled) }
                    }
                }
                if !house.isEmpty {
                    Card(padding: 12, spacing: 8) {
                        HStack(spacing: 8) {
                            Glyph("house", size: 16).foregroundStyle(Theme.blue)
                            Text(L("The house")).font(.brandHeading(18)).foregroundStyle(Theme.inkStrong)
                        }
                        ForEach(house) { task in row(task, scope: "house", enabled: enabled) }
                    }
                }
            }
        }
    }

    private func row(_ task: StaysChecklistTask, scope: String, enabled: Bool) -> some View {
        let done = task.status == "done"
        let skipped = task.status == "skipped"
        return HStack(spacing: 10) {
            Button { mark(task, scope: scope, status: done ? "pending" : "done") } label: {
                ZStack {
                    Circle().fill(done ? Theme.blue : Color.clear)
                    Circle().strokeBorder(done ? Theme.blue : Theme.borderStrong, lineWidth: 2)
                    if done { Glyph("check", size: 16).foregroundStyle(Theme.onBlue) }
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityLabel(done ? LF("Mark %@ as not done", task.label ?? "") : LF("Mark %@ as done", task.label ?? ""))
            VStack(alignment: .leading, spacing: 1) {
                (Text(task.time.map { StaysDay.clock($0) + " " } ?? "").foregroundColor(Theme.inkSoft) + Text(task.label ?? ""))
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(skipped ? Theme.inkSoft : Theme.inkStrong)
                    .strikethrough(skipped)
                if let by = task.doneByName, task.status != "pending" { Text(by).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
            }
            Spacer(minLength: 0)
            if enabled && task.status == "pending" {
                Button { mark(task, scope: scope, status: "skipped") } label: {
                    HStack(spacing: 4) { Glyph("skip-forward", size: 14); Text(L("Skip")) }
                        .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            } else if enabled && skipped {
                Button(L("Undo")) { mark(task, scope: scope, status: "pending") }.font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue).buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(done ? AnyShapeStyle(Theme.blue.opacity(0.10)) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
    }

    /// Ticked on the spot: shown at once, put back if the server says no.
    private func mark(_ task: StaysChecklistTask, scope: String, status: String) {
        let before = extras
        extras = Self.ticked(extras, task.id, status)
        Task {
            let path = scope == "pet" ? "/provider-stay-tasks/\(task.id)" : "/provider-homestays/house-tasks/\(task.id)"
            do {
                try await API.send("PATCH", path, body: ["status": status])
                announceDataChanged()
            } catch {
                extras = before
                Toast.error(StaysWords.homeError(error, fallback: "Could not save that."))
            }
        }
    }

    private static func ticked(_ extras: StaysVisitExtras?, _ taskId: String, _ status: String) -> StaysVisitExtras? {
        guard let extras else { return nil }
        func change(_ task: StaysChecklistTask) -> StaysChecklistTask {
            guard task.id == taskId else { return task }
            return StaysChecklistTask(id: task.id, label: task.label, time: task.time, status: status, doneAt: task.doneAt,
                                      doneByName: status == "pending" ? nil : task.doneByName, note: task.note, kind: task.kind)
        }
        return StaysVisitExtras(
            pets: extras.pets?.map { StaysVisitPet(stayPetId: $0.stayPetId, petName: $0.petName, photoUrl: $0.photoUrl, careNotes: $0.careNotes, tasks: $0.tasks?.map(change)) },
            houseTasks: extras.houseTasks?.map(change),
            houseRules: extras.houseRules,
            reports: extras.reports,
            pendingTasks: extras.pendingTasks
        )
    }

    // MARK: Moves

    private func arrivePressed(_ visit: StaysHomeVisit, _ stay: StaysStay) {
        if let onArrive { onArrive(); return }
        working = true
        Task {
            defer { working = false }
            do {
                try await arrive(visit, stay, override: nil)
            } catch let api as APIError where api.code == "consent_required" {
                sheet = .gate
            } catch {
                Toast.error(StaysWords.homeError(error, fallback: "Could not mark the arrival."))
            }
        }
    }

    /// Through the consent gate: an owner or admin may go ahead with a reason. The press time and place go with it.
    private func arrive(_ visit: StaysHomeVisit, _ stay: StaysStay, override: String?) async throws {
        var body: [String: Any?] = ["at": DateText.iso(Date())]
        if let stamp { body["position"] = await stamp().body }
        if let override {
            body["overrideConsent"] = true
            body["overrideReason"] = override.nonEmpty
        }
        try await API.send("POST", "/provider-homestays/\(stay.id)/visits/\(visit.id)/arrive", body: body)
        Toast.show(stay.status == "confirmed" && visit.kind != "meet_greet"
            ? (stay.familyOnApp ? L("Arrived. The stay has started and the family has been told.") : L("Arrived. The stay has started."))
            : L("Arrived."))
        announceDataChanged()
        await load()
    }

    private func undo(_ visit: StaysHomeVisit) {
        working = true
        Task {
            defer { working = false }
            do {
                try await API.send("POST", "/provider-homestays/\(stayId)/visits/\(visit.id)/undo", body: [:])
                Toast.show(L("Undone."))
                announceDataChanged()
                await load()
            } catch {
                Toast.error(StaysWords.homeError(error, fallback: "Could not undo that."))
            }
        }
    }

    @ViewBuilder private func moveSheet(_ which: StaysVisitSheetKind, _ visit: StaysHomeVisit, _ stay: StaysStay) -> some View {
        let when = "\(StaysDay.short(visit.dayKey)) · \(Self.timeText(visit, zone: zone))"
        switch which {
        case .leave, .cancel, .missed, .noAccess:
            StaysVisitMoveSheet(stayId: stay.id, visitId: visit.id, move: which.rawValue, when: when, pending: pendingTasks,
                                locate: which == .leave ? stamp : nil)
        case .change:
            StaysVisitChangeSheet(stay: stay, visit: visit, zone: zone)
        case .report:
            StaysReportCardSheet(stayId: stay.id, pets: stay.petList, familyOnApp: stay.familyOnApp, visitId: visit.id) { Task { await load() } }
        case .gate:
            // The same gate a visit's start has (the consents to sign here or send, then start; owners and admins may go ahead).
            SchedGateSheet(prompt: SchedGatePrompt(
                petName: stay.petNames, verb: "start", kind: "consent", message: L("A required consent is still missing."),
                attempt: { extra in
                    let reason: String? = extra["overrideConsent"] != nil ? (((extra["overrideReason"] ?? nil) as? String) ?? "") : nil
                    do { try await arrive(visit, stay, override: reason) } catch let api as APIError where api.status >= 300 {
                        throw SchedFailure(api: api, body: api.body)
                    }
                },
                onDone: {},
                clientName: stay.clientName, familyOnApp: stay.familyOnApp,
                consents: StaysActs.consentContext(stay, businessName: workspace.current?.name)
            ))
        }
    }
}

// MARK: - Leave, cancel, missed, couldn't get in

/// A home stay's visit: leave (with what is still undone, the press time and place), cancel, mark missed
/// or couldn't get in. Opened from the visit, from Domicilio's card and from Home.
struct StaysVisitMoveSheet: View {
    let stayId: String
    let visitId: String
    /// "leave", "cancel", "missed" or "no-access".
    let move: String
    /// The visit's day and time, under the title.
    let when: String
    /// The checklist still undone, said before leaving so a medicine isn't forgotten (nil: read it here).
    var pending: [String]? = nil
    /// "3 of 5" when the undone names aren't known.
    var checklist: (done: Int, total: Int)? = nil
    /// Leaving: where the phone was, as Domicilio's Finish records it.
    var locate: (() async -> VisitPosition)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var note = ""
    @State private var reason = ""
    @State private var undone: [String] = []
    @State private var working = false

    private var title: String {
        switch move {
        case "cancel": L("Cancel this visit?")
        case "missed": L("Mark as missed?")
        case "no-access": L("Couldn’t get in")
        default: L("Leave the home")
        }
    }

    private var reasons: [(value: String, title: String, subtitle: String?)] {
        [("code_wrong", L("The code didn’t work"), nil), ("key_missing", L("The key wasn’t there"), nil), ("vault_empty", L("No access details written"), nil),
         ("nobody_home", L("Nobody was home to let me in"), nil), ("other", L("Something else"), nil)]
    }

    var body: some View {
        ProviderModal(
            title: title,
            subtitle: when,
            systemImage: move == "leave" ? "log-out" : move == "no-access" ? "door-closed" : move == "missed" ? "user-x" : "circle-x",
            accent: move == "leave" ? .aqua : .coral,
            isDirty: !note.isEmpty || !reason.isEmpty,
            form: form,
            primaryTitle: move == "leave" ? L("Leave") : move == "cancel" ? L("Cancel visit") : move == "missed" ? L("Mark missed") : L("Tell them"),
            primaryVariant: move == "leave" ? .primary : .destructive,
            isWorking: working,
            primaryIcon: move == "leave" ? "log-out" : nil,
            onPrimary: submit
        ) {
            // Web ReasonFrame: the sentence, what it needs, then the words with no label of their own.
            switch move {
            case "no-access":
                Text(L("The family and the owners are told at once, as an incident.")).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                VStack(alignment: .leading, spacing: 8) {
                    ChoiceCards(options: reasons, selection: Binding(get: { reason }, set: { reason = $0; form.clear("reason") }))
                    if let error = form.error("reason") { Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
                }
                .id("reason")
                StaysPlainField(prompt: L("Anything else (optional)"), text: $note, key: "note", form: form, multiline: true)
            case "cancel":
                Text(L("It won’t be charged. Its checklist moves to another visit that day.")).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                StaysPlainField(prompt: L("Reason (optional)"), text: $note, key: "note", form: form, multiline: true)
            case "missed":
                Text(L("Nobody went. It isn’t charged, and only someone who manages stays can reopen it.")).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                StaysPlainField(prompt: L("What happened (optional)"), text: $note, key: "note", form: form, multiline: true)
            default:
                Text(L("The visit is done. A line on how it went stays with the visit.")).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                if !undone.isEmpty {
                    NoticeCard(tone: .warning, title: LF("Not done yet: %@", undone.joined(separator: ", ")))
                } else if let checklist, checklist.done < checklist.total {
                    NoticeCard(tone: .warning, title: LF("Checklist · %d of %d", checklist.done, checklist.total))
                }
                StaysPlainField(prompt: L("How it went (optional)"), text: $note, key: "note", form: form, multiline: true)
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            guard move == "leave" else { return }
            if let pending { undone = pending; return }
            if let detail: StaysVisitExtras = try? await API.get("/provider-homestays/\(stayId)/visits/\(visitId)") {
                undone = ((detail.pets ?? []).flatMap { $0.tasks ?? [] } + (detail.houseTasks ?? [])).filter { $0.status == "pending" }.compactMap(\.label)
            }
        }
    }

    private func submit() {
        guard form.check([("reason", move == "no-access" && reason.isEmpty ? L("Say what happened.") : nil)]) else { return }
        working = true
        Task {
            defer { working = false }
            var body: [String: Any?]
            switch move {
            case "cancel": body = ["reason": note.nonEmpty]
            case "missed": body = ["note": note.nonEmpty]
            case "no-access": body = ["reason": reason, "note": note.nonEmpty]
            default:
                body = ["note": note.nonEmpty, "at": DateText.iso(Date())]
                if let locate { body["position"] = await locate().body }
            }
            do {
                try await API.send("POST", "/provider-homestays/\(stayId)/visits/\(visitId)/\(move)", body: body)
                Toast.show(move == "cancel" ? L("Visit cancelled.") : move == "missed" ? L("Marked as missed.") : move == "no-access" ? L("Recorded. The family and the owners have been told.") : L("Visit done."))
                announceDataChanged()
                dismiss()
            } catch {
                let api = error as? APIError
                form.apply(APIError(status: api?.status ?? 400, message: StaysWords.homeError(error, fallback: "Something went wrong. Try again."), code: api?.code, fields: api?.fields ?? [:]),
                           known: ["reason": "reason", "note": "note"])
            }
        }
    }
}

// MARK: - Move it or give it to someone else

private struct StaysVisitChangeSheet: View {
    let stay: StaysStay
    let visit: StaysHomeVisit
    let zone: TimeZone

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var members: [StaysMember] = []
    @State private var date = ""
    @State private var startTime = ""
    @State private var minutes = 45
    @State private var memberId = ""
    @State private var reason = ""
    @State private var conflict = false
    @State private var overlapOk = false
    @State private var working = false

    private var overnight: Bool { visit.kind == "overnight" }
    private var bookedMinutes: Int {
        guard let a = DateText.parse(visit.startsAt), let b = DateText.parse(visit.endsAt) else { return 45 }
        return max(0, Int((b.timeIntervalSince(a) / 60).rounded()))
    }
    private var moved: Bool { date != visit.dayKey || startTime != StaysDay.clockKey(visit.startsAt, zone: zone) || (!overnight && minutes != bookedMinutes) }
    private var reassigned: Bool { memberId != (visit.sitter?.memberId ?? "") }

    var body: some View {
        ProviderModal(
            title: L("Move or give to someone else"),
            subtitle: "\(StaysWords.homeVisitKind(visit.kind)) · \(StaysDay.short(visit.dayKey)) · \(StaysHomeVisitSheet.timeText(visit, zone: zone))",
            systemImage: "clipboard-list",
            accent: .aqua,
            isDirty: moved || reassigned,
            form: form,
            primaryTitle: conflict ? L("Save anyway") : L("Save"),
            isWorking: working,
            primaryIcon: "check",
            onPrimary: submit
        ) {
            DayField(label: L("Day"), day: Binding(get: { date }, set: { date = $0; reset() }), key: "date", form: form)
            TimeField(label: L("Time"), value: Binding(get: { startTime }, set: { startTime = $0; reset() }), from: "05:00", to: "23:45")
            if !overnight {
                MenuField(label: L("Length"), options: Array(Set([15, 20, 30, 45, 60, 90, 120, 180, 240, minutes])).sorted().map { (value: $0, title: StaysHomePlanForm.minutesText($0)) },
                          selection: Binding(get: { minutes }, set: { minutes = $0; reset() }))
            }
            MenuField(label: L("Sitter"), options: [(value: "", title: L("Nobody yet"))] + members.filter { $0.canCare || $0.id == visit.sitter?.memberId }.map { (value: $0.id, title: $0.label) },
                      selection: Binding(get: { memberId }, set: { memberId = $0; reset() }))
            if reassigned {
                PMTextField(L("Why (the family reads it)"), text: $reason, prompt: L("e.g. Laura is sick"))
            }
            if conflict { StaysHomeTeam.conflictNotice(confirmed: $overlapOk) }
        }
        .onAppear {
            guard date.isEmpty else { return }
            date = visit.dayKey
            startTime = StaysDay.clockKey(visit.startsAt, zone: zone)
            minutes = bookedMinutes
            memberId = visit.sitter?.memberId ?? ""
        }
        .task { if members.isEmpty { members = await StaysHomeTeam.members() } }
    }

    private func reset() { conflict = false; overlapOk = false; form.clear("date") }

    private func submit() {
        guard moved || reassigned else { dismiss(); return }
        if conflict && !overlapOk { Toast.error(L("The sitter is busy then. Check the warning and book it anyway if you meant to.")); return }
        working = true
        Task {
            defer { working = false }
            var body: [String: Any?] = [:]
            if moved {
                body["date"] = date
                body["startTime"] = startTime
                if !overnight { body["durationMinutes"] = minutes }
            }
            if reassigned {
                body["memberId"] = memberId.nonEmpty
                body["reason"] = reason.nonEmpty
            }
            if overlapOk { body["allowDoubleBooking"] = true }
            do {
                try await API.send("PATCH", "/provider-homestays/\(stay.id)/visits/\(visit.id)", body: body)
                Toast.show(reassigned && stay.status != "requested" ? L("Visit changed. The family has been told.") : L("Visit changed."))
                announceDataChanged()
                dismiss()
            } catch let api as APIError where api.code == "visit_conflict" {
                conflict = true
                overlapOk = false
            } catch {
                _ = form.check([("date", StaysWords.homeError(error, fallback: "Something went wrong. Try again."))])
            }
        }
    }
}
