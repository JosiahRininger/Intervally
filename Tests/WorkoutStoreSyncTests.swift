//
//  WorkoutStoreSyncTests.swift
//  IntervallyTests
//

import Testing
import Foundation
@testable import Intervally

/// The other device: a copy of a document, edited with a clock of its own.
private struct OtherDevice {
    var document: SyncDocument
    var clock = SyncClock(device: "other-device")

    init(_ document: SyncDocument) {
        self.document = document
        clock.observe(document)
    }
}

/// How the store keeps its sync document, and how merging another device's behaves.
@Suite("Workout store sync")
@MainActor
struct WorkoutStoreSyncTests {
    let defaults = makeTestDefaults()

    /// A store whose local-change reports are counted.
    private func makeStore() -> (WorkoutStore, Counter) {
        let store = WorkoutStore(defaults: defaults)
        let reports = Counter()
        store.onLocalChange = { reports.increment() }
        return (store, reports)
    }

    /// This install's device id, as the store saved it.
    private func storedDevice() throws -> String {
        let data = try #require(defaults.data(forKey: WorkoutStore.Key.clock))
        return try JSONDecoder().decode(SyncClock.self, from: data).device
    }

    // MARK: Local edits

    enum Edit: String, CaseIterable {
        case update, add, delete, move, select
    }

    @Test("Every local edit stamps the document with this install and reports once", arguments: Edit.allCases)
    func localEditStamps(_ edit: Edit) throws {
        let (store, reports) = makeStore()
        let before = store.document

        switch edit {
        case .update:
            var classic = store.workouts[0]
            classic.workSeconds = 45
            store.update(classic)
        case .add:
            store.add(IntervalWorkout(name: "Hills"))
        case .delete:
            store.delete(store.workouts[1])
        case .move:
            store.move(fromOffsets: [2], toOffset: 0)
        case .select:
            store.selectedID = store.workouts[2].id
        }

        #expect(reports.value == 1)
        #expect(store.document != before)
        let device = try storedDevice()
        // The latest of a record's two stamps: a move writes only the place's.
        let restamped = store.document.presets.values.filter { before.presets[$0.id] != $0 }.map(\.latestStamp)
            + (store.document.selected != before.selected ? [store.document.selected.stamp] : [])
        #expect(!restamped.isEmpty)
        #expect(restamped.allSatisfy { $0.device == device && $0 > .origin })
        // Saved, so a relaunch holds the same document.
        #expect(WorkoutStore(defaults: defaults).document == store.document)
    }

    @Test("An edit that changes nothing stamps nothing and reports nothing")
    func noOpEditsStampNothing() {
        let (store, reports) = makeStore()
        let before = store.document

        store.update(store.selected)
        var unclamped = store.selected
        unclamped.rounds = 10_000
        store.update(unclamped)
        let clamped = store.document
        store.update(unclamped)
        store.selectedID = store.selectedID
        store.selectedID = UUID()
        store.move(fromOffsets: [1], toOffset: 1)
        store.update(IntervalWorkout(name: "Never added"))

        #expect(reports.value == 1, "Only the clamped rounds were a change")
        #expect(clamped != before)
        #expect(store.document == clamped)
    }

    @Test("Adding selects the new preset in the same edit; deleting the selected one selects the first")
    func addAndDeleteSelect() {
        let (store, reports) = makeStore()
        let hills = store.add(IntervalWorkout(name: "Hills"))
        #expect(store.selectedID == hills.id)
        #expect(store.document.selected.value == hills.id)

        store.delete(hills)
        #expect(store.selectedID == store.workouts[0].id)
        #expect(store.document.selected.value == store.workouts[0].id, "Stamped, not just derived")
        #expect(reports.value == 2)
    }

    @Test("A reorder is saved and survives a relaunch")
    func reorderPersists() {
        let (store, reports) = makeStore()
        store.move(fromOffsets: [2], toOffset: 0)
        #expect(store.workouts.map(\.name) == ["EMOM", "Classic", "Tabata"])
        #expect(reports.value == 1)

        let reloaded = WorkoutStore(defaults: defaults)
        #expect(reloaded.workouts.map(\.name) == ["EMOM", "Classic", "Tabata"])
        #expect(WorkoutStore.selectedPreset(in: defaults)?.name == "Classic", "The selection doesn't move with the list")
    }

    @Test("Deleting the last preset is still refused, also after a merge leaves only one")
    func lastPresetSurvives() {
        let (store, reports) = makeStore()
        var other = OtherDevice(store.document)
        other.document.delete(SyncDocument.starterIDs[0], clock: &other.clock)
        other.document.delete(SyncDocument.starterIDs[1], clock: &other.clock)
        store.merge(other.document)
        #expect(store.workouts.map(\.name) == ["EMOM"])

        store.delete(store.workouts[0])
        #expect(store.workouts.map(\.name) == ["EMOM"])
        #expect(reports.value == 0)
    }

    // MARK: Merging

    @Test("A merge folds in the other device's edits without stamping or reporting")
    func mergeDoesNotStamp() {
        let (store, reports) = makeStore()
        var other = OtherDevice(store.document)
        var tabata = other.document.workouts[1]
        tabata.rounds = 20
        other.document.upsert(tabata, clock: &other.clock)
        other.document.upsert(IntervalWorkout(name: "Hills"), clock: &other.clock)
        let before = store.document

        let result = store.merge(other.document)
        #expect(store.document == before.merged(with: other.document))
        #expect(store.workouts.map(\.name) == ["Classic", "Tabata", "EMOM", "Hills"])
        #expect(store.workouts[1].rounds == 20)
        #expect(reports.value == 0)
        #expect(result == WorkoutStore.MergeResult(changed: true, selectedPresetChanged: false, mergedDiffersFromRemote: false))
    }

    @Test("Remote edits reach the copies the complication reads, and a relaunch")
    func mergeUpdatesDerivedCopies() {
        let (store, _) = makeStore()
        var other = OtherDevice(store.document)
        var classic = other.document.workouts[0]
        classic.name = "Hills"
        other.document.upsert(classic, clock: &other.clock)

        let renamed = store.merge(other.document)
        #expect(renamed.selectedPresetChanged)
        #expect(WorkoutStore.selectedPreset(in: defaults)?.name == "Hills")

        other.document.select(SyncDocument.starterIDs[2], clock: &other.clock)
        let reselected = store.merge(other.document)
        #expect(reselected.selectedPresetChanged)
        #expect(store.selectedID == SyncDocument.starterIDs[2])
        #expect(WorkoutStore.selectedPreset(in: defaults)?.name == "EMOM")

        let reloaded = WorkoutStore(defaults: defaults)
        #expect(reloaded.workouts.map(\.name) == ["Hills", "Tabata", "EMOM"])
        #expect(reloaded.selected.name == "EMOM")
    }

    @Test("A remote delete of the selected preset falls back to the first without stamping")
    func remoteDeleteOfSelection() {
        let (store, reports) = makeStore()
        store.selectedID = SyncDocument.starterIDs[2]
        var other = OtherDevice(store.document)
        other.document.delete(SyncDocument.starterIDs[2], clock: &other.clock)
        let selectionBefore = store.document.selected

        let result = store.merge(other.document)
        #expect(store.selectedID == SyncDocument.starterIDs[0])
        #expect(store.document.selected == selectionBefore, "The register still names the deleted preset")
        #expect(WorkoutStore.selectedPreset(in: defaults)?.name == "Classic")
        #expect(result.selectedPresetChanged)
        #expect(result.mergedDiffersFromRemote == false, "Nothing to send back, so no ping-pong")
        #expect(reports.value == 1, "Only the local selection")

        // Choosing the preset the fallback put on screen records it as a real selection.
        store.selectedID = SyncDocument.starterIDs[0]
        #expect(store.document.selected.value == SyncDocument.starterIDs[0])
        #expect(reports.value == 2)
        store.selectedID = SyncDocument.starterIDs[0]
        #expect(reports.value == 2)
    }

    @Test("The merge says when the sender is behind")
    func mergeReportsWhatTheSenderLacks() {
        let (store, _) = makeStore()
        let other = OtherDevice(store.document)
        #expect(store.merge(other.document) == .unchanged)

        store.add(IntervalWorkout(name: "Hills"))
        let behind = store.merge(other.document)
        #expect(behind.changed == false)
        #expect(behind.mergedDiffersFromRemote)
        #expect(store.merge(store.document) == .unchanged)
    }

    @Test("Two fresh installs merge to the three starters")
    func freshStoresAgree() {
        let (store, _) = makeStore()
        let elsewhere = WorkoutStore(defaults: makeTestDefaults())
        #expect(store.merge(elsewhere.document) == .unchanged)
        #expect(store.workouts == WorkoutStore.starterWorkouts)
    }

    @Test("A merge to five keeps every preset editable and the free tier gated")
    func freeLimitAfterMerge() throws {
        let (store, _) = makeStore()
        var other = OtherDevice(store.document)
        other.document.upsert(IntervalWorkout(name: "Hills"), clock: &other.clock)
        other.document.upsert(IntervalWorkout(name: "Sprints"), clock: &other.clock)
        store.merge(other.document)
        #expect(store.workouts.count == 5)
        #expect(FakePro().canAddPreset(currentCount: store.workouts.count) == false)

        for workout in store.workouts {
            var edited = workout
            edited.workSeconds = 50
            store.update(edited)
        }
        let reloaded = WorkoutStore(defaults: defaults)
        #expect(reloaded.workouts.count == 5)
        #expect(reloaded.workouts.allSatisfy { $0.workSeconds == 50 })
    }

    @Test("A merge that would leave no preset restores one, and tells the sender")
    func mergeRepairsEmptyList() {
        let (store, reports) = makeStore()
        var other = OtherDevice(store.document)
        store.delete(store.workouts[0])
        store.delete(store.workouts[0])
        other.document.delete(SyncDocument.starterIDs[2], clock: &other.clock)
        other.document.delete(SyncDocument.starterIDs[1], clock: &other.clock)

        let result = store.merge(other.document)
        #expect(store.workouts.count == 1)
        #expect(result.mergedDiffersFromRemote)
        #expect(reports.value == 2, "The two local deletes; the repair travels in the reply")
    }

    /// The watch's Rename sheet holds the preset as it was when the sheet opened, and saving
    /// that copy put back what the iPhone had changed since, on both devices.
    @Test("A rename keeps what the other device changed while the name was being typed")
    func renameKeepsMergedEdits() {
        let (store, reports) = makeStore()
        let opened = store.workouts[0]
        var other = OtherDevice(store.document)
        var classic = other.document.workouts[0]
        classic.workSeconds = 60
        other.document.upsert(classic, clock: &other.clock)
        store.merge(other.document)

        store.rename(opened.id, to: "Sprints")
        #expect(store.workouts[0].name == "Sprints")
        #expect(store.workouts[0].workSeconds == 60)
        #expect(reports.value == 1)

        other.document = other.document.receiving(store.document, clock: &other.clock)
        #expect(other.document.workouts[0].name == "Sprints")
        #expect(other.document.workouts[0].workSeconds == 60)

        // The same name again, or a preset that is gone, changes nothing.
        store.rename(opened.id, to: "Sprints")
        store.rename(UUID(), to: "Nobody")
        #expect(reports.value == 1)
    }

    // MARK: Loading

    @Test("A fresh install saves its document, its derived copies and a stable device id")
    func freshInstallSaves() throws {
        let (store, _) = makeStore()
        #expect(defaults.data(forKey: WorkoutStore.Key.document) != nil)
        #expect(defaults.data(forKey: WorkoutStore.Key.workouts) != nil)
        #expect(store.document == .fresh)
        #expect(store.isSyncSuspended == false)

        let device = try storedDevice()
        var classic = store.workouts[0]
        classic.rounds = 4
        store.update(classic)
        #expect(try storedDevice() == device)
        #expect(store.document.presets[classic.id]?.stamp.device == device)
    }

    @Test("A preset list saved before sync is imported once, in order, with its selection")
    func importsLegacyList() throws {
        let legacy = Data("""
        [{"id":"0E4C1F6A-7B1D-4C55-8A2E-5D9B3F1C7A10","name":"Hills","workSeconds":40,"rounds":6},
         {"id":"1F5D2A7B-8C2E-4D66-9B3F-6EAC4F2D8B21","name":"Sprints","workSeconds":15,"rounds":10}]
        """.utf8)
        defaults.set(legacy, forKey: WorkoutStore.Key.workouts)
        defaults.set("1F5D2A7B-8C2E-4D66-9B3F-6EAC4F2D8B21", forKey: WorkoutStore.Key.selected)

        let store = WorkoutStore(defaults: defaults)
        #expect(store.workouts.map(\.name) == ["Hills", "Sprints"])
        #expect(store.selected.name == "Sprints")
        #expect(store.isSyncSuspended == false)
        let device = try storedDevice()
        #expect(store.document.presets.values.allSatisfy { $0.stamp.device == device })
        #expect(store.document.selected.stamp.device == device)

        // Imported once: the next launch reads the saved document as it is.
        let saved = try #require(defaults.data(forKey: WorkoutStore.Key.document))
        let reloaded = WorkoutStore(defaults: defaults)
        #expect(reloaded.document == store.document)
        #expect(defaults.data(forKey: WorkoutStore.Key.document) == saved)
    }

    @Test("An unreadable document is kept as it is, and sync stays off")
    func unreadableDocumentSuspendsSync() throws {
        let garbage = Data("{\"presets\": 7".utf8)
        defaults.set(garbage, forKey: WorkoutStore.Key.document)
        let derived = try JSONEncoder().encode([IntervalWorkout(name: "Hills"), IntervalWorkout(name: "Sprints")])
        defaults.set(derived, forKey: WorkoutStore.Key.workouts)

        let (store, reports) = makeStore()
        #expect(store.isSyncSuspended)
        #expect(store.workouts.map(\.name) == ["Hills", "Sprints"], "The derived copies the last good launch wrote")
        #expect(defaults.data(forKey: WorkoutStore.Key.document) == garbage)

        var other = OtherDevice(.fresh)
        other.document.upsert(IntervalWorkout(name: "Remote"), clock: &other.clock)
        #expect(store.merge(other.document) == .unchanged)
        #expect(store.workouts.map(\.name) == ["Hills", "Sprints"])

        // Local edits still save, beside the unreadable document rather than over it.
        store.add(IntervalWorkout(name: "Local"))
        #expect(reports.value == 1)
        #expect(defaults.data(forKey: WorkoutStore.Key.document) == garbage)
        let reloaded = WorkoutStore(defaults: defaults)
        #expect(reloaded.isSyncSuspended)
        #expect(reloaded.workouts.map(\.name) == ["Hills", "Sprints", "Local"])
    }

    @Test("An unreadable preset list from before sync isn't overwritten at launch")
    func unreadableLegacyListIsKept() {
        let garbage = Data("not json".utf8)
        defaults.set(garbage, forKey: WorkoutStore.Key.workouts)

        let store = WorkoutStore(defaults: defaults)
        #expect(store.isSyncSuspended)
        #expect(store.workouts == WorkoutStore.starterWorkouts)
        #expect(defaults.data(forKey: WorkoutStore.Key.workouts) == garbage)
        #expect(defaults.data(forKey: WorkoutStore.Key.document) == nil)
    }

    @Test("Edits after launch beat everything stored, even when the clock was lost")
    func clockObservesStoredDocument() throws {
        var future = SyncDocument.fresh
        let classic = SyncDocument.starterIDs[0]
        future.presets[classic]?.stamp = SyncStamp(millis: 9_000_000_000_000, device: "other-device")
        defaults.set(try JSONEncoder().encode(future), forKey: WorkoutStore.Key.document)

        let (store, _) = makeStore()
        var edit = store.workouts[0]
        edit.rounds = 3
        store.update(edit)
        let stamp = try #require(store.document.presets[classic]?.stamp)
        #expect(stamp > SyncStamp(millis: 9_000_000_000_000, device: "other-device"))
    }

    @Test("A stored document whose derived copies went missing writes them again")
    func rewritesMissingDerivedCopies() throws {
        let (store, _) = makeStore()
        store.selectedID = SyncDocument.starterIDs[1]
        defaults.removeObject(forKey: WorkoutStore.Key.workouts)
        defaults.removeObject(forKey: WorkoutStore.Key.selected)

        _ = WorkoutStore(defaults: defaults)
        #expect(WorkoutStore.selectedPreset(in: defaults)?.name == "Tabata")
    }
}
