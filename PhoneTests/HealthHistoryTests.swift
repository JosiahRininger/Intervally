//
//  HealthHistoryTests.swift
//  IntervallyPhoneTests
//

import Foundation
import HealthKit
import Testing
@testable import IntervallyPhone

/// The thin layer between HealthKit and History: what it asks for, how it finds Intervally's
/// workouts, and how it reads the watch's tags back.
@Suite("Health history")
struct HealthHistoryTests {

    private func activity(_ metadata: [String: Any]?, seconds: TimeInterval = 30) -> HKWorkoutActivity {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .highIntensityIntervalTraining
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return HKWorkoutActivity(workoutConfiguration: configuration, start: start, end: start.addingTimeInterval(seconds), metadata: metadata)
    }

    @Test("An interval's phase and round are read back as the watch tags them")
    func activityTags() {
        let read = RawWorkout.Activity(activity([HealthMetadata.phase: "work", HealthMetadata.round: 3], seconds: 45))
        #expect(read.phase == "work")
        #expect(read.round == 3)
        #expect(read.duration == 45)
        #expect(read.start == Date(timeIntervalSinceReferenceDate: 800_000_000))
        // No samples behind a made-up activity, so no heart rate.
        #expect(read.averageHeartRate == nil)
    }

    @Test("A bookend's missing round, and tags of the wrong type, read as none")
    func lenientActivityTags() {
        let bookend = RawWorkout.Activity(activity([HealthMetadata.phase: "warmup"]))
        #expect(bookend.phase == "warmup")
        #expect(bookend.round == nil)

        let garbled = RawWorkout.Activity(activity([HealthMetadata.phase: 7, HealthMetadata.round: "three"]))
        #expect(garbled.phase == nil)
        #expect(garbled.round == nil)

        #expect(RawWorkout.Activity(activity(nil)).phase == nil)
    }

    @Test("The workout's tags are read leniently: a wrong type is as good as none")
    func workoutTags() {
        let tags = RawWorkout.tags(from: [HealthMetadata.presetName: "Tabata", HealthMetadata.plannedRounds: 8])
        #expect(tags.name == "Tabata")
        #expect(tags.plannedRounds == 8)

        let garbled = RawWorkout.tags(from: [HealthMetadata.presetName: 12, HealthMetadata.plannedRounds: "8"])
        #expect(garbled.name == nil)
        #expect(garbled.plannedRounds == nil)

        let none = RawWorkout.tags(from: nil)
        #expect(none.name == nil)
        #expect(none.plannedRounds == nil)
    }

    @Test("Intervally's workouts are found by the preset tag the watch writes")
    func predicate() {
        #expect(HealthHistory.predicate.predicateFormat.contains(HealthMetadata.presetID))
    }

    @Test("History asks to read only workouts, heart rate and active energy")
    func readTypes() {
        #expect(HealthHistory.readTypes == [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
        ])
    }

    @Test("History never asks to write, and reads exactly what the watch also asks to read")
    func requestMatchesTheWatch() {
        #expect(HealthHistory.shareTypes.isEmpty)
        #expect(Set(HealthHistory.readTypes.map(\.identifier)) == HealthAccess.historyReads)
    }

    @Test("The Health explainer lists exactly what History asks to read")
    func explainerMatchesRequest() {
        #expect(Set(HealthReadItem.all.map(\.type)) == HealthHistory.readTypes)
        #expect(HealthReadItem.all.count == HealthHistory.readTypes.count)
    }
}
