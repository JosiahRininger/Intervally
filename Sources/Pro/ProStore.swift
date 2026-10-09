//
//  ProStore.swift
//  Intervally
//

import Foundation
import Observation
import StoreKit

/// What the paywall needs to show the price, without handing a StoreKit `Product` to a view.
struct ProOffer: Equatable, Sendable {
    /// Localized by the App Store for the user's storefront, e.g. "$4.99".
    let displayPrice: String
    let isFamilyShareable: Bool
}

/// The app's only contact with StoreKit: Intervally Pro, a single non-consumable.
///
/// SwiftUI files never import StoreKit — where both are imported, `Transaction` is
/// ambiguous — so views read this from the environment and call its async methods.
///
/// `isPro` starts from a cached flag, because a workout recovered in the background picks
/// its tap strength before any StoreKit query can answer. After that StoreKit always wins,
/// with one exception: a cached `true` that StoreKit reports as `false` is read a second
/// time first, so a single transient empty answer (storekitd being restarted, say) can't
/// downgrade a paying user in the middle of a workout. A real refund still lands seconds
/// later.
@MainActor
@Observable
final class ProStore: ProGating {

    enum Key {
        static let cachedIsPro = "pro.isPro.v1"
    }

    /// How the user holds Pro, which only changes the paywall's wording.
    enum Ownership: Equatable, Sendable {
        case none, purchased, familyShared
    }

    enum OfferState: Equatable, Sendable {
        case idle, loading, loaded(ProOffer)
        /// The App Store answered without the product: not on sale in this storefront, or
        /// (per App Store Connect) an Apple Watch build reviewed without its purchase.
        case unavailable
        /// The App Store could not be reached. Retryable.
        case failed
    }

    enum PurchaseOutcome: Equatable, Sendable {
        case purchased
        /// Ask to Buy: the grant arrives later through `Transaction.updates`.
        case pending
        case cancelled
        /// Screen Time or a device profile blocks purchases.
        case notAllowed
        /// The App Store's signature didn't check out. Nothing is granted.
        case unverified
        case unavailable
        /// Anything retryable: the network, storekitd, an unknown StoreKit error.
        case failed
    }

    enum RestoreOutcome: Equatable, Sendable {
        case restored, nothingFound, cancelled, failed
    }

    /// Whether Pro features are unlocked right now.
    private(set) var isPro: Bool
    /// How Pro is held, as StoreKit last reported it: `.none` until it has answered once,
    /// even when the cache already says Pro.
    private(set) var ownership: Ownership = .none
    private(set) var offer: OfferState = .idle
    /// True from the tap until StoreKit answers, so a second tap can't start a second
    /// purchase.
    private(set) var isPurchasing = false

    /// False when Screen Time or a profile blocks purchases. The paywall then explains the
    /// block instead of offering a button that can only fail.
    var canMakePayments: Bool { canMakePaymentsProvider() }

    /// Whether `start()` is listening for transactions. The unit-test host never starts it.
    var isListening: Bool { updatesTask != nil }

    @ObservationIgnored private var product: Product?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    /// Bumped by every entitlement read and every granted purchase. A read that finishes
    /// after a newer one began is dropped, so a slow empty answer can't undo a purchase.
    @ObservationIgnored private var generation = 0
    #if DEBUG
    @ObservationIgnored private var qaOverride: Bool?
    #endif

    private let defaults: UserDefaults
    private let canMakePaymentsProvider: @MainActor () -> Bool
    private let sync: @MainActor () async throws -> Void
    private let readOwnership: @MainActor () async -> Ownership
    private let downgradeConfirmDelay: Duration

    /// - Parameter readOwnership: the entitlement read. Injected so tests can hold a read
    ///   open and prove the stale-read and downgrade-confirm rules without StoreKit.
    init(
        defaults: UserDefaults = SharedDefaults.suite,
        canMakePayments: @escaping @MainActor () -> Bool = { AppStore.canMakePayments },
        sync: @escaping @MainActor () async throws -> Void = { try await AppStore.sync() },
        readOwnership: @escaping @MainActor () async -> Ownership = { await ProStore.currentOwnership() },
        downgradeConfirmDelay: Duration = .seconds(3)
    ) {
        self.defaults = defaults
        self.canMakePaymentsProvider = canMakePayments
        self.sync = sync
        self.readOwnership = readOwnership
        self.downgradeConfirmDelay = downgradeConfirmDelay
        self.isPro = defaults.bool(forKey: Key.cachedIsPro)
    }

    // MARK: - Lifecycle

    /// Listens for transactions that don't come back from `purchase()` — Ask to Buy
    /// approvals, refunds, family-sharing changes, a purchase on another device — and then
    /// reads the entitlement. Apple asks for the listener at launch: a transaction that
    /// finished while the app was away is delivered once, right then. Calling it again does
    /// nothing.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                await self.process(result)
            }
        }
        Task { await refreshEntitlement() }
    }

    /// Stops listening. Only tests need this; the app listens for its whole life.
    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    /// Reads the entitlement again as the app comes forward. A downgrade that two empty
    /// answers confirmed (storekitd down for longer than the confirming delay, say) would
    /// otherwise stand until a relaunch, a transaction update or a Restore, and watchOS can
    /// keep a suspended app for days. The read is local, and the generation and downgrade
    /// rules still apply. A store that never started, as in the unit-test host, reads nothing.
    func handleForeground() async {
        guard isListening else { return }
        await refreshEntitlement()
    }

    // MARK: - Offer

    /// Loads the price. Does nothing once loaded; after `.failed` or `.unavailable` it tries
    /// again, which is what the paywall's Try Again does.
    func loadOffer() async {
        if case .loaded = offer { return }
        offer = .loading
        let result: OfferState
        do {
            if let found = try await Product.products(for: [ProProduct.id]).first {
                product = found
                result = .loaded(ProOffer(displayPrice: found.displayPrice, isFamilyShareable: found.isFamilyShareable))
            } else {
                // `products(for:)` drops unknown IDs silently rather than throwing.
                result = .unavailable
            }
        } catch {
            result = .failed
        }
        // An older load, from a paywall dismissed mid-flight, must not replace an offer a
        // newer one already found.
        if case .loaded = offer { return }
        offer = result
    }

    // MARK: - Entitlement

    /// Asks StoreKit whether Pro is owned, and updates `isPro` and the cache to match.
    func refreshEntitlement() async {
        generation += 1
        let mine = generation
        var owned = await readOwnership()
        guard mine == generation else { return }
        if owned == .none, isPro {
            // Confirm a downgrade before applying it. A cancelled sleep just reads sooner.
            try? await Task.sleep(for: downgradeConfirmDelay)
            guard mine == generation else { return }
            owned = await readOwnership()
            guard mine == generation else { return }
        }
        apply(owned)
    }

    /// StoreKit's answer: how Pro is held, judged from verified current entitlements only.
    /// Bought outright beats family-shared when the user has both.
    nonisolated static func currentOwnership() async -> Ownership {
        var found = Ownership.none
        for await result in StoreKit.Transaction.currentEntitlements(for: ProProduct.id) {
            guard case .verified(let transaction) = result, Self.grantsPro(transaction) else { continue }
            let held = Self.ownership(of: transaction)
            if held == .purchased { return .purchased }
            found = held
        }
        return found
    }

    /// Whether a transaction unlocks Pro. Family-shared copies count; refunded, revoked
    /// and upgraded ones don't.
    nonisolated static func grantsPro(_ transaction: StoreKit.Transaction) -> Bool {
        transaction.productID == ProProduct.id
            && transaction.revocationDate == nil
            && !transaction.isUpgraded
    }

    /// The purchase a refund request would be for: the latest verified transaction for Pro,
    /// while it still grants Pro and was bought on this Apple Account. Nil for a family-shared
    /// copy, which only the family member who bought it can ask a refund for.
    nonisolated static func latestPurchasedTransactionID() async -> UInt64? {
        guard case .verified(let transaction)? = await StoreKit.Transaction.latest(for: ProProduct.id),
              grantsPro(transaction),
              ownership(of: transaction) == .purchased else { return nil }
        return transaction.id
    }

    nonisolated private static func ownership(of transaction: StoreKit.Transaction) -> Ownership {
        transaction.ownershipType == .familyShared ? .familyShared : .purchased
    }

    // MARK: - Purchase and restore

    /// Buys Pro through the system confirmation sheet.
    func purchase() async -> PurchaseOutcome {
        // Claimed before the first await, so a double tap can't start two purchases.
        guard !isPurchasing else { return .unavailable }
        isPurchasing = true
        defer { isPurchasing = false }

        guard canMakePayments else { return .notAllowed }
        if product == nil { await loadOffer() }
        guard let product else { return offer == .failed ? .failed : .unavailable }
        do {
            return await handle(try await product.purchase())
        } catch Product.PurchaseError.purchaseNotAllowed {
            return .notAllowed
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch StoreKitError.notAvailableInStorefront, Product.PurchaseError.productUnavailable {
            return .unavailable
        } catch {
            return .failed
        }
    }

    /// Applies what the purchase sheet returned. Separate from `purchase()` so every
    /// branch can be tested with a transaction from a test session.
    func handle(_ result: Product.PurchaseResult) async -> PurchaseOutcome {
        switch result {
        case .success(.verified(let transaction)):
            let grants = Self.grantsPro(transaction)
            if grants {
                generation += 1
                apply(Self.ownership(of: transaction))
            }
            // Finished either way: it is verified, and an unfinished transaction comes back
            // at every launch.
            await transaction.finish()
            return grants ? .purchased : .failed
        case .success(.unverified):
            // Grant nothing, and leave it unfinished so StoreKit can deliver it again.
            return .unverified
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .failed
        }
    }

    /// Restore Purchases. `AppStore.sync()` can ask for the Apple Account password, so it
    /// only ever runs from that explicit tap; a reinstall gets its transactions without it.
    func restore() async -> RestoreOutcome {
        do {
            try await sync()
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            return .failed
        }
        // Read for ourselves rather than trust whichever refresh lands first: the sync can
        // also wake the updates listener, and its newer refresh would drop ours mid-read.
        let owned = await readOwnership()
        if owned != .none {
            generation += 1
            apply(owned)
        } else {
            // Nothing found still goes through the confirming read before a cached Pro drops.
            await refreshEntitlement()
        }
        return isPro ? .restored : .nothingFound
    }

    // MARK: - Applying

    /// Grants, refunds and family revocations all arrive here.
    private func process(_ result: VerificationResult<StoreKit.Transaction>) async {
        if case .verified(let transaction) = result {
            await transaction.finish()
        }
        await refreshEntitlement()
    }

    /// The cache is written only on a change, so steady-state launches don't touch it.
    private func apply(_ ownership: Ownership) {
        #if DEBUG
        if qaOverride != nil { return }
        #endif
        self.ownership = ownership
        let entitled = ownership != .none
        guard entitled != isPro else { return }
        isPro = entitled
        defaults.set(entitled, forKey: Key.cachedIsPro)
    }

    #if DEBUG
    /// Pins the entitlement for QA and screenshots (`-qaPro pro|free`). StoreKit's answers
    /// are ignored from then on and the cache is left alone, so the override never outlives
    /// the launch. Debug builds only: in Release it would be an unlock path that bypasses
    /// the purchase.
    func overrideForQA(_ value: Bool) {
        qaOverride = value
        isPro = value
        ownership = value ? .purchased : .none
    }
    #endif
}
