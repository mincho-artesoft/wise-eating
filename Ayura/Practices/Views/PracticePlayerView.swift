import SwiftUI
import UIKit

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
    @State private var playbackStartTask: Task<Void, Never>?
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
        .background {
            PracticePlayerDidAppearReader {
                startPracticeIfNeeded()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onDisappear {
            playbackStartTask?.cancel()
            playbackStartTask = nil
            recordSessionIfNeeded(completed: player.state == .finished)
            UIApplication.shared.isIdleTimerDisabled = false
            player.stop()
        }
        .onChange(of: player.state) { _, state in
            guard state == .finished else { return }
            recordSessionIfNeeded(completed: true)
        }
    }

    @MainActor
    private func startPracticeIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        UIApplication.shared.isIdleTimerDisabled = true

        do {
            try player.prepareForPlayback()
        } catch {
            print("⚠️ Practice audio session could not prepare: \(error)")
        }

        playbackStartTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(400))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            let startedAt = Date()
            sessionStartedAt = startedAt
            player.play(
                practice.makeAudioPlan(
                    duration: duration,
                    voiceMode: voiceMode,
                    ambienceResourceName: ambienceResourceName
                ),
                voiceMode: voiceMode
            )

            Task {
                await NotificationManager.shared.updatePracticeReminder(
                    lastPracticeStartedAt: startedAt,
                    practiceTitle: practice.title,
                    profileID: profile.id
                )
                await NextEventLiveActivityManager.shared.refreshIfRunning(for: profile)
            }
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

        do {
            let writeContext = try CombinedStoreFactory.makeUserWriteContext(
                from: modelContext.container
            )
            guard let writeProfile = try CatalogReferenceResolver.userProfile(
                id: profile.id,
                context: writeContext
            ) else {
                throw CatalogReferenceError.missingUserProfile(profile.id)
            }

            let session = PracticeSession(
                practice: practice,
                profile: writeProfile,
                startedAt: sessionStartedAt,
                endedAt: endedAt,
                plannedDurationSeconds: duration,
                completed: completed
            )
            writeContext.insert(session)
            try writeContext.save()
            hasRecordedSession = true

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
                    try? writeContext.save()
                    NotificationCenter.default.post(
                        name: .forceCalendarReload,
                        object: nil
                    )
                }
            }
        } catch {
            print("⚠️ Could not save practice history: \(error)")
        }
    }
}

private struct PracticePlayerDidAppearReader: UIViewControllerRepresentable {
    let onDidAppear: @MainActor () -> Void

    func makeUIViewController(context: Context) -> DidAppearViewController {
        let controller = DidAppearViewController()
        controller.onDidAppear = onDidAppear
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(
        _ uiViewController: DidAppearViewController,
        context: Context
    ) {
        uiViewController.onDidAppear = onDidAppear
    }

    final class DidAppearViewController: UIViewController {
        var onDidAppear: (@MainActor () -> Void)?
        private var hasReportedAppearance = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !hasReportedAppearance else { return }
            hasReportedAppearance = true
            onDidAppear?()
        }
    }
}
