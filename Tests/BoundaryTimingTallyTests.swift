//
//  BoundaryTimingTallyTests.swift
//  IntervallyTests
//

import Testing
import Foundation
@testable import Intervally

@Suite("Boundary timing tally")
struct BoundaryTimingTallyTests {

    @Test("Nothing recorded, nothing to say; closing starts afresh")
    func emptyCloseIsNil() {
        var tally = BoundaryTimingTally(lateThreshold: 1.5, device: .phone)
        #expect(tally.close() == nil)
        tally.record(lateness: 0.01)
        #expect(tally.close() != nil)
        #expect(tally.close() == nil, "Said once")
        #expect(tally == BoundaryTimingTally(lateThreshold: 1.5, device: .phone))
    }

    @Test("One line: how many, the median and the slowest, and how many came too late for their cue")
    func medianMaxAndOverCount() {
        var tally = BoundaryTimingTally(lateThreshold: 1.5, device: .phone)
        // Exactly at the threshold still plays, as `CuePlan` has it.
        for lateness in [0.012, 0.3, 0.008, 1.5, 2.25] { tally.record(lateness: lateness) }
        #expect(tally.close() == "Run timing: 5 boundaries, median 0.30 s late, max 2.25 s; 1 over 1.5 s (nothing played for those)")

        // An even count takes the middle two halfway.
        for lateness in [0.5, 0.01, 0.04, 0.02] { tally.record(lateness: lateness) }
        #expect(tally.close() == "Run timing: 4 boundaries, median 0.03 s late, max 0.50 s; 0 over 1.5 s (nothing played for those)")

        tally.record(lateness: 0.008)
        #expect(tally.close() == "Run timing: 1 boundary, median 0.01 s late, max 0.01 s; 0 over 1.5 s (nothing played for those)")
    }

    @Test("Past a thousand, the median rests on the first thousand while the count, the slowest and the late keep counting")
    func capKeepsCountAndMax() {
        var tally = BoundaryTimingTally(lateThreshold: 1.0, device: .watch)
        for _ in 0..<BoundaryTimingTally.sampleLimit { tally.record(lateness: 0.01) }
        for _ in 0..<499 { tally.record(lateness: 0.4) }
        tally.record(lateness: 3)

        #expect(tally.samples.count == BoundaryTimingTally.sampleLimit)
        #expect(tally.count == 1_500)
        #expect(tally.close() == "Run timing: 1500 boundaries, median 0.01 s late, max 3.00 s; 1 over 1.0 s (one tap instead of the full pattern)")
    }

    @Test("The iPhone's line says a late change played nothing; the watch's, that it tapped once")
    func phoneAndWatchWording() {
        var phone = BoundaryTimingTally(lateThreshold: 1.5, device: .phone)
        var watch = BoundaryTimingTally(lateThreshold: 1.0, device: .watch)
        for lateness in [0.009, 1.2] {
            phone.record(lateness: lateness)
            watch.record(lateness: lateness)
        }
        #expect(phone.close() == "Run timing: 2 boundaries, median 0.60 s late, max 1.20 s; 0 over 1.5 s (nothing played for those)")
        #expect(watch.close() == "Run timing: 2 boundaries, median 0.60 s late, max 1.20 s; 1 over 1.0 s (one tap instead of the full pattern)")

        // This bundle runs on the watch: its runs take the watch's words and threshold.
        #expect(BoundaryTimingTally(lateThreshold: 1).device == .watch)
        #expect(RunPlatform.lateBoundary == Haptics.lateThreshold)
    }
}
