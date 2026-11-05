//
//  TeamMemberOlfato.swift
//  PawMiawNegocios
//
//  The "who asked" log of Olfato AI (web: components/app/olfato/
//  olfato-access.tsx, olfato-member-card.tsx; hooks/use-olfato-business.ts;
//  backend docs/olfato-business-chat-plan.md §9): one line per question —
//  who, when, which way in, the pets read, the kinds of information, what was
//  refused — never its text. A staff member's card shows their latest lines
//  and this week's count, for the person themself and for whoever reads the
//  team's use (owners, admins, whoever changes roles or manages money).
//  The log's shapes and its line are shared (Design/AuditHistoryCard.swift).
//

import SwiftUI

// MARK: - Shapes

/// Questions per person per week, Monday-start weeks in the workspace's calendar.
struct TeamOlfatoWeekly: Decodable, Hashable {
    struct Member: Decodable, Hashable {
        let memberId: String?
        let name: String?
        let counts: [Int]?
        let total: Int?
        let distinctPets: [Int]?
        let distinctPetsTotal: Int?
        let kinds: [[String: Int]]?

        var key: String { memberId ?? "left:\(name ?? "")" }
    }
    let weeks: [String]?
    let members: [Member]?
}

struct TeamOlfatoTeamPage: Decodable {
    let items: [OlfatoAccessEntry]?
    let total: Int?
    let hasMore: Bool?
    let weekly: TeamOlfatoWeekly?
}

// MARK: - Rules

enum TeamOlfatoAccess {
    /// The admin audit rule: the owner, an admin, or whoever changes roles and access or manages money.
    /// The server answers 403 to anyone else.
    static func seesTeam(_ workspace: Workspace) -> Bool {
        workspace.isOwnerOrAdmin || workspace.can(.staffEditRoles) || workspace.can(.billingManage)
    }

    /// The Monday (YYYY-MM-DD) of the week a calendar day falls in.
    static func monday(of day: String) -> String {
        guard let date = TeamDays.date(day) else { return day }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
        let back = (weekday + 5) % 7
        return TeamDays.add(TeamDays.key(utc: date), -back)
    }

    /// How many lines (newest first) fall in the week from `monday`, and whether that is all of them.
    static func weekCount(_ items: [OlfatoAccessEntry], monday: String, hasMore: Bool) -> (count: Int, exact: Bool) {
        let count = items.filter { ($0.day ?? "") >= monday }.count
        let exact = !hasMore || ((items.last?.day ?? "") < monday && !items.isEmpty)
        return (count, exact)
    }
}

// MARK: - A staff member's card

/// "Questions to Olfato AI" on a staff member's page: what they asked about,
/// and when (never the text), this week's count and their latest lines, a few
/// at a time. The whole team's list is in Settings › Olfato AI.
struct TeamMemberOlfatoCard: View {
    let memberId: String
    let isSelf: Bool
    let name: String
    /// This reader sees the team's use.
    let seesTeam: Bool

    private let pageSize = 5
    @State private var items: [OlfatoAccessEntry] = []
    @State private var total = 0
    @State private var hasMore = false
    @State private var loaded = false
    @State private var failed = false
    @State private var loadingMore = false
    @State private var moreFailed = false
    @State private var thisWeek: (count: Int, exact: Bool)?

    var body: some View {
        TeamPanel(
            title: L("Questions to Olfato AI"),
            subtitle: isSelf ? L("What you asked Olfato AI about, and when. Never the text.") : LF("What %@ asked Olfato AI about, and when. Never the text.", name),
            systemImage: "olfato",
            tint: Theme.aqua
        ) {
            if let thisWeek {
                Text(thisWeek.exact ? LF("%d this week", thisWeek.count) : LF("%d+ this week", thisWeek.count))
                    .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Theme.surfaceMuted, in: Capsule())
            }
        } content: {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            } else if failed {
                VStack(spacing: 10) {
                    Text(L("Could not load the questions to Olfato AI.")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    PMButton(L("Try again"), variant: .outline, size: .compact) { Task { await load() } }
                }
                .frame(maxWidth: .infinity)
            } else if items.isEmpty {
                EmptyState(systemImage: "message-circle-question", title: L("No questions to Olfato AI yet."))
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { entry in
                        OlfatoAccessLine(entry: entry, showPerson: false)
                        if entry.id != items.last?.id { RowDivider() }
                    }
                }
                HStack {
                    Text(LF("Showing %1$d of %2$d", items.count, max(total, items.count))).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    Spacer()
                    if hasMore || moreFailed {
                        PMButton(moreFailed ? L("Try again") : L("Show more"), systemImage: "chevron-down", variant: .outline, size: .compact, isWorking: loadingMore) { Task { await more() } }
                    }
                }
            }
            if seesTeam {
                NavigationLink { TeamOlfatoSettingsPage() } label: {
                    Text(L("See the whole team’s use")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: memberId) { await load() }
    }

    private var path: String { "/provider-olfato/access/members/\(isSelf ? "me" : memberId)" }

    private func load() async {
        do {
            let page: TeamOlfatoTeamPage = try await API.get(path, query: ["limit": "\(pageSize)", "offset": "0"])
            items = page.items ?? []
            total = page.total ?? items.count
            hasMore = page.hasMore ?? (items.count < total)
            failed = false
        } catch {
            failed = items.isEmpty
        }
        loaded = true
        await countThisWeek()
    }

    private func more() async {
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page: TeamOlfatoTeamPage = try await API.get(path, query: ["limit": "\(pageSize)", "offset": "\(items.count)"])
            let known = Set(items.map(\.id))
            items += (page.items ?? []).filter { !known.contains($0.id) }
            if let t = page.total { total = t }
            hasMore = page.hasMore ?? (items.count < total)
            moreFailed = false
            if !seesTeam { await countThisWeek() }
        } catch {
            moreFailed = true
        }
    }

    /// Exact weekly counts come with the team's list; the person themself counts from their own lines.
    private func countThisWeek() async {
        if seesTeam {
            guard let page: TeamOlfatoTeamPage = try? await API.get("/provider-olfato/access/team", query: ["memberId": memberId, "limit": "1", "offset": "0"]),
                  let weekly = page.weekly else { return }
            let row = weekly.members?.first { $0.memberId == memberId }
            thisWeek = (row?.counts?.last ?? 0, true)
        } else {
            guard let viewer: InboxOlfatoPanel = try? await API.get("/provider-olfato/viewer"), let today = viewer.today else { return }
            thisWeek = TeamOlfatoAccess.weekCount(items, monday: TeamOlfatoAccess.monday(of: today), hasMore: hasMore)
        }
    }
}
