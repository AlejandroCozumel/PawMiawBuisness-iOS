//
//  StaysBooking.swift
//  PawMiawNegocios
//
//  A new stay in three steps (web stay-booking-sheet.tsx): who (the client
//  and pets), when and where (boarding or daycare, the days, the times and a
//  room that fits: species, capacity, full nights), then the price and how to
//  save it — booked now, or held as a request — with the owner's words and a
//  note for the team. Who: the shared ClientPetPicker.
//

import SwiftUI

private enum StaysBookingStep: Int, CaseIterable { case who, when, confirm }

struct StaysBookingSheet: View {
    let preset: StaysBookingPreset
    let onBooked: () -> Void

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var step: StaysBookingStep = .who
    @State private var kind = "boarding"
    @State private var client: PickedClient?
    @State private var petIds: [String] = []
    @State private var checkInDay = ""
    @State private var checkOutDay = ""
    @State private var checkInTime = "14:00"
    @State private var checkOutTime = "11:00"
    @State private var unitId: String?
    @State private var rate: Int?
    @State private var rateTouched = false
    @State private var asRequest = false
    @State private var ownerInstructions = ""
    @State private var internalNotes = ""
    @State private var settings: StaysSettings?
    @State private var units: [StaysUnit] = []
    @State private var rangeStays: [StaysStay] = []
    @State private var working = false

    private var effectiveCheckOut: String { kind == "daycare" ? checkInDay : checkOutDay }
    private var datesReady: Bool { !checkInDay.isEmpty && (kind == "daycare" || (!checkOutDay.isEmpty && checkOutDay > checkInDay)) }
    private var pets: [PickedPet] { client?.activePets.filter { petIds.contains($0.id) } ?? [] }
    private var petCount: Int { max(1, pets.count) }
    private var nights: Int { StaysDay.nights(kind: kind, from: checkInDay, to: effectiveCheckOut) }
    private var currency: String { settings?.currency ?? workspace.currency }

    private struct RoomOption: Identifiable {
        let unit: StaysUnit
        let detail: String
        let available: Bool
        var id: String { unit.id }
    }

    private var roomOptions: [RoomOption] {
        units.map { unit in
            let dayRoom = !StaysDay.roomTakes(unitKind: unit.unitKind, stayKind: kind)
            let wrongSpecies = pets.contains { unit.species != "any" && ($0.petSpecies ?? "").lowercased() != unit.species }
            let tooSmall = pets.count > unit.seats
            let fullOn = datesReady ? StaysDay.firstFullDay(capacity: unit.seats, stays: rangeStays, unitId: unit.id, kind: kind, from: checkInDay, to: effectiveCheckOut, pets: petCount) : nil
            let unitRate = kind == "daycare" ? unit.dayRateCents : unit.nightlyRateCents
            let detail = dayRoom ? L("Daycare only")
                : wrongSpecies ? L("Not for this species")
                : tooSmall ? LF("Holds %d", unit.seats)
                : fullOn.map { LF("Full on %@", StaysDay.short($0)) }
                ?? "\(StaysWords.unitKind(unit.kind)) · \((unitRate ?? 0) > 0 ? Money.format(unitRate, currency: currency) : L("No rate set"))"
            return RoomOption(unit: unit, detail: detail, available: !dayRoom && !wrongSpecies && !tooSmall && fullOn == nil)
        }
    }

    var body: some View {
        ProviderModal(title: L("New stay"), subtitle: L("Book boarding or a day of daycare. The room is held as soon as you save."),
                      systemImage: "bed-double", accent: .aqua, isDirty: client != nil || step != .who, form: form,
                      primaryTitle: step == .confirm ? (asRequest ? L("Save request") : L("Book stay")) : L("Continue"),
                      isWorking: working,
                      steps: ModalSteps(steps: [(L("Who"), "user-round"), (L("When and where"), "calendar-days"), (L("Confirm"), "check")], current: step.rawValue),
                      onBack: step != .who ? { step = StaysBookingStep(rawValue: step.rawValue - 1) ?? .who } : nil,
                      primaryIcon: step == .confirm ? "check" : nil,
                      onPrimary: next) {
            if step != .who, let client {
                // What it's about, once chosen — the same pills as the other create modals; Back changes it.
                ContextPills(client: client.ownerName, linked: client.householdId != nil, pets: pets.map(\.name)) {
                    if step == .confirm {
                        Chip(text: "\(StaysWords.kind(kind)) · \(kind == "daycare" ? StaysDay.short(checkInDay) : "\(StaysDay.short(checkInDay)) – \(StaysDay.short(effectiveCheckOut))")",
                             tone: .muted, icon: kind == "daycare" ? "sun" : "moon", size: .large)
                        if let room = units.first(where: { $0.id == unitId }) { Chip(text: room.name, tone: .muted, icon: "bed-double", size: .large) }
                    }
                }
            }
            switch step {
            case .who:
                ClientPetPicker(client: $client, petIds: $petIds, pets: .several, petRequired: true, petKey: "pets", form: form)
            case .when:
                whenStep
            case .confirm:
                confirmStep
            }
        }
        .task { await loadBasics() }
        .onChange(of: kind) { _, _ in applyDefaultTimes(); clearRoomIfUnfit() }
        .onChange(of: checkInDay) { _, _ in Task { await loadRange() } }
        .onChange(of: checkOutDay) { _, _ in Task { await loadRange() } }
        .onChange(of: unitId) { _, _ in applyRoomRate() }
    }

    // MARK: Steps

    @ViewBuilder
    private var whenStep: some View {
        Segmented(options: [.init("boarding", L("Boarding"), icon: "moon"), .init("daycare", L("Daycare"), icon: "sun")], selection: $kind, label: L("Kind"))
        ModalSection(title: L("When")) {
            // A new stay starts today or later (the server says the same).
            DayField(label: kind == "daycare" ? L("Day") : L("Check-in"), day: $checkInDay, min: StaysDay.today(), key: "dates", form: form)
            if kind != "daycare" {
                DayField(label: L("Check-out"), day: $checkOutDay, min: StaysDay.add(checkInDay, 1))
                if datesReady { Text(StaysWords.units(kind, nights)).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft) }
            }
            TimeField(label: L("Arrival time"), value: $checkInTime)
            TimeField(label: L("Pickup time"), value: $checkOutTime)
        }
        ModalSection(title: L("Room"), subtitle: units.isEmpty ? L("Add rooms in the Rooms tab to assign them here.") : nil) {
            // A room that doesn't fit says why and stays unchosen.
            ChoiceCards(options: [(value: Optional<String>.none, title: L("Decide later"), subtitle: Optional(L("Book now, assign a room before arrival")))]
                        + roomOptions.map { (value: Optional($0.unit.id), title: $0.unit.name, subtitle: Optional($0.detail)) },
                        selection: Binding(get: { unitId }, set: { id in
                            if let id, let option = roomOptions.first(where: { $0.unit.id == id }), !option.available { Toast.error(option.detail) } else { unitId = id }
                        }))
        }
    }

    @ViewBuilder
    private var confirmStep: some View {
        let zeroTyped = rate != nil && (rate ?? 0) <= 0
        ModalSection(title: L("Price")) {
            MoneyField(label: kind == "daycare" ? L("Price per pet per day") : L("Price per pet per night"), cents: Binding(get: { rate }, set: { rate = $0; rateTouched = true }), key: "rate", form: form)
                .id("rate-\(unitId ?? "none")-\(kind)")
            // The total, the same height as the price.
            HStack {
                Text(StaysWords.units(kind, nights) + (petCount > 1 ? " × " + LF("%d pets", petCount) : "")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                Spacer()
                Text(rate == nil || zeroTyped ? L("No price yet") : Money.format(nights * (rate ?? 0) * petCount, currency: currency)).font(.brandHeading(18)).foregroundStyle(Theme.inkStrong)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Theme.wash(Theme.butter, 40), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            if zeroTyped {
                Text(L("A price is more than $0. To not charge it, leave it empty and give it as a courtesy when charging.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.destructive)
            } else if rate == nil {
                // Booking only holds the room: the bill at check-out is where it gets its price, or goes as a courtesy.
                HStack(alignment: .top, spacing: 8) {
                    Glyph("tag", size: 14).padding(.top, 1)
                    Text(L("No price yet: when charging the check-out, you put one or give it as a courtesy."))
                }
                .font(Theme.text(12)).foregroundStyle(Theme.inkStrong)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(Theme.mango, 16), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            }
        }
        ModalSection(title: L("How to save it")) {
            ChoiceCards(options: [(value: false, title: L("Book now"), subtitle: Optional(L("Confirmed, and the room is held."))),
                                  (value: true, title: L("Hold as a request"), subtitle: Optional(L("Keeps the room, confirm it later")))], selection: $asRequest)
        }
        ModalSection(title: L("Notes")) {
            PMTextField(L("What the owner asked for"), text: $ownerInstructions, prompt: L("e.g. Afraid of thunder, no chicken treats"), multiline: true)
            PMTextField(L("Note for the team"), text: $internalNotes, prompt: L("Only your team sees this"), multiline: true)
        }
    }

    // MARK: Work

    private func loadBasics() async {
        if checkInDay.isEmpty {
            checkInDay = preset.day < StaysDay.today() ? StaysDay.today() : preset.day
            checkOutDay = StaysDay.add(checkInDay, 1)
            unitId = preset.unitId
        }
        async let settingsCall: StaysSettings? = try? await API.get("/provider-stays/settings")
        async let unitsCall: [StaysUnit]? = try? await API.get("/provider-stays/units", query: ["locationId": workspace.locationId])
        settings = await settingsCall
        units = (await unitsCall) ?? []
        applyDefaultTimes()
        applyRoomRate()
        await loadRange()
    }

    private func loadRange() async {
        guard datesReady else { return }
        let to = effectiveCheckOut < checkInDay ? checkInDay : effectiveCheckOut
        let page: StaysPage? = try? await API.get("/provider-stays", query: ["from": checkInDay, "to": to, "locationId": workspace.locationId])
        rangeStays = page?.items ?? []
        clearRoomIfUnfit()
    }

    private func applyDefaultTimes() {
        guard let settings else { return }
        checkInTime = (kind == "daycare" ? settings.daycareStartTime : settings.checkInTime) ?? checkInTime
        checkOutTime = (kind == "daycare" ? settings.daycareEndTime : settings.checkOutTime) ?? checkOutTime
    }

    /// A room that stopped fitting (other pets, other dates) is let go.
    private func clearRoomIfUnfit() {
        if let unitId, roomOptions.contains(where: { $0.unit.id == unitId && !$0.available }) { self.unitId = nil }
    }

    private func applyRoomRate() {
        guard !rateTouched else { return }
        guard let room = units.first(where: { $0.id == unitId }) else { rate = nil; return }
        let cents = kind == "daycare" ? room.dayRateCents : room.nightlyRateCents
        rate = (cents ?? 0) > 0 ? cents : nil
    }

    private func next() {
        switch step {
        case .who:
            guard form.check([
                ("client", client == nil ? L("Choose the client first.") : nil),
                ("pets", client != nil && petIds.isEmpty ? L("Choose at least one pet.") : nil),
            ]) else { return }
            step = .when
        case .when:
            guard form.check([("dates", datesReady ? nil : (kind == "daycare" ? L("Choose a day") : L("Check-out has to be after check-in.")))]) else { return }
            step = .confirm
        case .confirm:
            book()
        }
    }

    private func book() {
        guard let client else { return }
        guard form.check([("rate", rate != nil && (rate ?? 0) <= 0 ? L("A price is more than $0. To not charge it, leave it empty and give it as a courtesy when charging.") : nil)]) else { return }
        working = true
        Task {
            defer { working = false }
            let body: [String: Any?] = [
                "providerClientId": client.id,
                "providerClientPetIds": petIds,
                "kind": kind,
                "status": asRequest ? "requested" : "confirmed",
                "unitId": unitId,
                "checkInDay": checkInDay,
                "checkInTime": checkInTime,
                "checkOutDay": effectiveCheckOut,
                "checkOutTime": checkOutTime,
                "rateCents": (rate ?? 0) > 0 ? rate : nil,
                "ownerInstructions": ownerInstructions.nonEmpty,
                "internalNotes": internalNotes.nonEmpty,
                "locationId": workspace.locationId,
            ]
            do {
                let stay: StaysStay = try await API.post("/provider-stays", body: body)
                let range = kind == "daycare" ? StaysDay.short(checkInDay) : "\(StaysDay.short(checkInDay)) – \(StaysDay.short(effectiveCheckOut))"
                Toast.show(LF("%@ booked · %@", stay.petNames, range))
                announceDataChanged()
                onBooked()
                dismiss()
            } catch {
                Toast.error(error, fallback: L("Could not book this stay."))
            }
        }
    }
}
