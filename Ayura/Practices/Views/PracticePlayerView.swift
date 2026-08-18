import SwiftUI

struct PracticePlayerView: View {
    let practice: Practice
    let profile: Profile
    let duration: Int
    let voiceMode: PracticeVoiceMode
    let ambienceResourceName: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @StateObject private var player = PracticeAudioPlayer()
    @State private var hasStarted = false
    @State private var sessionStartedAt: Date?
    @State private var hasRecordedSession = false

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = min(max(geometry.size.width - 56, 1), 680)

            ZStack {
                Color(red: 0.018, green: 0.027, blue: 0.025)

                PracticeArtworkView(practice: practice)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)

                Color.black
                    .opacity(player.isHolding ? 0.4 : 0.2)
                    .animation(.easeInOut(duration: 0.9), value: player.isHolding)

                tapSurface

                cueContent(width: contentWidth)

                closeButton
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topTrailing
                    )
                    .padding(.top, safeAreaInsets.top + 8)
                    .padding(.trailing, 16)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            guard !hasStarted else { return }
            hasStarted = true
            let startedAt = Date()
            sessionStartedAt = startedAt
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await NotificationManager.shared.updatePracticeReminder(
                    lastPracticeStartedAt: startedAt,
                    practiceTitle: practice.title,
                    profileID: profile.id
                )
            }
            player.play(
                practice.makeAudioPlan(
                    duration: duration,
                    voiceMode: voiceMode,
                    ambienceResourceName: ambienceResourceName
                ),
                voiceMode: voiceMode
            )
        }
        .onDisappear {
            recordSessionIfNeeded(completed: player.state == .finished)
            UIApplication.shared.isIdleTimerDisabled = false
            player.stop()
        }
        .onChange(of: player.state) { _, state in
            guard state == .finished else { return }
            recordSessionIfNeeded(completed: true)
        }
    }

    @ViewBuilder
    private func cueContent(width: CGFloat) -> some View {
        if player.state == .finished {
            VStack(spacing: 12) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.55))
                Text("Practice complete")
                    .font(.title3.weight(.medium))
                Text("Tap to close")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(width: width)
            .foregroundStyle(.white.opacity(0.9))
            .transition(.opacity)
            .allowsHitTesting(false)
        } else if !player.isHolding, let cue = player.currentCue {
            Text(cue.text)
                .font(.system(size: 26, weight: .regular, design: .serif))
                .multilineTextAlignment(.center)
                .lineSpacing(7)
                .foregroundStyle(.white.opacity(0.96))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(width: width)
                .background(
                    .black.opacity(0.44),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.24), radius: 14, y: 6)
                .transition(.opacity)
                .id(cue.id)
                .allowsHitTesting(false)
                .accessibilityAddTraits(.isStaticText)
        }
    }

    private var tapSurface: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture {
                if player.state == .finished {
                    dismiss()
                } else {
                    player.advance()
                }
            }
            .accessibilityLabel("Practice player")
            .accessibilityHint("Tap to move to the next instruction")
    }

    private var closeButton: some View {
        Button {
            recordSessionIfNeeded(completed: player.state == .finished)
            player.stop()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.46), in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.52), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
                .contentShape(Circle())
            }
        .buttonStyle(.plain)
        .accessibilityLabel("End practice")
        .zIndex(10)
    }

    @MainActor
    private func recordSessionIfNeeded(completed: Bool) {
        guard !hasRecordedSession,
              let sessionStartedAt else {
            return
        }

        let endedAt = Date()
        guard endedAt > sessionStartedAt else { return }
        hasRecordedSession = true

        let session = PracticeSession(
            practice: practice,
            profile: profile,
            startedAt: sessionStartedAt,
            endedAt: endedAt,
            plannedDurationSeconds: duration,
            completed: completed
        )
        modelContext.insert(session)

        do {
            try modelContext.save()
        } catch {
            print("⚠️ Could not save practice history: \(error)")
        }

        Task { @MainActor in
            let (_, eventID) = await CalendarViewModel.shared.createEvent(
                forProfile: profile,
                startDate: session.startedAt,
                endDate: session.endedAt,
                title: "Practice: \(session.practiceTitle)",
                invisiblePayload: PracticeCalendarEvent.invisiblePayload(for: session)
            )

            if let eventID {
                session.calendarEventID = eventID
                try? modelContext.save()
                NotificationCenter.default.post(name: .forceCalendarReload, object: nil)
            }
        }
    }
}
