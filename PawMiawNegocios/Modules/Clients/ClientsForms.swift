//
//  ClientsForms.swift
//  PawMiawNegocios
//
//  The client and pet forms (web: provider-client-sheet.tsx, the edit
//  sheets, provider-client-pet-sheet.tsx): add a client with their first
//  pet in two steps, edit the client, add a pet, edit a pet. Every one
//  fails the same way (the form error standard) and answers the server's
//  "¿Eres tú?" when the email is the person's own on PawMiaw.
//

import SwiftUI

// MARK: - Pieces

/// What a pet form holds, shared by "first pet", "add pet" and "edit pet".
@MainActor
final class ClientsPetDraft: ObservableObject {
    @Published var name = ""
    @Published var species = "dog"
    @Published var breed = ""
    @Published var sex = "unknown"
    @Published var hasBirthday = false
    @Published var birthday = Date()
    @Published var weight = ""
    @Published var unit = "kg"
    @Published var neutered = false
    @Published var microchip = ""
    @Published var notes = ""
    @Published var preferredMemberId = ""
    @Published var photo = PhotoDraft()

    init() {}

    init(pet: ClientsPet) {
        name = pet.petName
        species = pet.petSpecies ?? "dog"
        breed = pet.petBreed ?? ""
        sex = pet.sex ?? "unknown"
        if let born = DateText.parse(pet.birthDate) { hasBirthday = true; birthday = born }
        weight = ClientsText.kilogramsInput(pet.weight)
        neutered = pet.isNeutered ?? false
        microchip = pet.microchipNumber ?? ""
        notes = pet.notes ?? ""
        preferredMemberId = pet.preferredMember?.id ?? ""
    }

    var isEmpty: Bool { name.isEmpty && breed.isEmpty && weight.isEmpty && microchip.isEmpty && notes.isEmpty && photo.data == nil }

    var grams: Int? {
        let cleaned = weight.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0 else { return nil }
        return Int((value * (unit == "kg" ? 1000 : 453.59237)).rounded())
    }

    var weightInvalid: Bool { !weight.trimmingCharacters(in: .whitespaces).isEmpty && grams == nil }

    /// The fields as the API takes them. A linked pet's name and species are the family's.
    func body(linked: Bool = false, withPreferred: Bool = false) -> [String: Any?] {
        var body: [String: Any?] = [
            "petBreed": breed.nonEmpty,
            "sex": sex == "unknown" ? nil : sex,
            "birthDate": hasBirthday ? DateText.dayKey(birthday, zone: .current) : nil,
            "weight": grams,
            "isNeutered": neutered,
            "microchipNumber": microchip.nonEmpty,
            "notes": notes.nonEmpty,
        ]
        if !linked {
            body["petName"] = name.trimmingCharacters(in: .whitespaces)
            body["petSpecies"] = species
        }
        if withPreferred { body["preferredOrganizationMemberId"] = preferredMemberId.nonEmpty }
        return body
    }
}

/// The pet's fields (web: the "Perfil de la mascota" section, pink). A linked
/// pet keeps the family's name, species and photo: its own section says so.
struct ClientsPetFields: View {
    @ObservedObject var draft: ClientsPetDraft
    @ObservedObject var form: FormState
    var linked = false
    var currentPhotoURL: String?
    /// The pet notes' placeholder (the first pet's sheet says "intake").
    var notesPrompt: String = L("Anything the clinic should remember about this pet.")
    /// A linked pet: its name, species and last sync, read from the family.
    var linkedPet: ClientsPet? = nil
    /// Under the linked pet's values: where the family's profile differs.
    var linkedExtra: AnyView? = nil
    /// After the microchip: the preferred vet (editing a pet).
    var preferredVet: AnyView? = nil
    /// The name's placeholder ("e.g. Nina" when adding another pet).
    var namePrompt: String = L("e.g. Luna")
    /// Said under the name, not refused: the client already has a pet called that.
    var nameWarning: String? = nil

    var body: some View {
        if linked {
            ModalSection(title: L("Linked household profile"), systemImage: "link-2", tint: Theme.aqua) {
                let synced = linkedPet?.profileLastSyncedAt?.nonEmpty.map { LF("Last synced %@.", DateText.date($0)) }
                Text([L("Name, species and photo come from the family. Breed, sex, birthday, weight and microchip are your clinic’s own record: the family’s profile only fills what you leave empty."), synced].compactMap { $0 }.joined(separator: " "))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                if let linkedPet {
                    FactRow(label: L("Name"), value: linkedPet.petName)
                    FactRow(label: L("Species"), value: ClientsText.species(linkedPet.petSpecies))
                }
                if let linkedExtra { linkedExtra }
            }
        }
        ModalSection(title: L("Pet profile"), systemImage: "paw-print", tint: Theme.pink) {
            if !linked {
                PhotoField(label: L("Pet photo"), hint: L("Optional, but useful for recognition."), currentURL: currentPhotoURL, draft: $draft.photo, shape: .circle, optional: false, allowsRemove: false, addTitle: L("Upload photo"))
                PMTextField(L("Pet name"), text: $draft.name, key: "petName", form: form, prompt: namePrompt, capitalization: .words, required: true)
                if let nameWarning, form.error("petName") == nil {
                    NoticeCard(tone: .warning, message: nameWarning, icon: nil)
                }
                MenuField(label: L("Pet species"), options: ClientsText.speciesOptions, selection: $draft.species, required: true)
            }
            PMTextField(L("Breed"), text: $draft.breed, prompt: L("Optional breed or type"), capitalization: .words)
            OptionalDateField(
                label: L("Birthday"),
                date: Binding(get: { draft.hasBirthday ? draft.birthday : nil }, set: { day in
                    draft.hasBirthday = day != nil
                    if let day { draft.birthday = day }
                }),
                placeholder: L("Add birthday"), zone: .current, max: Date(), optional: false
            )
            FormField(label: L("Sex")) {
                ChoiceCards(tiles: [
                    (value: "female", title: L("Female"), icon: "venus"),
                    (value: "male", title: L("Male"), icon: "mars"),
                    (value: "unknown", title: L("Add later"), icon: "minus"),
                ], selection: $draft.sex)
            }
            HStack(alignment: .top, spacing: 12) {
                PMTextField(L("Weight"), text: $draft.weight, key: "weight", form: form, prompt: draft.unit == "kg" ? L("e.g. 12.5") : L("e.g. 27.5"), keyboard: .decimalPad)
                FormField(label: L("Unit")) {
                    ChoiceCards(tiles: [(value: "kg", title: "KG", icon: nil), (value: "lb", title: "LB", icon: nil)], selection: $draft.unit)
                }
            }
            PMTextField(L("Microchip number"), text: $draft.microchip, prompt: L("Optional chip number"), keyboard: .numbersAndPunctuation, capitalization: .never)
            if let preferredVet { preferredVet }
            // A linked pet's neuter status is the family's (web: no switch for it).
            if !linked {
                ToggleRow(title: L("Neutered or spayed"), subtitle: L("Save this now if it is already known."), isOn: $draft.neutered)
            }
            PMTextField(L("Pet notes"), text: $draft.notes, prompt: notesPrompt, multiline: true)
        }
    }
}

/// "¿Eres tú?": the email is the person's own on PawMiaw (docs/linking.md; web `SelfLinkPrompt`):
/// a 2 pt PAW Blue box on aqua, what each answer does, and the two answers.
private struct ClientsSelfLinkCard: View {
    let email: String
    let working: Bool
    let choose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(icon: "user-round-check", accent: Theme.blue, size: 36, iconSize: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Is this you?")).font(.brandHeading(18)).foregroundStyle(Theme.inkStrong)
                    Text(L("This will connect your pets with your business.")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                    Text(LF("%@ is your email, or someone’s in your family, on PawMiaw.", email)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Glyph("link-2", size: 16).foregroundStyle(Theme.blue).padding(.top, 2)
                    (Text("\(L("Connect")): ").bold().foregroundStyle(Theme.inkStrong) + Text(L("When your family books or connects a pet with this business, this client becomes your family and your pets’ records come together.")))
                }
                HStack(alignment: .top, spacing: 8) {
                    Glyph("link-2-off", size: 16).padding(.top, 2)
                    (Text("\(L("Keep separate")): ").bold().foregroundStyle(Theme.inkStrong) + Text(L("The client stays only in your business and never links to your family by itself.")))
                }
            }
            .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            VStack(spacing: 8) {
                PMButton(L("Yes, connect my pets"), systemImage: "link-2", fullWidth: true, isWorking: working) { choose("link") }
                PMButton(L("Keep separate"), systemImage: "link-2-off", variant: .outline, fullWidth: true) { choose("keep_separate") }.disabled(working)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(Theme.aqua, 14), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.blue, lineWidth: 2))
        .id("selfLink")
    }
}

/// The client's fields, shared by "add" and "edit" (web: "Perfil del cliente" sky,
/// "Datos de contacto" butter, "Notas del cliente" neutral).
private struct ClientsContactFields: View {
    @Binding var photo: PhotoDraft
    var currentPhotoURL: String? = nil
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var email: String
    @Binding var phone: String
    @Binding var language: String
    @Binding var notes: String
    @ObservedObject var form: FormState

    /// The client being edited (never its own match in "A client already has this contact").
    var clientId: String? = nil
    /// "Open {name}" in that notice: the sheet closes and the client opens.
    var onOpenClient: ((String) -> Void)? = nil

    var body: some View {
        ModalSection(title: L("Client profile"), systemImage: "contact-round", tint: Theme.aqua) {
            PhotoField(label: L("Client photo"), hint: L("Optional, but useful for recognition."), currentURL: currentPhotoURL, draft: $photo, shape: .circle, optional: false, allowsRemove: false, addTitle: L("Upload photo"))
            PMTextField(L("First name"), text: $firstName, key: "ownerFirstName", form: form, prompt: L("e.g. Alejandro"), capitalization: .words, required: true)
            PMTextField(L("Last name"), text: $lastName, prompt: L("Optional last name"), capitalization: .words)
        }
        ModalSection(title: L("Contact details"), systemImage: "message-square-text", tint: Theme.butter) {
            PMTextField(L("Client email"), text: $email, key: "ownerEmail", form: form, prompt: "azamora@example.com", keyboard: .emailAddress)
            PMTextField(L("Client phone"), text: $phone, key: "ownerPhone", form: form, prompt: "+52 55 1234 5678", keyboard: .phonePad)
            // Someone on file already has this phone or email: open them instead of adding a second.
            ClientsExistingClientNotice(phone: phone, email: email, excludeClientId: clientId, onOpenClient: onOpenClient)
            VStack(alignment: .leading, spacing: 8) {
                MenuField(label: L("Language to write to this client in"), options: [("", L("Automatic")), ("en", L("English")), ("es", L("Spanish"))], selection: $language)
                Text(L("Emails and ready-made messages to this client go out in it. Automatic uses the business’s language; someone with a PawMiaw account gets emails in their account’s language.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
        ModalSection(title: L("Client notes"), systemImage: "notebook-pen", tint: Theme.borderSoft) {
            PMTextField(L("Client notes"), text: $notes, prompt: L("Anything the clinic should remember about this client contact."), multiline: true)
        }
    }
}

/// Said while a client is added or edited, before anything is saved (web `ExistingClientNotice`):
/// someone on file already has this phone or this email. It never stops the save (a couple
/// shares a number); it lets the desk open the one that is there instead of making a second.
private struct ClientsExistingClientNotice: View {
    let phone: String
    let email: String
    var excludeClientId: String? = nil
    var onOpenClient: ((String) -> Void)? = nil

    @State private var found: [(client: ClientsClient, shares: String)] = []

    /// A phone as its digits; the last ten are what two ways of writing it share.
    private static func phoneKey(_ value: String?) -> String? {
        let digits = (value ?? "").filter(\.isNumber)
        return digits.count >= 8 ? String(digits.suffix(10)) : nil
    }

    /// An email worth looking up: it has both sides of the @.
    private static func emailKey(_ value: String?) -> String? {
        let email = (value ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return ClientsText.emailLooksValid(email) && email.contains("@") ? email : nil
    }

    var body: some View {
        Group {
            if !found.isEmpty {
                NoticeCard(tone: .warning, title: found.count == 1 ? L("A client already has this contact") : LF("%d clients already have this contact", found.count), icon: "users-round") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(found, id: \.client.id) { entry in
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(entry.client.ownerName).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                                        if entry.client.isArchived { Chip(text: L("Archived"), tone: .muted) }
                                    }
                                    let pets = entry.client.allPets.filter { !$0.isArchived }.map(\.petName).joined(separator: ", ")
                                    if !pets.isEmpty { Text(pets).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                                    Text(entry.shares == "both" ? L("Same phone and email") : entry.shares == "phone" ? L("Same phone") : L("Same email"))
                                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                                }
                                Spacer(minLength: 8)
                                if let onOpenClient {
                                    PMButton(LF("Open %@", entry.client.ownerName.split(separator: " ").first.map(String.init) ?? entry.client.ownerName), variant: .outline, size: .slim) {
                                        onOpenClient(entry.client.id)
                                    }
                                }
                            }
                        }
                        Text(L("If it is the same person, open their page and add the pet there. If it is someone else (a relative who shares it), carry on."))
                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        }
        .task(id: "\(Self.phoneKey(phone) ?? "")|\(Self.emailKey(email) ?? "")") {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await look()
        }
    }

    private func look() async {
        let phoneSearch = Self.phoneKey(phone)
        let emailSearch = Self.emailKey(email)
        var candidates: [ClientsClient] = []
        for search in [phoneSearch, emailSearch].compactMap({ $0 }) {
            let page: Page<ClientsClient>? = try? await API.get("/provider-clients", query: ["limit": "5", "offset": "0", "search": search, "includeArchived": "true"])
            for client in page?.items ?? [] where !candidates.contains(where: { $0.id == client.id }) { candidates.append(client) }
        }
        guard !Task.isCancelled else { return }
        found = candidates.compactMap { client in
            guard client.id != excludeClientId else { return nil }
            let samePhone = phoneSearch != nil && Self.phoneKey(client.ownerPhone) == phoneSearch
            let sameEmail = emailSearch != nil && Self.emailKey(client.ownerEmail) == emailSearch
            guard samePhone || sameEmail else { return nil }
            return (client, samePhone && sameEmail ? "both" : samePhone ? "phone" : "email")
        }
    }
}

/// A quiet line under a form's parts, or a quiet titled note (web: the muted rounded box,
/// `surface-muted` on a hairline).
func clientsQuietNote(title: String? = nil, _ text: String) -> some View {
    NoticeCard(tone: .custom(Theme.surfaceMuted), title: title, message: text, icon: nil)
}

private func clientsIsSelfLinkAsk(_ error: Error) -> Bool {
    guard let api = error as? APIError else { return false }
    return api.status == 409 && api.code == "self_link_confirm"
}

private let clientsFieldKeys: [String: String] = [
    "ownerFirstName": "ownerFirstName", "ownerEmail": "ownerEmail", "ownerPhone": "ownerPhone",
    "firstPet.petName": "petName", "petName": "petName", "firstPet.weight": "weight", "weight": "weight",
]

// MARK: - Add a client and their first pet

struct ClientsCreateSheet: View {
    /// "Open {name}" in "A client already has this contact": the sheet closes, that client opens.
    var onOpenClient: ((String) -> Void)? = nil
    let onCreated: (ClientsClient) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @StateObject private var pet = ClientsPetDraft()
    @State private var step = 0
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var language = ""
    @State private var notes = ""
    @State private var clientPhoto = PhotoDraft()
    @State private var saving = false
    @State private var selfLinkAsk = false

    private var dirty: Bool { !firstName.isEmpty || !lastName.isEmpty || !email.isEmpty || !phone.isEmpty || !notes.isEmpty || !pet.isEmpty }

    var body: some View {
        ProviderModal(
            title: step == 0 ? L("Add client") : L("Add first pet"),
            subtitle: step == 0 ? L("Start with the client contact. Their first pet comes next.") : L("Add the first pet for this client."),
            systemImage: step == 0 ? "users-round" : "paw-print",
            accent: step == 0 ? .butter : .pink,
            isDirty: dirty,
            form: form,
            primaryTitle: step == 0 ? L("Continue") : (saving ? L("Saving client") : L("Add client")),
            isWorking: saving,
            steps: ModalSteps(steps: [(L("Client"), "users-round"), (L("Pet"), "paw-print")], current: step),
            onBack: step == 1 ? { step = 0 } : nil,
            primaryIcon: step == 0 ? "paw-print" : "users-round",
            // The family is asked "¿Eres tú?" first: nothing is saved until they answer.
            onPrimary: step == 1 && selfLinkAsk ? nil : { if step == 0 { next() } else { save(selfLink: nil) } }
        ) {
            if step == 0 {
                ClientsContactFields(photo: $clientPhoto, firstName: $firstName, lastName: $lastName, email: $email, phone: $phone, language: $language, notes: $notes, form: form, onOpenClient: openExisting)
                clientsQuietNote(L("Save the client details first. The first pet comes next as its own step so the contact and pet profiles stay separate."))
            } else {
                ClientsPetFields(draft: pet, form: form, notesPrompt: L("Anything the clinic should remember about this pet intake."))
                clientsQuietNote(L("This creates the first pet under the client you just added. More pets can be attached to the same client later."))
                if selfLinkAsk {
                    ClientsSelfLinkCard(email: email.trimmingCharacters(in: .whitespaces), working: saving) { save(selfLink: $0) }
                }
            }
        }
    }

    private var openExisting: ((String) -> Void)? {
        guard let onOpenClient else { return nil }
        return { id in
            dismiss()
            onOpenClient(id)
        }
    }

    private func next() {
        // What is wrong with the contact is said on the step that has it.
        guard form.check([
            ("ownerFirstName", firstName.nonEmpty == nil ? L("Add the client first name first.") : nil),
            ("ownerEmail", email.nonEmpty != nil && !ClientsText.emailLooksValid(email) ? L("Check the email address.") : nil),
            ("ownerPhone", ClientsText.phoneLooksValid(phone) ? nil : L("Finish the phone number, or leave it empty.")),
        ]) else { return }
        step = 1
    }

    private func save(selfLink: String?) {
        guard form.check([
            ("petName", pet.name.nonEmpty == nil ? L("Add the pet name first.") : nil),
            ("weight", pet.weightInvalid ? L("Write the weight as a number, e.g. 12.5") : nil),
        ]) else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                var body: [String: Any?] = [
                    "ownerFirstName": firstName.trimmingCharacters(in: .whitespaces),
                    "ownerLastName": lastName.nonEmpty,
                    "ownerEmail": email.nonEmpty,
                    "recipientLanguage": language.nonEmpty,
                    "ownerPhone": phone.nonEmpty,
                    "notes": notes.nonEmpty,
                    "firstPet": pet.body(),
                ]
                if let selfLink { body["selfLink"] = selfLink }
                let client: ClientsClient = try await API.post("/provider-clients", body: body)
                if let clientPhoto = clientPhoto.data {
                    do { let _: EmptyResponse = try await ImageUpload.upload(clientPhoto, to: "/provider-clients/\(client.id)/photo") }
                    catch { Toast.error(L("Client and pet were created, but the client photo upload failed. You can add it again later.")) }
                }
                if let petPhoto = pet.photo.data, let created = client.allPets.first {
                    do { let _: EmptyResponse = try await ImageUpload.upload(petPhoto, to: "/provider-client-pets/\(created.id)/photo") }
                    catch { Toast.error(L("Client and pet were created, but the pet photo upload failed. You can add it again later.")) }
                }
                Toast.show(LF("%@ is now in the client directory.", pet.name.trimmingCharacters(in: .whitespaces)))
                announceDataChanged()
                dismiss()
                onCreated(client)
            } catch {
                if clientsIsSelfLinkAsk(error), selfLink == nil {
                    selfLinkAsk = true
                    form.scrollTarget = nil
                    Task { try? await Task.sleep(for: .milliseconds(150)); form.scrollTarget = "selfLink" }
                    return
                }
                if (error as? APIError)?.fields.keys.contains(where: { $0.hasPrefix("owner") }) == true { step = 0 }
                form.apply(error, known: clientsFieldKeys)
            }
        }
    }
}

// MARK: - Edit the client

struct ClientsEditClientSheet: View {
    let client: ClientsClient
    /// "Open {name}" in "A client already has this contact": the sheet closes, that client opens.
    var onOpenClient: ((String) -> Void)? = nil
    let onSaved: (ClientsClient) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var firstName: String
    @State private var lastName: String
    @State private var email: String
    @State private var phone: String
    @State private var language: String
    @State private var notes: String
    @State private var photo = PhotoDraft()
    @State private var saving = false
    @State private var selfLinkAsk = false

    init(client: ClientsClient, onOpenClient: ((String) -> Void)? = nil, onSaved: @escaping (ClientsClient) -> Void) {
        self.client = client
        self.onOpenClient = onOpenClient
        self.onSaved = onSaved
        _firstName = State(initialValue: client.ownerFirstName ?? client.ownerName)
        _lastName = State(initialValue: client.ownerLastName ?? "")
        _email = State(initialValue: client.ownerEmail ?? "")
        _phone = State(initialValue: client.ownerPhone ?? "")
        _language = State(initialValue: client.recipientLanguage ?? "")
        _notes = State(initialValue: client.notes ?? "")
    }

    private var dirty: Bool {
        firstName != (client.ownerFirstName ?? client.ownerName) || lastName != (client.ownerLastName ?? "") || email != (client.ownerEmail ?? "")
            || phone != (client.ownerPhone ?? "") || language != (client.recipientLanguage ?? "") || notes != (client.notes ?? "") || photo.data != nil
    }

    var body: some View {
        ProviderModal(title: L("Edit client"), subtitle: L("Update the main contact details that the provider workspace uses for this client."), systemImage: "users-round", accent: .butter, isDirty: dirty, form: form, primaryTitle: saving ? L("Saving client") : L("Save changes"), isWorking: saving, primaryIcon: "pencil", onPrimary: selfLinkAsk ? nil : { save(selfLink: nil) }) {
            ClientsContactFields(photo: $photo, currentPhotoURL: client.photoUrl, firstName: $firstName, lastName: $lastName, email: $email, phone: $phone, language: $language, notes: $notes, form: form, clientId: client.id, onOpenClient: onOpenClient.map { open in { id in dismiss(); open(id) } })
            if selfLinkAsk {
                ClientsSelfLinkCard(email: email.trimmingCharacters(in: .whitespaces), working: saving) { save(selfLink: $0) }
            }
        }
    }

    private func save(selfLink: String?) {
        guard form.check([
            ("ownerFirstName", firstName.nonEmpty == nil ? L("Add the client first name first.") : nil),
            ("ownerEmail", email.nonEmpty != nil && !ClientsText.emailLooksValid(email) ? L("Check the email address.") : nil),
            ("ownerPhone", ClientsText.phoneLooksValid(phone) ? nil : L("Finish the phone number, or leave it empty.")),
        ]) else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                var body: [String: Any?] = [
                    "ownerFirstName": firstName.trimmingCharacters(in: .whitespaces),
                    "ownerLastName": lastName.nonEmpty,
                    "ownerEmail": email.nonEmpty,
                    "recipientLanguage": language.nonEmpty,
                    "ownerPhone": phone.nonEmpty,
                    "notes": notes.nonEmpty,
                ]
                if let selfLink { body["selfLink"] = selfLink }
                let saved: ClientsClient = try await API.patch("/provider-clients/\(client.id)", body: body)
                if let photo = photo.data {
                    do { let _: EmptyResponse = try await ImageUpload.upload(photo, to: "/provider-clients/\(client.id)/photo") }
                    catch { Toast.error(L("Client details were saved, but the client photo upload failed. You can add it again later.")) }
                }
                Toast.show(LF("%@ was updated.", saved.ownerName))
                announceDataChanged()
                onSaved(saved)
                dismiss()
            } catch {
                if clientsIsSelfLinkAsk(error), selfLink == nil {
                    selfLinkAsk = true
                    form.scrollTarget = nil
                    Task { try? await Task.sleep(for: .milliseconds(150)); form.scrollTarget = "selfLink" }
                    return
                }
                form.apply(error, known: clientsFieldKeys)
            }
        }
    }
}

// MARK: - Add a pet

struct ClientsAddPetSheet: View {
    let client: ClientsClient
    let onSaved: (ClientsClient) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @StateObject private var pet = ClientsPetDraft()
    @State private var saving = false

    var body: some View {
        ProviderModal(title: L("Add pet"), subtitle: LF("Attach another pet to %@ without changing the main client contact.", client.ownerName), systemImage: "paw-print", accent: .pink, isDirty: !pet.isEmpty, form: form, primaryTitle: saving ? L("Adding pet") : L("Add pet"), isWorking: saving, primaryIcon: "paw-print") {
            save()
        } content: {
            ClientsPetFields(draft: pet, form: form, namePrompt: L("e.g. Nina"), nameWarning: sameNamedPet.map { LF("%@ already has a pet called %@.", client.ownerName, $0) })
        }
    }

    /// Two cats can share a name, but usually it is the same pet about to be added again.
    private var sameNamedPet: String? {
        guard let name = pet.name.trimmingCharacters(in: .whitespaces).nonEmpty else { return nil }
        return client.allPets.filter { !$0.isArchived }.map(\.petName).first { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func save() {
        guard form.check([
            ("petName", pet.name.nonEmpty == nil ? L("Add the pet name first.") : nil),
            ("weight", pet.weightInvalid ? L("Write the weight as a number, e.g. 12.5") : nil),
        ]) else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let saved: ClientsClient = try await API.post("/provider-clients/\(client.id)/pets", body: pet.body())
                let name = pet.name.trimmingCharacters(in: .whitespaces)
                if let photo = pet.photo.data, let created = saved.allPets.last(where: { $0.petName == name }) ?? saved.allPets.last {
                    do { let _: EmptyResponse = try await ImageUpload.upload(photo, to: "/provider-client-pets/\(created.id)/photo") }
                    catch { Toast.error(L("Pet details were saved, but the pet photo upload failed. You can add it again later.")) }
                }
                Toast.show(LF("%@ was added for %@.", name, client.ownerName))
                announceDataChanged()
                onSaved(saved)
                dismiss()
            } catch {
                form.apply(error, known: clientsFieldKeys)
            }
        }
    }
}

// MARK: - Edit a pet

struct ClientsEditPetSheet: View {
    let clientName: String
    let pet: ClientsPet
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workspace: Workspace
    @StateObject private var form = FormState()
    @StateObject private var draft: ClientsPetDraft
    @State private var members: [ClientsMember] = []
    @State private var saving = false
    @State private var changed = false
    @State private var differences: [ClientsFamilyDifference] = []

    init(clientName: String, pet: ClientsPet, onSaved: @escaping () -> Void = {}) {
        self.clientName = clientName
        self.pet = pet
        self.onSaved = onSaved
        _draft = StateObject(wrappedValue: ClientsPetDraft(pet: pet))
    }

    var body: some View {
        ProviderModal(title: L("Edit pet"), subtitle: LF("Update the pet profile that %@'s provider records and scheduling attach to.", clientName), systemImage: "paw-print", accent: .pink, isDirty: changed, form: form, primaryTitle: saving ? L("Saving pet") : L("Save changes"), isWorking: saving, primaryIcon: "pencil") {
            save()
        } content: {
            ClientsPetFields(
                draft: draft, form: form, linked: pet.isLinked, currentPhotoURL: pet.photoUrl,
                linkedPet: pet.isLinked ? pet : nil,
                linkedExtra: pet.isLinked && !differences.isEmpty ? AnyView(differencesBox) : nil,
                preferredVet: AnyView(preferredVetField)
            )
        }
        .task {
            members = await ClientsMembers.load()
            if pet.isLinked, let answer: ClientsFamilyDifferences = try? await API.get("/provider-client-pets/\(pet.id)/family-profile") {
                differences = answer.differences ?? []
            }
        }
        .onReceive(draft.objectWillChange) { _ in changed = true }
    }

    /// Where the family's profile differs (web: the mango box in the linked section).
    private var differencesBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("The family’s profile says something else")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
            ForEach(differences) { difference in
                HStack(alignment: .center, spacing: 8) {
                    Text(LF("%1$@: the family says %2$@ · you have %3$@", difference.label, difference.text(difference.family), difference.text(difference.clinic)))
                        .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                    Spacer(minLength: 6)
                    PMButton(L("Use this"), variant: .outline, size: .compact) { use(difference) }.disabled(saving)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(Theme.mango, 10), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mango, lineWidth: 1))
    }

    /// The preferred vet: only a linked pet keeps one.
    private var preferredVetField: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuField(label: L("Preferred vet"), options: vetOptions, selection: $draft.preferredMemberId)
                .disabled(!pet.isLinked)
                .opacity(pet.isLinked ? 1 : 0.5)
            Text(pet.isLinked ? L("Use this to override which vet should stay preferred for this linked pet.") : L("Preferred vet becomes available once this pet is linked to a real household."))
                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
        }
    }

    /// "Usar este dato": the family's value goes into the form; nothing is saved until "Guardar cambios".
    private func use(_ difference: ClientsFamilyDifference) {
        let value = difference.family
        switch difference.field {
        case "breed": draft.breed = value?.string ?? ""
        case "sex": draft.sex = value?.string ?? "unknown"
        case "birthDate":
            if let born = DateText.parse(value?.string.map { "\($0.prefix(10))T12:00:00Z" }) { draft.hasBirthday = true; draft.birthday = born }
        case "weight":
            draft.unit = "kg"
            draft.weight = ClientsText.kilogramsInput(value?.double)
        case "isNeutered": draft.neutered = value?.bool ?? false
        case "microchipNumber": draft.microchip = value?.string ?? ""
        default: break
        }
        differences.removeAll { $0.field == difference.field }
    }

    private var vetOptions: [(value: String, title: String)] {
        var options: [(value: String, title: String)] = [(value: "", title: L("No preferred vet yet"))]
        for member in members { options.append((value: member.id, title: member.label)) }
        return options
    }

    private func save() {
        guard form.check([
            ("petName", !pet.isLinked && draft.name.nonEmpty == nil ? L("Add the pet name first.") : nil),
            ("weight", draft.weightInvalid ? L("Write the weight as a number, e.g. 12.5") : nil),
        ]) else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                let _: ClientsClient = try await API.patch("/provider-client-pets/\(pet.id)", body: draft.body(linked: pet.isLinked, withPreferred: pet.isLinked))
                if let photo = draft.photo.data, !pet.isLinked {
                    do { let _: EmptyResponse = try await ImageUpload.upload(photo, to: "/provider-client-pets/\(pet.id)/photo") }
                    catch { Toast.error(L("Pet details were saved, but the pet photo upload failed. You can add it again later.")) }
                }
                Toast.show(LF("%@ was updated for %@.", pet.isLinked ? pet.petName : draft.name.trimmingCharacters(in: .whitespaces), clientName))
                announceDataChanged()
                onSaved()
                dismiss()
            } catch {
                form.apply(error, known: clientsFieldKeys)
            }
        }
    }
}

// MARK: - The family's profile, where it differs

private struct ClientsFamilyDifferences: Decodable {
    let differences: [ClientsFamilyDifference]?
}

/// One field the family's PawMiaw profile says differently (weight in grams, birthday as a day).
struct ClientsFamilyDifference: Decodable, Identifiable, Hashable {
    let field: String
    let clinic: JSONValue?
    let family: JSONValue?

    var id: String { field }

    var label: String {
        switch field {
        case "breed": L("Breed")
        case "sex": L("Sex")
        case "birthDate": L("Birthday")
        case "weight": L("Weight")
        case "isNeutered": L("Neutered or spayed")
        default: L("Microchip")
        }
    }

    func text(_ value: JSONValue?) -> String {
        guard let value, !value.isNull else { return "—" }
        switch field {
        case "sex": return ClientsText.sex(value.string) ?? "—"
        case "birthDate": return ClientsMatches.fullDay(value.string)
        case "weight": return ClientsMatches.weight(value.double) ?? "—"
        case "isNeutered": return value.bool == true ? L("Yes") : L("No")
        default: return value.string ?? "—"
        }
    }
}

// MARK: - Old names Money still calls (delete when Money uses PhotoField / ImageUpload)

