//
//  RecordsRecordSheet.swift
//  PawMiawNegocios
//
//  Add or edit a record (web provider-record-sheet.tsx): choose the client and
//  the pet, the kind of record, then write it — its title, the kind's own
//  fields, the date, who it is assigned to, the family's summary, a follow-up
//  date (the next dose for a vaccine or a dewormer), the details, photos and
//  PDFs (up to 6, 10 MB each, dragged into the order they upload in), and the
//  staff-only note. Someone who signs saves it signed; anyone else saves a
//  draft that waits for a signature. Opened from another screen
//  (`init(context:)`), the client, pet, visit and type it hands in are
//  already chosen and their steps skipped.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// A photo or a document picked on this device, waiting for the record to be saved.
struct RecordsPickedFile: Identifiable {
    let id = UUID()
    let name: String
    let mime: String
    let data: Data
    var preview: UIImage? = nil
}

/// What a new record starts from, handed in by the screen that asks (web provider-record-sheet.tsx
/// `fixedProviderClientId`, `fixedProviderClientPetId`, `linkedAppointmentId`, `fixedRecordType`,
/// `initialAssignedOrganizationMemberId`). A client and its pet together skip "Client + pet"; a type skips
/// "Record type"; the visit is saved with the record.
struct RecordsSheetContext: Hashable {
    var clientId: String? = nil
    var petId: String? = nil
    var appointmentId: String? = nil
    var kind: RecordsKind? = nil
    var assigneeId: String? = nil

    /// The web's record type key ("vaccination", "vet_visit"…), and the names other screens may use for one.
    static func kind(_ raw: String?) -> RecordsKind? {
        guard let key = raw?.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "-", with: "_").nonEmpty else { return nil }
        if let kind = RecordsKind(rawValue: key) { return kind }
        switch key {
        case "vaccine", "vaccines": return .vaccination
        case "visit", "consultation", "consult", "exam": return .vetVisit
        case "dewormer", "deworm": return .deworming
        case "medicine", "medicines", "prescription", "treatment": return .medication
        case "lab", "labs", "lab_results", "result": return .labResult
        case "weight", "weigh_in": return .weightCheck
        case "diagnoses", "problem": return .diagnosis
        case "allergies": return .allergy
        case "notes": return .note
        default: return nil
        }
    }
}

struct RecordsRecordSheet: View {
    let record: RecordsRecord?
    let members: [RecordsMember]
    let access: RecordsAccess
    var onSaved: ((RecordsRecord) -> Void)? = nil
    /// The visit a new record is written at (saved with it).
    private let linkedAppointmentId: String?
    /// The client and the pet were handed in: "Client + pet" is skipped.
    private let fixedContext: Bool
    /// The kind was handed in: "Record type" is skipped.
    private let fixedType: Bool
    private let initialClientId: String

    private enum Step: Int { case selection, type, details }

    /// Images and PDFs, up to 6 files of 10 MB each.
    private static let maxFiles = 6
    private static let maxBytes = 10 * 1024 * 1024
    private static let allowedMimes: Set<String> = ["image/jpeg", "image/png", "image/webp", "image/gif", "image/heic", "application/pdf"]

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()

    @State private var step: Step
    @State private var clientId: String
    @State private var petId: String
    @State private var client: RecordsClient?
    @State private var kind: RecordsKind
    @State private var title: String
    @State private var summary: String
    @State private var details: String
    @State private var internalNote: String
    @State private var values: [String: String]
    @State private var eventDate: Date?
    @State private var followUpDate: Date?
    @State private var assignee: String
    @State private var newFiles: [RecordsPickedFile] = []
    @State private var removedSaved: Set<String> = []
    @State private var saving = false

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importing = false
    /// The picked file being dragged into a new place.
    @State private var draggingFile: UUID?

    init(record: RecordsRecord?, members: [RecordsMember], access: RecordsAccess, onSaved: ((RecordsRecord) -> Void)? = nil) {
        self.init(record: record, context: RecordsSheetContext(), members: members, access: access, onSaved: onSaved)
    }

    /// A new record with what the asking screen knows already chosen.
    init(context: RecordsSheetContext, members: [RecordsMember], access: RecordsAccess, onSaved: ((RecordsRecord) -> Void)? = nil) {
        self.init(record: nil, context: context, members: members, access: access, onSaved: onSaved)
    }

    private init(record: RecordsRecord?, context: RecordsSheetContext, members: [RecordsMember], access: RecordsAccess, onSaved: ((RecordsRecord) -> Void)?) {
        self.record = record
        self.members = members
        self.access = access
        self.onSaved = onSaved
        let handedClient = record == nil ? context.clientId?.nonEmpty : nil
        let handedPet = record == nil ? context.petId?.nonEmpty : nil
        linkedAppointmentId = record == nil ? context.appointmentId?.nonEmpty : nil
        fixedContext = handedClient != nil && handedPet != nil
        fixedType = record == nil && context.kind != nil
        initialClientId = record?.providerClientId ?? handedClient ?? ""
        let kind = record?.kind ?? context.kind ?? .vetVisit
        var values: [String: String] = [:]
        for field in kind.fields {
            if let saved = record?.payload?[field.key], !saved.isNull {
                switch saved {
                case .number(let number):
                    // Typed back as written, never with the locale's grouping ("1,500" would read as 1.5).
                    values[field.key] = number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
                case .bool(let flag):
                    values[field.key] = flag ? "true" : "false"
                default:
                    values[field.key] = saved.string ?? ""
                }
            } else {
                values[field.key] = kind.defaultValue(field.key)
            }
        }
        let current = members.first { $0.isCurrentMember == true }?.id
        let firstStep: Step = record != nil ? .details : (handedClient != nil && handedPet != nil) ? (context.kind != nil ? .details : .type) : .selection
        _step = State(initialValue: firstStep)
        _clientId = State(initialValue: record?.providerClientId ?? handedClient ?? "")
        _petId = State(initialValue: record?.providerClientPetId ?? handedPet ?? "")
        _client = State(initialValue: nil)
        _kind = State(initialValue: kind)
        _title = State(initialValue: record?.title ?? "")
        _summary = State(initialValue: record?.summary ?? "")
        _details = State(initialValue: record?.details ?? "")
        _internalNote = State(initialValue: record?.internalNote ?? "")
        _values = State(initialValue: values)
        _eventDate = State(initialValue: DateText.parse(record?.eventAt) ?? Date())
        _followUpDate = State(initialValue: DateText.parse(record?.followUpAt))
        // Someone who works alone is the one responsible; without "anyone", it is the reader.
        let handedAssignee = context.assigneeId.flatMap { id in members.contains { $0.id == id } ? id : nil }
        let initialAssignee = record?.assignedMember?.id ?? handedAssignee ?? (access.assignAnyone ? (members.count == 1 ? current : nil) : current) ?? ""
        _assignee = State(initialValue: initialAssignee)
    }

    private var isEditing: Bool { record != nil }
    private var currentMember: RecordsMember? { members.first { $0.isCurrentMember == true } }
    private var stepOrder: [Step] {
        if isEditing { return [.details] }
        return (fixedContext ? [] : [.selection]) + (fixedType ? [] : [.type]) + [.details]
    }
    private var initialStep: Step { stepOrder.first ?? .details }
    private var previousStep: Step? {
        guard let index = stepOrder.firstIndex(of: step), index > 0 else { return nil }
        return stepOrder[index - 1]
    }
    private var chosenPet: RecordsClientPet? { client?.pets?.first { $0.id == petId } }

    private var isDirty: Bool {
        if !newFiles.isEmpty || !removedSaved.isEmpty { return true }
        if let record {
            return title != (record.title ?? "") || summary != (record.summary ?? "") || details != (record.details ?? "")
                || internalNote != (record.internalNote ?? "")
        }
        return clientId != initialClientId || step != initialStep || !title.isEmpty
            || !summary.isEmpty || !details.isEmpty || !internalNote.isEmpty
    }

    private var primaryTitle: String {
        switch step {
        case .selection, .type: L("Continue")
        case .details: isEditing ? L("Save record") : L("Add record")
        }
    }

    var body: some View {
        ProviderModal(
            title: isEditing ? L("Edit record") : L("Add record"),
            subtitle: isEditing
                ? (record?.isDraft == true ? L("Change what is needed. It stays a draft until it is signed.") : L("Change what is needed. A signed record keeps a mark that it was corrected."))
                : L("Choose the pet, the kind of record, and write it down."),
            systemImage: "file-text",
            accent: .aqua,
            isDirty: isDirty,
            form: form,
            primaryTitle: primaryTitle,
            isWorking: saving,
            steps: stepOrder.count > 1 ? ModalSteps(stepOrder.map(stepLabel), icons: stepOrder.map(stepIcon), current: stepOrder.firstIndex(of: step) ?? 0) : nil,
            onBack: previousStep.map { previous in { step = previous } },
            primaryIcon: step == .details ? "file-text" : nil,
            onPrimary: primary
        ) {
            ContextPills(
                client: client?.ownerName ?? record?.clientName,
                linked: client.map { $0.householdId?.nonEmpty != nil } ?? record.map { $0.onPawMiaw },
                pets: [chosenPet?.petName ?? record?.petName].compactMap { $0?.nonEmpty }
            ) {
                if step == .details { recordsTypeChip(kind) }
            }
            switch step {
            case .selection: selectionStep
            case .type: typeStep
            case .details: detailsStep
            }
        }
        .environment(\.timeZone, Workspace.shared.timeZone)
        .presentationDetents([.large])
        .task {
            // A client handed in by id is read once (its name and pets); with one pet, that pet.
            guard record == nil, client == nil, !clientId.isEmpty else { return }
            guard let loaded = try? await RecordsAPI.client(clientId), loaded.id == clientId else { return }
            client = loaded
            if petId.isEmpty, loaded.activePets.count == 1 { petId = loaded.activePets[0].id }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await addPhotos(items) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .jpeg, .png, .heic, .gif, .webP], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): addFiles(urls)
            case .failure(let error): Toast.error(error)
            }
        }
    }

    // MARK: Steps

    private func stepIcon(_ step: Step) -> String {
        switch step {
        case .selection: "user-round"
        case .type: "clipboard-list"
        case .details: "file-text"
        }
    }

    private func stepLabel(_ step: Step) -> String {
        switch step {
        case .selection: L("Client + pet")
        case .type: L("Record type")
        case .details: L("Record@one")
        }
    }

    // MARK: Client and pet

    /// The one client-and-pet picker (search from 2 letters, 20 at a time, the chosen one on top);
    /// a vet who sees only their own clients searches only those. Each pet shows its chip.
    private var selectionStep: some View {
        ClientPetPicker(
            client: Binding(get: { client.map(RecordsClientBridge.picked) }, set: { picked in
                client = picked.map(RecordsClientBridge.records)
                clientId = picked?.id ?? ""
            }),
            petIds: Binding(get: { petId.isEmpty ? [] : [petId] }, set: { petId = $0.first ?? "" }),
            pets: .one,
            petRequired: true,
            key: "client",
            petKey: "pet",
            form: form,
            assignedMemberId: access.assignAnyone ? nil : currentMember?.id,
            petNote: { pet in pet.microchipNumber?.nonEmpty.map { (text: LF("Chip %@", $0), disabled: false) } }
        )
    }

    // MARK: Kind

    private var typeStep: some View {
        ModalSection(title: L("Choose record type"), subtitle: L("Pick the kind of provider-side medical history entry you want to save."), systemImage: "clipboard-list") {
            // The web's option cards: each kind with its icon, on the sheet's aqua.
            OptionCards(options: RecordsKind.allCases.map {
                OptionCard($0, title: $0.formLabel, description: $0.summaryText, icon: $0.systemImage, accent: Theme.aqua)
            }, selection: Binding(get: { kind }, set: { choose($0) }))
        }
    }

    private func choose(_ next: RecordsKind) {
        if next != kind {
            kind = next
            var fresh: [String: String] = [:]
            for field in next.fields { fresh[field.key] = next.defaultValue(field.key) }
            if let nameKey = next.titleNamesField, let typed = title.nonEmpty { fresh[nameKey] = typed }
            values = fresh
        }
        // A short beat on the chosen card before the record slides in, as the web's confirm blink.
        Task { try? await Task.sleep(for: .milliseconds(220)); step = .details }
    }

    // MARK: The record

    private var titleBinding: Binding<String> {
        Binding(get: { title }, set: { next in
            // The name field follows the title until it's typed apart from it.
            if let nameKey = kind.titleNamesField {
                let current = values[nameKey] ?? ""
                if current.isEmpty || current == title { values[nameKey] = next }
            }
            title = next
        })
    }

    private func value(_ key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0; form.clear("field.\(key)") })
    }

    private func dayValue(_ key: String) -> Binding<Date?> {
        Binding(get: { DateText.parse(values[key]) }, set: { values[key] = $0.map { DateText.dayKey($0) } ?? ""; form.clear("field.\(key)") })
    }

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            PMTextField(L("Title"), text: titleBinding, key: "title", form: form, prompt: LF("e.g. %@", kind.titlePlaceholder), required: true)

            let fields = kind.fields.filter { $0.isShown(values) }
            if !fields.isEmpty {
                ModalSection(title: LF("%@ details", RecordsText.isSpanish ? kind.formLabel.lowercased() : kind.formLabel), systemImage: kind.systemImage) {
                    ForEach(fields) { field in fieldView(field) }
                }
            }

            OptionalDateField(
                label: kind.eventDateLabel, date: $eventDate, placeholder: L("Choose a day"),
                max: Date(), key: "eventDate", form: form, optional: false, required: true
            )

            assigneeField

            PMTextField(kind == .vetVisit ? L("Owner summary") : L("Summary"), text: $summary, key: "summary", form: form,
                        prompt: kind == .vetVisit ? L("Short recap the owner can understand quickly") : L("Quick clinical summary"),
                        multiline: true)

            VStack(alignment: .leading, spacing: 8) {
                OptionalDateField(
                    label: kind.hasNextDose ? L("Next dose") : L("Follow-up date"), date: $followUpDate,
                    placeholder: kind.hasNextDose ? L("Add the next dose") : L("Add follow-up"),
                    min: DateText.calendar.startOfDay(for: Date()), key: "followUpDate", form: form, optional: false
                )
                if kind.hasNextDose {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            nextDosePick(L("In 3 weeks"), .weekOfYear, 3)
                            nextDosePick(L("In 1 month"), .month, 1)
                            nextDosePick(L("In 3 months"), .month, 3)
                            nextDosePick(L("In 1 year"), .year, 1)
                        }
                    }
                    Text(L("A family on PawMiaw gets a reminder a week before.")).font(Theme.text(13)).foregroundStyle(Theme.inkSoft)
                }
            }

            PMTextField(L("Details"), text: $details, key: "details", form: form,
                        prompt: kind == .vetVisit ? L("Owner-facing visit details, what happened today, and anything useful to remember.") : L("Clinical notes, observations, medication details, or anything the team should remember."),
                        multiline: true)

            ModalSection(title: L("Attachments"), subtitle: L("Images and PDFs that belong to this record, up to 10 MB each with a maximum of 6 files."), systemImage: "paperclip", tint: Theme.borderSoft) {
                attachments
            }

            ModalSection(title: L("Internal"), subtitle: L("Staff-only context. This note stays separate from the owner-facing record."), systemImage: "lock", tint: Theme.pink) {
                PMTextField(L("Internal note"), text: $internalNote, key: "internalNote", form: form,
                            prompt: L("Private clinical context, follow-up rationale, or anything the team should keep internal."),
                            multiline: true)
            }
        }
    }

    @ViewBuilder
    private func fieldView(_ field: RecordsField) -> some View {
        let required = field.isRequired(values)
        let key = "field.\(field.key)"
        switch field.input {
        case .text:
            PMTextField(L(field.label), text: value(field.key), key: key, form: form, prompt: L(field.placeholder), hint: field.helper.map { L($0) }, required: required)
        case .number:
            PMTextField(L(field.label), text: value(field.key), key: key, form: form, prompt: L(field.placeholder), hint: field.helper.map { L($0) }, keyboard: .decimalPad, required: required)
        case .date:
            OptionalDateField(label: L(field.label), date: dayValue(field.key), placeholder: L(field.placeholder), key: key, form: form, hint: field.helper.map { L($0) }, optional: false, required: required)
        case .select:
            VStack(alignment: .leading, spacing: 6) {
                MenuField(
                    label: L(field.label),
                    options: Self.menuOptions(field),
                    selection: value(field.key),
                    key: key,
                    form: form,
                    required: required
                )
                if let helper = field.helper {
                    Text(L(helper)).font(Theme.text(13)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    /// A choice's options, its placeholder first (nothing chosen).
    private static func menuOptions(_ field: RecordsField) -> [(value: String, title: String)] {
        var options: [(value: String, title: String)] = [(value: "", title: L(field.placeholder))]
        for option in field.options { options.append((value: option.value, title: L(option.label))) }
        return options
    }

    private var assigneeOptions: [(value: String, title: String)] {
        var options: [(value: String, title: String)] = [(value: "", title: L("Choose assignee"))]
        // `label` already says "(tú)" for the reader; adding it again read "Ana (tú) (tú)".
        for member in members { options.append((value: member.id, title: member.label)) }
        return options
    }

    private func nextDosePick(_ label: String, _ unit: Calendar.Component, _ amount: Int) -> some View {
        Button {
            let base = eventDate ?? Date()
            followUpDate = DateText.calendar.date(byAdding: unit, value: amount, to: base)
            form.clear("followUpDate")
        } label: {
            Text(label)
                .font(Theme.text(13, weight: .bold))
                .foregroundStyle(Theme.inkStrong)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .overlay(Capsule().stroke(Theme.borderSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var assigneeField: some View {
        if access.assignAnyone && !members.isEmpty {
            MenuField(
                label: L("Assignee"),
                options: assigneeOptions,
                selection: Binding(get: { assignee }, set: { assignee = $0; form.clear("assignee") }),
                key: "assignee",
                form: form,
                required: true
            )
        } else {
            FormField(label: L("Assignee"), key: "assignee", form: form, required: true) {
                Text(currentMember?.label ?? L("You"))
                    .font(Theme.text(15, weight: .semibold))
                    .foregroundStyle(Theme.inkStrong)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
            }
        }
    }

    // MARK: Files

    private var savedFiles: [RecordsAttachment] { record?.files ?? [] }
    private var usedSlots: Int { savedFiles.filter { !removedSaved.contains($0.id) }.count + newFiles.count }

    private var attachments: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !savedFiles.isEmpty || !newFiles.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(savedFiles) { saved in
                        let removed = removedSaved.contains(saved.id)
                        fileTile(name: saved.fileName, caption: removed ? L("Removed on save") : L("Saved"), dimmed: removed,
                                 icon: removed ? "arrow.uturn.backward" : "xmark",
                                 iconLabel: removed ? LF("Keep %@", saved.fileName) : LF("Remove %@@file", saved.fileName)) {
                            if saved.isImage { RecordsAuthImage(url: saved.url) } else { docFace(saved.fileName) }
                        } action: {
                            if removed { removedSaved.remove(saved.id) } else { removedSaved.insert(saved.id) }
                        }
                    }
                    ForEach(Array(newFiles.enumerated()), id: \.element.id) { index, file in
                        let place = newFiles.count > 1 ? index + 1 : nil
                        fileTile(name: file.name, caption: nil, dimmed: false, place: place, icon: "xmark", iconLabel: LF("Remove %@@file", file.name)) {
                            if let preview = file.preview {
                                Image(uiImage: preview).resizable().scaledToFill()
                            } else {
                                docFace(file.name)
                            }
                        } action: {
                            newFiles.removeAll { $0.id == file.id }
                        }
                        // Long-press and drag into another place: they upload in this order (the web's picker).
                        .onDrag {
                            draggingFile = file.id
                            return NSItemProvider(object: file.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: RecordsFileReorder(target: file.id, files: $newFiles, dragging: $draggingFile))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(LF("Move %@", file.name))
                        .accessibilityValue(place.map { LF("Place %d of %d", $0, newFiles.count) } ?? "")
                        .accessibilityAction(named: L("Move earlier")) { move(file.id, by: -1) }
                        .accessibilityAction(named: L("Move later")) { move(file.id, by: 1) }
                        .accessibilityAction(named: LF("Remove %@@file", file.name)) { newFiles.removeAll { $0.id == file.id } }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: newFiles.map(\.id))
                // A drop that lands between tiles still ends the drag.
                .onDrop(of: [.text], isTargeted: nil) { _ in
                    let wasDragging = draggingFile != nil
                    draggingFile = nil
                    return wasDragging
                }
            }
            let room = Self.maxFiles - usedSlots
            let limits = "\(L("Images and PDFs")) · \(LF("up to %@ each", "10 MB"))"
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(newFiles.count > 1 ? L("Drag to change the order.") : limits)
                Spacer(minLength: 4)
                Text(room <= 0 ? LF("Full: %d of %d", Self.maxFiles, Self.maxFiles) : LF("%d of %d", usedSlots, Self.maxFiles))
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(room <= 0 ? AnyShapeStyle(Theme.wash(Theme.mango, 30)) : AnyShapeStyle(Theme.surfaceMuted), in: Capsule())
            }
            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            if room > 0 {
                HStack(spacing: 8) {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: room, matching: .images) {
                        HStack(spacing: 6) { Glyph("images", size: 16); Text(L("Choose photos")) }
                    }
                    .buttonStyle(.pm(.outline, size: .compact))
                    PMButton(L("Choose files"), systemImage: "file-plus", variant: .outline, size: .compact) { importing = true }
                }
                .disabled(saving)
            }
        }
    }

    private func docFace(_ name: String) -> some View {
        let ext: String = {
            guard let dot = name.lastIndex(of: ".") else { return "" }
            return String(name[name.index(after: dot)...].prefix(4)).uppercased()
        }()
        return VStack(spacing: 4) {
            Glyph("file-text", size: 24).foregroundStyle(Theme.inkStrong)
            Text(ext.isEmpty ? L("File") : ext).font(.brandText(10, weight: .heavy)).foregroundStyle(Theme.inkStrong)
                .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.surface, in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.wash(Theme.pink, 16))
    }

    private func fileTile<Face: View>(name: String, caption: String?, dimmed: Bool, place: Int? = nil, icon: String, iconLabel: String, @ViewBuilder face: () -> Face, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { face() }
                .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                .opacity(dimmed ? 0.4 : 1)
                .overlay(alignment: .bottomLeading) {
                    // Its place in the upload order, when there is more than one.
                    if let place {
                        Text("\(place)")
                            .font(.brandText(11, weight: .heavy))
                            .foregroundStyle(Theme.surface)
                            .frame(width: 22, height: 22)
                            .background(Theme.inkStrong, in: Circle())
                            .padding(5)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button(action: action) {
                        Glyph(icon, size: 14)
                            .foregroundStyle(Theme.inkStrong)
                            .frame(width: 26, height: 26)
                            .background(Theme.surface, in: Circle())
                            .overlay(Circle().stroke(Theme.borderSoft, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(5)
                    .accessibilityLabel(iconLabel)
                }
            Text(name).font(Theme.text(11, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1).truncationMode(.middle)
            if let caption { Text(caption).font(Theme.text(11)).foregroundStyle(Theme.inkSoft) }
        }
    }

    /// One place earlier or later (VoiceOver's way to reorder).
    private func move(_ id: UUID, by offset: Int) {
        guard let from = newFiles.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard newFiles.indices.contains(to) else { return }
        newFiles.swapAt(from, to)
    }

    private func addPhotos(_ items: [PhotosPickerItem]) async {
        var problems: [String] = []
        for (offset, item) in items.enumerated() {
            guard usedSlots < Self.maxFiles else {
                problems.append(LF("Only %d fit: %d were left out.", Self.maxFiles, items.count - offset))
                break
            }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                problems.append(LF("%@ couldn’t be prepared.", L("Photo")))
                continue
            }
            let type = item.supportedContentTypes.first { $0.conforms(to: .image) } ?? .jpeg
            let mime = type.preferredMIMEType ?? "image/jpeg"
            let ext = type.preferredFilenameExtension ?? "jpg"
            let name = "\(L("Photo"))-\(newFiles.count + 1).\(ext)"
            guard Self.allowedMimes.contains(mime) else {
                problems.append(LF("%@ isn’t a supported file.", name))
                continue
            }
            guard data.count <= Self.maxBytes else {
                problems.append(LF("%@ is over %@.", name, "10 MB"))
                continue
            }
            newFiles.append(RecordsPickedFile(name: name, mime: mime, data: data, preview: UIImage(data: data)))
        }
        photoItems = []
        if let first = problems.first { Toast.error(first) }
    }

    private func addFiles(_ urls: [URL]) {
        var problems: [String] = []
        for (offset, url) in urls.enumerated() {
            guard usedSlots < Self.maxFiles else {
                problems.append(LF("Only %d fit: %d were left out.", Self.maxFiles, urls.count - offset))
                break
            }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            let type = UTType(filenameExtension: url.pathExtension)
            let mime = type?.preferredMIMEType ?? "application/octet-stream"
            guard Self.allowedMimes.contains(mime) else {
                problems.append(LF("%@ isn’t a supported file.", name))
                continue
            }
            guard let data = try? Data(contentsOf: url) else {
                problems.append(LF("%@ couldn’t be prepared.", name))
                continue
            }
            guard data.count <= Self.maxBytes else {
                problems.append(LF("%@ is over %@.", name, "10 MB"))
                continue
            }
            newFiles.append(RecordsPickedFile(name: name, mime: mime, data: data, preview: mime.hasPrefix("image/") ? UIImage(data: data) : nil))
        }
        if let first = problems.first { Toast.error(first) }
    }

    // MARK: Saving

    private func primary() {
        switch step {
        case .selection:
            guard checkSelection() else { return }
            step = .type
        case .type:
            step = .details
        case .details:
            save()
        }
    }

    private func checkSelection() -> Bool {
        form.check([
            ("client", clientId.isEmpty ? L("Choose the client first.") : nil),
            ("pet", petId.isEmpty ? L("Choose the pet first.") : nil),
        ])
    }

    /// Noon of that day on the business's clock (a record saved with only its day).
    private func noon(_ date: Date) -> String {
        let calendar = DateText.calendar
        let start = calendar.startOfDay(for: date)
        return DateText.iso(calendar.date(byAdding: .hour, value: 12, to: start) ?? date)
    }

    private func save() {
        if clientId.isEmpty || petId.isEmpty {
            if !isEditing && stepOrder.contains(.selection) { step = .selection }
            _ = checkSelection()
            return
        }
        let calendar = DateText.calendar
        let today = calendar.startOfDay(for: Date())
        var rules: [(String, String?)] = [("title", title.nonEmpty == nil ? L("Title is required.") : nil)]
        for field in kind.fields where field.isShown(values) {
            let text = values[field.key]?.trimmingCharacters(in: .whitespaces) ?? ""
            var message: String?
            if field.isRequired(values) && text.isEmpty {
                message = field.key == "weight_kg" ? L("Weight is required for a weight check.") : LF("%@ is required.", L(field.label))
            }
            rules.append(("field.\(field.key)", message))
        }
        let eventMessage: String? = {
            guard let eventDate else { return LF("%@ is required.", kind.eventDateLabel) }
            return calendar.startOfDay(for: eventDate) > today ? LF("%@ cannot be in the future.", kind.eventDateLabel) : nil
        }()
        rules.append(("eventDate", eventMessage))
        rules.append(("assignee", access.assignAnyone && !members.isEmpty && assignee.isEmpty ? L("Assignee is required.") : nil))
        if let followUpDate, calendar.startOfDay(for: followUpDate) < today {
            rules.append(("followUpDate", L("Follow-up date cannot be in the past.")))
        }
        guard form.check(rules), let eventDate else { return }

        // Saved fields this kind doesn't ask for stay as they were.
        var payload: [String: Any?] = [:]
        if let saved = record?.payload {
            let known = Set(kind.fields.map(\.key))
            for (key, entry) in saved where !known.contains(key) { payload.updateValue(recordsPlainValue(entry), forKey: key) }
        }
        for field in kind.fields where field.isShown(values) {
            let text = values[field.key]?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !text.isEmpty else { continue }
            if field.input == .number, let number = Double(text.replacingOccurrences(of: ",", with: ".")), number.isFinite {
                payload[field.key] = number
            } else {
                payload[field.key] = text
            }
        }

        var body: [String: Any?] = [
            "providerClientId": clientId,
            "providerClientPetId": petId,
            "recordType": kind.rawValue,
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
            "summary": summary.nonEmpty,
            "details": details.nonEmpty,
            "internalNote": internalNote.nonEmpty,
            "payload": payload.isEmpty ? nil : payload,
            "eventAt": noon(eventDate),
            "eventDate": DateText.dayKey(eventDate),
            "followUpAt": followUpDate.map { noon($0) },
            "followUpDate": followUpDate.map { DateText.dayKey($0) },
        ]
        let assigneeId = access.assignAnyone ? assignee.nonEmpty : (record?.assignedMember?.id ?? currentMember?.id)
        if let assigneeId { body["assignedOrganizationMemberId"] = assigneeId }
        if let record {
            if let appointment = record.appointmentId?.nonEmpty { body["appointmentId"] = appointment }
            if let revision = record.revision { body["expectedRevision"] = revision }
        } else {
            // Written at a visit when one was handed in; otherwise none.
            body.updateValue(linkedAppointmentId, forKey: "appointmentId")
        }

        saving = true
        Task {
            defer { saving = false }
            var saved: RecordsRecord
            do {
                if let record {
                    saved = try await API.patch("/provider-records/\(record.id)", body: body)
                } else {
                    saved = try await API.post("/provider-records", body: body)
                }
            } catch {
                let known = [
                    "title": "title", "summary": "summary", "details": "details", "internalNote": "internalNote",
                    "eventAt": "eventDate", "eventDate": "eventDate", "followUpAt": "followUpDate", "followUpDate": "followUpDate",
                    "assignedOrganizationMemberId": "assignee", "providerClientId": "client", "providerClientPetId": "pet",
                ]
                if form.apply(error, known: known), !isEditing, stepOrder.contains(.selection), form.error("client") != nil || form.error("pet") != nil {
                    step = .selection
                }
                return
            }

            // Files after the record: removed ones first, then the new ones in the order they were arranged.
            do {
                for id in removedSaved {
                    try await API.send("DELETE", "/provider-records/\(saved.id)/attachments/\(id)")
                }
                for file in newFiles {
                    let _: RecordsAttachment = try await API.upload("/provider-records/\(saved.id)/attachments", fileName: file.name, mimeType: file.mime, fileData: file.data)
                }
                if !removedSaved.isEmpty || !newFiles.isEmpty, let fresh = try? await RecordsAPI.record(saved.id) { saved = fresh }
            } catch {
                // The record is saved: saving again would write it twice. Say so, and close.
                Toast.error("\(L("Saved, but a file could not be added. Open the record to try again.")) \(errorText(error))")
                announceDataChanged()
                onSaved?(saved)
                dismiss()
                return
            }

            if isEditing {
                Toast.show(L("Record updated."))
            } else {
                Toast.show(saved.isDraft ? L("Saved as a draft. It waits for a signature.") : L("Record created."))
            }
            announceDataChanged()
            onSaved?(saved)
            dismiss()
        }
    }
}

/// Moves the dragged picked file into the place of the one it is over, as it passes (the web's
/// `rectSortingStrategy`); the drop only ends the drag.
private struct RecordsFileReorder: DropDelegate {
    let target: UUID
    @Binding var files: [RecordsPickedFile]
    @Binding var dragging: UUID?

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
              let from = files.firstIndex(where: { $0.id == dragging }),
              let to = files.firstIndex(where: { $0.id == target }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            files.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// The shared picker's client as the record sheet's, and back.
private enum RecordsClientBridge {
    static func picked(_ c: RecordsClient) -> PickedClient {
        PickedClient(id: c.id, ownerName: c.ownerName, ownerEmail: c.ownerEmail, ownerPhone: c.ownerPhone, householdId: c.householdId,
                     photoUrl: c.photoUrl, status: c.status,
                     pets: (c.pets ?? []).map { PickedPet(id: $0.id, petName: $0.petName, petSpecies: $0.petSpecies, petBreed: $0.petBreed, photoUrl: $0.photoUrl, status: $0.status, microchipNumber: $0.microchipNumber) },
                     petCount: c.petCount)
    }

    static func records(_ c: PickedClient) -> RecordsClient {
        RecordsClient(id: c.id, ownerName: c.ownerName, ownerEmail: c.ownerEmail, ownerPhone: c.ownerPhone, householdId: c.householdId,
                      photoUrl: c.photoUrl, petCount: c.petCount,
                      pets: (c.pets ?? []).map { RecordsClientPet(id: $0.id, petName: $0.petName, petSpecies: $0.petSpecies, petBreed: $0.petBreed, photoUrl: $0.photoUrl, microchipNumber: $0.microchipNumber, status: $0.status) },
                      status: c.status)
    }
}
