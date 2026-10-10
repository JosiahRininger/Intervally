//
//  SmallScreenLayoutTests.swift
//  IntervallyPhoneTests
//

import Foundation
import SwiftUI
import Testing
@testable import IntervallyPhone

/// The fixes from the iPhone SE and largest-text pass: what shrinks on a short screen, and
/// what stops growing where it can't.
@Suite("Small screens and large text")
@MainActor
struct SmallScreenLayoutTests {

    /// Visible heights above Continue, measured in the simulators: iPhone 17 Pro Max and
    /// 17 Pro. Under the ring, without a watch: the words and the highlights, about 380 points.
    @Test("The welcome ring stays full size on today's iPhones", arguments: [780.0, 700.0])
    func fullRing(height: CGFloat) {
        #expect(Welcome.ringSide(visibleHeight: height, belowRing: 380) == 220)
    }

    @Test("With the watch's card as well, the ring gives up what the card needs")
    func ringMakesRoom() {
        // An iPhone 17 Pro with the install card: about 470 points under the ring.
        let side = Welcome.ringSide(visibleHeight: 700, belowRing: 470)
        #expect(side == 170)
        #expect(side + 470 + Welcome.chrome <= 700)
    }

    @Test("The ring is full size until measured, and never below 120 points")
    func ringBounds() {
        #expect(Welcome.ringSide(visibleHeight: 0, belowRing: 0) == 220)
        #expect(Welcome.ringSide(visibleHeight: 568, belowRing: 520) == 120)
    }

    @Test("The editor's ring is full size until it is measured, and wherever there is room")
    func editorRingFullSize() {
        #expect(EditorLayout.ringSide(visibleHeight: 0, belowRing: 0) == 220)
        #expect(EditorLayout.ringSide(visibleHeight: 900, belowRing: 560) == 220)
    }

    /// Measured on an iPhone 17 Pro, free, default text size: 664 points between the
    /// navigation bar and Put on Watch, 418 of them below the ring.
    @Test("On a 6.3-inch iPhone the ring shrinks until the whole editor fits")
    func editorRingFits() {
        let side = EditorLayout.ringSide(visibleHeight: 664, belowRing: 418)
        #expect(side == 190)
        #expect(side + 418 + EditorLayout.chrome <= 664)
    }

    @Test("The editor's ring never shrinks below 120 points; past that the editor scrolls")
    func editorRingSmallest() {
        #expect(EditorLayout.ringSide(visibleHeight: 500, belowRing: 560) == 120)
    }

    /// The same iPhone with the tab bar kept under the pinned bar: about 70 points fewer.
    @Test("With the tab bar showing, the ring gives up the room and every tile still shows")
    func editorRingWithTabBar() {
        let side = EditorLayout.ringSide(visibleHeight: 596, belowRing: 418)
        #expect(side == 122)
        #expect(side + 418 + EditorLayout.chrome <= 596)
    }

    /// At the accessibility sizes each wheel value overlapped the next on an iPhone SE.
    @Test("Wheel rows follow the text size up to the largest standard one, and stop there")
    func wheelRowsStopGrowing() {
        #expect(ValuePickerSheet.largestRowSize == .xxxLarge)
        #expect(!ValuePickerSheet.largestRowSize.isAccessibilitySize)
    }
}
