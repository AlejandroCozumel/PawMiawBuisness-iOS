//
//  Lists.swift
//  PawMiawNegocios
//
//  The plumbing of a list inside a card (web: the cards of Cuentas, Tienda, Farmacia,
//  Inventario, Expedientes, the agenda list): the card that runs its rows edge to edge, its
//  toolbar strip, the footer with the count, "Showing 25 of 81", the row that asks for the
//  next 20, a day's band, and rows between hairlines. One look each.
//

import SwiftUI

/// The frame of a card whose rows run edge to edge (rows draw their own dividers).
/// `.card`: the standard card (web `rounded-card border bg-surface shadow-card overflow-hidden`).
/// `.panel`: web pharmacy-bits `ListPanel` (a 2 pt edge, no shadow).
/// `.box`: a bordered box of rows inside a sheet (16 corners, 2 pt edge: the lots, a review).
enum ListCardStyle { case card, panel, box }

/// A card whose rows run edge to edge: `ListCard { rows }`, or `.listCard()` on a stack.
struct ListCard<Content: View>: View {
    typealias Style = ListCardStyle
    var style: Style = .card
    @ViewBuilder let content: () -> Content

    init(style: Style = .card, @ViewBuilder content: @escaping () -> Content) {
        self.style = style
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .listCard(style)
    }
}

extension View {
    /// Frames a stack of rows as a list card (see `ListCardStyle`).
    func listCard(_ style: ListCardStyle = .card) -> some View {
        modifier(ListCardFrame(style: style))
    }
}

private struct ListCardFrame: ViewModifier {
    let style: ListCardStyle

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: style == .box ? Theme.boxRadius : Theme.cardRadius, style: .continuous)
        let framed = content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style == .box ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.surface), in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.borderSoft, lineWidth: style == .card ? 1 : 2))
        if style == .card { framed.cardShadow() } else { framed }
    }
}

/// A card's toolbar strip (web: a card's toolbar row, padding 16/12, a hairline under it).
struct CardToolbar<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: spacing) { content() }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            RowDivider()
        }
    }
}

/// A card's footer line under a list (web: the pagination footer — a top hairline, "12
/// clientes" bold and tabular, " · what they add up to" grey, controls at the right).
struct ListFooter<Trailing: View>: View {
    let count: String
    var detail: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            RowDivider()
            HStack(spacing: 8) {
                Text(count).font(.brandText(14, weight: .bold)).monospacedDigit().foregroundStyle(Theme.inkStrong)
                if let detail { Text("· \(detail)").font(.brandText(14)).foregroundStyle(Theme.inkSoft).lineLimit(1) }
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

extension ListFooter where Trailing == EmptyView {
    init(count: String, detail: String? = nil) {
        self.init(count: count, detail: detail, trailing: { EmptyView() })
    }
}

/// The count under a list (web pharmacy-bits `ListCount`): "Showing 25 of 81", or what the
/// list holds when all of it shows. `one` / `many` are the words ("1 prescription", "%d
/// prescriptions"), already in the screen's language. Counts are the server's.
struct ListCount: View {
    let shown: Int
    let total: Int
    let one: String
    let many: String

    var body: some View {
        if total > 0 {
            Text(shown < total ? LF("Showing %d of %d", shown, total) : (total == 1 ? one : String(format: many, locale: .app, total)))
                .font(Theme.text(14)).foregroundStyle(Theme.inkSoft).padding(.horizontal, 4)
        }
    }
}

/// The next 20 of a list, asked for when its last row shows (the owner's infinite scroll).
struct LoadMoreRow: View {
    let hasMore: Bool
    var busy: Bool = false
    let load: () -> Void

    var body: some View {
        if hasMore {
            HStack {
                Spacer()
                ProgressView().tint(Theme.blue)
                Spacer()
            }
            .padding(.vertical, 12)
            .onAppear { if !busy { load() } }
        }
    }
}

/// A day's band over a list's rows. Each web list has its own:
/// - `.agenda` (agenda-list `DayHeading`): 14 bold on the muted band, "Hoy" in blue + " · 4 de nov".
/// - `.records` (record `DayHeading`): 12 extrabold navy on muted 60%.
/// - `.bills` (`InvoiceDayHeader`): 12 bold navy on muted 35%, its count at the right.
/// - `.caps` (the Pharmacy's lists): 12 bold uppercase, tracked, grey on the muted band.
struct DayBand: View {
    enum Style { case agenda, records, bills, caps }
    let title: String
    /// `.agenda`: the day's name before the date ("Hoy"), blue when `highlighted`.
    var lead: String? = nil
    var highlighted: Bool = false
    /// Words at the right (a count).
    var trailing: String? = nil
    var style: Style = .agenda

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            switch style {
            case .agenda:
                if let lead {
                    Text(lead).font(Theme.text(14, weight: .bold)).foregroundStyle(highlighted ? Theme.blue : Theme.inkStrong)
                    Text("· " + title).font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                } else {
                    Text(title).font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
                }
            case .records:
                Text(title).font(.brandText(12, weight: .heavy)).tracking(0.24).foregroundStyle(Theme.inkStrong)
            case .bills:
                Text(title).font(Theme.text(12, weight: .bold)).foregroundStyle(Theme.inkStrong)
            case .caps:
                Text(title.uppercased()).font(.brandText(12, weight: .bold)).tracking(12 * 0.12).foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing).font(Theme.text(12, weight: style == .agenda ? .semibold : .bold)).monospacedDigit().foregroundStyle(Theme.inkSoft)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, style == .agenda ? 8 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill)
        .overlay(alignment: .bottom) { if style != .bills { RowDivider() } }
    }

    private var fill: AnyShapeStyle {
        switch style {
        case .agenda, .caps: AnyShapeStyle(Theme.surfaceMuted)
        case .records: AnyShapeStyle(Theme.mix(Theme.surfaceMuted, 60, with: Theme.surface))
        case .bills: AnyShapeStyle(Theme.wash(Theme.surfaceMuted, 35))
        }
    }
}

/// Rows with a hairline between them (web `divide-y`).
struct RowList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { RowDivider() }
                row(item)
            }
        }
    }
}
