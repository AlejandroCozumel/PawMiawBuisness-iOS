//
//  RecordsScreen.swift
//  PawMiawNegocios
//
//  Expedientes (web routes/provider.records.tsx): every vaccine, visit,
//  medicine, diagnosis and result the team writes, the drafts still waiting
//  for a signature, and the follow-ups those records leave behind. As on the
//  web: the module header (FileText on aqua, "Nuevo registro", the four
//  numbers), then one card — the view switch and the search, the filters on
//  one line, the list under its day bands, how many under it. Three views:
//  "Por completar" (a finished visit's notes and reports, the notes to sign,
//  drafts left empty), Records and Follow-ups, 20 at a time with infinite
//  scroll, counts from the server.
//

import SwiftUI

/// The record sheet's target: a new record, or one to edit.
struct RecordsSheetTarget: Identifiable {
    let id = UUID()
    let record: RecordsRecord?
}

struct RecordsScreen: View {
    @EnvironmentObject private var workspace: Workspace
    @StateObject private var model = RecordsListModel()
    @State private var query = ""
    @State private var sheet: RecordsSheetTarget?
    @State private var signTarget: RecordsRecord?
    @State private var discardTarget: RecordsRecord?
    @State private var waiveTarget: RecordsFollowUp?
    @State private var pushed: ProviderRoute?
    @State private var rangeOpen = false

    /// Few enough people to show as chips; a bigger team gets a list.
    private let maxPeopleChips = 4

    private var access: RecordsAccess { RecordsAccess(workspace) }

    var body: some View {
        PageScroll(refresh: { await model.load(workspace) }) {
            if !access.seesPage {
                NoAccessState(message: L("Ask the workspace owner to let your role see records or follow-ups."))
            } else {
                header
                if model.clientsTotal == 0 && !model.filtered {
                    EmptyState(
                        systemImage: "paw-print",
                        title: L("Add your first client and pet"),
                        message: L("Create the first provider client and pet here. After that, appointments, records, invoices, and care history can start from the same profile."),
                        actionTitle: access.viewClients ? L("Add first client and pet") : nil,
                        action: access.viewClients ? { pushed = .section(.clients) } : nil,
                        panel: true
                    )
                } else {
                    listCard
                }
            }
        }
        .providerPage(L("Records"), root: true)
        .reloadsOnScope { await model.load(workspace) }
        .debounced(query) { model.applySearch($0) }
        .navigationDestination(item: $pushed) { RouteView(route: $0) }
        .sheet(item: $sheet) { target in
            RecordsRecordSheet(record: target.record, members: model.members, access: access)
        }
        .sheet(item: $signTarget) { RecordsSignSheet(record: $0) }
        .sheet(item: $waiveTarget) { RecordsWaiveSheet(followUp: $0) }
        .sheet(item: $discardTarget) { record in
            ConfirmSheet(
                title: L("Discard this empty draft?"),
                message: LF("%@ for %@ has nothing written in it. It goes away; the history keeps that it was discarded.", record.titleText, record.petText),
                confirmTitle: L("Discard"),
                destructive: true,
                cancelTitle: L("Keep it"),
                icon: "file-text"
            ) { _ in
                try await RecordsAPI.discard(record.id)
                Toast.show(L("Draft discarded."))
                announceDataChanged()
            }
        }
        .sheet(isPresented: $rangeOpen) {
            RecordsRangeSheet(
                title: model.view == .records ? L("Record date") : L("Due date"),
                presets: model.view == .records ? [.today, .week, .month] : [.today, .month],
                from: model.view == .followUps && model.due != nil ? nil : model.from,
                to: model.view == .followUps && model.due != nil ? nil : model.to
            ) { from, to in model.setRange(from: from, to: to) }
        }
    }

    // MARK: Actions

    private func openCreate() {
        guard access.writeRecords else { return }
        if model.clientsTotal == 0 {
            if access.viewClients { pushed = .section(.clients) }
            return
        }
        sheet = RecordsSheetTarget(record: nil)
    }

    private func edit(_ record: RecordsRecord) { sheet = RecordsSheetTarget(record: record) }

    private func clearFilters() {
        query = ""
        model.clearFilters()
    }

    // MARK: Header

    private var header: some View {
        ModuleHeader(
            icon: "file-text",
            title: L("Records"),
            subtitle: L("Vaccines, visits, medicines and results — what still needs a signature and what is due next."),
            accent: Theme.aqua,
            stats: headerStats,
            storageKey: "records"
        ) {
            if access.writeRecords {
                PMButton(L("New record"), systemImage: "plus", action: openCreate)
            }
        }
    }

    private var headerStats: [ModuleStat] {
        var stats: [ModuleStat] = [
            ModuleStat("to-complete", label: L("To complete"), value: "\(model.toCompleteCount)",
                       hint: L("Notes, reports and signatures from finished visits"), icon: "clipboard-pen", accent: Theme.pink,
                       attention: model.toCompleteCount > 0, active: model.view == .toComplete,
                       action: { model.switchView(.toComplete) }),
        ]
        if access.records {
            stats.append(ModuleStat("signed", label: L("Signed@plural"), value: model.signedTotal.map { "\($0)" } ?? "—",
                                    hint: L("Already part of the chart"), icon: "badge-check", accent: ProviderState.done.color,
                                    active: model.view == .records && model.signChoice == .signed,
                                    action: { model.showSigned() }))
        }
        if access.followUps {
            stats.append(ModuleStat("overdue", label: L("Follow-ups overdue"), value: model.overdue.map { "\($0)" } ?? "—",
                                    hint: L("Past their date and still open"), icon: "alarm-clock", accent: Theme.pink,
                                    attention: (model.overdue ?? 0) > 0, active: model.view == .followUps && model.due == .overdue,
                                    action: { model.showFollowUps(due: .overdue) }))
            stats.append(ModuleStat("week", label: L("Due this week"), value: model.week.map { "\($0)" } ?? "—",
                                    hint: L("Rechecks, calls and vaccines"), icon: "calendar-clock", accent: ProviderState.waiting.color,
                                    active: model.view == .followUps && model.due == .week,
                                    action: { model.showFollowUps(due: .week) }))
        }
        return stats
    }

    // MARK: The card

    private var viewOptions: [Segmented<RecordsListView>.Option] {
        var options: [Segmented<RecordsListView>.Option] = [
            .init(.toComplete, L("To complete"), icon: "clipboard-pen", badge: model.toCompleteCount, attention: true),
        ]
        if access.records {
            options.append(.init(.records, L("Records"), icon: "file-text", badge: access.signRecords ? model.drafts : nil, attention: false))
        }
        if access.followUps {
            options.append(.init(.followUps, L("Follow-ups"), icon: "bell-ring", badge: model.overdue, attention: true))
        }
        return options
    }

    private var listCard: some View {
        Card(padding: 0, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    if viewOptions.count > 1 {
                        Segmented(options: viewOptions, selection: Binding(get: { model.view }, set: { model.switchView($0) }), look: .raised, label: L("View"), fill: true)
                    }
                    if model.view != .toComplete {
                        SearchField(prompt: model.view == .records ? L("Pet, client or record") : L("Pet, client or task"), text: $query, height: 40)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                RowDivider()

                if model.view == .records && workspace.multiLocation {
                    HStack { LocationMenu(); Spacer(minLength: 0) }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    RowDivider()
                }
                if model.view != .toComplete {
                    filters
                    RowDivider()
                }

                switch model.view {
                case .toComplete: toComplete
                case .records: recordsList
                case .followUps: followUpsList
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    // MARK: Filters

    /// One line of filters, one height (36): what state, when, which type, whose.
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let pet = model.pet {
                    // The toolbar's "only this pet" chip (web `PetFilterChip`), with "Abrir expediente" beside it.
                    HStack(spacing: 4) {
                        FilterChip(title: [pet.name, pet.clientName].filter { !$0.isEmpty }.joined(separator: " · "),
                                   face: AnyView(PetAvatar(name: pet.name, species: pet.species, photoURL: pet.photoUrl, size: 28)),
                                   removeLabel: L("Show every pet again")) { model.setPet(nil) }
                            .frame(maxWidth: 288)
                            .accessibilityLabel(L("Only this pet"))
                        if access.viewClients {
                            PMButton(L("Open chart"), variant: .link, size: .header) { pushed = .patientChart(petId: pet.id) }
                                .accessibilityLabel(LF("Open %@’s chart", pet.name))
                        }
                    }
                    separator
                }
                if model.view == .records {
                    FilterChip(title: L("All@records"), isSelected: model.signChoice == .all) { model.setSign(.all) }
                    FilterChip(title: L("To sign"), count: positive(model.drafts), isSelected: model.signChoice == .draft,
                               tone: ProviderState.waiting.color, dot: ProviderState.waiting.color) {
                        model.setSign(model.signChoice == .draft ? .all : .draft)
                    }
                    FilterChip(title: L("Signed@plural"), isSelected: model.signChoice == .signed,
                               tone: ProviderState.done.color, dot: ProviderState.done.color) {
                        model.setSign(model.signChoice == .signed ? .all : .signed)
                    }
                } else {
                    FilterChip(title: L("To do"), isSelected: model.followUpState == nil,
                               tone: ProviderState.waiting.color, dot: ProviderState.waiting.color) { model.setFollowUpState(nil) }
                    FilterChip(title: L("Reminded"), isSelected: model.followUpState == "contacted",
                               tone: ProviderState.active.color, dot: ProviderState.active.color) {
                        model.setFollowUpState(model.followUpState == "contacted" ? nil : "contacted")
                    }
                    FilterChip(title: L("Done@plural"), isSelected: model.followUpState == "done",
                               tone: ProviderState.done.color, dot: ProviderState.done.color) {
                        model.setFollowUpState(model.followUpState == "done" ? nil : "done")
                    }
                    FilterChip(title: L("All@records"), isSelected: model.followUpState == "all") {
                        model.setFollowUpState(model.followUpState == "all" ? nil : "all")
                    }
                    separator
                    FilterChip(title: L("Overdue"), count: positive(model.overdue), isSelected: model.due == .overdue,
                               tone: ProviderState.problem.color, icon: "alarm-clock") {
                        model.setDue(model.due == .overdue ? nil : .overdue)
                    }
                    FilterChip(title: L("This week"), count: positive(model.week), isSelected: model.due == .week,
                               tone: ProviderState.waiting.color, icon: "calendar-clock") {
                        model.setDue(model.due == .week ? nil : .week)
                    }
                    FilterChip(title: L("Later"), isSelected: model.due == .later, tone: ProviderState.upcoming.color, icon: "calendar-range") {
                        model.setDue(model.due == .later ? nil : .later)
                    }
                }
                separator
                let rangeFrom = model.view == .followUps && model.due != nil ? nil : model.from
                let rangeTo = model.view == .followUps && model.due != nil ? nil : model.to
                FilterChip(title: RecordsRange.label(from: rangeFrom, to: rangeTo) ?? L("Any date"), isSelected: rangeFrom != nil || rangeTo != nil,
                           tone: model.view == .records ? Theme.aqua : Theme.lavender, icon: "calendar-range") { rangeOpen = true }
                    .accessibilityHint(model.view == .records ? L("Record date") : L("Due date"))
                Menu {
                    Button(L("Every type")) { model.setType(nil) }
                    ForEach(RecordsKind.allCases) { kind in
                        Button { model.setType(kind) } label: { GlyphLabel(kind.label, icon: kind.systemImage) }
                    }
                } label: {
                    FilterMenuLabel(title: model.type?.label ?? L("Every type"), selected: model.type != nil)
                }
                .accessibilityLabel(L("Record type"))
                who
                if model.filtered {
                    Button(action: clearFilters) {
                        HStack(spacing: 4) {
                            Glyph("x", size: 14)
                            Text(L("Clear filters"))
                        }
                        .font(Theme.text(14, weight: .bold))
                        .foregroundStyle(Theme.blue)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var who: some View {
        if !model.seesAnyone {
            FilterChip(title: L("Assigned to you"), isSelected: false, tone: Theme.inkSoft, icon: "user-round") {}
                .allowsHitTesting(false)
        } else if !model.members.isEmpty && model.members.count <= maxPeopleChips {
            FilterChip(title: L("Anyone"), isSelected: model.who == nil, icon: "user-round") { model.setWho(nil) }
            ForEach(model.members) { member in
                FilterChip(title: member.label, isSelected: model.who == member.id, tone: Theme.aqua) {
                    model.setWho(model.who == member.id ? nil : member.id)
                }
            }
            FilterChip(title: L("Unassigned"), isSelected: model.who == "unassigned", tone: Theme.inkSoft) {
                model.setWho(model.who == "unassigned" ? nil : "unassigned")
            }
        } else {
            let title: String = {
                guard let who = model.who else { return L("Anyone") }
                if who == "unassigned" { return L("Unassigned") }
                return model.members.first { $0.id == who }?.label ?? L("Assigned to")
            }()
            Menu {
                Button(L("Anyone")) { model.setWho(nil) }
                Button(L("Unassigned")) { model.setWho("unassigned") }
                ForEach(model.members) { member in
                    Button(member.label) { model.setWho(member.id) }
                }
            } label: {
                FilterMenuLabel(title: title, selected: model.who != nil)
            }
            .accessibilityLabel(L("Assigned to"))
        }
    }

    private var separator: some View {
        Rectangle().fill(Theme.borderSoft).frame(width: 1, height: 24).padding(.horizontal, 4)
    }

    private func positive(_ value: Int?) -> Int? { (value ?? 0) > 0 ? value : nil }

    // MARK: To complete

    @ViewBuilder
    private var toComplete: some View {
        if !model.toCompleteLoaded {
            LoadingState()
        } else if model.toCompleteCount == 0 {
            EmptyState(systemImage: "clipboard-pen", title: L("Everything is complete"), message: L("Notes, reports and signatures from finished visits wait here until they are done."), accent: Theme.aqua)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if !model.paperwork.isEmpty {
                    DayBand(title: RecordsText.capitalizedFirst(L("Notes and reports to finish")), style: .records)
                    ForEach(Array(model.paperwork.enumerated()), id: \.element.id) { index, followUp in
                        if index > 0 { RowDivider() }
                        RecordsFollowUpRow(followUp: followUp, access: access, canWaive: access.isManager,
                                           onWaive: { waiveTarget = followUp }, onOpen: { pushed = $0 })
                    }
                }
                if !model.toSign.isEmpty {
                    if !model.paperwork.isEmpty { RowDivider() }
                    DayBand(title: RecordsText.capitalizedFirst(L("Notes to sign")), style: .records)
                    ForEach(Array(model.toSign.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { RowDivider() }
                        RecordsRecordRow(record: record, access: access, onSign: { signTarget = record }, onEdit: { edit(record) }, onOpen: { pushed = $0 })
                    }
                }
                if !model.unfinished.isEmpty {
                    if !model.paperwork.isEmpty || !model.toSign.isEmpty { RowDivider() }
                    DayBand(title: RecordsText.capitalizedFirst(L("Drafts left unfinished")), style: .records)
                    ForEach(Array(model.unfinished.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { RowDivider() }
                        RecordsRecordRow(record: record, mode: .unfinished, access: access, onEdit: { edit(record) },
                                         onDiscard: access.editRecords ? { discardTarget = record } : nil, onOpen: { pushed = $0 })
                    }
                }
                if model.hasMoreToComplete {
                    RowDivider()
                    PMButton(L("Show more"), variant: .outline, isWorking: model.loadingMore) {
                        Task { await model.loadMoreToComplete() }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: Records and follow-ups

    private var recordsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecordsDayList(pager: model.recordsPager, dayOf: { RecordsText.dayKey($0.eventAt) }) {
                emptyList
            } row: { record in
                RecordsRecordRow(
                    record: record,
                    access: access,
                    needle: model.search,
                    onSign: { signTarget = record },
                    onEdit: { edit(record) },
                    onFilterPet: model.pet?.id == record.providerClientPetId ? nil : { model.setPet(record.petFilter) },
                    onOpen: { pushed = $0 }
                )
            }
            RecordsListFooter(pager: model.recordsPager, one: "%d record", other: "%d records", range: RecordsRange.label(from: model.from, to: model.to))
        }
    }

    private var followUpsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecordsDayList(pager: model.followUpsPager, dayOf: { RecordsText.dayKey($0.dueAt) }) {
                emptyList
            } row: { followUp in
                RecordsFollowUpRow(
                    followUp: followUp,
                    access: access,
                    grouped: true,
                    needle: model.search,
                    reach: model.reach[followUp.providerClientId],
                    onFilterPet: model.pet?.id == followUp.providerClientPetId ? nil : { model.setPet(followUp.petFilter) },
                    onOpen: { pushed = $0 }
                )
            }
            RecordsListFooter(pager: model.followUpsPager, one: "%d follow-up", other: "%d follow-ups", range: model.due == nil ? RecordsRange.label(from: model.from, to: model.to) : nil)
        }
    }

    /// Nothing to list, and the way out: clear the filters, write a record, or go to the records.
    @ViewBuilder
    private var emptyList: some View {
        let isRecords = model.view == .records
        let needle = model.search
        let drafts = isRecords && model.onlyDrafts
        let filtered = model.filtered
        let title: String = !needle.isEmpty
            ? LF("Nothing matches “%@”", needle)
            : isRecords
                ? (drafts ? L("Nothing waiting for a signature") : filtered ? L("No records match these filters") : L("No records yet"))
                : (filtered ? L("No follow-ups match these filters") : L("No follow-ups to do"))
        let message: String = isRecords
            ? (drafts ? L("Every record is signed.") : filtered ? L("Try another search, or clear the filters.") : L("Vaccines, visits, diagnoses and results your team writes show up here."))
            : (filtered ? L("Try another search, or clear the filters.") : L("When a record has a follow-up date, it waits here until someone closes it."))
        let create = access.writeRecords && !filtered
        let seeRecords = !isRecords && access.records && !filtered
        VStack(spacing: 0) {
            EmptyState(systemImage: isRecords ? "file-text" : "bell-ring", title: title, message: message, accent: isRecords ? Theme.aqua : Theme.pink)
            if filtered || create || seeRecords {
                FlowLayout(spacing: 8) {
                    if filtered {
                        PMButton(drafts && needle.isEmpty ? L("See all records") : L("Clear filters"), systemImage: drafts && needle.isEmpty ? nil : "x", variant: .outline, size: .header, action: clearFilters)
                    }
                    if create {
                        PMButton(L("New record"), systemImage: "plus", size: .header, action: openCreate)
                    }
                    if seeRecords {
                        PMButton(L("See records"), systemImage: "file-text", variant: .outline, size: .header) { model.switchView(.records) }
                    }
                }
                .padding(.top, -12)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// How many, under the list, from the server's total: "**24 registros** · Esta semana".
struct RecordsListFooter<Item: Decodable & Identifiable>: View {
    @ObservedObject var pager: Pager<Item>
    let one: String
    let other: String
    var range: String? = nil

    var body: some View {
        if pager.loadedOnce, let total = pager.total, total > 0 {
            VStack(spacing: 0) {
                RowDivider()
                (Text(pager.isLoading ? L("Updating…") : LP(total, one, other)).font(Theme.text(14, weight: .bold)).foregroundColor(Theme.inkStrong)
                 + Text(range.map { " · \($0)" } ?? "").font(Theme.text(14)).foregroundColor(Theme.inkSoft))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }
}
