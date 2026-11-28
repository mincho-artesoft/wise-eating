import Foundation
import SwiftData

/// One conversation with the assistant: messages, the engine, the pending
/// writes waiting for the person's confirmation and the last undo.
@MainActor
final class AssistantSession: ObservableObject {
    struct Message: Identifiable, Equatable {
        enum Role: Equatable { case person, assistant, notice }
        let id = UUID()
        var role: Role
        var text: String
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var pending: [AssistantPendingAction] = []
    @Published private(set) var lastUndo: AssistantUndo?
    @Published private(set) var isWorking = false
    @Published private(set) var engineKind: AssistantEngineKind

    let toolbox: AssistantToolbox
    private(set) var engine: AssistantEngine

    init(toolbox: AssistantToolbox, engine: AssistantEngine) {
        self.toolbox = toolbox
        self.engine = engine
        self.engineKind = engine.kind
    }

    convenience init(profile: Profile, container: ModelContainer) {
        let data = AssistantLiveDataSource(profile: profile, container: container)
        self.init(toolbox: AssistantToolbox(data: data), engine: OnDeviceEngine())
    }

    func use(_ engine: AssistantEngine) {
        self.engine = engine
        engineKind = engine.kind
    }

    /// Words that confirm the newest pending action when spoken or typed alone.
    static let confirmWords: Set<String> = ["yes", "yes please", "confirm", "ok", "okay", "do it", "save it",
                                            "да", "добре", "потвърди", "потвърждавам", "запиши"]
    static let cancelWords: Set<String> = ["no", "cancel", "don't", "не", "откажи", "отказ"]

    func send(_ text: String, imageJPEG: Data? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || imageJPEG != nil else { return }
        messages.append(.init(role: .person, text: trimmed.isEmpty ? String(localized: "Photo") : trimmed))

        let normalized = trimmed.lowercased().trimmingCharacters(in: .punctuationCharacters)
        if imageJPEG == nil, let newest = pending.last {
            if Self.confirmWords.contains(normalized) {
                await confirm(newest.id)
                return
            }
            if Self.cancelWords.contains(normalized) {
                discard(newest.id)
                messages.append(.init(role: .assistant, text: String(localized: "Cancelled. Nothing was changed.")))
                return
            }
        }

        isWorking = true
        defer { isWorking = false; sync() }
        do {
            let reply = try await engine.respond(to: AssistantTurn(text: trimmed, imageJPEG: imageJPEG), toolbox: toolbox)
            if !reply.text.isEmpty { messages.append(.init(role: .assistant, text: reply.text)) }
        } catch {
            messages.append(.init(role: .notice, text: error.localizedDescription))
        }
    }

    /// Adds a line the engine produced outside a turn (voice transcripts).
    func appendExternal(_ role: Message.Role, _ text: String) {
        messages.append(.init(role: role, text: text))
        sync()
    }

    func confirm(_ id: UUID) async {
        isWorking = true
        defer { isWorking = false; sync() }
        guard let result = await toolbox.confirm(id) else { return }
        messages.append(.init(role: .notice, text: result.message))
    }

    func discard(_ id: UUID) {
        toolbox.discard(id)
        sync()
    }

    func updateGrams(actionID: UUID, foodID: UUID, grams: Double) async {
        await toolbox.updateGrams(actionID: actionID, foodID: foodID, grams: grams)
        sync()
    }

    func removeConstraint(actionID: UUID, constraintID: UUID) {
        toolbox.removeConstraint(actionID: actionID, constraintID: constraintID)
        sync()
    }

    func undoLast() async {
        guard let undo = lastUndo else { return }
        let ok = await toolbox.undo(undo)
        messages.append(.init(role: .notice, text: ok
            ? String(localized: "Undone. The meal is as it was.")
            : String(localized: "It could not be undone.")))
        sync()
    }

    func sync() {
        pending = toolbox.pending
        lastUndo = toolbox.lastUndo
    }
}
