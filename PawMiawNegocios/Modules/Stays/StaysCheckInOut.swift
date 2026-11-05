//
//  StaysCheckInOut.swift
//  PawMiawNegocios
//
//  Checking a stay in and out (web stay-check-in-sheet.tsx,
//  stay-check-out-sheet.tsx, stay-bill-choice.tsx). Check-in: each pet's
//  vaccines against the stay rules (and "I checked the vaccination card"), its
//  care plan, the belongings and the emergency contact; a stay whose kind
//  needs a signed consent waits for it, and owners and admins may check in
//  anyway with a reason. Check-out: the day it leaves, extras, what to hand
//  back, and the bill (backend docs/charging-flow.md): fully priced it goes to
//  the front desk unless kept a draft; without a bill it asks why.
//

import SwiftUI

// MARK: - Check in

private struct StaysPetDraft: Identifiable, Equatable {
    let stayPetId: String
    var items: [StaysCareItem]
    var notes: String
    var confirmVaccines: Bool
    var id: String { stayPetId }
}

struct StaysCheckInSheet: View {
    let stay: StaysStay
    let onDone: () -> Void

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var intake: StaysIntake?
    @State private var loadError: String?
    @State private var drafts: [StaysPetDraft] = []
    @State private var belongings: [String] = []
    @State private var belongingDraft = ""
    @State private var contactName = ""
    @State private var contactPhone = ""
    @State private var working = false
    @State private var consentMissing: String?
    @State private var askingOverride = false

    private var unconfirmed: Int {
        (intake?.pets ?? []).reduce(0) { total, pet in
            if drafts.first(where: { $0.stayPetId == pet.stayPetId })?.confirmVaccines == true { return total }
            return total + (pet.vaccines ?? []).filter { $0.status != "current" }.count
        }
    }

    private var subtitle: String {
        if let today = stay.today, stay.checkInDay > today {
            // Earlier than booked: the server starts the stay today, so the extra nights count.
            return LF("Arriving early: the stay starts today, until %@ at %@", StaysDay.short(stay.checkOutDay), StaysDay.clock(stay.checkOutTime))
        }
        return LF("Until %@ at %@", StaysDay.short(stay.checkOutDay), StaysDay.clock(stay.checkOutTime))
    }

    var body: some View {
        ProviderModal(title: LF("Check in %@", stay.petNames), subtitle: subtitle, systemImage: "log-in", accent: .aqua,
                      isDirty: intake != nil, form: form, primaryTitle: L("Check in"), isWorking: working,
                      primaryIcon: "log-in", primaryDisabled: intake == nil, footerSummary: vaccinesSummary, onPrimary: { checkIn(override: nil) }) {
            if let consentMissing {
                NoticeCard(tone: .warning, title: LF("%@ can’t check in yet", stay.petNames),
                           message: L("The service needs these consents signed first.") + " " + consentMissing,
                           actionTitle: workspace.isOwnerOrAdmin ? L("Check in anyway") : nil,
                           action: workspace.isOwnerOrAdmin ? { askingOverride = true } : nil)
                    .id("consent")
                // The missing consents, to sign here with the client or send to the family; then check in.
                ConsentsCard(context: StaysActs.consentContext(stay, businessName: workspace.current?.name), bare: true)
            }
            if let intake {
                ForEach(intake.pets ?? []) { pet in petSection(pet) }
                ModalSection(title: L("Belongings"), subtitle: L("What came with them, so it all goes home.")) {
                    if !belongings.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(Array(belongings.enumerated()), id: \.offset) { index, item in
                                Button { belongings.remove(at: index) } label: {
                                    Chip(text: item, tone: .muted, icon: "trash-2")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(L("Remove")) \(item)")
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        TextField(L("e.g. Blue blanket, leash, food bag"), text: $belongingDraft)
                            .fieldChrome()
                            .onSubmit(addBelonging)
                        PMButton(L("Add"), variant: .outline, size: .compact, action: addBelonging)
                    }
                }
                ModalSection(title: L("Emergency contact")) {
                    StaysPlainField(prompt: L("Name"), text: $contactName)
                    StaysPlainField(prompt: L("Phone"), text: $contactPhone, key: "phone", form: form, keyboard: .phonePad)
                }
            } else if let loadError {
                ErrorState(message: loadError) { await load() }
            } else {
                LoadingState()
            }
        }
        .task { await load() }
        .sheet(isPresented: $askingOverride) {
            ConfirmSheet(title: L("Check in without the signed consent?"),
                         message: L("Only owners and admins can. It is written down with your name and the reason."),
                         confirmTitle: L("Check in anyway"), destructive: true, askReason: true, reasonRequired: true, cancelTitle: L("Not now")) { reason in
                try await submit(override: reason ?? "")
            }
        }
    }

    /// The vaccines' state, on the footer's line as on the web (once the pets are read).
    private var vaccinesSummary: AnyView? {
        guard intake != nil else { return nil }
        return AnyView(
            Text(unconfirmed == 0 ? L("Vaccines are in order.") : LP(unconfirmed, "%d vaccine is not confirmed. You can still check in.", "%d vaccines are not confirmed. You can still check in."))
                .font(Theme.text(14, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        )
    }

    private func petSection(_ pet: StaysIntakePet) -> some View {
        let index = drafts.firstIndex { $0.stayPetId == pet.stayPetId }
        let hint: String? = pet.linkedToHousehold != true
            ? L("This pet is not linked to a PawMiaw family, so only your own records are checked. Look at the paper card.")
            : pet.canReadVaccines == false ? L("The family has not shared health records with you. Look at the paper card.") : nil
        let planHint = (pet.suggestedCare ?? []).contains { $0.source == "clinic_record" }
            ? L("Started from the owner’s routines and the medications in your records. Adjust anything for the stay.")
            : pet.canReadRoutines == true && !(pet.suggestedCare ?? []).isEmpty
                ? L("Started from the owner’s own routines. Adjust anything for the stay.")
                : L("What the team does each day. Each item becomes a task on the care board.")
        // Each pet in its own bordered card (web `rounded-card border p-5`, no shadow).
        return Card(padding: 20, spacing: 24, flat: true) {
            HStack {
                Text(pet.petName ?? "").font(.brandHeading(24)).foregroundStyle(Theme.inkStrong)
                Spacer()
                if pet.linkedToHousehold == true {
                    Chip(text: L("From the family’s PawMiaw"), tone: .custom(Theme.lime), icon: "sparkles", percent: 35, ink: Theme.blueText, size: .medium)
                }
            }
            StaysAllergies(allergies: pet.allergies ?? [])
            ModalSection(title: L("Vaccines"), subtitle: hint) {
                ForEach(pet.vaccines ?? [], id: \.key) { vaccine in
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(StaysWords.vaccine(vaccine.key)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            Text(vaccineLine(vaccine)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                        }
                        Spacer(minLength: 6)
                        // Web: a pill in the state's colour at 45%, the words navy.
                        Chip(StaysWords.vaccineStatus(vaccine.status), color: ProviderState.vaccine(vaccine.status).color, percent: 45, size: .medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
                if (pet.vaccines ?? []).isEmpty {
                    Text(L("No vaccines are required for this pet.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                if let index {
                    StaysTickRow(title: L("I checked the vaccination card"), icon: "shield-check", muted: true, isOn: $drafts[index].confirmVaccines)
                }
            }
            ModalSection(title: L("Care plan"), subtitle: planHint) {
                if let index {
                    StaysCarePlanEditor(items: $drafts[index].items, notes: $drafts[index].notes, suggestions: pet.suggestedCare ?? [])
                }
            }
        }
    }

    private func vaccineLine(_ vaccine: StaysVaccineCheck) -> String {
        guard let name = vaccine.matchedName else { return L("No record found") }
        var line = name
        if let until = vaccine.validUntil { line += " · " + LF("valid until %@", StaysDay.format(String(until.prefix(10)), "dMMMyyyy")) }
        if vaccine.assumedOneYear == true { line += " · " + L("no due date recorded, one year assumed") }
        return line
    }

    private func addBelonging() {
        guard let value = belongingDraft.nonEmpty else { return }
        belongings.append(value)
        belongingDraft = ""
    }

    private func load() async {
        do {
            let loaded: StaysIntake = try await API.get("/provider-stays/\(stay.id)/intake")
            intake = loaded
            drafts = (loaded.pets ?? []).map { pet in
                let items = (pet.carePlan?.items ?? []).isEmpty ? (pet.suggestedCare ?? []) : (pet.carePlan?.items ?? [])
                return StaysPetDraft(stayPetId: pet.stayPetId, items: items, notes: pet.carePlan?.notes ?? "", confirmVaccines: false)
            }
            belongings = stay.belongings ?? []
            contactName = stay.emergencyContact?.name ?? loaded.suggestedEmergencyContact?.name ?? ""
            contactPhone = stay.emergencyContact?.phone ?? loaded.suggestedEmergencyContact?.phone ?? ""
            loadError = nil
        } catch is CancellationError {
        } catch {
            loadError = errorText(error)
        }
    }

    private func checkIn(override: String?) {
        // An unfinished number would be kept as the contact to call in an emergency.
        let digits = contactPhone.filter(\.isNumber).count
        guard form.check([("phone", contactPhone.nonEmpty != nil && digits < 8 ? L("Finish the phone number, or leave it empty.") : nil)]) else { return }
        working = true
        Task {
            defer { working = false }
            do {
                try await submit(override: override)
            } catch let api as APIError where api.code == "consent_required" {
                consentMissing = api.message
                form.scrollTarget = nil
                form.scrollTarget = "consent"
            } catch {
                Toast.error(error, fallback: L("Could not check in."))
            }
        }
    }

    private func submit(override: String?) async throws {
        var body: [String: Any?] = [
            "pets": drafts.map { draft -> [String: Any?] in
                [
                    "stayPetId": draft.stayPetId,
                    "confirmVaccines": draft.confirmVaccines,
                    "carePlan": StaysCarePlanEditor.clean(draft.items, draft.notes),
                ]
            },
            "belongings": belongings,
            "emergencyContact": (contactName.nonEmpty != nil && contactPhone.nonEmpty != nil)
                ? ["name": contactName.nonEmpty, "phone": contactPhone.nonEmpty] as [String: Any?]
                : nil,
        ]
        if let override {
            body["overrideConsent"] = true
            body["overrideReason"] = override.nonEmpty
        }
        let _: StaysStay = try await API.post("/provider-stays/\(stay.id)/check-in", body: body)
        // Only a family on PawMiaw hears about it.
        Toast.show(stay.familyOnApp ? LF("%@ checked in. The family has been told.", stay.petNames) : LF("%@ checked in.", stay.petNames))
        announceDataChanged()
        onDone()
        dismiss()
    }
}

// MARK: - Check out

struct StaysCheckOutSheet: View {
    let stay: StaysStay
    let onDone: () -> Void

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var checkOutDay = ""
    @State private var extras: [StaysExtraLine] = []
    @State private var createInvoice = true
    @State private var keepDraft = false
    @State private var noBillReason = ""
    @State private var handedBack: Set<Int> = []
    @State private var leaveBehind = false
    @State private var working = false

    private var canInvoice: Bool { workspace.can(.billingCreateInvoice) }
    private var today: String { stay.today ?? StaysDay.today() }
    private var nights: Int { StaysDay.nights(kind: stay.kind, from: stay.checkInDay, to: checkOutDay.isEmpty ? stay.checkInDay : checkOutDay) }
    private var stayTotal: Int { nights * stay.rate * stay.petCount }
    private var extrasTotal: Int { extras.reduce(0) { $0 + ($1.cents ?? 0) } }
    /// A stay with no rate bills its nights at $0: the server keeps that bill a draft until it has a price.
    private var noRate: Bool { stay.rate <= 0 }
    private var notHandedBack: [String] {
        (stay.belongings ?? []).enumerated().filter { !handedBack.contains($0.offset) }.map(\.element)
    }

    var body: some View {
        ProviderModal(title: LF("Check out %@", stay.petNames), subtitle: stay.clientName, systemImage: "log-out", accent: .aqua,
                      isDirty: !extras.isEmpty || !noBillReason.isEmpty, form: form,
                      primaryTitle: leaveBehind && !notHandedBack.isEmpty ? L("Check out anyway") : L("Check out"),
                      isWorking: working, primaryIcon: "log-out", footerSummary: AnyView(totalSummary), onPrimary: checkOut) {
            ModalSection(title: L("The stay")) {
                // A day of daycare ends the day it started.
                if !stay.isDaycare {
                    DayField(label: L("Leaving on"), day: $checkOutDay, min: stay.checkInDay, max: today < stay.checkInDay ? stay.checkInDay : today)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(stay.petList) { pet in
                        HStack {
                            Text("\(StaysWords.kind(stay.kind)) — \(pet.petName)").font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                            Spacer()
                            Text(noRate ? "\(StaysWords.units(stay.kind, nights)) · \(L("No rate set"))" : "\(StaysWords.units(stay.kind, nights)) × \(Money.format(stay.rate, currency: stay.stayCurrency))")
                                .font(Theme.text(14, weight: noRate ? .semibold : .regular)).foregroundStyle(noRate ? Theme.goldText : Theme.inkSoft)
                        }
                        .padding(.vertical, 4)
                    }
                    if noRate {
                        HStack(alignment: .top, spacing: 6) {
                            Glyph("triangle-alert", size: 14).padding(.top, 1)
                            Text(createInvoice ? L("No rate: the bill stays a draft until you put a price on it.") : L("No rate: nothing to charge for the nights."))
                        }
                        .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.goldText)
                        .padding(.top, 4)
                    }
                    if !checkOutDay.isEmpty && checkOutDay != stay.checkOutDay {
                        Text(checkOutDay > stay.checkOutDay
                             ? LF("Booked until %@; it stayed longer, so the extra nights are charged.", StaysDay.short(stay.checkOutDay))
                             : LF("Booked until %@; charging for the nights actually stayed.", StaysDay.short(stay.checkOutDay)))
                            .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.goldText)
                    }
                }
                .padding(16)
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            }
            StaysExtrasSection(extras: $extras)
            if !(stay.belongings ?? []).isEmpty {
                ModalSection(title: L("Hand back")) {
                    ForEach(Array((stay.belongings ?? []).enumerated()), id: \.offset) { index, item in
                        Button {
                            if handedBack.contains(index) { handedBack.remove(index) } else { handedBack.insert(index) }
                        } label: {
                            HStack(spacing: 12) {
                                Tick(on: handedBack.contains(index))
                                Glyph("package-check", size: 16).foregroundStyle(Theme.blue)
                                Text(item).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            StaysBillChoice(createInvoice: $createInvoice, canInvoice: canInvoice, keepDraft: $keepDraft, noBillReason: $noBillReason, unpriced: noRate, form: form)
        }
        .onAppear {
            guard checkOutDay.isEmpty else { return }
            checkOutDay = stay.isDaycare || today < stay.checkInDay ? stay.checkInDay : today
            createInvoice = canInvoice
        }
    }

    /// The web footer's line: the total, then what is not handed back yet or where the bill goes.
    private var totalSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Money.format(stayTotal + extrasTotal, currency: stay.stayCurrency)).font(.brandHeading(24)).foregroundStyle(Theme.inkStrong)
            if leaveBehind && !notHandedBack.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Glyph("triangle-alert", size: 16)
                    Text(LF("Not handed back yet: %@", notHandedBack.joined(separator: ", ")))
                }
                .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.goldText)
            } else {
                Text(StaysBillChoice.outcome(createInvoice: createInvoice, keepDraft: keepDraft, unpriced: noRate))
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func checkOut() {
        guard form.check([
            ("noBillReason", !createInvoice && noBillReason.nonEmpty == nil ? L("Write why it leaves without a bill.") : nil),
        ]) else { return }
        if !notHandedBack.isEmpty && !leaveBehind {
            leaveBehind = true
            return
        }
        working = true
        Task {
            defer { working = false }
            var body: [String: Any?] = [
                "createInvoice": createInvoice,
                "extras": StaysExtrasSection.payload(extras),
            ]
            body["checkOutDay"] = checkOutDay
            if createInvoice { body["keepDraft"] = keepDraft } else { body["noBillReason"] = noBillReason.nonEmpty }
            do {
                let _: StaysStay = try await API.post("/provider-stays/\(stay.id)/check-out", body: body)
                let toDesk = StaysBillChoice.goesToDesk(createInvoice: createInvoice, keepDraft: keepDraft, unpriced: noRate)
                Toast.show(createInvoice
                    ? (toDesk ? L("Checked out. The bill is at the front desk to be charged.") : L("Checked out. A draft invoice is waiting in Invoices."))
                    : (stay.familyOnApp ? L("Checked out. The family has been told.") : L("Checked out.")))
                announceDataChanged()
                onDone()
                dismiss()
            } catch let api as APIError where api.code == "reason_required" {
                _ = form.check([("noBillReason", L("Write why it leaves without a bill."))])
            } catch {
                Toast.error(error, fallback: L("Could not check out."))
            }
        }
    }
}

/// Extras added at the end (a bath before pickup, a late pickup).
struct StaysExtrasSection: View {
    @Binding var extras: [StaysExtraLine]
    var hint: String = L("A bath before pickup, a late pickup, anything added during the stay.")
    /// The words' placeholder; a home stay's says "What".
    var prompt: String = L("e.g. Bath before pickup")
    var removeIcon: String = "trash-2"
    /// A home stay's finish adds with a blue link (up to 20), a stay's check-out with an outline button.
    var addAsLink: Bool = false

    var body: some View {
        ModalSection(title: L("Extras"), subtitle: hint) {
            // Web: what and how much side by side, no labels (the placeholders say it), a bin.
            ForEach($extras) { $extra in
                HStack(alignment: .center, spacing: 8) {
                    StaysPlainField(prompt: prompt, text: $extra.label)
                    StaysPlainMoney(cents: $extra.cents)
                        .frame(width: 112)
                    IconCircleButton(systemImage: removeIcon, label: L("Remove"), tint: Theme.inkSoft, size: addAsLink ? 36 : 44, bordered: false) {
                        extras.removeAll { $0.id == extra.id }
                    }
                }
            }
            if addAsLink {
                if extras.count < 20 {
                    PMButton(L("Add an extra"), systemImage: "plus", variant: .link, size: .small) { extras.append(StaysExtraLine()) }
                }
            } else {
                PMButton(L("Add an extra"), systemImage: "plus", variant: .outline) { extras.append(StaysExtraLine()) }
            }
        }
    }

    static func payload(_ extras: [StaysExtraLine]) -> [[String: Any?]] {
        extras.compactMap { extra in
            guard let label = extra.label.nonEmpty, let cents = extra.cents, cents > 0 else { return nil }
            return ["label": label, "amountCents": cents]
        }
    }
}

/// One extra line on a stay's bill.
struct StaysExtraLine: Identifiable, Equatable {
    let id = UUID()
    var label = ""
    var cents: Int?
}

/// The bill at the end of a stay or a home stay (docs/charging-flow.md): fully
/// priced it goes to the front desk by itself unless "Keep it a draft to
/// adjust"; a line at $0 keeps it a draft; without a bill, why (the owner's exceptions).
struct StaysBillChoice: View {
    @Binding var createInvoice: Bool
    let canInvoice: Bool
    @Binding var keepDraft: Bool
    @Binding var noBillReason: String
    let unpriced: Bool
    @ObservedObject var form: FormState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToggleRow(title: L("Create the bill"),
                      subtitle: canInvoice ? L("The nights or visits and the extras, on the family’s account.") : L("Ask someone who can create invoices."),
                      isOn: $createInvoice)
                .disabled(!canInvoice)
            if createInvoice {
                ToggleRow(title: L("Keep it a draft to adjust"),
                          subtitle: unpriced
                            ? L("Something has no price yet: it stays a draft until it has one.")
                            : keepDraft ? L("It waits in Invoices › To charge until someone sends it to the front desk.") : L("Off, it goes to the front desk to be charged."),
                          isOn: Binding(get: { keepDraft || unpriced }, set: { keepDraft = $0 }))
                    .disabled(unpriced)
            } else {
                PMTextField(L("Why no bill"), text: $noBillReason, key: "noBillReason", form: form,
                            prompt: L("e.g. Paid in advance, a staff pet"), hint: L("The owner sees why on the day’s exceptions."), required: true)
            }
        }
    }

    /// Where the bill goes, in a few words.
    static func outcome(createInvoice: Bool, keepDraft: Bool, unpriced: Bool) -> String {
        if !createInvoice { return L("No invoice") }
        return keepDraft || unpriced ? L("Goes on a draft invoice") : L("Goes to the front desk to be charged")
    }

    static func goesToDesk(createInvoice: Bool, keepDraft: Bool, unpriced: Bool) -> Bool {
        createInvoice && !keepDraft && !unpriced
    }
}
