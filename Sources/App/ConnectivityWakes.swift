//
//  ConnectivityWakes.swift
//  Intervally
//

import WatchKit
import os

/// A background task the system lends the app and waits to get back.
@MainActor
protocol BackgroundTaskCompleting: AnyObject {
    func setTaskCompletedWithSnapshot(_ refreshSnapshot: Bool)
}

extension WKRefreshBackgroundTask: BackgroundTaskCompleting {}

/// When a WatchConnectivity wake can be handed back.
///
/// Completing it straight away, as the app did for every task it didn't know, lets the
/// watch suspend before the context that woke it is merged. Apple's guidance is to keep it
/// until the session has activated and has nothing pending. Holding it too long gets the
/// app killed, so there is a hard cap.
enum BackgroundTaskPolicy {
    static let cap: Duration = .seconds(15)

    static func shouldComplete(_ activity: SyncActivity, heldFor: Duration) -> Bool {
        // Sync never started (the unit-test host): nothing is coming.
        guard activity.isActive else { return true }
        if heldFor >= cap { return true }
        return activity.isActivated && !activity.hasContentPending && activity.deliveriesInFlight == 0
    }
}

/// Holds WatchConnectivity wakes until `BackgroundTaskPolicy` lets each go.
@MainActor
final class ConnectivityWakes {
    private var held: [(task: any BackgroundTaskCompleting, since: ContinuousClock.Instant)] = []
    private let activity: () -> SyncActivity
    private let now: () -> ContinuousClock.Instant
    private let sleep: @Sendable (Duration) async throws -> Void
    private let log = Logger(subsystem: "com.josiahrininger.intervally", category: "sync")

    init(
        activity: @escaping () -> SyncActivity,
        now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.activity = activity
        self.now = now
        self.sleep = sleep
    }

    var count: Int { held.count }

    func hold(_ task: any BackgroundTaskCompleting) {
        held.append((task, now()))
        log.info("holding a WatchConnectivity wake")
        // The cap is enforced even if sync never reports another change.
        let sleep = sleep
        Task { [weak self] in
            do { try await sleep(BackgroundTaskPolicy.cap) } catch { return }
            self?.reevaluate()
        }
        reevaluate()
    }

    /// Hands back every wake the policy now lets go. Call whenever sync's activity changes.
    func reevaluate() {
        guard !held.isEmpty else { return }
        let activity = activity()
        let instant = now()
        var kept: [(task: any BackgroundTaskCompleting, since: ContinuousClock.Instant)] = []
        var done: [any BackgroundTaskCompleting] = []
        for entry in held {
            let heldFor = instant - entry.since
            if BackgroundTaskPolicy.shouldComplete(activity, heldFor: heldFor) {
                done.append(entry.task)
                log.info("handed back a WatchConnectivity wake after \(heldFor.formatted(.units(allowed: [.seconds, .milliseconds])), privacy: .public)")
            } else {
                kept.append(entry)
            }
        }
        held = kept
        done.forEach { $0.setTaskCompletedWithSnapshot(false) }
    }
}
