//
//  ManualQAStoreKit.swift
//  IntervallyTests
//

#if DEBUG
import Testing
import Foundation
import StoreKitTest
@testable import Intervally

/// Opt-in manual QA: holds a live StoreKit test environment open inside the test host for
/// ten minutes, with the app's own store started, so the paywall can be driven by hand in
/// the simulator — real price, purchase sheet and all — without Xcode's Run action.
///
/// Skipped in every normal run. To use it:
///
///     TEST_RUNNER_INTERVALLY_QA_STOREKIT=1 xcodebuild test -project Intervally.xcodeproj \
///       -scheme Intervally -destination 'platform=watchOS Simulator,id=<claimed UDID>' \
///       -only-testing:IntervallyTests/ManualQAStoreKit
///
/// Unproven on watchOS: that the `TEST_RUNNER_` prefix reaches the host process, and that
/// the host's UI stays interactive during a hosted test. If either fails, use Xcode's Run
/// action (the scheme carries `Intervally.storekit`) or TestFlight.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["INTERVALLY_QA_STOREKIT"] == "1"))
@MainActor struct ManualQAStoreKit {
    @Test(.timeLimit(.minutes(15))) func idleWithStoreKitSession() async throws {
        let session = try SKTestSession(contentsOf: #require(Bundle(for: BundleToken.self)
            .url(forResource: "Intervally", withExtension: "storekit")))
        session.resetToDefaultState(); session.disableDialogs = false; session.clearTransactions()
        try #require(AppDelegate.current).pro.start()   // the delegate skipped start() under tests
        try await Task.sleep(for: .seconds(600))         // drive the UI in the simulator meanwhile
        // ARC may release a local after its last use; keep the session alive through the sleep.
        withExtendedLifetime(session) {}
    }
}
#endif
