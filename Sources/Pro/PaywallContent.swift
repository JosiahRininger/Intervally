//
//  PaywallContent.swift
//  Intervally
//

import Foundation

/// The door the paywall was opened from. Only the line under the title changes, so each
/// door answers what the user was reaching for.
enum PaywallContext: Hashable, Sendable {
    case presets, bookends, tapStrength, settings
    /// Pastel, chosen by a free user in Theme.
    case themes
    /// The voice coach, turned on by a free user in the iPhone's Sounds settings.
    case voice
}

/// Which device's paywall. The copy differs only where the devices do: what the other one
/// gets, and what a purchase leaves to do.
enum PaywallPlatform: Hashable, Sendable {
    case watch, phone
}

/// Everything the paywall says, worked out from the store's state apart from the view, so
/// every state is testable and no view needs StoreKit. Shared by the watch and the iPhone.
struct PaywallContent: Equatable, Sendable {

    /// What sits under the context line: the price on a capsule, or why there isn't one.
    enum Action: Equatable, Sendable {
        case buy(price: String)
        case loading
        case purchasing
        case owned(title: String, detail: String)
        /// Screen Time or a device profile blocks purchases.
        case blocked
        /// The App Store answered without the product.
        case unavailable
        /// The App Store could not be reached.
        case loadFailed
    }

    struct Feature: Equatable, Sendable, Identifiable {
        let systemImage: String
        let title: String
        var id: String { title }
    }

    let platform: PaywallPlatform
    /// What Pro adds, as this device sells it.
    let features: [Feature]
    let contextLine: String
    let action: Action
    /// The terms under the price: shown only once there is a price.
    let footnote: String?
    /// The answer to the user's last tap, when it needs one.
    let note: String?
    /// Restore stays even when purchases are blocked: restoring buys nothing.
    let offersRestore: Bool
    /// "Feel Strongest", for someone deciding whether stronger taps are worth it. Watch only:
    /// a phone can't play a wrist tap.
    let offersPreview: Bool
    /// The other device. On iPhone, beside a price: that the purchase unlocks the watch too.
    /// On the watch, only when the App Store couldn't sell Pro there: that the iPhone app can.
    let companionLine: String?

    static let title = "Intervally Pro"
    static let restoreTitle = "Restore Purchases"
    static let previewTitle = "Feel Strongest"
    static let retryTitle = "Try Again"

    /// Base taps stay free, so the copy only ever describes a repeated pattern (Guideline
    /// 4.10): never "unlock haptics".
    static let features: [Feature] = [
        Feature(systemImage: "square.stack.3d.up.fill", title: "Unlimited presets"),
        Feature(systemImage: "sunrise.fill", title: "Warmup & cooldown"),
        Feature(systemImage: "hand.tap.fill", title: "Stronger taps"),
        Feature(systemImage: "paintpalette.fill", title: "Pastel theme"),
        Feature(systemImage: "heart.fill", title: "Support an indie dev"),
    ]

    /// The iPhone sells what its runs get, the voice coach, and the watch's stronger taps
    /// only to someone with a watch to feel them on. The beeps stay free, so the copy only
    /// ever describes the coach (Guideline 4.10): never "unlock sounds".
    static func features(on platform: PaywallPlatform, hasWatch: Bool) -> [Feature] {
        switch platform {
        case .watch:
            return features
        case .phone:
            var list = [
                Feature(systemImage: "square.stack.3d.up.fill", title: "Unlimited presets"),
                Feature(systemImage: "sunrise.fill", title: "Warmup & cooldown"),
                Feature(systemImage: "waveform", title: "Voice coach"),
            ]
            if hasWatch {
                list.append(Feature(systemImage: "hand.tap.fill", title: "Stronger watch taps"))
            }
            list += [
                Feature(systemImage: "paintpalette.fill", title: "Pastel theme"),
                Feature(systemImage: "heart.fill", title: "Support an indie dev"),
            ]
            return list
        }
    }

    /// - Parameters:
    ///   - isPro: Pro with `ownership == .none` — from the cache before StoreKit answers,
    ///     or a QA override — still reads as owned.
    ///   - lastPurchase: The view keeps at most one of this and `lastRestore`: the outcome
    ///     of whichever was tapped last.
    ///   - platform: The watch unless said otherwise, so the watch's wording stays exactly
    ///     what it was before the iPhone app existed.
    ///   - hasWatch: iPhone only: whether it has a watch to choose Tap Strength on. Without
    ///     one, as on iPad, the owned state sends nobody to a watch.
    static func make(
        context: PaywallContext,
        isPro: Bool,
        ownership: ProStore.Ownership,
        canMakePayments: Bool,
        offer: ProStore.OfferState,
        isPurchasing: Bool,
        lastPurchase: ProStore.PurchaseOutcome?,
        lastRestore: ProStore.RestoreOutcome?,
        platform: PaywallPlatform = .watch,
        hasWatch: Bool = true
    ) -> PaywallContent {
        let action = action(
            isPro: isPro, ownership: ownership, canMakePayments: canMakePayments, offer: offer,
            isPurchasing: isPurchasing, lastPurchase: lastPurchase, platform: platform, hasWatch: hasWatch
        )
        return PaywallContent(
            platform: platform,
            features: features(on: platform, hasWatch: hasWatch),
            contextLine: contextLine(for: context, platform: platform),
            action: action,
            footnote: footnote(for: action, offer: offer),
            note: isPro ? nil : note(for: action, lastPurchase: lastPurchase, lastRestore: lastRestore),
            offersRestore: !isPro,
            offersPreview: platform == .watch && context == .tapStrength && !isPro,
            companionLine: companionLine(for: action, platform: platform, hasWatch: hasWatch)
        )
    }

    static func contextLine(for context: PaywallContext, platform: PaywallPlatform = .watch) -> String {
        switch context {
        // Opened by + or New Preset at the limit, so it says what a free user can still do.
        // The watch's is shorter: on a 40mm the longer one pushed the price below the fold.
        case .presets: platform == .phone
            // One sentence a line: run together, a 6.9-inch iPhone broke the line after "For".
            ? "Free includes \(ProProduct.freePresetLimit) presets you can edit any time.\nFor more, get Pro."
            : "Edit your presets any time, or get Pro for more."
        case .bookends: "Add a warmup and cooldown to any workout."
        case .tapStrength: "Stronger taps you can feel through a sleeve."
        case .settings: "Get more from every workout."
        // Shorter than the bookends' line, so the 40mm price stays above the fold.
        case .themes: "Make Intervally yours with Pastel."
        case .voice: "Hear every interval called out, even over your music."
        }
    }

    /// The status line under the headline, in this device's words.
    var statusDetail: String? { action.detail(on: platform) }

    private static func action(
        isPro: Bool,
        ownership: ProStore.Ownership,
        canMakePayments: Bool,
        offer: ProStore.OfferState,
        isPurchasing: Bool,
        lastPurchase: ProStore.PurchaseOutcome?,
        platform: PaywallPlatform,
        hasWatch: Bool
    ) -> Action {
        if isPro { return owned(ownership, platform: platform, hasWatch: hasWatch) }
        // Ahead of the block: the system sheet is already up, so the capsule waits with it.
        if isPurchasing { return .purchasing }
        if !canMakePayments || lastPurchase == .notAllowed { return .blocked }
        // The product loaded, but the App Store then refused to sell it.
        if lastPurchase == .unavailable { return .unavailable }
        switch offer {
        case .idle, .loading: return .loading
        case .loaded(let offer): return .buy(price: offer.displayPrice)
        case .unavailable: return .unavailable
        case .failed: return .loadFailed
        }
    }

    /// On iPhone the detail says what to do next, on both devices: Tap Strength is chosen
    /// on the watch, where the taps are felt. With no watch, only what is left here.
    private static func owned(_ ownership: ProStore.Ownership, platform: PaywallPlatform, hasWatch: Bool) -> Action {
        let shared = ownership == .familyShared
        let title = shared ? "Pro is shared by your family" : "You have Pro"
        switch platform {
        case .watch:
            return .owned(title: title, detail: shared ? "Unlocked through Family Sharing." : "Thanks for supporting Intervally.")
        case .phone:
            let next = hasWatch
                ? "Add more workouts and warmups, hear the voice coach on every run, and choose Tap Strength on your watch."
                : "Add more workouts and warmups, and hear the voice coach on every run."
            return .owned(title: title, detail: shared ? "Unlocked through Family Sharing. \(next)" : "Unlocked. \(next)")
        }
    }

    private static func footnote(for action: Action, offer: ProStore.OfferState) -> String? {
        guard case .loaded(let offer) = offer else { return nil }
        switch action {
        case .buy, .purchasing:
            return offer.isFamilyShareable ? "One-time purchase · Includes Family Sharing" : "One-time purchase"
        case .loading, .owned, .blocked, .unavailable, .loadFailed:
            return nil
        }
    }

    /// A purchase's note rides with the capsule it came from; elsewhere the status already
    /// says what went wrong. A restore's note can follow any state, blocked included.
    private static func note(
        for action: Action,
        lastPurchase: ProStore.PurchaseOutcome?,
        lastRestore: ProStore.RestoreOutcome?
    ) -> String? {
        if case .buy = action, let lastPurchase {
            switch lastPurchase {
            case .pending: return "Waiting for approval. Pro unlocks as soon as it's approved."
            case .failed: return "The purchase didn't go through. Try again."
            case .unverified: return "The App Store couldn't verify this purchase. Try Restore Purchases."
            case .purchased, .cancelled, .notAllowed, .unavailable: break
            }
        }
        switch lastRestore {
        case .nothingFound: return "No purchase found for this Apple Account."
        case .failed: return "Couldn't reach the App Store. Try again."
        case .restored, .cancelled, nil: return nil
        }
    }

    /// The iPhone promises the watch only beside something to buy, and only to someone with a
    /// watch. The watch points to the iPhone only where it can't sell Pro itself: the App
    /// Store may not offer an Apple Watch app's purchase there at all (README, "Intervally
    /// Pro").
    private static func companionLine(for action: Action, platform: PaywallPlatform, hasWatch: Bool) -> String? {
        switch (platform, action) {
        case (.phone, .buy), (.phone, .loading), (.phone, .purchasing):
            hasWatch ? "Also unlocks Intervally on your Apple Watch." : nil
        case (.watch, .unavailable), (.watch, .loadFailed):
            "You can also unlock Pro in Intervally on iPhone."
        default:
            nil
        }
    }
}

extension PaywallContent.Action {
    /// Whether the capsule buys anything: only once it shows the price.
    var isPurchasable: Bool {
        if case .buy = self { return true }
        return false
    }

    var isOwned: Bool {
        if case .owned = self { return true }
        return false
    }

    /// The capsule's words; nil while it shows a spinner, or when there is no capsule.
    var buttonTitle: String? {
        guard case .buy(let price) = self else { return nil }
        return "Unlock · \(price)"
    }

    /// The capsule spoken in full: "Unlock · $4.99" reads as punctuation.
    var buttonAccessibilityLabel: String? {
        switch self {
        case .buy(let price): "Unlock Intervally Pro for \(price)"
        case .loading: "Loading price"
        case .purchasing: "Purchasing"
        case .owned, .blocked, .unavailable, .loadFailed: nil
        }
    }

    /// The first line of a state with no capsule.
    var headline: String? {
        switch self {
        case .owned(let title, _): title
        case .blocked: "Purchases are turned off"
        case .unavailable: "Pro isn't available right now"
        case .loadFailed: "Can't reach the App Store"
        case .buy, .loading, .purchasing: nil
        }
    }

    /// The watch's words. The iPhone's paywall reads `detail(on: .phone)`.
    var detail: String? { detail(on: .watch) }

    /// The line under the headline. Only the blocked state names the device.
    func detail(on platform: PaywallPlatform) -> String? {
        switch self {
        case .owned(_, let detail): detail
        case .blocked:
            "Screen Time or a device profile is blocking purchases on this \(platform == .watch ? "watch" : "iPhone")."
        case .unavailable: "Try again later."
        case .loadFailed: "Check your connection and try again."
        case .buy, .loading, .purchasing: nil
        }
    }

    var systemImage: String? {
        switch self {
        case .owned: "checkmark.seal.fill"
        case .blocked: "lock.fill"
        case .unavailable: "clock.fill"
        case .loadFailed: "wifi.slash"
        case .buy, .loading, .purchasing: nil
        }
    }

    /// Both can clear on their own. `products(for:)` reports most network failures as an
    /// empty answer, so offline usually lands on `.unavailable` rather than `.loadFailed`.
    var offersRetry: Bool {
        self == .unavailable || self == .loadFailed
    }
}
