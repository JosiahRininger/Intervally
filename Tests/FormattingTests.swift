//
//  FormattingTests.swift
//  IntervallyTests
//

import Testing
import Foundation
@testable import Intervally

@Suite("Duration formatting")
struct DurationFormatTests {

    @Test("Under a minute reads as bare seconds", arguments: [0, 1, 5, 30, 59])
    func subMinute(seconds: Int) {
        #expect(DurationFormat.clock(seconds) == "\(seconds)s")
    }

    @Test("A minute and over reads as m:ss with a padded seconds field")
    func minutesAndSeconds() {
        #expect(DurationFormat.clock(60) == "1:00")
        #expect(DurationFormat.clock(61) == "1:01")
        #expect(DurationFormat.clock(90) == "1:30")
        #expect(DurationFormat.clock(119) == "1:59")
        #expect(DurationFormat.clock(600) == "10:00")
        #expect(DurationFormat.clock(3599) == "59:59")
    }

    @Test("An hour keeps counting in minutes rather than wrapping to zero")
    func pastAnHour() {
        // The ranges allow 3600s work intervals, so an hour has to render sensibly and
        // must not wrap back to "0:00".
        #expect(DurationFormat.clock(3600) == "60:00")
        #expect(DurationFormat.clock(3661) == "61:01")
    }

    @Test("Round counts are pluralised")
    func rounds() {
        #expect(DurationFormat.rounds(1) == "1 round")
        #expect(DurationFormat.rounds(0) == "0 rounds")
        #expect(DurationFormat.rounds(2) == "2 rounds")
        #expect(DurationFormat.rounds(99) == "99 rounds")
    }

    @Test("Spoken durations are non-empty and mention the unit, for VoiceOver")
    func spoken() {
        let short = DurationFormat.spoken(45)
        #expect(short.isEmpty == false)
        #expect(short.contains("45"))

        let long = DurationFormat.spoken(90)
        #expect(long.isEmpty == false)
        #expect(long.contains("1"))
    }

    @Test("A bookend at zero reads Off in every form, never a 0s phase")
    func bookendOff() {
        #expect(DurationFormat.bookend(0) == "Off")
        #expect(DurationFormat.bookendEditor(0) == "Off")
        #expect(DurationFormat.bookendSpoken(0) == "Off")
    }

    @Test("A bookend that is on reads like any other duration", arguments: [30, 45, 300, 1800])
    func bookendOn(seconds: Int) {
        #expect(DurationFormat.bookend(seconds) == DurationFormat.clock(seconds))
        #expect(DurationFormat.bookendEditor(seconds) == DurationFormat.bare(seconds))
        #expect(DurationFormat.bookendSpoken(seconds) == DurationFormat.spoken(seconds))
    }
}

@Suite("Workout configuration")
struct IntervalWorkoutTests {

    @Test("Total seconds excludes the trailing rest")
    func totalExcludesTrailingRest() {
        let workout = IntervalWorkout(
            prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 8
        )
        // 10 + 8*30 + 7*15 — seven rests, not eight.
        #expect(workout.totalSeconds == 355)
    }

    @Test("Total seconds agrees with the plan the workout actually builds", arguments: [
        IntervalWorkout(prepareSeconds: 0, workSeconds: 5, restSeconds: 0, rounds: 1),
        IntervalWorkout(prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 8),
        IntervalWorkout(prepareSeconds: 60, workSeconds: 120, restSeconds: 5, rounds: 3),
        IntervalWorkout(prepareSeconds: 5, workSeconds: 5, restSeconds: 5, rounds: 99),
        IntervalWorkout(prepareSeconds: 10, warmupSeconds: 300, workSeconds: 30, restSeconds: 15, rounds: 8, cooldownSeconds: 240),
        IntervalWorkout(prepareSeconds: 0, warmupSeconds: 60, workSeconds: 20, restSeconds: 0, rounds: 1),
        IntervalWorkout(prepareSeconds: 0, workSeconds: 20, restSeconds: 10, rounds: 4, cooldownSeconds: 1800),
    ])
    func totalMatchesPlan(workout: IntervalWorkout) {
        // These two are computed independently; if they ever disagree the setup screen is
        // advertising a duration the run does not honour.
        #expect(IntervalPlan(workout: workout).totalDuration == TimeInterval(workout.totalSeconds))
    }

    @Test("A single round has no rest at all in its total")
    func singleRoundHasNoRest() {
        let workout = IntervalWorkout(
            prepareSeconds: 0, workSeconds: 40, restSeconds: 999, rounds: 1
        )
        #expect(workout.totalSeconds == 40)
    }

    @Test("Clamping pulls every field into range")
    func clamping() {
        let wild = IntervalWorkout(
            prepareSeconds: -100, workSeconds: 100_000, restSeconds: -1, rounds: 10_000
        ).clamped

        #expect(wild.prepareSeconds == IntervalWorkout.prepareRange.lowerBound)
        #expect(wild.workSeconds == IntervalWorkout.workRange.upperBound)
        #expect(wild.restSeconds == IntervalWorkout.restRange.lowerBound)
        #expect(wild.rounds == IntervalWorkout.roundsRange.upperBound)
    }

    @Test("Clamping an in-range workout changes nothing")
    func clampingIsIdempotent() {
        let workout = IntervalWorkout(
            prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 8
        )
        #expect(workout.clamped == workout)
        #expect(workout.clamped.clamped == workout.clamped)
    }

    @Test("A workout round-trips through Codable unchanged")
    func codableRoundTrip() throws {
        let workout = IntervalWorkout(
            name: "Sprints", prepareSeconds: 5, workSeconds: 15, restSeconds: 45, rounds: 6
        )
        let data = try JSONEncoder().encode(workout)
        let decoded = try JSONDecoder().decode(IntervalWorkout.self, from: data)
        #expect(decoded == workout)
    }

    @Test("The largest allowed workout does not overflow into nonsense")
    func maximumWorkout() {
        let biggest = IntervalWorkout(
            prepareSeconds: IntervalWorkout.prepareRange.upperBound,
            workSeconds: IntervalWorkout.workRange.upperBound,
            restSeconds: IntervalWorkout.restRange.upperBound,
            rounds: IntervalWorkout.roundsRange.upperBound
        )
        let plan = IntervalPlan(workout: biggest)
        #expect(plan.totalDuration > 0)
        #expect(plan.totalDuration == TimeInterval(biggest.totalSeconds))
        #expect(plan.phases.count == 1 + 99 + 98)
        // Still resolvable at the far end rather than running off the end of the search.
        #expect(plan.position(atElapsed: plan.totalDuration - 1).isFinished == false)
    }

    @Test("Bare values drop the unit suffix the editor already captions")
    func bareValues() {
        #expect(DurationFormat.bare(45) == "45")
        #expect(DurationFormat.bare(0) == "0")
        #expect(DurationFormat.bare(60) == "1:00")
        #expect(DurationFormat.bare(95) == "1:35")
    }

    @Test("A workout's rhythm leaves out a rest it doesn't have")
    func rhythm() {
        #expect(IntervalWorkout(prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 8).rhythm == "30s · 15s · 8×")
        #expect(IntervalWorkout(prepareSeconds: 0, workSeconds: 60, restSeconds: 0, rounds: 10).rhythm == "1:00 · 10×")
    }

    @Test("Timer format switches to h:mm:ss from an hour, like Text(timerInterval:)")
    func timerHours() {
        #expect(DurationFormat.timer(59) == "0:59")
        #expect(DurationFormat.timer(3599) == "59:59")
        #expect(DurationFormat.timer(3600) == "1:00:00")
        #expect(DurationFormat.timer(713_400) == "198:10:00")
        #expect(DurationFormat.timer(-5) == "0:00")
    }
}

@Suite("Workout warmup and cooldown")
struct IntervalWorkoutBookendTests {

    private let withBookends = IntervalWorkout(
        name: "Long", prepareSeconds: 10, warmupSeconds: 300,
        workSeconds: 30, restSeconds: 15, rounds: 8, cooldownSeconds: 240
    )

    @Test("Both bookends survive a Codable round trip")
    func codableRoundTrip() throws {
        // `encode(to:)` is synthesised from CodingKeys: a key left out there would make the
        // value silently never save, and this is the only test that would notice.
        let data = try JSONEncoder().encode(withBookends)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["warmupSeconds"] as? Int == 300)
        #expect(json["cooldownSeconds"] as? Int == 240)
        #expect(try JSONDecoder().decode(IntervalWorkout.self, from: data) == withBookends)
    }

    @Test("A preset saved before bookends existed decodes with both off")
    func legacyJSONDecodesOff() throws {
        let legacy = Data("""
        {"id":"3B0F8E1C-2C55-4C1B-9F4A-7E0D8C9A1B2C","name":"Classic",
         "prepareSeconds":10,"workSeconds":30,"restSeconds":15,"rounds":8}
        """.utf8)
        let decoded = try JSONDecoder().decode(IntervalWorkout.self, from: legacy)
        #expect(decoded.warmupSeconds == 0)
        #expect(decoded.cooldownSeconds == 0)
        #expect(decoded.name == "Classic")
        #expect(decoded.workSeconds == 30 && decoded.restSeconds == 15 && decoded.rounds == 8)
        #expect(decoded.hasBookends == false)
    }

    @Test("Both bookends clamp into zero to thirty minutes")
    func clamping() {
        let low = IntervalWorkout(warmupSeconds: -60, cooldownSeconds: -1).clamped
        #expect(low.warmupSeconds == 0)
        #expect(low.cooldownSeconds == 0)

        let high = IntervalWorkout(warmupSeconds: 10_000, cooldownSeconds: 1801).clamped
        #expect(high.warmupSeconds == IntervalWorkout.warmupRange.upperBound)
        #expect(high.cooldownSeconds == IntervalWorkout.cooldownRange.upperBound)
        #expect(IntervalWorkout.warmupRange == 0...1800)
        #expect(IntervalWorkout.cooldownRange == 0...1800)
    }

    @Test("The total counts both bookends and agrees with the plan")
    func totalIncludesBookends() {
        // 10 + 300 + 8*30 + 7*15 + 240
        #expect(withBookends.totalSeconds == 895)
        #expect(IntervalPlan(workout: withBookends).totalDuration == TimeInterval(withBookends.totalSeconds))
    }

    @Test("The largest workout with both bookends has exactly two more phases")
    func maximumWithBookends() {
        let biggest = IntervalWorkout(
            prepareSeconds: IntervalWorkout.prepareRange.upperBound,
            warmupSeconds: IntervalWorkout.warmupRange.upperBound,
            workSeconds: IntervalWorkout.workRange.upperBound,
            restSeconds: IntervalWorkout.restRange.upperBound,
            rounds: IntervalWorkout.roundsRange.upperBound,
            cooldownSeconds: IntervalWorkout.cooldownRange.upperBound
        )
        let plan = IntervalPlan(workout: biggest)
        #expect(plan.phases.count == 1 + 99 + 98 + 2)
        #expect(plan.totalDuration == TimeInterval(biggest.totalSeconds))
        #expect(plan.position(atElapsed: plan.totalDuration - 1).phase?.kind == .cooldown)
    }

    @Test("Either bookend alone counts as having bookends")
    func hasBookends() {
        #expect(IntervalWorkout().hasBookends == false)
        #expect(IntervalWorkout(warmupSeconds: 30).hasBookends)
        #expect(IntervalWorkout(cooldownSeconds: 30).hasBookends)
    }

    @Test("Without Pro the bookends are zeroed in the copy that runs, not in the preset")
    func effectiveWithoutPro() {
        let preset = withBookends
        let runs = preset.effective(isPro: false)
        #expect(runs.warmupSeconds == 0)
        #expect(runs.cooldownSeconds == 0)
        // Everything else is the preset as built.
        #expect(runs.id == preset.id && runs.name == preset.name)
        #expect(runs.prepareSeconds == 10 && runs.workSeconds == 30 && runs.restSeconds == 15 && runs.rounds == 8)
        // The stored values are untouched, so a restored purchase brings them back.
        #expect(preset.warmupSeconds == 300)
        #expect(preset.cooldownSeconds == 240)
    }

    @Test("With Pro, or with no bookends to drop, the workout runs as built")
    func effectiveIsIdentityOtherwise() {
        #expect(withBookends.effective(isPro: true) == withBookends)
        let plain = IntervalWorkout(prepareSeconds: 5, workSeconds: 20, restSeconds: 10, rounds: 4)
        #expect(plain.effective(isPro: false) == plain)
        #expect(plain.effective(isPro: true) == plain)
    }

    @Test("The rhythm is the intervals alone; the bookends never join it")
    func rhythmIgnoresBookends() {
        #expect(withBookends.rhythm == "30s · 15s · 8×")
    }
}
