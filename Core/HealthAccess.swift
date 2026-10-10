//
//  HealthAccess.swift
//  Intervally
//

import Foundation

/// What each app asks Health for, by type identifier, so both suites can hold them together.
///
/// To Health the watch app and the iPhone app are one app, and the newest request for a type
/// decides what that app has asked for (paired simulators). The iPhone's read-only request
/// left the watch unable to save workouts ("Not authorized"), and the watch's write-only one
/// sent History back to Connect. So every request asks for the same thing: to read
/// everything History reads, and to write workouts, which a run saves on either device.
enum HealthAccess {
    /// What History on the iPhone reads.
    static let historyReads: Set<String> = [
        "HKWorkoutTypeIdentifier",
        "HKQuantityTypeIdentifierHeartRate",
        "HKQuantityTypeIdentifierActiveEnergyBurned",
    ]
    /// What a run writes, on the watch or on iPhone: each session, as a workout.
    static let watchWrites: Set<String> = ["HKWorkoutTypeIdentifier"]
}
