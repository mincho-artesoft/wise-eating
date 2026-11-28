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
            }
        }
        .onDisappear { speech.stop() }
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
    @Binding var draft: String
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
                    Task { await speech.start() }
                }
                choice(String(localized: "Type"), systemImage: "keyboard") {
                    mode = .type
                    textFocused.wrappedValue = true
                }
                choice(String(localized: "Photo"), systemImage: "camera") {}
                    .disabled(true)
                    .opacity(0.45)
            }
            Text("Photos of a prescription or lab report need the online assistant; the on-device assistant cannot read documents.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                if speech.state == .listening {
                    speech.stop()
                } else {
                    mode = .speak
                    Task { await speech.start() }
                }
            } label: {
                Image(systemName: speech.state == .listening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 30))
            }
            .accessibilityLabel(speech.state == .listening ? Text("Stop listening") : Text("Speak"))

            if speech.state == .listening {
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
