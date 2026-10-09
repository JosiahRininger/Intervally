//
//  PhoneLayoutTests.swift
//  IntervallyPhoneTests
//

import Foundation
import SwiftUI
import Testing
@testable import IntervallyPhone

/// The layout decisions made by text size, and the Core additions the iPhone relies on.
@Suite("iPhone layout and naming")
@MainActor
struct PhoneLayoutTests {

    @Test("Up to the largest standard size a card is one row", arguments: [
        DynamicTypeSize.xSmall, .large, .xxxLarge,
    ])
    func rowAtStandardSizes(size: DynamicTypeSize) {
        #expect(CardArrangement(typeSize: size) == .row)
    }

    /// One row cut the name to "Clas…" and broke "5:55" across two lines at the largest size.
    @Test("At every accessibility size a card stacks", arguments: [
        DynamicTypeSize.accessibility1, .accessibility3, .accessibility5,
    ])
    func stackedAtAccessibilitySizes(size: DynamicTypeSize) {
        #expect(CardArrangement(typeSize: size) == .stacked)
    }

    @Test("A new preset's name counts on from New Workout")
    func newName() {
        #expect(PresetNaming.newName(among: ["Classic"]) == "New Workout")
        #expect(PresetNaming.newName(among: ["New Workout"]) == "New Workout 2")
        #expect(PresetNaming.newName(among: ["New Workout", "New Workout 2"]) == "New Workout 3")
    }

    @Test("Adding without selecting leaves the watch's next workout alone, and syncs")
    func addWithoutSelecting() {
        let store = WorkoutStore(defaults: makeTestDefaults())
        let changes = Counter()
        store.onLocalChange = { changes.increment() }
        let selected = store.selectedID
        let added = store.add(IntervalWorkout(name: "Hills"), select: false)
        #expect(store.selectedID == selected)
        #expect(store.document.selected.value != added.id)
        #expect(store.workouts.last == added)
        #expect(changes.value == 1)
    }

    @Test("The paywall's sample ring has both bookends, the things Pro adds")
    func paywallSample() {
        #expect(PhonePaywallPage.sample.warmupSeconds > 0)
        #expect(PhonePaywallPage.sample.cooldownSeconds > 0)
    }
}
