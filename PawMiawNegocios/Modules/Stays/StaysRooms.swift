//
//  StaysRooms.swift
//  PawMiawNegocios
//
//  Rooms & rules (web stays-rooms-settings.tsx): this place's kennels, suites,
//  condos, runs and playrooms — who each is for, how many it holds, its night
//  and daycare rates (a missing one says so), its photo — and the house
//  rules every new stay starts from: check-in and check-out times, daycare
//  hours, and the vaccines checked at check-in.
//

import PhotosUI
import SwiftUI

private struct StaysRoomEditing: Identifiable {
    let unit: StaysUnit?
    var id: String { unit?.id ?? "new" }
}

struct StaysRoomsView: View {
    let canManage: Bool

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var units: [StaysUnit] = []
    @State private var settings: StaysSettings?
    @State private var draft: StaysSettings?
    @State private var loaded = false
    @State private var error: String?
    @State private var editing: StaysRoomEditing?
    @State private var saving = false

    private var active: [StaysUnit] { units.filter { $0.status != "archived" } }
    private var archived: [StaysUnit] { units.filter { $0.status == "archived" } }
    private var currency: String { settings?.currency ?? workspace.currency }

    var body: some View {
        Group {
            if !loaded {
                LoadingState()
            } else if let error {
                ErrorState(message: error) { await load() }
            } else if sizeClass == .regular {
                // Wide: the rooms beside the house rules (web xl grid 1.4fr / 1fr).
                HStack(alignment: .top, spacing: 24) {
                    rooms.frame(maxWidth: .infinity, alignment: .topLeading).layoutPriority(1.4)
                    if draft != nil { houseRules.frame(maxWidth: .infinity, alignment: .topLeading) }
                }
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    rooms
                    if draft != nil { houseRules }
                }
            }
        }
        .reloadsOnScope { await load() }
        .sheet(item: $editing) { item in
            StaysRoomSheet(unit: item.unit, currency: currency, nextSortOrder: units.count, rooms: active) { Task { await load() } }
        }
    }

    // MARK: Rooms

    private var rooms: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconBadge(icon: "bed-double", accent: Theme.aqua, size: 44, iconSize: 20, ink: .strong, washPercent: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Rooms")).font(.brandHeading(24)).foregroundStyle(Theme.inkStrong)
                    Text(L("Each room holds a number of pets a night, at its own rate.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
            if active.isEmpty {
                EmptyState(systemImage: "bed-double", title: L("No rooms yet"),
                           message: L("Add your kennels, suites and cat condos. You can book stays without a room and assign it later."),
                           actionTitle: canManage ? L("Add room") : nil, action: canManage ? { editing = StaysRoomEditing(unit: nil) } : nil,
                           accent: Theme.aqua, panel: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(active) { unit in
                        Button { editing = StaysRoomEditing(unit: unit) } label: { roomCard(unit) }
                            .buttonStyle(.plain)
                            .disabled(!canManage)
                    }
                    if canManage {
                        // One more room, right where it will appear.
                        Button { editing = StaysRoomEditing(unit: nil) } label: {
                            VStack(spacing: 8) {
                                IconBadge(icon: "plus", accent: Theme.aqua, size: 36, iconSize: 16, ink: .strong, washPercent: 35)
                                Text(L("Add room")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            }
                            .frame(maxWidth: .infinity, minHeight: 144)
                            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .strokeBorder(Theme.blue.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !archived.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    StaysEyebrow(text: L("Archived"), tint: Theme.inkSoft)
                    FlowLayout(spacing: 8) {
                        ForEach(archived) { unit in
                            Button { editing = StaysRoomEditing(unit: unit) } label: { Chip(text: unit.name, tone: .muted, icon: "archive") }
                                .buttonStyle(.plain)
                                .disabled(!canManage)
                        }
                    }
                }
            }
        }
    }

    /// Each pet type a room is for, in its own colour (dogs aqua, cats mango, any lime).
    private func speciesTone(_ species: String?) -> Color {
        switch species {
        case "dog": Theme.aqua
        case "cat": Theme.mango
        case "any": Theme.lime
        default: Theme.lavender
        }
    }

    /// A room: what it is and who it's for, how many it holds, and its two rates — a missing one says so.
    private func roomCard(_ unit: StaysUnit) -> some View {
        let tone = speciesTone(unit.species)
        return Card(padding: 0, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // The pet type's colour along the top, like a name tag.
                Rectangle().fill(tone).frame(height: 6)
                if let url = APIConfig.assetURL(unit.photoUrl) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { Theme.surfaceMuted }
                    }
                    .frame(maxWidth: .infinity).frame(height: 120).clipped()
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        IconBadge(icon: unit.species == "dog" ? "dog" : unit.species == "cat" ? "cat" : "paw-print", accent: tone, size: 40, iconSize: 20, ink: .strong, washPercent: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(unit.name).font(.brandHeading(20)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            Text("\(StaysWords.unitKind(unit.kind)) · \(StaysWords.species(unit.species))".uppercased())
                                .font(.brandText(12, weight: .bold)).tracking(12 * 0.12).foregroundStyle(Theme.inkSoft).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if canManage { Chip(text: L("Edit"), tone: .muted, icon: "pencil") }
                    }
                    FlowLayout(spacing: 6) {
                        Chip(text: LP(unit.seats, "%d pet", "%d pets"), tone: .muted, icon: "users-round")
                        if unit.unitKind != "playroom" { rateChip(unit.nightlyRateCents, per: L("/ night"), missing: L("No night rate"), icon: "moon", tone: .info) }
                        rateChip(unit.dayRateCents, per: L("/ day"), missing: L("No daycare rate"), icon: "sun", tone: .good)
                    }
                    if let notes = unit.notes?.nonEmpty { Text(notes).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(2) }
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    /// A rate, or plainly no rate: a stay in this room then asks for its price when it's charged.
    @ViewBuilder
    private func rateChip(_ cents: Int?, per: String, missing: String, icon: String, tone: Chip.Tone) -> some View {
        if let cents, cents > 0 {
            Chip(text: "\(Money.format(cents, currency: currency)) \(per)", tone: tone, icon: icon)
        } else {
            Chip(text: missing, tone: .muted, icon: icon, pending: true)
        }
    }

    // MARK: House rules

    private var houseRules: some View {
        let dirty = draft != settings
        return Card(padding: 0, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    IconBadge(icon: "scroll-text", accent: Theme.butter, size: 44, iconSize: 20, ink: .strong, washPercent: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("House rules")).font(.brandHeading(24)).foregroundStyle(Theme.inkStrong)
                        Text(L("Used for every new stay. Each booking can still change its own times.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(Theme.butter, 22))
                StitchedDivider()
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 12) {
                        ruleTimes(L("Boarding"), "moon", Theme.aqua,
                                  (L("Check-in from"), binding(\.checkInTime)), (L("Check-out by"), binding(\.checkOutTime)))
                        ruleTimes(L("Daycare"), "sun", Theme.butter,
                                  (L("Drop-off from"), binding(\.daycareStartTime)), (L("Pickup by"), binding(\.daycareEndTime)))
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Glyph("shield-check", size: 16).foregroundStyle(Theme.blue)
                            Text(L("Required vaccines")).font(.brandHeading(18)).foregroundStyle(Theme.inkStrong)
                            Spacer(minLength: 8)
                            Chip(text: LF("%d of %d", draft?.requiredVaccines?.count ?? 0, StaysWords.vaccineKeys.count), tone: .muted)
                        }
                        Text(L("Checked at check-in against the pet’s records. A dog is only asked for dog vaccines, a cat for cat ones.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                            ForEach(StaysWords.vaccineKeys, id: \.self) { key in vaccineToggle(key) }
                        }
                    }
                    // Stays charge in the business currency; it is set once, for everything, in Settings.
                    HStack(alignment: .top, spacing: 8) {
                        Glyph("coins", size: 14).padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LF("Rates and stay bills are in %@, the business currency.", currency))
                            if workspace.can(.workspaceEdit) {
                                NavigationLink(value: ProviderRoute.section(.settings)) {
                                    Text(L("Settings → Region and money")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
                .padding(20)
                if canManage {
                    // Saving shows up when there's something to save, with a way back.
                    SaveBar(dirty: dirty, working: saving, saveTitle: L("Save house rules"), onDiscard: { draft = settings }, onSave: { saveRules() })
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    private func binding(_ path: WritableKeyPath<StaysSettings, String?>) -> Binding<String> {
        Binding(get: { draft?[keyPath: path] ?? "" }, set: { draft?[keyPath: path] = $0 })
    }

    /// One kind of stay's two times, in its colour.
    private func ruleTimes(_ title: String, _ icon: String, _ tint: Color, _ first: (String, Binding<String>), _ second: (String, Binding<String>)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                IconBadge(icon: icon, accent: tint, size: 28, iconSize: 16, ink: .strong, washPercent: 45)
                Text(title).font(.brandHeading(18)).foregroundStyle(Theme.inkStrong)
            }
            HStack(alignment: .top, spacing: 12) {
                TimeField(label: first.0, value: first.1, from: "00:00", to: "23:45").disabled(!canManage)
                TimeField(label: second.0, value: second.1, from: "00:00", to: "23:45").disabled(!canManage)
            }
        }
        .padding(14)
        .background(Theme.wash(tint, 10), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(tint, 55, with: Theme.borderSoft), lineWidth: 1.5))
    }

    private func vaccineToggle(_ key: String) -> some View {
        let on = draft?.requiredVaccines?.contains(key) ?? false
        let who = StaysWords.vaccineSpecies(key)
        return Button {
            var list = draft?.requiredVaccines ?? []
            if on { list.removeAll { $0 == key } } else { list.append(key) }
            draft?.requiredVaccines = list
        } label: {
            HStack(spacing: 10) {
                Tick(on: on)
                VStack(alignment: .leading, spacing: 1) {
                    Text(StaysWords.vaccine(key)).font(Theme.text(14, weight: .bold)).foregroundStyle(on ? Theme.inkStrong : Theme.inkSoft).lineLimit(1)
                    HStack(spacing: 4) {
                        Glyph(who == "dog" ? "dog" : who == "cat" ? "cat" : "paw-print", size: 12)
                        Text(who == "both" ? L("all") : who == "dog" ? L("dogs") : L("cats"))
                    }
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(on ? AnyShapeStyle(Theme.wash(Theme.aqua, 16)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(on ? Theme.blue : Theme.borderSoft, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canManage)
    }

    // MARK: Work

    private func load() async {
        do {
            units = try await API.get("/provider-stays/units", query: ["includeArchived": "true", "locationId": workspace.locationId])
            let fresh: StaysSettings = try await API.get("/provider-stays/settings")
            if draft == nil || draft == settings { draft = fresh }
            settings = fresh
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = errorText(error)
        }
        loaded = true
    }

    private func saveRules() {
        guard let draft else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let saved: StaysSettings = try await API.put("/provider-stays/settings", body: [
                    "checkInTime": draft.checkInTime, "checkOutTime": draft.checkOutTime,
                    "daycareStartTime": draft.daycareStartTime, "daycareEndTime": draft.daycareEndTime,
                    "requiredVaccines": draft.requiredVaccines ?? [], "currency": draft.currency ?? currency,
                ])
                settings = saved
                self.draft = saved
                Toast.show(L("Stay settings saved."))
                announceDataChanged()
            } catch {
                Toast.error(error, fallback: L("Could not save the settings."))
            }
        }
    }
}

// MARK: - A room

private struct StaysRoomSheet: View {
    let unit: StaysUnit?
    let currency: String
    let nextSortOrder: Int
    let rooms: [StaysUnit]
    let onSaved: () -> Void

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var name = ""
    @State private var kind = "kennel"
    @State private var species = "dog"
    @State private var capacity = "1"
    @State private var nightly: Int?
    @State private var daily: Int?
    @State private var notes = ""
    @State private var active = true
    @State private var draft = PhotoDraft()
    @State private var shareWithKind = true
    @State private var working = false
    @State private var started = false

    private var hasPhoto: Bool { draft.data != nil || (unit?.photoUrl != nil && !draft.removed) }
    /// Ten identical kennels, one upload: the other rooms of this type still without a photo.
    private var bare: [StaysUnit] {
        rooms.filter { $0.id != unit?.id && $0.unitKind == kind && $0.photoUrl == nil && (unit == nil || $0.locationId == unit?.locationId) }
    }

    var body: some View {
        ProviderModal(title: unit == nil ? L("Add room") : L("Edit room"), subtitle: L("Rooms appear on the board in the order you add them."),
                      systemImage: "bed-double", accent: .aqua, isDirty: started && (name != (unit?.name ?? "") || !draft.isEmpty), form: form,
                      primaryTitle: L("Save room"), isWorking: working, primaryIcon: "save", onPrimary: save) {
            PMTextField(L("Name"), text: $name, key: "name", form: form, prompt: L("e.g. Suite 1, Kennel A"))
            MenuField(label: L("Type"), options: StaysWords.unitKinds.map { (value: $0, title: StaysWords.unitKind($0)) }, selection: $kind)
            MenuField(label: L("For"), options: StaysWords.speciesKeys.map { (value: $0, title: StaysWords.species($0)) }, selection: $species)
            PMTextField(kind == "playroom" ? L("Pets at a time") : L("Pets per night"),
                        text: Binding(get: { capacity }, set: { capacity = $0.filter(\.isNumber) }), keyboard: .numberPad)
            if kind == "playroom" {
                Text(L("A playroom is for daycare: it doesn’t take nights.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            } else {
                MoneyField(label: LF("Per pet per night (%@)", currency), cents: $nightly)
            }
            MoneyField(label: LF("Per pet per daycare day (%@)", currency), cents: $daily)
            Text(L("Leave a rate empty if this room doesn’t offer it: a stay here asks for its price (or a courtesy) when it’s charged."))
                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            PMTextField(L("Notes"), text: $notes, prompt: L("e.g. Heated floor, garden view, for dogs under 15 kg"), multiline: true)
            PhotoField(label: L("Photo"), hint: L("The room as a family would see it: the bed, the space, the view. Optional."),
                       currentURL: unit?.photoUrl, draft: $draft, optional: false, removedNote: L("The photo is removed when you save."))
            if hasPhoto && !bare.isEmpty {
                ToggleRow(title: bare.count == 1 ? L("Also use it for the other room of this type") : LF("Also use it for the %d other rooms of this type", bare.count),
                          subtitle: L("Only the ones without a photo: rooms that have their own keep it."), isOn: $shareWithKind)
            }
            if unit != nil {
                ToggleRow(title: L("In use"), subtitle: L("Archived rooms leave the board and cannot be booked. Past stays keep them."), isOn: $active)
            }
        }
        .onAppear {
            guard !started else { return }
            name = unit?.name ?? ""
            kind = unit?.unitKind ?? "kennel"
            species = unit?.species ?? "dog"
            capacity = String(unit?.seats ?? 1)
            nightly = (unit?.nightlyRateCents ?? 0) > 0 ? unit?.nightlyRateCents : nil
            daily = (unit?.dayRateCents ?? 0) > 0 ? unit?.dayRateCents : nil
            notes = unit?.notes ?? ""
            active = unit.map { $0.status != "archived" } ?? true
            started = true
        }
    }

    private func save() {
        guard form.check([("name", name.nonEmpty == nil ? L("Give the room a name.") : nil)]) else { return }
        working = true
        Task {
            defer { working = false }
            var values: [String: Any?] = [
                "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
                "kind": kind,
                "species": species,
                "capacity": min(20, max(1, Int(capacity) ?? 1)),
                // A playroom is for the day: it has no night to price.
                "nightlyRateCents": kind == "playroom" ? 0 : (nightly ?? 0),
                "dayRateCents": daily ?? 0,
                "notes": notes.nonEmpty,
            ]
            do {
                let saved: StaysUnit
                if let unit {
                    values["status"] = active ? "active" : "archived"
                    saved = try await API.patch("/provider-stays/units/\(unit.id)", body: values)
                } else {
                    values["sortOrder"] = nextSortOrder
                    values["locationId"] = workspace.locationId
                    saved = try await API.post("/provider-stays/units", body: values)
                }
                // The photo goes up (or comes off) once the room itself is saved; a photo that fails never loses the rest.
                do {
                    if let photo = draft.data {
                        let _: StaysUnit = try await ImageUpload.upload(photo, to: "/provider-stays/units/\(saved.id)/photo")
                    } else if unit?.photoUrl != nil && draft.removed {
                        try await API.send("DELETE", "/provider-stays/units/\(saved.id)/photo")
                    }
                    if hasPhoto && shareWithKind && !bare.isEmpty {
                        try await API.send("POST", "/provider-stays/units/\(saved.id)/photo/share", body: ["onlyEmpty": true])
                    }
                } catch let api as APIError {
                    Toast.error(api.code == "invalid_image" ? L("The photo must be a JPG, PNG or WebP image.")
                                : api.code == "image_too_large" ? L("The photo must be 5 MB or smaller.")
                                : L("The room was saved, but the photo couldn’t be. Try again."))
                }
                Toast.show(unit == nil ? LF("%@ added.", saved.name) : L("Room saved."))
                announceDataChanged()
                onSaved()
                dismiss()
            } catch {
                form.apply(error, known: ["name": "name"])
            }
        }
    }
}
