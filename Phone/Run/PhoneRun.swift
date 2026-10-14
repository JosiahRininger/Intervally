//
//  PhoneRun.swift
//  IntervallyPhone
//

import Foundation
import HealthKit
import Observation
import UIKit

/// Workouts on iPhone: the shared `RunCoordinator` with the iPhone's cues and Live Activity,
/// a run on the watch mirrored here (`WatchRunMirror`), and whether the run screen is up.
///
/// The run screen covers the app from Start until the run is ended or finished and closed.
/// The run belongs to this, not to the screen, so it keeps going while the app is in the
/// background or the phone is locked. With no run of its own, the screen shows the watch's,
/// and its buttons go to the watch.
@MainActor
@Observable
final class PhoneRun {
    let coordinator: RunCoordinator
    /// The watch's run, live, when its workout session is mirrored here.
    let mirror = WatchRunMirror()
    @ObservationIgnored let cues: PhoneCuePlayer
    @ObservationIgnored let activity: LiveActivityPresenter
    @ObservationIgnored private let presenter: any RunPresenting
    @ObservationIgnored private let store: WorkoutStore
    @ObservationIgnored private let defaults: UserDefaults

    /// Whether the run screen is showing.
    var isPresented = false
    /// Whether it shows the watch's run rather than this iPhone's. Said outright, not worked
    /// out from which engine is active: a finished run here still owns its summary, and Start
    /// here must start a run here even while the watch runs one.
    private(set) var showsWatchRun = false

    /// Start on Watch, from tap to the watch's run showing here.
    enum WatchStart: Equatable {
        case idle
        /// The watch is being woken; its run shows here once it starts.
        case starting
        /// The watch couldn't be reached.
        case failed
    }

    private(set) var watchStart = WatchStart.idle
    /// Sends the start request over sync, beside the presets (`WatchSync.requestStart`).
    @ObservationIgnored var requestWatchStart: (UUID) -> Bool = { _ in false }
    /// Takes back a start request the watch hasn't acted on: the presets sent again without
    /// it replace it in WatchConnectivity. Otherwise a watch reached within its minute would
    /// still start the workout, perhaps beside the same one started here instead.
    @ObservationIgnored var withdrawWatchStart: () -> Void = {}
    @ObservationIgnored private var watchStartTimeout: Task<Void, Never>?
    /// Wakes the watch app to run a workout (`HKHealthStore.startWatchApp`), with its own
    /// activity; throws when the watch can't be reached. A test's stand-in decides.
    @ObservationIgnored var wakeWatch: @MainActor (IntervalWorkout) async throws -> Void = { workout in
        try await HKHealthStore().startWatchApp(toHandle: workout.activityKind.configuration)
    }
    /// The media volume the cues play at, as last reported while the run held the audio.
    private(set) var mediaVolume: Float = 1

    enum Key {
        /// Runs finished on this iPhone, for the review prompt's "after real use".
        static let finishedRuns = "phone.run.finishedCount"
    }

    init(
        store: WorkoutStore,
        pro: any ProGating,
        theme: ThemeStore,
        output: (any CueOutput)? = nil,
        workout: (any WorkoutSessioning)? = nil,
        notifications: (any BoundaryScheduling)? = nil,
        presenter: (any RunPresenting)? = nil,
        defaults: UserDefaults = SharedDefaults.suite
    ) {
        self.store = store
        self.defaults = defaults
        let resolvedOutput = output ?? CueAudio()
        let cues = PhoneCuePlayer(output: resolvedOutput, pro: pro, defaults: defaults)
        let activity = LiveActivityPresenter { theme.effective(isPro: pro.isPro) }
        self.cues = cues
        self.activity = activity
        // A test's stand-in sees what the Live Activity would have been shown.
        self.presenter = presenter ?? activity
        self.coordinator = RunCoordinator(
            store: store,
            pro: pro,
            haptics: cues,
            workout: workout ?? WorkoutSessionController(),
            notifications: notifications ?? NotificationScheduler(),
            playCue: { cues.transport($0) },
            reloadWidgets: {},
            presenter: self.presenter
        )
        cues.roundsInRun = { [weak coordinator] in coordinator?.engine.plan.totalRounds ?? 1 }
        resolvedOutput.onVolumeChange = { [weak self] volume in self?.mediaVolume = volume }
        // The iPhone's own run comes first: a watch run takes the screen only from no run
        // here at all, and the Lock Screen only while nothing here is showing.
        mirror.onShow = { [weak self] in
            guard let self, !self.ownRunOnScreen, !self.coordinator.engine.isActive else { return }
            self.watchStartTimeout?.cancel()
            self.watchStart = .idle
            self.showsWatchRun = true
            self.isPresented = true
        }
        mirror.onPresentation = { [weak self] run in
            guard let self, self.showsWatchRun || (!self.isPresented && !self.coordinator.engine.isActive) else { return }
            self.presenter.present(run)
        }
        mirror.onEnded = { [weak self] in
            guard let self, self.showsWatchRun else { return }
            self.showsWatchRun = false
            self.isPresented = false
        }
    }

    // MARK: - What the run screen shows

    /// The screen shows the watch's run.
    var isMirroring: Bool {
        showsWatchRun && mirror.engine != nil
    }

    /// This iPhone's run has no workout session, so its sounds stop the moment the user
    /// leaves the app: iOS suspends it, and only the notification backstop marks the changes,
    /// which the Ring/Silent switch mutes. The run screen says so, and how to fix it.
    var soundsStopOutsideApp: Bool {
        Self.soundsStopOutsideApp(
            isMirroring: isMirroring,
            isRunning: coordinator.engine.status == .running,
            tier: coordinator.tier,
            isAcquiring: coordinator.isAcquiringTier,
            sessionsSupported: coordinator.workout.isSupported
        )
    }

    /// Not while the session is still being asked for: a run that is about to get one would
    /// flash the warning on every Start. Nor while paused, when nothing is playing: a run
    /// restored paused takes its session only once resumed.
    nonisolated static func soundsStopOutsideApp(
        isMirroring: Bool, isRunning: Bool, tier: RunCoordinator.RuntimeTier, isAcquiring: Bool, sessionsSupported: Bool
    ) -> Bool {
        !isMirroring && isRunning && sessionsSupported && !isAcquiring && tier != .workout
    }

    /// The screen is up for a run of this iPhone's: starting, running or finished.
    private var ownRunOnScreen: Bool { isPresented && !showsWatchRun }

    /// The run on screen: this iPhone's, or the watch's.
    var engine: TimerEngine {
        if isMirroring, let mirrored = mirror.engine { return mirrored }
        return coordinator.engine
    }

    var summary: RunCoordinator.Summary? {
        isMirroring ? mirror.summary : coordinator.summary
    }

    /// To the watch as what the button showed, so a tap that crosses a change on the watch
    /// in flight can't do the opposite.
    func togglePause() {
        guard isMirroring else { return coordinator.togglePause() }
        mirror.send(engine.status == .running ? .pause : .resume)
    }

    /// To the watch with the interval it skips, so a tap at the end of one can't skip the next.
    func skip() {
        guard isMirroring else { return coordinator.skip() }
        guard let phase = engine.position.phaseIndex else { return }
        mirror.send(.skip(phase: phase))
    }

    /// End, confirmed. A watch run is ended on the watch, and its screen here closes at once,
    /// as for a run here: a watch out of reach must not leave it stuck open. If the watch
    /// carries on, its next change brings it back.
    func end() {
        if isMirroring {
            mirror.send(.end)
            mirror.close()
            presenter.present(nil)
            showsWatchRun = false
            isPresented = false
        } else {
            close()
        }
    }

    /// Done on a finished run.
    func done() {
        if isMirroring {
            mirror.close()
            showsWatchRun = false
            isPresented = false
        } else {
            close()
        }
    }

    // MARK: - Start on Watch

    /// Wakes the watch to run `workout`: it becomes the one up next, the watch is asked to
    /// start it, and its run shows here once the mirror connects.
    func startOnWatch(_ workout: IntervalWorkout) {
        // This iPhone's own run comes first, as with Start.
        guard !coordinator.engine.isActive else {
            showsWatchRun = false
            isPresented = true
            return
        }
        store.selectedID = workout.id
        watchStartWorkout = workout
        _ = requestWatchStart(workout.id)
        watchStart = .starting
        let wake = wakeWatch
        Task { [weak self] in
            do {
                try await wake(workout)
            } catch {
                // Unless the watch's run already showed up regardless.
                guard let self, self.watchStart == .starting else { return }
                self.watchStartTimeout?.cancel()
                self.withdrawWatchStart()
                self.watchStart = .failed
                return
            }
            guard let self else { return }
            // The run normally shows here within a few seconds. If the mirror never comes (an
            // older watch, or the iPhone out of the watch's reach), stop saying "starting".
            self.watchStartTimeout?.cancel()
            self.watchStartTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard let self, !Task.isCancelled, self.watchStart == .starting else { return }
                self.withdrawWatchStart()
                self.watchStart = .idle
            }
        }
    }

    func dismissWatchStartFailure() {
        watchStart = .idle
    }

    /// The watch couldn't be reached: the same workout on this iPhone instead.
    func startHereInstead() {
        watchStart = .idle
        guard let watchStartWorkout else { return }
        start(store.workouts.first { $0.id == watchStartWorkout.id } ?? watchStartWorkout)
    }

    @ObservationIgnored private var watchStartWorkout: IntervalWorkout?

    /// Settings' Play a Sample. With no run to hold the audio, it is handed back once the
    /// sample has played, so the volume buttons go back to the ringer.
    func playSample() {
        cues.preview()
        guard !coordinator.engine.isActive else { return }
        sampleRelease?.cancel()
        sampleRelease = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled, !self.coordinator.engine.isActive else { return }
            self.cues.release()
        }
    }

    @ObservationIgnored private var sampleRelease: Task<Void, Never>?

    /// The run screen's hint to turn the volume up: the cues are on, and too quiet to hear.
    var isVolumeLow: Bool {
        coordinator.engine.isActive && cues.isQuiet(atVolume: mediaVolume)
    }

    /// Runs finished on this iPhone.
    var finishedRuns: Int { defaults.integer(forKey: Key.finishedRuns) }

    /// Starts `workout`: it becomes the one up next, here and on the watch, and the run screen
    /// opens and starts it.
    func start(_ workout: IntervalWorkout) {
        showsWatchRun = false
        guard !coordinator.engine.isActive else {
            isPresented = true
            return
        }
        store.selectedID = workout.id
        isPresented = true
    }

    /// The run screen is closing, after a finish or an End.
    func close() {
        coordinator.stopAndExit()
        cues.release()
        // A run still going on the watch takes the screen back, as it would have had there
        // been none here.
        if let watchRun = mirror.engine, watchRun.isActive {
            showsWatchRun = true
            presenter.present(RunPresentation(engine: watchRun))
        } else {
            isPresented = false
        }
    }

    /// Counted when the summary is first shown.
    func recordFinish() {
        defaults.set(finishedRuns + 1, forKey: Key.finishedRuns)
    }

    // MARK: - Launch

    /// A run that was under way when the app was last terminated comes back, on screen.
    ///
    /// The Live Activity is settled first, so the restored run's first update lands on the
    /// activity it keeps: settled after, the restore's own request was the one ended, and the
    /// Lock Screen kept the dead process's activity, stuck at 0:00.
    func restoreAtLaunch() {
        activity.reconcile(hasRun: store.loadActiveRun() != nil)
        let restored = coordinator.restoreIfNeeded()
        if restored {
            isPresented = true
        } else {
            // A snapshot that turned out to be finished: nothing to show.
            activity.present(nil)
        }
    }

    /// iOS relaunched the app to hand back a workout session that outlived it.
    func recoverWorkoutSession() {
        coordinator.recoverWorkoutSession()
        if coordinator.engine.isActive { isPresented = true }
    }

    func handleForeground() {
        guard coordinator.engine.isActive else { return }
        coordinator.handleForeground()
    }

    // MARK: - Screen

    /// Whether the screen should stay on: during a run on screen, this iPhone's or the
    /// watch's, unless turned off in Settings. Off again as soon as the run screen goes or the
    /// run stops counting.
    var keepsScreenAwake: Bool {
        isPresented && engine.status == .running
            && (defaults.object(forKey: CueSettings.Key.keepAwake) as? Bool ?? true)
    }
}
