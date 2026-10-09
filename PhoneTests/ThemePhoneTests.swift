//
//  ThemePhoneTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// Pastel on iPhone: its palette, its QA flag, its door, and the Home Screen icon that
/// follows it.
@Suite("Theme on iPhone")
@MainActor
struct ThemePhoneTests {

    @Test("Pastel on iPhone is the light palette; Classic is the black one")
    func palettes() {
        #expect(Palette.of(.pastel) == .pastelPhone)
        #expect(Palette.of(.classic) == .classic)
        #expect(Palette.pastelPhone.colorScheme == .light)
        #expect(Palette.classic.colorScheme == .dark)
        // Classic keeps the asset catalog's AccentColor and its glass as it was.
        #expect(Palette.classic.accent == nil)
        #expect(Palette.classic.glassTint == nil)
        #expect(Palette.pastelPhone.accent == Palette.pastelPhone.workInk)
    }

    @Test("A tile's text takes the theme's ink, rounds the neutral")
    func tileInk() {
        #expect(PresetField.work.tint(in: .pastelPhone) == Palette.pastelPhone.workInk)
        #expect(PresetField.prepare.tint(in: .pastelPhone) == Palette.pastelPhone.prepareInk)
        #expect(PresetField.rounds.tint(in: .pastelPhone) == Palette.pastelPhone.neutral)
        #expect(PresetField.work.tint(in: .classic) == Theme.work)
    }

    @Test("The Theme door reads the same on iPhone")
    func door() {
        let content = PaywallContent.make(
            context: .themes, isPro: false, ownership: .none, canMakePayments: true,
            offer: .loaded(ProOffer(displayPrice: "$4.99", isFamilyShareable: true)),
            isPurchasing: false, lastPurchase: nil, lastRestore: nil, platform: .phone
        )
        #expect(content.contextLine == "Make Intervally yours with Pastel.")
        #expect(content.offersPreview == false)
        #expect(content.companionLine == "Also unlocks Intervally on your Apple Watch.")
    }

    #if DEBUG
    @Test("-qaTheme is read from its value, and a typo is ignored")
    func qaFlag() {
        #expect(PhoneQAOptions.parse(["-qaTheme", "pastel"]) == PhoneQAOptions(theme: .pastel))
        #expect(PhoneQAOptions.parse(["-qaTheme", "classic", "-qaPro", "free"]) == PhoneQAOptions(pro: false, theme: .classic))
        #expect(PhoneQAOptions.parse(["-qaTheme", "pink"]) == PhoneQAOptions())
        #expect(PhoneQAOptions.parse(["-qaTheme", "-qaPro", "pro"]) == PhoneQAOptions(pro: true))
        #expect(PhoneQAOptions(theme: .pastel).isActive, "A themed launch is a QA launch: no review prompt")
        #expect(PhoneQAOptions.parse(["-qaOpen", "theme"]).screen == .theme)
    }
    #endif
}

/// The iPhone's Home Screen icon: Pastel's while Pastel shows, the dumbbell otherwise.
@Suite("Alternate app icon")
@MainActor
struct AppIconTests {

    /// Stands in for `UIApplication`: records every icon asked for, and refuses the first
    /// `failures` of them as the simulator did just after a launch.
    final class FakeApplication: AlternateIconSetting {
        var supportsAlternateIcons = true
        var alternateIconName: String?
        var failures = 0
        private(set) var requests: [String?] = []

        func setAlternateIconName(_ alternateIconName: String?) async throws {
            requests.append(alternateIconName)
            if failures > 0 {
                failures -= 1
                throw CocoaError(.fileReadUnknown)
            }
            self.alternateIconName = alternateIconName
        }
    }

    /// No waiting between tries.
    nonisolated static let immediately: @Sendable (Duration) async throws -> Void = { _ in }

    @MainActor
    final class Flag {
        var value: Bool
        init(_ value: Bool) { self.value = value }
        var isOpen: Bool { value }
    }

    @Test("Pastel has its icon; Classic is the primary dumbbell")
    func names() {
        #expect(AppTheme.pastel.iconName == "AppIcon-Pastel")
        #expect(AppTheme.classic.iconName == nil)
    }

    @Test("Only a different icon is asked for, only where icons can change, and only while active")
    func decide() {
        #expect(AppIconChange.decide(target: "AppIcon-Pastel", current: nil, supportsAlternateIcons: true, isActive: true) == .set("AppIcon-Pastel"))
        #expect(AppIconChange.decide(target: nil, current: "AppIcon-Pastel", supportsAlternateIcons: true, isActive: true) == .set(nil))
        #expect(AppIconChange.decide(target: "AppIcon-Pastel", current: "AppIcon-Pastel", supportsAlternateIcons: true, isActive: true) == .unchanged)
        #expect(AppIconChange.decide(target: nil, current: nil, supportsAlternateIcons: true, isActive: false) == .unchanged)
        #expect(AppIconChange.decide(target: "AppIcon-Pastel", current: nil, supportsAlternateIcons: false, isActive: true) == .unchanged)
        #expect(AppIconChange.decide(target: "AppIcon-Pastel", current: nil, supportsAlternateIcons: true, isActive: false) == .deferred("AppIcon-Pastel"))
    }

    @Test("The icon follows the theme, and is never asked for again once it matches")
    func follows() async {
        let app = FakeApplication()
        let follower = AppIconFollower(application: { app }, isActive: { true }, sleep: Self.immediately)
        follower.isEnabled = true

        follower.follow(.classic)
        #expect(follower.lastChange == .unchanged)
        follower.follow(.pastel)
        #expect(await waitUntil { app.requests == ["AppIcon-Pastel"] })
        follower.follow(.pastel)
        follower.cameForward()
        // A refund, or Classic chosen on the watch.
        follower.follow(.classic)
        #expect(await waitUntil { app.requests == ["AppIcon-Pastel", nil] })
    }

    @Test("A change that arrives in the background waits for the next foreground")
    func deferredUntilActive() async {
        let app = FakeApplication()
        let active = Flag(false)
        let follower = AppIconFollower(application: { app }, isActive: { active.value }, sleep: Self.immediately)
        follower.isEnabled = true

        follower.follow(.pastel)
        #expect(follower.lastChange == .deferred("AppIcon-Pastel"))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(app.requests.isEmpty)

        active.value = true
        follower.cameForward()
        #expect(await waitUntil { app.requests == ["AppIcon-Pastel"] })
    }

    @Test("A refused change is tried again, and stops once the icon is right")
    func retries() async {
        let app = FakeApplication()
        app.failures = 2
        let follower = AppIconFollower(application: { app }, isActive: { true }, sleep: Self.immediately)
        follower.isEnabled = true
        follower.follow(.pastel)
        #expect(await waitUntil { app.alternateIconName == "AppIcon-Pastel" })
        #expect(app.requests == ["AppIcon-Pastel", "AppIcon-Pastel", "AppIcon-Pastel"])
    }

    @Test("A change that never takes is given up after a few tries, and left for the next foreground")
    func givesUp() async {
        let app = FakeApplication()
        app.failures = 10
        let follower = AppIconFollower(application: { app }, isActive: { true }, sleep: Self.immediately)
        follower.isEnabled = true
        follower.follow(.pastel)
        #expect(await waitUntil { app.requests.count == AppIconFollower.attempts })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(app.requests.count == AppIconFollower.attempts)
        app.failures = 0
        follower.cameForward()
        #expect(await waitUntil { app.alternateIconName == "AppIcon-Pastel" })
    }

    @Test("A theme that changes back before the icon is set leaves the icon alone")
    func changedBack() async {
        let app = FakeApplication()
        let gate = Flag(false)
        let follower = AppIconFollower(application: { app }, isActive: { true }, sleep: { _ in
            while await !gate.isOpen { try await Task.sleep(for: .milliseconds(5)) }
        })
        follower.isEnabled = true
        follower.follow(.pastel)
        follower.follow(.classic)
        gate.value = true
        try? await Task.sleep(for: .milliseconds(100))
        #expect(app.requests.isEmpty)
    }

    @Test("Off until the app starts it: a test's services never change the icon")
    func offUntilStarted() async {
        let app = FakeApplication()
        let follower = AppIconFollower(application: { app }, isActive: { true }, sleep: Self.immediately)
        follower.follow(.pastel)
        follower.cameForward()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(app.requests.isEmpty)
        #expect(PhoneServices().icon.isEnabled == false)
    }

    @Test("A device that can't change icons is never asked to")
    func unsupported() async {
        let app = FakeApplication()
        app.supportsAlternateIcons = false
        let follower = AppIconFollower(application: { app }, isActive: { true }, sleep: Self.immediately)
        follower.isEnabled = true
        follower.follow(.pastel)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(app.requests.isEmpty)
    }

    // MARK: The asset

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    @Test("Pastel's icon is one 1024 square with no alpha, the art in Design, byte for byte")
    func asset() throws {
        let set = Self.root.appendingPathComponent("Phone/Resources/Assets.xcassets/AppIcon-Pastel.appiconset")
        let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: set.appendingPathComponent("Contents.json"))) as? [String: Any]
        let images = try #require(contents?["images"] as? [[String: String]])
        #expect(images.count == 1)
        #expect(images.first?["filename"] == "AppIcon-Pastel.png")
        #expect(images.first?["size"] == "1024x1024")
        #expect(images.first?["platform"] == "ios")

        let icon = try Data(contentsOf: set.appendingPathComponent("AppIcon-Pastel.png"))
        let header = try #require(PNGHeader(icon))
        #expect(header.width == 1024 && header.height == 1024)
        #expect(!header.hasAlpha)
        #expect(icon == (try Data(contentsOf: Self.root.appendingPathComponent("Design/AppIcon/AppIcon-pastel.png"))))
        // The primary icon is untouched: still the watch's art.
        let primary = try Data(contentsOf: Self.root.appendingPathComponent("Phone/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
        #expect(primary != icon)
    }

    @Test("The built app declares the alternate icon, so iOS will set it")
    func declared() throws {
        let icons = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let alternates = try #require(icons["CFBundleAlternateIcons"] as? [String: Any])
        #expect(alternates[AppTheme.pastel.iconName ?? ""] != nil)
        let primary = try #require(icons["CFBundlePrimaryIcon"] as? [String: Any])
        #expect(primary["CFBundleIconName"] as? String == "AppIcon")
    }
}
