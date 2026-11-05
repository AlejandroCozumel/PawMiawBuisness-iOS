//
//  ClientsChartBrief.swift
//  PawMiawNegocios
//
//  The Olfato AI brief at the top of a pet's chart (web: patient-chart/
//  chart-ai-summary.tsx, summary-sources.tsx). The server writes it from the
//  pet's records; the app asks for it, asks again while it is being written
//  and shows what the server says: the warnings and dates straight from the
//  records, the brief with numbered sources, what was read and left out,
//  and a thumbs up or down. "Preguntar a Olfato" opens a chat about the pet.
//

import SwiftUI
import QuickLook

struct ClientsChartBrief: View {
    let chart: ClientsChart
    /// Weighing from the weight card the brief shows under its Weight tab.
    let canWeigh: Bool
    let reload: () async -> Void
    /// Opens the chart's Follow-ups tab (a follow-up source).
    let onFollowUps: () -> Void

    init(chart: ClientsChart, canWeigh: Bool = false, reload: @escaping () async -> Void = {}, onFollowUps: @escaping () -> Void) {
        self.chart = chart
        self.canWeigh = canWeigh
        self.reload = reload
        self.onFollowUps = onFollowUps
    }

    @EnvironmentObject private var workspace: Workspace
    @StateObject private var olfato = InboxOlfatoViewer()
    @State private var language = LocalizationManager.shared.currentLanguage == .spanish ? "es" : "en"
    @State private var brief: ClientsBrief?
    @State private var loadFailed = false
    @State private var refreshFailed = false
    @State private var refreshing = false
    @State private var switching = false
    @State private var kept: ClientsBrief?
    @State private var settings: ClientsBriefSettings?
    @State private var ensured: Set<String> = []
    @State private var recovered: Set<String> = []
    @State private var tab = "problems"
    @State private var tabChosen = false
    @State private var readOpen: Bool?
    @State private var techOpen = false
    @State private var openSource: ClientsBriefSourceTarget?
    @State private var ratingSent: String?
    @State private var ratingFailed = false
    @State private var downReasons: Set<String> = []
    @State private var downComment = ""
    @State private var rating: String?
    @State private var route: ProviderRoute?

    private var path: String { "/provider-clients/\(chart.client.id)/pets/\(chart.pet.id)" }

    // MARK: Derived state (chart-ai-summary.tsx §1.4)

    private var status: String { brief?.status ?? "" }
    private var off: Bool { status == "disabled" || status == "off" }
    private var paused: Bool { status == "queued" && brief?.errorCode == "daily_limit" }
    private var held: Bool { status == "queued" && brief?.errorCode == "visit_open" }
    private var empty: Bool { status == "empty" }
    private var queuedOrRunning: Bool { status == "queued" || status == "running" }
    private var busy: Bool { brief != nil && !off && !empty && !paused && (refreshing || (!held && queuedOrRunning)) }
    private var delayed: Bool { brief?.delayed == true && !paused && !held && queuedOrRunning }
    private var current: Bool { !loadFailed && status == "current" }
    private var writing: Bool { busy || switching }
    private var rewriting: Bool { !current && kept != nil && kept?.sourceRevision == brief?.sourceRevision && writing }
    private var shown: ClientsBriefText? { current ? brief?.summary : (rewriting ? kept?.summary : nil) }
    private var dimmed: Bool { shown != nil && (switching || rewriting || (busy && current)) }
    private var failed: Bool { status == "failed" }
    private var nothing: Bool { status == "nothing_reliable" }
    private var retryLater: Bool { failed && (DateText.parse(brief?.retryAt).map { $0 > Date() } ?? false) }
    private var generated: Bool { brief != nil && !off && !empty && status != "missing" }
    private var textless: Bool { brief != nil && (failed || nothing || status == "missing") }
    private var organized: Bool { generated && !textless }
    private var branded: Bool { brief != nil && !off }
    /// The brief source for what the screen shows (kept text while rewriting).
    private var source: ClientsBrief? { current ? brief : (rewriting ? kept : brief) }
    /// "Preguntar a Olfato": the chat's own rule (`InboxOlfatoViewer.showsEntry`) for someone who may chat.
    private var asksOlfato: Bool { workspace.can(.olfatoChat) && olfato.showsEntry }

    var body: some View {
        Card(padding: 16, spacing: 16) {
            header
            if branded { warnings; conflicts }
            facts
            if organized || writing { statusLine }
            if let message = statusMessage {
                Text(message)
                    .font(Theme.text(14)).foregroundStyle(failed || loadFailed || refreshFailed ? Theme.destructive : Theme.inkSoft)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.wash(Theme.blue, 6), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            }
            if (failed || nothing), let diagnostics = brief?.diagnostics { technical(diagnostics) }
            offLines
            if writing && shown == nil && !delayed && branded {
                // Nothing written to show yet: the shape of what is coming.
                VStack(alignment: .leading, spacing: 10) {
                    Capsule().fill(Theme.borderSoft.opacity(0.72)).frame(width: 128, height: 16)
                    ForEach(0..<3, id: \.self) { i in Capsule().fill(Theme.borderSoft.opacity(0.72)).frame(height: 14).frame(maxWidth: i == 2 ? 220 : .infinity) }
                }
                .padding(14)
                .clientsChartBox()
            }
            if let text = shown {
                briefBody(text).opacity(dimmed ? 0.55 : 1)
            } else if let pending = brief?.pending, !pending.isEmpty {
                // The chart's own due dates are facts: shown whatever the summary's state, also when it is off.
                pendingBlock(nil)
            }
            if organized {
                tabs(shown).opacity(dimmed ? 0.55 : 1)
            } else {
                // No generated text to organize: the chart's own facts, all of them, with no tabs.
                looseFacts
                ClientsChartSummaryView(chart: chart, canWeigh: canWeigh, reload: reload)
            }
            sourcesRow
            if generated || textless, let read = brief?.read { whatWasRead(read) }
            if shown != nil && current && !dimmed { ratingBlock }
            if organized {
                HStack(alignment: .top, spacing: 6) {
                    Image("OlfatoFace").resizable().scaledToFit().frame(width: 12, height: 12).padding(.top, 2).accessibilityHidden(true)
                    Text(shown != nil ? L("Written by AI from this pet’s records. Check the record before acting.") : L("A summary is saved and reused until the chart changes."))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .task(id: language) { await poll() }
        .task { if workspace.can(.olfatoChat) { await olfato.load() } }
        .sheet(item: $openSource) { target in
            ClientsBriefSourceSheet(sources: target.sources, index: target.index, petId: chart.pet.id, onFollowUps: onFollowUps) { next in
                Task { try? await Task.sleep(for: .milliseconds(350)); route = next }
            }
        }
        .navigationDestination(item: $route) { RouteView(route: $0) }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if branded {
                        // Olfato AI is on for this workspace: the block carries its name.
                        Image("OlfatoFace").resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
                        Text("Olfato AI").font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
                    } else {
                        // Off or not available: the pet's own facts, with no AI in them and no AI name on them.
                        IconBadge(icon: "book-open", accent: Theme.blue, size: 32, iconSize: 16, ink: .accent, washPercent: 12)
                        Text(L("Patient overview")).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
                    }
                }
                Text(branded ? L("AI brief of each pet’s record.") : L("A connected view of the pet’s history.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            if asksOlfato || (!(off || empty) && brief != nil) {
                FlowLayout(spacing: 8) {
                    if asksOlfato {
                        NavigationLink(value: ProviderRoute.olfatoPetChat(petId: chart.pet.id)) {
                            HStack(spacing: 8) {
                                Image("OlfatoFace").resizable().scaledToFit().frame(width: 20, height: 20).accessibilityHidden(true)
                                Text(L("Ask Olfato"))
                            }
                        }
                        .buttonStyle(.pm(.outline, size: .compact))
                    }
                    if !(off || empty) && brief != nil {
                        Menu {
                            Picker(L("Summary language"), selection: Binding(get: { language }, set: { switchLanguage($0) })) {
                                Text(L("English")).tag("en")
                                Text(L("Spanish")).tag("es")
                            }
                        } label: {
                            FilterMenuLabel(title: language == "es" ? L("Spanish") : L("English"))
                        }
                        .accessibilityLabel(L("Summary language"))
                        PMButton(failed || loadFailed ? L("Retry") : L("Refresh"), systemImage: "refresh-cw", variant: .outline, size: .header, isWorking: writing) { refresh() }
                            .disabled(writing || paused || retryLater)
                    }
                }
            }
            if retryLater, let at = brief?.retryAt {
                Text(LF("You can try again at %@.", DateText.time(at))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    // MARK: Warnings, conflicts, facts

    /// What the overview on screen does not say and nobody should miss (web `WarningStrip`).
    @ViewBuilder
    private var warnings: some View {
        let list = (brief?.warnings ?? []).filter { $0.covered != true }
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 8) {
                    Text(L("Warnings")).font(.brandHeading(16, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                    Text(L("From the pet’s records, not written by AI")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
                ForEach(list) { w in
                    HStack(alignment: .top, spacing: 8) {
                        Glyph(w.kind == "allergy" ? "triangle-alert" : w.kind == "problem" ? "stethoscope" : "shield-alert", size: 16)
                            .foregroundStyle(Theme.destructive).padding(.top, 2)
                        let prefix = ClientsBriefWords.warningPrefix(w)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            (Text(prefix.map { "\($0): " } ?? "").bold() + Text(ClientsBriefWords.warningText(w)).fontWeight(prefix == nil ? .bold : .regular))
                                .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                            citations(w.sourceId.map { [$0] } ?? [])
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clientsChartBox(Theme.wash(Theme.destructive, 8), border: Theme.destructive.opacity(0.35))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L("Warnings"))
        }
    }

    /// Two records that disagree, said as they are (web `ConflictNotice`).
    @ViewBuilder
    private var conflicts: some View {
        let list = brief?.conflicts ?? []
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Glyph("file-search", size: 16).foregroundStyle(Theme.inkStrong)
                    Text(L("Check the record")).font(.brandHeading(16, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                }
                Text(L("These records don’t agree. Nothing was changed: check which one is right.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                ForEach(list) { c in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Theme.mango).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(ClientsBriefWords.conflictText(c)).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                            citations(c.sourceIds ?? [])
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clientsChartBox(Theme.wash(Theme.mango, 12), border: Theme.mango.opacity(0.45))
        }
    }

    /// The facts everyone looks for first, in one slim row that wraps (web `FactStrip`).
    private var facts: some View {
        let weights = chart.weights
        let trend = (weights?.trend ?? []).sorted { $0.at < $1.at }
        let change: String? = {
            guard trend.count >= 2 else { return nil }
            let last = trend[trend.count - 1], before = trend[trend.count - 2]
            let delta = (last.grams - before.grams) / 1000
            return delta == 0 ? LF("no change since %@", ClientsText.shortDay(before.at)) : LF("%1$@ since %2$@", ClientsBriefWords.change(delta), ClientsText.shortDay(before.at))
        }()
        let medications = chart.summary?.medications?.count ?? 0
        let lab = chart.summary?.labs?.first
        return FlowLayout(spacing: 6) {
            factChip("scale", label: L("Latest weight"), value: ClientsText.weight(weights?.latestGrams), detail: [weights?.latestAt.map { ClientsText.shortDay($0) }, weights?.latestGrams == nil ? nil : change].compactMap { $0 }.joined(separator: " · "), missing: L("No weight"))
            factChip("pill", label: L("Medications"), value: medications == 0 ? nil : LP(medications, "%d medication", "%d medications"), detail: nil, missing: L("No medications"))
            factChip("flask-conical", label: L("Latest lab"), value: lab?.name?.nonEmpty, detail: lab?.at.map { ClientsText.shortDay($0) }, missing: L("No lab results"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Live information from the chart"))
    }

    /// One of the chart's own facts as a small pill (web `FactChip`); nothing recorded is said quietly, dashed.
    private func factChip(_ icon: String, label: String, value: String?, detail: String?, missing: String) -> some View {
        HStack(spacing: 6) {
            Glyph(icon, size: 14).foregroundStyle(value == nil ? Theme.inkSoft : Theme.blue)
            if let value {
                (Text(value).bold().foregroundColor(Theme.inkStrong) + Text(detail?.nonEmpty.map { " · \($0)" } ?? "").foregroundColor(Theme.inkSoft))
                    .lineLimit(1)
            } else {
                Text(missing).foregroundStyle(Theme.inkSoft)
            }
        }
        .font(Theme.text(12))
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(value == nil ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.wash(Theme.blue, 9)), in: Capsule())
        .overlay { if value == nil { Capsule().strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value ?? missing)")
    }

    // MARK: Status

    private var statusLine: some View {
        let partial = current && (brief?.partial == true || !ClientsBriefWords.exclusions(brief?.read).isEmpty)
        let text: String = {
            if writing { return brief?.generatedAt == nil && shown == nil ? L("Writing the brief…") : L("Updating…") }
            if current {
                if let at = brief?.generatedAt { return partial ? LF("Partial summary · updated %@", ClientsBriefWords.stamp(at)) : LF("Updated %@", ClientsBriefWords.stamp(at)) }
                return partial ? L("Partial summary") : L("Up to date")
            }
            if paused || held { return L("Waiting") }
            return brief?.generatedAt != nil ? L("Outdated") : L("Not yet generated")
        }()
        return VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 8) {
                HStack(spacing: 4) {
                    if writing {
                        ProgressView().controlSize(.mini).tint(Theme.blue)
                    } else {
                        Glyph(current ? "check" : "clock-3", size: 14).foregroundStyle(current ? Theme.blue : Theme.inkSoft)
                    }
                    Text(text).font(Theme.text(12, weight: .semibold))
                }
                if !writing, let generated = DateText.parse(brief?.generatedAt), let covered = DateText.parse(brief?.coveredThrough), abs(generated.timeIntervalSince(covered)) > 60 {
                    Text(LF("Includes information through %@", ClientsBriefWords.stamp(brief?.coveredThrough))).font(Theme.text(12)).opacity(0.8)
                }
            }
            .foregroundStyle(Theme.inkSoft)
            if writing {
                Capsule().fill(Theme.wash(Theme.blue, 16)).frame(height: 2)
                    .overlay(Capsule().fill(Theme.blue).opacity(0.7))
            }
        }
    }

    private var statusMessage: String? {
        if off {
            return status == "disabled" ? L("Olfato AI isn’t available yet. The pet’s records are below.") : nil
        }
        if loadFailed { return L("We could not load the summary. Try again.") }
        guard let brief else { return nil }
        if empty { return L("Nothing to summarize yet.") }
        if paused { return L("Today’s limit of Olfato AI summaries has been reached. This one will be written automatically once there is room again.") }
        if failed { return ClientsBriefWords.failure(brief.errorCode, time: retryLater ? DateText.time(brief.retryAt) : nil) }
        if nothing {
            return brief.nothingReason == "unverified_documents" ? L("There is an attached document that hasn’t been verified; open it in Files.") : L("Olfato AI found nothing in this chart it could say reliably, so no summary is shown. The pet’s records are below.")
        }
        if refreshFailed { return L("We could not update the summary. Try again.") }
        if held { return L("This chart is being updated. The summary will be rewritten a few minutes after the last change. Press Refresh to rewrite it now.") }
        if delayed { return L("Taking longer than usual. The pet’s records are below.") }
        if (brief.coverage?.pending ?? 0) > 0 && queuedOrRunning { return L("Reading the attached documents before writing the summary…") }
        if status == "queued", let code = brief.errorCode, code != "documents_pending" { return L("That didn’t work the first time. Trying again shortly…") }
        if current { return nil }
        if brief.generatedAt != nil { return rewriting ? nil : L("The chart changed. A new summary is being prepared.") }
        return shown == nil ? L("Preparing the first summary…") : nil
    }

    @ViewBuilder
    private var offLines: some View {
        if status == "off" {
            let outdated = settings?.noticeOutdated == true
            let canEnable = brief?.canEnable == true
            if outdated && canEnable {
                // On, but waiting for the new notice: who can confirm it is taken to it.
                offNote(L("Olfato AI needs the new notice to be accepted."), link: L("Read the notice"))
            } else if outdated {
                // Everyone else: one quiet line, nothing to do.
                Text(L("Olfato AI is paused until the business accepts its new notice.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            } else if canEnable {
                // Only someone who can change the setting is told about it.
                offNote(L("Olfato AI can write an AI brief of each pet’s record. It is off for this business."), link: L("Turn on in Settings"))
            }
        }
    }

    private func offNote(_ text: String, link: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image("OlfatoFace").resizable().scaledToFit().frame(width: 16, height: 16).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                NavigationLink(value: ProviderRoute.section(.settings)) {
                    Text(link).font(Theme.text(14, weight: .bold)).underline().foregroundStyle(Theme.blue)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.wash(Theme.blue, 6), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
    }

    /// A failed summary's codes and counts, for support (web `TechnicalDetails`).
    private func technical(_ d: ClientsBriefDiagnostics) -> some View {
        let text = [
            "Olfato AI · \(d.errorCode ?? "—")",
            d.runId.map { "run: \($0)" },
            "version: \(d.version ?? "—") · model: \(d.model ?? "—")",
            (d.inputTokens != nil || d.outputTokens != nil) ? "tokens: in \(d.inputTokens ?? 0) · out \(d.outputTokens ?? 0)" : nil,
            d.attempts.map { "attempts: \($0)" },
        ].compactMap { $0 }.joined(separator: "\n")
        return VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.2)) { techOpen.toggle() } } label: {
                HStack(spacing: 6) {
                    Glyph("chevron-down", size: 14).rotationEffect(.degrees(techOpen ? 180 : 0))
                    Text(L("Technical details")).font(Theme.text(12, weight: .semibold))
                }
                .foregroundStyle(Theme.inkSoft)
            }
            .buttonStyle(.plain)
            if techOpen {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("For support. It has codes and counts only, nothing from the pet’s records.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    Text(text).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkStrong).textSelection(.enabled)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                    PMButton(L("Copy"), variant: .outline, size: .header) { clientsCopy(text, done: L("Copied")) }
                }
                .padding(.leading, 20)
            }
        }
    }

    // MARK: The brief

    @ViewBuilder
    private func briefBody(_ text: ClientsBriefText) -> some View {
        let overview = text.items("overview")
        let recent = text.items("recent")
        let hasPending = !(source?.pending ?? []).isEmpty || !text.items("pending").isEmpty
        if !overview.isEmpty || !recent.isEmpty || hasPending {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                if !overview.isEmpty {
                    stacked("clipboard-list", L("Overview")) { bullets(overview) }
                }
                if !recent.isEmpty || hasPending {
                    VStack(alignment: .leading, spacing: 12) {
                        if !recent.isEmpty {
                            stacked("history", source?.recent?.basis == "visit" ? L("Since the last visit") : L("Recent changes"), aside: source?.recent?.since.map { since in
                                source?.recent?.basis == "visit" ? LF("Since %@", ClientsText.shortDay(since)) : LF("Last 90 days · since %@", ClientsText.shortDay(since))
                            }) { bullets(recent) }
                        }
                        // The chart's own due dates are facts: shown whatever the summary's state.
                        if hasPending { pendingBlock(text) }
                    }
                }
            }
        }
    }

    /// A block that is always in view (web `Stacked`): a 24 disc, the title in Fredoka 16, an aside, its content.
    private func stacked<Content: View>(_ icon: String, _ title: String, aside: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 8) {
                HStack(spacing: 8) {
                    Glyph(icon, size: 14).foregroundStyle(Theme.blue)
                        .frame(width: 24, height: 24)
                        .background(Theme.wash(Theme.blue, 12), in: Circle())
                    Text(title).font(.brandHeading(16, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                }
                if let aside { Chip(text: aside, tone: .muted) }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clientsChartBox()
    }

    /// What is due: the chart's own dates first, then what the summary found recommended in the notes (web `PendingBlock`).
    private func pendingBlock(_ text: ClientsBriefText?) -> some View {
        let facts = source?.pending ?? []
        let noted = text?.items("pending") ?? []
        return stacked("calendar-clock", L("Pending@brief")) {
            if !facts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(facts.enumerated()), id: \.offset) { _, item in
                        let due = ClientsBriefWords.pendingDue(item.dueDay, today: source?.today)
                        HStack(alignment: .center, spacing: 8) {
                            (Text(item.title ?? "—").font(Theme.text(14, weight: .bold)).foregroundColor(Theme.inkStrong)
                             + Text("  " + [ClientsBriefWords.pendingKind(item.kind), item.source == "family" ? L("From the family") : nil, item.dueDay.map { ClientsText.shortDay($0) }].compactMap { $0 }.joined(separator: " · "))
                                .font(Theme.text(12)).foregroundColor(Theme.inkSoft))
                            Spacer(minLength: 6)
                            if due.late {
                                StatusChip(text: due.text, state: .problem)
                            } else if due.today {
                                StatusChip(text: due.text, state: .waiting)
                            } else {
                                Chip(text: due.text, tone: .muted)
                            }
                        }
                    }
                    if let more = source?.pendingMore, more > 0 { Text(LF("and %d more@brief", more)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                }
            }
            if !noted.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !facts.isEmpty { RowDivider().padding(.bottom, 4) }
                    Text(L("Noted in the records").uppercased()).font(Theme.text(12, weight: .bold)).tracking(0.7).foregroundStyle(Theme.inkSoft)
                    bullets(noted)
                }
            }
        }
    }

    /// A section's bullets, each ending in the numbered chips of the records it cites (web `Bullets`).
    private func bullets(_ items: [ClientsBriefItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Theme.blue).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ClientsBriefWords.datesInText(item.text)).font(Theme.text(14)).lineSpacing(3).foregroundStyle(Theme.inkStrong)
                        if item.unverified == true || !(item.sourceIds ?? []).isEmpty {
                            FlowLayout(spacing: 4) {
                                if item.unverified == true {
                                    // Set by the server, never by the AI: the line rests on a document nobody has verified.
                                    Chip(text: L("Unverified document"), tone: .warn, icon: "file-exclamation-point")
                                        .accessibilityHint(L("From an attached document nobody has verified. Check the original."))
                                }
                                citations(item.sourceIds ?? [])
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Tabs

    /// How many of the chart's own facts a tab has to show (web `liveCount`).
    private func liveCount(_ key: String) -> Int {
        switch key {
        case "problems": chart.summary?.problems?.count ?? 0
        case "medications": chart.summary?.medications?.count ?? 0
        case "labs": chart.summary?.labs?.count ?? 0
        case "weight": chart.weights?.latestGrams == nil ? 0 : 1
        case "milestones": chart.summary?.vaccines?.count ?? 0
        default: 0
        }
    }

    /// The chart's own facts shown under a tab (the vaccine list sits with the milestones).
    private func liveSection(_ key: String) -> String? {
        switch key {
        case "problems": "problems"
        case "medications": "medications"
        case "labs": "labs"
        case "weight": "weight"
        case "milestones": "history"
        default: nil
        }
    }

    private func hasContent(_ key: String, _ text: ClientsBriefText?) -> Bool {
        !(text?.items(key) ?? []).isEmpty || liveCount(key) > 0
            || (key == "weight" && source?.weights?.latest != nil)
            || (key == "medications" && !(uncoveredMeds.isEmpty && uncoveredTreatment.isEmpty))
            || (key == "care" && !uncoveredCare.isEmpty)
    }

    private var uncoveredMeds: [ClientsBriefMedication] { (source?.currentMedications ?? []).filter { $0.covered != true && $0.origin != "record" } }
    private var uncoveredTreatment: [ClientsBriefMedication] { (source?.recentTreatment ?? []).filter { $0.covered != true } }
    private var uncoveredCare: [ClientsBriefCareFact] { (source?.careFacts ?? []).filter { $0.covered != true } }

    private func tabs(_ text: ClientsBriefText?) -> some View {
        // Care & handling is a tab only when a groomer or the care card has something to say.
        let keys = ClientsBriefWords.tabs.filter { $0 != "care" || !(text?.items("care") ?? []).isEmpty || !uncoveredCare.isEmpty }
        let active = tabChosen && keys.contains(tab) ? tab : (keys.first { hasContent($0, text) } ?? "problems")
        let items = text?.items(active) ?? []
        let live = liveSection(active)
        let recorded = active == "weight" && source?.weights?.latest != nil
        let medicines = active == "medications" && !(uncoveredMeds.isEmpty && uncoveredTreatment.isEmpty)
        let care = active == "care" && !uncoveredCare.isEmpty
        return VStack(alignment: .leading, spacing: 16) {
            ClientsLineTabs(
                options: keys.map { (value: $0, title: ClientsBriefWords.tab($0), dimmed: !hasContent($0, text)) },
                selection: Binding(get: { active }, set: { tab = $0; tabChosen = true }),
                label: L("More from the summary")
            )
            VStack(alignment: .leading, spacing: 16) {
                if recorded { weightFacts }
                if !items.isEmpty { bullets(items) }
                if active == "medications" { medicationFacts }
                if active == "care" { careFacts }
                // The chart's own card says by itself when it is empty; with nothing at all, one quiet line.
                if let live, liveCount(active) > 0 {
                    ClientsChartSummaryView(chart: chart, canWeigh: canWeigh, section: live, reload: reload)
                } else if items.isEmpty && !recorded && !medicines && !care {
                    Text(L("Nothing on record here.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    /// The latest two recorded weights and how they differ: from the weight logs, not from the AI (web `WeightFacts`).
    @ViewBuilder
    private var weightFacts: some View {
        if let weights = source?.weights, let latest = weights.latest {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(latest.day.map { LF("Latest: %1$@ on %2$@", ClientsBriefWords.kg(latest.kg), ClientsText.shortDay($0)) } ?? LF("Latest: %@", ClientsBriefWords.kg(latest.kg)))
                        .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    citations([latest.sourceId].compactMap { $0 })
                }
                if let previous = weights.previous {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(previous.day.map { LF("Before: %1$@ on %2$@", ClientsBriefWords.kg(previous.kg), ClientsText.shortDay($0)) } ?? LF("Before: %@", ClientsBriefWords.kg(previous.kg)))
                            .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                        citations([previous.sourceId].compactMap { $0 })
                        if let change = weights.changeKg {
                            Text("· " + (change == 0 ? L("No change") : LF("Change: %@", ClientsBriefWords.change(change)))).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    if weights.outlier != nil {
                        HStack(alignment: .top, spacing: 8) {
                            Glyph("triangle-alert", size: 16).foregroundStyle(Theme.inkStrong).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LF("%1$@ → %2$@: check this entry", ClientsBriefWords.kg(previous.kg), ClientsBriefWords.kg(latest.kg))).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                                Text(L("The newest weight is far from the one before. It is shown as recorded; nothing was corrected.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.wash(Theme.mango, 16), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var medicationFacts: some View {
        if !uncoveredMeds.isEmpty { medicationList(L("Medications on record"), uncoveredMeds) }
        if !uncoveredTreatment.isEmpty { medicationList(L("Recent treatment on record"), uncoveredTreatment) }
    }

    private func factHeading(_ title: String) -> some View {
        FlowLayout(spacing: 8) {
            Text(title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
            Text(L("From the pet’s records, not written by AI")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
    }

    private func medicationList(_ title: String, _ list: [ClientsBriefMedication]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            factHeading(title)
            ForEach(list) { m in
                let line = ClientsBriefWords.medicationLine(m)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        (Text(line.title).bold() + Text(line.detail.isEmpty ? "" : " · \(line.detail)")).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                        citations(m.sourceId.map { [$0] } ?? [])
                    }
                    Text(ClientsBriefWords.medicationSource(m) + (m.said?.nonEmpty.map { " · “\($0)”" } ?? "")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    @ViewBuilder
    private var careFacts: some View {
        if !uncoveredCare.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                factHeading(L("From the care card"))
                ForEach(uncoveredCare) { fact in
                    let value = fact.key == "rebook_every_weeks" ? ((fact.weeks ?? 0) == 1 ? L("every week") : LF("every %d weeks", fact.weeks ?? 0)) : (fact.value ?? "")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        (Text(ClientsBriefWords.careLabel(fact.key)).bold() + Text(": \(value)")).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                        citations(fact.sourceId.map { [$0] } ?? [])
                    }
                }
            }
        }
    }

    /// Without the brief's tabs: the facts straight from the records that still matter.
    @ViewBuilder
    private var looseFacts: some View {
        if source?.weights?.outlier != nil { weightFacts }
        medicationFacts
    }

    // MARK: Sources

    /// Every cited source, numbered in reading order.
    private var numbered: [ClientsBriefSource] {
        let all = source?.sources ?? []
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var order: [String] = []
        let add = { (ids: [String]) in for id in ids where byId[id] != nil && !order.contains(id) { order.append(id) } }
        for w in (source?.warnings ?? []) where w.covered != true { add(w.sourceId.map { [$0] } ?? []) }
        for c in source?.conflicts ?? [] { add(c.sourceIds ?? []) }
        let text = shown
        for key in ["overview", "recent", "pending"] + ClientsBriefWords.tabs {
            if key == "weight" { add([source?.weights?.latest?.sourceId, source?.weights?.previous?.sourceId].compactMap { $0 }) }
            for item in text?.items(key) ?? [] { add(item.sourceIds ?? []) }
            if key == "medications" { add((uncoveredMeds + uncoveredTreatment).compactMap(\.sourceId)) }
            if key == "care" { add(uncoveredCare.compactMap(\.sourceId)) }
        }
        return order.compactMap { byId[$0] }
    }

    /// A citation's number on its tint (web `SourceChip`'s number): 18 tall, 10.4 extrabold.
    private func sourceNumber(_ number: Int) -> some View {
        Text("\(number)").font(.brandText(10.4, weight: .heavy)).monospacedDigit().foregroundStyle(Theme.inkStrong)
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18)
            .background(Theme.wash(Theme.blue, 16), in: Capsule())
    }

    @ViewBuilder
    private func citations(_ ids: [String]) -> some View {
        let list = numbered
        let shownIds = ids.filter { id in list.contains { $0.id == id } }
        if !shownIds.isEmpty {
            HStack(spacing: 1) {
                ForEach(shownIds, id: \.self) { id in
                    if let index = list.firstIndex(where: { $0.id == id }) {
                        Button { openSource = ClientsBriefSourceTarget(sources: list, index: index) } label: {
                            sourceNumber(index + 1).frame(minWidth: 24, minHeight: 24).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LF("Source %1$d: %2$@", index + 1, ClientsBriefWords.sourceTitle(list[index])))
                    }
                }
            }
        }
    }

    /// Every source the brief cites, once, in the order of their numbers (web `SourcesRow`).
    @ViewBuilder
    private var sourcesRow: some View {
        let list = numbered
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                RowDivider().padding(.bottom, 4)
                Text(L("Sources").uppercased()).font(Theme.text(12, weight: .bold)).tracking(0.7).foregroundStyle(Theme.inkSoft)
                FlowLayout(spacing: 6) {
                    ForEach(Array(list.enumerated()), id: \.offset) { index, item in
                        Button { openSource = ClientsBriefSourceTarget(sources: list, index: index) } label: {
                            HStack(spacing: 6) {
                                sourceNumber(index + 1)
                                Text([ClientsBriefWords.sourceTitle(item), item.page.map { LF("Page %d", $0) }, (item.date ?? item.at).map { ClientsText.shortDay($0) }].compactMap { $0 }.joined(separator: " · "))
                                    .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            }
                            .padding(.leading, 6).padding(.trailing, 12)
                            .frame(minHeight: 32)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LF("Source %1$d: %2$@", index + 1, ClientsBriefWords.sourceTitle(item)))
                    }
                }
            }
        }
    }

    // MARK: What was read, rating

    /// What the summary was written from, in one line, and what was left out when opened (web `WhatWasRead`).
    private func whatWasRead(_ read: ClientsBriefRead) -> some View {
        let gaps = !ClientsBriefWords.exclusions(read).isEmpty
        let exclusions = (current && brief?.partial == true ? [L("Some lines were left out because we couldn’t check them against the record.")] : []) + ClientsBriefWords.exclusions(read)
        let isOpen = readOpen ?? gaps
        return VStack(alignment: .leading, spacing: 8) {
            RowDivider().padding(.bottom, 4)
            Button { withAnimation(.easeOut(duration: 0.2)) { readOpen = !isOpen } } label: {
                HStack(alignment: .top, spacing: 6) {
                    Glyph("chevron-down", size: 14).rotationEffect(.degrees(isOpen ? 180 : 0)).padding(.top, 1)
                    (Text("\(L("What was read")): ").fontWeight(.semibold) + Text(ClientsBriefWords.readLine(read))
                     + Text(gaps ? " · \(L("Some things were left out"))" : "").fontWeight(.semibold).foregroundColor(Theme.inkStrong))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
            .buttonStyle(.plain)
            if isOpen {
                VStack(alignment: .leading, spacing: 4) {
                    if exclusions.isEmpty {
                        Text(L("Nothing was left out.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    } else {
                        ForEach(exclusions, id: \.self) { Text("• \($0)").font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                    }
                    let documents = brief?.documents ?? []
                    if !documents.isEmpty {
                        ForEach(documents) { Text("\($0.title ?? "—") · \(ClientsBriefWords.documentStatus($0.status))").font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                            .padding(.top, 4)
                    }
                }
                .padding(.leading, 20)
                .accessibilityLabel(L("What was left out"))
            }
        }
    }

    /// Thumbs up or down on the summary on screen; a thumbs down can say why (web `SummaryRatingRow`).
    private var ratingBlock: some View {
        let chosen = rating ?? brief?.rating?.rating
        return VStack(alignment: .leading, spacing: 12) {
            RowDivider()
            FlowLayout(spacing: 8) {
                Text(L("Was this summary useful?")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong).frame(minHeight: 36)
                IconCircleButton(systemImage: "thumbs-up", label: L("Yes, it was useful"), tint: chosen == "up" ? Theme.blue : Theme.inkSoft) { rate("up") }
                IconCircleButton(systemImage: "thumbs-down", label: L("No, it wasn’t"), tint: chosen == "down" ? Theme.blue : Theme.inkSoft) { rate("down") }
                if let ratingSent { Text(ratingSent).font(Theme.text(12)).foregroundStyle(ratingFailed ? Theme.destructive : Theme.inkSoft).frame(minHeight: 36) }
            }
            if chosen == "down" {
                FlowLayout(spacing: 6) {
                    ForEach([("missing", L("Something important is missing")), ("wrong", L("Something is wrong")), ("too_long", L("Too long")), ("not_relevant", L("Not relevant"))], id: \.0) { reason in
                        FilterChip(title: reason.1, isSelected: downReasons.contains(reason.0)) {
                            if downReasons.contains(reason.0) { downReasons.remove(reason.0) } else { downReasons.insert(reason.0) }
                        }
                    }
                }
                PMTextField(L("What was missing or wrong?"), text: $downComment, prompt: L("What was missing or wrong?"), hint: L("Optional. It stays in PawMiaw and is never sent to the AI."), optional: true, multiline: true)
                PMButton(L("Send"), variant: .outline, size: .compact) { rate("down") }
            }
        }
    }

    // MARK: Loading

    private func poll() async {
        while !Task.isCancelled {
            await load()
            let seconds: Double = {
                if status == "disabled" { return 0 }
                if status == "off" { return 300 }
                if !queuedOrRunning { return 30 }
                if paused { return 60 }
                if held || brief?.delayed == true { return 30 }
                return 3
            }()
            if seconds == 0 { return }
            try? await Task.sleep(for: .seconds(seconds))
        }
    }

    private func load() async {
        guard chart.viewer?.seesRecords == true else { return }
        do {
            let answer: ClientsBrief = try await API.get("\(path)/summary", query: ["language": language])
            apply(answer)
            loadFailed = false
            switching = false
            if answer.status == "off", settings == nil {
                settings = try? await API.get("/provider-patients/ai-summary-settings")
            }
            await ensure(answer)
        } catch is CancellationError {
        } catch {
            loadFailed = true
            switching = false
        }
    }

    private func apply(_ answer: ClientsBrief) {
        brief = answer
        if answer.status == "current" { kept = answer }
    }

    /// The first read of a revision asks the server to write it (once); a brief gone missing is asked for once more.
    private func ensure(_ answer: ClientsBrief) async {
        guard let revision = answer.sourceRevision, !["disabled", "off", "failed"].contains(answer.status) else { return }
        let key = "\(language):\(revision)"
        if !ensured.contains(key) {
            ensured.insert(key)
            await generate(retry: false)
        } else if answer.status == "missing", !recovered.contains(key) {
            recovered.insert(key)
            await generate(retry: false)
        }
    }

    private func generate(retry: Bool) async {
        do {
            let answer: ClientsBrief = try await API.post("\(path)/generate-summary", query: ["language": language, "retry": retry ? "true" : "false"])
            apply(answer)
            refreshFailed = false
        } catch is CancellationError {
        } catch {
            if retry { refreshFailed = true }
        }
    }

    private func refresh() {
        if loadFailed { Task { await load() }; return }
        refreshing = true
        Task {
            defer { refreshing = false }
            await generate(retry: true)
        }
    }

    private func switchLanguage(_ next: String) {
        guard next != language else { return }
        switching = true
        kept = nil
        rating = nil
        ratingSent = nil
        language = next
    }

    private func rate(_ value: String) {
        guard let revision = brief?.revision else { return }
        rating = value
        Task {
            do {
                var body: [String: Any?] = ["sourceRevision": revision, "rating": value]
                if value == "down" {
                    body["reasons"] = Array(downReasons).sorted()
                    body["comment"] = downComment.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty.map { String($0.prefix(500)) }
                }
                let _: EmptyResponse = try await API.post("\(path)/summary-rating", body: body, query: ["language": language])
                ratingFailed = false
                ratingSent = L("Thanks. Your rating was saved.")
            } catch {
                ratingFailed = true
                ratingSent = L("We couldn’t save your rating. Try again.")
            }
        }
    }
}

/// The brief's sections as line tabs (web `TabsList variant="line"`): 14 medium words, the chosen one
/// in ink with a 2 pt rule under it; a tab with nothing on record is dimmed, still a tab like the others.
/// (No kit piece draws line tabs; built from Theme tokens.)
struct ClientsLineTabs: View {
    let options: [(value: String, title: String, dimmed: Bool)]
    @Binding var selection: String
    var label: String = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(options, id: \.value) { option in
                    let chosen = option.value == selection
                    Button { withAnimation(.easeOut(duration: 0.15)) { selection = option.value } } label: {
                        Text(option.title)
                            .font(Theme.text(14, weight: .medium))
                            .foregroundStyle(chosen ? Theme.inkStrong : Theme.inkStrong.opacity(0.6))
                            .padding(.horizontal, 6)
                            .frame(height: 32)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Theme.inkStrong).frame(height: 2).opacity(chosen ? 1 : 0).offset(y: 4)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(option.dimmed ? 0.55 : 1)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                    .accessibilityHint(option.dimmed ? L("Nothing on record") : "")
                }
            }
            .padding(.bottom, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

// MARK: - A source, opened

struct ClientsBriefSourceTarget: Identifiable {
    let id = UUID()
    let sources: [ClientsBriefSource]
    let index: Int
}

private struct ClientsBriefSourceSheet: View {
    let sources: [ClientsBriefSource]
    let petId: String
    let onFollowUps: () -> Void
    /// Opens a visit, a record or a hospitalization from the page under the sheet.
    let onOpen: (ProviderRoute) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var original: URL?
    @State private var opening = false

    init(sources: [ClientsBriefSource], index: Int, petId: String, onFollowUps: @escaping () -> Void, onOpen: @escaping (ProviderRoute) -> Void) {
        self.sources = sources
        self.petId = petId
        self.onFollowUps = onFollowUps
        self.onOpen = onOpen
        _index = State(initialValue: index)
    }

    var body: some View {
        let source = sources[min(index, sources.count - 1)]
        let title = ClientsBriefWords.sourceTitle(source)
        let kind = ClientsBriefWords.sourceKind(source.kind)
        let fields = ClientsBriefFields.rows(source.data, title: source.title)
        ProviderModal(title: title, subtitle: [LF("Source %d", index + 1), (source.date ?? source.at).map { ClientsText.shortDay($0) }, source.page.map { LF("Page %d", $0) }].compactMap { $0 }.joined(separator: " · "), systemImage: "file-search", accent: .aqua, cancelTitle: L("Close")) {
            FlowLayout(spacing: 6) {
                if let kind, kind != title { Chip(text: kind, tone: .info) }
                if source.kind == "document" || source.data?["unverified"]?.bool == true { Chip(text: L("Unverified document"), tone: .warn, icon: "file-exclamation-point") }
            }
            if source.kind == "document" {
                NoticeCard(tone: .warning, title: L("Document text is automatically extracted and unverified. Check the original before using doses or lab values."))
            }
            if let lead = ClientsBriefFields.lead(source.data) { Text(lead).font(Theme.bodyFont).foregroundStyle(Theme.inkStrong).textSelection(.enabled) }
            if fields.isEmpty && ClientsBriefFields.lead(source.data) == nil {
                Text(L("This source has no more details.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .topLeading)], alignment: .leading, spacing: 8) {
                ForEach(Array(fields.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(row.label.uppercased()).font(.brandText(10.9, weight: .heavy)).tracking(1.1).foregroundStyle(Theme.inkSoft)
                            if row.staffOnly { Chip(text: L("Staff only@brief"), tone: .warn, icon: "lock") }
                        }
                        Text(row.value).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    }
                }
            }
            HStack(spacing: 10) {
                if let attachment = source.attachmentId {
                    PMButton(L("Open original"), systemImage: "file", variant: .outline, size: .compact, isWorking: opening) { openOriginal(attachment) }
                }
                link(source)
            }
            if sources.count > 1 {
                HStack {
                    IconCircleButton(systemImage: "chevron-left", label: L("Previous source")) { index = max(0, index - 1) }.disabled(index == 0)
                    Spacer()
                    Text(LF("%1$d of %2$d", index + 1, sources.count)).font(Theme.text(13, weight: .bold)).foregroundStyle(Theme.inkSoft)
                    Spacer()
                    IconCircleButton(systemImage: "chevron-right", label: L("Next source")) { index = min(sources.count - 1, index + 1) }.disabled(index >= sources.count - 1)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L("Sources"))
            }
        }
        .presentationDetents([.medium, .large])
        .quickLookPreview($original)
    }

    @ViewBuilder
    private func link(_ source: ClientsBriefSource) -> some View {
        let parts = source.id.split(separator: ":", maxSplits: 1).map(String.init)
        let kind = parts.first ?? "", id = parts.count > 1 ? parts[1] : ""
        switch kind {
        case "visit": PMButton(L("Open record@brief"), variant: .outline, size: .compact) { dismiss(); onOpen(.appointment(id)) }
        case "clinic_record": PMButton(L("Open record@brief"), variant: .outline, size: .compact) { dismiss(); onOpen(.record(id)) }
        case "hospitalization": PMButton(L("Open record@brief"), variant: .outline, size: .compact) { dismiss(); onOpen(.hospitalization(id)) }
        case "follow_up": PMButton(L("Open follow-ups"), variant: .outline, size: .compact) { dismiss(); onFollowUps() }
        default: EmptyView()
        }
    }

    private func openOriginal(_ attachmentId: String) {
        opening = true
        Task {
            defer { opening = false }
            do {
                let data = try await API.data("GET", "/provider-client-pets/\(petId)/chart-attachments/\(attachmentId)", query: [:], body: nil)
                let ext: String = data.starts(with: [0x25, 0x50, 0x44, 0x46]) ? "pdf" : data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "png" : data.starts(with: [0xFF, 0xD8]) ? "jpg" : "bin"
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("chart-\(attachmentId).\(ext)")
                try data.write(to: file, options: [.atomic, .completeFileProtection])
                original = file
            } catch {
                Toast.error(error, fallback: L("Something went wrong. Try again."))
            }
        }
    }
}

/// A source's fields as label and value (summary-sources.tsx `sourceFields`).
enum ClientsBriefFields {
    struct Row { let label: String; let value: String; let staffOnly: Bool }

    private static let leadKeys = ["summary", "details", "notes", "note", "text", "message"]
    private static let internalKeys: Set<String> = ["internal_notes", "internalNote", "internal_note"]

    static func lead(_ data: JSONValue?) -> String? {
        guard let object = data?.object else { return nil }
        for key in leadKeys { if let text = object[key]?.string?.nonEmpty { return text } }
        return nil
    }

    static func rows(_ data: JSONValue?, title: String?) -> [Row] {
        guard let object = data?.object else { return [] }
        let leadKey = leadKeys.first { object[$0]?.string?.nonEmpty != nil }
        var rows: [Row] = []
        for key in object.keys.sorted(by: order) where key != leadKey {
            collect(key: key, value: object[key] ?? .null, parent: nil, into: &rows, title: title)
        }
        // Two rows with one label read as one.
        var merged: [Row] = []
        for row in rows {
            if let i = merged.firstIndex(where: { $0.label == row.label }) {
                merged[i] = Row(label: row.label, value: "\(merged[i].value) · \(row.value)", staffOnly: merged[i].staffOnly || row.staffOnly)
            } else { merged.append(row) }
        }
        return merged
    }

    private static func order(_ a: String, _ b: String) -> Bool {
        let first = ["name", "title", "status", "recordType", "medication_name", "medicine_name", "vaccine_name", "test_name", "condition", "trigger", "diagnosis"]
        let ia = first.firstIndex(of: a) ?? Int.max, ib = first.firstIndex(of: b) ?? Int.max
        return ia != ib ? ia < ib : a < b
    }

    private static func hidden(_ key: String) -> Bool { key == "id" || key.hasSuffix("_id") || key.hasSuffix("Id") || key == "extraction" || key == "unverified" }

    private static func collect(key: String, value: JSONValue, parent: String?, into rows: inout [Row], title: String?) {
        guard !hidden(key) else { return }
        let label = Self.label(key, parent: parent)
        switch value {
        case .null: return
        case .object(let child):
            for childKey in child.keys.sorted(by: order) { collect(key: childKey, value: child[childKey] ?? .null, parent: key, into: &rows, title: title) }
        case .array(let items):
            if items.allSatisfy({ $0.object == nil }) {
                let text = items.compactMap { item in item.string.map { optionValue(key, $0) } }.joined(separator: ", ")
                if !text.isEmpty { rows.append(Row(label: label, value: text, staffOnly: internalKeys.contains(key))) }
            } else {
                for (i, item) in items.enumerated() {
                    guard let child = item.object else { continue }
                    var inner: [Row] = []
                    for childKey in child.keys.sorted(by: order) { collect(key: childKey, value: child[childKey] ?? .null, parent: key, into: &inner, title: title) }
                    rows += inner.map { Row(label: i == 0 ? $0.label : "\($0.label) \(i + 1)", value: $0.value, staffOnly: $0.staffOnly) }
                }
            }
        default:
            guard let text = format(key, value), !text.isEmpty, text != title else { return }
            rows.append(Row(label: label, value: text, staffOnly: internalKeys.contains(key)))
        }
    }

    private static func format(_ key: String, _ value: JSONValue) -> String? {
        switch value {
        case .bool(let flag): return flag ? L("Yes") : L("No")
        case .number: return value.string
        case .string(let text):
            if text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil { return ClientsText.shortDay(text) }
            if text.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$"#, options: .regularExpression) != nil { return text }
            if text.range(of: #"^\d{4}-\d{2}-\d{2}T"#, options: .regularExpression) != nil { return ClientsText.dayTime(text) }
            return optionValue(key, text)
        default: return nil
        }
    }

    private static func spanish() -> Bool { LocalizationManager.shared.currentLanguage == .spanish }

    private static func optionValue(_ key: String, _ value: String) -> String {
        if ["handling_tags", "services", "authorized_extras", "coat", "skin", "behaviour", "progress"].contains(key) { return SvcReportText.option(value) }
        if ["status", "verificationStatus", "clinical_state", "clinicalState"].contains(key), let pair = statuses[value] { return spanish() ? pair.1 : pair.0 }
        if key == "recordType" { return ClientsText.recordType(value) }
        if ["service_category", "kind", "asked_by", "areas", "poop", "ate", "schedule_kind", "sitting_mode", "mood"].contains(key), let pair = codes[value] { return spanish() ? pair.1 : pair.0 }
        return value
    }

    static func label(_ key: String, parent: String?) -> String {
        if let parent, let pair = contextLabels["\(parent).\(key)"] { return spanish() ? pair.1 : pair.0 }
        if let pair = labels[key] { return spanish() ? pair.1 : pair.0 }
        let words = key.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: #"([a-z])([A-Z])"#, with: "$1 $2", options: .regularExpression).lowercased()
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    private static let labels: [String: (String, String)] = [
        "name": ("Name", "Nombre"), "title": ("Title", "Título"), "species": ("Species", "Especie"), "breed": ("Breed", "Raza"), "sex": ("Sex", "Sexo"),
        "birthDate": ("Birth date", "Fecha de nacimiento"), "isNeutered": ("Neutered", "Esterilizado"), "status": ("Status", "Estado"),
        "recordType": ("Record type", "Tipo de registro"), "verificationStatus": ("Verification", "Verificación"), "summary": ("Summary", "Resumen"),
        "details": ("Details", "Detalles"), "notes": ("Notes", "Notas"), "note": ("Note", "Nota"), "internalNote": ("Internal note", "Nota interna"),
        "internal_note": ("Internal note", "Nota interna"), "internal_notes": ("Internal note", "Nota interna"), "text": ("Document text", "Texto del documento"),
        "message": ("Update", "Actualización"), "condition": ("Condition", "Condición"), "trigger": ("Allergen", "Alérgeno"), "reaction": ("Reaction", "Reacción"),
        "diagnosis": ("Diagnosis", "Diagnóstico"), "eventAt": ("Recorded date", "Fecha del registro"), "event_at": ("Recorded date", "Fecha del registro"),
        "recorded_at": ("Measured at", "Fecha de medición"), "signed_at": ("Signed at", "Fecha de firma"), "created_at": ("Created at", "Fecha de creación"),
        "followUpAt": ("Follow-up date", "Fecha de seguimiento"), "follow_up_at": ("Follow-up date", "Fecha de seguimiento"), "due_at": ("Due date", "Fecha límite"),
        "nextDueAt": ("Next due date", "Próxima fecha"), "next_due_date": ("Next due date", "Próxima fecha"), "admitted_at": ("Admitted at", "Fecha de ingreso"),
        "ended_at": ("Ended at", "Fecha de salida"), "starts_at": ("Starts at", "Inicio"), "ends_at": ("Ends at", "Fin"), "day_key": ("Day", "Día"),
        "medication_name": ("Medication", "Medicamento"), "medicine_name": ("Medication", "Medicamento"), "active_ingredient": ("Active ingredient", "Principio activo"),
        "strength": ("Strength", "Concentración"), "dose_amount": ("Dose", "Dosis"), "dose_unit": ("Dose unit", "Unidad de dosis"), "route": ("Route", "Vía"),
        "every_hours": ("Interval (hours)", "Intervalo (horas)"), "frequency_text": ("Frequency", "Frecuencia"), "duration_days": ("Duration (days)", "Duración (días)"),
        "instructions": ("Instructions", "Indicaciones"), "as_needed": ("As needed", "Según necesidad"), "valid_until": ("Prescription valid until", "Receta válida hasta"),
        "cancelled_at": ("Cancelled at", "Fecha de cancelación"), "cancel_reason": ("Cancellation reason", "Motivo de cancelación"), "stop_reason": ("Reason it was stopped", "Motivo de suspensión"),
        "not_given_reason": ("Reason not given", "Motivo por el que no se dio"), "transfer_reason": ("Transfer reason", "Motivo del traslado"), "death_cause": ("Cause of death", "Causa de muerte"),
        "rate_ml_per_hour": ("Rate (ml/h)", "Ritmo (ml/h)"), "schedule_kind": ("Schedule", "Horario"), "weight_grams": ("Weight (g)", "Peso (g)"), "weightGrams": ("Weight (g)", "Peso (g)"),
        "weight_kg": ("Weight (kg)", "Peso (kg)"), "test_name": ("Test", "Prueba"), "result_summary": ("Result", "Resultado"), "vaccine_name": ("Vaccine", "Vacuna"),
        "reason": ("Reason", "Motivo"), "discharge_diagnosis": ("Discharge diagnosis", "Diagnóstico de alta"), "discharge_summary": ("Discharge summary", "Resumen de alta"),
        "discharge_instructions": ("Discharge instructions", "Indicaciones de alta"), "temperature_c": ("Temperature (°C)", "Temperatura (°C)"), "heart_rate": ("Heart rate", "Frecuencia cardíaca"),
        "respiratory_rate": ("Respiratory rate", "Frecuencia respiratoria"), "pain_score": ("Pain score", "Escala de dolor"), "mucous_membranes": ("Mucous membranes", "Mucosas"),
        "crt_seconds": ("Capillary refill (s)", "Llenado capilar (s)"), "outcome_note": ("Outcome", "Resultado"), "check_in_day": ("Check-in", "Entrada"), "check_out_day": ("Check-out", "Salida"),
        "sitting_mode": ("Sitting", "Modalidad"), "owner_instructions": ("What the family asked", "Lo que pidió la familia"), "mood": ("Mood", "Ánimo"), "time": ("Time", "Hora"),
        "service_label": ("Service", "Servicio"), "label": ("Treatment", "Tratamiento"), "handling_tags": ("Handling", "Manejo"), "usual_cut": ("Usual cut", "Corte habitual"),
        "blade_or_length": ("Blade or length", "Cuchilla o largo"), "products": ("Products", "Productos"), "care_notes": ("Care notes", "Notas de cuidado"),
        "rebook_every_weeks": ("Comes back every (weeks)", "Regresa cada (semanas)"), "service_category": ("Kind of visit", "Tipo de visita"), "arrival_note": ("Arrival note", "Nota de llegada"),
        "kind": ("Kind", "Tipo"), "services": ("Services", "Servicios"), "style": ("Cut", "Corte"), "length": ("Length", "Largo"), "areas": ("Areas", "Zonas"),
        "authorized_extras": ("Extras the owner allows", "Extras que autoriza el dueño"), "same_as_last_time": ("Same as last time", "Igual que la última vez"), "asked_by": ("Asked by", "Lo pidió"),
        "coat": ("Coat", "Pelaje"), "skin": ("Skin", "Piel"), "behaviour": ("Behaviour", "Comportamiento"), "differenceNote": ("Why it differs from the request", "Por qué difiere de lo pedido"),
        "skills": ("Practised", "Practicaron"), "progress": ("Progress", "Avance"), "homework": ("Homework", "Tarea en casa"), "minutes": ("Minutes", "Minutos"),
        "distanceKm": ("Distance (km)", "Distancia (km)"), "pee": ("Pee", "Pipí"), "poop": ("Poop", "Popó"), "water": ("Water", "Agua"), "ate": ("Food", "Comida"), "medsGiven": ("Medicine given", "Medicina dada"),
    ]

    private static let contextLabels: [String: (String, String)] = [
        "groom_request.services": ("Services requested", "Servicios solicitados"), "groom_request.style": ("Cut requested", "Corte solicitado"),
        "groom_request.length": ("Length requested", "Largo solicitado"), "groom_request.note": ("Note with the request", "Nota del pedido"),
        "report.services": ("Services done", "Servicios realizados"), "report.style": ("Cut done", "Corte realizado"), "report.length": ("Length done", "Largo realizado"),
        "report.note": ("Note in the report", "Nota del reporte"), "report.kind": ("Report", "Reporte"), "care_plan.notes": ("Care plan notes", "Notas del plan de cuidado"),
        "items.kind": ("Planned care", "Cuidado planeado"), "items.label": ("Planned item", "Indicación del plan"), "items.time": ("Planned time", "Hora planeada"),
        "report_cards.message": ("Report card", "Reporte de la estancia"), "report_cards.created_at": ("Report card date", "Fecha del reporte"),
        "home_visits.kind": ("Home visit", "Visita en casa"), "home_visits.day_key": ("Home visit day", "Día de la visita"), "home_visits.status": ("Home visit status", "Estado de la visita"),
        "home_visits.note": ("Home visit note", "Nota de la visita"), "care.kind": ("Care", "Cuidado"), "care.day_key": ("Care day", "Día del cuidado"),
        "care.label": ("Care item", "Cuidado indicado"), "care.status": ("Care status", "Estado del cuidado"), "care.note": ("Care note", "Nota del cuidado"),
    ]

    private static let codes: [String: (String, String)] = [
        "groomer": ("Grooming", "Estética"), "walker": ("Walk", "Paseo"), "sitter": ("Sitting", "Cuidado"), "daycare": ("Daycare", "Guardería"), "trainer": ("Training", "Entrenamiento"),
        "vet": ("Veterinary", "Veterinaria"), "boarding": ("Boarding", "Hospedaje"), "home_sitting": ("Home sitting", "Cuidado en casa"), "overnight": ("Overnight", "Noche"),
        "visits": ("Visits", "Visitas"), "meet_greet": ("Meet & greet", "Primer encuentro"), "meal": ("Meal", "Comida"), "play": ("Play", "Juego"), "custom": ("Other", "Otro"),
        "happy": ("Happy", "Contento"), "playful": ("Playful", "Juguetón"), "calm": ("Calm", "Tranquilo"), "shy": ("Shy", "Tímido"), "tired": ("Tired", "Cansado"),
        "groom": ("Groom", "Estética"), "walk": ("Walk or sitting", "Paseo o cuidado"), "training": ("Training", "Entrenamiento"), "family": ("The family", "La familia"),
        "staff": ("The team", "El equipo"), "face": ("Face", "Cara"), "feet": ("Feet", "Patas"), "tail": ("Tail", "Cola"), "body": ("Body", "Cuerpo"), "sanitary": ("Sanitary area", "Área sanitaria"),
        "normal": ("Normal", "Normal"), "soft": ("Soft", "Blanda"), "diarrhea": ("Diarrhea", "Diarrea"), "all": ("Ate everything", "Comió todo"), "some": ("Ate some", "Comió algo"),
        "none": ("Didn’t eat", "No comió"), "medication": ("Medication", "Medicamento"), "fluid": ("Fluids", "Fluidos"), "fluids": ("Fluids", "Fluidos"), "procedure": ("Procedure", "Procedimiento"),
        "monitoring": ("Monitoring", "Monitoreo"), "feeding": ("Feeding", "Alimentación"), "once": ("Once", "Una vez"), "recurring": ("Recurring", "Recurrente"),
        "continuous": ("Continuous", "Continuo"), "prn": ("As needed", "Según necesidad"),
    ]

    private static let statuses: [String: (String, String)] = [
        "completed": ("Finished", "Terminada"), "no_show": ("Didn’t show up", "No se presentó"), "unfinished": ("Not finished", "Sin terminar"), "active": ("Active", "Activo"),
        "inactive": ("Inactive", "Inactivo"), "archived": ("Archived", "Archivado"), "draft": ("Draft", "Borrador"), "signed": ("Signed", "Firmada"), "cancelled": ("Cancelled", "Cancelada"),
        "canceled": ("Cancelled", "Cancelada"), "expired": ("Expired", "Vencida"), "open": ("Open", "Abierto"), "contacted": ("Reminder sent", "Recordatorio enviado"),
        "scheduled": ("Visit booked", "Visita agendada"), "snoozed": ("Snoozed", "Pospuesto"), "done": ("Done", "Hecho"), "pending": ("Pending", "Pendiente"),
        "admitted": ("Admitted", "Hospitalizado"), "discharged": ("Discharged", "Dado de alta"), "transferred": ("Transferred", "Trasladado"), "deceased": ("Deceased", "Fallecido"),
        "given": ("Given", "Administrado"), "not_given": ("Not given", "No administrado"), "skipped": ("Skipped", "Omitido"), "refused": ("Refused", "Rechazado"),
        "stopped": ("Stopped", "Suspendido"), "resolved": ("Resolved", "Resuelto"), "verified": ("Verified", "Verificado"), "unverified": ("Not verified", "Sin verificar"),
        "rejected": ("Rejected", "Rechazado"), "checked_out": ("Finished", "Terminada"), "missed": ("Missed", "No realizada"),
    ]
}
