//
//  SignatureCapture.swift
//  PawMiawNegocios
//
//  One way to capture and keep a signature everywhere (web components/app/
//  esign/signature-capture.tsx, signature-mark.tsx, my-signature-card.tsx,
//  esign-terms.tsx; lib/esign.ts; backend docs/e-signatures.md): draw it on
//  the shared `SignaturePad`, type it (shown in Dancing Script,
//  `Font.signatureScript`, the font the server stamps), use the saved one
//  ("Mi firma"), or upload a scan the server trims and clears. The capture
//  only shows the ways the place allows.
//
//  Used by Home's member welcome (the signature adopted once, with the
//  e-sign terms accepted one time), Clients' closing sheets (the saved
//  signature or one drawn there) and Team's "Mi firma" card (Your account
//  and a staff member's page). Uploads go through `API.multipart`.
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - What the server keeps

/// A saved signature (`GET /users/me/signatures`): an image, or typed words.
struct SignatureMark: Decodable, Hashable {
    let id: String?
    let purpose: String?
    /// "drawn", "typed", "uploaded" or "none".
    let kind: String?
    let text: String?
    let font: String?
    let imageDataUrl: String?
    let createdAt: String?

    /// A mark the server sent inside something else (a signed consent, a closing).
    init(kind: String?, text: String? = nil, imageDataUrl: String? = nil, createdAt: String? = nil) {
        id = nil
        purpose = nil
        font = nil
        self.kind = kind
        self.text = text
        self.imageDataUrl = imageDataUrl
        self.createdAt = createdAt
    }

    /// A mark worth drawing: an image, or typed words.
    var isVisible: Bool {
        if kind == "typed" { return text.nonEmpty != nil }
        if kind == "none" { return false }
        return imageDataUrl.nonEmpty != nil || (kind == nil && text.nonEmpty != nil)
    }
}

/// The account's two saved signatures: a family's own, and a professional's.
struct MySignatures: Decodable {
    let personal: SignatureMark?
    let professional: SignatureMark?
}

/// The consent to sign electronically (`GET /esign/terms`): its versioned text.
struct EsignTerms: Decodable, Hashable {
    let version: String
    let language: String?
    let title: String?
    let text: String?
    /// "Must be reviewed by a professional", when the server says so.
    let reviewNote: String?
}

// MARK: - The rules (web lib/esign.ts)

enum SignatureRules {
    static let typedMin = 2
    static let typedMax = 80
    static let uploadMaxBytes = 5 * 1024 * 1024
    /// Dark ink on white "paper", in light and dark mode alike.
    static let ink = Color(red: 27 / 255, green: 36 / 255, blue: 51 / 255)

    /// A typed signature as the server keeps it (spaces collapsed), or nil when too short or too long.
    static func typed(_ value: String) -> String? {
        let text = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (typedMin...typedMax).contains(text.count) ? text : nil
    }

    /// An image from a `data:` URL the server sends.
    static func image(_ dataURL: String?) -> UIImage? {
        guard let dataURL, dataURL.hasPrefix("data:"), let comma = dataURL.firstIndex(of: ",") else { return nil }
        guard let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]), options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: data)
    }

    /// The pad's strokes as the PNG the server keeps: dark ink on a clear background, like the web's pad.
    static func png(_ strokes: [[CGPoint]]) -> Data? {
        guard inkPoints(strokes) >= 2 else { return nil }
        let size = SignaturePad.size
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            var path = Path()
            SignaturePad.draw(strokes, into: &path, scale: CGSize(width: 1, height: 1))
            let bezier = UIBezierPath(cgPath: path.cgPath)
            bezier.lineWidth = 3
            bezier.lineCapStyle = .round
            bezier.lineJoinStyle = .round
            UIColor(red: 27 / 255, green: 36 / 255, blue: 51 / 255, alpha: 1).setStroke()
            bezier.stroke()
        }
        return image.pngData()
    }

    static func inkPoints(_ strokes: [[CGPoint]]) -> Int { strokes.reduce(0) { $0 + $1.count } }

    static func dataURL(png: Data) -> String { "data:image/png;base64,\(png.base64EncodedString())" }

    /// The server's refusals about a signature, in the reader's words.
    static func message(_ error: Error, fallback: String) -> String {
        switch (error as? APIError)?.code {
        case "typed_signature_required": L("Type the signature (2 to 80 characters).")
        case "signature_missing": L("Draw the signature.")
        case "signature_invalid": L("Use a PNG, JPEG or WebP image.")
        case "signature_too_large": L("The image is larger than 5 MB.")
        case "signature_blank": L("The image has no signature on it. Choose another one.")
        default: errorText(error, fallback: fallback)
        }
    }
}

// MARK: - Capturing one

/// The ways a place lets someone sign.
enum SignatureCaptureMode: String, CaseIterable, Hashable {
    case draw, type, saved, upload

    var title: String {
        switch self {
        case .draw: L("Draw@signature")
        case .type: L("Type@signature")
        case .saved: L("Use my signature")
        case .upload: L("Upload a scan")
        }
    }

    /// A professional's saved signature: drawn, typed or a scan.
    static let professional: [SignatureCaptureMode] = [.draw, .type, .upload]
    /// Signing in place (closing a file): the saved signature, or one drawn here.
    static let savedOrDrawn: [SignatureCaptureMode] = [.saved, .draw]
}

/// What a capture hands back.
enum CapturedSignature: Equatable {
    case saved
    /// A PNG.
    case drawn(Data)
    case typed(String)
    /// A JPEG of the scan.
    case uploaded(Data)

    /// As a JSON body's `signature` (closing a file): the saved one, or the drawing as a data URL.
    var json: [String: Any?] {
        switch self {
        case .saved: ["kind": "saved"]
        case .drawn(let png): ["kind": "drawn", "image": SignatureRules.dataURL(png: png)]
        case .typed(let text): ["kind": "typed", "text": text]
        case .uploaded(let jpeg): ["kind": "uploaded", "image": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]
        }
    }
}

/// What is being captured: the way chosen and what each way holds. The screen keeps it, so its
/// save reads it; a new one starts clean (the pad starts clean every time a sheet opens).
struct SignatureDraft: Equatable {
    var mode: SignatureCaptureMode = .draw
    var strokes: [[CGPoint]] = []
    var typed = ""
    var scan: Data? = nil

    var isDirty: Bool { !strokes.isEmpty || typed.nonEmpty != nil || scan != nil }

    /// The sentence to show while the chosen way has nothing usable; nil once it is ready.
    func problem(saved: SignatureMark? = nil) -> String? {
        switch mode {
        case .saved: return saved?.isVisible == true ? nil : L("There is no saved signature. Draw or type one.")
        case .type: return SignatureRules.typed(typed) == nil ? L("Type the signature (2 to 80 characters).") : nil
        case .upload:
            guard let scan else { return L("Choose the scan of your signature.") }
            return scan.count > SignatureRules.uploadMaxBytes ? L("The image is larger than 5 MB.") : nil
        case .draw: return SignatureRules.inkPoints(strokes) >= 2 ? nil : L("Draw the signature.")
        }
    }

    /// The signature as it stands, or nil (`problem` says why).
    func captured(saved: SignatureMark? = nil) -> CapturedSignature? {
        guard problem(saved: saved) == nil else { return nil }
        switch mode {
        case .saved: return .saved
        case .type: return SignatureRules.typed(typed).map { .typed($0) }
        case .upload: return scan.map { .uploaded($0) }
        case .draw: return SignatureRules.png(strokes).map { .drawn($0) }
        }
    }
}

/// Draw, type, use the saved one or upload a scan, as one field (its sentence under it when invalid).
struct SignatureCapture: View {
    let modes: [SignatureCaptureMode]
    @Binding var draft: SignatureDraft
    /// The saved signature shown under "Use my signature".
    var saved: SignatureMark? = nil
    /// Typed text to start from (the signer's name) when Type opens empty.
    var suggestedText: String? = nil
    /// What using the saved signature means here.
    var savedHint: String? = nil
    /// The field's label (nil where the block around it already says it).
    var label: String? = L("Your signature")
    var key: String = "signature"
    var form: FormState? = nil

    @State private var pickerItem: PhotosPickerItem?
    @State private var offeredSaved = false

    private var available: [SignatureCaptureMode] { modes.filter { $0 != .saved || saved?.isVisible == true } }
    private var invalid: Bool { form?.error(key) != nil }

    var body: some View {
        Group {
            if let label {
                FormField(label: label, key: key, form: form) { control }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    control
                    if let error = form?.error(key) {
                        Text(error).font(Theme.text(13, weight: .semibold)).foregroundStyle(Theme.coralText)
                    }
                }
                .id(key)
            }
        }
        .onAppear(perform: settle)
        .onChange(of: saved?.isVisible) { settle() }
        .onChange(of: pickerItem) { _, item in pick(item) }
    }

    private var control: some View {
        VStack(alignment: .leading, spacing: 10) {
            if available.count > 1 {
                Picker(L("How to sign"), selection: Binding(get: { draft.mode }, set: choose)) {
                    ForEach(available, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            switch draft.mode {
            case .draw:
                SignaturePad(strokes: $draft.strokes, showsClear: true)
                    .onChange(of: draft.strokes.count) { form?.clear(key) }
            case .type: typing
            case .saved:
                SignatureMarkView(mark: saved, height: 144, highlighted: true)
                Text(savedHint ?? L("Your saved signature (Mi firma) is placed on this document."))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            case .upload: uploading
            }
        }
    }

    private var typing: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("Type your signature"), text: $draft.typed)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .fieldChrome(invalid: invalid)
                .accessibilityLabel(L("Typed signature"))
                .onChange(of: draft.typed) { _, value in
                    if value.count > SignatureRules.typedMax { draft.typed = String(value.prefix(SignatureRules.typedMax)) }
                    form?.clear(key)
                }
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white)
                RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.borderSoft, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                if let text = draft.typed.nonEmpty?.trimmingCharacters(in: .whitespaces).nonEmpty {
                    TypedSignature(text: text, size: 44)
                } else {
                    Text(L("Your signature shows here")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Color(red: 138 / 255, green: 150 / 255, blue: 168 / 255))
                }
                VStack {
                    Spacer()
                    Rectangle().fill(Color(red: 201 / 255, green: 210 / 255, blue: 222 / 255)).frame(height: 1).padding(.horizontal, 24).padding(.bottom, 24)
                }
                .allowsHitTesting(false)
            }
            .frame(height: 132)
            .accessibilityHidden(true)
        }
    }

    private var uploading: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white)
                    RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(invalid ? Theme.coral : Theme.borderSoft, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    if let scan = draft.scan, let image = UIImage(data: scan) {
                        Image(uiImage: image).resizable().scaledToFit().padding(8).accessibilityLabel(L("The scan you chose"))
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.badge.arrow.down").font(.system(size: 22))
                            Text(L("Choose a photo or scan of your signature on white paper")).font(Theme.text(14, weight: .semibold)).multilineTextAlignment(.center)
                        }
                        .foregroundStyle(Color(red: 107 / 255, green: 114 / 255, blue: 128 / 255))
                        .padding(12)
                    }
                }
                .frame(height: 144)
            }
            .buttonStyle(.plain)
            Text(L("PNG, JPEG or WebP up to 5 MB. PawMiaw trims it and makes the paper transparent."))
                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
    }

    private func choose(_ next: SignatureCaptureMode) {
        draft.mode = next
        form?.clear(key)
        if next == .type && draft.typed.nonEmpty == nil, let name = suggestedText.nonEmpty { draft.typed = name }
    }

    /// A saved signature that arrives late becomes the first choice once; one that goes away leaves its tab.
    private func settle() {
        if saved?.isVisible == true && modes.contains(.saved) && !offeredSaved {
            offeredSaved = true
            draft.mode = .saved
        }
        if !available.contains(draft.mode) { draft.mode = available.first ?? .draw }
        if draft.mode == .type && draft.typed.nonEmpty == nil, let name = suggestedText.nonEmpty { draft.typed = name }
    }

    /// Any photo becomes a JPEG the server takes (a HEIC from the camera too).
    private func pick(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let jpeg = await ImageUpload.load(item) else { refuse(L("Use a PNG, JPEG or WebP image.")); return }
            guard jpeg.count <= SignatureRules.uploadMaxBytes else { refuse(L("The image is larger than 5 MB.")); return }
            draft.scan = jpeg
            form?.clear(key)
        }
    }

    private func refuse(_ sentence: String) {
        form?.errors[key] = sentence
        Toast.error(sentence)
    }
}

// MARK: - Showing one

/// Typed words in the signature font, sized to the box.
struct TypedSignature: View {
    let text: String
    var size: CGFloat = 38

    var body: some View {
        Text(text)
            .font(.signatureScript(size))
            .foregroundStyle(SignatureRules.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 12)
    }
}

/// How a signature looks, whatever made it: a drawn or scanned image, or typed words in the
/// signature font. Always on white "paper" so dark ink reads in dark mode too.
struct SignatureMarkView: View {
    let mark: SignatureMark?
    /// Who signed, for the description.
    var name: String? = nil
    var height: CGFloat = 112
    /// The chosen one (Use my signature): a blue edge.
    var highlighted: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white)
            RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(highlighted ? Theme.blue : Theme.borderSoft, lineWidth: highlighted ? 2 : 1)
            content.padding(8)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name.nonEmpty.map { LF("Signature of %@", $0) } ?? L("Signature"))
    }

    @ViewBuilder
    private var content: some View {
        if let mark, mark.isVisible, mark.kind == "typed" || (mark.imageDataUrl.nonEmpty == nil && mark.text.nonEmpty != nil) {
            TypedSignature(text: mark.text ?? "", size: height * 0.34)
        } else if let mark, mark.isVisible, let image = SignatureRules.image(mark.imageDataUrl) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            Text(L("No signature image.")).font(Theme.text(12)).foregroundStyle(Color(red: 107 / 255, green: 114 / 255, blue: 128 / 255))
        }
    }
}

// MARK: - The e-sign terms, accepted once

/// The consent to sign electronically: its versioned text, the review note and "I agree to sign
/// electronically". The version shown is the one sent with the signature.
struct EsignTermsPanel: View {
    let terms: EsignTerms?
    var failed: Bool = false
    /// The server said the terms changed since they were shown.
    var changed: Bool = false
    @Binding var accepted: Bool
    var error: String? = nil
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if changed {
                NoticeCard(tone: .warning, title: L("The terms for signing electronically were just updated. Read the new version and accept it to continue."))
            }
            if let terms {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let title = terms.title { Text(title).font(Theme.text(15, weight: .bold)).foregroundStyle(Theme.inkStrong) }
                        ForEach(Array((terms.text ?? "").components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph).font(Theme.text(13)).foregroundStyle(Theme.inkStrong)
                        }
                        Text(LF("Version %@", terms.version)).font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
                    }
                    .padding(12)
                }
                .frame(maxHeight: 220)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if let note = terms.reviewNote?.nonEmpty {
                    Label(note, systemImage: "scalemass").font(Theme.text(13, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.mango.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                ToggleRow(title: L("I agree to sign electronically"), isOn: $accepted)
                if let error { Text(error).font(Theme.text(13, weight: .semibold)).foregroundStyle(Theme.coralText) }
            } else if failed {
                Text(L("The terms for signing electronically could not be loaded.")).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                if let retry { PMButton(L("Try again"), systemImage: "arrow.clockwise", variant: .outline, size: .compact, action: retry) }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - The professional signature on the server

enum ProfessionalSignature {
    private static let path = "/users/me/signatures/professional"

    /// The account's saved professional signature, if any.
    static func load() async throws -> SignatureMark? {
        let mine: MySignatures = try await API.get("/users/me/signatures")
        return mine.professional
    }

    static func terms(language: String = LocalizationManager.shared.currentLanguage.rawValue) async throws -> EsignTerms {
        try await API.get("/esign/terms", query: ["lang": language, "purpose": "professional"])
    }

    /// Saves it (`kind` with the `signature` file or the `text`); with `terms`, also adopts it under
    /// them, so later signing is one tap (the terms accepted once).
    @discardableResult
    static func save(_ signature: CapturedSignature, terms: EsignTerms? = nil, language: String = LocalizationManager.shared.currentLanguage.rawValue) async throws -> SignatureMark {
        var fields: [(String, String)] = []
        var files: [API.UploadFile] = []
        switch signature {
        case .typed(let text):
            fields = [("kind", "typed"), ("text", text)]
        case .drawn(let png):
            fields = [("kind", "drawn")]
            files = [API.UploadFile(field: "signature", fileName: "signature.png", mimeType: "image/png", data: png)]
        case .uploaded(let jpeg):
            fields = [("kind", "uploaded")]
            files = [API.UploadFile(field: "signature", fileName: "signature.jpg", mimeType: "image/jpeg", data: jpeg)]
        case .saved:
            throw APIError(status: 0, message: L("Draw the signature."), code: "signature_missing", fields: [:])
        }
        if let terms {
            fields += [("termsAccepted", "true"), ("termsVersion", terms.version), ("language", language)]
        }
        return try await API.multipart(path, method: "PUT", fields: fields, files: files)
    }

    /// Adopts the signature already saved, accepting the terms at the version shown.
    static func adopt(terms: EsignTerms, language: String = LocalizationManager.shared.currentLanguage.rawValue) async throws {
        let _: EmptyResponse = try await API.post("\(path)/adopt", body: ["termsAccepted": true, "termsVersion": terms.version, "language": language])
    }

    static func delete() async throws {
        try await API.send("DELETE", path)
    }
}

// MARK: - "Mi firma"

/// "Mi firma" for a team member: the professional signature they keep, "Replace" or "Add my
/// signature", and "Delete". Printed on the prescriptions, signed records, discharge summaries
/// and certificates they sign; replacing or deleting it never changes what is already signed.
/// Shown on Your account and on the person's own staff page.
struct MySignatureCard: View {
    /// Typed text to start from (the signer's name) when Type opens empty.
    var suggestedName: String? = nil

    @State private var saved: SignatureMark?
    @State private var loaded = false
    @State private var failed: String?
    @State private var editing = false
    @State private var deleting = false

    static let explanation = L("Printed on the prescriptions, signed records, discharge summaries and certificates you sign. Changing it never changes documents already signed.")

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "signature")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.inkOnBright)
                    .frame(width: 36, height: 36)
                    .background(Theme.lavender.opacity(0.45), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("My professional signature")).font(Theme.sectionFont).foregroundStyle(Theme.inkStrong)
                    Text(Self.explanation).font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
            }
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else if let failed {
                ErrorState(message: failed) { await load() }
            } else if let saved, saved.isVisible {
                SignatureMarkView(mark: saved, name: suggestedName)
                if let date = saved.createdAt {
                    Text(LF("Saved %@", DateText.date(date))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            } else {
                Text(L("No signature yet. Draw it, type it or upload a scan."))
                    .font(Theme.smallFont).foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.borderSoft, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            }
            FlowLayout(spacing: 8) {
                PMButton(saved?.isVisible == true ? L("Replace") : L("Add my signature"), systemImage: "pencil.line", size: .compact) { editing = true }
                    .disabled(!loaded)
                if saved?.isVisible == true {
                    PMButton(L("Delete"), systemImage: "trash", variant: .outline, size: .compact) { deleting = true }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $editing) {
            MySignatureSheet(replacing: saved?.isVisible == true, suggestedName: suggestedName) { saved = $0 }
        }
        .sheet(isPresented: $deleting) {
            DeleteSignatureSheet { saved = nil }
        }
    }

    private func load() async {
        do {
            saved = try await ProfessionalSignature.load()
            failed = nil
        } catch {
            if saved == nil { failed = errorText(error, fallback: L("Your signature could not be loaded.")) }
        }
        loaded = true
    }
}

/// Drawing, typing or uploading the signature to keep. The pad starts clean every time it opens.
private struct MySignatureSheet: View {
    let replacing: Bool
    let suggestedName: String?
    let onSaved: (SignatureMark) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var draft = SignatureDraft()
    @State private var saving = false

    var body: some View {
        ProviderModal(
            title: L("My professional signature"),
            subtitle: replacing ? L("The new one is used from now on. Signed documents keep theirs.") : nil,
            systemImage: "signature",
            accent: .lavender,
            isDirty: draft.isDirty,
            form: form,
            primaryTitle: L("Save signature"),
            isWorking: saving
        ) {
            save()
        } content: {
            SignatureCapture(modes: SignatureCaptureMode.professional, draft: $draft, suggestedText: suggestedName, form: form)
            Text(MySignatureCard.explanation).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
        .presentationDetents([.large])
    }

    private func save() {
        guard form.check([("signature", draft.problem())]), let signature = draft.captured() else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let saved = try await ProfessionalSignature.save(signature)
                Toast.show(L("Your signature is saved."))
                onSaved(saved)
                announceDataChanged()
                dismiss()
            } catch {
                _ = form.check([("signature", SignatureRules.message(error, fallback: L("Could not save the signature. Try again.")))])
            }
        }
    }
}

/// "Delete your saved signature?", asked the same way wherever it is deleted.
private struct DeleteSignatureSheet: View {
    let onDeleted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        ProviderModal(
            title: L("Delete your saved signature?"),
            systemImage: "trash.fill",
            accent: .coral,
            primaryTitle: L("Delete signature"),
            primaryVariant: .destructive,
            isWorking: working,
            cancelTitle: L("Keep it")
        ) {
            working = true
            Task {
                defer { working = false }
                do {
                    try await ProfessionalSignature.delete()
                    onDeleted()
                    Toast.show(L("Signature deleted."))
                    announceDataChanged()
                    dismiss()
                } catch {
                    Toast.error(errorText(error, fallback: L("Could not delete it. Try again.")))
                }
            }
        } content: {
            Text(L("New documents won’t carry it until you add one again. Documents already signed keep theirs."))
                .font(Theme.bodyFont).foregroundStyle(Theme.inkStrong)
        }
        .presentationDetents([.medium, .large])
    }
}
