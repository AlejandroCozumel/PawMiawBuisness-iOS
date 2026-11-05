//
//  InboxRoutes.swift
//  PawMiawNegocios
//
//  A web address of the business workspace (`/provider/...`, as a
//  notification's `actionUrl` or an Olfato AI answer's "Ver en …" link
//  names it) as the screen the app pushes. An address the app has no screen
//  for gives nil: the row then only marks itself read.
//

import Foundation

enum InboxRoutes {
    /// `/provider/appointments/abc`, `/provider/invoices?invoice=abc`, `/app/hospital/abc` (older hospital notices).
    static func route(_ address: String?) -> ProviderRoute? {
        guard let address, address.hasPrefix("/"), !address.hasPrefix("//") else { return nil }
        let parts = address.split(separator: "?", maxSplits: 1).map(String.init)
        var query: [String: String] = [:]
        if parts.count > 1 {
            for item in URLComponents(string: "?" + parts[1])?.queryItems ?? [] { query[item.name] = item.value }
        }
        let path = parts[0].split(separator: "#").first.map(String.init) ?? parts[0]
        return route(path: path, query: query)
    }

    static func route(path: String, query: [String: String]) -> ProviderRoute? {
        let segments = path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        guard let first = segments.first else { return nil }
        // The hospital's first staff notices carried app paths.
        if first == "app" {
            if segments.count >= 3, segments[1] == "hospital" { return .hospitalization(segments[2]) }
            if segments.count >= 2, segments[1] == "home" { return .section(.home) }
            return nil
        }
        guard first == "provider" else { return nil }
        let rest = Array(segments.dropFirst())
        guard let head = rest.first else { return .section(.home) }
        let id = rest.count > 1 ? rest[1] : nil

        switch head {
        case "appointments":
            return id.map { ProviderRoute.appointment($0) } ?? .section(.appointments)
        case "clients":
            if let id, rest.count >= 4, rest[2] == "pets" { return .clientPet(clientId: id, petId: rest[3]) }
            return id.map { ProviderRoute.client($0) } ?? .section(.clients)
        case "records":
            return id.map { ProviderRoute.record($0) } ?? .section(.records)
        case "hospital":
            return id.map { ProviderRoute.hospitalization($0) } ?? .section(.hospital)
        case "staff":
            return id.map { ProviderRoute.staffMember($0) } ?? .section(.staff)
        case "olfato":
            return id.map { ProviderRoute.olfatoChat($0) } ?? .section(.olfato)
        case "invoices":
            if let invoice = query["invoice"]?.nonEmpty { return .invoice(invoice) }
            return .section(.invoices)
        case "stays":
            if let stay = query["stay"]?.nonEmpty { return .stay(stay) }
            return .section(.stays)
        case "store":
            if let sale = query["sale"]?.nonEmpty { return .sale(sale) }
            return .section(.store)
        case "settings":
            return id == "notifications" ? .section(.notificationSettings) : .section(.settings)
        case "account":
            return .section(.accountSecurity)
        case "schedule", "agenda": return .section(.schedule)
        case "grooming": return .section(.grooming)
        case "groups": return .section(.groups)
        case "home-visits": return .section(.homeVisits)
        case "patients": return .section(.patients)
        case "due": return .section(.due)
        case "invitations": return .section(.invitations)
        case "inventory": return .section(.inventory)
        case "pharmacy": return .section(.pharmacy)
        case "catalog": return .section(.catalog)
        case "finance": return .section(.finance)
        case "billing": return .section(.billing)
        case "availability": return .section(.availability)
        case "rooms": return .section(.rooms)
        case "locations": return .section(.locations)
        case "relocate": return .section(.relocate)
        case "notifications": return .section(.notifications)
        default: return nil
        }
    }
}
