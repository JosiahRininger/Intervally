//
//  HapticPlayer.swift
//  Intervally
//

import Foundation
import WatchKit

/// Plays each boundary's `BoundaryPlan` on the wrist.
///
/// The first tap plays synchronously, exactly as a single tap always has, so Standard never
/// goes near a task. Repeats run in one task that holds the player weakly: its owner, the
/// coordinator, is what keeps them coming.
///
/// The app has exactly one, previews included. Each `WKInterfaceDevice.play` stops the tap
/// still playing, so a second player's repeats would cut into a live run's boundary — a
/// preview's work taps landing on a rest cue — where here a boundary simply replaces them.
@MainActor
final class HapticPlayer: BoundaryHaptics {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    /// A repeat that wakes later than this was held up, usually by a suspension, and is
    /// dropped: played late, it would read as the next boundary.
    static let staleTolerance: Duration = .milliseconds(250)

    private let tap: @MainActor (WKHapticType) -> Void
    private let sleep: Sleep
    private let now: @MainActor () -> ContinuousClock.Instant
    private let strength: @MainActor () -> TapStrength
    private let countdownTaps: @MainActor () -> Bool

    private var pending: Task<Void, Never>?
    /// Bumped by every cancel, so a repeat already waking when its burst was replaced can
    /// tell that it is stale even before it sees the cancellation.
    private var generation = 0
    /// The countdown seconds the current burst would collide with. Scoped to one phase: the
    /// next boundary or a cancel clears it.
    private var suppressedCountdown: Set<Int> = []

    /// - Parameter strength: Read at every boundary, so a change in Settings, or Pro lapsing
    ///   mid-run, takes effect at the next interval change.
    init(
        tap: @escaping @MainActor (WKHapticType) -> Void = { WKInterfaceDevice.current().play($0) },
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
        strength: @escaping @MainActor () -> TapStrength,
        countdownTaps: @escaping @MainActor () -> Bool = {
            SharedDefaults.suite.object(forKey: SettingsKey.countdownTaps) as? Bool ?? true
        }
    ) {
        self.tap = tap
        self.sleep = sleep
        self.now = now
        self.strength = strength
        self.countdownTaps = countdownTaps
    }

    /// Whether repeats are still waiting to play.
    var hasPending: Bool { pending != nil }

    func play(_ event: TimerEvent, context: BoundaryContext) {
        if case .countdown(let second) = event {
            // The 3-2-1 lead-in is a preference, and always a single click.
            guard countdownTaps(), !suppressedCountdown.contains(second) else { return }
            tap(.click)
        } else {
            playBoundary(event, context: context, strength: strength())
        }
    }

    /// A work boundary at `strength` on a long phase, whatever is saved.
    func preview(_ strength: TapStrength) {
        let phase = IntervalPhase(id: 0, kind: .work, duration: 60, round: 1, start: 0)
        playBoundary(
            .phaseBegan(phase),
            context: BoundaryContext(lateness: 0, phaseDuration: phase.duration),
            strength: strength
        )
    }

    func cancelPending() {
        generation &+= 1
        pending?.cancel()
        pending = nil
        suppressedCountdown = []
    }

    private func playBoundary(_ event: TimerEvent, context: BoundaryContext, strength: TapStrength) {
        cancelPending()
        let plan = Haptics.plan(for: event, strength: strength, context: context)
        suppressedCountdown = plan.suppressedCountdown
        guard let first = plan.steps.first else { return }
        let start = now()
        tap(first.type)

        let repeats = Array(plan.steps.dropFirst())
        guard !repeats.isEmpty else { return }
        let burst = generation
        let sleep = self.sleep
        pending = Task { [weak self] in
            for step in repeats {
                guard let wait = self.map({ start + step.offset - $0.now() }) else { return }
                // A cancelled sleep throws at once: leave, rather than `try?` and carry on.
                do { try await sleep(max(.zero, wait)) } catch { return }
                guard let self, !Task.isCancelled, self.generation == burst else { return }
                // Its moment has passed. A later step can still be on time, so only this one goes.
                guard self.now() - (start + step.offset) <= Self.staleTolerance else { continue }
                self.tap(step.type)
            }
            if let self, self.generation == burst { self.pending = nil }
        }
    }
}
