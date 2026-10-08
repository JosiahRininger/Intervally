//
//  IntervallyControl.swift
//  IntervallyWidget
//

import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center button — and on Ultra, an Action button assignment — that starts the
/// selected workout. The intent opens the app to do it: a run needs the app in the
/// foreground to take its workout session.
struct IntervallyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.josiahrininger.intervally.control") {
            ControlWidgetButton(action: StartWorkoutIntent()) {
                Label("Start Workout", systemImage: "timer")
            }
        }
        .displayName("Start Interval Workout")
        .description("Starts your selected Intervally workout.")
    }
}
