//
//  StoreNotice.swift
//  IntervallyPhone
//

import Foundation

/// What Settings says once a Restore, Redeem Code or Request a Refund comes back: an alert's
/// title and message, or nothing where the system's own sheet already said it.
struct StoreNotice: Equatable, Identifiable {
    let title: String
    let message: String
    var id: String { title + message }

    static func restore(_ outcome: ProStore.RestoreOutcome) -> StoreNotice? {
        switch outcome {
        case .restored: StoreNotice(title: "Pro Restored", message: "Intervally Pro is unlocked on this iPhone.")
        case .nothingFound: StoreNotice(title: "Nothing to Restore", message: "No purchase found for this Apple Account.")
        case .failed: StoreNotice(title: "Couldn't Restore", message: "Couldn't reach the App Store. Try again.")
        case .cancelled: nil
        }
    }

    /// A redeemed code needs no words here: its purchase arrives like any other, and Pro
    /// unlocks.
    static func redeem(_ outcome: ProStore.RedeemOutcome) -> StoreNotice? {
        switch outcome {
        case .presented: nil
        case .failed: StoreNotice(title: "Couldn't Open Redeem Code", message: "Couldn't reach the App Store. Try again.")
        }
    }

    static func refund(_ outcome: ProStore.RefundOutcome) -> StoreNotice? {
        switch outcome {
        case .requested:
            StoreNotice(title: "Refund Requested", message: "Apple will email you once it has looked at your request.")
        case .alreadyRequested:
            StoreNotice(title: "Already Requested", message: "A refund request for this purchase is already open.")
        case .nothingToRefund:
            StoreNotice(
                title: "Nothing to Refund",
                message: "No purchase of Intervally Pro was found for this Apple Account. Pro shared by your family can be refunded only by whoever bought it."
            )
        case .failed: StoreNotice(title: "Couldn't Request a Refund", message: "Couldn't reach the App Store. Try again.")
        case .cancelled: nil
        }
    }
}
