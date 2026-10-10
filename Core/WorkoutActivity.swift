//
//  WorkoutActivity.swift
//  Intervally
//

import Foundation

/// What a preset's workout is, as Apple Health records it: the type Fitness shows and
/// counts it under, and on Apple Watch the one its calorie estimate is made for. Chosen per
/// preset on iPhone; the watch runs whatever its preset says.
///
/// The cases are the kinds of training an interval timer is used for, under Apple's own
/// names. Outdoor and indoor are separate choices where Apple tells them apart. The raw
/// values are stored and synced, so they never change.
enum WorkoutActivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case hiit
    case mixedCardio
    case jumpRope
    case dance
    case outdoorRun
    case indoorRun
    case outdoorWalk
    case indoorWalk
    case outdoorCycle
    case indoorCycle
    case rowing
    case elliptical
    case stairStepper
    case strength
    case functionalStrength
    case core
    case crossTraining
    case boxing
    case kickboxing
    case yoga
    case pilates

    /// Every preset's until it is changed, and every workout saved before there was a choice.
    static let standard = WorkoutActivity.hiit

    var id: Self { self }

    var title: String {
        switch self {
        case .hiit: "HIIT"
        case .mixedCardio: "Mixed Cardio"
        case .jumpRope: "Jump Rope"
        case .dance: "Dance"
        case .outdoorRun: "Outdoor Run"
        case .indoorRun: "Indoor Run"
        case .outdoorWalk: "Outdoor Walk"
        case .indoorWalk: "Indoor Walk"
        case .outdoorCycle: "Outdoor Cycle"
        case .indoorCycle: "Indoor Cycle"
        case .rowing: "Rowing"
        case .elliptical: "Elliptical"
        case .stairStepper: "Stair Stepper"
        case .strength: "Strength Training"
        case .functionalStrength: "Functional Strength"
        case .core: "Core Training"
        case .crossTraining: "Cross Training"
        case .boxing: "Boxing"
        case .kickboxing: "Kickboxing"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        }
    }

    /// The figure Apple draws for it.
    var symbolName: String {
        switch self {
        case .hiit: "figure.highintensity.intervaltraining"
        case .mixedCardio: "figure.mixed.cardio"
        case .jumpRope: "figure.jumprope"
        case .dance: "figure.dance"
        case .outdoorRun: "figure.run"
        case .indoorRun: "figure.run.treadmill"
        case .outdoorWalk: "figure.walk"
        case .indoorWalk: "figure.walk.treadmill"
        case .outdoorCycle: "figure.outdoor.cycle"
        case .indoorCycle: "figure.indoor.cycle"
        case .rowing: "figure.rower"
        case .elliptical: "figure.elliptical"
        case .stairStepper: "figure.stair.stepper"
        case .strength: "figure.strengthtraining.traditional"
        case .functionalStrength: "figure.strengthtraining.functional"
        case .core: "figure.core.training"
        case .crossTraining: "figure.cross.training"
        case .boxing: "figure.boxing"
        case .kickboxing: "figure.kickboxing"
        case .yoga: "figure.yoga"
        case .pilates: "figure.pilates"
        }
    }

    /// Whether Health records it as done outdoors.
    var isOutdoor: Bool {
        switch self {
        case .outdoorRun, .outdoorWalk, .outdoorCycle: true
        default: false
        }
    }

    /// The picker's groups, each case in exactly one.
    enum Group: String, CaseIterable, Identifiable, Sendable {
        case cardio = "Interval & Cardio"
        case distance = "Run, Walk & Ride"
        case machines = "Machines"
        case strength = "Strength & Combat"
        case mindAndBody = "Mind & Body"

        var id: Self { self }

        var activities: [WorkoutActivity] {
            switch self {
            case .cardio: [.hiit, .mixedCardio, .jumpRope, .dance]
            case .distance: [.outdoorRun, .indoorRun, .outdoorWalk, .indoorWalk, .outdoorCycle, .indoorCycle]
            case .machines: [.rowing, .elliptical, .stairStepper]
            case .strength: [.strength, .functionalStrength, .core, .crossTraining, .boxing, .kickboxing]
            case .mindAndBody: [.yoga, .pilates]
            }
        }
    }

    /// Other words people search for it by.
    private var keywords: String {
        switch self {
        case .hiit: "high intensity interval training tabata emom circuit"
        case .mixedCardio: "cardio conditioning"
        case .jumpRope: "skipping"
        case .dance: "cardio dance"
        case .outdoorRun: "running jog jogging"
        case .indoorRun: "treadmill running jog jogging"
        case .outdoorWalk: "walking hike hiking"
        case .indoorWalk: "treadmill walking"
        case .outdoorCycle: "bike biking cycling ride"
        case .indoorCycle: "bike biking cycling spin stationary ride"
        case .rowing: "rower erg"
        case .elliptical: "cross trainer"
        case .stairStepper: "stairs climbing stairmaster"
        case .strength: "weights lifting weightlifting gym"
        case .functionalStrength: "kettlebell weights bodyweight"
        case .core: "abs"
        case .crossTraining: "crossfit"
        case .boxing: "punching bag"
        case .kickboxing: "martial arts muay thai"
        case .yoga: "stretching flow"
        case .pilates: "reformer"
        }
    }

    /// The picker's search: every word typed must start a word of the title or a keyword,
    /// so "run" finds both runs and "out" every outdoor choice. An empty search matches
    /// everything.
    func matches(_ search: String) -> Bool {
        let terms = search.lowercased().split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return true }
        let words = "\(title) \(keywords)".lowercased().split(whereSeparator: { !$0.isLetter })
        return terms.allSatisfy { term in words.contains { $0.hasPrefix(term) } }
    }
}
