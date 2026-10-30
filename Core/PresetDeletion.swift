//
//  PresetDeletion.swift
//  Intervally
//

import Foundation

/// Deleting a preset, which both devices ask about first, in the same words. A delete
/// reaches the other device too, and nothing brings it back, so no swipe or menu deletes
/// one on its own: each only asks.
enum PresetDeletion {
    /// "Delete “Tabata”?", on iPhone, iPad and watch alike.
    static func title(for name: String) -> String {
        "Delete “\(name)”?"
    }
}
