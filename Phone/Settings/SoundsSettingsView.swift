//
//  SoundsSettingsView.swift
//  IntervallyPhone
//

import MediaPlayer
import SwiftUI

/// What Settings' Sounds row says under its title.
enum SoundsRow {
    static let title = "Sounds & Voice"
    static let systemImage = "speaker.wave.2"

    static func subtitle(_ settings: CueSettings) -> String {
        switch (settings.beeps, settings.voice) {
        case (true, true): "Beeps and voice coach"
        case (true, false): "Beeps"
        case (false, true): "Voice coach"
        case (false, false): "Off"
        }
    }
}

/// How a run on iPhone sounds: beeps at each change, the 3-2-1 before it, the voice coach
/// with Pro, and whether the screen stays on. Pushed inside Settings.
struct SoundsSettingsView: View {
    /// Opens the paywall, pushed by Settings: a free user turned the voice coach on.
    var openPaywall: () -> Void = {}

    @Environment(ProStore.self) private var pro
    @Environment(PhoneRun.self) private var run

    @AppStorage(CueSettings.Key.beeps, store: SharedDefaults.suite) private var beeps = true
    @AppStorage(CueSettings.Key.countdown, store: SharedDefaults.suite) private var countdown = true
    @AppStorage(CueSettings.Key.voice, store: SharedDefaults.suite) private var voice = true
    @AppStorage(CueSettings.Key.keepAwake, store: SharedDefaults.suite) private var keepAwake = true

    var body: some View {
        List {
            Section {
                Toggle("Beeps", isOn: $beeps)
                Toggle("3, 2, 1 Countdown", isOn: $countdown)
            } header: {
                Text("Interval Changes")
            } footer: {
                Text("A tone marks each change, higher for work and lower for rest. With the countdown on, three ticks come before it.")
            }

            Section {
                Toggle(isOn: voiceBinding) {
                    HStack(spacing: 8) {
                        Text("Voice Coach")
                        if !pro.isPro { ProBadge() }
                    }
                }
                .accessibilityHint(pro.isPro ? "" : "Opens Intervally Pro")
            } footer: {
                Text("Calls out each interval as it starts, by the name you gave it: Work, Rest, Last round.")
            }

            Section {
                SystemVolumeSlider()
                    .frame(height: 34)
                Button {
                    run.playSample()
                } label: {
                    Label("Play a Sample", systemImage: "play.circle")
                }
            } header: {
                Text("Volume")
            } footer: {
                Text("Cues play at your media volume, the one your music uses, even with the Ring/Silent switch on silent, and right over your music or podcast, which keeps playing. During a workout the volume buttons set it too.")
            }

            Section {
                Toggle("Keep Screen On", isOn: $keepAwake)
            } footer: {
                Text("While a workout is on screen, so the countdown stays in view.")
            }
        }
        .readableList()
        .appCanvas()
        .navigationTitle(SoundsRow.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// On without Pro opens the paywall instead, and the switch stays off; the saved choice
    /// is only ever the user's own.
    private var voiceBinding: Binding<Bool> {
        Binding {
            voice && pro.isPro
        } set: { on in
            if on && !pro.isPro {
                openPaywall()
            } else {
                voice = on
            }
        }
    }
}

/// The system's own volume slider: the media volume the cues play at, with the output
/// picker for headphones and speakers beside it.
private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {}
}
