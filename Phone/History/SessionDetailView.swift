//
//  SessionDetailView.swift
//  IntervallyPhone
//

import Charts
import SwiftUI

/// One session: the phases that ran as a ring, its totals, heart rate per interval, and every
/// interval in order.
struct SessionDetailView: View {
    let session: SessionSummary

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(HistoryModel.self) private var history
    @Environment(ReviewLedger.self) private var reviews
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                heading
                tiles
                if session.showsChart {
                    section("Heart Rate by Interval") { chart }
                }
                if !session.intervals.isEmpty {
                    section("Intervals") { intervals }
                }
                Label("Saved in Apple Health", systemImage: "heart.text.square")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .blackCanvas()
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        // Back to the list after looking at a session: the calmest good moment there is.
        .onDisappear {
            reviews.ask(.lookedBackAtSession(sessionCount: history.sessions.count), using: requestReview)
        }
    }

    // MARK: - Hero

    /// The phases that actually ran, an early end included, with the rounds inside.
    private var hero: some View {
        let side: CGFloat = 220
        return ZStack {
            if session.intervals.isEmpty {
                CompletionRing(fraction: session.completion)
            } else {
                SegmentedRing(phases: session.phases, strokeRatio: 0.07)
            }
            VStack(spacing: 4) {
                Text("Rounds")
                    .font(.phaseLabel)
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(.secondary)
                Text(session.plannedRounds.map { "\(session.roundsReached)/\($0)" } ?? "\(session.roundsReached)")
                    .font(.hero(52))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                if session.endedEarly {
                    Text("Ended early")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, side * 0.15)
            // The ring is a fixed size; the tiles below carry the same at any text size.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .frame(width: side, height: side)
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.spokenRounds)
    }

    private var heading: some View {
        VStack(spacing: 4) {
            Text(session.title)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(session.start.formatted(date: .complete, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Tiles

    /// Only what Health recorded: no heart-rate tiles when it has none. One column at the
    /// accessibility sizes, where two broke the titles and numbers mid-word.
    private var tiles: some View {
        let columns = typeSize.isAccessibilitySize ? 1 : 2
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
            tile("Duration", value: session.durationText, spoken: DurationFormat.spoken(Int(session.duration.rounded())))
            if let average = session.averageHeartRate {
                tile("Avg Heart Rate", value: "\(average)", unit: "BPM", spoken: "\(average) beats per minute")
            }
            if let maximum = session.maximumHeartRate {
                tile("Max Heart Rate", value: "\(maximum)", unit: "BPM", spoken: "\(maximum) beats per minute")
            }
            if let energy = session.activeEnergy {
                let text = Measurement(value: energy, unit: UnitEnergy.kilocalories)
                    .formatted(.measurement(width: .abbreviated, usage: .workout, numberFormatStyle: .number.precision(.fractionLength(0))))
                tile("Active Energy", value: text, spoken: text)
            }
        }
    }

    private func tile(_ title: String, value: String, unit: String? = nil, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.phaseLabel)
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileBackground()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spoken)
    }

    // MARK: - Chart

    /// A bar per interval, as tall as its average heart rate and in its phase's colour, so
    /// the work bars rise above the rest between them.
    private var chart: some View {
        Chart(session.intervals.filter { $0.averageHeartRate != nil }) { interval in
            BarMark(
                x: .value("Interval", "\(interval.id)"),
                y: .value("Heart Rate", interval.averageHeartRate ?? 0)
            )
            .foregroundStyle(Theme.light(for: interval.kind))
            .accessibilityLabel(interval.title)
            .accessibilityValue("\(interval.averageHeartRate ?? 0) beats per minute")
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.15))
                AxisValueLabel()
            }
        }
        .frame(height: 180)
        .padding(16)
        .tileBackground()
    }

    // MARK: - Intervals

    private var intervals: some View {
        VStack(spacing: 0) {
            ForEach(session.intervals) { interval in
                IntervalRow(interval: interval)
                if interval.id != session.intervals.last?.id {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 16)
        .tileBackground()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title)
            content()
        }
    }
}

/// One interval: its phase in its colour, its round, how long it ran and its heart rate.
private struct IntervalRow: View {
    let interval: SessionSummary.Interval

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            switch CardArrangement(typeSize: typeSize) {
            case .row:
                HStack(spacing: 12) {
                    title
                    Spacer(minLength: 8)
                    figures
                }
            case .stacked:
                VStack(alignment: .leading, spacing: 4) {
                    title
                    HStack(spacing: 16) {
                        figures
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var title: some View {
        HStack(spacing: 12) {
            Image(systemName: interval.kind.symbolName)
                .foregroundStyle(Theme.light(for: interval.kind))
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(interval.title)
                .font(.body)
        }
    }

    @ViewBuilder
    private var figures: some View {
        Text(DurationFormat.clock(Int(interval.duration.rounded())))
            .font(.body.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
        if let heartRate = interval.averageHeartRate {
            HeartRateLabel(beats: heartRate)
                .font(.body)
                .frame(minWidth: 64, alignment: typeSize.isAccessibilitySize ? .leading : .trailing)
        }
    }

    private var spoken: String {
        var parts = [interval.title, DurationFormat.spoken(Int(interval.duration.rounded()))]
        if let heartRate = interval.averageHeartRate {
            parts.append("\(heartRate) beats per minute")
        }
        return parts.joined(separator: ", ")
    }
}
