//
//  WorkoutActivityTests.swift
//  IntervallyTests
//

import Foundation
import HealthKit
import Testing
@testable import Intervally

/// A preset's activity: what Health records it as, how it is stored and synced, and how the
/// picker finds it.
@Suite("Workout activity")
struct WorkoutActivityTests {
    @Test("Every activity is in exactly one of the picker's groups")
    func groupsCoverEveryCase() {
        let grouped = WorkoutActivity.Group.allCases.flatMap(\.activities)
        #expect(grouped.count == WorkoutActivity.allCases.count)
        #expect(Set(grouped) == Set(WorkoutActivity.allCases))
        #expect(Set(WorkoutActivity.allCases.map(\.title)).count == WorkoutActivity.allCases.count, "Titles tell them apart")
    }

    @Test("Health records each as its own type, outdoors only where it says so, and reads it back", arguments: WorkoutActivity.allCases)
    func healthKitRoundTrip(_ activity: WorkoutActivity) {
        let configuration = activity.configuration
        #expect(configuration.activityType == activity.healthKitType)
        #expect(configuration.locationType == (activity.isOutdoor ? .outdoor : .indoor))
        #expect(WorkoutActivity(activity.healthKitType, indoor: !activity.isOutdoor) == activity)
    }

    @Test("HIIT stays what an unchosen preset runs as, and a type the picker lacks reads as none")
    func defaultsAndUnknowns() {
        #expect(WorkoutActivity.standard.configuration.activityType == .highIntensityIntervalTraining)
        #expect(IntervalWorkout().activityKind == .hiit)
        #expect(WorkoutActivity(.golf, indoor: false) == nil)
        #expect(WorkoutActivity(.running, indoor: nil) == .indoorRun, "No indoor flag reads as indoors, as a session started here would be")
    }

    @Test("Search matches the start of any word of the name or a keyword")
    func search() {
        func found(_ text: String) -> Set<WorkoutActivity> { Set(WorkoutActivity.allCases.filter { $0.matches(text) }) }
        #expect(found("") == Set(WorkoutActivity.allCases))
        #expect(found("run") == [.outdoorRun, .indoorRun])
        #expect(found("tread") == [.indoorRun, .indoorWalk])
        #expect(found("out cyc") == [.outdoorCycle])
        #expect(found("TABATA") == [.hiit])
        #expect(found("bike") == [.outdoorCycle, .indoorCycle])
        #expect(found("zzz").isEmpty)
    }
}

/// The activity on disk and on the wire: absent until chosen, and never lost to a version
/// that predates it.
@Suite("Workout activity — storage and sync")
struct WorkoutActivitySyncTests {
    @Test("A preset saved before there was a choice reads as never chosen, and encodes as it did")
    func absentStaysAbsent() throws {
        let old = Data(#"{"id":"2F1F7C1C-1E5F-4C0B-9C4F-6A0C1D2E3F40","name":"Old","workSeconds":30}"#.utf8)
        let workout = try JSONDecoder().decode(IntervalWorkout.self, from: old)
        #expect(workout.activity == nil)
        #expect(workout.activityKind == .hiit)
        let encoded = try #require(String(data: JSONEncoder().encode(workout), encoding: .utf8))
        #expect(!encoded.contains("activity"))
    }

    @Test("A chosen activity survives the trip, and one from a later version reads as none")
    func roundTripAndUnknown() throws {
        let chosen = IntervalWorkout(name: "Hills", activity: .outdoorRun)
        let decoded = try JSONDecoder().decode(IntervalWorkout.self, from: JSONEncoder().encode(chosen))
        #expect(decoded == chosen)

        let future = Data(#"{"id":"2F1F7C1C-1E5F-4C0B-9C4F-6A0C1D2E3F40","name":"Later","activity":"pickleball","rounds":5}"#.utf8)
        let lenient = try JSONDecoder().decode(IntervalWorkout.self, from: future)
        #expect(lenient.activity == nil)
        #expect(lenient.rounds == 5, "The rest of the preset still reads")
    }

    private func record(_ workout: IntervalWorkout, at millis: Int64, on device: String) -> PresetRecord {
        PresetRecord(id: workout.id, workout: workout, deleted: false, order: 0, stamp: SyncStamp(millis: millis, device: device))
    }

    @Test("A later edit from a version without the choice keeps the activity chosen here")
    func olderVersionEditKeepsActivity() {
        var mine = IntervalWorkout(name: "Hills", rounds: 6)
        mine.activity = .outdoorRun
        var theirs = mine
        theirs.activity = nil
        theirs.rounds = 8

        let merged = record(mine, at: 100, on: "phone").merged(with: record(theirs, at: 200, on: "watch"))
        #expect(merged.workout.rounds == 8, "Their later edit still wins")
        #expect(merged.workout.activity == .outdoorRun)
    }

    @Test("A later choice wins, HIIT chosen on purpose included")
    func laterChoiceWins() {
        var mine = IntervalWorkout(name: "Hills")
        mine.activity = .outdoorRun
        var theirs = mine
        theirs.activity = .hiit

        let merged = record(mine, at: 100, on: "phone").merged(with: record(theirs, at: 200, on: "watch"))
        #expect(merged.workout.activity == .hiit)
        let older = record(mine, at: 300, on: "phone").merged(with: record(theirs, at: 200, on: "watch"))
        #expect(older.workout.activity == .outdoorRun)
    }

    @Test("Setting the activity is an edit like any other: stamped, kept and offered to sync")
    @MainActor
    func storeSetsActivity() {
        let store = WorkoutStore(defaults: makeTestDefaults())
        var edits = 0
        store.onLocalChange = { edits += 1 }
        let preset = store.workouts[0]

        store.setActivity(preset.id, to: .rowing)
        #expect(store.workouts[0].activity == .rowing)
        #expect(edits == 1)
        store.setActivity(preset.id, to: .rowing)
        #expect(edits == 1, "Choosing what is already chosen changes nothing")
        store.setActivity(UUID(), to: .yoga)
        #expect(edits == 1)
    }
}
