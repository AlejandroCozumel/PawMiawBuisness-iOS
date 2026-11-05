//
//  ClientsMovePet.swift
//  PawMiawNegocios
//
//  A pet that has a new family (web: client-closing/move-pet-sheet.tsx):
//  its record with this client is archived and it continues as a new record
//  with the client you choose, which shows the earlier history to read.
//  Only the owner or an admin moves a pet; it is signed and confirmed by
//  typing the pet's name, like archiving.
//

import SwiftUI

struct ClientsMoveTarget: Identifiable, Hashable {
    var id: String { petId }
    let clientId: String
    let clientName: String
    let petId: String
    let name: String
    /// The family it is with reads it in PawMiaw: that link stays behind.
    let linked: Bool
}

private struct ClientsPetMovedResult: Decodable {
    struct Place: Decodable { let clientId: String; let petId: String }
    let movedTo: Place?
    let visitsCancelled: Int?
    let followUpsMoved: Int?
    let invitationsRevoked: Int?
}

/// "Recorded under your name": whose name the change stays under, shown before it is made.
struct ClientsStamp: View {
    @EnvironmentObject private var session: SessionStore
    let signed: Bool

    var body: some View {
        HStack(spacing: 12) {
            Glyph("stamp", size: 16).foregroundStyle(Theme.inkStrong).frame(width: 36, height: 36).background(Theme.surfaceMuted, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Recorded under your name").uppercased()).font(.brandText(10.6, weight: .heavy)).tracking(1.27).foregroundStyle(Theme.inkSoft)
                Text("\(session.user?.name.nonEmpty ?? session.user?.email ?? "—") · \(ClientsMatches.fullDay(DateText.iso(Date())))").font(.brandHeading(16)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                Text(signed ? L("It shows on the record and in its history, with your signature.") : L("It shows on the record and in its history.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.inkSoft, 45, with: Theme.borderSoft), style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
    }
}

struct ClientsMovePetSheet: View {
    let target: ClientsMoveTarget
    /// The new record: its client and pet.
    let onMoved: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var preview: ClientsClosingPreview?
    @State private var previewFailed = false
    @State private var query = ""
    @StateObject private var found = Pager<ClientsClient> { _, _ in Page(items: [], total: 0) }
    @State private var chosen: ClientsClient?
    @State private var note = ""
    @State private var typed = ""
    @State private var savedSignature: SignatureMark?
    @State private var signature = SignatureDraft()
    @State private var saving = false
    @State private var problem: String?

    private var blockers: [String] { (preview?.pets ?? []).flatMap { $0.blockers ?? [] } }
    private var ready: Bool { preview != nil && blockers.isEmpty }
    private var nameMatches: Bool { ClientsText.typedNameMatches(typed, target.name) }

    var body: some View {
        ProviderModal(
            title: LF("Move %@ to another client", target.name),
            subtitle: LF("%1$@ has a new family. Its record with %2$@ is archived and continues with the new client.", target.name, target.clientName),
            systemImage: "arrow-right-left", accent: .mango,
            isDirty: chosen != nil || !note.isEmpty || !typed.isEmpty || signature.isDirty,
            form: form,
            primaryTitle: ready ? (saving ? L("Moving…") : chosen.map { LF("Move to %@", $0.ownerFirstName?.nonEmpty ?? $0.ownerName) } ?? L("Move to another client")) : nil,
            primaryVariant: .destructive,
            isWorking: saving,
            primaryIcon: "arrow-right-left",
            onPrimary: ready ? { submit() } : nil
        ) {
            FormField(label: L("New client"), key: "client", form: form, required: true) { clientPicker }
            whatHappens
            if !blockers.isEmpty {
                NoticeCard(tone: .problem, title: L("It can’t be done yet"), message: blockers.map { ClientsText.blocker($0, name: target.name) }.joined(separator: "\n"))
            }
            if ready {
                PMTextField(L("Note (optional)"), text: $note, key: "note", form: form, prompt: L("e.g. Her sister adopted her"), multiline: true)
                ClientsStamp(signed: true)
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(L("Your signature"), required: true)
                    SignatureCapture(modes: SignatureCaptureMode.savedOrDrawn, draft: $signature, saved: savedSignature, savedHint: L("Your saved signature goes on this record."), label: nil, form: form)
                }
                PMTextField(LF("Type %@ to confirm", target.name), text: $typed, key: "typed", form: form, prompt: target.name, capitalization: .never, required: true)
                if let problem {
                    Text(problem).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.destructive)
                }
            }
        }
        .presentationDetents([.large])
        .task { await loadPreview() }
        .onChange(of: typed) { _, _ in problem = nil }
        .onChange(of: note) { _, _ in problem = nil }
        // The client search's one rule: the server searches from two letters, 250 ms after typing, 20 at a time.
        .debounced(query) { value in
            let q = ClientSearch.query(value)
            found.fetch = { offset, limit in
                guard let q else { return Page(items: [], total: 0) }
                return try await API.get("/provider-clients", query: ["limit": "\(limit)", "offset": "\(offset)", "search": q])
            }
            await found.reload()
        }
    }

    /// What the search found, never the client it is already with.
    private var results: [ClientsClient] { found.items.filter { $0.id != target.clientId } }

    // MARK: Parts

    private func clientLine(_ client: ClientsClient) -> String {
        [client.ownerPhone?.nonEmpty, client.allPets.filter { !$0.isArchived }.map(\.petName).joined(separator: ", ").nonEmpty ?? L("No pets yet")].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var clientPicker: some View {
        if let chosen {
            HStack(spacing: 12) {
                Glyph("user-round", size: 16).foregroundStyle(Theme.inkStrong).frame(width: 36, height: 36).background(Theme.surface, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(chosen.ownerName).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text(clientLine(chosen)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { self.chosen = nil; problem = nil } label: {
                    Text(L("Change")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue).padding(.horizontal, 12).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .disabled(saving)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.wash(Theme.blue, 8), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.blue, lineWidth: 2))
        } else {
            SearchField(prompt: L("Search by name, phone or pet"), text: $query, shape: .field).accessibilityLabel(L("Find the client"))
            if ClientSearch.query(query) != nil {
                if (found.isLoading || !found.loadedOnce) && results.isEmpty {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Searching…")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                } else if results.isEmpty {
                    Text(L("No client matches. Create the client first, then move the pet.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                } else {
                    if let total = found.total {
                        Text((total == 1 ? LF("%@ result", "1") : LF("%@ results", String(total))).uppercased())
                            .font(Theme.text(12)).tracking(1.4).foregroundStyle(Theme.inkSoft)
                    }
                    ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, client in
                            if index > 0 { RowDivider() }
                            Button { chosen = client; form.clear("client") } label: {
                                HStack(spacing: 12) {
                                    Glyph("user-round", size: 16).foregroundStyle(Theme.inkStrong).frame(width: 36, height: 36).background(Theme.surfaceMuted, in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(client.ownerName).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                                        Text(clientLine(client)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onAppear { found.loadMoreIfNeeded(client) }
                        }
                        PagerFooter(pager: found)
                    }
                    }
                    .frame(maxHeight: 320)
                    .scrollBounceBehavior(.basedOnSize)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
            }
        }
    }

    @ViewBuilder
    private var whatHappens: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("What happens").uppercased()).font(.brandText(11.2, weight: .heavy)).tracking(1.34).foregroundStyle(Theme.inkSoft)
            if let data = preview {
                let visits = data.upcomingVisits ?? []
                let reminders = data.openFollowUps ?? 0
                VStack(alignment: .leading, spacing: 8) {
                    line("archive", LF("The record with %@ is archived, with everything written on it.", target.clientName))
                    line("file-clock", chosen.map { LF("A new record starts with %@. It shows the earlier history (notes, vaccines, weights, prescriptions) to read, not to change.", $0.ownerName) } ?? L("A new record starts with the new client. It shows the earlier history (notes, vaccines, weights, prescriptions) to read, not to change."))
                    line("calendar-x-2", visits.isEmpty ? L("No visits still to come.") : visits.count == 1 ? L("1 visit still to come is cancelled:") : LF("%d visits still to come are cancelled:", visits.count), quiet: visits.isEmpty)
                    ForEach(visits.prefix(4)) { visit in
                        (Text(ClientsText.dayTime(visit.startsAt)).bold().foregroundStyle(Theme.inkStrong) + Text(" · \(visit.serviceLabel ?? "")").foregroundStyle(Theme.inkSoft))
                            .font(Theme.text(14)).padding(.leading, 26)
                    }
                    if visits.count > 4 { Text(LF("and %d more", visits.count - 4)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.leading, 26) }
                    line("bell-ring", reminders == 0 ? L("No open reminders to take along.") : reminders == 1 ? LF("1 open reminder goes with %@.", target.name) : LF("%1$d open reminders go with %2$@.", reminders, target.name), quiet: reminders == 0)
                    line("receipt", LF("Bills, payments and signed consents stay with %@.", target.clientName))
                    if target.linked {
                        line("smartphone", LF("The link with %@’s PawMiaw app stays on the archived record. The new record starts without PawMiaw: invite the new family when it is time.", target.clientName))
                    }
                    if (data.invitationsRevoked ?? 0) > 0 {
                        line("mail-x", L("The invitation to link that is still open is revoked: its link stops working."))
                    }
                    line("message-circle-off", visits.isEmpty ? L("Nothing is sent to either family.") : L("Nothing is sent to either family. If a visit was already agreed, let them know yourself."))
                }
            } else if previewFailed {
                Text(L("Could not check what is booked. Close and try again.")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.destructive)
            } else {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Checking what is booked…")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
            }
        }
    }

    private func line(_ icon: String, _ text: String, quiet: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Glyph(icon, size: 16).foregroundStyle(Theme.inkSoft).padding(.top, 2)
            Text(text).font(Theme.text(14)).foregroundStyle(quiet ? Theme.inkSoft : Theme.inkStrong)
        }
    }

    // MARK: Loading and saving

    private func loadPreview() async {
        do {
            preview = try await API.get("/provider-clients/\(target.clientId)/closing-preview", query: ["petId": target.petId])
            previewFailed = false
        } catch {
            previewFailed = true
        }
        savedSignature = (try? await ProfessionalSignature.load()) ?? nil
    }

    private func submit() {
        problem = nil
        let sign = signature.captured(saved: savedSignature)?.json
        guard form.check([
            ("client", chosen == nil ? L("Choose the new client.") : nil),
            ("signature", sign == nil ? L("Your signature is missing. Sign above.") : nil),
            ("typed", nameMatches ? nil : LF("That isn’t the name. Type %@.", target.name)),
        ]), let chosen, let sign else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let result: ClientsPetMovedResult = try await API.post("/provider-client-pets/\(target.petId)/move", body: [
                    "toClientId": chosen.id, "note": note.nonEmpty, "confirmName": typed, "signature": sign,
                ])
                let cancelled = result.visitsCancelled ?? 0, moved = result.followUpsMoved ?? 0
                let parts = [
                    cancelled == 1 ? L("1 visit cancelled") : cancelled > 1 ? LF("%d visits cancelled", cancelled) : nil,
                    moved == 1 ? L("1 reminder went along") : moved > 1 ? LF("%d reminders went along", moved) : nil,
                    (result.invitationsRevoked ?? 0) > 0 ? L("invitation revoked") : nil,
                ].compactMap { $0 }
                let headline = LF("%1$@ is now with %2$@.", target.name, chosen.ownerName)
                Toast.show(parts.isEmpty ? headline : "\(headline) \(parts.joined(separator: " · "))")
                announceDataChanged()
                dismiss()
                if let place = result.movedTo { onMoved(place.clientId, place.petId) }
            } catch {
                problem = refusal(error)
                await loadPreview()
            }
        }
    }

    private func refusal(_ error: Error) -> String {
        guard let api = error as? APIError, let code = api.code else { return L("It could not be moved. Try again.") }
        switch code {
        case "managers_only": return L("Only the owner or an admin can move a pet to another client.")
        case "confirm_name": return LF("That isn’t the name. Type %@.", target.name)
        case "destination_archived": return L("That client is archived. Restore it first.")
        case "same_client": return L("It already belongs to that client.")
        case "client_not_found": return L("That client was not found. Search again.")
        case "already_archived": return L("It was already archived. Reload the page.")
        case "already_deceased": return L("It was already recorded. Reload the page.")
        case "saved_signature_missing":
            savedSignature = nil
            return L("Your saved signature is gone. Draw it.")
        case "signature_required", "signature_missing", "signature_blank": return L("Your signature is missing. Sign above.")
        case "signature_invalid", "signature_too_large": return L("The signature could not be read. Draw it again.")
        case "visit_in_progress", "in_hospital", "on_stay", "stay_booked": return ClientsText.blocker(code, name: target.name)
        default: return L("It could not be moved. Try again.")
        }
    }
}
