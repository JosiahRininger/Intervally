//
//  ReviewRequest.swift
//  IntervallyPhone
//

import StoreKit
import SwiftUI

extension ReviewLedger {
    /// Asks a second after `moment`, so the prompt never lands mid-transition, and only if
    /// `ReviewPolicy` says the moment is a good one.
    func ask(_ moment: ReviewMoment, using requestReview: RequestReviewAction) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            ask(moment) { requestReview() }
        }
    }
}
