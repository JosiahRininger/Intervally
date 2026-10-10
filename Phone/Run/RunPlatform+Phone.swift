//
//  RunPlatform+Phone.swift
//  IntervallyPhone
//

import Foundation

/// The iPhone's side of the shared run.
///
/// iOS 26 runs a real `HKWorkoutSession` on iPhone, which keeps the app executing with the
/// screen locked, exactly as on the watch. There is no second tier: nothing like the watch's
/// extended runtime session exists here. So when Health is declined the run counts in the
/// foreground and the notification backstop marks each change once the app is away.
enum RunPlatform {
    @MainActor
    static func makeRuntime() -> any RuntimeSessioning {
        ForegroundRuntime()
    }

    /// Nothing by default: the app's `PhoneCuePlayer` plays pause and resume.
    @MainActor
    static func play(cue: TransportCue) {}
}

/// The fallback tier on iPhone: the app itself, while it is in front. Starting it holds
/// nothing, so it is never taken away either.
@MainActor
final class ForegroundRuntime: RuntimeSessioning {
    var onInvalidate: (() -> Void)?
    func start() {}
    func stop() {}
}
