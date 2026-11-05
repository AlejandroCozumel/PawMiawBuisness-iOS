//
//  PhotoField.swift
//  PawMiawNegocios
//
//  One field for every photo a form takes (a pet, a person, a logo, a place,
//  a report): the current or new picture, choose / change, and remove with
//  undo when the saved one may go. Round for faces, rounded square otherwise.
//

import SwiftUI
import PhotosUI

struct PhotoField: View {
    enum Shape { case circle, rounded }

    let label: String
    var hint: String? = nil
    /// The saved photo's URL, if any.
    var currentURL: String? = nil
    @Binding var draft: PhotoDraft
    var shape: Shape = .rounded
    var optional: Bool = true
    /// Whether the saved photo can be removed from here.
    var allowsRemove: Bool = true
    var addTitle: String = L("Add a photo")
    var changeTitle: String = L("Change photo")
    var removeTitle: String = L("Remove")
    /// The button that removes the SAVED photo, when it should read differently
    /// from removing a new pick ("Use the business’s logo").
    var removeSavedTitle: String? = nil
    var removedNote: String = L("Removed when you save.")
    var key: String? = nil
    var form: FormState? = nil

    @State private var item: PhotosPickerItem?
    @State private var loading = false

    private var hasImage: Bool { draft.preview != nil || (currentURL?.nonEmpty != nil && !draft.removed) }
    private var side: CGFloat { shape == .circle ? 64 : 88 }

    var body: some View {
        FormField(label: label, key: key, hint: hint, form: form, optional: optional) {
            HStack(alignment: .center, spacing: 12) {
                picture
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $item, matching: .images) {
                        Label(hasImage ? changeTitle : addTitle, systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.pm(.outline, size: .compact))
                    if draft.preview != nil {
                        Button(removeTitle) { draft.data = nil; draft.preview = nil; item = nil }
                            .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.coralText)
                    } else if draft.removed {
                        HStack(spacing: 6) {
                            Text(removedNote).font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
                            Button(L("Undo")) { draft.removed = false }.font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blueText)
                        }
                    } else if allowsRemove, currentURL?.nonEmpty != nil {
                        Button(removeSavedTitle ?? removeTitle) { draft.removed = true }
                            .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.coralText)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            loading = true
            Task {
                defer { loading = false }
                if let data = await ImageUpload.load(picked) {
                    draft.data = data
                    draft.preview = UIImage(data: data)
                    draft.removed = false
                    if let key { form?.clear(key) }
                } else {
                    Toast.error(L("That photo could not be read. Try another one."))
                }
            }
        }
    }

    private var picture: some View {
        ZStack {
            Theme.surfaceMuted
            if let preview = draft.preview {
                Image(uiImage: preview).resizable().scaledToFill()
            } else if !draft.removed, let url = APIConfig.assetURL(currentURL) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { ProgressView() }
                }
            } else {
                Image(systemName: shape == .circle ? "person.crop.circle" : "photo").font(.system(size: 24)).foregroundStyle(Theme.inkSoft)
            }
            if loading { ProgressView() }
        }
        .frame(width: side, height: side)
        .clipShape(shape == .circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
        .overlay {
            if shape == .circle { Circle().stroke(Theme.borderSoft, lineWidth: 1) }
            else { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.borderSoft, lineWidth: 1) }
        }
    }
}
