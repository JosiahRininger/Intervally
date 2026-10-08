//
//  DialGeometryTests.swift
//  IntervallyTests
//

import Testing
import CoreGraphics
@testable import Intervally

/// The run screen's layout, checked against every watch size so a tweak that looks right on
/// one simulator cannot quietly shrink the ring or crowd the controls on another.
@Suite("Run screen dial geometry")
struct DialGeometryTests {

    /// Full-display sizes in points: 40, 41, 42, 44, 45, 46mm, Ultra 1/2 and Ultra 3.
    static let screens: [CGSize] = [
        CGSize(width: 162, height: 197), CGSize(width: 176, height: 215),
        CGSize(width: 187, height: 223), CGSize(width: 184, height: 224),
        CGSize(width: 198, height: 242), CGSize(width: 208, height: 248),
        CGSize(width: 205, height: 251), CGSize(width: 211, height: 257),
    ]

    @Test("The ring is the hero: at least 100pt on 40mm and 140pt on 46mm")
    func ringIsLarge() {
        #expect(DialLayout(screen: CGSize(width: 162, height: 197)).diameter >= 100)
        #expect(DialLayout(screen: CGSize(width: 208, height: 248)).diameter >= 140)
    }

    @Test("Everything fits on one screen, top to bottom", arguments: screens)
    func fitsVertically(screen: CGSize) {
        let dial = DialLayout(screen: screen)
        let used = dial.ringTop + dial.diameter + dial.gap + dial.control + dial.bottomMargin
        #expect(used <= screen.height)
    }

    @Test("The ring leaves the screen's side edges clear", arguments: screens)
    func fitsHorizontally(screen: CGSize) {
        #expect(DialLayout(screen: screen).diameter <= screen.width - 16)
    }

    @Test("Controls meet the 44pt minimum and stay compact", arguments: screens)
    func controlSize(screen: CGSize) {
        let control = DialLayout(screen: screen).control
        #expect(control >= 44)
        #expect(control <= 52)
    }

    @Test("The system time clears the ring's top arc", arguments: screens)
    func timeClearance(screen: CGSize) {
        // The status-bar clock is ~17pt tall from ~10pt down on every size.
        #expect(DialLayout(screen: screen).ringTop >= 28)
    }

    @Test("Label and footer lines get a usable width inside the ring", arguments: screens)
    func chordIsUsable(screen: CGSize) {
        let dial = DialLayout(screen: screen)
        let chord = dial.chord(atOffset: 0.4 * dial.interior)
        #expect(chord > 0.5 * dial.interior)
        #expect(chord < dial.interior)
    }

    @Test("A bigger watch never gets a smaller ring")
    func monotonic() {
        let byHeight = Self.screens.sorted { $0.height < $1.height }
        let diameters = byHeight.map { DialLayout(screen: $0).diameter }
        #expect(diameters == diameters.sorted())
    }
}
