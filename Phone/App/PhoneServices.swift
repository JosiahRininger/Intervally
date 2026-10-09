//
//  PhoneServices.swift
//  IntervallyPhone
//

import Foundation
import os

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
    /// Keeps the presets in step with the watch. Pro never travels this way.
    let sync: WatchSync
    /// The sessions the watch saved to Health. Reads nothing until History is first shown.
    let history: HistoryModel

    #if DEBUG
    /// The services the running app was launched with, so the unit tests can check that the
    /// host app's store never started. Never set by a test's own instances.
    static weak var current: PhoneServices?
    /// The QA flags this launch was given (`PhoneQAOptions`).
    private(set) var qa = PhoneQAOptions()
    #endif

    init(
        store: WorkoutStore = WorkoutStore(),
        pro: ProStore = ProStore(),
        sync: WatchSync? = nil,
        history: HistoryModel? = nil
    ) {
        self.store = store
        self.pro = pro
        self.sync = sync ?? WatchSync(store: store)
        self.history = history ?? HistoryModel(source: HealthHistory())
    }

    /// The app's own services, started. The only place the app creates them.
    static func launch() -> PhoneServices {
        #if DEBUG
        let qa = PhoneQAOptions.current
        let store = WorkoutStore()
        // A stand-in watch never reaches the real one, so a QA launch can't send it anything.
        let sync = qa.watch.map { WatchSync(store: store, transport: QAWatchTransport(state: $0, store: store)) }
        // A fixture in place of Health, so nothing is read from it or written to it.
        let history = qa.history.map { HistoryModel(source: SampleHistory(mode: $0)) }
        let services = PhoneServices(store: store, sync: sync, history: history)
        services.qa = qa
        current = services
        services.applyQAEdits()
        if let isPro = qa.pro { services.pro.overrideForQA(isPro) }
        #else
        let services = PhoneServices()
        #endif
        services.start()
        return services
    }

    /// Starts what runs for the app's whole life. Apple asks for the transaction listener at
    /// launch: a transaction that finished while the app was away (an Ask to Buy approval, a
    /// refund, a purchase made on the watch) is delivered once, right then. Sync starts as
    /// early, so a context the watch sent while the app was closed is merged before the
    /// first view. Both are skipped in the unit-test host, where the real store would finish
    /// the test session's transactions and sync would send test presets to the watch.
    func start(isUnitTestHost: Bool = UnitTestHost.isActive) {
        guard !isUnitTestHost else { return }
        pro.start()
        sync.activate()
    }

    /// The app came forward. Reads the entitlement again, so a purchase or refund made on
    /// another device shows without a relaunch; a store that never started reads nothing.
    /// History reads Health again alongside, if it has been opened: the watch may have saved
    /// a workout meanwhile.
    func handleForeground() async {
        async let history: Void = history.handleForeground()
        await pro.handleForeground()
        await history
    }

    /// The app is leaving the foreground: an edit still waiting to be sent goes now.
    func handleBackground() {
        sync.flush()
    }

    #if DEBUG
    /// QA hook for the paired-simulator sync checks, which have no editor to drive yet:
    /// `simctl launch <udid> <bundle> -qaEdit "rename 0 Sprint; select 2"` makes those
    /// edits as the user would, before sync starts. Debug builds only.
    private func applyQAEdits() {
        guard let spec = UserDefaults.standard.string(forKey: "qaEdit") else { return }
        let log = Logger(subsystem: "com.josiahrininger.intervally", category: "app")
        guard let edits = QAEdit.parse(spec) else {
            log.error("QA edits ignored, unreadable: \(spec, privacy: .public)")
            return
        }
        edits.forEach { $0.apply(to: store) }
        log.info("QA edits applied: \(spec, privacy: .public)")
    }
    #endif
}
