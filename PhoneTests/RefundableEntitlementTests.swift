//
//  RefundableEntitlementTests.swift
//  IntervallyPhoneTests
//

import Testing
@testable import IntervallyPhone

/// How Pro is held, and which purchase Request a Refund is for, from one read of the current
/// entitlements. Settings shows the button when the first says "purchased"; the second must
/// then find that purchase. A StoreKit test session can't make a family-shared copy, so these
/// rules are checked on plain values.
@Suite("Refundable entitlement")
struct RefundableEntitlementTests {
    typealias Entitlement = ProStore.Entitlement

    static let bought = Entitlement(transactionID: 1, grantsPro: true, ownership: .purchased)
    static let shared = Entitlement(transactionID: 2, grantsPro: true, ownership: .familyShared)
    static let revokedShare = Entitlement(transactionID: 3, grantsPro: false, ownership: .familyShared)
    static let refunded = Entitlement(transactionID: 4, grantsPro: false, ownership: .purchased)

    /// The user bought Pro, and a family organizer's later purchase is shared with them too,
    /// in either order, or that share was since revoked.
    @Test("A purchase of the user's own is refundable beside a family-shared copy", arguments: [
        [bought, shared], [shared, bought], [revokedShare, bought], [bought, revokedShare],
    ])
    func ownPurchaseBesideShare(entitlements: [Entitlement]) {
        #expect(ProStore.ownership(among: entitlements) == .purchased)
        #expect(ProStore.refundableTransactionID(among: entitlements) == 1)
    }

    @Test("A family-shared copy alone is Pro, with nothing this account can refund")
    func shareAlone() {
        #expect(ProStore.ownership(among: [Self.shared]) == .familyShared)
        #expect(ProStore.refundableTransactionID(among: [Self.shared]) == nil)
    }

    @Test("Nothing that grants Pro is nothing to refund", arguments: [
        [Entitlement](), [refunded], [revokedShare], [refunded, revokedShare],
    ])
    func nothingGranting(entitlements: [Entitlement]) {
        #expect(ProStore.ownership(among: entitlements) == .none)
        #expect(ProStore.refundableTransactionID(among: entitlements) == nil)
    }

    @Test("The refund button and the refund lookup always agree", arguments: [
        [Entitlement](), [bought], [shared], [refunded], [revokedShare],
        [bought, shared], [shared, bought], [shared, refunded], [refunded, shared, revokedShare],
    ])
    func buttonAndLookupAgree(entitlements: [Entitlement]) {
        let showsRefund = ProStore.ownership(among: entitlements) == .purchased
        #expect((ProStore.refundableTransactionID(among: entitlements) != nil) == showsRefund)
    }
}
