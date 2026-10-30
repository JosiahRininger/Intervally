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
/// A schedule covers the run from now on, up to `maxScheduled` alerts, the last of them
/// always the finish, and is torn down on pause or stop, so it always reflects the run's
/// real timeline. `needsTopUp(now:)` says when a workout with more boundaries than that
/// should be scheduled again.
actor NotificationScheduler {

    private let center: any NotificationCentering
    /// The time, read again at each add. Injectable so a test can make an add take time
    /// without waiting for it.
    private let now: @Sendable () -> Date
    private let log = Logger(subsystem: "com.josiahrininger.intervally", category: "notifications")
    static let prefix = "interval-boundary-"

    /// watchOS caps pending local notifications; staying well under keeps long workouts
    /// from silently dropping their later cues.
    static let maxScheduled = 60

    /// How far ahead a boundary has to be for an alert, unless a schedule asks for more: one
    /// closer is under way, or as good as, by the time its alert could land. 1.2's floor.
    static let defaultMinimumLead: TimeInterval = 0.5

    /// The shortest delay an alert is handed over with. A trigger needs a strictly positive
    /// interval, and an alert whose moment has only just gone still goes off, at once.
    static let shortestDelay: TimeInterval = 0.5

    /// How long after its moment an alert can still be handed over. Any later (the app was
    /// suspended partway through a schedule, say), its change is well past and the alert
    /// would mark nothing.
    static let latestPast: TimeInterval = 1

    /// `needsTopUp(now:)` says yes once fewer of the scheduled boundaries than this are still
    /// to come.
    static let topUpBelow = 10

    /// Bumped by every cancel and every new schedule. The scheduling loop suspends on each
    /// `center.add`, and an actor releases its executor at each suspension, so without this
    /// a later `cancelAll()` could run *between* two adds and then be undone by the rest of
    /// the loop.
    private var epoch = 0

    /// What the last `schedule` handed over, for `needsTopUp(now:)`. Nil once cancelled.
    private var window: Window?

    private struct Window {
        /// The boundaries' alerts, in order. The finish isn't one.
        var boundaries: [BoundaryRequest]
        /// When the plan's last boundary falls, if it was ahead but didn't fit: the workout
        /// goes on past what this schedule covers.
        let lastLeftOut: Date?
    }

    init(
        center: any NotificationCentering = UNUserNotificationCenter.current(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.center = center
        self.now = now
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            log.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Identifiers

    /// The alert for the boundary that starts `plan.phases[index]`. Static, so the code that
    /// disarms an alert can name it without a hop onto this actor.
    static func identifier(forPhase index: Int) -> String { "\(prefix)\(index)" }

    /// The "Workout Complete" alert.
    static let finishIdentifier = "\(prefix)finish"

    // MARK: - What to schedule

    /// One boundary alert, decided but not yet handed to the system. It keeps the moment it
    /// is for, not a delay: the delay is worked out at its add (`schedule`).
    struct BoundaryRequest: Equatable, Sendable {
        let identifier: String
        let fireDate: Date
        let title: String
        let body: String
    }

    /// Works out which boundaries still need alerting: at most `limit` alerts, the last of
    /// them always the finish. Pure, so the decisions — which boundaries are skipped, how
    /// many are kept, what they say — are testable without touching
    /// `UNUserNotificationCenter`.
    ///
    /// - Parameter minimumLead: How far ahead of `now` a boundary has to be. A reschedule can
    ///   ask for more than the default, so it doesn't bring back an alert taken down just
    ///   before its boundary.
    static func requests(
        plan: IntervalPlan,
        anchor: Date,
        now: Date,
        limit: Int = maxScheduled,
        minimumLead: TimeInterval = defaultMinimumLead
    ) -> [BoundaryRequest] {
        let elapsed = now.timeIntervalSince(anchor)
        var requests: [BoundaryRequest] = []

        for (index, phase) in plan.phases.enumerated() where index > 0 {
            // The last slot is the finish's. Filled with boundaries first, a long workout
            // lost "Workout Complete", the one alert that says it's over.
            guard requests.count < limit - 1 else { break }
            // A trigger needs a strictly positive interval; boundaries already passed, or
            // closer than the lead, are skipped rather than fired immediately.
            guard phase.start - elapsed > minimumLead else { continue }
            requests.append(
                BoundaryRequest(
                    identifier: identifier(forPhase: index),
                    fireDate: anchor.addingTimeInterval(phase.start),
                    title: phase.title,
                    body: body(for: phase, totalRounds: plan.totalRounds)
                )
            )
        }

        if limit > 0, plan.totalDuration - elapsed > minimumLead {
            requests.append(
                BoundaryRequest(
                    identifier: finishIdentifier,
                    fireDate: anchor.addingTimeInterval(plan.totalDuration),
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

    /// When `plan`'s last boundary falls, if it was far enough ahead to alert and `requests`
    /// still stops short of it. A schedule covers a run of boundaries in order, so only the
    /// limit leaves that one out, and the workout has more to schedule later.
    private static func lastLeftOut(
        of plan: IntervalPlan, anchor: Date, elapsed: TimeInterval, minimumLead: TimeInterval,
        requests: [BoundaryRequest]
    ) -> Date? {
        guard let last = plan.phases.indices.last, last > 0,
              plan.phases[last].start - elapsed > minimumLead,
              !requests.contains(where: { $0.identifier == identifier(forPhase: last) })
        else { return nil }
        return anchor.addingTimeInterval(plan.phases[last].start)
    }

    // MARK: - Scheduling

    /// Replaces any existing schedule with alerts for `plan`, anchored at `anchor`, leaving
    /// out any boundary less than `minimumLead` seconds away.
    func schedule(plan: IntervalPlan, anchor: Date, minimumLead: TimeInterval) async {
        await cancelAll()
        epoch += 1
        let generation = epoch

        // Read after the cancel, which is a round trip or two to the notification server.
        let start = now()
        let requests = Self.requests(plan: plan, anchor: anchor, now: start, minimumLead: minimumLead)
        window = Window(
            boundaries: requests.filter { $0.identifier != Self.finishIdentifier },
            lastLeftOut: Self.lastLeftOut(
                of: plan, anchor: anchor, elapsed: start.timeIntervalSince(anchor),
                minimumLead: minimumLead, requests: requests
            )
        )

        var scheduled = 0
        var tooLate = 0
        for request in requests {
            guard await add(request) else {
                tooLate += 1
                continue
            }
            guard epoch == generation else {
                log.info("schedule superseded after \(scheduled) notifications")
                return
            }
            scheduled += 1
        }
        log.info("scheduled \(scheduled) boundary notifications, \(tooLate) too late to add")
    }

    /// Hands one alert to the system, its delay worked out now, just before the add. Each add
    /// before it, and the cancel before those, is a round trip to the notification server,
    /// and with every delay worked out up front, each alert went off late by all of them.
    /// Returns false, adding nothing, when the alert's moment is more than `latestPast` gone.
    private func add(_ request: BoundaryRequest) async -> Bool {
        let delay = request.fireDate.timeIntervalSince(now())
        guard delay >= -Self.latestPast else { return false }

        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.interruptionLevel = .timeSensitive
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(Self.shortestDelay, delay), repeats: false
        )
        let notification = UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)
        do {
            try await center.add(notification)
        } catch {
            log.error("failed to schedule \(request.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return true
    }

    /// Whether the alerts are running out before the workout does: fewer than `topUpBelow`
    /// of the boundaries the last `schedule` handed over are still to come after `now`, and
    /// the plan has boundaries after them that didn't fit. Scheduled again then, a long
    /// workout keeps its alerts to the finish instead of losing them after the first 59.
    /// False once cancelled, and for a plan that fit in one schedule.
    func needsTopUp(now: Date) -> Bool {
        guard let window, let lastLeftOut = window.lastLeftOut, lastLeftOut > now else { return false }
        return window.boundaries.filter { $0.fireDate > now }.count < Self.topUpBelow
    }

    /// Takes down one alert still to come, such as one the app is about to mark itself, and
    /// nothing that isn't a boundary's. Unlike a cancel it leaves the epoch alone, so a
    /// schedule still adding carries on, and could yet add this alert: whoever disarms orders
    /// the call after any schedule in flight.
    func disarm(identifier: String) async {
        guard identifier.hasPrefix(Self.prefix) else { return }
        center.removePendingRequests(withIdentifiers: [identifier])
        window?.boundaries.removeAll { $0.identifier == identifier }
        log.info("disarmed \(identifier, privacy: .public)")
    }

    func cancelAll() async {
        epoch += 1
        window = nil
        // Two passes: the first snapshot is taken across an await, so anything a superseded
        // `schedule` added in that window would not appear in it and would survive.
        for _ in 0..<2 {
            let ids = await center.pendingRequestIdentifiers().filter { $0.hasPrefix(Self.prefix) }
            if ids.isEmpty { return }
            center.removePendingRequests(withIdentifiers: ids)
            log.info("cancelled \(ids.count) boundary notifications")
        }
    }
}
