//
//  CountryPicker.swift
//  PawMiawNegocios
//
//  Choosing a country: a field that shows the chosen one in the app's
//  language and opens a searchable list of every ISO country (accents and
//  case ignored, the two-letter code works too). Used by Home's "Confirma tu
//  región y dinero" and Team's Settings › Region and money.
//

import SwiftUI

struct CountryPicker: View {
    let selection: String
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// A two-letter code in the app's language ("MX" → "México").
    static func name(_ code: String?) -> String? {
        guard let code = code?.uppercased(), !code.isEmpty else { return nil }
        return Locale.app.localizedString(forRegionCode: code) ?? code
    }

    /// Every country, by name in the app's language.
    static var all: [(code: String, name: String)] {
        Locale.Region.isoRegions
            .filter { $0.identifier.count == 2 && $0.identifier.allSatisfy(\.isLetter) }
            .map { ($0.identifier, name($0.identifier) ?? $0.identifier) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let needle = query.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .app)
        let shown = Self.all.filter { needle.isEmpty || $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .app).contains(needle) || $0.code.lowercased() == needle }
        NavigationStack {
            List(shown, id: \.code) { country in
                Button { onPick(country.code); dismiss() } label: {
                    HStack {
                        Text(country.name).foregroundStyle(Theme.inkStrong)
                        Spacer()
                        if country.code == selection { Image(systemName: "checkmark").foregroundStyle(Theme.blue) }
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle(L("Country"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } } }
        }
    }
}

/// The country as a form field: its name (or "Choose"), opening `CountryPicker`.
struct CountryField: View {
    var label: String = L("Country")
    let code: String
    var key: String? = nil
    var hint: String? = nil
    var form: FormState? = nil
    let onPick: (String) -> Void

    @State private var picking = false

    var body: some View {
        FormField(label: label, key: key, hint: hint, form: form) {
            Button { picking = true } label: {
                HStack {
                    Text(CountryPicker.name(code) ?? L("Choose")).foregroundStyle(code.isEmpty ? Theme.inkSoft : Theme.inkStrong)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                }
                .fieldChrome(invalid: key.flatMap { form?.error($0) } != nil)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $picking) {
            CountryPicker(selection: code) { picked in
                if let key { form?.clear(key) }
                onPick(picked)
            }
        }
    }
}
