//
//  Fakes.swift
//  IntervallyTests
//

import Foundation
@testable import Intervally

/// Holds an async call open until the test releases it, so a test can act while a start
/// or a permission prompt is still in flight.
@MainActor
final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

/// Stands in for `HKWorkoutSession`, which cannot run in a test.
@MainActor
final class FakeWorkoutSession: WorkoutSessioning {
    var isSupported = true
    var isRunning = false
    var heartRate: Double?
    var onUnexpectedEnd: (() -> Void)?

    /// What `start()` should report.
    var startResult = true
    /// How many upcoming `start()` calls fail before `startResult` applies — the shape of
    /// Health access that was granted a moment ago and is not in effect yet.
    var failingStarts = 0
    /// What `end` reports — whether the Health save succeeded.
    var endResult = true
    /// When set, `end` waits on it, so a test can observe the summary mid-save.
    var endGate: Gate?
    /// Whether the system is holding a session from before a termination. Adopting it
    /// consumes it, as the real recovery does.
    var recoverableSession = false
    /// When set, `start()` suspends until the gate opens.
    var startGate: Gate?
    /// When set, `requestAuthorization()` suspends until the gate opens — i.e. the
    /// permission sheet is still on screen.
    var authorizationGate: Gate?

    /// Set by the coordinator: the iPhone's buttons, as the mirrored session delivers them.
    var onRemoteCommand: ((RunMirrorCommand) -> Void)?
    /// Every state sent to the iPhone's mirror, in order.
    private(set) var mirrored: [RunMirrorState] = []
    func mirror(_ state: RunMirrorState) { mirrored.append(state) }

    private(set) var startCount = 0
    private(set) var recoveryAttempts = 0
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var endCount = 0
    private(set) var discardCount = 0
    private(set) var authorizationRequests = 0

    @discardableResult
    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        await authorizationGate?.wait()
        return isSupported
    }

    func adoptRecoveredSession() async -> Bool {
        recoveryAttempts += 1
        guard recoverableSession else { return false }
        recoverableSession = false
        isRunning = true
        return true
    }

    func start(at date: Date) async -> Bool {
        startCount += 1
        await startGate?.wait()
        if failingStarts > 0 {
            failingStarts -= 1
            isRunning = false
            return false
        }
        isRunning = startResult
        return startResult
    }

    private(set) var activities: [(kind: IntervalPhase.Kind, round: Int)] = []
    func beginActivity(for phase: IntervalPhase, at date: Date) {
        activities.append((phase.kind, phase.round))
    }

    func pause() { pauseCount += 1 }
    func resume() { resumeCount += 1 }

    @discardableResult
    func end(at date: Date) async -> Bool {
        endCount += 1
        isRunning = false
        await endGate?.wait()
        return endResult
    }

    func discard() {
        discardCount += 1
        isRunning = false
    }

    /// Simulates the system ending the session out from under the app.
    func simulateUnexpectedEnd() {
        isRunning = false
        onUnexpectedEnd?()
    }
}

/// Stands in for `WKExtendedRuntimeSession`.
@MainActor
final class FakeRuntimeSession: RuntimeSessioning {
    var onInvalidate: (() -> Void)?

    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }

    /// Simulates the system invalidating the session, e.g. on a crown press.
    func simulateInvalidation() { onInvalidate?() }
}

/// Records the ordered notification-scheduling calls the coordinator makes.
final class SpyScheduler: BoundaryScheduling, @unchecked Sendable {
    enum Call: Equatable {
        case schedule(anchor: Date)
        case cancelAll
    }

    private let lock = NSLock()
    nonisolated(unsafe) private var _calls: [Call] = []

    private func append(_ call: Call) {
        lock.withLock { _calls.append(call) }
    }

    var calls: [Call] {
        lock.withLock { _calls }
    }

    var scheduleCount: Int { calls.filter { if case .schedule = $0 { true } else { false } }.count }

    /// What the notification permission prompt resolves to.
    nonisolated(unsafe) var authorizationResult = true

    func requestAuthorization() async -> Bool { authorizationResult }

    func schedule(plan: IntervalPlan, anchor: Date) async {
        append(.schedule(anchor: anchor))
    }

    func cancelAll() async {
        append(.cancelAll)
    }
}

/// Stands in for `ProStore`, so gated code can be tested without a StoreKit session.
@MainActor
final class FakePro: ProGating {
    var isPro: Bool

    init(isPro: Bool = false) {
        self.isPro = isPro
    }
}

/// Records what the coordinator asks of the boundary haptics, in order, so a test can tell
/// a cancel that came before the finish from one after it.
@MainActor
final class SpyHaptics: BoundaryHaptics {
    enum Call: Equatable {
        case play(TimerEvent, BoundaryContext)
        case preview(TapStrength)
        case cancel
    }

    private(set) var calls: [Call] = []

    var played: [(event: TimerEvent, context: BoundaryContext)] {
        calls.compactMap { call in
            guard case .play(let event, let context) = call else { return nil }
            return (event, context)
        }
    }

    var cancelCount: Int { calls.filter { $0 == .cancel }.count }

    func play(_ event: TimerEvent, context: BoundaryContext) {
        calls.append(.play(event, context))
    }

    func preview(_ strength: TapStrength) {
        calls.append(.preview(strength))
    }

    func cancelPending() {
        calls.append(.cancel)
    }
}

/// Anchors `Bundle(for:)` to the test bundle, which is the only bundle that carries
/// `Intervally.storekit`.
final class BundleToken {}

/// A tally that the `@MainActor` closures a test hands to the code under test can bump.
@MainActor
final class Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

/// Polls `condition` every 20 ms until it holds or `timeout` passes. For work that lands on
/// its own schedule — a StoreKit update, a background read — rather than one a test drives.
@MainActor
@discardableResult
func waitUntil(within timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}

/// A defaults suite scoped to one test.
func makeTestDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
func makeCoordinator(
    workout: FakeWorkoutSession = FakeWorkoutSession(),
    runtime: FakeRuntimeSession = FakeRuntimeSession(),
    scheduler: SpyScheduler = SpyScheduler(),
    defaults: UserDefaults? = nil,
    pro: FakePro = FakePro(),
    haptics: SpyHaptics = SpyHaptics()
) -> (RunCoordinator, WorkoutStore, FakeWorkoutSession, FakeRuntimeSession, SpyScheduler, FakePro, SpyHaptics) {
    let store = WorkoutStore(defaults: defaults ?? makeTestDefaults())
    let coordinator = RunCoordinator(
        store: store,
        pro: pro,
        haptics: haptics,
        workout: workout,
        runtime: runtime,
        notifications: scheduler,
        playCue: { _ in },
        reloadWidgets: {}
    )
    return (coordinator, store, workout, runtime, scheduler, pro, haptics)
}
