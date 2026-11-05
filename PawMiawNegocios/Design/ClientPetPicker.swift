//
//  ClientPetPicker.swift
//  PawMiawNegocios
//
//  Who something is for (web client-pet-picker.tsx): search the business's
//  clients, choose one, then their pet (or several, or none). The one picker
//  of every sheet that starts with a family: booking, a stay, a home stay,
//  admitting, a prescription, a bill, the Store.
//
//  Search, the same everywhere: the server searches (`GET /provider-clients`),
//  250 ms after typing stops, from 2 characters; under that the most recent
//  clients show. Results come 20 at a time and load on as the list scrolls;
//  the count is the server's. The chosen client stays on top.
//

import SwiftUI

struct PickedPet: Codable, Identifiable, Hashable {
    let id: String
    let petName: String?
    let petSpecies: String?
    let petBreed: String?
    let photoUrl: String?
    let status: String?
    var microchipNumber: String? = nil
    var weight: Double? = nil

    var name: String { petName ?? "" }
}

struct PickedClient: Codable, Identifiable, Hashable {
    let id: String
    let ownerName: String?
    let ownerEmail: String?
    let ownerPhone: String?
    let householdId: String?
    let photoUrl: String?
    let status: String?
    let pets: [PickedPet]?
    var petCount: Int? = nil

    var name: String { ownerName ?? "" }
    var activePets: [PickedPet] { (pets ?? []).filter { $0.status != "archived" } }
}

enum ClientSearch {
    /// Searches start at two characters (one matches almost everyone).
    static let minimumCharacters = 2
    static let pageSize = 20
    static let debounce: Duration = .milliseconds(250)

    /// The text worth sending, or nil (show the most recent clients).
    static func query(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= minimumCharacters ? trimmed : nil
    }
}

struct ClientPetPicker: View {
    enum Pets { case none, one, several }

    @Binding var client: PickedClient?
    @Binding var petIds: [String]
    var pets: Pets = .one
    var petRequired: Bool = false
    var label: String = L("Find client")
    var key: String = "client"
    var petKey: String = "pet"
    var form: FormState? = nil
    /// Only this member's clients (a vet who sees only their own).
    var assignedMemberId: String? = nil
    /// A line under a pet (why a room won't take it) and whether it can't be chosen.
    var petNote: ((PickedPet) -> (text: String, disabled: Bool)?)? = nil
    /// A line under "For {name}" (how booking several pets together works).
    var petHint: String? = nil

    @State private var search = ""
    @State private var found: [PickedClient] = []
    @State private var total: Int?
    @State private var hasMore = false
    @State private var loading = false
    @State private var asked: String?
    /// The list is open (choosing); once a client is chosen it folds to that client so the pets show.
    @State private var listOpen = true

    private var query: String? { ClientSearch.query(search) }
    private var clientError: String? { form?.error(key) }
    private var petError: String? { form?.error(petKey) }

    /// The chosen client first, then what the search found.
    private var shown: [PickedClient] {
        guard let client, !found.contains(where: { $0.id == client.id }) else { return found }
        return [client] + found
    }

    private var pinned: Bool { query != nil && client != nil && !found.contains(where: { $0.id == client?.id }) }
    private var resultCount: Int { total ?? found.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let client, !listOpen {
                // Folded (owner, 2026-11-04): only the chosen client, so the pets are in view;
                // a tap on it opens the list again to choose someone else.
                chosenRow(client)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    FormField(label: label, key: key, form: form, required: true) {
                        SearchField(prompt: L("Search by name, email, phone, or pet"), text: $search, shape: .field)
                    }
                    clientList
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let client, pets != .none, !listOpen {
                petChoice(client)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.34), value: listOpen)
        // A client handed in (a pet's page, a follow-up) starts folded.
        .onAppear { if client != nil { listOpen = false } }
        .onChange(of: client?.id) { _, id in if id == nil { listOpen = true } }
        .task(id: "\(query ?? "")|\(assignedMemberId ?? "")") {
            if asked != nil { try? await Task.sleep(for: ClientSearch.debounce) }
            guard !Task.isCancelled else { return }
            await load(reset: true)
        }
    }

    // MARK: Clients

    private var clientList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                (Text(L("Choose client")) + Text(" *").foregroundColor(Theme.coral))
                    .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                Spacer(minLength: 8)
                Text((resultCount == 1 ? LF("%@ result", "1") : LF("%@ results", String(resultCount))).uppercased())
                    .font(Theme.text(12)).tracking(1.4).foregroundStyle(Theme.inkSoft)
            }
            if loading && shown.isEmpty {
                PickerEmpty(text: L("Searching clients…"))
            } else if shown.isEmpty {
                PickerEmpty(text: query != nil ? L("No clients matched that search.") : L("No clients exist yet. Add a client and their pet first."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(shown) { entry in
                            ClientTile(client: entry, chosen: entry.id == client?.id, pinned: pinned && entry.id == client?.id) { choose(entry) }
                                .onAppear { if entry.id == shown.last?.id, hasMore, !loading { Task { await load(reset: false) } } }
                        }
                        if loading && !shown.isEmpty { ProgressView().tint(Theme.blue).padding(.vertical, 6) }
                    }
                    .padding(2)
                }
                .frame(maxHeight: 280)
                .scrollBounceBehavior(.basedOnSize)
            }
            if pinned && found.isEmpty && !loading, let query {
                Text(LF("Nobody else matches “%@”.", query)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            }
            if let clientError { Text(clientError).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
        }
        .padding(clientError == nil ? 0 : 12)
        .overlay {
            if clientError != nil {
                RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.destructive.opacity(0.7), lineWidth: 1)
            }
        }
        .id(key)
    }

    /// The chosen client alone, with the way back to the list.
    private func chosenRow(_ chosen: PickedClient) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                (Text(L("Client")) + Text(" *").foregroundColor(Theme.coral))
                    .font(Theme.text(14, weight: .medium)).foregroundStyle(Theme.inkStrong)
                Spacer(minLength: 8)
                Button { listOpen = true } label: {
                    HStack(spacing: 4) {
                        Text(L("Change"))
                        Glyph("chevron-down", size: 14)
                    }
                    .font(Theme.text(13, weight: .bold))
                    .foregroundStyle(Theme.blue)
                }
                .buttonStyle(.plain)
            }
            ClientTile(client: chosen, chosen: true, pinned: false) { listOpen = true }
                .accessibilityHint(L("Opens the list to choose another client"))
        }
        .id(key)
    }

    // MARK: Pets

    @ViewBuilder
    private func petChoice(_ chosen: PickedClient) -> some View {
        let list = chosen.activePets
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if petRequired {
                        Text(pets == .several ? L("Choose pets") : L("Choose pet")) + Text(" *").foregroundColor(Theme.coral)
                    } else {
                        Text(pets == .several ? L("Choose pets") : L("Choose pet"))
                    }
                }
                .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                Text(pets == .several ? LF("For %@ · choose one or more", chosen.name) : LF("For %@", chosen.name))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                if let petHint { Text(petHint).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
            }
            if list.isEmpty {
                PickerEmpty(text: L("This client has no pets yet."))
            } else {
                VStack(spacing: 12) {
                    ForEach(list) { pet in
                        let note = petNote?(pet)
                        PetTile(pet: pet, chosen: petIds.contains(pet.id), several: pets == .several, note: note) { toggle(pet.id) }
                            .disabled(note?.disabled == true && !petIds.contains(pet.id))
                    }
                }
            }
            if let petError { Text(petError).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral) }
        }
        .padding(petError == nil ? 0 : 12)
        .overlay {
            if petError != nil {
                RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.destructive.opacity(0.7), lineWidth: 1)
            }
        }
        .id(petKey)
    }

    // MARK: Choosing

    private func choose(_ entry: PickedClient) {
        form?.clear(key)
        listOpen = false
        guard entry.id != client?.id else { return }
        client = entry
        let available = entry.activePets.filter { petNote?($0)?.disabled != true }
        petIds = pets != .none && available.count == 1 ? [available[0].id] : []
    }

    private func toggle(_ id: String) {
        form?.clear(petKey)
        switch pets {
        case .none: break
        case .one: petIds = petIds == [id] && !petRequired ? [] : [id]
        case .several: if petIds.contains(id) { petIds.removeAll { $0 == id } } else { petIds.append(id) }
        }
    }

    // MARK: Loading

    private func load(reset: Bool) async {
        let text = query
        if reset { asked = text ?? "" }
        loading = true
        defer { loading = false }
        let offset = reset ? 0 : found.count
        let page: Page<PickedClient>? = try? await API.get("/provider-clients", query: [
            "limit": String(ClientSearch.pageSize),
            "offset": String(offset),
            "search": text,
            "assignedOrganizationMemberId": assignedMemberId,
        ])
        // A slower answer for an older search never replaces a newer one.
        guard text == query else { return }
        let items = page?.items ?? []
        found = reset ? items : found + items.filter { item in !found.contains(where: { $0.id == item.id }) }
        total = page?.total
        hasMore = page?.hasMore ?? (items.count == ClientSearch.pageSize)
    }
}

/// A client in the picker (web: rounded box, 2 pt border; chosen = PAW Blue
/// edge on MIAW yellow 16%, a check; the face ringed in blue).
private struct ClientTile: View {
    let client: PickedClient
    let chosen: Bool
    let pinned: Bool
    let action: () -> Void

    private var petCount: Int { client.petCount ?? client.activePets.count }
    private var contact: String { client.ownerEmail?.nonEmpty ?? client.ownerPhone?.nonEmpty ?? L("No contact yet") }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.wash(Theme.mango, 35))
                    Text(NameText.firstLetters(client.name)).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    if let url = APIConfig.assetURL(client.photoUrl) {
                        AsyncImage(url: url) { phase in if let image = phase.image { image.resizable().scaledToFill() } }
                            .clipShape(Circle())
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.blue, lineWidth: 2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(client.name).font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text(contact).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    HStack(spacing: 8) {
                        Text((petCount == 1 ? LF("%@ pet", "1") : LF("%@ pets", String(petCount))).uppercased())
                            .font(Theme.text(12)).tracking(1.4).foregroundStyle(Theme.inkSoft)
                        if client.householdId != nil {
                            TagChip(text: L("Family linked"), icon: "link-2", linked: true)
                        } else {
                            TagChip(text: L("Clinic only"), icon: "building-2")
                        }
                        if pinned {
                            Text(L("Chosen").uppercased()).font(Theme.text(12, weight: .bold)).tracking(1.4).foregroundStyle(Theme.blue)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Theme.wash(Theme.blue, 12), in: Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 4)
                if chosen { Glyph("check", size: 20).foregroundStyle(Theme.blue) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(chosen ? AnyShapeStyle(Theme.wash(Theme.lime, 16)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(chosen ? Theme.blue : Theme.borderSoft, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// A pet in the picker: chosen = PAW Blue edge on Sky Blue 18%; several = a tick.
private struct PetTile: View {
    let pet: PickedPet
    let chosen: Bool
    let several: Bool
    let note: (text: String, disabled: Bool)?
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                PetAvatar(name: pet.name, species: pet.petSpecies, photoURL: pet.photoUrl, size: 48)
                    .overlay(Circle().strokeBorder(Theme.blue, lineWidth: 2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(pet.name).font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                    Text([PickerSpecies.label(pet.petSpecies), pet.petBreed?.nonEmpty].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? L("Pet profile"))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    if let note {
                        Text(note.text).font(Theme.text(12, weight: .semibold)).foregroundStyle(note.disabled ? Theme.destructive : Theme.inkSoft).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if several {
                    Tick(on: chosen)
                } else if chosen {
                    Glyph("check", size: 20).foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(chosen ? AnyShapeStyle(Theme.wash(Theme.aqua, 18)) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(chosen ? Theme.blue : Theme.borderSoft, lineWidth: 2))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// "Nothing here" inside the picker: a dashed box.
private struct PickerEmpty: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 20)
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}

/// The species' word (web getPetSpeciesLabel).
enum PickerSpecies {
    static func label(_ species: String?) -> String? {
        switch species?.lowercased() {
        case "dog": L("Dog")
        case "cat": L("Cat")
        case "bird": L("Bird")
        case "rabbit": L("Rabbit")
        case "fish": L("Fish")
        case "reptile": L("Reptile")
        case "rodent": L("Rodent")
        case nil, "": nil
        default: L("Other")
        }
    }
}
