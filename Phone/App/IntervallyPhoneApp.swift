//
//  IntervallyPhoneApp.swift
//  IntervallyPhone
//

import SwiftUI

/// The iPhone companion: where workouts are planned and Pro is bought. Workouts only ever run
/// on the watch.
@main
struct IntervallyPhoneApp: App {
    /// Created in `init`, so the store is listening before the first view appears.
    @State private var services: PhoneServices
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _services = State(initialValue: PhoneServices.launch())
    }

    var body: some Scene {
        WindowGroup {
            root
                .environment(services.store)
                .environment(services.pro)
                .environment(services.sync)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                services.handleBackground()
                return
            }
            Task { await services.handleForeground() }
        }
    }

    private var root: some View {
        #if DEBUG
        PhoneRootView(forceWelcome: services.qa.welcome)
            .environment(\.qaScreen, services.qa.screen)
        #else
        PhoneRootView()
        #endif
    }
}
