//
//  HistoryModel.swift
//  IntervallyPhone
//

import Foundation
import Observation
import os

/// History's state: whether there is Health to read, whether to offer Connect, and the
/// sessions once read.
///
/// It reads when History first appears, then again each time it appears, the app comes
/// forward or the list is pulled. A launch that never opens History never touches HealthKit.
@MainActor
@Observable
final class HistoryModel {
    enum State: Equatable {
        /// The first read hasn't answered yet.
        case loading
        /// No Health on this device. Everything else in the app works without it.
        case unavailable
        /// Never asked: Connect Apple Health.
        case needsAccess
        /// Asked, and nothing to show. Says where workouts come from, never that access was
        /// denied, which HealthKit doesn't disclose.
        case empty
        case loaded
        /// The read failed with nothing read before it. Health can't be read while the
        /// iPhone is locked, for one.
        case failed
    }

    private(set) var state: State = .loading
    /// Newest first.
    private(set) var sessions: [SessionSummary] = []
    private(set) var weeks: [SessionWeek] = []
    /// Health's sheet is up, or the read after it is under way.
    private(set) var isConnecting = false

    @ObservationIgnored private let source: any HistorySource
    @ObservationIgnored private let calendar: Calendar
    /// Bumped by every read, so an older read that answers late can't overwrite a newer one.
    @ObservationIgnored private var generation = 0
    /// Whether History has been opened, so coming forward only re-reads for someone who has.
    @ObservationIgnored private(set) var hasAppeared = false
    @ObservationIgnored private let log = Logger(subsystem: "com.josiahrininger.intervally", category: "history")

    init(source: any HistorySource, calendar: Calendar = .current) {
        self.source = source
        self.calendar = calendar
    }

    /// History is on screen.
    func appear() async {
        hasAppeared = true
        await refresh()
    }

    /// The app came forward. A workout the watch saved meanwhile may have arrived.
    func handleForeground() async {
        guard hasAppeared else { return }
        await refresh()
    }

    func refresh() async {
        generation += 1
        let mine = generation
        guard source.isAvailable else {
            apply([], state: .unavailable)
            return
        }
        let access = await source.access()
        guard mine == generation else { return }
        if access == .shouldRequest {
            apply([], state: .needsAccess)
            return
        }
        do {
            let found = try await source.workouts().map(SessionSummary.init)
            guard mine == generation else { return }
            if !found.isEmpty {
                apply(found.sorted { $0.start > $1.start }, state: .loaded)
            } else {
                // HealthKit couldn't say whether it ever asked. Connect is harmless if it
                // did, and the only way in if it didn't.
                apply([], state: access == .unknown ? .needsAccess : .empty)
            }
        } catch {
            guard mine == generation else { return }
            log.error("could not read history: \(error.localizedDescription, privacy: .public)")
            // Sessions already on screen stay: a locked iPhone hasn't deleted them.
            if sessions.isEmpty { apply([], state: .failed) }
        }
    }

    /// Connect Apple Health: Health's own sheet, then a read of whatever it allowed.
    func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await source.requestAccess()
        } catch {
            log.error("health authorization failed: \(error.localizedDescription, privacy: .public)")
        }
        await refresh()
    }

    private func apply(_ sessions: [SessionSummary], state: State) {
        self.sessions = sessions
        self.weeks = SessionWeek.group(sessions, calendar: calendar)
        self.state = state
    }
}
