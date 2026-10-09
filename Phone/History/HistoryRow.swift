//
//  HistoryRow.swift
//  IntervallyPhone
//

import SwiftUI

/// One session in History: how much of it ran as a white ring, then its name, when it
/// started, its rounds, its length and its average heart rate.
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
            // With the time: two sessions on one day are otherwise the same row.
            Text("\(session.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())) · \(session.roundsReachedText)")
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
            if let heartRate = session.averageHeartRate {
                HeartRateLabel(beats: heartRate)
                    .font(.subheadline)
            }
        }
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
