//
//  ActivityPickerTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
import UIKit
@testable import IntervallyPhone

/// The editor's activity picker and what History shows of the choice.
@Suite("Activity picker")
struct ActivityPickerTests {
    @Test("Every activity's figure is a real SF Symbol on this iOS", arguments: WorkoutActivity.allCases)
    func symbolsExist(_ activity: WorkoutActivity) {
        #expect(UIImage(systemName: activity.symbolName) != nil, "\(activity.symbolName)")
    }

    @Test("With no search every group shows in order; a search keeps only groups with a match")
    func groups() {
        let all = ActivityPicker.groups(matching: "")
        #expect(all.map(\.id) == WorkoutActivity.Group.allCases)
        #expect(all.flatMap(\.activities).count == WorkoutActivity.allCases.count)

        let rowing = ActivityPicker.groups(matching: "row")
        #expect(rowing.map(\.id) == [.machines])
        #expect(rowing.first?.activities == [.rowing])
        #expect(ActivityPicker.groups(matching: "zzz").isEmpty)
    }

    @Test("History names a session by what Health recorded it as")
    func sessionCarriesActivity() {
        let raw = RawWorkout(
            id: UUID(), start: Date(), duration: 600, presetName: "Hills", plannedRounds: 6,
            averageHeartRate: nil, maximumHeartRate: nil, activeEnergy: nil, activities: [],
            activity: .outdoorRun
        )
        #expect(SessionSummary(raw).activity == .outdoorRun)
        var unknown = raw
        unknown.activity = nil
        #expect(SessionSummary(unknown).activity == nil)
    }

    @Test("The sample hill repeats are an outdoor run, the starters HIIT")
    func sampleActivities() {
        let sessions = SampleHistory.sessions(now: Date())
        #expect(sessions.contains { $0.presetName == "Hill Repeats" && $0.activity == .outdoorRun })
        #expect(sessions.contains { $0.presetName == "Classic" && $0.activity == .hiit })
    }
}
