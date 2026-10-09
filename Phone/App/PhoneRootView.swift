//
//  PhoneRootView.swift
//  IntervallyPhone
//

import SwiftUI

/// The welcome on the first launch, the two tabs on every other, in the theme that shows.
struct PhoneRootView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(ProStore.self) private var pro
    @Environment(AppIconFollower.self) private var icon
    @AppStorage(Welcome.seenKey, store: SharedDefaults.suite) private var welcomeSeen = false
    /// `-qaWelcome`: shown this launch whatever was seen before. Debug builds only.
    @State private var forceWelcome: Bool

    init(forceWelcome: Bool = false) {
        _forceWelcome = State(initialValue: forceWelcome)
    }

    var body: some View {
        let palette = Palette.of(theme.effective(isPro: pro.isPro))
        // The Home Screen icon follows the theme that is really chosen and paid for: a
        // `-qaTheme` pin saves nothing, so it changes no icon either.
        let iconTheme = AppTheme.effective(stored: theme.stored, isPro: pro.isPro)

        Group {
            if welcomeSeen && !forceWelcome {
                PhoneTabs()
                    .transition(.opacity)
            } else {
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        welcomeSeen = true
                        forceWelcome = false
                    }
                }
                .transition(.opacity)
            }
        }
        .background(palette.canvas)
        // Read by every screen, sheets and pushed screens included, so a new theme, from
        // Settings, the watch or Pro lapsing, redraws them all in place.
        .palette(palette)
        .onChange(of: iconTheme, initial: true) { _, theme in
            icon.follow(theme)
        }
    }
}

/// A tab of the iPhone app.
enum PhoneTab: Hashable {
    case workouts, history
}

/// The app's two tabs: the workouts planned here, and the sessions the watch ran. Each has its
/// own stack and its own gear for Settings.
struct PhoneTabs: View {
    @State private var tab = PhoneTab.workouts

    var body: some View {
        TabView(selection: $tab) {
            Tab("Workouts", systemImage: "figure.highintensity.intervaltraining", value: PhoneTab.workouts) {
                WorkoutsView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: PhoneTab.history) {
                HistoryView()
            }
        }
        #if DEBUG
        .modifier(TabsQAOpen(tab: $tab))
        #endif
    }
}
