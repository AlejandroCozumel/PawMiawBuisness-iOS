//
//  CashServiceDefaults.swift
//  PawMiawNegocios
//
//  "Lo que cobra cada visita" (web: catalog-page/service-defaults-panel.tsx):
//  which catalog service each kind of visit starts its bill with. A booking
//  for "Baño y cepillado" starts its bill with the item chosen here; it can
//  still be changed on the visit. One optional item per kind, grouped by lane.
//

import SwiftUI

/// The kinds of visit the business offers (`/appointment-services?scope=provider`).
struct CashServiceCatalog: Decodable {
    struct Lane: Decodable, Identifiable { let id: String; let label: String; let description: String? }
    struct DefaultItem: Decodable, Hashable { let id: String; let name: String; let currency: String?; let defaultUnitAmount: Int; let active: Bool }
    struct Service: Decodable, Identifiable { let id: String; let category: String; let label: String; let description: String?; let defaultBillingItem: DefaultItem? }
    let categories: [Lane]
    let services: [Service]
}

struct CashServiceDefaultsPanel: View {
    /// The kinds of visit, read by the Catalog page; nil while loading.
    let catalog: CashServiceCatalog?
    /// Active services that can be a default.
    let billingItems: [CashCatalogItem]
    let canEdit: Bool
    /// Reads the kinds of visit again after a change.
    let reload: () async -> Void
    @State private var saving: String?
    @State private var open: Set<String> = []

    private var groups: [(lane: CashServiceCatalog.Lane, services: [CashServiceCatalog.Service])] {
        guard let catalog else { return [] }
        return catalog.categories.compactMap { lane in
            let services = catalog.services.filter { $0.category == lane.id }
            return services.isEmpty ? nil : (lane, services)
        }
    }

    var body: some View {
        let all = groups.flatMap(\.services)
        let mapped = all.filter { $0.defaultBillingItem != nil }.count
        // Web `ServiceDefaultsPanel`: a card, its header with "3 of 5 set", one folding box per lane.
        SectionCard(title: L("What each visit charges"), subtitle: L("The item a booking starts its bill with. Staff can still change it on the visit."), icon: "calendar-check-2", accent: Theme.blue) {
            if !all.isEmpty {
                Text(LF("%d of %d set", mapped, all.count))
                    .font(Theme.text(12, weight: .heavy))
                    .foregroundStyle(Theme.inkStrong)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Theme.wash(Theme.blue, 10), in: Capsule())
                    .fixedSize()
            }
        } content: {
            if catalog == nil {
                LoadingState()
            } else if groups.isEmpty {
                EmptyState(systemImage: "calendar-check-2", title: L("No visit types yet"), message: L("Once the workspace offers a kind of visit, its services show up here so each can start its bill with an item."), accent: Theme.mango)
            } else {
                VStack(spacing: 8) {
                    ForEach(groups, id: \.lane.id) { group in lane(group.lane, group.services) }
                }
                .padding(12)
            }
        }
        .onChange(of: groups.first?.lane.id) { _, first in if open.isEmpty, let first { open = [first] } }
        .onAppear { if open.isEmpty, let first = groups.first { open = [first.lane.id] } }
    }

    private func lane(_ lane: CashServiceCatalog.Lane, _ services: [CashServiceCatalog.Service]) -> some View {
        let isOpen = open.contains(lane.id)
        let assigned = services.filter { $0.defaultBillingItem != nil }.count
        let hue = Hue.category(lane.id)
        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    if isOpen { open.remove(lane.id) } else { open.insert(lane.id) }
                }
            } label: {
                HStack(spacing: 12) {
                    Glyph(Self.laneIcon(lane.id), size: 16)
                        .foregroundStyle(Theme.inkStrong)
                        .frame(width: 36, height: 36)
                        .background(Theme.wash(hue == .grey ? Theme.blue : hue.color, 24), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(lane.label).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                            if assigned == services.count {
                                Glyph("circle-check", size: 16).foregroundStyle(Theme.blue).accessibilityLabel(L("All set"))
                            }
                        }
                        HStack(spacing: 8) {
                            ProgressBar(value: Double(assigned) / Double(max(1, services.count)), height: 6, track: Theme.borderSoft)
                                .frame(maxWidth: 160)
                            Text(LF("%d of %d set", assigned, services.count)).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft).fixedSize()
                        }
                    }
                    Spacer(minLength: 8)
                    Glyph("chevron-down", size: 16).foregroundStyle(Theme.inkSoft).rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(isOpen ? AnyShapeStyle(Theme.wash(Theme.surfaceMuted, 45)) : AnyShapeStyle(Theme.surface))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOpen ? .isSelected : [])
            if isOpen {
                VStack(spacing: 0) {
                    ForEach(services) { service in
                        if service.id != services.first?.id { RowDivider() }
                        row(service)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    /// A lane's icon (web `PROVIDER_CATEGORY_ICONS`; the vet, groomer and walker marks drawn with Lucide's nearest).
    private static func laneIcon(_ lane: String) -> String {
        switch lane {
        case "vet": "stethoscope"
        case "groomer": "scissors"
        case "walker": "footprints"
        case "sitter": "house"
        case "trainer": "dumbbell"
        case "daycare", "boarding": "building-2"
        case "pharmacy": "package"
        case "emergency": "siren"
        case "other": "ellipsis"
        default: "calendar-check-2"
        }
    }

    @ViewBuilder private func row(_ service: CashServiceCatalog.Service) -> some View {
        let current = service.defaultBillingItem
        let listed = billingItems.map { CashServiceCatalog.DefaultItem(id: $0.id, name: $0.name, currency: $0.currency, defaultUnitAmount: $0.defaultUnitAmount, active: $0.active) }
        let options = current.map { item in listed.contains(where: { $0.id == item.id }) ? listed : [item] + listed } ?? listed
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(service.label).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text(current != nil ? L("Set@default") : L("Not set@default"))
                        .font(.brandText(10.6, weight: .heavy))
                        .foregroundStyle(current != nil ? Theme.inkStrong : Theme.inkSoft)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(current != nil ? AnyShapeStyle(Theme.wash(Theme.lime, 32)) : AnyShapeStyle(Color.clear), in: Capsule())
                        .overlay { if current == nil { Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1) } }
                }
                if let description = service.description?.nonEmpty {
                    Text(description).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                }
            }
            Menu {
                Button(L("No default item")) { choose(service, nil) }
                ForEach(options, id: \.id) { item in
                    Button("\(item.name) · \(cashMoney(item.defaultUnitAmount, item.currency))\(item.active ? "" : " · " + L("archived"))") { choose(service, item) }
                }
            } label: {
                // Web TOOLBAR_SELECT: a 40 capsule, semibold, the chevron at the right.
                HStack(spacing: 8) {
                    Text(current.map { "\($0.name) · \(cashMoney($0.defaultUnitAmount, $0.currency))" } ?? L("No default item"))
                        .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Spacer(minLength: 8)
                    if saving == service.id { ProgressView().controlSize(.small) }
                    Glyph("chevron-down", size: 16).foregroundStyle(Theme.inkSoft)
                }
                .padding(.leading, 16)
                .padding(.trailing, 14)
                .frame(height: 40)
                .background(Theme.inputFill, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
            }
            .disabled(!canEdit || saving == service.id)
            .accessibilityLabel(LF("Default item for %@", service.label))
            if let current, !current.active {
                Text(L("This item is archived — choose an active one.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.destructive)
            } else if current == nil {
                Text(L("Bookings use the visit name until you pick one.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.vertical, 12)
    }

    private func choose(_ service: CashServiceCatalog.Service, _ item: CashServiceCatalog.DefaultItem?) {
        guard canEdit, item?.id != service.defaultBillingItem?.id else { return }
        saving = service.id
        Task {
            defer { saving = nil }
            do {
                let _: EmptyResponse = try await API.patch("/provider-catalog/service-defaults/\(service.id)", body: ["providerCatalogItemId": item?.id])
                Toast.show(item.map { LF("%@ now starts its bill with %@.", service.label, $0.name) } ?? LF("%@ no longer has a default item.", service.label))
                await reload()
                announceDataChanged()
            } catch {
                Toast.error(error, fallback: L("Could not change what this visit charges."))
            }
        }
    }
}
