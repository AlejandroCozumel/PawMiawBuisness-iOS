//
//  NotificationSettingsScreen.swift
//  PawMiawNegocios
//
//  Your notifications (web: Settings › Your notifications,
//  components/app/settings/notifications-section.tsx): which alerts from
//  this workspace reach this person, in the app or by email, and how far
//  ahead. Each teammate chooses their own. "News and offers" saves at once.
//

import SwiftUI

/// The old address of the notification settings. On the web it redirects to
/// Settings › Your notifications; here it opens that same section, under
/// Settings' header.
struct NotificationSettingsScreen: View {
    var body: some View {
        TeamSettingsSectionScreen(section: "notifications")
    }
}

private struct TeamNotificationChoice: Equatable {
    let category: String
    var inApp: Bool
    var email: Bool
    var push: Bool
    var leadTimes: [Int]
}

private struct TeamTiming {
    let title: String
    let description: String
    let options: [(value: Int, label: String)]
    let defaults: [Int]
}

private enum TeamNotificationCopy {
    /// The workspace's kinds of alert, in order.
    static let categories = ["appointments", "provider_follow_ups", "records_documentation", "billing", "client_messages", "client_facing_reminders", "security"]
    static let emailByDefault: Set<String> = ["appointments", "provider_follow_ups", "records_documentation", "billing", "client_facing_reminders", "security"]

    static func label(_ category: String) -> String {
        switch category {
        case "appointments": L("Appointments")
        case "provider_follow_ups": L("Provider follow-ups")
        case "records_documentation": L("Records and documentation")
        case "billing": L("Billing")
        case "client_messages": L("Client messages")
        case "client_facing_reminders": L("Client reminders")
        case "security": L("Security")
        default: category
        }
    }

    static func description(_ category: String) -> String {
        switch category {
        case "appointments": L("Upcoming visits and what to get ready for them.")
        case "provider_follow_ups": L("Follow-ups your team has to make: calls, rechecks and reminders that are due.")
        case "records_documentation": L("Missing documents, chart updates, and record paperwork.")
        case "billing": L("Bills, payment reminders and what is still owed.")
        case "client_messages": L("Messages from clients that are waiting for an answer.")
        case "client_facing_reminders": L("The reminders your business sends to its clients.")
        case "security": L("Account security and sensitive access events.")
        default: ""
        }
    }

    static func icon(_ category: String) -> String {
        switch category {
        case "appointments": "calendar-clock"
        case "provider_follow_ups": "clipboard-check"
        case "records_documentation": "file-text"
        case "billing": "credit-card"
        case "client_messages": "message-circle"
        case "client_facing_reminders": "bell"
        case "security": "lock"
        default: "bell"
        }
    }

    /// The web's accent for each kind of alert (CATEGORY_META).
    static func accent(_ category: String) -> Color {
        switch category {
        case "appointments", "client_messages": Theme.pink
        case "provider_follow_ups", "client_facing_reminders": Theme.lime
        case "records_documentation": Theme.aqua
        case "billing", "security": Theme.mango
        default: Theme.aqua
        }
    }

    static func timing(_ category: String) -> TeamTiming? {
        let day = 24 * 60
        switch category {
        case "appointments":
            return TeamTiming(title: L("Appointment reminders"), description: L("How long before each visit you are reminded."), options: [(day, L("24h before")), (60, L("1h before")), (0, L("At visit time"))], defaults: [day, 60, 0])
        case "provider_follow_ups":
            return TeamTiming(title: L("Follow-up reminders"), description: L("How long before a follow-up is due you are reminded."), options: [(day, L("1d before")), (60, L("1h before")), (0, L("Due time"))], defaults: [60, 0])
        case "records_documentation":
            return TeamTiming(title: L("Record reminders"), description: L("How long before a record is due you are reminded."), options: [(day, L("1d before")), (60, L("1h before")), (0, L("Due time"))], defaults: [60, 0])
        case "billing":
            return TeamTiming(title: L("Bill reminders"), description: L("How long before a bill is due you are reminded."), options: [(3 * day, L("3d before")), (day, L("1d before")), (0, L("Due day"))], defaults: [day])
        case "client_facing_reminders":
            return TeamTiming(title: L("Client reminders"), description: L("How long before the due date they go out."), options: [(7 * day, L("7d before")), (day, L("1d before")), (0, L("Due day"))], defaults: [day, 0])
        default:
            return nil
        }
    }

    static func notice(_ category: String) -> (title: String, description: String) {
        switch category {
        case "client_messages": (L("Message alert"), L("Sent as soon as a message needs an answer."))
        case "security": (L("Security alert"), L("Sent right away for sensitive account or session activity."))
        default: (L("Sent when it happens"), L("Sent when it happens: there is no timing to choose."))
        }
    }

    static func normalized(_ category: String, _ values: [Int]?) -> [Int] {
        guard let timing = timing(category) else { return values?.isEmpty == false ? values! : [24 * 60, 0] }
        let allowed = Set(timing.options.map(\.value))
        var seen = Set<Int>()
        let kept = (values ?? []).filter { allowed.contains($0) && seen.insert($0).inserted }
        return kept.isEmpty ? timing.defaults : kept
    }
}

/// Which alerts from this workspace reach this person, and how.
struct TeamNotificationsSection: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var saved: [TeamNotificationChoice] = []
    @State private var draft: [TeamNotificationChoice] = []
    @State private var channels: [TeamNotificationChannel] = []
    @State private var timezone = TimeZone.current.identifier
    @State private var loaded = false
    @State private var failed = false
    @State private var saving = false
    @State private var marketing: Bool?
    @State private var marketingFailed = false
    @State private var savingMarketing = false
    @StateObject private var flash = TeamSavedFlash()

    var body: some View {
        TeamSaveSection(
            title: L("Your notifications"),
            subtitle: L("Which alerts from this workspace reach you, and how. Each teammate chooses their own."),
            systemImage: "bell",
            tint: Theme.aqua,
            look: .settings,
            state: flash.state(saving: saving, dirty: draft != saved),
            saveLabel: L("Save notifications"),
            onSave: loaded ? { save() } : nil,
            onDiscard: { draft = saved }
        ) {
            if !loaded {
                if failed {
                    VStack(spacing: 12) {
                        Text(L("Could not load your notifications.")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        PMButton(L("Try again"), variant: .outline) { Task { await load() } }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 32)
                    .frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 96)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        FlowLayout(spacing: 8) {
                            countPill(LF("%1$d/%2$d on in-app", draft.filter(\.inApp).count, draft.count), icon: "monitor-check", accent: Theme.lime)
                            countPill(LF("%1$d/%2$d on email", draft.filter(\.email).count, draft.count), icon: "mail", accent: Theme.aqua)
                        }
                        Text(L("In the app they show on the bell; by email they go to the address of your account.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    }
                    timezoneField
                    VStack(spacing: 0) {
                        ForEach($draft, id: \.category) { $item in
                            RowDivider()
                            categoryRow($item)
                        }
                        RowDivider()
                    }
                    .padding(.horizontal, -16)
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Glyph("smartphone", size: 16)
                            Glyph("message-circle", size: 16)
                        }
                        .foregroundStyle(Theme.blue)
                        Text(LF("%@ remain unavailable until those delivery systems are enabled.", futureChannels))
                    }
                    .font(Theme.text(14, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    marketingGroup
                }
            }
        }
        .reloadsOnScope { await load(); await loadMarketing() }
    }

    /// "9/9 en la app": a count pill on the channel's colour.
    private func countPill(_ text: String, icon: String, accent: Color) -> some View {
        HStack(spacing: 6) {
            Glyph(icon, size: 14)
            Text(text)
        }
        .font(Theme.text(14, weight: .semibold))
        .foregroundStyle(Theme.inkOnBright)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(accent, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.blue, lineWidth: 1))
    }

    /// The time zone reminders are scheduled in (read-only, as on the web).
    private var timezoneField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Timezone").uppercased()).font(Theme.text(12, weight: .bold)).tracking(1.7).foregroundStyle(Theme.inkSoft)
            HStack(spacing: 8) {
                Glyph("globe", size: 16).foregroundStyle(Theme.blue)
                Text(TeamHours.zoneLabel(timezone)).lineLimit(1)
            }
            .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            Text(L("Used to schedule appointment, preventive care, and follow-up reminders.")).font(Theme.text(11.2, weight: .medium)).foregroundStyle(Theme.inkSoft)
        }
    }

    /// "Novedades y ofertas": saves the moment it is switched.
    private var marketingGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("News and offers").uppercased()).font(Theme.text(11, weight: .heavy)).tracking(0.8).foregroundStyle(Theme.inkSoft)
                Text(L("Reminders, messages and security emails do not depend on this.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 6)
            if marketingFailed && marketing == nil {
                NoticeCard(tone: .problem, title: L("Could not load your notification settings."), actionTitle: L("Try again")) { Task { await loadMarketing() } }
            } else {
                ToggleRow(title: L("Email"), subtitle: L("Now and then, about what Paw Miaw can do and its plans."), isOn: Binding(get: { marketing ?? false }, set: { changeMarketing($0) }))
                    .disabled(marketing == nil || savingMarketing)
            }
        }
    }

    private var futureChannels: String {
        let list = channels.filter { !($0.availableNow ?? false) && $0.key != "push" }.compactMap(\.label)
        return list.isEmpty ? "SMS, WhatsApp" : list.joined(separator: ", ")
    }

    private func categoryRow(_ item: Binding<TeamNotificationChoice>) -> some View {
        let category = item.wrappedValue.category
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    IconBadge(icon: TeamNotificationCopy.icon(category), accent: TeamNotificationCopy.accent(category), size: 40, iconSize: 16, ink: .strong)
                        .overlay(Circle().strokeBorder(Theme.blue, lineWidth: 1))
                    Text(TeamNotificationCopy.label(category)).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
                }
                Text(TeamNotificationCopy.description(category)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            if let timing = TeamNotificationCopy.timing(category) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Glyph("clock-3", size: 16).foregroundStyle(Theme.blue)
                        Text(timing.title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    }
                    Text(timing.description).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    FlowLayout(spacing: 8) {
                        ForEach(timing.options, id: \.value) { option in
                            let on = item.wrappedValue.leadTimes.contains(option.value)
                            Button {
                                var next = Set(item.wrappedValue.leadTimes)
                                if on { if next.count > 1 { next.remove(option.value) } } else { next.insert(option.value) }
                                item.wrappedValue.leadTimes = timing.options.map(\.value).filter { next.contains($0) }
                            } label: {
                                Text(option.label)
                                    .font(Theme.text(12, weight: .bold))
                                    .foregroundStyle(on ? Theme.inkStrong : Theme.inkSoft)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 36)
                                    .background(on ? AnyShapeStyle(Theme.wash(Theme.lime, 42)) : AnyShapeStyle(Theme.surface), in: Capsule())
                                    .overlay(Capsule().strokeBorder(on ? Theme.blue : Theme.borderSoft, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(saving)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            } else {
                let notice = TeamNotificationCopy.notice(category)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Glyph("bell", size: 16).foregroundStyle(Theme.blue)
                        Text(notice.title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    }
                    Text(notice.description).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                channelToggle(L("In-app"), icon: "monitor-check", accent: Theme.lime, isOn: item.inApp)
                channelToggle(L("Email"), icon: "mail", accent: Theme.aqua, isOn: item.email)
            }
        }
        .padding(16)
    }

    /// A channel's switch (web `ChannelToggle`): a 40 pill washed in its colour when on.
    private func channelToggle(_ title: String, icon: String, accent: Color, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                Glyph(icon, size: 16).foregroundStyle(Theme.blue)
                Text(title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
            }
        }
        .toggleStyle(PMSwitchStyle())
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(isOn.wrappedValue ? AnyShapeStyle(Theme.wash(accent, 34)) : AnyShapeStyle(Theme.surfaceMuted), in: Capsule())
        .overlay(Capsule().strokeBorder(isOn.wrappedValue ? Theme.blue : Theme.borderSoft, lineWidth: 2))
        .disabled(saving)
        .opacity(saving ? 0.6 : 1)
    }

    private func load() async {
        guard let clinicId = workspace.current?.clinicId else { return }
        do {
            let answer: TeamNotificationPreferences = try await API.get("/notification-preferences", query: ["contextType": "provider_workspace", "contextId": clinicId])
            let byCategory = Dictionary((answer.items ?? []).map { ($0.category, $0) }, uniquingKeysWith: { a, _ in a })
            let next = TeamNotificationCopy.categories.map { category -> TeamNotificationChoice in
                if let existing = byCategory[category] {
                    return TeamNotificationChoice(category: category, inApp: existing.inAppEnabled ?? true, email: existing.emailEnabled ?? false, push: existing.pushEnabled ?? true, leadTimes: TeamNotificationCopy.normalized(category, existing.reminderLeadTimes))
                }
                return TeamNotificationChoice(category: category, inApp: true, email: TeamNotificationCopy.emailByDefault.contains(category), push: true, leadTimes: TeamNotificationCopy.normalized(category, nil))
            }
            // The draft follows what is saved while it is untouched.
            if draft == saved { draft = next }
            saved = next
            channels = answer.channels ?? []
            if let zone = answer.items?.first?.timezone, !zone.isEmpty { timezone = zone }
            loaded = true
            failed = false
        } catch {
            failed = !loaded
        }
    }

    private func loadMarketing() async {
        do {
            let answer: TeamMarketingEmail = try await API.get("/notification-preferences/marketing-email")
            marketing = answer.enabled ?? false
            marketingFailed = false
        } catch { marketingFailed = true }
    }

    private func changeMarketing(_ next: Bool) {
        let before = marketing
        marketing = next
        savingMarketing = true
        Task {
            defer { savingMarketing = false }
            do {
                let answer: TeamMarketingEmail = try await API.put("/notification-preferences/marketing-email", body: ["enabled": next])
                marketing = answer.enabled ?? next
                Toast.show(next ? L("You will get news and offers by email.") : L("No more news and offers by email."))
            } catch {
                marketing = before
                Toast.error(errorText(error, fallback: L("Could not save. Try again.")))
            }
        }
    }

    private func save() {
        guard let clinicId = workspace.current?.clinicId else { return }
        // Only the rows that were changed are written: a choice nobody made is never saved for them.
        let changed = draft.filter { item in !saved.contains(item) }
        guard !changed.isEmpty else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let _: EmptyResponse = try await API.put("/notification-preferences", body: [
                    "contextType": "provider_workspace",
                    "contextId": clinicId,
                    "timezone": timezone,
                    "categories": changed.map { ["category": $0.category, "inAppEnabled": $0.inApp, "emailEnabled": $0.email, "pushEnabled": $0.push, "smsEnabled": false, "reminderLeadTimes": $0.leadTimes] as [String: Any] },
                ])
                saved = draft
                flash.mark()
                announceDataChanged()
            } catch {
                Toast.error(errorText(error, fallback: L("Could not save notification preferences.")))
            }
        }
    }
}
