//
//  Theme.swift
//  Intervally
//

import SwiftUI

/// The app's palette and type, typed rather than looked up by string.
///
/// Colour is state here: amber for the lead-in, ember for the warmup, blue for work, green
/// for rest, lavender for the cooldown. One ring, one tinted control and one label carry it;
/// everything else is monochrome on black. These are Intervally's own hues — deliberately
/// not the red / lime / cyan trio of Apple's Activity rings, and never shown as concentric
/// rings.
enum Theme {
    /// Amber — the lead-in.
    static let prepare = Color(.displayP3, red: 1.000, green: 0.769, blue: 0.231)
    /// Ember — the warmup. Warmer and deeper than the lead-in's amber, so the two read as
    /// separate phases when one follows the other. Black text 8.6:1.
    static let warmup = Color(.displayP3, red: 1.000, green: 0.502, blue: 0.200)
    /// Sky blue — work, and the brand colour.
    static let work = Color(.displayP3, red: 0.153, green: 0.749, blue: 1.000)
    /// Emerald — rest. Kept well away from the work hue; those two must be told apart mid-set.
    static let rest = Color(.displayP3, red: 0.298, green: 0.851, blue: 0.541)
    /// Lavender — the cooldown. Away from both work and rest, because it follows the last
    /// work interval directly. Black text 8.5:1.
    static let cooldown = Color(.displayP3, red: 0.706, green: 0.565, blue: 1.000)

    /// Deeper variants, used only where the display is dimmed (Always-On) and for the
    /// bottom of the completion gradient — never brighter than the active colour.
    static let prepareDimmed = Color(.displayP3, red: 0.851, green: 0.541, blue: 0.086)
    static let warmupDimmed = Color(.displayP3, red: 0.851, green: 0.361, blue: 0.078)
    static let workDimmed = Color(.sRGB, red: 0.035, green: 0.631, blue: 0.871)
    static let restDimmed = Color(.displayP3, red: 0.086, green: 0.612, blue: 0.396)
    static let cooldownDimmed = Color(.displayP3, red: 0.545, green: 0.420, blue: 0.902)
    static let brandDeep = workDimmed

    /// Label colour on any phase-tinted capsule. White on these hues measured under 3:1;
    /// black measures 9.9:1 on work and at least 5.4:1 on every dimmed variant.
    static let onTint = Color.black

    static func light(for kind: IntervalPhase.Kind) -> Color {
        switch kind {
        case .prepare: prepare
        case .warmup: warmup
        case .work: work
        case .rest: rest
        case .cooldown: cooldown
        }
    }

    static func dimmed(for kind: IntervalPhase.Kind) -> Color {
        switch kind {
        case .prepare: prepareDimmed
        case .warmup: warmupDimmed
        case .work: workDimmed
        case .rest: restDimmed
        case .cooldown: cooldownDimmed
        }
    }

    /// The unfilled part of a ring: the phase colour, faint.
    static func track(for kind: IntervalPhase.Kind) -> Color {
        light(for: kind).opacity(0.20)
    }

    // Older names, kept so call sites migrate screen by screen.
    static let workLight = work
    static let workDark = workDimmed
    static let restLight = rest
    static let restDark = restDimmed
    static let prepareLight = prepare
    static let prepareDark = prepareDimmed
    static func dark(for kind: IntervalPhase.Kind) -> Color { dimmed(for: kind) }
}

extension IntervalPhase.Kind {
    var symbolName: String {
        switch self {
        case .prepare: "hourglass"
        // The sun coming up and going down: the two ends of the session, as a pair.
        case .warmup: "sunrise.fill"
        case .work: "bolt.fill"
        // Not pause.circle.fill: that sat directly above the Pause control and read as a
        // second pause button.
        case .rest: "wind"
        case .cooldown: "sunset.fill"
        }
    }

    /// The word shown inside the ring. Short enough for the top chord of a 40mm ring;
    /// "COOLDOWN", the longest, relies on the run screen's label scaling to about 0.69.
    var shortTitle: String {
        switch self {
        case .prepare: "Ready"
        case .warmup: "Warmup"
        case .work: "Work"
        case .rest: "Rest"
        case .cooldown: "Cooldown"
        }
    }
}

extension Font {
    /// Hero numerals: SF Rounded, bold, monospaced digits.
    static func hero(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }

    /// Small uppercase phase words. Apply `.textCase(.uppercase)` and `.kerning(0.6)` at use.
    static let phaseLabel: Font = .footnote.weight(.semibold)
}
