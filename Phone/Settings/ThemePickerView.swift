//
//  ThemePickerView.swift
//  IntervallyPhone
//

import SwiftUI

/// Settings > Theme: Classic and Pastel side by side, each previewed as the Workouts screen's
/// card in its own colours, as the system's Appearance setting previews Light and Dark.
/// Choosing one changes every screen at once, here and on the watch. A free user's Pastel
/// opens Intervally Pro, and a purchase there chooses it (`PhoneSettingsView`).
struct ThemePickerView: View {
    /// Pushes the paywall, for a free user's Pastel.
    let openPaywall: () -> Void

    @Environment(ThemeStore.self) private var theme
    @Environment(ProStore.self) private var pro
    @Environment(WatchSync.self) private var sync
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shown = theme.effective(isPro: pro.isPro)
        let row = ThemeRow(shown: shown, isPro: pro.isPro, platform: .phone, hasWatch: sync.peer.hasWatch)
        // Side by side, like Light and Dark in the system's own picker; stacked at the
        // accessibility sizes, where half a screen can't hold the words.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 20))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))

        ScrollView {
            VStack(spacing: 20) {
                layout {
                    ForEach(AppTheme.allCases) { option in
                        ThemeOptionCard(
                            option: option,
                            isSelected: option == shown,
                            isLocked: option.isLocked(isPro: pro.isPro)
                        ) {
                            choose(option)
                        }
                    }
                }

                if let footer = row.footer {
                    Text(footer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .appCanvas()
        .navigationTitle(ThemeRow.title)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: shown)
    }

    private func choose(_ option: AppTheme) {
        let tap = withAnimation(.easeInOut(duration: 0.25)) {
            theme.tap(option, isPro: pro.isPro)
        }
        if tap == .paywall { openPaywall() }
    }
}

/// One theme: a preview in its own colours, its name and what it is, and whether it is
/// chosen, or Pro.
private struct ThemeOptionCard: View {
    let option: AppTheme
    let isSelected: Bool
    let isLocked: Bool
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ThemePreview(palette: .of(option))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isSelected ? palette.workInk : Color.secondary.opacity(0.3), lineWidth: isSelected ? 3 : 1)
                    }

                VStack(spacing: 2) {
                    Text(option.title)
                        .font(.headline)
                    Text(option.detail(on: .phone))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                indicator
                    .frame(height: 24)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.title)
        .accessibilityValue(option.detail(on: .phone))
        .accessibilityHint(isLocked ? "Opens Intervally Pro" : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    /// The system's selection circle, or PRO where a tap opens the paywall instead.
    @ViewBuilder
    private var indicator: some View {
        if isLocked {
            ProBadge()
        } else if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(palette.workInk)
        } else {
            Image(systemName: "circle")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

/// The Workouts screen's up-next card in miniature, drawn in `palette` whatever the app is
/// wearing: its canvas, a card, the workout's ring with the total inside, and the rhythm.
private struct ThemePreview: View {
    let palette: Palette

    var body: some View {
        let workout = AppTheme.swatch

        VStack(spacing: 10) {
            ZStack {
                SegmentedRing(plan: IntervalPlan(workout: workout), strokeRatio: 0.09, gap: 1.5)
                Text(DurationFormat.clock(workout.totalSeconds))
                    .font(.hero(17))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 14)
            }
            .frame(width: 76, height: 76)

            RhythmLine(workout: workout)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .tileBackground()
        .padding(12)
        .background(palette.canvas, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        // Its own colours and appearance, so Classic's preview stays dark in Pastel, and the
        // other way round.
        .environment(\.palette, palette)
        .environment(\.colorScheme, palette.colorScheme)
        .accessibilityHidden(true)
    }
}

#Preview {
    let store = WorkoutStore(defaults: UserDefaults(suiteName: "preview.theme.store") ?? .standard)
    NavigationStack {
        ThemePickerView {}
    }
    .environment(ProStore(defaults: UserDefaults(suiteName: "preview.pro") ?? .standard))
    .environment(ThemeStore(defaults: UserDefaults(suiteName: "preview.theme") ?? .standard))
    .environment(WatchSync(store: store))
}
