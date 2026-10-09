//
//  ValueEditorView.swift
//  Intervally
//

import SwiftUI

/// Edits a single integer setting with the Digital Crown. The +/- in the bottom bar are the
/// touch backup; the crown owns the value.
///
/// The crown turns over an index into a precomputed table rather than over raw seconds. A
/// linear `by: 5` across 5…3600 was 720 detents — a full minute of turning to reach ten
/// minutes — so the table coarsens as the numbers grow: 5s steps below 2:00, 15s to 10:00,
/// 30s beyond. Rounds stay one per detent.
struct ValueEditorView: View {
    let title: String
    /// Kept so the call sites in `SetupView` need not change; the inline title carries the
    /// identity here and the tile already showed the glyph.
    let systemImage: String
    let range: ClosedRange<Int>
    /// The finest step. `1` marks a count (rounds); anything else is seconds.
    let step: Int
    let tint: Color
    /// Formats the value for display, e.g. "45s" or "8".
    let format: (Int) -> String
    /// What VoiceOver announces, which is words rather than the compact display form.
    let spoken: (Int) -> String
    /// The word beneath the value, for the value on screen. Inferred from `step` and the
    /// value when nil. A closure because one word can't fit every value: a bookend's "Off"
    /// takes no unit at all.
    var unit: ((Int) -> String)? = nil
    /// The crown's detents, when the coarsening schedule doesn't suit. Bookends pass their
    /// own: the schedule's 5- and 15-second bands would make 77 uneven detents of them.
    var valueTable: [Int]? = nil

    @Binding var value: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Index into `values`, not the value itself: that is what makes the steps non-linear.
    @State private var crown: Double = 0

    var values: [Int] { valueTable ?? Self.values(in: range, step: step) }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 2) {
                Text(format(value))
                    .font(.hero(min(0.26 * proxy.size.width, 54)))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .snappy, value: value)

                // A space rather than nothing when there is no unit, so the value doesn't
                // jump down a line as the crown turns it to "Off".
                Text(unitLabel.isEmpty ? " " : unitLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .scenePadding()
        .focusable()
        .digitalCrownRotation(
            $crown,
            from: 0,
            through: Double(values.count - 1),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crown) { _, new in
            let next = values[clampedIndex(Int(new.rounded()))]
            guard next != value else { return }
            value = next
        }
        .onChange(of: value) { _, new in
            if let position = crownPosition(after: new, from: crown) { crown = position }
        }
        .onAppear {
            // A stored value that is not on the table (say 7s from an older build) would
            // otherwise jump to a neighbour on the first click of the crown.
            let index = nearestIndex(to: value)
            crown = Double(index)
            if values[index] != value { value = values[index] }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                stepButton("minus", delta: -1, enabled: value > values[0])
            }
            ToolbarItem(placement: .bottomBar) {
                stepButton("plus", delta: 1, enabled: value < values[values.count - 1])
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(spoken(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(1)
            case .decrement: adjust(-1)
            default: break
            }
        }
    }

    var unitLabel: String {
        if let unit { return unit(value) }
        if step == 1 { return value == 1 ? "round" : "rounds" }
        // "1:30" is read as minutes; "seconds" beneath it would contradict the digits.
        return value < 60 ? "seconds" : "minutes"
    }

    /// Hidden from VoiceOver: the adjustable action on the value covers it.
    private func stepButton(_ systemImage: String, delta: Int, enabled: Bool) -> some View {
        Button {
            adjust(delta)
        } label: {
            Image(systemName: systemImage)
        }
        .buttonBorderShape(.circle)
        .disabled(!enabled)
        .accessibilityHidden(true)
    }

    private func adjust(_ delta: Int) {
        let index = clampedIndex(nearestIndex(to: value) + delta)
        guard values[index] != value else { return }
        value = values[index]
        crown = Double(index)
    }

    /// Where the crown must sit once `value` has changed: nil while it already rests on that
    /// value's detent, as after its own turn or a +/- tap, else on that detent. A value
    /// changed from outside, by an edit merged in from the iPhone, left the crown where it
    /// was, and its next click saved the old value's neighbour over the new one.
    func crownPosition(after value: Int, from crown: Double) -> Double? {
        let index = nearestIndex(to: value)
        return clampedIndex(Int(crown.rounded())) == index ? nil : Double(index)
    }

    private func clampedIndex(_ index: Int) -> Int {
        min(max(0, index), values.count - 1)
    }

    private func nearestIndex(to target: Int) -> Int {
        let table = values
        return table.indices.min { abs(table[$0] - target) < abs(table[$1] - target) } ?? 0
    }

    /// Every value the crown can land on. The table lives in `ValueSteps`, shared with the
    /// iPhone's pickers; this forwarder keeps the watch's call sites and tests as they were.
    nonisolated static func values(in range: ClosedRange<Int>, step: Int) -> [Int] {
        ValueSteps.values(in: range, step: step)
    }
}

#Preview {
    @Previewable @State var seconds = 30
    NavigationStack {
        ValueEditorView(
            title: "Work",
            systemImage: "bolt.fill",
            range: IntervalWorkout.workRange,
            step: 5,
            tint: Theme.work,
            format: DurationFormat.clock,
            spoken: DurationFormat.spoken,
            value: $seconds
        )
    }
}
