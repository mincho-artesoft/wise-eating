import SwiftUI
import SwiftData

struct ProfileListView: View {
    @ObservedObject private var effectManager = EffectManager.shared

    // MARK: – Queries & Dependencies
    @Query private var profiles: [Profile]
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
        .sheet(item: $profileForAIPlan) { profile in
            AIPlanGenerationView(profile: profile) {
                profileForAIPlan = nil
            }
        }
        .task {
            await checkForUnreadNotifications()
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
        HStack {
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
        AyurvedaConstitutionStore.delete(profileID: profileIDToDelete)

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
                let jobsForProfile = AIManager.shared.jobs.filter { $0.profile?.id == profileIDToDelete }

                if !jobsForProfile.isEmpty {
                    print("🧠 Profile deletion: Found \(jobsForProfile.count) AI job(s) for profile \(profileIDToDelete). Deleting...")
                    for job in jobsForProfile {
                        await AIManager.shared.deleteJob(job)
                    }
                } else {
                    print("🧠 Profile deletion: No AI jobs found for profile \(profileIDToDelete).")
                }

                await CalendarViewModel.shared.deleteCalendar(withID: calendarIDToDelete)

                if let profileToDeleteInContext = profiles.first(where: { $0.id == profileIDToDelete }) {
                    modelContext.delete(profileToDeleteInContext)
                }

                if let settings = try? modelContext.fetch(FetchDescriptor<UserSettings>()).first {
                    if settings.lastSelectedProfile?.id == profileIDToDelete {
                        settings.lastSelectedProfile = self.selectedProfile
                    }
                }

                do {
                    try modelContext.save()
                    print("✅ Profile and associated data (including AI jobs) deleted successfully after UI update.")
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

    // MARK: - Add Profile Button State

    /// Вече НИКОГА не дизейбълваме бутона – винаги може да се създават профили.
    private var isAddProfileButtonDisabled: Bool {
           profiles.count >= hardMaxProfiles
       }
}
