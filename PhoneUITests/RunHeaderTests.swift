//
//  RunHeaderTests.swift
//  IntervallyPhoneUITests
//

import XCTest

/// The run screen's top line with heart rate and calories showing, from a stand-in workout
/// session (`-qaWorkout`): the figures sit beside the workout's name and time left, or under
/// them at the accessibility sizes, and never over them, whatever the text size. On an SE the
/// room is tightest; 1.2 build 9 laid them over the corners, where a long name ran under them.
@MainActor
final class RunHeaderTests: XCTestCase {
    /// The default size, the largest before the accessibility sizes (the tightest beside the
    /// header), and the first and last accessibility sizes (under it).
    static let sizes = [
        "UICTContentSizeCategoryL",
        "UICTContentSizeCategoryXXXL",
        "UICTContentSizeCategoryAccessibilityM",
        "UICTContentSizeCategoryAccessibilityXXXL",
    ]

    func testFiguresNeverCoverTheHeader() throws {
        for size in Self.sizes {
            let app = PhoneApp.launch(
                ["-qaRunElapsed", "40", "-qaWorkout", "152,37", "-UIPreferredContentSizeCategoryName", size], pro: true
            )
            let heart = app.descendants(matching: .any)["Heart rate 152 beats per minute"].firstMatch
            let calories = app.descendants(matching: .any)["37 active calories"].firstMatch
            let header = app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH ' left'")).firstMatch
            XCTAssertTrue(heart.waitForExistence(timeout: 15), "Heart rate at \(size)")
            XCTAssertTrue(calories.exists, "Calories at \(size)")
            XCTAssertTrue(header.exists, "Header at \(size)")

            let window = app.windows.firstMatch.frame
            for (name, figure) in [("heart rate", heart.frame), ("calories", calories.frame)] {
                // Edges that only touch are fine; a point of overlap is not.
                XCTAssertFalse(figure.insetBy(dx: 0.5, dy: 0.5).intersects(header.frame), "The \(name) covers the header at \(size)")
                XCTAssertTrue(window.contains(figure), "The \(name) runs off the screen at \(size)")
            }
            XCTAssertFalse(heart.frame.intersects(calories.frame), "The figures overlap at \(size)")
            // The controls set the screen's width: one wider than it pushed everything right.
            for control in ["End Workout", "Skip Interval"] {
                XCTAssertTrue(window.contains(app.buttons[control].frame), "\(control) runs off the screen at \(size)")
            }
            // Each side keeps the wider figure's room, so the header stays in the middle.
            XCTAssertEqual(header.frame.midX, window.midX, accuracy: 1, "The header is off centre at \(size)")
            PhoneApp.endRun(app)
            app.terminate()
        }
    }
}
