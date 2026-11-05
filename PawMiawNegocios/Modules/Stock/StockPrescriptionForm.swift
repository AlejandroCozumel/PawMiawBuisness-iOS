//
//  StockPrescriptionForm.swift
//  PawMiawNegocios
//
//  The pieces the prescription sheet is built from (web lib/prescriptions.ts,
//  prescriptions/prescription-medicine-form.tsx, credential-sheet.tsx,
//  client-pet-picker): one medicine as typed and the server's rules for it
//  (what a draft needs, what a signature needs), the medicine's form, the
//  credential a signature asks for, and "who is it for".
//

import SwiftUI

// MARK: - One medicine as typed

struct StockItemDraft: Hashable, Identifiable {
    var key = UUID().uuidString
    var catalogItemId: String?
    var medicineName = ""
    var activeIngredient = ""
    var presentation = ""
    var strength = ""
    var doseAmount = ""
    var doseUnit = ""
    var doseRate = ""
    var doseRateUnit = "mg/kg"
    var route = "oral"
    var everyHours = "12"
    var frequencyText = ""
    var asNeeded = false
    var durationDays = ""
    var quantity = "1"
    var quantityUnit = ""
    var refills = "0"
    var instructions = ""
    var withdrawalPeriod = ""
    var controlSchedule = ""

    var id: String { key }

    init() {}

    /// The draft back from what the server has (to finish a draft).
    init(_ item: StockRxItem) {
        let show: (Double?) -> String = { value in value.map { StockDocWords.number($0) } ?? "" }
        catalogItemId = item.catalogItemId
        medicineName = item.medicineName
        activeIngredient = item.activeIngredient ?? ""
        presentation = item.presentation ?? ""
        strength = item.strength ?? ""
        doseAmount = show(item.doseAmount)
        doseUnit = item.doseUnit ?? ""
        doseRate = show(item.doseRate)
        doseRateUnit = item.doseRateUnit ?? "mg/kg"
        route = item.route ?? ""
        everyHours = show(item.everyHours)
        frequencyText = item.frequencyText ?? ""
        asNeeded = item.asNeeded ?? false
        durationDays = item.durationDays.map(String.init) ?? ""
        quantity = String(item.quantity ?? 1)
        quantityUnit = item.quantityUnit ?? ""
        refills = String(item.refills ?? 0)
        instructions = item.instructions ?? ""
        withdrawalPeriod = item.withdrawalPeriod ?? ""
        controlSchedule = item.controlSchedule ?? ""
    }

    /// A number as the server reads it: a comma is the decimal mark.
    static func number(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    var input: [String: Any?] {
        let dose = Self.number(doseAmount)
        let rate = Self.number(doseRate)
        let hours = asNeeded && everyHours.nonEmpty == nil ? nil : Self.number(everyHours)
        return [
            "catalogItemId": catalogItemId,
            "medicineName": medicineName.nonEmpty,
            "activeIngredient": activeIngredient.nonEmpty,
            "presentation": presentation.nonEmpty,
            "strength": strength.nonEmpty,
            "doseAmount": dose,
            "doseUnit": doseUnit.nonEmpty,
            "doseRate": rate,
            "doseRateUnit": rate != nil ? doseRateUnit.nonEmpty : nil,
            "route": route.nonEmpty,
            "everyHours": hours,
            "frequencyText": frequencyText.nonEmpty,
            "asNeeded": asNeeded,
            "durationDays": Self.number(durationDays).map { Int($0) },
            "quantity": Self.number(quantity).map { Int($0) },
            "quantityUnit": quantityUnit.nonEmpty,
            "refills": Self.number(refills).map { Int($0) } ?? 0,
            "instructions": instructions.nonEmpty,
            "withdrawalPeriod": withdrawalPeriod.nonEmpty,
            "controlSchedule": controlSchedule.nonEmpty,
        ]
    }

    /// "Amoxivet 250 mg tabletas · 1 tableta cada 12 h por 7 días · 14 tabletas".
    func summary(_ language: String) -> String {
        guard let name = medicineName.nonEmpty else { return "" }
        let what = [name, strength.nonEmpty, presentation.nonEmpty].compactMap { $0 }.joined(separator: " ")
        var dose = doseLine(language)
        if dose.isEmpty, let rate = Self.number(doseRate) { dose = "\(StockDocWords.number(rate)) \(doseRateUnit)" }
        let qty = Self.number(quantity).map { Int($0) }
        let dispense = qty.map { q in (quantityUnit.nonEmpty != nil || q != 1) ? "\(q)\(quantityUnit.nonEmpty.map { " \($0)" } ?? "")" : "" } ?? ""
        return [what, dose, dispense].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func doseLine(_ language: String) -> String {
        var parts: [String] = []
        let es = language != "en"
        if let dose = Self.number(doseAmount) { parts.append("\(StockDocWords.number(dose))\(doseUnit.nonEmpty.map { " \($0)" } ?? "")") }
        let hours = asNeeded && everyHours.nonEmpty == nil ? nil : Self.number(everyHours)
        if let hours { parts.append(es ? "cada \(StockDocWords.number(hours)) h" : "every \(StockDocWords.number(hours)) h") }
        else if let text = frequencyText.nonEmpty { parts.append(text) }
        if asNeeded { parts.append(es ? "si es necesario" : "as needed") }
        if let days = Self.number(durationDays).map({ Int($0) }) { parts.append(es ? "por \(days) \(days == 1 ? "día" : "días")" : "for \(days) \(days == 1 ? "day" : "days")") }
        return parts.joined(separator: " ")
    }

    var docItem: StockDocItem {
        StockDocItem(id: key, medicineName: medicineName, strength: strength.nonEmpty, activeIngredient: activeIngredient.nonEmpty, presentation: presentation.nonEmpty,
                     doseAmount: Self.number(doseAmount), doseUnit: doseUnit.nonEmpty, doseRate: Self.number(doseRate), doseRateUnit: doseRateUnit.nonEmpty,
                     route: route.nonEmpty, everyHours: asNeeded && everyHours.nonEmpty == nil ? nil : Self.number(everyHours), frequencyText: frequencyText.nonEmpty,
                     asNeeded: asNeeded, durationDays: Self.number(durationDays).map { Int($0) }, quantity: Self.number(quantity).map { Int($0) } ?? 1,
                     quantityUnit: quantityUnit.nonEmpty, refills: Self.number(refills).map { Int($0) } ?? 0, instructions: instructions.nonEmpty, withdrawalPeriod: withdrawalPeriod.nonEmpty)
    }
}

/// One thing wrong with a medicine, on its field.
struct StockItemProblem: Hashable {
    let field: String
    let message: String
    /// Stops a draft from being saved too; otherwise it only stops the signature.
    let blocksDraft: Bool
}

enum StockRxRules {
    static let maxItems = 10
    static let validDaysMax = 365
    static let doseRateUnits = ["mg/kg", "UI/kg", "mL/kg", "mcg/kg"]
    static let routes = ["oral", "topical", "ophthalmic", "otic", "subcutaneous", "intramuscular", "intravenous", "inhaled", "rectal", "transdermal", "other"]

    static func schedules(_ country: String?) -> [String] {
        switch country?.uppercased() {
        case "MX": ["mx_group_1"]
        case "US": ["us_c2", "us_c3", "us_c4", "us_c5"]
        default: ["controlled_other"]
        }
    }

    static func maxRefills(_ schedule: String?) -> Int {
        switch schedule {
        case "us_c2", "mx_group_1", "controlled_other": 0
        case "us_c3", "us_c4", "us_c5": 5
        default: 12
        }
    }

    static func validity(_ schedule: String?) -> (defaultDays: Int, maxDays: Int) {
        switch schedule {
        case "mx_group_1": (30, 30)
        case "us_c3", "us_c4", "us_c5": (180, 180)
        case "us_c2": (90, 180)
        case "controlled_other": (30, 90)
        default: (180, validDaysMax)
        }
    }

    /// The strictest class on the prescription: it sets how long it is valid.
    static func strictest(_ drafts: [StockItemDraft]) -> String? {
        ["us_c2", "mx_group_1", "controlled_other", "us_c3", "us_c4", "us_c5"].first { s in drafts.contains { $0.controlSchedule == s } }
    }

    static func route(_ route: String) -> String {
        switch route {
        case "oral": L("By mouth")
        case "topical": L("On the skin")
        case "ophthalmic": L("In the eye")
        case "otic": L("In the ear")
        case "subcutaneous": L("Under the skin (SC)")
        case "intramuscular": L("Into the muscle (IM)")
        case "intravenous": L("Into a vein (IV)")
        case "inhaled": L("Inhaled")
        case "rectal": L("Rectal")
        case "transdermal": L("Transdermal")
        default: L("Other@route")
        }
    }

    /// A number typed in the form and why it can't be taken.
    private static func numberProblem(_ text: String, whole: Bool = false, min: Double = .leastNonzeroMagnitude, max: Double? = nil) -> String? {
        guard text.nonEmpty != nil else { return nil }
        guard let value = StockItemDraft.number(text) else { return "unreadable" }
        if value < min { return "not_positive" }
        if whole && value.rounded() != value { return "not_whole" }
        if let max, value > max { return "too_large" }
        return nil
    }

    /// Everything wrong with one medicine, each on its field (web itemDraftProblems).
    static func problems(_ d: StockItemDraft, country: String?) -> [StockItemProblem] {
        var found: [StockItemProblem] = []
        func add(_ field: String, _ message: String, _ blocksDraft: Bool) {
            if !found.contains(where: { $0.field == field }) { found.append(StockItemProblem(field: field, message: message, blocksDraft: blocksDraft)) }
        }
        if d.medicineName.nonEmpty == nil { add("medicineName", L("Name the medicine."), true) }
        if let problem = numberProblem(d.doseAmount) { add("doseAmount", problem == "unreadable" ? L("Write the dose as a number, like 0.5.") : L("The dose must be more than zero."), true) }
        if let problem = numberProblem(d.doseRate) { add("doseRate", problem == "unreadable" ? L("Write the dose by weight as a number, like 10.") : L("The dose by weight must be more than zero."), true) }
        if numberProblem(d.everyHours, max: 168) != nil { add("everyHours", L("Write the hours as a number above 0, up to 168 (a week)."), true) }
        if numberProblem(d.durationDays, whole: true, min: 1, max: 730) != nil { add("durationDays", L("The duration is a number of days from 1 to 730."), true) }
        if numberProblem(d.quantity, whole: true, min: 1, max: 10_000) != nil { add("quantity", L("Say how much to dispense (a whole number from 1)."), true) }
        if numberProblem(d.refills, whole: true, min: 0, max: 12) != nil { add("refills", L("Refills are a whole number from 0 to 12."), true) }
        else if Int(StockItemDraft.number(d.refills) ?? 0) > maxRefills(d.controlSchedule.nonEmpty) { add("refills", L("This controlled medicine allows fewer refills."), true) }
        if let schedule = d.controlSchedule.nonEmpty, !schedules(country).contains(schedule) { add("controlSchedule", L("That controlled class isn’t used in this business’s country."), true) }

        if country?.uppercased() == "MX" && d.activeIngredient.nonEmpty == nil { add("activeIngredient", L("Add the active ingredient (NOM-064 asks for it next to the commercial name)."), false) }
        if StockItemDraft.number(d.doseAmount) == nil && StockItemDraft.number(d.doseRate) == nil && d.instructions.nonEmpty == nil { add("doseAmount", L("Add the dose."), false) }
        let hours = d.asNeeded && d.everyHours.nonEmpty == nil ? nil : StockItemDraft.number(d.everyHours)
        if hours == nil && d.frequencyText.nonEmpty == nil && !d.asNeeded { add("everyHours", L("Say how often it is given."), false) }
        if StockItemDraft.number(d.quantity) == nil { add("quantity", L("Say how much to dispense (a whole number from 1)."), false) }
        return found
    }

    static func sameMedicine(_ a: (catalog: String?, name: String, active: String), _ b: (catalog: String?, name: String, active: String)) -> Bool {
        let key = { (value: String) in value.trimmingCharacters(in: .whitespaces).lowercased() }
        if let id = a.catalog, id == b.catalog { return true }
        if !key(a.name).isEmpty && key(a.name) == key(b.name) { return true }
        return !key(a.active).isEmpty && key(a.active) == key(b.active)
    }

    /// The chart's allergies a medicine looks like (web lib/allergy-match.ts): its name and active
    /// ingredient against each trigger, through the curated families of drugs and foods.
    static func allergyConflicts(_ d: StockItemDraft, sources: [StockAllergySource]) -> [StockAllergyConflict] {
        let candidate = [d.medicineName, d.activeIngredient].filter { !$0.isEmpty }.joined(separator: " ")
        return StockAllergyMatch.findConflicts(candidateName: candidate, allergies: sources)
    }

    /// The triggers of the chart's allergies (by their labels) a medicine looks like.
    static func allergyConflicts(_ d: StockItemDraft, allergies: [String]) -> [String] {
        allergyConflicts(d, sources: allergies.map { StockAllergySource(trigger: $0) }).map(\.trigger)
    }
}

// MARK: - The medicine's form

struct StockMedicineForm: View {
    @Binding var item: StockItemDraft
    let country: String?
    let weightGrams: Int?
    let problems: [StockItemProblem]
    let showDraftProblems: Bool
    let showSignProblems: Bool
    let allergies: [String]
    @ObservedObject var form: FormState
    /// The chart's allergies with their records (the web's sources); the labels above when nil.
    var allergySources: [StockAllergySource]? = nil

    @State private var fromCatalog = true
    @State private var query = ""
    @State private var products: [StockStoreProduct] = []
    @State private var stockOf: StockStoreProduct.Stock?
    @State private var pickedPhoto: String?
    @State private var started = false

    private var mexico: Bool { country?.uppercased() == "MX" }
    private var refillCap: Int { StockRxRules.maxRefills(item.controlSchedule.nonEmpty) }

    private func key(_ field: String) -> String { "\(item.key)-\(field)" }

    /// The message under a field: a number that can't be read shows at once, the rest once someone tried.
    private func error(_ field: String) -> String? {
        if let marked = form.error(key(field)) { return marked }
        guard let problem = problems.first(where: { $0.field == field }) else { return nil }
        let typed = !(fieldValue(field).trimmingCharacters(in: .whitespaces).isEmpty)
        let immediate = problem.blocksDraft && typed && field != "medicineName"
        guard immediate || (problem.blocksDraft ? showDraftProblems : showSignProblems) else { return nil }
        return problem.message
    }

    private func fieldValue(_ field: String) -> String {
        switch field {
        case "doseAmount": item.doseAmount
        case "doseRate": item.doseRate
        case "everyHours": item.everyHours
        case "durationDays": item.durationDays
        case "quantity": item.quantity
        case "refills": item.refills
        case "activeIngredient": item.activeIngredient
        case "controlSchedule": item.controlSchedule
        default: item.medicineName
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModalSection(title: L("Medicine")) {
                PillPicker(options: [(value: true, title: L("From the Catalog")), (value: false, title: L("Write it in"))], selection: $fromCatalog)
                    .accessibilityLabel(L("Where the medicine comes from"))
                    .onChange(of: fromCatalog) { _, catalog in
                        // Writing it in lets go of the Catalog product and keeps its name to edit.
                        if !catalog && item.catalogItemId != nil { item.catalogItemId = nil }
                        if catalog && item.catalogItemId == nil { query = item.medicineName.trimmingCharacters(in: .whitespaces) }
                    }
                if fromCatalog, item.catalogItemId != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 12) {
                            StockProductThumb(photoUrl: pickedPhoto, productKind: "medication")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.medicineName).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(2)
                                FlowLayout(spacing: 6) {
                                    StockRxChip(text: L("from the Catalog"), tone: Theme.blue, icon: "package")
                                    stockChip(stockOf)
                                    if let schedule = StockRxWords.schedule(item.controlSchedule.nonEmpty) { StockRxControlledChip(label: schedule) }
                                }
                            }
                        }
                        PMButton(L("Type it instead"), systemImage: "pen-line", variant: .outline) { fromCatalog = false }
                        Text(L("Its name comes from the Catalog, so the counter and the bill can hand it out against this prescription.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 2))
                } else if fromCatalog {
                    FormField(label: L("Find in the Catalog"), key: key("medicineName"), hint: L("A Catalog product can be dispensed at the counter and on the bill."), form: form) {
                        SearchField(prompt: L("Search a product"), text: $query)
                    }
                    if !products.isEmpty {
                        ListCard(style: .box) {
                            ForEach(Array(products.enumerated()), id: \.element.id) { index, product in
                                if index > 0 { RowDivider() }
                                Button { choose(product) } label: {
                                    HStack(spacing: 12) {
                                        StockProductThumb(photoUrl: product.photoUrl, productKind: product.productKind ?? "medication", size: 40)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(product.name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                            FlowLayout(spacing: 4) {
                                                if product.requiresPrescription == true { StockRxChip(text: L("Prescription only")) }
                                                if product.controlSchedule?.nonEmpty != nil { StockRxControlledChip() }
                                                stockChip(product.stock)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                        HStack(spacing: 6) {
                            Text(LF("No product matches “%@”.", query.trimmingCharacters(in: .whitespaces))).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                            PMButton(L("Write it in"), variant: .link, size: .modal) {
                                if item.medicineName.nonEmpty == nil { item.medicineName = query.trimmingCharacters(in: .whitespaces) }
                                fromCatalog = false
                            }
                        }
                    }
                } else {
                    PMTextField(L("Medicine (commercial name)"), text: $item.medicineName, key: key("medicineName"), form: form, required: true)
                    if let message = error("medicineName"), form.error(key("medicineName")) == nil { fieldError(message) }
                }
                let conflicts = StockRxRules.allergyConflicts(item, sources: allergySources ?? allergies.map { StockAllergySource(trigger: $0) }).map(\.trigger)
                if !conflicts.isEmpty {
                    NoticeCard(tone: .problem, title: LF("It looks like an allergy on the chart: %@.", conflicts.joined(separator: ", ")), message: L("Check it before you sign. It can still be prescribed."), icon: "triangle-alert")
                }
            }

            ModalSection(title: L("What it is")) {
                PMTextField(L("Active ingredient"), text: $item.activeIngredient, key: key("activeIngredient"), form: form, hint: mexico ? L("NOM-064 asks for it next to the commercial name.") : nil, optional: !mexico)
                if let message = error("activeIngredient"), form.error(key("activeIngredient")) == nil { fieldError(message) }
                HStack(alignment: .top, spacing: 10) {
                    PMTextField(L("Strength"), text: $item.strength, prompt: "250 mg")
                    PMTextField(L("Form"), text: $item.presentation, prompt: L("e.g. tablets"))
                }
            }

            ModalSection(title: L("How much"), subtitle: L("To sign: the dose, the dose by weight, or the instructions for the family.")) {
                HStack(alignment: .top, spacing: 10) {
                    StockRxNumberField(label: L("Dose"), text: $item.doseAmount, key: key("doseAmount"), form: form, prompt: "1", decimal: true)
                    PMTextField(L("Unit"), text: $item.doseUnit, prompt: L("tablet, mL, drops"))
                }
                if let message = error("doseAmount"), form.error(key("doseAmount")) == nil { fieldError(message) }
                HStack(alignment: .top, spacing: 10) {
                    StockRxNumberField(label: L("Dose by weight"), text: $item.doseRate, key: key("doseRate"), form: form, prompt: "10", decimal: true)
                    MenuField(label: L("Per"), options: StockRxRules.doseRateUnits.map { (value: $0, title: $0) }, selection: $item.doseRateUnit)
                }
                if let message = error("doseRate"), form.error(key("doseRate")) == nil { fieldError(message) }
                HStack(alignment: .top, spacing: 8) {
                    Glyph("scale", size: 16).padding(.top, 2)
                    Text(doseMaths).fixedSize(horizontal: false, vertical: true)
                }
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }

            ModalSection(title: L("How it is given")) {
                MenuField(label: L("Route"), options: StockRxRules.routes.map { (value: $0, title: StockRxRules.route($0)) }, selection: $item.route)
                HStack(alignment: .top, spacing: 10) {
                    StockRxNumberField(label: L("Every"), text: $item.everyHours, key: key("everyHours"), form: form, prompt: "12", suffix: L("hours"), decimal: true)
                    StockRxNumberField(label: L("For"), text: $item.durationDays, key: key("durationDays"), form: form, prompt: "7", optional: true, suffix: L("days"))
                }
                if let message = error("everyHours") ?? error("durationDays"), form.error(key("everyHours")) == nil, form.error(key("durationDays")) == nil { fieldError(message) }
                ToggleRow(title: L("As needed"),
                          subtitle: item.asNeeded && item.everyHours.nonEmpty == nil ? L("It prints “as needed”, with no fixed interval.")
                            : item.asNeeded ? L("It prints the interval and “as needed”. Empty “Every” if there is no fixed interval.")
                            : L("Given only when the pet needs it, not on a fixed schedule."),
                          isOn: $item.asNeeded)
            }

            ModalSection(title: L("How much to dispense")) {
                HStack(alignment: .top, spacing: 10) {
                    StockRxNumberField(label: L("Quantity"), text: $item.quantity, key: key("quantity"), form: form, prompt: "1")
                    PMTextField(L("Of"), text: $item.quantityUnit, prompt: L("boxes, tablets"))
                }
                if let message = error("quantity"), form.error(key("quantity")) == nil { fieldError(message) }
                StockRxNumberField(label: L("Refills"), text: $item.refills, key: key("refills"), form: form, prompt: "0",
                                 hint: refillCap == 0 ? L("This class allows no refills.") : refillCap < 12 ? LF("Up to %d for this class", refillCap) : L("How many more times it can be filled, up to 12."))
                    .disabled(refillCap == 0 && (item.refills.nonEmpty == nil || item.refills.trimmingCharacters(in: .whitespaces) == "0"))
                if let message = error("refills"), form.error(key("refills")) == nil { fieldError(message) }
            }

            ModalSection(title: L("Controlled")) {
                MenuField(label: L("Controlled medicine"), options: [(value: "", title: mexico ? L("Not controlled (Group II or III)") : L("Not controlled"))] + StockRxRules.schedules(country).map { (value: $0, title: StockRxWords.schedule($0) ?? $0) },
                          selection: $item.controlSchedule, key: key("controlSchedule"), form: form, optional: true)
                    .onChange(of: item.controlSchedule) { _, value in
                        // A class with fewer refills brings the number down to what it allows.
                        if !value.isEmpty { item.refills = String(min(Int(StockItemDraft.number(item.refills) ?? 0), StockRxRules.maxRefills(value))) }
                    }
                if let message = error("controlSchedule") { fieldError(message) }
                if let schedule = item.controlSchedule.nonEmpty {
                    let validity = StockRxRules.validity(schedule)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("What this class asks of the prescription:")).font(Theme.text(14, weight: .bold))
                        ForEach([
                            L("A prescription of its own: no other medicine goes with it."),
                            refillCap == 0 ? L("No refills.") : LF("Up to %d refills.", refillCap),
                            validity.defaultDays == validity.maxDays ? LF("Valid for %d days.", validity.maxDays) : LF("Valid for %d days unless you set fewer or more, up to %d.", validity.defaultDays, validity.maxDays),
                            L("It prints as an original and a copy."),
                            L("A controlled prescription goes on paper, signed by hand — it can’t be sent as a link."),
                        ] + (schedule == "mx_group_1" ? [L("Group I goes on the official prescription pad the health authority assigns; the pharmacy keeps the original.")] : [])
                          + (country?.uppercased() == "US" ? [L("A controlled medicine needs your DEA number on the prescription.")] : []), id: \.self) { line in
                            HStack(alignment: .top, spacing: 8) {
                                Glyph("check", size: 16).foregroundStyle(Theme.blue).padding(.top, 2)
                                Text(line).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                        }
                    }
                } else {
                    Text(L("Choose its class if it is a controlled medicine. Most are not.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }

            ModalSection(title: L("For the family")) {
                PMTextField(L("Instructions for the family"), text: $item.instructions, prompt: L("e.g. Give with food. Finish the course."), hint: LF("%d of 1000 characters", item.instructions.count), optional: true, multiline: true)
                PMTextField(L("Withdrawal time"), text: $item.withdrawalPeriod, hint: L("For animals whose meat, milk or eggs are consumed."), optional: true)
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            fromCatalog = item.catalogItemId != nil || item.medicineName.nonEmpty == nil
        }
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespaces)
            guard text.count >= 2 else { products = []; return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found: [StockStoreProduct] = (try? await API.get("/provider-store/products", query: ["q": text])) ?? []
            products = Array(found.filter { $0.itemType == "product" }.prefix(6))
        }
    }

    /// Web `FieldError`: 14 semibold in the destructive red.
    private func fieldError(_ message: String) -> some View {
        Text(message).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.destructive)
    }

    /// What the shelf holds of the Catalog product (web `CatalogStockChip`).
    @ViewBuilder
    private func stockChip(_ stock: StockStoreProduct.Stock?) -> some View {
        if let available = stock?.available {
            if available <= 0 { StockRxChip(text: L("Out of stock"), tone: Theme.destructive, strong: true) }
            else if stock?.lowStock == true { StockRxChip(text: LF("Low stock: %d", available), tone: Theme.mango, strong: true) }
            else { StockRxChip(text: LF("In stock: %d", available), tone: Theme.lime, strong: true) }
        }
    }

    private var doseMaths: String {
        let kilos = weightGrams.map { Double($0) / 1000 }
        if let rate = StockItemDraft.number(item.doseRate), rate > 0, let kilos, kilos > 0 {
            let total = (rate * kilos * 1000).rounded() / 1000
            let unit = item.doseRateUnit.replacingOccurrences(of: "/kg", with: "")
            return LF("%@ %@ × %@ kg = %@ %@", StockDocWords.number(rate), item.doseRateUnit, StockDocWords.number(kilos), StockDocWords.number(total), unit) + " " + L("For reference: the dose you typed is the one that prints.")
        }
        if let kilos {
            return mexico ? LF("NOM-064 asks for the dose by weight (mg/kg or UI/kg). Type it and the dose for %@ kg is worked out here.", StockDocWords.number(kilos))
                : LF("Type a dose by weight and the dose for %@ kg is worked out here.", StockDocWords.number(kilos))
        }
        return L("No weight on file, so a dose by weight can’t be worked out here.")
    }

    private func choose(_ product: StockStoreProduct) {
        // The class comes with a controlled product, and a controlled medicine has no refills.
        let schedule = product.controlSchedule.flatMap { ["mx_group_1", "us_c2", "us_c3", "us_c4", "us_c5", "controlled_other"].contains($0) ? $0 : nil } ?? ""
        item.catalogItemId = product.catalogItemId
        item.medicineName = product.name
        item.controlSchedule = schedule
        if !schedule.isEmpty { item.refills = "0" }
        stockOf = product.stock
        pickedPhoto = product.photoUrl
        query = ""
        form.clear(key("medicineName"))
    }
}

// MARK: - The credential a signature asks for

// MARK: - Who it is for

/// The client's pet a prescription is written for.
struct StockRxPet: Hashable {
    let clientId: String
    let petId: String
    let petName: String
    var species: String? = nil
    var photoUrl: String? = nil
    var clientName: String? = nil
}
