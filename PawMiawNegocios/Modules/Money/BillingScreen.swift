//
//  BillingScreen.swift
//  PawMiawNegocios
//
//  Suscripción (web: routes/provider.billing.tsx, subscription/*): the
//  business's PawMiaw plan — the plan, its state, the trial, the period end,
//  users and locations, what every plan includes, the next charge, the card
//  and the receipts as Stripe has them. Plans are bought and changed on the
//  web (Stripe); no in-app purchase (the backend refuses Apple/Google
//  purchases for businesses). The plan manager or business finances read it.
//
//  Drawn as the web's `SubscriptionOverview`: the module header in the plan's
//  colour with its four figures, the notice when the plan needs someone, the
//  plan card, the payment card, the receipts, the workspaces and the history.
//  Every action that changes the plan opens the web's Subscription page.
//

import SwiftUI

private struct CashPlanInfo {
    let plan: String
    let name: String
    let badge: String
    let seats: Int
    let locations: Int
    let monthly: Int
    let annual: Int
    let summary: String
    let highlights: [String]
    /// The plan's colour (web `PLAN_ACCENT`): starter butter, business sky, clinic lavender.
    let accent: Color

    static func of(_ plan: String?) -> CashPlanInfo? {
        switch plan {
        case "basic":
            CashPlanInfo(plan: "basic", name: L("Starter"), badge: L("Solo care"), seats: 1, locations: 1, monthly: 19, annual: 190, summary: L("1 location · 1 user"),
                         highlights: [L("One person, one location"), L("The whole workspace, no team to set up"), L("Move up to Business when your team grows")], accent: Theme.butter)
        case "pro":
            CashPlanInfo(plan: "pro", name: L("Business"), badge: L("Care team"), seats: 10, locations: 1, monthly: 99, annual: 990, summary: L("1 location · 10 users · extra locations"),
                         highlights: [L("Roles and permissions for each person"), L("Extra locations, up to 3 in total"), L("Extra users in packs of 5")], accent: Hue.sky.color)
        case "enterprise":
            CashPlanInfo(plan: "enterprise", name: L("Clinic"), badge: L("Veterinary"), seats: 30, locations: 3, monthly: 249, annual: 2490, summary: L("3 locations · 30 users"),
                         highlights: [L("Chart, hospital and prescriptions across branches"), L("Extra locations, up to 10 in total"), L("Extra users in packs of 10")], accent: Theme.lavender)
        default: nil
        }
    }

    static let everyPlan = [L("Schedule and booking requests"), L("Clients, pets and records"), L("Clinical chart and prescriptions"), L("Invoices, payments and store"), L("Boarding, daycare and hospital"), L("Reminders and follow-ups"), L("Links to family profiles")]
}

struct BillingScreen: View {
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var billing: CashBillingSummary?
    @State private var billingError: String?
    @State private var billingLoading = false
    @State private var members: Int?
    @State private var invitations: Int?
    @State private var switching: String?

    private var current: ProviderWorkspace? { workspace.current }
    private var canView: Bool { (current?.canManagePlan ?? false) || workspace.moneyLevel >= .finances }
    private var canManage: Bool { current?.canManagePlan ?? workspace.can(.billingManage) }
    private var onStripe: Bool { current?.billingProvider == "stripe" }
    private var store: Bool { current?.billingProvider == "apple_iap" || current?.billingProvider == "google_play" }
    /// Our team set the plan up by hand: no card behind it.
    private var byHand: Bool { onStripe && billing != nil && billing?.available == false }
    private var seatsUsed: Int? { members.flatMap { m in invitations.map { m + $0 } } }

    var body: some View {
        PageScroll(maxWidth: 900, refresh: { await load() }) {
            if !canView {
                NoAccessState(message: L("Ask the workspace owner for business finances to see the plan."))
            } else if let current {
                content(current)
            } else {
                ModuleHeader(icon: "circle-dollar-sign", title: L("Subscription"), subtitle: L("Your PawMiaw plan, what it includes and when it renews."), storageKey: "billing")
                EmptyState(systemImage: "building-2", title: L("No workspace is open"), message: L("Open a workspace to see its plan."), panel: true)
            }
        }
        .providerPage(L("Subscription"), root: true)
        .reloadsOnScope { await load() }
    }

    private func load() async {
        guard canView, let current else { return }
        await workspace.refresh()
        if onStripe {
            billingLoading = true
            defer { billingLoading = false }
            do {
                billing = try await API.get("/provider-subscriptions/summary")
                billingError = nil
            } catch {
                billingError = errorText(error)
            }
        }
        if workspace.can(.staffView) {
            async let memberList: [CashMember]? = try? await API.get("/provider-workspaces/\(current.clinicId)/members")
            async let invitationList: [CashInvitation]? = try? await API.get("/provider-workspaces/\(current.clinicId)/invitations")
            if let memberList = await memberList, let invitationList = await invitationList {
                let now = Date()
                members = memberList.count
                invitations = invitationList.filter { $0.status == "pending" && (DateText.parse($0.expiresAt) ?? .distantPast) > now }.count
            }
        }
    }

    /// Changing the plan, the card, cancelling or keeping it happen on the web's Subscription page.
    private func openWeb() {
        openURL(APIConfig.webOrigin.appendingPathComponent("provider/billing"))
    }

    // MARK: Content

    @ViewBuilder private func content(_ w: ProviderWorkspace) -> some View {
        let plan = CashPlanInfo.of(w.plan)
        let status = statusMeta(w.billingStatus)
        header(w, plan, status)
        if let notice = notice(w, plan) {
            let act: (() -> Void)? = canManage && notice.action != nil ? { openWeb() } : nil
            NoticeCard(tone: notice.tone, title: notice.title, message: notice.body, actionTitle: canManage ? notice.action : nil, action: act)
        }
        NoticeCard(tone: .info, title: L("Plans are chosen and paid on the web"),
                   message: canManage ? L("Change the plan, update the card or cancel on pawmiaw.com: Stripe’s secure page handles the payment.") : L("Only the workspace owner can change or cancel the plan. You can see everything here."))
        planCard(w, plan)
        payment(w, status)
        if onStripe && !byHand { receipts }
        if workspace.workspaces.count > 1 { workspacesList(w) }
        AuditHistoryCard(entityType: "clinic_billing", entityId: w.organizationId, title: L("Subscription history"), description: L("Every change to the plan, its status, renewal dates and users."))
    }

    // MARK: Header (web: CircleDollarSign in the plan's colour, four figures)

    private func header(_ w: ProviderWorkspace, _ plan: CashPlanInfo?, _ status: CashPlanStatus) -> some View {
        let next = nextEvent(w)
        let limit = w.seatLimit ?? plan?.seats
        let full = seatsUsed.map { used in limit.map { used >= $0 } ?? false } ?? false
        let paymentProblem = w.billingStatus == "grace_period" || w.billingStatus == "past_due"
        let nextHint: String? = next.date.map { date in [billing?.nextCharge.map { cashMoney($0.amount, $0.currency.uppercased()) }, relativeDays(date)].compactMap { $0?.nonEmpty }.joined(separator: " · ") }
        return ModuleHeader(
            icon: "circle-dollar-sign",
            title: L("Subscription"),
            subtitle: LF("%@: your PawMiaw plan, what it includes and when it renews.", w.name),
            accent: plan?.accent ?? Theme.blue,
            stats: [
                ModuleStat("plan", label: L("Plan"), value: plan?.name ?? L("None yet"), hint: plan?.badge ?? L("Choose one to start"), icon: "badge-check", accent: plan?.accent ?? Theme.blue),
                ModuleStat("status", label: L("Status"), value: status.label, hint: trialHint(w) ?? status.short, icon: paymentProblem ? "triangle-alert" : "sparkles", accent: status.state.color, attention: paymentProblem),
                ModuleStat("next", label: next.label, value: next.date.map { shortDate($0) } ?? "—", hint: nextHint, icon: "calendar-clock", accent: Theme.mango),
                ModuleStat("seats", label: L("Users"), value: seatsUsed.flatMap { used in limit.map { "\(used) / \($0)" } } ?? limit.map(String.init) ?? "—",
                           hint: seatsUsed != nil ? (full ? L("All taken") : L("In use, invitations included")) : L("One per person on the team"),
                           icon: "users-round", accent: Theme.lavender, attention: full && (limit ?? 0) > 1),
            ],
            storageKey: "billing"
        ) {
            if canManage && onStripe && !byHand {
                PMButton(L("Manage plan on the web"), systemImage: "external-link", variant: .outline) { openWeb() }
            }
        }
    }

    // MARK: The plan

    private func planCard(_ w: ProviderWorkspace, _ plan: CashPlanInfo?) -> some View {
        let accent = plan?.accent ?? Theme.blue
        let seats = w.seatLimit ?? plan?.seats
        let locations = w.locationLimit ?? plan?.locations
        let cycle = billing?.billingCycle
        return ListCard {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("Your plan").uppercased()).font(.brandText(10.9, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.inkSoft)
                FlowLayout(spacing: 8) {
                    Text(plan?.name ?? L("No plan yet")).font(.brandHeading(36, relativeTo: .largeTitle)).foregroundStyle(Theme.inkStrong)
                    if let plan {
                        Text(plan.badge).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            .padding(.horizontal, 12).frame(height: 28)
                            .background(Theme.surface.opacity(0.75), in: Capsule())
                    }
                }
                .padding(.top, 4)
                if let plan {
                    let price = cycle == "annual" ? LF("%@ a year", listPrice(plan.annual))
                        : cycle == "monthly" ? LF("%@ a month", listPrice(plan.monthly))
                        : LF("%@ a month", listPrice(plan.monthly)) + " · " + LF("or %@ a year", listPrice(plan.annual))
                    (Text(price).font(Theme.text(14, weight: .semibold)) + Text(" · \(L("list price, before add-ons"))").font(Theme.text(14, weight: .medium)).foregroundColor(Theme.inkSoft))
                        .foregroundStyle(Theme.inkStrong)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(stops: [.init(color: accent.opacity(0.26), location: 0), .init(color: accent.opacity(0.08), location: 0.6), .init(color: accent.opacity(0), location: 1)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            if seats != nil || locations != nil {
                RowDivider()
                VStack(alignment: .leading, spacing: 8) {
                    eyebrow(L("It holds"))
                    FlowLayout(spacing: 8) {
                        if let locations { limitChip("map-pin", LP(locations, "%d location", "%d locations")) }
                        if let seats { limitChip("users-round", LP(seats, "%d user", "%d users")) }
                    }
                    if let seats { seatMeter(seats) }
                    if workspace.can(.staffView) {
                        NavigationLink(value: ProviderRoute.section(.staff)) {
                            HStack(spacing: 6) {
                                Glyph("users-round", size: 16)
                                Text(L("Open staff"))
                            }
                            .font(Theme.text(14, weight: .bold))
                            .foregroundStyle(Theme.blue)
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            if let plan {
                RowDivider()
                VStack(alignment: .leading, spacing: 16) {
                    checklist(L("Built for"), plan.highlights, bold: true)
                    checklist(L("Included with every plan"), CashPlanInfo.everyPlan, bold: false)
                }
                .padding(16)
            }
            RowDivider()
            HStack {
                PMButton(canManage && onStripe ? L("Change plan") : L("Compare plans"), systemImage: "repeat", variant: .outline, size: .compact) { openWeb() }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased()).font(.brandText(12, weight: .bold)).tracking(1.68).foregroundStyle(Theme.blue)
    }

    private func limitChip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Glyph(icon, size: 16).foregroundStyle(Theme.blue)
            Text(text).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Theme.surfaceMuted, in: Capsule())
    }

    @ViewBuilder private func seatMeter(_ limit: Int) -> some View {
        if let used = seatsUsed, let members, let invitations {
            let full = used >= limit
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 8) {
                    Text(LF("%d of %d users in use", used, limit)).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    Text(LP(members, "%d person", "%d people") + (invitations > 0 ? " · " + LP(invitations, "%d invitation waiting", "%d invitations waiting") : ""))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
                ProgressBar(value: Double(min(used, limit)) / Double(max(1, limit)), height: 10, track: Theme.surfaceMuted, fill: full && limit > 1 ? Theme.mango : Theme.blue)
                    .accessibilityLabel(L("Users in use"))
                Text(full && limit == 1 ? L("This plan is for one person. To bring your team in, move to Business.")
                     : full ? L("Every user is taken. To add someone, move to a bigger plan or free one.")
                     : L("Each person on the team and each invitation still waiting counts as a user."))
                    .font(Theme.text(14, weight: full && limit > 1 ? .semibold : .regular))
                    .foregroundStyle(full && limit > 1 ? Theme.inkStrong : Theme.inkSoft)
            }
            .padding(.top, 8)
        } else {
            Text(L("Each person on the team and each invitation still waiting counts as a user.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.top, 8)
        }
    }

    private func checklist(_ title: String, _ lines: [String], bold: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            eyebrow(title)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Glyph("check", size: 16).foregroundStyle(Theme.blue).padding(.top, 2)
                    Text(line).font(Theme.text(14, weight: bold ? .semibold : .regular)).foregroundStyle(Theme.inkStrong)
                }
            }
        }
    }

    // MARK: Payment

    private func payment(_ w: ProviderWorkspace, _ status: CashPlanStatus) -> some View {
        let next = nextEvent(w)
        let paymentProblem = w.billingStatus == "grace_period" || w.billingStatus == "past_due"
        let cancellable = canManage && onStripe && !byHand && ["trialing", "active", "grace_period", "past_due"].contains(w.billingStatus ?? "")
        return ListCard {
            panelTitle("credit-card", L("Payment"), byHand ? L("Our team set this plan up for you. There is no card on file and nothing to pay here.") : onStripe ? L("Payments are handled by Stripe. PawMiaw never sees your card.") : nil)
            RowDivider()
            detailRow("sparkles", status.state.color, L("Status")) {
                StatusChip(text: status.label, state: status.state)
                rowDetail(status.meaning)
            }
            RowDivider()
            detailRow("calendar-clock", Theme.mango, next.label) {
                (Text(next.date.map { longDate($0) } ?? "—").font(Theme.text(16, weight: .bold))
                    + Text(next.date.map { " · \(relativeDays($0))" } ?? "").font(Theme.text(16, weight: .medium)).foregroundColor(Theme.inkSoft))
                    .foregroundStyle(Theme.inkStrong)
                if let charge = billing?.nextCharge {
                    Text(LF("%@ will be charged", cashMoney(charge.amount, charge.currency.uppercased()))).font(Theme.text(16, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                }
                rowDetail(next.detail)
            }
            if let provider = w.billingProvider {
                RowDivider()
                detailRow(store ? "smartphone" : "circle-dollar-sign", Theme.aqua, byHand ? L("Set up by") : L("Billed through")) {
                    rowValue(byHand ? L("The PawMiaw team") : provider == "stripe" ? "Stripe" : provider == "apple_iap" ? "App Store" : "Google Play")
                    rowDetail(byHand ? L("Not paid with a card. To change or end it, write to us.")
                              : provider == "apple_iap" ? L("Bought in the App Store. Change or cancel it on the iPhone or iPad: Settings → your name → Subscriptions.")
                              : provider == "google_play" ? L("Bought on Google Play. Change or cancel it in the Play Store: Profile → Payments & subscriptions.")
                              : L("The card and cancelling are handled on Stripe’s secure page."))
                }
            }
            if onStripe && !byHand {
                RowDivider()
                cardRow(paymentProblem: paymentProblem)
            }
            if let billingError, billing == nil {
                RowDivider()
                HStack(spacing: 12) {
                    Text(L("Could not load the receipts.")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    Spacer(minLength: 8)
                    PMButton(L("Try again"), variant: .outline, size: .compact) { Task { await load() } }
                }
                .padding(16)
                .accessibilityHint(billingError)
            }
            if cancellable {
                footerStrip {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(w.billingStatus == "trialing" ? L("Not for you? Cancel before the trial ends and pay nothing.") : L("No longer need it? You keep access until the paid time ends."))
                            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        PMButton(w.billingStatus == "trialing" ? L("Cancel trial") : L("Cancel plan"), variant: .destructive, size: .compact, fullWidth: true) { openWeb() }
                    }
                }
            } else if byHand && canManage {
                footerStrip {
                    HStack(alignment: .top, spacing: 8) {
                        Glyph("mail", size: 16).padding(.top, 2)
                        (Text(L("To change or end this plan, write to")) + Text(" ") + Text(Self.supportEmail).fontWeight(.bold).foregroundColor(Theme.blue))
                    }
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    .onTapGesture { if let url = URL(string: "mailto:\(Self.supportEmail)") { openURL(url) } }
                }
            } else if !canManage && w.billingProvider != nil {
                footerStrip {
                    HStack(alignment: .top, spacing: 8) {
                        Glyph("lock", size: 16).padding(.top, 2)
                        Text(onStripe ? L("Only the workspace owner can change the plan, update the card or cancel. You can see everything here.") : L("Only the workspace owner can change or cancel the plan. You can see everything here."))
                    }
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    private static let supportEmail = "contact@pawmiaw.com"

    private func cardRow(paymentProblem: Bool) -> some View {
        let card = billing?.card
        let expiry = card?.expMonth.flatMap { month in card?.expYear.map { String(format: "%02d/%02d", month, $0 % 100) } }
        let expired = card?.expMonth.flatMap { month in card?.expYear.map { year in (DateText.calendar.date(from: DateComponents(year: year, month: month + 1, day: 1)) ?? .distantFuture) <= Date() } } ?? false
        let name = card?.last4.map { last4 in [card?.brand.map { $0.capitalized }, "···· \(last4)"].compactMap { $0 }.joined(separator: " ") }
        return detailRow("credit-card", Theme.lime, L("Payment method"), action: {
            if canManage {
                PMButton(L("Update card"), systemImage: "credit-card", variant: paymentProblem ? .primary : .outline, size: .compact) { openWeb() }
            }
        }) {
            (Text(name ?? L("Card saved in Stripe")).font(Theme.text(16, weight: .bold))
                + Text(name != nil ? expiry.map { " · " + (expired ? LF("Expired %@", $0) : LF("Expires %@", $0)) } ?? "" : "").font(Theme.text(16, weight: .medium)).foregroundColor(expired ? Theme.destructive : Theme.inkSoft))
                .foregroundStyle(Theme.inkStrong)
            rowDetail(paymentProblem ? L("The last charge failed on this card.") : expired ? L("This card has expired. Update it before the next charge.") : L("The card Stripe charges for each renewal."))
        }
    }

    // MARK: Receipts

    private var receipts: some View {
        ListCard {
            panelTitle("receipt-text", L("Receipts"), L("What PawMiaw has charged for this plan. Open one or download it as a PDF."), accent: Hue.sky.color)
            RowDivider()
            if let billing {
                if billing.receipts.isEmpty {
                    Text(billing.reachable ? L("No receipts yet. The first one arrives with the first charge.") : L("Stripe did not answer just now, so the receipts can’t be shown. Try again in a moment."))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 16).padding(.vertical, 24)
                } else {
                    ForEach(Array(billing.receipts.enumerated()), id: \.element.id) { index, receipt in
                        if index > 0 { RowDivider() }
                        receiptRow(receipt)
                    }
                    footerStrip {
                        Text(LP(billing.receipts.count, "%d receipt", "%d receipts, the most recent first") + (billing.reachable ? "" : " · " + L("Stripe did not answer everything; some may be missing.")))
                            .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    }
                }
            } else if billingError != nil {
                HStack(spacing: 12) {
                    Text(L("Could not load the receipts.")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    Spacer(minLength: 8)
                    PMButton(L("Try again"), variant: .outline, size: .compact) { Task { await load() } }
                }
                .padding(.horizontal, 16).padding(.vertical, 20)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
    }

    private func receiptRow(_ receipt: CashBillingSummary.Receipt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(longDate(receipt.date)).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    Text(receipt.number ?? L("Receipt")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(cashMoney(receipt.amount, receipt.currency.uppercased())).font(Theme.text(16, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    StatusChip(text: receiptStatus(receipt.status), state: receiptState(receipt.status))
                }
            }
            HStack(spacing: 8) {
                if let url = receipt.url.flatMap(URL.init(string:)) {
                    PMButton(receipt.status == "open" ? L("Pay") : L("Open@link"), systemImage: "external-link", variant: receipt.status == "open" ? .primary : .outline, size: .compact, fullWidth: true) { openURL(url) }
                }
                if let pdf = receipt.pdfUrl.flatMap(URL.init(string:)) {
                    PMButton(L("PDF"), systemImage: "download", variant: .outline, size: .compact, fullWidth: true) { openURL(pdf) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Workspaces

    private func workspacesList(_ w: ProviderWorkspace) -> some View {
        ListCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Your workspaces")).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
                    Text(L("Each one has its own plan. Switching changes which one opens on this browser.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 8)
                Text("\(workspace.workspaces.count)").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.onBlue)
                    .padding(.horizontal, 8).frame(minWidth: 28, minHeight: 28)
                    .background(Theme.blue, in: Capsule())
            }
            .padding(16)
            ForEach(workspace.workspaces) { entry in
                RowDivider()
                let entryPlan = CashPlanInfo.of(entry.plan)
                let entryStatus = statusMeta(entry.billingStatus)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text(String(entry.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                            .font(.brandHeading(18)).foregroundStyle(Theme.inkOnBright)
                            .frame(width: 40, height: 40)
                            .background(Theme.wash(entryPlan?.accent ?? Theme.blue, 55), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            Text("\(WorkspaceRole.label(entry.role)) · \(entryPlan?.name ?? L("No plan yet"))").font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        StatusChip(text: entryStatus.label, state: entryStatus.state)
                    }
                    if entry.clinicId == w.clinicId {
                        HStack(spacing: 6) {
                            Glyph("check", size: 16)
                            Text(L("Open now"))
                        }
                        .font(Theme.text(14, weight: .bold))
                        .foregroundStyle(Theme.blue)
                        .frame(height: 40)
                        .padding(.leading, 52)
                    } else {
                        PMButton(L("Switch to it"), systemImage: "repeat", variant: .outline, size: .compact, isWorking: switching == entry.clinicId) {
                            switching = entry.clinicId
                            Task { await workspace.choose(entry); switching = nil }
                        }
                        .disabled(switching != nil)
                        .padding(.leading, 52)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: Pieces of the cards

    /// A card's title (web `PanelTitle`): a 40 badge, the title in Fredoka 20, one line.
    private func panelTitle(_ icon: String, _ title: String, _ hint: String?, accent: Color = Theme.aqua) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(icon: icon, accent: accent, size: 40, iconSize: 20, ink: .strong)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.brandHeading(20, relativeTo: .title3)).foregroundStyle(Theme.inkStrong)
                if let hint { Text(hint).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    /// One fact about billing (web `DetailRow`): a 32 badge, the label as an eyebrow, the value; the action under it.
    private func detailRow<Action: View, Content: View>(_ icon: String, _ accent: Color, _ label: String, @ViewBuilder action: () -> Action, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(icon: icon, accent: accent, size: 32, iconSize: 16, ink: .strong)
                VStack(alignment: .leading, spacing: 4) {
                    Text(label.uppercased()).font(.brandText(10.9, weight: .heavy)).tracking(1.31).foregroundStyle(Theme.inkSoft)
                    content()
                }
                Spacer(minLength: 0)
            }
            if Action.self != EmptyView.self { action().padding(.leading, 44) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func detailRow<Content: View>(_ icon: String, _ accent: Color, _ label: String, @ViewBuilder content: () -> Content) -> some View {
        detailRow(icon, accent, label, action: { EmptyView() }, content: content)
    }

    private func rowValue(_ text: String) -> some View {
        Text(text).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
    }

    private func rowDetail(_ text: String) -> some View {
        Text(text).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
    }

    /// The muted strip at a card's foot (web: the cancel row, the receipts count).
    private func footerStrip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            RowDivider()
            content()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceMuted)
        }
    }

    // MARK: Words

    private func statusMeta(_ status: String?) -> CashPlanStatus {
        switch status {
        case "trialing": CashPlanStatus(label: L("Free trial"), state: .upcoming, short: L("Nothing charged yet"), meaning: L("Everything is open. Nothing has been charged yet."))
        case "active": CashPlanStatus(label: L("Active"), state: .done, short: L("Renews on its own"), meaning: L("Everything is open and the plan renews on its own."))
        case "grace_period": CashPlanStatus(label: L("Payment issue"), state: .waiting, short: L("The card needs updating"), meaning: L("The last charge failed. The workspace stays open while it is retried."))
        case "past_due": CashPlanStatus(label: L("Payment failed"), state: .problem, short: L("The card needs updating"), meaning: L("The last charge failed. Update the card to keep the workspace open."))
        case "canceled": CashPlanStatus(label: L("Canceled@plan"), state: .closed, short: L("Won’t renew"), meaning: L("It will not renew. The team keeps access until the paid time ends."))
        case "expired": CashPlanStatus(label: L("Ended"), state: .closed, short: L("Choose a plan to reopen"), meaning: L("The plan ended. Choose one again to reopen the workspace."))
        default: CashPlanStatus(label: L("No plan"), state: .closed, short: L("Choose a plan to start"), meaning: L("Choose a plan to open the provider tools."))
        }
    }

    private func nextEvent(_ w: ProviderWorkspace) -> (label: String, date: String?, detail: String) {
        switch w.billingStatus {
        case "trialing":
            byHand ? (L("Free days end"), w.trialEndsAt ?? w.currentPeriodEndsAt, L("Nothing is charged. After this day the workspace closes until a plan is chosen; nothing is deleted."))
                : (L("First charge"), w.trialEndsAt ?? w.currentPeriodEndsAt, store ? L("When the free days end, the store charges the plan.") : L("When the free days end, Stripe charges the card you added."))
        case "active": (L("Renews"), w.currentPeriodEndsAt, L("The plan renews and is charged on this day."))
        case "grace_period", "past_due": (L("Payment due"), w.currentPeriodEndsAt, L("Update the card so the next retry goes through."))
        case "canceled": (L("Access ends"), w.currentPeriodEndsAt, L("No more charges. The team can use the workspace until this day."))
        case "expired": (L("Ended"), w.currentPeriodEndsAt, L("The workspace is closed until a plan is chosen again."))
        default: (L("Next charge"), nil, L("Starts when a plan is chosen."))
        }
    }

    private func trialHint(_ w: ProviderWorkspace) -> String? {
        guard w.billingStatus == "trialing", let end = DateText.parse(w.trialEndsAt) else { return nil }
        let days = max(0, DateText.calendar.dateComponents([.day], from: DateText.calendar.startOfDay(for: Date()), to: DateText.calendar.startOfDay(for: end)).day ?? 0)
        return LP(days, "%d day left", "%d days left")
    }

    private func listPrice(_ amount: Int) -> String { "$\(amount.formatted()) USD" }

    /// "9 de octubre de 2026".
    private func longDate(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return "—" }
        let f = DateFormatter(); f.locale = .app; f.dateStyle = .long; f.timeStyle = .none
        return f.string(from: date)
    }

    /// "9 oct" this year, "9 oct 2027" another.
    private func shortDate(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return "—" }
        let sameYear = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date())
        let f = DateFormatter(); f.locale = .app
        f.setLocalizedDateFormatFromTemplate(sameYear ? "dMMM" : "dMMMyyyy")
        return f.string(from: date)
    }

    /// "en 14 días", "mañana", "hace 3 días".
    private func relativeDays(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return "" }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
        let f = RelativeDateTimeFormatter(); f.locale = .app; f.dateTimeStyle = .named; f.unitsStyle = .full
        return f.localizedString(from: DateComponents(day: days))
    }

    private func receiptStatus(_ status: String) -> String {
        switch status {
        case "paid": L("Paid@status")
        case "open": L("To pay")
        case "void": L("Voided")
        case "uncollectible": L("Not collected")
        case "draft": L("Draft")
        default: status
        }
    }

    private func receiptState(_ status: String) -> ProviderState {
        switch status {
        case "paid": .done
        case "open": .waiting
        case "uncollectible": .problem
        case "draft": .upcoming
        default: .closed
        }
    }

    private func notice(_ w: ProviderWorkspace, _ plan: CashPlanInfo?) -> (tone: NoticeCard.Tone, title: String, body: String, action: String?)? {
        switch w.billingStatus {
        case nil:
            return (.info, L("This workspace has no plan yet"), canManage ? L("Choose a plan to open the provider tools. New workspaces start with a free trial.") : L("The workspace owner needs to choose a plan before the team can use the provider tools."), L("Choose a plan"))
        case "trialing":
            let endsAt = w.trialEndsAt ?? w.currentPeriodEndsAt
            return (.info, endsAt.map { LF("Free trial until %@", longDate($0)) } ?? L("Free trial"),
                    byHand ? L("Nothing has been charged, and there is no card on file: our team set this plan up for you.") : store ? L("Nothing has been charged yet. When the trial ends the store charges the plan.") : L("Nothing has been charged yet."), nil)
        case "grace_period", "past_due":
            return (.warning, L("The last payment didn’t go through"), store ? L("Update the payment method in the store where the plan was bought so your team keeps access.") : canManage ? L("The workspace stays open while Stripe tries again. Update the card so your team keeps access.") : L("The workspace stays open while Stripe tries again. Ask the workspace owner to update the card."),
                    onStripe ? L("Update card") : nil)
        case "canceled", "expired":
            let endsAt = w.currentPeriodEndsAt
            let ended = (DateText.parse(endsAt) ?? .distantPast) <= Date() || w.billingStatus == "expired"
            return (.warning, ended || endsAt == nil ? L("This plan has ended") : LF("Your plan ends on %@", longDate(endsAt)),
                    ended ? L("Nothing was deleted. Choose a plan again to reopen the workspace for your team.") : canManage ? L("It won’t renew. Until then everything stays open; after that the workspace closes, and nothing is deleted. Changed your mind? Keep your plan and it renews as before.") : L("It won’t renew. Until then everything stays open; after that the workspace closes, and nothing is deleted. Only the workspace owner can keep the plan."),
                    ended ? L("Choose a plan") : onStripe ? L("Keep my plan") : nil)
        default:
            return nil
        }
    }
}

/// A plan state's words and colour (web `statusMeta`).
private struct CashPlanStatus {
    let label: String
    let state: ProviderState
    let short: String
    let meaning: String
}
