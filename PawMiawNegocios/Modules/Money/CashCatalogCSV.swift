//
//  CashCatalogCSV.swift
//  PawMiawNegocios
//
//  The Catalog as a spreadsheet, both ways (web: lib/catalog-csv.ts,
//  catalog-page/catalog-import-sheet.tsx): every item as a CSV row, and a CSV
//  of new services and products read back and checked row by row before
//  anything is added. A row already in the catalog (its SKU, or its name among
//  items of its kind) is skipped, never changed; packs are added by hand. The
//  file is written in the reader's language and read in either; Excel's
//  habits are allowed for (a byte-order mark, `;` or tabs, amounts with a comma).
//

import SwiftUI
import UniformTypeIdentifiers

enum CashCatalogCSV {
    static let columns = ["kind", "name", "category", "sku", "barcode", "price", "tax", "taxRate", "description", "active",
                          "productKind", "prescription", "trackStock", "onHand", "reorderPoint", "unitCost", "packOf", "packUnits"]

    static let headers: [String: (en: String, es: String)] = [
        "kind": ("Kind", "Tipo"), "name": ("Name", "Nombre"), "category": ("Category", "Categoría"), "sku": ("SKU", "SKU"),
        "barcode": ("Barcode", "Código de barras"), "price": ("Price", "Precio"), "tax": ("Tax", "Impuesto"), "taxRate": ("Own tax rate %", "Tasa propia %"),
        "description": ("Description", "Descripción"), "active": ("Active", "Activo"), "productKind": ("Kind of product", "Tipo de producto"),
        "prescription": ("Prescription only", "Solo con receta"), "trackStock": ("Track stock", "Llevar inventario"), "onHand": ("Quantity on hand", "Existencia"),
        "reorderPoint": ("Reorder point", "Punto de reorden"), "unitCost": ("Unit cost", "Costo unitario"), "packOf": ("Pack of", "Empaque de"), "packUnits": ("Units per pack", "Unidades por empaque"),
    ]
    static let kindWords: [String: (en: String, es: String)] = ["service": ("Service", "Servicio"), "product": ("Product", "Producto")]
    static let taxWords: [String: (en: String, es: String)] = ["default": ("Standard", "Estándar"), "standard": ("Own rate", "Tasa propia"), "zero": ("0%", "0%"), "exempt": ("Exempt", "Exento")]
    static let productKindWords: [String: (en: String, es: String)] = ["medication": ("Medication", "Medicamento"), "food": ("Food", "Alimento"), "supply": ("Supply", "Insumo"), "accessory": ("Accessory", "Accesorio"), "other": ("Other", "Otro")]

    static let maxRows = 500

    static var spanish: Bool { LocalizationManager.shared.currentLanguage == .spanish }
    static func word(_ pair: (en: String, es: String)) -> String { spanish ? pair.es : pair.en }

    /// Lower-case, accent-free, single-spaced: how headers, words and names are compared.
    static func fold(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// One cell; a text a spreadsheet would run as a formula is written with a leading apostrophe.
    static func cell(_ value: String) -> String {
        var text = value
        if let first = text.first, "=+-@\t\r".contains(first) { text = "'" + text }
        if text.contains(where: { "\",;\n\r".contains($0) }) { return "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        return text
    }

    // MARK: Export

    static func export(_ items: [CashCatalogItem], all: [CashCatalogItem]) -> String {
        let names = Dictionary(all.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let yes = spanish ? "Sí" : "Yes", no = "No"
        let rows = items.map { item -> String in
            let product = item.isProduct
            let pack = item.isPack
            let stock = product && !pack && item.trackInventory ? item.inventory : nil
            let values: [String: String] = [
                "kind": word(kindWords[product ? "product" : "service"]!),
                "name": item.name,
                "category": item.category?.name ?? "",
                "sku": item.sku ?? "",
                "barcode": item.inventory?.barcode ?? "",
                "price": item.defaultUnitAmount > 0 ? CashCSV.money(item.defaultUnitAmount) : "",
                "tax": word(taxWords[item.taxTreatment] ?? taxWords["default"]!),
                "taxRate": item.taxTreatment == "standard" ? (item.taxRateBps.map { String(format: "%g", Double($0) / 100) } ?? "") : "",
                "description": item.description ?? "",
                "active": item.active ? yes : no,
                "productKind": product ? (item.productKind.flatMap { productKindWords[$0] }.map(word) ?? "") : "",
                "prescription": product ? (item.requiresPrescription ? yes : no) : "",
                "trackStock": product ? (item.trackInventory && !pack ? yes : no) : "",
                "onHand": stock.map { "\($0.quantityOnHand)" } ?? "",
                "reorderPoint": stock.map { "\($0.reorderPoint)" } ?? "",
                "unitCost": stock?.unitCostAmount.map { CashCSV.money($0) } ?? "",
                "packOf": pack ? (item.stockCatalogItemId.flatMap { names[$0] } ?? "") : "",
                "packUnits": pack ? "\(item.stockUnits ?? 1)" : "",
            ]
            return columns.map { cell(values[$0] ?? "") }.joined(separator: ",")
        }
        return ([columns.map { cell(word(headers[$0]!)) }.joined(separator: ",")] + rows).joined(separator: "\r\n")
    }

    static func exportName() -> String {
        "\(spanish ? "catalogo" : "catalog")-\(DateText.dayKey()).csv"
    }

    /// A file to start an import from: the columns an import reads, with two rows to write over.
    static func template() -> String {
        let cols = ["kind", "name", "category", "sku", "barcode", "price", "tax", "taxRate", "description", "productKind", "trackStock", "onHand", "reorderPoint", "unitCost"]
        let examples: [[String: String]] = spanish
            ? [["kind": "Servicio", "name": "Consulta general", "category": "Consultas", "price": "450.00", "tax": "Estándar"],
               ["kind": "Producto", "name": "Croquetas 2 kg", "category": "Alimento", "sku": "CR-2KG", "price": "320.00", "tax": "Estándar", "productKind": "Alimento", "trackStock": "Sí", "onHand": "12", "reorderPoint": "4", "unitCost": "210.00"]]
            : [["kind": "Service", "name": "Wellness exam", "category": "Consults", "price": "45.00", "tax": "Standard"],
               ["kind": "Product", "name": "Dog food 2 kg", "category": "Food", "sku": "DF-2KG", "price": "32.00", "tax": "Standard", "productKind": "Food", "trackStock": "Yes", "onHand": "12", "reorderPoint": "4", "unitCost": "21.00"]]
        return ([cols.map { cell(word(headers[$0]!)) }.joined(separator: ",")] + examples.map { row in cols.map { cell(row[$0] ?? "") }.joined(separator: ",") }).joined(separator: "\r\n")
    }

    // MARK: Reading a file

    /// CSV text as rows of cells; the separator is the one that splits the first line into the most cells.
    static func parse(_ raw: String) -> [[String]] {
        let text = raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var mark: Character = ","
        var most = 0
        for candidate in [",", ";", "\t"] as [Character] {
            let cells = rows(firstLine, candidate).first?.count ?? 0
            if cells > most { most = cells; mark = candidate }
        }
        return rows(text, mark).filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    private static func rows(_ text: String, _ mark: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var value = ""
        var quoted = false
        let chars = Array(text)
        var at = 0
        while at < chars.count {
            let char = chars[at]
            if quoted {
                if char == "\"" {
                    if at + 1 < chars.count && chars[at + 1] == "\"" { value.append("\""); at += 1 } else { quoted = false }
                } else { value.append(char) }
            } else if char == "\"" && value.isEmpty {
                quoted = true
            } else if char == mark {
                row.append(value); value = ""
            } else if char.isNewline {
                row.append(value); value = ""
                rows.append(row); row = []
            } else {
                value.append(char)
            }
            at += 1
        }
        row.append(value)
        rows.append(row)
        return rows
    }

    /// An amount as written in a spreadsheet: "1,500.00", "1.500,00", "$450", "450 MXN".
    static func cents(_ text: String) -> Int? {
        var body = text.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty, body.contains(where: \.isNumber) else { return nil }
        for code in ["MXN", "USD", "COP", "EUR", "ARS", "CLP", "PEN", "GTQ", "CRC", "MX$", "US$", "$", "€", "£"] {
            if body.uppercased().hasPrefix(code) { body = String(body.dropFirst(code.count)).trimmingCharacters(in: .whitespaces) }
            if body.uppercased().hasSuffix(code) { body = String(body.dropLast(code.count)).trimmingCharacters(in: .whitespaces) }
        }
        body = body.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00a0}", with: "").replacingOccurrences(of: "'", with: "")
        guard !body.isEmpty, body.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) else { return nil }
        let points = body.filter { $0 == "." }.count
        let commas = body.filter { $0 == "," }.count
        func grouped(_ s: String, _ m: Character) -> Bool {
            let parts = s.split(separator: m, omittingEmptySubsequences: false)
            guard let head = parts.first, (1...3).contains(head.count) else { return false }
            return parts.dropFirst().allSatisfy { $0.count == 3 }
        }
        var whole = body, decimals = ""
        if points > 0 && commas > 0 {
            let decimal: Character = body.lastIndex(of: ".")! > body.lastIndex(of: ",")! ? "." : ","
            let group: Character = decimal == "." ? "," : "."
            guard body.filter({ $0 == decimal }).count == 1 else { return nil }
            let parts = body.split(separator: decimal, omittingEmptySubsequences: false)
            guard grouped(String(parts[0]), group) else { return nil }
            whole = parts[0].replacingOccurrences(of: String(group), with: "")
            decimals = String(parts[1])
        } else if points + commas > 1 {
            let m: Character = commas > 0 ? "," : "."
            guard grouped(body, m) else { return nil }
            whole = body.replacingOccurrences(of: String(m), with: "")
        } else if points + commas == 1 {
            let m: Character = commas > 0 ? "," : "."
            let parts = body.split(separator: m, omittingEmptySubsequences: false)
            let head = String(parts[0]), tail = String(parts[1])
            if m == "," && tail.count == 3 && (1...3).contains(head.count) && head.first != "0" { whole = head + tail } else { whole = head; decimals = tail }
        }
        guard !(whole.isEmpty && decimals.isEmpty), decimals.count <= 2, whole.count <= 13 else { return nil }
        let w = Int(whole.isEmpty ? "0" : whole) ?? -1
        let d = Int(decimals.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? -1
        guard w >= 0, d >= 0 else { return nil }
        return w * 100 + d
    }

    struct Row: Identifiable {
        enum Status { case add, skip, error }
        let line: Int
        let name: String
        let itemType: String?
        var status: Status
        var problems: [String] = []
        var skip: String?
        var notes: [String] = []
        var body: [String: Any?]?
        var categoryName: String?
        var categoryId: String?
        var price: Int?
        var id: Int { line }
    }

    struct Reading {
        var problem: String?
        var rows: [Row] = []
        var newCategories: [(itemType: String, name: String)] = []
        var fingerprint = ""
    }

    static func categoryKey(_ itemType: String, _ name: String) -> String { "\(itemType):\(fold(name))" }

    private static func lookup(_ words: [String: (en: String, es: String)], _ value: String, extra: [String: String] = [:]) -> String? {
        let folded = fold(value)
        guard !folded.isEmpty else { return nil }
        for (key, pair) in words where folded == fold(key) || folded == fold(pair.en) || folded == fold(pair.es) { return key }
        return extra[folded]
    }

    private static func yes(_ value: String, _ fallback: Bool) -> Bool {
        let folded = fold(value)
        if folded.isEmpty { return fallback }
        if ["yes", "y", "si", "s", "true", "1", "x"].contains(folded) { return true }
        if ["no", "n", "false", "0"].contains(folded) { return false }
        return fallback
    }

    private static func whole(_ value: String) -> (value: Int?, valid: Bool) {
        let text = value.filter { !$0.isWhitespace }
        if text.isEmpty { return (nil, true) }
        guard text.count <= 7, text.allSatisfy(\.isNumber), let number = Int(text) else { return (nil, false) }
        return (number, true)
    }

    private static func fingerprint(_ text: String) -> String {
        var hash: UInt32 = 0x811c9dc5
        for unit in text.utf16 { hash ^= UInt32(unit); hash = hash &* 0x01000193 }
        return String(format: "%08x", hash) + String(text.utf16.count, radix: 16)
    }

    /// The file checked against the catalog; nothing is sent from here.
    static func read(_ text: String, items: [CashCatalogItem], categories: [CashCategory], canEditInventory: Bool) -> Reading {
        let table = parse(text)
        var reading = Reading(fingerprint: fingerprint(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        guard let header = table.first?.map(fold) else { reading.problem = L("That file has no rows to import."); return reading }
        var at: [String: Int] = [:]
        for column in columns {
            if let index = header.firstIndex(where: { $0 == fold(headers[column]!.en) || $0 == fold(headers[column]!.es) || $0 == fold(column) }) { at[column] = index }
        }
        let missing = ["kind", "name", "price"].filter { at[$0] == nil }
        if !missing.isEmpty {
            reading.problem = LF("That file is missing these columns: %@. Download the template to see how it is laid out.", missing.map { word(headers[$0]!) }.joined(separator: ", "))
            return reading
        }
        guard table.count > 1 else { reading.problem = L("That file has no rows to import."); return reading }
        guard table.count - 1 <= maxRows else { reading.problem = LF("That file has more than %d rows. Split it and import each part.", maxRows); return reading }

        var skuOwners: [String: String] = [:]
        var nameOwners: [String: String] = [:]
        for item in items {
            if let sku = item.sku?.nonEmpty { skuOwners[fold(sku)] = item.id }
            nameOwners["\(item.itemType):\(fold(item.name))"] = item.id
        }
        var categoryByKey: [String: CashCategory] = [:]
        for category in categories { categoryByKey[categoryKey(category.itemType, category.name)] = category }
        var seenSkus = Set<String>(), seenNames = Set<String>()
        var newCategories: [String: (itemType: String, name: String)] = [:]
        var order: [String] = []

        for (index, cells) in table.dropFirst().enumerated() {
            func read(_ column: String) -> String { at[column].flatMap { $0 < cells.count ? cells[$0] : nil }?.trimmingCharacters(in: .whitespaces) ?? "" }
            let name = read("name")
            let itemType = lookup(kindWords, read("kind"), extra: ["servicios": "service", "productos": "product", "services": "service", "products": "product"])
            var row = Row(line: index + 2, name: name, itemType: itemType, status: .add)
            if name.isEmpty { row.problems.append(L("It has no name.")) } else if name.count > 140 { row.problems.append(L("The name is longer than 140 characters.")) }
            if itemType == nil { row.problems.append(L("The kind must be Service or Product.")) }
            if !read("packOf").isEmpty {
                row.status = row.problems.isEmpty ? .skip : .error
                if row.problems.isEmpty { row.skip = L("Packs are added by hand: they point at a product.") }
                reading.rows.append(row); continue
            }
            let sku = read("sku")
            let skuKey = sku.isEmpty ? nil : fold(sku)
            let nameKey = itemType != nil && !name.isEmpty ? "\(itemType!):\(fold(name))" : nil
            if row.problems.isEmpty {
                if let skuKey, skuOwners[skuKey] != nil { row.status = .skip; row.skip = L("Already in the catalog: an item has this SKU."); reading.rows.append(row); continue }
                if let nameKey, nameOwners[nameKey] != nil { row.status = .skip; row.skip = L("Already in the catalog: an item of this kind has this name."); reading.rows.append(row); continue }
            }
            let priceText = read("price")
            let price = priceText.isEmpty ? 0 : cents(priceText)
            if price == nil { row.problems.append(L("The price is not an amount. Leave it blank or 0 for no price yet.")) }
            if sku.count > 80 { row.problems.append(L("The SKU is longer than 80 characters.")) }
            let description = read("description")
            if description.count > 500 { row.problems.append(L("The description is longer than 500 characters.")) }
            let taxText = read("tax")
            let rateText = read("taxRate").replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
            var tax = lookup(taxWords, taxText, extra: ["tasa 0%": "zero", "zero-rated": "zero", "zero-rated (0%)": "zero", "tasa 0": "zero", "iva": "default", "estandar": "default", "own rate": "standard"])
            if !taxText.isEmpty && tax == nil { row.problems.append(L("The tax must be Standard, Own rate, 0% or Exempt.")) }
            var rateBps: Int?
            if !rateText.isEmpty {
                if let percent = Double(rateText), percent >= 0, percent <= 100 {
                    if taxText.isEmpty || tax == "standard" { tax = "standard"; rateBps = Int((percent * 100).rounded()) }
                } else { row.problems.append(L("The own tax rate must be a percentage from 0 to 100.")) }
            } else if tax == "standard" { row.problems.append(L("The own tax rate must be a percentage from 0 to 100.")) }
            let kindText = read("productKind")
            let productKind = lookup(productKindWords, kindText, extra: ["medicine": "medication", "medicina": "medication"])
            if itemType == "product" && !kindText.isEmpty && productKind == nil { row.problems.append(L("The kind of product must be Medication, Food, Supply, Accessory or Other.")) }
            let onHand = whole(read("onHand")), reorder = whole(read("reorderPoint"))
            let costText = read("unitCost")
            let unitCost = costText.isEmpty ? nil : cents(costText)
            let asksForStock = itemType == "product" && (onHand.value != nil || reorder.value != nil || !costText.isEmpty || !read("barcode").isEmpty)
            let trackStock = itemType == "product" && yes(read("trackStock"), asksForStock)
            if itemType == "product" && trackStock {
                if !onHand.valid { row.problems.append(L("The quantity on hand must be a whole number.")) }
                if !reorder.valid { row.problems.append(L("The reorder point must be a whole number.")) }
                if !costText.isEmpty && unitCost == nil { row.problems.append(L("The unit cost is not an amount.")) }
            }
            if let skuKey, seenSkus.contains(skuKey) { row.problems.append(L("Another row of the file has the same SKU.")) }
            if let skuKey { seenSkus.insert(skuKey) }
            if !row.problems.isEmpty { row.status = .error; reading.rows.append(row); continue }
            if let nameKey, seenNames.contains(nameKey) { row.status = .skip; row.skip = L("Already in the catalog: an item of this kind has this name."); reading.rows.append(row); continue }
            if let nameKey { seenNames.insert(nameKey) }
            if price == 0 { row.notes.append(L("Added with no price yet: it is asked for when charging.")) }
            let active = yes(read("active"), true)
            if !active { row.notes.append(L("Added as archived.")) }
            let categoryName = String(read("category").prefix(80)).nonEmpty
            if let categoryName, let itemType {
                let key = categoryKey(itemType, categoryName)
                if let existing = categoryByKey[key] { row.categoryId = existing.id } else if newCategories[key] == nil { newCategories[key] = (itemType, categoryName); order.append(key) }
            }
            row.categoryName = categoryName
            row.price = price
            let medication = itemType == "product" && productKind == "medication"
            var body: [String: Any?] = [
                "itemType": itemType, "name": name, "sku": sku.nonEmpty, "defaultUnitAmount": price ?? 0, "description": description.nonEmpty,
                "active": active, "trackInventory": trackStock, "productKind": itemType == "product" ? productKind : nil,
                "taxTreatment": tax ?? "default", "taxRateBps": tax == "standard" ? rateBps : nil,
                "requiresPrescription": medication ? yes(read("prescription"), false) : false,
            ]
            if trackStock {
                if canEditInventory {
                    body["inventory"] = ["barcode": String(read("barcode").prefix(120)).nonEmpty, "quantityOnHand": onHand.value ?? 0, "reorderPoint": reorder.value ?? 0, "unitCostAmount": unitCost] as [String: Any?]
                } else if asksForStock {
                    row.notes.append(L("Its stock is left at 0: your role cannot set stock."))
                }
            }
            row.body = body
            reading.rows.append(row)
        }
        reading.newCategories = order.compactMap { newCategories[$0] }
        return reading
    }
}

// MARK: - The import sheet

/// "Importar artículos": a CSV file chosen, its rows checked, then the new ones added.
struct CashCatalogImportSheet: View {
    let items: [CashCatalogItem]
    let categories: [CashCategory]
    let onDone: () -> Void
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false
    @State private var fileName = ""
    @State private var fileError: String?
    @State private var reading: CashCatalogCSV.Reading?
    @State private var filter = "all"
    @State private var progress: (done: Int, total: Int)?
    @State private var outcome: (added: Int, failed: [(line: Int, name: String, message: String)], lostCategories: [String])?
    @State private var template: CashSharedFile?

    private var rows: [CashCatalogCSV.Row] { reading?.rows ?? [] }
    private var toAdd: [CashCatalogCSV.Row] { rows.filter { $0.status == .add && $0.body != nil } }
    private var shown: [CashCatalogCSV.Row] {
        switch filter {
        case "add": rows.filter { $0.status == .add }
        case "skip": rows.filter { $0.status == .skip }
        case "error": rows.filter { $0.status == .error }
        default: rows
        }
    }

    /// The web's three steps: the file, the check, what was added.
    private var stepIndex: Int { outcome != nil ? 2 : reading != nil ? 1 : 0 }

    var body: some View {
        ProviderModal(title: L("Import items"), subtitle: L("Add services and products from a spreadsheet saved as CSV. Nothing already in the catalog is changed."), systemImage: "file-spreadsheet", accent: .mango,
                      isDirty: reading != nil && outcome == nil, primaryTitle: primaryTitle, isWorking: progress != nil,
                      steps: ModalSteps(steps: [(L("File"), "file-up"), (L("Check"), "list-checks"), (L("Added"), "circle-check")], current: stepIndex),
                      onBack: reading != nil && outcome == nil ? { reading = nil } : nil,
                      primaryIcon: stepIndex == 1 && progress == nil ? "plus" : nil,
                      primaryDisabled: stepIndex == 1 && toAdd.isEmpty,
                      // Added: the footer is only "Done", as the web's.
                      showsCancel: outcome == nil,
                      onPrimary: stepIndex == 1 ? { add() } : outcome != nil ? { dismiss() } : nil) {
            if let outcome {
                done(outcome)
            } else if let reading {
                check(reading)
            } else {
                choose
            }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.commaSeparatedText, .plainText, .text, UTType(filenameExtension: "csv") ?? .data]) { result in
            if case .success(let url) = result { load(url) }
        }
        .sheet(item: $template) { file in ShareSheet(items: [file.url]).presentationDetents([.medium, .large]) }
    }

    /// The check adds, the last step is Done; the file step has only Cancel (as the web).
    private var primaryTitle: String? {
        if outcome != nil { return L("Done@import") }
        guard stepIndex == 1 else { return nil }
        if let progress { return LF("Adding %d of %d…", progress.done, progress.total) }
        return LP(toAdd.count, "Add %d item", "Add %d items")
    }

    @ViewBuilder private var choose: some View {
        // Web: the dashed drop box that opens the file picker.
        Button { choosing = true } label: {
            VStack(spacing: 8) {
                Glyph("file-up", size: 20)
                    .foregroundStyle(Theme.inkStrong)
                    .frame(width: 48, height: 48)
                    .background(Theme.wash(Theme.mango, 26), in: Circle())
                Text(L("Choose a CSV file")).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                Text(LF("Up to %d rows.", CashCatalogCSV.maxRows)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
            .background(Theme.mix(Theme.surfaceMuted, 40, with: Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if let fileError { NoticeCard(tone: .problem, title: fileError) }
        VStack(alignment: .leading, spacing: 8) {
            Text(L("How the file is read")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
            ForEach([
                L("One row per item, with the columns Kind, Name and Price. Category, SKU, tax and stock are optional."),
                L("A row whose SKU or name is already in the catalog is skipped: nothing you have is changed."),
                L("A category the catalog does not have yet is created."),
                L("Packs are added by hand: they point at a product."),
            ], id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                    Text(line)
                }
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            Button {
                if let url = try? CashCSV.write(CashCatalogCSV.template(), name: CashCatalogCSV.spanish ? "plantilla-catalogo.csv" : "catalog-template.csv") { template = CashSharedFile(url: url) }
            } label: {
                HStack(spacing: 6) {
                    Glyph("download", size: 16)
                    Text(L("Download the template"))
                }
                .font(Theme.text(14, weight: .bold))
                .foregroundStyle(Theme.blue)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1.5))
    }

    @ViewBuilder private func check(_ reading: CashCatalogCSV.Reading) -> some View {
        let counts = (all: rows.count, add: rows.filter { $0.status == .add }.count, skip: rows.filter { $0.status == .skip }.count, error: rows.filter { $0.status == .error }.count)
        FlowLayout(spacing: 6) {
            Chip(text: fileName, tone: .muted, icon: "file-spreadsheet")
            if !reading.newCategories.isEmpty { Chip(text: LP(reading.newCategories.count, "%d new category", "%d new categories"), tone: .muted, icon: "tags") }
        }
        if counts.error > 0 {
            NoticeCard(tone: .warning, title: LP(counts.error, "%d row has a problem and is left out. Fix it in the file and import it again: what was already added is skipped.", "%d rows have problems and are left out. Fix them in the file and import it again: what was already added is skipped."))
        }
        if toAdd.isEmpty { NoticeCard(tone: .info, title: L("There is nothing to add from this file.")) }
        ScrollView(.horizontal, showsIndicators: false) {
            Segmented(options: [
                .init("all", L("All"), count: counts.all), .init("add", L("To add"), count: counts.add),
                .init("skip", L("Skipped"), count: counts.skip), .init("error", L("Problems"), count: counts.error),
            ], selection: $filter, look: .raised, label: L("Rows shown"))
        }
        VStack(spacing: 0) {
            if shown.isEmpty {
                Text(L("No rows here.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.vertical, 24).frame(maxWidth: .infinity)
            }
            LazyVStack(spacing: 0) {
                ForEach(shown) { row in
                    if row.id != shown.first?.id { RowDivider() }
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(row.line)").font(Theme.text(14)).monospacedDigit().foregroundStyle(Theme.inkSoft).frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(row.name.nonEmpty ?? "—").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(2)
                                Spacer(minLength: 8)
                                if row.body != nil, let price = row.price { Text(cashMoney(price)).font(Theme.text(14)).monospacedDigit().foregroundStyle(Theme.inkStrong) }
                            }
                            let detail = [row.itemType == "product" ? L("Product") : row.itemType == "service" ? L("Service") : nil, row.body != nil ? (row.categoryName ?? L("Uncategorized")) : nil].compactMap { $0 }
                            if !detail.isEmpty { Text(detail.joined(separator: " · ")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                            HStack(spacing: 6) {
                                Circle().fill(row.status == .add ? ProviderState.done.color : row.status == .skip ? Theme.inkSoft : Theme.destructive).frame(width: 6, height: 6)
                                Text(row.status == .add ? L("Will be added") : row.status == .skip ? L("Skipped@row") : L("Not added")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            }
                            .padding(.top, 2)
                            ForEach(row.problems + (row.skip.map { [$0] } ?? []) + row.notes, id: \.self) { line in
                                Text(line).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1.5))
        Text(LF("%d to add · %d skipped · %d with problems", counts.add, counts.skip, counts.error)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.horizontal, 4)
    }

    @ViewBuilder private func done(_ outcome: (added: Int, failed: [(line: Int, name: String, message: String)], lostCategories: [String])) -> some View {
        let skipped = rows.filter { $0.status == .skip }.count
        let problems = rows.filter { $0.status == .error }.count
        NoticeCard(tone: outcome.added > 0 ? .success : .warning, title: LP(outcome.added, "%d item was added to the catalog.", "%d items were added to the catalog."),
                   message: skipped + problems > 0 ? LF("%d skipped · %d with problems", skipped, problems) : nil)
        if !outcome.lostCategories.isEmpty {
            NoticeCard(tone: .warning, title: LF("These categories could not be created, so their items were added without one: %@.", outcome.lostCategories.joined(separator: ", ")))
        }
        if !outcome.failed.isEmpty {
            NoticeCard(tone: .problem, title: LP(outcome.failed.count, "%d row could not be added. Import the same file again to retry it: what was added is skipped.", "%d rows could not be added. Import the same file again to retry them: what was added is skipped."),
                       message: (outcome.failed.prefix(8).map { "\(LF("Row %d", $0.line)) · \($0.name)\($0.message.isEmpty ? "" : " — \($0.message)")" } + (outcome.failed.count > 8 ? [LF("…and %d more", outcome.failed.count - 8)] : [])).joined(separator: "\n"))
        }
    }

    private func load(_ url: URL) {
        fileError = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { fileError = L("That file could not be read. Save it as CSV and try again."); return }
        guard data.count <= 2 * 1024 * 1024 else { fileError = LF("That file is larger than 2 MB. Import up to %d rows at a time.", CashCatalogCSV.maxRows); return }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { fileError = L("That file could not be read. Save it as CSV and try again."); return }
        let next = CashCatalogCSV.read(text, items: items, categories: categories, canEditInventory: workspace.can(.inventoryEdit))
        if let problem = next.problem { fileError = problem; return }
        fileName = url.lastPathComponent
        filter = next.rows.contains { $0.status == .error } ? "error" : "all"
        reading = next
    }

    private func add() {
        guard let reading else { return }
        let rows = toAdd
        progress = (0, rows.count)
        Task {
            // The categories the rows name and the catalog lacks come first.
            var made: [String: String] = [:]
            var lost: [String] = []
            for category in reading.newCategories {
                if let created: CashCategory = try? await API.post("/provider-catalog/categories", body: ["itemType": category.itemType, "name": category.name, "active": true]) {
                    made[CashCatalogCSV.categoryKey(category.itemType, category.name)] = created.id
                } else {
                    lost.append(category.name)
                }
            }
            var added = 0
            var failed: [(line: Int, name: String, message: String)] = []
            for (index, row) in rows.enumerated() {
                guard var body = row.body else { continue }
                body["providerCatalogCategoryId"] = row.categoryId ?? (row.categoryName.flatMap { name in row.itemType.flatMap { made[CashCatalogCSV.categoryKey($0, name)] } })
                // The same file sent again finds what it already added.
                body["clientRequestId"] = "import-\(reading.fingerprint)-\(row.line)"
                do {
                    let _: EmptyResponse = try await API.post("/provider-catalog", body: body)
                    added += 1
                } catch {
                    failed.append((row.line, row.name, errorText(error, fallback: "")))
                    if let api = error as? APIError, api.isOffline {
                        for rest in rows.dropFirst(index + 1) { failed.append((rest.line, rest.name, api.message)) }
                        break
                    }
                }
                progress = (index + 1, rows.count)
            }
            progress = nil
            outcome = (added, failed, lost)
            if added > 0 {
                announceDataChanged()
                onDone()
            }
        }
    }
}
