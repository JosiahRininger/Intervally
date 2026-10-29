//
//  IntervalWorkoutTests.swift
//  IntervallyTests
//

import Foundation
import Testing
@testable import Intervally

/// More of the workout configuration suite, declared in FormattingTests.swift: which fields a
/// merge fills in, and how the optional ones are stored.
extension IntervalWorkoutTests {
    /// The same preset as a version that predates every optional field holds it. Built from
    /// the other fields alone, so a field added later is nil here without anyone touching it.
    private func originalFields(of workout: IntervalWorkout) -> IntervalWorkout {
        IntervalWorkout(
            id: workout.id, name: workout.name, prepareSeconds: workout.prepareSeconds,
            warmupSeconds: workout.warmupSeconds, workSeconds: workout.workSeconds,
            restSeconds: workout.restSeconds, rounds: workout.rounds, cooldownSeconds: workout.cooldownSeconds
        )
    }

    @Test("fillingAbsent(from:) fills every optional field a copy lacks, found by reflection, and replaces none it has")
    func fillingAbsentCoversEveryOptional() {
        let full = IntervalWorkout.everyFieldSet
        #expect(!full.optionalFieldNames.isEmpty)
        #expect(full.absentFieldNames.isEmpty, "everyFieldSet must set every optional field")
        let original = originalFields(of: full)
        #expect(original.absentFieldNames == full.optionalFieldNames, "A field added later must start out nil")

        let filled = original.fillingAbsent(from: full)
        #expect(filled.absentFieldNames.isEmpty, "Not taken from the other copy: \(filled.absentFieldNames)")
        #expect(filled == full)

        var other = IntervalWorkout(name: "Rows", rounds: 3, activity: .rowing)
        other.setLabel(PhaseLabel(name: "Row", symbol: .row), for: .work)
        #expect(other.absentFieldNames.isEmpty, "Set every optional field here too, to another value")
        #expect(full.fillingAbsent(from: other) == full, "A field a copy has is never replaced")
        #expect(original.fillingAbsent(from: other).name == original.name, "Only optional fields are taken")
        #expect(original.fillingAbsent(from: original) == original)
    }

    @Test("Optional fields are encoded only when set, so a preset without them encodes as an older version wrote it")
    func optionalFieldsEncodedOnlyWhenSet() throws {
        func keys(_ workout: IntervalWorkout) throws -> Set<String> {
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(workout)) as? [String: Any]
            return try Set(#require(object).keys)
        }
        let full = IntervalWorkout.everyFieldSet
        let original = originalFields(of: full)
        // Each optional field's key on the wire is its name.
        let optionals = Set(full.optionalFieldNames)
        #expect(try keys(full).isSuperset(of: optionals))
        #expect(try keys(original).isDisjoint(with: optionals))
        #expect(try JSONDecoder().decode(IntervalWorkout.self, from: JSONEncoder().encode(original)) == original)
    }
}
