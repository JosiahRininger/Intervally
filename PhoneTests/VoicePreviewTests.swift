//
//  VoicePreviewTests.swift
//  IntervallyPhoneTests
//

import Foundation
import Testing
@testable import IntervallyPhone

/// Hear the Coach, the voice coach's sample for someone deciding on Pro. With music playing it
/// plays only what is already rendered, as a run does, and says when that leaves nothing; it
/// hands the audio back once it has played. Music is a stand-in (`isOtherAudioPlaying`): the
/// real voice would render a phrase the code wrongly asked for, and leave it on disk.
@Suite("Hear the Coach")
@MainActor
struct VoicePreviewTests {
    /// The audio's notes, kept nowhere.
    private let log = RunDiagnostics(url: nil, write: { _, _ in }, schedule: { _, _ in })

    /// A voice cache in a folder of its own, for one test.
    private func makeCache() -> VoiceCache {
        VoiceCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString)", isDirectory: true))
    }

    private func remove(_ cache: VoiceCache) {
        if let directory = cache.directory { try? FileManager.default.removeItem(at: directory) }
    }

    @Test("With music playing, the sample plays the phrases already rendered, in order, and renders none")
    func usesCacheOnlyWithMusic() async throws {
        let cache = makeCache()
        defer { remove(cache) }
        let audio = CueAudio(voiceCache: cache, diagnostics: log, isOtherAudioPlaying: { true })
        // Rendered on an earlier run: a work change and the finish.
        let rendered = [Float](repeating: 0.1, count: 480)
        cache.store(rendered, for: "Work", voice: audio.voiceID)
        cache.store(rendered, for: "Workout complete", voice: audio.voiceID)

        let sample = await audio.preview(PhoneCuePlayer.coachSample)
        audio.handBackAudio()

        guard case .played(let phrases, let seconds) = sample else {
            Issue.record("Nothing played: \(sample)")
            return
        }
        #expect(phrases == ["Work", "Workout complete"])
        // Both phrases and the pause between them, as one cue, so the release waits for it all.
        let expected = 960 / Double(ToneSynth.sampleRate) + 0.6
        #expect(abs(seconds - expected) < 0.01, "\(seconds) s")
        #expect(sample.note == nil, "Something played: nothing to say")
        for phrase in ["Rest", "Last round"] {
            #expect(cache.samples(for: phrase, voice: audio.voiceID) == nil, "\"\(phrase)\" was rendered over the music")
        }
    }

    @Test("With music playing and nothing rendered, the sample asks for the music to be paused, and renders nothing")
    func musicPlayingUncachedShowsHint() async {
        let cache = makeCache()
        defer { remove(cache) }
        let audio = CueAudio(voiceCache: cache, diagnostics: log, isOtherAudioPlaying: { true })

        let sample = await audio.preview(PhoneCuePlayer.coachSample)
        audio.handBackAudio()

        #expect(sample == .needsQuiet)
        #expect(sample.note == "Pause your music to hear the coach.")
        for phrase in PhoneCuePlayer.coachSample {
            #expect(cache.samples(for: phrase, voice: audio.voiceID) == nil, "\"\(phrase)\" was rendered over the music")
        }
    }

    @Test("The sample hands the audio back once it has played, unless a run has started; one that played nothing took none")
    func previewReleasesAudio() async throws {
        let output = FakeCueOutput()
        let defaults = makeTestDefaults()
        // Free, with the coach switched off: the sample is for deciding on it.
        defaults.set(false, forKey: CueSettings.Key.voice)
        let player = PhoneCuePlayer(output: output, pro: FakePro(isPro: false), defaults: defaults)

        let sample = await player.previewCoach()
        #expect(output.previewed == [["Work", "Rest", "Last round", "Workout complete"]])
        // A run's own words, so each one rendered serves both.
        let twoRounds = IntervalPlan(workout: IntervalWorkout(prepareSeconds: 0, rounds: 2))
        #expect(PhoneCuePlayer.coachSample == PhoneCuePlayer.phrases(for: twoRounds.phases, totalRounds: 2))
        #expect(sample == .played(PhoneCuePlayer.coachSample, seconds: 0.05))
        #expect(!output.calls.contains(.release), "Not over its last word")
        #expect(await waitUntil { output.calls.last == .release })
        #expect(output.calls.filter { $0 == .release }.count == 1)

        output.reset()
        player.runIsActive = { true }
        _ = await player.previewCoach()
        try await Task.sleep(for: .milliseconds(800))
        #expect(!output.calls.contains(.release), "A run started meanwhile keeps the audio")

        player.runIsActive = { false }
        output.previewAnswer = .needsQuiet
        _ = await player.previewCoach()
        try await Task.sleep(for: .milliseconds(800))
        #expect(!output.calls.contains(.release), "Nothing played, so nothing was taken")
    }
}
