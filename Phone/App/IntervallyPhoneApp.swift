//
//  IntervallyPhoneApp.swift
//  IntervallyPhone
//

import HealthKitUI
import SwiftUI

/// Intervally on iPhone: where workouts are planned, run, looked back on, and Pro is bought.
/// A workout runs here or on the watch, whichever it is started on.
@main
struct IntervallyPhoneApp: App {
    /// Created in `init`, so the store is listening before the first view appears.
    @State private var services: PhoneServices
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _services = State(initialValue: PhoneServices.launch())
    }

    var body: some Scene {
        WindowGroup {
            root
                .environment(services.store)
                .environment(services.pro)
                .environment(services.theme)
                .environment(services.sync)
                .environment(services.history)
                .environment(services.reviews)
                .environment(services.icon)
                .environment(services.run)
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

/// Hands back a workout session that outlived the app: iOS relaunches an app whose session
/// was still running when it crashed or was terminated, and says so as the scene connects.
final class PhoneAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if options.shouldHandleActiveWorkoutRecovery {
            PhoneServices.live?.run.recoverWorkoutSession()
        }
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }
}
