//
//  HistoryStateTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// Stands in for Health: says what a test sets, counts what it is asked, and can hold a read
/// open so a test can act while it is in flight.
actor FakeHistorySource: HistorySource {
    nonisolated let isAvailable: Bool
    private var accessResult: HistoryAccess
    private var result: Result<[RawWorkout], any Error>
    private var holdsNextRead = false
    private var held: [CheckedContinuation<Void, Never>] = []

    private(set) var accessChecks = 0
    private(set) var accessRequests = 0
    private(set) var reads = 0
    var requestFails = false

    struct Failure: Error {}

    init(isAvailable: Bool = true, access: HistoryAccess = .requested, workouts: [RawWorkout] = []) {
        self.isAvailable = isAvailable
        self.accessResult = access
        self.result = .success(workouts)
    }

    func set(access: HistoryAccess) { accessResult = access }
    func set(workouts: [RawWorkout]) { result = .success(workouts) }
    func failReads() { result = .failure(Failure()) }
    func failRequests() { requestFails = true }

    /// The next read waits for `release()`; the ones after it don't.
    func holdNextRead() { holdsNextRead = true }

    func release() {
        held.forEach { $0.resume() }
        held.removeAll()
    }

    func access() -> HistoryAccess {
        accessChecks += 1
        return accessResult
    }

    func requestAccess() throws {
        accessRequests += 1
        if requestFails { throw Failure() }
        if accessResult == .shouldRequest { accessResult = .requested }
    }

    func workouts() async throws -> [RawWorkout] {
        reads += 1
        // What this read answers is decided when it starts, as a query's snapshot is.
        let answer = result
        if holdsNextRead {
            holdsNextRead = false
            await withCheckedContinuation { held.append($0) }
        }
        return try answer.get()
    }
}

/// A one-interval session at `start`, enough for History to list.
func rawSession(_ name: String = "Classic", at start: Date) -> RawWorkout {
    RawWorkout(
        id: UUID(), start: start, duration: 300, presetName: name, plannedRounds: 1,
        activities: [RawWorkout.Activity(phase: "work", round: 1, start: start, duration: 300)]
    )
}

@Suite("History state")
@MainActor
struct HistoryStateTests {

    @Test("Before the first read answers, History is loading")
    func startsLoading() {
        #expect(HistoryModel(source: FakeHistorySource()).state == .loading)
    }

    @Test("No Health on the device: unavailable, and Health is never asked anything")
    func unavailable() async {
        let source = FakeHistorySource(isAvailable: false)
        let history = HistoryModel(source: source)
        await history.appear()
        #expect(history.state == .unavailable)
        #expect(await source.accessChecks == 0)
        #expect(await source.reads == 0)
    }

    @Test("Never asked: Connect Apple Health, and nothing is read before it")
    func shouldRequest() async {
        let source = FakeHistorySource(access: .shouldRequest, workouts: [rawSession(at: .now)])
        let history = HistoryModel(source: source)
        await history.appear()
        #expect(history.state == .needsAccess)
        #expect(await source.reads == 0)
    }

    @Test("Connect asks once, then reads what it allowed")
    func connect() async {
        let source = FakeHistorySource(access: .shouldRequest, workouts: [rawSession(at: .now)])
        let history = HistoryModel(source: source)
        await history.appear()

        await history.connect()
        #expect(await source.accessRequests == 1)
        #expect(history.state == .loaded)
        #expect(history.sessions.count == 1)
        #expect(history.isConnecting == false)
    }

    @Test("A failed request still reads, rather than leaving Connect spinning")
    func connectFailureStillReads() async {
        let source = FakeHistorySource(access: .shouldRequest)
        await source.failRequests()
        let history = HistoryModel(source: source)
        await history.connect()
        #expect(history.state == .needsAccess)
        #expect(history.isConnecting == false)
        #expect(await source.accessChecks == 1)
    }

    @Test("Asked, and nothing saved yet: empty")
    func empty() async {
        let history = HistoryModel(source: FakeHistorySource(access: .requested))
        await history.appear()
        #expect(history.state == .empty)
        #expect(history.sessions.isEmpty)
        #expect(history.weeks.isEmpty)
    }

    @Test("Sessions: loaded, newest first, grouped by week")
    func loaded() async {
        let now = Date()
        let older = rawSession("Tabata", at: now.addingTimeInterval(-30 * 86_400))
        let newer = rawSession("Classic", at: now.addingTimeInterval(-3_600))
        let history = HistoryModel(source: FakeHistorySource(workouts: [older, newer]))
        await history.appear()
        #expect(history.state == .loaded)
        #expect(history.sessions.map(\.title) == ["Classic", "Tabata"])
        #expect(history.weeks.count == 2)
        #expect(history.weeks.first?.sessions.first?.title == "Classic")
    }

    @Test("HealthKit can't say whether it asked: sessions show, and none offers Connect")
    func unknownAccess() async {
        let source = FakeHistorySource(access: .unknown, workouts: [rawSession(at: .now)])
        let history = HistoryModel(source: source)
        await history.appear()
        #expect(history.state == .loaded)

        await source.set(workouts: [])
        await history.refresh()
        #expect(history.state == .needsAccess)
    }

    @Test("A failed first read says so; a failed later read keeps what was shown")
    func failures() async {
        let source = FakeHistorySource()
        await source.failReads()
        let history = HistoryModel(source: source)
        await history.appear()
        #expect(history.state == .failed)

        await source.set(workouts: [rawSession(at: .now)])
        await history.refresh()
        #expect(history.state == .loaded)

        // A locked iPhone hasn't deleted anything.
        await source.failReads()
        await history.refresh()
        #expect(history.state == .loaded)
        #expect(history.sessions.count == 1)
    }

    @Test("A read that answers late can't overwrite a newer one")
    func staleReadDropped() async {
        let source = FakeHistorySource(workouts: [rawSession("Old", at: .now)])
        let history = HistoryModel(source: source)
        await source.holdNextRead()
        let slow = Task { await history.refresh() }
        #expect(await waitFor { await source.reads == 1 })

        await source.set(workouts: [rawSession("New", at: .now)])
        await history.refresh()
        #expect(history.sessions.map(\.title) == ["New"])

        // The first read answers last, with what it saw when it started.
        await source.release()
        await slow.value

        #expect(history.sessions.map(\.title) == ["New"])
    }

    @Test("Coming forward reads again only once History has been opened")
    func foregroundAfterAppear() async {
        let source = FakeHistorySource()
        let history = HistoryModel(source: source)
        await history.handleForeground()
        #expect(await source.accessChecks == 0)
        #expect(history.state == .loading)

        await history.appear()
        await history.handleForeground()
        #expect(await source.reads == 2)
    }

    @Test("The app coming forward re-reads History once it has been shown, and never before")
    func servicesForeground() async {
        let source = FakeHistorySource()
        let defaults = makeTestDefaults()
        let services = PhoneServices(
            store: WorkoutStore(defaults: defaults), pro: ProStore(defaults: defaults),
            history: HistoryModel(source: source)
        )
        await services.handleForeground()
        #expect(await source.reads == 0)

        await services.history.appear()
        await services.handleForeground()
        #expect(await source.reads == 2)
    }

    @Test("The app's own History reads Apple Health")
    func defaultSourceIsHealth() {
        let defaults = makeTestDefaults()
        let services = PhoneServices(store: WorkoutStore(defaults: defaults), pro: ProStore(defaults: defaults))
        #expect(services.history.state == .loading)
        #expect(services.history.hasAppeared == false)
    }
}

/// `waitUntil` for a condition that has to be awaited, such as an actor's count.
@MainActor
private func waitFor(within timeout: Duration = .seconds(5), _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while await !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

@Suite("History messages")
struct HistoryMessageTests {

    @Test("Empty explains where workouts come from and where to check, never implying a denial")
    func emptyNeverImpliesDenial() throws {
        let message = try #require(HistoryMessage(.empty))
        #expect(message.detail.contains("Apple Watch"))
        #expect(message.detail.contains(HistoryMessage.whereToCheck))
        for word in ["denied", "declined", "not allowed", "turned off", "refused", "blocked"] {
            #expect(!message.detail.localizedCaseInsensitiveContains(word))
            #expect(!message.title.localizedCaseInsensitiveContains(word))
        }
    }

    @Test("Every state without sessions has words; the first read and the list don't")
    func everyStateHasWords() {
        for state in [HistoryModel.State.needsAccess, .empty, .unavailable, .failed] {
            #expect(HistoryMessage(state) != nil)
        }
        #expect(HistoryMessage(.loading) == nil)
        #expect(HistoryMessage(.loaded) == nil)
        #expect(HistoryMessage(.needsAccess)?.title == "See every session, interval by interval")
    }

    @Test("Connect promises only to read, and that it stays on the iPhone")
    func connectPromise() throws {
        let detail = try #require(HistoryMessage(.needsAccess)).detail
        #expect(detail.contains("only reads"))
        #expect(detail.contains("stays on this iPhone"))
    }

    /// Settings can open from Workouts before History has ever read Health, and on a fresh
    /// install the row then read as connected. Opening the explainer turned it into "Not
    /// connected".
    @Test("Before History has read Health, Settings' row claims no access either way")
    func settingsSubtitleBeforeFirstRead() {
        let subtitle = HistoryMessage.settingsSubtitle(for: .loading)
        #expect(subtitle == "What History reads")
        for known in [HistoryModel.State.unavailable, .needsAccess, .empty, .loaded, .failed] {
            #expect(subtitle != HistoryMessage.settingsSubtitle(for: known))
        }
    }

    @Test("Settings' Apple Health row says where History stands")
    func settingsSubtitles() {
        #expect(HistoryMessage.settingsSubtitle(for: .unavailable) == "Not available on this device")
        #expect(HistoryMessage.settingsSubtitle(for: .needsAccess) == "Not connected")
        #expect(HistoryMessage.settingsSubtitle(for: .loaded) == "Reads your watch's workouts")
        #expect(HistoryMessage.settingsSubtitle(for: .empty) == "Reads your watch's workouts")
    }
}
