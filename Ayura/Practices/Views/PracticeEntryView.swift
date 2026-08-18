import SwiftUI
import UIKit

struct PracticeEntryView: View {
    let practice: Practice
    let profile: Profile
    @Binding var selectedTab: AppTab
    let onDismissSearch: () -> Void
    let onHideSearchButton: () -> Void
    let onShowSearchButton: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @ObservedObject private var effectManager = EffectManager.shared
    @State private var selectedDuration: Int
    @State private var selectedVoiceMode: PracticeVoiceMode
    @State private var selectedAmbienceName: String?
    @State private var isPresentingPlayer = false
    @State private var isPresentingArtwork = false

    init(
        practice: Practice,
        profile: Profile,
        selectedTab: Binding<AppTab>,
        onDismissSearch: @escaping () -> Void,
        onHideSearchButton: @escaping () -> Void,
        onShowSearchButton: @escaping () -> Void
    ) {
        self.practice = practice
        self.profile = profile
        _selectedTab = selectedTab
        self.onDismissSearch = onDismissSearch
        self.onHideSearchButton = onHideSearchButton
        self.onShowSearchButton = onShowSearchButton
        _selectedDuration = State(initialValue: practice.availableDurationOptions.first ?? practice.durationSeconds)
        _selectedVoiceMode = State(initialValue: PracticeAudioDefaults.voiceMode)
        _selectedAmbienceName = State(
            initialValue: PracticeAudioAssetResolver.defaultResourceName(
                for: practice.ambienceTrackID,
                catalogNumber: practice.catalogNumber
            )
        )
    }

    private var ambienceTracks: [PracticeAmbienceTrack] {
        PracticeAudioAssetResolver.availableAmbienceTracks
    }

    private var selectedAmbienceTitle: String {
        guard let selectedAmbienceName else { return "No ambience" }
        return ambienceTracks.first { $0.resourceName == selectedAmbienceName }?.displayName
            ?? selectedAmbienceName.replacingOccurrences(of: "_", with: " ")
    }

    private var headerTopPadding: CGFloat {
        -safeAreaInsets.top + 10
    }

    var body: some View {
        ZStack {
            ThemeBackgroundView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                PracticeUserHeader(profile: profile)
                    .padding(.leading, 20)
                    .padding(.trailing, 30)
                    .padding(.bottom, 8)

                customHeader
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        artworkHero
                        titleBlock
                        metadata
                        descriptionBlock

                        lengthPicker
                        guidePicker
                        soundPicker
                        beginButton

                        Color.clear
                            .frame(height: 150)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.top, headerTopPadding)
        }
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .tint(effectManager.currentGlobalAccentColor)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            onDismissSearch()
            onHideSearchButton()
        }
        .onDisappear(perform: onShowSearchButton)
        .onChange(of: selectedTab) { _, newTab in
            guard newTab != .practices else { return }
            dismiss()
        }
        .fullScreenCover(isPresented: $isPresentingPlayer) {
            PracticePlayerView(
                practice: practice,
                profile: profile,
                duration: selectedDuration,
                voiceMode: selectedVoiceMode,
                ambienceResourceName: selectedAmbienceName
            )
        }
        .fullScreenCover(isPresented: $isPresentingArtwork) {
            if let artworkImage {
                FullscreenImageView(image: artworkImage) {
                    isPresentingArtwork = false
                }
            } else {
                Color.black.ignoresSafeArea()
            }
        }
    }

    private var customHeader: some View {
        ZStack {
            Text("Practice Details")
                .font(.headline)

            HStack {
                Button("Back") {
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassCardStyle(cornerRadius: 20)
                .buttonStyle(.plain)
                .accessibilityHint("Returns to the practices list")

                Spacer()

                PracticeFavoriteButton(
                    practice: practice,
                    font: .title2,
                    frameSize: 40
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40)
    }

    private var artworkHero: some View {
        PracticeArtworkView(practice: practice)
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.34), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.16), radius: 18, y: 9)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .onTapGesture {
                guard artworkImage != nil else { return }
                isPresentingArtwork = true
            }
            .accessibilityAddTraits(artworkImage == nil ? [] : .isButton)
            .accessibilityHint(
                artworkImage == nil ? "" : "Opens the practice image full screen"
            )
    }

    private var artworkImage: UIImage? {
        guard let assetName = practice.artworkAssetName else { return nil }
        return UIImage(named: assetName)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(kindDisplayName(practice.kind).uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.62))
            Text(practice.title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            if let sanskrit = practice.sanskrit, !sanskrit.isEmpty {
                Text(sanskrit)
                    .font(.title3)
                    .italic()
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.68))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadata: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                PracticeMetadataPill(
                    icon: "figure.mind.and.body",
                    text: practice.posture.capitalized
                )
                PracticeMetadataPill(
                    icon: practice.eyes == "closed" ? "eye.slash" : "eye",
                    text: "Eyes \(practice.eyes)"
                )
                PracticeMetadataPill(
                    icon: "chart.bar",
                    text: "Level \(practice.level)"
                )
                PracticeMetadataPill(
                    icon: "clock",
                    text: practiceDuration(practice.durationSeconds)
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20)
    }

    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(practice.practiceDescription)
                .font(.body)
                .lineSpacing(4)
            Divider().overlay(effectManager.currentGlobalAccentColor.opacity(0.16))
            VStack(alignment: .leading, spacing: 6) {
                Text("TRADITION")
                    .font(.caption2.weight(.bold))
                    .tracking(1.3)
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.58))
                Text(practice.sourceTradition)
                    .font(.subheadline)
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.78))
            }
        }
        .padding(18)
        .practiceCard()
    }

    private var lengthPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            PracticeSectionHeading(title: "Length", detail: "Choose your pace")
            HStack(spacing: 9) {
                ForEach(practice.availableDurationOptions, id: \.self) { duration in
                    Button {
                        withAnimation(.snappy) { selectedDuration = duration }
                    } label: {
                        Text(practiceDuration(duration))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                            )
                            .glassCardStyle(cornerRadius: 13)
                            .overlay {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(
                                        effectManager.currentGlobalAccentColor.opacity(
                                            selectedDuration == duration ? 0.16 : 0
                                        )
                                    )
                                    .allowsHitTesting(false)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(
                                        effectManager.currentGlobalAccentColor.opacity(
                                            selectedDuration == duration ? 0.56 : 0.12
                                        ),
                                        lineWidth: selectedDuration == duration ? 1.25 : 0.75
                                    )
                                    .allowsHitTesting(false)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            if practice.computedRuntimeSeconds > practice.durationSeconds {
                Text("Options shorter than the spoken practice were hidden.")
                    .font(.caption)
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.62))
            }
        }
    }

    private var guidePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            PracticeSectionHeading(title: "Guide", detail: "Voice guidance")
            HStack(spacing: 9) {
                ForEach(availableVoiceModes) { mode in
                    Button {
                        withAnimation(.snappy) { selectedVoiceMode = mode }
                    } label: {
                        Text(voiceModeTitle(mode))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                            )
                            .glassCardStyle(cornerRadius: 13)
                            .overlay {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(
                                        effectManager.currentGlobalAccentColor.opacity(
                                            selectedVoiceMode == mode ? 0.16 : 0
                                        )
                                    )
                                    .allowsHitTesting(false)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(
                                        effectManager.currentGlobalAccentColor.opacity(
                                            selectedVoiceMode == mode ? 0.56 : 0.12
                                        ),
                                        lineWidth: selectedVoiceMode == mode ? 1.25 : 0.75
                                    )
                                    .allowsHitTesting(false)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var availableVoiceModes: [PracticeVoiceMode] {
        practice.narrationAudioAssetName == nil
            ? [.deviceTTS, .off]
            : [.deviceTTS, .off, .recorded]
    }

    private func voiceModeTitle(_ mode: PracticeVoiceMode) -> String {
        switch mode {
        case .deviceTTS: "Device voice"
        case .off: "No voice"
        case .recorded: "Recorded"
        }
    }

    private var soundPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            PracticeSectionHeading(
                title: "Sound",
                detail: "\(ambienceTracks.count) bundled tracks"
            )
            Menu {
                Button("No ambience") { selectedAmbienceName = nil }
                if !ambienceTracks.isEmpty { Divider() }
                ForEach(ambienceTracks) { track in
                    Button {
                        selectedAmbienceName = track.resourceName
                    } label: {
                        if selectedAmbienceName == track.resourceName {
                            Label(track.displayName, systemImage: "checkmark")
                        } else {
                            Text(track.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selectedAmbienceName == nil ? "speaker.slash" : "waveform")
                        .frame(width: 22)
                    Text(selectedAmbienceTitle)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 15)
                .frame(height: 50)
                .practiceCard(cornerRadius: 15)
            }
        }
    }

    private var beginButton: some View {
        Button {
            isPresentingPlayer = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                Text("Begin")
                    .font(.headline)
            }
            .foregroundStyle(
                effectManager.currentGlobalAccentColor
            )
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .glassCardStyle(cornerRadius: 18)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(effectManager.currentGlobalAccentColor.opacity(0.12))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        effectManager.currentGlobalAccentColor.opacity(0.42),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .accessibilityHint("Starts the guided practice")
    }
}

private struct PracticeMetadataPill: View {
    let icon: String
    let text: String
    @ObservedObject private var effectManager = EffectManager.shared

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .frame(height: 34)
            .contentShape(Capsule())
            .glassCardStyle(cornerRadius: 17, showsShadow: false)
    }
}

private struct PracticeSectionHeading: View {
    let title: String
    let detail: String
    @ObservedObject private var effectManager = EffectManager.shared

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.58))
        }
    }
}
