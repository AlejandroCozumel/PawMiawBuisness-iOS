//
//  StockPharmacy.swift
//  PawMiawNegocios
//
//  Farmacia (web provider.pharmacy.tsx → components/app/pharmacy/pharmacy-page.tsx):
//  what waits (to hand over, refills, drafts to sign), every prescription of
//  the business, the controlled register and the period's report, with the
//  counts from `/provider-pharmacy/counts` on top. A prescription is started
//  here too, and opens on its own page. See docs/prescriptions.md (PawMiawIos).
//

import SwiftUI

struct PharmacyScreen: View {
    var body: some View {
        StockPharmacyPage()
    }
}

/// A prescription to open on its own page.
struct StockRxTarget: Hashable, Identifiable {
    let id: String
}

/// What this person may do in the Pharmacy (web prescriptionRights + pharmacy-page).
struct StockRxRights {
    let canRead: Bool
    let canWrite: Bool
    let canSign: Bool
    let canDispenseAtVisit: Bool
    let canViewClients: Bool
    let canSell: Bool
    let canHandOverControlled: Bool
    let canLogRefill: Bool
    /// The register and the report: owners, admins, who signs or adjusts stock.
    let canLog: Bool

    @MainActor
    init(_ w: Workspace, counts: StockPharmacyCounts? = nil) {
        canRead = w.canAny(.recordsView, .salesSell, .billingEditInvoice)
        canWrite = w.can(.recordsCreate)
        canSign = w.can(.recordsApprove)
        canDispenseAtVisit = w.can(.billingEditInvoice)
        canViewClients = w.can(.clientsView)
        canSell = w.can(.salesSell)
        canHandOverControlled = counts?.canHandOverControlled ?? w.can(.pharmacyDispenseControlled)
        canLogRefill = counts?.canLogRefill ?? (w.can(.salesSell) || w.can(.recordsCreate))
        canLog = w.isOwnerOrAdmin || w.can(.recordsApprove) || w.can(.inventoryAdjust)
    }
}

enum StockPharmacyTab: Hashable { case todo, prescriptions, register, report }

private struct StockPharmacyPage: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var counts: StockPharmacyCounts?
    @State private var tab: StockPharmacyTab = .todo
    @State private var focus: StockTodoFocus = .all
    @State private var rxFilters = StockRxFilters()
    @State private var openRx: StockRxTarget?
    @State private var inventory: StockInventoryTarget?
    @State private var writing = false
    @State private var logging = false

    private var rights: StockRxRights { StockRxRights(workspace, counts: counts) }
    private var tabs: [StockPharmacyTab] { rights.canLog ? [.todo, .prescriptions, .register, .report] : [.todo, .prescriptions] }

    var body: some View {
        Group {
            if workspace.current != nil && !rights.canRead {
                PageScroll {
                    EmptyState(systemImage: "lock", title: L("You do not have access to prescriptions."), message: L("Ask the workspace owner to let your role see records or sell."), panel: true)
                }
            } else {
                PageScroll(refresh: { await loadCounts(); announceDataChanged() }) {
                    header
                    ToneTabs(tabs: tabs.map { ToneTabs.Tab($0, label($0), icon: icon($0), count: $0 == .todo ? waiting : nil) },
                                selection: Binding(get: { tab }, set: { next in
                                    tab = next
                                    if next == .todo { focus = .all }
                                }))
                    switch tab {
                    case .todo:
                        StockTodoTab(focus: $focus, counts: counts, rights: rights, onOpen: open, onNew: rights.canWrite ? { writing = true } : nil, onLogRefill: rights.canLogRefill ? { logging = true } : nil)
                    case .prescriptions:
                        StockPrescriptionsTab(filters: $rxFilters, rights: rights, onOpen: open, onNew: rights.canWrite ? { writing = true } : nil)
                    case .register:
                        StockRegisterTab(onOpen: open)
                    case .report:
                        StockReportTab()
                    }
                }
            }
        }
        .providerPage(L("Pharmacy"), root: true)
        .reloadsOnScope { await loadCounts() }
        .task(id: workspace.scopeVersion) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await loadCounts()
            }
        }
        .navigationDestination(item: $openRx) { target in StockPrescriptionScreen(prescriptionId: target.id) }
        .navigationDestination(item: $inventory) { target in StockInventoryPage(initialFilter: target.filter, initialMedicinesOnly: true) }
        .sheet(isPresented: $writing) {
            StockPrescriptionSheet(pet: nil, draft: nil) { saved in open(saved.id) }
        }
        .sheet(isPresented: $logging) {
            StockLogRefillSheet(prescription: nil)
        }
    }

    private func open(_ id: String) {
        openRx = StockRxTarget(id: id)
    }

    private func loadCounts() async {
        guard rights.canRead else { return }
        if let fresh: StockPharmacyCounts = try? await API.get("/provider-pharmacy/counts") { counts = fresh }
    }

    /// What waits in To do, on its tab.
    private var waiting: Int? {
        guard let counts else { return nil }
        return (counts.refillsWaiting ?? 0) + (counts.draftsToSign ?? 0) + (counts.toHandOver ?? 0)
    }

    // MARK: Header (web ProviderModuleHeader: Pill, teal)

    private func value(_ number: Int?) -> String { number.map(String.init) ?? "—" }

    private var header: some View {
        ModuleHeader(
            icon: ProviderSection.pharmacy.headerIcon,
            title: L("Pharmacy"),
            subtitle: L("Prescriptions, refills, what was handed over and the controlled register."),
            accent: ProviderSection.pharmacy.headerAccent,
            stats: headerStats,
            storageKey: "pharmacy"
        ) {
            if rights.canWrite {
                PMButton(L("New prescription"), systemImage: "plus") { writing = true }
            }
        }
    }

    /// A tile filters the page; with nothing behind it, it is only a number.
    private var headerStats: [ModuleStat] {
        let handOver = counts?.toHandOver ?? 0
        let refills = counts?.refillsWaiting ?? 0
        let pending = counts?.refillsPending ?? 0
        let drafts = counts?.draftsToSign ?? 0
        let expiring = counts?.expiringSoon ?? 0
        var stats: [ModuleStat] = [
            ModuleStat("handover", label: L("To hand over"), value: value(counts?.toHandOver), icon: "package-check", accent: ChipTone.waiting.color,
                       attention: handOver > 0, active: tab == .todo && focus == .handover,
                       action: handOver > 0 ? { tab = .todo; focus = .handover } : nil),
            ModuleStat("refills", label: L("Refills waiting"), value: value(counts?.refillsWaiting),
                       hint: pending > 0 ? LF("%d for a vet to answer", pending) : nil,
                       icon: "bell-ring", accent: ChipTone.waiting.color, attention: pending > 0, active: tab == .todo && focus == .refills,
                       action: refills > 0 ? { tab = .todo; focus = .refills } : nil),
            ModuleStat("drafts", label: L("Drafts to sign"), value: value(counts?.draftsToSign), icon: "pen-line", accent: ChipTone.upcoming.color,
                       active: tab == .todo && focus == .drafts,
                       action: drafts > 0 ? { tab = .todo; focus = .drafts } : nil),
            ModuleStat("expiring", label: LF("Expiring in %d days", counts?.expiringDays ?? 7), value: value(counts?.expiringSoon),
                       hint: L("Signed, with something left"), icon: "calendar-clock", accent: Theme.lime,
                       active: tab == .prescriptions && rxFilters.expiring,
                       action: expiring > 0 ? { tab = .prescriptions; rxFilters = StockRxFilters(state: "all", expiring: true) } : nil),
        ]
        if let stock = counts?.stock {
            let either = stock.either ?? 0
            let hint = either > 0
                ? [(stock.low ?? 0) > 0 ? LF("%d low", stock.low ?? 0) : nil, (stock.expiring ?? 0) > 0 ? LF("%d expiring", stock.expiring ?? 0) : nil, (stock.expired ?? 0) > 0 ? LF("%d expired", stock.expired ?? 0) : nil].compactMap { $0 }.joined(separator: " · ")
                : L("In Inventory")
            stats.append(ModuleStat("stock", label: L("Medicines low or expiring"), value: "\(either)", hint: hint, icon: "boxes", accent: Theme.mango,
                                    attention: (stock.expired ?? 0) > 0,
                                    action: either > 0 ? { inventory = StockInventoryTarget(filter: (stock.low ?? 0) > 0 ? .low : (stock.expiring ?? 0) > 0 ? .expiring : .expired) } : nil))
        }
        return stats
    }

    private func label(_ tab: StockPharmacyTab) -> String {
        switch tab {
        case .todo: L("To do")
        case .prescriptions: L("Prescriptions")
        case .register: L("Controlled register")
        case .report: L("Report")
        }
    }

    private func icon(_ tab: StockPharmacyTab) -> String {
        switch tab {
        case .todo: "clipboard-list"
        case .prescriptions: "file-text"
        case .register: "scale"
        case .report: "pill"
        }
    }
}

/// Inventory opened from the Pharmacy on its medicines.
struct StockInventoryTarget: Hashable, Identifiable {
    let filter: StockFilter
    var id: String { filter.rawValue }
}

// MARK: - Shared rows

enum StockRxWords {
    static func state(_ state: String) -> String {
        switch state {
        case "draft": L("Draft@rx")
        case "active": L("Active@rx")
        case "expired": L("Expired@rx")
        case "used_up": L("Used up")
        case "cancelled": L("Cancelled@rx")
        case "all": L("All@rx")
        default: state
        }
    }

    /// A prescription's state as its status colour.
    static func stateState(_ state: String) -> ProviderState {
        switch state {
        case "draft": .upcoming
        case "active": .active
        case "used_up": .done
        default: .closed
        }
    }

    static func refill(_ status: String) -> String {
        switch status {
        case "pending": L("Waiting for the vet")
        case "approved": L("Approved")
        case "ready": L("Ready for pickup")
        case "declined": L("Declined")
        case "cancelled": L("Withdrawn")
        case "picked_up": L("Picked up")
        default: status
        }
    }

    static func refillState(_ status: String) -> ProviderState {
        switch status {
        case "pending": .waiting
        case "approved": .upcoming
        case "ready": .done
        case "declined": .problem
        default: .closed
        }
    }

    static func schedule(_ schedule: String?) -> String? {
        switch schedule {
        case "mx_group_1": L("Group I (quantified prescription)")
        case "us_c2": L("Schedule II (C-II)")
        case "us_c3": L("Schedule III (C-III)")
        case "us_c4": L("Schedule IV (C-IV)")
        case "us_c5": L("Schedule V (C-V)")
        case "controlled_other": L("Controlled")
        case .some(let other) where !other.isEmpty: L("Controlled")
        default: nil
        }
    }

    static func block(_ block: String?) -> String? {
        switch block {
        case "not_in_catalog": L("Not in the Catalog — sold outside PawMiaw")
        case "nothing_left": L("Nothing left to hand over")
        case "not_signed": L("Not signed yet")
        case "cancelled": L("Cancelled@rx")
        case "expired": L("Expired@rx")
        default: nil
        }
    }

    /// "today", "waiting 1 day", "waiting 3 days".
    static func waiting(_ since: String?) -> String {
        guard let date = DateText.parse(since) else { return L("today") }
        let calendar = DateText.calendar
        let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0)
        if days == 0 { return L("today") }
        return days == 1 ? L("waiting 1 day") : LF("waiting %d days", days)
    }

    /// The server's refusals by code (web PRESCRIPTION_ERROR_MESSAGES), else its own sentence.
    static func error(_ error: Error, fallback: String = L("Something went wrong. Try again.")) -> String {
        let code = (error as? StockRefusal)?.code ?? (error as? APIError)?.code
        let status = (error as? StockRefusal)?.status ?? (error as? APIError)?.status
        if code == "pet_archived", let refusal = error as? StockRefusal {
            if refusal.body["deceased"]?.bool == true { return L("This pet has died — no new prescriptions can be written for it.") }
            if refusal.body["deceased"]?.bool == false { return L("This pet is archived — restore it before writing a prescription.") }
        }
        if let code, let text = messages[code] { return L(text) }
        if status == 403 { return L("You don’t have permission to do this.") }
        if status == 404 { return L("It wasn’t found. It may have been removed.") }
        return stockErrorText(error, fallback: fallback)
    }

    static let messages: [String: String] = [
        "credential_required": "Add your professional credential to sign prescriptions.",
        "dea_required": "A controlled medicine needs your DEA number on the prescription.",
        "prescription_not_found": "That prescription wasn’t found.",
        "prescription_not_signed": "That prescription isn’t signed yet.",
        "prescription_cancelled": "That prescription was cancelled.",
        "prescription_expired": "That prescription expired — ask the vet for a new one.",
        "prescription_exhausted": "That prescription has nothing left to fill — ask the vet for a refill.",
        "prescription_controlled_forbidden": "A controlled medicine is handed over by a vet — ask one to do it.",
        "refill_already_open": "This medicine already has a refill request open.",
        "controlled_no_electronic": "A controlled prescription goes on paper, signed by hand — it can’t be sent as a link.",
        "controlled_separate": "A controlled medicine goes on a prescription of its own.",
        "already_signed": "This prescription is already signed.",
        "not_draft": "A signed prescription can’t change — cancel it and write a new one.",
        "reason_required": "Say why.",
        "items_required": "Add at least one medicine.",
        "too_many_items": "Up to 10 medicines per prescription.",
        "medicine_required": "Name the medicine.",
        "active_ingredient_required": "Add the active ingredient (NOM-064 asks for it next to the commercial name).",
        "dose_required": "Add the dose.",
        "frequency_required": "Say how often it is given.",
        "quantity_invalid": "Say how much to dispense (a whole number from 1).",
        "refills_invalid": "Refills are a whole number from 0 to 12.",
        "refills_not_allowed": "This controlled medicine allows fewer refills.",
        "duration_invalid": "The duration is a number of days from 1 to 730.",
        "dose_invalid": "The dose must be more than zero.",
        "prescription_changed": "This prescription changed while it was being signed. Here it is as it stands now: read it again and sign.",
        "catalog_item_not_found": "A medicine on this prescription is no longer in the Catalog. Choose it again or write it in.",
        "schedule_country_mismatch": "That controlled class isn’t used in this business’s country.",
        "valid_days_invalid": "A prescription is valid for 1 to 365 days.",
        "refill_not_open": "This request was already answered.",
        "refill_not_found": "That refill request wasn’t found.",
        "bill_closed": "This visit’s bill is closed — dispense it at the desk.",
        "not_a_visit": "This prescription wasn’t written at a visit.",
        "number_required": "Type the number.",
        "cedula_format": "A cédula profesional has 6 to 8 digits.",
        "state_required": "Choose the state that issued the license.",
        "dea_format": "That isn’t a valid DEA number (two letters and seven digits).",
        "dea_address_required": "Add the address the DEA registration is for.",
        "issuer_required": "Say who issued the license.",
        "credential_exists": "This credential is already on the list.",
        "forbidden": "You don’t have permission to do this.",
    ]
}

/// Whose row it is, as the Records list shows it (web `PetLine` → `PetCell`): the pet's face, its
/// name, what it is ("Perro · Schnauzer", so two Lunas don't pass for one) and its owner.
struct StockPetLine: View {
    let petName: String?
    let species: String?
    let photoUrl: String?
    let clientName: String?
    var breed: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            PetAvatar(name: petName, species: species, photoURL: photoUrl, size: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text(petName?.nonEmpty ?? L("Patient")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                if let kind = kindLine { Text(kind).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                if let clientName = clientName?.nonEmpty { Text(clientName).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
            }
        }
    }

    private var kindLine: String? {
        let language = LocalizationManager.shared.currentLanguage == .english ? "en" : "es"
        let line = [StockDocWords.species(species, language), breed?.nonEmpty].compactMap { $0 }.joined(separator: " · ")
        return line.nonEmpty
    }
}

/// "Controlled" (or its class) as a pill (web `ControlledPill`): the red tone with the scale.
struct StockControlledChip: View {
    var label: String? = nil
    var body: some View { Chip(label ?? L("Controlled"), color: Theme.destructive, percent: 22, icon: "scale", dot: true) }
}

/// A prescription's state as a pill (web `StatePill`).
struct StockRxStatePill: View {
    let state: String
    var body: some View { Chip(StockRxWords.state(state), color: StockRxWords.stateState(state).color, percent: 22, dot: true) }
}

/// A refill request's status as a pill (web `RefillPill`).
struct StockRefillPill: View {
    let status: String
    var body: some View {
        Chip(StockRxWords.refill(status), color: ["pending", "approved", "ready", "declined"].contains(status) ? StockRxWords.refillState(status).color : Theme.borderStrong, percent: 22, dot: true)
    }
}

/// A small chip of the prescription sheet (web `RxChip`): 11.2 extrabold on the tone at 14%.
struct StockRxChip: View {
    let text: String
    var tone: Color = Theme.inkSoft
    var icon: String? = nil
    var strong: Bool = false
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Glyph(icon, size: 12) }
            Text(text).lineLimit(1)
        }
        .font(.brandText(11.2, weight: .heavy))
        .foregroundStyle(Theme.inkStrong)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Theme.wash(tone, strong ? 26 : 14), in: Capsule())
        .fixedSize()
    }
}

/// "Controlled" on the prescription sheet (web `ControlledChip`): the coral chip with the scale.
struct StockRxControlledChip: View {
    var label: String? = nil
    var body: some View { StockRxChip(text: label ?? L("Controlled"), tone: Theme.coral, icon: "scale", strong: true) }
}

/// A number of the prescription form (web `RxField` + `RxSuffixed`): the kit's label, the field
/// chrome, the unit inside it.
struct StockRxNumberField: View {
    let label: String
    @Binding var text: String
    var key: String? = nil
    var form: FormState? = nil
    var prompt: String = ""
    var hint: String? = nil
    var optional: Bool = false
    var suffix: String? = nil
    var decimal: Bool = false

    var body: some View {
        FormField(label: label, key: key, hint: hint, form: form, optional: optional) {
            HStack(spacing: 6) {
                TextField(prompt, text: $text)
                    .keyboardType(decimal ? .decimalPad : .numberPad)
                    .monospacedDigit()
                if let suffix { Text(suffix).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
            }
            .fieldChrome(invalid: key.flatMap { form?.error($0) } != nil)
            .onChange(of: text) { _, _ in if let key { form?.clear(key) } }
        }
    }
}

/// "Open chart", on every row (web `ChartLink`).
struct StockChartLink: View {
    let clientId: String?
    let petId: String?
    let canViewClients: Bool
    var body: some View {
        if canViewClients, let clientId = clientId?.nonEmpty, let petId = petId?.nonEmpty {
            NavigationLink(value: ProviderRoute.clientPet(clientId: clientId, petId: petId)) {
                PMButtonContent(title: L("Open chart"), variant: .link, size: .modal)
            }
            .buttonStyle(.pm(.link, size: .modal))
        }
    }
}

/// A period of days for a list or a report (web `DateRangeMenu`): a chip that names the range
/// ("Esta semana", "1 sep – 15 sep") in the chips' "on" colours, or "Any date"; it opens the quick
/// choices and the two days.
struct StockPeriodButton: View {
    let label: String
    var noneLabel: String = L("Any date")
    @Binding var from: String
    @Binding var to: String
    @State private var choosing = false

    var body: some View {
        let chosen = !from.isEmpty || !to.isEmpty
        FilterChip(title: chosen ? StockPeriod.label(from, to) : noneLabel, isSelected: chosen, icon: "calendar-range") {
            choosing = true
        }
        .accessibilityLabel(chosen ? "\(label): \(StockPeriod.label(from, to))" : label)
        .sheet(isPresented: $choosing) {
            StockPeriodSheet(title: label, noneLabel: noneLabel, from: $from, to: $to)
        }
    }
}

/// The quick ranges of the web's date menu (records-list-logic.ts `rangePresets`).
enum StockPeriod {
    enum Preset: CaseIterable { case today, week, month }

    static func range(_ preset: Preset) -> (from: String, to: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Workspace.shared.timeZone
        calendar.firstWeekday = 2
        let now = Date()
        let zone = Workspace.shared.timeZone
        let key: (Date) -> String = { DateText.dayFormatter(zone).string(from: $0) }
        switch preset {
        case .today:
            return (key(now), key(now))
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return (key(start), key(calendar.date(byAdding: .day, value: 6, to: start) ?? now))
        case .month:
            let interval = calendar.dateInterval(of: .month, for: now)
            let start = interval?.start ?? now
            let end = interval.map { $0.end.addingTimeInterval(-1) } ?? now
            return (key(start), key(end))
        }
    }

    static func name(_ preset: Preset) -> String {
        switch preset {
        case .today: L("Today")
        case .week: L("This week")
        case .month: L("This month")
        }
    }

    static func preset(_ from: String, _ to: String) -> Preset? {
        Preset.allCases.first { range($0) == (from, to) }
    }

    /// What a range is called: its quick choice's name, else its days.
    static func label(_ from: String, _ to: String) -> String {
        if let preset = preset(from, to) { return name(preset) }
        if !from.isEmpty && !to.isEmpty { return from == to ? StockText.day(from) : "\(StockText.day(from)) – \(StockText.day(to))" }
        return !from.isEmpty ? LF("From %@", StockText.day(from)) : LF("Until %@", StockText.day(to))
    }
}

private struct StockPeriodSheet: View {
    let title: String
    let noneLabel: String
    @Binding var from: String
    @Binding var to: String
    @Environment(\.dismiss) private var dismiss
    @State private var draftFrom = ""
    @State private var draftTo = ""
    @State private var started = false
    @StateObject private var form = FormState()

    var body: some View {
        ProviderModal(title: title, systemImage: "calendar-range", accent: .aqua, form: form, primaryTitle: L("Apply"), onPrimary: {
            guard form.check([("to", !draftFrom.isEmpty && !draftTo.isEmpty && draftTo < draftFrom ? L("The end can’t be before the start.") : nil)]) else { return }
            from = draftFrom
            to = draftTo
            dismiss()
        }) {
            let current = StockPeriod.preset(from, to)
            VStack(spacing: 4) {
                ForEach(StockPeriod.Preset.allCases, id: \.self) { preset in
                    choice(StockPeriod.name(preset), on: current == preset) {
                        let range = StockPeriod.range(preset)
                        from = range.from; to = range.to
                        dismiss()
                    }
                }
                choice(noneLabel, on: from.isEmpty && to.isEmpty) {
                    from = ""; to = ""
                    dismiss()
                }
            }
            Text(L("Or choose the days")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
            DayField(label: L("From"), day: $draftFrom, optional: true, clearable: true)
            DayField(label: L("To"), day: $draftTo, key: "to", form: form, optional: true, clearable: true)
        }
        .presentationDetents([.large])
        .onAppear {
            guard !started else { return }
            started = true
            draftFrom = from
            draftTo = to
        }
    }

    /// A quick choice, as the web's menu rows: 14 bold, a blue check on the one in use.
    private func choice(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                Spacer()
                if on { Glyph("check", size: 16).foregroundStyle(Theme.blue) }
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(on ? AnyShapeStyle(Theme.wash(Theme.blue, 12)) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
