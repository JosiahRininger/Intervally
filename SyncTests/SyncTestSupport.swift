//
//  SyncTestSupport.swift
//  IntervallyTests, IntervallyPhoneTests
//

import Foundation
import WatchConnectivity
#if os(watchOS)
@testable import Intervally
#else
@testable import IntervallyPhone
#endif

// Compiled into both test bundles: sync runs on both devices, and each has branches the
// other doesn't.

extension PeerSnapshot {
    /// Activated, paired, and the other device has Intervally.
    static let ready = PeerSnapshot(
        isSupported: true,
        activationState: .activated,
        isPaired: true,
        isCounterpartInstalled: true,
        hasContentPending: false
    )
}

/// Stands in for `WCSession`: holds the two contexts as WatchConnectivity would and records
/// every send.
@MainActor
final class FakeTransport: SyncTransport {
    var snapshot: PeerSnapshot = .ready
    var applicationContext: [String: Any] = [:]
    var receivedApplicationContext: [String: Any] = [:]
    /// Thrown by the next sends, while set.
    var sendError: (any Error)?

    private(set) var sent: [[String: Any]] = []
    private(set) var activations = 0
    private(set) var onStateChange: (@MainActor @Sendable () -> Void)?

    var sentDocuments: [SyncDocument] { sent.compactMap(SyncWire.document(from:)) }

    func activate(delegate: any WCSessionDelegate, onStateChange: @escaping @MainActor @Sendable () -> Void) {
        activations += 1
        self.onStateChange = onStateChange
    }

    func updateApplicationContext(_ context: [String: Any]) throws {
        if let sendError { throw sendError }
        applicationContext = context
        sent.append(context)
    }
}

/// Stands in for `Task.sleep`: every sleep waits until the test wakes it, so a debounce is
/// as long as the test says.
@MainActor
final class ManualSleeper {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requested: [Duration] = []

    nonisolated var sleep: @Sendable (Duration) async throws -> Void {
        { [self] duration in await self.wait(duration) }
    }

    private func wait(_ duration: Duration) async {
        requested.append(duration)
        await withCheckedContinuation { waiters.append($0) }
    }

    func wakeAll() {
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// The other device: a copy of a document, edited with a clock of its own.
struct PeerDevice {
    var document: SyncDocument
    var clock = SyncClock(device: "peer-device")

    init(_ document: SyncDocument = .fresh) {
        self.document = document
        clock.observe(document)
    }

    mutating func rename(_ index: Int, to name: String) {
        var workout = document.workouts[index]
        workout.name = name
        document.upsert(workout, clock: &clock)
    }

    mutating func select(_ index: Int) {
        document.select(document.workouts[index].id, clock: &clock)
    }

    var context: [String: Any] {
        // A fixed instant: the tests compare documents, never send times.
        (try? SyncWire.context(for: document, sentAt: Date(timeIntervalSince1970: 1_000))) ?? [:]
    }
}

struct SendFailure: Error {}
