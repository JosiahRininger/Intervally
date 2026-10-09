//
//  CoreForwarderTests.swift
//  IntervallyTests
//

import Testing
import Foundation
@testable import Intervally

/// The watch's old entry points hand straight to the rules now shared with the iPhone, so
/// both devices offer the same values and names.
@Suite("Watch forwarders to Core")
struct CoreForwarderTests {

    @Test("The crown's table is the shared one", arguments: [
        (IntervalWorkout.workRange, 5),
        (IntervalWorkout.restRange, 5),
        (IntervalWorkout.prepareRange, 5),
        (IntervalWorkout.roundsRange, 1),
        (5...127, 5),
    ])
    func valueTable(range: ClosedRange<Int>, step: Int) {
        #expect(ValueEditorView.values(in: range, step: step) == ValueSteps.values(in: range, step: step))
    }

    @Test("Duplicate naming is the shared rule", arguments: [
        ("Tabata", ["Tabata"]),
        ("Tabata 2", ["Tabata", "Tabata 2"]),
        ("Classic", ["Classic", "Classic 2", "Classic 3"]),
        ("5", []),
    ])
    func naming(name: String, taken: [String]) {
        #expect(PresetListView.uniqueName(after: name, among: taken) == PresetNaming.uniqueName(after: name, among: taken))
    }
}
