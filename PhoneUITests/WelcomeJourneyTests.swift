//
//  WelcomeJourneyTests.swift
//  IntervallyPhoneUITests
//

import XCTest

/// The welcome, once: a new install opens on it, Continue goes to the workouts, and a relaunch
/// that keeps the defaults opens on the workouts. Neither launch skips it (`-qaSkipWelcome`),
/// as every other test does.
@MainActor
final class WelcomeJourneyTests: XCTestCase {
    func testWelcomeShowsOnceOnly() throws {
        let app = PhoneApp.launch(skipsWelcome: false)
        let proceed = app.buttons["welcome.continue"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 10), "A fresh launch didn't show the welcome")
        XCTAssertFalse(app.buttons["workouts.new"].exists, "The workouts showed with the welcome")
        proceed.tap()
        XCTAssertTrue(app.buttons["workouts.new"].waitForExistence(timeout: 5), "Continue didn't go to the workouts")
        XCTAssertFalse(proceed.exists)
        app.terminate()

        let again = PhoneApp.launch(defaults: .keep, skipsWelcome: false)
        XCTAssertTrue(again.buttons["workouts.new"].waitForExistence(timeout: 10))
        XCTAssertFalse(again.buttons["welcome.continue"].exists, "The welcome came back")
    }
}
