//
//  EditorNameTests.swift
//  IntervallyPhoneUITests
//

import XCTest

/// The editor's name field on a real screen: typing stops at the cap, as a phase's name does,
/// rather than the name being cut only once it is saved.
@MainActor
final class EditorNameTests: XCTestCase {
    /// `IntervalWorkout.maxNameLength`: the UI tests can't see the app's code.
    static let maxNameLength = 40

    func testTypingStopsAtTheCap() throws {
        let app = PhoneApp.launch(["-qaOpen", "editor"])
        let field = app.textFields["Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))

        // Far more than fits, wherever in the name the caret lands. Capitalised words, so the
        // field's own capitalisation changes nothing.
        field.tap()
        field.typeText(String(repeating: " Sprint", count: 8))
        let shown = try XCTUnwrap(field.value as? String)
        XCTAssertEqual(shown.count, Self.maxNameLength, shown)
        XCTAssertTrue(shown.contains("Sprint"), shown)

        // A name is saved only when typing ends: ending the app here leaves the preset as it
        // was for every test after this one.
        app.terminate()
    }
}
