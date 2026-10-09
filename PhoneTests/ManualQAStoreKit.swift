//
//  ManualQAStoreKit.swift
//  IntervallyPhoneTests
//

#if DEBUG
import Testing
import Foundation
import StoreKitTest
@testable import IntervallyPhone

/// Opt-in manual QA, the iPhone twin of the watch's: holds a live StoreKit test environment
/// open inside the test host for ten minutes, with the app's own store started, so the
/// paywall, Restore and Settings' purchase rows can be driven by hand in the simulator with
/// the real price and purchase sheet, without Xcode's Run action.
///
/// Skipped in every normal run. To use it:
///
///     TEST_RUNNER_INTERVALLY_QA_STOREKIT=1 xcodebuild test -project Intervally.xcodeproj \
///       -scheme IntervallyPhone -destination 'platform=iOS Simulator,id=<claimed UDID>' \
///       -only-testing:IntervallyPhoneTests/ManualQAStoreKit
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTERVALLY_QA_STOREKIT"] == "1"))
@MainActor struct ManualQAStoreKit {
    @Test(.timeLimit(.minutes(15))) func idleWithStoreKitSession() async throws {
        let session = try SKTestSession(contentsOf: #require(Bundle(for: BundleToken.self)
            .url(forResource: "Intervally", withExtension: "storekit")))
        session.resetToDefaultState(); session.disableDialogs = false; session.clearTransactions()
        try #require(PhoneServices.current).pro.start()   // launch() skipped start() under tests
        try await Task.sleep(for: .seconds(600))           // drive the UI in the simulator meanwhile
        // ARC may release a local after its last use; keep the session alive through the sleep.
        withExtendedLifetime(session) {}
    }
}
#endif
