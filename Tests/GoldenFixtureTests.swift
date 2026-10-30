//
//  GoldenFixtureTests.swift
//  IntervallyTests
//

import Foundation
import Testing
import WatchKit
@testable import Intervally

/// What 1.2 (13) stored, sent and decided, read and replayed by this version (`Fixture` has
/// the rules): presets, the sync document, saved runs and the run mirror's messages, which
/// must read back as they were; boundary alerts, taps, plans and the engine's events, which
/// must come out as they did.
@Suite("Golden fixtures")
@MainActor
struct GoldenFixtureTests {

    // MARK: - What 1.2 stored and sent

    @Test("Presets 1.2 saved read back as saved, in the complication and in a store that takes them over")
    func decodesWorkouts12() throws {
        let json = Fixture.data("workouts.json")
        let workouts = try JSONDecoder().decode([IntervalWorkout].self, from: json)
        #expect(workouts == Fixture.workouts12)
        // Saved again, they are exactly what 1.2 saved: a field added since is written only
        // once it is set.
        #expect(Fixture.sameJSON(try JSONEncoder().encode(workouts), json))

        let defaults = makeTestDefaults()
        defaults.set(json, forKey: WorkoutStore.Key.workouts)
        defaults.set(Fixture.boxing12.id.uuidString, forKey: WorkoutStore.Key.selected)
        #expect(WorkoutStore.selectedPreset(in: defaults) == Fixture.boxing12)
        // With no document beside them, as when one was lost, the store takes them over.
        let store = WorkoutStore(defaults: defaults)
        #expect(store.workouts == Fixture.workouts12)
        #expect(store.selected == Fixture.boxing12)
    }

    @Test("A 1.2 device's sync document reads back as sent: presets, tombstone, places and selection")
    func decodesSyncDocument12() throws {
        let json = Fixture.data("syncdocument.json")
        #expect(try JSONDecoder().decode(SyncDocument.self, from: json) == Fixture.document12)

        // As 1.2 left it on disk, where it keeps the same JSON: the store picks it up as it
        // stands, tombstone and all.
        let defaults = makeTestDefaults()
        defaults.set(json, forKey: WorkoutStore.Key.document)
        let stored = WorkoutStore(defaults: defaults)
        #expect(!stored.isSyncSuspended)
        #expect(stored.document == Fixture.document12)
        #expect(stored.workouts.map(\.name) == ["Hill Sprints", "Classic", "Tabata"])
        #expect(stored.selected == Fixture.hillSprints12)

        // As a 1.2 peer delivers it: compressed in an application context, beside the schema
        // and the time it was sent.
        let context: [String: Any] = [
            SyncWire.documentKey: try (json as NSData).compressed(using: .lzfse) as Data,
            SyncWire.schemaKey: 1,
            SyncWire.sentAtKey: Fixture.anchor12,
        ]
        let received = try #require(SyncWire.document(from: context))
        #expect(received == Fixture.document12)

        // Merged into a fresh install, it lists what the 1.2 device lists.
        let store = WorkoutStore(defaults: makeTestDefaults())
        store.merge(received)
        #expect(store.workouts.map(\.name) == ["Hill Sprints", "Classic", "Tabata"])
        #expect(store.workouts.last?.rounds == 10)
        #expect(store.selected == Fixture.hillSprints12)
    }

    @Test("A 1.2 document read and sent on is what 1.2 sent, so a 1.2 peer finds nothing new in it")
    func syncDocumentRoundTripIsLossless() throws {
        let json = Fixture.data("syncdocument.json")
        let document = try JSONDecoder().decode(SyncDocument.self, from: json)
        let context = try SyncWire.context(for: document, sentAt: Fixture.anchor12)
        let compressed = try #require(context[SyncWire.documentKey] as? Data)
        let sent = try (compressed as NSData).decompressed(using: .lzfse) as Data
        #expect(Fixture.sameJSON(sent, json))
        #expect(SyncWire.document(from: context) == document)
    }

    @Test("Runs 1.2 saved, running and paused, read back as saved, in the app and the complication")
    func decodesRunSnapshots12() throws {
        let saved = [
            ("runsnapshot-running.json", Fixture.runningSnapshot12),
            ("runsnapshot-paused.json", Fixture.pausedSnapshot12),
        ]
        for (name, expected) in saved {
            let json = Fixture.data(name)
            let snapshot = try JSONDecoder().decode(RunSnapshot.self, from: json)
            #expect(snapshot == expected, "\(name)")
            // Saved again, it is exactly what 1.2 saved: a field added since is written only
            // once it is set.
            #expect(Fixture.sameJSON(try JSONEncoder().encode(snapshot), json), "\(name)")
            let defaults = makeTestDefaults()
            defaults.set(json, forKey: WorkoutStore.Key.activeRun)
            #expect(WorkoutStore.activeRun(in: defaults) == expected, "\(name)")
            // A minute into the run, well before the running one would be over.
            let store = WorkoutStore(defaults: defaults)
            #expect(store.loadActiveRun(now: Fixture.anchor12.addingTimeInterval(60)) == expected, "\(name)")
        }
    }

    @Test("The run mirror's 1.2 messages read back as sent, and this version sends a 1.2 device the same")
    func decodesRunMirrorMessages12() throws {
        let json = Fixture.data("runmirror-messages.json")
        #expect(try JSONDecoder().decode([String: RunMirrorMessage].self, from: json) == Fixture.mirrorMessages12)
        let entries = Fixture.entries(json)
        #expect(entries.keys.sorted() == Fixture.mirrorMessages12.keys.sorted())
        for (name, frozen) in entries {
            #expect(RunMirrorMessage.decoded(frozen) == Fixture.mirrorMessages12[name], "\(name)")
            // Sent from here, the same message is exactly what 1.2 sent, so a 1.2 device on the
            // other end reads it as it always has.
            let sent = try #require(Fixture.mirrorMessages12[name]?.encoded())
            #expect(Fixture.sameJSON(sent, frozen), "\(name)")
        }
    }

    // MARK: - What 1.2 decided

    @Test("Tabata's boundary alerts are the ones 1.2 scheduled")
    func notificationRequestsMatch12() {
        Fixture.expect(Replay.tabataAlerts(), toMatch: "notifications-tabata.json")
    }

    @Test("Every boundary taps as it did in 1.2, at every strength, on time and late")
    func hapticsPlanMatches12() {
        Fixture.expect(Replay.taps(), toMatch: "haptics.json")
    }

    @Test("Every plan lays out its phases as 1.2 did")
    func plansMatch12() {
        Fixture.expect(Replay.plans(), toMatch: "plans.json")
    }

    @Test("The engine reports what 1.2 did, when it did, through a pause, a skip and time away")
    func engineEventsMatch12() {
        Fixture.expect(Replay.engineEvents(), toMatch: "engine-events.json")
    }
}

// MARK: - Replays

/// The cases the behavior fixtures pin, worked through this version's code. The generator
/// wrote 1.2's answers for these same cases; the tests above compare today's with them.
@MainActor
private enum Replay {

    /// An engine event as the fixtures write it.
    struct Event: Codable, Equatable {
        var event: String
        var kind: String?
        var round: Int?
        var seconds: Int?

        init(_ event: TimerEvent) {
            switch event {
            case .phaseBegan(let phase):
                self.event = "phaseBegan"
                kind = phase.kind.rawValue
                round = phase.round
            case .countdown(let seconds):
                self.event = "countdown"
                self.seconds = seconds
            case .finished:
                self.event = "finished"
            }
        }
    }

    // MARK: Boundary alerts

    /// One alert, as `notifications-tabata.json` keeps it.
    struct Alert: Codable, Equatable {
        var identifier: String
        var delay: TimeInterval
        var title: String
        var body: String
    }

    /// Tabata's alerts, scheduled the moment its run starts. An alert keeps its moment now,
    /// not 1.2's delay, so the delay is how long after that start it goes off.
    static func tabataAlerts() -> [Alert] {
        NotificationScheduler.requests(
            plan: IntervalPlan(workout: Fixture.starters12[1]),
            anchor: Fixture.anchor12, now: Fixture.anchor12, limit: 60
        )
        .map {
            Alert(
                identifier: $0.identifier, delay: $0.fireDate.timeIntervalSince(Fixture.anchor12),
                title: $0.title, body: $0.body
            )
        }
    }

    // MARK: Taps

    struct Boundary: Codable, Equatable {
        var event: String
        var kind: String?
        var round: Int?
        var seconds: Int?
        var rounds: Int
        var phaseDuration: TimeInterval?
        var lateness: TimeInterval
        var strength: String

        init(_ event: TimerEvent, rounds: Int, context: BoundaryContext, strength: TapStrength) {
            let named = Event(event)
            self.event = named.event
            kind = named.kind
            round = named.round
            seconds = named.seconds
            self.rounds = rounds
            phaseDuration = context.phaseDuration
            lateness = context.lateness
            self.strength = strength.rawValue
        }
    }

    struct Taps: Codable, Equatable {
        struct Step: Codable, Equatable {
            var milliseconds: Int
            var type: String
        }

        var steps: [Step]
        var suppressedCountdown: [Int]
    }

    /// Phases long enough for every burst, and phases short enough for the rules to trim one.
    static let tapWorkouts = [
        IntervalWorkout(
            name: "Roomy", prepareSeconds: 10, warmupSeconds: 60, workSeconds: 30, restSeconds: 15,
            rounds: 2, cooldownSeconds: 60
        ),
        IntervalWorkout(
            name: "Tight", prepareSeconds: 2, warmupSeconds: 2, workSeconds: 5, restSeconds: 2,
            rounds: 2, cooldownSeconds: 2
        ),
    ]

    /// On time, at the line the haptics draw for a catch-up, and past it.
    static let latenesses: [TimeInterval] = [0, 1.0, 2.0]

    /// Every phase of both workouts and the finish, each noticed that late, and the 3, 2, 1.
    /// Each context comes from the coordinator's own `boundaryContext`, so a change there
    /// shows up in these rows without this replay changing too.
    static func taps() -> [Fixture.Row<Boundary, Taps>] {
        var boundaries: [(event: TimerEvent, rounds: Int, context: BoundaryContext)] = []
        func add(_ event: TimerEvent, of plan: IntervalPlan, wallElapsed: TimeInterval?) {
            let context = RunCoordinator.boundaryContext(
                for: event, wallElapsed: wallElapsed, totalDuration: plan.totalDuration
            )
            boundaries.append((event, plan.totalRounds, context))
        }
        let plans = tapWorkouts.map { IntervalPlan(workout: $0) }
        for plan in plans {
            for phase in plan.phases {
                for lateness in latenesses {
                    add(.phaseBegan(phase), of: plan, wallElapsed: phase.start + lateness)
                }
            }
        }
        for lateness in latenesses {
            add(.finished, of: plans[0], wallElapsed: plans[0].totalDuration + lateness)
        }
        for seconds in [3, 2, 1] {
            add(.countdown(secondsRemaining: seconds), of: plans[0], wallElapsed: nil)
        }

        return boundaries.flatMap { boundary in
            TapStrength.allCases.map { strength in
                let plan = Haptics.plan(for: boundary.event, strength: strength, context: boundary.context)
                return Fixture.Row(
                    input: Boundary(boundary.event, rounds: boundary.rounds, context: boundary.context, strength: strength),
                    output: Taps(
                        steps: plan.steps.map { Taps.Step(milliseconds: milliseconds($0.offset), type: name($0.type)) },
                        suppressedCountdown: plan.suppressedCountdown.sorted()
                    )
                )
            }
        }
    }

    static func milliseconds(_ duration: Duration) -> Int {
        let parts = duration.components
        return Int(parts.seconds) * 1000 + Int(parts.attoseconds / 1_000_000_000_000_000)
    }

    /// The tap's name. Every type a 1.2 boundary plays has one; anything else shows its raw
    /// value.
    static func name(_ type: WKHapticType) -> String {
        switch type {
        case .notification: "notification"
        case .directionUp: "directionUp"
        case .directionDown: "directionDown"
        case .success: "success"
        case .failure: "failure"
        case .retry: "retry"
        case .start: "start"
        case .stop: "stop"
        case .click: "click"
        default: "WKHapticType(\(type.rawValue))"
        }
    }

    // MARK: Plans

    struct PlanPhase: Codable, Equatable {
        var workout: String
        var phase: Int
    }

    struct Planned: Codable, Equatable {
        var kind: String
        var round: Int
        var start: TimeInterval
        var duration: TimeInterval
        /// The preset's name for the phase, when it gives one.
        var label: String?
        var symbol: String
    }

    /// One round, no rest, and values outside every range, as a version without the limits
    /// might have saved them.
    static let edgeWorkouts = [
        IntervalWorkout(name: "One Round", prepareSeconds: 0, workSeconds: 60, restSeconds: 0, rounds: 1),
        IntervalWorkout(name: "No Rest", prepareSeconds: 5, workSeconds: 20, restSeconds: 0, rounds: 3),
        IntervalWorkout(
            name: "Out of Range", prepareSeconds: 400, warmupSeconds: 5_000, workSeconds: 2, restSeconds: -3,
            rounds: 0, cooldownSeconds: -1
        ),
    ]

    /// Every phase of every 1.2 preset in `workouts.json`, and of the edge cases.
    static func plans() -> [Fixture.Row<PlanPhase, Planned>] {
        (Fixture.workouts12 + edgeWorkouts).flatMap { workout in
            IntervalPlan(workout: workout).phases.map { phase in
                Fixture.Row(
                    input: PlanPhase(workout: workout.name, phase: phase.id),
                    output: Planned(
                        kind: phase.kind.rawValue, round: phase.round, start: phase.start,
                        duration: phase.duration, label: phase.label?.name, symbol: phase.symbol.rawValue
                    )
                )
            }
        }
    }

    // MARK: Engine events

    struct Moment: Codable, Equatable {
        var scenario: String
        /// What the run was asked to do: start, tick, pause or skip.
        var action: String
        /// Wall-clock seconds since Start.
        var at: TimeInterval
    }

    /// Two runs, ticked every half second as the run's ticker did in 1.2: Hill Sprints from
    /// Start to the end, through a lead-in, a warmup, renamed intervals and a cooldown; and
    /// Classic paused for a minute in its first work interval, skipped out of it, then left
    /// unticked while four changes pass, which come back as one.
    static func engineEvents() -> [Fixture.Row<Moment, Event>] {
        let hill = EngineScript("Hill Sprints, start to finish", Fixture.hillSprints12)
        hill.start()
        hill.tickToTheEnd()

        let classic = EngineScript("Classic, paused, skipped and away", Fixture.starters12[0])
        classic.start()
        classic.tick(until: 25)
        classic.pause()
        classic.wait(until: 85)
        classic.resume()
        classic.tick(until: 90)
        classic.skip()
        classic.tick(until: 95)
        classic.wait(until: 190)
        classic.tickToTheEnd()

        return hill.rows + classic.rows
    }

    /// One engine on a clock of its own, and every event it reports.
    @MainActor
    final class EngineScript {
        let scenario: String
        let engine: TimerEngine
        private let clock = TestClock(Fixture.anchor12)
        private(set) var rows: [Fixture.Row<Moment, Event>] = []

        init(_ scenario: String, _ workout: IntervalWorkout) {
            self.scenario = scenario
            engine = TimerEngine(workout: workout)
            engine.now = { [clock] in clock.current }
        }

        private var at: TimeInterval { clock.current.timeIntervalSince(Fixture.anchor12) }

        func start() { record("start", engine.start()) }
        func pause() { record("pause", engine.pause()) }
        func resume() { engine.resume() }
        func skip() { record("skip", engine.skipPhase()) }

        /// Ticks every half second until `seconds` after Start.
        func tick(until seconds: TimeInterval) {
            while at < seconds { tick() }
        }

        func tickToTheEnd() {
            while engine.status == .running { tick() }
        }

        /// Time passes with no tick, as for an app the system suspended.
        func wait(until seconds: TimeInterval) {
            clock.current = Fixture.anchor12.addingTimeInterval(seconds)
        }

        private func tick() {
            clock.current += 0.5
            record("tick", engine.advance())
        }

        private func record(_ action: String, _ events: [TimerEvent]) {
            for event in events {
                rows.append(Fixture.Row(input: Moment(scenario: scenario, action: action, at: at), output: Event(event)))
            }
        }
    }
}

/// A clock a test moves by hand.
@MainActor
private final class TestClock {
    var current: Date
    init(_ current: Date) { self.current = current }
}

// MARK: - Making the fixtures

#if DEBUG
/// Writes the 1.2 fixtures this bundle reads, with this version's own code. Run once, from the
/// 1.2 (13) sources: run later, it would freeze whatever the code does by then, regressions
/// and all. Skipped in every normal run, and it never writes over a file.
///
///     TEST_RUNNER_INTERVALLY_RECORD_FIXTURES=<folder> xcodebuild test -project Intervally.xcodeproj \
///       -scheme Intervally -destination 'platform=watchOS Simulator,id=<claimed UDID>' \
///       -only-testing:IntervallyTests/GoldenFixtureGenerator
///
/// What 1.2 stored or sent is made by the app's own code, and checked to hold exactly what
/// that code wrote before it is written out; those files are never made again. A change whose
/// point is to change what 1.2 decided deletes just that behavior file, runs its test alone,
/// and shows the new file's diff in its pull request. The iPhone bundle's twin writes the cues
/// and the Live Activity's states.
@Suite(.enabled(if: Fixture.recordingDirectory != nil))
@MainActor
struct GoldenFixtureGenerator {

    @Test func workouts() throws {
        // Each edited preset is made the way the editor makes one: added, renamed, given an
        // activity, its phases renamed one at a time, and its durations set.
        let defaults = makeTestDefaults()
        let store = WorkoutStore(defaults: defaults)
        for preset in Fixture.workouts12.dropFirst(Fixture.starters12.count) {
            store.add(IntervalWorkout(id: preset.id, name: "New"))
            store.rename(preset.id, to: preset.name)
            store.setActivity(preset.id, to: try #require(preset.activity))
            for (kind, label) in try #require(preset.phaseLabels) {
                store.setLabel(preset.id, kind: try #require(IntervalPhase.Kind(rawValue: kind)), to: label)
            }
            var timed = try #require(store.workouts.first { $0.id == preset.id })
            timed.prepareSeconds = preset.prepareSeconds
            timed.warmupSeconds = preset.warmupSeconds
            timed.workSeconds = preset.workSeconds
            timed.restSeconds = preset.restSeconds
            timed.rounds = preset.rounds
            timed.cooldownSeconds = preset.cooldownSeconds
            store.update(timed)
        }
        try #require(store.workouts == Fixture.workouts12)

        let saved = try #require(defaults.data(forKey: WorkoutStore.Key.workouts))
        let file = try Fixture.pretty(store.workouts)
        try #require(Fixture.sameJSON(saved, file))
        try Fixture.record(file, as: "workouts.json")
    }

    @Test func syncDocument() throws {
        let context = try SyncWire.context(for: Fixture.document12, sentAt: Fixture.anchor12)
        let compressed = try #require(context[SyncWire.documentKey] as? Data)
        let sent = try (compressed as NSData).decompressed(using: .lzfse) as Data
        let file = try Fixture.pretty(Fixture.document12)
        try #require(Fixture.sameJSON(sent, file))
        try Fixture.record(file, as: "syncdocument.json")
    }

    @Test func runSnapshots() throws {
        let defaults = makeTestDefaults()
        let store = WorkoutStore(defaults: defaults)
        let snapshots = [
            ("runsnapshot-running.json", Fixture.runningSnapshot12),
            ("runsnapshot-paused.json", Fixture.pausedSnapshot12),
        ]
        for (name, snapshot) in snapshots {
            store.saveActiveRun(snapshot)
            let saved = try #require(defaults.data(forKey: WorkoutStore.Key.activeRun))
            let file = try Fixture.pretty(snapshot)
            try #require(Fixture.sameJSON(saved, file))
            try Fixture.record(file, as: name)
        }
    }

    @Test func runMirrorMessages() throws {
        // The watch's states as the coordinator makes them, from an engine at each stage.
        let clock = TestClock(Fixture.anchor12)
        let engine = TimerEngine(workout: Fixture.hillSprints12)
        engine.now = { [clock] in clock.current }
        var messages: [String: RunMirrorMessage] = [:]
        messages["state-stopped"] = .state(RunMirrorState(engine: engine, health: nil))
        engine.start()
        clock.current += 60
        messages["state-running"] = .state(RunMirrorState(engine: engine, health: nil))
        engine.restore(anchor: Fixture.anchor12, workout: Fixture.hillSprints12, paused: 330.5)
        messages["state-paused"] = .state(RunMirrorState(engine: engine, health: nil))
        clock.current = Fixture.anchor12.addingTimeInterval(2_000)
        engine.restore(anchor: Fixture.anchor12, workout: Fixture.hillSprints12, paused: nil)
        try #require(engine.status == .finished)
        messages["state-finished"] = .state(RunMirrorState(engine: engine, health: .saved))
        let commands: [String: RunMirrorCommand] = [
            "command-pause": .pause, "command-resume": .resume, "command-skip": .skip(phase: 2),
            "command-end": .end, "command-refresh": .refresh,
        ]
        messages.merge(commands.mapValues(RunMirrorMessage.command)) { first, _ in first }
        try #require(messages == Fixture.mirrorMessages12)

        for message in messages.values {
            let sent = try #require(message.encoded())
            try #require(Fixture.sameJSON(sent, try Fixture.pretty(message)))
        }
        try Fixture.record(Fixture.pretty(messages), as: "runmirror-messages.json")
    }

    @Test func notifications() throws {
        try Fixture.record(Fixture.lines(Replay.tabataAlerts()), as: "notifications-tabata.json")
    }

    @Test func haptics() throws {
        try Fixture.record(Fixture.lines(Replay.taps()), as: "haptics.json")
    }

    @Test func plans() throws {
        try Fixture.record(Fixture.lines(Replay.plans()), as: "plans.json")
    }

    @Test func engineEvents() throws {
        try Fixture.record(Fixture.lines(Replay.engineEvents()), as: "engine-events.json")
    }
}
#endif
