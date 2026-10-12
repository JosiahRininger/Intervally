//
//  QAEdit.swift
//  IntervallyPhone
//

#if DEBUG
import Foundation

/// One preset edit named on the command line (`-qaEdit`), made through the store exactly as
/// the user's own edit would be, so it is stamped and synced like one. Indices count from 0
/// in list order, as the list stands when the edit runs. Debug builds only.
enum QAEdit: Equatable {
    case select(Int)
    case rename(Int, String)
    case work(Int, Int)
    case rest(Int, Int)
    case rounds(Int, Int)
    case prepare(Int, Int)
    case warmup(Int, Int)
    case cooldown(Int, Int)
    case delete(Int)
    /// SwiftUI's `onMove` offsets: the preset at `from` goes before the one now at `to`.
    case move(from: Int, to: Int)
    case add(String)
    /// `label 0 work run Run`: the phase's name and figure, as Name & Icon sets them.
    case label(Int, IntervalPhase.Kind, PhaseSymbol, String)
    /// `unlabel 0`: every phase back to its own name and figure.
    case unlabel(Int)
    /// `activity 0 outdoorRun`: what Health records the preset as.
    case activity(Int, WorkoutActivity)

    /// The edits in `spec`, separated by semicolons, e.g. `rename 0 Sprint; work 0 45`. Nil
    /// if any one is unreadable: a typo must not leave half the edits made.
    static func parse(_ spec: String) -> [QAEdit]? {
        let commands = spec.split(separator: ";").map { $0.split(separator: " ").map(String.init) }
        guard !commands.isEmpty else { return nil }
        var edits: [QAEdit] = []
        for words in commands {
            guard let edit = edit(from: words) else { return nil }
            edits.append(edit)
        }
        return edits
    }

    private static func edit(from words: [String]) -> QAEdit? {
        guard let verb = words.first else { return nil }
        let numbers = words.dropFirst().map { Int($0) }
        let rest = words.dropFirst(2).joined(separator: " ")
        switch (verb, numbers.first ?? nil) {
        case ("select", let index?) where words.count == 2: return .select(index)
        case ("delete", let index?) where words.count == 2: return .delete(index)
        case ("rename", let index?) where !rest.isEmpty: return .rename(index, rest)
        case ("add", _) where words.count > 1: return .add(words.dropFirst().joined(separator: " "))
        case ("unlabel", let index?) where words.count == 2: return .unlabel(index)
        case ("activity", let index?) where words.count == 3:
            return WorkoutActivity(rawValue: words[2]).map { .activity(index, $0) }
        case ("label", let index?) where words.count >= 5:
            guard let kind = IntervalPhase.Kind(rawValue: words[2]),
                  let symbol = PhaseSymbol(rawValue: words[3]) else { return nil }
            return .label(index, kind, symbol, words.dropFirst(4).joined(separator: " "))
        default: break
        }
        guard words.count == 3, let first = numbers[0], let second = numbers[1] else { return nil }
        switch verb {
        case "work": return .work(first, second)
        case "rest": return .rest(first, second)
        case "rounds": return .rounds(first, second)
        case "prepare": return .prepare(first, second)
        case "warmup": return .warmup(first, second)
        case "cooldown": return .cooldown(first, second)
        case "move": return .move(from: first, to: second)
        default: return nil
        }
    }

    /// Makes the edit. One naming a preset that isn't there does nothing.
    @MainActor
    func apply(to store: WorkoutStore) {
        let workouts = store.workouts
        func preset(_ index: Int) -> IntervalWorkout? {
            workouts.indices.contains(index) ? workouts[index] : nil
        }
        func edit(_ index: Int, _ change: (inout IntervalWorkout) -> Void) {
            guard var workout = preset(index) else { return }
            change(&workout)
            store.update(workout)
        }
        switch self {
        case .select(let index):
            if let workout = preset(index) { store.selectedID = workout.id }
        case .rename(let index, let name): edit(index) { $0.name = name }
        case .work(let index, let seconds): edit(index) { $0.workSeconds = seconds }
        case .rest(let index, let seconds): edit(index) { $0.restSeconds = seconds }
        case .rounds(let index, let count): edit(index) { $0.rounds = count }
        case .prepare(let index, let seconds): edit(index) { $0.prepareSeconds = seconds }
        case .warmup(let index, let seconds): edit(index) { $0.warmupSeconds = seconds }
        case .cooldown(let index, let seconds): edit(index) { $0.cooldownSeconds = seconds }
        case .delete(let index):
            if let workout = preset(index) { store.delete(workout) }
        case .move(let from, let to):
            store.move(fromOffsets: [from], toOffset: to)
        case .add(let name):
            store.add(IntervalWorkout(name: name))
        case .label(let index, let kind, let symbol, let name):
            if let workout = preset(index) { store.setLabel(workout.id, kind: kind, to: PhaseLabel(name: name, symbol: symbol)) }
        case .unlabel(let index):
            edit(index) { $0.phaseLabels = [:] }
        case .activity(let index, let activity):
            if let workout = preset(index) { store.setActivity(workout.id, to: activity) }
        }
    }
}
#endif
