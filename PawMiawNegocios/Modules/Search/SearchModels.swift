//
//  SearchModels.swift
//  PawMiawNegocios
//
//  The workspace's global search, its rules (web lib/search-palette.ts):
//  what `GET /provider-search` answers, which result groups a role opens,
//  the quick actions and pages a member may open, what this device
//  remembers, the groups in order and where each choice leads.
//

import SwiftUI

// MARK: - What the server answers

struct SearchPet: Decodable, Hashable {
    let id: String
    let clientId: String
    let name: String
    let species: String?
    let breed: String?
    let photoUrl: String?
    let status: String?
    let ownerName: String?
    /// Only when the microchip is what matched.
    let microchip: String?
    let matchedBy: String?
}

struct SearchClientPet: Decodable, Hashable {
    let id: String
    let name: String
    let species: String?
}

struct SearchClient: Decodable, Hashable {
    let id: String
    let name: String
    let email: String?
    let phone: String?
    let photoUrl: String?
    let status: String?
    let pets: [SearchClientPet]?
    let petCount: Int?
    let matchedBy: String?
}

/// A patient waiting for admission or in the hospital (opens its hospitalization).
struct SearchHospitalPatient: Decodable, Hashable {
    /// The hospitalization.
    let id: String
    let status: String?
    let emergency: Bool?
    let triagePriority: String?
    let roomName: String?
    let cageLabel: String?
    let petId: String?
    let petName: String
    let petSpecies: String?
    let petPhotoUrl: String?
    let clientId: String?
    let clientName: String?
    /// Only when the business has two or more locations.
    let locationName: String?
}

struct SearchVisit: Decodable, Hashable {
    let id: String
    let startsAt: String
    let status: String?
    let serviceLabel: String?
    let upcoming: Bool?
    let petId: String?
    let petName: String
    let petSpecies: String?
    let petPhotoUrl: String?
    let clientId: String?
    let clientName: String?
    /// Only when the business has two or more locations.
    let locationName: String?
    /// The visit's location clock.
    let timeZone: String?
}

struct SearchInvoice: Decodable, Hashable {
    let id: String
    let folio: String
    let kind: String?
    let status: String?
    let currency: String?
    /// Cents.
    let totalAmount: Int?
    /// Cents.
    let balanceDueAmount: Int?
    let date: String?
    /// Nil for a counter sale to the walk-in client.
    let clientId: String?
    let clientName: String?
    let petName: String?
    let locationName: String?
}

struct SearchGroupResult<T: Decodable & Hashable>: Decodable, Hashable {
    let items: [T]
    let hasMore: Bool?
}

/// Nil groups were not asked for, or this member's role doesn't open them.
struct SearchResponse: Decodable, Hashable {
    let query: String?
    let pets: SearchGroupResult<SearchPet>?
    let hospital: SearchGroupResult<SearchHospitalPatient>?
    let clients: SearchGroupResult<SearchClient>?
    let visits: SearchGroupResult<SearchVisit>?
    let invoices: SearchGroupResult<SearchInvoice>?

    /// Whether the server found anything at all.
    var hasResults: Bool {
        !(pets?.items.isEmpty ?? true) || !(hospital?.items.isEmpty ?? true) || !(clients?.items.isEmpty ?? true)
            || !(visits?.items.isEmpty ?? true) || !(invoices?.items.isEmpty ?? true)
    }
}

enum SearchResultGroup: String, CaseIterable {
    case pets, hospital, clients, visits, invoices
}

// MARK: - Who sees what

enum SearchRules {
    /// Which result groups a member may see — the same permissions the server checks.
    static func allowedGroups(_ w: Workspace) -> Set<SearchResultGroup> {
        var groups = Set<SearchResultGroup>()
        let clientReach = w.can(.clientsView) && w.canAny(.clientsAssignAnyone, .clientsAssignSelf)
        if clientReach && w.can(.recordsView) { groups.insert(.pets) }
        // The ward's reach: every client's patients in the hospital.
        if w.can(.hospitalView) { groups.insert(.hospital) }
        if clientReach { groups.insert(.clients) }
        if w.can(.appointmentsView) { groups.insert(.visits) }
        // Bills in search are level 1 (money access levels): a higher level includes it.
        if w.moneyLevel >= .charging { groups.insert(.invoices) }
        return groups
    }

    /// The groups whose "see all" list this member may open: the bills list is the front desk's (level 2).
    static func moreGroups(_ w: Workspace) -> Set<SearchResultGroup> {
        var groups = allowedGroups(w)
        if w.moneyLevel < .frontDesk { groups.remove(.invoices) }
        return groups
    }

    /// The actions and pages this member may open in this business.
    static func availableActions(_ w: Workspace) -> [SearchAction] {
        let categories = w.current?.enabledCategories ?? []
        let offersPharmacy = categories.isEmpty || categories.contains { ["vet", "pharmacy", "emergency"].contains($0) }
        let canManagePlan = w.current?.canManagePlan ?? false
        return SearchAction.all.filter { action in
            switch action.offer {
            case .stays where !w.offers(.boarding, .daycare, .sitter): return false
            case .grooming where !w.offers(.groomer): return false
            case .groups where !w.offers(.walker, .trainer): return false
            case .homeVisits where !w.offersHomeVisits: return false
            case .pharmacy where !offersPharmacy: return false
            default: break
            }
            if !action.needs.allSatisfy(w.can) { return false }
            if !action.anyOf.isEmpty && !action.anyOf.contains(where: w.can) { return false }
            if let money = action.money, w.moneyLevel < money, !(action.orPlanManager && canManagePlan) { return false }
            return true
        }
    }
}

// MARK: - Text

enum SearchText {
    static let minLength = 2
    /// Each group asks the server for this many.
    static let limit = 5
    /// How many actions show under results (the rest need more typing).
    static let actionsWithResults = 4

    /// Lowercase, no accents, single spaces — how both the typed text and the labels are compared.
    static func fold(_ value: String?) -> String {
        let plain = (value ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        let kept = plain.unicodeScalars.map { scalar -> Character in
            (("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)) ? Character(scalar) : " "
        }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// The text worth sending: trimmed, two characters or more, with a letter or digit in it.
    static func searchable(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= minLength && !fold(trimmed).isEmpty ? trimmed : nil
    }

    /// When a visit is, in its location's clock: "Hoy, 10:00", "Mañana, 9:30", "Ayer, 17:00",
    /// else "mar 30 sep, 10:00" (with the year when it isn't this one).
    static func visitWhen(_ iso: String, timeZone: String?) -> String {
        guard let date = DateText.parse(iso) else { return "" }
        let zone = timeZone.flatMap(TimeZone.init(identifier:)) ?? Workspace.shared.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let time = DateText.time(date, zone: zone)
        let now = Date()
        let difference = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day
        switch difference {
        case 0: return "\(L("Today")), \(time)"
        case 1: return "\(L("Tomorrow")), \(time)"
        case -1: return "\(L("Yesterday")), \(time)"
        default: break
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.locale = .app
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "EEEdMMM" : "EEEdMMMyyyy")
        return "\(formatter.string(from: date)), \(time)"
    }
}

// MARK: - Quick actions and pages

struct SearchAction: Hashable {
    enum Kind { case action, page }
    /// What the business must offer for it to show.
    enum Offer { case stays, grooming, groups, homeVisits, pharmacy }
    /// What an action opens instead of a page (the web's sheets).
    enum Opens: Hashable { case section(ProviderSection), newAppointment, newClient, newRecord }

    let id: String
    /// English; the palette translates it.
    let label: String
    /// 'action' does something ("Nueva cita"); 'page' goes somewhere ("Agenda").
    let kind: Kind
    /// The web's Lucide icon.
    let icon: String
    let opens: Opens
    /// Other words people type for it, in both languages.
    let keywords: [String]
    var needs: [Permission] = []
    /// At least one of these.
    var anyOf: [Permission] = []
    var money: MoneyLevel? = nil
    /// With `money`: the plan manager opens it too, whatever their level.
    var orPlanManager = false
    var offer: Offer? = nil

    static func == (a: SearchAction, b: SearchAction) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// web PALETTE_ACTIONS, in order.
    static let all: [SearchAction] = [
        SearchAction(id: "new-appointment", label: "New appointment", kind: .action, icon: "calendar-plus", opens: .newAppointment, keywords: ["nueva cita", "agendar", "reservar", "book", "visit", "visita", "cita"], needs: [.appointmentsCreate, .clientsView]),
        SearchAction(id: "new-client", label: "New client", kind: .action, icon: "user-plus", opens: .newClient, keywords: ["nuevo cliente", "alta", "agregar cliente", "add client", "familia", "family"], needs: [.clientsCreate, .petsCreate], anyOf: [.clientsAssignSelf, .clientsAssignAnyone]),
        SearchAction(id: "new-record", label: "New record", kind: .action, icon: "file-plus-2", opens: .newRecord, keywords: ["nuevo registro", "nota", "note", "expediente", "vacuna", "vaccine", "record"], needs: [.recordsCreate, .clientsView], anyOf: [.recordsAssignSelf, .recordsAssignAnyone]),
        SearchAction(id: "open-register", label: "Open register", kind: .action, icon: "wallet", opens: .section(.store), keywords: ["abrir caja", "caja", "turno", "register", "cash", "shift", "efectivo"], anyOf: [.salesSell, .billingRecordPayment, .registerManage]),
        SearchAction(id: "page-home", label: "Home", kind: .page, icon: "building-2", opens: .section(.home), keywords: ["inicio", "hoy", "today", "tablero"]),
        SearchAction(id: "page-agenda", label: "Schedule", kind: .page, icon: "calendar-days", opens: .section(.schedule), keywords: ["agenda", "calendario", "calendar", "citas", "appointments", "schedule"], needs: [.appointmentsView]),
        SearchAction(id: "page-stays", label: "Stays", kind: .page, icon: "bed-double", opens: .section(.stays), keywords: ["estancias", "hotel", "guarderia", "daycare", "boarding", "hospedaje"], needs: [.staysView], offer: .stays),
        SearchAction(id: "page-groups", label: "Walks & classes", kind: .page, icon: "dog", opens: .section(.groups), keywords: ["paseos", "clases", "grupal", "grupo", "paseo grupal", "clase grupal", "entrenamiento", "walks", "classes", "group", "training"], needs: [.appointmentsView], offer: .groups),
        SearchAction(id: "page-grooming", label: "Grooming", kind: .page, icon: "scissors", opens: .section(.grooming), keywords: ["estetica", "peluqueria", "bano", "corte", "groomer", "grooms", "bath", "haircut"], needs: [.appointmentsView], offer: .grooming),
        SearchAction(id: "page-home-visits", label: "Home visits", kind: .page, icon: "house", opens: .section(.homeVisits), keywords: ["domicilio", "visitas a domicilio", "a domicilio", "paseos", "paseador", "cuidador", "en casa", "ruta", "walks", "walker", "sitter", "drop-in"], anyOf: [.appointmentsView, .staysView], offer: .homeVisits),
        // One page for both: "pacientes" or "mascotas" finds it too.
        SearchAction(id: "page-clients", label: "Clients & patients", kind: .page, icon: "users-round", opens: .section(.clients), keywords: ["clientes", "clients", "directorio", "familias", "owners", "duenos", "pacientes", "patients", "mascotas", "pets", "animales"], needs: [.clientsView]),
        SearchAction(id: "page-due", label: "Due", kind: .page, icon: "bell", opens: .section(.due), keywords: ["pendientes de volver", "recordatorios", "recalls", "vencidos"], needs: [.followupsView]),
        SearchAction(id: "page-invitations", label: "Invitations", kind: .page, icon: "mail", opens: .section(.invitations), keywords: ["invitaciones", "invitar", "invite"], needs: [.clientsView]),
        SearchAction(id: "page-records", label: "Records", kind: .page, icon: "file-text", opens: .section(.records), keywords: ["expedientes", "notas", "seguimientos", "follow-ups"], needs: [.recordsView]),
        SearchAction(id: "page-store", label: "Store", kind: .page, icon: "shopping-cart", opens: .section(.store), keywords: ["tienda", "vender", "venta", "sell", "pos", "punto de venta"], needs: [.salesSell]),
        SearchAction(id: "page-inventory", label: "Inventory", kind: .page, icon: "boxes", opens: .section(.inventory), keywords: ["inventario", "stock", "existencias", "lotes"], needs: [.inventoryView]),
        SearchAction(id: "page-pharmacy", label: "Pharmacy", kind: .page, icon: "file-text", opens: .section(.pharmacy), keywords: ["farmacia", "recetas", "prescriptions", "resurtidos", "refills", "controlados", "control log", "libro de control", "controlled register"], anyOf: [.recordsView, .salesSell, .billingEditInvoice], offer: .pharmacy),
        SearchAction(id: "page-catalog", label: "Catalog", kind: .page, icon: "package", opens: .section(.catalog), keywords: ["catalogo", "servicios", "productos", "precios", "prices", "services", "products"], needs: [.catalogView]),
        SearchAction(id: "page-invoices", label: "Invoices", kind: .page, icon: "receipt", opens: .section(.invoices), keywords: ["facturas", "cuentas", "bills", "cobros", "folios"], money: .frontDesk),
        SearchAction(id: "page-finance", label: "Finance", kind: .page, icon: "coins", opens: .section(.finance), keywords: ["finanzas", "dinero", "money", "reportes", "reports", "ingresos"], money: .frontDesk),
        SearchAction(id: "page-day-close", label: "Day close", kind: .page, icon: "scale", opens: .section(.finance), keywords: ["cortes del dia", "corte de caja", "cierre", "day close", "cash up"], money: .frontDesk),
        SearchAction(id: "page-notifications", label: "Notifications", kind: .page, icon: "bell", opens: .section(.notifications), keywords: ["notificaciones", "avisos", "alerts"]),
        SearchAction(id: "page-staff", label: "Staff", kind: .page, icon: "shield-check", opens: .section(.staff), keywords: ["equipo", "team", "personal", "usuarios", "users", "roles"], needs: [.staffView]),
        SearchAction(id: "page-availability", label: "Availability", kind: .page, icon: "clock-3", opens: .section(.availability), keywords: ["disponibilidad", "horarios", "hours", "opening hours"], needs: [.workspaceEdit]),
        SearchAction(id: "page-rooms", label: "Rooms", kind: .page, icon: "door-open", opens: .section(.rooms), keywords: ["espacios", "salas", "consultorios", "rooms"], needs: [.appointmentsView]),
        SearchAction(id: "page-locations", label: "Locations", kind: .page, icon: "map-pin", opens: .section(.locations), keywords: ["sedes", "sucursales", "branches"], needs: [.workspaceEdit]),
        SearchAction(id: "page-settings", label: "Settings", kind: .page, icon: "settings", opens: .section(.settings), keywords: ["ajustes", "configuracion", "negocio", "workspace"], needs: [.workspaceEdit]),
        SearchAction(id: "page-subscription", label: "Subscription", kind: .page, icon: "circle-dollar-sign", opens: .section(.billing), keywords: ["suscripcion", "plan", "pago", "billing"], money: .finances, orPlanManager: true),
    ]

    /// The actions whose name (in either language) or keywords have every typed word, best
    /// first: a name that starts with the text, then a word of it, then the rest.
    static func matching(_ actions: [SearchAction], text: String, translated: (String) -> String) -> [SearchAction] {
        let words = SearchText.fold(text).split(separator: " ").map(String.init)
        guard let first = words.first else { return actions }
        let phrase = words.joined(separator: " ")
        let scored: [(action: SearchAction, score: Int, index: Int)] = actions.enumerated().compactMap { index, action in
            let names = [SearchText.fold(translated(action.label)), SearchText.fold(action.label)]
            let haystack = (names + action.keywords.map { SearchText.fold($0) }).joined(separator: " | ")
            guard words.allSatisfy({ haystack.contains($0) }) else { return nil }
            let score = names.contains { $0.hasPrefix(phrase) } ? 0
                : names.contains { $0.split(separator: " ").contains { $0.hasPrefix(first) } } ? 1 : 2
            return (action, score, index)
        }
        return scored.sorted { $0.score != $1.score ? $0.score < $1.score : $0.index < $1.index }.map(\.action)
    }
}

// MARK: - What this device remembers

enum SearchRecentKind: String, Codable {
    case pet, hospital, client, visit, invoice

    var group: SearchResultGroup {
        switch self {
        case .pet: .pets
        case .hospital: .hospital
        case .client: .clients
        case .visit: .visits
        case .invoice: .invoices
        }
    }
}

struct SearchRecentItem: Codable, Hashable {
    let kind: SearchRecentKind
    let id: String
    /// The client, for a pet (its chart lives under it).
    var clientId: String? = nil
    let title: String
    var subtitle: String? = nil
    var photoUrl: String? = nil
    var species: String? = nil
    /// When it was opened (ms).
    var at: Double = Date().timeIntervalSince1970 * 1000
}

struct SearchRecents: Codable, Equatable {
    var items: [SearchRecentItem] = []
    var queries: [String] = []

    static let itemsMax = 6
    static let queriesMax = 4

    /// Kept per person and per business on this device, so a shared front-desk device doesn't mix them.
    static func key(userId: String?, clinicId: String?) -> String {
        "pawmiaw.provider.search.recent.\(userId ?? "anon").\(clinicId ?? "none")"
    }

    /// What this device remembers; empty when it can't be read.
    static func read(_ key: String) -> SearchRecents {
        guard let data = UserDefaults.standard.data(forKey: key) else { return SearchRecents() }
        // Item by item, so one unreadable entry doesn't lose the rest.
        struct Loose: Decodable { let items: [JSONValue]?; let queries: [String]? }
        guard let loose = try? JSONDecoder().decode(Loose.self, from: data) else { return SearchRecents() }
        let items = (loose.items ?? []).compactMap { value -> SearchRecentItem? in
            guard let raw = try? JSONEncoder().encode(value) else { return nil }
            return try? JSONDecoder().decode(SearchRecentItem.self, from: raw)
        }
        let queries = (loose.queries ?? []).filter { $0.trimmingCharacters(in: .whitespaces).count >= SearchText.minLength }
        return SearchRecents(items: Array(items.prefix(itemsMax)), queries: Array(queries.prefix(queriesMax)))
    }

    func write(_ key: String) {
        if items.isEmpty && queries.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// The item first, without its older copy, capped.
    func remembering(_ item: SearchRecentItem) -> SearchRecents {
        let rest = items.filter { !($0.kind == item.kind && $0.id == item.id) }
        return SearchRecents(items: Array(([item] + rest).prefix(Self.itemsMax)), queries: queries)
    }

    /// The search first (the same words, however cased, only once), capped.
    func remembering(query: String) -> SearchRecents {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= SearchText.minLength else { return self }
        let rest = queries.filter { SearchText.fold($0) != SearchText.fold(trimmed) }
        return SearchRecents(items: items, queries: Array(([trimmed] + rest).prefix(Self.queriesMax)))
    }
}

// MARK: - The options, in groups

enum SearchGroupID: String {
    case recent, pets, hospital, clients, visits, invoices, actions, pages

    var title: String {
        switch self {
        case .recent: L("Recent")
        case .pets: L("Patients")
        case .hospital: L("Hospital")
        case .clients: L("Clients")
        case .visits: L("Visits")
        case .invoices: L("Invoices")
        case .actions: L("Quick actions")
        case .pages: L("Go to")
        }
    }
}

enum SearchOption: Identifiable, Hashable {
    case pet(SearchPet)
    case hospital(SearchHospitalPatient)
    case client(SearchClient)
    case visit(SearchVisit)
    case invoice(SearchInvoice)
    case more(SearchResultGroup, query: String)
    case recentItem(SearchRecentItem)
    case recentQuery(String)
    case action(SearchAction)

    var id: String {
        switch self {
        case .pet(let pet): "pet:\(pet.id)"
        case .hospital(let patient): "hospital:\(patient.id)"
        case .client(let client): "client:\(client.id)"
        case .visit(let visit): "visit:\(visit.id)"
        case .invoice(let invoice): "invoice:\(invoice.id)"
        case .more(let group, _): "more:\(group.rawValue)"
        case .recentItem(let item): "recent:\(item.kind.rawValue):\(item.id)"
        case .recentQuery(let query): "recent-query:\(query)"
        case .action(let action): "action:\(action.id)"
        }
    }

    /// What this device remembers when it is opened.
    var recent: SearchRecentItem? {
        switch self {
        case .pet(let pet):
            SearchRecentItem(kind: .pet, id: pet.id, clientId: pet.clientId, title: pet.name, subtitle: pet.ownerName, photoUrl: pet.photoUrl, species: pet.species)
        case .hospital(let patient):
            SearchRecentItem(kind: .hospital, id: patient.id, title: patient.petName, subtitle: patient.clientName, photoUrl: patient.petPhotoUrl, species: patient.petSpecies)
        case .client(let client):
            SearchRecentItem(kind: .client, id: client.id, title: client.name, subtitle: client.phone ?? client.email, photoUrl: client.photoUrl)
        case .visit(let visit):
            SearchRecentItem(kind: .visit, id: visit.id, title: [visit.petName, visit.serviceLabel ?? ""].filter { !$0.isEmpty }.joined(separator: " · "), subtitle: visit.clientName, photoUrl: visit.petPhotoUrl, species: visit.petSpecies)
        case .invoice(let invoice):
            SearchRecentItem(kind: .invoice, id: invoice.id, title: [invoice.folio, invoice.clientName ?? ""].filter { !$0.isEmpty }.joined(separator: " · "), subtitle: Money.format(invoice.totalAmount, currency: invoice.currency))
        case .recentItem(let item):
            SearchRecentItem(kind: item.kind, id: item.id, clientId: item.clientId, title: item.title, subtitle: item.subtitle, photoUrl: item.photoUrl, species: item.species)
        default:
            nil
        }
    }
}

struct SearchOptionGroup: Identifiable {
    let id: SearchGroupID
    let options: [SearchOption]
}

extension SearchRules {
    /// The groups, in order. Nothing typed: what this device remembers, then the quick actions
    /// and pages. Something typed: patients, patients in the hospital, clients, visits, bills
    /// (each with "see all" when there are more), then the actions that match.
    static func groups(text: String, results: SearchResponse?, actions: [SearchAction], recents: SearchRecents, moreGroups: Set<SearchResultGroup>, translated: (String) -> String) -> [SearchOptionGroup] {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty {
            let recent = recents.items.map(SearchOption.recentItem) + recents.queries.map(SearchOption.recentQuery)
            return [
                SearchOptionGroup(id: .recent, options: recent),
                SearchOptionGroup(id: .actions, options: actions.filter { $0.kind == .action }.map(SearchOption.action)),
                SearchOptionGroup(id: .pages, options: actions.filter { $0.kind == .page }.map(SearchOption.action)),
            ].filter { !$0.options.isEmpty }
        }

        var groups: [SearchOptionGroup] = []
        if let results, let query = SearchText.searchable(typed) {
            func more(_ group: SearchResultGroup, _ hasMore: Bool?) -> [SearchOption] {
                (hasMore ?? false) && moreGroups.contains(group) ? [.more(group, query: query)] : []
            }
            if let pets = results.pets, !pets.items.isEmpty {
                groups.append(SearchOptionGroup(id: .pets, options: pets.items.map(SearchOption.pet) + more(.pets, pets.hasMore)))
            }
            if let hospital = results.hospital, !hospital.items.isEmpty {
                groups.append(SearchOptionGroup(id: .hospital, options: hospital.items.map(SearchOption.hospital) + more(.hospital, hospital.hasMore)))
            }
            if let clients = results.clients, !clients.items.isEmpty {
                groups.append(SearchOptionGroup(id: .clients, options: clients.items.map(SearchOption.client) + more(.clients, clients.hasMore)))
            }
            if let visits = results.visits, !visits.items.isEmpty {
                groups.append(SearchOptionGroup(id: .visits, options: visits.items.map(SearchOption.visit) + more(.visits, visits.hasMore)))
            }
            if let invoices = results.invoices, !invoices.items.isEmpty {
                groups.append(SearchOptionGroup(id: .invoices, options: invoices.items.map(SearchOption.invoice) + more(.invoices, invoices.hasMore)))
            }
        }
        let matched = SearchAction.matching(actions, text: typed, translated: translated).prefix(SearchText.actionsWithResults)
        if !matched.isEmpty { groups.append(SearchOptionGroup(id: .actions, options: matched.map(SearchOption.action))) }
        return groups
    }
}

// MARK: - Where a choice leads

enum SearchDestination: Hashable {
    /// A page: pushed on the phone's stack; a section on the iPad is chosen in the sidebar.
    case route(ProviderRoute)
    /// The new-client sheet, then that client's page.
    case newClient
    /// A remembered search: typed again.
    case query(String)
}

extension SearchRules {
    /// Where an option leads. A patient opens its chart page; a patient in the hospital its
    /// hospitalization; a client their page; a visit its page; a bill (a counter sale too) its bill.
    static func destination(of option: SearchOption, workspace w: Workspace) -> SearchDestination? {
        switch option {
        case .pet(let pet): return .route(.clientPet(clientId: pet.clientId, petId: pet.id))
        case .hospital(let patient): return .route(.hospitalization(patient.id))
        case .client(let client): return .route(.client(client.id))
        case .visit(let visit): return .route(.appointment(visit.id))
        case .invoice(let invoice): return .route(.invoice(invoice.id))
        case .more(let group, _):
            // The list page with every match (the web opens it with the words in its own search box).
            switch group {
            case .pets: return .route(.section(.patients))
            case .hospital: return .route(.section(.hospital))
            case .clients: return .route(.section(.clients))
            case .visits: return .route(.schedule(ScheduleFilter(view: "list")))
            case .invoices: return .route(.section(.invoices))
            }
        case .recentQuery(let query): return .query(query)
        case .recentItem(let item):
            switch item.kind {
            case .pet:
                if let clientId = item.clientId { return .route(.clientPet(clientId: clientId, petId: item.id)) }
                return .route(.patientChart(petId: item.id))
            case .hospital: return .route(.hospitalization(item.id))
            case .client: return .route(.client(item.id))
            case .visit: return .route(.appointment(item.id))
            case .invoice: return .route(.invoice(item.id))
            }
        case .action(let action):
            switch action.opens {
            case .section(let section): return .route(.section(section))
            // Booking needs one place: with "Todas las sedes", the Agenda asks which first.
            case .newAppointment: return .route(w.allLocationsChosen ? .section(.schedule) : .bookVisit(BookingPrefill()))
            case .newClient: return .newClient
            case .newRecord: return .route(.newRecord(RecordPrefill()))
            }
        }
    }
}
