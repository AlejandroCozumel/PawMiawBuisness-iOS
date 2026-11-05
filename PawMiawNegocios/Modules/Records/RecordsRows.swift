//
//  RecordsRows.swift
//  PawMiawNegocios
//
//  A record and a follow-up in a list (web records-page/record-row.tsx,
//  follow-up-row.tsx, pet-cell.tsx, record-bits.tsx), and the day-grouped
//  list both sit in, inside the page's one card: a band per day, rows under
//  it between hairlines. The row opens what it is about; the pet's name, its
//  client and the buttons are their own taps.
//

import SwiftUI

// MARK: - Bits

/// The record's kind, in its hue (web `RecordTypeChip`): the kit's chip at 18%, extrabold, its
/// icon in the hue (a note's in grey).
func recordsTypeChip(_ kind: RecordsKind) -> Chip {
    Chip(text: kind.label, tone: .custom(kind.hue.color), icon: kind.systemImage, percent: 18,
         iconInk: kind == .note ? AnyShapeStyle(Theme.inkSoft) : AnyShapeStyle(Theme.mix(kind.hue.color, 70, with: Theme.inkStrong)), iconSize: 14, weight: .heavy)
}

/// Draft or signed, and "Corrected" when it changed after it was signed (web `RecordStatusBadge`).
struct RecordsStatusBadges: View {
    let record: RecordsRecord
    var body: some View {
        HStack(spacing: 6) {
            Chip(text: record.isDraft ? L("Draft") : L("Signed"), tone: .custom(RecordsText.statusState(record).color), icon: record.isDraft ? "pen-line" : "badge-check")
            if !record.isDraft, record.amendedAt?.nonEmpty != nil {
                Chip(text: L("Corrected"), tone: .custom(ProviderState.upcoming.color), icon: "rotate-ccw")
                    .accessibilityHint(L("Changed after it was signed"))
            }
        }
    }
}

/// An icon and its text, tight, for the meta line under a row (12 type, a 12 icon).
struct RecordsMetaItem: View {
    let icon: String
    var text: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Glyph(icon, size: 12)
            if let text { Text(text).lineLimit(1) }
        }
    }
}

// MARK: - The pet

/// Whose row this is (web `PetCell`): the pet's face, its name (opens its chart) with the filter
/// button beside it, what it is ("Perro · Schnauzer", so two Lunas read apart) and its owner.
struct RecordsPetCell: View {
    let pet: RecordsPetFilter
    let species: String?
    let breed: String?
    var needle = ""
    let canViewClients: Bool
    var filterLabel: String? = nil
    var onFilter: (() -> Void)? = nil
    var onOpen: ((ProviderRoute) -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            PetAvatar(name: pet.name, species: pet.species, photoURL: pet.photoUrl, size: 40)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    if canViewClients, let onOpen {
                        Button { onOpen(.patientChart(petId: pet.id)) } label: {
                            Text(RecordsText.highlight(pet.name, needle)).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LF("Open %@’s chart", pet.name))
                    } else {
                        Text(RecordsText.highlight(pet.name, needle)).lineLimit(1)
                    }
                    if let onFilter, let filterLabel {
                        Button(action: onFilter) {
                            Glyph("list-filter", size: 14)
                                .foregroundStyle(Theme.inkSoft)
                                .frame(width: 28, height: 28)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(filterLabel)
                    }
                }
                .font(Theme.text(16, weight: .bold))
                .foregroundStyle(Theme.inkStrong)
                .frame(minHeight: 24)
                let kind = RecordsText.petKind(species: species, breed: breed)
                if !kind.isEmpty {
                    Text(kind).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Group {
                    if canViewClients, let onOpen {
                        Button { onOpen(.client(pet.clientId)) } label: { Text(RecordsText.highlight(pet.clientName, needle)) }
                            .buttonStyle(.plain)
                    } else {
                        Text(RecordsText.highlight(pet.clientName, needle))
                    }
                }
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
            }
        }
    }
}

// MARK: - The day-grouped list

/// A paged list under the day each row falls on, in the order the server sent them;
/// a day cut by the page break heads the next page too. 20 at a time, infinite scroll.
/// Drawn edge to edge inside the page's card.
struct RecordsDayList<Item: Decodable & Identifiable, Row: View, Empty: View>: View {
    @ObservedObject var pager: Pager<Item>
    let dayOf: (Item) -> String
    @ViewBuilder let empty: () -> Empty
    @ViewBuilder let row: (Item) -> Row

    private struct DayGroup: Identifiable {
        let id: String
        let day: String
        var items: [Item]
    }

    private var groups: [DayGroup] {
        var result: [DayGroup] = []
        for item in pager.items {
            let day = dayOf(item)
            if let last = result.last, last.day == day {
                result[result.count - 1].items.append(item)
            } else {
                result.append(DayGroup(id: "\(day)-\(result.count)", day: day, items: [item]))
            }
        }
        return result
    }

    var body: some View {
        if !pager.loadedOnce && pager.isLoading {
            LoadingState()
        } else if let error = pager.error, pager.items.isEmpty {
            ErrorState(message: error) { await pager.reload() }
        } else if pager.items.isEmpty {
            if pager.isLoading { LoadingState() } else { empty() }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { RowDivider() }
                    DayBand(title: RecordsText.capitalizedFirst(RecordsText.dayHeading(group.day)), style: .records)
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { position, item in
                        if position > 0 { RowDivider() }
                        row(item).onAppear { pager.loadMoreIfNeeded(item) }
                    }
                }
                PagerFooter(pager: pager)
            }
            .opacity(pager.isLoading ? 0.55 : 1)
            .animation(.easeOut(duration: 0.15), value: pager.isLoading)
        }
    }
}

// MARK: - A record

/// A record in a list: the pet it belongs to, its kind and state, its title and one line of what it
/// says, at what time and by whom. Drafts carry Sign for those who sign; an empty draft (To complete)
/// "Write it" and "Discard". The row opens the record's page.
struct RecordsRecordRow: View {
    enum Mode { case normal, unfinished }

    let record: RecordsRecord
    var mode: Mode = .normal
    let access: RecordsAccess
    var needle = ""
    var onSign: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDiscard: (() -> Void)? = nil
    var onFilterPet: (() -> Void)? = nil
    var onOpen: ((ProviderRoute) -> Void)? = nil

    private var canEdit: Bool { access.canEdit(record) && onEdit != nil }
    private var author: String? { record.assignedMember?.name?.nonEmpty ?? record.createdBy?.name?.nonEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                RecordsPetCell(
                    pet: record.petFilter,
                    species: record.petSpecies,
                    breed: record.petBreed,
                    needle: needle,
                    canViewClients: access.viewClients,
                    filterLabel: LF("See only %@’s records", record.petText),
                    onFilter: onFilterPet,
                    onOpen: onOpen
                )
                Spacer(minLength: 0)
                if let time = RecordsText.time(record.eventAt) {
                    Text(time).font(Theme.text(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    recordsTypeChip(record.kind)
                    RecordsStatusBadges(record: record)
                }
                Text(RecordsText.highlight(record.titleText, needle))
                    .font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    .padding(.top, 4)
                let summary = RecordsPayload.summaryLine(record)
                if !summary.isEmpty {
                    Text(RecordsText.highlight(summary, needle)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
            }
            HStack(spacing: 8) {
                meta
                Spacer(minLength: 0)
                actions
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onOpen?(.record(record.id)) }
        .accessibilityAction(named: LF("Open %@", record.titleText)) { onOpen?(.record(record.id)) }
    }

    private var meta: some View {
        HStack(spacing: 10) {
            if let author { RecordsMetaItem(icon: "user-round", text: author) }
            if !record.files.isEmpty {
                RecordsMetaItem(icon: "paperclip", text: "\(record.files.count)")
                    .accessibilityLabel(LF("%d files attached", record.files.count))
            }
            if record.followUpAt?.nonEmpty != nil {
                RecordsMetaItem(icon: "bell-ring", text: RecordsText.day(record.followUpAt))
                    .accessibilityLabel(L("Follow-up"))
            }
            if record.internalNote.nonEmpty != nil {
                RecordsMetaItem(icon: "lock").accessibilityLabel(L("Has a staff-only note"))
            }
        }
        .font(Theme.text(12))
        .foregroundStyle(Theme.inkSoft)
    }

    @ViewBuilder
    private var actions: some View {
        let showSign = mode == .normal && record.isDraft && access.signRecords && onSign != nil
        HStack(spacing: 6) {
            if mode == .unfinished {
                if canEdit, let onEdit {
                    PMButton(L("Write it"), systemImage: "pencil", size: .compact, action: onEdit)
                }
                if let onDiscard {
                    PMButton(L("Discard"), variant: .outline, size: .compact, action: onDiscard)
                }
            } else {
                if showSign, let onSign {
                    PMButton(L("Sign"), systemImage: "badge-check", size: .compact, action: onSign)
                }
                if canEdit, let onEdit {
                    IconCircleButton(systemImage: "pencil", label: LF("Edit %@", record.titleText), action: onEdit)
                }
            }
        }
    }
}

// MARK: - A follow-up

/// One follow-up: when it is due (red once late), for which pet, what it is and where it came
/// from, and what to do about it — done, a reminder by WhatsApp or in PawMiaw, or its visit.
/// A finished visit's paperwork is never "done" by hand: it closes when the note exists; an owner
/// or admin may say it needs none. The left edge carries the urgency, as on the Due page.
struct RecordsFollowUpRow: View {
    let followUp: RecordsFollowUp
    let access: RecordsAccess
    /// On a record's page: no pet, no source (it is that record).
    var compact = false
    /// Under a day heading: only the due words.
    var grouped = false
    var needle = ""
    var reach: RecordsReach? = nil
    /// Owners and admins may close a visit's paperwork without a note.
    var canWaive = false
    var onWaive: (() -> Void)? = nil
    var onFilterPet: (() -> Void)? = nil
    var onOpen: ((ProviderRoute) -> Void)? = nil

    @Environment(\.openURL) private var openURL
    @State private var busy = false

    private var pending: Bool { followUp.isPending }
    private var paperwork: Bool { followUp.isVisitPaperwork }
    private var showWhatsApp: Bool { reach == nil || reach?.phone != nil }
    private var showApp: Bool { reach?.onPawMiaw != false }
    private var canRemind: Bool {
        access.remindFollowUps && pending && (showWhatsApp || showApp) && !RecordsText.isInternalFollowUp(followUp.followUpType)
    }
    private var writesOnVisit: Bool {
        pending && !compact && followUp.followUpType == "documentation_needed" && followUp.providerAppointmentId?.nonEmpty != nil && access.viewAppointments
    }
    private var titleText: String { RecordsText.followUpTitle(followUp.title) }

    /// Where the row opens: its record, else its visit, else its client.
    private var source: ProviderRoute? {
        if compact { return nil }
        if let record = followUp.providerRecordId?.nonEmpty, access.viewRecords { return .record(record) }
        if let visit = followUp.providerAppointmentId?.nonEmpty, access.viewAppointments { return .appointment(visit) }
        if access.viewClients { return .client(followUp.providerClientId) }
        return nil
    }

    private var stripe: Color {
        if pending { return RecordsText.urgency(followUp.dueAt).color }
        return followUp.status == "done" ? ProviderState.done.color : Theme.borderSoft
    }

    private var subline: String {
        let sourceName = followUp.recordTitle?.nonEmpty ?? followUp.appointmentServiceLabel?.nonEmpty
        // "From Triple felina" under "Toca: Triple felina" says the same thing twice.
        let source = sourceName.flatMap { titleText.lowercased().contains($0.lowercased()) ? nil : $0 }
        var parts: [String] = []
        if !compact {
            if let source { parts.append(LF("From %@", source)) } else if sourceName == nil { parts.append(L("Added by hand")) }
        }
        if let note = RecordsText.followUpNote(followUp.note) { parts.append(note) }
        if let resolution = RecordsText.resolutionLabel(followUp) { parts.append(resolution) }
        if followUp.resolvedAt?.nonEmpty != nil { parts.append(LF("Closed %@", RecordsText.day(followUp.resolvedAt))) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if compact {
                due(alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    RecordsPetCell(
                        pet: followUp.petFilter,
                        species: followUp.petSpecies,
                        breed: followUp.petBreed,
                        needle: needle,
                        canViewClients: access.viewClients,
                        filterLabel: LF("See only %@’s follow-ups", followUp.petName?.nonEmpty ?? ""),
                        onFilter: onFilterPet,
                        onOpen: onOpen
                    )
                    Spacer(minLength: 0)
                    due(alignment: .trailing)
                }
            }
            main
            actions
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(stripe).frame(width: 6) }
        .contentShape(Rectangle())
        .onTapGesture { if let source { onOpen?(source) } }
        .accessibilityAction(named: LF("Open %@", titleText)) { if let source { onOpen?(source) } }
    }

    private func due(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(pending ? RecordsText.dueLabel(followUp.dueAt) : RecordsText.day(followUp.dueAt))
                .font(.brandText(14, weight: .heavy))
                .foregroundStyle(!pending ? Theme.inkSoft : (followUp.isOverdue ? Theme.destructive : Theme.inkStrong))
                .lineLimit(1)
            if pending && !grouped {
                Text(RecordsText.day(followUp.dueAt)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Chip(text: RecordsText.followUpTypeLabel(followUp.followUpType), tone: .custom(Theme.lavender), icon: "bell-ring")
                if !pending || followUp.status != "open" {
                    Chip(text: RecordsText.followUpStatusLabel(followUp.status), tone: .custom(RecordsText.followUpState(followUp.status).color))
                }
            }
            Text(RecordsText.highlight(titleText, needle)).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                .padding(.top, 4)
            let sub = subline
            if !sub.isEmpty {
                Text(sub).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            RecordsMetaItem(icon: "user-round", text: followUp.assignedMember?.name?.nonEmpty ?? L("Unassigned"))
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var actions: some View {
        let canDone = access.completeFollowUps && pending && !paperwork
        let canNotNeeded = paperwork && pending && canWaive && onWaive != nil
        let visitLink = !compact && !writesOnVisit && followUp.providerAppointmentId?.nonEmpty != nil && access.viewAppointments
        if writesOnVisit || canDone || canNotNeeded || canRemind || visitLink {
            FlowLayout(spacing: 8) {
                if writesOnVisit, let visit = followUp.providerAppointmentId {
                    PMButton(L("Open visit"), systemImage: "calendar-days", size: .header) { onOpen?(.appointment(visit)) }
                }
                if canDone {
                    PMButton(L("Done"), systemImage: "circle-check", variant: writesOnVisit ? .outline : .primary, size: .header, isWorking: busy) {
                        Task { await complete() }
                    }
                }
                if canNotNeeded, let onWaive {
                    PMButton(L("Not needed…"), systemImage: "file-x-2", variant: .outline, size: .header, action: onWaive)
                        .disabled(busy)
                }
                if canRemind {
                    Menu {
                        if showWhatsApp {
                            Button { Task { await remind("whatsapp") } } label: { GlyphLabel("WhatsApp", icon: "message-circle") }
                        }
                        if showApp {
                            Button { Task { await remind("app") } } label: { GlyphLabel(L("In PawMiaw"), icon: "smartphone") }
                        }
                    } label: {
                        HStack(spacing: 6) { Glyph("message-circle", size: 16); Text(L("Remind")) }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.pm(.outline, size: .header))
                    .disabled(busy)
                }
                if visitLink, let visit = followUp.providerAppointmentId {
                    PMButton(L("Visit"), systemImage: "calendar-days", variant: .outline, size: .header) { onOpen?(.appointment(visit)) }
                }
            }
        }
    }

    private func complete() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await RecordsAPI.updateFollowUp(followUp.id, body: ["status": "done"])
            Toast.show(L("Follow-up done."))
            announceDataChanged()
        } catch {
            Toast.error(error, fallback: L("Could not complete this follow-up."))
        }
    }

    private func remind(_ channel: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await RecordsAPI.remind(followUp.id, channel: channel)
            if channel == "whatsapp", let link = result.link.nonEmpty, let url = URL(string: link) {
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
