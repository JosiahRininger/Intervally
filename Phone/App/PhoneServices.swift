//
//  PhoneServices.swift
//  IntervallyPhone
//

import Foundation

/// Owns the iPhone app's long-lived services.
///
/// Built once in `IntervallyPhoneApp.init`, before any view, so the transaction listener is
/// running from the first moment of the launch.
@MainActor
final class PhoneServices {

    let store: WorkoutStore
    /// Intervally Pro. The iPhone holds the same purchase as the watch: StoreKit reports it on
    /// each device, and nothing about it is relayed between them.
    let pro: ProStore

    #if DEBUG
    /// The services the running app was launched with, so the unit tests can check that the
    /// host app's store never started. Never set by a test's own instances.
    static weak var current: PhoneServices?
    #endif

    init(store: WorkoutStore = WorkoutStore(), pro: ProStore = ProStore()) {
        self.store = store
        self.pro = pro
    }

    /// The app's own services, started. The only place the app creates them.
    static func launch() -> PhoneServices {
        let services = PhoneServices()
        #if DEBUG
        current = services
        #endif
        services.start()
        return services
    }

    /// Starts what runs for the app's whole life. Apple asks for the transaction listener at
    /// launch: a transaction that finished while the app was away (an Ask to Buy approval, a
    /// refund, a purchase made on the watch) is delivered once, right then. Skipped in the
    /// unit-test host, where the real store would finish the test session's transactions.
    func start(isUnitTestHost: Bool = UnitTestHost.isActive) {
        guard !isUnitTestHost else { return }
        pro.start()
    }

    /// The app came forward. Reads the entitlement again, so a purchase or refund made on
    /// another device shows without a relaunch; a store that never started reads nothing.
    func handleForeground() async {
        await pro.handleForeground()
    }
}
