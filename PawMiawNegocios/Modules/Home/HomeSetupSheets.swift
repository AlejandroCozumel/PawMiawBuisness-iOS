//
//  HomeSetupSheets.swift
//  PawMiawNegocios
//
//  What Home sets up in place (web setup/region-card.tsx and
//  setup/setup-checklist.tsx): the one-time "Confirma tu región y dinero"
//  for a workspace set up before onboarding asked (backend
//  docs/onboarding.md), and the checklist's sheets — prices for the services
//  offered, the no-show and late-cancel policy, the cash drawer, the receipt
//  and legal details, your own credential, and who on the team still lacks
//  something. Each saves to the same endpoint the web's does.
//

import SwiftUI
import PhotosUI

// MARK: - What the setup reads (GET /provider-setup)

struct HomeSetupState: Decodable {
    struct Service: Decodable {
        let serviceId: String
        let offered: Bool?
        let priceAmount: Int?
    }
    struct Business: Decodable {
        let name: String?
        let logoUrl: String?
        let services: [Service]?
    }
    struct Region: Decodable {
        let confirmed: Bool?
        let country: String?
        let currency: String?
        let currencyLocked: Bool?
        let defaultTaxRateBps: Int?
        let pricesIncludeTax: Bool?
        let clientLanguage: String?
    }
    struct Availability: Decodable { let timezone: String? }
    struct Location: Decodable {
        let id: String?
        let name: String?
        let timezoneConfirmed: Bool?
        let availability: Availability?
    }
    struct Legal: Decodable {
        let legalName: String?
        let taxId: String?
        let taxRegime: String?
        let receiptLogoUrl: String?
    }

    let needsRegionConfirmation: Bool?
    let canEdit: Bool?
    let canEditRegion: Bool?
    let business: Business?
    let region: Region?
    let location: Location?
    let legal: Legal?
}

/// What a country starts with (`GET /provider-country-defaults`).
struct HomeCountryDefaults: Decodable {
    struct Entry: Decodable {
        let country: String?
        let currency: String?
        let defaultTaxRateBps: Int?
        let pricesIncludeTax: Bool?
        let language: String?
        let timezone: String?
    }
    let countries: [Entry]?
}

/// The checklist's sheets, opened over Home.
enum HomeSetupSheet: Identifiable {
    case region
    case prices
    case policy
    case cashDrawer
    case receipt
    case credential
    case teamSetup([HomeChecklistMember])

    var id: String {
        switch self {
        case .region: "region"
        case .prices: "prices"
        case .policy: "policy"
        case .cashDrawer: "cash-drawer"
        case .receipt: "receipt"
        case .credential: "credential"
        case .teamSetup: "team-setup"
        }
    }

    /// The checklist item done in this sheet (nil for an item done on its own page).
    static func forItem(_ item: HomeChecklistItem) -> HomeSetupSheet? {
        switch item.id {
        case "prices": .prices
        case "policy": .policy
        case "cash_drawer": .cashDrawer
        case "receipt": .receipt
        case "credentials": item.mine == false ? nil : .credential
        case "team_setup": .teamSetup(item.members ?? [])
        default: nil
        }
    }

    @MainActor @ViewBuilder
    func view(actions: HomeActions) -> some View {
        switch self {
        case .region: HomeRegionSheet()
        case .prices: HomePricesSheet()
        case .policy: HomePolicySheet()
        case .cashDrawer: HomeCashDrawerSheet()
        case .receipt: HomeReceiptSheet()
        case .credential:
            TeamCredentialSheet(memberId: "me", isSelf: true, country: Workspace.shared.current?.country, businessAddress: Workspace.shared.current?.address,
                                reason: L("Add your professional credential to sign prescriptions.")) { announceDataChanged() }
        case .teamSetup(let members): HomeTeamSetupSheet(members: members) { id in actions.go(.staffMember(id)) }
        }
    }
}

// MARK: - Region and money (a workspace set up before onboarding asked)

/// "Confirma tu región y dinero": a one-time card; nothing stops meanwhile.
struct HomeRegionCard: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(HomeActions.self) private var actions: HomeActions?

    var body: some View {
        let canEditRegion = workspace.can(.billingManage)
        Card(padding: 16, tint: Theme.mango) {
            HStack(alignment: .top, spacing: 12) {
                Glyph("earth", size: 20).foregroundStyle(Theme.inkStrong).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Confirm your region and money")).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
                    Text(L("Your workspace was set up before we asked. Choose your time zone yourself and check the money — nothing stops meanwhile."))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    if canEditRegion {
                        PMButton(L("Confirm@region"), systemImage: "save", size: .compact) { actions?.sheet = .setup(.region) }
                            .padding(.top, 8)
                    } else {
                        Text(L("The owner or whoever manages billing confirms the money. Ask them to open Home.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct HomeRegionSheet: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var state: HomeSetupState?
    @State private var countries: [HomeCountryDefaults.Entry] = []
    @State private var failed = false
    @State private var timezone = ""
    @State private var country = ""
    @State private var currency = "MXN"
    @State private var tax = ""
    @State private var included = true
    @State private var language = "es"
    @State private var pickingZone = false
    @State private var saving = false

    private var locked: Bool { state?.region?.currencyLocked == true }

    var body: some View {
        ProviderModal(title: L("Confirm your region and money"), subtitle: L("It sets \"today\", your hours, reminders and the day's cash."), systemImage: "earth", accent: .mango,
                      isDirty: state != nil, form: form, primaryTitle: state?.canEditRegion == false ? nil : L("Confirm@region"), isWorking: saving, primaryIcon: "save", onPrimary: save) {
            if let state {
                if state.canEditRegion == false {
                    Text(L("The owner or whoever manages billing confirms the money. Ask them to open Home.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                } else {
                    fields(state)
                }
            } else if failed {
                ErrorState(message: L("Could not load your region.")) { await load() }
            } else {
                LoadingState()
            }
        }
        .presentationDetents([.large])
        .task { if state == nil { await load() } }
        .sheet(isPresented: $pickingZone) {
            TeamTimeZonePicker(selection: timezone) { timezone = $0; form.clear("timezone") }
        }
    }

    @ViewBuilder
    private func fields(_ state: HomeSetupState) -> some View {
        let saved = state.location?.availability?.timezone
        let device = TimeZone.current.identifier
        let preset = countries.first { $0.country == country }
        FormField(label: L("Time zone"), key: "timezone", hint: L("It sets \"today\", your hours, reminders and the day's cash."), form: form, required: true) {
            Button { pickingZone = true } label: {
                HStack {
                    Text(timezone.isEmpty ? L("Choose the time zone") : TeamHours.zoneLabel(timezone)).foregroundStyle(timezone.isEmpty ? Theme.inkSoft : Theme.inkStrong)
                    Spacer()
                    Glyph("chevrons-up-down", size: 16).foregroundStyle(Theme.inkSoft)
                }
                .fieldChrome(invalid: form.error("timezone") != nil)
            }
            .buttonStyle(.plain)
        }
        FlowLayout(spacing: 6) {
            if let saved, saved != "UTC" {
                FilterChip(title: LF("Saved now: %@", TeamHours.zoneLabel(saved)), isSelected: timezone == saved) { timezone = saved; form.clear("timezone") }
            }
            FilterChip(title: LF("This device says: %@", TeamHours.zoneLabel(device)), isSelected: timezone == device) { timezone = device; form.clear("timezone") }
            if let zone = preset?.timezone, zone != device, zone != saved {
                FilterChip(title: "\(CountryPicker.name(country) ?? country): \(TeamHours.zoneLabel(zone))", isSelected: timezone == zone) { timezone = zone; form.clear("timezone") }
            }
        }
        CountryField(code: country, key: "country", hint: country.isEmpty || preset != nil ? L("We fill in its usual currency, tax and language. Check each one.") : L("No preset for this country yet. Choose your currency, tax and client language below."), form: form) { code in
            pick(country: code)
        }
        if locked {
            FormField(label: L("Currency")) {
                HStack(spacing: 8) { Glyph("lock", size: 16); Text(currency) }.font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).frame(maxWidth: .infinity, alignment: .leading).fieldChrome()
            }
            Text(LF("Everything the business charges is in %@. Now that money has been recorded in it, it no longer changes.", currency)).font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
        } else {
            MenuField(label: L("Currency"), options: Array(Set(TeamRegion.currencies + [currency])).sorted().map { ($0, $0) }, selection: $currency, required: true)
            Text(L("Everything is charged in it. It is fixed once you record your first bill.")).font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
        }
        PMTextField(L("Sales tax"), text: $tax, key: "tax", form: form, hint: L("The standard rate (IVA, VAT). 0 if you don't charge it."), keyboard: .decimalPad, required: true)
        ToggleRow(title: L("My prices already include tax"), subtitle: included ? L("A price of 100 is what the client pays; the tax is inside it.") : L("The tax is added on top of each price."), isOn: $included)
        FormField(label: L("Language of emails to your clients"), hint: L("Used when a client hasn't chosen one."), required: true) {
            ChoiceCards(options: [("es", "Español", nil), ("en", "English", nil)], selection: $language)
        }
    }

    private func load() async {
        failed = false
        do {
            async let setupCall: HomeSetupState = API.get("/provider-setup")
            async let defaultsCall: HomeCountryDefaults? = try? await API.get("/provider-country-defaults")
            let loaded = try await setupCall
            countries = (await defaultsCall)?.countries ?? []
            let region = loaded.region
            timezone = loaded.location?.timezoneConfirmed == true ? (loaded.location?.availability?.timezone ?? "") : ""
            country = region?.country?.uppercased() ?? ""
            currency = region?.currency ?? workspace.currency
            tax = TeamRegion.percent(region?.defaultTaxRateBps ?? 0)
            included = region?.pricesIncludeTax ?? true
            language = region?.clientLanguage ?? LocalizationManager.shared.currentLanguage.rawValue
            if region?.confirmed != true, !country.isEmpty { pick(country: country) }
            state = loaded
        } catch {
            failed = true
        }
    }

    /// A country's defaults over the draft; a fixed currency stays.
    private func pick(country code: String) {
        country = code
        form.clear("country")
        guard let preset = countries.first(where: { $0.country == code }) else {
            language = TeamRegion.defaultLanguage(code) ?? language
            return
        }
        if !locked, let value = preset.currency { currency = value }
        tax = TeamRegion.percent(preset.defaultTaxRateBps ?? 0)
        included = preset.pricesIncludeTax ?? included
        language = preset.language ?? language
    }

    private func save() {
        let parsed = Double(tax.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
        guard form.check([
            ("timezone", timezone.isEmpty ? L("Choose the time zone your hours are in.") : nil),
            ("country", country.isEmpty ? L("Choose a country from the list.") : nil),
            ("tax", parsed.map { (0...100).contains($0) } == true ? nil : L("Enter the tax rate as a percentage, like 16.")),
        ]), let parsed else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let _: EmptyResponse = try await API.put("/provider-setup/region", body: [
                    "country": country, "currency": currency, "defaultTaxRateBps": Int((parsed * 100).rounded()),
                    "pricesIncludeTax": included, "clientLanguage": language, "timezone": timezone,
                ])
                Toast.show(L("Region and money confirmed."))
                await workspace.refresh()
                announceDataChanged()
                dismiss()
            } catch {
                form.apply(error, known: ["country": "country", "defaultTaxRateBps": "tax", "timezone": "timezone"])
            }
        }
    }
}

// MARK: - Prices for the services offered

private struct HomePricesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var unpriced: [HomeSetupState.Service] = []
    @State private var labels: [String: String] = [:]
    @State private var prices: [String: Int?] = [:]
    @State private var loaded = false
    @State private var failed = false
    @State private var saving = false

    private struct Catalog: Decodable {
        struct Service: Decodable { let id: String; let label: String? }
        let services: [Service]?
    }

    var body: some View {
        ProviderModal(title: L("Prices for your services"), subtitle: L("What each visit bills. It creates the service in your Catalog."), systemImage: "badge-dollar-sign", accent: .aqua,
                      isDirty: prices.values.contains { $0 != nil }, form: form, primaryTitle: unpriced.isEmpty ? nil : L("Save"), isWorking: saving, primaryIcon: "save", onPrimary: save) {
            if !loaded {
                LoadingState()
            } else if failed {
                ErrorState(message: L("Could not load your services.")) { await load() }
            } else if unpriced.isEmpty {
                EmptyState(systemImage: "badge-dollar-sign", title: L("Every service you offer has a price."), accent: Theme.blue)
            } else {
                ForEach(unpriced, id: \.serviceId) { service in
                    MoneyField(label: labels[service.serviceId] ?? service.serviceId,
                               cents: Binding(get: { prices[service.serviceId] ?? nil }, set: { prices[service.serviceId] = $0 }),
                               key: service.serviceId, form: form, hint: L("No price"))
                }
            }
        }
        .presentationDetents([.large])
        .task { if !loaded { await load() } }
    }

    private func load() async {
        failed = false
        do {
            async let setupCall: HomeSetupState = API.get("/provider-setup")
            async let catalogCall: Catalog? = try? await API.get("/appointment-services", query: ["scope": "all"])
            let state = try await setupCall
            unpriced = (state.business?.services ?? []).filter { $0.offered == true && ($0.priceAmount ?? 0) <= 0 }
            labels = Dictionary(((await catalogCall)?.services ?? []).map { ($0.id, $0.label ?? $0.id) }, uniquingKeysWith: { first, _ in first })
        } catch {
            failed = true
        }
        loaded = true
    }

    private func save() {
        // $0 is "no price yet", not a price: this sheet exists to set one.
        let rules = unpriced.compactMap { service -> (String, String?)? in
            guard let value = prices[service.serviceId] ?? nil else { return nil }
            return (service.serviceId, value <= 0 ? L("Set a price above 0.") : nil)
        }
        guard form.check(rules) else { return }
        let services = unpriced.compactMap { service -> [String: Any]? in
            guard let value = prices[service.serviceId] ?? nil, value > 0 else { return nil }
            return ["serviceId": service.serviceId, "priceAmount": value]
        }
        guard !services.isEmpty else { dismiss(); return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let _: EmptyResponse = try await API.put("/provider-setup/prices", body: ["services": services])
                Toast.show(L("Prices saved."))
                announceDataChanged()
                dismiss()
            } catch {
                form.apply(error)
            }
        }
    }
}

// MARK: - No-show and late-cancel policy

private struct HomePolicySheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var settings: TeamStoreSettings?
    @State private var failed = false
    @State private var fee: Int?
    @State private var window = 24
    @State private var saving = false

    var body: some View {
        ProviderModal(title: L("No-show and late-cancel policy"), subtitle: L("The fee is offered when a visit is missed or cancelled late — never charged on its own."), systemImage: "circle-slash", accent: .aqua,
                      isDirty: settings != nil, form: form, primaryTitle: settings == nil ? nil : L("Save"), isWorking: saving, primaryIcon: "save", onPrimary: save) {
            if settings != nil {
                MoneyField(label: L("Fee"), cents: $fee, key: "fee", form: form, hint: L("Leave empty for no fee."))
                MenuField(label: L("A cancellation is late when it comes less than"), options: [2, 4, 12, 24, 48].map { ($0, LF("%d hours before", $0)) }, selection: $window)
                // The family sees the business's terms (docs/family-money.md §5): before booking and on each visit.
                Text(L("Families see this fee, and until when they can cancel without it, when they book and on every visit.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            } else if failed {
                ErrorState(message: L("Could not load the store settings.")) { await load() }
            } else {
                LoadingState()
            }
        }
        .presentationDetents([.medium, .large])
        .task { if settings == nil { await load() } }
    }

    private func load() async {
        failed = false
        do {
            let loaded = try await TeamStoreSettings.load()
            fee = loaded.raw["noShowFeeAmount"]?.int.flatMap { $0 > 0 ? $0 : nil }
            window = loaded.raw["lateCancelWindowHours"]?.int ?? 24
            settings = loaded
        } catch {
            failed = true
        }
    }

    private func save() {
        guard let settings else { return }
        guard form.check([("fee", (fee ?? 1) < 0 ? L("Check this amount.") : nil)]) else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                try await settings.save(["noShowFeeAmount": TeamStoreSettings.cents(fee.flatMap { $0 > 0 ? $0 : nil }), "lateCancelWindowHours": .number(Double(window))])
                Toast.show(L("Saved"))
                dismiss()
            } catch {
                form.apply(error, known: ["noShowFeeAmount": "fee"])
            }
        }
    }
}

// MARK: - Cash drawer

private struct HomeCashDrawerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var settings: TeamStoreSettings?
    @State private var failed = false
    @State private var starting: Int?
    @State private var alert: Int?
    @State private var saving = false

    var body: some View {
        ProviderModal(title: L("Cash drawer"), systemImage: "wallet", accent: .aqua, isDirty: settings != nil, form: form,
                      primaryTitle: settings == nil ? nil : L("Save"), isWorking: saving, primaryIcon: "save", onPrimary: save) {
            if settings != nil {
                MoneyField(label: L("Starting cash"), cents: $starting, key: "starting", form: form, hint: L("What the drawer starts the first shift with. After that, each close leaves the next one's."))
                MoneyField(label: L("Warn me when the cash count is off by more than"), cents: $alert, key: "alert", form: form, hint: L("When a register closes off by more, it asks for a note and tells the owners. Leave empty for no warning."))
            } else if failed {
                ErrorState(message: L("Could not load the store settings.")) { await load() }
            } else {
                LoadingState()
            }
        }
        .presentationDetents([.medium, .large])
        .task { if settings == nil { await load() } }
    }

    private func load() async {
        failed = false
        do {
            let loaded = try await TeamStoreSettings.load()
            starting = loaded.raw["openingCashDefault"]?.int
            alert = loaded.cashDifferenceAlertAmount.flatMap { $0 > 0 ? $0 : nil }
            settings = loaded
        } catch {
            failed = true
        }
    }

    private func save() {
        guard let settings else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                try await settings.save(["cashDifferenceAlertAmount": TeamStoreSettings.cents(alert), "openingCashDefault": TeamStoreSettings.cents(starting ?? 0)])
                Toast.show(L("Saved"))
                dismiss()
            } catch {
                form.apply(error, known: ["cashDifferenceAlertAmount": "alert", "openingCashDefault": "starting"])
            }
        }
    }
}

// MARK: - Receipt and legal details

private struct HomeReceiptSheet: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var state: HomeSetupState?
    @State private var failed = false
    @State private var legalName = ""
    @State private var taxId = ""
    @State private var taxRegime = ""
    @State private var footer = ""
    @State private var logo = PhotoDraft()
    @State private var saving = false

    /// Common Mexican tax regimes (SAT codes); anything else can be typed.
    private static let regimes = [
        "601 General de Ley Personas Morales",
        "603 Personas Morales con Fines no Lucrativos",
        "605 Sueldos y Salarios",
        "606 Arrendamiento",
        "612 Personas Físicas con Actividades Empresariales y Profesionales",
        "621 Incorporación Fiscal",
        "625 Actividades Empresariales con ingresos a través de Plataformas Tecnológicas",
        "626 Régimen Simplificado de Confianza",
    ]

    private var mexico: Bool { (state?.region?.country ?? workspace.current?.country)?.uppercased() == "MX" }

    var body: some View {
        ProviderModal(title: L("Receipt and legal details"), subtitle: L("What your receipts and, later, your invoices carry."), systemImage: "receipt-text", accent: .aqua,
                      isDirty: state != nil, form: form, primaryTitle: state == nil ? nil : L("Save"), isWorking: saving, primaryIcon: "save", onPrimary: save) {
            if let state {
                PhotoField(label: L("Receipt logo"), currentURL: state.legal?.receiptLogoUrl ?? state.business?.logoUrl, draft: $logo,
                           allowsRemove: false, addTitle: L("Add a logo"), changeTitle: L("Change logo"))
                PMTextField(L("Legal name"), text: $legalName, key: "legalName", form: form, prompt: L("e.g. Veterinaria Sol SA de CV"), hint: L("As it appears with your tax authority."))
                PMTextField(mexico ? L("RFC") : L("Tax id"), text: $taxId, key: "taxId", form: form, capitalization: .characters)
                PMTextField(mexico ? L("Régimen fiscal") : L("Tax regime"), text: $taxRegime, key: "taxRegime", form: form)
                if mexico {
                    FlowLayout(spacing: 6) {
                        ForEach(Self.regimes, id: \.self) { regime in
                            FilterChip(title: String(regime.prefix(3)), isSelected: taxRegime == regime) { taxRegime = regime }
                                .accessibilityLabel(regime)
                        }
                    }
                }
                if state.canEditRegion == true {
                    PMTextField(L("Receipt footer"), text: $footer, key: "receiptFooter", form: form, hint: L("A thank-you, your return policy, your hours."), multiline: true)
                }
            } else if failed {
                ErrorState(message: L("Could not load the legal details.")) { await load() }
            } else {
                LoadingState()
            }
        }
        .presentationDetents([.large])
        .task { if state == nil { await load() } }
    }

    private func load() async {
        failed = false
        do {
            async let setupCall: HomeSetupState = API.get("/provider-setup")
            async let storeCall: TeamStoreSettings? = try? await TeamStoreSettings.load()
            let loaded = try await setupCall
            legalName = loaded.legal?.legalName ?? ""
            taxId = loaded.legal?.taxId ?? ""
            taxRegime = loaded.legal?.taxRegime ?? ""
            footer = (await storeCall)?.raw["receiptFooter"]?.string ?? ""
            state = loaded
        } catch {
            failed = true
        }
    }

    private func save() {
        guard let state else { return }
        guard form.check([
            ("legalName", legalName.count > 200 ? L("Keep the legal name under 200 characters.") : nil),
            ("taxId", taxId.trimmingCharacters(in: .whitespaces).count > 40 ? L("Keep the tax id under 40 characters.") : nil),
            ("receiptFooter", footer.count > 500 ? L("Keep the footer under 500 characters.") : nil),
        ]) else { return }
        saving = true
        Task {
            defer { saving = false }
            var body: [String: Any?] = ["legalName": legalName.nonEmpty, "taxId": taxId.nonEmpty, "taxRegime": taxRegime.nonEmpty]
            if state.canEditRegion == true { body["receiptFooter"] = footer.nonEmpty }
            do {
                let _: EmptyResponse = try await API.put("/provider-setup/legal", body: body)
            } catch {
                if (error as? APIError)?.code == "invalid_tax_id" {
                    _ = form.check([("taxId", L("Check the RFC: 12 characters for a company or 13 for a person, like XAXX010101000."))])
                } else {
                    form.apply(error, known: ["legalName": "legalName", "taxId": "taxId", "taxRegime": "taxRegime", "receiptFooter": "receiptFooter"])
                }
                return
            }
            // The logo goes up after the details; one that fails never loses them.
            if let logo = logo.data {
                do {
                    let _: EmptyResponse = try await ImageUpload.upload(logo, to: "/provider-setup/receipt-logo", field: "logo")
                } catch {
                    Toast.error(errorText(error, fallback: L("Saved, but the receipt logo could not be uploaded.")))
                }
            }
            Toast.show(L("Saved"))
            announceDataChanged()
            dismiss()
        }
    }
}

// MARK: - Your team's profiles

private struct HomeTeamSetupSheet: View {
    let members: [HomeChecklistMember]
    let open: (String) -> Void

    private func gap(_ id: String) -> String {
        switch id {
        case "signature": L("No signature adopted")
        case "credential": L("No credential to prescribe")
        default: L("Hasn’t opened their welcome")
        }
    }

    var body: some View {
        ProviderModal(title: L("Your team’s profiles"), subtitle: L("Each person adds their own signature and credentials from their welcome; a reminder waits on their Home."), systemImage: "user-check", accent: .aqua, cancelTitle: L("Close")) {
            if members.isEmpty {
                EmptyState(systemImage: "user-check", title: L("Everyone on your team has their signature and credentials."), accent: Theme.blue)
            } else {
                ForEach(members) { member in
                    Button { open(member.memberId) } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(member.name ?? "—").font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                FlowLayout(spacing: 6) {
                                    ForEach(member.gaps ?? [], id: \.self) { Chip(text: gap($0), tone: .warn) }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(L("See their profile")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                        }
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
