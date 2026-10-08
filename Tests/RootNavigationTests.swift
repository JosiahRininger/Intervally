//
//  RootNavigationTests.swift
//  IntervallyTests
//

import Testing
import SwiftUI
@testable import Intervally

/// The root stack and the setup sheet, which a start from outside the app has to clear.
@Suite("Root navigation")
struct RootNavigationTests {

    /// Everything that can be up over the setup screen when the complication, Siri or
    /// Control Center asks for a start.
    static let leftOpen: [RootNavigation] = [
        RootNavigation(),
        RootNavigation(sheet: .settings),
        RootNavigation(sheet: .presets),
        RootNavigation(path: [.paywall(.bookends)]),
        RootNavigation(path: [.field(.warmup)]),
        RootNavigation(path: [.field(.work)], sheet: .settings),
    ]

    @Test("A start replaces whatever was open, the paywall included, with the run", arguments: leftOpen)
    func startClearsEverything(before: RootNavigation) {
        var navigation = before
        navigation.setRunning(true)
        #expect(navigation == RootNavigation(path: [.run], sheet: nil))
        #expect(navigation.isRunning)
    }

    @Test("Done returns to the setup screen itself, not to a screen left open before")
    func endingReturnsToSetup() {
        var navigation = RootNavigation(path: [.paywall(.bookends)], sheet: .settings)
        navigation.setRunning(true)
        navigation.setRunning(false)
        #expect(navigation == RootNavigation())
        #expect(navigation.isRunning == false)
    }

    @Test("A second start while running changes nothing")
    func startWhileRunning() {
        var navigation = RootNavigation()
        navigation.setRunning(true)
        let running = navigation
        navigation.setRunning(true)
        #expect(navigation == running)
    }

    @Test("Running is read from the stack, so the system's back gesture leaves the run too")
    func runningFollowsTheStack() {
        var navigation = RootNavigation()
        navigation.setRunning(true)
        navigation.path.removeLast()
        #expect(navigation.isRunning == false)
    }

    @Test("Ending a run that isn't showing leaves an open screen where it is")
    func endingWithoutARun() {
        var navigation = RootNavigation(path: [.field(.rest)])
        navigation.setRunning(false)
        #expect(navigation.path == [.field(.rest)])
    }
}

/// The numbers the setup pages edit, and the editors their tiles open.
@Suite("Setup fields")
@MainActor
struct SetupFieldTests {

    @Test("Each field edits its own number of the preset")
    func keyPaths() {
        let expected: [SetupField: WritableKeyPath<IntervalWorkout, Int>] = [
            .work: \.workSeconds,
            .rest: \.restSeconds,
            .rounds: \.rounds,
            .prepare: \.prepareSeconds,
            .warmup: \.warmupSeconds,
            .cooldown: \.cooldownSeconds,
        ]
        for field in SetupField.allCases {
            #expect(field.keyPath == expected[field], "\(field)")
        }
    }

    @Test("Only the warmup and cooldown are Pro")
    func onlyBookendsArePro() {
        #expect(SetupField.allCases.filter(\.isPro) == [.warmup, .cooldown])
    }

    @Test("Tiles keep their titles and colours, and rounds stays white")
    func tiles() {
        #expect(SetupField.allCases.map(\.title) == ["Work", "Rest", "Rounds", "Get Ready", "Warmup", "Cooldown"])
        #expect(SetupField.prepare.kind?.shortTitle == "Ready")
        #expect(SetupField.rounds.kind == nil)
        #expect(SetupField.rounds.tint == .white)
        #expect(SetupField.rounds.symbolName == "repeat")
        #expect(SetupField.work.tint == Theme.light(for: .work))
        #expect(SetupField.cooldown.symbolName == IntervalPhase.Kind.cooldown.symbolName)
    }

    @Test("A tile shows its value the way the rest of the app does")
    func tileText() {
        #expect(SetupField.work.tileText(90) == DurationFormat.clock(90))
        #expect(SetupField.rounds.tileText(8) == "8")
        #expect(SetupField.warmup.tileText(300) == DurationFormat.bookend(300))
        #expect(SetupField.cooldown.tileText(0) == DurationFormat.bookend(0))
        #expect(SetupField.rounds.spoken(8) == DurationFormat.rounds(8))
        #expect(SetupField.rest.spoken(15) == DurationFormat.spoken(15))
        #expect(SetupField.warmup.spoken(0) == DurationFormat.bookendSpoken(0))
    }

    @Test("Durations and rounds keep the editor's own schedule", arguments: [SetupField.work, .rest, .prepare])
    func durationEditors(field: SetupField) {
        let editor = field.editor(value: .constant(45))
        #expect(editor.values == ValueEditorView.values(in: field.range, step: 5))
        #expect(editor.unitLabel == "seconds")
    }

    @Test("Rounds count one per detent")
    func roundsEditor() {
        let editor = SetupField.rounds.editor(value: .constant(1))
        #expect(editor.values == Array(IntervalWorkout.roundsRange))
        #expect(editor.unitLabel == "round")
    }

    @Test("The bookends turn over their own table, with nothing under Off", arguments: [SetupField.warmup, .cooldown])
    func bookendEditors(field: SetupField) {
        #expect(field.editor(value: .constant(0)).values == IntervalWorkout.bookendValues)
        #expect(field.editor(value: .constant(0)).unitLabel == "")
        #expect(field.editor(value: .constant(30)).unitLabel == "seconds")
        #expect(field.editor(value: .constant(300)).unitLabel == "minutes")
    }
}
