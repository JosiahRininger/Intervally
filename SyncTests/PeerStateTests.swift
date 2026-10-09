//
//  PeerStateTests.swift
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

/// How what WatchConnectivity reports becomes the state sync and the status screen go by.
@Suite("Peer state")
struct PeerStateTests {

    private static func snapshot(
        supported: Bool = true,
        state: WCSessionActivationState = .activated,
        paired: Bool = true,
        installed: Bool = true
    ) -> PeerSnapshot {
        PeerSnapshot(
            isSupported: supported,
            activationState: state,
            isPaired: paired,
            isCounterpartInstalled: installed,
            hasContentPending: false
        )
    }

    @Test("Each question is asked in order: supported, activated, paired, installed")
    func mapping() {
        #expect(PeerState(Self.snapshot(supported: false)) == .unsupported)
        #expect(PeerState(.unsupported) == .unsupported)
        #expect(PeerState(Self.snapshot(state: .notActivated)) == .activating)
        #expect(PeerState(Self.snapshot(state: .inactive)) == .activating)
        #expect(PeerState(Self.snapshot(paired: false, installed: false)) == .notPaired)
        #expect(PeerState(Self.snapshot(installed: false)) == .appNotInstalled)
        #expect(PeerState(Self.snapshot()) == .ready)
    }

    @Test("Without support nothing else counts; before activation pairing doesn't either")
    func earlierQuestionsWin() {
        #expect(PeerState(Self.snapshot(supported: false, state: .activated, paired: true, installed: true)) == .unsupported)
        #expect(PeerState(Self.snapshot(state: .notActivated, paired: false, installed: false)) == .activating)
        #expect(PeerState(Self.snapshot(paired: false, installed: true)) == .notPaired)
    }

    @Test("A session that hasn't activated reads as neither paired nor installed")
    func unactivatedSession() {
        // Nothing in either test host ever activates the default session.
        let snapshot = PeerSnapshot(WCSession.default)
        #expect(snapshot.isSupported)
        #expect(snapshot.activationState == .notActivated)
        #expect(snapshot.isCounterpartInstalled == false)
        #if os(iOS)
        #expect(snapshot.isPaired == false)
        #else
        #expect(snapshot.isPaired)
        #endif
        #expect(PeerState(snapshot) == .activating)
    }

    @Test("In the unit-test host the real transport has no session, so it can't reach the paired device")
    @MainActor
    func realTransportStaysOffInTheHost() {
        #expect(UnitTestHost.isActive)
        #expect(WCSessionTransport.defaultSession == nil)
        let transport = WCSessionTransport()
        #expect(transport.snapshot == .unsupported)
        #expect(transport.applicationContext.isEmpty)

        let sync = WatchSync(store: WorkoutStore(defaults: makeTestDefaults()), transport: transport)
        sync.activate()
        #expect(sync.isActive == false)
        #expect(sync.peer == .unsupported)
        #expect(WCSession.default.activationState == .notActivated)
    }

    @Test("The real transport, given a session, reads it")
    @MainActor
    func realTransportReadsItsSession() {
        let transport = WCSessionTransport(session: .default)
        #expect(transport.snapshot.isSupported)
        #expect(transport.snapshot.activationState == .notActivated)
    }
}
