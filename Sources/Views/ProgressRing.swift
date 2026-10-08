//
//  ProgressRing.swift
//  Intervally
//

import SwiftUI

/// A single ring that **depletes**: the arc shows time remaining and retreats toward
/// twelve o'clock as the phase runs down — the timer idiom, not the goal-filling one.
///
/// Pure overlay. Callers compose whatever belongs inside it in a `ZStack`; the ring makes
/// no claim on its interior. Flat colour, round caps, no gradient, no marker, no shadow —
/// the earlier angular dark-to-light gradient at a ~10.7% stroke was the most
/// Activity-like thing in the app, and it is gone.
///
/// Sized from its container so it fills a 40mm SE and a 49mm Ultra alike.
struct ProgressRing: View {
    /// 0...1 — how much of the arc is shown. Pass the *remaining* fraction of a countdown.
    var fraction: Double
    var color: Color
    var track: Color
    /// Always-On: flat dimmed colour, fainter track, no animation.
    var isDimmed: Bool = false
    /// Stroke as a fraction of the outer diameter.
    var strokeRatio: CGFloat = 0.08
    /// Set false under Reduce Motion.
    var animated: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let lineWidth = max(7, side * strokeRatio)

            ZStack {
                Circle()
                    .stroke(track.opacity(isDimmed ? 0.5 : 1), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.0001, min(1, fraction)))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            // A stroke straddles its path; inset by half the width so it stays in bounds.
            .frame(width: side - lineWidth, height: side - lineWidth)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(animated && !isDimmed ? .easeInOut(duration: 0.3) : nil, value: color)
        }
        .accessibilityHidden(true)
    }

    /// Stroke width for a ring of outer diameter `diameter`, so callers can size an interior.
    nonisolated static func strokeWidth(for diameter: CGFloat, ratio: CGFloat = 0.08) -> CGFloat {
        max(7, diameter * ratio)
    }
}

/// The shape of a whole workout as one ring: a lead-in arc, a warmup, then alternating work
/// and rest arcs in proportion to their seconds, then a cooldown. One multicolour timeline —
/// not concentric rings, and carrying no Move / Exercise / Stand meaning.
///
/// Each round is drawn as one block — its work arc with its rest arc attached — and gaps
/// fall only between rounds, which halves the gaps a dense workout spends its ring on.
/// Proportional, with a floor: every arc gets at least `minArc` points (~30% of the stroke
/// width), so a 5-second rest after a 2-minute work interval still shows as a green tick
/// at the end of its block instead of vanishing. When even the floor can't fit — dozens of
/// rounds on a small ring — it draws the workout grouped: lead-in, warmup, all work, all
/// rest, cooldown.
///
/// The warmup and cooldown are each drawn at no more than `bookendCap` of the ring. A
/// 30-minute warmup before ten minutes of intervals would otherwise leave the intervals a
/// sliver; the ring is the workout's shape, and the hero total beneath it stays exact.
struct SegmentedRing: View {
    struct Segment: Identifiable, Equatable {
        let id: Int
        let color: Color
        let fraction: Double
        /// Whether a gap follows this arc. The last arc's gap is the seam at twelve o'clock.
        var breakAfter: Bool = true
        /// A warmup or cooldown. Not counted against `maxDetailedSegments`.
        var isBookend: Bool = false
    }

    /// One arc's placement, in points of arc length clockwise from twelve o'clock.
    struct Arc: Equatable {
        let start: CGFloat
        let length: CGFloat
    }

    var segments: [Segment]
    /// Drawn instead when `segments` can't all fit at the minimum arc length.
    var grouped: [Segment]? = nil
    var strokeRatio: CGFloat = 0.06
    /// Gap between arcs, in points of arc length.
    var gap: CGFloat = 2

    init(segments: [Segment], grouped: [Segment]? = nil, strokeRatio: CGFloat = 0.06, gap: CGFloat = 2) {
        self.segments = segments
        self.grouped = grouped
        self.strokeRatio = strokeRatio
        self.gap = gap
    }

    /// The workout's every phase, falling back to the grouped form when the ring is too
    /// small (or the workout too long) for each phase to be seen.
    init(plan: IntervalPlan, strokeRatio: CGFloat = 0.06, gap: CGFloat = 2) {
        self.init(
            segments: Self.segments(for: plan),
            grouped: Self.groupedSegments(for: plan),
            strokeRatio: strokeRatio,
            gap: gap
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let lineWidth = max(3, side * strokeRatio)
            let radius = (side - lineWidth) / 2
            let circumference = 2 * .pi * radius
            let minArc = max(1.5, lineWidth * 0.3)
            let (shown, arcs) = resolve(circumference: circumference, minArc: minArc)

            ZStack {
                ForEach(Array(zip(shown, arcs).enumerated()), id: \.offset) { _, pair in
                    let (segment, arc) = pair
                    Circle()
                        .trim(from: arc.start / circumference, to: (arc.start + arc.length) / circumference)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: side - lineWidth, height: side - lineWidth)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }

    private func resolve(circumference: CGFloat, minArc: CGFloat) -> ([Segment], [Arc]) {
        Self.resolve(segments: segments, grouped: grouped, circumference: circumference, gap: gap, minArc: minArc)
    }

    /// The detailed segments if every one can be seen, else the grouped ones.
    nonisolated static func resolve(
        segments: [Segment], grouped: [Segment]?, circumference: CGFloat, gap: CGFloat, minArc: CGFloat
    ) -> ([Segment], [Arc]) {
        // Only the rounds make a ring read as a dashed line. Counting the bookends as well
        // would tip a 30-round workout into the grouped form just for adding a warmup.
        if segments.filter({ !$0.isBookend }).count <= maxDetailedSegments,
           let arcs = layout(
               fractions: segments.map(\.fraction), breaks: segments.map(\.breakAfter),
               circumference: circumference, gap: gap, minArc: minArc
           ) {
            return (segments, arcs)
        }
        let fallback = grouped ?? segments
        let arcs = layout(
            fractions: fallback.map(\.fraction), breaks: fallback.map(\.breakAfter),
            circumference: circumference, gap: gap, minArc: minArc
        )
            ?? layout(fractions: fallback.map(\.fraction), circumference: circumference, gap: 0, minArc: 0)
            ?? []
        return (fallback, arcs)
    }

    /// Past ~30 rounds a per-phase ring reads as a dashed line rather than a rhythm.
    nonisolated static let maxDetailedSegments = 61

    /// The most of the ring a warmup or a cooldown is drawn with.
    nonisolated static let bookendCap = 0.15

    /// Every arc followed by a gap.
    nonisolated static func layout(fractions: [Double], circumference: CGFloat, gap: CGFloat, minArc: CGFloat) -> [Arc]? {
        layout(
            fractions: fractions, breaks: Array(repeating: true, count: fractions.count),
            circumference: circumference, gap: gap, minArc: minArc
        )
    }

    /// Places arcs around a circle of `circumference` points, each proportional to its
    /// fraction but never shorter than `minArc`, with a `gap` after every arc whose `breaks`
    /// entry is true. Arcs that would fall under the floor are pinned to it and the rest
    /// share what is left, repeated until stable (a pinned arc can push another under the
    /// floor). Returns nil when the floor can't be met for every arc.
    nonisolated static func layout(
        fractions: [Double], breaks: [Bool], circumference: CGFloat, gap: CGFloat, minArc: CGFloat
    ) -> [Arc]? {
        let count = fractions.count
        guard count > 0, circumference > 0 else { return count == 0 ? [] : nil }
        // One arc is a closed ring: no seam, no gap.
        let gapAfter: [CGFloat] = count > 1
            ? fractions.indices.map { index in (index < breaks.count ? breaks[index] : true) ? gap : 0 }
            : [0]
        let gapTotal = gapAfter.reduce(0, +)
        let available = circumference - gapTotal
        guard available > 0, available >= CGFloat(count) * minArc else { return nil }

        var pinned = [Bool](repeating: false, count: count)
        var lengths = [CGFloat](repeating: 0, count: count)
        while true {
            let pinnedCount = pinned.filter { $0 }.count
            let freeLength = available - CGFloat(pinnedCount) * minArc
            let freeFraction = fractions.indices.filter { !pinned[$0] }.reduce(0.0) { $0 + max(0, fractions[$1]) }
            let freeCount = count - pinnedCount
            var changed = false
            for index in fractions.indices where !pinned[index] {
                let share = freeFraction > 0
                    ? freeLength * CGFloat(max(0, fractions[index]) / freeFraction)
                    : freeLength / CGFloat(max(1, freeCount))
                if share < minArc {
                    pinned[index] = true
                    changed = true
                } else {
                    lengths[index] = share
                }
            }
            if !changed { break }
        }
        for index in fractions.indices where pinned[index] { lengths[index] = minArc }

        // Half the seam's gap either side of twelve o'clock, so the seam between the last
        // arc and the first sits exactly at the top.
        let seam = gapAfter[count - 1]
        var cursor = seam / 2
        return lengths.indices.map { index in
            defer { cursor += lengths[index] + gapAfter[index] }
            return Arc(start: cursor, length: lengths[index])
        }
    }

    /// Each phase's share of the ring, in plan order, summing to 1. A bookend keeps its
    /// true share up to `bookendCap`; whatever the bookends give up goes back to the other
    /// phases in proportion to their seconds, so the rounds keep their rhythm.
    nonisolated static func displayFractions(for plan: IntervalPlan, bookendCap: Double = SegmentedRing.bookendCap) -> [Double] {
        let phases = plan.phases
        let total = plan.totalDuration
        guard total > 0 else { return phases.map { _ in 0 } }
        let actual = phases.map { $0.duration / total }
        let bookendShare = phases.indices
            .filter { phases[$0].kind.isBookend }
            .reduce(0.0) { $0 + min(actual[$1], bookendCap) }
        let otherSeconds = phases.filter { !$0.kind.isBookend }.reduce(0.0) { $0 + $1.duration }
        // A plan always has at least one work interval; this only guards the arithmetic.
        guard otherSeconds > 0 else { return actual }
        let otherShare = 1 - bookendShare
        return phases.indices.map { index in
            phases[index].kind.isBookend
                ? min(actual[index], bookendCap)
                : otherShare * phases[index].duration / otherSeconds
        }
    }

    /// Builds the segments for a plan: one per phase, in order, with a gap only where the
    /// next phase starts a new block — the lead-in, the warmup, each round (work plus its
    /// rest), then the cooldown.
    nonisolated static func segments(for plan: IntervalPlan) -> [Segment] {
        let phases = plan.phases
        let fractions = displayFractions(for: plan)
        return phases.indices.map { index in
            let phase = phases[index]
            let next = index + 1 < phases.count ? phases[index + 1] : nil
            return Segment(
                id: phase.id,
                color: Theme.light(for: phase.kind),
                fraction: fractions[index],
                breakAfter: next.map { $0.kind != .rest } ?? true,
                isBookend: phase.kind.isBookend
            )
        }
    }

    /// The same plan as one arc per phase kind, in the order the kinds first appear, with
    /// the bookends capped as in the detailed form.
    nonisolated static func groupedSegments(for plan: IntervalPlan) -> [Segment] {
        let fractions = displayFractions(for: plan)
        var order: [IntervalPhase.Kind] = []
        var shares: [IntervalPhase.Kind: Double] = [:]
        for (phase, fraction) in zip(plan.phases, fractions) {
            if shares[phase.kind] == nil { order.append(phase.kind) }
            shares[phase.kind, default: 0] += fraction
        }
        return order.enumerated().map { index, kind in
            Segment(
                id: index,
                color: Theme.light(for: kind),
                fraction: shares[kind] ?? 0,
                isBookend: kind.isBookend
            )
        }
    }
}

#Preview("Depleting") {
    ProgressRing(fraction: 0.65, color: Theme.work, track: Theme.track(for: .work)).padding()
}

#Preview("Structure") {
    SegmentedRing(plan: IntervalPlan(workout: .default)).padding()
}
