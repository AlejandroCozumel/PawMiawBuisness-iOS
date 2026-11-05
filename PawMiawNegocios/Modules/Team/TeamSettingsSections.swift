//
//  TeamSettingsSections.swift
//  PawMiawNegocios
//
//  Settings › Services you offer (with "Se reserva en línea" per service),
//  Region and money, and Legal details (web: components/app/settings/,
//  components/app/online-booking/online-services-panel.tsx).
//

import SwiftUI
import PhotosUI

// MARK: - Services you offer

private struct TeamOfferedService: Equatable {
    var offered: Bool
    var minutes: Int
}

private struct TeamOfferedDraft: Equatable {
    var categories: [String]
    var services: [String: TeamOfferedService]

    func same(_ other: TeamOfferedDraft) -> Bool {
        guard Set(categories) == Set(other.categories) else { return false }
        for id in Set(services.keys).union(other.services.keys) {
            let a = services[id], b = other.services[id]
            if (a?.offered ?? false) != (b?.offered ?? false) { return false }
            if (a?.offered ?? false) && (b?.offered ?? false) && a?.minutes != b?.minutes { return false }
        }
        return true
    }
}

private struct TeamSettingsService {
    let serviceId: String
    let category: String
    let label: String
    let description: String?
    let defaultMinutes: Int
    let suggested: Bool?
}

/// The kinds of care the business offers and, for each, the services it books and how long they take.
struct TeamServicesSection: View {
    @ObservedObject var model: TeamSettingsModel
    @EnvironmentObject private var workspace: Workspace
    @StateObject private var flash = TeamSavedFlash()
    @State private var draft: TeamOfferedDraft?
    @State private var error: String?
    @State private var checked = false
    @State private var saving = false

    /// Boarding and daycare may be on for Stays alone, with no service ticked.
    private static let stayOnly: Set<String> = ["boarding", "daycare"]
    private static let durations = (1...12).map { $0 * 15 }

    private var canEdit: Bool { workspace.can(.workspaceEdit) }

    private var services: [TeamSettingsService] {
        let suggested = Dictionary((model.setup?.business?.services ?? []).map { ($0.serviceId, $0.suggested) }, uniquingKeysWith: { a, _ in a })
        return (model.catalog?.services ?? []).map {
            TeamSettingsService(serviceId: $0.id, category: $0.category, label: $0.label, description: $0.description, defaultMinutes: $0.defaultMinutes, suggested: suggested[$0.id] ?? nil)
        }
    }

    private var saved: TeamOfferedDraft {
        let categories = model.setup?.business?.enabledCategories ?? workspace.current?.enabledCategories ?? []
        var map: [String: TeamOfferedService] = [:]
        if let setup = model.setup?.business?.services {
            for service in setup { map[service.serviceId] = TeamOfferedService(offered: service.offered ?? false, minutes: service.durationMinutes ?? service.defaultDurationMinutes ?? 30) }
        } else {
            for service in model.offeredCatalog?.services ?? [] { map[service.id] = TeamOfferedService(offered: true, minutes: service.defaultMinutes) }
        }
        return TeamOfferedDraft(categories: categories, services: map)
    }

    private var value: TeamOfferedDraft { draft ?? saved }

    private func empty(_ value: TeamOfferedDraft) -> Set<String> {
        var covered = Set<String>()
        for service in services where value.services[service.serviceId]?.offered ?? false { covered.insert(service.category) }
        return Set(value.categories.filter { !covered.contains($0) && !Self.stayOnly.contains($0) })
    }

    var body: some View {
        let value = self.value
        let selected = Set(value.categories)
        let missing = empty(value)
        let cards = model.catalog?.categories ?? []
        let losingStays = saved.categories.contains { Self.stayOnly.contains($0) } && !value.categories.contains { Self.stayOnly.contains($0) }
        TeamSaveSection(
            title: L("Services you offer"),
            subtitle: L("Bookings — yours and families’ — only offer the services you choose here.") + " " + L("Prices live in the Catalog."),
            systemImage: "tags",
            tint: Theme.lime,
            look: .settings,
            state: flash.state(saving: saving, dirty: draft.map { !$0.same(saved) } ?? false),
            saveLabel: L("Save services"),
            readOnlyText: canEdit ? nil : L("Only someone who edits the workspace can change this."),
            onSave: canEdit ? { save() } : nil,
            onDiscard: { draft = nil; error = nil; checked = false }
        ) {
            if model.catalog == nil {
                if model.catalogFailed {
                    VStack(spacing: 8) {
                        Text(L("Could not load the list of services.")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        Button { Task { await model.load(workspace) } } label: {
                            Text(L("Try again")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                } else { ProgressView().frame(maxWidth: .infinity, minHeight: 80) }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(cards, id: \.id) { card in
                        categoryCard(card, on: selected.contains(card.id), invalid: error != nil && value.categories.isEmpty)
                    }
                }
                if let error { Text(error).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.destructive) }
                if losingStays {
                    Text(L("Without boarding or daycare, Stays leaves the sidebar."))
                        .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.wash(Theme.mango, 18), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                }
                let onCards = cards.filter { selected.contains($0.id) }
                if !onCards.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("The services of each one")).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                        Text(L("Tick what you book and set how long it takes. Switching a kind of care on ticks its usual services; each one needs at least one."))
                            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.top, 12)
                    ForEach(onCards, id: \.id) { card in
                        categoryServices(card, value: value, none: missing.contains(card.id))
                    }
                }
            }
        }
    }

    /// The category's Lucide icon (web PROVIDER_CATEGORY_ICONS).
    static func icon(_ category: String) -> String {
        switch category {
        case "vet": "stethoscope"
        case "groomer": "scissors"
        case "walker": "footprints"
        case "sitter": "house"
        case "trainer": "dumbbell"
        case "daycare", "boarding": "building-2"
        case "pharmacy": "package"
        case "emergency": "siren"
        default: "ellipsis"
        }
    }

    private func categoryCard(_ card: TeamServiceCatalog.Category, on: Bool, invalid: Bool) -> some View {
        let hue = Hue.category(card.id).color
        return Button { toggle(card.id) } label: {
            HStack(alignment: .top, spacing: 12) {
                Glyph(Self.icon(card.id), size: 20).foregroundStyle(Theme.inkStrong)
                    .frame(width: 40, height: 40).background(Theme.wash(hue, 45), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.label ?? card.id).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    if let description = card.description { Text(description).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.leading) }
                }
                Spacer(minLength: 0)
                Tick(on: on, style: .choice)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .background(on ? AnyShapeStyle(Theme.wash(hue, 18)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(on ? Theme.blue : (invalid ? Theme.destructive : Theme.borderSoft), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!canEdit || saving)
    }

    private func categoryServices(_ card: TeamServiceCatalog.Category, value: TeamOfferedDraft, none: Bool) -> some View {
        let own = services.filter { $0.category == card.id }
        let count = own.filter { value.services[$0.serviceId]?.offered ?? false }.count
        let label = card.label ?? card.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Glyph(Self.icon(card.id), size: 16).foregroundStyle(Theme.inkStrong)
                    .frame(width: 32, height: 32).background(Theme.wash(Hue.category(card.id).color, 45), in: Circle())
                Text(label).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                Spacer(minLength: 8)
                Text(LF("%1$d of %2$d selected", count, own.count))
                    .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Theme.surfaceMuted, in: Capsule())
            }
            if Self.stayOnly.contains(card.id) {
                Text(L("Nights and days are charged at each space's rate, in Stays. Tick a service only if you also book it as an appointment, like an assessment."))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            if none {
                Text(canEdit ? LF("Tick at least one %1$@ service, or switch %2$@ off. It can’t be saved with none.", label, label) : LF("No %@ service is ticked.", label))
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(checked ? Theme.destructive : Theme.inkStrong)
            }
            VStack(spacing: 8) {
                ForEach(own, id: \.serviceId) { service in
                    serviceRow(service, value: value)
                }
            }
            .padding(.top, 4)
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(none ? (checked ? Theme.destructive : Theme.mango) : Theme.borderSoft, lineWidth: 2))
    }

    private func serviceRow(_ service: TeamSettingsService, value: TeamOfferedDraft) -> some View {
        let state = value.services[service.serviceId]
        let ticked = state?.offered ?? false
        let minutes = state?.minutes ?? service.defaultMinutes
        return HStack(spacing: 8) {
            Button { change(service, offered: !ticked, minutes: minutes) } label: {
                HStack(alignment: .center, spacing: 10) {
                    Tick(on: ticked, style: .checkbox)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.label).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.leading)
                        if let description = service.description.nonEmpty { Text(description).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.leading) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canEdit || saving)
            if ticked {
                Menu {
                    Picker("", selection: Binding(get: { minutes }, set: { change(service, offered: true, minutes: $0) })) {
                        ForEach(Self.durations, id: \.self) { Text(Self.minutesLabel($0)).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(Self.minutesLabel(minutes)).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                        Spacer(minLength: 4)
                        Glyph("chevron-down", size: 16).foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.horizontal, 12)
                    .frame(width: 128, height: 36)
                    .background(Theme.inputFill, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
                .disabled(!canEdit || saving)
                .accessibilityLabel(LF("How long %@ takes", service.label))
            }
        }
        .padding(6)
        .background(ticked ? AnyShapeStyle(Theme.wash(Hue.sky.color, 18)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(ticked ? Theme.blue.opacity(0.3) : Theme.borderSoft, lineWidth: 1))
    }

    static func minutesLabel(_ minutes: Int) -> String {
        if minutes < 60 { return LF("%d min", minutes) }
        let hours = minutes / 60, rest = minutes % 60
        return rest > 0 ? LF("%1$d h %2$d min", hours, rest) : LF("%d h", hours)
    }

    private func toggle(_ category: String) {
        guard canEdit else { return }
        error = nil
        var next = value
        if next.categories.contains(category) {
            next.categories.removeAll { $0 == category }
        } else {
            next.categories.append(category)
            let own = services.filter { $0.category == category }
            if !Self.stayOnly.contains(category) && !own.contains(where: { next.services[$0.serviceId]?.offered ?? false }) {
                // Its usual services: the ones the server suggests, else every named one.
                let knows = own.contains { $0.suggested != nil }
                var defaults = own.filter { knows ? $0.suggested == true : !($0.serviceId.hasSuffix("_other") || $0.serviceId == "custom_service") }
                if defaults.isEmpty { defaults = own }
                for service in defaults {
                    next.services[service.serviceId] = TeamOfferedService(offered: true, minutes: next.services[service.serviceId]?.minutes ?? service.defaultMinutes)
                }
            }
        }
        draft = next
    }

    private func change(_ service: TeamSettingsService, offered: Bool, minutes: Int) {
        guard canEdit else { return }
        var next = value
        next.services[service.serviceId] = TeamOfferedService(offered: offered, minutes: minutes)
        draft = next
    }

    private func save() {
        let value = self.value
        if value.categories.isEmpty { error = L("Offer at least one service."); Toast.error(error ?? ""); return }
        if !empty(value).isEmpty {
            checked = true
            error = L("Each kind of care needs at least one service. Tick one, or switch that kind of care off.")
            Toast.error(error ?? "")
            return
        }
        let on = Set(value.categories)
        let payload: [[String: Any]] = services.filter { on.contains($0.category) && (value.services[$0.serviceId]?.offered ?? false) }.map {
            ["serviceId": $0.serviceId, "durationMinutes": value.services[$0.serviceId]?.minutes ?? $0.defaultMinutes]
        }
        saving = true
        Task {
            defer { saving = false }
            do {
                let _: EmptyResponse = try await API.put("/provider-setup/services", body: ["enabledCategories": value.categories, "services": payload])
                draft = nil; checked = false; error = nil
                await model.saved(workspace)
                flash.mark()
            } catch {
                Toast.error(errorText(error, fallback: L("Could not save the services.")))
            }
        }
    }
}

/// "Se reserva en línea" per offered service; each switch saves at once.
struct TeamOnlineServicesPanel: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var settings: TeamOnlineSettings?
    @State private var failed = false
    @State private var savingId: String?

    var body: some View {
        let services = settings?.services ?? []
        let anyLocationOn = (settings?.locations ?? []).contains { $0.status == "active" && ($0.allowOnlineBooking ?? false) }
        let bookable = services.filter { $0.onlineBookable ?? false }.count
        TeamPanel(title: L("Online booking"), subtitle: L("Which of your services families can book from the app. Who takes each one is set on each person’s page."), systemImage: "globe", tint: Theme.lavender, look: .settings) {
            if settings == nil {
                if failed {
                    VStack(spacing: 12) {
                        Text(L("The online booking settings didn’t load.")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.center)
                        PMButton(L("Try again"), systemImage: "refresh-cw", variant: .outline, size: .compact) { Task { await load() } }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                } else { ProgressView().frame(maxWidth: .infinity, minHeight: 64) }
            } else if services.isEmpty {
                Text(L("Tick the services you offer above; each one can then be booked online.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            } else {
                if anyLocationOn {
                    Text(LP(bookable, "1 service is booked online.", "%d services are booked online.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                } else {
                    NavigationLink(value: ProviderRoute.section(.availability)) {
                        (Text(LP(bookable, "1 service is booked online.", "%d services are booked online.")) + Text(" ") + Text(L("No location takes online bookings yet.")) + Text(" ") + Text(L("Turn it on in Availability")).bold().foregroundColor(Theme.blue))
                            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 8, alignment: .top)], spacing: 8) {
                    ForEach(services, id: \.serviceId) { service in
                        let minutes = service.durationMinutes ?? 0
                        let length = TeamServicesSection.minutesLabel(minutes)
                        ToggleRow(
                            title: service.label,
                            subtitle: minutes <= 0 ? L("No length set: it can’t be booked online.") : ((service.onlineBookable ?? false) ? LF("%@ · families book it online", length) : LF("%@ · only your team books it", length)),
                            isOn: Binding(get: { (service.onlineBookable ?? false) && minutes > 0 }, set: { toggle(service.serviceId, $0) })
                        )
                        .disabled(minutes <= 0 || savingId == service.serviceId)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do { settings = try await API.get("/provider-online-booking/settings"); failed = false } catch { failed = true }
    }

    private func toggle(_ serviceId: String, _ on: Bool) {
        savingId = serviceId
        Task {
            defer { savingId = nil }
            do {
                settings = try await API.put("/provider-online-booking/services/\(serviceId)", body: ["onlineBookable": on])
                announceDataChanged()
            } catch { Toast.error(error) }
        }
    }
}

// MARK: - Region and money

/// The region and money words and rules, shared with Home's "Confirma tu región y dinero".
enum TeamRegion {
    static let currencies = ["MXN", "USD", "COP", "EUR", "ARS", "CLP", "PEN", "GTQ", "CRC", "CAD", "GBP", "BRL", "UYU", "DOP"]

    /// Each language named in itself.
    static func languageName(_ code: String?) -> String? {
        switch code {
        case "es": "Español"
        case "en": "English"
        default: nil
        }
    }

    static func defaultLanguage(_ country: String?) -> String? {
        guard let country = country?.uppercased(), !country.isEmpty else { return nil }
        return ["US", "CA", "GB", "AU", "NZ", "IE"].contains(country) ? "en" : "es"
    }

    static func percent(_ bps: Int) -> String {
        let value = Double(bps) / 100
        return value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}

/// Where the business is and what money it counts in.
struct TeamRegionSection: View {
    @ObservedObject var model: TeamSettingsModel
    @EnvironmentObject private var workspace: Workspace
    @State private var editing = false
    @StateObject private var flash = TeamSavedFlash()

    var body: some View {
        let current = workspace.current
        let canSeeMoney = TeamSettingsModel.canSeeMoney(workspace)
        let canEditMoney = workspace.can(.billingManage)
        let canEditRegion = workspace.can(.workspaceEdit) && canEditMoney
        let timezone = current?.availability?.timezone ?? "UTC"
        let language = current?.clientLanguage ?? TeamRegion.defaultLanguage(current?.country)
        TeamSaveSection(
            title: L("Region and money"),
            subtitle: L("Where you are, the clock your Schedule runs on, and the currency and tax on every price, sale and bill."),
            systemImage: "earth",
            tint: Theme.mango,
            look: .settings,
            state: flash.on ? .saved : .clean,
            readOnlyText: canEditMoney ? nil : (canSeeMoney ? L("Only someone who manages billing can change the currency and tax.") : L("Your role does not include prices."))
        ) {
            if canEditMoney && model.store != nil {
                PMButton(canEditRegion ? L("Edit region and money") : L("Edit currency and tax"), systemImage: "pencil", variant: .outline, fullWidth: true) { editing = true }
            }
        } content: {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    microLabel(L("Region"))
                    VStack(spacing: 0) {
                        settingsRow(L("Country"), hint: Text(L("Sets the usual currency and tax, and how legal details are checked."))) {
                            if let name = CountryPicker.name(current?.country) { Text(name) } else { Text(L("Not chosen yet")).fontWeight(.medium).foregroundStyle(Theme.inkSoft) }
                        }
                        RowDivider()
                        settingsRow(L("Time zone"), hint: workspace.can(.workspaceEdit) ? nil : Text(L("Set with the opening hours, on Availability.")), link: workspace.can(.workspaceEdit) ? L("Change it with your opening hours") : nil) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(TeamHours.zoneLabel(timezone))
                                if let now = localTime(timezone) { Text(LF("It is %@ there now", now)).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.inkSoft) }
                            }
                        }
                        RowDivider()
                        settingsRow(L("Language for clients"), hint: Text(L("Emails and reminders go out in it when a client has not chosen their own."))) {
                            if let name = TeamRegion.languageName(language) { Text(name) } else { Text(L("Not chosen yet")).fontWeight(.medium).foregroundStyle(Theme.inkSoft) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    microLabel(L("Money"))
                    VStack(spacing: 0) {
                        if !canSeeMoney {
                            settingsRow(L("Currency and tax"), hint: nil) { Text(L("Your role does not include prices.")).fontWeight(.medium).foregroundStyle(Theme.inkSoft) }
                        } else if let store = model.store {
                            settingsRow(L("Currency"), hint: Text(store.currencyLocked ? L("Set with the first bill") : L("One for the whole business: prices, bills, stays, sales and reports."))) {
                                HStack(spacing: 6) {
                                    if store.currencyLocked { Glyph("lock", size: 14).foregroundStyle(Theme.inkSoft) }
                                    Text(store.currency)
                                }
                            }
                            RowDivider()
                            settingsRow(L("Standard tax rate"), hint: Text(L("Items can use their own rate, zero or exempt in the Catalog."))) { Text(TeamRegion.percent(store.defaultTaxRateBps) + "%") }
                            RowDivider()
                            settingsRow(L("Prices include tax"), hint: Text(store.pricesIncludeTax ? L("The price on a tag is what the client pays.") : L("Tax is added on top of the price."))) { Text(store.pricesIncludeTax ? L("Yes") : L("No")) }
                            RowDivider()
                            settingsRow(L("Cash difference alert"), hint: Text(L("A register close off by more than this needs a note, and the owners are told by email and in the app."))) {
                                Text(store.cashDifferenceAlertAmount.map { Money.format($0, currency: store.currency) } ?? L("Off"))
                            }
                        } else if model.storeFailed {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(L("Could not load the currency and tax.")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                                PMButton(L("Try again"), variant: .outline, size: .compact) { Task { await model.load(workspace) } }
                            }
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 64)
                        }
                    }
                }
                if canEditMoney {
                    NavigationLink(value: ProviderRoute.section(.store)) {
                        (Text(L("The receipt’s closing line and the missed-visit fee are in")) + Text(" ") + Text(L("Store settings")).fontWeight(.semibold).foregroundColor(Theme.blue) + Text("."))
                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let store = model.store {
                TeamMoneySheet(store: store, country: current?.country, language: language, canEditRegion: canEditRegion) {
                    await model.saved(workspace)
                    flash.mark()
                    Toast.show(L("Saved"))
                }
            }
        }
    }

    private func localTime(_ zone: String) -> String? {
        guard let tz = TimeZone(identifier: zone) else { return nil }
        return DateText.time(Date(), zone: tz)
    }

    private func microLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.brandText(10.9, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.inkSoft)
    }

    /// The web's `SettingsRow`: the label (14 bold) and its hint, the value (14 semibold) under them on a phone.
    private func settingsRow<Value: View>(_ label: String, hint: Text?, link: String? = nil, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                if let hint { hint.font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                if let link {
                    NavigationLink(value: ProviderRoute.section(.availability)) {
                        Text(link).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            value().font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Edits the country, language, currency and tax. With the country and language it saves
/// through the setup's region (it keeps the history); without them, the store's settings.
private struct TeamMoneySheet: View {
    let store: TeamStoreSettings
    let country: String?
    let language: String?
    let canEditRegion: Bool
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var countryCode = ""
    @State private var clientLanguage = "es"
    @State private var currency = "MXN"
    @State private var rate = ""
    @State private var included = false
    @State private var alertOn = false
    @State private var alertCents: Int?
    @State private var started = false
    @State private var saving = false

    var body: some View {
        ProviderModal(
            title: canEditRegion ? L("Region and money") : L("Currency and tax"),
            subtitle: L("Used on every price, sale, bill and register close."),
            systemImage: "coins",
            accent: .mango,
            isDirty: started,
            form: form,
            primaryTitle: canEditRegion ? L("Save region and money") : L("Save currency and tax"),
            isWorking: saving,
            primaryIcon: "save",
            onPrimary: { save() }
        ) {
            if canEditRegion {
                CountryField(code: countryCode, key: "country", hint: L("Changing it does not change your currency or tax: check them below."), form: form) { countryCode = $0 }
                VStack(alignment: .leading, spacing: 8) {
                    MenuField(label: L("Language for clients"), options: [("es", "Español"), ("en", "English")], selection: $clientLanguage)
                    Text(L("Used when a client has not chosen one.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            if store.currencyLocked {
                FormField(label: L("Currency")) {
                    HStack(spacing: 6) {
                        Glyph("lock", size: 14).foregroundStyle(Theme.inkSoft)
                        Text(store.currency)
                    }
                    .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).frame(maxWidth: .infinity, alignment: .leading).fieldChrome()
                }
                NoticeCard(tone: .info, title: L("Set with the first bill"), message: LF("Everything the business charges is in %@: prices, bills, stays, sales and reports. Now that money has been recorded in it, it no longer changes.", store.currency) + " " + L("If it is the wrong currency, write to") + " contact@pawmiaw.com " + L("and we will help you move it."))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    MenuField(label: L("Currency"), options: Array(Set([store.currency] + TeamRegion.currencies)).sorted().map { ($0, $0) }, selection: $currency)
                    Text(L("The whole business uses it. Changing it relabels Catalog prices without converting them; the first bill fixes it.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            PMTextField(L("Standard tax rate (%)"), text: $rate, key: "rate", form: form, hint: L("e.g. 16 for IVA in Mexico."), keyboard: .decimalPad)
            ToggleRow(title: L("Prices include tax"), subtitle: included ? L("The price on a tag is what the client pays.") : L("Tax is added on top of the price."), isOn: $included)
            ToggleRow(title: L("Cash difference alert"), subtitle: L("A register close off by more than this needs a note, and the owners are told by email and in the app."), isOn: $alertOn)
            if alertOn {
                MoneyField(label: LF("Alert above (%@)", (store.currencyLocked ? store.currency : currency).uppercased()), cents: $alertCents, key: "alert", form: form)
            }
        }
        .onAppear {
            guard !started else { return }
            countryCode = country?.uppercased() ?? ""
            clientLanguage = language ?? "es"
            currency = store.currency
            rate = TeamRegion.percent(store.defaultTaxRateBps)
            included = store.pricesIncludeTax
            alertOn = store.cashDifferenceAlertAmount != nil
            alertCents = store.cashDifferenceAlertAmount ?? 5000
            started = true
        }
    }

    private func save() {
        let normalized = rate.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        let parsed = Double(normalized)
        let rateError = parsed.map { (0...100).contains($0) } == true ? nil : L("Enter a tax rate from 0 to 100.")
        let alertError = alertOn && (alertCents ?? 0) <= 0 ? L("Enter an amount above 0, or turn the alert off.") : nil
        let regionChanged = canEditRegion && (countryCode != (country?.uppercased() ?? "") || clientLanguage != language)
        let countryError = regionChanged && countryCode.isEmpty ? L("Choose a country from the list.") : nil
        guard form.check([("country", countryError), ("rate", rateError), ("alert", alertError)]), let parsed else { return }
        let bps = Int((parsed * 100).rounded())
        let nextCurrency = store.currencyLocked ? store.currency : currency.uppercased()
        let alert: Int? = alertOn ? alertCents : nil
        saving = true
        Task {
            defer { saving = false }
            do {
                if regionChanged {
                    let _: EmptyResponse = try await API.put("/provider-setup/region", body: [
                        "country": countryCode, "clientLanguage": clientLanguage, "currency": nextCurrency,
                        "defaultTaxRateBps": bps, "pricesIncludeTax": included, "cashDifferenceAlertAmount": alert,
                    ])
                } else {
                    try await store.save([
                        "currency": .string(nextCurrency), "defaultTaxRateBps": .number(Double(bps)),
                        "pricesIncludeTax": .bool(included), "cashDifferenceAlertAmount": TeamStoreSettings.cents(alert),
                    ], announce: false)
                }
                await onSaved()
                dismiss()
            } catch {
                form.apply(error, known: ["country": "country", "defaultTaxRateBps": "rate", "cashDifferenceAlertAmount": "alert"])
            }
        }
    }
}

// MARK: - Legal details

/// The legal name, tax id and régimen that print on bills and receipts, and — in Mexico — the Registro SENASICA.
struct TeamLegalSection: View {
    @ObservedObject var model: TeamSettingsModel
    @EnvironmentObject private var workspace: Workspace
    @StateObject private var form = FormState()
    @StateObject private var flash = TeamSavedFlash()
    @State private var legalName = ""
    @State private var taxId = ""
    @State private var taxRegime = ""
    @State private var senasica = ""
    @State private var started = false
    @State private var logo = PhotoDraft()
    @State private var saving = false

    private var canEdit: Bool { workspace.can(.workspaceEdit) }
    private var mexico: Bool { workspace.current?.country?.uppercased() == "MX" }
    private var saved: (String, String, String, String) {
        (model.setup?.legal?.legalName ?? "", model.setup?.legal?.taxId ?? "", model.setup?.legal?.taxRegime ?? "", model.setup?.senasicaRegistration ?? "")
    }
    private var dirty: Bool {
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        return t(legalName) != t(saved.0) || t(taxId) != t(saved.1) || t(taxRegime) != t(saved.2) || t(senasica) != t(saved.3) || !logo.isEmpty
    }

    var body: some View {
        TeamSaveSection(
            title: L("Legal details"),
            subtitle: L("What prints on your bills, receipts and prescriptions. All optional: leave empty what you don’t use."),
            systemImage: "landmark",
            tint: Theme.lavender,
            look: .settings,
            state: flash.state(saving: saving, dirty: dirty),
            saveLabel: L("Save legal details"),
            readOnlyText: canEdit ? nil : L("Only someone who edits the workspace can see and change the legal details."),
            onSave: canEdit ? { save() } : nil,
            onDiscard: { fill() }
        ) {
            if !canEdit {
                Text(L("They print on what your business hands to clients. Ask the owner or an administrator if one needs changing.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            } else if model.setup == nil {
                if model.setupFailed {
                    VStack(spacing: 12) {
                        Text(L("Could not load the legal details.")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        PMButton(L("Try again"), variant: .outline) { Task { await model.load(workspace) } }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 32)
                    .frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                } else { ProgressView().frame(maxWidth: .infinity, minHeight: 80) }
            } else {
                FormScroll(form: form) {
                    VStack(alignment: .leading, spacing: 16) {
                        receiptLogo
                        PMTextField(L("Legal name"), text: $legalName, key: "legalName", form: form, hint: L("The registered name, when it differs from the business name."))
                        PMTextField(mexico ? L("RFC") : L("Tax id"), text: $taxId, key: "taxId", form: form, prompt: mexico ? "XAXX010101000" : nil, hint: mexico ? L("12 characters for a company, 13 for a person. Saved in capitals, without spaces.") : L("The number your tax authority gave the business."), capitalization: .characters)
                        PMTextField(L("Tax regime"), text: $taxRegime, key: "taxRegime", form: form, hint: mexico ? L("As on your tax certificate, e.g. 612 Personas Físicas con Actividades Empresariales.") : L("How the business is registered for tax, if your receipts must say it."))
                        if mexico || !saved.3.isEmpty || workspace.current?.country == nil {
                            PMTextField(L("SENASICA registration"), text: $senasica, key: "senasica", form: form, hint: mexico ? L("The establishment’s registration with SENASICA, for prescriptions.") : L("Mexico only. Leave it empty elsewhere."))
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L("Where they print").uppercased()).font(.brandText(10.9, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.inkSoft)
                            printsOn("file-text", L("Bills and receipts"), mexico ? L("Legal name, RFC and tax regime, at the top of the PDF.") : L("Legal name, tax id and tax regime, at the top of the PDF."))
                            printsOn("pill", L("Prescriptions"), mexico ? L("Legal name and the SENASICA registration.") : L("Legal name."))
                            Text(L("The address and phone on them are the ones in Contact and address.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                    }
                    .disabled(saving)
                }
            }
        }
        .onAppear { if !started && model.setup != nil { fill(); started = true } }
        .onChange(of: model.setup == nil) { _, missing in if !missing && !started { fill(); started = true } }
    }

    private func printsOn(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Glyph(icon, size: 16).foregroundStyle(Theme.blue).padding(.top, 2)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                Text(text).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    /// "Logo en recibos": the one saved, else the profile logo.
    private var receiptLogo: some View {
        let current = model.setup?.legal?.receiptLogoUrl
        return PhotoField(
            label: L("Receipt logo"),
            hint: current == nil || logo.removed ? L("Receipts print the profile logo.") : L("Receipts print this logo instead of the profile’s."),
            currentURL: current ?? model.setup?.business?.logoUrl,
            draft: $logo,
            allowsRemove: current != nil,
            addTitle: L("Add a logo"),
            changeTitle: L("Change logo"),
            removedNote: L("Receipts print the profile logo.")
        )
    }

    private func fill() {
        legalName = saved.0; taxId = saved.1; taxRegime = saved.2; senasica = saved.3
        logo = PhotoDraft()
        form.errors = [:]
    }

    private func normalizedTaxId(_ value: String) -> String {
        value.replacingOccurrences(of: #"[\s-]+"#, with: "", options: .regularExpression).uppercased()
    }

    private func save() {
        let id = taxId.trimmingCharacters(in: .whitespaces)
        var taxError: String?
        if id.count > 40 { taxError = L("Keep the tax id under 40 characters.") }
        else if !id.isEmpty && mexico && normalizedTaxId(id).range(of: #"^[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}$"#, options: .regularExpression) == nil && id.uppercased() != saved.1.trimmingCharacters(in: .whitespaces).uppercased() {
            taxError = L("Check the RFC: 12 characters for a company or 13 for a person, like XAXX010101000.")
        }
        guard form.check([
            ("legalName", legalName.trimmingCharacters(in: .whitespaces).count > 200 ? L("Keep the legal name under 200 characters.") : nil),
            ("taxId", taxError),
            ("taxRegime", taxRegime.trimmingCharacters(in: .whitespaces).count > 120 ? L("Keep the tax regime under 120 characters.") : nil),
            ("senasica", senasica.trimmingCharacters(in: .whitespaces).count > 60 ? L("Keep the SENASICA registration under 60 characters.") : nil),
        ]) else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let _: EmptyResponse = try await API.put("/provider-setup/legal", body: [
                    "legalName": legalName.nonEmpty,
                    "taxId": id.isEmpty ? nil : (mexico ? normalizedTaxId(id) : id.uppercased()),
                    "taxRegime": taxRegime.nonEmpty,
                    "senasicaRegistration": senasica.nonEmpty,
                ])
            } catch {
                if (error as? APIError)?.code == "invalid_tax_id" {
                    _ = form.check([("taxId", L("Check the RFC: 12 characters for a company or 13 for a person, like XAXX010101000."))])
                } else {
                    form.apply(error, known: ["legalName": "legalName", "taxId": "taxId", "taxRegime": "taxRegime", "senasicaRegistration": "senasica"])
                }
                return
            }
            // The logo goes up (or comes off) after the details; one that fails never loses them.
            do {
                if let data = logo.data {
                    let _: EmptyResponse = try await ImageUpload.upload(data, to: "/provider-setup/receipt-logo", field: "logo")
                } else if logo.removed {
                    try await API.send("DELETE", "/provider-setup/receipt-logo")
                }
            } catch {
                Toast.error(errorText(error, fallback: L("Saved, but the receipt logo could not be uploaded.")))
            }
            await model.saved(workspace)
            fill()
            flash.mark()
        }
    }
}
