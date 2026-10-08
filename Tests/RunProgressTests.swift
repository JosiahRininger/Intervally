//
//  RunProgressTests.swift
//  IntervallyTests
//

import Testing
import Foundation
@testable import Intervally

@Suite("Complication timeline derivation")
struct RunProgressTests {

    /// prepare 10 | work 30 (10-40) | rest 15 (40-55) | work 30 (55-85)
    private let workout = IntervalWorkout(
        prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 2
    )
    private let anchor = Date(timeIntervalSinceReferenceDate: 500_000)

    private func snapshot(paused: TimeInterval? = nil) -> RunSnapshot {
        RunSnapshot(workout: workout, anchor: anchor, pausedElapsed: paused)
    }

    @Test("Progress reports the phase, the round, and an absolute phase end")
    func progressMidRun() {
        let progress = snapshot().progress(at: anchor.addingTimeInterval(20))
        #expect(progress?.phaseKind == .work)
        #expect(progress?.round == 1)
        #expect(progress?.totalRounds == 2)
        // The end is an instant, not a duration, so the system can count down to it without
        // ever waking the widget.
        #expect(progress?.phaseEnd == anchor.addingTimeInterval(40))
        #expect(progress?.isPaused == false)
    }

    @Test("Once the run is over there is no progress to show")
    func progressAfterEnd() {
        #expect(snapshot().progress(at: anchor.addingTimeInterval(85)) == nil)
        #expect(snapshot().progress(at: anchor.addingTimeInterval(10_000)) == nil)
    }

    @Test("A paused snapshot is frozen wherever it was paused, however long ago")
    func pausedProgressIsFrozen() {
        let paused = snapshot(paused: 20)
        let soon = paused.progress(at: anchor.addingTimeInterval(25))
        let muchLater = paused.progress(at: anchor.addingTimeInterval(10_000))

        #expect(soon == muchLater)
        #expect(soon?.phaseKind == .work)
        #expect(soon?.isPaused == true)
    }

    @Test("Boundaries are every phase start still ahead, then the finish")
    func upcomingBoundaries() {
        let boundaries = snapshot().upcomingBoundaries(after: anchor)
        #expect(boundaries == [10, 40, 55, 85].map(anchor.addingTimeInterval))
    }

    @Test("Boundaries already passed are not offered again")
    func boundariesSkipThePast() {
        let boundaries = snapshot().upcomingBoundaries(after: anchor.addingTimeInterval(42))
        #expect(boundaries == [55, 85].map(anchor.addingTimeInterval))
    }

    @Test("A paused run publishes no boundaries, because nothing is moving")
    func pausedHasNoBoundaries() {
        #expect(snapshot(paused: 20).upcomingBoundaries(after: anchor).isEmpty)
    }

    @Test("The boundary list is capped so a long workout cannot flood the timeline")
    func boundariesAreCapped() {
        let long = RunSnapshot(
            workout: IntervalWorkout(prepareSeconds: 0, workSeconds: 5, restSeconds: 5, rounds: 99),
            anchor: anchor,
            pausedElapsed: nil
        )
        #expect(long.upcomingBoundaries(after: anchor, limit: 40).count == 40)
    }

    @Test("Every published boundary resolves to a real entry, never an empty one")
    func boundariesYieldRenderableEntries() {
        // The complication used to blank out at the first boundary because the follow-up
        // entry was hardcoded to nil, so it read "no workout running" mid-workout.
        let snapshot = self.snapshot()
        let boundaries = snapshot.upcomingBoundaries(after: anchor)
        for boundary in boundaries.dropLast() {
            #expect(snapshot.progress(at: boundary) != nil)
        }
        // The last one is the finish, where clearing is correct.
        #expect(snapshot.progress(at: boundaries.last!) == nil)
    }

    @Test("A phase end is never behind the entry that renders it")
    func phaseEndNeverPrecedesItsEntry() {
        // Building Text(timerInterval: now...phaseEnd) traps when the range is inverted.
        let snapshot = self.snapshot()
        for second in 0..<85 {
            let date = anchor.addingTimeInterval(TimeInterval(second))
            guard let progress = snapshot.progress(at: date) else { continue }
            #expect(progress.phaseEnd > date)
        }
    }
}

@Suite("Complication wording, warmup and cooldown included")
struct RunProgressWordingTests {

    private func progress(_ kind: IntervalPhase.Kind, round: Int, of total: Int = 8) -> RunProgress {
        RunProgress(phaseKind: kind, phaseEnd: .distantFuture, round: round, totalRounds: total, isPaused: false)
    }

    @Test("Interval phases name their round; bookends name only themselves")
    func phaseLines() {
        #expect(progress(.prepare, round: 1).phaseLine == "GET READY · 1 of 8")
        #expect(progress(.warmup, round: 1).phaseLine == "WARMUP")
        #expect(progress(.work, round: 3).phaseLine == "WORK · 3 of 8")
        #expect(progress(.rest, round: 3).phaseLine == "REST · 3 of 8")
        #expect(progress(.cooldown, round: 8).phaseLine == "COOLDOWN")
    }

    @Test("The inline form is as short, and bookends carry no round there either")
    func compactLines() {
        #expect(progress(.prepare, round: 1).compactLine == "Get Ready 1/8")
        #expect(progress(.warmup, round: 1).compactLine == "Warmup")
        #expect(progress(.work, round: 3).compactLine == "Work 3/8")
        #expect(progress(.rest, round: 3).compactLine == "Rest 3/8")
        #expect(progress(.cooldown, round: 8).compactLine == "Cooldown")
    }

    /// warmup 60 | work 30 (60-90) | rest 15 (90-105) | work 30 (105-135) | cooldown 120 (135-255)
    private let snapshot = RunSnapshot(
        workout: IntervalWorkout(
            prepareSeconds: 0, warmupSeconds: 60, workSeconds: 30, restSeconds: 15, rounds: 2, cooldownSeconds: 120
        ),
        anchor: Date(timeIntervalSinceReferenceDate: 500_000),
        pausedElapsed: nil
    )

    @Test("The cooldown's start is a boundary, and the finish comes after it")
    func cooldownBoundary() throws {
        let anchor = snapshot.anchor
        #expect(snapshot.upcomingBoundaries(after: anchor) == [60, 90, 105, 135, 255].map(anchor.addingTimeInterval))

        let atCooldown = try #require(snapshot.progress(at: anchor.addingTimeInterval(135)))
        #expect(atCooldown.phaseKind == .cooldown)
        #expect(atCooldown.round == 2)
        #expect(atCooldown.totalRounds == 2)
        #expect(atCooldown.phaseEnd == anchor.addingTimeInterval(255))
        #expect(atCooldown.phaseLine == "COOLDOWN")
    }

    @Test("A run opening on its warmup reports it as round 1 of the intervals to come")
    func warmupProgress() throws {
        let progress = try #require(snapshot.progress(at: snapshot.anchor.addingTimeInterval(20)))
        #expect(progress.phaseKind == .warmup)
        #expect(progress.round == 1)
        #expect(progress.phaseEnd == snapshot.anchor.addingTimeInterval(60))
        #expect(progress.phaseLine == "WARMUP")
    }
}
