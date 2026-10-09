//
//  ReviewPromptTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// When the iPhone asks for an App Store rating, and how often: rarely, after real use, once
/// a version, and never from a QA launch.
@Suite("Review prompts")
@MainActor
struct ReviewPromptTests {
    let calendar = Calendar(identifier: .gregorian)
    let day0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func day(_ n: Int) -> Date { day0.addingTimeInterval(Double(n) * 86_400) }

    private func ledger() -> ReviewLedger {
        ReviewLedger(defaults: makeTestDefaults(), calendar: calendar)
    }

    /// A ledger opened on `days` distinct days, starting on day 0.
    private func ledger(openedOn days: [Int]) -> ReviewLedger {
        let ledger = ledger()
        days.forEach { ledger.recordOpen(now: day($0)) }
        return ledger
    }

    @Test("Never in the first three days, however much it is used")
    func notTooSoon() {
        let reviews = ledger(openedOn: [0, 1, 2])
        var asked = 0
        reviews.ask(.lookedBackAtSession(sessionCount: 10), version: "1.0", now: day(2)) { asked += 1 }
        #expect(asked == 0)
        reviews.ask(.lookedBackAtSession(sessionCount: 10), version: "1.0", now: day(3)) { asked += 1 }
        #expect(asked == 1)
    }

    @Test("Back from a session, only after three of them", arguments: [(2, false), (3, true), (12, true)])
    func afterThreeSessions(sessions: Int, asks: Bool) {
        let snapshot = ledger(openedOn: [0]).snapshot
        #expect(ReviewPolicy.shouldAsk(.lookedBackAtSession(sessionCount: sessions), ledger: snapshot, version: "1.0", now: day(5), calendar: calendar) == asks)
    }

    @Test("After Put on Watch, only once the app has been opened on five different days")
    func afterFiveActiveDays() {
        let four = ledger(openedOn: [0, 1, 2, 3]).snapshot
        let five = ledger(openedOn: [0, 1, 2, 3, 4]).snapshot
        #expect(!ReviewPolicy.shouldAsk(.sentToWatch, ledger: four, version: "1.0", now: day(6), calendar: calendar))
        #expect(ReviewPolicy.shouldAsk(.sentToWatch, ledger: five, version: "1.0", now: day(6), calendar: calendar))
    }

    @Test("Opening the app again the same day isn't another active day")
    func sameDayCountsOnce() {
        let reviews = ledger()
        reviews.recordOpen(now: day(0))
        reviews.recordOpen(now: day(0).addingTimeInterval(3_600))
        reviews.recordOpen(now: day(1))
        #expect(reviews.snapshot.activeDays == 2)
        #expect(reviews.snapshot.firstOpened == day(0), "The first open is kept, never moved")
    }

    @Test("Once a version, and never twice within 120 days, even across versions")
    func cadence() {
        let reviews = ledger(openedOn: [0])
        var asked = 0
        let moment = ReviewMoment.lookedBackAtSession(sessionCount: 5)
        #expect(reviews.ask(moment, version: "1.0", now: day(10)) { asked += 1 })
        #expect(!reviews.ask(moment, version: "1.0", now: day(300)) { asked += 1 }, "Same version")
        #expect(!reviews.ask(moment, version: "1.1", now: day(100)) { asked += 1 }, "Too soon")
        #expect(reviews.ask(moment, version: "1.1", now: day(130)) { asked += 1 })
        #expect(asked == 2)
    }

    @Test("What it remembers survives a relaunch")
    func persists() {
        let defaults = makeTestDefaults()
        let first = ReviewLedger(defaults: defaults, calendar: calendar)
        first.recordOpen(now: day(0))
        first.ask(.lookedBackAtSession(sessionCount: 5), version: "1.0", now: day(4)) {}
        let again = ReviewLedger(defaults: defaults, calendar: calendar).snapshot
        #expect(again.firstOpened == day(0))
        #expect(again.lastRequestVersion == "1.0")
        #expect(again.lastRequest == day(4))
    }

    @Test("A QA launch never asks: a prompt would land on a screenshot")
    func suppressed() {
        let reviews = ledger(openedOn: [0])
        reviews.isSuppressed = true
        var asked = false
        #expect(!reviews.ask(.lookedBackAtSession(sessionCount: 9), version: "1.0", now: day(9)) { asked = true })
        #expect(!asked)
        #expect(reviews.snapshot.lastRequest == nil, "Nothing is spent on a suppressed ask")
    }

    @Test("Any QA flag marks the launch as driven", arguments: [
        ["-qaPro", "free"], ["-qaHistory", "sample"], ["-qaWelcome", "YES"], ["-qaOpen", "editor"],
    ])
    func qaLaunchesAreActive(arguments: [String]) {
        #expect(PhoneQAOptions.parse(["IntervallyPhone"] + arguments).isActive)
        #expect(!PhoneQAOptions.parse(["IntervallyPhone"]).isActive)
    }

    @Test("Rate opens this app's Write a Review page; Feedback drafts mail with the versions")
    func links() throws {
        let review = try #require(ReviewLinks.writeReview)
        #expect(review.absoluteString == "https://apps.apple.com/app/id6821077261?action=write-review")
        let mail = try #require(ReviewLinks.feedbackMail(appVersion: "1.0 (1)", systemVersion: "26.3"))
        #expect(mail.scheme == "mailto")
        let parts = try #require(URLComponents(url: mail, resolvingAgainstBaseURL: false))
        #expect(parts.path == "josiahrininger@gmail.com")
        #expect(parts.queryItems?.first { $0.name == "subject" }?.value == "Intervally feedback")
        #expect(parts.queryItems?.first { $0.name == "body" }?.value?.contains("Intervally 1.0 (1), iOS 26.3") == true)
    }
}
