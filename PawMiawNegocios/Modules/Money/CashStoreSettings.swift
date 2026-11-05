//
//  CashStoreSettings.swift
//  PawMiawNegocios
//
//  The Store's settings (web: store/store-settings.tsx): currency and tax,
//  receipts, the register's alert (read here, set in Settings), missed-visit
//  fees, what families see, and a clinic's emergency deposit. Whoever manages
//  billing (`billing.manage`) changes them; everyone else reads them. A
//  clinic also chooses the service added to a visit checked in after hours.
//

import SwiftUI

struct CashStoreSettingsTab: View {
    let settings: CashStoreSettings
    let onSaved: (CashStoreSettings) -> Void
    @EnvironmentObject private var workspace: Workspace
    @StateObject private var form = FormState()
    @State private var draft: CashStoreSettings?
    @State private var currency = ""
    @State private var rate = ""
    @State private var footer = ""
    @State private var feeOn = false
    @State private var lateOn = false
    @State private var lateHours = ""
    @State private var depositOn = false
    @State private var depositPercent = ""
    @State private var emergencyOn = false
    @State private var surchargeId = ""
    @State private var services: [CashCatalogItem] = []
    @State private var working = false

    private var canEdit: Bool { workspace.can(.billingManage) }
    private var isClinic: Bool { workspace.offers(.vet, .emergency) }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var baseline = ""
    @State private var justSaved = false

    private static let currencies = ["MXN", "USD", "COP", "EUR", "ARS", "CLP", "PEN", "GTQ", "CRC"]

    /// What the form holds now, to tell when something changed (the save bar shows then).
    private var signature: String {
        [currency, rate, "\(draft?.pricesIncludeTax ?? false)", footer, "\(draft?.emailReceipts != false)", "\(feeOn)", "\(draft?.noShowFeeAmount ?? 0)",
         "\(lateOn)", lateHours, "\(draft?.showPricesToFamilies ?? false)", "\(depositOn)", depositPercent, "\(emergencyOn)",
         "\(draft?.emergencyDepositAmount ?? 0)", surchargeId].joined(separator: "|")
    }
    private var dirty: Bool { draft != nil && signature != baseline }

    var body: some View {
        FormScroll(form: form) {
            VStack(alignment: .leading, spacing: 16) {
                if !canEdit {
                    HStack(spacing: 8) {
                        Glyph("lock", size: 16)
                        Text(L("You can read these settings. Only someone who manages billing can change them."))
                    }
                    .font(Theme.text(14, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
                if draft != nil {
                    // Two columns on a wide screen: money and the receipt on the left, the rules around visits on the right.
                    if sizeClass == .regular {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) { leftPanels }.frame(maxWidth: .infinity)
                            VStack(spacing: 16) { rightPanels }.frame(maxWidth: .infinity)
                        }
                    } else {
                        leftPanels
                        rightPanels
                    }
                    if canEdit && (dirty || justSaved || working) { saveBar }
                }
            }
        }
        .onAppear { start(settings) }
        .onChange(of: signature) { _, _ in if dirty { justSaved = false } }
        .task {
            guard isClinic else { return }
            let page: Page<CashCatalogItem>? = try? await API.get("/provider-catalog", query: ["limit": "100", "offset": "0", "itemType": "service", "active": "true"])
            services = (page?.items ?? []).filter { $0.itemType == "service" && $0.active }
        }
    }

    // MARK: Panels (web `SettingsPanel`, one card each)

    @ViewBuilder private var leftPanels: some View {
        panel(L("Prices and tax"), L("The currency everything is charged in and the tax on what you sell."), icon: "badge-percent", accent: Theme.mango) {
            if settings.currencyLocked == true {
                FormField(label: L("Currency")) {
                    HStack(spacing: 6) {
                        Glyph("lock", size: 14).foregroundStyle(Theme.inkSoft)
                        Text(settings.currency).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fieldChrome()
                }
            } else {
                MenuField(label: L("Currency"), options: Array(NSOrderedSet(array: [currency] + Self.currencies)).compactMap { $0 as? String }.map { (value: $0, title: $0) },
                          selection: $currency, key: "currency", form: form)
            }
            PMTextField(L("Standard tax rate (%)"), text: $rate, key: "rate", form: form, hint: L("In Mexico, IVA is 16%."), keyboard: .decimalPad)
            if settings.currencyLocked == true {
                currencyLockNote
            } else {
                Text(L("The currency is the whole business’s: the Catalog, bills, stays and sales. Changing it relabels prices without converting them, and the first bill fixes it.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            Text(L("Everything uses the standard rate unless you mark it zero-rated or exempt in the Catalog.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            ToggleRow(title: L("Shelf prices include tax"), subtitle: draft?.pricesIncludeTax == true ? L("The price on the shelf is what the customer pays; the receipt shows the tax inside it.") : L("Tax is added on top at the counter."), isOn: bind(\.pricesIncludeTax, false))
        }
        panel(L("Receipts"), L("What every receipt says at the end, and whether it is emailed."), icon: "receipt-text", accent: Theme.aqua) {
            PMTextField(L("Receipt footer"), text: $footer, prompt: L("e.g. Thank you! Returns within 7 days with this receipt."), hint: L("Printed at the end of every receipt: a thank-you, your returns policy."), optional: true, multiline: true)
            ToggleRow(title: L("Email receipts to clients"), subtitle: draft?.emailReceipts != false ? L("Every payment sends its receipt, PDF attached, to the client’s email. Clients without an email get none; you can type one when charging.") : L("Receipts are only emailed when someone turns it on while charging."), isOn: Binding(get: { draft?.emailReceipts != false }, set: { draft?.emailReceipts = $0 }))
        }
        panel(L("Register"), L("What happens when a close doesn’t match the count. It is set with the business’s money rules."), icon: "wallet", accent: ProviderState.done.color) {
            (Text("\(L("Cash difference alert")): ").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                + Text((settings.cashDifferenceAlertAmount ?? 0) > 0 ? LF("a register close off by more than %@ needs a note, and the owners are told.", cashMoney(settings.cashDifferenceAlertAmount, settings.currency)) : L("off.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft))
            NavigationLink(value: ProviderRoute.section(.settings)) {
                Text(L("Change it in Settings → Region and money")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue).frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var rightPanels: some View {
        panel(L("Missed visits"), L("A fee for a no-show, and for cancelling too late."), icon: "calendar-x-2", accent: Theme.pink) {
            ToggleRow(title: L("Fee for a missed visit"), subtitle: L("Offered when someone marks a no-show. Whoever marks it decides to charge or waive it, with a reason."), isOn: $feeOn)
            if feeOn {
                MoneyField(label: LF("Fee (%@)", currency.nonEmpty ?? settings.currency), cents: bindOptional(\.noShowFeeAmount), key: "fee", form: form)
                ToggleRow(title: L("Late cancellations too"), subtitle: lateOn ? L("Cancelling close to the visit is offered the same fee.") : L("Only no-shows are offered the fee."), isOn: $lateOn)
                if lateOn {
                    inlineNumber($lateHours, key: "hours", label: L("Hours before the visit"), after: L("hours or less before the visit"))
                    Text(L("Families who book online cancel by themselves until this window; it is also shown in Availability.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        panel(L("Families in the app"), L("What families see about prices when they book or ask for a stay."), icon: "smartphone", accent: Theme.lavender) {
            ToggleRow(title: L("Show prices when they book"), subtitle: L("Each service shows its Catalog price next to its length. Off: families see only the service and how long it takes."), isOn: Binding(get: { draft?.showPricesToFamilies ?? false }, set: { draft?.showPricesToFamilies = $0 }))
            ToggleRow(title: L("Ask for a deposit on stays"), subtitle: L("Families asking for a hotel or daycare stay are told before they send it. You take the deposit yourself once you confirm."), isOn: $depositOn)
            if depositOn {
                inlineNumber($depositPercent, key: "deposit", label: L("Deposit (%)"), after: L("% of the stay’s price"))
            }
        }
        if isClinic {
            panel(L("Emergencies"), L("The deposit an emergency starts with, and the charge for coming after hours."), icon: "heart-pulse", accent: Theme.coral) {
                ToggleRow(title: L("Emergency deposit"), subtitle: L("A triaged emergency starts treatment once it is paid. A critical patient never waits for it; owners and admins can start anyway, with a reason."), isOn: $emergencyOn)
                if emergencyOn {
                    MoneyField(label: LF("Deposit (%@)", settings.currency), cents: bindOptional(\.emergencyDepositAmount), key: "emergency", form: form)
                }
                MenuField(label: L("After-hours surcharge"),
                          options: [(value: "", title: L("No surcharge"))]
                            + services.map { (value: $0.id, title: "\($0.name) · \(cashMoney($0.defaultUnitAmount, $0.currency))") }
                            + (surchargeId.isEmpty || services.contains { $0.id == surchargeId } ? [] : [(value: surchargeId, title: L("The current service"))]),
                          selection: $surchargeId, key: "surcharge", form: form)
                Text(L("A catalog service added once to a visit checked in outside the location’s hours.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func panel<Content: View>(_ title: String, _ subtitle: String, icon: String, accent: Color, @ViewBuilder content: @escaping () -> Content) -> some View {
        SectionCard(title, subtitle: subtitle, icon: icon, accent: accent) {
            VStack(alignment: .leading, spacing: 16) { content() }
                .padding(16)
                .disabled(!canEdit)
        }
    }

    /// A short number with its words after it (web: the hours and the deposit %).
    private func inlineNumber(_ text: Binding<String>, key: String, label: String, after: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("", text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = $0.filter(\.isNumber); form.clear(key) }))
                    .keyboardType(.numberPad)
                    .fieldChrome(invalid: form.error(key) != nil)
                    .frame(width: 96)
                    .accessibilityLabel(label)
                Text(after).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            if let error = form.error(key) { Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
        }
        .id(key)
    }

    /// Why the currency no longer changes, and who can help if it is wrong (web `CurrencyLockNote`).
    private var currencyLockNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Glyph("lock", size: 16)
                Text(L("Set with the first bill")).font(Theme.text(14, weight: .bold))
            }
            .foregroundStyle(Theme.inkStrong)
            Text(LF("Everything the business charges is in %@: prices, bills, stays, sales and reports. Now that money has been recorded in it, it no longer changes.", settings.currency))
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            let help = "\(L("If it is the wrong currency, write to")) [contact@pawmiaw.com](mailto:contact@pawmiaw.com) \(L("and we will help you move it."))"
            Text((try? AttributedString(markdown: help)) ?? AttributedString(help))
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft).tint(Theme.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    /// Saving shows up when there is something to save, with a way back (web: the store settings' save bar).
    private var saveBar: some View {
        Card(padding: 16, tint: dirty ? Theme.mango : nil) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { barState; Spacer(minLength: 8); barButtons }
                VStack(alignment: .leading, spacing: 12) { barState; barButtons }
            }
        }
    }

    private var barState: some View {
        HStack(spacing: 6) {
            Circle().fill(dirty ? Theme.mango : ProviderState.done.color).frame(width: 8, height: 8)
            Text(dirty ? L("Unsaved changes") : L("Saved")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
        }
    }

    private var barButtons: some View {
        HStack(spacing: 8) {
            PMButton(L("Discard"), variant: .outline) { start(settings); form.errors = [:] }
                .disabled(!dirty || working)
            PMButton(working ? L("Saving…") : L("Save"), systemImage: "save", isWorking: working) { save() }
                .disabled(!dirty)
        }
    }

    private func bind(_ path: WritableKeyPath<CashStoreSettings, Bool>, _ fallback: Bool) -> Binding<Bool> {
        Binding(get: { draft?[keyPath: path] ?? fallback }, set: { draft?[keyPath: path] = $0 })
    }

    private func bindOptional(_ path: WritableKeyPath<CashStoreSettings, Int?>) -> Binding<Int?> {
        Binding(get: { draft?[keyPath: path] ?? nil }, set: { draft?[keyPath: path] = $0 })
    }

    private func start(_ value: CashStoreSettings) {
        draft = value
        currency = value.currency
        rate = Self.percent(value.defaultTaxRateBps)
        footer = value.receiptFooter ?? ""
        feeOn = (value.noShowFeeAmount ?? 0) > 0
        lateOn = value.lateCancelWindowHours != nil
        lateHours = value.lateCancelWindowHours.map(String.init) ?? "24"
        depositOn = (value.stayDepositPercent ?? 0) > 0
        depositPercent = value.stayDepositPercent.map(String.init) ?? ""
        emergencyOn = (value.emergencyDepositAmount ?? 0) > 0
        surchargeId = value.afterHoursSurchargeItemId ?? ""
        baseline = signature
    }

    private static func percent(_ bps: Int) -> String {
        let value = Double(bps) / 100
        return value.rounded() == value ? "\(Int(value))" : String(format: "%.2f", value)
    }

    private func save() {
        guard var next = draft else { return }
        let rateValue = Double(rate.replacingOccurrences(of: ",", with: "."))
        let hours = Int(lateHours)
        let deposit = Int(depositPercent)
        guard form.check([
            ("currency", currency.count == 3 && currency.allSatisfy(\.isLetter) ? nil : L("Use a three-letter currency code")),
            ("rate", rateValue.map { $0 >= 0 && $0 <= 100 } == true ? nil : L("Enter a tax rate from 0 to 100.")),
            ("fee", feeOn && (next.noShowFeeAmount ?? 0) <= 0 ? L("Enter the fee for a missed visit.") : nil),
            ("hours", feeOn && lateOn && !(1...336).contains(hours ?? 0) ? L("Enter the hours from 1 to 336.") : nil),
            ("deposit", depositOn && !(1...100).contains(deposit ?? 0) ? L("Enter a deposit from 1 to 100%.") : nil),
            ("emergency", isClinic && emergencyOn && (next.emergencyDepositAmount ?? 0) <= 0 ? L("Enter the emergency deposit.") : nil),
        ]) else { return }
        next.currency = currency.uppercased()
        next.defaultTaxRateBps = Int(((rateValue ?? 0) * 100).rounded())
        next.receiptFooter = footer.nonEmpty
        next.noShowFeeAmount = feeOn ? next.noShowFeeAmount : nil
        next.lateCancelWindowHours = feeOn && lateOn ? hours : nil
        next.stayDepositPercent = depositOn ? deposit : nil
        next.emergencyDepositAmount = emergencyOn ? next.emergencyDepositAmount : nil
        if isClinic { next.afterHoursSurchargeItemId = surchargeId.nonEmpty }
        working = true
        Task {
            defer { working = false }
            do {
                let body: [String: Any?] = [
                    "currency": next.currency,
                    "pricesIncludeTax": next.pricesIncludeTax,
                    "defaultTaxRateBps": next.defaultTaxRateBps,
                    "receiptFooter": next.receiptFooter,
                    "noShowFeeAmount": next.noShowFeeAmount,
                    "lateCancelWindowHours": next.lateCancelWindowHours,
                    "cashDifferenceAlertAmount": next.cashDifferenceAlertAmount,
                    "openingCashDefault": next.openingCashDefault,
                    "stayDepositPercent": next.stayDepositPercent,
                    "showPricesToFamilies": next.showPricesToFamilies ?? false,
                    "emergencyDepositAmount": next.emergencyDepositAmount,
                    "afterHoursSurchargeItemId": next.afterHoursSurchargeItemId,
                    "emailReceipts": next.emailReceipts ?? true,
                ]
                let saved: CashStoreSettings = try await API.put("/provider-store/settings", body: body)
                Toast.show(L("Store settings saved."))
                onSaved(saved)
                start(saved)
                justSaved = true
                announceDataChanged()
            } catch {
                if cashErrorCode(error) == "invalid_item" {
                    _ = form.check([("surcharge", L("That after-hours service is not in your catalog."))])
                    return
                }
                form.apply(error, known: ["currency": "currency", "defaultTaxRateBps": "rate", "noShowFeeAmount": "fee", "lateCancelWindowHours": "hours", "stayDepositPercent": "deposit", "emergencyDepositAmount": "emergency"])
            }
        }
    }
}
