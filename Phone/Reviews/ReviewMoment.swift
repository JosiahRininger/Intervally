//
//  ReviewMoment.swift
//  IntervallyPhone
//

import SwiftUI

/// A moment the iPhone app may ask for an App Store rating.
///
/// Only Apple's own prompt is allowed (Guideline 5.6.1 rules out custom prompts, and with
/// them any "Enjoying Intervally?" gate in front of it), the watch has none at all
/// (`RequestReviewAction` is unavailable on watchOS), and the system shows it at most three
/// times a year whatever the app asks. So the iPhone asks rarely, and only once someone has
/// trained with Intervally for real.
enum ReviewMoment: Equatable, Sendable {
    /// Done, after a workout finished on this iPhone: the best moment there is. `count`
    /// includes the one just finished.
    case finishedWorkout(count: Int)
    /// Back from a session in History: a workout's payoff, seen on the iPhone.
    case lookedBackAtSession(sessionCount: Int)
    /// Just after Put on Watch, the iPhone's own job done. For the people who never connect
    /// Health, whose sessions the iPhone can't see.
    case sentToWatch
    /// Back on the library after buying Pro on this iPhone: someone who just chose to pay.
    case paidForPro

    /// What is in front as a request lands, as far as the prompt is concerned.
    enum Screen: Equatable, Sendable {
        /// The Workouts library, with no editor pushed and no sheet or question over it.
        case library
        /// History: its sessions, or one session's summary, with no sheet over them.
        case summary
        /// Anything else: an editor, Settings, the paywall, the welcome.
        case other
    }

    /// Whether the prompt may appear now. It lands on whatever is in front, so it waits for a
    /// screen it can't interrupt: the library or History, with the app in front and no run
    /// going or on screen, here or from the watch. A finished run's summary counts as on
    /// screen: Done closes it first. Once a version, whatever the moment.
    static func canPresent(
        runActive: Bool, scenePhase: ScenePhase, topScreen: Screen, lastPromptVersion: String?, currentVersion: String
    ) -> Bool {
        guard !runActive, scenePhase == .active, lastPromptVersion != currentVersion else { return false }
        switch topScreen {
        case .library, .summary: return true
        case .other: return false
        }
    }
}
