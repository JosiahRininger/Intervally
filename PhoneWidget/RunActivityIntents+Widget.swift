//
//  RunActivityIntents+Widget.swift
//  IntervallyPhoneWidget
//

import AppIntents

// The extension only draws the Live Activity's buttons. The system runs their intents in the
// app (RunActivityIntents+Phone.swift), never here; these are only so that each compiles as
// an intent in the extension too.

extension PauseRunIntent {
    func perform() async throws -> some IntentResult { .result() }
}

extension ResumeRunIntent {
    func perform() async throws -> some IntentResult { .result() }
}

extension SkipIntervalIntent {
    func perform() async throws -> some IntentResult { .result() }
}
