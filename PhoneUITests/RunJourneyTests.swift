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

        // End, then End Workout: the run is thrown away and the library is back. Under a minute
        // in, there is nothing to save.
        app.buttons["run.end"].tap()
        let discard = app.alerts.buttons["run.endConfirm"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "End didn't ask first")
        XCTAssertEqual(discard.label, "End Workout")
        XCTAssertFalse(app.alerts.buttons["run.endSave"].firstMatch.exists, "A run under a minute in offered Save Workout")
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

    /// A minute and more into a run on a workout session, End offers Save Workout beside Discard
    /// and Keep Going. Saved, the summary says how far the run got, and Done goes back. The run
    /// is paused first, so a slow simulator can't carry it into the fourth round before Save,
    /// and a paused run is the one saved.
    func testEndOffersSaveDiscardKeepGoing() throws {
        let app = launchInThirdRound()
        let pause = app.buttons["run.pauseResume"]
        pause.tap()
        XCTAssertTrue(pause.wait(until: "label == %@", "Resume"), "Pause didn't offer Resume")
        app.buttons["run.end"].tap()
        let save = app.alerts.buttons["run.endSave"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "End didn't offer Save Workout")
        XCTAssertEqual(save.label, "Save Workout")
        XCTAssertEqual(app.alerts.buttons["run.endConfirm"].firstMatch.label, "Discard")
        XCTAssertEqual(app.alerts.buttons["run.endCancel"].firstMatch.label, "Keep Going")

        save.tap()
        let rounds = app.element("summary.rounds")
        XCTAssertTrue(rounds.waitForExistence(timeout: 10), "Save Workout didn't show the summary")
        XCTAssertEqual(rounds.label, "Ended early: 3 of 8 rounds")
        let ended = app.element("summary.complete")
        XCTAssertTrue(ended.label.hasPrefix("Workout ended early, "), ended.label)

        app.buttons["summary.done"].tap()
        XCTAssertTrue(rounds.wait(until: "exists == false"), "Done left the summary up")
        XCTAssertTrue(app.buttons["workouts.new"].isHittable)
    }

    /// Keep Going puts the question away, and the run is still going and still counting.
    func testKeepGoingResumes() throws {
        let app = launchInThirdRound()
        app.buttons["run.end"].tap()
        let keepGoing = app.alerts.buttons["run.endCancel"].firstMatch
        XCTAssertTrue(keepGoing.waitForExistence(timeout: 5), "End didn't ask first")
        keepGoing.tap()
        XCTAssertTrue(keepGoing.wait(until: "exists == false"), "The question stayed up")

        XCTAssertEqual(app.buttons["run.pauseResume"].label, "Pause")
        let status = app.element("run.status")
        let shown = status.label
        XCTAssertTrue(status.wait(until: "label != %@", shown), "The run stopped counting: \(shown)")
        XCTAssertFalse(app.element("summary.rounds").exists)
    }

    /// Classic restored 1:41 in, in its third round, which runs to 2:25: time enough for End's
    /// question without crossing into the fourth, on a workout session from a stand-in.
    private func launchInThirdRound() -> XCUIApplication {
        let app = PhoneApp.launch(["-qaRunElapsed", "101"])
        let pause = app.buttons["run.pauseResume"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15), "The run didn't come back")
        XCTAssertTrue(pause.wait(until: "isEnabled == true", timeout: 10), "The run never started")
        return app
    }

    /// "Work" from "Next, Work, 20 seconds": the interval the line under the ring says is next.
    private func nextInterval(in app: XCUIApplication) -> String {
        let words = app.element("run.next").label.components(separatedBy: ", ")
        XCTAssertEqual(words.first, "Next", "No next interval: \(words)")
        return words.count > 1 ? words[1] : ""
    }
}
