//
//  TeamOlfatoSettings.swift
//  PawMiawNegocios
//
//  Settings › Olfato AI (web: components/app/settings/ai-summary-section.tsx,
//  components/app/olfato/olfato-consent.tsx and olfato-team-use.tsx; backend
//  docs/patient-summaries.md and docs/olfato-business-chat-plan.md): the
//  business's own switch for the AI brief on a pet's chart and the chat,
//  which only turns on once someone who edits the workspace has read what is
//  sent and to whom and confirmed it; and "Team use", who on the team asked
//  Olfato AI, when, about which pets and what kind of information (never the
//  text), 20 at a time with filters.
//

import SwiftUI

/// `GET/PUT /provider-patients/ai-summary-settings`.
struct TeamOlfatoSummarySettings: Decodable, Equatable {
    /// The server can write summaries. False: nothing can be turned on yet.
    let available: Bool?
    let enabled: Bool?
    /// The current notice was confirmed.
    let acknowledged: Bool?
    /// On, but confirmed on an older notice: the brief and the chat wait until it is confirmed again.
    let noticeOutdated: Bool?
    let acknowledgedAt: String?
    let acknowledgedByName: String?
    let disclosureVersion: String?
    let canManage: Bool?
}

/// Olfato AI's page, opened from Settings and from a staff member's "See the whole team's use".
struct TeamOlfatoSettingsPage: View {
    @EnvironmentObject private var workspace: Workspace

    var body: some View {
        PageScroll {
            ModuleHeader(
                icon: "settings",
                title: L("Settings"),
                subtitle: L("How your business shows up to families, what it offers, and the clock and money it runs on."),
                accent: ProviderSection.settings.headerAccent,
                storageKey: "settings"
            )
            TeamOlfatoSections()
        }
        .providerPage("Olfato AI")
    }
}

/// The sections this person may see: the switch for whoever reads records or edits the
/// workspace, the team's use for owners, admins and whoever manages roles or money.
struct TeamOlfatoSections: View {
    @EnvironmentObject private var workspace: Workspace

    var body: some View {
        if workspace.canAny(.recordsView, .workspaceEdit) {
            TeamOlfatoSummarySection(canEdit: workspace.can(.workspaceEdit))
        }
        if TeamOlfatoAccess.seesTeam(workspace) {
            TeamOlfatoTeamUseSection()
        }
    }
}

// MARK: - The switch

struct TeamOlfatoSummarySection: View {
    let canEdit: Bool

    @StateObject private var flash = TeamSavedFlash()
    @State private var settings: TeamOlfatoSummarySettings?
    @State private var failed = false
    @State private var enabled = false
    @State private var acknowledged = false
    @State private var saving = false

    private var editable: Bool { canEdit && (settings?.canManage ?? false) }
    private var dirty: Bool {
        guard let settings else { return false }
        return enabled != (settings.enabled ?? false) || acknowledged != (settings.acknowledged ?? false)
    }

    var body: some View {
        if let settings {
            card(settings)
        } else if failed {
            TeamPanel(title: "Olfato AI", systemImage: "olfato", tint: Theme.aqua, look: .settings) {
                VStack(spacing: 12) {
                    Text(L("Could not load the Olfato AI settings.")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.center)
                    PMButton(L("Try again"), variant: .outline) { Task { await load() } }
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
        } else {
            TeamPanel(title: "Olfato AI", systemImage: "olfato", tint: Theme.aqua, look: .settings) {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
            .task { await load() }
        }
    }

    private func card(_ settings: TeamOlfatoSummarySettings) -> some View {
        let available = settings.available ?? false
        let canTurnOn = available && acknowledged
        return TeamSaveSection(
            title: "Olfato AI",
            subtitle: L("AI brief of each pet’s record.") + "\n" + L("Olfato is Spanish for a pet’s sense of smell: it sniffs out what matters in the chart."),
            systemImage: "olfato",
            tint: Theme.aqua,
            look: .settings,
            state: flash.state(saving: saving, dirty: dirty),
            readOnlyText: editable ? nil : L("Only someone who edits the workspace can change this."),
            onSave: editable ? { save(settings) } : nil,
            onDiscard: { reset(settings) }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom) {
                    Text(L("Before you turn it on")).font(Theme.text(14, weight: .heavy)).foregroundStyle(Theme.inkStrong)
                    Spacer()
                    Image("OlfatoAI").resizable().scaledToFit().frame(width: 96, height: 96).padding(.top, -4).accessibilityHidden(true)
                }
                OlfatoNotice()
            }
            if !available {
                Text(L("Olfato AI isn’t available on PawMiaw yet. When it is, you can turn it on here."))
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            }
            if settings.noticeOutdated == true {
                Text(editable
                     ? L("The Olfato AI notice changed: it now covers the chat too. Read it and confirm it to use Olfato AI.")
                     : L("Olfato AI is paused until someone who edits the workspace confirms its new notice."))
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            }
            // "I've read this…": once confirmed it stays confirmed (it records who read it, and when).
            let ackLocked = !editable || (settings.acknowledged ?? false)
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    flash.clear()
                    acknowledged.toggle()
                    // The switch does not stay on without the confirmation.
                    if !acknowledged { enabled = false }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Tick(on: acknowledged)
                        Text(L("I’ve read this and our clients are informed as our policies require"))
                            .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(ackLocked)
                .opacity(ackLocked && !acknowledged ? 0.5 : 1)
                if settings.acknowledged == true, let at = settings.acknowledgedAt {
                    Text(settings.acknowledgedByName.nonEmpty.map { LF("Confirmed by %1$@ on %2$@", $0, DateText.date(at)) } ?? LF("Confirmed on %@", DateText.date(at)))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        .padding(.leading, 28)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            // The one choice; it waits for the confirmation. Turning it off is always possible.
            ToggleRow(
                title: L("Olfato AI on pet charts"),
                subtitle: !available ? L("Not available yet.")
                    : !acknowledged ? L("Tick the confirmation above first.")
                    : enabled ? L("On: charts show the Olfato AI brief above the pet’s records.")
                    : L("Off: charts show the pet’s records as always, with no AI text. Nothing is sent."),
                isOn: Binding(get: { enabled }, set: { flash.clear(); enabled = $0 })
            )
            .disabled(!editable || (!enabled && !canTurnOn))
            // The chat goes with the same switch and notice.
            HStack(alignment: .top, spacing: 12) {
                Glyph("message-circle", size: 16).foregroundStyle(Theme.inkSoft).padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Olfato AI chat")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    Text(((settings.enabled ?? false) && (settings.acknowledged ?? false)
                          ? L("Your team asks Olfato AI from “Olfato AI” in the sidebar and from “Ask Olfato” on each pet’s chart. Each person only gets answers from what they can already see.")
                          : L("With Olfato AI on and this notice confirmed, your team can ask it about a pet or about the business: “Olfato AI” in the sidebar and “Ask Olfato” on each pet’s chart."))
                         + " " + L("To leave someone out, turn off “Use Olfato AI” in their access, in Staff."))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        }
    }

    private func reset(_ settings: TeamOlfatoSummarySettings) {
        enabled = settings.enabled ?? false
        acknowledged = settings.acknowledged ?? false
    }

    private func load() async {
        do {
            let loaded: TeamOlfatoSummarySettings = try await API.get("/provider-patients/ai-summary-settings")
            settings = loaded
            reset(loaded)
            failed = false
        } catch {
            failed = settings == nil
        }
    }

    private func save(_ settings: TeamOlfatoSummarySettings) {
        // Confirming a notice that changed is the notice alone: the server keeps the switch.
        let onlyTheNotice = settings.noticeOutdated == true && acknowledged && enabled == (settings.enabled ?? false)
        var body: [String: Any?] = [:]
        if onlyTheNotice {
            body["acknowledged"] = true
        } else {
            body["enabled"] = enabled
            if acknowledged && settings.acknowledged != true { body["acknowledged"] = true }
        }
        saving = true
        Task {
            defer { saving = false }
            do {
                let saved: TeamOlfatoSummarySettings = try await API.put("/provider-patients/ai-summary-settings", body: body)
                self.settings = saved
                reset(saved)
                flash.mark()
                await Workspace.shared.refresh()
                announceDataChanged()
            } catch {
                Toast.error(errorText(error, fallback: L("Could not save the Olfato AI settings.")))
            }
        }
    }
}

// MARK: - Team use

@MainActor
private final class TeamOlfatoTeamUseModel: ObservableObject {
    @Published var memberId: String?
    @Published var petId: String?
    @Published var petName: String?
    @Published var from: Date?
    @Published var to: Date?
    @Published var tool: String?
    @Published var weekly: TeamOlfatoWeekly?
    @Published var weeklyFailed = false
    @Published var areas: [InboxOlfatoArea] = []
    lazy var pager: Pager<OlfatoAccessEntry> = Pager { [weak self] offset, limit in
        guard let self else { return Page(items: [], total: 0) }
        let page: TeamOlfatoTeamPage = try await API.get("/provider-olfato/access/team", query: self.query(offset: offset, limit: limit))
        if let weekly = page.weekly { self.weekly = weekly }
        return Page(items: page.items ?? [], total: page.total, hasMore: page.hasMore)
    }

    var filtered: Bool { memberId != nil || petId != nil || from != nil || tool != nil }

    func query(offset: Int, limit: Int) -> [String: String?] {
        [
            "limit": "\(limit)",
            "offset": "\(offset)",
            "weeks": "8",
            "memberId": memberId,
            "petId": petId,
            "from": from.map { TeamDays.key(picked: $0) },
            "to": to.map { TeamDays.key(picked: $0) },
            "tool": tool,
        ]
    }

    func clear() {
        memberId = nil; petId = nil; petName = nil; from = nil; to = nil; tool = nil
    }

    func loadAreas() async {
        if let panel: InboxOlfatoPanel = try? await API.get("/provider-olfato/viewer") { areas = panel.areas ?? [] }
    }
}

/// Who on the team asked Olfato AI, how often (questions per person per week, with this week's
/// pets and kinds), and every line, narrowed by person, pet, dates and kind, 20 at a time.
struct TeamOlfatoTeamUseSection: View {
    @StateObject private var model = TeamOlfatoTeamUseModel()

    var body: some View {
        let people = (model.weekly?.members ?? []).filter { $0.memberId != nil }
        TeamPanel(
            title: L("Team use"),
            subtitle: L("Who on the team asked Olfato AI, when, about which pets and what kind of information."),
            systemImage: "users-round",
            tint: Theme.aqua,
            look: .settings
        ) {
            HStack(alignment: .top, spacing: 8) {
                Glyph("lock", size: 16).foregroundStyle(Theme.inkSoft).padding(.top, 2)
                Text(L("The text of questions and answers is never kept here: only who asked, when and about what."))
            }
            .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
            .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))

            if let weekly = model.weekly, !(weekly.members ?? []).isEmpty {
                weeklyCounts(weekly)
            }

            Text(L("Every question")).font(Theme.text(14, weight: .heavy)).foregroundStyle(Theme.inkStrong)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                MenuField(
                    label: L("Person"),
                    options: [("", L("Everyone"))] + people.map { ($0.memberId ?? "", $0.name?.nonEmpty ?? L("Someone")) } + (model.memberId.map { id in people.contains { $0.memberId == id } ? [] : [(id, L("Someone"))] } ?? []),
                    selection: Binding(get: { model.memberId ?? "" }, set: { model.memberId = $0.nonEmpty; reload() })
                )
                MenuField(
                    label: L("Kind of information"),
                    options: [("", L("Every kind"))] + model.areas.map { ($0.key, $0.label?.text.nonEmpty ?? $0.key) },
                    selection: Binding(get: { model.tool ?? "" }, set: { model.tool = $0.nonEmpty; reload() })
                )
            }
            dates
            if model.petId != nil || model.filtered {
                FlowLayout(spacing: 8) {
                    if model.petId != nil {
                        Button { model.petId = nil; model.petName = nil; reload() } label: {
                            HStack(spacing: 6) {
                                Glyph("paw-print", size: 14)
                                Text(LF("Pet: %@", model.petName?.nonEmpty ?? L("a pet")))
                                Glyph("x", size: 16).foregroundStyle(Theme.inkSoft).frame(width: 36, height: 36)
                            }
                            .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                            .padding(.leading, 12).frame(minHeight: 36)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Show every pet"))
                    }
                    if model.filtered {
                        PMButton(L("Clear the filters"), variant: .outline, size: .compact) { model.clear(); reload() }
                    }
                }
            }
            list
        }
        .task {
            if !model.pager.loadedOnce { await model.pager.reload() }
            if model.areas.isEmpty { await model.loadAreas() }
        }
    }

    private func reload() {
        Task { await model.pager.reload() }
    }

    private var dates: some View {
        FormField(label: L("Dates")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    dateField(L("From"), value: model.from) { model.from = $0; if let to = model.to, let from = $0, to < from { model.to = from }; reload() }
                    dateField(L("To"), value: model.to) { model.to = $0; if let from = model.from, let to = $0, to < from { model.from = to }; reload() }
                }
                if model.from != nil || model.to != nil {
                    PMButton(L("Clear the dates"), systemImage: "x", variant: .outline, size: .compact) { model.from = nil; model.to = nil; reload() }
                }
            }
        }
    }

    private func dateField(_ label: String, value: Date?, set: @escaping (Date?) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label).font(Theme.text(13, weight: .bold)).foregroundStyle(Theme.inkSoft)
            if let value {
                DatePicker(label, selection: Binding(get: { value }, set: { set($0) }), in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, .app)
            } else {
                Button { set(Date()) } label: { PillField(text: L("Choose a day"), icon: "calendar-days", placeholder: true) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var list: some View {
        TeamOlfatoTeamList(pager: model.pager, filtered: model.filtered) { pet in
            model.petId = pet.id; model.petName = pet.name; reload()
        } onPickMember: { id in
            model.memberId = id; reload()
        } onClear: {
            model.clear(); reload()
        }
    }

    private func weeklyCounts(_ weekly: TeamOlfatoWeekly) -> some View {
        let weeks = weekly.weeks ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Questions per week")).font(Theme.text(14, weight: .heavy)).foregroundStyle(Theme.inkStrong)
                Spacer()
                Text(LF("Last %d weeks", weeks.count)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
            VStack(spacing: 0) {
                ForEach(weekly.members ?? [], id: \.key) { member in
                    weekRow(member, weeks: weeks)
                    if member.key != weekly.members?.last?.key { RowDivider() }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        }
    }

    private func weekRow(_ member: TeamOlfatoWeekly.Member, weeks: [String]) -> some View {
        let name = member.name?.trimmingCharacters(in: .whitespaces).nonEmpty ?? L("Someone")
        let index = (member.counts?.count ?? 1) - 1
        let questions = index >= 0 ? (member.counts?[index] ?? 0) : 0
        let pets = index >= 0 && index < (member.distinctPets?.count ?? 0) ? (member.distinctPets?[index] ?? 0) : 0
        let kinds = index >= 0 && index < (member.kinds?.count ?? 0) ? (member.kinds?[index] ?? [:]) : [:]
        let kindKeys = kinds.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map(\.key)
        let kindNames = kindKeys.map { key in model.areas.first { $0.key == key }?.label?.text.nonEmpty ?? key }.joined(separator: ", ")
        let selected = member.memberId != nil && member.memberId == model.memberId
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let id = member.memberId {
                    Button(name) { model.memberId = id; reload() }
                        .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        .accessibilityLabel(LF("Show only %@", name))
                } else {
                    Text(LF("%@ (left the team)", name)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                }
                Text(L("This week:") + " " + (questions == 0 ? L("No questions this week.") : [
                    LP(questions, "1 question", "%d questions"),
                    LP(pets, "1 pet", "%d pets"),
                    LP(kindKeys.count, "1 kind", "%d kinds"),
                ].joined(separator: " · ")))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                if questions > 0 && !kindNames.isEmpty {
                    Text(kindNames).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            TeamOlfatoWeekBars(weeks: weeks, counts: member.counts ?? [])
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(member.total ?? 0)").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).monospacedDigit()
                if (member.distinctPetsTotal ?? 0) > 0 {
                    Text(LP(member.distinctPetsTotal ?? 0, "1 pet", "%d pets")).font(Theme.text(11)).foregroundStyle(Theme.inkSoft)
                }
            }
            .frame(width: 56, alignment: .trailing)
        }
        .padding(12)
        .background(selected ? Theme.surfaceMuted : Color.clear)
    }
}

/// Eight small bars: a person's questions week by week, the last one this week.
private struct TeamOlfatoWeekBars: View {
    let weeks: [String]
    let counts: [Int]

    var body: some View {
        let top = max(1, counts.max() ?? 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(counts.enumerated()), id: \.offset) { index, count in
                Capsule()
                    .fill(count > 0 ? Theme.aqua : Theme.borderSoft)
                    .frame(width: 7, height: max(3, 28 * CGFloat(count) / CGFloat(top)))
                    .accessibilityLabel(LF("Week of %1$@: %2$@", index < weeks.count ? TeamDays.short(weeks[index]) : "", LP(count, "1 question", "%d questions")))
            }
        }
        .frame(height: 28, alignment: .bottom)
    }
}

/// The team's lines, 20 at a time, with the empty states the filters call for.
private struct TeamOlfatoTeamList: View {
    @ObservedObject var pager: Pager<OlfatoAccessEntry>
    let filtered: Bool
    let onPickPet: (OlfatoAccessEntry.Pet) -> Void
    let onPickMember: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        if !pager.loadedOnce && pager.isLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 80)
        } else if pager.error != nil && pager.items.isEmpty {
            VStack(spacing: 12) {
                Text(L("Could not load the team’s use of Olfato AI.")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.center)
                PMButton(L("Try again"), variant: .outline) { Task { await pager.reload() } }
            }
            .padding(.horizontal, 16).padding(.vertical, 32)
            .frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        } else if pager.items.isEmpty {
            EmptyState(systemImage: "message-circle-question",
                       title: filtered ? L("No questions match these filters.") : L("No questions to Olfato AI yet."),
                       message: filtered ? L("Change or clear the filters to see more.") : L("When someone on the team asks Olfato AI, a line shows here: who, when and about what. Never the text."),
                       actionTitle: filtered ? L("Clear the filters") : nil,
                       action: filtered ? onClear : nil)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(pager.items) { entry in
                    OlfatoAccessLine(entry: entry, onPickPet: onPickPet, onPickMember: onPickMember)
                        .onAppear { pager.loadMoreIfNeeded(entry) }
                    if entry.id != pager.items.last?.id { RowDivider() }
                }
                PagerFooter(pager: pager)
            }
            Text(LF("Showing %1$d of %2$d", pager.items.count, max(pager.total ?? 0, pager.items.count)))
                .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
        }
    }
}
