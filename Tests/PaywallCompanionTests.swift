//
//  PaywallCompanionTests.swift
//  IntervallyTests
//

import Testing
import SwiftUI
@testable import Intervally

/// The watch's paywall since the iPhone app: the same words as before, plus a pointer to the
/// iPhone only where this watch can't sell Pro.
@Suite("Paywall on the watch, beside the iPhone")
struct PaywallCompanionTests {

    static let hint = "You can also unlock Pro in Intervally on iPhone."

    private func make(
        context: PaywallContext = .settings,
        isPro: Bool = false,
        canMakePayments: Bool = true,
        offer: ProStore.OfferState = PaywallContentTests.shareable,
        isPurchasing: Bool = false,
        lastPurchase: ProStore.PurchaseOutcome? = nil
    ) -> PaywallContent {
        PaywallContent.make(
            context: context, isPro: isPro, ownership: isPro ? .purchased : .none,
            canMakePayments: canMakePayments, offer: offer, isPurchasing: isPurchasing,
            lastPurchase: lastPurchase, lastRestore: nil
        )
    }

    @Test("The watch is the default, so every existing call keeps the watch's words")
    func watchByDefault() {
        #expect(make().platform == .watch)
        #expect(make(canMakePayments: false).statusDetail == "Screen Time or a device profile is blocking purchases on this watch.")
        #expect(make(isPro: true).statusDetail == "Thanks for supporting Intervally.")
    }

    @Test("The App Store couldn't sell Pro here: point to the iPhone", arguments: [
        ProStore.OfferState.unavailable, .failed,
    ])
    func hintWhereItCantSell(offer: ProStore.OfferState) {
        #expect(make(offer: offer).companionLine == Self.hint)
    }

    @Test("A purchase refused as unavailable points there too")
    func hintAfterRefusal() {
        #expect(make(lastPurchase: .unavailable).companionLine == Self.hint)
    }

    @Test("Nowhere else: not beside a price, a spinner, a block or Pro")
    func noHintElsewhere() {
        let others = [
            make(), make(offer: .loading), make(offer: .idle), make(isPurchasing: true),
            make(canMakePayments: false), make(isPro: true), make(lastPurchase: .pending),
        ]
        #expect(others.allSatisfy { $0.companionLine == nil })
    }
}

/// The watch's crown and the iPhone's picker turn over one table per field.
@Suite("Preset fields shared with the iPhone")
@MainActor
struct PresetFieldSharingTests {

    @Test("The setup tiles' fields are the shared ones")
    func sameType() {
        #expect(SetupField.self == PresetField.self)
        #expect(SetupField.allCases == PresetField.allCases)
    }

    @Test("Each crown editor turns over exactly the field's shared values", arguments: PresetField.allCases)
    func crownTableIsShared(field: PresetField) {
        #expect(field.editor(value: .constant(field.range.lowerBound)).values == field.values)
    }
}
