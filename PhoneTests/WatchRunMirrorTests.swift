//
//  WatchRunMirrorTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// A run on the watch, shown on iPhone: rebuilt from what the watch sends, on screen and on
/// the Lock Screen, and Start on Watch on the way to it.
@Suite("Watch run on iPhone")
@MainActor
struct WatchRunMirrorTests {
    let defaults = makeTestDefaults()
    let pro = FakePro()
    let session = FakeWorkoutSession()
    let presenter = RecordingPresenter()

    private func makeRun() -> (PhoneRun, WorkoutStore) {
        let store = WorkoutStore(defaults: defaults)
        let run = PhoneRun(
            store: store, pro: pro, theme: ThemeStore(defaults: defaults), output: FakeCueOutput(),
            workout: session, notifications: FakeBackstop(), presenter: presenter, defaults: defaults
        )
        return (run, store)
    }

    private let tabata = IntervalWorkout(name: "Tabata", workSeconds: 20, restSeconds: 10, rounds: 8)

    private func state(
        _ status: RunMirrorState.Status, anchor: Date? = nil, pausedElapsed: TimeInterval? = nil,
        health: RunMirrorState.Health? = nil
    ) -> RunMirrorState {
        RunMirrorState(workout: tabata, status: status, anchor: anchor, pausedElapsed: pausedElapsed, health: health)
    }

    @Test("A running watch run counts from the watch's own anchor, and takes the screen once")
    func running() throws {
        let (run, _) = makeRun()
        run.mirror.apply(state(.running, anchor: Date().addingTimeInterval(-25)))
        #expect(run.isPresented)
        #expect(run.isMirroring)
        #expect(run.engine.status == .running)
        #expect(abs(run.engine.elapsed - 25) < 1)
        let shown = try #require(presenter.shown.last ?? nil)
        #expect(shown.workoutName == "Tabata")

        // Shut by the user, the screen stays shut while the same run carries on.
        run.isPresented = false
        run.mirror.apply(state(.running, anchor: Date().addingTimeInterval(-26)))
        #expect(run.isPresented == false)
    }

    @Test("A pause holds exactly where the watch held it")
    func paused() {
        let (run, _) = makeRun()
        run.mirror.apply(state(.running, anchor: Date().addingTimeInterval(-10)))
        run.mirror.apply(state(.paused, pausedElapsed: 42))
        #expect(run.engine.status == .paused)
        #expect(run.engine.elapsed == 42)
    }

    @Test("Ended on the watch, the run leaves the screen and the Lock Screen")
    func stopped() {
        let (run, _) = makeRun()
        run.mirror.apply(state(.running, anchor: Date()))
        run.mirror.apply(state(.stopped))
        #expect(run.isMirroring == false)
        #expect(run.mirror.engine == nil)
        #expect(presenter.shown.last == .some(nil))
    }

    @Test("A finished watch run shows its summary until Done, without a Health claim it can't check")
    func finished() throws {
        let (run, _) = makeRun()
        run.mirror.apply(state(.running, anchor: Date()))
        run.mirror.apply(state(.finished, health: .saving))
        #expect(run.engine.status == .finished)
        // The mirror was never connected here, so the watch's save can't be followed.
        let summary = try #require(run.summary)
        #expect(summary.health == .notRecorded)
        #expect(summary.rounds == 8)

        run.mirror.apply(state(.finished, health: .saved))
        #expect(run.summary?.health == .saved)

        run.done()
        #expect(run.isPresented == false)
        #expect(run.mirror.engine == nil)
    }

    @Test("End closes a watch run's screen and Lock Screen at once, reachable watch or not")
    func endHere() {
        let (run, _) = makeRun()
        run.mirror.apply(state(.running, anchor: Date()))
        run.end()
        #expect(run.isPresented == false)
        #expect(run.mirror.engine == nil)
        #expect(presenter.shown.last == .some(nil))

        // The watch carried on: its next change shows it again.
        run.mirror.apply(state(.paused, pausedElapsed: 12))
        #expect(run.isPresented)
    }

    @Test("The session ending just short of the end is the finish, not a stop")
    func endedAtTheFinish() {
        let (run, _) = makeRun()
        let total = IntervalPlan(workout: tabata).totalDuration
        run.mirror.apply(state(.running, anchor: Date().addingTimeInterval(-(total - 1))))
        run.mirror.sessionEnded()
        #expect(run.engine.status == .finished)
        #expect(run.isMirroring)
    }

    @Test("The session ending mid-run clears it")
    func endedMidRun() {
        let (run, _) = makeRun()
        run.mirror.apply(state(.running, anchor: Date().addingTimeInterval(-30)))
        run.mirror.sessionEnded()
        #expect(run.mirror.engine == nil)
        #expect(presenter.shown.last == .some(nil))
    }

    @Test("The iPhone's own run keeps the screen and the Lock Screen while the watch runs too")
    func ownRunComesFirst() async throws {
        let (run, store) = makeRun()
        run.start(store.workouts[0])
        run.coordinator.begin()
        #expect(await waitUntil { run.coordinator.engine.status == .running })
        let shownBefore = presenter.shown.count

        run.mirror.apply(state(.running, anchor: Date()))
        #expect(run.isMirroring == false)
        #expect(run.engine === run.coordinator.engine)
        #expect(presenter.shown.count == shownBefore, "The watch's run doesn't take the Lock Screen")
        run.close()
    }

    // MARK: - Start on Watch

    @Test("Start on Watch puts the preset up next, asks the watch, and says so until its run shows")
    func startOnWatch() async throws {
        let (run, store) = makeRun()
        var requested: [UUID] = []
        run.requestWatchStart = { requested.append($0); return true }
        run.wakeWatch = {}
        let preset = store.workouts[1]

        run.startOnWatch(preset)
        #expect(store.selectedID == preset.id)
        #expect(requested == [preset.id])
        #expect(run.watchStart == .starting)
        #expect(run.isPresented == false, "Nothing shows here until the watch's run does")

        run.mirror.apply(state(.running, anchor: Date()))
        #expect(run.watchStart == .idle)
        #expect(run.isPresented)
    }

    @Test("A watch that can't be reached offers the same workout on iPhone")
    func startOnWatchFails() async throws {
        let (run, store) = makeRun()
        struct Unreachable: Error {}
        run.wakeWatch = { throw Unreachable() }
        let preset = store.workouts[1]

        run.startOnWatch(preset)
        #expect(await waitUntil { run.watchStart == .failed })

        run.startHereInstead()
        #expect(run.watchStart == .idle)
        #expect(run.isPresented)
        #expect(store.selectedID == preset.id)
    }

    @Test("With a run already going here, Start on Watch shows it instead of waking the watch")
    func startOnWatchDuringOwnRun() async throws {
        let (run, store) = makeRun()
        run.start(store.workouts[0])
        run.coordinator.begin()
        #expect(await waitUntil { run.coordinator.engine.status == .running })
        run.isPresented = false
        var requested = 0
        run.requestWatchStart = { _ in requested += 1; return true }

        run.startOnWatch(store.workouts[1])
        #expect(requested == 0)
        #expect(run.isPresented)
        #expect(run.watchStart == .idle)
        run.close()
    }
}
