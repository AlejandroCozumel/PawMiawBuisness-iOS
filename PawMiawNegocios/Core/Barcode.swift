//
//  Barcode.swift
//  PawMiawNegocios
//
//  What a scan means, with no camera in it (web lib/barcode-scan.ts): which
//  reads can be trusted (a check digit that holds, or the same read twice),
//  what a GS1 label says (the product's GTIN, its lot, its expiry), which
//  spellings of one product code are the same code (a GTIN-14 with a leading
//  0, an EAN-13, a UPC-A), and how a code is looked up when the server matches
//  barcodes exactly — two products with one code come back as `matches`, so
//  the screen asks which. The camera (Design/BarcodeScanner.swift) hands its
//  reads here. Used by the Store's counter, the Catalog's product sheet and
//  quick edit, the bill's item search, Inventory's search, stock settings and
//  the delivery's product picker.
//

import Foundation

/// One read (or one typed code): the code to look up or store and what else the label said.
struct BarcodeScan: Hashable {
    enum Source: Hashable { case camera, photo, typed }
    /// The GTIN of a GS1 label, otherwise what was read.
    let code: String
    /// Exactly what the symbol (or the keyboard) said.
    let raw: String
    /// The symbol's format by the web's names (`ean_13`, `code_128`, …); nil when typed.
    let format: String?
    let source: Source
    /// From a GS1 label: the lot (AI 10) and the expiry (AI 17) as yyyy-MM-dd.
    let lot: String?
    let expiresOn: String?
}

/// A GS1 element string, read.
struct GS1Label: Hashable {
    let gtin: String?
    let lot: String?
    let expiresOn: String?
    /// Every element read, by its application identifier.
    let elements: [String: String]
}

enum Barcode {
    /// Formats whose last digit checks the others: one valid read is enough.
    static let checkedFormats: Set<String> = ["ean_13", "ean_8", "upc_a", "upc_e"]
    /// FNC1 as decoders hand it over: the ASCII group separator.
    static let groupSeparator: Character = "\u{1d}"

    private static func isDigits(_ text: String) -> Bool { !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber } }

    /// The GS1 mod-10 check of a GTIN-8, UPC-A, EAN-13 or GTIN-14 (weights 3 and 1 from the right).
    static func hasValidCheckDigit(_ code: String) -> Bool {
        guard isDigits(code), [8, 12, 13, 14].contains(code.count) else { return false }
        let digits = code.compactMap { $0.wholeNumberValue }
        var sum = 0
        var weight = 3
        for index in stride(from: digits.count - 2, through: 0, by: -1) {
            sum += digits[index] * weight
            weight = 4 - weight
        }
        return (10 - (sum % 10)) % 10 == digits[digits.count - 1]
    }

    /// A UPC-E (8 digits, with its number system and check digit) written out as the UPC-A it abbreviates.
    static func expandUpcE(_ code: String) -> String? {
        guard code.count == 8, isDigits(code), let first = code.first, first == "0" || first == "1" else { return nil }
        let chars = Array(code)
        let system = String(chars[0])
        let a = chars[1], b = chars[2], c = chars[3], d = chars[4], e = chars[5], last = chars[6]
        let check = String(chars[7])
        let body: String
        switch last {
        case "0", "1", "2": body = "\(a)\(b)\(last)0000\(c)\(d)\(e)"
        case "3": body = "\(a)\(b)\(c)00000\(d)\(e)"
        case "4": body = "\(a)\(b)\(c)\(d)00000\(e)"
        default: body = "\(a)\(b)\(c)\(d)\(e)0000\(last)"
        }
        return system + body + check
    }

    /// Whether a text reads as a product code (digits in it, no spaces) rather than a name someone searched for.
    static func looksLikeCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 4 && trimmed.contains { $0.isNumber } && !trimmed.contains { $0.isWhitespace }
    }

    /// A GTIN of 12 to 14 digits as its 14: what two spellings of one code share.
    private static func gtin14(_ code: String) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isDigits(trimmed), (12...14).contains(trimmed.count) else { return nil }
        return String(repeating: "0", count: 14 - trimmed.count) + trimmed
    }

    /// Whether two stored or scanned codes are the same product code (a leading 0 apart, or identical).
    static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        let left = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = b.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right { return true }
        guard let padded = gtin14(left) else { return false }
        return padded == gtin14(right)
    }

    /// Every spelling a stored barcode may have for this code, the code itself first.
    /// The server matches a barcode exactly, so each is searched in turn.
    static func variants(_ code: String, format: String? = nil) -> [String] {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var list = [trimmed]
        func add(_ value: String) { if !list.contains(value) { list.append(value) } }
        let expanded = format == "upc_e" ? expandUpcE(trimmed) : nil
        if let padded = gtin14(expanded ?? trimmed) {
            if let expanded { add(expanded) }
            var significant = Substring(padded)
            var dropped = 0
            while dropped < 2, significant.first == "0" { significant = significant.dropFirst(); dropped += 1 }
            // Shortest first after the code itself: stores keep what is printed under the bars.
            if significant.count <= 12 { add(String(padded.dropFirst(2))) }
            if significant.count <= 13 { add(String(padded.dropFirst(1))) }
            add(padded)
        }
        return list
    }

    // MARK: GS1 labels

    /// How many digits an application identifier has, by its first two.
    private static func identifierLength(_ firstTwo: String) -> Int {
        if ["23", "24", "25", "40", "41", "42", "71"].contains(firstTwo) { return 3 }
        if ["31", "32", "33", "34", "35", "36", "39", "43", "70", "72", "80", "81", "82"].contains(firstTwo) { return 4 }
        return 2
    }

    /// Elements of a fixed length (identifier included), by their first two digits: no separator follows them.
    private static let fixedLengths: [String: Int] = [
        "00": 20, "01": 16, "02": 16, "03": 16, "04": 18,
        "11": 8, "12": 8, "13": 8, "14": 8, "15": 8, "16": 8, "17": 8, "18": 8, "19": 8,
        "20": 4, "31": 10, "32": 10, "33": 10, "34": 10, "35": 10, "36": 10, "41": 16,
    ]

    /// The longest value an element without a fixed length may carry.
    private static let maxVariable = 90

    /// `(01)07501234567893(17)271231(10)L123`: what a label prints, and what some decoders return.
    private static func parseBracketed(_ text: String) -> [String: String]? {
        var elements: [String: String] = [:]
        var rest = Substring(text)
        while !rest.isEmpty {
            guard rest.first == "(", let close = rest.firstIndex(of: ")") else { return nil }
            let identifier = rest[rest.index(after: rest.startIndex)..<close]
            guard (2...4).contains(identifier.count), isDigits(String(identifier)) else { return nil }
            let afterClose = rest.index(after: close)
            let end = rest[afterClose...].firstIndex(of: "(") ?? rest.endIndex
            let value = rest[afterClose..<end].filter { $0 != groupSeparator }.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return nil }
            elements[String(identifier)] = value
            rest = rest[end...]
        }
        return elements.isEmpty ? nil : elements
    }

    /// `010750123456789317271231` + `10L123<GS>21…`: the element string as it is encoded.
    private static func parsePlain(_ text: String) -> [String: String]? {
        let chars = Array(text)
        var elements: [String: String] = [:]
        var at = 0
        func slice(_ from: Int, _ to: Int) -> String { String(chars[max(0, min(from, chars.count))..<max(0, min(to, chars.count))]) }
        while at < chars.count {
            if chars[at] == groupSeparator { at += 1; continue }
            let firstTwo = slice(at, at + 2)
            guard firstTwo.count == 2, isDigits(firstTwo) else { return nil }
            let idLength = identifierLength(firstTwo)
            let identifier = slice(at, at + idLength)
            guard identifier.count == idLength, isDigits(identifier) else { return nil }
            let value: String
            if let fixed = fixedLengths[firstTwo] {
                value = slice(at + idLength, at + fixed)
                guard value.count == fixed - idLength, !value.contains(groupSeparator) else { return nil }
                at += fixed
            } else {
                let end = chars[(at)...].firstIndex(of: groupSeparator)
                value = slice(at + idLength, end ?? chars.count)
                guard !value.isEmpty, value.count <= maxVariable else { return nil }
                at = end.map { $0 + 1 } ?? chars.count
            }
            elements[identifier] = value
        }
        return elements.isEmpty ? nil : elements
    }

    /// The expiry of a label (YYMMDD) as a date. The century is the one that puts the year
    /// closest to now (GS1's rule: 49 years back, 50 ahead); day 00 means the last day of the month.
    static func gs1Date(_ yymmdd: String, now: Date = Date()) -> String? {
        guard yymmdd.count == 6, isDigits(yymmdd) else { return nil }
        let chars = Array(yymmdd)
        guard let yy = Int(String(chars[0...1])), let month = Int(String(chars[2...3])), var day = Int(String(chars[4...5])) else { return nil }
        guard (1...12).contains(month) else { return nil }
        let current = Calendar(identifier: .gregorian).component(.year, from: now)
        let gap = yy - (current % 100)
        let century = current - (current % 100) + (gap >= 51 ? -100 : gap <= -50 ? 100 : 0)
        let year = century + yy
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return nil }
        let lastDay = range.count
        if day == 0 { day = lastDay }
        guard day <= lastDay else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// A GS1 element string, however the decoder spelled it — with the symbology identifier
    /// (`]d2`, `]C1`, `]Q3`), a leading FNC1, group separators between elements, or the printed
    /// form with parentheses — or nil when the text is something else (a plain code, a URL, a name).
    static func parseGS1(_ raw: String, now: Date = Date(), format: String? = nil) -> GS1Label? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let flagged = ["]d2", "]C1", "]Q3", "]e0", "]J1"].contains { text.hasPrefix($0) }
        if flagged { text = String(text.dropFirst(3)) }
        let fnc1 = text.first == groupSeparator
        while text.first == groupSeparator { text.removeFirst() }
        guard !text.isEmpty else { return nil }

        let bracketed = text.hasPrefix("(")
        guard let elements = bracketed ? parseBracketed(text) : parsePlain(text) else { return nil }
        let gtin = elements["01"]
        if let gtin, !(isDigits(gtin) && gtin.count == 14 && hasValidCheckDigit(gtin)) { return nil }
        // Bare digits with no marker could be any number: they are a label only when they carry a GTIN and
        // more — or a GTIN alone in a symbol that labels use (a decoder may drop the FNC1 that said so).
        if !flagged && !fnc1 && !bracketed {
            let labelSymbol = format == "code_128" || format == "data_matrix"
            if gtin == nil || (elements.count < 2 && !labelSymbol) { return nil }
        }
        return GS1Label(
            gtin: gtin,
            lot: elements["10"]?.trimmingCharacters(in: .whitespaces).nonEmpty,
            expiresOn: elements["17"].flatMap { gs1Date($0, now: now) },
            elements: elements
        )
    }

    /// A GTIN-14 as stores keep it: without the leading 0 of an item sold one by one.
    private static func gtinAsCode(_ gtin: String) -> String { gtin.hasPrefix("0") ? String(gtin.dropFirst()) : gtin }

    /// What one read (or one typed code) means: the code to use and what else the label said.
    static func interpret(_ raw: String, format: String?, source: BarcodeScan.Source, now: Date = Date()) -> BarcodeScan {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Linear retail codes are numbers and nothing else: never read as a label.
        let label = format.map { checkedFormats.contains($0) } == true ? nil : parseGS1(text, now: now, format: format)
        if let label, let gtin = label.gtin {
            return BarcodeScan(code: gtinAsCode(gtin), raw: text, format: format, source: source, lot: label.lot, expiresOn: label.expiresOn)
        }
        return BarcodeScan(code: text.filter { $0 != groupSeparator }, raw: text, format: format, source: source, lot: nil, expiresOn: nil)
    }

    // MARK: Looking a code up

    /// What a code lookup found. `matches` is every product the code belongs to exactly: two of
    /// them leave `exact` empty, so the screen asks which instead of picking the first. `found` is
    /// what the code itself returned (names match too). `code` is the spelling that matched.
    struct Lookup<T> {
        let exact: T?
        let matches: [T]
        let found: [T]
        let code: String
    }

    /// Looks a scanned or typed code up through a search that matches barcodes exactly: the code as
    /// given, then — only when nothing has it — its other spellings.
    static func findByCode<T>(_ code: String, format: String? = nil, barcode: (T) -> String?, sku: (T) -> String?, key: (T) -> String, search: (String) async throws -> [T]) async throws -> Lookup<T> {
        let all = variants(code, format: format)
        guard let first = all.first else { return Lookup(exact: nil, matches: [], found: [], code: code) }
        func distinct(_ entries: [T]) -> [T] {
            var seen = Set<String>()
            return entries.filter { seen.insert(key($0)).inserted }
        }
        let lower = first.lowercased()
        let found = try await search(first)
        let matches = distinct(found.filter { same(barcode($0), first) || sku($0)?.lowercased() == lower })
        if !matches.isEmpty { return Lookup(exact: matches.count == 1 ? matches[0] : nil, matches: matches, found: found, code: first) }
        for variant in all.dropFirst() {
            let variantMatches = distinct(try await search(variant).filter { same(barcode($0), variant) })
            if !variantMatches.isEmpty {
                return Lookup(exact: variantMatches.count == 1 ? variantMatches[0] : nil, matches: variantMatches, found: found, code: variant)
            }
        }
        return Lookup(exact: nil, matches: [], found: found, code: first)
    }
}

/// When to believe the camera. A blurred frame can decode to a wrong number: a code whose own
/// check digit holds (EAN, UPC) is taken at once and one that fails it is thrown away; anything
/// else must be read the same twice in a row.
struct BarcodeStableReader {
    private var previous: String?

    /// A frame's read; true when it can be trusted.
    mutating func push(_ value: String, format: String?) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if let format, Barcode.checkedFormats.contains(format) {
            let digits = format == "upc_e" ? (Barcode.expandUpcE(text) ?? text) : text
            if Barcode.hasValidCheckDigit(digits) { return true }
            previous = nil
            return false
        }
        let key = "\(format ?? ""):\(text)"
        if previous == key { return true }
        previous = key
        return false
    }

    mutating func reset() { previous = nil }
}
