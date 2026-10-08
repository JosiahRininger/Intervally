//
//  QAPresetTests.swift
//  IntervallyTests
//

#if DEBUG
import Testing
import Foundation
@testable import Intervally

/// The Debug-only `-qaPreset work,rest,rounds[,prepare[,warmup,cooldown]]` launch hook.
@Suite("QA preset launch argument")
struct QAPresetTests {

    private let base = IntervalWorkout(
        name: "Classic", prepareSeconds: 10, warmupSeconds: 0, workSeconds: 30,
        restSeconds: 15, rounds: 8, cooldownSeconds: 0
    )

    private func apply(_ spec: String) -> IntervalWorkout? {
        AppDelegate.applying(qaPreset: spec, to: base)
    }

    @Test("Three fields set work, rest and rounds and leave the rest of the preset alone")
    func threeFields() throws {
        let workout = try #require(apply("120,5,20"))
        #expect(workout.workSeconds == 120 && workout.restSeconds == 5 && workout.rounds == 20)
        #expect(workout.prepareSeconds == 10)
        #expect(workout.hasBookends == false)
        #expect(workout.id == base.id && workout.name == "Classic")
    }

    @Test("A fourth field sets the lead-in")
    func prepareField() {
        #expect(apply("120,5,20,0")?.prepareSeconds == 0)
    }

    @Test("Fifth and sixth fields set the warmup and cooldown")
    func bookendFields() throws {
        let workout = try #require(apply("120, 5, 20, 10, 300, 240"))
        #expect(workout.warmupSeconds == 300)
        #expect(workout.cooldownSeconds == 240)
        #expect(apply("120,5,20,10,300")?.warmupSeconds == 300)
        #expect(apply("120,5,20,10,300")?.cooldownSeconds == 0)
    }

    @Test("Values are clamped like any edit")
    func clamps() throws {
        let workout = try #require(apply("1,0,500,0,99999,-5"))
        #expect(workout.workSeconds == IntervalWorkout.workRange.lowerBound)
        #expect(workout.rounds == IntervalWorkout.roundsRange.upperBound)
        #expect(workout.warmupSeconds == IntervalWorkout.warmupRange.upperBound)
        #expect(workout.cooldownSeconds == 0)
    }

    @Test("Too few fields, or one that is not a number, applies nothing", arguments: [
        "", "120,5", "120,x,20", "120,5,20,abc", "120,,5,20",
    ])
    func rejectsMalformed(spec: String) {
        #expect(apply(spec) == nil)
    }
}

/// The Debug-only `-qaPro pro|free` launch hook.
@Suite("QA Pro launch argument")
struct QAProTests {

    @Test("pro and free pin the entitlement, in any case and with stray spaces", arguments: [
        ("pro", true), ("free", false), (" Pro ", true), ("FREE", false),
    ])
    func pins(spec: String, isPro: Bool) {
        #expect(AppDelegate.qaProOverride(spec) == isPro)
    }

    @Test("Anything else leaves StoreKit in charge", arguments: ["", "yes", "true", "1", "pro,free", "premium"])
    func rejectsOthers(spec: String) {
        #expect(AppDelegate.qaProOverride(spec) == nil)
    }
}
#endif
