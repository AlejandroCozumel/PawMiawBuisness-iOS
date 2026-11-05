//
//  RecordDetailScreen.swift
//  PawMiawNegocios
//
//  One record (web routes/provider.records.$recordId.tsx): what it is and for
//  which pet, whether it is signed (shared with a family on PawMiaw) or still
//  a draft, the note labelled by who reads each part, its fields, its clinical
//  state, its files, its follow-ups, the visit it came from, the patient and
//  its history. Sign, edit, assign, add a follow-up date or files, and — for
//  an empty draft — discard it (the history keeps that it was).
//

import SwiftUI
import QuickLook

struct RecordDetailScreen: View {
    let recordId: String

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    @State private var record: RecordsRecord?
    @State private var loadError: String?
    @State private var notFound = false
    @State private var appointment: RecordsAppointment?
    @State private var followUps: [RecordsFollowUp] = []
    @State private var members: [RecordsMember] = []
    @State private var editing: RecordsSheetTarget?
    @State private var signing = false
    @State private var changingState = false
    @State private var previewURL: URL?
    @State private var openingFile: String?
    @State private var confirmDiscard = false
    @State private var discarded = false
    @State private var pushed: ProviderRoute?
    @State private var scrollTarget: String?

    private var access: RecordsAccess { RecordsAccess(workspace) }
    private var wide: Bool { sizeClass == .regular }

    var body: some View {
        PageScroll(maxWidth: wide ? 1120 : 820, refresh: { await load() }) {
            if !access.records {
                NoAccessState(message: L("Ask the workspace owner to let your role see records."))
            } else if let record {
                ScrollViewReader { proxy in
                    content(record)
                        .onChange(of: scrollTarget) { _, target in
                            guard let target else { return }
                            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .top) }
                            scrollTarget = nil
                        }
                }
            } else if notFound {
                EmptyState(
                    systemImage: "file-search",
                    title: L("Record not found"),
                    message: L("It may have been removed, or it belongs to another workspace or to someone else’s patients."),
                    actionTitle: L("See all records"),
                    action: { pushed = .section(.records) },
                    panel: true
                )
            } else if let loadError {
                ErrorState(message: loadError) { await load() }
            } else {
                LoadingState()
            }
        }
        .providerPage(record?.titleText ?? L("Record@one"))
        .reloadsOnScope { await load() }
        .quickLookPreview($previewURL)
        .navigationDestination(item: $pushed) { RouteView(route: $0) }
        .sheet(item: $editing) { target in
            RecordsRecordSheet(record: target.record, members: members, access: access) { saved in record = saved }
        }
        .sheet(isPresented: $confirmDiscard, onDismiss: { if discarded { dismiss() } }) {
            if let record {
                ConfirmSheet(
                    title: L("Discard this empty draft?"),
                    message: LF("%@ for %@ has nothing written in it. It goes away; the history keeps that it was discarded.", record.titleText, record.petText),
                    confirmTitle: L("Discard"),
                    destructive: true,
                    cancelTitle: L("Keep it"),
                    icon: "file-text"
                ) { _ in
                    try await RecordsAPI.discard(record.id)
                    Toast.show(L("Draft discarded."))
                    discarded = true
                    announceDataChanged()
                }
            }
        }
    }
    // MARK: Loading

    private func load() async {
        let a = access
        guard a.records else { return }
        let clinic = workspace.current?.clinicId
        let needTeam = a.editRecords && members.isEmpty && clinic != nil
        let id = recordId
        do {
            let fetched = try await RecordsAPI.record(id)
            record = fetched
            loadError = nil
            notFound = false
            let visitId = a.viewAppointments ? fetched.appointmentId?.nonEmpty : nil
            let visit = recordsStart(visitId != nil) { try await RecordsAPI.appointment(visitId ?? "") }
            let follow = recordsStart(a.viewFollowUps) { try await RecordsAPI.followUps(limit: 10, offset: 0, status: "all", record: id) }
            let team = recordsStart(needTeam) { try await RecordsAPI.members(clinicId: clinic ?? "") }
            appointment = await visit.value
            followUps = await follow.value?.items ?? followUps
            if let loaded = await team.value { members = loaded }
        } catch is CancellationError {
        } catch let error as APIError where error.status == 404 {
            if record == nil { notFound = true }
        } catch {
            if record == nil { loadError = errorText(error) } else { Toast.error(error) }
        }
    }

    // MARK: Actions

    private func sign(_ current: RecordsRecord) {
        guard !signing else { return }
        signing = true
        Task {
            defer { signing = false }
            do {
                if let signed = try await RecordsAPI.sign(current.id) { record = signed }
                Toast.show(current.onPawMiaw ? L("Signed. The family can see it now.") : L("Signed. It is part of the chart now."))
                announceDataChanged()
            } catch {
                Toast.error(error, fallback: L("Could not sign this record."))
            }
        }
    }

    private func changeClinicalState(_ current: RecordsRecord, to next: String) {
        guard !changingState, current.kind.clinicalState(current.payload) != next else { return }
        var payload = current.payload ?? [:]
        let today = DateText.dayKey()
        switch current.kind {
        case .diagnosis:
            payload["status"] = .string(next)
            payload["resolved_date"] = next == "resolved" ? .string(today) : .null
        case .medication:
            payload["status"] = .string(next)
            if next == "active" {
                payload["stop_date"] = .null
                payload["stop_reason"] = .null
            } else if payload["stop_date"]?.string?.nonEmpty == nil {
                payload["stop_date"] = .string(today)
            }
        case .allergy:
            payload["status"] = .string(next)
        default:
            return
        }
        changingState = true
        Task {
            defer { changingState = false }
            do {
                let plain: [String: Any?] = payload.mapValues { recordsPlainValue($0) }
                var body: [String: Any?] = ["payload": plain]
                if let revision = current.revision { body["expectedRevision"] = revision }
                record = try await RecordsAPI.update(current.id, body: body)
                Toast.show("\(LF("%@ updated.", current.kind.label)) \(LF("Now %@.", RecordsText.clinicalStateLabel(next).lowercased()))")
                announceDataChanged()
            } catch {
                Toast.error(error, fallback: L("Could not update this record right now."))
            }
        }
    }

    private func assign(_ current: RecordsRecord, to member: RecordsMember) {
        Task {
            do {
                var body: [String: Any?] = ["assignedOrganizationMemberId": member.id]
                if let revision = current.revision { body["expectedRevision"] = revision }
                record = try await RecordsAPI.update(current.id, body: body)
                Toast.show(L("Record updated."))
                announceDataChanged()
            } catch {
                Toast.error(error, fallback: L("Could not update this record right now."))
            }
        }
    }

    private func open(_ attachment: RecordsAttachment) {
        guard openingFile == nil else { return }
        openingFile = attachment.id
        Task {
            defer { openingFile = nil }
            do {
                previewURL = try await RecordsFileStore.shared.localFile(attachment)
            } catch {
                Toast.error(error)
            }
        }
    }

    // MARK: The page

    /// The header's ⋯ (web: the record's More menu): its pet, client and visit, assigning it, its
    /// history, and throwing an empty draft away.
    @ViewBuilder
    private func moreMenu(_ record: RecordsRecord) -> some View {
        let canEditThis = access.canEdit(record)
        Menu {
            if access.viewClients {
                Button { pushed = .patientChart(petId: record.providerClientPetId) } label: {
                    GlyphLabel(LF("Open %@’s chart", record.petText), icon: "paw-print")
                }
                Button { pushed = .client(record.providerClientId) } label: {
                    GlyphLabel(L("Open client"), icon: "user-round")
                }
            }
            if let visit = record.appointmentId?.nonEmpty, access.viewAppointments {
                Button { pushed = .appointment(visit) } label: { GlyphLabel(L("Open visit"), icon: "calendar-days") }
            }
            if canEditThis && access.assignAnyone && !members.isEmpty {
                Menu {
                    ForEach(members) { member in
                        Button { assign(record, to: member) } label: {
                            if record.assignedMember?.id == member.id { GlyphLabel(member.label, icon: "check") } else { Text(member.label) }
                        }
                    }
                } label: {
                    GlyphLabel(L("Assign to"), icon: "user-plus")
                }
            }
            Button { scrollTarget = "record-history" } label: { GlyphLabel(L("History of changes"), icon: "rotate-ccw") }
            if access.editRecords && record.isEmptyDraft {
                Divider()
                Button(role: .destructive) { confirmDiscard = true } label: { GlyphLabel(L("Discard this empty draft"), icon: "trash-2") }
            }
        } label: {
            IconCircleLabel()
        }
        .accessibilityLabel(L("More"))
    }

    @ViewBuilder
    private func content(_ record: RecordsRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(record)
            if wide {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) { mainColumn(record) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 16) { aside(record) }
                        .frame(width: 340)
                }
            } else {
                mainColumn(record)
                aside(record)
            }
        }
    }

    /// The module header (web `ProviderModuleHeader`): the pet's face, the title, what it is, for whom
    /// and when; its state, Sign, Edit and ⋯; the four numbers, each a jump to its card.
    private func header(_ record: RecordsRecord) -> some View {
        let canSign = record.isDraft && access.signRecords
        let canEditThis = access.canEdit(record)
        return ModuleHeader(
            icon: record.kind.systemImage,
            title: record.titleText,
            subtitle: [record.kind.label, record.petText, record.clientText, RecordsText.longDate(record.eventAt)].joined(separator: " · "),
            accent: Theme.aqua,
            media: AnyView(GeometryReader { proxy in
                PetAvatar(name: record.petName, species: record.petSpecies, photoURL: record.petPhotoUrl, size: proxy.size.width)
            }),
            titleAccessory: AnyView(RecordsStatusBadges(record: record)),
            stats: headerStats(record),
            storageKey: "record"
        ) {
            if canSign {
                PMButton(signing ? L("Signing…") : L("Sign"), systemImage: "badge-check", isWorking: signing) { sign(record) }
            }
            if canEditThis {
                PMButton(L("Edit"), systemImage: "pencil", variant: .outline) { editing = RecordsSheetTarget(record: record) }
            }
            moreMenu(record)
        }
    }

    private func headerStats(_ record: RecordsRecord) -> [ModuleStat] {
        let household = record.onPawMiaw
        let draft = record.isDraft
        let open = followUps.filter { ["open", "contacted", "snoozed"].contains($0.status ?? "open") }
        let next = open.sorted { ($0.dueAt ?? "") < ($1.dueAt ?? "") }.first
        let familyValue = draft ? L("Not shared") : household ? L("Shared") : L("Not on PawMiaw")
        let familyHint: String = draft
            ? (access.signRecords ? (household ? L("Draft — sign it to share") : L("Draft — sign it to make it part of the chart")) : L("Draft — waiting for a vet"))
            : (household ? LF("Signed %@", RecordsText.day(record.signedAt)) : LF("Signed %@ · only your clinic sees it", RecordsText.day(record.signedAt)))
        var stats: [ModuleStat] = [
            ModuleStat("shared", label: L("Family"), value: familyValue, hint: familyHint, icon: draft ? "pen-line" : "badge-check",
                       accent: draft ? ProviderState.waiting.color : ProviderState.done.color, attention: draft && access.signRecords,
                       action: { scrollTarget = "record-note" }),
        ]
        if access.viewFollowUps {
            stats.append(ModuleStat("follow-up", label: L("Follow-up"), value: next.map { RecordsText.day($0.dueAt) } ?? L("None@follow-up"),
                                    hint: next.map { "\(RecordsText.followUpTypeLabel($0.followUpType)) · \(RecordsText.dueLabel($0.dueAt))" } ?? (followUps.isEmpty ? L("Nothing due") : L("All closed")),
                                    icon: "bell-ring", accent: Theme.pink, attention: next?.isOverdue == true,
                                    action: { scrollTarget = "record-follow-ups" }))
        }
        stats.append(ModuleStat("files", label: L("Files"), value: "\(record.files.count)",
                                hint: record.files.isEmpty ? L("None attached") : L("Photos and documents"),
                                icon: "paperclip", accent: Theme.aqua, action: { scrollTarget = "record-files" }))
        if record.appointmentId?.nonEmpty != nil {
            stats.append(ModuleStat("visit", label: L("Visit"), value: appointment.map { RecordsText.day($0.startsAt) } ?? L("Linked@visit"),
                                    hint: appointment?.serviceLabel?.nonEmpty, icon: "calendar-days", accent: Theme.blue,
                                    action: { scrollTarget = "record-visit" }))
        }
        return stats
    }

    // MARK: Main column

    @ViewBuilder
    private func mainColumn(_ record: RecordsRecord) -> some View {
        let canEditThis = access.canEdit(record)
        let openEdit: (() -> Void)? = canEditThis ? { editing = RecordsSheetTarget(record: record) } : nil

        if record.isDraft {
            NoticeCard(
                tone: .warning,
                title: L("Draft — only your team can see it."),
                message: access.signRecords
                    ? (record.onPawMiaw ? LF("Sign it and %@ sees it in their app.", record.clientText) : L("Sign it to make it part of the chart."))
                    : (record.onPawMiaw ? L("A vet signs it before the family sees it.") : L("A vet signs it before it becomes part of the chart.")),
                actionTitle: access.signRecords ? L("Sign") : nil,
                action: access.signRecords ? { sign(record) } : nil
            )
        } else if record.amendedAt?.nonEmpty != nil {
            NoticeCard(
                tone: .info,
                title: record.onPawMiaw
                    ? LF("Corrected %@, after it was signed. The family sees the corrected version.", RecordsText.dateTime(record.amendedAt))
                    : LF("Corrected %@, after it was signed.", RecordsText.dateTime(record.amendedAt))
            )
        }

        if let states = record.kind.clinicalStates {
            clinicalCard(record, states: states, canChange: canEditThis)
        }

        noteSection(record, onEdit: openEdit).id("record-note")

        let rows = RecordsPayload.rows(record)
        if !rows.isEmpty {
            SectionCard(L("Record details"), subtitle: record.kind.label, icon: "file-text") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { RowDivider() }
                        RecordsLabelledRow(label: row.label, value: row.value)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }

        filesSection(record, onAdd: openEdit).id("record-files")

        if access.viewFollowUps {
            followUpsSection(record, onEdit: openEdit).id("record-follow-ups")
        }

        if record.appointmentId?.nonEmpty != nil {
            visitSection.id("record-visit")
        }

        AuditHistoryCard(entityType: "provider_record", entityId: record.id, title: L("History of changes"), description: L("Every edit, signature, file and follow-up on this record, and who made it."))
            .id("record-history")
    }

    /// The states a diagnosis, medicine or allergy moves through; the current one is raised (web `ClinicalStateCard`).
    private func clinicalCard(_ record: RecordsRecord, states: [String], canChange: Bool) -> some View {
        let current = record.kind.clinicalState(record.payload)
        return Card(spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Clinical status").uppercased()).font(.brandText(12, weight: .heavy)).tracking(1.44).foregroundStyle(Theme.inkSoft)
                    Text(current.map { RecordsText.clinicalStateLabel($0) } ?? "—").font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                }
                Spacer()
                if changingState { ProgressView().tint(Theme.blue) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Segmented(
                    options: states.map { .init($0, RecordsText.clinicalStateLabel($0)) },
                    selection: Binding(get: { current ?? states[0] }, set: { changeClinicalState(record, to: $0) }),
                    look: .raised,
                    label: L("Clinical status")
                )
            }
            .disabled(!canChange || changingState)
            .opacity(canChange ? 1 : 0.6)
        }
    }

    private func noteSection(_ record: RecordsRecord, onEdit: (() -> Void)?) -> some View {
        let summary = record.summary.nonEmpty
        let details = record.details.nonEmpty
        let staffNote = record.internalNote.nonEmpty
        let signer = record.signedBy?.name?.nonEmpty
        let empty = summary == nil && details == nil && staffNote == nil
        let familyAudience = !record.onPawMiaw ? L("Not on PawMiaw") : record.isSigned ? L("The family sees this") : L("The family sees it once signed")
        let hint = record.isSigned
            ? LF("Signed %@ by %@", RecordsText.dateTime(record.signedAt), signer ?? L("someone on the team"))
            : L("A draft — only your team can see it.")
        return SectionCard(title: L("Note"), subtitle: hint, icon: "file-text") {
            if let onEdit, empty {
                PMButton(L("Write the note"), systemImage: "plus", variant: .outline, size: .compact, action: onEdit)
            }
        } content: {
            if empty {
                EmptyState(systemImage: "file-text", title: L("Nothing written yet."))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if let summary {
                        RecordsNoteBlock(title: L("For the family"), audience: familyAudience, systemImage: "eye", tone: Theme.aqua, text: summary)
                    }
                    if let details {
                        RecordsNoteBlock(title: L("Clinical notes"), audience: L("In the chart"), systemImage: "stethoscope", tone: Theme.blue, text: details)
                    }
                    if let staffNote {
                        RecordsNoteBlock(title: L("Staff only"), audience: L("Never shown to the family"), systemImage: "lock", tone: Theme.mango, text: staffNote)
                    }
                    if record.isSigned, let signer {
                        RecordsSignature(name: signer, day: record.signedAt.map { RecordsText.day($0) })
                    }
                }
                .padding(16)
            }
        }
    }

    private func filesSection(_ record: RecordsRecord, onAdd: (() -> Void)?) -> some View {
        let files = record.files
        return SectionCard(title: L("Files"), subtitle: files.isEmpty ? nil : (files.count == 1 ? L("1 file") : LF("%d files", files.count)), icon: "paperclip") {
            if let onAdd, !files.isEmpty {
                PMButton(L("Add files"), systemImage: "plus", variant: .outline, size: .compact, action: onAdd)
            }
        } content: {
            if files.isEmpty {
                EmptyState(systemImage: "paperclip", title: L("No photos or documents attached."), actionTitle: onAdd == nil ? nil : L("Add files"), action: onAdd)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: wide ? 4 : 2), alignment: .leading, spacing: 12) {
                    ForEach(files) { attachment in
                        AttachmentTile(fileName: attachment.fileName, sizeText: attachment.sizeText, isImage: attachment.isImage, fileExtension: attachment.fileExtension,
                                       isOpening: openingFile == attachment.id) { open(attachment) } thumbnail: {
                            RecordsAuthImage(url: attachment.url)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func followUpsSection(_ record: RecordsRecord, onEdit: (() -> Void)?) -> some View {
        let open = followUps.filter { $0.isPending }.count
        return SectionCard(L("Follow-ups"), subtitle: open > 0 ? (open == 1 ? L("1 still open") : LF("%d still open", open)) : nil, icon: "bell-ring") {
            if followUps.isEmpty {
                EmptyState(systemImage: "bell-ring", title: L("No follow-up. Give the record a follow-up date and it becomes a task for the team."),
                           actionTitle: onEdit == nil ? nil : L("Add a follow-up date"), action: onEdit)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(followUps.enumerated()), id: \.element.id) { index, followUp in
                        if index > 0 { RowDivider() }
                        RecordsFollowUpRow(
                            followUp: followUp,
                            access: access,
                            compact: true,
                            reach: RecordsReach(phone: record.clientPhone?.nonEmpty, onPawMiaw: record.onPawMiaw),
                            onOpen: { pushed = $0 }
                        )
                    }
                }
            }
        }
    }

    private var visitSection: some View {
        SectionCard(title: L("Visit"), subtitle: L("Written during this visit."), icon: "calendar-days") {
            if let appointment, access.viewAppointments {
                PMButton(L("Open visit"), variant: .outline, size: .header) { pushed = .appointment(appointment.id) }
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                if let appointment {
                    HStack(spacing: 8) {
                        Text(appointment.serviceLabel?.nonEmpty ?? L("Visit")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        Chip(text: RecordsText.visitStatusLabel(appointment.status), tone: .custom(ProviderState.appointment(appointment.status).color))
                    }
                    FlowLayout(spacing: 16) {
                        RecordsMetaItem(icon: "calendar-days", text: RecordsText.dateTime(appointment.startsAt))
                        if let room = appointment.room?.nonEmpty { RecordsMetaItem(icon: "door-open", text: room) }
                        RecordsMetaItem(icon: "user-round", text: appointment.assignedMember?.name?.nonEmpty ?? L("Unassigned"))
                    }
                    .font(Theme.text(14))
                    .foregroundStyle(Theme.inkSoft)
                } else {
                    Text(L("This record is linked to a visit your role can’t open.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Aside

    @ViewBuilder
    private func aside(_ record: RecordsRecord) -> some View {
        SectionCard(L("Patient"), icon: "user-round") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    PetAvatar(name: record.petName, species: record.petSpecies, photoURL: record.petPhotoUrl, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        if access.viewClients {
                            Button { pushed = .patientChart(petId: record.providerClientPetId) } label: {
                                Text(record.petText).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(LF("Open %@’s chart", record.petText))
                        } else {
                            Text(record.petText).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        }
                        let profile = RecordsText.petProfile(record)
                        if !profile.isEmpty { Text(profile).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                    }
                    Spacer(minLength: 0)
                }
                if record.petMicrochipNumber?.nonEmpty != nil || record.petIsNeutered != nil {
                    VStack(alignment: .leading, spacing: 0) {
                        if let chip = record.petMicrochipNumber?.nonEmpty { RecordsLabelledRow(label: L("Microchip"), value: chip) }
                        if record.petMicrochipNumber?.nonEmpty != nil && record.petIsNeutered != nil { RowDivider() }
                        if let neutered = record.petIsNeutered { RecordsLabelledRow(label: L("Neutered"), value: neutered ? L("Yes") : L("No")) }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
                RowDivider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if access.viewClients {
                            Button { pushed = .client(record.providerClientId) } label: {
                                Text(record.clientText).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(record.clientText).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        TagChip(text: record.onPawMiaw ? L("Linked household") : L("Clinic-only"), icon: record.onPawMiaw ? "link-2" : "building-2", linked: record.onPawMiaw)
                    }
                    if let phone = record.clientPhone?.nonEmpty {
                        PhoneLink(phone: phone)
                    }
                    if let email = record.clientEmail?.nonEmpty, let url = URL(string: "mailto:\(email)") {
                        Link(destination: url) {
                            HStack(spacing: 8) {
                                Glyph("mail", size: 14).foregroundStyle(Theme.inkSoft)
                                Text(email).lineLimit(1)
                            }
                        }
                        .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    }
                }
            }
            .padding(16)
        }

        SectionCard(L("About this record"), icon: "file-text") {
            VStack(alignment: .leading, spacing: 0) {
                RecordsLabelledRow(label: L("Type"), value: record.kind.label)
                RowDivider()
                RecordsLabelledRow(label: L("Date"), value: RecordsText.longDate(record.eventAt))
                RowDivider()
                RecordsLabelledRow(label: L("Assigned to"), value: record.assignedMember?.name?.nonEmpty ?? L("Unassigned"))
                RowDivider()
                RecordsLabelledRow(label: L("Written by"), value: RecordsText.actorLine(record.createdBy?.name, record.createdAt))
                if record.updatedAt != record.createdAt {
                    RowDivider()
                    RecordsLabelledRow(label: L("Last change"), value: RecordsText.actorLine(record.updatedBy?.name, record.updatedAt))
                }
                if record.signedAt?.nonEmpty != nil {
                    RowDivider()
                    RecordsLabelledRow(label: L("Signed"), value: RecordsText.actorLine(record.signedBy?.name, record.signedAt))
                }
                if record.amendedAt?.nonEmpty != nil {
                    RowDivider()
                    RecordsLabelledRow(label: L("Corrected"), value: RecordsText.dateTime(record.amendedAt))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Pieces

/// A label and its value (web `LabelledRow`): 12 bold uppercase over 14 semibold; long values wrap.
struct RecordsLabelledRow: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.brandText(12, weight: .bold)).tracking(0.96).foregroundStyle(Theme.inkSoft)
            Text(value).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One part of the note and who reads it (web `NoteBlock`): a box washed 7% in its tone, the title
/// 14 extrabold, a pill saying who reads it, the text 14.
struct RecordsNoteBlock: View {
    let title: String
    let audience: String
    let systemImage: String
    let tone: Color
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(title).font(Theme.text(14, weight: .heavy)).foregroundStyle(Theme.inkStrong)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Glyph(systemImage, size: 12)
                    Text(audience).lineLimit(1)
                }
                .font(.brandText(10.9, weight: .heavy))
                .foregroundStyle(Theme.inkStrong)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Theme.wash(tone, 20), in: Capsule())
            }
            Text(text).font(Theme.text(14)).lineSpacing(3).foregroundStyle(Theme.inkStrong).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(tone, 7), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }
}

/// Who signed, in the signature hand, on a dashed line (as on the finish sheet and the signed PDFs).
struct RecordsSignature: View {
    let name: String
    let day: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Signed by").uppercased()).font(.brandText(11.2, weight: .heavy)).tracking(1.1).foregroundStyle(Theme.inkSoft)
            HStack(alignment: .lastTextBaseline) {
                Text(name).font(.signatureScript(32)).foregroundStyle(Theme.inkStrong).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                if let day { Text(day).font(Theme.text(11.2, weight: .semibold)).foregroundStyle(Theme.inkSoft) }
            }
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                Rectangle().stroke(style: StrokeStyle(lineWidth: 2, dash: [5, 4])).foregroundStyle(Theme.inkStrong.opacity(0.25)).frame(height: 1)
            }
        }
        .frame(maxWidth: 384, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 4)
    }
}
