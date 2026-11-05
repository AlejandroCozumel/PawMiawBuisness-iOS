//
//  HospitalPlacement.swift
//  PawMiawNegocios
//
//  Where the patient is and who looks after it (web
//  hospital-placement-sheet.tsx). The deposit, signing the estimate or the
//  euthanasia consent and the PDFs are the shared DepositSheet,
//  ConsentSignSheet and Quick Look download.
//

import SwiftUI

// MARK: - Ward, vet and estimate

struct HospPlacementSheet: View {
    @ObservedObject var model: HospDetailModel
    let detail: HospDetail

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var wards: [HospRoom] = []
    @State private var occupied: [String: Int] = [:]
    @State private var members: [HospMember] = []
    @State private var roomId = ""
    @State private var cageLabel = ""
    @State private var attendingId = ""
    @State private var reason = ""
    @State private var priority: String?
    @State private var estimate: Int?
    @State private var deposit: Int?
    @State private var note = ""
    @State private var saving = false
    @State private var roomFull: String?
    @State private var filled = false

    var body: some View {
        ProviderModal(
            title: LF("Change %@’s stay", detail.patient?.name ?? L("the patient")),
            subtitle: L("Ward, attending vet, reason, triage, estimate and deposit."),
            systemImage: "pencil",
            accent: .pink,
            isDirty: filled && patch().count > 0,
            form: form,
            primaryTitle: L("Save"),
            isWorking: saving,
            primaryIcon: "save"
        ) {
            Task { try? await save(allowOverCapacity: false) }
        } content: {
            MenuField(label: L("Ward or cage"), options: [("", L("Not placed yet"))] + wards.map { ward in
                (ward.id, LF("%@ · %d of %d", ward.name ?? "", occupied[ward.id] ?? 0, ward.capacity ?? 0))
            }, selection: $roomId)
            PMTextField(L("Cage or bed"), text: $cageLabel)
            MenuField(label: L("Attending vet"), options: [("", "—")] + members.filter { $0.can(.hospitalManage) }.map { ($0.id, $0.label) }, selection: $attendingId)
            // The web's "Why" part between stitched rules: the reason, then the triage.
            StitchedDivider().padding(.vertical, 4)
            PMTextField(L("Why"), text: $reason, key: "reason", form: form, multiline: true)
            FormField(label: L("Triage")) {
                PillPicker(options: HospWords.priorities.map { ($0, HospWords.triage($0)) }, choice: $priority, allowsNone: true)
            }
            StitchedDivider().padding(.vertical, 4)
            MoneyField(label: L("Estimate"), cents: $estimate, key: "estimate", form: form, optional: true)
            MoneyField(label: L("Deposit"), cents: $deposit, key: "deposit", form: form, optional: true)
            HospHint(text: L("Raising the estimate after it was signed asks the family to sign the new amount."))
            PMTextField(L("Internal note"), text: $note, prompt: L("Only the team sees it."), multiline: true)
        }
        .task { await prepare() }
        .sheet(isPresented: Binding(get: { roomFull != nil }, set: { if !$0 { roomFull = nil } })) {
            ConfirmSheet(title: L("Place the patient anyway?"), message: roomFull, confirmTitle: L("Place anyway"), destructive: true) { _ in
                try await save(allowOverCapacity: true)
            }
        }
    }

    private func prepare() async {
        if !filled {
            roomId = detail.room?.id ?? ""
            cageLabel = detail.cageLabel ?? ""
            attendingId = detail.attending?.id ?? ""
            reason = detail.reason ?? ""
            priority = detail.triagePriority
            estimate = detail.estimateAmount
            deposit = (detail.depositAmount ?? 0) > 0 ? detail.depositAmount : nil
            note = detail.internalNote ?? ""
            filled = true
        }
        async let loadedWards = HospAPI.wards(locationId: detail.locationId)
        async let loadedMembers = HospAPI.members()
        let board: HospBoard? = try? await API.get("/provider-hospital/board", query: ["locationId": Workspace.shared.locationId])
        wards = await loadedWards.filter { $0.status == nil || $0.status == "active" || $0.id == detail.room?.id }
        members = await loadedMembers
        occupied = Dictionary((board?.rooms ?? []).map { ($0.id, $0.occupied ?? 0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Only what changed.
    private func patch() -> [String: Any?] {
        var out: [String: Any?] = [:]
        if roomId.nonEmpty != detail.room?.id { out["roomId"] = roomId.nonEmpty }
        if cageLabel.nonEmpty != detail.cageLabel?.nonEmpty { out["cageLabel"] = cageLabel.nonEmpty }
        if attendingId.nonEmpty != detail.attending?.id { out["attendingMemberId"] = attendingId.nonEmpty }
        if (reason.nonEmpty ?? "") != (detail.reason ?? "") { out["reason"] = reason.nonEmpty }
        if priority != detail.triagePriority { out["triagePriority"] = priority }
        if estimate != detail.estimateAmount { out["estimateAmount"] = estimate }
        if (deposit ?? 0) != (detail.depositAmount ?? 0) { out["depositAmount"] = deposit ?? 0 }
        if note.nonEmpty != detail.internalNote?.nonEmpty { out["internalNote"] = note.nonEmpty }
        return out
    }

    private func save(allowOverCapacity: Bool) async throws {
        guard form.check([
            ("reason", reason.nonEmpty == nil ? L("Say why the patient is hospitalized.") : nil),
            ("deposit", (estimate ?? 0) > 0 && (deposit ?? 0) > (estimate ?? 0) ? L("The deposit can’t be more than the estimate.") : nil),
        ]) else { return }
        var body = patch()
        if body.isEmpty { dismiss(); return }
        if allowOverCapacity { body["allowOverCapacity"] = true }
        saving = true
        defer { saving = false }
        do {
            try await model.write("", method: "PATCH", body: body)
            let raised = (estimate ?? 0) > (detail.estimateAmount ?? 0) && body["estimateAmount"] != nil && detail.isPending
            Toast.show(raised ? L("Saved. The family signs the new estimate.") : L("Saved."))
            roomFull = nil
            dismiss()
        } catch {
            if (error as? APIError)?.code == "room_full", !allowOverCapacity { roomFull = hospError(error); return }
            if !allowOverCapacity { form.apply(hospRefusal(error, fallback: "Could not save."), known: ["reason": "reason", "estimateAmount": "estimate", "depositAmount": "deposit"]) }
            throw hospRefusal(error, fallback: "Could not save.")
        }
    }
}
