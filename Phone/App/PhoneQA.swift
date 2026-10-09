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
struct PhoneQAOptions: Equatable {
    var pro: Bool?
    var watch: QAWatchState?
    var welcome = false
    var screen: QAScreen?
    var history: QAHistory?
    var theme: AppTheme?

    /// Any QA flag at all: such a launch is being driven or captured, never really used.
    var isActive: Bool {
        pro != nil || watch != nil || welcome || screen != nil || history != nil || theme != nil
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
        var options = PhoneQAOptions()
        options.pro = value(after: "-qaPro").flatMap(proOverride)
        options.watch = value(after: "-qaWatch").flatMap(QAWatchState.init(rawValue:))
        if arguments.contains("-qaWelcome") {
            // A bare flag counts, but UserDefaults would read the next flag as its value.
            options.welcome = value(after: "-qaWelcome").map { ["yes", "1", "true"].contains($0.lowercased()) } ?? true
        }
        options.screen = value(after: "-qaOpen").flatMap(QAScreen.init(rawValue:))
        options.history = value(after: "-qaHistory").flatMap(QAHistory.init(rawValue:))
        options.theme = value(after: "-qaTheme").flatMap(AppTheme.qaOverride)
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
            case .settings, .watch, .pro, .health, .theme: sheet = .settings
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
