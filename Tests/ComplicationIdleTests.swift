//
//  ComplicationIdleTests.swift
//  IntervallyTests
//

import Testing
import Foundation
@testable import Intervally

/// An isolated defaults domain per test so they never bleed into each other.
private func makeDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// What the complication reads between workouts: the preset to offer, and when to offer it.
@Suite("Complication idle face")
struct ComplicationIdleTests {

    // MARK: Selected preset

    @Test("Before the app has saved anything there is no preset to offer")
    func noPresetBeforeFirstLaunch() {
        #expect(WorkoutStore.selectedPreset(in: makeDefaults()) == nil)
    }

    @Test("The static reader sees the preset the store selected")
    @MainActor
    func readerFollowsSelection() {
        let defaults = makeDefaults()
        let store = WorkoutStore(defaults: defaults)
        store.selectedID = store.workouts[2].id

        // The widget's path: a plain read of the shared suite, no @MainActor store.
        let preset = WorkoutStore.selectedPreset(in: defaults)
        #expect(preset == store.workouts[2])
        #expect(preset?.name == "EMOM")
    }

    @Test("Edits to the selected preset reach the reader")
    @MainActor
    func readerSeesEdits() {
        let defaults = makeDefaults()
        let store = WorkoutStore(defaults: defaults)
        var workout = store.selected
        workout.name = "Hills"
        workout.rounds = 12
        store.update(workout)

        let preset = WorkoutStore.selectedPreset(in: defaults)
        #expect(preset?.name == "Hills")
        #expect(preset?.rounds == 12)
    }

    @Test("A selection that no longer names a preset falls back to the first one")
    @MainActor
    func readerFallsBackToFirst() {
        let defaults = makeDefaults()
        let store = WorkoutStore(defaults: defaults)
        defaults.set(UUID().uuidString, forKey: WorkoutStore.Key.selected)

        #expect(WorkoutStore.selectedPreset(in: defaults) == store.workouts[0])
    }

    // MARK: Start history

    private let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("Starts accumulate in order and the oldest fall off")
    func startsAreCapped() {
        let defaults = makeDefaults()
        for minute in 0..<15 {
            WorkoutStore.recordStart(noon.addingTimeInterval(TimeInterval(minute * 3600)), in: defaults)
        }
        let starts = WorkoutStore.recentStarts(in: defaults)
        #expect(starts.count == WorkoutStore.startHistoryLimit)
        #expect(starts.first == noon.addingTimeInterval(5 * 3600))
        #expect(starts.last == noon.addingTimeInterval(14 * 3600))
    }

    @Test("A restored run reports the start it already had, and is not counted twice")
    func restoreIsNotASecondStart() {
        let defaults = makeDefaults()
        WorkoutStore.recordStart(noon, in: defaults)
        WorkoutStore.recordStart(noon, in: defaults)
        WorkoutStore.recordStart(noon.addingTimeInterval(0.4), in: defaults)
        #expect(WorkoutStore.recentStarts(in: defaults).count == 1)

        WorkoutStore.recordStart(noon.addingTimeInterval(90), in: defaults)
        #expect(WorkoutStore.recentStarts(in: defaults).count == 2)
    }

    @Test("Nothing recorded means no window to offer")
    func noHistoryNoWindow() {
        #expect(WorkoutStore.usualStartWindow(from: [], now: noon) == nil)
    }

    // MARK: Usual start window

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// `hour:minute` on `day`, in UTC.
    private func at(_ hour: Int, _ minute: Int = 0, day: Date) -> Date {
        utc.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    @Test("The window is the hour around the median start, on the day asked about")
    func windowCentresOnMedian() {
        let today = utc.startOfDay(for: noon)
        let starts = [at(7, 10, day: today), at(6, 50, day: today), at(7, 0, day: today)]
        let window = WorkoutStore.usualStartWindow(from: starts, now: at(1, day: today), calendar: utc)

        #expect(window?.start == at(6, 30, day: today))
        #expect(window?.end == at(7, 30, day: today))
    }

    @Test("One late-night session does not drag a morning habit into the afternoon")
    func medianIgnoresOutlier() {
        let today = utc.startOfDay(for: noon)
        let yesterday = utc.date(byAdding: .day, value: -1, to: today)!
        let starts = [
            at(7, day: yesterday), at(7, 5, day: yesterday), at(6, 55, day: yesterday), at(23, 30, day: yesterday),
        ]
        let window = WorkoutStore.usualStartWindow(from: starts, now: at(1, day: today), calendar: utc)

        // Even count: the upper middle, so the window still sits in the morning.
        #expect(window?.start == at(6, 35, day: today))
    }

    @Test("Once today's window has closed the next one is tomorrow's")
    func windowRollsToTomorrow() {
        let today = utc.startOfDay(for: noon)
        let tomorrow = utc.date(byAdding: .day, value: 1, to: today)!
        let starts = [at(7, day: today)]

        let still = WorkoutStore.usualStartWindow(from: starts, now: at(7, 29, day: today), calendar: utc)
        #expect(still?.start == at(6, 30, day: today))

        let rolled = WorkoutStore.usualStartWindow(from: starts, now: at(7, 31, day: today), calendar: utc)
        #expect(rolled?.start == at(6, 30, day: tomorrow))
        #expect(rolled?.duration == 3600)
    }

    @Test("A start just after midnight opens a window that begins the evening before")
    func windowMayStraddleMidnight() {
        let today = utc.startOfDay(for: noon)
        let starts = [at(0, 10, day: today)]
        let window = WorkoutStore.usualStartWindow(from: starts, now: at(0, day: today), calendar: utc)

        #expect(window?.start == today.addingTimeInterval(-20 * 60))
        #expect(window?.end == at(0, 40, day: today))
    }
}
