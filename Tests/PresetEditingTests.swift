//
//  PresetEditingTests.swift
//  IntervallyTests
//

import Testing
import Foundation
@testable import Intervally

@Suite("Crown value table")
struct CrownValueTableTests {

    @Test("Seconds coarsen at 2:00 and 10:00 and still reach both bounds")
    func secondsSchedule() {
        let table = ValueEditorView.values(in: IntervalWorkout.workRange, step: 5)
        #expect(table.first == 5)
        #expect(table.last == 3600)
        #expect(table.contains(115) && table.contains(120) && table.contains(135))
        #expect(!table.contains(125))
        #expect(table.contains(585) && table.contains(600) && table.contains(630))
        #expect(!table.contains(615))
        #expect(table == table.sorted() && Set(table).count == table.count)
        // 24 five-second steps, 32 fifteen-second steps, 100 thirty-second steps.
        #expect(table.count == 156)
    }

    @Test("A zero lower bound is kept, so rest and lead-in can be switched off")
    func zeroLowerBound() {
        #expect(ValueEditorView.values(in: IntervalWorkout.restRange, step: 5).first == 0)
        #expect(ValueEditorView.values(in: IntervalWorkout.prepareRange, step: 5).first == 0)
    }

    @Test("A stored value off the table becomes a detent of its own, so opening the editor keeps it")
    func offTableValueKept() {
        let table = ValueEditorView.values(in: IntervalWorkout.workRange, step: 5)
        #expect(!table.contains(125), "2:05, set on the iPhone's wheels, is between the crown's 2:00 and 2:15")
        let kept = ValueEditorView.table(table, keeping: 125)
        #expect(kept.count == table.count + 1)
        #expect(kept == kept.sorted())
        #expect(kept[kept.firstIndex(of: 125)! - 1] == 120 && kept[kept.firstIndex(of: 125)! + 1] == 135)
        #expect(ValueEditorView.table(table, keeping: 120) == table, "A value on the table adds nothing")
        #expect(ValueEditorView.table(table, keeping: nil) == table)
    }

    @Test("Rounds are one per detent")
    func rounds() {
        #expect(ValueEditorView.values(in: IntervalWorkout.roundsRange, step: 1) == Array(1...99))
    }

    @Test("An upper bound off the stride is still the final entry")
    func unalignedUpperBound() {
        #expect(ValueEditorView.values(in: 5...127, step: 5).last == 127)
    }

    @Test("Bookends: Off, half minutes to 5:00, then whole minutes to 30:00")
    func bookendTable() {
        let table = IntervalWorkout.bookendValues
        #expect(table.count == 36)
        #expect(table.first == 0)
        #expect(table.last == 1800)
        #expect(zip(table, table.dropFirst()).allSatisfy { $0 < $1 })
        #expect(Array(table.prefix(11)) == [0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300])
        #expect(table.contains(360) && !table.contains(330))
        // Every detent is a value the model accepts for either bookend.
        #expect(table.allSatisfy { IntervalWorkout.warmupRange.contains($0) && IntervalWorkout.cooldownRange.contains($0) })
    }
}

@Suite("Duplicate naming")
struct DuplicateNamingTests {

    @Test("A fresh name gets 2")
    func firstCopy() {
        #expect(PresetListView.uniqueName(after: "Tabata", among: ["Tabata"]) == "Tabata 2")
    }

    @Test("A numbered name counts up instead of stacking suffixes")
    func countsUp() {
        #expect(PresetListView.uniqueName(after: "Tabata 2", among: ["Tabata", "Tabata 2"]) == "Tabata 3")
    }

    @Test("Taken names are skipped")
    func skipsTaken() {
        let taken = ["Classic", "Classic 2", "Classic 3"]
        #expect(PresetListView.uniqueName(after: "Classic", among: taken) == "Classic 4")
    }

    @Test("A bare number is a stem, not a suffix")
    func bareNumber() {
        #expect(PresetListView.uniqueName(after: "5", among: []) == "5 2")
    }
}
