import SwiftData
import SwiftUI

struct PracticeUserHeader: View {
    let profile: Profile

    @ObservedObject private var effectManager = EffectManager.shared
    @State private var currentTimeString = ""
    @State private var hasUnreadNotifications = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let timeFormatter = DateFormatter.shortTime

    var body: some View {
        HStack {
            Text(currentTimeString)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(effectManager.currentGlobalAccentColor)

            Spacer()

            Button {
                NotificationCenter.default.post(
                    name: Notification.Name("openProfilesDrawer"),
                    object: nil
                )
            } label: {
                ZStack(alignment: .topTrailing) {
                    profileImage

                    if hasUnreadNotifications {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 12, height: 12)
                            .offset(x: 1, y: -1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open profiles")
        }
        .onAppear {
            currentTimeString = Self.timeFormatter.string(from: Date())
        }
        .onReceive(timer) { date in
            currentTimeString = Self.timeFormatter.string(from: date)
        }
        .task {
            await updateUnreadNotifications()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .unreadNotificationStatusChanged)
        ) { _ in
            Task { await updateUnreadNotifications() }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.willEnterForegroundNotification
            )
        ) { _ in
            Task { await updateUnreadNotifications() }
        }
    }

    @ViewBuilder
    private var profileImage: some View {
        if let photoData = profile.photoData,
           let image = UIImage(data: photoData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(effectManager.currentGlobalAccentColor.opacity(0.2))
                if let firstLetter = profile.name.first {
                    Text(String(firstLetter))
                        .font(.headline)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                }
            }
            .frame(width: 40, height: 40)
        }
    }

    @MainActor
    private func updateUnreadNotifications() async {
        let notifications = await NotificationManager.shared.getUnreadNotifications()
        hasUnreadNotifications = !notifications.isEmpty
    }
}

struct PracticesView: View {
    let profile: Profile
    @Binding var globalSearchText: String
    @Binding var selectedTab: AppTab

    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @Query(sort: \Practice.catalogNumber) private var practices: [Practice]
    @ObservedObject private var effectManager = EffectManager.shared
    @State private var selectedKind: String?
    @State private var showsFavoritesOnly = false
    @State private var favoriteRevision = 0
    @State private var constitutionRevision = 0

    private var eligiblePractices: [Practice] {
        practices.filter { $0.minimalAgeMonths <= profile.ageInMonths }
    }

    private var visiblePractices: [Practice] {
        _ = favoriteRevision
        let kindFiltered: [Practice]
        if showsFavoritesOnly {
            kindFiltered = eligiblePractices.filter(\.isFavorite)
        } else if let selectedKind {
            kindFiltered = eligiblePractices.filter { $0.kind == selectedKind }
        } else {
            kindFiltered = eligiblePractices
        }

        guard !searchQuery.isEmpty else { return kindFiltered }
        return kindFiltered.filter(matchesSearch)
    }

    private var searchQuery: String {
        globalSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentSlot: PracticeDaySlot {
        PracticeDaySlot.current()
    }

    private var rightNowPractices: [Practice] {
        _ = constitutionRevision
        let timeMatched = eligiblePractices.filter {
            $0.timeOfDay.contains(currentSlot.rawValue)
        }

        guard let target = AyurvedaConstitutionStore
            .record(for: profile.id)?
            .target()
        else {
            return timeMatched
        }

        return timeMatched.sorted { lhs, rhs in
            let lhsFit = target.doshaFit(
                vata: lhs.doshaVata,
                pitta: lhs.doshaPitta,
                kapha: lhs.doshaKapha
            )
            let rhsFit = target.doshaFit(
                vata: rhs.doshaVata,
                pitta: rhs.doshaPitta,
                kapha: rhs.doshaKapha
            )

            if lhsFit != rhsFit {
                return lhsFit > rhsFit
            }
            return lhs.catalogNumber < rhs.catalogNumber
        }
    }

    private var headerTopPadding: CGFloat {
        -safeAreaInsets.top + 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PracticeUserHeader(profile: profile)
                .padding(.leading, 20)
                .padding(.trailing, 30)
                .padding(.horizontal, -18)
                .padding(.bottom, -4)

            header
            rightNowCard
            filterChips

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if practices.isEmpty {
                        ProgressView("Preparing practices…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else if visiblePractices.isEmpty {
                        Group {
                            if searchQuery.isEmpty && showsFavoritesOnly {
                                ContentUnavailableView(
                                    "No favorite practices",
                                    systemImage: "star",
                                    description: Text(
                                        "Tap the star on a practice to add it to Favorites."
                                    )
                                )
                            } else if searchQuery.isEmpty {
                                ContentUnavailableView(
                                    "No practices",
                                    systemImage: "wind",
                                    description: Text("No practices match this filter.")
                                )
                            } else {
                                ContentUnavailableView.search(text: globalSearchText)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(visiblePractices) { practice in
                            HStack(alignment: .top, spacing: 0) {
                                NavigationLink {
                                    PracticeEntryView(
                                        practice: practice,
                                        profile: profile,
                                        selectedTab: $selectedTab
                                    )
                                } label: {
                                    PracticeLibraryRow(practice: practice)
                                }
                                .buttonStyle(.plain)

                                PracticeFavoriteButton(practice: practice) {
                                    favoriteRevision &+= 1
                                }
                                .padding(.top, 16)
                                .padding(.trailing, 12)
                            }
                            .glassCardStyle(cornerRadius: 20)
                        }
                    }

                    Color.clear
                        .frame(height: 150)
                        .accessibilityHidden(true)
                }
            }
            .scrollIndicators(.hidden)
            .mask(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(
                            color: effectManager.currentGlobalAccentColor,
                            location: 0.01
                        ),
                        .init(
                            color: effectManager.currentGlobalAccentColor,
                            location: 0.9
                        ),
                        .init(color: .clear, location: 0.95),
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .padding(.horizontal, 18)
        .padding(.top, headerTopPadding)
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .tint(effectManager.currentGlobalAccentColor)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(
            NotificationCenter.default.publisher(
                for: .ayurvedaConstitutionDidChange
            )
        ) { notification in
            guard notification.object == nil
                || (notification.object as? UUID) == profile.id
            else {
                return
            }
            constitutionRevision &+= 1
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Practices")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Meditation, breath and deep rest")
                .font(.subheadline)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
    }

    private var rightNowCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RIGHT NOW")
                        .font(.caption2.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.65))
                    Text(currentSlot.displayName)
                        .font(.title2.weight(.semibold))
                    Text(currentSlot.guidance)
                        .font(.subheadline)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.72))
                }
                Spacer()
                Image(systemName: currentSlot.symbol)
                    .font(.system(size: 27, weight: .light))
                    .symbolRenderingMode(.hierarchical)
            }

            if let suggested = rightNowPractices.first {
                NavigationLink {
                    PracticeEntryView(
                        practice: suggested,
                        profile: profile,
                        selectedTab: $selectedTab
                    )
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Suggested")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.62))
                            Text(suggested.title)
                                .font(.headline)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(practiceDuration(suggested.durationSeconds))
                            .font(.caption.monospacedDigit())
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(12)
                    .background(
                        effectManager.currentGlobalAccentColor.opacity(
                            effectManager.isLightRowTextColor ? 0.13 : 0.08
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .practiceCard()
    }

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(PracticeListFilter.allCases) { filter in
                    practiceSearchChip(for: filter)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 5)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -18)
    }

    private func practiceSearchChip(for filter: PracticeListFilter) -> some View {
        let isSelected = practiceFilterSelection.wrappedValue == filter
        let accent = effectManager.currentGlobalAccentColor

        return Button {
            withAnimation(.easeInOut) {
                practiceFilterSelection.wrappedValue = filter
            }
        } label: {
            HStack(spacing: 6) {
                if filter == .favorites {
                    Image(systemName: "star.fill")
                        .imageScale(.medium)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.yellow)
                }

                Text(filter.rawValue)
                    .font(.caption.weight(.semibold))

                Text(String(practiceCount(for: filter)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(accent.opacity(0.72))
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(accent.opacity(isSelected ? 0.24 : 0.12))
            }
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        isSelected ? accent : accent.opacity(0.22),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .glassCardStyle(cornerRadius: 20, showsShadow: false)
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var practiceFilterSelection: Binding<PracticeListFilter> {
        Binding(
            get: {
                if showsFavoritesOnly { return .favorites }
                guard let selectedKind else { return .all }
                return PracticeListFilter(kind: selectedKind) ?? .all
            },
            set: { filter in
                showsFavoritesOnly = filter == .favorites
                selectedKind = filter.kind
            }
        )
    }

    private func practiceCount(for filter: PracticeListFilter) -> Int {
        if filter == .all { return eligiblePractices.count }
        if filter == .favorites {
            return eligiblePractices.count(where: \.isFavorite)
        }
        guard let kind = filter.kind else { return 0 }
        return eligiblePractices.count { $0.kind == kind }
    }

    private func matchesSearch(_ practice: Practice) -> Bool {
        var searchableValues = [
            practice.title,
            practice.sanskrit ?? "",
            practice.practiceDescription,
            practice.technique,
            practice.sourceTradition,
            practice.kind,
            kindDisplayName(practice.kind),
            practice.posture,
            practice.eyes,
            practice.guna,
            practice.agni,
            practice.slug,
        ]
        searchableValues.append(contentsOf: practice.goals)
        searchableValues.append(contentsOf: practice.themes)
        searchableValues.append(contentsOf: practice.timeOfDay)
        searchableValues.append(contentsOf: practice.season)
        searchableValues.append(contentsOf: practice.contraindications)
        searchableValues.append(contentsOf: practice.script.map(\.text))

        return searchableValues.contains {
            $0.localizedStandardContains(searchQuery)
        }
    }
}

private struct PracticeLibraryRow: View {
    let practice: Practice
    @ObservedObject private var effectManager = EffectManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PracticeThumbnailView(practice: practice)

            VStack(alignment: .leading, spacing: 4) {
                Text(practice.title)
                    .font(.headline.weight(.bold))
                    .lineLimit(2)

                if let sanskrit = practice.sanskrit, !sanskrit.isEmpty {
                    Text(sanskrit)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                        .lineLimit(2)
                }

                HStack(spacing: 7) {
                    Text(kindDisplayName(practice.kind))
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                    Circle()
                        .frame(width: 3, height: 3)
                    Text(practiceDuration(practice.durationSeconds))
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.7))
            }
            .layoutPriority(1)

            Spacer(minLength: 6)
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens practice details")
    }
}

private struct PracticeThumbnailView: View {
    let practice: Practice
    @ObservedObject private var effectManager = EffectManager.shared

    private let centralContentDiameter: CGFloat = 60
    private let donutRingThickness: CGFloat = 5
    private let canalRingThickness: CGFloat = 5

    private var doshaSegments: [NutrientProportionData] {
        [
            NutrientProportionData(
                name: "Vata",
                value: Double(max(-practice.doshaVata, 0)),
                color: .blue
            ),
            NutrientProportionData(
                name: "Pitta",
                value: Double(max(-practice.doshaPitta, 0)),
                color: .orange
            ),
            NutrientProportionData(
                name: "Kapha",
                value: Double(max(-practice.doshaKapha, 0)),
                color: .green
            ),
        ].filter { $0.value > 0 }
    }

    private var doshaTotal: Double {
        doshaSegments.reduce(0) { $0 + $1.value }
    }

    private var canalRingOuterDiameter: CGFloat {
        centralContentDiameter + (2 * canalRingThickness)
    }

    private var arcDrawingRadius: CGFloat {
        (canalRingOuterDiameter / 2) + (donutRingThickness / 2)
    }

    private var totalDiameter: CGFloat {
        canalRingOuterDiameter + (2 * donutRingThickness)
    }

    private var symbol: String {
        switch practice.kind {
        case "meditation": "brain.head.profile"
        case "visualisation": "eye"
        case "pranayama": "wind"
        case "relaxation": "moon.zzz"
        case "kriya": "sparkles"
        default: "circle.hexagongrid"
        }
    }

    var body: some View {
        ZStack {
            TubularRingStroke(
                shape: Circle(),
                style: effectManager.currentGlobalAccentColor.opacity(0.1),
                strokeStyle: StrokeStyle(lineWidth: donutRingThickness),
                role: .track
            )
            .frame(width: arcDrawingRadius * 2, height: arcDrawingRadius * 2)

            if doshaTotal > 0 {
                ArcSegmentsView(
                    proportions: doshaSegments,
                    effectiveTotalForNormalization: doshaTotal,
                    arcCenter: CGPoint(x: totalDiameter / 2, y: totalDiameter / 2),
                    arcDrawingRadius: arcDrawingRadius,
                    donutRingThickness: donutRingThickness
                )
            }

            Circle()
                .fill(effectManager.currentGlobalAccentColor.opacity(0.05))
                .frame(width: centralContentDiameter, height: centralContentDiameter)
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.black.opacity(0.3), .clear],
                                startPoint: .bottomTrailing,
                                endPoint: .topLeading
                            ),
                            lineWidth: 1
                        )
                }
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.8), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }

            Image(systemName: symbol)
                .font(.system(size: centralContentDiameter * 0.45, weight: .medium))
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.9))
                .ringCenterDepth(scale: centralContentDiameter / 60)
        }
        .frame(width: totalDiameter, height: totalDiameter)
        .contentShape(Circle())
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

private enum PracticeListFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case favorites = "Favorites"
    case meditation = "Meditation"
    case visualisation = "Visualisation"
    case pranayama = "Pranayama"
    case relaxation = "Relaxation"
    case kriya = "Kriya"

    var id: String { rawValue }

    init?(kind: String) {
        guard let filter = Self.allCases.first(where: { $0.kind == kind }) else {
            return nil
        }
        self = filter
    }

    var kind: String? {
        switch self {
        case .all, .favorites: nil
        case .meditation: "meditation"
        case .visualisation: "visualisation"
        case .pranayama: "pranayama"
        case .relaxation: "relaxation"
        case .kriya: "kriya"
        }
    }
}

private enum PracticeDaySlot: String {
    case dawn, morning, midday, afternoon, evening, night

    static func current(date: Date = Date()) -> Self {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<6: .dawn
        case 6..<11: .morning
        case 11..<14: .midday
        case 14..<17: .afternoon
        case 17..<21: .evening
        default: .night
        }
    }

    var displayName: String {
        switch self {
        case .dawn: "Dawn"
        case .morning: "Morning"
        case .midday: "Midday"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .night: "Night"
        }
    }

    var guidance: String {
        switch self {
        case .dawn: "Quiet clarity before the day begins"
        case .morning: "Awaken attention and steady energy"
        case .midday: "Cool intensity and return to centre"
        case .afternoon: "Settle movement and restore focus"
        case .evening: "Release the day and turn inward"
        case .night: "Soften effort and prepare for rest"
        }
    }

    var symbol: String {
        switch self {
        case .dawn: "sun.horizon"
        case .morning: "sun.max"
        case .midday: "sun.max.fill"
        case .afternoon: "sun.haze"
        case .evening: "sunset"
        case .night: "moon.stars"
        }
    }
}

extension View {
    func practiceCard(cornerRadius: CGFloat = 22) -> some View {
        modifier(PracticeCardModifier(cornerRadius: cornerRadius))
    }
}

private struct PracticeCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @ObservedObject private var effectManager = EffectManager.shared

    func body(content: Content) -> some View {
        content
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .glassCardStyle(cornerRadius: cornerRadius)
            .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
    }
}

func kindDisplayName(_ kind: String) -> String {
    switch kind {
    case "meditation": "Meditation"
    case "visualisation": "Visualisation"
    case "pranayama": "Breath"
    case "relaxation": "Relaxation"
    case "kriya": "Kriya"
    default: kind.capitalized
    }
}

func practiceDuration(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let remainder = seconds % 60
    return remainder == 0 ? "\(minutes) min" : "\(minutes):\(String(format: "%02d", remainder))"
}
