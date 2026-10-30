//
//  PhoneQATests.swift
//  IntervallyPhoneTests
//

#if DEBUG
import Foundation
import Testing
@testable import IntervallyPhone

/// The iPhone's QA launch flags: read exactly, and a stand-in watch that never sends.
@Suite("iPhone QA flags")
@MainActor
struct PhoneQATests {

    @Test("Each flag is read from its value")
    func parse() {
        let options = PhoneQAOptions.parse([
            "IntervallyPhone", "-qaPro", "pro", "-qaWatch", "notInstalled", "-qaOpen", "editor", "-qaWelcome", "YES",
        ])
        #expect(options == PhoneQAOptions(pro: true, watch: .notInstalled, welcome: true, screen: .editor))
    }

    @Test("A run in progress, for screenshots: seconds since it started, never negative")
    func runElapsed() {
        #expect(PhoneQAOptions.parse(["-qaRunElapsed", "95"]).runElapsed == 95)
        #expect(PhoneQAOptions.parse(["-qaRunElapsed", "-5"]).runElapsed == nil, "Reads as a flag")
        #expect(PhoneQAOptions.parse(["-qaRunElapsed", "soon"]).runElapsed == nil)
        #expect(PhoneQAOptions.parse(["-qaWatchRun", "paused"]).watchRun == .paused)
        #expect(PhoneQAOptions.parse(["-qaWatchRun", "stopped"]).watchRun == nil, "Nothing to show")
        #expect(PhoneQAOptions.parse(["-qaWatchRun", "paused"]).isActive)
    }

    @Test("No flags, no overrides")
    func none() {
        #expect(PhoneQAOptions.parse(["IntervallyPhone"]) == PhoneQAOptions())
    }

    @Test("A typo is ignored rather than guessed at")
    func typos() {
        let options = PhoneQAOptions.parse(["-qaPro", "Pr0", "-qaWatch", "paired", "-qaOpen", "everything"])
        #expect(options == PhoneQAOptions())
        #expect(PhoneQAOptions.proOverride(" FREE ") == false)
        #expect(PhoneQAOptions.proOverride("pro") == true)
    }

    @Test("A flag with no value takes none, and never the next flag's")
    func missingValues() {
        #expect(PhoneQAOptions.parse(["-qaPro", "-qaWatch", "unpaired"]) == PhoneQAOptions(watch: .unpaired))
        #expect(PhoneQAOptions.parse(["-qaWelcome"]).welcome)
        #expect(PhoneQAOptions.parse(["-qaWelcome", "-qaPro", "free"]) == PhoneQAOptions(pro: false, welcome: true))
        #expect(PhoneQAOptions.parse(["-qaWelcome", "NO"]).welcome == false)
    }

    @Test("Each stand-in watch reports its state", arguments: [
        (QAWatchState.unsupported, PeerState.unsupported),
        (.unpaired, .notPaired),
        (.notInstalled, .appNotInstalled),
        (.installed, .ready),
        (.firstSync, .ready),
    ])
    func states(state: QAWatchState, peer: PeerState) {
        #expect(PeerState(state.snapshot) == peer)
    }

    @Test("A set-up stand-in has synced, so Last Synced has something to say")
    func installedHasSynced() {
        let store = WorkoutStore(defaults: makeTestDefaults())
        let sync = WatchSync(store: store, transport: QAWatchTransport(state: .installed, store: store))
        sync.activate()
        #expect(sync.lastReceivedAt.map { Date().timeIntervalSince($0) > 200 } == true)
        #expect(sync.lastSentAt == nil, "The stand-in already holds this iPhone's presets")
        #expect(WorkoutsContent.showsWatchHint(peer: sync.peer, lastReceivedAt: sync.lastReceivedAt) == false)
    }

    @Test("A first-sync stand-in has heard nothing yet: the hint shows")
    func firstSyncShowsTheHint() {
        let store = WorkoutStore(defaults: makeTestDefaults())
        let transport = QAWatchTransport(state: .firstSync, store: store)
        let sync = WatchSync(store: store, transport: transport)
        sync.activate()
        #expect(sync.lastReceivedAt == nil)
        #expect(WorkoutsContent.showsWatchHint(peer: sync.peer, lastReceivedAt: sync.lastReceivedAt))
        // What was "sent" stayed in the stand-in.
        #expect(SyncWire.document(from: transport.applicationContext) == store.document)
    }

    @Test("Without a watch the stand-in isn't even activated")
    func unsupportedNeverActivates() {
        let store = WorkoutStore(defaults: makeTestDefaults())
        let sync = WatchSync(store: store, transport: QAWatchTransport(state: .unsupported, store: store))
        sync.activate()
        #expect(sync.isActive == false)
        #expect(sync.peer == .unsupported)
    }

    @Test("QA edits reach the warmup and cooldown, for the Pro screenshots")
    func bookendEdits() throws {
        let edits = try #require(QAEdit.parse("warmup 0 300; cooldown 0 120"))
        #expect(edits == [.warmup(0, 300), .cooldown(0, 120)])
        let store = WorkoutStore(defaults: makeTestDefaults())
        edits.forEach { $0.apply(to: store) }
        #expect(store.workouts[0].warmupSeconds == 300)
        #expect(store.workouts[0].cooldownSeconds == 120)
    }

    @Test("Every screen -qaOpen names can be parsed back")
    func screens() {
        for screen in QAScreen.allCases {
            #expect(PhoneQAOptions.parse(["-qaOpen", screen.rawValue]).screen == screen)
        }
    }

    // MARK: - Fresh launches

    @Test("-qaDefaults fresh starts clean and shows no prompts; keep, a typo or no flag changes nothing")
    func freshDefaults() {
        let fresh = PhoneQAOptions.parse(["-qaDefaults", "fresh"])
        #expect(fresh.defaults == .fresh)
        #expect(fresh.suppressesPrompts)
        #expect(fresh.runsOnStandIns, "Its runs ask for neither notifications nor Health")
        #expect(fresh.isActive)

        let keep = PhoneQAOptions.parse(["-qaDefaults", "keep"])
        #expect(keep.defaults == .keep)
        #expect(keep.suppressesPrompts == false)
        #expect(keep.runsOnStandIns == false)
        #expect(keep.isActive)

        #expect(PhoneQAOptions.parse(["-qaDefaults", "wipe"]) == PhoneQAOptions())
        #expect(PhoneQAOptions.parse(["-qaDefaults", "-qaPro", "pro"]) == PhoneQAOptions(pro: true))
        #expect(PhoneQAOptions.parse(["IntervallyPhone"]).suppressesPrompts == false)
    }

    @Test("-qaAllowPrompts lets a fresh launch ask, on the real session and backstop")
    func allowPrompts() {
        let allowing = PhoneQAOptions.parse(["-qaDefaults", "fresh", "-qaAllowPrompts", "YES"])
        #expect(allowing.allowPrompts)
        #expect(allowing.suppressesPrompts == false)
        #expect(allowing.runsOnStandIns == false)
        #expect(PhoneQAOptions.parse(["-qaAllowPrompts", "-qaDefaults", "fresh"]).suppressesPrompts == false, "A bare flag counts")
        // -qaWorkout's figures come from the stand-in, whatever else is asked.
        #expect(PhoneQAOptions.parse(["-qaDefaults", "fresh", "-qaAllowPrompts", "YES", "-qaWorkout", "152,37"]).runsOnStandIns)
    }

    @Test("-qaSkipWelcome is read bare or with a value")
    func skipWelcome() {
        #expect(PhoneQAOptions.parse(["-qaSkipWelcome", "YES"]) == PhoneQAOptions(skipWelcome: true))
        #expect(PhoneQAOptions.parse(["-qaSkipWelcome", "-qaDefaults", "fresh"]) == PhoneQAOptions(defaults: .fresh, skipWelcome: true))
        #expect(PhoneQAOptions.parse(["-qaSkipWelcome", "NO"]).skipWelcome == false)
        #expect(PhoneQAOptions.parse(["-qaSkipWelcome", "YES"]).isActive)
    }

    @Test("A fresh launch clears the defaults and Application Support: the starters, nothing seen, no diagnostics")
    func clearsWhatTheAppKeeps() throws {
        let domain = UUID().uuidString
        let defaults = makeTestDefaults(domain)
        let store = WorkoutStore(defaults: defaults)
        store.add(IntervalWorkout(name: "Left Behind"))
        store.saveActiveRun(RunSnapshot(workout: store.selected, anchor: Date(), pausedElapsed: nil))
        defaults.set(true, forKey: Welcome.seenKey)
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("support-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: support) }
        let diagnosticsURL = support.appendingPathComponent("run-diagnostics.json")
        let diagnostics = RunDiagnostics(url: diagnosticsURL)
        diagnostics.note("Run: started Left Behind")
        // Written now, as the app leaving the screen would, rather than a moment later.
        diagnostics.flush()
        #expect(FileManager.default.fileExists(atPath: diagnosticsURL.path))

        QADefaults.clear(defaults: defaults, domain: domain, suite: defaults, support: support)

        #expect(defaults.object(forKey: Welcome.seenKey) == nil)
        #expect(WorkoutStore.activeRun(in: defaults) == nil)
        #expect(WorkoutStore(defaults: defaults).workouts.map(\.name) == SyncDocument.starterWorkouts.map(\.name))
        #expect(try FileManager.default.contentsOfDirectory(atPath: support.path).isEmpty)
        #expect(RunDiagnostics(url: diagnosticsURL).all.isEmpty)
    }

    @Test("A shared suite of its own is cleared as well")
    func clearsASeparateSuite() {
        let domain = UUID().uuidString
        let defaults = makeTestDefaults(domain)
        let suite = makeTestDefaults()
        defaults.set(true, forKey: Welcome.seenKey)
        WorkoutStore(defaults: suite).add(IntervalWorkout(name: "Left Behind"))
        #expect(suite.data(forKey: WorkoutStore.Key.document) != nil)

        QADefaults.clear(defaults: defaults, domain: domain, suite: suite, support: nil)

        #expect(defaults.object(forKey: Welcome.seenKey) == nil)
        #expect(suite.data(forKey: WorkoutStore.Key.document) == nil)
        #expect(suite.data(forKey: WorkoutStore.Key.workouts) == nil)
    }

    @Test("A fresh launch's stand-in session starts at once, unasked, and reports no figures")
    func standInWithoutFigures() async {
        let session = QAWorkoutSession(figures: nil)
        #expect(await session.requestAuthorization())
        #expect(await session.start(at: Date()))
        #expect(session.isRunning)
        #expect(session.heartRate == nil)
        #expect(session.activeEnergy == nil)
        // Nothing reached Health, so the summary must not say Saved to Health.
        #expect(await session.end(at: Date()) == false)
        #expect(session.isRunning == false)
    }

    @Test("-qaWorkout's stand-in ends saved, for the summary's screenshot")
    func standInWithFigures() async throws {
        let session = QAWorkoutSession(figures: try #require(QAWorkoutFigures("152,37")))
        #expect(await session.start(at: Date()))
        #expect(await session.end(at: Date()))
    }

    /// The services a set of flags launches with, on a test's own defaults and History.
    private func services(_ arguments: [String], health: FakeHistorySource) -> PhoneServices {
        let defaults = makeTestDefaults()
        return PhoneServices.forQA(
            PhoneQAOptions.parse(arguments),
            store: WorkoutStore(defaults: defaults),
            pro: ProStore(defaults: defaults),
            theme: ThemeStore(defaults: defaults),
            health: health
        )
    }

    @Test("A fresh launch is wired to ask for nothing: stand-ins for the run, an unprompted History, the icon left alone")
    func freshServices() async throws {
        let health = FakeHistorySource(access: .shouldRequest)
        let fresh = services(["-qaDefaults", "fresh"], health: health)
        let session = try #require(fresh.run.coordinator.workout as? QAWorkoutSession)
        #expect(session.figures == nil, "No figures, so its runs say nothing was saved")
        #expect(fresh.run.coordinator.notifications is QABackstop)
        #expect(fresh.iconFollowsTheme == false)
        #expect(fresh.qa.suppressesPrompts)

        await fresh.history.connect()
        #expect(await health.accessRequests == 0, "Connect put Health's sheet up")
        #expect(await health.accessChecks == 1, "History still reads Health")
    }

    @Test("Keep, no flag, or -qaAllowPrompts: the real session and backstop, and Connect asks Health", arguments: [
        ["-qaDefaults", "keep"],
        [],
        ["-qaDefaults", "fresh", "-qaAllowPrompts", "YES"],
    ])
    func promptingServices(arguments: [String]) async {
        let health = FakeHistorySource(access: .shouldRequest)
        let launch = services(arguments, health: health)
        #expect(launch.run.coordinator.workout is WorkoutSessionController)
        #expect(launch.run.coordinator.notifications is NotificationScheduler)
        #expect(launch.iconFollowsTheme)

        await launch.history.connect()
        #expect(await health.accessRequests == 1)
    }

    @Test("-qaWorkout runs on its figures, and leaves the icon following the theme")
    func workoutServices() throws {
        let launch = services(["-qaWorkout", "152,37"], health: FakeHistorySource())
        let session = try #require(launch.run.coordinator.workout as? QAWorkoutSession)
        #expect(session.figures == QAWorkoutFigures("152,37"))
        #expect(launch.run.coordinator.notifications is QABackstop)
        #expect(launch.iconFollowsTheme)
    }

    @Test("A History fixture stands in for Health whatever else is asked")
    func fixtureServices() async {
        let health = FakeHistorySource()
        let launch = services(["-qaDefaults", "fresh", "-qaHistory", "sample"], health: health)
        await launch.history.appear()
        #expect(launch.history.state == .loaded)
        #expect(await health.accessChecks == 0)
        #expect(await health.reads == 0)
    }

    @Test("A fresh launch's History reads Health, but Connect never asks it")
    func unpromptedHistory() async {
        let health = FakeHistorySource(access: .shouldRequest)
        let history = HistoryModel(source: QAUnpromptedHistory(source: health))
        await history.appear()
        #expect(history.state == .needsAccess)

        await history.connect()
        #expect(await health.accessRequests == 0)
        #expect(await health.accessChecks == 2, "Read again after Connect, as Health's own would be")
        #expect(history.state == .needsAccess)

        let allowed = FakeHistorySource(workouts: [rawSession(at: Date().addingTimeInterval(-3600))])
        let reading = HistoryModel(source: QAUnpromptedHistory(source: allowed))
        await reading.appear()
        #expect(reading.state == .loaded)
        #expect(reading.sessions.count == 1)
    }
}
#endif
