//
//  SimulatorEntitlementsTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing

/// The simulator build signs with its own entitlements file, so StoreKit testing works
/// (project.yml). It must stay the app's entitlements plus `get-task-allow` and nothing else,
/// or simulator runs would stop showing what a device build does. Read from the source tree,
/// which the simulator shares with the Mac.
@Suite("Simulator entitlements")
struct SimulatorEntitlementsTests {
    private static let supporting = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Supporting")

    private func entitlements(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Self.supporting.appendingPathComponent(name))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any])
    }

    @Test("The app's entitlements plus get-task-allow, and nothing else")
    func matchesTheApp() throws {
        let app = try entitlements("IntervallyPhone.entitlements")
        var simulator = try entitlements("IntervallyPhone-Simulator.entitlements")
        #expect(simulator.removeValue(forKey: "get-task-allow") as? Bool == true)
        #expect(NSDictionary(dictionary: simulator).isEqual(to: app))
    }

    @Test("Device and archive builds never carry get-task-allow from a file")
    func appFileHasNoTaskAllow() throws {
        #expect(try entitlements("IntervallyPhone.entitlements")["get-task-allow"] == nil)
    }
}
