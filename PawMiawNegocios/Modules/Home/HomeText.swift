//
//  HomeText.swift
//  PawMiawNegocios
//
//  Home's small rules, as the web's today-board.tsx, visit-row.tsx,
//  home-hub.tsx and lib/home-hub.ts word them: a lane's state, the clock on
//  a row, a bill in a few words, the activities and their counts.
//

import SwiftUI

enum HomeText {
    /// "20 min", "1 h", "1 h 56" (visits-copy `shortDuration`).
    static func shortDuration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest)"
    }

    /// A clinic that only sees patients says "Con el veterinario"; as soon as it grooms, boards or walks, "En servicio".
    static func clinicOnly(_ categories: [String]) -> Bool {
        categories.isEmpty || categories.allSatisfy { ["vet", "emergency", "pharmacy", "other"].contains($0) }
    }

    static func inServiceTitle(_ categories: [String]) -> String {
        clinicOnly(categories) ? L("With the vet") : L("In service")
    }

    /// The row's one-word state; the in-visit one follows the business.
    static func laneLabel(_ lane: HomeLane, categories: [String]) -> String {
        switch lane {
        case .upcoming: return L("Next up")
        case .waiting: return L("Waiting@home")
        case .inService:
            return categories.isEmpty || categories.contains("vet") || categories.contains("emergency") ? L("In the visit") : L("In service")
        case .toPay: return L("To pay")
        case .done: return L("Done@home")
        case .missed: return L("Missed@home")
        }
    }

    /// The stripe and state colour of a row (visit-row.tsx `stateTone`): late and missed in red.
    static func laneColor(_ visit: HomeVisit) -> Color {
        let late = visit.laneValue == .upcoming && (visit.lateMinutes ?? 0) > 0
        if late || visit.laneValue == .missed { return Theme.destructive }
        switch visit.laneValue {
        case .inService: return Theme.blue
        case .waiting: return Theme.mango
        case .toPay: return Theme.pink
        case .done: return Theme.borderSoft
        default: return Theme.aqua
        }
    }

    /// "Espera 12 min" / "Lleva 1 h" / "20 min tarde" under the time, in its colour.
    static func clock(_ visit: HomeVisit) -> (text: String, color: Color)? {
        if visit.laneValue == .waiting, let minutes = visit.waitingMinutes {
            return (LF("Waits %@", shortDuration(minutes)), minutes >= 20 ? Theme.destructive : Theme.mango)
        }
        if visit.laneValue == .inService, let minutes = visit.inServiceMinutes {
            return (LF("In for %@", shortDuration(minutes)), Theme.blue)
        }
        if visit.laneValue == .upcoming, let minutes = visit.lateMinutes, minutes > 0 {
            return (LF("%@ late", shortDuration(minutes)), Theme.destructive)
        }
        return nil
    }

    /// The bill's stage on a Home card (lib/visit-bill.ts `billStage`, without the lines).
    static func billStage(_ visit: HomeVisit) -> String {
        guard let invoice = visit.invoice else {
            if visit.billing == "no_charge" { return "no_charge" }
            switch visit.status {
            case "scheduled", "checked_in": return "not_started"
            case "cancelled", "canceled", "no_show": return "canceled"
            default: return "no_bill"
            }
        }
        let total = invoice.totalAmount ?? 0
        if invoice.status == "canceled" { return visit.billing == "no_charge" ? "no_charge" : "canceled" }
        if invoice.status == "paid" || (invoice.status != "draft" && (invoice.balanceDueAmount ?? 0) <= 0) {
            return total == 0 ? "covered" : "paid"
        }
        if invoice.status == "draft" { return total > 0 && (invoice.unpricedLines ?? 0) == 0 ? "building" : "needs_price" }
        if (invoice.amountPaid ?? 0) > 0 { return "part_paid" }
        return "ready"
    }

    static func billStageLabel(_ stage: String) -> String {
        switch stage {
        case "not_started": return L("Not started")
        case "no_charge": return L("No charge")
        case "canceled": return L("Canceled@bill")
        case "no_bill": return L("No bill yet")
        case "needs_price": return L("Needs a price")
        case "building": return L("Being built")
        case "ready": return L("Ready to charge")
        case "part_paid": return L("Part paid")
        case "paid": return L("Paid@bill")
        default: return L("Nothing to charge")
        }
    }

    /// The row's bill in a few words: "Lista para cobrar · Dr. Ricardo · $500.00 MXN", "Falta precio".
    static func billChip(_ visit: HomeVisit) -> (text: String, tone: Chip.Tone)? {
        guard visit.laneValue == .toPay || visit.laneValue == .done else { return nil }
        if visit.billing == "needs_price" || visit.billing == "needs_bill" { return (L("Needs a price"), .warn) }
        guard let invoice = visit.invoice else { return nil }
        let stage = billStage(visit)
        let amount = Money.format(stage == "building" ? invoice.totalAmount : invoice.balanceDueAmount, currency: invoice.currency)
        switch stage {
        case "building": return ("\(billStageLabel(stage)) · \(amount)", .info)
        case "ready": return ([billStageLabel(stage), invoice.sentBy?.name, amount].compactMap { $0?.nonEmpty }.joined(separator: " · "), .warn)
        case "part_paid": return (LF("Part paid · %@ to pay", amount), .warn)
        case "covered": return (billStageLabel(stage), .good)
        default: return nil
        }
    }

    /// "Luna", "Luna y Coco", "Luna, Coco y Kira".
    static func names(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "—" }
        return names.dropLast().joined(separator: ", ") + " " + L("and") + " " + (names.last ?? "")
    }

    /// "Hoy 10:30" for today's, "lun 20 oct" for an earlier day's.
    static func dayLabel(_ day: String?) -> String {
        guard let day, let date = DateText.parse(day) else { return "—" }
        return DateText.day(date)
    }

    static func confirmationWord(_ kind: String?) -> String {
        switch kind {
        case "reschedule_requested": return L("asked to reschedule")
        case "cancellation_requested": return L("asked to cancel")
        case "delivery_failed": return L("confirmation not delivered")
        case "declined": return L("declined the visit")
        case "expired": return L("did not confirm")
        default: return kind ?? ""
        }
    }

    static func leftOpenWord(_ status: String?) -> String {
        switch status {
        case "scheduled": return L("never marked")
        case "checked_in": return L("still waiting")
        case "in_progress": return L("still in progress")
        default: return status ?? ""
        }
    }

    /// "en 3 horas", "en 15 min": when a held time is released.
    static func releaseIn(_ iso: String?) -> String? {
        guard let date = DateText.parse(iso) else { return nil }
        let minutes = Int((date.timeIntervalSinceNow / 60).rounded())
        if minutes <= 1 { return L("now@release") }
        if minutes < 60 { return LF("in %d min", minutes) }
        let hours = Int((Double(minutes) / 60).rounded())
        return hours == 1 ? L("in 1 hour") : LF("in %d hours", hours)
    }

    /// The groom's stage words (lib/groom-stages.ts).
    static func groomStage(_ stage: String?, simple: Bool = false) -> String {
        switch stage {
        case "scheduled": return L("Scheduled@groom")
        case "waiting": return L("Waiting@groom")
        case "bath": return simple ? L("In progress@groom") : L("Bath@groom")
        case "styling": return L("Cut & dry")
        case "ready": return L("Ready for pickup")
        case "done": return L("Done@groom")
        default: return stage ?? ""
        }
    }

    static func groomState(_ stage: String?) -> ProviderState { ProviderState.groom(stage) }
}

/// Home as the day's hub (lib/home-hub.ts): visits, grooms, stays, the hospital and home visits, by activity.
enum HomeActivity: String, CaseIterable, Identifiable {
    case all, appointments, grooming, stays, hospital, home

    var id: String { rawValue }

    static let order: [HomeActivity] = [.appointments, .grooming, .stays, .hospital, .home]

    var label: String {
        switch self {
        case .all: L("All@activity")
        case .appointments: L("Appointments@activity")
        case .grooming: L("Grooming")
        case .stays: L("Stays")
        case .hospital: L("Hospital")
        case .home: L("At home")
        }
    }

    /// The web's `ACTIVITY_ICON` (Lucide).
    var icon: String {
        switch self {
        case .all: "layout-grid"
        case .appointments: "calendar-clock"
        case .grooming: "scissors"
        case .stays: "bed-double"
        case .hospital: "hospital"
        case .home: "house"
        }
    }

    /// The activity's colour (lib/provider-colors.ts `ACTIVITY_HUE`; Todos is the page's blue).
    var accent: Color {
        switch self {
        case .all: Theme.blue
        case .appointments: Hue.sky.color
        case .grooming: Hue.lavender.color
        case .stays: Hue.periwinkle.color
        case .hospital: Hue.teal.color
        case .home: Hue.mint.color
        }
    }

    /// Where its "Ver todo" goes.
    var section: ProviderSection {
        switch self {
        case .all, .appointments: .schedule
        case .grooming: .grooming
        case .stays: .stays
        case .hospital: .hospital
        case .home: .homeVisits
        }
    }

    func shows(_ module: HomeActivity) -> Bool { self == .all || self == module }

    /// The chips: "Todos" and each module this person has, only when there is more than one.
    static func options(_ modules: [HomeActivity]) -> [HomeActivity] {
        let own = order.filter { modules.contains($0) }
        return own.count > 1 ? [.all] + own : own
    }
}

/// Home's remembered activity, per business and member on this device.
enum HomeActivityStore {
    static func key(_ clinicId: String?, _ memberId: String?) -> String? {
        guard let clinicId else { return nil }
        return "pawmiaw_negocios_home_activity_\(clinicId)_\(memberId ?? "me")"
    }

    static func read(_ key: String?) -> HomeActivity? {
        guard let key, let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return HomeActivity(rawValue: raw)
    }

    static func save(_ key: String?, _ activity: HomeActivity) {
        guard let key else { return }
        if activity == .all { UserDefaults.standard.removeObject(forKey: key) } else { UserDefaults.standard.set(activity.rawValue, forKey: key) }
    }
}
