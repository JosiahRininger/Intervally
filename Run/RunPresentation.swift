//
//  RunPresentation.swift
//  Intervally
//

import Foundation

/// The run as a surface outside the app shows it, worked out from the engine in one place so
/// the iPhone's Live Activity computes nothing itself.
///
/// A Live Activity redraws only when the app updates it, apart from the system's own timer
/// text. So a running run is described by dates, which keep counting with the app asleep,
/// and a paused one by what was left when it stopped.
struct RunPresentation: Equatable, Sendable {
    enum Clock: Equatable, Sendable {
        /// Counting down: the phase ends at `phaseEnd`, the whole workout at `workoutEnd`.
        case running(phaseStart: Date, phaseEnd: Date, workoutEnd: Date)
        /// Held, with what was left of each when it stopped.
        case paused(remainingInPhase: TimeInterval, remainingInWorkout: TimeInterval)
        /// Done: every phase ran out or was skipped.
        case finished
    }

    let workoutName: String
    /// The phase under way; nil once the run has finished.
    let phase: IntervalPhase?
    /// The phase after it, for "Next: Rest 0:15"; nil in the last phase.
    let next: IntervalPhase?
    let totalRounds: Int
    let totalDuration: TimeInterval
    let clock: Clock

    /// Nil while there is nothing to show: before the start, and after a stop.
    @MainActor
    init?(engine: TimerEngine) {
        self.init(
            plan: engine.plan,
            status: engine.status,
            anchor: engine.anchor,
            elapsed: engine.elapsed
        )
    }

    /// Pure, for the tests: what an engine in `status` would show.
    init?(plan: IntervalPlan, status: TimerEngine.Status, anchor: Date?, elapsed: TimeInterval) {
        workoutName = plan.workout.name
        totalRounds = plan.totalRounds
        totalDuration = plan.totalDuration
        switch status {
        case .idle:
            return nil
        case .finished:
            phase = nil
            next = nil
            clock = .finished
        case .running, .paused:
            let position = plan.position(atElapsed: elapsed)
            guard let index = position.phaseIndex, let current = position.phase else { return nil }
            phase = current
            next = plan.phases.indices.contains(index + 1) ? plan.phases[index + 1] : nil
            if status == .running, let anchor {
                clock = .running(
                    phaseStart: anchor.addingTimeInterval(current.start),
                    phaseEnd: anchor.addingTimeInterval(current.end),
                    workoutEnd: anchor.addingTimeInterval(plan.totalDuration)
                )
            } else {
                clock = .paused(
                    remainingInPhase: position.remainingInPhase,
                    remainingInWorkout: position.remainingTotal
                )
            }
        }
    }

    var isPaused: Bool {
        if case .paused = clock { return true }
        return false
    }
}
