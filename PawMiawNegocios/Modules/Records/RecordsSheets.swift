//
//  RecordsSheets.swift
//  PawMiawNegocios
//
//  The Records page's small sheets: signing from a list (sign-record-sheet),
//  closing a finished visit's paperwork without a note (paperwork-waive-sheet,
//  owners and admins), and the days filter (date-range-menu).
//

import SwiftUI

// MARK: - Sign

/// Signing where the record hasn't been read: one look at what the family is about
/// to receive before it goes. The record's own page signs in one tap.
struct RecordsSignSheet: View {
    let record: RecordsRecord
    var onSigned: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        ProviderModal(
            title: L("Sign this record?"),
            subtitle: "\(record.kind.label) · \(record.petText)",
            systemImage: "badge-check",
            accent: .aqua,
            primaryTitle: working ? L("Signing…") : L("Sign"),
            isWorking: working,
            cancelTitle: L("Not yet"),
            primaryIcon: "badge-check",
            onPrimary: sign
        ) {
            ContextPills(client: record.clientText, linked: record.onPawMiaw, pets: [record.petText])
            HStack(spacing: 12) {
                PetAvatar(name: record.petName, species: record.petSpecies, photoURL: record.petPhotoUrl, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        recordsTypeChip(record.kind)
                        Text(RecordsText.day(record.eventAt)).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                    }
                    Text(record.titleText).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))

            ModalSection(title: record.onPawMiaw ? L("What the family will see") : L("What goes into the chart")) {
                let summary = RecordsPayload.summaryLine(record)
                if summary.isEmpty {
                    Text(L("This record has no summary or notes yet.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                } else {
                    Text(summary)
                        .font(Theme.text(14))
                        .foregroundStyle(Theme.inkStrong)
                        .lineLimit(4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.wash(Theme.aqua, 12), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                bullet("eye", record.onPawMiaw
                       ? LF("%@ sees it in their PawMiaw app as soon as it is signed.", record.clientText)
                       : LF("%@ isn’t on PawMiaw — it becomes part of the chart you can share.", record.clientText))
                bullet("lock", L("The staff-only note stays with your team."))
                bullet("badge-check", L("Later changes are marked as a correction."))
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Glyph(icon, size: 16).foregroundStyle(Theme.blue).padding(.top, 2)
            Text(text).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
        }
    }

    private func sign() {
        working = true
        Task {
            defer { working = false }
            do {
                _ = try await RecordsAPI.sign(record.id)
                Toast.show(record.onPawMiaw ? L("Signed. The family can see it now.") : L("Signed. It is part of the chart now."))
                announceDataChanged()
                onSigned?()
                dismiss()
            } catch {
                Toast.error(error, fallback: L("Could not sign this record."))
            }
        }
    }
}

// MARK: - Paperwork needs no note

/// A finished visit's paperwork closes itself when the note is written or signed, or the
/// report filled (docs/visit-paperwork.md). This is the one way out, for an owner or admin:
/// say why the visit needs none. The reason stays on it, in its history.
struct RecordsWaiveSheet: View {
    let followUp: RecordsFollowUp

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var reason = ""
    @State private var note = ""
    @State private var working = false

    /// The server takes only these.
    private static let reasons = ["client_left_before_exam", "service_did_not_require_clinical_documentation", "duplicate_task", "created_in_error", "other"]

    var body: some View {
        ProviderModal(
            title: L("This visit needs no note?"),
            subtitle: "\(followUp.petName?.nonEmpty ?? "—") · \(RecordsText.followUpTitle(followUp.title))",
            systemImage: "file-x-2",
            accent: .aqua,
            isDirty: !reason.isEmpty || !note.isEmpty,
            form: form,
            primaryTitle: L("Close without a note"),
            primaryVariant: .destructive,
            isWorking: working,
            cancelTitle: L("Back"),
            primaryIcon: "file-x-2",
            onPrimary: submit
        ) {
            Text(L("Only when there is truly nothing to write. Otherwise, write it on the visit: it closes on its own."))
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
            // The web's "Why" heading over round chips (ChoiceChips), then the box for "Other".
            ModalSection(title: L("Why")) {
                PillPicker(options: reasonOptions, selection: $reason)
                    .accessibilityLabel(L("Why"))
                    .id("reason")
                if reason == "other" {
                    TextField(L("What happened"), text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .fieldChrome(invalid: form.error("note") != nil, multiline: true)
                        .onChange(of: note) { _, _ in form.clear("note") }
                        .id("note")
                }
                if let problem = form.error("reason") ?? form.error("note") {
                    Text(problem).font(Theme.text(12, weight: .medium)).foregroundStyle(Theme.coral)
                }
            }
        }
        .onChange(of: reason) { _, _ in form.clear("reason") }
    }

    private var reasonOptions: [(value: String, title: String)] {
        Self.reasons.map { reason -> (value: String, title: String) in
            (value: reason, title: L(RecordsText.resolutionReasons[reason] ?? reason))
        }
    }

    private func submit() {
        guard form.check([
            ("reason", reason.isEmpty ? L("Choose why it needs no note.") : nil),
            ("note", reason == "other" && note.nonEmpty == nil ? L("Write why it needs no note.") : nil),
        ]) else { return }
        working = true
        Task {
            defer { working = false }
            do {
                _ = try await RecordsAPI.updateFollowUp(followUp.id, body: [
                    "status": "canceled",
                    "resolutionType": "resolved_without_record",
                    "resolutionReason": reason,
                    "outcomeNote": note.nonEmpty,
                ])
                Toast.show(L("Closed without a note. The reason stays on record."))
                announceDataChanged()
                dismiss()
            } catch {
                form.apply(error, known: ["resolutionReason": "reason", "outcomeNote": "note"])
            }
        }
    }
}

// MARK: - Days

enum RecordsRange {
    enum Preset: String, CaseIterable { case today, week, month }

    static func name(_ preset: Preset) -> String {
        switch preset {
        case .today: L("Today")
        case .week: L("This week")
        case .month: L("This month")
        }
    }

    /// Today, this week (Monday to Sunday) and this month, on the business's clock.
    static func days(_ preset: Preset) -> (from: String, to: String) {
        let calendar = DateText.calendar
        let now = Date()
        switch preset {
        case .today:
            let key = DateText.dayKey(now)
            return (key, key)
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? now
            return (DateText.dayKey(start), DateText.dayKey(end))
        case .month:
            let interval = calendar.dateInterval(of: .month, for: now)
            let start = interval?.start ?? now
            let end = interval.map { calendar.date(byAdding: .day, value: -1, to: $0.end) ?? now } ?? now
            return (DateText.dayKey(start), DateText.dayKey(end))
        }
    }

    static func match(from: String?, to: String?) -> Preset? {
        Preset.allCases.first { let d = days($0); return d.from == from && d.to == to }
    }

    /// What a range is called: its quick choice, else its days ("1 sep – 15 sep"); nil for none.
    static func label(from: String?, to: String?) -> String? {
        if from == nil && to == nil { return nil }
        if let preset = match(from: from, to: to) { return name(preset) }
        if let from, let to { return from == to ? RecordsText.day(from) : "\(RecordsText.day(from)) – \(RecordsText.day(to))" }
        if let from { return LF("From %@@day", RecordsText.day(from)) }
        return LF("Until %@@day", RecordsText.day(to))
    }
}

/// The days filter: today, this week, this month, any date, or a stretch chosen by hand.
struct RecordsRangeSheet: View {
    let title: String
    let presets: [RecordsRange.Preset]
    let from: String?
    let to: String?
    let onChange: (String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var choice = "all"
    @State private var start = DateText.dayKey(Date())
    @State private var end = DateText.dayKey(Date())

    var body: some View {
        ProviderModal(title: title, systemImage: "calendar-range", accent: .aqua, primaryTitle: L("Show"), onPrimary: apply) {
            ChoiceCards(options: options, selection: $choice)
            if choice == "custom" {
                ModalSection(title: L("Or choose the days"), systemImage: "calendar-range") {
                    DayField(label: L("From"), day: $start)
                    DayField(label: L("Until"), day: $end, min: start)
                    Text(length == 1 ? L("1 day") : LF("%d days", length)).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if from == nil && to == nil { choice = "all" }
            else if let preset = RecordsRange.match(from: from, to: to), presets.contains(preset) { choice = preset.rawValue }
            else {
                choice = "custom"
                start = from ?? to ?? DateText.dayKey(Date())
                end = to ?? start
            }
        }
        .onChange(of: start) { _, value in if end < value { end = value } }
    }

    /// Days from the first to the last, both counted.
    private var length: Int {
        guard let first = DateText.parse(start), let last = DateText.parse(max(start, end)) else { return 1 }
        return Int((last.timeIntervalSince(first) / 86_400).rounded()) + 1
    }

    private var options: [(value: String, title: String, subtitle: String?)] {
        var list: [(value: String, title: String, subtitle: String?)] = presets.map { preset -> (value: String, title: String, subtitle: String?) in
            (value: preset.rawValue, title: RecordsRange.name(preset), subtitle: nil)
        }
        list.append((value: "all", title: L("Any date"), subtitle: nil))
        list.append((value: "custom", title: L("Choose the days"), subtitle: nil))
        return list
    }

    private func apply() {
        switch choice {
        case "all": onChange(nil, nil)
        case "custom": onChange(start, max(start, end))
        default:
            if let preset = RecordsRange.Preset(rawValue: choice) {
                let days = RecordsRange.days(preset)
                onChange(days.from, days.to)
            }
        }
        dismiss()
    }
}
