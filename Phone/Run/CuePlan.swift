//
//  CuePlan.swift
//  IntervallyPhone
//

import Foundation

/// A sound the iPhone plays, synthesized rather than shipped as files (`ToneSynth`).
enum CueTone: Equatable, Sendable, CaseIterable {
    /// A short tick for 3, 2, 1.
    case tick
    /// A phase that asks for effort starts: work.
    case go
    /// An easy phase starts: rest, the cooldown.
    case ease
    /// The prepare countdown or the warmup starts.
    case ready
    /// The last phase ran out.
    case finish
}

/// A tap of the iPhone's Taptic Engine. Felt only while the app is in front, where iOS
/// allows it at all.
enum CueTap: Equatable, Sendable {
    case light, heavy, success
}

/// What the iPhone's cue settings ask for, as read when a boundary plays.
struct CueSettings: Equatable, Sendable {
    /// The tone at every interval change, and the finish chime.
    var beeps = true
    /// The 3, 2, 1 ticks before each change.
    var countdown = true
    /// The voice coach. Intervally Pro: `effective(isPro:)` drops it without.
    var voice = true
    /// Music or a podcast underneath dips while a cue sounds, and comes straight back.
    var lowerMusic = true

    enum Key {
        static let beeps = "phone.cues.beeps"
        static let countdown = "phone.cues.countdown"
        static let voice = "phone.cues.voice"
        static let lowerMusic = "phone.cues.lowerMusic"
        /// Whether the screen stays on while a run is in front.
        static let keepAwake = "phone.run.keepAwake"
    }

    /// The saved choices. Each is on until it is turned off.
    static func stored(in defaults: UserDefaults) -> CueSettings {
        func flag(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
        return CueSettings(
            beeps: flag(Key.beeps), countdown: flag(Key.countdown), voice: flag(Key.voice),
            lowerMusic: flag(Key.lowerMusic)
        )
    }

    /// Without Pro the voice stays quiet, but the saved choice is kept, so a restore brings
    /// it straight back.
    func effective(isPro: Bool) -> CueSettings {
        var settings = self
        settings.voice = voice && isPro
        return settings
    }
}

/// Everything one engine event plays on iPhone, decided apart from any speaker so the rules
/// are testable.
struct CuePlan: Equatable, Sendable {
    var tone: CueTone?
    /// The voice coach's words, after the tone.
    var phrase: String?
    var tap: CueTap?

    static let silent = CuePlan()

    /// A change announced later than this is a catch-up after the app was away: the moment
    /// has passed, and the notification backstop marked it when it did. It plays nothing.
    static let lateThreshold: TimeInterval = 1.5

    static func make(
        for event: TimerEvent, context: BoundaryContext, settings: CueSettings, totalRounds: Int
    ) -> CuePlan {
        if context.lateness > lateThreshold { return .silent }
        switch event {
        case .countdown:
            guard settings.countdown else { return .silent }
            return CuePlan(tone: settings.beeps ? .tick : nil, phrase: nil, tap: .light)
        case .phaseBegan(let phase):
            return CuePlan(
                tone: settings.beeps ? tone(for: phase.kind) : nil,
                phrase: settings.voice ? phrase(for: phase, totalRounds: totalRounds) : nil,
                tap: .heavy
            )
        case .finished:
            return CuePlan(
                tone: settings.beeps ? .finish : nil,
                phrase: settings.voice ? "Workout complete" : nil,
                tap: .success
            )
        }
    }

    static func tone(for kind: IntervalPhase.Kind) -> CueTone {
        switch kind {
        case .prepare, .warmup: .ready
        case .work: .go
        case .rest, .cooldown: .ease
        }
    }

    /// Short enough to finish inside a 10-second rest, and never a number the screen
    /// already shows bigger.
    static func phrase(for phase: IntervalPhase, totalRounds: Int) -> String {
        // A name the preset gave the phase is what the coach calls it, "Last round" aside.
        if let label = phase.label {
            return phase.kind == .work && totalRounds > 1 && phase.round == totalRounds ? "Last round" : label.name
        }
        return switch phase.kind {
        case .prepare: "Get ready"
        case .warmup: "Warm up"
        case .work: totalRounds > 1 && phase.round == totalRounds ? "Last round" : "Work"
        case .rest: "Rest"
        case .cooldown: "Cool down"
        }
    }
}
