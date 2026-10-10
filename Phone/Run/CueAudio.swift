//
//  CueAudio.swift
//  IntervallyPhone
//

import AVFoundation
import UIKit
import os

/// Where the iPhone's cues come out: the speaker or headphones, the voice, the Taptic
/// Engine. A protocol so `PhoneCuePlayer`'s tests can see what it asked for.
@MainActor
protocol CueOutput: AnyObject {
    /// Plays `tone` now and returns how long it lasts.
    @discardableResult func play(_ tone: CueTone) -> TimeInterval
    /// Speaks `phrase` once `delay` has passed, so it follows the tone instead of talking
    /// over it.
    func say(_ phrase: String, after delay: TimeInterval)
    func tap(_ tap: CueTap)
    /// Stops whatever is still sounding.
    func silence()
    /// The run is over: the audio is handed back, and the volume buttons go back to the
    /// ringer.
    func handBackAudio()
    /// The media volume the cues play at, 0 to 1, whenever it changes while a run holds the
    /// audio.
    var onVolumeChange: ((Float) -> Void)? { get set }
}

/// The real output: synthesized tones, the system voice and the Taptic Engine.
///
/// The audio session is held for the whole run, mixed with whatever else is playing, so
/// music and podcasts carry on underneath. Held, it makes the volume buttons set the volume
/// the cues play at. Switched on only for each cue, as it first was, the buttons set the
/// ringer between cues instead, and on an iPhone whose media volume was low the cues were
/// all but silent however far the volume was turned up. Cues play with the Ring/Silent
/// switch on silent too, as a workout timer has to: the Sounds settings turn them off.
@MainActor
final class CueAudio: NSObject, CueOutput {
    private let session = AVAudioSession.sharedInstance()
    private var players: [CueTone: AVAudioPlayer] = [:]
    private let speaker = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "en-US")
    private let log = Logger(subsystem: "com.josiahrininger.intervally", category: "cues")
    private var isActive = false
    private var volumeObservation: NSKeyValueObservation?

    var onVolumeChange: ((Float) -> Void)?

    override init() {
        super.init()
        do {
            // Mixed, never ducking: held for a whole run, a duck would quieten someone's
            // music for all of it, and a podcast would stop for the whole workout.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } catch {
            log.error("audio session category refused: \(error.localizedDescription, privacy: .public)")
        }
        for tone in CueTone.allCases {
            if let player = try? AVAudioPlayer(data: ToneSynth.wav(for: tone)) {
                player.prepareToPlay()
                players[tone] = player
            }
        }
        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            let volume = session.outputVolume
            Task { @MainActor in self?.onVolumeChange?(volume) }
        }
    }

    @discardableResult
    func play(_ tone: CueTone) -> TimeInterval {
        guard let player = players[tone] else { return 0 }
        hold()
        player.currentTime = 0
        player.play()
        return player.duration
    }

    func say(_ phrase: String, after delay: TimeInterval) {
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.preUtteranceDelay = delay
        hold()
        speaker.speak(utterance)
    }

    func tap(_ tap: CueTap) {
        // iOS plays haptics only for the app in front; asking from the background is a no-op.
        guard UIApplication.shared.applicationState == .active else { return }
        switch tap {
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .heavy: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func silence() {
        players.values.forEach { $0.stop() }
        speaker.stopSpeaking(at: .immediate)
    }

    func handBackAudio() {
        silence()
        guard isActive else { return }
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            log.notice("audio session not released: \(error.localizedDescription, privacy: .public)")
        }
        isActive = false
    }

    // MARK: - Session

    /// Takes the audio for the run, once: from then on the volume buttons set the cues'
    /// volume, and the current volume is reported so the run screen can say when it is low.
    private func hold() {
        guard !isActive else { return }
        do {
            try session.setActive(true)
            isActive = true
            onVolumeChange?(session.outputVolume)
        } catch {
            // A phone call, or another app holding audio that can't be mixed: the cue is lost,
            // the tap and the screen still mark the change. The next cue tries again.
            log.notice("audio session not activated: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// The cue tones, made in code: short sine notes with a fast attack and a soft tail, plus a
/// little of the octave for edge, so they cut through music without sounding like an alarm.
enum ToneSynth {
    static let sampleRate = 44_100

    /// (frequency in Hz, seconds) for each note, played back to back.
    static func notes(for tone: CueTone) -> [(Double, Double)] {
        switch tone {
        case .tick: [(1_046.5, 0.09)]
        case .go: [(880, 0.11), (1_318.5, 0.26)]
        case .ease: [(783.99, 0.11), (523.25, 0.26)]
        case .ready: [(659.25, 0.22)]
        case .finish: [(783.99, 0.12), (987.77, 0.12), (1_174.66, 0.12), (1_567.98, 0.42)]
        }
    }

    static func duration(of tone: CueTone) -> TimeInterval {
        notes(for: tone).reduce(0) { $0 + $1.1 }
    }

    /// 16-bit mono PCM samples.
    static func samples(for tone: CueTone, amplitude: Double = 0.85) -> [Int16] {
        var samples: [Int16] = []
        for (frequency, seconds) in notes(for: tone) {
            let count = Int(seconds * Double(sampleRate))
            let attack = Double(sampleRate) * 0.004
            for index in 0..<count {
                let t = Double(index) / Double(sampleRate)
                let rise = min(1, Double(index) / attack)
                let fall = pow(1 - Double(index) / Double(count), 1.6)
                let wave = sin(2 * .pi * frequency * t) + 0.18 * sin(4 * .pi * frequency * t)
                let value = wave / 1.18 * rise * fall * amplitude
                samples.append(Int16(max(-1, min(1, value)) * Double(Int16.max)))
            }
        }
        return samples
    }

    /// A complete WAV file, for `AVAudioPlayer(data:)`.
    static func wav(for tone: CueTone) -> Data {
        let pcm = samples(for: tone)
        let dataSize = UInt32(pcm.count * 2)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(dataSize)
        pcm.forEach { append($0) }
        return data
    }
}
