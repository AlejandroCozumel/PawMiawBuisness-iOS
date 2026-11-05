//
//  Permissions.swift
//  PawMiawNegocios
//
//  What a person may do in a business, as the server decides it
//  (`effectivePermissions` on the workspace). The app only hides what a
//  person can't do; the server refuses it anyway. The web's
//  lib/provider-permissions.ts, key for key.
//

import Foundation

enum Permission: String, CaseIterable {
    case appointmentsView = "appointments.view"
    case appointmentsCreate = "appointments.create"
    case appointmentsEdit = "appointments.edit"
    case appointmentsAssignSelf = "appointments.assign_self"
    case appointmentsAssignAnyone = "appointments.assign_anyone"
    case appointmentsCheckIn = "appointments.check_in"
    case appointmentsCancel = "appointments.cancel"
    case appointmentsComplete = "appointments.complete"
    case staysView = "stays.view"
    case staysManage = "stays.manage"
    case staysCare = "stays.care"
    case hospitalView = "hospital.view"
    case hospitalCare = "hospital.care"
    case hospitalManage = "hospital.manage"
    case salesSell = "sales.sell"
    case salesRefund = "sales.refund"
    case salesOverridePrice = "sales.override_price"
    case registerManage = "register.manage"
    case pharmacyDispenseControlled = "pharmacy.dispense_controlled"
    case inventoryReceive = "inventory.receive"
    case inventoryCount = "inventory.count"
    case catalogView = "catalog.view"
    case catalogCreate = "catalog.create"
    case catalogEdit = "catalog.edit"
    case inventoryView = "inventory.view"
    case inventoryEdit = "inventory.edit"
    case inventoryAdjust = "inventory.adjust"
    case clientsView = "clients.view"
    case clientsCreate = "clients.create"
    case clientsEdit = "clients.edit"
    case clientsAssignSelf = "clients.assign_self"
    case clientsAssignAnyone = "clients.assign_anyone"
    case petsCreate = "pets.create"
    case petsEdit = "pets.edit"
    case recordsView = "records.view"
    case recordsCreate = "records.create"
    case recordsEdit = "records.edit"
    case recordsAssignSelf = "records.assign_self"
    case recordsAssignAnyone = "records.assign_anyone"
    case recordsApprove = "records.approve"
    case olfatoChat = "olfato.chat"
    case followupsView = "followups.view"
    case followupsCreate = "followups.create"
    case followupsEdit = "followups.edit"
    case followupsAssignSelf = "followups.assign_self"
    case followupsAssignAnyone = "followups.assign_anyone"
    case followupsComplete = "followups.complete"
    case notificationsAppointments = "notifications.appointments"
    case notificationsProviderFollowups = "notifications.provider_followups"
    case notificationsRecordsDocumentation = "notifications.records_documentation"
    case notificationsBilling = "notifications.billing"
    case notificationsClientMessages = "notifications.client_messages"
    case notificationsClientFacingReminders = "notifications.client_facing_reminders"
    case inboxView = "inbox.view"
    case inboxReply = "inbox.reply"
    case staffView = "staff.view"
    case staffInvite = "staff.invite"
    case staffEditRoles = "staff.edit_roles"
    case staffRemove = "staff.remove"
    case workspaceEdit = "workspace.edit"
    case billingView = "billing.view"
    case financeDesk = "finance.desk"
    case financeView = "finance.view"
    case billingCreateInvoice = "billing.create_invoice"
    case billingEditInvoice = "billing.edit_invoice"
    case billingFinalizeInvoice = "billing.finalize_invoice"
    case billingRecordPayment = "billing.record_payment"
    case billingApplyDiscount = "billing.apply_discount"
    case billingWaiveVisit = "billing.waive_visit"
    case billingManage = "billing.manage"
}

/// Money reading in three levels (backend docs/money-access-levels.md):
/// 0 none · 1 `billing.view` the bill in front of you · 2 `finance.desk` the
/// front desk (who owes, today's cash, the day close, the bills list, the
/// last 7 days of sales) · 3 `finance.view` the business's finances (period
/// totals, reports, margins, costs, history, every location). A higher level
/// includes the lower ones. The server enforces; the app only hides.
enum MoneyLevel: Int, Comparable {
    case none = 0, charging = 1, frontDesk = 2, finances = 3

    static func < (a: MoneyLevel, b: MoneyLevel) -> Bool { a.rawValue < b.rawValue }

    static func of(_ permissions: Set<String>) -> MoneyLevel {
        if permissions.contains(Permission.financeView.rawValue) { return .finances }
        if permissions.contains(Permission.financeDesk.rawValue) { return .frontDesk }
        if permissions.contains(Permission.billingView.rawValue) { return .charging }
        return .none
    }

    /// "Recent" for the front desk: the last 7 days, today included.
    static let frontDeskDays = 7
}

enum WorkspaceRole: String, CaseIterable, Identifiable {
    case owner, admin, vet
    case supportStaff = "support_staff"
    case receptionist

    var id: String { rawValue }

    var label: String {
        switch self {
        case .owner: L("Owner")
        case .admin: L("Admin")
        case .vet: L("Vet")
        case .supportStaff: L("Support staff")
        case .receptionist: L("Receptionist")
        }
    }

    var summary: String {
        switch self {
        case .owner: L("Full control over staff, billing, workspace settings, and clinic workflows.")
        case .admin: L("Manages staff, money and clinic workflows; only the owner changes the workspace plan.")
        case .vet: L("Handles clinical work, appointments, clients, pets and records, and charges their own visits.")
        case .supportStaff: L("Keeps the day moving: check-ins, visits, drafts of notes for the vet to sign, and the desk.")
        case .receptionist: L("Focuses on booking, check-in, client contact, and front-desk coordination.")
        }
    }

    static func label(_ raw: String?) -> String {
        raw.flatMap(WorkspaceRole.init(rawValue:))?.label ?? (raw ?? "")
    }
}

/// The kinds of business a workspace runs (`enabledCategories`).
enum BusinessCategory: String, CaseIterable {
    case vet, emergency, groomer, boarding, daycare, sitter, walker, trainer, other

    var label: String {
        switch self {
        case .vet: L("Veterinary clinic")
        case .emergency: L("Emergency")
        case .groomer: L("Grooming")
        case .boarding: L("Boarding")
        case .daycare: L("Daycare")
        case .sitter: L("Pet sitting")
        case .walker: L("Dog walking")
        case .trainer: L("Training")
        case .other: L("Other")
        }
    }
}
