//
//  IntervalWorkoutTests.swift
//  IntervallyTests
//

import Foundation
import Testing
@testable import Intervally

/// More of the workout configuration suite, declared in FormattingTests.swift: which fields a
/// merge fills in, how the optional ones are stored, and how long a name can be.
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

    // MARK: - Name

    /// A name exactly at the cap.
    private static let fortyCharacters = "Saturday Hill Sprints with the Club, 6am"

    @Test("Clamping cuts a name to 40 characters, and an empty one becomes Workout")
    @MainActor
    func clampedCapsNameAt40() {
        #expect(Self.fortyCharacters.count == IntervalWorkout.maxNameLength)
        #expect(IntervalWorkout.maxNameLength == 40)
        #expect(IntervalWorkout(name: Self.fortyCharacters).clamped.name == Self.fortyCharacters)
        #expect(IntervalWorkout(name: Self.fortyCharacters + " and then some").clamped.name == Self.fortyCharacters)
        #expect(IntervalWorkout(name: "  Tabata \n").clamped.name == "Tabata")
        for empty in ["", "   ", "\n\t"] {
            #expect(IntervalWorkout(name: empty).clamped.name == "Workout")
        }

        // Every save goes through clamped: what the store keeps is cut too, on either device.
        let store = WorkoutStore(defaults: makeTestDefaults())
        let added = store.add(IntervalWorkout(name: Self.fortyCharacters + Self.fortyCharacters))
        #expect(store.workouts.last?.name == Self.fortyCharacters)
        #expect(added.name == Self.fortyCharacters)
        store.rename(added.id, to: "   ")
        #expect(store.workouts.last?.name == "Workout")
    }

    @Test("committedName trims, falls back when nothing is left, then cuts and trims again")
    func committedNameTrimsAndFallsBack() {
        #expect(IntervalWorkout.committedName("  Hills ", fallback: "Classic") == "Hills")
        #expect(IntervalWorkout.committedName(" \n ", fallback: "Classic") == "Classic")
        #expect(IntervalWorkout.committedName("", fallback: "") == "")
        // A cut that lands just after a space doesn't keep it.
        let spaced = String(repeating: "a", count: 39) + " tail"
        #expect(IntervalWorkout.committedName(spaced, fallback: "Classic") == String(repeating: "a", count: 39))
        // The fallback is held to the cap too: a name saved before there was one.
        let long = Self.fortyCharacters + "!!"
        #expect(IntervalWorkout.committedName("", fallback: long) == Self.fortyCharacters)
        #expect(IntervalWorkout.committedName(Self.fortyCharacters, fallback: "Classic") == Self.fortyCharacters)
    }

    @Test("A name field left as it was saves nothing, so a long 1.2 name is cut only by a rename")
    func savedNameOnlyForARename() {
        let legacy = Self.fortyCharacters + " and then some"
        // Opened and closed: the field still shows the whole stored name.
        #expect(IntervalWorkout.savedName(typed: legacy, stored: legacy) == nil)
        #expect(IntervalWorkout.savedName(typed: "Tabata", stored: "Tabata") == nil)
        // Typed back to the stored name, or emptied, which puts it back: nothing to save.
        #expect(IntervalWorkout.savedName(typed: "  Tabata ", stored: "Tabata") == nil)
        #expect(IntervalWorkout.savedName(typed: "", stored: "Tabata") == nil)
        // Emptying a long name is typing in it, though: what comes back is held to the cap.
        #expect(IntervalWorkout.savedName(typed: "", stored: legacy) == Self.fortyCharacters)
        // A rename saves, trimmed and cut, even when it only shortens a long name.
        #expect(IntervalWorkout.savedName(typed: " Hills ", stored: "Tabata") == "Hills")
        #expect(IntervalWorkout.savedName(typed: legacy + "!", stored: legacy) == Self.fortyCharacters)
    }

    /// A name, the other names taken, and what its copy is called.
    static let copiesAtTheCap: [(String, [String], String)] = {
        let x = { (count: Int) in String(repeating: "x", count: count) }
        return [
            (x(40), [], x(38) + " 2"),
            (x(38) + " 2", [x(38) + " 3"], x(38) + " 4"),
            (x(38) + " 9", [], x(37) + " 10"),
            // A cut that would leave a space before the number doesn't.
            (x(37) + " yz", [], x(37) + " 2"),
        ]
    }()

    @Test("A copy's number always shows under the cap: the name is cut to make room", arguments: copiesAtTheCap)
    func copySuffixRespectsCap(name: String, taken: [String], expected: String) {
        let copy = PresetNaming.uniqueName(after: name, among: taken + [name])
        #expect(copy == expected)
        #expect(copy.count <= IntervalWorkout.maxNameLength)
        #expect(copy != name, "The copy must not read as the preset it came from")
        #expect(PresetListView.uniqueName(after: name, among: taken + [name]) == copy, "The watch names copies the same way")
        #expect(IntervalWorkout(name: copy).clamped.name == copy, "Saved as named")
    }

    @Test("A copy of a long name skips numbers already taken, as a short one does")
    func copyOfLongNameSkipsTaken() {
        let name = String(repeating: "x", count: 40)
        let stem = String(repeating: "x", count: 38)
        #expect(PresetNaming.uniqueName(after: name, among: [name, "\(stem) 2", "\(stem) 3"]) == "\(stem) 4")
    }

    @Test("An emoji, however many code points it takes, counts as one character and is never cut apart")
    func emojiCountsAsOneCharacter() {
        // A woman running (four scalars), a flag (two) and a family (seven).
        for emoji in ["🏃‍♀️", "🇯🇵", "👨‍👩‍👧‍👦"] {
            #expect(emoji.count == 1)
            let name = IntervalWorkout.committedName(String(repeating: emoji, count: 41), fallback: "Workout")
            #expect(name.count == IntervalWorkout.maxNameLength)
            #expect(name == String(repeating: emoji, count: IntervalWorkout.maxNameLength))
        }
        let mixed = String(repeating: "a", count: 39) + "🏃‍♀️🏃‍♀️"
        #expect(IntervalWorkout.committedName(mixed, fallback: "Workout") == String(repeating: "a", count: 39) + "🏃‍♀️")
    }
}
