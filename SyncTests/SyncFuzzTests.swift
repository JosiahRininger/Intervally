//
//  SyncFuzzTests.swift
//  IntervallyTests, IntervallyPhoneTests
//

import Foundation
import Testing
#if os(watchOS)
@testable import Intervally
#else
@testable import IntervallyPhone
#endif

/// A clock far enough ahead of any wall clock (the year 2128) that every tick is
/// `last + 1`: stamps then depend only on the order of the edits, so a seeded run replays
/// exactly.
private let logicalBase: Int64 = 5_000_000_000_000

/// Seeded random merges over every field a preset carries, and seeded random runs of this
/// build beside a version already out there.
@Suite("Sync fuzz")
struct SyncFuzzTests {

    // MARK: Every field

    @Test("Merging is commutative, associative and idempotent over every field, and keeps the newest of each")
    func allFieldsCommutativeAssociativeIdempotent() throws {
        var rng = FuzzRandom(seed: 0x5EED_0024)
        let trials = 5_000
        var failures: [String: Int] = [:]
        var firstFailure: Int?
        var seen = FieldsSeen()

        for trial in 0..<trials {
            let presets = (0..<3).map { _ in PresetHistory.random(using: &rng) }
            let choices: [UUID?] = [nil] + presets.map(\.id)
            let selections = distinctStamps(Int.random(in: 1...2, using: &rng), using: &rng).map { stamp in
                Register(value: choices.randomElement(using: &rng)!, stamp: stamp)
            }
            // Three devices' copies; one may lack a preset the others hold.
            let documents = (0..<3).map { _ in
                var records: [UUID: PresetRecord] = [:]
                for preset in presets where Int.random(in: 0..<4, using: &rng) > 0 {
                    records[preset.id] = preset.randomCopy(using: &rng)
                }
                return SyncDocument(presets: records, selected: selections.randomElement(using: &rng)!)
            }
            // Enough trials to see every field vary and cross the wire; both are slow.
            let isEarly = trial < 500
            if isEarly { documents.forEach { seen.record($0) } }
            let (a, b, c) = (documents[0], documents[1], documents[2])
            let merged = a.merged(with: b).merged(with: c)

            var broken: [String] = []
            if a.merged(with: b) != b.merged(with: a) || b.merged(with: c) != c.merged(with: b)
                || a.merged(with: c) != c.merged(with: a) {
                broken.append("commutative")
            }
            if merged != a.merged(with: b.merged(with: c)) { broken.append("associative") }
            if documents.contains(where: { $0.merged(with: $0) != $0 }) || merged.merged(with: merged) != merged {
                broken.append("idempotent")
            }
            if merged != Self.newestOfEach(in: documents) { broken.append("newest of each field") }
            if isEarly, try merged.overTheWire() != merged { broken.append("wire") }
            for property in broken { failures[property, default: 0] += 1 }
            if !broken.isEmpty, firstFailure == nil { firstFailure = trial }
        }

        #expect(failures.isEmpty, "\(failures) in \(trials) trials, the first in trial \(firstFailure ?? -1)")
        // So the fuzz keeps covering every field as fields are added.
        #expect(
            OptionalWorkoutField.allCases.map(\.name).sorted() == IntervalWorkout.everyFieldSet.optionalFieldNames.sorted(),
            "Each optional field needs a case in OptionalWorkoutField"
        )
        #expect(seen.neverVaried.isEmpty, "Never varied: \(seen.neverVaried)")
    }

    /// What merging `documents` in any order must give, worked out field by field: for each
    /// preset, its newest copy's contents with each optional field from the newest copy that
    /// has it, and its newest place; and the newest selection.
    private static func newestOfEach(in documents: [SyncDocument]) -> SyncDocument {
        var presets: [UUID: PresetRecord] = [:]
        for id in Set(documents.flatMap(\.presets.keys)) {
            let copies = documents.compactMap { $0.presets[id] }
            var newest = copies.max { $0.stamp < $1.stamp }!
            for field in OptionalWorkoutField.allCases {
                if let holder = copies.filter({ field.isSet(in: $0.workout) }).max(by: { $0.stamp < $1.stamp }) {
                    field.copy(from: holder.workout, to: &newest.workout)
                }
            }
            let placed = copies.max { $0.orderStamp < $1.orderStamp }!
            newest.order = placed.order
            newest.orderStamp = placed.orderStamp
            presets[id] = newest
        }
        return SyncDocument(presets: presets, selected: documents.map(\.selected).max { $0.stamp < $1.stamp }!)
    }

    // MARK: An older version

    /// This build and a version already out there, editing at random while deliveries go
    /// missing, as `randomizedConvergence` has two of this build do, then connecting. The
    /// older one can't hold what it doesn't know, so they must agree on what it does, and
    /// this build must keep the rest exactly as it last wrote it.
    @Test("This build and an older version settle on what the older one knows, and this build keeps the rest", arguments: OlderVersion.allCases)
    func olderVersionSettles(_ version: OlderVersion) throws {
        var rng = FuzzRandom(seed: 0x5EED_0012 &+ UInt64(OlderVersion.allCases.firstIndex(of: version)!))
        let trials = 1_000
        var failures: [String: Int] = [:]
        var firstFailure: Int?
        var maxSent = 0

        for trial in 0..<trials {
            // Either device may be the one still on the older version.
            let olderSide = Int.random(in: 0...1, using: &rng)
            var devices = [
                Device("phone", version: olderSide == 0 ? version : nil),
                Device("watch", version: olderSide == 1 ? version : nil),
            ]
            // The latest document waiting for delivery to each side.
            var pending: [SyncDocument?] = [nil, nil]
            // Each preset as this build last wrote it.
            var written: [UUID: IntervalWorkout] = [:]
            var broken: Set<String> = []

            for _ in 0..<Int.random(in: 1...40, using: &rng) {
                let side = Int.random(in: 0...1, using: &rng)
                var me = devices[side]
                let live = me.document.workouts
                switch Int.random(in: 0..<10, using: &rng) {
                case 0:
                    var added = PresetHistory.randomCore(id: rng.uuid(), using: &rng)
                    for field in OptionalWorkoutField.allCases where me.knows(field) && Bool.random(using: &rng) {
                        field.randomize(&added, using: &rng)
                    }
                    me.document.upsert(added, clock: &me.clock)
                    if me.version == nil { written[added.id] = added.clamped }
                case 1, 2, 3:
                    let current = live.randomElement(using: &rng)!
                    if me.version == nil,
                       version.unknownFields(of: current) != version.unknownFields(of: written[current.id] ?? IntervalWorkout(id: current.id)) {
                        broken.insert("this build edited a copy that had lost a field")
                    }
                    var edited = PresetHistory.randomCore(id: current.id, using: &rng)
                    for field in OptionalWorkoutField.allCases {
                        field.copy(from: current, to: &edited)
                        if me.knows(field), Int.random(in: 0..<3, using: &rng) == 0 { field.randomize(&edited, using: &rng) }
                    }
                    me.document.upsert(edited, clock: &me.clock)
                    if me.version == nil { written[edited.id] = edited.clamped }
                case 4:
                    me.document.delete(live.randomElement(using: &rng)!.id, clock: &me.clock)
                case 5:
                    me.document.select(live.randomElement(using: &rng)!.id, clock: &me.clock)
                case 6:
                    let source = IndexSet(integer: Int.random(in: 0..<live.count, using: &rng))
                    me.document.move(fromOffsets: source, toOffset: Int.random(in: 0...live.count, using: &rng), clock: &me.clock)
                default:
                    if let document = pending[side], Bool.random(using: &rng) {
                        me.receive(try document.overTheWire())
                        pending[side] = nil
                    }
                }
                devices[side] = me
                // Every change is pushed, replacing whatever the other side hadn't received.
                pending[1 - side] = me.document
            }

            let sent = try Self.settle(&devices, from: Int.random(in: 0...1, using: &rng))
            maxSent = max(maxSent, sent)
            let newer = devices[1 - olderSide].document, older = devices[olderSide].document
            if version.reading(newer) != older { broken.insert("settled apart") }
            if newer.workouts.isEmpty { broken.insert("no preset left") }
            for record in newer.presets.values
            where version.unknownFields(of: record.workout) != version.unknownFields(of: written[record.id] ?? IntervalWorkout(id: record.id)) {
                broken.insert("lost a field the older version doesn't know")
            }
            for property in broken { failures[property, default: 0] += 1 }
            if !broken.isEmpty, firstFailure == nil { firstFailure = trial }
        }

        #expect(failures.isEmpty, "\(failures) in \(trials) trials, the first in trial \(firstFailure ?? -1)")
        // An older version, merging this build's older copy into its own newer one, may still
        // lack what that copy had until this build's reply brings it: one send more than two
        // of this build need.
        #expect(maxSent <= 3)
    }

    /// Sends `devices[sender]`'s document to the other, which replies while what it holds
    /// differs from what arrived as it read it, as WatchSync does. Returns how many were sent.
    private static func settle(_ devices: inout [Device], from sender: Int) throws -> Int {
        var from = sender
        var sent = 0
        while sent < 10 {
            let document = try devices[from].document.overTheWire()
            sent += 1
            guard devices[1 - from].receive(document) else { break }
            from = 1 - from
        }
        return sent
    }
}

// MARK: - Generators

/// SplitMix64: the same sequence for the same seed, so a failing trial replays exactly.
private struct FuzzRandom: RandomNumberGenerator {
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

/// `count` different stamps, oldest first, from a pool small enough that millis often tie
/// and only the device tells two writes apart. The origin, the starters' stamp, is one.
private func distinctStamps(_ count: Int, using rng: inout FuzzRandom) -> [SyncStamp] {
    let pool = [SyncStamp.origin] + (1...3).flatMap { millis in
        ["phone", "watch"].map { SyncStamp(millis: Int64(millis), device: $0) }
    }
    return pool.shuffled(using: &rng).prefix(count).sorted()
}

/// One preset's writes, oldest first: its contents with their tombstone, and its places,
/// each under a stamp of its own. A copy of it is what one device holds.
///
/// Each optional field has one value through the history, from the write that first set
/// it, and the newest write may change it. Any copy may lack a field, as a version that
/// predates it holds the preset, except a copy of a newest write that changed it. That
/// keeps out the one shape the merge can't order (`PresetRecord.merged(with:)`): a filled
/// copy reads as if its own write had set the field, so a copy without it that meets two
/// older copies holding different values keeps the first it meets. That takes a third
/// copy, or both devices editing the preset at once, and the two still agree in the end.
private struct PresetHistory {
    let id: UUID
    var contents: [(stamp: SyncStamp, workout: IntervalWorkout, deleted: Bool)]
    var places: [(stamp: SyncStamp, order: Int64)]
    /// The optional fields the newest contents changed.
    var changedLast: Set<OptionalWorkoutField> = []

    static func random(using rng: inout FuzzRandom) -> PresetHistory {
        let id = rng.uuid()
        var contents = distinctStamps(Int.random(in: 1...3, using: &rng), using: &rng).map { stamp in
            (stamp: stamp, workout: randomCore(id: id, using: &rng), deleted: Int.random(in: 0..<4, using: &rng) == 0)
        }
        var changedLast: Set<OptionalWorkoutField> = []
        for field in OptionalWorkoutField.allCases where Int.random(in: 0..<3, using: &rng) > 0 {
            var value = IntervalWorkout(id: id)
            field.randomize(&value, using: &rng)
            for index in Int.random(in: 0..<contents.count, using: &rng)..<contents.count {
                field.copy(from: value, to: &contents[index].workout)
            }
            if Bool.random(using: &rng) {
                var change = value
                field.randomize(&change, using: &rng)
                field.copy(from: change, to: &contents[contents.count - 1].workout)
                if change != value { changedLast.insert(field) }
            }
        }
        let places = distinctStamps(Int.random(in: 1...2, using: &rng), using: &rng).map { stamp in
            (stamp: stamp, order: [0, 1, 2, -SyncDocument.orderSpacing, SyncDocument.orderSpacing].randomElement(using: &rng)!)
        }
        return PresetHistory(id: id, contents: contents, places: places, changedLast: changedLast)
    }

    /// Every field but the optional ones, each from a few values (in range, as a save clamps
    /// them) so that copies often agree on some and differ on others.
    static func randomCore(id: UUID, using rng: inout FuzzRandom) -> IntervalWorkout {
        IntervalWorkout(
            id: id,
            name: ["Hills", "Tabata", "Hill Sprints", "", "Löwe 🦁"].randomElement(using: &rng)!,
            prepareSeconds: [0, 10, 300].randomElement(using: &rng)!,
            warmupSeconds: [0, 300].randomElement(using: &rng)!,
            workSeconds: [5, 30, 3600].randomElement(using: &rng)!,
            restSeconds: [0, 15].randomElement(using: &rng)!,
            rounds: [1, 8, 99].randomElement(using: &rng)!,
            cooldownSeconds: [0, 1800].randomElement(using: &rng)!
        )
    }

    /// The preset as one device holds it: one of its contents and one of its places, perhaps
    /// without some optional fields.
    func randomCopy(using rng: inout FuzzRandom) -> PresetRecord {
        let index = Int.random(in: 0..<contents.count, using: &rng)
        var workout = contents[index].workout
        for field in OptionalWorkoutField.allCases where Int.random(in: 0..<4, using: &rng) == 0 {
            if index == contents.count - 1, changedLast.contains(field) { continue }
            field.clear(in: &workout)
        }
        let place = places.randomElement(using: &rng)!
        return PresetRecord(
            id: id, workout: workout, deleted: contents[index].deleted,
            order: place.order, stamp: contents[index].stamp, orderStamp: place.stamp
        )
    }
}

/// The values each stored property of a record and its workout took across the fuzz, found
/// by reflection, so a field added later and never varied fails the test instead of going
/// unchecked.
private struct FieldsSeen {
    private var values: [String: Set<String>] = [:]
    private var absent: [String: Set<Bool>] = [:]

    mutating func record(_ document: SyncDocument) {
        for record in document.presets.values {
            note(record, prefix: "")
            note(record.workout, prefix: "workout.")
        }
    }

    private mutating func note(_ subject: Any, prefix: String) {
        for child in Mirror(reflecting: subject).children {
            guard let label = child.label.map({ prefix + $0 }), label != "workout" else { continue }
            values[label, default: []].insert(String(describing: child.value))
            if let optional = child.value as? any ReflectedOptional {
                absent[label, default: []].insert(optional.isNone)
            }
        }
    }

    /// Properties that never took two values, or optional ones never both set and unset.
    var neverVaried: [String] {
        let fixed = values.filter { $0.value.count < 2 }.keys
        let stuck = absent.filter { $0.value.count < 2 }.keys
        return Set(fixed).union(stuck).sorted()
    }
}

/// One device in the older-version fuzz: this build, or a version already out there.
private struct Device {
    var document = SyncDocument.fresh
    var clock: SyncClock
    /// Nil for this build.
    let version: OlderVersion?

    init(_ name: String, version: OlderVersion?) {
        clock = SyncClock(device: name, last: logicalBase)
        self.version = version
    }

    func knows(_ field: OptionalWorkoutField) -> Bool {
        version?.knows(field) ?? true
    }

    /// Takes in what arrived, as this device's version does. True when what it now holds
    /// differs from what arrived as it read it, which is when WatchSync replies.
    @discardableResult
    mutating func receive(_ remote: SyncDocument) -> Bool {
        guard let version else {
            document = document.receiving(remote, clock: &clock)
            return document != remote
        }
        document = version.receiving(remote, into: document, clock: &clock)
        return document != version.reading(remote)
    }
}
