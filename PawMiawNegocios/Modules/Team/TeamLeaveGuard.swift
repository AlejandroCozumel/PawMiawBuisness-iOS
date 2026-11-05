//
//  TeamLeaveGuard.swift
//  PawMiawNegocios
//
//  "¿Salir sin guardar?" (web: the blocker on routes/provider.settings.tsx
//  and provider.availability.tsx): while a page has changes that aren't
//  saved, its back button asks first, in the app's sheet, and the swipe back
//  waits. Every `TeamSaveSection` says by its title when it has unsaved
//  changes (`TeamUnsavedKey`), so a page knows which parts would be lost.
//

import SwiftUI

/// The titles of the save-in-place cards on a page that have unsaved changes.
struct TeamUnsavedKey: PreferenceKey {
    static let defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) {
        value += nextValue()
    }
}

/// While `dirty`, the back button of a pushed page asks before leaving:
/// `.modifier(TeamLeaveGuard(dirty: …, message: …))`.
struct TeamLeaveGuard: ViewModifier {
    let dirty: Bool
    let message: String
    /// Availability asks with its clock (web `ProviderConfirmModal`, Clock3); Settings with the triangle.
    var systemImage: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @State private var asking = false
    @State private var leaving = false

    private var guarding: Bool { dirty && isPresented }

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(guarding)
            .toolbar {
                if guarding {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { asking = true } label: {
                            HStack(spacing: 4) {
                                Glyph("chevron-left", size: 20)
                                Text(L("Back"))
                            }
                        }
                        .accessibilityLabel(L("Back"))
                    }
                }
            }
            .sheet(isPresented: $asking, onDismiss: {
                if leaving {
                    leaving = false
                    dismiss()
                }
            }) {
                ConfirmSheet(
                    title: L("Leave without saving?"),
                    message: message,
                    confirmTitle: L("Leave without saving"),
                    destructive: true,
                    cancelTitle: L("Keep editing"),
                    icon: systemImage ?? "triangle-alert"
                ) { _ in
                    leaving = true
                }
            }
    }
}
