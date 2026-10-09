//
//  HistoryQATests.swift
//  IntervallyPhoneTests
//

#if DEBUG
import Foundation
import Testing
@testable import IntervallyPhone

/// `-qaHistory`: each fixture reaches the History state it is for, and the sample shows what
/// the screenshots need without touching Health.
@Suite("History QA fixture")
@MainActor
struct HistoryQATests {

    @Test("-qaHistory is read from its value, and a typo is ignored")
    func parse() {
        #expect(PhoneQAOptions.parse(["-qaHistory", "sample"]).history == .sample)
        #expect(PhoneQAOptions.parse(["-qaHistory", "connect", "-qaOpen", "session"]) == PhoneQAOptions(screen: .session, history: .connect))
        #expect(PhoneQAOptions.parse(["-qaHistory", "lots"]).history == nil)
        #expect(PhoneQAOptions.parse(["-qaHistory", "-qaPro", "pro"]) == PhoneQAOptions(pro: true))
        for mode in QAHistory.allCases {
            #expect(PhoneQAOptions.parse(["-qaHistory", mode.rawValue]).history == mode)
        }
    }

    @Test("Each fixture lands History in its state", arguments: [
        (QAHistory.sample, HistoryModel.State.loaded),
        (.empty, .empty),
        (.connect, .needsAccess),
        (.unavailable, .unavailable),
        (.failed, .failed),
    ])
    func states(mode: QAHistory, state: HistoryModel.State) async {
        let history = HistoryModel(source: SampleHistory(mode: mode))
        await history.appear()
        #expect(history.state == state)
    }

    @Test("Connect on the connect fixture brings the sample in")
    func connectAllows() async {
        let history = HistoryModel(source: SampleHistory(mode: .connect))
        await history.appear()
        await history.connect()
        #expect(history.state == .loaded)
        #expect(history.sessions.count == 7)
    }

    @Test("The sample spans three weeks and shows every kind of row the screenshots need")
    func sampleCoversTheCases() async {
        let history = HistoryModel(source: SampleHistory(mode: .sample))
        await history.appear()
        let sessions = history.sessions
        #expect(sessions.count == 7)
        #expect(history.weeks.count >= 3)
        #expect(sessions.allSatisfy { $0.start < Date() })
        #expect(sessions.contains { $0.endedEarly })
        #expect(sessions.contains { !$0.showsChart })
        #expect(sessions.contains { $0.intervals.contains { $0.kind == .warmup } })
        #expect(sessions.first?.showsChart == true, "The newest is the Session Detail screenshot")
        #expect(sessions.first?.endedEarly == false)
    }

    @Test("Sample IDs hold across reads, so a refresh doesn't swap the session on screen")
    func stableIDs() async {
        let source = SampleHistory(mode: .sample)
        let first = try? await source.workouts().map(\.id)
        let second = try? await source.workouts().map(\.id)
        #expect(first == second)
        #expect(Set(first ?? []).count == 7)
    }

    @Test("A session early in the day is still over by now")
    func todayIsInThePast() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let earlyMorning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 5))!
        let sessions = SampleHistory.sessions(now: earlyMorning, calendar: calendar)
        #expect(sessions.allSatisfy { $0.start.addingTimeInterval($0.duration) < earlyMorning })
    }
}
#endif
