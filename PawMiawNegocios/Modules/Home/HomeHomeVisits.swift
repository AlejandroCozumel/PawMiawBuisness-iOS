//
//  HomeHomeVisits.swift
//  PawMiawNegocios
//
//  Domicilio on Home, under its own tile (web today/home-hub.tsx
//  `HomeVisitsSection`): every home visit not done yet, in the order they
//  are made, with the one step it takes next — "Llegué", then "Terminar"
//  ("Salir" for a home stay's visit) — exactly as on the Home visits page,
//  whose pieces it uses. Everything else about a visit (the way there,
//  access, the report) is on that page.
//

import SwiftUI

struct HomeHomeVisitsSection: View {
    let day: SvcHomeVisitsDay?

    @Environment(HomeActions.self) private var actions: HomeActions?

    private var openPage: (() -> Void)? {
        guard let actions else { return nil }
        return { actions.route = .section(.homeVisits) }
    }

    var body: some View {
        if let day {
            let items = day.items
            if items.isEmpty {
                VStack(spacing: 0) {
                    EmptyState(systemImage: "house", title: L("No home visits today"), message: L("The day's visits to families' homes show up here."), accent: Theme.blue)
                    NavigationLink(value: ProviderRoute.section(.homeVisits)) {
                        PMButtonContent(title: L("Open home visits"), trailingIcon: "chevron-right", variant: .link, size: .slim)
                    }
                    .buttonStyle(.pm(.link, size: .slim))
                    .padding(.top, -12)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
            } else {
                let open = items.filter { !$0.closed }
                let done = items.filter { $0.phase == "done" }.count
                // The same remembered choice as Domicilio's cards under Todos: it is one section.
                HomeStrip(storageKey: "home", title: HomeActivity.home.label, count: items.count, dot: HomeActivity.home.accent,
                          linkTitle: L("Open home visits"), link: openPage) {
                    if open.isEmpty {
                        HStack(spacing: 6) {
                            Glyph("check-check", size: 16).foregroundStyle(Theme.blue)
                            Text(L("Every home visit today is done.")).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    } else {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            RowList(items: Array(open.prefix(HomeCap.rows * 2))) { item in
                                HomeHomeVisitRow(item: item, day: day, now: context.date)
                            }
                        }
                        if open.count > HomeCap.rows * 2 {
                            HomeStripMore(more: open.count - HomeCap.rows * 2, route: .section(.homeVisits))
                        }
                        // The count sits under the list.
                        if done > 0 {
                            RowDivider()
                            Text(LF("%d of %d done", done, items.count))
                                .font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
        } else {
            LoadingState()
        }
    }
}

private struct HomeHomeVisitRow: View {
    let item: SvcHomeVisitItem
    let day: SvcHomeVisitsDay
    let now: Date

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(HomeActions.self) private var actions: HomeActions?
    @State private var topHeight: CGFloat = 0

    private var phone: Bool { sizeClass != .regular }
    private var lateAfter: Int { day.settings?.lateAfterMinutes ?? 15 }
    private var late: (late: Bool, minutes: Int) { SvcHomeRules.late(item, now: now, lateAfter: lateAfter, isToday: day.isToday ?? false) }
    private var runningLong: Bool { SvcHomeRules.runningLong(item, now: now, lateAfter: lateAfter) }

    /// The row's one word and its tone (lib/home-visits.ts `visitChip`).
    private var chip: (text: String, tone: Chip.Tone)? {
        if late.late { return (LF("Late · %d min", late.minutes), .danger) }
        switch item.phase {
        case "on_my_way": return (L("On the way"), .info)
        case "in_progress": return runningLong ? (L("Running long"), .warn) : (L("In progress"), .info)
        default: return nil
        }
    }

    /// The edge's colour (home-hub.tsx `HOME_TONE`).
    private var tone: Color {
        if late.late { return Theme.destructive }
        switch item.phase {
        case "in_progress": return runningLong ? Theme.mango : Theme.blue
        case "done": return Theme.inkSoft
        case "missed": return Theme.destructive
        default: return Theme.aqua
        }
    }

    private var hasSteps: Bool { actions != nil && (item.actions?.arrive == true || item.actions?.finish == true) }

    var body: some View {
        EdgeRow(edge: tone, time: DateText.time(item.startsAt)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    if item.pets.count > 1 {
                        PetStack(pets: item.pets.map { (name: $0.name, species: $0.species, photo: $0.photoUrl) }, size: 40)
                    } else {
                        PetAvatar(name: item.pets.first?.name ?? item.petNames, species: item.pets.first?.species, photoURL: item.pets.first?.photoUrl, size: 40)
                    }
                    details.frame(maxWidth: .infinity, alignment: .leading)
                    if !phone, hasSteps { steps }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
                if phone, hasSteps { steps }
            }
            .alignmentGuide(VerticalAlignment.center) { d in phone && hasSteps && topHeight > 0 ? topHeight / 2 : d[VerticalAlignment.center] }
        }
        // The row opens the Home visits page; its buttons take the next step.
        .onTapGesture { actions?.route = .section(.homeVisits) }
        .accessibilityAction(named: L("Open home visits")) { actions?.route = .section(.homeVisits) }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text(item.petNames).font(Theme.text(16, weight: .bold)).foregroundColor(Theme.inkStrong)
             + Text(" · " + item.serviceText).font(Theme.text(16)).foregroundColor(Theme.inkSoft))
                .lineLimit(1)
            let details = [item.client.name, item.address?.line, item.assigned?.name.map { LF("with %@", $0) }].compactMap { $0?.nonEmpty }.joined(separator: " · ")
            if !details.isEmpty { Text(details).font(Theme.text(12.8)).foregroundStyle(Theme.inkSoft).lineLimit(1).padding(.top, 2) }
            if let chip {
                FlowLayout(spacing: 6) { Chip(text: chip.text, tone: chip.tone) }.padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private var steps: some View {
        if let actions {
            let busy = actions.isBusy(item.id)
            HStack(spacing: 6) {
                if item.actions?.arrive == true {
                    PMButton(L("I’ve arrived"), systemImage: "door-open", size: .compact, fullWidth: phone, isWorking: busy) { actions.arriveHome(item) }
                }
                if item.actions?.finish == true {
                    if item.isStay || SvcHomeRules.finishesHere(item.serviceCategory) {
                        PMButton(item.isStay ? L("Leave@home") : L("Finish@visit"), systemImage: item.isStay ? "log-out" : "badge-check", size: .compact, fullWidth: phone, isWorking: busy) {
                            actions.finishHome(item, timeZone: day.timeZone, canWrite: day.viewer?.canAct ?? false)
                        }
                    } else if let id = item.appointmentId {
                        NavigationLink(value: ProviderRoute.appointment(id)) { PMButtonContent(title: L("Open visit"), icon: "external-link") }
                            .buttonStyle(.pm(.outline, size: .compact, fullWidth: phone))
                    }
                }
            }
        }
    }
}
