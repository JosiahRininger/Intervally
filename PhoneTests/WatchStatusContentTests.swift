//
//  WatchStatusContentTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// What the watch status card says for each state the watch can be in.
@Suite("Watch status")
struct WatchStatusContentTests {
    let earlier = Date(timeIntervalSince1970: 1_000)
    let later = Date(timeIntervalSince1970: 2_000)

    @Test("Every state has its own words, and none is a dead end", arguments: [
        PeerState.unsupported, .activating, .notPaired, .appNotInstalled, .ready,
    ])
    func everyState(_ peer: PeerState) {
        let content = WatchStatusContent(peer: peer, lastSentAt: nil, lastReceivedAt: nil)
        #expect(!content.title.isEmpty)
        #expect(!content.detail.isEmpty)
        #expect(content.syncedLine() == nil)
    }

    @Test("No watch here, or none paired: building workouts still works")
    func noWatch() {
        #expect(WatchStatusContent(peer: .unsupported, lastSentAt: nil, lastReceivedAt: nil).detail == "You can still build workouts here.")
        #expect(WatchStatusContent(peer: .notPaired, lastSentAt: nil, lastReceivedAt: nil).detail == "Your workouts will be waiting.")
    }

    @Test("Not installed: the steps to install it from the Watch app")
    func notInstalled() {
        let content = WatchStatusContent(peer: .appNotInstalled, lastSentAt: nil, lastReceivedAt: nil)
        #expect(content.detail.contains("Watch app"))
        #expect(content.detail.contains("Available Apps"))
        #expect(content.detail.contains("Install"))
    }

    @Test("Ready but never heard from: open the watch app to bring its presets over")
    func readyBeforeFirstContext() {
        let content = WatchStatusContent(peer: .ready, lastSentAt: earlier, lastReceivedAt: nil)
        #expect(content.title == "You're set")
        #expect(content.detail == "Open Intervally on your watch to bring your presets over.")
        #expect(content.lastSynced == earlier)
    }

    @Test("Ready and synced: the later of the last send and the last receipt")
    func readyAndSynced() {
        let content = WatchStatusContent(peer: .ready, lastSentAt: earlier, lastReceivedAt: later)
        #expect(content.detail == "Workouts you change here show up on your watch.")
        #expect(content.lastSynced == later)
        #expect(content.syncedLine(now: later.addingTimeInterval(30)) == "Synced just now")
        let line = content.syncedLine(now: later.addingTimeInterval(300))
        #expect(line?.hasPrefix("Last synced ") == true)
        #expect(line?.contains("5") == true)
    }

    @Test("A sync time is only shown while the watch is ready")
    func syncTimeOnlyWhenReady() {
        let content = WatchStatusContent(peer: .appNotInstalled, lastSentAt: earlier, lastReceivedAt: later)
        #expect(content.lastSynced == nil)
        #expect(content.syncedLine() == nil)
    }
}
