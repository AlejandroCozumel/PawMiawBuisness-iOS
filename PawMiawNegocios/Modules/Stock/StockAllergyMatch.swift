//
//  StockAllergyMatch.swift
//  PawMiawNegocios
//
//  The allergy cross-check of the prescription sheet (web lib/allergy-match.ts,
//  the same rules as PawMiaw's family app AllergyMatch.swift): a best-effort,
//  name-based heads-up when a medicine looks like a recorded allergy trigger
//  on the pet's chart. Not a clinical interaction checker: matching is on
//  names, with a small curated alias map for the common drug families and food
//  groups, in English and Spanish (Mexico). Its words say "check it", never
//  "safe" or "unsafe". Keep the lists identical to the web's.
//

import Foundation

/// An active allergy on the chart.
nonisolated struct StockAllergySource: Equatable {
    let trigger: String
    var reaction: String? = nil
    var petName: String? = nil
    var recordId: String? = nil
}

/// A trigger that looks like it matches the medicine.
nonisolated struct StockAllergyConflict: Equatable {
    let trigger: String
    let reaction: String?
    /// Whether the match was literal (`name`) or expanded through the alias map.
    let via: Via
    enum Via { case name, related }
}

nonisolated enum StockAllergyMatch {
    // Dosage, form, and filler words that should never count as an allergen
    // match, in English and in Spanish (Mexico). Written as `normalize` leaves
    // them: lowercase, no accents. Keep this list and the groups below identical
    // to pawmiaw-web `src/lib/allergy-match.ts` (`scripts/check-allergy-match.sh`
    // compares them and runs the shared cases).
    static let noiseTokens: Set<String> = [
        "mg", "ml", "g", "kg", "mcg", "iu", "l",
        "tablet", "tablets", "tab", "tabs", "capsule", "capsules", "cap", "caps",
        "drop", "drops", "chew", "chews", "chewable", "pill", "pills",
        "oral", "otic", "ophthalmic", "injection", "inj", "topical", "spray",
        "solution", "suspension", "ointment", "cream", "gel", "powder", "liquid",
        "bottle", "tube", "bag", "can", "pouch", "sachet", "jar", "box",
        "dose", "doses", "daily", "formula", "flavor", "flavour", "flavored",
        "treat", "treats", "food", "kibble", "meal", "diet", "recipe", "blend",
        "sensitivity", "sensitivities", "allergy", "allergic", "intolerance",
        "the", "and", "for", "with", "plus", "of", "a", "an",
        // Spanish: the same forms, doses and fillers.
        "tableta", "tabletas", "comprimido", "comprimidos", "capsula", "capsulas",
        "gota", "gotas", "masticable", "masticables", "pastilla", "pastillas", "pildora", "pildoras",
        "otico", "otica", "oftalmico", "oftalmica", "inyeccion", "inyectable", "topico", "topica", "aerosol",
        "solucion", "unguento", "crema", "polvo", "liquido",
        "botella", "frasco", "tubo", "bolsa", "lata", "sobre", "caja",
        "dosis", "diario", "diaria", "diarios", "diarias", "sabor",
        "premio", "premios", "golosina", "golosinas", "alimento", "comida", "croqueta", "croquetas",
        "receta", "dieta", "mezcla", "carne",
        "sensibilidad", "sensibilidades", "alergia", "alergias", "alergico", "alergica", "intolerancia",
        "el", "la", "los", "las", "un", "una", "de", "del", "al", "y", "e", "o", "u", "con", "para", "en", "por", "sin", "mas",
    ]

    // Conservative, extensible groups. A trigger in any group flags candidates
    // that contain a sibling term. Drug families tie generics to the class. Each
    // group has its Spanish (Mexico) words, so an allergy written "pollo" flags
    // "Chicken kibble" and the other way round ("carne", like "meal", is a
    // filler: "carne de res" is "res"). No "suero": in a clinic it is an IV
    // fluid far more often than whey.
    static let aliasGroups: [[String]] = [
        // Foods
        ["chicken", "poultry", "hen", "fowl", "pollo", "gallina", "ave", "aves"],
        ["beef", "cattle", "cow", "bovine", "res", "vaca", "vacuno", "bovino", "ternera", "ternero"],
        ["pork", "pig", "porcine", "ham", "bacon", "cerdo", "puerco", "porcino", "jamon", "tocino"],
        ["lamb", "mutton", "sheep", "cordero", "borrego", "carnero", "oveja", "ovino"],
        ["fish", "salmon", "tuna", "whitefish", "trout", "cod", "sardine", "pescado", "pescados", "pez", "atun", "trucha", "bacalao", "sardina", "sardinas"],
        ["seafood", "shellfish", "shrimp", "prawn", "crab", "lobster", "marisco", "mariscos", "camaron", "camarones", "cangrejo", "langosta", "langostino", "langostinos"],
        ["dairy", "milk", "lactose", "cheese", "whey", "casein", "lacteo", "lacteos", "leche", "lactosa", "queso", "quesos", "caseina", "yogur", "yogurt"],
        ["egg", "eggs", "albumin", "huevo", "huevos", "albumina"],
        ["wheat", "gluten", "grain", "grains", "trigo", "grano", "granos"],
        ["soy", "soya", "soybean", "soja"],
        ["corn", "maize", "maiz", "elote"],
        ["peanut", "peanuts", "cacahuate", "cacahuates", "cacahuete", "cacahuetes", "mani"],
        ["nut", "nuts", "almond", "cashew", "walnut", "hazelnut", "nuez", "nueces", "almendra", "almendras", "anacardo", "anacardos", "avellana", "avellanas"],
        // Drug families (generic ↔ class)
        ["penicillin", "penicillins", "amoxicillin", "ampicillin", "cloxacillin", "clavulanate", "clavamox", "amoxiclav", "penicilina", "penicilinas", "amoxicilina", "ampicilina", "cloxacilina", "clavulanato", "clavulanico"],
        ["cephalosporin", "cephalosporins", "cephalexin", "cefovecin", "cefpodoxime", "convenia", "cefalosporina", "cefalosporinas", "cefalexina", "cefovecina", "cefpodoxima"],
        ["sulfa", "sulfonamide", "sulfamethoxazole", "sulfadimethoxine", "trimethoprim", "tmp", "smz", "sulfas", "sulfonamida", "sulfonamidas", "sulfametoxazol", "sulfadimetoxina", "trimetoprima", "trimetoprim"],
        ["nsaid", "nsaids", "carprofen", "rimadyl", "meloxicam", "metacam", "firocoxib", "previcox", "deracoxib", "ibuprofen", "aspirin", "robenacoxib", "aine", "aines", "carprofeno", "ibuprofeno", "aspirina", "acetilsalicilico"],
        ["tetracycline", "tetracyclines", "doxycycline", "minocycline", "tetraciclina", "tetraciclinas", "doxiciclina", "minociclina"],
        ["fluoroquinolone", "fluoroquinolones", "enrofloxacin", "baytril", "marbofloxacin", "ciprofloxacin", "fluoroquinolona", "fluoroquinolonas", "enrofloxacino", "enrofloxacina", "marbofloxacino", "marbofloxacina", "ciprofloxacino", "ciprofloxacina"],
    ]

    private static let aliasByToken: [String: Set<String>] = {
        var map: [String: Set<String>] = [:]
        for group in aliasGroups {
            let set = Set(group)
            for term in group { map[term] = set }
        }
        return map
    }()

    /// Lowercase ASCII letters and digits separated by single spaces, the same
    /// as the web's `normalizeAllergyText`: compatibility-decomposed (NFKD),
    /// accents dropped ("Salmón" → "salmon", "piña" → "pina"), anything else a space.
    static func normalize(_ value: String) -> String {
        let decomposed = value.decomposedStringWithCompatibilityMapping
        var scalars = String.UnicodeScalarView()
        for scalar in decomposed.unicodeScalars where !(0x0300...0x036F).contains(scalar.value) {
            scalars.append(scalar)
        }
        let lowered = String(scalars).lowercased()
        let cleaned = lowered.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 0x61...0x7A, 0x30...0x39: return Character(scalar)
            default: return " "
            }
        }
        return String(cleaned)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// Meaningful, normalized tokens (dosage/form/filler words and bare numbers dropped).
    static func tokenize(_ value: String) -> [String] {
        let normalized = normalize(value)
        guard !normalized.isEmpty else { return [] }
        return normalized.split(separator: " ").map(String.init).filter { token in
            !token.isEmpty && !noiseTokens.contains(token) && !token.allSatisfy(\.isNumber)
        }
    }

    private static func expand(_ token: String) -> Set<String> {
        aliasByToken[token] ?? [token]
    }

    // A trigger token is present in the candidate if the candidate has the token
    // itself or any of its aliases. Single-character tokens require an exact match.
    private static func candidateHasToken(_ candidateTokens: Set<String>, _ token: String) -> (hit: Bool, viaAlias: Bool) {
        if candidateTokens.contains(token) { return (true, false) }
        if token.count <= 1 { return (false, false) }
        for variant in expand(token) where variant != token && candidateTokens.contains(variant) {
            return (true, true)
        }
        return (false, false)
    }

    /// Allergies whose trigger looks like it matches `candidateName`. A multi-word
    /// trigger must have all of its meaningful tokens present; a single-word
    /// trigger may match through the alias map. De-duplicated by record/trigger.
    static func findConflicts(candidateName: String?, allergies: [StockAllergySource]) -> [StockAllergyConflict] {
        let name = (candidateName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !allergies.isEmpty else { return [] }

        let candidateTokens = Set(tokenize(name))
        guard !candidateTokens.isEmpty else { return [] }

        var conflicts: [StockAllergyConflict] = []
        var seen = Set<String>()

        for allergy in allergies {
            let triggerTokens = tokenize(allergy.trigger)
            if triggerTokens.isEmpty { continue }

            var allPresent = true
            var viaAlias = false
            for token in triggerTokens {
                let result = candidateHasToken(candidateTokens, token)
                if !result.hit { allPresent = false; break }
                if result.viaAlias { viaAlias = true }
            }
            if !allPresent { continue }

            let key = allergy.recordId ?? "\(allergy.petName ?? ""):\(normalize(allergy.trigger))"
            if seen.contains(key) { continue }
            seen.insert(key)

            conflicts.append(StockAllergyConflict(
                trigger: allergy.trigger,
                reaction: allergy.reaction,
                via: viaAlias ? .related : .name
            ))
        }

        return conflicts
    }
}
