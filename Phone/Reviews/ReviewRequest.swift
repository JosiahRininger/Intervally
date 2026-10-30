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

    /// A purchase of Pro went through here: the next return to the library asks, as above.
    func markPaidForPro(using requestReview: RequestReviewAction) {
        markPaidForPro { requestReview() }
    }
}
