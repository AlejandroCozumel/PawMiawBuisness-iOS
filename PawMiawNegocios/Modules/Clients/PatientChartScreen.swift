//
//  PatientChartScreen.swift
//  PawMiawNegocios
//
//  The patient chart, the expediente (web: routes/provider.clients.$clientId.
//  pets.$petId.tsx and patient-chart/): the module header with the pet, its
//  owner and the numbers that matter (each opens its tab), the quick actions,
//  the red strip, the Olfato AI brief with the clinical summary, the
//  prescriptions and hospitalizations, then one card of tabs: the paged
//  history, visits, follow-ups, files, money and the pet's details. What a
//  role sees is the server's `viewer` ("who sees what").
//

import SwiftUI

/// A client's pet: its chart.
struct ClientPetScreen: View {
    let clientId: String
    let petId: String

    var body: some View {
        ClientsChartView(clientId: clientId, petId: petId)
    }
}

/// The chart of a pet known only by its id (from any screen): its client is found first.
struct PatientChartScreen: View {
    let petId: String

    @State private var clientId: String?
    @State private var failed = false

    var body: some View {
        Group {
            if let clientId {
                ClientsChartView(clientId: clientId, petId: petId)
            } else if failed {
                PageScroll {
                    EmptyState(systemImage: "paw-print", title: L("Pet not found"), message: L("It may have been combined with another record, or it belongs to a client assigned to someone else."), accent: Theme.lime, panel: true)
                }
                .providerPage(L("Patient chart"))
            } else {
                PageScroll { LoadingState() }
                    .providerPage(L("Patient chart"))
                    .task { await resolve() }
            }
        }
    }

    /// The chart is read under its client: the pet's records, visits, follow-ups, then the patients list say whose it is.
    private func resolve() async {
        let id = petId
        if let summary: JSONValue = try? await API.get("/provider-client-pets/\(id)/chart-summary"), let found = Self.clientId(in: summary) {
            clientId = found; return
        }
        if let visits: JSONValue = try? await API.get("/provider-appointments", query: ["limit": "1", "offset": "0", "providerClientPetId": id]), let found = Self.clientId(in: visits) {
            clientId = found; return
        }
        if let followUps: JSONValue = try? await API.get("/provider-follow-ups", query: ["limit": "1", "offset": "0", "status": "all", "providerClientPetId": id]), let found = Self.clientId(in: followUps) {
            clientId = found; return
        }
        for archived in [false, true] {
            var offset = 0
            while offset < 1000 {
                guard let page: Page<ClientsPatientRow> = try? await API.get("/provider-patients", query: ["limit": "50", "offset": "\(offset)", "archived": archived ? "true" : nil]) else { break }
                if let row = page.items.first(where: { $0.id == id }) { clientId = row.client.id; return }
                if page.items.count < 50 { break }
                offset += 50
            }
        }
        failed = true
    }

    private static func clientId(in value: JSONValue) -> String? {
        switch value {
        case .object(let object):
            if let id = object["providerClientId"]?.string?.nonEmpty { return id }
            for child in object.values { if let found = clientId(in: child) { return found } }
        case .array(let items):
            for child in items { if let found = clientId(in: child) { return found } }
        default: break
        }
        return nil
    }
}

enum ClientsChartTab: String, Hashable { case history, appointments, followups, files, billing, profile }

struct ClientsChartView: View {
    let clientId: String
    let petId: String

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var chart: ClientsChart?
    @State private var pet: ClientsPet?
    @State private var clientName = ""
    @State private var error: String?
    @State private var notFound = false
    @State private var tab: ClientsChartTab = .history
    @State private var weighing = false
    @State private var editing = false
    @State private var closing: ClientsClosingTarget?
    @State private var restoring: ClientsRestoreTarget?
    @State private var pushed: ClientsPush?
    @State private var route: ProviderRoute?
    @State private var client: ClientsClient?
    @State private var mergingPet: ClientsMergePetSource?
    @State private var movingPet: ClientsMoveTarget?
    @State private var unlinkingPet: ClientsUnlinkTarget?
    @State private var prescribing = false
    @State private var collectingOnAccount = false
    @State private var hospitalStays: [HospSummary] = []

    private var canView: Bool { workspace.can(.clientsView) && (workspace.can(.clientsAssignSelf) || workspace.can(.clientsAssignAnyone)) }
    private var canCreateRecords: Bool { workspace.can(.recordsCreate) && (workspace.can(.recordsAssignSelf) || workspace.can(.recordsAssignAnyone)) }
    private var canBook: Bool { workspace.can(.appointmentsCreate) }
    private var canWeigh: Bool { workspace.can(.petsEdit) || workspace.can(.appointmentsEdit) }
    private var wide: Bool { sizeClass == .regular }

    var body: some View {
        Group {
            if !canView {
                PageScroll { NoAccessState(message: L("Ask the workspace owner to let your role see clients.")) }
            } else if let chart {
                content(chart)
            } else if notFound {
                PageScroll {
                    EmptyState(systemImage: "paw-print", title: L("Pet not found"), message: L("It may have been combined with another record, or it belongs to a client assigned to someone else."), accent: Theme.lime, panel: true)
                }
            } else if let error {
                PageScroll { ErrorState(message: L("The chart could not be loaded.") + " " + error) { await load() } }
            } else {
                PageScroll { LoadingState() }
            }
        }
        .providerPage(chart?.pet.name ?? L("Patient chart"))
        .reloadsOnScope { await load() }
        .sheet(isPresented: $weighing) {
            if let chart { ClientsWeightSheet(chart: chart) { await load() } }
        }
        .sheet(isPresented: $editing) {
            if let pet { ClientsEditPetSheet(clientName: clientName, pet: pet) }
        }
        .sheet(item: $closing) { target in ClientsClosingSheet(target: target) }
        .sheet(item: $restoring) { target in ClientsRestoreSheet(target: target) }
        .navigationDestination(item: $pushed) { push in push.view }
        .navigationDestination(item: $route) { RouteView(route: $0) }
        .navigationDestination(isPresented: $collectingOnAccount) { CashAccountScreen(clientId: clientId) }
        .sheet(item: $mergingPet) { source in
            ClientsMergePetSheet(source: source, ownPets: client?.allPets ?? [], canSearchOthers: canView) { clientId, petId in
                Task { try? await Task.sleep(for: .milliseconds(400)); route = .clientPet(clientId: clientId, petId: petId) }
            }
        }
        .sheet(item: $movingPet) { target in
            ClientsMovePetSheet(target: target) { clientId, petId in
                Task { await load(); try? await Task.sleep(for: .milliseconds(300)); route = .clientPet(clientId: clientId, petId: petId) }
            }
        }
        .sheet(item: $unlinkingPet) { target in
            ClientsUnlinkPetSheet(target: target) { await load() }
        }
        .sheet(isPresented: $prescribing) {
            if let chart {
                StockPrescriptionSheet(
                    pet: StockRxPet(clientId: chart.client.id, petId: chart.pet.id, petName: chart.pet.name, species: chart.pet.species, photoUrl: chart.pet.photoUrl, clientName: chart.client.name),
                    draft: nil
                ) { _ in announceDataChanged() }
            }
        }
    }

    private func load() async {
        guard canView else { return }
        let path = "/provider-clients/\(clientId)/pets/\(petId)"
        let clientPath = "/provider-clients/\(clientId)"
        do {
            async let client: ClientsClient? = ClientsClientPage.fetch(true, clientPath)
            chart = try await API.get("\(path)/chart")
            error = nil
            if workspace.can(.hospitalView) && workspace.offers(.vet, .emergency) {
                hospitalStays = await ClientsHospitalCard.load(petId: petId)
            }
            if let client = await client {
                clientName = client.ownerName
                pet = client.allPets.first { $0.id == petId }
                self.client = client
            }
        } catch is CancellationError {
        } catch {
            if (error as? APIError)?.status == 404 { notFound = true }
            self.error = errorText(error)
        }
    }

    // MARK: Page

    private func content(_ chart: ClientsChart) -> some View {
        let archived = chart.isArchived
        let viewer = chart.viewer
        return PageScroll(refresh: { await load() }) {
            header(chart)
            if archived { closingBanner(chart) }
            if let from = chart.pet.movedFrom {
                // It came from another client: its earlier history is read here, and lives on the earlier record.
                NoticeCard(tone: .warning, title: LF("Came from %@", from.clientName ?? "—"), message: L("Its earlier history shows here to read. It is changed only on the earlier record."), actionTitle: L("Open the earlier record")) {
                    route = .clientPet(clientId: from.clientId, petId: from.petId)
                }
            }
            quickActions(chart)
            // Always on screen, before anything else.
            ClientsAlertStrip(alerts: chart.alerts ?? [], seesRecords: viewer?.seesRecords ?? false)
            if viewer?.seesRecords == true {
                ClientsChartBrief(chart: chart, canWeigh: canWeigh, reload: { await load() }) { tab = .followups }
            } else {
                ClientsChartSummaryView(chart: chart, canWeigh: canWeigh) { await load() }
            }
            if let toSign = chart.counts?.toSign, toSign > 0 {
                NoticeCard(tone: .warning, title: toSign == 1 ? L("1 note is waiting to be signed.") : LF("%d notes are waiting to be signed.", toSign))
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Clinical summary")).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
                ClientsPrescriptionsCard(chart: chart)
                if workspace.can(.hospitalView) && workspace.offers(.vet, .emergency) {
                    ClientsHospitalCard(items: hospitalStays)
                }
            }
            tabs(chart)
        }
    }

    // MARK: Header

    private func header(_ chart: ClientsChart) -> some View {
        ModuleHeader(
            icon: "paw-print",
            title: chart.pet.name,
            subtitle: subtitle(chart).nonEmpty ?? ClientsText.species(chart.pet.species),
            accent: Theme.aqua,
            media: AnyView(PetAvatar(name: chart.pet.name, species: chart.pet.species, photoURL: chart.pet.photoUrl, size: wide ? 56 : 36)),
            titleAccessory: chart.isArchived ? AnyView(Chip(text: chart.died ? L("Deceased") : L("Archived"), tone: .muted)) : nil,
            stats: stats(chart),
            actionsOnRow: true,
            storageKey: "patient-chart"
        ) {
            ownerLine(chart)
            moreMenu(chart)
        }
    }

    /// "Perro · Beagle · Hembra · 3 años · 12.4 kg" and, while the family shares, their latest home weight.
    private func subtitle(_ chart: ClientsChart) -> String {
        let pet = chart.pet
        let home = chart.weights?.home
        return [
            ClientsText.species(pet.species), pet.breed?.nonEmpty, ClientsText.sex(pet.sex), ClientsText.age(pet.birthDate), ClientsText.weight(pet.weightGrams),
            home.map { LF("At home: %@ · %@", ClientsText.weight($0.latestGrams) ?? "—", ClientsText.shortDay($0.latestAt)) },
        ].compactMap { $0 }.joined(separator: " · ")
    }

    /// The owner, with call and WhatsApp, and whether the family is on PawMiaw (web `OwnerLine`); the pet's state off the active lists sits beside the title.
    @ViewBuilder
    private func ownerLine(_ chart: ClientsChart) -> some View {
        NavigationLink(value: ProviderRoute.client(chart.client.id)) {
            Text(chart.client.name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
        }
        .buttonStyle(.plain)
        if let phone = chart.client.phone?.nonEmpty {
            if let tel = ContactLinks.phone(phone) {
                Button { openURL(tel) } label: {
                    HStack(spacing: 4) { Glyph("phone", size: 14); Text(phone).lineLimit(1) }
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LF("Call %@", chart.client.name))
            }
            if let whatsapp = ContactLinks.whatsApp(phone) {
                Button { openURL(whatsapp) } label: {
                    HStack(spacing: 4) { Glyph("message-circle", size: 14); Text("WhatsApp") }
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LF("WhatsApp %@", chart.client.name))
            }
        } else {
            Text(L("No phone")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        }
        // It reads the pet's own link: a pet not matched to the family's stays clinic-only.
        ClientsLinkBadge(linked: chart.pet.linked == true)
    }

    private func moreMenu(_ chart: ClientsChart) -> some View {
        let archived = chart.isArchived
        let movedTo = archived ? chart.pet.movedTo : nil
        let withClient = archived && (chart.pet.clientArchived == true || chart.pet.closing?.reason == "client_archived")
        return Menu {
            Button { route = .client(chart.client.id) } label: { GlyphLabel(L("Open client"), icon: "user-round") }
            if workspace.can(.petsEdit) && pet != nil {
                Button { editing = true } label: { GlyphLabel(chart.pet.linked == true ? L("Edit clinic details") : L("Edit pet"), icon: "pencil") }
            }
            if workspace.can(.petsEdit), let client, let pet {
                Button { mergingPet = ClientsMergePetSource(clientId: client.id, clientName: client.ownerName, petId: pet.id, name: pet.petName, species: pet.petSpecies, breed: pet.petBreed, photoUrl: pet.photoUrl, linked: pet.isLinked, householdPetId: pet.petId, details: ClientsPetDetails.of(pet, createdAt: nil)) } label: {
                    GlyphLabel(L("Combine with another pet"), icon: "git-merge")
                }
            }
            if workspace.can(.clientsEdit), let client, let pet, pet.isLinked {
                Divider()
                Button(role: .destructive) { unlinkingPet = ClientsUnlinkTarget(clientId: client.id, clientName: client.ownerName, petId: pet.id, petName: pet.petName) } label: {
                    GlyphLabel(L("Unlink from the family"), icon: "link-2-off")
                }
            }
            if workspace.can(.petsEdit) && workspace.isOwnerOrAdmin && !archived {
                Button { movingPet = ClientsMoveTarget(clientId: chart.client.id, clientName: chart.client.name, petId: chart.pet.id, name: chart.pet.name, linked: chart.pet.linked == true) } label: {
                    GlyphLabel(L("Move to another client"), icon: "arrow-right-left")
                }
            }
            if workspace.can(.petsEdit) {
                if archived && !withClient && movedTo == nil {
                    Button { restoring = .pet(id: chart.pet.id, name: chart.pet.name, deceased: chart.died) } label: { GlyphLabel(L("Restore"), icon: "rotate-ccw") }
                }
                if !chart.died && movedTo == nil {
                    Divider()
                    if !archived {
                        Button(role: .destructive) { closing = .archivePet(clientId: chart.client.id, petId: chart.pet.id, name: chart.pet.name) } label: { GlyphLabel(L("Archive pet"), icon: "archive") }
                    }
                    Button(role: .destructive) { closing = .petDeath(clientId: chart.client.id, petId: chart.pet.id, name: chart.pet.name) } label: { GlyphLabel(L("Record that it died"), icon: "flower-2") }
                }
            }
        } label: {
            IconCircleButton(systemImage: "ellipsis", label: LF("More for %@", chart.pet.name)) {}
                .allowsHitTesting(false)
        }
        .accessibilityLabel(LF("More for %@", chart.pet.name))
    }

    /// The header's numbers (web `stats`): each opens the tab it is about.
    private func stats(_ chart: ClientsChart) -> [ModuleStat] {
        let archived = chart.isArchived
        let vaccines = chart.summary?.vaccines ?? []
        let overdue = vaccines.filter { $0.status == "overdue" }.count
        let dueSoon = vaccines.filter { $0.status == "due_soon" }.count
        var stats: [ModuleStat] = [
            ModuleStat("last", label: L("Last visit"), value: chart.activity?.lastVisitAt.map { ClientsText.shortDay($0) } ?? L("None yet"),
                       icon: "stethoscope", accent: Theme.aqua, active: tab == .history, action: { tab = .history }),
        ]
        // A pet off the active lists has nothing coming and owes no vaccine.
        if chart.viewer?.seesVisits == true && !archived {
            stats.append(ModuleStat("next", label: L("Next appointment"), value: chart.activity?.nextVisit.map { ClientsText.shortDay($0.startsAt) } ?? L("Nothing booked"),
                                    hint: chart.activity?.nextVisit?.serviceLabel, icon: "calendar-clock", accent: Theme.blue,
                                    active: tab == .appointments, action: { tab = .appointments }))
        }
        if chart.summary != nil && !archived {
            let value = overdue > 0 ? (overdue == 1 ? L("1 overdue") : LF("%d overdue", overdue))
                : dueSoon > 0 ? (dueSoon == 1 ? L("1 due soon") : LF("%d due soon", dueSoon))
                : vaccines.isEmpty ? L("None on record") : L("Up to date")
            stats.append(ModuleStat("vaccines", label: L("Vaccines"), value: value, icon: "syringe", accent: Theme.mango, attention: overdue > 0))
        }
        if let balance = chart.activity?.balance {
            let owes = (balance.client ?? 0) > 0
            stats.append(ModuleStat("balance", label: L("Balance"), value: owes ? Money.format(balance.client, currency: balance.currency) : L("Nothing owed"),
                                    hint: owes ? LF("%@ owes", NameText.firstName(chart.client.name)) : nil, icon: "circle-dollar-sign", accent: Theme.pink,
                                    attention: owes, active: tab == .billing, action: { tab = .billing }))
        }
        return stats
    }

    @ViewBuilder
    private func closingBanner(_ chart: ClientsChart) -> some View {
        let movedTo = chart.pet.movedTo
        let withClient = chart.pet.clientArchived == true || chart.pet.closing?.reason == "client_archived"
        ClientsClosingBanner(
            name: chart.pet.name, stamp: chart.pet.closing, deceasedAt: chart.pet.deceasedAt,
            hint: movedTo.map { LF("Now with %@", $0.clientName ?? "—") } ?? (withClient ? L("It comes back when the client is restored.") : nil),
            onRestore: workspace.can(.petsEdit) && !withClient && movedTo == nil ? { restoring = .pet(id: chart.pet.id, name: chart.pet.name, deceased: chart.died) } : nil
        )
        if let movedTo {
            PMButton(L("Open its record there"), systemImage: "arrow-right", variant: .outline, size: .compact) {
                route = .clientPet(clientId: movedTo.clientId, petId: movedTo.petId)
            }
        } else if withClient {
            PMButton(L("Open the client"), systemImage: "user-round", variant: .outline, size: .compact) { route = .client(chart.client.id) }
        }
    }

    /// Quick actions, by permission: book, write, prescribe, weigh, walk in, collect what is owed.
    @ViewBuilder
    private func quickActions(_ chart: ClientsChart) -> some View {
        let archived = chart.isArchived
        let balance = chart.activity?.balance
        let canCollect = (balance?.client ?? 0) > 0 && (workspace.can(.salesSell) || (workspace.can(.billingRecordPayment) && workspace.moneyLevel >= .charging))
        let canPrescribe = workspace.can(.recordsCreate)
        let clientId = chart.client.id, petId = chart.pet.id
        if (!archived && (canBook || canWeigh || canPrescribe)) || canCreateRecords || canCollect {
            FlowLayout(spacing: 8) {
                if canBook && !archived {
                    PMButton(L("Book"), systemImage: "calendar-plus", size: .compact) { route = .bookVisit(BookingPrefill(clientId: clientId, petId: petId)) }
                }
                if canCreateRecords {
                    PMButton(L("New record"), systemImage: "file-plus-corner", variant: .outline, size: .compact) { route = .newRecord(RecordPrefill(clientId: clientId, petId: petId)) }
                }
                if canPrescribe && !archived {
                    PMButton(L("Prescribe"), systemImage: "pill", variant: .outline, size: .compact) { prescribing = true }
                }
                if canWeigh && !archived {
                    PMButton(L("Weigh"), systemImage: "scale", variant: .outline, size: .compact) { weighing = true }
                }
                if canBook && workspace.can(.appointmentsCheckIn) && !archived {
                    PMButton(L("Start a visit"), systemImage: "zap", variant: .outline, size: .compact) { route = .bookVisit(BookingPrefill(clientId: clientId, petId: petId, walkIn: true)) }
                }
                if canCollect, let balance {
                    // The Store's checkout collects a client's open bills; without the Store, the client's account takes the payment.
                    PMButton(LF("Collect %@", Money.format(balance.client, currency: balance.currency)), systemImage: "circle-dollar-sign", size: .compact) {
                        if workspace.can(.salesSell) { route = .storeCheckout(StorePrefill(clientId: clientId, petId: petId)) } else { collectingOnAccount = true }
                    }
                }
            }
        }
    }

    // MARK: Tabs

    private func tabs(_ chart: ClientsChart) -> some View {
        let viewer = chart.viewer
        let openFollowUps = chart.counts?.openFollowUps ?? 0
        var choices: [Segmented<ClientsChartTab>.Option] = [.init(.history, L("History"))]
        if viewer?.seesVisits == true { choices.append(.init(.appointments, L("Appointments"))) }
        if viewer?.seesFollowUps == true { choices.append(.init(.followups, openFollowUps > 0 ? "\(L("Follow-ups")) · \(openFollowUps > 99 ? "99+" : String(openFollowUps))" : L("Follow-ups"))) }
        if viewer?.seesRecords == true { choices.append(.init(.files, L("Files"))) }
        if viewer?.seesBilling == true { choices.append(.init(.billing, L("Billing"))) }
        choices.append(.init(.profile, L("Details")))
        let active = choices.contains { $0.value == tab } ? tab : .history
        return Card(padding: 12, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                Segmented(options: choices, selection: Binding(get: { active }, set: { tab = $0 }), look: .raised, label: L("Chart sections"))
                    .padding(.vertical, 2)
            }
            switch active {
            case .history: ClientsTimelineView(clientId: chart.client.id, petId: chart.pet.id, chart: chart)
            case .appointments: ClientsChartAppointments(chart: chart, onBook: canBook && !chart.isArchived ? { route = .bookVisit(BookingPrefill(clientId: chart.client.id, petId: chart.pet.id)) } : nil)
            case .followups: ClientsChartFollowUps(chart: chart)
            case .files: ClientsChartFiles(chart: chart)
            case .billing: ClientsChartBilling(chart: chart)
            case .profile: ClientsChartDetails(chart: chart, onEdit: workspace.can(.petsEdit) && pet != nil ? { editing = true } : nil)
            }
        }
    }
}

// MARK: - Shared pieces of the chart

/// A small uppercase heading inside the chart (web `ChartSectionTitle`): 11.2 extrabold, tracked.
struct ClientsChartSectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.brandText(11.2, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.inkSoft)
    }
}

extension View {
    /// A bordered box inside a card (web `rounded-box border border-soft`): 16 corners, a 1 pt grey border, a fill.
    func clientsChartBox<S: ShapeStyle>(_ fill: S, border: Color = Theme.borderSoft, lineWidth: CGFloat = 1) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(border, lineWidth: lineWidth))
    }

    /// The same box on the surface.
    func clientsChartBox() -> some View { clientsChartBox(Theme.surface) }
}

// MARK: - The red strip

/// Allergies, the care card's handling warnings and active problems — always on screen, before anything else (web `AlertStrip`).
struct ClientsAlertStrip: View {
    let alerts: [ClientsChartAlert]
    let seesRecords: Bool

    var body: some View {
        if alerts.isEmpty {
            HStack(spacing: 8) {
                Glyph("circle-check", size: 16).foregroundStyle(Theme.blue)
                Text(seesRecords ? L("No allergies, handling warnings or active problems on record.") : L("No handling warnings. Allergies and problems need access to records."))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .clientsChartBox()
        } else {
            FlowLayout(spacing: 6) {
                ForEach(alerts, id: \.self) { alert in
                    let label = alert.kind == "handling" ? alert.label.replacingOccurrences(of: "_", with: " ").capitalized : alert.label
                    let prefix = alert.kind == "allergy" ? "\(L("Allergy")): " : alert.kind == "problem" ? "\(L("Problem")): " : ""
                    let text = prefix + label + (alert.source == "family" ? " · \(L("Family"))" : "")
                    Group {
                        if alert.kind == "problem" {
                            Chip(text: text, tone: .warn, icon: "stethoscope")
                        } else {
                            StatusChip(text: text, state: .problem)
                        }
                    }
                    .accessibilityHint([alert.detail, alert.source == "family" ? L("Registered by the family") : nil].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clientsChartBox(Theme.wash(Theme.destructive, 9), border: Theme.destructive.opacity(0.35))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L("Alerts"))
        }
    }
}

// MARK: - The clinical summary

/// The chart's own facts (web `ChartSummary`): allergies first and in red, active problems, the medicines
/// being given, each vaccine with its status, the latest labs and the weight; `section` shows one of them
/// (under a tab of the brief).
struct ClientsChartSummaryView: View {
    let chart: ClientsChart
    let canWeigh: Bool
    var section: String? = nil
    let reload: () async -> Void

    init(chart: ClientsChart, canWeigh: Bool, section: String? = nil, reload: @escaping () async -> Void) {
        self.chart = chart
        self.canWeigh = canWeigh
        self.section = section
        self.reload = reload
    }

    private func show(_ key: String) -> Bool { section == nil || section == key }

    var body: some View {
        if let summary = chart.summary {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                if show("overview") {
                    block(L("Allergies"), "triangle-alert", Theme.destructive, empty: L("None recorded."), count: summary.allergies?.count ?? 0) {
                        ForEach(Array((summary.allergies ?? []).enumerated()), id: \.offset) { _, allergy in
                            line(Text(allergy.label ?? "—").fontWeight(.heavy).foregroundColor(Theme.destructive) + Text(allergy.detail.map { " · \($0)" } ?? "").foregroundColor(Theme.inkSoft), family: allergy.source == "family", draft: allergy.draft == true)
                        }
                    }
                }
                if show("problems") {
                    block(L("Active problems"), "stethoscope", Theme.pink, empty: L("No active problems recorded."), count: summary.problems?.count ?? 0) {
                        ForEach(Array((summary.problems ?? []).enumerated()), id: \.offset) { _, problem in
                            let state = problem.detail == "monitoring" ? L("Monitoring") : L("Active")
                            line(Text(problem.label ?? "—").bold() + Text(" · \(state) · \(LF("since %@", ClientsText.shortDay(problem.at)))").foregroundColor(Theme.inkSoft), family: problem.source == "family", draft: problem.draft == true)
                        }
                    }
                }
                if show("medications") {
                    block(L("Current medications"), "pill", Theme.mango, empty: L("No active medication records."), count: summary.medications?.count ?? 0) {
                        ForEach(Array((summary.medications ?? []).enumerated()), id: \.offset) { _, medication in
                            let until = medication.endDay.map { LF("until %@", ClientsText.shortDay($0)) } ?? L("no end date")
                            line(Text(medication.name ?? "—").bold() + Text((medication.dose.map { " · \($0)" } ?? "") + " · \(until)").foregroundColor(Theme.inkSoft), family: medication.source == "family", draft: medication.draft == true)
                        }
                    }
                }
                if show("history") {
                    block(L("Vaccines"), "syringe", Theme.blue, empty: L("No vaccines on record."), count: summary.vaccines?.count ?? 0) {
                        ForEach(summary.vaccines ?? [], id: \.self) { vaccine in
                            HStack(alignment: .center, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(vaccine.name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                                        if vaccine.source == "family" { Chip(text: L("Family"), tone: .info) }
                                    }
                                    Text((vaccine.lastGivenAt.map { LF("Given %@", ClientsText.shortDay($0)) } ?? L("Date not recorded")) + (vaccine.nextDueDay.map { " · \(LF("next %@", ClientsText.shortDay($0)))" } ?? ""))
                                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                                }
                                Spacer(minLength: 6)
                                ClientsVaccineBadge(status: vaccine.status)
                            }
                        }
                    }
                }
                if show("labs") {
                    block(L("Recent labs"), "flask-conical", Theme.aqua, empty: L("No lab results yet."), count: summary.labs?.count ?? 0) {
                        ForEach(summary.labs ?? [], id: \.self) { lab in
                            VStack(alignment: .leading, spacing: 1) {
                                line(Text(lab.name ?? "—").bold() + Text(" · \(ClientsText.shortDay(lab.at))").foregroundColor(Theme.inkSoft), family: lab.source == "family", draft: lab.draft == true)
                                if let result = lab.result?.nonEmpty { Text(result).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                            }
                        }
                    }
                }
                if show("weight") {
                    ClientsWeightCard(chart: chart, canWeigh: canWeigh, reload: reload)
                }
            }
            if section == nil {
                HStack(alignment: .top, spacing: 6) {
                    Glyph("share-2", size: 14).padding(.top, 1)
                    Text(shareLine).font(Theme.text(12))
                }
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 4)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Clinical records are hidden for your role.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clientsChartBox()
                ClientsWeightCard(chart: chart, canWeigh: canWeigh, reload: reload)
            }
        }
    }

    /// Who sees what: the family's history reaches the chart only while they share it.
    private var shareLine: String {
        guard chart.pet.linked == true else { return L("Not linked to a family on PawMiaw: only the clinic’s records.") }
        guard chart.sharedHistoryAccess?.canView == true else { return L("The family hasn’t shared their medical history with you.") }
        if chart.sharedHistoryAccess?.shareScope == "full" { return L("The family shares their whole medical history.") }
        return LF("The family shares what they record since %@.", ClientsText.shortDay(chart.sharedHistoryAccess?.sharedSince))
    }

    /// One block (web `Block`): a 24 disc of its tone, the small title, its lines or a quiet empty line.
    private func block<Rows: View>(_ title: String, _ icon: String, _ tone: Color, empty: String, count: Int, @ViewBuilder rows: () -> Rows) -> some View {
        let list = rows()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Glyph(icon, size: 14)
                    .foregroundStyle(Theme.mix(tone, 75, with: Theme.inkStrong))
                    .frame(width: 24, height: 24)
                    .background(Theme.wash(tone, 18), in: Circle())
                ClientsChartSectionTitle(text: title)
            }
            if count > 0 {
                VStack(alignment: .leading, spacing: 6) { list }
            } else {
                Text(empty).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clientsChartBox()
    }

    private func line(_ text: Text, family: Bool, draft: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            text.font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
            if family { Chip(text: L("Family"), tone: .info) }
            if draft { Chip(text: L("To sign"), tone: .warn) }
        }
    }
}

/// A vaccine's status (web `VaccineStatusBadge`): overdue solid red, due soon mango, current blue, no date grey.
struct ClientsVaccineBadge: View {
    let status: String?
    var body: some View {
        switch status {
        case "overdue": StatusChip(text: ClientsText.vaccineStatus(status), state: .problem)
        case "due_soon": Chip(text: ClientsText.vaccineStatus(status), tone: .warn)
        case "current": Chip(text: ClientsText.vaccineStatus(status), tone: .info)
        default: Chip(text: ClientsText.vaccineStatus(status), tone: .muted)
        }
    }
}

/// The weight: the clinic's is the pet's weight; while the family shares, their latest home weight too (web `WeightCard`).
struct ClientsWeightCard: View {
    let chart: ClientsChart
    let canWeigh: Bool
    let reload: () async -> Void

    @State private var showAll = false
    @State private var taking = false

    var body: some View {
        let weights = chart.weights
        let home = weights?.home
        let entries = ((weights?.trend ?? []).map { (at: $0.at, grams: $0.grams, home: false, id: $0.id, used: true) }
            + (home?.trend ?? []).map { (at: $0.at, grams: $0.grams, home: true, id: $0.id, used: $0.used ?? false) })
            .sorted { $0.at > $1.at }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Glyph("scale", size: 14)
                    .foregroundStyle(Theme.inkStrong)
                    .frame(width: 24, height: 24)
                    .background(Theme.wash(Theme.lime, 30), in: Circle())
                ClientsChartSectionTitle(text: L("Weight"))
            }
            HStack(alignment: .bottom) {
                if let grams = weights?.latestGrams {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ClientsText.weight(grams) ?? "—").font(.brandHeading(24, relativeTo: .title2)).foregroundStyle(Theme.inkStrong)
                        Text(weights?.latestAt.map { LF("Weighed on %@", ClientsText.shortDay($0)) } ?? L("From the profile")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                } else {
                    Text(L("Not weighed yet.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 8)
                ClientsSparkline(points: (weights?.trend ?? []).map { ($0.at, $0.grams) }, homePoints: (home?.trend ?? []).map { ($0.at, $0.grams) })
                    .frame(width: 160, height: 40)
            }
            if let home, let latest = home.latestGrams {
                RowDivider()
                FlowLayout(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().strokeBorder(Theme.apricot, lineWidth: 1.75).background(Circle().fill(Theme.surface)).frame(width: 10, height: 10)
                        Text(LF("At home: %@ · %@", ClientsText.weight(latest) ?? "—", ClientsText.shortDay(home.latestAt))).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    }
                    .frame(minHeight: 40)
                    if canWeigh, home.latestUsed != true, let id = home.latestId {
                        PMButton(L("Use this weight"), variant: .outline, size: .compact, isWorking: taking) { take(id, grams: latest) }
                    }
                }
                if weights?.differs == true {
                    HStack(alignment: .top, spacing: 6) {
                        Glyph("triangle-alert", size: 14).foregroundStyle(Theme.mix(Theme.mango, 80, with: Theme.inkStrong)).padding(.top, 1)
                        Text(L("Different from what the family logs")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.wash(Theme.mango, 14), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                }
            }
            if entries.count > 1 {
                Button { withAnimation(.easeOut(duration: 0.2)) { showAll.toggle() } } label: {
                    HStack(spacing: 4) {
                        Glyph("chevron-down", size: 14).rotationEffect(.degrees(showAll ? 180 : 0))
                        Text(showAll ? L("Hide weights") : LF("All weights (%d)", entries.count))
                    }
                    .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue)
                }
                .buttonStyle(.plain)
                if showAll {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                            if index > 0 { RowDivider() }
                            HStack(spacing: 8) {
                                Text(ClientsText.shortDay(entry.at)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                                if entry.home { Chip(text: L("At home"), tone: .warn) }
                                Spacer()
                                if entry.home && canWeigh && !entry.used, let id = entry.id {
                                    Button(L("Use this weight")) { take(id, grams: entry.grams) }
                                        .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue).buttonStyle(.plain).disabled(taking)
                                }
                                Text(ClientsText.weight(entry.grams) ?? "—").font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clientsChartBox()
    }

    /// "Usar este peso": a weight the family logged at home becomes the clinic's.
    private func take(_ id: String, grams: Double) {
        taking = true
        Task {
            defer { taking = false }
            do {
                let _: EmptyResponse = try await API.post("/provider-clients/\(chart.client.id)/pets/\(chart.pet.id)/weights/from-family", body: ["familyWeightId": id])
                Toast.show(LF("%@ weighs %@.", chart.pet.name, ClientsText.weight(grams) ?? ""))
                announceDataChanged()
                await reload()
            } catch {
                let api = error as? APIError
                if api?.code == "family_weight_not_shared" { Toast.error(L("The family no longer shares this weight. The chart has been updated.")); await reload() }
                else if api?.status == 404 { Toast.error(L("This weight is no longer in the chart. The chart has been updated.")); await reload() }
                else if api?.status == 403 { Toast.error(L("You can’t log this pet’s weight with your access.")) }
                else { Toast.error(error, fallback: L("The weight could not be saved.")) }
            }
        }
    }
}

/// A small line of the clinic's weight over time; the family's are hollow apricot dots of their own (web `WeightSparkline`).
struct ClientsSparkline: View {
    let points: [(String, Double)]
    let homePoints: [(String, Double)]

    var body: some View {
        GeometryReader { proxy in
            let all = (points + homePoints).compactMap { point in DateText.parse(point.0).map { ($0.timeIntervalSince1970, point.1) } }
            if all.count >= 2 {
                let times = all.map(\.0), grams = all.map(\.1)
                let minT = times.min() ?? 0, maxT = times.max() ?? 1, minG = grams.min() ?? 0, maxG = grams.max() ?? 1
                let pad: CGFloat = 4
                let x = { (t: Double) -> CGFloat in maxT == minT ? proxy.size.width / 2 : pad + CGFloat((t - minT) / (maxT - minT)) * (proxy.size.width - pad * 2) }
                let y = { (g: Double) -> CGFloat in maxG == minG ? proxy.size.height / 2 : proxy.size.height - pad - CGFloat((g - minG) / (maxG - minG)) * (proxy.size.height - pad * 2) }
                let clinic = points.compactMap { point in DateText.parse(point.0).map { CGPoint(x: x($0.timeIntervalSince1970), y: y(point.1)) } }.sorted { $0.x < $1.x }
                let family = homePoints.compactMap { point in DateText.parse(point.0).map { CGPoint(x: x($0.timeIntervalSince1970), y: y(point.1)) } }
                if clinic.count > 1 {
                    Path { path in
                        guard let first = clinic.first else { return }
                        path.move(to: first)
                        for point in clinic.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(Theme.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                ForEach(Array(family.enumerated()), id: \.offset) { _, point in
                    Circle().stroke(Theme.apricot, lineWidth: 1.75).background(Circle().fill(Theme.surface)).frame(width: 5.5, height: 5.5).position(point)
                }
                if let last = clinic.last { Circle().fill(Theme.blue).frame(width: 6, height: 6).position(last) }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(homePoints.isEmpty ? L("Weight trend") : L("Weight trend, with the weights the family logged at home"))
    }
}
