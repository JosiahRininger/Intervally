//
//  RunDiagnosticsTests.swift
//  IntervallyTests
//

import Foundation
import SwiftUI
import Testing
@testable import Intervally

private func tempURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString).json")
}

/// Lets the coordinator's `Task`-based work settle before asserting.
private func settle(_ coordinator: RunCoordinator) async {
    for _ in 0..<6 {
        for _ in 0..<8 { await Task.yield() }
        await coordinator.backstopSettled()
    }
}

/// Counts the log's writes and keeps what each one wrote, whichever thread writes.
private final class WriteSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var written: [Data] = []
    private var threads: [Bool] = []
    private var times: [Date] = []

    var count: Int { lock.withLock { written.count } }
    /// For each write, whether it ran on the main thread.
    var onMain: [Bool] { lock.withLock { threads } }
    /// When each write ran.
    var dates: [Date] { lock.withLock { times } }

    var write: RunDiagnostics.Write {
        { [self] data, _ in
            let main = Thread.isMainThread
            lock.withLock {
                written.append(data)
                threads.append(main)
                times.append(Date())
            }
        }
    }

    /// The entries the latest write held.
    func lastEntries() throws -> [RunDiagnostics.Entry] {
        let data = try #require(lock.withLock { written.last })
        return try JSONDecoder().decode([RunDiagnostics.Entry].self, from: data)
    }
}

/// Holds the writes the log asks for until the test says their two seconds are up.
private final class HeldSchedule: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [@Sendable () -> Void] = []
    private var asked: [TimeInterval] = []

    /// How long each write asked to wait, in order.
    var delays: [TimeInterval] { lock.withLock { asked } }

    var schedule: RunDiagnostics.Schedule {
        { [self] delay, work in
            lock.withLock {
                asked.append(delay)
                waiting.append(work)
            }
        }
    }

    /// Runs every write that is waiting, as if its two seconds had passed.
    func runWaiting() {
        let due = lock.withLock {
            defer { waiting.removeAll() }
            return waiting
        }
        due.forEach { $0() }
    }
}

@Suite("Run diagnostics")
struct RunDiagnosticsTests {

    @Test("Entries survive a relaunch, newest last, and stop at the capacity")
    func keepsAndCaps() {
        let url = tempURL()
        let log = RunDiagnostics(url: url)
        for index in 0..<(RunDiagnostics.capacity + 5) { log.note("entry \(index)") }
        // As the app leaving the screen does.
        log.flush()
        let reopened = RunDiagnostics(url: url)
        #expect(reopened.all.count == RunDiagnostics.capacity)
        #expect(reopened.all.last?.text == "entry \(RunDiagnostics.capacity + 4)")
        #expect(reopened.all.first?.text == "entry 5")
        reopened.clear()
        #expect(RunDiagnostics(url: url).all.isEmpty)
    }

    @Test("Errors read with their domain and code")
    func describesErrors() {
        let error = NSError(domain: "com.apple.healthkit", code: 4, userInfo: [NSLocalizedDescriptionKey: "Not authorized"])
        #expect(RunDiagnostics.describe(error) == "com.apple.healthkit 4: Not authorized")
    }

    @Test("The same line again, straight after, is counted on one entry, so a flood can't push the rest out")
    func collapsesRepeats() throws {
        let url = tempURL()
        let log = RunDiagnostics(url: url)
        let start = Date(timeIntervalSince1970: 1_000_000)
        log.note("Run: started Tabata", at: start)
        for second in 1...(RunDiagnostics.capacity + 50) {
            log.note("Audio: engine didn't start", at: start.addingTimeInterval(Double(second)))
        }
        log.note("Audio: cues can sound again", at: start.addingTimeInterval(1_000))
        log.flush()
        let entries = RunDiagnostics(url: url).all
        #expect(entries.map(\.text) == ["Run: started Tabata", "Audio: engine didn't start", "Audio: cues can sound again"])
        #expect(entries[1].repeats == RunDiagnostics.capacity + 49)
        #expect(entries[1].lastDate == start.addingTimeInterval(Double(RunDiagnostics.capacity + 50)))
        #expect(log.text.contains("\(RunDiagnostics.capacity + 50) times, until"))
        log.clear()
    }

    @Test("A log saved before repeats were counted still opens")
    func readsOldEntries() throws {
        let url = tempURL()
        try Data(#"[{"date":0,"text":"Run: started Tabata"}]"#.utf8).write(to: url)
        let entries = RunDiagnostics(url: url).all
        #expect(entries.map(\.text) == ["Run: started Tabata"])
        #expect(entries.first?.repeats == 0)
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Shared text is one line per entry")
    func text() {
        let log = RunDiagnostics(url: nil)
        log.note("one")
        log.note("two")
        #expect(log.text.split(separator: "\n").count == 2)
        #expect(log.text.hasSuffix("two"))
    }

    @Test("Ten notes in a moment go out in one write, two seconds after the first, and none as they're noted")
    func notesCoalesceIntoOneWrite() throws {
        let writes = WriteSpy()
        let later = HeldSchedule()
        let log = RunDiagnostics(url: tempURL(), write: writes.write, schedule: later.schedule)

        for index in 1...10 { log.note("note \(index)") }
        #expect(writes.count == 0, "Nothing written as they're noted")
        #expect(later.delays == [2], "One write asked for, two seconds on")

        later.runWaiting()
        #expect(writes.count == 1)
        #expect(try writes.lastEntries().map(\.text) == (1...10).map { "note \($0)" })

        // The first note after that write asks for the next one.
        log.note("note 11")
        #expect(later.delays == [2, 2])
        later.runWaiting()
        #expect(writes.count == 2)
        #expect(try writes.lastEntries().count == 11)
    }

    @Test("A flush writes at once; the write already asked for then takes only what came after, if anything")
    func flushWritesAtOnce() throws {
        let writes = WriteSpy()
        let later = HeldSchedule()
        let log = RunDiagnostics(url: tempURL(), write: writes.write, schedule: later.schedule)

        log.note("one")
        log.flush()
        #expect(writes.count == 1, "On the spot")
        later.runWaiting()
        #expect(writes.count == 1, "Nothing new to write")

        log.note("two")
        log.flush()
        log.note("three")
        #expect(later.delays.count == 2, "\"three\" waits on the write \"two\" asked for")
        later.runWaiting()
        #expect(writes.count == 3)
        #expect(try writes.lastEntries().map(\.text) == ["one", "two", "three"])
        log.flush()
        #expect(writes.count == 3, "Nothing left to write")
    }

    @Test("Left to itself, the write goes out on a background queue")
    func waitingWriteRunsInTheBackground() async {
        let onMain = await withCheckedContinuation { continuation in
            RunDiagnostics.inBackground(0.01) { continuation.resume(returning: Thread.isMainThread) }
        }
        #expect(onMain == false)
    }

    @Test("By default a note made on the main thread is written two seconds on, off it")
    @MainActor
    func defaultScheduleWaitsTwoSecondsOffTheMainThread() async throws {
        #expect(RunDiagnostics.writeDelay == 2)
        let writes = WriteSpy()
        let log = RunDiagnostics(url: tempURL(), write: writes.write)
        let noted = Date()
        log.note("Run: started Tabata")
        #expect(writes.count == 0, "Not as it's noted")

        let deadline = Date().addingTimeInterval(10)
        while writes.count == 0, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(writes.count == 1)
        #expect(writes.onMain == [false])
        let waited = try #require(writes.dates.first).timeIntervalSince(noted)
        #expect(waited >= 1.9, "Written \(waited) s on, not two")
        #expect(try writes.lastEntries().map(\.text) == ["Run: started Tabata"])
    }

    @Test("A flush in the background goes to the queue at once, and only with something to write")
    func flushInBackgroundLeavesTheCallingThread() throws {
        let writes = WriteSpy()
        let later = HeldSchedule()
        let log = RunDiagnostics(url: tempURL(), write: writes.write, schedule: later.schedule)

        log.flushInBackground()
        #expect(later.delays.isEmpty, "Nothing noted, nothing to write")

        log.note("one")
        log.flushInBackground()
        #expect(writes.count == 0, "Not on the calling thread")
        #expect(later.delays == [2, 0], "Straight away, alongside the write the note asked for")
        later.runWaiting()
        #expect(writes.count == 1, "The second finds nothing left to write")
        #expect(try writes.lastEntries().map(\.text) == ["one"])
    }

    @Test("Going to the background writes at once; going inactive, the watch's wrist-down, hands the write to the queue")
    func sceneChangesWrite() throws {
        let writes = WriteSpy()
        let later = HeldSchedule()
        let log = RunDiagnostics(url: tempURL(), write: writes.write, schedule: later.schedule)

        // A wrist raise during a run notes the app coming forward; lowering it again must not
        // write on the main thread.
        log.note("App: in front")
        log.sceneChanged(to: .inactive)
        #expect(writes.count == 0, "Inactive writes nothing on the calling thread")
        #expect(later.delays == [2, 0], "It goes to the background queue straight away")
        log.sceneChanged(to: .active)
        #expect(later.delays == [2, 0], "Coming forward asks for nothing more")
        later.runWaiting()
        #expect(writes.count == 1)

        log.note("App: left")
        log.sceneChanged(to: .background)
        #expect(writes.count == 2, "In the background it's written there and then")
        #expect(try writes.lastEntries().last?.text == "App: left")
        log.sceneChanged(to: .background)
        #expect(writes.count == 2, "Nothing new, no write")
    }
}

/// A wall clock the test sets by hand.
@MainActor
private final class HandClock {
    var now = Date(timeIntervalSinceReferenceDate: 1_000_000)
}

@Suite("Run coordinator — writing the diagnostics")
@MainActor
struct RunDiagnosticsWritingTests {

    let time = VirtualTime()
    private let writes = WriteSpy()
    private let later = HeldSchedule()

    /// A coordinator whose notes go to a log of their own, its writes counted, and whose
    /// ticker sleeps on a clock nothing moves, so only the test advances the run.
    private func makeNoting() -> (RunCoordinator, WorkoutStore, RunDiagnostics, FakeWorkoutSession) {
        let log = RunDiagnostics(url: tempURL(), write: writes.write, schedule: later.schedule)
        let (coordinator, store, workout, _, _, _, _) = makeCoordinator()
        coordinator.diagnostics = { log.note($0) }
        coordinator.flushDiagnostics = { log.flush() }
        coordinator.tickSleep = { [time] in try await time.sleep(for: .seconds($0)) }
        return (coordinator, store, log, workout)
    }

    /// A one-round, five-second run, begun and run to its finish.
    private func finishShortRun(_ coordinator: RunCoordinator, _ store: WorkoutStore) async throws {
        var short = store.selected
        short.prepareSeconds = 0
        short.workSeconds = 5
        short.restSeconds = 0
        short.rounds = 1
        store.update(short)

        coordinator.begin()
        await settle(coordinator)
        #expect(writes.count == 0, "The run's first notes wait two seconds for company")

        let anchor = try #require(coordinator.engine.anchor)
        coordinator.engine.now = { anchor.addingTimeInterval(5.25) }
        coordinator.advance()
        #expect(coordinator.engine.status == .finished)
    }

    @Test("A finished run's notes are written as it finishes, and the save's once it's over, not left for a write that may never come")
    func finishFlushesImmediately() async throws {
        let (coordinator, store, log, workout) = makeNoting()
        let saving = Gate()
        workout.endGate = saving
        try await finishShortRun(coordinator, store)
        #expect(writes.count == 1, "Written as the run finished")
        let written = try writes.lastEntries().map(\.text)
        #expect(written.contains { $0.hasPrefix("Run: started") })
        #expect(written.contains { $0.hasPrefix("Run timing:") }, "The run's timing line among them")

        // What the session notes as it ends and saves comes after that write.
        log.note("Session: running → ended")
        saving.open()
        await settle(coordinator)
        #expect(writes.count == 2, "Written once the save is over, not two seconds on")
        #expect(try writes.lastEntries().last?.text == "Session: running → ended")
        coordinator.stopAndExit()
    }

    @Test("Done on a finished run writes what the Health save noted once the save is over")
    func doneAfterFinishFlushesAfterTheSave() async throws {
        let (coordinator, store, log, workout) = makeNoting()
        try await finishShortRun(coordinator, store)
        await settle(coordinator)

        let saving = Gate()
        workout.endGate = saving
        coordinator.stopAndExit()
        let ended = writes.count
        log.note("Session: running → ended")
        saving.open()
        await settle(coordinator)
        #expect(writes.count == ended + 1, "Written once the save is over, not two seconds on")
        #expect(try writes.lastEntries().last?.text == "Session: running → ended")
    }

    @Test("Ending a run writes its notes at once too")
    func endFlushesImmediately() async throws {
        let (coordinator, _, _, _) = makeNoting()
        coordinator.begin()
        await settle(coordinator)
        #expect(writes.count == 0)

        coordinator.stopAndExit()
        #expect(writes.count == 1, "Written as the run ended")
        #expect(try writes.lastEntries().contains { $0.text.hasPrefix("Run: started") })
    }

    @Test("With no run under way, coming to the front is noted once a minute at most; during a run, every time")
    func idleForegroundWritesAtMostOncePerMinute() async {
        let (coordinator, _, log, _) = makeNoting()
        let clock = HandClock()
        coordinator.engine.now = { clock.now }
        let start = clock.now

        // The watch comes to the front at every wrist raise: here every ten seconds for two
        // and a half minutes with nothing running, each write given its two seconds.
        for second in stride(from: 0.0, through: 150, by: 10) {
            clock.now = start.addingTimeInterval(second)
            coordinator.handleForeground()
            later.runWaiting()
        }
        #expect(writes.count == 3, "Noted at 0, 70 and 140 s, each more than a minute after the last")
        #expect(log.all.filter { $0.text.hasPrefix("App: in front") }.map(\.repeats) == [2], "One line, three times")

        // During a run each one is noted, as it says what keeps the run going.
        coordinator.begin()
        await settle(coordinator)
        later.runWaiting()
        let written = writes.count
        for second in stride(from: 160.0, through: 180, by: 10) {
            clock.now = start.addingTimeInterval(second)
            coordinator.handleForeground()
            later.runWaiting()
        }
        #expect(coordinator.engine.status == .running)
        #expect(writes.count == written + 3)
        coordinator.stopAndExit()
    }
}
