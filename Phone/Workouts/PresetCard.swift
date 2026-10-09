//
//  PresetCard.swift
//  IntervallyPhone
//

import SwiftUI

/// What one preset card shows, worked out from the preset and the entitlement so the card
/// only lays it out.
struct PresetCardContent: Equatable {
    let name: String
    /// The workout that would run. Without Pro that is the preset minus its warmup and
    /// cooldown, as on the watch: the stored values stay, but neither the ring nor the total
    /// may promise phases that won't run.
    let runs: IntervalWorkout
    /// "30s · 15s · 8×".
    let rhythm: String
    /// "5:55".
    let total: String
    let spokenSummary: String

    init(workout: IntervalWorkout, isPro: Bool) {
        let runs = workout.effective(isPro: isPro)
        self.name = workout.name
        self.runs = runs
        self.rhythm = runs.rhythm
        self.total = DurationFormat.clock(runs.totalSeconds)
        self.spokenSummary = runs.spokenSummary
    }
}

/// How a card lays itself out at a text size.
enum CardArrangement: Equatable {
    /// Ring, then the words, then the total, side by side.
    case row
    /// Ring and total on top, the words free to wrap underneath.
    case stacked

    /// At the accessibility sizes one row can't hold all three: the name and rhythm were cut
    /// to a few letters and the total broke mid-number on a 402-point iPhone.
    init(typeSize: DynamicTypeSize) {
        self = typeSize.isAccessibilitySize ? .stacked : .row
    }
}

/// A preset in the library: its shape as a ring, then its name, rhythm and total time.
struct PresetCard: View {
    let content: PresetCardContent
    /// The preset the watch starts next, marked so the library agrees with the card above it.
    var isUpNext = false

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            switch CardArrangement(typeSize: typeSize) {
            case .row:
                HStack(spacing: 14) {
                    ring
                    // Two lines, so a narrow screen at a large size wraps the rhythm rather
                    // than dropping its rounds.
                    labels(lineLimit: 2)
                    Spacer(minLength: 8)
                    total
                }
            case .stacked:
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ring
                        Spacer(minLength: 8)
                        total
                    }
                    labels(lineLimit: nil)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileBackground()
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.spokenSummary)
        .accessibilityValue(isUpNext ? "Up next" : "")
    }

    /// The workout's shape, so presets are told apart before their names are read.
    private var ring: some View {
        SegmentedRing(plan: IntervalPlan(workout: content.runs), strokeRatio: 0.12, gap: 1.5)
            .frame(width: 44, height: 44)
    }

    private func labels(lineLimit: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(content.name)
                    .font(.headline)
                    .lineLimit(lineLimit)
                if isUpNext {
                    Image(systemName: "applewatch")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.workInk)
                }
            }
            Text(content.rhythm)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(lineLimit)
        }
    }

    /// Never wraps and never yields its width: "5:55" broken across two lines reads as two
    /// numbers.
    private var total: some View {
        Text(content.total)
            .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
    }
}

#Preview {
    VStack {
        PresetCard(content: PresetCardContent(workout: WorkoutStore.starterWorkouts[0], isPro: false), isUpNext: true)
        PresetCard(content: PresetCardContent(workout: WorkoutStore.starterWorkouts[1], isPro: false))
    }
    .padding()
    .background(.black)
}

#Preview("Largest text") {
    PresetCard(content: PresetCardContent(workout: WorkoutStore.starterWorkouts[0], isPro: false))
        .padding()
        .background(.black)
        .dynamicTypeSize(.accessibility5)
}
