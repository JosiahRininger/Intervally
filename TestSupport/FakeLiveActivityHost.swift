//
//  FakeLiveActivityHost.swift
//  Intervally test support
//

// Compiled into both test bundles, like the rest of the support, but only the iPhone has
// Live Activities.
#if os(iOS)
import ActivityKit
import Foundation
@testable import IntervallyPhone

/// Stands in for ActivityKit, so `LiveActivityPresenter` runs as it does on a device: an
/// activity it requests is listed until it ends, one ended to linger stays listed as ended,
/// and one ended at once is gone. Each update can take time, the trip to the system, a
/// request can be refused, as the system refuses one from the background or past its limit,
/// and every call that landed is recorded in the order it landed.
final class FakeLiveActivityHost: LiveActivityHosting, @unchecked Sendable {

    /// What a call carried, as the Lock Screen would show it: `ActivityContent` isn't
    /// `Equatable`.
    struct Shown: Equatable, Sendable {
        let state: RunActivityAttributes.ContentState
        let staleDate: Date?
    }

    /// A call, with the id of the activity it was for.
    enum Call: Equatable, Sendable {
        case request(String, workout: String, Shown)
        case update(String, Shown)
        case end(String, Shown?, LiveActivityDismissal)
    }

    let areActivitiesEnabled: Bool
    /// How long each update takes to land, by its number (every update counts, from 1).
    private let updateDuration: @Sendable (Int) -> Duration
    /// Whether a request is refused, by its number (every request counts, from 1).
    private let refusesRequest: @Sendable (Int) -> Bool

    private let lock = NSLock()
    private var current: [HostedActivity]
    private var log: [Call] = []
    private var requestCount = 0
    private var startedCount = 0
    private var updateCount = 0

    /// What ActivityKit throws when it won't start one.
    struct Refused: Error {}

    /// - Parameter activities: Left by an earlier launch, before the test begins. Activities
    ///   it starts are numbered from 1: "1", "2" and so on, a refused request taking none.
    init(
        activities: [HostedActivity] = [],
        enabled: Bool = true,
        updateDuration: @escaping @Sendable (Int) -> Duration = { _ in .zero },
        refusesRequest: @escaping @Sendable (Int) -> Bool = { _ in false }
    ) {
        current = activities
        areActivitiesEnabled = enabled
        self.updateDuration = updateDuration
        self.refusesRequest = refusesRequest
    }

    /// Every call, in the order each landed.
    var calls: [Call] { lock.withLock { log } }

    // MARK: - LiveActivityHosting

    var activities: [HostedActivity] { lock.withLock { current } }

    func request(attributes: RunActivityAttributes, content: Content) throws -> HostedActivity {
        try lock.withLock {
            requestCount += 1
            if refusesRequest(requestCount) { throw Refused() }
            startedCount += 1
            let activity = HostedActivity(id: "\(startedCount)", state: .active)
            current.append(activity)
            log.append(.request(activity.id, workout: attributes.workoutName, Shown(content)))
            return activity
        }
    }

    func update(_ activity: HostedActivity, content: Content) async {
        let number = lock.withLock {
            updateCount += 1
            return updateCount
        }
        let duration = updateDuration(number)
        if duration > .zero { try? await Task.sleep(for: duration) }
        lock.withLock { log.append(.update(activity.id, Shown(content))) }
    }

    func end(_ activity: HostedActivity, content: Content?, dismissal: LiveActivityDismissal) async {
        lock.withLock {
            log.append(.end(activity.id, content.map(Shown.init), dismissal))
            switch dismissal {
            case .immediate:
                current.removeAll { $0.id == activity.id }
            case .after:
                current = current.map { $0.id == activity.id ? HostedActivity(id: $0.id, state: .ended) : $0 }
            }
        }
    }
}

extension FakeLiveActivityHost.Shown {
    init(_ content: ActivityContent<RunActivityAttributes.ContentState>) {
        self.init(state: content.state, staleDate: content.staleDate)
    }
}
#endif
