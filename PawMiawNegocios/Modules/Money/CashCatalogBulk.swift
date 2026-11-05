//
//  CashCatalogBulk.swift
//  PawMiawNegocios
//
//  Changes to several catalog items at once (web: catalog-page/catalog-bulk.tsx,
//  use-provider-catalog.ts `useBulkUpdateCatalogItems`): move them to a
//  category, raise or lower their prices by a percentage, archive or restore
//  them. The server has no bulk endpoint: one request per item, each logged on
//  its own; what fails is listed with why and does not stop the rest. Also the
//  quick price of one item (catalog-price-sheet.tsx) and the categories
//  (catalog-category-manager.tsx).
//

import SwiftUI

/// What a run over several items left undone, with why.
struct CashBulkOutcome {
    var done: Int = 0
    var failed: [(name: String, message: String)] = []
}

enum CashCatalogBulk {
    /// The same change to each item, one request after another; a dropped connection stops the run.
    static func run(_ changes: [(item: CashCatalogItem, body: [String: Any?])], progress: @escaping (Int) -> Void) async -> CashBulkOutcome {
        var outcome = CashBulkOutcome()
        for (index, change) in changes.enumerated() {
            do {
                let _: EmptyResponse = try await API.patch("/provider-catalog/\(change.item.id)", body: change.body)
                outcome.done += 1
            } catch {
                outcome.failed.append((change.item.name, errorText(error, fallback: "")))
                if let api = error as? APIError, api.isOffline {
                    for rest in changes.dropFirst(index + 1) { outcome.failed.append((rest.item.name, api.message)) }
                    break
                }
            }
            progress(index + 1)
        }
        if outcome.done > 0 { announceDataChanged() }
        return outcome
    }

    /// A price moved by a percentage (10 raises it 10 %, −10 lowers it); nil when it would not be a price.
    static func movedPrice(_ amount: Int, percent: Double, whole: Bool) -> Int? {
        guard amount > 0 else { return nil }
        let raw = Double(amount) * (100 + percent) / 100
        let next = whole ? Int((raw / 100).rounded()) * 100 : Int(raw.rounded())
        return next > 0 ? next : nil
    }
}

/// The failures of a run.
private struct CashBulkFailures: View {
    let outcome: CashBulkOutcome

    var body: some View {
        NoticeCard(
            tone: .problem,
            title: outcome.done > 0 ? LF("%d were changed; %d could not be.", outcome.done, outcome.failed.count) : LP(outcome.failed.count, "%d item could not be changed.", "%d items could not be changed."),
            message: (outcome.failed.prefix(6).map { "\($0.name)\($0.message.isEmpty ? "" : " — \($0.message)")" } + (outcome.failed.count > 6 ? [LF("…and %d more", outcome.failed.count - 6)] : [])).joined(separator: "\n")
        )
    }
}

private func cashBusyTitle(_ progress: (done: Int, total: Int)?) -> String {
    progress.map { LF("Saving %d of %d…", $0.done, $0.total) } ?? L("Saving…")
}

/// What the sheet is about (web `ModalContextPills`): how many items, and their names when one or two.
private struct CashCountPills: View {
    let items: [CashCatalogItem]
    var body: some View {
        FlowLayout(spacing: 6) {
            Chip(text: LP(items.count, "%d item", "%d items"), tone: .muted)
            if items.count <= 2 { ForEach(items) { Chip(text: $0.name, tone: .muted) } }
        }
    }
}

// MARK: - Category

struct CashBulkCategorySheet: View {
    let items: [CashCatalogItem]
    let categories: [CashCategory]
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var categoryId = ""
    @State private var touched = false
    @State private var progress: (done: Int, total: Int)?
    @State private var outcome: CashBulkOutcome?

    private var itemType: String? { Set(items.map(\.itemType)).count == 1 ? items.first?.itemType : nil }
    private var offered: [CashCategory] { categories.filter { $0.itemType == itemType && $0.active }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
    private var changes: [CashCatalogItem] { items.filter { ($0.category?.id ?? "") != categoryId } }

    var body: some View {
        ProviderModal(title: L("Change category"), subtitle: L("Every selected item moves to the category you choose."), systemImage: "tags", accent: .aqua, isDirty: touched,
                      primaryTitle: progress != nil ? cashBusyTitle(progress) : LP(changes.count, "Move %d item", "Move %d items"), isWorking: progress != nil,
                      cancelTitle: outcome != nil ? L("Close") : L("Cancel"), primaryIcon: "tags",
                      primaryDisabled: itemType == nil || changes.isEmpty, onPrimary: { apply() }) {
            CashCountPills(items: items)
            if itemType == nil {
                NoticeCard(tone: .warning, title: L("You selected services and products. A category belongs to one or the other: select only services, or only products."))
            } else {
                MenuField(label: itemType == "product" ? L("Product category") : L("Service category"),
                          options: [(value: "", title: L("Uncategorized"))] + offered.map { (value: $0.id, title: $0.name) },
                          selection: Binding(get: { categoryId }, set: { categoryId = $0; touched = true }))
            }
            if let outcome { CashBulkFailures(outcome: outcome) }
        }
        .presentationDetents([.medium, .large])
    }

    private func apply() {
        let targets = changes
        let chosen = offered.first { $0.id == categoryId }
        progress = (0, targets.count)
        Task {
            let result = await CashCatalogBulk.run(targets.map { ($0, ["providerCatalogCategoryId": categoryId.nonEmpty]) }) { done in progress = (done, targets.count) }
            progress = nil
            if result.failed.isEmpty {
                Toast.show(chosen.map { LF(result.done == 1 ? "%d item moved to %@." : "%d items moved to %@.", result.done, $0.name) } ?? LP(result.done, "%d item is now uncategorized.", "%d items are now uncategorized."))
                onDone()
                dismiss()
            } else {
                outcome = result
            }
        }
    }
}

// MARK: - Prices

struct CashBulkPriceSheet: View {
    let items: [CashCatalogItem]
    let settings: CashStoreSettings?
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var direction = "raise"
    @State private var percentText = ""
    @State private var whole = false
    @State private var progress: (done: Int, total: Int)?
    @State private var outcome: CashBulkOutcome?

    private static let maxRaise = 500.0

    private var percent: Double? { Double(percentText.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) }
    private var problem: String? {
        guard let percent else { return L("Type the percentage first.") }
        if !percent.isFinite || percent <= 0 { return L("The percentage must be above 0.") }
        if direction == "lower" && percent >= 100 { return L("A price cannot be lowered by 100% or more.") }
        if direction == "raise" && percent > Self.maxRaise { return LF("Raise prices by %d%% at most.", Int(Self.maxRaise)) }
        return nil
    }
    private var signed: Double? { problem == nil ? percent.map { direction == "raise" ? $0 : -$0 } : nil }
    private var preview: [(item: CashCatalogItem, next: Int?)] { items.map { item in (item, signed.flatMap { s in CashCatalogBulk.movedPrice(item.defaultUnitAmount, percent: s, whole: whole) }) } }
    private var priced: [(item: CashCatalogItem, next: Int?)] { preview.filter { $0.item.defaultUnitAmount > 0 } }
    private var changes: [(item: CashCatalogItem, next: Int)] { priced.compactMap { entry in entry.next.flatMap { $0 != entry.item.defaultUnitAmount ? (entry.item, $0) : nil } } }

    var body: some View {
        ProviderModal(title: L("Change prices"), subtitle: L("Raise or lower the price of every selected item by a percentage. You see each new price before it is saved."), systemImage: "percent", accent: .mango,
                      isDirty: direction != "raise" || whole || !percentText.isEmpty, form: form,
                      primaryTitle: progress != nil ? cashBusyTitle(progress) : signed == nil ? L("Change prices") : LP(changes.count, "Change %d price", "Change %d prices"),
                      isWorking: progress != nil, cancelTitle: outcome != nil ? L("Close") : L("Cancel"), primaryIcon: "percent",
                      primaryDisabled: priced.isEmpty, onPrimary: { apply() }) {
            CashCountPills(items: items)
            FormField(label: L("What to do")) {
                Segmented(options: [
                    .init("raise", L("Raise"), icon: "trending-up", tone: .page),
                    .init("lower", L("Lower"), icon: "trending-down", tone: .page),
                ], selection: $direction, look: .raised, label: L("What to do"), fill: true)
            }
            FormField(label: L("By how much (%)"), key: "percent", form: form, required: true) {
                HStack(spacing: 8) {
                    TextField("10", text: Binding(get: { percentText }, set: { percentText = $0; form.clear("percent") }))
                        .keyboardType(.decimalPad)
                        .font(.brandHeading(18, relativeTo: .body))
                        .monospacedDigit()
                    Text("%").font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkSoft)
                }
                .fieldChrome(invalid: form.error("percent") != nil)
            }
            ToggleRow(title: L("Round to whole amounts"), subtitle: LF("%@ instead of cents: prices end in .00.", cashMoney(11_000, settings?.currency)), isOn: $whole)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(L("Item").uppercased())
                    Spacer(minLength: 8)
                    Text(L("Now").uppercased()).frame(width: 84, alignment: .trailing)
                    Color.clear.frame(width: 14, height: 1)
                    Text(L("After").uppercased()).frame(width: 84, alignment: .trailing)
                }
                .font(.brandText(10.6, weight: .heavy)).tracking(1.27).foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.wash(Theme.surfaceMuted, 55))
                ForEach(preview, id: \.item.id) { entry in
                    RowDivider()
                    HStack(spacing: 12) {
                        Text(entry.item.name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                        Spacer(minLength: 8)
                        if entry.item.defaultUnitAmount > 0 {
                            Text(cashMoney(entry.item.defaultUnitAmount, entry.item.currency)).font(Theme.text(14)).monospacedDigit().foregroundStyle(Theme.inkSoft).frame(width: 84, alignment: .trailing)
                            Glyph("arrow-right", size: 14).foregroundStyle(Theme.inkSoft)
                            Text(entry.next.map { cashMoney($0, entry.item.currency) } ?? "—").font(.brandHeading(16, relativeTo: .body)).monospacedDigit().foregroundStyle(Theme.inkStrong).frame(width: 84, alignment: .trailing)
                        } else {
                            Text(L("No price: stays as it is")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1.5))
            let unpriced = preview.count - priced.count
            Text(([signed == nil ? LP(priced.count, "%d price will change.", "%d prices will change.") : LP(changes.count, "%d price changes.", "%d prices change.")]
                  + (unpriced > 0 ? [LP(unpriced, "%d item has no price and stays as it is.", "%d items have no price and stay as they are.")] : [])).joined(separator: " "))
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            if let outcome { CashBulkFailures(outcome: outcome) }
        }
    }

    private func apply() {
        guard form.check([("percent", problem)]), !changes.isEmpty else { return }
        let targets = changes
        progress = (0, targets.count)
        Task {
            let result = await CashCatalogBulk.run(targets.map { ($0.item, ["defaultUnitAmount": $0.next]) }) { done in progress = (done, targets.count) }
            progress = nil
            if result.failed.isEmpty {
                Toast.show(LP(result.done, "%d price changed.", "%d prices changed."))
                onDone()
                dismiss()
            } else {
                outcome = result
            }
        }
    }
}

// MARK: - Archive and restore

struct CashBulkArchiveSheet: View {
    let items: [CashCatalogItem]
    /// Items a visit bills by default or a pack draws on, by id.
    let leanedOn: Set<String>
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var outcome: CashBulkOutcome?

    private var targets: [CashCatalogItem] { items.filter(\.active) }

    var body: some View {
        let used = targets.filter { leanedOn.contains($0.id) }
        ProviderModal(title: LP(targets.count, "Archive %d item?", "Archive %d items?"), subtitle: L("They stop being offered on new bills, visits and at the counter. Past bills keep them, and you can restore them any time."),
                      systemImage: "triangle-alert", accent: .pink, primaryTitle: L("Archive"), primaryVariant: .destructive, isWorking: working,
                      cancelTitle: outcome != nil ? L("Close") : L("Cancel"), primaryIcon: "triangle-alert", onPrimary: targets.isEmpty ? nil : { apply() }) {
            if let outcome {
                CashBulkFailures(outcome: outcome)
            } else if !used.isEmpty {
                NoticeCard(tone: .warning,
                           title: LP(used.count, "%d of them is used by a visit or a pack:", "%d of them are used by visits or packs:"),
                           message: used.prefix(5).map(\.name).joined(separator: ", ") + (used.count > 5 ? " " + LF("…and %d more", used.count - 5) : "") + "\n" + L("Those visits start without a price and those packs stop working until you restore the item or point them at another."))
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func apply() {
        working = true
        Task {
            let result = await CashCatalogBulk.run(targets.map { ($0, ["active": false]) }) { _ in }
            working = false
            if result.failed.isEmpty {
                Toast.show(LP(result.done, "%d item archived.", "%d items archived."))
                onDone()
                dismiss()
            } else {
                outcome = result
            }
        }
    }
}

// MARK: - One item's price

/// "Cambiar precio": the price staff see first on a bill or at the counter, and its tax.
struct CashCatalogPriceSheet: View {
    let item: CashCatalogItem
    let settings: CashStoreSettings?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var price: Int?
    @State private var working = false
    @State private var seed = 0

    /// What a client pays at the typed price, with the item's own tax (web `clientPrice`).
    private var pays: String? {
        guard let price, price > 0 else { return nil }
        let bps = CashCatalogRules.effectiveRate(treatment: item.taxTreatment, rateBps: item.taxRateBps, settings: settings)
        return CashCatalogRules.payText(price: price, bps: bps, settings: settings)
    }

    var body: some View {
        ProviderModal(title: item.defaultUnitAmount > 0 ? L("Change price") : L("Set price"), subtitle: L("What staff see first on an invoice or at the counter. It can be changed on each sale."),
                      systemImage: "tag", accent: .hue(CashCatalogLook.hue(item.itemType)),
                      isDirty: price != nil && price != item.defaultUnitAmount, form: form,
                      primaryTitle: L("Save price"), isWorking: working, primaryIcon: "save", onPrimary: { save() }) {
            FlowLayout(spacing: 6) {
                Chip(text: item.name, tone: .muted)
                if item.defaultUnitAmount > 0 {
                    Chip(text: LF("Now %@", cashMoney(item.defaultUnitAmount, item.currency)), tone: .muted)
                }
            }
            MoneyField(label: LF("Price (%@)", settings?.currency ?? item.currency ?? ""), cents: $price, key: "price", form: form,
                       hint: pays ?? (item.defaultUnitAmount == 0 ? L("No price yet: it will be asked for when charging. Add one here to stop asking.") : nil), required: true)
                .id("price-\(seed)")
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            price = item.defaultUnitAmount > 0 ? item.defaultUnitAmount : nil
            seed += 1
        }
    }

    /// Only the price is sent, so nothing else on the item is touched; here an empty box is not "leave it without one".
    private func save() {
        guard form.check([("price", CashCatalogRules.priceError(price, item: nil))]) else { return }
        guard price != item.defaultUnitAmount else { dismiss(); return }
        working = true
        Task {
            defer { working = false }
            do {
                let _: EmptyResponse = try await API.patch("/provider-catalog/\(item.id)", body: ["defaultUnitAmount": price ?? 0])
                Toast.show(LF("%@ now costs %@.", item.name, cashMoney(price ?? 0, item.currency)))
                announceDataChanged()
                onSaved()
                dismiss()
            } catch {
                form.apply(error, known: ["defaultUnitAmount": "price"])
            }
        }
    }
}

// MARK: - Categories

/// The categories of services and of products: add, rename, stop offering, remove
/// (web `CatalogCategoryManager`). Changes are saved as they are made.
struct CashCategoryManagerSheet: View {
    let categories: [CashCategory]
    let items: [CashCatalogItem]
    var startType: String = "service"
    let onChanged: () -> Void
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var list: [CashCategory] = []
    @State private var type = "service"
    @State private var newName = ""
    @State private var renaming: CashCategory?
    @State private var renameText = ""
    @State private var removing: CashCategory?
    @State private var working = false
    @State private var savingId: String?

    private var canCreate: Bool { workspace.can(.catalogCreate) }
    private var canEdit: Bool { workspace.can(.catalogEdit) }
    private var shown: [CashCategory] { list.filter { $0.itemType == type }.sorted { ($0.active ? 0 : 1, $0.name.lowercased()) < ($1.active ? 0 : 1, $1.name.lowercased()) } }
    private func count(_ category: CashCategory) -> Int { items.filter { $0.category?.id == category.id }.count }

    var body: some View {
        // Changes save as they are made: the footer is only "Done" (web `CatalogCategoryManager`).
        ProviderModal(title: L("Categories"), subtitle: L("Group what you charge for and what you sell. Services and products have their own categories; changes are saved as you make them."),
                      systemImage: "tags", accent: .aqua, form: form, primaryTitle: L("Done"), showsCancel: false, onPrimary: { dismiss() }) {
            Segmented(options: [
                .init("service", L("Services"), icon: "briefcase-medical", count: list.filter { $0.itemType == "service" }.count, tone: CashCatalogLook.tone("service")),
                .init("product", L("Products"), icon: "package", count: list.filter { $0.itemType == "product" }.count, tone: CashCatalogLook.tone("product")),
            ], selection: Binding(get: { type }, set: { type = $0; renaming = nil; form.clear("name") }), look: .raised, label: L("Kind of category"), fill: true)
            if canCreate {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField(type == "product" ? L("New product category, e.g. Food") : L("New service category, e.g. Grooming"), text: Binding(get: { newName }, set: { newName = String($0.prefix(80)); form.clear("name") }))
                            .fieldChrome(invalid: form.error("name") != nil)
                            .accessibilityLabel(type == "product" ? L("New product category") : L("New service category"))
                            .submitLabel(.done)
                            .onSubmit { add() }
                        PMButton(L("Add"), systemImage: "plus", isWorking: working && renaming == nil) { add() }
                    }
                    if let error = form.error("name") { Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
                }
                .id("name")
            }
            if shown.isEmpty {
                EmptyState(systemImage: "tags", title: type == "product" ? L("No product categories yet") : L("No service categories yet"),
                           message: type == "product" ? L("Add categories such as Food, Medicines or Accessories. Items without one show as Uncategorized.") : L("Add categories such as Consults, Grooming or Boarding. Items without one show as Uncategorized."),
                           accent: Theme.mango)
            } else {
                VStack(spacing: 0) {
                    ForEach(shown) { category in
                        if category.id != shown.first?.id { RowDivider() }
                        row(category)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1.5))
            }
            if !canEdit && !shown.isEmpty {
                Text(L("Your role can add categories; renaming and removing them takes permission to edit the catalog.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
        .onAppear { list = categories; type = startType }
        .sheet(item: $removing) { category in
            let inIt = count(category)
            ConfirmSheet(title: LF("Remove %@?", category.name),
                         message: inIt > 0 ? LP(inIt, "%d item is in it. It stays in the catalog, without a category. This cannot be undone.", "%d items are in it. They stay in the catalog, without a category. This cannot be undone.") : L("No item uses it. This cannot be undone."),
                         confirmTitle: L("Remove category"), destructive: true) { _ in
                let _: EmptyResponse = try await API.delete("/provider-catalog/categories/\(category.id)")
                list.removeAll { $0.id == category.id }
                Toast.show(inIt > 0 ? LF(inIt == 1 ? "%@ was removed. %d item is now uncategorized." : "%@ was removed. %d items are now uncategorized.", category.name, inIt) : LF("%@ was removed.", category.name))
                onChanged()
            }
        }
    }

    @ViewBuilder private func row(_ category: CashCategory) -> some View {
        let inIt = count(category)
        Group {
            if renaming?.id == category.id {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        TextField("", text: Binding(get: { renameText }, set: { renameText = String($0.prefix(80)); form.clear("rename") }))
                            .fieldChrome(invalid: form.error("rename") != nil)
                            .accessibilityLabel(LF("New name for %@", category.name))
                            .submitLabel(.done)
                            .onSubmit { rename(category) }
                        PMButton(L("Save"), systemImage: "check", isWorking: working && savingId == category.id) { rename(category) }
                        iconButton("x", label: L("Cancel the rename")) { renaming = nil; form.clear("rename") }
                    }
                    if let error = form.error("rename") { Text(error).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
                }
                .id("rename")
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(category.name).font(Theme.text(14, weight: .bold)).foregroundStyle(category.active ? Theme.inkStrong : Theme.inkSoft).lineLimit(1)
                        Text([inIt == 0 ? L("No items") : LP(inIt, "%d item", "%d items"), category.active ? nil : L("Not offered for new items")].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if canEdit {
                        if savingId == category.id && renaming == nil { ProgressView().controlSize(.small) }
                        Toggle(isOn: Binding(get: { category.active }, set: { toggle(category, to: $0) })) { EmptyView() }
                            .toggleStyle(PMSwitchStyle())
                            .labelsHidden()
                            .fixedSize()
                            .disabled(savingId != nil)
                            .accessibilityLabel(LF("Offer %@ for new items", category.name))
                        iconButton("pencil", label: LF("Rename %@", category.name)) { renameText = category.name; form.clear("rename"); renaming = category }
                        iconButton("trash-2", label: LF("Remove %@", category.name)) { removing = category }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func iconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        IconCircleButton(systemImage: icon, label: label, size: 40, bordered: false, action: action)
    }

    private func add() {
        guard form.check([("name", newName.nonEmpty == nil ? L("Add the category name first.") : list.contains(where: { $0.itemType == type && $0.name.lowercased() == newName.trimmingCharacters(in: .whitespaces).lowercased() }) ? L("There is already a category with that name.") : nil)]),
              let text = newName.nonEmpty else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let created: CashCategory = try await API.post("/provider-catalog/categories", body: ["itemType": type, "name": text, "active": true])
                list.append(created)
                newName = ""
                Toast.show(LF("%@ is ready to use.", created.name))
                onChanged()
            } catch {
                form.apply(error, known: ["name": "name"])
            }
        }
    }

    private func rename(_ category: CashCategory) {
        guard form.check([("rename", renameText.nonEmpty == nil ? L("Add the category name first.") : nil)]), let text = renameText.nonEmpty else { return }
        working = true
        savingId = category.id
        Task {
            defer { working = false; savingId = nil }
            do {
                let saved: CashCategory = try await API.patch("/provider-catalog/categories/\(category.id)", body: ["name": text])
                if let index = list.firstIndex(where: { $0.id == category.id }) { list[index] = saved }
                Toast.show(LF("%@ is now %@.", category.name, saved.name))
                renaming = nil
                onChanged()
            } catch {
                form.apply(error, known: ["name": "rename"])
            }
        }
    }

    private func toggle(_ category: CashCategory, to active: Bool) {
        guard active != category.active else { return }
        savingId = category.id
        Task {
            defer { savingId = nil }
            do {
                let saved: CashCategory = try await API.patch("/provider-catalog/categories/\(category.id)", body: ["active": active])
                if let index = list.firstIndex(where: { $0.id == category.id }) { list[index] = saved }
                Toast.show(saved.active ? LF("%@ is offered for new items again.", saved.name) : LF("%@ is no longer offered for new items. The items in it keep it.", saved.name))
                onChanged()
            } catch {
                Toast.error(error, fallback: L("Could not change this category."))
            }
        }
    }
}
