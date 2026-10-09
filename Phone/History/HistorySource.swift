//
//  HistorySource.swift
//  IntervallyPhone
//

import Foundation

/// Whether to offer Connect Apple Health. A denial to read is invisible by design: HealthKit
/// only says whether the user has been asked, so that is all this can say.
enum HistoryAccess: Equatable, Sendable {
    /// Never asked: History offers Connect Apple Health.
    case shouldRequest
    /// Asked already, whatever the answer. Reading just finds nothing if it was no.
    case requested
    /// HealthKit couldn't say.
    case unknown
}

/// Where History's sessions come from: Apple Health (`HealthHistory`), or in Debug builds
/// the `-qaHistory` fixture, which writes nothing to Health.
protocol HistorySource: Sendable {
    /// Whether this device has Health at all.
    var isAvailable: Bool { get }
    func access() async -> HistoryAccess
    /// Shows Health's own sheet if there is anything left to ask.
    func requestAccess() async throws
    /// Intervally's sessions, newest first.
    func workouts() async throws -> [RawWorkout]
}
