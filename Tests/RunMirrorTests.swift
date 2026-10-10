//
//  RunMirrorTests.swift
//  IntervallyTests
//

import Foundation
import Testing
@testable import Intervally

/// The watch's side of the mirror: what it sends the iPhone, and what the iPhone's buttons do.
@Suite("Run mirror — watch")
@MainActor
struct RunMirrorTests {
    private func settle(_ coordinator: RunCoordinator) async {
        for _ in 0..<6 {
            for _ in 0..<8 { await Task.yield() }
            await coordinator.backstopSettled()
        }
    }

    @Test("Messages survive the trip both ways")
    func roundTrip() throws {
        let state = RunMirrorState(
            workout: IntervalWorkout(name: "Tabata", workSeconds: 20, restSeconds: 10, rounds: 8),
            status: .paused, anchor: nil, pausedElapsed: 42.5, health: .saving
        )
        for message in [RunMirrorMessage.state(state), .command(.skip(phase: 3)), .command(.pause), .command(.refresh)] {
            let data = try #require(message.encoded())
            #expect(RunMirrorMessage.decoded(data) == message)
        }
        #expect(RunMirrorMessage.decoded(Data("nonsense".utf8)) == nil)
    }

    @Test("The state carries the anchor while running and how far in while paused")
    func stateFromEngine() {
        let engine = TimerEngine(workout: IntervalWorkout(name: "Run", workSeconds: 30, restSeconds: 15, rounds: 4))
        #expect(RunMirrorState(engine: engine, health: nil).status == .stopped)

        let start = Date(timeIntervalSince1970: 1_000)
        engine.now = { start }
        _ = engine.start()
        let running = RunMirrorState(engine: engine, health: nil)
        #expect(running.status == .running)
        #expect(running.anchor == engine.anchor)
        #expect(running.pausedElapsed == nil)

        engine.now = { start.addingTimeInterval(12) }
        _ = engine.pause()
        let paused = RunMirrorState(engine: engine, health: nil)
        #expect(paused.status == .paused)
        #expect(paused.anchor == nil)
        #expect(paused.pausedElapsed == 12)
    }

    @Test("Each change of shape goes to the iPhone, and its buttons drive the watch's run")
    func remoteCommands() async throws {
        let session = FakeWorkoutSession()
        let (coordinator, _, _, _, _, _, _) = makeCoordinator(workout: session)
        coordinator.begin()
        await settle(coordinator)
        #expect(session.mirrored.last?.status == .running)

        session.onRemoteCommand?(.pause)
        #expect(coordinator.engine.status == .paused)
        #expect(session.mirrored.last?.status == .paused)
        session.onRemoteCommand?(.pause)
        #expect(coordinator.engine.status == .paused, "A second Pause, sent before the first was seen, doesn't resume")

        session.onRemoteCommand?(.resume)
        #expect(coordinator.engine.status == .running)
        session.onRemoteCommand?(.resume)
        #expect(coordinator.engine.status == .running, "Nor does a second Resume pause")

        let phase = try #require(coordinator.engine.position.phaseIndex)
        session.onRemoteCommand?(.skip(phase: phase))
        #expect(coordinator.engine.position.phaseIndex == phase + 1)
        session.onRemoteCommand?(.skip(phase: phase))
        #expect(coordinator.engine.position.phaseIndex == phase + 1, "A skip of an interval already over skips nothing more")

        let sent = session.mirrored.count
        session.onRemoteCommand?(.refresh)
        #expect(session.mirrored.count == sent + 1)

        session.onRemoteCommand?(.end)
        #expect(coordinator.engine.status == .idle)
        #expect(coordinator.endedRemotely == 1)
        #expect(session.mirrored.last?.status == .stopped)
        #expect(session.discardCount == 1)

        // A late End after the run is gone does nothing.
        session.onRemoteCommand?(.end)
        #expect(coordinator.endedRemotely == 1)
    }

    @Test("A finished run tells the iPhone its Health save is under way")
    func finishMirrorsHealth() async {
        let session = FakeWorkoutSession()
        session.endGate = Gate()
        let (coordinator, _, _, _, _, _, _) = makeCoordinator(workout: session)
        coordinator.begin()
        await settle(coordinator)
        let end = Date().addingTimeInterval(coordinator.engine.plan.totalDuration + 1)
        coordinator.engine.now = { end }
        coordinator.advance()
        #expect(session.mirrored.last?.status == .finished)
        #expect(session.mirrored.last?.health == .saving)
        session.endGate?.open()
    }
}
