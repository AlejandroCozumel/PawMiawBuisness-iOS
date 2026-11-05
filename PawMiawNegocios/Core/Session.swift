//
//  Session.swift
//  PawMiawNegocios
//
//  Who is signed in. The backend's Bearer token (the session token Better Auth
//  returns at sign-in) is kept in the keychain and sent on every request.
//

import Foundation
import Security
import SwiftUI

struct AuthUser: Codable, Equatable, Hashable {
    let id: String
    let email: String
    let name: String
    let emailVerified: Bool?
    let image: String?
    let preferredLanguage: String?
}

private struct SignInBody: Decodable { let user: AuthUser }
private struct ValidateBody: Decodable { let valid: Bool; let user: AuthUser? }

/// The token, readable from anywhere (the API client signs requests with it).
enum SessionToken {
    private static let service = "com.pawmiaw.business.session"
    private static let account = "bearer"
    private static var cached: String?
    private static var loaded = false

    static var current: String? {
        #if DEBUG
        // A local design review signs in with a session made for it, without touching the stored one.
        if let override = ProcessInfo.processInfo.environment["PAWMIAW_DEBUG_SESSION_TOKEN"], !override.isEmpty { return override }
        #endif
        if !loaded { cached = read(); loaded = true }
        return cached
    }

    static func store(_ token: String?) {
        cached = token; loaded = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard let token, let data = token.data(using: .utf8) else { return }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }

    private static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

@MainActor
final class SessionStore: ObservableObject {
    enum Phase: Equatable { case checking, signedOut, signedIn(AuthUser) }

    @Published private(set) var phase: Phase = .checking
    var user: AuthUser? { if case .signedIn(let user) = phase { return user }; return nil }

    private let userKey = "pawmiaw_negocios_user"

    init() {
        if SessionToken.current != nil, let data = UserDefaults.standard.data(forKey: userKey), let user = try? JSONDecoder().decode(AuthUser.self, from: data) {
            phase = .signedIn(user)
        } else if SessionToken.current == nil {
            phase = .signedOut
        }
        NotificationCenter.default.addObserver(forName: .pawMiawSessionMayHaveExpired, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.revalidate() }
        }
    }

    func signIn(email: String, password: String) async throws {
        let body: SignInBody = try await API.post("/auth/sign-in", body: ["email": email, "password": password, "rememberMe": true])
        // The session comes back as Better Auth's signed session cookie; its
        // value is what the bearer plugin accepts in `Authorization`.
        guard let token = Self.sessionCookieValue(), !token.isEmpty else {
            throw APIError(status: 500, message: L("The sign-in did not return a session. Try again."), code: nil, fields: [:])
        }
        SessionToken.store(token)
        remember(body.user)
        LocalizationManager.shared.syncFromServerPreference(body.user.preferredLanguage)
        phase = .signedIn(body.user)
    }

    func requestPasswordReset(email: String) async throws {
        try await API.send("POST", "/auth/forget-password", body: ["email": email, "redirectTo": APIConfig.webOrigin.appendingPathComponent("reset-password").absoluteString])
    }

    /// Checks the stored session once with the server; signs out when it ended.
    func revalidate() async {
        guard SessionToken.current != nil else { phase = .signedOut; return }
        do {
            let body: ValidateBody = try await API.get("/auth/validate-session")
            if body.valid, let user = body.user {
                remember(user)
                phase = .signedIn(user)
            } else {
                clear()
            }
        } catch let error as APIError where error.status == 401 {
            clear()
        } catch {
            // Offline: keep the person signed in with what we know.
            if case .checking = phase { phase = user.map { .signedIn($0) } ?? .signedOut }
        }
    }

    func signOut() async {
        try? await API.send("POST", "/auth/sign-out", body: [:])
        clear()
    }

    private static func sessionCookieValue() -> String? {
        guard let host = APIConfig.baseURL.host else { return nil }
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        let match = cookies.first { cookie in
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return cookie.name.hasSuffix("better-auth.session_token") && (host == domain || host.hasSuffix(".\(domain)"))
        }
        // Kept as sent (percent-encoded): the bearer plugin decodes it itself, and a
        // decoded value loses the signature's "=" to the plugin's own trimming.
        return match?.value
    }

    private func remember(_ user: AuthUser) {
        if let data = try? JSONEncoder().encode(user) { UserDefaults.standard.set(data, forKey: userKey) }
    }

    private func clear() {
        SessionToken.store(nil)
        UserDefaults.standard.removeObject(forKey: userKey)
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        phase = .signedOut
    }
}
