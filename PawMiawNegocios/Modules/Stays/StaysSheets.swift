//
//  StaysSheets.swift
//  PawMiawNegocios
//
//  A stay's smaller sheets: its dates (web stay-dates-sheet.tsx), the report
//  card to the family (stay-report-card-sheet.tsx), and the care plan with
//  its editor (care-plan-sheet.tsx, care-plan-editor.tsx).
//

import PhotosUI
import SwiftUI

// MARK: - Dates

/// Extend, shorten or move a stay. Before the pet comes both ends move; once
/// it is in, only the day it leaves, from today on. The server checks the
/// room and the pet are free and tells the family.
struct StaysDatesSheet: View {
    let stay: StaysStay
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var checkInDay = ""
    @State private var checkOutDay = ""
    @State private var checkInTime = ""
    @State private var checkOutTime = ""
    @State private var working = false

    private var inHouse: Bool { stay.status == "checked_in" }
    private var today: String { stay.today ?? StaysDay.today() }
    private var end: String { stay.isDaycare ? checkInDay : checkOutDay }
    private var nights: Int { StaysDay.nights(kind: stay.kind, from: checkInDay, to: end) }
    private var before: Int { StaysDay.nights(kind: stay.kind, from: stay.checkInDay, to: stay.checkOutDay) }
    private var changed: Bool {
        checkInDay != stay.checkInDay || end != stay.checkOutDay || checkInTime != (stay.checkInTime ?? "") || checkOutTime != (stay.checkOutTime ?? "")
    }

    var body: some View {
        ProviderModal(title: inHouse ? L("Extend or shorten the stay") : L("Change the dates"),
                      subtitle: "\(stay.petNames) · \(stay.clientName ?? "")", systemImage: "calendar-range", accent: .aqua,
                      isDirty: changed, form: form, primaryTitle: L("Save the dates"), isWorking: working,
                      primaryIcon: "calendar-range", primaryDisabled: !changed, footerSummary: AnyView(nightsSummary), onPrimary: save) {
            ModalSection(title: L("When")) {
                if inHouse {
                    Text(LF("Arrived %@. The room stays held to the new day, if it is free.", StaysDay.short(stay.checkInDay)))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    DayField(label: L("Leaving on"), day: $checkOutDay, min: today, key: "dates", form: form)
                } else {
                    DayField(label: stay.isDaycare ? L("Day") : L("Check-in"), day: $checkInDay,
                                  min: min(today, stay.checkInDay), key: "dates", form: form)
                    if !stay.isDaycare {
                        DayField(label: L("Check-out"), day: $checkOutDay, min: checkInDay)
                    }
                    TimeField(label: L("Arrival time"), value: $checkInTime)
                }
                TimeField(label: L("Pickup time"), value: $checkOutTime)
            }
        }
        .onAppear {
            guard checkInDay.isEmpty else { return }
            // A pet still here past its day: the sheet starts from today, the earliest it can now leave.
            checkInDay = stay.checkInDay
            checkOutDay = inHouse && stay.checkOutDay < today ? today : stay.checkOutDay
            checkInTime = stay.checkInTime ?? ""
            checkOutTime = stay.checkOutTime ?? ""
        }
    }

    /// The web footer's line: what the new dates cost, and the nights before and now.
    private var nightsSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stay.rate > 0 ? Money.format(nights * stay.rate * stay.petCount, currency: stay.stayCurrency) : StaysWords.units(stay.kind, nights))
                .font(.brandHeading(24)).foregroundStyle(Theme.inkStrong)
            Text(nights == before ? StaysWords.units(stay.kind, nights) : LF("%@ before, %@ now", StaysWords.units(stay.kind, before), StaysWords.units(stay.kind, nights)))
                .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
        }
    }

    private var problem: String? {
        if end < today { return inHouse ? L("The pet is still here: choose today or a later day, or check it out.") : L("Choose days from today on.") }
        // Not in yet: a past arrival day can stay as booked (only the end moves), never move to another past day.
        if !inHouse && checkInDay != stay.checkInDay && checkInDay < today { return L("Choose days from today on.") }
        if !stay.isDaycare && end <= checkInDay { return L("Check-out must be at least one night after check-in.") }
        return nil
    }

    private func save() {
        guard form.check([("dates", problem)]) else { return }
        working = true
        Task {
            defer { working = false }
            let body: [String: Any?] = inHouse
                ? ["checkOutDay": end, "checkOutTime": checkOutTime]
                : ["checkInDay": checkInDay, "checkOutDay": end, "checkInTime": checkInTime, "checkOutTime": checkOutTime]
            do {
                let _: StaysStay = try await API.patch("/provider-stays/\(stay.id)", body: body)
                Toast.show(stay.familyOnApp ? L("Dates changed. The family has been told.") : L("Dates changed."))
                announceDataChanged()
                onDone()
                dismiss()
            } catch {
                form.errors = ["dates": errorText(error, fallback: L("Could not change this stay."))]
                Toast.error(error, fallback: L("Could not change this stay."))
            }
        }
    }
}

// MARK: - Report card

/// The report card: a photo, a mood and a line, straight to the owner's app.
/// Only a family on PawMiaw receives it; otherwise it stays on the stay.
struct StaysReportCardSheet: View {
    let stayId: String
    /// The stay's pets (id = the stay pet's id).
    let pets: [StaysPet]
    /// Whether the family is on PawMiaw; nil reads the stay first.
    var familyOnApp: Bool?
    var initialPetId: String? = nil
    /// A home stay's visit it is written at (docs/homestays.md).
    var visitId: String? = nil
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var petId: String?
    @State private var mood: String?
    @State private var message = ""
    @State private var photo = PhotoDraft()
    @State private var known: StaysStay?
    @State private var working = false
    @State private var recordingIncident = false
    @State private var incidentSent = false

    private var onApp: Bool? {
        if let known { return known.petList.contains { ($0.id == petId || petId == nil) && $0.linkedToHousehold == true } }
        guard let familyOnApp else { return nil }
        if let petId, let pet = pets.first(where: { $0.id == petId }), let linked = pet.linkedToHousehold { return linked }
        return familyOnApp
    }

    private var petName: String {
        pets.first { $0.id == petId }?.petName ?? pets.map(\.petName).joined(separator: ", ")
    }

    var body: some View {
        ProviderModal(title: L("Report card"),
                      subtitle: onApp.map { $0 ? L("Goes to the family in their PawMiaw app, with a notification.") : L("The family isn’t on PawMiaw: the report card stays on the stay.") },
                      systemImage: "send", accent: .aqua, isDirty: !message.isEmpty || photo.data != nil, form: form,
                      primaryTitle: onApp == false ? L("Save the report card") : L("Send to the family"), isWorking: working, primaryIcon: "send", onPrimary: send) {
            // Something went wrong is an incident, not a report card: its own sheet tells the family and the owners properly.
            Button { recordingIncident = true } label: {
                HStack(spacing: 12) {
                    Glyph("shield-alert", size: 20).foregroundStyle(Theme.pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Something happened? Record an incident")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        Text(L("A bite, an injury, an escape: with how serious it was and what you did.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous)
                    .strokeBorder(Theme.mix(Theme.pink, 55, with: Theme.borderSoft), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if pets.count > 1 {
                ModalSection(title: L("About")) {
                    FlowLayout(spacing: 8) {
                        FilterChip(title: L("Everyone"), isSelected: petId == nil) { petId = nil }
                        ForEach(pets) { pet in
                            FilterChip(title: pet.petName, isSelected: petId == pet.id) { petId = pet.id }
                        }
                    }
                }
            }
            ModalSection(title: L("How was the day?")) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(StaysWords.moods, id: \.value) { option in
                        let chosen = mood == option.value
                        Button { mood = chosen ? nil : option.value } label: {
                            VStack(spacing: 4) {
                                Text(option.emoji).font(.system(size: 24))
                                Text(L(option.label)).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(chosen ? AnyShapeStyle(Theme.wash(Theme.lime, 30)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(chosen ? Theme.blue : Theme.borderSoft, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
            }
            ModalSection(title: L("A line for the family")) {
                StaysPlainField(prompt: LF("e.g. %@ played ball all afternoon and ate everything", petName.isEmpty ? L("Luna") : petName),
                                text: $message, key: "message", form: form, multiline: true)
            }
            ModalSection(title: L("Photo")) {
                PhotoField(label: L("Photo"), hint: L("Owners love seeing their pet mid-stay."), draft: $photo, allowsRemove: false)
            }
        }
        .onAppear { if petId == nil { petId = initialPetId ?? (pets.count == 1 ? pets.first?.id : nil) } }
        .task {
            if familyOnApp == nil { known = try? await API.get("/provider-stays/\(stayId)") }
        }
        // Over the report card (it stays open behind); both close once the incident is sent.
        .sheet(isPresented: $recordingIncident, onDismiss: { if incidentSent { onDone(); dismiss() } }) {
            let stayPets = known?.petList ?? pets
            IncidentRecordSheet(
                act: ConsentAct(stayId: stayId),
                pets: stayPets.compactMap { pet in pet.providerClientPetId.map { ActPet(id: $0, name: pet.petName) } },
                familyName: known?.clientName,
                initialPetId: stayPets.first { $0.id == petId }?.providerClientPetId
            ) { incidentSent = true }
        }
    }

    private func send() {
        guard form.check([("message", message.nonEmpty == nil ? L("Write a line for the owner.") : nil)]) else { return }
        working = true
        Task {
            defer { working = false }
            var fields: [String: String] = ["kind": "report", "visibility": "owner", "message": message.trimmingCharacters(in: .whitespacesAndNewlines)]
            if let petId { fields["stayPetId"] = petId }
            if let mood { fields["mood"] = mood }
            if let visitId { fields["visitId"] = visitId }
            do {
                let _: StaysUpdate = try await API.multipart("/provider-stays/\(stayId)/updates", fields: fields.sorted { $0.key < $1.key }.map { ($0.key, $0.value) },
                                                             files: photo.data.map { [API.UploadFile(field: "photo", fileName: "photo.jpg", mimeType: "image/jpeg", data: $0)] } ?? [])
                switch onApp {
                case .none: Toast.show(L("Report card saved."))
                case .some(true): Toast.show(LF("Report card sent to %@’s family.", petName))
                case .some(false): Toast.show(LF("Report card saved on the stay. %@’s family isn’t on PawMiaw, so it wasn’t sent.", petName))
                }
                announceDataChanged()
                onDone()
                dismiss()
            } catch {
                Toast.error(error, fallback: L("Could not send this."))
            }
        }
    }
}

// MARK: - Care plan

/// Change each pet's care plan once the stay is booked or running: a medicine
/// the vet just prescribed, another meal. Boarding and daycare save to the
/// stay; a home stay to its visits.
struct StaysCarePlanSheet: View {
    let stay: StaysStay
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var intake: StaysIntake?
    @State private var drafts: [StaysPlanDraft] = []
    @State private var loaded = false
    @State private var working = false

    var body: some View {
        ProviderModal(title: L("Edit the care plan"), subtitle: stay.petNames, systemImage: "clipboard-list", accent: .aqua,
                      isDirty: loaded, primaryTitle: L("Save the plan"), isWorking: working,
                      primaryIcon: "clipboard-list", primaryDisabled: drafts.isEmpty, onPrimary: save) {
            if !loaded {
                LoadingState()
            }
            ForEach(drafts.indices, id: \.self) { index in
                let draft = drafts[index]
                let pet = stay.petList.first { $0.id == draft.id }
                let known = intake?.pets?.first { $0.stayPetId == draft.id }
                Card(padding: 20, spacing: 16, flat: true) {
                    Text(pet?.petName ?? "").font(.brandHeading(24)).foregroundStyle(Theme.inkStrong)
                    StaysAllergies(allergies: known?.allergies ?? [])
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Care plan")).font(.brandHeading(16.8)).foregroundStyle(Theme.inkStrong)
                            Text(L("Medicines from your records and the owner’s routines are suggested below.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        }
                        StaysCarePlanEditor(items: $drafts[index].items, notes: $drafts[index].notes, suggestions: known?.suggestedCare ?? [])
                    }
                }
            }
        }
        .task {
            guard !loaded else { return }
            drafts = stay.petList.map { StaysPlanDraft(id: $0.id, items: $0.carePlan?.items ?? [], notes: $0.carePlan?.notes ?? "") }
            intake = try? await API.get("/provider-stays/\(stay.id)/intake")
            loaded = true
        }
    }

    private func save() {
        working = true
        Task {
            defer { working = false }
            let pets: [[String: Any?]] = drafts.map { ["stayPetId": $0.id, "carePlan": StaysCarePlanEditor.clean($0.items, $0.notes)] }
            do {
                let path = stay.isHome ? "/provider-homestays/\(stay.id)/care" : "/provider-stays/\(stay.id)/care"
                try await API.send("PUT", path, body: ["pets": pets])
                Toast.show(stay.isHome ? L("Care plan saved.") : L("Care plan saved. New care shows on the day’s board."))
                announceDataChanged()
                onDone()
                dismiss()
            } catch {
                Toast.error(error, fallback: L("Could not save the care plan."))
            }
        }
    }
}

private struct StaysPlanDraft: Identifiable {
    let id: String
    var items: [StaysCareItem]
    var notes: String
}

/// A pet's care plan, item by item (what, at what time), with the suggestions
/// not yet in it — the owner's routines and the medicines on the clinic's
/// chart — and the usual ones a tap away.
struct StaysCarePlanEditor: View {
    @Binding var items: [StaysCareItem]
    @Binding var notes: String
    var suggestions: [StaysCareItem] = []

    private static let quickAdd: [(kind: String, label: String, time: String?)] = [
        ("meal", "Breakfast", "08:00"), ("meal", "Dinner", "18:00"), ("walk", "Walk", "10:00"), ("play", "Group play", "15:00"), ("medication", "Medicine", nil),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 8) {
                ForEach($items) { $item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Menu {
                                ForEach(StaysWords.taskKinds, id: \.self) { kind in
                                    Button { item.kind = kind } label: { GlyphLabel(StaysWords.task(kind), icon: StaysWords.taskIcon(kind)) }
                                }
                            } label: {
                                Glyph(StaysWords.taskIcon(item.kind), size: 16).foregroundStyle(Theme.blue)
                                    .frame(width: 36, height: 36)
                                    .background(Theme.surface, in: Circle())
                                    .overlay(Circle().strokeBorder(Theme.borderSoft, lineWidth: 1))
                            }
                            .accessibilityLabel(L("Kind"))
                            TextField(L("What"), text: $item.label).fieldChrome()
                            IconCircleButton(systemImage: "trash-2", label: L("Remove"), tint: Theme.inkSoft) {
                                items.removeAll { $0.key == item.key }
                            }
                        }
                        TimeField(label: L("Time"), value: Binding(get: { item.time ?? "" }, set: { item.time = $0.isEmpty ? nil : $0 }),
                                  from: "00:00", to: "23:45", allowsEmpty: true)
                    }
                    .padding(8)
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
            }
            FlowLayout(spacing: 8) {
                ForEach(suggestions.filter { suggestion in !items.contains { $0.key == suggestion.key } }) { item in
                    FilterChip(title: item.label + (item.time.map { " · " + StaysDay.clock($0) } ?? ""), isSelected: false, tone: Theme.lime,
                               icon: item.source == "clinic_record" ? "pill" : "sparkles") { items.append(item) }
                }
                ForEach(Self.quickAdd, id: \.label) { quick in
                    FilterChip(title: L(quick.label) + (quick.time.map { " · " + StaysDay.clock($0) } ?? ""), isSelected: false, icon: "plus") {
                        items.append(StaysCareItem(key: "desk:\(UUID().uuidString)", kind: quick.kind, label: L(quick.label), time: quick.time, source: "front_desk"))
                    }
                }
            }
            PMTextField(L("Anything else the team should know"), text: $notes, prompt: L("e.g. Loves tennis balls, eats slowly, pulls on the leash"), multiline: true)
        }
    }

    /// A plan to save: items with a name, trimmed; notes or nothing.
    static func clean(_ items: [StaysCareItem], _ notes: String) -> [String: Any?] {
        let kept = items.compactMap { item -> [String: Any?]? in
            guard let label = item.label.nonEmpty else { return nil }
            var copy = item
            copy.label = label
            return copy.body
        }
        return ["items": kept, "notes": notes.nonEmpty]
    }
}
