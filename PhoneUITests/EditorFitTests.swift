//
//  EditorFitTests.swift
//  IntervallyPhoneUITests
//

import XCTest

/// The editor on a real screen: every tile shows without scrolling on today's 6.1- and
/// 6.3-inch iPhones, the tab bar under the pinned Start included. The ring gives up the room
/// (`EditorLayout.ringSide`); 1.2's activity capsule, set under the name, once took more than
/// the ring could give, and Warmup and Cooldown sat under Start.
@MainActor
final class EditorFitTests: XCTestCase {
    /// The shortest iPhone this holds on: 6.1 inches (852 points tall). An SE scrolls.
    static let shortestFittingScreen: CGFloat = 852

    func testEveryTileShowsAboveStart() throws {
        for pro in [false, true] {
            let app = PhoneApp.launch(["-qaOpen", "editor"], pro: pro)
            let window = app.windows.firstMatch
            XCTAssertTrue(app.buttons["Work"].waitForExistence(timeout: 10))
            try XCTSkipIf(window.frame.height < Self.shortestFittingScreen, "An iPhone this short scrolls the editor")

            let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start ' AND NOT (label ENDSWITH 'Apple Watch')")).firstMatch
            XCTAssertTrue(start.exists)
            for title in ["Work", "Rest", "Rounds", "Get Ready", "Warmup", "Cooldown"] {
                let tile = app.buttons[title]
                XCTAssertTrue(tile.exists, title)
                XCTAssertLessThanOrEqual(tile.frame.maxY, start.frame.minY, "\(title) sits under Start (Pro: \(pro))")
            }
            app.terminate()
        }
    }

    /// The activity stays in reach whatever the scroll: in the navigation bar, not the list.
    func testActivityIsInTheNavigationBar() throws {
        let app = PhoneApp.launch(["-qaOpen", "editor"])
        let activity = app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Activity, '")).firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 10))
    }
}
