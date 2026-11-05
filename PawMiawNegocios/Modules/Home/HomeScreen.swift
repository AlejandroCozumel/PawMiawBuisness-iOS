//
//  HomeScreen.swift
//  PawMiawNegocios
//
//  Inicio (web routes/provider.index.tsx): one place's day. Until the
//  business is set up it says so (the setup is on the web); with the plan
//  paused it says that; a role that sees nothing of the day is told so.
//  Otherwise: the clock and setup cards, an invited member's reminders,
//  visits to relocate, families' requests, then the day's board
//  (components/app/today/today-board.tsx) and "Te necesita".
//

import SwiftUI

/// What a role may do on Home (the web's `TodayPermissions`).
struct HomePermissions {
    let checkIn: Bool
    let start: Bool
    let cancel: Bool
    let edit: Bool
    let create: Bool
    let takePayment: Bool
    let price: Bool
    let billView: Bool
    let billSend: Bool
    let reassign: Bool
    let followUps: Bool
    let clients: Bool
    let sign: Bool
    let register: Bool

    @MainActor
    init(_ w: Workspace) {
        checkIn = w.can(.appointmentsCheckIn)
        start = w.can(.appointmentsComplete)
        cancel = w.can(.appointmentsCancel)
        edit = w.can(.appointmentsEdit)
        create = w.can(.appointmentsCreate)
        takePayment = w.can(.billingRecordPayment)
        price = w.can(.billingEditInvoice)
        billView = w.canAny(.billingView, .financeDesk, .financeView)
        billSend = w.canAny(.billingEditInvoice, .billingFinalizeInvoice)
        reassign = w.can(.appointmentsAssignAnyone)
        followUps = w.can(.followupsEdit)
        clients = w.can(.clientsView)
        sign = w.can(.recordsApprove)
        register = w.canAny(.salesSell, .billingRecordPayment, .registerManage)
    }
}

/// Everything Home reads, refreshed together (the board every 30 s, as the web).
@MainActor
final class HomeModel: ObservableObject {
    @Published var today: HomeToday?
    @Published var error: String?
    @Published var grooming: HomeGroomingToday?
    @Published var groomingFailed = false
    @Published var homeVisits: HomeVisitsDay?
    @Published var checklist: HomeChecklist?
    @Published var reminders: [HomeMemberReminder] = []
    @Published var relocations: [HomeRelocationVisit] = []
    @Published var familyRequests: [HomeFamilyRequest] = []
    /// The Home visits day list whole, for "Llegué" and "Terminar" under Domicilio.
    @Published var homeVisitsDay: SvcHomeVisitsDay?
    /// An invited member's welcome, whole (shown over Home while `show`).
    @Published var welcome: HomeWelcomeState?
    /// The grooming settings' "simple stages".
    @Published var simpleStages = false
    @Published private(set) var loading = false

    func load(_ w: Workspace) async {
        guard let current = w.current else { return }
        loading = true
        defer { loading = false }
        let location = w.locationId
        let seesAnything = HomeModel.seesAnything(w)
        let setUp = current.setupCompletedAt != nil
        let asksChecklist = setUp && w.can(.workspaceEdit)
        let asksReminders = setUp && current.role != nil && current.role != "owner"
        let asksRelocations = w.canSeeAllLocations && w.can(.appointmentsView) && w.allLocations.contains { $0.status == "paused" }
        let asksRequests = setUp && w.canAny(.staysView, .appointmentsView)

        async let todayCall: Result<HomeToday, Error>? = seesAnything && setUp ? await Self.result { () async throws -> HomeToday in try await API.get("/provider-today", query: ["locationId": location]) } : nil
        async let checklistCall: HomeChecklist? = asksChecklist ? try? await API.get("/provider-setup/checklist") : nil
        async let remindersCall: Data? = asksReminders ? try? await API.data("GET", "/provider-member-onboarding", query: [:], body: nil) : nil
        async let relocationsCall: HomeRelocations? = asksRelocations ? try? await API.get("/provider-locations/relocate") : nil
        async let requestsCall: HomeFamilyRequestList? = asksRequests ? try? await API.get("/provider-requests", query: ["scope": "open", "locationId": location]) : nil

        switch await todayCall {
        case .success(let value)?:
            today = value
            error = nil
        case .failure(let failure)?:
            if !(failure is CancellationError) { error = errorText(failure) }
        case nil:
            today = nil
        }
        checklist = await checklistCall
        let onboardingData = await remindersCall
        let onboarding: HomeMemberOnboarding? = onboardingData.flatMap { try? API.decoder.decode(HomeMemberOnboarding.self, from: $0) }
        reminders = (onboarding?.applicable == true && onboarding?.show != true) ? (onboarding?.reminders ?? []) : []
        welcome = onboarding?.applicable == true ? onboardingData.flatMap { try? API.decoder.decode(HomeWelcomeState.self, from: $0) } : nil
        relocations = await relocationsCall?.visits ?? []
        familyRequests = await requestsCall?.items ?? []

        // Grooming and home visits read their own day lists, as the web's board does.
        let modules = today?.hub?.modules ?? []
        if modules.contains("grooming") {
            do {
                grooming = try await API.get("/provider-grooming/today", query: ["locationId": location])
                groomingFailed = false
            } catch is CancellationError {
            } catch {
                groomingFailed = grooming == nil
            }
        } else {
            grooming = nil
        }
        if modules.contains("home") {
            if let data = try? await API.data("GET", "/provider-home-visits/today", query: ["locationId": location], body: nil) {
                homeVisits = try? API.decoder.decode(HomeVisitsDay.self, from: data)
                homeVisitsDay = try? API.decoder.decode(SvcHomeVisitsDay.self, from: data)
            } else {
                homeVisits = nil
                homeVisitsDay = nil
            }
        } else {
            homeVisits = nil
            homeVisitsDay = nil
        }
        // "Simple stages": asked only where a groom's stage is shown.
        if modules.contains("grooming") || (today?.allVisits ?? []).contains(where: { $0.groomStage != nil }) {
            let settings: SchedGroomSettings? = try? await API.get("/provider-grooming/settings")
            simpleStages = settings?.simpleStages ?? simpleStages
        }
    }

    private static func result<T>(_ work: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    /// Home is the hub: visits, stays, the hospital, money and follow-ups — whichever this role may see.
    static func seesAnything(_ w: Workspace) -> Bool {
        w.canAny(.appointmentsView, .staysView, .hospitalView, .followupsView, .recordsView) || w.moneyLevel >= .charging
    }
}

/// Inicio: the place's day, or what stands before it.
struct HomeScreen: View {
    var body: some View {
        RequireLocation {
            HomeContent()
        }
        .providerPage(L("Home"), root: true)
    }
}

private struct HomeContent: View {
    @EnvironmentObject private var workspace: Workspace
    @StateObject private var model = HomeModel()
    @StateObject private var dayModel = HomeDayModel()
    @State private var actions = HomeActions()
    /// Another day than today (the workspace's): a list to get ready for, or the recap of one gone.
    @State private var otherDay: String?

    /// Booking takes creating visits and seeing clients.
    private var canBook: Bool { workspace.canAll(.appointmentsCreate, .clientsView) }

    private var current: ProviderWorkspace? { workspace.current }

    var body: some View {
        PageScroll(maxWidth: 1180, refresh: { await refresh() }) {
            if let current {
                if current.setupCompletedAt == nil {
                    HomeWebNotice(
                        systemImage: "wrench",
                        title: L("Finish setting up your workspace"),
                        message: L("Your business details, hours and services are set up on the web. Home opens here once they are done."),
                        actionTitle: L("Open setup on the web"),
                        path: "/provider"
                    )
                } else if !HomeAccess.canUse(current) {
                    HomeWebNotice(
                        systemImage: "lock",
                        title: HomeAccess.lockedTitle(current),
                        message: L("Provider tools are paused until billing is connected. Plans are chosen on the web."),
                        actionTitle: L("Open the plan on the web"),
                        path: "/provider/billing",
                        tone: .warning
                    )
                } else if !HomeModel.seesAnything(workspace) {
                    EmptyState(systemImage: "calendar-clock", title: L("Nothing on the Home for your role yet."),
                               message: L("Ask the workspace owner to let your role see visits, stays, the hospital, billing or follow-ups."),
                               accent: Theme.blue, panel: true)
                } else {
                    content
                }
            }
        }
        .reloadsOnScope { await model.load(workspace) }
        .task(id: workspace.scopeVersion) {
            // The board is a live screen at the front desk.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await model.load(workspace)
            }
        }
        .modifier(HomeActionsHost(actions: actions))
        .onChange(of: model.simpleStages) { _, simple in actions.simpleStages = simple }
        // An invited member's welcome opens over Home on their first entry (and stays until they leave it).
        .onChange(of: model.welcome?.show) { _, show in
            if show == true, !actions.showsWelcome, let welcome = model.welcome { actions.openWelcome(welcome) }
        }
    }

    private func refresh() async {
        await model.load(workspace)
        if let otherDay { await dayModel.load(otherDay, workspace) }
    }

    @ViewBuilder
    private var content: some View {
        if let current {
            // A workspace set up before onboarding asked confirms its clock and money once.
            if workspace.can(.workspaceEdit) {
                if current.needsRegionConfirmation == true {
                    HomeRegionCard()
                } else {
                    HomeClockCheck()
                }
            }
            if workspace.can(.workspaceEdit), let checklist = model.checklist, checklist.complete != true {
                HomeChecklistCard(checklist: checklist) { model.checklist = $0 }
            }
            // An invited member's items left for later: their signature, their credential, the welcome.
            if !model.reminders.isEmpty {
                HomeRemindersCard(reminders: model.reminders) { id in
                    model.reminders.removeAll { $0.id == id }
                }
            }
            // Visits left at a location the plan paused (owners and admins): move or cancel them.
            if !model.relocations.isEmpty {
                HomeRelocateBanner(visits: model.relocations)
            }
            // Families' requests waiting for an answer.
            HomeRequestsBanner(
                requests: model.familyRequests,
                online: model.today?.needsYou?.onlineRequests
            )
            if let today = model.today {
                let changeDay: ((String?) -> Void)? = workspace.can(.appointmentsView) ? { otherDay = $0 } : nil
                if let otherDay, let date = today.date, otherDay != date {
                    HomeDayView(date: otherDay, today: date, model: dayModel, onChangeDay: { self.otherDay = $0 },
                                onNewAppointment: canBook ? { actions.newAppointment(day: otherDay) } : nil)
                } else {
                    HomeBoard(today: today, model: model, open: { actions.route = $0 }, changeDay: changeDay)
                }
            } else if let error = model.error {
                ErrorState(message: error) { await model.load(workspace) }
            } else {
                LoadingState()
            }
        }
    }
}

/// "miércoles 4 de noviembre" for the day the server says it is.
enum HomeHeaderDate {
    static func text(_ day: String?) -> String { HomeDayKey.long(day) }
}

/// Whether the plan lets the business use its tools (web lib/provider-workspace-access.ts).
enum HomeAccess {
    static func canUse(_ w: ProviderWorkspace) -> Bool {
        guard let status = w.billingStatus, w.billingProvider != nil else { return false }
        switch status {
        case "active", "grace_period":
            return true
        case "canceled":
            return (DateText.parse(w.currentPeriodEndsAt) ?? .distantPast) > Date()
        case "trialing":
            return (DateText.parse(w.trialEndsAt) ?? .distantPast) > Date()
        default:
            return false
        }
    }

    static func lockedTitle(_ w: ProviderWorkspace) -> String {
        w.billingStatus == "trialing" ? L("Trial ended") : L("Activation needed")
    }
}

/// What only the web does (setup, the plan): the kit's empty state, as a panel, with the way there.
struct HomeWebNotice: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String
    let path: String
    var tone: NoticeCard.Tone = .info
    @Environment(\.openURL) private var openURL

    var body: some View {
        EmptyState(
            systemImage: systemImage,
            title: title,
            message: message + " " + L("Opens PawMiaw on the web."),
            actionTitle: actionTitle,
            action: { openURL(APIConfig.webOrigin.appendingPathComponent(String(path.dropFirst()))) },
            accent: tone == .warning ? Theme.mango : Theme.blue,
            panel: true
        )
    }
}

/// "Hoy" follows the place's clock; a place left on another zone than this device's is offered this device's.
private struct HomeClockCheck: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var saving = false
    @State private var fixed = false

    private var saved: String {
        (workspace.multiLocation ? workspace.selectedLocation?.availability?.timezone ?? workspace.selectedLocation?.timezone : nil)
            ?? workspace.current?.availability?.timezone ?? "UTC"
    }

    private var device: String { TimeZone.current.identifier }

    private var differs: Bool {
        guard !fixed, device != saved else { return false }
        let a = TimeZone(identifier: device)?.secondsFromGMT()
        let b = TimeZone(identifier: saved)?.secondsFromGMT()
        return a != b
    }

    private func label(_ zone: String) -> String {
        let name = TimeZone(identifier: zone)?.localizedName(for: .generic, locale: .app)
        let city = zone.split(separator: "/").last.map { String($0).replacingOccurrences(of: "_", with: " ") } ?? zone
        return name.map { "\(city) (\($0))" } ?? city
    }

    var body: some View {
        if differs {
            NoticeCard(tone: .custom(Theme.mango), title: LF("The workspace clock is set to %@.", label(saved)), message: LF("This device is on %@; “today”, opening hours and the day’s totals follow the workspace.", label(device)), icon: "clock", look: .banner, actionTitle: LF("Use %@", label(device)), isWorking: saving, action: { Task { await fix() } })
        }
    }

    private func fix() async {
        guard !saving, let clinicId = workspace.current?.clinicId else { return }
        saving = true
        defer { saving = false }
        do {
            let path = "/provider-workspaces/\(clinicId)/availability"
            let query: [String: String?] = ["locationId": workspace.locationId]
            var availability: [String: JSONValue] = try await API.get(path, query: query)
            availability["timezone"] = .string(device)
            // The web sends the whole availability back with the new zone (the server takes it whole).
            let body = try API.encoder.encode(availability)
            _ = try await API.data("PATCH", path, query: query, body: body)
            fixed = true
            Toast.show(LF("The workspace now runs on %@.", label(device)))
            await workspace.refresh()
            announceDataChanged()
        } catch {
            Toast.error(error)
        }
    }
}
