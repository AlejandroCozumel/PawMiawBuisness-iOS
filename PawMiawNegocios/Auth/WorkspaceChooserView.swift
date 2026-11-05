//
//  WorkspaceChooserView.swift
//  PawMiawNegocios
//
//  A person who works in more than one business chooses one; a person with
//  none is told where a business is made (the web) or joined (an invitation).
//

import SwiftUI

struct WorkspaceChooserView: View {
    @EnvironmentObject private var workspace: Workspace
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            PageScroll {
                Text(L("Which business are you working in?")).font(Theme.titleFont).foregroundStyle(Theme.inkStrong)
                ForEach(workspace.workspaces) { item in
                    Button {
                        Task { await workspace.choose(item) }
                    } label: {
                        Card {
                            ListRow(title: item.name, subtitle: WorkspaceRole.label(item.role), detail: item.address, showsChevron: true, leading: {
                                Avatar(name: item.name, imageURL: item.logoUrl, size: 48)
                            }, trailing: { EmptyView() })
                        }
                    }
                    .buttonStyle(.plain)
                }
                PMButton(L("Sign out"), variant: .outline, fullWidth: true) { Task { await session.signOut() } }
            }
            .navigationTitle(L("Businesses"))
        }
    }
}

struct NoWorkspaceView: View {
    @EnvironmentObject private var workspace: Workspace
    @EnvironmentObject private var session: SessionStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        PageScroll(refresh: { await workspace.load() }) {
            VStack(spacing: 16) {
                Image("BusinessMark").resizable().scaledToFit().frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                Text(L("You don't work in a business yet")).font(Theme.titleFont).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.center)
                Text(L("Create your business on pawmiaw.com, or open the invitation your team sent to your email. Then come back here."))
                    .font(Theme.bodyFont).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                PMButton(L("Create my business"), systemImage: "safari", fullWidth: true) {
                    openURL(APIConfig.webOrigin.appendingPathComponent("providers"))
                }
                PMButton(L("I already did: check again"), variant: .outline, fullWidth: true) { Task { await workspace.load() } }
                PMButton(L("Sign out"), variant: .outline, fullWidth: true) { Task { await session.signOut() } }
            }
            .padding(.top, 40)
            .frame(maxWidth: .infinity)
        }
    }
}
