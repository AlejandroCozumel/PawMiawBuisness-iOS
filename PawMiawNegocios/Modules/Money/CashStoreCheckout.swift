//
//  CashStoreCheckout.swift
//  PawMiawNegocios
//
//  The Store's counter with a sale another screen sent here already filled in
//  (web: provider.store.tsx with `?client&pet&rx` from the Pharmacy, or
//  `?client&checkout` from a bill or a visit): the client and pet chosen, a
//  hand-over's medicines in the sale against their prescription lines, or the
//  bills to charge selected with room for products from the shelf. Once it is
//  charged and the receipt closed, it goes back to the screen that sent it.
//

import SwiftUI

struct StoreCheckoutScreen: View {
    let prefill: StorePrefill

    var body: some View {
        RequireLocation { CashCheckoutPage(prefill: prefill) }
            .providerPage(L("Store"))
    }
}

private struct CashCheckoutPage: View {
    let prefill: StorePrefill
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var device = CashDeviceRegister()
    @State private var settings: CashStoreSettings?
    @State private var settingsError: String?
    @State private var registerShown = false

    private var what: String {
        if !prefill.lines.isEmpty || prefill.prescriptionId != nil { return L("The prescription’s medicines are in the sale, each against its prescription line. Stock, the prescription and the receipt follow the sale.") }
        if prefill.invoiceId != nil || prefill.appointmentId != nil { return L("The bill is selected: add anything else from the counter and charge it all at once.") }
        return L("Sell at the counter — stock, tax and the receipt take care of themselves.")
    }

    var body: some View {
        Group {
            if !workspace.can(.salesSell) {
                PageScroll { NoAccessState(message: L("Ask the workspace owner to let your role sell.")) }
            } else {
                PageScroll(maxWidth: 1180) {
                    // The Store's own header, on the Sell tab: the register at this device at the top.
                    ModuleHeader(icon: "shopping-cart", title: L("Store"), subtitle: what, storageKey: "store-checkout") {
                        if let register = device.register {
                            if device.registers.count > 1 {
                                Menu {
                                    ForEach(device.registers) { entry in
                                        Button { device.choose(entry.id) } label: {
                                            if entry.id == register.id { GlyphLabel(entry.name, icon: "check") } else { Text(entry.name) }
                                        }
                                    }
                                } label: {
                                    FilterMenuLabel(title: register.name)
                                }
                                .accessibilityLabel(L("Register at this device"))
                            }
                            Button { registerShown = true } label: {
                                Chip(text: register.openSessionId != nil ? LF("%@ open", register.name) : LF("%@ closed", register.name), tone: (register.openSessionId != nil) ? .custom(ProviderState.done.color) : .muted, icon: (register.openSessionId != nil) ? "lock-open" : "lock", percent: 16, ink: (register.openSessionId != nil) ? Theme.inkStrong : Theme.inkSoft, border: 60, size: .header)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let settings {
                        CashCounter(settings: settings, device: device, openRegister: { registerShown = true }, prefill: prefill, onCharged: {
                            announceDataChanged()
                            dismiss()
                        })
                    } else if let settingsError {
                        ErrorState(message: settingsError) { await load() }
                    } else {
                        LoadingState()
                    }
                }
                .modifier(CashKeepsRegister(device: device))
                .task { await load() }
                .navigationDestination(isPresented: $registerShown) {
                    PageScroll(maxWidth: 980) {
                        ModuleHeader(icon: "wallet", title: L("Register"), subtitle: device.register?.name, storageKey: "store-register")
                        CashRegisterTab(device: device)
                    }
                    .providerPage(L("Register"))
                }
            }
        }
    }

    private func load() async {
        guard settings == nil else { return }
        do {
            settings = try await API.get("/provider-store/settings")
            settingsError = nil
        } catch {
            settingsError = errorText(error)
        }
    }
}

// MARK: - A hand-over read from its prescription

/// What a signed prescription hands over now: each line sold through the Catalog
/// with its next fill (web: prescription-view-sheet.tsx `prescriptionHandOver`).
enum CashHandOver {
    struct Loaded { let clientId: String; let petId: String; let lines: [StorePrefill.Line] }

    private struct Prescription: Decodable {
        struct Fill: Decodable { let remaining: Int? }
        struct Product: Decodable { let active: Bool? }
        struct Item: Decodable {
            let id: String
            let catalogItemId: String?
            let product: Product?
            let fill: Fill?
            let nextFill: Int?
            let handOverBlock: String?
        }
        let providerClientId: String
        let providerClientPetId: String
        let status: String?
        let items: [Item]?
    }

    static func load(_ prescriptionId: String) async throws -> Loaded {
        let rx: Prescription = try await API.get("/provider-prescriptions/\(prescriptionId)")
        let lines: [StorePrefill.Line] = (rx.items ?? []).compactMap { item in
            let catalog = item.product?.active == false ? nil : item.catalogItemId
            let quantity = item.nextFill ?? 0
            guard item.handOverBlock == nil, let catalog, quantity > 0 else { return nil }
            return StorePrefill.Line(catalogItemId: catalog, quantity: Double(quantity), prescriptionItemId: item.id)
        }
        return Loaded(clientId: rx.providerClientId, petId: rx.providerClientPetId, lines: lines)
    }
}

// MARK: - A code on more than one product

struct CashAmbiguousCode: Identifiable {
    let id = UUID()
    let code: String
    let products: [CashProduct]
}

/// "¿Qué producto es?": a code saved on two products; the person says which is being sold.
struct CashAmbiguousCodeSheet: View {
    let found: CashAmbiguousCode
    let onChoose: (CashProduct) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ProviderModal(title: L("Which product is it?"), subtitle: LF("The code %@ is on %d products. Choose the one being sold.", found.code, found.products.count), systemImage: "scan-barcode", accent: .mango) {
            VStack(spacing: 8) {
                ForEach(found.products) { product in
                    Button {
                        dismiss()
                        onChoose(product)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                if let sku = product.sku?.nonEmpty { Text(sku).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                            }
                            Spacer(minLength: 8)
                            Text(product.unitAmount > 0 ? cashMoney(product.unitAmount, product.currency) : L("No price"))
                                .font(.brandHeading(16)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                        }
                        .padding(12)
                        .frame(minHeight: 56)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1.5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(L("Give each product its own barcode in the Catalog so a scan finds one.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
        .presentationDetents([.medium, .large])
    }
}
