//
//  CueAudioTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

@Suite("Cue audio")
@MainActor
struct CueAudioTests {
    /// The audio's notes, kept nowhere.
    private let log = RunDiagnostics(url: nil, write: { _, _ in }, schedule: { _, _ in })

    /// Called as the interruption notification would call it: a test that posted the real
    /// notification would interrupt every other test's audio too.
    @Test("An interruption that begins says at once that the cues can't sound, while a run holds the audio")
    func interruptionBeganReportsUnhealthy() {
        let audio = CueAudio(diagnostics: log)
        var reports: [Bool] = []
        audio.onHealthReport = { reports.append($0) }

        audio.interrupted(began: true)
        #expect(reports.isEmpty, "Nothing holds the audio: no run to tell")

        audio.holdForRun()
        #expect(reports.count == 1, "The hold says how it went")
        let held = reports.first
        audio.interrupted(began: true)
        #expect(reports.count == 2)
        #expect(reports.last == false, "Not at the next cue that fails: the run marks its changes with notifications from now")

        // Its end takes the audio again, and says how that went, as the hold did.
        audio.interrupted(began: false)
        #expect(reports.count == 3)
        #expect(reports.last == held)

        audio.handBackAudio()
        audio.interrupted(began: true)
        #expect(reports.count == 3, "Handed back: nobody to tell")
    }
}
