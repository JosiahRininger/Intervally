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

    init(output: any CueOutput, pro: any ProGating, defaults: UserDefaults = SharedDefaults.suite) {
        self.output = output
        self.pro = pro
        self.defaults = defaults
    }

    var settings: CueSettings {
        CueSettings.stored(in: defaults).effective(isPro: pro.isPro)
    }

    func play(_ event: TimerEvent, context: BoundaryContext) {
        // Taken at Start, in front, and kept: away from the app the audio can carry on but
        // can't be started. Every event re-checks it; it costs nothing while it runs.
        let settings = self.settings
        if settings.beeps || settings.voice { output.holdForRun() }
        let plan = CuePlan.make(for: event, context: context, settings: settings, totalRounds: roundsInRun())
        perform(plan)
    }

    func cancelPending() {
        output.silence()
    }

    /// The run is over: the audio goes back, and with it the volume buttons, to the ringer.
    func release() {
        output.handBackAudio()
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
        output.lowersOtherAudio = settings.lowerMusic
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
