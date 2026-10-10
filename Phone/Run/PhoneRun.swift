//
//  PhoneRun.swift
//  IntervallyPhone
//

import Foundation
import Observation
import UIKit

/// Workouts on iPhone: the shared `RunCoordinator` with the iPhone's cues and Live Activity,
/// and whether the run screen is up.
///
/// The run screen covers the app from Start until the run is ended or finished and closed.
/// The run belongs to this, not to the screen, so it keeps going while the app is in the
/// background or the phone is locked.
@MainActor
@Observable
final class PhoneRun {
    let coordinator: RunCoordinator
    @ObservationIgnored let cues: PhoneCuePlayer
    @ObservationIgnored let activity: LiveActivityPresenter
    @ObservationIgnored private let presenter: any RunPresenting
    @ObservationIgnored private let store: WorkoutStore
    @ObservationIgnored private let defaults: UserDefaults

    /// Whether the run screen is showing.
    var isPresented = false

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
        let cues = PhoneCuePlayer(output: output ?? CueAudio(), pro: pro, defaults: defaults)
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
    }

    /// Runs finished on this iPhone.
    var finishedRuns: Int { defaults.integer(forKey: Key.finishedRuns) }

    /// Starts `workout`: it becomes the one up next, here and on the watch, and the run screen
    /// opens and starts it.
    func start(_ workout: IntervalWorkout) {
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
        isPresented = false
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

    /// Whether the screen should stay on: during a run on screen, unless turned off in
    /// Settings. Off again as soon as the run screen goes or the run stops counting.
    var keepsScreenAwake: Bool {
        isPresented && coordinator.engine.status == .running
            && (defaults.object(forKey: CueSettings.Key.keepAwake) as? Bool ?? true)
    }
}
