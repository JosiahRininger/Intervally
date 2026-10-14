//
//  PhaseLabel.swift
//  Intervally
//

import Foundation

/// What a preset calls one of its phases, and the figure beside it: "Run" with a runner for
/// Work, "Walk" with a walker for Rest. Shown wherever the phase is named: the editor's
/// tile, the run screen on both devices, the Lock Screen, the voice coach and History.
struct PhaseLabel: Codable, Equatable, Hashable, Sendable {
    var name: String
    var symbol: PhaseSymbol

    /// Long enough for "Recovery" or "Jump Rope", short enough for the top of the watch's
    /// ring on a 40mm watch, where the word may shrink to `PhaseWord.smallestScale`.
    static let maxNameLength = 10

    /// The name as it will be shown: trimmed, cut to `maxNameLength`, nil when nothing is
    /// left or `WordFilter` turns it away, which keeps the phase's own name.
    static func cleaned(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cut = String(trimmed.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
        return WordFilter.allows(cut) ? cut : nil
    }

    /// The label as shown and spoken: a name the filter turns away, saved by a device without
    /// it, gives way to the phase's own; its figure stays.
    func shown(for kind: IntervalPhase.Kind) -> PhaseLabel {
        WordFilter.allows(name) ? self : PhaseLabel(name: kind.title, symbol: symbol)
    }
}

/// The figures a phase can wear: the built-in phases' own, and the kinds of effort and
/// recovery intervals are built from.
enum PhaseSymbol: String, Codable, CaseIterable, Identifiable, Sendable {
    case bolt, wind, hourglass, sunrise, sunset
    case run, walk, sprint, easy, cycle, row, lift, core, jumpRope, boxing, yoga, stretch, breathe, flame, heart

    var id: Self { self }

    var systemName: String {
        switch self {
        case .bolt: "bolt.fill"
        case .wind: "wind"
        case .hourglass: "hourglass"
        case .sunrise: "sunrise.fill"
        case .sunset: "sunset.fill"
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .sprint: "hare.fill"
        case .easy: "tortoise.fill"
        case .cycle: "figure.outdoor.cycle"
        case .row: "figure.rower"
        case .lift: "dumbbell.fill"
        case .core: "figure.core.training"
        case .jumpRope: "figure.jumprope"
        case .boxing: "figure.boxing"
        case .yoga: "figure.yoga"
        case .flame: "flame.fill"
        case .stretch: "figure.cooldown"
        case .breathe: "lungs.fill"
        case .heart: "heart.fill"
        }
    }

    /// What VoiceOver calls it in the picker.
    var spokenName: String {
        switch self {
        case .bolt: "Lightning bolt"
        case .wind: "Wind"
        case .hourglass: "Hourglass"
        case .sunrise: "Sunrise"
        case .sunset: "Sunset"
        case .run: "Runner"
        case .walk: "Walker"
        case .sprint: "Hare"
        case .easy: "Tortoise"
        case .cycle: "Cyclist"
        case .row: "Rower"
        case .lift: "Dumbbell"
        case .core: "Core"
        case .jumpRope: "Jump rope"
        case .boxing: "Boxer"
        case .yoga: "Yoga"
        case .flame: "Flame"
        case .stretch: "Stretch"
        case .breathe: "Lungs"
        case .heart: "Heart"
        }
    }
}

extension IntervalPhase.Kind {
    /// The figure a phase wears until its preset gives it another.
    var defaultSymbol: PhaseSymbol {
        switch self {
        case .prepare: .hourglass
        case .warmup: .sunrise
        case .work: .bolt
        case .rest: .wind
        case .cooldown: .sunset
        }
    }
}

extension IntervalWorkout {
    /// The phase's label: the preset's own, or the phase's name and figure.
    func label(for kind: IntervalPhase.Kind) -> PhaseLabel {
        phaseLabels?[kind.rawValue]?.shown(for: kind) ?? PhaseLabel(name: kind.title, symbol: kind.defaultSymbol)
    }

    /// Whether the preset renamed the phase or changed its figure.
    func hasCustomLabel(for kind: IntervalPhase.Kind) -> Bool {
        phaseLabels?[kind.rawValue] != nil
    }

    /// Sets the phase's label; a name and figure that are the phase's own clear it. The
    /// labels are never set back to nil once touched, only emptied: nil is what a version
    /// that predates them sends, which a merge must not take as "cleared" (`PresetRecord`).
    mutating func setLabel(_ label: PhaseLabel?, for kind: IntervalPhase.Kind) {
        var labels = phaseLabels ?? [:]
        if let label, let name = PhaseLabel.cleaned(label.name),
           name != kind.title || label.symbol != kind.defaultSymbol {
            labels[kind.rawValue] = PhaseLabel(name: name, symbol: label.symbol)
        } else if let label, PhaseLabel.cleaned(label.name) == nil, label.symbol != kind.defaultSymbol {
            labels[kind.rawValue] = PhaseLabel(name: kind.title, symbol: label.symbol)
        } else {
            labels[kind.rawValue] = nil
        }
        phaseLabels = labels
    }
}
