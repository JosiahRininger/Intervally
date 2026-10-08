//
//  SharedDefaults.swift
//  Intervally
//

import Foundation

/// The defaults suite shared between the app and its widget extension.
///
/// Falls back to `.standard` if the App Group is not available — which happens when the
/// group has not been registered for the signing team yet. The app stays fully functional;
/// only the complication goes stale.
enum SharedDefaults {
    static let appGroup = "group.com.josiahrininger.intervally"

    /// Created once. `UserDefaults` is documented as thread-safe but is not marked
    /// `Sendable`, hence `nonisolated(unsafe)` — the alternative, a computed property,
    /// builds a fresh suite on every access, which is both wasteful and crash-prone when
    /// it lands during `App.init()`.
    nonisolated(unsafe) static let suite: UserDefaults = UserDefaults(suiteName: appGroup) ?? .standard

    /// False when the App Group is not provisioned, in which case the app falls back to
    /// its own defaults and the complication cannot see the running workout.
    static let isSharing: Bool = UserDefaults(suiteName: appGroup) != nil
}
