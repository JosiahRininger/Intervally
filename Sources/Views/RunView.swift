//
//  RunView.swift
//  Intervally
//

import SwiftUI

/// The running workout — a dial layout in the Timers idiom: one depleting ring sized from
/// the full screen height, the countdown inside it, two round controls low in the bottom
/// corners (End in grey, Pause tinted), and Skip as a corner toolbar glyph.
///
/// There is no navigation title. The ring's colour and the word inside it already say which
/// phase this is; a coloured title in the corner repeated that and cost ~20pt of hero.
struct RunView: View {
    @Environment(RunCoordinator.self) private var coordinator
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    @Binding var isRunning: Bool

    @State private var confirmingEnd = false
    /// Full-screen colour at a phase change, fading out. Under the ring.
    @State private var flash: Double = 0
    @State private var flashKind: IntervalPhase.Kind = .work

    private var engine: TimerEngine { coordinator.engine }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 0.25, paused: engine.status != .running)) { _ in
                let position = engine.position
                if position.isFinished {
                    summary(in: proxy.size, insets: proxy.safeAreaInsets)
                } else {
                    running(position, in: proxy.size, insets: proxy.safeAreaInsets)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { toolbar }
        .confirmationDialog("End workout?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End Workout", role: .destructive) {
                coordinator.stopAndExit()
                isRunning = false
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { coordinator.begin() }
        .onDisappear { coordinator.end() }
    }

    // MARK: - Running

    private func running(_ position: IntervalPlan.Position, in size: CGSize, insets: EdgeInsets) -> some View {
        let kind = position.phase?.kind ?? .work
        let screen = CGSize(width: size.width, height: size.height + insets.top + insets.bottom)
        let dial = DialLayout(screen: screen)
        let diameter = dial.diameter
        let interior = dial.interior

        return VStack(spacing: dial.gap) {
            ZStack {
                ProgressRing(
                    // Depletes: the arc is the time left, retreating toward twelve o'clock.
                    fraction: 1 - position.phaseProgress,
                    color: isLuminanceReduced ? palette.dimmed(for: kind) : palette.fill(for: kind),
                    track: palette.track(for: kind),
                    isDimmed: isLuminanceReduced,
                    animated: !reduceMotion
                )
                .frame(width: diameter, height: diameter)

                interiorContent(position, kind: kind, dial: dial)
                    .frame(width: interior, height: interior)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            controls(kind: kind, dial: dial, width: screen.width)
        }
        .padding(.top, dial.ringTop)
        .padding(.bottom, dial.bottomMargin)
        .ignoresSafeArea(edges: [.top, .bottom])
        // The boundary flash fills the whole display, under the controls as well as the
        // ring. Inside the ring's ZStack it stopped at the ring's frame, so the bottom row
        // never lit up.
        .background {
            palette.fill(for: flashKind)
                .opacity(flash)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onChange(of: position.phase?.id) { _, _ in
            guard !reduceMotion, !isLuminanceReduced, engine.status == .running else { return }
            flashKind = kind
            flash = 0.35
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(16))
                withAnimation(.easeOut(duration: 0.5)) { flash = 0 }
            }
        }
        .containerBackground(Color.black, for: .navigation)
    }

    /// Inside the ring: the phase word, the countdown, then the round dots and heart rate.
    private func interiorContent(_ position: IntervalPlan.Position, kind: IntervalPhase.Kind, dial: DialLayout) -> some View {
        let interior = dial.interior
        // What a line near the top or bottom of the interior has before it meets the ring.
        let lineWidth = dial.chord(atOffset: 0.4 * interior)
        // Sized by how many glyphs the phase can show, so it never changes mid-phase.
        let longPhase = (position.phase?.duration ?? 0) >= 600
        // A 49mm interior is ~120pt; at 0.40 the countdown left ~20pt of air above and
        // below it there, so bigger dials get a bigger number.
        let heroSize = (longPhase ? 0.32 : (interior >= 110 ? 0.44 : 0.40)) * interior
        let paused = engine.status == .paused

        return VStack(spacing: 0) {
            PhaseWord(word: paused ? "Paused" : position.phase?.label?.name ?? kind.shortTitle)
                .frame(maxWidth: lineWidth)

            countdown(position, size: heroSize, color: paused ? .white.opacity(0.55) : palette.fill(for: kind))
                .padding(.top, 2)

            footer(position, kind: kind, interior: interior)
                .frame(maxWidth: lineWidth)
                .padding(.top, 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Self.accessibilitySummary(
                phase: position.phase,
                remainingSeconds: Int(position.remainingInPhase.rounded(.up)),
                isPaused: engine.status == .paused,
                totalRounds: engine.plan.totalRounds
            )
        )
    }

    @ViewBuilder
    private func countdown(_ position: IntervalPlan.Position, size: CGFloat, color: Color) -> some View {
        Group {
            if engine.status == .running, let end = engine.currentPhaseEndDate, let now = clampedNow(before: end) {
                // System-rendered from a date range, so it keeps counting in Always-On and
                // while the app is given no CPU.
                Text(timerInterval: now...end, countsDown: true)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.updatesFrequently)
            } else {
                Text(DurationFormat.timer(Int(position.remainingInPhase.rounded(.up))))
            }
        }
        .font(.hero(size))
        .foregroundStyle(color)
        .minimumScaleFactor(0.6)
        .lineLimit(1)
    }

    /// Where the run is: one dot per round up to ten, otherwise "10 of 20", shrinking to
    /// "10/20" on a small dial. Heart rate lives in the top-left corner instead of here —
    /// sharing this line with it ran "10 of 20 · ♥ 128" off both ends of a 41mm ring.
    /// `RoundFooter` decides what each phase shows, warmup and cooldown included.
    private func footer(_ position: IntervalPlan.Position, kind: IntervalPhase.Kind, interior: CGFloat) -> some View {
        let footer = RoundFooter(
            kind: kind, round: position.phase?.round ?? 1, totalRounds: engine.plan.totalRounds
        )

        return ViewThatFits(in: .horizontal) {
            if let dots = footer.dots {
                HStack(spacing: 4) {
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                        Circle()
                            .fill(dotColor(dot, kind: kind))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 16)
            }
            Text(footer.text)
            Text(footer.compactText)
                .minimumScaleFactor(0.7)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
        .opacity(isLuminanceReduced ? 0.5 : 1)
        .accessibilityLabel(footer.accessibilityLabel)
    }

    private func dotColor(_ dot: RoundFooter.Dot, kind: IntervalPhase.Kind) -> Color {
        switch dot {
        case .done: .white.opacity(0.9)
        case .current: palette.fill(for: kind)
        case .upcoming: .white.opacity(0.25)
        }
    }

    /// The visible "a workout session is running" indicator, and the one number worth words.
    /// It sits in the top-left corner, opposite Skip, where nothing else lives during a run.
    private func heartBadge(_ bpm: Double?) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
            Text(bpm.map { "\(Int($0))" } ?? "––")
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .font(.footnote.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
        .opacity(isLuminanceReduced ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bpm.map { "Heart rate \(Int($0)) beats per minute" } ?? "Recording to Health")
    }

    /// End and Pause as two equal circles at the quarter points of the width, like Timers.
    /// Pause is the screen's one tinted control; End is grey glass, and asks first.
    private func controls(kind: IntervalPhase.Kind, dial: DialLayout, width: CGFloat) -> some View {
        let paused = engine.status == .paused
        let side = dial.control
        // Each control is centred in its own half of the width, so the glass style's own
        // outer padding cannot push the pair toward the edges.
        return HStack(spacing: 0) {
            Button { confirmingEnd = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: side * 0.4, weight: .semibold))
                    .frame(width: side, height: side)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("End workout")
            .frame(maxWidth: .infinity)

            Button { coordinator.togglePause() } label: {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.system(size: side * 0.4, weight: .semibold))
                    .frame(width: side, height: side)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(palette.fill(for: kind))
            .foregroundStyle(palette.onTint)
            .handGestureShortcut(.primaryAction)
            .accessibilityLabel(paused ? "Resume" : "Pause")
            .frame(maxWidth: .infinity)
        }
        .frame(width: width, height: side)
    }

    // MARK: - Summary

    /// The same dial, resolved: the ring turns white and fills, the totals replace the
    /// countdown, the Health result takes the heart line, and one compact Done sits where
    /// Pause was. Nothing scrolls — a scroll view here ran the ring's top arc under the
    /// status bar's blur. The brand colour (Classic's blue, Pastel's pink), not rest-green —
    /// green is a phase word, and this is a state.
    private func summary(in size: CGSize, insets: EdgeInsets) -> some View {
        let screen = CGSize(width: size.width, height: size.height + insets.top + insets.bottom)
        let dial = DialLayout(screen: screen)
        let diameter = dial.diameter
        let interior = dial.interior
        let summary = coordinator.summary
        let duration = Int(summary?.duration ?? engine.plan.totalDuration)
        let rounds = summary?.rounds ?? engine.plan.totalRounds
        let fg: Color = isLuminanceReduced ? .white : .black

        return VStack(spacing: dial.gap) {
            ZStack {
                ProgressRing(
                    fraction: 1,
                    color: isLuminanceReduced ? palette.dimmed(for: .work) : .white,
                    track: .clear,
                    isDimmed: isLuminanceReduced,
                    animated: !reduceMotion
                )
                .frame(width: diameter, height: diameter)

                VStack(spacing: 0) {
                    Text("Complete")
                        .font(.phaseLabel)
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .foregroundStyle(fg.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: dial.chord(atOffset: 0.4 * interior))
                    // m:ss like the countdown it replaces — "45s" here read as a different unit —
                    // and free to shrink for a multi-hour total rather than truncate.
                    Text(DurationFormat.timer(duration))
                        .font(.hero(0.40 * interior))
                        .foregroundStyle(fg)
                        .minimumScaleFactor(0.45)
                        .lineLimit(1)
                        .padding(.top, 2)
                    summaryFooter(rounds: rounds, health: summary?.health ?? .notRecorded, foreground: fg)
                        .frame(maxWidth: dial.chord(atOffset: 0.4 * interior))
                        .padding(.top, 4)
                }
                .frame(width: interior)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(completionAccessibilitySummary)
            }
            .frame(width: diameter, height: diameter)

            Button {
                coordinator.stopAndExit()
                isRunning = false
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(width: dial.capsuleWidth, height: dial.control)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(isLuminanceReduced ? palette.dimmed(for: .work) : .white)
            .foregroundStyle(fg)
            .fixedSize()
            .handGestureShortcut(.primaryAction)
            .frame(height: dial.control)
        }
        .padding(.top, dial.ringTop)
        .padding(.bottom, dial.bottomMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: [.top, .bottom])
        .containerBackground(
            isLuminanceReduced
                ? AnyShapeStyle(Color.black)
                : AnyShapeStyle(LinearGradient(colors: [palette.brand, palette.brandDeep], startPoint: .top, endPoint: .bottom)),
            for: .navigation
        )
    }

    /// One line under the total: whether the workout reached Apple Health, or — when the
    /// run had no workout session to save — the rounds.
    ///
    /// One deterministic line per state, with no animation. The previous version let a
    /// ViewThatFits choose between two layouts while the screen was still animating in, and
    /// "Saved" showed truncated for a moment before it settled.
    private func summaryFooter(rounds: Int, health: RunCoordinator.HealthSave, foreground fg: Color) -> some View {
        let heart = Text(Image(systemName: "heart.fill")).foregroundStyle(.red)
        return Group {
            switch health {
            case .notRecorded:
                Text(DurationFormat.rounds(rounds))
            case .saving:
                Text("\(heart) Saving")
            case .saved:
                ViewThatFits(in: .horizontal) {
                    Text("\(heart) Saved to Health")
                    Text("\(heart) Saved")
                }
            case .failed:
                Text("\(heart) Not saved")
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(fg.opacity(0.7))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .transaction { $0.animation = nil }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if engine.status == .finished {
            // Leading, not trailing: Skip lives in the trailing corner during the run, and a
            // second tap on Skip as the last interval ended landed on Repeat and restarted
            // the workout the user had just finished.
            ToolbarItem(placement: .topBarLeading) {
                Button { coordinator.restart() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Repeat workout")
            }
        } else {
            if coordinator.tier == .workout {
                ToolbarItem(placement: .topBarLeading) {
                    heartBadge(coordinator.workout.heartRate)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { coordinator.skip() } label: { Image(systemName: "forward.end.fill") }
                    .accessibilityLabel("Skip to next interval")
            }
        }
    }

    // MARK: - Helpers

    /// `ClosedRange` traps when the lower bound exceeds the upper one; the engine samples
    /// the clock before this view does, so on a boundary the second sample can already be
    /// past the end. Fall back to the static label in that window.
    private func clampedNow(before end: Date) -> Date? {
        let now = Date()
        return now <= end ? now : nil
    }

    /// What VoiceOver reads for the running dial. A bookend names no round — the warmup
    /// comes before round 1 and the cooldown after the last — so it says what it is instead.
    nonisolated static func accessibilitySummary(
        phase: IntervalPhase?, remainingSeconds: Int, isPaused: Bool, totalRounds: Int
    ) -> String {
        guard let phase else { return "Workout complete" }
        let remaining = DurationFormat.spoken(remainingSeconds)
        let state = isPaused ? "Paused. " : ""
        return switch phase.kind {
        case .prepare: "\(state)\(phase.label?.name ?? "Get ready"), \(remaining) remaining"
        case .warmup: "\(state)\(phase.title), \(remaining) remaining"
        case .cooldown: "\(state)\(phase.title), intervals done, \(remaining) remaining"
        case .work, .rest:
            "\(state)\(phase.title), round \(phase.round) of \(totalRounds), \(remaining) remaining"
        }
    }

    private var completionAccessibilitySummary: String {
        let summary = coordinator.summary
        var parts = ["Workout complete", DurationFormat.spoken(Int(summary?.duration ?? engine.plan.totalDuration)), DurationFormat.rounds(summary?.rounds ?? engine.plan.totalRounds)]
        switch summary?.health {
        case .saved: parts.append("Saved to Health")
        case .saving: parts.append("Saving to Health")
        case .failed: parts.append("Not saved to Health")
        default: break
        }
        return parts.joined(separator: ", ")
    }
}

/// The round footer under the run screen's countdown, worked out apart from the view so
/// every phase's state can be tested.
///
/// The bookends sit outside the rounds, so the footer shows the rounds' state from there:
/// in the warmup none has started — every dot dim, "8 rounds" — and in the cooldown all
/// are done — every dot filled, "8 of 8".
struct RoundFooter: Equatable, Sendable {
    enum Dot: Equatable, Sendable { case done, current, upcoming }

    /// One per round, or nil past `maxDots`, where a row of dots stops reading as a count.
    let dots: [Dot]?
    /// "3 of 8"; "8 rounds" in the warmup.
    let text: String
    /// "3/8" for a small dial; "8×" in the warmup, the rhythm's own shorthand.
    let compactText: String
    let accessibilityLabel: String

    static let maxDots = 10

    init(kind: IntervalPhase.Kind, round: Int, totalRounds: Int) {
        let total = max(1, totalRounds)
        let current = min(total, max(1, round))
        let all: [Dot]
        switch kind {
        case .warmup:
            all = Array(repeating: .upcoming, count: total)
            text = DurationFormat.rounds(total)
            compactText = "\(total)×"
            accessibilityLabel = DurationFormat.rounds(total)
        case .cooldown:
            all = Array(repeating: .done, count: total)
            text = "\(total) of \(total)"
            compactText = "\(total)/\(total)"
            accessibilityLabel = "All \(DurationFormat.rounds(total)) done"
        case .prepare, .work, .rest:
            all = (1...total).map { $0 < current ? .done : $0 == current ? .current : .upcoming }
            text = "\(current) of \(total)"
            compactText = "\(current)/\(total)"
            accessibilityLabel = "Round \(current) of \(total)"
        }
        dots = total <= Self.maxDots ? all : nil
    }
}

/// The phase word at the top of the run ring: "WORK", "REST", "COOLDOWN", "PAUSED".
///
/// The tracked style when the word fits its line whole; otherwise the same size without the
/// tracking, allowed to shrink to `smallestScale`. On a 40mm ring the line is about 53pt and
/// "COOLDOWN" is 84pt as set: the old label asked that tracked Text to shrink to 0.65, which
/// would have fit, and it truncated to "COOLDO…" instead. So the fallback drops the tracking
/// before it shrinks. Only that word, on the smallest watches, ever shrinks.
struct PhaseWord: View {
    let word: String

    struct Style {
        let font: Font
        let kerning: CGFloat
    }

    static let tracked = Style(font: .phaseLabel, kerning: 0.6)
    static let untracked = Style(font: .phaseLabel, kerning: 0)
    static let smallestScale: CGFloat = 0.55

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Self.text(word, Self.tracked)
            Self.text(word, Self.untracked).minimumScaleFactor(Self.smallestScale)
        }
    }

    static func text(_ word: String, _ style: Style) -> some View {
        Text(word)
            .font(style.font)
            .textCase(.uppercase)
            .kerning(style.kerning)
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
    }
}
