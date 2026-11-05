//
//  HospitalEndSheets.swift
//  PawMiawNegocios
//
//  The end of a hospitalization (web hospital-end-sheets.tsx). Discharge
//  waits for the sheet: every dose whose time came is marked first
//  (`openDoses`, with "Open the sheet"); it writes the summary, the recheck
//  and the medicines to give at home, and sends the running bill to the
//  front desk unless kept a draft (docs/charging-flow.md). A transfer or a
//  death does not wait. Euthanasia needs the family's signed consent, or an
//  owner's or admin's reason.
//

import SwiftUI

// MARK: - Discharge

private struct HospTakeHomeDraft: Identifiable, Equatable {
    let id = UUID()
    var item: HospCatalogRef?
    var name = ""
    var dose = ""
    var unit = ""
    var route = "oral"
    var everyHours = "12"
    var days = "7"
    var quantity = ""
    var instructions = ""
    var addToBill = true
}

private struct HospDischargeDone {
    let prescription: HospPrescriptionResult?
    let records: Int
    let cabinetItems: Int
    let billAtDesk: Bool
}

struct HospDischargeSheet: View {
    @ObservedObject var model: HospDetailModel
    let detail: HospDetail
    let onGoToSheet: (String) -> Void
    let onPDF: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var summary = ""
    @State private var diagnosis = ""
    @State private var instructions = ""
    @State private var followUpAt: Date?
    @State private var followUpNote = ""
    @State private var rows: [HospTakeHomeDraft] = []
    @State private var prescribe = false
    @State private var keepDraft = false
    @State private var saving = false
    @State private var done: HospDischargeDone?

    private var onApp: Bool { detail.client?.onPawMiaw == true }
    private var openDoses: [HospOpenDose] { detail.openDoses ?? [] }
    private var unpriced: Bool { (detail.bill?.lines ?? []).contains(where: \.needsPrice) }

    var body: some View {
        ProviderModal(
            title: done != nil ? LF("%@ is going home", detail.petName) : LF("Discharge %@", detail.petName),
            subtitle: done != nil ? L("What the discharge created")
                : onApp ? L("The family reads the summary and the medicines in their app.") : L("The family isn’t on PawMiaw: print the summary or send them the PDF."),
            systemImage: "heart-handshake",
            accent: .lime,
            isDirty: done == nil && (!summary.isEmpty || !diagnosis.isEmpty || !instructions.isEmpty || !rows.isEmpty),
            form: form,
            primaryTitle: done != nil ? L("Discharge PDF") : L("Discharge"),
            isWorking: saving,
            cancelTitle: done != nil ? L("Close") : L("Cancel"),
            primaryIcon: done != nil ? "file-down" : "heart-handshake",
            onPrimary: primary
        ) {
            if let done { result(done) } else { fields }
        }
    }

    private func primary() {
        if done != nil {
            dismiss()
            onPDF()
        } else {
            submit()
        }
    }

    @ViewBuilder private func result(_ done: HospDischargeDone) -> some View {
        NoticeCard(tone: .success, title: [
            done.records == 0 ? nil : done.records == 1 ? L("1 medicine is on the chart.") : LF("%d medicines are on the chart.", done.records),
            done.cabinetItems == 0 ? nil : done.cabinetItems == 1 ? L("1 is in the family’s cabinet.") : LF("%d are in the family’s cabinet.", done.cabinetItems),
            done.billAtDesk ? L("Active orders stopped, and the bill is at the front desk to be charged.") : L("Active orders stopped, and the bill stays a draft for the desk."),
        ].compactMap { $0 }.joined(separator: " "))
        if !onApp { NoticeCard(tone: .info, title: L("The family isn’t on PawMiaw: print the summary or send them the PDF.")) }
        if let prescription = done.prescription {
            if prescription.ok == true {
                let folios = (prescription.prescriptions ?? []).compactMap { $0.folio?.nonEmpty }.joined(separator: ", ")
                NoticeCard(tone: .success, title: L("The discharge prescription is signed.") + (folios.isEmpty ? "" : " \(folios)"))
            } else {
                NoticeCard(tone: .warning, title: L("The prescription isn’t signed."),
                           message: hospRefusalText(code: prescription.code, error: prescription.error, fallback: "The prescription could not be written.")
                            + "\n" + L("The discharge went through. Finish the prescription from the patient’s chart, under Prescriptions."))
            }
        }
    }

    @ViewBuilder private var fields: some View {
        if !openDoses.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                NoticeCard(
                    tone: .problem,
                    title: openDoses.count == 1 ? L("1 dose on the sheet isn’t marked yet") : LF("%d doses on the sheet aren’t marked yet", openDoses.count),
                    message: ([LF("Mark each as given, or not given with the reason, before %@ goes home.", detail.petName)]
                        + openDoses.prefix(6).map { "· \($0.label ?? "") — \(HospFmt.dateTime($0.scheduledFor, detail.zone))" }
                        + (openDoses.count > 6 ? [LF("and %d more", openDoses.count - 6)] : [])).joined(separator: "\n"),
                    actionTitle: L("Open the sheet")
                ) {
                    let day = HospFmt.dayKey(openDoses[0].scheduledFor, detail.zone) ?? detail.sheet?.today ?? ""
                    dismiss()
                    onGoToSheet(day)
                }
            }
        }
        ModalSection(title: L("For the family")) {
            PMTextField(L("Summary"), text: $summary, key: "summary", form: form,
                        prompt: LF("e.g. %@ came in dehydrated with vomiting. After two days of fluids and anti-nausea medicine she is eating and drinking well.", detail.petName),
                        multiline: true, required: true)
            PMTextField(L("Diagnosis"), text: $diagnosis, prompt: L("e.g. Acute gastroenteritis"))
            OptionalDateField(label: L("Recheck on"), date: $followUpAt, placeholder: L("No recheck"), zone: detail.zone, min: Calendar.current.startOfDay(for: Date()), components: [.date],
                                  defaultDate: Date().addingTimeInterval(7 * 86_400), optional: false)
            if followUpAt != nil {
                // Web: a field with only its placeholder, under the day.
                TextField(L("What the recheck is for"), text: $followUpNote).fieldChrome()
            }
            PMTextField(L("Care at home"), text: $instructions, prompt: L("e.g. Small bland meals for 3 days, fresh water, short walks. Call us if the vomiting comes back."), multiline: true)
        }
        ModalSection(title: L("Medicines to give at home"),
                     subtitle: onApp ? L("Each one reaches the family’s medicines and cabinet, with its directions.") : L("Each one goes on the chart and the discharge summary, with its directions.")) {
            ForEach($rows) { $row in
                HospTakeHomeRow(row: $row) { rows.removeAll { $0.id == row.id } }
            }
            PMButton(L("Add a medicine"), systemImage: "plus", variant: .outline) { rows.append(HospTakeHomeDraft()) }
                .disabled(rows.count >= 20)
            if !rows.isEmpty {
                // Web: a checkbox row, not a switch.
                Button { prescribe.toggle() } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Tick(on: prescribe).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Write the prescription")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                            Text(L("Signs the discharge prescription with these medicines. If it can’t, the discharge still goes through."))
                                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(prescribe ? .isSelected : [])
            }
        }
        // Only whoever sees the bill (money level 1) chooses where it goes; a $0 line keeps it a draft.
        if detail.bill != nil {
            ModalSection(title: L("The bill")) {
                ToggleRow(
                    title: L("Keep it a draft to adjust"),
                    subtitle: unpriced ? L("Something has no price yet: it stays a draft until it has one.")
                        : keepDraft ? L("It waits in Invoices › To charge until someone sends it to the front desk.") : L("Off, it goes to the front desk to be charged."),
                    isOn: Binding(get: { keepDraft || unpriced }, set: { keepDraft = $0 })
                )
                .disabled(unpriced)
            }
        }
    }

    private func submit() {
        if !openDoses.isEmpty {
            Toast.error(L("Some doses on the sheet aren’t marked yet. Mark each as given or not given before the patient leaves."))
            return
        }
        guard form.check([("summary", summary.nonEmpty == nil ? L("Write the discharge summary.") : nil)]) else { return }
        var takeHome: [[String: Any?]] = []
        for row in rows {
            let name = row.name.nonEmpty ?? row.item?.name ?? ""
            let dose = HospFmt.read(row.dose)
            let every = row.everyHours.nonEmpty.map { Int($0) ?? -1 }
            let days = row.days.nonEmpty.map { Int($0) ?? -1 }
            let quantity = row.quantity.nonEmpty.map { Int($0) ?? -1 }
            let problem: String? = name.isEmpty ? L("Name each medicine to take home.")
                : dose.map { $0.isNaN || $0 <= 0 } == true ? L("Enter a dose greater than zero.")
                : every.map { !(1...168).contains($0) } == true ? L("Every 1 to 168 hours.")
                : days.map { !(1...365).contains($0) } == true ? L("For 1 to 365 days.")
                : quantity.map { !(0...1000).contains($0) } == true ? L("A quantity from 0 to 1000.") : nil
            if let problem { Toast.error(problem); return }
            takeHome.append([
                "catalogItemId": row.item?.id, "name": name, "doseAmount": dose, "doseUnit": row.unit.nonEmpty, "route": row.route.nonEmpty,
                "everyHours": every, "durationDays": days, "quantity": quantity, "instructions": row.instructions.nonEmpty,
                "addToBill": row.item != nil && row.addToBill,
            ])
        }
        var followUp: String?
        if let day = followUpAt {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = detail.zone
            followUp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day).map { DateText.iso($0) }
        }
        saving = true
        Task {
            defer { saving = false }
            do {
                let answer = try await model.write("/discharge", body: [
                    "summary": summary.nonEmpty,
                    "diagnosis": diagnosis.nonEmpty,
                    "instructions": instructions.nonEmpty,
                    "followUpAt": followUp,
                    "followUpNote": followUp != nil ? followUpNote.nonEmpty : nil,
                    "takeHome": takeHome,
                    "prescribe": prescribe && !takeHome.isEmpty,
                    "keepDraft": keepDraft,
                ])
                Toast.show(onApp ? LF("%@ is discharged. The family has been told.", detail.petName) : LF("%@ is discharged.", detail.petName))
                done = HospDischargeDone(prescription: answer.discharge?.prescription, records: answer.discharge?.records ?? 0,
                                         cabinetItems: answer.discharge?.cabinetItems ?? 0, billAtDesk: answer.bill?.status == "ready_for_payment")
            } catch {
                Toast.error(hospError(error, fallback: "Could not discharge."))
            }
        }
    }
}

private struct HospTakeHomeRow: View {
    @Binding var row: HospTakeHomeDraft
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                if let item = row.item {
                    HStack {
                        Text(item.name ?? "").font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        Spacer()
                        IconCircleButton(systemImage: "x", label: L("Remove item")) { row.item = nil }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HospCatalogSearch(prompt: L("From the Catalog"), itemType: "product", showsPrice: false) { entry in
                            row.item = HospCatalogRef(id: entry.id, name: entry.name, itemType: entry.itemType, unitAmount: entry.defaultUnitAmount)
                            row.name = ""
                        }
                        TextField(L("Or write its name"), text: $row.name).fieldChrome()
                    }
                }
                IconCircleButton(systemImage: "trash-2", label: L("Remove medicine"), tint: Theme.destructive, action: onRemove)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                small(L("Dose"), $row.dose, .decimalPad)
                small(L("Unit"), $row.unit, .default)
                MenuField(label: L("Route"), options: [("", "—")] + HospWords.homeRoutes.map { ($0, HospWords.route($0)) }, selection: $row.route)
                small(L("Every (hours)"), $row.everyHours, .numberPad)
                small(L("For (days)"), $row.days, .numberPad)
                small(L("Qty"), $row.quantity, .numberPad)
            }
            TextField(L("e.g. With food; finish the whole course"), text: $row.instructions).fieldChrome()
            if row.item != nil {
                ToggleRow(title: L("Add to the bill (and take it from stock)"), isOn: $row.addToBill)
            }
        }
        .padding(12)
        .background(Theme.wash(Theme.aqua, 8), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    private func small(_ label: String, _ text: Binding<String>, _ keyboard: UIKeyboardType) -> some View {
        FormField(label: label) {
            TextField("", text: text).keyboardType(keyboard).fieldChrome()
        }
    }
}

// MARK: - Transfer

struct HospTransferSheet: View {
    @ObservedObject var model: HospDetailModel
    let detail: HospDetail

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var destination = ""
    @State private var reason = ""
    @State private var summary = ""
    @State private var saving = false

    var body: some View {
        ProviderModal(
            title: LF("Transfer %@", detail.petName),
            subtitle: L("The stay here ends; active orders stop and the bill stays a draft."),
            systemImage: "arrow-right-left",
            accent: .aqua,
            isDirty: !destination.isEmpty || !reason.isEmpty || !summary.isEmpty,
            form: form,
            primaryTitle: L("Transfer"),
            isWorking: saving,
            primaryIcon: "arrow-right-left"
        ) {
            guard form.check([("destination", destination.nonEmpty == nil ? L("Say where the patient goes.") : nil)]) else { return }
            saving = true
            Task {
                defer { saving = false }
                do {
                    try await model.write("/transfer", body: ["destination": destination.nonEmpty, "reason": reason.nonEmpty, "summary": summary.nonEmpty])
                    Toast.show(LF("%@ is transferred to %@.", detail.petName, destination.nonEmpty ?? ""))
                    dismiss()
                } catch {
                    Toast.error(hospError(error, fallback: "Could not transfer."))
                }
            }
        } content: {
            PMTextField(L("To"), text: $destination, key: "destination", form: form, prompt: L("e.g. Hospital Veterinario del Norte, ICU"), required: true)
            PMTextField(L("Why"), text: $reason, prompt: L("e.g. Needs 24-hour intensive care and a CT scan"), multiline: true)
            PMTextField(L("Summary for the receiving team"), text: $summary, multiline: true)
        }
    }
}

// MARK: - Death

struct HospDeathSheet: View {
    @ObservedObject var model: HospDetailModel
    let detail: HospDetail
    let canOverride: Bool

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var cause: String? = "natural"
    @State private var diedAt = Date()
    @State private var aftercare = ""
    @State private var aftercareNote = ""
    @State private var notes = ""
    @State private var consent: HospConsent?
    @State private var needsConsent = false
    @State private var asking = false
    @State private var signing: String?
    @State private var overriding = false
    @State private var saving = false

    private var euthanasia: Bool { cause == "euthanasia" }
    private var signed: Bool { consent?.status == "signed" }
    private var onApp: Bool { detail.client?.onPawMiaw == true }

    var body: some View {
        ProviderModal(
            title: LF("Record %@’s passing", detail.petName),
            subtitle: onApp ? L("Take the time you need. The family is told with care, and upcoming reminders and visits are cancelled.")
                : L("Take the time you need. Upcoming reminders and visits are cancelled; the family isn’t on PawMiaw, so tell them yourself."),
            systemImage: "feather",
            accent: .grey,
            isDirty: !notes.isEmpty || !aftercareNote.isEmpty,
            form: form,
            primaryTitle: L("Record"),
            isWorking: saving,
            // Web: beside Record in the footer, its words in red.
            secondaryActions: euthanasia && !signed && canOverride
                ? [ModalAction(L("Record without the signed consent"), tint: Theme.destructive) { overriding = true }] : [],
            primaryIcon: "feather"
        ) {
            if euthanasia && !signed {
                Toast.error(L("The family’s signed euthanasia consent is needed first."))
                return
            }
            Task { try? await submit(override: nil) }
        } content: {
            // Web: the "Cause *" part, its choice under the title.
            ModalSection(title: L("Cause"), required: true) {
                PillPicker(options: HospWords.causes.map { ($0, HospWords.deathCause($0)) }, choice: Binding(get: { cause }, set: { cause = $0; needsConsent = false }))
                    .accessibilityLabel(L("Cause"))
            }
            if euthanasia {
                VStack(alignment: .leading, spacing: 8) {
                    NoticeCard(
                        tone: signed ? .success : .warning,
                        title: signed ? L("The family signed the euthanasia consent.")
                            : consent?.status == "pending" ? L("Waiting for the family’s signature on the euthanasia consent.")
                            : consent?.status == "declined" ? L("The family declined the euthanasia consent.") : L("The family’s signed euthanasia consent is needed first."),
                        message: needsConsent && !signed ? L("No signed euthanasia consent was found for this hospitalization.") : nil
                    )
                    if !signed {
                        FlowLayout(spacing: 8) {
                            PMButton(L("Sign here"), systemImage: "pen-line", size: .compact, isWorking: asking) {
                                if consent?.status == "pending", let id = detail.deathConsentId { signing = id } else { Task { await ask(false) } }
                            }
                            if onApp {
                                PMButton(consent?.status == "pending" ? L("Send again") : L("Send to the family"), systemImage: "send", variant: .outline, size: .compact, isWorking: asking) {
                                    Task { await ask(true) }
                                }
                            }
                        }
                    }
                }
            }
            DateTimeField(label: L("Time"), date: $diedAt, zone: detail.zone, max: Date(), key: "diedAt", form: form, required: true)
            MenuField(label: L("Aftercare"), options: [("", L("Not decided yet"))] + HospWords.aftercares.map { ($0, HospWords.aftercare($0)) }, selection: $aftercare)
            PMTextField(L("Aftercare note"), text: $aftercareNote, prompt: L("e.g. Paw print kept for the family"))
            PMTextField(L("Notes for the chart"), text: $notes, multiline: true)
        }
        .task(id: euthanasia) { await loadConsent() }
        .sheet(item: Binding(get: { signing.map { HospSigning($0) } }, set: { signing = $0?.id })) { item in
            ConsentSignSheet(consentId: item.id, successMessage: L("Signed. It is kept with the hospitalization.")) { Task { await loadConsent(); await model.load() } }
        }
        .sheet(isPresented: $overriding) {
            ConfirmSheet(
                title: L("Record the euthanasia without the signed consent?"),
                message: L("Only owners and admins can. It is written down with your name and the reason."),
                confirmTitle: L("Record"),
                destructive: true,
                askReason: true,
                reasonRequired: true,
                cancelTitle: L("Not now")
            ) { reason in
                try await submit(override: reason ?? "")
            }
        }
    }

    private func loadConsent() async {
        guard euthanasia, let id = detail.deathConsentId ?? model.detail?.deathConsentId else { return }
        consent = try? await API.get("/provider-consents/\(id)")
    }

    private func ask(_ notify: Bool) async {
        asking = true
        defer { asking = false }
        do {
            let answer = try await HospAPI.askConsent(detail.id, kind: "euthanasia", notify: notify)
            await model.load()
            if let id = answer.consentId { consent = try? await API.get("/provider-consents/\(id)") }
            if notify {
                Toast.show(answer.notified == true ? L("Sent to the family to sign.") : L("Asked. The family isn’t on the app: sign it here with them."))
            } else if let id = answer.consentId {
                signing = id
            }
        } catch {
            Toast.error(hospError(error, fallback: "Could not ask for the signature."))
        }
    }

    private func submit(override: String?) async throws {
        guard form.check([("diedAt", diedAt.timeIntervalSinceNow > 60 ? L("That time is in the future.") : nil)]) else { return }
        saving = true
        defer { saving = false }
        var body: [String: Any?] = [
            "cause": cause ?? "natural",
            "diedAt": DateText.iso(diedAt),
            "notes": notes.nonEmpty,
            "aftercare": aftercare.nonEmpty,
            "aftercareNote": aftercareNote.nonEmpty,
        ]
        if let override {
            body["overrideConsent"] = true
            body["overrideReason"] = override
        }
        do {
            try await model.write("/death", body: body)
            Toast.show(onApp ? L("Recorded. The family receives a gentle notice.") : L("Recorded."))
            overriding = false
            dismiss()
        } catch {
            if (error as? APIError)?.code == "consent_required" { needsConsent = true }
            if override == nil { Toast.error(hospError(error, fallback: "Could not record it.")) }
            throw hospRefusal(error, fallback: "Could not record it.")
        }
    }
}

/// A consent id to sign, as a sheet item.
struct HospSigning: Identifiable {
    let id: String
    init(_ id: String) { self.id = id }
}
