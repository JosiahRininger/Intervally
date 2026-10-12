//
//  RunActivityAttributes.swift
//  Intervally
//

import ActivityKit
import Foundation

/// The iPhone's run on the Lock Screen and in the Dynamic Island, and in the Smart Stack of
/// a paired Apple Watch. Compiled into the app, which starts and updates it, and into the
/// widget extension, which draws it.
struct RunActivityAttributes: ActivityAttributes {
    /// What changes during the run. Updated at each interval change, pause and resume: the
    /// system's timer text and progress bar count between updates on their own.
    struct ContentState: Codable, Hashable {
        enum Clock: Codable, Hashable {
            case running(phaseStart: Date, phaseEnd: Date, workoutEnd: Date)
            case paused(phaseLeft: TimeInterval, workoutLeft: TimeInterval)
            case finished
        }

        /// Nil once the run has finished.
        var phase: IntervalPhase.Kind?
        /// The whole phase, for a paused run's progress bar.
        var phaseDuration: TimeInterval
        var round: Int
        var next: IntervalPhase.Kind?
        var nextDuration: TimeInterval?
        /// What the preset calls the phase and the next; nil for their own names.
        var phaseName: String? = nil
        var nextName: String? = nil
        var clock: Clock
        /// The theme the app shows, so the activity matches it.
        var theme: AppTheme
    }

    var workoutName: String
    var totalRounds: Int
    var totalDuration: TimeInterval
}

extension RunActivityAttributes.ContentState {
    /// When the activity can no longer be trusted without an update: a moment after the
    /// phase it shows runs out. The app updates it before then whenever it is running; when
    /// it can't (no workout session, and the app asleep), the activity says how long the
    /// whole workout has left instead of a phase that is over.
    var staleDate: Date? {
        if case .running(_, let phaseEnd, _) = clock { return phaseEnd.addingTimeInterval(2) }
        return nil
    }
}
