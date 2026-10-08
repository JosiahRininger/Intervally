//
//  HapticPatternTests.swift
//  IntervallyTests
//

import Testing
import Foundation
import WatchKit
@testable import Intervally

/// The timing rules for stronger taps. They are what keeps a burst out of the next boundary
/// and off the 3-2-1 lead-in, so they are pinned here rather than felt for on a device.
@Suite("Haptic patterns")
struct HapticPatternTests {

    static let kinds: [IntervalPhase.Kind] = [.prepare, .warmup, .work, .rest, .cooldown]
    static let easyKinds: [IntervalPhase.Kind] = [.prepare, .warmup, .rest, .cooldown]

    /// A phase boundary as the coordinator reports it: noticed `lateness` seconds after the
    /// phase began, with the phase's own length.
    private func plan(
        _ kind: IntervalPhase.Kind,
        _ duration: TimeInterval,
        _ strength: TapStrength,
        lateness: TimeInterval = 0.3
    ) -> BoundaryPlan {
        let phase = IntervalPhase(id: 1, kind: kind, duration: duration, round: 1, start: 10)
        return Haptics.plan(
            for: .phaseBegan(phase),
            strength: strength,
            context: BoundaryContext(lateness: lateness, phaseDuration: duration)
        )
    }

    private func finishPlan(_ strength: TapStrength, lateness: TimeInterval = 0.2) -> BoundaryPlan {
        Haptics.plan(
            for: .finished, strength: strength,
            context: BoundaryContext(lateness: lateness, phaseDuration: nil)
        )
    }

    private func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }

    @Test("Standard is one tap, at once, of the phase's own type", arguments: HapticPatternTests.kinds)
    func standardIsOneTap(kind: IntervalPhase.Kind) {
        for duration: TimeInterval in [1, 5, 60] {
            let standard = plan(kind, duration, .standard)
            #expect(standard.steps == [HapticStep(offset: .zero, type: Haptics.boundaryType(for: kind))])
            #expect(standard.suppressedCountdown.isEmpty)
        }
        #expect(finishPlan(.standard).steps == [HapticStep(offset: .zero, type: .success)])
    }

    @Test("Strong and Strongest repeat at the pattern's spacing on a long phase")
    func repeatsAtTheirSpacing() {
        #expect(plan(.work, 60, .strong).steps.map(\.offset) == [.zero, .seconds(1)])
        #expect(plan(.work, 60, .strongest).steps.map(\.offset) == [.zero, .seconds(1), .seconds(2)])
        for kind in Self.easyKinds {
            let strongest = plan(kind, 60, .strongest)
            #expect(strongest.steps.map(\.offset) == [.zero, .milliseconds(600), .milliseconds(1200)])
            #expect(strongest.steps.allSatisfy { $0.type == Haptics.boundaryType(for: kind) })
            #expect(plan(kind, 60, .strong).steps.map(\.offset) == [.zero, .milliseconds(600)])
        }
        #expect(finishPlan(.strongest).steps == [0, 800, 1600].map {
            HapticStep(offset: .milliseconds($0), type: .success)
        })
        #expect(finishPlan(.strongest).suppressedCountdown.isEmpty, "Nothing counts down after the finish")
    }

    @Test("A burst ends 0.7 s before its phase does, so even noticed half a second late it is clear of the next boundary",
          arguments: TapStrength.allCases)
    func burstFitsInsideItsPhase(strength: TapStrength) {
        for kind in Self.kinds {
            let type = Haptics.boundaryType(for: kind)
            for duration in 1...10 {
                let burst = plan(kind, TimeInterval(duration), strength)
                #expect((1...strength.taps).contains(burst.steps.count))
                guard burst.steps.count > 1, let last = burst.steps.last else { continue }
                let ends = seconds(last.offset) + Haptics.patternLength(for: type)
                #expect(ends <= TimeInterval(duration) - 0.7, "\(kind), \(duration) s, \(strength)")
            }
        }
    }

    @Test("Short phases trim the burst but never the boundary's own tap")
    func shortPhasesTrim() {
        #expect(plan(.work, 1, .strongest).steps.count == 1)
        #expect(plan(.work, 3, .strongest).steps.count == 2, "0.5 + 1.0 + 0.8 + 0.2 fits in 3 s; the third tap would not")
        #expect(plan(.rest, 2, .strongest).steps.count == 2, "0.5 + 0.6 + 0.4 + 0.2 fits in 2 s; the third tap would not")
        #expect(plan(.rest, 1, .strong).steps.count == 1)
    }

    @Test("On a 5 s phase the burst silences exactly the countdown seconds it would overlap")
    func fiveSecondSuppression() {
        #expect(plan(.work, 5, .strong).suppressedCountdown == [3])
        #expect(plan(.work, 5, .strongest).suppressedCountdown == [2, 3])
        for kind in Self.easyKinds {
            #expect(plan(kind, 5, .strong).suppressedCountdown.isEmpty, "\(kind)")
            #expect(plan(kind, 5, .strongest).suppressedCountdown == [3], "\(kind)")
        }
        for kind in Self.kinds {
            #expect(plan(kind, 5, .standard).suppressedCountdown.isEmpty, "Standard never touches the countdown")
        }
    }

    @Test("A 10 s phase keeps every tap and every countdown second", arguments: TapStrength.allCases)
    func tenSecondsKeepEverything(strength: TapStrength) {
        for kind in Self.kinds {
            let burst = plan(kind, 10, strength)
            #expect(burst.steps.count == strength.taps)
            #expect(burst.suppressedCountdown.isEmpty)
        }
    }

    @Test("Suppression is judged at the worst latency, so every round of a preset feels the same")
    func suppressionIgnoresActualLateness() {
        #expect(plan(.work, 5, .strongest, lateness: 0).suppressedCountdown == [2, 3])
        #expect(plan(.work, 5, .strongest, lateness: 0.5).suppressedCountdown == [2, 3])
    }

    @Test("A boundary noticed more than a second late taps once, and leaves the countdown alone")
    func lateBoundaryTapsOnce() {
        for kind in Self.kinds {
            let late = plan(kind, 5, .strongest, lateness: 1.5)
            #expect(late.steps == [HapticStep(offset: .zero, type: Haptics.boundaryType(for: kind))])
            #expect(late.suppressedCountdown.isEmpty)
        }
        #expect(finishPlan(.strongest, lateness: 30).steps == [HapticStep(offset: .zero, type: .success)])
        #expect(plan(.work, 60, .strongest, lateness: 1.0).steps.count == 3, "Exactly a second late is still on time")
    }

    @Test("A countdown is never a burst", arguments: TapStrength.allCases)
    func countdownNeverBursts(strength: TapStrength) {
        for second in 1...3 {
            let tick = Haptics.plan(for: .countdown(secondsRemaining: second), strength: strength, context: .immediate)
            #expect(tick == BoundaryPlan(steps: [], suppressedCountdown: []))
        }
    }

    @Test("Each strength names its taps, and its raw value never changes")
    func vocabulary() {
        #expect(TapStrength.allCases.map(\.taps) == [1, 2, 3])
        #expect(TapStrength.allCases.map(\.title) == ["Standard", "Strong", "Strongest"])
        #expect(TapStrength.allCases.map(\.detail) == ["One tap", "Two taps", "Three taps"])
        // Persisted in the shared defaults.
        #expect(TapStrength.allCases.map(\.rawValue) == ["standard", "strong", "strongest"])
    }
}
