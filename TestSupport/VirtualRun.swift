//
//  VirtualRun.swift
//  Intervally test support
//

import Foundation
import Testing
#if os(watchOS)
@testable import Intervally
#else
@testable import IntervallyPhone
#endif

// Compiled into both test bundles: both devices run their workouts through the shared
// coordinator, and their tests move its ticker the same way.

extension RunCoordinator {
    /// Puts the run's clock and its ticker on `time`: the engine reads the wall clock from it,
    /// counted from the reference date, and the ticker sleeps on it, so a test moves both at
    /// once and by exactly as much as it says.
    func runOnVirtualTime(_ time: VirtualTime) {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        engine.now = { start.addingTimeInterval(time.elapsed) }
        tickSleep = { try await time.sleep(for: .seconds($0)) }
    }

    /// Pauses and resumes the run 0.3 s in, as any pause can, which takes the ticker off the
    /// half-second grid it starts on. On that grid every whole second falls on a wake, so
    /// polling every half second would have looked as prompt as waking at each deadline.
    /// Returns once the resumed ticker is asleep, beside the sleep the pause cut short: that
    /// one wakes at its old deadline and stops there.
    func pauseOffTheGrid(on time: VirtualTime) async {
        time.advance(by: .milliseconds(300))
        togglePause()
        togglePause()
        #expect(await waitUntil { time.sleeping == 2 }, "The resumed ticker is asleep")
    }

    /// Moves `time` on to the next wake and waits for the ticker to act on it and sleep again,
    /// or stop. The elapsed time it woke at; nil with nothing asleep.
    func nextWake(on time: VirtualTime) async -> TimeInterval? {
        let woken = time.woken
        guard time.advanceToNextWake() else { return nil }
        #expect(await waitUntil { time.woken > woken && (time.sleeping == 1 || !isTicking) })
        return time.elapsed
    }

    /// Wakes the ticker until `done` holds or the ticker stops, and returns the elapsed time
    /// of every wake.
    func tick(on time: VirtualTime, until done: () -> Bool) async -> [TimeInterval] {
        var wakes: [TimeInterval] = []
        // A bound, so a ticker that never gets there fails the test rather than hanging it.
        while !done(), wakes.count < 1_000, let woke = await nextWake(on: time) {
            wakes.append(woke)
        }
        return wakes
    }
}
