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

/// A preset in the library: its shape as a ring, then its name, rhythm and total time.
struct PresetCard: View {
    let content: PresetCardContent

    var body: some View {
        HStack(spacing: 14) {
            // The workout's shape, so presets are told apart before their names are read.
            SegmentedRing(plan: IntervalPlan(workout: content.runs), strokeRatio: 0.12, gap: 1.5)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(content.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(content.rhythm)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(content.total)
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
        }
        .padding(16)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.spokenSummary)
    }
}

#Preview {
    PresetCard(content: PresetCardContent(workout: WorkoutStore.starterWorkouts[0], isPro: false))
        .padding()
        .background(.black)
}
