//
//  WorkoutsModelTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// A `ProGating` a test can flip without StoreKit.
@MainActor
final class FakePro: ProGating {
    var isPro: Bool
    init(isPro: Bool = false) { self.isPro = isPro }
}

/// What the Workouts screen and the editor do to presets: the free limit, naming, Put on
/// Watch, delete and reorder.
@Suite("Workouts actions")
@MainActor
struct WorkoutsModelTests {
    let defaults = makeTestDefaults()
    let pro = FakePro()

    private func makeActions() -> PresetActions {
        PresetActions(store: WorkoutStore(defaults: defaults), pro: pro)
    }

    // MARK: - Adding

    @Test("+ under the limit opens the editor on a new preset, saved and unselected")
    func addUnderTheLimit() throws {
        let actions = makeActions()
        let store = actions.store
        store.delete(store.workouts[2])
        let selected = store.selectedID

        guard case .edit(let added) = actions.addNew() else {
            Issue.record("Expected the editor")
            return
        }
        #expect(added.name == "New Workout")
        #expect(store.workouts.last == added)
        #expect(added.rhythm == "30s · 15s · 8×")
        #expect(store.selectedID == selected, "Only Put on Watch changes what the watch starts next")
        #expect(WorkoutStore(defaults: defaults).workouts.last == added, "Saved, so it syncs")
    }

    @Test("+ at the free limit opens the paywall and adds nothing")
    func addAtTheLimit() {
        let actions = makeActions()
        #expect(actions.store.workouts.count == ProProduct.freePresetLimit)
        #expect(actions.canAdd == false)
        #expect(actions.addNew() == .paywall)
        #expect(actions.store.workouts.count == 3)
    }

    @Test("With Pro, + has no limit, and each new name is its own")
    func addWithPro() {
        pro.isPro = true
        let actions = makeActions()
        #expect(actions.addNew() != .paywall)
        #expect(actions.addNew() != .paywall)
        #expect(actions.store.workouts.suffix(2).map(\.name) == ["New Workout", "New Workout 2"])
    }

    @Test("Pro flipping on lifts the limit at once")
    func limitFollowsPro() {
        let actions = makeActions()
        #expect(actions.canAdd == false)
        pro.isPro = true
        #expect(actions.canAdd)
    }

    // MARK: - Duplicate

    @Test("Duplicate names the copy as the watch does, and keeps every value")
    func duplicateNaming() throws {
        pro.isPro = true
        let actions = makeActions()
        var tabata = try #require(actions.store.workouts.first { $0.name == "Tabata" })
        tabata.warmupSeconds = 300
        actions.store.update(tabata)
        tabata = try #require(actions.store.workouts.first { $0.name == "Tabata" })

        guard case .edit(let copy) = actions.duplicate(tabata) else {
            Issue.record("Expected a copy")
            return
        }
        #expect(copy.name == PresetNaming.uniqueName(after: "Tabata", among: ["Classic", "Tabata", "EMOM"]))
        #expect(copy.name == "Tabata 2")
        #expect(copy.id != tabata.id)
        var expected = tabata
        expected.id = copy.id
        expected.name = copy.name
        #expect(copy == expected, "Warmup and the rest come along")

        guard case .edit(let again) = actions.duplicate(copy) else {
            Issue.record("Expected a copy")
            return
        }
        #expect(again.name == "Tabata 3", "A copy of a copy counts on rather than stacking suffixes")
    }

    @Test("Duplicate at the free limit opens the paywall and copies nothing")
    func duplicateAtTheLimit() {
        let actions = makeActions()
        #expect(actions.duplicate(actions.store.workouts[0]) == .paywall)
        #expect(actions.store.workouts.count == 3)
    }

    // MARK: - Put on Watch, delete, reorder

    @Test("Put on Watch selects the preset, and only that")
    func putOnWatch() {
        let actions = makeActions()
        let emom = actions.store.workouts[2]
        #expect(actions.isUpNext(emom) == false)
        actions.putOnWatch(emom)
        #expect(actions.isUpNext(emom))
        #expect(actions.store.selected == emom)
        #expect(WorkoutStore.selectedPreset(in: defaults) == emom, "What the complication offers")
    }

    @Test("Delete removes a preset, and refuses the last one")
    func deleteRefusesTheLast() {
        let actions = makeActions()
        let store = actions.store
        #expect(actions.delete(store.workouts[0]))
        #expect(actions.delete(store.workouts[0]))
        #expect(store.workouts.count == 1)
        #expect(actions.canDelete == false)
        #expect(actions.delete(store.workouts[0]) == false)
        #expect(store.workouts.count == 1)
    }

    @Test("Deleting a preset that is already gone changes nothing")
    func deleteGone() {
        let actions = makeActions()
        #expect(actions.delete(IntervalWorkout(name: "Elsewhere")) == false)
        #expect(actions.store.workouts.count == 3)
    }

    @Test("Reorder persists, and reaches the copies the watch's complication reads")
    func reorderPersists() {
        let actions = makeActions()
        actions.move(fromOffsets: [2], toOffset: 0)
        #expect(actions.store.workouts.map(\.name) == ["EMOM", "Classic", "Tabata"])
        #expect(WorkoutStore(defaults: defaults).workouts.map(\.name) == ["EMOM", "Classic", "Tabata"])
    }

    // MARK: - The paywall's follow-up

    @Test("A follow-up runs once, and only after an unlock")
    func followUpNeedsAnUnlock() {
        var followUp = PaywallFollowUp<WorkoutsView.FollowUp>()
        followUp.open(for: .addNew)
        #expect(followUp.closed() == nil, "Backed out: nothing added")

        followUp.open(for: .duplicate(WorkoutStore.starterWorkouts[1].id))
        followUp.unlocked()
        #expect(followUp.closed() == .duplicate(WorkoutStore.starterWorkouts[1].id))
        #expect(followUp.closed() == nil, "Only once")
    }

    @Test("An unlock with no paywall open for anything leaves nothing to run")
    func unlockWithoutPaywall() {
        var followUp = PaywallFollowUp<WorkoutsView.FollowUp>()
        followUp.unlocked()
        #expect(followUp.closed() == nil)
        followUp.open(for: .addNew)
        #expect(followUp.closed() == nil, "The earlier unlock doesn't carry over")
    }

    // MARK: - The watch on the Workouts screen

    @Test("Up next names the watch only when there is one")
    func upNextTitle() {
        #expect(WorkoutsContent.upNextTitle(peer: .ready) == "Up next on your watch")
        #expect(WorkoutsContent.upNextTitle(peer: .appNotInstalled) == "Up next on your watch")
        #expect(WorkoutsContent.upNextTitle(peer: .activating) == "Up next on your watch")
        #expect(WorkoutsContent.upNextTitle(peer: .notPaired) == "Up next")
        #expect(WorkoutsContent.upNextTitle(peer: .unsupported) == "Up next")
    }

    /// On iPad, or an iPhone with no watch paired, nothing is removed from any watch.
    @Test("Delete's confirmation names the watch only when there is one", arguments: [
        PeerState.unsupported, .activating, .notPaired, .appNotInstalled, .ready,
    ])
    func deleteMessage(peer: PeerState) {
        let message = WorkoutsContent.deleteMessage(peer: peer)
        #expect(message.contains("watch") == peer.hasWatch)
        #expect(message == (peer.hasWatch ? "It's removed from your watch too." : "This can't be undone."))
    }

    @Test("The bring-your-presets hint shows until the watch has sent anything", arguments: [
        PeerState.unsupported, .activating, .notPaired, .appNotInstalled, .ready,
    ])
    func watchHint(peer: PeerState) {
        #expect(WorkoutsContent.showsWatchHint(peer: peer, lastReceivedAt: nil) == (peer == .ready))
        #expect(WorkoutsContent.showsWatchHint(peer: peer, lastReceivedAt: Date()) == false)
        #expect(WorkoutsContent.watchHint == "Open Intervally on your watch to bring your presets over.")
    }
}
