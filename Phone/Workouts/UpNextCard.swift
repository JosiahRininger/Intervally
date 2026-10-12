//
//  UpNextCard.swift
//  IntervallyPhone
//

import SwiftUI

/// The workout up next: the hero of the Workouts screen, drawn like the watch's own dial with
/// the total inside its ring, and Start under it. The same workout is the one the watch
/// starts next.
struct UpNextCard: View {
    let content: PresetCardContent
    let title: String
    /// The watch's glyph beside the title, only where there is a watch: the watch starts this
    /// one next too.
    var showsWatch = true
    /// Opens the editor: a tap anywhere on the card above Start.
    var open: () -> Void = {}
    var start: () -> Void = {}
    /// Start on Watch, beside Start, where the watch app can be woken.
    var startOnWatch: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .title) private var ringSide: CGFloat = 104

    var body: some View {
        let ring = ringWithTotal

        VStack(spacing: 16) {
            Button(action: open) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title). \(content.spokenSummary)")
            .accessibilityValue(showsWatch ? "Also up next on your watch" : "")
            .accessibilityHint("Opens the editor")

            buttons
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileBackground()
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Start, and under it, where there is a watch to wake, Start on Apple Watch: quieter,
    /// as Start is the one most taps want.
    private var buttons: some View {
        VStack(spacing: 6) {
            Button(action: start) {
                Label(WorkoutsContent.startTitle, systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .prominentCapsule()
            .accessibilityLabel("Start \(content.name)")

            if let startOnWatch {
                Button(action: startOnWatch) {
                    Label("Start on Apple Watch", systemImage: "applewatch")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.workInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start \(content.name) on Apple Watch")
            }
        }
        // The text button's own height stands in for the card's bottom padding.
        .padding(.bottom, startOnWatch == nil ? 0 : -8)
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
            HStack(spacing: 6) {
                Text(title)
                if showsWatch {
                    Image(systemName: "applewatch")
                        .accessibilityHidden(true)
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
        // 0.6, not 0.4: at 0.4 the dots came to about 3.7:1 on the card (accessibility audit).
        let separator = Text(" · ").foregroundStyle(palette.neutral.opacity(0.6))
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
    UpNextCard(content: PresetCardContent(workout: WorkoutStore.starterWorkouts[0], isPro: false), title: "Up next")
        .padding()
        .background(.black)
}
