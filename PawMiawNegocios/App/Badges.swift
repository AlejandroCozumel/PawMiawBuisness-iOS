//
//  Badges.swift
//  PawMiawNegocios
//
//  The numbers beside the sections (web provider-shell.tsx): records to
//  complete, pharmacy waiting, late stays, hospital doses needing someone,
//  grooms needing someone, late home visits, visits to charge. Each from the
//  server, refreshed every minute while the app is open, only for whoever
//  may see that section.
//

import SwiftUI

private struct CountPage: Decodable { let total: Int? }
private struct LateStays: Decodable { let lateArrivals: Int?; let lateDepartures: Int? }
private struct HospitalAttention: Decodable { let due: Int?; let late: Int?; let missed: Int? }
private struct GroomingDay: Decodable { let needsSomeone: Int? }
private struct HomeDayCounts: Decodable { let late: Int? }
private struct HomeDay: Decodable { let counts: HomeDayCounts? }
private struct ChargingCount: Decodable { let count: Int? }
private struct PharmacyCounts: Decodable { let badge: Int? }
private struct OlfatoChatStatus: Decodable { let available: Bool?; let workspaceOn: Bool?; let noticeOutdated: Bool? }
private struct OlfatoViewer: Decodable { let chat: OlfatoChatStatus? }
private struct PharmacyFlags: Decodable { let prescribes: Bool?; let dispenses: Bool? }

@MainActor
final class Badges: ObservableObject {
    @Published private(set) var counts: [ProviderSection: Int] = [:]
    @Published private(set) var olfatoShown = false
    @Published private(set) var pharmacyShown = false
    @Published private(set) var unreadNotifications = 0

    func count(_ section: ProviderSection) -> Int { counts[section] ?? 0 }

    func refresh(_ w: Workspace) async {
        guard w.current != nil else { return }
        let location: String? = w.locationId
        var next: [ProviderSection: Int] = [:]

        let asksOlfato = w.can(.olfatoChat)
        let asksStays = w.offers(.boarding, .daycare) && w.can(.staysView)
        let asksHospital = w.offers(.vet, .emergency) && w.can(.hospitalView)
        let asksGrooming = w.offers(.groomer) && w.can(.appointmentsView)
        let asksHome = w.offersHomeVisits && w.canAny(.appointmentsView, .staysView)
        let asksCharging = w.moneyLevel >= .frontDesk
        let asksPharmacy = w.can(.recordsApprove)
        let recordRules = (sign: w.can(.recordsApprove) && w.can(.recordsView), paperwork: w.can(.followupsView), unfinished: w.can(.recordsView))

        async let olfato: OlfatoViewer? = asksOlfato ? try? await API.get("/provider-olfato/viewer") : nil
        async let records: Int = Self.recordsToComplete(sign: recordRules.sign, paperwork: recordRules.paperwork, unfinished: recordRules.unfinished, location: location)
        async let stays: LateStays? = asksStays ? try? await API.get("/provider-stays/late", query: ["locationId": location]) : nil
        async let hospital: HospitalAttention? = asksHospital ? try? await API.get("/provider-hospital/attention", query: ["locationId": location]) : nil
        async let grooming: GroomingDay? = asksGrooming ? try? await API.get("/provider-grooming/today", query: ["locationId": location]) : nil
        async let home: HomeDay? = asksHome ? try? await API.get("/provider-home-visits/today", query: ["locationId": location]) : nil
        async let charging: ChargingCount? = asksCharging ? try? await API.get("/provider-charging", query: ["locationId": location, "limit": "0", "offset": "0"]) : nil
        async let pharmacy: PharmacyCounts? = asksPharmacy ? try? await API.get("/provider-pharmacy/counts") : nil
        async let unread: Int = Self.unreadNotifications()

        let viewer = await olfato
        olfatoShown = asksOlfato && (viewer?.chat?.available ?? false) && (viewer?.chat?.workspaceOn ?? false)
        next[.records] = await records
        if let late = await stays { next[.stays] = (late.lateArrivals ?? 0) + (late.lateDepartures ?? 0) }
        if let attention = await hospital { next[.hospital] = (attention.due ?? 0) + (attention.late ?? 0) + (attention.missed ?? 0) }
        next[.grooming] = await grooming?.needsSomeone ?? 0
        next[.homeVisits] = await home?.counts?.late ?? 0
        next[.invoices] = await charging?.count ?? 0
        let pharmacyCounts = await pharmacy
        next[.pharmacy] = pharmacyCounts?.badge ?? 0
        // The Pharmacy: for a business that prescribes or dispenses (web lib/pharmacy.ts).
        let categories = w.current?.enabledCategories ?? []
        let offersPharmacy = categories.isEmpty || categories.contains { ["vet", "pharmacy", "emergency"].contains($0) }
        pharmacyShown = offersPharmacy && w.canAny(.recordsView, .salesSell, .billingEditInvoice)
        unreadNotifications = await unread
        counts = next
    }

    private static func recordsToComplete(sign: Bool, paperwork: Bool, unfinished: Bool, location: String?) async -> Int {
        var total = 0
        if sign {
            let page: CountPage? = try? await API.get("/provider-records", query: ["status": "draft", "readyToSign": "true", "limit": "1", "offset": "0", "locationId": location])
            total += page?.total ?? 0
        }
        if paperwork {
            let page: CountPage? = try? await API.get("/provider-follow-ups", query: ["status": "to_do", "kind": "paperwork", "limit": "1", "offset": "0"])
            total += page?.total ?? 0
        }
        if unfinished {
            let page: CountPage? = try? await API.get("/provider-records", query: ["status": "draft", "unfinished": "true", "limit": "1", "offset": "0", "locationId": location])
            total += page?.total ?? 0
        }
        return total
    }

    private struct UnreadSummary: Decodable { let unreadCount: Int? }

    private static func unreadNotifications() async -> Int {
        let body: UnreadSummary? = try? await API.get("/provider-notifications/unread-summary")
        return body?.unreadCount ?? 0
    }
}
