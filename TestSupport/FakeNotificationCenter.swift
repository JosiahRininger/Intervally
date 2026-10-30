//
//  FakeNotificationCenter.swift
//  Intervally test support
//

import Foundation
import UserNotifications
#if os(watchOS)
@testable import Intervally
#else
@testable import IntervallyPhone
#endif

// Compiled into both test bundles: the run's notification scheduler is shared, and so is
// anything else that schedules through `NotificationCentering`.

/// Stands in for `UNUserNotificationCenter`, so `NotificationScheduler` runs as it does on a
/// device: what it adds stays pending until removed, an add with an identifier already
/// pending replaces it, and each add can take time on the center's clock, the round trip to
/// the notification server. A test can also hold one add, or one listing of what is pending,
/// open while it does something else, which is how the scheduler's orderings are tested.
final class FakeNotificationCenter: NotificationCentering, @unchecked Sendable {

    /// A request as the center holds it.
    struct Request: Equatable, Sendable {
        let identifier: String
        let title: String
        let body: String
        /// The trigger's delay, from the add.
        let interval: TimeInterval
        /// When it was added, on the center's clock.
        let addedAt: Date

        /// When it goes off, on the center's clock.
        var fireDate: Date { addedAt.addingTimeInterval(interval) }
    }

    /// How long each add takes on the clock.
    let addDuration: TimeInterval
    /// What `authorizationStatus()` reports.
    let status: UNAuthorizationStatus
    /// What a permission request comes back with.
    let granted: Bool

    private let lock = NSLock()
    private var clock: Date
    private var pendingRequests: [Request]
    private var adds: [Request] = []
    private var removals: [[String]] = []
    private var listingCount = 0
    private var asked: [UNAuthorizationOptions] = []
    private var addHolds: [Int: Hold] = [:]
    private var listingHolds: [Int: Hold] = [:]

    /// - Parameter alreadyPending: Requests of the app's own that aren't the run's, such as
    ///   a training reminder, pending before the test begins.
    init(
        now: Date,
        addDuration: TimeInterval = 0,
        status: UNAuthorizationStatus = .authorized,
        granted: Bool = true,
        alreadyPending: [String] = []
    ) {
        clock = now
        self.addDuration = addDuration
        self.status = status
        self.granted = granted
        pendingRequests = alreadyPending.map {
            Request(identifier: $0, title: "", body: "", interval: 86_400, addedAt: now)
        }
    }

    /// The center's clock: what a scheduler made for it reads as now.
    var now: Date { lock.withLock { clock } }
    /// What is pending, in the order it was added.
    var pending: [Request] { lock.withLock { pendingRequests } }
    /// Every add, in order, whether or not it is still pending.
    var added: [Request] { lock.withLock { adds } }
    /// The identifiers of each removal, in order.
    var removed: [[String]] { lock.withLock { removals } }
    /// How many times what is pending has been listed so far.
    var listings: Int { lock.withLock { listingCount } }
    /// What each permission request asked for, in order.
    var requestedOptions: [UNAuthorizationOptions] { lock.withLock { asked } }

    /// Moves the clock on, as a suspension would.
    func advance(by seconds: TimeInterval) {
        lock.withLock { clock = clock.addingTimeInterval(seconds) }
    }

    /// Holds the `number`th add (every add counts, from 1) open until released. With
    /// `landed`, its request is already pending while it waits: the server has it, and the
    /// answer is on the way back. Without, it is still on its way, and lands once released.
    func holdAdd(_ number: Int, landed: Bool = true) -> Hold {
        let hold = Hold(landed: landed)
        lock.withLock { addHolds[number] = hold }
        return hold
    }

    /// Holds the `number`th listing of what is pending (every listing counts, from 1) open
    /// until released. It answers with what was pending when asked: anything that lands
    /// while it waits isn't in it.
    func holdListing(_ number: Int) -> Hold {
        let hold = Hold(landed: true)
        lock.withLock { listingHolds[number] = hold }
        return hold
    }

    // MARK: - NotificationCentering

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        lock.withLock { asked.append(options) }
        return granted
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func pendingRequestIdentifiers() async -> [String] {
        let (identifiers, hold) = lock.withLock { () -> ([String], Hold?) in
            listingCount += 1
            return (pendingRequests.map(\.identifier), listingHolds.removeValue(forKey: listingCount))
        }
        await hold?.wait()
        return identifiers
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        lock.withLock {
            removals.append(identifiers)
            pendingRequests.removeAll { identifiers.contains($0.identifier) }
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        let interval = (request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval ?? 0
        let (added, hold) = lock.withLock { () -> (Request, Hold?) in
            let added = Request(
                identifier: request.identifier, title: request.content.title,
                body: request.content.body, interval: interval, addedAt: clock
            )
            adds.append(added)
            return (added, addHolds.removeValue(forKey: adds.count))
        }
        if let hold, !hold.landed { await hold.wait() }
        lock.withLock {
            pendingRequests.removeAll { $0.identifier == added.identifier }
            pendingRequests.append(added)
        }
        if let hold, hold.landed { await hold.wait() }
        lock.withLock { clock = clock.addingTimeInterval(addDuration) }
    }
}

extension FakeNotificationCenter {
    /// One call held open until the test lets it go.
    final class Hold: @unchecked Sendable {
        /// For an add: whether its request is pending while it waits.
        let landed: Bool

        private let lock = NSLock()
        private var isReached = false
        private var isReleased = false
        private var held: CheckedContinuation<Void, Never>?
        private var watchers: [CheckedContinuation<Void, Never>] = []

        init(landed: Bool) {
            self.landed = landed
        }

        /// Returns once the call is waiting here.
        func reached() async {
            await withCheckedContinuation { continuation in
                let reached = lock.withLock { () -> Bool in
                    if !isReached { watchers.append(continuation) }
                    return isReached
                }
                if reached { continuation.resume() }
            }
        }

        /// Lets the call carry on, or go straight through if it hasn't got here yet.
        func release() {
            let call = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                isReleased = true
                let call = held
                held = nil
                return call
            }
            call?.resume()
        }

        /// The held call's side: waits here until released.
        fileprivate func wait() async {
            await withCheckedContinuation { continuation in
                let (watchers, released) = lock.withLock { () -> ([CheckedContinuation<Void, Never>], Bool) in
                    isReached = true
                    let watchers = self.watchers
                    self.watchers = []
                    if !isReleased { held = continuation }
                    return (watchers, isReleased)
                }
                watchers.forEach { $0.resume() }
                if released { continuation.resume() }
            }
        }
    }
}
