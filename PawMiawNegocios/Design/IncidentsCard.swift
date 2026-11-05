//
//  IncidentsCard.swift
//  PawMiawNegocios
//
//  The incidents of an act — a visit, a stay or a home stay (web
//  incidents/incidents-card.tsx, incident-sheet.tsx, incident-bits.tsx;
//  backend docs/consents-incidents.md): each one with what kind, how serious,
//  when, what happened and what was done, who was there, the photos (shown
//  large on a tap) and whether the family was told, and its follow-up — add a
//  photo, close it with a note the family reads, or open it again. "Record an
//  incident" once the pet has arrived; the family and the owners are told as
//  soon as it is sent, so the last step says so before it goes.
//  Used by the visit page (Schedule), the stay, the home stay and a stay's
//  report card (Stays).
//

import SwiftUI
import PhotosUI

// MARK: - Models (use-incidents.ts)

struct Incident: Codable, Identifiable, Hashable {
    let id: String
    let providerClientPetId: String?
    let petName: String?
    let type: String
    let severity: String
    let occurredAt: String?
    let whatHappened: String?
    let actionsTaken: String?
    let involved: String?
    let photos: [String]?
    let status: String
    let resolvedAt: String?
    let resolvedByName: String?
    let resolutionNote: String?
    let familyVisible: Bool?
    let familyNotifiedAt: String?
    let reportedByName: String?
    let createdAt: String?
    let legacy: Bool?
}

struct IncidentList: Codable {
    let items: [Incident]?
    let canRecord: Bool?
}

struct IncidentRecorded: Codable {
    struct Notified: Codable { let family: Int?; let owners: Int? }
    let id: String?
    let notified: Notified?
    let photoErrors: Int?
}

// MARK: - Words (incidents-copy.ts)

enum IncidentWords {
    static let types = ["bite", "injury", "escape", "illness", "property_damage", "other"]
    static let severities = ["minor", "moderate", "serious"]
    static let photoMax = 6

    static func type(_ type: String) -> String {
        switch type {
        case "bite": L("Bite")
        case "injury": L("Injury")
        case "escape": L("Escape or lost")
        case "illness": L("Illness")
        case "property_damage": L("Property damage")
        default: L("Something else")
        }
    }

    static func typeIcon(_ type: String) -> String {
        switch type {
        case "bite": "dog.fill"
        case "injury": "bandage.fill"
        case "escape": "door.left.hand.open"
        case "illness": "allergens"
        case "property_damage": "hammer.fill"
        default: "questionmark.circle.fill"
        }
    }

    static func severity(_ severity: String) -> String {
        switch severity {
        case "moderate": L("Needs attention")
        case "serious": L("Serious")
        default: L("Minor")
        }
    }

    static func severityHint(_ severity: String) -> String {
        switch severity {
        case "moderate": L("Needs watching or a follow-up.")
        case "serious": L("Needed a vet, or could harm the pet or someone.")
        default: L("Handled on the spot, nothing more expected.")
        }
    }

    /// The colour each severity wears (INCIDENT_STATE).
    static func state(_ severity: String) -> ProviderState {
        switch severity {
        case "moderate": .waiting
        case "serious": .problem
        default: .upcoming
        }
    }

    static func error(_ error: Error, fallback: String) -> String {
        if let api = error as? APIError {
            if api.isOffline { return api.message }
            switch api.code {
            case "act_required": return L("Choose the visit or the stay it happened in.")
            case "act_not_started": return L("An incident is recorded once the pet has arrived.")
            case "pet_not_in_act": return L("That pet isn’t part of this visit or stay.")
            case "future_date": return L("It can’t be in the future.")
            case "too_many_photos": return L("Up to 6 photos.")
            case "invalid_photo": return L("Photos must be JPG, PNG or WebP, up to 8 MB.")
            case "already_resolved": return L("This incident is already resolved.")
            case "not_resolved": return L("This incident is still open.")
            case "upload_failed": return L("The photo didn’t upload. Try again.")
            default: break
            }
            if api.status == 403 { return L("You don’t have permission to do this.") }
            if !api.message.isEmpty, api.isRefusal || LocalizationManager.shared.currentLanguage != .spanish { return api.message }
        }
        return L(fallback)
    }

    /// Open first, then the most recent.
    static func sorted(_ items: [Incident]) -> [Incident] {
        items.sorted { a, b in
            a.status == b.status ? (a.occurredAt ?? "") > (b.occurredAt ?? "") : a.status == "open"
        }
    }
}

// MARK: - The card

private enum IncidentSheet: Identifiable {
    case record
    case resolve(Incident)
    var id: String {
        switch self {
        case .record: "record"
        case .resolve(let incident): "resolve-\(incident.id)"
        }
    }
}

/// The incidents of a visit or a stay: each one with its follow-up, and "Record an incident".
struct IncidentsCard: View {
    let act: ConsentAct
    let pets: [ActPet]
    var familyName: String? = nil
    /// The pet is here (or was): a stay checked in or out, a visit under way or done.
    let recordable: Bool
    /// Inside a page section: no card of its own.
    var bare = false
    /// Bumped by an action row outside the card ("Record an incident" beside the stay's moves); the card opens its sheet.
    var recordRequest: Int = 0
    /// Whether the card shows its own "Record an incident" (false when the page's action row has it).
    var showsRecordButton: Bool = true

    @State private var list: IncidentList?
    @State private var failed: String?
    @State private var forbidden = false
    @State private var sheet: IncidentSheet?

    private var items: [Incident] { IncidentWords.sorted(list?.items ?? []) }
    private var canRecord: Bool { list?.canRecord == true }
    private var openCount: Int { items.filter { $0.status == "open" }.count }
    private var recordButton: Bool { showsRecordButton && canRecord && recordable }

    var body: some View {
        Group {
            if forbidden {
                EmptyView()
            } else if bare {
                VStack(alignment: .leading, spacing: 12) {
                    if recordButton {
                        PMButton(L("Record an incident"), systemImage: "exclamationmark.shield", variant: .outline, size: .compact) { sheet = .record }
                    }
                    content
                }
            } else if (list != nil || failed != nil) && (!items.isEmpty || recordButton || failed != nil) {
                // A card of its own shows once there is something in it or something to do.
                Card {
                    HStack(spacing: 8) {
                        Label(L("Incidents"), systemImage: "exclamationmark.shield.fill").font(Theme.sectionFont).foregroundStyle(Theme.inkStrong)
                        Spacer()
                        if openCount > 0 { StatusChip(text: openCount == 1 ? L("1 open") : LF("%d open", openCount), state: .problem) }
                    }
                    content
                    if recordButton {
                        PMButton(L("Record an incident"), systemImage: "exclamationmark.shield", variant: .outline, size: .compact, fullWidth: true) { sheet = .record }
                    }
                }
            } else {
                // Nothing to show yet: still here, so it loads and hears of changes.
                Color.clear.frame(height: 0)
            }
        }
        .reloadsOnScope { await load() }
        .onChange(of: recordRequest) { _, _ in sheet = .record }
        .sheet(item: $sheet) { which in
            switch which {
            case .record: IncidentRecordSheet(act: act, pets: pets, familyName: familyName)
            case .resolve(let incident): IncidentResolveSheet(incident: incident)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if list == nil && failed == nil {
            ProgressView().frame(maxWidth: .infinity, minHeight: 56)
        } else if let failed, list == nil {
            HStack(spacing: 10) {
                Text(failed).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                PMButton(L("Try again"), variant: .outline, size: .compact) { Task { await load() } }
            }
        } else if items.isEmpty {
            Text(L("No incidents. If something happens — a bite, an injury, an escape — record it here and the family and the owners are told."))
                .font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
        } else {
            ForEach(items) { incident in
                IncidentItem(incident: incident, showPet: pets.count > 1, canFollowUp: canRecord) { sheet = .resolve(incident) }
            }
        }
    }

    private func load() async {
        guard !act.isEmpty else { return }
        do {
            list = try await API.get("/provider-incidents", query: act.query)
            failed = nil
        } catch is CancellationError {
        } catch {
            // A role that doesn't see incidents doesn't see the card.
            if (error as? APIError)?.status == 403 { forbidden = true; return }
            failed = IncidentWords.error(error, fallback: "The incidents could not be loaded.")
        }
    }
}

/// One incident as the team sees it, with its follow-up.
struct IncidentItem: View {
    let incident: Incident
    let showPet: Bool
    let canFollowUp: Bool
    let onResolve: () -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var adding = false
    @State private var reopening = false
    @State private var viewing: IncidentPhoto?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 6) {
                HueChip(text: IncidentWords.type(incident.type), hue: .peach, systemImage: IncidentWords.typeIcon(incident.type))
                StatusChip(text: IncidentWords.severity(incident.severity), state: IncidentWords.state(incident.severity))
                StatusChip(text: incident.status == "resolved" ? L("Resolved") : L("Follow-up open"), state: incident.status == "resolved" ? .done : .active, outlined: true)
                if showPet, let pet = incident.petName?.nonEmpty { HueChip(text: pet, hue: .grey, systemImage: "pawprint.fill") }
            }
            Text([ConsentWords.date(incident.occurredAt), incident.reportedByName.map { LF("Recorded by %@", $0) }].compactMap { $0 }.joined(separator: " · "))
                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            block(L("What happened"), incident.whatHappened)
            block(L("What was done"), incident.actionsTaken)
            block(L("Who was involved"), incident.involved)
            let photos = incident.photos ?? []
            if !photos.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, url in
                        Button { viewing = IncidentPhoto(url: url, index: index) } label: {
                            AsyncImage(url: APIConfig.assetURL(url)) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() } else { Theme.surfaceMuted }
                            }
                            .frame(height: 72)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LF("Photo %d of the incident", index + 1))
                    }
                }
            }
            if incident.status == "resolved" {
                VStack(alignment: .leading, spacing: 4) {
                    Label(L("How it ended").uppercased(), systemImage: "checkmark.seal.fill").font(.brandText(11, weight: .heavy)).foregroundStyle(Theme.inkSoft)
                    Text(incident.resolutionNote ?? "—").font(Theme.smallFont).foregroundStyle(Theme.inkStrong).fixedSize(horizontal: false, vertical: true)
                    Text([incident.resolvedByName, incident.resolvedAt.map { ConsentWords.date($0) }].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ProviderState.done.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Text(incident.legacy == true ? L("From an earlier report card: only the team saw it.")
                 : incident.familyNotifiedAt != nil ? LF("The family was told %@", ConsentWords.date(incident.familyNotifiedAt))
                 : incident.familyVisible == true ? L("The family sees it in their app.") : L("The family isn’t on PawMiaw: tell them yourself."))
                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            if canFollowUp {
                FlowLayout(spacing: 8) {
                    if photos.count < IncidentWords.photoMax && incident.legacy != true {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            HStack(spacing: 6) {
                                if adding { ProgressView().controlSize(.small) } else { Image(systemName: "camera.fill") }
                                Text(L("Add photo"))
                            }
                        }
                        .buttonStyle(.pm(.outline, size: .compact))
                        .disabled(adding)
                    }
                    if incident.status == "open" {
                        PMButton(L("Close the follow-up"), systemImage: "checkmark.seal", size: .compact, action: onResolve)
                    } else {
                        PMButton(L("Open again"), systemImage: "arrow.counterclockwise", variant: .outline, size: .compact, isWorking: reopening) { reopen() }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(incident.status == "open" ? Theme.pink : Theme.borderSoft, lineWidth: incident.status == "open" ? 2 : 1))
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task { await addPhoto(item) }
        }
        .sheet(item: $viewing) { photo in
            IncidentPhotoSheet(photos: incident.photos ?? [], start: photo.index, title: incident.petName)
        }
    }

    @ViewBuilder private func block(_ label: String, _ text: String?) -> some View {
        if let text = text?.nonEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased()).font(.brandText(11, weight: .heavy)).tracking(1).foregroundStyle(Theme.inkSoft)
                Text(text).font(Theme.smallFont).foregroundStyle(Theme.inkStrong).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func addPhoto(_ item: PhotosPickerItem) async {
        adding = true
        defer { adding = false }
        guard let jpeg = await ImageUpload.load(item) else {
            Toast.error(L("Could not add the photo. Try again."))
            return
        }
        do {
            let _: Incident = try await ImageUpload.upload(jpeg, to: "/provider-incidents/\(incident.id)/photos")
            Toast.show(L("Photo added."))
            announceDataChanged()
        } catch {
            Toast.error(IncidentWords.error(error, fallback: "Could not add the photo. Try again."))
        }
    }

    private func reopen() {
        reopening = true
        Task {
            defer { reopening = false }
            do {
                let _: Incident = try await API.post("/provider-incidents/\(incident.id)/reopen", body: [:])
                Toast.show(L("Follow-up open again."))
                announceDataChanged()
            } catch {
                Toast.error(IncidentWords.error(error, fallback: "Could not open it again. Try again."))
            }
        }
    }
}

struct IncidentPhoto: Identifiable { let url: String; let index: Int; var id: Int { index } }

/// An incident's photos, large, one after another.
struct IncidentPhotoSheet: View {
    let photos: [String]
    let start: Int
    var title: String? = nil
    @State private var page = 0

    var body: some View {
        ProviderModal(title: title ?? L("Photos"), subtitle: LF("Photo %d of the incident", page + 1), systemImage: "photo.on.rectangle", accent: .pink, cancelTitle: L("Close")) {
            TabView(selection: $page) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, url in
                    AsyncImage(url: APIConfig.assetURL(url)) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() } else { ProgressView() }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page)
            .frame(height: 420)
        }
        .onAppear { page = start }
    }
}

// MARK: - Record an incident

/// What kind, how serious, when, what happened and what was done, who was there,
/// which pet and up to six photos — then a last step that says who is told before it goes.
struct IncidentRecordSheet: View {
    let act: ConsentAct
    let pets: [ActPet]
    var familyName: String? = nil
    var initialPetId: String? = nil
    /// Once it is sent (the report card it was opened from closes too).
    var onRecorded: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var type: String?
    @State private var severity = "minor"
    @State private var occurredAt = Date()
    @State private var petId: String?
    @State private var whatHappened = ""
    @State private var actionsTaken = ""
    @State private var involved = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photos: [Data] = []
    @State private var confirming = false
    @State private var working = false

    private var petName: String? { pets.first { $0.id == petId }?.name ?? (pets.count == 1 ? pets.first?.name : nil) }

    var body: some View {
        ProviderModal(
            title: L("Record an incident"),
            subtitle: L("The family and the owners are told right away, and it stays open until you close the follow-up."),
            systemImage: "exclamationmark.shield.fill",
            accent: .pink,
            isDirty: type != nil || !whatHappened.isEmpty || !photos.isEmpty,
            form: form,
            primaryTitle: confirming ? L("Send the report") : L("Review and send"),
            isWorking: working,
            onPrimary: confirming ? send : review
        ) {
            if confirming {
                NoticeCard(tone: .problem, title: familyName.map { LF("%@ and the owners get this report now, with its photos. It can’t be taken back — you can add a closing note later.", $0) }
                    ?? L("The family and the owners get this report now, with its photos. It can’t be taken back — you can add a closing note later."))
                PMButton(L("Back to edit"), systemImage: "chevron.left", variant: .outline, size: .compact) { confirming = false }
            }
            Group {
                ModalSection(title: L("What kind")) {
                    FormField(label: "", key: "type", form: form) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                            ForEach(IncidentWords.types, id: \.self) { value in
                                Button { type = value; form.clear("type") } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: IncidentWords.typeIcon(value)).font(.system(size: 14, weight: .bold))
                                        Text(IncidentWords.type(value)).font(Theme.text(14, weight: .bold)).lineLimit(2).multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }
                                    .foregroundStyle(type == value ? Theme.inkStrong : Theme.inkSoft)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                    .background(type == value ? Theme.pink.opacity(0.18) : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(type == value ? Theme.pink : Theme.borderSoft, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                ModalSection(title: L("How serious")) {
                    VStack(spacing: 8) {
                        ForEach(IncidentWords.severities, id: \.self) { value in
                            let state = IncidentWords.state(value)
                            Button { severity = value } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Circle().fill(state.color).frame(width: 10, height: 10)
                                        Text(IncidentWords.severity(value)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                                    }
                                    Text(IncidentWords.severityHint(value)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(severity == value ? state.color.opacity(0.14) : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(severity == value ? state.color : Theme.borderSoft, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                DateTimeField(label: L("When it happened"), date: $occurredAt, max: Date().addingTimeInterval(300), key: "occurredAt", form: form)
                if pets.count > 1 {
                    FormField(label: L("Which pet")) {
                        FlowLayout(spacing: 8) {
                            FilterChip(title: L("All of them"), isSelected: petId == nil) { petId = nil }
                            ForEach(pets) { pet in FilterChip(title: pet.name, isSelected: petId == pet.id) { petId = pet.id } }
                        }
                    }
                }
                PMTextField(L("What happened"), text: $whatHappened, key: "whatHappened", form: form,
                            prompt: petName.map { LF("e.g. During group play %@ was nipped on the left ear by another dog.", $0) } ?? L("e.g. During group play the dog was nipped on the left ear by another dog."),
                            hint: L("The family reads this. Say it plainly and calmly."), multiline: true)
                PMTextField(L("What you did"), text: $actionsTaken, prompt: L("e.g. Separated them, cleaned the wound and the vet checked it. We will watch it tonight."), optional: true, multiline: true)
                PMTextField(L("Who was involved or there"), text: $involved, prompt: L("e.g. Ana (walker), another guest: Rocky"), hint: L("For your team only."), optional: true)
                ModalSection(title: L("Photos"), subtitle: L("Up to 6. They go to the family with the report.")) {
                    FormField(label: "", key: "photos", form: form) {
                        VStack(alignment: .leading, spacing: 10) {
                            if !photos.isEmpty {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                                    ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                                        ZStack(alignment: .topTrailing) {
                                            if let image = UIImage(data: data) {
                                                Image(uiImage: image).resizable().scaledToFill().frame(height: 84).frame(maxWidth: .infinity).clipped()
                                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            }
                                            IconCircleButton(systemImage: "xmark", label: L("Remove photo")) { photos.remove(at: index) }.padding(4)
                                        }
                                    }
                                }
                            }
                            if photos.count < IncidentWords.photoMax {
                                PhotosPicker(selection: $pickerItems, maxSelectionCount: IncidentWords.photoMax - photos.count, matching: .images) {
                                    Label(L("Add photos"), systemImage: "camera.fill")
                                }
                                .buttonStyle(.pm(.outline, size: .compact))
                            }
                        }
                    }
                }
            }
            .disabled(confirming || working)
            .opacity(confirming ? 0.6 : 1)
        }
        .onAppear { if petId == nil { petId = pets.count == 1 ? pets.first?.id : (initialPetId.flatMap { id in pets.contains { $0.id == id } ? id : nil }) } }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            Task {
                for item in items {
                    if photos.count >= IncidentWords.photoMax { break }
                    if let jpeg = await ImageUpload.load(item) { photos.append(jpeg) }
                }
                form.clear("photos")
            }
        }
    }

    private func review() {
        let text = whatHappened.trimmingCharacters(in: .whitespacesAndNewlines)
        guard form.check([
            ("type", type == nil ? L("Choose what kind of incident it was.") : nil),
            ("occurredAt", occurredAt > Date().addingTimeInterval(300) ? L("It can’t be in the future.") : nil),
            ("whatHappened", text.count < 3 ? L("Say what happened.") : nil),
            ("photos", photos.count > IncidentWords.photoMax ? L("Up to 6 photos.") : nil),
        ]) else { return }
        confirming = true
    }

    private func send() {
        guard let type else { confirming = false; return }
        var fields: [(String, String)] = act.fields
        if pets.count > 1, let petId { fields.append(("providerClientPetId", petId)) }
        fields += [("type", type), ("severity", severity), ("occurredAt", DateText.iso(occurredAt)),
                   ("whatHappened", whatHappened.trimmingCharacters(in: .whitespacesAndNewlines))]
        if let actions = actionsTaken.nonEmpty { fields.append(("actionsTaken", actions)) }
        if let people = involved.nonEmpty { fields.append(("involved", people)) }
        let files = photos.enumerated().map { API.UploadFile(field: "photos", fileName: "photo-\($0.offset + 1).jpg", mimeType: "image/jpeg", data: $0.element) }
        let parts = fields
        working = true
        Task {
            defer { working = false }
            do {
                let created: IncidentRecorded = try await API.multipart("/provider-incidents", fields: parts, files: files)
                Toast.show((created.notified?.family ?? 0) > 0 ? L("Incident recorded. The family and the owners were told.") : L("Incident recorded. The owners were told."))
                if let failed = created.photoErrors, failed > 0 { Toast.error(LF("%d photos didn’t upload. Add them again from the incident.", failed)) }
                announceDataChanged()
                onRecorded()
                dismiss()
            } catch {
                confirming = false
                form.apply(APIError(status: (error as? APIError)?.status ?? 400, message: IncidentWords.error(error, fallback: "Could not record the incident. Try again."),
                                    code: (error as? APIError)?.code, fields: (error as? APIError)?.fields ?? [:]),
                           known: ["type": "type", "whatHappened": "whatHappened", "occurredAt": "occurredAt"])
            }
        }
    }
}

// MARK: - Close the follow-up

/// Closing the follow-up: how it ended, in words the family will read.
struct IncidentResolveSheet: View {
    let incident: Incident

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var note = ""
    @State private var working = false

    var body: some View {
        ProviderModal(
            title: L("Close the follow-up"),
            subtitle: incident.familyVisible == true ? L("The family reads this note: how the pet is and what comes next, if anything.") : L("A note for your team about how it ended."),
            systemImage: "checkmark.seal.fill",
            accent: .mint,
            isDirty: !note.isEmpty,
            form: form,
            primaryTitle: incident.familyVisible == true ? L("Close and tell the family") : L("Close the follow-up"),
            isWorking: working,
            onPrimary: submit
        ) {
            PMTextField(L("How it ended"), text: $note, key: "note", form: form, prompt: L("e.g. The scratch healed well. No treatment needed; we checked it at pickup."), multiline: true)
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard form.check([("note", text.count < 3 ? L("Write how it was resolved.") : nil)]) else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let _: Incident = try await API.post("/provider-incidents/\(incident.id)/resolve", body: ["note": text])
                Toast.show(incident.familyVisible == true ? L("Closed. The family was told how it ended.") : L("Closed."))
                announceDataChanged()
                dismiss()
            } catch {
                _ = form.check([("note", IncidentWords.error(error, fallback: "Could not close it. Try again."))])
            }
        }
    }
}
