//
//  RemoteEditWhileEditingTests.swift
//  IntervallyTests
//

import Testing
import SwiftUI
@testable import Intervally

/// What an open crown editor does when an edit from the iPhone lands under it. Sync merges
/// whenever a context arrives, editor open or not.
@Suite("Crown editor under a remote edit")
@MainActor
struct RemoteEditWhileEditingTests {

    private func detent(of value: Int, in editor: ValueEditorView) throws -> Double {
        Double(try #require(editor.values.firstIndex(of: value)))
    }

    @Test("The crown's own turn, or a +/- tap, leaves it where it rests")
    func ownTurnLeavesCrown() throws {
        let editor = SetupField.work.editor(value: .constant(35))
        let rest = try detent(of: 35, in: editor)
        #expect(editor.crownPosition(after: 35, from: rest) == nil)
        // Mid-turn, between two detents, still on 35's.
        #expect(editor.crownPosition(after: 35, from: rest + 0.4) == nil)
    }

    /// Work at 30s, the iPhone sets 60s: the screen showed 60, and one click saved 35s over it
    /// on both devices.
    @Test("A value changed from the iPhone moves the crown to it, so the next click steps from there")
    func remoteValueMovesCrown() throws {
        let editor = SetupField.work.editor(value: .constant(60))
        let moved = try #require(editor.crownPosition(after: 60, from: try detent(of: 30, in: editor)))
        #expect(moved == (try detent(of: 60, in: editor)))
        #expect(editor.values[Int(moved) + 1] == 65)
        #expect(editor.values[Int(moved) - 1] == 55)
    }

    @Test("Bookends follow their own table: a warmup set on the iPhone moves the crown off Off")
    func bookendFollowsRemote() throws {
        let editor = SetupField.warmup.editor(value: .constant(300))
        let moved = try #require(editor.crownPosition(after: 300, from: try detent(of: 0, in: editor)))
        #expect(editor.values[Int(moved)] == 300)
    }

    @Test("A preset changed under an open field editor closes it", arguments: SetupField.allCases)
    func selectionChangeClosesFieldEditor(field: SetupField) {
        var navigation = RootNavigation(path: [.field(field)])
        navigation.selectedPresetChanged()
        #expect(navigation == RootNavigation())
    }

    @Test("The paywall, the run, a sheet and the setup screen itself stay", arguments: [
        RootNavigation(),
        RootNavigation(path: [.paywall(.bookends)]),
        RootNavigation(path: [.run]),
        RootNavigation(sheet: .presets),
        RootNavigation(sheet: .settings),
    ])
    func selectionChangeKeepsTheRest(before: RootNavigation) {
        var navigation = before
        navigation.selectedPresetChanged()
        #expect(navigation == before)
    }
}
