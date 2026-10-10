//
//  HistoryRow.swift
//  IntervallyPhone
//

import SwiftUI

/// One session in History: how much of it ran as a white ring, then its name, when it
/// started, its rounds, its length, its calories and its average heart rate.
struct HistoryRow: View {
    let session: SessionSummary

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            switch CardArrangement(typeSize: typeSize) {
            case .row:
                HStack(spacing: 14) {
                    ring
                    labels
                    Spacer(minLength: 8)
                    figures(alignment: .trailing)
                }
            case .stacked:
                VStack(alignment: .leading, spacing: 10) {
                    ring
                    labels
                    figures(alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileBackground()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(session))
    }

    /// "Classic, Thursday, October 9 at 7:42 AM, 8 of 8 rounds, 4 minutes 30 seconds, average
    /// heart rate 142 beats per minute".
    static func spoken(_ session: SessionSummary) -> String {
        var parts = [
            session.title,
            session.start.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()),
            session.spokenRounds,
            DurationFormat.spoken(Int(session.duration.rounded())),
        ]
        if let calories = session.calories {
            parts.append("\(calories) calories")
        }
        if let heartRate = session.averageHeartRate {
            parts.append("average heart rate \(heartRate) beats per minute")
        }
        return parts.joined(separator: ", ")
    }

    private var ring: some View {
        CompletionRing(fraction: session.completion)
            .frame(width: 36, height: 36)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title)
                .font(.headline)
            // With the time: two sessions on one day are otherwise the same row. On one line
            // where it fits; where it doesn't, broken between whole phrases, never mid-date or
            // after the separator with "8/8" left on a line alone. An iPhone SE takes the third.
            let day = session.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            let time = session.start.formatted(.dateTime.hour().minute())
            let dayAndTime = session.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
            ViewThatFits(in: .horizontal) {
                Text("\(dayAndTime) · \(session.roundsReachedText)")
                    .lineLimit(1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayAndTime).lineLimit(1)
                    Text(session.roundsLineText).lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(day).lineLimit(1)
                    Text("\(time) · \(session.roundsReachedText)").lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(day)
                    Text(time)
                    Text(session.roundsLineText)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            // A line of its own: wrapped onto the date's, it began a line with its separator.
            if session.endedEarly {
                Text("Ended early")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func figures(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            // Never wraps: "4:30" broken across two lines reads as two numbers.
            Text(session.durationText)
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .lineLimit(1)
                .fixedSize()
            // One line: calories for every kind of workout, the heart only where measured.
            HStack(spacing: 10) {
                if let calories = session.calories {
                    CaloriesLabel(calories: calories)
                }
                if let heartRate = session.averageHeartRate {
                    HeartRateLabel(beats: heartRate)
                }
            }
            .font(.subheadline)
        }
    }
}

/// "🔥 62": calories burned, the flame kept close to its number. Never wraps.
struct CaloriesLabel: View {
    let calories: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .imageScale(.small)
            Text("\(calories)")
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(calories) calories")
    }
}

/// "♥ 142": a heart rate, the heart kept close to its number. Never wraps.
struct HeartRateLabel: View {
    let beats: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .imageScale(.small)
            Text("\(beats)")
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
    }
}

/// How much of a session ran, as one ring in the neutral (Classic's white): full for a run
/// that went to the end. Neutral, because colour here only ever means a phase, and never
/// concentric rings (Guideline 5.2.5).
struct CompletionRing: View {
    /// 0...1.
    let fraction: Double

    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let lineWidth = max(3, side * 0.14)
            ZStack {
                Circle()
                    .stroke(palette.neutral.opacity(0.2), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.0001, min(1, fraction)))
                    .stroke(palette.neutral, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: side - lineWidth, height: side - lineWidth)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}
