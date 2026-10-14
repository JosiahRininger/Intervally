//
//  AuditExceptions.swift
//  IntervallyPhoneUITests
//

import XCTest

/// What the accessibility audit reports that is so by design, each with its reason. Kept
/// narrow on purpose: a finding outside these fails until it is fixed or argued for here.
/// Element descriptions, hit regions and traits have no exceptions; element detection only
/// the system wheel's (`Allowances.wheels`).
enum AuditExceptions {
    /// What a screen is known to show that the audit can't place on an element of its own.
    struct Allowances: OptionSet {
        let rawValue: Int
        /// A list longer than the screen, running under the tab bar or a pinned footer, which
        /// the system fades on purpose. Its rows are one element each, so a faded row's text
        /// comes back with no element to test the position of.
        static let contentUnderBars = Allowances(rawValue: 1 << 0)
        /// The system's wheel picker, which draws the rows around the chosen one as text that
        /// VoiceOver never reads: it reads the chosen value and adjusts it, by Apple's design.
        static let wheels = Allowances(rawValue: 1 << 1)
        /// The run screen's "5:15 left" (see `isKnown`), which the audit sometimes reports
        /// with no element to name it by: there, read with the header it belongs to.
        static let timeLeft = Allowances(rawValue: 1 << 2)
    }

    @MainActor
    /// `scrollFrames`: the screen's scroll views, measured before the audit, which has a time
    /// limit that a query of the whole tree per finding can run past.
    static func isKnown(_ issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication, scrollFrames: [CGRect], allowing allowances: Allowances = []) -> Bool {
        let label = issue.element?.label ?? ""
        if issue.element == nil {
            switch issue.auditType {
            case .contrast: return allowances.contains(.contentUnderBars) || allowances.contains(.timeLeft)
            case .elementDetection: return allowances.contains(.wheels)
            // Text inside a tile or a row, which VoiceOver reads as one element, that shrinks
            // to fit its line: the phase names and the settings' subtitles.
            case .textClipped: return true
            default: return false
            }
        }
        switch issue.auditType {
        case .dynamicType:
            // Grows with the text up to the largest standard size, then stops so the layout
            // holds: the editor's tiles, the session's stat cards, the run screen's header,
            // and the system's own bar buttons (Edit, Cancel). The largest-text pass checks
            // those screens for clipping instead.
            if issue.compactDescription.localizedCaseInsensitiveContains("partially") { return true }
            // Drawn to a ring's size: its digits and words would overflow it if they grew,
            // and VoiceOver reads the ring as one summary while the tiles and cards beside it
            // carry the same values at any size.
            return isRingText(label)
        case .textClipped:
            // Shrinks to fit its line rather than truncating: the ring's text and the phase
            // names on tiles and buttons, which a long custom name or a large text size
            // narrows. Checked by eye at every size in the release passes.
            return isRingText(label) || label.contains(" · ") || shrinksToFit.contains(label)
                || label.hasPrefix("Start") || wrapsWhenLarger.contains(label.lowercased())
        case .contrast:
            // The run screen's "5:15 left", .secondary on black: 6.4:1 measured from a
            // screenshot (141,141,147 on 0,0,0), well over 4.5:1, yet the audit fails it on
            // one iPhone or another, whatever its colour: at 72% white, 10.6:1, it failed just
            // the same (2026-10-14).
            if label.wholeMatch(of: /\d+:\d{2} left/) != nil { return true }
            // Under a bar or a sheet: content scrolled beneath the tab bar, a pinned bar or a
            // sheet's bottom edge is faded by the system on purpose, and the screen behind a
            // sheet is dimmed. Measured from the bottom of the scroll view the text is in, so
            // an iPad's form sheet counts from its own bottom, not the window's.
            guard let frame = issue.element?.frame else { return false }
            return frame.minY > bottomEdge(of: frame, among: scrollFrames, in: app) - 160
        default:
            return false
        }
    }

    /// Every scroll view on screen, for `bottomEdge`.
    @MainActor
    static func scrollFrames(in app: XCUIApplication) -> [CGRect] {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "elementType IN %@",
            [XCUIElement.ElementType.scrollView, .collectionView, .table].map(\.rawValue)
        )).allElementsBoundByIndex.map(\.frame)
    }

    /// The bottom of the smallest scroll view holding `frame`'s middle; the window's without one.
    @MainActor
    static func bottomEdge(of frame: CGRect, among scrollFrames: [CGRect], in app: XCUIApplication) -> CGFloat {
        let middle = CGPoint(x: frame.midX, y: frame.midY)
        let holding = scrollFrames.filter { $0.contains(middle) }
        return holding.min { $0.height < $1.height }?.maxY ?? app.windows.firstMatch.frame.maxY
    }

    /// The phase names a tile, a picker's title or the run screen shows, which shrink rather
    /// than wrap.
    static let shrinksToFit: Set<String> = ["Work", "Rest", "Rounds", "Get Ready", "Warmup", "Cooldown"]

    /// The session's stat captions, which the audit expects to clip at larger sizes on an
    /// iPhone SE but which have no line limit and wrap onto a second line (checked there at
    /// the largest standard size, the cards' own limit).
    static let wrapsWhenLarger: Set<String> = ["duration", "avg heart rate", "max heart rate", "active calories"]

    /// A clock ("5:55"), rounds ("8/8"), "Round 3 of 8", or a ring's word ("TOTAL", "REST").
    static func isRingText(_ label: String) -> Bool {
        let words: Set<String> = ["total", "rounds", "work", "rest", "get ready", "warmup", "cooldown", "paused"]
        return label.wholeMatch(of: /\d{1,2}:\d{2}/) != nil
            || label.wholeMatch(of: /\d+\/\d+/) != nil
            || label.wholeMatch(of: /Round \d+ of \d+/) != nil
            || words.contains(label.lowercased())
    }
}
