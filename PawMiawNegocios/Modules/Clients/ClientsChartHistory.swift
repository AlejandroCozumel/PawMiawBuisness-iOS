//
//  ClientsChartHistory.swift
//  PawMiawNegocios
//
//  The chart's tabs (web: patient-chart/chart-timeline.tsx, chart-files.tsx
//  and the tabs of provider.clients.$clientId.pets.$petId.tsx): one line of
//  time of everything that happened, newest first and paged by the server
//  (20 at a time as it scrolls), with filters and a search; the visits,
//  follow-ups, files, bills and the pet's details. And weighing the pet
//  (chart-weight-sheet.tsx).
//

import SwiftUI

// MARK: - History

struct ClientsTimelineView: View {
    let clientId: String
    let petId: String
    let chart: ClientsChart

    @State private var filters: Set<String> = []
    @State private var query = ""
    @State private var search = ""
    @State private var items: [ClientsTimelineItem] = []
    @State private var cursor: String?
    @State private var sources: ClientsTimelineSources?
    @State private var loading = false
    @State private var loadingMore = false
    @State private var failed = false
    @State private var loaded = false
    @State private var open: Set<String> = []
    @State private var signing: String?
    @State private var consentOpen: ClientsConsentTarget?

    private static let allFilters = ["consults", "grooming", "vaccines", "medications", "labs", "surgeries", "family", "notes"]

    private var viewer: ClientsChartViewer? { chart.viewer }

    private var choices: [String] {
        Self.allFilters.filter { filter in
            switch filter {
            case "family": viewer?.seesRecords == true && (sources?.family ?? true)
            case "consults": viewer?.seesVisits == true || viewer?.seesRecords == true
            // Only for a pet that has been groomed here; it stays while it is the one picked.
            case "grooming": viewer?.seesVisits == true && (sources?.grooming == true || filters.contains("grooming"))
            default: viewer?.seesRecords == true
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SearchField(prompt: L("Search the history"), text: $query)
                if !choices.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            FilterChip(title: L("All"), isSelected: filters.isEmpty) { filters = []; reload() }
                            ForEach(choices, id: \.self) { filter in
                                FilterChip(title: label(filter), isSelected: filters.contains(filter)) {
                                    if filters.contains(filter) { filters.remove(filter) } else { filters.insert(filter) }
                                    reload()
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityLabel(L("Show"))
                }
            }
            let searching = !search.isEmpty || !filters.isEmpty
            if !loaded && loading {
                LoadingState()
            } else if failed && items.isEmpty {
                ErrorState(message: L("The history could not be loaded.")) { await load(reset: true) }
            } else if items.isEmpty {
                EmptyState(systemImage: searching ? "search" : "history", title: searching ? L("Nothing matches") : L("No history yet"), message: searching ? L("Try another word or clear the filters.") : L("Visits, records and weights will appear here."))
            } else {
                ClientsChartSectionTitle(text: searching ? L("Results") : L("Newest first"))
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        entry(item)
                            .onAppear { if item.id == items.last?.id, cursor != nil { Task { await load(reset: false) } } }
                    }
                    if loadingMore { ProgressView().tint(Theme.blue).frame(maxWidth: .infinity).padding(.vertical, 8) }
                }
                .opacity(loading ? 0.6 : 1)
            }
        }
        .task { await load(reset: true) }
        .sheet(item: $consentOpen) { target in
            ConsentViewSheet(consentId: target.id, context: ConsentContext(act: ConsentAct(providerClientPetId: chart.pet.id), clientName: chart.client.name, familyOnApp: chart.client.onPawMiaw ?? false, clientEmail: chart.client.email, clientPhone: chart.client.phone))
        }
        .debounced(query) { value in
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard trimmed != search else { return }
            search = trimmed
            await load(reset: true)
        }
    }

    private func label(_ filter: String) -> String {
        switch filter {
        case "consults": L("Consults")
        case "grooming": L("Grooming")
        case "vaccines": L("Vaccines")
        case "medications": L("Medications")
        case "labs": L("Lab")
        case "surgeries": L("Surgeries")
        case "family": L("From the family")
        default: L("Notes")
        }
    }

    private func reload() { Task { await load(reset: true) } }

    private func load(reset: Bool) async {
        if reset { loading = true } else {
            guard !loadingMore, let _ = cursor else { return }
            loadingMore = true
        }
        defer { loading = false; loadingMore = false }
        let types = filters.sorted().joined(separator: ",").nonEmpty
        do {
            let page: ClientsTimelinePage = try await API.get("/provider-clients/\(clientId)/pets/\(petId)/timeline", query: [
                "limit": "20", "types": types, "q": search.nonEmpty, "cursor": reset ? nil : cursor,
            ])
            if reset {
                items = page.items
                sources = page.sources
            } else {
                let known = Set(items.map(\.id))
                items += page.items.filter { !known.contains($0.id) }
            }
            cursor = page.nextCursor
            failed = false
        } catch is CancellationError {
        } catch {
            failed = true
            if !reset { Toast.error(error) }
        }
        loaded = true
    }

    // MARK: Entries

    @ViewBuilder
    private func entry(_ item: ClientsTimelineItem) -> some View {
        switch item.kind {
        case "visit": if let visit = item.visit { visitEntry(item.key, visit) }
        case "record": if let record = item.record { recordEntry(item.key, record) }
        case "family_record": if let record = item.familyRecord { familyEntry(item.key, record) }
        case "weight": if let weight = item.weight { weightEntry(item.key, weight) }
        case "incident": if let incident = item.incident { incidentEntry(item.key, incident) }
        case "consent": if let consent = item.consent { consentEntry(item.key, consent) }
        // A kind this screen doesn't know yet (a newer server) is left out rather than breaking the list.
        default: EmptyView()
        }
    }

    /// One entry on the line of time (web `EntryShell`): the rail and its 28 disc of the entry's tone, then a
    /// bordered box that opens in place (blue edge while open).
    private func shell<Badges: View, Body: View>(_ key: String, icon: String, tone: Color, title: Text, meta: String, detail: String? = nil, @ViewBuilder badges: () -> Badges, @ViewBuilder content: () -> Body) -> some View {
        let isOpen = open.contains(key)
        let badgeViews = badges()
        let bodyView = content()
        let shape = RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous)
        return HStack(alignment: .top, spacing: 8) {
            ZStack(alignment: .top) {
                Rectangle().fill(Theme.borderSoft).frame(width: 1).frame(maxHeight: .infinity)
                Glyph(icon, size: 14)
                    .foregroundStyle(Theme.mix(tone, 70, with: Theme.inkStrong))
                    .frame(width: 28, height: 28)
                    .background(Theme.wash(tone, 25), in: Circle())
                    .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                    .padding(.top, 10)
            }
            .frame(width: 28)
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { if isOpen { open.remove(key) } else { open.insert(key) } }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            title.font(Theme.text(14)).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.leading)
                            Text(meta).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                            if let detail { Text(detail).font(Theme.text(12)).foregroundStyle(Theme.inkStrong) }
                            FlowLayout(spacing: 4) { badgeViews }.padding(.top, 4)
                        }
                        Spacer(minLength: 0)
                        Glyph("chevron-down", size: 16).foregroundStyle(Theme.inkSoft).rotationEffect(.degrees(isOpen ? 180 : 0)).padding(.top, 2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOpen ? .isSelected : [])
                if isOpen {
                    RowDivider()
                    VStack(alignment: .leading, spacing: 12) { bodyView }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(isOpen ? Theme.blue : Theme.borderSoft, lineWidth: 1))
            .shadow(color: Theme.navy.opacity(isOpen ? 0.06 : 0), radius: 2, y: 1)
            .padding(.bottom, 8)
        }
    }

    /// A title in bold with what was written there after it, quieter (web: "Consulta — dolor de oído").
    private func title(_ main: String, _ line: String?) -> Text {
        Text(main).bold() + Text(line?.nonEmpty.map { " — \($0)" } ?? "").foregroundColor(Theme.inkSoft)
    }

    private func visitEntry(_ key: String, _ visit: ClientsChartVisit) -> some View {
        let groom = visit.serviceCategory == "groomer"
        let records = visit.records ?? []
        let note = records.first { $0.recordType == "vet_visit" } ?? records.first
        let line = note?.summary ?? note?.details ?? (visit.report == nil || visit.report?.isNull == true ? visit.notes : nil)
        let drafts = records.filter { $0.status == "draft" }.count
        let weights = visit.weights ?? []
        let hasReport = visit.report != nil && visit.report?.isNull == false
        return shell(
            key, icon: groom ? "scissors" : "stethoscope", tone: groom ? Theme.pink : Theme.blue,
            title: title(visit.serviceLabel ?? "—", line),
            meta: [ClientsText.dayTime(visit.startsAt), visit.assigned?.name, visit.location?.name].compactMap { $0?.nonEmpty }.joined(separator: " · "),
            detail: groom ? visit.groomRequestSummary.map { LF("Asked for: %@", $0) } : nil
        ) {
            if visit.status != "completed" { Chip(text: ClientsText.visitStatus(visit.status), tone: visit.status == "no_show" ? .danger : .warn) }
            if drafts > 0 { Chip(text: L("To sign"), tone: .warn) }
            ForEach((ClientsReportBlock.decode(visit.report)?.skin ?? []).filter { $0 != "ok" }, id: \.self) { finding in
                Chip(text: SvcReportText.option(finding), tone: .danger, icon: "triangle-alert")
            }
            if hasReport { Chip(text: L("Report"), tone: .good) }
            if let first = weights.first { Chip(text: ClientsText.weight(first.grams) ?? "—", tone: .good) }
            if visit.carriedOver == true { Chip(text: L("With its earlier family"), tone: .warn) }
            else if visit.actionable == false { Chip(text: L("Another location"), tone: .muted, icon: "map-pin") }
        } content: {
            if let arrival = visit.arrivalNote?.nonEmpty { textBox(L("Reason for the visit"), arrival) }
            else if let notes = visit.notes?.nonEmpty { textBox(L("Booking notes"), notes) }
            ForEach(weights) { weight in
                HStack(spacing: 6) {
                    Glyph("scale", size: 16).foregroundStyle(Theme.inkSoft)
                    Text(LF("Weighed %@", ClientsText.weight(weight.grams) ?? "—")).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                }
            }
            if let report = ClientsReportBlock.decode(visit.report) {
                ClientsReportBlock(report: report)
            }
            ForEach(records) { record in
                VStack(alignment: .leading, spacing: 8) {
                    FlowLayout(spacing: 6) {
                        recordsTypeChip(RecordsKind.of(record.recordType))
                        Text(Self.recordTitle(record)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        if record.status == "draft" { Chip(text: L("To sign"), tone: .warn) }
                    }
                    recordBody(record)
                }
                .padding(10)
                .background(Theme.wash(Theme.surfaceMuted, 60), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            }
            if records.isEmpty && !hasReport && viewer?.seesRecords == true {
                Text(L("No note was written for this visit.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            HStack {
                Spacer(minLength: 0)
                if visit.actionable != false {
                    openLink(L("Open visit"), .appointment(visit.id))
                } else if visit.carriedOver == true {
                    // A visit it made with the client it was with before: part of its history, read here.
                    Text(L("From its earlier record — read only here.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                } else {
                    Text(LF("At %@ — only its team can act on this visit.", visit.location?.name ?? L("another location"))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    private func recordEntry(_ key: String, _ record: ClientsChartRecord) -> some View {
        shell(
            key, icon: "calendar-days", tone: Theme.aqua,
            title: title(Self.recordTitle(record), record.summary),
            meta: [ClientsText.shortDay(record.eventAt), record.signedBy?.name ?? record.createdBy?.name].compactMap { $0?.nonEmpty }.joined(separator: " · ")
        ) {
            recordsTypeChip(RecordsKind.of(record.recordType))
            if record.carriedOver == true { Chip(text: L("With its earlier family"), tone: .warn) }
            if record.status == "draft" { Chip(text: L("To sign"), tone: .warn) }
            if let count = record.attachments?.count, count > 0 { Chip(text: LP(count, "%d file", "%d files"), tone: .info) }
        } content: {
            recordBody(record)
        }
    }

    /// The written part of a clinic record, with the staff-only note marked as such (web `RecordBody`).
    @ViewBuilder
    private func recordBody(_ record: ClientsChartRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let summary = record.summary?.nonEmpty { textBox(L("For the family"), summary, tone: Theme.aqua) }
            if let details = record.details?.nonEmpty { textBox(L("Clinical notes"), details) }
            if let note = record.internalNote?.nonEmpty { textBox(L("Staff only"), note, tone: Theme.mango, icon: "lock") }
            fields(record.payload)
            ClientsAttachmentTiles(files: record.attachments ?? [])
            FlowLayout(spacing: 8) {
                Text(record.status == "draft"
                     ? LF("Draft by %@", record.createdBy?.name ?? L("someone on the team"))
                     : LF("Signed by %@ · %@", record.signedBy?.name ?? "—", ClientsText.shortDay(record.signedAt ?? record.eventAt)) + (record.amendedAt.map { " · \(LF("corrected %@", ClientsText.shortDay($0)))" } ?? ""))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    .frame(minHeight: 40)
                if record.status == "draft" && viewer?.canSign == true && record.actionable != false {
                    PMButton(L("Sign"), systemImage: "badge-check", size: .compact, isWorking: signing == record.id) { sign(record) }
                }
                openLink(L("Open record"), .record(record.id)).frame(minHeight: 40)
            }
        }
    }

    private func familyEntry(_ key: String, _ record: ClientsFamilyRecord) -> some View {
        shell(
            key, icon: "house", tone: Theme.pink,
            title: title(Self.familyTitle(record), record.summary),
            meta: [ClientsText.shortDay(record.eventAt ?? record.createdAt), record.by].compactMap { $0?.nonEmpty }.joined(separator: " · ")
        ) {
            recordsTypeChip(RecordsKind.of(record.recordType))
            Chip(text: L("Registered by the family"), tone: .online, icon: "user-round")
        } content: {
            if let details = record.details?.nonEmpty { textBox(L("Notes"), details) }
            fields(record.payload)
            if let next = record.nextDueAt { Text(LF("Next due %@", ClientsText.shortDay(next))).font(Theme.text(14)).foregroundStyle(Theme.inkStrong) }
            ClientsAttachmentTiles(files: record.attachments ?? [])
            Text(L("Read-only: the family keeps this record in PawMiaw.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
    }

    /// A weight: the clinic's, or one the family logged at home and shares — shown as theirs, never as the pet's weight here.
    private func weightEntry(_ key: String, _ weight: ClientsChartWeight) -> some View {
        let atHome = weight.from == "family"
        let takenFromHome = weight.from == "clinic" && weight.source == "family"
        return shell(
            key, icon: "scale", tone: atHome ? Theme.apricot : Theme.lime,
            title: Text(atHome ? LF("At home: %@", ClientsText.weight(weight.grams) ?? "—") : LF("Weighed %@", ClientsText.weight(weight.grams) ?? "—")).bold(),
            meta: [ClientsText.shortDay(weight.recordedAt), atHome ? L("the family") : weight.loggedBy ?? (weight.source == "manual" && weight.from == nil ? L("the family") : nil)].compactMap { $0?.nonEmpty }.joined(separator: " · ")
        ) {
            EmptyView()
        } content: {
            if let notes = weight.notes?.nonEmpty { Text(notes).font(Theme.text(14)).foregroundStyle(Theme.inkStrong) }
            Text(atHome ? L("Logged by the family at home and shared with you.") : takenFromHome ? L("The family’s weight, taken into the clinic’s log.") : weight.sharedWithOwner == true ? L("Shared with the family") : L("Kept in the clinic"))
                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
    }

    private func incidentEntry(_ key: String, _ incident: JSONValue) -> some View {
        shell(
            key, icon: "shield-alert", tone: Theme.pink,
            title: title(L("Incident"), incident["whatHappened"]?.string),
            meta: [ClientsText.dayTime(incident["occurredAt"]?.string), incident["serviceLabel"]?.string ?? (incident["stayId"]?.string?.nonEmpty != nil ? L("Stay") : nil)].compactMap { $0?.nonEmpty }.joined(separator: " · ")
        ) {
            if let type = incident["type"]?.string { HueChip(text: IncidentWords.type(type), hue: .peach, systemImage: IncidentWords.typeIcon(type)) }
            if let severity = incident["severity"]?.string { StatusChip(text: IncidentWords.severity(severity), state: IncidentWords.state(severity)) }
            if let status = incident["status"]?.string {
                StatusChip(text: status == "resolved" ? L("Resolved") : L("Follow-up open"), state: status == "resolved" ? .done : .active, outlined: true)
            }
        } content: {
            HStack {
                Spacer(minLength: 0)
                if let appointment = incident["appointmentId"]?.string?.nonEmpty {
                    openLink(L("Open visit"), .appointment(appointment))
                } else if let stay = incident["stayId"]?.string?.nonEmpty {
                    openLink(L("Open stay"), .stay(stay))
                }
            }
        }
    }

    private func consentEntry(_ key: String, _ consent: JSONValue) -> some View {
        let at = consent["signedAt"]?.string ?? consent["revokedAt"]?.string ?? consent["declinedAt"]?.string ?? consent["requestedAt"]?.string
        return shell(
            key, icon: "signature", tone: Theme.lavender,
            title: Text(consent["title"]?.string ?? L("Consent")).bold(),
            meta: [ClientsText.dayTime(at), consent["petName"]?.string].compactMap { $0?.nonEmpty }.joined(separator: " · ")
        ) {
            if let status = consent["status"]?.string { StatusChip(text: ClientsConsentWords.status(status), state: ClientsConsentWords.state(status)) }
        } content: {
            if let line = ClientsConsentWords.line(consent) { Text(line).font(Theme.text(14)).foregroundStyle(Theme.inkStrong) }
            if let body = consent["body"]?.string?.nonEmpty { Text(body).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(4) }
            FlowLayout(spacing: 12) {
                if let appointment = consent["appointmentId"]?.string?.nonEmpty {
                    openLink(L("Open visit"), .appointment(appointment)).frame(minHeight: 40)
                } else if let stay = consent["stayId"]?.string?.nonEmpty {
                    openLink(L("Open stay"), .stay(stay)).frame(minHeight: 40)
                }
                if let id = consent["id"]?.string?.nonEmpty {
                    PMButton(consent["status"]?.string == "signed" ? L("View and print") : L("View@consent"), systemImage: "eye", variant: .outline, size: .compact) {
                        consentOpen = ClientsConsentTarget(id: id, petName: consent["petName"]?.string)
                    }
                }
            }
        }
    }

    // MARK: Pieces

    /// "Abrir visita ↗": a quiet blue link to the page the entry is about.
    private func openLink(_ text: String, _ route: ProviderRoute) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 4) {
                Text(text)
                Glyph("external-link", size: 12)
            }
            .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue)
        }
        .buttonStyle(.plain)
    }

    /// A labelled piece of writing (web `Text`): a bordered box, a wash of its tone, the label small and tracked.
    private func textBox(_ label: String, _ text: String, tone: Color? = nil, icon: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.brandText(10.9, weight: .heavy)).tracking(1.1).foregroundStyle(Theme.inkSoft)
            HStack(alignment: .top, spacing: 4) {
                if let icon { Glyph(icon, size: 14).foregroundStyle(Theme.inkStrong).padding(.top, 2) }
                Text(text).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.map { AnyShapeStyle(Theme.wash($0, 8)) } ?? AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    /// A record's type-specific fields, as label and value.
    @ViewBuilder
    private func fields(_ payload: [String: JSONValue]?) -> some View {
        let rows: [(String, String)] = (payload ?? [:]).sorted { $0.key < $1.key }.compactMap { (pair: (key: String, value: JSONValue)) -> (String, String)? in
            let key = pair.key, value = pair.value
            let text: String?
            switch value {
            case .string(let string): text = string.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil ? (string.count > 10 ? ClientsText.dayTime(string) : ClientsText.shortDay(string)) : string
            case .number: text = value.string
            case .bool(let flag): text = flag ? L("Yes") : L("No")
            case .array(let items): text = items.compactMap(\.string).joined(separator: ", ")
            default: text = nil
            }
            guard let text = text?.nonEmpty else { return nil }
            let label = key.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: #"([a-z])([A-Z])"#, with: "$1 $2", options: .regularExpression).lowercased()
            return (L(label.prefix(1).uppercased() + label.dropFirst()), text)
        }
        if !rows.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .topLeading)], alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.0) { row in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.0.uppercased()).font(.brandText(10.9, weight: .heavy)).tracking(1.1).foregroundStyle(Theme.inkSoft)
                        Text(row.1).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    }
                }
            }
        }
    }

    static func recordTitle(_ record: ClientsChartRecord) -> String {
        for key in ["vaccine_name", "medication_name", "test_name", "condition", "trigger", "procedure"] {
            if let value = record.payload?[key]?.string?.nonEmpty { return value }
        }
        return record.title ?? ClientsText.recordType(record.recordType)
    }

    static func familyTitle(_ record: ClientsFamilyRecord) -> String {
        for key in ["vaccine_name", "medication_name", "test_name", "condition", "trigger", "procedure", "product_name"] {
            if let value = record.payload?[key]?.string?.nonEmpty { return value }
        }
        return record.title ?? L("Record")
    }

    /// Signing happens inside an opened entry — the note is on screen — so one tap.
    private func sign(_ record: ClientsChartRecord) {
        signing = record.id
        Task {
            defer { signing = nil }
            do {
                let _: EmptyResponse = try await API.post("/provider-records/\(record.id)/sign")
                Toast.show(chart.client.householdId != nil ? L("Signed. The family can see it now.") : L("Signed."))
                announceDataChanged()
                await load(reset: true)
            } catch {
                Toast.error(error, fallback: L("Could not sign it."))
            }
        }
    }
}

/// A record's files as square tiles (web `AttachmentTiles`): three across, each the kit's
/// `AttachmentTile` with its name inside; a photo shows itself.
struct ClientsAttachmentTiles: View {
    let files: [ClientsAttachment]
    @Environment(\.openURL) private var openURL

    var body: some View {
        if !files.isEmpty {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(files) { file in
                    if let url = APIConfig.assetURL(file.url) {
                        AttachmentTile(fileName: file.fileName ?? L("File"), isImage: ClientsFileKind.isImage(mimeType: file.mimeType, name: file.fileName),
                                       isPDF: file.mimeType == "application/pdf", caption: false) { openURL(url) } thumbnail: {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() } else { Theme.surfaceMuted }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Whether a file is a photo (web `isImageFile`).
enum ClientsFileKind {
    static func isImage(mimeType: String?, name: String?) -> Bool {
        if mimeType?.hasPrefix("image/") == true { return true }
        return (name ?? "").range(of: #"\.(jpe?g|png|webp|gif|heic)$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// "120 KB", "1.4 MB" (web `fileSizeLabel`).
    static func size(_ bytes: Int?) -> String? {
        guard let bytes, bytes > 0 else { return nil }
        if bytes < 1024 * 1024 { return "\(max(1, Int((Double(bytes) / 1024).rounded()))) KB" }
        let formatter = NumberFormatter()
        formatter.locale = .app
        formatter.maximumFractionDigits = 1
        return "\(formatter.string(from: NSNumber(value: Double(bytes) / (1024 * 1024))) ?? "") MB"
    }
}

// MARK: - A tab's parts

/// A tab's heading (web `h3 font-heading text-lg`), with an optional action at its right.
private struct ClientsTabHeading<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

private extension ClientsTabHeading where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}

/// Rows in one bordered box with hairlines between them (web `divide-y rounded-box border`).
private struct ClientsRowBox<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { RowDivider() }
                row(item)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .clientsChartBox()
    }
}

// MARK: - Appointments

struct ClientsChartAppointments: View {
    let chart: ClientsChart
    let onBook: (() -> Void)?

    @State private var items: [ClientsAppointment]?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let items {
                let now = DateText.iso(Date())
                let active: Set<String> = ["scheduled", "checked_in", "in_progress", "requested"]
                let upcoming = items.filter { ($0.startsAt ?? "") >= now && active.contains($0.status ?? "") }.sorted { ($0.startsAt ?? "") < ($1.startsAt ?? "") }
                let past = items.filter { item in !upcoming.contains { $0.id == item.id } }
                ClientsTabHeading(title: L("Upcoming")) {
                    if let onBook { PMButton(L("Book"), systemImage: "calendar-plus", variant: .outline, size: .compact, action: onBook) }
                }
                if upcoming.isEmpty { EmptyState(systemImage: "calendar-plus", title: L("Nothing booked.")) } else { list(upcoming) }
                ClientsTabHeading(title: L("Past"))
                if past.isEmpty { EmptyState(systemImage: "calendar-clock", title: L("No past appointments.")) } else { list(past) }
                if items.count >= 100 { Text(L("Showing the latest 100. The Schedule has the rest.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
            } else {
                LoadingState()
            }
        }
        .task {
            let page: Page<ClientsAppointment>? = try? await API.get("/provider-appointments", query: ["limit": "100", "offset": "0", "providerClientId": chart.client.id, "providerClientPetId": chart.pet.id, "order": "desc"])
            items = page?.items ?? []
        }
    }

    private func list(_ entries: [ClientsAppointment]) -> some View {
        ClientsRowBox(items: entries) { item in
            NavigationLink(value: ProviderRoute.appointment(item.id)) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.serviceLabel ?? "—").font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Text([ClientsText.dayTime(item.startsAt), item.assignedMember?.name].compactMap { $0?.nonEmpty }.joined(separator: " · ")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 8)
                    Text(ClientsText.visitStatus(item.status)).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Follow-ups

struct ClientsChartFollowUps: View {
    let chart: ClientsChart
    @State private var items: [ClientsFollowUp]?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let items {
                if items.isEmpty {
                    EmptyState(systemImage: "bell-ring", title: L("No follow-ups for this pet."))
                } else {
                    let openStates: Set<String> = ["open", "contacted", "snoozed", "scheduled"]
                    let open = items.filter { openStates.contains($0.status ?? "") }
                    let closed = items.filter { !openStates.contains($0.status ?? "") }
                    ClientsTabHeading(title: L("To do"))
                    if open.isEmpty { EmptyState(systemImage: "bell-ring", title: L("Nothing to do.")) } else { list(open, late: true) }
                    if !closed.isEmpty {
                        ClientsTabHeading(title: L("Done or closed"))
                        list(closed, late: false)
                    }
                }
            } else {
                LoadingState()
            }
        }
        .task {
            let page: Page<ClientsFollowUp>? = try? await API.get("/provider-follow-ups", query: ["limit": "50", "offset": "0", "status": "all", "providerClientPetId": chart.pet.id])
            items = page?.items ?? []
        }
    }

    private func list(_ entries: [ClientsFollowUp], late: Bool) -> some View {
        ClientsRowBox(items: entries) { item in
            let isLate = late && ClientsText.isPast(item.dueAt)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ClientsText.followUpTitle(item.title)).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text("\(ClientsText.followUpType(item.followUpType)) · \(item.assignedMember?.name ?? L("Unassigned"))").font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 8)
                Text("\(ClientsText.shortDay(item.dueAt)) · \(ClientsText.followUpStatus(item.status))").font(Theme.text(12, weight: .bold)).foregroundStyle(isLate ? Theme.destructive : Theme.inkSoft)
            }
        }
    }
}

// MARK: - Files

private struct ClientsChartFile: Decodable, Identifiable {
    let id: String
    let fileName: String?
    let url: String?
    let mimeType: String?
    let fileSizeBytes: Int?
    let createdAt: String?
    let source: String?
    let record: ClientsFileRecord?
    let visit: ClientsFileVisit?
}

private struct ClientsFileRecord: Decodable {
    let id: String?
    let type: String?
    let title: String?
    let at: String?
    let draft: Bool?
}

private struct ClientsFileVisit: Decodable {
    let id: String?
    let serviceLabel: String?
}

private struct ClientsFilesAnswer: Decodable {
    let items: [ClientsChartFile]
    let truncated: Bool?
}

/// Every file of the pet in one gallery (web `ChartFiles`): lab PDFs, x-rays and photos from records, the family's, and visit report photos.
struct ClientsChartFiles: View {
    let chart: ClientsChart
    @State private var answer: ClientsFilesAnswer?
    @State private var failed = false
    @State private var kind = "all"

    var body: some View {
        Group {
            if let answer {
                if answer.items.isEmpty {
                    EmptyState(systemImage: "file", title: L("No files yet"), message: L("Lab PDFs, x-rays and photos attached to records show up here."))
                } else {
                    let shown = answer.items.filter { file in
                        let image = isImage(file)
                        return kind == "all" ? true : kind == "images" ? image : !image
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                FilterChip(title: LF("All (%d)", answer.items.count), isSelected: kind == "all") { kind = "all" }
                                FilterChip(title: L("Photos"), isSelected: kind == "images") { kind = "images" }
                                FilterChip(title: L("Documents"), isSelected: kind == "documents") { kind = "documents" }
                            }
                            .padding(.vertical, 2)
                        }
                        .accessibilityLabel(L("Show"))
                        if shown.isEmpty {
                            EmptyState(systemImage: kind == "images" ? "image" : "file-text", title: L("Nothing of this kind."))
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)], spacing: 12) {
                            ForEach(shown) { file in tile(file) }
                        }
                        if answer.truncated == true { Text(L("Showing the newest 300 files.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                    }
                }
            } else if failed {
                ErrorState(message: L("The files could not be loaded.")) { await load() }
            } else {
                LoadingState()
            }
        }
        .task { await load() }
    }

    private func isImage(_ file: ClientsChartFile) -> Bool {
        file.source == "report" || ClientsFileKind.isImage(mimeType: file.mimeType, name: file.fileName)
    }

    private func caption(_ file: ClientsChartFile) -> String? {
        if file.source == "report" { return file.visit?.serviceLabel ?? L("Visit report") }
        guard let record = file.record else { return nil }
        return [record.type.map { ClientsText.recordType($0) }, record.title?.nonEmpty].compactMap { $0 }.joined(separator: " · ").nonEmpty
    }

    @ViewBuilder
    private func tile(_ file: ClientsChartFile) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous)
        let content = VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if isImage(file), let url = APIConfig.assetURL(file.url) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() } else { Theme.surfaceMuted }
                        }
                    } else {
                        Glyph(file.mimeType == "application/pdf" ? "file-text" : "file", size: 40)
                            .foregroundStyle(Theme.inkSoft)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.wash(Theme.aqua, 10))
                    }
                }
                .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName ?? L("File")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                if let caption = caption(file) { Text(caption).font(.brandText(10.9)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                HStack(spacing: 4) {
                    Glyph(file.source == "family" ? "house" : file.source == "report" ? "scissors" : "image", size: 12)
                    Text([ClientsText.shortDay(file.record?.at ?? file.createdAt), ClientsFileKind.size(file.fileSizeBytes), file.source == "family" ? L("Family") : nil, file.record?.draft == true ? L("To sign") : nil].compactMap { $0 }.joined(separator: " · "))
                        .lineLimit(1)
                }
                .font(.brandText(10.6)).foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Theme.surface)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.borderSoft, lineWidth: 1))
        if let url = APIConfig.assetURL(file.url) {
            Link(destination: url) { content }
                .accessibilityLabel(LF("Open %@", file.fileName ?? L("File")))
        } else {
            content
        }
    }

    private func load() async {
        do {
            answer = try await API.get("/provider-clients/\(chart.client.id)/pets/\(chart.pet.id)/files")
            failed = false
        } catch {
            failed = true
        }
    }
}

// MARK: - Billing

struct ClientsChartBilling: View {
    @EnvironmentObject private var workspace: Workspace
    let chart: ClientsChart
    @State private var bills: [ClientsInvoice]?
    @State private var route: ProviderRoute?
    @State private var collectingOnAccount = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let balance = chart.activity?.balance {
                let owes = (balance.client ?? 0) > 0
                let canCollect = owes && (workspace.can(.salesSell) || (workspace.can(.billingRecordPayment) && workspace.moneyLevel >= .charging))
                FlowLayout(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LF("%@ owes", chart.client.name).uppercased()).font(Theme.text(12, weight: .heavy)).tracking(1.4).foregroundStyle(Theme.inkSoft)
                        Text(Money.format(balance.client, currency: balance.currency)).font(.brandHeading(24, relativeTo: .title2)).foregroundStyle(Theme.inkStrong)
                        if let pet = balance.pet, pet > 0, pet != balance.client {
                            Text(LF("%@ of it for %@", Money.format(pet, currency: balance.currency), chart.pet.name)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    if canCollect {
                        // The Store's checkout collects a client's open bills; without the Store, the client's account takes the payment.
                        PMButton(L("Collect"), systemImage: "circle-dollar-sign") {
                            if workspace.can(.salesSell) { route = .storeCheckout(StorePrefill(clientId: chart.client.id, petId: chart.pet.id)) } else { collectingOnAccount = true }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clientsChartBox(Theme.wash(Theme.pink, 8))
            }
            if let bills {
                if bills.isEmpty {
                    EmptyState(systemImage: "circle-dollar-sign", title: L("No bills for this pet."))
                } else {
                    ClientsRowBox(items: bills) { invoice in
                        NavigationLink(value: ProviderRoute.invoice(invoice.id)) { row(invoice) }.buttonStyle(.plain)
                    }
                }
            } else {
                LoadingState()
            }
        }
        .task {
            let page: ClientsInvoicePage? = try? await API.get("/provider-invoices", query: ["limit": "50", "offset": "0", "providerClientId": chart.client.id, "providerClientPetId": chart.pet.id])
            bills = page?.items ?? []
        }
        .navigationDestination(item: $route) { RouteView(route: $0) }
        .navigationDestination(isPresented: $collectingOnAccount) { CashAccountScreen(clientId: chart.client.id) }
    }

    private func row(_ invoice: ClientsInvoice) -> some View {
        let toPay = (invoice.balanceDueAmount ?? 0) > 0 && invoice.status != "draft" && invoice.status != "canceled"
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.invoiceNumber ?? "—").font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                Text("\(ClientsText.shortDay(invoice.issuedAt ?? invoice.createdAt)) · \(ClientsText.invoiceStatus(invoice.status))").font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(invoice.totalAmount, currency: invoice.currency)).font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                if toPay {
                    Text(LF("%@ to pay", Money.format(invoice.balanceDueAmount, currency: invoice.currency))).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.destructive)
                }
            }
        }
    }
}

// MARK: - Details

struct ClientsChartDetails: View {
    let chart: ClientsChart
    let onEdit: (() -> Void)?
    @EnvironmentObject private var workspace: Workspace

    var body: some View {
        let pet = chart.pet
        let rows: [(String, String?)] = [
            (L("Species"), ClientsText.species(pet.species)),
            (L("Breed"), pet.breed),
            (L("Sex"), ClientsText.sex(pet.sex)),
            (L("Born"), pet.birthDate.map { ClientsText.shortDay($0) }),
            (L("Neutered"), pet.isNeutered.map { $0 ? L("Yes") : L("No") }),
            (L("Microchip"), pet.microchipNumber),
            (L("Weight"), ClientsText.weight(pet.weightGrams)),
            (L("Profile"), pet.linked == true ? L("Kept by the family in PawMiaw") : L("Kept by the clinic")),
        ]
        VStack(alignment: .leading, spacing: 16) {
            ClientsTabHeading(title: L("Pet details")) {
                if let onEdit { PMButton(pet.linked == true ? L("Edit clinic details") : L("Edit pet"), systemImage: "pencil", variant: .outline, size: .compact, action: onEdit) }
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { RowDivider() }
                    FactRow(label: row.0, value: row.1).padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .clientsChartBox()
            if let notes = pet.notes?.nonEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Notes").uppercased()).font(Theme.text(12, weight: .heavy)).tracking(1.4).foregroundStyle(Theme.inkSoft)
                    Text(notes).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clientsChartBox()
            }
            ClientsTabHeading(title: L("Care card"))
            SvcCareCard(petId: pet.id, petName: pet.name, canEdit: workspace.can(.petsEdit) || workspace.can(.appointmentsComplete))
            NavigationLink(value: ProviderRoute.client(chart.client.id)) {
                HStack(spacing: 4) {
                    Glyph("users-round", size: 16)
                    Text(LF("Open %@", chart.client.name))
                    Glyph("external-link", size: 12)
                }
                .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
            }
            .buttonStyle(.plain)
            AuditHistoryCard(entityType: "provider_client_pet", entityId: pet.id, olfatoPet: (id: pet.id, name: pet.name))
        }
    }
}

// MARK: - Weigh the pet

struct ClientsWeightSheet: View {
    let chart: ClientsChart
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var kilograms = ""
    @State private var day = Date()
    @State private var notes = ""
    @State private var shared = true
    @State private var saving = false

    private var grams: Int? { ClientsText.grams(fromKilograms: kilograms) }
    /// A big jump from the last weight asks for a second look.
    private var change: Double? {
        guard let grams, let last = chart.weights?.latestGrams, last > 0 else { return nil }
        let value = (Double(grams) - last) / last
        return abs(value) >= 0.1 ? value : nil
    }

    var body: some View {
        ProviderModal(title: LF("Weigh %@", chart.pet.name), subtitle: chart.weights?.latestGrams.map { LF("Last weight: %@", ClientsText.weight($0) ?? "—") } ?? L("No weight yet"), systemImage: "scale", accent: .aqua, isDirty: !kilograms.isEmpty || !notes.isEmpty, form: form, primaryTitle: saving ? L("Saving…") : L("Save weight"), isWorking: saving, primaryIcon: "scale") {
            save()
        } content: {
            PMTextField(L("Weight (kg)"), text: $kilograms, key: "weight", form: form, prompt: "12.4", hint: change.map { LF("That is %d%% from the last weight — check it’s right.", Int(($0 * 100).rounded())) }, keyboard: .decimalPad, required: true)
            DateTimeField(label: L("Day"), date: $day, zone: .current, max: Date(), components: [.date], key: "day", form: form)
            PMTextField(L("Note (optional)"), text: $notes, prompt: L("e.g. Fasting, before surgery"))
            if chart.pet.linked == true {
                ToggleRow(title: L("Show it to the family in PawMiaw"), isOn: $shared)
            }
        }
    }

    private func save() {
        guard form.check([("weight", grams == nil ? L("Write the weight in kilograms, e.g. 12.4") : nil)]), let grams else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                var body: [String: Any?] = ["weightGrams": grams, "recordedDate": DateText.dayKey(day, zone: .current), "notes": notes.nonEmpty]
                if chart.pet.linked == true { body["isSharedWithOwner"] = shared }
                let _: EmptyResponse = try await API.post("/provider-clients/\(chart.client.id)/pets/\(chart.pet.id)/weights", body: body)
                Toast.show(LF("%@ weighs %@.", chart.pet.name, ClientsText.weight(Double(grams)) ?? ""))
                announceDataChanged()
                await onSaved()
                dismiss()
            } catch {
                if (error as? APIError)?.code == "future_date" { _ = form.check([("day", L("The day can’t be in the future."))]) }
                else { form.apply(error, known: ["weightGrams": "weight", "recordedDate": "day"]) }
            }
        }
    }
}
