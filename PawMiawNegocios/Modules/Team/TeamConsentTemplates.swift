//
//  TeamConsentTemplates.swift
//  PawMiawNegocios
//
//  Settings › Consents (web: components/app/consents/consent-templates-section.tsx
//  and consent-template-editor.tsx; hooks/use-consents.ts; lib/consents.ts):
//  the business's consent templates, active and archived, each with how long
//  a signature lasts and what it is required for. Opening one edits it (with
//  workspace.edit) or reads it: its words with placeholders put in at the
//  cursor and a preview with sample values, which services and stays can't
//  start without it, archive/restore, and every version of its words. New
//  words make a new version; consents already signed keep the words they
//  were signed with. The defaults arrive the first time the list is read.
//

import SwiftUI

struct TeamConsentTemplate: Decodable, Identifiable, Hashable {
    struct Requirement: Decodable, Hashable {
        let serviceIds: [String]?
        let stayKinds: [String]?
    }
    let id: String
    let defaultKey: String?
    let language: String?
    let title: String?
    let body: String?
    let version: Int?
    let validity: String?
    let validDays: Int?
    let requiredFor: Requirement?
    let needsAmount: Bool?
    let status: String?
    let updatedAt: String?
}

struct TeamConsentVersion: Decodable, Identifiable, Hashable {
    let id: String
    let version: Int?
    let title: String?
    let body: String?
    let language: String?
    let createdAt: String?
    let createdByName: String?
}

private struct TeamConsentTemplateDetail: Decodable {
    let id: String
    let language: String?
    let title: String?
    let body: String?
    let version: Int?
    let validity: String?
    let validDays: Int?
    let requiredFor: TeamConsentTemplate.Requirement?
    let status: String?
    let updatedAt: String?
    let signedCount: Int?
    let versions: [TeamConsentVersion]?
}

private struct TeamConsentLibraryEntry: Decodable, Hashable {
    let key: String
    let language: String?
    let title: String?
    let body: String?
    let validity: String?
    let validDays: Int?
}

/// The consent rules the screens share (web: lib/consents.ts, the server's limits).
enum TeamConsentRules {
    static let placeholders = ["pet", "client", "amount", "date", "business", "service"]
    static let stayKinds = ["boarding", "daycare", "home_sitting"]
    static let titleMax = 160
    static let bodyMax = 12_000
    static let validDaysMax = 3650

    static func placeholderLabel(_ key: String) -> String {
        switch key {
        case "pet": L("Pet")
        case "client": L("Client")
        case "amount": L("Amount")
        case "date": L("Date")
        case "business": L("Business")
        case "service": L("Service")
        default: key
        }
    }

    /// A stay kind in words; one this version doesn't know yet reads as it is written.
    static func stayKindLabel(_ kind: String) -> String {
        switch kind {
        case "boarding": L("Boarding (hotel)")
        case "daycare": L("Daycare")
        case "home_sitting": L("Home sitting")
        default: kind.replacingOccurrences(of: "_", with: " ")
        }
    }

    static func validityLabel(_ validity: String?, _ days: Int?) -> String {
        if validity != "standing" { return L("Each visit or stay") }
        guard let days, days > 0 else { return L("Once per pet · until revoked") }
        return days == 1 ? L("Once per pet · 1 day") : LF("Once per pet · %d days", days)
    }

    /// A text that names {amount} can't go out until the business says how much.
    static func needsAmount(_ title: String, _ body: String) -> Bool {
        "\(title)\n\(body)".contains("{amount}")
    }

    /// Words that stand in for the real ones in the preview.
    static func samples(_ language: String, business: String?) -> [String: String] {
        language == "es"
            ? ["pet": "Luna", "client": "María López", "amount": "$4,500.00 MXN", "date": "1 de octubre de 2026", "business": business?.trimmingCharacters(in: .whitespaces).nonEmpty ?? "Tu negocio", "service": "Esterilización"]
            : ["pet": "Luna", "client": "Mary Lopez", "amount": "$450.00 USD", "date": "October 1, 2026", "business": business?.trimmingCharacters(in: .whitespaces).nonEmpty ?? "Your business", "service": "Spay surgery"]
    }

    /// Unknown braces stay as typed; a known placeholder with no value stays visible.
    static func render(_ text: String, _ values: [String: String]) -> String {
        var out = text
        for key in placeholders { if let value = values[key], !value.isEmpty { out = out.replacingOccurrences(of: "{\(key)}", with: value) } }
        return out
    }

    /// `{key}` put where the cursor is (replacing a selection), with a space added when it would
    /// otherwise stick to a word or a comma. Returns the new text and where the cursor goes.
    static func insert(_ key: String, into text: String, range: Range<String.Index>?) -> (text: String, caret: Int) {
        let start = range?.lowerBound ?? text.endIndex
        let end = range?.upperBound ?? text.endIndex
        let before = String(text[..<start])
        let after = String(text[end...])
        let glueBefore = (before.last.map { !$0.isWhitespace && !"(«\"“'¡¿[".contains($0) } ?? false) ? " " : ""
        let glueAfter = (after.first.map { $0.isLetter || $0.isNumber } ?? false) ? " " : ""
        let token = "\(glueBefore){\(key)}\(glueAfter)"
        return (before + token + after, before.count + token.count - glueAfter.count)
    }

    static func message(_ error: Error, fallback: String) -> String { errorText(error, fallback: fallback) }
}

// MARK: - The list

struct TeamConsentTemplatesSection: View {
    @ObservedObject var model: TeamSettingsModel
    @EnvironmentObject private var workspace: Workspace
    @State private var templates: [TeamConsentTemplate]?
    @State private var failed: String?
    @State private var tab = "active"
    @State private var target: TeamConsentTarget?

    private var canEdit: Bool { workspace.can(.workspaceEdit) }

    var body: some View {
        let all = templates ?? []
        let shown = all.filter { ($0.status ?? "active") == tab }
        TeamPanel(
            title: L("Consents"),
            subtitle: L("What families sign before a surgery, a sedation, a stay… in the app or here on your device. Each one can be required before a service starts."),
            systemImage: "file-pen-line",
            tint: Theme.lavender,
            look: .settings,
            readOnlyNote: canEdit ? nil : L("Only someone who edits the workspace can change consents.")
        ) {
            if canEdit {
                PMButton(L("New consent"), systemImage: "file-plus-2", fullWidth: true) { target = TeamConsentTarget(templateId: nil) }
            }
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                NoticeCard(tone: .warning, title: L("Wording must be reviewed by a professional before you rely on it."), message: L("The starting texts follow public guidance (NOM-064-ZOO-2000, AVMA) but aren’t legal advice for your business."), icon: "scale", look: .banner)
                Segmented(options: [
                    .init("active", L("Active@consents"), icon: "list-checks"),
                    .init("archived", L("Archived@consents"), icon: "archive"),
                ], selection: $tab, look: .solid, label: L("Consents"))
                if templates == nil {
                    if let failed {
                        VStack(spacing: 12) {
                            Text(failed).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.center)
                            PMButton(L("Try again"), variant: .outline) { Task { await load() } }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 32)
                        .frame(maxWidth: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    } else { ProgressView().frame(maxWidth: .infinity, minHeight: 80) }
                } else if shown.isEmpty {
                    EmptyState(systemImage: tab == "active" ? "file-pen-line" : "archive",
                               title: tab == "active" ? L("No active consents") : L("Nothing archived"),
                               message: tab == "active" ? L("Add one from the starting texts or write your own.") : L("Archived consents show here and can be restored."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 8, alignment: .top)], spacing: 8) {
                        ForEach(shown) { template in row(template) }
                    }
                    Text(tab == "active" ? LP(shown.count, "1 active consent", "%d active consents") : LP(shown.count, "1 archived consent", "%d archived consents"))
                        .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .task { if templates == nil { await load() } }
        .sheet(item: $target) { target in
            TeamConsentTemplateEditor(
                templateId: target.templateId,
                canEdit: canEdit,
                businessName: workspace.current?.name,
                enabledCategories: workspace.current?.enabledCategories ?? [],
                catalog: model.catalog
            ) { await load() }
        }
    }

    private func requiredLabel(_ template: TeamConsentTemplate) -> String? {
        let services = model.catalog?.services ?? []
        let names = (template.requiredFor?.stayKinds ?? []).map { TeamConsentRules.stayKindLabel($0) }
            + (template.requiredFor?.serviceIds ?? []).map { id in services.first { $0.id == id }?.label ?? id }
        if names.isEmpty { return nil }
        return names.count <= 3 ? names.joined(separator: ", ") : LF("%1$@ and %2$d more", names.prefix(3).joined(separator: ", "), names.count - 3)
    }

    private func row(_ template: TeamConsentTemplate) -> some View {
        Button { target = TeamConsentTarget(templateId: template.id) } label: {
            HStack(alignment: .top, spacing: 12) {
                Glyph("file-pen-line", size: 20).foregroundStyle(Theme.blue).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title ?? "").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.leading)
                    FlowLayout(spacing: 4) {
                        Chip(text: TeamConsentRules.validityLabel(template.validity, template.validDays), tone: .custom(Theme.inkSoft), percent: 14)
                        Chip(text: (template.language ?? "es").uppercased(), tone: .custom(Theme.inkSoft), percent: 14)
                        if template.needsAmount == true { Chip(text: L("Names an amount"), tone: .custom(Theme.mango), icon: "coins", percent: 14) }
                        Chip(text: LF("Version %d", template.version ?? 1), tone: .custom(Theme.inkSoft), percent: 14)
                    }
                    Text((requiredLabel(template).map { LF("Required for: %@", $0) } ?? L("Asked for when someone chooses it")) + " · " + LF("Changed %@", DateText.date(template.updatedAt)))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft).padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        do {
            templates = try await API.get("/provider-consent-templates", query: ["includeArchived": "true"])
            failed = nil
        } catch {
            if templates == nil { failed = errorText(error, fallback: L("The consents could not be loaded.")) }
        }
    }
}

private struct TeamConsentTarget: Identifiable {
    let id = UUID()
    /// nil = a new one.
    let templateId: String?
}

// MARK: - The editor

private struct TeamConsentDraft: Equatable {
    var language: String
    var title: String
    var body: String
    var validity: String
    var validDays: String
    var serviceIds: [String]
    var stayKinds: [String]

    init(language: String, title: String, body: String, validity: String, validDays: Int?, serviceIds: [String] = [], stayKinds: [String] = []) {
        self.language = language
        self.title = title
        self.body = body
        self.validity = validity
        self.validDays = validDays.map(String.init) ?? ""
        self.serviceIds = serviceIds
        self.stayKinds = stayKinds
    }

    func same(_ other: TeamConsentDraft) -> Bool {
        language == other.language && title == other.title && body == other.body && validity == other.validity && validDays == other.validDays
            && Set(serviceIds) == Set(other.serviceIds) && Set(stayKinds) == Set(other.stayKinds)
    }
}

private struct TeamConsentTemplateEditor: View {
    let templateId: String?
    let canEdit: Bool
    let businessName: String?
    let enabledCategories: [String]
    let catalog: TeamServiceCatalog?
    let onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var detail: TeamConsentTemplateDetail?
    @State private var detailFailed: String?
    @State private var library: [TeamConsentLibraryEntry]?
    @State private var libraryFailed = false
    @State private var libraryLanguage = LocalizationManager.shared.currentLanguage == .english ? "en" : "es"
    @State private var defaultKey: String?
    @State private var draft: TeamConsentDraft?
    @State private var saved: TeamConsentDraft?
    @State private var selection: TextSelection?
    @State private var preview = false
    @State private var openVersion: String?
    @State private var saving = false

    private var isNew: Bool { templateId == nil }
    private var readOnly: Bool { !canEdit || detail?.status == "archived" }
    private var dirty: Bool {
        guard let draft else { return false }
        if let saved { return !draft.same(saved) }
        return draft.title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty != nil || draft.body.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty != nil
    }
    private var wordsChanged: Bool {
        guard let draft, let saved else { return false }
        return draft.title.trimmingCharacters(in: .whitespacesAndNewlines) != saved.title.trimmingCharacters(in: .whitespacesAndNewlines)
            || draft.body.trimmingCharacters(in: .whitespacesAndNewlines) != saved.body.trimmingCharacters(in: .whitespacesAndNewlines)
            || draft.language != saved.language
    }
    private var choosingStart: Bool { isNew && draft == nil }

    var body: some View {
        ProviderModal(
            title: isNew ? L("New consent") : (detail?.title ?? L("Consent")),
            subtitle: detail.map { LF("Version %1$d · %2$d signed", $0.version ?? 1, $0.signedCount ?? 0) } ?? (isNew ? L("Start from a blank page or one of the starting texts.") : nil),
            systemImage: "file-pen-line",
            accent: .aqua,
            isDirty: canEdit && dirty,
            form: form,
            primaryTitle: canEdit && !readOnly && !choosingStart ? (isNew ? L("Add consent") : (wordsChanged ? LF("Save as version %d", (detail?.version ?? 0) + 1) : L("Save"))) : nil,
            isWorking: saving,
            // Choosing where to start has nothing to cancel yet: "Close", as on the web.
            cancelTitle: canEdit && !choosingStart ? L("Cancel") : L("Close"),
            secondaryActions: canEdit && detail != nil
                ? [detail?.status == "archived"
                    ? ModalAction(L("Restore"), icon: "archive-restore") { setArchived(false) }
                    : ModalAction(L("Archive"), icon: "archive") { setArchived(true) }]
                : [],
            primaryIcon: isNew ? "file-plus-2" : "save",
            onPrimary: canEdit && !readOnly && !choosingStart ? { save() } : nil
        ) {
            NoticeCard(tone: .warning, title: L("Wording must be reviewed by a professional before you rely on it."), message: L("The starting texts follow public guidance (NOM-064-ZOO-2000, AVMA) but aren’t legal advice for your business."), icon: "scale", look: .banner)
            if !isNew && detail == nil {
                if let detailFailed {
                    Text(detailFailed).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                        .padding(.horizontal, 16).padding(.vertical, 24).frame(maxWidth: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                }
            } else if choosingStart {
                startPicker
            } else if let draft {
                editor(draft)
            }
        }
        .presentationDetents([.large])
        .task { await load() }
        .onChange(of: libraryLanguage) { Task { await loadLibrary() } }
    }

    // MARK: Loading

    private func load() async {
        if let templateId {
            do {
                let loaded: TeamConsentTemplateDetail = try await API.get("/provider-consent-templates/\(templateId)")
                detail = loaded
                let next = TeamConsentDraft(language: loaded.language ?? "es", title: loaded.title ?? "", body: loaded.body ?? "", validity: loaded.validity ?? "per_act", validDays: loaded.validDays, serviceIds: loaded.requiredFor?.serviceIds ?? [], stayKinds: loaded.requiredFor?.stayKinds ?? [])
                saved = next
                // What is being typed stays; a first load fills the form.
                if draft == nil { draft = next }
            } catch {
                detailFailed = errorText(error, fallback: L("The consent could not be loaded."))
            }
        } else if canEdit {
            await loadLibrary()
        }
    }

    private func loadLibrary() async {
        do {
            library = try await API.get("/provider-consent-templates/library", query: ["language": libraryLanguage])
            libraryFailed = false
        } catch {
            libraryFailed = true
        }
    }

    // MARK: Starting point

    private var startPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { start(nil) } label: {
                HStack(spacing: 12) {
                    Glyph("file-plus-2", size: 20).foregroundStyle(Theme.blue)
                        .frame(width: 40, height: 40).background(Theme.wash(Theme.blue, 12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("A blank consent")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        Text(L("Write your own words.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
                .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
            }
            .buttonStyle(.plain)
            HStack {
                HStack(spacing: 8) {
                    Glyph("book-open", size: 16)
                    Text(L("Starting texts").uppercased()).tracking(1.7)
                }
                .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.blue)
                Spacer()
                Segmented(options: [.init("es", "Español"), .init("en", "English")], selection: $libraryLanguage, look: .solid, label: L("Language"))
                    .frame(maxWidth: 200)
            }
            if library == nil && !libraryFailed {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else if libraryFailed {
                Text(L("The starting texts could not be loaded. Start from a blank one, or try again later."))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 24).frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            } else {
                ForEach(library ?? [], id: \.self) { entry in
                    Button { start(entry) } label: {
                        HStack(spacing: 12) {
                            Glyph("file-pen-line", size: 20).foregroundStyle(Theme.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title ?? "").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.leading)
                                FlowLayout(spacing: 4) {
                                    Chip(text: TeamConsentRules.validityLabel(entry.validity, entry.validDays), tone: .custom(Theme.inkSoft), percent: 14)
                                    if TeamConsentRules.needsAmount(entry.title ?? "", entry.body ?? "") { Chip(text: L("Names an amount"), tone: .custom(Theme.mango), percent: 14) }
                                }
                            }
                            Spacer()
                            Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func start(_ entry: TeamConsentLibraryEntry?) {
        if let entry {
            draft = TeamConsentDraft(language: entry.language ?? libraryLanguage, title: entry.title ?? "", body: entry.body ?? "", validity: entry.validity ?? "per_act", validDays: entry.validDays)
        } else {
            draft = TeamConsentDraft(language: libraryLanguage, title: "", body: "", validity: "per_act", validDays: nil)
        }
        defaultKey = entry?.key
        saved = nil
        form.errors = [:]
    }

    // MARK: The words and the rules

    private func binding<T>(_ path: WritableKeyPath<TeamConsentDraft, T>, in snapshot: TeamConsentDraft, clear key: String? = nil) -> Binding<T> {
        Binding(get: { draft?[keyPath: path] ?? snapshot[keyPath: path] }, set: { value in draft?[keyPath: path] = value; if let key { form.clear(key) } })
    }

    @ViewBuilder
    private func editor(_ draft: TeamConsentDraft) -> some View {
        if detail?.status == "archived" {
            Text(L("Archived: it isn’t asked for any more. Restore it to change it."))
                .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        }
        if isNew {
            Button { self.draft = nil; defaultKey = nil } label: {
                HStack(spacing: 6) {
                    Glyph("arrow-left", size: 16)
                    Text(L("Start from something else"))
                }
                .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
            }
            .buttonStyle(.plain)
        }
        PMTextField(L("Title"), text: binding(\.title, in: draft, clear: "title"), key: "title", form: form, prompt: L("e.g. Consent for surgery and anesthesia"))
            .disabled(readOnly)
        FormField(label: L("Language")) {
            Segmented(options: [.init("es", "Español"), .init("en", "English")], selection: binding(\.language, in: draft), look: .solid, label: L("Language"))
                .disabled(readOnly)
        }
        if preview {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Preview with sample values")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                previewCard(draft)
            }
        } else {
            FormField(label: L("Text"), key: "body", hint: LF("%1$@ of %2$@ characters", draft.body.count.formatted(), TeamConsentRules.bodyMax.formatted()), form: form) {
                VStack(alignment: .leading, spacing: 8) {
                    if !readOnly {
                        FlowLayout(spacing: 6) {
                            ForEach(TeamConsentRules.placeholders, id: \.self) { key in
                                Button { insert(key) } label: {
                                    HStack(spacing: 4) {
                                        Text("{\(key)}").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Theme.inkStrong)
                                        Text(TeamConsentRules.placeholderLabel(key)).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                                    }
                                    .padding(.horizontal, 10).frame(height: 32)
                                    .background(Theme.wash(Theme.blue, 8), in: Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.mix(Theme.blue, 40, with: Theme.borderSoft), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(LF("Put in %@", TeamConsentRules.placeholderLabel(key)))
                            }
                        }
                    }
                    TextEditor(text: binding(\.body, in: draft, clear: "body"), selection: $selection)
                        .font(Theme.text(14))
                        .frame(minHeight: 260)
                        .scrollContentBackground(.hidden)
                        .fieldChrome(invalid: form.error("body") != nil, multiline: true)
                        .disabled(readOnly)
                        .overlay(alignment: .topLeading) {
                            if draft.body.isEmpty {
                                Text(L("Write what the client agrees to. Use the placeholders for the pet, the client, the date…"))
                                    .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                                    .padding(.horizontal, 18).padding(.vertical, 20)
                                    .allowsHitTesting(false)
                            }
                        }
                        .onChange(of: draft.body.count) { _, count in
                            if count > TeamConsentRules.bodyMax { self.draft?.body = String(draft.body.prefix(TeamConsentRules.bodyMax)) }
                        }
                }
            }
        }

        PMButton(preview ? L("Back to the text") : L("See the preview"), variant: .outline, size: .compact) { preview.toggle() }

        ModalSection(title: L("How long a signature lasts")) {
            ChoiceCards(options: [
                ("per_act", L("Each visit or stay"), L("Signed again every time, e.g. a surgery or a sedation.")),
                ("standing", L("Once per pet"), L("Signed once and valid for the days you set, e.g. daycare rules.")),
            ], selection: binding(\.validity, in: draft))
            .disabled(readOnly)
            if draft.validity == "standing" {
                PMTextField(L("Valid for (days)"), text: Binding(get: { draft.validDays }, set: { value in self.draft?.validDays = String(value.filter(\.isNumber).prefix(4)); form.clear("validDays") }), key: "validDays", form: form, prompt: "365", hint: L("Leave it empty to keep it until it is revoked."), keyboard: .numberPad)
                    .disabled(readOnly)
            }
        }

        ModalSection(title: L("Required before it starts"), subtitle: L("A visit with one of these services, or a stay of these kinds, can’t start until it is signed. Owners and admins can still start with a reason.")) {
            Text(L("Stays")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
            FlowLayout(spacing: 6) {
                ForEach(TeamConsentRules.stayKinds, id: \.self) { kind in
                    FilterChip(title: TeamConsentRules.stayKindLabel(kind), isSelected: draft.stayKinds.contains(kind)) {
                        guard !readOnly else { return }
                        self.draft?.stayKinds = draft.stayKinds.contains(kind) ? draft.stayKinds.filter { $0 != kind } : draft.stayKinds + [kind]
                    }
                }
            }
            if catalog == nil { ProgressView().frame(maxWidth: .infinity) }
            ForEach(serviceGroups(draft), id: \.id) { group in
                Text(group.label).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                FlowLayout(spacing: 6) {
                    ForEach(group.services, id: \.id) { service in
                        FilterChip(title: service.label, isSelected: draft.serviceIds.contains(service.id)) {
                            guard !readOnly else { return }
                            self.draft?.serviceIds = draft.serviceIds.contains(service.id) ? draft.serviceIds.filter { $0 != service.id } : draft.serviceIds + [service.id]
                        }
                    }
                }
            }
            let known = Set((catalog?.services ?? []).map(\.id))
            let unknown = draft.serviceIds.filter { !known.contains($0) }
            if catalog != nil && !unknown.isEmpty {
                Text(L("Other services")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                FlowLayout(spacing: 6) {
                    ForEach(unknown, id: \.self) { id in
                        FilterChip(title: id, isSelected: true) { if !readOnly { self.draft?.serviceIds = draft.serviceIds.filter { $0 != id } } }
                    }
                }
            }
        }

        if let versions = detail?.versions, !versions.isEmpty {
            ModalSection(title: L("Versions"), subtitle: L("Each saved wording is a version. Consents already signed keep the exact words they were signed with.")) {
                ForEach(versions) { version in versionRow(version) }
            }
        }

    }

    private func previewCard(_ draft: TeamConsentDraft) -> some View {
        let samples = TeamConsentRules.samples(draft.language, business: businessName)
        return VStack(alignment: .leading, spacing: 8) {
            Text(TeamConsentRules.render(draft.title, samples).nonEmpty ?? L("Untitled")).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
            if let text = TeamConsentRules.render(draft.body, samples).nonEmpty {
                Text(text).font(Theme.text(14)).foregroundStyle(Theme.inkStrong).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L("The text shows here as the client will read it.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            if TeamConsentRules.needsAmount(draft.title, draft.body) {
                Text(L("It names {amount}: whoever asks for it enters the amount first.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(Theme.aqua, 6), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    private func versionRow(_ version: TeamConsentVersion) -> some View {
        let expanded = openVersion == version.id
        return VStack(alignment: .leading, spacing: 8) {
            Button { openVersion = expanded ? nil : version.id } label: {
                HStack(spacing: 8) {
                    Glyph("history", size: 16).foregroundStyle(Theme.inkSoft)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(LF("Version %d", version.version ?? 1)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            if version.version == detail?.version {
                                Text(L("In use")).font(Theme.text(10.6, weight: .heavy)).foregroundStyle(Theme.inkStrong)
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Theme.wash(Theme.lime, 35), in: Capsule())
                            }
                        }
                        Text([DateText.dayTime(version.createdAt), version.createdByName.nonEmpty, version.language?.uppercased()].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                    Spacer()
                    Glyph("chevron-down", size: 16).rotationEffect(.degrees(expanded ? 180 : 0)).foregroundStyle(Theme.inkSoft)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(version.title ?? "").font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    Text(version.body ?? "").font(Theme.text(14)).foregroundStyle(Theme.inkStrong).fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { RowDivider() }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    /// Services grouped by kind: the ones this business offers, plus any already chosen.
    private func serviceGroups(_ draft: TeamConsentDraft) -> [(id: String, label: String, services: [TeamServiceCatalog.Service])] {
        let services = catalog?.services ?? []
        let chosen = Set(draft.serviceIds)
        let offered = Set(enabledCategories)
        return (catalog?.categories ?? []).compactMap { category in
            let list = services.filter { $0.category == category.id && (offered.contains(category.id) || chosen.contains($0.id)) }
            return list.isEmpty ? nil : (category.id, category.label ?? category.id, list)
        }
    }

    private func insert(_ key: String) {
        guard let draft, !readOnly else { return }
        var range: Range<String.Index>?
        if let selection, case .selection(let picked) = selection.indices, picked.upperBound <= draft.body.endIndex { range = picked }
        let next = TeamConsentRules.insert(key, into: draft.body, range: range)
        self.draft?.body = String(next.text.prefix(TeamConsentRules.bodyMax))
        form.clear("body")
        let body = self.draft?.body ?? ""
        let caret = body.index(body.startIndex, offsetBy: min(next.caret, body.count))
        selection = TextSelection(insertionPoint: caret)
    }

    // MARK: Saving

    private func save() {
        guard let draft else { return }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let daysText = draft.validDays.trimmingCharacters(in: .whitespaces)
        let days = Int(daysText)
        let daysValid = daysText.isEmpty || (days.map { (1...TeamConsentRules.validDaysMax).contains($0) } ?? false)
        guard form.check([
            ("title", title.isEmpty ? L("Give the consent a title.") : (title.count > TeamConsentRules.titleMax ? LF("Keep the title under %d characters.", TeamConsentRules.titleMax) : nil)),
            ("body", body.isEmpty ? L("Write the consent’s text.") : nil),
            ("validDays", draft.validity == "standing" && !daysValid ? L("Enter a number of days between 1 and 3650, or leave it empty.") : nil),
        ]) else { return }
        if !isNew && !dirty { dismiss(); return }
        let validDays: Int? = draft.validity == "standing" ? days : nil
        let requiredFor: [String: Any?] = ["serviceIds": draft.serviceIds, "stayKinds": draft.stayKinds]
        var input: [String: Any?] = [:]
        if isNew {
            if let defaultKey { input["defaultKey"] = defaultKey }
            input["language"] = draft.language
            input["title"] = title
            input["body"] = body
            input["validity"] = draft.validity
            input["validDays"] = validDays
            input["requiredFor"] = requiredFor
        } else if let saved {
            if draft.language != saved.language { input["language"] = draft.language }
            if title != saved.title.trimmingCharacters(in: .whitespacesAndNewlines) { input["title"] = title }
            if body != saved.body.trimmingCharacters(in: .whitespacesAndNewlines) { input["body"] = body }
            if draft.validity != saved.validity { input["validity"] = draft.validity }
            if draft.validity != saved.validity || draft.validDays != saved.validDays { input["validDays"] = validDays }
            if Set(draft.serviceIds) != Set(saved.serviceIds) || Set(draft.stayKinds) != Set(saved.stayKinds) { input["requiredFor"] = requiredFor }
        }
        let changedWords = wordsChanged
        saving = true
        Task {
            defer { saving = false }
            do {
                if let templateId {
                    let _: EmptyResponse = try await API.patch("/provider-consent-templates/\(templateId)", body: input)
                    Toast.show(changedWords ? L("Saved as a new version.") : L("Saved."))
                } else {
                    let _: EmptyResponse = try await API.post("/provider-consent-templates", body: input)
                    Toast.show(L("Consent added."))
                }
                await onDone()
                announceDataChanged()
                dismiss()
            } catch {
                form.apply(error, known: ["title": "title", "body": "body", "validDays": "validDays"])
            }
        }
    }

    private func setArchived(_ archived: Bool) {
        guard let templateId else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let _: EmptyResponse = try await API.patch("/provider-consent-templates/\(templateId)", body: ["status": archived ? "archived" : "active"])
                Toast.show(archived ? L("Archived. It is no longer asked for, and signed ones keep counting.") : L("Active again."))
                await onDone()
                announceDataChanged()
                dismiss()
            } catch {
                Toast.error(errorText(error, fallback: L("Could not change it. Try again.")))
            }
        }
    }
}
