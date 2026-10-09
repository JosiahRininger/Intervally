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

    /// Visible heights above Continue, measured in the simulators: iPhone 17 Pro Max, 17 Pro
    /// and SE (3rd generation).
    @Test("The welcome ring stays full size on today's iPhones", arguments: [780.0, 700.0])
    func fullRing(height: CGFloat) {
        #expect(Welcome.ringSide(forHeight: height) == 220)
    }

    @Test("On an iPhone SE the ring gives the watch's install steps room above Continue")
    func smallRing() {
        let side = Welcome.ringSide(forHeight: 568)
        #expect(side == 158)
        // What the words need, at the default size, with the ring at that side.
        #expect(side + 410 <= 568)
    }

    @Test("The ring never shrinks below 140 points, however little room is left")
    func smallestRing() {
        #expect(Welcome.ringSide(forHeight: 300) == 140)
        #expect(Welcome.ringSide(forHeight: 0) == 140)
    }

    /// At the accessibility sizes each wheel value overlapped the next on an iPhone SE.
    @Test("Wheel rows follow the text size up to the largest standard one, and stop there")
    func wheelRowsStopGrowing() {
        #expect(ValuePickerSheet.largestRowSize == .xxxLarge)
        #expect(!ValuePickerSheet.largestRowSize.isAccessibilitySize)
    }
}
