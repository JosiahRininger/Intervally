//
//  ProGatingTests.swift
//  IntervallyTests
//

import Testing
import Foundation
@testable import Intervally

/// What a free user can and can't do, decided through `ProGating` alone.
@Suite("Pro gating")
@MainActor
struct ProGatingTests {

    @Test("Free users can add presets only below three", arguments: zip(
        0...5, [true, true, true, false, false, false]
    ))
    func freePresetLimit(count: Int, canAdd: Bool) {
        #expect(FakePro(isPro: false).canAddPreset(currentCount: count) == canAdd)
    }

    @Test("Pro users can always add a preset", arguments: 0...5)
    func proHasNoLimit(count: Int) {
        #expect(FakePro(isPro: true).canAddPreset(currentCount: count))
    }

    @Test("The three starters fill the free tier, so a fresh install's first New Preset is gated")
    func startersFillTheFreeTier() {
        let store = WorkoutStore(defaults: makeTestDefaults())
        #expect(store.workouts.count == ProProduct.freePresetLimit)
        #expect(FakePro().canAddPreset(currentCount: store.workouts.count) == false)
    }

    @Test("A device holding more than three presets keeps them all, and stays gated until it is back under")
    func overLimitKeepsEveryPreset() throws {
        let defaults = makeTestDefaults()
        let before = WorkoutStore(defaults: defaults)
        before.add(IntervalWorkout(name: "Hills"))
        before.add(IntervalWorkout(name: "Sprints"))

        // A relaunch after a refund: nothing is trimmed.
        let store = WorkoutStore(defaults: defaults)
        #expect(store.workouts.map(\.name) == ["Classic", "Tabata", "EMOM", "Hills", "Sprints"])

        let free = FakePro()
        var gated: [Bool] = []
        while store.workouts.count > 2 {
            gated.append(!free.canAddPreset(currentCount: store.workouts.count))
            store.delete(try #require(store.workouts.last))
        }
        #expect(gated == [true, true, true], "Gated at 5, 4 and 3")
        #expect(free.canAddPreset(currentCount: store.workouts.count), "Open again at 2")
    }

    @Test("Gating follows the entitlement as it changes")
    func followsEntitlement() {
        let pro = FakePro(isPro: true)
        #expect(pro.canAddPreset(currentCount: 7))
        pro.isPro = false
        #expect(pro.canAddPreset(currentCount: 7) == false)
    }

    @Test("Without Pro every boundary taps once, and the saved strength is kept for later")
    func tapStrengthWithoutPro() {
        let defaults = makeTestDefaults()
        defaults.set(TapStrength.strongest.rawValue, forKey: SettingsKey.tapStrength)
        let stored = TapStrength.stored(in: defaults)

        #expect(TapStrength.effective(stored: stored, isPro: false) == .standard)
        #expect(defaults.string(forKey: SettingsKey.tapStrength) == "strongest")
        for strength in TapStrength.allCases {
            #expect(TapStrength.effective(stored: strength, isPro: true) == strength)
        }
    }

    @Test("A missing or unreadable saved strength reads as Standard", arguments: [nil, "", "Strongest", "prominent"])
    func unreadableTapStrength(raw: String?) {
        let defaults = makeTestDefaults()
        if let raw { defaults.set(raw, forKey: SettingsKey.tapStrength) }
        #expect(TapStrength.stored(in: defaults) == .standard)
    }
}

#if DEBUG
/// The real `ProStore` must stay off in the test host, or it would finish the StoreKit
/// suite's transactions and rewrite the cached flag while other suites run.
@Suite("Unit-test host")
@MainActor
struct UnitTestHostTests {

    @Test("Either variable marks the unit-test host; a normal launch has neither")
    func detection() {
        #expect(AppDelegate.isUnitTestHost([:]) == false)
        #expect(AppDelegate.isUnitTestHost(["INTERVALLY_UNIT_TESTS": "1"]))
        #expect(AppDelegate.isUnitTestHost(["XCTestConfigurationFilePath": "/tmp/Intervally.xctestconfiguration"]))
    }

    @Test("This process is the host, and the app's own ProStore never started")
    func appStoreStaysOff() throws {
        #expect(AppDelegate.isUnitTestHost())
        let delegate = try #require(AppDelegate.current, "The host app's delegate is reachable for manual QA")
        #expect(delegate.pro.isListening == false)
    }
}
#endif
