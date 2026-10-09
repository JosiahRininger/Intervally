//
//  WatchSync.swift
//  Intervally
//

import Foundation
import Observation
import WatchConnectivity
import os

/// What a background wake waits on before the watch hands it back.
struct SyncActivity: Equatable, Sendable {
    /// Sync was started. If not, nothing is coming and there is nothing to wait for.
    var isActive: Bool
    var isActivated: Bool
    var hasContentPending: Bool
    /// Delegate callbacks still on their way to the main actor.
    var deliveriesInFlight: Int

    /// Sync never started.
    static let inactive = SyncActivity(isActive: false, isActivated: false, hasContentPending: false, deliveriesInFlight: 0)
}

/// Keeps the presets on the iPhone and the watch the same, over WatchConnectivity.
///
/// One channel, both ways: `updateApplicationContext(_:)` carrying this device's whole
/// `SyncDocument`. It reaches a counterpart that isn't running, replaces anything older that
/// is still undelivered, and works in the Simulator. The receiver merges and never replaces,
/// then replies only if the merge holds something the sender lacks, so the two settle within
/// two exchanges. Each device's own store stays primary: with no counterpart, sync idles.
///
/// The delegate methods are `nonisolated`, as WatchConnectivity calls them on a background
/// serial queue. Each turns what it was handed into Sendable values and hops to the main
/// actor. Never make the conformance `@preconcurrency` or isolated: it compiles, then traps
/// at runtime on the first callback (`DelegateQueueTests`).
@MainActor
@Observable
final class WatchSync: NSObject {

    /// Where the other device stands, for the iPhone's status card. A send checks the
    /// session itself at that moment rather than this.
    private(set) var peer: PeerState
    private(set) var lastSentAt: Date?
    private(set) var lastReceivedAt: Date?

    /// A merge took something from the other device. Not called when nothing changed.
    @ObservationIgnored var onRemoteApplied: ((WorkoutStore.MergeResult) -> Void)?
    /// Something a background wake waits on may have changed (`activity`).
    @ObservationIgnored var onStateChange: (() -> Void)?

    /// Whether `activate()` started the session.
    @ObservationIgnored private(set) var isActive = false

    @ObservationIgnored private let store: WorkoutStore
    @ObservationIgnored private let transport: any SyncTransport
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var pendingPush: Task<Void, Never>?

    /// Written on the delegate queue, read on the main actor.
    private nonisolated let inFlight = OSAllocatedUnfairLock(initialState: 0)
    private nonisolated let log = Logger(subsystem: "com.josiahrininger.intervally", category: "sync")

    /// - Parameter debounce: how long local edits settle before they are sent. A crown turn
    ///   saves on every detent; the other device needs only where it stopped.
    init(
        store: WorkoutStore,
        transport: any SyncTransport = WCSessionTransport(),
        debounce: Duration = .milliseconds(800),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.transport = transport
        self.debounce = debounce
        self.sleep = sleep
        self.now = now
        self.peer = PeerState(transport.snapshot)
        super.init()
        store.onLocalChange = { [weak self] in self?.localDidChange() }
    }

    /// Starts WatchConnectivity, once. Call as early as the app starts, so a context that
    /// woke it is taken. Does nothing where WatchConnectivity doesn't exist, such as iPad.
    func activate() {
        guard !isActive, transport.snapshot.isSupported else { return }
        isActive = true
        log.info("activating")
        transport.activate(delegate: self) { [weak self] in self?.sessionStateDidChange() }
    }

    var activity: SyncActivity {
        let snapshot = transport.snapshot
        return SyncActivity(
            isActive: isActive,
            isActivated: snapshot.activationState == .activated,
            hasContentPending: snapshot.hasContentPending,
            deliveriesInFlight: inFlight.withLock { $0 }
        )
    }

    // MARK: - Sending

    /// A local edit: sent once edits have paused for `debounce`.
    func localDidChange() {
        pendingPush?.cancel()
        let sleep = sleep
        let debounce = debounce
        pendingPush = Task { [weak self] in
            do { try await sleep(debounce) } catch { return }
            guard !Task.isCancelled else { return }
            self?.push()
        }
    }

    /// Sends an edit still waiting out the debounce now. For the app leaving the foreground,
    /// after which it may not run again for a long while.
    func flush() {
        guard pendingPush != nil else { return }
        push()
    }

    /// Sends this device's document, unless nobody can take it or the other device already
    /// holds it: every send may wake the other device. `force` sends anyway, to a counterpart
    /// that may have lost what it held, such as a reinstalled app; `sentAt` keeps even an
    /// identical document from being coalesced away.
    func push(force: Bool = false) {
        pendingPush?.cancel()
        pendingPush = nil
        guard PeerState(transport.snapshot) == .ready else { return }
        guard !store.isSyncSuspended else {
            log.error("not sending: the stored presets didn't decode, so sync is suspended")
            return
        }
        let document = store.document
        if !force, otherDeviceHolds(document) {
            log.debug("not sending: the other device has this already")
            return
        }
        do {
            let sentAt = now()
            try transport.updateApplicationContext(SyncWire.context(for: document, sentAt: sentAt))
            lastSentAt = sentAt
            log.info("sent \(document.workouts.count) presets\(force ? " (forced)" : "", privacy: .public)")
        } catch {
            log.error("send failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Whether the other device already holds everything in `document`: it is what this
    /// device last sent, or what the other device last sent, which it has only added to since.
    /// A reinstall breaks that, and is why replies and installs send with `force`.
    private func otherDeviceHolds(_ document: SyncDocument) -> Bool {
        SyncWire.document(from: transport.applicationContext) == document
            || SyncWire.document(from: transport.receivedApplicationContext) == document
    }

    // MARK: - Receiving

    /// A context the other device just delivered; nil if it held no readable document. It is
    /// the sender's state, so if the merge holds more, the sender lacks that, whatever this
    /// device sent it before: the reply is forced, as the sender may have been reinstalled.
    /// Once both hold the same, neither replies, which is what ends the exchange.
    func receive(_ remote: SyncDocument?) {
        guard let remote else {
            log.error("ignored a context that isn't a sync document")
            return
        }
        lastReceivedAt = now()
        if merge(remote)?.mergedDiffersFromRemote == true { push(force: true) }
    }

    /// Merges, never replaces. A suspended store applies nothing, so an unreadable local copy
    /// can't be merged over. Nil when nothing was merged.
    @discardableResult
    private func merge(_ remote: SyncDocument) -> WorkoutStore.MergeResult? {
        guard !store.isSyncSuspended else {
            log.error("not merging: the stored presets didn't decode, so sync is suspended")
            return nil
        }
        let result = store.merge(remote)
        log.info(
            "merged \(remote.workouts.count) presets: changed \(result.changed), selection changed \(result.selectedPresetChanged), sender lacks some \(result.mergedDiffersFromRemote)"
        )
        if result.changed { onRemoteApplied?(result) }
        return result
    }

    // MARK: - Session events (main-actor halves of the delegate methods)

    /// Takes whatever arrived while the app wasn't running, then offers what the other
    /// device lacks: that is how a freshly installed watch hands over its presets.
    func sessionDidActivate(failure: String? = nil) {
        if let failure { log.error("activation failed: \(failure, privacy: .public)") }
        refreshPeer()
        let received = transport.receivedApplicationContext
        lastSentAt = lastSentAt ?? SyncWire.sentAt(from: transport.applicationContext)
        lastReceivedAt = lastReceivedAt ?? SyncWire.sentAt(from: received)
        // The last context that arrived, which this launch may not have seen. It may be old,
        // so whether to answer is left to push(), which skips what the other device holds.
        if let pending = SyncWire.document(from: received) { merge(pending) }
        push()
    }

    /// The other device's app was installed or removed, or (iPhone) the watch was paired or
    /// unpaired. A reinstalled app starts empty-handed, so send even an unchanged document.
    func counterpartDidChange() {
        refreshPeer()
        push(force: true)
    }

    /// The iPhone moved to another watch: reactivate, which reconnects to the new one.
    func sessionDidDeactivate() {
        refreshPeer()
        transport.activate(delegate: self) { [weak self] in self?.sessionStateDidChange() }
    }

    func refreshPeer() {
        let state = PeerState(transport.snapshot)
        guard state != peer else { return }
        log.info("peer: \(String(describing: state), privacy: .public)")
        peer = state
    }

    private func sessionStateDidChange() {
        refreshPeer()
        onStateChange?()
    }
}

// MARK: - WCSessionDelegate

extension WatchSync: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let failure = error?.localizedDescription
        deliver { $0.sessionDidActivate(failure: failure) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // Decoded here: the dictionary isn't Sendable, the document is.
        let remote = SyncWire.document(from: applicationContext)
        deliver { $0.receive(remote) }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        deliver { $0.refreshPeer() }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        deliver { $0.sessionDidDeactivate() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        deliver { $0.counterpartDidChange() }
    }
    #else
    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        deliver { $0.counterpartDidChange() }
    }
    #endif

    /// Every callback's hop to the main actor, counted while in flight so a background wake
    /// isn't handed back between a context arriving and its merge.
    private nonisolated func deliver(_ work: @escaping @MainActor @Sendable (WatchSync) -> Void) {
        inFlight.withLock { $0 += 1 }
        Task { @MainActor in
            work(self)
            self.inFlight.withLock { $0 -= 1 }
            self.onStateChange?()
        }
    }
}
