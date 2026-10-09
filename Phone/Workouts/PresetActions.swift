//
//  PresetActions.swift
//  IntervallyPhone
//

import Foundation

/// What the Workouts screen and the editor do to presets, apart from the views, so each rule
/// is testable: the free limit, duplicate naming, Put on Watch, delete and reorder.
@MainActor
struct PresetActions {
    let store: WorkoutStore
    let pro: any ProGating

    /// Where a tap that adds a preset leads.
    enum AddResult: Equatable {
        /// The new preset, already saved: its editor opens.
        case edit(IntervalWorkout)
        /// The free limit. The paywall opens first, and nothing has been added.
        case paywall
    }

    /// Only adding is gated. A device that holds more than the free limit, after a refund or
    /// a merge of offline adds, keeps editing, running and deleting every one.
    var canAdd: Bool { pro.canAddPreset(currentCount: store.workouts.count) }

    /// +: a preset with the starter rhythm under a name no other preset has. It leaves the
    /// selection alone: only Put on Watch changes what the watch starts next.
    func addNew() -> AddResult {
        guard canAdd else { return .paywall }
        let workout = IntervalWorkout(name: PresetNaming.newName(among: store.workouts.map(\.name)))
        return .edit(store.add(workout, select: false))
    }

    /// A copy of every stored value, warmup and cooldown included, named as the watch names
    /// copies ("Tabata" → "Tabata 2").
    func duplicate(_ workout: IntervalWorkout) -> AddResult {
        guard canAdd else { return .paywall }
        var copy = workout
        copy.id = UUID()
        copy.name = PresetNaming.uniqueName(after: workout.name, among: store.workouts.map(\.name))
        return .edit(store.add(copy, select: false))
    }

    func isUpNext(_ workout: IntervalWorkout) -> Bool {
        store.selectedID == workout.id
    }

    /// Makes it the preset the watch starts next, and the one its complication offers.
    func putOnWatch(_ workout: IntervalWorkout) {
        store.selectedID = workout.id
    }

    /// The last preset stays, as on the watch: there must always be one to start.
    var canDelete: Bool { store.workouts.count > 1 }

    @discardableResult
    func delete(_ workout: IntervalWorkout) -> Bool {
        guard canDelete, store.workouts.contains(where: { $0.id == workout.id }) else { return false }
        store.delete(workout)
        return true
    }

    /// Edit mode's reorder, with SwiftUI's `onMove` offsets. Synced like any edit.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        store.move(fromOffsets: source, toOffset: destination)
    }
}

/// A paywall opened on the way to something, and that something, held while the paywall is
/// up. It runs once the paywall closes, and only if Pro was unlocked there: backing out of
/// the paywall adds nothing and opens nothing.
struct PaywallFollowUp<Action: Equatable>: Equatable {
    /// What the paywall was opened for.
    private(set) var waiting: Action?
    private var isUnlocked = false

    mutating func open(for action: Action) {
        waiting = action
        isUnlocked = false
    }

    /// A purchase or a restore on that paywall unlocked Pro.
    mutating func unlocked() {
        isUnlocked = waiting != nil
    }

    /// The paywall has closed: what to finish now, at most once.
    mutating func closed() -> Action? {
        defer {
            waiting = nil
            isUnlocked = false
        }
        return isUnlocked ? waiting : nil
    }
}
