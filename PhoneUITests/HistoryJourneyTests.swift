//
//  HistoryJourneyTests.swift
//  IntervallyPhoneUITests
//

import XCTest

/// History reached from its tab, with sessions from the debug build's fixture
/// (`-qaHistory sample`, `SampleHistory`) rather than Health, which is never read: the week at
/// a glance, the sessions under it, and one opened.
@MainActor
final class HistoryJourneyTests: XCTestCase {
    func testHistoryWeekAndDetail() throws {
        let app = PhoneApp.launch(["-qaHistory", "sample"])
        // Not through the tab bar: on iPad the tabs float at the top, in none.
        let tab = app.buttons["History"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()

        // How many of the fixture's sessions fall in this week depends on the day it runs.
        let week = app.element("history.thisWeek")
        XCTAssertTrue(week.waitForExistence(timeout: 10), "No This Week card")
        XCTAssertTrue(week.label.hasPrefix("This week: "), week.label)

        // Newest first: the fixture's latest session is a Classic.
        let session = app.buttons.matching(identifier: "history.session").firstMatch
        XCTAssertTrue(session.exists, "No sessions under This Week")
        XCTAssertTrue(session.label.hasPrefix("Classic, "), session.label)
        XCTAssertTrue(session.label.contains("8 of 8 rounds"), session.label)
        session.tap()

        let title = app.element("session.title")
        XCTAssertTrue(title.waitForExistence(timeout: 5), "The session didn't open")
        XCTAssertEqual(title.label, "Classic")
    }
}
