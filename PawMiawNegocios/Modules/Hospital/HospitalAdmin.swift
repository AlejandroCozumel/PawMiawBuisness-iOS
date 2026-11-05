//
//  HospitalAdmin.swift
//  PawMiawNegocios
//
//  The hospital page's other two tabs (web hospital-admin.tsx): who is on
//  call at this place, now and the next two weeks (after hours a family's
//  "voy en camino" reaches them), and the hospital's rules: how long a dose
//  stays on time, when it counts as missed, the daily fee and what families
//  read about visiting.
//

import SwiftUI

// MARK: - On call

struct HospOnCallPanel: View {
    let canManage: Bool
    @EnvironmentObject private var workspace: Workspace
    @State private var list: HospOnCallList?
    @State private var error: String?
    @State private var members: [HospMember] = []
    @State private var memberId = ""
    @State private var startsAt = HospOnCallPanel.defaultStart()
    @State private var endsAt = HospOnCallPanel.defaultEnd()
    @State private var note = ""
    @State private var saving = false
    @State private var removing: HospOnCallShift?
    @StateObject private var form = FormState()

    private var zone: TimeZone { workspace.timeZone }
    private var locationId: String? { workspace.selectedLocation?.id ?? workspace.memberLocations.first?.id }
    private var eligible: [HospMember] {
        members.filter { member in
            member.can(.hospitalView) && ((member.locationIds ?? []).isEmpty || (locationId.map { (member.locationIds ?? []).contains($0) } ?? false))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionCard(L("On call"), subtitle: L("After hours, a family’s “on my way” reaches whoever is on call here."), icon: "phone-call", accent: Theme.lime) {
                VStack(alignment: .leading, spacing: 20) {
                    // Right now: who a family's warning reaches.
                    VStack(alignment: .leading, spacing: 12) {
                        HospCardGroup(title: L("On call now"), icon: "phone-call")
                        if let list {
                            let now = list.now ?? []
                            if now.isEmpty {
                                HStack(spacing: 12) {
                                    Glyph("moon", size: 20).foregroundStyle(Theme.inkStrong)
                                        .frame(width: 40, height: 40).background(Theme.wash(Theme.lavender, 30), in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L("Nobody is on call right now")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                                        Text(L("After hours, warnings go to the care team at this location.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                                    }
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                            } else {
                                ForEach(now) { shift in
                                    HStack(spacing: 12) {
                                        Avatar(name: shift.member?.name, imageURL: shift.member?.image, size: 48, tint: Theme.lime)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(shift.member?.name ?? L("Team member")).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                            HStack(spacing: 4) {
                                                Glyph("clock-3", size: 14)
                                                Text(LF("Until %@", HospFmt.dateTime(shift.endsAt, zone)))
                                            }
                                            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                                            if let note = shift.note?.nonEmpty { Text(note).font(Theme.text(12)).italic().foregroundStyle(Theme.inkSoft).lineLimit(1) }
                                        }
                                        Spacer(minLength: 8)
                                        Glyph("phone-call", size: 16).foregroundStyle(Theme.inkStrong)
                                            .frame(width: 36, height: 36).background(Theme.wash(Theme.lime, 45), in: Circle())
                                    }
                                    .padding(16)
                                    .background(Theme.wash(Theme.lime, 16), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.lime, 70, with: Theme.borderSoft), lineWidth: 1.5))
                                }
                            }
                        } else if let error {
                            ErrorState(message: error) { await load() }
                        } else {
                            LoadingState()
                        }
                    }

                    // The next two weeks, one row a shift.
                    if let list {
                        let shifts = list.shifts ?? []
                        let nowIds = Set((list.now ?? []).map(\.id))
                        StitchedDivider()
                        VStack(alignment: .leading, spacing: 12) {
                            HospCardGroup(title: L("Next two weeks"), icon: "calendar-clock") {
                                if !shifts.isEmpty {
                                    Text(LP(shifts.count, "1 shift", "%d shifts")).font(Theme.text(12, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                                        .padding(.horizontal, 10).padding(.vertical, 4).background(Theme.surfaceMuted, in: Capsule())
                                }
                            }
                            if shifts.isEmpty {
                                EmptyState(systemImage: "calendar-clock", title: L("No shifts yet."),
                                           message: canManage ? L("Add who answers after hours: a shift lasts up to 7 days.") : L("Whoever manages the hospital adds who answers after hours."),
                                           accent: Theme.lime)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(shifts.enumerated()), id: \.element.id) { index, shift in
                                        if index > 0 { RowDivider() }
                                        shiftRow(shift, current: nowIds.contains(shift.id))
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(16)
            }

            if canManage {
                SectionCard(L("Add a shift"), subtitle: L("At most 7 days a shift; two shifts of the same person can’t overlap."), icon: "calendar-plus", accent: Theme.aqua) {
                    VStack(alignment: .leading, spacing: 0) {
                        FormScroll(form: form) {
                            VStack(alignment: .leading, spacing: 16) {
                                MenuField(label: L("Who"), options: [("", L("Choose a person"))] + eligible.map { ($0.id, $0.label) }, selection: $memberId, key: "member", form: form, required: true)
                                DateTimeField(label: L("From"), date: $startsAt, zone: zone, required: true)
                                DateTimeField(label: L("Until"), date: $endsAt, zone: zone, min: startsAt, key: "until", form: form, required: true)
                                PMTextField(L("Note"), text: $note, prompt: L("e.g. Reachable by phone, 10 min away"), optional: true)
                            }
                            .padding(16)
                        }
                        RowDivider()
                        PMButton(L("Add shift"), systemImage: "plus", fullWidth: true, isWorking: saving) { add() }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                }
            }
        }
        .reloadsOnScope { await load() }
        .sheet(item: $removing) { shift in
            ConfirmSheet(
                title: L("Remove this shift?"),
                message: LF("%@ stops being on call %@ → %@.", shift.member?.name ?? L("Team member"), HospFmt.dateTime(shift.startsAt, zone), HospFmt.dateTime(shift.endsAt, zone)),
                confirmTitle: L("Remove shift"),
                destructive: true
            ) { _ in
                do {
                    try await API.send("DELETE", "/provider-hospital/on-call/\(shift.id)")
                    Toast.show(L("Shift removed."))
                    await load()
                } catch { throw hospRefusal(error, fallback: "Could not remove the shift.") }
            }
        }
    }

    private func shiftRow(_ shift: HospOnCallShift, current: Bool) -> some View {
        HStack(spacing: 12) {
            Avatar(name: shift.member?.name, imageURL: shift.member?.image, size: 40, tint: current ? Theme.lime : Theme.aqua)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(shift.member?.name ?? L("Team member")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    if current { Chip(text: L("Now"), tone: .custom(Theme.lime), dot: Theme.lime, percent: 22) }
                }
                HStack(spacing: 4) {
                    Glyph("clock-3", size: 14)
                    Text(range(shift)).monospacedDigit().lineLimit(1)
                }
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                let extra = [workspace.multiLocation ? shift.locationName : nil, shift.note].compactMap { $0?.nonEmpty }.joined(separator: " · ")
                if !extra.isEmpty { Text(extra).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if canManage {
                IconCircleButton(systemImage: "trash-2", label: L("Remove shift"), tint: Theme.destructive) { removing = shift }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(current ? AnyShapeStyle(Theme.wash(Theme.lime, 10)) : AnyShapeStyle(Theme.surface))
    }

    private func range(_ shift: HospOnCallShift) -> String {
        let from = HospFmt.clock(shift.startsAt, zone), to = HospFmt.clock(shift.endsAt, zone)
        let startDay = HospFmt.dayKey(shift.startsAt, zone), endDay = HospFmt.dayKey(shift.endsAt, zone)
        let startLabel = HospFmt.day(startDay, zone: zone), endLabel = HospFmt.day(endDay, zone: zone)
        if startDay == endDay { return "\(startLabel) · \(from)–\(to)" }
        return "\(startLabel) \(from) → \(endLabel) \(to)"
    }

    private func load() async {
        do {
            list = try await API.get("/provider-hospital/on-call", query: ["locationId": workspace.locationId])
            error = nil
        } catch is CancellationError {
        } catch {
            if list == nil { self.error = errorText(error) }
        }
        if canManage && members.isEmpty { members = await HospAPI.members() }
    }

    private func add() {
        guard form.check([
            ("member", memberId.isEmpty ? L("Choose who is on call.") : nil),
            ("until", endsAt <= startsAt ? L("The shift ends after it starts.") : nil),
        ]) else { return }
        guard let locationId else { Toast.error(L("Choose a location first.")); return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let _: HospOnCallList = try await API.post("/provider-hospital/on-call", body: [
                    "locationId": locationId, "organizationMemberId": memberId,
                    "startsAt": DateText.iso(startsAt), "endsAt": DateText.iso(endsAt), "note": note.nonEmpty,
                ])
                Toast.show(L("On-call shift added."))
                note = ""
                memberId = ""
                await load()
            } catch {
                Toast.error(hospError(error, fallback: "Could not add the shift."))
            }
        }
    }

    private static func defaultStart() -> Date {
        Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private static func defaultEnd() -> Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

// MARK: - Settings

struct HospSettingsPanel: View {
    let canEdit: Bool
    @State private var settings: HospSettings?
    @State private var services: [HospCatalogItem] = []
    @State private var error: String?
    @State private var grace = ""
    @State private var missed = ""
    @State private var feeGrace = ""
    @State private var visiting = ""
    @State private var feeItemId = ""
    @State private var saving = false
    @StateObject private var form = FormState()

    private var dirty: Bool {
        guard let s = settings else { return false }
        return grace != "\(s.lateGraceMinutes ?? 30)" || missed != "\(s.missedAfterMinutes ?? 120)" || feeGrace != "\(s.feeGraceMinutes ?? 60)"
            || visiting != (s.visitingInfo ?? "") || feeItemId != (s.dailyFeeItemId ?? "")
    }

    var body: some View {
        Group {
            if let settings {
                FormScroll(form: form) {
                    VStack(alignment: .leading, spacing: 24) {
                        // The team's side: when a dose is on time or missed, and what a hospital day charges.
                        SectionCard(L("Doses and daily fee"), subtitle: L("How the treatment sheet colours each dose, and what a hospital day charges."), icon: "clock-3", accent: Theme.aqua) {
                            VStack(alignment: .leading, spacing: 20) {
                                VStack(alignment: .leading, spacing: 12) {
                                    HospCardGroup(title: L("Dose timing"), icon: "clock-3")
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                                        minutes(L("On time within"), $grace, key: "grace", hint: L("Either side of the scheduled time."))
                                        minutes(L("Missed after"), $missed, key: "missed", hint: L("Or once the next dose is due."))
                                    }
                                }
                                StitchedDivider()
                                VStack(alignment: .leading, spacing: 12) {
                                    HospCardGroup(title: L("Daily hospital fee"), icon: "receipt", hint: L("A service from the Catalog, charged once per hospital day."))
                                    VStack(alignment: .leading, spacing: 8) {
                                        MenuField(label: L("Service"), options: feeOptions(settings), selection: $feeItemId)
                                            .disabled(!canEdit)
                                        if !feeItemId.isEmpty { HospHint(text: L("One line on the bill, its quantity the days in the hospital.")) }
                                    }
                                    minutes(L("Day grace"), $feeGrace, key: "feeGrace", hint: L("A discharge this soon into a new day doesn’t charge it."))
                                    if let chosen = services.first(where: { $0.id == feeItemId }), (chosen.defaultUnitAmount ?? 0) <= 0 {
                                        NoticeCard(tone: .warning, title: L("This service has no price: the bill asks for one before it can be charged. Set it in the Catalog."))
                                    }
                                }
                            }
                            .padding(16)
                        }
                        // The families' side: what they read, and where the money asked up front is set.
                        SectionCard(L("For families"), subtitle: L("Families read it in their app while their pet is in."), icon: "heart-handshake", accent: Theme.pink) {
                            VStack(alignment: .leading, spacing: 20) {
                                PMTextField(L("Visiting information"), text: $visiting, prompt: L("e.g. Visits from 12:00 to 13:00 and 18:00 to 19:00, one person at a time."), optional: true, multiline: true)
                                    .disabled(!canEdit)
                                StitchedDivider()
                                VStack(alignment: .leading, spacing: 12) {
                                    HospCardGroup(title: L("Deposit and after-hours surcharge"), icon: "coins")
                                    VStack(alignment: .leading, spacing: 8) {
                                        if let deposit = settings.emergencyDepositAmount, deposit > 0 {
                                            Text(LF("Emergency deposit: %@.", Money.format(deposit, currency: settings.currency))).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                                        }
                                        Text(L("The emergency deposit and the after-hours surcharge are in Store → Settings.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                                        NavigationLink(value: ProviderRoute.section(.store)) {
                                            Text(L("Open Store settings")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.blue)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.wash(Theme.aqua, 12), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                                }
                            }
                            .padding(16)
                        }
                        if canEdit {
                            // One save for both cards, with a way back.
                            SaveBar(dirty: dirty, working: saving, saveTitle: L("Save"), floating: true, onDiscard: { fill(settings) }, onSave: { save() })
                        } else {
                            HospHint(text: L("Only whoever manages the hospital can change these."))
                        }
                    }
                }
            } else if let error {
                ErrorState(message: error) { await load() }
            } else {
                LoadingState()
            }
        }
        .reloadsOnScope { await load() }
    }

    private func feeOptions(_ settings: HospSettings) -> [(value: String, title: String)] {
        var options: [(value: String, title: String)] = [("", L("No daily fee"))]
        options += services.map { ($0.id, "\($0.name) · \(($0.defaultUnitAmount ?? 0) > 0 ? Money.format($0.defaultUnitAmount, currency: $0.currency) : L("No price"))") }
        if let current = settings.dailyFeeItemId, !services.contains(where: { $0.id == current }) {
            options.append((current, L("The current service")))
        }
        return options
    }

    private func minutes(_ label: String, _ text: Binding<String>, key: String, hint: String) -> some View {
        FormField(label: label, key: key, hint: hint, form: form) {
            HStack {
                TextField("", text: text).keyboardType(.numberPad)
                Text(L("min")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            .fieldChrome(invalid: form.error(key) != nil)
            .disabled(!canEdit)
            .onChange(of: text.wrappedValue) { _, value in
                let digits = value.filter(\.isNumber)
                if digits != value { text.wrappedValue = digits }
                form.clear(key)
            }
        }
    }

    private func fill(_ s: HospSettings) {
        grace = "\(s.lateGraceMinutes ?? 30)"
        missed = "\(s.missedAfterMinutes ?? 120)"
        feeGrace = "\(s.feeGraceMinutes ?? 60)"
        visiting = s.visitingInfo ?? ""
        feeItemId = s.dailyFeeItemId ?? ""
    }

    private func load() async {
        do {
            let loaded: HospSettings = try await API.get("/provider-hospital/settings")
            let page: Page<HospCatalogItem>? = try? await API.get("/provider-catalog", query: ["limit": "100", "offset": "0", "itemType": "service", "active": "true"])
            services = page?.items ?? []
            if settings == nil || !dirty { fill(loaded) }
            settings = loaded
            error = nil
        } catch is CancellationError {
        } catch {
            if settings == nil { self.error = errorText(error) }
        }
    }

    private func save() {
        let late = Int(grace), miss = Int(missed), fee = Int(feeGrace)
        guard form.check([
            ("grace", late.map { (5...240).contains($0) } == true ? nil : L("The grace is 5 to 240 minutes.")),
            ("missed", miss.map { (15...720).contains($0) } != true ? L("Missed after is 15 to 720 minutes.")
                : ((miss ?? 0) < (late ?? 0) ? L("Missed after can’t be shorter than the grace.") : nil)),
            ("feeGrace", fee.map { (0...360).contains($0) } == true ? nil : L("The fee grace is 0 to 360 minutes.")),
        ]) else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let saved: HospSettings = try await API.put("/provider-hospital/settings", body: [
                    "lateGraceMinutes": late, "missedAfterMinutes": miss, "feeGraceMinutes": fee,
                    "visitingInfo": visiting.nonEmpty, "dailyFeeItemId": feeItemId.nonEmpty,
                ])
                settings = saved
                fill(saved)
                Toast.show(L("Hospital settings saved."))
                announceDataChanged()
            } catch {
                Toast.error(hospError(error, fallback: "Could not save."))
            }
        }
    }
}
