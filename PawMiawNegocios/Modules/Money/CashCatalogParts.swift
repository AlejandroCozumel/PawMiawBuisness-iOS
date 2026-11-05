//
//  CashCatalogParts.swift
//  PawMiawNegocios
//
//  Pieces the Catalog's editor and the counter's quick edit share (web:
//  catalog-page/catalog-sheet-fields.tsx, catalog-model.ts): the price rule,
//  the tax field with what a client pays, the item's photo, and "sold as a
//  pack of another product".
//

import SwiftUI

enum CashCatalogRules {
    /// A price is above 0; only an item already saved without one may keep none by leaving it empty.
    static func priceError(_ price: Int?, item: CashCatalogItem?) -> String? {
        guard let price else { return item?.defaultUnitAmount == 0 ? nil : L("Add a valid price first.") }
        return price <= 0 ? L("The price must be above 0.") : nil
    }

    /// The rate a sale charges for an item: its own, none, or the store's standard one.
    static func effectiveRate(treatment: String, rateBps: Int?, settings: CashStoreSettings?) -> Int {
        switch treatment {
        case "zero", "exempt": 0
        case "standard": rateBps ?? 0
        default: settings?.defaultTaxRateBps ?? 0
        }
    }

    /// "16" → 1600 basis points; nil when it is not a rate from 0 to 100.
    static func rateBps(_ text: String) -> Int? {
        guard let percent = Double(text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)), percent >= 0, percent <= 100 else { return nil }
        return Int((percent * 100).rounded())
    }

    static func rateText(_ bps: Int?) -> String {
        bps.map { String(format: "%g", Double($0) / 100) } ?? ""
    }

    /// What a client pays at this price, taxed at `bps` (web `clientPrice` / the TaxField preview).
    static func payText(price: Int, bps: Int, settings: CashStoreSettings?) -> String {
        let currency = settings?.currency
        if bps <= 0 { return LF("A client pays %@. No tax is charged.", cashMoney(price, currency)) }
        if settings?.pricesIncludeTax ?? true {
            let tax = Int((Double(price * bps) / Double(10_000 + bps)).rounded())
            return LF("A client pays %@, which includes %@ of tax.", cashMoney(price, currency), cashMoney(tax, currency))
        }
        let tax = Int((Double(price * bps) / 10_000).rounded())
        return LF("A client pays %@: %@ plus %@ of tax.", cashMoney(price + tax, currency), cashMoney(price, currency), cashMoney(tax, currency))
    }

    /// A refused stock save the form can put under a field: (form key, sentence).
    static func stockRefusal(_ error: Error) -> (String, String)? {
        guard let api = error as? APIError else { return nil }
        switch api.code {
        case "barcode_taken":
            // The refusal names the product that has it.
            let owner = api.body?["itemName"]?.string?.nonEmpty
            return ("barcode", owner.map { LF("%@ already has this barcode.", $0) } ?? api.message.nonEmpty ?? L("Another product already has this barcode."))
        case "stock_changed", "counted_from_required": return ("quantity", api.message.nonEmpty ?? L("The stock changed since you opened it. Check the count and save again."))
        case "stock_on_hand": return ("trackInventory", api.message.nonEmpty ?? L("This product still has stock on the shelf. Count it to 0 in Inventory first."))
        default: return nil
        }
    }
}

/// How an item is taxed, and what a client pays at that price (web `TaxField`):
/// the four treatments as choices, the own rate beside them, the preview on aqua.
struct CashTaxField: View {
    @Binding var treatment: String
    @Binding var rate: String
    let price: Int?
    let settings: CashStoreSettings?
    var key: String = "taxRate"
    var form: FormState? = nil

    private var standard: Int { settings?.defaultTaxRateBps ?? 0 }

    var body: some View {
        FormField(label: L("Tax"), key: key, form: form) {
            FlowLayout(spacing: 8) {
                ForEach([
                    (value: "default", title: settings != nil ? LF("Standard (%@)", cashRate(standard)) : L("Standard")),
                    (value: "standard", title: L("Own rate")),
                    (value: "zero", title: L("Zero-rated (0%)")),
                    (value: "exempt", title: L("Exempt")),
                ], id: \.value) { choice in
                    CashCatalogChoicePill(title: choice.title, isOn: treatment == choice.value) {
                        if choice.value == "standard" && rate.isEmpty { rate = CashCatalogRules.rateText(standard) }
                        treatment = choice.value
                        form?.clear(key)
                    }
                }
                if treatment == "standard" {
                    HStack(spacing: 6) {
                        TextField("", text: $rate)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(Theme.text(16, weight: .bold))
                            .monospacedDigit()
                            .fieldChrome(invalid: form?.error(key) != nil)
                            .frame(width: 80)
                            .accessibilityLabel(L("Own tax rate"))
                            .onChange(of: rate) { _, _ in form?.clear(key) }
                        Text("%").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        }
        if let preview {
            Text(preview)
                .font(Theme.text(14))
                .foregroundStyle(Theme.inkStrong)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(Theme.aqua, 14), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        }
    }

    private var preview: String? {
        guard let price, price > 0, settings != nil else { return nil }
        let bps = treatment == "standard" ? CashCatalogRules.rateBps(rate) ?? 0 : CashCatalogRules.effectiveRate(treatment: treatment, rateBps: nil, settings: settings)
        return CashCatalogRules.payText(price: price, bps: bps, settings: settings)
    }
}

/// One of a row of choices where one is picked (web catalog-sheet-fields `Choice`):
/// 40 tall, a 2 pt edge; chosen = the tone's 18% wash, a deeper edge and a tick.
struct CashCatalogChoicePill: View {
    let title: String
    let isOn: Bool
    var tone: Color = Theme.blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).lineLimit(1)
                if isOn { Glyph("check", size: 16) }
            }
            .font(Theme.text(14, weight: .bold))
            .foregroundStyle(isOn ? Theme.inkStrong : Theme.inkSoft)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(isOn ? AnyShapeStyle(Theme.wash(tone, 18)) : AnyShapeStyle(Theme.surface), in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? AnyShapeStyle(Theme.mix(tone, 60, with: Theme.inkStrong)) : AnyShapeStyle(Theme.borderSoft), lineWidth: 2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// "Sold as a pack of another product": a box of 30 draws 30 from the tablet's stock (web `PackField`).
struct CashPackField: View {
    /// The product it draws on; nil when it is not a pack.
    @Binding var stockItemId: String?
    @Binding var stockItemName: String?
    @Binding var units: Int
    /// On, with the product still to choose.
    @Binding var picking: Bool
    let excludeId: String?
    var key: String = "packProduct"
    var form: FormState? = nil
    @State private var query = ""
    @State private var results: [CashProduct] = []
    @State private var searching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToggleRow(title: L("Sold as a pack of another product"), subtitle: L("A box of 30 tablets draws 30 from the tablet’s stock, so stock lives in one place."),
                      isOn: Binding(get: { stockItemId != nil || picking }, set: { on in
                form?.clear(key)
                if on { picking = true } else { picking = false; stockItemId = nil; stockItemName = nil; units = 1 }
            }))
            if stockItemId != nil {
                FlowLayout(spacing: 8) {
                    Text(L("Each one takes")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).frame(minHeight: 48)
                    TextField("1", text: Binding(get: { "\(units)" }, set: { units = max(1, Int($0.filter(\.isNumber)) ?? 1) }))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(Theme.text(16, weight: .bold))
                        .monospacedDigit()
                        .fieldChrome()
                        .frame(width: 80)
                        .accessibilityLabel(L("Units per pack"))
                    Text(L("of")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).frame(minHeight: 48)
                    HStack(spacing: 4) {
                        Text(stockItemName ?? L("the product")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Button {
                            stockItemId = nil
                            stockItemName = nil
                            picking = true
                        } label: {
                            Glyph("x", size: 14).foregroundStyle(Theme.inkStrong).frame(width: 32, height: 32).contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Change"))
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 4)
                    .frame(minHeight: 40)
                    .background(Theme.wash(Theme.blue, 8), in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.mix(Theme.blue, 55, with: Theme.borderSoft), lineWidth: 2))
                    .padding(.vertical, 4)
                }
            } else if picking {
                VStack(alignment: .leading, spacing: 6) {
                    SearchField(prompt: L("Which product holds the stock?"), text: $query, shape: .field)
                    if results.isEmpty {
                        Text(searching ? L("Searching…") : L("Nothing found.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    ForEach(results) { product in
                        Button {
                            form?.clear(key)
                            stockItemId = product.catalogItemId
                            stockItemName = product.name
                            units = units > 1 ? units : 10
                            picking = false
                        } label: {
                            HStack(spacing: 12) {
                                Text(product.name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(cashMoney(product.unitAmount, product.currency)).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(minHeight: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                .id(key)
                if let error = form?.error(key) {
                    Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral)
                }
            }
        }
        // The one search rule: the server searches 250 ms after typing stops, from two characters.
        .task(id: "\(picking)|\(ClientSearch.query(query) ?? "")") {
            guard picking && stockItemId == nil else { return }
            try? await Task.sleep(for: ClientSearch.debounce)
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            let found: [CashProduct] = (try? await API.get("/provider-store/products", query: ["q": ClientSearch.query(query), "type": "product"])) ?? []
            // Only products that can hold stock for a pack: not packs themselves.
            results = Array(found.filter { $0.itemType == "product" && $0.catalogItemId != excludeId && ($0.stock == nil || $0.stock?.unitsPerSale == 1) }.prefix(ClientSearch.pageSize))
        }
        .task(id: stockItemId) {
            guard let id = stockItemId, stockItemName == nil else { return }
            let item: CashCatalogItem? = try? await API.get("/provider-catalog/\(id)")
            stockItemName = item?.name
        }
    }
}
