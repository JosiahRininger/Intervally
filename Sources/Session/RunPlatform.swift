//
//  RunPlatform.swift
//  Intervally
//

import Foundation

/// The watch's side of the shared run: what keeps it executing without a workout session,
/// and how a pause or a resume feels.
enum RunPlatform {
    @MainActor
    static func makeRuntime() -> any RuntimeSessioning {
        ExtendedRuntimeController()
    }

    @MainActor
    static func play(cue: TransportCue) {
        Haptics.play(cue: cue)
    }
}
