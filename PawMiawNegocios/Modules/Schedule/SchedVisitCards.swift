//
//  SchedVisitCards.swift
//  PawMiawNegocios
//
//  The visit page's side cards (web provider.appointments.$appointmentId.tsx):
//  the triage (hospital/visit-triage-card.tsx), the chart in short with "+"
//  to record into the visit (visits/visit-chart.tsx), the groom, walk or
//  training report that saves itself (care/visit-report.tsx), the notes to
//  the family during the visit (visit-updates-card.tsx), the prescriptions
//  written at it (prescriptions/prescriptions-card.tsx), the history of
//  changes (audit-history-panel.tsx) and "Add to calendar".
//

import SwiftUI
import PhotosUI

// MARK: - Triage

/// Priority, why, the quick vitals at arrival, after hours and the emergency deposit still owed.
/// Editable by whoever checks visits in; "Hospitalize" one tap away when it is urgent or critical.
struct SchedTriageCard: View {
    let appointmentId: String
    let canEdit: Bool
    var onHospitalize: ((SchedTriage?) -> Void)? = nil
    /// The pet's open hospitalization (waiting or in): the card opens it instead.
    var hospitalization: SchedHospStay? = nil
    var onTakeDeposit: ((SchedDepositDue) -> Void)? = nil

    @State private var triage: SchedTriage?
    @State private var editing = false

    var body: some View {
        Group {
            if let triage, !(triage.isEmpty && !canEdit && onHospitalize == nil && hospitalization == nil) {
                card(triage)
            }
        }
        .reloadsOnScope { await load() }
        .sheet(isPresented: $editing) {
            if let triage { SchedTriageSheet(appointmentId: appointmentId, triage: triage) { self.triage = $0 } }
        }
    }

    private func card(_ triage: SchedTriage) -> some View {
        SectionCard(title: L("Triage"), icon: "siren", accent: Theme.destructive) {
            if canEdit && !triage.isEmpty {
                PMButton(L("Change"), systemImage: "pencil", variant: .outline, size: .header) { editing = true }
            }
        } content: {
          VStack(alignment: .leading, spacing: 12) {
            if triage.isEmpty {
                Text(L("Not triaged")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                if canEdit {
                    PMButton(L("Triage"), systemImage: "siren", variant: .outline, size: .compact, fullWidth: true) { editing = true }
                }
            } else {
                if triage.triagePriority != nil || triage.afterHours == true {
                    FlowLayout(spacing: 6) {
                        if let priority = triage.triagePriority { HospTriageBadge(priority: priority) }
                        if triage.afterHours == true { Chip(text: L("After hours"), icon: "moon-star") }
                    }
                }
                if let reason = triage.triageReason?.nonEmpty {
                    Text(reason).font(Theme.text(15, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                }
                if let latest = triage.vitals?.first {
                    let values = vitals(latest)
                    if !values.isEmpty {
                        Text("\(L("Quick vitals")) · \(DateText.time(latest.recordedAt))").font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
                        FlowLayout(spacing: 6) { ForEach(values, id: \.self) { Chip(text: $0, tone: .info) } }
                    }
                }
                if let due = triage.depositDue, due.owed > 0 {
                    NoticeCard(tone: .warning, title: LF("Emergency deposit owed: %@", Money.format(due.owed, currency: due.currency)),
                               actionTitle: onTakeDeposit != nil ? L("Take the deposit") : nil, action: onTakeDeposit.map { take in { take(due) } })
                }
                if let onHospitalize, hospitalization == nil, triage.triagePriority == "critical" || triage.triagePriority == "urgent" {
                    PMButton(L("Hospitalize"), systemImage: "bed-double", variant: .outline, size: .compact, fullWidth: true) { onHospitalize(triage) }
                }
            }
            if let hospitalization {
                NavigationLink(value: ProviderRoute.hospitalization(hospitalization.id)) {
                    HStack(spacing: 10) {
                        Glyph("bed-double", size: 16).foregroundStyle(Theme.blue)
                        Text(hospitalization.status == "pending" ? L("Waiting for admission to the hospital") : L("In the hospital"))
                            .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        Spacer(minLength: 8)
                        Text(L("Open")).font(Theme.text(13, weight: .bold)).foregroundStyle(Theme.blue)
                        Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
          }
          .padding(16)
        }
    }

    private func vitals(_ v: SchedVitals) -> [String] {
        func n(_ value: Double?) -> String? { value.map { $0.formatted(.number.locale(.app)) } }
        return [
            n(v.temperatureC).map { "\($0) °C" },
            n(v.heartRate).map { LF("HR %@", $0) },
            n(v.respiratoryRate).map { LF("RR %@", $0) },
            n(v.painScore).map { LF("Pain %@", $0) },
            v.weightGrams.map { "\(($0 / 1000).formatted(.number.locale(.app))) kg" },
            v.mucousMembranes.map { HospWords.mucous($0) },
            n(v.crtSeconds).map { LF("CRT %@ s", $0) },
        ].compactMap { $0 }
    }

    private func load() async {
        if let loaded: SchedTriage = try? await API.get("/provider-visits/\(appointmentId)/triage") { triage = loaded }
    }
}

/// Critical, urgent or stable: the waiting room goes by it. A critical patient never waits for a deposit.
private struct SchedTriageSheet: View {
    let appointmentId: String
    let triage: SchedTriage
    let onSaved: (SchedTriage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = SchedTriageDraft(on: true)
    @State private var invalid: SchedTriageDraft.Missing?
    @State private var prepared = false
    @State private var working = false

    private var vitalInvalid: HospVitalsDraft.Field? {
        if case .vital(let field) = invalid { return field }
        return nil
    }

    var body: some View {
        ProviderModal(title: L("Triage"), subtitle: L("Critical, urgent or stable: the waiting room goes by it. A critical patient never waits for a deposit."),
                      systemImage: "siren", accent: .pink, isDirty: prepared && (draft.priority != triage.triagePriority || draft.reason != (triage.triageReason ?? "") || draft.vitals != HospVitalsDraft()),
                      primaryTitle: L("Save triage"), isWorking: working,
                      secondaryActions: triage.triagePriority != nil ? [ModalAction(L("Clear the triage"), variant: .ghost, isWorking: working) { save(clear: true) }] : [],
                      primaryIcon: "save") {
            save(clear: false)
        } content: {
            // The web's triage sheet: the priority, why (required), then the quick vitals, always open.
            VStack(alignment: .leading, spacing: 8) {
                PillPicker(options: HospWords.priorities.map { ($0, HospWords.triage($0)) }, choice: Binding(get: { draft.priority }, set: { draft.priority = $0; draft.on = true; invalid = nil }))
                if invalid == .priority { Text(SchedTriageDraft.missingText(.priority)).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.destructive) }
            }
            .id("priority")
            VStack(alignment: .leading, spacing: 8) {
                PMTextField(L("Why"), text: Binding(get: { draft.reason }, set: { draft.reason = $0; invalid = nil }), prompt: L("Why they came, e.g. Hit by a car, breathing fast"), required: true)
                if invalid == .reason { Text(SchedTriageDraft.missingText(.reason)).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.destructive) }
            }
            ModalSection(title: L("Quick vitals"), subtitle: L("A new reading; earlier ones stay on the chart.")) {
                HospVitalsFields(draft: $draft.vitals, invalid: vitalInvalid)
                    .onChange(of: draft.vitals) { _, _ in invalid = nil }
            }
        }
        .onAppear {
            guard !prepared else { return }
            draft.priority = triage.triagePriority
            draft.reason = triage.triageReason ?? ""
            prepared = true
        }
    }

    private func save(clear: Bool) {
        var body: [String: Any?] = ["priority": nil, "reason": nil, "vitals": nil]
        if !clear {
            let parsed = draft.parsed()
            if let missing = parsed.missing {
                invalid = missing
                Toast.error(SchedTriageDraft.missingText(missing))
                return
            }
            body = parsed.value ?? body
        }
        let payload = body
        working = true
        Task {
            defer { working = false }
            do {
                let saved: SchedTriage = try await API.put("/provider-visits/\(appointmentId)/triage", body: payload)
                onSaved(saved)
                Toast.show(clear ? L("Triage cleared.") : L("Triage saved. The waiting room goes by it."))
                announceDataChanged()
                dismiss()
            } catch {
                Toast.error(error, fallback: L("Could not save the triage."))
            }
        }
    }
}

// MARK: - The chart in short

private struct SchedAllergyLine: Identifiable {
    let id: String
    let title: String
    let detail: String?
    let family: Bool
}

/// What the vet needs in front of them: allergies first, then current problems and medicines,
/// vaccines, the last visits and the weight; "+" records into this visit.
struct SchedVisitChart: View {
    let appointmentId: String
    let petId: String
    let petWeightGrams: Double?
    let canLogWeight: Bool
    /// Record into this visit: "allergy", "diagnosis", "medication", "vaccination".
    var onAdd: ((String) -> Void)? = nil

    @State private var chart: SchedChartSummary?
    @State private var failed = false
    @State private var weight = ""
    @State private var saving = false

    var body: some View {
        Group {
            if let chart { card(chart) } else if !failed { SectionCard(L("Chart"), icon: "file-text", accent: Theme.blue) { LoadingState() } }
        }
        .reloadsOnScope { await load() }
    }

    private func card(_ chart: SchedChartSummary) -> some View {
        let sections = chart.sections
        let familyAllergies = (sections?.ownerRecords ?? []).filter { $0.recordType == "allergy" }
        let clinic: [SchedAllergyLine] = (sections?.allergies ?? []).map { r in
            SchedAllergyLine(id: r.id, title: r.title ?? L("Allergy"), detail: [severity(r.text("severity")), r.summary ?? r.text("reaction")].compactMap { $0?.nonEmpty }.joined(separator: " · ").nonEmpty, family: false)
        }
        let allergies = clinic + familyAllergies.map { SchedAllergyLine(id: $0.id, title: $0.title ?? L("Allergy"), detail: $0.summary, family: true) }
        let today = SchedDay.today
        let vaccines = Array((sections?.vaccines ?? []).prefix(4))
        let overdue = vaccines.contains { nextDose($0).map { $0 < today } ?? false }
        let visits = Array((sections?.recentRecords ?? []).filter { $0.appointmentId != appointmentId && ["vet_visit", "diagnosis", "surgery"].contains($0.recordType ?? "") }.prefix(3))
        return SectionCard(title: L("Chart"), icon: "file-text", accent: Theme.blue) {
            NavigationLink(value: ProviderRoute.patientChart(petId: petId)) {
                HStack(spacing: 4) { Text(L("Full chart")); Glyph("arrow-right", size: 14) }
                    .font(Theme.text(13, weight: .bold)).foregroundStyle(Theme.blue)
            }
        } content: {
            // Allergies never fold away: red and listed when there are any.
            HStack(alignment: .top, spacing: 8) {
                Glyph("triangle-alert", size: 16).foregroundStyle(allergies.isEmpty ? Theme.inkSoft : Theme.destructive).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Allergies")).font(Theme.text(15, weight: .bold)).foregroundStyle(allergies.isEmpty ? Theme.inkStrong : Theme.destructive)
                    if allergies.isEmpty {
                        Text(L("None on record.")).font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
                    }
                    ForEach(allergies, id: \.id) { allergy in
                        Text("\(allergy.title)\(allergy.detail.map { " · \($0)" } ?? "")\(allergy.family ? " (\(L("from the family")))" : "")")
                            .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.destructive)
                    }
                }
                Spacer(minLength: 0)
                addButton("allergy", L("Add an allergy"))
            }
            .padding(14)
            .background(allergies.isEmpty ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.wash(Theme.destructive, 12)))
            VStack(alignment: .leading, spacing: 0) {
                let problems = sections?.currentProblems ?? []
                if !problems.isEmpty || onAdd != nil {
                    row("heart-pulse", L("Current problems"), count: problems.count, add: ("diagnosis", L("Add a diagnosis"))) {
                        ForEach(problems.prefix(5)) { Text($0.title ?? "—").font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong) }
                    }
                }
                let medicines = sections?.currentMedications ?? []
                row("pill", L("Current medicines"), count: medicines.count, add: ("medication", L("Add a medicine"))) {
                    ForEach(medicines.prefix(6)) { record in
                        Text("\(record.title ?? "—")\(record.text("dosage").map { " · \($0)" } ?? "")").font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    }
                }
                row("syringe", L("Vaccines"), count: (sections?.vaccines ?? []).count, alert: overdue, add: ("vaccination", L("Add a vaccine"))) {
                    ForEach(vaccines) { record in
                        let next = nextDose(record)
                        let late = next.map { $0 < today } ?? false
                        HStack {
                            Text(record.title ?? "—").font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            Spacer()
                            Text(next.map { late ? LF("due %@", SchedDay.shortLabel($0)) : LF("next %@", SchedDay.shortLabel($0)) } ?? DateText.date(record.eventAt))
                                .font(Theme.captionFont).foregroundStyle(late ? Theme.destructive : Theme.inkSoft)
                        }
                    }
                }
                row("stethoscope", L("Last visits"), count: visits.count, summary: visits.isEmpty ? L("First visit here.") : nil) {
                    ForEach(visits) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(record.title ?? "—") · \(DateText.date(record.eventAt))").font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                            if let summary = record.summary?.nonEmpty { Text(summary).font(Theme.captionFont).foregroundStyle(Theme.inkSoft).lineLimit(2) }
                        }
                    }
                }
                weightRow(latest: chart.highlights?.latestWeight)
                if chart.sharedHistoryAccess?.canView == false {
                    RowDivider()
                    Text(L("The family’s own records are not shared with you.")).font(Theme.captionFont).foregroundStyle(Theme.inkSoft).padding(14)
                }
            }
        }
    }

    private func severity(_ value: String?) -> String? {
        switch value {
        case "severe": L("Severe")
        case "moderate": L("Moderate")
        case "mild": L("Mild")
        default: nil
        }
    }

    private func nextDose(_ record: SchedChartRecord) -> String? {
        record.followUpAt.map { String($0.prefix(10)) } ?? record.text("next_due_date").map { String($0.prefix(10)) }
    }

    @ViewBuilder private func addButton(_ type: String, _ label: String) -> some View {
        if let onAdd { IconCircleButton(systemImage: "plus", label: label) { onAdd(type) } }
    }

    private func row<Items: View>(_ icon: String, _ title: String, count: Int, alert: Bool = false, summary: String? = nil, add: (String, String)? = nil, @ViewBuilder items: @escaping () -> Items) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RowDivider()
            HStack(spacing: 8) {
                if count > 0 {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 6) { items() }.padding(.top, 6)
                    } label: {
                        rowLabel(icon, title, count: count, alert: alert, summary: summary)
                    }
                    .tint(Theme.inkSoft)
                } else {
                    rowLabel(icon, title, count: count, alert: alert, summary: summary)
                }
                if let add { addButton(add.0, add.1) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    private func rowLabel(_ icon: String, _ title: String, count: Int, alert: Bool, summary: String?) -> some View {
        HStack(spacing: 8) {
            Glyph(icon, size: 14).foregroundStyle(alert ? Theme.destructive : Theme.inkSoft)
            Text(title).font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.inkStrong)
            Spacer(minLength: 4)
            Text(summary ?? (count > 0 ? String(count) : "—")).font(Theme.text(13, weight: .bold)).foregroundStyle(alert ? Theme.destructive : count > 0 ? Theme.inkStrong : Theme.inkSoft)
        }
    }

    private func weightRow(latest: SchedChartRecord?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RowDivider()
            HStack(spacing: 8) {
                Glyph("scale", size: 14).foregroundStyle(Theme.inkSoft)
                Text(L("Weight")).font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.inkStrong)
                Spacer()
                if let grams = petWeightGrams, grams > 0 {
                    Text("\((grams / 1000).formatted(.number.precision(.fractionLength(0...2)).locale(.app))) kg\(latest.map { " · \(DateText.date($0.eventAt))" } ?? "")")
                        .font(Theme.text(13, weight: .bold)).foregroundStyle(Theme.inkStrong)
                } else {
                    Text(L("Not weighed yet.")).font(Theme.text(13, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.horizontal, 14)
            if canLogWeight {
                HStack(spacing: 8) {
                    TextField(L("Today, in kg"), text: $weight).font(Theme.bodyFont).keyboardType(.decimalPad).fieldChrome()
                    PMButton(L("Save"), variant: .outline, size: .compact, isWorking: saving) { saveWeight() }
                        .disabled(weight.nonEmpty == nil)
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.bottom, 14)
    }

    private func saveWeight() {
        let kg = Double(weight.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        guard let kg, kg > 0, kg <= 200 else {
            Toast.error(L("Enter the weight in kg, like 12.4"))
            return
        }
        saving = true
        Task {
            defer { saving = false }
            do {
                let _: EmptyResponse = try await API.post("/provider-appointments/\(appointmentId)/weight", body: [
                    "weightGrams": Int((kg * 1000).rounded()), "recordedAt": DateText.iso(Date()), "isSharedWithOwner": true,
                ])
                weight = ""
                Toast.show(L("Weight saved."))
                announceDataChanged()
            } catch { Toast.error(error) }
        }
    }

    private func load() async {
        do {
            chart = try await API.get("/provider-client-pets/\(petId)/chart-summary")
            failed = false
        } catch is CancellationError {
        } catch {
            failed = chart == nil
        }
    }
}

// MARK: - The report

/// What the groomer, walker or trainer tells the family about the visit. It saves itself; the family
/// sees it when the visit ends. Its missing fields go to the page's closing card.
struct SchedVisitReportCard: View {
    let appointment: SchedAppointment
    let canWrite: Bool
    var onMissing: ([String]) -> Void = { _ in }

    private enum SaveState { case idle, dirty, saving, saved, error }

    @State private var report: SvcReport?
    @State private var state: SaveState = .idle
    @State private var edits = 0
    @State private var prefilled = false
    @State private var adopted: String?

    private var arrived: Bool { ["in_progress", "completed"].contains(appointment.status) }
    private var editable: Bool { canWrite && arrived }
    private var kind: String { appointment.reportKind ?? "groom" }

    var body: some View {
        SectionCard(title: SvcReportText.title(kind, category: appointment.serviceCategory), icon: "clipboard-check", accent: Theme.blue) {
            if let badge { Text(badge).font(Theme.text(12, weight: .bold)).foregroundStyle(state == .error ? Theme.destructive : Theme.inkSoft) }
        } content: {
          VStack(alignment: .leading, spacing: 12) {
            if !arrived {
                Text(L("The report opens when the visit starts.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            if prefilled && appointment.report == nil {
                HStack(spacing: 6) { Glyph("sparkles", size: 14); Text(L("Filled in from what the owner asked for")) }
                    .font(Theme.captionFont).foregroundStyle(Theme.inkStrong)
                    .padding(8).background(Theme.wash(Theme.aqua, 22), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            }
            if let report {
                SvcReportForm(report: Binding(get: { report }, set: { change($0) }), category: appointment.serviceCategory, appointmentId: appointment.id, editable: editable)
            }
            Text(appointment.clientHouseholdId != nil ? L("The family sees this when the visit ends.") : LF("%@ isn’t on PawMiaw — you can send the report by WhatsApp when the visit ends.", NameText.firstName(appointment.clientName)))
                .font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
          }
          .padding(16)
        }
        .onAppear { adopt() }
        .onChange(of: appointment.reportUpdatedAt) { _, _ in adopt() }
        .task(id: edits) {
            guard state == .dirty else { return }
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled, state == .dirty else { return }
            await save()
        }
        .task(id: appointment.id) { await prefill() }
    }

    private var badge: String? {
        switch state {
        case .saving: L("Saving…")
        case .saved: L("Saved")
        case .dirty: L("Unsaved")
        case .error: L("Not saved")
        case .idle: appointment.report != nil ? L("For the family") : nil
        }
    }

    /// A report saved elsewhere replaces ours while nothing here is unsaved.
    private func adopt() {
        guard state == .idle || state == .saved else { return }
        let key = "\(appointment.id)|\(appointment.reportUpdatedAt ?? "")"
        guard adopted != key || report == nil else { return }
        adopted = key
        report = appointment.report ?? SvcReport(kind: kind)
        onMissing(SvcReportText.missing(appointment.serviceCategory, report))
    }

    /// No report yet: start from what the owner asked for (saved only once someone changes it).
    private func prefill() async {
        guard kind == "groom", appointment.report == nil, editable, !prefilled else { return }
        let view: SchedGroomView? = try? await API.get("/provider-appointments/\(appointment.id)/groom-request")
        guard var start = view?.prefill, state == .idle, appointment.report == nil else { return }
        start.kind = "groom"
        report = start
        prefilled = true
        onMissing(SvcReportText.missing(appointment.serviceCategory, start))
    }

    private func change(_ next: SvcReport) {
        guard next != report else { return }
        report = next
        state = .dirty
        edits += 1
        onMissing(SvcReportText.missing(appointment.serviceCategory, next))
    }

    private func save() async {
        guard let report else { return }
        state = .saving
        do {
            let _: SvcIgnored = try await API.put("/provider-appointments/\(appointment.id)/report", json: report)
            if state == .saving { state = .saved }
        } catch {
            state = .error
            Toast.error(error)
        }
    }
}

// MARK: - Notes to the family

/// A photo, a mood, a line from the visit: on the family's Home under "Right now", with a notification.
struct SchedVisitUpdatesCard: View {
    let appointment: SchedAppointment
    let canSend: Bool

    @State private var updates: [SchedVisitUpdate] = []
    @State private var composing = false

    private var linked: Bool { appointment.clientHouseholdId != nil }
    private var happened: Bool { !appointment.isGone }

    var body: some View {
        Group {
            if linked || (canSend && happened) || !updates.isEmpty {
                SectionCard(title: L("Notes to the family"), subtitle: linked ? L("Send the family a note from this visit — a photo, a mood, a line. It shows on their Home in PawMiaw, with a notification.") : nil, icon: "message-square-heart", accent: Theme.pink) {
                    EmptyView()
                } content: {
                  VStack(alignment: .leading, spacing: 12) {
                    if linked && canSend && happened {
                        PMButton(L("Send an update"), systemImage: "send", size: .compact) { composing = true }
                    }
                    if !linked && canSend && happened {
                        NoticeCard(tone: .info, title: LF("%@ isn’t on PawMiaw", appointment.clientName), message: L("Send them a note by WhatsApp instead."))
                        if let url = schedWhatsAppURL(appointment.clientPhone, message: LF("Hi %@, a quick note about %@: ", NameText.firstName(appointment.clientName), appointment.petName)) {
                            Link(destination: url) { HStack(spacing: 6) { Glyph("message-circle", size: 16); Text("WhatsApp") } }.buttonStyle(.pm(.outline, size: .compact))
                        }
                    }
                    if linked && updates.isEmpty {
                        Text(L("No notes sent from this visit yet.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    }
                    ForEach(updates) { update in
                        HStack(alignment: .top, spacing: 10) {
                            if let photo = APIConfig.assetURL(update.photoUrl) {
                                AsyncImage(url: photo) { phase in
                                    if let image = phase.image { image.resizable().scaledToFill() } else { Theme.surfaceMuted }
                                }
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(update.message ?? "").font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                                Text([StaysWords.mood(update.mood).map { "\($0.emoji) \($0.label)" }, update.authorName, DateText.dayTime(update.createdAt)].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                                    .font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                    }
                  }
                  .padding(16)
                }
            }
        }
        .reloadsOnScope { await load() }
        .sheet(isPresented: $composing) { SchedVisitUpdateSheet(appointmentId: appointment.id, petName: appointment.petName) }
    }

    private func load() async {
        if let loaded: [SchedVisitUpdate] = try? await API.get("/provider-appointments/\(appointment.id)/updates") { updates = loaded }
    }
}

private struct SchedVisitUpdateSheet: View {
    let appointmentId: String
    let petName: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var mood: String?
    @State private var message = ""
    @State private var photo = PhotoDraft()
    @State private var working = false

    var body: some View {
        ProviderModal(title: L("Update for the family"), subtitle: L("Goes to the family in their PawMiaw app, with a notification."), systemImage: "send", accent: .aqua,
                      isDirty: !message.isEmpty || photo.data != nil || mood != nil, form: form, primaryTitle: L("Send to the family"), isWorking: working, primaryIcon: "send") {
            send()
        } content: {
            ModalSection(title: LF("How is %@ doing?", petName)) {
                // Five tiles, an emoji over its word (web visit-updates-card).
                HStack(spacing: 8) {
                    ForEach(StaysWords.moods, id: \.value) { option in
                        let chosen = mood == option.value
                        let shape = RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous)
                        Button { mood = chosen ? nil : option.value } label: {
                            VStack(spacing: 4) {
                                Text(option.emoji).font(.system(size: 24))
                                Text(StaysWords.mood(option.value)?.label ?? option.label)
                                    .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(chosen ? AnyShapeStyle(Theme.wash(Theme.lime, 30)) : AnyShapeStyle(Theme.surface), in: shape)
                            .overlay(shape.strokeBorder(chosen ? Theme.blue : Theme.borderSoft, lineWidth: 2))
                            .contentShape(shape)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
            }
            ModalSection(title: L("A line for the family")) {
                SchedBareField(prompt: LF("e.g. Bath done, drying now — %@ is being a star", petName), text: $message, key: "message", form: form)
            }
            PhotoField(label: L("Photo"), hint: L("Families love a photo mid-visit."), draft: $photo, allowsRemove: false)
        }
    }

    private func send() {
        guard form.check([("message", message.nonEmpty == nil ? L("Write a line for the family.") : nil)]) else { return }
        var fields: [(String, String)] = [("message", message.trimmingCharacters(in: .whitespacesAndNewlines))]
        if let mood { fields.append(("mood", mood)) }
        let files = photo.data.map { [API.UploadFile(field: "photo", fileName: "update.jpg", mimeType: "image/jpeg", data: $0)] } ?? []
        let parts = fields
        working = true
        Task {
            defer { working = false }
            do {
                let _: SchedVisitUpdate = try await API.multipart("/provider-appointments/\(appointmentId)/updates", fields: parts, files: files)
                Toast.show(LF("Sent to %@’s family.", petName))
                announceDataChanged()
                dismiss()
            } catch {
                form.apply(error, known: ["message": "message"])
            }
        }
    }
}

// MARK: - Prescriptions written at the visit

struct SchedVisitPrescriptions: View {
    let appointment: SchedAppointment

    @EnvironmentObject private var workspace: Workspace
    @State private var items: [StockPrescription]?
    @State private var writing = false
    @State private var opened: String?

    private var rights: StockRxRights { StockRxRights(workspace) }

    var body: some View {
        Group {
            if rights.canRead {
                SectionCard(title: L("Prescriptions"), subtitle: L("Written at this visit"), icon: "pill", accent: Theme.blue) {
                    if rights.canWrite && !(items ?? []).isEmpty {
                        PMButton(L("Prescribe"), systemImage: "plus", size: .header) { writing = true }
                    }
                } content: {
                    VStack(alignment: .leading, spacing: 10) {
                        if let items {
                            if items.isEmpty {
                                Text(L("No prescriptions yet.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                                if rights.canWrite { PMButton(L("Prescribe"), systemImage: "plus", size: .compact) { writing = true } }
                            }
                            ForEach(items) { prescription in
                                Button { opened = prescription.id } label: { StockPrescriptionRow(prescription: prescription) }
                                    .buttonStyle(.plain)
                            }
                        } else {
                            LoadingState()
                        }
                    }
                    .padding(16)
                }
            }
        }
        .reloadsOnScope { await load() }
        .sheet(isPresented: $writing) {
            StockPrescriptionSheet(pet: StockRxPet(clientId: appointment.providerClientId, petId: appointment.providerClientPetId, petName: appointment.petName, species: appointment.petSpecies, photoUrl: appointment.petPhotoUrl, clientName: appointment.clientName),
                                   draft: nil, appointmentId: appointment.id) { saved in
                Task { await load(); try? await Task.sleep(for: .milliseconds(450)); opened = saved.id }
            }
        }
        .navigationDestination(item: $opened) { StockPrescriptionScreen(prescriptionId: $0) }
    }

    private func load() async {
        guard rights.canRead else { return }
        if let page: StockPrescriptionPage = try? await API.get("/provider-prescriptions", query: ["appointmentId": appointment.id, "limit": "50"]) { items = page.items }
    }
}

// MARK: - Add to calendar

/// The visit as an .ics from the server, handed to the share sheet (no calendar permission asked).
struct SchedCalendarSheet: View {
    let appointment: SchedAppointment
    @State private var file: URL?
    @State private var failed: String?

    var body: some View {
        ProviderModal(title: L("Add to calendar"), subtitle: "\(appointment.petName) · \(DateText.dayTime(appointment.start))", systemImage: "calendar-plus", accent: .aqua, cancelTitle: L("Close")) {
            if let file {
                Text(L("Open it with your calendar app, or send it to whoever takes the visit.")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                ShareLink(item: file, preview: SharePreview("\(appointment.petName) · \(appointment.serviceLabel)")) {
                    HStack(spacing: 6) { Glyph("download", size: 16); Text(L("Add to calendar")) }
                }
                .buttonStyle(.pm(fullWidth: true))
            } else if let failed {
                ErrorState(message: failed) { await load() }
            } else {
                LoadingState()
            }
        }
        .presentationDetents([.medium])
        .task { await load() }
    }

    private func load() async {
        do {
            let data = try await API.data("GET", "/provider-appointments/\(appointment.id)/calendar.ics", query: [:], body: nil)
            let name = "\(appointment.petName)-\(SchedDay.key(appointment.startsAt) ?? "visit")".components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<> ")).joined(separator: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).ics")
            try data.write(to: url, options: .atomic)
            file = url
            failed = nil
        } catch {
            failed = errorText(error)
        }
    }
}
