//
//  Style.swift
//  IntervallyPhone
//

import SwiftUI

// The iPhone's share of the watch's visual language: one canvas, cards on it, colour only
// where it means a phase, SF Rounded numbers. Classic draws it black with grey glass tiles;
// Pastel draws it light (`Palette.pastelPhone`). Every surface reads the palette, so a new
// theme redraws every screen in place.

/// How wide a screen's cards and rows may grow. On iPad and iPhone Duo's inner screen a card
/// drawn for a phone would otherwise stretch across the whole page.
enum ReadableWidth {
    static let column: CGFloat = 640
}

extension View {
    /// A list's rows in a centred column no wider than `maxWidth`, while the list keeps the
    /// whole width for scrolling. On every iPhone the margin is nothing at all.
    func readableList(maxWidth: CGFloat = ReadableWidth.column) -> some View {
        modifier(ReadableList(maxWidth: maxWidth))
    }

    /// A scroll view's content in a centred column no wider than `maxWidth`.
    func readableColumn(maxWidth: CGFloat = ReadableWidth.column) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }

    /// A tile or card: Classic's white at 10% on black, Pastel's pale pink, 16-point
    /// continuous corners, as on the watch.
    func tileBackground() -> some View {
        modifier(TileBackground())
    }

    /// The one tinted control on a screen: a capsule in the brand colour with black text,
    /// which measures 9.9:1 on Classic's blue and 8.1:1 on Pastel's pink, where white
    /// measured under 3:1 (`Palette.onTint`).
    func prominentCapsule() -> some View {
        modifier(ProminentCapsule())
    }

    /// Every screen is drawn on the theme's canvas, under its list or scroll view too: every
    /// phase colour's contrast was measured on it (Theme.swift).
    func appCanvas() -> some View {
        modifier(AppCanvas())
    }

    /// A list row that is only its card: no row background, separator or system inset.
    func cardRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }
}

private struct TileBackground: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content.background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ProminentCapsule: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(palette.brand)
            .foregroundStyle(palette.onTint)
    }
}

private struct AppCanvas: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(palette.canvas)
    }
}

/// A small uppercase heading over a group of cards.
struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.phaseLabel)
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Marks a control that opens the paywall rather than doing its job, for a free user.
/// Hidden from VoiceOver: the control's hint says the same thing in words.
struct ProBadge: View {
    var body: some View {
        Label("PRO", systemImage: "lock.fill")
            .font(.caption.weight(.bold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .accessibilityHidden(true)
    }
}

private struct ReadableList: ViewModifier {
    let maxWidth: CGFloat
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, ReadableList.margin(width: width, maxWidth: maxWidth), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    static func margin(width: CGFloat, maxWidth: CGFloat) -> CGFloat {
        max(0, ((width - maxWidth) / 2).rounded(.down))
    }
}
