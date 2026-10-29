//
//  IntervalPlanDeadlineTests.swift
//  IntervallyTests
//

import Testing
import Foundation
@testable import Intervally

/// A clock a test sets to the millisecond, counted from the reference date, so the engine's
/// elapsed time is exactly the figure the test names.
@MainActor
private final class MillisecondClock {
    var milliseconds = 0
    var date: Date { Date(timeIntervalSinceReferenceDate: TimeInterval(milliseconds) / 1000) }
}

@Suite("Interval plan deadlines")
@MainActor
struct IntervalPlanDeadlineTests {

    /// Every deadline of `plan` in order, from the start to the finish.
    private func deadlines(of plan: IntervalPlan) -> [TimeInterval] {
        var all: [TimeInterval] = []
        var elapsed: TimeInterval = 0
        while let next = plan.nextEventElapsed(afterElapsed: elapsed) {
            all.append(next)
            elapsed = next
        }
        return all
    }

    /// What reaching `deadline` should announce, worked out from the phases alone.
    private func event(at deadline: TimeInterval, in plan: IntervalPlan) -> TimerEvent? {
        guard let index = plan.phases.lastIndex(where: { $0.start < deadline }) else { return nil }
        let phase = plan.phases[index]
        guard deadline == phase.end else { return .countdown(secondsRemaining: Int(phase.end - deadline)) }
        return index + 1 < plan.phases.count ? .phaseBegan(plan.phases[index + 1]) : .finished
    }

    @Test("Each deadline is where the engine's next event lands, to the millisecond, and nothing lands between",
          arguments: SyncDocument.starterWorkouts + [
              // Pro's bookends, and a rest just long enough for all three countdown seconds.
              IntervalWorkout(name: "Bookends", prepareSeconds: 5, warmupSeconds: 60, workSeconds: 5,
                              restSeconds: 4, rounds: 3, cooldownSeconds: 30),
          ])
    func nextEventAgreesWithAdvanceRounding(workout: IntervalWorkout) throws {
        let plan = IntervalPlan(workout: workout)
        let deadlines = deadlines(of: plan)
        #expect(deadlines.last == plan.totalDuration)
        let clock = MillisecondClock()
        let engine = TimerEngine(workout: workout)
        engine.now = { clock.date }
        engine.start()

        // A millisecond at a time for 20 ms either side of every deadline, and every 100 ms
        // between them.
        let near = Set(deadlines.flatMap { deadline in (-20...20).map { Int(deadline * 1000) + $0 } })
        var previous: TimeInterval = 0
        for step in 1...(Int(plan.totalDuration * 1000) + 20) where near.contains(step) || step.isMultiple(of: 100) {
            let now = TimeInterval(step) / 1000
            let due = plan.nextEventElapsed(afterElapsed: previous)
            clock.milliseconds = step
            let events = engine.advance()
            if let due, due <= now {
                let expected = try #require(event(at: due, in: plan))
                guard events == [expected] else {
                    Issue.record("\(workout.name): \(events) at \(now) s, where \(expected) was due at \(due) s")
                    return
                }
            } else {
                guard events.isEmpty else {
                    Issue.record("\(workout.name): \(events) at \(now) s, with nothing due until \(due.map { "\($0) s" } ?? "never")")
                    return
                }
            }
            previous = now
        }
        #expect(engine.status == .finished)
    }

    @Test("A countdown second at or before its phase's start is no deadline, and the next wake plays it")
    func shortPhaseSkipsImpossibleTicks() {
        // prepare 2 | work 5 | rest 3 | work 5: room in the lead-in for 1 alone, in the rest for 2 and 1.
        let workout = IntervalWorkout(prepareSeconds: 2, workSeconds: 5, restSeconds: 3, rounds: 2)
        let plan = IntervalPlan(workout: workout)
        #expect(deadlines(of: plan) == [1, 2, 4, 5, 6, 7, 8, 9, 10, 12, 13, 14, 15])
        // work 5 | rest 1 | work 5: a one-second rest is its end alone.
        let oneSecondRest = IntervalPlan(workout: IntervalWorkout(prepareSeconds: 0, workSeconds: 5, restSeconds: 1, rounds: 2))
        #expect(deadlines(of: oneSecondRest) == [2, 3, 4, 5, 6, 8, 9, 10, 11])
        // Before the start, the first deadline is still one inside the first phase.
        #expect(plan.nextEventElapsed(afterElapsed: -5) == 1)

        // The rest's 3 comes with its start, so the change stands alone and the wake half a
        // second later, the ticker's longest sleep, plays it.
        let clock = MillisecondClock()
        let engine = TimerEngine(workout: workout)
        engine.now = { clock.date }
        engine.start()
        clock.milliseconds = 7_000
        #expect(engine.advance() == [.phaseBegan(plan.phases[2])])
        clock.milliseconds = 7_500
        #expect(engine.advance() == [.countdown(secondsRemaining: 3)])
    }

    @Test("Nothing is due at or after the finish; just before it, the finish is")
    func nilAtAndAfterTotal() {
        // prepare 10 | work 30 | rest 15 | work 30 (total 85)
        let plan = IntervalPlan(workout: IntervalWorkout(prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 2))
        #expect(plan.nextEventElapsed(afterElapsed: 85) == nil)
        #expect(plan.nextEventElapsed(afterElapsed: 85.001) == nil)
        #expect(plan.nextEventElapsed(afterElapsed: 10_000) == nil)
        #expect(plan.nextEventElapsed(afterElapsed: 84) == 85, "Past the last countdown second, the finish")
        #expect(plan.nextEventElapsed(afterElapsed: 84.999) == 85)
        // At a boundary the next phase already counts: its first countdown second.
        #expect(plan.nextEventElapsed(afterElapsed: 10) == 37)
    }
}
