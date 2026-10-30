//
//  PaywallJourneyTests.swift
//  IntervallyPhoneUITests
//

import XCTest

/// The ways on for someone without Pro: Hear the Coach, in Sounds & Voice and on the
/// paywall, and Edit a Starter Instead on the paywall from + at the free limit, which the
/// starters fill on a fresh install.
@MainActor
final class PaywallJourneyTests: XCTestCase {
    func testHearTheCoachPresent() throws {
        let app = PhoneApp.launch(["-qaOpen", "sounds"])
        let hear = app.buttons["sounds.hearCoach"]
        XCTAssertTrue(hear.waitForExistence(timeout: 10), "No Hear the Coach in Sounds & Voice")
        XCTAssertTrue(app.reveal(hear))
        // It plays, or asks for the music to be paused; either way the screen carries on.
        hear.tap()

        // The voice coach's switch, without Pro, opens the paywall, which has it too.
        let voice = app.switches["sounds.voice"]
        XCTAssertTrue(voice.waitForExistence(timeout: 5))
        voice.switches.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Intervally Pro"].firstMatch.waitForExistence(timeout: 5), "The paywall didn't open")
        XCTAssertTrue(app.reveal(app.buttons["paywall.hearCoach"]), "No Hear the Coach on the paywall")
        app.terminate()

        // With Pro the coach plays on every run: nothing to hear first.
        let pro = PhoneApp.launch(["-qaOpen", "sounds"], pro: true)
        XCTAssertTrue(pro.switches["sounds.voice"].waitForExistence(timeout: 10))
        XCTAssertFalse(pro.buttons["sounds.hearCoach"].exists, "Hear the Coach shown with Pro")
    }

    /// The editor opens on the starter up next, and no preset is added: the free limit stays
    /// where it was. Only + offers it: a paywall on the way to a copy doesn't.
    func testEditInsteadOpensEditor() throws {
        let app = PhoneApp.launch()
        let add = app.buttons["workouts.new"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        let presets = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'workouts.preset.'"))
        let before = presets.count
        XCTAssertEqual(before, 3, "The starters fill the free tier")
        add.tap()

        let instead = app.buttons["paywall.editInstead"]
        XCTAssertTrue(instead.waitForExistence(timeout: 5), "No Edit a Starter Instead on the paywall from +")
        XCTAssertTrue(app.reveal(instead))
        instead.tap()

        let name = app.textFields["editor.name"]
        XCTAssertTrue(name.wait(until: "value == %@", "Classic", timeout: 10), "The up next starter's editor didn't open")

        // Duplicate at the free limit opens the paywall too, without the way to edit instead.
        let more = app.buttons["editor.more"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let duplicate = app.buttons["editor.duplicate"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5))
        duplicate.tap()
        XCTAssertTrue(app.staticTexts["Intervally Pro"].firstMatch.waitForExistence(timeout: 5), "The paywall didn't open")
        XCTAssertFalse(app.buttons["paywall.editInstead"].exists, "Edit a Starter Instead on the paywall from Duplicate")
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()

        XCTAssertTrue(app.navigationBars.buttons["BackButton"].wait(until: "isHittable == true"))
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["workouts.new"].wait(until: "isHittable == true"), "The library didn't come back")
        XCTAssertEqual(presets.count, before, "A preset was added past the free limit")
        XCTAssertFalse(app.reveal(app.buttons["workouts.preset.New Workout"], swipes: 2), "A preset was added past the free limit")
    }

    /// The library's own Duplicate, apart from the editor's: its paywall is the one the
    /// Workouts screen tells apart from +'s. Opened directly, as a card's menu makes XCUITest
    /// wait a minute for its animations (`PresetDeleteTests`).
    func testLibraryDuplicatePaywallHasNoEditInstead() throws {
        let app = PhoneApp.launch(["-qaOpen", "duplicatePaywall"])
        XCTAssertTrue(app.staticTexts["Intervally Pro"].firstMatch.waitForExistence(timeout: 10), "The paywall didn't open")
        XCTAssertTrue(app.buttons["Close"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["paywall.editInstead"].exists, "Edit a Starter Instead on the paywall from Duplicate")
        app.terminate()

        // The same screen's paywall from + offers it: the check above is of the sheet, not of a
        // paywall that never shows it.
        let add = PhoneApp.launch(["-qaOpen", "paywall"])
        XCTAssertTrue(add.buttons["paywall.editInstead"].waitForExistence(timeout: 10), "No Edit a Starter Instead on the paywall from +")
    }
}
