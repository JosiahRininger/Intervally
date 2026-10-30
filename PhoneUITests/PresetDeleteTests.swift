//
//  PresetDeleteTests.swift
//  IntervallyPhoneUITests
//

import XCTest

/// Deleting a preset from the library asks first, however it is asked for: Delete in a card's
/// swipe actions, Delete in its menu, or a full swipe, which in 1.2 deleted the preset from
/// both devices with nothing asked. The editor asks the same question.
///
/// Each test makes a workout of its own with + and deletes it, so the library is left as it
/// was. Not with Duplicate in a card's menu: while that menu is open the app never reports
/// its animations finished, and XCUITest waits a full minute before and after each step there.
/// For the same reason only `testContextMenuDeleteAsksFirst` opens the menu.
///
/// On a loaded Mac the simulator now and then loses a tap, a press or a swipe, most often on
/// a screen still coming in, so each step is tried until what it opens shows, three times at
/// most.
@MainActor
final class PresetDeleteTests: XCTestCase {
    func testSwipeDeleteAsksFirst() throws {
        let app = PhoneApp.launch(pro: true)
        let workout = try makeWorkout(in: app)

        swipeToDelete(workout, in: app)
        let alert = confirmation(for: workout, in: app)
        XCTAssertFalse(card(workout, in: app).waitForNonExistence(timeout: 1), "Gone before the question was answered")
        alert.buttons["Delete"].tap()
        XCTAssertTrue(card(workout, in: app).waitForNonExistence(timeout: 5), "Delete in the question didn't delete it")
    }

    func testContextMenuDeleteAsksFirst() throws {
        let app = PhoneApp.launch(pro: true)
        let workout = try makeWorkout(in: app)

        menuDelete(workout, in: app)
        let alert = confirmation(for: workout, in: app)
        XCTAssertFalse(card(workout, in: app).waitForNonExistence(timeout: 1), "Gone before the question was answered")
        alert.buttons["Delete"].tap()
        XCTAssertTrue(card(workout, in: app).waitForNonExistence(timeout: 5), "Delete in the question didn't delete it")
    }

    /// From the swipe, where it can go wrong: the card has to stay on the list, not only in
    /// the store, and a destructive swipe button takes its row off the list as it is tapped.
    /// The menu opens the same question, so its Cancel is this one.
    func testCancelKeepsPreset() throws {
        let app = PhoneApp.launch(pro: true)
        let workout = try makeWorkout(in: app)

        swipeToDelete(workout, in: app)
        confirmation(for: workout, in: app).buttons["Cancel"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertFalse(card(workout, in: app).waitForNonExistence(timeout: 2), "Cancel lost the card")
        XCTAssertTrue(card(workout, in: app).isHittable)

        // And a Delete after it deletes it, once.
        swipeToDelete(workout, in: app)
        confirmation(for: workout, in: app).buttons["Delete"].tap()
        XCTAssertTrue(card(workout, in: app).waitForNonExistence(timeout: 5))
    }

    func testFullSwipeDoesNotDelete() throws {
        let app = PhoneApp.launch(pro: true)
        let workout = try makeWorkout(in: app)

        // All the way across, fast: what ran Delete outright in 1.2. Now it stops at the
        // actions, with Delete a tap away.
        let row = row(workout, in: app)
        let delete = app.buttons["Delete"].firstMatch
        for _ in 0..<3 where !delete.exists {
            let from = row.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            let to = row.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0)
            _ = delete.waitForExistence(timeout: 3)
        }
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2), "A full swipe ran Delete")
        XCTAssertFalse(card(workout, in: app).waitForNonExistence(timeout: 1), "A full swipe deleted it")
        XCTAssertTrue(delete.exists, "The swipe didn't open the actions")

        // And that Delete still asks.
        swipeToDelete(workout, in: app)
        confirmation(for: workout, in: app).buttons["Delete"].tap()
        XCTAssertTrue(card(workout, in: app).waitForNonExistence(timeout: 5))
    }

    /// The editor's menu asks the same question, and its Delete closes the editor as well.
    func testEditorDeleteAsksTheSame() throws {
        let app = PhoneApp.launch(pro: true)
        let workout = try add(in: app)

        askToDelete(in: app) { app.buttons["More"].tap() }
        confirmation(for: workout, in: app).buttons["Delete"].tap()
        XCTAssertTrue(app.navigationBars["Workouts"].waitForExistence(timeout: 5), "The editor stayed open")
        XCTAssertTrue(card(workout, in: app).waitForNonExistence(timeout: 5))
    }

    // MARK: - Helpers

    /// Under the question. Every launch has a stand-in watch (`-qaWatch installed`), which
    /// an iPhone names and an iPad, which never has one, doesn't.
    private static var message: String {
        UIDevice.current.userInterfaceIdiom == .pad
            ? "It will be removed from this iPad."
            : "It will be removed from this iPhone and your Apple Watch."
    }

    /// A workout's card in the library, read as its name then its rhythm. Up next's card reads
    /// "Up next" first, so it is never this.
    private func card(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(name). ")).firstMatch
    }

    /// The list row holding that card, for its swipe and its menu.
    private func row(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.cells.containing(NSPredicate(format: "label BEGINSWITH %@", "\(name). ")).firstMatch
    }

    /// + in the library, which opens the new workout's editor. Returns the workout's name,
    /// which no other preset has: the name field starts empty, showing it.
    private func add(in app: XCUIApplication) throws -> String {
        let add = app.buttons["New Workout"]
        let more = app.buttons["More"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        for _ in 0..<3 where !more.exists {
            if add.isHittable { add.tap() }
            _ = more.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(more.exists, "+ opened no editor")
        return try XCTUnwrap(app.textFields["Name"].placeholderValue)
    }

    /// A new workout from +, back on the library and scrolled to, at the end of it.
    private func makeWorkout(in app: XCUIApplication) throws -> String {
        let name = try add(in: app)
        let back = app.navigationBars.buttons["BackButton"]
        let list = app.collectionViews.firstMatch
        for _ in 0..<3 where !list.exists {
            if back.waitForExistence(timeout: 2) { back.tap() }
            _ = list.waitForExistence(timeout: 3)
        }
        // An SE shows only the first few cards.
        for _ in 0..<4 where !card(name, in: app).isHittable { list.swipeUp() }
        XCTAssertTrue(card(name, in: app).isHittable, "\(name) isn't in the library")
        return name
    }

    /// Opens Delete with `reveal`, tried until it shows, and taps it once. There is no second
    /// tap: a Delete whose first tap asks nothing is the presenter bug the question is for,
    /// and the test should catch it, not ride over it (`confirmation`). Never taps once
    /// anything is asked, so the question's own Delete is never the one tapped.
    private func askToDelete(in app: XCUIApplication, reveal: () -> Void) {
        let delete = app.buttons["Delete"].firstMatch
        let asked = app.alerts.firstMatch
        for _ in 0..<3 where !delete.exists && !asked.exists {
            reveal()
            _ = delete.waitForExistence(timeout: 5)
        }
        guard !asked.exists else { return }
        XCTAssertTrue(delete.wait(until: "isHittable == true"), "No Delete to tap")
        delete.tap()
    }

    /// Swipes the card as far as its actions and taps Delete there.
    private func swipeToDelete(_ name: String, in app: XCUIApplication) {
        askToDelete(in: app) { row(name, in: app).swipeLeft() }
    }

    /// Holds the card for its menu and taps Delete there.
    private func menuDelete(_ name: String, in app: XCUIApplication) {
        askToDelete(in: app) { row(name, in: app).press(forDuration: 1) }
    }

    /// The question, the same from the swipe, the menu and the editor.
    private func confirmation(for name: String, in app: XCUIApplication) -> XCUIElement {
        let alert = app.alerts["Delete “\(name)”?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Nothing asked before deleting \(name)")
        XCTAssertTrue(alert.staticTexts[Self.message].exists, "The question's message")
        XCTAssertTrue(alert.buttons["Cancel"].exists)
        return alert
    }
}
