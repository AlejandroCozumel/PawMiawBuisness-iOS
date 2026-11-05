//
//  PawMiawNegociosApp.swift
//  PawMiawNegocios
//
//  PawMiaw Negocios: the business workspace (the web's /provider) as a
//  native app, against the same backend.
//

import SwiftUI

@main
struct PawMiawNegociosApp: App {
    @StateObject private var localization = LocalizationManager.shared
    @StateObject private var session = SessionStore()
    @StateObject private var workspace = Workspace.shared
    /// As on the web: light unless the person chose dark (the account menu); it doesn't follow the system.
    @AppStorage("pawmiaw.negocios.theme") private var theme = "light"

    init() {
        BrandFonts.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(localization)
                .environmentObject(session)
                .environmentObject(workspace)
                .environment(\.locale, localization.locale)
                .id(localization.currentLanguage.rawValue)
                .tint(Theme.blue)
                .preferredColorScheme(theme == "dark" ? .dark : .light)
                .toastHost()
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var workspace: Workspace

    var body: some View {
        Group {
            switch session.phase {
            case .checking:
                SplashView()
            case .signedOut:
                SignInView()
            case .signedIn:
                WorkspaceGate()
            }
        }
        .task { await session.revalidate() }
        .onChange(of: session.phase) { _, phase in
            if case .signedOut = phase { workspace.reset() }
        }
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("BusinessMark").resizable().scaledToFit().frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            ProgressView().tint(Theme.blue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas.ignoresSafeArea())
    }
}

/// Signed in: which business, then the workspace.
struct WorkspaceGate: View {
    @EnvironmentObject private var workspace: Workspace
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            switch workspace.phase {
            case .idle, .loading:
                SplashView()
            case .none:
                NoWorkspaceView()
            case .choosing:
                WorkspaceChooserView()
            case .failed(let message):
                VStack {
                    ErrorState(message: message) { await workspace.load() }
                    PMButton(L("Sign out"), variant: .outline, size: .compact) { Task { await session.signOut() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas.ignoresSafeArea())
            case .ready:
                if let current = workspace.current, current.setupCompletedAt == nil || !HomeAccess.canUse(current) {
                    // As on the web: a business whose setup or plan isn't done opens no tools, only what to do next.
                    WorkspaceLockedView(workspace: current)
                } else {
                    AppShell()
                }
            }
        }
        .task { if workspace.phase == .idle { await workspace.load() } }
    }
}

/// The whole workspace while its setup or plan isn't done (web: the shell shows
/// `ProviderActivationPanel` in place of every page). Plans and setup are on the web.
struct WorkspaceLockedView: View {
    let workspace: ProviderWorkspace
    @EnvironmentObject private var store: Workspace
    @EnvironmentObject private var session: SessionStore
    @Environment(\.openURL) private var openURL

    private var needsSetup: Bool { workspace.setupCompletedAt == nil }

    var body: some View {
        PageScroll(refresh: { await store.load() }) {
            Image("Wordmark").resizable().scaledToFit().frame(height: 28).frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            Card(padding: 20) {
                HStack(spacing: 12) {
                    IconBadge(icon: needsSetup ? "wrench" : "lock", accent: Theme.blue, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(needsSetup ? L("Finish setting up your workspace") : HomeAccess.lockedTitle(workspace))
                            .font(.brandHeading(22, relativeTo: .title2)).foregroundStyle(Theme.inkStrong)
                        Text(workspace.name).font(.brandText(14, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    }
                }
                Text(needsSetup
                     ? L("Your business details, hours and services are set up on the web. Home opens here once they are done.")
                     : L("Provider tools are paused until billing is connected. Plans are chosen on the web."))
                    .font(.brandText(15)).foregroundStyle(Theme.inkSoft)
                PMButton(needsSetup ? L("Open setup on the web") : L("Open the plan on the web"), systemImage: "external-link", fullWidth: true) {
                    openURL(APIConfig.webOrigin.appendingPathComponent(needsSetup ? "provider" : "provider/billing"))
                }
                PMButton(L("I already did: check again"), variant: .outline, fullWidth: true) { Task { await store.load() } }
            }
            if store.workspaces.count > 1 {
                PMButton(L("Choose another business"), systemImage: "arrow-left-right", variant: .outline, fullWidth: true) { store.leaveToChooser() }
            }
            PMButton(L("Sign out"), systemImage: "log-out", variant: .outline, fullWidth: true) { Task { await session.signOut() } }
        }
    }
}
