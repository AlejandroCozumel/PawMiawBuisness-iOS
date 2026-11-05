//
//  TeamRoles.swift
//  PawMiawNegocios
//
//  Roles and permissions as the web's staff pages read them
//  (components/app/staff/staff-model.ts, lib/provider-permissions.ts): each
//  role's colour, icon and plain line; every permission grouped by the part
//  of the workspace it opens, in a manager's words; and the small rules the
//  pages share (overrides, "sees only their own…", open invitations).
//

import SwiftUI

enum TeamRole {
    static let all = ["owner", "admin", "vet", "support_staff", "receptionist"]
    /// Roles someone can be invited as or moved to: the owner is only the workspace's creator.
    static let assignable = ["admin", "vet", "support_staff", "receptionist"]

    static func label(_ role: String?) -> String {
        switch role {
        case "owner": L("Owner")
        case "admin": L("Admin")
        case "vet": L("Vet")
        case "support_staff": L("Support staff")
        case "receptionist": L("Receptionist")
        default: L("Member")
        }
    }

    static func summary(_ role: String?) -> String {
        switch role {
        case "owner": L("Everything, including the plan. There is one owner: whoever created the workspace.")
        case "admin": L("Runs the place: the team, money, settings and every visit. Only the owner changes the plan.")
        case "vet": L("Clinical work: their own visits and clients, writing and signing records, starting the bills.")
        case "support_staff": L("Keeps the day moving: check-ins, visits for anyone, drafts of notes for a vet to sign, the desk.")
        case "receptionist": L("The front desk: books for anyone, checks pets in, charges, runs the register and stays. No medical records.")
        default: ""
        }
    }

    /// The web's ROLE_META icon.
    static func icon(_ role: String?) -> String {
        switch role {
        case "owner": "crown"
        case "admin": "shield-check"
        case "vet": "stethoscope"
        case "support_staff": "heart-handshake"
        case "receptionist": "headset"
        default: "user-round"
        }
    }

    /// lib/provider-colors.ts ROLE_HUE.
    static func hue(_ role: String?) -> Hue {
        switch role {
        case "owner": .butter
        case "admin": .sky
        case "vet": .mint
        case "support_staff": .peach
        case "receptionist": .lavender
        default: .grey
        }
    }
}

struct TeamPermissionInfo: Hashable {
    let key: String
    let label: String
    let description: String
}

struct TeamPermissionGroup: Hashable {
    let key: String
    let title: String
    let permissions: [TeamPermissionInfo]
}

enum TeamPermissions {
    /// PROVIDER_PERMISSION_GROUPS, in order, with their English words (Spanish in Team.strings).
    static let groups: [TeamPermissionGroup] = [
        TeamPermissionGroup(key: "appointments", title: "Schedule and visits", permissions: [
            .init(key: "appointments.view", label: "See the Schedule", description: "See booked visits and how each one is going."),
            .init(key: "appointments.create", label: "Book visits", description: "Book new visits for clients and their pets."),
            .init(key: "appointments.edit", label: "Change visits", description: "Move a visit or change its details."),
            .init(key: "appointments.assign_self", label: "Book visits for themselves", description: "Put their own name on a visit they book or change."),
            .init(key: "appointments.assign_anyone", label: "Book visits for anyone", description: "Put any person of the team on a visit."),
            .init(key: "appointments.check_in", label: "Check pets in", description: "Record that a pet arrived, or that it didn’t show up."),
            .init(key: "appointments.cancel", label: "Cancel visits", description: "Cancel a booked visit when plans change."),
            .init(key: "appointments.complete", label: "Start and finish visits", description: "Take visits: start them and finish them. Whoever has this gets a column in the Schedule and can be booked."),
        ]),
        TeamPermissionGroup(key: "stays", title: "Stays", permissions: [
            .init(key: "stays.view", label: "View stays", description: "See the occupancy board, reservations, and pets staying in."),
            .init(key: "stays.manage", label: "Manage stays", description: "Book, change, check in and check out stays; set up rooms and rates."),
            .init(key: "stays.care", label: "Care and report cards", description: "Tick off the day's care and send report cards to owners."),
        ]),
        TeamPermissionGroup(key: "hospital", title: "Hospital", permissions: [
            .init(key: "hospital.view", label: "View the hospital", description: "See the ward, the patients in, and families on their way with an emergency."),
            .init(key: "hospital.care", label: "Treatment sheet and updates", description: "Tick doses on the sheet, record vitals and send updates to the family."),
            .init(key: "hospital.manage", label: "Manage hospitalizations", description: "Admit, write the treatment plan, sign rounds, discharge, transfer, record a death, set up the hospital and on-call."),
        ]),
        TeamPermissionGroup(key: "store", title: "Store", permissions: [
            .init(key: "sales.sell", label: "Sell", description: "Use the store: sell products and services at the counter."),
            .init(key: "sales.refund", label: "Returns and cancels", description: "Take goods back, refund them, and cancel a sale made by mistake."),
            .init(key: "sales.override_price", label: "Change prices at the counter", description: "Sell something for a different price than the catalog’s."),
            .init(key: "register.manage", label: "Run the register", description: "Put cash in or take it out, add registers and see past shifts and what the drawer should hold. Anyone who sells or takes payments opens and closes a shift."),
        ]),
        TeamPermissionGroup(key: "pharmacy", title: "Pharmacy", permissions: [
            .init(key: "pharmacy.dispense_controlled", label: "Hand over controlled medicines", description: "Sell or bill a controlled medicine against its prescription. Without it the Store and the visit’s bill ask for a vet."),
        ]),
        TeamPermissionGroup(key: "catalog", title: "Catalog", permissions: [
            .init(key: "catalog.view", label: "See the Catalog", description: "Open the Catalog of services and products."),
            .init(key: "catalog.create", label: "Add to the Catalog", description: "Add new services or products."),
            .init(key: "catalog.edit", label: "Change the Catalog", description: "Change prices, details and whether an item is offered."),
        ]),
        TeamPermissionGroup(key: "inventory", title: "Inventory", permissions: [
            .init(key: "inventory.view", label: "View inventory", description: "See stock levels, reorder points, and product inventory status."),
            .init(key: "inventory.edit", label: "Edit inventory setup", description: "Update inventory settings like quantity, reorder points, and shelf details."),
            .init(key: "inventory.adjust", label: "Adjust inventory", description: "Record stock movements, corrections, restocks, and waste."),
            .init(key: "inventory.receive", label: "Receive stock", description: "Record deliveries with their cost, lot, and expiry date."),
            .init(key: "inventory.count", label: "Count and write off", description: "Record stock counts and write off expired or damaged stock."),
        ]),
        TeamPermissionGroup(key: "clients", title: "Clients and pets", permissions: [
            .init(key: "clients.view", label: "See clients", description: "Open the client list and each client’s page."),
            .init(key: "clients.create", label: "Add clients", description: "Add new clients."),
            .init(key: "clients.edit", label: "Change clients", description: "Change a client’s details and photo."),
            .init(key: "clients.assign_self", label: "Their own clients", description: "See and add the clients assigned to them. With only this, they see no one else’s clients."),
            .init(key: "clients.assign_anyone", label: "Every client", description: "See every client and assign them to anyone on the team."),
            .init(key: "pets.create", label: "Add pets", description: "Add a client’s first pet and more pets later."),
            .init(key: "pets.edit", label: "Change pets", description: "Change a pet’s profile, photo, chip number and notes."),
        ]),
        TeamPermissionGroup(key: "records", title: "Records", permissions: [
            .init(key: "records.view", label: "See records", description: "See medical records and each pet’s history."),
            .init(key: "records.create", label: "Write records", description: "Add new medical records."),
            .init(key: "records.edit", label: "Change records", description: "Change records already written."),
            .init(key: "records.assign_self", label: "Their own records", description: "See and write the records assigned to them. With only this, they see no one else’s records."),
            .init(key: "records.assign_anyone", label: "Every record", description: "See every record and assign them to anyone on the team."),
            .init(key: "records.approve", label: "Sign records and prescriptions", description: "Sign records and prescriptions, and approve a draft someone else wrote."),
        ]),
        TeamPermissionGroup(key: "olfato", title: "Olfato AI", permissions: [
            .init(key: "olfato.chat", label: "Use Olfato AI", description: "Ask Olfato AI about a pet or about the business. It answers only from what this person can already see."),
        ]),
        TeamPermissionGroup(key: "followups", title: "Follow-ups", permissions: [
            .init(key: "followups.view", label: "See follow-ups", description: "See the lists of calls, rechecks and care follow-ups."),
            .init(key: "followups.create", label: "Add follow-ups", description: "Add a follow-up from a record or by hand."),
            .init(key: "followups.edit", label: "Change follow-ups", description: "Change the due date, notes, status and who has it."),
            .init(key: "followups.assign_self", label: "Their own follow-ups", description: "See and add the follow-ups assigned to them. With only this, they see no one else’s follow-ups."),
            .init(key: "followups.assign_anyone", label: "Every follow-up", description: "See every follow-up and assign them to anyone on the team."),
            .init(key: "followups.complete", label: "Finish follow-ups", description: "Mark a follow-up done."),
        ]),
        TeamPermissionGroup(key: "notifications", title: "Notices they get", permissions: [
            .init(key: "notifications.appointments", label: "Notices about visits", description: "Bookings, arrivals, changes of time, cancellations and no-shows."),
            .init(key: "notifications.provider_followups", label: "Notices about follow-ups", description: "Reminders of calls, rechecks, lab results and medication reviews."),
            .init(key: "notifications.records_documentation", label: "Notices about records", description: "Reminders of records left to write or sign."),
            .init(key: "notifications.billing", label: "Notices about money", description: "Reminders of bills left to charge and of payments."),
            .init(key: "notifications.client_messages", label: "Notices about client messages", description: "When a client writes, and when a message waits for an answer."),
            .init(key: "notifications.client_facing_reminders", label: "Notices about reminders to clients", description: "Reminders that go out, or could go out, to clients."),
        ]),
        TeamPermissionGroup(key: "inbox", title: "Messages", permissions: [
            .init(key: "inbox.view", label: "See messages", description: "See conversations with clients and families."),
            .init(key: "inbox.reply", label: "Answer messages", description: "Reply to clients and families."),
        ]),
        TeamPermissionGroup(key: "staff", title: "Team", permissions: [
            .init(key: "staff.view", label: "See the team", description: "Open the team list, each person’s page and the invitations."),
            .init(key: "staff.invite", label: "Invite people", description: "Invite someone to the team, send an invitation again or cancel it."),
            .init(key: "staff.edit_roles", label: "Change roles and access", description: "Change a person’s role, permissions, profile, hours and days off."),
            .init(key: "staff.remove", label: "Suspend and remove people", description: "Pause someone’s access, give it back, or take them off the team."),
        ]),
        TeamPermissionGroup(key: "billing", title: "Bills and payments", permissions: [
            .init(key: "billing.view", label: "See and charge bills", description: "The bill in front of them: a visit’s, stay’s or hospital bill, one client’s account and balance, one pet’s bills, selling at the counter."),
            .init(key: "finance.desk", label: "Front desk money", description: "Who owes, today’s cash and the day close, the bills list, and the last 7 days of sales."),
            .init(key: "finance.view", label: "Business finances", description: "Period totals, reports, margins, costs, payment history and every location."),
            .init(key: "billing.create_invoice", label: "Start bills", description: "Start a bill from a client, a visit or a record."),
            .init(key: "billing.edit_invoice", label: "Change bills", description: "Change what a bill in draft charges, and its notes."),
            .init(key: "billing.finalize_invoice", label: "Close bills", description: "Take a bill out of draft so it can be charged."),
            .init(key: "billing.record_payment", label: "Take payments", description: "Charge and record payments on open bills."),
            .init(key: "billing.apply_discount", label: "Give discounts", description: "Give a discount on a bill, with its reason."),
            .init(key: "billing.waive_visit", label: "Finish visits without charging", description: "Close a visit with “No charge” (a courtesy or a warranty recheck), with its reason. Without it, the visit goes to the desk to be charged."),
            .init(key: "billing.manage", label: "Money settings and the plan", description: "Set credit limits and the store’s, the receipt’s and money settings. Turned on by hand for one person, it also lets them change the workspace’s plan — only the owner can do that."),
        ]),
        TeamPermissionGroup(key: "workspace", title: "Business", permissions: [
            .init(key: "workspace.edit", label: "Change the business", description: "Change how the business is set up: its details, locations, rooms, opening hours, closed dates and booking rules."),
        ]),
    ]

    /// Inviting, changing a role and removing someone still need an Admin or the Owner.
    static let teamAdmin: Set<String> = ["staff.invite", "staff.edit_roles", "staff.remove"]

    static func label(_ key: String) -> String {
        for group in groups { if let found = group.permissions.first(where: { $0.key == key }) { return L(found.label) } }
        return key
    }

    /// What a role gives before any fine-tuning; nil while that isn't loaded.
    static func roleDefaults(_ roles: [TeamRolePermissions]?, _ role: String) -> [String]? {
        roles?.first(where: { $0.role == role })?.permissions
    }

    static func effective(defaults: [String], allow: [String], deny: [String]) -> [String] {
        var set = Set(defaults).union(allow)
        for permission in deny { set.remove(permission) }
        return orderedKeys(set)
    }

    /// The two lists the server keeps for a person, from what they should be able to do.
    static func overrides(defaults: [String], wanted: [String]) -> (allow: [String], deny: [String]) {
        let base = Set(defaults)
        let want = Set(wanted)
        return (orderedKeys(want.subtracting(base)), defaults.filter { !want.contains($0) })
    }

    static func orderedKeys(_ set: Set<String>) -> [String] {
        let order = groups.flatMap { $0.permissions.map(\.key) }
        let known = order.filter { set.contains($0) }
        return known + set.subtracting(order).sorted()
    }

    /// "Sees only their own clients": the "their own" permission of an area without its "every…" one.
    static func limits(_ effective: [String]) -> [String] {
        let set = Set(effective)
        let scopes: [(view: String, own: String, anyone: String, text: String)] = [
            ("clients.view", "clients.assign_self", "clients.assign_anyone", "Sees only their own clients"),
            ("records.view", "records.assign_self", "records.assign_anyone", "Sees only their own records"),
            ("followups.view", "followups.assign_self", "followups.assign_anyone", "Sees only their own follow-ups"),
            ("appointments.create", "appointments.assign_self", "appointments.assign_anyone", "Books visits only for themselves"),
        ]
        return scopes.filter { set.contains($0.view) && set.contains($0.own) && !set.contains($0.anyone) }.map { L($0.text) }
    }

    /// Each area with what is on and off in it.
    static func byGroup(_ effective: [String]) -> [(group: TeamPermissionGroup, on: [TeamPermissionInfo], off: [TeamPermissionInfo])] {
        let set = Set(effective)
        return groups.map { group in
            (group, group.permissions.filter { set.contains($0.key) }, group.permissions.filter { !set.contains($0.key) })
        }
    }

    /// Permissions whose name or description says what was typed; ignores case and accents.
    static func search(_ needle: String) -> [TeamPermissionGroup] {
        func plain(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .app) }
        let wanted = plain(needle.trimmingCharacters(in: .whitespaces))
        guard !wanted.isEmpty else { return groups }
        return groups.compactMap { group in
            let permissions = plain(L(group.title)).contains(wanted) ? group.permissions : group.permissions.filter {
                plain(L($0.label)).contains(wanted) || plain(L($0.description)).contains(wanted)
            }
            return permissions.isEmpty ? nil : TeamPermissionGroup(key: group.key, title: group.title, permissions: permissions)
        }
    }

    /// "The role's access" or "1 added · 2 taken away".
    static func accessLine(_ member: TeamMember) -> String {
        if member.roleKey == "owner" { return L("Full access") }
        if !member.hasCustomAccess { return L("The role’s access") }
        var parts: [String] = []
        if !member.allow.isEmpty { parts.append(LP(member.allow.count, "1 added", "%d added")) }
        if !member.deny.isEmpty { parts.append(LP(member.deny.count, "1 taken away", "%d taken away")) }
        return parts.joined(separator: " · ")
    }
}

enum TeamText {
    /// "Centro, Norte"; nil when it is every location (owners and admins work everywhere).
    static func locationNames(role: String?, ids: [String]?, locations: [ProviderLocation]) -> String? {
        if role == "owner" || role == "admin" { return nil }
        let names = (ids ?? []).compactMap { id in locations.first(where: { $0.id == id })?.name }
        if names.isEmpty || names.count == locations.count { return nil }
        return names.joined(separator: ", ")
    }

    /// The invitations still worth showing: one line per email, the newest; waiting first.
    static func openInvitations(_ invitations: [TeamInvitation], memberEmails: Set<String>, now: Date = Date()) -> [TeamOpenInvitation] {
        var byEmail: [String: TeamOpenInvitation] = [:]
        var order: [String] = []
        let sorted = invitations.sorted { (DateText.parse($0.expiresAt) ?? .distantPast) > (DateText.parse($1.expiresAt) ?? .distantPast) }
        for invitation in sorted where invitation.status == "pending" {
            let email = invitation.email.trimmingCharacters(in: .whitespaces).lowercased()
            if memberEmails.contains(email) || byEmail[email] != nil { continue }
            let expired = DateText.parse(invitation.expiresAt).map { $0 <= now } ?? false
            byEmail[email] = TeamOpenInvitation(invitation: invitation, expired: expired)
            order.append(email)
        }
        let items = order.compactMap { byEmail[$0] }
        return items.filter { !$0.expired } + items.filter(\.expired)
    }

    /// What to say to the person invited, in the owner's own words.
    static func invitationMessage(name: String?, email: String, workspace: String) -> String {
        let url = APIConfig.webOrigin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/provider?invite=team"
        return LF("Hi %@! I added you to %@ on PawMiaw. Open %@, sign in or create your account with %@ and accept the invitation. It lasts 48 hours.", name.nonEmpty ?? "", workspace, url, email)
            .replacingOccurrences(of: " !", with: "!")
            .replacingOccurrences(of: "¡Hola !", with: "¡Hola!")
    }

    /// "Active 3 hours ago"; "Not seen yet".
    static func lastActive(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return L("Not seen yet") }
        return LF("Active %@", relative(date))
    }

    /// "in 2 days", "3 hours ago" — numbers, in the reader's language.
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = .app
        f.unitsStyle = .full
        let diff = date.timeIntervalSince(now)
        if abs(diff) < 3600 { return f.localizedString(from: DateComponents(minute: Int((diff / 60).rounded()))) }
        if abs(diff) < 86_400 { return f.localizedString(from: DateComponents(hour: Int((diff / 3600).rounded()))) }
        return f.localizedString(from: DateComponents(day: Int((diff / 86_400).rounded())))
    }

    /// "4 nov", with the year only when it isn't this one.
    static func shortDate(_ iso: String?) -> String {
        guard let date = DateText.parse(iso) else { return "" }
        let f = DateFormatter()
        f.locale = .app
        let sameYear = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date())
        f.setLocalizedDateFormatFromTemplate(sameYear ? "dMMM" : "dMMMyyyy")
        return f.string(from: date)
    }
}

/// A role as a chip (web `RoleChip`): the role's hue at 18% with a 55% edge, its icon and name;
/// `large` = the member page's 28.
func teamRoleChip(_ role: String?, large: Bool = false) -> Chip {
    let tone = TeamRole.hue(role).color
    return Chip(text: TeamRole.label(role), tone: .custom(tone), icon: TeamRole.icon(role), percent: 18, border: 55, size: large ? .wide : .medium)
}
