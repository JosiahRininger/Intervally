//
//  DelegateQueueTests.swift
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

/// WatchConnectivity calls its delegate on a background serial queue, never the main thread.
/// Each delegate method must take that call and hop to the main actor itself. An isolated or
/// `@preconcurrency` conformance still compiles, but traps on such a call, which fails the run.
@Suite("Delegate queue")
@MainActor
struct DelegateQueueTests {
    let transport = FakeTransport()

    private func makeSync() -> (WatchSync, WorkoutStore) {
        let store = WorkoutStore(defaults: makeTestDefaults())
        return (WatchSync(store: store, transport: transport, sleep: { _ in throw CancellationError() }), store)
    }

    /// Calls `body` with the sync seen only as a `WCSessionDelegate`, from a background serial
    /// queue as WatchConnectivity does, then waits for the hop it made to the main actor.
    /// False if `body` somehow ran on the main thread.
    private func callFromDelegateQueue(
        _ sync: WatchSync,
        _ body: @escaping @Sendable (any WCSessionDelegate, WCSession) -> Void
    ) async -> Bool {
        nonisolated(unsafe) let delegate: any WCSessionDelegate = sync
        let offMain = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            DispatchQueue(label: "com.josiahrininger.intervally.tests.wc-delegate").async {
                let offMain = !Thread.isMainThread
                body(delegate, WCSession.default)
                done.resume(returning: offMain)
            }
        }
        let landed = await waitUntil { sync.activity.deliveriesInFlight == 0 }
        return offMain && landed
    }

    @Test("Activation completing merges the waiting context and sends what the other device lacks")
    func activationDidComplete() async {
        let (sync, store) = makeSync()
        var mine = store.workouts[1]
        mine.name = "Mine"
        store.update(mine)
        var peer = PeerDevice()
        peer.rename(0, to: "Remote")
        transport.receivedApplicationContext = peer.context

        #expect(await callFromDelegateQueue(sync) { delegate, session in
            delegate.session(session, activationDidCompleteWith: .activated, error: nil)
        })
        #expect(store.workouts.map(\.name) == ["Remote", "Mine", "EMOM"])
        #expect(transport.sentDocuments == [store.document])
    }

    @Test("A received context is decoded on the delegate queue and merged on the main actor")
    func didReceiveApplicationContext() async {
        let (sync, store) = makeSync()
        var peer = PeerDevice()
        peer.rename(2, to: "Hills")
        let sent = peer

        #expect(await callFromDelegateQueue(sync) { delegate, session in
            delegate.session?(session, didReceiveApplicationContext: sent.context)
        })
        #expect(store.workouts[2].name == "Hills")
        #expect(sync.lastReceivedAt != nil)
    }

    @Test("A garbage context is dropped on the delegate queue")
    func garbageContext() async {
        let (sync, store) = makeSync()
        let before = store.document

        #expect(await callFromDelegateQueue(sync) { delegate, session in
            delegate.session?(session, didReceiveApplicationContext: ["doc": Data([0xDE, 0xAD])])
        })
        #expect(store.document == before)
        #expect(transport.sent.isEmpty)
    }

    #if os(iOS)
    @Test("The watch being paired, unpaired or getting the app forces a send")
    func watchStateDidChange() async {
        let (sync, store) = makeSync()
        sync.push()

        #expect(await callFromDelegateQueue(sync) { delegate, session in
            delegate.sessionWatchStateDidChange?(session)
        })
        #expect(transport.sentDocuments == [store.document, store.document])
    }

    @Test("Becoming inactive while switching watches is reflected in the peer")
    func didBecomeInactive() async {
        let (sync, _) = makeSync()
        transport.snapshot.activationState = .inactive

        #expect(await callFromDelegateQueue(sync) { delegate, session in
            delegate.sessionDidBecomeInactive(session)
        })
        #expect(sync.peer == .activating)
    }

    @Test("Deactivating, after a switch to another watch, activates again")
    func didDeactivate() async {
        let (sync, _) = makeSync()

        #expect(await callFromDelegateQueue(sync) { delegate, session in
            delegate.sessionDidDeactivate(session)
        })
        #expect(transport.activations == 1)
    }
    #else
    @Test("The iPhone app being installed or removed forces a send")
    func companionAppInstalledDidChange() async {
        let (sync, store) = makeSync()
        sync.push()

        #expect(await callFromDelegateQueue(sync) { delegate, session in
            delegate.sessionCompanionAppInstalledDidChange?(session)
        })
        #expect(transport.sentDocuments == [store.document, store.document])
    }
    #endif
}
