//
//  ThemeStore.swift
//  Intervally
//

import Foundation
import Observation

/// How Intervally looks. Classic is the free look; Pastel is Intervally Pro.
enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Raw values are stored, and travel between the devices: never rename them.
    case classic, pastel

    var id: Self { self }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .pastel: "Pastel"
        }
    }

    /// Pastel is Intervally Pro.
    var isPro: Bool { self == .pastel }

    /// Whether choosing it opens the paywall instead.
    func isLocked(isPro: Bool) -> Bool {
        self.isPro && !isPro
    }

    /// What the app shows. Without Pro it is Classic, whatever is stored, and the stored
    /// choice is never erased, so a restore or a re-purchase brings it straight back. The same
    /// rule as `TapStrength.effective`.
    static func effective(stored: AppTheme, isPro: Bool) -> AppTheme {
        isPro ? stored : .classic
    }

    /// The theme a `-qaTheme` launch flag pins, or nil for anything but "classic" or
    /// "pastel", so a typo leaves the stored theme in charge.
    static func qaOverride(_ spec: String) -> AppTheme? {
        AppTheme(rawValue: spec.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

/// The theme the user chose, which the iPhone and the watch share.
///
/// One last-writer-wins register, stamped like the presets (`SyncStamp`): `WatchSync`
/// carries it in the application context beside the `SyncDocument`, under a key of its own,
/// so an older version that doesn't know themes ignores it, and the presets' document, its
/// merge and its wire format are untouched. A choice is stamped later than any choice this
/// install has made or seen, so the latest choice wins even from a device whose clock runs
/// behind. A value this version doesn't know, from a later one, is kept and passed on, and
/// shows as Classic here.
///
/// Stored in each device's own defaults, beside the presets: on the watch that is the App
/// Group, so the complication follows the theme too.
@MainActor
@Observable
final class ThemeStore {

    enum Key {
        /// The register, as JSON.
        static let register = "settings.theme.v1"
        /// This install's tie-breaker for two choices stamped in the same millisecond.
        static let device = "settings.themeDevice.v1"
        /// `ProStore.Key.cachedIsPro`, which the widget reads without a `ProStore`.
        static let cachedIsPro = "pro.isPro.v1"
    }

    /// Never chosen: Classic, stamped at the origin, so any real choice on either device
    /// beats it.
    nonisolated static let unchosen = Register(value: AppTheme.classic.rawValue, stamp: .origin)

    /// What travels to the other device.
    private(set) var register: Register<String>

    /// The choice on this device, Pro or not. Unknown values read as Classic.
    var stored: AppTheme { AppTheme(rawValue: register.value) ?? .classic }

    /// A choice made here, so sync can offer it to the other device.
    @ObservationIgnored var onLocalChange: (@MainActor () -> Void)?
    /// A choice that arrived from the other device and changed this one.
    @ObservationIgnored var onRemoteChange: (@MainActor () -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let device: String
    /// `-qaTheme`: shown for this launch whatever is stored or bought. Never saved, never
    /// synced, and cleared by the first real choice. Only a Debug build can set it.
    private(set) var qaPin: AppTheme?

    init(defaults: UserDefaults = SharedDefaults.suite) {
        self.defaults = defaults
        self.register = Self.register(in: defaults)
        if let device = defaults.string(forKey: Key.device), !device.isEmpty {
            self.device = device
        } else {
            let device = UUID().uuidString
            defaults.set(device, forKey: Key.device)
            self.device = device
        }
    }

    /// What the app shows: the stored choice with Pro, Classic without.
    func effective(isPro: Bool) -> AppTheme {
        qaPin ?? AppTheme.effective(stored: stored, isPro: isPro)
    }

    /// Chooses `theme` on this device. Choosing what is already stored stamps nothing: each
    /// stamp is something to sync.
    func choose(_ theme: AppTheme, now: Date = Date()) {
        qaPin = nil
        guard theme.rawValue != register.value else { return }
        let wall = Int64((now.timeIntervalSince1970 * 1000).rounded(.down))
        register = Register(
            value: theme.rawValue,
            stamp: SyncStamp(millis: max(wall, register.stamp.millis + 1), device: device)
        )
        persist()
        onLocalChange?()
    }

    /// What a tap on a theme in the picker did.
    enum Tap: Equatable, Sendable {
        case chosen
        /// A free user's Pastel: nothing is chosen yet. The paywall opens, and a purchase
        /// there calls `paywallUnlocked()`.
        case paywall
    }

    /// A tap on `option` in Theme, on either device.
    func tap(_ option: AppTheme, isPro: Bool) -> Tap {
        guard !option.isLocked(isPro: isPro) else { return .paywall }
        choose(option)
        return .chosen
    }

    /// Pro unlocked on the paywall Theme opened: Pastel, what the user reached for.
    func paywallUnlocked() {
        choose(.pastel)
    }

    /// Folds in the other device's choice: the later stamp wins, and on an exact tie this
    /// device keeps its own, as `Register` does. True when this device's choice changed.
    @discardableResult
    func merge(_ remote: Register<String>) -> Bool {
        let merged = register.merged(with: remote)
        guard merged != register else { return false }
        register = merged
        persist()
        onRemoteChange?()
        return true
    }

    #if DEBUG
    /// Pins the theme shown for QA and screenshots (`-qaTheme classic|pastel`). Debug builds
    /// only: in Release it would show Pastel without the purchase.
    func pinForQA(_ theme: AppTheme) {
        qaPin = theme
    }
    #endif

    private func persist() {
        guard let data = try? JSONEncoder().encode(register) else { return }
        defaults.set(data, forKey: Key.register)
    }

    // MARK: - Reading without a store

    /// The stored register; never chosen, or unreadable, is Classic at the origin.
    nonisolated static func register(in defaults: UserDefaults) -> Register<String> {
        guard let data = defaults.data(forKey: Key.register),
              let register = try? JSONDecoder().decode(Register<String>.self, from: data),
              !register.value.isEmpty
        else { return unchosen }
        return register
    }

    /// The theme the complication wears: the stored choice, gated on the Pro flag the app
    /// caches in the same suite. Read when a timeline is built; the app reloads timelines
    /// when the theme changes.
    nonisolated static func effective(in defaults: UserDefaults = SharedDefaults.suite) -> AppTheme {
        let stored = AppTheme(rawValue: register(in: defaults).value) ?? .classic
        return AppTheme.effective(stored: stored, isPro: defaults.bool(forKey: Key.cachedIsPro))
    }
}
