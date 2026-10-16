//
//  CueAudio.swift
//  IntervallyPhone
//

import AVFoundation
import CryptoKit
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
    /// Renders `phrases` ahead of time, in front and while nothing else plays, so the voice
    /// can say them away from the app, where the system voice may not render, and with music
    /// playing, which rendering would pause. Those already rendered are skipped.
    func prepare(_ phrases: [String])
    /// Stops whatever is still sounding.
    func silence()
    /// The run is over: the audio is handed back, and the volume buttons go back to the
    /// ringer.
    func handBackAudio()
    /// The media volume the cues play at, 0 to 1, whenever it changes while a run holds the
    /// audio.
    var onVolumeChange: ((Float) -> Void)? { get set }
    /// Takes the audio for a run and keeps it running until `handBackAudio`, so cues can
    /// sound away from the app. Called at Start, in front, where the audio may be started.
    func holdForRun()
    /// Whether the cues can sound, each time the audio is checked while a run holds it: false
    /// when the audio has stopped and can't be started again away from the app, so the run
    /// can mark the changes with notifications instead. Every time, not only when it changes:
    /// a run started while the last one's failure lasts has to hear of it too, and the run
    /// ignores what it already knows.
    var onHealthReport: ((Bool) -> Void)? { get set }
}

/// The real output: synthesized tones, the system voice and the Taptic Engine.
///
/// One audio engine plays every cue, and it keeps running from the run's first cue to its
/// end, silent between cues. That is what lets the cues sound with the app in the
/// background or the phone locked: iOS won't let an app start its audio from the
/// background, only keep it going. Played one by one as they came, each cue had to start
/// the audio afresh, and on a real iPhone every one after the app had been away a few
/// seconds failed to play, workout session or not, until the app was back in front
/// (diagnostics, 2026-10-14). Running, the engine also keeps the app going away from the
/// screen when there is no workout session to (Health declined, another app's workout).
///
/// The audio session is held for the whole run, mixed with whatever else is playing, so
/// the volume buttons set the cues' volume, and it is never let go and taken again until
/// the run is over. The cues play over music and podcasts, in front and away alike. 1.2's
/// builds up to 11 lowered the music for each cue with the app in front, which means
/// letting the session go and taking it again with other options: on a real iPhone that
/// paused Spotify instead of lowering it, lost the beep caught in the switch, and after a
/// few cues left Spotify pausing itself every half second until it was closed (2026-10-16).
/// The tones are made to carry over music (`ToneSynth`) without it.
///
/// The voice is rendered to audio first and played like a tone: spoken by the system
/// synthesizer directly, it takes the audio session over. Rendering at all pauses music
/// playing at the time, so every phrase is rendered ahead, while nothing else plays, and
/// kept on disk (`buffer(for:)`, `VoiceCache`).
///
/// Cues play with the Ring/Silent switch on silent too, as a workout timer has to: the
/// Sounds settings turn them off.
@MainActor
final class CueAudio: NSObject, CueOutput {
    private let session = AVAudioSession.sharedInstance()
    // Rebuilt from scratch if iOS resets its media services, which invalidates every node.
    private var engine = AVAudioEngine()
    private var tonePlayer = AVAudioPlayerNode()
    private var voicePlayer = AVAudioPlayerNode()
    /// Every cue's format: the tones' own rate, mono. Speech is resampled into it.
    private let format = AVAudioFormat(standardFormatWithSampleRate: Double(ToneSynth.sampleRate), channels: 1)!
    private var tones: [CueTone: AVAudioPCMBuffer] = [:]
    private let speaker = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "en-US")
    private let log = Logger(subsystem: "com.josiahrininger.intervally", category: "cues")
    private var isActive = false
    /// A cue has played since the audio was last handed back: a run, or the Sounds sample,
    /// holds it.
    private var isHeld = false
    private var volumeObservation: NSKeyValueObservation?
    private var observers: [any NSObjectProtocol] = []
    /// The phrase waiting for its tone to finish, if any.
    private var pendingPhrase: Task<Void, Never>?
    /// Each phrase, rendered once and kept for the run.
    private var phrases: [String: AVAudioPCMBuffer] = [:]

    var onVolumeChange: ((Float) -> Void)?
    var onHealthReport: ((Bool) -> Void)?
    /// What was last reported through `onHealthReport`.
    private var isHealthy = true
    /// Checks the engine every second while a run holds the audio, and restarts it if
    /// something stopped it without saying so.
    private var watchdog: Task<Void, Never>?
    /// The cues since the app was last in front, for the diagnostics.
    private var awayCues = CueTally()

    /// Phrases being rendered, so a phrase asked for twice is rendered once, and the last
    /// render asked for, which the next waits on: the synthesizer renders one at a time.
    private var rendering: [String: Task<Void, Never>] = [:]
    private var lastRender: Task<Void, Never>?

    /// Mixed with whatever else is playing, and nothing more: never lowering it, never
    /// interrupting it.
    nonisolated static let categoryOptions: AVAudioSession.CategoryOptions = [.mixWithOthers]

    /// Every phrase rendered on this iPhone, kept on disk, so each is rendered once ever.
    private let voiceCache: VoiceCache
    /// Phrases the voice skipped this run, noted once each.
    private var skippedPhrases: Set<String> = []

    init(voiceCache: VoiceCache = VoiceCache()) {
        self.voiceCache = voiceCache
        super.init()
        setCategory()
        buildEngine()
        for tone in CueTone.allCases {
            tones[tone] = Self.buffer(ToneSynth.samples(for: tone).map { Float($0) / Float(Int16.max) }, format: format)
        }
        let center = NotificationCenter.default
        // A call, Siri, or another app's audio that can't be mixed takes the audio away and
        // gives it back.
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            MainActor.assumeIsolated { self?.interrupted(began: type == .began) }
        })
        // iOS reset its audio: every node is gone. Build it all again and carry on.
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.mediaServicesReset() }
        })
        // Headphones or AirPods in or out, or the output otherwise changed: the engine stops.
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            MainActor.assumeIsolated { self?.routeChanged(reason) }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameActive() }
        })
        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            let volume = session.outputVolume
            Task { @MainActor in self?.onVolumeChange?(volume) }
        }
    }

    @discardableResult
    func play(_ tone: CueTone) -> TimeInterval {
        guard let buffer = tones[tone] else { return 0 }
        let duration = Double(buffer.frameLength) / format.sampleRate
        let wasHealthy = isHealthy
        noteCue("tone \(tone)", played: schedule(buffer, on: tonePlayer), wasHealthy: wasHealthy)
        return duration
    }

    func say(_ phrase: String, after delay: TimeInterval) {
        pendingPhrase?.cancel()
        voicePlayer.stop()
        let start = Date().addingTimeInterval(delay)
        pendingPhrase = Task { [weak self] in
            // Rendered while the tone plays; a phrase already heard this run is instant.
            guard let self, let buffer = await self.buffer(for: phrase), !Task.isCancelled else { return }
            let wait = start.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            let wasHealthy = self.isHealthy
            self.noteCue("voice \"\(phrase)\"", played: self.schedule(buffer, on: self.voicePlayer), wasHealthy: wasHealthy)
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

    /// Stops what is sounding. The engine runs on: the run isn't over.
    func silence() {
        pendingPhrase?.cancel()
        pendingPhrase = nil
        tonePlayer.stop()
        voicePlayer.stop()
    }

    func holdForRun() {
        _ = ensureRunning()
        startWatchdog()
    }

    func handBackAudio() {
        // A run that ended away from the app: its last stretch is noted now.
        if let line = awayCues.close() { RunDiagnostics.shared.note(line) }
        isHeld = false
        watchdog?.cancel()
        watchdog = nil
        isHealthy = true
        silence()
        phrases.removeAll()
        skippedPhrases.removeAll()
        engine.stop()
        guard isActive else { return }
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            log.notice("audio session not released: \(error.localizedDescription, privacy: .public)")
        }
        isActive = false
    }

    func prepare(_ phrases: [String]) {
        for phrase in phrases where self.phrases[phrase] == nil && rendering[phrase] == nil {
            Task { _ = await buffer(for: phrase) }
        }
    }

    // MARK: - Playing

    /// Plays `buffer` now on `node`, cutting off what it was playing. False if the engine
    /// isn't running and can't be started (in the background, after an interruption).
    private func schedule(_ buffer: AVAudioPCMBuffer, on node: AVAudioPlayerNode) -> Bool {
        startWatchdog()
        guard ensureRunning() else { return false }
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !node.isPlaying { node.play() }
        return true
    }

    /// The session held and the engine running, started if need be.
    private func ensureRunning() -> Bool {
        isHeld = true
        hold()
        guard !engine.isRunning else {
            report(healthy: true)
            return true
        }
        do {
            try engine.start()
            if UIApplication.shared.applicationState != .active {
                RunDiagnostics.shared.note("Audio: engine restarted away from the app")
            }
            report(healthy: true)
            return true
        } catch {
            // Noted once an outage: every try after it fails the same way.
            if isHealthy { RunDiagnostics.shared.note("Audio: engine didn't start: \(RunDiagnostics.describe(error))") }
            log.notice("cue engine didn't start: \(error.localizedDescription, privacy: .public)")
            report(healthy: false)
            return false
        }
    }

    private func report(healthy: Bool) {
        guard isHeld else { return }
        if healthy != isHealthy {
            isHealthy = healthy
            RunDiagnostics.shared.note(healthy ? "Audio: cues can sound again" : "Audio: CUES CAN'T SOUND; marking changes with notifications")
        }
        onHealthReport?(healthy)
    }

    /// How long the watchdog waits before it looks again: a second while the engine runs, and
    /// while it won't start, a second, then 5, then 15 for as long as that lasts. An outage
    /// nothing here can end, a phone call, costs a try every 15 seconds, not one a second.
    nonisolated static func watchdogDelay(afterFailures failures: Int) -> TimeInterval {
        [1, 5, 15][min(max(failures, 0), 2)]
    }

    private func startWatchdog() {
        guard watchdog == nil else { return }
        watchdog = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(CueAudio.watchdogDelay(afterFailures: failures)))
                guard let self, !Task.isCancelled, self.isHeld else { return }
                guard !self.engine.isRunning else {
                    failures = 0
                    continue
                }
                if failures == 0 { RunDiagnostics.shared.note("Audio: watchdog found the engine stopped") }
                failures = self.ensureRunning() ? 0 : failures + 1
            }
        }
    }

    /// Back in front, where the engine can always be started: one still stopped starts now,
    /// not at the watchdog's next try, and the cues while the app was away are noted.
    private func becameActive() {
        if let line = awayCues.close() { RunDiagnostics.shared.note(line) }
        if isHeld, !engine.isRunning { _ = ensureRunning() }
    }

    /// The engine and its two players, wired up: on launch, and again after a media reset.
    private func buildEngine() {
        engine = AVAudioEngine()
        tonePlayer = AVAudioPlayerNode()
        voicePlayer = AVAudioPlayerNode()
        engine.attach(tonePlayer)
        engine.attach(voicePlayer)
        engine.connect(tonePlayer, to: engine.mainMixerNode, format: format)
        engine.connect(voicePlayer, to: engine.mainMixerNode, format: format)
        // Running means running: the hardware is never let go between cues.
        engine.isAutoShutdownEnabled = false
        // Stopped by a change of output the route notification didn't cover.
        observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isHeld else { return }
                RunDiagnostics.shared.note("Audio: engine configuration changed; restarting")
                _ = self.ensureRunning()
            }
        })
    }

    private func mediaServicesReset() {
        RunDiagnostics.shared.note("Audio: media services were reset; rebuilding")
        isActive = false
        buildEngine()
        setCategory()
        if isHeld { _ = ensureRunning() }
    }

    private func routeChanged(_ reason: AVAudioSession.RouteChangeReason?) {
        guard isHeld else { return }
        let why: String = switch reason {
        case .newDeviceAvailable: "headphones or a speaker connected"
        case .oldDeviceUnavailable: "headphones or a speaker disconnected"
        default: "output changed"
        }
        RunDiagnostics.shared.note("Audio: \(why)")
        // The engine stops when its output goes; it may also carry on. Either way it is
        // running again before the next cue.
        _ = ensureRunning()
    }

    private func interrupted(began: Bool) {
        RunDiagnostics.shared.note("Audio: interrupted, \(began ? "began" : "ended")")
        if began {
            // The system has let the session go and stopped the engine.
            isActive = false
        } else if isHeld {
            // Back after a call: the engine picks up again, which works in front and, as a
            // resumption the system offers, often away from it too.
            _ = ensureRunning()
        }
    }

    // MARK: - Voice

    /// `phrase` as audio in the cues' format: from memory, from the disk, or rendered, one
    /// render at a time. Nil if it couldn't be had without interrupting other audio.
    ///
    /// The system voice renders in a process of its own, and on a real iPhone that pauses
    /// music playing at the time, even when it only renders and nothing is spoken: build 12
    /// rendered every phrase during Get Ready and stopped Josiah's Spotify for good
    /// (2026-10-16). So a phrase is rendered only while nothing else plays: ahead, at launch
    /// and back in front (`prepare`), and kept on disk. One not ready while music plays is
    /// skipped; the tone still marks the change.
    private func buffer(for phrase: String) async -> AVAudioPCMBuffer? {
        if let cached = phrases[phrase] { return cached }
        if let inFlight = rendering[phrase] {
            await inFlight.value
            return phrases[phrase]
        }
        if let samples = voiceCache.samples(for: phrase, voice: voiceID), let buffer = Self.buffer(samples, format: format) {
            phrases[phrase] = buffer
            return buffer
        }
        guard !session.isOtherAudioPlaying else {
            if isHeld, skippedPhrases.insert(phrase).inserted {
                RunDiagnostics.shared.note("Voice: \"\(phrase)\" skipped: not rendered yet, and other audio was playing")
            }
            return nil
        }
        let previous = lastRender
        // Kept in `phrases` as it lands; whoever waits reads it from there.
        let task = Task { [weak self] in
            await previous?.value
            guard let self, let samples = await self.render(phrase), let buffer = Self.buffer(samples, format: self.format) else { return }
            self.phrases[phrase] = buffer
            self.voiceCache.store(samples, for: phrase, voice: self.voiceID)
        }
        rendering[phrase] = task
        lastRender = task
        await task.value
        rendering[phrase] = nil
        return phrases[phrase]
    }

    /// Which voice renders, for the disk cache: a new system voice renders afresh.
    private var voiceID: String { voice?.identifier ?? "default" }

    /// `phrase` rendered by the system voice, at the cues' rate, without it ever touching
    /// the app's audio session.
    private func render(_ phrase: String) async -> [Float]? {
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        let pcm = await withCheckedContinuation { (continuation: CheckedContinuation<SpokenPCM, Never>) in
            let collector = SpokenPCM.Collector()
            speaker.write(utterance) { buffer in
                if collector.add(buffer) { continuation.resume(returning: collector.result) }
            }
        }
        let samples = pcm.resampled(to: format.sampleRate)
        guard !samples.isEmpty else {
            log.notice("phrase not rendered: \(phrase, privacy: .public)")
            if UIApplication.shared.applicationState != .active {
                RunDiagnostics.shared.note("Voice: \"\(phrase)\" not rendered away from the app")
            }
            return nil
        }
        return samples
    }

    nonisolated static func buffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    /// A cue, for the diagnostics, without a line for every one: a locked half hour is
    /// hundreds. Away from the app, cues are counted, and the count is noted once the app is
    /// back in front or the run is over. Noted in full: the first to play away, to show the
    /// audio carried on, and one that failed while the cues could last sound. In front, a
    /// cue that played was heard.
    private func noteCue(_ cue: String, played: Bool, wasHealthy: Bool) {
        let state = UIApplication.shared.applicationState
        let firstAway = state != .active && awayCues.count(played: played)
        guard played ? firstAway : wasHealthy else { return }
        let where_ = state == .background ? "in the background" : state == .inactive ? "while inactive" : "in front"
        RunDiagnostics.shared.note("Cue: \(cue) \(played ? "played" : "FAILED TO PLAY") \(where_), engine running \(engine.isRunning)")
    }

    // MARK: - Session

    private func setCategory() {
        do {
            try session.setCategory(.playback, mode: .default, options: Self.categoryOptions)
        } catch {
            log.error("audio session category refused: \(error.localizedDescription, privacy: .public)")
        }
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
            if isHealthy { RunDiagnostics.shared.note("Audio: session not activated: \(RunDiagnostics.describe(error))") }
            // A phone call, or another app holding audio that can't be mixed: the cue is lost,
            // the tap and the screen still mark the change. The next cue tries again.
            log.notice("audio session not activated: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Phrases the system voice rendered, kept on disk as samples at the cues' rate, so each is
/// rendered once on this iPhone, ever, rather than once a run (`CueAudio.buffer(for:)`).
struct VoiceCache: Sendable {
    let directory: URL?
    /// Bumped when the rendering changes, so old files are left behind.
    static let version = 1

    init(directory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("voice", isDirectory: true)) {
        self.directory = directory
    }

    /// The file for `phrase` in `voice`: named by a hash, as phrases are the user's own.
    func url(for phrase: String, voice: String) -> URL? {
        let digest = SHA256.hash(data: Data("\(Self.version)|\(voice)|\(phrase)".utf8))
        return directory?.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined() + ".f32")
    }

    func samples(for phrase: String, voice: String) -> [Float]? {
        guard let url = url(for: phrase, voice: voice), let data = try? Data(contentsOf: url),
              !data.isEmpty, data.count % MemoryLayout<Float>.size == 0 else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    func store(_ samples: [Float], for phrase: String, voice: String) {
        guard let url = url(for: phrase, voice: voice), !samples.isEmpty else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? samples.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: url, options: .atomic)
    }
}

/// The cues away from the app, counted between its times in front, so the diagnostics get
/// one line for the stretch rather than one a cue.
struct CueTally: Equatable {
    private(set) var played = 0
    private(set) var missed = 0

    /// Counts a cue: true for the first of the stretch to play, the one noted in full.
    mutating func count(played: Bool) -> Bool {
        if played { self.played += 1 } else { missed += 1 }
        return played && self.played == 1
    }

    /// The stretch in one line, with the count started again; nil if there was nothing.
    mutating func close() -> String? {
        defer { self = CueTally() }
        guard played + missed > 0 else { return nil }
        return "Cues away from the app: \(played) played, \(missed) didn't"
    }
}

/// A phrase the system voice rendered, as PCM, ready to play.
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

    /// The samples at `rate`, by linear interpolation: speech, so nothing finer is needed.
    func resampled(to rate: Double) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }
        guard rate != sampleRate else { return samples }
        let count = max(1, Int((Double(samples.count) * rate / sampleRate).rounded()))
        let step = sampleRate / rate
        return (0..<count).map { index in
            let position = Double(index) * step
            let lower = min(Int(position), samples.count - 1)
            let upper = min(lower + 1, samples.count - 1)
            let fraction = Float(position - Double(lower))
            return samples[lower] + (samples[upper] - samples[lower]) * fraction
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
