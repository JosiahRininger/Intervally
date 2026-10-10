//
//  RunCues.swift
//  Intervally
//

import Foundation

/// Transport feedback, named by intent so the run's seams never traffic in a device's own
/// vocabulary: a `WKHapticType` on the watch, a sound and a tap on iPhone.
enum TransportCue: Sendable {
    case start, stop
}

/// What only the coordinator knows about a boundary.
struct BoundaryContext: Equatable, Sendable {
    /// Seconds between the boundary and its announcement. The ticker alone accounts for up
    /// to half a second; a catch-up after a suspension for far more.
    var lateness: TimeInterval
    /// How long the phase that just began will run; nil for the finish, which has nothing
    /// after it to keep clear of.
    var phaseDuration: TimeInterval?

    /// On time, with nothing after it: a countdown tick.
    static let immediate = BoundaryContext(lateness: 0, phaseDuration: nil)
}
