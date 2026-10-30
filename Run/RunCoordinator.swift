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
    @ObservationIgnored let notifications: any BoundaryScheduling
    @ObservationIgnored private let store: WorkoutStore
    @ObservationIgnored private let pro: any ProGating
    @ObservationIgnored private let haptics: any BoundaryHaptics
    @ObservationIgnored private let playCue: @MainActor (TransportCue) -> Void
    @ObservationIgnored private let reloadWidgets: () -> Void
    @ObservationIgnored private let presenter: any RunPresenting
    @ObservationIgnored private let log = Logger(subsystem: "com.josiahrininger.intervally", category: "run")

    /// Which mechanism is keeping the run alive. This is not cosmetic: on the watch it decides
    /// whether boundary haptics can fire from the app at all, and together with whether the
    /// cues can be heard away from the app (`awayCuesAudible`), it decides what the
    /// notification backstop does (`backstop(isRunning:tier:cuesAudible:)`).
    enum RuntimeTier: String, CaseIterable {
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

        /// Whether the app can rely on playing its own haptics at interval boundaries. Only the
        /// watch's taps depend on it: the iPhone's are felt only in front, whatever the tier,
        /// and its sounds play away from the app under any.
        var deliversHaptics: Bool { self == .workout }
    }

    /// The iPhone's cues can't sound right now (their audio stopped away from the app and
    /// couldn't be started again). The notification backstop marks the changes meanwhile,
    /// whatever keeps the run going. See `cuesHealthChanged(healthy:)`.
    private(set) var cuesFailing = false

    /// Whether the run's own cues can be heard, or felt, with the app away, under `tier`. On
    /// the watch, the default, only a workout session's taps can (`deliversHaptics`). The
    /// iPhone's sounds keep playing away from the app whatever keeps the run going, so there
    /// `PhoneRun` answers with whether any sound is on.
    @ObservationIgnored var awayCuesAudible: @MainActor (RuntimeTier) -> Bool = { $0.deliversHaptics }

    /// Whether the app is in front. Away from it, a top-up of the alerts asks for the time to
    /// finish (`beginBackgroundWork`). The watch never needs to ask; the iPhone says.
    @ObservationIgnored var isAppActive: @MainActor () -> Bool = { true }

    /// Asks for the time to finish the work named, away from the app, and returns what to call
    /// once it's done. On iPhone a background task; elsewhere there's nothing to ask for.
    @ObservationIgnored var beginBackgroundWork: @MainActor (String) -> @MainActor () -> Void = { _ in {} }

    /// The alerts taken down ahead of their changes since the last schedule or cancel
    /// (`disarmNextAlertIfDue`), so each comes down once.
    @ObservationIgnored private var disarmed: Set<String> = []

    /// How close a change has to be before the app takes its alert down. Inside it the ticker
    /// wakes at least every half second, and at the 2-second countdown tick.
    static let disarmLead: TimeInterval = 2

    /// The lead a schedule asks for while the app takes the alerts down: a little over
    /// `disarmLead`, so a schedule never puts back an alert just taken down, or about to be.
    static let disarmingMinimumLead: TimeInterval = 2.5

    /// The top-up check after the latest change, if any (`topUpBackstopIfLow`).
    @ObservationIgnored private var topUpTask: Task<Void, Never>?

    private(set) var tier: RuntimeTier = .none {
        didSet {
            if tier != oldValue { diagnostics("Run: keeps running by \(tier.rawValue) (was \(oldValue.rawValue))") }
        }
    }

    /// Where the run's notes go: `RunDiagnostics`, for the user to share. Injectable so tests
    /// can read what a run noted.
    @ObservationIgnored var diagnostics: @MainActor (String) -> Void = { RunDiagnostics.shared.note($0) }

    /// Writes the notes out now rather than two seconds on (`RunDiagnostics.flush()`): at the
    /// finish and at End, and again once the workout's Health save is over, after which the
    /// app may not run again for a while. Injectable alongside `diagnostics`.
    @ObservationIgnored var flushDiagnostics: @MainActor () -> Void = { RunDiagnostics.shared.flush() }

    /// When `handleForeground` last noted the app coming to the front, on the run's clock.
    @ObservationIgnored private var lastForegroundNote: Date?

    /// How often the app coming to the front is noted with no run under way. The watch comes
    /// forward at every wrist raise, and a note each time said no more than one a minute.
    static let idleForegroundNoteInterval: TimeInterval = 60

    /// How late this run's boundaries were announced, for the line its diagnostics get once
    /// it finishes or is ended.
    @ObservationIgnored private var timing = BoundaryTimingTally(lateThreshold: RunPlatform.lateBoundary)

    /// What the run amounted to, for the summary screen: finished, or ended early with Save
    /// Workout.
    struct Summary: Equatable, Sendable {
        let duration: TimeInterval
        let rounds: Int
        var health: HealthSave
        /// Set only for a run ended early with Save Workout: the rounds the workout had, of
        /// which the run reached `rounds`.
        var plannedRounds: Int? = nil

        var endedEarly: Bool { plannedRounds != nil }

        /// How far a run ended with Save Workout got: "5 of 8 rounds".
        var roundsReachedText: String? {
            plannedRounds.map { "\(rounds) of \(DurationFormat.rounds($0))" }
        }

        /// The summary's line for a run ended with Save Workout: "Ended early: 5 of 8 rounds".
        var endedEarlyText: String? {
            roundsReachedText.map { "Ended early: \($0)" }
        }

        /// How full the summary's ring is drawn: all the way for a finished run, and only as
        /// far as the rounds reached for one ended early, so the ring doesn't claim a finish.
        var ringFraction: Double {
            guard let plannedRounds, plannedRounds > 0 else { return 1 }
            return min(1, Double(rounds) / Double(plannedRounds))
        }
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

    /// Whether the run screen shows the summary: the run finished, or was ended with Save
    /// Workout.
    var showsSummary: Bool { engine.status == .finished || summary != nil }

    /// How long a run has to have gone on before End offers to save it: one ended in its
    /// first minute is far more likely a false start than a workout to keep.
    static let saveOnEndMinimum: TimeInterval = 60

    /// Whether End offers Save Workout: only for a run on a workout session, which has a
    /// Health workout to save, once it is a minute in. Otherwise End asks as it always has.
    var offersSaveOnEnd: Bool {
        engine.isActive && tier == .workout && engine.elapsed >= Self.saveOnEndMinimum
    }

    /// The snapshot of a run ended with Save Workout whose Health save is still under way. It
    /// stays saved while no other run has one (`persistSnapshot`), so a relaunch before the
    /// save is done finishes it (`restoreIfNeeded`).
    @ObservationIgnored private var pendingSave: RunSnapshot?

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
    /// The retry is inside `workout.start` rather than waiting for its next try: cancelling
    /// it then would discard a session that may just have started.
    @ObservationIgnored private var upgradeAttemptInFlight = false

    /// How long to wait before each retry.
    ///
    /// Out to half a minute: on a real iPhone the first workout session raises a one-time
    /// system prompt about workout data while the phone is locked, and a session asked for
    /// while it is still up doesn't start. Two retries a few seconds apart ran out before
    /// anyone had answered it, and the whole run went without a session: silent the moment
    /// the user left the app. Coming back to the app tries again too (`handleForeground`).
    @ObservationIgnored var upgradeRetryDelays: [TimeInterval] = [1.0, 3.0, 10.0, 30.0]

    /// How each retry waits out its delay. Injectable so tests can move the retries on by
    /// exactly their delays rather than sleeping for real.
    @ObservationIgnored var upgradeSleep: @Sendable (TimeInterval) async throws -> Void = {
        try await Task.sleep(for: .seconds($0))
    }

    /// Whether a runtime tier is still being taken for this run, so the run screen can tell
    /// "not yet" from "not at all" before saying the sounds stop outside the app.
    private(set) var isAcquiringTier = false

    /// Drives event dispatch. Owned by the coordinator, not the view: an `autoconnect()`
    /// publisher tears its timer down when the last subscriber disappears, so tying it to
    /// the run screen meant walking away from that screen stopped the workout advancing —
    /// no boundary haptics, and no `finish()`. Display smoothness is handled separately by
    /// `TimelineView`, so this only has to wake when there is something to announce.
    ///
    /// It sleeps until the plan's next countdown second or interval change, and wakes just
    /// past it: polling every half second, the cues and taps landed anywhere up to half a
    /// second after the change on screen. It never sleeps longer than half a second, so
    /// pausing and the clock on screen behave as they always have, and a deadline worked
    /// out wrong is still noticed no later than polling noticed it.
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// How the ticker sleeps. Injectable so tests can move a run's clock by exactly as much as
    /// they say. Zero tolerance: the wake is when the cue plays, so it mustn't be put off to
    /// share a later wake with other timers.
    @ObservationIgnored var tickSleep: @Sendable (TimeInterval) async throws -> Void = {
        try await Task.sleep(for: .seconds($0), tolerance: .zero)
    }

    /// The ticker's sleep with `remaining` seconds left until the next thing to announce: 8 ms
    /// past it, so the engine finds the moment reached; at least 10 ms, so a wake that finds
    /// it not quite reached can't spin; and at most half a second.
    nonisolated static func tickDelay(_ remaining: TimeInterval) -> TimeInterval {
        min(0.5, max(0.01, remaining + 0.008))
    }

    private func startTicking() {
        guard ticker == nil else { return }
        let sleep = tickSleep
        ticker = Task { [weak self] in
            while !Task.isCancelled, let delay = self?.nextTickDelay() {
                // A cancelled sleep throws at once: leave, rather than advance a stopped run.
                do { try await sleep(delay) } catch { return }
                guard let self, !Task.isCancelled else { return }
                self.advance()
            }
            // Out of the loop uncancelled, the run stopped without `stopTicking()`. Let go of
            // the ticker, so `isTicking` says so and the next run can start one.
            if !Task.isCancelled { self?.ticker = nil }
        }
    }

    /// How long the ticker sleeps from now: until the next countdown second, interval change
    /// or finish, padded by `tickDelay`. Nil once the run is no longer running: every pause,
    /// finish and stop ends the loop through `stopTicking()`, and should one ever be missed,
    /// a finished run's clock sits at its end, where the ticker would wake every 10 ms for
    /// good rather than every half second as in 1.2.
    private func nextTickDelay() -> TimeInterval? {
        guard engine.status == .running else { return nil }
        let elapsed = engine.elapsed
        // At the end already: the next advance finishes the run.
        guard let next = engine.plan.nextEventElapsed(afterElapsed: elapsed) else { return Self.tickDelay(0) }
        return Self.tickDelay(next - elapsed)
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }

    /// Set by a Resume with a phase change already due, which a skip while paused leaves,
    /// until the next advance announces it. The ticker's first wake does that, half a second
    /// after Resume as in 1.2, rather than at once: on the watch Resume plays its own tap, and
    /// the phase's tap mustn't land on top of it. That half second is the gap kept on purpose,
    /// not the clock noticed late, so the run's timing line leaves this change out.
    @ObservationIgnored private var boundaryDueAtResume = false

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

    /// Awaits the chained notification update, and the top-up check after the latest change,
    /// so tests can assert on a settled schedule.
    func backstopSettled() async {
        await topUpTask?.value
        await backstopTask?.value
    }

    /// Awaits what a change leaves running once it returns: a tier still being taken (a resume
    /// with none starts one), then the notification update that ends it, and any top-up. A Live
    /// Activity tap waits on it (`PhoneRun.control(_:)`): iOS can suspend the app as soon as the
    /// tap is done, and a resume that left with its alerts still to come had none at all.
    func changeSettled() async {
        await supportTask?.value
        await backstopSettled()
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
        // A run ended with Save Workout keeps its summary up until Done or Repeat, which clears
        // it first: this is that screen showing again, not a new Start.
        guard engine.status == .idle, beginTask == nil, summary == nil else { return }
        diagnostics("Run: started \(engine.plan.workout.name)")
        // A new run's cues start out sounding; a failure the last run ended on is not this one's.
        cuesFailing = false
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
        isAcquiringTier = true
        supportTask = Task {
            // Asked here rather than at launch: the permission only means something once
            // the user has actually started a workout, and a prompt on the very first
            // frame of a cold launch is both jarring and easy to decline out of hand.
            await requestPermissionsIfNeeded()
            await startBackgroundSupport(recovering: recovering)
            // Clear BEFORE the deciding refresh: refreshBackstop defers while an acquisition
            // is in flight, and this is the one call that must not be deferred.
            supportTask = nil
            isAcquiringTier = false
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
            // rather than waiting for the next boundary. One skipped to while paused is still
            // to be announced, and its announcement opens it: opened here as well, it would
            // be in Health twice.
            if let phase = engine.position.phase, !engine.hasPendingBoundary { workout.beginActivity(for: phase) }
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
        let sleep = upgradeSleep
        upgradeTask = Task { [weak self] in
            // Done, one way or the other: a later return to the app may try again. Not when
            // cancelled, as whoever cancelled it has already replaced or cleared it.
            defer { if !Task.isCancelled { self?.upgradeTask = nil } }
            guard let delays = self?.upgradeRetryDelays else { return }
            for delay in delays {
                try? await sleep(delay)
                guard let self, !Task.isCancelled, self.engine.isActive,
                      self.tier == .extendedRuntime else { return }
                self.diagnostics("Run: retrying the workout session")
                self.upgradeAttemptInFlight = true
                let started = await self.workout.start(for: self.engine.plan.workout)
                self.upgradeAttemptInFlight = false
                guard started else { continue }

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
                // As in `startBackgroundSupport`: a phase still to be announced opens its own.
                if let phase = self.engine.position.phase, !self.engine.hasPendingBoundary {
                    self.workout.beginActivity(for: phase)
                }
                if self.engine.status == .paused { self.workout.pause() }
                // The app now plays its own haptics, so the notification backstop goes.
                self.refreshBackstop()
                return
            }
        }
    }

    /// What the notification backstop does for a run.
    struct Backstop: Equatable, Sendable {
        /// Whether the run's changes are scheduled as alerts.
        var isScheduled: Bool
        /// Whether the app takes each alert down just before its change, and marks the change
        /// itself (`disarmNextAlertIfDue`). A dead-man's switch: an alert goes off only if the
        /// app wasn't running to take it down, so no change is marked twice.
        var disarms: Bool
    }

    /// Decides the backstop, apart from any run, so every case is testable: the watch's, which
    /// is 1.2's, among them.
    ///
    /// - Parameter cuesAudible: Whether the run's own cues can be heard, or felt, away from the
    ///   app: what `awayCuesAudible` says for the tier, unless the cues can't sound at all.
    nonisolated static func backstop(isRunning: Bool, tier: RuntimeTier, cuesAudible: Bool) -> Backstop {
        // A workout session keeps the app running, so cues that can be heard mark every change,
        // and alerts as well would mark each twice. Without one the app can be suspended at any
        // moment, so the alerts are scheduled whatever the cues do, and while the cues can be
        // heard the app takes each alert down just before its change.
        let isScheduled = isRunning && (tier != .workout || !cuesAudible)
        return Backstop(isScheduled: isScheduled, disarms: isScheduled && tier != .workout && cuesAudible)
    }

    /// The backstop for the run as it stands.
    private var backstop: Backstop {
        Self.backstop(
            isRunning: engine.status == .running, tier: tier,
            cuesAudible: awayCuesAudible(tier) && !cuesFailing
        )
    }

    /// Keeps the notification backstop in step with the run (`backstop`).
    ///
    /// On the watch, a workout session plays its own haptics, so scheduling notifications as
    /// well would double-alert at every boundary and burn the pending-request budget for
    /// nothing. On iPhone the sounds play away from the app with or without one, so what
    /// counts is whether there are any: with Health declined each change once had a cue and
    /// an alert, and with the beeps and the voice off under a session, nothing at all.
    private func refreshBackstop() {
        // While a tier is still being acquired the right answer is unknown: scheduling now
        // (as the foreground transition did when the permission sheet dismissed) burns a
        // batch of notifications that the acquisition's own refresh then has to cancel, and
        // opens a double-alert window if a boundary lands in between. The acquisition ends
        // with its own refreshBackstop(), and it is bounded, so deferring is safe.
        guard supportTask == nil else { return }
        let backstop = self.backstop
        let wanted: (plan: IntervalPlan, anchor: Date, minimumLead: TimeInterval)?
        if backstop.isScheduled, let anchor = engine.anchor {
            // While the app takes the alerts down, a change about to be taken down is left
            // out, so a schedule never puts one back.
            let lead = backstop.disarms ? Self.disarmingMinimumLead : NotificationScheduler.defaultMinimumLead
            wanted = (engine.plan, anchor, lead)
        } else {
            wanted = nil
        }
        // A schedule starts with a cancel, so what was taken down is gone either way, and a
        // change the new schedule names again comes down afresh.
        disarmed.removeAll()

        // Chain onto the previous update rather than firing an independent task. Two
        // unstructured tasks can enter the scheduler in either order, so a quick
        // pause-then-resume could otherwise apply the cancel *after* the reschedule and
        // leave a running workout with no backstop at all.
        let previous = backstopTask
        backstopTask = Task { [notifications] in
            await previous?.value
            if let wanted {
                await notifications.schedule(plan: wanted.plan, anchor: wanted.anchor, minimumLead: wanted.minimumLead)
            } else {
                await notifications.cancelAll()
            }
        }
    }

    /// The backstop's dead-man's switch. While the app marks the changes with cues that can be
    /// heard away from it, it takes each change's alert down once the change is `disarmLead`
    /// away. Only a running app can, so one suspended or stopped by then leaves the alert to
    /// go off, and nothing marks a change twice. Paused, nothing ticks, and nothing comes down.
    private func disarmNextAlertIfDue() {
        guard engine.status == .running, let index = engine.position.phaseIndex else { return }
        let plan = engine.plan
        let next = index + 1
        let (identifier, moment) = next < plan.phases.count
            ? (NotificationScheduler.identifier(forPhase: next), plan.phases[next].start)
            : (NotificationScheduler.finishIdentifier, plan.totalDuration)
        // The clock first: most wakes are further off, and the backstop reads the settings.
        guard moment - engine.elapsed <= Self.disarmLead, !disarmed.contains(identifier),
              backstop.disarms else { return }
        disarmed.insert(identifier)
        // After any schedule still adding, which could otherwise put the alert back.
        let previous = backstopTask
        backstopTask = Task { [notifications] in
            await previous?.value
            await notifications.disarm(identifier: identifier)
        }
    }

    /// Schedules the alerts again once they run low: one schedule holds the next 59 changes
    /// and the finish, and a longer workout's changes went unmarked from there. Asked after
    /// every change, of the schedule as that change left it. Away from the app, the schedule
    /// is given the time to finish (`beginBackgroundWork`).
    private func topUpBackstopIfLow() {
        let previous = topUpTask
        topUpTask = Task { [weak self] in
            await previous?.value
            // Read once this runs, not when asked: a skip asks, then schedules afresh, and the
            // answer has to be about that schedule.
            await self?.backstopTask?.value
            guard let self, self.engine.status == .running,
                  await self.notifications.needsTopUp(now: self.engine.now()),
                  // It may have been paused or ended while the scheduler answered.
                  self.engine.status == .running else { return }
            let finished = self.isAppActive() ? nil : self.beginBackgroundWork("Schedule the workout's next alerts")
            self.refreshBackstop()
            guard let finished else { return }
            await self.backstopTask?.value
            finished()
        }
    }

    /// Whether the cues' audio can sound, at every check of it; only a change does anything. A
    /// workout session keeps the app running, but running isn't sounding: with the audio gone,
    /// the changes would pass unmarked. So the notification backstop takes over until the
    /// cues can sound again.
    func cuesHealthChanged(healthy: Bool) {
        guard cuesFailing == healthy else { return }
        cuesFailing = !healthy
        // Without a workout session the alerts are scheduled either way: this only decides
        // whether the app takes them down before their changes, from the next change on.
        // Scheduling again would cancel the same alerts and add them back.
        guard tier == .workout else { return }
        refreshBackstop()
    }

    /// What `awayCuesAudible` says has changed, as when the iPhone's volume goes down to silent
    /// or back up. Without a workout session it's read afresh as each change comes, so there's
    /// nothing to do. Under one it decides whether the alerts are scheduled at all.
    func awayCuesAudibilityChanged() {
        guard tier == .workout else { return }
        refreshBackstop()
    }

    /// Called when the run screen goes away.
    func end() {
        // Walking away from a finished run ends it, rather than leaving `.finished` behind
        // to block the next Start, and from one ended with Save Workout, rather than leaving
        // its summary to block it.
        if showsSummary {
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
        // Whatever was due at Resume has been announced now.
        boundaryDueAtResume = false
        disarmNextAlertIfDue()
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

    /// Hands `event` to the boundary haptics along with its timing, and keeps that timing for
    /// the run's diagnostics.
    private func announce(_ event: TimerEvent, wallElapsed: TimeInterval? = nil) {
        let context = Self.boundaryContext(
            for: event, wallElapsed: wallElapsed, totalDuration: engine.plan.totalDuration
        )
        haptics.play(event, context: context)
        switch event {
        case .phaseBegan, .finished:
            // Only a change the clock noticed says how promptly it was announced: a start or
            // a skip is on time by construction, and one due at Resume waits on purpose.
            if wallElapsed != nil, !boundaryDueAtResume { timing.record(lateness: context.lateness) }
        case .countdown:
            // A tick carries no lateness of its own (`BoundaryContext.immediate`).
            break
        }
    }

    /// Writes the run's timing line. The finish and an End both call this; whichever comes
    /// first writes it, and the other finds nothing left to say.
    private func noteTiming() {
        if let line = timing.close() { diagnostics(line) }
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
                topUpBackstopIfLow()
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
    /// shape. Phase changes need no message: the iPhone counts from the same anchor. Each says
    /// the run takes `.endAndSave`, so the iPhone can offer Save Workout.
    private func mirror() {
        workout.mirror(RunMirrorState(
            engine: engine, health: summary.map { RunMirrorState.Health($0.health) }, supportsEndAndSave: true
        ))
    }

    /// What the iPhone's mirror asked for, on the watch, or a Live Activity button on iPhone
    /// (`PhoneRun.control(_:)`). Each is done only if the run still stands as the button
    /// showed it, so a tap that crosses a change on its way does nothing rather than the
    /// opposite.
    func handleRemote(_ command: RunMirrorCommand) {
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
        case .endAndSave:
            // Saved just as Save Workout here saves it, and the screen closes as for End:
            // nobody on the watch is there to tap Done.
            guard engine.isActive else { return }
            endAndSave()
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
            boundaryDueAtResume = engine.hasPendingBoundary
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
        noteTiming()
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
        // The run's notes, its timing line among them, reach the disk now: the session ends
        // next, and the watch may suspend the app before the write two seconds on comes round.
        flushDiagnostics()
        Task {
            // A completed workout is saved to Health automatically, which is what a
            // workout app is expected to do once it has taken a session.
            let saved = await workout.end()
            if wasWorkoutTier { summary?.health = saved ? .saved : .failed }
            // What the session noted as it ended and saved came after the flush above.
            flushDiagnostics()
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

    /// End with Save Workout: the run stops where it is, its summary says how far it got, and
    /// its Health workout is ended and saved, as at the finish, rather than discarded. Until
    /// the save is done the snapshot says so (`savesOnEnd`), so a relaunch in the middle
    /// finishes the save instead of bringing the run back.
    func endAndSave() {
        guard engine.isActive else { return }
        // Read before the engine stops, which takes its clock back to zero.
        let elapsed = engine.elapsed
        let plan = engine.plan
        let rounds = Self.roundsReached(at: engine.position, totalRounds: plan.totalRounds)
        // As at End: a burst still repeating must not outlive the run, and the stop is felt.
        haptics.cancelPending()
        playCue(.stop)
        beginTask?.cancel()
        beginTask = nil
        upgradeTask?.cancel()
        upgradeTask = nil
        stopTicking()
        noteTiming()
        diagnostics("Run: ended early at \(DurationFormat.timer(Int(elapsed))), saving")
        engine.stop()
        runtime.stop()
        let wasWorkoutTier = tier == .workout
        tier = .none
        summary = Summary(
            duration: elapsed,
            rounds: rounds,
            health: wasWorkoutTier ? .saving : .notRecorded,
            plannedRounds: plan.totalRounds
        )
        // Its anchor is the moment Save was tapped, so a save finished after a relaunch ends
        // the workout there too, not at the relaunch.
        let endedAt = Date()
        let snapshot = RunSnapshot(workout: plan.workout, anchor: endedAt, pausedElapsed: elapsed, savesOnEnd: true)
        pendingSave = snapshot
        persistSnapshot()
        refreshBackstop()
        // As at the finish: the session ends next, and nothing keeps the app running after.
        flushDiagnostics()
        // The audio, which kept the app running, goes back now, and the session ends before
        // the save does: a phone locked straight after must not leave it to a suspended app.
        let finished = beginBackgroundWork("Save the workout")
        Task {
            let saved = await workout.end(at: endedAt)
            if wasWorkoutTier { summary?.health = saved ? .saved : .failed }
            saveSettled(snapshot)
            flushDiagnostics()
            finished()
        }
    }

    /// The rounds a run had reached at `position`, for the summary of one ended early: the one
    /// under way, none before the first, and every one from the cooldown on.
    nonisolated static func roundsReached(at position: IntervalPlan.Position, totalRounds: Int) -> Int {
        guard let phase = position.phase else { return totalRounds }
        return switch phase.kind {
        case .prepare, .warmup: 0
        case .work, .rest: phase.round
        case .cooldown: totalRounds
        }
    }

    /// The save of a run ended with Save Workout is over, one way or the other, so a relaunch
    /// has nothing left to finish. Its snapshot goes, unless a run since has one of its own.
    private func saveSettled(_ snapshot: RunSnapshot) {
        guard pendingSave == snapshot else { return }
        pendingSave = nil
        if !engine.isActive { store.saveActiveRun(nil) }
    }

    /// Ends the run and clears everything associated with it.
    func stopAndExit() {
        let wasFinished = engine.status == .finished
        // Ended with Save Workout: over already, and its save goes on without the screen.
        let wasSaved = summary?.endedEarly == true
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
        noteTiming()
        summary = nil
        engine.stop()
        runtime.stop()
        tier = .none
        persistSnapshot()
        refreshBackstop()
        // As at the finish: nothing keeps the app running from here.
        flushDiagnostics()
        // A completed workout is worth saving; one the user abandoned is not, and one ended
        // with Save Workout is being saved already.
        if wasFinished {
            Task {
                await workout.end()
                flushDiagnostics()
            }
        } else if !wasSaved {
            workout.discard()
        }
    }

    // MARK: - Restoration

    /// Re-attaches to a run that was in flight when the app was last terminated.
    /// Returns true if a run was restored.
    @discardableResult
    func restoreIfNeeded(now: Date = Date()) -> Bool {
        guard engine.status == .idle, let snapshot = store.loadActiveRun(now: now) else { return false }
        // Ended with Save Workout, and the app went away before the save was done: there is
        // no run to bring back, only the save to finish.
        if snapshot.savesOnEnd == true {
            finishSave(of: snapshot)
            return false
        }
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

    /// Finishes the save of a run ended with Save Workout that the app went away in the
    /// middle of: the session the system kept for it is adopted, tagged if need be, and
    /// ended, which saves it. With no session left there is nothing more to save.
    private func finishSave(of snapshot: RunSnapshot) {
        // Already being finished: a launch restores from more than one place.
        guard pendingSave == nil else { return }
        pendingSave = snapshot
        Task {
            if await workout.adoptRecoveredSession(for: snapshot.workout) {
                log.info("finishing the save of a run ended with Save Workout")
                // Ended where Save was tapped: the time since, until this relaunch, was
                // never part of the workout.
                await workout.end(at: snapshot.anchor)
            }
            saveSettled(snapshot)
            flushDiagnostics()
        }
    }

    /// Called when the system relaunches the app to hand back a workout session that
    /// outlived it (`WKApplicationDelegate.handleActiveWorkoutRecovery()`).
    ///
    /// If the interrupted run can be resumed, restoring it adopts the session. If it cannot,
    /// the session is still saved and ended rather than left running — an orphaned session
    /// keeps the app alive, shows the workout indicator, and never reaches Health.
    func recoverWorkoutSession() {
        if engine.status == .idle, restoreIfNeeded() { return }
        // A save being finished (`finishSave`) has taken the session already.
        guard !engine.isActive, pendingSave == nil else { return }
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
        noteForeground()
        advance()
        // Being foreground-active is the only state in which a session may be started, so
        // this is the moment to re-take a tier the system took away. Idempotent: the attach
        // is guarded on tier == .none.
        attachBackgroundSupport()
        // A run that fell back still has no workout session, and on iPhone the fallback
        // never ends on its own to send it back through the attach above. Back in front is
        // when one may be started, perhaps with Health just allowed in Settings, so try
        // again rather than staying silent outside the app for the rest of the run.
        // Restarted rather than left waiting: allowing Health and coming straight back
        // otherwise waited out the rest of a 30-second pause before the next try.
        if tier == .extendedRuntime, workout.isSupported, !upgradeAttemptInFlight {
            scheduleWorkoutUpgrade()
        }
        refreshBackstop()
    }

    /// Notes the app coming to the front: every time during a run, where it says what keeps
    /// the run going, and otherwise only once the last such note is a minute old.
    private func noteForeground() {
        let now = engine.now()
        // A clock set back since counts as a minute gone, rather than silencing the notes.
        if !engine.isActive, let last = lastForegroundNote,
           (0...Self.idleForegroundNoteInterval).contains(now.timeIntervalSince(last)) {
            return
        }
        lastForegroundNote = now
        diagnostics("App: in front. Run \(engine.status), keeps running by \(tier.rawValue)")
    }

    private func requestPermissionsIfNeeded() async {
        guard !hasRequestedPermissions else { return }
        hasRequestedPermissions = true
        canNotify = await notifications.requestAuthorization()
        diagnostics("Permissions: notifications \(canNotify ? "allowed" : "NOT ALLOWED")")
        if workout.isSupported {
            let asked = await workout.requestAuthorization()
            diagnostics("Permissions: Health request \(asked ? "answered" : "failed")")
        } else {
            diagnostics("Permissions: Health not available on this device")
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
            // Nothing, unless a run ended with Save Workout is still saving.
            store.saveActiveRun(pendingSave)
        }
        // The complication reads the same snapshot, so nudge it whenever the run's shape
        // changes. Between these points `Text(timerInterval:)` carries the countdown on
        // its own, so there is nothing to reload every second.
        reloadWidgets()
        present()
        mirror()
    }
}
