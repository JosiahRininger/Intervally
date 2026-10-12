//
//  IntervalPlan.swift
//  Intervally
//

import Foundation

/// One segment of a workout: the prepare countdown, a warmup, a work or rest interval, or
/// a cooldown.
struct IntervalPhase: Equatable, Sendable, Identifiable {
    /// Raw values are written to Health as workout metadata, so they must never be renamed.
    enum Kind: String, Codable, Equatable, Sendable {
        case prepare, warmup, work, rest, cooldown

        var title: String {
            switch self {
            case .prepare: "Get Ready"
            case .warmup: "Warmup"
            case .work: "Work"
            case .rest: "Rest"
            case .cooldown: "Cooldown"
            }
        }

        /// The easy phases either side of the intervals. They belong to no round, so
        /// anything that says "round 3 of 8" leaves them out.
        var isBookend: Bool { self == .warmup || self == .cooldown }
    }

    let id: Int
    let kind: Kind
    /// What the preset calls it, and its figure: the phase's own unless renamed.
    var title: String { label?.name ?? kind.title }
    var symbol: PhaseSymbol { label?.symbol ?? kind.defaultSymbol }
    /// The preset's label for the phase; nil for the phase's own name and figure.
    var label: PhaseLabel? = nil
    let duration: TimeInterval
    /// 1-based round this phase belongs to. The prepare and warmup phases report round 1;
    /// the cooldown reports the final round.
    let round: Int
    /// Seconds from the start of the workout at which this phase begins.
    let start: TimeInterval

    var end: TimeInterval { start + duration }
}

/// An immutable, fully-expanded schedule for one run of a workout.
///
/// The plan is the single source of truth for *what should be happening at time t*.
/// Nothing in the plan mutates while a workout runs, so recovering after the app is
/// suspended is just a matter of recomputing the position for the new elapsed time.
struct IntervalPlan: Equatable, Sendable {
    let workout: IntervalWorkout
    let phases: [IntervalPhase]
    let totalDuration: TimeInterval

    init(workout: IntervalWorkout) {
        let config = workout.clamped
        self.workout = config

        var phases: [IntervalPhase] = []
        var cursor: TimeInterval = 0
        var id = 0

        func append(_ kind: IntervalPhase.Kind, _ seconds: Int, round: Int) {
            guard seconds > 0 else { return }
            phases.append(
                IntervalPhase(
                    id: id, kind: kind, label: config.phaseLabels?[kind.rawValue],
                    duration: TimeInterval(seconds), round: round, start: cursor
                )
            )
            id += 1
            cursor += TimeInterval(seconds)
        }

        append(.prepare, config.prepareSeconds, round: 1)
        append(.warmup, config.warmupSeconds, round: 1)
        for round in 1...config.rounds {
            append(.work, config.workSeconds, round: round)
            // No trailing rest after the final round: the legacy app always emitted a
            // rest at the end, so every workout finished by idling through a rest period.
            // The cooldown follows the last work interval directly for the same reason.
            if round < config.rounds {
                append(.rest, config.restSeconds, round: round)
            }
        }
        append(.cooldown, config.cooldownSeconds, round: config.rounds)

        self.phases = phases
        self.totalDuration = cursor
    }

    /// The total number of work intervals, used for "round 3 of 8" style labels. The
    /// bookends are not rounds and never change it.
    var totalRounds: Int { workout.clamped.rounds }

}

// MARK: - Position

extension IntervalPlan {
    /// Where the workout stands at a given elapsed time.
    struct Position: Equatable, Sendable {
        /// Index into `phases`, or `nil` once the workout has finished.
        let phaseIndex: Int?
        let phase: IntervalPhase?
        /// Seconds left in the current phase, rounded up for display.
        let remainingInPhase: TimeInterval
        /// Seconds left in the whole workout.
        let remainingTotal: TimeInterval
        /// 0...1 through the current phase.
        let phaseProgress: Double
        /// 0...1 through the whole workout.
        let totalProgress: Double

        var isFinished: Bool { phaseIndex == nil }
    }

    /// Computes the position for an elapsed time. Pure: the same input always yields the
    /// same output, which is what makes recovery after suspension trivial and testable.
    func position(atElapsed elapsed: TimeInterval) -> Position {
        let t = max(0, elapsed)

        guard t < totalDuration, !phases.isEmpty else {
            return Position(
                phaseIndex: nil,
                phase: nil,
                remainingInPhase: 0,
                remainingTotal: 0,
                phaseProgress: 1,
                totalProgress: 1
            )
        }

        // Phases are contiguous and cover [0, totalDuration), so the phase containing `t`
        // is the last one that starts at or before it. Binary search keeps this O(log n)
        // for the display tick.
        var low = 0
        var high = phases.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if phases[mid].start <= t {
                low = mid
            } else {
                high = mid - 1
            }
        }

        let index = low
        let phase = phases[index]
        let intoPhase = t - phase.start
        let remainingInPhase = max(0, phase.duration - intoPhase)

        return Position(
            phaseIndex: index,
            phase: phase,
            remainingInPhase: remainingInPhase,
            remainingTotal: max(0, totalDuration - t),
            phaseProgress: phase.duration > 0 ? min(1, max(0, intoPhase / phase.duration)) : 1,
            totalProgress: totalDuration > 0 ? min(1, max(0, t / totalDuration)) : 1
        )
    }
}
