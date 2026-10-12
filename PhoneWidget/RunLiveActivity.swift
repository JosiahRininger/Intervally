//
//  RunLiveActivity.swift
//  IntervallyPhoneWidget
//

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct IntervallyPhoneWidgets: WidgetBundle {
    var body: some Widget {
        RunLiveActivity()
    }
}

/// The iPhone's run on the Lock Screen, in the Dynamic Island, and in a paired watch's Smart
/// Stack: the phase in its colour, its countdown, and the round.
///
/// Between the app's updates the system's own timer text and progress bar keep counting, so
/// every running view is built from dates, never from a number of seconds.
struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            RunActivityView(context: context)
                .activityBackgroundTint(ActivityStyle(context.state.theme).background)
                .activitySystemActionForegroundColor(ActivityStyle(context.state.theme).primary)
        } dynamicIsland: { context in
            let style = ActivityStyle(context.state.theme)
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        PhaseTitle(state: state, isStale: context.isStale)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                        if let round = ActivityText.round(state: state, totalRounds: context.attributes.totalRounds) {
                            Text(round)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: state, isStale: context.isStale)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(style.fill(state.phase))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        PhaseBar(state: state, isStale: context.isStale)
                            .tint(style.fill(state.phase))
                        HStack {
                            Text(context.attributes.workoutName)
                                .lineLimit(1)
                            Spacer()
                            Text(ActivityText.next(state: state))
                                .monospacedDigit()
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                PhaseRing(state: state, isStale: context.isStale)
                    .tint(style.fill(state.phase))
                    .frame(width: 22, height: 22)
            } compactTrailing: {
                Countdown(state: state, isStale: context.isStale)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(style.fill(state.phase))
                    .frame(maxWidth: 52)
            } minimal: {
                PhaseRing(state: state, isStale: context.isStale)
                    .tint(style.fill(state.phase))
                    .frame(width: 22, height: 22)
            }
            .keylineTint(style.fill(state.phase))
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

// MARK: - Lock Screen

struct RunActivityView: View {
    let context: ActivityViewContext<RunActivityAttributes>

    @Environment(\.activityFamily) private var family

    var body: some View {
        let style = ActivityStyle(context.state.theme)
        let state = context.state
        switch family {
        case .small:
            // A watch's Smart Stack: the phase, its countdown and its bar, nothing else.
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    PhaseTitle(state: state, isStale: context.isStale)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                    Spacer(minLength: 4)
                    Countdown(state: state, isStale: context.isStale)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(style.fill(state.phase))
                }
                PhaseBar(state: state, isStale: context.isStale)
                    .tint(style.fill(state.phase))
            }
            .padding(10)
        default:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        PhaseTitle(state: state, isStale: context.isStale)
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                        Text(ActivityText.subtitle(state: state, attributes: context.attributes))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(style.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Countdown(state: state, isStale: context.isStale)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(style.fill(state.phase))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                PhaseBar(state: state, isStale: context.isStale)
                    .tint(style.fill(state.phase))
                Text(ActivityText.next(state: state))
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(style.secondary)
            }
            .foregroundStyle(style.primary)
            .padding(16)
        }
    }
}

// MARK: - Pieces

/// "WORK", "PAUSED", "COMPLETE", or the workout's name once the activity has gone stale.
private struct PhaseTitle: View {
    let state: RunActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let style = ActivityStyle(state.theme)
        Text(ActivityText.title(state: state, isStale: isStale))
            .textCase(.uppercase)
            .kerning(0.8)
            .foregroundStyle(state.phase.map { style.ink($0) } ?? style.primary)
            .lineLimit(1)
    }
}

/// The phase's countdown: the system's timer while running, the time left while paused.
/// Stale, it counts to the end of the whole workout instead, which no update can make wrong.
private struct Countdown: View {
    let state: RunActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        Group {
            switch state.clock {
            case .running(let phaseStart, let phaseEnd, let workoutEnd):
                if isStale {
                    Text(timerInterval: Date.now...max(Date.now, workoutEnd), countsDown: true)
                } else {
                    Text(timerInterval: phaseStart...phaseEnd, countsDown: true)
                }
            case .paused(let phaseLeft, _):
                Text(ActivityText.clock(phaseLeft))
            case .finished:
                Image(systemName: "checkmark")
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

/// How much of the phase is left, emptying as it runs.
private struct PhaseBar: View {
    let state: RunActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        switch state.clock {
        case .running(let phaseStart, let phaseEnd, let workoutEnd):
            if isStale {
                ProgressView(timerInterval: Date.now...max(Date.now, workoutEnd), countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
            } else {
                ProgressView(timerInterval: phaseStart...phaseEnd, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
            }
        case .paused(let phaseLeft, _):
            ProgressView(value: state.phaseDuration > 0 ? min(1, phaseLeft / state.phaseDuration) : 0)
        case .finished:
            ProgressView(value: 1)
        }
    }
}

/// The phase as a small ring, for the Dynamic Island's compact and minimal places.
private struct PhaseRing: View {
    let state: RunActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        switch state.clock {
        case .running(let phaseStart, let phaseEnd, _) where !isStale:
            ProgressView(timerInterval: phaseStart...phaseEnd, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.circular)
        case .paused(let phaseLeft, _):
            ProgressView(value: state.phaseDuration > 0 ? min(1, phaseLeft / state.phaseDuration) : 0)
                .progressViewStyle(.circular)
        default:
            Image(systemName: state.clock == .finished ? "checkmark.circle.fill" : "figure.highintensity.intervaltraining")
        }
    }
}

// MARK: - Words and colours

enum ActivityText {
    static func title(state: RunActivityAttributes.ContentState, isStale: Bool) -> String {
        guard let phase = state.phase else { return "Complete" }
        if case .paused = state.clock { return "Paused" }
        if isStale { return "Intervally" }
        return state.phaseName ?? phase.title
    }

    static func round(state: RunActivityAttributes.ContentState, totalRounds: Int) -> String? {
        guard let phase = state.phase, phase == .work || phase == .rest, totalRounds > 1 else { return nil }
        return "Round \(state.round) of \(totalRounds)"
    }

    /// "Tabata · Round 3 of 8", or just the name where rounds don't apply.
    static func subtitle(state: RunActivityAttributes.ContentState, attributes: RunActivityAttributes) -> String {
        if case .finished = state.clock {
            return "\(attributes.workoutName) · \(clock(attributes.totalDuration))"
        }
        guard let round = round(state: state, totalRounds: attributes.totalRounds) else { return attributes.workoutName }
        return "\(attributes.workoutName) · \(round)"
    }

    static func next(state: RunActivityAttributes.ContentState) -> String {
        if case .finished = state.clock { return "Workout complete" }
        guard let next = state.next, let duration = state.nextDuration else { return "Last interval" }
        return "Next: \(state.nextName ?? next.title) \(clock(duration))"
    }

    /// m:ss, as the timer text shows it.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.up)))
        if whole >= 3600 { return String(format: "%d:%02d:%02d", whole / 3600, whole % 3600 / 60, whole % 60) }
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// The app's palette, as the activity draws it: Classic on near-black, Pastel on its pale
/// canvas, each phase in the colour it has in the app.
struct ActivityStyle {
    let palette: Palette

    init(_ theme: AppTheme) {
        palette = Palette.of(theme)
    }

    var background: Color { palette.colorScheme == .dark ? Color.black.opacity(0.82) : palette.canvas.opacity(0.94) }
    var primary: Color { palette.colorScheme == .dark ? .white : .black }
    var secondary: Color { primary.opacity(0.6) }

    func fill(_ kind: IntervalPhase.Kind?) -> Color {
        guard let kind else { return palette.work }
        // On Pastel's light canvas the fills are too pale for text; the inks carry it.
        return palette.colorScheme == .dark ? palette.fill(for: kind) : palette.ink(for: kind)
    }

    func ink(_ kind: IntervalPhase.Kind) -> Color {
        palette.colorScheme == .dark ? palette.fill(for: kind) : palette.ink(for: kind)
    }
}
