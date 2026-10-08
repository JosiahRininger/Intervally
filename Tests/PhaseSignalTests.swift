//
//  PhaseSignalTests.swift
//  IntervallyTests
//

import Testing
import Foundation
import HealthKit
import WatchKit
@testable import Intervally

/// How each phase reaches Health and the wrist. The bookends must not invent a round, and
/// must not change the workout's activity type.
@Suite("Health activity metadata")
struct ActivityMetadataTests {

    private func metadata(_ kind: IntervalPhase.Kind, round: Int) -> [String: Any] {
        WorkoutSessionController.activityMetadata(
            for: IntervalPhase(id: 0, kind: kind, duration: 60, round: round, start: 0)
        )
    }

    @Test("Every activity is tagged indoor with its phase", arguments: [
        IntervalPhase.Kind.prepare, .warmup, .work, .rest, .cooldown,
    ])
    func taggedWithPhase(kind: IntervalPhase.Kind) {
        let tags = metadata(kind, round: 2)
        #expect(tags[HKMetadataKeyIndoorWorkout] as? Bool == true)
        #expect(tags[WorkoutSessionController.phaseMetadataKey] as? String == kind.rawValue)
    }

    @Test("Interval phases carry their round")
    func intervalsCarryRound() {
        #expect(metadata(.work, round: 3)[WorkoutSessionController.roundMetadataKey] as? Int == 3)
        #expect(metadata(.rest, round: 3)[WorkoutSessionController.roundMetadataKey] as? Int == 3)
        #expect(metadata(.prepare, round: 1)[WorkoutSessionController.roundMetadataKey] as? Int == 1)
    }

    @Test("The warmup and cooldown carry no round")
    func bookendsCarryNoRound() {
        #expect(metadata(.warmup, round: 1)[WorkoutSessionController.roundMetadataKey] == nil)
        #expect(metadata(.cooldown, round: 8)[WorkoutSessionController.roundMetadataKey] == nil)
        #expect(metadata(.warmup, round: 1)[WorkoutSessionController.phaseMetadataKey] as? String == "warmup")
        #expect(metadata(.cooldown, round: 8)[WorkoutSessionController.phaseMetadataKey] as? String == "cooldown")
    }
}

@Suite("Boundary haptic per phase")
struct BoundaryHapticTypeTests {

    @Test("Each phase start has its tap; the bookends use the directional pair")
    func types() {
        #expect(Haptics.boundaryType(for: .prepare) == .start)
        #expect(Haptics.boundaryType(for: .warmup) == .directionUp)
        #expect(Haptics.boundaryType(for: .work) == .notification)
        #expect(Haptics.boundaryType(for: .rest) == .directionDown)
        #expect(Haptics.boundaryType(for: .cooldown) == .directionDown)
    }

    @Test("Work never shares its tap: it is the one that must be felt through a sleeve")
    func workIsDistinct() {
        let others: [IntervalPhase.Kind] = [.prepare, .warmup, .rest, .cooldown]
        #expect(others.allSatisfy { Haptics.boundaryType(for: $0) != Haptics.boundaryType(for: .work) })
    }
}
