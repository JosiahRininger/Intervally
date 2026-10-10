//
//  SessionSummaryTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// A session as the watch saves it: one activity per phase of `workout`'s plan, tagged as
/// `WorkoutSessionController.activityMetadata` tags them, up to the work of `lastRound`.
private func session(
    _ workout: IntervalWorkout = WorkoutStore.starterWorkouts[0],
    lastRound: Int? = nil,
    name: String? = "Classic",
    plannedRounds: Int? = 8,
    heartRate: Double? = 140,
    start: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)
) -> RawWorkout {
    let phases = IntervalPlan(workout: workout).phases.filter { phase in
        guard let lastRound else { return true }
        return phase.kind != .cooldown && phase.round <= lastRound && !(phase.kind == .rest && phase.round == lastRound)
    }
    return RawWorkout(
        id: UUID(),
        start: start,
        duration: phases.reduce(0) { $0 + $1.duration },
        presetName: name,
        plannedRounds: plannedRounds,
        averageHeartRate: heartRate,
        maximumHeartRate: heartRate.map { $0 + 20 },
        activeEnergy: 48,
        activities: phases.map { phase in
            RawWorkout.Activity(
                phase: phase.kind.rawValue,
                round: phase.kind.isBookend ? nil : phase.round,
                start: start.addingTimeInterval(phase.start),
                duration: phase.duration,
                averageHeartRate: heartRate
            )
        }
    )
}

@Suite("Session summary")
struct SessionSummaryTests {

    @Test("A run to the end reached every round it planned")
    func fullRun() {
        let summary = SessionSummary(session())
        #expect(summary.roundsReached == 8)
        #expect(summary.plannedRounds == 8)
        #expect(summary.endedEarly == false)
        #expect(summary.roundsReachedText == "8/8")
        #expect(summary.spokenRounds == "8 of 8 rounds")
        #expect(summary.completion == 1)
    }

    @Test("Rounds reached falls short of the plan: ended early")
    func endedEarly() {
        let summary = SessionSummary(session(lastRound: 5))
        #expect(summary.roundsReached == 5)
        #expect(summary.endedEarly)
        #expect(summary.roundsReachedText == "5/8")
        #expect(summary.roundsLineText == "5/8 rounds")
        #expect(summary.spokenRounds == "5 of 8 rounds, ended early")
        #expect(summary.completion == 5.0 / 8.0)
    }

    @Test("Rounds reached is the furthest work round: a session taken mid-run still ran to the end")
    func reachedIsFurthestRound() {
        var raw = session()
        // Health was granted during round 3, so the session holds rounds 3 to 8 only.
        raw.activities.removeAll { ($0.round ?? 0) < 3 }
        let summary = SessionSummary(raw)
        #expect(summary.intervals.filter { $0.kind == .work }.count == 6)
        #expect(summary.roundsReached == 8)
        #expect(summary.endedEarly == false)
    }

    @Test("Without round tags, the work intervals are counted")
    func untaggedRoundsCounted() {
        var raw = session(lastRound: 3)
        for index in raw.activities.indices { raw.activities[index].round = nil }
        #expect(SessionSummary(raw).roundsReached == 3)
    }

    @Test("The warmup and cooldown carry no round and never count as one")
    func bookendsCarryNoRound() {
        let workout = IntervalWorkout(name: "Long", warmupSeconds: 300, workSeconds: 30, restSeconds: 15, rounds: 2, cooldownSeconds: 120)
        var raw = session(workout, plannedRounds: 2)
        // Even a bookend that somehow arrives with a round tag.
        for index in raw.activities.indices where raw.activities[index].phase == "warmup" {
            raw.activities[index].round = 7
        }
        let summary = SessionSummary(raw)
        let bookends = summary.intervals.filter { $0.kind.isBookend }
        #expect(bookends.map(\.kind) == [.warmup, .cooldown])
        #expect(bookends.allSatisfy { $0.round == nil })
        #expect(bookends.map(\.title) == ["Warmup", "Cooldown"])
        #expect(summary.roundsReached == 2)
    }

    @Test("Missing or blank metadata falls back to “Interval workout”", arguments: [nil, "", "   "] as [String?])
    func fallbackTitle(name: String?) {
        #expect(SessionSummary(session(name: name)).title == "Interval workout")
        #expect(SessionSummary.fallbackTitle == "Interval workout")
    }

    @Test("A name is shown trimmed")
    func trimmedName() {
        #expect(SessionSummary(session(name: "  Hill Repeats \n")).title == "Hill Repeats")
    }

    @Test("Without a planned round count nothing is called an early end", arguments: [nil, 0, -3] as [Int?])
    func unknownPlan(planned: Int?) {
        let summary = SessionSummary(session(lastRound: 5, plannedRounds: planned))
        #expect(summary.plannedRounds == nil)
        #expect(summary.endedEarly == false)
        #expect(summary.roundsReachedText == "5 rounds")
        #expect(summary.roundsLineText == "5 rounds")
        #expect(summary.completion == 1)
    }

    @Test("No heart rate hides the chart; any interval with it shows the chart")
    func chartNeedsHeartRate() {
        var raw = session(heartRate: nil)
        let summary = SessionSummary(raw)
        #expect(summary.showsChart == false)
        #expect(summary.averageHeartRate == nil)
        #expect(summary.maximumHeartRate == nil)

        raw.activities[3].averageHeartRate = 151.4
        #expect(SessionSummary(raw).showsChart)
        #expect(SessionSummary(raw).intervals[3].averageHeartRate == 151)
    }

    @Test("Heart rates are rounded to whole beats")
    func heartRateRounded() {
        let summary = SessionSummary(session(heartRate: 141.6))
        #expect(summary.averageHeartRate == 142)
        #expect(summary.maximumHeartRate == 162)
        #expect(summary.intervals.allSatisfy { $0.averageHeartRate == 142 })
    }

    @Test("Intervals come in the order they ran, and a phase this version doesn't know is left out")
    func orderAndUnknownPhases() {
        var raw = session(lastRound: 2)
        raw.activities.reverse()
        raw.activities.append(RawWorkout.Activity(phase: "stretch", round: nil, start: raw.start.addingTimeInterval(1), duration: 5))
        raw.activities.append(RawWorkout.Activity(phase: nil, round: 1, start: raw.start.addingTimeInterval(2), duration: 5))
        let summary = SessionSummary(raw)
        #expect(summary.intervals.map(\.kind) == [.prepare, .work, .rest, .work])
        #expect(summary.intervals.map(\.id) == [0, 1, 2, 3])
    }

    @Test("Each interval names its phase, and its round only for work and rest")
    func intervalTitles() {
        let titles = SessionSummary(session(lastRound: 2)).intervals.map(\.title)
        #expect(titles == ["Get Ready", "Work · Round 1", "Rest · Round 1", "Work · Round 2"])
    }

    @Test("The ring of a full session is the ring of the plan it ran")
    func ringMatchesPlan() {
        let workout = IntervalWorkout(name: "Long", warmupSeconds: 300, workSeconds: 40, restSeconds: 20, rounds: 6, cooldownSeconds: 180)
        let summary = SessionSummary(session(workout, plannedRounds: 6))
        let plan = IntervalPlan(workout: workout)
        #expect(summary.phases.map(\.kind) == plan.phases.map(\.kind))
        #expect(summary.phases.map(\.start) == plan.phases.map(\.start))
        #expect(SegmentedRing.segments(for: summary.phases) == SegmentedRing.segments(for: plan))
        #expect(SegmentedRing.groupedSegments(for: summary.phases) == SegmentedRing.groupedSegments(for: plan))
    }

    @Test("A session that ended in its warmup still draws: the bookend at its true share")
    func ringOfWarmupOnly() {
        let phases = [IntervalPhase(id: 0, kind: .warmup, duration: 120, round: 1, start: 0)]
        #expect(SegmentedRing.displayFractions(for: phases) == [1])
    }

    @Test("The duration reads as a timer")
    func durationText() {
        var raw = session()
        raw.duration = 270.4
        #expect(SessionSummary(raw).durationText == "4:30")
        raw.duration = 3723
        #expect(SessionSummary(raw).durationText == "1:02:03")
    }
}

@Suite("History weeks")
struct SessionWeekTests {
    private static func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private static let english = Locale(identifier: "en_US")

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func summary(at start: Date, minutes: Double = 6) -> SessionSummary {
        var raw = session(start: start)
        raw.duration = minutes * 60
        return SessionSummary(raw)
    }

    @Test("A week starts on the calendar's first weekday")
    func firstWeekday() {
        let sundayFirst = Self.calendar(firstWeekday: 1)
        let mondayFirst = Self.calendar(firstWeekday: 2)
        // Sunday 4 and Monday 5 October 2026.
        let sunday = date(2026, 10, 4, in: sundayFirst)
        let monday = date(2026, 10, 5, in: sundayFirst)
        let sessions = [summary(at: sunday), summary(at: monday)]

        let sundayWeeks = SessionWeek.group(sessions, calendar: sundayFirst)
        #expect(sundayWeeks.count == 1)
        #expect(sundayWeeks[0].start == date(2026, 10, 4, hour: 0, in: sundayFirst))
        #expect(sundayWeeks[0].sessions.map(\.start) == [monday, sunday])

        let mondayWeeks = SessionWeek.group(sessions, calendar: mondayFirst)
        #expect(mondayWeeks.map(\.start) == [date(2026, 10, 5, hour: 0, in: mondayFirst), date(2026, 9, 28, hour: 0, in: mondayFirst)])
    }

    @Test("A week across New Year stays one week, and says both years")
    func yearBoundary() {
        let calendar = Self.calendar(firstWeekday: 1)
        let newYearsEve = date(2025, 12, 31, in: calendar)
        let afterNewYear = date(2026, 1, 2, in: calendar)
        let weeks = SessionWeek.group([summary(at: newYearsEve), summary(at: afterNewYear)], calendar: calendar)
        #expect(weeks.count == 1)
        #expect(weeks[0].start == date(2025, 12, 28, hour: 0, in: calendar))
        let now = date(2026, 3, 1, in: calendar)
        #expect(weeks[0].title(now: now, calendar: calendar, locale: Self.english) == "Dec 28, 2025 – Jan 3, 2026")
    }

    @Test("Weeks are titled This Week, Last Week, then by their dates, with a year once it's not this one")
    func titles() {
        let calendar = Self.calendar(firstWeekday: 1)
        let now = date(2026, 10, 9, in: calendar)
        let sessions = [
            summary(at: date(2026, 10, 6, in: calendar)),
            summary(at: date(2026, 9, 30, in: calendar)),
            summary(at: date(2026, 9, 22, in: calendar)),
            summary(at: date(2025, 9, 22, in: calendar)),
        ]
        let weeks = SessionWeek.group(sessions, calendar: calendar)
        let titles = weeks.map { $0.title(now: now, calendar: calendar, locale: Self.english) }
        #expect(titles == ["This Week", "Last Week", "Sep 20 – Sep 26", "Sep 21, 2025 – Sep 27, 2025"])
        // Only this week goes without its own label, under the This Week card.
        #expect(weeks.map { $0.isCurrent(now: now, calendar: calendar) } == [true, false, false, false])
    }

    @Test("Newest week first, newest session first within it")
    func ordering() {
        let calendar = Self.calendar(firstWeekday: 1)
        let early = date(2026, 9, 1, in: calendar)
        let late = date(2026, 10, 7, in: calendar)
        let lateSameWeek = date(2026, 10, 8, in: calendar)
        let weeks = SessionWeek.group([summary(at: early), summary(at: late), summary(at: lateSameWeek)], calendar: calendar)
        #expect(weeks.map { $0.sessions.map(\.start) } == [[lateSameWeek, late], [early]])
    }

    @Test("This week counts only this week's sessions, and their minutes rounded up")
    func thisWeekTotals() {
        let calendar = Self.calendar(firstWeekday: 1)
        let now = date(2026, 10, 9, in: calendar)
        let weekStart = date(2026, 10, 4, hour: 0, in: calendar)
        let nextWeekStart = date(2026, 10, 11, hour: 0, in: calendar)
        let sessions = [
            summary(at: weekStart, minutes: 6.2),
            summary(at: date(2026, 10, 8, in: calendar), minutes: 4.5),
            // The instant the next week starts belongs to it, not to this one.
            summary(at: nextWeekStart, minutes: 30),
            summary(at: weekStart.addingTimeInterval(-1), minutes: 30),
        ]
        #expect(WeekTotals(sessions, now: now, calendar: calendar) == WeekTotals(sessions: 2, minutes: 11))
        #expect(WeekTotals([], now: now, calendar: calendar) == WeekTotals(sessions: 0, minutes: 0))
        // A 28-second session is a minute, never "1 session, 0 min".
        #expect(WeekTotals([summary(at: weekStart, minutes: 28.0 / 60)], now: now, calendar: calendar) == WeekTotals(sessions: 1, minutes: 1))
    }
}
