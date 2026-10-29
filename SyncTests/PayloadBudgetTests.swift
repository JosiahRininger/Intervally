//
//  PayloadBudgetTests.swift
//  IntervallyTests, IntervallyPhoneTests
//

import Foundation
import Testing
#if os(watchOS)
@testable import Intervally
#else
@testable import IntervallyPhone
#endif

/// How large the context sync sends can grow. Every preset goes in it whole, deleted ones too:
/// a tombstone keeps its last contents for the empty-list repair (`SyncDocument.repairIfEmpty`).
/// Every number has a range; the name has its cap (`IntervalWorkout.maxNameLength`).
@Suite("Sync payload budget")
struct PayloadBudgetTests {
    /// Bytes. WatchConnectivity turns away a payload it finds too large
    /// (`WCError.payloadTooLarge`); this keeps clear of that, with room for what a later
    /// version adds.
    static let budget = 48 * 1024

    /// Words people name workouts and phases with. A name is a run of them, so names differ
    /// from preset to preset and compress as typed names do.
    static let words = """
        Hill Sprint Repeats Tabata Burner Morning Evening Core Blast Ladder Pyramid Long Easy
        Tempo Rowing Bike Track Legs Arms Chest Back Glutes Cardio Power Endurance Recovery Warm
        Cool Fast Slow Steady Push Pull Squat Lunge Plank Burpee Jump Rope Boxing Kick Yoga
        Stretch Walk Jog Run Swim Stairs Kettlebell Dumbbell Circuit Interval Session Training
        Drill Round Minute Monday Tuesday Wednesday Thursday Friday Saturday Sunday Park Beach
        Gym Home Hotel Garage Club Team Coach Partner Quick Short Heavy Light Hard Mixed Strength
        Speed Agility Balance Mobility Flow Breath Focus Fire Storm Rocket Turbo Summit Peak River
        """.split(whereSeparator: \.isWhitespace).map(String.init)

    @Test("The largest document a user builds fits the budget: 99 presets named to the cap with every phase labelled, and 200 deleted")
    func worstCaseDocumentUnder48KB() throws {
        var rng = PayloadRandom(seed: 0x5EED_0025)
        let devices = [rng.uuid().uuidString, rng.uuid().uuidString]
        let kinds: [IntervalPhase.Kind] = [.prepare, .warmup, .work, .rest, .cooldown]
        /// Months of edits from either device: no two alike, and no run for compression to find.
        func stamp() -> SyncStamp {
            SyncStamp(millis: 1_790_000_000_000 + Int64.random(in: 0..<10_000_000_000, using: &rng), device: devices.randomElement(using: &rng)!)
        }
        /// Words until the phrase is longer than `count` characters.
        func phrase(longerThan count: Int) -> String {
            var phrase = Self.words.randomElement(using: &rng)!
            while phrase.count <= count { phrase += " " + Self.words.randomElement(using: &rng)! }
            return phrase
        }

        var presets: [UUID: PresetRecord] = [:]
        for index in 0..<299 {
            // Built on the preset with every field set, so a field added later is weighed too.
            var workout = IntervalWorkout.everyFieldSet
            workout.id = rng.uuid()
            // Far longer than a save keeps, and cut to the cap on the way in, as every save
            // is. Uncut, names this long would take the document past the budget.
            workout.name = phrase(longerThan: 200)
            workout.prepareSeconds = 300
            workout.warmupSeconds = 1800
            workout.workSeconds = 3600
            workout.restSeconds = 3600
            workout.rounds = 99
            workout.cooldownSeconds = 1800
            workout.activity = WorkoutActivity.allCases.randomElement(using: &rng)
            workout.phaseLabels = Dictionary(uniqueKeysWithValues: kinds.map { kind in
                let name = PhaseLabel.cleaned(phrase(longerThan: PhaseLabel.maxNameLength)) ?? kind.title
                return (kind.rawValue, PhaseLabel(name: name, symbol: PhaseSymbol.allCases.randomElement(using: &rng)!))
            })
            // Every one moved since it was added, so its place has a stamp of its own.
            let record = PresetRecord(
                id: workout.id, workout: workout.clamped, deleted: index >= 99,
                order: 1_790_000_000_000 + Int64.random(in: 0..<10_000_000_000, using: &rng),
                stamp: stamp(), orderStamp: stamp()
            )
            presets[record.id] = record
        }
        let live = presets.values.filter { !$0.deleted }.map(\.id).sorted { $0.uuidString < $1.uuidString }
        let document = SyncDocument(presets: presets, selected: Register(value: live.first, stamp: stamp()))
        #expect(document.workouts.count == 99)
        #expect(document.presets.count == 299)
        // At the cap, or one short where the cut fell on a space.
        let lengths = document.presets.values.map(\.workout.name.count)
        #expect(lengths.allSatisfy { (IntervalWorkout.maxNameLength - 1)...IntervalWorkout.maxNameLength ~= $0 })

        // The largest context there is: the theme and a start request beside the document.
        let sentAt = Date(timeIntervalSince1970: 1_790_000_000)
        let context = try SyncWire.context(
            for: document, theme: Register(value: "pastel", stamp: stamp()), sentAt: sentAt,
            start: SyncWire.StartRequest(id: rng.uuid(), presetID: live[0], requestedAt: sentAt)
        )
        let bytes = try PropertyListSerialization.data(fromPropertyList: context, format: .binary, options: 0).count
        #expect(bytes < Self.budget, "\(bytes) bytes")
        #expect(SyncWire.document(from: context) == document, "And it still arrives whole")
    }
}

/// SplitMix64: the same sequence for the same seed, so the document weighed is the same at
/// every run.
private struct PayloadRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func uuid() -> UUID {
        let bytes = (next(), next())
        return withUnsafeBytes(of: bytes) { UUID(uuid: $0.load(as: uuid_t.self)) }
    }
}
