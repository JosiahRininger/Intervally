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
            WorkoutsView()
                .environment(services.store)
                .environment(services.pro)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await services.handleForeground() }
        }
    }
}
