import PhotosUI
import SwiftData
import SwiftUI

/// What the AI button opens: speak, type, or send a photo; the conversation;
/// the cards the person confirms before anything is written.
struct AssistantSheet: View {
    let profile: Profile
    let day: Date
    let onMakeDayPlan: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var effectManager = EffectManager.shared

    @StateObject private var holder = Holder()
    @StateObject private var speech = AssistantSpeechRecognizer()
    @StateObject private var voice = AssistantVoiceSession()
    @ObservedObject private var backend = AssistantBackendClient.shared
    @AppStorage("assistant.useOpenAI") private var useOpenAI = false
    @State private var showCreditsFromBar = false
    @State private var draft = ""
    @State private var mode: InputMode?
    @State private var showConstraints = false
    @FocusState private var textFocused: Bool

    enum InputMode { case speak, type }

    /// Holds the session so it survives view updates and is made once.
    @MainActor
    final class Holder: ObservableObject {
        var session: AssistantSession?
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session = holder.session {
                    AssistantConversationView(
                        session: session,
                        speech: speech,
                        voice: voice,
                        online: onlineEnabled,
                        draft: $draft,
                        mode: $mode,
                        textFocused: $textFocused,
                        onMakeDayPlan: onMakeDayPlan
                    )
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(Text("Assistant"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                if AssistantBackendClient.isOpenAIAvailable {
                    engineBar
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Close") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showConstraints = true } label: {
                        Label { Text("Dietary constraints") } icon: { Image(systemName: "list.bullet.clipboard") }
                    }
                }
            }
            .sheet(isPresented: $showConstraints) {
                NavigationStack { DietaryConstraintsView(profileID: profile.id) }
            }
        }
        .tint(effectManager.currentGlobalAccentColor)
        .onAppear {
            if holder.session == nil {
                let session = AssistantSession(profile: profile, container: modelContext.container)
                session.toolbox.now = { Self.moment(on: day) }
                holder.session = session
                holder.objectWillChange.send()
                applyEngine()
            }
        }
        .onDisappear {
            speech.stop()
            Task { await voice.stop() }
        }
        .onChange(of: useOpenAI) { _, _ in applyEngine() }
    }

    private var onlineEnabled: Bool { AssistantBackendClient.isOpenAIAvailable && useOpenAI }

    private func applyEngine() {
        guard let session = holder.session else { return }
        session.use(onlineEnabled ? OpenAIEngine() : OnDeviceEngine())
        if onlineEnabled { Task { try? await backend.refreshWallet() } }
    }

    /// On-device (free) or OpenAI (credits), with the balance.
    private var engineBar: some View {
        HStack(spacing: 10) {
            Picker(selection: $useOpenAI) {
                Text("On device · free").tag(false)
                Text("OpenAI · credits").tag(true)
            } label: { Text("Assistant") }
            .pickerStyle(.segmented)
            if useOpenAI {
                Button { showCreditsFromBar = true } label: {
                    AssistantCreditsBadge(credits: voice.credits ?? backend.wallet?.credits)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showCreditsFromBar) { AssistantCreditsView() }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    /// Logging defaults to the day shown on the nutrition screen, at the
    /// current time of day.
    private static func moment(on day: Date) -> Date {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return Date() }
        let t = cal.dateComponents([.hour, .minute], from: Date())
        return cal.date(bySettingHour: t.hour ?? 12, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }
}

struct AssistantConversationView: View {
    @ObservedObject var session: AssistantSession
    @ObservedObject var speech: AssistantSpeechRecognizer
    @ObservedObject var voice: AssistantVoiceSession
    let online: Bool
    @Binding var draft: String
    @State private var showPhotoConsent = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showCredits = false
    @Binding var mode: AssistantSheet.InputMode?
    var textFocused: FocusState<Bool>.Binding
    let onMakeDayPlan: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if session.messages.isEmpty && mode == nil {
                            startChoices
                        }
                        ForEach(session.messages) { message in
                            AssistantMessageRow(message: message)
                        }
                        ForEach(session.pending) { action in
                            AssistantPreviewCard(action: action, session: session)
                        }
                        if let undo = session.lastUndo, session.pending.isEmpty {
                            Button {
                                Task { await session.undoLast() }
                            } label: {
                                Label { Text("Undo: \(undo.message)") } icon: { Image(systemName: "arrow.uturn.backward") }
                            }
                            .buttonStyle(.bordered)
                        }
                        if session.isWorking {
                            ProgressView().padding(.vertical, 4)
                        }
                        if session.needsCredits || voice.state == .ended(String(localized: "You are out of AI credits.")) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("The online assistant needs credits. The on-device assistant stays free.")
                                    .font(.subheadline)
                                Button { showCredits = true } label: { Text("Get credits") }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .onChange(of: session.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: session.pending.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            Divider()
            inputBar
        }
        .confirmationDialog(Text("Send a photo to OpenAI?"), isPresented: $showPhotoConsent, titleVisibility: .visible) {
            Button { showPhotoPicker = true } label: { Text("Choose a photo") }
            Button(role: .cancel) {} label: { Text("Cancel") }
        } message: {
            Text("The photo is sent to OpenAI to read the dietary restrictions in it. It is not stored on our server. You check every restriction before it is saved.")
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .sheet(isPresented: $showCredits, onDismiss: { session.needsCredits = false }) { AssistantCreditsView() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let jpeg = AssistantPhoto.jpeg(from: data) else { return }
                await session.send(draft, imageJPEG: jpeg)
                draft = ""
            }
        }
        .onChange(of: voice.state) { _, new in
            if case let .ended(reason?) = new { session.appendExternal(.notice, reason) }
        }
        .onChange(of: speech.state) { old, new in
            // Recognition ended (the person stopped, or it finished): send it.
            if old == .listening, new != .listening {
                let text = speech.transcript
                if !text.isEmpty { Task { await session.send(text) } }
            }
        }
    }

    private var startChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tell me what you ate, or ask for a plan.")
                .font(.headline)
            Text("For example: \"two eggs and a slice of bread with butter for breakfast\".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                choice(String(localized: "Speak"), systemImage: "mic.fill") {
                    mode = .speak
                    startListening()
                }
                choice(String(localized: "Type"), systemImage: "keyboard") {
                    mode = .type
                    textFocused.wrappedValue = true
                }
                choice(String(localized: "Photo"), systemImage: "camera") { showPhotoConsent = true }
                    .disabled(!online)
                    .opacity(online ? 1 : 0.45)
            }
            if online {
                Text("Send a photo of a prescription, lab results or a note; I will list the dietary restrictions in it for you to check.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Photos of a prescription or lab report need the online assistant; the on-device assistant cannot read documents.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if AssistantOnboardingOffer.firstPlanRequested {
                Button {
                    AssistantOnboardingOffer.firstPlanRequested = false
                    Task { await session.send(String(localized: "Make my first day plan for tomorrow, for my constitution, allergies and constraints.")) }
                } label: {
                    Label { Text("Make my first day plan") } icon: { Image(systemName: "sun.max") }
                }
                .buttonStyle(.borderedProminent)
            }
            Button(action: onMakeDayPlan) {
                Label { Text("Make a plan for this day") } icon: { Image(systemName: "sparkles") }
            }
            .padding(.top, 4)
            Text("A wellness and food-logging tool, not medical advice.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    private func choice(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.title2)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(.bordered)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button {
                if isListening {
                    speech.stop()
                    Task { await voice.stop() }
                } else {
                    mode = .speak
                    startListening()
                }
            } label: {
                Image(systemName: isListening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 30))
            }
            .accessibilityLabel(isListening ? Text("Stop listening") : Text("Speak"))

            if online {
                Button { showPhotoConsent = true } label: {
                    Image(systemName: "camera.circle.fill").font(.system(size: 30))
                }
                .accessibilityLabel(Text("Send a photo"))
            }

            if voice.state == .live {
                Text("Live conversation. Speak naturally; tap stop to end.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
            } else if voice.state == .connecting {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            } else if speech.state == .listening {
                Text(speech.transcript.isEmpty ? String(localized: "Listening…") : speech.transcript)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else {
                TextField(String(localized: "Type a message"), text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused(textFocused)
                    .submitLabel(.send)
                    .onSubmit(sendDraft)
                Button(action: sendDraft) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || session.isWorking)
                .accessibilityLabel(Text("Send"))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            if speech.state == .denied {
                Text("Allow microphone and speech recognition in Settings to speak to the assistant.")
                    .font(.footnote).foregroundStyle(.red).offset(y: -24)
            } else if speech.state == .unavailable {
                Text("Speech recognition is not available for this language right now.")
                    .font(.footnote).foregroundStyle(.red).offset(y: -24)
            }
        }
    }

    private var isListening: Bool { speech.state == .listening || voice.state == .live || voice.state == .connecting }

    private func startListening() {
        if online {
            Task { await voice.start(purpose: "assistant", session: session) }
        } else {
            Task { await speech.start() }
        }
    }

    private func sendDraft() {
        let text = draft
        draft = ""
        Task { await session.send(text) }
    }
}

struct AssistantMessageRow: View {
    let message: AssistantSession.Message

    var body: some View {
        HStack {
            if message.role == .person { Spacer(minLength: 40) }
            Text(message.text)
                .padding(10)
                .background(background, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(message.role == .notice ? .secondary : .primary)
            if message.role != .person { Spacer(minLength: 40) }
        }
    }

    private var background: Color {
        switch message.role {
        case .person: Color.accentColor.opacity(0.18)
        case .assistant: Color.secondary.opacity(0.12)
        case .notice: Color.clear
        }
    }
}
