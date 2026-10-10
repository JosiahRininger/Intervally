//
//  RunCoordinator.swift
//  Intervally
//

import Foundation
import Observation
import SwiftUI
import WidgetKit
import os

extension RunMirrorState.Health {
    init(_ health: RunCoordinator.HealthSave) {
        self = switch health {
        case .notRecorded: .notRecorded
        case .saving: .saving
        case .saved: .saved
        case .failed: .failed
        }
    }
}

/// Owns a workout run and everything that has to happen around it.
///
/// The layering is deliberate, because no single watchOS mechanism covers every case:
///
/// | layer | covers |
/// |---|---|
/// | deadline-based `TimerEngine` | time is always correct, however long the app was away |
/// | `HKWorkoutSession` | app keeps executing indefinitely, even if the user leaves it |
/// | `WKExtendedRuntimeSession` | fallback when Health is unavailable: screen-off, wrist-down |
/// | local notifications | boundaries still alert if the app is suspended or terminated |
/// | `RunSnapshot` persistence | a relaunch resumes exactly where the run had got to |
///
/// The original app had only a `Timer.publish` counter and a single reused runtime session,
/// so it lost a second of workout for every tick the system withheld and had no background
/// time at all after the first run.
@MainActor
@Observable
final class RunCoordinator {

    let engine: TimerEngine
    @ObservationIgnored let runtime: any RuntimeSessioning
    @ObservationIgnored let workout: any WorkoutSessioning
    @ObservationIgnored private let notifications: any BoundaryScheduling
    @ObservationIgnored private let store: WorkoutStore
    @ObservationIgnored private let pro: any ProGating
    @ObservationIgnored private let haptics: any BoundaryHaptics
    @ObservationIgnored private let playCue: @MainActor (TransportCue) -> Void
    @ObservationIgnored private let reloadWidgets: () -> Void
    @ObservationIgnored private let presenter: any RunPresenting
    @ObservationIgnored private let log = Logger(subsystem: "com.josiahrininger.intervally", category: "run")

    /// Which mechanism is keeping the run alive. This is not cosmetic: it decides whether
    /// boundary haptics can fire from the app at all, and therefore whether the
    /// notification backstop is needed.
    enum RuntimeTier: String {
        /// A live `HKWorkoutSession`. The app keeps executing indefinitely, survives the
        /// user leaving it, and — uniquely — is allowed to play haptics from the
        /// background. `WKInterfaceDevice.play(_:)` is documented as a no-op when the app
        /// is not active, with an active workout session as the sole exception.
        case workout
        /// A `WKExtendedRuntimeSession`. Keeps executing with the screen off, but ends when
        /// the user leaves the app, and background haptics are not guaranteed.
        case extendedRuntime
        /// Nothing is holding the app open.
        case none

        /// Whether the app can rely on playing its own haptics at interval boundaries.
        var deliversHaptics: Bool { self == .workout }
    }

    private(set) var tier: RuntimeTier = .none

    /// What the finished run amounted to, for the summary screen.
    struct Summary: Equatable, Sendable {
        let duration: TimeInterval
        let rounds: Int
        var health: HealthSave
    }

    /// What became of the run's Health workout, for the summary screen.
    enum HealthSave: Equatable, Sendable {
        /// The run never had a workout session — Health was declined or unavailable — so
        /// there was nothing to save, and nothing worth saying about it.
        case notRecorded
        case saving
        case saved
        case failed
    }

    private(set) var summary: Summary?

    /// Counts runs the iPhone ended, so the watch's screen can close itself. A run ended here
    /// closes its own screen; one ended from the iPhone's mirror has nobody on the watch to.
    private(set) var endedRemotely = 0

    @ObservationIgnored private var hasRequestedPermissions = false

    /// Whether notifications may actually be delivered. When this is false and no workout
    /// session is running, nothing will alert the user at a boundary unless they are looking
    /// at the screen — the run view says so rather than implying alerts are on.
    private(set) var canNotify = true
    /// Serialises notification-schedule updates so they apply in the order requested.
    @ObservationIgnored private var backstopTask: Task<Void, Never>?

    /// The start sequence in flight, if any. Held so a second `begin()` cannot start the
    /// clock early (before the permission prompts resolve), and so leaving the screen can
    /// cancel a start that has not happened yet.
    @ObservationIgnored private var beginTask: Task<Void, Never>?

    /// The runtime-tier acquisition in flight, if any. `tier` is only set once a session
    /// has actually started, so without this every caller arriving in the meantime — a
    /// restore and the foreground transition land together on every launch — would start
    /// its own session, and they would compete.
    @ObservationIgnored private var supportTask: Task<Void, Never>?

    /// A pending retry of the workout session after a fallback. See `scheduleWorkoutUpgrade`.
    @ObservationIgnored private var upgradeTask: Task<Void, Never>?

    /// How long to wait before each retry. Injectable so tests need not sleep for real.
    @ObservationIgnored var upgradeRetryDelays: [TimeInterval] = [1.0, 3.0]

    /// Drives event dispatch. Owned by the coordinator, not the view: an `autoconnect()`
    /// publisher tears its timer down when the last subscriber disappears, so tying it to
    /// the run screen meant walking away from that screen stopped the workout advancing —
    /// no boundary haptics, and no `finish()`. Display smoothness is handled separately by
    /// `TimelineView`, so this only has to be frequent enough to catch a boundary promptly.
    @ObservationIgnored private var ticker: Task<Void, Never>?

    private func startTicking() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                self.advance()
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    /// - Parameters:
    ///   - pro: No default, so no test can run against the real store by accident.
    ///   - haptics: No default either: the app's player reads the tap strength and the
    ///     entitlement, and a test needs to see what was asked of it.
    init(
        store: WorkoutStore,
        pro: any ProGating,
        haptics: any BoundaryHaptics,
        workout: any WorkoutSessioning = WorkoutSessionController(),
        runtime: any RuntimeSessioning = RunPlatform.makeRuntime(),
        notifications: any BoundaryScheduling = NotificationScheduler(),
        playCue: @escaping @MainActor (TransportCue) -> Void = RunPlatform.play(cue:),
        reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() },
        presenter: any RunPresenting = NoRunPresenter()
    ) {
        self.store = store
        self.pro = pro
        self.haptics = haptics
        self.workout = workout
        self.runtime = runtime
        self.notifications = notifications
        self.playCue = playCue
        self.reloadWidgets = reloadWidgets
        self.presenter = presenter
        self.engine = TimerEngine(workout: store.selected.effective(isPro: pro.isPro))
        self.workout.onRemoteCommand = { [weak self] command in self?.handleRemote(command) }
    }

    // MARK: - Test seams

    /// Whether the advance loop is live. Its lifetime has been a repeated source of bugs.
    var isTicking: Bool { ticker != nil }

    /// Awaits the chained notification update, so tests can assert on a settled schedule.
    func backstopSettled() async {
        await backstopTask?.value
    }

    // MARK: - Lifecycle

    /// Called when the run screen appears.
    func begin() {
        // #13: a run left on the completion screen used to wedge the guard below, so Start
        // silently re-presented the finished screen instead of starting anything.
        if engine.status == .finished {
            engine.stop()
            summary = nil
        }
        guard engine.status == .idle, beginTask == nil else { return }
        // The one place Pro gates the warmup and cooldown. The snapshot, the widget, the
        // notifications and a later restore all inherit the plan built here, and Siri,
        // Shortcuts, Control Center and the complication all start through this method.
        // Nothing rebuilds the plan mid-run, so a refund never reshapes a workout under way.
        engine.configure(with: store.selected.effective(isPro: pro.isPro))

        beginTask = Task {
            defer { beginTask = nil }
            // Ask BEFORE the clock starts. These prompts are a notification alert followed
            // by HealthKit's multi-screen sheet; starting the engine first meant a first-run
            // workout counted down behind them and landed on screen several rounds in.
            // After the first run this returns without prompting, so it costs nothing.
            await requestPermissionsIfNeeded()
            // The user may have left while the prompts were up.
            guard !Task.isCancelled, engine.status == .idle else { return }

            engine.start().forEach { announce($0) }
            persistSnapshot()
            startTicking()
            // A brand-new run must not inherit a session left over from an earlier one.
            attachBackgroundSupport(recovering: false)
        }
    }

    /// Takes a runtime tier for the current run. The single entry point for every path that
    /// needs one — a new run, a restore, a resume, a foreground retry, a session that died —
    /// and idempotent while an acquisition is already under way.
    ///
    /// - Parameter recovering: Whether a session the system kept alive across a termination
    ///   belongs to this run and should be adopted. Only a brand-new run says no.
    private func attachBackgroundSupport(recovering: Bool = true) {
        guard engine.status == .running, tier == .none, supportTask == nil else { return }
        supportTask = Task {
            // Asked here rather than at launch: the permission only means something once
            // the user has actually started a workout, and a prompt on the very first
            // frame of a cold launch is both jarring and easy to decline out of hand.
            await requestPermissionsIfNeeded()
            await startBackgroundSupport(recovering: recovering)
            // Clear BEFORE the deciding refresh: refreshBackstop defers while an acquisition
            // is in flight, and this is the one call that must not be deferred.
            supportTask = nil
            refreshBackstop()
        }
    }

    private func startBackgroundSupport(recovering: Bool) async {
        // Prefer a real workout session. It is the only tier that both keeps running when
        // the user navigates away and is permitted to play haptics from the background.
        //
        // Attempt it rather than pre-checking `authorizationStatus`: that query reports
        // `.notDetermined` in situations where a session would in fact start (it is
        // unreliable in the simulator, and HealthKit is deliberately cagey about what it
        // discloses). Starting and catching the failure is both simpler and more accurate,
        // and costs nothing when it is genuinely unavailable — HealthKit prompts at most
        // once, so a denied user is never re-asked.
        guard engine.isActive else { return }
        workout.onUnexpectedEnd = { [weak self] in
            // No status guard. The session is gone whatever the engine is doing; leaving
            // `tier` at .workout while paused made it terminal, because nothing re-takes a
            // tier unless it is .none — and .workout also suppresses the backstop.
            guard let self else { return }
            self.log.notice("workout session ended unexpectedly; falling back")
            self.tier = .none
            // Re-take a tier if one is available (attach only acts while running), and in
            // any case restore the notification backstop that .workout was suppressing.
            self.attachBackgroundSupport()
            self.refreshBackstop()
        }
        // Reclaim a session the system held across a termination before starting a new one:
        // creating a second one orphans the first, so everything recorded before the
        // termination never reaches Health.
        var tookSession = false
        if recovering {
            // The run's own workout, from its snapshot: the session ran it, so a tag that never
            // landed before the termination can still be written.
            tookSession = await workout.adoptRecoveredSession(for: engine.plan.workout)
        } else if await workout.adoptRecoveredSession() {
            // A session the system is still holding from a run that is no longer resumable.
            // Save what it recorded and start clean, rather than appending this run to it.
            log.info("closing out a leftover workout session before a new run")
            await workout.end()
        }
        // Tagged with the run's own workout, which a restore takes from its snapshot.
        if !tookSession { tookSession = await workout.start(for: engine.plan.workout) }

        // The run may have been stopped while the session was starting. Taking a tier now
        // would leave a live workout session — holding the app open and showing the workout
        // indicator — attached to a run that no longer exists.
        guard engine.isActive else {
            if tookSession { workout.discard() }
            return
        }

        if workout.isSupported, tookSession {
            tier = .workout
            // The phase already under way was announced by `engine.start()` (or by a
            // restore), before there was a session to segment — so open its activity here
            // rather than waiting for the next boundary.
            if let phase = engine.position.phase { workout.beginActivity(for: phase) }
            // The user may have paused while the session was still being created, in which
            // case that pause never reached the session.
            if engine.status == .paused { workout.pause() }
        } else {
            runtime.onInvalidate = { [weak self] in
                // No status guard: the session is gone whatever the engine is doing, and
                // claiming a tier that no longer exists is terminal — attachBackgroundSupport
                // only re-takes one when the tier is .none.
                guard let self else { return }
                self.log.notice("runtime session ended; falling back to notifications")
                self.tier = .none
                self.refreshBackstop()
            }
            runtime.start()
            tier = .extendedRuntime
            if workout.isSupported { scheduleWorkoutUpgrade() }
        }
    }

    /// Retries the workout session shortly after falling back, and upgrades the run if it
    /// takes.
    ///
    /// Health access granted moments ago is not always in effect yet: a session started
    /// straight after the permission sheet fails as "not authorized", then succeeds a second
    /// later. Without this, the very first workout — the one where the user just said yes to
    /// Health — runs without a workout session, gets no background haptics, and never
    /// reaches Health. Declined access fails every retry and the run stays as it was.
    private func scheduleWorkoutUpgrade() {
        upgradeTask?.cancel()
        upgradeTask = Task { [weak self] in
            guard let delays = self?.upgradeRetryDelays else { return }
            for delay in delays {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled, self.engine.isActive,
                      self.tier == .extendedRuntime else { return }
                guard await self.workout.start(for: self.engine.plan.workout) else { continue }

                // The run may have ended while the session was starting.
                guard self.engine.isActive, !Task.isCancelled else {
                    self.workout.discard()
                    return
                }
                self.log.info("upgraded the run to a workout session")
                // stop() detaches before invalidating, so this does not report back as a
                // lost session and knock the tier down again.
                self.runtime.stop()
                self.tier = .workout
                if let phase = self.engine.position.phase { self.workout.beginActivity(for: phase) }
                if self.engine.status == .paused { self.workout.pause() }
                // The app now plays its own haptics, so the notification backstop goes.
                self.refreshBackstop()
                return
            }
        }
    }

    /// Keeps the notification backstop in sync with the current tier.
    ///
    /// Under a workout session the app is executing and plays its own haptics, so
    /// scheduling notifications as well would double-alert at every boundary and burn the
    /// pending-request budget for nothing.
    private func refreshBackstop() {
        // While a tier is still being acquired the right answer is unknown: scheduling now
        // (as the foreground transition did when the permission sheet dismissed) burns a
        // batch of notifications that the acquisition's own refresh then has to cancel, and
        // opens a double-alert window if a boundary lands in between. The acquisition ends
        // with its own refreshBackstop(), and it is bounded, so deferring is safe.
        guard supportTask == nil else { return }
        let wanted: (plan: IntervalPlan, anchor: Date)?
        if engine.status == .running, !tier.deliversHaptics, let anchor = engine.anchor {
            wanted = (engine.plan, anchor)
        } else {
            wanted = nil
        }

        // Chain onto the previous update rather than firing an independent task. Two
        // unstructured tasks can enter the scheduler in either order, so a quick
        // pause-then-resume could otherwise apply the cancel *after* the reschedule and
        // leave a running workout with no backstop at all.
        let previous = backstopTask
        backstopTask = Task { [notifications] in
            await previous?.value
            if let wanted {
                await notifications.schedule(plan: wanted.plan, anchor: wanted.anchor)
            } else {
                await notifications.cancelAll()
            }
        }
    }

    /// Called when the run screen goes away.
    func end() {
        // Walking away from a finished run ends it, rather than leaving `.finished` behind
        // to block the next Start.
        if engine.status == .finished {
            stopAndExit()
            return
        }
        guard engine.status != .idle else { return }
        // Leaving the screen while still running keeps the run alive so it can be resumed;
        // an explicit stop goes through `stopAndExit`.
        persistSnapshot()
    }

    // MARK: - Transport

    func advance() {
        // Read before advancing: the engine drops its anchor once the run finishes. Unlike
        // `engine.elapsed` this is not clamped to the plan, so a finish noticed late says so.
        let wall = engine.anchor.map { engine.now().timeIntervalSince($0) }
        dispatch(engine.advance(), wallElapsed: wall)
    }

    /// Jumps to the next phase. The boundary haptic and Health segment fire exactly as if
    /// the phase had run out, and the boundary is on time by definition.
    func skip() {
        dispatch(engine.skipPhase(), wallElapsed: nil)
        refreshBackstop()
        persistSnapshot()
    }

    #if os(watchOS)
    /// Plays `strength` for Settings' picker or the paywall's Feel Strongest, through the
    /// run's own player. A run can still be going behind those screens, and on one player
    /// its next boundary replaces the preview instead of being masked by it.
    func previewTaps(_ strength: TapStrength) {
        haptics.preview(strength)
    }
    #endif

    /// How late `event` is being announced, and how long the phase it opens will run, for
    /// the boundary haptics: a catch-up after a suspension taps once rather than bursting,
    /// and a burst has to fit inside its phase.
    ///
    /// - Parameter wallElapsed: The run's unclamped elapsed time when the event was noticed,
    ///   or nil when it is on time by construction (a start, a skip, a tap that finished it).
    nonisolated static func boundaryContext(
        for event: TimerEvent, wallElapsed: TimeInterval?, totalDuration: TimeInterval
    ) -> BoundaryContext {
        switch event {
        case .phaseBegan(let phase):
            BoundaryContext(
                lateness: max(0, (wallElapsed ?? phase.start) - phase.start),
                phaseDuration: phase.duration
            )
        case .finished:
            BoundaryContext(
                lateness: max(0, (wallElapsed ?? totalDuration) - totalDuration),
                phaseDuration: nil
            )
        case .countdown:
            .immediate
        }
    }

    /// Hands `event` to the boundary haptics along with its timing.
    private func announce(_ event: TimerEvent, wallElapsed: TimeInterval? = nil) {
        let context = Self.boundaryContext(
            for: event, wallElapsed: wallElapsed, totalDuration: engine.plan.totalDuration
        )
        haptics.play(event, context: context)
    }

    private func dispatch(_ events: [TimerEvent], wallElapsed: TimeInterval?) {
        guard !events.isEmpty else { return }
        for event in events {
            // Ahead of `finish()`, which ends the workout session that lets the app tap in
            // the background. Nothing cancels the finish burst once it has started.
            announce(event, wallElapsed: wallElapsed)
            switch event {
            case .phaseBegan(let phase):
                // Segment the Health workout at the same boundaries the user feels.
                if tier == .workout { workout.beginActivity(for: phase) }
                present()
            case .finished:
                finish()
            case .countdown:
                break
            }
        }
    }

    /// Hands the run as it now stands to the surface outside the app. Every change of shape
    /// goes through `persistSnapshot()`, which calls this; a phase running out changes
    /// nothing persisted, so `dispatch` calls it as well.
    private func present() {
        presenter.present(RunPresentation(engine: engine))
    }

    /// Sends the run to the iPhone that mirrors its workout session, at every change of
    /// shape. Phase changes need no message: the iPhone counts from the same anchor.
    private func mirror() {
        workout.mirror(RunMirrorState(engine: engine, health: summary.map { RunMirrorState.Health($0.health) }))
    }

    /// What the iPhone's mirror asked for.
    private func handleRemote(_ command: RunMirrorCommand) {
        switch command {
        case .pause:
            guard engine.status == .running else { return }
            togglePause()
        case .resume:
            guard engine.status == .paused else { return }
            togglePause()
        case .skip(let phase):
            guard engine.status == .running || engine.status == .paused,
                  engine.position.phaseIndex == phase else { return }
            skip()
        case .end:
            guard engine.isActive else { return }
            stopAndExit()
            endedRemotely += 1
        case .refresh:
            mirror()
        }
    }

    func togglePause() {
        switch engine.status {
        case .running:
            stopTicking()
            let events = engine.pause()
            guard events.isEmpty else {
                // The run had already completed; treat the tap as the finish.
                for event in events {
                    announce(event)
                    if case .finished = event { finish() }
                }
                return
            }
            // Nothing advances while paused, so there is nothing to tick for.
            workout.pause()
            // A burst still repeating would otherwise tap on into the pause.
            haptics.cancelPending()
            playCue(.stop)
        case .paused:
            engine.resume()
            workout.resume()
            playCue(.start)
            startTicking()
            attachBackgroundSupport()
        default:
            return
        }
        refreshBackstop()
        persistSnapshot()
    }

    private func finish() {
        upgradeTask?.cancel()
        upgradeTask = nil
        stopTicking()
        runtime.stop()
        let wasWorkoutTier = tier == .workout
        tier = .none
        summary = Summary(
            duration: engine.plan.totalDuration,
            rounds: engine.plan.totalRounds,
            health: wasWorkoutTier ? .saving : .notRecorded
        )
        persistSnapshot()
        // Through the serialised chain, not a bare cancelAll: an unchained cancel could land
        // after a quick Repeat had already scheduled the next run's alerts, and wipe them.
        refreshBackstop()
        Task {
            // A completed workout is saved to Health automatically, which is what a
            // workout app is expected to do once it has taken a session.
            let saved = await workout.end()
            if wasWorkoutTier { summary?.health = saved ? .saved : .failed }
        }
    }

    /// Runs the same workout again from the top without leaving the run screen.
    func restart() {
        summary = nil
        // The finish burst may still be repeating; the new run's first tap must stand alone.
        haptics.cancelPending()
        engine.stop()
        begin()
    }

    /// Ends the run and clears everything associated with it.
    func stopAndExit() {
        let wasFinished = engine.status == .finished
        // A burst still repeating must not outlive the run.
        haptics.cancelPending()
        // Stopping a timer is the documented meaning of the .stop haptic.
        if engine.isActive { playCue(.stop) }
        // A start still waiting on the permission prompts must not fire after this, and nor
        // must a pending workout-session retry.
        beginTask?.cancel()
        beginTask = nil
        upgradeTask?.cancel()
        upgradeTask = nil
        stopTicking()
        summary = nil
        engine.stop()
        runtime.stop()
        tier = .none
        persistSnapshot()
        refreshBackstop()
        // A completed workout is worth saving; one the user abandoned is not.
        if wasFinished {
            Task { await workout.end() }
        } else {
            workout.discard()
        }
    }

    // MARK: - Restoration

    /// Re-attaches to a run that was in flight when the app was last terminated.
    /// Returns true if a run was restored.
    @discardableResult
    func restoreIfNeeded(now: Date = Date()) -> Bool {
        guard engine.status == .idle, let snapshot = store.loadActiveRun(now: now) else { return false }
        engine.restore(
            anchor: snapshot.anchor, workout: snapshot.workout, paused: snapshot.pausedElapsed
        )
        guard engine.status != .finished else {
            store.saveActiveRun(nil)
            return false
        }
        log.info("restored an in-flight run")

        // A restored run comes back with no session behind it — `begin()` is guarded on
        // the idle state and never runs for this path. Without this the workout would
        // keep perfect time but lose every boundary alert after a relaunch.
        // A restored *paused* run has nothing to advance; ticking it would just burn battery
        // until the user resumed.
        if engine.status == .running { startTicking() }
        attachBackgroundSupport(recovering: true)
        present()
        return true
    }

    /// Called when the system relaunches the app to hand back a workout session that
    /// outlived it (`WKApplicationDelegate.handleActiveWorkoutRecovery()`).
    ///
    /// If the interrupted run can be resumed, restoring it adopts the session. If it cannot,
    /// the session is still saved and ended rather than left running — an orphaned session
    /// keeps the app alive, shows the workout indicator, and never reaches Health.
    func recoverWorkoutSession() {
        if engine.status == .idle, restoreIfNeeded() { return }
        guard !engine.isActive else { return }
        Task {
            if await workout.adoptRecoveredSession() {
                log.info("saving an orphaned workout session that had no resumable run")
                await workout.end()
            }
        }
    }

    /// Recomputes state after the app returns to the foreground. The engine needs no help
    /// catching up — elapsed time comes from the clock — but events since the last tick
    /// still have to be dispatched and the notification schedule re-aligned.
    func handleForeground() {
        advance()
        // Being foreground-active is the only state in which a session may be started, so
        // this is the moment to re-take a tier the system took away. Idempotent: the attach
        // is guarded on tier == .none.
        attachBackgroundSupport()
        refreshBackstop()
    }

    private func requestPermissionsIfNeeded() async {
        guard !hasRequestedPermissions else { return }
        hasRequestedPermissions = true
        canNotify = await notifications.requestAuthorization()
        if workout.isSupported {
            await workout.requestAuthorization()
        }
    }

    private func persistSnapshot() {
        switch engine.status {
        case .running:
            guard let anchor = engine.anchor else { return }
            store.saveActiveRun(
                RunSnapshot(workout: engine.plan.workout, anchor: anchor, pausedElapsed: nil)
            )
        case .paused:
            store.saveActiveRun(
                RunSnapshot(
                    workout: engine.plan.workout, anchor: Date(), pausedElapsed: engine.elapsed
                )
            )
        case .idle, .finished:
            store.saveActiveRun(nil)
        }
        // The complication reads the same snapshot, so nudge it whenever the run's shape
        // changes. Between these points `Text(timerInterval:)` carries the countdown on
        // its own, so there is nothing to reload every second.
        reloadWidgets()
        present()
        mirror()
    }
}
