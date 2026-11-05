//
//  StayDetailScreen.swift
//  PawMiawNegocios
//
//  One stay (web stay-detail-sheet.tsx; a home stay opens home-stay-sheet.tsx,
//  StaysHomeStay.swift): its status, room and estimate (or bill), a red
//  banner when it is a day late, the actions for its stage (confirm, check in,
//  report card, check out, change the dates, no-show, cancel, the bill), the
//  guests with their allergies, vaccines and care plan, the family, the times,
//  the notes and the report cards.
//

import SwiftUI

struct StayDetailScreen: View {
    let stayId: String
    @EnvironmentObject private var workspace: Workspace
    @State private var stay: StaysStay?
    @State private var home: StaysHomeDetail?
    @State private var units: [StaysUnit] = []
    @State private var billTotal: Int?
    @State private var error: String?

    var body: some View {
        Group {
            if let stay, stay.isHome, let home {
                StaysHomeStayView(stay: stay, home: home, billTotal: billTotal) { await load() }
            } else if let stay, !stay.isHome {
                StaysStayDetailView(stay: stay, units: units, billTotal: billTotal) { await load() }
            } else if let error {
                PageScroll { ErrorState(message: error) { await load() } }
            } else {
                PageScroll { LoadingState() }
            }
        }
        .providerPage(stay?.petNames ?? L("Stay"))
        .reloadsOnScope { await load() }
    }

    private func load() async {
        do {
            let summary: StaysStay = try await API.get("/provider-stays/\(stayId)")
            if summary.isHome {
                let (full, detail) = try await StaysAPI.homeStay(stayId)
                stay = full
                home = detail
            } else {
                stay = summary
                units = (try? await API.get("/provider-stays/units", query: ["locationId": workspace.locationId])) ?? units
            }
            if let invoiceId = stay?.invoiceId, workspace.can(.billingCreateInvoice) {
                let bill: StaysInvoiceTotal? = try? await API.get("/provider-invoices/\(invoiceId)")
                billTotal = bill?.totalAmount
            } else {
                billTotal = nil
            }
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = errorText(error)
        }
    }
}

private enum StaysDetailSheet: Identifiable {
    case checkIn, checkOut, dates, report, plan, room, close(String)
    var id: String {
        switch self {
        case .checkIn: "in"
        case .checkOut: "out"
        case .dates: "dates"
        case .report: "report"
        case .plan: "plan"
        case .room: "room"
        case .close(let kind): "close-\(kind)"
        }
    }
}

/// A boarding or daycare stay, in full (web stay-detail-sheet.tsx as a page):
/// the header with the pets' photo, its status, room and estimate (or bill)
/// as numbers and the actions for its stage; a red notice when it is a day
/// late; the guests, consents, incidents, the family and times, the notes
/// and the report cards.
private struct StaysStayDetailView: View {
    let stay: StaysStay
    let units: [StaysUnit]
    let billTotal: Int?
    let reload: () async -> Void

    @EnvironmentObject private var workspace: Workspace
    @State private var sheet: StaysDetailSheet?
    @State private var pushed: ProviderRoute?
    @State private var working = false
    /// Counts presses of "Record an incident" in the action row; the incidents card opens its sheet.
    @State private var incidentRequest = 0

    private var canManage: Bool { workspace.can(.staysManage) }
    private var canCare: Bool { workspace.can(.staysCare) }
    private var started: Bool { stay.status == "checked_in" || stay.status == "checked_out" }
    private var today: String { stay.today ?? StaysDay.today() }
    private var actPets: [ActPet] { StaysActs.pets(of: stay) }
    private var consentContext: ConsentContext { StaysActs.consentContext(stay, businessName: workspace.current?.name) }
    /// Its days are over and it never came: change them (or mark the no-show) before checking in.
    private var daysOver: Bool { stay.status != "checked_in" && (stay.checkOutDay < today || (stay.isDaycare && stay.checkInDay < today)) }
    private var hasActions: Bool {
        (stay.isOpen && canManage) || (stay.status == "checked_in" && canCare) || (started && canCare)
            || (stay.invoiceId != nil && workspace.moneyLevel >= .charging)
    }

    var body: some View {
        PageScroll(refresh: { await reload() }) {
            header
            lateBanner
            guests
            // What the family signs before check-in, and anything that happened (docs/consents-incidents.md).
            SectionCard(L("Consents")) {
                ConsentsCard(context: consentContext, bare: true).padding(16)
            }
            SectionCard(L("Incidents")) {
                IncidentsCard(act: ConsentAct(stayId: stay.id), pets: actPets, familyName: stay.clientName,
                              recordable: started, bare: true, recordRequest: incidentRequest, showsRecordButton: false)
                    .padding(16)
            }
            familyAndTimes
            notes
            reportCards
            if let reason = stay.cancellationReason?.nonEmpty { StaysNoteBlock(label: L("Why it closed"), text: reason) }
        }
        .navigationDestination(item: $pushed) { RouteView(route: $0) }
        .sheet(item: $sheet) { which in
            switch which {
            case .checkIn: StaysCheckInSheet(stay: stay) { Task { await reload() } }
            case .checkOut: StaysCheckOutSheet(stay: stay) { Task { await reload() } }
            case .dates: StaysDatesSheet(stay: stay) { Task { await reload() } }
            case .report: StaysReportCardSheet(stayId: stay.id, pets: stay.petList, familyOnApp: stay.familyOnApp) { Task { await reload() } }
            case .plan: StaysCarePlanSheet(stay: stay) { Task { await reload() } }
            case .room: StaysRoomPickSheet(stay: stay, units: units)
            case .close(let kind):
                ConfirmSheet(title: kind == "no_show" ? L("Mark as no-show?") : L("Cancel this stay?"),
                             message: L("The room is freed for these nights. This cannot be undone."),
                             confirmTitle: kind == "no_show" ? L("Mark no-show") : L("Cancel stay"),
                             destructive: true, askReason: true, reasonRequired: false, reasonLabel: L("Reason"), cancelTitle: L("Back")) { reason in
                    let _: StaysStay = try await API.patch("/provider-stays/\(stay.id)", body: ["status": kind, "cancellationReason": reason])
                    Toast.show(kind == "no_show" ? L("Marked as no-show.") : L("Stay cancelled."))
                    announceDataChanged()
                }
            }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        let pet = stay.petList.first
        let subtitle = "\(stay.clientName ?? "") · \(StaysDay.short(stay.checkInDay))\(stay.kind == "boarding" ? " – \(StaysDay.short(stay.checkOutDay))" : "")"
        let media = pet?.photoUrl == nil ? nil : AnyView(PetAvatar(name: pet?.petName, species: pet?.petSpecies, photoURL: pet?.photoUrl, size: 56))
        // The actions for this stage on their own line; a stay with none has no empty line.
        if hasActions {
            ModuleHeader(icon: "bed-double", title: stay.petNames, subtitle: subtitle, accent: Theme.aqua, media: media,
                         stats: headerStats, actionsOnRow: true, storageKey: "stay") { actions }
        } else {
            ModuleHeader(icon: "bed-double", title: stay.petNames, subtitle: subtitle, accent: Theme.aqua, media: media, stats: headerStats, storageKey: "stay")
        }
    }

    private var headerStats: [ModuleStat] {
        let state = ProviderState.stay(stay.status)
        let unitsText = StaysWords.units(stay.kind, stay.billableUnits ?? 1)
        let rateHint: String
        if stay.rate > 0 {
            let extras = billTotal != nil && billTotal != stay.estimatedTotalCents ? " + " + L("extras") : ""
            rateHint = "\(unitsText) × \(Money.format(stay.rate, currency: stay.stayCurrency))\(stay.petList.count > 1 ? " × \(stay.petList.count)" : "")\(extras)"
        } else {
            rateHint = "\(unitsText) · \(L("No rate set"))"
        }
        return [
            ModuleStat("status", label: L("Status"), value: StaysWords.status(stay.status), icon: "circle-dot", accent: state.color,
                       attention: stay.late != nil && stay.isOpen),
            ModuleStat("room", label: L("Room"), value: working ? "…" : (stay.unitName ?? L("No room yet")),
                       hint: stay.isOpen && canManage ? L("Tap to change it") : nil, icon: "bed-double", accent: Theme.aqua,
                       attention: stay.unitName == nil && stay.isOpen,
                       action: stay.isOpen && canManage ? { sheet = .room } : nil),
            ModuleStat("total", label: billTotal != nil ? L("Bill") : L("Estimated total"),
                       value: Money.format(billTotal ?? stay.estimatedTotalCents, currency: stay.stayCurrency),
                       hint: rateHint, icon: billTotal != nil ? "receipt" : "wallet", accent: Theme.lime),
        ]
    }

    // MARK: Late

    @ViewBuilder
    private var lateBanner: some View {
        // A day late either way: what happened and what to do, above everything.
        if let late = stay.late, stay.isOpen {
            NoticeCard(
                tone: .problem,
                title: late == .departure
                    ? LF("%@ was due out %@ at %@ and is still here.", stay.petNames, StaysDay.short(stay.checkOutDay), StaysDay.clock(stay.checkOutTime))
                    : LF("%@ was due in %@ at %@ and hasn’t arrived.", stay.petNames, StaysDay.short(stay.checkInDay), StaysDay.clock(stay.checkInTime)),
                message: late == .departure
                    ? L("The room stays held until you check it out. If the family is staying longer, extend the stay; the nights are counted when it leaves.")
                    : daysOver
                        ? L("Its days are over. Change the dates if the family is still coming, or mark the no-show.")
                        : L("Check it in when it comes, change the dates, or mark the no-show.")
            )
        }
    }

    // MARK: Actions for this stage

    @ViewBuilder
    private var actions: some View {
        if stay.status == "requested" && canManage {
            PMButton(L("Confirm"), systemImage: "calendar-check", isWorking: working) { confirm() }
        }
        if (stay.status == "requested" || stay.status == "confirmed") && !daysOver && canManage {
            PMButton(L("Check in"), systemImage: "log-in") { sheet = .checkIn }
        }
        if stay.status == "checked_in" && canCare {
            PMButton(L("Report card"), systemImage: "message-square-heart") { sheet = .report }
        }
        if stay.status == "checked_in" && canManage {
            PMButton(L("Check out"), systemImage: "log-out") { sheet = .checkOut }
        }
        if stay.isOpen && canManage {
            PMButton(stay.status == "checked_in" ? L("Extend or shorten") : L("Change the dates"), systemImage: "calendar-range", variant: .outline) { sheet = .dates }
        }
        if started && canCare {
            PMButton(L("Record an incident"), systemImage: "shield-alert", variant: .outline) { incidentRequest += 1 }
        }
        if stay.status == "confirmed" && stay.checkInDay <= today && canManage {
            PMButton(L("No-show"), systemImage: "user-x", variant: .outline) { sheet = .close("no_show") }
        }
        if (stay.status == "requested" || stay.status == "confirmed") && canManage {
            PMButton(L("Cancel stay"), systemImage: "circle-x", variant: .outline) { sheet = .close("cancelled") }
        }
        if let invoiceId = stay.invoiceId, workspace.moneyLevel >= .charging {
            PMButton(L("Open the bill"), systemImage: "receipt", variant: .outline) { pushed = .invoice(invoiceId) }
        }
    }

    private func confirm() {
        working = true
        Task {
            defer { working = false }
            do {
                let _: StaysStay = try await API.patch("/provider-stays/\(stay.id)", body: ["status": "confirmed"])
                Toast.show(L("Stay confirmed."))
                announceDataChanged()
            } catch {
                Toast.error(error, fallback: L("Could not change this stay."))
            }
        }
    }

    // MARK: Guests

    private var guests: some View {
        SectionCard(stay.petList.count > 1 ? L("Guests") : L("Guest")) {
            ForEach(Array(stay.petList.enumerated()), id: \.element.id) { index, pet in
                if index > 0 { RowDivider() }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        PetAvatar(name: pet.petName, species: pet.petSpecies, photoURL: pet.photoUrl, size: 48)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pet.petName).font(.brandHeading(20)).foregroundStyle(Theme.inkStrong)
                            Text(pet.petBreed ?? StaysWords.petSpecies(pet.petSpecies)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer(minLength: 0)
                        if let petId = pet.providerClientPetId {
                            IconCircleButton(systemImage: "file-text", label: L("Open the chart"), tint: Theme.blue) { pushed = .patientChart(petId: petId) }
                        }
                    }
                    StaysAllergies(allergies: pet.allergies ?? [])
                    if let checks = pet.vaccineCheck, !checks.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(checks, id: \.key) { StaysVaccineChip(key: $0.key, status: $0.status) }
                            if let name = pet.vaccinesConfirmedByName {
                                Chip(text: LF("Card checked by %@", name), tone: .info, icon: "check")
                            }
                        }
                    }
                    StaysCarePlanList(items: pet.carePlan?.items ?? [])
                    if let notes = pet.carePlan?.notes?.nonEmpty {
                        Text(notes).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                    }
                }
                .padding(16)
            }
            // Once in, the plan can change: a medicine the vet just prescribed, another meal.
            if stay.status == "checked_in" && canManage {
                RowDivider()
                PMButton(L("Edit the care plan"), systemImage: "clipboard-list", variant: .outline, size: .compact) { sheet = .plan }
                    .padding(16)
            }
        }
    }

    // MARK: Family and times

    private var familyAndTimes: some View {
        Card(spacing: 0) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Owner")).font(.brandHeading(16.8)).foregroundStyle(Theme.inkStrong)
                    if let clientId = stay.providerClientId {
                        Button { pushed = .client(clientId) } label: {
                            HStack(spacing: 4) {
                                Text(stay.clientName ?? "").font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                                Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(stay.clientName ?? "").font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    }
                    if let phone = stay.clientPhone?.nonEmpty { PhoneLink(phone: phone) }
                    if let contact = stay.emergencyContact, let name = contact.name?.nonEmpty {
                        Text("\(L("Emergency")): \(name) · \(contact.phone ?? "")").font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Times")).font(.brandHeading(16.8)).foregroundStyle(Theme.inkStrong)
                    // When they really came and went, once they did; the booked times until then.
                    Text(stay.checkedInAt != nil
                         ? "\(L("Arrived")) \(DateText.dayTime(stay.checkedInAt))"
                         : "\(L("Arrives")) \(StaysDay.short(stay.checkInDay)) · \(StaysDay.clock(stay.checkInTime))")
                        .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    Text(stay.checkedOutAt != nil
                         ? "\(L("Left")) \(DateText.dayTime(stay.checkedOutAt))"
                         : "\(L("Leaves")) \(StaysDay.short(stay.checkOutDay)) · \(StaysDay.clock(stay.checkOutTime))")
                        .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                }
            }
        }
    }

    @ViewBuilder
    private var notes: some View {
        let belongings = stay.belongings ?? []
        if stay.ownerInstructions?.nonEmpty != nil || stay.internalNotes?.nonEmpty != nil || !belongings.isEmpty {
            SectionCard(L("Notes")) {
                VStack(alignment: .leading, spacing: 12) {
                    if let text = stay.ownerInstructions?.nonEmpty { StaysNoteBlock(label: L("From the owner"), text: text) }
                    if let text = stay.internalNotes?.nonEmpty { StaysNoteBlock(label: L("For the team"), text: text) }
                    if !belongings.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(Array(belongings.enumerated()), id: \.offset) { Chip(text: $0.element, tone: .muted, icon: "backpack") }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: Report cards

    private var reportCards: some View {
        // Incidents have their own list above; an old report card marked "incident" shows there too.
        let cards = (stay.updates ?? []).filter { $0.kind != "incident" }
        return SectionCard(L("Report cards"),
                           subtitle: cards.isEmpty ? L("Nothing yet. Report cards sent during the stay show up here and in the family’s app.") : nil,
                           icon: nil) {
            if !cards.isEmpty {
                VStack(spacing: 12) {
                    ForEach(cards) { update in
                        StaysReportCardView(update: update, pets: stay.petList, sentToFamily: {
                            let pet = stay.petList.first { $0.id == update.stayPetId }
                            return pet.map { $0.linkedToHousehold == true } ?? stay.familyOnApp
                        }(), zone: workspace.timeZone)
                    }
                }
                .padding(16)
            }
        }
    }
}

/// The stay's room (web: the select in the summary): another room that takes
/// this kind of stay, or none yet.
private struct StaysRoomPickSheet: View {
    let stay: StaysStay
    let units: [StaysUnit]

    @Environment(\.dismiss) private var dismiss
    @State private var unitId: String?
    @State private var working = false
    @State private var started = false

    private var choices: [StaysUnit] {
        units.filter { StaysDay.roomTakes(unitKind: $0.unitKind, stayKind: stay.kind) || $0.id == stay.unitId }
    }

    var body: some View {
        ProviderModal(title: L("Room"), subtitle: stay.petNames, systemImage: "bed-double", accent: .aqua,
                      isDirty: started && unitId != stay.unitId, primaryTitle: L("Save"), isWorking: working,
                      primaryDisabled: unitId == stay.unitId, onPrimary: save) {
            ChoiceCards(options: [(value: Optional<String>.none, title: L("No room yet"), subtitle: Optional<String>.none)]
                        + choices.map { (value: Optional($0.id), title: $0.name, subtitle: Optional(StaysWords.unitKind($0.kind))) },
                        selection: $unitId)
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            guard !started else { return }
            unitId = stay.unitId
            started = true
        }
    }

    private func save() {
        working = true
        Task {
            defer { working = false }
            do {
                let _: StaysStay = try await API.patch("/provider-stays/\(stay.id)", body: ["unitId": unitId])
                Toast.show(L("Room updated."))
                announceDataChanged()
                dismiss()
            } catch {
                Toast.error(error, fallback: L("Could not change this stay."))
            }
        }
    }
}

/// A care plan's items: what, at what time.
struct StaysCarePlanList: View {
    let items: [StaysCareItem]

    var body: some View {
        if !items.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Glyph(StaysWords.taskIcon(item.kind), size: 16).foregroundStyle(Theme.blue)
                        Text(item.time.map { StaysDay.clock($0) } ?? "—").font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft).monospacedDigit()
                        Text(item.label).font(Theme.text(14)).foregroundStyle(Theme.inkStrong).lineLimit(2)
                    }
                }
            }
        }
    }
}

/// A report card as the stay shows it: the photo, who it went to, the mood, the words.
struct StaysReportCardView: View {
    let update: StaysUpdate
    let pets: [StaysPet]
    let sentToFamily: Bool
    let zone: TimeZone

    var body: some View {
        let incident = update.kind == "incident"
        let pet = pets.first { $0.id == update.stayPetId }
        VStack(alignment: .leading, spacing: 0) {
            if let url = APIConfig.assetURL(update.photoUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Theme.surfaceMuted }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipped()
            }
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 6) {
                    Text((incident ? L("Incident · team only") : (sentToFamily ? L("Sent to the family") : L("Report card"))).uppercased())
                        .foregroundStyle(incident ? Theme.coralText : Theme.blue)
                    if let pet { Text("· \(pet.petName)".uppercased()) }
                    if let mood = StaysWords.mood(update.mood) { Text("· \(mood.emoji) \(mood.label)".uppercased()) }
                }
                .font(.brandText(12, weight: .bold))
                .tracking(12 * 0.12)
                .foregroundStyle(Theme.inkSoft)
                if let message = update.message?.nonEmpty {
                    Text(message).font(Theme.text(14)).foregroundStyle(Theme.inkStrong).fixedSize(horizontal: false, vertical: true)
                }
                Text("\(update.authorName ?? L("Your team")) · \(DateText.dayTime(DateText.parse(update.createdAt), zone: zone))")
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(incident ? Theme.pink : Theme.borderSoft, lineWidth: 2))
    }
}
