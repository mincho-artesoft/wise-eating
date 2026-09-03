import AVFoundation
import Combine
import MediaPlayer
import SwiftUI

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
    private var voiceMode: PracticeVoiceMode = .recorded
    private var ambiencePlayer: AVAudioPlayer?
    private var narrationPlayer: AVAudioPlayer?
    private var tickerTask: Task<Void, Never>?
    private var playbackStartedAt: Date?
    private var elapsedBeforeStart: Double = 0
    private var narrationEndsAt: Double = 0
    private var audioSessionIsPrepared = false

    private static let narrationFadeInDuration: TimeInterval = 0.22
    private static let narrationCrossfadeDuration: TimeInterval = 0.08
    private static let ambienceFadeInDuration: TimeInterval = 1.0

    func prepareForPlayback() throws {
        guard !audioSessionIsPrepared else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.mixWithOthers]
        )
        try session.setActive(true)
        audioSessionIsPrepared = true
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
        ambiencePlayer?.pause()
        narrationPlayer?.pause()
        updateNowPlaying()
    }

    func resume() {
        guard state == .paused else { return }
        playbackStartedAt = Date()
        state = .playing
        if let narrationPlayer,
           narrationPlayer.currentTime < narrationPlayer.duration {
            narrationPlayer.play()
        }
        ambiencePlayer?.play()
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

        retireNarrationPlayer()
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
        ambiencePlayer?.volume = 0
        narrationPlayer?.volume = 0
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
            let targetVolume = Float(plan.ambienceVolume)
            player.volume = 0
            player.numberOfLoops = plan.ambienceLoops ? -1 : 0
            player.prepareToPlay()
            player.play()
            player.setVolume(
                targetVolume,
                fadeDuration: Self.ambienceFadeInDuration
            )
            ambiencePlayer = player
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
        var spokenDuration = max(3.2, Double(wordCount) / 95 * 60)
        retireNarrationPlayer()

        if voiceMode == .recorded {
            if let narrationURL = cue.recordedAudioURL {
                do {
                    let player = try AVAudioPlayer(contentsOf: narrationURL)
                    player.volume = 0
                    player.numberOfLoops = 0
                    player.prepareToPlay()
                    spokenDuration = player.duration > 0
                        ? player.duration
                        : (cue.recordedDurationSeconds ?? spokenDuration)
                    narrationPlayer = player
                    if state == .playing {
                        player.play()
                        player.setVolume(
                            1,
                            fadeDuration: Self.narrationFadeInDuration
                        )
                    }
                } catch {
                    print("⚠️ Recorded practice cue could not start: \(error)")
                }
            } else {
                print("⚠️ Recorded practice cue is missing: \(cue.id)")
            }
        }
        narrationEndsAt = cue.atSeconds + spokenDuration

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

    private func retireNarrationPlayer() {
        guard let outgoingPlayer = narrationPlayer else { return }
        narrationPlayer = nil

        guard outgoingPlayer.isPlaying else {
            outgoingPlayer.stop()
            return
        }

        outgoingPlayer.setVolume(
            0,
            fadeDuration: Self.narrationCrossfadeDuration
        )
        Task { @MainActor in
            try? await Task.sleep(
                for: .seconds(Self.narrationCrossfadeDuration)
            )
            outgoingPlayer.stop()
        }
    }

    private func finish() {
        tickerTask?.cancel()
        tickerTask = nil
        narrationPlayer?.volume = 0
        narrationPlayer?.stop()
        if plan?.sleepSafe != true {
            ambiencePlayer?.volume = 0
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
