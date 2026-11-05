//
//  AppShell.swift
//  PawMiawNegocios
//
//  The workspace's frame, as the web draws it (provider-shell.tsx). On a
//  phone: one white top bar (the sidebar button, the PawMiaw wordmark, the
//  bell) and the sidebar sliding in from the left with every page, grouped
//  OPERACIÓN · COBROS · NEGOCIO; there is no tab bar. On an iPad the same
//  sidebar stays docked beside the page.
//

import SwiftUI

struct AppShell: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var workspace: Workspace
    @StateObject private var badges = Badges()

    var body: some View {
        Group {
            if sizeClass == .regular {
                SidebarShell()
            } else {
                PhoneShell()
            }
        }
        .environmentObject(badges)
        .task(id: workspace.scopeVersion) {
            while !Task.isCancelled {
                await badges.refresh(workspace)
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pawMiawDataChanged)) { _ in
            Task { await badges.refresh(workspace) }
        }
    }
}

// MARK: - Opening the sidebar

struct OpenSidebarAction {
    let action: (() -> Void)?
    func callAsFunction() { action?() }
}

private struct OpenSidebarKey: EnvironmentKey { static let defaultValue = OpenSidebarAction(action: nil) }

extension EnvironmentValues {
    /// Slides the sidebar in (phone); nil where it is docked.
    var openSidebar: OpenSidebarAction {
        get { self[OpenSidebarKey.self] }
        set { self[OpenSidebarKey.self] = newValue }
    }
}

// MARK: - Phone

private struct PhoneShell: View {
    @State private var section: ProviderSection = .launchSection
    @State private var open = false

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack {
                SectionView(section: section)
                    .providerRoutes()
                    .toolbar(.hidden, for: .navigationBar)
                    .safeAreaInset(edge: .top, spacing: 0) { ProviderTopBar() }
            }
            .id(section)
            .environment(\.openSidebar, OpenSidebarAction { withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3)) { open = true } })

            if open {
                Color.black.opacity(0.1)
                    .background(.ultraThinMaterial.opacity(0.4))
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)
                SidebarPanel(selection: section) { chosen in
                    section = chosen
                    close()
                }
                .frame(width: 288)
                .frame(maxHeight: .infinity)
                .background(Theme.sidebarBackground.ignoresSafeArea())
                .overlay(alignment: .trailing) { Rectangle().fill(Theme.borderSoft).frame(width: 1).ignoresSafeArea() }
                .shadow(color: Theme.navy.opacity(0.14), radius: 24, x: 8)
                .transition(.move(edge: .leading))
                .gesture(DragGesture().onEnded { if $0.translation.width < -60 { close() } })
            }
        }
    }

    private func close() {
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3)) { open = false }
    }
}

/// The web's phone top bar (56 tall, white, a hairline under it): the
/// sidebar button, the wordmark, the place when there are several, the bell.
struct ProviderTopBar: View {
    @EnvironmentObject private var workspace: Workspace
    @EnvironmentObject private var badges: Badges
    @Environment(\.openSidebar) private var openSidebar

    var body: some View {
        HStack(spacing: 12) {
            if openSidebar.action != nil {
                Button { openSidebar() } label: {
                    Glyph("panel-left", size: 16)
                        .foregroundStyle(Theme.inkStrong)
                        .frame(width: 36, height: 36)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Menu"))
            }
            Image("Wordmark").resizable().scaledToFit().frame(height: 26)
                .accessibilityLabel("PawMiaw")
            Spacer(minLength: 4)
            if workspace.multiLocation { PlacesSwitcherMenu() }
            SearchTopBarButton()
            NavigationLink(value: ProviderRoute.section(.notifications)) {
                Glyph("bell", size: 20)
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 36, height: 36)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(badges.unreadNotifications > 0 ? Theme.coral : Theme.borderSoft, lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if badges.unreadNotifications > 0 {
                            CountBadge(count: badges.unreadNotifications, color: Theme.coral, cap: 9)
                                .overlay(Capsule().strokeBorder(Theme.surface, lineWidth: 1.5))
                                .offset(x: 6, y: -6)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Notifications"))
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderSoft).frame(height: 1) }
    }
}

// MARK: - The sidebar

/// The web's sidebar (provider-shell.tsx): the business switcher, the pages in
/// three groups with their numbers, and the person at the foot.
struct SidebarPanel: View {
    let selection: ProviderSection?
    let choose: (ProviderSection) -> Void
    @EnvironmentObject private var workspace: Workspace
    @EnvironmentObject private var badges: Badges

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                PlacesSwitcherMenu(sidebar: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SearchSidebarField(choose: choose)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.sidebarBorder).frame(height: 1) }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let groups = SectionGroup.allCases.map { group in
                        (group, group.sections.filter { $0.isVisible(in: workspace, olfatoShown: badges.olfatoShown, pharmacyShown: badges.pharmacyShown) })
                    }.filter { !$0.1.isEmpty }
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, entry in
                        if index > 0 { Rectangle().fill(Theme.sidebarBorder).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 8) }
                        Text(entry.0.title.uppercased())
                            .font(Theme.text(10.9, weight: .heavy))
                            .tracking(1.75)
                            .foregroundStyle(Theme.inkSoft)
                            .frame(height: 32)
                            .padding(.horizontal, 12)
                        VStack(spacing: 4) {
                            ForEach(entry.1) { section in
                                SidebarItem(section: section, count: badges.count(section), selected: section == selection) { choose(section) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
            SidebarAccountRow(choose: choose)
                .padding(12)
                .overlay(alignment: .top) { Rectangle().fill(Theme.sidebarBorder).frame(height: 1) }
        }
    }
}

/// One page in the sidebar: 32 tall, icon 16, label 14; chosen = PAW Blue
/// with a gold edge and white bold words; its number in a red capsule.
private struct SidebarItem: View {
    let section: ProviderSection
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SectionIcon(section: section, size: 16)
                Text(section.title).font(Theme.text(14, weight: selected ? .bold : .regular)).lineLimit(1)
                Spacer(minLength: 4)
                CountBadge(count: count)
            }
            .foregroundStyle(selected ? Theme.sidebarActiveInk : Theme.inkSoft)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background {
                if selected {
                    Capsule().fill(Theme.sidebarActive)
                    Capsule().strokeBorder(Theme.sidebarActiveBorder, lineWidth: 2)
                }
            }
            .shadow(color: selected ? Theme.blueFixed.opacity(0.14) : .clear, radius: 11, y: 10)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A section's icon: the web's Lucide icon (Olfato AI wears its corgi).
struct SectionIcon: View {
    let section: ProviderSection
    var size: CGFloat = 16

    var body: some View {
        if section == .olfato {
            Image("OlfatoFace").resizable().scaledToFit().frame(width: size + 2, height: size + 2)
        } else {
            Glyph(section.icon, size: size)
        }
    }
}

/// The person at the foot of the sidebar, opening the account menu.
private struct SidebarAccountRow: View {
    let choose: (ProviderSection) -> Void
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var localization: LocalizationManager
    @AppStorage("pawmiaw.negocios.theme") private var theme = "light"
    @State private var confirmSignOut = false

    var body: some View {
        Menu {
            if let user = session.user {
                Section(user.email) {
                    Button { choose(.accountSecurity) } label: { GlyphLabel(L("Your account"), icon: "user-round") }
                    Button { choose(.notificationSettings) } label: { GlyphLabel(L("Notification settings"), icon: "bell-ring") }
                }
            }
            Picker(selection: Binding(get: { theme }, set: { theme = $0 })) {
                Text(L("Light")).tag("light")
                Text(L("Dark")).tag("dark")
            } label: { GlyphLabel(L("Theme"), icon: theme == "dark" ? "moon" : "sun") }
            .pickerStyle(.menu)
            Picker(selection: Binding(get: { localization.currentLanguage }, set: { localization.setLanguage($0) })) {
                ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
            } label: { GlyphLabel(L("Language"), icon: "languages") }
            .pickerStyle(.menu)
            Button(role: .destructive) { confirmSignOut = true } label: { GlyphLabel(L("Sign out"), icon: "log-out") }
        } label: {
            HStack(spacing: 8) {
                AccountAvatar(name: session.user?.name, imageURL: session.user?.image, size: 28)
                Text(session.user?.name.split(separator: " ").first.map(String.init) ?? "")
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.sidebarControl, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.sidebarControlBorder, lineWidth: 1))
        }
        .confirmationDialog(L("Sign out of PawMiaw Business?"), isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(L("Sign out"), role: .destructive) { Task { await session.signOut() } }
        }
    }
}

/// The account's face: the photo, or white initials on PAW Blue.
struct AccountAvatar: View {
    let name: String?
    var imageURL: String? = nil
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(Theme.blueFixed)
            Text(NameText.initials(name)).font(Theme.text(size * 0.36, weight: .bold)).foregroundStyle(.white)
            if let url = APIConfig.assetURL(imageURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                }
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// The business's mark: its logo on white, or its initials on PAW Blue.
struct BusinessMarkView: View {
    let name: String
    var logoURL: String? = nil
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            if let url = APIConfig.assetURL(logoURL) {
                Circle().fill(.white)
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() }
                }
                .padding(2)
                .clipShape(Circle())
            } else {
                Circle().fill(Theme.blueFixed)
                Text(NameText.initials(name)).font(Theme.text(12, weight: .heavy)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Theme.borderSoft, lineWidth: logoURL == nil ? 0 : 1))
    }
}

/// The place this device works at, on a page's toolbar: the business's one
/// switcher (`PlacesSwitcherMenu`), shown when there is more than one place.
struct LocationMenu: View {
    @EnvironmentObject private var workspace: Workspace

    var body: some View {
        if workspace.multiLocation {
            PlacesSwitcherMenu()
        }
    }
}

// MARK: - iPad

private struct SidebarShell: View {
    @State private var selection: ProviderSection = .launchSection
    @State private var path = NavigationPath()

    var body: some View {
        NavigationSplitView {
            SidebarPanel(selection: selection) { selection = $0 }
                .background(Theme.sidebarBackground.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .navigationSplitViewColumnWidth(256)
        } detail: {
            NavigationStack(path: $path) {
                SectionView(section: selection).providerRoutes()
            }
            .id(selection)
        }
        .onChange(of: selection) { _, _ in path = NavigationPath() }
    }
}

// MARK: - Page bar

extension View {
    /// A page's bar: no big title (the module header carries it). A section's
    /// own page sits under the shell's top bar; a page opened from another
    /// shows the system bar with its back button and its title small.
    func providerPage(_ title: String, root: Bool = false) -> some View {
        modifier(ProviderPageBar(title: title, root: root))
    }
}

private struct ProviderPageBar: ViewModifier {
    let title: String
    let root: Bool

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .background(Theme.canvas.ignoresSafeArea())
    }
}

extension ProviderSection {
    /// Home, or in a DEBUG build the page named by `PAWMIAW_DEBUG_SECTION` (a design review opens a page directly).
    static var launchSection: ProviderSection {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["PAWMIAW_DEBUG_SECTION"], let section = ProviderSection(rawValue: name) { return section }
        #endif
        return .home
    }
}
