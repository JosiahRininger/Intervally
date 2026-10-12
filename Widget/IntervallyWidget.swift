//
//  IntervallyWidget.swift
//  IntervallyWidget
//

import RelevanceKit
import SwiftUI
import WidgetKit

/// A Smart Stack widget / complication: the interval currently running, or — between
/// workouts — the selected preset, one tap from starting.
///
/// The countdown is rendered with `Text(timerInterval:)` and a timer-interval gauge from the
/// shared run snapshot, so the complication keeps counting on the watch face without the
/// widget extension being woken to redraw each second.
struct IntervallyWidget: Widget {
    static let kind = "IntervallyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: RunProvider()) { entry in
            IntervallyWidgetView(entry: entry)
        }
        .configurationDisplayName("Interval Timer")
        .description("Shows the interval you're on, or starts your preset.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner,
        ])
    }
}

// MARK: - Timeline

struct RunEntry: TimelineEntry {
    let date: Date
    /// Nil when nothing is running.
    let run: RunProgress?
    /// When the current phase began. With `run.phaseEnd` it is the range the gauge counts
    /// down through on its own.
    let phaseStart: Date?
    /// How much of the phase was left at `date`. Only the paused face draws it; a running
    /// gauge keeps its own time.
    let remainingFraction: Double
    /// What the idle face offers to start.
    let preset: IntervalWorkout?
    /// The theme the app is wearing, read as the timeline was built.
    var theme: AppTheme = .classic

    static func idle(at date: Date, preset: IntervalWorkout?, theme: AppTheme = .classic) -> RunEntry {
        RunEntry(date: date, run: nil, phaseStart: nil, remainingFraction: 0, preset: preset, theme: theme)
    }
}

struct RunProvider: TimelineProvider {

    func placeholder(in context: Context) -> RunEntry {
        let now = Date.now
        return RunEntry(
            date: now,
            run: RunProgress(
                phaseKind: .work, phaseEnd: now.addingTimeInterval(30),
                round: 3, totalRounds: 8, isPaused: false
            ),
            phaseStart: now,
            remainingFraction: 1,
            preset: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (RunEntry) -> Void) {
        completion(entry(at: .now, from: WorkoutStore.activeRun(), theme: ThemeStore.effective()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RunEntry>) -> Void) {
        let now = Date()
        let snapshot = WorkoutStore.activeRun()
        // Once per timeline: the app reloads every timeline when the theme changes.
        let theme = ThemeStore.effective()
        let current = entry(at: now, from: snapshot, theme: theme)

        guard current.run?.isPaused == false, let snapshot else {
            // Nothing counting down, so there is nothing to refresh for. The idle face is
            // rebuilt when the app reloads the timeline.
            completion(Timeline(entries: [current], policy: .never))
            return
        }

        // An entry per upcoming phase boundary. `Text(timerInterval:)` covers every second
        // between them without waking the extension, but each boundary still needs a real
        // entry — WidgetKit renders entries verbatim, so a placeholder would show
        // "no workout running" for the rest of the workout.
        let entries = [current] + snapshot.upcomingBoundaries(after: now).map { entry(at: $0, from: snapshot, theme: theme) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// Tells the Smart Stack when this complication is worth floating to the top: during a
    /// workout it is the most useful thing on the watch, and around the hour the user
    /// usually trains it is the quickest way to begin one.
    func relevance() async -> WidgetRelevance<Void> {
        if let snapshot = WorkoutStore.activeRun() {
            let end = snapshot.anchor.addingTimeInterval(snapshot.plan.totalDuration)
            if end > Date() {
                return WidgetRelevance([WidgetRelevanceAttribute(context: .fitness(.workoutActive))])
            }
        }
        guard let window = WorkoutStore.usualStartWindow(from: WorkoutStore.recentStarts()) else {
            return WidgetRelevance([])
        }
        return WidgetRelevance([
            WidgetRelevanceAttribute(context: .date(interval: window, kind: .scheduled))
        ])
    }

    /// Rebuilds the widget's view of the run from the snapshot the app persists.
    /// The derivation itself lives in `RunSnapshot` so it can be tested.
    private func entry(at date: Date, from snapshot: RunSnapshot?, theme: AppTheme) -> RunEntry {
        guard let snapshot, let run = snapshot.progress(at: date) else {
            return .idle(at: date, preset: WorkoutStore.selectedPreset(), theme: theme)
        }
        let position = snapshot.plan.position(atElapsed: snapshot.elapsed(at: date))
        return RunEntry(
            date: date,
            run: run,
            phaseStart: position.phase.map { snapshot.anchor.addingTimeInterval($0.start) },
            remainingFraction: 1 - position.phaseProgress,
            preset: nil,
            theme: theme
        )
    }
}

// MARK: - Views

struct IntervallyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: RunEntry

    private var palette: Palette { .of(entry.theme) }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                inline
            case .accessoryCircular:
                circular
            case .accessoryCorner:
                corner
            default:
                rectangular
            }
        }
        .containerBackground(canvas, for: .widget)
        .widgetURL(destination)
    }

    /// `ClosedRange` traps when its lower bound exceeds its upper one. A timeline entry is
    /// rendered at, and after, its own date, so by the time the view is built the phase end
    /// can already be in the past.
    private func clampedNow(before end: Date) -> Date? {
        let now = Date()
        return now <= end ? now : nil
    }

    /// Running taps land in the workout; idle taps start the preset. With no preset saved
    /// yet there is nothing to start, so the app simply opens.
    private var destination: URL? {
        if entry.run != nil {
            URL(string: "intervally://run")
        } else if entry.preset != nil {
            URL(string: "intervally://start")
        } else {
            URL(string: "intervally://open")
        }
    }

    /// The rectangular face is the one place the complication wears the phase colour; the
    /// smaller faces leave colour to the gauge.
    private var canvas: AnyShapeStyle {
        guard family == .accessoryRectangular, let run = entry.run else {
            return AnyShapeStyle(.fill.tertiary)
        }
        return AnyShapeStyle(tint(for: run).gradient)
    }

    /// Black holds up on every phase tint. In accented rendering the system recolours the
    /// canvas itself, so the text goes back to the default.
    private var onCanvas: Color {
        renderingMode == .fullColor ? palette.onTint : Color.primary
    }

    private func tint(for run: RunProgress) -> Color {
        run.isPaused ? palette.dimmed(for: run.phaseKind) : palette.fill(for: run.phaseKind)
    }

    // MARK: Pieces

    /// "WORK · 3 of 8", or a bookend's name alone. The wording lives in `RunProgress` so
    /// the app's tests can reach it.
    private func phaseLine(for run: RunProgress) -> Text {
        Text(run.phaseLine)
    }

    @ViewBuilder
    private func countdown(for run: RunProgress) -> some View {
        if run.isPaused {
            Text("Paused")
        } else if let now = clampedNow(before: run.phaseEnd) {
            Text(timerInterval: now...run.phaseEnd, countsDown: true)
        } else {
            // The phase has ended and the next entry is about to replace this one.
            Text(DurationFormat.timer(0))
        }
    }

    /// The system's circular gauge, counting the phase down on its own. Paused, it holds
    /// still at the fraction the run froze on.
    @ViewBuilder
    private func gauge(for run: RunProgress) -> some View {
        if !run.isPaused, let start = entry.phaseStart, start < run.phaseEnd {
            ProgressView(timerInterval: start...run.phaseEnd, countsDown: true) {
                Image(systemName: run.symbolName)
            } currentValueLabel: {
                countdown(for: run)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
            }
            .progressViewStyle(.circular)
            .tint(tint(for: run))
        } else {
            Gauge(value: entry.remainingFraction) {
                Image(systemName: run.symbolName)
            } currentValueLabel: {
                Image(systemName: "pause.fill")
                    .font(.caption.weight(.semibold))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(tint(for: run))
        }
    }

    private static func summary(of workout: IntervalWorkout) -> String {
        workout.rhythm
    }

    private var idleTitle: String {
        entry.preset.map { "Start \($0.name)" } ?? "Intervally"
    }

    // MARK: Families

    private var inline: some View {
        if let run = entry.run {
            Text("\(Image(systemName: run.symbolName)) \(run.compactLine)")
        } else {
            Text("\(Image(systemName: "timer")) \(idleTitle)")
        }
    }

    @ViewBuilder
    private var circular: some View {
        if let run = entry.run {
            gauge(for: run)
        } else {
            VStack(spacing: 0) {
                Image(systemName: "timer")
                    .font(.body.weight(.semibold))
                if let initial = entry.preset?.name.first {
                    Text(String(initial))
                        .font(.caption2.weight(.bold))
                }
            }
            .widgetAccentable()
        }
    }

    @ViewBuilder
    private var corner: some View {
        if let run = entry.run {
            gauge(for: run)
                .widgetLabel {
                    if run.isPaused {
                        Text("Paused")
                    } else {
                        phaseLine(for: run)
                    }
                }
        } else {
            Image(systemName: "timer")
                .font(.title3.weight(.semibold))
                .widgetAccentable()
                .widgetLabel(idleTitle)
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let run = entry.run {
            VStack(alignment: .leading, spacing: 2) {
                phaseLine(for: run)
                    .font(.caption.weight(.semibold))
                    .widgetAccentable()
                countdown(for: run)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(onCanvas)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label(idleTitle, systemImage: "timer")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .widgetAccentable()
                Text(entry.preset.map(Self.summary(of:)) ?? "Open to set up")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@main
struct IntervallyWidgetBundle: WidgetBundle {
    var body: some Widget {
        IntervallyWidget()
        IntervallyControl()
    }
}
