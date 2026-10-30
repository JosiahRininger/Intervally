//
//  TimerEngineFuzzTests.swift
//  IntervallyTests
//

import Foundation
import Testing
@testable import Intervally

/// Seeded random runs of the timer engine: 2,000 generated plans, each run through ticks,
/// suspensions, pauses, resumes, skips and relaunches, and held at every step to what any run
/// must do. A relaunch while paused on a phase the run had skipped to lost that phase's cue on
/// Resume, and no hand-picked case caught it; rules checked over thousands of runs find that
/// kind of mistake. A failure gives the run's seed, its plan and every step, and
/// `FuzzCase(seed:)` makes the same run again.
///
/// Runs are driven the way a device drives them. The clock moves in steps of 1/1024 s, so the
/// engine's sums are exact, as they are at a real date. Each move of the clock is a tick: the
/// run is advanced, as the ticker or a return to the app advances it. A tap or a relaunch
/// always comes after at least one tick, so by then the run has announced whatever was due,
/// but a change a skip while paused left for Resume. And a pause never lands on the very
/// instant a phase began: on a device it comes a moment after the tick that announced the
/// change, and a run paused on that instant is one a skip while paused left there
/// (`TimerEngine.restore`).
@Suite("Timer engine fuzz")
@MainActor
struct TimerEngineFuzzTests {

    private static let trials = 2_000

    @Test("Over 2,000 generated plans, time only moves on, each phase reached is announced once, each countdown second plays once, and the finish comes once")
    func invariantsHoldAcrossGeneratedPlans() {
        var failures: [String: Int] = [:]
        var firstFailure: String?
        var seen = Coverage()

        for trial in 0..<Self.trials {
            let fuzz = FuzzCase(seed: 0x5EED_0007_0000 &+ UInt64(trial))
            let run = FuzzRun(fuzz.workout)
            var rules = RunRules(plan: IntervalPlan(workout: fuzz.workout))
            var firstBreak: String?
            for (step, op) in fuzz.ops.enumerated() {
                let wasBroken = rules.broken
                let before = run.standing
                let events = run.apply(op)
                if op == .relaunch {
                    // The snapshot holds all a relaunch needs, a change still to come included.
                    if run.standing != before { rules.breaks("a relaunch moved the run") }
                    if before.status == .running { seen.relaunchedRunning += 1 }
                    if before.status == .paused, before.hasPendingBoundary { seen.relaunchedPausedOnASkip += 1 }
                }
                if op == .skip, events.contains(.finished) { seen.finishedBySkip += 1 }
                rules.check(op, events, run.engine)
                if firstBreak == nil, rules.broken != wasBroken {
                    firstBreak = "\(rules.broken.subtracting(wasBroken).sorted()) at step \(step), \(op), with \(events)"
                }
            }
            if run.engine.status != .finished || rules.finishes != 1 { rules.breaks("didn't finish exactly once") }
            seen.replays += rules.replays
            seen.catchUps += rules.catchUps

            for rule in rules.broken { failures[rule, default: 0] += 1 }
            if !rules.broken.isEmpty, firstFailure == nil { firstFailure = "\(fuzz)\n\(firstBreak ?? "At the end")" }
        }

        #expect(failures.isEmpty, "\(failures) in \(Self.trials) runs. The first: \(firstFailure ?? "")")
        // So the runs keep reaching the cases the rules are for as the generator changes.
        #expect(seen.shortfall.isEmpty, "Reached too seldom: \(seen.shortfall)")
    }

    /// A relaunch while paused must leave nothing to tell: the run comes back exactly as it
    /// was. One while running comes back as a Resume at that moment would leave it, the
    /// countdown second under way free to play again (`resume()`), so that is what it's
    /// compared with.
    @Test("A relaunch at any step changes nothing a Resume there wouldn't: the restored run reports what the run that carried on does")
    func restoreIsTransparent() {
        var differed = 0
        var firstDifference: String?
        var relaunchedPausedOnASkip = 0

        for trial in 0..<Self.trials {
            let fuzz = FuzzCase(seed: 0x5EED_0007_8000 &+ UInt64(trial))
            let restored = FuzzRun(fuzz.workout)
            let carriedOn = FuzzRun(fuzz.workout, comesBack: false)
            for (step, op) in fuzz.ops.enumerated() {
                if op == .relaunch, restored.engine.status == .paused, restored.engine.hasPendingBoundary {
                    relaunchedPausedOnASkip += 1
                }
                let events = restored.apply(op)
                let expected = carriedOn.apply(op)
                guard events == expected, restored.standing == carriedOn.standing else {
                    differed += 1
                    if firstDifference == nil {
                        firstDifference = "\(fuzz)\nAt step \(step), \(op): \(events) and \(restored.standing), "
                            + "where the run that carried on had \(expected) and \(carriedOn.standing)"
                    }
                    break
                }
            }
        }

        #expect(differed == 0, "\(differed) of \(Self.trials) runs went differently once relaunched. The first: \(firstDifference ?? "")")
        #expect(relaunchedPausedOnASkip >= 700, "Relaunched while paused on a skip only \(relaunchedPausedOnASkip) times")
    }
}

// MARK: - Runs

/// One step of a fuzzed run.
private enum FuzzOp: Equatable, CustomStringConvertible {
    case start
    /// The clock moves on by this many 1/1024 s and the run is advanced: the ticker waking, or
    /// the app coming back after a suspension.
    case tick(Int)
    case pause
    case resume
    case skip
    /// The app is ended and launched again, and the run comes back from its snapshot.
    case relaunch

    var description: String {
        switch self {
        case .start: "start"
        case .tick(let steps): "+\(Double(steps) * FuzzRun.step)"
        case .pause: "pause"
        case .resume: "resume"
        case .skip: "skip"
        case .relaunch: "relaunch"
        }
    }
}

/// A generated plan and a random run of it, made from its seed alone.
private struct FuzzCase: CustomStringConvertible {
    let seed: UInt64
    let workout: IntervalWorkout
    let ops: [FuzzOp]

    /// Turns of ticks, each perhaps ending in a tap or a relaunch, before the run is left to
    /// run out: enough to cross many phases.
    private static let turns = 40

    @MainActor
    init(seed: UInt64) {
        var rng = SeededGenerator(seed: seed)
        let workout = Self.randomWorkout(using: &rng)
        // Drawn against a run of its own, so each step suits where the run then stands. Its
        // relaunches carry on as a Resume would, which is where a restored run stands too.
        let run = FuzzRun(workout, comesBack: false)
        var ops: [FuzzOp] = []
        func take(_ op: FuzzOp) {
            ops.append(op)
            _ = run.apply(op)
        }

        take(.start)
        for _ in 0..<Self.turns {
            for _ in 0..<Int.random(in: 1...3, using: &rng) {
                take(.tick(Self.randomTick(run.engine, using: &rng)))
            }
            guard run.engine.isActive else { break }
            switch Int.random(in: 0..<10, using: &rng) {
            case 0..<3 where run.engine.status == .paused:
                take(.resume)
            case 0..<3:
                // A moment after the tick that announced a change, never on its instant.
                if run.isOnAPhaseStart { take(.tick(1)) }
                take(.pause)
            case 3..<6:
                take(.skip)
            case 6..<8:
                take(.relaunch)
            default:
                // Only ticks this time.
                break
            }
        }
        // Then resumed if need be and left to run out, and one step more finds nothing to do.
        if run.engine.status == .paused {
            take(.tick(Int.random(in: 1...1024, using: &rng)))
            take(.resume)
        }
        if run.engine.isActive {
            let left = Int((run.engine.plan.totalDuration - run.engine.elapsed) / FuzzRun.step)
            take(.tick(left + Int.random(in: 0...10 * 1024, using: &rng)))
        }
        take([FuzzOp.tick(1024), .pause, .resume, .skip, .relaunch].randomElement(using: &rng)!)

        self.seed = seed
        self.workout = workout
        self.ops = ops
    }

    /// A plan as the editor can make one: 1 to 30 rounds, each phase 0 to 600 s in 5 s steps
    /// within its limits, and the warmup and the cooldown each on or off.
    private static func randomWorkout(using rng: inout SeededGenerator) -> IntervalWorkout {
        func seconds(_ range: ClosedRange<Int>) -> Int {
            Int.random(in: (range.lowerBound / 5)...(range.upperBound / 5), using: &rng) * 5
        }
        return IntervalWorkout(
            name: "Fuzz",
            prepareSeconds: seconds(IntervalWorkout.prepareRange),
            warmupSeconds: Bool.random(using: &rng) ? seconds(5...600) : 0,
            workSeconds: seconds(5...600),
            restSeconds: seconds(0...600),
            rounds: Int.random(in: 1...30, using: &rng),
            cooldownSeconds: Bool.random(using: &rng) ? seconds(5...600) : 0
        )
    }

    /// How far a tick moves the clock, in steps of 1/1024 s: to the next moment the run has
    /// something to announce, or up to 16 ms past it, as the ticker wakes; a moment of up to a
    /// second; a suspension of up to a minute; or anything up to past the end.
    @MainActor
    private static func randomTick(_ engine: TimerEngine, using rng: inout SeededGenerator) -> Int {
        let elapsed = engine.elapsed
        switch Int.random(in: 0..<10, using: &rng) {
        case 0..<4 where engine.status == .running:
            guard let next = engine.plan.nextEventElapsed(afterElapsed: elapsed) else { return 1 }
            return Int((next - elapsed) / FuzzRun.step) + Int.random(in: 0...16, using: &rng)
        case 0..<7:
            return Int.random(in: 1...1024, using: &rng)
        case 7..<9:
            return Int.random(in: 1...(60 * 1024), using: &rng)
        default:
            return Int.random(in: 1...Int((engine.plan.totalDuration - elapsed + 10) / FuzzRun.step), using: &rng)
        }
    }

    var description: String {
        let plan = "prepare \(workout.prepareSeconds), warmup \(workout.warmupSeconds), "
            + "\(workout.rounds) × work \(workout.workSeconds) and rest \(workout.restSeconds), "
            + "cooldown \(workout.cooldownSeconds)"
        return "seed 0x\(String(seed, radix: 16, uppercase: true)) (\(plan)): "
            + ops.map(\.description).joined(separator: " ")
    }
}

/// Where a run stands, to tell two apart.
private struct Standing: Equatable, CustomStringConvertible {
    let status: TimerEngine.Status
    let elapsed: TimeInterval
    let phaseIndex: Int?
    let hasPendingBoundary: Bool
    let phaseEnd: Date?

    var description: String {
        "\(status) at \(elapsed) s in phase \(phaseIndex.map(String.init) ?? "none")"
            + (hasPendingBoundary ? ", its change still to come" : "")
    }
}

/// The wall clock of one run, shared with every engine the run is rebuilt as.
@MainActor
private final class FuzzClock {
    var now = Date(timeIntervalSinceReferenceDate: 1_000_000)
}

/// One plan's run on a clock of its own.
@MainActor
private final class FuzzRun {
    /// How far the clock moves at a time, in seconds. A power of two, so every sum is exact.
    nonisolated static let step: TimeInterval = 1.0 / 1024

    private(set) var engine: TimerEngine
    private let clock = FuzzClock()
    /// Whether a relaunch rebuilds the engine from its snapshot. The run a restored one is
    /// compared with carries on instead, as it would after a Resume at that moment.
    private let comesBack: Bool

    init(_ workout: IntervalWorkout, comesBack: Bool = true) {
        self.comesBack = comesBack
        engine = TimerEngine(workout: workout)
        engine.now = { [clock] in clock.now }
    }

    var standing: Standing {
        Standing(
            status: engine.status, elapsed: engine.elapsed, phaseIndex: engine.position.phaseIndex,
            hasPendingBoundary: engine.hasPendingBoundary, phaseEnd: engine.currentPhaseEndDate
        )
    }

    /// Running, on the very first instant of a phase.
    var isOnAPhaseStart: Bool {
        engine.status == .running && engine.position.phase?.start == engine.elapsed
    }

    func apply(_ op: FuzzOp) -> [TimerEvent] {
        switch op {
        case .start:
            return engine.start()
        case .tick(let steps):
            clock.now = clock.now.addingTimeInterval(Double(steps) * Self.step)
            return engine.advance()
        case .pause:
            return engine.pause()
        case .resume:
            engine.resume()
            return []
        case .skip:
            return engine.skipPhase()
        case .relaunch:
            relaunch()
            return []
        }
    }

    /// Rebuilds the engine from the snapshot `RunCoordinator.persistSnapshot()` saves for it,
    /// read back through JSON as `WorkoutStore` keeps it, as `restoreIfNeeded()` does.
    private func relaunch() {
        let snapshot: RunSnapshot
        switch engine.status {
        case .running:
            guard let anchor = engine.anchor else { return }
            snapshot = RunSnapshot(workout: engine.plan.workout, anchor: anchor, pausedElapsed: nil)
        case .paused:
            snapshot = RunSnapshot(workout: engine.plan.workout, anchor: clock.now, pausedElapsed: engine.elapsed)
        case .idle, .finished:
            // Nothing saved, so nothing comes back.
            return
        }
        guard comesBack else {
            if engine.status == .running {
                engine.pause()
                engine.resume()
            }
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot),
              let saved = try? JSONDecoder().decode(RunSnapshot.self, from: data) else {
            Issue.record("The snapshot didn't read back: \(snapshot)")
            return
        }
        let restored = TimerEngine(workout: saved.workout)
        restored.now = { [clock] in clock.now }
        restored.restore(anchor: saved.anchor, workout: saved.workout, paused: saved.pausedElapsed)
        engine = restored
    }
}

// MARK: - Rules

/// What every run must do, checked after each step of it.
@MainActor
private struct RunRules {
    let plan: IntervalPlan
    private(set) var broken: Set<String> = []
    private(set) var finishes = 0
    /// Countdown seconds played again after a Resume or a relaunch, as `resume()` allows.
    private(set) var replays = 0
    /// Phases announced after one or more went by unannounced, as after a suspension.
    private(set) var catchUps = 0

    private var elapsed: TimeInterval = 0
    /// How many times each phase was announced, by index.
    private var announced: [Int: Int] = [:]
    private var lastAnnounced = -1
    private var played: Set<CountdownSecond> = []
    /// The second under way when the run last resumed or came back running from a relaunch:
    /// the engine forgets the countdown second it played, so that one may play again.
    private var replayable: CountdownSecond?

    init(plan: IntervalPlan) {
        self.plan = plan
    }

    mutating func breaks(_ rule: String) {
        broken.insert(rule)
    }

    mutating func check(_ op: FuzzOp, _ events: [TimerEvent], _ engine: TimerEngine) {
        let position = engine.position
        if engine.elapsed < elapsed { breaks("time went back") }
        if engine.elapsed > plan.totalDuration { breaks("time ran past the end") }
        elapsed = engine.elapsed

        for event in events {
            if finishes > 0 { breaks("something after the finish") }
            switch event {
            case .phaseBegan(let phase):
                announced[phase.id, default: 0] += 1
                if announced[phase.id] != 1 { breaks("a phase announced twice") }
                if phase.id <= lastAnnounced { breaks("a phase announced out of order") }
                if phase.id > lastAnnounced + 1 { catchUps += 1 }
                lastAnnounced = max(lastAnnounced, phase.id)
                if position.phaseIndex != phase.id || plan.phases[phase.id] != phase {
                    breaks("announced a phase the run isn't in")
                }
            case .finished:
                finishes += 1
                if engine.status != .finished || engine.elapsed != plan.totalDuration {
                    breaks("finished short of the end")
                }
            case .countdown(let second):
                guard let index = position.phaseIndex, Int(position.remainingInPhase.rounded(.up)) == second else {
                    breaks("counted a second that isn't the one under way")
                    continue
                }
                let key = CountdownSecond(phase: index, second: second)
                if !played.insert(key).inserted {
                    if key == replayable { replays += 1 } else { breaks("a countdown second played twice") }
                }
            }
            // Only the first thing played after a Resume can be its second again.
            replayable = nil
        }

        switch op {
        case .start, .tick, .skip:
            // Every phase the run is found in while running has been announced, once.
            if engine.status == .running, let index = position.phaseIndex, announced[index] != 1 {
                breaks("a phase reached but not announced")
            }
        case .resume, .relaunch:
            // A run relaunched while paused gets its allowance at Resume.
            if engine.status == .running, let index = position.phaseIndex {
                replayable = CountdownSecond(phase: index, second: Int(position.remainingInPhase.rounded(.up)))
            }
        case .pause:
            replayable = nil
        }
    }
}

/// A countdown second of one phase, by the phase's index.
private struct CountdownSecond: Hashable {
    let phase: Int
    let second: Int
}

/// How often the runs reached the cases the rules are there for.
private struct Coverage {
    var relaunchedPausedOnASkip = 0
    var relaunchedRunning = 0
    var finishedBySkip = 0
    var replays = 0
    var catchUps = 0

    /// Each count short of the least 2,000 runs should reach: about half what they do.
    var shortfall: [String: Int] {
        let least = [
            "relaunched while paused on a skip": (relaunchedPausedOnASkip, 700),
            "relaunched running": (relaunchedRunning, 2_000),
            "finished by a skip": (finishedBySkip, 500),
            "a countdown second played again": (replays, 500),
            "caught up past a phase": (catchUps, 2_000),
        ]
        return least.filter { $0.value.0 < $0.value.1 }.mapValues(\.0)
    }
}
