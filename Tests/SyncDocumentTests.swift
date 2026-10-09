//
//  SyncDocumentTests.swift
//  IntervallyTests
//

import Testing
import Foundation
@testable import Intervally

/// A clock far enough ahead of any wall clock (the year 2128) that every tick is
/// `last + 1`: stamps then depend only on the order of the edits, so a seeded run replays
/// exactly.
private let logicalBase: Int64 = 5_000_000_000_000

/// One device in a sync test: its document and its clock.
private struct Replica {
    var document = SyncDocument.fresh
    var clock: SyncClock

    init(_ device: String, last: Int64 = 0) {
        clock = SyncClock(device: device, last: last)
    }

    /// Receives `remote` exactly as `WorkoutStore.merge(_:)` does.
    mutating func receive(_ remote: SyncDocument) {
        document = document.receiving(remote, clock: &clock)
    }
}

/// The document as the other side decodes it from an application context.
private func overTheWire(_ document: SyncDocument) throws -> SyncDocument {
    try #require(SyncWire.document(from: SyncWire.context(for: document)))
}

/// Sends `replicas[sender]`'s document to the other replica, which replies while its merge
/// differs from what arrived, as WatchSync does. Returns how many documents were sent.
private func settle(_ replicas: inout [Replica], from sender: Int) throws -> Int {
    var from = sender
    var sent = 0
    while sent < 10 {
        let document = try overTheWire(replicas[from].document)
        sent += 1
        replicas[1 - from].receive(document)
        guard replicas[1 - from].document != document else { break }
        from = 1 - from
    }
    return sent
}

@Suite("Sync document")
struct SyncDocumentTests {

    // MARK: Fresh installs

    @Test("Two fresh installs merge to the same three starters")
    func freshInstallsAgree() {
        var phone = Replica("phone"), watch = Replica("watch")
        phone.receive(watch.document)
        watch.receive(phone.document)
        #expect(phone.document.workouts.map(\.name) == ["Classic", "Tabata", "EMOM"])
        #expect(phone.document == watch.document)
        #expect(phone.document == .fresh)
    }

    @Test("The starters' ids are the same in every install, not just in this process")
    func starterIDsAreFixed() {
        // Literals: a random id per launch would still agree with itself inside one test
        // process, and only a second install would show the duplicates.
        #expect(SyncDocument.fresh.workouts.map(\.id.uuidString) == [
            "6A1E0C2B-5D4F-4E43-9C1A-000000000001",
            "6A1E0C2B-5D4F-4E43-9C1A-000000000002",
            "6A1E0C2B-5D4F-4E43-9C1A-000000000003",
        ])
        #expect(WorkoutStore.starterWorkouts.map(\.id) == SyncDocument.starterIDs)
        #expect(SyncDocument.fresh.selected.value == SyncDocument.starterIDs[0])
    }

    @Test("Control: starters with random ids would list every starter twice")
    func randomStarterIDsDuplicate() {
        func randomStarters() -> SyncDocument {
            var document = SyncDocument.fresh
            document.presets = [:]
            for (index, starter) in SyncDocument.starterWorkouts.enumerated() {
                var copy = starter
                copy.id = UUID()
                document.presets[copy.id] = PresetRecord(id: copy.id, workout: copy, deleted: false, order: Int64(index), stamp: .origin)
            }
            return document
        }
        #expect(randomStarters().merged(with: randomStarters()).workouts.count == 6)
    }

    // MARK: Conflicts

    @Test("Concurrent edits to different presets both survive")
    func concurrentEditsSurvive() {
        var phone = Replica("phone"), watch = Replica("watch")
        var classic = phone.document.workouts[0]
        classic.workSeconds = 40
        var tabata = watch.document.workouts[1]
        tabata.restSeconds = 25
        phone.document.upsert(classic, clock: &phone.clock)
        watch.document.upsert(tabata, clock: &watch.clock)

        phone.receive(watch.document)
        watch.receive(phone.document)
        #expect(phone.document == watch.document)
        #expect(phone.document.workouts[0].workSeconds == 40)
        #expect(phone.document.workouts[1].restSeconds == 25)
    }

    @Test("An edit made after seeing the other's wins, even with a clock five minutes behind")
    func laterEditWinsDespiteSkew() {
        var phone = Replica("phone"), watch = Replica("watch")
        // The phone's clock runs five minutes ahead of the watch's.
        let watchWall = Int64(Date().timeIntervalSince1970 * 1000)
        phone.clock.last = watchWall + 300_000
        var edit = phone.document.workouts[0]
        edit.rounds = 5
        phone.document.upsert(edit, clock: &phone.clock)

        watch.receive(phone.document)
        edit.rounds = 12
        watch.document.upsert(edit, clock: &watch.clock)
        let watchStamp = watch.document.presets[edit.id]!.stamp
        #expect(watchStamp > phone.document.presets[edit.id]!.stamp)
        #expect(watchStamp.millis > watchWall + 60_000, "Stamped past its own wall clock, which would have lost")

        phone.receive(watch.document)
        #expect(phone.document.workouts[0].rounds == 12)
        #expect(phone.document == watch.document)
    }

    @Test("A delete replicates and stays deleted")
    func deleteReplicates() {
        var phone = Replica("phone"), watch = Replica("watch")
        let emom = phone.document.workouts[2].id
        #expect(phone.document.delete(emom, clock: &phone.clock))

        watch.receive(phone.document)
        phone.receive(watch.document)
        #expect(!watch.document.workouts.contains { $0.id == emom })
        #expect(watch.document.presets[emom]?.deleted == true)
        #expect(phone.document == watch.document)
    }

    @Test("An edit stamped after a delete brings the preset back on both devices")
    func laterEditBeatsDelete() {
        var phone = Replica("phone"), watch = Replica("watch")
        let emom = phone.document.workouts[2]
        phone.document.delete(emom.id, clock: &phone.clock)
        var edit = emom
        edit.rounds = 3
        watch.clock.last = phone.clock.last + 1
        watch.document.upsert(edit, clock: &watch.clock)

        phone.receive(watch.document)
        watch.receive(phone.document)
        #expect(phone.document == watch.document)
        #expect(phone.document.workouts.contains { $0.id == emom.id && $0.rounds == 3 })
    }

    @Test("Each device deleting the other's last preset repairs to one shared preset")
    func mutualLastDeleteRepairs() throws {
        var phone = Replica("phone"), watch = Replica("watch")
        let ids = phone.document.workouts.map(\.id)
        phone.document.delete(ids[0], clock: &phone.clock)
        phone.document.delete(ids[1], clock: &phone.clock)
        watch.document.delete(ids[2], clock: &watch.clock)
        watch.document.delete(ids[1], clock: &watch.clock)

        var replicas = [phone, watch]
        let sent = try settle(&replicas, from: 0)
        #expect(replicas[0].document.workouts.count == 1)
        #expect(replicas[0].document == replicas[1].document)
        #expect(sent <= 2)
    }

    @Test("Delete refuses the last live preset")
    func deleteRefusesLast() {
        var replica = Replica("phone")
        let ids = replica.document.workouts.map(\.id)
        #expect(replica.document.delete(ids[0], clock: &replica.clock))
        #expect(replica.document.delete(ids[1], clock: &replica.clock))
        let before = replica.document
        #expect(replica.document.delete(ids[2], clock: &replica.clock) == false)
        #expect(replica.document == before)
        #expect(replica.document.delete(ids[0], clock: &replica.clock) == false, "Already a tombstone")
    }

    @Test("The selection is last writer wins")
    func selectionLastWriterWins() {
        var phone = Replica("phone"), watch = Replica("watch")
        watch.document.select(watch.document.workouts[2].id, clock: &watch.clock)
        phone.clock.last = watch.clock.last
        phone.document.select(phone.document.workouts[1].id, clock: &phone.clock)

        phone.receive(watch.document)
        watch.receive(phone.document)
        #expect(watch.document.selected.value == SyncDocument.starterIDs[1])
        #expect(phone.document == watch.document)
    }

    @Test("An exact tie keeps the receiver's own copy")
    func tieKeepsLocal() {
        let stamp = SyncStamp(millis: 42, device: "phone")
        var mine = SyncDocument.fresh, theirs = SyncDocument.fresh
        let id = SyncDocument.starterIDs[0]
        mine.presets[id]?.stamp = stamp
        mine.presets[id]?.workout.name = "Mine"
        theirs.presets[id]?.stamp = stamp
        theirs.presets[id]?.workout.name = "Theirs"
        mine.selected = Register(value: SyncDocument.starterIDs[1], stamp: stamp)
        theirs.selected = Register(value: SyncDocument.starterIDs[2], stamp: stamp)

        #expect(mine.merged(with: theirs).presets[id]?.workout.name == "Mine")
        #expect(theirs.merged(with: mine).presets[id]?.workout.name == "Theirs")
        #expect(mine.merged(with: theirs).selected.value == SyncDocument.starterIDs[1])
    }

    // MARK: Ordering

    @Test("A new preset goes after every other, an edit keeps its place")
    func upsertOrder() {
        var replica = Replica("phone")
        let added = IntervalWorkout(name: "Hills")
        replica.document.upsert(added, clock: &replica.clock)
        #expect(replica.document.workouts.map(\.name) == ["Classic", "Tabata", "EMOM", "Hills"])

        var tabata = replica.document.workouts[1]
        tabata.name = "Tabata+"
        replica.document.upsert(tabata, clock: &replica.clock)
        #expect(replica.document.workouts.map(\.name) == ["Classic", "Tabata+", "EMOM", "Hills"])
    }

    @Test("A new preset still lands last after a move to the bottom")
    func addAfterBottomMove() {
        var replica = Replica("phone")
        replica.document.upsert(IntervalWorkout(name: "Hills"), clock: &replica.clock)
        replica.document.move(fromOffsets: [0], toOffset: 4, clock: &replica.clock)
        #expect(replica.document.workouts.map(\.name) == ["Tabata", "EMOM", "Hills", "Classic"])

        replica.document.upsert(IntervalWorkout(name: "Sprints"), clock: &replica.clock)
        #expect(replica.document.workouts.last?.name == "Sprints")
    }

    @Test("Moving between neighbours with no room renumbers, then later moves fit between them")
    func moveRenumbersOnCollision() {
        var replica = Replica("phone")
        let before = replica.document
        // The starters sit at 0, 1, 2: nothing fits between Classic and Tabata.
        #expect(replica.document.move(fromOffsets: [2], toOffset: 1, clock: &replica.clock))
        #expect(replica.document.workouts.map(\.name) == ["Classic", "EMOM", "Tabata"])

        let spacing = SyncDocument.orderSpacing
        let orders = replica.document.workouts.map { replica.document.presets[$0.id]!.order }
        #expect(orders == [0, spacing, 2 * spacing])
        // Classic kept its order, so it kept its stamp: a concurrent edit to it survives.
        let classic = SyncDocument.starterIDs[0]
        #expect(replica.document.presets[classic] == before.presets[classic])

        // Now there is room: the next move restamps only the preset that moved.
        let renumbered = replica.document
        #expect(replica.document.move(fromOffsets: [0], toOffset: 2, clock: &replica.clock))
        #expect(replica.document.workouts.map(\.name) == ["EMOM", "Classic", "Tabata"])
        let changed = replica.document.presets.keys.filter { replica.document.presets[$0] != renumbered.presets[$0] }
        #expect(changed == [classic])
    }

    @Test("Moves to the top and the bottom, and of several presets at once")
    func moveEdges() {
        var replica = Replica("phone")
        replica.document.upsert(IntervalWorkout(name: "Hills"), clock: &replica.clock)
        replica.document.upsert(IntervalWorkout(name: "Sprints"), clock: &replica.clock)

        replica.document.move(fromOffsets: [4], toOffset: 0, clock: &replica.clock)
        #expect(replica.document.workouts.map(\.name) == ["Sprints", "Classic", "Tabata", "EMOM", "Hills"])

        replica.document.move(fromOffsets: [0, 2], toOffset: 5, clock: &replica.clock)
        #expect(replica.document.workouts.map(\.name) == ["Classic", "EMOM", "Hills", "Sprints", "Tabata"])

        replica.document.move(fromOffsets: [3, 4], toOffset: 1, clock: &replica.clock)
        #expect(replica.document.workouts.map(\.name) == ["Classic", "Sprints", "Tabata", "EMOM", "Hills"])
    }

    @Test("A move that leaves everything in place stamps nothing", arguments: [(0, 0), (0, 1), (2, 3), (1, 2)])
    func noOpMove(from: Int, to: Int) {
        var replica = Replica("phone")
        let before = replica.document
        #expect(replica.document.move(fromOffsets: [from], toOffset: to, clock: &replica.clock) == false)
        #expect(replica.document == before)
    }

    @Test("Out-of-range offsets move nothing")
    func invalidMove() {
        var replica = Replica("phone")
        #expect(replica.document.move(fromOffsets: [7], toOffset: 0, clock: &replica.clock) == false)
        #expect(replica.document.move(fromOffsets: [0], toOffset: 9, clock: &replica.clock) == false)
        #expect(replica.document == .fresh)
    }

    @Test("A reorder on one device is the order on the other")
    func moveReplicates() {
        var phone = Replica("phone"), watch = Replica("watch")
        phone.document.move(fromOffsets: [2], toOffset: 0, clock: &phone.clock)
        phone.document.move(fromOffsets: [2], toOffset: 1, clock: &phone.clock)
        watch.receive(phone.document)
        #expect(watch.document.workouts.map(\.name) == ["EMOM", "Tabata", "Classic"])
        #expect(watch.document == phone.document)
    }

    // MARK: Places and contents

    /// The first reorder on a fresh install, between two starters, renumbers the presets
    /// after it. That once restamped their contents too, with this device's copies.
    @Test("An edit on one device survives a reorder on the other that renumbers its preset")
    func editSurvivesRenumberingMove() throws {
        var phone = Replica("phone", last: logicalBase), watch = Replica("watch", last: logicalBase)
        phone.document.upsert(IntervalWorkout(name: "Hill Sprints"), clock: &phone.clock)
        watch.receive(phone.document)

        // At the gym without the phone, the watch changes Tabata. An hour later the phone,
        // still unaware, drags Hill Sprints between Classic and Tabata.
        var tabata = watch.document.workouts[1]
        tabata.rounds = 12
        watch.document.upsert(tabata, clock: &watch.clock)
        phone.clock.last = watch.clock.last + 3_600_000
        let before = try #require(phone.document.presets[tabata.id])
        #expect(phone.document.move(fromOffsets: [3], toOffset: 1, clock: &phone.clock))
        let renumbered = try #require(phone.document.presets[tabata.id])
        #expect(renumbered.order != before.order, "No room between the starters: Tabata is renumbered")
        #expect(renumbered.stamp == before.stamp, "Its place is written, never its contents")

        var replicas = [phone, watch]
        _ = try settle(&replicas, from: 0)
        for replica in replicas {
            #expect(replica.document.workouts.map(\.name) == ["Classic", "Hill Sprints", "Tabata", "EMOM"])
            #expect(replica.document.workouts[2].rounds == 12)
        }
        #expect(replicas[0].document == replicas[1].document)
    }

    @Test("A move and an edit of the same preset on the two devices both survive, in either order", arguments: [false, true])
    func moveAndEditBothSurvive(editFirst: Bool) throws {
        var phone = Replica("phone", last: logicalBase), watch = Replica("watch", last: logicalBase)
        var emom = watch.document.workouts[2]
        emom.rounds = 4
        if editFirst {
            watch.document.upsert(emom, clock: &watch.clock)
            phone.clock.last = watch.clock.last + 1_000
            #expect(phone.document.move(fromOffsets: [2], toOffset: 0, clock: &phone.clock))
        } else {
            #expect(phone.document.move(fromOffsets: [2], toOffset: 0, clock: &phone.clock))
            watch.clock.last = phone.clock.last + 1_000
            watch.document.upsert(emom, clock: &watch.clock)
        }

        var replicas = [phone, watch]
        _ = try settle(&replicas, from: 1)
        for replica in replicas {
            #expect(replica.document.workouts.map(\.name) == ["EMOM", "Classic", "Tabata"])
            #expect(replica.document.workouts[0].rounds == 4)
        }
        #expect(replicas[0].document == replicas[1].document)
    }

    @Test("A move made after seeing the other's move wins, even with a clock five minutes behind")
    func laterMoveWinsDespiteSkew() {
        var phone = Replica("phone"), watch = Replica("watch")
        phone.clock.last = Int64(Date().timeIntervalSince1970 * 1000) + 300_000
        phone.document.move(fromOffsets: [2], toOffset: 0, clock: &phone.clock)
        watch.receive(phone.document)
        #expect(watch.document.workouts.map(\.name) == ["EMOM", "Classic", "Tabata"])

        // The clock saw the phone's move, though it wrote no contents and no selection.
        watch.document.move(fromOffsets: [0], toOffset: 3, clock: &watch.clock)
        phone.receive(watch.document)
        #expect(phone.document.workouts.map(\.name) == ["Classic", "Tabata", "EMOM"])
        #expect(phone.document == watch.document)
    }

    @Test("A place's stamp travels with the document; a record without one was placed when written")
    func orderStampCoding() throws {
        var replica = Replica("phone")
        replica.document.move(fromOffsets: [2], toOffset: 0, clock: &replica.clock)
        let moved = try #require(replica.document.presets[SyncDocument.starterIDs[2]])
        #expect(moved.orderStamp > moved.stamp)
        #expect(try overTheWire(replica.document) == replica.document)

        let json = Data("""
        {"presets": [{"id": "6A1E0C2B-5D4F-4E43-9C1A-000000000001", "order": 3,
                      "stamp": {"millis": 9, "device": "phone"}}]}
        """.utf8)
        let record = try #require(JSONDecoder().decode(SyncDocument.self, from: json).presets[SyncDocument.starterIDs[0]])
        #expect(record.orderStamp == SyncStamp(millis: 9, device: "phone"))
    }

    // MARK: Legacy import

    @Test("A preset list from before sync is imported in order, stamped as this device's write")
    func importsLegacyList() {
        var clock = SyncClock(device: "watch")
        let hills = IntervalWorkout(name: "Hills"), sprints = IntervalWorkout(name: "Sprints")
        let document = SyncDocument.imported([hills, sprints, hills], selectedID: sprints.id, clock: &clock)

        #expect(document.workouts == [hills, sprints])
        #expect(document.presets[hills.id]?.order == 0)
        #expect(document.presets[sprints.id]?.order == 1)
        #expect(document.selected.value == sprints.id)
        #expect(document.presets.values.allSatisfy { $0.stamp.device == "watch" && $0.stamp > .origin })
        #expect(document.selected.stamp > .origin)

        let unknownSelection = SyncDocument.imported([hills], selectedID: UUID(), clock: &clock)
        #expect(unknownSelection.selected.value == hills.id)
    }

    // MARK: Decoding

    @Test("Unknown fields and a higher schema still decode")
    func lenientDecoding() throws {
        let json = Data("""
        {"schema": 2, "settings": {"tapStrength": "strongest"},
         "presets": [
           {"id": "6A1E0C2B-5D4F-4E43-9C1A-000000000001", "deleted": false, "order": 0, "colour": "red",
            "stamp": {"millis": 9, "device": "phone", "zone": "UTC"},
            "workout": {"id": "0E4C1F6A-7B1D-4C55-8A2E-5D9B3F1C7A10", "name": "Classic", "workSeconds": 40,
                        "rounds": 8, "stretchSeconds": 60}}
         ],
         "selected": {"value": "6A1E0C2B-5D4F-4E43-9C1A-000000000001", "stamp": {"millis": 9, "device": "phone"}}}
        """.utf8)
        let document = try JSONDecoder().decode(SyncDocument.self, from: json)
        let id = SyncDocument.starterIDs[0]
        #expect(document.workouts.count == 1)
        #expect(document.presets[id]?.workout.workSeconds == 40)
        #expect(document.presets[id]?.stamp == SyncStamp(millis: 9, device: "phone"))
        #expect(document.presets[id]?.workout.id == id, "The record's id wins over the workout's")
        #expect(document.selected.value == id)
    }

    @Test("An unreadable record costs only that record; a missing preset list is no document")
    func lossyRecords() throws {
        let json = Data("""
        {"presets": [
           {"id": "not a uuid"},
           {"id": "6A1E0C2B-5D4F-4E43-9C1A-000000000002"},
           42
         ]}
        """.utf8)
        let document = try JSONDecoder().decode(SyncDocument.self, from: json)
        #expect(Array(document.presets.keys) == [SyncDocument.starterIDs[1]])
        #expect(document.presets.values.first?.stamp == .origin)
        #expect(document.selected == Register(value: nil, stamp: .origin))

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SyncDocument.self, from: Data(#"{"selected": null}"#.utf8))
        }
    }

    @Test("A document round-trips through JSON, and equal documents encode to equal bytes")
    func codableRoundTrip() throws {
        var replica = Replica("phone")
        replica.document.upsert(IntervalWorkout(name: "Hills", warmupSeconds: 300), clock: &replica.clock)
        replica.document.delete(SyncDocument.starterIDs[1], clock: &replica.clock)
        let data = try JSONEncoder().encode(replica.document)
        #expect(try JSONDecoder().decode(SyncDocument.self, from: data) == replica.document)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let copy = try JSONDecoder().decode(SyncDocument.self, from: data)
        #expect(try encoder.encode(copy) == encoder.encode(replica.document))
    }

    // MARK: Wire format

    @Test("The context is a valid property list, and its document is LZFSE-compressed JSON")
    func contextIsPropertyList() throws {
        var replica = Replica("phone")
        for index in 0..<100 {
            replica.document.upsert(IntervalWorkout(name: "Preset \(index)", warmupSeconds: 300, cooldownSeconds: 300), clock: &replica.clock)
        }
        for workout in replica.document.workouts.prefix(50) {
            replica.document.delete(workout.id, clock: &replica.clock)
        }
        let sentAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let context = try SyncWire.context(for: replica.document, sentAt: sentAt)

        #expect(PropertyListSerialization.propertyList(context, isValidFor: .binary))
        #expect(context[SyncWire.schemaKey] as? Int == SyncDocument.currentSchema)
        #expect(context[SyncWire.sentAtKey] as? Date == sentAt)
        let compressed = try #require(context[SyncWire.documentKey] as? Data)
        let json = try (compressed as NSData).decompressed(using: .lzfse) as Data
        #expect(try JSONDecoder().decode(SyncDocument.self, from: json) == replica.document)
        #expect(SyncWire.document(from: context) == replica.document)
        // 103 presets, 50 of them tombstones, far inside what an application context carries.
        #expect(compressed.count < 16_384)
        #expect(compressed.count < json.count / 2)
    }

    @Test("Two sends of the same document are still two different contexts")
    func contextsAreDistinct() throws {
        let first = try SyncWire.context(for: .fresh, sentAt: Date(timeIntervalSinceReferenceDate: 1))
        let second = try SyncWire.context(for: .fresh, sentAt: Date(timeIntervalSinceReferenceDate: 2))
        #expect(!NSDictionary(dictionary: first).isEqual(to: second))
        #expect(SyncWire.document(from: first) == SyncWire.document(from: second))
    }

    @Test("Anything that isn't a document reads as nothing")
    func garbageContexts() throws {
        let notJSON = try (Data("hello".utf8) as NSData).compressed(using: .lzfse) as Data
        let notADocument = try (Data(#"{"name": "Classic"}"#.utf8) as NSData).compressed(using: .lzfse) as Data
        let contexts: [[String: Any]] = [
            [:],
            [SyncWire.documentKey: "doc"],
            [SyncWire.documentKey: Data()],
            [SyncWire.documentKey: Data([0x00, 0xFF, 0x13, 0x37])],
            [SyncWire.documentKey: try JSONEncoder().encode(SyncDocument.fresh)],
            [SyncWire.documentKey: notJSON],
            [SyncWire.documentKey: notADocument],
        ]
        for context in contexts {
            #expect(SyncWire.document(from: context) == nil)
        }
    }

    // MARK: Clock

    @Test("The clock never runs backwards and stays ahead of what it has seen")
    func clockIsMonotonic() {
        var clock = SyncClock(device: "watch")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = clock.tick(now: now)
        let second = clock.tick(now: now.addingTimeInterval(-3600))
        #expect(second > first)
        #expect(second.millis == first.millis + 1)

        var seen = SyncDocument.fresh
        seen.selected.stamp = SyncStamp(millis: first.millis + 1_000_000, device: "phone")
        clock.observe(seen)
        #expect(clock.tick(now: now).millis == first.millis + 1_000_001)
    }

    // MARK: Properties

    @Test("Merging is commutative, idempotent and associative")
    func mergeAlgebra() {
        var a = Replica("a"), b = Replica("b"), c = Replica("c")
        a.document.upsert(IntervalWorkout(name: "A"), clock: &a.clock)
        a.document.delete(SyncDocument.starterIDs[0], clock: &a.clock)
        b.document.select(SyncDocument.starterIDs[2], clock: &b.clock)
        var tabata = b.document.workouts[1]
        tabata.rounds = 20
        b.document.upsert(tabata, clock: &b.clock)
        c.document.move(fromOffsets: [0], toOffset: 3, clock: &c.clock)

        #expect(a.document.merged(with: b.document) == b.document.merged(with: a.document))
        #expect(a.document.merged(with: a.document) == a.document)
        #expect(a.document.merged(with: b.document).merged(with: c.document)
                == a.document.merged(with: b.document.merged(with: c.document)))
    }

    /// Two devices editing at random while only the latest context is ever delivered, as with
    /// `updateApplicationContext`, and deliveries go missing. Then they connect.
    @Test("Seeded random runs converge, with the merge algebra holding throughout")
    func randomizedConvergence() throws {
        var rng = SeededGenerator(seed: 0x1D7E_57A1)
        let trials = 2000
        var converged = 0, algebraHolds = 0, maxSent = 0

        for _ in 0..<trials {
            var replicas = [Replica("phone", last: logicalBase), Replica("watch", last: logicalBase)]
            // The latest document waiting for delivery to each side.
            var pending: [SyncDocument?] = [nil, nil]
            var neverEmpty = true

            for _ in 0..<Int.random(in: 1...40, using: &rng) {
                let side = Int.random(in: 0...1, using: &rng)
                var me = replicas[side]
                let live = me.document.workouts
                switch Int.random(in: 0..<9, using: &rng) {
                case 0:
                    me.document.upsert(IntervalWorkout(id: rng.uuid(), name: "New"), clock: &me.clock)
                case 1, 2:
                    var workout = live.randomElement(using: &rng)!
                    workout.rounds = Int.random(in: 1...99, using: &rng)
                    me.document.upsert(workout, clock: &me.clock)
                case 3:
                    me.document.delete(live.randomElement(using: &rng)!.id, clock: &me.clock)
                case 4:
                    me.document.select(live.randomElement(using: &rng)!.id, clock: &me.clock)
                case 5:
                    var source = IndexSet(integer: Int.random(in: 0..<live.count, using: &rng))
                    if Bool.random(using: &rng) { source.insert(Int.random(in: 0..<live.count, using: &rng)) }
                    me.document.move(fromOffsets: source, toOffset: Int.random(in: 0...live.count, using: &rng), clock: &me.clock)
                default:
                    if let document = pending[side], Bool.random(using: &rng) {
                        me.receive(try overTheWire(document))
                        pending[side] = nil
                    }
                }
                neverEmpty = neverEmpty && !me.document.workouts.isEmpty
                replicas[side] = me
                // Every change is pushed, replacing whatever the other side hadn't received.
                pending[1 - side] = me.document
            }

            let a = replicas[0].document, b = replicas[1].document
            var third = Replica("third", last: logicalBase)
            third.document.upsert(IntervalWorkout(id: rng.uuid(), name: "C"), clock: &third.clock)
            third.document.delete(SyncDocument.starterIDs[Int.random(in: 0...2, using: &rng)], clock: &third.clock)
            let c = third.document
            if a.merged(with: b) == b.merged(with: a),
               a.merged(with: a) == a,
               a.merged(with: b).merged(with: c) == a.merged(with: b.merged(with: c)) {
                algebraHolds += 1
            }

            let sent = try settle(&replicas, from: Int.random(in: 0...1, using: &rng))
            maxSent = max(maxSent, sent)
            let settled = replicas[0].document
            if settled == replicas[1].document, neverEmpty, !settled.workouts.isEmpty,
               Set(settled.workouts.map(\.id)).count == settled.workouts.count {
                converged += 1
            }
        }

        #expect(converged == trials)
        #expect(algebraHolds == trials)
        #expect(maxSent <= 2, "A merged result already holds the sender's state, so one reply settles it")
    }
}

/// SplitMix64: the same sequence for the same seed, so a failing trial replays exactly.
private struct SeededGenerator: RandomNumberGenerator {
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
