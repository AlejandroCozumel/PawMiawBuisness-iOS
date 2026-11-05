//
//  TeamMemberCredentials.swift
//  PawMiawNegocios
//
//  A team member's professional credentials (web:
//  components/app/prescriptions/credentials-card.tsx and credential-sheet.tsx):
//  type, number, state, whether it is verified and whether it lets them
//  prescribe here; add one or change it, declare it, record the registry
//  check, remove it. At a clinic it is what lets someone sign prescriptions;
//  elsewhere it lists certifications. Every change is audited by the server.
//  The add/change sheet is the one credential sheet: Home's welcome and
//  setup checklist open it for the person's own ("me") credentials too.
//

import SwiftUI

struct TeamCredential: Decodable, Identifiable, Hashable {
    struct Words: Decodable, Hashable { let es: String?; let en: String? }
    struct Registry: Decodable, Hashable { let url: String?; let label: String? }
    let id: String
    let type: String?
    let label: Words?
    let number: String?
    let region: String?
    let registeredAddress: String?
    let issuer: String?
    let title: String?
    let expiresOn: String?
    let status: String?
    let verified: Bool?
    let prescribesHere: Bool?
    let allowsControlled: Bool?
    let registry: Registry?
    let declaredAt: String?
    let registryCheckedAt: String?
    let registryCheckedByName: String?
}

private struct TeamMemberCredentials: Decodable {
    let items: [TeamCredential]?
    let canPrescribe: Bool?
}

/// The credential types and the rules the form shares with the server (web: lib/prescriptions.ts).
enum TeamCredentialRules {
    static let types = ["cedula_profesional", "state_license", "dea", "other_license", "state_controlled", "usda_accreditation", "vet_tech_license", "certification"]
    /// Types that carry a US state.
    static let stateTypes: Set<String> = ["state_license", "state_controlled", "vet_tech_license"]
    /// A US veterinary technician's designation.
    static let designations = ["RVT", "LVT", "CVT", "LVMT"]

    static func label(_ type: String) -> String {
        switch type {
        case "cedula_profesional": L("Cédula profesional")
        case "state_license": L("State license")
        case "dea": L("DEA number")
        case "other_license": L("Other professional license")
        case "state_controlled": L("State controlled-substance registration")
        case "usda_accreditation": L("USDA accreditation")
        case "vet_tech_license": L("Vet tech license (RVT, LVT, CVT)")
        case "certification": L("Certification")
        default: type
        }
    }

    /// Offered first in this country; the rest follow.
    static func suggested(_ country: String?) -> [String] {
        switch country?.uppercased() {
        case "MX": ["cedula_profesional", "other_license"]
        case "US": ["state_license", "dea", "state_controlled", "usda_accreditation", "other_license"]
        default: ["other_license"]
        }
    }

    static func ordered(_ country: String?) -> [String] {
        let first = suggested(country)
        return first + types.filter { !first.contains($0) }
    }

    static func numberLabel(_ type: String) -> String {
        switch type {
        case "cedula_profesional": L("Cédula number")
        case "dea": L("DEA number")
        case "state_controlled": L("Registration number")
        case "usda_accreditation": L("Accreditation number")
        case "certification": L("Number (optional)")
        default: L("License number")
        }
    }

    static func note(_ type: String) -> String? {
        switch type {
        case "dea": L("Only for controlled substances; it is printed only on those prescriptions.")
        case "state_controlled": L("Optional. Some states ask for their own registration, besides the DEA, to prescribe controlled substances.")
        case "usda_accreditation": L("Optional. For official health certificates (travel, interstate and export).")
        case "vet_tech_license": L("Optional. Your credential as a veterinary technician; it doesn’t let you prescribe.")
        case "certification": L("Optional. Shown on your profile in this workspace.")
        default: nil
        }
    }

    static func registry(_ type: String) -> (url: String, label: String)? {
        switch type {
        case "cedula_profesional": ("https://www.cedulaprofesional.sep.gob.mx/", L("Look it up in the Registro Nacional de Profesionistas (SEP)"))
        case "state_license", "vet_tech_license": ("https://www.aavsb.org/public-resources/look-up-a-license/", L("Look it up with the state board (AAVSB directory)"))
        case "dea": ("https://www.deadiversion.usdoj.gov/", L("DEA Diversion Control Division"))
        case "usda_accreditation": ("https://www.aphis.usda.gov/nvap", L("USDA National Veterinary Accreditation Program"))
        default: nil
        }
    }

    static let usStates: [(code: String, name: String)] = [
        ("AL", "Alabama"), ("AK", "Alaska"), ("AZ", "Arizona"), ("AR", "Arkansas"), ("CA", "California"), ("CO", "Colorado"),
        ("CT", "Connecticut"), ("DE", "Delaware"), ("DC", "District of Columbia"), ("FL", "Florida"), ("GA", "Georgia"),
        ("HI", "Hawaii"), ("ID", "Idaho"), ("IL", "Illinois"), ("IN", "Indiana"), ("IA", "Iowa"), ("KS", "Kansas"),
        ("KY", "Kentucky"), ("LA", "Louisiana"), ("ME", "Maine"), ("MD", "Maryland"), ("MA", "Massachusetts"),
        ("MI", "Michigan"), ("MN", "Minnesota"), ("MS", "Mississippi"), ("MO", "Missouri"), ("MT", "Montana"),
        ("NE", "Nebraska"), ("NV", "Nevada"), ("NH", "New Hampshire"), ("NJ", "New Jersey"), ("NM", "New Mexico"),
        ("NY", "New York"), ("NC", "North Carolina"), ("ND", "North Dakota"), ("OH", "Ohio"), ("OK", "Oklahoma"),
        ("OR", "Oregon"), ("PA", "Pennsylvania"), ("PR", "Puerto Rico"), ("RI", "Rhode Island"), ("SC", "South Carolina"),
        ("SD", "South Dakota"), ("TN", "Tennessee"), ("TX", "Texas"), ("UT", "Utah"), ("VT", "Vermont"), ("VA", "Virginia"),
        ("WA", "Washington"), ("WV", "West Virginia"), ("WI", "Wisconsin"), ("WY", "Wyoming"),
    ]

    /// The state a US license starts from: the two-letter code or the name of a state in the business's address.
    static func state(fromAddress address: String?) -> String? {
        guard let address = address?.nonEmpty else { return nil }
        let codes = Set(usStates.map(\.code))
        let upper = address.uppercased()
        let found = upper.matches(of: #/\b([A-Z]{2})\b(?:\s+\d{5})?/#).map { String($0.output.1) }.filter { codes.contains($0) }
        if let last = found.last { return last }
        let lower = address.lowercased()
        return usStates.first { lower.contains($0.name.lowercased()) }?.code
    }

    /// A DEA number: two letters and seven digits, the last one a check digit.
    static func deaValid(_ value: String) -> Bool {
        let cleaned = value.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "").uppercased()
        guard let match = cleaned.wholeMatch(of: #/([A-Z])([A-Z9])(\d{7})/#), "ABCDEFGHJKLMPRSTUX".contains(match.output.1) else { return false }
        let d = match.output.3.compactMap { $0.wholeNumberValue }
        guard d.count == 7 else { return false }
        return (d[0] + d[2] + d[4] + 2 * (d[1] + d[3] + d[5])) % 10 == d[6]
    }

    /// The field a problem belongs to and what the form says before the server does.
    static func problem(type: String, number: String, region: String, address: String, issuer: String, title: String) -> (field: String, message: String)? {
        func message(_ code: String) -> String { Self.message(code) ?? L("The credential couldn’t be saved.") }
        let number = number.trimmingCharacters(in: .whitespaces)
        if type == "certification" {
            return title.trimmingCharacters(in: .whitespaces).count < 2 ? ("title", message("title_required")) : nil
        }
        if number.isEmpty { return ("number", message("number_required")) }
        if (type == "state_controlled" || type == "vet_tech_license") && region.isEmpty { return ("region", message("state_required")) }
        if type == "vet_tech_license" && !designations.contains(issuer.trimmingCharacters(in: .whitespaces).uppercased()) { return ("designation", message("designation_invalid")) }
        if type == "cedula_profesional" {
            let digits = number.filter { !" .-".contains($0) }
            if digits.wholeMatch(of: #/\d{6,8}/#) == nil { return ("number", message("cedula_format")) }
        }
        if type == "state_license" && region.isEmpty { return ("region", message("state_required")) }
        if type == "dea" && !deaValid(number) { return ("number", message("dea_format")) }
        if type == "dea" && address.trimmingCharacters(in: .whitespaces).isEmpty { return ("address", message("dea_address_required")) }
        if type == "other_license" && issuer.trimmingCharacters(in: .whitespaces).isEmpty { return ("issuer", message("issuer_required")) }
        return nil
    }

    /// The server's refusals, by code (web: PRESCRIPTION_ERROR_MESSAGES).
    static func message(_ code: String) -> String? {
        switch code {
        case "number_required": L("Type the number.")
        case "cedula_format": L("A cédula profesional has 6 to 8 digits.")
        case "state_required": L("Choose the state that issued the license.")
        case "state_invalid": L("That isn’t a US state.")
        case "license_format": L("That license number doesn’t look right.")
        case "dea_format": L("That isn’t a valid DEA number (two letters and seven digits).")
        case "dea_address_required": L("Add the address the DEA registration is for.")
        case "issuer_required": L("Say who issued the license.")
        case "other_format": L("The number must have 3 to 40 characters.")
        case "usda_format": L("That USDA accreditation number doesn’t look right.")
        case "designation_invalid": L("Choose RVT, LVT, CVT or LVMT.")
        case "title_required": L("Type the certification’s name.")
        case "expires_invalid": L("The expiry date must be a date.")
        case "credential_exists": L("This credential is already on the list.")
        case "declaration_self_only": L("Only the professional can declare a credential is theirs.")
        case "forbidden": L("You don’t have permission to do this.")
        default: nil
        }
    }

    /// Which field a refusal code points at.
    static func field(_ code: String) -> String? {
        switch code {
        case "number_required", "cedula_format", "license_format", "dea_format", "other_format", "usda_format": "number"
        case "state_required", "state_invalid": "region"
        case "dea_address_required": "address"
        case "issuer_required": "issuer"
        case "designation_invalid": "designation"
        case "title_required": "title"
        case "expires_invalid": "expires"
        default: nil
        }
    }
}

struct TeamCredentialsCard: View {
    let memberId: String
    let isSelf: Bool
    let canEdit: Bool
    /// A clinic: say whether they can prescribe. Elsewhere it lists certifications.
    let prescribing: Bool
    /// Their name, for the sheet's "For …" line.
    var memberName: String? = nil

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.openURL) private var openURL
    @State private var data: TeamMemberCredentials?
    @State private var failed = false
    @State private var busy: String?
    @State private var removing: TeamCredential?
    @State private var sheet: TeamCredentialTarget?

    private var editable: Bool { canEdit || isSelf }

    var body: some View {
        TeamPanel(
            title: prescribing ? L("Professional credentials") : L("Certifications and licenses"),
            subtitle: !prescribing ? L("Shown on this profile in the workspace.") : ((data?.canPrescribe ?? false) ? L("Can sign prescriptions here.") : L("Needs a credential valid in this country to sign prescriptions.")),
            systemImage: "id-card",
            tint: Theme.aqua
        ) {
            if editable {
                PMButton(L("Add"), systemImage: "plus", variant: .outline) { sheet = TeamCredentialTarget(credential: nil) }
            }
        } content: {
            if data == nil {
                if failed {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Something went wrong. Try again.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                        PMButton(L("Try again"), variant: .outline, size: .compact) { Task { await load() } }
                    }
                } else { ProgressView().frame(maxWidth: .infinity, minHeight: 64) }
            } else if (data?.items ?? []).isEmpty {
                EmptyState(systemImage: "id-card", title: isSelf && prescribing ? L("Add your cédula profesional or license so you can sign prescriptions.") : L("No credentials yet."), accent: Theme.pink)
            } else {
                VStack(spacing: 8) {
                    ForEach(data?.items ?? []) { credential in row(credential) }
                }
            }
            TeamLegalReviewNote()
        }
        .task(id: memberId) { await load() }
        .sheet(item: $removing) { credential in
            ConfirmSheet(title: L("Remove"), message: name(credential), confirmTitle: L("Remove"), destructive: true) { _ in
                try await API.send("DELETE", "/provider-members/\(memberId)/credentials/\(credential.id)")
                Toast.show(L("Credential removed."))
                await load()
            }
        }
        .sheet(item: $sheet) { target in
            TeamCredentialSheet(
                memberId: memberId,
                memberName: memberName,
                isSelf: isSelf,
                country: workspace.current?.country,
                businessAddress: workspace.current?.address,
                credential: target.credential
            ) { await load() }
        }
    }

    private func name(_ credential: TeamCredential) -> String {
        if credential.type == "certification", let title = credential.title.nonEmpty { return title }
        let words = LocalizationManager.shared.currentLanguage == .spanish ? credential.label?.es : credential.label?.en
        return words.nonEmpty ?? credential.type.map { TeamCredentialRules.label($0) } ?? ""
    }


    private func row(_ credential: TeamCredential) -> some View {
        let facts = [
            credential.issuer.nonEmpty,
            credential.registeredAddress.nonEmpty,
            credential.expiresOn.map { LF("Expires %@", DateText.date($0)) },
            credential.declaredAt.map { LF("Declared %@", DateText.date($0)) },
            credential.registryCheckedAt != nil ? LF("Checked in the registry by %@", credential.registryCheckedByName ?? "—") : nil,
        ].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 4) {
            FlowLayout(spacing: 8) {
                Text(name(credential)).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                TeamCredentialStatusChip(status: credential.status, verified: credential.verified)
                if credential.prescribesHere ?? false { Chip(text: L("Prescribes here"), tone: .custom(Theme.blue), icon: "badge-check", percent: 14, weight: .heavy) }
                if credential.allowsControlled ?? false { Chip(text: L("Controlled substances"), tone: .custom(Theme.coral), percent: 14, weight: .heavy) }
            }
            if credential.number.nonEmpty != nil || credential.region.nonEmpty != nil {
                Text([credential.region.nonEmpty, credential.number.nonEmpty].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 14, design: .monospaced)).foregroundStyle(Theme.inkStrong)
            }
            if !facts.isEmpty { Text(facts.joined(separator: " · ")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
            FlowLayout(spacing: 6) {
                if let link = credential.registry?.url, let url = URL(string: link) {
                    PMButton(L("Official registry"), systemImage: "external-link", variant: .outline, size: .compact) { openURL(url) }
                }
                if isSelf && credential.declaredAt == nil {
                    PMButton(L("Declare it is mine"), systemImage: "badge-check", size: .compact, isWorking: busy == credential.id) { act(credential, "declare") }
                }
                if editable && credential.registry != nil && credential.registryCheckedAt == nil {
                    PMButton(L("I checked the registry"), systemImage: "search-check", variant: .outline, size: .compact, isWorking: busy == credential.id) { act(credential, "registry-check") }
                }
                if editable {
                    PMButton(L("Change"), systemImage: "pencil", variant: .outline, size: .compact) { sheet = TeamCredentialTarget(credential: credential) }
                    PMButton(L("Remove"), systemImage: "trash-2", variant: .destructive, size: .compact) { removing = credential }
                }
            }
            .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
    }

    private func load() async {
        do { data = try await API.get("/provider-members/\(memberId)/credentials"); failed = false } catch { failed = data == nil }
    }

    private func act(_ credential: TeamCredential, _ action: String) {
        busy = credential.id
        Task {
            defer { busy = nil }
            do {
                try await API.send("POST", "/provider-members/\(memberId)/credentials/\(credential.id)/\(action)", body: [:])
                Toast.show(action == "declare" ? L("Declared. The credential is verified.") : L("Registry check recorded."))
                await load()
            } catch {
                Toast.error((error as? APIError)?.code.flatMap { TeamCredentialRules.message($0) } ?? errorText(error))
            }
        }
    }
}

/// A credential's state, the same wherever it is listed (a staff page, the welcome).
struct TeamCredentialStatusChip: View {
    let status: String?
    var verified: Bool? = nil

    var body: some View {
        // The web's CredentialStatusChip: the state's tone at 26%, its icon, 11.2 extrabold.
        switch status {
        case "verified": Chip(text: L("Verified"), tone: .custom(Theme.lime), icon: "badge-check", percent: 26, weight: .heavy)
        case "unverified": Chip(text: L("Not declared yet"), tone: .custom(Theme.mango), icon: "circle-dashed", percent: 26, weight: .heavy)
        case "expired": Chip(text: L("Expired@credential"), tone: .custom(Theme.coral), icon: "file-warning", percent: 26, weight: .heavy)
        case "invalid": Chip(text: L("Check the number"), tone: .custom(Theme.coral), icon: "file-warning", percent: 26, weight: .heavy)
        case "removed": Chip(text: L("Removed@credential"), tone: .custom(Theme.inkSoft), icon: "file-warning", percent: 26, weight: .heavy)
        default:
            if verified == true { Chip(text: L("Verified"), tone: .custom(Theme.lime), icon: "badge-check", percent: 26, weight: .heavy) }
            else { Chip(text: L("Not declared yet"), tone: .custom(Theme.mango), icon: "circle-dashed", percent: 26, weight: .heavy) }
        }
    }
}

/// The legal wording and fields follow public sources and must be reviewed by a professional (the app says so).
struct TeamLegalReviewNote: View {
    var body: some View {
        Text(L("The prescription fields and wording follow public sources (NOM-064-ZOO-2000 in Mexico; the AVMA, the DEA and state boards in the United States). Have a professional review them before you rely on them."))
            .font(Theme.text(12)).foregroundStyle(Theme.inkStrong)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wash(Theme.mango, 12), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
    }
}

private struct TeamCredentialTarget: Identifiable {
    let id = UUID()
    let credential: TeamCredential?
}

private struct TeamCredentialSaved: Decodable {
    let id: String
    let verified: Bool?
}

/// Adds (or changes) a professional credential. The country decides what is
/// offered first: the cédula profesional in Mexico, a state license (the
/// state taken from the business's address) and the DEA number in the US,
/// another license anywhere else. Only the professional declares it is
/// theirs: that declaration, with the format check and the registry link,
/// makes it "verificada". `memberId` "me" is the person's own (Home's
/// welcome and checklist); `types` narrows it to what a place asks for.
struct TeamCredentialSheet: View {
    let memberId: String
    var memberName: String? = nil
    let isSelf: Bool
    let country: String?
    let businessAddress: String?
    var credential: TeamCredential? = nil
    /// Only these types (the welcome's "Add" for one type); nil = every type, the country's first.
    var types: [String]? = nil
    /// Why it is asked, shown first.
    var reason: String? = nil
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var form = FormState()
    @State private var type = ""
    @State private var number = ""
    @State private var region = ""
    @State private var address = ""
    @State private var issuer = ""
    @State private var title = ""
    @State private var expires: Date?
    @State private var declare = false
    @State private var started = false
    @State private var saving = false

    private var editing: Bool { credential != nil }
    private var offered: [String] { types.flatMap { $0.isEmpty ? nil : $0 } ?? TeamCredentialRules.ordered(country) }
    private var hasState: Bool { TeamCredentialRules.stateTypes.contains(type) }
    /// A vet tech's designation lives where other licenses keep their issuer.
    private var designation: String { type == "vet_tech_license" ? (issuer.trimmingCharacters(in: .whitespaces).uppercased().nonEmpty ?? "RVT") : issuer }
    private var dirty: Bool {
        guard started else { return false }
        if let credential {
            return number != (credential.number ?? "") || region != (credential.region ?? "") || address != (credential.registeredAddress ?? "") || issuer != (credential.issuer ?? "") || title != (credential.title ?? "") || expiresKey != credential.expiresOn
        }
        return !number.isEmpty || !issuer.isEmpty || !title.isEmpty || expires != nil
    }
    private var expiresKey: String? { expires.map { TeamDays.key(picked: $0) } }

    var body: some View {
        ProviderModal(
            title: editing ? L("Change credential") : L("Add a professional credential"),
            subtitle: memberName.nonEmpty.map { LF("For %@", $0) } ?? (offered.count == 1 && !editing ? TeamCredentialRules.label(type) : nil),
            systemImage: "id-card",
            accent: .aqua,
            isDirty: dirty,
            form: form,
            primaryTitle: editing ? L("Save changes") : L("Save credential"),
            isWorking: saving,
            primaryIcon: "badge-check"
        ) {
            save()
        } content: {
            if let reason { NoticeCard(tone: .info, title: reason) }
            if !editing {
                if offered.count > 1 {
                    FormField(label: L("Type"), key: "type", form: form) {
                        FlowLayout(spacing: 6) {
                            ForEach(offered, id: \.self) { value in
                                FilterChip(title: TeamCredentialRules.label(value), isSelected: type == value) { type = value; form.errors = [:] }
                            }
                        }
                    }
                }
                if let note = TeamCredentialRules.note(type) {
                    Text(note).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            if type == "certification" {
                PMTextField(L("Certification"), text: $title, key: "title", form: form, prompt: L("e.g. Fear Free Certified, Certified Master Groomer"), capitalization: .words)
                PMTextField(L("Issued by"), text: $issuer, key: "issuer", form: form, prompt: L("e.g. NDGAA, Fear Free, CCPDT"), hint: L("Optional."))
            }
            if type == "vet_tech_license" {
                MenuField(label: L("Designation"), options: TeamCredentialRules.designations.map { ($0, $0) }, selection: Binding(get: { designation }, set: { issuer = $0 }), key: "designation", form: form)
            }
            PMTextField(
                TeamCredentialRules.numberLabel(type),
                text: $number,
                key: "number",
                form: form,
                prompt: type == "cedula_profesional" ? "1234567" : type == "dea" ? "AB1234563" : nil,
                keyboard: type == "cedula_profesional" ? .numberPad : .asciiCapable,
                capitalization: .characters
            )
            if hasState {
                MenuField(label: L("State"), options: [("", L("Choose the state"))] + TeamCredentialRules.usStates.map { ($0.code, $0.name) }, selection: $region, key: "region", form: form)
            }
            if type == "other_license" {
                PMTextField(L("Issued by"), text: $issuer, key: "issuer", form: form, prompt: L("e.g. Colegio de Médicos Veterinarios"))
            }
            OptionalDateField(label: L("Expires"), date: $expires, placeholder: L("Choose a day"), zone: .current,
                              defaultDate: Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date(),
                              key: "expires", form: form, hint: L("Optional. An expired credential stops counting."))
            if type == "dea" {
                PMTextField(L("Address of the DEA registration"), text: $address, key: "address", form: form, hint: L("Printed with the DEA number on controlled prescriptions."))
            }
            if let registry = TeamCredentialRules.registry(type), let url = URL(string: registry.url) {
                Button { openURL(url) } label: {
                    HStack(spacing: 6) {
                        Glyph("external-link", size: 14)
                        Text(registry.label)
                    }
                    .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                }
                .buttonStyle(.plain)
            }
            if !editing && isSelf {
                Button { declare.toggle() } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Tick(on: declare).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("I declare this credential is mine and in force")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            Text(L("Your declaration, the format check and the registry link make it verified. It is kept in the audit log.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        }
                        .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                    .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else if !editing {
                Text(LF("%@ declares it is theirs from their own account; until then it shows as not declared.", memberName.nonEmpty ?? L("The professional")))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            } else {
                Text(L("Changing the number, state or address asks for the declaration again.")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
            TeamLegalReviewNote()
        }
        .presentationDetents([.large])
        .onAppear(perform: start)
        .onChange(of: number) { form.clear("number") }
        .onChange(of: issuer) { form.clear("issuer"); form.clear("designation") }
        .onChange(of: title) { form.clear("title") }
        .onChange(of: address) { form.clear("address") }
    }

    private func start() {
        guard !started else { return }
        type = credential?.type ?? offered.first ?? "other_license"
        number = credential?.number ?? ""
        region = credential?.region ?? TeamCredentialRules.state(fromAddress: businessAddress) ?? ""
        address = credential?.registeredAddress ?? (businessAddress ?? "")
        issuer = credential?.issuer ?? ""
        title = credential?.title ?? ""
        expires = credential?.expiresOn.map { TeamDays.picked(String($0.prefix(10))) }
        declare = isSelf && credential == nil
        started = true
    }

    private func save() {
        if let problem = TeamCredentialRules.problem(type: type, number: number, region: region, address: address, issuer: designation, title: title) {
            _ = form.check([(problem.field, problem.message)])
            return
        }
        let trimmedIssuer = issuer.trimmingCharacters(in: .whitespaces)
        var body: [String: Any?] = [
            "number": number.trimmingCharacters(in: .whitespaces),
            "region": hasState ? region : nil,
            "registeredAddress": type == "dea" ? address.trimmingCharacters(in: .whitespaces) : nil,
            "issuer": type == "other_license" || type == "certification" ? trimmedIssuer.nonEmpty : (type == "vet_tech_license" ? designation.trimmingCharacters(in: .whitespaces) : nil),
            "expiresOn": expiresKey,
        ]
        if type == "certification" { body["title"] = title.trimmingCharacters(in: .whitespaces) }
        if !editing {
            body["type"] = type
            body["declare"] = isSelf && declare
        }
        saving = true
        Task {
            defer { saving = false }
            do {
                let saved: TeamCredentialSaved
                if let credential {
                    saved = try await API.patch("/provider-members/\(memberId)/credentials/\(credential.id)", body: body)
                } else {
                    saved = try await API.post("/provider-members/\(memberId)/credentials", body: body)
                }
                Toast.show((saved.verified ?? false) ? L("Credential saved and verified.") : L("Credential saved."))
                await onSaved()
                announceDataChanged()
                dismiss()
            } catch {
                if let code = (error as? APIError)?.code, let field = TeamCredentialRules.field(code), let message = TeamCredentialRules.message(code) {
                    _ = form.check([(field, message)])
                } else if let code = (error as? APIError)?.code, let message = TeamCredentialRules.message(code) {
                    Toast.error(message)
                } else {
                    Toast.error(errorText(error, fallback: L("The credential couldn’t be saved.")))
                }
            }
        }
    }
}
