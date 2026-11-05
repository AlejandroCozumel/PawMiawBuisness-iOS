//
//  ClientsClosingSheets.swift
//  PawMiawNegocios
//
//  Archiving a client or a pet, recording that a pet died, and the way back
//  (web: client-closing/closing-sheets.tsx). Delete means archive: the sheet
//  says what gets cancelled, asks why, shows whose name it stays under and
//  waits for the record's own name to be typed. A death and a whole client
//  are signed as well: the saved signature, or one drawn here.
//

import SwiftUI

enum ClientsClosingTarget: Identifiable, Hashable {
    case archivePet(clientId: String, petId: String, name: String)
    case petDeath(clientId: String, petId: String, name: String)
    case archiveClient(id: String, name: String, firstName: String, owed: String?)

    var id: String {
        switch self {
        case .archivePet(_, let petId, _): "archive:\(petId)"
        case .petDeath(_, let petId, _): "death:\(petId)"
        case .archiveClient(let id, _, _, _): "client:\(id)"
        }
    }

    var clientId: String {
        switch self {
        case .archivePet(let clientId, _, _), .petDeath(let clientId, _, _): clientId
        case .archiveClient(let id, _, _, _): id
        }
    }

    var petId: String? {
        switch self {
        case .archivePet(_, let petId, _), .petDeath(_, let petId, _): petId
        case .archiveClient: nil
        }
    }

    var name: String {
        switch self {
        case .archivePet(_, _, let name), .petDeath(_, _, let name), .archiveClient(_, let name, _, _): name
        }
    }

    /// What is typed to confirm ("José Luis"); for a client the whole name works too.
    var confirmName: String {
        if case .archiveClient(_, _, let firstName, _) = self { return firstName }
        return name
    }

    var isDeath: Bool { if case .petDeath = self { return true }; return false }
    var isClient: Bool { if case .archiveClient = self { return true }; return false }
}

enum ClientsRestoreTarget: Identifiable, Hashable {
    case pet(id: String, name: String, deceased: Bool)
    case client(id: String, name: String)

    var id: String {
        switch self {
        case .pet(let id, _, _): "pet:\(id)"
        case .client(let id, _): "client:\(id)"
        }
    }

    var name: String {
        switch self {
        case .pet(_, let name, _), .client(_, let name): name
        }
    }
}

struct ClientsClosingSheet: View {
    let target: ClientsClosingTarget
    var onDone: (ClientsClosingResult) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var preview: ClientsClosingPreview?
    @State private var previewFailed = false
    @State private var reason: String?
    @State private var note = ""
    @State private var day = Date()
    @State private var typed = ""
    @State private var savedSignature: SignatureMark?
    @State private var signature = SignatureDraft()
    @State private var saving = false

    private var signs: Bool { target.isDeath || target.isClient }
    private var reasons: [String] { target.isClient ? ["moved", "no_longer_comes", "other_provider", "other"] : ["rehomed", "moved", "no_longer_comes", "other"] }
    private var blocked: [(pet: String, code: String)] {
        (preview?.pets ?? []).flatMap { pet in (pet.blockers ?? []).map { (pet: pet.name ?? target.name, code: $0) } }
    }
    private var ready: Bool { preview != nil && blocked.isEmpty }

    var body: some View {
        ProviderModal(
            title: target.isDeath ? LF("Record that %@ died", target.name) : LF("Archive %@", target.name),
            subtitle: subtitle,
            systemImage: target.isDeath ? "flower-2" : "archive",
            // The web washes a death in grey (ink-soft).
            accent: target.isDeath ? .grey : .pink,
            isDirty: !note.isEmpty || !typed.isEmpty || signature.isDirty,
            form: form,
            primaryTitle: ready ? (saving ? (target.isDeath ? L("Saving…") : L("Archiving…")) : target.isDeath ? L("Record the death") : LF("Archive %@", target.isClient ? target.confirmName : target.name)) : nil,
            primaryVariant: .destructive,
            isWorking: saving,
            primaryIcon: target.isDeath ? "flower-2" : "archive",
            onPrimary: ready ? { submit() } : nil
        ) {
            consequences
            if !blocked.isEmpty {
                NoticeCard(tone: .problem, title: L("It can’t be done yet"), message: blocked.map { ClientsText.blocker($0.code, name: $0.pet) }.joined(separator: "\n"))
            }
            if ready { fields }
        }
        .task { await loadPreview() }
    }

    private var subtitle: String {
        if target.isDeath { return LF("%@’s chart stays as it is. Nothing is sent to the family.", target.name) }
        if target.isClient { return LF("%@ and their pets leave the active lists. Their history and what they owe stay.", target.name) }
        return LF("%@ leaves the active lists. The chart stays, and it can be restored.", target.name)
    }

    @ViewBuilder
    private var consequences: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("What happens").uppercased()).font(.brandText(11.2, weight: .heavy)).tracking(1.34).foregroundStyle(Theme.inkSoft)
            if let data = preview {
                let visits = data.upcomingVisits ?? []
                VStack(alignment: .leading, spacing: 8) {
                    if target.isClient, let pets = data.pets, !pets.isEmpty {
                        consequence("paw-print", pets.count == 1 ? LF("Its pet is archived too: %@.", pets[0].name ?? "") : LF("Their %d pets are archived too: %@.", pets.count, pets.compactMap(\.name).joined(separator: ", ")))
                    }
                    consequence("calendar-x-2", visits.isEmpty ? L("No visits still to come.") : visits.count == 1 ? L("1 visit still to come is cancelled:") : LF("%d visits still to come are cancelled:", visits.count), quiet: visits.isEmpty)
                    ForEach(visits.prefix(4)) { visit in
                        (Text(ClientsText.dayTime(visit.startsAt)).bold().foregroundStyle(Theme.inkStrong)
                         + Text(" · \(visit.serviceLabel ?? "")\(target.isClient ? " · \(visit.petName ?? "")" : "")").foregroundStyle(Theme.inkSoft))
                            .font(Theme.text(14)).padding(.leading, 26)
                    }
                    if visits.count > 4 { Text(LF("and %d more", visits.count - 4)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.leading, 26) }
                    let reminders = data.openFollowUps ?? 0
                    consequence("bell-off", reminders == 0 ? L("No open reminders.") : reminders == 1 ? L("1 open reminder is closed.") : LF("%d open reminders are closed.", reminders), quiet: reminders == 0)
                    if (data.invitationsRevoked ?? 0) > 0 {
                        consequence("mail-x", L("The invitation to link that is still open is revoked: its link stops working."))
                    }
                    if case .archiveClient(_, _, _, let owed?) = target {
                        consequence("circle-dollar-sign", LF("They owe %@. It stays on their account.", owed))
                    }
                    consequence("message-circle-off", target.isDeath ? L("Nothing is sent to the family, and nothing changes in their PawMiaw app.") : !visits.isEmpty ? L("The family gets no message. If a visit was already agreed, let them know yourself.") : L("Nothing new can be booked until it is restored."))
                }
            } else if previewFailed {
                Text(L("Could not check what is booked. Close and try again.")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.destructive)
            } else {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Checking what is booked…")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
            }
        }
    }

    /// One line of what happens (web `Consequence`): a 16 grey icon and the sentence; quiet = grey.
    private func consequence(_ icon: String, _ text: String, quiet: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Glyph(icon, size: 16).foregroundStyle(Theme.inkSoft).padding(.top, 2)
            Text(text).font(Theme.text(14)).foregroundStyle(quiet ? Theme.inkSoft : Theme.inkStrong)
        }
    }

    @ViewBuilder
    private var fields: some View {
        if target.isDeath {
            DateTimeField(label: L("Day it happened"), date: $day, zone: .current, max: Date(), components: [.date], key: "day", form: form, required: true)
        } else {
            FormField(label: L("Reason"), key: "reason", form: form, required: true) {
                FlowLayout(spacing: 8) {
                    ForEach(reasons, id: \.self) { value in
                        FilterChip(title: ClientsText.closingReason(value) ?? value, isSelected: reason == value, tone: Theme.blue) { reason = value; form.clear("reason") }
                    }
                }
            }
        }
        PMTextField(reason == "other" && !target.isDeath ? L("Note") : L("Note (optional)"), text: $note, key: "note", form: form, prompt: target.isDeath ? L("e.g. The family called to let us know") : L("e.g. Moved to Monterrey"), multiline: true, required: reason == "other" && !target.isDeath, lines: 2...6)
        // The stamp: whose name the change stays under, shown before it is made.
        ClientsStamp(signed: signs)
        if signs {
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(L("Your signature"), required: true)
                SignatureCapture(modes: SignatureCaptureMode.savedOrDrawn, draft: $signature, saved: savedSignature, savedHint: L("Your saved signature goes on this record."), label: nil, form: form)
            }
        }
        PMTextField(LF("Type %@ to confirm", target.confirmName), text: $typed, key: "typed", form: form, prompt: target.confirmName, capitalization: .never, required: true)
    }

    private func loadPreview() async {
        let path = "/provider-clients/\(target.clientId)/closing-preview"
        do {
            preview = try await API.get(path, query: ["petId": target.petId])
            previewFailed = false
        } catch {
            previewFailed = true
        }
        if signs { savedSignature = (try? await ProfessionalSignature.load()) ?? nil }
    }

    private func submit() {
        let nameMatches = ClientsText.typedNameMatches(typed, target.confirmName) || (target.isClient && ClientsText.typedNameMatches(typed, target.name))
        let sign = signs ? signature.captured(saved: savedSignature)?.json : nil
        guard form.check([
            ("reason", !target.isDeath && reason == nil ? L("Choose a reason.") : nil),
            ("note", !target.isDeath && reason == "other" && note.nonEmpty == nil ? L("Say why, in a few words.") : nil),
            ("signature", signs && sign == nil ? L("Your signature is missing. Sign above.") : nil),
            ("typed", nameMatches ? nil : LF("That isn’t the name. Type %@.", target.confirmName)),
        ]) else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let result: ClientsClosingResult
                switch target {
                case .petDeath(_, let petId, _):
                    result = try await API.post("/provider-client-pets/\(petId)/death", body: ["diedOn": DateText.dayKey(day, zone: .current), "note": note.nonEmpty, "confirmName": typed, "signature": sign])
                case .archivePet(_, let petId, _):
                    result = try await API.post("/provider-client-pets/\(petId)/archive", body: ["reason": reason, "note": note.nonEmpty, "confirmName": typed])
                case .archiveClient(let id, _, _, _):
                    result = try await API.post("/provider-clients/\(id)/archive", body: ["reason": reason, "note": note.nonEmpty, "confirmName": typed, "signature": sign])
                }
                let parts = [
                    (result.visitsCancelled ?? 0) == 1 ? L("1 visit cancelled") : (result.visitsCancelled ?? 0) > 1 ? LF("%d visits cancelled", result.visitsCancelled ?? 0) : nil,
                    (result.followUpsCancelled ?? 0) == 1 ? L("1 reminder closed") : (result.followUpsCancelled ?? 0) > 1 ? LF("%d reminders closed", result.followUpsCancelled ?? 0) : nil,
                    (result.invitationsRevoked ?? 0) > 0 ? L("invitation revoked") : nil,
                ].compactMap { $0 }
                let headline = target.isDeath ? LF("The death of %@ is recorded.", target.name) : LF("%@ is archived.", target.name)
                Toast.show(parts.isEmpty ? headline : "\(headline) \(parts.joined(separator: " · "))")
                announceDataChanged()
                onDone(result)
                dismiss()
            } catch {
                refusal(error)
                await loadPreview()
            }
        }
    }

    private func refusal(_ error: Error) {
        guard let api = error as? APIError, let code = api.code else { form.apply(error); return }
        switch code {
        case "confirm_name": _ = form.check([("typed", LF("That isn’t the name. Type %@.", target.confirmName))])
        case "note_required": _ = form.check([("note", L("Say why, in a few words."))])
        case "invalid_day": _ = form.check([("day", L("Choose the day it happened: today or earlier."))])
        case "already_archived": Toast.error(L("It was already archived. Reload the page."))
        case "already_deceased": Toast.error(L("It was already recorded. Reload the page."))
        case "saved_signature_missing":
            savedSignature = nil
            _ = form.check([("signature", L("Your saved signature is gone. Draw it."))])
        case "signature_required", "signature_missing", "signature_blank": _ = form.check([("signature", L("Your signature is missing. Sign above."))])
        case "signature_invalid", "signature_too_large": _ = form.check([("signature", L("The signature could not be read. Draw it again."))])
        default: Toast.error(api.message.nonEmpty ?? (target.isDeath ? L("It could not be saved. Try again.") : L("It could not be archived. Try again.")))
        }
    }
}

/// Undo an archive or a recorded death. Reminders open again; cancelled visits stay cancelled.
struct ClientsRestoreSheet: View {
    let target: ClientsRestoreTarget
    var onDone: (ClientsClosingResult) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        ProviderModal(title: LF("Restore %@?", target.name), systemImage: "rotate-ccw", accent: .aqua, primaryTitle: L("Restore"), isWorking: working, primaryIcon: "rotate-ccw") {
            restore()
        } content: {
            Text(message).font(Theme.bodyFont).foregroundStyle(Theme.inkStrong)
        }
        .presentationDetents([.medium])
    }

    private var message: String {
        switch target {
        case .client(_, let name): LF("%@ goes back to the active lists with the pets that were archived along with the client, and their reminders open again. The visits that were cancelled don’t come back: book them again.", name)
        case .pet(_, let name, true): LF("The record of the death is removed, %@ goes back to the active lists and the reminders that were closed open again. The visits that were cancelled don’t come back: book them again.", name)
        case .pet(_, let name, false): LF("%@ goes back to the active lists and the reminders that were closed open again. The visits that were cancelled don’t come back: book them again.", name)
        }
    }

    private func restore() {
        working = true
        Task {
            defer { working = false }
            do {
                let result: ClientsClosingResult
                switch target {
                case .pet(let id, _, _): result = try await API.post("/provider-client-pets/\(id)/restore")
                case .client(let id, _): result = try await API.post("/provider-clients/\(id)/restore")
                }
                let reopened = result.followUpsReopened ?? 0
                let extra = reopened == 1 ? L("1 reminder open again") : reopened > 1 ? LF("%d reminders open again", reopened) : nil
                Toast.show([LF("%@ is back on the active lists.", target.name), extra].compactMap { $0 }.joined(separator: " "))
                announceDataChanged()
                onDone(result)
                dismiss()
            } catch {
                let code = (error as? APIError)?.code
                Toast.error(
                    code == "client_archived" ? L("Restore the client first.")
                        : code == "pet_moved" ? L("It moved to another client. Move it back from its new record.")
                        : code == "recorded_at_hospital" ? L("This death was recorded at the hospital. Undo it from the hospitalization.")
                        : L("It could not be restored. Try again.")
                )
                dismiss()
            }
        }
    }
}

/// The stamp on an archived client or pet (web `ClosingBanner`): a dashed
/// card on the muted surface, a 40 disc with the flower or the box, what it
/// is now, who did it, when and why — and the way back.
struct ClientsClosingBanner: View {
    let name: String
    let stamp: ClientsClosingStamp?
    let deceasedAt: String?
    let hint: String?
    let onRestore: (() -> Void)?

    var body: some View {
        let died = deceasedAt != nil
        let reason = stamp?.reason == "deceased" ? nil : ClientsText.closingReason(stamp?.reason)
        let signed: String? = stamp?.at.map { at in
            if let by = stamp?.byName?.nonEmpty {
                return died ? LF("Recorded by %@ on %@", by, ClientsText.shortDay(at)) : LF("Archived by %@ on %@", by, ClientsText.shortDay(at))
            }
            return died ? LF("Recorded on %@", ClientsText.shortDay(at)) : LF("Archived on %@", ClientsText.shortDay(at))
        }
        let line = [signed, reason.map { LF("Reason: %@", $0) }].compactMap { $0 }.joined(separator: " · ")
        let off = L("Off the active lists. Nothing new can be booked; everything recorded stays.")
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Glyph(died ? "flower-2" : "archive", size: 20)
                    .foregroundStyle(Theme.inkStrong)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface, in: Circle())
                    .shadow(color: Theme.navy.opacity(0.08), radius: 1.5, y: 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(died ? LF("%@ died on %@", name, ClientsText.shortDay(deceasedAt)) : LF("%@ is archived", name))
                        .font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                    Text(line.nonEmpty ?? off).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    if let note = stamp?.note?.nonEmpty { Text("“\(note)”").font(Theme.text(14)).foregroundStyle(Theme.inkStrong) }
                    if !line.isEmpty { Text(off).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                    if let hint { Text(hint).font(Theme.text(14)).foregroundStyle(Theme.inkStrong) }
                }
            }
            if let onRestore { PMButton(L("Restore"), systemImage: "rotate-ccw", variant: .outline, size: .compact, action: onRestore) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(Theme.surfaceMuted, 60), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(Theme.mix(Theme.inkSoft, 45, with: Theme.borderSoft), style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
    }
}
