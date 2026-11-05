//
//  SignaturePad.swift
//  PawMiawNegocios
//
//  Sign with a finger: the strokes become the PNG data URL the server keeps
//  (consents, closing a file, a prescription, the person's own signature).
//

import SwiftUI
import UIKit

struct SignaturePad: View {
    @Binding var strokes: [[CGPoint]]
    var placeholder: String = L("Sign here")
    var height: CGFloat = 160
    /// A "Clear" link under the pad (screens with their own clear button leave it off).
    var showsClear: Bool = false
    /// The drawing's own size; the PNG is made at it.
    static let size = CGSize(width: 600, height: 200)

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white)
                    RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1.5)
                    if strokes.isEmpty {
                        Text(placeholder).font(Theme.text(14)).foregroundStyle(Color(red: 102 / 255, green: 117 / 255, blue: 138 / 255))
                    }
                    Path { path in Self.draw(strokes, into: &path, scale: CGSize(width: proxy.size.width / Self.size.width, height: proxy.size.height / Self.size.height)) }
                        .stroke(Theme.navy, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let point = CGPoint(x: value.location.x / Swift.max(proxy.size.width, 1) * Self.size.width,
                                                y: value.location.y / Swift.max(proxy.size.height, 1) * Self.size.height)
                            if value.translation == .zero || strokes.isEmpty { strokes.append([point]) } else { strokes[strokes.count - 1].append(point) }
                        }
                )
            }
            .frame(height: height)
            if showsClear && !strokes.isEmpty {
                Button(L("Clear")) { strokes = [] }
                    .font(Theme.text(14, weight: .bold))
                    .foregroundStyle(Theme.blueText)
            }
        }
        .accessibilityLabel(L("Your signature"))
    }

    static func draw(_ strokes: [[CGPoint]], into path: inout Path, scale: CGSize) {
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            path.move(to: CGPoint(x: first.x * scale.width, y: first.y * scale.height))
            if stroke.count == 1 { path.addLine(to: CGPoint(x: first.x * scale.width + 0.5, y: first.y * scale.height + 0.5)) }
            for point in stroke.dropFirst() { path.addLine(to: CGPoint(x: point.x * scale.width, y: point.y * scale.height)) }
        }
    }

    /// The signature as the server takes it: a PNG data URL (nil when nothing is drawn).
    static func pngDataURL(_ strokes: [[CGPoint]]) -> String? {
        guard let data = pngData(strokes) else { return nil }
        return "data:image/png;base64,\(data.base64EncodedString())"
    }

    /// The signature as PNG bytes, for a multipart upload.
    static func pngData(_ strokes: [[CGPoint]]) -> Data? {
        let points = strokes.reduce(0) { $0 + $1.count }
        guard points >= 2 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            var path = Path()
            draw(strokes, into: &path, scale: CGSize(width: 1, height: 1))
            let bezier = UIBezierPath(cgPath: path.cgPath)
            bezier.lineWidth = 3
            bezier.lineCapStyle = .round
            bezier.lineJoinStyle = .round
            UIColor(red: 16 / 255, green: 34 / 255, blue: 59 / 255, alpha: 1).setStroke()
            bezier.stroke()
        }
        return image.pngData()
    }
}
