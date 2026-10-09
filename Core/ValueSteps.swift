//
//  ValueSteps.swift
//  Intervally
//

import Foundation

/// The values a duration or a count can be set to: the watch's crown detents and the
/// iPhone's picker rows alike, so a preset edited on one device lands on values the other
/// offers.
///
/// A table rather than raw seconds. A linear `by: 5` across 5…3600 was 720 detents — a full
/// minute of turning to reach ten minutes — so the steps coarsen as the numbers grow: 5s
/// below 2:00, 15s to 10:00, 30s beyond. Rounds stay one per step.
enum ValueSteps {
    /// Every value from the lower bound to the upper, each a multiple of the stride in force
    /// at that point. The upper bound is always included. A `step` of 1 marks a count.
    static func values(in range: ClosedRange<Int>, step: Int) -> [Int] {
        var table = [range.lowerBound]
        while let last = table.last, last < range.upperBound {
            let stride = Self.stride(at: last, step: step)
            table.append(min(range.upperBound, (last / stride + 1) * stride))
        }
        return table
    }

    private static func stride(at value: Int, step: Int) -> Int {
        guard step > 1 else { return 1 }
        if value < 120 { return step }
        if value < 600 { return 15 }
        return 30
    }
}
