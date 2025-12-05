import SwiftUI
import EventKit
import SwiftData
import NaturalLanguage

struct RootView: View {
    @AppStorage("hasShownInitialSubscription") private var hasShownInitialSubscription: Bool = false

    @Environment(\.safeAreaInsets) private var safeAreaInsets
    private var headerTopPadding: CGFloat { safeAreaInsets.top }
    @State private var hasUnreadBadgeNotifications: Bool = false

    enum ProfilesDrawerContent { case profiles, notifications }
    
    // ПРОМЯНА 1: Премахваме .notificationsDenied от enum-а, тъй като вече не блокираме приложението за това.
    enum PermissionState { case checking, granted, calendarDenied }
    
    @State private var isAIGenerating: Bool = false
    @State private var permissionState: PermissionState = .checking
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var navBarIsHiden: Bool = false

    @Query private var allVitamins: [Vitamin]
    @Query private var allMinerals: [Mineral]

    @State private var hasNewNutrition: Bool = false
    @State private var launchDate: Date? = nil
    @State private var launchMealName: String? = nil
    @State private var hasNewTraining: Bool = false
    @State private var launchTrainingName: String? = nil
    let timer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    @State private var nutritionChosenDate: Date = Date()
    @State private var trainingChosenDate: Date = Date()
    @State private var nutritionSelectedMealID: Meal.ID? = nil

    @State private var pinnedFromDateSingle: Date = Date()
    @State private var pinnedEventsSingle: [EventDescriptor] = []

    @AppStorage("lastSelectedTabRoot") private var selectedTab: AppTab = .nutrition
    @AppStorage("lastPreviousTabRoot") private var previousTab: AppTab = .nutrition
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var menuState: MenuState = .collapsed
    @State private var selectedTabDraggableMenuView = 0

    @State private var selectedNutrientTab = 0

    @FocusState private var isSearchFieldFocused: Bool
    @State private var keyboardHeight: CGFloat = 0

    @State private var isPresentingNewProfile = false
    @State private var editingProfile: Profile? = nil
    @State private var profileForHistoryView: Profile?

    @State private var editorState: ThemeEditorState? = nil

    @State private var isPresentingNewFood = false
    @State private var editingFood: FoodItem? = nil
    @State private var dublicateFood: FoodItemCopy? = nil
    @State private var dublicateRecipe: FoodItemCopy? = nil
    @State private var isPresentingNewRecipe = false
    @State private var editingRecipe: FoodItem? = nil
    @State private var detailedFood: FoodItem? = nil

    @AppStorage("showMultiSelection") private var showMultiSelection: Bool = false

    @Query private var profiles: [Profile]
    @Query private var settings: [UserSettings]

    @State private var selectedProfile: Profile?
    @State private var selectedProfiles: [Profile] = []

    @StateObject private var coordinator = NavigationCoordinator.shared

    @StateObject private var foodListVM = FoodListVM()
    @StateObject private var exerciseListVM = ExerciseListVM()

    private let localSearchTabs: [AppTab] = [.storage, .foods, .nutrition]

    @ObservedObject var effectManager = EffectManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var isProfilesDrawerVisible: Bool = false
    @State private var profilesMenuState: MenuState = .collapsed
    @State private var profilesDrawerContent: ProfilesDrawerContent = .profiles
    @State private var isSearchButtonVisible: Bool = true

    @State private var isPresentingProfileWizard = false

    @State private var aiGenerationMenuState: MenuState = .collapsed

    @State private var hasUnreadAINotifications: Bool = false
    
    // Novo: opening daily AI generator
    @State private var isShowingDailyAIGenerator = false

    // Helper variables
    private var isMealPlanEditorPresented: Bool { coordinator.pendingAIPlanPreview != nil }
    private var isRecipeEditorPresented: Bool { coordinator.pendingAIRecipe != nil }
    private var isMenuEditorPresented: Bool { coordinator.pendingAIMenu != nil }
    private var isFoodDetailEditorPresented: Bool { coordinator.pendingAIFoodDetailResponse != nil }
    private var isDietEditorPresented: Bool { coordinator.pendingAIDietWireResponse != nil }
    private var isExerciseDetailEditorPresented: Bool { coordinator.pendingAIExerciseDetailResponse != nil }
    private var isTrainingPlanEditorPresented: Bool { coordinator.pendingAITrainingPlan != nil }
    private var isWorkoutEditorPresented: Bool { coordinator.pendingAIWorkout != nil }
    
    private var isAnyAIEditorPresented: Bool {
           isMealPlanEditorPresented || isRecipeEditorPresented || isMenuEditorPresented || isFoodDetailEditorPresented || isDietEditorPresented || isExerciseDetailEditorPresented || isTrainingPlanEditorPresented || isWorkoutEditorPresented
       }

    private func hideSearchButton() { withAnimation { isSearchButtonVisible = false } }
    private func showSearchButton() { withAnimation { isSearchButtonVisible = true } }

    private var visibleTabs: [AppTab] {
        AppTab.allCases.filter { $0 != .search && $0 != .analytics && $0 != .foods && $0 != .exercises && $0 != .nodes && $0 != .badges }
    }

    var body: some View {
        ZStack {
            switch permissionState {
            case .checking:
                ZStack {
                    ThemeBackgroundView().ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                }
                .onAppear(perform: checkPermissions)
                
            case .granted:
                if profiles.isEmpty {
                    ProfileWizardView(isInit: true, onDismiss: { newlyCreatedProfile in
                        if let profile = newlyCreatedProfile {
                            self.selectedProfile = profile
                        }
                        // 👇 След приключване на първоначалния wizard – отваряме Subscriptions (Remove Ads)
                        showInitialSubscriptionIfNeeded()
                    })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    rootViewHierarchy
                        .onAppear {
                            setup()
                            // 👇 Ако wizard не се е отворил (има профили), пак показваме началния Subscription екран
                            showInitialSubscriptionIfNeeded()
                        }
                }
            case .calendarDenied:
                PermissionDeniedView(type: .calendar, onTryAgain: checkPermissions)
                
                // ПРОМЯНА 2: Случаят .notificationsDenied е премахнат, защото вече не блокираме.
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .nutrition { hasNewNutrition = false }
            if newTab == .training { hasNewTraining = false }
            
            if newTab == .aiGenerate {
                if hasUnreadAINotifications {
                    Task {
                        await NotificationManager.shared.markAllAINotificationsAsRead()
                    }
                }
            }
            
            let isSheetPresentedInitially = isPresentingNewProfile || editingProfile != nil || profileForHistoryView != nil || editorState != nil || isPresentingProfileWizard
            
            if isSheetPresentedInitially && newTab != .search {
                withAnimation {
                    isPresentingNewProfile = false
                    editingProfile = nil
                    profileForHistoryView = nil
                    editorState = nil
                    isPresentingProfileWizard = false
                    
                    coordinator.pendingAIPlanPreview = nil
                    coordinator.profileForPendingAIPlan = nil
                    coordinator.sourceAIGenerationJobID = nil
                    
                    navBarIsHiden = false
                    isProfilesDrawerVisible = true
                }
            }
            
            if isAnyAIEditorPresented && newTab != .search && newTab != .aiGenerate {
                withAnimation {
                    coordinator.pendingAIPlanPreview = nil
                    coordinator.profileForPendingAIPlan = nil
                    coordinator.sourceAIGenerationJobID = nil
                    
                    coordinator.pendingAIRecipe = nil
                    coordinator.sourceAIRecipeJobID = nil
                    
                    coordinator.pendingAIMenu = nil
                    coordinator.sourceAIMenuJobID = nil
                    
                    coordinator.pendingAIFoodDetailResponse = nil
                    coordinator.sourceAIFoodDetailJobID = nil
                    
                    coordinator.pendingAIExerciseDetailResponse = nil
                    coordinator.sourceAIExerciseDetailJobID = nil
                    
                    coordinator.pendingAIDietResponse = nil
                    coordinator.pendingAIDietWireResponse = nil
                    coordinator.sourceAIDietJobID = nil
                    
                    coordinator.pendingAITrainingPlan = nil
                    coordinator.sourceAITrainingPlanJobID = nil
                    coordinator.pendingAIPlanJobType = nil
                    
                    coordinator.pendingAIWorkout = nil
                    coordinator.sourceAIWorkoutJobID = nil
                    
                    navBarIsHiden = false
                    isProfilesDrawerVisible = true
                }
            }
            
            
            DispatchQueue.main.async {
                let isSheetPresentedAfterDismissal = isPresentingNewProfile || editingProfile != nil || profileForHistoryView != nil || editorState != nil || isPresentingProfileWizard
                
                if newTab == .calendar || newTab == .analytics || newTab == .aiGenerate || newTab == .nodes || newTab == .badges || isSheetPresentedAfterDismissal {
                    if !isAnyAIEditorPresented {
                        isSearchButtonVisible = false
                    }
                    
                } else {
                    isSearchButtonVisible = true
                }
            }
        }
        .statusBarHidden(true)
        .onChange(of: selectedProfile) { _, newProfile in
            handleProfileChange(newProfile)
            dayProgress = [:]
            nutritionChosenDate = Date()
            trainingChosenDate = Date()
            nutritionSelectedMealID = nil
            
            if let profile = newProfile {
                UsageTrackingManager.shared.logUsage(for: profile)
                Task {
                    await BadgeManager.shared.checkAndAwardBadges(for: profile, using: modelContext)
                }
            }
        }
        .onChange(of: selectedProfiles) { _, newValue in
            Task { @MainActor in CalendarViewModel.shared.updateSelectedCalendars(for: newValue) }
        }
        .onChange(of: profiles) {
            if let sel = selectedProfile, !profiles.contains(where: { $0.id == sel.id }) {
                selectedProfile = nil
            }
        }
        .background(
            ObserversHub(
                profiles: profiles,
                settings: settings,
                timer: timer,
                isProfilesDrawerVisible: $isProfilesDrawerVisible,
                profilesMenuState: $profilesMenuState,
                profilesDrawerContent: $profilesDrawerContent,
                navBarIsHidden: $navBarIsHiden,
                showMultiSelection: $showMultiSelection,
                selectedProfile: $selectedProfile,
                selectedProfiles: $selectedProfiles,
                isPresentingNewProfile: $isPresentingNewProfile,
                editingProfile: $editingProfile,
                profileForHistoryView: $profileForHistoryView,
                isPresentingProfileWizard: $isPresentingProfileWizard,
                selectedTab: $selectedTab,
                previousTab: $previousTab,
                isSearching: $isSearching,
                searchText: $searchText,
                isSearchFieldFocused: $isSearchFieldFocused,
                isSearchButtonVisible: $isSearchButtonVisible,
                menuState: $menuState,
                hasNewNutrition: $hasNewNutrition,
                hasNewTraining: $hasNewTraining,
                nutritionChosenDate: $nutritionChosenDate,
                trainingChosenDate: $trainingChosenDate,
                launchMealName: $launchMealName,
                launchTrainingName: $launchTrainingName,
                nutritionSelectedMealID: $nutritionSelectedMealID,
                coordinator: coordinator,
                hasUnreadAINotifications: $hasUnreadAINotifications,
                hasUnreadBadgeNotifications: $hasUnreadBadgeNotifications,
                isShowingDailyAIGenerator: $isShowingDailyAIGenerator,
                isAIGenerating: $isAIGenerating,
                keyboardHeight: $keyboardHeight,
                onActivateSearch: activateSearch,
                onDismissSearch: dismissSearch,
                onHideSearchButton: hideSearchButton,
                onShowSearchButton: showSearchButton,
                onUpdateBackgroundSnapshot: updateBackgroundSnapshot,
                onCheckUnreadAI: { await checkForUnreadAINotifications() },
                onCheckUnreadBadges: { await checkForUnreadBadgeNotifications() },
                
                // ✅ ДОБАВЕНО: Логика за отваряне на менюто с абонаменти
                onOpenSubscriptionFlow: {
                    dismissSearch()
                    
                    selectedDraggableMenuTab = .subscriptions

                    // 👇 Тук приемам, че имаш case .removeAds в SubscriptionCategory
                    // Ако името е друго – смени го с твоето.
                    selectedSubscriptionCategory = .removeAds

                    withAnimation {
                        profilesMenuState = .collapsed
                        menuState = .full
                    }
                }
            )
        )
    }

    private func checkForUnreadBadgeNotifications() async {
        let unread = await NotificationManager.shared.getUnreadBadgeNotifications()
        if self.hasUnreadBadgeNotifications != !unread.isEmpty {
            self.hasUnreadBadgeNotifications = !unread.isEmpty
        }
    }
    
    // MARK: - Views
    @ViewBuilder
    private var rootViewHierarchy: some View {
        ZStack {
            VStack(spacing: 0) {
                NavigationStack {
                    ZStack { tabContent }
                        .background(backgroundSourceView)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                updateBackgroundSnapshot()
                            }
                        }
                        .onChange(of: themeManager.currentTheme) { _, _ in updateBackgroundSnapshot() }
                }
            }

            let showEditor = isPresentingNewProfile || editingProfile != nil

            if let preview = coordinator.pendingAIPlanPreview,
               let profile = coordinator.profileForPendingAIPlan,
               let jobType = coordinator.pendingAIPlanJobType {
                
                let dismissAction = {
                    withAnimation {
                        coordinator.pendingAIPlanPreview = nil
                        coordinator.profileForPendingAIPlan = nil
                        coordinator.sourceAIGenerationJobID = nil
                        coordinator.pendingAIPlanJobType = nil
                        isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
                        dismissSearch()
                    }
                }

                switch jobType {
                case .mealPlan:
                    MealPlanEditorView(
                        profile: profile,
                        planPreview: preview,
                        sourceAIGenerationJobID: coordinator.sourceAIGenerationJobID,
                        navBarIsHiden: $navBarIsHiden,
                        globalSearchText: $searchText,
                        isSearchFieldFocused: $isSearchFieldFocused,
                        onDismiss: dismissAction
                    )
                    .onAppear {
                        profilesMenuState = .collapsed
                        menuState = .collapsed
                        isSearchButtonVisible = true
                    }
                    .onDisappear {
                        isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
                    }
                    .padding(.top, headerTopPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                case .dailyMealPlan:
                    DailyMealPlanView(
                        profile: profile,
                        planPreview: preview,
                        sourceAIGenerationJobID: coordinator.sourceAIGenerationJobID,
                        onDismiss: dismissAction
                    )
                    .onAppear {
                        profilesMenuState = .collapsed
                        menuState = .collapsed
                        isSearchButtonVisible = false
                    }
                    .onDisappear {
                        isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
                    }
                    .padding(.top, headerTopPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                default:
                    EmptyView()
                }
         
            }
            
            dietEditorLayer
            recipeEditorLayer
            menuEditorLayer
            foodDetailEditorLayer
            exerciseDetailEditorLayer
            trainingPlanEditorLayer
            workoutEditorLayer
            
            if showEditor {
                ProfileEditorView(
                       profile: editingProfile,
                       navBarIsHiden: $navBarIsHiden,
                       isProfilesDrawerVisible: $isProfilesDrawerVisible,
                       menuState: $menuState,
                       onDismiss: { newOrUpdatedProfile in
                           let wasEditingExisting = (editingProfile != nil)

                           withAnimation {
                               isPresentingNewProfile = false
                               isProfilesDrawerVisible = true
                               editingProfile = nil
                               profilesMenuState = .full
                           }

                           guard let profile = newOrUpdatedProfile else { return }

                           if wasEditingExisting {
                               self.selectedProfile = profile
                               if let userSettings = settings.first {
                                   userSettings.lastSelectedProfile = profile
                                   if !showMultiSelection {
                                       self.selectedProfiles = [profile]
                                       userSettings.lastSelectedProfiles = [profile]
                                   }
                                   try? modelContext.save()
                               }
                           } else {
                               let allProfiles: [Profile]
                               if profiles.contains(where: { $0.id == profile.id }) {
                                   allProfiles = profiles
                               } else {
                                   allProfiles = profiles + [profile]
                               }

                               let activeIDs = subscriptionManager.activeProfileIDs(from: allProfiles)
                               let isUnlocked = activeIDs.contains(profile.id)

                               if !isUnlocked {
                                   if let _ = settings.first {
                                       try? modelContext.save()
                                   }
                                   openSubscriptionUpgradeFlow()
                                   return
                               }

                               self.selectedProfile = profile
                               if let userSettings = settings.first {
                                   userSettings.lastSelectedProfile = profile
                                   if !showMultiSelection {
                                       self.selectedProfiles = [profile]
                                       userSettings.lastSelectedProfiles = [profile]
                                   }
                                   try? modelContext.save()
                               }
                           }
                       }
                   )
                .onAppear {
                    isProfilesDrawerVisible = false
                    profilesMenuState = .collapsed
                }
                .onDisappear { navBarIsHiden = false }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if isPresentingProfileWizard {
                ProfileWizardView(
                    isInit: false,
                    onDismiss: { newlyCreatedProfile in
                        withAnimation {
                            isPresentingProfileWizard = false
                            isProfilesDrawerVisible = true
                            profilesMenuState = .full
                        }

                        guard let profile = newlyCreatedProfile else { return }

                        let allProfiles: [Profile]
                        if profiles.contains(where: { $0.id == profile.id }) {
                            allProfiles = profiles
                        } else {
                            allProfiles = profiles + [profile]
                        }

                        let activeIDs = subscriptionManager.activeProfileIDs(from: allProfiles)
                        let isUnlocked = activeIDs.contains(profile.id)

                        if !isUnlocked {
                            if let _ = settings.first {
                                try? modelContext.save()
                            }
                            openSubscriptionUpgradeFlow()
                            return
                        }

                        self.selectedProfile = profile
                        if let userSettings = settings.first {
                            userSettings.lastSelectedProfile = profile
                            if !showMultiSelection {
                                self.selectedProfiles = [profile]
                                userSettings.lastSelectedProfiles = [profile]
                            }
                            try? modelContext.save()
                        }
                    }

                )
                .onAppear {
                    isProfilesDrawerVisible = false
                    profilesMenuState = .collapsed
                }
                .onDisappear { navBarIsHiden = false }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let profile = profileForHistoryView {
                WeightHeightHistoryView(
                    profile: profile,
                    navBarIsHiden: $navBarIsHiden,
                    isProfilesDrawerVisible: $isProfilesDrawerVisible,
                    menuState: $menuState,
                    onDismiss: {
                        withAnimation {
                            profileForHistoryView = nil
                            isProfilesDrawerVisible = true
                            profilesMenuState = .full
                        }
                    }
                )
                .onAppear {
                    isProfilesDrawerVisible = false
                    profilesMenuState = .collapsed
                }
                .onDisappear {
                    isProfilesDrawerVisible = true
                    profilesMenuState = .full
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            if isShowingDailyAIGenerator, let profile = selectedProfile {
                AIDailyMealGeneratorView(
                    profile: profile,
                    date: nutritionChosenDate,
                    meals: nil,
                    onJobScheduled: {},
                    onDismiss: { withAnimation { isShowingDailyAIGenerator = false } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let state = editorState {
                switch state {
                case .new:
                    ThemeEditorView(
                        themeToEdit: nil,
                        navBarIsHiden: $navBarIsHiden,
                        menuState: $menuState,
                        onDismiss: {
                            withAnimation {
                                editorState = nil
                                navBarIsHiden = false
                                menuState = .full
                            }
                        }
                    )
                    .onAppear {
                        navBarIsHiden = true
                        isProfilesDrawerVisible = false
                        profilesMenuState = .collapsed
                        menuState = .collapsed
                    }
                    .onDisappear {
                        menuState = .full
                        navBarIsHiden = false
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))

                case .edit(let theme):
                    ThemeEditorView(
                        themeToEdit: theme,
                        navBarIsHiden: $navBarIsHiden,
                        menuState: $menuState,
                        onDismiss: {
                            withAnimation {
                                editorState = nil
                                navBarIsHiden = false
                                menuState = .full
                            }
                        }
                    )
                    .onAppear {
                        navBarIsHiden = true
                        isProfilesDrawerVisible = false
                        profilesMenuState = .collapsed
                        menuState = .collapsed
                    }
                    .onDisappear {
                        menuState = .full
                        navBarIsHiden = false
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            ZStack(alignment: .bottom) {
                if profilesMenuState == .full {
                    (effectManager.isLightRowTextColor ? Color.black.opacity(0.4) : Color.white.opacity(0.4))
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                profilesMenuState = .collapsed
                                navBarIsHiden = false
                            }
                        }
                }
                
                if menuState == .full {
                    let overlay = effectManager.isLightRowTextColor ? Color.black.opacity(0.4) : Color.white.opacity(0.4)
                    overlay
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                menuState = .collapsed
                            }
                        }
                }
                
                if isProfilesDrawerVisible {
                    DraggableMenuView(
                        menuState: $profilesMenuState,
                        customTopGap: UIScreen.main.bounds.height * 0.2,
                        horizontalContent: { EmptyView() },
                        verticalContent: {
                            switch profilesDrawerContent {
                            case .profiles:
                                ProfileListView(
                                    selectedProfile: $selectedProfile,
                                    selectedProfiles: $selectedProfiles,
                                    isPresentingNewProfile: $isPresentingNewProfile,
                                    editingProfile: $editingProfile,
                                    showMultiSelection: $showMultiSelection,
                                    profileForHistoryView: $profileForHistoryView,
                                    isPresentingWizard: $isPresentingProfileWizard,
                                    selectedTab: $selectedTab,
                                    profilesMenuState: $profilesMenuState,
                                    profilesDrawerContent: $profilesDrawerContent,
                                    hasUnreadBadgeNotifications: $hasUnreadBadgeNotifications,
                                    onRequestedUpgrade: { targetCategory in
                                        selectedSubscriptionCategory = targetCategory
                                        pendingUpgradeCategory = targetCategory
                                        selectedDraggableMenuTab = .subscriptions
                                        withAnimation {
                                            profilesMenuState = .collapsed
                                            menuState = .full
                                        }
                                    }
                                )
                            case .notifications:
                                NotificationHistoryView(
                                    currentDrawerContent: $profilesDrawerContent,
                                    onDismiss: {
                                        profilesMenuState = .collapsed
                                        navBarIsHiden = false
                                    }
                                )
                            }
                        },
                        onStateChange: { _ in },
                        onWillExpand: {
                            dismissKeyboard()
                            searchText = ""
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                if !isSearching && !navBarIsHiden {
                    DraggableMenuView(
                        menuState: $menuState,
                        customTopGap: UIScreen.main.bounds.height * 0.2,
                        horizontalContent: { menuHorizontalContent },
                        verticalContent: { menuVerticalContent },
                        onStateChange: { _ in },
                        onWillExpand: {
                            dismissKeyboard()
                            searchText = ""
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                VStack {
                    Spacer()
                    LiquidTabBar(
                        menuState: $menuState,
                        selectedTab: $selectedTab,
                        isSearching: $isSearching,
                        searchText: $searchText,
                        hasNewNutrition: $hasNewNutrition,
                        hasNewTraining: $hasNewTraining,
                        hasUnreadAINotifications: $hasUnreadAINotifications,
                        navBarIsHiden: $navBarIsHiden,
                        isAIGenerating: $isAIGenerating,
                        isSearchButtonVisible: $isSearchButtonVisible,
                        tabs: visibleTabs,
                        onSearchTapped: activateSearch,
                        onDismissSearchTapped: dismissSearch,
                        isSearchFieldFocused: $isSearchFieldFocused,
                        profilesMenuState: $profilesMenuState,
                        isProfilesDrawerVisible: $isProfilesDrawerVisible
                    )
                }
            }
            .offset(y: isSearching ? -keyboardHeight - 8 : -8)
            .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.8), value: keyboardHeight)
            .ignoresSafeArea(.keyboard)
        }
    }

    private func openSubscriptionUpgradeFlow() {
        guard let targetCategory = subscriptionManager.nextTierForProfileLimit else {
            print("ℹ️ Already at highest subscription tier; cannot upgrade further.")
            return
        }

        selectedSubscriptionCategory = targetCategory
        pendingUpgradeCategory = targetCategory

        selectedDraggableMenuTab = .subscriptions
        withAnimation {
            profilesMenuState = .collapsed
            menuState = .full
        }
    }

    
    @ViewBuilder
    private var backgroundSourceView: some View {
        ThemeBackgroundView().ignoresSafeArea()
    }

    private func updateBackgroundSnapshot() {
        let viewToRender = backgroundSourceView
        effectManager.snapshot = viewToRender.renderAsImage(size: UIScreen.main.bounds.size)

        guard let snapshot = effectManager.snapshot else {
            effectManager.currentGlobalAccentColor = (colorScheme == .dark ? .white : .black)
            return
        }
        Task { @MainActor in
            let calculatedColor = await snapshot.findGlobalAccentColor()
            effectManager.currentGlobalAccentColor = calculatedColor
            effectManager.isLightRowTextColor = calculatedColor.isLight()
        }
    }


    @ViewBuilder
    private var tabContent: some View {
        let tabToDisplay = isSearching ? previousTab : selectedTab
        switch tabToDisplay {
        case .nutrition:
            if let profile = selectedProfile, profiles.contains(where: { $0.id == profile.id }) {
                NutritionsDetailView(
                    profile: profile,
                    globalSearchText: $searchText,
                    chosenDate: $nutritionChosenDate,
                    selectedMealID: $nutritionSelectedMealID,
                    preselectMealName: launchMealName,
                    isSearchFieldFocused: $isSearchFieldFocused,
                    navBarIsHiden: $navBarIsHiden,
                    isSearching: $isSearching,
                    selectedTab: $selectedTab,
                    onInternalFieldFocused: dismissSearch
                )
                .id(profile)
                .onDisappear { launchMealName = nil }
            } else {
                ZStack { }.background(backgroundSourceView)
            }
        case .training:
            if let profile = selectedProfile {
                TrainingView(
                    profile: profile,
                    globalSearchText: $searchText,
                    chosenDate: $trainingChosenDate,
                    preselectTrainingName: launchTrainingName,
                    isSearchFieldFocused: $isSearchFieldFocused,
                    navBarIsHiden: $navBarIsHiden,
                    isSearching: $isSearching,
                    selectedTab: $selectedTab,
                    onInternalFieldFocused: dismissSearch
                )
                .id(profile)
                .onDisappear { launchTrainingName = nil }
            } else {
                ZStack { }.background(backgroundSourceView)
            }
        case .analytics:
            if let profile = selectedProfile, profiles.contains(where: { $0.id == profile.id }) {
                AnalyticsView(profile: profile).id(profile)
            }
        case .foods:
            FoodItemListView(
                vm: foodListVM,
                profile: selectedProfile,
                globalSearchText: $searchText,
                isSearching: $isSearching,
                navBarIsHiden: $navBarIsHiden,
                isProfilesDrawerVisible: $isProfilesDrawerVisible,
                onActivateSearch: activateSearch,
                onDismissSearch: dismissSearch,
                isSearchFieldFocused: $isSearchFieldFocused
            )
            .id(selectedProfile)
        case .calendar:
            if let profile = selectedProfile {
                TwoWayPinnedSingleDayMultiCalendarWrapper(
                    fromDate: $pinnedFromDateSingle,
                    events: $pinnedEventsSingle,
                    profile: profile,
                    goalProgressProvider: { date in goalProgress(on: date) },
                    eventStore: CalendarViewModel.shared.eventStore,
                    onNodesButtonTapped: {
                        withAnimation {
                            self.selectedTab = .nodes
                        }
                    }
                )
                .onAppear { NotificationCenter.default.post(name: .forceCalendarReload, object: nil) }
                .onReceive(timer) { _ in
                    let isSheetPresented = isPresentingNewProfile || editingProfile != nil || profileForHistoryView != nil || editorState != nil || isPresentingProfileWizard
                    if selectedTab == .calendar && !isSheetPresented {
                        NotificationCenter.default.post(name: .forceCalendarReload, object: nil)
                    }
                }
                .ignoresSafeArea(.all)
                .id(selectedProfile)
                .task(id: selectedProfile?.id) {
                    await preloadProgress(weeksRange: 4)
                }
            }
        case .storage:
            if let profile = selectedProfile {
                StorageListView(
                    profile: profile,
                    globalSearchText: $searchText,
                    onShouldActivateGlobalSearch: { self.activateSearch() },
                    onShouldDismissGlobalSearch: { self.dismissSearch() },
                    navBarIsHiden: $navBarIsHiden,
                    isSearching: $isSearching,
                    isSearchFieldFocused: $isSearchFieldFocused
                )
                .id(selectedProfile)
            }
        case .shoppingList:
            if let profile = selectedProfile {
                ShoppingListView(
                    profile: profile,
                    globalSearchText: $searchText,
                    onShouldActivateGlobalSearch: { self.activateSearch() },
                    onShouldDismissGlobalSearch: { self.dismissSearch() },
                    isSearching: $isSearching,
                    isSearchFieldFocused: $isSearchFieldFocused,
                    onHideSearchButton: hideSearchButton,
                    onShowSearchButton: showSearchButton,
                    navBarIsHiden: $navBarIsHiden
                )
                .id(selectedProfile)
            }
        case .search:
            EmptyView()
        case .exercises:
            ExerciseListView(
                vm: exerciseListVM,
                profile: selectedProfile,
                globalSearchText: $searchText,
                isSearching: $isSearching,
                navBarIsHiden: $navBarIsHiden,
                isProfilesDrawerVisible: $isProfilesDrawerVisible,
                onActivateSearch: activateSearch,
                onDismissSearch: dismissSearch,
                isSearchFieldFocused: $isSearchFieldFocused
            )
            .id(selectedProfile)
        case .aiGenerate:
            if let profile = selectedProfile {
                AIGenerationHostView(profile: profile).id(selectedProfile)
            }
        case .nodes:
            if let profile = selectedProfile {
                NodesListView(profile: profile)
            }
        case .badges:
            if let profile = selectedProfile {
                ProfileBadgesView(profile: profile).id(profile)
            }
//        case .test:
//            if #available(iOS 26.0, *) {
//                FoodSearchView(profile: selectedProfile)
//            } else {
//               EmptyView()
//            }
        }
      
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // MARK: - Draggable Menu (Segments + Content)
    // ─────────────────────────────────────────────────────────────────────────────

    private enum DraggableMenuTab: String, CaseIterable, Identifiable {
        case nutrients = "Nutrients"
        case settings = "Settings"
        case subscriptions = "Subs"
        case moreApps = "More Apps"

        var id: String { rawValue }
    }

    private enum NutrientSubTab: String, CaseIterable, Identifiable {
        case vitamins = "Vitamins"
        case minerals = "Minerals"

        var id: String { rawValue }
    }

    @State private var selectedDraggableMenuTab: DraggableMenuTab = .nutrients
    @State private var selectedNutrientSubTab: NutrientSubTab = .vitamins
    @State private var selectedSubscriptionCategory: SubscriptionCategory = .base
    @State private var pendingUpgradeCategory: SubscriptionCategory? = nil

    @ViewBuilder
    private var menuHorizontalContent: some View {
        WrappingSegmentedControl(selection: $selectedDraggableMenuTab, layoutMode: .wrap)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private var menuVerticalContent: some View {
        switch selectedDraggableMenuTab {
        case .nutrients:
            VStack {
                WrappingSegmentedControl(selection: $selectedNutrientSubTab, layoutMode: .wrap)
                    .padding(.horizontal)

                switch selectedNutrientSubTab {
                case .vitamins:
                    VitaminListView(profile: selectedProfile)
                case .minerals:
                    MineralListView(profile: selectedProfile)
                }
            }

        case .settings:
            SettingsView(editorState: $editorState)

        case .subscriptions:
            SubscriptionView(
                selectedCategory: $selectedSubscriptionCategory,
                pendingUpgradeCategory: $pendingUpgradeCategory
            )
        case .moreApps:
            OtherAppsView()
        }
    }
    
    // MARK: - Setup/Helpers
    private func checkPermissions() {
        Task {
            var calendarStatus = CalendarViewModel.shared.isCalendarAccessGranted()
            if !calendarStatus {
                calendarStatus = await CalendarViewModel.shared.requestCalendarAccessIfNeeded()
            }
            guard calendarStatus else { permissionState = .calendarDenied; return }

            var notificationStatus = await NotificationManager.shared.getAuthorizationStatus()
            // ПРОМЯНА 3: Ако статусът е notDetermined, питаме потребителя.
            if notificationStatus == .notDetermined {
                _ = await NotificationManager.shared.requestAuthorization()
                // Изчакваме малко, за да се обнови статусът (по желание, но полезно при бързи преходи)
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            
            // ПРОМЯНА 4: Без значение дали потребителят е дал разрешение или е отказал,
            // ние продължаваме напред към .granted, защото нотификациите са optional.
            permissionState = .granted
        }
    }

    private func activateSearch() {
        previousTab = selectedTab
        selectedTab = .search
        menuState = .collapsed
        isSearching = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { isSearchFieldFocused = true }
    }

    private func dismissSearch() {
        isSearchFieldFocused = false
        searchText = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.8)) {
                isSearching = false
                if selectedTab == .search { selectedTab = previousTab }
            }
        }
    }

    private func dismissKeyboard() { isSearchFieldFocused = false }

    
    private func setup() {
        print("selectedTab", selectedTab, previousTab)
        EmbeddingWarmup.prewarm()
        if selectedTab == .search{
           
            selectedTab = previousTab
        }
        
        let isSheetPresentedAfterDismissal = isPresentingNewProfile || editingProfile != nil || profileForHistoryView != nil || editorState != nil || isPresentingProfileWizard

        if selectedTab == .calendar || selectedTab == .analytics || selectedTab == .aiGenerate || selectedTab == .nodes || selectedTab == .badges || isSheetPresentedAfterDismissal {
            if !isAnyAIEditorPresented {
                  isSearchButtonVisible = false
            }
                  
        } else {
            isSearchButtonVisible = true
        }
        updateBackgroundSnapshot()
        Task { @MainActor in
            CalendarViewModel.shared.reloadCalendars()

            if settings.isEmpty {
                let newSettings = UserSettings()
                modelContext.insert(newSettings)
                try? modelContext.save()
            }
            guard let userSettings = settings.first else { return }

            if let last = userSettings.lastSelectedProfile,
               profiles.contains(where: { $0.id == last.id }) {
                selectedProfile = last
            } else {
                selectedProfile = profiles.first
                userSettings.lastSelectedProfile = selectedProfile
            }

            selectedProfiles = userSettings.lastSelectedProfiles.filter { stored in
                profiles.contains(where: { $0.id == stored.id })
            }

            if selectedProfiles.isEmpty, let primary = selectedProfile {
                selectedProfiles = [primary]
                userSettings.lastSelectedProfiles = selectedProfiles
            }

            try? modelContext.save()
            CalendarViewModel.shared.updateSelectedCalendars(for: selectedProfiles)
        }
    }

    private func handleProfileCountChange(_ newCount: Int) {
        guard newCount > 0 else { return }
        if selectedProfile == nil {
            if let last = settings.first?.lastSelectedProfile,
               profiles.contains(where: { $0.id == last.id }) {
                selectedProfile = last
            } else {
                selectedProfile = profiles.first
            }
        }
        if let current = selectedProfile,
           !selectedProfiles.contains(where: { $0.id == current.id }) {
            selectedProfiles = [current]
        }
        if let us = settings.first {
            us.lastSelectedProfile  = selectedProfile
            us.lastSelectedProfiles = selectedProfiles
            try? modelContext.save()
        }
    }

    private func handleProfileChange(_ newProfile: Profile?) {
        if let new = newProfile, let userSettings = settings.first {
            userSettings.lastSelectedProfile = new
            try? modelContext.save()
        }
    }

    @State private var dayProgress: [DateComponents : Double] = [:]
    private func key(for d: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day], from: d)
    }

    private func goalProgress(on date: Date) -> Double? {
        let k = key(for: date)
        if let ready = dayProgress[k] { return ready }

        Task {
            if let profile = selectedProfile,
               let fresh = await computeProgress(for: date, profile: profile) {
                await MainActor.run { dayProgress[k] = fresh }
            }
        }
        return nil
    }

    private func computeProgress(for date: Date, profile: Profile) async -> Double? {
        let template = profile.meals(for: date)
        let calendarEvents = await CalendarViewModel.shared.meals(forProfile: profile, on: date)
        let meals = mergedMeals(template: template, calendar: calendarEvents)

        let foodsByMeal = Dictionary(uniqueKeysWithValues: meals.map { ($0.id, $0.foods(using: modelContext)) })
        let foods = mergedFoods(foodsByMeal)
        guard !foods.isEmpty else { return nil }

        let totals = nutrientTotals(for: foods)
        let demo = demographicString(for: profile)

        let items =
            profile.priorityMinerals.map {
                var it = NutriItem(mineral: $0, demographic: demo)
                if let mg = totals[it.nutrientID ?? ""] { it.amount = fromMg(mg, to: it.unit) }
                return it
            } +
            profile.priorityVitamins.map {
                var it = NutriItem(vitamin: $0, demographic: demo)
                if let mg = totals[it.nutrientID ?? ""] { it.amount = fromMg(mg, to: it.unit) }
                return it
            }

        guard !items.isEmpty else { return nil }
        let met = items.filter(isGoalMet).count
        return Double(met) / Double(items.count)
    }

    @MainActor
    private func preloadProgress(weeksRange range: Int) async {
        guard let profile = selectedProfile else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var cache: [DateComponents : Double] = [:]

        for w in -range...range {
            if let week = cal.date(byAdding: .day, value: w * 7, to: today) {
                for i in 0..<7 {
                    guard let d = cal.date(byAdding: .day, value: i, to: week) else { continue }
                    if let pr = await computeProgress(for: d, profile: profile) {
                        cache[key(for: d)] = pr
                    }
                }
            }
        }
        dayProgress = cache
    }

    private func showInitialSubscriptionIfNeeded() {
        // Показваме само веднъж – при първо стартиране на приложението
        guard !hasShownInitialSubscription else { return }
        hasShownInitialSubscription = true

        // Отваряме долното меню на таб "Subscriptions"
        selectedDraggableMenuTab = .subscriptions

        // 👇 Тук приемам, че имаш case .removeAds в SubscriptionCategory
        // Ако името е друго – смени го с твоето.
        selectedSubscriptionCategory = .removeAds

        withAnimation {
            profilesMenuState = .collapsed
            menuState = .full
        }
    }

    
    func mergedMeals(template: [Meal], calendar events: [Meal]) -> [Meal] {
        var merged = template
        for ev in events {
            if let idx = merged.firstIndex(where: { $0.name.lowercased() == ev.name.lowercased() }) {
                merged[idx].startTime = ev.startTime
                merged[idx].endTime   = ev.endTime
                merged[idx].notes     = ev.notes
            } else {
                merged.append(ev)
            }
        }
        return merged.sorted { $0.startTime < $1.startTime }
    }

    func mergedFoods(_ meals: [Meal.ID : [FoodItem : Double]]) -> [FoodItem : Double] {
        var merged: [FoodItem : Double] = [:]
        for (_, foods) in meals {
            for (item, g) in foods {
                merged[item, default: 0] += g
            }
        }
        return merged
    }

    func nutrientTotals(for foods: [FoodItem : Double]) -> [String : Double] {
        var sumsMg: [String : Double] = [:]
        let vitIDs = vitaminLabelById.keys.map { "vit_\($0)" }
        let minIDs = mineralLabelById.keys.map { "min_\($0)" }

        for (food, grams) in foods {
            let ref = food.referenceWeightG
            guard ref > 0 else { continue }
            func add(_ id: String) {
                guard let (val, unit) = food.value(of: id) else { return }
                let densityMgPerG = toMg(value: val, unit: unit) / ref
                sumsMg[id, default: 0] += densityMgPerG * grams
            }
            for id in vitIDs { add(id) }
            for id in minIDs { add(id) }
        }
        return sumsMg
    }

    func demographicString(for p: Profile) -> String {
        let isF = p.gender.lowercased().hasPrefix("f")
        if isF {
            if p.isPregnant  { return Demographic.pregnantWomen }
            if p.isLactating { return Demographic.lactatingWomen }
        }
        let m = Calendar.current.dateComponents([.month], from: p.birthday, to: Date()).month ?? 0
        if m < 6  { return Demographic.babies0_6m }
        if m < 12 { return Demographic.babies7_12m }
        switch p.age {
        case 1..<4:   return Demographic.children1_3y
        case 4..<9:   return Demographic.children4_8y
        case 9..<14:  return Demographic.children9_13y
        case 14..<19: return isF ? Demographic.adolescentFemales14_18y
                                 : Demographic.adolescentMales14_18y
        default:
            return isF
                ? (p.age <= 50 ? Demographic.adultWomen19_50y
                               : Demographic.adultWomen51plusY)
                : (p.age <= 50 ? Demographic.adultMen19_50y
                               : Demographic.adultMen51plusY)
        }
    }

    func isGoalMet(_ i: NutriItem) -> Bool {
        if let dn = i.dailyNeed,  i.amount < dn { return false }
        if let ul = i.upperLimit, i.amount > ul { return false }
        return true
    }

    private func checkForUnreadAINotifications() async {
        let unreadAI = await NotificationManager.shared.getUnreadAINotifications()
        self.hasUnreadAINotifications = !unreadAI.isEmpty
    }
}

extension RootView {
    private var recipeEditorLayer: AnyView {
        guard let recipeCopy = coordinator.pendingAIRecipe else { return AnyView(EmptyView()) }
        guard let profile = (coordinator.profileForPendingAIPlan ?? selectedProfile) else {
            return AnyView(EmptyView().task { coordinator.pendingAIRecipe = nil })
        }
        let dismissAction: (FoodItem?) -> Void = { savedItem in
            if savedItem != nil, let jobID = coordinator.sourceAIRecipeJobID {
                Task { @MainActor in await AIManager.shared.deleteJob(byID: jobID) }
            }
            withAnimation {
                coordinator.pendingAIRecipe = nil
                coordinator.sourceAIRecipeJobID = nil
                isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
                dismissSearch()
            }
        }
        return AnyView(
            FoodItemReceptEditorView(
                dubFood: recipeCopy,
                profile: profile,
                globalSearchText: $searchText,
                onDismiss: dismissAction,
                isSearchFieldFocused: $isSearchFieldFocused,
                isAIInit: true
            )
            .onAppear {
                dismissSearch()
                profilesMenuState = .collapsed
                menuState = .collapsed
                isSearchButtonVisible = true
            }
                .onDisappear {
                    isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
                }
                .padding(.top, headerTopPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        )
    }
    
    private var menuEditorLayer: AnyView {
        guard let menuCopy = coordinator.pendingAIMenu else { return AnyView(EmptyView()) }
        guard let profile = (coordinator.profileForPendingAIPlan ?? selectedProfile) else {
            return AnyView(EmptyView().task { coordinator.pendingAIMenu = nil })
        }
        let dismissAction: (FoodItem?) -> Void = { savedItem in
            if savedItem != nil, let jobID = coordinator.sourceAIMenuJobID {
                Task { @MainActor in await AIManager.shared.deleteJob(byID: jobID) }
            }
            withAnimation {
                coordinator.pendingAIMenu = nil
                coordinator.sourceAIMenuJobID = nil
                isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
                dismissSearch()
            }
        }
        return AnyView(
            FoodItemMenuEditorView(
                dubFood: menuCopy,
                profile: profile,
                globalSearchText: $searchText,
                onDismiss: dismissAction,
                isSearchFieldFocused: $isSearchFieldFocused,
                isAIInit: true
            )
            .onAppear {
                dismissSearch()
                profilesMenuState = .collapsed
                menuState = .collapsed
                isSearchButtonVisible = true
            }
                .onDisappear {
                    isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
                }
                .padding(.top, headerTopPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        )
    }
    
    private var foodDetailEditorLayer: AnyView {
        guard let response = coordinator.pendingAIFoodDetailResponse else { return AnyView(EmptyView()) }
        let foodCopy = FoodItemCopy(from: response)
        let dismissAction: (FoodItem?) -> Void = { savedItem in
            if savedItem != nil, let jobID = coordinator.sourceAIFoodDetailJobID {
                Task { @MainActor in
                    let descriptor = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.id == jobID })
                    if let jobToDelete = (try? modelContext.fetch(descriptor))?.first {
                        await AIManager.shared.deleteJob(jobToDelete)
                    }
                }
            }
            withAnimation {
                coordinator.pendingAIFoodDetailResponse = nil
                coordinator.sourceAIFoodDetailJobID = nil
                isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
                dismissSearch()
            }
        }
        guard let profile = (selectedProfile ?? coordinator.profileForPendingAIPlan) else {
            return AnyView(EmptyView().task {
                coordinator.pendingAIFoodDetailResponse = nil
                coordinator.sourceAIFoodDetailJobID = nil
            })
        }
        return AnyView(
            FoodItemEditorView(
                dubFood: foodCopy,
                profile: profile,
                onDismiss: dismissAction,
                isAIInit: true
            )
            .onAppear {
                dismissSearch()
                profilesMenuState = .collapsed
                menuState = .collapsed
                isSearchButtonVisible = false
            }
                .onDisappear {
                    isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
                }
                .padding(.top, headerTopPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        )
    }
    
    private var exerciseDetailEditorLayer: AnyView {
        guard let response = coordinator.pendingAIExerciseDetailResponse else { return AnyView(EmptyView()) }
        let exerciseCopy = ExerciseItemCopy(from: response)
        let dismissAction: (ExerciseItem?) -> Void = { savedItem in
            if savedItem != nil, let jobID = coordinator.sourceAIExerciseDetailJobID {
                Task { @MainActor in await AIManager.shared.deleteJob(byID: jobID) }
            }
            withAnimation {
                dismissSearch()
                coordinator.pendingAIExerciseDetailResponse = nil
                coordinator.sourceAIExerciseDetailJobID = nil
                isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
                dismissSearch()
            }
        }
        guard let profile = (selectedProfile ?? coordinator.profileForPendingAIPlan) else {
            return AnyView(EmptyView().task {
                coordinator.pendingAIExerciseDetailResponse = nil
                coordinator.sourceAIExerciseDetailJobID = nil
            })
        }
        return AnyView(
            ExerciseItemEditorView(
                dubExercise: exerciseCopy,
                isAIInit: true,
                profile: profile,
                onDismiss: dismissAction
            )
            .onAppear {
                dismissSearch()
                menuState = .collapsed
                isSearchButtonVisible = false
            }
                .onDisappear {
                    isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
                }
                .padding(.top, headerTopPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        )
    }
    
    private var dietEditorLayer: AnyView {
        guard let dto = coordinator.pendingAIDietWireResponse else { return AnyView(EmptyView()) }
        let dismissAction: (Diet?) -> Void = { savedItem in
            if savedItem != nil, let jobID = coordinator.sourceAIDietJobID {
                Task { @MainActor in await AIManager.shared.deleteJob(byID: jobID) }
            }
            withAnimation {
                coordinator.pendingAIDietResponse = nil
                coordinator.pendingAIDietWireResponse = nil
                coordinator.sourceAIDietJobID = nil
                isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
                dismissSearch()
            }
        }
        guard let profile = coordinator.profileForPendingAIPlan else {
            return AnyView(EmptyView().task {
                coordinator.pendingAIDietResponse = nil
                coordinator.pendingAIDietWireResponse = nil
                coordinator.sourceAIDietJobID = nil
            })
        }
        return AnyView(
            AddEditDietView(
                wireDTO: dto,
                profile: profile,
                onDismiss: dismissAction,
                globalSearchText: $searchText,
                isSearchFieldFocused: $isSearchFieldFocused,
                onDismissSearch: dismissSearch
            )
            .onAppear {
                dismissSearch()
                profilesMenuState = .collapsed
                menuState = .collapsed
                isSearchButtonVisible = true
            }
                .onDisappear {
                    isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
                }
                .padding(.top, headerTopPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        )
    }
    
    private var trainingPlanEditorLayer: AnyView {
           guard let draft = coordinator.pendingAITrainingPlan,
                 let profile = (coordinator.profileForPendingAIPlan ?? selectedProfile),
                 let jobType = coordinator.pendingAIPlanJobType else {
               return AnyView(EmptyView())
           }

           let view: AnyView
           
           let commonDismissCleanup = {
               withAnimation {
                   coordinator.pendingAITrainingPlan = nil
                   coordinator.sourceAITrainingPlanJobID = nil
                   coordinator.profileForPendingAIPlan = nil
                   coordinator.pendingAIPlanJobType = nil
                   isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
                   dismissSearch()
               }
           }
           
           switch jobType {
           case .trainingPlan:
               let editorDismissAction: (TrainingPlan?) -> Void = { savedPlan in
                   if savedPlan != nil, let jobID = coordinator.sourceAITrainingPlanJobID {
                       Task { @MainActor in await AIManager.shared.deleteJob(byID: jobID) }
                   }
                   commonDismissCleanup()
               }
               
               view = AnyView(
                   TrainingPlanEditorView(
                       profile: profile,
                       planDraft: draft,
                       globalSearchText: $searchText,
                       isSearchFieldFocused: self.$isSearchFieldFocused,
                       onDismiss: editorDismissAction
                   )
                   .onAppear {
                       dismissSearch()
                       profilesMenuState = .collapsed
                       menuState = .collapsed
                       isSearchButtonVisible = true
                   }
                   .onDisappear {
                       isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
                   }
                   .padding(.top, headerTopPadding)
                   .transition(.move(edge: .bottom).combined(with: .opacity))
               )
               
           case .dailyTreiningPlan, .trainingViewDailyPlan:
               let dailyPlanDismissAction = {
                    commonDismissCleanup()
               }
               
               view = AnyView(
                   DailyTrainingPlanView(
                       profile: profile,
                       planPreview: draft,
                       sourceAIGenerationJobID: coordinator.sourceAITrainingPlanJobID,
                       onDismiss: dailyPlanDismissAction
                   )
                   .onAppear {
                       dismissSearch()
                       profilesMenuState = .collapsed
                       menuState = .collapsed
                       isSearchButtonVisible = false
                   }
                   .onDisappear {
                       isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
                   }
                   .padding(.top, headerTopPadding)
                   .transition(.move(edge: .bottom).combined(with: .opacity))
               )
               
           default:
               view = AnyView(EmptyView())
           }

           return AnyView(
               view
                  
           )
       }
    
    private var workoutEditorLayer: AnyView {
         guard let workoutCopy = coordinator.pendingAIWorkout,
               let profile = (coordinator.profileForPendingAIPlan ?? selectedProfile) else {
             return AnyView(EmptyView())
         }

         let dismissAction: (ExerciseItem?) -> Void = { savedItem in
             if savedItem != nil, let jobID = coordinator.sourceAIWorkoutJobID {
                 Task { @MainActor in await AIManager.shared.deleteJob(byID: jobID) }
             }
             withAnimation {
                 coordinator.pendingAIWorkout = nil
                 coordinator.sourceAIWorkoutJobID = nil
                 isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
                 dismissSearch()
             }
         }
         
         return AnyView(
             WorkoutEditorView(
                 dubWorkout: workoutCopy,
                 profile: profile,
                 globalSearchText: $searchText,
                 isSearchFieldFocused: $isSearchFieldFocused,
                 onDismissSearch: dismissSearch,
                 onDismiss: dismissAction
             )
             .onAppear {
                 dismissSearch()
                 profilesMenuState = .collapsed
                 menuState = .collapsed
                 isSearchButtonVisible = true
             }
             .onDisappear {
                 isSearchButtonVisible = !(selectedTab == .aiGenerate || selectedTab == .calendar || selectedTab == .analytics)
             }
             .padding(.top, headerTopPadding)
             .transition(.move(edge: .bottom).combined(with: .opacity))
         )
     }
}

enum EmbeddingWarmup {
    static func prewarm() {
        Task.detached(priority: .background) {
            _ = NLEmbedding.wordEmbedding(for: .english)
            // Or any other NL models you use
        }
    }
}
