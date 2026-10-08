//
//  ExtendedRuntimeController.swift
//  Intervally
//

import Foundation
import Observation
import WatchKit
import os

/// Keeps the app executing while a workout runs, using a `physical-therapy` extended
/// runtime session (declared in `WKBackgroundModes`).
///
/// Two things about this API bite hard, both confirmed against the watchOS SDK headers:
///
/// 1. **A session object is single-use.** Once `invalidate()` is called — or the system
///    invalidates it — that instance is dead and `start()` on it does nothing. The original
///    app held one `WKExtendedRuntimeSession` for the lifetime of the hosting controller
///    and called `start()` on it for every workout, so the first run consumed the session
///    and every subsequent run silently had no background time at all. This controller
///    creates a fresh session per run.
///
/// 2. **It must be started while the app is foreground-active**, otherwise the session
///    fails with `mustBeActiveToStartOrSchedule`.
///
/// The session survives the screen turning off and the wrist dropping, which is the case
/// that matters mid-set. It does *not* survive the user leaving the app — the system
/// invalidates with `resignedFrontmost`. Time keeps being tracked correctly regardless,
/// because elapsed time is derived from the clock; what is lost is the ability to fire a
/// haptic, which is why boundaries are also scheduled as local notifications.
@MainActor
@Observable
final class ExtendedRuntimeController: NSObject {

    enum State: Equatable {
        case idle
        case running
        case ended(reason: String)
    }

    private(set) var state: State = .idle
    @ObservationIgnored private var session: WKExtendedRuntimeSession?
    @ObservationIgnored private let log = Logger(subsystem: "com.josiahrininger.intervally", category: "runtime-session")

    /// Called when the system tears the session down early, so the coordinator can fall
    /// back to notification-only alerting.
    @ObservationIgnored var onInvalidate: (() -> Void)?

    func start() {
        guard session == nil else { return }
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        self.session = session
        session.start()
    }

    func stop() {
        // Detach first. Invalidation is reported asynchronously, and a session we have
        // already let go of must not report back: on a quick Repeat its late callback would
        // otherwise land after the next run's session had been created, and tear that one
        // down instead.
        session?.delegate = nil
        session?.invalidate()
        session = nil
        state = .idle
    }
}

// The delegate callbacks are not annotated for main-actor isolation in WatchKit, so the
// conformance is nonisolated and hops explicitly.
extension ExtendedRuntimeController: WKExtendedRuntimeSessionDelegate {

    nonisolated func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {
        Task { @MainActor in
            self.state = .running
            self.log.info("extended runtime session started")
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {
        Task { @MainActor in
            self.log.info("extended runtime session will expire")
        }
    }

    nonisolated func extendedRuntimeSession(
        _ session: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        let description = Self.describe(reason)
        // Compared by identity: the session object itself is not Sendable, so it cannot
        // cross into the main-actor task, but its identity can.
        let invalidated = ObjectIdentifier(session)
        Task { @MainActor in
            // Ignore a session that is no longer ours — only the current one may clear state.
            guard let current = self.session, ObjectIdentifier(current) == invalidated else {
                return
            }
            if let error {
                self.log.error("session invalidated: \(description, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            } else {
                self.log.info("session invalidated: \(description, privacy: .public)")
            }
            self.session = nil
            self.state = .ended(reason: description)
            self.onInvalidate?()
        }
    }

    private nonisolated static func describe(_ reason: WKExtendedRuntimeSessionInvalidationReason) -> String {
        switch reason {
        case .none: "ended"
        case .sessionInProgress: "another session already running"
        case .expired: "expired"
        case .resignedFrontmost: "app left the foreground"
        case .suppressedBySystem: "suppressed by the system"
        case .error: "error"
        @unknown default: "unknown"
        }
    }
}
