//
//  PhaseWordTests.swift
//  IntervallyTests
//

import SwiftUI
import Testing
@testable import Intervally

/// The phase word fits the run ring's line whole on every watch, COOLDOWN on a 40mm included.
@Suite("Phase word")
@MainActor
struct PhaseWordTests {
    /// The line the word sits on: the ring's chord near the top of its interior, as RunView
    /// measures it.
    private func line(on screen: CGSize) -> CGFloat {
        let dial = DialLayout(screen: screen)
        return dial.chord(atOffset: 0.4 * dial.interior)
    }

    /// A word's natural width in one style, uppercased as drawn.
    private func width(_ word: String, _ style: PhaseWord.Style, textSize: DynamicTypeSize) throws -> CGFloat {
        let renderer = ImageRenderer(content: PhaseWord.text(word, style).fixedSize().environment(\.dynamicTypeSize, textSize))
        let image = try #require(renderer.cgImage)
        return CGFloat(image.width) / renderer.scale
    }

    static let words = ([.prepare, .warmup, .work, .rest, .cooldown] as [IntervalPhase.Kind]).map(\.shortTitle) + ["Paused"]
    static let screen40 = CGSize(width: 162, height: 197)
    /// Large is the 40mm default text size; xLarge (the 46mm default) covers a 40mm set one up.
    nonisolated static let textSizes: [DynamicTypeSize] = [.large, .xLarge]

    /// The old label asked a tracked Text to shrink to 0.65, which would have fit (about
    /// 51pt on a 53pt line); it truncated instead, so a tracked Text isn't trusted to shrink.
    /// The fallback drops the tracking before it shrinks.
    @Test("As set, COOLDOWN is wider than a 40mm ring's line: the truncation this fixes")
    func cooldownOverflowsAsSet() throws {
        #expect(try width("Cooldown", PhaseWord.tracked, textSize: .large) > line(on: Self.screen40))
    }

    @Test("On a 40mm, every phase word fits whole: tracked as set, or untracked within the shrink floor", arguments: textSizes)
    func everyWordFitsOn40mm(textSize: DynamicTypeSize) throws {
        let line = line(on: Self.screen40)
        for word in Self.words {
            let tracked = try width(word, PhaseWord.tracked, textSize: textSize)
            let untracked = try width(word, PhaseWord.untracked, textSize: textSize)
            #expect(tracked <= line || untracked * PhaseWord.smallestScale <= line, "\(word) at \(textSize): \(tracked)/\(untracked) vs \(line)")
        }
    }

    /// A preset's own names, at the longest a name can be (`PhaseLabel.maxNameLength`).
    @Test("On a 40mm, a ten-letter name of the preset's own fits whole within the shrink floor")
    func longestNamesFitOn40mm() throws {
        let line = line(on: Self.screen40)
        for word in ["Kettlebell", "Wall Balls", "Recovery J", "Burpee Box"] {
            #expect(word.count <= PhaseLabel.maxNameLength)
            let untracked = try width(word, PhaseWord.untracked, textSize: .large)
            #expect(untracked * PhaseWord.smallestScale <= line, "\(word): \(untracked) × \(PhaseWord.smallestScale) vs \(line)")
        }
    }

    @Test("Short words keep the tracked style and full size on every watch")
    func shortWordsKeepTheirStyle() throws {
        for screen in [Self.screen40, CGSize(width: 208, height: 248)] {
            for word in ["Work", "Rest"] {
                #expect(try width(word, PhaseWord.tracked, textSize: .large) <= line(on: screen), "\(word)")
            }
        }
    }

    @Test("On a 46mm, COOLDOWN needs far less shrinking than on a 40mm")
    func cooldownOn46mm() throws {
        let untracked = try width("Cooldown", PhaseWord.untracked, textSize: .xLarge)
        #expect(line(on: CGSize(width: 208, height: 248)) / untracked > line(on: Self.screen40) / untracked)
    }
}
