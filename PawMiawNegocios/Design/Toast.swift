//
//  Toast.swift
//  PawMiawNegocios
//
//  One toast at a time, over everything (sheets included): `Toast.show("Saved.")`,
//  `Toast.error("…")`. The root view hosts it with `.toastHost()`.
//

import SwiftUI

@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    struct Item: Identifiable, Equatable { let id = UUID(); let text: String; let isError: Bool }
    @Published var current: Item?
    private var hideTask: Task<Void, Never>?

    func show(_ text: String, isError: Bool = false) {
        current = Item(text: text, isError: isError)
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(isError ? 4 : 2.6))
            guard !Task.isCancelled else { return }
            withAnimation { self.current = nil }
        }
    }
}

enum Toast {
    static func show(_ text: String) { ToastCenter.shared.show(text) }
    static func error(_ text: String) { ToastCenter.shared.show(text, isError: true) }
    /// The failed action's sentence (the server's, when it refused).
    static func error(_ error: Error, fallback: String = L("Something went wrong. Try again.")) {
        ToastCenter.shared.show(errorText(error, fallback: fallback), isError: true)
    }
}

/// Shows the toast in its own window, so it sits above sheets too.
private final class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit == rootViewController?.view ? nil : hit
    }
}

private struct ToastOverlay: View {
    @ObservedObject var center = ToastCenter.shared
    var body: some View {
        VStack {
            if let item = center.current {
                // The web's sonner toasts: rich colours, 20 corners, a 16 icon.
                let tone = item.isError ? Theme.destructive : Theme.blue
                HStack(alignment: .top, spacing: 10) {
                    Glyph(item.isError ? "octagon-x" : "circle-check", size: 16).padding(.top, 2)
                    Text(item.text).font(Theme.text(14, weight: .semibold)).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(tone)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: 420)
                .background(Theme.wash(tone, 14), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(tone.opacity(0.45), lineWidth: 1))
                .shadow(color: Theme.navy.opacity(0.14), radius: 24, y: 12)
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { center.current = nil }
                .id(item.id)
            }
            Spacer()
        }
        .padding(.top, 8)
        .animation(.spring(duration: 0.3), value: center.current)
    }
}

private struct ToastHost: ViewModifier {
    @State private var window: UIWindow?

    func body(content: Content) -> some View {
        content.onAppear {
            guard window == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
            let host = UIHostingController(rootView: ToastOverlay())
            host.view.backgroundColor = .clear
            let overlay = PassThroughWindow(windowScene: scene)
            overlay.rootViewController = host
            overlay.windowLevel = .alert + 1
            overlay.isHidden = false
            window = overlay
        }
    }
}

extension View {
    func toastHost() -> some View { modifier(ToastHost()) }
}
