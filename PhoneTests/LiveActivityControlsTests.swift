//
//  LiveActivityControlsTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// The Live Activity's Pause, Resume and Skip Interval: when it shows them, and what a tap does
/// to the run on this iPhone, through the intents the system runs, against a stand-in for
/// ActivityKit.
@Suite("Live Activity controls")
@MainActor
struct LiveActivityControlsTests {
    let defaults = makeTestDefaults()
    let host = FakeLiveActivityHost()
    /// The run's clock: it reads the reference date until a test moves it.
    let time = VirtualTime()

    /// Hill Sprints, the 1.2 fixtures' run: the first Sprint, phase 2, from 315 to 345 seconds,
    /// then a Walk to 435; the last Sprint, phase 12, from 915 to 945; and the cooldown, the
    /// last interval, to 1245.
    private static let plan = IntervalPlan(workout: Fixture.hillSprints12)

    private static let virtualNow = Date(timeIntervalSinceReferenceDate: 0)

    /// Hill Sprints on this iPhone, brought back paused `elapsed` seconds in, as a relaunch
    /// brings a run back, with its Live Activity showing it.
    private func pausedRun(at elapsed: TimeInterval) async -> (PhoneRun, WorkoutStore) {
        let store = WorkoutStore(defaults: defaults)
        store.saveActiveRun(RunSnapshot(workout: Fixture.hillSprints12, anchor: Date(), pausedElapsed: elapsed))
        let run = PhoneRun(
            store: store, pro: FakePro(), theme: ThemeStore(defaults: defaults), output: FakeCueOutput(),
            workout: FakeWorkoutSession(), notifications: FakeBackstop(), activityHost: host, defaults: defaults
        )
        run.coordinator.runOnVirtualTime(time)
        run.restoreAtLaunch()
        await run.activity.settled()
        return (run, store)
    }

    /// What the Lock Screen shows now: the state last sent to the activity.
    private var lastShown: RunActivityAttributes.ContentState? {
        switch host.calls.last {
        case .request(_, _, let shown), .update(_, let shown): shown.state
        case .end(_, let shown, _): shown?.state
        case nil: nil
        }
    }

    private static func state(
        _ status: TimerEngine.Status, at elapsed: TimeInterval, of plan: IntervalPlan = plan
    ) throws -> RunActivityAttributes.ContentState {
        let run = try #require(RunPresentation(
            plan: plan, status: status, anchor: status == .running ? Date() : nil, elapsed: elapsed
        ))
        return RunActivityAttributes.ContentState(run, theme: .classic)
    }

    @Test("The watch's run, shown on this iPhone, has no buttons, and a tap that reaches the app anyway changes nothing")
    func controlsHiddenWhenMirrored() async throws {
        let run = PhoneRun(
            store: WorkoutStore(defaults: defaults), pro: FakePro(), theme: ThemeStore(defaults: defaults),
            output: FakeCueOutput(), workout: FakeWorkoutSession(), notifications: FakeBackstop(),
            activityHost: host, defaults: defaults
        )
        run.mirror.apply(RunMirrorState(
            workout: Fixture.hillSprints12, status: .paused, anchor: nil, pausedElapsed: 330.5, health: nil
        ))
        await run.activity.settled()
        #expect(run.isMirroring)
        #expect(lastShown?.phase == .work, "The watch's run is on the Lock Screen")
        #expect(lastShown?.controls == nil)

        run.mirror.apply(RunMirrorState(
            workout: Fixture.hillSprints12, status: .running, anchor: Date().addingTimeInterval(-330.5),
            pausedElapsed: nil, health: nil
        ))
        await run.activity.settled()
        #expect(lastShown?.staleDate != nil, "Running")
        #expect(lastShown?.controls == nil)

        let calls = host.calls.count
        await run.control(PauseRunIntent().command)
        await run.control(SkipIntervalIntent(phaseIndex: 2).command)
        #expect(run.engine.status == .running, "The watch's run is paused and skipped on the watch")
        #expect(run.coordinator.engine.status == .idle)
        #expect(host.calls.count == calls)

        // The same run on this iPhone has them.
        let own = try Self.state(.paused, at: 330.5)
        #expect(own.controls == .init(canPause: false, canResume: true, canSkip: true))
    }

    @Test("A finished run's card has no buttons, nor has one the system has marked stale")
    func hiddenWhenFinishedOrStale() async throws {
        // Paused in the cooldown, and skipped in the app: that finishes the run.
        let (run, _) = await pausedRun(at: 1200)
        #expect(lastShown?.controls != nil)
        run.skip()
        await run.activity.settled()
        #expect(run.coordinator.engine.status == .finished)
        let ended = try #require(host.calls.last)
        guard case .end("1", let finished?, .after) = ended else {
            Issue.record("Not ended showing the finish: \(ended)")
            return
        }
        #expect(finished.state.clock == .finished)
        #expect(finished.state.controls == nil)
        #expect(finished.state.visibleControls(isStale: false) == nil)

        // A tap left from the card before, landing on the finished run, does nothing.
        let calls = host.calls.count
        await run.control(ResumeRunIntent().command)
        await run.control(SkipIntervalIntent(phaseIndex: 13).command)
        #expect(run.coordinator.engine.status == .finished)
        #expect(host.calls.count == calls)
        run.close()

        // Stale, the activity shows a phase that has run out: its buttons are for a run that
        // has moved on.
        let running = try Self.state(.running, at: 330.5)
        #expect(running.visibleControls(isStale: false) == .init(canPause: true, canResume: false, canSkip: true))
        #expect(running.visibleControls(isStale: true) == nil)
    }

    @Test("No Skip in the last interval: skipping it would end the workout, which only the app does")
    func noSkipInLastInterval() async throws {
        // Hill Sprints ends with its cooldown.
        #expect(try Self.state(.running, at: 930).controls == .init(canPause: true, canResume: false, canSkip: true))
        #expect(try Self.state(.running, at: 1000).controls == .init(canPause: true, canResume: false, canSkip: false))
        #expect(try Self.state(.paused, at: 1000).controls == .init(canPause: false, canResume: true, canSkip: false))
        // Tabata, with none, ends on its last work, from 220 seconds.
        let tabata = IntervalPlan(workout: Fixture.starters12[1])
        #expect(try Self.state(.running, at: 215, of: tabata).controls?.canSkip == true)
        #expect(try Self.state(.running, at: 230, of: tabata).controls?.canSkip == false)

        // Skipped from the Lock Screen into the cooldown, the card loses its Skip at once.
        let (run, _) = await pausedRun(at: 930)
        await run.control(SkipIntervalIntent(phaseIndex: 12).command)
        #expect(run.coordinator.engine.position.phaseIndex == 13)
        #expect(lastShown?.phase == .cooldown)
        #expect(lastShown?.controls == .init(canPause: false, canResume: true, canSkip: false))
        run.close()
    }

    @Test("A Skip that lands once its interval is over, or a second tap on the same button, skips nothing")
    func staleSkipIgnored() async throws {
        // Paused in the first Sprint: a tap skips it, and the same button again, before the
        // Lock Screen has caught up, is for an interval that is gone.
        let (run, _) = await pausedRun(at: 330.5)
        let engine = run.coordinator.engine
        let sprint = SkipIntervalIntent(phaseIndex: 2)
        await run.control(sprint.command)
        #expect(engine.position.phaseIndex == 3)
        #expect(engine.elapsed == 345)
        let calls = host.calls.count
        await run.control(sprint.command)
        #expect(engine.position.phaseIndex == 3)
        #expect(engine.elapsed == 345, "The Walk isn't skipped as well")
        #expect(host.calls.count == calls)

        // Running, the Walk runs out with its button on the Lock Screen, the phone in a pocket
        // for a while: the tap that arrives in the next Sprint leaves it be.
        run.togglePause()
        #expect(await waitUntil { time.sleeping == 1 }, "The ticker is asleep")
        let walk = SkipIntervalIntent(phaseIndex: 3)
        let woken = time.woken
        time.advance(by: .seconds(95))
        #expect(await waitUntil { time.woken > woken && time.sleeping == 1 }, "The ticker has caught up")
        await run.activity.settled()
        #expect(engine.position.phaseIndex == 4)
        #expect(lastShown?.phaseIndex == 4)
        let elapsed = engine.elapsed
        let shown = host.calls.count
        await run.control(walk.command)
        #expect(engine.position.phaseIndex == 4)
        #expect(engine.elapsed == elapsed)
        #expect(host.calls.count == shown)
        run.close()
    }

    @Test("Pause pauses the run where it stands and saves it so, and the Lock Screen shows Resume before the tap is done")
    func pauseIntentPauses() async throws {
        let (run, store) = await pausedRun(at: 330.5)
        run.togglePause()
        await run.activity.settled()
        let engine = run.coordinator.engine
        #expect(engine.status == .running)
        let calls = host.calls.count

        await run.control(PauseRunIntent().command)
        #expect(engine.status == .paused)
        #expect(engine.elapsed == 330.5)
        #expect(store.loadActiveRun(now: Self.virtualNow)?.pausedElapsed == 330.5, "Saved at once")
        // No waiting: the activity is updated before the intent returns.
        #expect(host.calls.count == calls + 1)
        #expect(lastShown?.clock == .paused(phaseLeft: 14.5, workoutLeft: 914.5))
        #expect(lastShown?.controls == .init(canPause: false, canResume: true, canSkip: true))

        // The same Pause again, landing on the paused run, doesn't resume it.
        await run.control(PauseRunIntent().command)
        #expect(engine.status == .paused)
        #expect(host.calls.count == calls + 1)
        run.close()
    }

    @Test("Resume carries on from where the run stopped and saves it so, and the Lock Screen shows Pause before the tap is done")
    func resumeIntentResumes() async throws {
        let (run, store) = await pausedRun(at: 330.5)
        let engine = run.coordinator.engine
        #expect(lastShown?.controls == .init(canPause: false, canResume: true, canSkip: true))
        let calls = host.calls.count

        await run.control(ResumeRunIntent().command)
        #expect(engine.status == .running)
        #expect(engine.elapsed == 330.5)
        let anchor = Self.virtualNow.addingTimeInterval(-330.5)
        let saved = store.loadActiveRun(now: Self.virtualNow)
        #expect(saved?.pausedElapsed == nil)
        #expect(saved?.anchor == anchor, "Saved running at once")
        #expect(host.calls.count == calls + 1)
        #expect(lastShown?.clock == .running(
            phaseStart: anchor.addingTimeInterval(315), phaseEnd: anchor.addingTimeInterval(345),
            workoutEnd: anchor.addingTimeInterval(1245)
        ))
        #expect(lastShown?.controls == .init(canPause: true, canResume: false, canSkip: true))

        // The same Resume again changes nothing.
        await run.control(ResumeRunIntent().command)
        #expect(engine.status == .running)
        #expect(host.calls.count == calls + 1)
        run.close()
    }

    @Test("Skip Interval skips the interval its button was drawn for, and the Lock Screen shows the next at once")
    func skipIntentSkipsCurrent() async throws {
        let (run, store) = await pausedRun(at: 330.5)
        run.togglePause()
        await run.activity.settled()
        let engine = run.coordinator.engine
        #expect(lastShown?.phaseIndex == 2)

        await run.control(SkipIntervalIntent(phaseIndex: 2).command)
        #expect(engine.status == .running)
        #expect(engine.position.phaseIndex == 3)
        #expect(engine.position.phase?.title == "Walk")
        #expect(engine.elapsed == 345)
        #expect(store.loadActiveRun(now: Self.virtualNow)?.anchor == Self.virtualNow.addingTimeInterval(-345))
        #expect(lastShown?.phase == .rest)
        #expect(lastShown?.phaseName == "Walk")
        #expect(lastShown?.phaseIndex == 3)
        #expect(lastShown?.controls == .init(canPause: true, canResume: false, canSkip: true))
        run.close()
    }

    @Test("Siri and Shortcuts are offered none of the buttons")
    func intentsNotDiscoverable() {
        #expect(!PauseRunIntent.isDiscoverable)
        #expect(!ResumeRunIntent.isDiscoverable)
        #expect(!SkipIntervalIntent.isDiscoverable)
    }
}
