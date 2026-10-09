//
//  SettingsView.swift
//  Intervally
//

import SwiftUI
import UserNotifications

/// Keys for the preferences `SettingsView` persists, in the shared suite.
enum SettingsKey {
    static let countdownTaps = "settings.countdownTaps"
    /// A `TapStrength` raw value. Kept when Pro lapses; `TapStrength.effective` decides
    /// whether it applies.
    static let tapStrength = "settings.tapStrength"
}

/// App-wide preferences, presented as a sheet from the setup screen's gear.
///
/// Small on purpose: Intervally Pro, the two haptic preferences, the theme, the alert status
/// explained where it can be acted on, and the links App Review and users look for. Nothing here is a
/// placeholder — a "Coming soon" row is the kind of incomplete-feature content review
/// rejects.
struct SettingsView: View {
    @Environment(ProStore.self) private var pro
    @Environment(ThemeStore.self) private var theme
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.countdownTaps, store: SharedDefaults.suite) private var countdownTaps = true
    @AppStorage(SettingsKey.tapStrength, store: SharedDefaults.suite) private var tapStrength: TapStrength = .standard
    @State private var alertsOff = false

    private static let privacyPolicy = URL(string: "https://josiahrininger.com/intervally/privacy")
    private static let support = URL(string: "https://josiahrininger.com/intervally/support")

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        let strengthRow = TapStrengthRow(stored: tapStrength, isPro: pro.isPro)
        let themeRow = ThemeRow(shown: theme.effective(isPro: pro.isPro), isPro: pro.isPro, platform: .watch)

        List {
            Section {
                // Pushed, like every way into the paywall: this list is already a sheet.
                NavigationLink {
                    PaywallView(context: .settings)
                } label: {
                    proRow(ProStatusRow(isPro: pro.isPro, ownership: pro.ownership))
                }
            }

            Section {
                Toggle("Countdown taps", isOn: $countdownTaps)
            } footer: {
                Text("Three light taps before each interval ends.")
            }

            Section {
                // One link for free and Pro alike: the gate shows the paywall, and swaps to
                // the picker in place once Pro unlocks.
                NavigationLink {
                    ProGate(context: .tapStrength) { TapStrengthView() }
                } label: {
                    tapStrengthLabel(strengthRow)
                }
                .accessibilityLabel("Tap Strength")
                .accessibilityValue(strengthRow.value)
                .accessibilityHint(strengthRow.isLocked ? "Opens Intervally Pro" : "")
            } footer: {
                Text(strengthRow.footer)
            }

            Section {
                // Open to everyone: Classic is free. Pastel opens the paywall from there.
                NavigationLink {
                    ThemeView()
                } label: {
                    valueLabel(ThemeRow.title, value: themeRow.value)
                }
                .accessibilityLabel(ThemeRow.title)
                .accessibilityValue(themeRow.value)
            }

            if alertsOff {
                Section {
                    Label("Alerts are off", systemImage: "bell.slash.fill")
                        .foregroundStyle(.orange)
                } footer: {
                    Text("While Intervally records a workout to Health it taps you at every interval. Without Health access it relies on notifications — turn them on for Intervally in Settings so alerts reach you with your wrist down.")
                }
            }

            Section {
                if let support = Self.support {
                    Link(destination: support) {
                        Label("Support", systemImage: "questionmark.circle.fill")
                    }
                }
                if let privacyPolicy = Self.privacyPolicy {
                    Link(destination: privacyPolicy) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                }
            } footer: {
                Text("Intervally \(version)")
            }
        }
        .accentTitle()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            alertsOff = status == .denied
        }
    }

    private func proRow(_ row: ProStatusRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: row.systemImage)
                .foregroundStyle(palette.work)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(ProStatusRow.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(row.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    /// Title over value: "Tap Strength" and "Strongest" side by side don't fit a 40mm row.
    private func valueLabel(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(value)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func tapStrengthLabel(_ row: TapStrengthRow) -> some View {
        HStack(spacing: 8) {
            valueLabel("Tap Strength", value: row.value)
            Spacer(minLength: 0)
            if row.isLocked {
                Image(systemName: "lock.fill")
                    .accessibilityHidden(true)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Settings' Tap Strength row. It shows the strength that actually plays — Standard
/// without Pro, whatever is saved — so the row never promises taps the wrist won't feel.
struct TapStrengthRow: Equatable, Sendable {
    let value: String
    let isLocked: Bool
    let footer: String

    init(stored: TapStrength, isPro: Bool) {
        value = TapStrength.effective(stored: stored, isPro: isPro).title
        isLocked = !isPro
        footer = isPro ? "Taps repeat at every interval change." : "Stronger taps are part of Intervally Pro."
    }
}

#Preview {
    let pro = ProStore()
    NavigationStack { SettingsView() }
        .environment(pro)
        .environment(ThemeStore(defaults: UserDefaults(suiteName: "preview.theme")!))
        // The paywall and Tap Strength, a push away, play their previews through it.
        .environment(RunCoordinator(
            store: WorkoutStore(defaults: UserDefaults(suiteName: "preview")!),
            pro: pro,
            haptics: HapticPlayer(strength: { .standard })
        ))
}
