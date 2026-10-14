//
//  WordFilterTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// Phase names the voice coach says aloud. Every word on the filter's lists is turned away
/// however it's dressed up, checked word by word so the list can grow without a gap; the
/// names workouts actually use still pass. Blocked samples are written in ROT13, as the
/// filter's own lists are.
@Suite("Word filter")
struct WordFilterTests {
    private func blocked(_ rot13: String) -> String { WordFilter.rot13(rot13) }

    /// The disguises: `word` dressed every way the filter promises to see through.
    private func disguises(of word: String) -> [String] {
        let leet: [Character: String] = ["a": "@", "e": "3", "i": "1", "l": "1", "o": "0", "s": "$", "t": "7", "g": "9", "b": "8"]
        let cyrillic: [Character: String] = ["a": "а", "e": "е", "o": "о", "c": "с", "p": "р", "x": "х", "y": "у", "k": "к"]
        func swap(_ table: [Character: String]) -> String { word.map { table[$0] ?? String($0) }.joined() }
        let fullWidth = String(word.unicodeScalars.map { Character(UnicodeScalar($0.value - 0x61 + 0xFF41)!) })
        return [
            word, word.uppercased(), word.capitalized, word + "s",
            word.map(String.init).joined(separator: " "),
            word.map(String.init).joined(separator: "."),
            word.map(String.init).joined(separator: "\u{200B}"),
            word.map { "\($0)\($0)" }.joined(),
            swap(leet), swap(cyrillic), fullWidth, swap(["i": "!", "l": "|"]),
            word.map { "\($0)\u{0301}" }.joined(),
        ]
    }

    @Test("Every listed word is turned away in every disguise")
    func everyWordEveryDisguise() {
        for word in WordFilter.anywhere + WordFilter.wholeWords {
            for name in disguises(of: word) {
                // Named in ROT13, so a failure doesn't print the word itself.
                #expect(!WordFilter.allows(name), "ROT13 \(WordFilter.rot13(word)) as \(WordFilter.rot13(name))")
            }
        }
    }

    @Test("The anywhere words are caught inside other words too")
    func insideOtherWords() {
        for word in WordFilter.anywhere {
            #expect(!WordFilter.allows("Big" + word.capitalized + "Day"), "ROT13 \(WordFilter.rot13(word))")
        }
        #expect(!WordFilter.allows(blocked("Qhzonff")))
        #expect(!WordFilter.allows(blocked("Onqnff")))
    }

    @Test("The names workouts use pass, including ones holding a whole-word-only word")
    func workoutNames() {
        let names = [
            "Work", "Rest", "Sprint", "Run", "Walk", "Jog", "Recovery", "Jump Rope", "Burpees", "Plank", "Squats",
            "Push Ups", "Pull Ups", "Sit Ups", "Lunges", "Climbers", "Row", "Rower", "Bike", "Cycle", "Swim", "Box",
            "Boxing", "Kick", "Punch", "Stretch", "Breathe", "Yoga", "Pilates", "Spin Class", "HIIT", "Tabata",
            "Max Effort", "Easy", "Hard", "Hills", "Cooldown", "Warmup", "Abs", "Core", "Glutes", "Legs", "Arms",
            "Chest", "Back", "Cardio", "Steps", "Stairs", "Skip", "Hop", "Dance", "Zumba", "Heavy Bag", "Speed",
            "Power", "Tempo", "Strides", "Sets", "Reps", "Push", "Pull", "Press", "Curl", "Deadlift", "Clean",
            "Snatch", "Jerk", "Thruster", "Wall Ball", "Box Jump", "Kettlebell", "Swing", "Assault", "Dumbbell",
            "Pistol", "Tuck Jumps", "Hollow Hold", "Hip Thrust", "Duck Walk", "Shuttle", "Skater", "Basket",
            "Pass", "Mass", "Grass", "Title", "Shoe", "Spice", "Raccoon", "Grape", "Hello", "Shell", "Jazz",
            "Bob", "Set 1", "8 Rounds", "Round 3", "4x4", "5K Pace", "Mile 2", "Récup", "Lvl 10",
        ]
        for name in names {
            #expect(WordFilter.allows(name), "\(name)")
        }
    }

    @Test("A turned-away name isn't saved: the phase keeps its own name, and its new figure")
    func savingKeepsTheOwnName() {
        #expect(PhaseLabel.cleaned(blocked("Fuvg")) == nil)
        #expect(PhaseLabel.cleaned("Sprint") == "Sprint")
        var workout = IntervalWorkout(name: "Test", prepareSeconds: 10, workSeconds: 20, restSeconds: 10, rounds: 2)
        workout.setLabel(PhaseLabel(name: blocked("Fuvg"), symbol: .sprint), for: .work)
        #expect(workout.label(for: .work) == PhaseLabel(name: "Work", symbol: .sprint))
    }

    @Test("One saved by a device without the filter is shown and spoken as the phase's own")
    func readingFallsBack() throws {
        var workout = IntervalWorkout(name: "Test", prepareSeconds: 10, workSeconds: 20, restSeconds: 10, rounds: 2)
        workout.phaseLabels = [IntervalPhase.Kind.work.rawValue: PhaseLabel(name: blocked("Fuvg"), symbol: .run)]
        #expect(workout.label(for: .work).name == "Work")
        let phase = try #require(IntervalPlan(workout: workout).phases.first { $0.kind == .work })
        #expect(phase.title == "Work")
        #expect(phase.symbol == .run)
        #expect(CuePlan.phrase(for: phase, totalRounds: 2) == "Work")
    }
}
