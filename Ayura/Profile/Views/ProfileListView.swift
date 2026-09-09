import SwiftUI
import SwiftData

struct ProfileListView: View {
    @ObservedObject private var effectManager = EffectManager.shared
    @ObservedObject private var sleepHealthStore = SleepHealthStore.shared
    @ObservedObject private var liveActivityManager = NextEventLiveActivityManager.shared

    // MARK: – Queries & Dependencies
    @Query private var profiles: [Profile]
    @Query private var userSettings: [UserSettings]
    @Environment(\.modelContext) private var modelContext
    // MARK: – Subscription
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    private let hardMaxProfiles = 12

    // MARK: - Bindings
    @Binding var selectedProfile:   Profile?
    @Binding var editingProfile:    Profile?
    @Binding var isPresentingWizard: Bool
    @Binding var selectedTab: AppTab
    @Binding var profilesMenuState: MenuState
    @Binding var profilesDrawerContent: RootView.ProfilesDrawerContent

    // MARK: – Callbacks
    let onRequestedUpgrade: (SubscriptionCategory) -> Void

    // MARK: - State
    @State private var showingDeleteConfirmation = false
    @State private var profileToDelete: Profile?
    @State private var profileForAIPlan: Profile? = nil
    
    @State private var hasUnreadNotifications: Bool = false
    @State private var showingLiveActivityError = false
    @State private var liveActivityErrorMessage = ""

    // MARK: - Init

    init(
        selectedProfile: Binding<Profile?>,
        editingProfile: Binding<Profile?>,
        isPresentingWizard: Binding<Bool>,
        selectedTab: Binding<AppTab>,
        profilesMenuState: Binding<MenuState>,
        profilesDrawerContent: Binding<RootView.ProfilesDrawerContent>,
        onRequestedUpgrade: @escaping (SubscriptionCategory) -> Void
    ) {
        self._selectedProfile = selectedProfile
        self._editingProfile = editingProfile
        self._isPresentingWizard = isPresentingWizard
        self._selectedTab = selectedTab
        self._profilesMenuState = profilesMenuState
        self._profilesDrawerContent = profilesDrawerContent
        self.onRequestedUpgrade = onRequestedUpgrade
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            topActionButtonsRow
            
            GeometryReader { geo in
                let cardWidth  = geo.size.width
                let cardHeight = geo.size.height

                List {
                    ForEach(profiles) { profile in
                        row(for: profile)
                            .contentShape(Rectangle())
                            .onTapGesture { handleSingleSelection(profile) }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .padding(.bottom, 6)
                            .padding(.top, 6)
                            .padding(.horizontal)
                    }
                    Color.clear
                        .frame(height: 150)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: effectManager.currentGlobalAccentColor, location: 0.01),
                            .init(color: effectManager.currentGlobalAccentColor, location: 0.9),
                            .init(color: .clear, location: 0.95)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(width: cardWidth, height: cardHeight)
            }
        }
        .padding(.top, 10)
        .alert("Delete Profile", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    performDeletion(for: profile)
                }
                profileToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                profileToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete '\(profileToDelete?.name ?? "this profile")'? This action cannot be undone.")
        }
        .alert("Live Activity", isPresented: $showingLiveActivityError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(liveActivityErrorMessage)
        }
        .sheet(item: $profileForAIPlan) { profile in
            AIPlanGenerationView(profile: profile) {
                profileForAIPlan = nil
            }
        }
        .task {
            ensureHealthKitProfileSelection()
            await checkForUnreadNotifications()
            liveActivityManager.refreshStatus()
        }
        .onChange(of: profiles.map(\.id)) { _, _ in
            ensureHealthKitProfileSelection()
        }
        .onChange(of: activeProfileIDs) { _, _ in
            ensureHealthKitProfileSelection()
        }
        .onChange(of: sleepHealthStore.isHealthKitEnabled) { _, isEnabled in
            if isEnabled {
                ensureHealthKitProfileSelection()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await checkForUnreadNotifications()
            }
        }
    }
    
    // MARK: - Notifications

    private func checkForUnreadNotifications() async {
        let unread = await NotificationManager.shared.getUnreadNotifications()
        self.hasUnreadNotifications = !unread.isEmpty
    }
    
    // MARK: - Top Buttons Row

    private var topActionButtonsRow: some View {
        HStack(spacing: 10) {
            Button {
                toggleLiveActivity()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: liveActivityManager.isRunning ? "livephoto.slash" : "livephoto")
                        .font(.title2)
                    Text(liveActivityManager.isRunning ? "Stop" : "Live")
                        .font(.headline)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .glassCardStyle(cornerRadius: 20)
            .disabled(selectedProfile == nil)
            .opacity(selectedProfile == nil ? 0.4 : 1.0)
            .accessibilityLabel(
                liveActivityManager.isRunning
                    ? "Stop next activity Live Activity"
                        : "Start next activity Live Activity"
            )

            Spacer()

            HStack {
                // New profiles always use the guided wizard.
                Button {
                    handleAddProfileTapped()
                } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                        .padding(8)
                }
                .disabled(isAddProfileButtonDisabled)
                .opacity(isAddProfileButtonDisabled ? 0.4 : 1.0)
                .accessibilityLabel("Add profile")
                .accessibilityIdentifier("profile-add-button")

                Divider().frame(height: 25)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                
                Button {
                    withAnimation {
                        selectedTab = .analytics
                        profilesMenuState = .collapsed
                    }
                } label: {
                    Image(systemName: "chart.bar.xaxis").font(.title2).padding(8)
                }

                Divider().frame(height: 25)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                
                Button {
                    withAnimation {
                        profilesDrawerContent = .notifications
                    }
                } label: {
                    if hasUnreadNotifications {
                        Image(systemName: "bell.badge.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.orange, effectManager.currentGlobalAccentColor)
                            .font(.title2)
                            .padding(8)
                    } else {
                        Image(systemName: "bell.fill").font(.title2).padding(8)
                    }
                }
                
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .padding(.horizontal, 4)
            .glassCardStyle(cornerRadius: 20)
        }
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func handleAddProfileTapped() {
        isPresentingWizard = true
    }

    private func toggleLiveActivity() {
        guard let selectedProfile else { return }

        Task {
            do {
                try await liveActivityManager.toggle(for: selectedProfile)
            } catch {
                liveActivityErrorMessage = error.localizedDescription
                showingLiveActivityError = true
            }
        }
    }

    private func formatAge(from birthDate: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year, .month], from: birthDate, to: now)

        let years = ageComponents.year ?? 0
        let months = ageComponents.month ?? 0

        if years >= 2 { return "\(years) y/o" }
        if years == 1 {
            return months == 0
                ? "1 year"
                : (months == 1 ? "1 year & 1 month" : "1 year & \(months) months")
        }
        if months == 0 { return "Under a month" }
        return months == 1 ? "1 month" : "\(months) months"
    }

    @ViewBuilder
    private func row(for profile: Profile) -> some View {
        let isSingleSelected = selectedProfile?.id == profile.id
        let isHealthKitProfile = userSettings.first?.healthKitProfileID == profile.id

        let isImperial = GlobalState.measurementSystem == "Imperial"
        let displayedWeight = isImperial ? UnitConversion.kgToLbs(profile.weight) : profile.weight
        let displayedHeight = isImperial ? UnitConversion.cmToInches(profile.height) : profile.height
        let formattedWeight = UnitConversion.formatDecimal(displayedWeight)
        let formattedHeight = UnitConversion.formatDecimal(displayedHeight)
        let weightUnit = isImperial ? "lbs" : "kg"
        let heightUnit = isImperial ? "in" : "cm"

        let isLocked = isProfileLocked(profile)

        let upgradePlanName: String? = {
            guard isLocked else { return nil }
            switch subscriptionManager.nextTierForProfileLimit {
            case .advance:
                return "Advanced"
            case .premium:
                return "Premium"
            default:
                return nil
            }
        }()

        HStack(spacing: 12) {
            if let data = profile.photoData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle")
                    .font(.system(size: 60))
                    .foregroundColor(effectManager.currentGlobalAccentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.headline)
                        .foregroundColor(effectManager.currentGlobalAccentColor)

                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Age: \(formatAge(from: profile.birthday))")
                    Text("Weight: \(formattedWeight) \(weightUnit)")
                    Text("Height: \(formattedHeight) \(heightUnit)")
                }
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .font(.subheadline)

                if isLocked, let plan = upgradePlanName {
                    Text("Upgrade to the \(plan) plan to unlock and use this profile.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if sleepHealthStore.isHealthKitEnabled {
                    Button {
                        setHealthKitProfile(profile)
                    } label: {
                        Label(
                            isHealthKitProfile ? "HealthKit profile" : "Use HealthKit",
                            systemImage: isHealthKitProfile
                                ? "heart.text.square.fill"
                                : "heart.text.square"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(
                                    isHealthKitProfile
                                        ? effectManager.currentGlobalAccentColor.opacity(0.14)
                                        : .clear
                                )
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    effectManager.currentGlobalAccentColor.opacity(
                                        isHealthKitProfile ? 0.65 : 0.3
                                    ),
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isLocked)
                    .accessibilityLabel(
                        isHealthKitProfile
                            ? "Current HealthKit profile"
                            : "Use HealthKit for \(profile.name)"
                    )
                }
            }

            Spacer()

            if isSingleSelected && !isLocked {
                Image(systemName: "checkmark")
                    .foregroundColor(effectManager.currentGlobalAccentColor)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    (isSingleSelected && !isLocked)
                    ? effectManager.currentGlobalAccentColor
                    : .clear,
                    lineWidth: 2
                )
        )
        .opacity(isLocked ? 0.4 : 1.0)
        .contentShape(Rectangle())
        .glassCardStyle(cornerRadius: 15)
        .accessibilityIdentifier("profile-row-\(profile.name)")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                if #available(iOS 26.0, *) {
                    performDeletion(for: profile)
                } else {
                    self.profileToDelete = profile
                    self.showingDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "trash.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
            }
            .tint(.clear)
            .accessibilityLabel("Delete \(profile.name)")
            
            Button {
                withAnimation {
                    editingProfile = profile
                }
            } label: {
                Image(systemName: "pencil")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
            }
            .tint(.clear)
            .disabled(isLocked)
            .accessibilityLabel("Edit \(profile.name)")
        }
    }

    // MARK: - Next Selected Profile Helper

    /// Връща следващ профил за селекция след изтриване:
    /// - ако текущият селектиран не е изтрит и не е заключен -> запазваме него
    /// - иначе взимаме първия отключен профил, различен от изтрития
    /// - ако няма отключени профили -> връща nil
    private func pickNextUnlockedProfile(excluding deletedID: UUID) -> Profile? {
        // 1) Ако текущият селектиран още съществува и не е заключен – задържаме го
        if let current = selectedProfile,
           current.id != deletedID,
           !isProfileLocked(current) {
            return current
        }

        // 2) Иначе търсим първи отключен профил, различен от изтрития
        return profiles.first(where: { $0.id != deletedID && !isProfileLocked($0) })
    }

    private func performDeletion(for profile: Profile) {
        let profileIDToDelete = profile.id
        let calendarIDToDelete = profile.calendarID

        CalendarViewModel.shared.markProfileAsDeleted(
            profileUUID: profileIDToDelete,
            calendarID: calendarIDToDelete
        )

        // 🔑 НОВО: избираме следващия САМО от отключените профили
        let nextProfile = pickNextUnlockedProfile(excluding: profileIDToDelete)

        // Избираме следващия отключен профил, ако има такъв.
        self.selectedProfile = nextProfile

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { @MainActor in
                await CalendarViewModel.shared.deleteCalendar(withID: calendarIDToDelete)

                do {
                    let writeContext = try CombinedStoreFactory
                        .makeUserWriteContext(from: modelContext.container)
                    guard let storedProfile = try ProfilePersistence.fetch(
                        id: profileIDToDelete,
                        in: writeContext
                    ) else {
                        return
                    }

                    if let settings = try writeContext.fetch(
                        FetchDescriptor<UserSettings>()
                    ).first {
                        if settings.lastSelectedProfile?.id == profileIDToDelete {
                            if let nextID = nextProfile?.id {
                                settings.lastSelectedProfile = try ProfilePersistence
                                    .fetch(id: nextID, in: writeContext)
                            } else {
                                settings.lastSelectedProfile = nil
                            }
                        }
                        if settings.healthKitProfileID == profileIDToDelete {
                            settings.healthKitProfileID = nextProfile?.id
                        }
                    }

                    writeContext.delete(storedProfile)
                    try writeContext.save()
                    AyurvedaConstitutionStore.delete(profileID: profileIDToDelete)
                    await AIManager.shared.fetchJobs()

                    // Drop the combined context's stale registered object;
                    // the durable deletion already happened in the user store.
                    modelContext.rollback()
                    print("✅ Profile and associated data deleted successfully.")
                } catch {
                    print("❗️ Error saving after profile deletion: \(error)")
                }
            }
        }
    }


    private func handleSingleSelection(_ profile: Profile) {
        if isProfileLocked(profile) { return }
        selectedProfile = profile
    }
    
    // MARK: - Active / Locked Profiles

    private var activeProfileIDs: Set<UUID> {
        subscriptionManager.activeProfileIDs(from: profiles)
    }

    private func isProfileLocked(_ profile: Profile) -> Bool {
        !activeProfileIDs.contains(profile.id)
    }

    private func orderedUnlockedProfiles(excluding excludedID: UUID? = nil) -> [Profile] {
        let remainingProfiles = profiles.filter { $0.id != excludedID }
        let remainingActiveIDs = subscriptionManager.activeProfileIDs(
            from: remainingProfiles
        )
        return remainingProfiles
            .filter { remainingActiveIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.updatedAt < rhs.updatedAt
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private func ensureHealthKitProfileSelection() {
        guard sleepHealthStore.isHealthKitEnabled,
              let settings = userSettings.first else { return }
        let unlockedProfiles = orderedUnlockedProfiles()
        let currentIsAvailable = settings.healthKitProfileID.map { selectedID in
            unlockedProfiles.contains { $0.id == selectedID }
        } ?? false

        guard !currentIsAvailable else { return }
        settings.healthKitProfileID = unlockedProfiles.first?.id
        try? modelContext.save()
    }

    private func setHealthKitProfile(_ profile: Profile) {
        guard sleepHealthStore.isHealthKitEnabled,
              !isProfileLocked(profile),
              let settings = userSettings.first,
              settings.healthKitProfileID != profile.id else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            settings.healthKitProfileID = profile.id
        }
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Add Profile Button State

    /// Вече НИКОГА не дизейбълваме бутона – винаги може да се създават профили.
    private var isAddProfileButtonDisabled: Bool {
           profiles.count >= hardMaxProfiles
       }
}
