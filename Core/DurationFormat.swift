//
//  DurationFormat.swift
//  Intervally
//

import Foundation

enum DurationFormat {
    /// "45s", "1:30", "12:05" — compact enough for a watch row.
    static func clock(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    /// "45", "1:30" — for a value captioned with its unit ("seconds" / "minutes"), where
    /// "45s seconds" would say it twice.
    static func bare(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)" : clock(seconds)
    }

    /// A spoken-friendly form for VoiceOver: "1 minute 30 seconds".
    static func spoken(_ seconds: Int) -> String {
        let style = Duration.UnitsFormatStyle(
            allowedUnits: seconds < 60 ? [.seconds] : [.minutes, .seconds],
            width: .wide
        )
        return Duration.seconds(seconds).formatted(style)
    }

    /// m:ss, or h:mm:ss from an hour up — what `Text(timerInterval:)` shows, so a paused
    /// countdown and a running one read the same. Never "27s": switching between "27s" and
    /// "0:27" changed the rendered size by more than half.
    static func timer(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        if clamped >= 3600 {
            return String(format: "%d:%02d:%02d", clamped / 3600, clamped % 3600 / 60, clamped % 60)
        }
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    /// "Off", "45s", "5:00" — a warmup or cooldown on its tile. Zero switches the phase
    /// off, so it reads "Off" rather than a "0s" phase that never happens.
    static func bookend(_ seconds: Int) -> String {
        seconds == 0 ? "Off" : clock(seconds)
    }

    /// "Off", "45", "5:00" — the bookend editor, where the unit is captioned beneath.
    static func bookendEditor(_ seconds: Int) -> String {
        seconds == 0 ? "Off" : bare(seconds)
    }

    /// "Off", "5 minutes" — what VoiceOver says for a bookend.
    static func bookendSpoken(_ seconds: Int) -> String {
        seconds == 0 ? "Off" : spoken(seconds)
    }

    /// Uses Foundation's automatic grammar agreement rather than an English `s`, so the
    /// plural rule comes from the locale once a String Catalog is added.
    static func rounds(_ count: Int) -> String {
        String(AttributedString(localized: "^[\(count) round](inflect: true)").characters)
    }
}
