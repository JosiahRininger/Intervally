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
    /// Seconds between the boundary and its announcement. The ticker alone accounts for a few
    /// milliseconds, as it wakes just past each boundary; a catch-up after a suspension for
    /// far more.
    var lateness: TimeInterval
    /// How long the phase that just began will run; nil for the finish, which has nothing
    /// after it to keep clear of.
    var phaseDuration: TimeInterval?

    /// On time, with nothing after it: a countdown tick.
    static let immediate = BoundaryContext(lateness: 0, phaseDuration: nil)
}

/// How late a run's boundaries were announced, summed up in one line for its diagnostics
/// when it ends. A boundary noticed past `lateThreshold`, a catch-up after a suspension,
/// didn't get its usual cue, so the line counts those apart.
struct BoundaryTimingTally: Equatable, Sendable {
    /// Whose cues the line is about: a late boundary costs each device something different.
    enum Device: Equatable, Sendable {
        /// iPhone and iPad: nothing plays (`CuePlan.lateThreshold`).
        case phone
        /// Apple Watch: one tap plays instead of the whole pattern (`Haptics.lateThreshold`).
        case watch

        static var current: Device {
            #if os(watchOS)
            .watch
            #else
            .phone
            #endif
        }
    }

    /// A cap, so a run of any length keeps a tally of a bounded size. Past it the median rests
    /// on the first thousand, while the count, the slowest and the late ones keep counting.
    static let sampleLimit = 1_000

    let lateThreshold: TimeInterval
    let device: Device
    private(set) var samples: [TimeInterval] = []
    private(set) var count = 0
    private(set) var slowest: TimeInterval = 0
    /// Boundaries later than `lateThreshold`: their cue didn't play as usual.
    private(set) var late = 0

    init(lateThreshold: TimeInterval, device: Device = .current) {
        self.lateThreshold = lateThreshold
        self.device = device
    }

    mutating func record(lateness: TimeInterval) {
        count += 1
        slowest = max(slowest, lateness)
        if lateness > lateThreshold { late += 1 }
        if samples.count < Self.sampleLimit { samples.append(lateness) }
    }

    /// Everything recorded in one line, with the tally started again; nil if there was nothing.
    mutating func close() -> String? {
        defer { self = BoundaryTimingTally(lateThreshold: lateThreshold, device: device) }
        guard count > 0 else { return nil }
        let boundaries = count == 1 ? "1 boundary" : "\(count) boundaries"
        let cost = switch device {
        case .phone: "nothing played for those"
        case .watch: "one tap instead of the full pattern"
        }
        return "Run timing: \(boundaries), median \(Self.seconds(median, places: 2)) s late, "
            + "max \(Self.seconds(slowest, places: 2)) s; "
            + "\(late) over \(Self.seconds(lateThreshold, places: 1)) s (\(cost))"
    }

    private var median: TimeInterval {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// The same figures in any region: the line is read wherever it is shared.
    private static func seconds(_ value: TimeInterval, places: Int) -> String {
        String(format: "%.\(places)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
