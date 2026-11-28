import AVFoundation
import Foundation

/// Microphone in and speech out for the Realtime voice session, on one
/// AVAudioEngine with voice processing (echo cancellation), as in GPT Realtime
/// Assistant's `RealtimeDuplexAudioEngine`. Audio is PCM16 mono at 24 kHz.
@MainActor
final class AssistantRealtimeAudio {
    enum AudioError: LocalizedError {
        case microphoneUnavailable
        var errorDescription: String? { String(localized: "The microphone is not available.") }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: false)!
    private var tapInstalled = false
    private var observers: [NSObjectProtocol] = []
    /// Called when the system interrupts audio (a call, Siri) and when it ends.
    var onInterruption: ((Bool) -> Void)?

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
    }

    func start(onAudio: @escaping @Sendable (Data) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setPreferredSampleRate(48_000)
        try? session.setPreferredInputNumberOfChannels(1)
        try session.setActive(true)

        let input = engine.inputNode
        if !input.isVoiceProcessingEnabled {
            try input.setVoiceProcessingEnabled(true)
        }
        input.isVoiceProcessingAGCEnabled = true
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioError.microphoneUnavailable }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2_400, format: format, block: Self.tap(onAudio))
        tapInstalled = true

        engine.prepare()
        try engine.start()
        player.play()
        observe()
    }

    func stop() {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Plays one `response.output_audio.delta` chunk.
    func play(pcm16 data: Data) {
        let frames = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        data.withUnsafeBytes { raw in
            guard let src = raw.bindMemory(to: Int16.self).baseAddress, let dst = buffer.int16ChannelData?.pointee else { return }
            dst.update(from: src, count: Int(frames))
        }
        if engine.isRunning, !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// Barge-in: the person started speaking, so the queued reply is dropped.
    func flushPlayback() {
        player.stop()
        if engine.isRunning { player.play() }
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = raw == AVAudioSession.InterruptionType.began.rawValue
            MainActor.assumeIsolated { self?.onInterruption?(began) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onInterruption?(true) }
        })
    }

    nonisolated private static func tap(_ onAudio: @escaping @Sendable (Data) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            if let data = convert(buffer) { onAudio(data) }
        }
    }

    /// Any input format to PCM16 mono 24 kHz (from `RealtimePCM16AudioConverter`).
    nonisolated static func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let out = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: buffer.format, to: out) else { return nil }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * out.sampleRate / buffer.format.sampleRate) + 32
        guard let result = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: capacity) else { return nil }
        var provided = false
        var error: NSError?
        converter.convert(to: result, error: &error) { _, status in
            if provided { status.pointee = .noDataNow; return nil }
            provided = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = result.int16ChannelData?.pointee, result.frameLength > 0 else { return nil }
        return Data(bytes: channel, count: Int(result.frameLength) * MemoryLayout<Int16>.size)
    }
}
