//
//  Localization.swift
//  PawMiawNegocios
//
//  Spanish first, like the business side of the web. Keys are the English
//  sentence; each language's words live in `<lang>.lproj/*.strings`, one
//  table per module (Localizable.strings for the shared pieces, Schedule.strings,
//  Clients.strings, …). A module's file reads its own table first (the map in
//  StringTables.swift, from scripts/strings-map.py), then the shared one, then
//  any other: so "Cancelled" can be "Cancelada" for a visit and "Cancelado"
//  for a groom. A key may carry a context after "@" ("Done@home"); if no table
//  has it, the English before the "@" shows.
//

import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case spanish = "es"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .spanish: "Español"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .english: "en_US"
        case .spanish: "es_MX"
        }
    }
}

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published private(set) var currentLanguage: AppLanguage
    /// The language's tables by name ("Schedule", "Localizable").
    private var tables: [String: [String: String]] = [:]
    /// Every table but the shared one, merged: the last resort for a key.
    private var merged: [String: String] = [:]
    private let languageKey = "pawmiaw_negocios_language"

    init() {
        if let stored = UserDefaults.standard.string(forKey: languageKey), let language = AppLanguage(rawValue: stored) {
            currentLanguage = language
        } else {
            // Spanish unless the device asks for English first.
            currentLanguage = Locale.preferredLanguages.first?.lowercased().hasPrefix("en") == true ? .english : .spanish
        }
        loadTables()
    }

    func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: languageKey)
        guard language != currentLanguage else { return }
        currentLanguage = language
        loadTables()
    }

    /// The account's language from the server, unless the person chose one here.
    func syncFromServerPreference(_ value: String?) {
        guard UserDefaults.standard.string(forKey: languageKey) == nil,
              let value, let language = AppLanguage(rawValue: value), language != currentLanguage else { return }
        currentLanguage = language
        loadTables()
    }

    private func loadTables() {
        var loaded: [String: [String: String]] = [:]
        var all: [String: String] = [:]
        if let folder = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj"),
           let files = try? FileManager.default.contentsOfDirectory(atPath: folder) {
            for file in files.sorted() where file.hasSuffix(".strings") {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(file)
                guard let dict = NSDictionary(contentsOf: url) as? [String: String] else { continue }
                let name = String(file.dropLast(".strings".count))
                loaded[name] = dict
                if name != "Localizable" { all.merge(dict) { old, _ in old } }
            }
        }
        tables = loaded
        merged = all
    }

    func localizedString(_ key: String, file: StaticString) -> String {
        let fileID = "\(file)"
        let fileName = fileID.split(separator: "/").last.map(String.init) ?? fileID
        if let module = StringTables.moduleOfFile[fileName], let value = tables[module]?[key] { return value }
        if let value = tables["Localizable"]?[key] ?? merged[key] { return value }
        return Self.withoutContext(key)
    }

    /// "Done@home" → "Done" (a key's context is never shown).
    private static func withoutContext(_ key: String) -> String {
        guard let at = key.lastIndex(of: "@"), at != key.startIndex else { return key }
        let context = key[key.index(after: at)...]
        guard !context.isEmpty, context.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return key }
        return String(key[..<at])
    }

    var locale: Locale { Locale(identifier: currentLanguage.localeIdentifier) }
}

/// The sentence in the app's language. The key is the English sentence.
func L(_ key: String, file: StaticString = #fileID) -> String {
    LocalizationManager.shared.localizedString(key, file: file)
}

/// A sentence with `%@` / `%d` arguments, in the app's language.
func LF(_ key: String, _ arguments: CVarArg..., file: StaticString = #fileID) -> String {
    String(format: L(key, file: file), locale: LocalizationManager.shared.locale, arguments: arguments)
}

/// "1 visit" / "3 visits": the key's `one` and `other` forms, each with `%d`.
func LP(_ count: Int, _ one: String, _ other: String, file: StaticString = #fileID) -> String {
    String(format: L(count == 1 ? one : other, file: file), locale: LocalizationManager.shared.locale, count)
}

extension Locale {
    /// The locale of the language chosen in the app (en_US / es_MX), for anything formatted for display.
    static var app: Locale { LocalizationManager.shared.locale }
}
