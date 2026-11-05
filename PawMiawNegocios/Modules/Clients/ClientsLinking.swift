//
//  ClientsLinking.swift
//  PawMiawNegocios
//
//  Two records that are one family or one pet (web: linking/match-review-
//  sheet.tsx, merge-client-sheet.tsx, merge-pet-sheet.tsx, unlink-pet-
//  sheet.tsx, linking-model.ts, use-provider-linking.ts): the possible
//  matches to review, combining two clients or two pets (the one you start
//  from goes, the one you pick stays), and unlinking a pet from its family.
//

import SwiftUI

// MARK: - Shapes

/// One side of a suggestion: a client or a pet (the fields of both, all optional).
struct ClientsSuggestedRecord: Codable, Hashable {
    let id: String
    let name: String?
    // A client.
    let email: String?
    let phone: String?
    let linked: Bool?
    let linkedAccountName: String?
    let pets: [String]?
    let createdAt: String?
    // A pet.
    let species: String?
    let breed: String?
    let sex: String?
    let birthDate: String?
    let weightGrams: Double?
    let microchipNumber: String?
    let photoUrl: String?
    let clientId: String?
    let clientName: String?
}

struct ClientsMatchSuggestion: Codable, Identifiable, Hashable {
    let id: String
    /// "client" or "pet".
    let kind: String
    let score: Double?
    let reasons: [String]?
    let origin: String?
    let status: String?
    let createdAt: String?
    /// The record that would be combined away.
    let source: ClientsSuggestedRecord
    /// The record that stays.
    let target: ClientsSuggestedRecord

    var isPet: Bool { kind == "pet" }
}

struct ClientsMergeResult: Decodable {
    let status: String?
    let targetId: String?
    /// For two pets: the client of the pet that stays.
    let providerClientId: String?
}

private struct ClientsUnlinkResult: Decodable {
    let status: String?
    let clientUnlinked: Bool?
}

/// The match suggestions and their words (linking-model.ts, linking-copy.ts).
enum ClientsMatches {
    static func load() async -> [ClientsMatchSuggestion] {
        let all: [ClientsMatchSuggestion] = (try? await API.get("/provider-match-suggestions")) ?? []
        return all.filter { ($0.status ?? "open") == "open" }
    }

    /// The open suggestions that touch a client: as one of the two clients, or through one of its pets.
    static func related(_ suggestions: [ClientsMatchSuggestion], clientId: String) -> [ClientsMatchSuggestion] {
        suggestions.filter { s in
            s.isPet ? (s.source.clientId == clientId || s.target.clientId == clientId) : (s.source.id == clientId || s.target.id == clientId)
        }
    }

    /// The other side's name, as the banner says it.
    static func otherSideName(_ s: ClientsMatchSuggestion, clientId: String) -> String {
        if !s.isPet { return (s.source.id == clientId ? s.target.name : s.source.name) ?? "—" }
        let mineIsSource = s.source.clientId == clientId
        if s.source.clientId == clientId && s.target.clientId == clientId {
            return "\(s.source.name ?? "—") / \(s.target.name ?? "—")"
        }
        let other = mineIsSource ? s.target : s.source
        return "\(other.name ?? "—") (\(other.clientName ?? "—"))"
    }

    static func reason(_ code: String) -> String {
        switch code {
        case "same_email": L("Same email")
        case "same_phone": L("Same phone")
        case "similar_name": L("Similar name")
        case "same_name": L("Same name")
        case "same_household": L("Same family on PawMiaw")
        case "family_confirmed": L("The family said it’s the same pet")
        case "same_microchip": L("Same microchip")
        case "same_breed": L("Same breed")
        case "same_birth_date": L("Same birth date")
        default: code.replacingOccurrences(of: "_", with: " ")
        }
    }

    static func origin(_ code: String?) -> String? {
        switch code {
        case "family_connected": L("Found when the family connected from PawMiaw")
        case "invitation_accepted": L("Found when the family accepted an invitation")
        case "clients_combined": L("Found after combining two clients")
        default: nil
        }
    }

    /// A refusal from the linking routes, in the reader's words.
    static func errorText(_ error: Error) -> String {
        guard let api = error as? APIError else { return L("Something went wrong. Try again.") }
        switch api.code {
        case "not_found": return L("Not found")
        case "closed": return L("This suggestion was already answered")
        case "same": return L("Choose a different record to combine with")
        case "walk_in": return L("The walk-in client cannot be combined")
        case "different_households": return L("They are linked to different PawMiaw families")
        case "different_household_pets": return L("They are linked to different pets in PawMiaw")
        case "not_linked": return L("This pet is not linked to PawMiaw")
        default: break
        }
        if api.status == 403 { return L("You do not have permission to change clients") }
        return api.message.nonEmpty ?? L("Something went wrong. Try again.")
    }

    /// Accents, case and punctuation left out, spaces collapsed.
    static func normalized(_ value: String?) -> String {
        let plain = (value ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        return plain.map { $0.isLetter || $0.isNumber ? String($0) : " " }.joined().split(separator: " ").joined(separator: " ")
    }

    static func lastTenDigits(_ phone: String?) -> String { String((phone ?? "").filter(\.isNumber).suffix(10)) }

    /// "12 kg", "4.5 kg": the web's pet weight.
    static func weight(_ grams: Double?) -> String? {
        guard let grams, grams > 0 else { return nil }
        let kilograms = grams / 1000
        let text = kilograms >= 10 ? String(format: "%.0f", kilograms) : String(format: "%.1f", kilograms).replacingOccurrences(of: ".0", with: "")
        return "\(text) kg"
    }

    /// "3 oct 2026": the day, month and year.
    static func fullDay(_ iso: String?) -> String {
        guard let date = DateText.parse(iso.map { $0.count == 10 ? "\($0)T12:00:00" : $0 }) ?? DateText.parse(iso) else { return "—" }
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = Workspace.shared.timeZone
        f.setLocalizedDateFormatFromTemplate("dMMMyyyy")
        return f.string(from: date)
    }
}

/// "Stays" / "Moves into the other and goes": the two sides of a combine, side by side (stacked on a phone).
private struct ClientsMergeSide<Body: View>: View {
    let stays: Bool
    @ViewBuilder let content: () -> Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((stays ? L("Stays@merge") : L("Moves into the other and goes")).uppercased())
                .font(.brandText(10.6, weight: .heavy)).tracking(1.27).foregroundStyle(stays ? Theme.blue : Theme.inkSoft)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(stays ? AnyShapeStyle(Theme.wash(Theme.blue, 5)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous)
                .strokeBorder(stays ? Theme.blue : Theme.borderSoft, style: StrokeStyle(lineWidth: 2, dash: stays ? [] : [6, 5]))
        )
    }
}

/// The two sides with an arrow between them: down on a phone, right on a wide screen.
private struct ClientsMergePair<Source: View, Target: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ViewBuilder let source: () -> Source
    @ViewBuilder let target: () -> Target

    var body: some View {
        if sizeClass == .regular {
            HStack(alignment: .top, spacing: 8) {
                source()
                arrow("arrow-right").frame(maxHeight: .infinity)
                target()
            }
        } else {
            VStack(spacing: 6) {
                source()
                arrow("arrow-down")
                target()
            }
        }
    }

    /// The 32 disc between the two sides (web: a bordered circle with the arrow).
    private func arrow(_ icon: String) -> some View {
        Glyph(icon, size: 16).foregroundStyle(Theme.inkSoft)
            .frame(width: 32, height: 32)
            .background(Theme.surface, in: Circle())
            .overlay(Circle().strokeBorder(Theme.borderSoft, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// A bulleted line of "What happens".
private struct ClientsWhatHappensLine: View {
    let text: String
    var tint: Color = Theme.coral

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(tint).frame(width: 6, height: 6).offset(y: -2)
            Text(text).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
        }
    }
}

/// The name of a record with its face and the link to PawMiaw.
private struct ClientsMergeHeading: View {
    let name: String
    var photoURL: String? = nil
    var species: String? = nil
    var isPet = false
    let linked: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isPet {
                PetAvatar(name: name, species: species, photoURL: photoURL, size: 40)
            } else {
                Avatar(name: name, imageURL: photoURL, size: 40)
            }
            Text(name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(2)
            if linked {
                Glyph("link-2", size: 14).foregroundStyle(Theme.blue)
                    .frame(width: 28, height: 28)
                    .background(Theme.wash(Theme.blue, 14), in: Circle())
                    .accessibilityLabel(L("Linked to PawMiaw"))
            }
        }
    }
}

// MARK: - Possible matches

struct ClientsMatchReviewSheet: View {
    let suggestions: [ClientsMatchSuggestion]
    let canEdit: Bool
    var subtitle: String = L("Records that may be the same family or the same pet. Nothing is combined until you say so.")
    /// After a combine: the suggestion and the record that stayed.
    var onMerged: (ClientsMatchSuggestion, String) -> Void = { _, _ in }
    /// After any answer (to read the list again).
    var onAnswered: () async -> Void = {}

    @State private var answered: Set<String> = []
    @State private var working: String?

    var body: some View {
        ProviderModal(title: L("Possible matches"), subtitle: subtitle, systemImage: "git-merge", accent: .coral, isWorking: working != nil, cancelTitle: L("Close")) {
            let open = suggestions.filter { !answered.contains($0.id) }
            if open.isEmpty {
                EmptyState(systemImage: "circle-check", title: L("Nothing to review"), message: L("When two records look like the same family or pet, they show up here."), accent: Theme.lime)
            } else {
                ForEach(open) { suggestion in card(suggestion) }
            }
        }
        .presentationDetents([.large])
    }

    /// One pair (web `MatchCard`): "¿Mismo cliente?" with why on a coral band,
    /// the two sides with the arrow, what combining moves, the two answers.
    private func card(_ s: ClientsMatchSuggestion) -> some View {
        Card(padding: 0, spacing: 0) {
            FlowLayout(spacing: 8) {
                HStack(spacing: 6) {
                    Glyph(s.isPet ? "paw-print" : "users-round", size: 16)
                    Text(s.isPet ? L("Same pet?") : L("Same client?"))
                }
                .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                ForEach(s.reasons ?? [], id: \.self) { Chip(text: ClientsMatches.reason($0), tone: .info, icon: "check") }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wash(Theme.coral, 8))
            RowDivider()
            ClientsMergePair {
                ClientsMergeSide(stays: false) { column(s, s.source, other: s.target) }
            } target: {
                ClientsMergeSide(stays: true) { column(s, s.target, other: s.source) }
            }
            .padding(16)
            RowDivider()
            VStack(alignment: .leading, spacing: 12) {
                let source = s.source.name ?? "—", target = s.target.name ?? "—"
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.isPet
                         ? LF("Combining moves %1$@’s visits, records, invoices, stays, reminders, notes and history to %2$@. %1$@ goes.", source, target)
                         : LF("Combining moves %1$@’s pets, visits, invoices and payments, stays, reminders, notes and history to %2$@. %1$@ goes.", source, target))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    if let origin = ClientsMatches.origin(s.origin) {
                        Text(origin).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
                if canEdit {
                    VStack(spacing: 8) {
                        PMButton(L("Yes, combine"), systemImage: "git-merge", size: .compact, fullWidth: true, isWorking: working == "merge:\(s.id)") { merge(s) }
                            .disabled(working != nil)
                        PMButton(L("No, it’s someone else"), systemImage: "x", variant: .outline, size: .compact, fullWidth: true, isWorking: working == "dismiss:\(s.id)") { dismissPair(s) }
                            .disabled(working != nil)
                    }
                } else {
                    Text(L("Someone who can edit clients can answer this.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func column(_ s: ClientsMatchSuggestion, _ record: ClientsSuggestedRecord, other: ClientsSuggestedRecord) -> some View {
        ClientsMergeHeading(name: record.name ?? "—", photoURL: s.isPet ? record.photoUrl : nil, species: record.species, isPet: s.isPet, linked: record.linked == true)
        ForEach(rows(s, record, other: other), id: \.0) { row in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.0).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).frame(width: 84, alignment: .leading)
                Text(row.1.nonEmpty ?? "—").font(Theme.text(14, weight: .semibold)).foregroundStyle(row.1.nonEmpty == nil ? Theme.inkSoft : Theme.inkStrong)
                if row.2 && row.1.nonEmpty != nil {
                    Glyph("check", size: 14).foregroundStyle(Theme.blue).accessibilityLabel(L("Same on both"))
                }
            }
        }
    }

    /// Label, value and "same on both" for each line of a side.
    private func rows(_ s: ClientsMatchSuggestion, _ r: ClientsSuggestedRecord, other o: ClientsSuggestedRecord) -> [(String, String, Bool)] {
        if s.isPet {
            let chip = { (value: String?) in (value ?? "").filter { !$0.isWhitespace } }
            return [
                (L("Species"), ClientsText.species(r.species), r.species != nil && r.species == o.species),
                (L("Breed"), r.breed ?? "", r.breed?.nonEmpty != nil && o.breed?.nonEmpty != nil && ClientsMatches.normalized(r.breed) == ClientsMatches.normalized(o.breed)),
                (L("Born"), r.birthDate.map { ClientsMatches.fullDay($0) } ?? "", r.birthDate?.nonEmpty != nil && r.birthDate == o.birthDate),
                (L("Weight"), ClientsMatches.weight(r.weightGrams) ?? "", false),
                (L("Microchip"), r.microchipNumber ?? "", r.microchipNumber?.nonEmpty != nil && o.microchipNumber?.nonEmpty != nil && chip(r.microchipNumber) == chip(o.microchipNumber)),
                (L("Client"), r.clientName ?? "", r.clientId != nil && r.clientId == o.clientId),
                (L("PawMiaw"), r.linked == true ? L("Linked@pet") : L("Not linked@pet"), false),
            ]
        }
        let email = { (value: String?) in (value ?? "").trimmingCharacters(in: .whitespaces).lowercased() }
        return [
            (L("Email"), r.email ?? "", r.email?.nonEmpty != nil && o.email?.nonEmpty != nil && email(r.email) == email(o.email)),
            (L("Phone"), r.phone ?? "", r.phone?.nonEmpty != nil && o.phone?.nonEmpty != nil && ClientsMatches.lastTenDigits(r.phone) == ClientsMatches.lastTenDigits(o.phone)),
            (L("Pets"), (r.pets ?? []).joined(separator: ", "), false),
            (L("PawMiaw"), r.linked == true ? (r.linkedAccountName?.nonEmpty.map { LF("Linked · %@", $0) } ?? L("Linked")) : L("Not linked"), false),
            (L("Added"), ClientsMatches.fullDay(r.createdAt), false),
        ]
    }

    private func merge(_ s: ClientsMatchSuggestion) {
        working = "merge:\(s.id)"
        Task {
            defer { working = nil }
            do {
                let result: ClientsMergeResult = try await API.post("/provider-match-suggestions/\(s.id)/merge")
                answered.insert(s.id)
                Toast.show(LF("Combined. %@ keeps everything.", s.target.name ?? ""))
                announceDataChanged()
                await onAnswered()
                onMerged(s, result.targetId ?? s.target.id)
            } catch {
                Toast.error(ClientsMatches.errorText(error))
            }
        }
    }

    private func dismissPair(_ s: ClientsMatchSuggestion) {
        working = "dismiss:\(s.id)"
        Task {
            defer { working = nil }
            do {
                let _: EmptyResponse = try await API.post("/provider-match-suggestions/\(s.id)/dismiss")
                answered.insert(s.id)
                Toast.show(L("Kept apart. We won’t suggest this pair again."))
                await onAnswered()
            } catch {
                Toast.error(ClientsMatches.errorText(error))
            }
        }
    }
}

/// "Posible duplicado": the client page's banner for its open suggestions.
struct ClientsMatchBanner: View {
    let suggestions: [ClientsMatchSuggestion]
    let clientId: String
    let canEdit: Bool
    let onReview: () -> Void

    var body: some View {
        let names = suggestions.map { ClientsMatches.otherSideName($0, clientId: clientId) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        Card(padding: 14, tint: Theme.coral) {
            HStack(alignment: .top, spacing: 10) {
                Glyph("git-merge", size: 16).foregroundStyle(Theme.inkStrong).padding(.top, 2)
                (Text(L("Possible duplicate:")).bold() + Text(" \(names.joined(separator: " · "))"))
                    .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                Spacer(minLength: 0)
            }
            PMButton(canEdit ? L("Review") : L("See them"), variant: .outline, size: .compact, action: onReview)
        }
    }
}

// MARK: - Combine with another client

struct ClientsMergeClientSheet: View {
    let client: ClientsClient
    /// The client that stayed.
    let onMerged: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @StateObject private var pager = Pager<ClientsClient> { _, _ in Page(items: [], total: 0) }
    @State private var picked: ClientsClient?
    @State private var confirming = false
    @State private var saving = false

    /// Every other client (not this one), as the server found them.
    private var results: [ClientsClient] { pager.items.filter { $0.id != client.id } }

    var body: some View {
        let target = picked?.ownerName ?? ""
        ProviderModal(
            title: confirming ? LF("Combine %@ into %@?", client.ownerName, target) : L("Combine with another client"),
            subtitle: confirming ? L("Check what moves before you combine.") : LF("Pick the record that stays. %@ moves into it.", client.ownerName),
            systemImage: "git-merge", accent: .coral,
            isDirty: picked != nil,
            primaryTitle: confirming ? L("Combine") : L("Continue"),
            primaryVariant: confirming ? .destructive : .primary,
            isWorking: saving,
            onBack: confirming ? { confirming = false } : nil,
            primaryIcon: confirming ? "git-merge" : nil,
            onPrimary: picked == nil ? nil : { if confirming { merge() } else { confirming = true } }
        ) {
            if confirming, let picked { confirmStep(picked) } else { pickStep }
        }
        .presentationDetents([.large])
        // The client search's one rule: the server searches from two letters, 250 ms after typing, 20 at a time.
        .debounced(query) { value in
            let q = ClientSearch.query(value)
            pager.fetch = { offset, limit in
                try await API.get("/provider-clients", query: ["limit": "\(limit)", "offset": "\(offset)", "search": q])
            }
            await pager.reload()
        }
    }

    @ViewBuilder
    private var pickStep: some View {
        SearchField(prompt: L("Client, pet, email or phone"), text: $query, shape: .field)
            .accessibilityLabel(L("Search clients"))
        if !pager.loadedOnce && pager.isLoading {
            LoadingState()
        } else if let error = pager.error, results.isEmpty {
            ErrorState(message: error) { await pager.reload() }
        } else if results.isEmpty {
            let searched = ClientSearch.query(query)
            EmptyState(systemImage: searched == nil ? "users-round" : "search", title: searched.map { LF("No client matches “%@”", $0) } ?? L("No other clients yet."), accent: Theme.lime)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(results) { other in
                    row(other).onAppear { pager.loadMoreIfNeeded(other) }
                }
                PagerFooter(pager: pager)
            }
            .accessibilityLabel(L("Clients"))
        }
    }

    private func blocked(_ other: ClientsClient) -> Bool {
        guard let mine = client.householdId?.nonEmpty, let theirs = other.householdId?.nonEmpty else { return false }
        return mine != theirs
    }

    private func row(_ other: ClientsClient) -> some View {
        let isBlocked = blocked(other)
        let selected = picked?.id == other.id
        let line = [other.ownerEmail?.nonEmpty ?? other.ownerPhone?.nonEmpty, other.allPets.filter { !$0.isArchived }.map(\.petName).joined(separator: ", ").nonEmpty]
            .compactMap { $0 }.joined(separator: " · ").nonEmpty ?? L("No contact details yet")
        return Button {
            picked = selected ? nil : other
        } label: {
            HStack(spacing: 12) {
                Avatar(name: other.ownerName, imageURL: other.photoUrl, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(other.ownerName).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        if other.isLinked { Glyph("link-2", size: 14).foregroundStyle(Theme.blue).accessibilityLabel(L("Linked to PawMiaw")) }
                    }
                    Text(line).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                    if isBlocked { Text(L("Linked to a different PawMiaw family")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.destructive) }
                }
                Spacer(minLength: 0)
                Tick(on: selected, style: .choice)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selected ? AnyShapeStyle(Theme.wash(Theme.blue, 8)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(selected ? Theme.blue : Theme.borderSoft, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(isBlocked)
        .opacity(isBlocked ? 0.55 : 1)
        .simultaneousGesture(TapGesture(count: 2).onEnded { if !isBlocked { picked = other; confirming = true } })
    }

    @ViewBuilder
    private func confirmStep(_ picked: ClientsClient) -> some View {
        ClientsMergePair {
            ClientsMergeSide(stays: false) { card(client) }
        } target: {
            ClientsMergeSide(stays: true) { card(picked) }
        }
        ModalSection(title: L("What happens")) {
            VStack(alignment: .leading, spacing: 8) {
                ClientsWhatHappensLine(text: LF("%1$@ stays. Its pets, visits, invoices and payments, stays, reminders, notes and history are joined by %2$@’s.", picked.ownerName, client.ownerName))
                ClientsWhatHappensLine(text: LF("Contact details %1$@ is missing are filled in from %2$@, and the notes are joined.", picked.ownerName, client.ownerName))
                ClientsWhatHappensLine(text: LF("%@’s record goes. This can’t be undone.", client.ownerName))
                ClientsWhatHappensLine(text: L("Two clients linked to different PawMiaw families can’t be combined."))
            }
        }
    }

    @ViewBuilder
    private func card(_ c: ClientsClient) -> some View {
        ClientsMergeHeading(name: c.ownerName, photoURL: c.photoUrl, linked: c.isLinked)
        ForEach([c.ownerEmail?.nonEmpty, c.ownerPhone?.nonEmpty, c.allPets.filter { !$0.isArchived }.map(\.petName).joined(separator: ", ").nonEmpty].compactMap { $0 }, id: \.self) { line in
            Text(line).font(Theme.text(13)).foregroundStyle(Theme.inkSoft)
        }
    }

    private func merge() {
        guard let picked else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let result: ClientsMergeResult = try await API.post("/provider-clients/\(client.id)/merge", body: ["intoClientId": picked.id])
                Toast.show(LF("Combined into %@.", picked.ownerName))
                announceDataChanged()
                dismiss()
                onMerged(result.targetId ?? picked.id)
            } catch {
                Toast.error(ClientsMatches.errorText(error))
            }
        }
    }
}

// MARK: - Combine with another pet

/// The pet a combine starts from (it goes).
struct ClientsMergePetSource: Identifiable, Hashable {
    var id: String { petId }
    let clientId: String
    let clientName: String
    let petId: String
    let name: String
    let species: String?
    let breed: String?
    let photoUrl: String?
    let linked: Bool
    /// The family pet it is linked to.
    let householdPetId: String?
    let details: String
}

private struct ClientsPetChoice: Identifiable, Hashable {
    let id: String
    let name: String
    let species: String?
    let breed: String?
    let photoUrl: String?
    let clientId: String
    let clientName: String
    let linked: Bool
    let householdPetId: String?
    let archived: Bool
    let details: String
}

private struct ClientsDirectoryPet: Decodable, Identifiable {
    let id: String
    let petName: String
    let petSpecies: String?
    let petBreed: String?
    let photoUrl: String?
    let status: String?
    let linked: Bool?
    let client: ClientsRowClient
    let createdAt: String?
}

private struct ClientsPetDates: Decodable {
    struct Pet: Decodable { let id: String; let createdAt: String? }
    let pets: [Pet]?
}

enum ClientsPetDetails {
    /// What tells two pets with one name apart: its weight, its chip, when it was added.
    static func of(_ pet: ClientsPet, createdAt: String?) -> String {
        [
            ClientsMatches.weight(pet.weight),
            pet.microchipNumber?.nonEmpty.map { LF("Chip ··%@", String($0.suffix(6))) },
            createdAt.map { LF("Added %@", ClientsMatches.fullDay($0)) },
        ].compactMap { $0 }.joined(separator: " · ")
    }
}

struct ClientsMergePetSheet: View {
    let source: ClientsMergePetSource
    /// The client's other pets (this one is left out here).
    let ownPets: [ClientsPet]
    let canSearchOthers: Bool
    /// The client and the pet that stayed.
    let onMerged: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @StateObject private var directory = Pager<ClientsDirectoryPet> { _, _ in Page(items: [], total: 0) }
    @State private var dates: [String: String] = [:]
    @State private var picked: ClientsPetChoice?
    @State private var confirming = false
    @State private var saving = false

    private var own: [ClientsPetChoice] {
        ownPets.filter { $0.id != source.petId }.map { pet in
            ClientsPetChoice(id: pet.id, name: pet.petName, species: pet.petSpecies, breed: pet.petBreed, photoUrl: pet.photoUrl, clientId: source.clientId, clientName: source.clientName, linked: pet.isLinked, householdPetId: pet.petId, archived: pet.isArchived, details: ClientsPetDetails.of(pet, createdAt: dates[pet.id]))
        }
    }

    var body: some View {
        ProviderModal(
            title: confirming ? LF("Combine %@ into %@?", source.name, picked?.name ?? "") : L("Combine with another pet"),
            subtitle: confirming ? L("Check what moves before you combine.") : LF("Pick the pet that stays. %@ moves into it.", source.name),
            systemImage: "git-merge", accent: .coral,
            isDirty: picked != nil,
            primaryTitle: confirming ? L("Combine") : L("Continue"),
            primaryVariant: confirming ? .destructive : .primary,
            isWorking: saving,
            onBack: confirming ? { confirming = false } : nil,
            primaryIcon: confirming ? "git-merge" : nil,
            onPrimary: picked == nil ? nil : { if confirming { merge() } else { confirming = true } }
        ) {
            if confirming, let picked { confirmStep(picked) } else { pickStep }
        }
        .presentationDetents([.large])
        .task {
            if let answer: ClientsPetDates = try? await API.get("/provider-clients/\(source.clientId)") {
                dates = Dictionary((answer.pets ?? []).compactMap { pet in pet.createdAt.map { (pet.id, $0) } }, uniquingKeysWith: { a, _ in a })
            }
        }
        // The search's one rule: the server searches from two letters, 250 ms after typing, 20 at a time.
        .debounced(query) { value in
            guard canSearchOthers, let q = ClientSearch.query(value) else {
                directory.fetch = { _, _ in Page(items: [], total: 0) }
                await directory.reload()
                return
            }
            directory.fetch = { offset, limit in
                try await API.get("/provider-directory/pets", query: ["limit": "\(limit)", "offset": "\(offset)", "search": q])
            }
            await directory.reload()
        }
    }

    /// Other clients' pets the search found (never this client's own).
    private var others: [(entry: ClientsDirectoryPet, choice: ClientsPetChoice)] {
        directory.items.filter { $0.client.id != source.clientId }.map { entry in
            (entry, ClientsPetChoice(id: entry.id, name: entry.petName, species: entry.petSpecies, breed: entry.petBreed, photoUrl: entry.photoUrl, clientId: entry.client.id, clientName: entry.client.name ?? "—", linked: entry.linked == true, householdPetId: nil, archived: entry.status == "archived", details: entry.createdAt.map { LF("Added %@", ClientsMatches.fullDay($0)) } ?? ""))
        }
    }

    @ViewBuilder
    private var pickStep: some View {
        ModalSection(title: LF("%@’s other pets", source.clientName)) {
            if own.isEmpty {
                EmptyState(systemImage: "paw-print", title: LF("%@ has no other pets.", source.clientName), accent: Theme.lime)
            } else {
                VStack(spacing: 8) { ForEach(own) { row($0, otherClient: false) } }
            }
        }
        if canSearchOthers {
            ModalSection(title: L("Another client’s pet"), subtitle: L("When the same pet was registered under someone else in the family.")) {
                SearchField(prompt: L("Pet, owner, phone or microchip"), text: $query, shape: .field).accessibilityLabel(L("Search pets"))
                if let searched = ClientSearch.query(query) {
                    if !directory.loadedOnce || (directory.isLoading && others.isEmpty) {
                        LoadingState()
                    } else if others.isEmpty {
                        EmptyState(systemImage: "search", title: LF("No other client’s pet matches “%@”", searched), accent: Theme.lime)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(others, id: \.entry.id) { found in
                                row(found.choice, otherClient: true).onAppear { directory.loadMoreIfNeeded(found.entry) }
                            }
                            PagerFooter(pager: directory)
                        }
                        .accessibilityLabel(L("Another client’s pet"))
                        .opacity(directory.isLoading ? 0.6 : 1)
                    }
                }
            }
        }
    }

    private func blocked(_ choice: ClientsPetChoice) -> Bool {
        guard let mine = source.householdPetId?.nonEmpty, let theirs = choice.householdPetId?.nonEmpty else { return false }
        return mine != theirs
    }

    private func row(_ choice: ClientsPetChoice, otherClient: Bool) -> some View {
        let isBlocked = blocked(choice)
        let selected = picked?.id == choice.id
        let line = [ClientsText.species(choice.species), choice.breed?.nonEmpty, otherClient ? choice.clientName : nil, choice.archived ? L("Archived@pet") : nil].compactMap { $0 }.joined(separator: " · ")
        return Button {
            picked = selected ? nil : choice
        } label: {
            HStack(spacing: 12) {
                PetAvatar(name: choice.name, species: choice.species, photoURL: choice.photoUrl, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(choice.name).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        if choice.linked { Glyph("link-2", size: 14).foregroundStyle(Theme.blue).accessibilityLabel(L("Linked to PawMiaw")) }
                    }
                    Text(line).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                    if let details = choice.details.nonEmpty { Text(details).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                    if isBlocked { Text(L("Linked to a different pet in PawMiaw")).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.destructive) }
                }
                Spacer(minLength: 0)
                Tick(on: selected, style: .choice)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selected ? AnyShapeStyle(Theme.wash(Theme.blue, 8)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(selected ? Theme.blue : Theme.borderSoft, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(isBlocked)
        .opacity(isBlocked ? 0.55 : 1)
        .simultaneousGesture(TapGesture(count: 2).onEnded { if !isBlocked { picked = choice; confirming = true } })
    }

    @ViewBuilder
    private func confirmStep(_ picked: ClientsPetChoice) -> some View {
        ClientsMergePair {
            ClientsMergeSide(stays: false) {
                ClientsMergeHeading(name: source.name, photoURL: source.photoUrl, species: source.species, isPet: true, linked: source.linked)
                lines([[ClientsText.species(source.species), source.breed?.nonEmpty].compactMap { $0 }.joined(separator: " · "), source.clientName, source.details])
            }
        } target: {
            ClientsMergeSide(stays: true) {
                ClientsMergeHeading(name: picked.name, photoURL: picked.photoUrl, species: picked.species, isPet: true, linked: picked.linked)
                lines([[ClientsText.species(picked.species), picked.breed?.nonEmpty].compactMap { $0 }.joined(separator: " · "), picked.clientName, picked.details])
            }
        }
        ModalSection(title: L("What happens")) {
            VStack(alignment: .leading, spacing: 8) {
                ClientsWhatHappensLine(text: LF("%1$@ stays. %2$@’s visits, records, invoices, stays, reminders, weight history, notes and history move to it.", picked.name, source.name))
                if picked.clientId != source.clientId {
                    ClientsWhatHappensLine(text: LF("%1$@ belongs to %2$@: what moves goes under %2$@ too.", picked.name, picked.clientName))
                }
                ClientsWhatHappensLine(text: LF("Details %1$@ is missing are filled in from %2$@, and its care card is completed, not duplicated.", picked.name, source.name))
                ClientsWhatHappensLine(text: LF("%@’s record goes. This can’t be undone.", source.name))
                ClientsWhatHappensLine(text: L("Two pets linked to different pets in PawMiaw can’t be combined."))
            }
        }
    }

    private func lines(_ values: [String]) -> some View {
        ForEach(values.filter { !$0.isEmpty }, id: \.self) { Text($0).font(Theme.text(13)).foregroundStyle(Theme.inkSoft) }
    }

    private func merge() {
        guard let picked else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let result: ClientsMergeResult = try await API.post("/provider-clients/\(source.clientId)/pets/\(source.petId)/merge", body: ["intoPetId": picked.id])
                Toast.show(LF("Combined into %@.", picked.name))
                announceDataChanged()
                dismiss()
                onMerged(result.providerClientId ?? picked.clientId, result.targetId ?? picked.id)
            } catch {
                Toast.error(ClientsMatches.errorText(error))
            }
        }
    }
}

// MARK: - Unlink a pet from the family

struct ClientsUnlinkTarget: Identifiable, Hashable {
    var id: String { petId }
    let clientId: String
    let clientName: String
    let petId: String
    let petName: String
}

struct ClientsUnlinkPetSheet: View {
    let target: ClientsUnlinkTarget
    var onDone: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        ProviderModal(title: LF("Unlink %@?", target.petName), subtitle: L("From the family’s PawMiaw"), systemImage: "link-2-off", accent: .pink, primaryTitle: L("Unlink"), primaryVariant: .destructive, isWorking: working, cancelTitle: L("Keep it linked"), primaryIcon: "link-2-off") {
            unlink()
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                ClientsWhatHappensLine(text: LF("Your clinic keeps its copy of %@, with every visit, record and invoice.", target.petName), tint: Theme.pink)
                ClientsWhatHappensLine(text: LF("The family stops sharing %@ with your clinic: what they add in PawMiaw no longer reaches you, and what you write no longer reaches them.", target.petName), tint: Theme.pink)
                ClientsWhatHappensLine(text: L("If it was the wrong pet, unlink it and invite the family again to link the right one."), tint: Theme.pink)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func unlink() {
        working = true
        Task {
            defer { working = false }
            do {
                let result: ClientsUnlinkResult = try await API.post("/provider-clients/\(target.clientId)/pets/\(target.petId)/unlink")
                Toast.show(result.clientUnlinked == true ? LF("%1$@ unlinked. %2$@ is no longer linked to a PawMiaw family.", target.petName, target.clientName) : LF("%@ unlinked.", target.petName))
                announceDataChanged()
                await onDone()
                dismiss()
            } catch {
                Toast.error(ClientsMatches.errorText(error))
            }
        }
    }
}
