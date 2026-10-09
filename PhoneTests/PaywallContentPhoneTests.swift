//
//  PaywallContentPhoneTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// The iPhone's paywall words: the shared content with `platform: .phone`.
@Suite("Paywall content on iPhone")
struct PaywallContentPhoneTests {

    static let shareable = ProStore.OfferState.loaded(ProOffer(displayPrice: "$4.99", isFamilyShareable: true))

    private func make(
        context: PaywallContext = .presets,
        isPro: Bool = false,
        ownership: ProStore.Ownership = .none,
        canMakePayments: Bool = true,
        offer: ProStore.OfferState = shareable,
        isPurchasing: Bool = false,
        lastPurchase: ProStore.PurchaseOutcome? = nil,
        lastRestore: ProStore.RestoreOutcome? = nil,
        platform: PaywallPlatform = .phone
    ) -> PaywallContent {
        PaywallContent.make(
            context: context, isPro: isPro, ownership: ownership, canMakePayments: canMakePayments,
            offer: offer, isPurchasing: isPurchasing, lastPurchase: lastPurchase, lastRestore: lastRestore,
            platform: platform
        )
    }

    @Test("Beside the price: the terms, and that the purchase unlocks the watch too")
    func buy() {
        let content = make()
        #expect(content.platform == .phone)
        #expect(content.action.buttonTitle == "Unlock · $4.99")
        #expect(content.footnote == "One-time purchase · Includes Family Sharing")
        #expect(content.companionLine == "Also unlocks Intervally on your Apple Watch.")
        #expect(content.offersRestore)
    }

    @Test("The watch line waits with the price, and goes where nothing can be bought", arguments: [
        (ProStore.OfferState.loading, false, true),
        (PaywallContentPhoneTests.shareable, true, true),
        (.unavailable, false, false),
        (.failed, false, false),
    ])
    func companionLineFollowsThePrice(offer: ProStore.OfferState, isPurchasing: Bool, shows: Bool) {
        #expect((make(offer: offer, isPurchasing: isPurchasing).companionLine != nil) == shows)
        #expect(make(canMakePayments: false).companionLine == nil, "Blocked")
        #expect(make(isPro: true, ownership: .purchased).companionLine == nil, "Owned")
    }

    @Test("Owned: what to do next, here and on the watch")
    func owned() {
        #expect(make(isPro: true, ownership: .purchased).action == .owned(
            title: "You have Pro",
            detail: "Unlocked. Add more workouts and warmups here; choose Tap Strength on your watch."
        ))
        #expect(make(isPro: true, ownership: .familyShared).action == .owned(
            title: "Pro is shared by your family",
            detail: "Unlocked through Family Sharing. Add more workouts and warmups here; choose Tap Strength on your watch."
        ))
        // The cache or a QA override, before StoreKit answers: bought outright.
        #expect(make(isPro: true, ownership: .none) == make(isPro: true, ownership: .purchased))
    }

    /// On iPad, or an iPhone with no watch paired, there is no watch to choose Tap Strength on.
    @Test("Owned with no watch: only what is left to do here")
    func ownedWithoutWatch() {
        func owned(_ ownership: ProStore.Ownership) -> PaywallContent.Action {
            PaywallContent.make(
                context: .settings, isPro: true, ownership: ownership, canMakePayments: true,
                offer: Self.shareable, isPurchasing: false, lastPurchase: nil, lastRestore: nil,
                platform: .phone, hasWatch: false
            ).action
        }
        #expect(owned(.purchased) == .owned(title: "You have Pro", detail: "Unlocked. Add more workouts and warmups."))
        #expect(owned(.familyShared) == .owned(
            title: "Pro is shared by your family",
            detail: "Unlocked through Family Sharing. Add more workouts and warmups."
        ))
        // The watch's own paywall never asks.
        #expect(PaywallContent.make(
            context: .settings, isPro: true, ownership: .purchased, canMakePayments: true, offer: .idle,
            isPurchasing: false, lastPurchase: nil, lastRestore: nil, platform: .watch, hasWatch: false
        ).action == .owned(title: "You have Pro", detail: "Thanks for supporting Intervally."))
    }

    @Test("Blocked purchases name this iPhone, not a watch")
    func blocked() {
        let content = make(canMakePayments: false)
        #expect(content.action == .blocked)
        #expect(content.statusDetail == "Screen Time or a device profile is blocking purchases on this iPhone.")
        #expect(content.action.detail(on: .phone) == content.statusDetail)
    }

    @Test("Every other state reads as on the watch", arguments: [
        ProStore.OfferState.unavailable, .failed,
    ])
    func sharedStates(offer: ProStore.OfferState) {
        let phone = make(offer: offer)
        let watch = make(offer: offer, platform: .watch)
        #expect(phone.action == watch.action)
        #expect(phone.statusDetail == watch.statusDetail)
        #expect(phone.contextLine == watch.contextLine)
        #expect(phone.note == watch.note)
    }

    @Test("Feel Strongest is the watch's alone: a phone can't play a wrist tap")
    func noPreview() {
        #expect(make(context: .tapStrength).offersPreview == false)
        #expect(make(context: .tapStrength, platform: .watch).offersPreview)
    }

    @Test("The doors the iPhone opens say what was reached for", arguments: [
        (PaywallContext.presets, "Free includes 3 presets. Pro has no limit."),
        (.bookends, "Add a warmup and cooldown to any workout."),
        (.settings, "Get more from every workout."),
    ])
    func contextLines(context: PaywallContext, line: String) {
        #expect(make(context: context).contextLine == line)
    }

    @Test("Purchase and restore answers are the shared ones")
    func notes() {
        #expect(make(lastPurchase: .pending).note == "Waiting for approval. Pro unlocks as soon as it's approved.")
        #expect(make(lastRestore: .nothingFound).note == "No purchase found for this Apple Account.")
    }

    @Test("The watch points to the iPhone only where it can't sell Pro itself")
    func watchHintOnlyInFailures() {
        let hint = "You can also unlock Pro in Intervally on iPhone."
        #expect(make(offer: .unavailable, platform: .watch).companionLine == hint)
        #expect(make(offer: .failed, platform: .watch).companionLine == hint)
        #expect(make(lastPurchase: .unavailable, platform: .watch).companionLine == hint)
        for content in [
            make(platform: .watch),
            make(offer: .loading, platform: .watch),
            make(isPurchasing: true, platform: .watch),
            make(canMakePayments: false, platform: .watch),
            make(isPro: true, ownership: .purchased, platform: .watch),
        ] {
            #expect(content.companionLine == nil, "\(content.action)")
        }
    }

    @Test("Guideline 4.10: the iPhone's copy never sells haptics either")
    func neverSellsHaptics() {
        let owned = make(isPro: true, ownership: .purchased)
        let copy = [make().companionLine, owned.statusDetail, make(canMakePayments: false).statusDetail]
            .compactMap { $0 } + PaywallContent.features.map(\.title)
        #expect(copy.allSatisfy { !$0.localizedCaseInsensitiveContains("haptic") })
    }
}
