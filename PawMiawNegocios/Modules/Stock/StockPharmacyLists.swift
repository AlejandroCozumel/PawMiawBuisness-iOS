//
//  StockPharmacyLists.swift
//  PawMiawNegocios
//
//  The Pharmacy's lists (web pharmacy/prescriptions-tab.tsx, register-tab.tsx,
//  report-tab.tsx):
//  - every prescription of the business, by state (each chip with how many),
//    controlled only, about to expire, by the days they were signed, by folio,
//    medicine, pet or client — 20 at a time, under the day they were signed;
//  - the controlled register: each controlled medicine with its balance
//    against Inventory, one medicine's register for a period (opening, in,
//    out, closing, each line with the balance after it), every movement, and
//    the plain log of everything dispensed against a prescription, with
//    "Owner counselled", the PDF and the CSV;
//  - the period's report.
//  The web's "Print" is the PDF here: the share sheet prints it. Every list
//  sits in one panel, as on the web, and adds 20 rows as it is scrolled.
//

import SwiftUI

// MARK: - Prescriptions

struct StockRxFilters: Equatable {
    var state: String = "active"
    var controlled = false
    var expiring = false
    var q = ""
    var from = ""
    var to = ""

    var narrowed: Bool { !q.isEmpty || controlled || expiring || !from.isEmpty || !to.isEmpty }
}

/// Keeps what the first page of a list said besides its rows (the state counts).
@MainActor
final class StockCountsBox: ObservableObject {
    @Published var counts: [String: Int]?
}

/// One colour and icon per state chip: the one its pill wears.
private func rxStateChip(_ state: String) -> (tone: ChipTone, icon: String) {
    switch state {
    case "active": (.active, "badge-check")
    case "draft": (.upcoming, "clock-3")
    case "expired": (.closed, "hourglass")
    case "used_up": (.done, "package-check")
    case "cancelled": (.closed, "circle-slash")
    default: (.page, "layout-grid")
    }
}

struct StockPrescriptionsTab: View {
    @Binding var filters: StockRxFilters
    let rights: StockRxRights
    let onOpen: (String) -> Void
    let onNew: (() -> Void)?

    @State private var typed = ""
    @StateObject private var box = StockCountsBox()
    @StateObject private var pager = Pager<StockPrescription>(pageSize: stockPageSize) { _, _ in Page(items: [], total: 0, hasMore: false) }

    private static let states = ["active", "draft", "expired", "used_up", "cancelled", "all"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SearchField(prompt: L("Folio, medicine, pet or client"), text: $typed)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Self.states, id: \.self) { state in
                            let chip = rxStateChip(state)
                            ToneChip(StockRxWords.state(state), icon: chip.icon, tone: chip.tone, count: box.counts?[state], isOn: filters.state == state) { filters.state = state }
                        }
                        ChipRule()
                        ToneChip(L("Controlled only"), icon: "scale", tone: .sky, isOn: filters.controlled) { filters.controlled.toggle() }
                        ToneChip(L("Expiring soon@rx"), icon: "calendar-clock", tone: .waiting, isOn: filters.expiring) {
                            filters.expiring.toggle()
                            if filters.expiring { filters.state = "all" }
                        }
                        StockPeriodButton(label: L("Signed on"), from: $filters.from, to: $filters.to)
                    }
                    .padding(.vertical, 2)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                ListCard(style: .panel) { list }
                if pager.loadedOnce, let total = pager.total {
                    ListCount(shown: pager.items.count, total: total, one: L("1 prescription"), many: L("%d prescriptions"))
                }
            }
        }
        .onAppear { typed = filters.q }
        .debounced(typed) { text in
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed != filters.q { filters.q = trimmed }
        }
        .reloadsOnScope { await reload() }
        .onChange(of: filters) { _, _ in Task { await reload() } }
    }

    @ViewBuilder
    private var list: some View {
        if !pager.loadedOnce && pager.isLoading {
            LoadingState()
        } else if pager.error != nil, pager.items.isEmpty {
            EmptyState(systemImage: "pill", title: L("The prescriptions could not be loaded."), actionTitle: L("Try again"), action: { Task { await pager.reload() } }, accent: Theme.pink)
        } else if pager.items.isEmpty {
            if filters.narrowed || (box.counts?["all"] ?? 0) > 0 {
                EmptyState(systemImage: "pill", title: filters.narrowed ? L("No prescription matches these filters.") : L("No prescriptions in this state."),
                           actionTitle: filters.narrowed ? L("Clear the filters") : nil,
                           action: filters.narrowed ? { filters = StockRxFilters(state: filters.state); typed = "" } : nil, accent: Theme.mango)
            } else {
                EmptyState(systemImage: "pill", title: L("No prescriptions yet"),
                           message: onNew != nil ? L("Prescriptions appear here when a vet signs one from a visit or a pet’s chart. Start one now.") : L("Prescriptions appear here when a vet signs one from a visit or a pet’s chart."),
                           actionTitle: onNew != nil ? L("New prescription") : nil, action: onNew, accent: Theme.mango)
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Self.groups(pager.items), id: \.key) { group in
                    DayBand(title: StockText.day(group.day), style: .caps)
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, prescription in
                        if index > 0 { RowDivider() }
                        Button { onOpen(prescription.id) } label: {
                            StockRxListRow(prescription: prescription, canViewClients: rights.canViewClients)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LF("Open %@: %@", prescription.folio ?? L("the draft"), prescription.medicines))
                        .onAppear { pager.loadMoreIfNeeded(prescription) }
                    }
                    RowDivider()
                }
                PagerFooter(pager: pager)
            }
        }
    }

    /// Rows under the day they were signed (made, for a draft), in the order they came.
    static func groups(_ items: [StockPrescription]) -> [(key: String, day: String, items: [StockPrescription])] {
        var groups: [(key: String, day: String, items: [StockPrescription])] = []
        for item in items {
            let day = DateText.parse(item.signedAt ?? item.createdAt).map { DateText.dayFormatter(Workspace.shared.timeZone).string(from: $0) } ?? ""
            if let last = groups.last, last.day == day {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append(("\(day)-\(groups.count)", day, [item]))
            }
        }
        return groups
    }

    private func reload() async {
        let f = filters
        let box = box
        pager.fetch = { offset, limit in
            let page: StockPrescriptionPage = try await API.get("/provider-prescriptions", query: [
                "state": f.state == "all" ? nil : f.state,
                "controlled": f.controlled ? "true" : nil,
                "expiring": f.expiring ? "true" : nil,
                "q": f.q.nonEmpty,
                "from": f.from.nonEmpty,
                "to": f.to.nonEmpty,
                "counts": "true",
                "limit": "\(limit)",
                "offset": offset > 0 ? "\(offset)" : nil,
            ])
            if offset == 0 { box.counts = page.stateCounts }
            return Page(items: page.items, total: page.total, hasMore: page.hasMore)
        }
        await pager.reload()
    }
}

/// One prescription in the Pharmacy's list (web `PrescriptionRow`): whose, which medicines, what is
/// left, then its pills and its state.
private struct StockRxListRow: View {
    let prescription: StockPrescription
    let canViewClients: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                StockPetLine(petName: prescription.petName, species: prescription.petSpecies, photoUrl: prescription.petPhotoUrl, clientName: prescription.clientName, breed: prescription.petBreed)
                Spacer(minLength: 4)
                Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
            }
            StockRxSummary(prescription: prescription)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// What a prescription row says under whose it is: its medicines, folio, prescriber, what is left, and its pills.
private struct StockRxSummary: View {
    let prescription: StockPrescription

    var body: some View {
        let left = prescription.isSigned ? prescription.items.reduce(0) { $0 + ($1.fill?.remaining ?? 0) } : nil
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(prescription.medicines).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                StockMetaLine(parts: [
                    prescription.folio,
                    prescription.prescriberName,
                    left != nil && prescription.state == "active" ? LF("%d left", left ?? 0) : nil,
                    prescription.validUntil != nil && prescription.state == "active" ? LF("valid until %@", StockText.day(prescription.validUntil)) : nil,
                ])
            }
            FlowLayout(spacing: 8) {
                if prescription.controlled == true { StockControlledChip() }
                if prescription.expiresSoon == true { StockRxChip(text: L("Expires soon"), tone: Theme.lime, strong: true) }
                StockRxStatePill(state: prescription.state)
            }
        }
    }
}

/// One prescription as a card of its own (a visit's prescriptions): the same row, on a card.
struct StockPrescriptionRow: View {
    let prescription: StockPrescription

    var body: some View {
        Card(padding: 14) {
            HStack(alignment: .center) {
                StockPetLine(petName: prescription.petName, species: prescription.petSpecies, photoUrl: prescription.petPhotoUrl, clientName: prescription.clientName, breed: prescription.petBreed)
                Spacer(minLength: 6)
                Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
            }
            StockRxSummary(prescription: prescription)
        }
    }
}

// MARK: - The controlled register

private enum RegisterView: Hashable { case medicines, movements, dispensed }

private let registerTypes = ["received", "dispensed", "administered", "returned", "waste", "count"]
private let rareRegisterTypes = ["sold", "opening", "adjustment"]

private func registerTypeLabel(_ type: String) -> String {
    switch type {
    case "received": L("Received@register")
    case "dispensed": L("Dispensed")
    case "administered": L("Given in the clinic")
    case "returned": L("Returned@register")
    case "waste": L("Written off@register")
    case "count": L("Count@register")
    case "sold": L("Sold, no prescription on file")
    case "opening": L("Opening count")
    case "adjustment": L("Adjustment")
    default: type
    }
}

/// What each movement was: its colour and icon (web `TYPE_META`, `REGISTER_MOVEMENT_TONE`).
private func registerTypeMeta(_ type: String) -> (tone: ChipTone, icon: String) {
    switch type {
    case "received": (.hue(.mint), "arrow-down-to-line")
    case "dispensed": (.hue(.sky), "pill")
    case "administered": (.hue(.teal), "syringe")
    case "returned": (.hue(.periwinkle), "rotate-ccw")
    case "waste": (.problem, "trash-2")
    case "count", "opening": (.hue(.butter), "clipboard-list")
    case "sold": (.hue(.peach), "arrow-up-from-line")
    default: (.hue(.grey), "clipboard-list")
    }
}

struct StockRegisterTab: View {
    let onOpen: (String) -> Void

    @EnvironmentObject private var workspace: Workspace
    @State private var view: RegisterView = .medicines
    @State private var medicine: StockRegisterMedicine?
    @State private var medicines: StockRegisterMedicines?
    @State private var medicinesError: String?
    @State private var typed = ""
    @State private var q = ""
    @State private var from = ""
    @State private var to = ""
    @State private var types: Set<String> = []
    @State private var locationId: String?
    @State private var stock: [StockRow] = []
    @State private var sheet: StockInventorySheet?
    @State private var counselling: StockCounselTarget?

    private var canReceive: Bool { workspace.can(.inventoryReceive) }
    private var canCount: Bool { workspace.can(.inventoryCount) }
    private var canCounsel: Bool { workspace.can(.salesSell) || workspace.can(.recordsCreate) }
    private var places: [ProviderLocation] { workspace.activeLocations }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Segmented(options: [
                    .init(RegisterView.medicines, L("By medicine"), icon: "scale", tone: .page),
                    .init(.movements, L("All movements"), icon: "clipboard-list", tone: .page),
                    .init(.dispensed, L("Everything dispensed"), icon: "pill", tone: .page),
                ], selection: $view, look: .raised, label: L("What the register shows"), fill: true)
                .onChange(of: view) { _, _ in medicine = nil; types = []; locationId = nil; typed = ""; q = "" }
                if view != .dispensed, medicines?.stockIsBusinessWide == true, (medicines?.locations ?? 0) > 1 || places.count > 1 {
                    HStack(spacing: 6) {
                        Glyph("info", size: 16)
                        Text(L("Stock is counted for the whole business, not per location."))
                    }
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
            switch view {
            case .dispensed:
                StockDispensedLog(typed: $typed, q: q, from: $from, to: $to, canCounsel: canCounsel, onCounsel: { counselling = $0 }, onOpen: onOpen)
            case .medicines where medicine == nil:
                medicineList
            default:
                StockRegisterMovements(medicine: medicine, medicines: medicines?.items ?? [], typed: $typed, q: q, from: $from, to: $to, types: $types, locationId: $locationId,
                                       places: places, canCounsel: canCounsel, actions: medicine.map(actions),
                                       onBack: { medicine = nil; types = []; typed = ""; q = "" }, onPick: { picked in medicine = picked; types = []; typed = ""; q = "" },
                                       onCounsel: { counselling = $0 }, onOpen: onOpen)
            }
            Text(L("Format based on public sources; a professional must review it before use."))
                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
        .debounced(typed) { text in
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed != q { q = trimmed }
        }
        .reloadsOnScope { await loadMedicines() }
        .onChange(of: q) { _, _ in if view == .medicines && medicine == nil { Task { await loadMedicines() } } }
        .sheet(item: $sheet) { which in
            switch which {
            case .receive(let row): StockReceiveSheet(preset: row, severalLocations: places.count > 1, onSaved: saved)
            case .count(let row): StockAdjustSheet(row: row, kind: .count, lotId: nil, onSaved: saved)
            case .waste(let row, let lot): StockAdjustSheet(row: row, kind: .waste, lotId: lot, onSaved: saved)
            default: EmptyView()
            }
        }
        .sheet(item: $counselling) { target in StockCounselSheet(target: target) }
    }

    private func saved() {
        announceDataChanged()
    }

    private func loadMedicines() async {
        do {
            medicines = try await API.get("/provider-pharmacy/register/medicines", query: ["q": view == .medicines && medicine == nil ? q.nonEmpty : nil])
            medicinesError = nil
            if let chosen = medicine { medicine = medicines?.items.first { $0.catalogItemId == chosen.catalogItemId } ?? chosen }
        } catch is CancellationError {
        } catch {
            medicinesError = errorText(error)
        }
        if workspace.can(.inventoryView) && (canReceive || canCount), let rows: [StockRow] = try? await API.get("/provider-stock") { stock = rows }
    }

    /// A medicine as Inventory's sheets want it, when the stock list hasn't got it (its stock isn't counted yet).
    private func asRow(_ medicine: StockRegisterMedicine) -> StockRow {
        if let row = stock.first(where: { $0.inventoryItemId != nil && $0.inventoryItemId == medicine.inventoryItemId }) { return row }
        return StockRow(inventoryItemId: medicine.inventoryItemId, catalogItemId: medicine.catalogItemId, name: medicine.name, sku: medicine.sku, barcode: nil, photoUrl: medicine.photoUrl,
                        productKind: "medication", quantityOnHand: medicine.onHand ?? 0, reorderPoint: medicine.reorderPoint ?? 0, unitCostAmount: nil, lowStock: medicine.lowStock ?? false,
                        lots: (medicine.lots ?? []).map { StockLot(id: $0.id, lotCode: $0.lotCode, expiresOn: $0.expiresOn, quantityOnHand: $0.quantityOnHand ?? 0, unitCostAmount: nil, receivedAt: nil) },
                        packs: medicine.packs ?? [], tracked: medicine.tracked, controlSchedule: medicine.controlSchedule)
    }

    private func actions(_ medicine: StockRegisterMedicine) -> StockRegisterActions {
        let ready = medicine.inventoryItemId == nil || stock.contains { $0.inventoryItemId == medicine.inventoryItemId }
        return StockRegisterActions(
            name: medicine.name,
            receive: canReceive && medicine.active != false ? { sheet = .receive(asRow(medicine)) } : nil,
            count: canCount && medicine.inventoryItemId != nil && ready ? { sheet = .count(asRow(medicine)) } : nil,
            waste: canCount && medicine.inventoryItemId != nil && ready ? { sheet = .waste(asRow(medicine), lotId: nil) } : nil
        )
    }

    @ViewBuilder
    private var medicineList: some View {
        VStack(alignment: .leading, spacing: 16) {
            SearchField(prompt: L("Medicine or SKU"), text: $typed)
            VStack(alignment: .leading, spacing: 12) {
                ListCard(style: .panel) {
                    if medicines == nil {
                        if let medicinesError { ErrorState(message: medicinesError) { await loadMedicines() } } else { LoadingState() }
                    } else if let items = medicines?.items, items.isEmpty {
                        EmptyState(systemImage: "scale", title: q.isEmpty ? L("No controlled medicines yet") : LF("No controlled medicine matches “%@”.", q),
                                   message: q.isEmpty ? L("A medicine is controlled when its Catalog item has a control class. Its register starts with its first delivery in Inventory.") : nil, accent: Theme.mango)
                    } else if let items = medicines?.items {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, medicine in
                            if index > 0 { RowDivider() }
                            medicineRow(medicine)
                        }
                    }
                }
                if let items = medicines?.items {
                    ListCount(shown: items.count, total: items.count, one: L("1 controlled medicine"), many: L("%d controlled medicines"))
                }
            }
        }
    }

    private func medicineRow(_ medicine: StockRegisterMedicine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { self.medicine = medicine; types = []; typed = ""; q = "" } label: {
                VStack(alignment: .leading, spacing: 2) {
                    FlowLayout(spacing: 8) {
                        Text(medicine.name).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        if let schedule = StockRxWords.schedule(medicine.controlSchedule) { StockControlledChip(label: schedule) }
                        if let discrepancy = medicine.discrepancy { Chip(LF("Doesn’t match Inventory: %@", StockText.signed(discrepancy.difference ?? 0)), color: Theme.destructive, percent: 22, dot: true) }
                        if medicine.active == false { Chip(L("Archived@medicine"), color: Theme.borderStrong, percent: 22, dot: true) }
                    }
                    Text(medicine.tracked != false
                         ? [medicine.sku, medicine.lastMovementAt.map { LF("last movement %@", StockText.dateTime($0)) } ?? L("no movements yet"),
                            (medicine.movements ?? 0) == 0 ? nil : ((medicine.movements ?? 0) == 1 ? L("1 movement") : LF("%d movements", medicine.movements ?? 0))].compactMap { $0?.nonEmpty }.joined(separator: " · ")
                         : L("Its stock isn’t counted yet: the register starts with its first delivery."))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    if let lots = medicine.lots, !lots.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(lots.prefix(3), id: \.id) { lot in
                                stockLotChip(code: lot.lotCode, quantity: lot.quantityOnHand ?? 0, expiresOn: lot.expiresOn, today: medicines?.today ?? StockRules.today)
                            }
                            if lots.count > 3 { Text(LF("+%d more", lots.count - 3)).font(.brandText(11.2, weight: .bold)).foregroundStyle(Theme.inkSoft) }
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LF("Open the register of %@", medicine.name))
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(StockText.count(medicine.registerBalance ?? 0)).font(.brandHeading(24)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    Text(medicine.discrepancy != nil ? LF("in the register · %@ in Inventory", StockText.count(medicine.onHand ?? 0)) : L("balance"))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
                StockRegisterActionButtons(actions: actions(medicine), compact: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct StockRegisterActions {
    let name: String
    let receive: (() -> Void)?
    let count: (() -> Void)?
    let waste: (() -> Void)?
}

/// Receive, count, write off: round icons on a list's row, labelled buttons over one medicine's register.
private struct StockRegisterActionButtons: View {
    let actions: StockRegisterActions
    var compact: Bool = false
    var body: some View {
        if actions.receive != nil || actions.count != nil || actions.waste != nil {
            if compact {
                HStack(spacing: 6) {
                    if let receive = actions.receive { StockIconButton(icon: "package-plus", label: LF("Receive %@", actions.name), action: receive) }
                    if let count = actions.count { StockIconButton(icon: "clipboard-list", label: LF("Count %@", actions.name), action: count) }
                    if let waste = actions.waste { StockIconButton(icon: "trash-2", label: LF("Write off %@", actions.name), action: waste) }
                }
            } else {
                FlowLayout(spacing: 8) {
                    if let receive = actions.receive { PMButton(L("Receive"), systemImage: "package-plus", variant: .outline, size: .compact, action: receive) }
                    if let count = actions.count { PMButton(L("Count"), systemImage: "clipboard-list", variant: .outline, size: .compact, action: count) }
                    if let waste = actions.waste { PMButton(L("Write off"), systemImage: "trash-2", variant: .outline, size: .compact, action: waste) }
                }
            }
        }
    }
}

/// One medicine's register, or every controlled medicine's movements, for a period.
private struct StockRegisterMovements: View {
    let medicine: StockRegisterMedicine?
    let medicines: [StockRegisterMedicine]
    @Binding var typed: String
    let q: String
    @Binding var from: String
    @Binding var to: String
    @Binding var types: Set<String>
    @Binding var locationId: String?
    let places: [ProviderLocation]
    let canCounsel: Bool
    let actions: StockRegisterActions?
    let onBack: () -> Void
    let onPick: (StockRegisterMedicine) -> Void
    let onCounsel: (StockCounselTarget) -> Void
    let onOpen: (String) -> Void

    @State private var limit = stockPageSize
    @State private var data: StockControlledRegister?
    @State private var loadError: String?
    @State private var loadingMore = false

    private var single: Bool { medicine != nil }
    private var query: [String: String?] {
        [
            "catalogItemId": medicine?.catalogItemId,
            "from": from.nonEmpty,
            "to": to.nonEmpty,
            "types": types.isEmpty ? nil : types.sorted().joined(separator: ","),
            "locationId": locationId,
            "q": q.nonEmpty,
        ]
    }
    private var key: String { [medicine?.catalogItemId ?? "", from, to, types.sorted().joined(separator: ","), locationId ?? "", q].joined(separator: "|") }
    private var title: String { single ? (data?.medicine?.name ?? medicine?.name ?? "") : L("Every controlled medicine") }
    private var period: String { data.map { "\(StockText.day($0.from)) – \(StockText.day($0.to))" } ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if single, let medicine { summary(medicine) }
            VStack(alignment: .leading, spacing: 8) {
                SearchField(prompt: L("Patient, folio, lot or note"), text: $typed)
                FlowLayout(spacing: 8) {
                    StockPeriodButton(label: L("Period"), noneLabel: L("Last 30 days"), from: $from, to: $to)
                    if !single && !medicines.isEmpty {
                        Menu {
                            ForEach(medicines.filter { $0.tracked != false }) { entry in Button(entry.name) { onPick(entry) } }
                        } label: {
                            FilterMenuLabel(title: L("Every medicine"))
                        }
                        .accessibilityLabel(L("Open one medicine’s register"))
                    }
                    if places.count > 1 {
                        Menu {
                            Button(L("Every location")) { locationId = nil }
                            ForEach(places) { place in Button(place.name) { locationId = place.id } }
                        } label: {
                            FilterMenuLabel(title: places.first { $0.id == locationId }?.name ?? L("Every location"), selected: locationId != nil)
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(registerTypes + rareRegisterTypes.filter { (data?.typeCounts?[$0] ?? 0) > 0 || types.contains($0) }, id: \.self) { type in
                            let meta = registerTypeMeta(type)
                            ToneChip(registerTypeLabel(type), icon: meta.icon, tone: meta.tone, count: data?.typeCounts?[type], isOn: types.contains(type)) {
                                if types.contains(type) { types.remove(type) } else { types.insert(type) }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                if places.count > 1 && locationId != nil {
                    Text(L("Showing the movements recorded at this location. The balance is the whole business’s.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                FlowLayout(spacing: 8) {
                    if single {
                        DocumentButton(title: L("Download PDF"), systemImage: "file-down", path: "/provider-pharmacy/register/pdf", query: query, fileName: "\(L("Controlled register")) \(title)", size: .regular)
                            .disabled(data == nil)
                    }
                    DocumentButton(title: L("Download CSV"), systemImage: "file-spreadsheet", path: "/provider-pharmacy/register/csv", query: query, fileName: "\(L("Controlled register")) \(title)", ext: "csv", size: .regular)
                        .disabled((data?.total ?? 0) == 0)
                }
                ListCard(style: .panel) { list }
                if let data, !data.items.isEmpty {
                    ListCount(shown: data.items.count, total: data.total ?? data.items.count, one: L("1 movement"), many: L("%d movements"))
                }
                if data?.truncated == true {
                    Text(L("This period has more movements than can be listed at once: shorten it to see them all.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                Text(L("Read from Inventory: it can’t be edited here. A correction is a new movement — a count, a write-off, a return."))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
        .reloadsOnScope { await load() }
        .onChange(of: key) { _, _ in
            limit = stockPageSize
            Task { await load() }
        }
    }

    /// The medicine's name, its opening, in, out and closing, and whether Inventory agrees.
    private func summary(_ medicine: StockRegisterMedicine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 12) {
                PMButton(L("All medicines"), systemImage: "arrow-left", variant: .outline, size: .compact, action: onBack)
                if let actions { StockRegisterActionButtons(actions: actions) }
            }
            VStack(alignment: .leading, spacing: 0) {
                FlowLayout(spacing: 8) {
                    Text(title).font(.brandHeading(20)).foregroundStyle(Theme.inkStrong)
                    if let schedule = StockRxWords.schedule(data?.medicine?.controlSchedule ?? medicine.controlSchedule) { StockControlledChip(label: schedule) }
                }
                if let data, let opening = data.openingBalance, let closing = data.closingBalance {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                        balance(L("Opening balance"), StockText.count(opening))
                        balance(L("In"), "+\(StockText.count(data.unitsIn ?? 0))")
                        balance(L("Out"), "−\(StockText.count(data.unitsOut ?? 0))")
                        balance(L("Closing balance"), StockText.count(closing))
                    }
                    .padding(.top, 12)
                }
                if let onHand = data?.medicine?.onHand {
                    Text(LF("%@ · Inventory has %@ on hand today.", period, StockText.count(onHand))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).padding(.top, 8)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 2))
            if let discrepancy = data?.discrepancy {
                NoticeCard(tone: .problem, title: L("The register and Inventory don’t match."), message: LF("The register adds up to %@; Inventory has %@ on hand: a difference of %@. Count the medicine to set it right.",
                                       StockText.count(discrepancy.registerBalance ?? 0), StockText.count(discrepancy.onHand ?? 0), StockText.signed(discrepancy.difference ?? 0)), icon: "triangle-alert")
            }
        }
    }

    /// One of the four balances (web: a muted box, 12 bold label, Fredoka 24).
    private func balance(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
            Text(value).font(.brandHeading(24)).monospacedDigit().foregroundStyle(Theme.inkStrong)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
    }

    @ViewBuilder
    private var list: some View {
        if data == nil {
            if let loadError { ErrorState(message: loadError) { await load() } } else { LoadingState() }
        } else if let data, data.items.isEmpty {
            let filtered = !types.isEmpty || !q.isEmpty || locationId != nil
            EmptyState(systemImage: "clipboard-list", title: filtered ? L("No movement matches these filters.") : L("No movements in this period"),
                       message: filtered ? nil : L("Deliveries, sales against a prescription, doses given in the clinic, write-offs and counts of controlled medicines show here as they happen."), accent: Theme.mango)
        } else if let data {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(data.items.enumerated()), id: \.element.id) { index, line in
                    if index > 0 { RowDivider() }
                    lineRow(line)
                }
                LoadMoreRow(hasMore: (data.total ?? data.items.count) > data.items.count, busy: loadingMore) {
                    guard !loadingMore else { return }
                    limit += stockPageSize
                    loadingMore = true
                    Task { await load(); loadingMore = false }
                }
            }
        }
    }

    private func load() async {
        var query = query
        query["limit"] = "\(limit)"
        do {
            data = try await API.get("/provider-pharmacy/register", query: query)
            loadError = nil
        } catch is CancellationError {
        } catch {
            loadError = errorText(error)
        }
    }

    private func lineRow(_ line: StockRegisterLine) -> some View {
        let lot = (line.lotCode != nil || line.lotExpiresOn != nil)
            ? [LF("Lot %@", line.lotCode ?? "—"), line.lotExpiresOn.map { LF("exp. %@", StockText.day($0)) }].compactMap { $0 }.joined(separator: " · ")
            : nil
        let who = [line.petName, line.clientName].compactMap { $0?.nonEmpty }.joined(separator: " · ")
        let prescriber = [line.prescriberName, line.prescriberCredential].compactMap { $0?.nonEmpty }.joined(separator: " · ")
        let actor: String? = line.actorName.map { name in
            line.type == "dispensed" ? LF("handed over by %@", name) : line.type == "administered" ? LF("given by %@", name) : LF("recorded by %@", name)
        }
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                FlowLayout(spacing: 8) {
                    Chip(registerTypeLabel(line.type), color: registerTypeMeta(line.type).tone.color, percent: 22, dot: true)
                    Text(StockText.dateTime(line.occurredAt)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    if !single, let product = line.productName { Text(product).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong) }
                }
                if !who.isEmpty { Text(who).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong) }
                if !prescriber.isEmpty { Text(LF("Prescribed by %@", prescriber)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                if let dose = line.doseText?.nonEmpty { Text(dose).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                if let note = line.note?.nonEmpty { Text(note).font(Theme.text(14)).foregroundStyle(Theme.inkStrong) }
                StockMetaLine(parts: [lot, line.prescriptionFolio, line.documentFolio, actor, line.witnessName.map { LF("witness: %@", $0) }, line.locationName])
                if line.type == "dispensed" || line.prescriptionId != nil {
                    FlowLayout(spacing: 8) {
                        if line.counselledAt != nil {
                            StockRxChip(text: L("Counselled") + (line.counselNote?.nonEmpty.map { ": \($0)" } ?? ""), tone: Theme.lime, icon: "hand-heart")
                        } else if line.type == "dispensed", let dispenseId = line.dispenseId, canCounsel {
                            PMButton(L("Record counselling"), systemImage: "hand-heart", variant: .ghost, size: .modal) {
                                onCounsel(StockCounselTarget(dispenseId: dispenseId, label: line.productName ?? "", petName: line.petName))
                            }
                        }
                        if let prescriptionId = line.prescriptionId {
                            PMButton(L("Open prescription"), systemImage: "file-text", variant: .ghost, size: .modal) { onOpen(prescriptionId) }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(StockText.signed(line.quantity ?? 0)).font(.brandHeading(20)).monospacedDigit()
                    .foregroundStyle((line.quantity ?? 0) < 0 ? AnyShapeStyle(Theme.inkStrong) : AnyShapeStyle(Theme.mix(ProviderState.done.color, 70, with: Theme.inkStrong)))
                Spacer()
                Text(LF("balance %@", StockText.count(line.balanceAfter ?? 0))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// "Everything dispensed": the dispensing log of every prescription medicine, controlled or not.
private struct StockDispensedLog: View {
    @Binding var typed: String
    let q: String
    @Binding var from: String
    @Binding var to: String
    let canCounsel: Bool
    let onCounsel: (StockCounselTarget) -> Void
    let onOpen: (String) -> Void

    @State private var limit = stockPageSize
    @State private var data: StockDispenseLog?
    @State private var loadError: String?
    @State private var loadingMore = false

    private var key: String { [q, from, to].joined(separator: "|") }
    private var query: [String: String?] { ["from": from.nonEmpty, "to": to.nonEmpty, "q": q.nonEmpty] }
    private var period: String { data.map { "\(StockText.day($0.from)) – \(StockText.day($0.to))" } ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SearchField(prompt: L("Medicine, patient, client or folio"), text: $typed)
                FlowLayout(spacing: 8) {
                    StockPeriodButton(label: L("Period"), noneLabel: L("Last 30 days"), from: $from, to: $to)
                    DocumentButton(title: L("Download PDF"), systemImage: "file-down", path: "/provider-pharmacy/dispenses/pdf", query: query, fileName: "\(L("Dispensing log")) \(period)", size: .regular)
                        .disabled((data?.total ?? 0) == 0)
                    DocumentButton(title: L("Download CSV"), systemImage: "file-spreadsheet", path: "/provider-pharmacy/dispenses/csv", query: query, fileName: "\(L("Dispensing log")) \(period)", ext: "csv", size: .regular)
                        .disabled((data?.total ?? 0) == 0)
                }
            }
            Text(L("Written by every sale, visit and stay bill that hands a medicine out against a prescription. It can’t be edited: a return is a new line."))
                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            ListCard(style: .panel) { list }
            if let data, !data.items.isEmpty {
                ListCount(shown: data.items.count, total: data.total ?? data.items.count, one: L("1 line"), many: L("%d lines"))
            }
        }
        .reloadsOnScope { await load() }
        .onChange(of: key) { _, _ in
            limit = stockPageSize
            Task { await load() }
        }
    }

    @ViewBuilder
    private var list: some View {
        if data == nil {
            if let loadError { ErrorState(message: loadError) { await load() } } else { LoadingState() }
        } else if let data, data.items.isEmpty {
            EmptyState(systemImage: "pill", title: q.isEmpty ? L("Nothing dispensed in this period.") : L("Nothing dispensed matches that."),
                       message: q.isEmpty ? L("Each medicine handed out against a prescription — at the Store, on a visit’s bill or an invoice — is listed here.") : nil, accent: Theme.mango)
        } else if let data {
            let mayCounsel = data.canCounsel ?? canCounsel
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(data.items.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { RowDivider() }
                    row(entry, mayCounsel: mayCounsel)
                }
                LoadMoreRow(hasMore: (data.total ?? data.items.count) > data.items.count, busy: loadingMore) {
                    guard !loadingMore else { return }
                    limit += stockPageSize
                    loadingMore = true
                    Task { await load(); loadingMore = false }
                }
            }
        }
    }

    private func row(_ entry: StockDispense, mayCounsel: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                FlowLayout(spacing: 8) {
                    Chip(entry.kind == "return" ? L("Returned@register") : L("Dispensed"), color: entry.kind == "return" ? Theme.butter : Theme.aqua, percent: 22, dot: true)
                    Text(StockText.dateTime(entry.occurredAt)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    Text(entry.label ?? "").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    if let schedule = StockRxWords.schedule(entry.controlSchedule) { StockControlledChip(label: schedule) }
                }
                Text([entry.petName, entry.clientName].compactMap { $0?.nonEmpty }.joined(separator: " · ").nonEmpty ?? "—").font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                StockMetaLine(parts: [
                    entry.prescriberName.map { LF("Prescribed by %@", [$0, entry.prescriberCredential].compactMap { $0?.nonEmpty }.joined(separator: " · ")) },
                    (entry.lots ?? []).isEmpty ? nil : (entry.lots ?? []).map { lot in LF("Lot %@", lot.code ?? "—") + (lot.expiresOn.map { " (\(LF("exp. %@", StockText.day($0))))" } ?? "") }.joined(separator: ", "),
                    entry.prescriptionFolio,
                    entry.documentFolio,
                    entry.dispensedByName.map { LF("handed over by %@", $0) },
                ])
                FlowLayout(spacing: 8) {
                    if entry.kind != "return" {
                        if entry.counselledAt != nil {
                            StockRxChip(text: L("Counselled") + (entry.counselNote?.nonEmpty.map { ": \($0)" } ?? ""), tone: Theme.lime, icon: "hand-heart")
                        } else if mayCounsel {
                            PMButton(L("Record counselling"), systemImage: "hand-heart", variant: .ghost, size: .modal) {
                                onCounsel(StockCounselTarget(dispenseId: entry.id, label: entry.label ?? "", petName: entry.petName))
                            }
                        }
                    }
                    if let prescriptionId = entry.prescriptionId {
                        PMButton(L("Open prescription"), systemImage: "file-text", variant: .ghost, size: .modal) { onOpen(prescriptionId) }
                    }
                }
                .padding(.top, 2)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(entry.quantity ?? 0)").font(.brandHeading(20)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                Spacer()
                if let sold = entry.sold?.nonEmpty { Text(LF("sold %@", sold)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func load() async {
        var query = query
        query["limit"] = "\(limit)"
        do {
            data = try await API.get("/provider-pharmacy/dispenses", query: query)
            loadError = nil
        } catch is CancellationError {
        } catch {
            loadError = errorText(error)
        }
    }
}

// MARK: - Owner counselled

struct StockCounselTarget: Identifiable, Hashable {
    let dispenseId: String
    let label: String
    let petName: String?
    var id: String { dispenseId }
}

/// "Owner counselled" on a dispense, with what was explained (optional).
struct StockCounselSheet: View {
    let target: StockCounselTarget
    var onSaved: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var saving = false

    var body: some View {
        ProviderModal(title: L("Owner counselled"), subtitle: [target.label, target.petName].compactMap { $0?.nonEmpty }.joined(separator: " · "),
                      systemImage: "hand-heart", accent: .aqua, isDirty: !note.isEmpty, primaryTitle: L("Record counselling"), isWorking: saving,
                      primaryIcon: "hand-heart", onPrimary: { Task { await save() } }) {
            PMTextField(L("What was explained"), text: $note, hint: L("How to give it, what to watch for, when to come back."), optional: true, multiline: true)
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await API.send("POST", "/provider-pharmacy/dispenses/\(target.dispenseId)/counsel", body: ["note": note.nonEmpty])
            Toast.show(L("Counselling recorded."))
            onSaved?()
            announceDataChanged()
            dismiss()
        } catch {
            Toast.error(StockRxWords.error(error))
        }
    }
}

// MARK: - Report

struct StockReportTab: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var from = ""
    @State private var to = ""
    @State private var data: StockPharmacyReport?
    @State private var loadError: String?

    private var query: [String: String?] { ["from": from.nonEmpty, "to": to.nonEmpty] }
    private var period: String { data.map { "\(StockText.day($0.from)) – \(StockText.day($0.to))" } ?? "" }
    private var empty: Bool {
        guard let data else { return false }
        return (data.totals.dispenses ?? 0) == 0 && (data.totals.prescriptionsSigned ?? 0) == 0 && (data.totals.units ?? 0) == 0 && data.refills.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 8) {
                    StockPeriodButton(label: L("Period"), noneLabel: L("Last 30 days"), from: $from, to: $to)
                    if !period.isEmpty { Text(period).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).frame(minHeight: 36) }
                }
                FlowLayout(spacing: 8) {
                    DocumentButton(title: L("Download PDF"), systemImage: "file-down", path: "/provider-pharmacy/report/pdf", query: query, fileName: "\(L("Pharmacy report")) \(period)", size: .regular)
                        .disabled(data == nil || empty)
                    DocumentButton(title: L("Download CSV"), systemImage: "file-spreadsheet", path: "/provider-pharmacy/report/csv", query: query, fileName: "\(L("Pharmacy report")) \(period)", ext: "csv", size: .regular)
                        .disabled(data == nil || empty)
                }
            }
            if data == nil {
                if let loadError {
                    ListCard(style: .panel) {
                        EmptyState(systemImage: "clipboard-list", title: L("The report could not be loaded."), message: loadError, actionTitle: L("Try again"), action: { Task { await load() } }, accent: Theme.pink)
                    }
                } else {
                    LoadingState()
                }
            } else if empty {
                ListCard(style: .panel) {
                    EmptyState(systemImage: "clipboard-list", title: L("Nothing in this period."), message: L("Once prescriptions are signed and their medicines handed out, the period’s numbers show here. Try a longer period."), accent: Theme.mango)
                }
            } else if let data {
                reportBody(data)
            }
        }
        .reloadsOnScope { await load() }
        .onChange(of: "\(from)|\(to)") { _, _ in Task { await load() } }
    }

    private func load() async {
        do {
            data = try await API.get("/provider-pharmacy/report", query: query)
            loadError = nil
        } catch is CancellationError {
        } catch {
            loadError = errorText(error)
        }
    }

    @ViewBuilder
    private func reportBody(_ data: StockPharmacyReport) -> some View {
        // Revenue is business finances: null for anyone else, and then not shown.
        let money: (Int?) -> String? = { amount in amount.map { Money.format($0, currency: data.currency) } }
        let totals = data.totals
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: sizeClass == .regular ? 5 : 2), alignment: .leading, spacing: 12) {
            tile(L("Prescriptions signed"), StockText.count(totals.prescriptionsSigned ?? 0), nil)
            tile(L("Dispenses"), StockText.count(totals.dispenses ?? 0), (totals.patients ?? 0) == 1 ? L("1 patient") : LF("%@ patients", StockText.count(totals.patients ?? 0)))
            tile(L("Units dispensed"), StockText.count(totals.units ?? 0), LF("%@ controlled", StockText.count(totals.controlledUnits ?? 0)))
            if let revenue = money(totals.revenueAmount) {
                tile(L("Revenue from prescription medicines"), revenue, L("What the bills charged for them, less returns"))
            }
            tile(L("Owners counselled"), StockText.count(totals.counselled ?? 0), (totals.dispenses ?? 0) == 1 ? L("of 1 dispense") : LF("of %@ dispenses", StockText.count(totals.dispenses ?? 0)))
        }
        section(L("By medicine")) {
            if data.byProduct.isEmpty {
                none(L("Nothing dispensed in this period."))
            } else {
                ForEach(Array(data.byProduct.enumerated()), id: \.offset) { index, row in
                    if index > 0 { RowDivider() }
                    VStack(alignment: .leading, spacing: 4) {
                        FlowLayout(spacing: 8) {
                            Text(row.label).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            if row.controlled == true { StockControlledChip() }
                        }
                        FlowLayout(spacing: 16) {
                            (Text(StockText.count(row.units ?? 0)).font(.brandHeading(16)).foregroundColor(Theme.inkStrong) + Text(" " + ((row.units ?? 0) == 1 ? L("unit") : L("units"))))
                            Text((row.dispenses ?? 0) == 1 ? L("1 dispense") : LF("%@ dispenses", StockText.count(row.dispenses ?? 0)))
                            Text(LF("%@ counselled", StockText.count(row.counselled ?? 0)))
                            if let revenue = money(row.revenueAmount) { Text(revenue).font(.brandHeading(16)).foregroundStyle(Theme.inkStrong) }
                        }
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        section(L("By prescriber")) {
            if data.byPrescriber.isEmpty {
                none(L("Nothing dispensed in this period."))
            } else {
                ForEach(Array(data.byPrescriber.enumerated()), id: \.offset) { index, row in
                    if index > 0 { RowDivider() }
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(row.name).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        Spacer(minLength: 8)
                        Text((row.dispenses ?? 0) == 1 ? L("1 dispense") : LF("%@ dispenses", StockText.count(row.dispenses ?? 0))).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        if let revenue = money(row.revenueAmount) { Text(revenue).font(.brandHeading(16)).foregroundStyle(Theme.inkStrong) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        section(L("Refill requests")) {
            if data.refills.isEmpty {
                none(L("No refill requests in this period."))
            } else {
                ForEach(Array(data.refills.keys.sorted().enumerated()), id: \.element) { index, status in
                    if index > 0 { RowDivider() }
                    HStack {
                        Text(StockRxWords.refill(status)).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        Spacer()
                        Text(StockText.count(data.refills[status] ?? 0)).font(.brandHeading(16)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    /// A section of the report: its name in Fredoka 18 over its panel.
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let body = content()
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.brandHeading(18)).foregroundStyle(Theme.inkStrong)
            ListCard(style: .panel) { body }
        }
    }

    private func none(_ text: String) -> some View {
        Text(text).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.horizontal, 16).padding(.vertical, 20)
    }

    /// A number of the period (web: a 2 pt bordered card, 12 bold label, Fredoka 24, a 12 hint).
    private func tile(_ label: String, _ value: String, _ hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            Text(value).font(.brandHeading(24)).monospacedDigit().foregroundStyle(Theme.inkStrong).lineLimit(1).minimumScaleFactor(0.6).padding(.top, 4)
            if let hint { Text(hint).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 2))
    }
}
