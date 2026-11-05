//
//  RecordsListModel.swift
//  PawMiawNegocios
//
//  What the Records page shows (web routes/provider.records.tsx): the view
//  (To complete, Records, Follow-ups), its filters, the header's numbers and
//  the three lists, each from the server. The page opens on To complete when
//  a finished visit still waits on the reader, else on the view used last on
//  this device; the records open on the drafts to sign when the reader signs
//  and has some. Both are decided once per visit to the page.
//

import SwiftUI

enum RecordsListView: String, Hashable {
    case toComplete = "to-complete"
    case records
    case followUps = "follow-ups"
}

/// Records: drafts waiting for a signature, signed ones, or all of them.
enum RecordsSignChoice: Hashable { case draft, signed, all }

/// Follow-ups: late, due this week, or later.
enum RecordsDue: Hashable { case overdue, week, later }

/// What the reader's role lets them do here (web `hasProviderPermission` calls on the page).
struct RecordsAccess {
    var viewRecords = false
    var createRecords = false
    var editRecords = false
    var signRecords = false
    var assignSelf = false
    var assignAnyone = false
    var viewFollowUps = false
    var completeFollowUps = false
    var remindFollowUps = false
    var followUpsSelf = false
    var followUpsAnyone = false
    var viewClients = false
    var viewAppointments = false
    var isManager = false

    init() {}

    @MainActor
    init(_ w: Workspace) {
        viewRecords = w.can(.recordsView)
        createRecords = w.can(.recordsCreate)
        editRecords = w.can(.recordsEdit)
        signRecords = w.can(.recordsApprove)
        assignSelf = w.can(.recordsAssignSelf)
        assignAnyone = w.can(.recordsAssignAnyone)
        viewFollowUps = w.can(.followupsView)
        completeFollowUps = w.can(.followupsComplete)
        remindFollowUps = w.can(.followupsEdit)
        followUpsSelf = w.can(.followupsAssignSelf)
        followUpsAnyone = w.can(.followupsAssignAnyone)
        viewClients = w.can(.clientsView)
        viewAppointments = w.can(.appointmentsView)
        isManager = w.isOwnerOrAdmin
    }

    var records: Bool { viewRecords && (assignSelf || assignAnyone) }
    var followUps: Bool { viewFollowUps && (followUpsSelf || followUpsAnyone) }
    /// The page itself (and its "To complete" view): records or follow-ups.
    var seesPage: Bool { records || followUps }
    var writeRecords: Bool { createRecords && (assignSelf || assignAnyone) }
    /// A signed record reaches the family: only someone who can sign changes it.
    func canEdit(_ record: RecordsRecord) -> Bool { editRecords && (record.isDraft || signRecords) }
}

/// How to reach a family: WhatsApp needs a phone, PawMiaw a linked household. Unknown lets the server decide.
struct RecordsReach {
    let phone: String?
    let onPawMiaw: Bool
}

@MainActor
final class RecordsListModel: ObservableObject {
    private static let viewKey = "pawmiaw.provider.records.view"
    /// To complete shows this many of each part, then "Show more".
    static let toCompletePage = 50

    @Published private(set) var access = RecordsAccess()
    @Published private(set) var members: [RecordsMember] = []
    @Published private(set) var view: RecordsListView = .records
    @Published private(set) var opened = false

    // Filters
    @Published private(set) var signChoice: RecordsSignChoice = .all
    @Published private(set) var search = ""
    @Published private(set) var type: RecordsKind?
    /// A staff member's id, or "unassigned".
    @Published private(set) var who: String?
    /// nil = to do (open or reminded); "contacted", "done" or "all".
    @Published private(set) var followUpState: String?
    @Published private(set) var due: RecordsDue?
    @Published private(set) var from: String?
    @Published private(set) var to: String?
    @Published private(set) var pet: RecordsPetFilter?

    // The header's numbers
    @Published private(set) var drafts: Int?
    @Published private(set) var signedTotal: Int?
    @Published private(set) var overdue: Int?
    @Published private(set) var week: Int?

    // To complete
    @Published private(set) var paperwork: [RecordsFollowUp] = []
    @Published private(set) var paperworkTotal = 0
    @Published private(set) var toSign: [RecordsRecord] = []
    @Published private(set) var toSignTotal = 0
    @Published private(set) var unfinished: [RecordsRecord] = []
    @Published private(set) var unfinishedTotal = 0
    @Published private(set) var toCompleteLoaded = false
    @Published private(set) var loadingMore = false

    @Published private(set) var clientsTotal: Int?
    @Published private(set) var reach: [String: RecordsReach] = [:]

    let recordsPager = Pager<RecordsRecord> { _, _ in Page(items: [], total: 0) }
    let followUpsPager = Pager<RecordsFollowUp> { _, _ in Page(items: [], total: 0) }

    private var clinicId: String?
    private var location: String?

    init() {
        recordsPager.fetch = { [weak self] offset, limit in
            guard let self else { return Page(items: [], total: 0) }
            return try await self.fetchRecords(offset: offset, limit: limit)
        }
        followUpsPager.fetch = { [weak self] offset, limit in
            guard let self else { return Page(items: [], total: 0) }
            return try await self.fetchFollowUps(offset: offset, limit: limit)
        }
    }

    // MARK: Derived

    var currentMemberId: String? { members.first { $0.isCurrentMember == true }?.id }
    var toCompleteCount: Int { paperworkTotal + toSignTotal + unfinishedTotal }
    var hasMoreToComplete: Bool { paperwork.count < paperworkTotal || toSign.count < toSignTotal || unfinished.count < unfinishedTotal }
    var seesAnyone: Bool { view == .records ? access.assignAnyone : access.followUpsAnyone }

    var filtered: Bool {
        !search.isEmpty || type != nil || who != nil || pet != nil || from != nil || to != nil
            || (view == .records ? signChoice != .all : (followUpState != nil || due != nil))
    }

    /// Only "To sign", nothing else narrowed: its empty list says everything is signed.
    var onlyDrafts: Bool { signChoice == .draft && pet == nil && from == nil && to == nil && type == nil && who == nil }

    /// Whose lists: anyone's (a filter) for those who may see all, else only the reader's own.
    private func scope(_ seesAnyone: Bool) -> (member: String?, unassigned: Bool) {
        if !seesAnyone { return (currentMemberId, false) }
        if who == "unassigned" { return (nil, true) }
        return (who, false)
    }

    private struct Days { let yesterday, today, weekEnd, afterWeek: String }

    private var days: Days {
        let calendar = DateText.calendar
        let now = Date()
        func key(_ offset: Int) -> String { DateText.dayKey(calendar.date(byAdding: .day, value: offset, to: now) ?? now) }
        return Days(yesterday: key(-1), today: key(0), weekEnd: key(6), afterWeek: key(7))
    }

    // MARK: Loading

    func load(_ workspace: Workspace) async {
        access = RecordsAccess(workspace)
        location = workspace.listLocationFilter
        guard access.seesPage else { return }
        let clinic = workspace.current?.clinicId
        if clinic != clinicId {
            clinicId = clinic
            opened = false
            resetFilters()
            if let clinic { members = (try? await RecordsAPI.members(clinicId: clinic)) ?? [] } else { members = [] }
        }
        await loadCounts()
        if !opened {
            let stored = UserDefaults.standard.string(forKey: Self.viewKey).flatMap(RecordsListView.init(rawValue:))
            view = toCompleteCount > 0 ? .toComplete : (stored ?? .records)
            signChoice = access.signRecords && access.records && (drafts ?? 0) > 0 ? .draft : .all
            opened = true
        }
        normalizeView()
        await reloadList()
    }

    private func normalizeView() {
        if view == .toComplete { return }
        if !access.followUps { view = .records } else if !access.records { view = .followUps }
    }

    private func resetFilters() {
        signChoice = .all; search = ""; type = nil; who = nil; followUpState = nil; due = nil; from = nil; to = nil; pet = nil
    }

    /// The header's numbers, To complete's three parts and the first clients (to know there are any).
    func loadCounts() async {
        let a = access
        let records = scope(a.assignAnyone)
        let followUps = scope(a.followUpsAnyone)
        let clients = scope(a.assignAnyone || a.followUpsAnyone)
        let mine = currentMemberId
        let d = days
        let page = Self.toCompletePage

        let draftsPage = recordsStart(a.records) { try await RecordsAPI.records(limit: 1, offset: 0, status: "draft", readyToSign: true, member: records.member, unassigned: records.unassigned) }
        let signedPage = recordsStart(a.records) { try await RecordsAPI.records(limit: 1, offset: 0, status: "active", member: records.member, unassigned: records.unassigned) }
        let overduePage = recordsStart(a.followUps) { try await RecordsAPI.followUps(limit: 1, offset: 0, kind: "care", member: followUps.member, unassigned: followUps.unassigned, dueTo: d.yesterday) }
        let weekPage = recordsStart(a.followUps) { try await RecordsAPI.followUps(limit: 1, offset: 0, kind: "care", member: followUps.member, unassigned: followUps.unassigned, dueFrom: d.today, dueTo: d.weekEnd) }
        let paperworkPage = recordsStart(a.followUps) { try await RecordsAPI.followUps(limit: page, offset: 0, kind: "paperwork", member: a.followUpsAnyone ? nil : mine) }
        let toSignPage = recordsStart(a.records && a.signRecords) { try await RecordsAPI.records(limit: page, offset: 0, status: "draft", readyToSign: true, member: a.assignAnyone ? nil : mine) }
        let unfinishedPage = recordsStart(a.records) { try await RecordsAPI.records(limit: page, offset: 0, status: "draft", unfinished: true, member: a.assignAnyone ? nil : mine) }
        let clientsPage = recordsStart { try await RecordsAPI.clients(limit: 50, member: clients.member, unassigned: clients.unassigned) }

        drafts = await draftsPage.value?.total
        signedTotal = await signedPage.value?.total
        overdue = await overduePage.value?.total
        week = await weekPage.value?.total
        let paperworkResult = await paperworkPage.value
        paperwork = paperworkResult?.items ?? []
        paperworkTotal = paperworkResult?.total ?? paperwork.count
        let toSignResult = await toSignPage.value
        toSign = toSignResult?.items ?? []
        toSignTotal = toSignResult?.total ?? toSign.count
        let unfinishedResult = await unfinishedPage.value
        unfinished = unfinishedResult?.items ?? []
        unfinishedTotal = unfinishedResult?.total ?? unfinished.count
        toCompleteLoaded = true
        if let clientsResult = await clientsPage.value {
            clientsTotal = clientsResult.total ?? clientsResult.items.count
            reach = Dictionary(clientsResult.items.map { ($0.id, RecordsReach(phone: $0.ownerPhone?.nonEmpty, onPawMiaw: $0.householdId?.nonEmpty != nil)) }, uniquingKeysWith: { first, _ in first })
        }
    }

    func reloadList() async {
        switch view {
        case .records: await recordsPager.reload()
        case .followUps: await followUpsPager.reload()
        case .toComplete: break
        }
    }

    /// The next 50 of each part of To complete that has more.
    func loadMoreToComplete() async {
        guard !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        let a = access
        let mine = currentMemberId
        let page = Self.toCompletePage
        let paperworkOffset = paperwork.count, toSignOffset = toSign.count, unfinishedOffset = unfinished.count
        let morePaperwork = a.followUps && paperworkOffset < paperworkTotal
        let moreToSign = a.records && a.signRecords && toSignOffset < toSignTotal
        let moreUnfinished = a.records && unfinishedOffset < unfinishedTotal

        let paperworkPage = recordsStart(morePaperwork) { try await RecordsAPI.followUps(limit: page, offset: paperworkOffset, kind: "paperwork", member: a.followUpsAnyone ? nil : mine) }
        let toSignPage = recordsStart(moreToSign) { try await RecordsAPI.records(limit: page, offset: toSignOffset, status: "draft", readyToSign: true, member: a.assignAnyone ? nil : mine) }
        let unfinishedPage = recordsStart(moreUnfinished) { try await RecordsAPI.records(limit: page, offset: unfinishedOffset, status: "draft", unfinished: true, member: a.assignAnyone ? nil : mine) }

        if let more = await paperworkPage.value {
            let known = Set(paperwork.map(\.id))
            paperwork += more.items.filter { !known.contains($0.id) }
            if let total = more.total { paperworkTotal = total }
        }
        if let more = await toSignPage.value {
            let known = Set(toSign.map(\.id))
            toSign += more.items.filter { !known.contains($0.id) }
            if let total = more.total { toSignTotal = total }
        }
        if let more = await unfinishedPage.value {
            let known = Set(unfinished.map(\.id))
            unfinished += more.items.filter { !known.contains($0.id) }
            if let total = more.total { unfinishedTotal = total }
        }
    }

    private func fetchRecords(offset: Int, limit: Int) async throws -> Page<RecordsRecord> {
        let status: String? = signChoice == .draft ? "draft" : signChoice == .signed ? "active" : nil
        let scope = scope(access.assignAnyone)
        return try await RecordsAPI.records(
            limit: limit, offset: offset,
            status: status, readyToSign: status == "draft",
            search: search, recordType: type?.rawValue,
            member: scope.member, unassigned: scope.unassigned,
            location: location, pet: pet?.id, from: from, to: to
        ).page
    }

    private func fetchFollowUps(offset: Int, limit: Int) async throws -> Page<RecordsFollowUp> {
        let scope = scope(access.followUpsAnyone)
        let d = days
        let dueFrom: String? = due == .week ? d.today : due == .later ? d.afterWeek : due != nil ? nil : from
        let dueTo: String? = due == .overdue ? d.yesterday : due == .week ? d.weekEnd : due != nil ? nil : to
        return try await RecordsAPI.followUps(
            limit: limit, offset: offset,
            status: followUpState ?? "to_do", kind: "care",
            search: search, recordType: type?.rawValue,
            member: scope.member, unassigned: scope.unassigned,
            pet: pet?.id, dueFrom: dueFrom, dueTo: dueTo
        ).page
    }

    // MARK: Changing what is shown

    private func refreshList() { Task { await reloadList() } }

    func switchView(_ next: RecordsListView) {
        // To complete is chosen by what waits, never remembered.
        if next != .toComplete { UserDefaults.standard.set(next.rawValue, forKey: Self.viewKey) }
        // The days mean a record's date in one view and a due date in the other: they don't cross over.
        if next != view { from = nil; to = nil }
        view = next
        refreshList()
    }

    func setSign(_ choice: RecordsSignChoice) { signChoice = choice; refreshList() }
    func setType(_ kind: RecordsKind?) { type = kind; refreshList() }
    func setFollowUpState(_ state: String?) { followUpState = state; refreshList() }
    func setPet(_ filter: RecordsPetFilter?) { pet = filter; refreshList() }

    func setDue(_ value: RecordsDue?) {
        due = value
        from = nil; to = nil
        refreshList()
    }

    func setRange(from start: String?, to end: String?) {
        from = start; to = end
        if view == .followUps { due = nil }
        refreshList()
    }

    /// Whose lists changes the header's numbers too.
    func setWho(_ value: String?) {
        who = value
        Task {
            await loadCounts()
            await reloadList()
        }
    }

    func applySearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != search else { return }
        search = trimmed
        refreshList()
    }

    /// The header's Signed card: the records, signed (again: all).
    func showSigned() {
        UserDefaults.standard.set(RecordsListView.records.rawValue, forKey: Self.viewKey)
        let next: RecordsSignChoice = view == .records && signChoice == .signed ? .all : .signed
        if view != .records { from = nil; to = nil }
        view = .records
        signChoice = next
        refreshList()
    }

    /// The header's follow-up cards: late, or due this week (again: off).
    func showFollowUps(due value: RecordsDue) {
        UserDefaults.standard.set(RecordsListView.followUps.rawValue, forKey: Self.viewKey)
        let next: RecordsDue? = view == .followUps && due == value ? nil : value
        view = .followUps
        followUpState = nil; from = nil; to = nil
        due = next
        refreshList()
    }

    func clearFilters() {
        let whoChanged = who != nil
        search = ""; type = nil; who = nil; followUpState = nil; due = nil; from = nil; to = nil; pet = nil
        // "All" is said out loud, so the records don't fall back to the drafts.
        if view == .records { signChoice = .all }
        if whoChanged {
            Task { await loadCounts(); await reloadList() }
        } else {
            refreshList()
        }
    }
}
