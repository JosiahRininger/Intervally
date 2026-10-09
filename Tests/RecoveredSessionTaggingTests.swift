//
//  RecoveredSessionTaggingTests.swift
//  IntervallyTests
//

import Foundation
import Testing
@testable import Intervally

/// Records which workout each adoption was for, as the real controller tags with it.
@MainActor
private final class RecoveringWorkoutSession: WorkoutSessioning {
    var isSupported = true
    var isRunning = false
    var heartRate: Double?
    var onUnexpectedEnd: (() -> Void)?
    var recoverableSession = false

    /// The workout each adoption that knew its run was for.
    private(set) var adoptedFor: [IntervalWorkout] = []
    private(set) var plainAdoptions = 0
    private(set) var tagged: [IntervalWorkout] = []

    func requestAuthorization() async -> Bool { true }

    func adoptRecoveredSession() async -> Bool {
        plainAdoptions += 1
        return adopt()
    }

    func adoptRecoveredSession(for workout: IntervalWorkout) async -> Bool {
        let adopted = adopt()
        if adopted { adoptedFor.append(workout) }
        return adopted
    }

    private func adopt() -> Bool {
        guard recoverableSession else { return false }
        recoverableSession = false
        isRunning = true
        return true
    }

    func start(at date: Date) async -> Bool { isRunning = true; return true }

    func start(at date: Date, for workout: IntervalWorkout) async -> Bool {
        tagged.append(workout)
        isRunning = true
        return true
    }

    func beginActivity(for phase: IntervalPhase, at date: Date) {}
    func pause() {}
    func resume() {}
    func end(at date: Date) async -> Bool { isRunning = false; return true }
    func discard() { isRunning = false }
}

/// A session recovered after a termination may never have been tagged: the tag is written
/// just after collection begins, without holding up the start. Untagged, the saved workout
/// is missing from History altogether.
@Suite("Run coordinator — tagging a recovered session")
@MainActor
struct RecoveredSessionTaggingTests {

    private func makeCoordinator(_ session: RecoveringWorkoutSession, defaults: UserDefaults) -> RunCoordinator {
        RunCoordinator(
            store: WorkoutStore(defaults: defaults), pro: FakePro(), haptics: SpyHaptics(), workout: session,
            runtime: FakeRuntimeSession(), notifications: SpyScheduler(), playCue: { _ in }, reloadWidgets: {}
        )
    }

    private func settle(_ coordinator: RunCoordinator) async {
        for _ in 0..<6 {
            for _ in 0..<8 { await Task.yield() }
            await coordinator.backstopSettled()
        }
    }

    @Test("A restored run adopts its session for its own snapshot's workout, so a missing tag is written")
    func restoreAdoptsForTheRunsWorkout() async {
        let defaults = makeTestDefaults()
        let running = IntervalWorkout(name: "Was Running", workSeconds: 40, rounds: 12)
        WorkoutStore(defaults: defaults)
            .saveActiveRun(RunSnapshot(workout: running, anchor: Date().addingTimeInterval(-20), pausedElapsed: nil))
        let session = RecoveringWorkoutSession()
        session.recoverableSession = true
        let coordinator = makeCoordinator(session, defaults: defaults)

        #expect(coordinator.restoreIfNeeded())
        await settle(coordinator)

        #expect(coordinator.tier == .workout)
        #expect(session.adoptedFor.map(\.id) == [running.id])
        #expect(session.adoptedFor.first?.name == "Was Running")
        #expect(session.tagged.isEmpty, "Adopted, not started again")
    }

    /// A leftover session from a run that can't be resumed is saved and ended. Which preset
    /// it ran is unknown, so it must not take the new run's tag.
    @Test("A leftover session closed before a new run is never tagged as the new run")
    func leftoverSessionNotTaggedAsNewRun() async {
        let session = RecoveringWorkoutSession()
        session.recoverableSession = true
        let coordinator = makeCoordinator(session, defaults: makeTestDefaults())

        coordinator.begin()
        await settle(coordinator)

        #expect(session.plainAdoptions == 1)
        #expect(session.adoptedFor.isEmpty)
        #expect(session.tagged.count == 1, "The new run's own session is tagged")
    }

    @Test("A session that knows nothing of tagging still adopts, through the plain adopt")
    func defaultForwardsToPlainAdopt() async {
        let fake = FakeWorkoutSession()
        fake.recoverableSession = true
        let session: any WorkoutSessioning = fake
        #expect(await session.adoptRecoveredSession(for: WorkoutStore.starterWorkouts[0]))
        #expect(fake.recoveryAttempts == 1)
    }

    @Test("A workout needs its tag until it carries the preset ID History finds it by")
    func needsTag() {
        let workout = WorkoutStore.starterWorkouts[1]
        #expect(WorkoutSessionController.needsTag([:]))
        #expect(WorkoutSessionController.needsTag([HealthMetadata.presetName: "Tabata", HealthMetadata.plannedRounds: 8]))
        #expect(WorkoutSessionController.needsTag(WorkoutSessionController.workoutMetadata(for: workout)) == false)
    }
}
