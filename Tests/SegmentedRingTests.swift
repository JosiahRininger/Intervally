//
//  SegmentedRingTests.swift
//  IntervallyTests
//

import Testing
import CoreGraphics
import SwiftUI
@testable import Intervally

/// The setup ring's arc layout: proportional, but never so thin that a phase disappears.
@Suite("Segmented ring layout")
struct SegmentedRingTests {

    /// Circumference of the setup ring on a 40mm watch (D ≈ 102, stroke ≈ 8).
    private let small: CGFloat = 2 * .pi * (102 - 8) / 2
    private let gap: CGFloat = 2
    private let minArc: CGFloat = 4

    private func fractions(for workout: IntervalWorkout) -> [Double] {
        SegmentedRing.segments(for: IntervalPlan(workout: workout)).map(\.fraction)
    }

    @Test("A 5-second rest between 2-minute work intervals stays visible")
    func shortRestIsVisible() throws {
        let workout = IntervalWorkout(prepareSeconds: 10, workSeconds: 120, restSeconds: 5, rounds: 20)
        let arcs = try #require(SegmentedRing.layout(fractions: fractions(for: workout), circumference: small, gap: gap, minArc: minArc))
        // Proportionally a rest would be ~0.4pt — invisible next to the 2pt gaps.
        #expect(arcs.allSatisfy { $0.length >= minArc - 0.0001 })
    }

    @Test("Arcs and gaps exactly fill the circle")
    func fillsCircle() throws {
        let workout = IntervalWorkout(prepareSeconds: 10, workSeconds: 65, restSeconds: 15, rounds: 20)
        let f = fractions(for: workout)
        let arcs = try #require(SegmentedRing.layout(fractions: f, circumference: small, gap: gap, minArc: minArc))
        let total = arcs.reduce(0) { $0 + $1.length } + CGFloat(arcs.count) * gap
        #expect(abs(total - small) < 0.001)
    }

    @Test("Arcs run in order without overlapping, seam at twelve o'clock")
    func ordered() throws {
        let arcs = try #require(SegmentedRing.layout(fractions: [0.1, 0.4, 0.1, 0.4], circumference: 300, gap: gap, minArc: minArc))
        #expect(abs(arcs[0].start - gap / 2) < 0.001)
        for (a, b) in zip(arcs, arcs.dropFirst()) {
            #expect(abs(b.start - (a.start + a.length + gap)) < 0.001)
        }
        let last = try #require(arcs.last)
        #expect(abs(last.start + last.length + gap / 2 - 300) < 0.001)
    }

    @Test("Unpinned arcs keep their proportions to each other")
    func proportionsKept() throws {
        // One tiny phase gets pinned; the two big ones still split the rest 1:3.
        let arcs = try #require(SegmentedRing.layout(fractions: [0.001, 0.25, 0.749], circumference: 300, gap: gap, minArc: minArc))
        #expect(abs(arcs[0].length - minArc) < 0.001)
        #expect(abs(arcs[2].length / arcs[1].length - 0.749 / 0.25) < 0.001)
    }

    @Test("Too many phases for the floor returns nil so the ring can group them")
    func overflowReturnsNil() {
        let workout = IntervalWorkout(prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 99)
        #expect(SegmentedRing.layout(fractions: fractions(for: workout), circumference: small, gap: gap, minArc: minArc) == nil)
    }

    @Test("A single phase is one full ring with no gap")
    func singlePhase() throws {
        let arcs = try #require(SegmentedRing.layout(fractions: [1], circumference: 200, gap: gap, minArc: minArc))
        #expect(arcs == [SegmentedRing.Arc(start: 0, length: 200)])
    }

    @Test("Grouped segments are one arc per kind, in first-appearance order, summing to 1")
    func grouped() {
        let plan = IntervalPlan(workout: IntervalWorkout(prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 99))
        let grouped = SegmentedRing.groupedSegments(for: plan)
        #expect(grouped.count == 3)
        #expect(abs(grouped.reduce(0) { $0 + $1.fraction } - 1) < 0.000_001)
        // Lead-in first, then work, then rest.
        #expect(grouped[0].fraction < grouped[2].fraction)
        #expect(grouped[1].fraction > grouped[2].fraction)
    }

    @Test("No rest phase: the grouped form has only lead-in and work")
    func groupedWithoutRest() {
        let plan = IntervalPlan(workout: IntervalWorkout(prepareSeconds: 10, workSeconds: 60, restSeconds: 0, rounds: 50))
        #expect(SegmentedRing.groupedSegments(for: plan).count == 2)
    }

    @Test("Each round is one block: rest attaches to its work, gaps fall between rounds")
    func roundBlocks() throws {
        let plan = IntervalPlan(workout: IntervalWorkout(prepareSeconds: 10, workSeconds: 120, restSeconds: 5, rounds: 3))
        let segments = SegmentedRing.segments(for: plan)
        // prepare | work rest | work rest | work
        #expect(segments.map(\.breakAfter) == [true, false, true, false, true, true])
        let arcs = try #require(SegmentedRing.layout(
            fractions: segments.map(\.fraction), breaks: segments.map(\.breakAfter),
            circumference: small, gap: gap, minArc: minArc
        ))
        // Work 1 ends exactly where its rest begins.
        #expect(abs(arcs[1].start + arcs[1].length - arcs[2].start) < 0.001)
        // A gap separates that rest from the next round's work.
        #expect(abs(arcs[3].start - (arcs[2].start + arcs[2].length + gap)) < 0.001)
        // And everything still fills the circle: 4 gaps (lead-in, two rounds, seam).
        let total = arcs.reduce(0) { $0 + $1.length } + 4 * gap
        #expect(abs(total - small) < 0.001)
    }

    @Test("Without rest every work interval is its own block")
    func noRestBlocks() {
        let plan = IntervalPlan(workout: IntervalWorkout(prepareSeconds: 0, workSeconds: 60, restSeconds: 0, rounds: 3))
        #expect(SegmentedRing.segments(for: plan).map(\.breakAfter) == [true, true, true])
    }
}

/// The warmup and cooldown on the setup ring: capped so they never swamp the rounds, and
/// left out of the count that decides when the ring groups.
@Suite("Segmented ring — warmup and cooldown")
struct SegmentedRingBookendTests {

    private func plan(
        prepare: Int = 10, warmup: Int, work: Int = 30, rest: Int = 15, rounds: Int = 8, cooldown: Int
    ) -> IntervalPlan {
        IntervalPlan(workout: IntervalWorkout(
            prepareSeconds: prepare, warmupSeconds: warmup, workSeconds: work,
            restSeconds: rest, rounds: rounds, cooldownSeconds: cooldown
        ))
    }

    @Test("Each bookend is its own block, with a gap either side")
    func bookendBreaks() {
        let segments = SegmentedRing.segments(for: plan(warmup: 60, work: 120, rest: 5, rounds: 2, cooldown: 60))
        // prepare | warmup | work rest | work | cooldown
        #expect(segments.map(\.breakAfter) == [true, true, false, true, true, true])
        #expect(segments.map(\.isBookend) == [false, true, false, false, false, true])
        #expect(segments[1].color == Theme.warmup)
        #expect(segments[5].color == Theme.cooldown)
    }

    @Test("Grouped, the kinds run lead-in, warmup, work, rest, cooldown")
    func groupedOrder() {
        let grouped = SegmentedRing.groupedSegments(for: plan(warmup: 60, rounds: 99, cooldown: 60))
        #expect(grouped.map(\.color) == [Theme.prepare, Theme.warmup, Theme.work, Theme.rest, Theme.cooldown])
        #expect(grouped.map(\.isBookend) == [false, true, false, false, true])
        #expect(abs(grouped.reduce(0) { $0 + $1.fraction } - 1) < 0.000_001)
    }

    @Test("Long bookends are drawn at the cap, and the shares still sum to 1")
    func longBookendsAreCapped() throws {
        // 30 minutes either side of under five minutes of intervals.
        let long = plan(warmup: 1800, cooldown: 1800)
        let fractions = SegmentedRing.displayFractions(for: long)
        let kinds = long.phases.map(\.kind)
        #expect(fractions.count == long.phases.count)
        #expect(abs(fractions.reduce(0, +) - 1) < 0.000_001)
        for (kind, fraction) in zip(kinds, fractions) where kind.isBookend {
            #expect(abs(fraction - SegmentedRing.bookendCap) < 0.000_001)
        }
        // What the bookends gave up goes back to the rounds in proportion: a work interval
        // is still twice its 15-second rest.
        let work = fractions[try #require(kinds.firstIndex(of: .work))]
        let rest = fractions[try #require(kinds.firstIndex(of: .rest))]
        #expect(abs(work / rest - 2) < 0.000_001)
        // The grouped form caps them the same way.
        let grouped = SegmentedRing.groupedSegments(for: long)
        #expect(grouped.filter(\.isBookend).allSatisfy { abs($0.fraction - SegmentedRing.bookendCap) < 0.000_001 })
    }

    @Test("Bookends under the cap keep their true share, so nothing else moves")
    func shortBookendsAreExact() {
        let short = plan(warmup: 30, cooldown: 45)
        let fractions = SegmentedRing.displayFractions(for: short)
        let actual = short.phases.map { $0.duration / short.totalDuration }
        #expect(zip(fractions, actual).allSatisfy { abs($0 - $1) < 0.000_001 })
        #expect(fractions[1] < SegmentedRing.bookendCap)
        #expect(SegmentedRing.segments(for: short).map(\.fraction) == fractions)
    }

    @Test("Without bookends the ring is drawn exactly as before")
    func noBookendsUnchanged() {
        let plain = plan(warmup: 0, cooldown: 0)
        let fractions = SegmentedRing.displayFractions(for: plain)
        #expect(fractions == plain.phases.map { $0.duration / plain.totalDuration })
        #expect(SegmentedRing.segments(for: plain).allSatisfy { !$0.isBookend })
    }

    @Test("Thirty rounds with rest and both bookends still draws every round")
    func thirtyRoundsStayDetailed() {
        // 60 interval-side arcs plus two bookends: 62 in all, over the 61 a ring shows
        // detailed, but only the rounds count toward it.
        let thirty = plan(warmup: 300, work: 30, rest: 15, rounds: 30, cooldown: 300)
        let segments = SegmentedRing.segments(for: thirty)
        #expect(segments.count == 62)
        #expect(segments.filter { !$0.isBookend }.count == 60)

        // The 46mm setup ring: ~140pt across at an 8% stroke.
        let lineWidth: CGFloat = 140 * 0.08
        let circumference = 2 * .pi * (140 - lineWidth) / 2
        let (shown, arcs) = SegmentedRing.resolve(
            segments: segments, grouped: SegmentedRing.groupedSegments(for: thirty),
            circumference: circumference, gap: 2, minArc: lineWidth * 0.3
        )
        #expect(shown == segments)
        #expect(arcs.count == 62)
    }

    @Test("The detailed limit counts only non-bookend arcs: 61 stay, 62 group")
    func limitCountsRoundsOnly() {
        let roomy: CGFloat = 4000
        // No lead-in: 31 work + 30 rest = 61, plus two bookends.
        let atLimit = plan(prepare: 0, warmup: 60, rounds: 31, cooldown: 60)
        let atLimitSegments = SegmentedRing.segments(for: atLimit)
        #expect(atLimitSegments.filter { !$0.isBookend }.count == SegmentedRing.maxDetailedSegments)
        let (kept, _) = SegmentedRing.resolve(
            segments: atLimitSegments, grouped: SegmentedRing.groupedSegments(for: atLimit),
            circumference: roomy, gap: 2, minArc: 3
        )
        #expect(kept == atLimitSegments)

        // A lead-in makes 62 interval-side arcs: grouped, bookends or not.
        let over = plan(prepare: 10, warmup: 60, rounds: 31, cooldown: 60)
        let grouped = SegmentedRing.groupedSegments(for: over)
        let (shown, _) = SegmentedRing.resolve(
            segments: SegmentedRing.segments(for: over), grouped: grouped,
            circumference: roomy, gap: 2, minArc: 3
        )
        #expect(shown == grouped)
    }
}
