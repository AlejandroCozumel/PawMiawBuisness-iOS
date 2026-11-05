//
//  AuditHistoryCard.swift
//  PawMiawNegocios
//
//  Every change to one thing and who made it (`GET /audit-events`), for any
//  entity (web components/app/audit-history-panel.tsx, olfato/olfato-access.tsx):
//  20 at a time with "Show more entries", the count from the server's total,
//  each entry opening to its field-by-field changes (Spanish reads the
//  server's action and field codes), the signature kept with a closing, and
//  optional chips that narrow it to one part of a page. On a pet's history,
//  who asked Olfato AI about the pet joins the changes by time (one line per
//  question, never its text); the same Olfato line is the team's log.
//
//  Used by Clients (a client, a pet's chart, an invitation), Records (a
//  record), Team (a staff member, Availability, Settings) and Team's Olfato
//  AI log and member card (`OlfatoAccessLine`).
//

import SwiftUI

// MARK: - What the server sends

struct AuditChange: Codable, Hashable {
    let field: String?
    let label: String?
    let before: JSONValue?
    let after: JSONValue?
    let type: String?
    /// Its values are not shown (a PIN, a secret): only that it changed.
    let sensitive: Bool?
}

struct AuditEntry: Codable, Identifiable, Hashable {
    let id: String
    let occurredAt: String?
    let action: String?
    let actionLabel: String?
    let outcome: String?
    let summary: String?
    let actorDisplayName: String?
    let source: String?
    let changes: [AuditChange]?
    let metadata: [String: JSONValue]?
}

/// A part of a page a history's chips narrow it to (Settings: profile, contact, services…), by the
/// server's action names that change it.
struct AuditArea: Hashable {
    let key: String
    let label: String
    let actions: [String]
}

/// A tool or an area of an Olfato AI question as people read it ("Finanzas del negocio").
struct OlfatoAreaRef: Decodable, Hashable {
    let name: String?
    let area: String?
    let label: InboxOlfatoWords?
}

/// One question to Olfato AI in a log. Never its text.
struct OlfatoAccessEntry: Decodable, Identifiable, Hashable {
    struct Member: Decodable, Hashable {
        let id: String?
        let name: String?
        let isYou: Bool?
        /// No longer on the team: the line stays, by name.
        let left: Bool?
    }
    struct Pet: Decodable, Hashable {
        let id: String
        let name: String?
    }
    let id: String
    let at: String?
    /// The day in the workspace's calendar (YYYY-MM-DD).
    let day: String?
    let member: Member?
    let way: String?
    let chatId: String?
    let tools: [OlfatoAreaRef]?
    let refused: [OlfatoAreaRef]?
    let pets: [Pet]?
}

/// How an Olfato AI log line says things (web lib/olfato-access.ts).
enum OlfatoAccessWords {
    /// Who asked: "You", their name, or their name and that they left.
    static func personName(_ member: OlfatoAccessEntry.Member?) -> String {
        if member?.isYou == true { return L("You") }
        let name = member?.name?.trimmingCharacters(in: .whitespaces).nonEmpty ?? L("Someone")
        return member?.left == true ? LF("%@ (left the team)", name) : name
    }

    /// The kinds of information a line read, each once (two tools of one area are one kind).
    static func kinds(_ refs: [OlfatoAreaRef]?) -> [OlfatoAreaRef] {
        var seen = Set<String>()
        var out: [OlfatoAreaRef] = []
        for ref in refs ?? [] {
            let key = ref.area ?? ref.name ?? ""
            if seen.insert(key).inserted { out.append(ref) }
        }
        return out
    }

    static func words(_ ref: OlfatoAreaRef) -> String {
        ref.label?.text.nonEmpty ?? ref.area ?? ref.name ?? ""
    }
}

// MARK: - The card

struct AuditHistoryCard: View {
    let entityType: String
    let entityId: String
    var title: String = L("Audit history")
    var description: String = L("A compact record of changes, staff actions, and system updates for this item.")
    /// Folded until asked for (the web's panel); a page of its own shows it open with no fold.
    var collapsible: Bool = true
    var startsOpen: Bool = false
    var emptyText: String = L("No audit history for this record yet.")
    /// Chips that narrow it to one part; each entry links to its part with `openArea`.
    var areas: [AuditArea] = []
    var openArea: ((String) -> AnyView)? = nil
    /// A pet's history: who asked Olfato AI about it joins the changes by time.
    var olfatoPet: (id: String, name: String)? = nil

    static let pageSize = 20

    @State private var open = false
    @State private var audit: [AuditEntry] = []
    @State private var auditTotal = 0
    @State private var auditMore = false
    @State private var olfato: [OlfatoAccessEntry] = []
    @State private var olfatoTotal = 0
    @State private var olfatoMore = false
    @State private var loaded = false
    @State private var loading = false
    @State private var failed = false
    @State private var expanded: Set<String> = []
    @State private var area: String?

    private var isOpen: Bool { !collapsible || open }

    var body: some View {
        // The web's panel (audit-history-panel.tsx): the header as its own button, then the entries
        // between hairlines, edge to edge.
        VStack(alignment: .leading, spacing: 0) {
            header
            if isOpen {
                RowDivider()
                content
            }
        }
        .listCard()
        .task {
            if (!collapsible || startsOpen) && !loaded {
                open = true
                await load(reset: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pawMiawDataChanged)) { _ in
            if isOpen && loaded { Task { await load(reset: true) } }
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        let total = auditTotal + olfatoTotal
        let face = HStack(alignment: .top, spacing: 12) {
            Glyph("history", size: 16)
                .foregroundStyle(Theme.blue)
                .frame(width: 36, height: 36)
                .background(Theme.wash(Theme.aqua, 18), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.leading)
                    if loaded && total > 0 { Chip(text: "\(total)", tone: .muted, weight: .semibold) }
                }
                Text(description).font(Theme.text(14)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            if collapsible {
                Glyph("chevron-down", size: 16)
                    .foregroundStyle(Theme.inkSoft)
                    .rotationEffect(.degrees(open ? 180 : 0))
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        if collapsible {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
                if open && !loaded { Task { await load(reset: true) } }
            } label: { face.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
        } else {
            face
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !areas.isEmpty {
            CardToolbar {
                FlowLayout(spacing: 6) {
                    ForEach(areas, id: \.key) { item in
                        FilterChip(title: item.label, isSelected: area == item.key) { choose(area == item.key ? nil : item.key) }
                    }
                }
                .accessibilityLabel(L("Show changes to"))
            }
        }
        if !loaded {
            LoadingState().frame(minHeight: 120)
        } else if failed && audit.isEmpty {
            Text(L("Audit history is unavailable right now."))
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 12).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                .padding(16)
        } else if lines.isEmpty {
            if area != nil {
                EmptyState(systemImage: "shield-check", title: L("No changes to this part yet."), message: L("Choose another part, or see all of them."),
                           actionTitle: L("See all changes"), action: { choose(nil) })
            } else {
                EmptyState(systemImage: "shield-check", title: emptyText)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    if line.id != lines.first?.id { RowDivider() }
                    switch line {
                    case .audit(let item): entry(item)
                    case .olfato(let question):
                        OlfatoAccessLine(entry: question, aboutPet: olfatoPet?.name ?? "")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                    }
                }
            }
            if auditMore || olfatoMore {
                RowDivider()
                PMButton(loading ? L("Loading...") : L("Show more entries"), systemImage: "chevron-down", variant: .ghost, size: .small, isWorking: loading) {
                    Task { await load(reset: false) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
    }

    private enum Line: Identifiable {
        case audit(AuditEntry)
        case olfato(OlfatoAccessEntry)

        var id: String {
            switch self {
            case .audit(let item): "a:\(item.id)"
            case .olfato(let entry): "o:\(entry.id)"
            }
        }

        var at: String {
            switch self {
            case .audit(let item): item.occurredAt ?? ""
            case .olfato(let entry): entry.at ?? ""
            }
        }
    }

    /// Both lists by time; a line shows only once nothing still unread can be newer.
    private var lines: [Line] {
        let all = (audit.map(Line.audit) + olfato.map(Line.olfato)).sorted { $0.at > $1.at }
        let floor = [auditMore ? audit.last?.occurredAt : nil, olfatoMore ? olfato.last?.at : nil].compactMap { $0 }.max()
        guard let floor, olfatoPet != nil else { return all }
        return all.filter { $0.at >= floor }
    }

    /// One change (web `AuditEntry`): a 24 aqua disc with the chevron, the summary semibold (a
    /// pink outcome tag when it didn't succeed), when · who · from where; open, its fields in a
    /// bordered box: before and after under uppercase heads.
    private func entry(_ item: AuditEntry) -> some View {
        let isOpen = expanded.contains(item.id)
        let changes = item.changes ?? []
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isOpen { expanded.remove(item.id) } else { expanded.insert(item.id) }
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Glyph("chevron-right", size: 14)
                        .foregroundStyle(Theme.blue)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 24, height: 24)
                        .background(Theme.wash(Theme.aqua, 22), in: Circle())
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        FlowLayout(spacing: 8) {
                            Text(item.summary?.nonEmpty ?? Self.actionText(item)).font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong).multilineTextAlignment(.leading)
                            if let outcome = item.outcome, outcome != "success" {
                                TagChip(text: outcome, tone: Theme.pink, size: .sm)
                            }
                        }
                        Text([DateText.dayTime(item.occurredAt), item.actorDisplayName?.nonEmpty ?? L("System"), Self.sourceText(item.source)].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                            .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        if !isOpen && !changes.isEmpty {
                            Text(LP(changes.count, "%d field changed", "%d fields changed")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let action = item.action, let part = areas.first(where: { $0.actions.contains(action) }), let openArea {
                NavigationLink { openArea(part.key) } label: {
                    PMButtonContent(title: LF("Open %@", part.label), variant: .link, size: .slim)
                }
                .buttonStyle(.pm(.link, size: .slim))
                .padding(.leading, 40)
                .padding(.bottom, 8)
            }

            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.actionText(item)).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    RowDivider()
                    if changes.isEmpty {
                        Text(L("No field-level changes were captured for this action.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                            .padding(12)
                    }
                    ForEach(Array(changes.enumerated()), id: \.offset) { index, change in
                        if index > 0 { RowDivider() }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Self.fieldText(change)).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkStrong)
                            if change.sensitive != true {
                                (Text(L("Before").uppercased() + " ").font(.brandText(10.9, weight: .bold)).tracking(1.3).foregroundStyle(Theme.inkSoft)
                                    + Text(Self.valueText(change.before)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft))
                                (Text(L("After").uppercased() + " ").font(.brandText(10.9, weight: .bold)).tracking(1.3).foregroundStyle(Theme.inkSoft)
                                    + Text(Self.valueText(change.after)).font(Theme.text(14)).foregroundStyle(Theme.inkStrong))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    // What was signed to confirm it (a death, an archived client): the signature given then.
                    if let signatureId = item.metadata?["signatureId"]?.string?.nonEmpty {
                        RowDivider()
                        AuditSignatureFigure(signatureId: signatureId).padding(12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .listCard(.box)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                .padding(.leading, 52)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: Loading

    private func choose(_ key: String?) {
        area = key
        Task { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        guard !loading || reset else { return }
        loading = true
        defer { loading = false; loaded = true }
        let actions = areas.first { $0.key == area }?.actions ?? []
        if reset || auditMore {
            do {
                let page: Page<AuditEntry> = try await API.get("/audit-events", query: [
                    "entityType": entityType, "entityId": entityId, "limit": "\(Self.pageSize)", "offset": "\(reset ? 0 : audit.count)",
                    "actions": actions.isEmpty ? nil : actions.sorted().joined(separator: ","),
                ])
                if reset { audit = page.items } else {
                    let known = Set(audit.map(\.id))
                    audit += page.items.filter { !known.contains($0.id) }
                }
                auditTotal = page.total ?? audit.count
                auditMore = page.hasMore ?? (audit.count < auditTotal)
                failed = false
            } catch is CancellationError {
            } catch {
                failed = true
                auditMore = false
                if !audit.isEmpty { Toast.error(error) }
            }
        }
        // The Olfato AI lines are an extra: when they can't be read, the history is the changes alone.
        if let pet = olfatoPet, reset || olfatoMore {
            if let page: Page<OlfatoAccessEntry> = try? await API.get("/provider-olfato/access/pets/\(pet.id)", query: ["limit": "\(Self.pageSize)", "offset": "\(reset ? 0 : olfato.count)"]) {
                if reset { olfato = page.items } else {
                    let known = Set(olfato.map(\.id))
                    olfato += page.items.filter { !known.contains($0.id) }
                }
                olfatoTotal = page.total ?? olfato.count
                olfatoMore = page.hasMore ?? (olfato.count < olfatoTotal)
            } else {
                olfatoMore = false
            }
        }
    }

    // MARK: Words (the server names actions and fields in English; Spanish reads their codes)

    static func sourceText(_ source: String?) -> String? {
        guard let source = source?.nonEmpty else { return nil }
        switch source {
        case "web": return L("Web")
        case "api": return L("API")
        default: return source.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
    }

    /// English reads the server's label; Spanish builds "Cliente · perfil: actualizado" from the action code.
    static func actionText(_ item: AuditEntry) -> String {
        guard LocalizationManager.shared.currentLanguage == .spanish, let action = item.action?.nonEmpty else { return item.actionLabel ?? item.action ?? "" }
        var parts = action.split(separator: ".").map(String.init)
        guard let entity = parts.first else { return item.actionLabel ?? action }
        parts.removeFirst()
        let verb = parts.popLast()
        let subject = ([esEntities[entity] ?? entity.replacingOccurrences(of: "_", with: " ")] + parts.map { esParts[$0] ?? $0.replacingOccurrences(of: "_", with: " ") }).joined(separator: " · ")
        guard let verb else { return subject }
        return "\(subject): \(esVerbs[verb] ?? verb.replacingOccurrences(of: "_", with: " "))"
    }

    static func fieldText(_ change: AuditChange) -> String {
        if LocalizationManager.shared.currentLanguage == .spanish, let field = change.field, let spanish = esFields[field] { return spanish }
        return change.label?.nonEmpty ?? change.field ?? "—"
    }

    static func valueText(_ value: JSONValue?) -> String {
        guard let value else { return L("Empty") }
        switch value {
        case .null: return L("Empty")
        case .string(let text): return text.isEmpty ? L("Empty") : text
        case .bool(let flag): return flag ? L("Yes") : L("No")
        case .number(let number): return number.formatted(.number.locale(.app))
        case .array, .object:
            guard let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) else { return L("Captured value") }
            return text
        }
    }

    // The Spanish tables (audit-history-panel.tsx).
    private static let esEntities: [String: String] = [
        "provider_appointment": "Cita", "appointment": "Cita", "provider_client": "Cliente", "provider_client_invitation": "Invitación",
        "provider_invoice": "Cuenta", "provider_pet": "Mascota", "pet": "Mascota", "provider_record": "Registro", "provider_store": "Tienda",
        "provider_catalog": "Catálogo", "provider_inventory": "Inventario", "provider_stay": "Estancia", "provider_follow_up": "Seguimiento",
        "household": "Hogar", "routine": "Rutina", "conversation": "Conversación", "provider_room": "Espacio", "client": "Cliente",
    ]

    private static let esParts: [String: String] = [
        "confirmation": "confirmación", "attachment": "archivo", "profile": "perfil", "weight": "peso", "photo": "foto", "record": "registro",
        "settings": "ajustes", "register": "caja", "stock": "inventario", "sale": "venta", "item": "artículo", "invite": "invitación",
        "message": "mensaje", "cabinet": "botiquín", "document": "documento", "routine_log": "bitácora", "checkin": "registro",
        "report": "reporte", "note": "nota", "death": "fallecimiento",
    ]

    private static let esVerbs: [String: String] = [
        "created": "creado", "updated": "actualizado", "deleted": "eliminado", "accessed": "consultado", "added": "agregado", "removed": "quitado",
        "uploaded": "subido", "attachment_uploaded": "archivo subido", "attachment_deleted": "archivo eliminado", "accepted": "aceptada",
        "expired": "vencida", "resent": "reenviada", "revoked": "revocada", "requested": "solicitada", "client_confirmed": "confirmada por el cliente",
        "link_opened": "enlace abierto", "cancellation_requested": "cancelación solicitada", "reschedule_requested": "cambio de hora solicitado",
        "sync_completed": "sincronizado", "update_rejected": "cambio rechazado", "completed": "completado", "downloaded": "descargado",
        "opened": "abierta", "closed": "cerrada", "cash_moved": "movimiento de efectivo", "received": "recibido", "returned": "devuelta",
        "signed": "firmado", "amended": "corregido", "checked_in": "llegada registrada", "started": "empezada", "finished": "terminada",
        "cancelled": "cancelada", "no_show": "no llegó", "rebooked": "reagendada", "reopened": "reabierta", "moved": "movida",
        "recorded": "registrado", "archived": "en archivo", "restored": "de vuelta en las listas", "moved_out": "pasó a otro cliente",
        "moved_in": "llegó de otro cliente", "discarded": "descartado", "reminded": "recordado",
    ]

    private static let esFields: [String: String] = [
        "status": "Estado", "startsAt": "Inicio", "endsAt": "Fin", "room": "Espacio", "roomId": "Espacio", "notes": "Notas",
        "serviceLabel": "Servicio", "serviceId": "Servicio", "serviceCategory": "Tipo de servicio", "assignedOrganizationMemberId": "Asignado a",
        "confirmationStatus": "Confirmación", "title": "Título", "summary": "Resumen", "details": "Detalles", "internalNote": "Nota interna",
        "eventAt": "Fecha", "followUpAt": "Seguimiento", "payload": "Datos", "recordType": "Tipo de registro", "ownerName": "Nombre",
        "ownerLastName": "Apellido", "ownerEmail": "Correo", "ownerPhone": "Teléfono", "petName": "Nombre de la mascota", "petBreed": "Raza",
        "petSpecies": "Especie", "weight": "Peso", "sex": "Sexo", "birthDate": "Nacimiento", "microchipNumber": "Microchip", "photoUrl": "Foto",
        "totalAmount": "Total", "amountPaid": "Pagado", "balanceDueAmount": "Saldo", "dueAt": "Vence", "name": "Nombre", "capacity": "Capacidad",
        "doubleBooked": "Doble reserva", "hoursOverride": "Fuera del horario", "arrivalNote": "Nota de llegada", "cancelReason": "Motivo de cancelación",
    ]
}

/// The signature kept with an archive or a death (an audit entry's `signatureId`).
private struct AuditSignatureFigure: View {
    private struct Kept: Decodable {
        let imageDataUrl: String?
        let signerName: String?
        let byName: String?
        let signedAt: String?
        let createdAt: String?
    }

    let signatureId: String
    @State private var kept: Kept?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let kept, let image = SignatureRules.image(kept.imageDataUrl) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 80)
                    .padding(6).background(Color.white, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                let who = kept.signerName?.nonEmpty ?? kept.byName?.nonEmpty
                let day = DateText.date(kept.signedAt ?? kept.createdAt)
                Text(who.map { LF("Signed by %1$@ on %2$@", $0, day) } ?? LF("Signed on %@", day)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            }
        }
        .task { kept = try? await API.get("/provider-closing-signatures/\(signatureId)") }
    }
}

// MARK: - One Olfato AI question

/// One question: who (unless the list is one person's), the way in, when and what it read. On a
/// pet's history (`aboutPet`) it reads "Ana asked Olfato AI about Luna", with the kinds on the date line.
struct OlfatoAccessLine: View {
    let entry: OlfatoAccessEntry
    var showPerson: Bool = true
    /// The pet whose history this line is in.
    var aboutPet: String? = nil
    /// Narrow the list to this pet (the team's log).
    var onPickPet: ((OlfatoAccessEntry.Pet) -> Void)? = nil
    /// Narrow the list to this person (the team's log).
    var onPickMember: ((String) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image("OlfatoFace").resizable().scaledToFit()
                .padding(4)
                .frame(width: 32, height: 32)
                .background(Theme.wash(Theme.aqua, 35), in: Circle())
                .accessibilityHidden(true)
            if let aboutPet { petLine(aboutPet) } else { logLine }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private func petLine(_ petName: String) -> some View {
        let pet = petName.trimmingCharacters(in: .whitespaces).nonEmpty ?? L("a pet")
        let refused = OlfatoAccessWords.kinds(entry.refused).map(OlfatoAccessWords.words)
        return VStack(alignment: .leading, spacing: 4) {
            Text(entry.member?.isYou == true ? LF("You asked Olfato AI about %@", pet) : LF("%1$@ asked Olfato AI about %2$@", OlfatoAccessWords.personName(entry.member), pet))
                .font(Theme.text(16, weight: .semibold)).foregroundStyle(Theme.inkStrong)
            Text(([DateText.dayTime(entry.at)] + OlfatoAccessWords.kinds(entry.tools).map(OlfatoAccessWords.words)).filter { !$0.isEmpty }.joined(separator: " · "))
                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            if !refused.isEmpty { HueChip(text: LF("Not open to them: %@", refused.joined(separator: ", ")), hue: .butter) }
        }
    }

    private var logLine: some View {
        let kinds = OlfatoAccessWords.kinds(entry.tools)
        let refused = OlfatoAccessWords.kinds(entry.refused)
        let pets = entry.pets ?? []
        let way = entry.way == "pet" ? L("From a pet") : L("About the business")
        return VStack(alignment: .leading, spacing: 4) {
            if showPerson {
                HStack(spacing: 4) {
                    if let onPickMember, let id = entry.member?.id {
                        Button(OlfatoAccessWords.personName(entry.member)) { onPickMember(id) }
                            .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                            .accessibilityLabel(LF("Show only %@", OlfatoAccessWords.personName(entry.member)))
                    } else {
                        Text(OlfatoAccessWords.personName(entry.member)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    }
                    Text("· \(way)").font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            } else {
                Text(way).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
            }
            Text(DateText.dayTime(entry.at)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
            if !pets.isEmpty || !kinds.isEmpty || !refused.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(pets, id: \.id) { pet in
                        let name = pet.name?.trimmingCharacters(in: .whitespaces).nonEmpty ?? L("a pet")
                        if let onPickPet {
                            Button { onPickPet(pet) } label: { HueChip(text: name, hue: .sky, systemImage: "pawprint.fill") }
                                .buttonStyle(.plain)
                                .accessibilityLabel(LF("Pet: %@", name))
                        } else {
                            HueChip(text: name, hue: .sky, systemImage: "pawprint.fill")
                        }
                    }
                    ForEach(kinds, id: \.self) { kind in HueChip(text: OlfatoAccessWords.words(kind), hue: .grey) }
                    if !refused.isEmpty {
                        HueChip(text: LF("Not open to them: %@", refused.map(OlfatoAccessWords.words).joined(separator: ", ")), hue: .butter)
                    }
                }
            }
        }
    }
}
