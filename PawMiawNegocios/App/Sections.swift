//
//  Sections.swift
//  PawMiawNegocios
//
//  The business workspace's sections, grouped and filtered exactly as the
//  web's sidebar (components/app/provider-shell.tsx): each has its
//  permission, some need a kind of business, money pages follow the money
//  levels. `ProviderRoute` is every place a screen can push.
//

import SwiftUI

enum SectionGroup: String, CaseIterable {
    case operations, billing, workspace

    var title: String {
        switch self {
        case .operations: L("Operations")
        case .billing: L("Billing")
        case .workspace: L("Workspace")
        }
    }

    var sections: [ProviderSection] {
        switch self {
        case .operations: [.home, .schedule, .stays, .hospital, .grooming, .groups, .homeVisits, .clients, .due, .invitations, .records, .olfato]
        case .billing: [.store, .inventory, .pharmacy, .catalog, .invoices, .finance]
        case .workspace: [.billing, .settings, .staff, .availability, .rooms, .locations]
        }
    }
}

enum ProviderSection: String, CaseIterable, Identifiable, Hashable {
    case home, schedule, appointments, stays, hospital, grooming, groups, homeVisits, clients, patients, due, invitations, records, olfato
    case store, inventory, pharmacy, catalog, invoices, finance
    case billing, settings, staff, availability, rooms, locations
    case notifications, notificationSettings, relocate, accountSecurity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: L("Home")
        case .schedule: L("Schedule")
        case .appointments: L("Appointments")
        case .stays: L("Stays")
        case .hospital: L("Hospital")
        case .grooming: L("Grooming")
        case .groups: L("Walks & classes")
        case .homeVisits: L("Home visits")
        case .clients: L("Clients & patients")
        case .patients: L("Patients")
        case .due: L("Due")
        case .invitations: L("Invitations")
        case .records: L("Records")
        case .olfato: "Olfato AI"
        case .store: L("Store")
        case .inventory: L("Inventory")
        case .pharmacy: L("Pharmacy")
        case .catalog: L("Catalog")
        case .invoices: L("Invoices")
        case .finance: L("Finance")
        case .billing: L("Subscription")
        case .settings: L("Settings")
        case .staff: L("Staff")
        case .availability: L("Availability")
        case .rooms: L("Rooms")
        case .locations: L("Locations")
        case .notifications: L("Notifications")
        case .notificationSettings: L("Notification settings")
        case .relocate: L("To relocate")
        case .accountSecurity: L("Your account")
        }
    }

    /// The web sidebar's Lucide icon (provider-shell.tsx).
    var icon: String {
        switch self {
        case .home: "building-2"
        case .schedule, .appointments: "calendar-days"
        case .stays: "bed-double"
        case .hospital: "hospital"
        case .grooming: "scissors"
        case .groups: "dog"
        case .homeVisits: "house"
        case .clients, .patients: "users-round"
        case .due: "bell-ring"
        case .invitations: "mail-plus"
        case .records: "file-text"
        case .olfato: "stethoscope"
        case .store: "shopping-cart"
        case .inventory: "boxes"
        case .pharmacy: "pill"
        case .catalog: "package"
        case .invoices: "receipt"
        case .finance: "coins"
        case .billing: "circle-dollar-sign"
        case .settings: "settings"
        case .staff: "shield-check"
        case .availability: "clock-3"
        case .rooms: "door-open"
        case .locations: "map-pin"
        case .notifications: "bell"
        case .notificationSettings: "bell-ring"
        case .relocate: "arrow-right-left"
        case .accountSecurity: "user-round"
        }
    }

    /// The page's module header: its Lucide icon (web, where it differs from the sidebar's).
    var headerIcon: String {
        switch self {
        case .home: "calendar-clock"
        case .hospital: "bed-double"
        case .groups, .staff: "users-round"
        case .finance: "banknote"
        default: icon
        }
    }

    /// The page's module header colour (web `ProviderModuleHeader` accent).
    var headerAccent: Color {
        switch self {
        case .hospital, .grooming, .staff: Theme.pink
        case .groups, .clients, .patients: Theme.lime
        case .homeVisits, .invitations, .records, .notifications, .availability, .accountSecurity: Theme.aqua
        case .catalog, .relocate: Theme.mango
        case .finance: ProviderState.done.color
        default: Theme.blue
        }
    }

    var systemImage: String {
        switch self {
        case .home: "building.2.fill"
        case .schedule, .appointments: "calendar"
        case .stays: "bed.double.fill"
        case .hospital: "cross.case.fill"
        case .grooming: "scissors"
        case .groups: "figure.walk"
        case .homeVisits: "house.fill"
        case .clients, .patients: "person.2.fill"
        case .due: "bell.badge.fill"
        case .invitations: "envelope.badge.fill"
        case .records: "doc.text.fill"
        case .olfato: "stethoscope"
        case .store: "cart.fill"
        case .inventory: "shippingbox.fill"
        case .pharmacy: "pills.fill"
        case .catalog: "tag.fill"
        case .invoices: "doc.plaintext.fill"
        case .finance: "chart.bar.fill"
        case .billing: "dollarsign.circle.fill"
        case .settings: "gearshape.fill"
        case .staff: "person.badge.shield.checkmark.fill"
        case .availability: "clock.fill"
        case .rooms: "door.left.hand.open"
        case .locations: "mappin.and.ellipse"
        case .notifications: "bell.fill"
        case .notificationSettings: "bell.and.waves.left.and.right.fill"
        case .relocate: "arrow.triangle.swap"
        case .accountSecurity: "lock.shield.fill"
        }
    }

    private var permission: Permission? {
        switch self {
        case .schedule, .appointments, .grooming, .groups, .rooms: .appointmentsView
        case .clients, .patients, .invitations: .clientsView
        case .due: .followupsView
        case .stays: .staysView
        case .hospital: .hospitalView
        case .records: .recordsView
        case .store: .salesSell
        case .inventory: .inventoryView
        case .catalog: .catalogView
        case .settings, .availability, .locations: .workspaceEdit
        case .staff: .staffView
        default: nil
        }
    }

    /// The sidebar's rule for this section in this business, for this person.
    @MainActor
    func isVisible(in w: Workspace, olfatoShown: Bool, pharmacyShown: Bool) -> Bool {
        switch self {
        case .stays where !w.offers(.boarding, .daycare, .sitter): return false
        case .hospital where !w.offers(.vet, .emergency): return false
        case .grooming where !w.offers(.groomer): return false
        case .groups where !w.offers(.walker, .trainer): return false
        case .homeVisits: return w.offersHomeVisits && w.canAny(.appointmentsView, .staysView)
        case .pharmacy: return pharmacyShown
        case .olfato: return olfatoShown
        case .invoices, .finance: return w.moneyLevel >= .frontDesk
        case .billing: return (w.current?.canManagePlan ?? false) || w.moneyLevel >= .finances
        default: break
        }
        if let permission { return w.can(permission) }
        return true
    }
}

/// A visit to book, filled in by the screen that asks for it (a client's page, the
/// Due list, a record, a groom, a free gap on the Agenda). Everything is optional:
/// what is given is chosen, the rest is asked.
struct BookingPrefill: Hashable {
    var clientId: String? = nil
    var petId: String? = nil
    /// The catalog service to book.
    var serviceId: String? = nil
    /// "yyyy-MM-dd" on the business's clock.
    var day: String? = nil
    /// Minutes after midnight.
    var startMinute: Int? = nil
    var memberId: String? = nil
    var roomId: String? = nil
    /// The Due list's follow-up this visit answers (the web ties them together).
    var followUpId: String? = nil
    var notes: String? = nil
    /// "Sin cita": the pet is here now.
    var walkIn: Bool = false
}

/// A sale at the Store, filled in by the screen that sends someone to the counter
/// (a prescription to hand over, a bill to charge with products).
struct StorePrefill: Hashable {
    struct Line: Hashable {
        var catalogItemId: String
        var quantity: Double
        /// The prescription line this hands over (the Pharmacy's rule).
        var prescriptionItemId: String? = nil
    }
    var clientId: String? = nil
    var petId: String? = nil
    var lines: [Line] = []
    /// Charge this bill with the products added.
    var invoiceId: String? = nil
    var appointmentId: String? = nil
    var prescriptionId: String? = nil
}

/// The Agenda opened on a day, a person or a room ("day", "week" or "list"),
/// its day grouped by "staff" or "rooms".
struct ScheduleFilter: Hashable {
    var day: String? = nil
    var memberId: String? = nil
    var roomId: String? = nil
    var view: String? = nil
    var by: String? = nil
}

/// A record to write, filled in by the screen that asks (a pet's chart, a visit).
struct RecordPrefill: Hashable {
    var clientId: String? = nil
    var petId: String? = nil
    var appointmentId: String? = nil
    /// The web's record type key ("vaccine", "consultation", …).
    var recordType: String? = nil
}

/// Every place a screen pushes. Push with `NavigationLink(value: ProviderRoute.client(id))`.
enum ProviderRoute: Hashable {
    case section(ProviderSection)
    case appointment(String)
    case client(String)
    case clientPet(clientId: String, petId: String)
    /// The patient chart (expediente) of a client's pet, from any screen.
    case patientChart(petId: String)
    case record(String)
    case hospitalization(String)
    case staffMember(String)
    case olfatoChat(String)
    case invoice(String)
    case sale(String)
    case stay(String)
    /// Book a visit with what the asking screen knows (Schedule's booking).
    case bookVisit(BookingPrefill)
    /// The Store's counter with a client, pet and lines already in the cart.
    case storeCheckout(StorePrefill)
    /// The Agenda on a day / person / room.
    case schedule(ScheduleFilter)
    /// A new record with its pet, visit or type chosen (Records' sheet).
    case newRecord(RecordPrefill)
    /// A new Olfato AI chat about one pet (the pet is the provider client pet id).
    case olfatoPetChat(petId: String)
}

/// The screen for a route. Every NavigationStack in the app uses it.
struct RouteView: View {
    let route: ProviderRoute

    var body: some View {
        switch route {
        case .section(let section): SectionView(section: section)
        case .appointment(let id): AppointmentDetailScreen(appointmentId: id)
        case .client(let id): ClientDetailScreen(clientId: id)
        case .clientPet(let clientId, let petId): ClientPetScreen(clientId: clientId, petId: petId)
        case .patientChart(let petId): PatientChartScreen(petId: petId)
        case .record(let id): RecordDetailScreen(recordId: id)
        case .hospitalization(let id): HospitalDetailScreen(hospitalizationId: id)
        case .staffMember(let id): StaffMemberScreen(memberId: id)
        case .olfatoChat(let id): OlfatoChatScreen(chatId: id)
        case .invoice(let id): InvoiceDetailScreen(invoiceId: id)
        case .sale(let id): SaleDetailScreen(saleId: id)
        case .stay(let id): StayDetailScreen(stayId: id)
        case .bookVisit(let prefill): BookVisitScreen(prefill: prefill)
        case .storeCheckout(let prefill): StoreCheckoutScreen(prefill: prefill)
        case .schedule(let filter): ScheduleScreen(filter: filter)
        case .newRecord(let prefill): NewRecordScreen(prefill: prefill)
        case .olfatoPetChat(let petId): OlfatoPetChatScreen(petId: petId)
        }
    }
}

/// A section's page.
struct SectionView: View {
    let section: ProviderSection

    var body: some View {
        Group {
            switch section {
            case .home: HomeScreen()
            case .schedule: ScheduleScreen()
            case .appointments: AppointmentsListScreen()
            case .stays: StaysScreen()
            case .hospital: HospitalScreen()
            case .grooming: GroomingScreen()
            case .groups: GroupsScreen()
            case .homeVisits: HomeVisitsScreen()
            case .clients: ClientsScreen()
            case .patients: PatientsScreen()
            case .due: DueScreen()
            case .invitations: InvitationsScreen()
            case .records: RecordsScreen()
            case .olfato: OlfatoScreen()
            case .store: StoreScreen()
            case .inventory: InventoryScreen()
            case .pharmacy: PharmacyScreen()
            case .catalog: CatalogScreen()
            case .invoices: InvoicesScreen()
            case .finance: FinanceScreen()
            case .billing: BillingScreen()
            case .settings: SettingsScreen()
            case .staff: StaffScreen()
            case .availability: AvailabilityScreen()
            case .rooms: RoomsScreen()
            case .locations: LocationsScreen()
            case .notifications: NotificationsScreen()
            case .notificationSettings: NotificationSettingsScreen()
            case .relocate: RelocateScreen()
            case .accountSecurity: AccountSecurityScreen()
            }
        }
    }
}

extension View {
    /// Every navigation stack resolves `ProviderRoute`s the same way.
    func providerRoutes() -> some View {
        navigationDestination(for: ProviderRoute.self) { RouteView(route: $0) }
    }
}
