//
//  WatchStatusViewModelTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// The Watch Status screen: the install steps, Send to Watch Now, and which states count as
/// having a watch at all.
@Suite("Watch Status screen")
@MainActor
struct WatchStatusViewModelTests {

    @Test("Install steps only while the watch is paired without the app", arguments: [
        PeerState.unsupported, .activating, .notPaired, .appNotInstalled, .ready,
    ])
    func installSteps(peer: PeerState) {
        let content = WatchStatusContent(peer: peer, lastSentAt: nil, lastReceivedAt: nil)
        #expect(content.installSteps.isEmpty == (peer != .appNotInstalled))
    }

    @Test("The steps follow the Watch app's own path to Install")
    func stepsInOrder() {
        let steps = WatchStatusContent(peer: .appNotInstalled, lastSentAt: nil, lastReceivedAt: nil).installSteps
        #expect(steps.count == 3)
        #expect(steps[0].contains("Watch app"))
        #expect(steps[1].contains("My Watch") && steps[1].contains("Available Apps"))
        #expect(steps[2].contains("Install") && steps[2].contains("Intervally"))
    }

    @Test("Send to Watch Now only with a watch app to send to", arguments: [
        PeerState.unsupported, .activating, .notPaired, .appNotInstalled, .ready,
    ])
    func sendNowOnlyWhenReady(peer: PeerState) {
        #expect(WatchStatusContent(peer: peer, lastSentAt: nil, lastReceivedAt: nil).offersSendNow == (peer == .ready))
    }

    @Test("Without a watch, only the watch words go", arguments: [
        (PeerState.unsupported, false), (.notPaired, false),
        (.activating, true), (.appNotInstalled, true), (.ready, true),
    ])
    func hasWatch(peer: PeerState, expected: Bool) {
        #expect(peer.hasWatch == expected)
    }

    @Test("Send to Watch Now sends even what the watch already has, and updates Last Synced")
    func sendNowForces() throws {
        let transport = FakeTransport()
        let store = WorkoutStore(defaults: makeTestDefaults())
        var now = Date(timeIntervalSince1970: 10_000)
        let sync = WatchSync(store: store, transport: transport, now: { now })
        sync.push()
        try #require(transport.sent.count == 1)

        sync.push()
        #expect(transport.sent.count == 1, "An ordinary push skips what the watch holds")

        now = now.addingTimeInterval(120)
        sync.push(force: true)
        #expect(transport.sent.count == 2)
        let content = WatchStatusContent(peer: sync.peer, lastSentAt: sync.lastSentAt, lastReceivedAt: sync.lastReceivedAt)
        #expect(content.lastSynced == now)
        #expect(content.syncedLine(now: now) == "Synced just now")
    }
}
