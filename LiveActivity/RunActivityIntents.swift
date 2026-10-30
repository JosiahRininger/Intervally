//
//  RunActivityIntents.swift
//  Intervally
//

import AppIntents

// The Live Activity's buttons: Pause or Resume, and Skip Interval, on the Lock Screen and in
// the expanded Dynamic Island.
//
// Compiled into the widget extension, which draws the buttons, and into the app, where the
// system runs them: a Live Activity's intents run in the app's process, launched in the
// background if it has to be, since that is where the run is. So each target has its own
// `perform()`: the app's takes the tap to the run (RunActivityIntents+Phone.swift), and the
// extension's is never called. Siri and Shortcuts are offered none of them: each means
// something only beside the run its activity shows.

struct PauseRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Workout"
    static let isDiscoverable = false
}

struct ResumeRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Workout"
    static let isDiscoverable = false
}

struct SkipIntervalIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip Interval"
    static let isDiscoverable = false

    /// The interval the button was drawn for, by its place in the plan. A tap that lands once
    /// that interval has run out skips nothing, rather than the one after it.
    @Parameter(title: "Interval")
    var phaseIndex: Int

    init() {}

    init(phaseIndex: Int) {
        self.phaseIndex = phaseIndex
    }
}
