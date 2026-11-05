//
//  HospitalVitalsTab.swift
//  PawMiawNegocios
//
//  The vitals (web hospital-vitals-tab.tsx): one sign over time (the
//  triage's quick vitals included), every reading with what is out of the
//  usual range for a dog or cat in red, a new reading, and striking one out.
//

import Charts
import SwiftUI

struct HospVitalsTab: View {
    @ObservedObject var model: HospDetailModel
    let detail: HospDetail
    let canCare: Bool

    @State private var metric: HospMetric = .temperatureC
    @State private var adding = false
    @State private var striking: HospVitals?

    private var zone: TimeZone { detail.zone }
    private var readings: [HospVitals] { (detail.vitals ?? []).filter { $0.voided != true } }
    private var newestFirst: [HospVitals] { readings.sorted { ($0.recordedAt ?? "") > ($1.recordedAt ?? "") } }

    private func series(_ metric: HospMetric) -> [(id: String, at: Date, value: Double, triage: Bool)] {
        readings.compactMap { entry in
            guard let value = metric.value(entry), let at = DateText.parse(entry.recordedAt) else { return nil }
            return (entry.id, at, value, entry.source == "triage")
        }
        .sorted { $0.at < $1.at }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(HospMetric.allCases) { entry in
                        FilterChip(title: entry.title, count: series(entry).count, isSelected: metric == entry, tone: entry.hue.color) { metric = entry }
                    }
                }
                .padding(.vertical, 2)
            }
            if canCare && detail.isAdmitted {
                HStack {
                    Spacer()
                    PMButton(L("Record vitals"), systemImage: "plus", size: .compact) { adding = true }
                }
            }
            // No readings at all: one empty state, not an empty chart over an empty list.
            if newestFirst.isEmpty {
                EmptyState(systemImage: "activity", title: L("No vitals yet."), accent: Theme.pink, panel: true)
            } else {
                chart
                Card(padding: 0, spacing: 0) {
                    ForEach(Array(newestFirst.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { RowDivider() }
                        reading(entry)
                    }
                }
            }
        }
        .sheet(isPresented: $adding) { HospAddVitalsSheet(model: model, detail: detail) }
        .sheet(item: $striking) { entry in
            ConfirmSheet(
                title: L("Strike out these vitals?"),
                message: LF("The reading of %@ leaves the chart. It stays on record as struck out.", HospFmt.dateTime(entry.recordedAt, zone)),
                confirmTitle: L("Strike out"),
                destructive: true
            ) { _ in
                do {
                    try await model.write("/vitals/\(entry.id)/void")
                    Toast.show(L("Struck out."))
                } catch { throw hospRefusal(error, fallback: "Could not strike it out.") }
            }
        }
    }

    @ViewBuilder private var chart: some View {
        let points = series(metric)
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.title).font(.brandHeading(18, relativeTo: .headline)).foregroundStyle(Theme.inkStrong)
                Spacer()
                if let last = points.last {
                    Text(HospFmt.number(last.value, digits: 2)).font(.brandHeading(24, relativeTo: .title)).foregroundStyle(Theme.inkStrong)
                    + Text(" \(metric.unit)").font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
            }
            if points.isEmpty {
                EmptyState(systemImage: "activity", title: LF("No %@ readings yet.", metric.title.lowercased()), accent: Theme.pink)
            } else {
                let values = points.map(\.value)
                let low = values.min() ?? 0, high = values.max() ?? 0
                let pad = metric == .painScore ? 1 : Swift.max(0.5, (high - low) * 0.2)
                let domain: ClosedRange<Double> = metric == .painScore ? 0...10 : (low - pad)...(high + pad)
                Chart {
                    ForEach(points, id: \.id) { point in
                        LineMark(x: .value(L("When"), point.at), y: .value(metric.title, point.value))
                            .foregroundStyle(metric.hue.color)
                            .lineStyle(StrokeStyle(lineWidth: 3))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value(L("When"), point.at), y: .value(metric.title, point.value))
                            .foregroundStyle(point.triage ? Theme.mango : metric.hue.color)
                            .symbolSize(point.triage ? 80 : 40)
                    }
                }
                .chartYScale(domain: domain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) { Text(HospFmt.clock(DateText.iso(date), zone)).font(Theme.text(12)) }
                        }
                    }
                }
                .frame(height: 220)
                if points.contains(where: \.triage) {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.mango).frame(width: 9, height: 9)
                        Text(L("Triage")).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        }
    }

    private func reading(_ entry: HospVitals) -> some View {
        let species = detail.patient?.species
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(HospFmt.dateTime(entry.recordedAt, zone)).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                    if entry.source == "triage" { Chip(text: L("Triage"), tone: .custom(Theme.mango), percent: 26) }
                }
                FlowLayout(spacing: 6) {
                    value("°C", entry.temperatureC, warn: entry.temperatureC.map { HospFmt.outOfRange(.temperatureC, $0, species: species) } ?? false)
                    value(L("HR"), entry.heartRate, warn: entry.heartRate.map { HospFmt.outOfRange(.heartRate, $0, species: species) } ?? false)
                    value(L("RR"), entry.respiratoryRate, warn: entry.respiratoryRate.map { HospFmt.outOfRange(.respiratoryRate, $0, species: species) } ?? false)
                    value(L("Pain"), entry.painScore, warn: entry.painScore.map { HospFmt.outOfRange(.painScore, $0, species: species) } ?? false)
                    value("kg", entry.weightGrams.map { ($0 / 10).rounded() / 100 }, warn: false)
                    if let gums = entry.mucousMembranes { valueText(L("Gums"), HospWords.mucous(gums), warn: false) }
                    value(L("CRT"), entry.crtSeconds, warn: false)
                }
                let by = [entry.recordedByName, entry.notes].compactMap { $0?.nonEmpty }.joined(separator: " · ")
                if !by.isEmpty { Text(by).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
            }
            Spacer(minLength: 0)
            if canCare && detail.isAdmitted && entry.source != "triage" {
                IconCircleButton(systemImage: "undo-2", label: L("Strike out")) { striking = entry }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder private func value(_ label: String, _ number: Double?, warn: Bool) -> some View {
        if let number { valueText(label, HospFmt.number(number, digits: 2), warn: warn) }
    }

    private func valueText(_ label: String, _ text: String, warn: Bool) -> some View {
        (Text("\(label) ").font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
         + Text(text).font(Theme.text(14, weight: warn ? .heavy : .bold)).monospacedDigit().foregroundStyle(warn ? Theme.destructive : Theme.inkStrong))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(warn ? AnyShapeStyle(Theme.wash(Theme.destructive, 12)) : AnyShapeStyle(Theme.surfaceMuted), in: Capsule())
    }
}

// MARK: - A new reading

private struct HospAddVitalsSheet: View {
    @ObservedObject var model: HospDetailModel
    let detail: HospDetail

    @Environment(\.dismiss) private var dismiss
    @StateObject private var form = FormState()
    @State private var draft = HospVitalsDraft()
    @State private var invalid: HospVitalsDraft.Field?
    @State private var recordedAt = Date()
    @State private var notes = ""
    @State private var saving = false

    var body: some View {
        ProviderModal(
            title: L("Record vitals"),
            subtitle: L("Any of them; the rest can stay empty."),
            systemImage: "activity",
            accent: .pink,
            isDirty: draft != HospVitalsDraft() || !notes.isEmpty,
            form: form,
            primaryTitle: L("Save vitals"),
            isWorking: saving,
            primaryIcon: "save",
            onPrimary: save
        ) {
            HospVitalsFields(draft: $draft, invalid: invalid)
                .onChange(of: draft) { _, _ in invalid = nil }
            DateTimeField(label: L("Taken at"), date: $recordedAt, zone: detail.zone, max: Date(), key: "recordedAt", form: form)
            PMTextField(L("Note"), text: $notes, multiline: true)
        }
    }

    private func save() {
        let values: [String: Any]
        switch draft.parsed() {
        case .failure(let problem):
            invalid = problem.field
            Toast.error(LF("Check %@.", HospVitalsDraft.label(problem.field)))
            return
        case .success(let parsed):
            guard let parsed else { Toast.error(L("Enter at least one value.")); return }
            values = parsed
        }
        guard form.check([("recordedAt", recordedAt.timeIntervalSinceNow > 60 ? L("That time is in the future.") : nil)]) else { return }
        var body: [String: Any?] = values.mapValues { $0 as Any? }
        body["recordedAt"] = DateText.iso(recordedAt)
        body["notes"] = notes.nonEmpty
        saving = true
        Task {
            defer { saving = false }
            do {
                try await model.write("/vitals", body: body)
                Toast.show(L("Vitals recorded."))
                dismiss()
            } catch {
                Toast.error(hospError(error, fallback: "Could not record them."))
            }
        }
    }
}
