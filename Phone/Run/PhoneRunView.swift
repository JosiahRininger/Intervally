//
//  PhoneRunView.swift
//  IntervallyPhone
//

import StoreKit
import SwiftUI

/// How big the run screen's ring is: as wide as the screen allows with a margin, but never so
/// tall that the controls drop off an iPhone SE.
enum RunScreenLayout {
    /// Where the first run's volume tip is remembered as seen, per iPhone.
    static let soundTipSeenKey = "phone.run.soundTipSeen.v1"

    static func ringSide(width: CGFloat, height: CGFloat) -> CGFloat {
        let byWidth = width - 56
        let byHeight = height * 0.5
        return max(220, min(largest(width: width, height: height), byWidth, byHeight)).rounded()
    }

    /// The ring beside everything else rather than above it: a landscape screen too short to
    /// stack them, as iPhone Duo's inner screen is, opened. iPad's is tall enough to stack.
    static func isSideBySide(width: CGFloat, height: CGFloat) -> Bool {
        width > height * 1.2 && height < 760
    }

    /// Beside the controls: as tall as the screen allows, and no wider than half of it.
    static func sideRingSide(width: CGFloat, height: CGFloat) -> CGFloat {
        let byWidth = width * 0.5 - 40
        let byHeight = height - 48
        return max(200, min(largest(width: width, height: height), byWidth, byHeight)).rounded()
    }

    /// 380 on every iPhone; an iPad-sized screen has room for more.
    private static func largest(width: CGFloat, height: CGFloat) -> CGFloat {
        min(width, height) >= 600 ? 520 : 380
    }

    /// The next phase, as the line under the ring says it: "Next: Rest 0:15", or the end.
    static func nextLine(after phase: IntervalPhase?, next: IntervalPhase?) -> String {
        guard phase != nil else { return "" }
        guard let next else { return "Last interval" }
        return "Next: \(next.title) \(DurationFormat.timer(Int(next.duration)))"
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
    /// The first run on this iPhone says how to set the beeps' volume, once.
    @AppStorage(RunScreenLayout.soundTipSeenKey, store: SharedDefaults.suite) private var soundTipSeen = false

    /// This iPhone's run, or the watch's when the screen mirrors one.
    private var engine: TimerEngine { run.engine }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 0.1, paused: engine.status != .running)) { _ in
                if engine.status == .finished, let summary = run.summary {
                    RunSummaryView(
                        summary: summary, workoutName: engine.plan.workout.name, onWatch: run.isMirroring
                    ) {
                        done()
                    } repeatRun: {
                        // A tap landing while Done closes the screen must not start a run
                        // with nothing showing it.
                        guard run.isPresented, engine.status == .finished, !run.isMirroring else { return }
                        countedFinish = false
                        run.coordinator.restart()
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
            Button("End Workout", role: .destructive) { run.end() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text(run.isMirroring ? "It ends on your Apple Watch too, and won't be saved." : "This workout won't be saved.")
        }
        // A watch run is already going: only this iPhone's own run starts here.
        .onAppear { if !run.isMirroring { run.coordinator.begin() } }
        .onChange(of: run.keepsScreenAwake, initial: true) { _, awake in
            UIApplication.shared.isIdleTimerDisabled = awake
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: engine.status) { _, status in
            // An End still being confirmed when the run finishes would close the summary
            // unseen, under words that say the finished, saved workout won't be saved.
            if status == .finished { confirmingEnd = false }
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

        return Group {
            if RunScreenLayout.isSideBySide(width: size.width, height: size.height) {
                HStack(spacing: 32) {
                    ring(position, kind: kind, paused: paused, side: RunScreenLayout.sideRingSide(width: size.width, height: size.height))
                    VStack(spacing: 0) {
                        header
                        Spacer(minLength: 12)
                        nextLine(position, next: next)
                        Spacer(minLength: 12)
                        hints(position)
                        controls(kind: kind, paused: paused)
                            .padding(.bottom, 12)
                    }
                    .frame(maxWidth: 420, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 12)
                    ring(position, kind: kind, paused: paused, side: side)
                    nextLine(position, next: next)
                        .padding(.top, 24)
                    Spacer(minLength: 12)
                    hints(position)
                    controls(kind: kind, paused: paused)
                        .padding(.bottom, 12)
                }
                // Centred: on iPad the ring stops well short of the screen's width, and the
                // geometry reader would otherwise pin it to the leading edge.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 24)
        .onChange(of: position.phase?.id) { _, _ in
            // The tip has had its moment once the run is past getting ready.
            if position.phase?.kind != .prepare, engine.status == .running { soundTipSeen = true }
            guard !reduceMotion, engine.status == .running else { return }
            flashKind = kind
            flash = palette.colorScheme == .dark ? 0.3 : 0.45
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(16))
                withAnimation(.easeOut(duration: 0.6)) { flash = 0 }
            }
        }
    }

    /// One depleting ring in the phase's colour, with the countdown inside.
    private func ring(_ position: IntervalPlan.Position, kind: IntervalPhase.Kind, paused: Bool, side: CGFloat) -> some View {
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
    }

    private func nextLine(_ position: IntervalPlan.Position, next: IntervalPhase?) -> some View {
        Text(RunScreenLayout.nextLine(after: position.phase, next: next))
            .font(.headline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .multilineTextAlignment(.center)
            // Grows with the text size, but not so far that it crowds the controls.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .accessibilityLabel(next.map { "Next, \($0.title), \(DurationFormat.spoken(Int($0.duration)))" } ?? "Last interval")
    }

    @ViewBuilder
    private func hints(_ position: IntervalPlan.Position) -> some View {
        if run.isVolumeLow {
            hint("Turn up the volume to hear each interval", systemImage: "speaker.wave.1.fill")
                .padding(.bottom, 16)
                .transition(.opacity)
        } else if !soundTipSeen, !run.isMirroring, position.phase?.kind == .prepare {
            // While getting ready, before the first change: the moment to set the volume.
            hint("Set how loud the beeps are with the volume buttons", systemImage: "speaker.wave.2.fill")
                .padding(.bottom, 16)
                .transition(.opacity)
        }
    }

    /// A line about the sound. The cues play at the media volume, which the volume buttons set
    /// while a run is going.
    private func hint(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
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
            if run.isMirroring {
                // The watch runs it and taps the wrist; this screen follows it live.
                Label("On your Apple Watch", systemImage: "applewatch")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.workInk)
            }
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
            Text(paused ? "Paused" : position.phase?.title ?? kind.title)
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
                run.togglePause()
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
                run.skip()
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
        let title = position.phase?.title ?? kind.title
        var parts = [paused ? "Paused, \(title)" : title]
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
        run.done()
        reviews.ask(.finishedWorkout(count: run.finishedRuns), using: requestReview)
    }
}

/// The finished run: what it came to, whether Health has it, and Done or Repeat.
struct RunSummaryView: View {
    let summary: RunCoordinator.Summary
    let workoutName: String
    /// A run the watch ran: it repeats from the watch, not from here.
    var onWatch = false
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
                if !onWatch {
                    Button(action: repeatRun) {
                        Label("Repeat", systemImage: "arrow.counterclockwise")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .neutralGlass()
                }
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
            Label(onWatch ? "Your watch is saving it to Health" : "Saving to Health", systemImage: "heart")
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
