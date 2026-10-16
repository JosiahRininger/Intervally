//
//  PhoneCuePlayer.swift
//  IntervallyPhone
//

import Foundation

/// Marks each interval change on iPhone: a tone, the voice coach with Pro, and a tap while
/// the app is in front. What plays is `CuePlan`'s decision; this only reads the settings and
/// hands the plan to the output.
@MainActor
final class PhoneCuePlayer: BoundaryHaptics {
    private let output: any CueOutput
    private let pro: any ProGating
    private let defaults: UserDefaults
    /// The rounds in the run under way, for "Last round". Set by whoever owns the run.
    var roundsInRun: () -> Int = { 1 }
    /// The phases of the run under way, for the phrases rendered ahead. Set by whoever owns
    /// the run.
    var phasesInRun: () -> [IntervalPhase] = { [] }
    /// Whether a run is under way (running or paused). Set by whoever owns the run.
    var runIsActive: () -> Bool = { false }
    /// How long after the finish the audio is handed back: the chime and "Workout complete"
    /// are over well before.
    var releaseAfterFinish: TimeInterval = 5
    private var finishRelease: Task<Void, Never>?

    init(output: any CueOutput, pro: any ProGating, defaults: UserDefaults = SharedDefaults.suite) {
        self.output = output
        self.pro = pro
        self.defaults = defaults
    }

    var settings: CueSettings {
        CueSettings.stored(in: defaults).effective(isPro: pro.isPro)
    }

    func play(_ event: TimerEvent, context: BoundaryContext) {
        // An event is a run going on: a finished run's release still waiting is off.
        finishRelease?.cancel()
        finishRelease = nil
        // Taken at Start, in front, and kept: away from the app the audio can carry on but
        // can't be started. Every event re-checks it; it costs nothing while it runs.
        holdIfSounding()
        let plan = CuePlan.make(for: event, context: context, settings: settings, totalRounds: roundsInRun())
        perform(plan)
        if case .finished = event { releaseOnceFinished() }
    }

    /// Takes the audio for a run, if it has anything to be heard: at each event, and for a run
    /// already under way that comes back after a relaunch or to the front, so the next change
    /// sounds even if the phone is locked by then.
    func holdIfSounding() {
        let settings = self.settings
        if settings.beeps || settings.voice { output.holdForRun() }
        // Every phrase the run can say, rendered now, in front, where it can be.
        if settings.voice { output.prepare(Self.phrases(for: phasesInRun(), totalRounds: roundsInRun())) }
    }

    /// Renders what the voice coach can say in any of `workouts`, ahead of a run: at launch
    /// and back in front. The output renders only while nothing else plays, and keeps each.
    func prepareAhead(_ workouts: [IntervalWorkout]) {
        let settings = self.settings
        guard settings.voice else { return }
        var seen = Set<String>()
        let phrases = workouts.flatMap { workout in
            let plan = IntervalPlan(workout: workout.effective(isPro: pro.isPro))
            return Self.phrases(for: plan.phases, totalRounds: plan.totalRounds)
        }.filter { seen.insert($0).inserted }
        output.prepare(phrases)
    }

    /// What the voice coach can say in a run of `phases`, each once, in the order it comes.
    static func phrases(for phases: [IntervalPhase], totalRounds: Int) -> [String] {
        var seen = Set<String>()
        return (phases.map { CuePlan.phrase(for: $0, totalRounds: totalRounds) } + [CuePlan.finishPhrase])
            .filter { seen.insert($0).inserted }
    }

    func cancelPending() {
        output.silence()
    }

    /// The run is over: the audio goes back, and with it the volume buttons, to the ringer.
    func release() {
        finishRelease?.cancel()
        finishRelease = nil
        output.handBackAudio()
    }

    /// A finished run's audio goes back once the finish has sounded, with no Done needed: a
    /// summary left on screen in a pocket must not hold the audio, and with it the app, open
    /// for nothing. Unless another run has started meanwhile (Repeat).
    private func releaseOnceFinished() {
        let delay = releaseAfterFinish
        finishRelease = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, !self.runIsActive() else { return }
            self.finishRelease = nil
            self.output.handBackAudio()
        }
    }

    /// Whether the cues would be hard to hear at `volume`: with something to hear (beeps,
    /// which carry the countdown too, or the voice), and the media volume near the bottom.
    func isQuiet(atVolume volume: Float) -> Bool {
        let settings = self.settings
        return (settings.beeps || settings.voice) && volume < Self.quietVolume
    }

    /// About two presses of the volume button from silent.
    static let quietVolume: Float = 0.15

    /// A pause or a resume: felt, not heard. A sound there would be mistaken for an interval.
    func transport(_ cue: TransportCue) {
        output.tap(.light)
    }

    /// Settings' preview of what an interval change sounds like with the current choices.
    func preview() {
        let sample = IntervalPhase(id: 0, kind: .work, duration: 30, round: 1, start: 0)
        perform(CuePlan.make(for: .phaseBegan(sample), context: .immediate, settings: settings, totalRounds: 8))
    }

    private func perform(_ plan: CuePlan) {
        var delay: TimeInterval = 0
        if let tone = plan.tone {
            delay = output.play(tone)
        }
        if let phrase = plan.phrase {
            output.say(phrase, after: delay)
        }
        if let tap = plan.tap {
            output.tap(tap)
        }
    }
}
