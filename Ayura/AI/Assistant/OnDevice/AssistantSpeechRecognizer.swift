import AVFoundation
import Foundation
import Speech

/// Apple's speech recognition in the app's language, on the device when the
/// language supports it. Text only; the audio is not kept.
@MainActor
final class AssistantSpeechRecognizer: ObservableObject {
    enum State: Equatable {
        case idle, listening, denied, unavailable
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript: String = ""

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    /// The language the app's interface is shown in.
    static var appLocale: Locale {
        let id = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        return Locale(identifier: id)
    }

    func start() async {
        transcript = ""
        guard await Self.authorize() else { state = .denied; return }
        let recognizer = SFSpeechRecognizer(locale: Self.appLocale) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else { state = .unavailable; return }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.taskHint = .dictation
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(appendingTo: request))
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            state = .unavailable
            return
        }

        state = .listening
        let sink: @Sendable (String?, Bool) -> Void = { [weak self] text, done in
            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = text }
                if done { self.stop() }
            }
        }
        task = recognizer.recognitionTask(with: request, resultHandler: Self.handler(sink))
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if state == .listening { state = .idle }
    }

    // The audio and recognition callbacks run off the main thread, so they are
    // built outside the main actor.
    nonisolated private static func tap(appendingTo request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    nonisolated private static func handler(
        _ sink: @escaping @Sendable (String?, Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            sink(result?.bestTranscription.formattedString, (result?.isFinal ?? false) || error != nil)
        }
    }

    nonisolated private static func speechAuthorized() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    private static func authorize() async -> Bool {
        guard await speechAuthorized() else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
