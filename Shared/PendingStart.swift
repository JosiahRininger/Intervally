//
//  PendingStart.swift
//  Intervally
//

import Foundation

/// A request to begin a workout that arrived from outside the UI — a Siri phrase, a
/// Shortcut, or a Control Center button.
///
/// App Intents on watchOS launch the app rather than running in-process, so the request is
/// left in the shared suite for the app to pick up. Two things make that safe:
///
/// - **It expires.** A request that was never picked up — the launch failed, or the app
///   never came forward — must not fire the next time the user opens the app normally,
///   possibly days later, starting a workout nobody asked for.
/// - **It is announced in-process too.** With `openAppWhenRun`, the intent's `perform()` can
///   run *after* the scene has already gone active, by which point the foreground check has
///   come and gone. The notification lets the running app pick the request up immediately.
enum PendingStart {
    private static let key = "pendingStart.v3"

    /// A Siri phrase or Control Center tap brings the app forward within a second or two;
    /// anything older than this was never picked up.
    static let lifetime: TimeInterval = 60

    /// Posted in the process that recorded the request.
    static let didRequest = Notification.Name("IntervallyPendingStartRequested")

    private struct Request: Codable {
        let workoutID: UUID?
        let requestedAt: Date
    }

    static func request(
        workoutID: UUID?,
        now: Date = Date(),
        defaults: UserDefaults = SharedDefaults.suite
    ) {
        let request = Request(workoutID: workoutID, requestedAt: now)
        guard let data = try? JSONEncoder().encode(request) else { return }
        defaults.set(data, forKey: key)
        NotificationCenter.default.post(name: didRequest, object: nil)
    }

    /// Returns and clears any live request. The outer optional says whether a start was
    /// requested; the inner one names a specific preset, or nil for the current selection.
    /// Expired or unreadable requests are cleared and ignored.
    static func consume(
        now: Date = Date(),
        defaults: UserDefaults = SharedDefaults.suite
    ) -> UUID?? {
        guard let data = defaults.data(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        guard let request = try? JSONDecoder().decode(Request.self, from: data) else { return nil }
        let age = now.timeIntervalSince(request.requestedAt)
        // A small negative age tolerates clock adjustment; a large one is not a real request.
        guard age < lifetime, age > -5 else { return nil }
        return .some(request.workoutID)
    }
}
