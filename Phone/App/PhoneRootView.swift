//
//  PhoneRootView.swift
//  IntervallyPhone
//

import SwiftUI

/// The welcome on the first launch, the workouts on every other.
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
                WorkoutsView()
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
