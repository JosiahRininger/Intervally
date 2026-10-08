//
//  WorkoutSessionController.swift
//  Intervally
//

import Foundation
import HealthKit
import Observation
import os

/// Runs the interval workout as a real `HKWorkoutSession`.
///
/// This is the strongest background guarantee watchOS offers an app like this. Unlike an
/// extended runtime session, a live workout session keeps the app executing indefinitely,
/// survives the user leaving the app, and gets Always-On Display treatment — the behaviour
/// people expect from a gym timer. It also means the session lands in Health and counts
/// toward the activity rings, which an interval timer arguably should.
///
/// Health access is optional. If the user declines, `start()` reports failure and the
/// coordinator falls back to an extended runtime session plus notifications.
@MainActor
@Observable
final class WorkoutSessionController: NSObject {

    private(set) var isRunning = false
    private(set) var heartRate: Double?

    /// Called when the session ends for any reason the app did not ask for. Without this
    /// the coordinator keeps believing it is in the `.workout` tier and goes on suppressing
    /// the notification backstop, so the run loses every remaining alert.
    @ObservationIgnored var onUnexpectedEnd: (() -> Void)?

    /// Set while the app is deliberately tearing the session down, so an expected `.ended`
    /// transition is not mistaken for a failure.
    @ObservationIgnored private var isEnding = false
    /// The in-flight Health save, so a restart waits for it instead of racing it.
    @ObservationIgnored private var teardownTask: Task<Void, Never>?

    // HKHealthStore is safe to call from any queue; marked so it can be used from the
    // recovery timeout race below without a strict-concurrency complaint.
    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private let log = Logger(subsystem: "com.josiahrininger.intervally", category: "workout")

    static var isSupported: Bool { HKHealthStore.isHealthDataAvailable() }

    private var typesToShare: Set<HKSampleType> { [HKQuantityType.workoutType()] }
    /// Only what the app uses. Heart rate is shown during a run; active energy feeds the
    /// workout's totals. The activity summary (ring data) was requested but never read —
    /// and HealthKit review holds apps to asking for exactly what they need.
    private var typesToRead: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
        ]
    }

    /// Asks for Health permission. Returns false if Health is unavailable or the request
    /// fails; a user who denies still returns true here, since HealthKit deliberately does
    /// not disclose denials.
    func requestAuthorization() async -> Bool {
        guard Self.isSupported else { return false }
        // When access is still undetermined the system shows its multi-page sheet and the
        // user may take as long as they like — bounding that would start the clock behind
        // the sheet. Once it IS determined the call should return at once, so a long wait
        // means healthd is unresponsive, and the Start button must not look dead for minutes.
        let alreadyDecided = await authorizationIsDecided()
        let timeout: Double? = alreadyDecided ? 5 : nil
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = Once()
            Task { @MainActor in
                do {
                    try await self.store.requestAuthorization(toShare: self.typesToShare, read: self.typesToRead)
                    if once.claim() { continuation.resume(returning: true) }
                } catch {
                    self.log.error("health authorization failed: \(error.localizedDescription, privacy: .public)")
                    if once.claim() { continuation.resume(returning: false) }
                }
            }
            if let timeout {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(timeout))
                    if once.claim() {
                        self.log.notice("health authorization did not answer in \(timeout)s; proceeding")
                        continuation.resume(returning: true)
                    }
                }
            }
        }
    }


    /// Re-attaches to a session the system kept alive across a termination.
    ///
    /// Must be tried before `start()`. `handleActiveWorkoutRecovery()` is the system telling
    /// the app it still holds a session from before the app died; starting a fresh one
    /// instead leaves that session never ended and never finished, so everything recorded
    /// before the termination is lost and the workout never lands in Health.
    func adoptRecoveredSession() async -> Bool {
        guard Self.isSupported, session == nil else { return isRunning }
        // Errors and a stuck call both come back as nil: there is nothing to adopt.
        guard let recovered = await recoverWithTimeout(seconds: 3) else { return false }
        let builder = recovered.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: store, workoutConfiguration: recovered.workoutConfiguration
        )
        recovered.delegate = self
        builder.delegate = self
        self.session = recovered
        self.builder = builder

        if recovered.state == .notStarted || recovered.state == .prepared {
            recovered.startActivity(with: Date())
        }
        isRunning = (recovered.state == .running)
        log.info("adopted a recovered workout session")
        return true
    }

    /// First-to-finish gate for the recovery race. Thread-safe so either task may win.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
    }

    private enum CollectionStart { case began, failed(any Error), timedOut }

    private struct CollectionTimedOut: LocalizedError {
        var errorDescription: String? { "beginCollection did not answer in time" }
    }

    /// `beginCollection` hangs the same way `recoverActiveWorkoutSession()` does when healthd
    /// is wedged — observed in the simulator after the app was killed mid-run. Unbounded, it
    /// held the run's tier acquisition open forever: no workout session, no extended-runtime
    /// fallback, and (because the backstop defers while an acquisition is in flight) no
    /// boundary notifications either. Bounded, a stuck start falls back like a failed one,
    /// and the upgrade retries take a session once healthd answers again.
    private func beginCollection(at date: Date, timeout seconds: Double) async -> CollectionStart {
        await withCheckedContinuation { (continuation: CheckedContinuation<CollectionStart, Never>) in
            let once = Once()
            Task { @MainActor in
                guard let builder = self.builder else {
                    if once.claim() { continuation.resume(returning: .timedOut) }
                    return
                }
                let result: CollectionStart
                do {
                    try await builder.beginCollection(at: date)
                    result = .began
                } catch {
                    result = .failed(error)
                }
                if once.claim() { continuation.resume(returning: result) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                if once.claim() {
                    self.log.notice("beginCollection did not answer in \(seconds)s; abandoning the session")
                    continuation.resume(returning: .timedOut)
                }
            }
        }
    }

    /// Whether the user has already answered the Health prompt.
    ///
    /// `authorizationStatus(for:)` is a *synchronous* XPC call to healthd. On the main actor
    /// it froze the whole UI mid-push for over a minute when healthd was degraded (seen in
    /// the simulator after a preferences reset). Run it off the main actor, and if healthd
    /// doesn't answer in two seconds, assume the prompt was answered: an unresponsive
    /// healthd will not be showing a sheet either, and "decided" is the branch that bounds
    /// the authorization request that follows.
    private func authorizationIsDecided() async -> Bool {
        let store = self.store
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = Once()
            Task.detached {
                let decided = store.authorizationStatus(for: HKQuantityType.workoutType()) != .notDetermined
                if once.claim() { continuation.resume(returning: decided) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if once.claim() {
                    self.log.notice("health authorization status did not answer in 2s; treating it as decided")
                    continuation.resume(returning: true)
                }
            }
        }
    }

    /// Waits for the previous run's Health save, but not indefinitely.
    ///
    /// healthd has been seen to accept `finishWorkout()` and then sit in its Saving state
    /// for good (simulator, after a run skipped through every interval). An unbounded wait
    /// here then wedged the *next* run: its session never started, it never fell back to
    /// an extended runtime session, and the notification backstop — which defers while an
    /// acquisition is in flight — never scheduled either. The earlier session has already
    /// ended by this point; only its save is pending, so starting a new one is safe.
    private func awaitTeardown(seconds: Double) async {
        guard let pending = teardownTask else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = Once()
            Task { @MainActor in
                await pending.value
                if once.claim() { continuation.resume() }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                if once.claim() {
                    self.log.notice("previous workout still saving after \(seconds)s; starting anyway")
                    continuation.resume()
                }
            }
        }
    }

    /// `recoverActiveWorkoutSession()` has been observed to never return when healthd is
    /// holding a session in a bad state. Every path that takes a runtime tier calls it first,
    /// so an unbounded await here left runs with no session, no fallback and no log line —
    /// silently. This bounds it.
    ///
    /// Deliberately NOT a task group: a group waits for every child before returning, even a
    /// cancelled one, and the HealthKit completion-handler bridge does not honour
    /// cancellation — so a "timed out" group still hangs on the stuck child, which is exactly
    /// the failure this exists to prevent. Whichever finishes first resumes the continuation;
    /// a stuck recovery call is simply abandoned.
    private func recoverWithTimeout(seconds: Double) async -> HKWorkoutSession? {
        await withCheckedContinuation { (continuation: CheckedContinuation<HKWorkoutSession?, Never>) in
            let once = Once()
            Task { @MainActor in
                let recovered = try? await self.store.recoverActiveWorkoutSession()
                if once.claim() { continuation.resume(returning: recovered) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                if once.claim() {
                    self.log.notice("workout recovery did not answer in \(seconds)s; proceeding without it")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Starts a live workout session. Returns false if one could not be started, so the
    /// caller can fall back.
    func start(at date: Date = Date()) async -> Bool {
        // Wait out any teardown still in flight rather than reporting its stale state.
        await awaitTeardown(seconds: 8)
        guard Self.isSupported, session == nil else { return isRunning }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .highIntensityIntervalTraining
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            session.startActivity(with: date)
            let outcome = await beginCollection(at: date, timeout: 6)
            if case .began = outcome {} else {
                // The session is already running in HealthKit by this point. Dropping our
                // references is not enough — it would carry on with nobody holding it, keep
                // the workout indicator up, and be offered back for "recovery" on the next
                // launch. End it before walking away.
                isEnding = true
                session.end()
                builder.discardWorkout()
                teardown()
                isEnding = false
                if case .failed(let error) = outcome { throw error }
                throw CollectionTimedOut()
            }

            isRunning = true
            log.info("workout session started")
            return true
        } catch {
            log.error("could not start workout session: \(error.localizedDescription, privacy: .public)")
            teardown()
            return false
        }
    }

    /// Marks one interval as its own activity inside the session, so the saved workout
    /// carries per-interval segments with their own heart-rate and energy statistics
    /// instead of one undifferentiated block.
    func beginActivity(for phase: IntervalPhase, at date: Date = Date()) {
        guard let session, let builder else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .highIntensityIntervalTraining
        configuration.locationType = .indoor

        if builder.currentWorkoutActivity != nil {
            session.endCurrentActivity(on: date)
        }
        session.beginNewActivity(
            configuration: configuration,
            date: date,
            metadata: Self.activityMetadata(for: phase)
        )
    }

    nonisolated static let phaseMetadataKey = "IntervallyPhase"
    nonisolated static let roundMetadataKey = "IntervallyRound"

    /// What each Health activity is tagged with. Every activity keeps the workout's HIIT
    /// type, warmup and cooldown included: all activities of an interval workout share the
    /// workout's type, and a different one switches the sensor algorithm mid-session. The
    /// phase rides in metadata instead. A bookend belongs to no round, so it carries none.
    nonisolated static func activityMetadata(for phase: IntervalPhase) -> [String: Any] {
        var metadata: [String: Any] = [
            HKMetadataKeyIndoorWorkout: true,
            phaseMetadataKey: phase.kind.rawValue,
        ]
        if !phase.kind.isBookend { metadata[roundMetadataKey] = phase.round }
        return metadata
    }

    func pause() {
        session?.pause()
    }

    func resume() {
        session?.resume()
    }

    /// Ends the session and saves the workout to Health.
    ///
    /// The session and builder are released *before* the save is awaited: leaving them in
    /// place across the await meant a workout started again in that window (the "Repeat"
    /// button) hit the `session == nil` guard in `start()` and silently got no session.
    /// Returns whether the workout actually reached Health, so the summary can say so
    /// truthfully rather than claiming credit for a save that failed.
    @discardableResult
    func end(at date: Date = Date()) async -> Bool {
        // Published as `teardownTask` so a restart can wait for the Health save rather than
        // creating a competing session while this one is still finishing.
        let save = Task { await performEnd(at: date) }
        teardownTask = Task { _ = await save.value }
        defer { teardownTask = nil }
        return await save.value
    }

    private func performEnd(at date: Date) async -> Bool {
        guard let session, let builder else { return false }
        isEnding = true
        // Close the final interval's activity at exactly the workout's end date. Left open,
        // `session.end()` closes it at whatever instant HealthKit gets round to the call — a
        // fraction of a second after `date` — and HealthKit then rejects the *entire* workout
        // because that activity "did not occur during this workout". Every workout with
        // Health on was failing to save this way.
        if builder.currentWorkoutActivity != nil {
            session.endCurrentActivity(on: date)
        }
        session.end()
        teardown()

        defer { isEnding = false }
        // A session whose collection never began — a leftover recovered from a run that
        // failed to start — has nothing to save, and asking HealthKit to save it fails with
        // "cannot set endDate without a startDate". Discard it instead.
        guard builder.startDate != nil else {
            builder.discardWorkout()
            log.info("discarded a workout session that never collected anything")
            return false
        }
        do {
            try await builder.endCollection(at: date)
            _ = try await builder.finishWorkout()
            log.info("workout saved")
            return true
        } catch {
            log.error("could not save workout: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Discards the session without writing anything to Health.
    func discard() {
        guard let session, let builder else { return }
        isEnding = true
        session.end()
        builder.discardWorkout()
        teardown()
        isEnding = false
    }

    private func teardown() {
        session?.delegate = nil
        builder?.delegate = nil
        session = nil
        builder = nil
        isRunning = false
        heartRate = nil
    }
}

extension WorkoutSessionController: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            self.isRunning = (toState == .running)
            // The system can end a session out from under the app — another workout app
            // takes over, or the watch decides to stop it.
            if toState == .ended, !self.isEnding, self.session != nil {
                self.log.notice("workout session ended by the system")
                self.teardown()
                self.onUnexpectedEnd?()
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.log.error("workout session failed: \(error.localizedDescription, privacy: .public)")
            let wasExpected = self.isEnding
            self.teardown()
            if !wasExpected { self.onUnexpectedEnd?() }
        }
    }
}

extension WorkoutSessionController: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let heartRateType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(heartRateType) else { return }
        let statistics = workoutBuilder.statistics(for: heartRateType)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let value = statistics?.mostRecentQuantity()?.doubleValue(for: unit)
        Task { @MainActor in
            self.heartRate = value
        }
    }
}
