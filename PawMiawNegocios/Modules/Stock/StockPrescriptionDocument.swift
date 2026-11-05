//
//  StockPrescriptionDocument.swift
//  PawMiawNegocios
//
//  A prescription as paper (web prescriptions/prescription-document.tsx), in
//  the prescription's own language (the business's), with every field its
//  country asks for: the vet, the credential (cédula profesional, state
//  license, DEA), the owner, the animal, each medicine with its active
//  ingredient, dose, dose by weight, route, frequency, duration, quantity,
//  refills and withdrawal time, the legal legend and the signature line. A
//  controlled one prints as an original and a copy. The signed snapshot is
//  the server's; the review step shows a preview built from the form.
//

import SwiftUI

/// One medicine as the document prints it.
struct StockDocItem: Hashable, Identifiable {
    let id: String
    let medicineName: String
    let strength: String?
    let activeIngredient: String?
    let presentation: String?
    let doseAmount: Double?
    let doseUnit: String?
    let doseRate: Double?
    let doseRateUnit: String?
    let route: String?
    let everyHours: Double?
    let frequencyText: String?
    let asNeeded: Bool
    let durationDays: Int?
    let quantity: Int
    let quantityUnit: String?
    let refills: Int
    let instructions: String?
    let withdrawalPeriod: String?

    init(_ item: StockRxItem) {
        id = item.id; medicineName = item.medicineName; strength = item.strength; activeIngredient = item.activeIngredient
        presentation = item.presentation; doseAmount = item.doseAmount; doseUnit = item.doseUnit; doseRate = item.doseRate
        doseRateUnit = item.doseRateUnit; route = item.route; everyHours = item.everyHours; frequencyText = item.frequencyText
        asNeeded = item.asNeeded ?? false; durationDays = item.durationDays; quantity = item.quantity ?? 1; quantityUnit = item.quantityUnit
        refills = item.refills ?? 0; instructions = item.instructions; withdrawalPeriod = item.withdrawalPeriod
    }

    init(id: String, medicineName: String, strength: String?, activeIngredient: String?, presentation: String?, doseAmount: Double?, doseUnit: String?, doseRate: Double?, doseRateUnit: String?, route: String?, everyHours: Double?, frequencyText: String?, asNeeded: Bool, durationDays: Int?, quantity: Int, quantityUnit: String?, refills: Int, instructions: String?, withdrawalPeriod: String?) {
        self.id = id; self.medicineName = medicineName; self.strength = strength; self.activeIngredient = activeIngredient
        self.presentation = presentation; self.doseAmount = doseAmount; self.doseUnit = doseUnit; self.doseRate = doseRate
        self.doseRateUnit = doseRateUnit; self.route = route; self.everyHours = everyHours; self.frequencyText = frequencyText
        self.asNeeded = asNeeded; self.durationDays = durationDays; self.quantity = quantity; self.quantityUnit = quantityUnit
        self.refills = refills; self.instructions = instructions; self.withdrawalPeriod = withdrawalPeriod
    }
}

/// Everything above and below the medicines.
struct StockDocHeader: Hashable {
    var folio: String?
    var signedAt: String?
    var validUntil: String?
    var country: String?
    var language: String
    var legend: String?
    var controlled: Bool
    var controlLabel: String?
    var businessName: String
    var businessLegalName: String?
    var businessLine: String
    var senasica: String?
    var prescriberName: String
    var prescriberTitle: String?
    var credentialLine: String?
    var deaNumber: String?
    var deaAddress: String?
    var clientName: String?
    var clientAddress: String?
    var petName: String?
    var species: String?
    var breed: String?
    var sex: String?
    var age: String?
    var weightKg: Double?
    var microchip: String?
    var diagnosis: String?
    var notes: String?

    init(snapshot s: StockSnapshot) {
        folio = s.folio; signedAt = s.signedAt; validUntil = s.validUntil; country = s.country?.uppercased()
        language = s.language == "en" ? "en" : "es"; legend = s.legend; controlled = s.controlled ?? false; controlLabel = s.controlLabel
        businessName = s.business?.name ?? ""; businessLegalName = s.business?.legalName
        businessLine = [s.business?.address, s.business?.phone, s.business?.email].compactMap { $0?.nonEmpty }.joined(separator: " · ")
        senasica = s.business?.senasica
        prescriberName = s.prescriber?.name ?? ""; prescriberTitle = s.prescriber?.title; credentialLine = s.prescriber?.credentialLine
        deaNumber = s.prescriber?.dea?.number; deaAddress = s.prescriber?.dea?.registeredAddress
        clientName = s.client?.name; clientAddress = s.client?.address
        petName = s.pet?.name; species = s.pet?.species; breed = s.pet?.breed; sex = s.pet?.sex
        age = StockDocWords.age(years: s.pet?.age?.years, months: s.pet?.age?.months, language: language)
        weightKg = s.pet?.weightKg; microchip = s.pet?.microchip; diagnosis = s.diagnosis; notes = s.notes
    }

    init(language: String, country: String?) {
        self.language = language; self.country = country?.uppercased(); controlled = false; businessName = ""; businessLine = ""; prescriberName = ""
    }
}

/// The document's own words, in the prescription's language (web prescription-document.tsx `L`).
enum StockDocWords {
    static func word(_ key: String, _ language: String) -> String {
        let es = language != "en"
        switch key {
        case "prescription": return es ? "Receta médica veterinaria" : "Veterinary prescription"
        case "folio": return es ? "Folio" : "No."
        case "date": return es ? "Fecha" : "Date"
        case "validUntil": return es ? "Vigente hasta" : "Valid until"
        case "vet": return es ? "Médico veterinario" : "Veterinarian"
        case "cedula": return "Cédula profesional"
        case "license": return es ? "Licencia" : "License"
        case "address": return es ? "Domicilio" : "Address"
        case "senasica": return es ? "Registro SENASICA" : "SENASICA registration"
        case "owner": return es ? "Propietario" : "Client"
        case "animal": return es ? "Paciente" : "Patient"
        case "species": return es ? "Especie" : "Species"
        case "sex": return es ? "Sexo" : "Sex"
        case "age": return es ? "Edad" : "Age"
        case "weight": return es ? "Peso" : "Weight"
        case "microchip": return "Microchip"
        case "diagnosis": return es ? "Diagnóstico" : "Diagnosis"
        case "active": return es ? "Principio activo" : "Active ingredient"
        case "presentation": return es ? "Presentación" : "Form"
        case "dose": return es ? "Dosis" : "Dose"
        case "doseRate": return es ? "Dosis por peso" : "Dose by weight"
        case "route": return es ? "Vía" : "Route"
        case "frequency": return es ? "Frecuencia" : "Frequency"
        case "duration": return es ? "Duración" : "Duration"
        case "quantity": return es ? "Cantidad a surtir" : "Quantity to dispense"
        case "refills": return es ? "Resurtidos" : "Refills"
        case "instructions": return es ? "Indicaciones" : "Directions"
        case "withdrawal": return es ? "Tiempo de retiro" : "Withdrawal time"
        case "notes": return es ? "Notas" : "Notes"
        case "signature": return es ? "Firma del médico veterinario" : "Veterinarian’s signature"
        case "original": return es ? "ORIGINAL — para la farmacia" : "ORIGINAL — for the pharmacy"
        case "copy": return es ? "COPIA — para el expediente del médico" : "COPY — for the veterinarian’s record"
        case "controlled": return es ? "Medicamento controlado" : "Controlled substance"
        case "cuantificada": return es ? "Receta cuantificada (Grupo I): el original lo retiene la farmacia que surte; la copia la conserva el médico veterinario. Debe hacerse en el recetario oficial que la autoridad sanitaria asigna." : "Quantified prescription (Group I): the dispensing pharmacy keeps the original; the veterinarian keeps the copy."
        case "usPaper": return es ? "Esta receta se firma a mano; no se puede enviar electrónicamente sin software certificado para controlados." : "This prescription must be signed by hand; it cannot be sent electronically without EPCS-certified software."
        case "dea": return "DEA"
        case "deaAddress": return es ? "Domicilio registrado ante la DEA" : "DEA-registered address"
        case "noRefills": return es ? "Sin resurtidos" : "No refills"
        case "days": return es ? "días" : "days"
        case "every": return es ? "cada" : "every"
        case "asNeeded": return es ? "si es necesario" : "as needed"
        case "verified": return es ? "Integridad verificada" : "Integrity verified"
        case "fingerprint": return es ? "Huella" : "Fingerprint"
        case "review": return es ? "Formato basado en fuentes públicas; debe revisarlo un profesional antes de usarse." : "Format based on public sources; a professional must review it before use."
        case "preview": return es ? "VISTA PREVIA — sin firmar" : "PREVIEW — not signed"
        case "previewNote": return es ? "El folio, la fecha, tu credencial y la leyenda legal se agregan al firmar." : "The number, the date, your credential and the legal legend are added when you sign."
        case "cancelled": return es ? "Cancelada" : "Cancelled"
        default: return key
        }
    }

    static func route(_ route: String?, _ language: String) -> String? {
        guard let route else { return nil }
        let es: [String: String] = ["oral": "Oral", "topical": "Tópica", "ophthalmic": "Oftálmica", "otic": "Ótica", "subcutaneous": "Subcutánea", "intramuscular": "Intramuscular", "intravenous": "Intravenosa", "inhaled": "Inhalada", "rectal": "Rectal", "transdermal": "Transdérmica", "other": "Otra"]
        let en: [String: String] = ["oral": "Oral (PO)", "topical": "Topical", "ophthalmic": "Ophthalmic", "otic": "Otic", "subcutaneous": "Subcutaneous (SC)", "intramuscular": "Intramuscular (IM)", "intravenous": "Intravenous (IV)", "inhaled": "Inhaled", "rectal": "Rectal", "transdermal": "Transdermal", "other": "Other"]
        return (language == "en" ? en : es)[route] ?? route
    }

    static func species(_ value: String?, _ language: String) -> String? {
        guard let value = value?.nonEmpty else { return nil }
        let es: [String: String] = ["dog": "Perro", "cat": "Gato", "bird": "Ave", "rabbit": "Conejo", "horse": "Caballo", "reptile": "Reptil", "other": "Otra"]
        let en: [String: String] = ["dog": "Dog", "cat": "Cat", "bird": "Bird", "rabbit": "Rabbit", "horse": "Horse", "reptile": "Reptile", "other": "Other"]
        return (language == "en" ? en : es)[value.lowercased()] ?? value
    }

    static func sex(_ value: String?, _ language: String) -> String? {
        guard let value = value?.nonEmpty else { return nil }
        switch value.lowercased() {
        case "female": return language == "en" ? "Female" : "Hembra"
        case "male": return language == "en" ? "Male" : "Macho"
        default: return "—"
        }
    }

    static func age(years: Int?, months: Int?, language: String) -> String? {
        guard years != nil || months != nil else { return nil }
        let y = years ?? 0, m = months ?? 0
        if language == "en" {
            return y > 0 ? "\(y) \(y == 1 ? "year" : "years")\(m > 0 ? " \(m) \(m == 1 ? "month" : "months")" : "")" : "\(m) \(m == 1 ? "month" : "months")"
        }
        return y > 0 ? "\(y) \(y == 1 ? "año" : "años")\(m > 0 ? " \(m) \(m == 1 ? "mes" : "meses")" : "")" : "\(m) \(m == 1 ? "mes" : "meses")"
    }

    static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%g", value)
    }

    /// "26 de septiembre de 2026" for a day, in the prescription's language.
    static func longDay(_ value: String?, _ language: String) -> String {
        guard let raw = value?.nonEmpty else { return "—" }
        let date: Date?
        if raw.count == 10 { date = DateText.dayFormatter(TimeZone(identifier: "UTC")!).date(from: raw) } else { date = DateText.parse(raw) }
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == "en" ? "en_US" : "es_MX")
        formatter.timeZone = raw.count == 10 ? TimeZone(identifier: "UTC") : Workspace.shared.timeZone
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}

/// One page of the prescription (or, for a controlled one, the original and the copy).
struct StockPrescriptionDocument: View {
    /// The paper's own corner (web `.prescription-document`, 1.25rem): no shared token is 20.
    private static let paperRadius: CGFloat = 20

    let header: StockDocHeader
    let items: [StockDocItem]
    var preview: Bool = false
    var cancelled: Bool = false
    var integrity: StockPrescription.Integrity? = nil

    var body: some View {
        VStack(spacing: 16) {
            if header.controlled && !preview {
                page(copy: "original")
                page(copy: "copy")
            } else {
                page(copy: nil)
            }
        }
    }

    private func w(_ key: String) -> String { StockDocWords.word(key, header.language) }

    private func page(copy: String?) -> some View {
        let mx = header.country == "MX"
        let credentialLabel = mx ? w("cedula") : w("license")
        return VStack(alignment: .leading, spacing: 0) {
            if preview { band(w("preview"), color: Theme.mango, percent: 18) }
            if let copy { band(copy == "original" ? w("original") : w("copy"), color: Theme.coral, percent: 12) }
            // The business and the folio.
            VStack(alignment: .leading, spacing: 6) {
                Text(header.businessLegalName?.nonEmpty ?? header.businessName).font(.brandHeading(20)).foregroundStyle(Theme.inkStrong)
                if let legal = header.businessLegalName?.nonEmpty, legal != header.businessName { Text(header.businessName).font(Theme.text(14)) }
                if !header.businessLine.isEmpty { Text(header.businessLine).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                if mx, let senasica = header.senasica?.nonEmpty { Text("\(w("senasica")): \(senasica)").font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                RowDivider().padding(.vertical, 4)
                Text(w("prescription").uppercased()).font(.brandText(11.2, weight: .heavy)).tracking(11.2 * 0.14).foregroundStyle(Theme.inkSoft)
                Text("\(w("folio")) \(preview ? "—" : (header.folio ?? "—"))").font(.system(.body, design: .monospaced).bold())
                Text("\(w("date")): \(StockDocWords.longDay(header.signedAt, header.language))").font(Theme.text(14))
                Text("\(w("validUntil")): \(StockDocWords.longDay(header.validUntil, header.language))").font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
            .padding(16)
            RowDivider()
            facts([
                (w("vet"), [header.prescriberName.nonEmpty, header.prescriberTitle?.nonEmpty].compactMap { $0 }.joined(separator: ", ")),
                (credentialLabel, withoutLabel(header.credentialLine, credentialLabel)),
            ] + (header.deaNumber != nil ? [(w("dea"), header.deaNumber ?? ""), (w("deaAddress"), header.deaAddress ?? "")] : []) + [
                (w("owner"), header.clientName ?? ""),
                (w("address"), header.clientAddress ?? ""),
            ])
            RowDivider()
            facts([
                (w("animal"), header.petName ?? ""),
                (w("species"), [StockDocWords.species(header.species, header.language), header.breed?.nonEmpty].compactMap { $0 }.joined(separator: " · ")),
                (w("sex"), StockDocWords.sex(header.sex, header.language) ?? ""),
                (w("age"), header.age ?? ""),
                (w("weight"), header.weightKg.map { "\(StockDocWords.number($0)) kg" } ?? ""),
            ] + (header.microchip?.nonEmpty != nil ? [(w("microchip"), header.microchip ?? "")] : []) + (header.diagnosis?.nonEmpty != nil ? [(w("diagnosis"), header.diagnosis ?? "")] : []))
            RowDivider()
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    itemCard(item, index: index, mx: mx)
                }
                if let notes = header.notes?.nonEmpty {
                    (Text("\(w("notes")): ").bold() + Text(notes)).font(Theme.text(14))
                }
            }
            .padding(16)
            RowDivider()
            VStack(alignment: .leading, spacing: 8) {
                if let legend = header.legend?.nonEmpty { Text(legend).font(Theme.text(14, weight: .heavy)) }
                if header.controlled {
                    (Text("\(w("controlled"))\(header.controlLabel.map { " · \($0)" } ?? ""). ").bold() + Text(mx ? w("cuantificada") : w("usPaper")))
                        .font(Theme.text(12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.wash(Theme.coral, 12), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                }
                Spacer().frame(height: 64)
                Rectangle().fill(Theme.inkStrong).frame(height: 1)
                Text(w("signature")).font(Theme.text(12, weight: .bold)).frame(maxWidth: .infinity)
                Text([header.prescriberName.nonEmpty, header.credentialLine?.nonEmpty].compactMap { $0 }.joined(separator: " · ")).font(Theme.text(12)).frame(maxWidth: .infinity)
            }
            .padding(16)
            RowDivider()
            HStack(alignment: .top, spacing: 6) {
                if preview {
                    Text(w("previewNote"))
                } else {
                    Glyph(integrity?.verified == false ? "triangle-alert" : "shield-check", size: 14)
                        .foregroundStyle(integrity?.verified == false ? Theme.destructive : Theme.blue)
                    Text(integrity?.verified == false ? "!" : w("verified"))
                    if let sha = integrity?.sha256?.nonEmpty { Text("· \(w("fingerprint")) \(String(sha.prefix(12)))").font(.system(.caption2, design: .monospaced)) }
                }
                Spacer()
            }
            .font(.brandText(10.9)).foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 20).padding(.top, 8)
            Text(w("review")).font(.brandText(10.9)).foregroundStyle(Theme.inkSoft).padding(.horizontal, 20).padding(.bottom, 8)
        }
        .foregroundStyle(Theme.inkStrong)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Self.paperRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Self.paperRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.paperRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        .overlay {
            if cancelled {
                Text(w("cancelled").uppercased())
                    .font(.system(size: 52, weight: .black))
                    .foregroundStyle(Theme.coral.opacity(0.3))
                    .tracking(4)
                    .rotationEffect(.degrees(-18))
                    .allowsHitTesting(false)
            }
        }
    }

    /// The "preview" or "original / copy" band across the top (web: 12 extrabold, tracked, the tone washed).
    private func band(_ text: String, color: Color, percent: Double) -> some View {
        VStack(spacing: 0) {
            Text(text).font(.brandText(12, weight: .heavy)).tracking(12 * 0.12)
                .frame(maxWidth: .infinity).padding(.vertical, 6).padding(.horizontal, 20)
                .background(Theme.wash(color, percent))
            RowDivider()
        }
    }

    private func withoutLabel(_ value: String?, _ label: String) -> String {
        let text = (value ?? "").trimmingCharacters(in: .whitespaces)
        return text.lowercased().hasPrefix(label.lowercased() + " ") ? String(text.dropFirst(label.count)).trimmingCharacters(in: .whitespaces) : text
    }

    private func facts(_ pairs: [(String, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .topLeading)], alignment: .leading, spacing: 8) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in fact(pair.0, pair.1) }
        }
        .padding(16)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.brandText(9.9, weight: .heavy)).tracking(0.99).foregroundStyle(Theme.inkSoft)
            Text(value.nonEmpty ?? "—").font(Theme.text(14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func itemCard(_ item: StockDocItem, index: Int, mx: Bool) -> some View {
        let frequency: String = item.everyHours.map { "\(w("every")) \(StockDocWords.number($0)) h\(item.asNeeded ? " · \(w("asNeeded"))" : "")" }
            ?? [item.frequencyText?.nonEmpty, item.asNeeded ? w("asNeeded") : nil].compactMap { $0 }.joined(separator: " · ")
        var pairs: [(String, String)] = [(w("active"), item.activeIngredient ?? "")]
        if let presentation = item.presentation?.nonEmpty { pairs.append((w("presentation"), presentation)) }
        pairs.append((w("dose"), item.doseAmount.map { "\(StockDocWords.number($0))\(item.doseUnit.map { " \($0)" } ?? "")" } ?? ""))
        if item.doseRate != nil || mx { pairs.append((w("doseRate"), item.doseRate.map { "\(StockDocWords.number($0)) \(item.doseRateUnit ?? "")" } ?? "")) }
        pairs.append((w("route"), StockDocWords.route(item.route, header.language) ?? ""))
        pairs.append((w("frequency"), frequency))
        pairs.append((w("duration"), item.durationDays.map { "\($0) \(w("days"))" } ?? ""))
        pairs.append((w("quantity"), "\(item.quantity)\(item.quantityUnit?.nonEmpty.map { " \($0)" } ?? "")"))
        pairs.append((w("refills"), item.refills > 0 ? "\(item.refills)" : w("noRefills")))
        if let withdrawal = item.withdrawalPeriod?.nonEmpty { pairs.append((w("withdrawal"), withdrawal)) }
        return VStack(alignment: .leading, spacing: 8) {
            (Text("Rx \(index + 1). ").foregroundColor(Theme.inkSoft) + Text(item.medicineName) + Text(item.strength?.nonEmpty.map { " · \($0)" } ?? "").font(Theme.text(16, weight: .semibold)))
                .font(.brandHeading(18))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .topLeading)], alignment: .leading, spacing: 6) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in fact(pair.0, pair.1) }
            }
            if let instructions = item.instructions?.nonEmpty {
                (Text("\(w("instructions")): ").bold() + Text(instructions)).font(Theme.text(14))
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }
}
