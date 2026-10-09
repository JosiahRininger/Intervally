//
//  ProStatusRow.swift
//  Intervally
//

import Foundation

/// Settings' Intervally Pro row, for each way Pro can be held, on the watch and the iPhone.
struct ProStatusRow: Equatable, Sendable {
    static let title = "Intervally Pro"

    let subtitle: String
    let systemImage: String

    /// Pro with `ownership == .none` — the cached answer before StoreKit's, or a QA
    /// override — reads as bought outright.
    init(isPro: Bool, ownership: ProStore.Ownership) {
        switch (isPro, ownership) {
        case (false, _):
            subtitle = "Unlimited presets & more"
            systemImage = "sparkles"
        case (true, .familyShared):
            subtitle = "Shared by your family"
            systemImage = "checkmark.seal.fill"
        case (true, .purchased), (true, .none):
            subtitle = "Unlocked"
            systemImage = "checkmark.seal.fill"
        }
    }
}
