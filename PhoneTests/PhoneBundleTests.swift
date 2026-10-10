//
//  PhoneBundleTests.swift
//  IntervallyPhoneTests
//

import Foundation
import HealthKit
import Testing
import UIKit
@testable import IntervallyPhone

/// The iPhone app's own packaging: what App Store Connect and App Review read from the
/// bundle before anyone opens the app.
@Suite("iPhone bundle")
struct PhoneBundleTests {
    let info = Bundle.main.infoDictionary ?? [:]

    @Test("Uploads answer the export-compliance question without a prompt")
    func encryptionAnswered() {
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
    }

    /// A run on iPhone saves its workout, so both purpose strings say what they are for, and
    /// the write one no longer says the iPhone only reads.
    @Test("Both Health purpose strings say what they are for")
    func healthPurposes() throws {
        #expect(HealthHistory.shareTypes == [HKObjectType.workoutType()])
        let read = try #require(info["NSHealthShareUsageDescription"] as? String)
        #expect(read.contains("interval workouts"))
        let write = try #require(info["NSHealthUpdateUsageDescription"] as? String)
        #expect(write.contains("saves your interval sessions"))
        #expect(!write.contains("only reads"))
    }

    @Test("Runs keep going locked: the audio mode for cues, and Live Activities on")
    func runCapabilities() throws {
        let modes = try #require(info["UIBackgroundModes"] as? [String])
        #expect(modes == ["audio"])
        #expect(info["NSSupportsLiveActivities"] as? Bool == true)
    }

    @Test("The icon comes from the asset catalog")
    func appIcon() throws {
        let icons = try #require(info["CFBundleIcons"] as? [String: Any])
        let primary = try #require(icons["CFBundlePrimaryIcon"] as? [String: Any])
        #expect(primary["CFBundleIconName"] as? String == "AppIcon")
    }

    @Test("Launches on the black the whole app is drawn on")
    func launchScreen() throws {
        let screen = try #require(info["UILaunchScreen"] as? [String: Any])
        let name = try #require(screen["UIColorName"] as? String)
        let color = try #require(UIColor(named: name, in: .main, compatibleWith: nil))
        var (red, green, blue, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (-1, -1, -1, -1)
        #expect(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        #expect([red, green, blue, alpha] == [0, 0, 0, 1])
        #expect(info["UIUserInterfaceStyle"] as? String == "Dark")
    }

    @Test("The privacy manifest declares the app's own defaults and nothing else")
    func privacyManifest() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        let manifest = try #require(plist as? [String: Any])
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)

        let accessed = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        #expect(accessed.count == 1)
        #expect(accessed.first?["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults")
        // CA92.1 only: there is no App Group on iPhone, so 1C8F.1 would be a false claim.
        #expect(accessed.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
    }

    @Test("The StoreKit configuration ships in the test bundle and never in the app")
    func storeKitConfigurationIsTestOnly() {
        #expect(Bundle.main.url(forResource: "Intervally", withExtension: "storekit") == nil)
        #expect(Bundle(for: BundleToken.self).url(forResource: "Intervally", withExtension: "storekit") != nil)
    }
}
