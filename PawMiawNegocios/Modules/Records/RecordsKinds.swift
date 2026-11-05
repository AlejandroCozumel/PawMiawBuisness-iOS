//
//  RecordsKinds.swift
//  PawMiawNegocios
//
//  The ten kinds of record and the fields each asks for, word for word from
//  the web (lib/pet-record-definitions.ts, care-schedule.tsx,
//  lib/records-copy.ts): their names, the date each one is about, the
//  fields, and how a saved field reads back.
//

import SwiftUI

/// A record type, in the web's VISIBLE_RECORD_TYPES order.
enum RecordsKind: String, CaseIterable, Identifiable, Hashable {
    case vetVisit = "vet_visit"
    case vaccination
    case deworming
    case diagnosis
    case medication
    case allergy
    case labResult = "lab_result"
    case weightCheck = "weight_check"
    case surgery
    case note

    var id: String { rawValue }

    static func of(_ raw: String?) -> RecordsKind { raw.flatMap(RecordsKind.init(rawValue:)) ?? .note }

    /// The lists' and the record page's name (records-copy `recordTypeLabel`).
    var label: String {
        switch self {
        case .vaccination: L("Vaccine")
        case .vetVisit: L("Vet visit")
        case .medication: L("Medicine")
        case .surgery: L("Surgery")
        case .diagnosis: L("Diagnosis")
        case .labResult: L("Lab result")
        case .deworming: L("Deworming")
        case .weightCheck: L("Weight")
        case .allergy: L("Allergy")
        case .note: L("Note")
        }
    }

    /// The record sheet's name (RECORD_TYPE_LABELS).
    var formLabel: String {
        switch self {
        case .vaccination: L("Vaccination")
        case .vetVisit: L("Vet Visit")
        case .medication: L("Medication")
        case .surgery: L("Surgery")
        case .diagnosis: L("Diagnosis")
        case .labResult: L("Lab Result")
        case .deworming: L("Deworming")
        case .weightCheck: L("Weight Check")
        case .allergy: L("Allergy")
        case .note: L("Note")
        }
    }

    var summaryText: String {
        switch self {
        case .vaccination: L("Vaccines, boosters, and immunization follow-ups.")
        case .vetVisit: L("Consults, annual checkups, and specialist visits.")
        case .medication: L("Medication courses, refills, and prescribed treatments.")
        case .surgery: L("Procedures, operations, and post-op history.")
        case .diagnosis: L("Confirmed conditions and clinical findings.")
        case .labResult: L("Lab work, panels, and test results.")
        case .deworming: L("Parasite control treatments and next doses.")
        case .weightCheck: L("Weight snapshots and progress tracking.")
        case .allergy: L("Allergies, sensitivities, and known triggers.")
        case .note: L("General medical notes and owner observations.")
        }
    }

    var titlePlaceholder: String {
        switch self {
        case .vaccination: L("Rabies booster")
        case .vetVisit: L("Annual wellness exam")
        case .medication: L("Amoxicillin 250 mg")
        case .surgery: L("Spay surgery follow-up")
        case .diagnosis: L("Seasonal dermatitis")
        case .labResult: L("CBC and chemistry panel")
        case .deworming: L("Monthly deworming tablet")
        case .weightCheck: L("Weight check")
        case .allergy: L("Chicken sensitivity")
        case .note: L("Behavior change after treatment")
        }
    }

    /// What the record's date is (RECORD_EVENT_DATE_LABELS).
    var eventDateLabel: String {
        switch self {
        case .vaccination: L("Date given")
        case .vetVisit: L("Visit date")
        case .medication: L("Start date")
        case .surgery: L("Procedure date")
        case .diagnosis: L("Date identified")
        case .labResult: L("Result date")
        case .deworming: L("Dose date")
        case .weightCheck: L("Weigh-in date")
        case .allergy: L("First noted")
        case .note: L("Record date")
        }
    }

    /// The web's icon for the kind (care-schedule RECORD_TYPE_ICONS), a Lucide name.
    var systemImage: String {
        switch self {
        case .vaccination: "shield-check"
        case .vetVisit: "stethoscope"
        case .medication: "pill"
        case .surgery: "scissors"
        case .diagnosis: "clipboard-list"
        case .labResult: "flask-conical"
        case .deworming: "microscope"
        case .weightCheck: "scale"
        case .allergy: "triangle-alert"
        case .note: "file-text"
        }
    }

    /// Records are turquoise and a medicine blue, as in the family app (provider-colors `recordTypeHue`).
    var hue: Hue { self == .medication ? .sky : .teal }

    /// A vaccine or a dewormer: its follow-up date is the next dose.
    var hasNextDose: Bool { self == .vaccination || self == .deworming }

    /// The field the title already names: it follows the title until typed apart (TITLE_NAMES_FIELD).
    var titleNamesField: String? {
        switch self {
        case .vaccination: "vaccine_name"
        case .medication: "medication_name"
        case .diagnosis: "condition"
        default: nil
        }
    }

    /// The states a diagnosis, medicine or allergy moves between, in order (the record page's switch).
    var clinicalStates: [String]? {
        switch self {
        case .diagnosis: ["active", "monitoring", "resolved"]
        case .medication: ["active", "completed", "stopped"]
        case .allergy: ["active", "inactive"]
        default: nil
        }
    }

    /// The current state (provider-pet-chart `getProviderRecordClinicalState`).
    func clinicalState(_ payload: [String: JSONValue]?) -> String? {
        let status = payload?["status"]?.string
        switch self {
        case .diagnosis: return status == "monitoring" || status == "resolved" ? status : "active"
        case .medication: return status == "completed" || status == "stopped" ? status : "active"
        case .allergy: return status == "inactive" ? "inactive" : "active"
        default: return nil
        }
    }

    /// A field's value when a new record of this kind starts.
    func defaultValue(_ key: String) -> String {
        switch (self, key) {
        case (.vaccination, "next_due_status"): "scheduled"
        case (.diagnosis, "status"), (.medication, "status"), (.allergy, "status"): "active"
        default: ""
        }
    }

    var fields: [RecordsField] { RecordsField.definitions[self] ?? [] }
}

/// One field a kind of record asks for (RecordFieldDefinition). Labels are English keys, read with `L` when shown.
struct RecordsField: Identifiable {
    enum Input { case text, number, date, select }

    let key: String
    let label: String
    let placeholder: String
    var input: Input = .text
    var helper: String? = nil
    var options: [(value: String, label: String)] = []
    var required: Bool = false
    var requiredWhen: (key: String, value: String)? = nil
    var showWhen: (key: String, value: String)? = nil

    var id: String { key }

    func isRequired(_ values: [String: String]) -> Bool {
        if required { return true }
        guard let rule = requiredWhen else { return false }
        return values[rule.key] == rule.value
    }

    func isShown(_ values: [String: String]) -> Bool {
        if let rule = requiredWhen, values[rule.key] != rule.value { return false }
        if let rule = showWhen, values[rule.key] != rule.value { return false }
        return true
    }

    // MARK: Option lists

    static let diagnosisStatus: [(value: String, label: String)] = [("active", "Active@state"), ("monitoring", "Monitoring"), ("resolved", "Resolved")]
    static let medicationStatus: [(value: String, label: String)] = [("active", "Active@state"), ("completed", "Completed@state")]
    static let allergyStatus: [(value: String, label: String)] = [("active", "Active@state"), ("inactive", "Inactive@state")]
    static let allergySeverity: [(value: String, label: String)] = [("mild", "Mild"), ("moderate", "Moderate"), ("severe", "Severe")]
    static let routes: [(value: String, label: String)] = [
        ("oral", "Oral"), ("topical", "Topical"), ("otic", "Ear"), ("ophthalmic", "Eye"),
        ("injection", "Injection"), ("inhaled", "Inhaled"), ("other", "Other@route"),
    ]
    static let doseUnits: [(value: String, label: String)] = [
        ("mcg", "mcg"), ("mg", "mg"), ("ml", "ml"), ("tablet", "tablet"), ("capsule", "capsule"),
        ("drop", "drop"), ("gram", "gram"), ("unit", "unit"), ("IU", "IU"),
    ]
    static let therapyClasses: [(value: String, label: String)] = [
        ("peptide", "Peptide (prepared before use)"), ("biologic", "Biologic"), ("hormone", "Hormonal"), ("other", "Other medication type"),
    ]
    static let peptideVerification: [(value: String, label: String)] = [
        ("vet_verified", "Verified by veterinarian"), ("vet_directed", "Veterinarian-directed"), ("owner_entered", "Owner-entered / not verified"),
    ]
    static let stopReasons: [String: String] = [
        "vet_advised_stop": "Vet advised stop", "side_effects": "Side effects", "refused": "Pet refused medication",
        "course_changed": "Course changed", "unavailable": "Medication unavailable", "other": "Other",
    ]
    static let noteTags: [String: String] = [
        "vomiting": "Vomiting", "diarrhea": "Diarrhea", "not_eating": "Not eating", "drinking_more": "Drinking more",
        "low_energy": "Low energy", "limping": "Limping", "coughing": "Coughing", "itching": "Itching",
        "injury": "Injury", "behavior_change": "Behavior change",
    ]

    // MARK: The fields of each kind (RECORD_TYPE_FIELD_DEFINITIONS)

    static let definitions: [RecordsKind: [RecordsField]] = [
        .vaccination: [
            RecordsField(key: "vaccine_name", label: "Vaccine name", placeholder: "Nobivac Rabies", required: true),
            RecordsField(key: "manufacturer_brand", label: "Manufacturer / brand", placeholder: "Merck Animal Health"),
            RecordsField(key: "lot_serial_number", label: "Lot / serial number", placeholder: "RB-29401"),
        ],
        .vetVisit: [
            RecordsField(key: "instructions", label: "Instructions", placeholder: "Home care, medication timing, warnings, and what the owner should do next"),
            RecordsField(key: "follow_up_note", label: "Follow-up note", placeholder: "Recheck in 2 weeks if limping continues"),
        ],
        .medication: [
            RecordsField(key: "therapy_class", label: "Therapy class", placeholder: "Medication", input: .select, helper: "Peptide therapies remain medication records so they stay in the medication list and emergency summary.", options: therapyClasses),
            RecordsField(key: "medication_name", label: "Medication", placeholder: "Amoxicillin", required: true),
            RecordsField(key: "dose_amount", label: "Dose amount", placeholder: "1", input: .number, required: true),
            RecordsField(key: "dose_unit", label: "Dose unit", placeholder: "Choose unit", input: .select, options: doseUnits, required: true),
            RecordsField(key: "route", label: "Route", placeholder: "Choose route", input: .select, options: routes, required: true),
            RecordsField(key: "instructions", label: "Instructions", placeholder: "Give with food and finish the full course"),
            RecordsField(key: "peptide_verification_status", label: "Instruction verification", placeholder: "Choose source", input: .select, options: peptideVerification, requiredWhen: ("therapy_class", "peptide"), showWhen: ("therapy_class", "peptide")),
            RecordsField(key: "concentration_label", label: "Concentration from label", placeholder: "e.g. 5 mg / 2 mL", helper: "Copy the exact label or pharmacy wording. PawMiaw does not use this to recommend a dose.", showWhen: ("therapy_class", "peptide")),
            RecordsField(key: "administration_volume_ml", label: "Administration volume (mL)", placeholder: "Exact veterinarian-provided volume", input: .number, showWhen: ("therapy_class", "peptide")),
            RecordsField(key: "injection_site_instructions", label: "Injection-site instructions", placeholder: "Copy the veterinarian-provided site or rotation instructions", showWhen: ("therapy_class", "peptide")),
            RecordsField(key: "status", label: "Status", placeholder: "Choose status", input: .select, helper: "Use this to keep the current medication list accurate.", options: medicationStatus, required: true),
            RecordsField(key: "planned_end_date", label: "Planned end date", placeholder: "Choose a day", input: .date),
        ],
        .surgery: [
            RecordsField(key: "procedure", label: "Procedure", placeholder: "Dental extraction", required: true),
            RecordsField(key: "instructions", label: "Instructions", placeholder: "Keep the incision dry and use the cone at all times"),
            RecordsField(key: "follow_up_note", label: "Follow-up note", placeholder: "Recheck the incision in 10 days"),
        ],
        .diagnosis: [
            RecordsField(key: "condition", label: "Condition", placeholder: "Seasonal dermatitis", required: true),
            RecordsField(key: "status", label: "Status", placeholder: "Choose status", input: .select, options: diagnosisStatus, required: true),
            RecordsField(key: "resolved_date", label: "Resolved date", placeholder: "Choose a day", input: .date, showWhen: ("status", "resolved")),
        ],
        .labResult: [
            RecordsField(key: "test_name", label: "Test name", placeholder: "CBC and chemistry panel", required: true),
            RecordsField(key: "result_summary", label: "Result summary", placeholder: "Mild inflammation markers"),
        ],
        .deworming: [
            RecordsField(key: "product_name", label: "Product", placeholder: "Drontal Plus", required: true),
            RecordsField(key: "dose_amount", label: "Dose amount", placeholder: "1", input: .number),
            RecordsField(key: "dose_unit", label: "Dose unit", placeholder: "Choose unit", input: .select, options: doseUnits),
            RecordsField(key: "route", label: "Route", placeholder: "Choose route", input: .select, options: routes),
            RecordsField(key: "instructions", label: "Instructions", placeholder: "Give with food"),
        ],
        .weightCheck: [
            RecordsField(key: "weight_kg", label: "Weight (kg)", placeholder: "6.4", input: .number, helper: "Used for the detail card and trend tracking.", required: true),
        ],
        .allergy: [
            RecordsField(key: "trigger", label: "Trigger", placeholder: "Chicken", required: true),
            RecordsField(key: "reaction", label: "Reaction", placeholder: "Itchy skin and ear redness"),
            RecordsField(key: "severity", label: "Severity", placeholder: "Choose severity", input: .select, options: allergySeverity),
            RecordsField(key: "status", label: "Status", placeholder: "Choose status", input: .select, options: allergyStatus),
        ],
        .note: [],
    ]

    /// Saved field names as the record page shows them (PAYLOAD_LABEL_OVERRIDES), in the order they read best.
    static let payloadLabels: [(key: String, label: String)] = [
        ("vaccine_name", "Vaccine Name"), ("manufacturer_brand", "Manufacturer / Brand"), ("lot_serial_number", "Lot / Serial Number"),
        ("next_due_date", "Next Due Date"), ("next_due_status", "Next Dose Plan"), ("next_dose_plan", "Next Dose Plan"),
        ("clinic_name", "Clinic"), ("doctor_name", "Doctor"), ("reason", "Reason"), ("instructions", "Instructions"),
        ("follow_up_note", "Follow-up Note"), ("medication_name", "Medication"), ("dose_amount", "Dose Amount"),
        ("dose_unit", "Dose Unit"), ("route", "Route"), ("planned_end_date", "Planned End Date"), ("stop_date", "Stop Date"),
        ("stop_reason", "Stop Reason"), ("stop_note", "Stop Note"), ("procedure", "Procedure"), ("condition", "Condition"),
        ("status", "Status"), ("resolved_date", "Resolved Date"), ("test_name", "Test Name"), ("result_summary", "Result Summary"),
        ("product_name", "Product"), ("weight_kg", "Weight (kg)"), ("trigger", "Trigger"), ("reaction", "Reaction"),
    ]
}

// MARK: - Reading a saved record back

enum RecordsPayload {
    /// A saved field's name in the reader's language (formatPayloadLabel).
    static func label(_ key: String) -> String {
        if let override = RecordsField.payloadLabels.first(where: { $0.key == key }) { return L(override.label) }
        for kind in RecordsKind.allCases {
            if let field = kind.fields.first(where: { $0.key == key }) { return L(field.label) }
        }
        return key.replacingOccurrences(of: "_", with: " ").split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// A saved value as words (formatPayloadEntryValue), "" when there is nothing to say.
    static func value(_ key: String, _ value: JSONValue, kind: RecordsKind? = nil) -> String {
        switch value {
        case .null: return ""
        case .bool(let flag): return flag ? L("Yes") : L("No")
        case .object: return ""
        case .array(let items):
            if key == "tags" {
                return items.compactMap { $0.string }.map { L(RecordsField.noteTags[$0] ?? $0) }.joined(separator: ", ")
            }
            return items.compactMap { $0.string?.nonEmpty }.joined(separator: ", ")
        case .number(let number):
            return number.formatted(.number.locale(.app))
        case .string(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return "" }
            if key == "route", let option = RecordsField.routes.first(where: { $0.value == text }) { return L(option.label) }
            if key == "status" {
                let all = RecordsField.medicationStatus + RecordsField.diagnosisStatus + RecordsField.allergyStatus
                if let option = all.first(where: { $0.value == text }) { return L(option.label) }
                if text == "stopped" { return L("Stopped") }
                return text
            }
            if key == "stop_reason" { return L(RecordsField.stopReasons[text] ?? text) }
            if key == "next_due_status" || key == "next_dose_plan" {
                switch text {
                case "scheduled": return L("Next due date known")
                case "not_applicable", "not_needed": return L("No next dose needed")
                case "unknown": return L("Next due date unknown")
                default: break
                }
            }
            // A choice of the kind's own fields reads as its option's name.
            let kinds = kind.map { [$0] + RecordsKind.allCases } ?? RecordsKind.allCases
            for candidate in kinds {
                if let field = candidate.fields.first(where: { $0.key == key && $0.input == .select }),
                   let option = field.options.first(where: { $0.value == text }) {
                    return L(option.label)
                }
            }
            if text.count == 10, text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
                return RecordsText.longDate(text)
            }
            if text.range(of: #"^\d{4}-\d{2}-\d{2}T"#, options: .regularExpression) != nil {
                return RecordsText.dateTime(text)
            }
            return text
        }
    }

    /// The record's own fields as label + value, the kind's fields first (recordPayloadRows).
    static func rows(_ record: RecordsRecord) -> [(key: String, label: String, value: String)] {
        guard let payload = record.payload, !payload.isEmpty else { return [] }
        let kind = record.kind
        var order: [String] = kind.fields.map(\.key)
        for entry in RecordsField.payloadLabels where !order.contains(entry.key) { order.append(entry.key) }
        let known = Set(order)
        order += payload.keys.filter { !known.contains($0) }.sorted()
        return order.compactMap { key in
            guard let raw = payload[key] else { return nil }
            let text = value(key, raw, kind: kind)
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty, text != "—" else { return nil }
            return (key, label(key), text)
        }
    }

    /// One line of what the record says, never repeating its title (record-row `recordSummaryLine`).
    static func summaryLine(_ record: RecordsRecord) -> String {
        let title = record.titleText
        func same(_ a: String, _ b: String) -> Bool {
            a.trimmingCharacters(in: .whitespaces).lowercased() == b.trimmingCharacters(in: .whitespaces).lowercased()
        }
        func collapse(_ text: String) -> String {
            text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        if let text = record.summary.nonEmpty ?? record.details.nonEmpty {
            return same(text, title) ? "" : collapse(text)
        }
        let payload = record.payload ?? [:]
        let kind = record.kind
        func said(_ key: String) -> String { payload[key].map { value(key, $0, kind: kind) } ?? "" }
        if kind == .medication {
            if let instructions = payload["instructions"]?.string?.nonEmpty { return collapse(instructions) }
            let dose = [said("dose_amount"), said("dose_unit")].filter { !$0.isEmpty }.joined(separator: " ")
            return [dose, said("route")].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return rows(record).map { $0.value }.filter { !same($0, title) }.prefix(3).joined(separator: " · ")
    }
}
