//
//  IntervalPlanTests.swift
//  IntervallyTests
//

import Testing
import Foundation
import SwiftUI
@testable import Intervally

@Suite("Interval plan construction")
struct IntervalPlanConstructionTests {

    @Test("A plan expands into prepare + work/rest phases with no trailing rest")
    func expandsPhases() {
        let workout = IntervalWorkout(
            prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 3
        )
        let plan = IntervalPlan(workout: workout)

        #expect(plan.phases.map(\.kind) == [.prepare, .work, .rest, .work, .rest, .work])
        // The legacy app appended a rest after every round including the last, so a
        // workout never actually ended on the work interval.
        #expect(plan.phases.last?.kind == .work)
        let expected: TimeInterval = 10 + (30 * 3) + (15 * 2)
        #expect(plan.totalDuration == expected)
        #expect(plan.totalDuration == TimeInterval(workout.totalSeconds))
    }

    @Test("Zero-length phases are omitted entirely")
    func omitsZeroLengthPhases() {
        let plan = IntervalPlan(
            workout: IntervalWorkout(prepareSeconds: 0, workSeconds: 20, restSeconds: 0, rounds: 3)
        )
        #expect(plan.phases.map(\.kind) == [.work, .work, .work])
        #expect(plan.totalDuration == 60)
    }

    @Test("Phase start offsets are contiguous")
    func contiguousOffsets() {
        let plan = IntervalPlan(
            workout: IntervalWorkout(prepareSeconds: 5, workSeconds: 20, restSeconds: 10, rounds: 4)
        )
        var cursor: TimeInterval = 0
        for phase in plan.phases {
            #expect(phase.start == cursor)
            cursor += phase.duration
        }
        #expect(cursor == plan.totalDuration)
    }

    @Test("Rounds are numbered 1-based and each work phase gets its own round")
    func roundNumbering() {
        let plan = IntervalPlan(
            workout: IntervalWorkout(prepareSeconds: 5, workSeconds: 10, restSeconds: 5, rounds: 4)
        )
        let workRounds = plan.phases.filter { $0.kind == .work }.map(\.round)
        #expect(workRounds == [1, 2, 3, 4])
        #expect(plan.totalRounds == 4)
    }

    @Test("A single-round workout has exactly one work phase and no rest")
    func singleRound() {
        let plan = IntervalPlan(
            workout: IntervalWorkout(prepareSeconds: 0, workSeconds: 45, restSeconds: 20, rounds: 1)
        )
        #expect(plan.phases.map(\.kind) == [.work])
        #expect(plan.totalDuration == 45)
    }

    @Test("Out-of-range configuration is clamped rather than producing a broken plan")
    func clampsConfiguration() {
        let wild = IntervalWorkout(
            prepareSeconds: -5, workSeconds: 0, restSeconds: -1, rounds: 0
        )
        let plan = IntervalPlan(workout: wild)
        #expect(plan.phases.isEmpty == false)
        #expect(plan.totalDuration > 0)
        #expect(plan.totalRounds >= 1)
    }
}

@Suite("Interval plan position math")
struct IntervalPlanPositionTests {

    /// prepare 10 | work 30 | rest 15 | work 30  (total 85)
    private let plan = IntervalPlan(
        workout: IntervalWorkout(prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 2)
    )

    @Test("At t=0 the workout sits at the start of the first phase")
    func atStart() {
        let position = plan.position(atElapsed: 0)
        #expect(position.phaseIndex == 0)
        #expect(position.phase?.kind == .prepare)
        #expect(position.remainingInPhase == 10)
        #expect(position.remainingTotal == 85)
        #expect(position.totalProgress == 0)
        #expect(position.isFinished == false)
    }

    @Test("A boundary belongs to the phase that is starting, not the one that ended")
    func boundaryBelongsToNextPhase() {
        let position = plan.position(atElapsed: 10)
        #expect(position.phaseIndex == 1)
        #expect(position.phase?.kind == .work)
        #expect(position.remainingInPhase == 30)
    }

    @Test("Mid-phase remaining time is exact")
    func midPhase() {
        let position = plan.position(atElapsed: 25)
        #expect(position.phase?.kind == .work)
        #expect(position.remainingInPhase == 15)
        #expect(position.remainingTotal == 60)
        #expect(abs(position.phaseProgress - 0.5) < 0.0001)
    }

    @Test("Jumping far ahead — the case that broke the old app — lands on the right phase")
    func largeJumpAfterSuspension() {
        // The app was suspended during prepare and resumed deep into the second work
        // interval. A decrementing counter would have lost every tick in between.
        let position = plan.position(atElapsed: 70)
        #expect(position.phaseIndex == 3)
        #expect(position.phase?.kind == .work)
        #expect(position.phase?.round == 2)
        #expect(position.remainingInPhase == 15)
    }

    @Test("At and past the end the workout reports finished")
    func finished() {
        #expect(plan.position(atElapsed: 85).isFinished)
        #expect(plan.position(atElapsed: 10_000).isFinished)
        #expect(plan.position(atElapsed: 85).remainingTotal == 0)
        #expect(plan.position(atElapsed: 85).totalProgress == 1)
    }

    @Test("Negative elapsed clamps to the start instead of underflowing")
    func negativeElapsed() {
        let position = plan.position(atElapsed: -30)
        #expect(position.phaseIndex == 0)
        #expect(position.remainingInPhase == 10)
    }

    @Test("Every whole second maps to the phase containing it")
    func exhaustiveSecondBySecond() {
        for second in 0..<Int(plan.totalDuration) {
            let position = plan.position(atElapsed: TimeInterval(second))
            guard let phase = position.phase else {
                Issue.record("expected a phase at t=\(second)")
                continue
            }
            #expect(phase.start <= TimeInterval(second))
            #expect(TimeInterval(second) < phase.end)
            // Remaining across the whole workout must decrease by exactly one each second.
            #expect(position.remainingTotal == plan.totalDuration - TimeInterval(second))
        }
    }

}

@Suite("Position lookup is exhaustively consistent")
struct IntervalPlanExhaustiveTests {

    /// A spread of shapes: no lead-in, no rest, single round, long tails, many short rounds.
    private static let shapes: [IntervalWorkout] = [
        IntervalWorkout(prepareSeconds: 0, workSeconds: 5, restSeconds: 0, rounds: 1),
        IntervalWorkout(prepareSeconds: 0, workSeconds: 5, restSeconds: 5, rounds: 12),
        IntervalWorkout(prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 8),
        IntervalWorkout(prepareSeconds: 60, workSeconds: 5, restSeconds: 90, rounds: 3),
        IntervalWorkout(prepareSeconds: 5, workSeconds: 120, restSeconds: 0, rounds: 6),
        IntervalWorkout(prepareSeconds: 0, workSeconds: 7, restSeconds: 3, rounds: 25),
        // Bookends: both, warmup alone with no lead-in, cooldown alone with no rest.
        IntervalWorkout(prepareSeconds: 10, warmupSeconds: 60, workSeconds: 20, restSeconds: 10, rounds: 4, cooldownSeconds: 90),
        IntervalWorkout(prepareSeconds: 0, warmupSeconds: 30, workSeconds: 5, restSeconds: 5, rounds: 3),
        IntervalWorkout(prepareSeconds: 5, workSeconds: 15, restSeconds: 0, rounds: 2, cooldownSeconds: 45),
        IntervalWorkout(prepareSeconds: 0, warmupSeconds: 30, workSeconds: 5, restSeconds: 0, rounds: 1, cooldownSeconds: 30),
    ]

    @Test("Every second of every shape resolves to the phase that contains it", arguments: shapes)
    func everySecondResolvesCorrectly(workout: IntervalWorkout) {
        let plan = IntervalPlan(workout: workout)

        for second in 0..<Int(plan.totalDuration) {
            let t = TimeInterval(second)
            let position = plan.position(atElapsed: t)

            guard let phase = position.phase, let index = position.phaseIndex else {
                Issue.record("no phase at t=\(second) for \(workout.name)")
                continue
            }
            // The binary search must agree with a plain linear scan.
            let expected = plan.phases.firstIndex { $0.start <= t && t < $0.end }
            #expect(index == expected)
            #expect(phase.start <= t && t < phase.end)
            #expect(position.remainingTotal == plan.totalDuration - t)
            #expect(position.remainingInPhase == phase.end - t)
        }

        // Half-second offsets exercise the non-integer path too.
        for half in 0..<Int(plan.totalDuration * 2) {
            let t = TimeInterval(half) / 2
            let position = plan.position(atElapsed: t)
            let expected = plan.phases.firstIndex { $0.start <= t && t < $0.end }
            #expect(position.phaseIndex == expected)
        }

        #expect(plan.position(atElapsed: plan.totalDuration).isFinished)
    }
}

@Suite("Warmup and cooldown in the plan")
struct IntervalPlanBookendTests {

    @Test("Order is lead-in, warmup, the rounds, then the cooldown")
    func order() {
        let plan = IntervalPlan(workout: IntervalWorkout(
            prepareSeconds: 10, warmupSeconds: 60, workSeconds: 30, restSeconds: 15, rounds: 3, cooldownSeconds: 90
        ))
        #expect(plan.phases.map(\.kind) == [.prepare, .warmup, .work, .rest, .work, .rest, .work, .cooldown])
        #expect(plan.phases.map(\.id) == Array(0..<8))
        #expect(plan.phases.map(\.start) == [0, 10, 70, 100, 115, 145, 160, 190])
        #expect(plan.totalDuration == 280)
    }

    @Test("With both bookends off the plan is exactly what it was before they existed")
    func zeroBookendsChangeNothing() {
        let plan = IntervalPlan(workout: IntervalWorkout(
            prepareSeconds: 10, warmupSeconds: 0, workSeconds: 30, restSeconds: 15, rounds: 3, cooldownSeconds: 0
        ))
        let expected: [IntervalPhase] = [
            IntervalPhase(id: 0, kind: .prepare, duration: 10, round: 1, start: 0),
            IntervalPhase(id: 1, kind: .work, duration: 30, round: 1, start: 10),
            IntervalPhase(id: 2, kind: .rest, duration: 15, round: 1, start: 40),
            IntervalPhase(id: 3, kind: .work, duration: 30, round: 2, start: 55),
            IntervalPhase(id: 4, kind: .rest, duration: 15, round: 2, start: 85),
            IntervalPhase(id: 5, kind: .work, duration: 30, round: 3, start: 100),
        ]
        #expect(plan.phases == expected)
        #expect(plan.totalDuration == 130)
    }

    @Test("The cooldown follows the last work interval directly, with no rest between")
    func noRestBeforeCooldown() throws {
        let plan = IntervalPlan(workout: IntervalWorkout(
            prepareSeconds: 0, workSeconds: 20, restSeconds: 10, rounds: 2, cooldownSeconds: 60
        ))
        let cooldown = try #require(plan.phases.last)
        let lastWork = plan.phases[plan.phases.count - 2]
        #expect(cooldown.kind == .cooldown)
        #expect(lastWork.kind == .work)
        #expect(cooldown.start == lastWork.end)
        #expect(cooldown.end == plan.totalDuration)
    }

    @Test("A one-round workout is lead-in, warmup, work, cooldown")
    func singleRound() {
        let plan = IntervalPlan(workout: IntervalWorkout(
            prepareSeconds: 10, warmupSeconds: 60, workSeconds: 45, restSeconds: 20, rounds: 1, cooldownSeconds: 60
        ))
        #expect(plan.phases.map(\.kind) == [.prepare, .warmup, .work, .cooldown])
        #expect(plan.totalDuration == 175)
    }

    @Test("The warmup reports round 1 and the cooldown the last; neither adds a round")
    func rounds() throws {
        let plan = IntervalPlan(workout: IntervalWorkout(
            prepareSeconds: 10, warmupSeconds: 60, workSeconds: 30, restSeconds: 15, rounds: 5, cooldownSeconds: 90
        ))
        let warmup = try #require(plan.phases.first { $0.kind == .warmup })
        let cooldown = try #require(plan.phases.first { $0.kind == .cooldown })
        #expect(warmup.round == 1)
        #expect(cooldown.round == 5)
        #expect(plan.totalRounds == 5)
        #expect(plan.phases.filter { $0.kind == .work }.map(\.round) == [1, 2, 3, 4, 5])
    }

    @Test("Without a lead-in the warmup opens the workout at zero")
    func warmupFirstWithoutPrepare() throws {
        let plan = IntervalPlan(workout: IntervalWorkout(
            prepareSeconds: 0, warmupSeconds: 120, workSeconds: 30, restSeconds: 15, rounds: 2
        ))
        let first = try #require(plan.phases.first)
        #expect(first.kind == .warmup)
        #expect(first.start == 0)
        #expect(first.id == 0)
        #expect(plan.position(atElapsed: 0).phase?.kind == .warmup)
    }
}

@Suite("Phase kind vocabulary")
struct PhaseKindTests {

    private static let all: [IntervalPhase.Kind] = [.prepare, .warmup, .work, .rest, .cooldown]

    @Test("Only the warmup and cooldown are bookends")
    func bookends() {
        #expect(Self.all.filter(\.isBookend) == [.warmup, .cooldown])
    }

    @Test("Raw values are fixed: Health metadata stores them")
    func rawValues() {
        #expect(Self.all.map(\.rawValue) == ["prepare", "warmup", "work", "rest", "cooldown"])
    }

    @Test("Each kind has its own name, ring word and glyph")
    func words() {
        #expect(Self.all.map(\.title) == ["Get Ready", "Warmup", "Work", "Rest", "Cooldown"])
        #expect(Self.all.map(\.shortTitle) == ["Ready", "Warmup", "Work", "Rest", "Cooldown"])
        #expect(IntervalPhase.Kind.warmup.symbolName == "sunrise.fill")
        #expect(IntervalPhase.Kind.cooldown.symbolName == "sunset.fill")
        #expect(Set(Self.all.map(\.symbolName)).count == Self.all.count)
    }

    @Test("Each kind has its own colour, and its dimmed colour differs from it")
    func colours() {
        let light = Self.all.map(Theme.light(for:))
        let dimmed = Self.all.map(Theme.dimmed(for:))
        for (index, colour) in light.enumerated() {
            #expect(light.filter { $0 == colour }.count == 1, "\(Self.all[index]) shares a colour")
            #expect(dimmed[index] != colour)
        }
        #expect(Theme.light(for: .warmup) == Theme.warmup)
        #expect(Theme.light(for: .cooldown) == Theme.cooldown)
    }
}
