//
//  SeededGenerator.swift
//  Intervally test support
//

import Foundation

// Compiled into both test bundles: the sync tests and the timer engine's fuzz draw their
// cases from it.

/// SplitMix64: the same sequence for the same seed, so a failing trial replays exactly.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func uuid() -> UUID {
        let bytes = (next(), next())
        return withUnsafeBytes(of: bytes) { UUID(uuid: $0.load(as: uuid_t.self)) }
    }
}
