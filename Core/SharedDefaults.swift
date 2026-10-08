//
//  SharedDefaults.swift
//  Intervally
//

import Foundation

/// The defaults suite the app's model and Pro cache live in.
///
/// On the watch it is the App Group shared with the widget extension, falling back to
/// `.standard` if the group is not available — which happens when it has not been
/// registered for the signing team yet. The app stays fully functional; only the
/// complication goes stale.
///
/// On iPhone it is always `.standard`. A group container never crosses devices, so a group
/// could never reach the watch, and the iPhone app has no extension to share with. What an
/// unentitled `UserDefaults(suiteName:)` returns on iOS isn't something to depend on either.
enum SharedDefaults {
    #if os(watchOS)
    static let appGroup = "group.com.josiahrininger.intervally"

    /// Created once. `UserDefaults` is documented as thread-safe but is not marked
    /// `Sendable`, hence `nonisolated(unsafe)` — the alternative, a computed property,
    /// builds a fresh suite on every access, which is both wasteful and crash-prone when
    /// it lands during `App.init()`.
    nonisolated(unsafe) static let suite: UserDefaults = UserDefaults(suiteName: appGroup) ?? .standard

    /// False when the App Group is not provisioned, in which case the app falls back to
    /// its own defaults and the complication cannot see the running workout.
    static let isSharing: Bool = UserDefaults(suiteName: appGroup) != nil
    #else
    /// The app's own defaults. `nonisolated(unsafe)` for the same reason as on the watch.
    nonisolated(unsafe) static let suite: UserDefaults = .standard

    /// Never: nothing else on the iPhone reads these defaults.
    static let isSharing = false
    #endif
}
