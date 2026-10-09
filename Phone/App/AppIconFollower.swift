//
//  AppIconFollower.swift
//  IntervallyPhone
//

import Observation
import UIKit
import os

/// The few `UIApplication` calls the icon makes, so the tests can stand in for them.
@MainActor
protocol AlternateIconSetting: AnyObject {
    var supportsAlternateIcons: Bool { get }
    var alternateIconName: String? { get }
    func setAlternateIconName(_ alternateIconName: String?) async throws
}

extension UIApplication: AlternateIconSetting {}

/// What the icon does when the theme that shows changes, worked out apart from UIKit.
enum AppIconChange: Equatable, Sendable {
    /// Already right, or this device can't change icons.
    case unchanged
    /// Set it now. Nil is the primary icon, the dumbbell.
    case set(String?)
    /// Not now: UIKit refuses a new icon unless the app is active. Set it on the next
    /// foreground.
    case deferred(String?)

    static func decide(target: String?, current: String?, supportsAlternateIcons: Bool, isActive: Bool) -> AppIconChange {
        guard supportsAlternateIcons, target != current else { return .unchanged }
        return isActive ? .set(target) : .deferred(target)
    }
}

extension AppTheme {
    /// The iPhone's Home Screen icon for the theme: Pastel's alternate, or nil for the
    /// primary dumbbell. The name of the asset set `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`
    /// compiles in.
    var iconName: String? {
        switch self {
        case .classic: nil
        case .pastel: "AppIcon-Pastel"
        }
    }
}

/// Keeps the iPhone's Home Screen icon on the theme that shows: Pastel's icon while Pastel
/// shows, the dumbbell otherwise, a refund or a choice synced from the watch included.
///
/// iOS shows its own "You have changed the icon" alert on every change, which is expected.
/// A change is asked for a moment after it is decided, and tried again a couple of times:
/// made in the first instant after a launch, the simulator refused it ("Resource
/// temporarily unavailable") and the icon stayed behind. A failure is only logged; an icon
/// still left behind is put right at the next change or foreground. Off until the app starts
/// it, so a test's services, and the unit-test host, never change the icon.
@MainActor
@Observable
final class AppIconFollower {
    /// Set by `PhoneServices.start`.
    @ObservationIgnored var isEnabled = false

    /// The icon the theme asks for, kept for the next foreground when it can't be set now.
    @ObservationIgnored private(set) var target: String?
    /// The last change decided, for the tests.
    @ObservationIgnored private(set) var lastChange: AppIconChange = .unchanged

    @ObservationIgnored private let application: () -> any AlternateIconSetting
    @ObservationIgnored private let isActive: () -> Bool
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var hasTarget = false
    /// The change being made. It reads `target` again before each try, so a newer theme
    /// that lands meanwhile is the one set.
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.josiahrininger.intervally", category: "icon")

    /// Before the first try, and between tries.
    static let settle: Duration = .milliseconds(800)
    static let retryDelay: Duration = .seconds(2)
    static let attempts = 3

    init(
        application: @escaping () -> any AlternateIconSetting = { UIApplication.shared },
        isActive: @escaping () -> Bool = { UIApplication.shared.applicationState == .active },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.application = application
        self.isActive = isActive
        self.sleep = sleep
    }

    /// The theme that shows is now `theme`.
    func follow(_ theme: AppTheme) {
        target = theme.iconName
        hasTarget = true
        update()
    }

    /// The app came forward: an icon that had to wait is set now.
    func cameForward() {
        update()
    }

    private func update() {
        guard isEnabled, hasTarget else { return }
        let change = currentChange()
        lastChange = change
        guard case .set = change, inFlight == nil else { return }
        inFlight = Task { [weak self] in
            let settled = await self?.apply() ?? false
            self?.inFlight = nil
            // A theme that changed while the icon was being set is followed now. Not after
            // giving up, which would only try again at once.
            if settled { self?.update() }
        }
    }

    private func currentChange() -> AppIconChange {
        let app = application()
        return AppIconChange.decide(
            target: target, current: app.alternateIconName,
            supportsAlternateIcons: app.supportsAlternateIcons, isActive: isActive()
        )
    }

    /// True once the icon is right or there is nothing to do here; false after giving up.
    private func apply() async -> Bool {
        for attempt in 1...Self.attempts {
            do { try await sleep(attempt == 1 ? Self.settle : Self.retryDelay) } catch { return false }
            // Decided again: the theme may have changed back, or the app gone to the
            // background, where the next foreground takes over.
            guard isEnabled, case .set(let name) = currentChange() else { return true }
            do {
                try await application().setAlternateIconName(name)
                log.info("icon set: \(name ?? "primary", privacy: .public)")
                return true
            } catch {
                log.error("icon not set (try \(attempt)): \(error.localizedDescription, privacy: .public)")
            }
        }
        return false
    }
}
