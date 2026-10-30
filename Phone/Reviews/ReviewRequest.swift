//
//  ReviewRequest.swift
//  IntervallyPhone
//

import StoreKit
import SwiftUI

extension ReviewLedger {
    /// Asks a second after `moment`, so the prompt never lands mid-transition, and only if
    /// it can still land then (`ReviewMoment.canPresent`) and `ReviewPolicy` says the moment
    /// is a good one.
    func ask(_ moment: ReviewMoment, using requestReview: RequestReviewAction) {
        askLater(moment) { requestReview() }
    }

    /// The paywall's purchase ended: one that went through asks on the next return to the
    /// library, as above.
    func purchaseEnded(_ outcome: ProStore.PurchaseOutcome, using requestReview: RequestReviewAction) {
        purchaseEnded(outcome) { requestReview() }
    }
}
