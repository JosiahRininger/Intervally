//
//  RunMirror.swift
//  Intervally
//

import Foundation

/// A run on the watch, as the iPhone mirrors it: what travels over the workout session's
/// own channel (`HKWorkoutSession` mirroring, watchOS 10 and iOS 17).
///
/// The watch's run is the one that counts. It sends its state at every change of shape, a
/// start, pause, resume, skip, finish or stop, and the iPhone rebuilds the same run from it:
/// the same workout and the same anchor date, so both count the same seconds without a
/// message at every interval change. The iPhone sends back only what its buttons ask for.
enum RunMirrorMessage: Codable, Equatable, Sendable {
    /// Watch to iPhone: the run as it now stands.
    case state(RunMirrorState)
    /// iPhone to watch.
    case command(RunMirrorCommand)

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decoded(_ data: Data) -> RunMirrorMessage? {
        try? JSONDecoder().decode(RunMirrorMessage.self, from: data)
    }
}

/// What the iPhone asks of a run on the watch: its buttons, and on connecting, the run as it
/// stands, as whatever was sent before the iPhone was listening is gone.
enum RunMirrorCommand: String, Codable, Equatable, Sendable {
    case togglePause, skip, end, refresh
}

/// The watch's run, in enough detail to rebuild it exactly.
struct RunMirrorState: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case running, paused, finished
        /// Ended before the last interval: there is nothing more to show.
        case stopped
    }

    /// What became of the finished run's Health workout, by `RunCoordinator.HealthSave`'s name.
    enum Health: String, Codable, Sendable {
        case notRecorded, saving, saved, failed
    }

    /// The workout as it runs, warmup and cooldown already decided by Pro on the watch.
    var workout: IntervalWorkout
    var status: Status
    /// While running: the instant the run would have started had it never paused.
    var anchor: Date?
    /// While paused: how far in it was.
    var pausedElapsed: TimeInterval?
    var health: Health?
}

/// One more thing a workout session can do: carry the run between the devices.
extension RunMirrorState {
    @MainActor
    init(engine: TimerEngine, health: Health?) {
        let status: Status = switch engine.status {
        case .running: .running
        case .paused: .paused
        case .finished: .finished
        case .idle: .stopped
        }
        self.init(
            workout: engine.plan.workout,
            status: status,
            anchor: engine.status == .running ? engine.anchor : nil,
            pausedElapsed: engine.status == .paused ? engine.elapsed : nil,
            health: health
        )
    }
}
