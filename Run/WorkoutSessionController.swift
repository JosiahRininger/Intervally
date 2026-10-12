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

    nonisolated static var typesToShare: Set<HKSampleType> { [HKQuantityType.workoutType()] }
    /// Only what Intervally uses. Heart rate is shown during a run; active energy feeds the
    /// workout's totals. The activity summary (ring data) was requested but never read —
    /// and HealthKit review holds apps to asking for exactly what they need. Workouts are
    /// read by History on the iPhone, which shares this app's Health identity: asking for
    /// them here too keeps either app's request from undoing the other's (`HealthAccess`).
    nonisolated static var typesToRead: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKObjectType.workoutType(),
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
                    try await self.store.requestAuthorization(toShare: Self.typesToShare, read: Self.typesToRead)
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
        // A relaunch lost the mirror with the old process; the iPhone picks the run up again.
        startMirroring()
        return true
    }

    /// Adopts the recovered session of a run of `workout`, and tags it if the tag never
    /// landed: the app can be terminated between `beginCollection` and `addMetadata`, and
    /// that save would then never show in History.
    func adoptRecoveredSession(for workout: IntervalWorkout) async -> Bool {
        guard await adoptRecoveredSession() else { return false }
        if let builder, Self.needsTag(builder.metadata) {
            log.notice("recovered workout was never tagged; tagging it now")
            tag(builder, with: workout)
        }
        return true
    }

    /// Whether a workout's metadata lacks the preset ID History finds it by.
    nonisolated static func needsTag(_ metadata: [String: Any]) -> Bool {
        metadata[HealthMetadata.presetID] == nil
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
    /// Asks whether this exact request would show the sheet, not what the workout type's
    /// sharing status is. The iPhone app shares this app's Health identity, and its History
    /// asks to read workouts: once that was granted, sharing no longer read as
    /// `.notDetermined` on a watch that had never asked to share. The sheet then got the
    /// five-second bound meant for an answered one, and the first run started behind it with
    /// no workout session (paired simulators).
    ///
    /// Bounded: healthd has been seen to stop answering (the simulator, after a preferences
    /// reset, froze the UI for over a minute on the old synchronous status call). If it
    /// doesn't answer in two seconds, assume the prompt was answered: an unresponsive healthd
    /// will not be showing a sheet either, and "decided" is the branch that bounds the
    /// authorization request that follows.
    private func authorizationIsDecided() async -> Bool {
        let store = self.store
        let share = Self.typesToShare
        let read = Self.typesToRead
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = Once()
            Task.detached {
                let status = try? await store.statusForAuthorizationRequest(toShare: share, read: read)
                if once.claim() { continuation.resume(returning: Self.isDecided(status)) }
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

    /// Whether a request would come back without showing a sheet. Only `.shouldRequest`
    /// means a sheet; HealthKit's not knowing, or an error, counts as answered, which bounds
    /// the request rather than leaving Start waiting on healthd.
    nonisolated static func isDecided(_ status: HKAuthorizationRequestStatus?) -> Bool {
        status != .shouldRequest
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
        await start(at: date, tagging: nil)
    }

    /// Starts a live workout session for `workout`, and tags the saved Health workout with it
    /// (`workoutMetadata(for:)`) so History on the iPhone can find it and name it.
    func start(at date: Date, for workout: IntervalWorkout) async -> Bool {
        await start(at: date, tagging: workout)
    }

    private func start(at date: Date, tagging workout: IntervalWorkout?) async -> Bool {
        // Wait out any teardown still in flight rather than reporting its stale state.
        await awaitTeardown(seconds: 8)
        guard Self.isSupported, session == nil else { return isRunning }

        // The preset's own activity: what Fitness shows it as, and on the watch what its
        // calories are estimated for.
        let configuration = (workout?.activityKind ?? .standard).configuration

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
            if let workout { tag(builder, with: workout) }

            isRunning = true
            log.info("workout session started")
            startMirroring()
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
        // Each interval is the session's own activity, a recovered session's included.
        let configuration = session.workoutConfiguration

        if builder.currentWorkoutActivity != nil {
            session.endCurrentActivity(on: date)
        }
        session.beginNewActivity(
            configuration: configuration,
            date: date,
            metadata: Self.activityMetadata(for: phase, indoor: configuration.locationType != .outdoor)
        )
    }

    /// Tags the collecting workout with the preset it runs, without holding up the start. The
    /// tags only matter at the save, a whole run away, and a wedged healthd must not keep the
    /// run waiting for its tier (see `beginCollection`). A failure leaves the session out of
    /// History altogether, which finds Intervally's workouts by the preset ID alone, though
    /// it still saves to Health and Fitness. It is logged, and a recovered session is tagged
    /// again (`adoptRecoveredSession(for:)`); one that stays in this process is not retried.
    private func tag(_ builder: HKLiveWorkoutBuilder, with workout: IntervalWorkout) {
        Task { @MainActor in
            do {
                try await builder.addMetadata(Self.workoutMetadata(for: workout))
                self.log.info("workout tagged with its preset")
            } catch {
                self.log.error("could not tag the workout: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// What the saved workout is tagged with: the preset's ID, which is how History finds
    /// Intervally's workouts, its name as it was, and the rounds planned, so History can tell
    /// a run that ended early. A blank name is left out rather than written empty.
    nonisolated static func workoutMetadata(for workout: IntervalWorkout) -> [String: Any] {
        var metadata: [String: Any] = [
            HealthMetadata.presetID: workout.id.uuidString,
            HealthMetadata.plannedRounds: workout.clamped.rounds,
        ]
        let name = workout.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { metadata[HealthMetadata.presetName] = name }
        // Said outright, so History reads an outdoor run back as one whatever HealthKit adds.
        metadata[HKMetadataKeyIndoorWorkout] = !workout.activityKind.isOutdoor
        return metadata
    }

    nonisolated static let phaseMetadataKey = HealthMetadata.phase
    nonisolated static let roundMetadataKey = HealthMetadata.round

    /// What each Health activity is tagged with. Every activity keeps the workout's HIIT
    /// type, warmup and cooldown included: all activities of an interval workout share the
    /// workout's type, and a different one switches the sensor algorithm mid-session. The
    /// phase rides in metadata instead. A bookend belongs to no round, so it carries none.
    nonisolated static func activityMetadata(for phase: IntervalPhase, indoor: Bool = true) -> [String: Any] {
        var metadata: [String: Any] = [
            HKMetadataKeyIndoorWorkout: indoor,
            phaseMetadataKey: phase.kind.rawValue,
        ]
        if !phase.kind.isBookend { metadata[roundMetadataKey] = phase.round }
        // As it was named when it ran, so a rename later doesn't rewrite the past.
        if let label = phase.label {
            metadata[HealthMetadata.phaseName] = label.name
            metadata[HealthMetadata.phaseSymbol] = label.symbol.rawValue
        }
        return metadata
    }

    // MARK: - Mirroring to the iPhone

    /// Commands the iPhone's buttons sent for this run (`RunMirrorCommand`).
    var onRemoteCommand: ((RunMirrorCommand) -> Void)?
    /// Sent again once mirroring starts.
    private var lastMirrored: RunMirrorState?

    /// Hands the session to the iPhone app, which shows the run live and can pause, skip and
    /// end it. Best effort: with no iPhone app, or the iPhone out of reach, the run carries on
    /// exactly as before. Only the watch can mirror (watchOS 10).
    private func startMirroring() {
        #if os(watchOS)
        guard let session else { return }
        Task { @MainActor in
            do {
                try await session.startMirroringToCompanionDevice()
                self.log.info("mirroring the workout to the iPhone")
                // The run's first state went before the iPhone was there to take it.
                if let lastMirrored = self.lastMirrored { self.mirror(lastMirrored) }
            } catch {
                self.log.notice("not mirrored to the iPhone: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
    }

    /// Sends the run as it now stands to the iPhone's mirror. Nothing without a session, and
    /// nothing on iPhone, whose own sessions have no mirror.
    func mirror(_ state: RunMirrorState) {
        #if os(watchOS)
        lastMirrored = state
        guard let session, let data = RunMirrorMessage.state(state).encoded() else { return }
        Task { @MainActor in
            do {
                try await session.sendToRemoteWorkoutSession(data: data)
            } catch {
                self.log.debug("mirror state not sent: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
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

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]
    ) {
        let commands = data.compactMap(RunMirrorMessage.decoded).compactMap { message -> RunMirrorCommand? in
            if case .command(let command) = message { return command }
            return nil
        }
        guard !commands.isEmpty else { return }
        Task { @MainActor in
            for command in commands {
                self.log.info("command from the iPhone: \(String(describing: command), privacy: .public)")
                self.onRemoteCommand?(command)
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: (any Error)?) {
        Task { @MainActor in
            self.log.notice("the iPhone's mirror disconnected: \(error?.localizedDescription ?? "no error", privacy: .public)")
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
