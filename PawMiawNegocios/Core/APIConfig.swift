//
//  APIConfig.swift
//  PawMiawNegocios
//
//  The backend's address, the same one the family app and the web use:
//  local dev talks to the backend on :3000, release builds to the live API.
//

import Foundation
import UIKit

enum APIConfig {
    /// Backend API base, including the `/api` suffix.
    static let baseURL: URL = {
        #if DEBUG
        let processOverride = ProcessInfo.processInfo.environment["PAWMIAW_API_BASE_URL"]
        #else
        let processOverride: String? = nil
        #endif
        let configured = processOverride
            ?? Bundle.main.object(forInfoDictionaryKey: "PawMiawAPIBaseURL") as? String
        guard let value = configured?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.contains("$("),
              let url = URL(string: value),
              url.path.hasSuffix("/api") else {
            fatalError("PawMiawAPIBaseURL must be an absolute backend URL ending in /api")
        }
        #if !DEBUG
        guard url.scheme == "https" else {
            fatalError("Release builds require an HTTPS PawMiawAPIBaseURL")
        }
        #endif
        return url
    }()

    /// Scheme + host (drops `/api`): resolves relative asset paths such as pet photos.
    static var origin: URL { baseURL.deletingLastPathComponent() }

    /// The web app, for what this app sends people to (the plan, a public page).
    static var webOrigin: URL {
        #if DEBUG
        URL(string: "http://localhost:3001")!
        #else
        URL(string: "https://pawmiaw.com")!
        #endif
    }

    /// A photo or file path from the API, absolute or relative to the origin.
    static func assetURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("http") { return URL(string: value) }
        if value.hasPrefix("/api/") { return URL(string: value, relativeTo: origin)?.absoluteURL }
        let path = value.hasPrefix("/") ? String(value.dropFirst()) : value
        return origin.appendingPathComponent(path)
    }

    static let userAgent: String = {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        return "PawMiawNegocios-iOS/\(appVersion) (\(device); iOS \(UIDevice.current.systemVersion))"
    }()

    static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }()
}
