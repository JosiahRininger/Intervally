//
//  Fixture.swift
//  Intervally test support
//

import Foundation
import Testing
#if os(watchOS)
@testable import Intervally
#else
@testable import IntervallyPhone
#endif

// Compiled into both test bundles: GoldenFixtureTests in each reads the same frozen files.

/// JSON frozen from Intervally 1.2 (13), the version on the App Store when work on 1.3 began,
/// in the test bundles' `Fixtures/1.2` folder.
///
/// Nearly every 1.3 change adds a field to something the app stores or sends. These files are
/// what 1.2 wrote and decided, captured once from its own code (`GoldenFixtureGenerator` in
/// each test bundle), so the tests can show that this version still reads what 1.2 left on a
/// device, and that a paired iPhone or watch still on 1.2 understands what this one sends.
///
/// Two kinds, with a rule each:
/// - What 1.2 stored or sent: `workouts`, `syncdocument`, `runsnapshot-running`,
///   `runsnapshot-paused`, `liveactivity-state` and `runmirror-messages`. These never change.
///   Each must keep decoding to equal values for good, and encode back to the same JSON: a
///   field added later is written only once it is set.
/// - What 1.2 decided: `notifications-tabata`, `cueplan`, `haptics`, `plans` and
///   `engine-events`. One of these changes only in a change whose point is to change that
///   behavior, which re-records just that file and shows its diff in the pull request.
enum Fixture {
    /// Where the files sit in a test bundle: `TestSupport/Fixtures` is copied in as a folder.
    static let folder = "Fixtures/1.2"

    /// The frozen file `name`, such as `"workouts.json"`. A missing one records an issue and
    /// reads as empty, so the test fails on it rather than crashing the whole run.
    static func data(_ name: String) -> Data {
        guard let url = Bundle(for: Token.self).resourceURL?.appending(path: "\(folder)/\(name)"),
              let data = try? Data(contentsOf: url)
        else {
            Issue.record("No \(folder)/\(name) in the test bundle")
            return Data()
        }
        return data
    }

    /// Whether two JSON texts hold the same keys and values, whatever their spacing or key
    /// order: whether a reader of one would find exactly what is in the other.
    static func sameJSON(_ a: Data, _ b: Data) -> Bool {
        guard let left = canonical(a), let right = canonical(b) else { return false }
        return left == right
    }

    /// `data` written out again with sorted keys and no spacing, or nil when it isn't JSON.
    /// Compared as text rather than as objects, which would take `true` for `1`.
    private static func canonical(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
    }

    /// The values of a fixture that keeps one encoded value under each name, each as JSON of
    /// its own, for comparing with what this version encodes.
    static func entries(_ data: Data) -> [String: Data] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object.compactMapValues { try? JSONSerialization.data(withJSONObject: $0, options: .fragmentsAllowed) }
    }

    /// One case of a behavior fixture: what went in, and what came out.
    struct Row<Input: Codable & Equatable, Output: Codable & Equatable>: Codable, Equatable {
        var input: Input
        var output: Output
    }

    /// Holds what this version decides to what 1.2 decided, case by case, so a failure shows
    /// the case that changed rather than two long lists.
    static func expect<Entry: Codable & Equatable>(
        _ entries: [Entry], toMatch name: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let frozen = try? JSONDecoder().decode([Entry].self, from: data(name)) else {
            Issue.record("\(name) doesn't decode", sourceLocation: sourceLocation)
            return
        }
        #expect(entries.count == frozen.count, "\(name) has \(frozen.count) cases", sourceLocation: sourceLocation)
        for (now, then) in zip(entries, frozen) {
            #expect(now == then, sourceLocation: sourceLocation)
        }
    }

    private final class Token {}
}

// MARK: - Making them

#if DEBUG
extension Fixture {
    /// Where `GoldenFixtureGenerator` writes, from `INTERVALLY_RECORD_FIXTURES`. Nil in every
    /// normal run, which skips the generators.
    static var recordingDirectory: URL? {
        ProcessInfo.processInfo.environment["INTERVALLY_RECORD_FIXTURES"]
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// A value as the app encodes it, written with sorted keys and indentation for review:
    /// spacing and key order are all that differ from the app's own bytes.
    static func pretty(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value) + Data("\n".utf8)
    }

    /// One case per line, keys sorted, so a change in what the app decides shows in a pull
    /// request as exactly the cases it changes.
    static func lines(_ entries: [some Encodable]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let lines = try entries.map { "  " + String(decoding: try encoder.encode($0), as: UTF8.self) }
        return Data(("[\n" + lines.joined(separator: ",\n") + "\n]\n").utf8)
    }

    /// Writes `data` as `name`, and never over a file that is already there: a fixture is
    /// made once, from the version it freezes.
    static func record(_ data: Data, as name: String) throws {
        let directory = try #require(recordingDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: name), options: .withoutOverwriting)
    }
}
#endif

// MARK: - What the 1.2 files hold

extension Fixture {
    /// When the fixtures' runs began: 28 October 2026 at 12:00 UTC. A whole second, so it
    /// reads the same in any JSON.
    static let anchor12 = Date(timeIntervalSince1970: 1_793_188_800)

    /// 1.2's starters, written out rather than read from `SyncDocument.starterWorkouts`, so a
    /// later change there can't move what the files are held to.
    static let starters12: [IntervalWorkout] = [
        IntervalWorkout(
            id: UUID(uuidString: "6A1E0C2B-5D4F-4E43-9C1A-000000000001")!, name: "Classic",
            prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 8
        ),
        IntervalWorkout(
            id: UUID(uuidString: "6A1E0C2B-5D4F-4E43-9C1A-000000000002")!, name: "Tabata",
            prepareSeconds: 10, workSeconds: 20, restSeconds: 10, rounds: 8
        ),
        IntervalWorkout(
            id: UUID(uuidString: "6A1E0C2B-5D4F-4E43-9C1A-000000000003")!, name: "EMOM",
            prepareSeconds: 10, workSeconds: 45, restSeconds: 15, rounds: 10
        ),
    ]

    // Three presets as the iPhone's editor leaves them: phases renamed or given another
    // figure, an activity for Health, a warmup and a cooldown.

    /// 0 to 15 Get Ready, 15 to 315 Warmup, then six 30-second Sprints with 90-second Walks
    /// between (the first Sprint 315 to 345), and a cooldown from 945 to the end at 1245.
    static let hillSprints12 = IntervalWorkout(
        id: UUID(uuidString: "5B2E8C41-3F6A-4D17-9A0C-1E7D4B6F2A81")!, name: "Hill Sprints",
        prepareSeconds: 15, warmupSeconds: 300, workSeconds: 30, restSeconds: 90, rounds: 6,
        cooldownSeconds: 300, activity: .outdoorRun,
        phaseLabels: [
            "work": PhaseLabel(name: "Sprint", symbol: .sprint),
            "rest": PhaseLabel(name: "Walk", symbol: .walk),
        ]
    )

    /// A renamed lead-in that keeps its own figure.
    static let boxing12 = IntervalWorkout(
        id: UUID(uuidString: "C83F1A6D-0B4E-47A2-8D5C-9E61F2B7A043")!, name: "Boxing",
        prepareSeconds: 10, warmupSeconds: 180, workSeconds: 180, restSeconds: 60, rounds: 12,
        cooldownSeconds: 120, activity: .boxing,
        phaseLabels: [
            "prepare": PhaseLabel(name: "Gloves On", symbol: .hourglass),
            "work": PhaseLabel(name: "Fight", symbol: .boxing),
            "rest": PhaseLabel(name: "Corner", symbol: .breathe),
        ]
    )

    /// No lead-in, and a rest that keeps its name but wears another figure.
    static let rowLadder12 = IntervalWorkout(
        id: UUID(uuidString: "2D7A9F03-6C1B-4E85-B4A0-7F3E8D2C5B16")!, name: "Row Ladder",
        prepareSeconds: 0, warmupSeconds: 600, workSeconds: 60, restSeconds: 30, rounds: 10,
        cooldownSeconds: 300, activity: .rowing,
        phaseLabels: [
            "warmup": PhaseLabel(name: "Easy Row", symbol: .row),
            "work": PhaseLabel(name: "Pull", symbol: .row),
            "rest": PhaseLabel(name: "Rest", symbol: .breathe),
            "cooldown": PhaseLabel(name: "Stretch", symbol: .stretch),
        ]
    )

    /// `workouts.json`: the starters, then the three edited presets, as `WorkoutStore` lists
    /// and saves them.
    static let workouts12 = starters12 + [hillSprints12, boxing12, rowLadder12]

    /// `syncdocument.json`: Classic as installed; Tabata given two more rounds on the watch;
    /// EMOM given an activity and a phase name that was then reset, and deleted on the iPhone,
    /// so a tombstone; Hill Sprints added on the iPhone, then moved to the top of the list;
    /// and Hill Sprints chosen on the watch.
    static let document12: SyncDocument = {
        let phone = "8E4B1C7A-2D9F-4A63-B0E5-6C1F3A8D7E24"
        let watch = "F1A63D9E-7B2C-4085-9E4D-3B7A1C6F0D58"
        var tabata = starters12[1]
        tabata.rounds = 10
        var emom = starters12[2]
        emom.activity = .crossTraining
        emom.phaseLabels = [:]
        let records = [
            PresetRecord(id: starters12[0].id, workout: starters12[0], deleted: false, order: 0, stamp: .origin),
            PresetRecord(
                id: tabata.id, workout: tabata, deleted: false, order: 1,
                stamp: SyncStamp(millis: 1_793_150_000_000, device: watch), orderStamp: .origin
            ),
            PresetRecord(
                id: emom.id, workout: emom, deleted: true, order: 2,
                stamp: SyncStamp(millis: 1_793_160_000_000, device: phone), orderStamp: .origin
            ),
            PresetRecord(
                id: hillSprints12.id, workout: hillSprints12, deleted: false, order: -65_536,
                stamp: SyncStamp(millis: 1_793_100_042_000, device: phone),
                orderStamp: SyncStamp(millis: 1_793_170_000_000, device: phone)
            ),
        ]
        return SyncDocument(
            presets: Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) }),
            selected: Register(value: hillSprints12.id, stamp: SyncStamp(millis: 1_793_180_000_000, device: watch))
        )
    }()

    /// `runsnapshot-running.json`: Hill Sprints, started at `anchor12`.
    static let runningSnapshot12 = RunSnapshot(workout: hillSprints12, anchor: anchor12, pausedElapsed: nil)

    /// `runsnapshot-paused.json`: Hill Sprints paused 330.5 seconds in, 15.5 seconds into the
    /// first Sprint. A paused run's anchor is the moment it paused, and nothing reads it.
    static let pausedSnapshot12 = RunSnapshot(
        workout: hillSprints12, anchor: anchor12.addingTimeInterval(330.5), pausedElapsed: 330.5
    )

    /// `runmirror-messages.json`: what 1.2 sends over a mirrored workout session, the watch's
    /// states one way and the iPhone's buttons the other.
    static let mirrorMessages12: [String: RunMirrorMessage] = [
        "state-running": .state(RunMirrorState(
            workout: hillSprints12, status: .running, anchor: anchor12, pausedElapsed: nil, health: nil
        )),
        "state-paused": .state(RunMirrorState(
            workout: hillSprints12, status: .paused, anchor: nil, pausedElapsed: 330.5, health: nil
        )),
        "state-finished": .state(RunMirrorState(
            workout: hillSprints12, status: .finished, anchor: nil, pausedElapsed: nil, health: .saved
        )),
        "state-stopped": .state(RunMirrorState(
            workout: hillSprints12, status: .stopped, anchor: nil, pausedElapsed: nil, health: nil
        )),
        "command-pause": .command(.pause),
        "command-resume": .command(.resume),
        "command-skip": .command(.skip(phase: 2)),
        "command-end": .command(.end),
        "command-refresh": .command(.refresh),
    ]
}
