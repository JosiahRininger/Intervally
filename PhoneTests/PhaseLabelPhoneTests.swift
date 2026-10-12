//
//  PhaseLabelPhoneTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
import UIKit
@testable import IntervallyPhone

/// Names and figures on iPhone: the editor, the voice coach, the Lock Screen and History;
/// and the duration wheels and the cues' sound.
@Suite("Phase labels on iPhone")
@MainActor
struct PhaseLabelPhoneTests {
    private var running: IntervalWorkout {
        var workout = IntervalWorkout(name: "Run Walk", workSeconds: 60, restSeconds: 90, rounds: 4)
        workout.setLabel(PhaseLabel(name: "Run", symbol: .run), for: .work)
        workout.setLabel(PhaseLabel(name: "Walk", symbol: .walk), for: .rest)
        return workout
    }

    @Test("Every figure is a real SF Symbol", arguments: PhaseSymbol.allCases)
    func symbolsExist(_ symbol: PhaseSymbol) {
        #expect(UIImage(systemName: symbol.systemName) != nil, "\(symbol.systemName)")
    }

    @Test("The icon grid: the phase's own first, then sixteen in all, no other phase's")
    func iconGrid() {
        let work = PhaseLabelPicker.symbols(for: .work)
        #expect(work.first == .bolt)
        #expect(work.count == 16)
        #expect(!work.contains(.wind) && !work.contains(.sunrise))
        #expect(PhaseLabelPicker.symbols(for: .rest).first == .wind)
    }

    @Test("The editor's tiles carry the preset's names and figures")
    func tiles() {
        let work = EditorTileContent(field: .work, workout: running, isPro: true)
        #expect(work.title == "Run")
        #expect(work.symbolName == "figure.run")
        let rounds = EditorTileContent(field: .rounds, workout: running, isPro: true)
        #expect(rounds.title == "Rounds")
    }

    @Test("The voice coach says the preset's names, and still says Last round")
    func voice() {
        let plan = IntervalPlan(workout: running)
        let work = plan.phases.first { $0.kind == .work && $0.round == 1 }!
        let rest = plan.phases.first { $0.kind == .rest }!
        let last = plan.phases.last { $0.kind == .work }!
        #expect(CuePlan.phrase(for: work, totalRounds: 4) == "Run")
        #expect(CuePlan.phrase(for: rest, totalRounds: 4) == "Walk")
        #expect(CuePlan.phrase(for: last, totalRounds: 4) == "Last round")
    }

    @Test("The Lock Screen says the preset's names for the phase and the next")
    func liveActivity() throws {
        let plan = IntervalPlan(workout: running)
        let gettingReady = try #require(RunPresentation(plan: plan, status: .running, anchor: Date(), elapsed: 2))
        let first = RunActivityAttributes.ContentState(gettingReady, theme: .classic)
        #expect(first.phase == .prepare)
        #expect(first.phaseName == nil, "Get Ready keeps its own name")
        #expect(first.nextName == "Run")
        let working = try #require(RunPresentation(plan: plan, status: .running, anchor: Date(), elapsed: 15))
        let second = RunActivityAttributes.ContentState(working, theme: .classic)
        #expect(second.phaseName == "Run")
        #expect(second.nextName == "Walk")
    }

    @Test("History names an interval as it was called when it ran")
    func history() {
        let raw = RawWorkout(
            id: UUID(), start: Date(), duration: 150, presetName: "Run Walk", plannedRounds: 1,
            averageHeartRate: nil, maximumHeartRate: nil, activeEnergy: nil,
            activities: [
                RawWorkout.Activity(phase: "work", round: 1, start: Date(), duration: 60, averageHeartRate: nil, phaseName: "Run", phaseSymbol: "run"),
                RawWorkout.Activity(phase: "rest", round: 1, start: Date().addingTimeInterval(60), duration: 90, averageHeartRate: nil),
            ]
        )
        let intervals = SessionSummary(raw).intervals
        #expect(intervals[0].title == "Run · Round 1")
        #expect(intervals[0].symbolName == "figure.run")
        #expect(intervals[1].title == "Rest · Round 1")
    }

    @Test("Duration wheels: minutes to the top, seconds by fives, kept to the field's range")
    func wheels() {
        #expect(DurationWheels.minutes(for: .work) == Array(0...60))
        #expect(DurationWheels.minutes(for: .prepare) == Array(0...5))
        #expect(DurationWheels.secondSteps.count == 12)
        #expect(DurationWheels.split(125) == (2, 5))
        #expect(DurationWheels.split(7) == (0, 5), "Off the grid, shown at the five below")
        #expect(DurationWheels.value(minutes: 2, seconds: 5, field: .work) == 125, "Past two minutes, still to the five seconds")
        #expect(DurationWheels.value(minutes: 0, seconds: 0, field: .work) == 5, "Work's shortest")
        #expect(DurationWheels.value(minutes: 60, seconds: 30, field: .rest) == 3600, "The top minute takes no seconds")
        #expect(DurationWheels.value(minutes: 0, seconds: 0, field: .cooldown) == 0, "Off")
    }

    @Test("Lower Music is on until turned off, and every cue says so to the output")
    func lowerMusic() {
        let defaults = makeTestDefaults()
        #expect(CueSettings.stored(in: defaults).lowerMusic)
        let output = FakeCueOutput()
        let player = PhoneCuePlayer(output: output, pro: FakePro(), defaults: defaults)
        defaults.set(false, forKey: CueSettings.Key.lowerMusic)
        player.preview()
        #expect(output.lowersOtherAudio == false)
        defaults.set(true, forKey: CueSettings.Key.lowerMusic)
        player.preview()
        #expect(output.lowersOtherAudio == true)
    }

    @Test("The tones are richer but never clip, peaking where they're set")
    func tones() {
        for tone in CueTone.allCases {
            let samples = ToneSynth.samples(for: tone)
            let peak = samples.map { abs(Int($0)) }.max() ?? 0
            #expect(peak <= Int(Int16.max))
            #expect(Double(peak) / Double(Int16.max) > 0.88, "\(tone) reaches its 0.9")
        }
        #expect(ToneSynth.partials.count >= 4, "Harmonics up through 1 to 4 kHz")
    }

    @Test("A rendered phrase becomes a playable WAV; silence becomes nothing")
    func spokenWAV() {
        #expect(SpokenPCM().wav() == nil)
        let pcm = SpokenPCM(sampleRate: 22_050, samples: Array(repeating: 0.5, count: 2_205))
        let data = pcm.wav()
        #expect(data?.prefix(4) == Data("RIFF".utf8))
        #expect(data?.count == 44 + 2_205 * 2)
    }
}
