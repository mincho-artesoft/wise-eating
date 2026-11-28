import Foundation

enum AssistantEngineKind: String, Sendable {
    /// Apple's on-device model (free), with a deterministic fallback.
    case onDevice
    /// OpenAI through our backend (paid with credits).
    case openAI
}

struct AssistantTurn: Sendable {
    var text: String
    /// JPEG data the person chose to send, with consent; OpenAI engine only.
    var imageJPEG: Data?
}

struct AssistantReply: Equatable, Sendable {
    var text: String
}

/// One brain behind the assistant. Both engines act only through the same
/// `AssistantToolbox`, so what they can do is identical.
@MainActor
protocol AssistantEngine: AnyObject {
    var kind: AssistantEngineKind { get }
    var canReadImages: Bool { get }
    func respond(to turn: AssistantTurn, toolbox: AssistantToolbox) async throws -> AssistantReply
}

enum AssistantEngineError: LocalizedError {
    case imagesNeedOpenAI
    case outOfCredits
    case backendUnavailable
    case server(String)

    var errorDescription: String? {
        switch self {
        case .imagesNeedOpenAI:
            String(localized: "The on-device assistant cannot read photos or documents. Switch to the OpenAI assistant to send a photo.")
        case .outOfCredits:
            String(localized: "You are out of AI credits.")
        case .backendUnavailable:
            String(localized: "The online assistant is not reachable right now.")
        case let .server(message):
            message
        }
    }
}
