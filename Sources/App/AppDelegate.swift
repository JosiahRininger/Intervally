//
//  AppDelegate.swift
//  Intervally
//

import WatchKit
import WidgetKit
import os

/// Owns the app's long-lived services.
///
/// They live here rather than in the SwiftUI `App` because the delegate is the one object
/// guaranteed to exist when the system relaunches the app in the background to hand back a
/// workout session — at which point no view has appeared, so a coordinator built lazily by
/// a view would not exist yet, and the recovered session would be left running with nobody
/// to claim it.
@MainActor
final class AppDelegate: NSObject, WKApplicationDelegate {

    let store = WorkoutStore()
    /// Intervally Pro. Created with the delegate, so a background workout recovery has the
    /// cached answer before its first boundary taps.
    let pro = ProStore()
    /// The theme, chosen here or on the iPhone. In the App Group, so the complication wears it.
    let theme = ThemeStore()
    private(set) lazy var coordinator = RunCoordinator(
        store: store,
        pro: pro,
        // Read at every boundary, so a new choice in Settings, or Pro lapsing mid-run, takes
        // effect at the next interval change without rebuilding anything.
        haptics: HapticPlayer(strength: { [pro] in
            TapStrength.effective(stored: .stored(in: SharedDefaults.suite), isPro: pro.isPro)
        })
    )
    /// Keeps the presets in step with the iPhone. Started with the delegate, so a background
    /// wake that brought a context finds someone to merge it.
    private(set) lazy var sync = WatchSync(store: store, theme: theme)
    /// WatchConnectivity wakes, held until sync has merged what they brought.
    private lazy var connectivityWakes = ConnectivityWakes(activity: { [weak self] in self?.sync.activity ?? .inactive })

    #if DEBUG
    /// The live delegate, for the opt-in manual StoreKit QA test (`ManualQAStoreKit`),
    /// which has to start the store the unit-test host skipped.
    static weak var current: AppDelegate?
    #endif

    override init() {
        super.init()
        #if DEBUG
        Self.current = self
        applyQAPreset()
        applyQAPro()
        applyQATheme()
        #endif
        // Also runs on a background workout-recovery relaunch, which is when a transaction
        // that finished while the app was away (an Ask to Buy approval, a refund) arrives.
        if !Self.isUnitTestHost() {
            pro.start()
            startSync()
        }
    }

    private func startSync() {
        sync.onRemoteApplied = { [log] result in
            // Only the selected preset is on the face; anything else would spend widget budget.
            guard Self.reloadsComplication(after: result) else { return }
            WidgetCenter.shared.reloadAllTimelines()
            log.info("complication reloaded: the iPhone changed the selected preset")
        }
        sync.onStateChange = { [weak self] in self?.connectivityWakes.reevaluate() }
        // The complication wears the theme. A choice made here reloads it from RootView; one
        // from the iPhone can land while no view exists, in a background wake.
        theme.onRemoteChange = { [log] in
            WidgetCenter.shared.reloadAllTimelines()
            log.info("complication reloaded: the iPhone changed the theme")
        }
        sync.activate()
    }

    /// Whether a merge from the iPhone changed what the complication's idle face offers.
    nonisolated static func reloadsComplication(after result: WorkoutStore.MergeResult) -> Bool {
        result.selectedPresetChanged
    }

    /// True inside the unit-test host, where the real store must not run. The rule lives in
    /// `UnitTestHost`, shared with the iPhone app; this forwarder keeps the watch's call
    /// sites and tests as they were. Always false in Release.
    nonisolated static func isUnitTestHost(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        UnitTestHost.isActive(in: environment)
    }

    private let log = Logger(subsystem: "com.josiahrininger.intervally", category: "app")

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let snapshot as WKSnapshotRefreshBackgroundTask:
                snapshot.setTaskCompleted(
                    restoredDefaultState: true,
                    estimatedSnapshotExpiration: .distantFuture,
                    userInfo: nil
                )
            case let connectivity as WKWatchConnectivityRefreshBackgroundTask:
                connectivityWakes.hold(connectivity)
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    #if DEBUG
    /// QA hook for layout edge cases:
    /// `simctl launch <udid> <bundle> -qaPreset work,rest,rounds[,prepare[,warmup,cooldown]]`
    /// — e.g. `-qaPreset 120,5,20,10,300,300` — rewrites the selected preset, in seconds,
    /// instead of thirty taps on a crown. Debug builds only.
    private func applyQAPreset() {
        guard let spec = UserDefaults.standard.string(forKey: "qaPreset"),
              let workout = Self.applying(qaPreset: spec, to: store.selected) else { return }
        store.update(workout)
        log.info("QA preset applied: \(spec, privacy: .public)")
    }

    /// `workout` with a `-qaPreset` spec applied, clamped. Nil unless the spec is three or
    /// more comma-separated integers: one stray character would otherwise shift every later
    /// field into the wrong slot.
    nonisolated static func applying(qaPreset spec: String, to workout: IntervalWorkout) -> IntervalWorkout? {
        let parsed = spec.split(separator: ",", omittingEmptySubsequences: false)
            .map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parsed.count >= 3, !parsed.contains(nil) else { return nil }
        let numbers = parsed.compactMap { $0 }
        var copy = workout
        copy.workSeconds = numbers[0]
        copy.restSeconds = numbers[1]
        copy.rounds = numbers[2]
        if numbers.count >= 4 { copy.prepareSeconds = numbers[3] }
        if numbers.count >= 5 { copy.warmupSeconds = numbers[4] }
        if numbers.count >= 6 { copy.cooldownSeconds = numbers[5] }
        return copy.clamped
    }

    /// QA hook for the paywall and the Pro features: `-qaPro pro` or `-qaPro free` pins the
    /// entitlement for this launch, whatever StoreKit says. Debug builds only — in Release
    /// it would be a hidden unlock (Guidelines 2.3.1(a) and 3.1.1).
    private func applyQAPro() {
        guard let spec = UserDefaults.standard.string(forKey: "qaPro"),
              let isPro = Self.qaProOverride(spec) else { return }
        pro.overrideForQA(isPro)
        log.info("QA Pro override applied: \(spec, privacy: .public)")
    }

    /// QA hook for screenshots: `-qaTheme classic` or `-qaTheme pastel` pins the theme shown
    /// for this launch, whatever is stored or bought. Nothing is saved or synced. Debug
    /// builds only, like `-qaPro`.
    private func applyQATheme() {
        guard let spec = UserDefaults.standard.string(forKey: "qaTheme"),
              let pinned = AppTheme.qaOverride(spec) else { return }
        theme.pinForQA(pinned)
        log.info("QA theme pinned: \(spec, privacy: .public)")
    }

    /// The entitlement a `-qaPro` value pins, or nil for anything but "pro" or "free", so a
    /// typo leaves StoreKit in charge rather than silently picking a side.
    nonisolated static func qaProOverride(_ spec: String) -> Bool? {
        switch spec.trimmingCharacters(in: .whitespaces).lowercased() {
        case "pro": true
        case "free": false
        default: nil
        }
    }
    #endif

    /// The system kept a workout session alive across the app's termination and is offering
    /// it back. Claim it: resume the run if it can be resumed, or save and end it if not.
    func handleActiveWorkoutRecovery() {
        log.info("system offered an active workout for recovery")
        coordinator.recoverWorkoutSession()
    }
}
