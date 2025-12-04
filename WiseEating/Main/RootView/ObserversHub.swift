import SwiftUI
import SwiftData
import Combine

struct ObserversHub: View {
    
    @ObservedObject private var aiManager = AIManager.shared
    @Binding var isAIGenerating: Bool
    
    // MARK: – Входни данни
    let profiles: [Profile]
    let settings: [UserSettings]
    let timer: Publishers.Autoconnect<Timer.TimerPublisher>

    // Drawer/Profile
    @Binding var isProfilesDrawerVisible: Bool
    @Binding var profilesMenuState: MenuState
    @Binding var profilesDrawerContent: RootView.ProfilesDrawerContent
    @Binding var navBarIsHidden: Bool
    @Binding var showMultiSelection: Bool
    @Binding var selectedProfile: Profile?
    @Binding var selectedProfiles: [Profile]
    @Binding var isPresentingNewProfile: Bool
    @Binding var editingProfile: Profile?
    @Binding var profileForHistoryView: Profile?
    @Binding var isPresentingProfileWizard: Bool

    // Tabs & Search
    @Binding var selectedTab: AppTab
    @Binding var previousTab: AppTab
    @Binding var isSearching: Bool
    @Binding var searchText: String
    @FocusState.Binding var isSearchFieldFocused: Bool
    @Binding var isSearchButtonVisible: Bool
    @Binding var menuState: MenuState

    // Nutrition/Training
    @Binding var hasNewNutrition: Bool
    @Binding var hasNewTraining: Bool
    @Binding var nutritionChosenDate: Date
    @Binding var trainingChosenDate: Date
    @Binding var launchMealName: String?
    @Binding var launchTrainingName: String?
    @Binding var nutritionSelectedMealID: Meal.ID?

    // AI
    var coordinator: NavigationCoordinator
    @Binding var hasUnreadAINotifications: Bool
    @Binding var hasUnreadBadgeNotifications: Bool

    @Binding var isShowingDailyAIGenerator: Bool

    // Keyboard
    @Binding var keyboardHeight: CGFloat

    // Callbacks
    var onActivateSearch: () -> Void
    var onDismissSearch: () -> Void
    var onHideSearchButton: () -> Void
    var onShowSearchButton: () -> Void
    var onUpdateBackgroundSnapshot: () -> Void
    var onCheckUnreadAI: () async -> Void
    var onCheckUnreadBadges: () async -> Void
    
    // ✅ ДОБАВЕНО: Callback за отваряне на абонаментите
    var onOpenSubscriptionFlow: () -> Void
    
    init(
          profiles: [Profile],
          settings: [UserSettings],
          timer: Publishers.Autoconnect<Timer.TimerPublisher>,
          isProfilesDrawerVisible: Binding<Bool>,
          profilesMenuState: Binding<MenuState>,
          profilesDrawerContent: Binding<RootView.ProfilesDrawerContent>,
          navBarIsHidden: Binding<Bool>,
          showMultiSelection: Binding<Bool>,
          selectedProfile: Binding<Profile?>,
          selectedProfiles: Binding<[Profile]>,
          isPresentingNewProfile: Binding<Bool>,
          editingProfile: Binding<Profile?>,
          profileForHistoryView: Binding<Profile?>,
          isPresentingProfileWizard: Binding<Bool>,
          selectedTab: Binding<AppTab>,
          previousTab: Binding<AppTab>,
          isSearching: Binding<Bool>,
          searchText: Binding<String>,
          isSearchFieldFocused: FocusState<Bool>.Binding,
          isSearchButtonVisible: Binding<Bool>,
          menuState: Binding<MenuState>,
          hasNewNutrition: Binding<Bool>,
          hasNewTraining: Binding<Bool>,
          nutritionChosenDate: Binding<Date>,
          trainingChosenDate: Binding<Date>,
          launchMealName: Binding<String?>,
          launchTrainingName: Binding<String?>,
          nutritionSelectedMealID: Binding<Meal.ID?>,
          coordinator: NavigationCoordinator,
          hasUnreadAINotifications: Binding<Bool>,
          hasUnreadBadgeNotifications: Binding<Bool>,
          isShowingDailyAIGenerator: Binding<Bool>,
          isAIGenerating: Binding<Bool>,
          keyboardHeight: Binding<CGFloat>,
          onActivateSearch: @escaping () -> Void,
          onDismissSearch: @escaping () -> Void,
          onHideSearchButton: @escaping () -> Void,
          onShowSearchButton: @escaping () -> Void,
          onUpdateBackgroundSnapshot: @escaping () -> Void,
          onCheckUnreadAI: @escaping () async -> Void,
          onCheckUnreadBadges: @escaping () async -> Void,
          // ✅ ДОБАВЕНО в init
          onOpenSubscriptionFlow: @escaping () -> Void
      ) {
          self.profiles = profiles
          self.settings = settings
          self.timer = timer
          self._isProfilesDrawerVisible = isProfilesDrawerVisible
          self._profilesMenuState = profilesMenuState
          self._profilesDrawerContent = profilesDrawerContent
          self._navBarIsHidden = navBarIsHidden
          self._showMultiSelection = showMultiSelection
          self._selectedProfile = selectedProfile
          self._selectedProfiles = selectedProfiles
          self._isPresentingNewProfile = isPresentingNewProfile
          self._editingProfile = editingProfile
          self._profileForHistoryView = profileForHistoryView
          self._isPresentingProfileWizard = isPresentingProfileWizard
          self._selectedTab = selectedTab
          self._previousTab = previousTab
          self._isSearching = isSearching
          self._searchText = searchText
          self._isSearchFieldFocused = isSearchFieldFocused
          self._isSearchButtonVisible = isSearchButtonVisible
          self._menuState = menuState
          self._hasNewNutrition = hasNewNutrition
          self._hasNewTraining = hasNewTraining
          self._nutritionChosenDate = nutritionChosenDate
          self._trainingChosenDate = trainingChosenDate
          self._launchMealName = launchMealName
          self._launchTrainingName = launchTrainingName
          self._nutritionSelectedMealID = nutritionSelectedMealID
          self.coordinator = coordinator
          self._hasUnreadAINotifications = hasUnreadAINotifications
          self._hasUnreadBadgeNotifications = hasUnreadBadgeNotifications
          self._isShowingDailyAIGenerator = isShowingDailyAIGenerator
          self._isAIGenerating = isAIGenerating
          self._keyboardHeight = keyboardHeight
          self.onActivateSearch = onActivateSearch
          self.onDismissSearch = onDismissSearch
          self.onHideSearchButton = onHideSearchButton
          self.onShowSearchButton = onShowSearchButton
          self.onUpdateBackgroundSnapshot = onUpdateBackgroundSnapshot
          self.onCheckUnreadAI = onCheckUnreadAI
          self.onCheckUnreadBadges = onCheckUnreadBadges
          // ✅ Присвояване
          self.onOpenSubscriptionFlow = onOpenSubscriptionFlow
      }
    
    var body: some View {
        Group {
            
            Color.clear
                .onChange(of: aiManager.jobs) { _, newJobs in
                    let isGenerating = newJobs.contains { $0.status == .pending || $0.status == .running }
                    if self.isAIGenerating != isGenerating {
                        self.isAIGenerating = isGenerating
                    }
                }
                .onAppear {
                    let isGenerating = aiManager.isGenerating
                    if self.isAIGenerating != isGenerating {
                        self.isAIGenerating = isGenerating
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .aiJobStatusDidChange)) { _ in
                    let isGenerating = aiManager.isGenerating
                    if self.isAIGenerating != isGenerating {
                        self.isAIGenerating = isGenerating
                    }
                }
            
            TabChangeObserver(
                selectedTab: $selectedTab,
                hasNewNutrition: $hasNewNutrition,
                hasNewTraining: $hasNewTraining,
                isPresentingNewProfile: $isPresentingNewProfile,
                editingProfile: $editingProfile,
                profileForHistoryView: $profileForHistoryView,
                isPresentingProfileWizard: $isPresentingProfileWizard,
                isMealPlanEditorPresented: coordinator.pendingAIPlanPreview != nil,
                isSearchButtonVisible: $isSearchButtonVisible,
                menuState: $menuState,
                navBarIsHidden: $navBarIsHidden,
                isProfilesDrawerVisible: $isProfilesDrawerVisible,
                hasUnreadAINotifications: $hasUnreadAINotifications
            )

            NotificationsObserver(
                profiles: profiles,
                onEditNutrition: { payload in
                    if let profile = profiles.first(where: { $0.calendarID == payload.calendarID }) {
                        selectedProfile = profile
                        selectedTab = .nutrition
                        menuState = .collapsed
                        nutritionChosenDate = payload.date
                        launchMealName = payload.mealName
                    }
                },
                onEditTraining: { payload in
                    if let profile = profiles.first(where: { $0.calendarID == payload.calendarID }) {
                        selectedProfile = profile
                        selectedTab = .training
                        menuState = .collapsed
                        trainingChosenDate = payload.date
                        launchTrainingName = payload.mealName
                    }
                },
                onNewMeal: { payload in
                    if selectedTab != .nutrition {
                        withAnimation {
                            if let profile = profiles.first(where: { $0.calendarID == payload.calendarID }) {
                                selectedProfile = profile
                                hasNewNutrition = true
                                nutritionChosenDate = payload.date
                                launchMealName = payload.mealName
                            }
                        }
                    }
                },
                onNewTraining: { payload in
                    if selectedTab != .training {
                        withAnimation {
                            if let profile = profiles.first(where: { $0.calendarID == payload.calendarID }) {
                                selectedProfile = profile
                                hasNewTraining = true
                                trainingChosenDate = payload.date
                                launchTrainingName = payload.mealName
                            }
                        }
                    }
                },
                onWillEnterForeground: {
                    Task { await onCheckUnreadAI() }
                },
                onUnreadStatusChanged: {
                    Task { await onCheckUnreadAI() }
                },
                onOpenProfilesDrawer: {
                    isProfilesDrawerVisible = true
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        profilesMenuState = .full
                        menuState = .collapsed
                        navBarIsHidden = true
                    }
                },
                onBackgroundChanged: {
                    onUpdateBackgroundSnapshot()
                },
                onCheckUnreadBadges: onCheckUnreadBadges,
                // ✅ ДОБАВЕНО: Подаваме callback-а към NotificationsObserver
                onOpenSubscriptionFlow: onOpenSubscriptionFlow
            )
            
            CoordinatorObserver(
                coordinator: coordinator,
                profiles: profiles,
                selectedProfile: $selectedProfile,
                selectedTab: $selectedTab,
                menuState: $menuState,
                nutritionChosenDate: $nutritionChosenDate,
                nutritionSelectedMealID: $nutritionSelectedMealID,
                trainingChosenDate: $trainingChosenDate,
                launchTrainingName: $launchTrainingName,
                isProfilesDrawerVisible: $isProfilesDrawerVisible,
                profilesMenuState: $profilesMenuState,
                navBarIsHidden: $navBarIsHidden,
                isPresentingNewProfile: $isPresentingNewProfile,
                editingProfile: $editingProfile,
                profileForHistoryView: $profileForHistoryView,
                isPresentingProfileWizard: $isPresentingProfileWizard,
                isShowingDailyAIGenerator: $isShowingDailyAIGenerator,
                onDismissSearch: onDismissSearch
            )

            ProfilesDrawerObserver(
                profilesMenuState: $profilesMenuState,
                isPresentingNewProfile: $isPresentingNewProfile,
                editingProfile: $editingProfile,
                profileForHistoryView: $profileForHistoryView,
                isPresentingProfileWizard: $isPresentingProfileWizard,
                navBarIsHidden: $navBarIsHidden,
                isProfilesDrawerVisible: $isProfilesDrawerVisible,
                onDismissSearch: onDismissSearch
            )

            KeyboardObserver(keyboardHeight: $keyboardHeight)
        }
        .hidden()
    }
}

// MARK: - Small, focused observers

private struct TabChangeObserver: View {
    @Binding var selectedTab: AppTab
    @Binding var hasNewNutrition: Bool
    @Binding var hasNewTraining: Bool
    @Binding var isPresentingNewProfile: Bool
    @Binding var editingProfile: Profile?
    @Binding var profileForHistoryView: Profile?
    @Binding var isPresentingProfileWizard: Bool
    let isMealPlanEditorPresented: Bool
    @Binding var isSearchButtonVisible: Bool
    @Binding var menuState: MenuState
    @Binding var navBarIsHidden: Bool
    @Binding var isProfilesDrawerVisible: Bool
    @Binding var hasUnreadAINotifications: Bool

    var body: some View {
        Color.clear
            .onChange(of: selectedTab) { _, newTab in
                if newTab == .nutrition { hasNewNutrition = false }
                if newTab == .training  { hasNewTraining  = false }

                if newTab == .aiGenerate, hasUnreadAINotifications {
                    Task { await NotificationManager.shared.markAllAINotificationsAsRead() }
                }

                let sheetInitially = isPresentingNewProfile || editingProfile != nil || profileForHistoryView != nil || isPresentingProfileWizard
                if sheetInitially && newTab != .search {
                    withAnimation {
                        isPresentingNewProfile = false
                        editingProfile = nil
                        profileForHistoryView = nil
                        isPresentingProfileWizard = false
                        navBarIsHidden = false
                        isProfilesDrawerVisible = true
                    }
                }

                if isMealPlanEditorPresented && newTab != .search && newTab != .aiGenerate {
                    withAnimation {
                        isPresentingNewProfile = false
                        editingProfile = nil
                        profileForHistoryView = nil
                        isPresentingProfileWizard = false
                        navBarIsHidden = false
                        isProfilesDrawerVisible = true
                    }
                }

                DispatchQueue.main.async {
                    let sheetAfter = isPresentingNewProfile || editingProfile != nil || profileForHistoryView != nil || isPresentingProfileWizard
                    if newTab == .calendar || newTab == .analytics || newTab == .aiGenerate || newTab == .nodes || newTab == .badges || sheetAfter {
                        if !isMealPlanEditorPresented { isSearchButtonVisible = false }
                    } else {
                        isSearchButtonVisible = true
                    }
                }
            }
    }
}

private struct NotificationsObserver: View {
    let profiles: [Profile]
    let onEditNutrition: (EditNutritionPayload) -> Void
    let onEditTraining: (EditNutritionPayload) -> Void
    let onNewMeal: (EditNutritionPayload) -> Void
    let onNewTraining: (EditNutritionPayload) -> Void
    let onWillEnterForeground: () -> Void
    let onUnreadStatusChanged: () -> Void
    let onOpenProfilesDrawer: () -> Void
    let onBackgroundChanged: () -> Void
    let onCheckUnreadBadges: () async -> Void
    
    // ✅ ДОБАВЕНО: Callback параметър
    let onOpenSubscriptionFlow: () -> Void

    var body: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .editNutritionForEvent)) { note in
                guard let payload = note.object as? EditNutritionPayload else { return }
                onEditNutrition(payload)
            }
            .onReceive(NotificationCenter.default.publisher(for: .editTrainingForEvent)) { note in
                guard let payload = note.object as? EditNutritionPayload else { return }
                onEditTraining(payload)
            }
            .onReceive(NotificationCenter.default.publisher(for: .newMealCreated)) { note in
                guard let payload = note.object as? EditNutritionPayload else { return }
                onNewMeal(payload)
            }
            .onReceive(NotificationCenter.default.publisher(for: .newTrainingCreated)) { note in
                guard let payload = note.object as? EditNutritionPayload else { return }
                onNewTraining(payload)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                onWillEnterForeground()
                Task { await onCheckUnreadBadges() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .unreadNotificationStatusChanged)) { _ in
                onUnreadStatusChanged()
                Task { await onCheckUnreadBadges() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openProfilesDrawer)) { _ in
                onOpenProfilesDrawer()
            }
            .onReceive(NotificationCenter.default.publisher(for: .backGroundChanged)) { _ in
                onBackgroundChanged()
            }
            // ✅ ДОБАВЕНО: Слушател за нотификацията
            .onReceive(NotificationCenter.default.publisher(for: .openSubscriptionFlow)) { _ in
                onOpenSubscriptionFlow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .aiJobCompleted)) { notification in
                guard let userInfo = notification.userInfo,
                      let completedJobID = userInfo["jobID"] as? UUID else {
                    return
                }
                
                Task { @MainActor in
                    guard let context = GlobalState.modelContext else {
                        print("🔴 ObserversHub: ModelContext is not available.")
                        return
                    }
                    
                    let descriptor = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.id == completedJobID })
                    guard let job = (try? context.fetch(descriptor))?.first else {
                        print("▶️ ObserversHub: Could not find job \(completedJobID) to check its type.")
                        return
                    }
                    
                    if job.jobType == .nutritionsDetailDailyMealPlan {
                        print("▶️ ObserversHub: Received .aiJobCompleted for job \(completedJobID) [\(job.jobType.rawValue)]. Applying plan now.")
                        _ = await AIManager.shared.applyAndSaveDailyPlan(jobID: completedJobID)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .aiTrainingJobCompleted)) { notification in
                guard let userInfo = notification.userInfo,
                      let completedJobID = userInfo["jobID"] as? UUID else {
                    return
                }
                
                Task { @MainActor in
                    guard let context = GlobalState.modelContext else {
                        print("🔴 ObserversHub: ModelContext is not available.")
                        return
                    }
                    
                    let descriptor = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.id == completedJobID })
                    guard let job = (try? context.fetch(descriptor))?.first else {
                        print("▶️ ObserversHub: Could not find job \(completedJobID) to check its type.")
                        return
                    }
                    
                    if job.jobType == .trainingViewDailyPlan {
                        print("▶️ ObserversHub: Received .aiTrainingJobCompleted for job \(completedJobID) [\(job.jobType.rawValue)]. Applying daily training plan now.")
                        _ = await AIManager.shared.applyAndSaveDailyTrainingPlan(jobID: completedJobID)
                    }
                }
            }
    }
}

private struct CoordinatorObserver: View {
    @ObservedObject var coordinator: NavigationCoordinator
    let profiles: [Profile]

    @Binding var selectedProfile: Profile?
    @Binding var selectedTab: AppTab
    @Binding var menuState: MenuState

    @Binding var nutritionChosenDate: Date
    @Binding var nutritionSelectedMealID: Meal.ID?

    @Binding var trainingChosenDate: Date
    @Binding var launchTrainingName: String?

    @Binding var isProfilesDrawerVisible: Bool
    @Binding var profilesMenuState: MenuState
    @Binding var navBarIsHidden: Bool

    @Binding var isPresentingNewProfile: Bool
    @Binding var editingProfile: Profile?
    @Binding var profileForHistoryView: Profile?
    @Binding var isPresentingProfileWizard: Bool

    @Binding var isShowingDailyAIGenerator: Bool
    
    let onDismissSearch: () -> Void

    var body: some View {
        Color.clear
            .onChange(of: coordinator.pendingBadgeProfileID) { _, newProfileID in
                guard let id = newProfileID else { return }
                
                onDismissSearch()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let profileToSelect = profiles.first(where: { $0.id == id }) {
                        selectedProfile = profileToSelect
                    }
                    
                    withAnimation {
                        selectedTab = .badges
                        menuState = .collapsed
                    }
                    coordinator.pendingBadgeProfileID = nil
                }
            }
            .onChange(of: coordinator.pendingTab) { _, newTab in
                guard let tab = newTab else { return }
                
                onDismissSearch()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation { selectedTab = tab }
                    coordinator.pendingTab = nil
                }
            }
            .onChange(of: coordinator.pendingProfileID) { _, newProfileID in
                guard let id = newProfileID else { return }
                
                onDismissSearch()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let profileToSelect = profiles.first(where: { $0.id == id }) {
                        selectedProfile = profileToSelect
                    }
                    coordinator.pendingProfileID = nil
                }
            }
            .onChange(of: coordinator.pendingShoppingListID) { _, newID in
                guard newID != nil else { return }
                
                onDismissSearch()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation { selectedTab = .shoppingList }
                    menuState = .collapsed
                    coordinator.pendingShoppingListID = nil
                }
            }
            .onChange(of: coordinator.pendingMealID) { _, newID in
                guard let mealID = newID, let mealDate = coordinator.pendingMealDate else { return }
                
                onDismissSearch()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation { selectedTab = .nutrition }
                    nutritionChosenDate = mealDate
                    nutritionSelectedMealID = mealID
                    menuState = .collapsed
                    coordinator.pendingMealID = nil
                    coordinator.pendingMealDate = nil
                }
            }
            .onChange(of: coordinator.pendingTrainingID) { _, newID in
                guard newID != nil,
                      let trainingDate = coordinator.pendingTrainingDate,
                      let trainingName = coordinator.pendingTrainingName else { return }
                
                onDismissSearch()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation { selectedTab = .training }
                    trainingChosenDate = trainingDate
                    launchTrainingName = trainingName
                    menuState = .collapsed
                    coordinator.pendingTrainingID = nil
                    coordinator.pendingTrainingDate = nil
                    coordinator.pendingTrainingName = nil
                }
            }
            .onChange(of: coordinator.pendingApplyDailyMealPlanJobID) { _, jobID in
                guard let id = jobID else { return }
                
                onDismissSearch()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        selectedTab = .nutrition
                    }
                    menuState = .collapsed
                    nutritionChosenDate = Date()
                }
                
                Task {
                    _ = await AIManager.shared.applyAndSaveDailyPlan(jobID: id)
                    coordinator.pendingApplyDailyMealPlanJobID = nil
                }
            }
            .onChange(of: coordinator.pendingApplyDailyTreaningPlanJobID) { _, jobID in
                guard let id = jobID else { return }
                
                onDismissSearch()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        selectedTab = .training
                    }
                    menuState = .collapsed
                    trainingChosenDate = Date()
                }

                Task {
                    _ = await AIManager.shared.applyAndSaveDailyTrainingPlan(jobID: id)
                    coordinator.pendingApplyDailyTreaningPlanJobID = nil
                }
            }
            .onChange(of: coordinator.sourceAIGenerationJobID) { _, newID in
                
                if newID != nil {
                    onDismissSearch()
                }
                
                 guard let jobID = newID, let context = GlobalState.modelContext else {
                     coordinator.pendingAIPlanPreview = nil
                     coordinator.profileForPendingAIPlan = nil
                     coordinator.sourceAIGenerationJobID = nil
                     coordinator.pendingAIPlanJobType = nil
                     coordinator.pendingAIFoodDetailResponse = nil
                     coordinator.sourceAIFoodDetailJobID = nil
                     coordinator.pendingAIRecipe = nil
                     coordinator.sourceAIRecipeJobID = nil
                     coordinator.pendingAIMenu = nil
                     coordinator.sourceAIMenuJobID = nil
                     coordinator.pendingAIExerciseDetailResponse = nil
                     coordinator.sourceAIExerciseDetailJobID = nil
                     coordinator.pendingAIDietResponse = nil
                     coordinator.sourceAIDietJobID = nil
                     coordinator.pendingAIDietWireResponse = nil
                     coordinator.pendingAITrainingPlan = nil
                     coordinator.sourceAITrainingPlanJobID = nil
                     coordinator.pendingAIWorkout = nil
                     coordinator.sourceAIWorkoutJobID = nil
                     return
                 }

                 let descriptor = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.id == jobID })
                 guard let job = (try? context.fetch(descriptor))?.first else {
                     coordinator.sourceAIGenerationJobID = nil
                     return
                 }

                 switch job.jobType {
                 case .foodItemDetail:
                     if #available(iOS 26.0, *), let data = job.resultData, let response = try? JSONDecoder().decode(FoodItemDTO.self, from: data) {
                         if let profile = job.profile, selectedProfile?.id != profile.id {
                             selectedProfile = profile
                         }
                         coordinator.pendingAIFoodDetailResponse = response
                         coordinator.sourceAIFoodDetailJobID = job.id
                     } else {
                         coordinator.sourceAIGenerationJobID = nil
                     }
                 case .recipeGeneration:
                     guard #available(iOS 26.0, *),
                           let data = job.resultData,
                           let payload = try? JSONDecoder().decode(ResolvedRecipeResponseDTO.self, from: data),
                           let recipeName = job.inputParameters?.foodNameToGenerate else {
                         print("❌ Failed to decode ResolvedRecipeResponseDTO or get recipe name.")
                         coordinator.sourceAIGenerationJobID = nil
                         return
                     }

                     if let profile = job.profile, selectedProfile?.id != profile.id {
                         selectedProfile = profile
                     }
                   
                     let foodCopy = FoodItemCopy(from: payload, recipeName: recipeName, context: context)
                     
                     coordinator.pendingAIRecipe = foodCopy
                     coordinator.sourceAIRecipeJobID = job.id
                     coordinator.profileForPendingAIPlan = job.profile
                     
                 case .menuGeneration:
                     guard #available(iOS 26.0, *),
                           let data = job.resultData,
                           let payload = try? JSONDecoder().decode(ResolvedRecipeResponseDTO.self, from: data),
                           let menuName = payload.name else {
                         print("❌ Failed to decode ResolvedRecipeResponseDTO or get menu name for menu generation.")
                         coordinator.sourceAIGenerationJobID = nil
                         return
                     }

                     if let profile = job.profile, selectedProfile?.id != profile.id {
                         selectedProfile = profile
                     }
                     
                     let foodCopy = FoodItemCopy(from: payload, menuName: menuName, context: context)
                     
                     coordinator.pendingAIMenu = foodCopy
                     coordinator.sourceAIMenuJobID = job.id
                     coordinator.profileForPendingAIPlan = job.profile
                     
                 case .mealPlan, .dailyMealPlan, .nutritionsDetailDailyMealPlan:
                     if let preview = job.result, let profile = job.profile {
                         if selectedProfile?.id != profile.id {
                             selectedProfile = profile
                         }
                         coordinator.pendingAIPlanPreview = preview
                         coordinator.profileForPendingAIPlan = profile
                         coordinator.pendingAIPlanJobType = job.jobType
                     } else {
                         coordinator.sourceAIGenerationJobID = nil
                     }
                 case .exerciseDetail:
                     guard #available(iOS 26.0, *),
                           let data = job.resultData,
                           let response = try? JSONDecoder().decode(ExerciseItemDTO.self, from: data) else {
                         print("❌ Failed to decode ExerciseItemDTO or OS version is too old.")
                         return
                     }
                     
                     withAnimation {
                         coordinator.pendingAIExerciseDetailResponse = response
                         coordinator.sourceAIExerciseDetailJobID = job.id
                     }
                 case .dietGeneration:
                     guard #available(iOS 26.0, *),
                              let data = job.resultData
                        else {
                            print("❌ Diet job has no result data or OS too old.")
                            coordinator.sourceAIGenerationJobID = nil
                            return
                        }

                        guard let wire = try? JSONDecoder().decode(AIDietResponseWireDTO.self, from: data) else {
                            print("❌ Failed to decode AIDietResponseWireDTO for diet generation job.")
                            coordinator.sourceAIGenerationJobID = nil
                            return
                        }
                        
                        if let profile = job.profile, selectedProfile?.id != profile.id {
                            selectedProfile = profile
                        }
                        coordinator.pendingAIDietWireResponse = wire
                        coordinator.sourceAIDietJobID = job.id
                        coordinator.profileForPendingAIPlan = job.profile
                 
                 case .trainingPlan:
                     guard #available(iOS 26.0, *),
                           let data = job.resultData,
                           let draft = try? JSONDecoder().decode(TrainingPlanDraft.self, from: data) else {
                         print("❌ Failed to decode TrainingPlanDraft from job result for .trainingPlan.")
                         coordinator.sourceAIGenerationJobID = nil
                         return
                     }
                     
                     withAnimation {
                         coordinator.pendingAITrainingPlan = draft
                         coordinator.sourceAITrainingPlanJobID = job.id
                         coordinator.profileForPendingAIPlan = job.profile
                         coordinator.pendingAIPlanJobType = .trainingPlan
                     }

                 case .trainingViewDailyPlan, .dailyTreiningPlan:
                     guard #available(iOS 26.0, *),
                           let data = job.resultData,
                           let draft = try? JSONDecoder().decode(TrainingPlanDraft.self, from: data) else {
                         print("❌ Failed to decode TrainingPlanDraft from job result for daily plan.")
                         coordinator.sourceAIGenerationJobID = nil
                         return
                     }
                     
                     withAnimation {
                         coordinator.pendingAITrainingPlan = draft
                         coordinator.sourceAITrainingPlanJobID = job.id
                         coordinator.profileForPendingAIPlan = job.profile
                         coordinator.pendingAIPlanJobType = job.jobType
                     }
                 
                 case .workoutGeneration:
                     guard #available(iOS 26.0, *),
                           let data = job.resultData,
                           let dto = try? JSONDecoder().decode(ResolvedWorkoutResponseDTO.self, from: data)
                     else {
                         print("❌ Failed to decode ResolvedWorkoutResponseDTO for workout job.")
                         coordinator.sourceAIGenerationJobID = nil
                         return
                     }
                     
                     let exerciseIDs = dto.exercises.map { $0.exerciseID }
                     
                     let descriptor = FetchDescriptor<ExerciseItem>(predicate: #Predicate { exerciseIDs.contains($0.id) })
                     guard let fetchedItems = try? context.fetch(descriptor) else {
                         print("❌ Could not fetch exercises for workout DTO.")
                         coordinator.sourceAIGenerationJobID = nil
                         return
                     }
                     let itemMap = Dictionary(uniqueKeysWithValues: fetchedItems.map { ($0.id, $0) })
                     
                     let links: [ExerciseLinkCopy] = dto.exercises.compactMap { resolvedExercise -> ExerciseLinkCopy? in
                         guard let exerciseItem = itemMap[resolvedExercise.exerciseID] else {
                             return nil
                         }
                         let exerciseCopy = ExerciseItemCopy(from: exerciseItem)
                         return ExerciseLinkCopy(exercise: exerciseCopy, durationMinutes: resolvedExercise.durationMinutes)
                     }
                     
                     let workoutCopy = ExerciseItemCopy(from: dto, links: links)
                     
                     withAnimation {
                         coordinator.pendingAIWorkout = workoutCopy
                         coordinator.sourceAIWorkoutJobID = job.id
                         coordinator.profileForPendingAIPlan = job.profile
                     }
                     
                 case .createFoodWithAI, .createExerciseWithAI:
                     print("Handled in specific editors, not here.")
                 }
             }
            .onChange(of: coordinator.triggerDailyAIGeneratorForProfile) { _, profile in
                if let profileToUse = profile {
                    if selectedProfile?.id != profileToUse.id { selectedProfile = profileToUse }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation { isShowingDailyAIGenerator = true }
                    }
                    coordinator.triggerDailyAIGeneratorForProfile = nil
                }
            }
    }
}

private struct ProfilesDrawerObserver: View {
    @Binding var profilesMenuState: MenuState
    @Binding var isPresentingNewProfile: Bool
    @Binding var editingProfile: Profile?
    @Binding var profileForHistoryView: Profile?
    @Binding var isPresentingProfileWizard: Bool
    @Binding var navBarIsHidden: Bool
    @Binding var isProfilesDrawerVisible: Bool

    var onDismissSearch: () -> Void

    var body: some View {
        Color.clear
            .onChange(of: profilesMenuState) { _, newState in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    if newState == .collapsed {
                        let showEditorOrWizard = isPresentingNewProfile || editingProfile != nil || profileForHistoryView != nil || isPresentingProfileWizard
                        if !showEditorOrWizard {
                            navBarIsHidden = false
                            isProfilesDrawerVisible = false
                        }
                    } else if newState == .full {
                        navBarIsHidden = true
                        onDismissSearch()
                    }
                }
            }
    }
}

private struct KeyboardObserver: View {
    @Binding var keyboardHeight: CGFloat

    var body: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                guard let userInfo = notification.userInfo,
                      let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                keyboardHeight = keyboardFrame.height
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
    }
}
