//
//  SvcVisitSheets.swift
//  PawMiawNegocios
//
//  The visit's own sheets as the Services pages use them: finishing with the
//  charge choice (docs/charging-flow.md), the report at the end of a groom,
//  walk or class (with its photos), "On my way", and "didn't come" / taking
//  a pet out (with the fee the server asks a decision on).
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - Finish, with the charge choice

struct SvcFinishTarget: Identifiable {
    let id: String
    let petName: String
    let serviceLabel: String
    let serviceCategory: String?
    var reportMissing: [String] = []
    /// For "¿Cuándo vuelve?" and the signature: who the family is and whether PawMiaw reaches them.
    var clientName: String = ""
    var familyOnApp: Bool = false
    /// Who the visit is assigned to — the vet who signs what is left unsigned.
    var assignedId: String? = nil
    var assignedName: String? = nil
    /// The family's other pets finished with it: they get the same return day.
    var together: [String] = []
    /// Where it is: the return day counts by that location's hours.
    var locationId: String? = nil
}

/// What the visit page already knows when it opens "Terminar": nothing is read again.
struct SvcFinishKnown {
    let drafts: Int
    let signed: Int
    /// The person finishing, when they can sign (owner, admin, vet).
    let signer: (memberId: String, name: String)?
}

/// "Terminar" (web: visits/visit-sheets.tsx VisitFinishSheet), the one finish sheet — the visit page
/// (through SchedFinishSheet), Domicilio, Paseos y clases and Home: where the bill goes (the desk, charged now,
/// priced by me, or not charged with the reason), signing what is written when the person can sign,
/// and "¿Cuándo vuelve?" (docs/come-back.md) — the charge choice and the return are the Agenda's own pieces.
struct SvcFinishSheet: View {
    let target: SvcFinishTarget
    /// Extra body (a home visit's press time).
    var extraBody: [String: Any?] = [:]
    /// "Fill it in now": the report.
    var onOpenReport: (() -> Void)? = nil
    /// Where this screen has the visit's bill (charge now / price it), and where an earlier day's visit is closed.
    var onOpenVisit: (() -> Void)? = nil
    let onFinished: () -> Void
    /// Taken as Finish is pressed (a home visit's time, where the phone was, the last of a walk's route): it never stops the finish.
    var prepare: (() async -> [String: Any?])? = nil
    /// The visit's bill as the page has it: whether it is ready to charge, and the hints under each choice.
    var invoice: SchedInvoice? = nil
    /// The drafts, signed records and signer, when the page already read them.
    var known: SvcFinishKnown? = nil
    /// Whether "Charge now" / "Put the price myself" are offered (default: when there is somewhere to open the bill).
    var collects: Bool? = nil
    /// After finishing with "Charge now" or "Put the price myself" (default: `onOpenVisit`).
    var onAfter: ((SchedChargeMode) -> Void)? = nil
    /// Left open since an earlier day: "Sí vino" instead (default: `onOpenVisit`).
    var onEarlierDay: (() -> Void)? = nil

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var mode: SchedChargeMode = .desk
    @State private var reason = ""
    @State private var sign = true
    @State private var comeBack = SchedComeBack()
    @State private var availability: SchedAvailability?
    @State private var closures: [SchedClosure] = []
    @State private var drafts = 0
    @State private var signed = 0
    @State private var signerId: String?
    @State private var signerName: String?
    @State private var working = false
    @StateObject private var form = FormState()

    private var modes: [SchedChargeMode] {
        let ready: Bool? = invoice.map { bill in !(bill.lineItems ?? []).isEmpty && !(bill.lineItems ?? []).contains(where: \.needsPrice) }
        return SchedChargeMode.modes(pay: workspace.can(.billingRecordPayment), price: workspace.can(.billingEditInvoice), waive: workspace.can(.billingWaiveVisit),
                                     collects: collects ?? (onOpenVisit != nil), billReady: ready)
    }
    private var canSign: Bool { signerName != nil }
    private var willSign: Bool { canSign && sign && drafts > 0 }
    private var assignedToOther: Bool {
        guard let signerId, let assigned = target.assignedId else { return false }
        return assigned != signerId
    }
    private var asksReturn: Bool { SchedComeBack.asks(target.serviceCategory) }
    private var clinical: Bool { target.serviceCategory == nil || target.serviceCategory == "vet" || target.serviceCategory == "emergency" }
    private var reportVisit: Bool { SvcReportText.kind(for: target.serviceCategory) != nil }
    private var whatSigns: String { drafts == 1 ? L("the note") : LF("the note and %d records", drafts - 1) }
    private var reach: String { target.familyOnApp ? LF("%@ will see it in PawMiaw.", target.clientName) : L("It stays in the chart.") }
    private var reminder: String {
        target.assignedName.map { LF("You can finish now: it stays in %@’s “To complete” until it’s done, by the end of today.", $0) }
            ?? L("You can finish now: it stays in “To complete” until it’s done, by the end of today.")
    }

    var body: some View {
        ProviderModal(title: L("Finish the visit"), subtitle: "\(target.petName) · \(target.serviceLabel)", systemImage: "badge-check", accent: .lime, isDirty: !reason.isEmpty || comeBack.touched, form: form, primaryTitle: mode.actionTitle(record: false, signs: willSign), isWorking: working, cancelTitle: L("Back"),
                      primaryIcon: mode == .collect ? "hand-coins" : mode == .price ? "tag" : "badge-check", onPrimary: submit) {
            SchedChargeChoice(modes: modes, mode: $mode, reason: $reason, invoice: invoice, form: form)
            if drafts > 0 {
                ModalSection(title: L("Signature")) { signature }
            } else if reportVisit && !target.reportMissing.isEmpty {
                NoticeCard(tone: .warning, title: LF("The report is missing %@", SvcReportText.fieldsText(target.reportMissing)), message: reminder, actionTitle: onOpenReport == nil ? nil : L("Fill it in now")) {
                    dismiss()
                    onOpenReport?()
                }
            } else if clinical && drafts + signed == 0 {
                NoticeCard(tone: .warning, title: L("The visit’s note isn’t written yet"), message: reminder)
            } else if signed == 0 && !reportVisit && !clinical {
                NoticeCard(tone: .warning, title: L("No note written yet"), message: L("You can finish now: it stays in “To complete” until it’s done, by the end of today."))
            }
            if asksReturn {
                // Last, once the visit itself is settled: when this pet should come back.
                ModalSection(title: L("When does it come back?")) {
                    SchedComeBackFields(value: $comeBack, category: target.serviceCategory, availability: availability, closures: closures, familyOnApp: target.familyOnApp, clientName: target.clientName, alsoFor: target.together)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await setUp() }
    }

    /// Signing is the moment the visit becomes the record: a switch, and the signature itself under it.
    @ViewBuilder private var signature: some View {
        if let signerName {
            if assignedToOther {
                let vet = target.assignedName ?? L("the assigned vet")
                ChoiceCards(options: [
                    (true, L("Sign it myself"), LF("Signed in your name (%@), not %@’s. %@", signerName, vet, reach)),
                    (false, LF("Leave it for %@", vet), L("It waits in their “To sign” and they get a reminder.")),
                ], selection: $sign)
            } else {
                ToggleRow(title: LF("Sign %@ when finishing", whatSigns),
                          subtitle: sign ? "\(L("Your signature confirms what is written.")) \(reach) \(L("Any change afterwards is marked as a correction."))" : L("It stays in your “To sign”, with a reminder."),
                          isOn: $sign)
                if sign {
                    HStack(alignment: .lastTextBaseline) {
                        Text(signerName).font(.signatureScript(30)).foregroundStyle(Theme.inkStrong).lineLimit(1).minimumScaleFactor(0.6)
                        Spacer(minLength: 8)
                        Text(DateText.date(Date())).font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.bottom, 6)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.inkStrong.opacity(0.25)).frame(height: 1.5)
                    }
                }
            }
        } else {
            NoticeCard(tone: .warning, title: LF("%@ stays to sign", svcCapitalized(whatSigns)),
                       message: target.assignedName.map { LF("We let %@ know; the family sees it once it’s signed.", $0) } ?? L("A vet signs it; the family sees it once it’s signed."))
        }
    }

    /// What is written on the visit (to sign), who is finishing (when they can sign), and the place's open days.
    private func setUp() async {
        if let known {
            drafts = known.drafts
            signed = known.signed
            signerId = known.signer?.memberId
            signerName = known.signer?.name
        } else {
            let id = target.id
            let canApprove = workspace.can(.recordsApprove)
            let page: Page<SchedRecord>? = try? await API.get("/provider-records", query: ["limit": "100", "offset": "0", "appointmentId": id])
            let records = page?.items ?? []
            drafts = records.filter { $0.isDraft && $0.hasWords }.count
            signed = records.filter(\.isSigned).count
            if canApprove, drafts > 0, let me = await svcLoadMembers(workspace).first(where: { $0.isCurrentMember == true }) {
                signerId = me.id
                signerName = me.shownName
            }
        }
        if asksReturn, availability == nil {
            let place = target.locationId ?? workspace.locationId
            availability = await SchedData.availability(locationId: target.locationId)
            closures = await SchedData.closures(locationId: place)
        }
    }

    private func submit() {
        guard form.check([("noChargeReason", SchedChargeChoice.missingReason(mode, reason))]) else { return }
        var body = mode.body(reason: reason)
        if willSign { body["sign"] = true }
        if asksReturn, case .some(let value) = comeBack.input(category: target.serviceCategory, availability: availability, closures: closures, familyOnApp: target.familyOnApp) {
            body["comeBack"] = value
        }
        for (key, value) in extraBody { body[key] = value }
        let chosen = mode, signs = willSign
        working = true
        Task {
            defer { working = false }
            if let prepare {
                for (key, value) in await prepare() { body[key] = value }
            }
            do {
                let result: SchedMoveResponse = try await SvcAPI.send("POST", "/provider-appointments/\(target.id)/finish", body: body)
                Toast.show((signs ? L("Visit finished and signed.") : L("Visit finished.")) + " " + chosen.outcome(result.bill))
                announceDataChanged()
                dismiss()
                onFinished()
                if chosen == .collect || chosen == .price {
                    if let onAfter { onAfter(chosen) } else { onOpenVisit?() }
                }
            } catch {
                switch svcCode(error) {
                case "reason_required":
                    _ = form.check([("noChargeReason", L("Write why it is finished without charging."))])
                case "no_charge_paid":
                    _ = form.check([("noChargeReason", L("A payment is already on this visit’s bill: give it back before finishing without charging."))])
                case "no_charge_forbidden":
                    _ = form.check([("noChargeReason", L("You can’t finish a visit without charging. Send it to the desk instead."))])
                case "visit_from_earlier_day":
                    Toast.error(svcMessage(error))
                    if let onEarlierDay { onEarlierDay() } else { dismiss(); onOpenVisit?() }
                default:
                    form.apply(svcAPIError(error), known: ["noChargeReason": "noChargeReason"])
                }
            }
        }
    }
}

// MARK: - The report

struct SvcReportPet: Identifiable, Hashable {
    let id: String
    let name: String
}

struct SvcReportTarget: Identifiable {
    let id = UUID()
    let subtitle: String
    let pets: [SvcReportPet]
    let canWrite: Bool
}

/// The visit's report, written from the list: the same form the visit page has.
/// A family's pets booked together each have their own report. A groom starts
/// from what the owner asked for and says where it differs (lib/groom-request.ts).
struct SvcReportSheet: View {
    let target: SvcReportTarget
    var onSaved: () -> Void = {}

    init(target: SvcReportTarget, onSaved: @escaping () -> Void = {}) {
        self.target = target
        self.onSaved = onSaved
        _chosen = State(initialValue: target.pets.first?.id ?? "")
    }

    @State private var chosen: String = ""
    @State private var appointment: SvcAppointment?
    @State private var report: SvcReport?
    @State private var original: SvcReport?
    /// The report as the server has it (nil: none yet).
    @State private var saved: SvcReport?
    @State private var groomView: SvcGroomRequestView?
    @State private var prefilled = false
    @State private var loadError: String?
    @State private var saving = false

    private var dirty: Bool { report != nil && report != original }
    private var editable: Bool {
        guard let appointment else { return false }
        return target.canWrite && ["in_progress", "completed"].contains(appointment.status)
    }

    var body: some View {
        ProviderModal(title: L("Report"), subtitle: target.subtitle, systemImage: "clipboard-pen", accent: .aqua, isDirty: dirty, primaryTitle: editable ? L("Save report") : nil, isWorking: saving, cancelTitle: editable ? L("Cancel") : L("Close"), onPrimary: editable ? { Task { await save(close: true) } } : nil) {
            if target.pets.count > 1 {
                // A family's pets booked together: each has its own report.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(target.pets) { pet in
                            Button {
                                Task {
                                    if dirty { guard await save(close: false) else { return } }
                                    chosen = pet.id
                                }
                            } label: {
                                PetChip(name: pet.name, highlighted: chosen == pet.id)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(chosen == pet.id ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            if let appointment, let kind = appointment.reportKind, report != nil {
                HStack(spacing: 8) {
                    Glyph("clipboard-check", size: 20).foregroundStyle(Theme.blue)
                    Text(SvcReportText.title(kind, category: appointment.serviceCategory)).font(.brandHeading(18)).foregroundStyle(Theme.inkStrong)
                }
                if !["in_progress", "completed"].contains(appointment.status) {
                    Text(L("The report opens when the visit starts.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                if prefilled && saved == nil && report?.kind == "groom" {
                    HStack(spacing: 6) {
                        Glyph("sparkles", size: 14).foregroundStyle(Theme.blue)
                        Text(L("Filled in from what the owner asked for"))
                    }
                    .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.wash(Theme.blue, 10), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                }
                SvcReportForm(report: Binding(get: { report ?? SvcReport(kind: kind) }, set: { report = $0 }), category: appointment.serviceCategory, appointmentId: appointment.id, editable: editable,
                              wanted: groomView?.hasRequest == true ? groomView?.wanted : nil, startedAt: appointment.startedAt)
                if let groomView, let current = report, current.kind == "groom", editable {
                    SvcUsualStyleOffer(view: groomView, report: current, unsaved: current != saved, saveFirst: { await save(close: false) }, onSaved: { await loadGroomView(appointment.id) })
                }
                reach(appointment)
            } else if appointment != nil {
                EmptyState(systemImage: "clipboard-list", title: L("This visit has no report."))
            } else if loadError != nil {
                SvcLoadError(message: L("The report couldn’t be loaded.")) { await load() }
            } else {
                LoadingState()
            }
        }
        .task(id: chosen) { await load() }
    }

    /// Whether the family gets it in the app, or how to send it to one that isn't on PawMiaw.
    @ViewBuilder private func reach(_ appointment: SvcAppointment) -> some View {
        let name = NameText.firstName(appointment.clientName)
        if appointment.clientHouseholdId != nil {
            Text(L("The family sees this when the visit ends.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        } else if appointment.status == "completed", let current = report, SvcReportText.hasContent(current) {
            let link = ContactLinks.whatsApp(appointment.clientPhone, text: message(appointment, current))
            NoticeCard(tone: .warning, title: LF("%@ isn’t on PawMiaw", name),
                       message: L("The report won’t reach them in the app — send it by WhatsApp.") + (link == nil ? " " + L("Add a phone number to message them by WhatsApp.") : ""),
                       actionTitle: link == nil ? nil : L("WhatsApp")) {
                if let link { UIApplication.shared.open(link) }
            }
        } else {
            Text(LF("%@ isn’t on PawMiaw — you can send the report by WhatsApp when the visit ends.", name))
                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
    }

    /// The report as a WhatsApp message, for a family that isn't on PawMiaw.
    private func message(_ appointment: SvcAppointment, _ report: SvcReport) -> String {
        var lines = [LF("Hi %@, here is %@’s report from today:", NameText.firstName(appointment.clientName), appointment.petName ?? ""), ""]
        lines += SvcReportText.rows(report).map { "• \($0.label): \($0.value)" }
        if let note = report.note?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty { lines += ["", note] }
        return lines.joined(separator: "\n")
    }

    private func load() async {
        guard !chosen.isEmpty else { return }
        loadError = nil
        appointment = nil
        groomView = nil
        prefilled = false
        do {
            let loaded: SvcAppointment = try await API.get("/provider-appointments/\(chosen)")
            var start = loaded.report ?? loaded.reportKind.map { SvcReport(kind: $0) }
            saved = loaded.report
            if loaded.reportKind == "groom" {
                await loadGroomView(loaded.id)
                // No report yet: it starts from what was asked (saved only once someone saves it).
                let canWrite = target.canWrite && ["in_progress", "completed"].contains(loaded.status)
                if loaded.report == nil, canWrite, var prefill = groomView?.prefill {
                    prefill.kind = "groom"
                    start = prefill
                    prefilled = true
                }
            }
            report = start
            original = start
            appointment = loaded
        } catch is CancellationError {
        } catch {
            loadError = errorText(error)
        }
    }

    private func loadGroomView(_ appointmentId: String) async {
        if let view: SvcGroomRequestView = try? await API.get("/provider-appointments/\(appointmentId)/groom-request") { groomView = view }
    }

    @discardableResult
    private func save(close: Bool) async -> Bool {
        guard let report, let appointment else { return false }
        saving = true
        defer { saving = false }
        do {
            let _: SvcIgnored = try await API.put("/provider-appointments/\(appointment.id)/report", json: report)
            original = report
            saved = report
            Toast.show(L("Report saved."))
            announceDataChanged()
            onSaved()
            if close { dismissSelf() }
            return true
        } catch {
            Toast.error(error)
            return false
        }
    }

    @Environment(\.dismiss) private var dismiss
    private func dismissSelf() { dismiss() }
}

/// The report's fields for a groom, a walk (or a sitter's visit) or a class.
struct SvcReportForm: View {
    @Binding var report: SvcReport
    let category: String?
    let appointmentId: String
    let editable: Bool
    /// A groom: what the owner asked for (the report says where it differs).
    var wanted: SvcGroomWanted? = nil
    /// When the visit started: a walk's time can come from the clock.
    var startedAt: String? = nil
    @State private var skill = ""

    private var required: Set<String> { SvcReportText.required(category, report) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch report.kind {
            case "groom": groomFields
            case "walk": walkFields
            default: trainingFields
            }
            // Web: every part under a 12 bold name, none marked optional.
            field(nil, L("Note")) {
                TextField(L("Anything the family should know…"), text: text(\.note), axis: .vertical).lineLimit(2...8).fieldChrome(multiline: true)
            }
            .disabled(!editable)
        }
    }

    // MARK: Groom

    @ViewBuilder private var groomFields: some View {
        if let wanted { SvcGroomAskedLine(wanted: wanted) }
        field("services", L("Services")) {
            chips(SvcReportText.groomServices, selected: report.services) { report.services = toggled(report.services, $0) }
        }
        field("style", L("Style")) {
            FlowLayout(spacing: 6) {
                ForEach(SvcReportText.styles, id: \.self) { style in
                    SvcChoiceChip(title: SvcReportText.style(style), isSelected: report.styleKind == style) { report.styleKind = report.styleKind == style ? nil : style }
                }
            }
            .disabled(!editable)
            TextField(L("Puppy cut, round ears…"), text: text(\.style)).fieldChrome().disabled(!editable)
        }
        field(nil, L("Report · Length")) {
            TextField(L("Blade number or cm, e.g. #7 or 2 cm"), text: text(\.length)).fieldChrome()
        }
        .disabled(!editable)
        // Where the report differs from what was asked, live as it is written.
        if let differences = SvcGroomAsk.compare(wanted, report), differences.any {
            SvcGroomDifferenceBox(differences: differences, note: text(\.differenceNote), editable: editable)
        }
        field(nil, L("Coat")) {
            chips(SvcReportText.coats, selected: report.coat.map { [$0] } ?? []) { report.coat = report.coat == $0 ? nil : $0 }
        }
        field(nil, L("Skin")) {
            chips(SvcReportText.skins, selected: report.skin) { value in
                if value == "ok" { report.skin = report.skin.contains("ok") ? [] : ["ok"] }
                else { report.skin = toggled(report.skin.filter { $0 != "ok" }, value) }
            }
        }
        behaviourField
        HStack(spacing: 12) {
            SvcPhotoSlot(label: L("Before"), url: report.beforePhotoUrl, disabled: !editable, appointmentId: appointmentId) { report.beforePhotoUrl = $0 }
            SvcPhotoSlot(label: L("After"), url: report.afterPhotoUrl, disabled: !editable, appointmentId: appointmentId) { report.afterPhotoUrl = $0 }
        }
    }

    // MARK: Walk (and a sitter's visit)

    @ViewBuilder private var walkFields: some View {
        // Drawn by the server when the walk was finished: read here, never edited.
        if let route = report.route { WalkRouteView(route: route) }
        HStack(alignment: .top, spacing: 12) {
            field(nil, L("Time")) {
                TextField(startedAt != nil ? L("From the clock") : "min", text: Binding(get: { report.minutes.map(String.init) ?? "" }, set: { report.minutes = Int($0.filter(\.isNumber)).map { min($0, 1440) } }))
                    .keyboardType(.numberPad).fieldChrome()
            }
            field(nil, L("Distance")) {
                TextField("km", text: Binding(get: { report.distanceKm.map { $0.formatted() } ?? "" }, set: { report.distanceKm = Double($0.replacingOccurrences(of: ",", with: ".")).map { min($0, 100) } }))
                    .keyboardType(.decimalPad).fieldChrome()
            }
        }
        .disabled(!editable)
        field("pee", L("Pee")) { yesNo(report.pee, yes: L("Yes"), no: L("No")) { report.pee = $0 } }
        field("water", L("Water")) { yesNo(report.water, yes: L("Yes"), no: L("No")) { report.water = $0 } }
        field(nil, L("Poop")) { chips(SvcReportText.stool, selected: report.poop.map { [$0] } ?? [], worry: "diarrhea") { report.poop = report.poop == $0 ? nil : $0 } }
        field("ate", L("Food")) { chips(SvcReportText.eating, selected: report.ate.map { [$0] } ?? [], worry: "none") { report.ate = report.ate == $0 ? nil : $0 } }
        field(nil, L("Medicine")) { yesNo(report.medsGiven, yes: L("Given"), no: L("Not given")) { report.medsGiven = $0 } }
        behaviourField
        SvcPhotoSlot(label: L("Photo"), url: report.photoUrl, disabled: !editable, appointmentId: appointmentId) { report.photoUrl = $0 }
    }

    // MARK: Training

    @ViewBuilder private var trainingFields: some View {
        field("skills", L("Practised")) {
            if !report.skills.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(report.skills, id: \.self) { entry in
                        HStack(spacing: 4) {
                            Text(entry)
                            if editable {
                                Button { report.skills.removeAll { $0 == entry } } label: { Glyph("x", size: 14) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(L("Remove"))
                            }
                        }
                        .font(Theme.text(14, weight: .bold))
                        .foregroundStyle(Theme.inkStrong)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Theme.surfaceMuted, in: Capsule())
                    }
                }
            }
            if editable {
                TextField(L("Sit, stay, loose leash…"), text: $skill)
                    .fieldChrome()
                    .onSubmit(addSkill)
                    .submitLabel(.done)
            }
        }
        field("progress", L("Progress")) { chips(SvcReportText.progress, selected: report.progress.map { [$0] } ?? []) { report.progress = report.progress == $0 ? nil : $0 } }
        behaviourField
        field(nil, L("Homework")) {
            TextField(L("Five minutes of “stay” twice a day…"), text: text(\.homework), axis: .vertical).lineLimit(2...8).fieldChrome(multiline: true)
        }
        .disabled(!editable)
        SvcPhotoSlot(label: L("Photo"), url: report.photoUrl, disabled: !editable, appointmentId: appointmentId) { report.photoUrl = $0 }
    }

    private func addSkill() {
        guard let value = skill.nonEmpty, !report.skills.contains(value), report.skills.count < 20 else { return }
        report.skills.append(value)
        skill = ""
    }

    // MARK: Pieces

    private var behaviourField: some View {
        field("behaviour", L("Behaviour")) {
            chips(SvcReportText.behaviours, selected: report.behaviour.map { [$0] } ?? []) { report.behaviour = report.behaviour == $0 ? nil : $0 }
        }
    }

    private func text(_ path: WritableKeyPath<SvcReport, String?>) -> Binding<String> {
        Binding(get: { report[keyPath: path] ?? "" }, set: { report[keyPath: path] = $0.isEmpty ? nil : $0 })
    }

    private func toggled(_ list: [String], _ value: String) -> [String] {
        list.contains(value) ? list.filter { $0 != value } : list + [value]
    }

    /// A report field (web `Field`): its name 12 bold over it, the coral mark on the ones the report must have.
    private func field<Content: View>(_ key: String?, _ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(label).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                if key.map({ required.contains($0) }) == true { Text("*").font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.coral) }
            }
            content()
        }
    }

    private func chips(_ options: [String], selected: [String], worry: String? = nil, toggle: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(options, id: \.self) { option in
                SvcChoiceChip(title: SvcReportText.option(option), isSelected: selected.contains(option), danger: option == worry) { toggle(option) }
            }
        }
        .disabled(!editable)
    }

    private func yesNo(_ value: Bool?, yes: String, no: String, set: @escaping (Bool?) -> Void) -> some View {
        HStack(spacing: 6) {
            SvcChoiceChip(title: yes, isSelected: value == true) { set(value == true ? nil : true) }
            SvcChoiceChip(title: no, isSelected: value == false) { set(value == false ? nil : false) }
        }
        .disabled(!editable)
    }
}

/// A report photo: the shared PhotoField, uploaded for this visit as soon as it is chosen
/// (the server keeps it under the visit) and taken off at once.
struct SvcPhotoSlot: View {
    let label: String
    let url: String?
    let disabled: Bool
    let appointmentId: String
    let onChange: (String?) -> Void

    @State private var draft = PhotoDraft()
    @State private var uploading = false

    var body: some View {
        PhotoField(label: label, currentURL: url, draft: $draft, allowsRemove: !disabled)
            .disabled(disabled || uploading)
            .overlay(alignment: .topTrailing) { if uploading { ProgressView().tint(Theme.blue).padding(8) } }
            .onChange(of: draft) { _, next in
                if let data = next.data { Task { await upload(data) } }
                else if next.removed { draft = PhotoDraft(); onChange(nil) }
            }
    }

    private func upload(_ jpeg: Data) async {
        uploading = true
        defer { uploading = false; draft = PhotoDraft() }
        do {
            let result: SvcUploadResult = try await ImageUpload.upload(jpeg, to: "/provider-appointments/\(appointmentId)/report-photo")
            onChange(result.url)
        } catch {
            Toast.error(error)
        }
    }
}

// MARK: - On my way

struct SvcOnMyWayTarget: Identifiable {
    let id: String
    let appointmentId: String
    let client: SvcClientRef
    let petNames: String
}

/// "On my way": tell the family in PawMiaw, or open WhatsApp with the message ready. The visit doesn't move.
struct SvcOnMyWaySheet: View {
    let target: SvcOnMyWayTarget
    var onSent: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var channel = "app"
    @State private var minutes = 0
    @State private var working = false

    private var canApp: Bool { target.client.onPawMiaw == true }
    private var canWhatsApp: Bool { target.client.phone?.nonEmpty != nil }
    private var available: Bool { channel == "app" ? canApp : canWhatsApp }
    private var client: String { target.client.shortName }

    var body: some View {
        ProviderModal(title: L("On my way"), subtitle: LF("Tell %@ you’re on the way", client), systemImage: "navigation", accent: .aqua,
                      primaryTitle: channel == "whatsapp" ? L("Open WhatsApp") : L("Send"), isWorking: working,
                      primaryIcon: channel == "whatsapp" ? "message-circle" : "send", primaryDisabled: !available, onPrimary: send) {
            ContextPills(client: target.client.name, pets: target.petNames.components(separatedBy: ", ").filter { !$0.isEmpty && $0 != "—" })
            ModalSection(title: L("How to tell them")) {
                ChoiceCards(options: channelOptions, selection: $channel)
            }
            ModalSection(title: L("Arriving in about")) {
                FlowLayout(spacing: 8) {
                    ForEach(minuteOptions, id: \.value) { option in
                        SvcChoiceChip(title: option.title, isSelected: minutes == option.value, height: 48) { minutes = option.value }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { channel = canApp ? "app" : "whatsapp" }
    }

    private var channelOptions: [(value: String, title: String, subtitle: String?)] {
        let app: String = canApp ? LF("%@ gets a notice in PawMiaw.", client) : LF("%@ is not on PawMiaw.", client)
        let whatsapp: String = canWhatsApp ? L("WhatsApp opens with the message ready. You send it there.") : LF("%@ has no phone for WhatsApp.", client)
        return [("app", L("In PawMiaw"), app), ("whatsapp", L("By WhatsApp"), whatsapp)]
    }

    private var minuteOptions: [(value: Int, title: String, count: Int?)] {
        [(0, L("Don’t say when"), nil)] + [5, 10, 15, 20, 30].map { minutes -> (value: Int, title: String, count: Int?) in (minutes, LF("%d min", minutes), nil) }
    }

    private func send() {
        working = true
        Task {
            defer { working = false }
            do {
                var body: [String: Any?] = ["channel": channel, "locale": svcLocale]
                if minutes > 0 { body["minutes"] = minutes }
                let result: SvcOnMyWayResult = try await SvcAPI.send("POST", "/provider-appointments/\(target.appointmentId)/home-on-my-way", body: body)
                if channel == "whatsapp", let link = result.link {
                    svcOpen(link)
                    Toast.show(L("WhatsApp opened with the message ready."))
                } else {
                    Toast.show(LF("%@ was told you’re on the way.", client))
                }
                announceDataChanged()
                onSent()
                dismiss()
            } catch {
                Toast.error(svcMessage(error, codes: SvcRefusals.homeVisits))
            }
        }
    }
}

// MARK: - Didn't come / take the pet out

struct SvcMissedTarget: Identifiable {
    let id: String
    let petName: String
    let clientName: String
    let subtitle: String
    /// "no_show" or "cancel".
    let mode: String
}
