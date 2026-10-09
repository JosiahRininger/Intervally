//
//  QAEditTests.swift
//  IntervallyPhoneTests
//

#if DEBUG
import Foundation
import Testing
@testable import IntervallyPhone

/// The `-qaEdit` launch hook the paired-simulator checks drive the iPhone with.
@Suite("QA edits")
@MainActor
struct QAEditTests {

    @Test("Each command reads, and several are separated by semicolons")
    func parses() {
        #expect(QAEdit.parse("select 2") == [.select(2)])
        #expect(QAEdit.parse("rename 0 Hill Sprints") == [.rename(0, "Hill Sprints")])
        #expect(QAEdit.parse("work 1 45; rest 1 20 ;rounds 1 12; prepare 1 5") == [
            .work(1, 45), .rest(1, 20), .rounds(1, 12), .prepare(1, 5),
        ])
        #expect(QAEdit.parse("delete 2; move 2 0; add Ladder") == [.delete(2), .move(from: 2, to: 0), .add("Ladder")])
    }

    @Test("Any unreadable command drops them all", arguments: [
        "", ";", "select", "select x", "select 1 2", "rename 0", "rename x Name",
        "work 0", "work 0 4 5", "move 1", "jump 1 2", "add", "select 1; delete",
    ])
    func rejects(_ spec: String) {
        #expect(QAEdit.parse(spec) == nil)
    }

    @Test("Edits go through the store, so they are stamped and reported like the user's own")
    func appliesThroughTheStore() throws {
        let store = WorkoutStore(defaults: makeTestDefaults())
        let reports = Counter()
        store.onLocalChange = { reports.increment() }
        let edits = try #require(QAEdit.parse("rename 0 Sprint; work 0 45; move 2 0; select 0; delete 2; add Ladder"))

        edits.forEach { $0.apply(to: store) }

        #expect(store.workouts.map(\.name) == ["EMOM", "Sprint", "Ladder"])
        #expect(store.workouts[1].workSeconds == 45)
        // Adding selects the new preset, as on the watch.
        #expect(store.selected.name == "Ladder")
        #expect(reports.value == edits.count)
    }

    @Test("An edit naming a preset that isn't there does nothing")
    func outOfRange() {
        let store = WorkoutStore(defaults: makeTestDefaults())
        let before = store.document
        for edit in [QAEdit.select(9), .rename(9, "X"), .work(-1, 30), .delete(3), .move(from: 7, to: 0)] {
            edit.apply(to: store)
        }
        #expect(store.document == before)
    }
}
#endif
