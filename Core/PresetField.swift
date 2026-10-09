//
//  PresetField.swift
//  Intervally
//

import SwiftUI

/// A number a preset is built from, as a tile shows it: the watch's setup tiles and the
/// iPhone's editor alike. One definition, so a value set on either device is one the other
/// offers, under the same name and colour.
enum PresetField: Hashable, CaseIterable, Sendable {
    case work, rest, rounds, prepare, warmup, cooldown

    var title: String {
        switch self {
        case .work: "Work"
        case .rest: "Rest"
        case .rounds: "Rounds"
        case .prepare: "Get Ready"
        case .warmup: "Warmup"
        case .cooldown: "Cooldown"
        }
    }

    /// The phase it times. Rounds is structure, not a phase.
    var kind: IntervalPhase.Kind? {
        switch self {
        case .work: .work
        case .rest: .rest
        case .rounds: nil
        case .prepare: .prepare
        case .warmup: .warmup
        case .cooldown: .cooldown
        }
    }

    /// The warmup and cooldown are Intervally Pro.
    var isPro: Bool { self == .warmup || self == .cooldown }

    var keyPath: WritableKeyPath<IntervalWorkout, Int> {
        switch self {
        case .work: \.workSeconds
        case .rest: \.restSeconds
        case .rounds: \.rounds
        case .prepare: \.prepareSeconds
        case .warmup: \.warmupSeconds
        case .cooldown: \.cooldownSeconds
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .work: IntervalWorkout.workRange
        case .rest: IntervalWorkout.restRange
        case .rounds: IntervalWorkout.roundsRange
        case .prepare: IntervalWorkout.prepareRange
        case .warmup: IntervalWorkout.warmupRange
        case .cooldown: IntervalWorkout.cooldownRange
        }
    }

    /// The phase's colour in Classic. Rounds stays white rather than borrowing a meaning it
    /// doesn't have.
    var tint: Color { tint(in: .classic) }

    /// The phase's colour as text on `palette`'s canvas: its ink, which on black is the fill.
    /// Rounds takes the neutral, Classic's white.
    func tint(in palette: Palette) -> Color {
        kind.map(palette.ink(for:)) ?? palette.neutral
    }

    /// The editor's glyph: the phase's own, or a loop for rounds.
    var symbolName: String { kind?.symbolName ?? "repeat" }

    /// The value as its tile shows it.
    func tileText(_ value: Int) -> String {
        switch self {
        case .rounds: "\(value)"
        case .warmup, .cooldown: DurationFormat.bookend(value)
        case .work, .rest, .prepare: DurationFormat.clock(value)
        }
    }

    /// The value as VoiceOver reads it, on the tile and in the editor.
    func spoken(_ value: Int) -> String {
        switch self {
        case .rounds: DurationFormat.rounds(value)
        case .warmup, .cooldown: DurationFormat.bookendSpoken(value)
        case .work, .rest, .prepare: DurationFormat.spoken(value)
        }
    }

    /// Every value the field can be set to, in order: the watch's crown detents and the
    /// iPhone's picker rows. Durations coarsen as they grow (`ValueSteps`); the bookends turn
    /// over their own table, Off then 30-second and minute steps.
    var values: [Int] {
        switch self {
        case .rounds: ValueSteps.values(in: range, step: 1)
        case .work, .rest, .prepare: ValueSteps.values(in: range, step: 5)
        case .warmup, .cooldown: IntervalWorkout.bookendValues
        }
    }

    /// The value on the table closest to `value`, the lower on a tie: where a stored value
    /// that isn't on the table, such as 7 seconds from an older build, lands when shown.
    func nearestValue(to value: Int) -> Int {
        let table = values
        return table.min { abs($0 - value) < abs($1 - value) } ?? range.lowerBound
    }
}
