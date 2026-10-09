//
//  ReviewPrompt.swift
//  IntervallyPhone
//

import Foundation
import Observation

/// A moment the iPhone app may ask for an App Store rating.
///
/// Only Apple's own prompt is allowed (Guideline 5.6.1 rules out custom prompts, and with
/// them any "Enjoying Intervally?" gate in front of it), the watch has none at all
/// (`RequestReviewAction` is unavailable on watchOS), and the system shows it at most three
/// times a year whatever the app asks. So the iPhone asks rarely, and only once someone has
/// trained with Intervally for real.
enum ReviewMoment: Equatable, Sendable {
    /// Back from a session in History: a workout's payoff, seen on the iPhone.
    case lookedBackAtSession(sessionCount: Int)
    /// Just after Put on Watch, the iPhone's own job done. For the people who never connect
    /// Health, whose sessions the iPhone can't see.
    case sentToWatch
}

/// When a moment is good enough to ask. Pure, so the cadence is tested rather than hoped for.
enum ReviewPolicy {
    /// Long enough to have trained more than once, not just to have explored.
    static let minimumDaysInstalled = 3
    static let minimumSessions = 3
    /// Distinct days the iPhone app was opened, for the moment without Health.
    static let minimumActiveDays = 5
    /// Beyond the system's own limit: a second ask comes with a new version, months later.
    static let minimumDaysBetweenRequests = 120

    static func shouldAsk(
        _ moment: ReviewMoment, ledger: ReviewLedger.Snapshot, version: String, now: Date, calendar: Calendar
    ) -> Bool {
        guard let firstOpened = ledger.firstOpened,
              days(from: firstOpened, to: now, calendar) >= minimumDaysInstalled,
              ledger.lastRequestVersion != version
        else { return false }
        if let last = ledger.lastRequest, days(from: last, to: now, calendar) < minimumDaysBetweenRequests {
            return false
        }
        switch moment {
        case .lookedBackAtSession(let count): return count >= minimumSessions
        case .sentToWatch: return ledger.activeDays >= minimumActiveDays
        }
    }

    private static func days(from start: Date, to end: Date, _ calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}

/// What the cadence needs to remember, on this iPhone only: never synced, never sent.
@MainActor
@Observable
final class ReviewLedger {
    struct Snapshot: Equatable {
        var firstOpened: Date?
        var activeDays = 0
        var lastActiveDay: Date?
        var lastRequest: Date?
        var lastRequestVersion: String?
    }

    enum Key {
        static let firstOpened = "phone.review.firstOpened"
        static let activeDays = "phone.review.activeDays"
        static let lastActiveDay = "phone.review.lastActiveDay"
        static let lastRequest = "phone.review.lastRequest"
        static let lastRequestVersion = "phone.review.lastRequestVersion"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    /// Debug launches with QA flags never ask: a prompt over a screenshot capture.
    @ObservationIgnored var isSuppressed = false

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    var snapshot: Snapshot {
        Snapshot(
            firstOpened: defaults.object(forKey: Key.firstOpened) as? Date,
            activeDays: defaults.integer(forKey: Key.activeDays),
            lastActiveDay: defaults.object(forKey: Key.lastActiveDay) as? Date,
            lastRequest: defaults.object(forKey: Key.lastRequest) as? Date,
            lastRequestVersion: defaults.string(forKey: Key.lastRequestVersion)
        )
    }

    /// The app was opened or came forward. Counts a day once, however often it is opened.
    func recordOpen(now: Date = .now) {
        if defaults.object(forKey: Key.firstOpened) == nil {
            defaults.set(now, forKey: Key.firstOpened)
        }
        let today = calendar.startOfDay(for: now)
        guard (defaults.object(forKey: Key.lastActiveDay) as? Date) != today else { return }
        defaults.set(today, forKey: Key.lastActiveDay)
        defaults.set(defaults.integer(forKey: Key.activeDays) + 1, forKey: Key.activeDays)
    }

    /// Asks through `request` if this moment is a good one, and remembers that it did. The
    /// system may still show nothing; the app counts the ask either way, so it never nags.
    @discardableResult
    func ask(_ moment: ReviewMoment, version: String = ReviewLedger.appVersion, now: Date = .now, request: () -> Void) -> Bool {
        guard !isSuppressed,
              ReviewPolicy.shouldAsk(moment, ledger: snapshot, version: version, now: now, calendar: calendar)
        else {
            return false
        }
        defaults.set(now, forKey: Key.lastRequest)
        defaults.set(version, forKey: Key.lastRequestVersion)
        request()
        return true
    }

    nonisolated static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

/// The App Store's own pages for a rating and for feedback the user chooses to send.
enum ReviewLinks {
    static let appID = "6821077261"
    /// Opens the App Store straight on Write a Review.
    static let writeReview = URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review")
    static let feedbackAddress = "josiahrininger@gmail.com"

    /// A mail draft with what helps answer it: the app version and the iOS version.
    static func feedbackMail(appVersion: String, systemVersion: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = feedbackAddress
        parts.queryItems = [
            URLQueryItem(name: "subject", value: "Intervally feedback"),
            URLQueryItem(name: "body", value: "\n\n—\nIntervally \(appVersion), iOS \(systemVersion)"),
        ]
        return parts.url
    }
}
