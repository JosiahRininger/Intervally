//
//  GoldenFixtureTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// What 1.2 (13) decided and left behind on iPhone, replayed and read by this version
/// (`Fixture` has the rules): the voice coach's cues, the Live Activity's states, and a run
/// paused under 1.2 coming back.
@Suite("Golden fixtures on iPhone")
@MainActor
struct GoldenFixtureTests {

    @Test("Every cue plays as it did in 1.2, with the voice on and off, on time and late")
    func cuePlanMatches12() {
        Fixture.expect(Replay.cues(), toMatch: "cueplan.json")
    }

    @Test("The Live Activity 1.2 showed reads back running, paused and finished")
    func liveActivityStateDecodes12() throws {
        let json = Fixture.data("liveactivity-state.json")
        let states = try JSONDecoder().decode([String: RunActivityAttributes.ContentState].self, from: json)
        #expect(states == Self.liveActivityStates12)
        // Encoded again, they are exactly what 1.2 encoded: a field added since is written
        // only once it is set.
        #expect(Fixture.sameJSON(try JSONEncoder().encode(states), json))
    }

    @Test("A run paused under 1.2 comes back paused where it stopped, here and on the Lock Screen, and resumes from there")
    func pausedSnapshotRestores12() throws {
        let defaults = makeTestDefaults()
        defaults.set(Fixture.data("runsnapshot-paused.json"), forKey: WorkoutStore.Key.activeRun)
        let presenter = RecordingPresenter()
        let run = PhoneRun(
            store: WorkoutStore(defaults: defaults), pro: FakePro(), theme: ThemeStore(defaults: defaults),
            output: FakeCueOutput(), workout: FakeWorkoutSession(), notifications: FakeBackstop(),
            presenter: presenter, defaults: defaults
        )
        run.restoreAtLaunch()
        #expect(run.isPresented)

        let engine = run.coordinator.engine
        #expect(engine.status == .paused)
        #expect(engine.plan.workout == Fixture.hillSprints12)
        #expect(engine.elapsed == 330.5)
        let phase = try #require(engine.position.phase)
        #expect(phase.kind == .work)
        #expect(phase.round == 1)
        #expect(phase.title == "Sprint")
        #expect(engine.position.remainingInPhase == 14.5)

        let shown = try #require(presenter.shown.last ?? nil)
        #expect(shown.clock == .paused(remainingInPhase: 14.5, remainingInWorkout: 914.5))
        #expect(shown.next?.title == "Walk")

        run.coordinator.togglePause()
        #expect(engine.status == .running)
        #expect((330.5..<331.5).contains(engine.elapsed), "Resumed where it stopped")
        run.close()
    }

    /// `liveactivity-state.json`: Hill Sprints 330.5 seconds in, in the first Sprint, as the
    /// presenter showed `runningSnapshot12` (in Pastel) and `pausedSnapshot12` (in Classic),
    /// and the same run finished.
    static let liveActivityStates12: [String: RunActivityAttributes.ContentState] = [
        "running": RunActivityAttributes.ContentState(
            phase: .work, phaseDuration: 30, round: 1, next: .rest, nextDuration: 90,
            phaseName: "Sprint", nextName: "Walk",
            clock: .running(
                phaseStart: Fixture.anchor12.addingTimeInterval(315),
                phaseEnd: Fixture.anchor12.addingTimeInterval(345),
                workoutEnd: Fixture.anchor12.addingTimeInterval(1245)
            ),
            theme: .pastel
        ),
        "paused": RunActivityAttributes.ContentState(
            phase: .work, phaseDuration: 30, round: 1, next: .rest, nextDuration: 90,
            phaseName: "Sprint", nextName: "Walk",
            clock: .paused(phaseLeft: 14.5, workoutLeft: 914.5),
            theme: .classic
        ),
        "finished": RunActivityAttributes.ContentState(
            phase: nil, phaseDuration: 0, round: 6, next: nil, nextDuration: nil,
            clock: .finished,
            theme: .classic
        ),
    ]
}

// MARK: - Replays

/// The cues `cueplan.json` pins, worked through this version's code. The generator wrote
/// 1.2's answers for these same cases; the test above compares today's with them.
private enum Replay {

    struct Boundary: Codable, Equatable {
        var event: String
        var kind: String?
        var round: Int?
        var seconds: Int?
        var rounds: Int
        /// The preset's name for the phase, when it gives one.
        var label: String?
        var voice: Bool
        var lateness: TimeInterval
    }

    struct Cue: Codable, Equatable {
        var tone: String?
        var phrase: String?
        var tap: String?
    }

    /// Every phase under its own name; every phase renamed; and a one-round workout, whose
    /// only interval is never "Last round".
    static let cueWorkouts = [
        IntervalWorkout(
            name: "Own Names", prepareSeconds: 10, warmupSeconds: 60, workSeconds: 20, restSeconds: 10,
            rounds: 2, cooldownSeconds: 60
        ),
        IntervalWorkout(
            name: "Renamed", prepareSeconds: 10, warmupSeconds: 60, workSeconds: 20, restSeconds: 10,
            rounds: 2, cooldownSeconds: 60,
            phaseLabels: [
                "prepare": PhaseLabel(name: "Set Up", symbol: .hourglass),
                "warmup": PhaseLabel(name: "Easy Row", symbol: .row),
                "work": PhaseLabel(name: "Sprint", symbol: .sprint),
                "rest": PhaseLabel(name: "Walk", symbol: .walk),
                "cooldown": PhaseLabel(name: "Stretch", symbol: .stretch),
            ]
        ),
        IntervalWorkout(name: "One Round", prepareSeconds: 0, workSeconds: 60, restSeconds: 0, rounds: 1),
    ]

    /// Every phase of those, the 3, 2, 1 and the finish, each with the voice on and off, on
    /// time, late, and late enough to be a catch-up that plays nothing. Beeps and the
    /// countdown are on, as they are until turned off.
    ///
    /// A phase's and the finish's context come from the coordinator's own `boundaryContext`,
    /// so a change there shows up in these rows without this replay changing too. A 3, 2, 1
    /// keeps its lateness by hand: the coordinator always calls it on time, which would hide
    /// the cue plan's own rule that a late tick plays nothing.
    static func cues() -> [Fixture.Row<Boundary, Cue>] {
        // When each boundary falls, so the coordinator can tell how late it was noticed.
        var boundaries: [(event: TimerEvent, rounds: Int, at: TimeInterval, totalDuration: TimeInterval)] = []
        let plans = cueWorkouts.map { IntervalPlan(workout: $0) }
        for plan in plans {
            boundaries += plan.phases.map { (.phaseBegan($0), plan.totalRounds, $0.start, plan.totalDuration) }
        }
        boundaries += [3, 2, 1].map { (.countdown(secondsRemaining: $0), 2, 0, 0) }
        boundaries.append((.finished, 2, plans[0].totalDuration, plans[0].totalDuration))

        return boundaries.flatMap { boundary in
            [true, false].flatMap { voice in
                [0, 1.0, 2.0].map { lateness in
                    let context: BoundaryContext
                    if case .countdown = boundary.event {
                        context = BoundaryContext(lateness: lateness, phaseDuration: nil)
                    } else {
                        context = RunCoordinator.boundaryContext(
                            for: boundary.event, wallElapsed: boundary.at + lateness,
                            totalDuration: boundary.totalDuration
                        )
                    }
                    let cue = CuePlan.make(
                        for: boundary.event,
                        context: context,
                        settings: CueSettings(voice: voice),
                        totalRounds: boundary.rounds
                    )
                    return Fixture.Row(
                        input: input(boundary.event, rounds: boundary.rounds, voice: voice, lateness: lateness),
                        output: Cue(tone: cue.tone.map { "\($0)" }, phrase: cue.phrase, tap: cue.tap.map { "\($0)" })
                    )
                }
            }
        }
    }

    private static func input(_ event: TimerEvent, rounds: Int, voice: Bool, lateness: TimeInterval) -> Boundary {
        var boundary = Boundary(event: "", rounds: rounds, voice: voice, lateness: lateness)
        switch event {
        case .phaseBegan(let phase):
            boundary.event = "phaseBegan"
            boundary.kind = phase.kind.rawValue
            boundary.round = phase.round
            boundary.label = phase.label?.name
        case .countdown(let seconds):
            boundary.event = "countdown"
            boundary.seconds = seconds
        case .finished:
            boundary.event = "finished"
        }
        return boundary
    }
}

// MARK: - Making the fixtures

#if DEBUG
/// Writes the iPhone's half of the 1.2 fixtures, the cues and the Live Activity's states, with
/// this version's own code. The watch bundle's `GoldenFixtureGenerator` writes the rest and
/// says when to run them (once, from the 1.2 (13) sources). Skipped in every normal run, and
/// it never writes over a file.
///
///     TEST_RUNNER_INTERVALLY_RECORD_FIXTURES=<folder> xcodebuild test -project Intervally.xcodeproj \
///       -scheme IntervallyPhone -destination 'platform=iOS Simulator,id=<claimed UDID>' \
///       -only-testing:IntervallyPhoneTests/GoldenFixtureGenerator
@Suite(.enabled(if: Fixture.recordingDirectory != nil))
@MainActor
struct GoldenFixtureGenerator {

    @Test func cuePlan() throws {
        try Fixture.record(Fixture.lines(Replay.cues()), as: "cueplan.json")
    }

    @Test func liveActivityState() throws {
        // As the presenter makes them: from the run as it is shown outside the app, in a theme.
        let plan = IntervalPlan(workout: Fixture.hillSprints12)
        func state(
            _ status: TimerEngine.Status, anchor: Date?, elapsed: TimeInterval, theme: AppTheme
        ) throws -> RunActivityAttributes.ContentState {
            let run = try #require(RunPresentation(plan: plan, status: status, anchor: anchor, elapsed: elapsed))
            return RunActivityAttributes.ContentState(run, theme: theme)
        }
        let states = [
            "running": try state(.running, anchor: Fixture.anchor12, elapsed: 330.5, theme: .pastel),
            "paused": try state(.paused, anchor: nil, elapsed: 330.5, theme: .classic),
            "finished": try state(.finished, anchor: nil, elapsed: plan.totalDuration, theme: .classic),
        ]
        try #require(states == GoldenFixtureTests.liveActivityStates12)
        try Fixture.record(Fixture.pretty(states), as: "liveactivity-state.json")
    }
}
#endif
