//
//  StockPrescriptionSheet.swift
//  PawMiawNegocios
//
//  Writes a prescription and signs it, or finishes a draft (web
//  pharmacy/new-prescription-flow.tsx + prescriptions/prescription-sheet.tsx,
//  prescription-review.tsx): who it is for (from the Pharmacy), the medicines
//  (a list, one edited at a time), what goes for the whole prescription, and a
//  review of it as it will print with whatever still stops the signature. A
//  draft saves from any step with whatever is filled; signing needs a
//  prescribing credential — without one the credential sheet opens here and
//  the signature goes through after it is saved.
//
//  The pet's chart gives its last weight (the dose by weight is worked out
//  from it; with none on file, "Weigh" opens the chart's weight sheet) and
//  its allergies (each medicine is checked against them by the web's
//  allergy matcher). Written in a visit, the diagnosis made in it is the
//  prescription's unless it is changed.
//

import SwiftUI

private enum RxStep: Int { case who, medicines, details, review }

/// A record of the visit, as far as the prescription reads it (its diagnosis).
private struct StockVisitRecord: Decodable {
    let recordType: String?
    let title: String?
    let payload: JSONValue?
}

struct StockPrescriptionSheet: View {
    /// The pet; nil = choose the client and the pet first.
    let pet: StockRxPet?
    /// A draft to finish.
    let draft: StockPrescription?
    var appointmentId: String? = nil
    let onDone: (StockPrescription) -> Void

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()

    @State private var chosenPet: StockRxPet?
    /// The client chosen in the who step (the shared picker), whose pet `chosenPet` is.
    @State private var pickedClient: PickedClient?
    @State private var step: RxStep = .who
    @State private var items: [StockItemDraft] = [StockItemDraft()]
    @State private var editing: String?
    @State private var diagnosis = ""
    @State private var notes = ""
    @State private var validDays = ""
    @State private var dispenseNow = false
    @State private var draftId: String?
    @State private var checked = false
    @State private var signChecked = false
    @State private var saveError: String?
    @State private var removed: (item: StockItemDraft, index: Int)?
    @State private var changed = false
    @State private var saving = false
    @State private var started = false
    @State private var credentialAsk: (prescriptionId: String, type: String?, reason: String)?

    @State private var chart: StockChart?
    /// The same chart as the Clients module reads it, for its weight sheet.
    @State private var weighChart: ClientsChart?
    @State private var weighing = false
    @State private var diagnosisFilled = false
    @State private var credentials: StockMemberCredentials?
    @State private var active: [StockPrescription] = []

    private var rights: StockRxRights { StockRxRights(workspace) }
    private var canSign: Bool { draft?.canSign ?? rights.canSign }
    private var canDispenseAtVisit: Bool { draft?.canDispenseAtVisit ?? rights.canDispenseAtVisit }
    private var visitId: String? { appointmentId ?? draft?.appointmentId }
    private var country: String? { workspace.current?.country }
    private var language: String { draft?.language ?? (LocalizationManager.shared.currentLanguage == .english ? "en" : "es") }
    private var anyControlled: Bool { items.contains { $0.controlSchedule.nonEmpty != nil } }
    private var mixed: Bool { items.count > 1 && anyControlled }
    private var schedule: String? { StockRxRules.strictest(items) }
    private var validity: (defaultDays: Int, maxDays: Int) { StockRxRules.validity(schedule) }
    private var weightGrams: Int? { chart?.weights?.latestGrams ?? chart?.pet?.weightGrams }
    private var allergies: [String] { (chart?.summary?.allergies ?? []).filter { $0.draft != true }.map(\.label) }
    private var allergySources: [StockAllergySource] {
        (chart?.summary?.allergies ?? []).filter { $0.draft != true }.map { StockAllergySource(trigger: $0.label, reaction: $0.detail, recordId: $0.recordId) }
    }
    /// Whoever may weigh the pet (the chart's own rule): "Weigh" is offered when no weight is on file.
    private var canWeigh: Bool { workspace.can(.petsEdit) || workspace.can(.appointmentsEdit) }
    private var problems: [String: [StockItemProblem]] { Dictionary(uniqueKeysWithValues: items.map { ($0.key, StockRxRules.problems($0, country: country)) }) }
    private var asked: Int? { validDays.nonEmpty.flatMap { Int($0) } }
    private var validDaysProblem: Bool { asked.map { $0 < 1 || $0 > StockRxRules.validDaysMax } ?? false }
    private var firstStep: RxStep { pet == nil && draft == nil ? .who : .medicines }

    var body: some View {
        ProviderModal(
            title: step == .who ? L("New prescription") : draft != nil ? L("Finish the prescription") : L("Write a prescription"),
            subtitle: step == .who ? L("Who is it for? Then the medicines.") : L("The medicines, what goes for all of them, then the review to sign."),
            systemImage: "pill",
            accent: .aqua,
            isDirty: changed || step != firstStep || (chosenPet != nil && pet == nil),
            form: form,
            primaryTitle: primaryTitle,
            isWorking: saving,
            steps: step != .who ? ModalSteps(steps: [(L("Medicines"), "pill"), (L("Details"), "clipboard-list"), (canSign ? L("Review and sign") : L("Review"), "pen-line")],
                                             current: max(0, step.rawValue - 1)) : nil,
            onBack: step != firstStep ? { back() } : nil,
            secondaryActions: step != .who && (step != .review || canSign)
                ? [ModalAction(L("Save draft"), icon: "file-plus-2", isWorking: saving) { Task { await handleDraft() } }] : [],
            primaryIcon: step == .review ? (canSign ? "pen-line" : "file-plus-2") : nil,
            onPrimary: primary
        ) {
            if step != .who, let who = chosenPet { context(who) }
            if let saveError { NoticeCard(tone: .problem, title: saveError, icon: "triangle-alert") }
            switch step {
            case .who: whoStep
            case .medicines: medicinesStep
            case .details: detailsStep
            case .review: reviewStep
            }
            Text(L("Format based on public sources; a professional must review it before use.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
        .onAppear(perform: start)
        .task(id: chosenPet?.petId) { await loadContext() }
        .task(id: visitId) { await fillVisitDiagnosis() }
        .sheet(isPresented: $weighing) {
            if let weighChart {
                ClientsWeightSheet(chart: weighChart) { await loadContext() }
            }
        }
        .sheet(isPresented: Binding(get: { credentialAsk != nil }, set: { if !$0 { credentialAsk = nil } })) {
            if let ask = credentialAsk {
                TeamCredentialSheet(memberId: "me", isSelf: true, country: Workspace.shared.current?.country, businessAddress: Workspace.shared.current?.address, types: (ask.type).map { [$0] }, reason: ask.reason) {
                    let id = ask.prescriptionId
                    credentialAsk = nil
                    Task { await signAfterCredential(id) }
                }
            }
        }
    }

    private func start() {
        guard !started else { return }
        started = true
        chosenPet = pet
        if let draft {
            items = draft.items.isEmpty ? [StockItemDraft()] : draft.items.map { StockItemDraft($0) }
            diagnosis = draft.diagnosis ?? ""
            notes = draft.notes ?? ""
            validDays = draft.validDays.map(String.init) ?? ""
            draftId = draft.id
            editing = draft.items.isEmpty ? items.first?.key : nil
        } else {
            editing = items.first?.key
        }
        step = firstStep
    }

    private func loadContext() async {
        guard let who = chosenPet else { return }
        let signs = canSign
        async let chartLoad: Data? = try? API.data("GET", "/provider-clients/\(who.clientId)/pets/\(who.petId)/chart", query: [:], body: nil)
        async let credentialLoad: StockMemberCredentials? = signs ? try? API.get("/provider-members/me/credentials") : nil
        async let activeLoad: StockPrescriptionPage? = try? API.get("/provider-prescriptions", query: ["providerClientPetId": who.petId, "state": "active", "limit": "20"])
        if let data = await chartLoad {
            chart = try? API.decode(data)
            // The weight sheet is the patient chart's own (Clients): it reads the chart its way.
            weighChart = try? API.decode(data)
        }
        credentials = await credentialLoad
        active = (await activeLoad)?.items ?? []
    }

    /// Written in a visit: the diagnosis made in it is the prescription's, unless changed (a draft keeps its own).
    private func fillVisitDiagnosis() async {
        guard draft == nil, !diagnosisFilled, let visitId else { return }
        guard let page: Page<StockVisitRecord> = try? await API.get("/provider-records", query: ["limit": "100", "offset": "0", "appointmentId": visitId]) else { return }
        var seen: [String] = []
        for record in page.items where record.recordType == "diagnosis" {
            let condition = record.payload?["condition"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            guard let text = condition ?? record.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty else { continue }
            if !seen.contains(text) { seen.append(text) }
        }
        guard !seen.isEmpty else { return }
        diagnosisFilled = true
        if diagnosis.trimmingCharacters(in: .whitespaces).isEmpty { diagnosis = seen.joined(separator: ", ") }
    }

    // MARK: Steps

    private var primaryTitle: String {
        switch step {
        case .who: L("Write the prescription")
        case .medicines, .details: L("Continue")
        case .review: canSign ? L("Sign prescription") : L("Save draft")
        }
    }

    private func primary() {
        switch step {
        case .who:
            guard form.check([
                ("client", pickedClient == nil && chosenPet == nil ? L("Choose the client first.") : nil),
                ("pet", pickedClient != nil && chosenPet == nil ? L("Choose the pet it is for.") : nil),
            ]) else { return }
            step = .medicines
        case .medicines:
            guard check(forSigning: false) else { return }
            step = .details
        case .details:
            guard form.check([("validDays", validDaysProblem ? L("A prescription is valid for 1 to 365 days.") : nil)]) else { return }
            step = .review
        case .review:
            Task { canSign ? await handleSign() : await handleDraft() }
        }
    }

    private func back() {
        saveError = nil
        switch step {
        case .who, .medicines: step = firstStep
        case .details: step = .medicines
        case .review: step = .details
        }
    }

    private func touch() {
        changed = true
        saveError = nil
    }

    /// Whose it is, its weight and its class (web `ModalContextPills`: the client with its link
    /// badge once the chart says, the pet with its face, the weight, "Weigh", the class).
    private func context(_ who: StockRxPet) -> some View {
        ContextPills(client: who.clientName?.nonEmpty ?? chart?.client?.name, linked: chart.map { $0.client?.householdId != nil }) {
            contextPill(who.petName.nonEmpty ?? L("Patient"), face: true) {
                PetAvatar(name: who.petName, species: who.species, photoURL: who.photoUrl, size: 20)
            }
            if chart != nil {
                contextPill(weightGrams.map { "\(StockDocWords.number(Double($0) / 1000)) kg" + (chart?.weights?.latestAt.map { " · \(DateText.day($0))" } ?? "") } ?? L("No weight on file")) {
                    Glyph("scale", size: 14)
                }
            }
            if chart != nil && weightGrams == nil && canWeigh && weighChart != nil {
                PMButton(L("Weigh"), systemImage: "scale", variant: .outline, size: .compact) { weighing = true }
            }
            if let schedule, let label = StockRxWords.schedule(schedule) { StockRxControlledChip(label: label) }
        }
    }

    /// One more pill in `ContextPills`' look (32 tall, 12 semibold, the muted fill with a hairline):
    /// the pet with its face, the weight.
    private func contextPill<Mark: View>(_ text: String, face: Bool = false, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 6) {
            mark()
            Text(text).lineLimit(1)
        }
        .font(.brandText(12, weight: .semibold))
        .foregroundStyle(Theme.inkStrong)
        .padding(.leading, face ? 6 : 12)
        .padding(.trailing, 12)
        .frame(minHeight: 32)
        .background(Theme.surfaceMuted, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    @ViewBuilder
    private var whoStep: some View {
        ClientPetPicker(
            client: Binding(get: { pickedClient }, set: { next in
                pickedClient = next
                if chosenPet?.clientId != next?.id { chosenPet = nil }
            }),
            petIds: Binding(get: { chosenPet.map { [$0.petId] } ?? [] }, set: { ids in
                guard let client = pickedClient, let id = ids.first, let pet = client.activePets.first(where: { $0.id == id }) else { chosenPet = nil; return }
                chosenPet = StockRxPet(clientId: client.id, petId: pet.id, petName: pet.name, species: pet.petSpecies, photoUrl: pet.photoUrl, clientName: client.ownerName)
            }),
            petRequired: true,
            form: form
        )
        NoticeCard(tone: .info, message: L("A prescription is written for a client’s pet. A walk-in customer isn’t on the list: add them as a client, with their pet, first."), icon: "info")
    }

    private func medicineLabel(_ index: Int) -> String {
        guard items.indices.contains(index) else { return LF("Medicine %d", index + 1) }
        return items[index].medicineName.nonEmpty.map { LF("Medicine %d: %@", index + 1, $0) } ?? LF("Medicine %d", index + 1)
    }

    private func binding(_ key: String) -> Binding<StockItemDraft> {
        Binding {
            items.first { $0.key == key } ?? StockItemDraft()
        } set: { value in
            if let index = items.firstIndex(where: { $0.key == key }), items[index] != value {
                items[index] = value
                touch()
            }
        }
    }

    @ViewBuilder
    private var medicinesStep: some View {
        if items.isEmpty {
            NoticeCard(tone: .info, title: L("No medicines on this prescription."), message: L("Add at least one medicine."), icon: "pill")
        }
        ForEach(Array(items.enumerated()), id: \.element.key) { index, item in
            medicineRow(item, index: index)
        }
        if let removed {
            HStack {
                Text(LF("%@ was removed.", removed.item.medicineName.nonEmpty ?? LF("Medicine %d", removed.index + 1))).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                Spacer()
                PMButton(L("Undo"), systemImage: "undo-2", variant: .ghost, size: .modal) { undoRemove() }
            }
            .padding(.leading, 12)
            .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        }
        PMButton(items.isEmpty ? L("Add medicine") : L("Add another medicine"), systemImage: "plus", variant: .outline, fullWidth: true) { addMedicine() }
            .disabled(!canAdd)
        if anyControlled {
            Text(L("A controlled medicine goes on a prescription of its own (original and copy).")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        } else if items.count >= StockRxRules.maxItems {
            Text(L("Up to 10 medicines per prescription.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        } else if items.count > 1 {
            Text(L("They print in this order.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
        // The medicine being edited, under the list (the web's second column on a phone).
        if let index = items.firstIndex(where: { $0.key == editing }) {
            let item = items[index]
            VStack(alignment: .leading, spacing: 20) {
                FlowLayout(spacing: 8) {
                    Text(LF("Medicine %d", index + 1).uppercased()).font(.brandText(12, weight: .bold)).tracking(12 * 0.14).foregroundStyle(Theme.inkSoft)
                    HStack(spacing: 6) {
                        Text(L("Required to sign"))
                            .font(.brandText(10.4, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.wash(Theme.mango, 22), in: Capsule())
                        Text(L("A draft saves without them.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
                StockMedicineForm(item: binding(item.key), country: country, weightGrams: weightGrams, problems: problems[item.key] ?? [],
                                  showDraftProblems: checked, showSignProblems: signChecked, allergies: allergies, form: form, allergySources: allergySources)
                    .id(item.key)
                HStack {
                    Spacer()
                    PMButton(L("Done with this medicine"), variant: .outline) { editing = nil }
                }
            }
            .padding(.top, 8)
        } else if !items.isEmpty {
            NoticeCard(tone: .info, message: L("Choose a medicine to edit it, or add another."), icon: "pencil")
        }
    }

    /// One medicine of the list (web: its number, its summary, its chips, then edit, duplicate, move, remove).
    private func medicineRow(_ item: StockItemDraft, index: Int) -> some View {
        let on = item.key == editing
        let pending = (problems[item.key] ?? []).filter { $0.blocksDraft ? (checked || !on) : (signChecked || !on) }.count
        let conflicts = StockRxRules.allergyConflicts(item, sources: allergySources)
        let summary = item.summary(language)
        return VStack(alignment: .leading, spacing: 8) {
            Button { editing = on ? nil : item.key } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)").font(.brandText(12, weight: .heavy)).foregroundStyle(Theme.inkStrong)
                        .frame(width: 24, height: 24).background(Theme.wash(Theme.blue, 16), in: Circle())
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.nonEmpty ?? L("New medicine")).font(Theme.text(14, weight: .bold))
                            .foregroundStyle(summary.isEmpty ? Theme.inkSoft : Theme.inkStrong).multilineTextAlignment(.leading)
                        FlowLayout(spacing: 6) {
                            if item.catalogItemId != nil { StockRxChip(text: L("from the Catalog"), tone: Theme.blue) }
                            if item.controlSchedule.nonEmpty != nil { StockRxControlledChip() }
                            if !conflicts.isEmpty { StockRxChip(text: L("Allergy"), tone: Theme.destructive, icon: "triangle-alert", strong: true) }
                            if pending > 0 { StockRxChip(text: pending == 1 ? L("1 thing to complete") : LF("%d things to complete", pending), tone: Theme.mango, strong: true) }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44, alignment: .top)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
            HStack(spacing: 4) {
                PMButton(on ? L("Done") : L("Edit"), systemImage: "pencil", variant: .ghost, size: .modal) { editing = on ? nil : item.key }
                IconCircleButton(systemImage: "copy", label: LF("Duplicate %@", medicineLabel(index)), tint: Theme.inkStrong, size: 40, bordered: false) { duplicate(index) }
                    .disabled(!canAdd)
                IconCircleButton(systemImage: "arrow-up", label: LF("Move %@ up", medicineLabel(index)), tint: Theme.inkStrong, size: 40, bordered: false) { move(index, by: -1) }
                    .disabled(index == 0)
                IconCircleButton(systemImage: "arrow-down", label: LF("Move %@ down", medicineLabel(index)), tint: Theme.inkStrong, size: 40, bordered: false) { move(index, by: 1) }
                    .disabled(index == items.count - 1)
                Spacer()
                IconCircleButton(systemImage: "trash-2", label: LF("Remove %@", medicineLabel(index)), tint: Theme.destructive, size: 40, bordered: false) { remove(index) }
            }
        }
        .padding(12)
        .background(on ? AnyShapeStyle(Theme.wash(Theme.aqua, 14)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(on ? Theme.blue : Theme.borderSoft, lineWidth: 2))
    }

    private var canAdd: Bool { items.count < StockRxRules.maxItems && !anyControlled }

    private func addMedicine() {
        let next = StockItemDraft()
        items.append(next)
        editing = next.key
        removed = nil
        touch()
    }

    private func duplicate(_ index: Int) {
        var copy = items[index]
        copy.key = UUID().uuidString
        items.insert(copy, at: index + 1)
        editing = copy.key
        touch()
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard items.indices.contains(target) else { return }
        items.swapAt(index, target)
        touch()
    }

    private func remove(_ index: Int) {
        let item = items.remove(at: index)
        removed = (item, index)
        if editing == item.key { editing = nil }
        touch()
    }

    private func undoRemove() {
        guard let removed else { return }
        items.insert(removed.item, at: min(removed.index, items.count))
        self.removed = nil
        touch()
    }

    @ViewBuilder
    private var detailsStep: some View {
        ModalSection(title: L("For the whole prescription")) {
            PMTextField(L("Diagnosis"), text: $diagnosis, hint: L("It prints on the prescription."), optional: true)
                .onChange(of: diagnosis) { _, _ in touch() }
            StockRxNumberField(label: L("Valid for"), text: $validDays, key: "validDays", form: form, prompt: "",
                               hint: schedule.map { LF("Blank: %d days for %@ (at most %d).", validity.defaultDays, StockRxWords.schedule($0) ?? "", validity.maxDays) } ?? L("Blank: 180 days (controlled medicines less)."),
                               optional: true, suffix: L("days"))
                .onChange(of: validDays) { _, _ in touch() }
            PMTextField(L("Notes"), text: $notes, hint: LF("%d of 1000 characters", notes.count), optional: true, multiline: true)
                .onChange(of: notes) { _, _ in touch() }
        }
        ModalSection(title: L("Refills"), subtitle: L("How many more times each medicine can be filled. They are changed on each medicine.")) {
            ListCard(style: .box) {
                ForEach(Array(items.enumerated()), id: \.element.key) { index, item in
                    if index > 0 { RowDivider() }
                    let refills = Int(StockItemDraft.number(item.refills) ?? 0)
                    HStack(spacing: 16) {
                        Text(item.medicineName.nonEmpty ?? LF("Medicine %d", index + 1)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        Spacer(minLength: 8)
                        Text(refills > 0 ? (refills == 1 ? L("1 refill") : LF("%d refills", refills)) : L("No refills")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        PMButton(L("Change"), variant: .link, size: .modal) { step = .medicines; editing = item.key }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
            }
        }
        if visitId != nil && canDispenseAtVisit {
            ModalSection(title: L("At this visit")) {
                ToggleRow(title: L("Hand it out at this visit (adds it to the bill)"), subtitle: L("Its Catalog medicines are added to this visit’s bill when you sign."), isOn: $dispenseNow)
                    .onChange(of: dispenseNow) { _, _ in touch() }
            }
        }
    }

    // MARK: Review

    private struct Blocker: Identifiable {
        let id: String
        let text: String
        let itemKey: String?
        let toDetails: Bool
        let about: String?
    }

    private var blockers: [Blocker] {
        var list: [Blocker] = []
        if items.isEmpty { list.append(Blocker(id: "none", text: L("Add at least one medicine."), itemKey: nil, toDetails: false, about: nil)) }
        if mixed { list.append(Blocker(id: "mixed", text: L("A controlled medicine goes on a prescription of its own."), itemKey: nil, toDetails: false, about: nil)) }
        for (index, item) in items.enumerated() {
            for problem in problems[item.key] ?? [] {
                list.append(Blocker(id: "\(item.key)-\(problem.field)", text: problem.message, itemKey: item.key, toDetails: false, about: medicineLabel(index)))
            }
        }
        if validDaysProblem { list.append(Blocker(id: "valid-days", text: L("A prescription is valid for 1 to 365 days."), itemKey: nil, toDetails: true, about: nil)) }
        return list
    }

    private var warnings: [(id: String, danger: Bool, text: String, detail: String?)] {
        var list: [(id: String, danger: Bool, text: String, detail: String?)] = []
        for (index, item) in items.enumerated() {
            let conflicts = StockRxRules.allergyConflicts(item, sources: allergySources)
            if !conflicts.isEmpty {
                list.append(("allergy-\(item.key)", true, LF("%@ looks like an allergy on the chart: %@.", medicineLabel(index), conflicts.map(\.trigger).joined(separator: ", ")), L("Check it before you sign. It can still be prescribed.")))
            }
        }
        let repeated = items.indices.filter { i in items.indices.contains { j in j != i && StockRxRules.sameMedicine((items[i].catalogItemId, items[i].medicineName, items[i].activeIngredient), (items[j].catalogItemId, items[j].medicineName, items[j].activeIngredient)) } }
        if !repeated.isEmpty {
            list.append(("repeated", false, LF("The same medicine is written more than once: %@.", repeated.map(medicineLabel).joined(separator: "; ")), nil))
        }
        for (index, item) in items.enumerated() where item.medicineName.nonEmpty != nil || item.catalogItemId != nil {
            let same = active.filter { p in p.state == "active" && p.id != draftId && p.items.contains { StockRxRules.sameMedicine((item.catalogItemId, item.medicineName, item.activeIngredient), ($0.catalogItemId, $0.medicineName, $0.activeIngredient ?? "")) } }
            if !same.isEmpty {
                list.append(("active-\(item.key)", false, LF("%@ is already on an active prescription: %@.", medicineLabel(index), same.map { $0.folio ?? "—" }.joined(separator: ", ")), L("Both can be filled unless the earlier one is cancelled.")))
            }
        }
        if let asked, !validDaysProblem, asked > validity.maxDays {
            list.append(("validity", false, LF("This class is valid for %d days at most: it will be valid for %d, not %d.", validity.maxDays, validity.maxDays, asked), nil))
        }
        return list
    }

    @ViewBuilder
    private var reviewStep: some View {
        let blockers = blockers
        let credential = credentials?.items.first { $0.prescribesHere == true }
        if !blockers.isEmpty {
            NoticeCard(tone: .problem, icon: "circle-alert") {
                Text(canSign ? L("Before signing, complete this:") : L("Before a vet signs it, this is missing:")).bold()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(blockers) { blocker in
                        HStack(alignment: .center, spacing: 12) {
                            (Text(blocker.about.map { "\($0): " } ?? "").bold() + Text(blocker.text)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if blocker.itemKey != nil || blocker.toDetails {
                                PMButton(L("Fix"), variant: .link, size: .modal) { fix(blocker) }
                            }
                        }
                    }
                }
                .padding(.top, 6)
                Text(L("A draft saves without them.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).padding(.top, 6)
            }
        } else if canSign {
            NoticeCard(tone: .lime, title: L("Everything a signature needs is here."), icon: "badge-check")
        }
        ForEach(warnings, id: \.id) { warning in
            NoticeCard(tone: warning.danger ? .problem : .warning, title: warning.text, message: warning.detail, icon: "triangle-alert")
        }
        if country?.uppercased() == "US" && anyControlled {
            NoticeCard(tone: .warning, message: L("Controlled substances can’t be prescribed electronically without EPCS-certified software. Print it and sign it by hand; it can’t be sent as a link."), icon: "triangle-alert")
        }
        VStack(alignment: .leading, spacing: 8) {
            if !canSign {
                reviewLine("lock", Theme.inkSoft, L("Your role can’t sign prescriptions. Save it as a draft: a vet with a credential signs it."))
            } else if let credential {
                reviewLine("id-card", Theme.blue, LF("You sign with %@.", [language == "en" ? credential.label?.en : credential.label?.es, credential.number, credential.region].compactMap { $0?.nonEmpty }.joined(separator: " ")))
            } else if credentials != nil {
                reviewLine("id-card", Theme.mango, L("You have no professional credential here yet. Signing asks for it, and the prescription is kept as a draft meanwhile."))
            }
            if canSign && anyControlled && country?.uppercased() == "US" && credentials != nil && credentials?.canPrescribeControlled != true {
                reviewLine("id-card", Theme.mango, L("A controlled medicine needs your DEA number. Add it and the prescription is signed."))
            }
            if canSign { reviewLine("lock", Theme.inkSoft, L("A signed prescription can’t change — cancel it and write a new one.")) }
            if canSign && anyControlled { reviewLine("copy", Theme.inkSoft, L("It prints as an original and a copy.") + " " + L("A controlled prescription goes on paper, signed by hand — it can’t be sent as a link.")) }
            if canSign, let linked = chart?.pet?.linked {
                reviewLine("smartphone", Theme.inkSoft, linked ? L("The family gets it in their PawMiaw app as soon as it is signed.") : L("The family isn’t on PawMiaw, so it doesn’t reach their app: print it for them."))
            }
            if canSign && dispenseNow { reviewLine("badge-check", Theme.blue, L("Its Catalog medicines are added to this visit’s bill when you sign.")) }
        }
        VStack(alignment: .leading, spacing: 8) {
            Text(L("The prescription as it will print")).font(.brandHeading(16.8)).foregroundStyle(Theme.inkStrong)
            StockPrescriptionDocument(header: previewHeader(credential), items: items.map(\.docItem), preview: true)
        }
    }

    /// One line of what signing means (web: a 16 icon in its colour, 14 text).
    private func reviewLine(_ icon: String, _ tint: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Glyph(icon, size: 16).foregroundStyle(tint).padding(.top, 2)
            Text(text).font(Theme.text(14)).foregroundStyle(Theme.inkStrong).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func previewHeader(_ credential: StockCredential?) -> StockDocHeader {
        var header = StockDocHeader(language: language, country: country)
        let today = DateText.dayKey()
        header.signedAt = today
        header.validUntil = StockRules.addDays(today, min(validity.maxDays, (asked ?? 0) > 0 && !validDaysProblem ? asked! : validity.defaultDays) - 1)
        header.controlled = schedule != nil
        header.controlLabel = schedule.flatMap { StockRxWords.schedule($0) }
        header.businessName = workspace.current?.name ?? ""
        header.businessLine = [workspace.current?.address, workspace.current?.phone, workspace.current?.email].compactMap { $0?.nonEmpty }.joined(separator: " · ")
        header.credentialLine = credential.map { [language == "en" ? $0.label?.en : $0.label?.es, $0.number, $0.region].compactMap { $0?.nonEmpty }.joined(separator: " ") }
        header.clientName = chart?.client?.name ?? chosenPet?.clientName
        header.petName = chart?.pet?.name ?? chosenPet?.petName
        header.species = chart?.pet?.species ?? chosenPet?.species
        header.weightKg = weightGrams.map { (Double($0) / 10).rounded() / 100 }
        header.diagnosis = diagnosis.nonEmpty
        header.notes = notes.nonEmpty
        return header
    }

    private func fix(_ blocker: Blocker) {
        checked = true
        signChecked = true
        if blocker.toDetails {
            step = .details
            _ = form.check([("validDays", L("A prescription is valid for 1 to 365 days."))])
        } else if let key = blocker.itemKey {
            goToItem(key, forSigning: true)
        }
    }

    /// Opens a medicine and marks what is wrong with it, scrolling to the first field.
    private func goToItem(_ key: String, forSigning: Bool) {
        step = .medicines
        editing = key
        let found = (problems[key] ?? []).filter { $0.blocksDraft || forSigning }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            _ = form.check(found.map { ("\(key)-\($0.field)", $0.message) })
        }
    }

    // MARK: Saving

    /// What stops this save, pointed at; true when nothing does.
    private func check(forSigning: Bool) -> Bool {
        checked = true
        if forSigning { signChecked = true }
        if items.isEmpty {
            step = .medicines
            saveError = L("Add at least one medicine.")
            Toast.error(saveError ?? "")
            return false
        }
        if mixed {
            step = .medicines
            saveError = L("A controlled medicine goes on a prescription of its own.")
            Toast.error(saveError ?? "")
            return false
        }
        for item in items {
            if (problems[item.key] ?? []).contains(where: { $0.blocksDraft || forSigning }) {
                goToItem(item.key, forSigning: forSigning)
                return false
            }
        }
        if validDaysProblem {
            step = .details
            _ = form.check([("validDays", L("A prescription is valid for 1 to 365 days."))])
            return false
        }
        return true
    }

    private var payload: [String: Any?] {
        [
            "diagnosis": diagnosis.nonEmpty,
            "notes": notes.nonEmpty,
            "validDays": asked,
            "items": items.map { $0.input },
        ]
    }

    private func saveDraft() async throws -> StockPrescription {
        if let draftId {
            return try await StockAPI.send("PATCH", "/provider-prescriptions/\(draftId)", body: payload)
        }
        guard let who = chosenPet else { throw APIError(status: 400, message: L("Choose the pet it is for."), code: nil, fields: [:]) }
        var body = payload
        body["providerClientPetId"] = who.petId
        body["appointmentId"] = visitId
        let created: StockPrescription = try await StockAPI.send("POST", "/provider-prescriptions", body: body)
        draftId = created.id
        return created
    }

    private func done(_ result: StockPrescription, _ message: String) {
        Toast.show(message)
        announceDataChanged()
        onDone(result)
        dismiss()
    }

    private func handleDraft() async {
        guard !saving, check(forSigning: false) else { return }
        saving = true
        saveError = nil
        defer { saving = false }
        do {
            done(try await saveDraft(), L("Saved as a draft. A vet with a credential signs it."))
        } catch {
            await showError(error)
        }
    }

    private func signExisting(_ id: String) async throws {
        let signed: StockPrescription = try await StockAPI.send("POST", "/provider-prescriptions/\(id)/sign", body: ["dispenseAtVisit": dispenseNow])
        done(signed, LF("Signed. %@ is ready to print and share.", signed.folio ?? ""))
    }

    private func handleSign() async {
        guard !saving, check(forSigning: true) else { return }
        saving = true
        saveError = nil
        defer { saving = false }
        do {
            if draftId != nil {
                let saved = try await saveDraft()
                try await signExisting(saved.id)
            } else {
                guard let who = chosenPet else { return }
                var body = payload
                body["providerClientPetId"] = who.petId
                body["appointmentId"] = visitId
                body["sign"] = true
                body["dispenseAtVisit"] = dispenseNow
                let created: StockPrescription = try await StockAPI.send("POST", "/provider-prescriptions", body: body)
                done(created, LF("Signed. %@ is ready to print and share.", created.folio ?? ""))
            }
        } catch let refusal as StockRefusal where refusal.code == "credential_required" || refusal.code == "dea_required" {
            let id = refusal.body["prescriptionId"]?.string ?? draftId
            guard let id else { await showError(refusal); return }
            draftId = id
            let type = refusal.code == "dea_required" ? "dea" : refusal.body["requiredType"]?.string
            let reason: String
            if refusal.code == "dea_required" { reason = L("A controlled medicine needs your DEA number. Add it and the prescription is signed.") }
            else if type == "cedula_profesional" { reason = L("To sign, add your cédula profesional. The prescription is kept as a draft meanwhile.") }
            else if type == "state_license" { reason = L("To sign, add your state license. The prescription is kept as a draft meanwhile.") }
            else { reason = L("To sign, add your professional credential. The prescription is kept as a draft meanwhile.") }
            credentialAsk = (id, type, reason)
        } catch {
            await showError(error)
        }
    }

    private func signAfterCredential(_ id: String) async {
        saving = true
        defer { saving = false }
        do {
            try await signExisting(id)
        } catch {
            await showError(error)
        }
    }

    /// A refused or lost save: the form stays as typed, the reason is said here, and the medicine it is about opens.
    private func showError(_ error: Error) async {
        let refusal = error as? StockRefusal
        if refusal?.code == "prescription_changed" {
            let text = L("This prescription changed while it was being signed. Here it is as it stands now: read it again and sign.")
            Toast.error(text)
            if let id = refusal?.body["prescriptionId"]?.string ?? draftId, let fresh: StockPrescription = try? await API.get("/provider-prescriptions/\(id)") {
                items = fresh.items.isEmpty ? [StockItemDraft()] : fresh.items.map { StockItemDraft($0) }
                diagnosis = fresh.diagnosis ?? ""
                notes = fresh.notes ?? ""
                validDays = fresh.validDays.map(String.init) ?? ""
                draftId = fresh.id
                editing = nil
            }
            step = .review
            saveError = text
            return
        }
        let text = stockIsConnectionError(error)
            ? L("We couldn’t reach PawMiaw, so it isn’t saved. What you wrote is still here: try again.")
            : StockRxWords.error(error, fallback: L("The prescription couldn’t be saved."))
        saveError = text
        Toast.error(text)
        if let index = refusal?.body["index"]?.int, items.indices.contains(index) {
            let key = items[index].key
            step = .medicines
            editing = key
            if refusal?.code == "dose_invalid" {
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    _ = form.check([("\(key)-doseAmount", L("The dose must be more than zero."))])
                }
            }
        }
    }
}
