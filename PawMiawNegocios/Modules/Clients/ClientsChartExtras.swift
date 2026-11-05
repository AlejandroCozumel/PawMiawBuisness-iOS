//
//  ClientsChartExtras.swift
//  PawMiawNegocios
//
//  The smaller cards of a pet's chart and a client's page (web:
//  prescriptions/prescriptions-card.tsx, hospital/patient-hospital-card.tsx,
//  consents/consent-document.tsx, care/report-view.tsx, care/walk-route-
//  drawing.tsx, stays/client-stays-section.tsx): the pet's prescriptions,
//  its hospitalizations, a consent to read and print, a visit's full report
//  and the client's stays.
//

import SwiftUI

// MARK: - Prescriptions

/// The latest five prescriptions of the pet (web `PrescriptionsCard` compact); each opens in the Pharmacy's page.
struct ClientsPrescriptionsCard: View {
    let chart: ClientsChart
    @EnvironmentObject private var workspace: Workspace
    @State private var items: [StockPrescription]?
    @State private var failed = false
    @State private var writing = false
    @State private var opened: StockRxTarget?

    var body: some View {
        let rights = StockRxRights(workspace)
        if rights.canRead {
            SectionCard(title: L("Prescriptions"), subtitle: L("Signed, printable, and in the family’s app"), icon: "pill", accent: Theme.lime) {
                // Empty, the button waits in the empty state; once there is one, "another" sits up here.
                if rights.canWrite && !(items ?? []).isEmpty {
                    PMButton(L("Prescribe"), systemImage: "plus", size: .compact) { writing = true }
                }
            } content: {
                VStack(spacing: 0) {
                    if let items {
                        if items.isEmpty {
                            EmptyState(systemImage: "pill", title: L("No prescriptions yet."), actionTitle: rights.canWrite ? L("Prescribe") : nil, action: { writing = true }, accent: Theme.mango)
                        } else {
                            ForEach(items) { prescription in
                                NavigationLink { StockPrescriptionScreen(prescriptionId: prescription.id) } label: { row(prescription) }
                                    .buttonStyle(.plain)
                            }
                        }
                    } else if failed {
                        ErrorState(message: L("Something went wrong. Try again.")) { await load() }
                    } else {
                        LoadingState()
                    }
                }
                .padding(8)
            }
            .reloadsOnScope { await load() }
            .sheet(isPresented: $writing) {
                StockPrescriptionSheet(
                    pet: StockRxPet(clientId: chart.client.id, petId: chart.pet.id, petName: chart.pet.name, species: chart.pet.species, photoUrl: chart.pet.photoUrl, clientName: chart.client.name),
                    draft: nil
                ) { saved in
                    Task { await load() }
                    opened = StockRxTarget(id: saved.id)
                }
            }
            .navigationDestination(item: $opened) { target in StockPrescriptionScreen(prescriptionId: target.id) }
        }
    }

    private func row(_ p: StockPrescription) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.medicines.nonEmpty ?? "—").font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                Text([p.folio, p.prescriberName, ClientsMatches.fullDay(p.signedAt ?? p.createdAt)].compactMap { $0?.nonEmpty }.joined(separator: " · "))
                    .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            Spacer(minLength: 6)
            if p.controlled == true { StockControlledChip() }
            StatusChip(text: StockRxWords.state(p.state), state: StockRxWords.stateState(p.state))
            Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private func load() async {
        do {
            let page: StockPrescriptionPage = try await API.get("/provider-prescriptions", query: ["providerClientPetId": chart.pet.id, "limit": "5"])
            items = page.items
            failed = false
        } catch is CancellationError {
        } catch {
            failed = true
        }
    }
}

// MARK: - Hospitalizations

private struct ClientsHospitalList: Decodable {
    let hospitalizations: [HospSummary]?
}

/// The pet's stays in the hospital (web `PatientHospitalCard`; vets and emergencies only): the current one
/// first, each with its status edge, opening its page. Nothing when it has none.
struct ClientsHospitalCard: View {
    let items: [HospSummary]

    /// Every stay but the cancelled ones (the page reads them with the chart).
    static func load(petId: String) async -> [HospSummary] {
        let answer: ClientsHospitalList? = try? await API.get("/provider-hospital/hospitalizations", query: ["providerClientPetId": petId])
        return (answer?.hospitalizations ?? []).filter { $0.status != "cancelled" }
    }

    var body: some View {
        if !items.isEmpty {
            Card(padding: 16, spacing: 8) {
                HStack(spacing: 8) {
                    Glyph("bed-double", size: 16).foregroundStyle(Theme.blue)
                    Text(L("Hospitalizations")).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                }
                VStack(spacing: 6) {
                    ForEach(items.prefix(8)) { stay in row(stay) }
                }
            }
        }
    }

    private func row(_ stay: HospSummary) -> some View {
        let active = stay.status == "admitted" || stay.status == "pending"
        return NavigationLink(value: ProviderRoute.hospitalization(stay.id)) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    FlowLayout(spacing: 6) {
                        HospStatusChip(status: stay.status)
                        if active, let day = stay.dayNumber { Text(LF("Day %d", day)).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft) }
                        if active, let triage = stay.triagePriority { HospTriageBadge(priority: triage) }
                    }
                    Text([ClientsText.dayTime(stay.admittedAt ?? stay.requestedAt), stay.reason?.nonEmpty].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 0)
                Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
            .background(active ? AnyShapeStyle(Theme.wash(Theme.pink, 8)) : AnyShapeStyle(Theme.surface))
            .overlay(alignment: .leading) {
                Rectangle().fill(ProviderState.hospital(stay.status).color).frame(width: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - A consent to read and print

struct ClientsConsentTarget: Identifiable, Hashable {
    let id: String
    let petName: String?
}

enum ClientsConsentWords {
    static func status(_ status: String?) -> String {
        switch status {
        case "draft": L("Needs an amount")
        case "pending": L("Waiting for signature")
        case "signed": L("Signed@consent")
        case "declined": L("Declined@consent")
        case "cancelled": L("Withdrawn")
        case "revoked": L("Revoked@consent")
        default: status ?? "—"
        }
    }

    static func state(_ status: String?) -> ProviderState {
        switch status {
        case "signed": .done
        case "pending": .active
        case "draft": .waiting
        case "declined", "revoked": .problem
        default: .closed
        }
    }

    static func side(_ side: String?) -> String { side == "family" ? L("the family") : L("the business") }

    /// The line under a consent in the history.
    static func line(_ consent: JSONValue) -> String? {
        let date = { (key: String) in ClientsText.dayTime(consent[key]?.string) }
        let reason = { (key: String) in consent[key]?.string?.nonEmpty.map { " — \($0)" } ?? "" }
        let name = consent["signerName"]?.string?.nonEmpty ?? "—"
        switch consent["status"]?.string {
        case "draft": return L("Waiting for the amount before it can be signed.")
        case "pending":
            if consent["sentAt"]?.string?.nonEmpty != nil { return LF("Sent %@@consent", date("sentAt")) }
            let by = consent["origin"]?.string == "auto" ? " · \(L("required by the service"))" : consent["requestedByName"]?.string?.nonEmpty.map { " · \($0)" } ?? ""
            return LF("Asked %1$@%2$@", date("requestedAt"), by)
        case "signed":
            switch consent["signedVia"]?.string {
            case "clinic_device": return LF("Signed by %1$@ here · %2$@", name, date("signedAt"))
            case "email_link": return LF("Signed by %1$@ through a link · %2$@", name, date("signedAt"))
            default: return LF("Signed by %1$@ in the app · %2$@", name, date("signedAt"))
            }
        case "declined": return LF("Declined %1$@%2$@", date("declinedAt"), reason("declineReason"))
        case "cancelled": return LF("Withdrawn %1$@%2$@", date("cancelledAt"), reason("cancelReason"))
        case "revoked": return LF("Revoked by %1$@ %2$@%3$@", side(consent["revokedBySide"]?.string), date("revokedAt"), reason("revokeReason"))
        default: return nil
        }
    }
}

// MARK: - A visit's full report

/// A groom, walk or training report as the chart shows it (web `ReportView`): what is worth a look first, the walk's route, the rows, what changed, photos and the note.
struct ClientsReportBlock: View {
    let report: SvcReport

    /// The report of a timeline visit (kept as plain JSON there).
    static func decode(_ value: JSONValue?) -> SvcReport? {
        guard let value, !value.isNull, let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(SvcReport.self, from: data)
    }

    var body: some View {
        let concerns = SvcReportText.rows(report).contains { $0.concern }
        VStack(alignment: .leading, spacing: 12) {
            ClientsChartSectionTitle(text: SvcReportText.title(report.kind, category: nil))
            if concerns {
                HStack(spacing: 6) {
                    Glyph("triangle-alert", size: 14)
                    Text(L("Worth a look").uppercased()).font(Theme.text(12, weight: .heavy)).tracking(1.2)
                }
                .foregroundStyle(Theme.destructive)
            }
            if report.kind == "walk", let route = report.route {
                WalkRouteView(route: route)
            }
            SvcReportView(report: report)
            if let difference = report.differenceNote?.nonEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Glyph("shuffle", size: 14)
                        Text(L("What changed").uppercased()).font(Theme.text(12, weight: .heavy)).tracking(1.2)
                    }
                    .foregroundStyle(Theme.inkStrong)
                    Text(difference).font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.wash(Theme.mango, 16), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            }
        }
    }
}

// MARK: - The client's stays

struct ClientsStayPet: Decodable, Hashable { let petName: String? }

struct ClientsStay: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String?
    let status: String?
    let checkInDay: String?
    let checkOutDay: String?
    let unitName: String?
    let pets: [ClientsStayPet]?
}

private struct ClientsStayList: Decodable {
    let today: String?
    let items: [ClientsStay]
}

/// A client's stays as the page shows them: those on now or still ahead, then the last three.
struct ClientsStaySplit: Hashable {
    var active: [ClientsStay] = []
    var past: [ClientsStay] = []
}

/// The client's stays (web `ClientStaysSection`): staying now and coming first, then the last few that
/// ended, each opening its stay. Nothing at all when they have none (the page reads them with the client).
struct ClientsStaysSection: View {
    let stays: ClientsStaySplit

    private var active: [ClientsStay] { stays.active }
    private var past: [ClientsStay] { stays.past }

    var body: some View {
        if !active.isEmpty || !past.isEmpty {
            SectionCard(title: L("Stays"), icon: "bed-double", accent: Theme.aqua) {
                NavigationLink(value: ProviderRoute.section(.stays)) {
                    Text(L("Open stays")).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.blue)
                }
                .buttonStyle(.plain)
            } content: {
                let all = active + past
                VStack(spacing: 0) {
                    ForEach(Array(all.enumerated()), id: \.element.id) { index, stay in
                        if index > 0 { RowDivider() }
                        NavigationLink(value: ProviderRoute.stay(stay.id)) { row(stay) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row(_ stay: ClientsStay) -> some View {
        let names = (stay.pets ?? []).compactMap(\.petName).joined(separator: ", ")
        let kind = stay.kind == "home_sitting" ? L("Home sitting") : stay.kind == "daycare" ? L("Daycare") : L("Boarding")
        return HStack(spacing: 12) {
            Glyph(stay.kind == "home_sitting" ? "house" : stay.kind == "daycare" ? "sun" : "bed-double", size: 16)
                .foregroundStyle(Theme.blue)
                .frame(width: 36, height: 36)
                .background(Theme.wash(Theme.aqua, 22), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text([names.nonEmpty, kind].compactMap { $0 }.joined(separator: " · ")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                Text([range(stay), stay.unitName?.nonEmpty].compactMap { $0 }.joined(separator: " · ")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            Spacer(minLength: 6)
            StatusChip(text: status(stay.status), state: ProviderState.stay(stay.status))
            Glyph("chevron-right", size: 16).foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func range(_ stay: ClientsStay) -> String {
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = TimeZone(identifier: "UTC")
        let parse = { (day: String?) -> Date? in
            guard let day else { return nil }
            let p = DateFormatter(); p.locale = Locale(identifier: "en_US_POSIX"); p.timeZone = TimeZone(identifier: "UTC"); p.dateFormat = "yyyy-MM-dd"
            return p.date(from: String(day.prefix(10)))
        }
        guard let start = parse(stay.checkInDay) else { return "—" }
        let end = parse(stay.checkOutDay)
        if stay.kind == "daycare" || end == nil || stay.checkInDay == stay.checkOutDay {
            f.setLocalizedDateFormatFromTemplate("EEEdMMM")
            return f.string(from: start).capitalizedFirst
        }
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return "\(f.string(from: start)) – \(f.string(from: end ?? start))".capitalizedFirst
    }

    private func status(_ status: String?) -> String {
        switch status {
        case "requested": L("Requested@stay")
        case "confirmed": L("Confirmed@stay")
        case "checked_in": L("Staying")
        case "checked_out": L("Checked out")
        case "cancelled": L("Cancelled@stay")
        case "no_show": L("No-show")
        default: status ?? "—"
        }
    }

    static func load(clientId: String) async -> ClientsStaySplit {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        let from = DateText.dayKey(calendar.date(byAdding: .day, value: -120, to: today) ?? today, zone: TimeZone(identifier: "UTC"))
        let to = DateText.dayKey(calendar.date(byAdding: .day, value: 365, to: today) ?? today, zone: TimeZone(identifier: "UTC"))
        guard let list: ClientsStayList = try? await API.get("/provider-stays", query: ["from": from, "to": to, "clientId": clientId]) else { return ClientsStaySplit() }
        let day = list.today ?? DateText.dayKey(today)
        let isActive = { (stay: ClientsStay) in
            stay.status == "checked_in" || ((stay.status == "confirmed" || stay.status == "requested") && (stay.checkOutDay ?? "") >= day)
        }
        return ClientsStaySplit(
            active: list.items.filter(isActive),
            past: Array(list.items.filter { !isActive($0) }.sorted { ($0.checkInDay ?? "") > ($1.checkInDay ?? "") }.prefix(3))
        )
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
