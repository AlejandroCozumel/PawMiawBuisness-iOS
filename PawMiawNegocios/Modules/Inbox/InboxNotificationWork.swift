//
//  InboxNotificationWork.swift
//  PawMiawNegocios
//
//  The work a notification opens rather than its page (web
//  notifications/provider-notification-work.tsx `openInPlace`): a follow-up
//  to schedule opens the booking with its client, pet, day, person and note
//  (the visit is tied to the follow-up); a visit's missing record opens the
//  record sheet on its client, pet, visit and type; an invoice opens the bill;
//  a client's request about a visit opens the visit. Everything else goes to
//  the notification's page.
//

import Foundation

enum InboxNotificationWork {
    enum Outcome {
        /// Open this screen.
        case push(ProviderRoute)
        /// Handled here (a refusal was said): nothing opens.
        case stay
        /// Not work to open in place: the notification's page.
        case page
    }

    /// Whether this notification is opened in place (it may need a read first).
    static func handles(_ n: InboxNotification) -> Bool {
        guard n.sourceId?.nonEmpty != nil else { return false }
        switch (n.sourceType ?? "", n.category ?? "") {
        case ("provider_follow_up", "provider_follow_ups"), ("provider_follow_up", "records_documentation"),
             ("provider_invoice", "billing"), ("provider_appointment_confirmation", "appointments"):
            return true
        default:
            return false
        }
    }

    static func open(_ n: InboxNotification, workspace: Workspace) async -> Outcome {
        guard let id = n.sourceId?.nonEmpty else { return .page }
        switch (n.sourceType ?? "", n.category ?? "") {
        case ("provider_follow_up", "provider_follow_ups"):
            guard workspace.can(.appointmentsCreate) else {
                Toast.error(L("You do not have permission to schedule this follow-up."))
                return .stay
            }
            guard let followUp = await followUp(id) else { return .page }
            return .push(.bookVisit(booking(for: followUp)))
        case ("provider_follow_up", "records_documentation"):
            guard workspace.can(.recordsCreate) else {
                Toast.error(L("You do not have permission to create the missing record."))
                return .stay
            }
            guard let followUp = await followUp(id) else { return .page }
            return .push(.newRecord(RecordPrefill(
                clientId: followUp.providerClientId,
                petId: followUp.providerClientPetId,
                appointmentId: followUp.providerAppointmentId?.nonEmpty,
                recordType: primaryRecordType(followUp.appointmentServiceLabel?.nonEmpty ?? followUp.title ?? "")
            )))
        case ("provider_invoice", "billing"):
            return .push(.invoice(id))
        case ("provider_appointment_confirmation", "appointments"):
            return .push(.appointment(id))
        default:
            return .page
        }
    }

    private static func followUp(_ id: String) async -> RecordsFollowUp? {
        let path = "/provider-follow-ups/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)"
        return try? await API.get(path)
    }

    /// The follow-up's visit: its client and pet, on its due day (today when that has passed), with the
    /// person it is assigned to and a note of what it is for.
    private static func booking(for followUp: RecordsFollowUp) -> BookingPrefill {
        let today = DateText.dayKey()
        let due = followUp.dueAt?.nonEmpty.map { RecordsText.dayKey($0) } ?? today
        let notes = [
            LF("Clinical follow-up: %@", RecordsText.followUpTitle(followUp.title)),
            followUp.note?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty.map { LF("Note: %@", $0) },
            followUp.recordTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty.map { LF("Source record: %@", $0) },
        ].compactMap { $0 }.joined(separator: "\n")
        return BookingPrefill(
            clientId: followUp.providerClientId,
            petId: followUp.providerClientPetId,
            day: due < today ? today : due,
            memberId: followUp.assignedMember?.id?.nonEmpty,
            followUpId: followUp.id,
            notes: notes
        )
    }

    /// The record a visit asks for, from its service (lib/provider-appointment-records.ts).
    static func primaryRecordType(_ serviceLabel: String) -> String {
        let label = serviceLabel.trimmingCharacters(in: .whitespaces).lowercased()
        if label.contains("vaccination") { return "vaccination" }
        if label.contains("lab") || label.contains("test") { return "lab_result" }
        return "vet_visit"
    }
}
