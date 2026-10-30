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

    /// How long after `offset` seconds into the run each alert goes off.
    private func delays(at offset: TimeInterval) -> [TimeInterval] {
        requests(at: offset).map { $0.fireDate.timeIntervalSince(anchor.addingTimeInterval(offset)) }
    }

    @Test("From the start, every boundary after the first phase is scheduled, plus the finish")
    func schedulesEveryBoundary() {
        // The first phase is already running, so it needs no alert; 10/40/55 are the
        // remaining boundaries and 85 is the finish.
        #expect(delays(at: 0) == [10, 40, 55, 85])
    }

    @Test("Boundaries already passed are skipped rather than fired immediately")
    func skipsPassedBoundaries() {
        // A UNTimeIntervalNotificationTrigger needs a strictly positive interval; a negative
        // delay would either throw or fire at once.
        let remaining = delays(at: 42)
        #expect(remaining == [13, 43])
        #expect(remaining.allSatisfy { $0 > 0 })
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

    @Test("Each alert is named for the phase it starts, or the finish, as 1.2 named it")
    func identifiersNameThePhase() {
        #expect(NotificationScheduler.identifier(forPhase: 3) == "interval-boundary-3")
        #expect(NotificationScheduler.finishIdentifier == "interval-boundary-finish")
        let expected = [1, 2, 3].map(NotificationScheduler.identifier(forPhase:)) + [NotificationScheduler.finishIdentifier]
        #expect(requests(at: 0).map(\.identifier) == expected)
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
        #expect(all[0].fireDate == anchor.addingTimeInterval(20))
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
        #expect(all.map { $0.fireDate.timeIntervalSince(anchor) } == [10, 310, 340, 355, 385, 505])
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
        #expect(all.map { $0.fireDate.timeIntervalSince(anchor) } == [60, 80])
    }

    @Test("The completion alert waits for the end of the cooldown")
    func finishAfterCooldown() throws {
        let all = NotificationScheduler.requests(plan: plan, anchor: anchor, now: anchor)
        let finish = try #require(all.last)
        let cooldown = try #require(plan.phases.last)
        #expect(cooldown.kind == .cooldown)
        #expect(finish.title == "Workout Complete")
        #expect(finish.fireDate == anchor.addingTimeInterval(cooldown.end))
        #expect(finish.fireDate == anchor.addingTimeInterval(plan.totalDuration))
    }
}

// MARK: - The window

/// The plans and names the window and scheduling tests share.
private enum Plans {
    /// prepare 10 | work 30 (10-40) | rest 15 (40-55) | work 30 (55-85)
    static let short = IntervalPlan(
        workout: IntervalWorkout(prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 2)
    )
    /// The longest plan the app allows: 200 phases, so 199 changes and the finish, far over
    /// the limit.
    static let longest = IntervalPlan(workout: IntervalWorkout(
        prepareSeconds: 10, warmupSeconds: 60, workSeconds: 5, restSeconds: 5, rounds: 99, cooldownSeconds: 60
    ))
    static let anchor = Date(timeIntervalSinceReferenceDate: 500_000)

    /// The short plan's alerts: its three changes and the finish.
    static let work1 = NotificationScheduler.identifier(forPhase: 1)
    static let rest1 = NotificationScheduler.identifier(forPhase: 2)
    static let work2 = NotificationScheduler.identifier(forPhase: 3)
    static let finish = NotificationScheduler.finishIdentifier
}

@Suite("Boundary notifications: the window")
struct NotificationWindowTests {

    @Test("Over the limit, the last slot is still the finish: the next 59 changes, then Workout Complete")
    func finishKeptWhenOverLimit() async throws {
        let anchor = Plans.anchor
        #expect(Plans.longest.phases.count == 200)
        let all = NotificationScheduler.requests(plan: Plans.longest, anchor: anchor, now: anchor, limit: 60)
        #expect(all.count == 60)
        let finish = try #require(all.last)
        #expect(finish.identifier == Plans.finish)
        #expect(finish.title == "Workout Complete")
        #expect(finish.fireDate == anchor.addingTimeInterval(Plans.longest.totalDuration))
        #expect(all.dropLast().map(\.identifier) == (1...59).map(NotificationScheduler.identifier(forPhase:)))

        // The default limit is the same, and that is what reaches the center.
        #expect(NotificationScheduler.requests(plan: Plans.longest, anchor: anchor, now: anchor) == all)
        let center = FakeNotificationCenter(now: anchor)
        await NotificationScheduler(center: center, now: { center.now }).schedule(plan: Plans.longest, anchor: anchor)
        #expect(center.pending.map(\.identifier) == all.map(\.identifier))
    }

    @Test("A limit of one keeps the finish alone, and a limit of none keeps nothing")
    func finishKeptAtTheSmallestLimits() {
        let anchor = Plans.anchor
        #expect(NotificationScheduler.requests(plan: Plans.longest, anchor: anchor, now: anchor, limit: 1).map(\.identifier) == [Plans.finish])
        #expect(NotificationScheduler.requests(plan: Plans.longest, anchor: anchor, now: anchor, limit: 0).isEmpty)
    }

    @Test("A change closer than the minimum lead is left out, and so is a finish that close")
    func minimumLeadLeavesOutNearBoundary() async {
        let anchor = Plans.anchor
        func identifiers(at offset: TimeInterval, lead: TimeInterval? = nil) -> [String] {
            let now = anchor.addingTimeInterval(offset)
            let requests = if let lead {
                NotificationScheduler.requests(plan: Plans.short, anchor: anchor, now: now, minimumLead: lead)
            } else {
                NotificationScheduler.requests(plan: Plans.short, anchor: anchor, now: now)
            }
            return requests.map(\.identifier)
        }
        // Two seconds before the first work interval.
        #expect(identifiers(at: 8, lead: 2.5) == [Plans.rest1, Plans.work2, Plans.finish])
        #expect(identifiers(at: 8, lead: 0.5) == [Plans.work1, Plans.rest1, Plans.work2, Plans.finish])
        // Left out a little further off, too, with a longer lead.
        #expect(identifiers(at: 7.25, lead: 2.5) == [Plans.work1, Plans.rest1, Plans.work2, Plans.finish])
        #expect(identifiers(at: 7.5, lead: 2.5) == [Plans.rest1, Plans.work2, Plans.finish])
        // By default the lead is 1.2's half second, a change exactly that far off left out.
        #expect(identifiers(at: 9.25) == [Plans.work1, Plans.rest1, Plans.work2, Plans.finish])
        #expect(identifiers(at: 9.5) == [Plans.rest1, Plans.work2, Plans.finish])
        // Two seconds before the finish.
        #expect(identifiers(at: 83, lead: 2.5).isEmpty)
        #expect(identifiers(at: 83) == [Plans.finish])

        // A schedule passes its lead on.
        let center = FakeNotificationCenter(now: anchor.addingTimeInterval(8))
        await NotificationScheduler(center: center, now: { center.now })
            .schedule(plan: Plans.short, anchor: anchor, minimumLead: 2.5)
        #expect(center.pending.map(\.identifier) == [Plans.rest1, Plans.work2, Plans.finish])
    }

    @Test("A long workout asks to be topped up once fewer than ten of its scheduled changes are still to come")
    func needsTopUpWhenTenRemain() async {
        let anchor = Plans.anchor
        let center = FakeNotificationCenter(now: anchor)
        let scheduler = NotificationScheduler(center: center, now: { center.now })
        await scheduler.schedule(plan: Plans.longest, anchor: anchor)
        let changes = center.pending.filter { $0.identifier != Plans.finish }
        #expect(changes.count == 59)

        #expect(await scheduler.needsTopUp(now: anchor) == false)
        // As the 49th goes off, ten are still to come: enough.
        #expect(await scheduler.needsTopUp(now: changes[48].fireDate) == false)
        // As the 50th goes off, nine are, with the finish not counted among them.
        #expect(await scheduler.needsTopUp(now: changes[49].fireDate))
        #expect(await scheduler.needsTopUp(now: changes[58].fireDate))
        // Topping up then covers the next 59, and asks for nothing more for now.
        center.advance(by: changes[49].fireDate.timeIntervalSince(anchor))
        await scheduler.schedule(plan: Plans.longest, anchor: anchor)
        #expect(await scheduler.needsTopUp(now: center.now) == false)
        #expect(center.pending.filter { $0.identifier != Plans.finish }.count == 59)
        #expect(center.pending.first?.identifier == NotificationScheduler.identifier(forPhase: 51))
        // Past the plan's last change, there is nothing left to top up.
        let lastChange = anchor.addingTimeInterval(Plans.longest.phases[199].start)
        #expect(await scheduler.needsTopUp(now: lastChange) == false)

        // Cancelled, nothing is wanted.
        await scheduler.cancelAll()
        #expect(await scheduler.needsTopUp(now: changes[58].fireDate) == false)
    }

    @Test("A disarmed change no longer counts as still to come, so the top-up comes one change sooner")
    func disarmedChangeBringsTopUpSooner() async {
        let anchor = Plans.anchor
        let center = FakeNotificationCenter(now: anchor)
        let scheduler = NotificationScheduler(center: center, now: { center.now })
        await scheduler.schedule(plan: Plans.longest, anchor: anchor)
        let changes = center.pending.filter { $0.identifier != Plans.finish }
        #expect(await scheduler.needsTopUp(now: changes[48].fireDate) == false)

        // One of the last ten comes down: nine alerts are left to come, not ten.
        await scheduler.disarm(identifier: changes[55].identifier)
        #expect(await scheduler.needsTopUp(now: changes[48].fireDate))
        #expect(await scheduler.needsTopUp(now: changes[47].fireDate) == false)
        // A name that isn't the run's changes nothing.
        await scheduler.disarm(identifier: "training-reminder-2026-10-30")
        #expect(await scheduler.needsTopUp(now: changes[47].fireDate) == false)
    }

    @Test("A workout that fits in one schedule never asks to be topped up")
    func fittingPlanNeverNeedsTopUp() async {
        let anchor = Plans.anchor
        let center = FakeNotificationCenter(now: anchor)
        let scheduler = NotificationScheduler(center: center, now: { center.now })
        await scheduler.schedule(plan: Plans.short, anchor: anchor)
        for offset in [0.0, 20, 60, 84, 90] {
            #expect(await scheduler.needsTopUp(now: anchor.addingTimeInterval(offset)) == false, "at \(offset) s")
        }
    }
}

// MARK: - Scheduling

@Suite("Boundary notifications: handing them to the system", .timeLimit(.minutes(1)))
struct NotificationSchedulingTests {

    private let plan = Plans.short
    private let anchor = Plans.anchor

    private func makeScheduler(_ center: FakeNotificationCenter) -> NotificationScheduler {
        NotificationScheduler(center: center, now: { center.now })
    }

    @Test("Each alert's delay is worked out at its own add, so slow adds make none of them late")
    func intervalComputedAtAdd() async {
        let center = FakeNotificationCenter(now: anchor, addDuration: 2)
        await makeScheduler(center).schedule(plan: plan, anchor: anchor)
        // Each add takes two seconds, so each delay is two seconds shorter than the last
        // one's would make it. Worked out up front, the rest went off 2 s late, the second
        // work interval 4 s and the finish 6 s.
        #expect(center.added.map(\.interval) == [10, 38, 51, 79])
        #expect(center.added.map(\.fireDate) == [10, 40, 55, 85].map { anchor.addingTimeInterval($0) })
    }

    @Test("What is left out is decided after the cancel before it, not before")
    func intervalComputedAfterTheCancel() async {
        // Two seconds before the first work interval, something is pending, so the cancel
        // takes its time over it.
        let center = FakeNotificationCenter(now: anchor.addingTimeInterval(8))
        let scheduler = makeScheduler(center)
        await scheduler.schedule(plan: plan, anchor: anchor)
        let earlier = center.added.count
        let look = center.holdListing(center.listings + 1)
        let scheduling = Task { await scheduler.schedule(plan: plan, anchor: anchor) }
        await look.reached()
        // By the time the cancel hears back, the work interval is a quarter second off,
        // inside the lead. Decided before the cancel, it was two seconds off and went back up,
        // which is how a reschedule would bring back an alert taken down just before its
        // change.
        center.advance(by: 1.75)
        look.release()
        await scheduling.value
        let added = center.added.dropFirst(earlier)
        #expect(added.map(\.identifier) == [Plans.rest1, Plans.work2, Plans.finish])
        #expect(added.map(\.interval) == [30.25, 45.25, 75.25])
    }

    @Test("An alert more than a second past by its add is left out")
    func stalePastRequestsSkipped() async {
        let center = FakeNotificationCenter(now: anchor)
        let first = center.holdAdd(1)
        let scheduler = makeScheduler(center)
        let scheduling = Task { await scheduler.schedule(plan: plan, anchor: anchor) }
        // Suspended for 41.5 s after the first add: the rest began a second and a half ago.
        await first.reached()
        center.advance(by: 41.5)
        first.release()
        await scheduling.value
        #expect(center.added.map(\.identifier) == [Plans.work1, Plans.work2, Plans.finish])
        #expect(center.added.map(\.interval) == [10, 13.5, 43.5])
    }

    @Test("An alert only just past by its add still goes off, at once")
    func justPastRequestsFireAtOnce() async {
        for late in [0.75, 1.0] {
            let center = FakeNotificationCenter(now: anchor)
            let first = center.holdAdd(1)
            let scheduler = makeScheduler(center)
            let scheduling = Task { await scheduler.schedule(plan: plan, anchor: anchor) }
            await first.reached()
            center.advance(by: 40 + late)
            first.release()
            await scheduling.value
            #expect(center.added.map(\.identifier) == [Plans.work1, Plans.rest1, Plans.work2, Plans.finish], "\(late) s late")
            #expect(center.added.map(\.interval) == [10, 0.5, 15 - late, 45 - late], "\(late) s late")
        }
    }

    @Test("A newer schedule supersedes one still adding: the older adds nothing more once it hears back")
    func newerEpochSupersedesOlder() async {
        let center = FakeNotificationCenter(now: anchor)
        let scheduler = makeScheduler(center)
        // The older schedule's second add has landed, and its answer is on the way back.
        let answer = center.holdAdd(2)
        let older = Task { await scheduler.schedule(plan: plan, anchor: anchor) }
        await answer.reached()
        // Resumed 30 s later than the older one planned for: every alert moves on.
        let resumed = anchor.addingTimeInterval(30)
        await scheduler.schedule(plan: plan, anchor: resumed)
        answer.release()
        await older.value

        let newer = NotificationScheduler.requests(plan: plan, anchor: resumed, now: anchor)
        #expect(center.pending.map(\.identifier) == newer.map(\.identifier))
        #expect(center.pending.map(\.fireDate) == newer.map(\.fireDate))
        // Two adds from the older schedule, then only the newer one's.
        #expect(center.added.count == 2 + newer.count)
    }

    @Test("A cancel looks twice, so an add that lands while it looks the first time still comes down")
    func doubleCancelRemovesLateAdds() async {
        let center = FakeNotificationCenter(now: anchor)
        let scheduler = makeScheduler(center)
        // The second add is still on its way to the server.
        let inFlight = center.holdAdd(2, landed: false)
        let scheduling = Task { await scheduler.schedule(plan: plan, anchor: anchor) }
        await inFlight.reached()
        // The cancel's first look at what is pending is taken, and answered only once that
        // add has landed.
        let firstLook = center.holdListing(center.listings + 1)
        let cancelling = Task { await scheduler.cancelAll() }
        await firstLook.reached()
        inFlight.release()
        await scheduling.value
        #expect(center.pending.map(\.identifier) == [Plans.work1, Plans.rest1])

        firstLook.release()
        await cancelling.value
        #expect(center.pending.isEmpty)
        #expect(center.removed == [[Plans.work1], [Plans.rest1]])
        // Superseded, the schedule added nothing after the add it was waiting on.
        #expect(center.added.count == 2)
    }

    @Test("Disarming takes down exactly the alert it names, and nothing that isn't the run's")
    func disarmRemovesExactlyOne() async {
        let reminder = "training-reminder-2026-10-30"
        let center = FakeNotificationCenter(now: anchor, alreadyPending: [reminder])
        let scheduler = makeScheduler(center)
        await scheduler.schedule(plan: plan, anchor: anchor)
        #expect(center.pending.map(\.identifier) == [reminder, Plans.work1, Plans.rest1, Plans.work2, Plans.finish])

        await scheduler.disarm(identifier: Plans.rest1)
        #expect(center.pending.map(\.identifier) == [reminder, Plans.work1, Plans.work2, Plans.finish])
        await scheduler.disarm(identifier: reminder)
        await scheduler.disarm(identifier: Plans.finish)
        #expect(center.pending.map(\.identifier) == [reminder, Plans.work1, Plans.work2])
        #expect(center.removed == [[Plans.rest1], [Plans.finish]])
    }

    @Test("Disarming leaves a schedule that is still adding to carry on, as a cancel would not")
    func disarmKeepsTheScheduleGoing() async {
        let center = FakeNotificationCenter(now: anchor)
        let scheduler = makeScheduler(center)
        let answer = center.holdAdd(2)
        let scheduling = Task { await scheduler.schedule(plan: plan, anchor: anchor) }
        await answer.reached()
        await scheduler.disarm(identifier: Plans.work1)
        answer.release()
        await scheduling.value
        #expect(center.pending.map(\.identifier) == [Plans.rest1, Plans.work2, Plans.finish])
    }

    @Test("A cancel, and the one each schedule starts with, takes down the run's alerts and nothing else")
    func onlyPrefixedIdentifiersCancelled() async {
        let others = ["training-reminder-2026-10-30", "intervally-reminder"]
        let center = FakeNotificationCenter(now: anchor, alreadyPending: others)
        let scheduler = makeScheduler(center)
        await scheduler.schedule(plan: plan, anchor: anchor)
        await scheduler.schedule(plan: plan, anchor: anchor.addingTimeInterval(5))
        #expect(center.pending.map(\.identifier) == others + [Plans.work1, Plans.rest1, Plans.work2, Plans.finish])

        await scheduler.cancelAll()
        #expect(center.pending.map(\.identifier) == others)
        #expect(center.removed.joined().allSatisfy { $0.hasPrefix(NotificationScheduler.prefix) })
    }

    @Test("Permission is asked of the center the scheduler is given, for alerts and sounds")
    func authorizationGoesThroughTheCenter() async {
        let center = FakeNotificationCenter(now: anchor, granted: false)
        #expect(await makeScheduler(center).requestAuthorization() == false)
        #expect(center.requestedOptions == [[.alert, .sound]])
    }
}
