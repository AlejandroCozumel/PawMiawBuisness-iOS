//
//  SchedComponents.swift
//  PawMiawNegocios
//
//  The Schedule's own small pieces, built from the shared design: the
//  "En línea" and "Por confirmar" marks, a visit's status pills, the
//  double-booking and hours warnings, a visit row, and the consent gate a
//  start may run into.
//

import SwiftUI

// MARK: - Marks

/// "En línea": a family booked it from the app (web `OnlineMark`).
struct SchedOnlineMark: View {
    var body: some View { Chip(text: L("Online"), tone: .online, icon: "globe") }
}

/// "Por confirmar": a requested visit, dashed (it holds the time, it isn't a visit yet; web `PendingMark`).
struct SchedPendingMark: View {
    var body: some View { Chip(text: L("To confirm"), icon: "clock-3", pending: true) }
}

/// "Cambio de hora": the family asks to move a confirmed online booking; dashed like a request (it waits on you).
struct SchedRescheduleMark: View {
    var body: some View { Chip(text: L("Change of time"), icon: "arrow-right-left", pending: true) }
}

/// The visit's state, and what happened to its bill or fee when the list knows (web `StatusPills`).
struct SchedStatusPills: View {
    let appointment: SchedAppointment

    var body: some View {
        let missed = appointment.isGone
        if appointment.isRequested {
            SchedPendingMark()
        } else {
            Chip(text: SchedStatus.label(appointment.status), tone: (missed) ? .danger : .custom(ProviderState.appointment(appointment.status).color))
        }
        if appointment.bookedOnline == true { SchedOnlineMark() }
        if appointment.status == "completed" && appointment.noCharge == true { Chip(text: L("No charge"), tone: .custom(Theme.lime)) }
        if missed && appointment.feeDecision == "charged" { Chip(text: L("Fee charged"), tone: .custom(Theme.mango)) }
        if missed && appointment.feeDecision == "waived" { Chip(text: L("Fee waived"), tone: .custom(Theme.inkSoft)) }
    }
}

// MARK: - Warnings

/// A double booking: who or what is taken, and the switch to book it anyway.
struct SchedConflictWarning: View {
    let conflicts: [SchedConflict]
    @Binding var confirmed: Bool

    private var onlyOut: Bool { conflicts.allSatisfy { $0.kind == "room" && $0.outOfService != nil } }

    var body: some View {
        if !conflicts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                NoticeCard(tone: .problem, title: onlyOut ? L("Room out of service") : L("Double booking"), message: conflicts.map { SchedConflicts.line($0) }.joined(separator: "\n"))
                ToggleRow(title: onlyOut ? L("Book it anyway — I know it is out of service") : L("Book it anyway — I know they overlap"), isOn: $confirmed)
            }
        }
    }
}

/// Outside the hours (a closed date, someone's day off): said, and booked only on purpose.
struct SchedHoursWarning: View {
    let problem: SchedHoursProblem
    var personName: String? = nil
    @Binding var confirmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NoticeCard(tone: .warning, title: SchedHours.problemTitle(problem, personName: personName), message: SchedHours.problemBody(problem))
            ToggleRow(title: L("Book it anyway"), isOn: $confirmed)
        }
    }
}

// MARK: - A day heading

/// The list's day band (web agenda-list `DayHeading`): "Hoy · miércoles 4 de noviembre",
/// "Ayer · …", or just "Viernes 6 de noviembre" — the kit's `DayBand`.
func schedDayBand(_ day: String, detail: String? = nil) -> DayBand {
    if let relative = SchedDay.relative(day) {
        return DayBand(title: SchedDay.longLabel(day).lowercased(), lead: relative, highlighted: day == SchedDay.today, trailing: detail)
    }
    return DayBand(title: SchedDay.longLabel(day), trailing: detail)
}

// MARK: - A visit in a list

/// The next step a row's button takes (as on Home and the visit page).
enum SchedRowAction {
    case open, answer, checkIn, start, finish

    var title: String {
        switch self {
        case .open: L("Open")
        case .answer: L("Answer")
        case .checkIn: L("Check in")
        case .start: L("Start")
        case .finish: L("Finish")
        }
    }

    var systemImage: String {
        switch self {
        case .open: "chevron-right"
        case .answer: "message-square-reply"
        case .checkIn: "arrow-right-to-line"
        case .start: "play"
        case .finish: "badge-check"
        }
    }

    static func next(for appointment: SchedAppointment, canCheckIn: Bool, canStart: Bool) -> SchedRowAction {
        if appointment.group?.isSession == true { return .open }
        if appointment.isRequested { return .answer }
        if appointment.status == "scheduled" && canCheckIn && SchedDay.key(appointment.startsAt) == SchedDay.today { return .checkIn }
        if appointment.status == "checked_in" && canStart { return .start }
        if appointment.status == "in_progress" && canStart { return .finish }
        return .open
    }
}

/// One visit in the list (web agenda-list `ListRow`): the time in Fredoka, the pet
/// (its face opens the chart), "service · client", who and where, its pills, and the
/// next step's button. The row opens the visit.
struct SchedVisitRow: View {
    let appointment: SchedAppointment
    var action: SchedRowAction = .open
    var canOpenChart = false
    var onAction: ((SchedRowAction) -> Void)? = nil
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var asking: Bool { appointment.familyAsking }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // The row opens the visit; the pet's face opens its chart (kept outside the row's link).
            NavigationLink(value: ProviderRoute.appointment(appointment.id)) {
                Text(DateText.time(appointment.start))
                    .font(.brandHeading(15.2)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: 60, alignment: .leading)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            face
            NavigationLink(value: ProviderRoute.appointment(appointment.id)) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(appointment.petName).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            if appointment.doubleBooked == true {
                                Glyph("triangle-alert", size: 14).foregroundStyle(Theme.destructive).accessibilityLabel(L("Double booked"))
                            }
                            if asking {
                                Glyph("message-circle-question", size: 14).foregroundStyle(Theme.pink).accessibilityLabel(L("The family asked for a change"))
                            }
                        }
                        Text("\(appointment.serviceLabel) · \(appointment.clientName)").font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                        if let line = groupLine {
                            HStack(spacing: 4) { Glyph("users-round", size: 12); Text(line).lineLimit(1) }
                                .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue)
                        }
                        FlowLayout(spacing: 6, lineSpacing: 4) {
                            HStack(spacing: 4) { Glyph("user-round", size: 12); Text(appointment.assignedMember?.name ?? L("Nobody yet")).lineLimit(1) }
                            if let room = appointment.room { HStack(spacing: 4) { Glyph("door-open", size: 12); Text(room).lineLimit(1) } }
                            SchedStatusPills(appointment: appointment)
                        }
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // On a phone, as on the web's, the row itself opens the visit: only check-in and start keep a button.
            if let onAction {
                if sizeClass == .regular {
                    PMButton(action.title, systemImage: action.systemImage, variant: .outline, size: .compact) { act(onAction) }
                } else if action == .checkIn || action == .start {
                    IconCircleButton(systemImage: action.systemImage, label: action.title, tint: Theme.blue) { act(onAction) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var face: some View {
        let avatar = PetAvatar(name: appointment.petName, species: appointment.petSpecies, photoURL: appointment.petPhotoUrl, size: 40)
        if canOpenChart {
            NavigationLink(value: ProviderRoute.patientChart(petId: appointment.providerClientPetId)) { avatar }
                .buttonStyle(.plain)
                .accessibilityLabel(LF("Open %@’s chart", appointment.petName))
        } else {
            avatar
        }
    }

    /// Answering and finishing open the visit; check-in and start run here.
    private func act(_ onAction: (SchedRowAction) -> Void) {
        onAction(action)
    }

    private var groupLine: String? {
        guard let group = appointment.group else { return nil }
        if group.isSession { return "\(group.serviceLabel ?? "") · \(group.placesLabel)" }
        let others = group.stayingPets.filter { $0.appointmentId != appointment.id }.compactMap(\.name)
        guard !others.isEmpty else { return nil }
        return LF("Together with %@", schedNames(others))
    }
}

/// The same person written two ways ("Hernandez" and "Hernández").
func schedSameName(_ left: String, _ right: String) -> Bool {
    left.trimmingCharacters(in: .whitespaces).compare(right.trimmingCharacters(in: .whitespaces), options: [.caseInsensitive, .diacriticInsensitive], locale: .app) == .orderedSame
}

/// "Luna, Coco y Max".
func schedNames(_ names: [String]) -> String {
    guard names.count > 1 else { return names.first ?? "" }
    return LF("%@ and %@", names.dropLast().joined(separator: ", "), names.last!)
}

// MARK: - The consent and deposit gate

/// A start (or a check-in that starts) refused for a consent nobody signed, or for an
/// emergency deposit not taken yet (409 `consent_required` / `deposit_required`).
struct SchedGatePrompt: Identifiable {
    let id = UUID()
    let petName: String
    /// "start" or "check_in".
    let verb: String
    /// "consent" or "deposit".
    let kind: String
    let message: String
    /// Tries again with the override's body (`overrideConsent`/`overrideDeposit` and the reason).
    let attempt: ([String: Any?]) async throws -> Void
    let onDone: () -> Void
    /// "Check in without starting".
    var fallback: (() async throws -> Void)? = nil
    /// The visit, when it exists (a walk-in doesn't until it is created): its consents are signed here.
    var appointmentId: String? = nil
    /// Whose account takes the deposit.
    var clientId: String? = nil
    var clientName: String? = nil
    var familyOnApp: Bool = false
    /// The emergency deposit owed (deposit_required).
    var deposit: SchedDepositDue? = nil
    /// The consents missing (consent_required), for a walk-in with no visit yet.
    var missing: [ConsentLine] = []
    /// A walk-in: the deposit goes with it (`payment`, then the override already given).
    var takeDeposit: (([String: Any?], [String: Any?]) async throws -> Void)? = nil
    /// Another act's consents (a home stay's first arrival); a visit's come from `appointmentId`.
    var consents: ConsentContext? = nil

    static func from(_ error: Error, petName: String, verb: String, attempt: @escaping ([String: Any?]) async throws -> Void, onDone: @escaping () -> Void, fallback: (() async throws -> Void)? = nil,
                     appointmentId: String? = nil, clientId: String? = nil, clientName: String? = nil, familyOnApp: Bool = false,
                     takeDeposit: (([String: Any?], [String: Any?]) async throws -> Void)? = nil) -> SchedGatePrompt? {
        guard let failure = error as? SchedFailure else { return nil }
        let kind: String
        switch failure.code {
        case "consent_required": kind = "consent"
        case "deposit_required": kind = "deposit"
        default: return nil
        }
        return SchedGatePrompt(petName: petName, verb: verb, kind: kind, message: failure.api.message, attempt: attempt, onDone: onDone, fallback: fallback,
                               appointmentId: appointmentId, clientId: clientId, clientName: clientName, familyOnApp: familyOnApp,
                               deposit: failure.depositGap, missing: failure.consentGap, takeDeposit: takeDeposit)
    }

    /// The same prompt for a visit: who it is for, where its consents and deposit go.
    static func from(_ error: Error, visit: SchedAppointment, verb: String, attempt: @escaping ([String: Any?]) async throws -> Void, onDone: @escaping () -> Void, fallback: (() async throws -> Void)? = nil) -> SchedGatePrompt? {
        from(error, petName: visit.petName, verb: verb, attempt: attempt, onDone: onDone, fallback: fallback,
             appointmentId: visit.id, clientId: visit.providerClientId, clientName: visit.clientName, familyOnApp: visit.clientHouseholdId != nil)
    }
}

private enum SchedGateStep: Identifiable {
    case override, deposit
    var id: Int { self == .override ? 0 : 1 }
}

/// The sheet for a gate: what is missing — the consents to sign here (or send) or the emergency
/// deposit to take — then the start; owners and admins may start anyway with a reason; or check in only.
struct SchedGateSheet: View {
    let prompt: SchedGatePrompt
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var kind = ""
    @State private var owed: SchedDepositDue?
    /// An override already given on the way (a consent), sent again with the deposit's.
    @State private var base: [String: Any?] = [:]
    @State private var satisfied = false
    @State private var step: SchedGateStep?
    @State private var working = false

    private var canOverride: Bool { workspace.isOwnerOrAdmin }
    private var checkIn: Bool { prompt.verb == "check_in" }
    private var isDeposit: Bool { (kind.isEmpty ? prompt.kind : kind) == "deposit" }
    private var canTake: Bool { prompt.clientId != nil && (prompt.appointmentId != nil || prompt.takeDeposit != nil) }
    private var due: SchedDepositDue? { owed ?? prompt.deposit }

    var body: some View {
        ProviderModal(
            title: isDeposit ? LF("%@ needs the emergency deposit first", prompt.petName) : (checkIn ? LF("%@ can’t check in yet", prompt.petName) : LF("%@ can’t start yet", prompt.petName)),
            subtitle: isDeposit ? L("Treatment starts once it is paid. A critical patient never waits for it.") : L("The service needs these consents signed first."),
            systemImage: isDeposit ? "siren" : "shield-alert",
            accent: .mango,
            primaryTitle: primaryTitle,
            isWorking: working,
            cancelTitle: L("Not now"),
            secondaryActions: footerActions,
            primaryIcon: isDeposit ? "hand-coins" : "play",
            onPrimary: primaryAction
        ) {
            if isDeposit { depositContent } else { consentContent }
        }
        .presentationDetents([.large])
        .sheet(item: $step) { item in
            switch item {
            case .override:
                ConfirmSheet(
                    title: isDeposit ? (checkIn ? L("Check in before the deposit is paid?") : L("Start before the deposit is paid?")) : (checkIn ? L("Check in without the signed consent?") : L("Start without the signed consent?")),
                    message: L("Only owners and admins can. It is written down with your name and the reason."),
                    confirmTitle: checkIn ? L("Check in anyway") : L("Start anyway"),
                    destructive: true, askReason: true, reasonRequired: true, cancelTitle: L("Not now")
                ) { reason in
                    var body = base
                    if isDeposit { body["overrideDeposit"] = true } else { body["overrideConsent"] = true }
                    body["overrideReason"] = reason ?? ""
                    try await go(body)
                }
            case .deposit:
                DepositSheet(
                    clientId: prompt.clientId ?? "",
                    clientName: prompt.clientName ?? "",
                    appointmentId: prompt.appointmentId,
                    owed: due?.owed ?? 0,
                    currency: due?.currency,
                    label: LF("Emergency deposit · %@", prompt.petName),
                    explanation: prompt.takeDeposit == nil ? L("It stays as credit on their account and is used when they pay the visit.") : nil,
                    takeWith: prompt.takeDeposit.map { take in { payment in
                        do { try await take(payment, base) } catch { throw schedAPIError(error) }
                    } },
                    closesWhenTaken: true,
                    onTaken: {
                        // Once the deposit's sheet is gone: done (a walk-in), or the start again.
                        Task {
                            try? await Task.sleep(for: .milliseconds(450))
                            if prompt.takeDeposit != nil {
                                prompt.onDone()
                                dismiss()
                            } else {
                                try? await go(base)
                            }
                        }
                    }
                )
            }
        }
    }

    /// The footer's other ways (web: the fallback, then "Start anyway" in red), above "Not now".
    private var footerActions: [ModalAction] {
        var actions: [ModalAction] = []
        if let fallback = prompt.fallback {
            actions.append(ModalAction(L("Check in without starting"), isWorking: working) {
                working = true
                Task {
                    defer { working = false }
                    do {
                        try await fallback()
                        dismiss()
                    } catch { schedToast(error) }
                }
            })
        }
        if canOverride {
            actions.append(ModalAction(checkIn ? L("Check in anyway") : L("Start anyway"), tint: Theme.destructive) { step = .override })
        }
        return actions
    }

    private var primaryTitle: String? {
        if isDeposit { return canTake ? L("Take the deposit") : nil }
        return prompt.appointmentId != nil || prompt.consents != nil ? (checkIn ? L("Check in now") : L("Start now")) : nil
    }

    private var primaryAction: (() -> Void)? {
        if isDeposit { return canTake ? { step = .deposit } : nil }
        guard prompt.appointmentId != nil || prompt.consents != nil else { return nil }
        return {
            guard satisfied else {
                Toast.error(L("A required consent is still missing."))
                return
            }
            working = true
            Task {
                defer { working = false }
                try? await go(base)
            }
        }
    }

    /// Where the consents to sign are: the act given, else the visit.
    private func consentContext(_ businessName: String?) -> ConsentContext? {
        if let given = prompt.consents { return given }
        return prompt.appointmentId.map { ConsentContext(act: ConsentAct(appointmentId: $0), businessName: businessName, clientName: prompt.clientName ?? "", familyOnApp: prompt.familyOnApp) }
    }

    @ViewBuilder private var consentContent: some View {
        if let context = consentContext(workspace.current?.name) {
            if satisfied {
                NoticeCard(tone: .success, title: checkIn ? L("Everything is signed. You can check in now.") : L("Everything is signed. You can start now."))
            } else {
                Text(L("Sign them here with the client, or send them to the family and start once they sign.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            ConsentsCard(context: context, bare: true) { list in satisfied = list.requirement?.satisfied ?? (list.requirement == nil) }
        } else {
            if !prompt.missing.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(prompt.missing.enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 8) { Glyph("circle-alert", size: 16); Text(line.title ?? "") }
                            .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(Theme.mango, 10), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.mango, 60, with: Theme.borderSoft), lineWidth: 1))
            } else {
                Text(prompt.message).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
            }
            Text(L("Check the pet in: the visit asks for the consents, and the client can sign them there on this device. Then start.")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
        }
    }

    @ViewBuilder private var depositContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Money.format(due?.owed ?? 0, currency: due?.currency)).font(.brandHeading(24, relativeTo: .title)).foregroundStyle(Theme.inkStrong)
            if let due, (due.paid ?? 0) > 0 {
                Text(LF("%@ paid of %@.", Money.format(due.paid, currency: due.currency), Money.format(due.amount, currency: due.currency))).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
            } else {
                Text(L("The store’s emergency deposit (Store → Settings).")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(Theme.mango, 10), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.mango, 60, with: Theme.borderSoft), lineWidth: 1))
        Text(canTake
             ? L("Take it now: it stays as credit on their account, is used when they pay, and treatment starts right after.")
             : L("Check the pet in first: the deposit is taken on the visit, then treatment starts."))
            .font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
    }

    /// The start again; a deposit asked after a consent turns this into the deposit's gate.
    private func go(_ body: [String: Any?]) async throws {
        do {
            try await prompt.attempt(body)
            prompt.onDone()
            dismiss()
        } catch let failure as SchedFailure where failure.code == "deposit_required" {
            base = body.filter { $0.key != "overrideDeposit" }
            owed = failure.depositGap
            kind = "deposit"
            Toast.show(L("Take the deposit, then start."))
        } catch let failure as SchedFailure where failure.code == "consent_required" {
            Toast.error(L("A required consent is still missing."))
            announceDataChanged()
        } catch {
            schedToast(error)
            throw schedAPIError(error)
        }
    }
}

// MARK: - Starting a visit

enum SchedVisitOps {
    /// `POST …/start`, with the override's body when there is one.
    static func start(_ appointmentId: String, extra: [String: Any?] = [:]) async throws {
        let _: SchedMoveResponse = try await SchedAPI.send("POST", "/provider-appointments/\(appointmentId)/start", body: extra)
        announceDataChanged()
    }

    /// Start, or the gate's prompt when a consent or deposit stops it.
    static func startWithGate(_ appointment: SchedAppointment, onGate: @escaping (SchedGatePrompt) -> Void) async {
        let id = appointment.id
        let pet = appointment.petName
        do {
            try await start(id)
            Toast.show(LF("%@ is in.", pet))
        } catch {
            if let prompt = SchedGatePrompt.from(error, visit: appointment, verb: "start", attempt: { extra in try await start(id, extra: extra) }, onDone: { Toast.show(LF("%@ is in.", pet)) }) {
                onGate(prompt)
            } else {
                schedToast(error)
            }
        }
    }
}

// MARK: - A sheet's bare text box

/// A text box with no label of its own: the `ModalSection` above it names it (web: a
/// `ProviderSheetSection` over a bare `Textarea`, the check-in's arrival notes). Marked,
/// said and scrolled to like any field of the form.
struct SchedBareField: View {
    let prompt: String
    @Binding var text: String
    var key: String? = nil
    @ObservedObject var form: FormState
    var multiline = true

    private var error: String? { key.flatMap { form.error($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if multiline {
                    TextField(prompt, text: $text, axis: .vertical).lineLimit(3...8)
                } else {
                    TextField(prompt, text: $text)
                }
            }
            .fieldChrome(invalid: error != nil, multiline: multiline)
            .accessibilityLabel(prompt)
            .onChange(of: text) { _, _ in if let key { form.clear(key) } }
            if let error {
                Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral)
            }
        }
        .id(key ?? prompt)
    }
}

/// One of a sheet's other ways out, as a bordered row: what it is, a line, and its button
/// (web visit-sheets: "Here for something else?", "It did happen?", "They never came?").
struct SchedWayRow: View {
    let title: String
    let hint: String
    let actionTitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                Text(hint).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
            PMButton(actionTitle, systemImage: icon, variant: .outline, size: .small, action: action)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(shape.strokeBorder(Theme.borderSoft, lineWidth: 1))
    }
}
