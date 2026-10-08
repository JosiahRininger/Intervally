//
//  HapticPlayerTests.swift
//  IntervallyTests
//

import Testing
import Foundation
import WatchKit
@testable import Intervally

/// Virtual time for `HapticPlayer`. `now` moves only when a test advances it, and a sleep
/// wakes once the clock passes its deadline, so a burst's timing is exact and a suspension
/// is a single big jump.
@MainActor
final class VirtualTime {
    private(set) var now = ContinuousClock.now
    private var sleepers: [(deadline: ContinuousClock.Instant, wake: CheckedContinuation<Void, Never>)] = []
    /// Every sleep asked for, in order.
    private(set) var requested: [Duration] = []
    /// Sleeps that have woken and returned, cancelled or not.
    private(set) var woken = 0

    var sleeping: Int { sleepers.count }

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
}

/// The wrist, as far as a test can feel it.
@MainActor
final class TapLog {
    private(set) var types: [WKHapticType] = []
    func record(_ type: WKHapticType) { types.append(type) }
}

/// A saved tap strength the test changes between boundaries.
@MainActor
final class SavedStrength {
    var value: TapStrength
    init(_ value: TapStrength) { self.value = value }
}

@Suite("Haptic player")
@MainActor
struct HapticPlayerTests {

    let time = VirtualTime()
    let taps = TapLog()

    private func makePlayer(
        strength: @escaping @MainActor () -> TapStrength,
        countdownTaps: @escaping @MainActor () -> Bool = { true }
    ) -> HapticPlayer {
        HapticPlayer(
            tap: { [taps] in taps.record($0) },
            sleep: { [time] in try await time.sleep(for: $0) },
            now: { [time] in time.now },
            strength: strength,
            countdownTaps: countdownTaps
        )
    }

    private func phase(_ kind: IntervalPhase.Kind, _ duration: TimeInterval) -> TimerEvent {
        .phaseBegan(IntervalPhase(id: 1, kind: kind, duration: duration, round: 1, start: 0))
    }

    private func onTime(_ duration: TimeInterval) -> BoundaryContext {
        BoundaryContext(lateness: 0.2, phaseDuration: duration)
    }

    /// Waits for the burst's task to reach its next sleep.
    private func awaitSleep() async {
        #expect(await waitUntil { time.sleeping == 1 }, "The burst is waiting on its next repeat")
    }

    /// Lets every woken sleep return and its task act on it, so an absence can be asserted.
    private func settle(woken count: Int) async {
        #expect(await waitUntil { time.woken >= count })
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test("The first tap is synchronous, and Standard schedules nothing")
    func standardIsSynchronous() async {
        let player = makePlayer(strength: { .standard })

        player.play(phase(.work, 60), context: onTime(60))

        #expect(taps.types == [.notification])
        #expect(player.hasPending == false)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(time.requested.isEmpty)
    }

    @Test("Strongest plays every repeat at its offset")
    func strongestDeliversEveryRepeat() async {
        let player = makePlayer(strength: { .strongest })

        player.play(phase(.work, 60), context: onTime(60))
        #expect(taps.types == [.notification])
        #expect(player.hasPending)

        await awaitSleep()
        time.advance(by: .seconds(1))
        #expect(await waitUntil { taps.types.count == 2 })
        await awaitSleep()
        time.advance(by: .seconds(1))
        #expect(await waitUntil { player.hasPending == false })

        #expect(taps.types == [.notification, .notification, .notification])
        #expect(time.requested == [.seconds(1), .seconds(1)])
    }

    @Test("The finish repeats its success tap")
    func finishBursts() async {
        let player = makePlayer(strength: { .strong })

        player.play(.finished, context: BoundaryContext(lateness: 0.1, phaseDuration: nil))
        await awaitSleep()
        time.advance(by: .milliseconds(800))
        #expect(await waitUntil { player.hasPending == false })

        #expect(taps.types == [.success, .success])
    }

    @Test("Cancelling stops the repeats still to come")
    func cancelStopsTheRest() async {
        let player = makePlayer(strength: { .strongest })

        player.play(phase(.work, 60), context: onTime(60))
        await awaitSleep()
        player.cancelPending()
        #expect(player.hasPending == false)

        time.advance(by: .seconds(5))
        await settle(woken: 1)
        #expect(taps.types == [.notification])
        #expect(time.sleeping == 0, "The cancelled burst asked for no further sleep")
    }

    @Test("A new boundary replaces the burst still playing")
    func newBoundaryReplacesBurst() async {
        let player = makePlayer(strength: { .strongest })

        player.play(phase(.work, 60), context: onTime(60))
        await awaitSleep()
        time.advance(by: .milliseconds(500))
        player.play(phase(.rest, 60), context: onTime(60))
        #expect(taps.types == [.notification, .directionDown])

        #expect(await waitUntil { time.sleeping == 2 }, "The old burst sleeps on; only its cancellation stops it")
        time.advance(by: .milliseconds(600))
        #expect(await waitUntil { taps.types.count == 3 })
        await awaitSleep()
        time.advance(by: .milliseconds(600))
        #expect(await waitUntil { player.hasPending == false })
        await settle(woken: 3)

        #expect(taps.types == [.notification, .directionDown, .directionDown, .directionDown])
    }

    @Test("Repeats woken after a suspension are dropped, not played late")
    func suspendedRepeatsAreDropped() async {
        let player = makePlayer(strength: { .strongest })

        player.play(phase(.work, 60), context: onTime(60))
        await awaitSleep()
        time.advance(by: .seconds(30))
        #expect(await waitUntil { player.hasPending == false })

        #expect(taps.types == [.notification])
    }

    @Test("Only the repeat that woke late is dropped; one still on time plays")
    func onlyTheLateRepeatIsDropped() async {
        let player = makePlayer(strength: { .strongest })

        player.play(phase(.rest, 60), context: onTime(60))
        await awaitSleep()
        // Due at 0.6 s; 0.2 s late is within tolerance.
        time.advance(by: .milliseconds(800))
        #expect(await waitUntil { taps.types.count == 2 })
        await awaitSleep()
        // Due at 1.2 s; woken at 1.8 s, 0.6 s late.
        time.advance(by: .milliseconds(1000))
        #expect(await waitUntil { player.hasPending == false })
        #expect(taps.types == [.directionDown, .directionDown])

        // A step past a late one is still played on time.
        player.play(phase(.work, 60), context: onTime(60))
        await awaitSleep()
        time.advance(by: .milliseconds(1300))
        await awaitSleep()
        time.advance(by: .milliseconds(700))
        #expect(await waitUntil { player.hasPending == false })
        #expect(taps.types == [.directionDown, .directionDown, .notification, .notification])
    }

    @Test("Countdown seconds inside a burst stay silent, and only for that phase")
    func suppressionIsScopedToItsPhase() async {
        let player = makePlayer(strength: { .strongest })

        player.play(phase(.work, 5), context: onTime(5))
        for second in [3, 2, 1] { player.play(.countdown(secondsRemaining: second), context: .immediate) }
        #expect(taps.types == [.notification, .click], "3 and 2 would land inside the burst")
        #expect(player.hasPending, "A countdown never cancels the burst")

        player.play(phase(.rest, 60), context: onTime(60))
        player.play(.countdown(secondsRemaining: 3), context: .immediate)
        #expect(taps.types == [.notification, .click, .directionDown, .click])

        player.play(phase(.work, 5), context: onTime(5))
        player.cancelPending()
        player.play(.countdown(secondsRemaining: 3), context: .immediate)
        #expect(taps.types.suffix(2) == [.notification, .click], "Cancelling clears the suppression too")
    }

    @Test("With countdown taps off, no click plays at any strength", arguments: TapStrength.allCases)
    func countdownToggleOff(strength: TapStrength) async {
        let player = makePlayer(strength: { strength }, countdownTaps: { false })

        player.play(phase(.work, 60), context: onTime(60))
        for second in [3, 2, 1] { player.play(.countdown(secondsRemaining: second), context: .immediate) }
        player.cancelPending()

        #expect(taps.types == [.notification])
    }

    @Test("A countdown is one click at any strength", arguments: TapStrength.allCases)
    func countdownIsOneClick(strength: TapStrength) async {
        let player = makePlayer(strength: { strength })

        player.play(.countdown(secondsRemaining: 2), context: .immediate)

        #expect(taps.types == [.click])
        #expect(player.hasPending == false)
    }

    @Test("Strength is read at every boundary, so a change applies at the next one")
    func strengthIsReadPerBoundary() async {
        let saved = SavedStrength(.strongest)
        let player = makePlayer(strength: { [saved] in saved.value })

        player.play(phase(.work, 60), context: onTime(60))
        #expect(player.hasPending)
        saved.value = .standard
        player.play(phase(.rest, 60), context: onTime(60))

        #expect(player.hasPending == false)
        #expect(taps.types == [.notification, .directionDown])
    }

    @Test("The preview plays a work burst at the strength asked for, whatever is saved")
    func previewIgnoresSavedStrength() async {
        let player = makePlayer(strength: { .standard })

        player.preview(.strongest)
        await awaitSleep()
        time.advance(by: .seconds(1))
        #expect(await waitUntil { taps.types.count == 2 })
        await awaitSleep()
        time.advance(by: .seconds(1))
        #expect(await waitUntil { player.hasPending == false })

        #expect(taps.types == [.notification, .notification, .notification])
    }

    @Test("A boundary replaces a preview still repeating, so a live run's cue is never masked")
    func boundaryReplacesPreview() async {
        let player = makePlayer(strength: { .standard })

        player.preview(.strongest)
        await awaitSleep()
        time.advance(by: .milliseconds(400))
        player.play(phase(.rest, 60), context: onTime(60))
        #expect(player.hasPending == false)

        time.advance(by: .seconds(3))
        await settle(woken: 1)
        #expect(taps.types == [.notification, .directionDown], "Not one of the preview's work taps after the rest cue")
    }

    @Test("A preview replaces a boundary's burst rather than playing over it")
    func previewReplacesBoundary() async {
        let player = makePlayer(strength: { .strongest })

        player.play(phase(.rest, 60), context: onTime(60))
        await awaitSleep()
        player.preview(.standard)
        #expect(player.hasPending == false)

        time.advance(by: .seconds(3))
        await settle(woken: 1)
        #expect(taps.types == [.directionDown, .notification])
    }

    @Test("Repeats hold the player weakly: once it is released they stop")
    func releasedPlayerStops() async {
        var player: HapticPlayer? = makePlayer(strength: { .strongest })

        player?.play(phase(.work, 60), context: onTime(60))
        await awaitSleep()
        player = nil
        time.advance(by: .seconds(5))
        await settle(woken: 1)

        #expect(taps.types == [.notification])
        #expect(time.sleeping == 0)
    }
}
