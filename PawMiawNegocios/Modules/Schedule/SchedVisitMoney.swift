//
//  SchedVisitMoney.swift
//  PawMiawNegocios
//
//  The hospital from a visit (the emergency deposit is the shared
//  DepositSheet): hospitalizing the visit's patient
//  (web hospital/admit-sheet.tsx with the visit's preset): why and where,
//  the estimate the family signs and the deposit, admitted now or waiting.
//

import SwiftUI

// MARK: - Hospitalize from the visit

/// The visit's patient, with what the triage said: why and where, then the estimate and the deposit.
struct SchedAdmitPreset: Identifiable {
    let id = UUID()
    let appointmentId: String
    let clientName: String
    let familyOnApp: Bool
    let petId: String
    let petName: String
    var priority: String? = nil
    var reason: String? = nil
}

struct SchedAdmitSheet: View {
    let preset: SchedAdmitPreset
    /// The hospitalization made: its page opens next.
    let onCreated: (String) -> Void

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
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
    @State private var members: [HospMember] = []
    @State private var wards: [HospRoom] = []
    @State private var occupied: [String: Int] = [:]
    @State private var roomFull: String?
    @State private var overriding = false
    @State private var prepared = false
    @State private var saving = false

    private var vets: [HospMember] { members.filter { $0.can(.hospitalManage) } }
    private var me: HospMember? { members.first { $0.isCurrentMember == true } }
    private var hasEstimate: Bool { (estimate ?? 0) > 0 }
    private var owesDeposit: Bool { (deposit ?? 0) > 0 && !(emergency && priority == "critical") }
    private var gated: Bool { hasEstimate || owesDeposit }
    private var room: HospRoom? { wards.first { $0.id == roomId } }

    /// The web's two steps for a visit's patient (the patient is already known): why and where, then the money.
    @State private var step = 0

    var body: some View {
        ProviderModal(title: LF("Hospitalize %@", preset.petName), subtitle: L("It waits for the signed estimate and the deposit, then is admitted."),
                      systemImage: "bed-double", accent: .pink, isDirty: prepared && (!reason.isEmpty || estimate != nil || deposit != nil), form: form,
                      primaryTitle: step == 0 ? L("Continue") : primaryTitle, isWorking: saving,
                      steps: ModalSteps(steps: [(L("Why and where"), "stethoscope"), (L("Estimate and deposit"), "wallet")], current: step),
                      onBack: step > 0 ? { step = 0 } : nil,
                      secondaryActions: step == 1 && admitNow && workspace.isOwnerOrAdmin && gated
                        ? [ModalAction(L("Admit without the gate"), tint: Theme.destructive) { if validate() { overriding = true } }] : [],
                      primaryIcon: step == 0 ? nil : "bed-double") {
            if step == 0 {
                guard form.check([("reason", reason.nonEmpty == nil ? L("Say why the patient is hospitalized.") : nil)]) else { return }
                step = 1
                return
            }
            guard validate() else { return }
            Task { try? await submit(extra: [:]) }
        } content: {
            ContextPills(client: preset.clientName, pets: [preset.petName]) {
                if step == 1 {
                    if emergency { contextPill(priority.map(HospWords.triage) ?? L("Emergency"), icon: "siren") }
                    if let place = [room?.name, cageLabel.nonEmpty].compactMap({ $0?.nonEmpty }).joined(separator: " · ").nonEmpty { contextPill(place, icon: "bed-double") }
                    if let vet = vets.first(where: { $0.id == attendingId }) { contextPill(vet.label, icon: "stethoscope") }
                }
            }
            if step == 0 { whyStep } else { moneyStep }
        }
        .task { await prepare() }
        .sheet(isPresented: Binding(get: { roomFull != nil }, set: { if !$0 { roomFull = nil } })) {
            ConfirmSheet(title: L("Place the patient anyway?"), message: roomFull, confirmTitle: L("Place anyway"), destructive: true) { _ in
                try await submit(extra: ["allowOverCapacity": true])
            }
        }
        .sheet(isPresented: $overriding) {
            ConfirmSheet(title: L("Admit without the signed estimate or the deposit?"), message: L("Only owners and admins can. It is written down with your name and the reason."),
                         confirmTitle: L("Admit anyway"), destructive: true, askReason: true, reasonRequired: true, cancelTitle: L("Not now")) { reason in
                try await submit(extra: ["admitNow": true, "overrideConsent": true, "overrideDeposit": true, "overrideReason": reason ?? ""])
            }
        }
    }

    @ViewBuilder private var whyStep: some View {
        ModalSection(title: L("Why"), required: true) {
            SchedBareField(prompt: L("e.g. Gastroenteritis, dehydrated — IV fluids and monitoring"), text: $reason, key: "reason", form: form)
            ToggleRow(title: L("Emergency"), subtitle: L("A critical emergency is never held back by the deposit."), isOn: $emergency)
            if emergency {
                PillPicker(options: HospWords.priorities.map { ($0, HospWords.triage($0)) }, choice: $priority)
            }
        }
        ModalSection(title: L("Where and who")) {
            if wards.isEmpty {
                NoticeCard(tone: .info, title: L("No wards set up yet"), message: L("Admit them without a place and place them from the ward later. Write the cage or bed below if you know it."), icon: "bed-double")
            } else {
                MenuField(label: L("Ward or cage"), options: [("", L("Not placed yet"))] + wards.map { ward in
                    (ward.id, LF("%@ · %@ of %@", ward.name ?? "", String(occupied[ward.id] ?? 0), String(ward.capacity ?? 0)))
                }, selection: $roomId)
                if let room, (occupied[room.id] ?? 0) >= (room.capacity ?? 0) {
                    Text(LF("%@ is full.", room.name ?? "")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.goldText)
                }
            }
            PMTextField(L("Cage or bed"), text: $cageLabel, prompt: L("e.g. C3"))
            MenuField(label: L("Attending vet"), options: attendingOptions, selection: $attendingId)
        }
    }

    @ViewBuilder private var moneyStep: some View {
        ModalSection(title: L("Estimate and deposit"), subtitle: L("The family signs the estimate before the patient is admitted; the deposit stays as credit and is spent on the bill.")) {
            MoneyField(label: L("Estimate"), cents: $estimate, key: "estimate", form: form)
            MoneyField(label: L("Deposit"), cents: $deposit, key: "deposit", form: form)
            if hasEstimate {
                VStack(alignment: .leading, spacing: 8) {
                    Text(LF("The family signs an estimate of %@.", Money.format(estimate ?? 0, currency: nil))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    PillPicker(
                        options: (preset.familyOnApp ? [("family", L("Send it to the family’s app"))] : []) + [("here", L("Sign here, on this device"))],
                        choice: Binding(get: { signHere ? "here" : "family" }, set: { signHere = $0 == "here" })
                    )
                }
            } else {
                Text(L("No estimate: nothing to sign.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
        ToggleRow(title: L("Admit now"), subtitle: admitNowHint, isOn: $admitNow)
        PMTextField(L("Internal note"), text: $internalNote, prompt: L("Only the team sees it."), multiline: true)
    }

    /// A soft pill after the client and the pet (the triage, the place, the vet), as ContextPills draws them.
    private func contextPill(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Glyph(icon, size: 14)
            Text(text).lineLimit(1)
        }
        .font(.brandText(12, weight: .semibold))
        .foregroundStyle(Theme.inkStrong)
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(Theme.surfaceMuted, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    private var primaryTitle: String {
        if !admitNow { return L("Save as waiting") }
        if !gated { return L("Admit") }
        return hasEstimate && signHere ? L("Save and sign") : L("Save and wait")
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

    private func prepare() async {
        guard !prepared else { return }
        reason = preset.reason ?? ""
        emergency = preset.priority != nil
        priority = preset.priority
        signHere = !preset.familyOnApp
        prepared = true
        async let loadedMembers = HospAPI.members()
        async let loadedWards = HospAPI.wards(locationId: Workspace.shared.locationId)
        let board: HospBoard? = try? await API.get("/provider-hospital/board", query: ["locationId": Workspace.shared.locationId])
        members = await loadedMembers
        wards = await loadedWards.filter { $0.status == nil || $0.status == "active" }
        occupied = Dictionary((board?.rooms ?? []).map { ($0.id, $0.occupied ?? 0) }, uniquingKeysWith: { a, _ in a })
        if attendingId.isEmpty, let me, me.can(.hospitalManage) { attendingId = me.id }
    }

    private func validate() -> Bool {
        form.check([
            ("reason", reason.nonEmpty == nil ? L("Say why the patient is hospitalized.") : nil),
            ("deposit", hasEstimate && (deposit ?? 0) > (estimate ?? 0) ? L("The deposit can’t be more than the estimate.") : nil),
        ])
    }

    /// Creates it; a ConfirmSheet's action rethrows so it stays open on a refusal.
    private func submit(extra: [String: Any?]) async throws {
        var body: [String: Any?] = [
            "providerClientPetId": preset.petId,
            "appointmentId": preset.appointmentId,
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
        if hasEstimate { body["notifyFamily"] = !signHere }
        for (key, value) in extra { body[key] = value }
        saving = true
        defer { saving = false }
        do {
            let created: SchedAdmitted = try await SchedAPI.send("POST", "/provider-hospital/hospitalizations", body: body)
            announceDataChanged()
            roomFull = nil
            overriding = false
            let name = created.patient?.name ?? preset.petName
            if let failed = created.consentError { Toast.error(LF("The estimate could not be sent to sign: %@", failed)) }
            if created.status == "admitted" {
                Toast.show(created.client?.onPawMiaw == true ? LF("%@ is in the hospital. The family has been told.", name) : LF("%@ is in the hospital.", name))
            } else if created.admitError?.code == "room_full" {
                Toast.show(LF("%@ is waiting for admission: the ward is full.", name))
            } else {
                Toast.show(LF("%@ is waiting for admission.", name))
            }
            dismiss()
            onCreated(created.id)
        } catch let failure as SchedFailure {
            if failure.code == "room_full" {
                if roomFull == nil { roomFull = failure.api.message; return }
                throw failure.api
            }
            if failure.code == "already_hospitalized", let existing = failure.body?["hospitalizationId"]?.string {
                Toast.error(failure.api.message)
                dismiss()
                onCreated(existing)
                return
            }
            if !overriding && roomFull == nil {
                if form.apply(failure.api, known: ["reason": "reason", "estimateAmount": "estimate", "depositAmount": "deposit"]), form.error("reason") != nil { step = 0 }
                return
            }
            throw failure.api
        } catch {
            if !overriding && roomFull == nil { Toast.error(error); return }
            throw error
        }
    }
}
