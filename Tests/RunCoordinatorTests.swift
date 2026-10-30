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
        // Nothing advances while paused, so ticking would be pure battery cost.
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

    @Test("A session that starts while a skipped-to phase waits for Resume leaves that phase's activity to its announcement")
    func sessionDuringPausedSkipOpensActivityOnce() async {
        let time = VirtualTime()
        let gate = Gate()
        let (coordinator, store, workout, _, _, _, haptics) = makeCoordinator()
        // work 5 | rest 5 | work 5
        var short = store.selected
        short.prepareSeconds = 0
        short.workSeconds = 5
        short.restSeconds = 5
        short.rounds = 2
        store.update(short)
        workout.startGate = gate
        coordinator.runOnVirtualTime(time)

        coordinator.begin()
        await settle(coordinator)
        #expect(workout.startCount == 1, "Started, but still waiting on HealthKit")
        time.advance(by: .milliseconds(300))
        coordinator.togglePause()
        coordinator.skip()
        gate.open()
        await settle(coordinator)
        #expect(coordinator.tier == .workout)
        #expect(workout.activities.isEmpty, "Left to the rest's announcement")

        coordinator.togglePause()
        _ = await coordinator.tick(on: time) { haptics.played.count == 2 }
        #expect(haptics.played.last?.event == .phaseBegan(coordinator.engine.plan.phases[1]))
        #expect(workout.activities.map(\.kind) == [.rest], "Opened once")
        coordinator.stopAndExit()
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

    /// The retries sleep on this, so a test moves them on by exactly their delays.
    let time = VirtualTime()

    private func makeRetrying() -> (RunCoordinator, FakeWorkoutSession, FakeRuntimeSession, SpyScheduler) {
        let (coordinator, _, workout, runtime, spy, _, _) = makeCoordinator()
        coordinator.upgradeSleep = { [time] in try await time.sleep(for: .seconds($0)) }
        return (coordinator, workout, runtime, spy)
    }

    /// Moves the clock on to each retry in turn, every one of them failing.
    private func runOutTheRetries(_ coordinator: RunCoordinator, _ workout: FakeWorkoutSession) async {
        for delay in coordinator.upgradeRetryDelays {
            let starts = workout.startCount
            #expect(await waitUntil { time.sleeping == 1 }, "The next retry waits \(delay) s")
            time.advance(by: .seconds(delay))
            #expect(await waitUntil { workout.startCount == starts + 1 })
        }
    }

    /// Lets the retries that woke return and act, so an absence can be asserted.
    private func settleRetries(_ coordinator: RunCoordinator, woken count: Int) async {
        #expect(await waitUntil { time.woken >= count })
        try? await Task.sleep(for: .milliseconds(50))
        await settle(coordinator)
    }

    @Test("Each retry waits exactly its delay, 1, 3, 10 then 30 seconds, on the clock it is given")
    func upgradeRetriesRunOnVirtualTime() async {
        let (coordinator, workout, _, _) = makeRetrying()
        workout.startResult = false

        coordinator.begin()
        await settle(coordinator)
        #expect(workout.startCount == 1)
        for (index, delay) in [1, 3, 10, 30].enumerated() {
            #expect(await waitUntil { time.sleeping == 1 })
            #expect(time.requested.last == .seconds(delay))
            time.advance(by: .seconds(delay) - .milliseconds(1))
            await settle(coordinator)
            #expect(workout.startCount == index + 1, "Not a millisecond early")
            time.advance(by: .milliseconds(1))
            #expect(await waitUntil { workout.startCount == index + 2 }, "On the dot")
        }
        #expect(time.requested == [.seconds(1), .seconds(3), .seconds(10), .seconds(30)])
    }

    @Test("Health granted a moment ago: the first run upgrades to a workout session once it takes")
    func upgradesAfterFreshGrant() async {
        // Observed on the simulator: straight after the Health sheet, starting the session
        // fails as "not authorized" and succeeds a second later. Without a retry the user's
        // very first workout is never recorded.
        let (coordinator, workout, runtime, spy) = makeRetrying()
        workout.failingStarts = 1

        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.tier == .extendedRuntime)
        #expect(await waitUntil { time.sleeping == 1 })
        time.advance(by: .seconds(1))
        #expect(await waitUntil { coordinator.tier == .workout })
        await settle(coordinator)

        #expect(workout.startCount == 2)
        // The weaker tier is released, and the notification backstop with it — otherwise
        // every boundary would alert twice.
        #expect(runtime.stopCount >= 1)
        #expect(spy.calls.last == .cancelAll)
        // The interval already under way gets its Health segment.
        #expect(workout.activities.isEmpty == false)
        #expect(time.sleeping == 0, "Taken: nothing left to retry")
    }

    @Test("Health declined: every retry fails and the run stays on the fallback tier")
    func declinedStaysOnFallback() async {
        let (coordinator, workout, _, spy) = makeRetrying()
        workout.startResult = false

        coordinator.begin()
        await settle(coordinator)
        await runOutTheRetries(coordinator, workout)

        #expect(coordinator.tier == .extendedRuntime)
        // The initial attempt plus one per retry, and no more.
        #expect(workout.startCount == 5)
        #expect(time.sleeping == 0)
        #expect(spy.scheduleCount >= 1)
    }

    /// Health declined at the first Start, then allowed in Settings: the run must take its
    /// session when the user comes back, or it stays silent outside the app to the end.
    @Test("Back in the app after the retries ran out, a fallen-back run tries for a session again")
    func foregroundRetriesTheSession() async {
        let (coordinator, workout, _, spy) = makeRetrying()
        workout.startResult = false

        coordinator.begin()
        await settle(coordinator)
        await runOutTheRetries(coordinator, workout)
        #expect(coordinator.tier == .extendedRuntime)
        #expect(coordinator.isAcquiringTier == false)
        #expect(workout.startCount == 5)

        workout.startResult = true
        coordinator.handleForeground()
        #expect(await waitUntil { time.sleeping == 1 })
        time.advance(by: .seconds(1))
        #expect(await waitUntil { coordinator.tier == .workout })
        await settle(coordinator)

        #expect(workout.startCount == 6)
        #expect(spy.calls.last == .cancelAll, "A session plays the cues itself, so the backstop goes")
    }

    @Test("Coming back to the app tries again at once instead of waiting out a long pause")
    func foregroundRestartsAWaitingRetry() async {
        let (coordinator, workout, _, _) = makeRetrying()
        workout.startResult = false

        coordinator.begin()
        await settle(coordinator)
        #expect(await waitUntil { time.sleeping == 1 })
        time.advance(by: .seconds(1))
        // The first attempt and the one-second retry; the next is three seconds off.
        #expect(await waitUntil { workout.startCount == 2 && time.sleeping == 1 })
        #expect(time.requested.last == .seconds(3))

        workout.startResult = true
        coordinator.handleForeground()
        // A fresh one-second retry, beside the cancelled one still asleep.
        #expect(await waitUntil { time.sleeping == 2 })
        time.advance(by: .seconds(1))
        #expect(await waitUntil { coordinator.tier == .workout })
        #expect(workout.startCount == 3, "Restarted from the one-second retry, not the three-second one")

        // The cancelled retry wakes when its time comes, and tries nothing.
        time.advance(by: .seconds(2))
        await settleRetries(coordinator, woken: 3)
        #expect(workout.startCount == 3)
    }

    @Test("An upgrade that lands while a skipped-to phase waits for Resume leaves that phase's activity to its announcement")
    func upgradeDuringPausedSkipOpensActivityOnce() async {
        // The run's clock and ticker on one clock, the retries on another, so the retry can
        // come first.
        let ticks = VirtualTime()
        let (coordinator, store, workout, _, _, _, haptics) = makeCoordinator()
        // work 5 | rest 5 | work 5
        var short = store.selected
        short.prepareSeconds = 0
        short.workSeconds = 5
        short.restSeconds = 5
        short.rounds = 2
        store.update(short)
        coordinator.upgradeSleep = { [time] in try await time.sleep(for: .seconds($0)) }
        coordinator.runOnVirtualTime(ticks)
        workout.failingStarts = 1

        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.tier == .extendedRuntime)
        ticks.advance(by: .milliseconds(300))
        coordinator.togglePause()
        coordinator.skip()

        #expect(await waitUntil { time.sleeping == 1 })
        time.advance(by: .seconds(1))
        #expect(await waitUntil { coordinator.tier == .workout })
        await settle(coordinator)
        #expect(workout.activities.isEmpty, "Left to the rest's announcement")

        coordinator.togglePause()
        _ = await coordinator.tick(on: ticks) { haptics.played.count == 2 }
        #expect(haptics.played.last?.event == .phaseBegan(coordinator.engine.plan.phases[1]))
        #expect(workout.activities.map(\.kind) == [.rest], "Opened once")
        coordinator.stopAndExit()
    }

    @Test("The retries reach half a minute, past the iPhone's one-time workout prompt")
    func retriesOutlastThePrompt() {
        let (coordinator, _, _, _, _, _, _) = makeCoordinator()
        #expect(coordinator.upgradeRetryDelays.reduce(0, +) >= 30)
    }

    @Test("A run that ends before the retry does not get a session attached afterwards")
    func endedRunIsNotUpgraded() async {
        let (coordinator, workout, _, _) = makeRetrying()
        workout.failingStarts = 1

        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.tier == .extendedRuntime)
        #expect(await waitUntil { time.sleeping == 1 })

        coordinator.stopAndExit()
        time.advance(by: .seconds(1))
        await settleRetries(coordinator, woken: 1)

        #expect(coordinator.tier == .none)
        // Cancelled: no retry ran, so nothing could start a session for the dead run.
        #expect(workout.startCount == 1)
    }
}


@Suite("Run coordinator — deadline ticker")
@MainActor
struct RunCoordinatorTickerTests {

    let time = VirtualTime()

    @Test("The ticker wakes 8 ms past each countdown second and boundary, not up to half a second later")
    func tickerWakesAtBoundaryNotHalfSecond() async throws {
        let (coordinator, store, _, _, _, _, haptics) = makeCoordinator()
        // work 30 | rest 10 | work 30: the rest begins at 30 s.
        var workout = store.selected
        workout.prepareSeconds = 0
        workout.workSeconds = 30
        workout.restSeconds = 10
        workout.rounds = 2
        store.update(workout)
        coordinator.runOnVirtualTime(time)

        coordinator.begin()
        await settle(coordinator)
        #expect(await waitUntil { time.sleeping == 1 })
        // Polling from there would have caught the rest at 30.3 s.
        await coordinator.pauseOffTheGrid(on: time)
        let wakes = await coordinator.tick(on: time) { time.elapsed >= 30 }

        let phases = coordinator.engine.plan.phases
        #expect(haptics.played.map(\.event) == [
            .phaseBegan(phases[0]), .countdown(secondsRemaining: 3), .countdown(secondsRemaining: 2),
            .countdown(secondsRemaining: 1), .phaseBegan(phases[1]),
        ])
        let rest = try #require(haptics.played.last)
        #expect(abs(rest.context.lateness - 0.008) < 0.000_001, "Announced at 30.008 s")
        for second in [27.0, 28, 29, 30] {
            #expect(wakes.contains { abs($0 - second - 0.008) < 0.000_001 }, "Woke at \(second + 0.008) s")
        }
        #expect(time.requested.allSatisfy { $0 <= .milliseconds(500) }, "Never asleep for more than half a second")
        coordinator.stopAndExit()
    }

    @Test("The ticker sleeps 8 ms past the moment, never less than 10 ms nor more than half a second")
    func tickDelayClamps() {
        #expect(RunCoordinator.tickDelay(0.001) == 0.01)
        #expect(RunCoordinator.tickDelay(2) == 0.5)
        #expect(RunCoordinator.tickDelay(-1) == 0.01)
        #expect(abs(RunCoordinator.tickDelay(0.3) - 0.308) < 1e-12)
        #expect(RunCoordinator.tickDelay(0.6) == 0.5)
    }

    @Test("Paused, the ticker neither sleeps nor advances; resumed, it sleeps again")
    func pausedStopsTicker() async {
        let (coordinator, _, _, _, _, _, haptics) = makeCoordinator()
        coordinator.runOnVirtualTime(time)

        coordinator.begin()
        await settle(coordinator)
        #expect(await waitUntil { time.sleeping == 1 })
        coordinator.togglePause()
        #expect(coordinator.isTicking == false)
        let played = haptics.played.count
        let asked = time.requested.count

        // Well past the next deadline. The sleep the pause cut short wakes, and stops there.
        time.advance(by: .seconds(30))
        #expect(await waitUntil { time.woken == 1 })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(time.requested.count == asked, "No further sleep")
        #expect(haptics.played.count == played, "Nothing announced")
        #expect(coordinator.engine.status == .paused)

        coordinator.togglePause()
        #expect(coordinator.isTicking)
        #expect(await waitUntil { time.sleeping == 1 })
        #expect(time.requested.count == asked + 1)
        coordinator.stopAndExit()
    }

    @Test("A ticker whose run has ended without it stops itself rather than waking every 10 ms")
    func endedRunStopsTheTicker() async {
        let (coordinator, _, _, _, _, _, haptics) = makeCoordinator()
        coordinator.runOnVirtualTime(time)

        coordinator.begin()
        await settle(coordinator)
        #expect(await waitUntil { time.sleeping == 1 })
        // Finished behind the coordinator's back, so nothing calls `stopTicking()`. The clock
        // then sits at the run's end, with no deadline left to sleep until.
        while coordinator.engine.status == .running { coordinator.engine.skipPhase() }
        #expect(coordinator.engine.status == .finished)
        let asked = time.requested.count
        let played = haptics.played.count

        time.advanceToNextWake()
        #expect(await waitUntil { !coordinator.isTicking }, "The ticker let go of itself")
        try? await Task.sleep(for: .milliseconds(50))
        #expect(time.requested.count == asked, "No further sleep")
        #expect(time.sleeping == 0)
        #expect(haptics.played.count == played, "Nothing announced")
        coordinator.stopAndExit()
    }

    @Test("A phase skipped to while paused plays on the first wake after Resume, half a second on as in 1.2")
    func skipWhilePausedPlaysAfterResume() async throws {
        let (coordinator, store, _, _, _, _, haptics) = makeCoordinator()
        // work 5 | rest 5 | work 5
        var short = store.selected
        short.prepareSeconds = 0
        short.workSeconds = 5
        short.restSeconds = 5
        short.rounds = 2
        store.update(short)
        coordinator.runOnVirtualTime(time)

        coordinator.begin()
        await settle(coordinator)
        #expect(await waitUntil { time.sleeping == 1 })
        time.advance(by: .milliseconds(300))
        coordinator.togglePause()
        coordinator.skip()
        #expect(coordinator.engine.hasPendingBoundary)
        coordinator.togglePause()
        // Beside the sleep the pause cut short, which wakes at 0.5 s and stops there.
        #expect(await waitUntil { time.sleeping == 2 })
        let rest = coordinator.engine.plan.phases[1]
        #expect(haptics.played.map(\.event) == [.phaseBegan(coordinator.engine.plan.phases[0])],
                "Nothing played at Resume itself")

        let wakes = await coordinator.tick(on: time) { haptics.played.count == 2 }
        #expect(wakes.last.map { abs($0 - 0.8) < 0.000_001 } == true, "The first wake after Resume, at 0.8 s")
        #expect(haptics.played.last?.event == .phaseBegan(rest))
        #expect(coordinator.engine.hasPendingBoundary == false)
        coordinator.stopAndExit()
    }

    @Test("A phase skipped to while paused still plays after a relaunch, on the first wake after Resume, and opens its activity once")
    func skipWhilePausedPlaysAfterARelaunch() async {
        let defaults = makeTestDefaults()
        let (coordinator, store, _, _, _, _, _) = makeCoordinator(defaults: defaults)
        // work 5 | rest 5 | work 5
        var short = store.selected
        short.prepareSeconds = 0
        short.workSeconds = 5
        short.restSeconds = 5
        short.rounds = 2
        store.update(short)
        coordinator.runOnVirtualTime(time)

        coordinator.begin()
        await settle(coordinator)
        #expect(await waitUntil { time.sleeping == 1 })
        time.advance(by: .milliseconds(300))
        coordinator.togglePause()
        coordinator.skip()

        // The app is ended and launched again; the system kept its workout session.
        let (relaunched, _, workout, _, _, _, haptics) = makeCoordinator(defaults: defaults)
        workout.recoverableSession = true
        relaunched.runOnVirtualTime(time)
        #expect(relaunched.restoreIfNeeded())
        #expect(relaunched.engine.status == .paused)
        #expect(relaunched.engine.hasPendingBoundary, "The rest still waits for Resume")

        relaunched.togglePause()
        await settle(relaunched)
        #expect(relaunched.tier == .workout)
        #expect(workout.activities.isEmpty, "Left to the rest's announcement")
        #expect(haptics.played.isEmpty, "Nothing played at Resume itself")

        // Beside the sleep the first run's pause cut short, which wakes at 0.5 s and stops.
        let wakes = await relaunched.tick(on: time) { haptics.played.count == 1 }
        let rest = relaunched.engine.plan.phases[1]
        #expect(wakes.last.map { abs($0 - 0.8) < 0.000_001 } == true, "The first wake after Resume, at 0.8 s")
        #expect(haptics.played.map(\.event) == [.phaseBegan(rest)])
        #expect(workout.activities.map(\.kind) == [.rest], "Opened once, by the announcement")
        relaunched.stopAndExit()
    }
}

/// The run's notes, as its diagnostics would get them.
@MainActor
private final class SpyDiagnostics {
    private(set) var lines: [String] = []
    func note(_ line: String) { lines.append(line) }
    /// The run's timing lines alone.
    var timing: [String] { lines.filter { $0.hasPrefix("Run timing:") } }
}

@Suite("Run coordinator — timing in the diagnostics")
@MainActor
struct RunCoordinatorTimingLineTests {

    let time = VirtualTime()
    private let notes = SpyDiagnostics()

    @Test("A finished run's diagnostics say once how late its boundaries were: each just past its moment")
    func finishWritesTheTimingLine() async {
        let (coordinator, store, _, _, _, _, _) = makeCoordinator()
        // work 5 | rest 5 | work 5
        var short = store.selected
        short.prepareSeconds = 0
        short.workSeconds = 5
        short.restSeconds = 5
        short.rounds = 2
        store.update(short)
        coordinator.diagnostics = { [notes] in notes.note($0) }
        coordinator.runOnVirtualTime(time)

        coordinator.begin()
        await settle(coordinator)
        #expect(await waitUntil { time.sleeping == 1 })
        await coordinator.pauseOffTheGrid(on: time)
        _ = await coordinator.tick(on: time) { coordinator.engine.status != .running }

        #expect(coordinator.engine.status == .finished)
        // The rest, the second work and the finish. The start is on time by construction, and
        // a countdown tick is no boundary.
        #expect(notes.timing == [
            "Run timing: 3 boundaries, median 0.01 s late, max 0.01 s; 0 over 1.0 s (one tap instead of the full pattern)",
        ])
        coordinator.stopAndExit()
        #expect(notes.timing.count == 1, "Done after the finish has nothing more to say")
    }

    @Test("Ending a run writes its timing too: a skip is on time by definition, a catch-up is late")
    func stopWritesTheTimingLine() async throws {
        let (coordinator, store, _, _, _, _, _) = makeCoordinator()
        // prepare 10 | work 60 | rest 30 | work 60
        var long = store.selected
        long.prepareSeconds = 10
        long.workSeconds = 60
        long.restSeconds = 30
        long.rounds = 2
        store.update(long)
        coordinator.diagnostics = { [notes] in notes.note($0) }
        // Asleep on a clock nothing moves, so only the test advances this run.
        coordinator.tickSleep = { [time] in try await time.sleep(for: .seconds($0)) }

        coordinator.begin()
        await settle(coordinator)
        let anchor = try #require(coordinator.engine.anchor)
        coordinator.engine.now = { anchor.addingTimeInterval(3) }
        coordinator.skip()
        // Back after a while away: the rest began at 70 s and is noticed at 72.5 s.
        let skipped = try #require(coordinator.engine.anchor)
        coordinator.engine.now = { skipped.addingTimeInterval(72.5) }
        coordinator.advance()
        coordinator.stopAndExit()

        #expect(notes.timing == [
            "Run timing: 1 boundary, median 2.50 s late, max 2.50 s; 1 over 1.0 s (one tap instead of the full pattern)",
        ])
    }

    @Test("A phase skipped to while paused waits half a second after Resume on purpose, and isn't counted late")
    func skipWhilePausedIsNotLate() async {
        let (coordinator, store, _, _, _, _, _) = makeCoordinator()
        // work 5 | rest 5 | work 5
        var short = store.selected
        short.prepareSeconds = 0
        short.workSeconds = 5
        short.restSeconds = 5
        short.rounds = 2
        store.update(short)
        coordinator.diagnostics = { [notes] in notes.note($0) }
        coordinator.runOnVirtualTime(time)

        coordinator.begin()
        await settle(coordinator)
        #expect(await waitUntil { time.sleeping == 1 })
        time.advance(by: .milliseconds(300))
        coordinator.togglePause()
        coordinator.skip()
        coordinator.togglePause()
        #expect(await waitUntil { time.sleeping == 2 })
        _ = await coordinator.tick(on: time) { coordinator.engine.status != .running }

        #expect(coordinator.engine.status == .finished)
        // The second work and the finish. The rest, announced 0.5 s after Resume, is left out;
        // counted, it would be a third boundary at 0.50 s. The skip put the clock on a whole
        // second at Resume, so from there every deadline falls on a half-second wake.
        #expect(notes.timing == [
            "Run timing: 2 boundaries, median 0.00 s late, max 0.00 s; 0 over 1.0 s (one tap instead of the full pattern)",
        ])
        coordinator.stopAndExit()
    }

    @Test("A run ended before any change has no timing to give; its other notes go the same way")
    func noBoundaryNoLine() async {
        let (coordinator, _, _, _, _, _, _) = makeCoordinator()
        coordinator.diagnostics = { [notes] in notes.note($0) }
        coordinator.tickSleep = { [time] in try await time.sleep(for: .seconds($0)) }

        coordinator.begin()
        await settle(coordinator)
        coordinator.stopAndExit()

        #expect(notes.timing.isEmpty)
        #expect(notes.lines.contains { $0.hasPrefix("Run: started") })
        #expect(notes.lines.contains { $0.hasPrefix("Run: keeps running by workout") })
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

    @Test("A boundary noticed half a second late says so, with the phase's length")
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

@Suite("Run coordinator — cues that can't sound")
@MainActor
struct RunCoordinatorCueHealthTests {
    @Test("A workout session plays its own cues, but when they can't sound, notifications mark the changes")
    func backstopWhileCuesFail() async {
        let (coordinator, _, _, _, spy, _, _) = makeCoordinator()
        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.tier == .workout)
        #expect(spy.calls.last == .cancelAll, "Under a session the app plays the cues itself")

        coordinator.cuesHealthChanged(healthy: false)
        await coordinator.backstopSettled()
        #expect(coordinator.cuesFailing)
        #expect(spy.scheduleCount >= 1, "The rest of the run is scheduled as notifications")

        coordinator.cuesHealthChanged(healthy: true)
        await coordinator.backstopSettled()
        #expect(!coordinator.cuesFailing)
        #expect(spy.calls.last == .cancelAll, "Sound is back: no double alerts")
    }

    @Test("A failure the last run ended on doesn't carry into the next")
    func resetsAtStart() async {
        let (coordinator, _, _, _, _, _, _) = makeCoordinator()
        coordinator.begin()
        await settle(coordinator)
        coordinator.cuesHealthChanged(healthy: false)
        coordinator.stopAndExit()
        await settle(coordinator)
        coordinator.begin()
        await settle(coordinator)
        #expect(!coordinator.cuesFailing)
    }
}

/// Background time a run asked for, and what was pending as it gave each back.
@MainActor
private final class SpyBackgroundWork {
    private(set) var asked: [String] = []
    /// How many alerts were pending at each give-back.
    private(set) var pendingAtEnd: [Int] = []
    private let center: FakeNotificationCenter

    init(center: FakeNotificationCenter) {
        self.center = center
    }

    func begin(_ name: String) -> @MainActor () -> Void {
        asked.append(name)
        return { [self] in pendingAtEnd.append(center.pending.count) }
    }
}

@Suite("Run coordinator — the backstop, by whether the cues can be heard")
@MainActor
struct RunCoordinatorAudibleBackstopTests {

    let time = VirtualTime()

    /// work 5 | rest 5 | work 5: changes at 5 and 10 s, the finish at 15 s.
    private func useShortWorkout(_ store: WorkoutStore) {
        var short = store.selected
        short.prepareSeconds = 0
        short.workSeconds = 5
        short.restSeconds = 5
        short.rounds = 2
        store.update(short)
    }

    /// Health declined, with no retries, so nothing changes the tier under the test.
    private func declineHealth(_ workout: FakeWorkoutSession) {
        workout.isSupported = false
        workout.startResult = false
    }

    /// A run on the real scheduler, its clock the notification center's.
    private func makeScheduledRun(
        _ center: FakeNotificationCenter, store: WorkoutStore, pro: FakePro = FakePro()
    ) -> RunCoordinator {
        let workout = FakeWorkoutSession()
        declineHealth(workout)
        let coordinator = RunCoordinator(
            store: store, pro: pro, haptics: SpyHaptics(), workout: workout, runtime: FakeRuntimeSession(),
            notifications: NotificationScheduler(center: center, now: { center.now }),
            playCue: { _ in }, reloadWidgets: {}
        )
        coordinator.engine.now = { center.now }
        // Asleep on a clock nothing moves, so only the test advances the run.
        coordinator.tickSleep = { [time] in try await time.sleep(for: .seconds($0)) }
        return coordinator
    }

    /// Begins a run made by `makeScheduledRun`, and waits for its first schedule. Its start
    /// asks the scheduler's actor for permission and the schedule runs there, and `settle`'s
    /// yields on the main actor don't wait for another one.
    private func beginScheduled(_ coordinator: RunCoordinator) async {
        coordinator.begin()
        #expect(await waitUntil { coordinator.tier == .extendedRuntime })
        await coordinator.backstopSettled()
    }

    /// Wakes the ticker to the run's end, and says which alerts came down, at which wake.
    private func disarms(_ coordinator: RunCoordinator, _ spy: SpyScheduler) async -> [(at: TimeInterval, identifier: String)] {
        var disarms: [(at: TimeInterval, identifier: String)] = []
        while coordinator.engine.status == .running {
            let seen = spy.calls.count
            guard await coordinator.nextWake(on: time) != nil else { break }
            await coordinator.backstopSettled()
            for case .disarm(let identifier) in spy.calls.dropFirst(seen) {
                disarms.append((time.elapsed, identifier))
            }
        }
        return disarms
    }

    @Test("The watch decides as 1.2 did for every tier, running or not, its cues sounding or not, and takes nothing down")
    func watchDecisionUnchangedForEveryTier() {
        // The watch leaves `awayCuesAudible` as it comes.
        let (coordinator, _, _, _, _, _, _) = makeCoordinator()
        for tier in RunCoordinator.RuntimeTier.allCases {
            for isRunning in [true, false] {
                for cuesFailing in [false, true] {
                    let decided = RunCoordinator.backstop(
                        isRunning: isRunning, tier: tier,
                        cuesAudible: coordinator.awayCuesAudible(tier) && !cuesFailing
                    )
                    // 1.2's rule, as it was written.
                    let scheduled12 = isRunning && (!tier.deliversHaptics || cuesFailing)
                    #expect(
                        decided == RunCoordinator.Backstop(isScheduled: scheduled12, disarms: false),
                        "\(tier), running \(isRunning), cues failing \(cuesFailing)"
                    )
                }
            }
        }
    }

    @Test("On the watch, without a workout session, every change keeps its alert to the end")
    func watchFallbackTakesNothingDown() async {
        let (coordinator, store, workout, _, spy, _, _) = makeCoordinator()
        useShortWorkout(store)
        declineHealth(workout)
        coordinator.runOnVirtualTime(time)

        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.tier == .extendedRuntime)
        #expect(await waitUntil { time.sleeping == 1 })
        #expect(await disarms(coordinator, spy).isEmpty)
        #expect(coordinator.engine.status == .finished)
        #expect(spy.leads == [NotificationScheduler.defaultMinimumLead])
        coordinator.stopAndExit()
    }

    @Test("iPhone, Health declined, sounds on: each change's alert comes down 2 s before it, the finish's too, once each")
    func phoneHealthDeclinedSoundsOnDisarmsEachBoundary() async {
        let (coordinator, store, workout, _, spy, _, _) = makeCoordinator()
        useShortWorkout(store)
        declineHealth(workout)
        // The iPhone's sounds, on: heard away from the app, whatever keeps the run going.
        coordinator.awayCuesAudible = { _ in true }
        coordinator.runOnVirtualTime(time)

        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.tier == .extendedRuntime)
        #expect(spy.leads == [RunCoordinator.disarmingMinimumLead], "Scheduled all the same: the app could be suspended")
        #expect(await waitUntil { time.sleeping == 1 })
        // Off the half-second grid, so each comes down at the 2-second tick rather than at a
        // wake that happens to fall 2 s before the change.
        await coordinator.pauseOffTheGrid(on: time)
        let disarms = await disarms(coordinator, spy)

        #expect(coordinator.engine.status == .finished)
        #expect(disarms.map(\.identifier) == [
            NotificationScheduler.identifier(forPhase: 1), NotificationScheduler.identifier(forPhase: 2),
            NotificationScheduler.finishIdentifier,
        ])
        for (disarm, change) in zip(disarms, [5.0, 10, 15]) {
            #expect(abs(change - disarm.at - 1.992) < 0.000_001, "\(disarm.identifier) came down at \(disarm.at) s")
        }
        #expect(spy.leads.allSatisfy { $0 == RunCoordinator.disarmingMinimumLead })
        coordinator.stopAndExit()
    }

    @Test("Repeat's run takes its alerts down too, though they have the last run's names")
    func repeatedRunTakesItsAlertsDown() async {
        let (coordinator, store, workout, _, spy, _, _) = makeCoordinator()
        useShortWorkout(store)
        declineHealth(workout)
        coordinator.awayCuesAudible = { _ in true }
        coordinator.runOnVirtualTime(time)

        coordinator.begin()
        await settle(coordinator)
        #expect(await waitUntil { time.sleeping == 1 })
        let first = await disarms(coordinator, spy).map(\.identifier)
        #expect(first.count == 3)

        coordinator.restart()
        await settle(coordinator)
        #expect(await waitUntil { time.sleeping == 1 })
        #expect(await disarms(coordinator, spy).map(\.identifier) == first)
        coordinator.stopAndExit()
    }

    @Test("iPhone with a workout session but the beeps and the voice off: notifications mark each change, none taken down")
    func phoneWorkoutTierSoundsOffSchedulesBackstop() async {
        let (coordinator, store, _, _, spy, _, _) = makeCoordinator()
        useShortWorkout(store)
        coordinator.awayCuesAudible = { _ in false }
        coordinator.runOnVirtualTime(time)

        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.tier == .workout)
        // On the watch a session's taps mark the changes; an iPhone's are felt only in front.
        #expect(spy.leads == [NotificationScheduler.defaultMinimumLead])
        #expect(await waitUntil { time.sleeping == 1 })
        #expect(await disarms(coordinator, spy).isEmpty, "Nothing will be heard, so every alert stays up")
        #expect(spy.calls.last == .cancelAll, "Gone with the finish")
        coordinator.stopAndExit()
    }

    @Test("iPhone with a workout session and sounds on: the cues mark each change, and no alerts are scheduled")
    func phoneWorkoutTierSoundsOnSchedulesNothing() async {
        let (coordinator, store, _, _, spy, _, _) = makeCoordinator()
        useShortWorkout(store)
        coordinator.awayCuesAudible = { _ in true }
        coordinator.tickSleep = { [time] in try await time.sleep(for: .seconds($0)) }

        coordinator.begin()
        await settle(coordinator)
        #expect(coordinator.tier == .workout)
        coordinator.togglePause()
        coordinator.togglePause()
        coordinator.skip()
        coordinator.handleForeground()
        await settle(coordinator)
        #expect(spy.scheduleCount == 0)
        #expect(spy.calls.allSatisfy { $0 == .cancelAll })
        coordinator.stopAndExit()
    }

    @Test("Without a workout session, cues that stop sounding leave the alerts up, and nothing is scheduled again")
    func cueHealthFlipOutsideWorkoutDoesNotReschedule() async {
        let (coordinator, store, workout, _, spy, _, _) = makeCoordinator()
        useShortWorkout(store)
        declineHealth(workout)
        coordinator.awayCuesAudible = { _ in true }
        coordinator.runOnVirtualTime(time)

        coordinator.begin()
        await settle(coordinator)
        #expect(await waitUntil { time.sleeping == 1 })
        let scheduled = spy.calls

        // The audio stops before the first change, so its alert has to go off.
        coordinator.cuesHealthChanged(healthy: false)
        await settle(coordinator)
        #expect(spy.calls == scheduled, "The alerts are up already: nothing cancelled, nothing added")
        _ = await coordinator.tick(on: time) { coordinator.engine.position.phaseIndex == 1 }
        await coordinator.backstopSettled()
        #expect(spy.disarmed.isEmpty, "No cue will mark the rest, so its alert stays up")

        // Sounding again: the next change's alert comes down before it, still with nothing
        // scheduled afresh.
        coordinator.cuesHealthChanged(healthy: true)
        _ = await coordinator.tick(on: time) { coordinator.engine.position.phaseIndex == 2 }
        await coordinator.backstopSettled()
        #expect(spy.disarmed == [NotificationScheduler.identifier(forPhase: 2)])
        #expect(spy.calls.count == scheduled.count + 1)
        coordinator.stopAndExit()
    }

    @Test("While the app takes the alerts down, every schedule leaves out a change under 2.5 s off; otherwise 1.2's half second")
    func rescheduleUsesMinimumLeadWhileDisarming() async {
        let (coordinator, store, workout, _, spy, _, _) = makeCoordinator()
        useShortWorkout(store)
        declineHealth(workout)
        coordinator.awayCuesAudible = { _ in true }
        coordinator.tickSleep = { [time] in try await time.sleep(for: .seconds($0)) }

        // The start, a skip, a resume and coming back to the front all schedule afresh.
        coordinator.begin()
        await settle(coordinator)
        coordinator.skip()
        coordinator.togglePause()
        coordinator.togglePause()
        coordinator.handleForeground()
        await settle(coordinator)
        #expect(spy.leads == Array(repeating: RunCoordinator.disarmingMinimumLead, count: 4))

        // Cues that can't sound, and then none on at all: nothing is taken down, so the lead
        // goes back to 1.2's.
        coordinator.cuesHealthChanged(healthy: false)
        coordinator.handleForeground()
        await settle(coordinator)
        coordinator.cuesHealthChanged(healthy: true)
        coordinator.awayCuesAudible = { _ in false }
        coordinator.handleForeground()
        await settle(coordinator)
        #expect(spy.leads.dropFirst(4) == [NotificationScheduler.defaultMinimumLead, NotificationScheduler.defaultMinimumLead])
        coordinator.stopAndExit()
    }

    @Test("A schedule straight after an alert came down doesn't put it back")
    func rescheduleKeepsATakenDownAlertDown() async {
        let center = FakeNotificationCenter(now: Date(timeIntervalSinceReferenceDate: 700_000))
        let store = WorkoutStore(defaults: makeTestDefaults())
        useShortWorkout(store)
        let coordinator = makeScheduledRun(center, store: store)
        coordinator.awayCuesAudible = { _ in true }
        let rest = NotificationScheduler.identifier(forPhase: 1)

        await beginScheduled(coordinator)
        #expect(center.pending.map(\.identifier).contains(rest))
        // 1.8 s before the rest, the app takes its alert down: its cue will mark it.
        center.advance(by: 3.2)
        coordinator.advance()
        await settle(coordinator)
        #expect(!center.pending.map(\.identifier).contains(rest))

        // Back in front, which schedules afresh. With 1.2's lead the rest's alert came back up.
        coordinator.handleForeground()
        await settle(coordinator)
        #expect(center.pending.map(\.identifier) == [
            NotificationScheduler.identifier(forPhase: 2), NotificationScheduler.finishIdentifier,
        ])
        coordinator.stopAndExit()
    }

    @Test("An alert due to come down while a schedule is still adding it comes down once that schedule is in")
    func disarmWaitsForTheScheduleInFlight() async {
        let center = FakeNotificationCenter(now: Date(timeIntervalSinceReferenceDate: 750_000))
        let store = WorkoutStore(defaults: makeTestDefaults())
        useShortWorkout(store)
        let coordinator = makeScheduledRun(center, store: store)
        coordinator.awayCuesAudible = { _ in true }
        let rest = NotificationScheduler.identifier(forPhase: 1)

        await beginScheduled(coordinator)
        #expect(center.added.count == 3)
        // 2.6 s before the rest, back in front: a schedule afresh, which still names the rest,
        // and whose add of it is held on its way to the server.
        let inFlight = center.holdAdd(4, landed: false)
        center.advance(by: 2.4)
        coordinator.handleForeground()
        await inFlight.reached()
        #expect(center.added.last?.identifier == rest)

        // At the 2-second tick the rest's alert is due to come down. A disarm that didn't wait
        // for the schedule would find nothing pending, and the add would then put it up.
        center.advance(by: 0.608)
        coordinator.advance()
        let removals = center.removed.count
        try? await Task.sleep(for: .milliseconds(100))
        #expect(center.removed.count == removals, "Nothing comes down while the schedule adds")

        inFlight.release()
        await settle(coordinator)
        #expect(center.removed.last == [rest])
        #expect(center.pending.map(\.identifier) == [
            NotificationScheduler.identifier(forPhase: 2), NotificationScheduler.finishIdentifier,
        ])
        coordinator.stopAndExit()
    }

    @Test("A long workout's alerts are topped up as they run low, so every change has one, to the finish", arguments: [true, false])
    func topUpAfterPhaseBeganWhenWindowLow(inFront: Bool) async throws {
        let center = FakeNotificationCenter(now: Date(timeIntervalSinceReferenceDate: 800_000))
        let store = WorkoutStore(defaults: makeTestDefaults())
        // The longest workout the app allows: 200 phases, so 199 changes and the finish, where
        // one schedule holds 59 changes and the finish.
        var longest = store.selected
        longest.prepareSeconds = 10
        longest.warmupSeconds = 60
        longest.workSeconds = 5
        longest.restSeconds = 5
        longest.rounds = 99
        longest.cooldownSeconds = 60
        store.update(longest)
        let coordinator = makeScheduledRun(center, store: store, pro: FakePro(isPro: true))
        let work = SpyBackgroundWork(center: center)
        coordinator.isAppActive = { inFront }
        coordinator.beginBackgroundWork = { work.begin($0) }

        await beginScheduled(coordinator)
        let plan = coordinator.engine.plan
        #expect(plan.phases.count == 200)
        let anchor = try #require(coordinator.engine.anchor)
        for (index, phase) in plan.phases.enumerated().dropFirst() {
            let moment = anchor.addingTimeInterval(phase.start)
            let alert = center.pending.first { $0.identifier == NotificationScheduler.identifier(forPhase: index) }
            #expect(alert.map { abs($0.fireDate.timeIntervalSince(moment)) < 0.001 } == true, "Change \(index) has its alert")
            center.advance(by: moment.timeIntervalSince(center.now) + 0.008)
            coordinator.advance()
            await settle(coordinator)
        }
        #expect(center.pending.contains { $0.identifier == NotificationScheduler.finishIdentifier })
        // The start's schedule, and a top-up as each lot ran low: at the 50th change, the 100th
        // and the 150th.
        #expect(center.added.filter { $0.identifier == NotificationScheduler.finishIdentifier }.count == 4)
        if inFront {
            #expect(work.asked.isEmpty, "In front, there's no background time to ask for")
        } else {
            #expect(work.asked.count == 3)
            #expect(work.pendingAtEnd == [60, 60, 50], "Given back once each top-up was in")
        }
        coordinator.stopAndExit()
    }
}
