//
//  TapStrengthView.swift
//  Intervally
//

import SwiftUI

/// Picks how many times each interval change taps. Reached through `ProGate`, so only a Pro
/// user sees it; choosing a level plays it at once, which is the only way to judge it.
struct TapStrengthView: View {
    @AppStorage(SettingsKey.tapStrength, store: SharedDefaults.suite) private var tapStrength: TapStrength = .standard
    /// For `previewTaps` alone, which plays on the run's own player. Called from a tap and
    /// never read in `body`, so a run going on behind this screen never redraws it.
    @Environment(RunCoordinator.self) private var coordinator

    nonisolated static let footer = "Repeats the tap at every interval change. On short intervals a countdown tap may be skipped so taps don't run together."

    var body: some View {
        List {
            Section {
                ForEach(TapStrength.allCases) { strength in
                    row(strength)
                }
            } footer: {
                Text(Self.footer)
            }
        }
        .navigationTitle("Tap Strength")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ strength: TapStrength) -> some View {
        let isSelected = strength == tapStrength

        return Button {
            tapStrength = strength
            coordinator.previewTaps(strength)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(strength.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(strength.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.work)
                }
            }
        }
        .accessibilityLabel(strength.title)
        .accessibilityValue(strength.detail)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    NavigationStack { TapStrengthView() }
        .environment(RunCoordinator(
            store: WorkoutStore(defaults: UserDefaults(suiteName: "preview")!),
            pro: ProStore(),
            haptics: HapticPlayer(strength: { .standard })
        ))
}
