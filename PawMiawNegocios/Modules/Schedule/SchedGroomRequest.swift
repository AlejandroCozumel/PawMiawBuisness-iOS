//
//  SchedGroomRequest.swift
//  PawMiawNegocios
//
//  "Lo que pidió el dueño" on the business side (web care/groom-request-staff.tsx,
//  groom-request-fields.tsx, lib/groom-request.ts): the booking sheet's
//  section (one request per pet booked, "same as last time" first when there
//  is an earlier groom), the visit page's "Today's request" card with the
//  extras on the bill against what the owner authorized, and its edit sheet.
//

import SwiftUI
import PhotosUI

// MARK: - Words

enum SchedGroomWords {
    static let areas = ["face", "feet", "tail", "body", "sanitary"]
    static let extras = ["dematting", "flea_bath", "deshedding", "teeth", "glands"]
    static let photoLimit = 3

    static func style(_ value: String) -> String {
        switch value {
        case "puppy": L("Puppy cut")
        case "shave": L("Shave")
        case "breed": L("Breed standard")
        case "tidy": L("Just a tidy")
        default: L("Other")
        }
    }

    static func area(_ value: String) -> String {
        switch value {
        case "face": L("Face")
        case "feet": L("Feet")
        case "tail": L("Tail")
        case "body": L("Body")
        default: L("Sanitary area")
        }
    }

    static func service(_ value: String) -> String { SvcReportText.option(value) }

    /// "Puppy cut — round ears", or the free text alone.
    static func cut(_ style: String?, _ text: String?) -> String? {
        let label = style.flatMap { $0 == "other" ? nil : Self.style($0) }
        let detail = text?.nonEmpty
        if let label, let detail, detail.lowercased().hasPrefix(label.lowercased()) { return detail }
        if let label, let detail { return "\(label) — \(detail)" }
        return label ?? detail
    }

    /// What to do, with "same as last time" filled in (the server's `effectiveRequest`).
    static func wanted(_ input: SchedGroomInput, last: SchedGroomLastTime?) -> SchedGroomWanted {
        let previous = input.sameAsLastTime ? last : nil
        let services = SvcReportText.groomServices.filter { input.services.contains($0) || (previous?.services ?? []).contains($0) }
        return SchedGroomWanted(
            services: services,
            style: input.style ?? previous?.style,
            styleText: input.styleText.nonEmpty ?? (previous.flatMap { $0.styleText ?? $0.careStyle }),
            length: input.length.nonEmpty ?? (previous.flatMap { $0.length ?? $0.careTools })
        )
    }

    static func rows(_ wanted: SchedGroomWanted, areas: [String], note: String?) -> [(label: String, value: String)] {
        var rows: [(String, String)] = []
        let services = wanted.services ?? []
        if !services.isEmpty { rows.append((L("Services"), services.map(service).joined(separator: ", "))) }
        if let cut = cut(wanted.style, wanted.styleText) { rows.append((L("Cut"), cut)) }
        if let length = wanted.length?.nonEmpty { rows.append((L("Length"), length)) }
        if !areas.isEmpty { rows.append((L("Areas"), areas.map(area).joined(separator: ", "))) }
        if let note = note?.nonEmpty { rows.append((L("Note"), note)) }
        return rows.map { (label: $0.0, value: $0.1) }
    }

    static func extrasText(cents: Int?, extras: [String], currency: String?) -> String? {
        guard let cents, cents > 0 else { return nil }
        let amount = Money.format(cents, currency: currency)
        let which = extras.map(service).joined(separator: ", ")
        return which.isEmpty ? LF("Up to %@ in extras", amount) : LF("Up to %@ for %@", amount, which)
    }

    static func byline(_ request: SchedGroomRequest) -> String {
        let who = request.setBy?.side == "family" ? L("Set by the owner") : LF("Set by %@", request.setBy?.name ?? L("the team"))
        if let checkIn = request.checkIn {
            return "\(who) · \(LF("Changed at check-in by %@ at %@", checkIn.name ?? L("the team"), DateText.time(checkIn.at)))"
        }
        return who
    }

    static func lastTimeLine(_ last: SchedGroomLastTime) -> String {
        var input = SchedGroomInput()
        input.sameAsLastTime = true
        let wanted = wanted(input, last: last)
        return [(wanted.services ?? []).map(service).joined(separator: ", ").nonEmpty, cut(wanted.style, wanted.styleText), wanted.length?.nonEmpty]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// A refusal from the request's endpoints, in words.
    static func refusal(_ error: Error) -> String { errorText(schedAPIError(error)) }
}

// MARK: - The form

/// What to do ("same as last time" or services, cut, length), the areas, reference photos and a note;
/// then the extras the owner authorizes and when they come back for the pet.
struct SchedGroomRequestFields: View {
    @Binding var value: SchedGroomInput
    let lastTime: SchedGroomLastTime?
    let currency: String?
    var disabled = false

    @State private var photo: PhotosPickerItem?
    @State private var uploading = false

    private var hasLast: Bool { lastTime?.exists ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FormField(label: L("What should the groomer do?")) {
                // The web's mode cards: each with its icon; "same" can't be chosen before a first groom.
                OptionCards(options: [
                    OptionCard(true, title: L("Same as last time"), description: hasLast ? lastHint : nil, icon: "history", accent: Theme.aqua,
                               unavailableReason: hasLast ? nil : L("No earlier groom yet — choose what they should do.")),
                    OptionCard(false, title: L("Something different"), description: L("Choose the services, the cut and the length."), icon: "pen-line", accent: Theme.aqua),
                ], selection: Binding(get: { value.sameAsLastTime && hasLast }, set: { same in
                    guard same != value.sameAsLastTime else { return }
                    if same && hasLast {
                        value.sameAsLastTime = true
                        value.services = []
                        value.style = nil
                        value.styleText = ""
                        value.length = ""
                    } else {
                        value.sameAsLastTime = false
                    }
                }))
                .disabled(disabled)
            }
            if value.sameAsLastTime && hasLast, let lastTime {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lastHint).font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
                    Text(SchedGroomWords.lastTimeLine(lastTime).nonEmpty ?? L("Their usual cut")).font(Theme.bodyFont).foregroundStyle(Theme.inkStrong)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(Theme.aqua, 14), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            } else {
                FormField(label: L("Services")) {
                    pills(SvcReportText.groomServices, selected: value.services, label: SchedGroomWords.service) { toggle(&value.services, $0) }
                }
                FormField(label: L("Style")) {
                    pills(SvcReportText.styles, selected: value.style.map { [$0] } ?? [], label: SchedGroomWords.style) { value.style = value.style == $0 ? nil : $0 }
                    TextField(L("e.g. round ears, leave the tail long"), text: $value.styleText).font(Theme.bodyFont).fieldChrome().disabled(disabled)
                }
                PMTextField(L("Length"), text: $value.length, prompt: L("Blade number or cm, e.g. #7 or 2 cm"), optional: true).disabled(disabled)
            }
            FormField(label: L("Areas")) {
                pills(SchedGroomWords.areas, selected: value.areas, label: SchedGroomWords.area) { toggle(&value.areas, $0) }
            }
            FormField(label: L("Reference photo")) { photos }
            PMTextField(L("Note"), text: $value.note, prompt: L("Anything else the groomer should know"), optional: true, multiline: true).disabled(disabled)
            extrasFields
        }
        .onChange(of: photo) { _, picked in
            guard let picked else { return }
            Task { await upload(picked) }
        }
    }

    private var lastHint: String {
        guard let at = lastTime?.at else { return L("Their usual cut") }
        return LF("Last time (%@)", DateText.date(at))
    }

    private var extrasFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) { Glyph("banknote", size: 16); Text(L("Extras the owner authorizes")) }.font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.inkStrong)
                Text(L("The groomer can add these without calling, up to this amount.")).font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
                MoneyField(label: L("Up to"), cents: $value.extrasUpToCents, optional: true).disabled(disabled)
                pills(SchedGroomWords.extras, selected: value.extras, label: SchedGroomWords.service) { toggle(&value.extras, $0) }
            }
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            MenuField(label: L("Pickup time"), options: [(nil, L("No pickup time"))] + stride(from: 7 * 60, through: 21 * 60, by: 15).map { (Optional($0), SchedDay.timeLabel($0)) },
                      selection: $value.pickupMinute, optional: true)
                .disabled(disabled)
        }
    }

    @ViewBuilder private var photos: some View {
        FlowLayout(spacing: 8) {
            ForEach(value.photoUrls, id: \.self) { url in
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: APIConfig.assetURL(url)) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { Theme.surfaceMuted }
                    }
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                    if !disabled {
                        IconCircleButton(systemImage: "x", label: L("Remove photo"), tint: Theme.destructive) { value.photoUrls.removeAll { $0 == url } }
                            .scaleEffect(0.8)
                    }
                }
            }
            if !disabled && value.photoUrls.count < SchedGroomWords.photoLimit {
                PhotosPicker(selection: $photo, matching: .images) {
                    VStack(spacing: 4) {
                        if uploading { ProgressView() } else { Glyph("camera", size: 20) }
                        Text(L("Add a photo")).font(Theme.text(11, weight: .bold))
                    }
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 76, height: 76)
                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                }
                .disabled(uploading)
            }
        }
    }

    private func pills(_ options: [String], selected: [String], label: @escaping (String) -> String, toggle: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(options, id: \.self) { option in
                FilterChip(title: label(option), isSelected: selected.contains(option)) { toggle(option) }
            }
        }
        .disabled(disabled)
    }

    private func toggle(_ list: inout [String], _ item: String) {
        if list.contains(item) { list.removeAll { $0 == item } } else { list.append(item) }
    }

    private func upload(_ picked: PhotosPickerItem) async {
        uploading = true
        defer { uploading = false; photo = nil }
        do {
            guard let jpeg = await ImageUpload.load(picked) else { return }
            struct Uploaded: Decodable { let url: String }
            let result: Uploaded = try await ImageUpload.upload(jpeg, to: "/provider-groom-requests/photo")
            // A photo lands after the upload: added to the request as it is now.
            if value.photoUrls.count < SchedGroomWords.photoLimit { value.photoUrls.append(result.url) }
        } catch {
            Toast.error(L("The photo did not upload. Try again."))
        }
    }
}

/// The request read back: the rows, the reference photos, the extras and pickup, who set it.
struct SchedGroomSummary: View {
    let rows: [(label: String, value: String)]
    let photoUrls: [String]
    let extras: String?
    let pickup: String?
    let byline: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.label).font(Theme.text(13, weight: .bold)).foregroundStyle(Theme.inkSoft).frame(width: 84, alignment: .leading)
                    Text(row.value).font(Theme.text(15)).foregroundStyle(Theme.inkStrong)
                    Spacer(minLength: 0)
                }
            }
            if !photoUrls.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(photoUrls, id: \.self) { url in
                        AsyncImage(url: APIConfig.assetURL(url)) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() } else { Theme.surfaceMuted }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                        .accessibilityLabel(L("Reference photo"))
                    }
                }
            }
            if extras != nil || pickup != nil {
                FlowLayout(spacing: 6) {
                    if let extras { Chip(text: extras, icon: "banknote") }
                    if let pickup { Chip(text: LF("Pick up at %@", pickup), icon: "clock-3") }
                }
            }
            if let byline { Text(byline).font(Theme.captionFont).foregroundStyle(Theme.inkSoft) }
        }
    }
}

// MARK: - The booking sheet's section

/// One request per pet on the booking. A pet with an earlier groom starts on "same as last time";
/// an untouched pet with no history stays empty and isn't sent.
struct SchedBookingGroomRequests: View {
    let pets: [(id: String, name: String)]
    @Binding var values: [String: SchedGroomInput]
    let familyOnApp: Bool

    var body: some View {
        ModalSection(title: L("What the owner asked for"), subtitle: familyOnApp
                     ? L("The groomer sees it on the visit; the family sees it in their app and can change it until the pet arrives.")
                     : L("The groomer sees it on the visit. The family isn’t on PawMiaw: confirm it with them when the pet arrives.")) {
            ForEach(pets, id: \.id) { pet in
                SchedBookingGroomPet(petId: pet.id, name: pets.count > 1 ? pet.name : nil, value: Binding(get: { values[pet.id] }, set: { values[pet.id] = $0 }))
            }
        }
    }

    /// The requests to send: the pets booked now, leaving out any left empty.
    static func payload(_ values: [String: SchedGroomInput], petIds: [String]) -> [[String: Any?]] {
        petIds.compactMap { id in
            guard let value = values[id], !value.isEmpty else { return nil }
            var body = value.body
            body["providerClientPetId"] = id
            return body
        }
    }
}

private struct SchedBookingGroomPet: View {
    let petId: String
    let name: String?
    @Binding var value: SchedGroomInput?
    @State private var care: SchedCareForGroom?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let name { Text(name).font(Theme.text(15, weight: .heavy)).foregroundStyle(Theme.inkStrong) }
            if let current = value {
                SchedGroomRequestFields(value: Binding(get: { current }, set: { value = $0 }), lastTime: care?.lastGroom, currency: care?.currency)
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task(id: petId) {
            care = try? await API.get("/provider-client-pets/\(petId)/care")
            loaded = true
            // Start from the pet's history once it's known ("same as last time" when there is one).
            if value == nil { value = SchedGroomInput.empty(care?.lastGroom) }
        }
    }
}

// MARK: - The visit page

/// "Today's request": what the owner asked for, who set it, and the extras on the bill against what
/// they authorized (over warns, never blocks).
struct SchedGroomRequestCard: View {
    let appointmentId: String
    let petName: String
    let canEdit: Bool

    @State private var view: SchedGroomView?
    @State private var loading = true
    @State private var editing = false

    var body: some View {
        Group {
            if loading && view == nil {
                SectionCard(L("Today's request"), icon: "scissors", accent: Theme.blue) { LoadingState() }
            } else if let view, view.isGroom == true {
                card(view)
            }
        }
        .reloadsOnScope { await load() }
        .sheet(isPresented: $editing) {
            if let view { SchedGroomRequestSheet(view: view, petName: petName) { self.view = $0 } }
        }
    }

    private func card(_ view: SchedGroomView) -> some View {
        let mayEdit = canEdit && view.staffMayEdit == true
        let currency = view.extras?.currency
        return SectionCard(title: L("Today's request"), icon: "scissors", accent: Theme.blue) {
            if mayEdit && view.request != nil {
                PMButton(L("Edit"), systemImage: "pencil", variant: .outline, size: .header) { editing = true }
            }
        } content: {
          VStack(alignment: .leading, spacing: 12) {
            if let request = view.request, let wanted = view.wanted {
                SchedGroomSummary(
                    rows: SchedGroomWords.rows(wanted, areas: request.areas ?? [], note: request.note),
                    photoUrls: request.photoUrls ?? [],
                    extras: SchedGroomWords.extrasText(cents: request.extrasUpToCents, extras: request.extras ?? [], currency: currency),
                    pickup: request.pickupTime.flatMap { SchedHours.startMinutes($0) }.map(SchedDay.timeLabel),
                    byline: SchedGroomWords.byline(request)
                )
                if let extras = view.extras {
                    if extras.status == "over" {
                        NoticeCard(tone: .problem, title: LF("Exceeds what the owner authorized by %@ — call before charging.", Money.format(extras.overByCents, currency: currency)))
                    } else if extras.status == "within" {
                        HStack(spacing: 6) {
                            Glyph("circle-check", size: 14)
                            Text(LF("Extras on the bill: %@ of %@ authorized", Money.format(extras.chargedCents, currency: currency), Money.format(extras.authorizedCents, currency: currency)))
                        }
                        .font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
                    }
                }
            } else {
                Text(L("Nothing asked for yet")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                if mayEdit {
                    PMButton(L("Add what the owner asked for"), systemImage: "plus", variant: .outline, size: .compact) { editing = true }
                }
            }
          }
          .padding(16)
        }
    }

    private func load() async {
        defer { loading = false }
        if let loaded: SchedGroomView = try? await API.get("/provider-appointments/\(appointmentId)/groom-request") { view = loaded }
    }
}

/// The request as a form, in a sheet of its own.
struct SchedGroomRequestSheet: View {
    let view: SchedGroomView
    let petName: String
    var onSaved: (SchedGroomView) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var draft = SchedGroomInput()
    @State private var original = SchedGroomInput()
    @State private var prepared = false
    @State private var working = false

    var body: some View {
        ProviderModal(title: L("What the owner asked for"), subtitle: petName, systemImage: "scissors", accent: .aqua, isDirty: prepared && draft != original, primaryTitle: L("Save"), isWorking: working) {
            save()
        } content: {
            if prepared {
                SchedGroomRequestFields(value: $draft, lastTime: view.lastTime, currency: view.extras?.currency)
            }
        }
        .onAppear {
            guard !prepared else { return }
            draft = SchedGroomInput.from(view.request, last: view.lastTime)
            original = draft
            prepared = true
        }
    }

    private func save() {
        guard !draft.isEmpty else {
            Toast.error(L("Say what they should do, or choose same as last time"))
            return
        }
        let body = draft.body
        working = true
        Task {
            defer { working = false }
            do {
                let saved: SchedGroomView = try await SchedAPI.send("PUT", "/provider-appointments/\(view.appointmentId)/groom-request", body: body)
                onSaved(saved)
                Toast.show(L("Saved"))
                announceDataChanged()
                dismiss()
            } catch {
                Toast.error(SchedGroomWords.refusal(error))
            }
        }
    }
}
