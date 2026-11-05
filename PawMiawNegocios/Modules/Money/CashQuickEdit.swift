//
//  CashQuickEdit.swift
//  PawMiawNegocios
//
//  Fix an item without leaving the counter (web: store/store-quick-edit.tsx):
//  its name, price and tax and — for a product whose stock is counted — the
//  barcode and how many are on the shelf. The Catalog's rules and requests (a
//  price is above 0; a stock change is a correction counted from the figure
//  shown); everything else stays in the Catalog. Only for who edits the catalog.
//

import SwiftUI

/// What changed, for a line of this item already in the sale.
struct CashQuickEditSaved {
    let catalogItemId: String
    let name: String
    let unitAmount: Int
    let taxTreatment: String
    let taxRateBps: Int
    let barcode: String?
}

extension CashProduct {
    /// The same product with what the quick edit saved.
    fileprivate func updated(_ saved: CashQuickEditSaved) -> CashProduct {
        CashProduct(catalogItemId: catalogItemId, itemType: itemType, name: saved.name, sku: sku, barcode: saved.barcode, photoUrl: photoUrl, categoryId: categoryId,
                    unitAmount: saved.unitAmount, currency: currency, productKind: productKind, taxTreatment: saved.taxTreatment, taxRateBps: saved.taxRateBps,
                    requiresPrescription: requiresPrescription, controlSchedule: controlSchedule, stock: stock)
    }
}

enum CashQuickEdit {
    static func apply(_ saved: CashQuickEditSaved, to product: CashProduct) -> CashProduct { product.updated(saved) }
}

struct CashQuickEditSheet: View {
    let product: CashProduct
    let settings: CashStoreSettings
    let onSaved: (CashQuickEditSaved) -> Void
    /// The Catalog opened on this item (the sheet closes first).
    var onOpenCatalog: (() -> Void)? = nil
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var item: CashCatalogItem?
    @State private var failed = false
    @State private var name = ""
    @State private var price: Int?
    @State private var treatment = "default"
    @State private var rate = ""
    @State private var barcode = ""
    @State private var quantity = ""
    @State private var countedFrom = 0
    @State private var working = false
    @State private var seed = 0

    private var canEditInventory: Bool { workspace.can(.inventoryEdit) }
    private var countsStock: Bool { item.map { $0.isProduct && $0.trackInventory && !$0.isPack && $0.inventory != nil } ?? false }
    private var keepsNoPrice: Bool { item?.defaultUnitAmount == 0 }
    private var owes: Int { min(0, item?.inventory?.quantityOnHand ?? 0) }

    var body: some View {
        ProviderModal(title: LF("Edit %@", item?.name ?? product.name), subtitle: item != nil ? L("The name, price and tax, right from the counter.") : nil, systemImage: "pencil", accent: .mango,
                      isDirty: item != nil && dirty, form: form, primaryTitle: item != nil ? L("Save changes") : nil, isWorking: working, primaryIcon: "save", onPrimary: item != nil ? { save() } : nil) {
            if let item {
                fields(item)
            } else if failed {
                Text(L("This item could not be opened here.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                catalogLink
            } else {
                LoadingState()
            }
        }
        .task { await load() }
    }

    private var dirty: Bool {
        guard let item else { return false }
        return name != item.name || (price ?? 0) != item.defaultUnitAmount || treatment != item.taxTreatment || barcode != (item.inventory?.barcode ?? "")
            || (!quantity.isEmpty && Int(quantity) != item.inventory?.quantityOnHand)
    }

    @ViewBuilder private func fields(_ item: CashCatalogItem) -> some View {
        PMTextField(L("Name"), text: Binding(get: { name }, set: { name = String($0.prefix(140)) }), key: "name", form: form, required: true)
        MoneyField(label: LF("Price (%@)", settings.currency), cents: $price, key: "price", form: form,
                   hint: keepsNoPrice && price == nil ? L("No price yet: it is asked for when charging. Type one here to stop asking.") : nil, required: !keepsNoPrice)
            .id("price-\(seed)")
        CashTaxField(treatment: $treatment, rate: $rate, price: price, settings: settings, form: form)
        if countsStock {
            if canEditInventory {
                PMTextField(L("On the shelf"), text: Binding(get: { quantity }, set: { quantity = $0.filter(\.isNumber); form.clear("quantity") }), key: "quantity", form: form,
                            hint: owes < 0 ? LF("%d short: type what is really there to set it right.", -owes) : L("A change is recorded as a stock correction."), keyboard: .numberPad)
                BarcodeField(label: L("Barcode"), text: $barcode, key: "barcode", form: form, hint: L("Scan it here to save it."))
            } else {
                Text(owes < 0 ? LF("%d short on the shelf: it needs a count. Your role cannot change stock from here.", -owes)
                     : LF("%d on the shelf. Your role cannot change stock from here.", item.inventory?.quantityOnHand ?? 0))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
            }
        }
        // Web: the rest of the item lives in the Catalog, under a dashed rule.
        StitchedDivider()
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(L("Photo, category, description and the rest are in the Catalog.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                Spacer(minLength: 8)
                catalogLink
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Photo, category, description and the rest are in the Catalog.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                catalogLink
            }
        }
    }

    @ViewBuilder private var catalogLink: some View {
        if workspace.can(.catalogView), let onOpenCatalog {
            Button { dismiss(); onOpenCatalog() } label: {
                HStack(spacing: 6) {
                    Text(L("Open in the Catalog"))
                    Glyph("arrow-up-right", size: 16)
                }
                .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private func load() async {
        do {
            let loaded: CashCatalogItem = try await API.get("/provider-catalog/\(product.catalogItemId)")
            name = loaded.name
            price = loaded.defaultUnitAmount > 0 ? loaded.defaultUnitAmount : nil
            treatment = loaded.taxTreatment
            rate = loaded.taxTreatment == "standard" ? CashCatalogRules.rateText(loaded.taxRateBps) : ""
            barcode = loaded.inventory?.barcode ?? ""
            // Below zero is not a count to show: the box starts empty, for what is really there.
            quantity = (loaded.inventory?.quantityOnHand).map { $0 >= 0 ? "\($0)" : "" } ?? ""
            countedFrom = loaded.inventory?.quantityOnHand ?? 0
            item = loaded
            seed += 1
        } catch {
            failed = true
        }
    }

    private func save() {
        guard let item else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = Int(quantity)
        let owesCount = (item.inventory?.quantityOnHand ?? 0) < 0
        let ownRate = treatment == "standard" ? CashCatalogRules.rateBps(rate) : nil
        guard form.check([
            ("name", trimmed.isEmpty ? L("Add the name first.") : nil),
            ("price", CashCatalogRules.priceError(price, item: item)),
            ("taxRate", treatment == "standard" && ownRate == nil ? L("Enter a tax rate from 0 to 100.") : nil),
            ("quantity", countsStock && canEditInventory && count == nil && !owesCount ? L("Enter how many are on the shelf.") : nil),
        ]) else { return }

        // Only what changed is sent, so nothing else on the item is touched.
        let amount = price ?? 0
        var itemPatch: [String: Any?] = [:]
        if trimmed != item.name { itemPatch["name"] = trimmed }
        if amount != item.defaultUnitAmount { itemPatch["defaultUnitAmount"] = amount }
        if treatment != item.taxTreatment || ownRate != (item.taxTreatment == "standard" ? item.taxRateBps : nil) {
            itemPatch["taxTreatment"] = treatment
            itemPatch["taxRateBps"] = ownRate
        }
        var stockPatch: [String: Any?] = [:]
        if countsStock && canEditInventory, let inventory = item.inventory {
            if barcode.nonEmpty != inventory.barcode?.nonEmpty { stockPatch["barcode"] = barcode.nonEmpty }
            if let count, count != countedFrom {
                stockPatch["quantityOnHand"] = count
                stockPatch["countedFrom"] = countedFrom
                stockPatch["clientRequestId"] = "catalog-\(cashRequestId())"
            }
        }
        guard !itemPatch.isEmpty || !stockPatch.isEmpty else { dismiss(); return }
        working = true
        Task {
            defer { working = false }
            do {
                if !itemPatch.isEmpty { let _: EmptyResponse = try await API.patch("/provider-catalog/\(item.id)", body: itemPatch) }
                if !stockPatch.isEmpty { let _: EmptyResponse = try await API.patch("/provider-catalog/\(item.id)/inventory", body: stockPatch) }
                onSaved(CashQuickEditSaved(
                    catalogItemId: item.id, name: trimmed, unitAmount: amount, taxTreatment: treatment,
                    taxRateBps: CashCatalogRules.effectiveRate(treatment: treatment, rateBps: ownRate, settings: settings),
                    barcode: countsStock && canEditInventory ? barcode.nonEmpty : item.inventory?.barcode
                ))
                Toast.show(LF("%@ was updated.", trimmed))
                announceDataChanged()
                dismiss()
            } catch {
                if let refusal = CashCatalogRules.stockRefusal(error), refusal.0 == "barcode" || refusal.0 == "quantity" {
                    if refusal.0 == "quantity", let fresh: CashCatalogItem = try? await API.get("/provider-catalog/\(item.id)") {
                        countedFrom = fresh.inventory?.quantityOnHand ?? countedFrom
                    }
                    _ = form.check([(refusal.0, refusal.1)])
                    return
                }
                Toast.error(error, fallback: item.isProduct ? L("Could not save this product.") : L("Could not save this service."))
            }
        }
    }
}
