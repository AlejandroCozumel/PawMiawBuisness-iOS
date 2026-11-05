//
//  DueScreen.swift
//  PawMiawNegocios
//
//  Due (web: routes/provider.due.tsx and due/due-list.tsx): who should come
//  back — vaccines and rechecks from follow-ups, grooming by each pet's
//  cadence — in three buckets, with a reminder (WhatsApp opens with the
//  message, or PawMiaw tells the family through the API) and a booking.
//  The app itself never sends a message: the reminder in PawMiaw is the
//  server's action, as on the web.
//
//  The page as the web draws it: the module header (its three numbers are
//  the bucket filter), the reason chips with "Próximos N días", then one
//  heading and one card per bucket, each row with the bucket's colour down
//  its left edge.
//

import SwiftUI

struct DueScreen: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.openURL) private var openURL
    @State private var windowDays = 30
    @State private var reason = "all"
    @State private var bucket: String?
    @State private var list: ClientsDueList?
    @State private var error: String?
    @State private var working: String?
    @State private var route: ProviderRoute?

    private static let windows = [7, 30, 60, 90]
    private static let reasons = ["all", "vaccine", "recheck", "grooming", "follow_up"]
    private static let buckets = ["overdue", "this_week", "later"]

    private var allowed: Bool { workspace.can(.followupsView) || workspace.can(.appointmentsCreate) }
    private var canRemind: Bool { workspace.can(.followupsEdit) || workspace.can(.appointmentsCreate) }
    private var canBook: Bool { workspace.can(.appointmentsCreate) && workspace.can(.clientsView) }
    /// Closing a follow-up, or putting it off, is working on follow-ups.
    private var canWorkFollowUps: Bool { workspace.can(.followupsEdit) }

    var body: some View {
        Group {
            if !allowed {
                PageScroll { NoAccessState(message: L("Ask the workspace owner to let your role see follow-ups.")) }
            } else {
                PageScroll(refresh: { await load() }) {
                    header
                    filters
                    content
                }
            }
        }
        .providerPage(L("Due"), root: true)
        .reloadsOnScope { await load() }
        .navigationDestination(item: $route) { RouteView(route: $0) }
    }

    /// The visit to book for a row: its pet, the service the follow-up knows (a vaccine as a vaccination, a recheck as a
    /// medical follow-up), the day it is due (today when that has passed) and the follow-up the visit answers.
    private func booking(_ item: ClientsDueItem) -> BookingPrefill {
        let serviceId: String? = {
            guard item.reason != "grooming" else { return nil }
            if let id = item.service?.id?.nonEmpty { return id }
            guard workspace.offers(.vet, .emergency) else { return nil }
            return item.reason == "vaccine" ? "vaccination" : "medical_follow_up"
        }()
        let due = DateText.parse(item.dueAt)
        let day = DateText.dayKey(due.map { $0 < Date() ? Date() : $0 } ?? Date(), zone: workspace.timeZone)
        return BookingPrefill(clientId: item.client.id, petId: item.pet.id, serviceId: serviceId, day: day, followUpId: item.followUpId)
    }

    private func load() async {
        guard allowed else { return }
        do {
            list = try await API.get("/provider-due", query: ["window": "\(windowDays)"])
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = errorText(error)
        }
    }

    // MARK: Header

    private var header: some View {
        ModuleHeader(
            icon: "bell-ring",
            title: L("Due"),
            subtitle: L("Who should come back — vaccines, rechecks and grooming — with a reminder and a booking in one tap."),
            stats: headerStats,
            storageKey: "due"
        )
    }

    /// The header's numbers are filters too: one bucket at a time.
    private var headerStats: [ModuleStat] {
        guard let counts = list?.counts else { return [] }
        let overdue = counts.overdue ?? 0
        return [
            ModuleStat("overdue", label: bucketTitle("overdue"), value: "\(overdue)", icon: "bell-ring", accent: Theme.pink,
                       attention: overdue > 0, active: bucket == "overdue", action: { toggleBucket("overdue") }),
            ModuleStat("week", label: bucketTitle("this_week"), value: "\(counts.thisWeek ?? 0)", icon: "calendar-plus", accent: Theme.mango,
                       active: bucket == "this_week", action: { toggleBucket("this_week") }),
            ModuleStat("later", label: bucketTitle("later"), value: "\(counts.later ?? 0)", icon: "calendar-clock", accent: Theme.aqua,
                       active: bucket == "later", action: { toggleBucket("later") }),
        ]
    }

    private func toggleBucket(_ key: String) { bucket = bucket == key ? nil : key }

    // MARK: Filters

    /// Each reason in its own colour (a dot), with how many; then how far ahead to look.
    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 6) {
                ForEach(Self.reasons, id: \.self) { key in
                    let count = list.map { key == "all" ? $0.items.count : $0.items.filter { $0.reason == key }.count }
                    FilterChip(title: reasonFilterLabel(key), count: count, isSelected: reason == key,
                               tone: key == "all" ? Theme.blue : reasonTone(key), dot: key == "all" ? nil : reasonTone(key)) { reason = key }
                }
            }
            HStack(spacing: 8) {
                Text(L("Next@window")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkSoft)
                Menu {
                    ForEach(Self.windows, id: \.self) { days in
                        Button {
                            windowDays = days
                            Task { await load() }
                        } label: {
                            if days == windowDays { GlyphLabel(LF("%d days", days), icon: "check") } else { Text(LF("%d days", days)) }
                        }
                    }
                } label: {
                    FilterMenuLabel(title: LF("%d days", windowDays))
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: The buckets

    @ViewBuilder
    private var content: some View {
        if let list {
            let items = list.items.filter { (reason == "all" || $0.reason == reason) && (bucket == nil || $0.bucket == bucket) }
            if items.isEmpty {
                if !list.items.isEmpty {
                    // Someone is due, just not under these filters.
                    EmptyState(systemImage: "bell-ring", title: L("Nothing here with these filters."), actionTitle: L("Show everything"), action: { reason = "all"; bucket = nil }, accent: Theme.pink, panel: true)
                } else {
                    EmptyState(systemImage: "bell-ring", title: L("Nobody is due in this window."), message: L("Vaccines and rechecks come from follow-ups; grooming comes from each pet’s last visit and cadence."), accent: Theme.pink, panel: true)
                }
            } else {
                ForEach(Self.buckets, id: \.self) { key in
                    let inBucket = items.filter { $0.bucket == key }
                    if !inBucket.isEmpty { bucketSection(key, inBucket) }
                }
            }
        } else if let error {
            ErrorState(message: error) { await load() }
        } else {
            LoadingState()
        }
    }

    /// A bucket: its dot, name and count over one card of rows.
    private func bucketSection(_ key: String, _ items: [ClientsDueItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(bucketTone(key)).frame(width: 10, height: 10)
                Text(bucketTitle(key)).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                Text("\(items.count)")
                    .font(Theme.text(12, weight: .heavy)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.surfaceMuted, in: Capsule())
            }
            Card(padding: 0, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { RowDivider() }
                        row(item, tone: bucketTone(key))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
        }
    }

    // MARK: A row

    private func row(_ item: ClientsDueItem, tone: Color) -> some View {
        let days = item.days ?? ClientsText.daysUntil(item.dueAt)
        let busy = working == item.key
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // The pet's photo and name open its chart.
                NavigationLink(value: ProviderRoute.clientPet(clientId: item.client.id, petId: item.pet.id)) {
                    PetAvatar(name: item.pet.name, species: item.pet.species, photoURL: item.pet.photoUrl, size: 48)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 4) {
                    FlowLayout(spacing: 8, lineSpacing: 4) {
                        NavigationLink(value: ProviderRoute.clientPet(clientId: item.client.id, petId: item.pet.id)) {
                            Text(item.pet.name).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        Chip(text: item.reason == "grooming" || item.title?.nonEmpty == nil ? reasonLabel(item.reason) : ClientsText.followUpTitle(item.title), tone: .custom(reasonTone(item.reason)), icon: reasonIcon(item.reason), percent: 26, ink: Theme.inkStrong)
                    }
                    meta(item, days: days)
                    chips(item)
                }
                Spacer(minLength: 0)
                // Calling the family from the row (iOS keeps it; the web's row has none).
                if let tel = ContactLinks.phone(item.client.phone) {
                    IconCircleButton(systemImage: "phone", label: L("Call")) { openURL(tel) }
                }
            }
            actions(item, busy: busy)
                .padding(.leading, 60)
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The bucket's colour down the left edge, as on Home: red is late, mango is this week.
        .overlay(alignment: .leading) { Rectangle().fill(tone).frame(width: 6) }
    }

    /// "3 days overdue · 4 nov · Carmen Vázquez · last visit 2 oct".
    private func meta(_ item: ClientsDueItem, days: Int) -> some View {
        FlowLayout(spacing: 6, lineSpacing: 2) {
            Text(ClientsText.dueWords(days)).font(Theme.text(12, weight: .bold))
                .foregroundStyle(item.bucket == "overdue" ? Theme.destructive : Theme.inkStrong)
            Text("·").font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            Text(ClientsText.shortDay(item.dueAt)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            Text("·").font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            NavigationLink(value: ProviderRoute.client(item.client.id)) {
                Text(item.client.name).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            .buttonStyle(.plain)
            if let last = item.lastVisitAt {
                Text("·").font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                Text(LF("last visit %@", ClientsText.shortDay(last))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    @ViewBuilder
    private func chips(_ item: ClientsDueItem) -> some View {
        let hasAny = item.missedVisitAt != nil || item.nextVisit != nil || item.snoozedUntil != nil || item.lastContact != nil || showsFamilyNotice(item)
        if hasAny {
            FlowLayout(spacing: 6) {
                if let missed = item.missedVisitAt {
                    // A visit cancelled before its day never "didn't happen": it was cancelled.
                    Chip(text: (DateText.parse(missed).map { $0 > Date() } ?? false) ? LF("The visit on %@ was cancelled", ClientsText.shortDay(missed)) : LF("The visit on %@ didn’t happen", ClientsText.shortDay(missed)), tone: .custom(Theme.mango), icon: "calendar-x-2", percent: 26, ink: Theme.inkStrong)
                }
                if let next = item.nextVisit {
                    // Already on the calendar: so nobody calls a family that has booked.
                    let booked = Chip(text: LF("Has a visit on %@: %@", ClientsText.shortDay(next.startsAt), next.serviceLabel ?? ""), tone: .custom(Theme.blue), icon: "calendar-check", percent: 14, ink: Theme.inkStrong)
                    if workspace.can(.appointmentsView) {
                        NavigationLink(value: ProviderRoute.appointment(next.id)) { booked }.buttonStyle(.plain)
                    } else {
                        booked
                    }
                }
                if let until = item.snoozedUntil {
                    Chip(text: LF("Postponed until %@", ClientsText.shortDay(until)), tone: .muted, icon: "clock-3", ink: Theme.inkStrong)
                }
                if showsFamilyNotice(item), let due = DateText.parse(item.dueAt) {
                    // PawMiaw tells the family a week before, once: so nobody sends it twice by hand.
                    Chip(text: LF("PawMiaw tells the family on %@", ClientsText.shortDay(DateText.iso(due.addingTimeInterval(-7 * 86_400)))), tone: .custom(Theme.blue), icon: "smartphone", percent: 14, ink: Theme.inkStrong)
                }
                if let contact = item.lastContact {
                    // Already told: so nobody messages the same family twice.
                    Chip(text: contact.channel == "whatsapp" ? LF("WhatsApp opened %@", ClientsText.shortDay(contact.at)) : LF("Reminded in PawMiaw %@", ClientsText.shortDay(contact.at)), tone: .custom(ProviderState.done.color), icon: "check-check", percent: 16, ink: Theme.inkStrong)
                }
            }
        }
    }

    private func actions(_ item: ClientsDueItem, busy: Bool) -> some View {
        FlowLayout(spacing: 8) {
            if canRemind, item.client.phone?.nonEmpty != nil {
                PMButton("WhatsApp", systemImage: "message-circle", variant: .outline, size: .compact, isWorking: busy) { remind(item, channel: "whatsapp") }
                    .disabled(working != nil)
            }
            if canRemind && item.client.onPawMiaw == true {
                PMButton(L("Remind in PawMiaw"), systemImage: "smartphone", variant: .outline, size: .compact) { remind(item, channel: "app") }
                    .disabled(working != nil)
            }
            if canBook {
                // Once the pet has a visit, booking is no longer the row's main thing.
                PMButton(L("Book"), systemImage: "calendar-plus", variant: item.nextVisit == nil ? .primary : .outline, size: .compact) { route = .bookVisit(booking(item)) }
            }
            if canWorkFollowUps && canRemind, item.followUpId != nil {
                Menu {
                    Button(L("1 week")) { snooze(item, days: 7) }
                    Button(L("2 weeks")) { snooze(item, days: 14) }
                    Button(L("1 month")) { snooze(item, days: 30) }
                } label: {
                    GlyphLabel(L("Postpone"), icon: "clock-3")
                }
                .buttonStyle(.pm(.outline, size: .compact))
                .disabled(working != nil)
                PMButton(L("Done"), systemImage: "circle-check", variant: .outline, size: .compact) { done(item) }
                    .disabled(working != nil)
                    .accessibilityHint(L("It was done, or it no longer applies: take it off the list."))
            }
        }
    }

    private func showsFamilyNotice(_ item: ClientsDueItem) -> Bool {
        item.familyNotice?.asked == true && item.familyNotice?.sentAt == nil && item.lastContact == nil && item.nextVisit == nil && item.snoozedUntil == nil && item.bucket != "overdue"
    }

    // MARK: Words and colours

    /// A bucket's name. Several things are late, so "Overdue" reads in the plural here ("Vencidos").
    private func bucketTitle(_ key: String) -> String {
        switch key {
        case "overdue": L("Overdue@plural")
        case "this_week": L("This week")
        default: L("Later")
        }
    }

    /// The bucket's state colour (web DUE_STATE): late red, this week mango, later light blue.
    private func bucketTone(_ key: String) -> Color {
        switch key {
        case "overdue": ProviderState.problem.color
        case "this_week": ProviderState.waiting.color
        default: ProviderState.upcoming.color
        }
    }

    private func reasonFilterLabel(_ key: String) -> String {
        switch key {
        case "all": L("All")
        case "vaccine": L("Vaccines")
        case "recheck": L("Rechecks")
        case "grooming": L("Grooming")
        default: L("Follow-ups")
        }
    }

    private func reasonLabel(_ key: String) -> String {
        switch key {
        case "vaccine": L("Vaccine")
        case "recheck": L("Recheck")
        case "grooming": L("Grooming")
        default: L("Follow-up")
        }
    }

    /// Each reason in its own hue, on the filter and on every row (web DUE_REASON_HUE).
    private func reasonTone(_ key: String) -> Color {
        switch key {
        case "vaccine": Hue.sky.color
        case "recheck": Hue.teal.color
        case "grooming": Hue.lavender.color
        default: Hue.periwinkle.color
        }
    }

    private func reasonIcon(_ key: String) -> String {
        switch key {
        case "grooming": "scissors"
        case "vaccine": "syringe"
        case "recheck": "stethoscope"
        default: "bell-ring"
        }
    }

    // MARK: Actions

    /// A reminder in PawMiaw (the server writes to the family), or a WhatsApp chat opened with the message.
    private func remind(_ item: ClientsDueItem, channel: String) {
        working = item.key
        let locale = LocalizationManager.shared.currentLanguage.rawValue
        Task {
            defer { working = nil }
            do {
                let result: ClientsRemindResult
                if let followUpId = item.followUpId {
                    result = try await API.post("/provider-follow-ups/\(followUpId)/remind", body: ["channel": channel, "locale": locale])
                } else {
                    result = try await API.post("/provider-due/remind", body: ["providerClientPetId": item.pet.id, "reason": "grooming", "channel": channel, "locale": locale])
                }
                if channel == "whatsapp", let link = result.link.flatMap(URL.init(string:)) {
                    openURL(link)
                    Toast.show(L("WhatsApp is open with the message."))
                } else {
                    Toast.show(L("Reminder sent in PawMiaw."))
                }
                await load()
            } catch {
                Toast.error(error)
            }
        }
    }

    /// Closing a follow-up from the list: it was done somewhere else, or no longer applies.
    private func done(_ item: ClientsDueItem) {
        guard let followUpId = item.followUpId else { return }
        working = item.key
        Task {
            defer { working = nil }
            do {
                let _: EmptyResponse = try await API.patch("/provider-follow-ups/\(followUpId)", body: ["status": "done"])
                Toast.show(L("Marked as done."))
                announceDataChanged()
            } catch {
                Toast.error(error)
            }
        }
    }

    /// Putting a follow-up off: N days after the later of today and the day it is due (the business's calendar).
    private func snooze(_ item: ClientsDueItem, days: Int) {
        guard let followUpId = item.followUpId else { return }
        let calendar = DateText.calendar
        let due = DateText.parse(item.dueAt) ?? Date()
        let from = calendar.startOfDay(for: max(due, Date()))
        let until = DateText.dayKey(calendar.date(byAdding: .day, value: days, to: from) ?? from)
        working = item.key
        Task {
            defer { working = nil }
            do {
                let _: EmptyResponse = try await API.patch("/provider-follow-ups/\(followUpId)", body: ["status": "snoozed", "snoozedUntil": until])
                Toast.show(LF("Postponed until %@.", ClientsText.shortDay(until)))
                announceDataChanged()
            } catch {
                Toast.error(error)
            }
        }
    }
}
