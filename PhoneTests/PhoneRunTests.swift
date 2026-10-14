//
//  PhoneRunTests.swift
//  IntervallyPhoneTests
//

import AVFoundation
import Foundation
import Testing
@testable import IntervallyPhone

// MARK: - Stand-ins

/// Records what a cue player asked of the speaker, the voice and the Taptic Engine.
@MainActor
final class FakeCueOutput: CueOutput {
    enum Call: Equatable {
        case tone(CueTone)
        case say(String, after: TimeInterval)
        case tap(CueTap)
        case silence
        case release
    }

    private(set) var calls: [Call] = []
    var onVolumeChange: ((Float) -> Void)?
    var onHealthReport: ((Bool) -> Void)?
    var lowersOtherAudio = true
    /// How often a run asked to hold the audio; apart from `calls`, as every event asks.
    private(set) var holds = 0
    /// Whether the cues can sound, reported at every hold as the real output does.
    var healthy = true
    func holdForRun() {
        holds += 1
        onHealthReport?(healthy)
    }

    /// What the media volume would report, as the audio session's KVO does.
    func report(volume: Float) { onVolumeChange?(volume) }

    func play(_ tone: CueTone) -> TimeInterval {
        calls.append(.tone(tone))
        return ToneSynth.duration(of: tone)
    }

    func say(_ phrase: String, after delay: TimeInterval) { calls.append(.say(phrase, after: delay)) }
    func tap(_ tap: CueTap) { calls.append(.tap(tap)) }
    func silence() { calls.append(.silence) }
    func handBackAudio() { calls.append(.release) }
    func reset() { calls = [] }
}

/// A workout session that starts whenever asked, so a run takes the workout tier.
@MainActor
final class FakeWorkoutSession: WorkoutSessioning {
    var isSupported = true
    var startsSucceed = true
    private(set) var isRunning = false
    var heartRate: Double? { nil }
    var onUnexpectedEnd: (() -> Void)?
    private(set) var activities: [IntervalPhase.Kind] = []
    private(set) var ended = 0
    private(set) var discarded = 0

    func requestAuthorization() async -> Bool { true }
    func adoptRecoveredSession() async -> Bool { false }
    func start(at date: Date) async -> Bool {
        isRunning = startsSucceed
        return startsSucceed
    }
    func beginActivity(for phase: IntervalPhase, at date: Date) { activities.append(phase.kind) }
    func pause() {}
    func resume() {}
    func end(at date: Date) async -> Bool {
        isRunning = false
        ended += 1
        return true
    }
    func discard() {
        isRunning = false
        discarded += 1
    }
}

/// Counts the notification backstop's schedules and cancels.
actor FakeBackstop: BoundaryScheduling {
    private(set) var schedules = 0
    private(set) var cancels = 0
    func requestAuthorization() async -> Bool { true }
    func schedule(plan: IntervalPlan, anchor: Date) async { schedules += 1 }
    func cancelAll() async { cancels += 1 }
}

/// What the Live Activity would have been shown, in order.
@MainActor
final class RecordingPresenter: RunPresenting {
    private(set) var shown: [RunPresentation?] = []
    func present(_ run: RunPresentation?) { shown.append(run) }
}

// MARK: - Cues

@Suite("iPhone cues")
@MainActor
struct CuePlanTests {
    let work = IntervalPhase(id: 1, kind: .work, duration: 30, round: 3, start: 10)
    let lastWork = IntervalPhase(id: 15, kind: .work, duration: 30, round: 8, start: 325)
    let rest = IntervalPhase(id: 2, kind: .rest, duration: 15, round: 3, start: 40)
    let prepare = IntervalPhase(id: 0, kind: .prepare, duration: 10, round: 1, start: 0)
    let all = CueSettings(beeps: true, countdown: true, voice: true)

    private func plan(_ event: TimerEvent, _ settings: CueSettings? = nil, late: TimeInterval = 0) -> CuePlan {
        CuePlan.make(
            for: event, context: BoundaryContext(lateness: late, phaseDuration: 30),
            settings: settings ?? all, totalRounds: 8
        )
    }

    @Test("Work starts high and is called out; rest starts low")
    func phaseStarts() {
        #expect(plan(.phaseBegan(work)) == CuePlan(tone: .go, phrase: "Work", tap: .heavy))
        #expect(plan(.phaseBegan(rest)) == CuePlan(tone: .ease, phrase: "Rest", tap: .heavy))
        #expect(plan(.phaseBegan(prepare)) == CuePlan(tone: .ready, phrase: "Get ready", tap: .heavy))
    }

    @Test("The last work interval says so, and a single round never does")
    func lastRound() {
        #expect(plan(.phaseBegan(lastWork)).phrase == "Last round")
        let only = IntervalPhase(id: 1, kind: .work, duration: 30, round: 1, start: 0)
        #expect(CuePlan.phrase(for: only, totalRounds: 1) == "Work")
    }

    @Test("3, 2, 1 ticks and taps lightly, unless the countdown is off")
    func countdown() {
        #expect(plan(.countdown(secondsRemaining: 2)) == CuePlan(tone: .tick, phrase: nil, tap: .light))
        var off = all
        off.countdown = false
        #expect(plan(.countdown(secondsRemaining: 2), off) == .silent)
    }

    @Test("The finish chimes and the coach says the workout is complete")
    func finish() {
        #expect(plan(.finished) == CuePlan(tone: .finish, phrase: "Workout complete", tap: .success))
    }

    @Test("Beeps off keeps the voice and the tap; the voice off keeps the beep")
    func eachSettingAlone() {
        var noBeeps = all
        noBeeps.beeps = false
        #expect(plan(.phaseBegan(work), noBeeps) == CuePlan(tone: nil, phrase: "Work", tap: .heavy))
        var noVoice = all
        noVoice.voice = false
        #expect(plan(.phaseBegan(work), noVoice) == CuePlan(tone: .go, phrase: nil, tap: .heavy))
    }

    @Test("A change announced late, after the app was away, plays nothing")
    func lateIsSilent() {
        #expect(plan(.phaseBegan(work), late: 1.4) != .silent)
        #expect(plan(.phaseBegan(work), late: 2) == .silent)
        #expect(plan(.finished, late: 30) == .silent)
    }

    @Test("Everything is on until turned off; the voice needs Pro but its choice is kept")
    func settings() {
        let defaults = makeTestDefaults()
        #expect(CueSettings.stored(in: defaults) == all)
        defaults.set(false, forKey: CueSettings.Key.beeps)
        defaults.set(false, forKey: CueSettings.Key.countdown)
        #expect(CueSettings.stored(in: defaults) == CueSettings(beeps: false, countdown: false, voice: true))
        #expect(all.effective(isPro: false).voice == false)
        #expect(all.effective(isPro: true).voice == true)
        #expect(all.effective(isPro: false).beeps, "Beeps are free")
    }

    @Test("Settings' Sounds row says what will play")
    func soundsRow() {
        #expect(SoundsRow.subtitle(all) == "Beeps and voice coach")
        #expect(SoundsRow.subtitle(all.effective(isPro: false)) == "Beeps")
        #expect(SoundsRow.subtitle(CueSettings(beeps: false, countdown: true, voice: false)) == "Off")
    }
}

@Suite("Cue tones")
struct ToneSynthTests {
    @Test("Every tone is a playable 16-bit mono WAV of its notes' length", arguments: CueTone.allCases)
    func wav(tone: CueTone) {
        let data = ToneSynth.wav(for: tone)
        #expect(data.prefix(4) == Data("RIFF".utf8))
        #expect(data.subdata(in: 8..<16) == Data("WAVEfmt ".utf8))
        let samples = (data.count - 44) / 2
        let expected = ToneSynth.notes(for: tone).reduce(0) { $0 + Int($1.1 * Double(ToneSynth.sampleRate)) }
        #expect(samples == expected)
        #expect(ToneSynth.duration(of: tone) < 0.8, "Short enough to finish inside a 10-second rest")
    }

    @Test("Tones never clip, and fade out rather than click")
    func envelope() {
        for tone in CueTone.allCases {
            let samples = ToneSynth.samples(for: tone)
            #expect(samples.allSatisfy { $0 > Int16.min })
            #expect(abs(Int(samples.last ?? 0)) < 200)
        }
    }
}

@Suite("Cue player")
@MainActor
struct PhoneCuePlayerTests {
    let output = FakeCueOutput()
    let pro = FakePro(isPro: true)
    let defaults = makeTestDefaults()

    private func player() -> PhoneCuePlayer {
        let player = PhoneCuePlayer(output: output, pro: pro, defaults: defaults)
        player.roundsInRun = { 8 }
        return player
    }

    @Test("A run with any sound on holds the audio from its first event, so cues can sound away from the app")
    func holdsTheAudio() {
        let phase = IntervalPhase(id: 0, kind: .prepare, duration: 10, round: 1, start: 0)
        player().play(.phaseBegan(phase), context: .immediate)
        #expect(output.holds == 1)
        defaults.set(false, forKey: CueSettings.Key.beeps)
        player().play(.phaseBegan(phase), context: .immediate)
        #expect(output.holds == 2, "The voice alone still needs the audio")
        defaults.set(false, forKey: CueSettings.Key.voice)
        player().play(.phaseBegan(phase), context: .immediate)
        #expect(output.holds == 2, "Nothing to hear: nothing held")
    }

    @Test("The voice waits for the tone to finish, and a tap goes with it")
    func voiceFollowsTone() {
        let work = IntervalPhase(id: 1, kind: .work, duration: 30, round: 2, start: 0)
        player().play(.phaseBegan(work), context: .immediate)
        #expect(output.calls == [
            .tone(.go), .say("Work", after: ToneSynth.duration(of: .go)), .tap(.heavy),
        ])
    }

    @Test("Without Pro the coach stays quiet")
    func freeHasNoVoice() {
        pro.isPro = false
        player().play(.finished, context: .immediate)
        #expect(output.calls == [.tone(.finish), .tap(.success)])
    }

    @Test("Pause and resume are felt, not heard; stopping silences what is playing")
    func transport() {
        let player = player()
        player.transport(.stop)
        player.cancelPending()
        #expect(output.calls == [.tap(.light), .silence])
    }

    @Test("Play a Sample plays a work change with the current choices")
    func preview() {
        player().preview()
        #expect(output.calls.first == .tone(.go))
        #expect(output.calls.contains(.say("Work", after: ToneSynth.duration(of: .go))))
    }

    /// A player that hands a finished run's audio back after 50 ms rather than seconds.
    private func quickPlayer() -> PhoneCuePlayer {
        let player = player()
        player.releaseAfterFinish = 0.05
        return player
    }

    @Test("A finished run hands the audio back once the finish has sounded, with no Done")
    func releasesAfterTheFinish() async {
        let player = quickPlayer()
        player.play(.finished, context: .immediate)
        #expect(!output.calls.contains(.release), "Not over the chime")
        #expect(await waitUntil { output.calls.last == .release })
        #expect(output.calls.filter { $0 == .release }.count == 1)
    }

    @Test("Repeat keeps the audio: the new run's first event calls the release off")
    func repeatKeepsTheAudio() async throws {
        let player = quickPlayer()
        player.play(.finished, context: .immediate)
        let prepare = IntervalPhase(id: 0, kind: .prepare, duration: 10, round: 1, start: 0)
        player.play(.phaseBegan(prepare), context: .immediate)
        try await Task.sleep(for: .milliseconds(250))
        #expect(!output.calls.contains(.release))
    }

    @Test("A run going again by the time the release is due keeps the audio")
    func activeRunKeepsTheAudio() async throws {
        let player = quickPlayer()
        player.runIsActive = { true }
        player.play(.finished, context: .immediate)
        try await Task.sleep(for: .milliseconds(250))
        #expect(!output.calls.contains(.release))
    }

    @Test("Done before the release hands the audio back once, not twice")
    func doneFirst() async throws {
        let player = quickPlayer()
        player.play(.finished, context: .immediate)
        player.release()
        try await Task.sleep(for: .milliseconds(250))
        #expect(output.calls.filter { $0 == .release }.count == 1)
    }

    @Test("A run under way takes the audio when asked, if it has anything to be heard")
    func holdIfSounding() {
        player().holdIfSounding()
        #expect(output.holds == 1)
        defaults.set(false, forKey: CueSettings.Key.beeps)
        defaults.set(false, forKey: CueSettings.Key.voice)
        player().holdIfSounding()
        #expect(output.holds == 1, "Nothing to hear: nothing held")
    }
}

// MARK: - What the run shows outside the app

@Suite("Run presentation")
@MainActor
struct RunPresentationTests {
    let plan = IntervalPlan(workout: IntervalWorkout(name: "Tabata", prepareSeconds: 10, workSeconds: 20, restSeconds: 10, rounds: 8))
    let anchor = Date(timeIntervalSince1970: 1_000_000)

    @Test("Nothing before the start")
    func idle() {
        #expect(RunPresentation(plan: plan, status: .idle, anchor: nil, elapsed: 0) == nil)
    }

    @Test("Running: the phase, the next one, and dates that count on their own")
    func running() throws {
        let run = try #require(RunPresentation(plan: plan, status: .running, anchor: anchor, elapsed: 15))
        #expect(run.phase?.kind == .work)
        #expect(run.phase?.round == 1)
        #expect(run.next?.kind == .rest)
        #expect(run.workoutName == "Tabata")
        #expect(run.clock == .running(
            phaseStart: anchor.addingTimeInterval(10),
            phaseEnd: anchor.addingTimeInterval(30),
            workoutEnd: anchor.addingTimeInterval(plan.totalDuration)
        ))
    }

    @Test("Paused: what was left of the phase and the workout")
    func paused() throws {
        let run = try #require(RunPresentation(plan: plan, status: .paused, anchor: nil, elapsed: 15))
        #expect(run.isPaused)
        #expect(run.clock == .paused(remainingInPhase: 15, remainingInWorkout: plan.totalDuration - 15))
    }

    @Test("The last phase has no next; a finished run has no phase")
    func ends() throws {
        let last = try #require(RunPresentation(plan: plan, status: .running, anchor: anchor, elapsed: plan.totalDuration - 1))
        #expect(last.next == nil)
        #expect(last.phase?.round == 8)
        let done = try #require(RunPresentation(plan: plan, status: .finished, anchor: nil, elapsed: plan.totalDuration))
        #expect(done.phase == nil)
        #expect(done.clock == .finished)
    }

    @Test("The Live Activity carries the phase, its length, the next and the theme")
    func activityState() throws {
        let run = try #require(RunPresentation(plan: plan, status: .running, anchor: anchor, elapsed: 32))
        let state = RunActivityAttributes.ContentState(run, theme: .pastel)
        #expect(state.phase == .rest)
        #expect(state.phaseDuration == 10)
        #expect(state.round == 1)
        #expect(state.next == .work)
        #expect(state.nextDuration == 20)
        #expect(state.theme == .pastel)
        #expect(state.staleDate == anchor.addingTimeInterval(40 + 2), "Stale a moment after the phase ends")
        let attributes = RunActivityAttributes(run)
        #expect(attributes.totalRounds == 8)
        #expect(attributes.totalDuration == plan.totalDuration)
    }

    @Test("A finished run reads as the last round, and a paused one never goes stale")
    func activityEnds() throws {
        let done = try #require(RunPresentation(plan: plan, status: .finished, anchor: nil, elapsed: plan.totalDuration))
        let state = RunActivityAttributes.ContentState(done, theme: .classic)
        #expect(state.round == 8)
        #expect(state.phase == nil)
        #expect(state.staleDate == nil)
        let paused = try #require(RunPresentation(plan: plan, status: .paused, anchor: nil, elapsed: 5))
        #expect(RunActivityAttributes.ContentState(paused, theme: .classic).staleDate == nil)
    }
}

// MARK: - The run screen

@Suite("Run screen")
struct RunScreenLayoutTests {
    @Test("Only a short landscape screen puts the ring beside the controls")
    func sideBySide() {
        // iPhone Duo's inner screen, opened.
        #expect(RunScreenLayout.isSideBySide(width: 951, height: 640))
        #expect(RunScreenLayout.sideRingSide(width: 951, height: 640) == 436)
        // Every iPhone, iPad either way up, and the Duo closed stack them.
        #expect(!RunScreenLayout.isSideBySide(width: 402, height: 780))
        #expect(!RunScreenLayout.isSideBySide(width: 1376, height: 980))
        #expect(!RunScreenLayout.isSideBySide(width: 1032, height: 1300))
        #expect(!RunScreenLayout.isSideBySide(width: 381, height: 640))
    }

    @Test("The ring fills the width with a margin, and leaves the controls room on an SE")
    func ringSide() {
        #expect(RunScreenLayout.ringSide(width: 402, height: 780) == 346)
        #expect(RunScreenLayout.ringSide(width: 440, height: 860) == 380)
        #expect(RunScreenLayout.ringSide(width: 375, height: 560) == 280)
        #expect(RunScreenLayout.ringSide(width: 320, height: 300) == 220, "Never below 220")
        // iPad: room for more than any iPhone's 380.
        #expect(RunScreenLayout.ringSide(width: 1032, height: 1300) == 520)
        #expect(RunScreenLayout.ringSide(width: 1376, height: 980) == 490)
    }

    @Test("Round 3 of 8 only in the work and rest of a run with rounds")
    func roundLine() {
        func phase(_ kind: IntervalPhase.Kind, round: Int = 3) -> IntervalPhase {
            IntervalPhase(id: 0, kind: kind, duration: 30, round: round, start: 0)
        }
        #expect(RunScreenLayout.roundLine(for: phase(.work), totalRounds: 8) == "Round 3 of 8")
        #expect(RunScreenLayout.roundLine(for: phase(.rest), totalRounds: 8) == "Round 3 of 8")
        #expect(RunScreenLayout.roundLine(for: phase(.prepare, round: 1), totalRounds: 8) == nil)
        #expect(RunScreenLayout.roundLine(for: phase(.warmup, round: 1), totalRounds: 8) == nil)
        #expect(RunScreenLayout.roundLine(for: phase(.cooldown, round: 8), totalRounds: 8) == nil)
        #expect(RunScreenLayout.roundLine(for: phase(.work, round: 1), totalRounds: 1) == nil)
    }

    @Test("The header gets the room between the figures, the same each side, and never less than nothing")
    func headerBetweenFigures() {
        // An iPhone SE's run screen, 375 points less its margins.
        #expect(FlankedLayout.centreWidth(in: 327, leading: 0, trailing: 0, spacing: 8) == 327, "No figures, the whole width")
        #expect(FlankedLayout.centreWidth(in: 327, leading: 92, trailing: 80, spacing: 8) == 127, "Room for the wider figure, both sides")
        #expect(FlankedLayout.centreWidth(in: 327, leading: 0, trailing: 80, spacing: 8) == 151, "One figure still keeps the header centred")
        #expect(FlankedLayout.centreWidth(in: 100, leading: 90, trailing: 90, spacing: 8) == 0)
        // Centred in what's left, the header never reaches either figure.
        for (leading, trailing) in [(92.0, 80.0), (140.0, 60.0), (0.0, 110.0)] {
            let width: CGFloat = 327
            let centre = FlankedLayout.centreWidth(in: width, leading: leading, trailing: trailing, spacing: 8)
            #expect((width - centre) / 2 >= leading + 8)
            #expect((width + centre) / 2 <= width - trailing - 8)
        }
    }

    @Test("Next names the phase and its length, or says this is the last")
    func nextLine() {
        let work = IntervalPhase(id: 1, kind: .work, duration: 30, round: 1, start: 10)
        let rest = IntervalPhase(id: 2, kind: .rest, duration: 15, round: 1, start: 40)
        #expect(RunScreenLayout.nextLine(after: work, next: rest) == "Next: Rest 0:15")
        #expect(RunScreenLayout.nextLine(after: work, next: nil) == "Last interval")
        #expect(RunScreenLayout.nextLine(after: nil, next: nil) == "")
    }
}

// MARK: - A run on iPhone, end to end

@Suite("Running on iPhone")
@MainActor
struct PhoneRunTests {
    let defaults = makeTestDefaults()
    let pro = FakePro()
    let output = FakeCueOutput()
    let session = FakeWorkoutSession()
    let backstop = FakeBackstop()
    let presenter = RecordingPresenter()

    private func makeRun() -> (PhoneRun, WorkoutStore) {
        let store = WorkoutStore(defaults: defaults)
        let run = PhoneRun(
            store: store, pro: pro, theme: ThemeStore(defaults: defaults), output: output,
            workout: session, notifications: backstop, presenter: presenter, defaults: defaults
        )
        return (run, store)
    }

    @Test("Start makes the workout the one up next, opens the screen, and runs it on a workout session")
    func start() async throws {
        let (run, store) = makeRun()
        let tabata = try #require(store.workouts.first { $0.name == "Tabata" })
        run.start(tabata)
        #expect(store.selectedID == tabata.id)
        #expect(run.isPresented)

        run.coordinator.begin()
        #expect(await waitUntil { run.coordinator.tier == .workout })
        #expect(run.coordinator.engine.status == .running)
        #expect(run.coordinator.engine.plan.workout.name == "Tabata")
        #expect(session.activities.first == .prepare, "The phase under way is segmented in Health")
        #expect(output.calls.contains(.tone(.ready)), "Get Ready is announced")
        let shown = try #require(presenter.shown.last ?? nil)
        #expect(shown.phase?.kind == .prepare)
        // A workout session plays the cues itself: no notifications as well.
        await run.coordinator.backstopSettled()
        #expect(await backstop.schedules == 0)
        run.close()
    }

    @Test("Start while a run is under way only brings it back to the screen")
    func startWhileRunning() async throws {
        let (run, store) = makeRun()
        run.start(store.workouts[0])
        run.coordinator.begin()
        #expect(await waitUntil { run.coordinator.engine.status == .running })
        run.isPresented = false
        run.start(store.workouts[1])
        #expect(run.isPresented)
        #expect(store.selectedID == store.workouts[0].id)
        run.close()
    }

    @Test("Without a workout session the notification backstop marks each change")
    func backstopWithoutHealth() async {
        session.startsSucceed = false
        let (run, store) = makeRun()
        run.start(store.workouts[0])
        run.coordinator.begin()
        #expect(await waitUntil { run.coordinator.tier == .extendedRuntime })
        await run.coordinator.backstopSettled()
        #expect(await backstop.schedules >= 1)
        run.close()
    }

    @Test("Skipping to the end finishes the run, saves it, shows it complete and counts it")
    func finish() async throws {
        let (run, store) = makeRun()
        run.start(store.workouts[0])
        run.coordinator.begin()
        #expect(await waitUntil { run.coordinator.tier == .workout })
        while run.coordinator.engine.status == .running { run.coordinator.skip() }
        #expect(run.coordinator.engine.status == .finished)
        #expect(output.calls.contains(.tone(.finish)))
        let shown = try #require(presenter.shown.last ?? nil)
        #expect(shown.clock == .finished)
        #expect(await waitUntil { run.coordinator.summary?.health == .saved })
        #expect(session.ended == 1)
        run.recordFinish()
        #expect(run.finishedRuns == 1)
        run.close()
        #expect(!run.isPresented)
        #expect(run.coordinator.engine.status == .idle)
    }

    @Test("End stops the run, discards its session, and clears what the Lock Screen showed")
    func end() async {
        let (run, store) = makeRun()
        run.start(store.workouts[0])
        run.coordinator.begin()
        #expect(await waitUntil { run.coordinator.tier == .workout })
        run.close()
        #expect(!run.isPresented)
        #expect(session.discarded == 1)
        #expect(presenter.shown.last == .some(nil))
        #expect(store.loadActiveRun() == nil, "Nothing left to restore")
    }

    @Test("A run interrupted by a termination comes back on screen, still counting")
    func restore() async {
        let (first, store) = makeRun()
        first.start(store.workouts[0])
        first.coordinator.begin()
        #expect(await waitUntil { first.coordinator.engine.status == .running })
        // The app is terminated: the snapshot is all that survives.
        let (again, _) = makeRun()
        again.restoreAtLaunch()
        #expect(again.isPresented)
        #expect(again.coordinator.engine.status == .running)
        again.close()
        first.close()
    }

    @Test("The screen stays on during a run on screen, unless turned off")
    func keepAwake() async {
        let (run, store) = makeRun()
        #expect(!run.keepsScreenAwake)
        run.start(store.workouts[0])
        run.coordinator.begin()
        #expect(await waitUntil { run.coordinator.engine.status == .running })
        #expect(run.keepsScreenAwake)
        defaults.set(false, forKey: CueSettings.Key.keepAwake)
        #expect(!run.keepsScreenAwake)
        run.close()
    }

    @Test("A run holds the audio until it is over, then hands it back")
    func audioIsHeldForTheRun() async {
        let (run, store) = makeRun()
        run.start(store.workouts[0])
        run.coordinator.begin()
        #expect(await waitUntil { run.coordinator.engine.status == .running })
        run.coordinator.togglePause()
        #expect(!output.calls.contains(.release), "A pause keeps it, so the volume buttons still set the cues' volume")
        run.close()
        #expect(output.calls.last == .release)
    }

    @Test("Too quiet to hear: the run screen asks for more volume, only during a run with cues on")
    func lowVolumeHint() async {
        let (run, store) = makeRun()
        output.report(volume: 0.05)
        #expect(!run.isVolumeLow, "No run, no hint")
        run.start(store.workouts[0])
        run.coordinator.begin()
        #expect(await waitUntil { run.coordinator.engine.status == .running })
        #expect(run.isVolumeLow)
        output.report(volume: 0.5)
        #expect(!run.isVolumeLow)
        output.report(volume: 0.05)
        defaults.set(false, forKey: CueSettings.Key.beeps)
        #expect(!run.isVolumeLow, "Nothing to hear without beeps or the voice")
        pro.isPro = true
        #expect(run.isVolumeLow, "The voice coach is on with Pro")
        run.close()
    }

    @Test("Finishing hands the audio back a few seconds later, with the summary still up")
    func finishReleasesTheAudio() async {
        let (run, store) = makeRun()
        run.cues.releaseAfterFinish = 0.05
        run.start(store.workouts[0])
        run.coordinator.begin()
        #expect(await waitUntil { run.coordinator.engine.status == .running })
        while run.coordinator.engine.status == .running { run.coordinator.skip() }
        #expect(await waitUntil { output.calls.last == .release })
        #expect(run.isPresented, "Released without Done")
        run.close()
    }

    @Test("Repeat right after the finish keeps the audio for the new run")
    func repeatKeepsTheAudio() async throws {
        let (run, store) = makeRun()
        run.cues.releaseAfterFinish = 0.05
        run.start(store.workouts[0])
        run.coordinator.begin()
        #expect(await waitUntil { run.coordinator.engine.status == .running })
        while run.coordinator.engine.status == .running { run.coordinator.skip() }
        run.coordinator.restart()
        #expect(await waitUntil { run.coordinator.engine.status == .running })
        try await Task.sleep(for: .milliseconds(250))
        #expect(!output.calls.contains(.release))
        run.close()
    }

    @Test("A run restored after a relaunch takes the audio at once, not at its next change")
    func restoredRunHoldsTheAudio() async {
        let (first, store) = makeRun()
        first.start(store.workouts[0])
        first.coordinator.begin()
        #expect(await waitUntil { first.coordinator.engine.status == .running })
        let before = output.holds
        let (again, _) = makeRun()
        again.restoreAtLaunch()
        #expect(output.holds == before + 1)
        again.handleForeground()
        #expect(output.holds > before + 1, "Back in front, it takes it again")
        again.close()
        first.close()
    }

    @Test("Cues that can't sound when a run starts bring the notifications, after a run that ended that way too")
    func failureOutlastsTheRun() async {
        output.healthy = false
        let (run, store) = makeRun()
        run.start(store.workouts[0])
        run.coordinator.begin()
        #expect(await waitUntil { run.coordinator.cuesFailing })
        while run.coordinator.engine.status == .running { run.coordinator.skip() }
        run.coordinator.restart()
        #expect(await waitUntil { run.coordinator.engine.status == .running })
        #expect(run.coordinator.cuesFailing, "Still failing: the new run is told, and marks changes with notifications")
        await run.coordinator.backstopSettled()
        #expect(await backstop.schedules >= 1)
        output.healthy = true
        run.cues.holdIfSounding()
        #expect(!run.coordinator.cuesFailing)
        run.close()
    }

    @Test("Cues know the run's rounds, for Last round")
    func lastRoundUsesTheRun() async {
        let (run, store) = makeRun()
        run.start(store.workouts[0])
        run.coordinator.begin()
        #expect(await waitUntil { run.coordinator.engine.status == .running })
        #expect(run.cues.roundsInRun() == run.coordinator.engine.plan.totalRounds)
        run.close()
    }
}

@Suite("Cue engine audio")
struct CueEngineAudioTests {
    @Test("Speech is resampled to the cues' rate, keeping its length in time")
    func resampling() {
        let pcm = SpokenPCM(sampleRate: 22_050, samples: (0..<2_205).map { Float($0) / 2_205 })
        let resampled = pcm.resampled(to: 44_100)
        #expect(resampled.count == 4_410, "A tenth of a second either way")
        #expect(resampled.first == 0)
        #expect(abs((resampled.last ?? 0) - 1) < 0.01, "Ends where it ended")
        #expect(zip(resampled, resampled.dropFirst()).allSatisfy { $0 <= $1 }, "No glitches between samples")
        #expect(pcm.resampled(to: 22_050) == pcm.samples)
        #expect(SpokenPCM().resampled(to: 44_100).isEmpty)
    }

    @Test("Every tone becomes a playable buffer of its own length")
    func toneBuffers() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: Double(ToneSynth.sampleRate), channels: 1))
        for tone in CueTone.allCases {
            let samples = ToneSynth.samples(for: tone).map { Float($0) / Float(Int16.max) }
            let buffer = try #require(CueAudio.buffer(samples, format: format))
            #expect(Int(buffer.frameLength) == samples.count)
            #expect(abs(Double(buffer.frameLength) / format.sampleRate - ToneSynth.duration(of: tone)) < 0.01)
        }
        #expect(CueAudio.buffer([], format: format) == nil)
    }

    @Test("The watchdog backs off while the audio won't start: 1, 5, then 15 seconds")
    func watchdogBacksOff() {
        #expect(CueAudio.watchdogDelay(afterFailures: 0) == 1)
        #expect(CueAudio.watchdogDelay(afterFailures: 1) == 5)
        #expect(CueAudio.watchdogDelay(afterFailures: 2) == 15)
        #expect(CueAudio.watchdogDelay(afterFailures: 40) == 15)
        #expect(CueAudio.watchdogDelay(afterFailures: -1) == 1)
    }

    @Test("Cues away from the app are counted, the first to play picked out, and summed up once")
    func awayTally() {
        var tally = CueTally()
        let empty = tally.close()
        #expect(empty == nil, "Nothing away, nothing to say")
        let firsts = [tally.count(played: true), tally.count(played: true), tally.count(played: false)]
        #expect(firsts == [true, false, false], "Only the first to play is noted in full")
        let summary = tally.close()
        #expect(summary == "Cues away from the app: 2 played, 1 didn't")
        let again = tally.close()
        #expect(again == nil, "Started again")
        let next = tally.count(played: true)
        #expect(next, "A new stretch has its own first")
    }

    @Test("The audio reports whether cues can sound at every hold, not only when it changes")
    @MainActor
    func reportsEveryHold() {
        let audio = CueAudio()
        var reports: [Bool] = []
        audio.onHealthReport = { reports.append($0) }
        audio.holdForRun()
        audio.holdForRun()
        #expect(reports.count == 2)
        #expect(reports.allSatisfy { $0 == reports.first })
        audio.handBackAudio()
        audio.holdForRun()
        #expect(reports.count == 3)
        audio.handBackAudio()
    }
}

@Suite("Motion")
struct MotionTests {
    @Test("Reduce Motion turns every added animation off, and leaves it otherwise")
    func reduceMotion() {
        #expect(AppMotion.animation(.snappy, reduceMotion: true) == nil)
        #expect(AppMotion.animation(.snappy, reduceMotion: false) == .snappy)
    }

    @Test("Which hint the run screen shows: the volume first, the tip only while getting ready")
    func hints() {
        #expect(RunScreenLayout.hint(volumeLow: true, tipSeen: false, mirroring: false, kind: .prepare) == .volumeLow)
        #expect(RunScreenLayout.hint(volumeLow: false, tipSeen: false, mirroring: false, kind: .prepare) == .setVolume)
        #expect(RunScreenLayout.hint(volumeLow: false, tipSeen: true, mirroring: false, kind: .prepare) == nil)
        #expect(RunScreenLayout.hint(volumeLow: false, tipSeen: false, mirroring: true, kind: .prepare) == nil)
        #expect(RunScreenLayout.hint(volumeLow: false, tipSeen: false, mirroring: false, kind: .work) == nil)
    }

    @Test("The Health line is one line that changes: saving, saved, couldn't, or nothing")
    func healthLine() {
        #expect(HealthSaveLine(.notRecorded, onWatch: false) == nil)
        #expect(HealthSaveLine(.saving, onWatch: false)?.symbol == "heart")
        #expect(HealthSaveLine(.saving, onWatch: true)?.text == "Your watch is saving it to Health")
        let saved = HealthSaveLine(.saved, onWatch: false)
        #expect(saved?.text == "Saved to Health" && saved?.symbol == "heart.fill" && saved?.isDone == true)
        #expect(HealthSaveLine(.failed, onWatch: false)?.symbol == "heart.slash")
    }
}

@Suite("Live metrics")
struct LiveMetricTests {
    @Test("Heart rate shows once Health has a reading, rounded, and says itself in words")
    func heartRate() {
        #expect(LiveMetric.heartRate(nil) == nil)
        #expect(LiveMetric.heartRate(0) == nil)
        let metric = LiveMetric.heartRate(142.6)
        #expect(metric?.value == "143" && metric?.unit == "BPM")
        #expect(metric?.spoken == "Heart rate 143 beats per minute")
    }

    @Test("Calories show from the first whole one, counted down, never up")
    func calories() {
        #expect(LiveMetric.calories(nil) == nil)
        #expect(LiveMetric.calories(0.6) == nil)
        #expect(LiveMetric.calories(37.9)?.value == "37")
        #expect(LiveMetric.calories(37.9)?.spoken == "37 active calories")
    }
}
