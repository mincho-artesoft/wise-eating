import SwiftData
import SwiftUI

struct PracticeHistoryView: View {
    let profile: Profile
    @Binding var selectedTab: AppTab
    @Binding var globalSearchText: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @Query private var sessions: [PracticeSession]
    @Query(sort: \Practice.catalogNumber) private var practices: [Practice]
    @ObservedObject private var effectManager = EffectManager.shared

    init(
        profile: Profile,
        selectedTab: Binding<AppTab>,
        globalSearchText: Binding<String>
    ) {
        self.profile = profile
        _selectedTab = selectedTab
        _globalSearchText = globalSearchText
        let profileID = profile.id
        _sessions = Query(
            filter: #Predicate<PracticeSession> { session in
                session.profile?.id == profileID
            },
            sort: \PracticeSession.startedAt,
            order: .reverse
        )
    }

    private var searchQuery: String {
        globalSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleSessions: [PracticeSession] {
        guard !searchQuery.isEmpty else { return sessions }

        return sessions.filter { session in
            let searchableValues = [
                session.practiceTitle,
                session.practiceKind,
                session.startedAt.formatted(date: .complete, time: .shortened),
                session.startedAt.formatted(date: .abbreviated, time: .omitted),
                session.startedAt.formatted(date: .omitted, time: .shortened),
                session.endedAt.formatted(date: .omitted, time: .shortened),
                durationText(session.actualDuration),
            ]

            return searchableValues.contains {
                $0.localizedStandardContains(searchQuery)
            }
        }
    }

    private var groupedSessions: [(date: Date, sessions: [PracticeSession])] {
        Dictionary(grouping: visibleSessions) {
            Calendar.current.startOfDay(for: $0.startedAt)
        }
        .map { (date: $0.key, sessions: $0.value) }
        .sorted { $0.date > $1.date }
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

                header
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No practice history",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Practices you start will appear here with their start and end times.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visibleSessions.isEmpty {
                    ContentUnavailableView.search(text: globalSearchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(groupedSessions, id: \.date) { group in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(group.date.formatted(date: .complete, time: .omitted))
                                        .font(.caption.weight(.bold))
                                        .textCase(.uppercase)
                                        .foregroundStyle(
                                            effectManager.currentGlobalAccentColor.opacity(0.68)
                                        )

                                    ForEach(group.sessions) { session in
                                        sessionRow(session)
                                    }
                                }
                            }

                            Color.clear
                                .frame(height: 150)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.top, -safeAreaInsets.top + 10)
        }
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .tint(effectManager.currentGlobalAccentColor)
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: selectedTab) { _, newTab in
            guard newTab != .practices && newTab != .search else { return }
            dismiss()
        }
    }

    private var header: some View {
        ZStack {
            Text("Practice History")
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

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40)
    }

    private func sessionRow(_ session: PracticeSession) -> some View {
        HStack(spacing: 14) {
            sessionArtwork(session)

            VStack(alignment: .leading, spacing: 5) {
                Text(session.practiceTitle)
                    .font(.headline)
                    .lineLimit(2)

                Text(session.practiceKind.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.62))

                Label {
                    Text(
                        "\(session.startedAt.formatted(date: .omitted, time: .shortened)) – "
                            + session.endedAt.formatted(date: .omitted, time: .shortened)
                    )
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.subheadline.weight(.medium))

                Text(durationText(session.actualDuration))
                    .font(.caption)
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.66))
            }

            Spacer(minLength: 4)
        }
        .padding(14)
        .glassCardStyle(cornerRadius: 20)
    }

    @ViewBuilder
    private func sessionArtwork(_ session: PracticeSession) -> some View {
        if let practice = practice(for: session) {
            PracticeThumbnailView(practice: practice)
        } else {
            ZStack {
                Circle()
                    .stroke(
                        effectManager.currentGlobalAccentColor.opacity(0.12),
                        lineWidth: 5
                    )
                    .frame(width: 70, height: 70)

                if let assetName = session.artworkAssetName,
                   let image = UIImage(named: assetName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                } else {
                    Image("practices_icon")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        .padding(18)
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                }
            }
            .frame(width: 80, height: 80)
            .accessibilityHidden(true)
        }
    }

    private func practice(for session: PracticeSession) -> Practice? {
        practices.first { $0.id == session.practiceID }
            ?? practices.first { $0.catalogNumber == session.practiceCatalogNumber }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(1, Int(duration.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes == 0 { return "\(seconds) sec" }
        if seconds == 0 { return "\(minutes) min" }
        return "\(minutes) min \(seconds) sec"
    }
}
