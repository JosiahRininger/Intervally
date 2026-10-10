//
//  SampleHistory.swift
//  IntervallyPhone
//

#if DEBUG
import Foundation

/// `-qaHistory`: History from a fixture instead of Health, for screenshots and for seeing each
/// state by hand. Nothing is read from or written to HealthKit (Guideline 5.1.3(ii)), and
/// Release builds don't have it.
actor SampleHistory: HistorySource {
    nonisolated let mode: QAHistory
    /// `connect` starts unasked; Connect "allows" the sample.
    private var connected: Bool

    /// What HealthKit says when the iPhone is locked.
    struct ReadFailed: LocalizedError {
        var errorDescription: String? { "Protected health data is inaccessible" }
    }

    init(mode: QAHistory) {
        self.mode = mode
        connected = mode != .connect
    }

    nonisolated var isAvailable: Bool { mode != .unavailable }

    func access() -> HistoryAccess {
        connected ? .requested : .shouldRequest
    }

    func requestAccess() {
        connected = true
    }

    func workouts() throws -> [RawWorkout] {
        switch mode {
        case .failed: throw ReadFailed()
        case .empty, .unavailable: []
        case .sample, .connect: Self.sessions(now: Date())
        }
    }

    // MARK: - Fixture

    /// One made-up session: which preset, when, how far it got, and whether Health had heart
    /// rate for it.
    private struct Spec {
        let workout: IntervalWorkout
        let daysAgo: Int
        let hour: Int
        var endedAtRound: Int?
        var heartRate = true
    }

    private static let hillRepeats = IntervalWorkout(
        name: "Hill Repeats", prepareSeconds: 10, warmupSeconds: 300, workSeconds: 60,
        restSeconds: 90, rounds: 6, cooldownSeconds: 180, activity: .outdoorRun
    )

    private static let specs: [Spec] = {
        let starters = WorkoutStore.starterWorkouts
        return [
            Spec(workout: starters[0], daysAgo: 0, hour: 7),
            Spec(workout: starters[1], daysAgo: 2, hour: 18),
            Spec(workout: hillRepeats, daysAgo: 4, hour: 6, endedAtRound: 4),
            Spec(workout: starters[2], daysAgo: 8, hour: 12),
            Spec(workout: starters[0], daysAgo: 10, hour: 7),
            Spec(workout: starters[1], daysAgo: 16, hour: 19, heartRate: false),
            Spec(workout: hillRepeats, daysAgo: 23, hour: 6),
        ]
    }()

    /// Three weeks of sessions up to `now`, newest first. The same IDs every time, so a
    /// refresh doesn't replace the session on screen with a copy.
    static func sessions(now: Date, calendar: Calendar = .current) -> [RawWorkout] {
        specs.enumerated().compactMap { index, spec in
            guard let day = calendar.date(byAdding: .day, value: -spec.daysAgo, to: now),
                  var start = calendar.date(bySettingHour: spec.hour, minute: 10, second: 0, of: day)
            else { return nil }
            // Today's session is always over by now, whatever time "now" is.
            if start > now { start = now.addingTimeInterval(-TimeInterval(spec.workout.totalSeconds) - 3600) }
            return session(spec, index: index, start: start)
        }
    }

    private static func session(_ spec: Spec, index: Int, start: Date) -> RawWorkout {
        let phases = IntervalPlan(workout: spec.workout).phases.filter { phase in
            guard let last = spec.endedAtRound else { return true }
            // Stopped in the rest after its last work interval: no cooldown either.
            return phase.kind != .cooldown && phase.round <= last && !(phase.kind == .rest && phase.round == last)
        }
        let activities = phases.map { phase in
            RawWorkout.Activity(
                phase: phase.kind.rawValue,
                round: phase.kind.isBookend ? nil : phase.round,
                start: start.addingTimeInterval(phase.start),
                duration: phase.duration,
                averageHeartRate: spec.heartRate ? heartRate(for: phase, session: index) : nil,
                activeEnergy: calories(for: phase)
            )
        }
        let duration = phases.reduce(0) { $0 + $1.duration }
        let rates = activities.compactMap { activity in activity.averageHeartRate.map { ($0, activity.duration) } }
        let weighted = rates.reduce(0) { $0 + $1.0 * $1.1 } / max(1, rates.reduce(0) { $0 + $1.1 })
        return RawWorkout(
            id: UUID(uuidString: String(format: "5A3B1E00-0000-4000-8000-%012d", index)) ?? UUID(),
            start: start,
            duration: duration,
            presetName: spec.workout.name,
            plannedRounds: spec.workout.rounds,
            averageHeartRate: rates.isEmpty ? nil : weighted,
            maximumHeartRate: rates.map(\.0).max().map { $0 + 6 },
            activeEnergy: activities.compactMap(\.activeEnergy).reduce(0, +),
            activities: activities,
            activity: spec.workout.activityKind
        )
    }

    /// Kilocalories an interval burns: about 14 a minute working, 6 resting, as a HIIT session
    /// on a watch records.
    private static func calories(for phase: IntervalPhase) -> Double {
        let perMinute: Double = switch phase.kind {
        case .work: 14
        case .warmup: 9
        case .rest, .cooldown: 6
        case .prepare: 3
        }
        return phase.duration / 60 * perMinute
    }

    /// Rises through the rounds and drops in each rest, as a real session does.
    private static func heartRate(for phase: IntervalPhase, session: Int) -> Double {
        let lift = Double(session % 3) * 2
        return switch phase.kind {
        case .prepare: 92 + lift
        case .warmup: 114 + lift
        case .work: min(174, 138 + Double(phase.round) * 4 + lift)
        case .rest: min(150, 118 + Double(phase.round) * 3 + lift)
        case .cooldown: 106 + lift
        }
    }
}
#endif
