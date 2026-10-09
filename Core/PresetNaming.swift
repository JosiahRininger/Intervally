//
//  PresetNaming.swift
//  Intervally
//

import Foundation

/// Names for duplicated presets, the same on the watch and the iPhone.
enum PresetNaming {
    /// "Tabata" → "Tabata 2"; "Tabata 2" → "Tabata 3", counting past any name already taken,
    /// so duplicating a duplicate does not pile up suffixes.
    static func uniqueName(after name: String, among taken: [String]) -> String {
        var stem = name
        var number = 2
        if let space = name.lastIndex(of: " "),
           space > name.startIndex,
           let suffix = Int(name[name.index(after: space)...]) {
            stem = String(name[..<space])
            number = suffix + 1
        }
        let names = Set(taken)
        while names.contains("\(stem) \(number)") { number += 1 }
        return "\(stem) \(number)"
    }
}
