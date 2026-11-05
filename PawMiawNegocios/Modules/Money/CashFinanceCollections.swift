//
//  CashFinanceCollections.swift
//  PawMiawNegocios
//
//  "Te deben" (web: finance/finance-collections.tsx, finance-client-sheet.tsx):
//  who owes, how late, the promises to pay and the last contact; one client's
//  account — what is open, the movements, collect a payment (oldest debt
//  first), take a deposit, a note or a promise, a reminder, the credit limit.
//  The list is the front desk's (level 2); one account is level 1.
//
//  The account is a modal on the web; here it is a page of its own with the
//  modal's head as its module header (pink, HandCoins) and its sections as cards.
//

import SwiftUI

// MARK: - Who owes (level 2)

struct CashFinanceCollections: View {
    /// Who is listed: all, an aging bucket, or a follow-up filter (the overview's figures set it).
    @Binding var filter: String
    /// A client's account; `true` opens it on "Collect" (a row's button).
    let onClient: (String, Bool) -> Void
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var data: CashCollections?
    @State private var error: String?
    @State private var query = ""
    @State private var shown = 20

    private var canRecord: Bool { workspace.can(.billingRecordPayment) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let summary = data?.summary {
                CashFinGrid(items: CashText.agingBuckets.map { AnyView(bucketTile($0, summary)) }, columns: sizeClass == .regular ? 4 : 2, spacing: 8)
            }
            SearchField(prompt: L("Client, pet or phone"), text: $query)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let summary = data?.summary
                    ToneChip(L("Overdue"), icon: "triangle-alert", tone: .state(.problem), count: summary?.overdueClients, isOn: filter == "overdue") { toggle("overdue") }
                    ToneChip(L("Promises"), icon: "handshake", tone: .state(.upcoming), count: summary.map { $0.promisesDue + $0.promisesBroken + $0.promisesPending }, isOn: filter == "promises") { toggle("promises") }
                    ToneChip(L("Not contacted"), icon: "bell-ring", tone: .state(.waiting), count: summary?.uncontacted, isOn: filter == "uncontacted") { toggle("uncontacted") }
                    if let over = summary?.overLimit, over > 0 {
                        ToneChip(L("Over their limit"), icon: "shield-alert", tone: .state(.problem), count: over, isOn: filter == "over_limit") { toggle("over_limit") }
                    }
                }
                .padding(.vertical, 1)
            }
            HStack {
                CashCSVButton(disabled: data?.items.isEmpty ?? true) {
                    guard let data else { throw CancellationError() }
                    return (CashCSV.fileName(L("receivables"), from: data.today, to: data.today), CashFinanceCSV.collections(data))
                }
                Spacer(minLength: 0)
            }
            if let data {
                list(data)
                if let credits = data.credits, !credits.isEmpty { creditsSection(credits, currency: data.summary.currency) }
            } else if let error {
                CashFinError(title: L("Who owes could not be loaded."), message: error) { await load() }
            } else {
                LoadingState()
            }
        }
        .debounced(query) { _ in await load() }
        .onChange(of: filter) { _, _ in Task { await load() } }
        .reloadsOnScope { await load() }
    }

    private func toggle(_ next: String) {
        filter = filter == next ? "all" : next
    }

    /// One aging bucket (web: the tiles over the list): its dot, name, amount and clients; a filter.
    private func bucketTile(_ bucket: String, _ summary: CashCollections.Summary) -> some View {
        let amount = summary.aging?[bucket]
        let clients = summary.agingClients?[bucket] ?? 0
        let active = filter == bucket
        return Button { toggle(bucket) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(CashFinAging.tone(bucket)).frame(width: 8, height: 8)
                    Text(CashText.aging(bucket).uppercased()).font(.brandText(10.6, weight: .heavy)).tracking(0.85).foregroundStyle(Theme.inkSoft).lineLimit(2)
                }
                Text(amount.map { cashMoney($0, summary.currency) } ?? "—")
                    .font(.brandHeading(18)).monospacedDigit()
                    .foregroundStyle(bucket == "d61_plus" && (amount ?? 0) > 0 ? Theme.destructive : Theme.inkStrong)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.top, 6)
                Text(LP(clients, "%d client", "%d clients")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(active ? Theme.inkStrong : Theme.borderSoft, lineWidth: 2))
            .shadow(color: active ? Theme.navy.opacity(0.1) : .clear, radius: 1.5, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(amount == nil)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder private func list(_ data: CashCollections) -> some View {
        if data.items.isEmpty {
            let everyone = filter == "all" && query.isEmpty
            ListCard {
                EmptyState(systemImage: "circle-check", title: everyone ? L("Nobody owes you anything.") : L("No one here."),
                           message: everyone ? L("Sales and bills left unpaid show up here.") : L("Try another filter or search."),
                           actionTitle: everyone ? nil : L("Show everyone who owes"), action: { filter = "all"; query = "" }, accent: Theme.lime)
            }
        } else {
            ListCard {
                LazyVStack(spacing: 0) {
                    ForEach(Array(data.items.prefix(shown).enumerated()), id: \.element.id) { index, item in
                        if index > 0 { RowDivider() }
                        CashCollectionRow(item: item, today: data.today, canRecord: canRecord) { collect in onClient(item.providerClientId, collect) }
                            .onAppear { if index >= shown - 3 && shown < data.items.count { shown += 20 } }
                    }
                }
            }
            let owed = data.items.reduce(0) { $0 + $1.owed }
            CashFinListCount(text: LP(data.items.count, "%d client owes", "%d clients owe"),
                             trailing: filter == "all" && query.isEmpty
                                ? LF("%@ owed in total", cashMoney(owed, data.summary.currency))
                                : LF("%@ owed by these clients · %@ by everyone", cashMoney(owed, data.summary.currency), cashMoney(data.summary.owed, data.summary.currency)))
        }
    }

    /// The other side of the ledger: clients who paid ahead.
    private func creditsSection(_ credits: [CashCollections.Credit], currency: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Glyph("piggy-bank", size: 16).foregroundStyle(Theme.inkSoft)
                    Text(L("Credit on account")).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                }
                Text(L("Deposits paid ahead and not spent yet. You owe these clients the work, or the money back.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            ListCard {
                ForEach(Array(credits.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { RowDivider() }
                    Button { onClient(row.providerClientId, false) } label: {
                        HStack(spacing: 12) {
                            Avatar(name: row.name, imageURL: row.photoUrl, size: 36, tint: ProviderState.done.color)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                if row.owed > 0 {
                                    Text(LF("Also owes %@ — the credit can pay it", cashMoney(row.owed, currency))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                                }
                            }
                            Spacer(minLength: 8)
                            Text(cashMoney(row.credit, currency)).font(.brandHeading(18)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            CashFinListCount(text: LP(credits.count, "%d client holds credit", "%d clients hold credit"),
                             trailing: LF("%@ held in total", cashMoney(credits.reduce(0) { $0 + $1.credit }, currency)))
        }
    }

    private func load() async {
        do {
            data = try await API.get("/provider-finance/collections", query: ["filter": filter, "q": query.nonEmpty, "locationId": workspace.listLocationFilter])
            error = nil
            shown = 20
        } catch {
            if data == nil { self.error = errorText(error) }
        }
    }
}

/// One client who owes (web `CollectionRow`): their face, the pets and open bills, the chips (how
/// late, the promise, over the limit, credit to apply, the last contact), what they owe and "Collect".
struct CashCollectionRow: View {
    let item: CashCollectionItem
    let today: String
    var canRecord: Bool = false
    /// `true`: open straight on "Collect".
    let onOpen: (Bool) -> Void

    private var money: (Int) -> String { { cashMoney($0, item.currency) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { onOpen(false) } label: {
                HStack(alignment: .top, spacing: 12) {
                    Avatar(name: item.name, imageURL: item.photoUrl, size: 44, tint: Theme.pink)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.walkIn == true ? L("Walk-in sales") : item.name).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            if item.onPawMiaw == true {
                                Glyph("smartphone", size: 14).foregroundStyle(Theme.inkSoft).accessibilityLabel(L("On PawMiaw"))
                            }
                        }
                        Text(([(item.petNames ?? []).isEmpty ? nil : (item.petNames ?? []).joined(separator: ", "), LP(item.documents, "%d open bill", "%d open bills")] as [String?]).compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        FlowLayout(spacing: 6) { chips }
                            .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(money(item.owed)).font(.brandHeading(20)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    if item.overdue > 0 && item.overdue < item.owed {
                        Text(LF("%@ overdue", money(item.overdue))).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.destructive)
                    }
                }
                Spacer(minLength: 8)
                if canRecord {
                    PMButton(L("Collect"), systemImage: "hand-coins") { onOpen(true) }
                        .accessibilityLabel(LF("Collect from %@", item.name))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder private var chips: some View {
        if item.daysOverdue > 0 {
            Chip(text: CashText.daysLate(item.daysOverdue), tone: .danger)
        } else if let due = item.oldestDueDay {
            Chip(text: due == today ? L("Due today") : LF("Due %@", CashDay.short(due)), tone: .info)
        }
        if let promise = item.promise {
            CashPromiseChip(status: promise.status, day: promise.promisedOn, amount: promise.promisedAmount.map { money($0) })
        }
        if item.overLimit == true, let limit = item.creditLimitAmount {
            Chip(text: LF("Over %@ limit", money(limit)), tone: .danger)
        }
        if let credit = item.credit, credit > 0 {
            Chip(text: LF("%@ of credit to apply", money(credit)), tone: .good, icon: "piggy-bank")
        }
        Chip(text: lastContact, tone: .muted)
    }

    private var lastContact: String {
        guard let at = DateText.parse(item.lastContactAt) else { return L("Never contacted") }
        let days = DateText.calendar.dateComponents([.day], from: DateText.calendar.startOfDay(for: at), to: DateText.calendar.startOfDay(for: Date())).day ?? 0
        let when = days == 0 ? L("today") : days == 1 ? L("yesterday") : LF("%d days ago", days)
        if item.lastContactKind == "reminder" {
            let channel = item.lastContactChannel == "whatsapp" ? "WhatsApp" : item.lastContactChannel == "email" ? L("email") : L("the app")
            return LF("Reminded by %@ %@", channel, when)
        }
        return LF("Note %@", when)
    }
}

/// A promise to pay on a row or in the history (web `PromiseChip`).
struct CashPromiseChip: View {
    let status: String
    let day: String
    let amount: String?

    var body: some View {
        let what = amount.map { LF("%@ by %@", $0, CashDay.short(day)) } ?? LF("by %@", CashDay.short(day))
        switch status {
        case "kept": Chip(text: LF("Kept: %@", what), tone: .good, icon: "calendar-check")
        case "broken": Chip(text: LF("Broken: %@", what), tone: .danger, icon: "handshake")
        case "due": Chip(text: amount.map { LF("Promised %@ today", $0) } ?? L("Promised to pay today"), tone: .warn, icon: "handshake")
        default: Chip(text: LF("Promised %@", what), tone: .info, icon: "handshake")
        }
    }
}

// MARK: - One client's account (level 1)

struct CashAccountScreen: View {
    let clientId: String
    /// Opened from a row's "Collect": straight to collecting.
    var collect: Bool = false
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.openURL) private var openURL
    @StateObject private var loader: Loader<CashAccount>
    @State private var collecting = false
    @State private var depositing = false
    @State private var noting = false
    @State private var limiting = false
    @State private var reminding: String?
    @State private var allMovements = false
    @State private var focusTaken = false
    @State private var openClient = false

    init(clientId: String, collect: Bool = false) {
        self.clientId = clientId
        self.collect = collect
        _loader = StateObject(wrappedValue: Loader<CashAccount> { try await API.get("/provider-finance/clients/\(clientId)/account") })
    }

    private var canRecord: Bool { workspace.can(.billingRecordPayment) }

    var body: some View {
        PageScroll(refresh: { await loader.load() }) {
            if workspace.moneyLevel < .charging {
                NoAccessState()
            } else {
                LoadedContent(loader: loader) { account in content(account) }
            }
        }
        .providerPage(loader.value.map { $0.client.walkIn == true ? L("Walk-in sales") : $0.client.name } ?? L("Account"))
        .reloadsOnScope { await loader.load() }
        .onChange(of: loader.value?.client.id) { _, _ in
            // A row's "Collect": once the account is here, collecting opens.
            guard collect, !focusTaken, let account = loader.value else { return }
            focusTaken = true
            if account.owed > 0 && canRecord { collecting = true }
        }
        .sheet(isPresented: $collecting) { if let account = loader.value { CashCollectSheet(account: account) { Task { await loader.load() } } } }
        .sheet(isPresented: $depositing) { if let account = loader.value { DepositSheet(clientId: account.client.id, clientName: account.client.name) { await loader.load() } } }
        .sheet(isPresented: $noting) { if let account = loader.value { CashNoteSheet(account: account) { Task { await loader.load() } } } }
        .sheet(isPresented: $limiting) { if let account = loader.value { CashCreditLimitSheet(account: account) { Task { await loader.load() } } } }
        .navigationDestination(isPresented: $openClient) { RouteView(route: .client(clientId)) }
    }

    // MARK: The page

    @ViewBuilder private func content(_ account: CashAccount) -> some View {
        let money = { (cents: Int) in cashMoney(cents, account.currency) }
        header(account, money)
        if account.owed > 0 && account.credit > 0 {
            NoticeCard(tone: .success, title: LF("They hold %@ of credit: it can pay what they owe — choose “Credit on account” when collecting.", money(account.credit)))
        }
        if !account.open.isEmpty { openBills(account, money) }
        movements(account, money)
        if account.owed > 0 && workspace.moneyLevel >= .frontDesk { remind(account) }
        if workspace.moneyLevel >= .frontDesk { followUp }
        timeline(account, money)
        if account.client.walkIn != true && (account.credit > 0 || canRecord) { credit(account, money) }
        if account.client.walkIn != true { creditLimit(account, money) }
    }

    /// The modal's head as the page's header: what they owe, the three figures, the account's actions.
    private func header(_ account: CashAccount, _ money: @escaping (Int) -> String) -> some View {
        let subtitle = account.owed > 0
            ? (account.overdue > 0 ? LF("Owes %@ · %@ overdue", money(account.owed), money(account.overdue)) : LF("Owes %@", money(account.owed)))
            : account.credit > 0 ? LF("Owes nothing · %@ of credit", money(account.credit)) : L("Nothing owed")
        let pets = Array(Set(account.open.compactMap { $0.petName?.nonEmpty })).sorted()
        return ModuleHeader(
            icon: "hand-coins",
            title: account.client.walkIn == true ? L("Walk-in sales") : account.client.name,
            subtitle: subtitle,
            accent: Theme.pink,
            stats: [
                ModuleStat("owes", label: L("Owes"), value: money(account.owed), icon: "hand-coins", accent: Theme.pink),
                ModuleStat("overdue", label: L("Overdue"), value: money(account.overdue), icon: "alarm-clock", accent: ProviderState.problem.color, attention: account.overdue > 0),
                ModuleStat("credit", label: L("Credit on account"), value: money(account.credit), icon: "piggy-bank", accent: ProviderState.done.color),
            ],
            actionsOnRow: true,
            storageKey: "finance-account"
        ) {
            if canRecord && account.owed > 0 {
                PMButton(L("Collect"), systemImage: "hand-coins") { collecting = true }
            }
            DocumentButton(title: L("Download PDF"), systemImage: "file-down", path: "/provider-finance/clients/\(account.client.id)/statement/pdf", fileName: "\(account.client.name) \(account.today)")
            if workspace.can(.clientsView) && account.client.walkIn != true {
                PMButton(L("Open client"), systemImage: "user-round", variant: .outline) { openClient = true }
            }
        } footer: {
            if account.client.walkIn != true && (!pets.isEmpty || account.client.onPawMiaw == true) {
                VStack(spacing: 0) {
                    RowDivider()
                    FlowLayout(spacing: 6) {
                        ForEach(pets, id: \.self) { pet in Chip(text: pet, tone: .muted, icon: "paw-print") }
                        if account.client.onPawMiaw == true { Chip(text: L("On PawMiaw"), tone: .info, icon: "smartphone") }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: What is open

    private func openBills(_ account: CashAccount, _ money: @escaping (Int) -> String) -> some View {
        SectionCard(L("What is open"), subtitle: L("Oldest first — the order a payment settles them.")) {
            VStack(spacing: 0) {
                ForEach(Array(account.open.enumerated()), id: \.element.id) { index, bill in
                    if index > 0 { RowDivider() }
                    // A store sale opens its sale; a bill opens the bill (its refunds live there).
                    NavigationLink(value: bill.source == "store" ? ProviderRoute.sale(bill.id) : ProviderRoute.invoice(bill.id)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(bill.folio).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(Theme.inkStrong)
                                Text([CashText.source(bill.source), bill.petName, bill.dueDay.map { LF("Due %@", CashDay.short($0)) }].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(money(bill.balanceDueAmount)).font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                                if bill.daysOverdue > 0 {
                                    Text(CashText.daysLate(bill.daysOverdue)).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.destructive)
                                } else if bill.amountPaid > 0 {
                                    Text(LF("of %@", money(bill.totalAmount - (bill.refundedAmount ?? 0)))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                                }
                            }
                            Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ListFooter(count: LP(account.open.count, "%d open bill", "%d open bills"), detail: LF("%@ owed in total", money(account.owed)))
            }
        }
    }

    // MARK: Movements

    @ViewBuilder private func movements(_ account: CashAccount, _ money: @escaping (Int) -> String) -> some View {
        let entries = Array(account.statement.reversed())
        if !entries.isEmpty {
            let shown = allMovements ? entries : Array(entries.prefix(6))
            SectionCard(L("Movements"), subtitle: L("Charges add to the balance; payments and deposits take from it. A balance below zero is credit they hold.")) {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, entry in
                        if index > 0 { RowDivider() }
                        movementRow(entry, account, money)
                    }
                    ListFooter(count: shown.count < entries.count ? LF("Showing %d of %d", shown.count, entries.count) : LP(entries.count, "%d movement", "%d movements")) {
                        if entries.count > 6 {
                            Button(allMovements ? L("Show fewer") : L("Show all")) { withAnimation { allMovements.toggle() } }
                                .font(Theme.text(14, weight: .bold))
                                .foregroundStyle(Theme.blue)
                        }
                    }
                }
            }
        }
    }

    private func movementRow(_ entry: CashAccount.Entry, _ account: CashAccount, _ money: @escaping (Int) -> String) -> some View {
        let charge = entry.type == "charge"
        let deposit = entry.label == "Deposit" || entry.label == "Deposit returned"
        let what = charge ? L("Charge") : entry.label == "Deposit" ? L("Deposit") : entry.label == "Deposit returned" ? L("Deposit returned") : entry.type == "refund" ? L("Refund") : L("Payment")
        let zone = account.timeZone.flatMap(TimeZone.init(identifier:))
        let day = DateText.parse(entry.at).map { CashDay.short(DateText.dayKey($0, zone: zone)) }
        let line = [day, charge ? entry.source.map { CashText.source($0) } : entry.method.map { CashText.method($0) }, deposit ? nil : entry.label].compactMap { $0?.nonEmpty }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                (Text(what).font(Theme.text(14, weight: .bold)) + Text(entry.folio?.nonEmpty.map { " · \($0)" } ?? "").font(.system(size: 13, design: .monospaced)).foregroundColor(Theme.inkSoft))
                    .foregroundStyle(Theme.inkStrong).lineLimit(1)
                Text(line.joined(separator: " · ")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(entry.type == "payment" ? "−" : "+")\(money(abs(entry.amount)))").font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                Text(entry.balance < 0 ? LF("Credit %@", money(-entry.balance)) : LF("Balance %@", money(entry.balance))).font(Theme.text(12)).monospacedDigit().foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Send a reminder

    private func remind(_ account: CashAccount) -> some View {
        SectionCard(L("Send a reminder"), subtitle: L("The message says what they owe. Every reminder is written down as the last contact.")) {
            VStack(spacing: 8) {
                reminderButton(account, "whatsapp", "WhatsApp", account.client.phone != nil ? L("A message with the amount") : L("No phone on file"), "message-circle", account.client.phone != nil)
                reminderButton(account, "email", L("Email"), account.client.email ?? L("No email on file"), "mail", account.client.email != nil)
                reminderButton(account, "app", L("In PawMiaw"), account.client.onPawMiaw == true ? L("A notification on their phone") : L("Not on PawMiaw"), "smartphone", account.client.onPawMiaw == true)
            }
            .padding(16)
        }
    }

    private func reminderButton(_ account: CashAccount, _ channel: String, _ title: String, _ hint: String, _ icon: String, _ available: Bool) -> some View {
        Button { send(account, channel) } label: {
            HStack(spacing: 12) {
                Group {
                    if reminding == channel { ProgressView().controlSize(.small) } else { Glyph(icon, size: 16) }
                }
                .foregroundStyle(Theme.inkStrong)
                .frame(width: 32, height: 32)
                .background(Theme.surfaceMuted, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    Text(hint).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!available || reminding != nil)
        .opacity(available ? 1 : 0.5)
    }

    private func send(_ account: CashAccount, _ channel: String) {
        reminding = channel
        Task {
            defer { reminding = nil }
            do {
                struct Sent: Decodable { let channel: String; let message: String?; let link: String?; let sentTo: Int? }
                let sent: Sent = try await API.post("/provider-finance/clients/\(account.client.id)/remind", body: ["channel": channel, "locale": LocalizationManager.shared.currentLanguage.rawValue])
                if channel == "whatsapp", let link = sent.link.flatMap(URL.init(string:)) {
                    openURL(link)
                    Toast.show(L("WhatsApp is open with the message. Send it from there."))
                } else if channel == "app" {
                    Toast.show(LF("Reminder sent to %@’s PawMiaw.", account.client.firstName ?? account.client.name))
                } else {
                    Toast.show(LF("Reminder emailed to %@.", account.client.email ?? ""))
                }
                await loader.load()
            } catch {
                Toast.error(error)
            }
        }
    }

    // MARK: Follow up, history

    private var followUp: some View {
        SectionCard(L("Follow up"), subtitle: L("What you talked about, and when they said they would pay.")) {
            HStack {
                PMButton(L("Write a note or a promise"), systemImage: "notebook-pen", variant: .outline, size: .compact) { noting = true }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

    @ViewBuilder private func timeline(_ account: CashAccount, _ money: @escaping (Int) -> String) -> some View {
        if !account.notes.isEmpty {
            SectionCard(L("History")) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(account.notes) { note in
                        HStack(alignment: .top, spacing: 12) {
                            Glyph(note.kind == "promise" ? "handshake" : note.kind == "reminder" ? "bell-ring" : "file-text", size: 16)
                                .foregroundStyle(Theme.inkSoft)
                                .frame(width: 32, height: 32)
                                .background(Theme.surfaceMuted, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text([note.author, CashDay.when(note.createdAt, zone: account.timeZone.flatMap(TimeZone.init(identifier:))), note.balanceAmount.map { LF("owed %@", money($0)) }].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                                if note.kind == "reminder" {
                                    Text(note.channel == "whatsapp" ? L("Reminder by WhatsApp") : note.channel == "email" ? L("Reminder by email") : L("Reminder in PawMiaw"))
                                        .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                                }
                                if note.kind == "promise", let day = note.promisedOn, let status = note.promiseStatus {
                                    CashPromiseChip(status: status, day: day, amount: note.promisedAmount.map { money($0) })
                                }
                                if let body = note.body?.nonEmpty, note.kind != "reminder" {
                                    Text(body).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: Credit and its limit

    private func credit(_ account: CashAccount, _ money: @escaping (Int) -> String) -> some View {
        SectionCard(L("Credit on account"), subtitle: L("Deposits they can spend at checkout.")) {
            HStack(spacing: 12) {
                Glyph("piggy-bank", size: 20).foregroundStyle(Theme.inkSoft)
                Text(money(account.credit)).font(.brandHeading(20)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                Spacer(minLength: 8)
                if canRecord {
                    PMButton(L("Take a deposit"), systemImage: "hand-coins", variant: .outline, size: .compact) { depositing = true }
                }
            }
            .padding(16)
        }
    }

    private func creditLimit(_ account: CashAccount, _ money: @escaping (Int) -> String) -> some View {
        SectionCard(title: L("Credit limit"), subtitle: L("The most they can owe. The store will not sell on account past it.")) {
            if workspace.can(.billingManage) {
                PMButton(L("Edit"), variant: .outline, size: .compact) { limiting = true }
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 8) {
                    HStack(spacing: 8) {
                        Glyph("shield-check", size: 16).foregroundStyle(Theme.inkSoft)
                        Text(account.client.creditLimitAmount.map { LF("Up to %@", money($0)) } ?? L("No limit")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    }
                    if let limit = account.client.creditLimitAmount, account.owed > limit { Chip(text: L("Over the limit"), tone: .danger) }
                }
                if !workspace.can(.billingManage) {
                    Text(L("Only billing managers can change it.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Sheets on an account

/// One payment, applied to the oldest debt first (web: the account's "Collect" step).
struct CashCollectSheet: View {
    let account: CashAccount
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @StateObject private var device = CashDeviceRegister()
    @StateObject private var form = FormState()
    @State private var amount: Int?
    @State private var method = "cash"
    @State private var reference = ""
    @State private var working = false
    @State private var requestId = cashRequestId()
    @State private var seed = 0

    private var methods: [String] { CashText.methods + (account.credit > 0 ? ["credit"] : []) }
    private var money: (Int) -> String { { cashMoney($0, account.currency) } }

    /// How the amount settles the open bills, oldest first, and what would be left over.
    private var preview: (parts: [(folio: String, amount: Int, settles: Bool)], leftover: Int) {
        var left = amount ?? 0
        var parts: [(folio: String, amount: Int, settles: Bool)] = []
        for bill in account.open where left > 0 {
            let take = min(left, bill.balanceDueAmount)
            parts.append((folio: bill.folio, amount: take, settles: take >= bill.balanceDueAmount))
            left -= take
        }
        return (parts: parts, leftover: max(0, left))
    }

    var body: some View {
        let pets = Array(Set(account.open.compactMap { $0.petName?.nonEmpty })).sorted()
        ProviderModal(title: L("Collect a payment"), subtitle: L("One payment, applied to the oldest debt first."), systemImage: "hand-coins", accent: .pink, isDirty: amount != account.owed || method != "cash", form: form, primaryTitle: L("Collect"), isWorking: working, cancelTitle: L("Back"), primaryIcon: "hand-coins") {
            submit()
        } content: {
            // Who pays and what they owe (web `ModalContextPills` with the "Owes" pill).
            ContextPills(client: account.client.walkIn == true ? nil : account.client.name, pets: pets) {
                Chip(text: LF("Owes %@", money(account.owed)), tone: .muted, size: .large)
            }
            ModalSection(title: L("Amount received")) {
                MoneyField(label: L("Amount received"), cents: $amount, key: "amount", form: form)
                    .id(seed)
                PMButton(L("All of it"), variant: .outline, size: .compact) {
                    amount = method == "credit" ? min(account.owed, account.credit) : account.owed
                    seed += 1
                    requestId = cashRequestId()
                }
                if (amount ?? 0) > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        if preview.leftover > 0 {
                            Text(LF("That is %@ more than they owe.", money(preview.leftover))).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.destructive)
                        } else {
                            ForEach(Array(preview.parts.enumerated()), id: \.offset) { _, part in
                                HStack {
                                    Text(part.folio).font(.system(size: 14, design: .monospaced)).foregroundStyle(Theme.inkStrong)
                                    Spacer(minLength: 12)
                                    Text(part.settles ? LF("%@ · paid in full", money(part.amount)) : LF("%@ on account", money(part.amount))).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                }
            }
            ModalSection(title: L("How they paid")) {
                FlowLayout(spacing: 8) {
                    ForEach(methods, id: \.self) { entry in
                        CashMethodPill(title: CashText.method(entry), isOn: method == entry) { method = entry; requestId = cashRequestId() }
                    }
                }
                if method == "credit" {
                    let over = (amount ?? 0) > account.credit
                    Text(LF("From their deposits: %@ available.", money(account.credit))).font(Theme.text(14, weight: over ? .bold : .regular)).foregroundStyle(over ? Theme.destructive : Theme.inkSoft)
                } else if method != "cash" {
                    PMTextField(L("Reference"), text: $reference, prompt: L("Reference (authorization, transfer…)"))
                }
                CashRegisterGate(device: device, wantsCash: method == "cash")
            }
        }
        .modifier(CashKeepsRegister(device: device))
        .onAppear { amount = account.owed; seed += 1 }
    }

    private func submit() {
        let value = amount ?? 0
        guard form.check([
            ("amount", value <= 0 ? L("Enter the amount received") : value > account.owed ? LF("That is %@ more than they owe.", money(value - account.owed)) : method == "credit" && value > account.credit ? LF("They have %@ of credit", money(account.credit)) : nil),
        ]) else { return }
        if method == "cash" && device.sessionId == nil { Toast.error(L("Open the register to take cash")); return }
        working = true
        Task {
            defer { working = false }
            do {
                let result: CashCollectResult = try await API.post("/provider-finance/clients/\(account.client.id)/collect", body: [
                    "amount": value, "method": method, "reference": method == "credit" ? nil : reference.nonEmpty,
                    "registerSessionId": method == "credit" ? nil : device.sessionId, "clientRequestId": requestId,
                ])
                if result.replayed == true {
                    Toast.show(LF("That payment was already recorded: %@ collected, nothing taken twice.", money(result.collected)))
                } else {
                    Toast.show(result.owedAfter > 0 ? LF("%@ collected. %@ still owed.", money(result.collected), money(result.owedAfter)) : LF("%@ collected. The account is paid up.", money(result.collected)))
                }
                NotificationCenter.default.post(name: CashDeviceRegister.changed, object: nil)
                announceDataChanged()
                onDone()
                dismiss()
            } catch {
                form.apply(error, known: ["amount": "amount"])
            }
        }
    }
}

/// What was talked about, and when they said they would pay (web: the account's "Follow up").
struct CashNoteSheet: View {
    let account: CashAccount
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var body_ = ""
    @State private var promising = false
    @State private var promisedOn = ""
    @State private var promised: Int?
    @State private var working = false

    var body: some View {
        ProviderModal(title: L("Follow up"), subtitle: L("What you talked about, and when they said they would pay."), systemImage: "notebook-pen", accent: .pink, isDirty: !body_.isEmpty || promising, form: form, primaryTitle: promising ? L("Save promise") : L("Save note"), isWorking: working, primaryIcon: "notebook-pen") {
            submit()
        } content: {
            PMTextField(L("Note"), text: $body_, key: "body", form: form, prompt: L("Called, will pay on Friday…"), optional: promising, multiline: true)
            ToggleRow(title: L("They promised to pay"), isOn: $promising)
            if promising {
                // A week from the business's today, never the device's.
                DayField(label: L("By@day"), day: $promisedOn, min: account.today)
                MoneyField(label: L("Amount (optional)"), cents: $promised, optional: true)
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { if promisedOn.isEmpty { promisedOn = CashDay.shift(account.today, 7) } }
    }

    private func submit() {
        guard form.check([("body", !promising && body_.nonEmpty == nil ? L("Write the note") : nil)]) else { return }
        working = true
        Task {
            defer { working = false }
            do {
                struct Saved: Decodable { let id: String }
                let _: Saved = try await API.post("/provider-finance/clients/\(account.client.id)/notes", body: [
                    "kind": promising ? "promise" : "note", "body": body_.nonEmpty, "promisedAmount": promising ? promised : nil, "promisedOn": promising ? promisedOn : nil,
                ])
                Toast.show(promising ? L("Promise saved. It shows as kept once they pay.") : L("Note saved."))
                announceDataChanged()
                onDone()
                dismiss()
            } catch {
                form.apply(error, known: ["body": "body"])
            }
        }
    }
}

/// The most they can owe (web: the account's "Credit limit").
struct CashCreditLimitSheet: View {
    let account: CashAccount
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var limit: Int?
    @State private var working = false
    @State private var seed = 0

    var body: some View {
        let current = account.client.creditLimitAmount
        ProviderModal(title: L("Credit limit"), subtitle: L("The most they can owe. The store will not sell on account past it."), systemImage: "shield-check", accent: .pink, isDirty: limit != current, form: form, primaryTitle: L("Save limit"), isWorking: working,
                      secondaryActions: current != nil ? [ModalAction(L("Remove")) { save(nil) }] : []) {
            save(limit)
        } content: {
            MoneyField(label: L("Credit limit"), cents: $limit, key: "limit", form: form, hint: current.map { LF("Up to %@", cashMoney($0, account.currency)) } ?? L("No limit"), optional: true)
                .id(seed)
            if let current, account.owed > current {
                Chip(text: L("Over the limit"), tone: .danger, size: .medium)
            }
        }
        .presentationDetents([.medium])
        .onAppear { limit = account.client.creditLimitAmount; seed += 1 }
    }

    private func save(_ value: Int?) {
        working = true
        Task {
            defer { working = false }
            do {
                struct Saved: Decodable { let creditLimitAmount: Int? }
                let _: Saved = try await API.put("/provider-finance/clients/\(account.client.id)/credit-limit", body: ["creditLimitAmount": value])
                Toast.show(value.map { LF("Limit set to %@.", cashMoney($0, account.currency)) } ?? L("No limit now."))
                announceDataChanged()
                onDone()
                dismiss()
            } catch {
                form.apply(error, known: ["creditLimitAmount": "limit"])
            }
        }
    }
}
