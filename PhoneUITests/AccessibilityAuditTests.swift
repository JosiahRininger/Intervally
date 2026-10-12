//
//  AccessibilityAuditTests.swift
//  IntervallyPhoneUITests
//

import XCTest

/// Apple's accessibility audit (`performAccessibilityAudit`) on every main iPhone screen, each
/// opened straight from launch with the debug build's QA flags (`PhoneQAOptions`), as the
/// screenshots are. The audit checks contrast, element descriptions, hit regions, traits,
/// Dynamic Type and clipped text; anything it finds fails the test, apart from the
/// exceptions in `AuditExceptions`, each with its reason.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        // iPad shows these same screens, but as glass sheets over the screen behind them,
        // which the audit can't measure contrast or reach against: it fails plain body text
        // there. The iPhone runs audit every screen; `EditorFitTests` still runs on iPad.
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "Audited on iPhone: iPad's sheets are glass the audit can't measure against")
    }

    // MARK: - Workouts

    func testWorkouts() throws {
        let app = PhoneApp.launch()
        XCTAssertTrue(app.staticTexts["Workouts"].waitForExistence(timeout: 10))
        try audit(app, allowing: shortScreenAllowances(app))
    }

    func testWelcome() throws {
        let app = PhoneApp.launch(["-qaWelcome", "YES"])
        _ = app.buttons.firstMatch.waitForExistence(timeout: 10)
        try audit(app)
    }

    func testPaywall() throws {
        let app = PhoneApp.launch(["-qaOpen", "paywall"])
        XCTAssertTrue(app.staticTexts["Intervally Pro"].firstMatch.waitForExistence(timeout: 10))
        try audit(app)
    }

    // MARK: - Editor

    /// The pinned Start's hard scroll edge begins a few points above it, where Warmup and
    /// Cooldown end on a 6.3-inch iPhone and under which they scroll on an SE; that the tiles
    /// clear Start itself is `EditorFitTests`' to check.
    func testEditor() throws {
        let app = PhoneApp.launch(["-qaOpen", "editor"])
        XCTAssertTrue(app.buttons["Work"].waitForExistence(timeout: 10))
        try audit(app, allowing: .contentUnderBars)
    }

    func testEditorWithPro() throws {
        let app = PhoneApp.launch(["-qaOpen", "editor"], pro: true)
        XCTAssertTrue(app.buttons["Warmup"].waitForExistence(timeout: 10))
        try audit(app, allowing: .contentUnderBars)
    }

    /// On an iPhone too short for the whole library (an SE), the last workouts scroll under
    /// the tab bar; on every other iPhone they fit, so nothing is allowed there.
    private func shortScreenAllowances(_ app: XCUIApplication) -> AuditExceptions.Allowances {
        app.windows.firstMatch.frame.height < EditorFitTests.shortestFittingScreen ? .contentUnderBars : []
    }

    func testDurationPicker() throws {
        let app = PhoneApp.launch(["-qaOpen", "picker"])
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 10))
        try audit(app, allowing: .wheels)
    }

    func testNameAndIcon() throws {
        let app = PhoneApp.launch(["-qaOpen", "picker"])
        let rename = app.buttons["Work, rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 10))
        rename.tap()
        XCTAssertTrue(app.navigationBars["Name & Icon"].waitForExistence(timeout: 5))
        try audit(app)
    }

    func testActivityPicker() throws {
        let app = PhoneApp.launch(["-qaOpen", "editor"])
        let activity = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Activity, '")).firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 10))
        activity.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        try audit(app, allowing: .contentUnderBars)
    }

    // MARK: - Run

    /// The run screen as it shows a run on the watch: the same screen and controls, with no
    /// workout session of the iPhone's own, so no Health or notification prompt can stand in
    /// the way and no session can outlive the test. Paused, so nothing on it is mid-tick: a
    /// countdown caught halfway through its change of digit reads as faint.
    func testRunScreen() throws {
        let app = PhoneApp.launch(["-qaWatchRun", "paused", "-qaRunElapsed", "40"], pro: true)
        let end = app.buttons["End Workout"]
        XCTAssertTrue(end.waitForExistence(timeout: 15))
        try audit(app)
        PhoneApp.endRun(app)
    }

    // MARK: - Settings

    func testSettings() throws {
        try auditScreen(["-qaOpen", "settings"], expecting: "Settings")
    }

    func testSoundsAndVoice() throws {
        try auditScreen(["-qaOpen", "sounds"], expecting: "Sounds & Voice", pro: true)
    }

    func testTheme() throws {
        try auditScreen(["-qaOpen", "theme"], expecting: "Theme")
    }

    func testIntervallyPro() throws {
        try auditScreen(["-qaOpen", "pro"], expecting: "Intervally Pro")
    }

    func testAppleWatch() throws {
        try auditScreen(["-qaOpen", "watch"], expecting: "Apple Watch")
    }

    func testAppleHealth() throws {
        try auditScreen(["-qaOpen", "health"], expecting: "Apple Health")
    }

    // MARK: - History

    func testHistory() throws {
        let app = PhoneApp.launch(["-qaHistory", "sample", "-qaOpen", "history"])
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 10) || app.buttons.element(boundBy: 2).waitForExistence(timeout: 1))
        try audit(app, allowing: .contentUnderBars)
    }

    func testEmptyHistory() throws {
        let app = PhoneApp.launch(["-qaHistory", "empty", "-qaOpen", "history"])
        _ = app.staticTexts.firstMatch.waitForExistence(timeout: 10)
        try audit(app)
    }

    func testSession() throws {
        let app = PhoneApp.launch(["-qaHistory", "sample", "-qaOpen", "session"])
        XCTAssertTrue(app.staticTexts["Classic"].firstMatch.waitForExistence(timeout: 10))
        try audit(app)
    }

    // MARK: - The largest text size

    /// The screens a person at the largest accessibility size spends their time in, audited
    /// there for clipped text and overlapping targets.
    func testLargestTextSize() throws {
        for flags in [["-qaOpen", "editor"], ["-qaOpen", "sounds"], ["-qaHistory", "sample", "-qaOpen", "session"]] {
            let app = PhoneApp.launch(flags + PhoneApp.largestText, pro: true)
            _ = app.buttons.firstMatch.waitForExistence(timeout: 10)
            // At this size every one of them is longer than the screen.
            try audit(app, allowing: .contentUnderBars)
        }
    }

    // MARK: - Helpers

    private func auditScreen(_ flags: [String], expecting title: String, pro: Bool = false) throws {
        let app = PhoneApp.launch(flags, pro: pro)
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10) || app.staticTexts[title].firstMatch.waitForExistence(timeout: 2), title)
        try audit(app)
    }

    private func audit(_ app: XCUIApplication, allowing allowances: AuditExceptions.Allowances = []) throws {
        // A screen pushed or presented at launch is still sliding in when its first element
        // exists; caught mid-way, its text reads as faint.
        Thread.sleep(forTimeInterval: 1.5)
        let scrollFrames = AuditExceptions.scrollFrames(in: app)
        try app.performAccessibilityAudit { issue in
            let known = AuditExceptions.isKnown(issue, in: app, scrollFrames: scrollFrames, allowing: allowances)
            if !known {
                print("AUDIT: \(issue.auditType) | \(issue.compactDescription) | \(issue.detailedDescription) | \(issue.element?.debugDescription.prefix(160) ?? "no element")")
            }
            return known
        }
    }
}

/// Launching the app as the QA flags open it.
@MainActor
enum PhoneApp {
    /// The largest accessibility text size, for one launch.
    static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    /// The welcome and the editor's first-run tip already seen, a watch paired and installed,
    /// Pro pinned on or off. `PhoneQAOptions` reads a flag's first occurrence, so these are
    /// never repeated in `flags`.
    static func launch(_ flags: [String] = [], pro: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-phone.welcomeSeen.v1", "YES", "-phone.editorTipSeen.v1", "YES",
            "-qaWatch", "installed", "-qaPro", pro ? "pro" : "free",
        ] + flags
        app.launch()
        return app
    }

    /// End, then End Workout in the confirmation.
    static func endRun(_ app: XCUIApplication) {
        let end = app.buttons["End Workout"].firstMatch
        guard end.waitForExistence(timeout: 5) else { return }
        end.tap()
        let confirm = app.buttons.matching(identifier: "End Workout").element(boundBy: 1)
        if confirm.waitForExistence(timeout: 3) { confirm.tap() } else if end.exists { end.tap() }
    }
}
