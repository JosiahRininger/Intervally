//
//  RunFooterTests.swift
//  IntervallyTests
//

import Testing
import Foundation
@testable import Intervally

/// What the run screen shows beneath the countdown, and what VoiceOver reads for the dial.
@Suite("Run screen round footer")
struct RoundFooterTests {

    @Test("An interval phase fills the rounds behind it and lights its own")
    func workRound() {
        let footer = RoundFooter(kind: .work, round: 3, totalRounds: 8)
        #expect(footer.dots == [.done, .done, .current, .upcoming, .upcoming, .upcoming, .upcoming, .upcoming])
        #expect(footer.text == "3 of 8")
        #expect(footer.compactText == "3/8")
        #expect(footer.accessibilityLabel == "Round 3 of 8")
    }

    @Test("The lead-in reads as round 1, as it always has")
    func prepareUnchanged() {
        let footer = RoundFooter(kind: .prepare, round: 1, totalRounds: 4)
        #expect(footer.dots == [.current, .upcoming, .upcoming, .upcoming])
        #expect(footer.text == "1 of 4")
        #expect(footer.compactText == "1/4")
    }

    @Test("In the warmup no round has started: every dot dim, and the count to come")
    func warmup() {
        let footer = RoundFooter(kind: .warmup, round: 1, totalRounds: 8)
        #expect(footer.dots == Array(repeating: .upcoming, count: 8))
        #expect(footer.text == "8 rounds")
        #expect(footer.compactText == "8×")
        #expect(footer.accessibilityLabel == "8 rounds")
    }

    @Test("In the cooldown every round is done: every dot filled, and all of them")
    func cooldown() {
        let footer = RoundFooter(kind: .cooldown, round: 8, totalRounds: 8)
        #expect(footer.dots == Array(repeating: .done, count: 8))
        #expect(footer.text == "8 of 8")
        #expect(footer.compactText == "8/8")
        #expect(footer.accessibilityLabel == "All 8 rounds done")
    }

    @Test("Ten rounds still get dots; more fall back to text, bookends included")
    func dotLimit() {
        #expect(RoundFooter(kind: .work, round: 1, totalRounds: 10).dots?.count == 10)
        #expect(RoundFooter(kind: .work, round: 1, totalRounds: 11).dots == nil)

        let warmup = RoundFooter(kind: .warmup, round: 1, totalRounds: 20)
        #expect(warmup.dots == nil)
        #expect(warmup.text == "20 rounds")
        #expect(warmup.compactText == "20×")

        let cooldown = RoundFooter(kind: .cooldown, round: 20, totalRounds: 20)
        #expect(cooldown.dots == nil)
        #expect(cooldown.text == "20 of 20")
    }

    @Test("A single-round warmup says round, not rounds")
    func singleRoundWarmup() {
        #expect(RoundFooter(kind: .warmup, round: 1, totalRounds: 1).text == "1 round")
    }

    @Test("A round outside the workout is clamped rather than drawn as nonsense")
    func clampsRound() {
        #expect(RoundFooter(kind: .work, round: 0, totalRounds: 3).text == "1 of 3")
        #expect(RoundFooter(kind: .rest, round: 9, totalRounds: 3).text == "3 of 3")
        #expect(RoundFooter(kind: .rest, round: 9, totalRounds: 3).dots == [.done, .done, .current])
    }
}

@Suite("Run screen VoiceOver summary")
struct RunAccessibilitySummaryTests {

    private func phase(_ kind: IntervalPhase.Kind, round: Int) -> IntervalPhase {
        IntervalPhase(id: 0, kind: kind, duration: 300, round: round, start: 0)
    }

    private func summary(_ kind: IntervalPhase.Kind, round: Int = 1, remaining: Int, paused: Bool = false) -> String {
        RunView.accessibilitySummary(
            phase: phase(kind, round: round), remainingSeconds: remaining, isPaused: paused, totalRounds: 8
        )
    }

    @Test("The warmup and cooldown name themselves, with no round")
    func bookends() {
        #expect(summary(.warmup, remaining: 240) == "Warmup, \(DurationFormat.spoken(240)) remaining")
        #expect(summary(.cooldown, round: 8, remaining: 180)
            == "Cooldown, intervals done, \(DurationFormat.spoken(180)) remaining")
    }

    @Test("The lead-in and the intervals read as they always have")
    func intervals() {
        #expect(summary(.prepare, remaining: 10) == "Get ready, \(DurationFormat.spoken(10)) remaining")
        #expect(summary(.work, round: 3, remaining: 30) == "Work, round 3 of 8, \(DurationFormat.spoken(30)) remaining")
        #expect(summary(.rest, round: 3, remaining: 15) == "Rest, round 3 of 8, \(DurationFormat.spoken(15)) remaining")
    }

    @Test("Paused says so first, in every phase")
    func paused() {
        #expect(summary(.warmup, remaining: 60, paused: true).hasPrefix("Paused. Warmup, "))
        #expect(summary(.cooldown, remaining: 60, paused: true).hasPrefix("Paused. Cooldown, "))
        #expect(summary(.work, round: 2, remaining: 60, paused: true).hasPrefix("Paused. Work, round 2 of 8"))
    }

    @Test("A finished run reads as complete")
    func finished() {
        #expect(RunView.accessibilitySummary(phase: nil, remainingSeconds: 0, isPaused: false, totalRounds: 8)
            == "Workout complete")
    }
}
