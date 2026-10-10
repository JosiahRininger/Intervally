//
//  HealthHistory.swift
//  IntervallyPhone
//

import Foundation
import HealthKit

/// History from Apple Health: the interval workouts saved by a run on this iPhone, or by the
/// watch once Health has brought them over. History itself only reads.
final class HealthHistory: HistorySource {
    private let store = HKHealthStore()

    /// Workouts, which History never writes but a run on this iPhone saves. Asked here as
    /// well, so Connect and a run's first Start ask for exactly the same thing and neither
    /// request undoes the other's (`HealthAccess`).
    static let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]

    /// Only what History shows: the workouts, and the heart rate and energy inside them.
    static let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.heartRate),
        HKQuantityType(.activeEnergyBurned),
    ]

    /// Years of daily sessions, newest first. Each comes with its intervals, so there is a
    /// cap rather than everything Health holds.
    static let limit = 500

    /// Every workout the watch tags since History arrived, and nothing from any other app.
    static var predicate: NSPredicate {
        HKQuery.predicateForObjects(withMetadataKey: HealthMetadata.presetID)
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func access() async -> HistoryAccess {
        do {
            switch try await store.statusForAuthorizationRequest(toShare: Self.shareTypes, read: Self.readTypes) {
            case .shouldRequest: return .shouldRequest
            case .unnecessary: return .requested
            default: return .unknown
            }
        } catch {
            return .unknown
        }
    }

    func requestAccess() async throws {
        try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
    }

    func workouts() async throws -> [RawWorkout] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(Self.predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: Self.limit
        )
        return try await descriptor.result(for: store).map(RawWorkout.init)
    }
}

// MARK: - From HealthKit

private extension HKUnit {
    static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
}

extension RawWorkout {
    init(_ workout: HKWorkout) {
        let heartRate = workout.statistics(for: HKQuantityType(.heartRate))
        let tags = Self.tags(from: workout.metadata)
        self.init(
            id: workout.uuid,
            start: workout.startDate,
            duration: workout.duration,
            presetName: tags.name,
            plannedRounds: tags.plannedRounds,
            averageHeartRate: heartRate?.averageQuantity()?.doubleValue(for: .beatsPerMinute),
            maximumHeartRate: heartRate?.maximumQuantity()?.doubleValue(for: .beatsPerMinute),
            activeEnergy: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie()),
            activities: workout.workoutActivities.map(Activity.init),
            activity: WorkoutActivity(
                workout.workoutActivityType,
                indoor: (workout.metadata?[HKMetadataKeyIndoorWorkout] as? NSNumber)?.boolValue
            )
        )
    }

    /// The workout's own tags, read leniently: a value of the wrong type is as good as none,
    /// rather than a reason to drop the session.
    static func tags(from metadata: [String: Any]?) -> (name: String?, plannedRounds: Int?) {
        (
            metadata?[HealthMetadata.presetName] as? String,
            (metadata?[HealthMetadata.plannedRounds] as? NSNumber)?.intValue
        )
    }
}

extension RawWorkout.Activity {
    init(_ activity: HKWorkoutActivity) {
        self.init(
            phase: activity.metadata?[HealthMetadata.phase] as? String,
            round: (activity.metadata?[HealthMetadata.round] as? NSNumber)?.intValue,
            start: activity.startDate,
            duration: activity.duration,
            averageHeartRate: activity.statistics(for: HKQuantityType(.heartRate))?
                .averageQuantity()?.doubleValue(for: .beatsPerMinute),
            // Each interval is its own workout activity, so Health sums its energy on its own.
            activeEnergy: activity.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie())
        )
    }
}
