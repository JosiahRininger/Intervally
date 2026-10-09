//
//  SyncTransport.swift
//  Intervally
//

import Foundation
import WatchConnectivity

/// The other device as WatchConnectivity reports it, read in one go.
struct PeerSnapshot: Equatable, Sendable {
    /// False on iPad, and anywhere else without WatchConnectivity.
    var isSupported: Bool
    var activationState: WCSessionActivationState
    /// Whether this iPhone has an Apple Watch paired. Always true on the watch, which has no
    /// such question to ask.
    var isPaired: Bool
    /// Whether the other device has its half of Intervally: the watch app, seen from the
    /// iPhone; the iPhone app, seen from the watch.
    var isCounterpartInstalled: Bool
    /// WatchConnectivity still has something to hand this device.
    var hasContentPending: Bool

    static let unsupported = PeerSnapshot(
        isSupported: false,
        activationState: .notActivated,
        isPaired: false,
        isCounterpartInstalled: false,
        hasContentPending: false
    )
}

extension PeerSnapshot {
    /// Reads `session`. Pairing and installation mean nothing until the session has
    /// activated, so before that they read as false rather than as whatever it last knew.
    init(_ session: WCSession) {
        let activated = session.activationState == .activated
        #if os(iOS)
        let paired = activated && session.isPaired
        let installed = paired && session.isWatchAppInstalled
        #else
        let paired = true
        let installed = activated && session.isCompanionAppInstalled
        #endif
        self.init(
            isSupported: true,
            activationState: session.activationState,
            isPaired: paired,
            isCounterpartInstalled: installed,
            hasContentPending: session.hasContentPending
        )
    }
}

/// Where the other device stands: what the iPhone's watch status shows, and the one state
/// in which sync sends.
enum PeerState: Equatable, Sendable {
    /// No WatchConnectivity here, as on iPad. Everything else still works on its own.
    case unsupported
    /// Activation hasn't finished, or the iPhone is switching to another watch.
    case activating
    /// An iPhone with no Apple Watch paired.
    case notPaired
    /// The other device doesn't have Intervally.
    case appNotInstalled
    case ready

    init(_ snapshot: PeerSnapshot) {
        if !snapshot.isSupported {
            self = .unsupported
        } else if snapshot.activationState != .activated {
            self = .activating
        } else if !snapshot.isPaired {
            self = .notPaired
        } else if !snapshot.isCounterpartInstalled {
            self = .appNotInstalled
        } else {
            self = .ready
        }
    }
}

/// The few `WCSession` calls sync makes, so the tests can stand in for the session.
@MainActor
protocol SyncTransport: AnyObject {
    var snapshot: PeerSnapshot { get }
    /// The last context this device sent. WatchConnectivity keeps it across launches.
    var applicationContext: [String: Any] { get }
    /// The last context the other device sent, kept across launches too.
    var receivedApplicationContext: [String: Any] { get }
    /// Hands the session its delegate and activates it. `onStateChange` runs whenever the
    /// activation state or the pending content changes. Safe to call again, to reactivate.
    func activate(delegate: any WCSessionDelegate, onStateChange: @escaping @MainActor @Sendable () -> Void)
    func updateApplicationContext(_ context: [String: Any]) throws
}

/// The real transport: `WCSession.default`.
@MainActor
final class WCSessionTransport: SyncTransport {
    private let session: WCSession?
    private var observations: [NSKeyValueObservation] = []

    init(session: WCSession? = WCSessionTransport.defaultSession) {
        self.session = session
    }

    /// The default session where WatchConnectivity exists, but never in the unit-test host:
    /// a test run must not send its throwaway presets to the paired device.
    nonisolated static var defaultSession: WCSession? {
        WCSession.isSupported() && !UnitTestHost.isActive ? .default : nil
    }

    var snapshot: PeerSnapshot {
        session.map(PeerSnapshot.init) ?? .unsupported
    }

    var applicationContext: [String: Any] {
        session?.applicationContext ?? [:]
    }

    var receivedApplicationContext: [String: Any] {
        session?.receivedApplicationContext ?? [:]
    }

    func activate(delegate: any WCSessionDelegate, onStateChange: @escaping @MainActor @Sendable () -> Void) {
        guard let session else { return }
        session.delegate = delegate
        if observations.isEmpty {
            // Apple's SimpleWatchConnectivity sample watches these two to know when a
            // background wake has been handed everything. KVO calls back on any thread.
            observations = [
                session.observe(\.activationState) { _, _ in Task { @MainActor in onStateChange() } },
                session.observe(\.hasContentPending) { _, _ in Task { @MainActor in onStateChange() } },
            ]
        }
        session.activate()
    }

    func updateApplicationContext(_ context: [String: Any]) throws {
        try session?.updateApplicationContext(context)
    }
}
