//
//  WorkoutSessionControllerTests.swift
//  IntervallyTests
//

import Foundation
import HealthKit
import Testing
@testable import Intervally

/// Whether a finished save counts as reaching Health. `finishWorkout()` has been seen to return
/// no workout and no error on a locked iPhone, and the summary said Saved to Health for it.
@Suite("Workout session: what a Health save comes to")
struct WorkoutSaveOutcomeTests {

    private struct SaveFailed: Error {}

    @Test("No workout back, even with no error, is not a save")
    func saveOutcomeNilWorkoutIsFailure() {
        #expect(WorkoutSessionController.saveOutcome(workout: nil, error: nil) == false)
    }

    @Test("An error is not a save, even with a workout back")
    func saveOutcomeErrorIsFailure() {
        #expect(WorkoutSessionController.saveOutcome(workout: nil, error: SaveFailed()) == false)
        #expect(WorkoutSessionController.saveOutcome(workout: NSObject(), error: SaveFailed()) == false)
    }

    @Test("A workout back with no error is a save")
    func saveOutcomeWorkoutIsSuccess() {
        #expect(WorkoutSessionController.saveOutcome(workout: NSObject(), error: nil))
    }
}

/// What the controller noted, how often it reported the session ending unasked, and the
/// commands from the iPhone it passed on.
private final class Observed {
    var notes: [String] = []
    var unexpectedEnds = 0
    var commands: [RunMirrorCommand] = []
}

/// The step `performEnd` hands every finished save to, so the summary and the shareable log
/// both say a save that came back empty didn't reach Health.
@Suite("Workout session: what a finished save notes")
@MainActor
struct WorkoutSaveResultTests {

    private struct SaveFailed: Error {}

    private func makeController() -> (WorkoutSessionController, Observed) {
        let controller = WorkoutSessionController()
        let observed = Observed()
        controller.diagnostics = { [observed] in observed.notes.append($0) }
        return (controller, observed)
    }

    @Test("No workout back is not a save, and the log says finishWorkout returned nil")
    func nilWorkoutIsNotedAndFails() {
        let (controller, observed) = makeController()
        #expect(controller.saveResult(workout: nil, error: nil) == false)
        #expect(observed.notes == ["Health save: finishWorkout returned nil"])
    }

    @Test("A failed save is not a save, and the log says it failed")
    func errorIsNotedAndFails() {
        let (controller, observed) = makeController()
        #expect(controller.saveResult(workout: nil, error: SaveFailed()) == false)
        #expect(observed.notes.count == 1)
        #expect(observed.notes.first?.hasPrefix("Health save failed: ") == true)
    }

    @Test("A workout back is a save, with nothing to note")
    func workoutIsASave() {
        let (controller, observed) = makeController()
        #expect(controller.saveResult(workout: NSObject(), error: nil))
        #expect(observed.notes.isEmpty)
    }
}

/// Callbacks that land after their session was let go of. HealthKit calls the delegate on a
/// queue of its own, so one from a session that ended, was discarded or failed to start can
/// arrive once a newer session is running, and it used to tear that one down. The bodies take
/// identities, so plain objects stand in for HealthKit's here.
@Suite("Workout session: callbacks from an earlier session")
@MainActor
struct WorkoutSessionIdentityTests {

    private struct SessionFailed: Error {}

    /// The session and builder held now, and a pair let go of earlier. Alive for the whole test,
    /// so neither identity can be taken by another object.
    private let current = (session: NSObject(), builder: NSObject())
    private let earlier = (session: NSObject(), builder: NSObject())

    /// A controller holding `current`, which is running.
    private func makeController() -> (WorkoutSessionController, Observed) {
        let controller = WorkoutSessionController()
        let observed = Observed()
        controller.diagnostics = { [observed] in observed.notes.append($0) }
        controller.onUnexpectedEnd = { [observed] in observed.unexpectedEnds += 1 }
        controller.onRemoteCommand = { [observed] in observed.commands.append($0) }
        controller.sessionIdentity = ObjectIdentifier(current.session)
        controller.builderIdentity = ObjectIdentifier(current.builder)
        controller.sessionDidChange(ObjectIdentifier(current.session), to: .running)
        return (controller, observed)
    }

    @Test("An earlier session's end leaves the session held now running")
    func staleSessionEndedIsIgnored() {
        let (controller, observed) = makeController()

        controller.sessionDidChange(ObjectIdentifier(earlier.session), to: .ended)
        #expect(observed.unexpectedEnds == 0)
        #expect(controller.isRunning)
        #expect(controller.sessionIdentity == ObjectIdentifier(current.session))
        #expect(observed.notes == ["Session: ignored an earlier session's change to ended"])

        // The system ending the session held now still is an end the run must hear of.
        controller.sessionDidChange(ObjectIdentifier(current.session), to: .ended)
        #expect(observed.unexpectedEnds == 1)
        #expect(controller.isRunning == false)
        #expect(controller.sessionIdentity == nil)
    }

    @Test("An earlier session starting up doesn't mark a paused session running")
    func staleSessionRunningIsIgnored() {
        let (controller, observed) = makeController()
        controller.sessionDidChange(ObjectIdentifier(current.session), to: .paused)
        #expect(controller.isRunning == false)

        controller.sessionDidChange(ObjectIdentifier(earlier.session), to: .running)
        #expect(controller.isRunning == false)
        #expect(observed.notes == ["Session: ignored an earlier session's change to running"])
    }

    @Test("An earlier session's failure leaves the session held now running")
    func staleSessionErrorIsIgnored() {
        let (controller, observed) = makeController()

        controller.sessionDidFail(ObjectIdentifier(earlier.session), with: SessionFailed())
        #expect(observed.unexpectedEnds == 0)
        #expect(controller.isRunning)
        #expect(controller.sessionIdentity == ObjectIdentifier(current.session))
        #expect(observed.notes == ["Session: ignored an earlier session's failure"])

        controller.sessionDidFail(ObjectIdentifier(current.session), with: SessionFailed())
        #expect(observed.unexpectedEnds == 1)
        #expect(controller.isRunning == false)
        #expect(controller.sessionIdentity == nil)
    }

    @Test("An earlier session's heart rate and energy don't show for the session held now")
    func staleBuilderDataIsIgnored() {
        let (controller, observed) = makeController()
        controller.builderDidCollect(ObjectIdentifier(current.builder), heartRate: 128)
        controller.builderDidCollect(ObjectIdentifier(current.builder), activeEnergy: 41)

        controller.builderDidCollect(ObjectIdentifier(earlier.builder), heartRate: 171)
        controller.builderDidCollect(ObjectIdentifier(earlier.builder), activeEnergy: 380)

        #expect(controller.heartRate == 128)
        #expect(controller.activeEnergy == 41)
        #expect(observed.notes == [
            "Session: ignored an earlier session's heart rate",
            "Session: ignored an earlier session's energy",
        ])
    }

    @Test("An earlier session's commands from the iPhone don't reach the run held now")
    func staleRemoteCommandsAreIgnored() {
        let (controller, observed) = makeController()

        controller.sessionDidReceive(ObjectIdentifier(earlier.session), commands: [.end])
        #expect(observed.commands.isEmpty)
        #expect(observed.notes == ["Session: ignored an earlier session's commands from the iPhone"])

        controller.sessionDidReceive(ObjectIdentifier(current.session), commands: [.pause, .resume])
        #expect(observed.commands == [.pause, .resume])
    }
}

/// The wiring the tests above stand in for: holding a real session and builder gives them the
/// identities their own callbacks carry, through the delegate methods HealthKit calls. If it
/// broke, every callback of the session held now would be ignored, and a session the system
/// ended would leave the run on the workout tier with no session.
@Suite("Workout session: a held session's own callbacks")
@MainActor
struct WorkoutSessionDelegateWiringTests {

    private func makeSession() throws -> HKWorkoutSession {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .highIntensityIntervalTraining
        return try HKWorkoutSession(healthStore: HKHealthStore(), configuration: configuration)
    }

    /// Lets the delegate methods' hops to the main actor run.
    private func settle(until done: () -> Bool) async {
        for _ in 0..<200 where !done() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("The held session's end is heard, and an earlier one's is not")
    func heldSessionEndIsHeard() async throws {
        let controller = WorkoutSessionController()
        let observed = Observed()
        controller.diagnostics = { [observed] in observed.notes.append($0) }
        controller.onUnexpectedEnd = { [observed] in observed.unexpectedEnds += 1 }
        controller.onRemoteCommand = { [observed] in observed.commands.append($0) }

        let earlier = try makeSession()
        let session = try makeSession()
        controller.session = session
        controller.builder = session.associatedWorkoutBuilder()
        #expect(controller.sessionIdentity == ObjectIdentifier(session))
        #expect(controller.builderIdentity == ObjectIdentifier(try #require(controller.builder)))

        let end = try #require(RunMirrorMessage.command(.end).encoded())
        controller.workoutSession(session, didReceiveDataFromRemoteWorkoutSession: [end])
        await settle { !observed.commands.isEmpty }
        #expect(observed.commands == [.end])

        controller.workoutSession(earlier, didChangeTo: .ended, from: .running, date: .now)
        await settle { !observed.notes.isEmpty }
        #expect(observed.notes == ["Session: ignored an earlier session's change to ended"])
        #expect(observed.unexpectedEnds == 0)

        controller.workoutSession(session, didChangeTo: .ended, from: .running, date: .now)
        await settle { observed.unexpectedEnds > 0 }
        #expect(observed.unexpectedEnds == 1)
        #expect(controller.sessionIdentity == nil)
        #expect(controller.builderIdentity == nil)
    }
}
