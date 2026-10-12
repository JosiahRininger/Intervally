//
//  PhaseLabelTests.swift
//  IntervallyTests
//

import Foundation
import HealthKit
import Testing
@testable import Intervally

/// A preset's own names and figures for its phases: how they are set, stored, synced, and
/// carried into the run and Health.
@Suite("Phase labels")
struct PhaseLabelTests {
    @Test("A phase keeps its own name and figure until the preset gives it others")
    func defaults() {
        let workout = IntervalWorkout()
        #expect(workout.label(for: .work) == PhaseLabel(name: "Work", symbol: .bolt))
        #expect(workout.label(for: .rest) == PhaseLabel(name: "Rest", symbol: .wind))
        #expect(workout.label(for: .prepare).symbol == .hourglass)
        #expect(!workout.hasCustomLabel(for: .work))
    }

    @Test("Names are trimmed and cut to fit; an empty one keeps the phase's own")
    func cleaning() {
        #expect(PhaseLabel.cleaned("  Run  ") == "Run")
        #expect(PhaseLabel.cleaned("Sprint as hard as you can") == "Sprint as", "Cut, then trimmed again")
        #expect(PhaseLabel.cleaned("Recovery Jog") == "Recovery J", "Ten letters: the top of a 40mm ring")
        #expect(PhaseLabel.cleaned("   ") == nil)
    }

    @Test("Setting, changing only the figure, and putting back")
    func setting() {
        var workout = IntervalWorkout()
        workout.setLabel(PhaseLabel(name: " Run ", symbol: .run), for: .work)
        #expect(workout.label(for: .work) == PhaseLabel(name: "Run", symbol: .run))
        #expect(workout.hasCustomLabel(for: .work))

        // A blank name with a new figure keeps the phase's name.
        workout.setLabel(PhaseLabel(name: "", symbol: .breathe), for: .rest)
        #expect(workout.label(for: .rest) == PhaseLabel(name: "Rest", symbol: .breathe))

        // The phase's own name and figure, or nil, put it back: emptied, never nil again.
        workout.setLabel(PhaseLabel(name: "Work", symbol: .bolt), for: .work)
        workout.setLabel(nil, for: .rest)
        #expect(!workout.hasCustomLabel(for: .work))
        #expect(!workout.hasCustomLabel(for: .rest))
        #expect(workout.phaseLabels == [:])
    }

    @Test("The plan's phases carry the labels: title and figure")
    func planCarriesLabels() {
        var workout = IntervalWorkout(prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 2)
        workout.setLabel(PhaseLabel(name: "Run", symbol: .run), for: .work)
        let plan = IntervalPlan(workout: workout)
        let work = plan.phases.first { $0.kind == .work }
        let rest = plan.phases.first { $0.kind == .rest }
        #expect(work?.title == "Run")
        #expect(work?.symbol == .run)
        #expect(rest?.title == "Rest")
        #expect(rest?.label == nil)
    }

    @Test("Stored and read back; a preset from before labels has none, and one bad label costs only itself")
    func coding() throws {
        var workout = IntervalWorkout(name: "Hills")
        workout.setLabel(PhaseLabel(name: "Climb", symbol: .run), for: .work)
        let decoded = try JSONDecoder().decode(IntervalWorkout.self, from: JSONEncoder().encode(workout))
        #expect(decoded == workout)

        let old = Data(#"{"id":"2F1F7C1C-1E5F-4C0B-9C4F-6A0C1D2E3F40","name":"Old"}"#.utf8)
        let before = try JSONDecoder().decode(IntervalWorkout.self, from: old)
        #expect(before.phaseLabels == nil)
        #expect(try String(data: JSONEncoder().encode(before), encoding: .utf8)?.contains("phaseLabels") == false)

        let mixed = Data(#"{"id":"2F1F7C1C-1E5F-4C0B-9C4F-6A0C1D2E3F40","phaseLabels":{"work":{"name":"Run","symbol":"run"},"rest":{"name":"Walk","symbol":"unicycle"}}}"#.utf8)
        let lenient = try JSONDecoder().decode(IntervalWorkout.self, from: mixed)
        #expect(lenient.label(for: .work) == PhaseLabel(name: "Run", symbol: .run))
        #expect(lenient.label(for: .rest) == PhaseLabel(name: "Rest", symbol: .wind))
    }

    @Test("A later edit from a version without labels keeps the ones set here; a later reset wins")
    func merge() {
        var mine = IntervalWorkout(name: "Hills")
        mine.setLabel(PhaseLabel(name: "Climb", symbol: .run), for: .work)
        var theirs = mine
        theirs.phaseLabels = nil
        theirs.rounds = 10
        func record(_ workout: IntervalWorkout, _ millis: Int64) -> PresetRecord {
            PresetRecord(id: workout.id, workout: workout, deleted: false, order: 0, stamp: SyncStamp(millis: millis, device: "d\(millis)"))
        }
        let kept = record(mine, 100).merged(with: record(theirs, 200))
        #expect(kept.workout.rounds == 10)
        #expect(kept.workout.label(for: .work).name == "Climb")

        var reset = mine
        reset.setLabel(nil, for: .work)
        let cleared = record(mine, 100).merged(with: record(reset, 200))
        #expect(!cleared.workout.hasCustomLabel(for: .work), "An emptied set is a reset, not a version without labels")
    }

    /// The iPhone named a phase at 5 while the watch, out of range, changed rounds at 6. The
    /// iPhone's merge keeps its name on the watch's write at 6; the watch, holding that write
    /// without it, gets it back at the same stamp. Both must settle on the same record, or
    /// each keeps its own on the tie and they push it back and forth for good.
    @Test("At the same stamp, a copy without the activity or names takes them from one with")
    func tieConverges() {
        let id = UUID()
        var named = IntervalWorkout(id: id, name: "Hills", rounds: 10)
        named.setLabel(PhaseLabel(name: "Climb", symbol: .run), for: .work)
        named.activity = .outdoorRun
        var bare = named
        bare.phaseLabels = nil
        bare.activity = nil
        let stamp = SyncStamp(millis: 6, device: "watch")
        let phone = PresetRecord(id: id, workout: named, deleted: false, order: 0, stamp: stamp)
        let watch = PresetRecord(id: id, workout: bare, deleted: false, order: 0, stamp: stamp)
        #expect(phone.merged(with: watch) == watch.merged(with: phone))
        #expect(watch.merged(with: phone).workout == named)
        #expect(watch.merged(with: watch) == watch, "A tie with itself changes nothing")
    }

    @Test("Each interval saved to Health keeps its name and figure, and the workout says outdoors outright")
    func healthMetadata() {
        let labelled = IntervalPhase(id: 0, kind: .work, label: PhaseLabel(name: "Run", symbol: .run), duration: 30, round: 2, start: 0)
        let metadata = WorkoutSessionController.activityMetadata(for: labelled, indoor: false)
        #expect(metadata[HealthMetadata.phaseName] as? String == "Run")
        #expect(metadata[HealthMetadata.phaseSymbol] as? String == "run")
        #expect(metadata[HKMetadataKeyIndoorWorkout] as? Bool == false)

        let plain = WorkoutSessionController.activityMetadata(for: IntervalPhase(id: 0, kind: .rest, duration: 15, round: 1, start: 0))
        #expect(plain[HealthMetadata.phaseName] == nil)

        var outdoor = IntervalWorkout(name: "Hills")
        outdoor.activity = .outdoorRun
        #expect(WorkoutSessionController.workoutMetadata(for: outdoor)[HKMetadataKeyIndoorWorkout] as? Bool == false)
        #expect(WorkoutSessionController.workoutMetadata(for: IntervalWorkout())[HKMetadataKeyIndoorWorkout] as? Bool == true)
    }

    @Test("The complication names the phase as the preset does")
    func complication() {
        let custom = RunProgress(phaseKind: .work, label: PhaseLabel(name: "Run", symbol: .run), phaseEnd: Date(), round: 3, totalRounds: 8, isPaused: false)
        #expect(custom.phaseLine == "RUN · 3 of 8")
        #expect(custom.compactLine == "Run 3/8")
        #expect(custom.symbolName == "figure.run")
        let plain = RunProgress(phaseKind: .rest, phaseEnd: Date(), round: 3, totalRounds: 8, isPaused: false)
        #expect(plain.compactLine == "Rest 3/8")
        #expect(plain.symbolName == "wind")
    }

    @Test("Get Ready reaches five minutes, and the crown still turns in sensible steps")
    func longerGetReady() {
        #expect(IntervalWorkout.prepareRange == 0...300)
        let values = PresetField.prepare.values
        #expect(values.first == 0)
        #expect(values.last == 300)
        #expect(values.contains(60) && values.contains(115) && values.contains(135))
    }
}
