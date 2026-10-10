//
//  Haptics.swift
//  Intervally
//

import Foundation
import WatchKit

/// Haptic cues for the events the engine emits.
///
/// The watch has a small fixed vocabulary of system haptics; these are chosen so that
/// starting work and starting rest feel clearly different through a sleeve. What a boundary
/// plays is decided by the pure `plan(for:strength:context:)` and played by `HapticPlayer`.
enum Haptics {

    /// Transport feedback (`TransportCue`, shared with the iPhone's run).
    typealias Cue = TransportCue

    @MainActor
    static func play(cue: Cue) {
        play(cue.type)
    }

    /// The tap that marks a phase starting. The easy phases borrow the directional pair:
    /// up into the warmup as the session builds, and down into the cooldown, as into a rest.
    static func boundaryType(for kind: IntervalPhase.Kind) -> WKHapticType {
        switch kind {
        case .prepare: .start
        case .warmup: .directionUp
        case .work: .notification
        case .rest: .directionDown
        case .cooldown: .directionDown
        }
    }

    @MainActor
    static func play(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
}

extension TransportCue {
    var type: WKHapticType {
        switch self {
        case .start: .start
        case .stop: .stop
        }
    }
}

// MARK: - Tap strength

/// How hard each interval change taps: an Intervally Pro setting.
///
/// Third-party apps get no amplitude control — `WKInterfaceDevice.play(_:)` takes no
/// intensity and watchOS has no Core Haptics — so "stronger" means the same tap repeated.
/// Never name a level "Prominent": that is the system's own Haptics setting.
enum TapStrength: String, CaseIterable, Identifiable, Sendable {
    /// Raw values are persisted in the shared defaults, so they must never be renamed.
    case standard, strong, strongest

    var id: Self { self }

    /// Taps per boundary, before the timing rules in `Haptics.plan` trim a burst to fit.
    var taps: Int {
        switch self {
        case .standard: 1
        case .strong: 2
        case .strongest: 3
        }
    }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .strong: "Strong"
        case .strongest: "Strongest"
        }
    }

    var detail: String {
        switch self {
        case .standard: "One tap"
        case .strong: "Two taps"
        case .strongest: "Three taps"
        }
    }

    /// The saved choice. Missing or unreadable reads as Standard.
    static func stored(in defaults: UserDefaults) -> TapStrength {
        defaults.string(forKey: SettingsKey.tapStrength)
            .flatMap(TapStrength.init(rawValue:)) ?? .standard
    }

    /// What actually plays. Without Pro every boundary taps once, but the saved choice is
    /// never erased, so a restore or a re-purchase brings it straight back.
    static func effective(stored: TapStrength, isPro: Bool) -> TapStrength {
        isPro ? stored : .standard
    }
}

// MARK: - Boundary patterns

/// One tap of a boundary's pattern, timed from the moment the boundary is announced.
struct HapticStep: Equatable, Sendable {
    let offset: Duration
    let type: WKHapticType
}

/// Everything one boundary will play, decided up front so the timing rules are testable
/// without a Taptic Engine.
struct BoundaryPlan: Equatable, Sendable {
    var steps: [HapticStep]
    /// Countdown seconds (3, 2, 1) of this phase that would land inside the burst. They
    /// stay silent: a new `play(_:)` stops the tap in progress, so a click there would cut
    /// the burst short and blur into it.
    var suppressedCountdown: Set<Int>
}

extension Haptics {

    // Starting values, estimated from the system tones rather than measured on a Taptic
    // Engine. Every rule below is written in terms of them, so tuning one on a device keeps
    // the guarantees.

    /// Worst case between a boundary and the tick that notices it: the ticker runs every 500 ms.
    static let tickLatency: TimeInterval = 0.5
    /// Quiet time kept between the end of a burst and the next cue, so the two stay distinct.
    static let quietGap: TimeInterval = 0.2
    /// A boundary announced later than this is a catch-up after a suspension. It taps once:
    /// a burst for a moment that has already passed would only confuse.
    static let lateThreshold: TimeInterval = 1.0

    /// Start-to-start spacing of a repeated tap. The notification pattern is the longest of
    /// the boundary taps, so it needs the most room to be felt as separate taps.
    static func repeatSpacing(for type: WKHapticType) -> TimeInterval {
        switch type {
        case .notification: 1.0
        case .success: 0.8
        default: 0.6
        }
    }

    /// How long one tap is felt for, which a burst has to finish inside its phase.
    static func patternLength(for type: WKHapticType) -> TimeInterval {
        switch type {
        case .notification: 0.8
        case .success: 0.55
        default: 0.4
        }
    }

    /// The taps for one engine event at `strength`.
    ///
    /// - Standard, and any catch-up, is exactly one tap at offset zero.
    /// - A repeat is dropped if, noticed at the worst tick latency, it could not finish with
    ///   a quiet gap to spare before the phase ends, so a burst never bleeds into the next
    ///   boundary.
    /// - A countdown second is suppressed when it would land inside the burst, judged from
    ///   the phase start at the worst latency, so a preset feels the same every round.
    /// - A countdown is never a burst: the player clicks once or not at all.
    static func plan(
        for event: TimerEvent, strength: TapStrength, context: BoundaryContext
    ) -> BoundaryPlan {
        let type: WKHapticType
        switch event {
        case .phaseBegan(let phase): type = boundaryType(for: phase.kind)
        case .finished: type = .success
        case .countdown: return BoundaryPlan(steps: [], suppressedCountdown: [])
        }
        let taps = context.lateness > lateThreshold ? 1 : strength.taps
        let spacing = repeatSpacing(for: type)
        let length = patternLength(for: type)

        var steps = [HapticStep(offset: .zero, type: type)]
        for index in 1..<taps {
            let offset = Double(index) * spacing
            let ends = tickLatency + offset + length + quietGap
            if let duration = context.phaseDuration, ends > duration { break }
            steps.append(HapticStep(offset: .milliseconds(Int((offset * 1000).rounded())), type: type))
        }

        var suppressed: Set<Int> = []
        if steps.count > 1, let duration = context.phaseDuration {
            let burstEnd = tickLatency + Double(steps.count - 1) * spacing + length + quietGap
            for second in 1...3 where duration - Double(second) < burstEnd {
                suppressed.insert(second)
            }
        }
        return BoundaryPlan(steps: steps, suppressedCountdown: suppressed)
    }
}
