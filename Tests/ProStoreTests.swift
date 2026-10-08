//
//  ProStoreTests.swift
//  IntervallyTests
//

import Testing
import Foundation
import StoreKit
@testable import Intervally

/// Stands in for StoreKit's entitlement read: answers in order, the last one repeating, and
/// can hold any read open on a gate.
@MainActor
private final class ScriptedOwnership {
    private let answers: [ProStore.Ownership]
    private(set) var started = 0
    var gates: [Int: Gate] = [:]

    init(_ answers: ProStore.Ownership...) {
        self.answers = answers
    }

    func read() async -> ProStore.Ownership {
        let index = started
        started += 1
        await gates[index]?.wait()
        return answers[min(index, answers.count - 1)]
    }
}

/// The rules `ProStore` applies to StoreKit's answers, driven by a scripted read so they run
/// in parallel with everything else. The StoreKit round trips are in `ProStoreStoreKitTests`.
@Suite("ProStore entitlement rules")
@MainActor
struct ProStoreEntitlementTests {

    private func makeStore(
        _ reads: ScriptedOwnership,
        defaults: UserDefaults = makeTestDefaults(),
        confirmDelay: Duration = .zero
    ) -> ProStore {
        ProStore(
            defaults: defaults,
            canMakePayments: { true },
            sync: {},
            readOwnership: { await reads.read() },
            downgradeConfirmDelay: confirmDelay
        )
    }

    private func cached(_ defaults: UserDefaults) -> Bool? {
        defaults.object(forKey: ProStore.Key.cachedIsPro) as? Bool
    }

    private func seeded(isPro: Bool) -> UserDefaults {
        let defaults = makeTestDefaults()
        defaults.set(isPro, forKey: ProStore.Key.cachedIsPro)
        return defaults
    }

    @Test("isPro starts from the cache, before StoreKit has said anything", arguments: [false, true])
    func seedsFromCache(isPro: Bool) {
        let store = makeStore(ScriptedOwnership(.none), defaults: seeded(isPro: isPro))
        #expect(store.isPro == isPro)
        #expect(store.ownership == .none)
    }

    @Test("A purchase StoreKit reports unlocks at once, from a single read, and is cached")
    func upgradeIsImmediate() async {
        let reads = ScriptedOwnership(.purchased)
        let defaults = makeTestDefaults()
        let store = makeStore(reads, defaults: defaults)

        await store.refreshEntitlement()
        #expect(store.isPro)
        #expect(store.ownership == .purchased)
        #expect(reads.started == 1)
        #expect(cached(defaults) == true)
    }

    @Test("Family-shared Pro unlocks like a purchase and says so")
    func familyShared() async {
        let store = makeStore(ScriptedOwnership(.familyShared))
        await store.refreshEntitlement()
        #expect(store.isPro)
        #expect(store.ownership == .familyShared)
    }

    @Test("A free user who stays free is read once and the cache is never written")
    func freeStaysFree() async {
        let reads = ScriptedOwnership(.none)
        let defaults = makeTestDefaults()
        let store = makeStore(reads, defaults: defaults)

        await store.refreshEntitlement()
        #expect(store.isPro == false)
        #expect(reads.started == 1)
        #expect(cached(defaults) == nil)
    }

    @Test("A cached Pro that StoreKit can't find is read a second time before it is dropped")
    func downgradeIsConfirmed() async {
        let reads = ScriptedOwnership(.none, .none)
        let defaults = seeded(isPro: true)
        let store = makeStore(reads, defaults: defaults)

        await store.refreshEntitlement()
        #expect(reads.started == 2)
        #expect(store.isPro == false)
        #expect(cached(defaults) == false)
    }

    @Test("One empty answer between two good ones doesn't downgrade a paying user")
    func transientEmptyReadKeepsPro() async {
        let reads = ScriptedOwnership(.none, .purchased)
        let defaults = seeded(isPro: true)
        let store = makeStore(reads, defaults: defaults)

        await store.refreshEntitlement()
        #expect(reads.started == 2)
        #expect(store.isPro)
        #expect(store.ownership == .purchased)
        #expect(cached(defaults) == true)
    }

    @Test("A confirmed downgrade lasts only until the next read finds Pro")
    func confirmedDowngradeIsNotSticky() async {
        // storekitd answering empty twice running, then recovering.
        let reads = ScriptedOwnership(.none, .none, .purchased)
        let defaults = seeded(isPro: true)
        let store = makeStore(reads, defaults: defaults)

        await store.refreshEntitlement()
        #expect(store.isPro == false)
        #expect(cached(defaults) == false)

        await store.refreshEntitlement()
        #expect(reads.started == 3)
        #expect(store.isPro)
        #expect(store.ownership == .purchased)
        #expect(cached(defaults) == true)
    }

    @Test("A store that never started reads nothing when the app comes forward")
    func foregroundNeedsAStartedStore() async {
        let reads = ScriptedOwnership(.purchased)
        let store = makeStore(reads)

        await store.handleForeground()
        #expect(reads.started == 0, "The unit-test host never starts the app's store")
        #expect(store.isPro == false)
    }

    @Test("The confirming read waits out the delay first")
    func confirmWaits() async {
        let store = makeStore(ScriptedOwnership(.none), defaults: seeded(isPro: true), confirmDelay: .milliseconds(200))
        let started = ContinuousClock.now
        await store.refreshEntitlement()
        #expect(ContinuousClock.now - started >= .milliseconds(200))
        #expect(store.isPro == false)
    }

    @Test("A read that finishes after a newer one is dropped")
    func staleReadIsDropped() async throws {
        let reads = ScriptedOwnership(.none, .purchased)
        let held = Gate()
        reads.gates[0] = held
        let store = makeStore(reads)

        let older = Task { await store.refreshEntitlement() }
        try #require(await waitUntil { reads.started == 1 })
        await store.refreshEntitlement()
        #expect(store.isPro)

        held.open()
        await older.value
        #expect(store.isPro, "The older, empty answer must not undo the newer one")
        #expect(store.ownership == .purchased)
    }

    @Test("With purchases blocked, buying reports it without asking the App Store")
    func purchaseBlocked() async {
        let reads = ScriptedOwnership(.none)
        let store = ProStore(
            defaults: makeTestDefaults(),
            canMakePayments: { false },
            sync: {},
            readOwnership: { await reads.read() }
        )
        #expect(store.canMakePayments == false)
        #expect(await store.purchase() == .notAllowed)
        #expect(store.isPurchasing == false)
        #expect(store.isPro == false)
        #expect(store.offer == .idle)
    }

    @Test("A Restore that is cancelled or fails reads nothing")
    func restoreErrorsSkipTheRead() async {
        let reads = ScriptedOwnership(.purchased)
        let cancelled = ProStore(defaults: makeTestDefaults(), sync: { throw StoreKitError.userCancelled },
                                 readOwnership: { await reads.read() })
        let offline = ProStore(defaults: makeTestDefaults(), sync: { throw URLError(.notConnectedToInternet) },
                               readOwnership: { await reads.read() })

        #expect(await cancelled.restore() == .cancelled)
        #expect(await offline.restore() == .failed)
        #expect(reads.started == 0)
        #expect(cancelled.isPro == false && offline.isPro == false)
    }

    @Test("A Restore that syncs reports what the fresh read found", arguments: [
        (ProStore.Ownership.purchased, ProStore.RestoreOutcome.restored),
        (.familyShared, .restored),
        (.none, .nothingFound),
    ])
    func restoreReadsAfterSync(found: ProStore.Ownership, outcome: ProStore.RestoreOutcome) async {
        let store = makeStore(ScriptedOwnership(found))
        #expect(await store.restore() == outcome)
        #expect(store.isPro == (found != .none))
        #expect(store.ownership == found)
    }

    @Test("A Restore that finds Pro isn't undone by an older empty read still in flight")
    func restoreBeatsOlderRead() async throws {
        let reads = ScriptedOwnership(.none, .purchased)
        let held = Gate()
        reads.gates[0] = held
        let defaults = makeTestDefaults()
        let store = makeStore(reads, defaults: defaults)

        // The listener's refresh, woken by the sync, is still waiting on StoreKit.
        let listener = Task { await store.refreshEntitlement() }
        try #require(await waitUntil { reads.started == 1 })

        #expect(await store.restore() == .restored)
        held.open()
        await listener.value
        #expect(store.isPro)
        #expect(cached(defaults) == true)
    }

    @Test("A Restore that finds nothing still confirms before dropping a cached Pro")
    func restoreNothingFoundConfirms() async {
        let reads = ScriptedOwnership(.none)
        let defaults = seeded(isPro: true)
        let store = makeStore(reads, defaults: defaults)

        #expect(await store.restore() == .nothingFound)
        #expect(reads.started == 3, "Restore's own read, then the refresh's read and its confirmation")
        #expect(store.isPro == false)
        #expect(cached(defaults) == false)
    }

    #if DEBUG
    @Test("The QA override pins isPro, ignores StoreKit and leaves the cache alone", arguments: [false, true])
    func qaOverride(pinned: Bool) async {
        let reads = ScriptedOwnership(pinned ? .none : .purchased)
        let defaults = makeTestDefaults()
        let store = makeStore(reads, defaults: defaults)

        store.overrideForQA(pinned)
        #expect(store.isPro == pinned)
        #expect(store.ownership == (pinned ? .purchased : .none))

        await store.refreshEntitlement()
        #expect(store.isPro == pinned)
        // Restore answers for the pinned state too, so the paywall never contradicts it.
        #expect(await store.restore() == (pinned ? .restored : .nothingFound))
        #expect(store.isPro == pinned)
        #expect(cached(defaults) == nil)
    }
    #endif
}
