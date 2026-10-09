//
//  HealthMetadata.swift
//  Intervally
//

import Foundation

/// The metadata keys the watch writes to Health and the iPhone's History reads back. Both
/// ends name them from here, so a rename can't split them, and none may ever be renamed:
/// workouts already in Health keep the key they were saved with.
enum HealthMetadata {
    /// On the workout: the preset that ran, as a UUID string. History finds Intervally's
    /// workouts by this key alone.
    static let presetID = "IntervallyPresetID"
    /// On the workout: the preset's name when it ran, so a rename later doesn't rewrite what
    /// History says about the past.
    static let presetName = "IntervallyPresetName"
    /// On the workout: the rounds the run was planned for, which History counts an early
    /// end against.
    static let plannedRounds = "IntervallyPlannedRounds"
    /// On each interval's activity: its `IntervalPhase.Kind` raw value.
    static let phase = "IntervallyPhase"
    /// On each interval's activity: its 1-based round. The warmup and cooldown carry none.
    static let round = "IntervallyRound"
}
