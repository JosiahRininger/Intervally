//
//  ThemeTests.swift
//  IntervallyTests
//

import SwiftUI
import Testing
@testable import Intervally

/// The watch in each theme: the same black screen, the theme's phase colours.
@Suite("Theme on the watch")
@MainActor
struct ThemeTests {

    @Test("A ring's segments take their colour from the palette they are drawn in")
    func segmentsFollowThePalette() {
        let plan = IntervalPlan(workout: AppTheme.swatch)
        for segment in SegmentedRing.segments(for: plan) {
            #expect(segment.color(in: .pastelWatch) == Palette.pastelWatch.fill(for: segment.kind))
            #expect(segment.color == Theme.light(for: segment.kind), "Classic, with no palette")
        }
    }

    @Test("A tile's colour follows the theme; rounds stays the neutral white on the watch")
    func tilesFollowThePalette() {
        #expect(SetupField.work.tint(in: .pastelWatch) == Palette.pastelWatch.work)
        #expect(SetupField.cooldown.tint(in: .pastelWatch) == Palette.pastelWatch.cooldown)
        #expect(SetupField.rounds.tint(in: .pastelWatch) == .white)
        for field in SetupField.allCases {
            #expect(field.tint(in: .classic) == field.tint)
        }
    }

    @Test("A crown editor shows its value in the theme's colour")
    func editorTint() {
        #expect(SetupField.work.editor(value: .constant(30), palette: .pastelWatch).tint == Palette.pastelWatch.work)
        #expect(SetupField.rest.editor(value: .constant(30)).tint == Theme.rest)
    }

    @Test("The completion screen is the brand colour fading deeper: blue in Classic, pink in Pastel")
    func completionGradient() {
        #expect(Palette.classic.brand == Theme.work)
        #expect(Palette.classic.brandDeep == Theme.brandDeep)
        #expect(Palette.pastelWatch.brand == Palette.pastelWatch.work)
        #expect(Palette.pastelWatch.brandDeep == Palette.pastelWatch.workDimmed)
        #expect(Palette.pastelWatch.brand != Theme.work)
    }

    @Test("Pastel's accent is its pink, for titles only: the watch's root sets no tint to fill its glass")
    func accent() {
        #expect(Palette.pastelWatch.accent == Palette.pastelWatch.work)
        #expect(Palette.pastelWatch.glassTint == nil)
        #expect(Palette.classic.accent == nil)
    }

    @Test("Setup's pages are titled as before")
    func pageTitles() {
        #expect((0...2).map(SetupView.pageTitle) == ["", "Intervals", "Warm & Cool"])
    }
}
