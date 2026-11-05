//
//  SchedBookVisitScreen.swift
//  PawMiawNegocios
//
//  Booking a visit from another screen (`ProviderRoute.bookVisit`): a client's
//  page, a pet's chart, the Due list, a record, a groom. The same booking
//  flow as the Agenda's (SchedBookingSheet) as a page, with everything the
//  asking screen knows already chosen — the client, the pet, the service,
//  the day, the start, the person, the room, the notes, a walk-in. A visit
//  booked for a Due follow-up is tied to it, as the web's Due list does.
//  Booked, it goes back to the asking screen (and every screen reloads).
//

import SwiftUI

struct BookVisitScreen: View {
    let prefill: BookingPrefill

    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SchedBookingDraft
    @State private var gate: SchedGatePrompt?
    @State private var finished = false

    init(prefill: BookingPrefill) {
        self.prefill = prefill
        _draft = State(initialValue: SchedBookingDraft(
            mode: prefill.walkIn ? .walkIn : .appointment,
            day: prefill.day,
            startMinute: prefill.startMinute,
            memberId: prefill.memberId,
            roomId: prefill.roomId,
            clientId: prefill.clientId,
            petId: prefill.petId,
            serviceId: prefill.serviceId,
            notes: prefill.notes,
            followUpId: prefill.followUpId
        ))
    }

    private var canBook: Bool {
        workspace.can(.appointmentsCreate) && (workspace.can(.appointmentsAssignAnyone) || workspace.can(.appointmentsAssignSelf)) && (!prefill.walkIn || workspace.can(.clientsView))
    }

    var body: some View {
        Group {
            if canBook {
                RequireLocation {
                    SchedBookingSheet(draft: draft, onGate: { prompt in gate = wrapped(prompt) }, staysOnGate: true)
                        .environment(\.modalAsPage, true)
                }
                .navigationBarBackButtonHidden(true)
            } else {
                PageScroll { NoAccessState(message: L("Ask the workspace owner to let your role book visits.")) }
            }
        }
        // The booking's own sheet, open as the page (its tinted header is the page's header).
        .providerPage(prefill.walkIn ? L("Walk-in") : L("New visit"))
        // A walk-in stopped by a consent or a deposit: the gate opens over the form; once it is in, back.
        .sheet(item: $gate, onDismiss: { if finished { dismiss() } }) { SchedGateSheet(prompt: $0) }
    }

    /// The same prompt, noting when the walk-in went through (started, or checked in only).
    private func wrapped(_ p: SchedGatePrompt) -> SchedGatePrompt {
        SchedGatePrompt(
            petName: p.petName, verb: p.verb, kind: p.kind, message: p.message,
            attempt: p.attempt,
            onDone: { p.onDone(); finished = true },
            fallback: p.fallback.map { run in { try await run(); finished = true } },
            appointmentId: p.appointmentId, clientId: p.clientId, clientName: p.clientName, familyOnApp: p.familyOnApp,
            deposit: p.deposit, missing: p.missing,
            takeDeposit: p.takeDeposit
        )
    }
}
