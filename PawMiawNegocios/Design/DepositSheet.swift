//
//  DepositSheet.swift
//  PawMiawNegocios
//
//  "Take a deposit" (web visits/visit-money-sheets.tsx DepositSheet;
//  docs/hospitalization.md, docs/money-access-levels.md): an amount, how they
//  paid and its reference, into the shift open at THIS device's register
//  (Money's CashDeviceRegister and CashRegisterGate, which opens a closed
//  register in place). It stays as credit on the client's account, tied to
//  the act it is for — a visit, a stay or a hospitalization — and is spent on
//  its bill. One request per opening (`clientRequestId`): a double tap or a
//  retry never takes it twice. Once taken, the receipt's PDF is offered (or the
//  sheet closes at once when a gate goes straight on).
//  Used by the visit page and the start gate (Schedule), a home stay's confirm
//  (Stays) and the hospital's admission gate (Hospital).
//

import SwiftUI

struct DepositTaken: Decodable {
    let id: String?
    let folio: String?
    let creditBalance: Int?
}

struct DepositSheet: View {
    let clientId: String
    let clientName: String
    /// The act it is for (one of them, or none for plain credit).
    var appointmentId: String? = nil
    var stayId: String? = nil
    var hospitalizationId: String? = nil
    /// What is still owed, filled in (cents).
    var owed: Int? = nil
    var currency: String? = nil
    /// The line under the title ("Emergency deposit · Luna").
    var label: String? = nil
    /// What happens to the money, said once (the default names the bill).
    var explanation: String? = nil
    /// A walk-in not created yet: the deposit goes with it (the payment's body), and the start with them.
    var takeWith: (([String: Any?]) async throws -> Void)? = nil
    /// Close at once when taken (a gate goes straight on) instead of showing the receipt.
    var closesWhenTaken: Bool = false
    var onTaken: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @StateObject private var device = CashDeviceRegister()
    @StateObject private var form = FormState()
    @State private var amount: Int?
    @State private var method = "card"
    @State private var reference = ""
    @State private var working = false
    @State private var requestId = cashRequestId()
    @State private var taken: DepositTaken?

    private var said: String {
        if let explanation { return explanation }
        if takeWith != nil {
            return L("The visit is checked in, the deposit goes on it as credit on their account, and treatment starts. If they leave, it stays their credit until it is used or refunded.")
        }
        return L("It stays as credit on their account and is used when they pay the bill.")
    }

    var body: some View {
        ProviderModal(
            title: taken == nil ? L("Take a deposit") : L("Deposit taken"),
            subtitle: label ?? clientName,
            systemImage: "banknote.fill",
            accent: .mint,
            isDirty: taken == nil && (amount != owed || !reference.isEmpty),
            form: form,
            primaryTitle: taken != nil ? L("Done") : (takeWith != nil ? L("Take deposit and start") : L("Take deposit")),
            isWorking: working,
            cancelTitle: taken == nil ? L("Cancel") : L("Close"),
            onPrimary: { if taken == nil { submit() } else { dismiss() } }
        ) {
            if let taken {
                NoticeCard(tone: .success, title: LF("Deposit %@ taken. %@ has %@ of credit.", taken.folio ?? "", clientName, Money.format(taken.creditBalance, currency: currency)))
                if let id = taken.id {
                    DocumentButton(title: L("Download PDF"), path: "/provider-finance/deposits/\(id)/pdf", fileName: taken.folio ?? L("Deposit"), variant: .outline, size: .compact)
                }
            } else {
                Text(said).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                MoneyField(label: L("Amount"), cents: $amount, key: "amount", form: form)
                ModalSection(title: L("How they paid")) {
                    FilterBar(options: CashText.methods.map { (value: $0, title: CashText.method($0), count: nil) }, selection: $method)
                    if method != "cash" {
                        PMTextField(L("Reference"), text: $reference, prompt: L("Reference (authorization, transfer…)"), optional: true)
                    }
                    CashRegisterGate(device: device, wantsCash: method == "cash")
                }
            }
        }
        .modifier(CashKeepsRegister(device: device))
        .onAppear { if amount == nil, let owed, owed > 0 { amount = owed } }
    }

    private func submit() {
        guard form.check([("amount", (amount ?? 0) <= 0 ? L("Enter the deposit amount") : nil)]) else { return }
        if method == "cash" && device.sessionId == nil { Toast.error(L("Open the register to take a cash deposit")); return }
        let payment: [String: Any?] = [
            "amount": amount ?? 0,
            "method": method,
            "reference": method == "cash" ? nil : reference.nonEmpty,
            "registerSessionId": device.sessionId,
            "clientRequestId": takeWith != nil ? nil : requestId,
        ]
        working = true
        Task {
            defer { working = false }
            do {
                var result: DepositTaken?
                if let takeWith {
                    try await takeWith(payment)
                } else {
                    var body = payment
                    body["appointmentId"] = appointmentId
                    body["stayId"] = stayId
                    if let hospitalizationId { body["hospitalizationId"] = hospitalizationId }
                    let answer: DepositTaken = try await API.post("/provider-finance/clients/\(clientId)/deposit", body: body)
                    Toast.show(LF("Deposit %@ taken. %@ has %@ of credit.", answer.folio ?? "", clientName, Money.format(answer.creditBalance, currency: currency)))
                    result = answer
                }
                NotificationCenter.default.post(name: CashDeviceRegister.changed, object: nil)
                announceDataChanged()
                await onTaken()
                if closesWhenTaken || result == nil { dismiss() } else { taken = result }
            } catch {
                if (error as? APIError)?.code == "deposit_required" {
                    Toast.error(L("The deposit hasn’t been paid yet."))
                } else {
                    form.apply(error, known: ["amount": "amount"])
                }
            }
        }
    }
}
