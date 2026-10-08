//
//  SharedDefaultsPhoneTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// The iPhone keeps its model and Pro cache in its own defaults. An App Group container never
/// crosses devices, so it could never reach the watch, and the iPhone app has no extension
/// to share one with.
@Suite("Shared defaults on iPhone")
struct SharedDefaultsPhoneTests {

    @Test("The suite is the app's standard defaults, and nothing shares it")
    func standardOnly() {
        #expect(SharedDefaults.suite === UserDefaults.standard)
        #expect(SharedDefaults.isSharing == false)
    }

    @Test("The preset store and the Pro cache use it by default")
    @MainActor
    func storesUseIt() {
        // The host app's own store seeded its presets there at launch.
        #expect(UserDefaults.standard.data(forKey: WorkoutStore.Key.workouts) != nil)
        #expect(WorkoutStore().workouts == WorkoutStore(defaults: .standard).workouts)

        let key = ProStore.Key.cachedIsPro
        let before = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }

        UserDefaults.standard.set(true, forKey: key)
        #expect(ProStore().isPro)
        UserDefaults.standard.set(false, forKey: key)
        #expect(ProStore().isPro == false)
    }
}
