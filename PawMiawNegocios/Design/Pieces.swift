//
//  Pieces.swift
//  PawMiawNegocios
//
//  Shared pieces several modules draw: a sheet's context pills, a file tile, the settings
//  card of a service page (its tinted head, its rules, its save bar).
//

import SwiftUI

// MARK: - Context pills

/// Whose visit or record a sheet is about (web `ModalContextPills`): the client and each pet
/// as soft pills (32 tall, 12 semibold, the muted fill with a hairline), the client's link
/// badge after the client, then any other pill (a room, the record's kind).
struct ContextPills<Extra: View>: View {
    let client: String?
    /// The client's link badge: true "FAMILIA VINCULADA", false "SOLO EN LA CLÍNICA", nil none.
    var linked: Bool? = nil
    var pets: [String] = []
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        FlowLayout(spacing: 8) {
            if let client = client?.nonEmpty { pill(client, icon: "user-round") }
            if let linked {
                TagChip(text: linked ? L("Linked household") : L("Clinic-only"), icon: linked ? "link-2" : "building-2", linked: linked, size: .header)
            }
            ForEach(Array(pets.enumerated()), id: \.offset) { _, pet in pill(pet, icon: "paw-print") }
            extra()
        }
    }

    private func pill(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Glyph(icon, size: 14)
            Text(text).lineLimit(1)
        }
        .font(.brandText(12, weight: .semibold))
        .foregroundStyle(Theme.inkStrong)
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(Theme.surfaceMuted, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.borderSoft, lineWidth: 1))
    }
}

extension ContextPills where Extra == EmptyView {
    init(client: String?, linked: Bool? = nil, pets: [String] = []) {
        self.init(client: client, linked: linked, pets: pets, extra: { EmptyView() })
    }
}

// MARK: - A file

/// A file as a square tile (web chart-bits `AttachmentTiles`, the record page's files): a photo
/// shows itself (the `thumbnail`), any other file its icon on a pale wash with its name. With
/// `caption` the name and size sit under the tile (the record page); without, inside it (a
/// chart's history).
struct AttachmentTile<Thumbnail: View>: View {
    let fileName: String
    var sizeText: String? = nil
    var isImage: Bool = false
    var isPDF: Bool = false
    /// The file's kind on a white tag ("PDF") in a document tile.
    var fileExtension: String? = nil
    var caption: Bool = true
    var isOpening: Bool = false
    let action: () -> Void
    @ViewBuilder var thumbnail: () -> Thumbnail

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: caption ? Theme.boxRadius : Theme.chipRadius, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: action) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if isImage {
                            thumbnail()
                        } else if caption {
                            VStack(spacing: 6) {
                                Glyph(isPDF ? "file-text" : "file-text", size: 28).foregroundStyle(Theme.inkStrong)
                                if let ext = fileExtension?.nonEmpty {
                                    Text(ext)
                                        .font(.brandText(9.6, weight: .black))
                                        .tracking(0.4)
                                        .foregroundStyle(Theme.inkStrong)
                                        .padding(.horizontal, 6)
                                        .background(Theme.surface, in: Capsule())
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.wash(Theme.pink, 16))
                        } else {
                            VStack(spacing: 4) {
                                Glyph(isPDF ? "file-text" : "file", size: 24)
                                Text(fileName).font(.brandText(9.9, weight: .bold)).lineLimit(2).multilineTextAlignment(.center)
                                if let sizeText { Text(sizeText).font(.brandText(9.3)) }
                            }
                            .foregroundStyle(Theme.inkSoft)
                            .padding(6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.wash(Theme.aqua, 10))
                        }
                    }
                    .overlay {
                        if isOpening {
                            ZStack { Color.black.opacity(0.25); ProgressView().tint(.white) }
                        }
                    }
                    .background(Theme.surfaceMuted)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Theme.borderSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LF("Open %@", fileName))

            if caption {
                HStack(spacing: 4) {
                    if isImage { Glyph("file-image", size: 12).foregroundStyle(Theme.inkSoft) }
                    Text(fileName).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1).truncationMode(.middle)
                }
                if let sizeText {
                    Text(sizeText).font(Theme.text(11.2)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }
}

// MARK: - A service's settings

/// How the business does a service (web grooming-settings / home-visits-settings /
/// stays-rooms-settings): one card with a tinted head (a 44 pebble at the tone's 38%, Fredoka
/// 24, a line), a 1 pt dashed foot, the rules under it and the save bar at its foot.
struct SettingsCard<Content: View, Footer: View>: View {
    let icon: String
    let tone: Color
    let title: String
    let hint: String
    var note: String? = nil
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Glyph(icon, size: 20)
                    .foregroundStyle(Theme.inkStrong)
                    .frame(width: 44, height: 44)
                    .background(Theme.wash(tone, 38), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.brandHeading(24, relativeTo: .title2)).foregroundStyle(Theme.inkStrong)
                    Text(hint).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    if let note { Text(note).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft).padding(.top, 2) }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wash(tone, 16))
            .overlay(alignment: .bottom) { StitchedDivider(lineWidth: 1) }
            content()
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            footer()
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
        .cardShadow()
    }
}

/// One rule of a settings card (web `Rule`): a box washed in its tone (8%, a 1.5 pt edge at
/// 55%), a 28 disc and a Fredoka 18 title, the line that explains it, then its control.
struct SettingsRule<Content: View>: View {
    let icon: String
    let tone: Color
    let title: String
    let hint: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Glyph(icon, size: 16)
                    .foregroundStyle(Theme.inkStrong)
                    .frame(width: 28, height: 28)
                    .background(Theme.wash(tone, 45), in: Circle())
                Text(title).font(.brandHeading(18)).foregroundStyle(Theme.inkStrong)
            }
            Text(hint).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.top, 4)
            VStack(alignment: .leading, spacing: 12) { content() }.padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(tone, 8), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(tone, 55, with: Theme.borderSoft), lineWidth: 1.5))
    }
}

/// A settings card's foot (web: grooming / home visits / stays / hospital settings): "Unsaved
/// changes" on a mango wash with Discard, or "Saved"; the save at the right, both `size="sm"`.
/// `floating`: its own card under the settings (the hospital's one save for two cards).
struct SaveBar: View {
    let dirty: Bool
    let working: Bool
    var saveTitle: String = L("Save settings")
    var floating: Bool = false
    let onDiscard: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if dirty {
                HStack(spacing: 6) {
                    Circle().fill(Theme.mango).frame(width: 8, height: 8)
                    Text(L("Unsaved changes"))
                }
                .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkStrong)
            } else {
                HStack(spacing: 6) {
                    Glyph("check", size: 14).foregroundStyle(Theme.blue)
                    Text(L("Saved"))
                }
                .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 8)
            if dirty { PMButton(L("Discard"), variant: .outline, size: .small, action: onDiscard).disabled(working) }
            PMButton(saveTitle, systemImage: "save", size: .small, isWorking: working, action: onSave)
                .disabled(!dirty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(dirty ? AnyShapeStyle(Theme.wash(Theme.mango, 14)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: floating ? Theme.cardRadius : 0, style: .continuous))
        .overlay {
            if floating {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(dirty ? AnyShapeStyle(Theme.mix(Theme.mango, 55, with: Theme.borderSoft)) : AnyShapeStyle(Theme.borderSoft), lineWidth: 1)
            }
        }
        .overlay(alignment: .top) { if !floating { RowDivider() } }
        .modifier(SaveBarShadow(on: floating))
    }
}

private struct SaveBarShadow: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.cardShadow() } else { content }
    }
}
