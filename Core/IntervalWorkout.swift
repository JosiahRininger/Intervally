//
//  IntervalWorkout.swift
//  Intervally
//

import Foundation

/// The user-facing configuration for an interval workout.
///
/// Durations are stored as plain seconds. The legacy app stored opaque picker
/// indices and reconstituted seconds with `index * 5 + 5`, which made the stored
/// values meaningless on their own and drifted out of sync with the picker.
struct IntervalWorkout: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    /// Lead-in countdown before anything else. Zero disables it.
    var prepareSeconds: Int
    /// Pro. An easy phase after the lead-in, before the first work interval. Zero is off.
    var warmupSeconds: Int
    var workSeconds: Int
    var restSeconds: Int
    var rounds: Int
    /// Pro. An easy phase straight after the final work interval, with no rest before it.
    /// Zero is off.
    var cooldownSeconds: Int
    /// What Health records it as. Nil until chosen, and always nil from a version that
    /// predates the choice, which is how a merge tells "never set" from a choice
    /// (`PresetRecord.merged`). Read `activityKind`.
    var activity: WorkoutActivity?

    init(
        id: UUID = UUID(),
        name: String = "Workout",
        prepareSeconds: Int = 10,
        warmupSeconds: Int = 0,
        workSeconds: Int = 30,
        restSeconds: Int = 15,
        rounds: Int = 8,
        cooldownSeconds: Int = 0,
        activity: WorkoutActivity? = nil
    ) {
        self.id = id
        self.name = name
        self.prepareSeconds = prepareSeconds
        self.warmupSeconds = warmupSeconds
        self.workSeconds = workSeconds
        self.restSeconds = restSeconds
        self.rounds = rounds
        self.cooldownSeconds = cooldownSeconds
        self.activity = activity
    }

    static let `default` = IntervalWorkout()

    /// What Health records it as: HIIT until chosen.
    var activityKind: WorkoutActivity { activity ?? .standard }

    // MARK: - Decoding

    /// `encode(to:)` is synthesised from these, so a field missing here is silently never
    /// saved — every stored property must be listed.
    private enum CodingKeys: String, CodingKey {
        case id, name, prepareSeconds, warmupSeconds, workSeconds, restSeconds, rounds, cooldownSeconds
        // Optional, so encoded only once chosen: a preset never given one encodes exactly
        // as it did before there was a choice.
        case activity
    }

    /// Decodes field by field, falling back to defaults.
    ///
    /// Presets are the only thing a user builds in this app. A strict synthesised decoder
    /// means that adding one field in a future version makes every stored preset fail to
    /// decode — and a store that cannot decode treats that as "no presets". Being lenient
    /// here is what makes the schema safe to evolve.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = IntervalWorkout.default
        self.init(
            id: (try? container.decode(UUID.self, forKey: .id)) ?? UUID(),
            name: (try? container.decode(String.self, forKey: .name)) ?? fallback.name,
            prepareSeconds: (try? container.decode(Int.self, forKey: .prepareSeconds)) ?? fallback.prepareSeconds,
            warmupSeconds: (try? container.decode(Int.self, forKey: .warmupSeconds)) ?? fallback.warmupSeconds,
            workSeconds: (try? container.decode(Int.self, forKey: .workSeconds)) ?? fallback.workSeconds,
            restSeconds: (try? container.decode(Int.self, forKey: .restSeconds)) ?? fallback.restSeconds,
            rounds: (try? container.decode(Int.self, forKey: .rounds)) ?? fallback.rounds,
            cooldownSeconds: (try? container.decode(Int.self, forKey: .cooldownSeconds)) ?? fallback.cooldownSeconds,
            // One a later version added reads as never chosen, rather than failing the preset.
            activity: try? container.decodeIfPresent(WorkoutActivity.self, forKey: .activity)
        )
    }

    // MARK: - Limits

    static let workRange = 5...3600
    static let restRange = 0...3600
    static let prepareRange = 0...60
    static let roundsRange = 1...99
    static let warmupRange = 0...1800
    static let cooldownRange = 0...1800

    /// Crown detents for both bookends: Off, 0:30 to 5:00 by 30 seconds, then 6:00 to 30:00
    /// by the minute. The work table's 5- and 15-second bands would make 77 uneven detents
    /// for a phase nobody sets to the second.
    static let bookendValues: [Int] = [0]
        + Array(stride(from: 30, through: 300, by: 30))
        + Array(stride(from: 360, through: 1800, by: 60))

    /// A copy with every field clamped into its supported range.
    var clamped: IntervalWorkout {
        var copy = self
        copy.prepareSeconds = Self.prepareRange.clamping(prepareSeconds)
        copy.warmupSeconds = Self.warmupRange.clamping(warmupSeconds)
        copy.workSeconds = Self.workRange.clamping(workSeconds)
        copy.restSeconds = Self.restRange.clamping(restSeconds)
        copy.rounds = Self.roundsRange.clamping(rounds)
        copy.cooldownSeconds = Self.cooldownRange.clamping(cooldownSeconds)
        return copy
    }

    /// Total wall-clock duration of the workout, in seconds.
    ///
    /// Must count every phase the plan builds: restoring a run compares elapsed time against
    /// this, so leaving the bookends out would throw away a run relaunched mid-cooldown as
    /// already finished.
    var totalSeconds: Int {
        let c = clamped
        // The final round has no trailing rest, so there are `rounds - 1` rests.
        return c.prepareSeconds + c.warmupSeconds
            + c.rounds * c.workSeconds + max(0, c.rounds - 1) * c.restSeconds
            + c.cooldownSeconds
    }

    // MARK: - Bookends

    var hasBookends: Bool { warmupSeconds > 0 || cooldownSeconds > 0 }

    /// What actually runs. Without Pro the bookends are zeroed in the copy that runs; the
    /// stored values are untouched, so a purchase restored later brings them straight back.
    func effective(isPro: Bool) -> IntervalWorkout {
        guard !isPro, hasBookends else { return self }
        var copy = self
        copy.warmupSeconds = 0
        copy.cooldownSeconds = 0
        return copy
    }
}

extension ClosedRange where Bound: Comparable {
    func clamping(_ value: Bound) -> Bound {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}

extension IntervalWorkout {
    /// "30s · 15s · 8×" — the rhythm at a glance, as the preset list and the Smart Stack
    /// show it. No rest is shown when there is none, rather than a "0s" for a phase that
    /// never happens.
    var rhythm: String {
        var parts = [DurationFormat.clock(workSeconds)]
        if restSeconds > 0 { parts.append(DurationFormat.clock(restSeconds)) }
        parts.append("\(rounds)×")
        return parts.joined(separator: " · ")
    }

    /// What VoiceOver reads for the whole preset, in the order it runs — the watch's dial and
    /// the iPhone's preset cards alike. A bookend is named only when it is on, as the ring
    /// only draws it then.
    var spokenSummary: String {
        var parts: [String] = []
        if warmupSeconds > 0 {
            parts.append("\(DurationFormat.spoken(warmupSeconds)) warmup")
        }
        parts.append("\(DurationFormat.spoken(workSeconds)) work")
        parts.append(restSeconds > 0 ? "\(DurationFormat.spoken(restSeconds)) rest" : "no rest")
        parts.append(DurationFormat.rounds(rounds))
        if cooldownSeconds > 0 {
            parts.append("\(DurationFormat.spoken(cooldownSeconds)) cooldown")
        }
        parts.append("total \(DurationFormat.spoken(totalSeconds))")
        return "\(name). " + parts.joined(separator: ", ")
    }
}
