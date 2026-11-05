//
//  PlacesLocationSheet.swift
//  PawMiawNegocios
//
//  Add or change a location (web components/app/locations/location-sheet.tsx):
//  its name, where it is and how to reach it, a photo of the place, its own
//  receipts (with two or more sedes), and the clock it runs on. A new one is two
//  steps — the place, then its clock and the hours it starts with (a copy of
//  another location's). Editing is one page, and changing the clock says what it
//  does to the times already booked. The plan is checked before this opens and
//  again by the server.
//

import SwiftUI
import UIKit

struct PlacesLocationSheet: View {
    let location: PlacesLocation?
    /// Active locations, primary first: the default time zone and where hours are copied from.
    let active: [PlacesLocation]
    /// Every location (archived ones too): no two share a name.
    let all: [PlacesLocation]
    /// Visits still to come at the location being edited: what a new clock would move.
    let upcomingVisits: Int
    let onPlanRequired: () -> Void

    private enum Step { case place, clock }

    private struct Draft: Equatable {
        var name: String
        var address: String
        var phone: String
        var email: String
        var receiptName: String
        var timezone: String
        var copyFrom: String
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var step: Step = .place
    @State private var draft: Draft
    @State private var saving = false
    @State private var photo = PhotoDraft()
    @State private var logo = PhotoDraft()
    @State private var choosingZone = false
    private let initial: Draft
    private let primary: PlacesLocation?

    init(location: PlacesLocation?, active: [PlacesLocation], all: [PlacesLocation], upcomingVisits: Int, onPlanRequired: @escaping () -> Void) {
        self.location = location
        self.active = active
        self.all = all
        self.upcomingVisits = upcomingVisits
        self.onPlanRequired = onPlanRequired
        let primary = active.first(where: \.primary) ?? active.first
        self.primary = primary
        let start = Draft(
            name: location?.name ?? "",
            address: location?.address ?? "",
            phone: location?.phone ?? "",
            email: location?.email ?? "",
            receiptName: location?.receiptName ?? "",
            timezone: location?.timezone?.nonEmpty ?? primary?.timezone?.nonEmpty ?? TimeZone.current.identifier,
            copyFrom: primary?.id ?? ""
        )
        initial = start
        _draft = State(initialValue: start)
    }

    private var editing: Bool { location != nil }
    /// Its own receipts only matter once there are two sedes (a new one makes the second).
    private var several: Bool { !editing || all.filter { !$0.isArchived }.count > 1 }
    private var dirty: Bool { draft != initial || !photo.isEmpty || !logo.isEmpty || (!editing && step == .clock) }
    private var zoneChanged: Bool { editing && draft.timezone != (location?.timezone ?? draft.timezone) }

    var body: some View {
        ProviderModal(
            title: location.map { LF("Edit %@", $0.name) } ?? L("Add a location"),
            subtitle: L("A place the business works from. It keeps its own hours, rooms, registers, visits and stays; clients and the catalog are shared."),
            systemImage: "map-pin",
            accent: .aqua,
            isDirty: dirty,
            form: form,
            primaryTitle: !editing && step == .place ? L("Continue") : (editing ? L("Save location") : L("Add location")),
            isWorking: saving,
            steps: editing ? nil : ModalSteps([L("The place"), L("Clock and hours")], current: step == .place ? 0 : 1),
            onBack: !editing && step != .place ? { step = .place } : nil,
            primaryIcon: !editing && step == .place ? nil : (editing ? "save" : "plus"),
            onPrimary: primaryAction
        ) {
            if editing {
                place
                clock
            } else if step == .place {
                place
            } else {
                clock
            }
        }
        .sheet(isPresented: $choosingZone) {
            PlacesTimeZonePicker(selection: draft.timezone, suggestions: [primary?.timezone, TimeZone.current.identifier].compactMap { $0?.nonEmpty }) { draft.timezone = $0 }
        }
    }

    // MARK: The place

    @ViewBuilder
    private var place: some View {
        PMTextField(L("Name"), text: $draft.name, key: "name", form: form, prompt: L("e.g. Downtown, North branch"), capitalization: .words, required: true)
        PMTextField(L("Address"), text: $draft.address, key: "address", form: form, prompt: L("Street and number, neighbourhood, city"), hint: L("Families see it on their visit, their stay and their receipt."))
        PMTextField(L("Phone or WhatsApp"), text: $draft.phone, key: "phone", form: form, keyboard: .phonePad)
        PMTextField(L("Email"), text: $draft.email, key: "email", form: form, keyboard: .emailAddress)

        PhotoField(
            label: L("Photo"),
            hint: L("The building or the entrance: families see it when they choose where to book."),
            currentURL: location?.photoUrl,
            draft: $photo,
            addTitle: L("Add a photo"),
            changeTitle: L("Change photo"),
            removedNote: L("The photo is removed when you save.")
        )
        .disabled(saving)

        if several {
            ModalSection(title: L("Its receipts"), subtitle: L("Optional. Leave them empty and this sede’s receipts carry the business’s name and logo. The legal details are always the business’s."), systemImage: "receipt-text", tint: Theme.borderSoft) {
                PMTextField(L("Name on receipts"), text: $draft.receiptName, prompt: Workspace.shared.current?.name ?? L("The business’s name"), hint: L("When this sede goes by its own name, e.g. a second brand."))
                PhotoField(
                    label: L("Logo on receipts"),
                    hint: L("Without one, this sede’s receipts print the business’s logo."),
                    currentURL: location?.receiptLogoUrl,
                    draft: $logo,
                    addTitle: L("Use another logo"),
                    changeTitle: L("Change logo"),
                    removeTitle: L("Take this logo back out"),
                    removeSavedTitle: L("Use the business’s logo"),
                    removedNote: L("Back to the business’s logo when you save.")
                )
                .disabled(saving)
            }
        }
    }

    // MARK: The clock

    @ViewBuilder
    private var clock: some View {
        ModalSection(title: L("Its clock"), subtitle: L("“Today”, opening hours and the day’s totals at this location follow it."), systemImage: "earth", tint: Theme.aqua) {
            // The web's TimezonePicker under the section's line, its label read aloud only.
            FormField(label: "", key: "timezone", form: form) {
                PlacesTimeZoneButton(zone: draft.timezone, invalid: form.error("timezone") != nil) { choosingZone = true }
                    .disabled(saving)
            }
            if zoneChanged, let old = location?.timezone {
                let shift = PlacesLocationRules.shiftMinutes(from: old, to: draft.timezone)
                PlacesConsequenceRow(
                    systemImage: "triangle-alert",
                    text: upcomingVisits > 0
                        ? (upcomingVisits == 1
                           ? L("Visits keep the moment they were booked for, not the hour on the clock: 1 visit to come moves on this location’s schedule. Opening hours keep their times, now in the new zone.")
                           : LF("Visits keep the moment they were booked for, not the hour on the clock: %d visits to come move on this location’s schedule. Opening hours keep their times, now in the new zone.", upcomingVisits))
                        : L("Visits keep the moment they were booked for, not the hour on the clock. Opening hours keep their times, now in the new zone."),
                    title: shift == 0
                        ? LF("%@ and %@ read the same time today.", PlacesLocationRules.city(old), PlacesLocationRules.city(draft.timezone))
                        : LF("Times already booked here will read %@.", PlacesLocationRules.shiftLabel(shift))
                )
            }
        }

        if !editing {
            ModalSection(title: L("Hours and booking rules"), systemImage: "clock-3", tint: Theme.butter) {
                if active.count > 1 {
                    Text(L("It starts with a copy; change them afterwards in Availability.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    ChoiceCards(options: active.map { (value: $0.id, title: LF("Same as %@", $0.name), subtitle: nil) }, selection: $draft.copyFrom)
                } else {
                    Text(LF("It starts with the hours and booking rules of %@; change them afterwards in Availability.", primary?.name ?? L("the main location")))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    // MARK: Saving

    private func placeProblems() -> [(String, String?)] {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameProblem: String? = name.isEmpty
            ? L("Give the location a name.")
            : (PlacesLocationRules.nameTaken(name, locations: all.isEmpty ? active : all, except: location?.id) ? L("Another location already has that name.") : nil)
        let phone = draft.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = phone.filter(\.isNumber).count
        let phoneProblem: String? = phone.isEmpty || (8...15).contains(digits) ? nil : L("Check the phone number.")
        let email = draft.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailProblem: String? = email.isEmpty || email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil ? nil : L("Check the email address.")
        return [("name", nameProblem), ("phone", phoneProblem), ("email", emailProblem)]
    }

    private func primaryAction() {
        if !editing && step == .place {
            if form.check(placeProblems()) { step = .clock }
            return
        }
        guard form.check(placeProblems()) else { step = .place; return }
        var fields: [String: Any?] = [
            "name": draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            "timezone": draft.timezone,
            "address": draft.address.nonEmpty,
            "phone": draft.phone.nonEmpty,
            "email": draft.email.nonEmpty,
        ]
        if several { fields["receiptName"] = draft.receiptName.nonEmpty }
        if !editing, !draft.copyFrom.isEmpty, draft.copyFrom != primary?.id { fields["copyFromLocationId"] = draft.copyFrom }

        saving = true
        Task {
            defer { saving = false }
            do {
                let saved: PlacesLocation
                if let location {
                    saved = try await API.patch("/provider-locations/\(location.id)", body: fields)
                } else {
                    saved = try await API.post("/provider-locations", body: fields)
                }
                // The photo goes up (or comes off) once the location itself is saved; a photo that fails never loses the rest.
                await apply(photo, path: "/provider-locations/\(saved.id)/photo", field: "photo", failure: photoError)
                await apply(logo, path: "/provider-locations/\(saved.id)/receipt-logo", field: "logo", failure: logoError)
                Toast.show(location != nil ? L("Location saved.") : LF("%@ added.@location", saved.name))
                await placesLocationsChanged()
                dismiss()
            } catch {
                if let api = error as? APIError {
                    if api.code == "location_name_taken" {
                        step = .place
                        _ = form.check([("name", L("Another location already has that name."))])
                        return
                    }
                    if api.code == "invalid_timezone" {
                        _ = form.check([("timezone", L("Choose a valid time zone."))])
                        return
                    }
                    // Past the plan's locations: close and show what to do, in the page's own words.
                    if api.code == "location_plan_required" || api.code == "location_limit_reached" {
                        Toast.error(PlacesLocationRules.errorText(error))
                        dismiss()
                        onPlanRequired()
                        return
                    }
                }
                form.apply(error, known: ["name": "name", "phone": "phone", "email": "email", "address": "address", "timezone": "timezone"])
            }
        }
    }

    /// A photo or logo picked here goes up once the location is saved (or comes off then).
    private func apply(_ image: PhotoDraft, path: String, field: String, failure: (Error) -> String) async {
        do {
            if let data = image.data {
                let _: PlacesLocation = try await ImageUpload.upload(data, to: path, field: field)
            } else if location != nil && image.removed {
                try await API.send("DELETE", path)
            }
        } catch {
            Toast.error(failure(error))
        }
    }

    private func photoError(_ error: Error) -> String {
        switch (error as? APIError)?.code {
        case "invalid_image": L("The photo must be a JPG, PNG or WebP image.")
        case "image_too_large": L("The photo must be 5 MB or smaller.")
        default: L("The photo couldn’t be saved. Try again.")
        }
    }

    private func logoError(_ error: Error) -> String {
        switch (error as? APIError)?.code {
        case "invalid_image": L("The logo must be a JPG, PNG or WebP image.")
        case "image_too_large": L("The logo must be 3 MB or smaller.")
        default: L("The logo couldn’t be saved. Try again.")
        }
    }
}

// MARK: - Time zone

/// The web's TimezonePicker trigger: a 48 field with the blue globe, the zone and a chevron.
struct PlacesTimeZoneButton: View {
    let zone: String
    var invalid = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Glyph("earth", size: 16).foregroundStyle(Theme.blue)
                Text(PlacesTimeZones.label(zone)).font(Theme.text(14)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                Spacer(minLength: 0)
                Glyph("chevron-down", size: 16).foregroundStyle(Theme.inkSoft)
            }
            .fieldChrome(invalid: invalid)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Time zone"))
        .accessibilityValue(PlacesTimeZones.label(zone))
    }
}

/// Choose a time zone (web `TimezonePicker`): the zone in use, the suggestions (the main
/// location's, this device's), the common ones, or a search. A location's clock and the
/// business hours' clock both open it.
struct PlacesTimeZonePicker: View {
    let selection: String
    var suggestions: [String] = []
    /// A line under a suggestion ("This device’s time zone").
    var notes: [String: String] = [:]
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var searching: Bool { query.nonEmpty != nil }

    private var results: [String] {
        let found = PlacesTimeZones.search(query)
        guard !searching else { return found }
        var seen = Set<String>()
        return ([selection] + suggestions + found).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var body: some View {
        ProviderModal(title: L("Time zone"), systemImage: "earth", accent: .aqua, cancelTitle: L("Close")) {
            SearchField(prompt: L("Search a city or zone"), text: $query, shape: .field)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(results, id: \.self) { zone in
                    Button {
                        onPick(zone)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(PlacesTimeZones.label(zone)).font(Theme.text(14, weight: zone == selection ? .bold : .regular)).foregroundStyle(Theme.inkStrong)
                                // Searching by region ("America/") still shows what matched.
                                if let line = searching ? zone.replacingOccurrences(of: "_", with: " ") : notes[zone] {
                                    Text(line).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                                }
                            }
                            Spacer(minLength: 8)
                            if zone == selection { Glyph("check", size: 16).foregroundStyle(Theme.blue) }
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(zone == selection ? .isSelected : [])
                    RowDivider()
                }
                if results.isEmpty {
                    Text(LF("No time zone matches “%@”.", query)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.vertical, 12)
                }
            }
        }
        .presentationDetents([.large])
    }
}
