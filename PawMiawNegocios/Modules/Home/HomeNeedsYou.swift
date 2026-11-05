//
//  HomeNeedsYou.swift
//  PawMiawNegocios
//
//  "Te necesita" (web today-board.tsx `NeedsYou`): everything else that
//  needs someone today, a problem a day late first and in red. Late home
//  visits, grooms that need someone, a register left open, visits left open
//  on earlier days, "Por cobrar", notes to sign, "Reservas por confirmar"
//  (the server's count), families' requests to move or cancel, follow-ups
//  due, missing paperwork, "Te deben", "Excepciones de ayer" (money level 3),
//  stays, the hospital, grooms due back and stock. Blocks are the kit's
//  `NeedsCard`; pages are its `LinkLine`.
//

import SwiftUI

struct HomeNeedsYou: View {
    let today: HomeToday
    @ObservedObject var model: HomeModel
    let permissions: HomePermissions
    let grooms: [HomeGroomItem]
    let lateHome: [HomeHomeVisit]
    let open: (ProviderRoute) -> Void

    private var needs: HomeNeeds? { today.needsYou }
    private var currency: String? { today.currency }

    /// Whether anything here needs someone: the same things its blocks show.
    var hasAnything: Bool {
        !blocks.isEmpty
    }

    private struct Block: Identifiable {
        let id: String
        let view: AnyView
    }

    private func line(_ icon: String, _ title: String, hint: String?, attention: Bool, route: ProviderRoute) -> some View {
        NavigationLink(value: route) {
            LinkLine(title: title, icon: icon, hint: hint, attention: attention)
        }
        .buttonStyle(.plain)
    }

    private var blocks: [Block] {
        var list: [Block] = []
        func push(_ id: String, _ view: some View) { list.append(Block(id: id, view: AnyView(view))) }
        func lead(_ id: String, _ view: some View) { list.insert(Block(id: id, view: AnyView(view)), at: 0) }

        // A home visit nobody has reached past its time leads, in red: someone calls the family or goes.
        if !lateHome.isEmpty {
            let names = lateHome.flatMap { ($0.pets ?? []).compactMap(\.name) }
            push("home-late", line(
                "house",
                lateHome.count == 1 ? LF("Home visit running late: %@", names.joined(separator: ", ")) : LF("%d home visits running late", lateHome.count),
                hint: lateHome.count == 1 ? LF("%d min past its time, nobody there yet", lateHome[0].lateMinutes ?? 0) : names.prefix(3).joined(separator: ", "),
                attention: true,
                route: .section(.homeVisits)
            ))
        }

        // Grooms that need someone lead, in red, until each pet goes home or its family is told.
        if !grooms.isEmpty {
            func kinds(_ kind: String) -> Int { grooms.filter { $0.attention == kind }.count }
            let hint = [
                kinds("carried_over") > 0 ? LF("%d here since an earlier day", kinds("carried_over")) : nil,
                kinds("not_told") > 0 ? LF("%d ready, family not told", kinds("not_told")) : nil,
                kinds("late_pickup") > 0 ? LF("%d not picked up", kinds("late_pickup")) : nil,
            ].compactMap { $0 }.joined(separator: " · ")
            push("grooming", line(
                "scissors",
                grooms.count == 1 ? LF("Grooming: %@ needs you", grooms[0].pet?.name ?? "—") : LF("Grooming: %d need you", grooms.count),
                hint: hint,
                attention: true,
                route: .section(.grooming)
            ))
        }

        // A register shift left open from an earlier day comes first: today's cash must not go into it.
        for shift in (today.registers ?? []).filter({ $0.stale == true }) {
            push("shift-\(shift.sessionId)", HomeOpenShiftCard(shift: shift, canClose: permissions.register))
        }

        // Visits nobody closed stay above today's work, in amber: nothing forces closing them, so they must be hard to miss.
        if let unfinished = needs?.unfinished, (unfinished.count ?? 0) > 0 {
            let items = unfinished.items ?? []
            push("unfinished", NeedsCard(title: L("Left open on earlier days"), icon: "triangle-alert", count: unfinished.count,
                                         hint: L("Record them as done, mark them no-show or cancel them so they stop counting as open."),
                                         tone: Theme.mango, attention: .amber) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HomeUnfinishedRow(item: item, canRecord: permissions.start, first: index == 0, open: open)
                }
            })
        }

        // "Por cobrar": red while one is from an earlier day — it leads, like any other day-late problem — amber for today's.
        if let charging = needs?.charging, (charging.count ?? 0) > 0 {
            let late = (charging.earlierDays?.count ?? 0) > 0
            let card = HomeChargingBlock(charging: charging, late: late, canCharge: permissions.takePayment, canOpen: permissions.billView, open: open)
            if late { lead("charging", card) } else { push("charging", card) }
        }

        if let notes = needs?.notesToSign, (notes.count ?? 0) > 0 {
            let items = notes.items ?? []
            push("notes", NeedsCard(title: L("Notes to sign"), icon: "notebook-pen", count: notes.count, tone: Theme.mango) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HomeNoteToSignRow(item: item, canSign: permissions.sign, first: index == 0, open: open)
                }
            })
        }

        // Online bookings waiting: amber, their time is held and released if nobody answers.
        if let online = needs?.onlineRequests, (online.count ?? 0) > 0 {
            let items = online.items ?? []
            let more = (online.count ?? 0) - items.count
            push("online", NeedsCard(title: L("Bookings to confirm"), icon: "globe", count: online.count,
                                     hint: L("Booked online. The time is held until you answer."), tone: Theme.mango, attention: .amber,
                                     more: max(0, more), seeAll: { open(.section(.appointments)) }) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HomeOnlineNeedRow(item: item, canAnswer: permissions.create, first: index == 0, open: open)
                }
            })
        }

        if let requests = needs?.requests, (requests.count ?? 0) > 0 {
            let items = requests.items ?? []
            push("requests", NeedsCard(title: L("Requests to answer"), icon: "message-circle", count: requests.count, tone: Theme.aqua) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NeedsRow(
                        title: "\(item.petName ?? "—") · \(HomeText.confirmationWord(item.kind))",
                        hint: [DateText.dayTime(item.startsAt), item.preferredTime].compactMap { $0?.nonEmpty }.joined(separator: " · "),
                        first: index == 0
                    ) { EmptyView() }
                    .contentShape(Rectangle())
                    .onTapGesture { open(.appointment(item.id)) }
                    .accessibilityAddTraits(.isButton)
                }
            })
        }

        if let followUps = needs?.followUps, (followUps.dueToday ?? 0) + (followUps.overdue ?? 0) > 0 {
            let later = followUps.later ?? 0
            let items = followUps.items ?? []
            push("followups", NeedsCard(title: L("Follow-ups due"), icon: "calendar-clock", count: (followUps.dueToday ?? 0) + (followUps.overdue ?? 0), tone: Theme.blue) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HomeFollowUpRow(item: item, canRemind: permissions.followUps, first: index == 0)
                }
                HomeNeedsFooterLink(title: L("All follow-ups") + (later > 0 ? " · " + LF("%d later", later) : ""), route: .section(.notifications))
            })
        }

        // The job itself, on Records › To complete — not the notices about it.
        if let documentation = needs?.followUps?.documentation, documentation > 0 {
            push("docs", line("clipboard-pen", LF("%d finished visits still missing their note or report", documentation), hint: nil, attention: false, route: .section(.records)))
        }

        // "Te deben": what clients owe, every bill out of draft with a balance.
        if let money = needs?.money, (money.owed ?? 0) > 0 {
            let hint = [
                (money.atDesk?.amount ?? 0) > 0 ? LF("%@ at the desk, not charged", Money.format(money.atDesk?.amount, currency: currency)) : nil,
                (money.overdue ?? 0) > 0 ? LF("%@ overdue", Money.format(money.overdue, currency: currency)) : nil,
                (money.promisesDue ?? 0) > 0 ? LF("%d promises due today", money.promisesDue ?? 0) : nil,
                (money.promisesBroken ?? 0) > 0 ? LF("%d broken", money.promisesBroken ?? 0) : nil,
            ].compactMap { $0 }.joined(separator: " · ")
            push("money", line("hand-coins", LF("%@ owed to you", Money.format(money.owed, currency: currency)), hint: hint.nonEmpty, attention: (money.overdue ?? 0) > 0, route: .section(.finance)))
        }

        // "Excepciones de ayer (N)": what business finances read after a day away.
        if let exceptions = today.exceptionsYesterday, exceptions > 0, Workspace.shared.moneyLevel >= .finances {
            push("exceptions", line("triangle-alert", LF("Exceptions yesterday (%d)", exceptions), hint: L("Refunds, discounts and other moves to look at."), attention: false, route: .section(.finance)))
        }

        if let stays = needs?.stays, (stays.arriving ?? 0) + (stays.leaving ?? 0) + (stays.inHouse ?? 0) + (stays.lateArrivals ?? 0) > 0 {
            let lateOut = stays.lateDepartures ?? 0
            let lateIn = stays.lateArrivals ?? 0
            // A pet still here past its day, or one that never came, leads the list, in red, until it is dealt with.
            let late = lateOut + lateIn > 0
            let hint = [
                lateOut > 0 ? LF("%d still here past check-out", lateOut) : nil,
                lateIn > 0 ? LF("%d late arrivals", lateIn) : nil,
                (stays.arriving ?? 0) > 0 ? LF("%d arriving", stays.arriving ?? 0) : nil,
                (stays.leaving ?? 0) > 0 ? LF("%d leaving", stays.leaving ?? 0) : nil,
            ].compactMap { $0 }.joined(separator: " · ")
            let card = line("bed-double", LF("Stays: %d in house", stays.inHouse ?? 0), hint: hint.nonEmpty, attention: late, route: .section(.stays))
            if late { lead("stays", card) } else { push("stays", card) }
        }

        // The hospital: patients in, and the doses needing someone now. A dose missed or late leads, in red.
        if let hospital = today.hospital, (hospital.admitted ?? 0) + (hospital.pending ?? 0) > 0 {
            let missed = hospital.missed ?? 0, lateDoses = hospital.late ?? 0
            let urgent = missed + lateDoses > 0
            let hint = [
                missed > 0 ? (missed == 1 ? L("1 missed@dose") : LF("%d missed@dose", missed)) : nil,
                lateDoses > 0 ? (lateDoses == 1 ? L("1 late@dose") : LF("%d late@dose", lateDoses)) : nil,
                (hospital.due ?? 0) > 0 ? LF("%d due@dose", hospital.due ?? 0) : nil,
                (hospital.pending ?? 0) > 0 ? LF("%d waiting for admission", hospital.pending ?? 0) : nil,
            ].compactMap { $0 }.joined(separator: " · ")
            let admitted = hospital.admitted ?? 0
            let card = line("hospital", admitted == 1 ? L("Hospital: 1 in") : LF("Hospital: %d in", admitted), hint: hint.nonEmpty, attention: urgent, route: .section(.hospital))
            if urgent { lead("hospital", card) } else { push("hospital", card) }
        }

        if let due = needs?.due, (due.overdue ?? 0) + (due.thisWeek ?? 0) > 0 {
            let hint = [
                (due.overdue ?? 0) > 0 ? LF("Overdue: %d", due.overdue ?? 0) : nil,
                (due.thisWeek ?? 0) > 0 ? LF("This week: %d", due.thisWeek ?? 0) : nil,
            ].compactMap { $0 }.joined(separator: " · ")
            push("due", line("scissors", L("Due for grooming"), hint: hint, attention: (due.overdue ?? 0) > 0, route: .section(.due)))
        }

        if let stock = needs?.stock, (stock.low ?? 0) + (stock.out ?? 0) + (stock.expiring ?? 0) + (stock.expired ?? 0) > 0 {
            let hint = [
                (stock.out ?? 0) > 0 ? LF("%d out", stock.out ?? 0) : nil,
                (stock.low ?? 0) > 0 ? LF("%d low", stock.low ?? 0) : nil,
                (stock.expired ?? 0) > 0 ? LF("%d expired", stock.expired ?? 0) : nil,
                (stock.expiring ?? 0) > 0 ? LF("%d expiring", stock.expiring ?? 0) : nil,
            ].compactMap { $0 }.joined(separator: " · ")
            push("stock", line("boxes", L("Stock needs you"), hint: hint, attention: (stock.out ?? 0) > 0 || (stock.expired ?? 0) > 0, route: .section(.inventory)))
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Needs you@home")).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong).padding(.horizontal, 4)
            ForEach(blocks) { block in block.view }
        }
    }
}

/// "since 8:02", "since yesterday 8:02", "since Mon 3 Nov 8:02" (register/open-shift-card.tsx).
enum HomeOpenSince {
    static func text(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return "" }
        let time = DateText.time(date)
        let calendar = DateText.calendar
        if calendar.isDateInToday(date) { return LF("since %@", time) }
        if calendar.isDateInYesterday(date) { return LF("since yesterday %@", time) }
        return LF("since %@ %@", DateText.day(date), time)
    }
}

/// A block's footer link (web: "Ver todo · 3 más", "Todos los seguimientos"): 12 bold blue.
private struct HomeNeedsFooterLink: View {
    let title: String
    let route: ProviderRoute

    var body: some View {
        NavigationLink(value: route) {
            Text(title).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}

/// A register shift still open from an earlier day (web register/open-shift-card.tsx): "Caja principal abierta por
/// Ana desde ayer 8:02", with the close right here for whoever may close it. It never closes on its own.
private struct HomeOpenShiftCard: View {
    let shift: HomeRegisterShift
    let canClose: Bool
    @Environment(HomeActions.self) private var actions: HomeActions?

    var body: some View {
        NeedsCard(title: LF("%@ open by %@ %@", shift.registerName ?? L("The register"), shift.openedByName ?? "—", HomeOpenSince.text(shift.openedAt)),
                  icon: "wallet", hint: L("Count the cash and close it before today’s cash goes in."), tone: Theme.mango, attention: .amber) {
            FlowLayout(spacing: 8) {
                if canClose, let actions {
                    PMButton(L("Count and close"), systemImage: "lock", size: .compact, isWorking: actions.isBusy("shift-\(shift.sessionId)")) {
                        actions.closeShift(shift.sessionId)
                    }
                }
                NavigationLink(value: ProviderRoute.section(.store)) { PMButtonContent(title: L("Open the register"), variant: .link, size: .slim) }
                    .buttonStyle(.pm(.link, size: .slim))
                    .frame(minHeight: 40)
            }
            .padding(.top, 4)
        }
    }
}

/// "Por cobrar" on Home: the front desk's whole queue with amounts and "Ver todo" (Cuentas › Por cobrar), or what
/// this person prices (no amounts). Each row says what it was and opens its bill.
struct HomeChargingBlock: View {
    let charging: HomeChargingSummary
    let late: Bool
    let canCharge: Bool
    let canOpen: Bool
    let open: (ProviderRoute) -> Void

    private var desk: Bool { charging.scope == "desk" }

    private var hint: String {
        let currency = (charging.items ?? []).compactMap(\.currency).first
        let oldest = charging.earlierDays?.oldestDay.flatMap { DateText.parse($0) }.map { DateText.date($0) }
        return [
            desk && charging.amount != nil && currency != nil ? LF("%@ in all", Money.format(charging.amount, currency: currency)) : nil,
            late && oldest != nil ? LF("%d from earlier days, since %@", charging.earlierDays?.count ?? 0, oldest ?? "") : nil,
            desk ? nil : L("Price them so the desk can charge them."),
        ].compactMap { $0 }.joined(separator: " · ")
    }

    static func route(_ item: HomeChargingItem) -> ProviderRoute? {
        // A bill that exists opens in Cuentas; a visit without one opens the visit (its bill card).
        if let invoice = item.invoiceId { return .invoice(invoice) }
        if item.source == "visit", let appointment = item.appointmentId { return .appointment(appointment) }
        guard let source = item.sourceId else { return nil }
        return item.source == "hospital" ? .hospitalization(source) : .stay(source)
    }

    static func what(_ item: HomeChargingItem) -> String {
        switch item.source {
        case "visit": item.serviceLabel ?? ""
        case "stay": L("Stay@charge")
        case "hospital": L("Hospital")
        case "home_stay": L("Home stay")
        default: item.serviceLabel ?? ""
        }
    }

    static func stage(_ state: String?) -> String {
        switch state {
        case "no_bill": HomeText.billStageLabel("no_bill")
        case "needs_price": HomeText.billStageLabel("needs_price")
        case "unsent": HomeText.billStageLabel("building")
        default: HomeText.billStageLabel("ready")
        }
    }

    private func when(_ item: HomeChargingItem) -> String {
        item.earlierDay == true ? HomeText.dayLabel(item.day) : "\(L("Today")) \(DateText.time(item.at))"
    }

    var body: some View {
        let items = charging.items ?? []
        let more = (charging.count ?? 0) - items.count
        NeedsCard(title: desk ? L("To charge") : L("Yours to bill"), icon: "receipt", count: charging.count, hint: hint.nonEmpty,
                  tone: late ? Theme.destructive : Theme.mango, attention: late ? .red : .amber, more: desk ? 0 : max(0, more)) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let amount = item.amount.map { Money.format($0, currency: item.currency) }
                let route = canOpen ? Self.route(item) : nil
                NeedsRow(
                    title: "\((item.petNames ?? [item.petName ?? "—"]).joined(separator: ", ")) · \(Self.what(item))",
                    hint: [item.earlierDay == true ? when(item) : nil, Self.stage(item.state), amount, item.earlierDay == true ? nil : when(item)].compactMap { $0 }.joined(separator: " · "),
                    first: index == 0
                ) {
                    if desk && canCharge && item.state == "ready", let route {
                        PMButton(L("Charge"), systemImage: "hand-coins", variant: .outline, size: .compact) { open(route) }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { if let route { open(route) } }
            }
            if desk {
                HomeNeedsFooterLink(title: L("See everything") + (more > 0 ? " · " + LF("%d more", more) : ""), route: .section(.invoices))
            }
        }
    }
}

/// A note to sign: it opens its visit; whoever signs signs it here.
private struct HomeNoteToSignRow: View {
    let item: HomeNoteToSign
    let canSign: Bool
    let first: Bool
    let open: (ProviderRoute) -> Void
    @State private var signing = false

    private var late: Bool {
        guard let updated = DateText.parse(item.updatedAt) else { return false }
        return updated < DateText.calendar.startOfDay(for: Date())
    }

    var body: some View {
        NeedsRow(
            title: "\(item.petName ?? "—") · \(item.title ?? "")",
            hint: [item.author.map { LF("by %@", $0) }, late ? L("overdue") : nil].compactMap { $0 }.joined(separator: " · "),
            first: first
        ) {
            if canSign {
                PMButton(L("Sign"), systemImage: "badge-check", variant: .outline, size: .compact, isWorking: signing) { sign() }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { open(item.appointmentId.map { ProviderRoute.appointment($0) } ?? ProviderRoute.record(item.recordId)) }
    }

    private func sign() {
        signing = true
        Task {
            defer { signing = false }
            do {
                try await API.send("POST", "/provider-records/\(item.recordId)/sign", body: [:])
                Toast.show(L("Signed."))
                announceDataChanged()
            } catch {
                Toast.error(error)
            }
        }
    }
}

/// A follow-up due: remind the family in PawMiaw or on WhatsApp.
private struct HomeFollowUpRow: View {
    let item: HomeFollowUp
    let canRemind: Bool
    let first: Bool
    @Environment(\.openURL) private var openURL
    @State private var sending = false

    private struct Reminded: Decodable { let link: String? }

    var body: some View {
        NeedsRow(
            title: "\(item.petName ?? "—") · \(item.title ?? "")",
            hint: (item.clientName ?? "") + (item.overdue == true ? " · " + L("overdue") : ""),
            first: first
        ) {
            if canRemind {
                IconCircleButton(systemImage: "smartphone", label: L("Remind in PawMiaw"), tint: Theme.blue) { remind("app") }
                    .disabled(sending)
                IconCircleButton(systemImage: "message-circle", label: "WhatsApp", tint: Theme.blue) { remind("whatsapp") }
                    .disabled(sending)
            }
        }
    }

    private func remind(_ channel: String) {
        sending = true
        Task {
            defer { sending = false }
            do {
                let result: Reminded = try await API.post("/provider-follow-ups/\(item.id)/remind", body: ["channel": channel, "locale": LocalizationManager.shared.currentLanguage.rawValue])
                if channel == "whatsapp", let link = result.link, let url = URL(string: link) {
                    openURL(url)
                    Toast.show(L("WhatsApp is open with the message."))
                } else {
                    Toast.show(L("Reminder sent in PawMiaw."))
                }
                announceDataChanged()
            } catch {
                Toast.error(error)
            }
        }
    }
}

/// A visit left open since an earlier day: "Sí vino" records it; "Abrir" opens it to mark no-show or cancel.
private struct HomeUnfinishedRow: View {
    let item: HomeUnfinishedVisit
    let canRecord: Bool
    let first: Bool
    let open: (ProviderRoute) -> Void
    @Environment(HomeActions.self) private var actions: HomeActions?

    var body: some View {
        // What the family said when asked the next morning.
        let answer: String? = item.familyAttendance == "attended" ? L("family says they went") : (item.familyAttendance == "not_attended" ? L("family says they didn’t go") : nil)
        NeedsRow(
            title: "\(item.petName ?? "—") · \(item.serviceLabel ?? "")",
            hint: [DateText.date(item.startsAt), HomeText.leftOpenWord(item.status), answer].compactMap { $0 }.joined(separator: " · "),
            first: first
        ) {
            if canRecord, let actions {
                PMButton(L("They came"), systemImage: "badge-check", variant: .outline, size: .compact, isWorking: actions.isBusy(item.id)) { actions.recordPast(item.id) }
            }
            PMButton(L("Open@needs"), variant: .outline, size: .compact) { open(.appointment(item.id)) }
        }
        .contentShape(Rectangle())
        .onTapGesture { open(.appointment(item.id)) }
    }
}

/// A family's online booking: answered over Home (Confirmar, Cambiar hora y confirmar, Rechazar).
private struct HomeOnlineNeedRow: View {
    let item: HomeOnlineRequest
    let canAnswer: Bool
    let first: Bool
    let open: (ProviderRoute) -> Void
    @Environment(HomeActions.self) private var actions: HomeActions?

    var body: some View {
        // "Se libera en 3 horas" on its own line: on a phone it would be cut off at the end of the hint.
        let release = HomeText.releaseIn(item.releasesAt).map { LF("Released %@", $0) }
        NeedsRow(
            title: "\((item.pets ?? []).compactMap(\.name).joined(separator: ", ")) · \(item.serviceLabel ?? "")",
            hint: [[DateText.dayTime(item.startsAt), item.client?.name].compactMap { $0 }.joined(separator: " · "), release].compactMap { $0 }.joined(separator: "\n"),
            first: first
        ) {
            if canAnswer {
                PMButton(L("Answer"), variant: .outline, size: .compact, isWorking: actions?.isBusy(item.appointmentId) ?? false) { answer() }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { answer() }
    }

    private func answer() {
        if let actions { actions.answerOnline(item.appointmentId) } else { open(.appointment(item.appointmentId)) }
    }
}
