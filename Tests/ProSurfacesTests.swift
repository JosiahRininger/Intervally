//
//  ProSurfacesTests.swift
//  IntervallyTests
//

import Testing
import SwiftUI
@testable import Intervally

/// The Settings rows that front Intervally Pro.
@Suite("Settings Pro rows")
struct SettingsProRowTests {

    @Test("The Pro row, for each way Pro can be held")
    func proRow() {
        #expect(ProStatusRow.title == "Intervally Pro")
        #expect(ProStatusRow(isPro: false, ownership: .none) == ProStatusRow(isPro: false, ownership: .purchased))
        let free = ProStatusRow(isPro: false, ownership: .none)
        #expect(free.subtitle == "Unlimited presets & more")
        #expect(free.systemImage == "sparkles")
        let bought = ProStatusRow(isPro: true, ownership: .purchased)
        #expect(bought.subtitle == "Unlocked")
        #expect(bought.systemImage == "checkmark.seal.fill")
        #expect(ProStatusRow(isPro: true, ownership: .familyShared).subtitle == "Shared by your family")
        // Pro from the cache before StoreKit answers: bought outright, not "free".
        #expect(ProStatusRow(isPro: true, ownership: .none) == bought)
    }

    @Test("Without Pro the row shows what plays — Standard — locked, whatever is saved", arguments: TapStrength.allCases)
    func tapStrengthFree(stored: TapStrength) {
        let row = TapStrengthRow(stored: stored, isPro: false)
        #expect(row.value == "Standard")
        #expect(row.isLocked)
        #expect(row.footer == "Stronger taps are part of Intervally Pro.")
    }

    @Test("With Pro the row shows the saved strength, unlocked", arguments: TapStrength.allCases)
    func tapStrengthPro(stored: TapStrength) {
        let row = TapStrengthRow(stored: stored, isPro: true)
        #expect(row.value == stored.title)
        #expect(row.isLocked == false)
        #expect(row.footer == "Taps repeat at every interval change.")
    }

    @Test("The picker's footer discloses the skipped countdown taps")
    func pickerFooter() {
        #expect(TapStrengthView.footer == "Repeats the tap at every interval change. On short intervals a countdown tap may be skipped so taps don't run together.")
        #expect(TapStrength.allCases.map(\.title) == ["Standard", "Strong", "Strongest"])
        #expect(TapStrength.allCases.map(\.detail) == ["One tap", "Two taps", "Three taps"])
    }
}

/// New Preset and Duplicate at the free limit: the paywall first, the copy only after an
/// unlock, and nothing added on the way.
@Suite("Preset copy gate")
@MainActor
struct PresetCopyGateTests {

    @Test("Under the limit the copy is made at once and no paywall opens")
    func underTheLimit() {
        var gate = PresetCopyGate()
        let id = UUID()
        #expect(gate.request(copyOf: id, canAdd: true) == id)
        #expect(gate.paywallFor == nil)
        #expect(gate.paywallClosed() == nil)
    }

    @Test("At the limit the paywall opens for that preset, and nothing is copied yet")
    func atTheLimit() {
        var gate = PresetCopyGate()
        let id = UUID()
        #expect(gate.request(copyOf: id, canAdd: false) == nil)
        #expect(gate.paywallFor == id)
        // Still on the paywall: nothing to copy.
        #expect(gate.paywallClosed() == nil)
        #expect(gate.paywallFor == id)
    }

    @Test("An unlock pops the paywall and hands back the preset to copy, exactly once")
    func unlockCopiesOnce() {
        var gate = PresetCopyGate()
        let id = UUID()
        _ = gate.request(copyOf: id, canAdd: false)
        gate.unlocked()
        #expect(gate.paywallFor == nil)
        #expect(gate.pendingDuplicate == id)
        #expect(gate.paywallClosed() == id)
        #expect(gate.paywallClosed() == nil)
        #expect(gate.pendingDuplicate == nil)
    }

    @Test("Backing out without buying copies nothing")
    func backOut() {
        var gate = PresetCopyGate()
        _ = gate.request(copyOf: UUID(), canAdd: false)
        gate.paywallFor = nil  // the back button
        #expect(gate.paywallClosed() == nil)
    }

    @Test("A purchase that lands after Back can't copy behind a later paywall")
    func lateUnlock() {
        var gate = PresetCopyGate()
        _ = gate.request(copyOf: UUID(), canAdd: false)
        gate.paywallFor = nil
        gate.unlocked()
        #expect(gate.pendingDuplicate == nil)

        let later = UUID()
        _ = gate.request(copyOf: later, canAdd: false)
        gate.paywallFor = nil
        #expect(gate.paywallClosed() == nil)
    }

    @Test("A fresh install's New Preset opens the paywall, and the store keeps its three starters")
    func freshInstallIsGated() {
        let store = WorkoutStore(defaults: makeTestDefaults())
        let free = FakePro()
        var gate = PresetCopyGate()
        let canAdd = free.canAddPreset(currentCount: store.workouts.count)
        #expect(gate.request(copyOf: store.selected.id, canAdd: canAdd) == nil)
        #expect(gate.paywallFor == store.selected.id)
        #expect(store.workouts.count == ProProduct.freePresetLimit)
    }
}

/// Setup's dial and the bookend editors.
@Suite("Setup with bookends")
@MainActor
struct SetupBookendTests {

    /// Spoken durations come from the system formatter, so expectations are built with it.
    private func spoken(_ seconds: Int) -> String { DurationFormat.spoken(seconds) }

    @Test("Without bookends the dial reads as it always has")
    func dialLabelWithoutBookends() {
        let classic = IntervalWorkout(name: "Classic", prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 8)
        #expect(SetupView.dialAccessibilityLabel(for: classic)
            == "Classic. \(spoken(30)) work, \(spoken(15)) rest, 8 rounds, total \(spoken(355))")
        let noRest = IntervalWorkout(name: "EMOM", prepareSeconds: 0, workSeconds: 60, restSeconds: 0, rounds: 1)
        #expect(SetupView.dialAccessibilityLabel(for: noRest)
            == "EMOM. \(spoken(60)) work, no rest, \(DurationFormat.rounds(1)), total \(spoken(60))")
    }

    @Test("Bookends are read in the order they run, and only when on")
    func dialLabelWithBookends() {
        let workout = IntervalWorkout(
            name: "Hills", prepareSeconds: 0, warmupSeconds: 300, workSeconds: 30,
            restSeconds: 30, rounds: 2, cooldownSeconds: 120
        )
        #expect(SetupView.dialAccessibilityLabel(for: workout)
            == "Hills. \(spoken(300)) warmup, \(spoken(30)) work, \(spoken(30)) rest, 2 rounds, \(spoken(120)) cooldown, total \(spoken(510))")

        var warmupOnly = workout
        warmupOnly.cooldownSeconds = 0
        #expect(SetupView.dialAccessibilityLabel(for: warmupOnly).contains("cooldown") == false)
        #expect(SetupView.dialAccessibilityLabel(for: warmupOnly).hasPrefix("Hills. \(spoken(300)) warmup, "))
    }

    @Test("A free user's dial is the effective workout: no bookends read, and the total without them")
    func dialLabelWithoutPro() {
        let workout = IntervalWorkout(name: "Hills", prepareSeconds: 0, warmupSeconds: 300, workSeconds: 30, restSeconds: 30, rounds: 2, cooldownSeconds: 120)
        let label = SetupView.dialAccessibilityLabel(for: workout.effective(isPro: false))
        #expect(label == "Hills. \(spoken(30)) work, \(spoken(30)) rest, 2 rounds, total \(spoken(90))")
    }

    @Test("A bookend's editor: nothing under Off, then the unit its digits are read in")
    func bookendUnit() {
        #expect(SetupView.bookendUnit(0) == "")
        #expect(SetupView.bookendUnit(30) == "seconds")
        #expect(SetupView.bookendUnit(60) == "minutes")
        #expect(SetupView.bookendUnit(1800) == "minutes")
    }

    @Test("The bookend editor turns over the bookend table, captioned by value")
    func bookendEditor() {
        let editor = bookendEditor(value: 0)
        #expect(editor.values == IntervalWorkout.bookendValues)
        #expect(editor.unitLabel == "")
        #expect(bookendEditor(value: 30).unitLabel == "seconds")
        #expect(bookendEditor(value: 300).unitLabel == "minutes")
    }

    @Test("Without a table or a unit the editor behaves as before")
    func editorDefaults() {
        let rounds = ValueEditorView(
            title: "Rounds", systemImage: "repeat", range: IntervalWorkout.roundsRange, step: 1,
            tint: .white, format: { "\($0)" }, spoken: DurationFormat.rounds, value: .constant(1)
        )
        #expect(rounds.values == Array(1...99))
        #expect(rounds.unitLabel == "round")

        let work = ValueEditorView(
            title: "Work", systemImage: "bolt.fill", range: IntervalWorkout.workRange, step: 5,
            tint: Theme.work, format: DurationFormat.bare, spoken: DurationFormat.spoken, value: .constant(90)
        )
        #expect(work.values == ValueEditorView.values(in: IntervalWorkout.workRange, step: 5))
        #expect(work.unitLabel == "minutes")
    }

    private func bookendEditor(value: Int) -> ValueEditorView {
        ValueEditorView(
            title: "Warmup", systemImage: "sunrise.fill", range: IntervalWorkout.warmupRange, step: 30,
            tint: Theme.warmup, format: DurationFormat.bookendEditor, spoken: DurationFormat.bookendSpoken,
            unit: SetupView.bookendUnit, valueTable: IntervalWorkout.bookendValues, value: .constant(value)
        )
    }
}
