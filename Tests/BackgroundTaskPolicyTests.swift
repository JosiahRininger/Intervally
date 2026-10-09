//
//  BackgroundTaskPolicyTests.swift
//  IntervallyTests
//

import Foundation
import Testing
@testable import Intervally

/// Stands in for a `WKWatchConnectivityRefreshBackgroundTask`, which only the system makes.
@MainActor
private final class FakeBackgroundTask: BackgroundTaskCompleting {
    private(set) var completions: [Bool] = []
    func setTaskCompletedWithSnapshot(_ refreshSnapshot: Bool) {
        completions.append(refreshSnapshot)
    }
}

/// When the watch hands a WatchConnectivity wake back, and that it always does.
@Suite("Background task policy")
@MainActor
struct BackgroundTaskPolicyTests {

    private static let settled = SyncActivity(isActive: true, isActivated: true, hasContentPending: false, deliveriesInFlight: 0)

    private static func activity(
        active: Bool = true,
        activated: Bool = true,
        pending: Bool = false,
        inFlight: Int = 0
    ) -> SyncActivity {
        SyncActivity(isActive: active, isActivated: activated, hasContentPending: pending, deliveriesInFlight: inFlight)
    }

    // MARK: The decision

    @Test("Handed back once the session is activated, nothing is pending and every delivery has merged")
    func completesWhenSettled() {
        #expect(BackgroundTaskPolicy.shouldComplete(Self.settled, heldFor: .zero))
    }

    @Test("Kept while activation, pending content or a merge is still to come")
    func waitsWhileBusy() {
        #expect(!BackgroundTaskPolicy.shouldComplete(Self.activity(activated: false), heldFor: .seconds(1)))
        #expect(!BackgroundTaskPolicy.shouldComplete(Self.activity(pending: true), heldFor: .seconds(1)))
        #expect(!BackgroundTaskPolicy.shouldComplete(Self.activity(inFlight: 1), heldFor: .seconds(1)))
    }

    @Test("Never kept past the cap, whatever sync is doing")
    func cap() {
        let busy = Self.activity(activated: false, pending: true, inFlight: 2)
        #expect(BackgroundTaskPolicy.cap == .seconds(15))
        #expect(!BackgroundTaskPolicy.shouldComplete(busy, heldFor: .milliseconds(14_999)))
        #expect(BackgroundTaskPolicy.shouldComplete(busy, heldFor: .seconds(15)))
        #expect(BackgroundTaskPolicy.shouldComplete(busy, heldFor: .seconds(60)))
    }

    @Test("Handed back at once when sync never started, as in the unit-test host")
    func completesWhenSyncIsOff() {
        #expect(BackgroundTaskPolicy.shouldComplete(.inactive, heldFor: .zero))
        #expect(BackgroundTaskPolicy.shouldComplete(Self.activity(active: false, activated: false, pending: true), heldFor: .zero))
    }

    // MARK: Holding wakes

    /// A clock the test moves by hand.
    @MainActor
    private final class TestClock {
        var now = ContinuousClock.now
    }

    @Test("A wake is held while sync is busy, then handed back exactly once when it settles")
    func holdsUntilSettled() {
        var activity = Self.activity(activated: false)
        let clock = TestClock()
        let wakes = ConnectivityWakes(activity: { activity }, now: { clock.now }, sleep: { _ in throw CancellationError() })
        let task = FakeBackgroundTask()

        wakes.hold(task)
        #expect(task.completions.isEmpty)
        #expect(wakes.count == 1)

        activity = Self.activity(pending: true)
        wakes.reevaluate()
        #expect(task.completions.isEmpty)

        activity = Self.settled
        wakes.reevaluate()
        wakes.reevaluate()
        #expect(task.completions == [false])
        #expect(wakes.count == 0)
    }

    @Test("A wake that arrives once sync has settled is handed back straight away")
    func settledCompletesAtOnce() {
        let wakes = ConnectivityWakes(activity: { Self.settled }, sleep: { _ in throw CancellationError() })
        let task = FakeBackgroundTask()
        wakes.hold(task)
        #expect(task.completions == [false])
    }

    @Test("The cap hands a wake back even if sync never reports again")
    func capFires() async {
        let clock = TestClock()
        let sleeper = ManualSleeper()
        let busy = Self.activity(pending: true)
        let wakes = ConnectivityWakes(activity: { busy }, now: { clock.now }, sleep: sleeper.sleep)
        let early = FakeBackgroundTask()
        let late = FakeBackgroundTask()

        wakes.hold(early)
        clock.now += .seconds(10)
        wakes.hold(late)
        #expect(await waitUntil { sleeper.requested == [.seconds(15), .seconds(15)] })

        clock.now += .seconds(5)
        sleeper.wakeAll()
        #expect(await waitUntil { early.completions == [false] })
        // Held for 5 s only: it keeps waiting for sync, or for its own cap.
        #expect(late.completions.isEmpty)
        #expect(wakes.count == 1)

        clock.now += .seconds(10)
        wakes.reevaluate()
        #expect(late.completions == [false])
    }

    // MARK: The complication

    @Test("Only a merge that changes the selected preset reloads the complication")
    func complicationReload() {
        let unchanged = WorkoutStore.MergeResult(changed: true, selectedPresetChanged: false, mergedDiffersFromRemote: false)
        let moved = WorkoutStore.MergeResult(changed: true, selectedPresetChanged: true, mergedDiffersFromRemote: true)
        #expect(AppDelegate.reloadsComplication(after: unchanged) == false)
        #expect(AppDelegate.reloadsComplication(after: moved))
    }
}
