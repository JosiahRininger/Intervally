//
//  WorkoutMetadataTests.swift
//  IntervallyTests
//

import Foundation
import Testing
@testable import Intervally

/// What the saved Health workout is tagged with, which is all the iPhone's History has to go
/// on: the preset that ran, its name then, and the rounds it was planned for.
@Suite("Health workout metadata")
struct WorkoutMetadataTests {

    @Test("A workout is tagged with its preset's ID, name and planned rounds")
    func tags() {
        let workout = IntervalWorkout(name: "Hill Repeats", workSeconds: 60, restSeconds: 90, rounds: 6)
        let metadata = WorkoutSessionController.workoutMetadata(for: workout)
        #expect(metadata[HealthMetadata.presetID] as? String == workout.id.uuidString)
        #expect(metadata[HealthMetadata.presetName] as? String == "Hill Repeats")
        #expect(metadata[HealthMetadata.plannedRounds] as? Int == 6)
        #expect(metadata.count == 3)
    }

    @Test("Planned rounds are the rounds that run, clamped as the plan clamps them")
    func plannedRoundsAreClamped() {
        let metadata = WorkoutSessionController.workoutMetadata(for: IntervalWorkout(rounds: 500))
        #expect(metadata[HealthMetadata.plannedRounds] as? Int == IntervalWorkout.roundsRange.upperBound)
        #expect(IntervalPlan(workout: IntervalWorkout(rounds: 500)).totalRounds == IntervalWorkout.roundsRange.upperBound)
    }

    @Test("A blank name is left out rather than written empty", arguments: ["", "   ", "\n"])
    func blankNameLeftOut(name: String) {
        let metadata = WorkoutSessionController.workoutMetadata(for: IntervalWorkout(name: name))
        #expect(metadata[HealthMetadata.presetName] == nil)
        #expect(metadata[HealthMetadata.presetID] != nil)
    }

    @Test("Every value is one HealthKit accepts as metadata: a string or a number")
    func valuesArePropertyListTypes() {
        let metadata = WorkoutSessionController.workoutMetadata(for: WorkoutStore.starterWorkouts[0])
        for value in metadata.values {
            #expect(value is NSString || value is NSNumber)
        }
        #expect(PropertyListSerialization.propertyList(metadata, isValidFor: .binary))
    }

    @Test("The keys are pinned: workouts already in Health keep the key they were saved with")
    func keysArePinned() {
        #expect(HealthMetadata.presetID == "IntervallyPresetID")
        #expect(HealthMetadata.presetName == "IntervallyPresetName")
        #expect(HealthMetadata.plannedRounds == "IntervallyPlannedRounds")
        #expect(HealthMetadata.phase == "IntervallyPhase")
        #expect(HealthMetadata.round == "IntervallyRound")
        // The activity tags the iPhone reads are the ones the watch writes.
        #expect(WorkoutSessionController.phaseMetadataKey == HealthMetadata.phase)
        #expect(WorkoutSessionController.roundMetadataKey == HealthMetadata.round)
        // No custom key may use HealthKit's own prefix.
        for key in [HealthMetadata.presetID, HealthMetadata.presetName, HealthMetadata.plannedRounds] {
            #expect(!key.hasPrefix("HK"))
        }
    }
}

/// Records the workout each session start was tagged with.
@MainActor
private final class TaggingWorkoutSession: WorkoutSessioning {
    var isSupported = true
    var isRunning = false
    var heartRate: Double?
    var onUnexpectedEnd: (() -> Void)?
    /// How many upcoming starts fail, as Health access granted a moment ago does.
    var failingStarts = 0
    var recoverableSession = false

    private(set) var tagged: [IntervalWorkout] = []
    private(set) var untaggedStarts = 0

    func requestAuthorization() async -> Bool { true }

    func adoptRecoveredSession() async -> Bool {
        guard recoverableSession else { return false }
        recoverableSession = false
        isRunning = true
        return true
    }

    func start(at date: Date) async -> Bool {
        untaggedStarts += 1
        return result()
    }

    func start(at date: Date, for workout: IntervalWorkout) async -> Bool {
        tagged.append(workout)
        return result()
    }

    private func result() -> Bool {
        if failingStarts > 0 {
            failingStarts -= 1
            return false
        }
        isRunning = true
        return true
    }

    func beginActivity(for phase: IntervalPhase, at date: Date) {}
    func pause() {}
    func resume() {}
    func end(at date: Date) async -> Bool { isRunning = false; return true }
    func discard() { isRunning = false }
}

@Suite("Run coordinator — tagging the Health workout")
@MainActor
struct RunWorkoutTaggingTests {

    private func makeCoordinator(
        _ session: TaggingWorkoutSession, defaults: UserDefaults = makeTestDefaults(), isPro: Bool = false
    ) -> (RunCoordinator, WorkoutStore) {
        let store = WorkoutStore(defaults: defaults)
        let coordinator = RunCoordinator(
            store: store, pro: FakePro(isPro: isPro), haptics: SpyHaptics(), workout: session,
            runtime: FakeRuntimeSession(), notifications: SpyScheduler(), playCue: { _ in }, reloadWidgets: {}
        )
        return (coordinator, store)
    }

    private func settle(_ coordinator: RunCoordinator) async {
        for _ in 0..<6 {
            for _ in 0..<8 { await Task.yield() }
            await coordinator.backstopSettled()
        }
    }

    @Test("A new run's session is tagged with the workout that runs, never started untagged")
    func newRunTagged() async throws {
        let session = TaggingWorkoutSession()
        let (coordinator, store) = makeCoordinator(session)
        store.update(IntervalWorkout(id: store.selected.id, name: "Sprints", warmupSeconds: 300, rounds: 5))

        coordinator.begin()
        await settle(coordinator)

        #expect(coordinator.tier == .workout)
        #expect(session.untaggedStarts == 0)
        let tagged = try #require(session.tagged.first)
        #expect(session.tagged.count == 1)
        #expect(tagged.id == store.selected.id)
        #expect(tagged.name == "Sprints")
        #expect(tagged.rounds == 5)
        // Without Pro the warmup doesn't run, so it isn't what the session is tagged with.
        #expect(tagged == coordinator.engine.plan.workout)
        #expect(tagged.warmupSeconds == 0)
    }

    @Test("A session taken late, after Health was granted mid-run, is tagged too")
    func upgradeTagged() async {
        let session = TaggingWorkoutSession()
        session.failingStarts = 1
        let (coordinator, store) = makeCoordinator(session)
        coordinator.upgradeRetryDelays = [0.01]

        coordinator.begin()
        await settle(coordinator)
        var attempts = 0
        while coordinator.tier != .workout, attempts < 40 {
            try? await Task.sleep(for: .milliseconds(10))
            attempts += 1
        }

        #expect(coordinator.tier == .workout)
        #expect(session.untaggedStarts == 0)
        #expect(session.tagged.map(\.id) == [store.selected.id, store.selected.id])
    }

    @Test("A restored run with no session left to adopt is tagged with its own snapshot's workout")
    func restoreTaggedWithSnapshot() async {
        let defaults = makeTestDefaults()
        let seed = WorkoutStore(defaults: defaults)
        let running = IntervalWorkout(name: "Was Running", workSeconds: 40, rounds: 12)
        seed.saveActiveRun(RunSnapshot(workout: running, anchor: Date().addingTimeInterval(-20), pausedElapsed: nil))
        let session = TaggingWorkoutSession()
        let (coordinator, _) = makeCoordinator(session, defaults: defaults)

        #expect(coordinator.restoreIfNeeded())
        await settle(coordinator)

        // The selected preset may have changed since; the run's own workout is what ran.
        #expect(session.tagged.map(\.id) == [running.id])
        #expect(session.tagged.first?.name == "Was Running")
    }

    @Test("A recovered session is adopted as it is, not started again to be tagged")
    func recoveredSessionNotRestarted() async {
        let defaults = makeTestDefaults()
        let seed = WorkoutStore(defaults: defaults)
        seed.saveActiveRun(RunSnapshot(workout: seed.selected, anchor: Date().addingTimeInterval(-20), pausedElapsed: nil))
        let session = TaggingWorkoutSession()
        session.recoverableSession = true
        let (coordinator, _) = makeCoordinator(session, defaults: defaults)

        #expect(coordinator.restoreIfNeeded())
        await settle(coordinator)

        #expect(coordinator.tier == .workout)
        #expect(session.tagged.isEmpty)
        #expect(session.untaggedStarts == 0)
    }

    @Test("A session that knows nothing of tagging still starts, through the plain start")
    func defaultForwardsToPlainStart() async {
        let fake = FakeWorkoutSession()
        let session: any WorkoutSessioning = fake
        #expect(await session.start(for: WorkoutStore.starterWorkouts[0]))
        #expect(fake.startCount == 1)
    }
}
