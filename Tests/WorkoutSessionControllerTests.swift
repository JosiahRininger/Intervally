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

/// What the controller noted, and how often it reported the session ending unasked.
private final class Observed {
    var notes: [String] = []
    var unexpectedEnds = 0
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
}
