//
//  WalkRouteView.swift
//  PawMiawNegocios
//
//  The route a walk took, as the server draws it (the report's `route`:
//  a box, line segments, distance, moving time and gaps). Shown on a
//  walk's report in Domicilio and on the pet's chart.
//

import SwiftUI

/// A line on a plain panel, a dot where it started and one where it ended. No tiles, no street map,
/// no coordinates — the shape arrives fitted to a box. A break in the line is a stretch not recorded.
struct WalkRouteView: View {
    let route: JSONValue

    private struct Shape {
        let box: Double
        let lines: [[CGPoint]]
        let km: Double
        let minutes: Int
        let gaps: Bool
    }

    private var shape: Shape? {
        guard let segments = route["segments"]?.array else { return nil }
        let lines: [[CGPoint]] = segments.compactMap { segment in
            let numbers = (segment.array ?? []).compactMap(\.double)
            var points: [CGPoint] = []
            var index = 0
            while index + 1 < numbers.count {
                if numbers[index].isFinite && numbers[index + 1].isFinite { points.append(CGPoint(x: numbers[index], y: numbers[index + 1])) }
                index += 2
            }
            return points.count >= 2 ? points : nil
        }
        guard !lines.isEmpty else { return nil }
        let box = (route["box"]?.double).flatMap { $0 > 0 ? $0 : nil } ?? 1000
        let km = ((route["distanceM"]?.double ?? 0) / 10).rounded() / 100
        let minutes = max(1, Int(((route["movingSeconds"]?.double ?? 0) / 60).rounded()))
        return Shape(box: box, lines: lines, km: km, minutes: minutes, gaps: route["hasGaps"]?.bool == true || lines.count > 1)
    }

    var body: some View {
        if let shape {
            VStack(alignment: .leading, spacing: 0) {
                Canvas { context, size in
                    let side = min(size.width, size.height)
                    let scale = side / shape.box
                    let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
                    func place(_ point: CGPoint) -> CGPoint { CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale) }
                    for line in shape.lines {
                        var path = Path()
                        path.addLines(line.map(place))
                        context.stroke(path, with: .color(Theme.blue), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                    let radius = max(5, side * 0.02)
                    if let first = shape.lines.first?.first {
                        let at = place(first)
                        let dot = Path(ellipseIn: CGRect(x: at.x - radius, y: at.y - radius, width: radius * 2, height: radius * 2))
                        context.fill(dot, with: .color(Theme.surface))
                        context.stroke(dot, with: .color(Theme.blue), lineWidth: 4)
                    }
                    if let end = shape.lines.last?.last {
                        let at = place(end)
                        let dot = Path(ellipseIn: CGRect(x: at.x - radius, y: at.y - radius, width: radius * 2, height: radius * 2))
                        context.fill(dot, with: .color(Theme.blue))
                        context.stroke(dot, with: .color(Theme.surface), lineWidth: 2)
                    }
                }
                .aspectRatio(16 / 10, contentMode: .fit)
                .background(Theme.surfaceMuted)
                .accessibilityLabel(L("Route of the walk drawn as a line"))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(L("Walk route").uppercased()).font(.brandText(11, weight: .heavy)).tracking(1).foregroundStyle(Theme.inkSoft)
                        Spacer()
                        Text(LF("%@ km · %d min", shape.km.formatted(.number.precision(.fractionLength(0...2))), shape.minutes))
                            .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong).monospacedDigit()
                    }
                    if shape.gaps {
                        Text(L("Part of the walk wasn’t recorded")).font(Theme.captionFont).foregroundStyle(Theme.inkSoft)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.borderSoft, lineWidth: 1))
        }
    }
}
