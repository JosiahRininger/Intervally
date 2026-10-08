//
//  NotificationSchedulerTests.swift
//  IntervallyTests
//

import Testing
import Foundation
@testable import Intervally

@Suite("Boundary notification derivation")
struct NotificationSchedulerTests {

    /// prepare 10 | work 30 (10-40) | rest 15 (40-55) | work 30 (55-85)
    private let plan = IntervalPlan(
        workout: IntervalWorkout(prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 2)
    )
    private let anchor = Date(timeIntervalSinceReferenceDate: 500_000)

    private func requests(at offset: TimeInterval, limit: Int = 60) -> [NotificationScheduler.BoundaryRequest] {
        NotificationScheduler.requests(
            plan: plan, anchor: anchor, now: anchor.addingTimeInterval(offset), limit: limit
        )
    }

    @Test("From the start, every boundary after the first phase is scheduled, plus the finish")
    func schedulesEveryBoundary() {
        let delays = requests(at: 0).map(\.delay)
        // The first phase is already running, so it needs no alert; 10/40/55 are the
        // remaining boundaries and 85 is the finish.
        #expect(delays == [10, 40, 55, 85])
    }

    @Test("Boundaries already passed are skipped rather than fired immediately")
    func skipsPassedBoundaries() {
        // A UNTimeIntervalNotificationTrigger needs a strictly positive interval; a negative
        // delay would either throw or fire at once.
        let delays = requests(at: 42).map(\.delay)
        #expect(delays == [13, 43])
        #expect(delays.allSatisfy { $0 > 0 })
    }

    @Test("Once the run is over nothing is scheduled")
    func nothingAfterTheEnd() {
        #expect(requests(at: 85).isEmpty)
        #expect(requests(at: 10_000).isEmpty)
    }

    @Test("Identifiers are unique and all carry the shared prefix so cancellation finds them")
    func identifiersAreUniqueAndPrefixed() {
        let ids = requests(at: 0).map(\.identifier)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0.hasPrefix(NotificationScheduler.prefix) })
    }

    @Test("Each alert says what is starting")
    func bodiesDescribeThePhase() {
        let all = requests(at: 0)
        #expect(all[0].title == "Work")
        #expect(all[0].body == "Round 1 of 2")
        #expect(all[1].title == "Rest")
        #expect(all[2].title == "Work")
        #expect(all[2].body == "Round 2 of 2")
        #expect(all.last?.title == "Workout Complete")
    }

    @Test("The schedule is capped, so a long workout cannot exhaust the pending-request budget")
    func respectsTheLimit() {
        let long = IntervalPlan(
            workout: IntervalWorkout(prepareSeconds: 0, workSeconds: 5, restSeconds: 5, rounds: 99)
        )
        let capped = NotificationScheduler.requests(
            plan: long, anchor: anchor, now: anchor, limit: 60
        )
        #expect(capped.count == 60)
    }

    @Test("A one-round workout still gets its completion alert")
    func singleRoundStillFinishes() {
        let single = IntervalPlan(
            workout: IntervalWorkout(prepareSeconds: 0, workSeconds: 20, restSeconds: 0, rounds: 1)
        )
        let all = NotificationScheduler.requests(plan: single, anchor: anchor, now: anchor)
        #expect(all.count == 1)
        #expect(all[0].title == "Workout Complete")
        #expect(all[0].delay == 20)
    }
}

@Suite("Boundary notifications — warmup and cooldown")
struct NotificationSchedulerBookendTests {

    /// prepare 10 | warmup 300 (10-310) | work 30 (310-340) | rest 15 (340-355)
    /// | work 30 (355-385) | cooldown 120 (385-505)
    private let plan = IntervalPlan(workout: IntervalWorkout(
        prepareSeconds: 10, warmupSeconds: 300, workSeconds: 30, restSeconds: 15, rounds: 2, cooldownSeconds: 120
    ))
    private let anchor = Date(timeIntervalSinceReferenceDate: 500_000)

    @Test("The warmup and cooldown say what they are, never Rest or Round 0")
    func bookendAlerts() throws {
        let all = NotificationScheduler.requests(plan: plan, anchor: anchor, now: anchor)
        #expect(all.map(\.delay) == [10, 310, 340, 355, 385, 505])
        #expect(all.map(\.title) == ["Warmup", "Work", "Rest", "Work", "Cooldown", "Workout Complete"])

        #expect(all[0].body == "Easy for 5:00")
        #expect(all[4].body == "Intervals done. Easy for 2:00")
        // The intervals between read exactly as they always have.
        #expect(all[1].body == "Round 1 of 2")
        #expect(all[2].body == "Rest 15s")
        #expect(all[5].body == "2 rounds done.")
        #expect(all.filter { $0.body.hasPrefix("Rest") }.count == 1)
        #expect(all.allSatisfy { !$0.body.contains("Round 0") })
    }

    @Test("A warmup that opens the workout is already under way, so it is not alerted")
    func openingWarmupNotAlerted() {
        let opening = IntervalPlan(workout: IntervalWorkout(
            prepareSeconds: 0, warmupSeconds: 60, workSeconds: 20, restSeconds: 0, rounds: 1
        ))
        let all = NotificationScheduler.requests(plan: opening, anchor: anchor, now: anchor)
        #expect(all.map(\.title) == ["Work", "Workout Complete"])
        #expect(all.map(\.delay) == [60, 80])
    }

    @Test("The completion alert waits for the end of the cooldown")
    func finishAfterCooldown() throws {
        let all = NotificationScheduler.requests(plan: plan, anchor: anchor, now: anchor)
        let finish = try #require(all.last)
        let cooldown = try #require(plan.phases.last)
        #expect(cooldown.kind == .cooldown)
        #expect(finish.title == "Workout Complete")
        #expect(finish.delay == cooldown.end)
        #expect(finish.delay == plan.totalDuration)
    }
}
