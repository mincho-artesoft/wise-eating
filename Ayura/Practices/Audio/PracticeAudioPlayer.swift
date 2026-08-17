import AVFoundation
import Combine
import MediaPlayer
import SwiftUI
import UIKit

@MainActor
final class PracticeAudioPlayer: NSObject, ObservableObject {
    enum PlaybackState: Equatable {
        case idle
        case playing
        case paused
        case finished
    }

    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var currentCue: PracticeAudioCue?
    @Published private(set) var currentCueIndex: Int = 0
    @Published private(set) var isHolding = false
    @Published private(set) var elapsed: Double = 0

    private var plan: PracticeAudioPlan?
    private var voiceMode: PracticeVoiceMode = .deviceTTS
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var ambiencePlayer: AVAudioPlayer?
    private var narrationPlayer: AVAudioPlayer?
    private var tickerTask: Task<Void, Never>?
    private var playbackStartedAt: Date?
    private var elapsedBeforeStart: Double = 0
    private var narrationEndsAt: Double = 0

    func prepareForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.mixWithOthers]
        )
        try session.setActive(true)
    }

    func play(
        _ plan: PracticeAudioPlan,
        voiceMode: PracticeVoiceMode = PracticeAudioDefaults.voiceMode
    ) {
        stop(clearNowPlaying: false)
        self.plan = plan
        self.voiceMode = voiceMode
        elapsed = 0
        elapsedBeforeStart = 0
        currentCueIndex = 0
        isHolding = false

        do {
            try prepareForPlayback()
            try startAudioBeds(plan: plan)
        } catch {
            print("⚠️ Practice audio session could not start: \(error)")
        }

        state = .playing
        playbackStartedAt = Date()
        if let first = plan.cues.first {
            showCue(first, at: 0)
        }
        updateNowPlaying()
        startTicker()
    }

    func pause() {
        guard state == .playing else { return }
        captureElapsed()
        state = .paused
        speechSynthesizer.pauseSpeaking(at: .immediate)
        ambiencePlayer?.pause()
        narrationPlayer?.pause()
        updateNowPlaying()
    }

    func resume() {
        guard state == .paused else { return }
        playbackStartedAt = Date()
        state = .playing
        if speechSynthesizer.isPaused {
            speechSynthesizer.continueSpeaking()
        }
        ambiencePlayer?.play()
        narrationPlayer?.play()
        updateNowPlaying()
    }

    func togglePlayPause() {
        state == .playing ? pause() : resume()
    }

    func advance() {
        guard let plan, state == .playing || state == .paused else { return }
        let nextIndex = currentCueIndex + 1
        guard plan.cues.indices.contains(nextIndex) else {
            finish()
            return
        }

        speechSynthesizer.stopSpeaking(at: .immediate)
        let nextCue = plan.cues[nextIndex]
        elapsedBeforeStart = nextCue.atSeconds
        elapsed = nextCue.atSeconds
        if state == .playing { playbackStartedAt = Date() }
        showCue(nextCue, at: nextIndex)
        updateNowPlaying()
    }

    func stop(clearNowPlaying: Bool = true) {
        tickerTask?.cancel()
        tickerTask = nil
        speechSynthesizer.stopSpeaking(at: .immediate)
        ambiencePlayer?.stop()
        narrationPlayer?.stop()
        ambiencePlayer = nil
        narrationPlayer = nil
        playbackStartedAt = nil
        elapsedBeforeStart = 0
        elapsed = 0
        currentCue = nil
        currentCueIndex = 0
        isHolding = false
        plan = nil
        state = .idle
        if clearNowPlaying {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    private func startAudioBeds(plan: PracticeAudioPlan) throws {
        if let ambienceURL = plan.ambienceURL {
            let player = try AVAudioPlayer(contentsOf: ambienceURL)
            player.volume = Float(plan.ambienceVolume)
            player.numberOfLoops = plan.ambienceLoops ? -1 : 0
            player.prepareToPlay()
            player.play()
            ambiencePlayer = player
        }

        if voiceMode == .recorded, let narrationURL = plan.recordedNarrationURL {
            let player = try AVAudioPlayer(contentsOf: narrationURL)
            player.numberOfLoops = 0
            player.prepareToPlay()
            player.play()
            narrationPlayer = player
        }
    }

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    private func tick() {
        guard state == .playing, let plan else { return }
        captureElapsed(keepClockRunning: true)

        if elapsed >= plan.totalDuration {
            finish()
            return
        }

        if let nextIndex = plan.cues.indices.last(where: {
            plan.cues[$0].atSeconds <= elapsed
        }), nextIndex != currentCueIndex {
            showCue(plan.cues[nextIndex], at: nextIndex)
        }

        if elapsed >= narrationEndsAt, !isHolding {
            withAnimation(.easeOut(duration: 0.8)) {
                isHolding = true
            }
        }
    }

    private func showCue(_ cue: PracticeAudioCue, at index: Int) {
        currentCueIndex = index
        currentCue = cue
        isHolding = false

        let wordCount = cue.text.split(whereSeparator: \.isWhitespace).count
        let spokenDuration = max(3.2, Double(wordCount) / 95 * 60)
        narrationEndsAt = cue.atSeconds + spokenDuration

        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        let shouldUseTTS = voiceMode == .deviceTTS
            || (voiceMode == .recorded && plan?.recordedNarrationURL == nil)
        if shouldUseTTS {
            speechSynthesizer.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(string: cue.text)
            utterance.rate = 0.38
            utterance.pitchMultiplier = 0.92
            utterance.volume = 0.92
            utterance.preUtteranceDelay = 0.1
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            speechSynthesizer.speak(utterance)
        }
    }

    private func captureElapsed(keepClockRunning: Bool = false) {
        guard let playbackStartedAt else { return }
        let updated = elapsedBeforeStart + Date().timeIntervalSince(playbackStartedAt)
        elapsed = updated
        if !keepClockRunning {
            elapsedBeforeStart = updated
            self.playbackStartedAt = nil
        }
    }

    private func finish() {
        tickerTask?.cancel()
        tickerTask = nil
        speechSynthesizer.stopSpeaking(at: .immediate)
        narrationPlayer?.stop()
        if plan?.sleepSafe != true {
            ambiencePlayer?.stop()
        }
        state = .finished
        currentCue = nil
        isHolding = true
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard let plan else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: plan.title,
            MPMediaItemPropertyAlbumTitle: "Ayura Practices",
            MPMediaItemPropertyPlaybackDuration: plan.totalDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1 : 0,
        ]
        if let cue = currentCue {
            info[MPMediaItemPropertyArtist] = cue.text
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
