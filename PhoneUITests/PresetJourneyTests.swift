//
//  PresetJourneyTests.swift
//  IntervallyPhoneUITests
//

import XCTest

/// Presets made, copied and opened end to end, as someone would: + and the editor, the
/// wheels, Back, and the library's cards. The editor saves every change as it is made, so
/// Back is its only Save. Making and copying one takes Pro: the starters fill the free tier,
/// where + and Duplicate open the paywall instead.
@MainActor
final class PresetJourneyTests: XCTestCase {
    func testCreateRenameSave() throws {
        let app = PhoneApp.launch(pro: true)
        let add = app.buttons["workouts.new"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        // The new preset's name starts empty and being typed in, its default the placeholder.
        let name = app.textFields["editor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.placeholderValue, "New Workout")
        name.typeText("Hill Sprints\n")
        XCTAssertEqual(name.value as? String, "Hill Sprints")

        set("work", ["minutes": "0 minutes", "seconds": "40 seconds"], showing: "40 seconds", in: app)
        set("rest", ["minutes": "0 minutes", "seconds": "20 seconds"], showing: "20 seconds", in: app)
        // A new preset already has 8 rounds, so 8 would leave the rounds wheel untried.
        set("rounds", ["rounds": "10 rounds"], showing: "10 rounds", in: app)

        app.navigationBars.buttons["BackButton"].tap()
        let card = app.buttons["workouts.preset.Hill Sprints"]
        XCTAssertTrue(app.reveal(card), "The new preset isn't in the library")
        XCTAssertTrue(card.staticTexts["40s · 20s · 10×"].exists, "Its rhythm line: \(card.label)")
        XCTAssertTrue(card.staticTexts["9:50"].exists, "Its total: \(card.label)")
    }

    /// From the editor's menu. The library's long-press menu duplicates the same way, but while
    /// it is up XCUITest waits a minute for the app to settle, once to open it and once to tap.
    func testDuplicate() throws {
        let app = PhoneApp.launch(pro: true)
        let tabata = app.buttons["workouts.preset.Tabata"]
        XCTAssertTrue(tabata.waitForExistence(timeout: 10))
        tabata.tap()

        let more = app.buttons["editor.more"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let duplicate = app.buttons["editor.duplicate"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5))
        duplicate.tap()

        // The copy opens in its own editor, named as the watch names copies, every value kept.
        XCTAssertTrue(app.textFields["editor.name"].wait(until: "value == %@", "Tabata 2"), "The copy's editor didn't open")
        XCTAssertEqual(app.buttons["editor.work"].value as? String, "20 seconds")
        XCTAssertEqual(app.buttons["editor.rest"].value as? String, "10 seconds")
        XCTAssertEqual(app.buttons["editor.rounds"].value as? String, "8 rounds")

        // Back to Tabata's editor, which opened the copy's, then to the library.
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.textFields["editor.name"].wait(until: "value == %@", "Tabata"))
        app.navigationBars.buttons["BackButton"].tap()
        let copy = app.buttons["workouts.preset.Tabata 2"]
        XCTAssertTrue(app.reveal(copy), "The copy isn't in the library")
        XCTAssertTrue(copy.staticTexts["20s · 10s · 8×"].exists, "The copy's rhythm line: \(copy.label)")
        XCTAssertTrue(app.buttons["workouts.preset.Tabata"].exists, "The copy replaced the original")
    }

    /// An editor opened and left with nothing changed, though its name was typed in and Work's
    /// picker opened, leaves every card on the library as it was.
    func testCancelLeavesLibraryUnchanged() throws {
        let app = PhoneApp.launch()
        let classic = app.buttons["workouts.preset.Classic"]
        XCTAssertTrue(classic.waitForExistence(timeout: 10))
        let before = cards(in: app)
        classic.tap()

        let name = app.textFields["editor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("\n")
        let work = app.buttons["editor.work"]
        work.tap()
        XCTAssertTrue(app.pickers["picker.seconds"].waitForExistence(timeout: 5))
        app.buttons["picker.done"].tap()
        XCTAssertTrue(work.wait(until: "value == %@", "30 seconds"))
        app.navigationBars.buttons["BackButton"].tap()

        XCTAssertTrue(app.buttons["workouts.new"].wait(until: "isHittable == true"), "The library didn't come back")
        let after = cards(in: app)
        for (card, shown) in before {
            XCTAssertEqual(after[card], shown, card)
        }
    }

    // MARK: - Helpers

    /// Opens a tile's picker, turns its wheels in order, closes it with Done, and checks the
    /// tile now says `value`.
    private func set(_ field: String, _ wheels: KeyValuePairs<String, String>, showing value: String, in app: XCUIApplication) {
        let tile = app.buttons["editor.\(field)"]
        tile.tap()
        for (picker, row) in wheels {
            let wheel = app.pickers["picker.\(picker)"].pickerWheels.firstMatch
            XCTAssertTrue(wheel.waitForExistence(timeout: 5), "\(field): no \(picker) wheel")
            wheel.adjust(toPickerWheelValue: row)
        }
        app.buttons["picker.done"].tap()
        XCTAssertTrue(tile.wait(until: "value == %@", value), "\(field) says \(tile.value as? String ?? "nothing")")
    }

    /// The cards the library shows, by identifier: what each says, and whether it is up next.
    /// Only those on screen: a list builds no others, and an SE shows the top of the library.
    private func cards(in app: XCUIApplication) -> [String: String] {
        var cards = ["workouts.upNext": app.element("workouts.upNext").label]
        let presets = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workouts.preset."))
        for card in presets.allElementsBoundByIndex {
            cards[card.identifier] = "\(card.label), \(card.value as? String ?? "")"
        }
        return cards
    }
}
