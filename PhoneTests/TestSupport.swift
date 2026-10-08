//
//  TestSupport.swift
//  IntervallyPhoneTests
//

import Foundation

// The iPhone twins of the helpers in the watch suite's Fakes.swift. The two test bundles
// are separate modules, so neither can see the other's.

/// Anchors `Bundle(for:)` to the test bundle, which is the only bundle that carries
/// `Intervally.storekit`.
final class BundleToken {}

/// A tally that the `@MainActor` closures a test hands to the code under test can bump.
@MainActor
final class Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

/// A defaults suite scoped to one test.
func makeTestDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}
