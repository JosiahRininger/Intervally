//
//  ProGating.swift
//  Intervally
//

import Foundation

/// The single Intervally Pro product and the limits of the free tier.
enum ProProduct {
    /// Immutable in App Store Connect and never reusable, so it never changes here either.
    static let id = "com.josiahrininger.intervally.pro"
    /// Exactly the three starters, so a fresh install fills it: the free app is complete
    /// and the paywall only appears when someone asks for a fourth preset.
    static let freePresetLimit = 3
}

/// The one question gated code asks. Views and the coordinator depend on this rather than
/// on `ProStore`, so tests can flip it without a StoreKit session.
@MainActor
protocol ProGating: AnyObject {
    var isPro: Bool { get }
}

extension ProGating {
    /// Up to three presets free. A device that already holds more keeps every one — after a
    /// refund, say — and can still edit, run and delete them; it just can't add.
    func canAddPreset(currentCount: Int) -> Bool {
        isPro || currentCount < ProProduct.freePresetLimit
    }
}
