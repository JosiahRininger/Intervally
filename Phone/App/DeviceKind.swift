//
//  DeviceKind.swift
//  IntervallyPhone
//

import UIKit

/// The device the app runs on, for the words that name it: "this iPhone" or "this iPad".
/// iPad never has an Apple Watch, whatever a stand-in for one reports, so copy that names a
/// watch names it only on iPhone.
enum DeviceKind: Equatable, Sendable {
    case phone, pad

    @MainActor static var current: DeviceKind {
        UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
    }
}
