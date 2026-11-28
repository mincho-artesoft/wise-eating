import Foundation

/// The paid engine for typed requests and photos: the reasoning model through
/// our backend, in a tool loop. The backend returns `function_call` items, the
/// app runs them through the toolbox and sends the outputs back, until the
/// model answers in words. Writes still only become cards to confirm.
@MainActor
final class OpenAIEngine: AssistantEngine {
    let kind: AssistantEngineKind = .openAI
    let canReadImages = true

    private let backend: AssistantBackendClient
    /// The conversation so far, in Responses API items (kept on the device).
    private var history: [[String: Any]] = []
    private let maxToolRounds = 6

    init(backend: AssistantBackendClient = .shared) {
        self.backend = backend
    }

    func respond(to turn: AssistantTurn, toolbox: AssistantToolbox) async throws -> AssistantReply {
        let purpose: String
        if turn.imageJPEG != nil {
            purpose = "photo"
        } else {
            let lower = turn.text.lowercased()
            let heavy = ["plan", "regimen", "recipe", "week", "days", "режим", "план", "рецепт", "седмиц", "дни"]
            purpose = heavy.contains(where: { lower.contains($0) }) ? "plan" : "assistant"
        }
        let text = turn.text.isEmpty ? String(localized: "Please read the dietary restrictions in this photo.") : turn.text
        history.append(["type": "message", "role": "user", "content": text])
        trimHistory()

        // The photo goes with every round of this turn (the backend keeps nothing),
        // and is not kept in the conversation afterwards.
        let image = turn.imageJPEG
        for _ in 0..<maxToolRounds {
            let response = try await backend.reasoning(purpose: purpose, input: history, imageJPEG: image)
            history.append(contentsOf: response.output)
            let calls = response.output.filter { $0["type"] as? String == "function_call" }
            if calls.isEmpty {
                return AssistantReply(text: response.text)
            }
            for call in calls {
                let name = call["name"] as? String ?? ""
                let arguments = call["arguments"] as? String ?? "{}"
                let output = await toolbox.call(name, arguments: arguments)
                history.append(["type": "function_call_output", "call_id": call["call_id"] as? String ?? "", "output": output])
            }
        }
        return AssistantReply(text: String(localized: "I could not finish that in one go. Please try a shorter request."))
    }

    /// Keeps the request small: the last 40 items, never starting on a tool output.
    private func trimHistory() {
        guard history.count > 40 else { return }
        history.removeFirst(history.count - 40)
        while let first = history.first, (first["type"] as? String) != "message" {
            history.removeFirst()
        }
    }
}
