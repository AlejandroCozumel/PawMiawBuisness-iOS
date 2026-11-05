//
//  HomeDayScreen.swift
//  PawMiawNegocios
//
//  Home on another day (web components/app/today/home-day.tsx,
//  `GET /provider-day`), shown in place of today's board as on the web:
//  ‹ › on a phone's own line, the day's header with its numbers as filters —
//  a day ahead is the list to get ready for (not confirmed, consents
//  missing, no price, double booked, first visits); a day gone is its recap
//  (unpaid, notes to sign, reports incomplete, what was collected) — the
//  visits card, and the stays arriving and leaving that day beside it.
//

import SwiftUI

/// The other day's data, kept by Home so a pull to refresh reaches it.
@MainActor
final class HomeDayModel: ObservableObject {
    @Published var day: HomeOtherDay?
    @Published var error: String?
    @Published var loading = false

    func load(_ date: String, _ w: Workspace) async {
        loading = true
        defer { loading = false }
        do {
            day = try await API.get("/provider-day", query: ["date": date, "locationId": w.locationId])
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = errorText(error)
        }
    }
}

struct HomeDayView: View {
    let date: String
    let today: String
    @ObservedObject var model: HomeDayModel
    let onChangeDay: (String?) -> Void
    /// Booked from another day's Home: that day. Nil when this person can't book.
    let onNewAppointment: (() -> Void)?

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var filter: HomeDayFilter = .all
    @State private var width: CGFloat = 0

    private var ahead: Bool { date > today }
    private var phone: Bool { sizeClass != .regular }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if phone { switcher }
            if let day = model.day, day.date == date {
                header(stats(day))
                content(day)
            } else {
                header([])
                if model.error != nil {
                    EmptyState(systemImage: "triangle-alert", title: L("This day couldn’t be loaded"), message: L("Check the connection and try again."),
                               actionTitle: L("Try again"), action: { Task { await model.load(date, workspace) } }, accent: Theme.mango, panel: true)
                } else {
                    LoadingState()
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .opacity(model.loading && model.day != nil ? 0.8 : 1)
        .task(id: "\(date)-\(workspace.scopeVersion)") { await model.load(date, workspace) }
        .onChange(of: date) { _, _ in filter = .all }
    }

    private var switcher: DayStepper {
        homeDayStepper(date: date, today: today) { next in
            filter = .all
            onChangeDay(next)
        }
    }

    // MARK: The header

    @ViewBuilder
    private func header(_ stats: [ModuleStat]) -> some View {
        // "Mañana · sábado, 3 de octubre"; a day with no such name is just its date.
        let name = HomeDayKey.name(date, today: today)
        let full = HomeDayKey.long(date)
        let icon = ahead ? "calendar-check-2" : "calendar-days"
        let accent = ahead ? Theme.lavender : Theme.butter
        if !phone || (ahead && onNewAppointment != nil) {
            ModuleHeader(icon: icon, title: name ?? full, subtitle: name == nil ? nil : full, accent: accent, stats: stats, storageKey: "home-day") {
                if !phone { switcher }
                if ahead, let onNewAppointment {
                    PMButton(L("New appointment"), systemImage: "calendar-plus", action: onNewAppointment)
                }
            }
        } else {
            ModuleHeader(icon: icon, title: name ?? full, subtitle: name == nil ? nil : full, accent: accent, stats: stats, storageKey: "home-day")
        }
    }

    private func toggle(_ next: HomeDayFilter) {
        filter = filter == next ? .all : next
    }

    private func stats(_ day: HomeOtherDay) -> [ModuleStat] {
        let counts = day.counts
        let missed = counts?.missed ?? 0
        if ahead {
            let seesPrices = (day.visits ?? []).contains { $0.prep != nil && $0.prep?.needsPrice != nil }
            var stats = [
                ModuleStat("visits", label: L("Visits@day"), value: "\(counts?.total ?? 0)", hint: missed > 0 ? LF("%d cancelled", missed) : nil,
                           icon: "calendar-check-2", accent: Theme.aqua, active: filter == .all, action: { toggle(.all) }),
                ModuleStat("unconfirmed", label: L("Not confirmed"), value: "\(counts?.unconfirmed ?? 0)", icon: "mail-question-mark", accent: Theme.mango,
                           attention: (counts?.unconfirmed ?? 0) > 0, active: filter == .unconfirmed, action: { toggle(.unconfirmed) }),
                ModuleStat("consents", label: L("Consent missing"), value: "\(counts?.consentsMissing ?? 0)", icon: "file-pen-line", accent: Theme.pink,
                           attention: (counts?.consentsMissing ?? 0) > 0, active: filter == .consents, action: { toggle(.consents) }),
            ]
            if seesPrices {
                stats.append(ModuleStat("price", label: L("No price"), value: "\(counts?.needsPrice ?? 0)", icon: "tag", accent: Theme.butter,
                                        attention: (counts?.needsPrice ?? 0) > 0, active: filter == .price, action: { toggle(.price) }))
            }
            // Said only when there is one: booked over another visit on purpose, worth a look before the day.
            if (counts?.doubleBooked ?? 0) > 0 {
                stats.append(ModuleStat("double", label: L("Double booked"), value: "\(counts?.doubleBooked ?? 0)", icon: "triangle-alert", accent: Theme.mango,
                                        attention: true, active: filter == .double, action: { toggle(.double) }))
            }
            stats.append(ModuleStat("first", label: L("First visits"), value: "\(counts?.firstVisits ?? 0)", icon: "sparkles", accent: Theme.lavender,
                                    active: filter == .first, action: { toggle(.first) }))
            return stats
        }
        var stats = [
            ModuleStat("done", label: L("Done@home"), value: "\(counts?.done ?? 0)", hint: missed > 0 ? LF("%d missed@home", missed) : nil,
                       icon: "calendar-check-2", accent: Theme.aqua, active: filter == .all || filter == .missed,
                       action: { toggle(missed > 0 && filter != .missed ? .missed : .all) }),
        ]
        if let unpaid = counts?.unpaidAmount {
            let hint = [
                (counts?.unpaid ?? 0) > 0 ? LF("%d visits", counts?.unpaid ?? 0) : nil,
                // Bills never sent to the desk: not owed yet, but nobody charged them.
                (counts?.uncharged ?? 0) > 0 ? ((counts?.uncharged ?? 0) == 1 ? L("1 bill not closed") : LF("%d bills not closed", counts?.uncharged ?? 0)) : nil,
            ].compactMap { $0 }.joined(separator: " · ")
            stats.append(ModuleStat("unpaid", label: L("Unpaid"), value: Money.format(unpaid, currency: day.currency), hint: hint.nonEmpty,
                                    icon: "circle-dollar-sign", accent: Theme.pink, attention: (counts?.unpaid ?? 0) > 0, active: filter == .unpaid, action: { toggle(.unpaid) }))
        }
        stats.append(ModuleStat("notes", label: L("Notes to sign"), value: "\(counts?.notesToSign ?? 0)", icon: "notebook-pen", accent: Theme.mango,
                                attention: (counts?.notesToSign ?? 0) > 0, active: filter == .notes, action: { toggle(.notes) }))
        if (counts?.reportsMissing ?? 0) > 0 {
            stats.append(ModuleStat("reports", label: L("Report incomplete"), value: "\(counts?.reportsMissing ?? 0)", icon: "clipboard-check", accent: Theme.lavender,
                                    attention: true, active: filter == .reports, action: { toggle(.reports) }))
        }
        if let collected = day.collected {
            stats.append(ModuleStat("collected", label: L("Collected"), value: Money.format(collected, currency: day.currency), icon: "hand-coins", accent: Theme.lime))
        }
        return stats
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ day: HomeOtherDay) -> some View {
        let staysAny = !(day.stays?.arriving ?? []).isEmpty || !(day.stays?.leaving ?? []).isEmpty
        if width >= 940 {
            HStack(alignment: .top, spacing: 16) {
                visitCard(day.visits ?? []).frame(maxWidth: .infinity, alignment: .top)
                if staysAny, let stays = day.stays { staysBlock(stays).frame(width: 352) }
            }
        } else {
            visitCard(day.visits ?? [])
            if staysAny, let stays = day.stays { staysBlock(stays) }
        }
    }

    private func matches(_ visit: HomeDayVisit) -> Bool {
        switch filter {
        case .all: return true
        case .unconfirmed: return visit.prep?.confirmation != nil
        case .consents: return !(visit.prep?.consentsMissing ?? []).isEmpty
        case .price: return visit.prep?.needsPrice == true
        case .first: return visit.prep?.firstVisit == true
        case .double: return visit.doubleBooked == true
        // Charged and still owed, as the server counts "Sin pagar": a draft is not a debt yet.
        case .unpaid: return (visit.recap?.balanceDue ?? 0) > 0 && visit.recap?.billStatus != "draft"
        case .notes: return (visit.recap?.notesToSign ?? 0) > 0
        case .reports: return !(visit.recap?.reportMissing ?? []).isEmpty
        case .missed: return HomeDayRow.missed(visit)
        }
    }

    private func visitCard(_ visits: [HomeDayVisit]) -> some View {
        let shown = visits.filter(matches)
        let active = shown.filter { !HomeDayRow.missed($0) || filter == .missed }
        let dropped = filter == .all ? visits.filter(HomeDayRow.missed) : []
        return SectionCard(
            title: ahead ? L("Get ready") : L("How it went"),
            subtitle: ahead ? L("What each visit still needs before they come.") : L("What was done, and what is still open.")
        ) {
            if filter != .all {
                Button { filter = .all } label: { Chip(text: L("See everything"), tone: .muted, icon: "x") }
                    .buttonStyle(.plain)
            }
        } content: {
            if active.isEmpty && dropped.isEmpty {
                VStack(spacing: 0) {
                    EmptyState(
                        systemImage: "calendar-days",
                        title: filter != .all ? L("Nothing here") : (ahead ? L("Nothing booked for this day") : L("No visits this day")),
                        message: filter != .all ? L("No visit on this day matches.") : (ahead ? L("Visits booked for this day show here, with what each still needs.") : L("Visits of this day show here once there are some.")),
                        actionTitle: ahead && filter == .all && onNewAppointment != nil ? L("New appointment") : nil,
                        action: onNewAppointment,
                        accent: Theme.aqua
                    )
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    RowList(items: active) { visit in HomeDayRow(visit: visit, ahead: ahead) }
                    if !dropped.isEmpty {
                        if !active.isEmpty { RowDivider() }
                        Text(L("Cancelled or didn’t come").uppercased())
                            .font(Theme.text(12, weight: .bold)).tracking(1.44).foregroundStyle(Theme.inkSoft)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surfaceMuted)
                        RowDivider()
                        RowList(items: dropped) { visit in HomeDayRow(visit: visit, ahead: ahead) }
                    }
                }
            }
        }
    }

    /// The stays arriving and leaving that day.
    private func staysBlock(_ stays: HomeDayStays) -> some View {
        SectionCard(L("Stays"), icon: "bed-double", accent: Theme.blue) {
            VStack(alignment: .leading, spacing: 0) {
                stayGroup(ahead ? L("Arriving") : L("Arrived"), "log-in", stays.arriving ?? [], arriving: true)
                stayGroup(ahead ? L("Leaving") : L("Left"), "log-out", stays.leaving ?? [], arriving: false)
            }
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func stayGroup(_ title: String, _ icon: String, _ list: [HomeDayStay], arriving: Bool) -> some View {
        if !list.isEmpty {
            HStack(spacing: 6) {
                Glyph(icon, size: 14)
                Text("\(title) · \(list.count)".uppercased()).tracking(1.44)
            }
            .font(Theme.text(12, weight: .bold))
            .foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
            ForEach(list) { stay in
                NavigationLink(value: ProviderRoute.stay(stay.id)) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(arriving ? (stay.checkInTime ?? "—") : (stay.checkOutTime ?? "—"))
                            .font(.brandHeading(14)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                            .frame(width: 48, alignment: .leading)
                        VStack(alignment: .leading, spacing: 0) {
                            Text((stay.pets ?? []).joined(separator: ", ")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            Text([stay.clientName, stay.unitName].compactMap { $0?.nonEmpty }.joined(separator: " · ")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                            // An earlier day's arrival or departure still undone.
                            if stay.late == true {
                                Text(stay.status == "checked_in" ? LF("Was due out %@", DateText.day(stay.checkOutDay)) : LF("Was due in %@", DateText.day(stay.checkInDay)))
                                    .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.destructive).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

enum HomeDayFilter: Hashable { case all, unconfirmed, consents, price, first, double, unpaid, notes, reports, missed }

/// A visit of the day: its time and state, who and what, and what it still needs (ahead) or what is still open (gone).
private struct HomeDayRow: View {
    let visit: HomeDayVisit
    let ahead: Bool

    static func missed(_ visit: HomeDayVisit) -> Bool { visit.status == "cancelled" || visit.status == "no_show" }
    /// A visit from a day gone that was never closed (still booked, waiting or in service).
    private var leftOpen: Bool { ["scheduled", "checked_in", "in_progress"].contains(visit.status ?? "") }

    private var state: (text: String, color: Color) {
        if Self.missed(visit) { return (visit.status == "no_show" ? L("No-show") : L("Cancelled@visit"), Theme.destructive) }
        // A family's online booking still waiting for an answer: it holds the time, it isn't booked yet.
        if visit.status == "requested" { return (L("To confirm"), ProviderState.waiting.color) }
        if ahead { return visit.confirmationStatus == "confirmed" ? (L("Confirmed@visit"), Theme.blue) : (L("Booked"), Theme.inkSoft) }
        return leftOpen ? (L("Left open"), Theme.destructive) : (L("Done@home"), Theme.blue)
    }

    private var stripe: Color {
        if Self.missed(visit) || (!ahead && leftOpen) { return Theme.destructive }
        return ahead ? Theme.lavender : Theme.borderSoft
    }

    private var confirmation: (String, Chip.Tone)? {
        switch visit.prep?.confirmation {
        case "pending": (L("No answer yet"), .warn)
        case "reschedule_requested": (L("Asked to reschedule"), .warn)
        case "cancellation_requested": (L("Asked to cancel"), .danger)
        case "declined": (L("Declined@visit"), .danger)
        case "delivery_failed": (L("The confirmation didn’t reach them"), .warn)
        case "expired": (L("No answer — the request expired"), .warn)
        default: nil
        }
    }

    /// "con Dra. Rivas" — unless the person is the client too (a vet's own pet).
    private var people: String {
        let client = visit.client?.name ?? ""
        let assigned: String? = {
            if let name = visit.assigned?.name {
                return name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(client.trimmingCharacters(in: .whitespaces)) == .orderedSame ? nil : LF("with %@", name)
            }
            return ahead ? L("Whoever is free") : nil
        }()
        return [client.nonEmpty, assigned, visit.room?.nonEmpty].compactMap { $0 }.joined(separator: " · ")
    }

    private var chips: [HomeChipSpec] {
        var list: [HomeChipSpec] = []
        if let allergies = visit.pet?.allergies, !allergies.isEmpty {
            list.append(.chip(LF("Allergy: %@", allergies.joined(separator: ", ")), .danger, icon: "triangle-alert"))
        }
        if visit.doubleBooked == true { list.append(.chip(L("Double booked"), .danger, icon: "triangle-alert")) }
        if visit.bookedOnline == true { list.append(.chip(L("Online@booking"), .online, icon: "globe")) }
        // A day ahead: what to sort out before they come.
        if let confirmation { list.append(.chip(confirmation.0, confirmation.1, icon: "mail-question-mark")) }
        if let consents = visit.prep?.consentsMissing, !consents.isEmpty {
            list.append(.chip(LF("Consent missing: %@", consents.joined(separator: ", ")), .danger, icon: "file-pen-line"))
        }
        if visit.prep?.needsPrice == true { list.append(.chip(L("No price"), .warn, icon: "tag")) }
        if visit.prep?.groomRequest == false { list.append(.chip(L("No grooming request yet"), .info, icon: "scissors")) }
        if visit.prep?.groomRequest == true { list.append(.chip(L("Owner’s request in"), .good, icon: "scissors")) }
        if visit.prep?.firstVisit == true { list.append(.chip(L("First visit"), .info, icon: "sparkles")) }
        // A day gone: what is still open.
        if let recap = visit.recap {
            if let balance = recap.balanceDue, balance > 0 { list.append(.chip(LF("Unpaid %@", Money.format(balance, currency: recap.currency)), .danger, icon: "circle-dollar-sign")) }
            if recap.billStatus == "paid" { list.append(.chip(L("Paid@bill"), .good, icon: "circle-dollar-sign")) }
            if (recap.notesToSign ?? 0) > 0 { list.append(.chip(L("Note to sign"), .warn, icon: "notebook-pen")) }
            if !(recap.reportMissing ?? []).isEmpty { list.append(.chip(L("Report incomplete"), .warn, icon: "clipboard-check")) }
        }
        return list
    }

    var body: some View {
        let state = state
        NavigationLink(value: ProviderRoute.appointment(visit.id)) {
            EdgeRow(edge: stripe, time: DateText.time(visit.startsAt), timeNote: state.text, timeNoteColor: state.color) {
                HStack(alignment: .center, spacing: 12) {
                    PetAvatar(name: visit.pet?.name, species: visit.pet?.species, photoURL: visit.pet?.photoUrl, size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        (Text(visit.pet?.name ?? "—").font(Theme.text(16, weight: .bold)).foregroundColor(Theme.inkStrong)
                         + Text(" · " + (visit.serviceLabel ?? "")).font(Theme.text(16)).foregroundColor(Theme.inkSoft))
                            .lineLimit(1)
                        Text(people).font(Theme.text(12.8)).foregroundStyle(Theme.inkSoft).lineLimit(1).padding(.top, 2)
                        let shown = chips
                        if !shown.isEmpty {
                            FlowLayout(spacing: 6) { ForEach(shown) { $0.view } }.padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .opacity(Self.missed(visit) ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(L("Open visit")): \(visit.pet?.name ?? "") · \(visit.serviceLabel ?? "")")
    }
}
