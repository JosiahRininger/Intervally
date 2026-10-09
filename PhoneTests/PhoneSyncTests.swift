//
//  PhoneSyncTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// When the iPhone app starts sync, and what leaving the foreground does to a waiting edit.
@Suite("Phone sync")
@MainActor
struct PhoneSyncTests {
    let defaults = makeTestDefaults()
    let transport = FakeTransport()

    private func makeServices(sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in throw CancellationError() }) -> PhoneServices {
        let store = WorkoutStore(defaults: defaults)
        let pro = ProStore(defaults: defaults, readOwnership: { .none })
        return PhoneServices(store: store, pro: pro, sync: WatchSync(store: store, transport: transport, sleep: sleep))
    }

    @Test("A normal launch activates sync along with the store")
    func startActivates() {
        let services = makeServices()
        defer { services.pro.stop() }
        services.start(isUnitTestHost: false)
        #expect(transport.activations == 1)
        #expect(services.sync.isActive)
    }

    @Test("The unit-test host never activates sync")
    func hostStaysOff() {
        let services = makeServices()
        services.start(isUnitTestHost: true)
        #expect(transport.activations == 0)
        #expect(services.sync.isActive == false)
    }

    @Test("By default the services sync the store they were given")
    func defaultSyncUsesTheStore() {
        let store = WorkoutStore(defaults: defaults)
        let services = PhoneServices(store: store, pro: ProStore(defaults: defaults))
        #expect(store.onLocalChange != nil)
        // The real transport, which the test host keeps away from the paired watch.
        #expect(services.sync.peer == .unsupported)
    }

    #if DEBUG
    @Test("The app's own sync never started in the test host")
    func appSyncStaysOff() throws {
        let app = try #require(PhoneServices.current)
        #expect(app.sync.isActive == false)
    }
    #endif

    @Test("Leaving the foreground sends an edit still waiting out the debounce")
    func backgroundFlushes() async {
        let sleeper = ManualSleeper()
        let services = makeServices(sleep: sleeper.sleep)
        var workout = services.store.workouts[0]
        workout.name = "Before bed"
        services.store.update(workout)
        #expect(transport.sent.isEmpty)

        services.handleBackground()
        #expect(transport.sentDocuments == [services.store.document])

        // The debounce still running finds nothing left to send.
        #expect(await waitUntil { sleeper.requested.count == 1 })
        sleeper.wakeAll()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(transport.sent.count == 1)
    }
}
