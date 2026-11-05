//
//  HomeVisitCard.swift
//  PawMiawNegocios
//
//  One home visit, read top to bottom on a phone in the street (web:
//  home-visits/visit-card.tsx): when, who, where (with the way there), whom
//  to call, how to get in, what to watch for with this pet, and one big
//  button for the next thing to do. Everything else is in "More".
//

import SwiftUI

struct SvcVisitHandlers {
    let arrive: (SvcHomeVisitItem) -> Void
    let finish: (SvcHomeVisitItem) -> Void
    let onMyWay: (SvcHomeVisitItem) -> Void
    let report: (SvcHomeVisitItem) -> Void
    let reassign: (SvcHomeVisitItem) -> Void
    let check: (SvcHomeVisitItem) -> Void
    let reveal: (SvcHomeVisitItem) -> Void
    let emergency: (SvcHomeVisitItem) -> Void
    let open: (SvcHomeVisitItem) -> Void
    /// A home stay's visit: "leave", "no-access", "undo", "missed".
    let stayMove: (SvcHomeVisitItem, String) -> Void
    let push: (ProviderRoute) -> Void
    /// A press the server refused: try it again, forget it, or settle the consent or deposit first.
    var retry: (String) -> Void = { _ in }
    var discard: (String) -> Void = { _ in }
    var reviewConsents: (SvcOutboxEntry, SvcHomeVisitItem) -> Void = { _, _ in }
}

enum SvcVault {
    static let fields = ["keys", "gateCode", "alarmCode", "wifiName", "wifiPassword", "parking", "houseRules", "hidingSpots", "notes"]

    static func label(_ field: String) -> String {
        switch field {
        case "keys": L("Keys")
        case "gateCode": L("Gate code")
        case "alarmCode": L("Alarm code")
        case "wifiName": L("Wi-Fi network")
        case "wifiPassword": L("Wi-Fi password")
        case "parking": L("Parking")
        case "houseRules": L("House rules")
        case "hidingSpots": L("Where the pets hide")
        default: L("Anything else")
        }
    }
}

/// One home visit, read top to bottom on a phone in the street (web `VisitCard`): when,
/// who, where (with the way there), whom to call, how to get in, what to watch for with
/// this pet, and one big button for the next thing to do. Everything else is in "More".
/// A finished visit folds to its essentials.
struct SvcVisitCard: View {
    let item: SvcHomeVisitItem
    let day: SvcHomeVisitsDay
    let now: Date
    let highlight: Bool
    let pressing: Bool
    let handlers: SvcVisitHandlers
    /// This phone's press not yet with the server.
    var pending: SvcPending? = nil
    /// This phone's presses the server refused.
    var failed: [SvcOutboxEntry] = []
    /// Set on the walk whose route this phone records.
    var tracker: SvcWalkTracker? = nil
    /// What the phone answered at this card's last press.
    var lastPosition: VisitPosition? = nil

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var viewer: SvcHomeViewer? { day.viewer }
    private var isManager: Bool { viewer?.isManager ?? false }
    private var canAct: Bool { viewer?.canAct ?? false }
    private var lateAfter: Int { day.settings?.lateAfterMinutes ?? 15 }
    private var lateInfo: (late: Bool, minutes: Int) { SvcHomeRules.late(item, now: now, lateAfter: lateAfter, isToday: day.isToday ?? false) }
    private var runningLong: Bool { SvcHomeRules.runningLong(item, now: now, lateAfter: lateAfter) }
    private var locationOn: Bool { day.settings?.locationStamps == true || day.settings?.walkRoutes == true }
    /// A report the person can write from here (a home stay's report card is written in its visit's sheet).
    private var canWriteReport: Bool { (item.isStay || item.reportKind != nil) && ["in_progress", "done"].contains(item.phase) && canAct }
    private var offersOnMyWay: Bool { item.actions?.onMyWay == true && item.onMyWay?.offered == true && item.onMyWay?.at == nil && item.phase == "upcoming" }

    /// Where the visit stands (web `visitChip`).
    private var chip: String {
        switch item.phase {
        case "missed": "missed"
        case "done": "done"
        case "in_progress": runningLong ? "running_long" : "in_progress"
        default: lateInfo.late ? "late" : (item.phase == "on_my_way" ? "on_my_way" : "upcoming")
        }
    }

    /// The state's colour: the card's edge and its pill (web `CHIP_TONE`).
    private func tone(_ chip: String) -> Color {
        switch chip {
        case "on_my_way", "in_progress": ProviderState.active.color
        case "running_long": ProviderState.waiting.color
        case "late", "missed": ProviderState.problem.color
        case "done": ProviderState.done.color
        default: ProviderState.upcoming.color
        }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topRow
            whoRow
            if item.closed {
                Text([item.client.name, item.arrivedAt.map { LF("Arrived at %@", SvcTime.clock($0, day.timeZone)) }, item.finishedAt.map { LF("Finished at %@", SvcTime.clock($0, day.timeZone)) }].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            } else {
                addressBlock
                clientRow
                accessBlock
                handlingBlock
                if let instructions = item.instructions?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
                    // A home stay carries the family's house rules; an appointment, the note written when it was booked.
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Glyph("notebook-text", size: 14).foregroundStyle(Theme.inkSoft)
                            Eyebrow(item.isStay ? L("House rules") : L("Visit notes"))
                        }
                        Text(instructions).font(Theme.text(15.2)).foregroundStyle(Theme.inkStrong)
                    }
                }
                if let checklist = item.checklist, checklist.total > 0, item.phase != "in_progress" {
                    Text(LF("Checklist · %d of %d", checklist.done, checklist.total)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkSoft)
                }
            }
            teamPills
            if item.phase == "in_progress" {
                SvcVisitTimer(item: item, timeZone: day.timeZone)
                if let tracker { SvcRouteRecording(tracker: tracker) }
            }
            if let pending { SvcPendingLine(pending: pending) }
            ForEach(failed) { entry in
                SvcOutboxRow(entry: entry, onRetry: { handlers.retry(entry.id) }, onDiscard: { handlers.discard(entry.id) }, onOpenVisit: { handlers.open(item) },
                             onReviewConsents: ["arrive", "stay_arrive"].contains(entry.kind) ? { handlers.reviewConsents(entry, item) } : nil)
            }
            actions
            if let quiet = quietReason { Text(quiet).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft) }
        }
        .padding(.vertical, sizeClass == .regular ? 20 : 16)
        .padding(.leading, (sizeClass == .regular ? 20 : 16) + 6)
        .padding(.trailing, sizeClass == .regular ? 20 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(alignment: .leading) { Rectangle().fill(tone(chip)).frame(width: 6) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(highlight ? AnyShapeStyle(Theme.mix(Theme.blue, 55, with: Theme.borderSoft)) : AnyShapeStyle(Theme.borderSoft), lineWidth: 1.5))
        .modifier(SvcCardShadow(on: !item.closed))
    }

    // MARK: When, and where the visit stands

    private var topRow: some View {
        // The window at the left, where the visit stands at the right; under it when they don't fit.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                window
                Spacer(minLength: 0)
                HStack(spacing: 6) { pills }.fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                window
                FlowLayout(spacing: 6) { pills }
            }
        }
    }

    private var window: some View {
        HStack(spacing: 6) {
            if item.kind == "overnight" { Glyph("moon-star", size: 20).foregroundStyle(Theme.blue) }
            Text(SvcHomeRules.window(item, day.timeZone)).font(.brandHeading(21.6)).monospacedDigit().foregroundStyle(Theme.inkStrong).lineLimit(1)
        }
        .fixedSize()
    }

    @ViewBuilder private var pills: some View {
        switch chip {
        case "late":
            Chip(text: LF("Late · %d min", lateInfo.minutes), tone: .custom(tone("late")), icon: "triangle-alert", percent: 26, weight: .heavy, border: 80, size: .large)
            if item.phase == "on_my_way" { Chip(text: onMyWayLabel, tone: .custom(tone("on_my_way")), icon: "navigation", percent: 16, weight: .heavy, border: 55, size: .large) }
        case "on_my_way": Chip(text: onMyWayLabel, tone: .custom(tone("on_my_way")), icon: "navigation", percent: 16, weight: .heavy, border: 55, size: .large)
        case "in_progress": Chip(text: L("Home visit · In progress"), tone: .custom(tone(chip)), icon: "door-open", percent: 26, weight: .heavy, border: 80, size: .large)
        case "running_long": Chip(text: L("Running long"), tone: .custom(tone(chip)), icon: "hourglass", percent: 26, weight: .heavy, border: 80, size: .large)
        case "done": Chip(text: L("Home visit · Done"), tone: .custom(tone(chip)), icon: "check-check", percent: 16, weight: .heavy, border: 55, size: .large)
        case "missed": Chip(text: L("Home visit · Missed"), tone: .custom(tone(chip)), icon: "timer-off", percent: 26, weight: .heavy, border: 80, size: .large)
        default: EmptyView()
        }
    }

    /// The family was told only when the notice went out in PawMiaw; by WhatsApp the chat just opened.
    private var onMyWayLabel: String {
        guard let at = item.onMyWay?.at else { return L("On the way") }
        let time = SvcTime.clock(at, day.timeZone)
        return item.onMyWay?.channel == "whatsapp" ? LF("On the way · WhatsApp opened %@", time) : LF("On the way · told at %@", time)
    }

    // MARK: Who

    private var whoRow: some View {
        HStack(spacing: 12) {
            PetStack(pets: item.pets.map { ($0.name, $0.species, $0.photoUrl) }, size: 48, max: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.petNames).font(.brandHeading(20.8)).foregroundStyle(Theme.inkStrong)
                Text(item.serviceText).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu { menuItems } label: {
                Glyph("ellipsis", size: 20).foregroundStyle(Theme.inkStrong)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().strokeBorder(Theme.borderSoft, lineWidth: 1.5))
                    .contentShape(Circle())
            }
            .accessibilityLabel(LF("More for %@", item.petNames))
        }
    }

    @ViewBuilder private var menuItems: some View {
        if !item.isStay && item.actions?.onMyWay == true && !offersOnMyWay {
            Button { handlers.onMyWay(item) } label: { GlyphLabel(L("On my way"), icon: "navigation") }
        }
        if canWriteReport {
            Button { handlers.report(item) } label: { GlyphLabel(item.hasReport == true ? L("Report") : L("Write report"), icon: "clipboard-pen") }
        }
        if item.actions?.reassign == true {
            Button { handlers.reassign(item) } label: { GlyphLabel(L("Reassign"), icon: "user-round-cog") }
        }
        if isManager && (item.stamps != nil || item.closed) {
            Button { handlers.check(item) } label: { GlyphLabel(L("Check the location"), icon: "locate-fixed") }
        }
        // A home stay's visit opens its own sheet: the checklist, the report card and every move.
        Button { handlers.open(item) } label: { GlyphLabel(L("Open visit"), icon: "external-link") }
        if item.isStay, let stay = item.stayId {
            Button { handlers.push(.stay(stay)) } label: { GlyphLabel(L("Open the home stay"), icon: "house") }
        }
    }

    // MARK: Where, and the way there

    @ViewBuilder private var addressBlock: some View {
        if let address = item.address {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Glyph("map-pin", size: 20).foregroundStyle(Theme.blue)
                    (Text(address.label?.nonEmpty.map { $0 + " · " } ?? "").fontWeight(.heavy) + Text(address.line?.nonEmpty ?? address.formatted ?? ""))
                        .font(Theme.text(16.3, weight: .bold)).foregroundStyle(Theme.inkStrong)
                }
                if let reference = address.reference?.nonEmpty {
                    Text(reference).font(Theme.text(14)).foregroundStyle(Theme.inkStrong).padding(.leading, 28)
                }
                if address.shared == false {
                    HStack(alignment: .top, spacing: 6) {
                        Glyph("triangle-alert", size: 14).padding(.top, 1)
                        Text(L("This address is no longer shared. This is how it was when the visit was booked."))
                    }
                    .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.wash(Theme.mango, 18), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                }
                let links = mapLinks(address)
                if let primary = links.first {
                    HStack(spacing: 8) {
                        PMButton(L("Directions"), systemImage: "navigation", variant: .outline, fullWidth: true) { svcOpen(primary.url) }
                        if links.count > 1 {
                            Menu {
                                ForEach(links.dropFirst(), id: \.url) { link in
                                    Button { svcOpen(link.url) } label: { GlyphLabel(link.title, icon: "map-pin") }
                                }
                            } label: {
                                Glyph("chevron-down", size: 20).foregroundStyle(Theme.blue)
                                    .frame(width: 48, height: 48)
                                    .background(Theme.surface, in: Circle())
                                    .overlay(Circle().strokeBorder(Theme.blue, lineWidth: 2))
                            }
                            .accessibilityLabel(L("Other map apps"))
                        }
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                Glyph("map-pin-off", size: 16)
                Text(L("No address yet"))
            }
            .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
    }

    /// Apple Maps first on this device, then the others the server gave.
    private func mapLinks(_ address: SvcHomeAddress) -> [(title: String, url: String)] {
        var out: [(title: String, url: String)] = []
        if let apple = address.maps?.apple { out.append((L("Open in Apple Maps"), apple)) }
        else if let text = (address.formatted ?? address.line)?.nonEmpty, let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            out.append((L("Open in Apple Maps"), "http://maps.apple.com/?daddr=\(encoded)"))
        }
        if let google = address.maps?.google { out.append((L("Open in Google Maps"), google)) }
        if let waze = address.maps?.waze { out.append((L("Open in Waze"), waze)) }
        return out
    }

    // MARK: Whom to call at the door

    private var clientRow: some View {
        HStack(spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Glyph("user-round", size: 20).foregroundStyle(Theme.inkSoft)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.client.name).font(Theme.text(15.7, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    if let phone = item.client.phone?.nonEmpty { Text(phone).font(Theme.text(12, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.inkSoft) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let tel = ContactLinks.phone(item.client.phone) {
                PMButton(L("Call"), systemImage: "phone", variant: .outline) { UIApplication.shared.open(tel) }
                    .accessibilityLabel(LF("Call %@", item.client.shortName))
            }
        }
    }

    // MARK: How to get in (the notes anyone assigned reads; the codes only through the audited reveal)

    @ViewBuilder private var accessBlock: some View {
        if let access = item.access, access.notes?.nonEmpty != nil || access.hasVault == true {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Glyph("key-round", size: 16).foregroundStyle(Theme.blue)
                    Text(L("Arrival & access"))
                }
                .font(Theme.text(14, weight: .heavy)).foregroundStyle(Theme.inkStrong)
                if let notes = access.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty { Text(notes).font(Theme.text(15.2)).foregroundStyle(Theme.inkStrong) }
                if access.hasVault == true {
                    FlowLayout(spacing: 6) {
                        ForEach(SvcVault.fields.filter { (access.fields ?? []).contains($0) }, id: \.self) { field in
                            HStack(spacing: 4) {
                                Glyph("lock", size: 12).foregroundStyle(Theme.inkSoft)
                                Text(SvcVault.label(field))
                            }
                            .font(.brandText(11.2, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
                        }
                    }
                    if access.canReveal == true {
                        PMButton(L("Show access details"), systemImage: "eye", variant: .outline, fullWidth: true) { handlers.reveal(item) }
                    } else if access.reason == "not_assigned" {
                        Text(L("Only the person assigned sees them.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    } else if access.reason == "window_closed" {
                        Text(L("They open from 30 minutes before the visit until it ends.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        if access.canEmergency == true {
                            PMButton(L("Emergency opening"), systemImage: "triangle-alert", variant: .destructive, fullWidth: true) { handlers.emergency(item) }
                        }
                    } else if access.reason == "family_off" {
                        Text(L("The family hasn’t shared its access details with your business.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wash(Theme.aqua, 9), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.aqua, 55, with: Theme.borderSoft), lineWidth: 1.5))
        }
    }

    // MARK: What to watch for with this pet

    @ViewBuilder private var handlingBlock: some View {
        let handling = item.pets.filter { !($0.handlingTags ?? []).isEmpty || $0.careNotes?.nonEmpty != nil || !($0.allergies ?? []).isEmpty }
        if !handling.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Glyph("shield-alert", size: 16)
                    Text(L("Handle with care"))
                }
                .font(Theme.text(14, weight: .heavy)).foregroundStyle(Theme.inkStrong)
                ForEach(handling) { pet in
                    VStack(alignment: .leading, spacing: 4) {
                        if item.pets.count > 1 { Text(pet.name).font(Theme.text(12, weight: .heavy)).foregroundStyle(Theme.inkStrong) }
                        // What they must not be given comes first: a treat at the door is the usual slip.
                        if let allergies = pet.allergies, !allergies.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Glyph("triangle-alert", size: 16).foregroundStyle(Theme.destructive).padding(.top, 1)
                                Text(allergyLine(allergies))
                            }
                            .font(Theme.text(14, weight: .heavy)).foregroundStyle(Theme.inkStrong)
                        }
                        SvcHandlingChips(tags: pet.handlingTags ?? [], large: true)
                        if let notes = pet.careNotes?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty { Text(notes).font(Theme.text(14)).foregroundStyle(Theme.inkStrong) }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wash(Theme.mango, 13), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.mango, 70, with: Theme.borderSoft), lineWidth: 1.5))
        }
    }

    /// "Allergy: chicken, beef" — or the chart's own words when they already say it.
    private func allergyLine(_ allergies: [String]) -> String {
        let list = allergies.joined(separator: ", ")
        let saysIt = allergies.allSatisfy { $0.lowercased().trimmingCharacters(in: .whitespaces).hasPrefix("alergi") || $0.lowercased().trimmingCharacters(in: .whitespaces).hasPrefix("allerg") }
        return saysIt ? list : LF("Allergy: %@", list)
    }

    // MARK: The team's side: who has it, and (owners and admins) how it went. Never a coordinate.

    @ViewBuilder private var teamPills: some View {
        let seesAll = viewer?.seesAll ?? false
        let short = isManager && item.shortVisit == true
        let stamps = stampLines
        if (seesAll && !item.closed) || short || !stamps.isEmpty || SvcBilling.label(item.billing) != nil || (seesAll && item.closed && item.assigned != nil) {
            FlowLayout(spacing: 6) {
                if seesAll { Chip(text: item.assigned.map { $0.name ?? "—" } ?? L("Unassigned"), tone: .custom(Theme.lavender), icon: "user-round", percent: 16, weight: .heavy, border: 55, size: .large) }
                if let label = SvcBilling.label(item.billing) { Chip(text: label, tone: .custom(SvcBilling.state(item.billing).color), icon: "receipt", percent: 16, weight: .heavy, border: 55, size: .large) }
                if short {
                    Chip(text: item.bookedMinutes != nil && item.arrivedAt != nil && item.finishedAt != nil
                                 ? LF("Short visit · %d of %d min", SvcTime.minutesBetween(item.arrivedAt, item.finishedAt), item.bookedMinutes ?? 0)
                                 : L("Short visit"), tone: .custom(Theme.mango), icon: "timer-off", percent: 26, weight: .heavy, border: 80, size: .large)
                }
                ForEach(stamps, id: \.0) { _, line in
                    Chip(text: line.text, tone: .custom(SvcHomeRules.stampTone(warn: line.warn, muted: line.muted)), icon: "locate-fixed", percent: (line.warn) ? 26 : 16, weight: .heavy, border: (line.warn) ? 80 : 55, size: .large)
                }
            }
        }
    }

    private var stampLines: [(String, (text: String, warn: Bool, muted: Bool))] {
        [("arrive", item.stamps?.arrive), ("finish", item.stamps?.finish)].compactMap { kind, stamp in SvcHomeRules.stampLine(kind, stamp, isManager: isManager).map { (kind, $0) } }
    }

    /// The quiet line under a card when this phone's press saved no position (never for a manager, who reads the stamps).
    private var quietReason: String? {
        guard !isManager, stampLines.isEmpty else { return nil }
        return lastPosition.flatMap { $0.status == "ok" ? nil : SvcHomeRules.noLocation($0.status) }
    }

    // MARK: One next thing to do

    @ViewBuilder private var actions: some View {
        if item.actions?.arrive == true && failed.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                PMButton(item.status == "missed" ? L("Arrived after all") : L("I’ve arrived"), systemImage: "door-open", fullWidth: true, isWorking: pressing) { handlers.arrive(item) }
                if locationOn {
                    Text(L("Your location is saved when you arrive and finish. Only owners and admins see it.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        if item.actions?.finish == true && failed.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if item.isStay {
                    PMButton(L("Leave"), systemImage: "log-out", fullWidth: true, isWorking: pressing) { handlers.finish(item) }
                } else if SvcHomeRules.finishesHere(item.serviceCategory) {
                    if canWriteReport && item.hasReport != true {
                        PMButton(L("Write report"), systemImage: "clipboard-pen", variant: .outline, fullWidth: true) { handlers.report(item) }
                    }
                    PMButton(L("Finish"), systemImage: "badge-check", fullWidth: true, isWorking: pressing) { handlers.finish(item) }
                } else {
                    PMButton(L("Finish on the visit"), systemImage: "external-link", fullWidth: true, isWorking: false) { handlers.open(item) }
                    Text(L("A vet visit is finished on its page, with its note.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        if !canAct && !item.closed && !item.isStay && day.isToday == true {
            Text(L("Your role can’t record arrivals.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
        }
        if item.phase == "done" && canWriteReport && item.hasReport != true {
            PMButton(L("Write report"), systemImage: "clipboard-pen", variant: .outline, fullWidth: true) { handlers.report(item) }
        }
        if offersOnMyWay && failed.isEmpty {
            PMButton(L("On my way"), systemImage: "message-circle", variant: .outline, fullWidth: true) { handlers.onMyWay(item) }
        }
    }
}

/// The card's shadow, gone once the visit is over (web: `closed && 'shadow-none'`).
private struct SvcCardShadow: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.cardShadow() } else { content }
    }
}

/// A visit under way (web `VisitInProgress`): how long the person has been there against
/// what was booked, the checklist's progress on a stay visit, and whether the report is in.
private struct SvcVisitTimer: View {
    let item: SvcHomeVisitItem
    let timeZone: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = SvcTime.minutesBetween(item.arrivedAt, DateText.iso(context.date))
            let booked = item.bookedMinutes
            let over = booked.map { elapsed > $0 } ?? false
            let tone = over ? Theme.mango : Theme.blue
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Eyebrow(L("Time at the visit"))
                            Text(SvcHomeRules.timer(item.arrivedAt, now: context.date)).font(.brandHeading(33.6)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(booked.map { LF("%d of %d min", elapsed, $0) } ?? LF("%d min", elapsed)).font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                            if let arrived = item.arrivedAt { Text(LF("Arrived at %@", SvcTime.clock(arrived, timeZone))).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft) }
                        }
                    }
                    if let booked, booked > 0 {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.wash(Theme.inkStrong, 12))
                                Capsule().fill(tone).frame(width: proxy.size.width * min(1, Double(elapsed) / Double(booked)))
                            }
                        }
                        .frame(height: 8)
                        .padding(.top, 10)
                        Text((over ? L("Over the booked time") + " · " : "") + LF("Booked %d min", booked))
                            .font(Theme.text(12, weight: .bold)).foregroundStyle(over ? Theme.inkStrong : Theme.inkSoft)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.wash(tone, 12), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(tone, 60, with: Theme.borderSoft), lineWidth: 1.5))
                if let checklist = item.checklist, checklist.total > 0 {
                    HStack(spacing: 8) {
                        Glyph("list-checks", size: 16).foregroundStyle(Theme.blue)
                        Text(LF("Checklist · %d of %d", checklist.done, checklist.total))
                    }
                    .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                }
                if item.hasReport == true {
                    HStack(spacing: 8) {
                        Glyph("clipboard-check", size: 16).foregroundStyle(ProviderState.done.color)
                        Text(L("Report"))
                    }
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }
}
