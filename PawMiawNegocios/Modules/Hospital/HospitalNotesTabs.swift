//
//  HospitalNotesTabs.swift
//  PawMiawNegocios
//
//  Updates to the family and notes for the team (with a condition and a
//  photo), the vet's daily rounds, and the running bill (web
//  hospital-notes-tabs.tsx). The bill shows for money level 1 and up
//  (backend docs/money-access-levels.md); a line without a price keeps it a
//  draft (docs/charging-flow.md).
//

import PhotosUI
import SwiftUI

// MARK: - Updates

struct HospUpdatesTab: View {
    @ObservedObject var model: HospDetailModel
    let detail: HospDetail
    let canCare: Bool

    @StateObject private var form = FormState()
    @State private var message = ""
    @State private var condition: String?
    @State private var visibility: String?
    @State private var photo = PhotoDraft()
    @State private var sending = false

    private var open: Bool { detail.isAdmitted || detail.isPending }
    private var onApp: Bool { detail.client?.onPawMiaw == true }
    private var toFamily: Bool { (visibility ?? (onApp ? "owner" : "internal")) == "owner" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if canCare && open {
                Card(spacing: 12) {
                    HospCardGroup(title: L("New update"), icon: "message-square-text")
                    PillPicker(
                        options: (onApp ? [("owner", L("To the family"))] : []) + [("internal", L("Team only"))],
                        choice: Binding(get: { visibility ?? (onApp ? "owner" : "internal") }, set: { visibility = $0 })
                    )
                    if !onApp { HospHint(text: L("The family isn’t on PawMiaw: updates stay with the team. Call them.")) }
                    PMTextField(L("Message"), text: $message, key: "message", form: form,
                                prompt: toFamily ? LF("e.g. %@ ate a little and is resting. Fluids continue tonight.", detail.patient?.name ?? L("the patient")) : L("e.g. Watch the IV line; restless after 22:00"),
                                multiline: true)
                    FormField(label: L("Condition (optional)")) {
                        PillPicker(options: HospWords.conditions.map { ($0, HospWords.condition($0)) }, choice: $condition, allowsNone: true)
                    }
                    PhotoField(label: L("Photo"), draft: $photo, allowsRemove: false)
                    PMButton(toFamily ? L("Send to the family") : L("Save note"), systemImage: "send", fullWidth: true, isWorking: sending) { send() }
                }
            }
            if (detail.updates ?? []).isEmpty {
                EmptyState(systemImage: "message-square-text", title: L("No updates yet."), accent: Theme.pink, panel: true)
            }
            ForEach(detail.updates ?? []) { update in
                let teamOnly = update.visibility == "internal"
                VStack(alignment: .leading, spacing: 8) {
                    FlowLayout(spacing: 6) {
                        HStack(spacing: 4) {
                            Glyph(teamOnly ? "eye-off" : "users", size: 14)
                            Text(teamOnly ? L("Team only") : L("Sent to the family"))
                        }
                        .font(Theme.text(12, weight: .bold)).foregroundStyle(teamOnly ? Theme.inkSoft : Theme.blue)
                        Text("· \(update.authorName ?? L("Someone")) · \(HospFmt.dateTime(update.createdAt, detail.zone))").font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        if let condition = update.condition { HospConditionBadge(condition: condition) }
                    }
                    if let text = update.message?.nonEmpty { Text(text).font(Theme.text(14)).foregroundStyle(Theme.inkStrong) }
                    if let url = APIConfig.assetURL(update.photoUrl) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFit() } else { Color.clear.frame(height: 120) }
                        }
                        .frame(maxHeight: 288)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                        .padding(.top, 4)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(teamOnly ? AnyShapeStyle(Theme.surface) : AnyShapeStyle(Theme.wash(Theme.aqua, 8)), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay {
                    if teamOnly {
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    } else {
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1)
                    }
                }
            }
        }
    }

    private func send() {
        guard form.check([("message", message.nonEmpty == nil ? L("Write the update.") : nil)]) else { return }
        let who = toFamily ? "owner" : "internal"
        sending = true
        Task {
            defer { sending = false }
            do {
                if let photo = photo.data {
                    var fields = ["message": message.nonEmpty ?? "", "visibility": who]
                    if let condition { fields["condition"] = condition }
                    let _: HospDetail = try await ImageUpload.upload(photo, to: HospAPI.detailPath(detail.id) + "/updates", fields: fields)
                    announceDataChanged()
                    await model.load()
                } else {
                    try await model.write("/updates", body: ["message": message.nonEmpty, "condition": condition, "visibility": who])
                }
                Toast.show(who == "owner" ? L("Sent to the family.") : L("Note saved for the team."))
                message = ""
                condition = nil
                photo = PhotoDraft()
            } catch {
                Toast.error(hospError(error, fallback: "Could not send it."))
            }
        }
    }
}

// MARK: - Rounds

struct HospRoundsTab: View {
    @ObservedObject var model: HospDetailModel
    let detail: HospDetail
    let canManage: Bool

    @State private var picked = ""
    @State private var note = ""
    @State private var signing = false

    private var unsigned: [String] {
        let signed = Set((detail.rounds ?? []).compactMap(\.day))
        let today = detail.sheet?.today ?? ""
        return (detail.sheet?.days ?? []).filter { $0 <= today && !signed.contains($0) }
    }

    /// The newest day still to sign, unless another was picked (and is still unsigned).
    private var day: String { unsigned.contains(picked) ? picked : (unsigned.last ?? detail.sheet?.today ?? "") }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if canManage && detail.isAdmitted && !unsigned.isEmpty {
                Card(spacing: 12) {
                    HospCardGroup(title: L("Sign rounds"), icon: "shield-check")
                    MenuField(label: L("Day"), options: unsigned.map { entry in
                        (entry, entry == detail.sheet?.today ? LF("Today · %@", HospFmt.day(entry, zone: detail.zone)) : HospFmt.day(entry, zone: detail.zone))
                    }, selection: Binding(get: { day }, set: { picked = $0 }))
                    PMTextField(L("Note"), text: $note, prompt: L("e.g. Stable, eating; continue fluids 24 h, recheck bloodwork tomorrow"), optional: true, multiline: true)
                    PMButton(L("Sign rounds"), systemImage: "shield-check", fullWidth: true, isWorking: signing) { sign() }
                }
            }
            if (detail.rounds ?? []).isEmpty {
                EmptyState(systemImage: "shield-check", title: L("No rounds signed yet."), accent: Theme.pink, panel: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(detail.rounds ?? []) { round in
                    Card(flat: true) {
                        HStack(alignment: .top, spacing: 12) {
                            Glyph("shield-check", size: 20).foregroundStyle(Theme.blue)
                                .frame(width: 40, height: 40).background(Theme.wash(Theme.lime, 40), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(HospFmt.day(round.day, style: .long, zone: detail.zone)).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                                Text(LF("Signed by %@ · %@", round.signedByName ?? L("a vet"), HospFmt.dateTime(round.signedAt, detail.zone))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                                if let note = round.note?.nonEmpty { Text(note).font(Theme.text(14)).foregroundStyle(Theme.inkStrong).padding(.top, 4) }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private func sign() {
        let chosen = day
        signing = true
        Task {
            defer { signing = false }
            do {
                try await model.write("/rounds", body: ["day": chosen, "note": note.nonEmpty])
                Toast.show(LF("Rounds signed for %@.", HospFmt.day(chosen, zone: detail.zone)))
                note = ""
                picked = ""
            } catch {
                Toast.error(hospError(error, fallback: "Could not sign the rounds."))
            }
        }
    }
}

// MARK: - The running bill

struct HospBillTab: View {
    let detail: HospDetail
    let canManage: Bool

    var body: some View {
        if let bill = detail.bill {
            let currency = bill.currency ?? detail.money
            let total = bill.totalAmount ?? 0
            let deposits = bill.depositsPaid ?? 0
            let balance = max(0, total - deposits)
            let taxOnTop = bill.pricesIncludeTax == false
            let againstEstimate = taxOnTop ? total - (bill.taxAmount ?? 0) : total
            let open = detail.isAdmitted || detail.isPending
            let consent = detail.gate?.consent
            let signedAmount = consent?.status == "signed" ? (consent?.amountCents ?? (consent?.satisfied == true ? detail.estimateAmount : nil)) : nil
            let lines = bill.lines ?? []
            let unpriced = lines.filter(\.needsPrice).count
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)], spacing: 16) {
                SectionCard(title: L("Running bill"), trailing: {
                    if let invoiceId = bill.invoiceId {
                        NavigationLink(value: ProviderRoute.invoice(invoiceId)) {
                            HStack(spacing: 6) {
                                Glyph("receipt", size: 16)
                                Text(L("Open the bill"))
                            }
                        }
                        .buttonStyle(.pm(.outline, size: .header))
                    }
                }) {
                    if lines.isEmpty {
                        EmptyState(systemImage: "receipt", title: detail.isPending ? L("The bill opens at admission.") : L("Nothing charged yet."), accent: Theme.pink)
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            if index > 0 { RowDivider() }
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lineLabel(line.label ?? "")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                                    if line.needsPrice { Chip(text: L("Needs a price"), tone: .custom(Theme.mango), dot: Theme.mango, percent: 18) }
                                    if let description = line.description?.nonEmpty { Text(lineDescription(description)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                                }
                                Spacer(minLength: 6)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Money.format(Int(((line.quantity ?? 1) * Double(line.unitAmount ?? 0)).rounded()), currency: currency)).font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                                    Text("\(HospFmt.number(line.quantity ?? 1)) × \(Money.format(line.unitAmount, currency: currency))").font(Theme.text(12)).monospacedDigit().foregroundStyle(Theme.inkSoft)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }
                    if unpriced > 0 {
                        RowDivider()
                        HStack(alignment: .top, spacing: 6) {
                            Glyph("triangle-alert", size: 14).foregroundStyle(Theme.mango).padding(.top, 1)
                            Text(unpriced == 1
                                 ? L("A line has no price: the bill can’t be charged until it has one, or is marked a courtesy.")
                                 : LF("%d lines have no price: the bill can’t be charged until they have one, or are marked a courtesy.", unpriced))
                        }
                        .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.wash(Theme.mango, 14))
                    }
                }
                Card(spacing: 12) {
                    amountRow(L("Total so far"), Money.format(total, currency: currency), strong: true)
                    amountRow(L("Deposits paid"), "− \(Money.format(deposits, currency: currency))")
                    amountRow(L("Still to pay"), Money.format(balance, currency: currency), strong: true)
                    if let estimate = detail.estimateAmount, estimate > 0 {
                        amountRow(taxOnTop ? L("Estimate (before tax)") : L("Estimate (tax included)"), Money.format(estimate, currency: currency))
                        if let signedAmount { amountRow(L("Signed by the family"), Money.format(signedAmount, currency: currency)) }
                    }
                    if consent?.required == true && consent?.satisfied != true {
                        billNote(consent?.reason == "amount_changed"
                            ? L("The estimate went up after it was signed: the family signs the new amount.")
                            : L("The family hasn’t signed this estimate yet."))
                    }
                    if let estimate = detail.estimateAmount, estimate > 0, againstEstimate > estimate {
                        billNote(taxOnTop
                            ? LF("Over the estimate before tax (%@): tell the family and raise it (they sign again).", Money.format(againstEstimate, currency: currency))
                            : L("Over the estimate: tell the family and raise it (they sign again)."))
                    }
                    if let fee = bill.dailyFee {
                        Text(LF("Daily fee: %@, %@ a day.", fee.name ?? "", Money.format(fee.unitAmount, currency: currency))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    } else if open {
                        // No daily fee: the days in the hospital are not charged until one is chosen.
                        (Text(L("No daily fee: the days in the hospital aren’t charged.")).foregroundStyle(Theme.inkSoft)
                            + Text(canManage ? " " + L("Choose one in Settings") : "").bold().foregroundStyle(Theme.blue))
                            .font(Theme.text(12))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    if let earlier = bill.earlierBills, !earlier.isEmpty {
                        RowDivider()
                        Text(L("Earlier bills").uppercased()).font(Theme.text(12, weight: .bold)).tracking(1.44).foregroundStyle(Theme.inkSoft)
                        ForEach(earlier) { entry in
                            NavigationLink(value: ProviderRoute.invoice(entry.id)) {
                                HStack {
                                    StatusChip(text: HospWords.invoiceStatus(entry.status), state: ProviderState.invoice(entry.status))
                                    Spacer()
                                    Text(Money.format(entry.totalAmount, currency: currency)).font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                                    Glyph("chevron-right", size: 14).foregroundStyle(Theme.inkSoft)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !open && bill.invoiceId != nil { Text(L("The bill stays a draft for the desk to check and send.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                }
            }
        } else {
            HospHint(text: L("You don’t see billing."))
        }
    }

    /// A mango note in the totals (web: rounded-chip, mango 22%).
    private func billNote(_ text: String) -> some View {
        Text(text).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkStrong)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wash(Theme.mango, 22), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
    }

    private func amountRow(_ label: String, _ value: String, strong: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            Spacer()
            Text(value).font(strong ? .brandHeading(20, relativeTo: .title3) : Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
        }
    }

    /// The server's own English lines ("Boarding — Toby"), said in the reader's words.
    private func lineLabel(_ label: String) -> String {
        if label == "No-show fee" { return L("No-show fee") }
        if label == "Late cancellation fee" { return L("Late cancellation fee") }
        for (english, word) in [("Boarding", L("Boarding")), ("Daycare", L("Daycare")), ("Home sitting", L("Home sitting")), ("Home visits", L("Home visits"))] {
            if label.hasPrefix(english + " — ") { return word + " — " + String(label.dropFirst(english.count + 3)) }
        }
        return label
    }

    private func lineDescription(_ description: String) -> String {
        if description == "Hospital days" { return L("Hospital days") }
        if description == "To take home" { return L("To take home") }
        return description
    }
}
