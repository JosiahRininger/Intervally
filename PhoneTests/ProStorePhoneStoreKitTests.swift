//
//  ProStorePhoneStoreKitTests.swift
//  IntervallyPhoneTests
//

import Testing
import Foundation
import StoreKit
import StoreKitTest
@testable import IntervallyPhone

/// `ProStore` against a local StoreKit test environment loaded from `Intervally.storekit`, in
/// the iPhone app, which owns the purchase.
///
/// The watch's twin of this suite can't run since the watch app became a companion (its
/// StoreKit is served under the iPhone app's ID), so this is where the real StoreKit paths
/// are checked, its tests ported here with it: `ProStore` is the same file on both devices. Every test that touches StoreKit lives in this one serialized suite: a
/// process has a single test environment, so two suites running at once would clear each
/// other's transactions. It needs the simulator build's `get-task-allow`
/// (`SimulatorEntitlementsTests`): without it storekitd answers every call with
/// "not installed for development". The time limit turns any StoreKit call that never answers
/// into a failure rather than a run that never ends.
@Suite("ProStore against StoreKit on iPhone", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ProStorePhoneStoreKitTests {

    private let session: SKTestSession
    private let defaults = makeTestDefaults()

    init() async throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "Intervally", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.askToBuyEnabled = false
        session.clearTransactions()
        // A test that failed halfway must not leave an error armed for the next one.
        try await session.setSimulatedError(nil, forAPI: .purchase)
        try await session.setSimulatedError(nil, forAPI: .loadProducts)
    }

    private func makeStore(
        defaults: UserDefaults? = nil,
        sync: @escaping @MainActor () async throws -> Void = {},
        readOwnership: (@MainActor () async -> ProStore.Ownership)? = nil
    ) -> ProStore {
        ProStore(
            defaults: defaults ?? self.defaults,
            sync: sync,
            readOwnership: readOwnership ?? { await ProStore.currentOwnership() },
            downgradeConfirmDelay: .zero
        )
    }

    private var cachedIsPro: Bool? {
        defaults.object(forKey: ProStore.Key.cachedIsPro) as? Bool
    }

    /// Waits for a change made through the session to reach `currentEntitlements`, which
    /// lags a `buyProduct` or a refund by a moment. In the app the change arrives through
    /// `Transaction.updates`, which triggers the refresh.
    private func entitlementSettles(on expected: ProStore.Ownership) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while await ProStore.currentOwnership() != expected {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    private func refundableSettles(on expected: UInt64?) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while await ProStore.latestPurchasedTransactionID() != expected {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    // MARK: - Offer

    @Test("The offer is the $4.99 non-consumable, with Family Sharing, in the iPhone's words")
    func loadsOffer() async throws {
        let store = makeStore()
        await store.loadOffer()
        guard case .loaded(let offer) = store.offer else {
            Issue.record("Expected a loaded offer, got \(store.offer)")
            return
        }
        #expect(offer.displayPrice.contains("4.99"))
        #expect(offer.isFamilyShareable)
        let product = try #require(try await Product.products(for: [ProProduct.id]).first)
        #expect(product.type == .nonConsumable)

        // The family-shared wording the iPhone's paywall shows beside that price.
        let content = PaywallContent.make(
            context: .presets, isPro: store.isPro, ownership: store.ownership,
            canMakePayments: store.canMakePayments, offer: store.offer, isPurchasing: false,
            lastPurchase: nil, lastRestore: nil, platform: .phone
        )
        #expect(content.action.buttonTitle == "Unlock · \(offer.displayPrice)")
        #expect(content.footnote == "One-time purchase · Includes Family Sharing")
        #expect(content.companionLine == "Also unlocks Intervally on your Apple Watch.")
    }

    @Test("A failed load leaves no offer, and Try Again recovers once the App Store answers")
    func loadFailureIsRetryable() async throws {
        let store = makeStore()
        try await session.setSimulatedError(
            .generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts
        )
        await store.loadOffer()
        // `products(for:)` may answer a simulated failure with no products rather than throw;
        // both states are retryable, which is what matters.
        #expect(store.offer == .unavailable || store.offer == .failed)

        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        await store.loadOffer()
        guard case .loaded = store.offer else {
            Issue.record("Expected the retry to load the offer, got \(store.offer)")
            return
        }
    }

    // MARK: - Entitlement

    @Test("A fresh install is free, and the cache is never written for it")
    func freshInstallIsFree() async {
        let store = makeStore()
        await store.refreshEntitlement()
        #expect(store.isPro == false)
        #expect(store.ownership == .none)
        #expect(cachedIsPro == nil)
    }

    @Test("A purchase in the test session unlocks Pro and is cached")
    func purchaseInSessionUnlocks() async throws {
        let store = makeStore()
        let transaction = try await session.buyProduct(identifier: ProProduct.id)
        #expect(ProStore.grantsPro(transaction))
        try #require(await entitlementSettles(on: .purchased))

        await store.refreshEntitlement()
        #expect(store.isPro)
        #expect(store.ownership == .purchased)
        #expect(cachedIsPro == true)
    }

    @Test("A refund takes Pro away and clears the cache")
    func refundRevokes() async throws {
        let store = makeStore()
        let transaction = try await session.buyProduct(identifier: ProProduct.id)
        try #require(await entitlementSettles(on: .purchased))
        await store.refreshEntitlement()
        try #require(store.isPro)

        try session.refundTransaction(identifier: UInt(transaction.id))
        try #require(await entitlementSettles(on: .none), "A refund leaves currentEntitlements")
        await store.refreshEntitlement()
        #expect(store.isPro == false)
        #expect(store.ownership == .none)
        #expect(cachedIsPro == false)
    }

    @Test("A refund reaches a running store through the listener, unprompted", .timeLimit(.minutes(1)))
    func listenerDeliversRefund() async throws {
        let transaction = try await session.buyProduct(identifier: ProProduct.id)
        try #require(await entitlementSettles(on: .purchased))
        let store = makeStore()
        defer { store.stop() }
        store.start()
        try #require(await waitUntil { store.isPro })

        try session.refundTransaction(identifier: UInt(transaction.id))
        #expect(await waitUntil { !store.isPro })
        #expect(cachedIsPro == false)
    }

    @Test("A cached Pro with no transaction behind it is dropped after the confirming read")
    func staleCacheIsDropped() async {
        let seeded = makeTestDefaults()
        seeded.set(true, forKey: ProStore.Key.cachedIsPro)
        let store = makeStore(defaults: seeded)
        #expect(store.isPro, "The cache answers before StoreKit does")

        await store.refreshEntitlement()
        #expect(store.isPro == false)
        #expect(seeded.object(forKey: ProStore.Key.cachedIsPro) as? Bool == false)
    }

    @Test("A refunded transaction grants nothing, even handed straight to the store")
    func refundedTransactionGrantsNothing() async throws {
        let store = makeStore()
        let bought = try await session.buyProduct(identifier: ProProduct.id)
        try session.refundTransaction(identifier: UInt(bought.id))

        // The refund reaches the transaction history on the same delay as the entitlements.
        var refunded: StoreKit.Transaction?
        let deadline = ContinuousClock.now + .seconds(5)
        while refunded == nil, ContinuousClock.now < deadline {
            for await result in StoreKit.Transaction.all {
                if case .verified(let transaction) = result, transaction.id == bought.id,
                   transaction.revocationDate != nil {
                    refunded = transaction
                }
            }
            if refunded == nil { try? await Task.sleep(for: .milliseconds(50)) }
        }
        let transaction = try #require(refunded, "The refunded copy carries a revocation date")
        #expect(ProStore.grantsPro(transaction) == false)

        #expect(await store.handle(.success(.verified(transaction))) == .failed)
        #expect(store.isPro == false)
        #expect(cachedIsPro == nil)
    }

    @Test("An empty read still in flight when a purchase lands can't undo it")
    func staleReadCantUndoPurchase() async throws {
        let transaction = try await session.buyProduct(identifier: ProProduct.id)
        let gate = Gate()
        let reads = Counter()
        let store = makeStore(readOwnership: {
            reads.increment()
            await gate.wait()
            return .none
        })

        let refresh = Task { await store.refreshEntitlement() }
        try #require(await waitUntil { reads.value == 1 })
        #expect(await store.handle(.success(.verified(transaction))) == .purchased)
        gate.open()
        await refresh.value

        #expect(store.isPro)
        #expect(cachedIsPro == true)
    }

    // MARK: - Purchase

    @Test(
        "Buying with dialogs disabled unlocks Pro",
        .disabled("""
            Product.purchase() can't complete in an SKTestSession on the iOS 26.3 simulator, as on \
            the watchOS 26.2 one. Xcode's StoreKit server answers with "cancel-purchase-batch" \
            (AMSErrorDomain 305, "Server canceled the purchase") and it throws StoreKitError.unknown, \
            alone or in the suite, under Xcode 26.2 and 27.1 RC (2026-10-09). Buying through the \
            session, Ask to Buy and every simulated error get through. Covered by the session-purchase \
            and handle(_:) tests; the real sheet is bought by hand through ManualQAStoreKit.
            """),
        .timeLimit(.minutes(1))
    )
    func purchaseUnlocks() async {
        let store = makeStore()
        #expect(await store.purchase() == .purchased)
        #expect(store.isPro)
        #expect(store.ownership == .purchased)
        #expect(store.isPurchasing == false)
        #expect(cachedIsPro == true)
    }

    @Test("handle: a verified purchase unlocks Pro and is cached")
    func handleVerified() async throws {
        let store = makeStore()
        let transaction = try await session.buyProduct(identifier: ProProduct.id)
        #expect(await store.handle(.success(.verified(transaction))) == .purchased)
        #expect(store.isPro)
        #expect(store.ownership == .purchased)
        #expect(cachedIsPro == true)
    }

    @Test("handle: an unverified purchase grants nothing")
    func handleUnverified() async throws {
        let store = makeStore()
        let transaction = try await session.buyProduct(identifier: ProProduct.id)
        #expect(await store.handle(.success(.unverified(transaction, .invalidSignature))) == .unverified)
        #expect(store.isPro == false)
        #expect(cachedIsPro == nil)
    }

    @Test("handle: Ask to Buy and a cancelled sheet change nothing")
    func handlePendingAndCancelled() async {
        let store = makeStore()
        #expect(await store.handle(.pending) == .pending)
        #expect(await store.handle(.userCancelled) == .cancelled)
        #expect(store.isPro == false)
        #expect(cachedIsPro == nil)
    }

    @Test("Purchase errors map to what the paywall can say", .timeLimit(.minutes(1)), arguments: [
        (SKTestFailures.Purchase.generic(.userCancelled), ProStore.PurchaseOutcome.cancelled),
        (.generic(.notAvailableInStorefront), .unavailable),
        (.purchase(.productUnavailable), .unavailable),
        (.purchase(.purchaseNotAllowed), .notAllowed),
        (.generic(.networkError(URLError(.notConnectedToInternet))), .failed),
        (.generic(.unknown), .failed),
    ])
    func purchaseErrorMapping(error: SKTestFailures.Purchase, outcome: ProStore.PurchaseOutcome) async throws {
        let store = makeStore()
        try await session.setSimulatedError(error, forAPI: .purchase)
        #expect(await store.purchase() == outcome)
        #expect(store.isPro == false)
        #expect(store.isPurchasing == false)
        try await session.setSimulatedError(nil, forAPI: .purchase)
    }

    @Test("A second tap while a purchase is in flight starts nothing", .timeLimit(.minutes(1)))
    func doubleTapIsIgnored() async throws {
        let store = makeStore()
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        let first = Task { await store.purchase() }
        for _ in 0..<1_000 where !store.isPurchasing { await Task.yield() }
        try #require(store.isPurchasing)

        #expect(await store.purchase() == .unavailable)
        #expect(await first.value == .cancelled)
        #expect(store.isPurchasing == false)
    }

    @Test("Ask to Buy is pending, says so, and unlocks through the listener once approved", .timeLimit(.minutes(1)))
    func askToBuy() async throws {
        let store = makeStore()
        defer { store.stop() }
        session.askToBuyEnabled = true
        await store.loadOffer()
        let outcome = await store.purchase()
        #expect(outcome == .pending)
        #expect(store.isPro == false)

        let content = PaywallContent.make(
            context: .presets, isPro: store.isPro, ownership: store.ownership,
            canMakePayments: store.canMakePayments, offer: store.offer, isPurchasing: false,
            lastPurchase: outcome, lastRestore: nil, platform: .phone
        )
        #expect(content.note == "Waiting for approval. Pro unlocks as soon as it's approved.")

        store.start()
        let pending = try #require(session.allTransactions().last)
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        #expect(await waitUntil { store.isPro })
    }

    @Test("A purchase made outside purchase(), as on the watch, arrives through the listener", .timeLimit(.minutes(1)))
    func listenerDeliversPurchase() async throws {
        let reads = Counter()
        let store = makeStore(readOwnership: {
            let ownership = await ProStore.currentOwnership()
            reads.increment()
            return ownership
        })
        defer { store.stop() }
        store.start()
        try #require(await waitUntil { reads.value == 1 })
        #expect(store.isPro == false)

        try await session.buyProduct(identifier: ProProduct.id)
        #expect(await waitUntil { store.isPro })
        #expect(reads.value >= 2, "The unlock came from a refresh the listener triggered")
    }

    // MARK: - Lifecycle

    /// Here rather than with the scripted rules: `start()` listens to the real
    /// `Transaction.updates`, which only this serialized suite may do.
    @Test("Coming forward reads again, so a downgrade an outage confirmed doesn't stand", .timeLimit(.minutes(1)))
    func foregroundUndoesConfirmedDowngrade() async throws {
        let seeded = makeTestDefaults()
        seeded.set(true, forKey: ProStore.Key.cachedIsPro)
        // Empty for start()'s read and its confirmation, then StoreKit recovers.
        let answers: [ProStore.Ownership] = [.none, .none, .purchased]
        let reads = Counter()
        let store = makeStore(defaults: seeded, readOwnership: {
            let answer = answers[min(reads.value, answers.count - 1)]
            reads.increment()
            return answer
        })
        defer { store.stop() }

        store.start()
        try #require(await waitUntil { !store.isPro })
        #expect(reads.value == 2)

        await store.handleForeground()
        #expect(reads.value == 3)
        #expect(store.isPro)
        #expect(store.ownership == .purchased)
        #expect(seeded.object(forKey: ProStore.Key.cachedIsPro) as? Bool == true)
    }

    /// A second listener would finish and process every transaction twice, and outlive
    /// `stop()`. Each `start()` that listens also reads the entitlement once, so the reads
    /// count the listeners.
    @Test("start() listens once, however often it is called, and stop() ends it", .timeLimit(.minutes(1)))
    func startIsIdempotent() async throws {
        let reads = Counter()
        let store = makeStore(readOwnership: {
            reads.increment()
            return .none
        })
        #expect(store.isListening == false)
        store.start()
        store.start()
        #expect(store.isListening)
        try #require(await waitUntil { reads.value >= 1 })
        // Long enough for a second start's read, which follows at once, to have landed.
        try await Task.sleep(for: .milliseconds(300))
        #expect(reads.value == 1)

        store.stop()
        #expect(store.isListening == false)
    }

    // MARK: - Restore

    @Test("Restore reports cancelled, failed, nothing found, and restored")
    func restoreOutcomes() async throws {
        #expect(await makeStore(sync: { throw StoreKitError.userCancelled }).restore() == .cancelled)
        #expect(await makeStore(sync: { throw URLError(.notConnectedToInternet) }).restore() == .failed)
        #expect(await makeStore().restore() == .nothingFound)

        try await session.buyProduct(identifier: ProProduct.id)
        try #require(await entitlementSettles(on: .purchased))
        let store = makeStore()
        #expect(await store.restore() == .restored)
        #expect(store.isPro)
    }

    // MARK: - Refunds

    @Test("Request a Refund is for the purchase on this account, and for nothing once refunded")
    func refundableTransaction() async throws {
        // Required, not expected: with a purchase left behind, requestRefund() would put up the
        // real refund sheet and wait for a tap that never comes.
        try #require(await ProStore.latestPurchasedTransactionID() == nil)
        #expect(await makeStore().requestRefund() == .nothingToRefund, "No purchase: no sheet")

        let transaction = try await session.buyProduct(identifier: ProProduct.id)
        try #require(await refundableSettles(on: transaction.id))

        try session.refundTransaction(identifier: UInt(transaction.id))
        #expect(await refundableSettles(on: nil), "A refunded purchase can't be refunded again")
    }

    // MARK: - QA override

    #if DEBUG
    @Test("The QA override wins over StoreKit and never touches the cache")
    func qaOverrideIgnoresStoreKit() async throws {
        try await session.buyProduct(identifier: ProProduct.id)
        let store = makeStore()
        store.overrideForQA(false)

        await store.refreshEntitlement()
        #expect(store.isPro == false)
        #expect(cachedIsPro == nil)
    }
    #endif
}
