//
//  RunActivityIntents+Phone.swift
//  IntervallyPhone
//

import AppIntents

// The Live Activity's buttons as the system runs them: here, in the app, beside the run. Each
// asks for what its button showed, and `PhoneRun.control(_:)` does it only if the run still
// stands that way.

extension PauseRunIntent {
    var command: RunMirrorCommand { .pause }

    @MainActor
    func perform() async throws -> some IntentResult {
        await PhoneServices.live?.run.control(command)
        return .result()
    }
}

extension ResumeRunIntent {
    var command: RunMirrorCommand { .resume }

    @MainActor
    func perform() async throws -> some IntentResult {
        await PhoneServices.live?.run.control(command)
        return .result()
    }
}

extension SkipIntervalIntent {
    var command: RunMirrorCommand { .skip(phase: phaseIndex) }

    @MainActor
    func perform() async throws -> some IntentResult {
        await PhoneServices.live?.run.control(command)
        return .result()
    }
}
