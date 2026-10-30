//
//  LaunchHygieneTests.swift
//  IntervallyPhoneUITests
//

import XCTest

/// What every UI test launches into: a fresh launch (`-qaDefaults fresh`) starts as a new
/// install would and puts up no system alert, and one that keeps its defaults (`keep`) still
/// has what the last launch made. Before fresh launches, a preset or a run one test left
/// behind could show up in the next, and a first Start could raise the notification alert
/// over the screen under test.
@MainActor
final class LaunchHygieneTests: XCTestCase {
    /// Selected as it is added, so it is the workout up next: at the top of the screen, where
    /// even an SE shows it, unlike the bottom of the library.
    static let leftBehind = "Left Behind"

    func testFreshDefaultsStartsWithStartersOnly() throws {
        let earlier = PhoneApp.launch(["-qaEdit", "add \(Self.leftBehind)"], defaults: .keep)
        XCTAssertTrue(earlier.buttons["Start \(Self.leftBehind) on Apple Watch"].waitForExistence(timeout: 10))
        earlier.terminate()

        let app = PhoneApp.launch()
        // Up next is Classic again, as on a new install, and the library holds the starters.
        XCTAssertTrue(app.buttons["Start Classic on Apple Watch"].waitForExistence(timeout: 10))
        for starter in ["Classic", "Tabata", "EMOM"] {
            XCTAssertTrue(app.buttons["Start \(starter)"].firstMatch.exists, starter)
        }
        let leftover = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", Self.leftBehind)).firstMatch
        XCTAssertFalse(leftover.exists, "A preset from the launch before survived a fresh launch")
    }

    func testKeepPreservesCreatedPreset() throws {
        let earlier = PhoneApp.launch(["-qaEdit", "add Kept"])
        XCTAssertTrue(earlier.buttons["Start Kept on Apple Watch"].waitForExistence(timeout: 10))
        earlier.terminate()

        let app = PhoneApp.launch(defaults: .keep)
        XCTAssertTrue(app.buttons["Start Kept on Apple Watch"].waitForExistence(timeout: 10), "Keep lost the preset made before")
        XCTAssertTrue(app.buttons["Start Classic"].firstMatch.exists)
    }

    /// The first Start is where a run asks for notifications and Health. A fresh launch asks
    /// for neither, so the run starts at once (Pause is enabled only once the clock runs) and
    /// nothing comes up over it.
    func testFreshLaunchShowsNoSystemAlert() throws {
        let app = PhoneApp.launch()
        let start = app.buttons["Start Classic"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        let running = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: pause)
        XCTAssertEqual(XCTWaiter().wait(for: [running], timeout: 10), .completed, "The run never started: a prompt is holding it")

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertFalse(springboard.alerts.firstMatch.waitForExistence(timeout: 5), "A system alert covers the app")
        XCTAssertTrue(pause.isHittable, "Something covers the run screen")
        PhoneApp.endRun(app)
    }
}
