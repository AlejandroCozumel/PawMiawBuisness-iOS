//
//  HomeCards.swift
//  PawMiawNegocios
//
//  What stands above Home's board (web routes/provider.index.tsx): the setup
//  checklist "Tu espacio está al N%" (setup/setup-checklist.tsx), an invited
//  member's reminders (member-onboarding/member-reminders-card.tsx), visits
//  to relocate (locations/relocate-banner.tsx), and families' requests
//  waiting for an answer (requests/provider-requests.tsx `FamilyRequestsBanner`).
//

import SwiftUI

// MARK: - Setup checklist

struct HomeChecklistCard: View {
    let checklist: HomeChecklist
    let onChange: (HomeChecklist) -> Void

    @State private var open = UserDefaults.standard.string(forKey: HomeChecklistCard.openKey) != "closed"
    @State private var showHidden = false
    @State private var busy: String?

    static let openKey = "pawmiaw_negocios_setup_checklist_open"

    private var visible: [HomeChecklistItem] { (checklist.items ?? []).filter { $0.dismissed != true } }
    private var hidden: [HomeChecklistItem] { (checklist.items ?? []).filter { $0.dismissed == true } }

    var body: some View {
        let left = visible.filter { $0.done != true }.count
        let percent = checklist.percent ?? 0
        Card(padding: 0, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Folded it is one quiet line, so the day's work stays at the top of Home.
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { open.toggle() }
                    UserDefaults.standard.set(open ? "open" : "closed", forKey: Self.openKey)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LF("Your workspace is %d%% ready", percent))
                                .font(.brandHeading(open ? 20 : 14, relativeTo: .title3))
                                .foregroundStyle(Theme.inkStrong)
                            Text(left == 1 ? L("1 thing left to make it work well.") : LF("%d things left to make it work well.", left))
                                .font(Theme.text(open ? 14 : 12)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer(minLength: 0)
                        Glyph("chevron-down", size: 16)
                            .foregroundStyle(Theme.inkSoft)
                            .rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(open ? .isSelected : [])
                if open {
                    ProgressBar(value: Double(percent) / 100, label: L("Setup progress")).padding(.top, 12)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(visible) { item in
                            HomeChecklistRow(item: item, busy: busy == item.id) { dismiss(item.id, true) }
                        }
                    }
                    .padding(.top, 16)
                    if !hidden.isEmpty {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { showHidden.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Glyph("eye-off", size: 16)
                                Text(LF("Hidden (%d)", hidden.count))
                                Glyph("chevron-down", size: 16).rotationEffect(.degrees(showHidden ? 180 : 0))
                            }
                            .font(Theme.text(14, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                        if showHidden {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(hidden) { item in
                                    HStack(spacing: 8) {
                                        Text(HomeChecklistMeta.title(item.id)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                                        Spacer(minLength: 8)
                                        if busy == item.id {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            PMButton(L("Show again"), variant: .link, size: .slim, tint: Theme.inkStrong) { dismiss(item.id, false) }
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, open ? 16 : 10)
        }
    }

    private func dismiss(_ id: String, _ dismissed: Bool) {
        busy = id
        Task {
            defer { busy = nil }
            do {
                let updated: HomeChecklist = try await API.put("/provider-setup/checklist/\(id)", body: ["dismissed": dismissed])
                onChange(updated)
            } catch {
                Toast.error(error, fallback: L("Could not save. Try again."))
            }
        }
    }
}

/// Each checklist item's words (setup-checklist.tsx `ITEM_META`, `checklistWhy`) and where it is done.
enum HomeChecklistMeta {
    static func title(_ id: String) -> String {
        switch id {
        case "prices": L("Prices for your services")
        case "rooms": L("Rooms")
        case "team": L("Your team")
        case "online_booking": L("Online booking")
        case "policy": L("No-show and late-cancel policy")
        case "cash_drawer": L("Cash drawer")
        case "receipt": L("Receipt and legal details")
        case "credentials": L("Professional credentials")
        case "team_setup": L("Your team’s profiles")
        default: id
        }
    }

    /// The web's `ITEM_META` icon (Lucide).
    static func icon(_ id: String) -> String {
        switch id {
        case "prices": "badge-dollar-sign"
        case "rooms": "door-open"
        case "team": "users"
        case "online_booking": "calendar-check"
        case "policy": "circle-slash"
        case "cash_drawer": "wallet"
        case "receipt": "receipt-text"
        case "credentials": "id-card"
        case "team_setup": "user-check"
        default: "list-checks"
        }
    }

    static func action(_ item: HomeChecklistItem) -> String {
        if item.id == "credentials" && item.mine == false { return L("See the team") }
        switch item.id {
        case "prices": return L("Add prices")
        case "rooms": return L("Set up rooms")
        case "team": return L("Invite someone")
        case "online_booking": return L("Set it up")
        case "policy": return L("Set the policy")
        case "cash_drawer": return L("Set up the drawer")
        case "receipt": return L("Add details")
        case "credentials": return L("Add yours")
        case "team_setup": return L("See who")
        default: return L("Open@needs")
        }
    }

    /// Where the app does it, or nil when only the web does (the row says so).
    static func route(_ item: HomeChecklistItem) -> ProviderRoute? {
        switch item.id {
        case "rooms": .section(.rooms)
        case "team", "team_setup": .section(.staff)
        case "online_booking": .section(.availability)
        case "credentials": item.mine == false ? .section(.staff) : nil
        default: nil
        }
    }

    static func why(_ item: HomeChecklistItem) -> String {
        let count = item.count ?? 0
        if item.done == true {
            switch item.id {
            case "prices": return L("Every service you offer has a price.")
            case "rooms": return count == 1 ? L("1 room set up.") : (count > 0 ? LF("%d rooms set up.", count) : L("You don't use rooms."))
            case "team": return L("Your team is invited.")
            case "online_booking": return L("Families you work with can book online.")
            case "policy": return L("Your no-show and late-cancel policy is set.")
            case "cash_drawer": return L("Your cash drawer is ready.")
            case "receipt": return L("Receipts carry your footer and legal details.")
            case "credentials": return L("Your vets can sign prescriptions.")
            case "team_setup": return L("Everyone on your team has their signature and credentials.")
            default: return item.why ?? ""
            }
        }
        switch item.id {
        case "prices": return count == 1 ? L("1 service has no price: its bill asks for it before charging.") : LF("%d services have no price: their bills ask for it before charging.", count)
        case "rooms": return L("Add your rooms, or say you don't use them, so two visits never share one by accident.")
        case "team": return L("Invite the people who work with you, then set their days and hours.")
        case "online_booking": return L("Off: families you work with can't book from the app.")
        case "policy": return L("No fee yet for no-shows or late cancellations.")
        case "cash_drawer": return L("Its starting cash, and the difference that should warn you.")
        case "receipt": return L("Your tax id (RFC), tax regime and a receipt footer.")
        case "credentials":
            if count == 1 { return L("1 vet has no professional credential, so they can't sign prescriptions.") }
            return count > 0 ? LF("%d vets have no professional credential, so they can't sign prescriptions.", count) : L("Nobody on the team can sign prescriptions yet.")
        case "team_setup":
            let members = item.members ?? []
            func gap(_ kind: String) -> Int { members.filter { ($0.gaps ?? []).contains(kind) }.count }
            return [
                gap("signature") > 0 ? LF("%d without a signature", gap("signature")) : nil,
                gap("credential") > 0 ? LF("%d without a credential to prescribe", gap("credential")) : nil,
                gap("welcome") > 0 ? LF("%d yet to open their welcome", gap("welcome")) : nil,
            ].compactMap { $0 }.joined(separator: " · ")
        default: return item.why ?? ""
        }
    }
}

private struct HomeChecklistRow: View {
    let item: HomeChecklistItem
    let busy: Bool
    let dismiss: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(HomeActions.self) private var actions: HomeActions?

    var body: some View {
        let done = item.done == true
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if done {
                    HomeDisc(icon: "check", fill: Theme.blueFixed, ink: .white)
                } else {
                    HomeDisc(icon: HomeChecklistMeta.icon(item.id))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(HomeChecklistMeta.title(item.id)).font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    Text(HomeChecklistMeta.why(item)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    if done, let extra = extraLink {
                        NavigationLink(value: ProviderRoute.section(.staff)) {
                            Text(extra).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.blue)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !done {
                HStack(spacing: 8) {
                    // Each is done in place, in a sheet over Home, or on its own page.
                    if let sheet = HomeSetupSheet.forItem(item), let actions {
                        PMButton(HomeChecklistMeta.action(item), size: .compact) { actions.sheet = .setup(sheet) }
                    } else if let route = HomeChecklistMeta.route(item) {
                        NavigationLink(value: route) { Text(HomeChecklistMeta.action(item)) }
                            .buttonStyle(.pm(.primary, size: .compact))
                    } else {
                        PMButton(HomeChecklistMeta.action(item), systemImage: "external-link", size: .compact) {
                            openURL(APIConfig.webOrigin.appendingPathComponent("provider"))
                        }
                    }
                    if busy {
                        ProgressView().controlSize(.small).padding(.horizontal, 12)
                    } else {
                        PMButton(L("Not for me"), variant: .link, size: .slim, tint: Theme.inkStrong, action: dismiss)
                            .accessibilityLabel(LF("Hide “%@”", HomeChecklistMeta.title(item.id)))
                    }
                }
                .padding(.leading, 48)
            }
        }
        .padding(12)
        .background(done ? AnyShapeStyle(Theme.wash(Theme.blue, 7)) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(done ? Color.clear : Theme.borderSoft, lineWidth: 1))
    }

    /// Once done: where the team's days and profiles are set (web: "Fija sus días y horarios", "Ver el equipo").
    private var extraLink: String? {
        switch item.id {
        case "team": L("Set their days and hours")
        case "credentials", "team_setup": L("See the team")
        default: nil
        }
    }
}

// MARK: - An invited member's reminders

struct HomeRemindersCard: View {
    let reminders: [HomeMemberReminder]
    let onHidden: (String) -> Void
    @Environment(\.openURL) private var openURL
    @Environment(HomeActions.self) private var actions: HomeActions?
    @State private var busy: String?

    private func copy(_ reminder: HomeMemberReminder) -> (title: String, body: String, action: String, icon: String) {
        switch reminder.id {
        case "signature":
            return (L("Your signature is missing"), L("Adopt it once and prescriptions, records and discharges are signed with one tap."), L("Adopt my signature"), "file-pen-line")
        case "credential":
            let noun: String
            switch reminder.credentialType {
            case "cedula_profesional": noun = L("your cédula profesional")
            case "state_license": noun = L("your state license")
            default: noun = L("your professional license")
            }
            return (LF("Add %@ to prescribe", noun), L("Without it you can’t sign prescriptions here. Everything else works as usual."), L("Add it"), "id-card")
        default:
            return (L("Finish your welcome"), L("A few steps left: your profile, alerts and how you work."), L("Continue@welcome"), "sparkles")
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(reminders) { reminder in
                let copy = copy(reminder)
                Card(padding: 16, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        IconBadge(icon: copy.icon, accent: Theme.mango, size: 40, iconSize: 20, ink: .strong, washPercent: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(copy.title).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                            Text(copy.body).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 4) {
                        Button { resume(reminder.id) } label: {
                            HStack(spacing: 6) {
                                Text(copy.action)
                                if busy == reminder.id || (actions?.isBusy("welcome") ?? false) {
                                    ProgressView().tint(Theme.onBlue).controlSize(.small)
                                } else {
                                    Glyph("arrow-right", size: 16)
                                }
                            }
                        }
                            .buttonStyle(.pm(.primary, size: .compact))
                            .disabled(busy == reminder.id || (actions?.isBusy("welcome") ?? false))
                        IconCircleButton(systemImage: "x", label: LF("Hide “%@”", copy.title)) { hide(reminder.id) }
                            .disabled(busy == reminder.id)
                    }
                    .padding(.leading, 52)
                }
            }
        }
        .accessibilityLabel(L("Left for later"))
    }

    /// Each reminder opens the welcome at its step.
    private func resume(_ id: String) {
        let step: String? = id == "signature" ? "signature" : (id == "credential" ? "credentials" : nil)
        if let actions {
            actions.resumeWelcome(step: step)
            return
        }
        busy = id
        Task {
            defer { busy = nil }
            do {
                try await API.send("POST", "/provider-member-onboarding/resume", body: ["step": step])
                openURL(APIConfig.webOrigin.appendingPathComponent("provider"))
            } catch {
                Toast.error(error, fallback: L("Could not open it. Try again."))
            }
        }
    }

    private func hide(_ id: String) {
        busy = id
        Task {
            defer { busy = nil }
            do {
                try await API.send("PUT", "/provider-member-onboarding/reminders/\(id)", body: ["hidden": true])
                onHidden(id)
            } catch {
                Toast.error(error)
            }
        }
    }
}

// MARK: - Visits to relocate

struct HomeRelocateBanner: View {
    let visits: [HomeRelocationVisit]

    var body: some View {
        let places = visits.compactMap(\.locationName).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        NavigationLink(value: ProviderRoute.section(.relocate)) {
            Card(tint: Theme.mango) {
                HStack(alignment: .center, spacing: 12) {
                    HomeDisc(icon: "arrow-right-left", size: 40, iconSize: 20, fill: Theme.surface)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(visits.count == 1 ? L("1 visit to relocate") : LF("%d visits to relocate", visits.count))
                            .font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                        Text(LF("%@ is paused by the plan. Move each visit to an open location or cancel it with a notice to the family.", places.joined(separator: ", ")))
                            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Glyph("arrow-right", size: 20).foregroundStyle(Theme.inkSoft)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Families' requests

struct HomeRequestsBanner: View {
    let requests: [HomeFamilyRequest]
    let online: HomeOnlineRequestList?
    @State private var reviewing = false

    var body: some View {
        let waiting = requests.filter { $0.displayStatus == "pending" }
        let accepted = waiting.filter { $0.familyAcceptedAt != nil }.count
        let onlineCount = online?.count ?? 0
        // The server's count holds the families' asks to move a booking too ("Cambio de hora").
        let asks = min(onlineCount, (online?.items ?? []).filter(\.isReschedule).count)
        let bookings = onlineCount - asks
        let total = waiting.count + onlineCount
        if total > 0 {
            let more = [
                bookings > 0 ? (bookings == 1 ? L("1 visit booked online to confirm.") : LF("%d visits booked online to confirm.", bookings)) : nil,
                asks > 0 ? LP(asks, "%d change of time to answer.", "%d changes of time to answer.") : nil,
                accepted > 0 ? (accepted == 1 ? L("1 family accepted the dates you proposed.") : LF("%d families accepted the dates you proposed.", accepted)) : nil,
            ].compactMap { $0 }.joined(separator: " ")
            NoticeCard(tone: .custom(Theme.pink), title: total == 1 ? L("1 request from a family is waiting for your answer.") : LF("%d requests from families are waiting for your answer.", total), message: more.nonEmpty ?? L("Stays, home stays and programs asked for from the app."), icon: "mail-question-mark", look: .banner, actionTitle: L("Review requests"), action: { reviewing = true })
            .navigationDestination(isPresented: $reviewing) { HomeRequestsScreen() }
        }
    }
}

/// "Solicitudes de familias": hotel stays, daycare and home stays (the Stays module's list and sheets,
/// with the online bookings to confirm beside them) and programs, each answered here.
struct HomeRequestsScreen: View {
    var body: some View {
        PageScroll {
            ModuleHeader(icon: "mail-question-mark", title: L("Requests from families"),
                         subtitle: L("Confirm, propose other dates or decline. The family is told either way."), accent: Theme.aqua, storageKey: "requests")
            StaysRequestsView(held: [])
            HomeProgramRequests()
        }
        .providerPage(L("Requests from families"))
    }
}
