//
//  ProStore+Phone.swift
//  IntervallyPhone
//

import StoreKit
import UIKit

/// The two App Store sheets only iOS has: redeeming an offer code and asking for a refund.
/// Both need the window scene they appear over, which is why they live here rather than in
/// the shared `ProStore`; like it, this file never imports SwiftUI, where `Transaction` is
/// ambiguous.
extension ProStore {

    enum RedeemOutcome: Equatable, Sendable {
        /// The sheet was shown and closed. A redeemed code's transaction arrives through
        /// `Transaction.updates`, which `start()` listens to.
        case presented
        case failed
    }

    enum RefundOutcome: Equatable, Sendable {
        /// Apple has the request; the decision comes by email, and a granted refund through
        /// `Transaction.updates`.
        case requested
        case cancelled
        /// A request for this purchase is already open.
        case alreadyRequested
        /// Nothing this Apple Account bought outright to refund.
        case nothingToRefund
        case failed
    }

    /// Presents the App Store's offer-code sheet over the app's window.
    func redeemOfferCode() async -> RedeemOutcome {
        guard let scene = Self.foregroundScene() else { return .failed }
        do {
            try await AppStore.presentOfferCodeRedeemSheet(in: scene)
            return .presented
        } catch {
            return .failed
        }
    }

    /// Opens the App Store's refund sheet for the Pro purchase.
    func requestRefund() async -> RefundOutcome {
        guard let id = await Self.latestPurchasedTransactionID() else { return .nothingToRefund }
        guard let scene = Self.foregroundScene() else { return .failed }
        do {
            return Self.refundOutcome(try await StoreKit.Transaction.beginRefundRequest(for: id, in: scene))
        } catch {
            return Self.refundOutcome(error)
        }
    }

    nonisolated static func refundOutcome(_ status: StoreKit.Transaction.RefundRequestStatus) -> RefundOutcome {
        switch status {
        case .success: .requested
        case .userCancelled: .cancelled
        @unknown default: .failed
        }
    }

    nonisolated static func refundOutcome(_ error: any Error) -> RefundOutcome {
        (error as? StoreKit.Transaction.RefundRequestError) == .duplicateRequest ? .alreadyRequested : .failed
    }

    /// The scene the user is looking at. The app has one, but a scene still connecting or in
    /// the background can't present a sheet.
    private static func foregroundScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}
