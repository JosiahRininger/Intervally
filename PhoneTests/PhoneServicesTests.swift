//
//  PhoneServicesTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// When the iPhone app's store starts, and what coming forward does.
@Suite("Phone services")
@MainActor
struct PhoneServicesTests {
    let defaults = makeTestDefaults()
    /// Entitlement reads, so a test can tell a started store from one that never ran.
    let reads = Counter()

    private func makeServices() -> PhoneServices {
        let reads = reads
        let pro = ProStore(defaults: defaults, readOwnership: {
            reads.increment()
            return .none
        })
        return PhoneServices(store: WorkoutStore(defaults: defaults), pro: pro)
    }

    @Test("In the unit-test host the store never starts, and coming forward reads nothing")
    func staysOffInTheHost() async {
        let services = makeServices()
        services.start(isUnitTestHost: true)
        #expect(services.pro.isListening == false)

        await services.handleForeground()
        #expect(reads.value == 0)
    }

    @Test("A normal launch listens for transactions, and coming forward reads the entitlement")
    func startsOtherwise() async {
        let services = makeServices()
        defer { services.pro.stop() }
        services.start(isUnitTestHost: false)
        #expect(services.pro.isListening)

        let before = reads.value
        await services.handleForeground()
        #expect(reads.value > before)
    }

    @Test("By default start() asks this process, which is the test host")
    func defaultsToThisProcess() {
        let services = makeServices()
        services.start()
        #expect(services.pro.isListening == false)
    }

    #if DEBUG
    @Test("A test's own services never replace the app's")
    func currentIsTheApp() throws {
        let app = try #require(PhoneServices.current)
        _ = makeServices()
        #expect(PhoneServices.current === app)
    }
    #endif
}
