//
//  OlfatoNotice.swift
//  PawMiawNegocios
//
//  The Olfato AI notice's six points (web components/app/olfato/
//  olfato-consent.tsx; backend docs/patient-summaries.md and
//  docs/olfato-business-chat-plan.md): what it does, what is sent, who
//  receives it, checking it against the record, what is kept, and telling
//  your clients. The same words wherever someone reads it before confirming:
//  Team's Settings › Olfato AI and Inbox's chat gate.
//

import SwiftUI

struct OlfatoNotice: View {
    /// The narrowest a point gets before the grid wraps.
    var minimumWidth: CGFloat = 280

    static let points: [(systemImage: String, title: String, text: String)] = [
        ("bubble.left.and.text.bubble.right", "What it does", "Olfato AI writes a brief of each pet’s record, and now has a chat too, where your team asks about a pet or about the business. It reads and never acts: it doesn’t book, charge, send or change anything. Each person only gets answers from what they can already see in PawMiaw."),
        ("doc.text", "What is sent", "The question and the chat so far; the business’s name and locations, and the name and role of the person asking; the pet’s record under the brief’s rules (clinical records, including the team’s internal notes for those who can see clinical records, visit notes and reports, prescriptions, weights, the care card and the text of attached documents), plus the owner’s name and, for those who see bills, what is owed; and what the answer needs from the business: client, pet and staff names, visits, bills and payments with who billed or collected them, stock and the controlled register (prescriber, lot, folio, who moved it), and what people wrote in incidents, hospital stays, follow-ups, families’ requests to move or cancel, and groom requests. Only what the person asking is allowed to see. Email, phone and address fields and card data are never sent; emails and phone numbers found in notes are removed, but something typed in a note, such as an address, can still be sent."),
        ("building.2", "Who receives it", "An AI company outside PawMiaw receives that text to write the brief and the answers. That is not a promise that nothing is kept: it may retain data for a limited time to watch for abuse and security problems."),
        ("checkmark.shield", "Check it against the record", "The brief and the chat can leave something out or get it wrong. They say what they read. The record is what counts: check it before acting."),
        ("archivebox", "What is kept", "Chats are private to the person who asked: nobody else in the business reads them, owners included. Each one is deleted 90 days after its last message, and all of a person’s chats are deleted when they leave the business or are suspended. Owners, admins and whoever manages roles or money settings see a log of who asked about which pet, never the text; each person sees their own, and a pet’s history shows who asked about it. The log is kept 1 year."),
        ("person.crop.circle.badge.checkmark", "Your clients", "Veterinary regulators ask practices to be open with clients about using AI on their records. Tell your clients that your business uses Olfato AI, as your own policies and local rules require."),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: 10, alignment: .top)], spacing: 10) {
            ForEach(Self.points, id: \.title) { point in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: point.systemImage)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.inkOnBright)
                            .frame(width: 32, height: 32)
                            .background(Theme.aqua.opacity(0.45), in: Circle())
                        Text(L(point.title)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    }
                    Text(L(point.text)).font(Theme.text(13)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.borderSoft, lineWidth: 1))
            }
        }
    }
}
