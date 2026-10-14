//
//  RunDependencies.swift
//  Intervally
//

import Foundation

/// The seams `RunCoordinator` is built against.
///
/// The coordinator decides which runtime tier to take and whether the notification backstop
/// is needed, and every regression this project has had has been in that logic. None of it
/// was testable while the coordinator constructed `HKWorkoutSession` and
/// `WKExtendedRuntimeSession` itself — neither of which can run in a test. These
/// protocols are the smallest change that makes the decisions assertable; the concrete
/// controllers already match them.
@MainActor
protocol WorkoutSessioning: AnyObject {
    /// An instance member rather than a static one, so a fake can report either answer.
    var isSupported: Bool { get }
    var isRunning: Bool { get }
    var heartRate: Double? { get }
    /// Active energy burned so far this session, in kilocalories; nil until Health has any.
    var activeEnergy: Double? { get }
    /// Invoked when the session ends for a reason the app did not ask for.
    var onUnexpectedEnd: (() -> Void)? { get set }

    @discardableResult func requestAuthorization() async -> Bool
    func adoptRecoveredSession() async -> Bool
    /// Adopts a recovered session that ran `workout`, the run's own, and tags it with that
    /// workout if its tag never landed: History finds a workout by its tag alone. A stand-in
    /// that doesn't care takes the default, a plain adopt.
    func adoptRecoveredSession(for workout: IntervalWorkout) async -> Bool
    func start(at date: Date) async -> Bool
    /// Starts a session for `workout`, so the saved Health workout carries the preset that
    /// ran (History on the iPhone reads it). A stand-in that doesn't care takes the default,
    /// a plain `start(at:)`.
    func start(at date: Date, for workout: IntervalWorkout) async -> Bool
    /// Segments the session so each interval becomes its own activity in Health.
    func beginActivity(for phase: IntervalPhase, at date: Date)
    /// Sends the run, as it now stands, to the iPhone that mirrors this session.
    func mirror(_ state: RunMirrorState)
    /// Commands from the iPhone mirroring this session.
    var onRemoteCommand: ((RunMirrorCommand) -> Void)? { get set }
    func pause()
    func resume()
    @discardableResult func end(at date: Date) async -> Bool
    func discard()
}

extension WorkoutSessioning {
    /// Sends the run to the iPhone's mirror (`RunMirrorState`). A stand-in sends nothing.
    func mirror(_ state: RunMirrorState) {}
    /// What the iPhone's buttons ask of the run. A stand-in never hears from one.
    var onRemoteCommand: ((RunMirrorCommand) -> Void)? {
        get { nil }
        set {}
    }
    func adoptRecoveredSession(for workout: IntervalWorkout) async -> Bool { await adoptRecoveredSession() }
    func beginActivity(for phase: IntervalPhase) { beginActivity(for: phase, at: Date()) }
    func start() async -> Bool { await start(at: Date()) }
    func start(at date: Date, for workout: IntervalWorkout) async -> Bool { await start(at: date) }
    func start(for workout: IntervalWorkout) async -> Bool { await start(at: Date(), for: workout) }
    @discardableResult func end() async -> Bool { await end(at: Date()) }
}

@MainActor
protocol RuntimeSessioning: AnyObject {
    /// Called when the system tears the session down.
    var onInvalidate: (() -> Void)? { get set }
    func start()
    func stop()
}

protocol BoundaryScheduling: Sendable {
    func requestAuthorization() async -> Bool
    func schedule(plan: IntervalPlan, anchor: Date) async
    func cancelAll() async
}

/// What marks each boundary: taps on the watch, sounds, a voice and taps on iPhone. A
/// stronger tap repeats after the call that starts it returns, so the coordinator must be
/// able to silence the rest when the run pauses, stops or starts over — and its tests need
/// to see what it asked for and how late.
@MainActor
protocol BoundaryHaptics: AnyObject {
    func play(_ event: TimerEvent, context: BoundaryContext)
    #if os(watchOS)
    /// Plays a work boundary at `strength`, whatever is saved: Settings' picker and the
    /// paywall's Feel Strongest. On the same player as the boundaries, so each replaces
    /// the other's repeats rather than cutting into them.
    func preview(_ strength: TapStrength)
    #endif
    /// Drops anything still waiting to play.
    func cancelPending()
}

/// Shows the run outside the app: the iPhone's Live Activity. The watch's complication reads
/// the run snapshot instead, so the watch takes the default, which shows nothing.
@MainActor
protocol RunPresenting: AnyObject {
    /// The run as it stands, or nil once it is over and gone.
    func present(_ run: RunPresentation?)
}

/// Shows nothing.
@MainActor
final class NoRunPresenter: RunPresenting {
    func present(_ run: RunPresentation?) {}
}

// MARK: - Conformances

extension WorkoutSessionController: WorkoutSessioning {
    var isSupported: Bool { Self.isSupported }
}

#if os(watchOS)
extension ExtendedRuntimeController: RuntimeSessioning {}
#endif

extension NotificationScheduler: BoundaryScheduling {
    func schedule(plan: IntervalPlan, anchor: Date) async {
        await schedule(plan: plan, anchor: anchor, now: Date())
    }
}

extension WorkoutSessioning {
    /// Stand-ins that don't track energy report none.
    var activeEnergy: Double? { nil }
}
