//
//  SyncMergeTests.swift
//  IntervallyTests, IntervallyPhoneTests
//

import Foundation
import Testing
#if os(watchOS)
@testable import Intervally
#else
@testable import IntervallyPhone
#endif

/// How two copies of one preset merge: to the same record whichever device merges first,
/// and without losing anything an older version never knew to its edits.
@Suite("Sync merge")
struct SyncMergeTests {
    private func record(_ workout: IntervalWorkout, at millis: Int64, on device: String, deleted: Bool = false) -> PresetRecord {
        PresetRecord(id: workout.id, workout: workout, deleted: deleted, order: 0, stamp: SyncStamp(millis: millis, device: device))
    }

    // MARK: Order

    /// The iPhone chose Outdoor Run and named the work phase at 100. The watch, out of range,
    /// changed the rounds (or deleted the preset) at 200 on a copy that had neither. The
    /// iPhone kept both on the watch's later write, but the watch, merging the iPhone's older
    /// copy into its own newer one, did not: the two disagreed until another round trip, and
    /// a third copy merged in another order could end up without them.
    @Test("A later copy without the activity or phase names takes them from an earlier one, whichever merges first", arguments: [false, true])
    func mergeCommutesForActivityAndLabels(laterIsTombstone: Bool) {
        var chosen = IntervalWorkout(name: "Hills", rounds: 6, activity: .outdoorRun)
        chosen.setLabel(PhaseLabel(name: "Climb", symbol: .run), for: .work)
        var bare = chosen
        bare.activity = nil
        bare.phaseLabels = nil
        bare.rounds = 10
        let earlier = record(chosen, at: 100, on: "phone")
        let later = record(bare, at: 200, on: "watch", deleted: laterIsTombstone)

        let onWatch = later.merged(with: earlier), onPhone = earlier.merged(with: later)
        #expect(onWatch == onPhone)
        #expect(onWatch.stamp == later.stamp)
        #expect(onWatch.workout.rounds == 10, "The later write still wins")
        #expect(onWatch.deleted == laterIsTombstone)
        #expect(onWatch.workout.activity == .outdoorRun)
        #expect(onWatch.workout.label(for: .work) == PhaseLabel(name: "Climb", symbol: .run))
    }

    // MARK: Older versions

    /// The watch runs an older version. It reads the preset without what it doesn't know,
    /// renames it and changes the rounds, and sends that back to the iPhone.
    @Test("An edit on an older version wins and keeps every field that version doesn't know", arguments: OlderVersion.allCases)
    func oldReplicaEditKeepsNewFields(_ version: OlderVersion) throws {
        let id = IntervalWorkout.everyFieldSet.id
        var phoneClock = SyncClock(device: "phone"), watchClock = SyncClock(device: "watch")
        var phone = SyncDocument.fresh
        phone.upsert(.everyFieldSet, clock: &phoneClock)

        var watch = try version.receiving(phone.overTheWire(), into: .fresh, clock: &watchClock)
        var edit = try #require(watch.presets[id]?.workout)
        #expect(edit == version.reading(.everyFieldSet))
        edit.name = "Hill Repeats"
        edit.rounds = 12
        watch.upsert(edit, clock: &watchClock)

        phone = try phone.receiving(watch.overTheWire(), clock: &phoneClock)
        var expected = IntervalWorkout.everyFieldSet
        expected.name = "Hill Repeats"
        expected.rounds = 12
        #expect(phone.presets[id]?.workout == expected)
        #expect(phone.presets[id]?.stamp == watch.presets[id]?.stamp, "The watch's later edit won")

        // The iPhone's reply settles the watch on the same preset, as far as it can hold it.
        watch = try version.receiving(phone.overTheWire(), into: watch, clock: &watchClock)
        #expect(watch == version.reading(phone))
    }

    // MARK: What 1.2 sends

    /// A document exactly as 1.2 (13) encodes it, with sorted keys as on the wire: Classic
    /// with an activity and a named work phase, Tabata deleted with its names put back,
    /// EMOM untouched, and Hills with warmup, cooldown and two named phases, moved to the top
    /// and selected. Checked against the 1.2 encoder before any 1.3 change; never edit it.
    static let shippedIn12 = """
        {"presets":[\
        {"deleted":false,"id":"6A1E0C2B-5D4F-4E43-9C1A-000000000001","order":0,\
        "orderStamp":{"device":"","millis":0},"stamp":{"device":"phone","millis":1760600000000},\
        "workout":{"activity":"outdoorRun","cooldownSeconds":0,"id":"6A1E0C2B-5D4F-4E43-9C1A-000000000001",\
        "name":"Classic","phaseLabels":{"work":{"name":"Run","symbol":"run"}},"prepareSeconds":10,\
        "restSeconds":15,"rounds":8,"warmupSeconds":0,"workSeconds":30}},\
        {"deleted":true,"id":"6A1E0C2B-5D4F-4E43-9C1A-000000000002","order":1,\
        "orderStamp":{"device":"","millis":0},"stamp":{"device":"watch","millis":1760600005000},\
        "workout":{"activity":"hiit","cooldownSeconds":0,"id":"6A1E0C2B-5D4F-4E43-9C1A-000000000002",\
        "name":"Tabata","phaseLabels":{},"prepareSeconds":10,"restSeconds":10,"rounds":8,\
        "warmupSeconds":0,"workSeconds":20}},\
        {"deleted":false,"id":"6A1E0C2B-5D4F-4E43-9C1A-000000000003","order":2,\
        "orderStamp":{"device":"","millis":0},"stamp":{"device":"","millis":0},\
        "workout":{"cooldownSeconds":0,"id":"6A1E0C2B-5D4F-4E43-9C1A-000000000003","name":"EMOM",\
        "prepareSeconds":10,"restSeconds":15,"rounds":10,"warmupSeconds":0,"workSeconds":45}},\
        {"deleted":false,"id":"9B2D4E7A-3C1F-4A8B-9E6D-2F5A7C1B3D40","order":-65536,\
        "orderStamp":{"device":"watch","millis":1760600009000},"stamp":{"device":"phone","millis":1760600002000},\
        "workout":{"cooldownSeconds":300,"id":"9B2D4E7A-3C1F-4A8B-9E6D-2F5A7C1B3D40","name":"Hills",\
        "phaseLabels":{"rest":{"name":"Walk","symbol":"walk"},"work":{"name":"Climb","symbol":"run"}},\
        "prepareSeconds":10,"restSeconds":60,"rounds":6,"warmupSeconds":300,"workSeconds":90}}\
        ],"schema":1,\
        "selected":{"stamp":{"device":"phone","millis":1760600010000},"value":"9B2D4E7A-3C1F-4A8B-9E6D-2F5A7C1B3D40"}}
        """

    @Test("A document as 1.2 sends it decodes, encodes back to the same bytes, and merges with itself unchanged")
    func shippedDocumentRoundTrips() throws {
        let document = try JSONDecoder().decode(SyncDocument.self, from: Data(Self.shippedIn12.utf8))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let reencoded = try String(decoding: encoder.encode(document), as: UTF8.self)
        #expect(reencoded == Self.shippedIn12)

        let hills = try #require(UUID(uuidString: "9B2D4E7A-3C1F-4A8B-9E6D-2F5A7C1B3D40"))
        let ids = SyncDocument.starterIDs
        #expect(document.workouts.map(\.name) == ["Hills", "Classic", "EMOM"])
        #expect(document.selected.value == hills)
        #expect(document.presets[ids[0]]?.workout.activity == .outdoorRun)
        #expect(document.presets[ids[0]]?.workout.label(for: .work) == PhaseLabel(name: "Run", symbol: .run))
        #expect(document.presets[ids[1]]?.deleted == true)
        #expect(document.presets[ids[1]]?.workout.phaseLabels == [:], "Put back, not never set")
        #expect(document.presets[ids[2]]?.workout.activity == nil)
        #expect(document.presets[hills]?.orderStamp == SyncStamp(millis: 1_760_600_009_000, device: "watch"))
        #expect(document.presets[hills]?.workout.warmupSeconds == 300)

        // Nothing changes merging it with itself, or with what an older version makes of it,
        // in either order.
        #expect(document.merged(with: document) == document)
        for version in OlderVersion.allCases {
            let older = version.reading(document)
            #expect(document.merged(with: older) == document)
            #expect(older.merged(with: document) == document)
        }
    }
}
