//
//  WatchStatusContentTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
import UIKit
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

    @Test("No watch here, or none paired: workouts run on the iPhone")
    func noWatch() {
        #expect(WatchStatusContent(peer: .unsupported, lastSentAt: nil, lastReceivedAt: nil).detail == "Your workouts run right here.")
        #expect(WatchStatusContent(peer: .notPaired, lastSentAt: nil, lastReceivedAt: nil).detail == "Your workouts run right here, and they'll be waiting for a watch.")
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

    // MARK: Suspended

    @Test("Suspended sync says workouts aren't syncing, where the watch is ready or being looked for", arguments: [
        PeerState.ready, .activating,
    ])
    func suspendedShowsNotSyncing(_ peer: PeerState) {
        let content = WatchStatusContent(peer: peer, lastSentAt: earlier, lastReceivedAt: later, syncSuspended: true)
        #expect(content.title == "Workouts aren't syncing")
        #expect(content.detail == "Your workouts are saved on this iPhone, but they can't be sent to your watch right now.")
        #expect(UIImage(systemName: content.systemImage) != nil, "\(content.systemImage)")
        #expect(content.title != WatchStatusContent(peer: peer, lastSentAt: earlier, lastReceivedAt: later).title)
    }

    @Test("Suspended sync offers no Send Now and shows no last sync, which would read as sync working")
    func suspendedHidesSendNow() {
        let content = WatchStatusContent(peer: .ready, lastSentAt: earlier, lastReceivedAt: later, syncSuspended: true)
        #expect(content.offersSendNow == false)
        #expect(content.lastSynced == nil)
        #expect(content.syncedLine(now: later) == nil)
        // Not suspended, the same watch offers both.
        let syncing = WatchStatusContent(peer: .ready, lastSentAt: earlier, lastReceivedAt: later, syncSuspended: false)
        #expect(syncing.offersSendNow)
        #expect(syncing.lastSynced == later)
    }

    @Test("Without a watch to sync with, suspended sync changes nothing: the watch needs seeing to first", arguments: [
        PeerState.unsupported, .notPaired, .appNotInstalled,
    ])
    func suspendedLeavesOtherStates(_ peer: PeerState) {
        let suspended = WatchStatusContent(peer: peer, lastSentAt: earlier, lastReceivedAt: later, syncSuspended: true)
        #expect(suspended == WatchStatusContent(peer: peer, lastSentAt: earlier, lastReceivedAt: later))
    }

    @Test("The card reads the store's suspension through sync, the way every screen builds it")
    @MainActor
    func suspensionReachesTheCard() {
        let defaults = makeTestDefaults()
        let transport = FakeTransport()
        let readable = WatchSync(store: WorkoutStore(defaults: defaults), transport: transport)
        #expect(readable.isSuspended == false)
        #expect(WatchStatusContent(sync: readable).title == "You're set")
        #expect(WatchStatusContent(sync: readable).offersSendNow)

        defaults.set(Data("not a document".utf8), forKey: WorkoutStore.Key.document)
        let sync = WatchSync(store: WorkoutStore(defaults: defaults), transport: transport)
        #expect(sync.isSuspended)
        #expect(sync.peer == .ready)
        let content = WatchStatusContent(sync: sync)
        #expect(content.title == "Workouts aren't syncing")
        #expect(content.offersSendNow == false)
        #expect(content.lastSynced == nil)
    }
}
