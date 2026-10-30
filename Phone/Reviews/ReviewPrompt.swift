//
//  ReviewPrompt.swift
//  IntervallyPhone
//

import Foundation
import Observation
import SwiftUI

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
        case .finishedWorkout(let count): return count >= minimumSessions
        case .lookedBackAtSession(let count): return count >= minimumSessions
        case .sentToWatch: return ledger.activeDays >= minimumActiveDays
        // Paying for Pro is use enough, with no count of its own to reach.
        case .paidForPro: return true
        }
    }

    private static func days(from start: Date, to end: Date, _ calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}

/// What the cadence needs to remember, on this iPhone only: never synced, never sent. And,
/// for this launch only, what is in front, so a request lands only where it interrupts
/// nothing (`ReviewMoment.canPresent`).
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

    /// The app's scene, as the app reports it.
    @ObservationIgnored var scenePhase = ScenePhase.active
    /// Whether a run is going or on screen, here or from the watch. `PhoneServices` wires it
    /// to the run.
    @ObservationIgnored var runIsActive: @MainActor () -> Bool = { false }
    /// How long a request waits after its moment, so the prompt never lands mid-transition.
    @ObservationIgnored var requestDelay = Duration.seconds(1)
    /// The tab in front, once the tabs show: none on the welcome.
    @ObservationIgnored private var tab: PhoneTab?
    /// What each tab has in front, as it last said.
    @ObservationIgnored private var screens: [PhoneTab: ReviewMoment.Screen] = [:]
    /// The request a purchase of Pro here earned, until a return to the library makes it.
    @ObservationIgnored private var purchaseRequest: (@MainActor () -> Void)?

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

    // MARK: - Landing

    /// What is in front: the front tab's own report, and nothing calm before the tabs show.
    var topScreen: ReviewMoment.Screen {
        tab.flatMap { screens[$0] } ?? .other
    }

    /// Whether a prompt could land right now.
    var canPresentNow: Bool {
        ReviewMoment.canPresent(
            runActive: runIsActive(), scenePhase: scenePhase, topScreen: topScreen,
            lastPromptVersion: snapshot.lastRequestVersion, currentVersion: Self.appVersion
        )
    }

    /// A purchase of Pro here is still waiting for its return to the library.
    var paidForPro: Bool { purchaseRequest != nil }

    /// `tab` now has `screen` in front: its own, or something over it. Returns the request a
    /// return to the library made, if it made one, for the tests to wait on.
    @discardableResult
    func show(_ screen: ReviewMoment.Screen, in tab: PhoneTab) -> Task<Void, Never>? {
        let before = topScreen
        screens[tab] = screen
        return frontChanged(from: before)
    }

    /// `tab` is now the one in front.
    @discardableResult
    func select(_ tab: PhoneTab) -> Task<Void, Never>? {
        let before = topScreen
        self.tab = tab
        return frontChanged(from: before)
    }

    /// A purchase of Pro just went through on this iPhone. Its paywall is still up, so the
    /// request waits for the next return to the library.
    func markPaidForPro(request: @escaping @MainActor () -> Void) {
        purchaseRequest = request
    }

    /// Asks for `moment` through `request` once `requestDelay` has passed, if a prompt can
    /// land then and `ReviewPolicy` says the moment is a good one.
    @discardableResult
    func askLater(_ moment: ReviewMoment, request: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        land { self.ask(moment, request: request) }
    }

    /// Back on the library, where a purchase asks. Only a return still in front as its
    /// request lands spends the purchase: + at the free limit passes the library on its way
    /// from the paywall to the new workout's editor.
    private func frontChanged(from before: ReviewMoment.Screen) -> Task<Void, Never>? {
        guard topScreen == .library, before != .library, purchaseRequest != nil else { return nil }
        return land {
            // An earlier return may have asked already.
            guard let request = self.purchaseRequest else { return }
            self.purchaseRequest = nil
            self.ask(.paidForPro, request: request)
        }
    }

    /// Runs `fire` once `requestDelay` has passed, if a prompt can land then. The wait is long
    /// enough to start a run, open a sheet or lock the phone, so this is checked as the
    /// request lands, not as it is made. One that can't land is dropped, and spends nothing.
    private func land(_ fire: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        let delay = requestDelay
        return Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard self.canPresentNow else { return }
            fire()
        }
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
