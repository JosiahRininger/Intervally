//
//  PhoneQA.swift
//  IntervallyPhone
//

#if DEBUG
import SwiftUI
import WatchConnectivity

/// The iPhone's QA launch flags, for screenshots and for checking every state by hand.
/// Debug builds only, like the watch's: in Release `-qaPro` would be an unlock that bypasses
/// the purchase (Guidelines 2.3.1(a) and 3.1.1).
///
///     simctl launch <udid> com.josiahrininger.intervally -qaPro pro -qaWatch notInstalled -qaOpen editor
///
/// - `-qaPro pro|free` pins the entitlement for the launch.
/// - `-qaWatch unsupported|unpaired|notInstalled|installed|firstSync` stands in for the watch:
///   sync reports that state and sends nothing to a real one.
/// - `-qaWelcome YES` shows the welcome whatever was seen before.
/// - `-qaOpen <screen>` opens one screen on launch (`QAScreen`).
/// - `-qaHistory sample|empty|connect|unavailable|failed` reads History from a fixture
///   (`SampleHistory`) instead of Health, which is never read or written.
/// - `-qaTheme classic|pastel` pins the theme shown for the launch, whatever is stored or
///   bought. Nothing is saved or synced, and choosing a theme in Settings ends it.
/// - `-qaRunElapsed <seconds>` launches into a run of the preset up next that started that
///   many seconds ago, for screenshots of the run screen and its Live Activity.
/// - `-qaWatchRun running|paused|finished` shows a run of the preset up next as if the watch
///   were running it and mirroring it here (`-qaRunElapsed` sets how far in; 40 s without).
///   The simulator can't mirror a real watch's session.
/// - `-qaWorkout <bpm>,<kcal>` runs this iPhone's runs on a stand-in workout session
///   (`QAWorkoutSession`) that reports that heart rate and those calories, with no Health or
///   notification prompts, and nothing saved: the simulator measures neither.
/// - `-qaDefaults fresh|keep`: fresh starts the launch as a new install would, with what the
///   app keeps cleared before anything reads it (`QADefaults.clear`) and no system prompt on
///   the way (`suppressesPrompts`). keep, like no flag, starts from what the last launch left.
/// - `-qaAllowPrompts YES` lets a fresh launch ask for notifications and Health as a new
///   install would, for checking the prompts themselves.
/// - `-qaSkipWelcome YES` marks the welcome as seen, so a fresh launch opens on the tabs.
struct PhoneQAOptions: Equatable {
    var pro: Bool?
    var watch: QAWatchState?
    var welcome = false
    var screen: QAScreen?
    var history: QAHistory?
    var theme: AppTheme?
    var runElapsed: TimeInterval?
    var watchRun: RunMirrorState.Status?
    var workout: QAWorkoutFigures?
    var defaults: QADefaults?
    var allowPrompts = false
    var skipWelcome = false

    /// Any QA flag at all: such a launch is being driven or captured, never really used.
    var isActive: Bool {
        pro != nil || watch != nil || welcome || screen != nil || history != nil || theme != nil
            || runElapsed != nil || watchRun != nil || workout != nil || defaults != nil || allowPrompts
            || skipWelcome
    }

    /// A fresh launch shows no system alert of its own, so none can cover the screen under
    /// test: its runs ask for neither notifications nor Health, History's Connect shows no
    /// sheet, and the Home Screen icon stays as it is, since iOS announces every change in an
    /// alert. `-qaAllowPrompts` lets them all show.
    var suppressesPrompts: Bool {
        defaults == .fresh && !allowPrompts
    }

    /// Whether this iPhone's runs take the stand-in workout session and backstop
    /// (`QAWorkoutSession`, `QABackstop`), which ask for nothing and save nothing: for the
    /// figures `-qaWorkout` shows, or for a launch that must show no prompt.
    var runsOnStandIns: Bool {
        workout != nil || suppressesPrompts
    }

    static let current = parse(ProcessInfo.processInfo.arguments)

    /// Unreadable values are ignored rather than guessed at, so a typo leaves the app as it
    /// would launch anyway.
    static func parse(_ arguments: [String]) -> PhoneQAOptions {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            let next = arguments[index + 1]
            return next.hasPrefix("-") ? nil : next
        }
        func isOn(_ flag: String) -> Bool {
            guard arguments.contains(flag) else { return false }
            // A bare flag counts, but UserDefaults would read the next flag as its value.
            return value(after: flag).map { ["yes", "1", "true"].contains($0.lowercased()) } ?? true
        }
        var options = PhoneQAOptions()
        options.pro = value(after: "-qaPro").flatMap(proOverride)
        options.watch = value(after: "-qaWatch").flatMap(QAWatchState.init(rawValue:))
        options.welcome = isOn("-qaWelcome")
        options.screen = value(after: "-qaOpen").flatMap(QAScreen.init(rawValue:))
        options.history = value(after: "-qaHistory").flatMap(QAHistory.init(rawValue:))
        options.theme = value(after: "-qaTheme").flatMap(AppTheme.qaOverride)
        options.runElapsed = value(after: "-qaRunElapsed").flatMap(TimeInterval.init).map { max(0, $0) }
        options.watchRun = value(after: "-qaWatchRun").flatMap(RunMirrorState.Status.init(rawValue:))
            .flatMap { $0 == .stopped ? nil : $0 }
        options.workout = value(after: "-qaWorkout").flatMap(QAWorkoutFigures.init)
        options.defaults = value(after: "-qaDefaults").flatMap(QADefaults.init(rawValue:))
        options.allowPrompts = isOn("-qaAllowPrompts")
        options.skipWelcome = isOn("-qaSkipWelcome")
        return options
    }

    /// The entitlement a `-qaPro` value pins: "pro" or "free", nothing else.
    static func proOverride(_ spec: String) -> Bool? {
        switch spec.trimmingCharacters(in: .whitespaces).lowercased() {
        case "pro": true
        case "free": false
        default: nil
        }
    }
}

/// What a launch starts from (`-qaDefaults`). The UI tests launch fresh every time, so no test
/// inherits a preset, a theme or a run another test left behind.
enum QADefaults: String, Sendable {
    /// As a new install would: everything the app keeps is cleared first (`clear`).
    case fresh
    /// Whatever the last launch left, as with no flag at all.
    case keep

    /// Keys a fresh launch sets to what a new install reads, where clearing leaves a value
    /// showing from outside the app's own defaults. A simulator can keep defaults for the app
    /// beside its container rather than in it (`simctl spawn … defaults write` leaves them
    /// there), and removing the app's own leaves those in place: one set up for screenshots
    /// skipped the welcome on every fresh launch.
    static let newInstall: [String: Bool] = [Welcome.seenKey: false]

    /// Clears what the app keeps, before anything reads it: its own defaults, the shared
    /// suite (the same defaults on iPhone today; a suite of its own is cleared key by key),
    /// and Application Support, where the run diagnostics live. Caches stay: the voice coach
    /// would only render its phrases again, which takes time and changes nothing.
    static func clear(
        defaults: UserDefaults = .standard,
        domain: String? = Bundle.main.bundleIdentifier,
        suite: UserDefaults = SharedDefaults.suite,
        support: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    ) {
        if let domain { defaults.removePersistentDomain(forName: domain) }
        if suite !== defaults {
            // Removing a key the suite only reads from elsewhere (the global domain, the
            // launch arguments) changes nothing, so every key it shows can go.
            for key in suite.dictionaryRepresentation().keys {
                suite.removeObject(forKey: key)
            }
        }
        // Only where a value from elsewhere still shows: otherwise the key stays unset, as on
        // a new install.
        for (key, value) in newInstall where suite.object(forKey: key) != nil {
            suite.set(value, forKey: key)
        }
        let files = FileManager.default
        guard let support, let items = try? files.contentsOfDirectory(at: support, includingPropertiesForKeys: nil) else { return }
        for item in items {
            try? files.removeItem(at: item)
        }
    }
}

/// A watch to stand in for, one per Watch Status state.
enum QAWatchState: String, CaseIterable, Sendable {
    /// iPad, or anywhere without WatchConnectivity.
    case unsupported
    case unpaired
    /// Paired, without the watch app.
    case notInstalled
    /// Set up, with presets received from it four minutes ago.
    case installed
    /// Set up, but nothing received from it yet: the Workouts hint shows.
    case firstSync

    var snapshot: PeerSnapshot {
        switch self {
        case .unsupported:
            .unsupported
        case .unpaired:
            PeerSnapshot(isSupported: true, activationState: .activated, isPaired: false, isCounterpartInstalled: false, hasContentPending: false)
        case .notInstalled:
            PeerSnapshot(isSupported: true, activationState: .activated, isPaired: true, isCounterpartInstalled: false, hasContentPending: false)
        case .installed, .firstSync:
            PeerSnapshot(isSupported: true, activationState: .activated, isPaired: true, isCounterpartInstalled: true, hasContentPending: false)
        }
    }
}

/// Sync's transport for `-qaWatch`: reports the chosen state and keeps what is "sent" to
/// itself, so a QA launch never reaches a real watch.
@MainActor
final class QAWatchTransport: SyncTransport {
    let state: QAWatchState
    private let store: WorkoutStore
    private(set) var applicationContext: [String: Any] = [:]
    private(set) var receivedApplicationContext: [String: Any] = [:]

    init(state: QAWatchState, store: WorkoutStore) {
        self.state = state
        self.store = store
    }

    var snapshot: PeerSnapshot { state.snapshot }

    /// Activates at once. A set-up watch "sent" this device's own presets four minutes ago,
    /// so Last Synced has something to say and nothing needs merging.
    func activate(delegate: any WCSessionDelegate, onStateChange: @escaping @MainActor @Sendable () -> Void) {
        if state == .installed {
            receivedApplicationContext = (try? SyncWire.context(for: store.document, sentAt: Date().addingTimeInterval(-240))) ?? [:]
        }
        (delegate as? WatchSync)?.sessionDidActivate()
    }

    func updateApplicationContext(_ context: [String: Any]) throws {
        applicationContext = context
    }
}

/// What `-qaWorkout` reports: "152,37" is 152 BPM and 37 calories.
struct QAWorkoutFigures: Equatable, Sendable {
    let heartRate: Double
    let activeEnergy: Double

    init?(_ spec: String) {
        let parts = spec.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, parts.allSatisfy({ $0 >= 0 }) else { return nil }
        heartRate = parts[0]
        activeEnergy = parts[1]
    }
}

/// The workout session for `-qaWorkout`: starts at once, reports fixed figures, and saves
/// nothing, so the run screen can be checked with its heart rate and calories showing, and
/// its summary with Saved to Health. A fresh launch's runs take it too, with no figures, so
/// no Health prompt stands in the way; their summary says nothing was saved, which is true.
@MainActor
final class QAWorkoutSession: WorkoutSessioning {
    let figures: QAWorkoutFigures?
    var isSupported: Bool { true }
    private(set) var isRunning = false
    var heartRate: Double? { isRunning ? figures?.heartRate : nil }
    var activeEnergy: Double? { isRunning ? figures?.activeEnergy : nil }
    var onUnexpectedEnd: (() -> Void)?

    init(figures: QAWorkoutFigures?) {
        self.figures = figures
    }

    func requestAuthorization() async -> Bool { true }
    func adoptRecoveredSession() async -> Bool { false }
    func start(at date: Date) async -> Bool {
        isRunning = true
        return true
    }
    func beginActivity(for phase: IntervalPhase, at date: Date) {}
    func pause() {}
    func resume() {}
    /// Saved only for `-qaWorkout`'s screenshots. A fresh launch's run reports a failed save,
    /// as nothing reached Health, so a UI test can't take Saved to Health for granted.
    func end(at date: Date) async -> Bool {
        isRunning = false
        return figures != nil
    }
    func discard() { isRunning = false }
}

/// The notification backstop for `-qaWorkout` and a fresh launch: asks for nothing and
/// schedules nothing.
struct QABackstop: BoundaryScheduling {
    func requestAuthorization() async -> Bool { true }
    func schedule(plan: IntervalPlan, anchor: Date) async {}
    func cancelAll() async {}
}

/// History from Health for a fresh launch: read as usual, but Connect asks for nothing, so
/// Health's sheet never covers the screen under test.
struct QAUnpromptedHistory: HistorySource {
    let source: any HistorySource

    var isAvailable: Bool { source.isAvailable }
    func access() async -> HistoryAccess { await source.access() }
    func requestAccess() async throws {}
    func workouts() async throws -> [RawWorkout] { try await source.workouts() }
}

/// A screen `-qaOpen` opens on launch, for screenshots.
enum QAScreen: String, CaseIterable, Sendable {
    /// The selected preset's editor.
    case editor
    /// The editor, with the Work picker up.
    case picker
    /// The editor, with the warmup tapped: the paywall without Pro, its picker with it.
    case bookends
    /// The paywall from + at the free limit.
    case paywall
    case settings
    /// Settings > Apple Watch.
    case watch
    /// Settings > Intervally Pro.
    case pro
    /// Settings > Apple Health.
    case health
    /// Settings > Theme.
    case theme
    /// Settings > Sounds & Voice.
    case sounds
    /// The History tab.
    case history
    /// The History tab, with its newest session open.
    case session

    /// Where each screen starts: the tabs, the Workouts stack, the editor, Settings or History.
    enum Stage: Sendable {
        case tabs, workouts, editor, settings, history
    }

    /// Each stage opens its part once per launch, so a second editor opened by hand doesn't
    /// open the picker again.
    @MainActor private static var opened: Set<Stage> = []

    @MainActor
    static func open(_ stage: Stage) -> Bool {
        opened.insert(stage).inserted
    }
}

private struct QAScreenKey: EnvironmentKey {
    static let defaultValue: QAScreen? = nil
}

extension EnvironmentValues {
    var qaScreen: QAScreen? {
        get { self[QAScreenKey.self] }
        set { self[QAScreenKey.self] = newValue }
    }
}

/// `-qaOpen` on the Workouts screen: pushes the editor or presents a sheet, once.
struct WorkoutsQAOpen: ViewModifier {
    @Binding var path: [WorkoutsRoute]
    @Binding var sheet: WorkoutsView.Sheet?
    @Environment(\.qaScreen) private var screen
    @Environment(WorkoutStore.self) private var store

    func body(content: Content) -> some View {
        content.onAppear {
            guard let screen, QAScreen.open(.workouts) else { return }
            switch screen {
            case .editor, .picker, .bookends: path = [.editor(store.selected.id, isNew: false)]
            case .paywall: sheet = .paywall
            case .settings, .watch, .pro, .health, .theme, .sounds: sheet = .settings
            case .history, .session: break
            }
        }
    }
}

/// `-qaOpen picker|bookends` in the editor: presents its sheet, once.
struct EditorQAOpen: ViewModifier {
    @Binding var sheet: PresetEditorView.Sheet?
    @Environment(\.qaScreen) private var screen
    @Environment(ProStore.self) private var pro

    func body(content: Content) -> some View {
        content.onAppear {
            guard screen == .picker || screen == .bookends, QAScreen.open(.editor) else { return }
            if screen == .picker {
                sheet = .picker(.work)
            } else {
                sheet = pro.isPro ? .picker(.warmup) : .paywall(.bookends)
            }
        }
    }
}

/// `-qaOpen watch|pro|health` in Settings: pushes the screen, once.
struct SettingsQAOpen: ViewModifier {
    @Binding var path: [SettingsRoute]
    @Environment(\.qaScreen) private var screen

    func body(content: Content) -> some View {
        content.onAppear {
            let route: SettingsRoute? = switch screen {
            case .watch: .watch
            case .pro: .pro
            case .health: .health
            case .theme: .theme
            case .sounds: .sounds
            default: nil
            }
            guard let route, QAScreen.open(.settings) else { return }
            path = [route]
        }
    }
}

/// `-qaOpen history|session`: selects the History tab, once.
struct TabsQAOpen: ViewModifier {
    @Binding var tab: PhoneTab
    @Environment(\.qaScreen) private var screen

    func body(content: Content) -> some View {
        content.onAppear {
            guard screen == .history || screen == .session, QAScreen.open(.tabs) else { return }
            tab = .history
        }
    }
}

/// `-qaOpen session` in History: opens the newest session once the sessions are in, once.
struct HistoryQAOpen: ViewModifier {
    @Binding var path: [SessionSummary]
    @Environment(\.qaScreen) private var screen
    @Environment(HistoryModel.self) private var history

    func body(content: Content) -> some View {
        content.onChange(of: history.sessions.first) { _, newest in
            guard screen == .session, let newest, QAScreen.open(.history) else { return }
            path = [newest]
        }
    }
}

/// A History to stand in for Health's, one per History state.
enum QAHistory: String, CaseIterable, Sendable {
    /// Three weeks of sessions: an early end, a long warmup, one without heart rate.
    case sample
    /// Connected, with nothing saved yet.
    case empty
    /// Never asked: Connect Apple Health, which then "allows" the sample.
    case connect
    /// A device without Health.
    case unavailable
    /// Every read fails, as on a locked iPhone.
    case failed
}
#endif
