//
//  StartRequestTests.swift
//  IntervallyTests, IntervallyPhoneTests
//

import Foundation
import Testing
#if os(watchOS)
@testable import Intervally
#else
@testable import IntervallyPhone
#endif

/// Start on Watch's request: sent beside the presets, acted on once, and only while fresh.
@Suite("Start on Watch request")
@MainActor
struct StartRequestTests {
    let defaults = makeTestDefaults()
    let transport = FakeTransport()
    nonisolated static let now = Date(timeIntervalSince1970: 5_000)

    private func makeSync() -> (WatchSync, WorkoutStore) {
        let store = WorkoutStore(defaults: defaults)
        let sync = WatchSync(
            store: store, transport: transport, sleep: { _ in throw CancellationError() },
            now: { Self.now }, defaults: defaults
        )
        return (sync, store)
    }

    private func request(age: TimeInterval, id: UUID = UUID(), preset: UUID = UUID()) -> SyncWire.StartRequest {
        SyncWire.StartRequest(id: id, presetID: preset, requestedAt: Self.now.addingTimeInterval(-age))
    }

    @Test("A request is fresh for a minute, and a clock a little ahead is forgiven")
    func freshness() {
        #expect(request(age: 0).isFresh(at: Self.now))
        #expect(request(age: 59).isFresh(at: Self.now))
        #expect(!request(age: 60).isFresh(at: Self.now))
        #expect(request(age: -20).isFresh(at: Self.now))
        #expect(!request(age: -31).isFresh(at: Self.now))
    }

    @Test("The request travels in the context beside the document, and a context without one has none")
    func wireRoundTrip() throws {
        let sent = request(age: 0)
        let context = try SyncWire.context(for: .fresh, start: sent)
        #expect(SyncWire.startRequest(from: context) == sent)
        #expect(SyncWire.document(from: context) != nil)
        #expect(SyncWire.startRequest(from: try SyncWire.context(for: .fresh)) == nil)
    }

    @Test("The iPhone sends the request with its presets, so the watch has the preset it starts")
    func requestSendsDocument() throws {
        let (sync, store) = makeSync()
        let preset = store.workouts[1].id
        #expect(sync.requestStart(of: preset))
        let context = try #require(transport.sent.last)
        #expect(SyncWire.startRequest(from: context)?.presetID == preset)
        #expect(SyncWire.document(from: context) == store.document)
    }

    @Test("No request goes out while the watch app can't be reached")
    func requestNeedsReadyPeer() {
        transport.snapshot.isCounterpartInstalled = false
        let (sync, store) = makeSync()
        #expect(sync.requestStart(of: store.workouts[0].id) == false)
        #expect(transport.sent.isEmpty)
    }

    @Test("A request is acted on once, however often its context is delivered or read again")
    func actsOnce() {
        let (sync, _) = makeSync()
        var started: [UUID] = []
        sync.onStartRequest = { started.append($0) }
        let sent = request(age: 2)
        sync.receiveStart(sent)
        sync.receiveStart(sent)
        #expect(started == [sent.presetID])

        // The next tap is a new request.
        let next = request(age: 1)
        sync.receiveStart(next)
        #expect(started == [sent.presetID, next.presetID])
    }

    @Test("A request that waited too long starts nothing: the watch was off the wrist")
    func staleIgnored() {
        let (sync, _) = makeSync()
        var started = 0
        sync.onStartRequest = { _ in started += 1 }
        sync.receiveStart(request(age: 61))
        sync.receiveStart(nil)
        #expect(started == 0)
    }

    @Test("A request still waiting in the received context is acted on when the session activates")
    func readAtActivation() throws {
        let sent = request(age: 3)
        transport.receivedApplicationContext = try SyncWire.context(for: .fresh, start: sent)
        let (sync, _) = makeSync()
        var started: [UUID] = []
        sync.onStartRequest = { started.append($0) }
        sync.sessionDidActivate()
        #expect(started == [sent.presetID])
    }
}
