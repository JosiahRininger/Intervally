//
//  NotificationScheduler.swift
//  Intervally
//

import Foundation
import UserNotifications
import os

/// Schedules a local notification at every interval boundary.
///
/// This is the backstop that makes the app trustworthy when it is *not* executing — the
/// user pressed the crown, took a call, or the system reclaimed the app. Notifications are
/// delivered by the system from an absolute fire date, so they land whether or not the app
/// ever gets CPU time again.
///
/// Every boundary for the whole workout is scheduled up front and torn down on pause or
/// stop, so the schedule always reflects the run's real timeline.
actor NotificationScheduler {

    private let center = UNUserNotificationCenter.current()
    private let log = Logger(subsystem: "com.josiahrininger.intervally", category: "notifications")
    static let prefix = "interval-boundary-"

    /// watchOS caps pending local notifications; staying well under keeps long workouts
    /// from silently dropping their later cues.
    static let maxScheduled = 60

    /// Bumped by every cancel and every new schedule. The scheduling loop suspends on each
    /// `center.add`, and an actor releases its executor at each suspension, so without this
    /// a later `cancelAll()` could run *between* two adds and then be undone by the rest of
    /// the loop.
    private var epoch = 0

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            log.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// One boundary alert, decided but not yet handed to the system.
    struct BoundaryRequest: Equatable, Sendable {
        let identifier: String
        let delay: TimeInterval
        let title: String
        let body: String
    }

    /// Works out which boundaries still need alerting. Pure, so the decisions — which
    /// boundaries are skipped, how many are kept, what they say — are testable without
    /// touching `UNUserNotificationCenter`.
    static func requests(
        plan: IntervalPlan,
        anchor: Date,
        now: Date,
        limit: Int = maxScheduled
    ) -> [BoundaryRequest] {
        let elapsed = now.timeIntervalSince(anchor)
        var requests: [BoundaryRequest] = []

        for (index, phase) in plan.phases.enumerated() where index > 0 {
            guard requests.count < limit else { return requests }
            let delay = phase.start - elapsed
            // A trigger needs a strictly positive interval; boundaries already passed are
            // skipped rather than fired immediately.
            guard delay > 0.5 else { continue }
            requests.append(
                BoundaryRequest(
                    identifier: "\(prefix)\(index)",
                    delay: delay,
                    title: phase.kind.title,
                    body: body(for: phase, totalRounds: plan.totalRounds)
                )
            )
        }

        let finishDelay = plan.totalDuration - elapsed
        if requests.count < limit, finishDelay > 0.5 {
            requests.append(
                BoundaryRequest(
                    identifier: "\(prefix)finish",
                    delay: finishDelay,
                    title: "Workout Complete",
                    body: "\(DurationFormat.rounds(plan.totalRounds)) done."
                )
            )
        }
        return requests
    }

    /// What a boundary alert says beneath the phase name. Spelled out per kind: a two-way
    /// "work, else rest" choice would announce a warmup as "Rest 5:00".
    private static func body(for phase: IntervalPhase, totalRounds: Int) -> String {
        let length = DurationFormat.clock(Int(phase.duration))
        return switch phase.kind {
        case .work: "Round \(phase.round) of \(totalRounds)"
        case .rest: "Rest \(length)"
        case .warmup: "Easy for \(length)"
        case .cooldown: "Intervals done. Easy for \(length)"
        // Never alerted today: the lead-in is always the first phase, and the first phase
        // is already under way when the schedule is made.
        case .prepare: "Get ready"
        }
    }

    /// Replaces any existing schedule with boundaries for `plan`, anchored at `anchor`.
    func schedule(plan: IntervalPlan, anchor: Date, now: Date = Date()) async {
        await cancelAll()
        epoch += 1
        let generation = epoch

        var scheduled = 0
        for request in Self.requests(plan: plan, anchor: anchor, now: now) {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.interruptionLevel = .timeSensitive
            content.sound = .default

            await add(identifier: request.identifier, delay: request.delay, content: content)
            guard epoch == generation else {
                log.info("schedule superseded after \(scheduled) notifications")
                return
            }
            scheduled += 1
        }
        log.info("scheduled \(scheduled) boundary notifications")
    }

    private func add(identifier: String, delay: TimeInterval, content: UNMutableNotificationContent) async {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            log.error("failed to schedule \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancelAll() async {
        epoch += 1
        // Two passes: the first snapshot is taken across an await, so anything a superseded
        // `schedule` added in that window would not appear in it and would survive.
        for _ in 0..<2 {
            let pending = await center.pendingNotificationRequests()
            let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            if ids.isEmpty { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            log.info("cancelled \(ids.count) boundary notifications")
        }
    }
}
