//
//  PresetCardContentTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// What a library card shows for a preset, with and without Pro.
@Suite("Preset card")
struct PresetCardContentTests {
    let bookended = IntervalWorkout(
        name: "Long", prepareSeconds: 10, warmupSeconds: 300,
        workSeconds: 30, restSeconds: 15, rounds: 8, cooldownSeconds: 120
    )

    @Test("A starter shows its rhythm and total time")
    @MainActor
    func starter() throws {
        let classic = try #require(WorkoutStore.starterWorkouts.first)
        let content = PresetCardContent(workout: classic, isPro: false)
        #expect(content.name == "Classic")
        #expect(content.rhythm == "30s · 15s · 8×")
        // 10 + 8 × 30 + 7 × 15 = 355 seconds.
        #expect(content.total == "5:55")
        #expect(content.runs == classic)
    }

    @Test("Without Pro, the warmup and cooldown are left out of the ring, total and summary")
    func freeOmitsBookends() {
        let content = PresetCardContent(workout: bookended, isPro: false)
        #expect(content.runs.warmupSeconds == 0)
        #expect(content.runs.cooldownSeconds == 0)
        #expect(content.total == "5:55")
        #expect(!content.spokenSummary.contains("warmup"))
        #expect(!content.spokenSummary.contains("cooldown"))
    }

    @Test("With Pro, they count")
    func proIncludesBookends() {
        let content = PresetCardContent(workout: bookended, isPro: true)
        #expect(content.runs == bookended)
        // 355 + 300 + 120 = 775 seconds.
        #expect(content.total == "12:55")
        #expect(content.spokenSummary.contains("warmup"))
        #expect(content.spokenSummary.contains("cooldown"))
    }

    @Test("VoiceOver hears the whole preset, as on the watch's dial")
    func spokenSummary() {
        let workout = IntervalWorkout(name: "Sprint", prepareSeconds: 0, workSeconds: 20, restSeconds: 0, rounds: 1)
        let content = PresetCardContent(workout: workout, isPro: false)
        #expect(content.spokenSummary.hasPrefix("Sprint. "))
        #expect(content.spokenSummary.contains("no rest"))
        #expect(content.spokenSummary == workout.spokenSummary)
    }
}
