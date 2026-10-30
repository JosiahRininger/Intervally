//
//  LiveActivityPresenterTests.swift
//  IntervallyPhoneTests
//

import ActivityKit
import Foundation
import Testing
@testable import IntervallyPhone

/// The Live Activity presenter against a stand-in for ActivityKit: its one chain of calls,
/// its reconcile at launch, a finished run's linger, and what it shows, held to 1.2's.
@Suite("Live Activity presenter")
@MainActor
struct LiveActivityPresenterTests {

    /// Hill Sprints, the 1.2 fixtures' run: a Sprint from 315 to 345 seconds, then a Walk.
    private static let plan = IntervalPlan(workout: Fixture.hillSprints12)

    private static func running(
        _ elapsed: TimeInterval, anchor: Date = Fixture.anchor12
    ) throws -> RunPresentation {
        try #require(RunPresentation(plan: plan, status: .running, anchor: anchor, elapsed: elapsed))
    }

    private static func paused(_ elapsed: TimeInterval) throws -> RunPresentation {
        try #require(RunPresentation(plan: plan, status: .paused, anchor: nil, elapsed: elapsed))
    }

    private static func finished() throws -> RunPresentation {
        try #require(RunPresentation(plan: plan, status: .finished, anchor: nil, elapsed: plan.totalDuration))
    }

    /// What the Lock Screen is sent for `run`, in Classic.
    private static func shown(_ run: RunPresentation) -> FakeLiveActivityHost.Shown {
        let state = RunActivityAttributes.ContentState(run, theme: .classic)
        return FakeLiveActivityHost.Shown(state: state, staleDate: state.staleDate)
    }

    @Test("A burst of changes as a run begins starts one activity, and the rest update it")
    func startRequestsOnce() async throws {
        // The last run's finished card, still lingering.
        let lingering = HostedActivity(id: "lingering", state: .ended)
        let host = FakeLiveActivityHost(activities: [lingering])
        let presenter = LiveActivityPresenter(host: host) { .classic }
        let first = try Self.running(330.5), second = try Self.running(345.5), third = try Self.paused(350)

        presenter.present(first)
        presenter.present(second)
        presenter.present(third)
        await presenter.settled()

        #expect(host.calls == [
            // Replaced by the new run, not left beside it.
            .end("lingering", nil, .immediate),
            .request("1", workout: "Hill Sprints", Self.shown(first)),
            .update("1", Self.shown(second)),
            .update("1", Self.shown(third)),
        ])
        #expect(host.activities == [HostedActivity(id: "1", state: .active)])

        // With Live Activities off in Settings, nothing starts, and nothing ends to make room.
        let off = FakeLiveActivityHost(activities: [lingering], enabled: false)
        let refused = LiveActivityPresenter(host: off) { .classic }
        refused.present(first)
        refused.present(second)
        await refused.settled()
        #expect(off.calls.isEmpty)
    }

    @Test("A quick pause and resume reach the Lock Screen in the order they were made, however long each takes")
    func rapidUpdatesApplyInOrder() async throws {
        // The pause is slow to reach the system and the resume isn't: sent as loose tasks,
        // the resume would land first and leave the Lock Screen paused.
        let host = FakeLiveActivityHost(updateDuration: { $0 == 1 ? .milliseconds(150) : .zero })
        let presenter = LiveActivityPresenter(host: host) { .classic }
        let start = try Self.running(330.5), pause = try Self.paused(340)
        let resume = try Self.running(340, anchor: Fixture.anchor12.addingTimeInterval(10))

        presenter.present(start)
        presenter.present(pause)
        presenter.present(resume)
        await presenter.settled()

        #expect(host.calls == [
            .request("1", workout: "Hill Sprints", Self.shown(start)),
            .update("1", Self.shown(pause)),
            .update("1", Self.shown(resume)),
        ])
    }

    @Test("At launch, a run coming back keeps the newest activity still showing, and every other one ends at once")
    func reconcileEndsStrays() async throws {
        let earlier = [
            HostedActivity(id: "older", state: .active),
            HostedActivity(id: "finished", state: .ended),
            HostedActivity(id: "newest", state: .stale),
        ]
        let host = FakeLiveActivityHost(activities: earlier)
        let presenter = LiveActivityPresenter(host: host) { .classic }
        let restored = try Self.paused(340)

        presenter.reconcile(hasRun: true)
        presenter.present(restored)
        await presenter.settled()

        // The restored run's first change lands on the one kept, with nothing new requested.
        #expect(host.calls == [
            .end("older", nil, .immediate),
            .end("finished", nil, .immediate),
            .update("newest", Self.shown(restored)),
        ])
        #expect(host.activities.map(\.id) == ["newest"])

        // With no run to come back, every one ends, stale or not.
        let orphaned = FakeLiveActivityHost(activities: earlier)
        let relaunched = LiveActivityPresenter(host: orphaned) { .classic }
        relaunched.reconcile(hasRun: false)
        await relaunched.settled()
        #expect(orphaned.calls == earlier.map { .end($0.id, nil, .immediate) })
        #expect(orphaned.activities.isEmpty)
    }

    @Test("A finished run's activity ends showing the finish and stays 15 minutes, until the next run")
    func finishLingers15Minutes() async throws {
        let host = FakeLiveActivityHost()
        let presenter = LiveActivityPresenter(host: host) { .classic }
        let finished = try Self.finished()
        presenter.present(try Self.running(1200))

        let before = Date()
        presenter.present(finished)
        await presenter.settled()
        let after = Date()

        let ended = try #require(host.calls.last)
        guard case .end("1", let shown, .after(let dismissed)) = ended else {
            Issue.record("Not ended to linger: \(ended)")
            return
        }
        #expect(shown == Self.shown(finished))
        #expect((before.addingTimeInterval(15 * 60)...after.addingTimeInterval(15 * 60)).contains(dismissed))
        #expect(host.activities == [HostedActivity(id: "1", state: .ended)])

        // Closing the finished run leaves the card where it is; the next run replaces it.
        presenter.present(nil)
        await presenter.settled()
        #expect(host.calls.count == 2)
        let next = try Self.running(330.5)
        presenter.present(next)
        await presenter.settled()
        #expect(Array(host.calls.dropFirst(2)) == [
            .end("1", nil, .immediate),
            .request("2", workout: "Hill Sprints", Self.shown(next)),
        ])
    }

    @Test("Closing a run ends its activity at once, and the next run starts a new one")
    func closeEndsImmediately() async throws {
        let host = FakeLiveActivityHost()
        let presenter = LiveActivityPresenter(host: host) { .classic }
        let run = try Self.running(330.5)

        presenter.present(run)
        presenter.present(nil)
        await presenter.settled()
        #expect(host.calls == [
            .request("1", workout: "Hill Sprints", Self.shown(run)),
            .end("1", nil, .immediate),
        ])
        #expect(host.activities.isEmpty)

        // A close with nothing showing ends nothing more.
        presenter.present(nil)
        await presenter.settled()
        #expect(host.calls.count == 2)

        presenter.present(run)
        await presenter.settled()
        #expect(host.calls.last == .request("2", workout: "Hill Sprints", Self.shown(run)))
    }

    @Test("A saved run shows what 1.2 showed, running, paused and finished, and the presenter sends it so")
    func contentMatchesGoldenFixture() async throws {
        let golden = GoldenFixtureTests.liveActivityStates12
        let running = try #require(golden["running"])
        let paused = try #require(golden["paused"])
        let finished = try #require(golden["finished"])
        let now = Fixture.anchor12.addingTimeInterval(330.5)
        #expect(LiveActivityPresenter.content(for: Fixture.runningSnapshot12, now: now, theme: .pastel) == running)
        #expect(LiveActivityPresenter.content(for: Fixture.pausedSnapshot12, now: now, theme: .classic) == paused)
        // Saved running and brought back after its end, it shows the finish.
        let end = Fixture.anchor12.addingTimeInterval(Self.plan.totalDuration)
        #expect(LiveActivityPresenter.content(for: Fixture.runningSnapshot12, now: end, theme: .classic) == finished)

        // The same run, as the presenter sends it: stale 2 seconds after its Sprint runs out.
        let host = FakeLiveActivityHost()
        let presenter = LiveActivityPresenter(host: host) { .pastel }
        presenter.present(try Self.running(330.5))
        await presenter.settled()
        #expect(host.calls == [
            .request("1", workout: "Hill Sprints", .init(state: running, staleDate: Fixture.anchor12.addingTimeInterval(347))),
        ])
    }
}
