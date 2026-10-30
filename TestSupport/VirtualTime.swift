//
//  VirtualTime.swift
//  Intervally test support
//

import Foundation

// Compiled into both test bundles: the watch's haptic bursts sleep on it, and so do both
// devices' run tickers and workout session retries.

/// Virtual time for whatever sleeps. `now` moves only when a test advances it, and a sleep
/// wakes once the clock passes its deadline, so a burst's or a run's timing is exact and a
/// suspension is a single big jump. A sleep cancelled while it waits still counts in
/// `sleeping` until its deadline, and throws only then, as the burst tests rely on.
@MainActor
final class VirtualTime {
    private let origin: ContinuousClock.Instant
    private(set) var now: ContinuousClock.Instant
    private var sleepers: [(deadline: ContinuousClock.Instant, wake: CheckedContinuation<Void, Never>)] = []
    /// Every sleep asked for, in order.
    private(set) var requested: [Duration] = []
    /// Sleeps that have woken and returned, cancelled or not.
    private(set) var woken = 0

    init() {
        let start = ContinuousClock.now
        origin = start
        now = start
    }

    var sleeping: Int { sleepers.count }

    /// Seconds the clock has been moved on since it was made: what a run's wall clock reads.
    var elapsed: TimeInterval {
        let moved = (now - origin).components
        return TimeInterval(moved.seconds) + TimeInterval(moved.attoseconds) / 1e18
    }

    /// Throws on cancellation like `Task.sleep`: at once if already cancelled, otherwise
    /// when it wakes.
    func sleep(for duration: Duration) async throws {
        requested.append(duration)
        try Task.checkCancellation()
        if duration > .zero {
            let deadline = now + duration
            await withCheckedContinuation { sleepers.append((deadline, $0)) }
        }
        woken += 1
        try Task.checkCancellation()
    }

    /// Moves the clock and wakes every sleep that is due.
    func advance(by duration: Duration) {
        now = now + duration
        let due = sleepers.filter { $0.deadline <= now }
        sleepers.removeAll { $0.deadline <= now }
        due.forEach { $0.wake.resume() }
    }

    /// Moves the clock to the first deadline of the sleeps waiting, and wakes what is due
    /// there. False with nothing asleep.
    @discardableResult
    func advanceToNextWake() -> Bool {
        guard let next = sleepers.map(\.deadline).min() else { return false }
        advance(by: next - now)
        return true
    }
}
