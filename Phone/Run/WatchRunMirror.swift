//
//  WatchRunMirror.swift
//  IntervallyPhone
//

import Foundation
import HealthKit
import Observation
import os

/// A run on the watch, shown live on iPhone through HealthKit's workout mirroring.
///
/// The watch's workout session is mirrored here (`HKHealthStore.workoutSessionMirroringStartHandler`,
/// iOS 17); iOS launches the app in the background for it if need be. The watch sends its
/// run's state at each change of shape (`RunMirrorState`), and this rebuilds the same run in
/// a `TimerEngine` from the same anchor, so both count the same seconds. The run screen and
/// the Lock Screen show it; Pause, Skip and End go back to the watch, whose run is the one
/// that counts. Nothing is played here: the watch taps the wrist.
@MainActor
@Observable
final class WatchRunMirror {
    /// The watch's run, rebuilt here; nil when there is none to show.
    private(set) var engine: TimerEngine?
    private(set) var state: RunMirrorState?
    /// Whether the watch's session is still mirrored here.
    private(set) var isConnected = false

    /// A watch run arrived: the run screen should show it.
    @ObservationIgnored var onShow: (() -> Void)?
    /// The run as the Lock Screen should show it, or nil once it is gone.
    @ObservationIgnored var onPresentation: ((RunPresentation?) -> Void)?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var delegate: MirrorSessionDelegate?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.josiahrininger.intervally", category: "mirror")

    /// Listens for a mirrored session. Apple asks for this early in every launch, the
    /// background launch HealthKit makes for a mirror included.
    func start() {
        store.workoutSessionMirroringStartHandler = { [weak self] session in
            let handed = UncheckedSession(session: session)
            Task { @MainActor in self?.adopt(handed.session) }
        }
    }

    private func adopt(_ session: HKWorkoutSession) {
        log.info("mirroring a workout from the watch")
        let delegate = MirrorSessionDelegate(mirror: self)
        session.delegate = delegate
        self.session = session
        self.delegate = delegate
        isConnected = true
        // Whatever the watch sent before this delegate was set is gone: ask again.
        send(.refresh)
    }

    // MARK: - From the watch

    /// The watch's run as it now stands.
    func apply(_ state: RunMirrorState) {
        self.state = state
        guard state.status != .stopped else {
            log.info("the watch ended its run")
            clear()
            onPresentation?(nil)
            return
        }
        let isNew = engine == nil
        let engine = self.engine ?? TimerEngine(workout: state.workout)
        switch state.status {
        case .running:
            engine.restore(anchor: state.anchor ?? Date(), workout: state.workout, paused: nil)
        case .paused:
            engine.restore(anchor: Date(), workout: state.workout, paused: state.pausedElapsed ?? 0)
        case .finished:
            engine.restore(anchor: Date(), workout: state.workout, paused: nil)
            settleFinished(engine)
        case .stopped:
            return
        }
        self.engine = engine
        if engine.status == .running { startTicking() } else { stopTicking() }
        onPresentation?(RunPresentation(engine: engine))
        if isNew { onShow?() }
    }

    /// The session ended or lost the watch. A finished run stays on screen until Done; any
    /// other is over.
    func sessionEnded() {
        isConnected = false
        session = nil
        delegate = nil
        guard let engine else { return }
        // The watch ends its session the moment its run finishes, and that can land before
        // this side's own count, half a second apart, has reached the end.
        _ = engine.advance()
        if engine.status == .running, engine.plan.totalDuration - engine.elapsed < Self.finishTolerance {
            settleFinished(engine)
            onPresentation?(RunPresentation(engine: engine))
        }
        guard engine.status != .finished else { return }
        log.info("the watch's session ended")
        clear()
        onPresentation?(nil)
    }

    // MARK: - From the buttons here

    func send(_ command: RunMirrorCommand) {
        guard let session, let data = RunMirrorMessage.command(command).encoded() else { return }
        let handed = UncheckedSession(session: session)
        Task { @MainActor in
            do {
                try await handed.session.sendToRemoteWorkoutSession(data: data)
            } catch {
                self.log.error("command not sent to the watch: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Done on a finished watch run: the screen closes; the Lock Screen keeps its summary.
    func close() {
        clear()
    }

    /// The finished run's summary, as truthfully as the iPhone can know it: the watch saves
    /// to Health after its session ends, which ends the mirror too, so a save still under way
    /// when the mirror went is not claimed either way.
    var summary: RunCoordinator.Summary? {
        guard let engine, engine.status == .finished, let state else { return nil }
        let health: RunCoordinator.HealthSave = switch state.health {
        case .saved: .saved
        case .failed: .failed
        case .saving: isConnected ? .saving : .notRecorded
        case .notRecorded, nil: .notRecorded
        }
        return RunCoordinator.Summary(duration: engine.plan.totalDuration, rounds: engine.plan.totalRounds, health: health)
    }

    /// How close to its end a run whose session ended counts as finished.
    static let finishTolerance: TimeInterval = 2

    /// Anchored a whole workout back: the engine settles on finished.
    private func settleFinished(_ engine: TimerEngine) {
        engine.restore(
            anchor: Date().addingTimeInterval(-engine.plan.totalDuration - 1),
            workout: engine.plan.workout, paused: nil
        )
        stopTicking()
    }

    // MARK: - Counting

    /// Each interval change redraws the Lock Screen; the watch sends nothing for one.
    private func startTicking() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled, let engine = self.engine else { return }
                let events = engine.advance()
                if events.contains(where: { if case .countdown = $0 { false } else { true } }) {
                    self.onPresentation?(RunPresentation(engine: engine))
                }
                if engine.status != .running { self.stopTicking() }
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    private func clear() {
        stopTicking()
        engine = nil
        state = nil
    }
}

/// HealthKit hands the session over on a queue of its own; the session isn't Sendable, and
/// it is only touched again on the main actor.
private struct UncheckedSession: @unchecked Sendable {
    let session: HKWorkoutSession
}

/// The mirrored session's delegate, which HealthKit calls on a queue of its own: each call
/// turns what it was handed into Sendable values and hops to the main actor.
private final class MirrorSessionDelegate: NSObject, HKWorkoutSessionDelegate {
    private weak var mirror: WatchRunMirror?

    init(mirror: WatchRunMirror) {
        self.mirror = mirror
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState, date: Date
    ) {
        guard toState == .ended || toState == .stopped else { return }
        Task { @MainActor [weak mirror] in mirror?.sessionEnded() }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        Task { @MainActor [weak mirror] in mirror?.sessionEnded() }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let states = data.compactMap(RunMirrorMessage.decoded).compactMap { message -> RunMirrorState? in
            if case .state(let state) = message { return state }
            return nil
        }
        guard !states.isEmpty else { return }
        Task { @MainActor [weak mirror] in
            for state in states { mirror?.apply(state) }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: (any Error)?) {
        Task { @MainActor [weak mirror] in mirror?.sessionEnded() }
    }
}
