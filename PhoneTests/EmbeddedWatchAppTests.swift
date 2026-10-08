//
//  EmbeddedWatchAppTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// The packaging rules a Simulator build never enforces. The iOS installd rejects an iPhone
/// app whose embedded watch app is watch-only, names another companion, or has an ID that
/// isn't the iPhone app's ID plus a dot; App Store Connect rejects bundles whose versions
/// disagree. The host app here is the real IntervallyPhone.app, watch app and all.
@Suite("Embedded watch app")
struct EmbeddedWatchAppTests {
    static let watchPath = "Watch/Intervally.app"
    static let widgetPath = "PlugIns/IntervallyWidgetExtension.appex"

    let phone = Bundle.main

    private func watch() throws -> Bundle {
        try #require(Bundle(url: phone.bundleURL.appending(path: Self.watchPath)), "no \(Self.watchPath)")
    }

    private func widget() throws -> Bundle {
        let url = try watch().bundleURL.appending(path: Self.widgetPath)
        return try #require(Bundle(url: url), "no \(Self.widgetPath) in the watch app")
    }

    @Test("The watch app and its widget are embedded where the App Store looks for them")
    func embedded() throws {
        let watchURL = phone.bundleURL.appending(path: Self.watchPath)
        #expect(FileManager.default.fileExists(atPath: watchURL.appending(path: "Info.plist").path))
        #expect(FileManager.default.fileExists(atPath: watchURL.appending(path: Self.widgetPath).path))
        // The watch app's own executable, not just a folder with the right name.
        #expect(try watch().executableURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    @Test("The iPhone app holds the root ID; the watch app and widget are dotted children of it")
    func identifiers() throws {
        let phoneID = try #require(phone.bundleIdentifier)
        #expect(phoneID == "com.josiahrininger.intervally")
        let watchID = try #require(try watch().bundleIdentifier)
        #expect(watchID == phoneID + ".watchkitapp")
        #expect(try widget().bundleIdentifier == watchID + ".widget")
    }

    @Test("The watch app names this app as its companion and still runs without it")
    func companion() throws {
        let watch = try watch()
        #expect(watch.object(forInfoDictionaryKey: "WKCompanionAppBundleIdentifier") as? String == phone.bundleIdentifier)
        #expect(watch.object(forInfoDictionaryKey: "WKRunsIndependentlyOfCompanionApp") as? Bool == true)
        #expect(watch.object(forInfoDictionaryKey: "WKApplication") as? Bool == true)
    }

    @Test("All three bundles carry one version and one build", arguments: ["CFBundleShortVersionString", "CFBundleVersion"])
    func versionsMatch(key: String) throws {
        let mine = try #require(phone.object(forInfoDictionaryKey: key) as? String)
        #expect(try watch().object(forInfoDictionaryKey: key) as? String == mine)
        #expect(try widget().object(forInfoDictionaryKey: key) as? String == mine)
    }

    @Test("No bundle is marked watch-only")
    func nothingWatchOnly() throws {
        for bundle in [phone, try watch(), try widget()] {
            let name = bundle.bundleURL.lastPathComponent
            #expect(bundle.object(forInfoDictionaryKey: "WKWatchOnly") == nil, "\(name) has WKWatchOnly")
            #expect(bundle.object(forInfoDictionaryKey: "ITSWatchOnlyContainer") == nil, "\(name) has ITSWatchOnlyContainer")
        }
    }
}
