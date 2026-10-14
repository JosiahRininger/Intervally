//
//  Motion.swift
//  Intervally
//

import SwiftUI

/// Every animation the app adds goes through here, so Reduce Motion is honoured in one
/// place: with it on, the change still happens, at once.
enum AppMotion {
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
