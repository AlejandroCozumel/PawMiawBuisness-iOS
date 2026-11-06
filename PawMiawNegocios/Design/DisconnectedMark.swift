//
//  DisconnectedMark.swift
//  PawMiawNegocios
//
//  "Se desconectó de PawMiaw el 6 nov" (the family unlinked itself) or
//  "Desvinculado el 6 nov" (the business did), from a client's
//  `disconnectedAt` / `disconnectedBy` (web linking/disconnected-mark.tsx,
//  paw-miaw-backend docs/family-money.md §1). A small amber pill with the day;
//  `withDetail` adds the line saying what it means for what they owe (the
//  client's page, their account). Nothing while the client is linked or was
//  never linked. Client rows, the client page, Te deben and the account.
//

import SwiftUI

struct DisconnectedMark: View {
    /// When an unlink cleared the family; nil while linked or never linked.
    let at: String?
    /// Which side unlinked: "family" or "business".
    var by: String? = nil
    /// Also the line saying what it means for what they owe.
    var withDetail: Bool = false

    var body: some View {
        if let text = Self.text(at: at, by: by) {
            if withDetail, let detail = Self.detail(at: at, by: by) {
                VStack(alignment: .leading, spacing: 4) {
                    pill(text)
                    Text(detail).font(Theme.text(12)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                pill(text).accessibilityHint(Self.detail(at: at, by: by) ?? "")
            }
        }
    }

    private func pill(_ text: String) -> some View {
        Chip(text: text, tone: .custom(Theme.mango), icon: "link-2-off", percent: 12, border: 55)
    }

    /// The pill's words, or nil when it doesn't apply.
    static func text(at: String?, by: String?) -> String? {
        guard let date = DateText.parse(at) else { return nil }
        let day = dayLabel(date)
        return by == "business" ? LF("Unlinked on %@", day) : LF("Disconnected from PawMiaw on %@", day)
    }

    /// What it means for money, where the mark has room.
    static func detail(at: String?, by: String?) -> String? {
        guard DateText.parse(at) != nil else { return nil }
        return by == "business"
            ? L("Your business unlinked them. What they owe from before stays theirs, and a reminder in PawMiaw still reaches them.")
            : L("The family unlinked itself. What they owe from before stays theirs, and a reminder in PawMiaw still reaches them.")
    }

    /// "6 nov", with the year when it isn't this one.
    private static func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .app
        f.timeZone = Workspace.shared.timeZone
        let sameYear = DateText.calendar.component(.year, from: date) == DateText.calendar.component(.year, from: Date())
        f.setLocalizedDateFormatFromTemplate(sameYear ? "dMMM" : "dMMMyyyy")
        return f.string(from: date).replacingOccurrences(of: ".", with: "")
    }
}
