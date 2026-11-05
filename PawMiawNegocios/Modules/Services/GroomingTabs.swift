//
//  GroomingTabs.swift
//  PawMiawNegocios
//
//  Estética's other tabs (web: grooming-pets.tsx, grooming-pet-sheet.tsx,
//  grooming-due.tsx, grooming-settings.tsx, care/care-card.tsx): every pet
//  groomed here with its care card and history, who is due back (with the
//  reminder), and how the business grooms.
//

import SwiftUI

// MARK: - Pets

/// Every pet groomed here (web `GroomingPets`): one card with the search and the
/// sort, the filter chips, the pets (20 at a time) and the server's count.
struct SvcGroomPetsTab: View {
    let canBook: Bool
    let canEditCard: Bool
    let canRemind: Bool
    let push: (ProviderRoute) -> Void

    @EnvironmentObject private var workspace: Workspace
    @State private var query = ""
    @State private var due = "all"
    @State private var sort = "recent"
    @State private var counts: SvcGroomPetCounts?
    @State private var open: SvcGroomPetRow?
    @StateObject private var pager = Pager<SvcGroomPetRow> { _, _ in Page(items: [], total: 0) }

    private var reloadKey: String { "\(query)|\(due)|\(sort)|\(workspace.scopeVersion)" }
    private var filtered: Bool { query.nonEmpty != nil || due != "all" }

    private static let sorts: [(value: String, title: String)] = [("recent", "Last groom"), ("name", "Name"), ("due", "Due first")]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                SearchField(prompt: L("Pet, owner or phone"), text: $query, height: 40)
                Menu {
                    ForEach(Self.sorts, id: \.value) { option in
                        Button { sort = option.value } label: {
                            if sort == option.value { GlyphLabel(L(option.title), icon: "check") } else { Text(L(option.title)) }
                        }
                    }
                } label: {
                    PillField(text: L(Self.sorts.first { $0.value == sort }?.title ?? "Last groom"), height: 40)
                }
                .accessibilityLabel(L("Sort"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            RowDivider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: L("All"), count: counts?.pets, isSelected: due == "all", tone: Theme.blue) { due = "all" }
                    FilterChip(title: L("Overdue"), count: counts?.overdue, isSelected: due == "overdue", tone: Theme.pink, icon: "bell-ring") { due = due == "overdue" ? "all" : "overdue" }
                    FilterChip(title: L("Due soon"), count: counts?.soon, isSelected: due == "soon", tone: Theme.mango, icon: "clock-3") { due = due == "soon" ? "all" : "soon" }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .padding(.vertical, 10)
            RowDivider()
            rows
        }
        .listCard()
        .task(id: reloadKey) {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pawMiawDataChanged)) { _ in Task { await reload() } }
        .sheet(item: $open) { row in
            // The sheet shows the row as it is now (a saved care card changes its cadence and its due date).
            SvcGroomPetSheet(row: pager.items.first { $0.id == row.id } ?? row, canBook: canBook, canEditCard: canEditCard, canRemind: canRemind, push: push)
        }
    }

    @ViewBuilder private var rows: some View {
        if !pager.loadedOnce && pager.isLoading {
            LoadingState()
        } else if pager.error != nil, pager.items.isEmpty {
            SvcLoadError(message: L("The groomed pets couldn’t be loaded.")) { await pager.reload() }
                .padding(16)
        } else if pager.items.isEmpty {
            EmptyState(systemImage: query.nonEmpty != nil ? "search" : "paw-print",
                       title: query.nonEmpty.map { LF("Nothing matches “%@”", $0) } ?? (due != "all" ? L("No pets match this filter") : L("No groomed pets yet")),
                       message: filtered ? L("Try the owner’s name or a phone, or show every pet.") : L("A pet appears here after its first groom, or once its care card says how it is groomed."),
                       actionTitle: filtered ? L("Show every pet") : nil, action: {
                           query = ""
                           due = "all"
                       }, accent: Theme.pink)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(pager.items) { row in
                    if row.id != pager.items.first?.id { RowDivider() }
                    // The row opens the pet's grooming; its photo and name open the chart; "Book" books.
                    SvcGroomPetRowView(row: row, push: push, onBook: canBook ? { push(SvcBook.groom(clientId: row.client.id, petId: row.pet.id, lastService: row.lastServiceLabel)) } : nil)
                        .contentShape(Rectangle())
                        .onTapGesture { open = row }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(named: Text(LF("Open %@’s grooming", row.pet.name))) { open = row }
                        .onAppear { pager.loadMoreIfNeeded(row) }
                }
                PagerFooter(pager: pager)
            }
            if let total = pager.total, total > 0 {
                RowDivider()
                Text(pager.isLoading ? L("Updating…") : LP(total, "1 pet", "%d pets"))
                    .font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
    }

    private func reload() async {
        let q = query.nonEmpty, filter = due == "all" ? nil : due, order = sort
        pager.fetch = { offset, limit in
            let page: SvcGroomPetsPage = try await API.get("/provider-grooming/pets", query: ["q": q, "due": filter, "sort": order, "page": "\(offset / limit + 1)", "size": "\(limit)"])
            counts = page.counts
            return Page(items: page.items, total: page.total)
        }
        await pager.reload()
    }
}

/// One pet of the list (web: the table's row): the pet (photo and name open the
/// chart), its owner, the last groom, how often it comes and when it's due, and Book.
private struct SvcGroomPetRowView: View {
    let row: SvcGroomPetRow
    let push: (ProviderRoute) -> Void
    /// "Book" on the row; nil when the member can't book.
    var onBook: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Button { push(.patientChart(petId: row.pet.id)) } label: {
                    PetAvatar(name: row.pet.name, species: row.pet.species, photoURL: row.pet.photoUrl, size: 40)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Button { push(.patientChart(petId: row.pet.id)) } label: {
                        Text(row.pet.name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    Text([row.pet.species.map { ClientsText.species($0) }, row.pet.breed].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    Text(row.client.name).font(Theme.text(14)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    SvcHandlingChips(tags: row.handlingTags ?? []).padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let onBook {
                    PMButton(L("Book"), systemImage: "calendar-plus", size: .compact, action: onBook)
                }
                Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft).frame(width: 32, height: 32)
            }
            HStack(alignment: .top, spacing: 16) {
                fact(L("Last groom")) {
                    if let last = row.lastGroomAt {
                        Text(SvcTime.day(last)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        if let line = [row.lastServiceLabel, row.usualStyle].compactMap({ $0?.nonEmpty }).joined(separator: " · ").nonEmpty {
                            Text(line).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                        }
                    } else {
                        Text(L("Not yet")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        if let usual = row.usualStyle?.nonEmpty { Text(usual).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                    }
                }
                fact(L("Every")) {
                    if let weeks = row.rebookEveryWeeks {
                        Text(SvcTime.cadence(weeks)).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    } else if let weeks = row.effectiveRebookWeeks {
                        // No cadence of its own: the business's, said as such.
                        Text(SvcTime.cadence(weeks)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                            .accessibilityHint(L("The business’s default"))
                    } else {
                        Text("—").font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    }
                }
                fact(L("Due")) { SvcDueCell(nextBookedAt: row.nextBookedAt, nextGroomDueAt: row.nextGroomDueAt) }
            }
            .padding(.leading, 52)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func fact<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(label, size: 10.6)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// When the pet is due (web `DueCell`): already booked (never late), or the Due
/// list's words with its colour's dot, and the day under them.
private struct SvcDueCell: View {
    let nextBookedAt: String?
    let nextGroomDueAt: String?

    var body: some View {
        if let booked = nextBookedAt {
            HStack(spacing: 6) {
                Glyph("calendar-check", size: 14)
                Text(LF("Booked %@", SvcTime.day(booked)))
            }
            .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
        } else if let due = nextGroomDueAt, let days = SvcTime.daysUntil(due) {
            let state: ProviderState = days < 0 ? .problem : (days <= 6 ? .waiting : .upcoming)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(state.color).frame(width: 8, height: 8)
                    Text(SvcTime.dueWords(days))
                }
                .font(Theme.text(14, weight: .bold)).foregroundStyle(days < 0 ? Theme.destructive : Theme.inkStrong)
                Text(SvcTime.day(due)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        } else {
            Text("—").font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        }
    }
}

// MARK: - One pet's grooming

/// One pet's grooming (web `GroomingPetSheet`): how many grooms, how often it
/// comes back and when it's due, its care card, and every groom with its report.
private struct SvcGroomPetSheet: View {
    let row: SvcGroomPetRow
    let canBook: Bool
    let canEditCard: Bool
    let canRemind: Bool
    let push: (ProviderRoute) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var history: [SvcGroomHistoryItem]?
    @State private var historyError: String?

    var body: some View {
        ProviderModal(title: row.pet.name,
                      subtitle: [row.client.name, row.pet.species.map { ClientsText.species($0) }, row.pet.breed].compactMap { $0?.nonEmpty }.joined(separator: " · "),
                      systemImage: "paw-print", accent: .pink, primaryTitle: canBook ? L("Book a groom") : nil, cancelTitle: L("Close"),
                      // Web footer: Book a groom, WhatsApp, Close.
                      secondaryActions: whatsApp.map { link in [ModalAction(L("WhatsApp"), icon: "message-circle") { UIApplication.shared.open(link) }] } ?? [],
                      // Web: the pet's own photo in the header's pebble.
                      primaryIcon: "calendar-plus", pebbleImageURL: row.pet.photoUrl, onPrimary: canBook ? { book() } : nil) {
            FlowLayout(spacing: 16) {
                fact("scissors", L("Grooms here")) { Text("\(row.groomCount ?? 0)") }
                fact("repeat-2", L("Comes back")) {
                    if let weeks = row.rebookEveryWeeks {
                        Text(SvcTime.cadence(weeks))
                    } else if let weeks = row.effectiveRebookWeeks {
                        Text(SvcTime.cadence(weeks)) + Text(" · " + L("the business’s default")).font(Theme.text(12)).fontWeight(.regular).foregroundColor(Theme.inkSoft)
                    } else {
                        Text(L("No cadence"))
                    }
                }
                fact("calendar-plus", L("Due")) { SvcDueCell(nextBookedAt: row.nextBookedAt, nextGroomDueAt: row.nextGroomDueAt) }
            }
            // Web: a blue link after the facts.
            PMButton(L("Open chart"), variant: .link, size: .small) {
                dismiss()
                push(.patientChart(petId: row.pet.id))
            }

            SvcCareCard(petId: row.pet.id, petName: row.pet.name, canEdit: canEditCard, photoURL: row.pet.photoUrl, species: row.pet.species)

            ModalSection(title: L("Grooming history"), systemImage: "history", tint: Theme.aqua) {
                if let history {
                    if history.isEmpty {
                        EmptyState(systemImage: "scissors", title: L("No grooms here yet"), message: L("Each groom is kept here with its report and its before and after photos."), accent: Theme.pink)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(Array(history.enumerated()), id: \.element.id) { index, item in
                                SvcGroomHistoryRow(item: item, startsOpen: index == 0)
                            }
                        }
                    }
                } else if historyError != nil {
                    SvcLoadError(message: L("The history couldn’t be loaded.")) { await loadHistory() }
                } else {
                    LoadingState()
                }
            }
        }
        .task { await loadHistory() }
    }

    private var whatsApp: URL? { canRemind ? ContactLinks.whatsApp(row.client.phone) : nil }

    /// A fact of the pet's grooming (web `Fact`): a pink disc, the micro-label, the value.
    private func fact<Value: View>(_ icon: String, _ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 8) {
            Glyph(icon, size: 16)
                .foregroundStyle(Theme.inkStrong)
                .frame(width: 32, height: 32)
                .background(Theme.wash(Theme.pink, 20), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(label, size: 10.6)
                value().font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
            }
        }
    }

    /// The Agenda's booking with this pet, on its last service.
    private func book() {
        dismiss()
        push(SvcBook.groom(clientId: row.client.id, petId: row.pet.id, lastService: row.lastServiceLabel))
    }

    private func loadHistory() async {
        do {
            let page: SvcGroomHistory = try await API.get("/provider-client-pets/\(row.pet.id)/grooms", query: ["limit": "20"])
            history = page.items
            historyError = nil
        } catch is CancellationError {
        } catch {
            historyError = errorText(error)
        }
    }
}

/// One groom: when, what, who, what was asked — and the report the family got, photos included.
private struct SvcGroomHistoryRow: View {
    let item: SvcGroomHistoryItem
    let startsOpen: Bool
    @State private var open = false

    private var statusLabel: String? {
        switch item.status {
        case "scheduled": L("Booked")
        case "checked_in": L("Here now")
        case "in_progress": L("In progress")
        case "cancelled": L("Cancelled")
        case "no_show": L("No-show")
        default: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowLayout(spacing: 8) {
                Text(SvcTime.day(item.at, withYear: true)).font(.brandHeading(18)).foregroundStyle(Theme.inkStrong)
                if let statusLabel { Chip(text: statusLabel, tone: .muted) }
            }
            HStack(spacing: 8) {
                if let service = item.serviceLabel?.nonEmpty { Text(service).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong) }
                if let groomer = item.groomerName?.nonEmpty {
                    HStack(spacing: 4) {
                        Glyph("user-round", size: 14)
                        Text(groomer)
                    }
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.top, 2)
            if let asked = item.requestSummary?.nonEmpty {
                SvcAskedBox(text: asked, lineLimit: nil).padding(.top, 8)
            }
            if let report = item.report, SvcReportText.hasContent(report) {
                VStack(alignment: .leading, spacing: 8) {
                    Button { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } } label: {
                        HStack(spacing: 6) {
                            Glyph("chevron-right", size: 14).rotationEffect(.degrees(open ? 90 : 0))
                            Text(L("Report"))
                            Spacer(minLength: 0)
                        }
                        .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if open { SvcReportView(report: report) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                .padding(.top, 8)
            } else if item.status == "completed" {
                Text(L("No report was written.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).padding(.top, 8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        .onAppear { if startsOpen { open = true } }
    }
}

// MARK: - The care card

/// What a groomer or walker keeps about the pet (web `CareCard`): how to handle
/// them first, then the cut, the tools and products, the notes and how often they
/// come back, and (on a groom) the last groom's report.
struct SvcCareCard: View {
    let petId: String
    let petName: String
    let canEdit: Bool
    /// A groomer's card (the cut, when it's due back); a walker or a sitter keeps the route and the door.
    var grooming: Bool = true
    /// With either, the head shows the pet's face; without both, a paw.
    var photoURL: String? = nil
    var species: String? = nil

    @State private var profile: SvcCareProfile?
    @State private var failed: String?
    @State private var editing = false
    @State private var lastOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if photoURL != nil || species != nil {
                    PetAvatar(name: petName, species: species, photoURL: photoURL, size: 32)
                } else {
                    Glyph("paw-print", size: 20).foregroundStyle(Theme.blue)
                }
                Text(LF("Care card · %@", petName)).font(.brandHeading(20)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                Spacer(minLength: 8)
                if canEdit, let profile, !isEmpty(profile) {
                    PMButton(L("Edit"), systemImage: "pencil", variant: .outline, size: .compact) { editing = true }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            RowDivider()
            VStack(alignment: .leading, spacing: 12) {
                if let profile {
                    content(profile)
                } else if failed != nil {
                    SvcLoadError(message: L("The care card couldn’t be loaded.")) { await load() }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listCard()
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .pawMiawDataChanged)) { _ in Task { await load() } }
        .sheet(isPresented: $editing) {
            if let profile {
                SvcCareCardForm(petId: petId, petName: petName, profile: profile, grooming: grooming) { saved in self.profile = saved }
            }
        }
    }

    @ViewBuilder private func content(_ profile: SvcCareProfile) -> some View {
        let tags = profile.handlingTags ?? []
        let warnings = tags.filter { SvcHandling.warn.contains($0) }
        let others = tags.filter { !SvcHandling.warn.contains($0) }
        if !warnings.isEmpty {
            FlowLayout(spacing: 6) {
                Glyph("shield-alert", size: 16)
                ForEach(warnings, id: \.self) { tag in Text(SvcReportText.option(tag)).font(Theme.text(14, weight: .bold)) }
            }
            .foregroundStyle(Theme.destructive)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wash(Theme.destructive, 9), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
        }
        if !others.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(others, id: \.self) { tag in
                    Text(SvcReportText.option(tag)).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        .padding(.horizontal, 10).padding(.vertical, 2)
                        .background(Theme.surfaceMuted, in: Capsule())
                }
            }
        }
        if isEmpty(profile) {
            // One line and its button: it reads the same at any width.
            FlowLayout(spacing: 12) {
                Glyph(grooming ? "scissors" : "paw-print", size: 16)
                    .foregroundStyle(Theme.inkStrong)
                    .frame(width: 36, height: 36)
                    .background(Theme.wash(Theme.aqua, 30), in: Circle())
                Text(grooming
                     ? LF("Nothing written yet. Note the cut, the tools and how %@ likes to be handled — the next person will thank you.", petName)
                     : LF("Nothing written yet. Note the route, the keys and how %@ likes to be handled — the next person will thank you.", petName))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                if canEdit {
                    PMButton(L("Write it"), systemImage: "pencil", variant: .outline, size: .compact) { editing = true }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.blue, 30, with: Theme.borderSoft), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        } else {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                row(L("Cut"), profile.groomStyle)
                row(L("Tools"), profile.groomTools)
                row(L("Products"), profile.groomProducts)
                row(L("Notes"), profile.careNotes)
            }
        }
        if grooming { dueLine(profile) }
        if let last = lastReport(profile), let report = last.report {
            VStack(alignment: .leading, spacing: 8) {
                Button { withAnimation(.easeOut(duration: 0.2)) { lastOpen.toggle() } } label: {
                    HStack(spacing: 6) {
                        Glyph("scissors", size: 14).foregroundStyle(Theme.inkSoft)
                        Text(LF("Last time: %@, %@", last.serviceLabel ?? "—", SvcTime.day(last.at)))
                            .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        Spacer(minLength: 0)
                        Glyph("chevron-down", size: 14).foregroundStyle(Theme.inkSoft).rotationEffect(.degrees(lastOpen ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if lastOpen { SvcReportView(report: report, compact: true) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        }
    }

    @ViewBuilder private func row(_ label: String, _ value: String?) -> some View {
        if let value = value?.nonEmpty {
            GridRow {
                Text(label).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft).frame(minWidth: 88, alignment: .leading)
                Text(value).font(Theme.text(14)).foregroundStyle(Theme.inkStrong).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func isEmpty(_ profile: SvcCareProfile) -> Bool {
        (profile.handlingTags ?? []).isEmpty && profile.groomStyle?.nonEmpty == nil && profile.groomTools?.nonEmpty == nil
            && profile.groomProducts?.nonEmpty == nil && profile.careNotes?.nonEmpty == nil
    }

    /// On a groom, "last time" is the last groom — not the walk or the class in between.
    private func lastReport(_ profile: SvcCareProfile) -> SvcCareLastReport? {
        let reports = (profile.lastReports ?? []).filter { $0.report != nil }
        return grooming ? reports.first { $0.report?.kind == "groom" } : reports.first
    }

    private func dueLine(_ profile: SvcCareProfile) -> some View {
        let weeks = profile.rebookEveryWeeks ?? profile.effectiveRebookWeeks ?? 6
        let due = DateText.parse(profile.nextGroomDueAt)
        let overdue = profile.nextBookedAt == nil && (due.map { $0 < Date() } ?? false)
        let text: String = {
            if let booked = profile.nextBookedAt { return LF("Next groom booked for %@", SvcTime.day(booked)) }
            if let dueAt = profile.nextGroomDueAt { return LF("Due back around %@ (every %d weeks)", SvcTime.day(dueAt), weeks) }
            if let own = profile.rebookEveryWeeks { return LF("Comes back every %d weeks", own) }
            return L("No grooming here yet")
        }()
        return HStack(spacing: 6) {
            Glyph("calendar-clock", size: 14)
            Text(text)
        }
        .font(Theme.text(12, weight: .bold))
        .foregroundStyle(overdue ? Theme.destructive : Theme.inkSoft)
    }

    private func load() async {
        do {
            profile = try await API.get("/provider-client-pets/\(petId)/care")
            failed = nil
        } catch is CancellationError {
        } catch {
            failed = errorText(error)
        }
    }
}

/// The care card's form (web `CareProfileSheet`): how to handle the pet, the cut,
/// the tools and products and how often it comes (a groom), the notes.
private struct SvcCareCardForm: View {
    let petId: String
    let petName: String
    let profile: SvcCareProfile
    let grooming: Bool
    let onSaved: (SvcCareProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var style = ""
    @State private var tools = ""
    @State private var products = ""
    @State private var notes = ""
    @State private var tags: [String] = []
    @State private var weeks = ""
    @State private var working = false
    @StateObject private var form = FormState()

    private var dirty: Bool {
        style != (profile.groomStyle ?? "") || tools != (profile.groomTools ?? "") || products != (profile.groomProducts ?? "")
            || notes != (profile.careNotes ?? "") || Set(tags) != Set(profile.handlingTags ?? []) || weeks != (profile.rebookEveryWeeks.map(String.init) ?? "")
    }

    var body: some View {
        ProviderModal(title: LF("%@'s care card", petName), subtitle: LF("Kept for everyone in the workspace who works with %@.", petName), systemImage: "paw-print", accent: .aqua, isDirty: dirty, form: form, primaryTitle: L("Save"), isWorking: working, cancelTitle: L("Back"), onPrimary: save) {
            ModalSection(title: L("Handling")) {
                FlowLayout(spacing: 6) {
                    ForEach(SvcHandling.all, id: \.self) { tag in
                        SvcChoiceChip(title: SvcReportText.option(tag), isSelected: tags.contains(tag), danger: SvcHandling.warn.contains(tag)) {
                            if tags.contains(tag) { tags.removeAll { $0 == tag } } else { tags.append(tag) }
                        }
                    }
                }
            }
            if grooming {
                ModalSection(title: L("Grooming")) {
                    TextField(L("Cut: puppy cut, round ears…"), text: $style).fieldChrome()
                    TextField(L("Tools: blade 7F, comb 1/2\"…"), text: $tools).fieldChrome()
                    TextField(L("Products: oatmeal shampoo…"), text: $products).fieldChrome()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(L("Comes back every")).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                            TextField("6", text: $weeks)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .fieldChrome(invalid: form.error("weeks") != nil)
                                .frame(width: 80)
                                .onChange(of: weeks) { _, _ in form.clear("weeks") }
                            Text(L("weeks")).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                        }
                        if let error = form.error("weeks") {
                            Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral)
                        }
                    }
                    .id("weeks")
                }
            }
            ModalSection(title: LF("Notes for whoever takes %@", petName)) {
                TextField(L("Keys, route, feeding, where the leash is…"), text: $notes, axis: .vertical)
                    .lineLimit(4...10)
                    .fieldChrome(multiline: true)
            }
        }
        .onAppear {
            style = profile.groomStyle ?? ""
            tools = profile.groomTools ?? ""
            products = profile.groomProducts ?? ""
            notes = profile.careNotes ?? ""
            tags = profile.handlingTags ?? []
            weeks = profile.rebookEveryWeeks.map(String.init) ?? ""
        }
    }

    private func save() {
        let parsed = Int(weeks.trimmingCharacters(in: .whitespaces))
        guard form.check([("weeks", weeks.nonEmpty != nil && !(1...52).contains(parsed ?? 0) ? L("Weeks go from 1 to 52.") : nil)]) else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let saved: SvcCareProfile = try await API.put("/provider-client-pets/\(petId)/care", body: [
                    "groomStyle": style.nonEmpty, "groomTools": tools.nonEmpty, "groomProducts": products.nonEmpty,
                    "careNotes": notes.nonEmpty, "handlingTags": SvcHandling.all.filter(tags.contains), "rebookEveryWeeks": weeks.nonEmpty == nil ? nil : parsed,
                ])
                onSaved(saved)
                Toast.show(L("Care card saved."))
                announceDataChanged()
                dismiss()
            } catch {
                form.apply(error, known: ["rebookEveryWeeks": "weeks"])
            }
        }
    }
}

// MARK: - Due back

/// Who is due back for grooming (web `GroomingDue`): the Due list's grooming rows
/// in their buckets, with the same reminder and the same booking.
struct SvcGroomDueTab: View {
    let canRemind: Bool
    let canBook: Bool
    let push: (ProviderRoute) -> Void

    @State private var windowDays = 30
    @State private var list: SvcDueList?
    @State private var failed: String?
    @State private var reminding: String?

    private var items: [SvcDueItem] { (list?.items ?? []).filter { $0.reason == "grooming" } }

    private static let buckets: [(key: String, state: ProviderState)] = [("overdue", .problem), ("this_week", .waiting), ("later", .upcoming)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Pets whose next groom is due, by their cadence and their last visit.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                HStack(spacing: 8) {
                    Text(L("Due window · Next")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkSoft)
                    Menu {
                        ForEach([7, 30, 60, 90], id: \.self) { days in
                            Button(LF("%d days", days)) { windowDays = days }
                        }
                    } label: {
                        FilterMenuLabel(title: LF("%d days", windowDays))
                    }
                }
            }
            if list == nil && failed == nil {
                LoadingState()
            } else if failed != nil, list == nil {
                SvcLoadError(message: L("The list couldn’t be loaded.")) { await load() }
            } else if items.isEmpty {
                EmptyState(systemImage: "scissors", title: L("Nobody is due back in this window."), message: L("A pet is due when its cadence (on its care card, or the default in Settings) has passed since its last groom."), accent: Theme.pink, panel: true)
            } else {
                ForEach(Self.buckets, id: \.key) { bucket in
                    let rows = items.filter { $0.bucket == bucket.key }
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeading(title: bucket.key == "overdue" ? L("Due bucket · Overdue") : bucket.key == "this_week" ? L("This week") : L("Later"), count: rows.count, dot: bucket.state.color, style: .heading, bubble: Theme.surfaceMuted, showsZero: true)
                            VStack(spacing: 0) {
                                ForEach(rows) { item in
                                    if item.id != rows.first?.id { RowDivider() }
                                    dueRow(item, tone: bucket.state.color)
                                }
                            }
                            .listCard()
                        }
                    }
                }
            }
        }
        .task(id: windowDays) {
            await load()
            if canBook { await SvcServices.load("provider") }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pawMiawDataChanged)) { _ in Task { await load() } }
    }

    /// One row (web `DueBucketList`): the bucket's colour down the left edge, the pet,
    /// how late, the chips that say what was done already, and the reminder and booking.
    private func dueRow(_ item: SvcDueItem, tone: Color) -> some View {
        let days = item.days ?? SvcTime.daysUntil(item.dueAt) ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Button { push(.patientChart(petId: item.pet.id)) } label: {
                    PetAvatar(name: item.pet.name, species: item.pet.species, photoURL: item.pet.photoUrl, size: 48)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 4) {
                    FlowLayout(spacing: 8) {
                        Button { push(.patientChart(petId: item.pet.id)) } label: {
                            Text(item.pet.name).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        }
                        .buttonStyle(.plain)
                        Chip(text: L("Grooming"), tone: .custom(Hue.lavender.color), icon: "scissors", percent: 26)
                    }
                    FlowLayout(spacing: 6) {
                        Text(SvcTime.dueWords(days)).fontWeight(.bold).foregroundStyle(item.bucket == "overdue" ? Theme.destructive : Theme.inkStrong)
                        Text("·")
                        Text(SvcTime.day(item.dueAt))
                        Text("·")
                        Button { push(.client(item.client.id)) } label: { Text(item.client.name).foregroundStyle(Theme.inkSoft) }.buttonStyle(.plain)
                        if let last = item.lastVisitAt {
                            Text("·")
                            Text(LF("last visit %@", SvcTime.day(last)))
                        }
                    }
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    chips(item)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            FlowLayout(spacing: 8) {
                if canRemind && item.client.phone?.nonEmpty != nil {
                    PMButton(L("WhatsApp"), systemImage: "message-circle", variant: .outline, size: .header, isWorking: reminding == item.key + "whatsapp") { Task { await remind(item, "whatsapp") } }
                        .disabled(reminding != nil)
                }
                if canRemind && item.client.onPawMiaw == true {
                    PMButton(L("Remind in PawMiaw"), systemImage: "smartphone", variant: .outline, size: .header, isWorking: reminding == item.key + "app") { Task { await remind(item, "app") } }
                        .disabled(reminding != nil)
                }
                if canBook {
                    // The Agenda's booking for this pet, tied to the Due row it answers; once it has a visit, booking is no longer the row's main thing.
                    PMButton(L("Book"), systemImage: "calendar-plus", variant: item.nextVisit == nil ? .primary : .outline, size: .header) {
                        push(SvcBook.groom(clientId: item.client.id, petId: item.pet.id, followUpId: item.followUpId))
                    }
                }
            }
            .padding(.leading, 60)
        }
        .padding(.vertical, 12)
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .overlay(alignment: .leading) { Rectangle().fill(tone).frame(width: 6) }
    }

    @ViewBuilder private func chips(_ item: SvcDueItem) -> some View {
        let familyNotice = item.familyNotice?.asked == true && item.familyNotice?.sentAt == nil && item.lastContact == nil && item.nextVisit == nil && item.snoozedUntil == nil && item.bucket != "overdue"
        if item.missedVisitAt != nil || item.nextVisit != nil || item.snoozedUntil != nil || familyNotice || item.lastContact != nil {
            FlowLayout(spacing: 6) {
                if let missed = item.missedVisitAt {
                    // It was booked and didn't happen: that is why it is here again.
                    Chip(text: (DateText.parse(missed) ?? .distantPast) > Date() ? LF("The visit on %@ was cancelled", SvcTime.day(missed)) : LF("The visit on %@ didn’t happen", SvcTime.day(missed)), tone: .custom(Theme.mango), icon: "calendar-x-2", percent: 26)
                }
                if let next = item.nextVisit {
                    // Already on the calendar: so nobody calls a family that has booked.
                    Chip(text: LF("Has a visit on %@: %@", SvcTime.day(next.startsAt), next.serviceLabel ?? ""), tone: .custom(Theme.blue), icon: "calendar-check", percent: 14)
                }
                if let until = item.snoozedUntil {
                    Chip(text: LF("Postponed until %@", SvcTime.day(until)), tone: .custom(Theme.surfaceMuted), icon: "clock-3", percent: 100)
                }
                if familyNotice, let due = DateText.parse(item.dueAt) {
                    // PawMiaw tells the family a week before, once: so nobody sends it twice by hand.
                    Chip(text: LF("PawMiaw tells the family on %@", SvcTime.day(DateText.iso(due.addingTimeInterval(-7 * 86_400)))), tone: .custom(Theme.blue), icon: "smartphone", percent: 14)
                }
                if let contact = item.lastContact {
                    // Already told: so nobody messages the same family twice.
                    Chip(text: contact.channel == "whatsapp" ? LF("WhatsApp opened %@", SvcTime.day(contact.at)) : LF("Reminded in PawMiaw %@", SvcTime.day(contact.at)), tone: .custom(ProviderState.done.color), icon: "check-check", percent: 16)
                }
            }
        }
    }

    private func load() async {
        do {
            list = try await API.get("/provider-due", query: ["window": "\(windowDays)"])
            failed = nil
        } catch is CancellationError {
        } catch {
            failed = errorText(error)
        }
    }

    /// In PawMiaw, or a WhatsApp chat opened with the message; the row then says it was reminded.
    private func remind(_ item: SvcDueItem, _ channel: String) async {
        reminding = item.key + channel
        defer { reminding = nil }
        do {
            let result: SvcRemindResult
            if let followUp = item.followUpId {
                result = try await API.post("/provider-follow-ups/\(followUp)/remind", body: ["channel": channel, "locale": svcLocale])
            } else {
                result = try await API.post("/provider-due/remind", body: ["providerClientPetId": item.pet.id, "reason": "grooming", "channel": channel, "locale": svcLocale])
            }
            if channel == "whatsapp", let link = result.link {
                svcOpen(link)
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

// MARK: - Settings

/// How this business grooms (web `GroomingSettingsPanel`): how often pets come
/// back, which stages the board has, and what "ready" says.
struct SvcGroomSettingsTab: View {
    let canManage: Bool
    let businessName: String

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var saved: SvcGroomingSettings?
    @State private var failed: String?
    @State private var weeks = ""
    @State private var simple = false
    @State private var message = ""
    @State private var working = false
    @StateObject private var form = FormState()

    private static let standard = "Hi {client}, this is {business}: {pet} is ready for pickup."

    private var parsedWeeks: (ok: Bool, weeks: Int?) {
        guard let text = weeks.nonEmpty else { return (true, nil) }
        guard let value = Int(text), (1...52).contains(value) else { return (false, nil) }
        return (true, value)
    }

    private var dirty: Bool {
        guard let saved else { return false }
        return parsedWeeks.weeks != saved.defaultRebookWeeks || !parsedWeeks.ok || simple != saved.simpleStages || message.nonEmpty != saved.readyMessage?.nonEmpty
    }

    var body: some View {
        if let saved {
            FormScroll(form: form) {
                SettingsCard(icon: "scissors", tone: Theme.pink, title: L("How you groom"),
                                hint: canManage ? L("For the whole business: the board’s stages, when pets are due back and what “ready” says.") : L("Set by whoever manages the business. You can read it here.")) {
                    if sizeClass == .regular {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) { dueRule; stagesRule }
                            messageRule
                        }
                    } else {
                        VStack(spacing: 16) { dueRule; stagesRule; messageRule }
                    }
                } footer: {
                    if canManage {
                        SaveBar(dirty: dirty, working: working, onDiscard: { reset(saved) }, onSave: save)
                    }
                }
            }
        } else if failed != nil {
            SvcLoadError(message: L("The settings couldn’t be loaded.")) { await load() }
        } else {
            LoadingState()
                .task { await load() }
        }
    }

    private var dueRule: some View {
        SettingsRule(icon: "repeat-2", tone: Theme.mango, title: L("Due back"), hint: L("When a pet’s care card doesn’t say how often it comes, it is due this many weeks after its last groom. Empty: six weeks.")) {
            FlowLayout(spacing: 8) {
                Text(L("Every")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                TextField("6", text: Binding(get: { weeks }, set: { weeks = String($0.filter(\.isNumber).prefix(2)); form.clear("weeks") }))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .fieldChrome(invalid: form.error("weeks") != nil || !parsedWeeks.ok)
                    .frame(width: 72)
                    .disabled(!canManage)
                Text(L("weeks")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                if !parsedWeeks.ok { Text(L("From 1 to 52")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.destructive) }
            }
            .id("weeks")
        }
    }

    private var stagesRule: some View {
        SettingsRule(icon: "workflow", tone: Theme.aqua, title: L("Stages on the board"),
                hint: simple ? L("Waiting → In progress → Ready for pickup. One stage for the whole groom.") : L("Waiting → Bath → Cut & dry → Ready for pickup. The bath and the table are two stages.")) {
            ToggleRow(title: L("Simple stages"), subtitle: L("For one groomer, or when the bath and the cut happen in one go."), isOn: $simple)
                .disabled(!canManage)
        }
    }

    private var messageRule: some View {
        SettingsRule(icon: "message-circle", tone: ProviderState.done.color, title: L("The “ready” message"),
                hint: L("What WhatsApp opens with when you tell a family their pet is ready. Leave it empty for the standard one, written in the family’s language.")) {
            TextField(L(Self.standard), text: $message, axis: .vertical)
                .lineLimit(3...8)
                .fieldChrome(multiline: true)
                .disabled(!canManage)
            if canManage {
                SvcPlaceholderRow(placeholders: ["{pet}", "{client}", "{business}"], onAdd: { message += $0 }, trailing: L("They become the pet, the client’s first name and your business."))
            }
            SvcMessagePreview(text: preview, standard: message.nonEmpty == nil)
        }
    }

    private var preview: String {
        let template = message.nonEmpty ?? L(Self.standard)
        return template
            .replacingOccurrences(of: "{pet}", with: "Rocky")
            .replacingOccurrences(of: "{client}", with: "Carlos")
            .replacingOccurrences(of: "{business}", with: businessName.nonEmpty ?? L("your business"))
    }

    private func reset(_ settings: SvcGroomingSettings) {
        weeks = settings.defaultRebookWeeks.map(String.init) ?? ""
        simple = settings.simpleStages
        message = settings.readyMessage ?? ""
    }

    private func load() async {
        do {
            let loaded: SvcGroomingSettings = try await API.get("/provider-grooming/settings")
            saved = loaded
            reset(loaded)
            failed = nil
        } catch is CancellationError {
        } catch {
            failed = errorText(error)
        }
    }

    private func save() {
        guard form.check([("weeks", parsedWeeks.ok ? nil : L("Weeks go from 1 to 52. Leave it empty for none."))]) else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let result: SvcGroomingSettings = try await API.put("/provider-grooming/settings", body: ["defaultRebookWeeks": parsedWeeks.weeks, "simpleStages": simple, "readyMessage": message.nonEmpty])
                saved = result
                reset(result)
                Toast.show(L("Grooming settings saved."))
                announceDataChanged()
            } catch {
                form.apply(error, known: ["defaultRebookWeeks": "weeks"])
            }
        }
    }
}
