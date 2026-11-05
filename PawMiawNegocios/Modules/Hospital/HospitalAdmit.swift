//
//  HospitalAdmit.swift
//  PawMiawNegocios
//
//  Admit a patient (web admit-sheet.tsx), in steps: who (a client and one of
//  their pets), why and where (reason, emergency and triage, ward or cage,
//  the attending vet), then the estimate the family signs and the deposit.
//  It is created waiting for the gate and admitted right away when "Admit
//  now" is on and the gate allows it, or an owner or admin goes ahead with
//  a reason. A ward that is full asks "Place the patient anyway?".
//

import SwiftUI

/// What the ward opens after an admission: the patient, and the estimate to sign here first.
struct HospOpened: Hashable {
    let id: String
    var signConsentId: String? = nil
    var admitAfterSigning: Bool = false
}

private enum HospAdmitStep: Int { case patient, why, money }

struct HospAdmitSheet: View {
    let onCreated: (HospOpened) -> Void

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()

    @State private var step: HospAdmitStep = .patient
    @State private var client: PickedClient?
    @State private var petIds: [String] = []
    @State private var reason = ""
    @State private var emergency = false
    @State private var priority: String?
    @State private var roomId = ""
    @State private var cageLabel = ""
    @State private var attendingId = ""
    @State private var estimate: Int?
    @State private var deposit: Int?
    @State private var signHere = false
    @State private var admitNow = true
    @State private var internalNote = ""
    @State private var saving = false
    @State private var members: [HospMember] = []
    @State private var wards: [HospRoom] = []
    @State private var occupied: [String: Int] = [:]
    @State private var roomFull: String?
    @State private var overriding = false
    /// The patient is already in the hospital: its hospitalization, to open instead.
    @State private var existingId: String?

    private var vets: [HospMember] { members.filter { $0.can(.hospitalManage) } }
    private var me: HospMember? { members.first { $0.isCurrentMember == true } }
    private var petId: String? { petIds.first }
    private var pet: PickedPet? { client?.activePets.first { $0.id == petId } }
    private var patientName: String { pet?.name ?? "" }
    private var attendingName: String? {
        let id = attendingId.nonEmpty ?? me?.id
        return members.first { $0.id == id }?.label
    }
    private var hasEstimate: Bool { (estimate ?? 0) > 0 }
    private var owesDeposit: Bool { (deposit ?? 0) > 0 && !(emergency && priority == "critical") }
    private var gated: Bool { hasEstimate || owesDeposit }
    private var canOverride: Bool { workspace.isOwnerOrAdmin }
    private var clientOnApp: Bool { client?.householdId != nil }
    private var room: HospRoom? { wards.first { $0.id == roomId } }

    var body: some View {
        ProviderModal(
            title: patientName.isEmpty ? L("Admit a patient") : LF("Hospitalize %@", patientName),
            subtitle: L("It waits for the signed estimate and the deposit, then is admitted."),
            systemImage: "bed-double",
            accent: .pink,
            isDirty: client != nil || step != .patient,
            form: form,
            primaryTitle: primaryTitle,
            isWorking: saving,
            steps: ModalSteps(steps: [(L("Patient"), "user-round"), (L("Why and where"), "stethoscope"), (L("Estimate and deposit"), "wallet")], current: step.rawValue),
            onBack: step != .patient ? { step = HospAdmitStep(rawValue: step.rawValue - 1) ?? .patient } : nil,
            secondaryActions: step == .money && admitNow && canOverride && gated
                ? [ModalAction(L("Admit without the gate"), tint: Theme.destructive) { if validate() { overriding = true } }] : [],
            primaryIcon: step == .money ? "bed-double" : nil,
            onPrimary: primary
        ) {
            if step != .patient, let client {
                // Who it is for (Back changes it), then what the second step settled (web ModalContextPills).
                ContextPills(client: client.name, linked: client.householdId != nil, pets: patientName.isEmpty ? [] : [patientName]) {
                    if step == .money && emergency { hospContextPill(priority.map { HospWords.triage($0) } ?? L("Emergency"), icon: "siren") }
                    if step == .money, let place = [room?.name, cageLabel.nonEmpty].compactMap({ $0 }).joined(separator: " · ").nonEmpty {
                        hospContextPill(place, icon: "bed-double")
                    }
                    if step == .money, let attendingName { hospContextPill(attendingName, icon: "stethoscope") }
                }
            }
            if let existingId {
                NoticeCard(tone: .warning, title: L("This patient is already in the hospital."), actionTitle: L("Open it")) {
                    dismiss()
                    onCreated(HospOpened(id: existingId))
                }
            }
            switch step {
            case .patient: patientStep
            case .why: whyStep
            case .money: moneyStep
            }
        }
        .task { await prepare() }
        .onChange(of: client?.id) { _, _ in signHere = client.map { $0.householdId == nil } ?? false }
        .sheet(isPresented: Binding(get: { roomFull != nil }, set: { if !$0 { roomFull = nil } })) {
            ConfirmSheet(title: L("Place the patient anyway?"), message: roomFull, confirmTitle: L("Place anyway"), destructive: true) { _ in
                try await submit(extra: ["allowOverCapacity": true])
            }
        }
        .sheet(isPresented: $overriding) {
            ConfirmSheet(
                title: L("Admit without the signed estimate or the deposit?"),
                message: L("Only owners and admins can. It is written down with your name and the reason."),
                confirmTitle: L("Admit anyway"),
                destructive: true,
                askReason: true,
                reasonRequired: true,
                cancelTitle: L("Not now")
            ) { reason in
                try await submit(extra: ["admitNow": true, "overrideConsent": true, "overrideDeposit": true, "overrideReason": reason ?? ""])
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case .patient: L("Patient")
        case .why: L("Why and where")
        case .money: L("Estimate and deposit")
        }
    }

    private var primaryTitle: String {
        guard step == .money else { return L("Continue") }
        if !admitNow { return L("Save as waiting") }
        if !gated { return L("Admit") }
        return hasEstimate && signHere ? L("Save and sign") : L("Save and wait")
    }

    // MARK: Steps

    @ViewBuilder private var patientStep: some View {
        ClientPetPicker(client: $client, petIds: $petIds, pets: .one, petRequired: true, label: L("Patient"), key: "patient", petKey: "patient", form: form)
    }

    @ViewBuilder private var whyStep: some View {
        // The web's "Why *" part: the reason under the title (no label of its own), then the
        // emergency switch with its triage.
        ModalSection(title: L("Why"), required: true) {
            StaysPlainField(prompt: L("e.g. Gastroenteritis, dehydrated — IV fluids and monitoring"), text: $reason, key: "reason", form: form, multiline: true)
                .accessibilityLabel(L("Why"))
            ToggleRow(title: L("Emergency"), subtitle: L("A critical emergency is never held back by the deposit."), isOn: $emergency)
            if emergency {
                FormField(label: L("Triage")) {
                    PillPicker(options: HospWords.priorities.map { ($0, HospWords.triage($0)) }, choice: $priority)
                }
            }
        }
        ModalSection(title: L("Where and who")) {
            if wards.isEmpty {
                NoticeCard(tone: .info, title: L("No wards set up yet"),
                           message: L("Admit them without a place and place them from the ward later. Write the cage or bed below if you know it."))
            } else {
                MenuField(label: L("Ward or cage"), options: [("", L("Not placed yet"))] + wards.map { ward in
                    (ward.id, LF("%@ · %d of %d", ward.name ?? "", occupied[ward.id] ?? 0, ward.capacity ?? 0))
                }, selection: $roomId)
                if let room, (occupied[room.id] ?? 0) >= (room.capacity ?? 0) {
                    Text(LF("%@ is full.", room.name ?? "")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.mango)
                }
            }
            PMTextField(L("Cage or bed"), text: $cageLabel, prompt: L("e.g. C3"))
            MenuField(label: L("Attending vet"), options: attendingOptions, selection: $attendingId)
        }
    }

    @ViewBuilder private var moneyStep: some View {
        ModalSection(title: L("Estimate and deposit"), subtitle: L("The family signs the estimate before the patient is admitted; the deposit stays as credit and is spent on the bill.")) {
            MoneyField(label: L("Estimate"), cents: $estimate, key: "estimate", form: form, optional: true)
            MoneyField(label: L("Deposit"), cents: $deposit, key: "deposit", form: form, optional: true)
            if hasEstimate {
                HospHint(text: LF("The family signs an estimate of %@.", Money.format(estimate, currency: workspace.currency)))
                PillPicker(
                    options: (clientOnApp ? [("family", L("Send it to the family’s app"))] : []) + [("here", L("Sign here, on this device"))],
                    choice: Binding(get: { signHere ? "here" : "family" }, set: { signHere = $0 == "here" })
                )
            } else {
                HospHint(text: L("No estimate: nothing to sign."))
            }
        }
        ToggleRow(title: L("Admit now"), subtitle: admitNowHint, isOn: $admitNow)
        PMTextField(L("Internal note"), text: $internalNote, prompt: L("Only the team sees it."), multiline: true)
    }

    private var admitNowHint: String {
        if !admitNow { return L("It waits on the board until someone admits it.") }
        if !gated { return L("Right away: there is nothing to sign or pay first.") }
        if !owesDeposit { return L("Once the estimate is signed.") }
        return hasEstimate ? L("Once the estimate is signed and the deposit paid: “Admit” on its page.") : L("Once the deposit is paid: “Admit” on its page.")
    }

    private var attendingOptions: [(value: String, title: String)] {
        var options: [(value: String, title: String)] = []
        if !(me.map { me in vets.contains { $0.id == me.id } } ?? false) { options.append(("", L("Me"))) }
        options += vets.map { ($0.id, $0.id == me?.id ? LF("%@ (you)", $0.label) : $0.label) }
        return options
    }

    // MARK: Actions

    private func prepare() async {
        async let loadedMembers = HospAPI.members()
        async let loadedWards = HospAPI.wards(locationId: Workspace.shared.locationId)
        let board: HospBoard? = try? await API.get("/provider-hospital/board", query: ["locationId": Workspace.shared.locationId])
        members = await loadedMembers
        wards = await loadedWards.filter { $0.status == nil || $0.status == "active" }
        occupied = Dictionary((board?.rooms ?? []).map { ($0.id, $0.occupied ?? 0) }, uniquingKeysWith: { a, _ in a })
        if attendingId.isEmpty, let me, me.can(.hospitalManage) { attendingId = me.id }
    }

    private func primary() {
        switch step {
        case .patient:
            guard form.check([("patient", petId == nil ? L("Choose the patient.") : nil)]) else { return }
            step = .why
        case .why:
            guard form.check([("reason", reason.nonEmpty == nil ? L("Say why the patient is hospitalized.") : nil)]) else { return }
            step = .money
        case .money:
            guard validate() else { return }
            Task { do { try await submit(extra: [:]) } catch {} }
        }
    }

    private func validate() -> Bool {
        if petId == nil { step = .patient; return form.check([("patient", L("Choose the patient."))]) }
        if reason.nonEmpty == nil { step = .why; return form.check([("reason", L("Say why the patient is hospitalized."))]) }
        return form.check([
            ("deposit", hasEstimate && (deposit ?? 0) > (estimate ?? 0) ? L("The deposit can’t be more than the estimate.") : nil),
        ])
    }

    /// Creates it; a ConfirmSheet's action rethrows so it stays open on a refusal.
    private func submit(extra: [String: Any?]) async throws {
        guard let petId else { return }
        var body: [String: Any?] = [
            "providerClientPetId": petId,
            "appointmentId": nil,
            "emergency": emergency,
            "triagePriority": emergency ? priority : nil,
            "reason": reason.nonEmpty,
            "internalNote": internalNote.nonEmpty,
            "roomId": roomId.nonEmpty,
            "cageLabel": cageLabel.nonEmpty,
            "attendingMemberId": attendingId.nonEmpty,
            "estimateAmount": hasEstimate ? estimate : nil,
            "depositAmount": deposit ?? 0,
            "askConsent": hasEstimate,
            "admitNow": admitNow,
        ]
        if let location = workspace.locationId { body["locationId"] = location }
        if hasEstimate { body["notifyFamily"] = !signHere }
        for (key, value) in extra { body[key] = value }
        saving = true
        defer { saving = false }
        do {
            existingId = nil
            let detail: HospDetail = try await API.post("/provider-hospital/hospitalizations", body: body)
            announceDataChanged()
            roomFull = nil
            overriding = false
            if let failed = detail.consentError { Toast.error(LF("The estimate could not be sent to sign: %@", failed)) }
            let name = detail.patient?.name ?? patientName
            let consentId = detail.consentRequest?.consentId
            let signsHere = consentId != nil && (body["notifyFamily"] as? Bool) == false && detail.status == "pending"
            if detail.status == "admitted" {
                Toast.show(detail.client?.onPawMiaw == true ? LF("%@ is in the hospital. The family has been told.", name) : LF("%@ is in the hospital.", name))
            } else if detail.admitError?.code == "room_full" {
                Toast.show(LF("%@ is waiting for admission: the ward is full.", name))
            } else if detail.admitError?.code == "consent_required" || detail.admitError?.code == "deposit_required" {
                if !signsHere { Toast.show([LF("%@ is waiting for admission.", name), waitsOn(detail.gate)].compactMap { $0 }.joined(separator: " ")) }
            } else if let refusal = detail.admitError {
                Toast.show(LF("%@ is waiting for admission.", name) + " " + hospRefusalText(code: refusal.code, error: refusal.error, fallback: "Could not admit the patient."))
            } else {
                Toast.show(LF("%@ is waiting for admission.", name))
            }
            dismiss()
            onCreated(HospOpened(id: detail.id, signConsentId: signsHere ? consentId : nil, admitAfterSigning: admitNow))
        } catch {
            // A refusal keeps its body: `already_hospitalized` names the hospitalization to open instead.
            let failure: Error = error
            if (failure as? APIError)?.code == "room_full" {
                if roomFull == nil { roomFull = hospError(failure) } else { throw hospRefusal(failure, fallback: "Could not admit the patient.") }
                return
            }
            if (failure as? APIError)?.code == "already_hospitalized", let existing = (failure as? APIError)?.body?["hospitalizationId"]?.string {
                existingId = existing
                roomFull = nil
                overriding = false
                Toast.error(hospError(failure, fallback: "Could not admit the patient."))
                return
            }
            if !overriding && roomFull == nil {
                form.apply(hospRefusal(failure, fallback: "Could not admit the patient."), known: ["reason": "reason", "estimateAmount": "estimate", "depositAmount": "deposit"])
            }
            throw hospRefusal(failure, fallback: "Could not admit the patient.")
        }
    }

    /// What a patient saved as waiting still needs, in a line.
    private func waitsOn(_ gate: HospGate?) -> String? {
        let consent = gate?.consent?.required == true && gate?.consent?.satisfied != true
        let deposit = gate?.deposit?.satisfied != true
        if consent && deposit { return L("The estimate needs signing and the deposit paying.") }
        if consent { return L("The estimate needs signing.") }
        if deposit { return L("The deposit needs paying.") }
        return nil
    }
}

