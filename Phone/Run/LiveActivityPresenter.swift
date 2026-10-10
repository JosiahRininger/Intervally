//
//  LiveActivityPresenter.swift
//  IntervallyPhone
//

import ActivityKit
import Foundation
import os

extension RunActivityAttributes {
    init(_ run: RunPresentation) {
        self.init(workoutName: run.workoutName, totalRounds: run.totalRounds, totalDuration: run.totalDuration)
    }
}

extension RunActivityAttributes.ContentState {
    init(_ run: RunPresentation, theme: AppTheme) {
        let clock: Clock
        switch run.clock {
        case .running(let phaseStart, let phaseEnd, let workoutEnd):
            clock = .running(phaseStart: phaseStart, phaseEnd: phaseEnd, workoutEnd: workoutEnd)
        case .paused(let phaseLeft, let workoutLeft):
            clock = .paused(phaseLeft: phaseLeft, workoutLeft: workoutLeft)
        case .finished:
            clock = .finished
        }
        self.init(
            phase: run.phase?.kind,
            phaseDuration: run.phase?.duration ?? 0,
            // The cooldown reports the final round, so a finished run reads "8 of 8".
            round: run.phase?.round ?? run.totalRounds,
            next: run.next?.kind,
            nextDuration: run.next?.duration,
            clock: clock,
            theme: theme
        )
    }
}

/// Keeps the run's Live Activity in step with the run: started with it, updated at every
/// change, and ended with it.
///
/// Every call goes through one chain of tasks, in order: ActivityKit's calls are async, and
/// a quick pause and resume sent as two loose tasks could land the other way round and leave
/// the Lock Screen showing a paused run that is counting.
@MainActor
final class LiveActivityPresenter: RunPresenting {
    private let theme: () -> AppTheme
    /// Touched only by the chain's steps, one at a time, off the main actor: ActivityKit's
    /// handle isn't `Sendable`, and the chain is what makes sharing it safe.
    nonisolated(unsafe) private var activity: Activity<RunActivityAttributes>?
    private var chain: Task<Void, Never>?
    private let log = Logger(subsystem: "com.josiahrininger.intervally", category: "activity")

    /// How long a finished run stays on the Lock Screen: long enough to look at after the
    /// last interval, not so long that it is still there the next morning.
    static let finishedLinger: TimeInterval = 15 * 60

    init(theme: @escaping () -> AppTheme) {
        self.theme = theme
    }

    func present(_ run: RunPresentation?) {
        let content = run.map { ContentStateUpdate(run: $0, state: .init($0, theme: theme())) }
        let previous = chain
        chain = Task { [weak self] in
            await previous?.value
            await self?.apply(content)
        }
    }

    /// Takes over an activity left by an earlier launch of the app, for a restored run, or
    /// ends every one when there is no run to show: an activity whose app was terminated
    /// would otherwise sit on the Lock Screen, counting a run that no longer exists.
    func reconcile(hasRun: Bool) {
        let previous = chain
        chain = Task { [weak self] in
            await previous?.value
            await self?.adoptOrEnd(hasRun: hasRun)
        }
    }

    nonisolated private func adoptOrEnd(hasRun: Bool) async {
        let existing = Activity<RunActivityAttributes>.activities
        if hasRun, let first = existing.first {
            activity = first
            for extra in existing.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        } else if !hasRun {
            for leftover in existing { await leftover.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private struct ContentStateUpdate: Sendable {
        let run: RunPresentation
        let state: RunActivityAttributes.ContentState
    }

    nonisolated private func apply(_ update: ContentStateUpdate?) async {
        guard let update else {
            // Stopped: gone at once. A finished run ended itself already.
            await activity?.end(nil, dismissalPolicy: .immediate)
            activity = nil
            return
        }
        let content = ActivityContent(state: update.state, staleDate: update.state.staleDate)
        if update.state.clock == .finished {
            await activity?.end(content, dismissalPolicy: .after(.now.addingTimeInterval(Self.finishedLinger)))
            activity = nil
            return
        }
        if let activity {
            await activity.update(content)
            return
        }
        // Only an app in front may start one; a restore in the background waits for the
        // next change made in front.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(attributes: RunActivityAttributes(update.run), content: content)
        } catch {
            log.notice("live activity not started: \(error.localizedDescription, privacy: .public)")
        }
    }
}
