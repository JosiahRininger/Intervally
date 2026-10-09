//
//  IntervallyApp.swift
//  Intervally
//

import SwiftUI

/// The modern single-target watchOS app entry point.
///
/// This replaces the Xcode 11 arrangement the project used to have: a WatchKit App target
/// holding a storyboard, a separate WatchKit Extension target, a `WKExtensionDelegate`, and
/// a `WKHostingController` subclass that built the root view — and, along the way, seeded
/// `UserDefaults` and owned the extended runtime session, neither of which belongs in a
/// view controller.
@main
struct IntervallyApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // The services come from the delegate, which exists before any view does — so
            // there is no blank first frame while a coordinator is built, and background
            // workout recovery has something to talk to.
            RootView()
                .environment(delegate.store)
                .environment(delegate.coordinator)
                .environment(delegate.pro)
        }
        .onChange(of: scenePhase) { _, phase in
            // Lowering the wrist suspends the app soon after; send an edit made just before
            // rather than leave it waiting out the debounce until the next launch.
            if phase != .active { delegate.sync.flush() }
        }
    }
}
