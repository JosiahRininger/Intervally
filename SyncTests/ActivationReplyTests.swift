//
//  ActivationReplyTests.swift
//  IntervallyTests, IntervallyPhoneTests
//

import Foundation
import Testing
#if os(watchOS)
@testable import Intervally
#else
@testable import IntervallyPhone
#endif

/// What activation sends to a device whose last context lacks writes this one holds, though
/// this one sent them before: the whole document again, once, and not at every launch after.
@Suite("Activation reply")
@MainActor
struct ActivationReplyTests {
    let defaults = makeTestDefaults()
    let transport = FakeTransport()

    /// One launch of the app: its store and sync on this device's defaults, which outlive
    /// it, as the session's two contexts do (WatchConnectivity keeps them across launches).
    private func launch() -> (WatchSync, WorkoutStore) {
        Self.launch(defaults: defaults, transport: transport)
    }

    private static func launch(defaults: UserDefaults, transport: FakeTransport) -> (WatchSync, WorkoutStore) {
        let store = WorkoutStore(defaults: defaults)
        let sync = WatchSync(
            store: store, transport: transport, sleep: WatchSyncTests.neverSends,
            now: { Date(timeIntervalSince1970: 5_000) }, defaults: defaults
        )
        return (sync, store)
    }

    private static func rename(_ store: WorkoutStore, _ index: Int, to name: String) {
        var workout = store.workouts[index]
        workout.name = name
        store.update(workout)
    }

    /// This device renamed a preset and sent it, but the other device never took that send:
    /// its last context, all this device knows of it, still holds only the starters.
    private func peerMissesTheLastSend() throws {
        let (sync, store) = launch()
        transport.receivedApplicationContext = PeerDevice().context
        Self.rename(store, 0, to: "Mine")
        try #require(sync.push())
    }

    @Test("Activation sends the whole document again, forced, to a device whose last context lacks some of it")
    func replySentWhenPeerBehind() throws {
        try peerMissesTheLastSend()
        #expect(transport.sent.count == 1)

        let (sync, store) = launch()
        sync.sessionDidActivate()
        #expect(transport.sent.count == 2, "An ordinary push skips a document it sent before")
        #expect(transport.sentDocuments.last == store.document)
        #expect(store.workouts[0].name == "Mine")
    }

    @Test("A context still behind at the next launch isn't answered again, nor is one that holds everything")
    func noReplyLoop() throws {
        try peerMissesTheLastSend()
        launch().0.sessionDidActivate()
        #expect(transport.sent.count == 2)

        // The other device took the answer and had nothing to add, so it sent nothing back:
        // its last context still holds only the starters.
        for _ in 0..<3 { launch().0.sessionDidActivate() }
        #expect(transport.sent.count == 2)

        // An edit made since goes out as any edit does, and the next launch adds nothing.
        let (editing, store) = launch()
        Self.rename(store, 1, to: "Later")
        #expect(editing.push())
        launch().0.sessionDidActivate()
        #expect(transport.sent.count == 3)

        // Once the other device does send, it holds what this one holds: nothing to answer.
        transport.receivedApplicationContext = try SyncWire.context(for: store.document)
        launch().0.sessionDidActivate()
        #expect(transport.sent.count == 3)
    }

    @Test("Two devices that both answer at activation settle once, and stay settled launch after launch")
    func noReplyLoopBetweenTwoDevices() throws {
        let phoneDefaults = makeTestDefaults(), watchDefaults = makeTestDefaults()
        let phoneTransport = FakeTransport(), watchTransport = FakeTransport()
        func launchPhone() -> (WatchSync, WorkoutStore) { Self.launch(defaults: phoneDefaults, transport: phoneTransport) }
        func launchWatch() -> (WatchSync, WorkoutStore) { Self.launch(defaults: watchDefaults, transport: watchTransport) }
        /// The last context `from` sent arrives at `to`, while it runs.
        func deliver(_ from: FakeTransport, to: FakeTransport, _ receiver: WatchSync) {
            guard let last = from.sent.last else { return }
            to.receivedApplicationContext = last
            receiver.receive(SyncWire.document(from: last))
        }

        // The watch's first launch hands the iPhone its starters.
        launchWatch().0.sessionDidActivate()
        deliver(watchTransport, to: phoneTransport, launchPhone().0)
        // An edit on the iPhone that the watch never takes.
        let (phone, phoneStore) = launchPhone()
        Self.rename(phoneStore, 2, to: "Hills")
        #expect(phone.push())
        #expect(phoneTransport.sent.count == 1)

        // The iPhone's next launch answers; the watch takes it and has nothing to add.
        let (answering, _) = launchPhone()
        answering.sessionDidActivate()
        #expect(phoneTransport.sent.count == 2)
        let (watch, watchStore) = launchWatch()
        deliver(phoneTransport, to: watchTransport, watch)
        #expect(watchStore.document == phoneStore.document)
        #expect(watchTransport.sent.count == 1, "The watch holds nothing the iPhone lacks")

        for _ in 0..<3 {
            launchPhone().0.sessionDidActivate()
            launchWatch().0.sessionDidActivate()
        }
        #expect(phoneTransport.sent.count == 2)
        #expect(watchTransport.sent.count == 1)
    }

    @Test("A later context that is still behind is answered too: each is answered once")
    func laterContextAnswered() throws {
        try peerMissesTheLastSend()
        launch().0.sessionDidActivate()
        #expect(transport.sent.count == 2)

        // The other device edited something else, still without this device's rename.
        var peer = PeerDevice()
        peer.rename(2, to: "Theirs")
        transport.receivedApplicationContext = peer.context
        let (sync, store) = launch()
        sync.sessionDidActivate()
        #expect(store.workouts.map(\.name) == ["Mine", "Tabata", "Theirs"])
        #expect(transport.sent.count == 3)
        #expect(transport.sentDocuments.last == store.document)
    }

    @Test("A device reinstalled after an answer sends the same starters again, and is answered again, once")
    func reinstalledPeerAnswered() throws {
        try peerMissesTheLastSend()
        launch().0.sessionDidActivate()
        #expect(transport.sent.count == 2)

        // Reinstalled, the other device starts from the starters again: the same digest as
        // the context just answered, but a new send.
        let reinstalled = try SyncWire.context(for: .fresh, sentAt: Date(timeIntervalSince1970: 2_000))
        #expect(SyncWire.document(from: reinstalled)?.digest == SyncWire.document(from: PeerDevice().context)?.digest)
        transport.receivedApplicationContext = reinstalled
        let (sync, store) = launch()
        sync.sessionDidActivate()
        #expect(transport.sent.count == 3)
        #expect(transport.sentDocuments.last == store.document)

        // It took the answer and had nothing to add: that context isn't answered again.
        for _ in 0..<3 { launch().0.sessionDidActivate() }
        #expect(transport.sent.count == 3)
    }

    @Test("A context that doesn't say when it was sent is answered once, by its digest")
    func contextWithoutSentAtAnsweredOnce() throws {
        try peerMissesTheLastSend()
        var undated = PeerDevice().context
        undated[SyncWire.sentAtKey] = nil
        transport.receivedApplicationContext = undated
        for _ in 0..<3 { launch().0.sessionDidActivate() }
        #expect(transport.sent.count == 2)
        #expect(defaults.string(forKey: WatchSync.activationReplyKey) == SyncDocument.fresh.digest)
    }

    @Test("An answer that couldn't be sent is tried again at the next launch")
    func failedReplyRetried() throws {
        try peerMissesTheLastSend()
        transport.sendError = SendFailure()
        launch().0.sessionDidActivate()
        #expect(transport.sent.count == 1)

        transport.sendError = nil
        launch().0.sessionDidActivate()
        #expect(transport.sent.count == 2)
    }

    @Test("A device behind only in fields its version doesn't know is never answered for them")
    func olderVersionNotBehindForFieldsItDrops() throws {
        let (first, store) = launch()
        store.setActivity(store.workouts[0].id, to: .rowing)
        store.setLabel(store.workouts[1].id, kind: .work, to: PhaseLabel(name: "Climb", symbol: .run))
        #expect(first.push())
        // 1.1 holds both presets at the same stamps, without the activity and the phase name.
        transport.receivedApplicationContext = try SyncWire.context(for: OlderVersion.v11.reading(store.document))

        let (sync, relaunched) = launch()
        sync.sessionDidActivate()
        #expect(transport.sent.count == 1)
        #expect(relaunched.workouts[0].activity == .rowing)
    }

    @Test("A suspended store answers nothing at activation, and remembers no answer")
    func suspendedStoreDoesNotAnswer() throws {
        // The document won't decode; the copies beside it hold a preset the starters lack.
        defaults.set(Data("not a document".utf8), forKey: WorkoutStore.Key.document)
        defaults.set(try JSONEncoder().encode([IntervalWorkout(name: "Kept")]), forKey: WorkoutStore.Key.workouts)
        transport.receivedApplicationContext = PeerDevice().context
        let (sync, store) = launch()
        try #require(store.isSyncSuspended)
        #expect(store.document.digest != SyncDocument.fresh.digest)

        sync.sessionDidActivate()
        #expect(transport.sent.isEmpty)
        #expect(defaults.string(forKey: WatchSync.activationReplyKey) == nil)
        #expect(store.workouts.map(\.name) == ["Kept"])
    }

    // MARK: Digest

    @Test("The digest is ids and stamps: fields an older version drops leave it alone, and every write changes it")
    func digestIsIdsAndStamps() {
        let fresh = SyncDocument.fresh
        let ids = SyncDocument.starterIDs
        var clock = SyncClock(device: "this-device")
        #expect(fresh.digest == SyncDocument.fresh.digest)

        // The same writes with more fields, or fewer, as two versions hold them.
        var filled = fresh
        filled.presets[ids[0]]?.workout.activity = .rowing
        #expect(filled.digest == fresh.digest)
        #expect(OlderVersion.v11.reading(filled).digest == filled.digest)

        var edited = fresh
        var workout = fresh.workouts[0]
        workout.name = "Hills"
        edited.upsert(workout, clock: &clock)
        var added = fresh
        added.upsert(IntervalWorkout(name: "New"), clock: &clock)
        var deleted = fresh
        deleted.delete(ids[2], clock: &clock)
        var moved = fresh
        moved.move(fromOffsets: [0], toOffset: 3, clock: &clock)
        var chosen = fresh
        chosen.select(ids[1], clock: &clock)

        let digests = [fresh, edited, added, deleted, moved, chosen].map(\.digest)
        #expect(Set(digests).count == digests.count, "Each write must change the digest")
    }
}
