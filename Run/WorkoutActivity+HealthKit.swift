//
//  WorkoutActivity+HealthKit.swift
//  Intervally
//

import HealthKit

extension WorkoutActivity {
    /// The type the workout session runs and Health saves it as.
    var healthKitType: HKWorkoutActivityType {
        switch self {
        case .hiit: .highIntensityIntervalTraining
        case .mixedCardio: .mixedCardio
        case .jumpRope: .jumpRope
        case .dance: .cardioDance
        case .outdoorRun, .indoorRun: .running
        case .outdoorWalk, .indoorWalk: .walking
        case .outdoorCycle, .indoorCycle: .cycling
        case .rowing: .rowing
        case .elliptical: .elliptical
        case .stairStepper: .stairClimbing
        case .strength: .traditionalStrengthTraining
        case .functionalStrength: .functionalStrengthTraining
        case .core: .coreTraining
        case .crossTraining: .crossTraining
        case .boxing: .boxing
        case .kickboxing: .kickboxing
        case .yoga: .yoga
        case .pilates: .pilates
        }
    }

    /// The session's configuration. Indoor unless the activity says outdoor: Fitness shows
    /// an "Indoor Run", and the watch measures it without GPS.
    var configuration: HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = healthKitType
        configuration.locationType = isOutdoor ? .outdoor : .indoor
        return configuration
    }

    /// The activity a saved workout was recorded as, for History: nil for a type the picker
    /// doesn't offer. Outdoor and indoor are told apart by Health's own indoor flag.
    init?(_ type: HKWorkoutActivityType, indoor: Bool?) {
        let indoor = indoor ?? true
        switch type {
        case .highIntensityIntervalTraining: self = .hiit
        case .mixedCardio: self = .mixedCardio
        case .jumpRope: self = .jumpRope
        case .cardioDance: self = .dance
        case .running: self = indoor ? .indoorRun : .outdoorRun
        case .walking: self = indoor ? .indoorWalk : .outdoorWalk
        case .cycling: self = indoor ? .indoorCycle : .outdoorCycle
        case .rowing: self = .rowing
        case .elliptical: self = .elliptical
        case .stairClimbing: self = .stairStepper
        case .traditionalStrengthTraining: self = .strength
        case .functionalStrengthTraining: self = .functionalStrength
        case .coreTraining: self = .core
        case .crossTraining: self = .crossTraining
        case .boxing: self = .boxing
        case .kickboxing: self = .kickboxing
        case .yoga: self = .yoga
        case .pilates: self = .pilates
        default: return nil
        }
    }
}
