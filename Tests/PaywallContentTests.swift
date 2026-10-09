//
//  PaywallContentTests.swift
//  IntervallyTests
//

import Testing
import SwiftUI
@testable import Intervally

/// Every state the paywall can be in, with the exact words it shows.
@Suite("Paywall content")
struct PaywallContentTests {

    static let price = "$4.99"
    static let shareable = ProStore.OfferState.loaded(ProOffer(displayPrice: price, isFamilyShareable: true))
    static let notShareable = ProStore.OfferState.loaded(ProOffer(displayPrice: price, isFamilyShareable: false))

    private func make(
        context: PaywallContext = .settings,
        isPro: Bool = false,
        ownership: ProStore.Ownership = .none,
        canMakePayments: Bool = true,
        offer: ProStore.OfferState = shareable,
        isPurchasing: Bool = false,
        lastPurchase: ProStore.PurchaseOutcome? = nil,
        lastRestore: ProStore.RestoreOutcome? = nil
    ) -> PaywallContent {
        PaywallContent.make(
            context: context, isPro: isPro, ownership: ownership, canMakePayments: canMakePayments,
            offer: offer, isPurchasing: isPurchasing, lastPurchase: lastPurchase, lastRestore: lastRestore
        )
    }

    // MARK: Buying

    @Test("A loaded offer is a capsule with the App Store's own price")
    func buyUsesDisplayPrice() {
        let content = make(offer: .loaded(ProOffer(displayPrice: "4,99 €", isFamilyShareable: true)))
        #expect(content.action == .buy(price: "4,99 €"))
        #expect(content.action.buttonTitle == "Unlock · 4,99 €")
        #expect(content.action.buttonAccessibilityLabel == "Unlock Intervally Pro for 4,99 €")
        #expect(content.note == nil)
        #expect(content.offersRestore)
    }

    @Test("Each door says what the user was reaching for", arguments: [
        (PaywallContext.presets, "Edit your presets any time, or get Pro for more."),
        (.bookends, "Add a warmup and cooldown to any workout."),
        (.tapStrength, "Stronger taps you can feel through a sleeve."),
        (.settings, "Get more from every workout."),
    ])
    func contextLines(context: PaywallContext, line: String) {
        #expect(make(context: context).contextLine == line)
    }

    @Test("The Family Sharing footnote appears only for a shareable product")
    func familyFootnote() {
        #expect(make(offer: Self.shareable).footnote == "One-time purchase · Includes Family Sharing")
        #expect(make(offer: Self.notShareable).footnote == "One-time purchase")
    }

    @Test("The terms stay under the capsule while the sheet is up, and wait for a price")
    func footnoteNeedsAPrice() {
        #expect(make(isPurchasing: true).footnote == "One-time purchase · Includes Family Sharing")
        #expect(make(offer: .loading).footnote == nil)
        #expect(make(offer: .failed).footnote == nil)
        #expect(make(canMakePayments: false).footnote == nil)
        #expect(make(isPro: true, ownership: .purchased).footnote == nil)
    }

    @Test("No price yet is a spinner in the capsule", arguments: [ProStore.OfferState.idle, .loading])
    func loading(offer: ProStore.OfferState) {
        let content = make(offer: offer)
        #expect(content.action == .loading)
        #expect(content.action.buttonTitle == nil)
        #expect(content.action.buttonAccessibilityLabel == "Loading price")
    }

    @Test("While the purchase sheet is up the capsule waits, whatever else is true")
    func purchasing() {
        #expect(make(isPurchasing: true).action == .purchasing)
        #expect(make(isPurchasing: true).action.buttonAccessibilityLabel == "Purchasing")
        #expect(make(isPurchasing: true, lastPurchase: .failed).note == nil)
    }

    @Test("Only a price on screen can be bought: a spinner VoiceOver activates starts nothing")
    func onlyAPriceIsPurchasable() {
        #expect(make().action.isPurchasable)
        #expect(make(offer: .idle).action.isPurchasable == false, "Loading price")
        #expect(make(offer: .loading).action.isPurchasable == false, "Loading price")
        #expect(make(isPurchasing: true).action.isPurchasable == false, "A purchase already in flight")
        let others: [PaywallContent.Action] = [
            .owned(title: "", detail: ""), .blocked, .unavailable, .loadFailed,
        ]
        #expect(others.allSatisfy { !$0.isPurchasable })
    }

    // MARK: Blocked, unavailable, unreachable

    @Test("Blocked purchases replace the capsule, and Restore stays")
    func blocked() {
        let content = make(context: .bookends, canMakePayments: false)
        #expect(content.action == .blocked)
        #expect(content.action.headline == "Purchases are turned off")
        #expect(content.action.detail == "Screen Time or a device profile is blocking purchases on this watch.")
        #expect(content.action.systemImage == "lock.fill")
        #expect(content.action.buttonTitle == nil)
        #expect(content.action.offersRetry == false)
        #expect(content.offersRestore)
    }

    @Test("A purchase refused as not allowed shows the blocked state too")
    func notAllowedPurchase() {
        #expect(make(lastPurchase: .notAllowed).action == .blocked)
    }

    @Test("A restore's answer still shows while purchases are blocked")
    func restoreNoteWhileBlocked() {
        let content = make(canMakePayments: false, lastRestore: .nothingFound)
        #expect(content.action == .blocked)
        #expect(content.note == "No purchase found for this Apple Account.")
    }

    @Test("The App Store answering without the product offers a retry")
    func unavailable() {
        let content = make(offer: .unavailable)
        #expect(content.action == .unavailable)
        #expect(content.action.headline == "Pro isn't available right now")
        #expect(content.action.detail == "Try again later.")
        #expect(content.action.offersRetry)
        #expect(content.offersRestore)
    }

    @Test("A purchase refused as unavailable shows the same, though the price had loaded")
    func unavailablePurchase() {
        let content = make(offer: Self.shareable, lastPurchase: .unavailable)
        #expect(content.action == .unavailable)
        #expect(content.footnote == nil)
        #expect(content.note == nil)
    }

    @Test("An unreachable App Store offers a retry")
    func loadFailed() {
        let content = make(offer: .failed)
        #expect(content.action == .loadFailed)
        #expect(content.action.headline == "Can't reach the App Store")
        #expect(content.action.detail == "Check your connection and try again.")
        #expect(content.action.systemImage == "wifi.slash")
        #expect(content.action.offersRetry)
        #expect(PaywallContent.retryTitle == "Try Again")
    }

    @Test("Only the two states that can clear on their own offer a retry")
    func retryOnlyWhereItHelps() {
        let actions: [PaywallContent.Action] = [
            .buy(price: Self.price), .loading, .purchasing, .owned(title: "", detail: ""), .blocked,
        ]
        #expect(actions.allSatisfy { !$0.offersRetry })
    }

    // MARK: Owned

    @Test("Pro bought outright")
    func owned() {
        let content = make(isPro: true, ownership: .purchased, lastRestore: .restored)
        #expect(content.action == .owned(title: "You have Pro", detail: "Thanks for supporting Intervally."))
        #expect(content.action.headline == "You have Pro")
        #expect(content.action.detail == "Thanks for supporting Intervally.")
        #expect(content.action.systemImage == "checkmark.seal.fill")
        #expect(content.note == nil)
        #expect(content.offersRestore == false)
    }

    @Test("Pro through Family Sharing says so")
    func ownedByFamily() {
        let content = make(isPro: true, ownership: .familyShared)
        #expect(content.action == .owned(title: "Pro is shared by your family", detail: "Unlocked through Family Sharing."))
    }

    @Test("Pro before StoreKit has answered — the cache, or a QA override — reads as owned")
    func ownedFromCache() {
        #expect(make(isPro: true, ownership: .none).action == .owned(title: "You have Pro", detail: "Thanks for supporting Intervally."))
    }

    @Test("Owning Pro outranks every other state, and drops any leftover note")
    func ownedOutranksEverything() {
        let content = make(
            isPro: true, ownership: .purchased, canMakePayments: false, offer: .failed,
            isPurchasing: true, lastPurchase: .pending
        )
        #expect(content.action == .owned(title: "You have Pro", detail: "Thanks for supporting Intervally."))
        #expect(content.note == nil)
    }

    // MARK: Notes

    @Test("Each purchase outcome that needs words gets them", arguments: [
        (ProStore.PurchaseOutcome.pending, "Waiting for approval. Pro unlocks as soon as it's approved."),
        (.failed, "The purchase didn't go through. Try again."),
        (.unverified, "The App Store couldn't verify this purchase. Try Restore Purchases."),
    ])
    func purchaseNotes(outcome: ProStore.PurchaseOutcome, note: String) {
        let content = make(lastPurchase: outcome)
        #expect(content.action == .buy(price: Self.price))
        #expect(content.note == note)
    }

    @Test("A cancelled purchase says nothing")
    func cancelledPurchase() {
        #expect(make(lastPurchase: .cancelled).note == nil)
    }

    @Test("A failed purchase on an unreachable store lets the status speak")
    func failedPurchaseWhileUnreachable() {
        let content = make(offer: .failed, lastPurchase: .failed)
        #expect(content.action == .loadFailed)
        #expect(content.note == nil)
    }

    @Test("Each restore outcome that needs words gets them", arguments: [
        (ProStore.RestoreOutcome.nothingFound, "No purchase found for this Apple Account." as String?),
        (.failed, "Couldn't reach the App Store. Try again."),
        (.cancelled, nil),
        (.restored, nil),
    ])
    func restoreNotes(outcome: ProStore.RestoreOutcome, note: String?) {
        #expect(make(lastRestore: outcome).note == note)
    }

    // MARK: Extras and fixed copy

    @Test("Feel Strongest is offered only from the Tap Strength door, and only before Pro")
    func feelStrongest() {
        #expect(make(context: .tapStrength).offersPreview)
        #expect(make(context: .tapStrength, isPro: true, ownership: .purchased).offersPreview == false)
        for context in [PaywallContext.presets, .bookends, .settings] {
            #expect(make(context: context).offersPreview == false)
        }
        #expect(PaywallContent.previewTitle == "Feel Strongest")
    }

    @Test("Fixed copy and the four features, in order")
    func fixedCopy() {
        #expect(PaywallContent.title == "Intervally Pro")
        #expect(PaywallContent.restoreTitle == "Restore Purchases")
        #expect(PaywallContent.features.map(\.title) == [
            "Unlimited presets", "Warmup & cooldown", "Stronger taps", "Support an indie dev",
        ])
        #expect(PaywallContent.features.map(\.systemImage) == [
            "square.stack.3d.up.fill", "sunrise.fill", "hand.tap.fill", "heart.fill",
        ])
    }

    @Test("Guideline 4.10: the copy never sells haptics themselves, only the repeated pattern")
    func neverSellsHaptics() {
        let contexts: [PaywallContext] = [.presets, .bookends, .tapStrength, .settings]
        let copy = contexts.flatMap { [PaywallContent.contextLine(for: $0), PaywallContent.contextLine(for: $0, platform: .phone)] }
            + PaywallContent.features.map(\.title)
            + [TapStrengthView.footer, TapStrengthRow(stored: .standard, isPro: false).footer]
        #expect(copy.allSatisfy { !$0.localizedCaseInsensitiveContains("haptic") })
    }
}

/// The price must show without scrolling on the smallest watch. Rendered offscreen at a
/// 40mm watch's width and default text size, against its height less the navigation bar.
@Suite("Paywall layout")
@MainActor
struct PaywallLayoutTests {

    /// 40mm: 162×197pt. The bar with the back button and the clock takes about 31pt there;
    /// 40 leaves margin.
    static let width40: CGFloat = 162
    static let fold40: CGFloat = 197 - 40
    /// Large is the small watches' default text size. xLarge, the 46mm default (read from
    /// this simulator), is checked too, in case a 40mm is set one step up.
    static let textSizes: [DynamicTypeSize] = [.large, .xLarge]

    private func height(_ content: PaywallContent, width: CGFloat, textSize: DynamicTypeSize) throws -> CGFloat {
        let header = PaywallHeader(content: content)
            .scenePadding(.horizontal)
            .environment(\.dynamicTypeSize, textSize)
        let renderer = ImageRenderer(content: header)
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        let image = try #require(renderer.cgImage)
        return CGFloat(image.height) / renderer.scale
    }

    private func content(_ context: PaywallContext, offer: ProStore.OfferState, isPurchasing: Bool = false) -> PaywallContent {
        PaywallContent.make(
            context: context, isPro: false, ownership: .none, canMakePayments: true,
            offer: offer, isPurchasing: isPurchasing, lastPurchase: nil, lastRestore: nil
        )
    }

    @Test("The price is above the fold on 40mm from every door, however long the price", arguments: [
        PaywallContext.presets, .bookends, .tapStrength, .settings,
    ])
    func priceAboveTheFold(context: PaywallContext) throws {
        for price in ["$4.99", "1 099,00 kr", "₹449.00"] {
            let offer = ProStore.OfferState.loaded(ProOffer(displayPrice: price, isFamilyShareable: true))
            for size in Self.textSizes {
                let height = try height(content(context, offer: offer), width: Self.width40, textSize: size)
                #expect(height <= Self.fold40, "\(context) at \(price), \(size): \(height)pt")
            }
        }
    }

    @Test("Loading and purchasing hold the same place as the price", arguments: [
        PaywallContext.presets, .bookends, .tapStrength, .settings,
    ])
    func spinnerKeepsThePlace(context: PaywallContext) throws {
        let price = try height(content(context, offer: PaywallContentTests.shareable), width: Self.width40, textSize: .large)
        let loading = try height(content(context, offer: .loading), width: Self.width40, textSize: .large)
        let purchasing = try height(content(context, offer: PaywallContentTests.shareable, isPurchasing: true), width: Self.width40, textSize: .large)
        #expect(loading == price)
        #expect(purchasing == price)
    }
}
