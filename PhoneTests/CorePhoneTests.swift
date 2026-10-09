//
//  CorePhoneTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// The model rules the iPhone shares with the watch, as compiled for iOS.
@Suite("Core on iPhone")
struct CorePhoneTests {

    @Test("Value steps coarsen exactly as the watch's crown does")
    func valueSteps() {
        let work = ValueSteps.values(in: IntervalWorkout.workRange, step: 5)
        #expect(work.count == 156)
        #expect(work.first == 5 && work.last == 3600)
        #expect(work.contains(115) && work.contains(135) && !work.contains(125))
        #expect(ValueSteps.values(in: IntervalWorkout.roundsRange, step: 1) == Array(1...99))
        #expect(ValueSteps.values(in: IntervalWorkout.restRange, step: 5).first == 0)
    }

    @Test("Duplicate names count up instead of stacking suffixes")
    func naming() {
        #expect(PresetNaming.uniqueName(after: "Tabata", among: ["Tabata"]) == "Tabata 2")
        #expect(PresetNaming.uniqueName(after: "Tabata 2", among: ["Tabata", "Tabata 2"]) == "Tabata 3")
        #expect(PresetNaming.uniqueName(after: "Classic", among: ["Classic", "Classic 2", "Classic 3"]) == "Classic 4")
    }

    @Test("The iPhone's store keeps the same sync document as the watch's, and merges into it")
    @MainActor
    func storeKeepsSyncDocument() {
        let defaults = makeTestDefaults()
        let store = WorkoutStore(defaults: defaults)
        #expect(store.document == .fresh)
        #expect(store.isSyncSuspended == false)
        #expect(defaults.data(forKey: WorkoutStore.Key.document) != nil)

        var watch = SyncDocument.fresh
        var clock = SyncClock(device: "watch")
        watch.upsert(IntervalWorkout(name: "Hills"), clock: &clock)
        let result = store.merge(watch)
        #expect(result.changed)
        #expect(result.mergedDiffersFromRemote == false)
        #expect(store.workouts.map(\.name) == ["Classic", "Tabata", "EMOM", "Hills"])
        #expect(WorkoutStore(defaults: defaults).workouts.map(\.name) == ["Classic", "Tabata", "EMOM", "Hills"])
    }
}
