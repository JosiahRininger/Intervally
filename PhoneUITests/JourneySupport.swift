//
//  JourneySupport.swift
//  IntervallyPhoneUITests
//

import XCTest

// What the journey tests share. They find the app's elements by the accessibility identifiers
// its views give them, which no one hears and no copy change moves; system chrome that has
// none of its own (the tab bar, Back) by what it says. They wait for an element to change,
// never for time to pass.

extension XCUIElement {
    /// Waits until the element matches `format`, as `waitForExistence` waits for it to exist:
    /// for a label or value that a tap or the run's clock changes.
    @discardableResult
    func wait(until format: String, _ arguments: CVarArg..., timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: format, argumentArray: arguments)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Flips a switch in a list, and says whether it changed. Its element spans the whole row,
    /// and a tap in the middle lands on the title, which turns nothing: the switch itself is
    /// inside it. A loaded simulator now and then loses a tap on it (the log shows the tap
    /// sent and the switch as it was, and the same test passes alone), so a tap that changed
    /// nothing is sent once more. The tap waits for the app to settle, so a change has shown
    /// by the time the wait begins.
    func flip() -> Bool {
        let before = value as? String ?? ""
        for _ in 1...2 {
            switches.firstMatch.tap()
            if wait(until: "value != %@", before, timeout: 3) { return true }
        }
        return false
    }
}

extension XCUIApplication {
    /// The element with this identifier, whatever kind SwiftUI made it: the run's ring is an
    /// "other", its next line static text.
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any)[identifier].firstMatch
    }

    /// Scrolls up a swipe at a time until `element` can be tapped. A list only builds the rows
    /// it shows, and an SE shows the top of the library and of Sounds & Voice, not the end.
    @discardableResult
    func reveal(_ element: XCUIElement, swipes: Int = 4) -> Bool {
        var swiped = 0
        while !(element.exists && element.isHittable), swiped < swipes {
            swipeUp()
            swiped += 1
        }
        return element.exists && element.isHittable
    }
}
