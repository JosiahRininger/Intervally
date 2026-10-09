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
/// sent History back to Connect. So the watch asks to read everything History reads as well
/// as to write workouts: once it has asked, the iPhone has nothing left to ask, and the
/// iPhone never asks to write.
enum HealthAccess {
    /// What History on the iPhone reads.
    static let historyReads: Set<String> = [
        "HKWorkoutTypeIdentifier",
        "HKQuantityTypeIdentifierHeartRate",
        "HKQuantityTypeIdentifierActiveEnergyBurned",
    ]
    /// What the watch writes: each session, as a workout.
    static let watchWrites: Set<String> = ["HKWorkoutTypeIdentifier"]
}
