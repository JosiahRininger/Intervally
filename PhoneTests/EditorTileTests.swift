//
//  EditorTileTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// The editor's tiles and pickers: the watch's values, the Pro lock, and clamping.
@Suite("Editor tiles")
@MainActor
struct EditorTileTests {
    let bookended = IntervalWorkout(
        name: "Hills", prepareSeconds: 10, warmupSeconds: 300,
        workSeconds: 90, restSeconds: 30, rounds: 6, cooldownSeconds: 120
    )

    @Test("Each picker offers exactly the watch's crown values", arguments: PresetField.allCases)
    func pickerValuesAreTheWatchs(field: PresetField) {
        let expected: [Int] = switch field {
        case .work: ValueSteps.values(in: IntervalWorkout.workRange, step: 5)
        case .rest: ValueSteps.values(in: IntervalWorkout.restRange, step: 5)
        case .prepare: ValueSteps.values(in: IntervalWorkout.prepareRange, step: 5)
        case .rounds: ValueSteps.values(in: IntervalWorkout.roundsRange, step: 1)
        case .warmup, .cooldown: IntervalWorkout.bookendValues
        }
        #expect(field.values == expected)
        #expect(field.values.allSatisfy(field.range.contains), "Every row is in range")
        #expect(field.values == field.values.sorted())
    }

    @Test("The tables at a glance")
    func tables() {
        #expect(PresetField.rounds.values == Array(1...99))
        #expect(PresetField.work.values.count == 156)
        #expect(PresetField.warmup.values.first == 0)
        #expect(PresetField.warmup.values.contains(30) && PresetField.warmup.values.contains(1800))
        #expect(PresetField.prepare.values == [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60])
    }

    @Test("Bookends are locked without Pro, the stored value kept out of sight")
    func bookendsLockedWhenFree() {
        for field in [PresetField.warmup, .cooldown] {
            let tile = EditorTileContent(field: field, workout: bookended, isPro: false)
            #expect(tile.isLocked)
            #expect(tile.value == nil)
            #expect(tile.accessibilityValue == "Locked")
            #expect(tile.accessibilityHint == "Opens Intervally Pro")
        }
    }

    @Test("They unlock the moment isPro flips, with the value that was stored")
    func bookendsUnlockWithPro() {
        let pro = FakePro()
        func tile(_ field: PresetField) -> EditorTileContent {
            EditorTileContent(field: field, workout: bookended, isPro: pro.isPro)
        }
        #expect(tile(.warmup).isLocked)
        pro.isPro = true
        #expect(tile(.warmup).isLocked == false)
        #expect(tile(.warmup).value == "5:00")
        #expect(tile(.cooldown).value == "2:00")
        #expect(tile(.warmup).accessibilityValue == DurationFormat.bookendSpoken(300))
    }

    @Test("The four interval tiles are never locked", arguments: [PresetField.work, .rest, .rounds, .prepare])
    func intervalTilesOpen(field: PresetField) {
        let tile = EditorTileContent(field: field, workout: bookended, isPro: false)
        #expect(tile.isLocked == false)
        #expect(tile.value == field.tileText(bookended[keyPath: field.keyPath]))
        #expect(tile.accessibilityHint == "Opens a picker")
    }

    @Test("Every tile a tap opens a picker for shows the chevron that says so; a locked one doesn't")
    func pickerHint() {
        let workout = WorkoutStore.starterWorkouts[0]
        for field in PresetField.allCases {
            #expect(EditorTileContent(field: field, workout: workout, isPro: true).showsPickerHint)
            #expect(EditorTileContent(field: field, workout: workout, isPro: false).showsPickerHint == !field.isPro)
        }
    }

    @Test("The first-run hint names both things a tap changes, and is kept per iPhone")
    func firstRunTip() {
        #expect(EditorLayout.tip == "Tap the name or any tile to change it.")
        #expect(EditorLayout.tipSeenKey.hasPrefix("phone."), "Never synced to the watch")
    }

    @Test("Tile words, as the watch's tiles show them")
    func tileText() {
        func value(_ field: PresetField) -> String? {
            EditorTileContent(field: field, workout: bookended, isPro: true).value
        }
        #expect(value(.work) == "1:30")
        #expect(value(.rest) == "30s")
        #expect(value(.rounds) == "6")
        #expect(value(.prepare) == "10s")
        var off = bookended
        off.warmupSeconds = 0
        #expect(EditorTileContent(field: .warmup, workout: off, isPro: true).value == "Off")
    }

    @Test("A wheel row spells rounds out, and shows durations as the tile does")
    func rowText() {
        #expect(ValuePickerSheet.rowText(.rounds, 8) == "8 rounds")
        #expect(ValuePickerSheet.rowText(.rounds, 1) == "1 round")
        #expect(ValuePickerSheet.rowText(.work, 45) == "45s")
        #expect(ValuePickerSheet.rowText(.cooldown, 0) == "Off")
    }

    @Test("A stored value off the table opens at its nearest neighbour, the lower on a tie")
    func nearestValue() {
        #expect(PresetField.work.nearestValue(to: 7) == 5)
        #expect(PresetField.work.nearestValue(to: 8) == 10)
        #expect(PresetField.work.nearestValue(to: 125) == 120)
        #expect(PresetField.warmup.nearestValue(to: 45) == 30)
        #expect(PresetField.warmup.nearestValue(to: 10) == 0)
        #expect(PresetField.rounds.nearestValue(to: 500) == 99)
        #expect(PresetField.work.nearestValue(to: 3) == 5)
    }

    @Test("Clamping holds: a value out of range is saved at the nearest limit")
    func clampingHolds() throws {
        let store = WorkoutStore(defaults: makeTestDefaults())
        var workout = store.selected
        workout.workSeconds = 99_999
        workout.rounds = 0
        workout.warmupSeconds = -5
        store.update(workout)
        #expect(store.selected.workSeconds == IntervalWorkout.workRange.upperBound)
        #expect(store.selected.rounds == IntervalWorkout.roundsRange.lowerBound)
        #expect(store.selected.warmupSeconds == 0)
    }

    @Test("Turning a picker to the value already stored saves nothing new")
    func unchangedPickStampsNothing() {
        let store = WorkoutStore(defaults: makeTestDefaults())
        let changes = Counter()
        store.onLocalChange = { changes.increment() }
        var workout = store.selected
        workout.workSeconds = store.selected.workSeconds
        store.update(workout)
        #expect(changes.value == 0)
        workout.workSeconds = 45
        store.update(workout)
        #expect(changes.value == 1)
    }
}
