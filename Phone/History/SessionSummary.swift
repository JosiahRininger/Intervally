//
//  SessionSummary.swift
//  IntervallyPhone
//

import Foundation

/// One workout the watch saved to Health, as plain values: what `HealthHistory` reads out of
/// an `HKWorkout`, so everything worked out from it can be tested without HealthKit.
struct RawWorkout: Equatable, Sendable {
    /// One interval, from the workout activity the watch began at its boundary.
    struct Activity: Equatable, Sendable {
        /// `IntervalPhase.Kind`'s raw value, as the watch wrote it.
        var phase: String?
        var round: Int?
        var start: Date
        /// Recording time, pauses left out.
        var duration: TimeInterval
        /// Beats per minute.
        var averageHeartRate: Double?
        /// Kilocalories burned in this interval alone.
        var activeEnergy: Double? = nil
    }

    var id: UUID
    var start: Date
    /// Recording time, pauses left out.
    var duration: TimeInterval
    var presetName: String?
    var plannedRounds: Int?
    /// Beats per minute.
    var averageHeartRate: Double?
    var maximumHeartRate: Double?
    /// Kilocalories.
    var activeEnergy: Double?
    var activities: [Activity]
    /// What Health recorded it as; nil for a type the picker doesn't offer.
    var activity: WorkoutActivity? = nil
}

/// What History shows for one session, worked out here so the views only lay it out.
struct SessionSummary: Identifiable, Hashable, Sendable {
    /// One interval that ran.
    struct Interval: Identifiable, Hashable, Sendable {
        /// Its place in the session, from 0.
        let id: Int
        let kind: IntervalPhase.Kind
        /// Nil for the warmup and cooldown, which belong to no round.
        let round: Int?
        let duration: TimeInterval
        let averageHeartRate: Int?
        /// Whole kilocalories, rounded; nil when Health recorded none for it.
        var calories: Int? = nil

        /// "Work · Round 3", "Get Ready". Only work and rest name their round: the lead-in
        /// is tagged round 1, which nobody would call it.
        var title: String {
            guard kind == .work || kind == .rest, let round else { return kind.title }
            return "\(kind.title) · Round \(round)"
        }
    }

    /// The title of a workout saved without a usable preset name.
    static let fallbackTitle = "Interval workout"

    let id: UUID
    let start: Date
    let duration: TimeInterval
    let title: String
    /// The last round the run got to. Its highest round rather than a count of its work
    /// intervals: a run that only took its workout session after Health was granted mid-run
    /// has no activities for its first rounds, yet ran to the end.
    let roundsReached: Int
    /// Nil when the workout doesn't say, and then nothing is called an early end.
    let plannedRounds: Int?
    let averageHeartRate: Int?
    let maximumHeartRate: Int?
    /// Kilocalories.
    let activeEnergy: Double?
    /// In the order they ran. An activity whose phase this version doesn't know is left out.
    let intervals: [Interval]
    /// What Health recorded it as.
    let activity: WorkoutActivity?

    init(_ raw: RawWorkout) {
        id = raw.id
        start = raw.start
        duration = raw.duration
        let name = raw.presetName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        title = name.isEmpty ? Self.fallbackTitle : name
        plannedRounds = raw.plannedRounds.flatMap { $0 > 0 ? $0 : nil }
        averageHeartRate = raw.averageHeartRate.map { Int($0.rounded()) }
        maximumHeartRate = raw.maximumHeartRate.map { Int($0.rounded()) }
        activeEnergy = raw.activeEnergy
        activity = raw.activity

        let known = raw.activities
            .sorted { $0.start < $1.start }
            .compactMap { activity in activity.phase.flatMap(IntervalPhase.Kind.init(rawValue:)).map { (activity, $0) } }
        intervals = known.enumerated().map { index, pair in
            let (activity, kind) = pair
            return Interval(
                id: index,
                kind: kind,
                round: kind.isBookend ? nil : activity.round,
                duration: activity.duration,
                averageHeartRate: activity.averageHeartRate.map { Int($0.rounded()) },
                calories: activity.activeEnergy.map { Int($0.rounded()) }
            )
        }
        let work = intervals.filter { $0.kind == .work }
        roundsReached = work.compactMap(\.round).max() ?? work.count
    }

    var endedEarly: Bool {
        plannedRounds.map { roundsReached < $0 } ?? false
    }

    /// How much of the plan ran, for the white completion ring: 1 when the plan isn't known.
    var completion: Double {
        guard let plannedRounds else { return 1 }
        return min(1, Double(roundsReached) / Double(plannedRounds))
    }

    /// "5/8", or "8 rounds" when the plan isn't known.
    var roundsReachedText: String {
        plannedRounds.map { "\(roundsReached)/\($0)" } ?? DurationFormat.rounds(roundsReached)
    }

    /// "5/8 rounds", on a line of its own, where a bare "5/8" would be a fraction.
    var roundsLineText: String {
        plannedRounds.map { "\(roundsReached)/\($0) rounds" } ?? DurationFormat.rounds(roundsReached)
    }

    /// What VoiceOver says for the rounds, an early end included.
    var spokenRounds: String {
        guard let plannedRounds else { return DurationFormat.rounds(roundsReached) }
        let line = "\(roundsReached) of \(DurationFormat.rounds(plannedRounds))"
        return endedEarly ? "\(line), ended early" : line
    }

    /// "4:30", or "1:02:03" from an hour up.
    var durationText: String {
        DurationFormat.timer(Int(duration.rounded()))
    }

    /// The per-interval heart-rate chart has nothing to draw without heart rate: declined, or
    /// a watch that didn't measure it.
    var showsChart: Bool {
        intervals.contains { $0.averageHeartRate != nil }
    }

    /// The per-interval calories chart, likewise, needs calories recorded per interval.
    var showsCaloriesChart: Bool {
        intervals.contains { $0.calories != nil }
    }

    /// Whole kilocalories for the session, rounded, for the row and the totals.
    var calories: Int? {
        activeEnergy.map { Int($0.rounded()) }
    }

    /// The charts this session can draw, calories first: they mean something in every kind
    /// of workout, heart rate only where something measured it.
    var charts: [IntervalMetric] {
        (showsCaloriesChart ? [IntervalMetric.calories] : []) + (showsChart ? [.heartRate] : [])
    }

    /// The intervals as phases laid end to end, for a ring of what actually ran.
    var phases: [IntervalPhase] {
        var cursor: TimeInterval = 0
        return intervals.map { interval in
            defer { cursor += interval.duration }
            return IntervalPhase(
                id: interval.id, kind: interval.kind, duration: interval.duration,
                round: interval.round ?? 1, start: cursor
            )
        }
    }
}

/// What a session's per-interval chart can show.
enum IntervalMetric: String, CaseIterable, Identifiable, Hashable, Sendable {
    case calories, heartRate

    var id: Self { self }

    var title: String {
        switch self {
        case .calories: "Calories"
        case .heartRate: "Heart Rate"
        }
    }

    /// The interval's value, or nil when Health recorded none.
    func value(of interval: SessionSummary.Interval) -> Int? {
        switch self {
        case .calories: interval.calories
        case .heartRate: interval.averageHeartRate
        }
    }

    func spoken(_ value: Int) -> String {
        switch self {
        case .calories: "\(value) calories"
        case .heartRate: "\(value) beats per minute"
        }
    }
}

/// One calendar week of sessions, newest first.
struct SessionWeek: Identifiable, Hashable, Sendable {
    /// The week's first day, by the calendar's `firstWeekday`.
    let start: Date
    let sessions: [SessionSummary]

    var id: Date { start }

    /// Groups sessions by the calendar's weeks, newest week first. A week is the calendar's,
    /// so it starts on the user's first weekday and runs across New Year whole.
    static func group(_ sessions: [SessionSummary], calendar: Calendar) -> [SessionWeek] {
        let byWeek = Dictionary(grouping: sessions) { session in
            calendar.dateInterval(of: .weekOfYear, for: session.start)?.start ?? calendar.startOfDay(for: session.start)
        }
        return byWeek
            .map { SessionWeek(start: $0.key, sessions: $0.value.sorted { $0.start > $1.start }) }
            .sorted { $0.start > $1.start }
    }

    /// Whether this is `now`'s week, which History's This Week card heads.
    func isCurrent(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.dateInterval(of: .weekOfYear, for: now)?.start == start
    }

    /// "This Week", "Last Week", "Sep 21 – Sep 27", with the years once it isn't this year's.
    func title(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        if isCurrent(now: now, calendar: calendar) { return "This Week" }
        if let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
           calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek) == start {
            return "Last Week"
        }
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated).day()
        if calendar.component(.year, from: end) != calendar.component(.year, from: now)
            || calendar.component(.year, from: start) != calendar.component(.year, from: end) {
            style = style.year()
        }
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }
}

/// The header's "this week": how many sessions, and how many minutes they came to, a part
/// minute counting as one.
struct WeekTotals: Equatable, Sendable {
    let sessions: Int
    let minutes: Int

    init(sessions: Int, minutes: Int) {
        self.sessions = sessions
        self.minutes = minutes
    }

    /// The sessions in `now`'s calendar week.
    init(_ sessions: [SessionSummary], now: Date = Date(), calendar: Calendar = .current) {
        // Half-open: `DateInterval.contains` would also count the first instant of next week.
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let inWeek = sessions.filter { session in week.map { $0.start <= session.start && session.start < $0.end } ?? false }
        self.sessions = inWeek.count
        // Up, so a short session never reads "1 session, 0 min".
        self.minutes = Int((inWeek.reduce(0) { $0 + $1.duration } / 60).rounded(.up))
    }
}
