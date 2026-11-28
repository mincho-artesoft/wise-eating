import Foundation

/// The OpenAI Realtime WebSocket (wss://api.openai.com/v1/realtime), as GPT
/// Realtime Assistant and LingoVela use it, with an ephemeral client secret
/// minted by our backend. The session's instructions and tools were fixed by
/// the backend when it minted the secret; this socket never sends `session.update`.
@MainActor
final class AssistantRealtimeSocket {
    enum Event {
        case audioDelta(Data)
        case assistantTranscript(String)
        case personTranscript(String, usage: [String: Any]?, itemID: String)
        case speechStarted
        case responseDone(id: String, usage: [String: Any]?, functionCalls: [(callID: String, name: String, arguments: String)])
        case error(String)
        case closed
    }

    private var task: URLSessionWebSocketTask?
    private var receiving = false
    var onEvent: ((Event) -> Void)?

    func connect(model: String, clientSecret: String, safetyIdentifier: String?) {
        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")!
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(clientSecret)", forHTTPHeaderField: "Authorization")
        if let safetyIdentifier { request.setValue(safetyIdentifier, forHTTPHeaderField: "OpenAI-Safety-Identifier") }
        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        task.resume()
        receiving = true
        receive()
    }

    func close() {
        receiving = false
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    func appendAudio(_ pcm16: Data) {
        send(["type": "input_audio_buffer.append", "audio": pcm16.base64EncodedString()])
    }

    /// Returns a tool result to the model.
    func sendFunctionOutput(callID: String, output: String) {
        send(["type": "conversation.item.create", "item": ["type": "function_call_output", "call_id": callID, "output": output]])
    }

    /// A note from the app into the conversation (for example "the person confirmed").
    func sendAppNote(_ text: String) {
        send(["type": "conversation.item.create", "item": [
            "type": "message", "role": "user",
            "content": [["type": "input_text", "text": text]],
        ]])
    }

    func requestResponse() {
        send(["type": "response.create"])
    }

    func cancelResponse() {
        send(["type": "response.cancel"])
    }

    private func send(_ object: [String: Any]) {
        guard let task, let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text), completionHandler: Self.ignore)
    }

    private func receive() {
        guard let task, receiving else { return }
        let sink: @Sendable (String?, String?) -> Void = { [weak self] message, failure in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let failure {
                    if self.receiving { self.onEvent?(.error(failure)) }
                    self.receiving = false
                    self.onEvent?(.closed)
                    return
                }
                if let message { self.handle(message) }
                self.receive()
            }
        }
        task.receive(completionHandler: Self.receiver(sink))
    }

    // URLSession calls these off the main thread, so they are built outside the main actor.
    nonisolated private static func receiver(
        _ sink: @escaping @Sendable (String?, String?) -> Void
    ) -> @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void {
        { result in
            switch result {
            case let .success(.string(text)): sink(text, nil)
            case let .success(.data(data)): sink(String(data: data, encoding: .utf8), nil)
            case .success: sink(nil, nil)
            case let .failure(error): sink(nil, error.localizedDescription)
            }
        }
    }

    nonisolated private static let ignore: @Sendable ((any Error)?) -> Void = { _ in }

    private func handle(_ text: String) {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let type = object["type"] as? String else { return }
        switch type {
        case "response.output_audio.delta", "response.audio.delta":
            if let delta = object["delta"] as? String, let data = Data(base64Encoded: delta) { onEvent?(.audioDelta(data)) }
        case "response.output_audio_transcript.done", "response.audio_transcript.done":
            if let transcript = object["transcript"] as? String { onEvent?(.assistantTranscript(transcript)) }
        case "conversation.item.input_audio_transcription.completed":
            onEvent?(.personTranscript(
                object["transcript"] as? String ?? "",
                usage: object["usage"] as? [String: Any],
                itemID: object["item_id"] as? String ?? UUID().uuidString))
        case "input_audio_buffer.speech_started":
            onEvent?(.speechStarted)
        case "response.done":
            let response = object["response"] as? [String: Any] ?? [:]
            let output = response["output"] as? [[String: Any]] ?? []
            let calls = output.compactMap { item -> (callID: String, name: String, arguments: String)? in
                guard item["type"] as? String == "function_call",
                      let callID = item["call_id"] as? String, let name = item["name"] as? String else { return nil }
                return (callID, name, item["arguments"] as? String ?? "{}")
            }
            onEvent?(.responseDone(id: response["id"] as? String ?? UUID().uuidString, usage: response["usage"] as? [String: Any], functionCalls: calls))
        case "error":
            let message = (object["error"] as? [String: Any])?["message"] as? String ?? String(localized: "Voice error")
            onEvent?(.error(message))
        default:
            break
        }
    }
}
