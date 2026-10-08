//
//  CompanionBundleTests.swift
//  IntervallyTests
//

import Foundation
import Testing
@testable import Intervally

/// A simulator build checks none of this. The iPhone's installd does, when it installs the
/// iPhone app that embeds this one, and App Store Connect does at upload. So the watch app's
/// companion keys are pinned here, in the test host, which is the watch app itself.
@Suite("Companion bundle")
struct CompanionBundleTests {
    let info = Bundle.main.infoDictionary ?? [:]

    @Test("The iPhone app is named as the companion, and this app's ID is a child of it")
    func namesTheIPhoneAppAsItsCompanion() throws {
        let companion = try #require(info["WKCompanionAppBundleIdentifier"] as? String)
        #expect(companion == "com.josiahrininger.intervally")
        // installd: a watch app's bundle ID must be the companion's ID followed by a '.'.
        #expect(Bundle.main.bundleIdentifier == companion + ".watchkitapp")
    }

    @Test("It still runs without the iPhone app, and is no longer watch-only")
    func runsWithoutTheIPhoneApp() {
        #expect(info["WKRunsIndependentlyOfCompanionApp"] as? Bool == true)
        // installd rejects an iPhone app that embeds a watch-only app.
        #expect(info["WKWatchOnly"] == nil)
        #expect(info["ITSWatchOnlyContainer"] == nil)
        #expect(info["WKApplication"] as? Bool == true)
    }

    @Test("The widget's ID is a child of the watch app's, and its version matches")
    func widgetSitsUnderTheWatchApp() throws {
        let url = try #require(Bundle.main.builtInPlugInsURL?.appendingPathComponent("IntervallyWidgetExtension.appex"))
        let widget = try #require(Bundle(url: url))
        let watchID = try #require(Bundle.main.bundleIdentifier)
        #expect(widget.bundleIdentifier == watchID + ".widget")
        // App Store Connect rejects an upload whose embedded bundles disagree on either.
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            let version = widget.object(forInfoDictionaryKey: key) as? String
            #expect(version != nil)
            #expect(version == info[key] as? String, "\(key) differs")
        }
    }

    /// `ProStoreStoreKitTests` held this (S12) until a companion watch app's StoreKit test
    /// session stopped working; the packaging rule still holds for the watch app.
    @Test("The StoreKit configuration ships in the test bundle and never in the watch app")
    func storeKitConfigurationIsTestOnly() {
        #expect(Bundle.main.url(forResource: "Intervally", withExtension: "storekit") == nil)
        #expect(Bundle(for: BundleToken.self).url(forResource: "Intervally", withExtension: "storekit") != nil)
    }
}
