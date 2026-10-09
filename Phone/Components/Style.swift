//
//  Style.swift
//  IntervallyPhone
//

import SwiftUI

// The iPhone's share of the watch's visual language: black canvas, grey glass tiles, colour
// only where it means a phase, SF Rounded numbers.

extension View {
    /// A tile or card: white at 10% on black, 16-point continuous corners, as on the watch.
    func tileBackground() -> some View {
        background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// The one tinted control on a screen: a capsule in the brand blue with black text, which
    /// measures 9.9:1 where white measured under 3:1 (Theme.onTint).
    func prominentCapsule() -> some View {
        buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(Theme.work)
            .foregroundStyle(Theme.onTint)
    }

    /// Every phase colour's contrast was measured on black (Theme.swift), so every screen is
    /// drawn on it, under its list or scroll view too.
    func blackCanvas() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.black)
    }

    /// A list row that is only its card: no row background, separator or system inset.
    func cardRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
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
