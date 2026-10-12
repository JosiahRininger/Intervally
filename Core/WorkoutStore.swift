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
///
/// The presets and the selection live in a `SyncDocument`, which the iPhone and the watch
/// replicate: local edits stamp it, and `merge(_:)` folds in the other device's.
@MainActor
@Observable
final class WorkoutStore {

    /// Shared with the widget extension, which reads the active run to render a live
    /// countdown on the watch face.
    enum Key {
        /// Derived from `document` and rewritten with it, so the widget, the complication and
        /// the run code read exactly what they always have.
        static let workouts = "workouts.v2"
        static let selected = "selectedWorkoutID.v2"
        static let activeRun = "activeRun.v2"
        static let startTimes = "startTimes.v1"
        /// The presets' source of truth.
        static let document = "sync.document.v1"
        /// This install's `SyncClock`.
        static let clock = "sync.clock.v1"
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

    /// What sync sends. Local edits stamp it; `merge(_:)` folds in the other device's.
    @ObservationIgnored private(set) var document: SyncDocument
    @ObservationIgnored private var clock: SyncClock

    /// True when a stored preset list exists but won't decode. The store then never writes
    /// the document, and neither applies nor offers remote changes, so a decoding problem
    /// can't turn into permanent loss on either device. Only a launch that reads it clears it.
    let isSyncSuspended: Bool

    /// Called once after every local edit, so sync can offer it to the other device. A merge
    /// never calls it: `MergeResult` already says whether the sender needs a reply.
    @ObservationIgnored var onLocalChange: (@MainActor () -> Void)?

    /// The live presets in list order, derived from `document`.
    private(set) var workouts: [IntervalWorkout]
    /// Derived too: the document's selection while it names a live preset, else the first.
    private var selection: UUID

    /// Setting it is a local edit; an id that names no live preset is ignored.
    var selectedID: UUID {
        get { selection }
        set { select(newValue) }
    }

    init(defaults: UserDefaults = SharedDefaults.suite) {
        self.defaults = defaults

        var clock = defaults.data(forKey: Key.clock).flatMap { try? JSONDecoder().decode(SyncClock.self, from: $0) }
            ?? SyncClock(device: UUID().uuidString)
        let loaded = Self.load(from: defaults, clock: &clock)
        // Stamps must beat everything already stored, even if the clock itself was lost.
        clock.observe(loaded.document)

        self.clock = clock
        self.document = loaded.document
        self.isSyncSuspended = loaded.isSuspended
        let derived = Self.derive(from: loaded.document)
        self.workouts = derived.workouts
        self.selection = derived.selection

        if loaded.needsSave { persist() }
    }

    /// What the store starts from, and whether that must be written back now.
    private struct Loaded {
        var document: SyncDocument
        var isSuspended = false
        var needsSave = false
    }

    /// The stored document; else a preset list saved before sync existed, imported once; else
    /// the starters. A blob that exists but won't decode is left exactly as it is: overwriting
    /// it would turn a decoding problem into permanent loss of everything the user built.
    nonisolated private static func load(from defaults: UserDefaults, clock: inout SyncClock) -> Loaded {
        let legacyBlob = defaults.data(forKey: Key.workouts)
        let legacy = legacyBlob.map(decodePresets) ?? []
        let legacySelection = defaults.string(forKey: Key.selected).flatMap(UUID.init(uuidString:))

        if let blob = defaults.data(forKey: Key.document) {
            if var document = try? JSONDecoder().decode(SyncDocument.self, from: blob) {
                clock.observe(document)
                let repaired = document.repairIfEmpty(clock: &clock)
                // Also rewrites the derived copies if they went missing, so the complication
                // never loses its preset over them.
                if !document.workouts.isEmpty {
                    return Loaded(document: document, needsSave: repaired || legacyBlob == nil)
                }
            }
            // Fall back to the derived copies, which the last good launch wrote beside it and
            // which keep taking this install's edits while sync is off.
            guard !legacy.isEmpty else { return Loaded(document: .fresh, isSuspended: true) }
            return Loaded(document: .imported(legacy, selectedID: legacySelection, clock: &clock), isSuspended: true)
        }
        guard legacyBlob != nil else { return Loaded(document: .fresh, needsSave: true) }
        guard !legacy.isEmpty else { return Loaded(document: .fresh, isSuspended: true) }
        return Loaded(document: .imported(legacy, selectedID: legacySelection, clock: &clock), needsSave: true)
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

    /// The list and the selection everything else reads. A selection naming a preset that is
    /// gone falls back to the first without stamping anything, so two devices never trade
    /// fallbacks back and forth.
    nonisolated private static func derive(from document: SyncDocument) -> (workouts: [IntervalWorkout], selection: UUID) {
        let workouts = document.workouts
        let chosen = workouts.first { $0.id == document.selected.value } ?? workouts[0]
        return (workouts, chosen.id)
    }

    // MARK: - Presets

    /// Fixed ids, so two fresh installs agree on them (`SyncDocument.starterIDs`).
    nonisolated static let starterWorkouts = SyncDocument.starterWorkouts

    var selected: IntervalWorkout {
        get { workouts.first(where: { $0.id == selectedID }) ?? workouts[0] }
        set { update(newValue) }
    }

    /// Saves an edit to a live preset. An edit that changes nothing stamps nothing: the crown
    /// re-sends the same value, and each stamp is something to sync.
    func update(_ workout: IntervalWorkout) {
        let clamped = workout.clamped
        guard let current = workouts.first(where: { $0.id == workout.id }), current != clamped else { return }
        document.upsert(clamped, clock: &clock)
        commitLocalChange()
    }

    /// Renames a preset as it stands now, not as a sheet captured it when it opened: anything
    /// the other device changed in the meantime has been merged since, and saving the old
    /// copy would put it back, under a newer stamp, on both devices.
    func rename(_ id: UUID, to name: String) {
        guard var workout = workouts.first(where: { $0.id == id }) else { return }
        workout.name = name
        update(workout)
    }

    /// Sets what Health records a preset as, on the preset as it stands now, as `rename` does.
    func setActivity(_ id: UUID, to activity: WorkoutActivity) {
        guard var workout = workouts.first(where: { $0.id == id }) else { return }
        workout.activity = activity
        update(workout)
    }

    /// Renames a phase of a preset or changes its figure, on the preset as it stands now; the
    /// phase's own name and figure, or nil, put it back.
    func setLabel(_ id: UUID, kind: IntervalPhase.Kind, to label: PhaseLabel?) {
        guard var workout = workouts.first(where: { $0.id == id }) else { return }
        workout.setLabel(label, for: kind)
        update(workout)
    }

    /// Adds a preset at the end of the list. On the watch it is also selected, as the setup
    /// screen shows the selected preset; the iPhone passes `select: false`, where only Put on
    /// Watch changes what the watch starts next.
    @discardableResult
    func add(_ workout: IntervalWorkout = IntervalWorkout(name: "New"), select: Bool = true) -> IntervalWorkout {
        let clamped = workout.clamped
        document.upsert(clamped, clock: &clock)
        if select { document.select(clamped.id, clock: &clock) }
        commitLocalChange()
        return clamped
    }

    /// Refused for the last preset. Deleting the selected one selects the first, as an edit of
    /// its own, so the deleted preset can't take the selection back if it is ever restored.
    func delete(_ workout: IntervalWorkout) {
        let wasSelected = workout.id == selection
        guard document.delete(workout.id, clock: &clock) else { return }
        if wasSelected { document.select(document.workouts.first?.id, clock: &clock) }
        commitLocalChange()
    }

    /// Reorders the list, with offsets as SwiftUI's `onMove` gives them.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard document.move(fromOffsets: source, toOffset: destination, clock: &clock) else { return }
        commitLocalChange()
    }

    /// Compared with the register rather than the derived selection: choosing the preset a
    /// fallback put on screen records it, so a restored preset can't take the selection back.
    private func select(_ id: UUID) {
        guard id != document.selected.value, workouts.contains(where: { $0.id == id }) else { return }
        document.select(id, clock: &clock)
        commitLocalChange()
    }

    private func commitLocalChange() {
        rederive()
        persist()
        onLocalChange?()
    }

    /// Assigns only what changed: a merge that touches nothing visible, a tombstone say,
    /// must not redraw every view that reads the list.
    private func rederive() {
        let derived = Self.derive(from: document)
        if workouts != derived.workouts { workouts = derived.workouts }
        if selection != derived.selection { selection = derived.selection }
    }

    /// Writes the document, unless sync is suspended over an unreadable one, and the derived
    /// copies the rest of the app reads.
    private func persist() {
        if !isSyncSuspended, let data = try? encoder.encode(document) {
            defaults.set(data, forKey: Key.document)
        }
        if let data = try? encoder.encode(clock) {
            defaults.set(data, forKey: Key.clock)
        }
        if let data = try? encoder.encode(workouts) {
            defaults.set(data, forKey: Key.workouts)
        }
        defaults.set(selection.uuidString, forKey: Key.selected)
    }

    // MARK: - Sync

    /// What a merge did, for whoever delivered the remote document.
    struct MergeResult: Equatable, Sendable {
        /// The local document took something from the remote one, if perhaps only a record
        /// nothing shows, such as the tombstone of a preset this device never had.
        var changed: Bool
        /// The preset setup and the complication show is another one, or reads differently.
        var selectedPresetChanged: Bool
        /// The merge holds something the sender's document doesn't, so the sender needs a
        /// reply. False once both hold the same, which is what stops the two replying forever.
        var mergedDiffersFromRemote: Bool

        static let unchanged = MergeResult(changed: false, selectedPresetChanged: false, mergedDiffersFromRemote: false)
    }

    /// Folds in the other device's document. Stamps nothing of its own, apart from the repair
    /// when the merge would leave no preset, and never calls `onLocalChange`. A suspended
    /// store applies nothing.
    @discardableResult
    func merge(_ remote: SyncDocument) -> MergeResult {
        guard !isSyncSuspended else { return .unchanged }
        let before = selected
        let merged = document.receiving(remote, clock: &clock)
        let changed = merged != document
        if changed {
            document = merged
            rederive()
            persist()
        }
        return MergeResult(changed: changed, selectedPresetChanged: selected != before, mergedDiffersFromRemote: merged != remote)
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
