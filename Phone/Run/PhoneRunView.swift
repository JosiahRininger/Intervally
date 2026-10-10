//
//  PhoneRunView.swift
//  IntervallyPhone
//

import SwiftUI

/// How big the run screen's ring is: as wide as the screen allows with a margin, but never so
/// tall that the controls drop off an iPhone SE.
enum RunScreenLayout {
    static func ringSide(width: CGFloat, height: CGFloat) -> CGFloat {
        let byWidth = width - 56
        let byHeight = height * 0.5
        return max(220, min(380, byWidth, byHeight)).rounded()
    }

    /// The next phase, as the line under the ring says it: "Next: Rest 0:15", or the end.
    static func nextLine(after phase: IntervalPhase?, next: IntervalPhase?) -> String {
        guard phase != nil else { return "" }
        guard let next else { return "Last interval" }
        return "Next: \(next.kind.title) \(DurationFormat.timer(Int(next.duration)))"
    }

    /// "Round 3 of 8", where a round means something: never while getting ready, in the
    /// warmup or the cooldown, and never for a single round.
    static func roundLine(for phase: IntervalPhase?, totalRounds: Int) -> String? {
        guard let phase, phase.kind == .work || phase.kind == .rest, totalRounds > 1 else { return nil }
        return "Round \(phase.round) of \(totalRounds)"
    }
}

/// A workout running on iPhone, from Start to its summary.
///
/// Built like the watch's run screen at iPhone scale: one depleting ring in the phase's
/// colour with the countdown inside, End and Skip either side of a large Pause, and the
/// whole screen flashing the new phase's colour at each change.
struct PhoneRunView: View {
    @Environment(PhoneRun.self) private var run
    @Environment(ReviewLedger.self) private var reviews
    @Environment(\.requestReview) private var requestReview
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var confirmingEnd = false
    @State private var flash: Double = 0
    @State private var flashKind: IntervalPhase.Kind = .work
    @State private var countedFinish = false

    private var coordinator: RunCoordinator { run.coordinator }
    private var engine: TimerEngine { coordinator.engine }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 0.1, paused: engine.status != .running)) { _ in
                if engine.status == .finished, let summary = coordinator.summary {
                    RunSummaryView(summary: summary, workoutName: engine.plan.workout.name) {
                        done()
                    } repeatRun: {
                        // A tap landing while Done closes the screen must not start a run
                        // with nothing showing it.
                        guard run.isPresented, engine.status == .finished else { return }
                        countedFinish = false
                        coordinator.restart()
                    }
                } else {
                    running(engine.position, size: proxy.size)
                }
            }
        }
        .background(palette.canvas.ignoresSafeArea())
        .background {
            palette.fill(for: flashKind)
                .opacity(flash)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .preferredColorScheme(palette.colorScheme)
        .confirmationDialog("End workout?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End Workout", role: .destructive) { run.close() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("This workout won't be saved.")
        }
        .onAppear { coordinator.begin() }
        .onChange(of: run.keepsScreenAwake, initial: true) { _, awake in
            UIApplication.shared.isIdleTimerDisabled = awake
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: engine.status) { _, status in
            guard status == .finished, !countedFinish else { return }
            countedFinish = true
            run.recordFinish()
        }
    }

    // MARK: - Running

    private func running(_ position: IntervalPlan.Position, size: CGSize) -> some View {
        let kind = position.phase?.kind ?? engine.plan.phases.first?.kind ?? .work
        let side = RunScreenLayout.ringSide(width: size.width, height: size.height)
        let paused = engine.status == .paused
        let next = position.phaseIndex.flatMap { index in
            engine.plan.phases.indices.contains(index + 1) ? engine.plan.phases[index + 1] : nil
        }

        return VStack(spacing: 0) {
            header
            Spacer(minLength: 12)
            ZStack {
                // A soft glow of the phase's colour behind the ring.
                Circle()
                    .fill(palette.fill(for: kind).opacity(palette.colorScheme == .dark ? 0.16 : 0.22))
                    .blur(radius: side * 0.18)
                    .frame(width: side * 0.9, height: side * 0.9)
                    .accessibilityHidden(true)
                ProgressRing(
                    fraction: 1 - position.phaseProgress,
                    color: palette.fill(for: kind),
                    track: palette.track(for: kind),
                    strokeRatio: 0.075,
                    animated: !reduceMotion
                )
                .frame(width: side, height: side)
                interior(position, kind: kind, paused: paused, side: side)
                    .frame(width: side * 0.72)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenStatus(position, kind: kind, paused: paused))
            .accessibilityAddTraits(.updatesFrequently)

            Text(RunScreenLayout.nextLine(after: position.phase, next: next))
                .font(.headline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                // Grows with the text size, but not so far that it crowds the controls.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .padding(.top, 24)
                .accessibilityLabel(next.map { "Next, \($0.kind.title), \(DurationFormat.spoken(Int($0.duration)))" } ?? "Last interval")
            Spacer(minLength: 12)
            if run.isVolumeLow {
                volumeHint
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
            controls(kind: kind, paused: paused)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .onChange(of: position.phase?.id) { _, _ in
            guard !reduceMotion, engine.status == .running else { return }
            flashKind = kind
            flash = palette.colorScheme == .dark ? 0.3 : 0.45
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(16))
                withAnimation(.easeOut(duration: 0.6)) { flash = 0 }
            }
        }
    }

    /// The cues play at the media volume, which the volume buttons set while a run is going.
    private var volumeHint: some View {
        Label("Turn up the volume to hear each interval", systemImage: "speaker.wave.1.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// The workout's name and how long is left in all, small, so the ring stays the hero.
    private var header: some View {
        VStack(spacing: 4) {
            Text(engine.plan.workout.name)
                .font(.headline)
                .lineLimit(1)
            Text("\(DurationFormat.timer(Int(engine.position.remainingTotal.rounded(.up)))) left")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private func interior(_ position: IntervalPlan.Position, kind: IntervalPhase.Kind, paused: Bool, side: CGFloat) -> some View {
        let remaining = Int(position.remainingInPhase.rounded(.up))
        return VStack(spacing: side * 0.02) {
            Text(paused ? "Paused" : kind.title)
                .font(.system(size: side * 0.07, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .kerning(1.2)
                .foregroundStyle(paused ? Color.secondary : palette.ink(for: kind))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(DurationFormat.timer(remaining))
                .font(.hero(side * (remaining >= 600 ? 0.22 : 0.27)))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(countsDown: true))
            if let line = RunScreenLayout.roundLine(for: position.phase, totalRounds: engine.plan.totalRounds) {
                Text(line)
                    .font(.system(size: side * 0.055, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func controls(kind: IntervalPhase.Kind, paused: Bool) -> some View {
        HStack {
            Button {
                confirmingEnd = true
            } label: {
                // Fixed, like the circle it sits in: at the largest text sizes a scaled glyph
                // outgrew Pause's.
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .neutralGlass()
            .accessibilityLabel("End Workout")

            Spacer()

            Button {
                coordinator.togglePause()
            } label: {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 34, weight: .bold))
                    .frame(width: 92, height: 92)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(palette.fill(for: kind))
            .foregroundStyle(palette.onTint)
            .disabled(engine.status == .idle)
            .accessibilityLabel(paused ? "Resume" : "Pause")

            Spacer()

            Button {
                coordinator.skip()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .neutralGlass()
            .disabled(engine.status == .idle)
            .accessibilityLabel("Skip Interval")
        }
        .frame(maxWidth: 360)
    }

    private func spokenStatus(_ position: IntervalPlan.Position, kind: IntervalPhase.Kind, paused: Bool) -> String {
        var parts = [paused ? "Paused, \(kind.title)" : kind.title]
        parts.append("\(DurationFormat.spoken(Int(position.remainingInPhase.rounded(.up)))) left")
        if let line = RunScreenLayout.roundLine(for: position.phase, totalRounds: engine.plan.totalRounds) {
            parts.append(line)
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Done

    /// Back to the workouts. A good moment to ask for a rating, once someone has finished a
    /// few: the system decides whether to show anything.
    private func done() {
        guard run.isPresented, engine.status == .finished else { return }
        run.close()
        reviews.ask(.finishedWorkout(count: run.finishedRuns), using: requestReview)
    }
}

/// The finished run: what it came to, whether Health has it, and Done or Repeat.
struct RunSummaryView: View {
    let summary: RunCoordinator.Summary
    let workoutName: String
    let done: () -> Void
    let repeatRun: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            ZStack {
                ProgressRing(fraction: 1, color: palette.work, track: palette.track(for: .work), strokeRatio: 0.075, animated: false)
                    .frame(width: 220, height: 220)
                VStack(spacing: 6) {
                    Text("Complete")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .textCase(.uppercase)
                        .kerning(1.2)
                        .foregroundStyle(palette.workInk)
                    Text(DurationFormat.timer(Int(summary.duration)))
                        .font(.hero(56))
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Workout complete, \(DurationFormat.spoken(Int(summary.duration)))")

            Text(workoutName)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.top, 28)
            Text(DurationFormat.rounds(summary.rounds) + " done")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            healthLine
                .padding(.top, 16)
            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Button(action: done) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .prominentCapsule()
                Button(action: repeatRun) {
                    Label("Repeat", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .neutralGlass()
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
    }

    /// Nothing at all when the run had no workout session: Health was declined, and saying
    /// "Not saved" after every run would only nag.
    @ViewBuilder
    private var healthLine: some View {
        switch summary.health {
        case .notRecorded:
            EmptyView()
        case .saving:
            Label("Saving to Health", systemImage: "heart")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .saved:
            Label("Saved to Health", systemImage: "heart.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.workInk)
        case .failed:
            Label("Couldn't save to Health", systemImage: "heart.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
