//
//  SearchTriggers.swift
//  PawMiawNegocios
//
//  Where the search opens (web `ProviderSearchTrigger`), and where its choices go.
//  Phone: the top bar's round search button, before the bell; the palette fills
//  the screen and a choice is pushed on the page's own stack. iPad (the docked
//  sidebar, where there is no top bar): the search bar under the business
//  switcher; the palette is a centred sheet, a page of the sidebar is chosen
//  there, and any other page (a client, a visit, a bill…) opens in a sheet with
//  its own navigation, as the place switcher's pages do. ⌘K opens it with a
//  hardware keyboard.
//

import SwiftUI

/// The phone top bar's search (web `variant="icon"`): 36 round, 1 pt border, the magnifier at 16.
struct SearchTopBarButton: View {
    @State private var open = false
    @State private var pending: SearchDestination?
    @State private var pushed: ProviderRoute?
    @State private var creatingClient = false
    @State private var createdClientId: String?

    var body: some View {
        IconCircleButton(systemImage: "search", label: L("Search"), tint: Theme.inkStrong) { open = true }
            .keyboardShortcut("k", modifiers: .command)
            .fullScreenCover(isPresented: $open, onDismiss: leave) {
                SearchScreen { destination in
                    pending = destination
                    open = false
                }
            }
            .sheet(isPresented: $creatingClient, onDismiss: {
                guard let id = createdClientId else { return }
                createdClientId = nil
                pushed = .client(id)
            }) {
                ClientsCreateSheet { createdClientId = $0.id }
            }
            .navigationDestination(item: $pushed) { RouteView(route: $0) }
    }

    /// Once the palette has gone: push the page, or open the new-client sheet.
    private func leave() {
        guard let destination = pending else { return }
        pending = nil
        switch destination {
        case .route(let route): pushed = route
        case .newClient: creatingClient = true
        case .query: break
        }
    }
}

/// The docked sidebar's search bar (web `variant="bar"`): 36 tall, a capsule, the magnifier
/// and "Buscar pacientes, clientes…". Not drawn in the phone's slide-in sidebar (the top bar has it).
struct SearchSidebarField: View {
    /// The sidebar's own choice of page.
    let choose: (ProviderSection) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var shown: SearchSidebarSheet?
    @State private var pending: SearchDestination?
    @State private var createdClientId: String?

    var body: some View {
        if Self.docked(sizeClass) {
            Button { shown = .palette } label: {
                HStack(spacing: 8) {
                    Glyph("search", size: 16).foregroundStyle(Theme.inkSoft)
                    Text(L("Search patients, clients…"))
                        .font(Theme.text(14))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .frame(height: 36)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: .command)
            .accessibilityLabel(L("Search"))
            .sheet(item: $shown, onDismiss: next) { sheet in
                switch sheet {
                case .palette:
                    SearchScreen { destination in
                        pending = destination
                        shown = nil
                    }
                    .presentationSizing(.form)
                case .route(let route):
                    NavigationStack {
                        RouteView(route: route)
                            .providerRoutes()
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) { Button(L("Close")) { shown = nil } }
                            }
                    }
                case .newClient:
                    ClientsCreateSheet { createdClientId = $0.id }
                }
            }
        }
    }

    /// Once a sheet has gone: the next one, or the sidebar's page.
    private func next() {
        if let id = createdClientId {
            createdClientId = nil
            shown = .route(.client(id))
            return
        }
        guard let destination = pending else { return }
        pending = nil
        switch destination {
        case .route(.section(let section)): choose(section)
        case .route(let route): shown = .route(route)
        case .newClient: shown = .newClient
        case .query: break
        }
    }

    /// Whether this is the docked sidebar: the window is wide, as the shell reads it. (A split
    /// view's sidebar column may call itself compact, so the window has the last word.)
    private static func docked(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
        if sizeClass == .regular { return true }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.traitCollection.horizontalSizeClass == .regular
    }
}

private enum SearchSidebarSheet: Identifiable, Hashable {
    case palette
    case route(ProviderRoute)
    case newClient

    var id: Self { self }
}
