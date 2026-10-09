//
//  UpNextCard.swift
//  IntervallyPhone
//

import SwiftUI

/// The preset the watch starts next: the hero of the Workouts screen, drawn like the watch's
/// own dial, with the total inside its ring.
struct UpNextCard: View {
    let content: PresetCardContent
    /// "Up next on your watch", or just "Up next" with no watch to speak of.
    let title: String
    /// The watch's glyph beside the title, only where there is a watch.
    var showsWatch = true

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var ringSide: CGFloat = 104

    var body: some View {
        let ring = ringWithTotal

        Group {
            switch CardArrangement(typeSize: typeSize) {
            case .row:
                HStack(spacing: 18) {
                    ring
                    words
                    Spacer(minLength: 0)
                }
            case .stacked:
                VStack(alignment: .leading, spacing: 14) {
                    ring
                    words
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileBackground()
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(content.spokenSummary)")
    }

    /// Capped, so the largest text sizes grow the words rather than a ring that would push
    /// them off the card.
    private var ringWithTotal: some View {
        let side = min(ringSide, 150)
        return ZStack {
            SegmentedRing(plan: IntervalPlan(workout: content.runs), strokeRatio: 0.08)
            Text(content.total)
                .font(.hero(side * 0.24))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, side * 0.16)
        }
        .frame(width: side, height: side)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if showsWatch {
                    Label(title, systemImage: "applewatch")
                } else {
                    Text(title)
                }
            }
            .font(.phaseLabel)
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(.secondary)
            Text(content.name)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            RhythmLine(workout: content.runs)
                .font(.subheadline.weight(.semibold))
        }
    }
}

/// "30s · 15s · 8×" in the ring's colours as text: work, rest, then the rounds in the neutral
/// (Classic's white). No rest is shown when there is none, rather than a "0s" for a phase that
/// never happens. One `Text`, so a tight fit wraps or scales the line as a whole.
struct RhythmLine: View {
    let workout: IntervalWorkout

    @Environment(\.palette) private var palette

    var body: some View {
        let separator = Text(" · ").foregroundStyle(palette.neutral.opacity(0.4))
        var line = Text(DurationFormat.clock(workout.workSeconds)).foregroundStyle(palette.workInk)
        if workout.restSeconds > 0 {
            line = Text("\(line)\(separator)\(Text(DurationFormat.clock(workout.restSeconds)).foregroundStyle(palette.restInk))")
        }
        line = Text("\(line)\(separator)\(Text("\(workout.rounds)×").foregroundStyle(palette.neutral.opacity(0.8)))")
        return line
            .monospacedDigit()
            .accessibilityLabel(workout.rhythm)
    }
}

#Preview {
    UpNextCard(content: PresetCardContent(workout: WorkoutStore.starterWorkouts[0], isPro: false), title: "Up next on your watch")
        .padding()
        .background(.black)
}
