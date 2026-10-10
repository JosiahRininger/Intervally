//
//  PhoneMetadataTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// The iPhone's half of `AppStore/Metadata.md`, held to the iPhone app's own words: notes
/// that send a reviewer to a button that was renamed are a rejection (Guideline 2.1(b)).
/// The watch's half, and Apple's field limits, are MetadataTests in the watch bundle.
@Suite("App Store metadata, iPhone")
@MainActor
struct PhoneMetadataTests {

    @Test("The reviewer notes walk the iPhone's real screens")
    func versionNotes() throws {
        let notes = try Self.block("### Notes for the reviewer (4000)")
        let tiles = [PresetField.work, .rest, .rounds, .prepare].map(\.title).joined(separator: ", ")
        #expect(notes.contains("each tile (\(tiles)) opens a picker"))
        #expect(notes.contains("\(WorkoutsContent.putOnWatchTitle) makes it the workout the watch starts next"))
        #expect(notes.contains("Tap \(HistoryMessage.connectTitle)."))
        let store = PhoneSettingsView.StoreAction.self
        #expect(notes.contains(
            "Settings (the gear at top left) has \(ProStatusRow.title), \(ThemeRow.title), \(SoundsRow.title), Apple Watch, "
                + "Apple Health, \(store.restore.title), \(store.redeem.title), Support and the Privacy Policy."
        ))
    }

    @Test("The notes run a workout on iPhone with the app's own controls")
    func runNotes() throws {
        let notes = try Self.block("### Notes for the reviewer (4000)")
        #expect(notes.contains("Tap \(WorkoutsContent.startTitle) on the workout up next, or the play button on any workout"))
        #expect(notes.contains("Settings > \(SoundsRow.title) turns the beeps, the 3-2-1 countdown and Keep Screen On"))
        #expect(notes.contains("Its Voice Coach, which calls out each interval as it starts, is part of Intervally Pro."))
        // The bundle's background modes are exactly what the notes explain.
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] == ["audio"])
        #expect(notes.contains("- audio: each interval change is a tone, or the voice coach's words"))
    }

    @Test("Every iPhone way into the purchase is named in the app's own words")
    func purchaseNotes() throws {
        let notes = try Self.block("### Review notes (4000)")
        let store = PhoneSettingsView.StoreAction.self
        #expect(notes.contains("Tap Settings (the gear at top left), then \(ProStatusRow.title) (the first row)."))
        #expect(notes.contains("Tap Settings, then \(ThemeRow.title), then \(AppTheme.pastel.title), marked PRO."))
        #expect(notes.contains("then its \(PresetField.warmup.title) or \(PresetField.cooldown.title) tile, marked PRO."))
        #expect(notes.contains(
            "Settings also has \(store.restore.title) and \(store.redeem.title), and \(store.refund.title) once Pro is bought."
        ))
        // "marked PRO": a free user's bookend tiles are locked.
        let workout = WorkoutStore.starterWorkouts[0]
        #expect(EditorTileContent(field: .warmup, workout: workout, isPro: false).isLocked)
        #expect(EditorTileContent(field: .cooldown, workout: workout, isPro: false).isLocked)
    }

    @Test("+ on a fresh install opens Intervally Pro, as both sets of notes say")
    func plusAtTheFreeLimit() throws {
        #expect(WorkoutStore.starterWorkouts.count == ProProduct.freePresetLimit)
        let actions = PresetActions(store: WorkoutStore(defaults: makeTestDefaults()), pro: FakePro())
        #expect(actions.addNew() == .paywall)
        #expect(try Self.block("### Notes for the reviewer (4000)").contains("tap + (top right of Workouts)"))
        #expect(try Self.block("### Review notes (4000)").contains("On Workouts, tap + (top right)."))
    }

    @Test("Restore is on the iPhone's Intervally Pro screen too, as the notes say")
    func restoreOnTheIPhonePaywall() throws {
        let free = PaywallContent.make(
            context: .settings, isPro: false, ownership: .none, canMakePayments: true,
            offer: .idle, isPurchasing: false, lastPurchase: nil, lastRestore: nil, platform: .phone
        )
        #expect(free.offersRestore)
        #expect(try Self.block("### Review notes (4000)").contains(
            "\(PaywallContent.restoreTitle) is at the bottom of the \(PaywallContent.title) screen on both devices."
        ))
    }

    @Test("The description names the iPhone's control by its title")
    func descriptionNamesPutOnWatch() throws {
        let description = try Self.block("## Description (4000)")
        #expect(description.contains("Tap \(WorkoutsContent.putOnWatchTitle) and"))
        #expect(description.contains("tap \(WorkoutsContent.startOnWatchTitle) to run one on your wrist"))
    }

    // MARK: - Helpers

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Read from the source tree, which the simulator shares with the Mac.
    static func listing() throws -> String {
        try String(contentsOf: root.appendingPathComponent("AppStore/Metadata.md"), encoding: .utf8)
    }

    /// The one fenced block under `heading`.
    static func block(_ heading: String) throws -> String {
        let matches = Listing.fields(in: try listing()).filter { $0.isBlock && $0.label == heading }
        #expect(matches.count == 1, "\(matches.count) blocks under \(heading)")
        return try #require(matches.first).text
    }
}
