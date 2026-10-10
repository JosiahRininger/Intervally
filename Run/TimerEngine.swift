//
//  TimerEngine.swift
//  Intervally
//

import Foundation
import Observation

/// Something worth reacting to — a haptic, a UI change — produced by advancing the clock.
enum TimerEvent: Equatable, Sendable {
    /// A new phase started. Carries the phase that just began.
    case phaseBegan(IntervalPhase)
    /// The final phase completed.
    case finished
    /// A pre-roll cue in the closing seconds of a phase (3, 2, 1).
    case countdown(secondsRemaining: Int)
}

/// Drives one run of an `IntervalPlan`.
///
/// The engine never counts down. It stores an *anchor date* and derives elapsed time from
/// the wall clock, so time that passes while the app is suspended, the screen is off, or
/// the wrist is down is accounted for automatically — the app does not need to be executing
/// for the workout to progress. This is the fix for the bug that stalled the original app:
/// it decremented a `Timer.publish` counter, so every tick the system withheld was a second
/// the workout silently lost.
@MainActor
@Observable
final class TimerEngine {

    enum Status: Equatable, Sendable {
        case idle, running, paused, finished
    }

    private(set) var plan: IntervalPlan
    private(set) var status: Status = .idle

    /// Injectable clock so tests can drive time deterministically.
    @ObservationIgnored var now: () -> Date = { Date() }

    /// The instant the workout *would* have started had it never been paused.
    /// `elapsed == now - anchor`, which keeps pause/resume and suspension on one code path.
    private(set) var anchor: Date?
    private var elapsedWhenPaused: TimeInterval = 0

    @ObservationIgnored private var lastPhaseIndex: Int?
    @ObservationIgnored private var lastCountdownSecond: Int?

    init(workout: IntervalWorkout) {
        self.plan = IntervalPlan(workout: workout)
    }

    // MARK: - Derived state

    var elapsed: TimeInterval {
        switch status {
        case .idle:
            return 0
        case .running:
            guard let anchor else { return 0 }
            return min(plan.totalDuration, max(0, now().timeIntervalSince(anchor)))
        case .paused:
            return elapsedWhenPaused
        case .finished:
            return plan.totalDuration
        }
    }

    var position: IntervalPlan.Position { plan.position(atElapsed: elapsed) }

    var isActive: Bool { status == .running || status == .paused }

    /// The date the current phase ends, for `Text(timerInterval:)` — which keeps ticking on
    /// screen without the app burning CPU, including in Always-On Display.
    var currentPhaseEndDate: Date? {
        guard status == .running, let anchor, let phase = position.phase else { return nil }
        return anchor.addingTimeInterval(phase.end)
    }

    /// The date the whole workout ends.
    var workoutEndDate: Date? {
        guard status == .running, let anchor else { return nil }
        return anchor.addingTimeInterval(plan.totalDuration)
    }

    // MARK: - Transport

    func configure(with workout: IntervalWorkout) {
        guard status == .idle || status == .finished else { return }
        // Same reasoning as `reset()`: rebuilding an identical plan would still notify.
        let next = IntervalPlan(workout: workout)
        if next != plan { plan = next }
        reset()
    }

    @discardableResult
    func start() -> [TimerEvent] {
        reset()
        status = .running
        anchor = now()
        var events: [TimerEvent] = []
        if let first = plan.phases.first {
            lastPhaseIndex = 0
            events.append(.phaseBegan(first))
        }
        return events
    }

    @discardableResult
    func pause() -> [TimerEvent] {
        guard status == .running else { return [] }
        // If the run completed in the moment before the tap landed, finish it rather than
        // parking in a paused state that can never emit `.finished`.
        if position.isFinished { return advance() }
        elapsedWhenPaused = elapsed
        status = .paused
        anchor = nil
        return []
    }

    func resume() {
        guard status == .paused else { return }
        // Re-anchor so the pause interval is excluded from elapsed time.
        anchor = now().addingTimeInterval(-elapsedWhenPaused)
        status = .running
        lastCountdownSecond = nil
    }

    /// Jumps to the start of the next phase. Running: the anchor moves back by the time
    /// remaining, so `elapsed` lands exactly on the boundary and `advance()` emits the
    /// phase-began event (or `.finished` from the last phase). Paused: the frozen elapsed
    /// time moves instead; the boundary event fires on the first tick after resuming.
    /// Skipping the last phase finishes the run either way.
    @discardableResult
    func skipPhase() -> [TimerEvent] {
        let position = self.position
        guard position.remainingInPhase > 0, let phase = position.phase else { return [] }
        switch status {
        case .running:
            guard let anchor else { return [] }
            self.anchor = anchor.addingTimeInterval(-position.remainingInPhase)
            lastCountdownSecond = nil
            return advance()
        case .paused:
            // Parked on the final second instead, the run would show its summary with no
            // finish tap, no Health save and nothing to resume, and Done would discard it.
            guard phase.end < plan.totalDuration else { return finish() }
            elapsedWhenPaused = phase.end
            lastCountdownSecond = nil
            return []
        case .idle, .finished:
            return []
        }
    }

    func togglePause() {
        switch status {
        case .running: pause()
        case .paused: resume()
        default: break
        }
    }

    func stop() {
        reset()
    }

    private func reset() {
        // Assign only what actually changes. `@Observable` notifies observers on every set,
        // even of an identical value, and `configure` runs from the run screen's `onAppear`
        // — in the middle of the push transition. Redundantly re-setting `status` to `.idle`
        // there invalidated every view watching it, including the outgoing root, mid-push.
        if status != .idle { status = .idle }
        if anchor != nil { anchor = nil }
        if elapsedWhenPaused != 0 { elapsedWhenPaused = 0 }
        lastPhaseIndex = nil
        lastCountdownSecond = nil
    }

    // MARK: - Advancing

    /// Recomputes state from the clock and returns everything that happened since the last
    /// call. Safe to call at any cadence: once a second while visible, or once on returning
    /// to the foreground after minutes of suspension. Skipped phases collapse into a single
    /// `phaseBegan` for the phase actually current, rather than a burst of stale haptics.
    @discardableResult
    func advance() -> [TimerEvent] {
        guard status == .running else { return [] }

        let position = self.position
        guard let index = position.phaseIndex, let phase = position.phase else { return finish() }

        var events: [TimerEvent] = []
        if lastPhaseIndex != index {
            lastPhaseIndex = index
            lastCountdownSecond = nil
            events.append(.phaseBegan(phase))
        }

        // Pre-roll cue for the last three seconds of a phase. Only fires when the app is
        // actually ticking; after a suspension the phase change above stands on its own.
        let remaining = Int(position.remainingInPhase.rounded(.up))
        if (1...3).contains(remaining), lastCountdownSecond != remaining, events.isEmpty {
            lastCountdownSecond = remaining
            events.append(.countdown(secondsRemaining: remaining))
        }

        return events
    }

    /// Ends the run, whether its last phase ran out or was skipped, running or paused.
    private func finish() -> [TimerEvent] {
        status = .finished
        anchor = nil
        // Assigned only on a change, for the reason `reset()` gives.
        if elapsedWhenPaused != 0 { elapsedWhenPaused = 0 }
        lastPhaseIndex = nil
        lastCountdownSecond = nil
        return [.finished]
    }

    /// Restores a run that was interrupted, from a persisted anchor.
    func restore(anchor: Date, workout: IntervalWorkout, paused elapsedWhenPaused: TimeInterval?) {
        plan = IntervalPlan(workout: workout)
        lastCountdownSecond = nil

        if let elapsedWhenPaused {
            self.elapsedWhenPaused = min(elapsedWhenPaused, plan.totalDuration)
            self.anchor = nil
            status = .paused
        } else {
            self.anchor = anchor
            self.elapsedWhenPaused = 0
            status = .running
        }
        lastPhaseIndex = position.phaseIndex
        if position.isFinished { status = .finished }
    }
}
