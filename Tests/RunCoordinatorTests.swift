//
//  RunCoordinatorTests.swift
//  IntervallyTests
//

import Testing
import Foundation
@testable import Intervally

/// Lets the coordinator's `Task`-based work settle before asserting.
private func settle(_ coordinator: RunCoordinator) async {
    for _ in 0..<6 {
        for _ in 0..<8 { await Task.yield() }
        await coordinator.backstopSettled()
    }
}

/// Runs the engine's clock past the end of the plan and lets the coordinator notice.
@MainActor
private func finishRun(_ coordinator: RunCoordinator) {
    let engine = coordinator.engine
    let end = Date().addingTimeInterval(engine.plan.totalDuration + 1)
    engine.now = { end }
    coordinator.advance()
}

@Suite("Run coordinator — runtime tier selection")
@MainActor
struct RunCoordinatorTierTests {

    @Test("A workout session takes the workout tier and suppresses the notification backstop")
    func workoutTierSuppressesBackstop() async {
        let (coordinator, _, workout, runtime, spy, _, _) = makeCoordinator()
        workout.startResult = true

        coordinator.begin()
        await settle(coordinator)

        #expect(coordinator.tier == .workout)
        #expect(workout.startCount == 1)
        // Under a workout session the app plays its own haptics; scheduling notifications as
        // well would double-alert at every single boundary.
        #expect(spy.scheduleCount == 0)
        #expect(runtime.startCount == 0)
    }

    @Test("Without a workout session the run falls back to extended runtime and schedules alerts")
    func extendedRuntimeTierSchedulesBackstop() async {
        let (coordinator, _, workout, runtime, spy, _, _) = makeCoordinator()
        workout.isSupported = false
        workout.startResult = false

        coordinator.begin()
        await settle(coordinator)

        #expect(coordinator.tier == .extendedRuntime)
        #expect(runtime.startCount == 1)
        #expect(spy.scheduleCount == 1)
    }

    @Test("A brand-new run closes out a leftover session instead of inheriting it")
    func freshRunEndsLeftoverSession() async {
        // The system can still be holding a session from a run that is no longer resumable.
        // Appending a new workout onto it would save one merged workout starting at the old
        // run's time; the leftover must be saved on its own and a clean session started.
        let (coordinator, _, workout, _, _, _, _) = makeCoordinator()
        workout.recoverableSession = true

        coordinator.begin()
        await settle(coordinator)

        #expect(workout.endCount == 1)
        #expect(workout.startCount == 1)
        #expect(coordinator.tier == .workout)
    }

    @Test("A restored run adopts the recovered session rather than starting a second one")
    func restoreAdoptsRecoveredSession() async {
        let defaults = makeTestDefaults()
        let seed = WorkoutStore(defaults: defaults)
        seed.saveActiveRun(
            RunSnapshot(workout: seed.selected, anchor: Date().addingTimeInterval(-20), pausedElapsed: nil)
        )
        let (coordinator, _, workout, _, _, _, _) = makeCoordinator(defaults: defaults)
        workout.recoverableSession = true

        #expect(coordinator.restoreIfNeeded())
        await settle(coordinator)

        // Starting a second session while the system still holds the first orphans the
        // pre-termination segment, so it must never happen on this path.
        #expect(coordinator.tier == .workout)
        #expect(workout.startCount == 0)
        #expect(workout.endCount == 0)
    }

    @Test("A workout session dying mid-run clears the tier and restores the backstop")
    func unexpectedEndRestoresBackstop() async {
        let (coordinator, _, workout, _, spy, _, _) = makeCoordinator()
        workout.startResult = true

        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.tier == .workout)
        #expect(spy.scheduleCount == 0)

        // The system hands the session to another app, or ends it.
        workout.startResult = false
        workout.simulateUnexpectedEnd()
        await settle(coordinator)

        #expect(coordinator.tier != .workout)
        // Without this the run would finish with no alerting mechanism at all.
        #expect(spy.scheduleCount >= 1)
    }

    @Test("An extended runtime session invalidating while paused still clears the tier")
    func invalidationWhilePausedClearsTier() async {
        let (coordinator, _, workout, runtime, _, _, _) = makeCoordinator()
        workout.isSupported = false
        workout.startResult = false

        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.tier == .extendedRuntime)

        coordinator.togglePause()
        #expect(coordinator.engine.status == .paused)

        // The user pressed the crown while paused. The session is gone either way; leaving
        // the tier set made the state terminal, because re-attaching requires tier == .none.
        runtime.simulateInvalidation()
        await settle(coordinator)

        #expect(coordinator.tier == .none)
    }
}

@Suite("Run coordinator — lifecycle")
@MainActor
struct RunCoordinatorLifecycleTests {

    @Test("Beginning starts the clock and the ticker")
    func beginStartsRun() async {
        let (coordinator, _, _, _, _, _, _) = makeCoordinator()

        coordinator.begin()
        await settle(coordinator)

        #expect(coordinator.engine.status == .running)
        #expect(coordinator.isTicking)
    }

    @Test("Pausing stops the ticker; resuming starts it again")
    func pauseStopsTicker() async {
        let (coordinator, _, workout, _, _, _, _) = makeCoordinator()

        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.isTicking)

        coordinator.togglePause()
        // Nothing advances while paused, so a 2 Hz loop is pure battery cost.
        #expect(coordinator.isTicking == false)
        #expect(workout.pauseCount == 1)

        coordinator.togglePause()
        await settle(coordinator)
        #expect(coordinator.isTicking)
        #expect(workout.resumeCount == 1)
    }

    @Test("Ending a run tears down every tier and cancels the backstop")
    func stopTearsDownEverything() async {
        let (coordinator, store, workout, runtime, spy, _, _) = makeCoordinator()
        workout.isSupported = false
        workout.startResult = false

        coordinator.begin()
        await settle(coordinator)

        coordinator.stopAndExit()
        await settle(coordinator)

        #expect(coordinator.engine.status == .idle)
        #expect(coordinator.tier == .none)
        #expect(coordinator.isTicking == false)
        #expect(runtime.stopCount >= 1)
        // Abandoned runs are discarded rather than written to Health.
        #expect(workout.discardCount == 1)
        #expect(spy.calls.last == .cancelAll)
        #expect(store.loadActiveRun() == nil)
    }

    @Test("A finished run does not wedge the next Start")
    func finishedRunDoesNotWedgeStart() async {
        // begin() used to accept only .idle, and nothing reset .finished off-screen, so
        // leaving the completion screen by swiping back made Start a no-op that re-presented
        // the finished screen forever.
        let (coordinator, store, _, _, _, _, _) = makeCoordinator()
        var short = store.selected
        short.prepareSeconds = 0
        short.workSeconds = 5
        short.restSeconds = 0
        short.rounds = 1
        store.update(short)

        coordinator.begin()
        await settle(coordinator)

        finishRun(coordinator)
        #expect(coordinator.engine.status == .finished)

        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.engine.status == .running)
    }

    @Test("Restoring an interrupted run re-takes a runtime tier")
    func restoreTakesTier() async {
        let defaults = makeTestDefaults()
        let seed = WorkoutStore(defaults: defaults)
        let workout = seed.selected
        seed.saveActiveRun(
            RunSnapshot(workout: workout, anchor: Date().addingTimeInterval(-20), pausedElapsed: nil)
        )

        let (coordinator, _, session, _, _, _, _) = makeCoordinator(defaults: defaults)
        session.startResult = true

        #expect(coordinator.restoreIfNeeded())
        await settle(coordinator)

        // A restored run used to come back with no session behind it at all, because begin()
        // is guarded on .idle and never runs for this path.
        #expect(coordinator.engine.status == .running)
        #expect(coordinator.tier == .workout)
        #expect(coordinator.isTicking)
    }

    @Test("Restarting from the summary clears it and begins a fresh run")
    func restartClearsSummary() async {
        let (coordinator, store, workout, _, _, _, _) = makeCoordinator()
        var short = store.selected
        short.prepareSeconds = 0
        short.workSeconds = 5
        short.restSeconds = 0
        short.rounds = 1
        store.update(short)

        coordinator.begin()
        await settle(coordinator)
        finishRun(coordinator)
        #expect(coordinator.summary != nil)

        coordinator.restart()
        await settle(coordinator)

        #expect(coordinator.summary == nil)
        #expect(coordinator.engine.status == .running)
        #expect(workout.endCount >= 1)
    }

    @Test("Each interval becomes its own activity in the saved Health workout")
    func segmentsTheHealthWorkout() async {
        let (coordinator, store, workout, _, _, _, _) = makeCoordinator()
        workout.startResult = true
        var short = store.selected
        short.prepareSeconds = 0
        short.workSeconds = 5
        short.restSeconds = 5
        short.rounds = 2
        store.update(short)

        coordinator.begin()
        await settle(coordinator)

        // Walk the clock across every boundary.
        let engine = coordinator.engine
        let start = Date()
        for second in 0...Int(engine.plan.totalDuration) {
            engine.now = { start.addingTimeInterval(TimeInterval(second)) }
            coordinator.advance()
        }
        await settle(coordinator)

        // work 1 | rest 1 | work 2 — one activity per phase, so Fitness shows real splits
        // instead of one undifferentiated block.
        #expect(workout.activities.map(\.kind) == [.work, .rest, .work])
        #expect(workout.activities.map(\.round) == [1, 1, 2])
    }

    @Test("The warmup and cooldown become activities of their own, outside the rounds")
    func segmentsTheHealthWorkoutWithBookends() async {
        // Pro: without it, begin() runs the preset with its bookends zeroed.
        let (coordinator, store, workout, _, _, _, _) = makeCoordinator(pro: FakePro(isPro: true))
        workout.startResult = true
        var short = store.selected
        short.prepareSeconds = 0
        short.warmupSeconds = 5
        short.workSeconds = 5
        short.restSeconds = 5
        short.rounds = 2
        short.cooldownSeconds = 5
        store.update(short)

        coordinator.begin()
        await settle(coordinator)

        let engine = coordinator.engine
        let start = Date()
        for second in 0...Int(engine.plan.totalDuration) {
            engine.now = { start.addingTimeInterval(TimeInterval(second)) }
            coordinator.advance()
        }
        await settle(coordinator)

        #expect(workout.activities.map(\.kind) == [.warmup, .work, .rest, .work, .cooldown])
        #expect(workout.activities.map(\.round) == [1, 1, 1, 2, 2])
        // The session tags by kind, and a bookend kind is what keeps a round off it.
        #expect(workout.activities.filter { $0.kind.isBookend }.map(\.kind) == [.warmup, .cooldown])
        #expect(coordinator.summary != nil)
    }

    @Test("No activities are begun when there is no workout session to segment")
    func noActivitiesWithoutWorkoutTier() async {
        let (coordinator, _, workout, _, _, _, _) = makeCoordinator()
        workout.isSupported = false
        workout.startResult = false

        coordinator.begin()
        await settle(coordinator)

        #expect(coordinator.tier == .extendedRuntime)
        #expect(workout.activities.isEmpty)
    }

    @Test("A completed run reports a summary and is saved rather than discarded")
    func completionSaves() async {
        let (coordinator, store, workout, _, _, _, _) = makeCoordinator()
        var short = store.selected
        short.prepareSeconds = 0
        short.workSeconds = 5
        short.restSeconds = 0
        short.rounds = 3
        store.update(short)

        coordinator.begin()
        await settle(coordinator)
        finishRun(coordinator)
        await settle(coordinator)

        #expect(coordinator.summary?.rounds == 3)
        #expect(coordinator.summary?.duration == 15)
        #expect(workout.endCount == 1)
        #expect(workout.discardCount == 0)
    }

    @Test("Pausing and then skipping the cooldown finishes the run: the finish tap, a summary, and a save")
    func pausedSkipOfLastPhaseFinishes() async throws {
        let (coordinator, store, workout, _, _, _, haptics) = makeCoordinator(pro: FakePro(isPro: true))
        var short = store.selected
        short.prepareSeconds = 0
        short.workSeconds = 5
        short.restSeconds = 0
        short.rounds = 1
        short.cooldownSeconds = 60
        store.update(short)

        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.tier == .workout)
        coordinator.skip()
        try #require(coordinator.engine.position.phase?.kind == .cooldown)
        coordinator.togglePause()
        coordinator.skip()
        await settle(coordinator)

        #expect(coordinator.engine.status == .finished)
        #expect(coordinator.summary != nil)
        #expect(haptics.played.last?.event == .finished)
        #expect(haptics.played.last?.context == BoundaryContext(lateness: 0, phaseDuration: nil))
        #expect(workout.endCount == 1)
        #expect(workout.discardCount == 0)

        // Done keeps it: a finished run is never discarded.
        coordinator.stopAndExit()
        await settle(coordinator)
        #expect(workout.discardCount == 0)
    }

    @Test("The summary's duration includes the warmup and cooldown; its rounds do not")
    func summaryIncludesBookends() async {
        let (coordinator, store, _, _, _, _, _) = makeCoordinator(pro: FakePro(isPro: true))
        var short = store.selected
        short.prepareSeconds = 0
        short.warmupSeconds = 10
        short.workSeconds = 5
        short.restSeconds = 0
        short.rounds = 3
        short.cooldownSeconds = 20
        store.update(short)

        coordinator.begin()
        await settle(coordinator)
        finishRun(coordinator)
        await settle(coordinator)

        #expect(coordinator.summary?.duration == 45)
        #expect(coordinator.summary?.rounds == 3)
    }

    @Test("The summary says Saving while the Health save is in flight, then Saved")
    func summaryTracksHealthSave() async {
        let (coordinator, _, workout, _, _, _, _) = makeCoordinator()
        let gate = Gate()
        workout.endGate = gate

        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.tier == .workout)
        finishRun(coordinator)
        await settle(coordinator)
        #expect(coordinator.summary?.health == .saving)

        gate.open()
        await settle(coordinator)
        #expect(coordinator.summary?.health == .saved)
    }

    @Test("A failed Health save is reported, not shown as saved")
    func summaryReportsFailedSave() async {
        let (coordinator, _, workout, _, _, _, _) = makeCoordinator()
        workout.endResult = false

        coordinator.begin()
        await settle(coordinator)
        finishRun(coordinator)
        await settle(coordinator)

        #expect(coordinator.summary?.health == .failed)
    }

    @Test("A run without a workout session says nothing about Health")
    func summaryWithoutWorkoutSession() async {
        let (coordinator, _, workout, _, _, _, _) = makeCoordinator()
        workout.isSupported = false
        workout.startResult = false

        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.tier == .extendedRuntime)
        finishRun(coordinator)
        await settle(coordinator)

        // Declining Health is a choice, not a failure; "Not saved" after every workout
        // would nag about it.
        #expect(coordinator.summary?.health == .notRecorded)
    }
}


@Suite("Run coordinator — races and recovery")
@MainActor
struct RunCoordinatorRaceTests {

    @Test("A restore and the foreground transition together take exactly one session")
    func restoreAndForegroundTakeOneSession() async {
        // Both land on every launch. `tier` is only set once a session has started, so
        // without an in-flight guard each would start its own, and they would compete.
        let defaults = makeTestDefaults()
        let seed = WorkoutStore(defaults: defaults)
        seed.saveActiveRun(
            RunSnapshot(workout: seed.selected, anchor: Date().addingTimeInterval(-20), pausedElapsed: nil)
        )
        let gate = Gate()
        let (coordinator, _, workout, _, _, _, _) = makeCoordinator(defaults: defaults)
        workout.startGate = gate

        #expect(coordinator.restoreIfNeeded())
        coordinator.handleForeground()
        coordinator.handleForeground()
        gate.open()
        await settle(coordinator)

        #expect(workout.startCount == 1)
        #expect(coordinator.tier == .workout)
    }

    @Test("Stopping while the session is still starting discards it instead of keeping it")
    func stopDuringSessionStartDiscards() async {
        let gate = Gate()
        let (coordinator, _, workout, _, _, _, _) = makeCoordinator()
        workout.startGate = gate

        coordinator.begin()
        await settle(coordinator)
        #expect(workout.startCount == 1)   // started, but still waiting on HealthKit

        coordinator.stopAndExit()
        gate.open()
        await settle(coordinator)

        // Taking the tier now would leave a live workout session — holding the app open and
        // showing the workout indicator — attached to a run that no longer exists.
        #expect(coordinator.tier == .none)
        #expect(workout.discardCount >= 1)
    }

    @Test("Leaving before the permission prompts resolve means the clock never starts")
    func stopDuringPermissionsNeverStarts() async {
        let gate = Gate()
        let (coordinator, _, workout, _, _, _, _) = makeCoordinator()
        workout.authorizationGate = gate

        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.engine.status == .idle)   // still on the Health sheet

        coordinator.stopAndExit()
        gate.open()
        await settle(coordinator)

        #expect(coordinator.engine.status == .idle)
        #expect(coordinator.isTicking == false)
        #expect(workout.startCount == 0)
    }

    @Test("A second begin while the first is waiting on permissions does not start early")
    func doubleBeginWaitsForPermissions() async {
        // SwiftUI can deliver onAppear twice. The second call used to sail past the prompt
        // and start the clock while the Health sheet was still up.
        let gate = Gate()
        let (coordinator, _, workout, _, _, _, _) = makeCoordinator()
        workout.authorizationGate = gate

        coordinator.begin()
        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.engine.status == .idle)

        gate.open()
        await settle(coordinator)
        #expect(coordinator.engine.status == .running)
    }

    @Test("A workout session dying while paused clears the tier instead of wedging it")
    func unexpectedEndWhilePausedClearsTier() async {
        let (coordinator, _, workout, _, _, _, _) = makeCoordinator()

        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.tier == .workout)

        coordinator.togglePause()
        workout.startResult = false
        workout.simulateUnexpectedEnd()
        await settle(coordinator)

        // Left at .workout, nothing would ever re-take a tier on resume, and the backstop
        // would stay suppressed for the rest of the run.
        #expect(coordinator.tier == .none)
    }

    @Test("Recovering with no resumable run saves the orphaned session rather than leaving it")
    func recoveryWithoutRunSavesOrphan() async {
        let (coordinator, _, workout, _, _, _, _) = makeCoordinator()
        workout.recoverableSession = true

        coordinator.recoverWorkoutSession()
        await settle(coordinator)

        #expect(coordinator.engine.status == .idle)
        #expect(workout.endCount == 1)
    }

    @Test("Recovering with a resumable run restores it and adopts the session")
    func recoveryWithRunRestores() async {
        let defaults = makeTestDefaults()
        let seed = WorkoutStore(defaults: defaults)
        seed.saveActiveRun(
            RunSnapshot(workout: seed.selected, anchor: Date().addingTimeInterval(-20), pausedElapsed: nil)
        )
        let (coordinator, _, workout, _, _, _, _) = makeCoordinator(defaults: defaults)
        workout.recoverableSession = true

        coordinator.recoverWorkoutSession()
        await settle(coordinator)

        #expect(coordinator.engine.status == .running)
        #expect(coordinator.tier == .workout)
        #expect(workout.startCount == 0)
        #expect(workout.endCount == 0)
    }

    @Test("A restored paused run does not tick")
    func restoredPausedRunDoesNotTick() async {
        let defaults = makeTestDefaults()
        let seed = WorkoutStore(defaults: defaults)
        seed.saveActiveRun(RunSnapshot(workout: seed.selected, anchor: Date(), pausedElapsed: 30))
        let (coordinator, _, _, _, _, _, _) = makeCoordinator(defaults: defaults)

        #expect(coordinator.restoreIfNeeded())
        #expect(coordinator.engine.status == .paused)
        #expect(coordinator.isTicking == false)
    }

    @Test("Declined notifications are reported, so the UI does not promise alerts")
    func declinedNotificationsAreReported() async {
        let spy = SpyScheduler()
        spy.authorizationResult = false
        let (coordinator, _, _, _, _, _, _) = makeCoordinator(scheduler: spy)

        coordinator.begin()
        await settle(coordinator)

        #expect(coordinator.canNotify == false)
    }

    @Test("Finishing cancels the backstop through the serialised chain, after any schedule")
    func finishCancelIsOrdered() async {
        let (coordinator, store, workout, _, spy, _, _) = makeCoordinator()
        workout.isSupported = false
        workout.startResult = false
        var short = store.selected
        short.prepareSeconds = 0
        short.workSeconds = 5
        short.restSeconds = 0
        short.rounds = 1
        store.update(short)

        coordinator.begin()
        await settle(coordinator)
        #expect(spy.scheduleCount == 1)

        let engine = coordinator.engine
        let end = Date().addingTimeInterval(engine.plan.totalDuration + 1)
        engine.now = { end }
        coordinator.advance()
        await settle(coordinator)

        // The cancel must come after the schedule it is cancelling, never before.
        #expect(spy.calls.last == .cancelAll)
    }
}


@Suite("Run coordinator — upgrading to a workout session")
@MainActor
struct RunCoordinatorUpgradeTests {

    /// Polls until `condition` holds or the attempts run out, since the upgrade is a
    /// detached retry rather than part of the start sequence.
    private func eventually(_ coordinator: RunCoordinator, _ condition: () -> Bool) async {
        for _ in 0..<40 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
            await coordinator.backstopSettled()
        }
    }

    @Test("Health granted a moment ago: the first run upgrades to a workout session once it takes")
    func upgradesAfterFreshGrant() async {
        // Observed on the simulator: straight after the Health sheet, starting the session
        // fails as "not authorized" and succeeds a second later. Without a retry the user's
        // very first workout is never recorded.
        let (coordinator, _, workout, runtime, spy, _, _) = makeCoordinator()
        coordinator.upgradeRetryDelays = [0.01, 0.01]
        workout.failingStarts = 1

        coordinator.begin()
        await settle(coordinator)
        await eventually(coordinator) { coordinator.tier == .workout }

        #expect(coordinator.tier == .workout)
        #expect(workout.startCount == 2)
        // The weaker tier is released, and the notification backstop with it — otherwise
        // every boundary would alert twice.
        #expect(runtime.stopCount >= 1)
        #expect(spy.calls.last == .cancelAll)
        // The interval already under way gets its Health segment.
        #expect(workout.activities.isEmpty == false)
    }

    @Test("Health declined: every retry fails and the run stays on the fallback tier")
    func declinedStaysOnFallback() async {
        let (coordinator, _, workout, _, spy, _, _) = makeCoordinator()
        coordinator.upgradeRetryDelays = [0.01, 0.01]
        workout.startResult = false

        coordinator.begin()
        await settle(coordinator)
        try? await Task.sleep(for: .milliseconds(100))
        await settle(coordinator)

        #expect(coordinator.tier == .extendedRuntime)
        // The initial attempt plus one per retry, and no more.
        #expect(workout.startCount == 3)
        #expect(spy.scheduleCount >= 1)
    }

    @Test("A run that ends before the retry does not get a session attached afterwards")
    func endedRunIsNotUpgraded() async {
        let (coordinator, _, workout, _, _, _, _) = makeCoordinator()
        coordinator.upgradeRetryDelays = [0.05]
        workout.failingStarts = 1

        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.tier == .extendedRuntime)

        coordinator.stopAndExit()
        try? await Task.sleep(for: .milliseconds(150))
        await settle(coordinator)

        #expect(coordinator.tier == .none)
        // Cancelled: no retry ran, so nothing could start a session for the dead run.
        #expect(workout.startCount == 1)
    }
}


@Suite("Run coordinator — boundary haptics")
@MainActor
struct RunCoordinatorHapticsTests {

    /// prepare 10 | work 60 | rest 30 | work 60: long phases, so a jump of the clock lands
    /// well inside the phase it names.
    private func useLongWorkout(_ store: WorkoutStore) {
        var long = store.selected
        long.prepareSeconds = 10
        long.workSeconds = 60
        long.restSeconds = 30
        long.rounds = 2
        store.update(long)
    }

    /// Begins a run and moves the engine's clock to `elapsed` seconds after its start.
    private func begin(_ coordinator: RunCoordinator, at elapsed: TimeInterval = 0) async throws {
        coordinator.begin()
        await settle(coordinator)
        let anchor = try #require(coordinator.engine.anchor)
        coordinator.engine.now = { anchor.addingTimeInterval(elapsed) }
    }

    @Test("The opening phase is announced on time, with its length")
    func startIsOnTime() async throws {
        let (coordinator, store, _, _, _, _, haptics) = makeCoordinator()
        useLongWorkout(store)

        try await begin(coordinator)

        let first = try #require(haptics.played.first)
        #expect(first.event == .phaseBegan(coordinator.engine.plan.phases[0]))
        #expect(first.context == BoundaryContext(lateness: 0, phaseDuration: 10))
    }

    @Test("A boundary the ticker catches half a second late says so, with the phase's length")
    func tickLatenessIsReported() async throws {
        let (coordinator, store, _, _, _, _, haptics) = makeCoordinator()
        useLongWorkout(store)

        try await begin(coordinator, at: 10.5)
        coordinator.advance()

        let last = try #require(haptics.played.last)
        #expect(last.event == .phaseBegan(coordinator.engine.plan.phases[1]))
        #expect(last.context.lateness >= 0.49 && last.context.lateness < 0.6)
        #expect(last.context.phaseDuration == 60)
        #expect(Haptics.plan(for: last.event, strength: .strongest, context: last.context).steps.count == 3)
    }

    @Test("A skip is on time by definition")
    func skipIsOnTime() async throws {
        let (coordinator, store, _, _, _, _, haptics) = makeCoordinator()
        useLongWorkout(store)

        try await begin(coordinator, at: 3)
        coordinator.skip()

        let last = try #require(haptics.played.last)
        #expect(last.event == .phaseBegan(coordinator.engine.plan.phases[1]))
        #expect(last.context == BoundaryContext(lateness: 0, phaseDuration: 60))
    }

    @Test("Coming back after 30 s away is a catch-up, so the boundary taps once")
    func foregroundJumpIsLate() async throws {
        let (coordinator, store, _, _, _, _, haptics) = makeCoordinator()
        useLongWorkout(store)

        try await begin(coordinator, at: 40)
        coordinator.handleForeground()

        let last = try #require(haptics.played.last)
        #expect(last.event == .phaseBegan(coordinator.engine.plan.phases[1]))
        #expect(last.context.lateness >= 1)
        #expect(last.context.phaseDuration == 60)
        #expect(Haptics.plan(for: last.event, strength: .strongest, context: last.context).steps.count == 1)
    }

    @Test("A finish noticed late says so, and has no phase to fit inside")
    func lateFinish() async throws {
        let (coordinator, store, _, _, _, _, haptics) = makeCoordinator()
        useLongWorkout(store)
        let total = IntervalPlan(workout: store.selected).totalDuration

        try await begin(coordinator, at: total + 30)
        coordinator.advance()

        let last = try #require(haptics.played.last)
        #expect(last.event == .finished)
        #expect(last.context.lateness >= 29)
        #expect(last.context.phaseDuration == nil)
    }

    @Test("A countdown tick goes out as immediate")
    func countdownIsImmediate() async throws {
        let (coordinator, store, _, _, _, _, haptics) = makeCoordinator()
        useLongWorkout(store)

        try await begin(coordinator, at: 8)
        coordinator.advance()

        let last = try #require(haptics.played.last)
        #expect(last.event == .countdown(secondsRemaining: 2))
        #expect(last.context == .immediate)
    }

    @Test("A preview plays on the run's own player, so the next boundary replaces it")
    func previewSharesTheRunsPlayer() async throws {
        let (coordinator, store, _, _, _, _, haptics) = makeCoordinator()
        useLongWorkout(store)

        try await begin(coordinator, at: 3)
        coordinator.previewTaps(.strongest)
        #expect(haptics.calls.last == .preview(.strongest))

        coordinator.skip()
        #expect(haptics.calls.last == .play(
            .phaseBegan(coordinator.engine.plan.phases[1]),
            BoundaryContext(lateness: 0, phaseDuration: 60)
        ))
    }

    @Test("Pausing silences a burst in flight; resuming does not")
    func pauseCancels() async {
        let (coordinator, _, _, _, _, _, haptics) = makeCoordinator()

        coordinator.begin()
        await settle(coordinator)
        coordinator.togglePause()
        #expect(haptics.cancelCount == 1)

        coordinator.togglePause()
        #expect(haptics.cancelCount == 1)
    }

    @Test("Stopping silences a burst in flight")
    func stopCancels() async {
        let (coordinator, _, _, _, _, _, haptics) = makeCoordinator()

        coordinator.begin()
        await settle(coordinator)
        coordinator.stopAndExit()

        #expect(haptics.cancelCount == 1)
    }

    @Test("Repeat silences the finish burst before the new run's first tap")
    func repeatCancelsBeforeStarting() async throws {
        let (coordinator, store, _, _, _, _, haptics) = makeCoordinator()
        useLongWorkout(store)

        coordinator.begin()
        await settle(coordinator)
        finishRun(coordinator)
        coordinator.restart()
        await settle(coordinator)

        let finish = try #require(haptics.calls.lastIndex { if case .play(.finished, _) = $0 { true } else { false } })
        let cancel = try #require(haptics.calls.lastIndex(of: .cancel))
        #expect(finish < cancel)
        #expect(haptics.calls.last == .play(
            .phaseBegan(coordinator.engine.plan.phases[0]),
            BoundaryContext(lateness: 0, phaseDuration: 10)
        ))
    }

    @Test("Finishing leaves the finish burst to play out")
    func finishDoesNotCancel() async {
        let (coordinator, store, _, _, _, _, haptics) = makeCoordinator()
        useLongWorkout(store)

        coordinator.begin()
        await settle(coordinator)
        finishRun(coordinator)
        await settle(coordinator)

        #expect(coordinator.summary != nil)
        #expect(haptics.played.last?.event == .finished)
        #expect(haptics.cancelCount == 0, "Nothing cancels the finish burst, before or after it")
    }

    @Test("A pause that lands after the end finishes the run, on time")
    func pausePastTheEndFinishesOnTime() async throws {
        let (coordinator, store, _, _, _, _, haptics) = makeCoordinator()
        useLongWorkout(store)
        let total = IntervalPlan(workout: store.selected).totalDuration

        try await begin(coordinator, at: total + 5)
        coordinator.togglePause()

        #expect(coordinator.summary != nil)
        #expect(haptics.calls.last == .play(.finished, BoundaryContext(lateness: 0, phaseDuration: nil)))
    }
}


@Suite("Run coordinator — Pro gating")
@MainActor
struct RunCoordinatorProGatingTests {

    /// A preset with a 2:00 warmup and a 1:00 cooldown.
    private func withBookends(_ workout: IntervalWorkout) -> IntervalWorkout {
        var copy = workout
        copy.warmupSeconds = 120
        copy.cooldownSeconds = 60
        return copy
    }

    @Test("Without Pro the run and its snapshot drop the warmup and cooldown; the preset keeps them")
    func freeRunsWithoutBookends() async throws {
        let (coordinator, store, _, _, _, _, _) = makeCoordinator(pro: FakePro(isPro: false))
        store.update(withBookends(store.selected))

        coordinator.begin()
        await settle(coordinator)

        #expect(coordinator.engine.status == .running)
        #expect(coordinator.engine.plan.phases.contains { $0.kind.isBookend } == false)
        let snapshot = try #require(store.loadActiveRun())
        #expect(snapshot.workout.warmupSeconds == 0)
        #expect(snapshot.workout.cooldownSeconds == 0)
        #expect(store.selected.warmupSeconds == 120)
        #expect(store.selected.cooldownSeconds == 60)
    }

    @Test("With Pro the run and its snapshot carry the warmup and cooldown")
    func proRunsBookends() async throws {
        let (coordinator, store, _, _, _, _, _) = makeCoordinator(pro: FakePro(isPro: true))
        store.update(withBookends(store.selected))

        coordinator.begin()
        await settle(coordinator)

        let kinds = coordinator.engine.plan.phases.map(\.kind)
        #expect(kinds.filter(\.isBookend) == [.warmup, .cooldown])
        #expect(kinds.last == .cooldown)
        let snapshot = try #require(store.loadActiveRun())
        #expect(snapshot.workout.warmupSeconds == 120)
        #expect(snapshot.workout.cooldownSeconds == 60)
    }

    @Test("The idle plan already matches what Start will run")
    func idlePlanIsEffective() {
        let defaults = makeTestDefaults()
        let seed = WorkoutStore(defaults: defaults)
        seed.update(withBookends(seed.selected))

        let (freeRun, _, _, _, _, _, _) = makeCoordinator(defaults: defaults, pro: FakePro(isPro: false))
        let (proRun, _, _, _, _, _, _) = makeCoordinator(defaults: defaults, pro: FakePro(isPro: true))

        #expect(freeRun.engine.plan.workout.hasBookends == false)
        #expect(proRun.engine.plan.workout.warmupSeconds == 120)
    }

    @Test("Losing Pro mid-run leaves the plan under way as it was")
    func revocationMidRunKeepsPlan() async {
        let pro = FakePro(isPro: true)
        let (coordinator, store, _, _, _, _, _) = makeCoordinator(pro: pro)
        store.update(withBookends(store.selected))

        coordinator.begin()
        await settle(coordinator)
        let plan = coordinator.engine.plan
        pro.isPro = false
        coordinator.advance()
        coordinator.skip()
        coordinator.togglePause()
        coordinator.togglePause()
        coordinator.handleForeground()
        await settle(coordinator)

        #expect(coordinator.engine.plan == plan)
        #expect(store.loadActiveRun()?.workout.warmupSeconds == 120)
    }

    @Test("A restored run keeps the bookends it started with, whatever Pro says now")
    func restoreKeepsBookends() {
        let defaults = makeTestDefaults()
        let seed = WorkoutStore(defaults: defaults)
        seed.saveActiveRun(RunSnapshot(
            workout: withBookends(seed.selected), anchor: Date().addingTimeInterval(-20), pausedElapsed: nil
        ))
        let (coordinator, _, _, _, _, _, _) = makeCoordinator(defaults: defaults, pro: FakePro(isPro: false))

        #expect(coordinator.restoreIfNeeded())
        #expect(coordinator.engine.plan.workout.warmupSeconds == 120)
        #expect(coordinator.engine.position.phase?.kind == .warmup)
    }
}
