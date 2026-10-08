//
//  WorkoutStore.swift
//  Intervally
//

import Foundation
import Observation

/// A run that was in progress when the app went away, so it can be picked back up.
struct RunSnapshot: Codable, Equatable, Sendable {
    var workout: IntervalWorkout
    /// The virtual start instant. Elapsed time is `now - anchor`.
    var anchor: Date
    /// Set only when the run was paused; the elapsed time frozen at that moment.
    var pausedElapsed: TimeInterval?
}

/// Persists the user's presets and any in-flight run.
///
/// Backed by `UserDefaults` with `Codable` values. The legacy app wrote three loose
/// integer keys and got them wrong: `HostingController` seeded `"timerOn"` while
/// `SelectorOptions.key` read and wrote `"timeOn"`, so the seeded default and the saved
/// value lived at different keys and the work duration silently reset.
@MainActor
@Observable
final class WorkoutStore {

    /// Shared with the widget extension, which reads the active run to render a live
    /// countdown on the watch face.
    enum Key {
        static let workouts = "workouts.v2"
        static let selected = "selectedWorkoutID.v2"
        static let activeRun = "activeRun.v2"
        static let startTimes = "startTimes.v1"
    }

    /// Reads the persisted run without constructing a full store. Used by the widget,
    /// which has no business owning presets.
    nonisolated static func activeRun(in defaults: UserDefaults = SharedDefaults.suite) -> RunSnapshot? {
        guard let data = defaults.data(forKey: Key.activeRun) else { return nil }
        return try? JSONDecoder().decode(RunSnapshot.self, from: data)
    }

    /// The preset the setup screen is showing, read without a store: the complication's
    /// idle face offers to start it. Nil until the app has saved presets at least once.
    nonisolated static func selectedPreset(in defaults: UserDefaults = SharedDefaults.suite) -> IntervalWorkout? {
        guard let data = defaults.data(forKey: Key.workouts) else { return nil }
        let workouts = decodePresets(from: data)
        let storedID = defaults.string(forKey: Key.selected).flatMap(UUID.init(uuidString:))
        return workouts.first(where: { $0.id == storedID }) ?? workouts.first
    }

    // MARK: - Start history

    /// How many run starts are kept. Enough for a median that ignores the odd late session,
    /// few enough that a changed routine takes over within a couple of weeks.
    nonisolated static let startHistoryLimit = 10

    /// Remembers when a run began, so the complication can tell the Smart Stack when the
    /// user usually trains. A repeat of the last start is dropped: a run restored after a
    /// relaunch reports the same anchor, and it is not a second workout.
    nonisolated static func recordStart(_ date: Date = Date(), in defaults: UserDefaults = SharedDefaults.suite) {
        var starts = recentStarts(in: defaults)
        if let last = starts.last, abs(last.timeIntervalSince(date)) < 1 { return }
        starts.append(date)
        defaults.set(Array(starts.suffix(startHistoryLimit)), forKey: Key.startTimes)
    }

    nonisolated static func recentStarts(in defaults: UserDefaults = SharedDefaults.suite) -> [Date] {
        defaults.array(forKey: Key.startTimes) as? [Date] ?? []
    }

    /// The hour around the user's usual start, on the first day from `now` whose window has
    /// not already closed. Median rather than mean: one late-night session must not drag a
    /// morning habit into the afternoon.
    nonisolated static func usualStartWindow(
        from starts: [Date],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DateInterval? {
        guard !starts.isEmpty else { return nil }
        let minutes = starts
            .map { calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0) }
            .sorted()
        let median = minutes[minutes.count / 2]
        let halfWindow: TimeInterval = 30 * 60
        var day = calendar.startOfDay(for: now)
        // At most two tries: today's window, then tomorrow's.
        for _ in 0..<2 {
            guard let centre = calendar.date(byAdding: .minute, value: median, to: day) else { return nil }
            let window = DateInterval(start: centre.addingTimeInterval(-halfWindow), duration: 2 * halfWindow)
            if window.end >= now { return window }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
        }
        return nil
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    private(set) var workouts: [IntervalWorkout]
    var selectedID: UUID {
        didSet { defaults.set(selectedID.uuidString, forKey: Key.selected) }
    }

    init(defaults: UserDefaults = SharedDefaults.suite) {
        self.defaults = defaults

        let blob = defaults.data(forKey: Key.workouts)
        let decoded = blob.map(Self.decodePresets) ?? []

        let loaded = decoded.isEmpty ? Self.starterWorkouts : decoded
        self.workouts = loaded

        let storedID = defaults.string(forKey: Key.selected).flatMap(UUID.init(uuidString:))
        self.selectedID = loaded.first(where: { $0.id == storedID })?.id ?? loaded[0].id

        // Seed only a genuinely fresh install. A blob that exists but would not decode is
        // left exactly as it is: overwriting it with the starters would turn a decoding
        // problem into permanent loss of everything the user built.
        if blob == nil { persistWorkouts() }
    }

    /// Decodes presets one at a time, so a single unreadable entry costs that entry rather
    /// than the whole list.
    nonisolated private static func decodePresets(from data: Data) -> [IntervalWorkout] {
        struct Lossy: Decodable {
            let value: IntervalWorkout?
            init(from decoder: Decoder) throws {
                value = try? IntervalWorkout(from: decoder)
            }
        }
        guard let entries = try? JSONDecoder().decode([Lossy].self, from: data) else { return [] }
        return entries.compactMap(\.value)
    }

    // MARK: - Presets

    static let starterWorkouts: [IntervalWorkout] = [
        IntervalWorkout(name: "Classic", prepareSeconds: 10, workSeconds: 30, restSeconds: 15, rounds: 8),
        IntervalWorkout(name: "Tabata", prepareSeconds: 10, workSeconds: 20, restSeconds: 10, rounds: 8),
        IntervalWorkout(name: "EMOM", prepareSeconds: 10, workSeconds: 45, restSeconds: 15, rounds: 10),
    ]

    var selected: IntervalWorkout {
        get { workouts.first(where: { $0.id == selectedID }) ?? workouts[0] }
        set { update(newValue) }
    }

    func update(_ workout: IntervalWorkout) {
        guard let index = workouts.firstIndex(where: { $0.id == workout.id }) else { return }
        workouts[index] = workout.clamped
        persistWorkouts()
    }

    @discardableResult
    func add(_ workout: IntervalWorkout = IntervalWorkout(name: "New")) -> IntervalWorkout {
        let clamped = workout.clamped
        workouts.append(clamped)
        selectedID = clamped.id
        persistWorkouts()
        return clamped
    }

    func delete(_ workout: IntervalWorkout) {
        guard workouts.count > 1 else { return }
        workouts.removeAll { $0.id == workout.id }
        if selectedID == workout.id { selectedID = workouts[0].id }
        persistWorkouts()
    }

    private func persistWorkouts() {
        guard let data = try? encoder.encode(workouts) else { return }
        defaults.set(data, forKey: Key.workouts)
    }

    // MARK: - In-flight run

    /// Records the current run so a relaunch can resume exactly where it left off.
    func saveActiveRun(_ snapshot: RunSnapshot?) {
        guard let snapshot else {
            defaults.removeObject(forKey: Key.activeRun)
            return
        }
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: Key.activeRun)
    }

    /// The run to resume, if one was in flight and has not already run past its end.
    func loadActiveRun(now: Date = Date()) -> RunSnapshot? {
        guard
            let data = defaults.data(forKey: Key.activeRun),
            let snapshot = try? decoder.decode(RunSnapshot.self, from: data)
        else { return nil }

        // A paused run is always resumable. A running one is stale once it has finished.
        if snapshot.pausedElapsed == nil {
            let total = TimeInterval(snapshot.workout.totalSeconds)
            guard now.timeIntervalSince(snapshot.anchor) < total else {
                defaults.removeObject(forKey: Key.activeRun)
                return nil
            }
        }
        return snapshot
    }
}
