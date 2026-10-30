//
//  SettingsJourneyTests.swift
//  IntervallyPhoneUITests
//

import XCTest

/// Sounds & Voice, reached from the Workouts gear as someone would, keeps each switch as it
/// was left through a relaunch that keeps the defaults (`-qaDefaults keep`). Two are turned
/// off and two left on, so a relaunch that put every switch back, or turned every one off,
/// fails as well. With Pro, so the voice coach is a switch rather than the paywall.
@MainActor
final class SettingsJourneyTests: XCTestCase {
    func testSoundSettingsPersist() throws {
        let app = PhoneApp.launch(pro: true)
        let settings = app.buttons["workouts.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let sounds = app.element("settings.sounds")
        XCTAssertTrue(sounds.waitForExistence(timeout: 5))
        sounds.tap()

        // Each starts on, as on a new install.
        for name in ["countdown", "voice"] {
            let toggle = app.switches["sounds.\(name)"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), name)
            XCTAssertEqual(toggle.value as? String, "1", name)
            XCTAssertTrue(toggle.flip(), "\(name) didn't turn off")
        }
        app.terminate()

        let again = PhoneApp.launch(["-qaOpen", "sounds"], pro: true, defaults: .keep)
        let beeps = again.switches["sounds.beeps"]
        XCTAssertTrue(beeps.waitForExistence(timeout: 10))
        XCTAssertEqual(beeps.value as? String, "1", "Beeps")
        XCTAssertEqual(again.switches["sounds.countdown"].value as? String, "0", "3, 2, 1 Countdown")
        XCTAssertEqual(again.switches["sounds.voice"].value as? String, "0", "Voice Coach")
        let keepAwake = again.switches["sounds.keepAwake"]
        XCTAssertTrue(again.reveal(keepAwake), "Keep Screen On is missing")
        XCTAssertEqual(keepAwake.value as? String, "1", "Keep Screen On")
    }
}
