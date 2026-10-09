//
//  RootView.swift
//  Intervally
//

import SwiftUI
import WidgetKit

/// A screen pushed on the root stack, which is never more than one deep: a setup tile's
/// editor, the paywall, or the run.
enum RootRoute: Hashable, Sendable {
    case field(SetupField)
    case paywall(PaywallContext)
    case run
}

/// A sheet over the setup screen.
enum SetupSheet: Hashable, Identifiable, Sendable {
    case presets, settings
    var id: Self { self }
}

/// Everything the root shows over the setup screen, as data, so that starting a run can
/// clear it in one step.
///
/// A start can arrive from outside the app — the complication, Siri, Control Center — while
/// a sheet or a pushed screen, the paywall included, is still up from before. Left there,
/// the workout began out of sight beneath it, and Done popped back onto it. A run now always
/// opens from the setup screen and closes back to it.
struct RootNavigation: Equatable, Sendable {
    var path: [RootRoute] = []
    var sheet: SetupSheet?

    /// Read from the stack, so the system's own back gesture counts as leaving the run.
    var isRunning: Bool { path.contains(.run) }

    mutating func setRunning(_ running: Bool) {
        if running {
            sheet = nil
            path = [.run]
        } else {
            path.removeAll { $0 == .run }
        }
    }

    /// The preset on the setup screen changed underneath: the iPhone put another one on the
    /// watch, or deleted this one. A field's editor edits whatever is selected, under a title
    /// that names only the field, so it closes rather than go on editing another preset
    /// unannounced. The paywall and the run stay.
    mutating func selectedPresetChanged() {
        path.removeAll { route in
            if case .field = route { return true }
            return false
        }
    }
}

struct RootView: View {
    @Environment(RunCoordinator.self) private var coordinator
    @Environment(WorkoutStore.self) private var store
    @Environment(ProStore.self) private var pro
    @Environment(ThemeStore.self) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = RootNavigation()
    /// The preset the complication's idle face was last built from.
    @State private var publishedPreset: IntervalWorkout?

    /// Whether the run screen is showing. Every write goes through `setRunning`, so a start
    /// from anywhere clears what was open.
    private var isRunning: Binding<Bool> {
        Binding { navigation.isRunning } set: { navigation.setRunning($0) }
    }

    var body: some View {
        let shown = theme.effective(isPro: pro.isPro)

        // A path rather than value-free links, so a start can pop whatever is pushed.
        NavigationStack(path: $navigation.path) {
            SetupView(isRunning: isRunning, sheet: $navigation.sheet)
                .navigationDestination(for: RootRoute.self) { route in
                    switch route {
                    case .field(let field): SetupFieldEditor(field: field)
                    case .paywall(let context): PaywallView(context: context)
                    case .run: RunView(isRunning: isRunning)
                    }
                }
        }
        // Read by every screen, sheets and pushed screens included, so a new theme, from
        // Settings, the iPhone or Pro lapsing, redraws them all in place.
        .palette(.of(shown))
        .onChange(of: shown) {
            // The complication wears the theme too.
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onAppear {
            // Pick up a run that was still going when the app was last terminated — or one
            // the delegate already restored during a background workout recovery, before
            // this view existed.
            if coordinator.restoreIfNeeded() || coordinator.engine.isActive { navigation.setRunning(true) }
            consumePendingStart()
        }
        .onOpenURL { url in
            guard url.scheme == "intervally" else { return }
            switch url.host() {
            case "run":
                // Tapping the running complication deep-links straight into the workout
                // rather than dropping the user on the setup screen mid-set.
                if coordinator.engine.isActive || coordinator.restoreIfNeeded() { navigation.setRunning(true) }
            case "start":
                // The idle complication offers the selected preset; a tap is a start request,
                // routed through the same door as Siri and Control Center.
                PendingStart.request(workoutID: nil)
                consumePendingStart()
            default:
                break
            }
        }
        .onChange(of: store.selectedID) {
            navigation.selectedPresetChanged()
        }
        .onChange(of: navigation.isRunning) { _, running in
            guard running else { return }
            // The run's anchor rather than the clock: a run restored after a relaunch
            // reports the start it already had, which `recordStart` recognises and drops.
            WorkoutStore.recordStart(WorkoutStore.activeRun()?.anchor ?? Date())
        }
        // The intent's perform() can land after the scene is already active, so the
        // foreground check below would miss it; this catches that ordering.
        .onReceive(NotificationCenter.default.publisher(for: PendingStart.didRequest)) { _ in
            consumePendingStart()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                publishIdleFace()
                return
            }
            coordinator.handleForeground()
            Task { await pro.handleForeground() }
            // A Siri phrase or Control Center button launches the app rather than running
            // in-process, so the request is picked up here.
            consumePendingStart()
        }
    }

    /// Hands the complication the preset it offers to start. Done as the app leaves the
    /// foreground, not on every crown tick while a value is being edited: each reload
    /// spends widget budget.
    private func publishIdleFace() {
        guard store.selected != publishedPreset else { return }
        publishedPreset = store.selected
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Honours a start requested by Siri, a Shortcut, or a Control Center button.
    private func consumePendingStart() {
        // Consume unconditionally: leaving the request in place while a run is already
        // going means it fires spuriously the next time the app comes forward.
        guard let requested = PendingStart.consume(), !navigation.isRunning else { return }
        if let id = requested, store.workouts.contains(where: { $0.id == id }) {
            store.selectedID = id
        }
        navigation.setRunning(true)
    }
}
