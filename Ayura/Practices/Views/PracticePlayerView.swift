import SwiftUI

struct PracticePlayerView: View {
    let practice: Practice
    let duration: Int
    let voiceMode: PracticeVoiceMode
    let ambienceResourceName: String?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var effectManager = EffectManager.shared
    @StateObject private var player = PracticeAudioPlayer()
    @State private var hasStarted = false

    private var hasScene: Bool {
        practice.kind == "visualisation" && practice.sceneImageName != nil
    }

    var body: some View {
        ZStack {
            Color(red: 0.018, green: 0.027, blue: 0.025)
                .ignoresSafeArea()

            if hasScene, let sceneName = practice.sceneImageName {
                PracticeSceneLayer(sceneName: sceneName)
                    .opacity(player.currentCueIndex == 0 && !player.isHolding ? 0.88 : 0.07)
                    .animation(.easeInOut(duration: 2.2), value: player.currentCueIndex)
                    .animation(.easeInOut(duration: 1.2), value: player.isHolding)
                    .ignoresSafeArea()
            }

            Color.black
                .opacity(player.isHolding ? 0.82 : 0.05)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.9), value: player.isHolding)

            tapSurface

            if player.state == .finished {
                VStack(spacing: 12) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("Practice complete")
                        .font(.title3.weight(.medium))
                    Text("Tap to close")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .foregroundStyle(.white.opacity(0.82))
                .transition(.opacity)
                .allowsHitTesting(false)
            } else if !player.isHolding, let cue = player.currentCue {
                Text(cue.text)
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineSpacing(7)
                    .foregroundStyle(.white.opacity(0.94))
                    .padding(.horizontal, 34)
                    .frame(maxWidth: 760)
                    .transition(.opacity)
                    .id(cue.id)
                    .allowsHitTesting(false)
                    .accessibilityAddTraits(.isStaticText)
            }

            closeButton
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            guard !hasStarted else { return }
            hasStarted = true
            UIApplication.shared.isIdleTimerDisabled = true
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
            UIApplication.shared.isIdleTimerDisabled = false
            player.stop()
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
        VStack {
            HStack {
                Spacer()
                Button {
                    player.stop()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        .frame(width: 44, height: 44)
                        .glassCardStyle(cornerRadius: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("End practice")
                .zIndex(10)
            }
            Spacer()
        }
        .padding(.top, 10)
        .padding(.horizontal, 16)
    }
}

private struct PracticeSceneLayer: View {
    let sceneName: String

    private var palette: [Color] {
        if sceneName.contains("hearth") || sceneName.contains("candle") {
            return [
                Color(red: 0.10, green: 0.035, blue: 0.02),
                Color(red: 0.84, green: 0.31, blue: 0.08),
                Color(red: 1.0, green: 0.72, blue: 0.29),
            ]
        }
        if sceneName.contains("night") || sceneName.contains("empty") {
            return [
                Color(red: 0.018, green: 0.025, blue: 0.08),
                Color(red: 0.12, green: 0.16, blue: 0.35),
                Color(red: 0.42, green: 0.47, blue: 0.68),
            ]
        }
        if sceneName.contains("rain") || sceneName.contains("river") || sceneName.contains("lake") {
            return [
                Color(red: 0.025, green: 0.10, blue: 0.13),
                Color(red: 0.08, green: 0.36, blue: 0.43),
                Color(red: 0.42, green: 0.72, blue: 0.70),
            ]
        }
        return [
            Color(red: 0.02, green: 0.08, blue: 0.045),
            Color(red: 0.12, green: 0.42, blue: 0.22),
            Color(red: 0.66, green: 0.74, blue: 0.39),
        ]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [.white.opacity(0.35), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 380
            )
            Canvas { context, size in
                for index in 0..<12 {
                    let fraction = CGFloat(index) / 12
                    let width = size.width * (0.22 + fraction * 0.72)
                    let rect = CGRect(
                        x: size.width * (0.08 + fraction * 0.045),
                        y: size.height * (0.18 + fraction * 0.06),
                        width: width,
                        height: 1
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 1),
                        with: .color(.white.opacity(0.05))
                    )
                }
            }
        }
        .blur(radius: 0.2)
    }
}
