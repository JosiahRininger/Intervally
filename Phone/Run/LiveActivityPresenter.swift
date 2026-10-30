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
            phaseName: run.phase?.label?.name,
            nextName: run.next?.label?.name,
            clock: clock,
            theme: theme,
            phaseIndex: run.phaseIndex,
            controls: Controls(run)
        )
    }
}

extension RunActivityAttributes.ContentState.Controls {
    /// The buttons for `run`: Pause or Resume, whichever it can take, and Skip Interval while
    /// another interval follows. Skipping the last would end the workout, and only the app
    /// ends one. None once it has finished, and none for the watch's run, which is paused and
    /// skipped on the watch.
    init?(_ run: RunPresentation) {
        guard run.phase != nil, !run.isMirrored else { return nil }
        self.init(canPause: !run.isPaused, canResume: run.isPaused, canSkip: run.next != nil)
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
    private let host: any LiveActivityHosting
    private let theme: () -> AppTheme
    /// Touched only by the chain's steps, one at a time, off the main actor: the chain is
    /// what makes sharing it safe.
    nonisolated(unsafe) private var activity: HostedActivity?
    private var chain: Task<Void, Never>?
    private let log = Logger(subsystem: "com.josiahrininger.intervally", category: "activity")

    /// How long a finished run stays on the Lock Screen: long enough to look at after the
    /// last interval, not so long that it is still there the next morning.
    static let finishedLinger: TimeInterval = 15 * 60

    init(host: any LiveActivityHosting = ActivityKitHost(), theme: @escaping () -> AppTheme) {
        self.host = host
        self.theme = theme
    }

    /// What the activity shows for a run saved as `snapshot`, at `now`, in `theme`: the run
    /// as a launch at `now` brings it back, shown the way every run is. The tests hold it to
    /// what 1.2 showed.
    static func content(
        for snapshot: RunSnapshot, now: Date, theme: AppTheme
    ) -> RunActivityAttributes.ContentState? {
        let engine = TimerEngine(workout: snapshot.workout)
        engine.now = { now }
        engine.restore(anchor: snapshot.anchor, workout: snapshot.workout, paused: snapshot.pausedElapsed)
        return RunPresentation(engine: engine).map { RunActivityAttributes.ContentState($0, theme: theme) }
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

    /// Awaits every call made so far, so tests can assert on what reached ActivityKit.
    func settled() async {
        await chain?.value
    }

    /// Keeps the newest activity still showing, for a run that is coming back, and ends every
    /// other one: a finished run's lingering one, or one whose run is gone.
    nonisolated private func adoptOrEnd(hasRun: Bool) async {
        let existing = host.activities
        let live = existing.filter { $0.state == .active || $0.state == .stale }
        let keep = hasRun ? live.last : nil
        activity = keep
        for other in existing where other.id != keep?.id {
            await host.end(other, content: nil, dismissal: .immediate)
        }
    }

    private struct ContentStateUpdate: Sendable {
        let run: RunPresentation
        let state: RunActivityAttributes.ContentState
    }

    nonisolated private func apply(_ update: ContentStateUpdate?) async {
        guard let update else {
            // Stopped: gone at once. A finished run ended itself already.
            if let activity { await host.end(activity, content: nil, dismissal: .immediate) }
            activity = nil
            return
        }
        let content = ActivityContent(state: update.state, staleDate: update.state.staleDate)
        if update.state.clock == .finished {
            if let activity {
                await host.end(
                    activity, content: content, dismissal: .after(.now.addingTimeInterval(Self.finishedLinger))
                )
            }
            activity = nil
            return
        }
        if let activity {
            await host.update(activity, content: content)
            return
        }
        // Only an app in front may start one; a restore in the background waits for the
        // next change made in front.
        guard host.areActivitiesEnabled else { return }
        // A finished run's card lingers on its own for a while; a new run replaces it rather
        // than sitting beside it.
        for lingering in host.activities {
            await host.end(lingering, content: nil, dismissal: .immediate)
        }
        do {
            activity = try host.request(attributes: RunActivityAttributes(update.run), content: content)
        } catch {
            log.notice("live activity not started: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - ActivityKit

/// What `LiveActivityPresenter` asks of ActivityKit: the app's activities, and starting,
/// updating and ending one. The presenter's bugs would be in its ordering: a quick pause and
/// resume landing the other way round, or a burst of changes starting two activities.
/// ActivityKit shows neither in a test, so the presenter's tests run it against a stand-in
/// that records each call and can make an update take time.
protocol LiveActivityHosting: Sendable {
    typealias Content = ActivityContent<RunActivityAttributes.ContentState>

    /// Whether Live Activities are on in Settings.
    var areActivitiesEnabled: Bool { get }
    /// The app's activities, newest last, ended ones still on the Lock Screen among them.
    var activities: [HostedActivity] { get }
    func request(attributes: RunActivityAttributes, content: Content) throws -> HostedActivity
    func update(_ activity: HostedActivity, content: Content) async
    func end(_ activity: HostedActivity, content: Content?, dismissal: LiveActivityDismissal) async
}

/// One of the app's activities, as the presenter holds on to it. ActivityKit's own handle
/// isn't `Sendable`; this is, and the host keeps the handle for it.
struct HostedActivity: Equatable, Sendable {
    let id: String
    let state: ActivityState
}

/// How an ended activity leaves the Lock Screen. ActivityKit's own policy doesn't say when,
/// so a test couldn't check how long a finished run lingers.
enum LiveActivityDismissal: Equatable, Sendable {
    case immediate
    /// Stays, showing how it ended, until then.
    case after(Date)

    var policy: ActivityUIDismissalPolicy {
        switch self {
        case .immediate: .immediate
        case .after(let date): .after(date)
        }
    }
}

/// The system's Live Activities. Each handle it gives out it keeps until that activity ends,
/// so an update reaches the very activity requested or listed, not one looked up again.
final class ActivityKitHost: LiveActivityHosting, @unchecked Sendable {
    /// ActivityKit's handles aren't `Sendable`: the lock keeps the table safe, and the
    /// presenter's chain uses one handle at a time.
    private let lock = NSLock()
    private var handles: [String: Activity<RunActivityAttributes>] = [:]

    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    var activities: [HostedActivity] {
        Activity<RunActivityAttributes>.activities.map(keep)
    }

    func request(attributes: RunActivityAttributes, content: Content) throws -> HostedActivity {
        keep(try Activity<RunActivityAttributes>.request(attributes: attributes, content: content))
    }

    func update(_ activity: HostedActivity, content: Content) async {
        await handle(for: activity)?.update(content)
    }

    func end(_ activity: HostedActivity, content: Content?, dismissal: LiveActivityDismissal) async {
        await handle(for: activity)?.end(content, dismissalPolicy: dismissal.policy)
        lock.withLock { handles[activity.id] = nil }
    }

    private func keep(_ activity: Activity<RunActivityAttributes>) -> HostedActivity {
        lock.withLock { handles[activity.id] = activity }
        return HostedActivity(id: activity.id, state: activity.activityState)
    }

    private func handle(for activity: HostedActivity) -> Activity<RunActivityAttributes>? {
        lock.withLock { handles[activity.id] }
    }
}
