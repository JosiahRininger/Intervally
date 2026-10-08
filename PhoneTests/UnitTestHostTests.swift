//
//  UnitTestHostTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

#if DEBUG
/// The real `ProStore` must stay off in the iPhone test host too, or it would finish a
/// StoreKit suite's transactions and rewrite the cached flag while other suites run.
@Suite("Unit-test host")
@MainActor
struct UnitTestHostTests {

    @Test("Either variable marks the unit-test host; a normal launch has neither")
    func detection() {
        #expect(UnitTestHost.isActive(in: [:]) == false)
        #expect(UnitTestHost.isActive(in: ["INTERVALLY_UNIT_TESTS": "1"]))
        #expect(UnitTestHost.isActive(in: ["XCTestConfigurationFilePath": "/tmp/IntervallyPhone.xctestconfiguration"]))
        #expect(UnitTestHost.isActive(in: ["PATH": "/usr/bin"]) == false)
    }

    @Test("This process is the host, and the app's own ProStore never started")
    func appStoreStaysOff() throws {
        #expect(UnitTestHost.isActive)
        let services = try #require(PhoneServices.current, "The host app launched its services")
        #expect(services.pro.isListening == false)
    }
}
#endif
