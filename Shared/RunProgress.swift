//
//  RunProgress.swift
//  Intervally
//

import Foundation

/// What a persisted run looks like at a given instant.
///
/// Lives here, not in the widget, because the widget's timeline is pure logic over a
/// snapshot and deserves tests — and because the extension and the app must agree on what
/// the snapshot means.
struct RunProgress: Equatable, Sendable {
    let phaseKind: IntervalPhase.Kind
    /// Absolute instant the current phase ends, for `Text(timerInterval:)`.
    let phaseEnd: Date
    let round: Int
    let totalRounds: Int
    let isPaused: Bool
}

extension RunProgress {
    /// "WORK · 3 of 8", "GET READY · 1 of 8". A bookend belongs to no round, so it shows its
    /// name alone: "WARMUP", never "WARMUP · 1 of 8".
    var phaseLine: String {
        let name = phaseKind.title.uppercased()
        return phaseKind.isBookend ? name : "\(name) · \(round) of \(totalRounds)"
    }

    /// "Work 3/8" for the inline complication; a bookend is just "Warmup".
    var compactLine: String {
        phaseKind.isBookend ? phaseKind.title : "\(phaseKind.title) \(round)/\(totalRounds)"
    }
}

extension RunSnapshot {
    var plan: IntervalPlan { IntervalPlan(workout: workout) }

    /// Elapsed time at `date`. A paused snapshot is frozen at the moment it was paused.
    func elapsed(at date: Date) -> TimeInterval {
        pausedElapsed ?? date.timeIntervalSince(anchor)
    }

    /// The run's state at `date`, or nil once it has finished.
    func progress(at date: Date) -> RunProgress? {
        let plan = self.plan
        let position = plan.position(atElapsed: elapsed(at: date))
        guard let phase = position.phase else { return nil }
        return RunProgress(
            phaseKind: phase.kind,
            // Derived from the anchor, so it stays an absolute instant the system can count
            // down to without the widget being woken.
            phaseEnd: anchor.addingTimeInterval(phase.end),
            round: phase.round,
            totalRounds: plan.totalRounds,
            isPaused: pausedElapsed != nil
        )
    }

    /// Instants at which the complication needs a fresh entry: every phase boundary still
    /// ahead of `date`, then the finish. A paused run has none — nothing is moving.
    func upcomingBoundaries(after date: Date, limit: Int = 40) -> [Date] {
        guard pausedElapsed == nil else { return [] }
        let plan = self.plan
        var dates = plan.phases
            .map { anchor.addingTimeInterval($0.start) }
            .filter { $0 > date }
        let finish = anchor.addingTimeInterval(plan.totalDuration)
        if finish > date { dates.append(finish) }
        return Array(dates.prefix(limit))
    }
}
