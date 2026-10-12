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
    /// over it. The newest phrase wins: anything still waiting, or being spoken, is dropped,
    /// so eight quick Skips say only where they landed, not "Work, Rest" eight times over.
    func say(_ phrase: String, after delay: TimeInterval)
    func tap(_ tap: CueTap)
    /// Stops whatever is still sounding.
    func silence()
    /// The run is over: the audio is handed back, and the volume buttons go back to the
    /// ringer.
    func handBackAudio()
    /// Whether music or a podcast playing underneath is lowered while a cue sounds.
    var lowersOtherAudio: Bool { get set }
    /// The media volume the cues play at, 0 to 1, whenever it changes while a run holds the
    /// audio.
    var onVolumeChange: ((Float) -> Void)? { get set }
}

/// The real output: synthesized tones, the system voice and the Taptic Engine.
///
/// The audio session is held for the whole run, mixed with whatever else is playing. Held,
/// it makes the volume buttons set the volume the cues play at; switched on only for each
/// cue, as it first was, the buttons set the ringer between cues instead, and on an iPhone
/// whose media volume was low the cues were all but silent.
///
/// With music or a podcast playing, each cue lowers it ("ducks" it) for as long as the cue
/// sounds, as Seconds, Runkeeper and the like do, and the music comes back up straight
/// after: mixed in at full volume, a beep was lost under a loud song. Cues close together,
/// the 3-2-1 and the change after it, share one dip rather than pumping the music each
/// second. A podcast pauses for the cue and picks up again.
///
/// The voice is rendered to audio first and played like a tone. Spoken by the system
/// synthesizer directly, it takes the audio session over and never lets it go, so the music
/// would have stayed lowered for the rest of the workout.
///
/// Cues play with the Ring/Silent switch on silent too, as a workout timer has to: the
/// Sounds settings turn them off.
@MainActor
final class CueAudio: NSObject, CueOutput {
    private let session = AVAudioSession.sharedInstance()
    private var players: [CueTone: AVAudioPlayer] = [:]
    private let speaker = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "en-US")
    private let log = Logger(subsystem: "com.josiahrininger.intervally", category: "cues")
    private var isActive = false
    private var volumeObservation: NSKeyValueObservation?
    /// The phrase waiting for its tone to finish, if any.
    private var pendingPhrase: Task<Void, Never>?
    /// Each phrase, rendered once and kept for the run.
    private var phrases: [String: AVAudioPlayer] = [:]
    private var speaking: AVAudioPlayer?

    var lowersOtherAudio = true
    var onVolumeChange: ((Float) -> Void)?

    /// Whether other audio is lowered right now, and until when.
    private var isDucking = false
    private var duckUntil = Date.distantPast
    private var restoreTask: Task<Void, Never>?
    /// How long the music stays down after a cue ends: enough to carry the 3-2-1 into the
    /// change and the word after it as one dip.
    static let duckTail: TimeInterval = 0.8

    override init() {
        super.init()
        setCategory(ducking: false)
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
        prepareSession(for: player.duration)
        player.currentTime = 0
        player.play()
        return player.duration
    }

    func say(_ phrase: String, after delay: TimeInterval) {
        pendingPhrase?.cancel()
        speaking?.stop()
        hold()
        let start = Date().addingTimeInterval(delay)
        pendingPhrase = Task { [weak self] in
            // Rendered while the tone plays; a phrase already heard this run is instant.
            guard let self, let player = await self.player(for: phrase), !Task.isCancelled else { return }
            let wait = start.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            self.speaking?.stop()
            self.prepareSession(for: player.duration)
            player.currentTime = 0
            player.play()
            self.speaking = player
        }
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
        pendingPhrase?.cancel()
        pendingPhrase = nil
        players.values.forEach { $0.stop() }
        speaking?.stop()
        speaking = nil
    }

    func handBackAudio() {
        silence()
        restoreTask?.cancel()
        restoreTask = nil
        isDucking = false
        phrases.removeAll()
        guard isActive else { return }
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            log.notice("audio session not released: \(error.localizedDescription, privacy: .public)")
        }
        isActive = false
        setCategory(ducking: false)
    }

    // MARK: - Voice

    /// `phrase` as playable audio, rendered by the system voice without it ever touching the
    /// audio session. Nil if the voice produced nothing.
    private func player(for phrase: String) async -> AVAudioPlayer? {
        if let cached = phrases[phrase] { return cached }
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        let pcm = await withCheckedContinuation { (continuation: CheckedContinuation<SpokenPCM, Never>) in
            let collector = SpokenPCM.Collector()
            speaker.write(utterance) { buffer in
                if collector.add(buffer) { continuation.resume(returning: collector.result) }
            }
        }
        guard let data = pcm.wav(), let player = try? AVAudioPlayer(data: data) else {
            log.notice("phrase not rendered: \(phrase, privacy: .public)")
            return nil
        }
        player.prepareToPlay()
        phrases[phrase] = player
        return player
    }

    // MARK: - Session

    private func setCategory(ducking: Bool) {
        do {
            // Mixed always; lowering others only for a cue with something playing under it.
            let options: AVAudioSession.CategoryOptions = ducking
                ? [.mixWithOthers, .duckOthers, .interruptSpokenAudioAndMixWithOthers]
                : [.mixWithOthers]
            try session.setCategory(.playback, mode: .default, options: options)
        } catch {
            log.error("audio session category refused: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Ready for a cue of `duration`: held as always, and with music or a podcast playing,
    /// lowering it until the cue, and any cue close behind it, is done.
    private func prepareSession(for duration: TimeInterval) {
        guard lowersOtherAudio, isDucking || session.isOtherAudioPlaying else {
            hold()
            return
        }
        duckUntil = max(duckUntil, Date().addingTimeInterval(duration + Self.duckTail))
        if !isDucking { startDucking() }
        scheduleRestore()
    }

    /// Ducking takes hold when the session is activated with it, so the held session is let
    /// go and taken again. Nothing of ours is sounding at that moment: a cue starts after.
    private func startDucking() {
        if isActive {
            try? session.setActive(false)
            isActive = false
        }
        setCategory(ducking: true)
        do {
            try session.setActive(true)
            isActive = true
            isDucking = true
        } catch {
            log.notice("could not lower other audio: \(error.localizedDescription, privacy: .public)")
            setCategory(ducking: false)
            hold()
        }
    }

    private func scheduleRestore() {
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let wait = self.duckUntil.timeIntervalSinceNow
                guard wait <= 0 else {
                    try? await Task.sleep(for: .seconds(wait))
                    continue
                }
                self.stopDucking()
                return
            }
        }
    }

    /// The music comes back up, and the session is held again, unlowered, for the volume
    /// buttons and the next cue.
    private func stopDucking() {
        guard isDucking else { return }
        isDucking = false
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            log.notice("other audio not restored: \(error.localizedDescription, privacy: .public)")
        }
        isActive = false
        setCategory(ducking: false)
        hold()
    }

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

/// A phrase the system voice rendered, as PCM, ready to become a WAV for `AVAudioPlayer`.
struct SpokenPCM: Sendable {
    var sampleRate: Double = 22_050
    var samples: [Float] = []

    /// Gathers the synthesizer's buffers on its own queue; an empty buffer ends the phrase.
    final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var pcm = SpokenPCM()
        private var done = false

        /// Adds `buffer`; true once, when the phrase is complete.
        func add(_ buffer: AVAudioBuffer) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !done else { return false }
            guard let pcmBuffer = buffer as? AVAudioPCMBuffer, pcmBuffer.frameLength > 0 else {
                done = true
                return true
            }
            pcm.sampleRate = pcmBuffer.format.sampleRate
            let frames = Int(pcmBuffer.frameLength)
            if let floats = pcmBuffer.floatChannelData?[0] {
                pcm.samples.append(contentsOf: UnsafeBufferPointer(start: floats, count: frames))
            } else if let ints = pcmBuffer.int16ChannelData?[0] {
                pcm.samples.append(contentsOf: UnsafeBufferPointer(start: ints, count: frames).map { Float($0) / Float(Int16.max) })
            }
            return false
        }

        var result: SpokenPCM {
            lock.lock(); defer { lock.unlock() }
            return pcm
        }
    }

    /// 16-bit mono WAV, or nil when nothing was spoken.
    func wav() -> Data? {
        guard !samples.isEmpty else { return nil }
        let pcm = samples.map { Int16(max(-1, min(1, $0)) * Float(Int16.max)) }
        return WAV.mono16(pcm, sampleRate: Int(sampleRate))
    }
}

/// The cue tones, made in code: short notes with a fast attack and a soft tail, each with
/// three harmonics above it. A pure sine is easily lost under music; the harmonics put energy
/// across 1 to 4 kHz, where hearing is keenest and a song leaves the most room, so the same
/// peak level carries much further (Patterson's guidelines for warning sounds, CAA 82017).
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

    /// Each harmonic's strength, the fundamental first: bright, but still a note.
    static let partials: [Double] = [1, 0.5, 0.3, 0.18]

    /// One note's waveform at phase `x` (radians of the fundamental).
    static func wave(at x: Double) -> Double {
        partials.enumerated().reduce(0) { sum, partial in sum + partial.element * sin(Double(partial.offset + 1) * x) }
    }

    /// The waveform's own peak, so a note is scaled to `amplitude` exactly and never clips.
    static let wavePeak: Double = {
        (0..<2_000).map { abs(wave(at: 2 * .pi * Double($0) / 2_000)) }.max() ?? 1
    }()

    /// 16-bit mono PCM samples.
    static func samples(for tone: CueTone, amplitude: Double = 0.9) -> [Int16] {
        var samples: [Int16] = []
        for (frequency, seconds) in notes(for: tone) {
            let count = Int(seconds * Double(sampleRate))
            // Fast enough to mark the instant, slow enough not to click.
            let attack = Double(sampleRate) * 0.008
            for index in 0..<count {
                let t = Double(index) / Double(sampleRate)
                let rise = min(1, Double(index) / attack)
                // The tail begins once the attack is done, so even the short tick reaches
                // `amplitude` instead of fading on the way up.
                let fall = pow(1 - max(0, Double(index) - attack) / (Double(count) - attack), 1.6)
                let value = wave(at: 2 * .pi * frequency * t) / wavePeak * rise * fall * amplitude
                samples.append(Int16(max(-1, min(1, value)) * Double(Int16.max)))
            }
        }
        return samples
    }

    /// A complete WAV file, for `AVAudioPlayer(data:)`.
    static func wav(for tone: CueTone) -> Data {
        WAV.mono16(samples(for: tone), sampleRate: sampleRate)
    }
}

/// 16-bit mono PCM as a WAV file.
enum WAV {
    static func mono16(_ pcm: [Int16], sampleRate: Int) -> Data {
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
