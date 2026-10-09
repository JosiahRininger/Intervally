//
//  StoreNoticeTests.swift
//  IntervallyPhoneTests
//

import Foundation
import StoreKit
import Testing
@testable import IntervallyPhone

/// What Settings says after Restore, Redeem Code and Request a Refund, and how the refund
/// sheet's answers map.
@Suite("Settings store notices")
struct StoreNoticeTests {

    @Test("Restore: an answer for each outcome but a cancel")
    func restore() {
        #expect(StoreNotice.restore(.restored)?.title == "Pro Restored")
        #expect(StoreNotice.restore(.nothingFound)?.message == "No purchase found for this Apple Account.")
        #expect(StoreNotice.restore(.failed)?.message == "Couldn't reach the App Store. Try again.")
        #expect(StoreNotice.restore(.cancelled) == nil)
    }

    @Test("Redeem Code: the sheet speaks for itself; only a failure needs words")
    func redeem() {
        #expect(StoreNotice.redeem(.presented) == nil)
        #expect(StoreNotice.redeem(.failed) != nil)
    }

    @Test("Request a Refund: each outcome but a cancel says what happens next")
    func refund() {
        #expect(StoreNotice.refund(.requested)?.message.contains("email") == true)
        #expect(StoreNotice.refund(.alreadyRequested)?.title == "Already Requested")
        #expect(StoreNotice.refund(.nothingToRefund)?.message.contains("Family") == false)
        #expect(StoreNotice.refund(.nothingToRefund)?.message.contains("family") == true)
        #expect(StoreNotice.refund(.failed) != nil)
        #expect(StoreNotice.refund(.cancelled) == nil)
    }

    @Test("The refund sheet's answers and errors map to the outcomes")
    func refundMapping() {
        #expect(ProStore.refundOutcome(StoreKit.Transaction.RefundRequestStatus.success) == .requested)
        #expect(ProStore.refundOutcome(StoreKit.Transaction.RefundRequestStatus.userCancelled) == .cancelled)
        #expect(ProStore.refundOutcome(StoreKit.Transaction.RefundRequestError.duplicateRequest) == .alreadyRequested)
        #expect(ProStore.refundOutcome(StoreKit.Transaction.RefundRequestError.failed) == .failed)
        #expect(ProStore.refundOutcome(URLError(.notConnectedToInternet)) == .failed)
    }

    @Test("Every notice has words, and none is empty")
    func noneEmpty() {
        let notices: [StoreNotice?] = [
            .restore(.restored), .restore(.nothingFound), .restore(.failed), .redeem(.failed),
            .refund(.requested), .refund(.alreadyRequested), .refund(.nothingToRefund), .refund(.failed),
        ]
        for notice in notices {
            #expect(notice.map { !$0.title.isEmpty && !$0.message.isEmpty } == true)
        }
    }
}
