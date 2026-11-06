//
//  SchedVisitPanels.swift
//  PawMiawNegocios
//
//  The visit page's parts (web provider.appointments.$appointmentId.tsx and
//  visits/visit-note.tsx): the visit's four steps, the banners (a family
//  asking for a change, a missed visit's story), the arrival and waiting
//  locks, the note written during the visit (saved as a draft as you type,
//  signed by whoever signs), what else was recorded, the closing card and the
//  bill's summary.
//

import SwiftUI

// MARK: - The journey

/// A step of the visit (arrive, the visit, sign, pay), shown as one of the header's numbers.
struct SchedJourneyStep: Identifiable {
    enum State { case done, now, next, attention, skip }
    let id: String
    let label: String
    let value: String
    var extra: String? = nil
    let state: State
    let systemImage: String

    /// The header's stat (web `journeyStat`): done is ticked, where the visit is now is
    /// underlined, what needs someone reads red, what is still to come is quieter.
    var stat: ModuleStat {
        ModuleStat(id, label: label, value: value, hint: extra,
                   icon: state == .done ? "check" : systemImage,
                   accent: state == .done ? Theme.lime : state == .attention ? Theme.pink : state == .now ? Theme.aqua : Theme.surfaceMuted,
                   attention: state == .attention, active: state == .now, muted: state == .next || state == .skip)
    }
}

// MARK: - Banners

/// What the visit is waiting on: a request from the family, a missed visit's story (who cancelled
/// it, its fee), and the family's "Sí fuimos" after a no-show with what the business can do about
/// it (web `Banners`, docs/family-money.md §5): full-width rows under the header's client line,
/// each tinted by its tone.
struct SchedVisitBanners: View {
    let appointment: SchedAppointment
    var onEdit: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    var onKeep: (() -> Void)? = nil
    /// "Perdonar el cargo": the no-show fee's bill, forgiven with a reason.
    var onForgiveFee: (() -> Void)? = nil
    /// "Descartar": off Home's "Te necesita"; the answer stays here.
    var onDismissDispute: (() -> Void)? = nil
    var dismissing: Bool = false

    private enum Tone { case warn, danger, info }

    var body: some View {
        let a = appointment
        VStack(spacing: 1) {
            if a.status == "scheduled" && a.confirmationStatus == "reschedule_requested" {
                banner(.warn, L("The family asked to move this visit"), [a.confirmationPreferredTime, a.confirmationNote].compactMap { $0?.nonEmpty }.joined(separator: " · ").nonEmpty) {
                    if let onEdit { PMButton(L("Move it"), size: .header, action: onEdit) }
                    if let onKeep { PMButton(L("Keep as booked"), variant: .outline, size: .header, action: onKeep) }
                }
            }
            if a.status == "scheduled" && a.confirmationStatus == "cancellation_requested" {
                banner(.warn, L("The family asked to cancel"), a.confirmationNote) {
                    if let onCancel { PMButton(L("Cancel visit"), size: .header, action: onCancel) }
                    if let onKeep { PMButton(L("Keep it"), variant: .outline, size: .header, action: onKeep) }
                }
            }
            if a.status == "scheduled", ["delivery_failed", "expired", "declined"].contains(a.confirmationStatus ?? "") {
                banner(.warn, a.confirmationStatus == "declined" ? L("The family declined this visit") : L("The confirmation did not reach them"), a.clientPhone.map { LF("Call them: %@", $0) }) { EmptyView() }
            }
            if a.isGone {
                // Who cancelled: the family (a fee may follow) or the business (never one). Older visits don't say.
                let cancelled = a.cancelledBy == "family" ? L("Cancelled by the family") : a.cancelledBy == "business" ? L("Cancelled by your business") : L("Cancelled")
                banner(.danger, a.status == "no_show" ? L("They didn’t come") : cancelled, [outcome ?? a.cancelReason, fee].compactMap { $0?.nonEmpty }.joined(separator: " · ").nonEmpty) { EmptyView() }
            }
            // "Sí fuimos": the family says the pet did come after the no-show was recorded. Nothing changes by itself.
            if a.status == "no_show", let disputed = a.disputedAt {
                banner(.warn, LF("The family says they did come (%@)", DateText.dayTime(DateText.parse(disputed))),
                       a.disputeDismissedAt.map { LF("Dismissed on %@.", DateText.day($0)) }
                        ?? (onForgiveFee != nil ? L("You decide: forgive the fee or dismiss it. Nothing changes by itself.") : L("Nothing changes by itself."))) {
                    if let onForgiveFee { PMButton(L("Forgive the fee"), systemImage: "hand-heart", size: .header, action: onForgiveFee) }
                    if let onDismissDispute { PMButton(L("Dismiss"), variant: .outline, size: .header, isWorking: dismissing, action: onDismissDispute) }
                }
            }
            if a.status == "completed" && a.noCharge == true {
                banner(.info, L("Finished with no charge."), a.noChargeReason) { EmptyView() }
            }
            if let note = a.arrivalNote?.nonEmpty, a.status == "checked_in" || a.status == "in_progress" {
                banner(.info, L("At the desk"), note) { EmptyView() }
            }
        }
        .background(Theme.borderSoft)
    }

    /// Whether any banner shows (the header draws a rule above them only then).
    static func any(_ a: SchedAppointment) -> Bool {
        (a.status == "scheduled" && ["reschedule_requested", "cancellation_requested", "delivery_failed", "expired", "declined"].contains(a.confirmationStatus ?? ""))
            || a.isGone || (a.status == "completed" && a.noCharge == true)
            || (a.status == "no_show" && a.disputedAt != nil)
            || (a.arrivalNote?.nonEmpty != nil && (a.status == "checked_in" || a.status == "in_progress"))
    }

    private var fee: String? {
        guard appointment.feeKind != nil else { return nil }
        return appointment.feeDecision == "charged" ? L("The fee was charged to their account.") : LF("The fee was waived: %@", appointment.feeNote ?? "—")
    }

    /// An online booking that ended without a visit says how.
    private var outcome: String? {
        switch appointment.onlineOutcome {
        case "declined": return appointment.declineReason.map { LF("Declined: %@", $0) } ?? L("Declined")
        case "expired": return L("Released: nobody answered in time")
        case "cancelled_by_family": return L("The family cancelled it")
        default: return nil
        }
    }

    private func banner<Actions: View>(_ tone: Tone, _ title: String, _ body: String?, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Glyph("triangle-alert", size: 16).foregroundStyle(tone == .danger ? Theme.destructive : Theme.inkSoft).padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    if let body { Text(body).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) { actions() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill(tone))
    }

    private func fill(_ tone: Tone) -> AnyShapeStyle {
        switch tone {
        case .warn: AnyShapeStyle(Theme.wash(Theme.mango, 16))
        case .danger: AnyShapeStyle(Theme.wash(Theme.destructive, 8))
        case .info: AnyShapeStyle(Theme.wash(Theme.aqua, 12))
        }
    }
}

// MARK: - Before the visit is written

/// A lock in place of the visit's work (web `ArrivalLock`/`WaitingLock`): a dashed card
/// tinted by the step, a 56 well, a Fredoka 24 title, the line, then what comes next.
private struct SchedLockCard<Content: View>: View {
    let icon: String
    let iconInk: Color
    let tint: Color
    let border: Double
    let fill: Double
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Glyph(icon, size: 24)
                .foregroundStyle(iconInk)
                .frame(width: 56, height: 56)
                .background(Theme.surface, in: Circle())
                .cardShadow()
            content()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
        .background(Theme.wash(tint, fill), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.mix(tint == Theme.aqua ? Theme.blue : tint, border, with: Theme.borderSoft), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}

/// Before the pet arrives, the visit is read, not written.
struct SchedArrivalLock: View {
    let appointment: SchedAppointment
    let late: Bool
    let dayWhen: String
    let canStart: Bool
    var onArrive: (() -> Void)?

    var body: some View {
        let pet = appointment.petName
        SchedLockCard(icon: "door-open", iconInk: Theme.blue, tint: Theme.aqua, border: 40, fill: 8) {
            Text(dayWhen == "future" ? LF("%@ comes another day", pet) : dayWhen == "past" ? LF("%@ was never checked in", pet) : LF("%@ hasn’t arrived yet", pet))
                .font(.brandHeading(24, relativeTo: .title2)).foregroundStyle(Theme.inkStrong)
                .padding(.top, 16)
            Text(sentence + " " + L("The note, the charges and the report open when you register the arrival. Until then, read the chart to prepare."))
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: 448)
                .padding(.top, 4)
            if let onArrive {
                // Whoever can see the pet starts the visit as it arrives; the front desk sends it to the waiting room.
                PMButton(canStart ? L("Register arrival and start") : L("Register arrival"), systemImage: canStart ? "play" : "log-in", action: onArrive)
                    .padding(.top, 20)
            } else {
                Text(L("The front desk registers the arrival.")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft).padding(.top, 16)
            }
        }
    }

    private var sentence: String {
        let time = DateText.time(appointment.start)
        let text: String
        if dayWhen != "today" {
            text = LF("Booked for %@ at %@", DateText.day(appointment.start), time)
        } else if late {
            let minutes = max(0, Int(Date().timeIntervalSince(appointment.start ?? Date()) / 60))
            return LF("Booked for %@, %@ min ago.", time, String(minutes))
        } else {
            text = LF("Booked for %@", time)
        }
        return text.hasSuffix(".") ? text : text + "."
    }
}

/// Checked in, not started: the pet is in the waiting room.
struct SchedWaitingLock: View {
    let appointment: SchedAppointment
    var onStart: (() -> Void)?
    var starting = false

    var body: some View {
        let waited = max(0, Int(Date().timeIntervalSince(DateText.parse(appointment.arrivedAt) ?? Date()) / 60))
        SchedLockCard(icon: "clock-3", iconInk: Theme.inkStrong, tint: Theme.lime, border: 60, fill: 10) {
            Text(LF("%@ is waiting · %@ min", appointment.petName, String(waited)))
                .font(.brandHeading(24, relativeTo: .title2)).foregroundStyle(Theme.inkStrong)
                .padding(.top, 16)
            Text(L("The note, the records, the report and the charges open when the visit starts."))
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: 448)
                .padding(.top, 4)
            let facts = self.facts
            if !facts.isEmpty {
                VStack(spacing: 8) {
                    ForEach(facts, id: \.label) { fact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fact.label.uppercased()).font(Theme.text(11.2, weight: .heavy)).tracking(1.1).foregroundStyle(Theme.inkSoft)
                            Text(fact.value).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                        }
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                    }
                }
                .frame(maxWidth: 448)
                .padding(.top, 20)
            }
            if let onStart {
                PMButton(L("Start the visit"), systemImage: "play", isWorking: starting, action: onStart).padding(.top, 20)
            } else {
                Text(L("Waiting for the vet to start the visit.")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft).padding(.top, 16)
            }
        }
    }

    private var facts: [(label: String, value: String)] {
        var out: [(label: String, value: String)] = []
        if let note = appointment.arrivalNote?.nonEmpty { out.append((L("Why they came"), note)) }
        if let grams = appointment.petWeight, grams > 0 {
            out.append((L("Weight on file"), (grams / 1000).formatted(.number.precision(.fractionLength(0...2)).locale(.app)) + " kg"))
        }
        if let room = appointment.room { out.append((L("Room"), room)) }
        return out
    }
}

/// A finished visit whose note still waits for a vet's signature (web `ToSignBanner`).
struct SchedToSignBanner: View {
    let count: Int
    let vetName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Glyph("pen-line", size: 20).foregroundStyle(Theme.inkStrong)
                .frame(width: 40, height: 40).background(Theme.surface, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(LF("The visit is finished and %@ still to sign", String(count))).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                Text(vetName.map { LF("Waiting for %@ to sign it.", $0) } ?? L("Waiting for a vet to sign it.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(Theme.lime, 12), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.lime, lineWidth: 2))
    }
}

// MARK: - The closing card

struct SchedClosingCheck: Identifiable {
    enum State { case ok, pending, warn, missing }
    let id: String
    let label: String
    let value: String
    let state: State
}

/// Under the note: what the visit still needs, then the button that closes it (web `VisitClosing`).
struct SchedVisitClosing: View {
    let title: String
    let checks: [SchedClosingCheck]
    let actionTitle: String
    let actionImage: String
    let action: () -> Void

    var body: some View {
        SectionCard(title, icon: "badge-check", accent: Theme.blue) {
            ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
                if index > 0 { RowDivider() }
                HStack(spacing: 12) {
                    Glyph(icon(check.state), size: 14)
                        .foregroundStyle(ink(check.state))
                        .frame(width: 24, height: 24)
                        .background(disc(check.state), in: Circle())
                    Text(check.label).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).frame(width: 96, alignment: .leading)
                    Text(check.value).font(Theme.text(14, weight: check.state == .ok || check.state == .pending ? .regular : .bold))
                        .foregroundStyle(check.state == .missing ? Theme.destructive : check.state == .warn ? Theme.inkStrong : Theme.inkSoft)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            RowDivider()
            PMButton(actionTitle, systemImage: actionImage, size: .modal, fullWidth: true, action: action)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    private func icon(_ state: SchedClosingCheck.State) -> String {
        switch state {
        case .ok: "check"
        case .missing, .warn: "triangle-alert"
        case .pending: "clock-3"
        }
    }

    private func ink(_ state: SchedClosingCheck.State) -> Color {
        switch state {
        case .ok: ProviderState.done.color
        case .missing: Theme.destructive
        case .warn: Theme.inkStrong
        case .pending: Theme.inkSoft
        }
    }

    private func disc(_ state: SchedClosingCheck.State) -> AnyShapeStyle {
        switch state {
        case .ok: AnyShapeStyle(Theme.wash(ProviderState.done.color, 18))
        case .missing: AnyShapeStyle(Theme.wash(Theme.destructive, 12))
        case .warn: AnyShapeStyle(Theme.wash(Theme.mango, 24))
        case .pending: AnyShapeStyle(Theme.surfaceMuted)
        }
    }
}

// MARK: - The note of the visit

/// Written during the visit: what was found (the chart), a summary for the family, a
/// private note for the staff. It saves itself as a draft; signing makes it part of
/// the chart the family sees. Two people editing at once can't overwrite each other.
struct SchedVisitNote: View {
    let appointment: SchedAppointment
    let records: [SchedRecord]
    let canWrite: Bool
    let canSign: Bool
    /// Whoever is here signs the note by finishing the visit.
    let signsOnFinish: Bool
    let noteRequired: Bool
    let onChanged: () async -> Void

    private enum SaveState { case idle, dirty, saving, saved, conflict, error }

    @State private var details = ""
    @State private var summary = ""
    @State private var internalNote = ""
    @State private var state: SaveState = .idle
    @State private var recordId: String?
    @State private var revision = 0
    @State private var savedAt: Date?
    @State private var edits = 0
    @State private var signing = false
    @State private var loadedFrom: String?

    private var noteType: String {
        let clinical = ["vet", "emergency", "pharmacy"]
        if let category = appointment.serviceCategory, !clinical.contains(category) { return "note" }
        return "vet_visit"
    }
    private var note: SchedRecord? {
        records.filter { $0.recordType == noteType }.sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }.first
    }
    private var signed: Bool { note?.isSigned == true }
    private var editable: Bool { canWrite && (!signed || canSign) }
    private var linked: Bool { appointment.clientHouseholdId != nil }
    private var empty: Bool { details.nonEmpty == nil && summary.nonEmpty == nil && internalNote.nonEmpty == nil }

    var body: some View {
        SectionCard(title: L("Visit note"), icon: "notebook-pen", accent: Theme.blue) {
            StatusChip(text: badge, state: signed ? .done : state == .error ? .problem : .closed)
        } content: {
          VStack(alignment: .leading, spacing: 12) {
            if canSign && !signed && canWrite {
                PMButton(L("Sign"), systemImage: "badge-check", size: .compact, isWorking: signing) { Task { await signNow() } }
                    .disabled(empty)
            }
            if state == .conflict {
                NoticeCard(tone: .warning, title: L("Someone else saved this note. Reload to see their version — your last changes here were not saved."), actionTitle: L("Reload")) {
                    Task {
                        recordId = nil
                        loadedFrom = nil
                        state = .idle
                        await onChanged()
                    }
                }
            }
            if signed && editable {
                Text(L("Signed — changes you make reach the family and are marked as a correction.")).font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
            }
            PMTextField(L("What you found and did"), text: binding($details), hint: L("History, exam, diagnosis, treatment. Part of the chart."), multiline: true)
                .disabled(!editable)
            PMTextField(linked ? L("For the family") : L("Summary to share"), text: binding($summary), hint: linked ? L("A short summary they will read in their app.") : LF("%@ isn’t on PawMiaw — send this by WhatsApp once the note is signed.", NameText.firstName(appointment.clientName)), multiline: true)
                .disabled(!editable)
            if !linked && signed, let text = summary.nonEmpty, let url = schedWhatsAppURL(appointment.clientPhone, message: LF("Hi %@, here is the summary of %@’s visit:", NameText.firstName(appointment.clientName), appointment.petName) + "\n\n" + text) {
                Link(destination: url) { HStack(spacing: 6) { Glyph("message-circle", size: 16); Text("WhatsApp") } }.buttonStyle(.pm(.outline, size: .compact))
            }
            PMTextField(L("Staff only"), text: binding($internalNote), hint: L("Never shown to the family."), multiline: true)
                .disabled(!editable)
            if canWrite && !signed {
                HStack(spacing: 6) {
                    Glyph(state == .saving ? "refresh-cw" : state == .error ? "triangle-alert" : "cloud", size: 14)
                    Text(footer)
                }
                .font(Theme.text(12, weight: .semibold)).foregroundStyle(state == .error ? Theme.destructive : Theme.inkSoft)
            }
          }
          .padding(16)
        }
        .onAppear { adopt() }
        .onChange(of: note?.revision) { _, _ in adopt() }
        .task(id: edits) {
            guard state == .dirty else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled, state == .dirty else { return }
            await save()
        }
    }

    private func binding(_ field: Binding<String>) -> Binding<String> {
        Binding(get: { field.wrappedValue }, set: { value in
            guard value != field.wrappedValue else { return }
            field.wrappedValue = value
            state = .dirty
            edits += 1
        })
    }

    /// Someone else's save (or a refresh) replaces the text only when nothing here is unsaved.
    private func adopt() {
        guard let note else { return }
        guard state != .dirty && state != .saving else { return }
        if note.id == recordId && (note.revision ?? 0) <= revision && loadedFrom != nil { return }
        recordId = note.id
        revision = note.revision ?? 0
        details = note.details ?? ""
        summary = note.summary ?? ""
        internalNote = note.internalNote ?? ""
        loadedFrom = note.id
    }

    private var badge: String {
        switch state {
        case .saving: return L("Saving…")
        case .dirty: return L("Unsaved")
        case .error: return L("Not saved")
        default:
            if signed { return LF("Signed by %@ · %@", note?.signedBy?.name ?? "—", DateText.time(note?.signedAt)) }
            return note != nil || state == .saved ? L("Draft saved") : L("Not started")
        }
    }

    private var footer: String {
        switch state {
        case .saving: return L("Saving…")
        case .dirty: return L("Saving in a moment…")
        case .error: return L("Not saved. It tries again as you type.")
        default:
            guard note != nil || state == .saved else { return L("It saves on its own as you write: there is no save button.") }
            let time = DateText.time(savedAt ?? DateText.parse(note?.updatedAt) ?? Date())
            return "\(LF("Saved automatically %@", time)) · \(signsOnFinish || canSign ? L("A draft until the visit is finished: finishing signs it.") : L("A draft until a vet signs it; the family sees it after."))"
        }
    }

    private func save() async {
        state = .saving
        do {
            if let recordId {
                let saved: SchedRecord = try await SchedAPI.send("PATCH", "/provider-records/\(recordId)", body: [
                    "details": details.nonEmpty, "summary": summary.nonEmpty, "internalNote": internalNote.nonEmpty, "expectedRevision": revision,
                ])
                revision = saved.revision ?? revision + 1
            } else {
                let created: SchedRecord = try await SchedAPI.send("POST", "/provider-records", body: [
                    "appointmentId": appointment.id,
                    "providerClientId": appointment.providerClientId,
                    "providerClientPetId": appointment.providerClientPetId,
                    "recordType": noteType,
                    "title": appointment.serviceLabel,
                    "details": details.nonEmpty,
                    "summary": summary.nonEmpty,
                    "internalNote": internalNote.nonEmpty,
                    "eventAt": appointment.startsAt,
                    "draft": true,
                ])
                recordId = created.id
                revision = created.revision ?? 0
                loadedFrom = created.id
            }
            if state == .saving { state = .saved }
            savedAt = Date()
            await onChanged()
        } catch {
            if (error as? SchedFailure)?.code == "record_changed" { state = .conflict; return }
            state = .error
            schedToast(error)
        }
    }

    private func signNow() async {
        if state == .dirty || recordId == nil && !empty { await save() }
        guard let recordId else {
            Toast.error(L("Write the note before signing it."))
            return
        }
        signing = true
        defer { signing = false }
        do {
            try await API.send("POST", "/provider-records/\(recordId)/sign", body: [:])
            Toast.show(linked ? L("Signed. The family can see it now.") : L("Signed. It is part of the chart now."))
            announceDataChanged()
            await onChanged()
        } catch { Toast.error(error) }
    }
}

/// "Also recorded in this visit": each opens its record.
struct SchedVisitRecords: View {
    let records: [SchedRecord]
    let canSign: Bool
    let onChanged: () async -> Void
    /// "Add a record": a vaccine, a diagnosis, a lab result… into this visit (Records' sheet).
    var onAdd: (() -> Void)? = nil
    @State private var signing: String?

    var body: some View {
        SectionCard(title: L("Also recorded in this visit"), icon: "files", accent: Theme.blue) {
            if let onAdd { PMButton(L("Add a record"), systemImage: "plus", variant: .outline, size: .header, action: onAdd) }
        } content: {
            if records.isEmpty {
                Text(L("Nothing else yet.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(16)
            }
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                if index > 0 { RowDivider() }
                HStack(spacing: 10) {
                    NavigationLink(value: ProviderRoute.record(record.id)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.title ?? L("Record")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(2)
                                Text([record.isDraft ? L("Draft") : L("Signed"), DateText.dayTime(record.eventAt ?? record.createdAt)].joined(separator: " · "))
                                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if record.isDraft && canSign {
                        PMButton(L("Sign"), variant: .outline, size: .compact, isWorking: signing == record.id) { sign(record) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }

    private func sign(_ record: SchedRecord) {
        signing = record.id
        Task {
            defer { signing = nil }
            do {
                try await API.send("POST", "/provider-records/\(record.id)/sign", body: [:])
                Toast.show(L("Signed."))
                announceDataChanged()
                await onChanged()
            } catch { Toast.error(error) }
        }
    }
}

// MARK: - The bill

/// "Cuenta de la visita": where it stands, its lines and what has been paid; the bill
/// itself (charging, prices, payments) opens in Cuentas.
struct SchedVisitBillCard: View {
    let appointment: SchedAppointment
    let invoice: SchedInvoice?
    let stage: SchedBillStage
    let collectAmount: Int
    let canCollect: Bool

    var body: some View {
        SectionCard(title: L("The visit’s bill"), icon: "receipt", accent: Theme.blue) {
            StatusChip(text: stage.label, state: stage.state)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if let invoice {
                    let currency = invoice.currency
                    if let number = invoice.invoiceNumber { Text(number).font(Theme.captionFont).foregroundStyle(Theme.inkSoft) }
                    let lines = invoice.lineItems ?? []
                    if lines.isEmpty {
                        Text(L("No charges on the bill yet.")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                    }
                    ForEach(lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.label ?? "—").font(Theme.text(15, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                                if let quantity = line.quantity, quantity != 1 {
                                    Text("\(quantity.formatted()) × \(Money.short(line.unitAmount))").font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
                                }
                            }
                            Spacer(minLength: 8)
                            if line.needsPrice {
                                StatusChip(text: L("Needs a price"), state: .waiting)
                            } else {
                                Text(Money.format(line.lineTotalAmount, currency: currency)).font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            }
                        }
                    }
                    StitchedDivider()
                    if (invoice.discountAmount ?? 0) > 0 { FactRow(label: L("Discount"), value: "−" + Money.format(invoice.discountAmount, currency: currency)) }
                    if (invoice.taxAmount ?? 0) > 0 { FactRow(label: L("Tax"), value: Money.format(invoice.taxAmount, currency: currency)) }
                    FactRow(label: L("Total"), value: Money.format(invoice.totalAmount, currency: currency))
                    if (invoice.amountPaid ?? 0) > 0 { FactRow(label: L("Paid"), value: Money.format(invoice.amountPaid, currency: currency)) }
                    if invoice.status != "draft" { FactRow(label: L("Balance"), value: Money.format(invoice.balanceDueAmount, currency: currency)) }
                    if stage == .forgiven {
                        // "Perdonar saldo" (docs/family-money.md §1): what was left will not be collected.
                        VStack(alignment: .leading, spacing: 2) {
                            Text((invoice.forgivenAmount ?? 0) > 0 ? LF("Balance forgiven: %@", Money.format(invoice.forgivenAmount, currency: currency)) : L("Balance forgiven"))
                                .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            Text([invoice.forgivenBy?.name?.nonEmpty, invoice.forgivenReason?.nonEmpty].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? L("Nothing more to charge."))
                                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    HStack(spacing: 8) {
                        if canCollect {
                            NavigationLink(value: ProviderRoute.invoice(invoice.id)) {
                                HStack(spacing: 6) { Glyph("hand-coins", size: 16); Text(LF("Collect %@", Money.format(collectAmount, currency: currency))) }
                            }
                            .buttonStyle(.pm(.primary, size: .compact))
                        }
                        NavigationLink(value: ProviderRoute.invoice(invoice.id)) {
                            HStack(spacing: 6) { Glyph("receipt-text", size: 16); Text(L("Open the bill")) }
                        }
                        .buttonStyle(.pm(.outline, size: .compact))
                    }
                } else {
                    Text(stage == .notStarted ? L("The bill opens when the visit starts.") : stage == .noCharge ? L("Finished with no charge.") : L("No bill yet")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Booked together

/// The family's pets booked together, or the session it has a place in (web `VisitGroupCard`):
/// a card with a blue eyebrow; a session opens whole, each of the family's pets opens its visit.
struct SchedVisitGroupCard: View {
    let appointment: SchedAppointment

    var body: some View {
        if let group = appointment.group {
            let others = (group.pets ?? []).filter { $0.appointmentId != appointment.id }
            if group.isSession || !others.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text((group.isSession ? LF("A place in %@", group.serviceLabel ?? L("Group session")) : L("Booked with")).uppercased())
                        .font(Theme.text(12, weight: .bold)).tracking(1.68).foregroundStyle(Theme.blue)
                    if group.isSession {
                        NavigationLink { SvcSessionScreen(sessionId: group.id) } label: {
                            HStack(spacing: 12) {
                                PetStack(pets: group.stayingPets.map { ($0.name ?? "", $0.species, $0.photoUrl) }, size: 32, max: 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.placesLabel).font(.brandHeading(18)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                                    if let capacity = group.capacity {
                                        Text(LP(max(0, capacity - (group.size ?? group.stayingPets.count)), "1 place left", "%d places left")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                                    }
                                }
                                Spacer(minLength: 8)
                                HStack(spacing: 2) { Text(L("Open the session")); Glyph("chevron-right", size: 16) }
                                    .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Theme.wash(Theme.aqua, 14), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                    } else {
                        Text(L("Moves, arrives, starts and finishes with them; one bill for all.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.top, 4)
                        VStack(spacing: 6) {
                            ForEach(others, id: \.appointmentId) { pet in
                                let gone = SchedStatus.gone.contains(pet.status ?? "")
                                NavigationLink(value: ProviderRoute.appointment(pet.appointmentId)) {
                                    HStack(spacing: 12) {
                                        PetAvatar(name: pet.name, species: pet.species, photoURL: pet.photoUrl, size: 32)
                                        Text(pet.name ?? "").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).strikethrough(gone).lineLimit(1)
                                        Spacer(minLength: 8)
                                        if gone {
                                            Text(pet.status == "no_show" ? L("Didn’t come") : L("Cancelled")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                                        }
                                        Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                                    .opacity(gone ? 0.6 : 1)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 12)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                .cardShadow()
            }
        }
    }
}

// MARK: - A groom's stage

private struct SchedGroomResult: Decodable {
    let groomReadyNotifiedAt: String?
    let groomReadyChannel: String?
    let link: String?
}

struct SchedGroomSettings: Decodable { let simpleStages: Bool? }

/// A groom that is here: where it is (Esperando · En baño · Corte y secado · Listo para recoger),
/// moved in one tap, and telling the family once it is ready. Handing the pet over is finishing.
struct SchedGroomStageBar: View {
    let appointment: SchedAppointment
    let simple: Bool
    var onGate: (SchedGatePrompt) -> Void = { _ in }

    @Environment(\.openURL) private var openURL
    @State private var busy = false
    @State private var sent: (at: String, channel: String?)?

    private var stage: String { appointment.groomStage ?? "waiting" }
    private var current: String { simple && stage == "styling" ? "bath" : stage }
    private var stages: [String] { simple ? ["waiting", "bath", "ready"] : ["waiting", "bath", "styling", "ready"] }

    private func label(_ stage: String) -> String { Self.label(stage, simple: simple) }

    /// A stage's word (web `groomStageLabel`).
    static func label(_ stage: String, simple: Bool) -> String {
        switch stage {
        case "waiting": L("Waiting")
        case "bath": simple ? L("In progress") : L("Bath")
        case "styling": L("Cut & dry")
        case "ready": L("Ready for pickup")
        default: stage
        }
    }

    var body: some View {
        // The web's stage switch (a raised white segment on the muted track), then, once ready,
        // "Avisar que está listo" by WhatsApp or in PawMiaw with when it was sent.
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                Segmented(options: stages.map { .init($0, label($0)) },
                          selection: Binding(get: { current }, set: { next in
                              // A started groom doesn't go back to waiting: the bath is its start.
                              guard !busy, !(next == "waiting" && appointment.status == "in_progress") else { return }
                              move(next)
                          }),
                          look: .raised, label: L("Grooming stage"))
                    .opacity(busy ? 0.6 : 1)
            }
            if stage == "ready" {
                FlowLayout(spacing: 8) {
                    if appointment.clientPhone != nil || appointment.clientHouseholdId != nil {
                        Text(L("Tell them it’s ready")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            .frame(minHeight: 40)
                    }
                    if appointment.clientPhone != nil {
                        PMButton("WhatsApp", systemImage: "message-circle", variant: .outline, size: .compact, isWorking: busy) { notify("whatsapp") }
                    }
                    if appointment.clientHouseholdId != nil {
                        PMButton("PawMiaw", systemImage: "smartphone", variant: .outline, size: .compact, isWorking: busy) { notify("app") }
                    }
                    if let at = appointment.groomReadyNotifiedAtValue ?? sent?.at {
                        // Already told: so nobody messages the family twice.
                        let channel = sent?.channel ?? appointment.groomReadyChannel
                        Chip(text: channel == "whatsapp" ? LF("WhatsApp opened %@", DateText.time(at)) : LF("Notified %@ · %@", DateText.time(at), "PawMiaw"), tone: .good, icon: "check-check")
                            .frame(minHeight: 40)
                    }
                }
            }
        }
    }

    private func move(_ next: String) {
        guard next != current else { return }
        let id = appointment.id, pet = appointment.petName, nextLabel = label(next)
        func set() async throws {
            let _: SchedGroomResult = try await SchedAPI.send("PATCH", "/provider-appointments/\(id)/groom-stage", body: ["stage": next])
            announceDataChanged()
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await set()
                Toast.show("\(pet) · \(nextLabel)")
            } catch {
                // A stage picked while the pet waits starts the visit: a missing consent asks first.
                if let prompt = SchedGatePrompt.from(error, visit: appointment, verb: "start", attempt: { extra in
                    try await SchedVisitOps.start(id, extra: extra)
                    if next != "bath" { try await set() }
                }, onDone: { Toast.show("\(pet) · \(nextLabel)") }) {
                    onGate(prompt)
                } else {
                    schedToast(error)
                }
            }
        }
    }

    private func notify(_ channel: String) {
        busy = true
        let id = appointment.id
        let locale = LocalizationManager.shared.currentLanguage.rawValue
        Task {
            defer { busy = false }
            do {
                let result: SchedGroomResult = try await SchedAPI.send("POST", "/provider-appointments/\(id)/groom-ready", body: ["channel": channel, "locale": locale])
                if let at = result.groomReadyNotifiedAt { sent = (at, result.groomReadyChannel) }
                if channel == "whatsapp", let link = result.link.flatMap(URL.init(string:)) {
                    openURL(link)
                    Toast.show(L("WhatsApp is open with the message."))
                } else {
                    Toast.show(L("The family was told in PawMiaw."))
                }
                announceDataChanged()
            } catch { schedToast(error) }
        }
    }
}
