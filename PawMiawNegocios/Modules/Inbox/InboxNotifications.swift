//
//  InboxNotifications.swift
//  PawMiawNegocios
//
//  Avisos (web routes/provider.notifications.tsx,
//  components/app/notifications/, hooks/use-notifications.ts): everything
//  the workspace was told, newest first by day. The owner's rule: a row
//  opens by a tap (and is read then), leaves by a swipe to the LEFT, no
//  snooze. 20 at a time with infinite scroll; the counts are the server's.
//

import SwiftUI

// MARK: - Models

struct InboxNotification: Decodable, Identifiable, Equatable {
    let id: String
    let contextType: String?
    let recipientScope: String?
    let category: String?
    let title: String?
    let body: String?
    let petName: String?
    let clientName: String?
    let pet: InboxNotificationPet?
    let severity: String?
    let sourceType: String?
    let sourceId: String?
    let actionUrl: String?
    let dueAt: String?
    let readAt: String?
    let resolvedAt: String?
    let dismissedAt: String?
    let createdAt: String?
    let destinationState: String?

    var closed: Bool { dismissedAt != nil || resolvedAt != nil }
    var unread: Bool { readAt == nil }
}

struct InboxNotificationPet: Decodable, Equatable {
    let clientId: String?
    let providerClientPetId: String?
}

struct InboxUnreadSummary: Decodable {
    let unreadCount: Int?
    let urgentUnreadCount: Int?
    let activeCount: Int?
    let categoryCounts: [String: InboxCategoryCount]?
}

struct InboxCategoryCount: Decodable {
    let active: Int?
    let unread: Int?
}

// MARK: - Words and rules (lib/notification-formatting.ts, lib/notification-routing.ts)

enum InboxArea: String, CaseIterable, Identifiable {
    case agenda, billing, records, clients, team

    var id: String { rawValue }

    var categories: [String] {
        switch self {
        case .agenda: ["appointments", "client_facing_reminders"]
        case .billing: ["billing"]
        case .records: ["records_documentation", "provider_follow_ups", "medical_follow_ups", "routines", "routine_checkins", "preventive_care", "care_supplies"]
        case .clients: ["client_messages", "provider_invitations", "provider_updates"]
        case .team: ["security", "household_access", "owner_tasks"]
        }
    }

    var label: String {
        switch self {
        case .agenda: L("Schedule@area")
        case .billing: L("Billing & register")
        case .records: L("Records@area")
        case .clients: L("Clients@area")
        case .team: L("Team@area")
        }
    }

    static func of(_ category: String?) -> InboxArea {
        allCases.first { $0.categories.contains(category ?? "") } ?? .team
    }
}

enum InboxNotificationText {
    /// "2:43 p.m.." → "2:43 p.m."; doubled spaces gone.
    static func clean(_ text: String?) -> String {
        guard var text, !text.isEmpty else { return "" }
        while let range = text.range(of: "(?<!\\.)\\.\\.(?!\\.)", options: .regularExpression) {
            text.replaceSubrange(range, with: ".")
        }
        return text.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func accessChanged(_ n: InboxNotification) -> Bool {
        n.destinationState == "access_changed" || n.title == "Access changed"
    }

    static func title(_ n: InboxNotification) -> String {
        accessChanged(n) ? L("Access changed") : clean(n.title)
    }

    static func body(_ n: InboxNotification) -> String {
        accessChanged(n) ? L("This update is no longer available with your current permissions.") : clean(n.body)
    }

    static func severity(_ raw: String?) -> String {
        switch raw {
        case "urgent", "critical": "urgent"
        case "action", "warning": "action"
        default: "info"
        }
    }

    private static let deadlineSources: Set<String> = [
        "provider_follow_up", "provider_recall", "provider_appointment_documentation", "household_record_follow_up",
        "household_preventive_record", "missing_documentation", "pet_routine", "routine", "routine_checkin",
    ]
    private static let deadlineCategories: Set<String> = ["provider_follow_ups", "medical_follow_ups", "preventive_care", "owner_tasks"]
    private static let receipts: Set<String> = [
        "auth_sign_in", "household_invite_accepted", "household_member_access_updated", "household_member_removed",
        "provider_client_invitation_expired", "routine_checkin",
    ]
    private static let actionable: Set<String> = [
        "appointment", "appointment_confirmation", "appointment_reschedule", "billing", "cabinet", "cabinet_expired",
        "cabinet_expiring", "cabinet_expiring_soon", "cabinet_low_stock", "cabinet_refill_needed", "cabinet_runs_out",
        "client_message", "household_appointment", "household_invite", "household_preventive_record",
        "household_record_follow_up", "invoice", "missing_documentation", "pet_record", "pet_routine",
        "routine_course_ending", "routine_course_ended", "provider_appointment", "provider_appointment_confirmation",
        "provider_client_invitation", "provider_follow_up", "provider_invoice", "provider_link_request",
        "provider_paperwork_late", "provider_paperwork_today", "provider_record", "record", "records_documentation", "routine",
    ]

    /// A notice whose date can be missed (a task, a dose); an event's date is when it happened.
    static func hasRealDeadline(_ n: InboxNotification) -> Bool {
        let source = n.sourceType ?? ""
        if source.hasPrefix("cabinet") || source.hasPrefix("routine_course") { return false }
        if deadlineSources.contains(source) { return true }
        if source.hasPrefix("provider_register") || source.contains("invoice") || source.contains("invitation") { return false }
        if source.contains("confirmation") || source.contains("reschedule") { return false }
        return deadlineCategories.contains(n.category ?? "")
    }

    static func isStartTime(_ source: String?) -> Bool {
        ["provider_appointment", "household_appointment", "appointment", "stay"].contains(source ?? "")
    }

    static func isReceipt(_ n: InboxNotification) -> Bool { receipts.contains(n.sourceType ?? "") }

    /// Informational notices leave the list once seen; the rest are only read.
    static func autoDismissOnView(_ n: InboxNotification) -> Bool {
        let source = n.sourceType ?? ""
        if actionable.contains(source) { return false }
        if receipts.contains(source) { return true }
        if let severity = n.severity, severity != "info" { return false }
        return ["household_access", "provider_updates", "security"].contains(n.category ?? "")
    }

    /// "in 3 h", "3 h ago", "tomorrow", "in 4 days".
    static func distance(_ target: Date, now: Date = Date()) -> String {
        let diff = target.timeIntervalSince(now)
        let minutes = Int((abs(diff) / 60).rounded())
        if minutes < 1 { return L("Just now").lowercased() }
        if minutes < 60 { return diff < 0 ? LF("%d min ago", minutes) : LF("in %d min@notification", minutes) }
        let hours = Int((Double(minutes) / 60).rounded())
        if hours < 24 { return diff < 0 ? LF("%d h ago", hours) : LF("in %d h", hours) }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: target)).day ?? 0
        if days == 1 { return L("tomorrow") }
        if days == -1 { return L("yesterday") }
        return days < 0 ? LF("%d days ago", -days) : LF("in %d days", days)
    }

    /// The one tag beside the title, if any: overdue, due or starting soon, urgent, or needs you.
    static func status(_ n: InboxNotification, now: Date = Date()) -> (text: String, state: ProviderState)? {
        if n.closed { return nil }
        let due = DateText.parse(n.dueAt)
        if let due, hasRealDeadline(n) {
            if due < now.addingTimeInterval(-60) { return (LF("Overdue · %@", distance(due, now: now)), .problem) }
            if due.timeIntervalSince(now) <= 2 * 86_400 { return (LF("Due %@", distance(due, now: now)), .waiting) }
        }
        if let due, isStartTime(n.sourceType), due > now, due.timeIntervalSince(now) <= 2 * 86_400 {
            return (LF("Starts %@", distance(due, now: now)), .upcoming)
        }
        if isReceipt(n) { return nil }
        switch severity(n.severity) {
        case "urgent": return (L("Urgent@notification"), .problem)
        case "action": return (L("Needs you@notification"), .waiting)
        default: return nil
        }
    }

    /// When it arrived: "Just now", "20 min ago", "3 h ago" today; "Yesterday", the weekday this week, then the date.
    static func time(_ iso: String?, now: Date = Date()) -> String {
        guard let date = DateText.parse(iso) else { return "" }
        let diff = now.timeIntervalSince(date)
        let group = timeGroup(date, now: now)
        if diff < 60 { return L("Just now") }
        if group == .today || diff < 3600 {
            let minutes = Int((diff / 60).rounded())
            return minutes < 60 ? LF("%d min ago", minutes) : LF("%d h ago", Int((Double(minutes) / 60).rounded()))
        }
        if group == .yesterday { return L("Yesterday") }
        let formatter = DateFormatter()
        formatter.locale = .app
        formatter.setLocalizedDateFormatFromTemplate(group == .thisWeek ? "EEEE" : (Calendar.current.isDate(date, equalTo: now, toGranularity: .year) ? "dMMM" : "dMMMyyyy"))
        return formatter.string(from: date)
    }

    enum TimeGroup: Int, CaseIterable { case today, yesterday, thisWeek, earlier
        var label: String {
            switch self {
            case .today: L("Today")
            case .yesterday: L("Yesterday")
            case .thisWeek: L("This week")
            case .earlier: L("Earlier")
            }
        }
    }

    static func timeGroup(_ date: Date, now: Date = Date()) -> TimeGroup {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 0 { return .today }
        if days == 1 { return .yesterday }
        return days < 7 ? .thisWeek : .earlier
    }

    /// The row's one step, named for what it does.
    static func actionLabel(_ n: InboxNotification) -> String {
        switch n.sourceType {
        case "provider_register_open": return L("Go to the register")
        case "provider_register_difference": return L("See the cash count")
        case "provider_balance": return L("See balance")
        case "provider_record_signature", "provider_record_unsigned": return L("Sign@notification")
        case "provider_follow_up": return n.category == "records_documentation" ? L("Complete the record") : L("Schedule@action")
        case "provider_recall": return L("Schedule@action")
        case "provider_appointment_documentation": return L("Complete the record")
        case "provider_paperwork_today", "provider_paperwork_late": return L("See what is missing")
        case "provider_client_invitation", "provider_link_request": return L("Review")
        case "provider_appointment_confirmation": return L("Review request")
        case "appointment_confirmation": return L("Confirm appointment")
        case "appointment_reschedule": return L("Review change")
        case "provider_appointment": return L("Open visit@notification")
        case "household_appointment", "appointment": return L("View appointment")
        case "stay": return L("Open stay")
        case "provider_record": return L("Open record")
        case "pet_record", "household_preventive_record", "household_record_follow_up", "record": return L("View record")
        case "missing_documentation": return L("Upload document")
        case "provider_invoice", "invoice": return L("Open invoice")
        case "client_message": return L("Open chat")
        case "auth_sign_in": return L("Check security")
        default:
            switch n.category {
            case "provider_invitations": return L("Review")
            case "billing": return L("Open invoice")
            case "records_documentation": return L("Review records")
            case "preventive_care": return L("View record")
            case "provider_follow_ups": return L("Open follow-up")
            case "appointments": return L("View appointment")
            case "client_messages": return L("Open chat")
            default: return L("Open@notification")
            }
        }
    }

    /// Where a tap goes (lib/notification-routing.ts `getNotificationActionUrl`), as a screen of the app.
    static func route(_ n: InboxNotification) -> ProviderRoute? {
        let generic: Set<String> = ["/app/notifications", "/provider/notifications"]
        let knownFallback: Set<String> = ["provider_appointment", "provider_follow_up", "provider_record", "records_documentation", "provider_invoice", "invoice", "billing", "client_message"]
        let source = n.sourceType ?? ""
        if source.hasPrefix("hospital"), let url = n.actionUrl, !url.hasPrefix("/provider") {
            if let route = InboxRoutes.route(url) { return route }
            if source == "hospital_missed_treatment" { return .section(.hospital) }
        }
        if let url = n.actionUrl, url.hasPrefix("/"), !(generic.contains(url) && knownFallback.contains(source)) {
            return InboxRoutes.route(url)
        }
        let id = n.sourceId?.nonEmpty
        switch source {
        case "provider_appointment": return id.map { ProviderRoute.appointment($0) }
        case "provider_follow_up": return .section(.records)
        case "provider_record", "records_documentation": return id.map { ProviderRoute.record($0) } ?? .section(.records)
        case "provider_invoice", "invoice", "billing": return .section(.invoices)
        case "client_message": return .section(.clients)
        default: return nil
        }
    }

    /// Gente's navy, which thins to grey as a wash (web `--kind-people` / its ink); no Theme token holds it.
    private static let peopleColor = Color.scheme(light: (34, 58, 102), dark: (142, 167, 214))
    private static let peopleInk = Color.scheme(light: (34, 58, 102), dark: (195, 210, 238))

    /// What a notification is about (web `getNotificationKind` + `KIND_LOOK`): a Lucide icon, the colour
    /// of the kind of thing it is about (the badge is a wash of it) and the glyph's ink.
    static func look(_ n: InboxNotification) -> (icon: String, accent: Color, ink: Color) {
        let agenda = (Hue.peach.color, Hue.peach.ink)
        let record = (Hue.teal.color, Hue.teal.ink)
        let people = (peopleColor, peopleInk)
        let plain = (Hue.grey.color, Hue.grey.ink)
        func of(_ icon: String, _ kind: (Color, Color)) -> (icon: String, accent: Color, ink: Color) { (icon, kind.0, kind.1) }
        let source = n.sourceType ?? ""
        if source == "provider_register_open" { return ("wallet", Theme.mango, Theme.inkStrong) }
        if source == "provider_register_difference" { return ("scale", Theme.coral, Theme.inkStrong) }
        if ["provider_invoice", "invoice", "provider_balance"].contains(source) { return ("receipt", Theme.mango, Theme.inkStrong) }
        if source == "provider_record_signature" || source == "provider_record_unsigned" { return of("file-pen", record) }
        if source == "stay" || source.hasPrefix("provider_stay") { return of("bed-double", agenda) }
        if source.hasPrefix("cabinet") { return of("pill", (Hue.sky.color, Hue.sky.ink)) }
        if source == "household_preventive_record" { return of("syringe", record) }
        if source.contains("invitation") || source == "provider_link_request" || source == "household_invite" { return of("mail-check", people) }
        if source == "client_message" { return of("message-circle", people) }
        if source == "provider_follow_up" && n.category == "records_documentation" { return of("file-text", record) }
        if source == "provider_follow_up" || source == "provider_recall" || source == "household_record_follow_up" { return of("clipboard-check", record) }
        if source.contains("appointment") { return of("calendar-days", agenda) }
        if source.contains("record") || source == "missing_documentation" { return of("file-text", record) }
        if source.contains("routine") { return of("repeat", (Hue.butter.color, Hue.butter.ink)) }
        if source == "auth_sign_in" { return of("shield-check", plain) }
        if source.hasPrefix("household_member") || source == "household_invite_accepted" { return of("house", people) }
        switch n.category {
        case "appointments", "client_facing_reminders": return of("calendar-days", agenda)
        case "billing": return ("receipt", Theme.mango, Theme.inkStrong)
        case "records_documentation": return of("file-text", record)
        case "provider_follow_ups", "medical_follow_ups": return of("clipboard-check", record)
        case "client_messages", "provider_updates": return of("message-circle", people)
        case "provider_invitations": return of("mail-check", people)
        case "routines", "routine_checkins", "owner_tasks": return of("repeat", (Hue.butter.color, Hue.butter.ink))
        case "care_supplies": return of("pill", (Hue.sky.color, Hue.sky.ink))
        case "preventive_care": return of("syringe", record)
        case "security": return of("shield-check", plain)
        case "household_access": return n.contextType == "provider_workspace" ? of("users-round", people) : of("house", people)
        default: return of("bell", plain)
        }
    }

    /// A status tag's colour (web `STATUS_ACCENT`): overdue and urgent coral, due and needs-you mango, starts aqua.
    static func statusAccent(_ state: ProviderState) -> Color {
        switch state {
        case .problem: Theme.coral
        case .waiting: Theme.mango
        default: Theme.aqua
        }
    }
}

// MARK: - The screen

/// Notificaciones: the business's notifications, filtered by area, unread, what to show and for whom.
struct NotificationsScreen: View {
    @EnvironmentObject private var workspace: Workspace

    private static let categoryPermissions: [(String, Permission)] = [
        ("appointments", .notificationsAppointments),
        ("provider_follow_ups", .notificationsProviderFollowups),
        ("records_documentation", .notificationsRecordsDocumentation),
        ("billing", .notificationsBilling),
        ("client_messages", .notificationsClientMessages),
        ("client_facing_reminders", .notificationsClientFacingReminders),
    ]

    private var canView: Bool { Self.categoryPermissions.contains { workspace.can($0.1) } }

    var body: some View {
        Group {
            if canView {
                InboxNotificationsList()
            } else {
                PageScroll {
                    EmptyState(systemImage: "bell-off", title: L("No notification access"), message: L("Your role does not include notifications for this workspace. Ask the owner to change it."), panel: true)
                }
            }
        }
        .providerPage(L("Notifications"), root: true)
    }
}

private enum InboxShow: String, CaseIterable { case active, recent, all }
private enum InboxFor: String, CaseIterable { case all, mine, workspaceQueue = "workspace_queue" }

private struct InboxNotificationsList: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var area: InboxArea?
    @State private var unreadOnly = false
    @State private var show: InboxShow = .active
    @State private var forWhom: InboxFor = .all
    @State private var query = ""
    @State private var summary: InboxUnreadSummary?
    @State private var pushed: ProviderRoute?
    @State private var removing: InboxNotification?
    @State private var markingAll = false
    @State private var busyId: String?
    @StateObject private var pager = Pager<InboxNotification> { _, _ in Page(items: [], total: 0) }

    private var filtered: Bool { area != nil || unreadOnly || show != .active || forWhom != .all || query.nonEmpty != nil }

    var body: some View {
        PageScroll(refresh: { await reload() }) {
            header
            card
        }
        .debounced(query) { _ in await reload() }
        .task(id: workspace.scopeVersion) { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .pawMiawDataChanged)) { _ in Task { await loadSummary() } }
        .onChange(of: area) { _, _ in Task { await reload() } }
        .onChange(of: unreadOnly) { _, _ in Task { await reload() } }
        .onChange(of: show) { _, _ in Task { await reload() } }
        .onChange(of: forWhom) { _, _ in Task { await reload() } }
        .navigationDestination(item: $pushed) { RouteView(route: $0) }
        .sheet(item: $removing) { notification in
            ConfirmSheet(
                title: L("Remove this notification for the whole team?"),
                message: L("It leaves everyone’s list; the work behind it stays where it is."),
                confirmTitle: L("Remove"),
                destructive: true
            ) { _ in
                try await dismissNow(notification)
            }
        }
    }

    private func clearFilters() {
        area = nil
        unreadOnly = false
        show = .active
        forWhom = .all
        query = ""
    }

    // MARK: Header: the counts, mark all, preferences

    private var header: some View {
        let unread = summary?.unreadCount ?? 0
        let urgent = summary?.urgentUnreadCount ?? 0
        return ModuleHeader(
            icon: "bell",
            title: L("Notifications"),
            subtitle: L("Everything your workspace needs to know, newest first: what needs you, what changed, and what is coming up."),
            accent: Theme.aqua,
            stats: [
                ModuleStat("unread", label: L("Unread@stat"), value: summary?.unreadCount.map(String.init) ?? "—",
                           hint: urgent > 0 ? (urgent == 1 ? L("1 urgent") : LF("%d urgent", urgent)) : L("Not opened yet"),
                           icon: "bell", accent: Theme.coral, attention: unread > 0, active: unreadOnly,
                           action: { unreadOnly.toggle() }),
                ModuleStat("active", label: L("Active@stat"), value: summary?.activeCount.map(String.init) ?? "—",
                           hint: L("In the list now"), icon: "inbox", accent: Theme.aqua, active: !filtered,
                           action: clearFilters),
            ],
            storageKey: "notifications"
        ) {
            if unread > 0 {
                PMButton(markingAll ? L("Marking…") : L("Mark all as read"), systemImage: "check-check", isWorking: markingAll) {
                    Task { await markAllRead() }
                }
            }
            Button { pushed = .section(.notificationSettings) } label: { Glyph("settings", size: 16) }
                .buttonStyle(.pm(.outline, size: .header))
                .accessibilityLabel(L("Notification preferences"))
        }
    }

    // MARK: The card: search, what and whose, the areas, the list

    private var card: some View {
        Card(padding: 0, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    SearchField(prompt: L("Client, pet or text"), text: $query)
                        .accessibilityLabel(L("Search notifications"))
                    HStack(spacing: 8) {
                        Menu {
                            Picker(L("Show"), selection: $show) {
                                Text(L("Active@show")).tag(InboxShow.active)
                                Text(L("Last 30 days")).tag(InboxShow.recent)
                                Text(L("All, including dismissed")).tag(InboxShow.all)
                            }
                        } label: {
                            PillField(text: showTitle, height: 48)
                        }
                        .accessibilityLabel(L("Show"))
                        Menu {
                            Picker(L("For"), selection: $forWhom) {
                                Text(L("Everyone@for")).tag(InboxFor.all)
                                Text(L("Only me")).tag(InboxFor.mine)
                                Text(L("Team queue")).tag(InboxFor.workspaceQueue)
                            }
                        } label: {
                            PillField(text: forTitle, height: 48)
                        }
                        .accessibilityLabel(L("For"))
                        Spacer(minLength: 0)
                    }
                    chips
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                RowDivider()
                feed
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    private var showTitle: String {
        switch show {
        case .active: L("Active@show")
        case .recent: L("Last 30 days")
        case .all: L("All, including dismissed")
        }
    }

    private var forTitle: String {
        switch forWhom {
        case .all: L("Everyone@for")
        case .mine: L("Only me")
        case .workspaceQueue: L("Team queue")
        }
    }

    private var areaCounts: [InboxArea: Int]? {
        guard let counts = summary?.categoryCounts else { return nil }
        var totals: [InboxArea: Int] = [:]
        for (category, count) in counts {
            totals[InboxArea.of(category), default: 0] += unreadOnly ? (count.unread ?? 0) : (count.active ?? 0)
        }
        return totals
    }

    /// All · Unread · one chip per area that has something (web `NotificationFilterChips`).
    private var chips: some View {
        let counts = areaCounts
        let areas = InboxArea.allCases.filter { counts == nil || (counts?[$0] ?? 0) > 0 || area == $0 }
        return FlowLayout(spacing: 6) {
            FilterChip(title: L("All@notification"), count: summary?.activeCount, isSelected: area == nil && !unreadOnly, solid: true) {
                area = nil
                unreadOnly = false
            }
            FilterChip(title: L("Unread"), count: summary?.unreadCount, isSelected: unreadOnly, solid: true) { unreadOnly.toggle() }
            ForEach(areas) { option in
                FilterChip(title: option.label, count: counts?[option], isSelected: area == option, solid: true) {
                    area = area == option ? nil : option
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Filter notifications"))
    }

    // MARK: The list, by day

    @ViewBuilder
    private var feed: some View {
        if !pager.loadedOnce && pager.isLoading {
            LoadingState()
        } else if let error = pager.error, pager.items.isEmpty {
            ErrorState(message: L("Could not load notifications.") + " " + error) { await reload() }
        } else if pager.items.isEmpty {
            empty
        } else {
            let now = Date()
            let groups = InboxNotificationText.TimeGroup.allCases.compactMap { group -> (InboxNotificationText.TimeGroup, [InboxNotification])? in
                let items = pager.items.filter { InboxNotificationText.timeGroup(DateText.parse($0.createdAt) ?? now, now: now) == group }
                return items.isEmpty ? nil : (group, items)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.0) { index, entry in
                    if index > 0 { RowDivider() }
                    Text(entry.0.label.uppercased())
                        .font(.brandText(12, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface)
                        .overlay(alignment: .bottom) { RowDivider() }
                    ForEach(Array(entry.1.enumerated()), id: \.element.id) { position, notification in
                        if position > 0 { RowDivider() }
                        InboxSwipeAway(enabled: !notification.closed && busyId != notification.id, onRemove: { remove(notification) }) {
                            InboxNotificationRow(notification: notification, busy: busyId == notification.id, now: now,
                                                 openChart: chartAction(notification), onRemove: notification.closed ? nil : { remove(notification) }) {
                                open(notification)
                            }
                        }
                        .onAppear { pager.loadMoreIfNeeded(notification) }
                    }
                }
                PagerFooter(pager: pager)
            }
            if let total = pager.total, total > 0 {
                RowDivider()
                Text(LF("%d–%d of %d", 1, pager.items.count, total))
                    .font(Theme.text(14)).monospacedDigit().foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }

    private var empty: some View {
        let typed = query.nonEmpty
        let title: String = {
            if let typed { return LF("Nothing matches “%@”", typed) }
            if let area { return LF("Nothing in %@", area.label) }
            return unreadOnly ? L("Nothing unread") : L("You’re all caught up")
        }()
        let body: String = typed != nil ? L("Try another word, or clear the filters.") : (area != nil ? L("Nothing here needs you right now.") : (unreadOnly ? L("Everything here has been read.") : L("New reminders and updates will show up here.")))
        return VStack(spacing: 0) {
            EmptyState(systemImage: "check-check", title: title, message: body, accent: Theme.aqua)
            if filtered {
                PMButton(L("Show everything"), variant: .outline, size: .compact, action: clearFilters)
                    .padding(.top, -12)
                    .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Loading

    private func reload() async {
        let categories = area?.categories.joined(separator: ",")
        let status = show.rawValue
        let assigned = forWhom.rawValue
        let unread = unreadOnly ? "true" : nil
        let search = query.nonEmpty
        let wanted = area.map { Set($0.categories) }
        let onlyUnread = unreadOnly
        pager.fetch = { offset, limit in
            let page: Page<InboxNotification> = try await API.get("/provider-notifications", query: [
                "status": status, "limit": "\(limit)", "offset": "\(offset)",
                "categories": categories, "unread": unread, "assigned": assigned, "search": search,
            ])
            // An older server ignores the area and unread filters: the list keeps true to the chip either way.
            let items = page.items.filter { (wanted == nil || wanted!.contains($0.category ?? "")) && (!onlyUnread || $0.readAt == nil) }
            return Page(items: items, total: page.total, hasMore: page.hasMore)
        }
        async let summaryLoad: Void = loadSummary()
        await pager.reload()
        await summaryLoad
    }

    private func loadSummary() async {
        if let fresh: InboxUnreadSummary = try? await API.get("/provider-notifications/unread-summary") { summary = fresh }
    }

    // MARK: Actions

    /// Opens it at once and marks it read on the way (or, for a receipt that only informs, removes it).
    private func open(_ notification: InboxNotification) {
        if !notification.closed && InboxNotificationText.autoDismissOnView(notification) {
            Task { await quietly("/notifications/\(notification.id)/dismiss", notification) }
        } else if notification.unread && notification.sourceType != "system" {
            Task { await quietly("/notifications/\(notification.id)/read", notification) }
        }
        // Some open the work itself (the web's "open in place"): it may need the follow-up read first.
        if InboxNotificationWork.handles(notification) {
            guard busyId == nil else { return }
            busyId = notification.id
            Task {
                defer { busyId = nil }
                switch await InboxNotificationWork.open(notification, workspace: workspace) {
                case .push(let route): pushed = route
                case .stay: break
                case .page: if let route = InboxNotificationText.route(notification) { pushed = route }
                }
            }
            return
        }
        if let route = InboxNotificationText.route(notification) { pushed = route }
    }

    /// The pet's name opens its chart (web notification-feed.tsx), for someone who sees clients.
    private func chartAction(_ notification: InboxNotification) -> (() -> Void)? {
        guard workspace.can(.clientsView), notification.petName?.nonEmpty != nil,
              let petId = notification.pet?.providerClientPetId?.nonEmpty else { return nil }
        let clientId = notification.pet?.clientId?.nonEmpty
        return { pushed = clientId.map { ProviderRoute.clientPet(clientId: $0, petId: petId) } ?? .patientChart(petId: petId) }
    }

    private func quietly(_ path: String, _ notification: InboxNotification) async {
        do {
            let updated: InboxNotification = try await API.post(path)
            if updated.closed && show == .active { pager.remove(id: updated.id) } else { pager.replace(updated) }
            await loadSummary()
            announceDataChanged()
        } catch {
            // Opening never waits on this; the next read of the list says how it stands.
        }
    }

    /// A team's shared notice is asked about first; one's own leaves at once.
    private func remove(_ notification: InboxNotification) {
        if notification.recipientScope == "workspace_queue" {
            removing = notification
        } else {
            Task {
                do { try await dismissNow(notification) } catch { Toast.error(error, fallback: L("Could not remove it.")) }
            }
        }
    }

    private func dismissNow(_ notification: InboxNotification) async throws {
        busyId = notification.id
        defer { busyId = nil }
        let updated: InboxNotification = try await API.post("/notifications/\(notification.id)/dismiss")
        if show == .all { pager.replace(updated) } else { pager.remove(id: updated.id) }
        Toast.show(L("Notification removed."))
        await loadSummary()
        announceDataChanged()
    }

    private func markAllRead() async {
        markingAll = true
        defer { markingAll = false }
        do {
            try await API.send("POST", "/provider-notifications/read-all")
            Toast.show(L("All marked as read."))
            await reload()
            announceDataChanged()
        } catch {
            Toast.error(error, fallback: L("Could not mark them as read. Try again."))
        }
    }
}

// MARK: - Pieces

/// A row that leaves by a swipe to the LEFT (web `useSwipeAway`): it follows the finger over a coral
/// "Quitar" band, and goes once past a third of its width (or on a quick flick); short of that it
/// springs back. A vertical drag is left to the list.
private struct InboxSwipeAway<Content: View>: View {
    let enabled: Bool
    let onRemove: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var horizontal: Bool?

    private var armed: Bool { -offset > max(80, width * 0.35) }

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text(L("Remove")).font(.brandText(14, weight: .heavy)).opacity(armed ? 1 : 0.7)
                    Glyph("trash-2", size: 20).scaleEffect(armed ? 1.25 : 1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.coral)
                .animation(.easeOut(duration: 0.15), value: armed)
                .accessibilityHidden(true)
            }
            content().offset(x: offset)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .clipped()
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard enabled else { return }
                    if horizontal == nil { horizontal = abs(value.translation.width) > abs(value.translation.height) }
                    guard horizontal == true else { return }
                    offset = min(0, value.translation.width)
                }
                .onEnded { value in
                    defer { horizontal = nil }
                    guard enabled, horizontal == true else { return }
                    let flick = value.predictedEndTranslation.width < -max(160, width * 0.6)
                    if armed || flick {
                        withAnimation(.easeOut(duration: 0.22)) { offset = -width }
                        Task {
                            try? await Task.sleep(for: .milliseconds(220))
                            onRemove()
                            // Kept after all (a team's notice asked about, a refusal): it comes back.
                            try? await Task.sleep(for: .milliseconds(700))
                            withAnimation(.spring(duration: 0.3)) { offset = 0 }
                        }
                    } else {
                        withAnimation(.spring(duration: 0.3)) { offset = 0 }
                    }
                }
        )
    }
}

/// One notification (web `NotificationRow`): what it is about (icon), what happened (title and a line),
/// whether it needs anything (a tag only when it does), when, and the one thing to do next. The whole row
/// is that next step; it leaves by a swipe to the left (and the ✕ on an iPad).
private struct InboxNotificationRow: View {
    let notification: InboxNotification
    let busy: Bool
    let now: Date
    /// The pet's name as a link to its chart, above the row's own tap.
    var openChart: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    let open: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let look = InboxNotificationText.look(notification)
        let status = InboxNotificationText.status(notification, now: now)
        let subject = [notification.clientName, notification.petName].compactMap { $0?.nonEmpty }.joined(separator: " · ")
        let unread = notification.unread && !notification.closed
        let body = InboxNotificationText.body(notification)
        HStack(alignment: .top, spacing: 12) {
            Glyph(look.icon, size: 17.6)
                .foregroundStyle(look.ink)
                .frame(width: 40, height: 40)
                .background(Theme.wash(look.accent, notification.closed ? 10 : 24), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.mix(look.accent, 50, with: Theme.borderSoft), lineWidth: 1))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if unread {
                        Circle().fill(Theme.coral).frame(width: 8, height: 8).accessibilityLabel(L("Unread"))
                    }
                    Text(InboxNotificationText.title(notification))
                        .font(.brandHeading(16, relativeTo: .headline))
                        .foregroundStyle(Theme.inkStrong)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.trailing, sizeClass == .regular && onRemove != nil ? 32 : 0)
                if !body.isEmpty {
                    Text(body).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(3).multilineTextAlignment(.leading)
                        .padding(.top, 2)
                }
                if status != nil || !subject.isEmpty || notification.closed {
                    FlowLayout(spacing: 8) {
                        if let status { Chip(text: status.text, tone: .custom(InboxNotificationText.statusAccent(status.state)), dot: InboxNotificationText.statusAccent(status.state), percent: 16, border: 55, size: .medium) }
                        if notification.closed {
                            Text(notification.resolvedAt != nil ? L("Done@notification") : L("Dismissed"))
                                .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                                .frame(minHeight: 24)
                        }
                        if let openChart, let petName = notification.petName?.nonEmpty {
                            HStack(spacing: 0) {
                                if let client = notification.clientName?.nonEmpty {
                                    Text("\(client) · ").font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                                }
                                Button(action: openChart) {
                                    Text(petName).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(LF("Open %@’s chart", petName))
                            }
                            .lineLimit(1)
                            .frame(minHeight: 24)
                        } else if !subject.isEmpty {
                            Text(subject).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                                .frame(minHeight: 24)
                        }
                    }
                    .padding(.top, 8)
                }
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text(InboxNotificationText.actionLabel(notification)).lineLimit(1)
                        Glyph("arrow-right", size: 14)
                    }
                    .font(.brandText(13.1, weight: .heavy))
                    .foregroundStyle(Theme.blue)
                    Spacer(minLength: 0)
                    Text(InboxNotificationText.time(notification.createdAt, now: now))
                        .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opaque either way: it covers the band behind it until it is swiped.
        .background(unread ? AnyShapeStyle(Theme.wash(Theme.aqua, 13)) : AnyShapeStyle(Theme.surface))
        .overlay(alignment: .topTrailing) {
            if sizeClass == .regular, let onRemove {
                Button(action: onRemove) {
                    Glyph("x", size: 16).foregroundStyle(Theme.inkSoft).frame(width: 40, height: 40).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel(LF("Remove “%@”", InboxNotificationText.title(notification)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !busy { open() } }
        .allowsHitTesting(!busy)
        .opacity(busy ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !busy { open() } }
        .accessibilityActions {
            if let openChart, let petName = notification.petName?.nonEmpty {
                Button(LF("Open %@’s chart", petName), action: openChart)
            }
            if let onRemove {
                Button(L("Remove"), action: onRemove)
            }
        }
        .accessibilityHint(notification.closed ? "" : L("Swipe left to remove it."))
    }
}
