//
//  PhoneRootView.swift
//  IntervallyPhone
//

import SwiftUI

/// The welcome on the first launch, the two tabs on every other.
struct PhoneRootView: View {
    @AppStorage(Welcome.seenKey, store: SharedDefaults.suite) private var welcomeSeen = false
    /// `-qaWelcome`: shown this launch whatever was seen before. Debug builds only.
    @State private var forceWelcome: Bool

    init(forceWelcome: Bool = false) {
        _forceWelcome = State(initialValue: forceWelcome)
    }

    var body: some View {
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
        .background(Color.black)
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
