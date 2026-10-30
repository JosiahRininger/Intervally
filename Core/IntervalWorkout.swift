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
    /// (`fillingAbsent(from:)`). Read `activityKind`.
    var activity: WorkoutActivity?
    /// The phases the preset renamed or gave another figure, by `IntervalPhase.Kind` raw
    /// value. Nil from a version that predates them; once touched, emptied rather than set
    /// back to nil (`setLabel(_:for:)`). Read `label(for:)`.
    var phaseLabels: [String: PhaseLabel]?

    init(
        id: UUID = UUID(),
        name: String = "Workout",
        prepareSeconds: Int = 10,
        warmupSeconds: Int = 0,
        workSeconds: Int = 30,
        restSeconds: Int = 15,
        rounds: Int = 8,
        cooldownSeconds: Int = 0,
        activity: WorkoutActivity? = nil,
        phaseLabels: [String: PhaseLabel]? = nil
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
        self.phaseLabels = phaseLabels
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
        // as it did before there was a choice. Each one goes in `fillingAbsent(from:)` too.
        case activity
        case phaseLabels
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
            activity: try? container.decodeIfPresent(WorkoutActivity.self, forKey: .activity),
            phaseLabels: Self.decodeLabels(from: container)
        )
    }

    /// Each label on its own, so one a later version writes differently costs only itself.
    private static func decodeLabels(from container: KeyedDecodingContainer<CodingKeys>) -> [String: PhaseLabel]? {
        guard let raw = try? container.decodeIfPresent([String: LenientLabel].self, forKey: .phaseLabels) else { return nil }
        return raw.compactMapValues(\.label)
    }

    private struct LenientLabel: Decodable {
        let label: PhaseLabel?
        init(from decoder: Decoder) throws {
            label = try? PhaseLabel(from: decoder)
        }
    }

    // MARK: - Merging

    /// This preset with each optional field it lacks taken from `other`: today `activity` and
    /// `phaseLabels`. A merge fills the winning copy from the losing one this way
    /// (`PresetRecord.merged`), so an edit from a version that predates a field never resets
    /// it on either device.
    ///
    /// Every Optional stored property added later must be listed here, encoded only when
    /// non-nil, and never set back to nil once touched (emptied instead, as `setLabel` does):
    /// nil is what a version that predates the field sends, so here it can only mean "not
    /// known", never "cleared". `IntervalWorkoutTests` fails for one that is left out.
    func fillingAbsent(from other: IntervalWorkout) -> IntervalWorkout {
        var filled = self
        filled.activity = activity ?? other.activity
        filled.phaseLabels = phaseLabels ?? other.phaseLabels
        return filled
    }

    // MARK: - Limits

    static let workRange = 5...3600
    static let restRange = 0...3600
    /// Up to five minutes: time to walk to the track or set up the bike, not only to breathe.
    static let prepareRange = 0...300
    static let roundsRange = 1...99
    static let warmupRange = 0...1800
    static let cooldownRange = 0...1800

    /// Crown detents for both bookends: Off, 0:30 to 5:00 by 30 seconds, then 6:00 to 30:00
    /// by the minute. The work table's 5- and 15-second bands would make 77 uneven detents
    /// for a phase nobody sets to the second.
    static let bookendValues: [Int] = [0]
        + Array(stride(from: 30, through: 300, by: 30))
        + Array(stride(from: 360, through: 1800, by: 60))

    /// Long enough for "Saturday Hill Sprints with the Club". Without a cap a name could be
    /// any length, and sync sends every preset's name, deleted ones too, in one document
    /// (`PayloadBudgetTests`). Counted in characters as they are seen, so an emoji is one.
    static let maxNameLength = 40

    /// A name as it is saved: trimmed, `fallback` when nothing is left, then cut to
    /// `maxNameLength` characters and trimmed again, so a cut never leaves a space at the
    /// end. Every create, rename and duplicate on both devices names presets through it, and
    /// `clamped` holds every save to it.
    static func committedName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = trimmed.isEmpty ? fallback : trimmed
        return String(chosen.prefix(maxNameLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What a name field showing `field` saves over the `stored` name, or nil when it saves
    /// nothing: the field left as it was, or typed back to the same name. A name kept longer
    /// than the cap from 1.2 is cut when someone renames it, not because its editor was
    /// opened and closed, which would sync a change nobody made.
    static func savedName(typed field: String, stored: String) -> String? {
        guard field != stored else { return nil }
        let committed = committedName(field, fallback: stored)
        return committed == stored ? nil : committed
    }

    /// A copy with every field clamped into its supported range, and the name held to its
    /// cap. A name left empty is the default's, as a preset decoded without one gets.
    var clamped: IntervalWorkout {
        var copy = self
        copy.name = Self.committedName(name, fallback: Self.default.name)
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
