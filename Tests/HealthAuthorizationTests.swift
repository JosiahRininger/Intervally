//
//  HealthAuthorizationTests.swift
//  IntervallyTests
//

import HealthKit
import Testing
@testable import Intervally

/// Whether Start waits for the Health sheet as long as the user likes, or bounds it as an
/// answered request. Only a request that would show the sheet may go unbounded.
@Suite("Health prompt")
struct HealthAuthorizationTests {

    @Test("A request that would show the sheet is undecided: the user takes as long as they like")
    func sheetIsUndecided() {
        #expect(WorkoutSessionController.isDecided(.shouldRequest) == false)
    }

    @Test("Asked already, HealthKit not knowing, or healthd not answering all count as decided",
          arguments: [HKAuthorizationRequestStatus.unnecessary, .unknown, nil] as [HKAuthorizationRequestStatus?])
    func otherwiseDecided(status: HKAuthorizationRequestStatus?) {
        #expect(WorkoutSessionController.isDecided(status))
    }

    @Test("The watch asks to write only workouts, and to read everything History reads on iPhone")
    func requestCoversHistory() {
        let share = Set(WorkoutSessionController.typesToShare.map(\.identifier))
        let read = Set(WorkoutSessionController.typesToRead.map(\.identifier))
        #expect(share == HealthAccess.watchWrites)
        // A subset would let the iPhone's request and this one keep undoing each other.
        #expect(read.isSuperset(of: HealthAccess.historyReads))
        #expect(read == HealthAccess.historyReads, "Nothing beyond what Intervally uses")
    }
}
