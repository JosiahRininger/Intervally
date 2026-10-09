//
//  WatchSyncTests.swift
//  IntervallyTests, IntervallyPhoneTests
//

import Foundation
import Testing
import WatchConnectivity
#if os(watchOS)
@testable import Intervally
#else
@testable import IntervallyPhone
#endif

/// When sync sends, what it does with what arrives, and how the two devices settle.
@Suite("Watch sync")
@MainActor
struct WatchSyncTests {
    let defaults = makeTestDefaults()
    let transport = FakeTransport()
    let sleeper = ManualSleeper()

    /// A debounce that never ends, so only what a test sends directly goes out.
    nonisolated static let neverSends: @Sendable (Duration) async throws -> Void = { _ in throw CancellationError() }

    private func makeSync(
        store: WorkoutStore? = nil,
        sleep: @escaping @Sendable (Duration) async throws -> Void = neverSends
    ) -> (WatchSync, WorkoutStore) {
        let store = store ?? WorkoutStore(defaults: defaults)
        let sync = WatchSync(store: store, transport: transport, sleep: sleep, now: { Date(timeIntervalSince1970: 5_000) })
        return (sync, store)
    }

    private func renameFirst(_ store: WorkoutStore, to name: String) {
        var workout = store.workouts[0]
        workout.name = name
        store.update(workout)
    }

    // MARK: Gates

    nonisolated static let unreachable: [PeerSnapshot] = {
        var notActivated = PeerSnapshot.ready
        notActivated.activationState = .notActivated
        var inactive = PeerSnapshot.ready
        inactive.activationState = .inactive
        var notPaired = PeerSnapshot.ready
        notPaired.isPaired = false
        var notInstalled = PeerSnapshot.ready
        notInstalled.isCounterpartInstalled = false
        return [.unsupported, notActivated, inactive, notPaired, notInstalled]
    }()

    @Test("Nothing is sent unless the session is activated and the other device has the app", arguments: unreachable)
    func gates(_ snapshot: PeerSnapshot) {
        transport.snapshot = snapshot
        let (sync, _) = makeSync()
        sync.push(force: true)
        sync.sessionDidActivate()
        #expect(transport.sent.isEmpty)
        #expect(sync.lastSentAt == nil)

        transport.snapshot = .ready
        sync.push()
        #expect(transport.sentDocuments.count == 1)
    }

    @Test("A document is sent once: an unchanged one isn't sent again, even by a new launch")
    func unchangedIsNotResent() {
        let (sync, store) = makeSync()
        sync.push()
        sync.push()
        #expect(transport.sentDocuments == [store.document])
        #expect(sync.lastSentAt == Date(timeIntervalSince1970: 5_000))

        // WatchConnectivity keeps the last context sent across launches.
        let (relaunched, _) = makeSync(store: WorkoutStore(defaults: defaults))
        relaunched.push()
        #expect(transport.sent.count == 1)
    }

    @Test("A forced send goes even when unchanged, so a reinstalled counterpart gets it")
    func forcedSendsUnchanged() {
        let (sync, store) = makeSync()
        sync.push()
        sync.counterpartDidChange()
        #expect(transport.sentDocuments == [store.document, store.document])
        #expect(transport.sent.allSatisfy { SyncWire.sentAt(from: $0) != nil })
    }

    @Test("Each context names its send time")
    func contextCarriesSendTime() throws {
        let context = try SyncWire.context(for: .fresh, sentAt: Date(timeIntervalSince1970: 42))
        #expect(SyncWire.sentAt(from: context) == Date(timeIntervalSince1970: 42))
        #expect(SyncWire.sentAt(from: [:]) == nil)
        #expect(SyncWire.sentAt(from: ["sentAt": "yesterday"]) == nil)
    }

    @Test("A failed send is survived, and isn't recorded as sent")
    func failedSend() {
        transport.sendError = SendFailure()
        let (sync, _) = makeSync()
        sync.push()
        #expect(transport.sent.isEmpty)
        #expect(sync.lastSentAt == nil)

        transport.sendError = nil
        sync.push()
        #expect(transport.sent.count == 1)
    }

    // MARK: Receiving

    @Test("No reply to a document this device already holds")
    func noReplyToIdentical() {
        let (sync, store) = makeSync()
        let applied = Counter()
        sync.onRemoteApplied = { _ in applied.increment() }
        sync.receive(store.document)
        #expect(transport.sent.isEmpty)
        #expect(applied.value == 0)
        #expect(sync.lastReceivedAt == Date(timeIntervalSince1970: 5_000))
    }

    @Test("No reply when the merge is exactly what arrived, though it is applied")
    func noReplyWhenSenderIsAhead() {
        let (sync, store) = makeSync()
        var peer = PeerDevice()
        peer.rename(1, to: "Sprints")
        sync.receive(peer.document)
        #expect(store.workouts[1].name == "Sprints")
        #expect(store.document == peer.document)
        #expect(transport.sent.isEmpty)
    }

    @Test("A reply when the merge holds something the sender lacks, and it holds both sides")
    func replyWhenMergeDiffers() throws {
        let (sync, store) = makeSync()
        renameFirst(store, to: "Mine")
        var peer = PeerDevice()
        peer.rename(2, to: "Theirs")
        sync.receive(peer.document)

        let reply = try #require(transport.sentDocuments.last)
        #expect(transport.sent.count == 1)
        #expect(reply == store.document)
        #expect(reply.workouts.map(\.name) == ["Mine", "Tabata", "Theirs"])
    }

    @Test("A reply goes even if this device sent that document before: the sender may have been reinstalled")
    func replyIsForced() {
        let (sync, store) = makeSync()
        renameFirst(store, to: "Mine")
        sync.push()
        // A reinstalled watch app starts again from the starters, and says so.
        sync.receive(SyncDocument.fresh)
        #expect(transport.sentDocuments == [store.document, store.document])
        #expect(store.workouts[0].name == "Mine")
    }

    @Test("Nothing is sent to a device whose own last document is this one")
    func skipsWhatTheOtherDeviceSent() throws {
        let (sync, store) = makeSync()
        var peer = PeerDevice()
        peer.rename(1, to: "Theirs")
        store.merge(peer.document)
        transport.receivedApplicationContext = peer.context

        sync.push()
        #expect(transport.sent.isEmpty)
        sync.push(force: true)
        #expect(transport.sentDocuments == [store.document])
    }

    @Test("Launching after the other device's edits takes them, and sends nothing back")
    func activationAfterRemoteEdits() throws {
        let (first, store) = makeSync()
        first.push()
        var peer = PeerDevice(store.document)
        peer.rename(0, to: "From the watch")
        peer.select(2)
        transport.receivedApplicationContext = peer.context

        let (sync, relaunched) = makeSync(store: WorkoutStore(defaults: defaults))
        sync.sessionDidActivate()
        #expect(relaunched.workouts[0].name == "From the watch")
        #expect(relaunched.selected.name == "EMOM")
        #expect(transport.sent.count == 1)
    }

    @Test("A context that isn't a sync document changes nothing and gets no reply")
    func garbageIgnored() {
        let (sync, store) = makeSync()
        renameFirst(store, to: "Mine")
        let before = store.document
        sync.receive(nil)
        #expect(store.document == before)
        #expect(transport.sent.isEmpty)
        #expect(sync.lastReceivedAt == nil)

        for garbage: [String: Any] in [[:], ["doc": "text"], ["doc": Data([1, 2, 3])], ["schema": 1]] {
            #expect(SyncWire.document(from: garbage) == nil)
        }
    }

    @Test("A suspended store neither applies what arrives nor sends")
    func suspendedStore() {
        defaults.set(Data("not a document".utf8), forKey: WorkoutStore.Key.document)
        let store = WorkoutStore(defaults: defaults)
        #expect(store.isSyncSuspended)
        let (sync, _) = makeSync(store: store)

        var peer = PeerDevice()
        peer.rename(0, to: "Remote")
        sync.receive(peer.document)
        transport.receivedApplicationContext = peer.context
        sync.sessionDidActivate()
        sync.push(force: true)

        #expect(store.workouts[0].name == "Classic")
        #expect(transport.sent.isEmpty)
        #expect(defaults.data(forKey: WorkoutStore.Key.document) == Data("not a document".utf8))
    }

    @Test("A merge is reported, and says whether the selected preset changed")
    func remoteAppliedReports() throws {
        let (sync, _) = makeSync()
        var results: [WorkoutStore.MergeResult] = []
        sync.onRemoteApplied = { results.append($0) }

        var peer = PeerDevice()
        peer.rename(2, to: "Hills")
        sync.receive(peer.document)
        peer.select(1)
        sync.receive(peer.document)
        sync.receive(peer.document)

        #expect(results.count == 2)
        #expect(results.map(\.selectedPresetChanged) == [false, true])
    }

    // MARK: Activation

    @Test("Activation merges what arrived while the app was closed, then sends what the other device lacks")
    func activationMergesPending() throws {
        let (sync, store) = makeSync()
        renameFirst(store, to: "Mine")
        var peer = PeerDevice()
        peer.rename(1, to: "Theirs")
        transport.receivedApplicationContext = peer.context

        sync.sessionDidActivate()

        #expect(store.workouts.map(\.name) == ["Mine", "Theirs", "EMOM"])
        #expect(transport.sentDocuments == [store.document])
        // The other device's send time, as it said, until something newer arrives.
        #expect(sync.lastReceivedAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test("Activation with nothing new sends nothing, and keeps the last send time")
    func activationWithNothingNew() throws {
        let (first, store) = makeSync()
        first.push()
        #expect(transport.sent.count == 1)

        let (sync, _) = makeSync(store: WorkoutStore(defaults: defaults))
        transport.receivedApplicationContext = try SyncWire.context(for: store.document, sentAt: Date(timeIntervalSince1970: 900))
        sync.sessionDidActivate()
        #expect(transport.sent.count == 1)
        #expect(sync.lastSentAt == Date(timeIntervalSince1970: 5_000))
        #expect(sync.lastReceivedAt == Date(timeIntervalSince1970: 900))
    }

    @Test("activate() starts the session once, and never where WatchConnectivity is missing")
    func activateOnce() {
        transport.snapshot = .unsupported
        let (unsupported, _) = makeSync()
        unsupported.activate()
        #expect(transport.activations == 0)
        #expect(unsupported.isActive == false)
        #expect(unsupported.peer == .unsupported)

        transport.snapshot = .ready
        let (sync, _) = makeSync()
        sync.activate()
        sync.activate()
        #expect(transport.activations == 1)
        #expect(sync.isActive)
        #expect(sync.activity.isActive)
    }

    @Test("The peer follows the session, and a state change is passed on")
    func peerFollowsSession() {
        var snapshot = PeerSnapshot.ready
        snapshot.activationState = .notActivated
        transport.snapshot = snapshot
        let (sync, _) = makeSync()
        let changes = Counter()
        sync.onStateChange = { changes.increment() }
        #expect(sync.peer == .activating)
        sync.activate()

        snapshot.activationState = .activated
        snapshot.isCounterpartInstalled = false
        transport.snapshot = snapshot
        transport.onStateChange?()
        #expect(sync.peer == .appNotInstalled)
        #expect(changes.value == 1)

        transport.snapshot = .ready
        sync.counterpartDidChange()
        #expect(sync.peer == .ready)
    }

    // MARK: Debounce

    @Test("Ten rapid edits are sent once, after the debounce")
    func debounce() async throws {
        let (sync, store) = makeSync(sleep: sleeper.sleep)
        for seconds in stride(from: 35, through: 80, by: 5) {
            var workout = store.selected
            workout.workSeconds = seconds
            store.update(workout)
        }
        #expect(transport.sent.isEmpty)
        #expect(await waitUntil { sleeper.requested.count == 10 })
        #expect(sleeper.requested.allSatisfy { $0 == .milliseconds(800) })

        sleeper.wakeAll()
        #expect(await waitUntil { transport.sent.count == 1 })
        try await Task.sleep(for: .milliseconds(100))
        #expect(transport.sentDocuments == [store.document])
        #expect(store.selected.workSeconds == 80)
        withExtendedLifetime(sync) {}
    }

    @Test("flush() sends a waiting edit at once; with nothing waiting it sends nothing")
    func flush() async throws {
        let (sync, store) = makeSync(sleep: sleeper.sleep)
        sync.flush()
        #expect(transport.sent.isEmpty)

        renameFirst(store, to: "Now")
        sync.flush()
        #expect(transport.sentDocuments == [store.document])

        // The debounce that was waiting finds nothing left to send.
        #expect(await waitUntil { sleeper.requested.count == 1 })
        sleeper.wakeAll()
        try await Task.sleep(for: .milliseconds(100))
        #expect(transport.sent.count == 1)
        withExtendedLifetime(sync) {}
    }

    @Test("A merge never schedules a send of its own")
    func mergeDoesNotDebounce() async throws {
        let (sync, _) = makeSync(sleep: sleeper.sleep)
        var peer = PeerDevice()
        peer.rename(0, to: "Remote")
        sync.receive(peer.document)
        try await Task.sleep(for: .milliseconds(50))
        #expect(sleeper.requested.isEmpty)
    }

    // MARK: Two devices

    /// Delivers everything `from` sent since `since`, as WatchConnectivity would: only the
    /// latest context arrives. Returns how many were sent.
    private func deliverLatest(from sender: FakeTransport, since: Int, to receiver: WatchSync) -> Int {
        guard sender.sent.count > since, let last = sender.sent.last else { return 0 }
        receiver.receive(SyncWire.document(from: last))
        return sender.sent.count - since
    }

    @Test("Two devices editing at once settle on the same presets within two exchanges")
    func twoDevicesConverge() {
        let phoneTransport = FakeTransport()
        let watchTransport = FakeTransport()
        let phoneStore = WorkoutStore(defaults: makeTestDefaults())
        let watchStore = WorkoutStore(defaults: makeTestDefaults())
        let phone = WatchSync(store: phoneStore, transport: phoneTransport, sleep: Self.neverSends)
        let watch = WatchSync(store: watchStore, transport: watchTransport, sleep: Self.neverSends)

        renameFirst(phoneStore, to: "Phone")
        watchStore.delete(watchStore.workouts[2])
        watchStore.selectedID = watchStore.workouts[1].id
        phone.push()
        watch.push()

        var phoneSent = 0, watchSent = 0, exchanges = 0
        while exchanges < 10 {
            let toWatch = deliverLatest(from: phoneTransport, since: phoneSent, to: watch)
            phoneSent = phoneTransport.sent.count
            let toPhone = deliverLatest(from: watchTransport, since: watchSent, to: phone)
            watchSent = watchTransport.sent.count
            if toWatch == 0 && toPhone == 0 { break }
            exchanges += 1
        }

        #expect(phoneStore.document == watchStore.document)
        #expect(phoneStore.workouts.map(\.name) == ["Phone", "Tabata"])
        #expect(phoneStore.selected.name == "Tabata")
        #expect(exchanges <= 2)
    }

    @Test("Two fresh installs sync to the three starters, never six")
    func freshInstallsStayThree() {
        let (phone, phoneStore) = makeSync()
        let watchStore = WorkoutStore(defaults: makeTestDefaults())
        phone.push()
        let result = watchStore.merge(transport.sentDocuments[0])
        #expect(result.changed == false)
        #expect(watchStore.workouts.count == 3)
        #expect(phoneStore.workouts.count == 3)
    }
}
