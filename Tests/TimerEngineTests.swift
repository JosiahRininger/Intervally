//
//  TimerEngineTests.swift
//  IntervallyTests
//

import Testing
import Foundation
@testable import Intervally

/// A controllable clock so tests can jump time without sleeping.
@MainActor
private final class TestClock {
    var current = Date(timeIntervalSinceReferenceDate: 1_000_000)
    func advance(_ seconds: TimeInterval) { current += seconds }
}

@MainActor
private func makeEngine(
    prepare: Int = 5, warmup: Int = 0, work: Int = 20, rest: Int = 10, rounds: Int = 3, cooldown: Int = 0
) -> (TimerEngine, TestClock) {
    let clock = TestClock()
    let engine = TimerEngine(
        workout: IntervalWorkout(
            prepareSeconds: prepare, warmupSeconds: warmup, workSeconds: work,
            restSeconds: rest, rounds: rounds, cooldownSeconds: cooldown
        )
    )
    engine.now = { clock.current }
    return (engine, clock)
}

@Suite("Timer engine transport")
@MainActor
struct TimerEngineTransportTests {

    @Test("A fresh engine is idle with no elapsed time")
    func startsIdle() {
        let (engine, _) = makeEngine()
        #expect(engine.status == .idle)
        #expect(engine.elapsed == 0)
        #expect(engine.isActive == false)
    }

    @Test("Starting announces the first phase")
    func startAnnouncesFirstPhase() {
        let (engine, _) = makeEngine()
        let events = engine.start()
        #expect(engine.status == .running)
        #expect(events.count == 1)
        if case .phaseBegan(let phase) = events[0] {
            #expect(phase.kind == .prepare)
        } else {
            Issue.record("expected phaseBegan, got \(events)")
        }
    }

    @Test("Elapsed time tracks the clock while running")
    func elapsedTracksClock() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(7)
        #expect(engine.elapsed == 7)
        #expect(engine.position.phase?.kind == .work)
        #expect(engine.position.remainingInPhase == 18)
    }

    @Test("Pausing freezes elapsed time and resuming excludes the paused interval")
    func pauseExcludesPausedTime() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(10)
        engine.pause()
        #expect(engine.status == .paused)
        #expect(engine.elapsed == 10)

        // Two minutes pass while paused — none of it should count.
        clock.advance(120)
        #expect(engine.elapsed == 10)

        engine.resume()
        #expect(engine.status == .running)
        #expect(engine.elapsed == 10)

        clock.advance(5)
        #expect(engine.elapsed == 15)
    }

    @Test("Toggling flips between running and paused")
    func togglePause() {
        let (engine, _) = makeEngine()
        engine.start()
        engine.togglePause()
        #expect(engine.status == .paused)
        engine.togglePause()
        #expect(engine.status == .running)
    }

    @Test("Stopping returns the engine to idle")
    func stopResets() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(30)
        engine.stop()
        #expect(engine.status == .idle)
        #expect(engine.elapsed == 0)
    }
}

@Suite("Timer engine advancing")
@MainActor
struct TimerEngineAdvanceTests {

    @Test("Crossing a boundary emits exactly one phaseBegan")
    func emitsPhaseBegan() {
        let (engine, clock) = makeEngine()
        engine.start()

        clock.advance(4)
        #expect(engine.advance().contains(.countdown(secondsRemaining: 1)))

        clock.advance(1) // t=5, prepare -> work
        let events = engine.advance()
        #expect(events.count == 1)
        if case .phaseBegan(let phase) = events[0] {
            #expect(phase.kind == .work)
            #expect(phase.round == 1)
        } else {
            Issue.record("expected phaseBegan, got \(events)")
        }

        // Advancing again inside the same phase emits nothing new.
        clock.advance(1)
        #expect(engine.advance().isEmpty)
    }

    @Test("Countdown cues fire at 3, 2 and 1 seconds remaining")
    func countdownCues() {
        let (engine, clock) = makeEngine(prepare: 0, work: 10, rest: 5, rounds: 2)
        engine.start()

        var cues: [Int] = []
        for _ in 0..<10 {
            clock.advance(1)
            for event in engine.advance() {
                if case .countdown(let remaining) = event { cues.append(remaining) }
            }
        }
        #expect(cues == [3, 2, 1])
    }

    @Test("A long suspension collapses to one phaseBegan for the current phase")
    func suspensionCollapsesEvents() {
        // This is the scenario that killed the original app: the watch suspends the app
        // for most of the workout, then it resumes. Time must have advanced correctly and
        // the user must not receive a burst of stale haptics for every missed boundary.
        let (engine, clock) = makeEngine(prepare: 5, work: 20, rest: 10, rounds: 3)
        engine.start()

        clock.advance(70) // straight past prepare, work 1, rest 1, work 2, rest 2
        let events = engine.advance()

        #expect(events.count == 1)
        if case .phaseBegan(let phase) = events[0] {
            #expect(phase.kind == .work)
            #expect(phase.round == 3)
        } else {
            Issue.record("expected a single phaseBegan, got \(events)")
        }
        #expect(engine.elapsed == 70)
    }

    @Test("Running past the end finishes exactly once")
    func finishesOnce() {
        let (engine, clock) = makeEngine(prepare: 0, work: 5, rest: 0, rounds: 1)
        engine.start()
        clock.advance(5)

        let events = engine.advance()
        #expect(events == [.finished])
        #expect(engine.status == .finished)
        #expect(engine.position.isFinished)

        // Once finished, advancing is inert.
        clock.advance(60)
        #expect(engine.advance().isEmpty)
        #expect(engine.elapsed == 5)
    }

    @Test("Elapsed never exceeds the plan duration")
    func elapsedClamped() {
        let (engine, clock) = makeEngine(prepare: 0, work: 5, rest: 0, rounds: 1)
        engine.start()
        clock.advance(10_000)
        #expect(engine.elapsed == 5)
    }

    @Test("A paused engine ignores advance")
    func pausedIgnoresAdvance() {
        let (engine, clock) = makeEngine()
        engine.start()
        engine.pause()
        clock.advance(100)
        #expect(engine.advance().isEmpty)
        #expect(engine.status == .paused)
    }
}

@Suite("Timer engine deadlines and restoration")
@MainActor
struct TimerEngineDeadlineTests {

    @Test("Phase and workout end dates are absolute and survive re-reading")
    func endDates() {
        let (engine, clock) = makeEngine(prepare: 5, work: 20, rest: 10, rounds: 2)
        let started = clock.current
        engine.start()

        #expect(engine.currentPhaseEndDate == started.addingTimeInterval(5))
        let total: TimeInterval = 5 + 20 + 10 + 20
        #expect(engine.workoutEndDate == started.addingTimeInterval(total))

        clock.advance(6)
        #expect(engine.currentPhaseEndDate == started.addingTimeInterval(25))
        // The workout end date does not drift as time passes.
        #expect(engine.workoutEndDate == started.addingTimeInterval(55))
    }

    @Test("Pausing clears the deadlines so the UI stops showing a live countdown")
    func deadlinesClearedWhenPaused() {
        let (engine, _) = makeEngine()
        engine.start()
        engine.pause()
        #expect(engine.currentPhaseEndDate == nil)
        #expect(engine.workoutEndDate == nil)
    }

    @Test("Restoring from an anchor recovers mid-workout state")
    func restoreRunning() {
        let (engine, clock) = makeEngine()
        let workout = IntervalWorkout(prepareSeconds: 5, workSeconds: 20, restSeconds: 10, rounds: 3)

        // The app was killed 40 seconds into the workout and relaunched.
        engine.restore(anchor: clock.current.addingTimeInterval(-40), workout: workout, paused: nil)

        #expect(engine.status == .running)
        #expect(engine.elapsed == 40)
        #expect(engine.position.phase?.kind == .work)
        #expect(engine.position.phase?.round == 2)
        // Restoration must not replay the boundary it resumed into.
        #expect(engine.advance().isEmpty)
    }

    @Test("Restoring a run that finished while the app was away reports finished")
    func restoreFinished() {
        let (engine, clock) = makeEngine()
        let workout = IntervalWorkout(prepareSeconds: 5, workSeconds: 20, restSeconds: 10, rounds: 3)
        engine.restore(anchor: clock.current.addingTimeInterval(-10_000), workout: workout, paused: nil)
        #expect(engine.status == .finished)
    }

    @Test("Restoring a paused run keeps it paused at the right elapsed time")
    func restorePaused() {
        let (engine, clock) = makeEngine()
        let workout = IntervalWorkout(prepareSeconds: 5, workSeconds: 20, restSeconds: 10, rounds: 3)
        engine.restore(anchor: clock.current, workout: workout, paused: 30)
        #expect(engine.status == .paused)
        #expect(engine.elapsed == 30)
        #expect(engine.position.phase?.kind == .rest)
        #expect(engine.position.phase?.round == 1)
    }
}

@Suite("Regressions found in review")
@MainActor
struct TimerEngineRegressionTests {

    @Test("Pausing after the run has already completed finishes it instead of stranding it")
    func pauseAfterCompletionFinishes() {
        // A tap that lands in the moment between the last second elapsing and the tick that
        // would have noticed used to leave the engine paused at a finished position, where
        // `advance()` does nothing and `.finished` could never fire — so the workout never
        // ended, was never saved, and the session was never torn down.
        let (engine, clock) = makeEngine(prepare: 0, work: 5, rest: 0, rounds: 1)
        engine.start()
        clock.advance(5)

        let events = engine.pause()
        #expect(events == [.finished])
        #expect(engine.status == .finished)
        #expect(engine.position.isFinished)
    }

    @Test("Pausing before completion still pauses normally")
    func pauseBeforeCompletionStillPauses() {
        let (engine, clock) = makeEngine(prepare: 0, work: 10, rest: 0, rounds: 1)
        engine.start()
        clock.advance(4)

        #expect(engine.pause().isEmpty)
        #expect(engine.status == .paused)
        #expect(engine.elapsed == 4)
    }

    @Test("The phase end date is never behind the clock while running")
    func phaseEndNeverBehindNow() {
        // Constructing `now...phaseEnd` traps if the end has already passed, so the engine
        // must not report a stale phase end.
        let (engine, clock) = makeEngine(prepare: 3, work: 4, rest: 2, rounds: 3)
        engine.start()

        for _ in 0..<Int(engine.plan.totalDuration * 4) {
            clock.advance(0.25)
            engine.advance()
            guard engine.status == .running, let end = engine.currentPhaseEndDate else { continue }
            #expect(end >= clock.current)
        }
    }
}

@Suite("Timer engine — skipping")
@MainActor
struct TimerEngineSkipTests {

    @Test("Skipping while running lands exactly on the next boundary and announces it")
    func skipRunning() {
        // prepare 5 | work 20 (5-25) | rest 10 (25-35) | work 20 (35-55) ...
        let (engine, clock) = makeEngine(prepare: 5, work: 20, rest: 10, rounds: 3)
        engine.start()
        clock.advance(2)

        let events = engine.skipPhase()
        #expect(engine.elapsed == 5)
        #expect(engine.position.phase?.kind == .work)
        #expect(engine.position.remainingInPhase == 20)
        #expect(events.count == 1)
        if case .phaseBegan(let phase) = events[0] { #expect(phase.kind == .work) } else { Issue.record("expected phaseBegan") }
    }

    @Test("Skipping the final phase finishes the run exactly once")
    func skipLastPhaseFinishes() {
        let (engine, clock) = makeEngine(prepare: 0, work: 10, rest: 0, rounds: 1)
        engine.start()
        clock.advance(3)
        #expect(engine.skipPhase() == [.finished])
        #expect(engine.status == .finished)
        #expect(engine.skipPhase().isEmpty)
    }

    @Test("Skipping while paused moves the frozen time; the haptic waits for resume")
    func skipPaused() {
        let (engine, clock) = makeEngine(prepare: 5, work: 20, rest: 10, rounds: 3)
        engine.start()
        clock.advance(2)
        engine.pause()

        #expect(engine.skipPhase().isEmpty)
        #expect(engine.status == .paused)
        #expect(engine.elapsed == 5)
        #expect(engine.position.phase?.kind == .work)

        engine.resume()
        let events = engine.advance()
        #expect(events.contains { if case .phaseBegan(let p) = $0 { return p.kind == .work } else { return false } })
    }

    @Test("Skipping the last phase while paused finishes the run instead of parking on its end")
    func skipLastPhasePaused() {
        // work 10 (0-10) | cooldown 30 (10-40)
        let (engine, clock) = makeEngine(prepare: 0, work: 10, rest: 0, rounds: 1, cooldown: 30)
        engine.start()
        clock.advance(12.5)
        engine.pause()
        #expect(engine.position.phase?.kind == .cooldown)

        #expect(engine.skipPhase() == [.finished])
        #expect(engine.status == .finished)
        #expect(engine.anchor == nil)
        #expect(engine.elapsed == engine.plan.totalDuration)

        #expect(engine.skipPhase().isEmpty, "Finished exactly once")
        engine.resume()
        #expect(engine.status == .finished, "There is nothing left to resume")
    }

    @Test("Skipping repeatedly walks every boundary in order")
    func skipWalksAllPhases() {
        let (engine, _) = makeEngine(prepare: 5, work: 20, rest: 10, rounds: 2)
        engine.start()
        var kinds: [IntervalPhase.Kind] = []
        while engine.status == .running {
            for e in engine.skipPhase() { if case .phaseBegan(let p) = e { kinds.append(p.kind) } }
        }
        #expect(kinds == [.work, .rest, .work])
        #expect(engine.status == .finished)
    }
}

@Suite("Timer engine — warmup and cooldown")
@MainActor
struct TimerEngineBookendTests {

    private func began(_ events: [TimerEvent]) -> IntervalPhase? {
        for event in events { if case .phaseBegan(let phase) = event { return phase } }
        return nil
    }

    @Test("With no lead-in, starting announces the warmup")
    func startAnnouncesWarmup() {
        let (engine, _) = makeEngine(prepare: 0, warmup: 60)
        let phase = began(engine.start())
        #expect(phase?.kind == .warmup)
        #expect(phase?.round == 1)
    }

    @Test("Skipping the warmup lands on the first work interval")
    func skipWarmup() {
        let (engine, clock) = makeEngine(prepare: 0, warmup: 60)
        engine.start()
        clock.advance(10)
        let phase = began(engine.skipPhase())
        #expect(phase?.kind == .work)
        #expect(phase?.round == 1)
        #expect(engine.elapsed == 60)
    }

    @Test("Skipping the last work interval now lands in the cooldown, not the finish")
    func skipLastWorkReachesCooldown() {
        // prepare 0 | work 20 (0-20) | rest 10 (20-30) | work 20 (30-50) | cooldown 60 (50-110)
        let (engine, clock) = makeEngine(prepare: 0, rounds: 2, cooldown: 60)
        engine.start()
        clock.advance(35)
        #expect(engine.position.phase?.kind == .work)

        let phase = began(engine.skipPhase())
        #expect(phase?.kind == .cooldown)
        #expect(phase?.round == 2)
        #expect(engine.status == .running)
        #expect(engine.elapsed == 50)
    }

    @Test("Skipping the cooldown finishes the run")
    func skipCooldownFinishes() {
        let (engine, clock) = makeEngine(prepare: 0, rounds: 1, cooldown: 60)
        engine.start()
        clock.advance(25)
        #expect(engine.position.phase?.kind == .cooldown)
        #expect(engine.skipPhase() == [.finished])
        #expect(engine.status == .finished)
    }

    @Test("Skipping repeatedly walks lead-in, warmup, the rounds and the cooldown in order")
    func skipWalksEveryPhase() {
        let (engine, _) = makeEngine(prepare: 5, warmup: 10, work: 20, rest: 10, rounds: 2, cooldown: 15)
        #expect(began(engine.start())?.kind == .prepare)
        var kinds: [IntervalPhase.Kind] = []
        while engine.status == .running {
            if let phase = began(engine.skipPhase()) { kinds.append(phase.kind) }
        }
        #expect(kinds == [.warmup, .work, .rest, .work, .cooldown])
        #expect(engine.status == .finished)
    }

    @Test("The warmup gets the 3-2-1 lead into the first work interval")
    func countdownEndsWarmup() {
        let (engine, clock) = makeEngine(prepare: 0, warmup: 10, work: 10, rest: 0, rounds: 1)
        engine.start()

        var cues: [Int] = []
        var workBeganAt: Int?
        for second in 1...10 {
            clock.advance(1)
            for event in engine.advance() {
                switch event {
                case .countdown(let remaining): cues.append(remaining)
                case .phaseBegan(let phase) where phase.kind == .work: workBeganAt = second
                default: break
                }
            }
        }
        #expect(cues == [3, 2, 1])
        #expect(workBeganAt == 10)
    }

    @Test("Restoring into the cooldown resumes there without replaying its start")
    func restoreIntoCooldown() {
        let (engine, clock) = makeEngine()
        let workout = IntervalWorkout(
            prepareSeconds: 5, warmupSeconds: 30, workSeconds: 20, restSeconds: 10, rounds: 3, cooldownSeconds: 120
        )
        // 5 + 30 + 3*20 + 2*10 = 115 before the cooldown; 150 s in is 35 s into it.
        engine.restore(anchor: clock.current.addingTimeInterval(-150), workout: workout, paused: nil)

        #expect(engine.status == .running)
        #expect(engine.position.phase?.kind == .cooldown)
        #expect(engine.position.phase?.round == 3)
        #expect(engine.position.remainingInPhase == 85)
        #expect(engine.advance().isEmpty)
    }
}
