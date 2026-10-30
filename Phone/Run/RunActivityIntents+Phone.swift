//
//  RunActivityIntents+Phone.swift
//  IntervallyPhone
//

import AppIntents

// The Live Activity's buttons as the system runs them: here, in the app, beside the run. Each
// asks for what its button showed, and `PhoneRun.control(_:)` does it only if the run still
// stands that way.

/// One of the Live Activity's buttons, in the app.
protocol RunActivityButtonIntent {
    /// What the button asks of the run.
    var command: RunMirrorCommand { get }
}

extension RunActivityButtonIntent {
    /// The whole of a tap, against `run`: the app's own in `perform()`, a test's in the tests.
    /// It returns only once the run has taken it, as iOS can suspend the app once it does.
    @MainActor
    @discardableResult
    func perform(on run: PhoneRun?) async -> some IntentResult {
        await run?.control(command)
        return .result()
    }
}

extension PauseRunIntent: RunActivityButtonIntent {
    var command: RunMirrorCommand { .pause }

    @MainActor
    func perform() async throws -> some IntentResult {
        await perform(on: PhoneServices.live?.run)
    }
}

extension ResumeRunIntent: RunActivityButtonIntent {
    var command: RunMirrorCommand { .resume }

    @MainActor
    func perform() async throws -> some IntentResult {
        await perform(on: PhoneServices.live?.run)
    }
}

extension SkipIntervalIntent: RunActivityButtonIntent {
    var command: RunMirrorCommand { .skip(phase: phaseIndex) }

    @MainActor
    func perform() async throws -> some IntentResult {
        await perform(on: PhoneServices.live?.run)
    }
}
