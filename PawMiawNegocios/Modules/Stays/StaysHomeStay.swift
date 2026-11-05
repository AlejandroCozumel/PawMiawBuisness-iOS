//
//  StaysHomeStay.swift
//  PawMiawNegocios
//
//  Home stays — pet sitting at the client's home (web home-stay-sheet.tsx,
//  home-stay-action-sheets.tsx, home-stay-booking-sheet.tsx,
//  home-stay-plan-fields.tsx): one home stay with its status, sitter, money,
//  where it happens, the keys, the visits planned day by day, the pets and
//  their care, the house; confirming (with its deposit), the quote,
//  cancelling and finishing it into a bill. Visits are run from Domicilio.
//  Also the plan form a new home stay and a family's homestay request share.
//

import SwiftUI

private enum StaysHomeSheet: Identifiable {
    case confirm, finish, report, plan, cancel, reassign, edit, keys, addVisit
    case visit(String)
    var id: String {
        switch self {
        case .visit(let id): "visit-\(id)"
        default: "\(self)"
        }
    }
}

struct StaysHomeStayView: View {
    let stay: StaysStay
    let home: StaysHomeDetail
    var billTotal: Int? = nil
    let reload: () async -> Void

    @EnvironmentObject private var workspace: Workspace
    @State private var sheet: StaysHomeSheet?
    @State private var pushed: ProviderRoute?
    @State private var showPast = false
    @State private var quoting = false
    @State private var showAllKeys = false
    /// Counts presses of "Record an incident" in the action row; the incidents card opens its sheet.
    @State private var incidentRequest = 0

    private var canManage: Bool { workspace.can(.staysManage) }
    private var canCare: Bool { workspace.can(.staysCare) }
    private var started: Bool { stay.status == "checked_in" || stay.status == "checked_out" }
    private var today: String { home.today?.dayKey ?? StaysDay.today() }
    private var days: [(day: String, visits: [StaysHomeVisit])] {
        let grouped = Dictionary(grouping: home.visits ?? [], by: \.dayKey)
        return grouped.keys.sorted().map { key in (key, (grouped[key] ?? []).sorted { $0.startsAt < $1.startsAt }) }
    }

    var body: some View {
        PageScroll(refresh: { await reload() }) {
            header
            moneyChips
            todayStrip
            SectionCard(L("Where")) { StaysHomeAccessCard(stay: stay, home: home).padding(16) }
            keysSection
            visitsSection
            petsSection
            houseSection
            // The vet authorization and anything that happened (docs/consents-incidents.md).
            SectionCard(L("Consents")) {
                ConsentsCard(context: StaysActs.consentContext(stay, businessName: workspace.current?.name), bare: true).padding(16)
            }
            SectionCard(L("Incidents")) {
                IncidentsCard(act: ConsentAct(stayId: stay.id), pets: StaysActs.pets(of: stay), familyName: stay.clientName,
                              recordable: started, bare: true, recordRequest: incidentRequest, showsRecordButton: false)
                    .padding(16)
            }
            familySection
            notesSection
            reportCards
            if let reason = stay.cancellationReason?.nonEmpty { StaysNoteBlock(label: L("Why it closed"), text: reason) }
        }
        .navigationDestination(item: $pushed) { RouteView(route: $0) }
        .sheet(item: $sheet) { which in
            switch which {
            case .confirm: StaysHomeConfirmSheet(stay: stay, home: home)
            case .finish: StaysHomeFinishSheet(stay: stay, home: home)
            case .report:
                StaysReportCardSheet(stayId: stay.id, pets: stay.petList, familyOnApp: stay.familyOnApp,
                                     visitId: home.visits?.first { $0.status == "in_progress" }?.id) { Task { await reload() } }
            case .plan: StaysCarePlanSheet(stay: stay) { Task { await reload() } }
            case .reassign: StaysHomeReassignSheet(stay: stay, home: home)
            case .edit: StaysHomeEditSheet(stay: stay, home: home)
            case .keys: StaysHomeKeysSheet(stay: stay, home: home)
            case .addVisit: StaysHomeAddVisitSheet(stay: stay, home: home)
            case .visit(let id): StaysHomeVisitSheet(stay: stay, home: home, visitId: id)
            case .cancel:
                ConfirmSheet(title: stay.status == "requested" && home.quoteSentAt != nil ? L("Withdraw the quote?") : L("Cancel this home stay?"),
                             message: L("Its visits are cancelled and the family is told. This cannot be undone."),
                             confirmTitle: stay.status == "requested" && home.quoteSentAt != nil ? L("Withdraw the quote") : L("Cancel home stay"),
                             destructive: true, askReason: true, reasonLabel: L("Reason"), accent: .coral, icon: "circle-x") { reason in
                    do {
                        try await API.send("POST", "/provider-homestays/\(stay.id)/cancel", body: ["reason": reason])
                    } catch {
                        throw APIError(status: (error as? APIError)?.status ?? 0, message: StaysWords.homeError(error, fallback: "Could not cancel this home stay."), code: nil, fields: [:])
                    }
                    Toast.show(stay.familyOnApp ? L("Home stay cancelled. The family has been told.") : L("Home stay cancelled. Let the family know."))
                    announceDataChanged()
                }
            }
        }
    }

    // MARK: Header

    /// Something to do from the header (the web's "what happens next" row).
    private var hasActions: Bool {
        (stay.isOpen && canManage) || (stay.status == "checked_in" && canCare) || (started && canCare)
            || (stay.invoiceId != nil && workspace.moneyLevel >= .charging) || (stay.isOpen && workspace.offersHomeVisits)
    }

    @ViewBuilder
    private var header: some View {
        let pet = stay.petList.first
        let subtitle = "\(stay.clientName ?? "") · \(StaysDay.short(stay.checkInDay)) – \(StaysDay.short(stay.checkOutDay))"
        let media = pet?.photoUrl == nil ? nil : AnyView(PetAvatar(name: pet?.petName, species: pet?.petSpecies, photoURL: pet?.photoUrl, size: 56))
        if hasActions {
            ModuleHeader(icon: "house", title: stay.petNames, subtitle: subtitle, accent: Theme.aqua, media: media,
                         stats: headerStats, actionsOnRow: true, storageKey: "home-stay") { actions }
        } else {
            ModuleHeader(icon: "house", title: stay.petNames, subtitle: subtitle, accent: Theme.aqua, media: media, stats: headerStats, storageKey: "home-stay")
        }
    }

    private var headerStats: [ModuleStat] {
        let units = home.units ?? 0
        let unitText = home.priceUnit == "night" ? LP(units, "%d night", "%d nights") : LP(units, "%d visit", "%d visits")
        return [
            ModuleStat("status", label: L("Status"), value: StaysWords.homeStatus(stay, quoteSent: home.quoteSentAt != nil),
                       hint: home.quoteAcceptedAt != nil ? L("The family accepted the quote")
                           : home.quoteSentAt != nil && stay.status == "requested" ? L("Waiting for the family")
                           : home.mode == "overnight" ? L("Overnight") : L("Drop-in visits"),
                       icon: "circle-dot", accent: ProviderState.stay(stay.status).color),
            ModuleStat("sitter", label: L("Sitter"), value: home.sitter?.name ?? L("Nobody yet"),
                       hint: stay.isOpen && canManage ? (home.sitter != nil ? L("Give to another sitter") : L("Choose a sitter")) : nil,
                       icon: "user-round-cog", accent: Theme.aqua, attention: home.sitter == nil && stay.isOpen,
                       action: stay.isOpen && canManage ? { sheet = .reassign } : nil),
            ModuleStat("total", label: billTotal != nil ? L("Bill") : L("Estimated total"),
                       value: Money.format(billTotal ?? home.estimatedTotalCents, currency: stay.stayCurrency),
                       hint: (home.rateCents ?? 0) > 0 ? "\(unitText) × \(Money.format(home.rateCents, currency: stay.stayCurrency))" : "\(unitText) · \(L("No rate set"))",
                       icon: billTotal != nil ? "receipt" : "wallet", accent: Theme.lime),
        ]
    }

    /// Money beyond the estimate.
    @ViewBuilder
    private var moneyChips: some View {
        if (home.depositCents ?? 0) > 0 || (home.vetAuthorizationCents ?? 0) > 0 || home.catalogItem != nil {
            FlowLayout(spacing: 8) {
                if let item = home.catalogItem?.name { Chip(text: item, tone: .info) }
                if let deposit = home.depositCents, deposit > 0 {
                    Chip(text: home.depositOwed > 0
                         ? LF("Deposit %@ · %@ paid", Money.format(deposit, currency: stay.stayCurrency), Money.format(home.depositPaidCents, currency: stay.stayCurrency))
                         : LF("Deposit %@ paid", Money.format(deposit, currency: stay.stayCurrency)),
                         tone: home.depositOwed > 0 ? .warn : .good, icon: "wallet")
                }
                if let vet = home.vetAuthorizationCents, vet > 0 {
                    Chip(text: LF("Vet authorized up to %@", Money.format(vet, currency: stay.stayCurrency)), tone: .online, icon: "stethoscope")
                }
            }
        }
    }

    // MARK: What happens next

    @ViewBuilder
    private var actions: some View {
        if stay.status == "requested" && canManage {
            PMButton(L("Confirm"), systemImage: "calendar-check") { sheet = .confirm }
            PMButton(home.quoteSentAt != nil ? L("Send the quote again") : L("Send as a quote"), systemImage: "send", variant: .outline, isWorking: quoting) { sendQuote() }
        }
        if stay.status == "checked_in" && canCare {
            PMButton(L("Report card"), systemImage: "message-square-heart") { sheet = .report }
        }
        if stay.status == "checked_in" && canManage {
            PMButton(L("Finish"), systemImage: "log-out") { sheet = .finish }
        }
        if stay.isOpen && canManage {
            PMButton(L("Change dates or plan"), systemImage: "calendar-plus", variant: .outline) { sheet = .edit }
            PMButton(L("Add a visit"), systemImage: "calendar-plus", variant: .outline) { sheet = .addVisit }
        }
        if started && canCare {
            PMButton(L("Record an incident"), systemImage: "shield-alert", variant: .outline) { incidentRequest += 1 }
        }
        if (stay.status == "requested" || stay.status == "confirmed") && canManage {
            PMButton(stay.status == "requested" && home.quoteSentAt != nil ? L("Withdraw the quote") : L("Cancel home stay"), systemImage: "circle-x", variant: .outline) { sheet = .cancel }
        }
        if let invoiceId = stay.invoiceId, workspace.moneyLevel >= .charging {
            PMButton(L("Open the bill"), systemImage: "receipt", variant: .outline) { pushed = .invoice(invoiceId) }
        }
        if stay.isOpen && workspace.offersHomeVisits {
            PMButton(L("Run the visits in Domicilio"), systemImage: "house", variant: .outline) { pushed = .section(.homeVisits) }
        }
    }

    private func sendQuote() {
        quoting = true
        Task {
            defer { quoting = false }
            struct Quoted: Decodable { let notified: Int? }
            do {
                let result: Quoted = try await API.post("/provider-homestays/\(stay.id)/quote", body: [:])
                Toast.show((result.notified ?? 0) > 0 ? L("Quote sent. The family answers it in the app.") : L("Quote saved. The family isn’t on PawMiaw, so share it with them yourself."))
                announceDataChanged()
            } catch {
                Toast.error(StaysWords.homeError(error, fallback: "Could not send the quote."))
            }
        }
    }

    /// Today's visits at a glance: done, under way, missed.
    @ViewBuilder
    private var todayStrip: some View {
        if let day = home.today, (day.total ?? 0) > 0, stay.status == "checked_in" || stay.status == "confirmed" {
            FlowLayout(spacing: 12) {
                Text(L("Today")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                ProgressBar(value: Double(day.done ?? 0) / Double(max(1, day.total ?? 1)), height: 10, width: 128, track: Theme.surface)
                Text(LF("%d of %d visits done", day.done ?? 0, day.total ?? 0)).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                if (day.inProgress ?? 0) > 0 { Chip(text: L("Someone is there now"), tone: .good) }
                if (day.missed ?? 0) > 0 { Chip(text: LP(day.missed ?? 0, "%d visit missed", "%d visits missed"), tone: .danger) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wash(Theme.blue, 10), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        }
    }

    // MARK: The keys

    /// Who has the family's keys now, and their history.
    private var keysSection: some View {
        let out = home.keys?.state == "with_sitter" || home.keys?.state == "lockbox"
        let events = home.keys?.events ?? []
        return SectionCard(L("The keys")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    IconBadge(icon: "key-round", accent: out ? Theme.mango : Theme.surfaceMuted, size: 40, iconSize: 20, ink: .strong, washPercent: out ? 30 : 100)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(StaysWords.keysState(home.keys)).font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                        let line = [home.keys?.label, home.keys?.since.map { DateText.dayTime(DateText.parse($0), zone: home.zone) }].compactMap { $0 }.joined(separator: " · ")
                        Text(line.isEmpty ? L("Record them when the family hands them over.") : line).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
                if canCare && (stay.isOpen || out) {
                    PMButton(out ? L("Update") : L("Record keys"), systemImage: "key-round", variant: .outline, size: .compact) { sheet = .keys }
                }
                if !events.isEmpty {
                    RowDivider()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(showAllKeys ? events : Array(events.prefix(3))) { event in
                            VStack(alignment: .leading, spacing: 1) {
                                (Text(StaysWords.keyAction(event)).bold()
                                 + Text(" · " + [event.occurredAt.map { DateText.dayTime(DateText.parse($0), zone: home.zone) }, event.byName].compactMap { $0 }.joined(separator: " · ")).foregroundColor(Theme.inkSoft))
                                    .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                                if let note = event.note?.nonEmpty { Text("“\(note)”").font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                            }
                        }
                        if events.count > 3 {
                            Button(showAllKeys ? L("Show less") : LF("Show all (%d)", events.count)) { showAllKeys.toggle() }
                                .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue).buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: Visits

    private var visitsSection: some View {
        let past = days.filter { $0.day < today }
        let shown = showPast ? days : days.filter { $0.day >= today }
        return SectionCard(home.mode == "overnight" ? L("Nights and visits") : L("Visits"),
                           subtitle: (home.visits ?? []).isEmpty ? L("No visits planned.") : nil) {
            if !past.isEmpty || !shown.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    if !past.isEmpty {
                        Button(showPast ? L("Hide past days") : LP(past.count, "Show %d past day", "Show %d past days")) { showPast.toggle() }
                            .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue).buttonStyle(.plain)
                    }
                    ForEach(shown, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(((group.day == today ? L("Today") + " · " : "") + StaysDay.format(group.day, "EEEEdMMM")).uppercased())
                                .font(.brandText(12, weight: .bold)).tracking(12 * 0.12)
                                .foregroundStyle(group.day == today ? Theme.blue : Theme.inkSoft)
                            ForEach(group.visits) { visit in visitRow(visit) }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func visitRow(_ visit: StaysHomeVisit) -> some View {
        let status = StaysWords.homeVisitStatus(visit.status)
        return Button { sheet = .visit(visit.id) } label: {
            HStack(spacing: 12) {
                IconBadge(icon: visit.kind == "overnight" ? "moon-star" : visit.kind == "meet_greet" ? "key-round" : "house",
                          accent: Theme.aqua, size: 36, iconSize: 16, ink: .strong, washPercent: 22)
                VStack(alignment: .leading, spacing: 3) {
                    (Text(visitTime(visit)).bold() + Text(" · " + StaysWords.homeVisitKind(visit.kind)).fontWeight(.semibold).foregroundColor(Theme.inkSoft))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    FlowLayout(spacing: 6) {
                        Text(visit.sitter?.name ?? L("No sitter yet")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        StaysHomeVisitChips(visit: visit, status: status)
                    }
                }
                Spacer(minLength: 0)
                Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            .opacity(visit.status == "cancelled" ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func visitTime(_ visit: StaysHomeVisit) -> String {
        let start = StaysDay.clockAt(visit.startsAt, zone: home.zone)
        let end = StaysDay.clockAt(visit.endsAt, zone: home.zone)
        if visit.kind == "overnight", let a = DateText.parse(visit.startsAt), let b = DateText.parse(visit.endsAt),
           DateText.dayKey(a, zone: home.zone) != DateText.dayKey(b, zone: home.zone) {
            return LF("%@ – %@ next morning", start, end)
        }
        return "\(start) – \(end)"
    }

    // MARK: Pets and the house

    private var petsSection: some View {
        SectionCard(stay.petList.count > 1 ? L("Pets") : L("Pet")) {
            ForEach(Array(stay.petList.enumerated()), id: \.element.id) { index, pet in
                if index > 0 { RowDivider() }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        PetAvatar(name: pet.petName, species: pet.petSpecies, photoURL: pet.photoUrl, size: 48)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pet.petName).font(.brandHeading(20)).foregroundStyle(Theme.inkStrong)
                            Text(pet.petBreed ?? StaysWords.petSpecies(pet.petSpecies)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer(minLength: 0)
                        if let petId = pet.providerClientPetId {
                            IconCircleButton(systemImage: "file-text", label: L("Open the chart"), tint: Theme.blue) { pushed = .patientChart(petId: petId) }
                        }
                    }
                    StaysAllergies(allergies: pet.allergies ?? [])
                    if (pet.carePlan?.items ?? []).isEmpty {
                        Text(stay.isOpen && canManage ? L("No care plan yet: write what the sitter does at each visit.") : L("No care plan yet. When the family shares their routines, they show up here."))
                            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    } else {
                        StaysCarePlanList(items: pet.carePlan?.items ?? [])
                    }
                    if let notes = pet.carePlan?.notes?.nonEmpty {
                        Text(notes).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                    }
                }
                .padding(16)
            }
            if stay.isOpen && canManage {
                RowDivider()
                PMButton(L("Edit the care plan"), systemImage: "clipboard-list", variant: .outline, size: .compact) { sheet = .plan }
                    .padding(16)
            }
        }
    }

    @ViewBuilder
    private var houseSection: some View {
        let tasks = home.houseTasks ?? []
        if home.houseRules?.nonEmpty != nil || !tasks.isEmpty {
            SectionCard(L("The house")) {
                VStack(alignment: .leading, spacing: 12) {
                    if let rules = home.houseRules?.nonEmpty { StaysNoteBlock(label: L("House rules"), text: rules, tint: Theme.mango) }
                    if !tasks.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(Array(tasks.enumerated()), id: \.offset) { _, task in
                                Chip(text: (task.time.map { StaysDay.clock($0) + " " } ?? "") + (task.label ?? ""), tone: .muted)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private var familySection: some View {
        Card(spacing: 0) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Family")).font(.brandHeading(16.8)).foregroundStyle(Theme.inkStrong)
                    if let clientId = stay.providerClientId {
                        Button { pushed = .client(clientId) } label: {
                            HStack(spacing: 4) {
                                Text(stay.clientName ?? "").font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                                Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(stay.clientName ?? "").font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    }
                    if let phone = stay.clientPhone?.nonEmpty { PhoneLink(phone: phone) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Times")).font(.brandHeading(16.8)).foregroundStyle(Theme.inkStrong)
                    Text("\(L("They leave")) \(StaysDay.short(stay.checkInDay)) · \(StaysDay.clock(stay.checkInTime))").font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    Text("\(L("They come back")) \(StaysDay.short(stay.checkOutDay)) · \(StaysDay.clock(stay.checkOutTime))").font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    if home.mode == "overnight" {
                        Text(LF("Nights %@ – %@", StaysDay.clock(home.plan?.overnightStart), StaysDay.clock(home.plan?.overnightEnd))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                    if let times = home.plan?.times, !times.isEmpty {
                        Text(LF("Visits at %@ · %@", times.map { StaysDay.clock($0) }.joined(separator: ", "), StaysHomePlanForm.minutesText(home.plan?.durationMinutes ?? 45)))
                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if stay.ownerInstructions?.nonEmpty != nil || stay.internalNotes?.nonEmpty != nil {
            SectionCard(L("Notes")) {
                VStack(alignment: .leading, spacing: 12) {
                    if let text = stay.ownerInstructions?.nonEmpty { StaysNoteBlock(label: L("From the family"), text: text) }
                    if let text = stay.internalNotes?.nonEmpty { StaysNoteBlock(label: L("For the team"), text: text) }
                }
                .padding(16)
            }
        }
    }

    private var reportCards: some View {
        let cards = (stay.updates ?? []).filter { $0.kind != "incident" }
        return SectionCard(L("Report cards"),
                           subtitle: cards.isEmpty ? L("Nothing yet. Report cards written at a visit show up here and in the family’s app.") : nil) {
            if !cards.isEmpty {
                VStack(spacing: 12) {
                    ForEach(cards) { StaysReportCardView(update: $0, pets: stay.petList, sentToFamily: true, zone: home.zone) }
                }
                .padding(16)
            }
        }
    }
}

/// A home visit's chips (web home-stay-bits `VisitChips`): its status, late,
/// double booked, no access.
struct StaysHomeVisitChips: View {
    let visit: StaysHomeVisit
    let status: (String, ProviderState)

    var body: some View {
        StatusChip(text: status.0, state: status.1)
        if visit.late == true && visit.status == "planned" { Chip(text: L("Late"), tone: .warn, icon: "clock-3") }
        if visit.doubleBooked == true && visit.status != "cancelled" { Chip(text: L("Double booked"), tone: .danger, icon: "split") }
        if visit.noAccessAt != nil { Chip(text: L("No access"), tone: .danger, icon: "door-closed") }
    }
}

// MARK: - Confirm

private struct StaysHomeConfirmSheet: View {
    let stay: StaysStay
    let home: StaysHomeDetail

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var waive = false
    @State private var refusedForDeposit = false
    @State private var working = false
    @State private var takingDeposit = false

    private var owedShown: Bool { home.depositOwed > 0 || refusedForDeposit }

    var body: some View {
        ProviderModal(title: L("Confirm the home stay"), subtitle: "\(stay.petNames) · \(StaysDay.short(stay.checkInDay)) – \(StaysDay.short(stay.checkOutDay))",
                      systemImage: "calendar-check", accent: .aqua,
                      primaryTitle: waive ? L("Confirm without the deposit") : L("Confirm"), isWorking: working,
                      primaryIcon: "calendar-check", primaryDisabled: owedShown && !waive, onPrimary: confirm) {
            Text(home.quoteAcceptedAt != nil ? L("The family accepted the quote. Confirming books the visits and tells them.")
                 : home.quoteSentAt != nil ? L("The family hasn’t answered the quote yet. You can confirm it for them.")
                 : L("Confirming books the visits and tells the family."))
                .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
            if let deposit = home.depositCents, deposit > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L("Deposit asked")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                        Spacer()
                        Text(Money.format(deposit, currency: stay.stayCurrency)).font(.brandHeading(18)).foregroundStyle(Theme.inkStrong)
                    }
                    HStack {
                        Text(L("Paid")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        Spacer()
                        Text(Money.format(home.depositPaidCents, currency: stay.stayCurrency)).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    }
                    if owedShown {
                        NoticeCard(tone: .warning, title: LF("The deposit isn’t in yet (%@ to go). Take it first, or confirm without it.", Money.format(home.depositOwed, currency: stay.stayCurrency)))
                    }
                    if owedShown && workspace.can(.billingRecordPayment), stay.providerClientId != nil {
                        // Web: a blue bold link with a plus.
                        PMButton(L("Take the deposit"), systemImage: "plus", variant: .link, size: .small) { takingDeposit = true }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            }
            if owedShown {
                if workspace.isOwnerOrAdmin {
                    ToggleRow(title: L("Confirm without the deposit"), subtitle: L("Owners and admins only. It is written down."), isOn: $waive)
                } else {
                    Text(L("Only owners and admins can confirm without the deposit.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $takingDeposit) {
            if let clientId = stay.providerClientId {
                DepositSheet(clientId: clientId, clientName: stay.clientName ?? "", stayId: stay.id, owed: home.depositOwed,
                             currency: stay.stayCurrency, label: L("Home stay deposit"),
                             explanation: L("It stays as credit on their account and is used when they pay the bill.")) {
                    refusedForDeposit = false
                }
            }
        }
    }

    private func confirm() {
        working = true
        Task {
            defer { working = false }
            do {
                try await API.send("POST", "/provider-homestays/\(stay.id)/confirm", body: waive ? ["waiveDeposit": true] : [:])
                Toast.show(stay.familyOnApp
                    ? (waive ? L("Confirmed without the deposit. The family has been told.") : L("Home stay confirmed. The family has been told."))
                    : (waive ? L("Confirmed without the deposit.") : L("Home stay confirmed.")))
                announceDataChanged()
                dismiss()
            } catch let api as APIError where api.code == "deposit_required" {
                refusedForDeposit = true
            } catch {
                Toast.error(StaysWords.homeError(error, fallback: "Could not confirm this home stay."))
            }
        }
    }
}

// MARK: - Finish

private struct StaysHomeFinishSheet: View {
    let stay: StaysStay
    let home: StaysHomeDetail

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var checkOutDay = ""
    @State private var extras: [StaysExtraLine] = []
    @State private var createInvoice = true
    @State private var keepDraft = false
    @State private var noBillReason = ""
    @State private var keysChoice: String?
    @State private var working = false

    private var keysOut: Bool { home.keys?.state == "with_sitter" || home.keys?.state == "lockbox" }
    private var noRate: Bool { (home.rateCents ?? 0) <= 0 }
    /// What the bill charges, as the server does: the nights up to the last day, or the visits made.
    private var charged: Int {
        home.priceUnit == "night"
            ? max(1, StaysDay.between(stay.checkInDay, checkOutDay.isEmpty ? stay.checkOutDay : checkOutDay))
            : (home.visits ?? []).filter { $0.kind != "meet_greet" && ($0.status == "done" || $0.status == "in_progress") }.count
    }
    private var extrasCents: Int { extras.reduce(0) { $0 + ($1.cents ?? 0) } }

    var body: some View {
        ProviderModal(title: L("Finish the home stay"), subtitle: stay.petNames, systemImage: "log-out", accent: .aqua,
                      isDirty: !extras.isEmpty || !noBillReason.isEmpty, form: form, primaryTitle: L("Finish"), isWorking: working, primaryIcon: "log-out",
                      footerSummary: AnyView(totalSummary), onPrimary: finish) {
            DayField(label: L("Last day"), day: $checkOutDay, min: stay.checkInDay)
            if noRate {
                // No rate bills the nights or visits at $0: the server keeps that bill a draft until it has a price.
                HStack(alignment: .top, spacing: 6) {
                    Glyph("triangle-alert", size: 16).padding(.top, 1)
                    Text(createInvoice ? L("No rate: the bill stays a draft until you put a price on it.") : L("No rate: nothing to charge for the nights or visits."))
                }
                .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.goldText)
            } else {
                Text(home.priceUnit == "night"
                     ? LF("Billed per night, %@ each.", Money.format(home.rateCents, currency: stay.stayCurrency))
                     : LF("Billed per visit made, %@ each. Missed and cancelled visits aren’t charged.", Money.format(home.rateCents, currency: stay.stayCurrency)))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            StaysExtrasSection(extras: $extras, hint: L("An extra pet, a bath, keys copied — anything added during the stay."), prompt: L("What"), removeIcon: "x", addAsLink: true)
            if keysOut {
                ModalSection(title: L("The keys"), subtitle: StaysWords.keysState(home.keys)) {
                    FormField(label: L("The keys"), key: "keys", form: form) {
                        ChoiceCards(options: [(value: "returned", title: L("Returned to the family"), subtitle: Optional(L("Recorded now"))),
                                              (value: "later", title: L("They’ll be returned later"), subtitle: Optional(L("Record it on the stay when they are")))],
                                    selection: Binding(get: { keysChoice ?? "" }, set: { keysChoice = $0; form.clear("keys") }))
                    }
                }
            }
            StaysBillChoice(createInvoice: $createInvoice, canInvoice: workspace.can(.billingCreateInvoice), keepDraft: $keepDraft, noBillReason: $noBillReason, unpriced: noRate, form: form)
        }
        .onAppear {
            guard checkOutDay.isEmpty else { return }
            let today = home.today?.dayKey ?? StaysDay.today()
            checkOutDay = today < stay.checkOutDay && today >= stay.checkInDay ? today : stay.checkOutDay
            createInvoice = workspace.can(.billingCreateInvoice)
        }
    }

    /// The web footer's line: the total, the nights or visits charged, and where the bill goes.
    private var totalSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Money.format(charged * (home.rateCents ?? 0) + extrasCents, currency: stay.stayCurrency)).font(.brandHeading(24)).foregroundStyle(Theme.inkStrong)
            Text((home.priceUnit == "night" ? LP(charged, "%d night", "%d nights") : LP(charged, "%d visit made", "%d visits made"))
                 + (extrasCents > 0 ? " + " + L("extras") : "") + " · " + StaysBillChoice.outcome(createInvoice: createInvoice, keepDraft: keepDraft, unpriced: noRate))
                .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func finish() {
        guard form.check([
            ("keys", keysOut && keysChoice == nil ? L("The keys are still out. Say whether they were returned or will be later.") : nil),
            ("noBillReason", !createInvoice && noBillReason.nonEmpty == nil ? L("Write why it leaves without a bill.") : nil),
        ]) else { return }
        working = true
        Task {
            defer { working = false }
            do {
                if keysOut && keysChoice == "returned" {
                    try await API.send("POST", "/provider-homestays/\(stay.id)/keys", body: ["action": "returned"])
                }
                var body: [String: Any?] = ["checkOutDay": checkOutDay, "extras": StaysExtrasSection.payload(extras), "createInvoice": createInvoice]
                if createInvoice { body["keepDraft"] = keepDraft } else { body["noBillReason"] = noBillReason.nonEmpty }
                if keysOut && keysChoice == "later" { body["keysHandled"] = true }
                try await API.send("POST", "/provider-homestays/\(stay.id)/finish", body: body)
                Toast.show(createInvoice
                    ? (StaysBillChoice.goesToDesk(createInvoice: createInvoice, keepDraft: keepDraft, unpriced: noRate) ? L("Home stay finished. The bill is at the front desk to be charged.") : L("Home stay finished. The bill waits as a draft in Invoices."))
                    : (stay.familyOnApp ? L("Home stay finished. The family has been told.") : L("Home stay finished.")))
                announceDataChanged()
                dismiss()
            } catch let api as APIError where api.code == "keys_out" {
                _ = form.check([("keys", StaysWords.homeError(api, fallback: "Could not finish this home stay."))])
            } catch let api as APIError where api.code == "reason_required" {
                _ = form.check([("noBillReason", L("Write why it leaves without a bill."))])
            } catch {
                Toast.error(StaysWords.homeError(error, fallback: "Could not finish this home stay."))
            }
        }
    }
}

// MARK: - The plan of a home stay

/// A house task of a plan being written: its label and an optional time ("" = none).
struct StaysHouseTaskDraft: Identifiable, Equatable {
    let id = UUID()
    /// The server's key, kept when changing a booked stay so its checklist stays linked.
    var key: String? = nil
    var label = ""
    var time = ""
}

/// What a home stay plans: the days and times, overnight or drop-in visits,
/// the price and its unit (or a catalog service), the deposit, the vet
/// authorization, the house (rules and tasks) and the meet & greet.
struct StaysHomePlan: Equatable {
    var checkInDay: String
    var checkInTime: String
    var checkOutDay: String
    var checkOutTime: String
    var mode: String
    var times: [String]
    var durationMinutes: Int
    var overnightStart = "20:00"
    var overnightEnd = "08:00"
    var priceUnit: String
    var rate: Int?
    var deposit: Int?
    var vetAuthorization: Int?
    var houseRules = ""
    var catalogItemId: String? = nil
    var houseTasks: [StaysHouseTaskDraft] = []
    var meetGreetOn = false
    var meetGreetDate = ""
    var meetGreetTime = "18:00"
    var meetGreetMinutes = 30

    init(day: String = StaysDay.today(), mode: String = "visits") {
        checkInDay = day
        checkInTime = mode == "overnight" ? "18:00" : "07:00"
        checkOutDay = StaysDay.add(day, mode == "overnight" ? 1 : 2)
        checkOutTime = mode == "overnight" ? "10:00" : "21:00"
        self.mode = mode
        times = mode == "overnight" ? [] : ["08:00", "19:00"]
        durationMinutes = 45
        priceUnit = mode == "overnight" ? "night" : "visit"
        let twoBefore = StaysDay.add(day, -2)
        meetGreetDate = twoBefore >= StaysDay.today() ? twoBefore : StaysDay.today()
    }

    /// A booked home stay's plan, to change it (web draftFromStay).
    init(stay: StaysStay, home: StaysHomeDetail) {
        self.init(day: stay.checkInDay, mode: home.mode ?? "visits")
        checkInTime = stay.checkInTime ?? checkInTime
        checkOutDay = stay.checkOutDay
        checkOutTime = stay.checkOutTime ?? checkOutTime
        times = home.plan?.times ?? []
        durationMinutes = home.plan?.durationMinutes ?? 45
        overnightStart = home.plan?.overnightStart ?? "20:00"
        overnightEnd = home.plan?.overnightEnd ?? "08:00"
        priceUnit = home.priceUnit ?? priceUnit
        catalogItemId = home.catalogItem?.id
        rate = home.rateCents
        deposit = home.depositCents
        vetAuthorization = home.vetAuthorizationCents
        houseRules = home.houseRules ?? ""
        houseTasks = (home.houseTasks ?? []).map { StaysHouseTaskDraft(key: $0.key, label: $0.label ?? "", time: $0.time ?? "") }
    }

    var planBody: [String: Any?] {
        ["times": times, "durationMinutes": durationMinutes, "overnightStart": overnightStart, "overnightEnd": overnightEnd]
    }

    /// The house tasks as the server takes them: labelled ones, a time only when set, up to 20.
    var houseTasksBody: [[String: Any?]] {
        houseTasks.compactMap { task -> [String: Any?]? in
            guard let label = task.label.nonEmpty else { return nil }
            var item: [String: Any?] = ["label": String(label.prefix(120)), "time": task.time.isEmpty ? nil : task.time]
            if let key = task.key { item["key"] = key }
            return item
        }
        .prefix(20).map { $0 }
    }

    /// The meet & greet as the server takes it, with who goes.
    func meetGreetBody(sitterId: String?) -> [String: Any?]? {
        meetGreetOn ? ["date": meetGreetDate, "startTime": meetGreetTime, "durationMinutes": meetGreetMinutes, "memberId": sitterId] : nil
    }

    /// The fields a create sends (dates, plan, price, house, meet & greet).
    func body(sitterId: String?) -> [String: Any?] {
        var body: [String: Any?] = [
            "checkInDay": checkInDay, "checkInTime": checkInTime, "checkOutDay": checkOutDay, "checkOutTime": checkOutTime,
            "mode": mode, "plan": planBody, "priceUnit": priceUnit, "catalogItemId": catalogItemId,
            "vetAuthorizationCents": vetAuthorization, "houseRules": houseRules.nonEmpty, "houseTasks": houseTasksBody,
            "meetGreet": meetGreetBody(sitterId: sitterId),
        ]
        if let rate { body["rateCents"] = rate }
        if let deposit { body["depositCents"] = deposit }
        return body
    }

    /// The fields a create or a request's confirm sends.
    var body: [String: Any?] { body(sitterId: nil) }

    /// The server's rules, for errors before sending (homestays.ts).
    var problems: [(String, String?)] {
        var dates: String?
        if checkOutDay < checkInDay || (checkOutDay == checkInDay && checkOutTime <= checkInTime) {
            dates = L("Choose valid dates: the family comes back after they leave.")
        } else if StaysDay.between(checkInDay, checkOutDay) > 60 {
            dates = L("A home stay lasts 60 days at most.")
        } else if mode == "overnight" && checkOutDay <= checkInDay {
            dates = L("An overnight stay needs at least one night. Choose a later return day, or plan visits instead.")
        }
        var plan: String?
        if mode == "visits" && times.isEmpty { plan = L("Add at least one visit time.") }
        else if times.count > 6 { plan = L("Up to six visits a day.") }
        else if Set(times).count != times.count || overlaps { plan = L("Two visits of the same day overlap, or a daytime visit runs into the night.") }
        else if mode == "overnight" && StaysDay.minutes(overnightEnd) >= StaysDay.minutes(overnightStart) { plan = L("A night starts in the evening and ends the next morning.") }
        let meet: String? = meetGreetOn && (meetGreetDate.isEmpty || meetGreetDate > checkInDay) ? L("Choose a valid day and time for the meet & greet.") : nil
        return [("dates", dates), ("plan", plan), ("meetGreet", meet)]
    }

    /// Two drop-ins closer than a visit's length, or a drop-in inside the night.
    private var overlaps: Bool {
        let sorted = times.sorted().map(StaysDay.minutes)
        for index in sorted.indices.dropFirst() where sorted[index] < sorted[index - 1] + durationMinutes { return true }
        if mode == "overnight" {
            let start = StaysDay.minutes(overnightStart), end = StaysDay.minutes(overnightEnd)
            return sorted.contains { $0 < end || $0 + durationMinutes > start }
        }
        return false
    }
}

/// A service from the catalog a home stay can be billed as.
struct StaysCatalogService: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let defaultUnitAmount: Int?
    let currency: String?
}

/// The plan's fields (web HomePlanFields): mode, days and times, visits, price
/// (or a catalog service), the house's rules and tasks, and the meet & greet.
struct StaysHomePlanForm: View {
    /// The form's parts, in the web's order (HomePlanFields): How, When, the visits, Price, The house, Meet & greet.
    /// The new home stay sheet lays them over its steps (PlanModeSection, PlanVisitsSection…).
    enum Part { case mode, when, visits, price, house, meetGreet }

    @Binding var plan: StaysHomePlan
    var lockDays = false
    @ObservedObject var form: FormState
    /// The meet & greet section (not when changing a booked stay).
    var showMeetGreet = true
    var parts: Set<Part> = [.mode, .when, .visits, .price, .house, .meetGreet]
    /// The stay started: its first day stays.
    var startedDay: String? = nil
    /// Changing a booked stay: an empty deposit means none.
    var editing = false

    @State private var services: [StaysCatalogService] = []

    static func minutesText(_ minutes: Int) -> String {
        if minutes < 60 { return LF("%d min", minutes) }
        let hours = Double(minutes) / 60
        if hours == hours.rounded() { return LP(Int(hours), "%d hour", "%d hours") }
        return LF("%@ h", String(format: "%.1f", hours))
    }

    private var chosen: StaysCatalogService? { services.first { $0.id == plan.catalogItemId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) { fields }
            .task {
                guard services.isEmpty, parts.contains(.price) else { return }
                let page: Page<StaysCatalogService>? = try? await API.get("/provider-catalog", query: ["limit": "100", "offset": "0", "itemType": "service", "active": "true"])
                services = page?.items ?? []
            }
    }

    @ViewBuilder private var fields: some View {
        if parts.contains(.mode) { modeSection }
        if parts.contains(.when) { whenSection }
        if parts.contains(.visits) { visitsSection }
        if parts.contains(.price) { priceSection }
        if parts.contains(.house) { houseSection }
        if showMeetGreet && parts.contains(.meetGreet) { meetGreetSection }
    }

    private var modeSection: some View {
        ModalSection(title: L("How")) {
            ChoiceCards(options: [(value: "overnight", title: L("Overnight"), subtitle: L("The sitter sleeps at the home, evening to morning")),
                                  (value: "visits", title: L("Drop-in visits"), subtitle: L("Visits at set times each day"))],
                       selection: Binding(get: { plan.mode }, set: { mode in
                           guard mode != plan.mode else { return }
                           plan.mode = mode
                           plan.priceUnit = mode == "overnight" ? "night" : "visit"
                           if mode == "overnight" { plan.times = [] } else if plan.times.isEmpty { plan.times = ["08:00", "19:00"] }
                           if mode == "overnight" && plan.checkOutDay <= plan.checkInDay { plan.checkOutDay = StaysDay.add(plan.checkInDay, 1) }
                           form.clear("plan")
                       }))
        }
    }

    private var whenSection: some View {
        ModalSection(title: L("When"), subtitle: lockDays ? L("The family asked for these days; choose the times.") : L("From when the family leaves until they come back.")) {
            if lockDays {
                Text("\(StaysDay.short(plan.checkInDay)) – \(StaysDay.short(plan.checkOutDay))").font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
            } else {
                if let startedDay {
                    FactRow(label: L("They leave"), value: StaysDay.short(startedDay))
                    Text(L("The stay has started, so its first day stays.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                } else {
                    DayField(label: L("They leave"), day: Binding(get: { plan.checkInDay }, set: { value in
                        plan.checkInDay = value
                        if plan.checkOutDay < value || (plan.mode == "overnight" && plan.checkOutDay <= value) { plan.checkOutDay = StaysDay.add(value, 1) }
                        if plan.meetGreetDate > value { plan.meetGreetDate = value }
                    }), min: editing ? nil : StaysDay.today(), key: "dates", form: form)
                }
                DayField(label: L("They come back"), day: $plan.checkOutDay, min: plan.checkInDay)
            }
            TimeField(label: L("Time they leave"), value: $plan.checkInTime, from: "00:00", to: "23:45")
            TimeField(label: L("Time they come back"), value: $plan.checkOutTime, from: "00:00", to: "23:45")
        }
    }

    private var visitsSection: some View {
        ModalSection(title: plan.mode == "overnight" ? L("Nights and daytime visits") : L("Visits each day")) {
            if plan.mode == "overnight" {
                TimeField(label: L("Arrives in the evening"), value: $plan.overnightStart, from: "15:00", to: "23:45")
                TimeField(label: L("Leaves the next morning"), value: $plan.overnightEnd, from: "05:00", to: "12:00")
            }
            FormField(label: plan.mode == "overnight" ? L("Daytime drop-ins (optional)") : L("Times"), key: "plan", form: form) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(plan.times.indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            Menu {
                                ForEach(StaysDay.times(from: "05:00", to: "23:00"), id: \.self) { time in
                                    Button(StaysDay.clock(time)) { plan.times[index] = time; plan.times.sort(); form.clear("plan") }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Glyph("clock-3", size: 16).foregroundStyle(Theme.inkSoft)
                                    Text(StaysDay.clock(plan.times[index])).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                                    Spacer()
                                    Glyph("chevron-down", size: 16).foregroundStyle(Theme.inkSoft)
                                }
                                .fieldChrome()
                            }
                            IconCircleButton(systemImage: "x", label: L("Remove this time"), tint: Theme.inkSoft) { plan.times.remove(at: index) }
                        }
                    }
                    if plan.times.count < 6 {
                        PMButton(L("Add a time"), systemImage: "plus", variant: .outline, size: .compact) {
                            plan.times.append(plan.times.isEmpty ? "08:00" : plan.times.count == 1 ? "18:00" : "13:00")
                            plan.times.sort()
                            form.clear("plan")
                        }
                    }
                }
            }
            if !plan.times.isEmpty {
                MenuField(label: L("Length of each visit"), options: Array(Set([15, 20, 30, 45, 60, 90, 120, 180, 240, plan.durationMinutes])).sorted().map { (value: $0, title: Self.minutesText($0)) }, selection: $plan.durationMinutes)
            }
        }
    }

    private var priceSection: some View {
        ModalSection(title: L("Price"), subtitle: L("Not per pet: the family’s pets share the sitter. Add an extra pet as an extra when finishing.")) {
            ChoiceCards(options: [(value: "night", title: L("Per night"), subtitle: nil),
                                  (value: "visit", title: L("Per visit"), subtitle: L("Visits and nights made; never the meet & greet"))],
                        selection: $plan.priceUnit)
            MenuField(label: L("Service from your catalog"),
                      options: [(value: "", title: L("None — type the price"))] + services.map { (value: $0.id, title: "\($0.name) · \(Money.format($0.defaultUnitAmount, currency: $0.currency))") },
                      selection: Binding(get: { plan.catalogItemId ?? "" }, set: { id in
                          plan.catalogItemId = id.nonEmpty
                          if let item = services.first(where: { $0.id == id }) { plan.rate = item.defaultUnitAmount }
                      }))
            MoneyField(label: plan.priceUnit == "night" ? L("Price per night") : L("Price per visit"), cents: $plan.rate, key: "rate", form: form,
                       hint: chosen.map { LF("Empty: %@ from the catalog.", Money.format($0.defaultUnitAmount, currency: $0.currency)) })
            MoneyField(label: L("Deposit"), cents: $plan.deposit, hint: editing ? L("Empty or 0: no deposit.") : L("Empty: your usual stay deposit. 0: none."))
            MoneyField(label: L("Vet authorization up to"), cents: $plan.vetAuthorization, hint: L("The family signs it before the first visit."))
        }
    }

    private var houseSection: some View {
        ModalSection(title: L("The house"), subtitle: L("Rules the sitter follows, and chores laid out each day (plants, mail, trash).")) {
            PMTextField(L("House rules"), text: $plan.houseRules, prompt: L("e.g. Shoes off inside; Luna isn’t allowed on the sofa."), multiline: true)
            FormField(label: L("House tasks")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($plan.houseTasks) { $task in
                        HStack(spacing: 8) {
                            TextField(L("Water the plants"), text: $task.label).fieldChrome()
                            Menu {
                                Button(L("No set time")) { task.time = "" }
                                ForEach(StaysDay.times(from: "00:00", to: "23:45"), id: \.self) { time in
                                    Button(StaysDay.clock(time)) { task.time = time }
                                }
                            } label: {
                                Text(task.time.isEmpty ? L("Time") : StaysDay.clock(task.time))
                                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(task.time.isEmpty ? Theme.inkSoft : Theme.inkStrong)
                                    .frame(minWidth: 72)
                                    .fieldChrome()
                            }
                            .fixedSize()
                            IconCircleButton(systemImage: "x", label: L("Remove this task"), tint: Theme.inkSoft) {
                                plan.houseTasks.removeAll { $0.id == task.id }
                            }
                        }
                    }
                    if plan.houseTasks.count < 20 {
                        // Web: a blue bold link with a plus.
                        PMButton(L("Add a task"), systemImage: "plus", variant: .link, size: .small) { plan.houseTasks.append(StaysHouseTaskDraft()) }
                    }
                }
            }
        }
    }

    private var meetGreetSection: some View {
            ModalSection(title: L("Meet & greet")) {
                ToggleRow(title: L("Meet the family first"), subtitle: L("A short visit before the stay to meet the pets and get the keys. Not charged."), isOn: $plan.meetGreetOn)
                if plan.meetGreetOn {
                    DayField(label: L("Day"), day: $plan.meetGreetDate, min: StaysDay.today(), max: plan.checkInDay, key: "meetGreet", form: form)
                    TimeField(label: L("Time"), value: $plan.meetGreetTime, from: "07:00", to: "21:00")
                    MenuField(label: L("Length"), options: [15, 20, 30, 45, 60, 90].map { (value: $0, title: Self.minutesText($0)) }, selection: $plan.meetGreetMinutes)
                }
            }
    }
}

// MARK: - New home stay

private enum StaysHomeBookingStep: Int, CaseIterable { case who, plan, confirm }

struct StaysHomeBookingSheet: View {
    let presetDay: String
    let onBooked: () -> Void

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var step: StaysHomeBookingStep = .who
    @State private var client: PickedClient?
    @State private var petIds: [String] = []
    @State private var plan = StaysHomePlan()
    @State private var sitterId = ""
    @State private var sitters: [StaysMember] = []
    @State private var addressId: String?
    @State private var accessNotes = ""
    @State private var sendQuote = false
    @State private var ownerInstructions = ""
    @State private var internalNotes = ""
    @State private var conflict = false
    @State private var bookAnyway = false
    @State private var working = false
    @State private var started = false

    var body: some View {
        ProviderModal(title: L("New home stay"), subtitle: L("Pet sitting at the client’s home: overnight or drop-in visits."), systemImage: "house", accent: .aqua,
                      isDirty: client != nil || step != .who, form: form,
                      primaryTitle: step == .confirm ? (conflict ? L("Book anyway") : sendQuote ? L("Send quote") : L("Book home stay")) : L("Continue"),
                      isWorking: working,
                      steps: ModalSteps(steps: [(L("Who"), "user-round"), (L("The plan"), "calendar-days"), (L("Confirm"), "check")], current: step.rawValue),
                      onBack: step != .who ? { step = StaysHomeBookingStep(rawValue: step.rawValue - 1) ?? .who } : nil,
                      primaryIcon: step == .confirm ? (sendQuote && !conflict ? "send" : "check") : nil,
                      onPrimary: next) {
            if step != .who, let client {
                // What it's about, once chosen — the same pills as the other create modals; Back changes it.
                ContextPills(client: client.ownerName, linked: client.householdId != nil, pets: chosenPets.map(\.name))
            }
            switch step {
            case .who:
                ClientPetPicker(client: $client, petIds: $petIds, pets: .several, petRequired: true, petKey: "pets", form: form)
            case .plan:
                // Web order: How, When, the visits, At their home, Who goes, Meet & greet.
                StaysHomePlanForm(plan: $plan, form: form, parts: [.mode, .when, .visits])
                if let client {
                    ModalSection(title: L("At their home")) {
                        // The one address picker of every visit at a client's home.
                        SchedAddressPicker(clientId: client.id, addressId: $addressId, accessNotes: $accessNotes)
                    }
                }
                ModalSection(title: L("Who goes")) {
                    MenuField(label: L("Sitter"), options: [(value: "", title: L("Decide later"))] + sitters.map { (value: $0.id, title: $0.label) }, selection: $sitterId, key: "sitter", form: form)
                    if sitters.isEmpty {
                        Text(L("Nobody on your team looks after stays yet. Give someone “Care and report cards” in Staff."))
                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
                StaysHomePlanForm(plan: $plan, form: form, parts: [.meetGreet])
            case .confirm:
                summary
                StaysHomePlanForm(plan: $plan, form: form, parts: [.house])
                ModalSection(title: L("Notes")) {
                    PMTextField(L("What the family asked for"), text: $ownerInstructions, prompt: L("e.g. Luna hides under the bed when it thunders."), multiline: true)
                    PMTextField(L("Note for the team"), text: $internalNotes, prompt: L("Only your team sees this"), multiline: true)
                }
                StaysHomePlanForm(plan: $plan, form: form, parts: [.price])
                ModalSection(title: L("How to save it")) {
                    ChoiceCards(options: [(value: false, title: L("Book now"), subtitle: Optional(L("Confirmed straight away; the visits go on the calendar."))),
                                          (value: true, title: L("Send as a quote"), subtitle: Optional(client?.householdId != nil ? L("The family accepts it in the app") : L("The family isn’t on PawMiaw: you share it and confirm it for them")))],
                                selection: $sendQuote)
                }
                if conflict { StaysHomeTeam.conflictNotice(confirmed: $bookAnyway) }
            }
        }
        .task {
            guard !started else { return }
            started = true
            plan = StaysHomePlan(day: presetDay < StaysDay.today() ? StaysDay.today() : presetDay)
            if let clinic = workspace.current?.clinicId {
                let members: [StaysMember]? = try? await API.get("/provider-workspaces/\(clinic)/members")
                sitters = (members ?? []).filter(\.canCare)
            }
        }
        .onChange(of: client?.id) { _, _ in
            // Another family: their own address (the picker chooses its default) and no notes.
            addressId = nil
            accessNotes = ""
        }
        .onChange(of: sitterId) { _, _ in conflict = false; bookAnyway = false }
    }

    private var chosenPets: [PickedPet] { client?.activePets.filter { petIds.contains($0.id) } ?? [] }

    /// Web `SummaryTile`s: who, when and who goes, before the last choices.
    private var summary: some View {
        VStack(spacing: 8) {
            StaysSummaryTile(label: L("Who")) {
                HStack(spacing: 8) {
                    PetStack(pets: chosenPets.map { (name: $0.name, species: $0.petSpecies, photo: $0.photoUrl) }, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(chosenPets.map(\.name).joined(separator: ", ")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Text(client?.name ?? "").font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                }
            }
            StaysSummaryTile(label: L("When")) {
                Text("\(StaysDay.short(plan.checkInDay)) \(StaysDay.clock(plan.checkInTime)) – \(StaysDay.short(plan.checkOutDay)) \(StaysDay.clock(plan.checkOutTime))")
                    .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
            }
            StaysSummaryTile(label: L("Who goes")) {
                Text(sitters.first { $0.id == sitterId }?.label ?? L("Decide later")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
            }
        }
    }

    private func next() {
        switch step {
        case .who:
            guard form.check([
                ("client", client == nil ? L("Choose the client first.") : nil),
                ("pets", client != nil && petIds.isEmpty ? L("Choose at least one pet.") : nil),
            ]) else { return }
            step = .plan
        case .plan:
            guard form.check(plan.problems) else { return }
            step = .confirm
        case .confirm:
            if conflict && !bookAnyway { _ = form.check([("conflict", L("The sitter is busy then. Check the warning and book it anyway if you meant to."))]); return }
            book()
        }
    }

    private func book() {
        guard let client else { return }
        working = true
        Task {
            defer { working = false }
            var body = plan.body(sitterId: sitterId.nonEmpty)
            body["providerClientId"] = client.id
            body["providerClientPetIds"] = petIds
            body["sendQuote"] = sendQuote
            body["status"] = sendQuote ? "requested" : "confirmed"
            body["memberId"] = sitterId.nonEmpty
            body["addressId"] = addressId
            body["accessNotes"] = accessNotes.nonEmpty
            body["ownerInstructions"] = ownerInstructions.nonEmpty
            body["internalNotes"] = internalNotes.nonEmpty
            body["locationId"] = workspace.locationId
            if bookAnyway { body["allowDoubleBooking"] = true }
            do {
                let stay: StaysStay = try await API.post("/provider-homestays", body: body)
                Toast.show(sendQuote
                    ? (client.householdId != nil ? LF("Quote sent to the family · %@", stay.petNames) : LF("Quote saved · %@. The family isn’t on PawMiaw, so share it with them yourself.", stay.petNames))
                    : LF("%@ booked · %@", stay.petNames, "\(StaysDay.short(stay.checkInDay)) – \(StaysDay.short(stay.checkOutDay))"))
                announceDataChanged()
                onBooked()
                dismiss()
            } catch let api as APIError where api.code == "visit_conflict" {
                conflict = true
                bookAnyway = false
            } catch let api as APIError where ["invalid_member", "member_cannot_care", "member_not_at_location"].contains(api.code ?? "") {
                step = .plan
                _ = form.check([("sitter", StaysWords.homeError(api, fallback: "Could not book this home stay."))])
            } catch {
                Toast.error(StaysWords.homeError(error, fallback: "Could not book this home stay."))
            }
        }
    }
}
