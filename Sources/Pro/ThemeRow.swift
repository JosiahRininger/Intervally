//
//  ThemeRow.swift
//  Intervally
//

import Foundation

/// Settings' Theme row and its picker, on the watch and the iPhone. The row shows the theme
/// that actually shows — Classic without Pro, whatever is stored — so it never names a look
/// the screen isn't wearing.
struct ThemeRow: Equatable, Sendable {
    static let title = "Theme"
    static let systemImage = "paintpalette"

    /// The theme on screen.
    let value: String
    /// Under the picker.
    let footer: String?

    /// - Parameters:
    ///   - shown: the effective theme (`ThemeStore.effective(isPro:)`).
    ///   - hasWatch: iPhone only: whether there is a watch to follow the choice.
    init(shown: AppTheme, isPro: Bool, platform: PaywallPlatform, hasWatch: Bool = true) {
        value = shown.title
        if !isPro {
            footer = "Pastel is part of Intervally Pro."
        } else {
            switch platform {
            case .watch: footer = "Intervally on your iPhone follows."
            // The watch wears Pastel's colours on its own black screen.
            case .phone: footer = hasWatch ? "Your Apple Watch follows, keeping its black screen." : nil
            }
        }
    }
}

extension AppTheme {
    /// The line under its name in the picker.
    func detail(on platform: PaywallPlatform) -> String {
        switch (self, platform) {
        case (.classic, .watch): "Blue for work"
        case (.pastel, .watch): "Pink for work"
        case (.classic, .phone): "Dark, with blue for work"
        case (.pastel, .phone): "Light, with pink for work"
        }
    }

    /// The workout the picker's swatches draw: every phase, so every colour shows.
    static let swatch = IntervalWorkout(
        name: "Swatch", prepareSeconds: 10, warmupSeconds: 60, workSeconds: 40,
        restSeconds: 20, rounds: 4, cooldownSeconds: 60
    )
}
