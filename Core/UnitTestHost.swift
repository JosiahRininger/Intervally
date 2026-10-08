//
//  UnitTestHost.swift
//  Intervally
//

import Foundation

/// Whether this process is hosting the unit tests, on the watch or the iPhone.
///
/// Inside the host the real `ProStore` must not run: it would finish the test session's
/// transactions and rewrite the cached flag behind the tests' backs. Each scheme's test
/// action sets `INTERVALLY_UNIT_TESTS`; `XCTestConfigurationFilePath` covers a run where the
/// scheme's variables don't reach the host, as can happen on watchOS.
enum UnitTestHost {
    /// This process's answer. Always false in Release.
    static var isActive: Bool {
        isActive(in: ProcessInfo.processInfo.environment)
    }

    /// The answer for `environment`. Always false in Release, so a stray variable can never
    /// keep a shipping app's store from starting.
    static func isActive(in environment: [String: String]) -> Bool {
        #if DEBUG
        environment["INTERVALLY_UNIT_TESTS"] != nil || environment["XCTestConfigurationFilePath"] != nil
        #else
        false
        #endif
    }
}
