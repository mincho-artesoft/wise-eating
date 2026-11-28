import Foundation

/// A Realtime voice conversation with the OpenAI engine: microphone to the
/// socket, speech back, function calls run through the same toolbox, usage
/// reported to our backend, which stops the session when credits run out.
@MainActor
final class AssistantVoiceSession: ObservableObject {
    enum State: Equatable { case idle, connecting, live, ended(String?) }

    @Published private(set) var state: State = .idle
    @Published private(set) var credits: Int?

    private let backend: AssistantBackendClient
    private let socket = AssistantRealtimeSocket()
    private let audio = AssistantRealtimeAudio()
    private weak var session: AssistantSession?
    private var sessionID: String?
    private var endTask: Task<Void, Never>?

    init(backend: AssistantBackendClient = .shared) {
        self.backend = backend
    }

    /// - Parameter purpose: "assistant", or "constitution" for the onboarding questionnaire.
    func start(purpose: String, session: AssistantSession) async {
        guard state != .connecting, state != .live else { return }
        self.session = session
        state = .connecting
        do {
            let secret = try await backend.clientSecret(purpose: purpose)
            sessionID = secret.sessionId
            credits = secret.wallet.credits
            socket.onEvent = { [weak self] event in self?.handle(event) }
            socket.connect(model: secret.model, clientSecret: secret.clientSecret, safetyIdentifier: secret.safetyIdentifier)
            let socket = self.socket
            let sink: @Sendable (Data) -> Void = { data in
                Task { @MainActor in socket.appendAudio(data) }
            }
            try audio.start(onAudio: sink)
            audio.onInterruption = { [weak self] began in
                if began { Task { await self?.stop(reason: String(localized: "Voice paused by the system.")) } }
            }
            state = .live
            // The backend's limit; the session is ended here as well.
            endTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Double(secret.maxMinutes * 60)))
                await self?.stop(reason: String(localized: "The voice session reached its time limit."))
            }
        } catch {
            state = .ended(error.localizedDescription)
            await stopTransport()
        }
    }

    func stop(reason: String? = nil) async {
        guard state == .live || state == .connecting else { return }
        state = .ended(reason)
        await stopTransport()
    }

    private func stopTransport() async {
        endTask?.cancel()
        endTask = nil
        audio.stop()
        socket.close()
        if let id = sessionID {
            sessionID = nil
            await backend.endSession(id)
            credits = backend.wallet?.credits
        }
    }

    private func handle(_ event: AssistantRealtimeSocket.Event) {
        switch event {
        case let .audioDelta(data):
            audio.play(pcm16: data)
        case .speechStarted:
            // The person interrupts: drop what is queued; the server cancels the reply.
            audio.flushPlayback()
        case let .assistantTranscript(text):
            session?.appendExternal(.assistant, text)
        case let .personTranscript(text, usage, itemID):
            if !text.isEmpty { session?.appendExternal(.person, text) }
            if let usage { report(eventID: itemID, kind: "transcription", usage: usage) }
            confirmIfSpokenYes(text)
        case let .responseDone(id, usage, calls):
            if let usage { report(eventID: id, kind: "response", usage: usage) }
            guard !calls.isEmpty, let toolbox = session?.toolbox else { return }
            Task { @MainActor in
                for call in calls {
                    let output = await toolbox.call(call.name, arguments: call.arguments)
                    self.socket.sendFunctionOutput(callID: call.callID, output: output)
                }
                self.session?.sync()
                self.socket.requestResponse()
            }
        case let .error(message):
            session?.appendExternal(.notice, message)
        case .closed:
            Task { await self.stop() }
        }
    }

    /// "Yes" / "да" with a card on screen confirms it, as a tap would.
    private func confirmIfSpokenYes(_ text: String) {
        guard let session, let newest = session.pending.last else { return }
        let normalized = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        guard AssistantSession.confirmWords.contains(normalized) else { return }
        Task { @MainActor in
            await session.confirm(newest.id)
            let note = session.messages.last?.text ?? ""
            self.socket.sendAppNote("(App: the person confirmed on screen. Result: \(note))")
        }
    }

    private func report(eventID: String, kind: String, usage: [String: Any]) {
        guard let sessionID else { return }
        Task { @MainActor in
            guard let result = try? await self.backend.reportUsage(sessionID: sessionID, eventID: eventID, kind: kind, usage: usage) else { return }
            self.credits = result.wallet.credits
            if result.insufficientCredits || result.ended {
                await self.stop(reason: String(localized: "You are out of AI credits."))
            }
        }
    }
}
