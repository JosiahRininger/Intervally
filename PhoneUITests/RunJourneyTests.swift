//
//  RunJourneyTests.swift
//  IntervallyPhoneUITests
//

import XCTest

/// A run on this iPhone end to end: started from the library and driven with its controls,
/// or launched seconds from its end to finish on its own. A fresh launch's runs take stand-ins
/// for the workout session and the notifications (`QAWorkoutSession`, `QABackstop`), so no
/// prompt holds the clock and nothing reaches Health.
@MainActor
final class RunJourneyTests: XCTestCase {
    /// Classic, the workout up next on a fresh launch, runs 5:55.
    static let classicSeconds = 355

    func testPauseResumeSkipEndDiscard() throws {
        let app = PhoneApp.launch()
        let start = app.buttons["workouts.start.Tabata"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        let header = app.element("run.header")
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(header.label.hasPrefix("Tabata, "), header.label)
        let pause = app.buttons["run.pauseResume"]
        XCTAssertTrue(pause.wait(until: "isEnabled == true", timeout: 10), "The run never started")
        XCTAssertEqual(pause.label, "Pause")

        pause.tap()
        XCTAssertTrue(pause.wait(until: "label == %@", "Resume"), "Pause didn't offer Resume")
        let status = app.element("run.status")
        XCTAssertTrue(status.label.hasPrefix("Paused, "), status.label)

        // Paused, nothing on the screen moves: Skip goes to the interval the next line names,
        // and the run stays paused there.
        var skippedTo = nextInterval(in: app)
        app.buttons["run.skip"].tap()
        XCTAssertTrue(status.wait(until: "label BEGINSWITH %@", "Paused, \(skippedTo), "), status.label)

        // Resumed at the start of that interval, which leaves Skip its whole length to land in.
        pause.tap()
        XCTAssertTrue(pause.wait(until: "label == %@", "Pause"), "Resume didn't offer Pause")
        skippedTo = nextInterval(in: app)
        app.buttons["run.skip"].tap()
        XCTAssertTrue(status.wait(until: "label BEGINSWITH %@", "\(skippedTo), "), status.label)

        // End, then End Workout: the run is thrown away and the library is back.
        app.buttons["run.end"].tap()
        let discard = app.alerts.buttons["run.endConfirm"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "End didn't ask first")
        discard.tap()
        XCTAssertTrue(status.wait(until: "exists == false"), "The run screen stayed")
        XCTAssertTrue(app.buttons["workouts.start.Tabata"].isHittable)
    }

    /// Two seconds from the end (`-qaRunElapsed`), the run finishes by itself: the summary,
    /// and Done back to the library.
    func testRunReachesSummary() throws {
        let app = PhoneApp.launch(["-qaRunElapsed", "\(Self.classicSeconds - 2)"])
        let complete = app.element("summary.complete")
        XCTAssertTrue(complete.waitForExistence(timeout: 15), "The run never finished")
        XCTAssertEqual(complete.label, "Workout complete, 5 minutes, 55 seconds")
        XCTAssertEqual(app.element("summary.rounds").label, "8 rounds done")

        app.buttons["summary.done"].tap()
        XCTAssertTrue(complete.wait(until: "exists == false"), "Done left the summary up")
        XCTAssertTrue(app.buttons["workouts.new"].isHittable)
    }

    /// "Work" from "Next, Work, 20 seconds": the interval the line under the ring says is next.
    private func nextInterval(in app: XCUIApplication) -> String {
        let words = app.element("run.next").label.components(separatedBy: ", ")
        XCTAssertEqual(words.first, "Next", "No next interval: \(words)")
        return words.count > 1 ? words[1] : ""
    }
}
