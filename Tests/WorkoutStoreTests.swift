//
//  WorkoutStoreTests.swift
//  IntervallyTests
//

import Testing
import Foundation
@testable import Intervally

/// An isolated defaults domain per test so they never bleed into each other.
private func makeDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite("Workout store")
@MainActor
struct WorkoutStoreTests {

    @Test("A fresh store seeds the starter presets and selects one")
    func seedsStarters() {
        let store = WorkoutStore(defaults: makeDefaults())
        #expect(store.workouts.count == WorkoutStore.starterWorkouts.count)
        #expect(store.workouts.contains { $0.id == store.selectedID })
        #expect(store.selected.name == "Classic")
    }

    @Test("Edits round-trip through persistence")
    func editsPersist() {
        let defaults = makeDefaults()
        let store = WorkoutStore(defaults: defaults)

        var workout = store.selected
        workout.workSeconds = 42
        workout.rounds = 12
        store.update(workout)

        // A second store reading the same defaults sees the edit. The legacy app failed
        // exactly here: it seeded under "timerOn" and saved under "timeOn".
        let reloaded = WorkoutStore(defaults: defaults)
        #expect(reloaded.selected.workSeconds == 42)
        #expect(reloaded.selected.rounds == 12)
    }

    @Test("Selection persists across launches")
    func selectionPersists() {
        let defaults = makeDefaults()
        let store = WorkoutStore(defaults: defaults)
        let target = store.workouts[2]
        store.selectedID = target.id

        let reloaded = WorkoutStore(defaults: defaults)
        #expect(reloaded.selectedID == target.id)
        #expect(reloaded.selected.name == target.name)
    }

    @Test("Saved values are clamped, so a bad value can never poison the store")
    func clampsOnUpdate() {
        let store = WorkoutStore(defaults: makeDefaults())
        var workout = store.selected
        workout.rounds = 10_000
        workout.workSeconds = -5
        store.update(workout)

        #expect(store.selected.rounds == IntervalWorkout.roundsRange.upperBound)
        #expect(store.selected.workSeconds == IntervalWorkout.workRange.lowerBound)
    }

    @Test("Adding a preset selects it; deleting never empties the store")
    func addAndDelete() {
        let store = WorkoutStore(defaults: makeDefaults())
        let added = store.add(IntervalWorkout(name: "Sprints", workSeconds: 15, restSeconds: 45, rounds: 6))
        #expect(store.selectedID == added.id)
        #expect(store.workouts.count == 4)

        store.delete(added)
        #expect(store.workouts.count == 3)
        #expect(store.selectedID != added.id)

        // Deleting down to the last preset is refused rather than leaving nothing to run.
        while store.workouts.count > 1 { store.delete(store.workouts[0]) }
        store.delete(store.workouts[0])
        #expect(store.workouts.count == 1)
    }
}

@Suite("Active run recovery")
@MainActor
struct ActiveRunRecoveryTests {

    private let workout = IntervalWorkout(
        prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 8
    )

    @Test("A running snapshot mid-workout is offered back")
    func resumesRunningSnapshot() {
        let defaults = makeDefaults()
        let store = WorkoutStore(defaults: defaults)
        let now = Date()

        store.saveActiveRun(
            RunSnapshot(workout: workout, anchor: now.addingTimeInterval(-45), pausedElapsed: nil)
        )

        let recovered = WorkoutStore(defaults: defaults).loadActiveRun(now: now)
        #expect(recovered?.anchor == now.addingTimeInterval(-45))
        #expect(recovered?.workout == workout)
    }

    @Test("A running snapshot that already finished is discarded")
    func discardsFinishedSnapshot() {
        let defaults = makeDefaults()
        let store = WorkoutStore(defaults: defaults)
        let now = Date()

        // Anchored far enough back that the workout ended while the app was gone.
        store.saveActiveRun(
            RunSnapshot(workout: workout, anchor: now.addingTimeInterval(-10_000), pausedElapsed: nil)
        )
        #expect(WorkoutStore(defaults: defaults).loadActiveRun(now: now) == nil)
    }

    @Test("A paused snapshot survives any amount of elapsed wall-clock time")
    func pausedSnapshotAlwaysResumable() {
        let defaults = makeDefaults()
        let store = WorkoutStore(defaults: defaults)
        let now = Date()

        store.saveActiveRun(
            RunSnapshot(workout: workout, anchor: now.addingTimeInterval(-10_000), pausedElapsed: 60)
        )
        let recovered = WorkoutStore(defaults: defaults).loadActiveRun(now: now)
        #expect(recovered?.pausedElapsed == 60)
    }

    @Test("Clearing the active run leaves nothing to recover")
    func clearsSnapshot() {
        let defaults = makeDefaults()
        let store = WorkoutStore(defaults: defaults)
        store.saveActiveRun(RunSnapshot(workout: workout, anchor: Date(), pausedElapsed: nil))
        store.saveActiveRun(nil)
        #expect(store.loadActiveRun() == nil)
    }

    @Test("A recovered snapshot restores the engine to the right phase")
    func snapshotDrivesEngine() {
        let now = Date()
        let snapshot = RunSnapshot(
            workout: workout, anchor: now.addingTimeInterval(-55), pausedElapsed: nil
        )
        let engine = TimerEngine(workout: snapshot.workout)
        engine.now = { now }
        engine.restore(
            anchor: snapshot.anchor, workout: snapshot.workout, paused: snapshot.pausedElapsed
        )

        // prepare 10 | work 30 (10-40) | rest 15 (40-55) | work 30 (55-85)
        #expect(engine.status == .running)
        #expect(engine.elapsed == 55)
        #expect(engine.position.phase?.kind == .work)
        #expect(engine.position.phase?.round == 2)
    }
}

@Suite("Widget-facing shared reader")
@MainActor
struct SharedReaderTests {

    private let workout = IntervalWorkout(
        prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 8
    )

    @Test("The static reader sees what the app wrote, without building a store")
    func staticReaderSeesWrites() {
        let defaults = makeDefaults()
        let store = WorkoutStore(defaults: defaults)
        let anchor = Date().addingTimeInterval(-45)

        store.saveActiveRun(RunSnapshot(workout: workout, anchor: anchor, pausedElapsed: nil))

        // This is the path the widget extension takes: a plain read from the shared suite
        // with no @MainActor store instance involved.
        let snapshot = WorkoutStore.activeRun(in: defaults)
        #expect(snapshot?.anchor == anchor)
        #expect(snapshot?.workout.rounds == 8)
    }

    @Test("With no run recorded the reader returns nothing")
    func staticReaderEmpty() {
        #expect(WorkoutStore.activeRun(in: makeDefaults()) == nil)
    }

    @Test("A snapshot resolves to the phase end date the complication counts down to")
    func snapshotYieldsPhaseEnd() {
        let now = Date()
        let anchor = now.addingTimeInterval(-45)
        let plan = IntervalPlan(workout: workout)
        let position = plan.position(atElapsed: now.timeIntervalSince(anchor))

        // prepare 10 | work 30 (10-40) | rest 15 (40-55)
        #expect(position.phase?.kind == .rest)
        let phaseEnd = anchor.addingTimeInterval(position.phase!.end)
        #expect(abs(phaseEnd.timeIntervalSince(now) - 10) < 0.001)
    }
}

@Suite("Workout store — warmup and cooldown")
@MainActor
struct WorkoutStoreBookendTests {

    private let workout = IntervalWorkout(
        prepareSeconds: 10, warmupSeconds: 300, workSeconds: 30, restSeconds: 15, rounds: 8, cooldownSeconds: 240
    )

    @Test("A preset list saved before bookends existed still loads, with both off")
    func legacyPresetBlobLoads() {
        let defaults = makeDefaults()
        let legacy = Data("""
        [{"id":"0E4C1F6A-7B1D-4C55-8A2E-5D9B3F1C7A10","name":"Hills",
          "prepareSeconds":5,"workSeconds":40,"restSeconds":20,"rounds":6}]
        """.utf8)
        defaults.set(legacy, forKey: WorkoutStore.Key.workouts)

        let store = WorkoutStore(defaults: defaults)
        #expect(store.workouts.count == 1)
        #expect(store.selected.name == "Hills")
        #expect(store.selected.workSeconds == 40)
        #expect(store.selected.warmupSeconds == 0)
        #expect(store.selected.cooldownSeconds == 0)
    }

    @Test("A run snapshot saved before bookends existed still decodes")
    func legacySnapshotDecodes() throws {
        let defaults = makeDefaults()
        let legacy = Data("""
        {"workout":{"id":"0E4C1F6A-7B1D-4C55-8A2E-5D9B3F1C7A10","name":"Hills",
          "prepareSeconds":5,"workSeconds":40,"restSeconds":20,"rounds":6},
         "anchor":700000000}
        """.utf8)
        defaults.set(legacy, forKey: WorkoutStore.Key.activeRun)

        let snapshot = try #require(WorkoutStore.activeRun(in: defaults))
        #expect(snapshot.workout.rounds == 6)
        #expect(snapshot.workout.hasBookends == false)
        #expect(snapshot.pausedElapsed == nil)
        #expect(snapshot.anchor == Date(timeIntervalSinceReferenceDate: 700_000_000))
    }

    @Test("Bookends persist through the store like every other field")
    func bookendsPersist() {
        let defaults = makeDefaults()
        let store = WorkoutStore(defaults: defaults)
        var edited = store.selected
        edited.warmupSeconds = 300
        edited.cooldownSeconds = 99_999
        store.update(edited)

        let reloaded = WorkoutStore(defaults: defaults)
        #expect(reloaded.selected.warmupSeconds == 300)
        // Clamped on the way in, like the other fields.
        #expect(reloaded.selected.cooldownSeconds == IntervalWorkout.cooldownRange.upperBound)
    }

    @Test("A run relaunched mid-cooldown is offered back, not discarded as finished")
    func resumesMidCooldown() {
        let defaults = makeDefaults()
        let store = WorkoutStore(defaults: defaults)
        let now = Date()
        // 895 s in all; the cooldown is the last 240, so 800 s in is mid-cooldown.
        let anchor = now.addingTimeInterval(-800)
        store.saveActiveRun(RunSnapshot(workout: workout, anchor: anchor, pausedElapsed: nil))

        let recovered = WorkoutStore(defaults: defaults).loadActiveRun(now: now)
        #expect(recovered?.anchor == anchor)
        #expect(recovered?.workout == workout)
        #expect(recovered?.progress(at: now)?.phaseKind == .cooldown)
    }

    @Test("A run past the end of its cooldown is still discarded")
    func discardsAfterCooldown() {
        let defaults = makeDefaults()
        let store = WorkoutStore(defaults: defaults)
        let now = Date()
        store.saveActiveRun(RunSnapshot(workout: workout, anchor: now.addingTimeInterval(-896), pausedElapsed: nil))
        #expect(WorkoutStore(defaults: defaults).loadActiveRun(now: now) == nil)
    }
}
