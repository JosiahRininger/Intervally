//
//  ThemeView.swift
//  Intervally
//

import SwiftUI

/// Picks how Intervally looks: Classic, free, or Pastel, Intervally Pro. Each option shows
/// its colours as a small ring. The watch keeps its black screen in either; Pastel changes
/// the phase colours. A free user's Pastel opens the paywall, and a purchase there applies it.
struct ThemeView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(ProStore.self) private var pro
    @Environment(\.palette) private var palette

    @State private var showsPaywall = false

    var body: some View {
        let shown = theme.effective(isPro: pro.isPro)
        let row = ThemeRow(shown: shown, isPro: pro.isPro, platform: .watch)

        List {
            Section {
                ForEach(AppTheme.allCases) { option in
                    optionRow(option, shown: shown)
                }
            } footer: {
                if let footer = row.footer {
                    Text(footer)
                }
            }
        }
        .accentTitle()
        .navigationTitle(ThemeRow.title)
        .navigationBarTitleDisplayMode(.inline)
        // Pushed inside Settings' own stack, like every way into the paywall.
        .navigationDestination(isPresented: $showsPaywall) {
            PaywallView(context: .themes) {
                theme.paywallUnlocked()
                showsPaywall = false
            }
        }
    }

    private func optionRow(_ option: AppTheme, shown: AppTheme) -> some View {
        let isSelected = option == shown
        let isLocked = option.isLocked(isPro: pro.isPro)

        return Button {
            if theme.tap(option, isPro: pro.isPro) == .paywall {
                showsPaywall = true
            }
        } label: {
            HStack(spacing: 8) {
                SegmentedRing(plan: IntervalPlan(workout: AppTheme.swatch), strokeRatio: 0.15, gap: 1)
                    .environment(\.palette, .of(option))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(option.detail(on: .watch))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                if isLocked {
                    ProBadge()
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.work)
                }
            }
        }
        .accessibilityLabel(option.title)
        .accessibilityValue(option.detail(on: .watch))
        .accessibilityHint(isLocked ? "Opens Intervally Pro" : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    let pro = ProStore()
    NavigationStack { ThemeView() }
        .environment(pro)
        .environment(ThemeStore(defaults: UserDefaults(suiteName: "preview.theme")!))
        .environment(RunCoordinator(
            store: WorkoutStore(defaults: UserDefaults(suiteName: "preview")!),
            pro: pro,
            haptics: HapticPlayer(strength: { .standard })
        ))
}
