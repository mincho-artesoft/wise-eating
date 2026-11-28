import Foundation
import SwiftUI

/// The onboarding bonus: the online assistant asks the twelve constitution
/// questions by voice, paid by the one-time welcome credits. It is offered only
/// when the backend is reachable and the welcome credits are still available
/// for this device; otherwise nothing in onboarding changes.
@MainActor
final class AssistantOnboardingOffer: ObservableObject {
    @Published private(set) var isOffered = false

    func check() async {
        guard FeatureFlags.voiceAssistant, AssistantBackendClient.isOpenAIAvailable else {
            isOffered = false
            return
        }
        do {
            try await AssistantBackendClient.shared.refreshWallet()
            isOffered = AssistantBackendClient.shared.grantState == .available
        } catch {
            isOffered = false
        }
    }

    /// Set when the person asked, during onboarding, for a first day plan; the
    /// assistant offers it once the profile exists.
    static var firstPlanRequested: Bool {
        get { UserDefaults.standard.bool(forKey: "assistant.firstPlanRequested") }
        set { UserDefaults.standard.set(newValue, forKey: "assistant.firstPlanRequested") }
    }
}

/// The tools' view during onboarding: there is no profile yet, so the only
/// write that does anything is filling the questionnaire's answers.
@MainActor
final class AssistantOnboardingDataSource: AssistantDataSource {
    let onAnswers: ([AyurvedaDosha]) -> Void
    let profile: AssistantProfileSnapshot

    init(onAnswers: @escaping ([AyurvedaDosha]) -> Void) {
        self.onAnswers = onAnswers
        self.profile = AssistantProfileSnapshot(
            profileID: UUID(), age: 0, sex: "", heightCm: 0, weightKg: 0, allergens: [],
            constitutionLabel: nil, constitution: nil, priorityNutrients: [], mealNames: [])
    }

    var canGeneratePlans: Bool { true }
    func searchFoods(_ query: String, limit: Int) async -> [CompactFoodItem] { [] }
    func food(id: UUID) async -> CompactFoodItem? { nil }
    func food(named name: String) async -> CompactFoodItem? { nil }
    func meals(on day: Date) async -> [AssistantMealRecord] { [] }
    func save(_ meal: AssistantMealRecord, on day: Date) async -> AssistantMealRecord? { nil }
    func constraints() -> [DietaryConstraint] { [] }
    func mergeConstraints(_ constraints: [DietaryConstraint]) {}
    /// The model never writes a constitution: these are the answers to the
    /// same twelve questions, scored by the same code as the questionnaire.
    func saveConstitution(answers: [AyurvedaDosha]) { onAnswers(answers) }
    func startRecipe(named name: String) -> Bool { false }
    func startFood(named name: String) -> Bool { false }
    func startMealPlan(days: Int, notes: [String]) -> Bool {
        AssistantOnboardingOffer.firstPlanRequested = true
        return true
    }
    func findPractices(_ query: String, limit: Int) -> [AssistantPracticeHit] { [] }
    func findPoses(_ query: String, limit: Int) -> [AssistantPoseHit] { [] }
}

/// "Talk it through": claims the welcome credits once, then the voice
/// conversation over the twelve questions.
struct AssistantVoiceConstitutionView: View {
    let onComplete: (AyurvedaConstitutionDraft) -> Void
    let onCancel: () -> Void

    @StateObject private var voice = AssistantVoiceSession()
    @StateObject private var holder = Holder()
    @State private var status: String?
    @State private var started = false
    @ObservedObject private var effectManager = EffectManager.shared

    @MainActor
    final class Holder: ObservableObject {
        var session: AssistantSession?
        var answers: [AyurvedaDosha]?
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let session = holder.session {
                    AssistantVoiceTranscript(session: session)
                }
                if let status {
                    Text(status).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                switch voice.state {
                case .connecting:
                    ProgressView()
                case .live:
                    Label { Text("Listening. Answer in your own words.") } icon: { Image(systemName: "waveform") }
                        .foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
                Text("This conversation uses OpenAI and your free welcome credits. A wellness tool, not medical advice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle(Text("Talk it through"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        Task { await voice.stop() }
                        onCancel()
                    } label: { Text("Answer on screen instead") }
                }
            }
        }
        .tint(effectManager.currentGlobalAccentColor)
        .task { await begin() }
        .onDisappear { Task { await voice.stop() } }
        .onChange(of: voice.state) { _, new in
            if case let .ended(reason) = new, holder.answers == nil {
                status = reason ?? String(localized: "The conversation ended before all twelve answers.")
            }
        }
    }

    private func begin() async {
        guard !started else { return }
        started = true
        let holder = self.holder
        let data = AssistantOnboardingDataSource { answers in
            holder.answers = answers
            let result = AyurvedaConstitutionResult.from(answers: answers)
            let draft = AyurvedaConstitutionDraft(
                source: .questionnaire, prakriti: result.distribution,
                declaredTypeID: nil, questionnaireAnswers: answers)
            Task { @MainActor in
                // Let the assistant say the result before the screen moves on.
                try? await Task.sleep(for: .seconds(4))
                onComplete(draft)
            }
        }
        let session = AssistantSession(toolbox: AssistantToolbox(data: data), engine: OnDeviceEngine())
        holder.session = session
        holder.objectWillChange.send()

        let backend = AssistantBackendClient.shared
        if backend.grantState == .available {
            do {
                let granted = try await backend.claimOnboardingGrant()
                status = String(localized: "\(granted) free credits added.")
            } catch {
                status = error.localizedDescription
                return
            }
        }
        await voice.start(purpose: "constitution", session: session)
    }
}

/// The spoken conversation as text, with the card to confirm the result.
struct AssistantVoiceTranscript: View {
    @ObservedObject var session: AssistantSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(session.messages) { AssistantMessageRow(message: $0) }
                ForEach(session.pending) { AssistantPreviewCard(action: $0, session: session) }
            }
        }
    }
}
