//
//  PhoneQATests.swift
//  IntervallyPhoneTests
//

#if DEBUG
import Foundation
import Testing
@testable import IntervallyPhone

/// The iPhone's QA launch flags: read exactly, and a stand-in watch that never sends.
@Suite("iPhone QA flags")
@MainActor
struct PhoneQATests {

    @Test("Each flag is read from its value")
    func parse() {
        let options = PhoneQAOptions.parse([
            "IntervallyPhone", "-qaPro", "pro", "-qaWatch", "notInstalled", "-qaOpen", "editor", "-qaWelcome", "YES",
        ])
        #expect(options == PhoneQAOptions(pro: true, watch: .notInstalled, welcome: true, screen: .editor))
    }

    @Test("A run in progress, for screenshots: seconds since it started, never negative")
    func runElapsed() {
        #expect(PhoneQAOptions.parse(["-qaRunElapsed", "95"]).runElapsed == 95)
        #expect(PhoneQAOptions.parse(["-qaRunElapsed", "-5"]).runElapsed == nil, "Reads as a flag")
        #expect(PhoneQAOptions.parse(["-qaRunElapsed", "soon"]).runElapsed == nil)
        #expect(PhoneQAOptions.parse(["-qaWatchRun", "paused"]).watchRun == .paused)
        #expect(PhoneQAOptions.parse(["-qaWatchRun", "stopped"]).watchRun == nil, "Nothing to show")
        #expect(PhoneQAOptions.parse(["-qaWatchRun", "paused"]).isActive)
    }

    @Test("No flags, no overrides")
    func none() {
        #expect(PhoneQAOptions.parse(["IntervallyPhone"]) == PhoneQAOptions())
    }

    @Test("A typo is ignored rather than guessed at")
    func typos() {
        let options = PhoneQAOptions.parse(["-qaPro", "Pr0", "-qaWatch", "paired", "-qaOpen", "everything"])
        #expect(options == PhoneQAOptions())
        #expect(PhoneQAOptions.proOverride(" FREE ") == false)
        #expect(PhoneQAOptions.proOverride("pro") == true)
    }

    @Test("A flag with no value takes none, and never the next flag's")
    func missingValues() {
        #expect(PhoneQAOptions.parse(["-qaPro", "-qaWatch", "unpaired"]) == PhoneQAOptions(watch: .unpaired))
        #expect(PhoneQAOptions.parse(["-qaWelcome"]).welcome)
        #expect(PhoneQAOptions.parse(["-qaWelcome", "-qaPro", "free"]) == PhoneQAOptions(pro: false, welcome: true))
        #expect(PhoneQAOptions.parse(["-qaWelcome", "NO"]).welcome == false)
    }

    @Test("Each stand-in watch reports its state", arguments: [
        (QAWatchState.unsupported, PeerState.unsupported),
        (.unpaired, .notPaired),
        (.notInstalled, .appNotInstalled),
        (.installed, .ready),
        (.firstSync, .ready),
    ])
    func states(state: QAWatchState, peer: PeerState) {
        #expect(PeerState(state.snapshot) == peer)
    }

    @Test("A set-up stand-in has synced, so Last Synced has something to say")
    func installedHasSynced() {
        let store = WorkoutStore(defaults: makeTestDefaults())
        let sync = WatchSync(store: store, transport: QAWatchTransport(state: .installed, store: store))
        sync.activate()
        #expect(sync.lastReceivedAt.map { Date().timeIntervalSince($0) > 200 } == true)
        #expect(sync.lastSentAt == nil, "The stand-in already holds this iPhone's presets")
        #expect(WorkoutsContent.showsWatchHint(peer: sync.peer, lastReceivedAt: sync.lastReceivedAt) == false)
    }

    @Test("A first-sync stand-in has heard nothing yet: the hint shows")
    func firstSyncShowsTheHint() {
        let store = WorkoutStore(defaults: makeTestDefaults())
        let transport = QAWatchTransport(state: .firstSync, store: store)
        let sync = WatchSync(store: store, transport: transport)
        sync.activate()
        #expect(sync.lastReceivedAt == nil)
        #expect(WorkoutsContent.showsWatchHint(peer: sync.peer, lastReceivedAt: sync.lastReceivedAt))
        // What was "sent" stayed in the stand-in.
        #expect(SyncWire.document(from: transport.applicationContext) == store.document)
    }

    @Test("Without a watch the stand-in isn't even activated")
    func unsupportedNeverActivates() {
        let store = WorkoutStore(defaults: makeTestDefaults())
        let sync = WatchSync(store: store, transport: QAWatchTransport(state: .unsupported, store: store))
        sync.activate()
        #expect(sync.isActive == false)
        #expect(sync.peer == .unsupported)
    }

    @Test("QA edits reach the warmup and cooldown, for the Pro screenshots")
    func bookendEdits() throws {
        let edits = try #require(QAEdit.parse("warmup 0 300; cooldown 0 120"))
        #expect(edits == [.warmup(0, 300), .cooldown(0, 120)])
        let store = WorkoutStore(defaults: makeTestDefaults())
        edits.forEach { $0.apply(to: store) }
        #expect(store.workouts[0].warmupSeconds == 300)
        #expect(store.workouts[0].cooldownSeconds == 120)
    }

    @Test("Every screen -qaOpen names can be parsed back")
    func screens() {
        for screen in QAScreen.allCases {
            #expect(PhoneQAOptions.parse(["-qaOpen", screen.rawValue]).screen == screen)
        }
    }
}
#endif
