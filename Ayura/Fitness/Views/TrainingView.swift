import SwiftUI
import SwiftData
import EventKit

struct TrainingView: View {
    @State private var isShowingDeleteNodeConfirmation = false
    @State private var exerciseItemToView: ExerciseItem? = nil
    @State private var nodeToDelete: Node? = nil
    @State private var nodesForDay: [Node] = []
    @State private var presentedNode: PresentedNode? = nil
    @Query private var userSettingsArray: [UserSettings]   // 👈 ДОБАВИ ТОВА
    private var isAIButtonEnabledGlobally: Bool {
        userSettingsArray.first?.isAIButtonEnabled ?? true
    }
    @State private var refreshTrigger = 0
    @State private var isAITapOnCooldown: Bool = false
    // MARK: - AI State
    @ObservedObject private var aiManager = AIManager.shared
    @State private var runningGenerationJobID: UUID? = nil
    @State private var showAIGenerationToast = false
    @State private var toastTimer: Timer? = nil
    @State private var toastProgress: Double = 0.0
    @State private var alertMsg: String = ""
    @State private var showAlert: Bool = false
    
    // --- AI Floating Button: State ---
    @State private var isAIButtonVisible: Bool = true
    @State private var aiButtonOffset: CGSize = .zero
    @State private var aiIsDragging: Bool = false
    @GestureState private var aiGestureDragOffset: CGSize = .zero
    @State private var aiIsPressed: Bool = false
    private let aiButtonPositionKey = "floatingTrainingAIButtonPosition"
    
    @State private var isShowingDailyAIGenerator = false
    
    // --- Prompt State ---
    @Query(sort: \Prompt.creationDate, order: .reverse) private var allPrompts: [Prompt]
    @State private var selectedPromptIDs: Set<Prompt.ID> = []
    private let selectedPromptsKey = "AIDailyTrainingGenerator_SelectedPrompts"
    
    private let pageGap: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    private var ringsPerRow: Int {
        // Ако е Regular (iPad/Landscape Max), показваме 8, иначе 4 за телефони
        return sizeClass == .regular ? 8 : 4
    }
    private let ringSize:      CGFloat = 40
    private let ringSpacing:   CGFloat = 10
    private let labelSpacing:  CGFloat = 6
    private let ringPadding:   CGFloat = 6
    
    private var ringCellWidth:  CGFloat { ringSize + ringPadding * 6 }
    private var labelHeight:    CGFloat { ringSize * 0.18 * 1.25 }
    private var ringCellHeight: CGFloat {
        ringSize + labelSpacing
        + ringSize * 1.25 * 2
        + ringPadding * 2 + 4
    }
    
    @State private var isShowingDeleteExerciseConfirmation = false
    @State private var exerciseToDelete: ExerciseItem? = nil
    
    @State private var trainingPlanDraftForEditor: TrainingPlanDraft? = nil
    
    @State private var scrollToExerciseID: ExerciseItem.ID? = nil
    
    private enum TrainingActionMenuContent {
        case actions
        case newPlanSelection
        case pickExistingPlan
        case selectWorkoutsForPlan(targetPlan: TrainingPlan)
        case selectDestinationForPlan(targetPlan: TrainingPlan, selectedTrainings: [Training])
        case nodes
    }
    
    enum TrainingRingDetailType: Identifiable {
        case workout, totalBurned, netBalance
        var id: Self { self }
    }
    @State private var showingTrainingRingDetail: TrainingRingDetailType? = nil
    @State private var ringDetailMenuState: MenuState = .collapsed
    
    // MARK: - Environment & Managers
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var ctx
    
    // MARK: - Input & Bindings
    let profile: Profile
    @Binding var globalSearchText: String
    @FocusState.Binding var isSearchFieldFocused: Bool
    @Binding var navBarIsHiden: Bool
    @Binding var isSearching: Bool
    let onInternalFieldFocused: () -> Void
    @Binding var selectedTab: AppTab
    
    // MARK: - State
    @Binding var chosenDate: Date
    @State private var dailyTrainings: [Training] = []
    @State private var selectedTrainingID: Training.ID?
    @State private var totalCaloriesConsumedToday: Double = 0.0
    
    // +++ НАЧАЛО НА ПРОМЯНАТА (1/2) +++
    // Добавяме състояние, което да следи ID-то на разпънатия ред.
    @State private var expandedExerciseID: ExerciseItem.ID? = nil
    // +++ КРАЙ НА ПРОМЯНАТА (1/2) +++
    
    @State private var trainingNameToPreselect: String?
    
    @State private var showAllMuscleGroups: Bool = false
    @State private var selectedMuscleGroup: MuscleGroup? = nil {
        didSet {
            exerciseSearchVM.muscleGroupFilter = selectedMuscleGroup
        }
    }
    
    @State private var isRingsPinned: Bool = true
    private func pinKey(for profile: Profile) -> String { "training.ringsPinned.\(profile.id.uuidString)" }
    
    private struct TaskTrigger: Equatable {
        let date: Date
        let updatedAt: Date
    }
    
    // Toolbar
    @State private var currentTimeString: String = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let tFmt = DateFormatter.shortTime
    
    @StateObject private var exerciseSearchVM = ExerciseSearchVM()
    @State private var autosaveTask: Task<Void, Never>? = nil
    
    @State private var hasUnreadNotifications: Bool = false
    
    @State private var isShowingTrainingActionMenu = false
    @State private var trainingActionMenuState: MenuState = .collapsed
    @State private var trainingActionContent: TrainingActionMenuContent = .actions
    
    @State private var isShowingTrainingPlanPicker = false
    @State private var trainingPlanMenuState: MenuState = .collapsed
    @State private var selectedPlanForPreview: TrainingPlan? = nil
    @State private var trainingPlanDaysToAdd: [TrainingPlanDay]? = nil
    @State private var isSavingPlanToCalendar = false
    private enum TrainingAddMode { case overwrite, append }
    
    enum FocusableField: Hashable {
        case exerciseDuration(id: ExerciseItem.ID)
    }
    @FocusState private var focusedField: FocusableField?
    @State private var exerciseDurationTextValues: [ExerciseItem.ID: String] = [:]
    
    @Query private var trainingPlans: [TrainingPlan]
    
    private var filteredTrainingPlans: [TrainingPlan] {
        let profileID = profile.persistentModelID
        return trainingPlans.filter { $0.profile?.persistentModelID == profileID }
    }
    
    init(
        profile: Profile,
        globalSearchText: Binding<String>,
        chosenDate: Binding<Date>,
        preselectTrainingName: String? = nil,
        isSearchFieldFocused: FocusState<Bool>.Binding,
        navBarIsHiden: Binding<Bool>,
        isSearching: Binding<Bool>,
        selectedTab: Binding<AppTab>,
        onInternalFieldFocused: @escaping () -> Void
    ) {
        self.profile = profile
        self._globalSearchText = globalSearchText
        self._chosenDate = chosenDate
        self._isSearchFieldFocused = isSearchFieldFocused
        self._navBarIsHiden = navBarIsHiden
        self._isSearching = isSearching
        self._selectedTab = selectedTab
        self.onInternalFieldFocused = onInternalFieldFocused
        self._trainingNameToPreselect = State(initialValue: preselectTrainingName)
        
        let initialTrainings = profile.trainings(for: chosenDate.wrappedValue)
        self._dailyTrainings = State(initialValue: initialTrainings)
    }
    
    private var isAIButtonCurrentlyVisible: Bool {
        if isSearchFieldFocused { return false }
        if showingTrainingRingDetail != nil { return false }
        if isShowingTrainingActionMenu { return false }
        if isShowingTrainingPlanPicker { return false }
        if trainingPlanDraftForEditor != nil { return false }
        if isShowingDailyAIGenerator { return false }
        if presentedNode != nil { return false }
        if exerciseItemToView != nil { return false }
        return true
    }
    
    private var headerTopPadding: CGFloat {
        -safeAreaInsets.top + 10
    }
    private var currentExercises: [ExerciseItem: Double] {
        guard let id = selectedTrainingID,
              let training = dailyTrainings.first(where: { $0.id == id })
        else { return [:] }
        return training.exercises(using: ctx)
    }
    
    private var selectedWorkoutCaloriesBurned: Double {
        guard !currentExercises.isEmpty else { return 0.0 }
        return currentExercises.reduce(0.0) { acc, pair in
            let (ex, dur) = pair
            guard let met = ex.metValue, met > 0, dur > 0 else { return acc }
            let cpm = (met * 3.5 * profile.weight) / 200.0 // Calories per minute
            return acc + cpm * dur
        }
    }
    
    private var totalCaloriesBurnedToday: Double {
        dailyTrainings.reduce(0.0) { tot, tr in
            let exs = tr.exercises(using: ctx)
            let burn = exs.reduce(0.0) { acc, pair in
                let (ex, dur) = pair
                guard let met = ex.metValue, met > 0, dur > 0 else { return acc }
                let cpm = (met * 3.5 * profile.weight) / 200.0
                return acc + cpm * dur
            }
            return tot + burn
        }
    }
    
    private var netCalorieBalance: Double { totalCaloriesConsumedToday - totalCaloriesBurnedToday }
    private var targetCalories: Double { TDEECalculator.calculate(for: profile) }
    
    private var allMuscleGroups: [MuscleGroup] {
        MuscleGroup.allCases
            .sorted { $0.rawValue < $1.rawValue }
    }
    
    var body: some View {
        ZStack {
            ZStack {
                viewWithLifeCycle
                    .opacity(trainingPlanDraftForEditor == nil ? 1 : 0)
                
                if let exerciseToView = exerciseItemToView {
                    ExerciseItemDetailView(
                        item: exerciseToView,
                        profile: profile,
                        onDismiss: {
                            withAnimation(.easeInOut) {
                                exerciseItemToView = nil
                                navBarIsHiden = false
                            }
                        }
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    .zIndex(20)
                    .onAppear { navBarIsHiden = true }
                }
                
                if let draft = trainingPlanDraftForEditor {
                    TrainingPlanEditorView(
                        profile: profile,
                        planDraft: draft,
                        globalSearchText: $globalSearchText,
                        isSearchFieldFocused: $isSearchFieldFocused,
                        onDismiss: { savedPlan in
                            withAnimation(.easeInOut) {
                                trainingPlanDraftForEditor = nil
                                navBarIsHiden = false
                            }
                        },
                        navBarIsHiden: $navBarIsHiden,
                        onDismissSearch: onInternalFieldFocused
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    .zIndex(10)
                }
                
                if let presented = presentedNode {
                    presentedNodeView(for: presented)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                        .zIndex(15)
                }
                
                if isShowingDailyAIGenerator {
                    AIDailyTrainingGeneratorView(
                        profile: profile,
                        date: chosenDate,
                        trainings: dailyTrainings,
                        onJobScheduled: {
                            triggerAIGenerationToast()
                            withAnimation {
                                isShowingDailyAIGenerator = false
                            }
                        },
                        onDismiss: {
                            withAnimation {
                                isShowingDailyAIGenerator = false
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
                }
            }
            .overlay {
                GeometryReader { geometry in
                    Group {
                        if showAIGenerationToast {
                            aiGenerationToast
                        }
                        if !isSearchFieldFocused &&
                            showingTrainingRingDetail == nil &&
                            !isShowingTrainingActionMenu &&
                            !isShowingTrainingPlanPicker &&
                            trainingPlanDraftForEditor == nil &&
                            !isShowingDailyAIGenerator &&
                            GlobalState.aiAvailability != .deviceNotEligible &&
                            isAIButtonEnabledGlobally{
                            AIButton(geometry: geometry)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .alert("Delete Exercise", isPresented: $isShowingDeleteExerciseConfirmation) {
                Button("Delete", role: .destructive) {
                    if let exercise = exerciseToDelete {
                        withAnimation {
                            delete(exercise: exercise)
                        }
                    }
                    exerciseToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    exerciseToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete '\(exerciseToDelete?.name ?? "this exercise")' from your workout? This action cannot be undone.")
            }
            .confirmationDialog("Add Trainings from Plan", isPresented: .constant(trainingPlanDaysToAdd != nil), titleVisibility: .visible, actions: {
                Button("Add to Existing Workouts") { processTrainingPlanAddition(mode: .append) }
                Button("Overwrite Existing Workouts", role: .destructive) { processTrainingPlanAddition(mode: .overwrite) }
                Button("Cancel", role: .cancel) { trainingPlanDaysToAdd = nil }
            }, message: { Text("This will add workouts for \(trainingPlanDaysToAdd?.count ?? 0) day(s), starting from \(chosenDate.formatted(date: .abbreviated, time: .omitted)). How should workouts for a specific time slot be added?") })
            .onReceive(NotificationCenter.default.publisher(for: .aiTrainingJobCompleted)) { notification in
                loadTrainings(preselect: selectedTrainingID)
            }
            .onAppear(perform: loadAIButtonPosition)
            .alert("AI Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: { Text(alertMsg) }
                .alert("Delete Note", isPresented: $isShowingDeleteNodeConfirmation) {
                    Button("Delete", role: .destructive) {
                        if let node = nodeToDelete {
                            delete(node: node)
                        }
                        nodeToDelete = nil
                    }
                    Button("Cancel", role: .cancel) {
                        nodeToDelete = nil
                    }
                } message: {
                    Text("Are you sure you want to delete this note? This action cannot be undone.")
                }
        }
    }
    
    @ViewBuilder
    private var viewWithLifeCycle: some View {
        ZStack {
            VStack(spacing: 0) {
                userToolbar
                    .padding(.trailing, 50)
                    .padding(.leading, 40)
                    .padding(.horizontal, -20)
                    .padding(.top, headerTopPadding)
                
                UpdatePlanBanner()
                    .if(safeAreaInsets.top != 0) {view in
                        view.padding(.top, -4)
                    }else: { view in
                        view.padding(.top, 8)
                    }
                
                
                WeekCarouselRepresentable(
                    selectedDate: $chosenDate,
                    progressProvider: { date in goalProgress(on: date) }
                )
                .frame(height: 80)
                .padding(.bottom, 35)
                .onChange(of: chosenDate) {
                    loadTrainings(preselect: selectedTrainingID)
                }
                
                VStack(spacing: 0) {
                    TrainingTimelineView(
                        trainings: $dailyTrainings,
                        selectedTrainingID: $selectedTrainingID,
                        showOnlySelected: true,
                        onTimeChanged: scheduleAutosave
                    )
                    .frame(height: 80)
                    .padding(.horizontal, 20)
                    
                    if isRingsPinned {
                        TrainingSummaryView(
                            selectedWorkoutCaloriesBurned: selectedWorkoutCaloriesBurned,
                            totalCaloriesBurnedToday: totalCaloriesBurnedToday,
                            targetCalories: targetCalories,
                            netCalorieBalance: netCalorieBalance,
                            totalCaloriesConsumedToday: totalCaloriesConsumedToday,
                            isPinned: $isRingsPinned,
                            onTap: { detailType in
                                presentRingDetail(detailType)
                            }
                        )
                        .padding(.top, -40)
                        .transition(.opacity.combined(with: .scale))
                    }
                    
                    ScrollViewReader { proxy in
                        List {
                            if !isRingsPinned {
                                TrainingSummaryView(
                                    selectedWorkoutCaloriesBurned: selectedWorkoutCaloriesBurned,
                                    totalCaloriesBurnedToday: totalCaloriesBurnedToday,
                                    targetCalories: targetCalories,
                                    netCalorieBalance: netCalorieBalance,
                                    totalCaloriesConsumedToday: totalCaloriesConsumedToday,
                                    isPinned: $isRingsPinned,
                                    onTap: { detailType in
                                        presentRingDetail(detailType)
                                    }
                                )
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                                .padding(.horizontal, -6)
                                .padding(.top, 4)
                            }
                            
                            muscleGroupsSection
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
                            
                            HStack {
                                Text("Exercises")
                                    .font(.headline)
                                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                                Spacer()
                                
                                Button("Exercises List") {
                                    onInternalFieldFocused()
                                    selectedTab = .exercises
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .glassCardStyle(cornerRadius: 20)
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                                .buttonStyle(.plain)
                                
                                Button("Load Plan") {
                                    presentTrainingPlanPicker()
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .glassCardStyle(cornerRadius: 20)
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                                .buttonStyle(.plain)
                                
                                Button("Actions") {
                                    presentTrainingActionMenu()
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .glassCardStyle(cornerRadius: 20)
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                                .buttonStyle(.plain)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            
                            let exercises = currentExercises.keys.sorted { $0.name < $1.name }
                            
                            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                                // 👉 Рекламният ред преди упражнението
                                if shouldShowAd(at: index) {
                                    AdRowView()
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6))
                                }
                                
                                SelectedExerciseRowView(
                                    exercise: exercise,
                                    duration: currentExercises[exercise] ?? 15.0,
                                    profile: profile,
                                    onDurationChanged: { newDuration in
                                        update(duration: newDuration, for: exercise)
                                    },
                                    onDelete: {
                                        delete(exercise: exercise)
                                    },
                                    focusedField: $focusedField,
                                    focusCase: .exerciseDuration(id: exercise.id),
                                    expandedExerciseID: $expandedExerciseID
                                )
                                // +++ ДОБАВЕТЕ ТОВА (Context Menu) +++
                                .contextMenu {
                                    Button {
                                        withAnimation(.easeInOut) {
                                            onInternalFieldFocused()
                                            exerciseItemToView = exercise
                                            navBarIsHiden = true
                                        }
                                    } label: {
                                        Label("View Details", systemImage: "info.circle")
                                    }
                                    
                                    Button(role: .destructive) {
                                        if #available(iOS 26.0, *) {
                                            delete(exercise: exercise)
                                        } else {
                                            self.exerciseToDelete = exercise
                                            self.isShowingDeleteExerciseConfirmation = true
                                        }
                                    } label: {
                                        Label("Remove from Workout", systemImage: "trash")
                                    }
                                }
                                // +++ КРАЙ НА ДОБАВКАТА +++
                                .id(exercise.id)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 0, trailing: 6))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        if #available(iOS 26.0, *) {
                                            delete(exercise: exercise)
                                        } else {
                                            self.exerciseToDelete = exercise
                                            self.isShowingDeleteExerciseConfirmation = true
                                        }
                                    } label: {
                                        Image(systemName: "trash.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                                    }
                                    .tint(.clear)
                                }
                            }
                            
                            Color.clear
                                .frame(height: 150)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        .onChange(of: focusedField) { _, newValue in
                            guard let focus = newValue else { return }
                            
                            let itemID: ExerciseItem.ID?
                            switch focus {
                            case .exerciseDuration(let id):
                                itemID = id
                            }
                            
                            if let idToScroll = itemID {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(idToScroll, anchor: .top)
                                    }
                                }
                            }
                        }
                        .onChange(of: scrollToExerciseID) { _, newID in
                            guard let id = newID else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeInOut) {
                                    proxy.scrollTo(id, anchor: .top)
                                }
                                scrollToExerciseID = nil
                            }
                        }
                        .modifier(ListMask(enabled: !showAllMuscleGroups, accent: effectManager.currentGlobalAccentColor))
                        .offset(y: !isRingsPinned ? -44: 0)
                        .padding(.horizontal, 6)
                        .listStyle(.plain)
                        .listRowSpacing(0)
                        .listSectionSpacing(0)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .scrollIndicators(.hidden)
                        .modifier(ListContentMarginsZero())
                        .onAppear {
                            loadAIButtonPosition()
                            
                            let key = pinKey(for: profile)
                            if let saved = UserDefaults.standard.object(forKey: key) as? Bool {
                                isRingsPinned = saved
                            }
                        }
                        .onChange(of: isRingsPinned) { _, newVal in
                            UserDefaults.standard.set(newVal, forKey: pinKey(for: profile))
                        }
                    }
                }
                .animation(.easeInOut, value: selectedTrainingID)
            }
            .onChange(of: globalSearchText) { _, newText in
                exerciseSearchVM.query = newText
            }
            .onChange(of: selectedTrainingID) { _, _ in
                exerciseSearchVM.exclude(Set(currentExercises.keys))
            }
            .onChange(of: dailyTrainings) { _, _ in
                exerciseSearchVM.exclude(Set(currentExercises.keys))
            }
            .onChange(of: ctx) { _, newCtx in
                exerciseSearchVM.attach(context: newCtx)
            }
            
            if isSearchFieldFocused {
                fullScreenSearchResultsView
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
            
            if showingTrainingRingDetail != nil {
                trainingRingDetailOverlay
            }
            
            if isShowingTrainingPlanPicker { trainingPlanPickerOverlay }
            if isShowingTrainingActionMenu { trainingActionMenuOverlay }
        }
        
        .onReceive(timer) { _ in
            self.currentTimeString = Self.tFmt.string(from: Date())
        }
        .task(id: "\(chosenDate)-\(profile.updatedAt)-\(refreshTrigger)") {
            exerciseSearchVM.attach(context: ctx)
            loadTrainings(preselect: selectedTrainingID)
            exerciseSearchVM.query = globalSearchText
            exerciseSearchVM.muscleGroupFilter = selectedMuscleGroup
            exerciseSearchVM.profileAgeInMonths = profile.ageInMonths
            exerciseSearchVM.exclude(Set(currentExercises.keys))
            await loadNodesForDay()
            await fetchAndCalculateDailyIntake()
        }
        .onChange(of: currentExercises) { _, newExercises in
            var newTextValues: [ExerciseItem.ID: String] = [:]
            for (exercise, duration) in newExercises {
                newTextValues[exercise.id] = String(format: "%.0f", duration)
            }
            self.exerciseDurationTextValues = newTextValues
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
    
    private func checkForUnreadNotifications() async {
        let unread = await NotificationManager.shared.getUnreadNotifications()
        self.hasUnreadNotifications = !unread.isEmpty
    }
    
    @ViewBuilder
    private var trainingRingDetailOverlay: some View {
        ZStack {
            if ringDetailMenuState == .full {
                (effectManager.isLightRowTextColor ? Color.black.opacity(0.4) : Color.white.opacity(0.4))
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { dismissRingDetail() }
            }
            DraggableMenuView(
                menuState: $ringDetailMenuState,
                customTopGap: UIScreen.main.bounds.height * 0.2,
                horizontalContent: { EmptyView() },
                verticalContent: {
                    if let detailType = showingTrainingRingDetail {
                        trainingRingDetailContent(for: detailType)
                    }
                },
                onStateChange: { newState in
                    if newState == .collapsed {
                        dismissRingDetail()
                    }
                }
            )
        }
        .edgesIgnoringSafeArea(.all)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    ringDetailMenuState = .full
                }
            }
        }
    }
    
    @ViewBuilder
    private func trainingRingDetailContent(for detailType: TrainingRingDetailType) -> some View {
        
        let onSaveChangesCallback = {
            self.scheduleAutosave()
        }
        
        if let selectedID = selectedTrainingID,
           let trainingIndex = dailyTrainings.firstIndex(where: { $0.id == selectedID }) {
            
            let trainingBinding = $dailyTrainings[trainingIndex]
            
            VStack(spacing: 0) {
                switch detailType {
                case .workout:
                    WorkoutDetailRingView(
                        training: trainingBinding.wrappedValue,
                        onDismiss: dismissRingDetail,
                        profile: profile,
                        onSaveChanges: onSaveChangesCallback
                    )
                case .totalBurned:
                    TotalBurnedDetailRingView(
                        totalCalories: totalCaloriesBurnedToday,
                        trainings: dailyTrainings,
                        profile: profile,
                        onDismiss: dismissRingDetail
                    )
                case .netBalance:
                    NetBalanceDetailRingView(
                        totalConsumed: totalCaloriesConsumedToday,
                        totalBurned: totalCaloriesBurnedToday,
                        netBalance: netCalorieBalance,
                        dailyTrainings: dailyTrainings,
                        onDismiss: dismissRingDetail, profile: profile
                    )
                }
            }
            .id(detailType.id)
            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            
        } else {
            Text("Please select a workout from the timeline.")
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .padding()
        }
    }
    
    
    private func presentRingDetail(_ type: TrainingRingDetailType) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showingTrainingRingDetail = type
            ringDetailMenuState = .full
            navBarIsHiden = true
            if isSearching {
                onInternalFieldFocused()
            }
        }
    }
    
    private func dismissRingDetail() {
        withAnimation(.easeInOut(duration: 0.3)) {
            ringDetailMenuState = .collapsed
            showingTrainingRingDetail = nil
            navBarIsHiden = false
        }
    }
    
    @ViewBuilder
    private var userToolbar: some View {
        HStack {
            Text(currentTimeString)
                .font(.system(size: 16))
                .fontWeight(.medium)
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .onAppear {
                    self.currentTimeString = Self.tFmt.string(from: Date())
                }
            
            Spacer()
            
            Button(action: {
                NotificationCenter.default.post(name: Notification.Name("openProfilesDrawer"), object: nil)
            }) {
                ZStack(alignment: .topTrailing) {
                    if let photoData = profile.photoData, let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else {
                        ZStack {
                            Circle().fill(effectManager.currentGlobalAccentColor.opacity(0.2))
                            if let firstLetter = profile.name.first {
                                Text(String(firstLetter))
                                    .font(.headline)
                                    .foregroundColor(effectManager.currentGlobalAccentColor)
                            }
                        }
                        .frame(width: 40, height: 40)
                    }
                    
                    if hasUnreadNotifications {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 12, height: 12)
                            .offset(x: 1, y: -1)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(effectManager.currentGlobalAccentColor)
        }
    }
    
    @ViewBuilder
    private var trainingActionMenuOverlay: some View {
        ZStack {
            if trainingActionMenuState == .full {
                (effectManager.isLightRowTextColor ? Color.black.opacity(0.4) : Color.white.opacity(0.4))
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { dismissTrainingActionMenu() }
            }
            
            DraggableMenuView(
                menuState: $trainingActionMenuState,
                customTopGap: UIScreen.main.bounds.height * 0.2,
                horizontalContent: { EmptyView() },
                verticalContent: {
                    switch trainingActionContent {
                    case .actions:
                        TrainingActionMenuView(
                            onDismiss: dismissTrainingActionMenu,
                            onCopyToNewPlan: { withAnimation { trainingActionContent = .newPlanSelection } },
                            onAddToExistingPlan: { withAnimation { trainingActionContent = .pickExistingPlan } },
                            onGenerateWithAI: {
                                dismissTrainingActionMenu()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    isShowingDailyAIGenerator = true
                                }
                            },
                            onNodesTapped: {
                                withAnimation { trainingActionContent = .nodes }
                            }
                        )
                    case .newPlanSelection:
                        TrainingSelectionForPlanView(
                            trainings: updatedTrainingsForPicker(),
                            onBack: { withAnimation { trainingActionContent = .actions } },
                            onCancel: dismissTrainingActionMenu,
                            onCreatePlan: { selectedTrainings, planName in
                                let dayDraft = TrainingPlanDayDraft(dayIndex: 1, trainings: selectedTrainings)
                                let draft = TrainingPlanDraft(name: planName, days: [dayDraft])
                                
                                dismissTrainingActionMenu()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(.easeInOut) {
                                        self.trainingPlanDraftForEditor = draft
                                    }
                                }
                            }
                        )
                    case .pickExistingPlan:
                        TrainingPlanPickerView(
                            title: "Add to Existing Plan",
                            dismissButtonLabel: "Back",
                            plans: filteredTrainingPlans,
                            onDismiss: { withAnimation { trainingActionContent = .actions } },
                            onSelectPlan: { plan in
                                withAnimation {
                                    trainingActionContent = .selectWorkoutsForPlan(targetPlan: plan)
                                }
                            }
                        )
                    case .selectWorkoutsForPlan(let targetPlan):
                        TrainingPlanAddWorkoutsView(
                            sourceTrainings: updatedTrainingsForPicker(),
                            onBack: { withAnimation { trainingActionContent = .pickExistingPlan } },
                            onCancel: dismissTrainingActionMenu,
                            onNext: { selected in
                                withAnimation {
                                    trainingActionContent = .selectDestinationForPlan(targetPlan: targetPlan, selectedTrainings: selected)
                                }
                            }
                        )
                    case .selectDestinationForPlan(let targetPlan, let selectedTrainings):
                        TrainingPlanAddDestinationView(
                            targetPlan: targetPlan,
                            selectedTrainings: selectedTrainings,
                            profile: self.profile,
                            onBack: { withAnimation { trainingActionContent = .selectWorkoutsForPlan(targetPlan: targetPlan) } },
                            onComplete: dismissTrainingActionMenu
                        )
                    case .nodes:
                        nodesListView
                    }
                },
                onStateChange: { newState in
                    if newState == .collapsed { dismissTrainingActionMenu() }
                }
            )
        }
        .onAppear {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    trainingActionMenuState = .full
                }
            }
        }
    }
    
    @ViewBuilder
    private var trainingPlanPickerOverlay: some View {
        ZStack {
            if trainingPlanMenuState == .full {
                (effectManager.isLightRowTextColor ? Color.black.opacity(0.4) : Color.white.opacity(0.4))
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { dismissTrainingPlanPicker() }
            }
            DraggableMenuView(
                menuState: $trainingPlanMenuState,
                customTopGap: UIScreen.main.bounds.height * 0.2,
                horizontalContent: { EmptyView() },
                verticalContent: {
                    if let plan = selectedPlanForPreview {
                        TrainingPlanPreviewView(
                            plan: plan,
                            profile: profile,
                            onDismiss: { withAnimation { selectedPlanForPreview = nil } },
                            onAdd: { selectedDays in
                                self.trainingPlanDaysToAdd = selectedDays
                                dismissTrainingPlanPicker()
                            }
                        )
                    } else {
                        TrainingPlanPickerView(
                            title: "Add from Training Plan",
                            plans: filteredTrainingPlans,
                            onDismiss: dismissTrainingPlanPicker,
                            onSelectPlan: { plan in
                                withAnimation { self.selectedPlanForPreview = plan }
                            }
                        )
                    }
                },
                onStateChange: { newState in
                    if newState == .collapsed { dismissTrainingPlanPicker() }
                }
            )
        }
        .onAppear {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    trainingPlanMenuState = .full
                }
            }
        }
    }
    
    private func presentTrainingActionMenu() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isShowingTrainingActionMenu = true
            trainingActionMenuState = .full
            navBarIsHiden = true
            if isSearching { onInternalFieldFocused() }
        }
    }
    
    private func dismissTrainingActionMenu() {
        withAnimation(.easeInOut(duration: 0.3)) {
            trainingActionMenuState = .collapsed
            isShowingTrainingActionMenu = false
            navBarIsHiden = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                trainingActionContent = .actions
            }
        }
    }
    
    private func presentTrainingPlanPicker() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isShowingTrainingPlanPicker = true
            trainingPlanMenuState = .full
            navBarIsHiden = true
            if isSearching { onInternalFieldFocused() }
        }
    }
    
    private func dismissTrainingPlanPicker() {
        withAnimation(.easeInOut(duration: 0.3)) {
            trainingPlanMenuState = .collapsed
            isShowingTrainingPlanPicker = false
            selectedPlanForPreview = nil
            navBarIsHiden = false
        }
    }
    
    private func updatedTrainingsForPicker() -> [Training] {
        return dailyTrainings.map { training in
            let updated = Training(from: training)
            return updated
        }
    }
    
    // В TrainingView.swift

    private func processTrainingPlanAddition(mode: TrainingAddMode) {
            guard let daysToAdd = trainingPlanDaysToAdd else { return }
            self.trainingPlanDaysToAdd = nil
            isSavingPlanToCalendar = true
            
            Task(priority: .userInitiated) {
                let calendar = Calendar.current
                let startDate = chosenDate
                
                for (index, planDay) in daysToAdd.enumerated() {
                    guard let targetDate = calendar.date(byAdding: .day, value: index, to: startDate) else { continue }
                    
                    let existingTrainingsForTargetDate = await CalendarViewModel.shared.trainings(forProfile: profile, on: targetDate)
                    
                    for planWorkout in planDay.workouts {
                        guard let workoutTemplate = profile.trainings.first(where: { $0.name == planWorkout.workoutName }) else { continue }
                        
                        let targetTraining = workoutTemplate.detached(for: targetDate)
                        let existingTrainingEvent = existingTrainingsForTargetDate.first { $0.name == targetTraining.name }
                        
                        var finalExercises: [ExerciseItem: Double] = [:]
                        
                        // --- Подготовка за Detailed Log ---
                        var detailedLogHelper: [ExerciseLog] = []
                        
                        // Ако добавяме към съществуваща (append), взимаме текущите логове
                        if mode == .append, let existing = existingTrainingEvent, let existingLog = existing.detailedLog(using: ctx) {
                            finalExercises = existing.exercises(using: ctx)
                            detailedLogHelper = existingLog.logs
                        }
                        
                        for entry in planWorkout.exercises {
                            guard let exercise = entry.exercise else { continue }
                            
                            // 1. Добавяме/Актуализираме продължителността
                            finalExercises[exercise, default: 0.0] += entry.durationMinutes
                            
                            // 2. Конвертираме TrainingPlanSet -> WorkoutSet
                            // ✅ FIX: Сортираме по orderIndex и прехвърляме isTimeBased И timeUnit
                            let workoutSets: [WorkoutSet] = entry.sets
                                .sorted { $0.orderIndex < $1.orderIndex }
                                .map { planSet in
                                    WorkoutSet(
                                        reps: planSet.reps,
                                        weight: planSet.weight,
                                        isToFailure: planSet.isToFailure,
                                        isTimeBased: planSet.isTimeBased,
                                        timeUnit: planSet.timeUnit // 👈 ДОБАВЕНО: Прехвърляме единицата
                                    )
                                }
                            
                            if !workoutSets.isEmpty {
                                // Проверяваме дали вече има лог за това упражнение (при append)
                                if let existingLogIndex = detailedLogHelper.firstIndex(where: { $0.exerciseID == exercise.id }) {
                                    detailedLogHelper[existingLogIndex].sets.append(contentsOf: workoutSets)
                                } else {
                                    let newLog = ExerciseLog(exerciseID: exercise.id, sets: workoutSets)
                                    detailedLogHelper.append(newLog)
                                }
                            }
                        }
                        
                        if finalExercises.isEmpty {
                            if let idToDelete = existingTrainingEvent?.calendarEventID {
                                _ = await CalendarViewModel.shared.deleteEvent(withIdentifier: idToDelete)
                            }
                            continue
                        }
                        
                        targetTraining.calendarEventID = existingTrainingEvent?.calendarEventID
                        
                        // Създаваме payload с упражненията И детайлния лог
                        let tempTrainingForPayload = Training(name: "", startTime: Date(), endTime: Date())
                        let finalDetailedLog = detailedLogHelper.isEmpty ? nil : DetailedTrainingLog(logs: detailedLogHelper)
                        
                        tempTrainingForPayload.updateNotes(exercises: finalExercises, detailedLog: finalDetailedLog)
                        
                        let payload = OptimizedInvisibleCoder.encode(from: tempTrainingForPayload.notes ?? "")
                        
                        _ = await CalendarViewModel.shared.createOrUpdateTrainingEvent(
                            forProfile: profile,
                            training: targetTraining,
                            exercisesPayload: payload
                        )
                    }
                    
                    if mode == .overwrite {
                        let workoutNamesInPlan = Set(planDay.workouts.map { $0.workoutName })
                        let eventsToDelete = existingTrainingsForTargetDate.filter { !workoutNamesInPlan.contains($0.name) }
                        for event in eventsToDelete {
                            if let id = event.calendarEventID {
                                _ = await CalendarViewModel.shared.deleteEvent(withIdentifier: id)
                            }
                        }
                    }
                }
                
                await MainActor.run {
                    self.isSavingPlanToCalendar = false
                    self.refreshTrigger += 1
                }
            }
        }
    
    private func aiBottomPadding(for geometry: GeometryProxy) -> CGFloat {
        let size = geometry.size
        guard size.width > 0 else { return 75 }
        let aspect = size.height / size.width
        return aspect > 1.9 ? 75 : 95
    }
    private func aiTrailingPadding(for geometry: GeometryProxy) -> CGFloat { 45 }
    
    private func aiDragGesture(geometry: GeometryProxy) -> some Gesture {
        let buttonSize: CGFloat = 60
        let radius = buttonSize / 2
        
        return DragGesture(minimumDistance: 0)
            .updating($aiGestureDragOffset) { value, state, _ in
                // Жив превод по време на drag – без анимация
                state = value.translation
            }
            .onChanged { value in
                let distance = max(abs(value.translation.width), abs(value.translation.height))
                
                if distance > 6 {
                    // Вече влачим – махаме "pressed" и маркираме "dragging"
                    if !aiIsDragging {
                        aiIsDragging = true
                        aiIsPressed = false
                    }
                } else {
                    // Малко мърдане = натиснат бутон
                    aiIsPressed = true
                }
            }
            .onEnded { value in
                let safeArea = geometry.safeAreaInsets
                let size = geometry.size
                
                // Базова позиция (дясно-долу) спрямо размера + твоите padding-и
                let baseX = size.width  - aiTrailingPadding(for: geometry) - radius
                let baseY = size.height - aiBottomPadding(for: geometry)   - radius
                
                // Центърът, ако приложим текущия offset + преместеното
                let rawCenterX = baseX + aiButtonOffset.width  + value.translation.width
                let rawCenterY = baseY + aiButtonOffset.height + value.translation.height
                
                // Ограничаваме центъра ВЪТРЕ в екрана
                let minX = radius
                let maxX = size.width  - radius
                let minY = radius + safeArea.top
                let maxY = size.height - radius - safeArea.bottom
                
                let clampedCenterX = min(max(rawCenterX, minX), maxX)
                let clampedCenterY = min(max(rawCenterY, minY), maxY)
                
                // Новият offset е просто разлика спрямо базовата позиция
                let newOffset = CGSize(
                    width:  clampedCenterX - baseX,
                    height: clampedCenterY - baseY
                )
                
                if aiIsDragging {
                    aiButtonOffset = newOffset
                    saveAIButtonPosition()
                } else {
                    // Тап (без реален drag)
                    handleAITap()
                }
                
                aiIsDragging = false
                aiIsPressed = false
            }
    }
    /// Стартира същинското AI генериране на дневния тренировъчен план.
    /// Извиква се САМО след като потребителят вече е "платил" (абонамент или реклама).
    private func startTrainingPlanAIGeneration(
        workoutsToGenerate: [Int: [String]],
        existingWorkouts: [Int: [TrainingPlanWorkoutDraft]],
        selectedPrompts: [String]
    ) {
        triggerAIGenerationToast()
        
        if let newJob = aiManager.startTrainingPlanGeneration(
            for: profile,
            prompts: selectedPrompts, // вече е почистен списък
            workoutsToFill: workoutsToGenerate,
            existingWorkouts: existingWorkouts.isEmpty ? nil : existingWorkouts,
            jobType: .trainingViewDailyPlan
        ) {
            self.runningGenerationJobID = newJob.id
        } else {
            alertMsg = "Could not start AI training generation job."
            showAlert = true
            toastTimer?.invalidate()
            toastTimer = nil
            withAnimation { showAIGenerationToast = false }
        }
    }
    
    private func handleAITap() {
        if isAITapOnCooldown {
            return
        }
        
        // 1. Веднага активираме cooldown за да предотвратим спам/двойни кликове
        isAITapOnCooldown = true
        Task { @MainActor in
            // Тук можеш да смениш 1.5 на 1.0 или 2.0 според това, което искаш
            try? await Task.sleep(for: .seconds(1.5))
            isAITapOnCooldown = false
        }
        
        NotificationCenter.default.post(name: .snoozeAds, object: nil)
        
        // 1. Проверка за наличност на AI (като при ExerciseItemEditorView)
        guard ensureAIAvailableOrShowMessage() else { return }
        
        // 2. Подготовка на данните за генериране (ПРЕДИ рекламите)
        let workoutsToGenerate = dailyTrainings.reduce(into: [Int: [String]]()) { result, training in
            if training.exercises(using: ctx).isEmpty {
                let dayIndex = 1 // ако имаш реален индекс за деня – сложи него
                result[dayIndex, default: []].append(training.name)
            }
        }
        
        guard !workoutsToGenerate.isEmpty else {
            alertMsg = "All workouts for this day already have exercises. Clear some if you want the AI to generate new ones."
            showAlert = true
            return
        }
        
        let existingWorkouts = dailyTrainings.reduce(into: [Int: [TrainingPlanWorkoutDraft]]()) { result, training in
            let exercises = training.exercises(using: ctx)
            if !exercises.isEmpty {
                let dayIndex = 1 // същото тук – ако имаш истински dayIndex, ползвай него
                let exerciseDrafts = exercises.map { (item, duration) in
                    TrainingPlanExerciseDraft(
                        exerciseName: item.name,
                        durationMinutes: duration
                    )
                }
                let workoutDraft = TrainingPlanWorkoutDraft(
                    workoutName: training.name,
                    exercises: exerciseDrafts
                )
                result[dayIndex, default: []].append(workoutDraft)
            }
        }
        
        let rawPrompts = allPrompts
            .filter { selectedPromptIDs.contains($0.id) && $0.type == .trainingViewМealPlan }
            .map { $0.text }
        
        // Нормализираме, за да не се занимаваме после в helper-а
        let promptsForGeneration = rawPrompts.isEmpty ? [] : rawPrompts
        let existingForGeneration = existingWorkouts
        
        // 3. Логика за АБОНАМЕНТ / РЕКЛАМИ (копи/пейст от ExerciseItemEditorView)
        
        // 3.1 Платен план – без реклами
        if !AdsConfiguration.shouldShowAds {
            print("💎 Premium user: Skipping ad.")
            startTrainingPlanAIGeneration(
                workoutsToGenerate: workoutsToGenerate,
                existingWorkouts: existingForGeneration,
                selectedPrompts: promptsForGeneration
            )
            return
        }
        
        // 3.2 Безплатен план – първо пробваме Rewarded, после Interstitial, накрая без реклами
        print("📺 Free user: Checking for ads...")
        if RewardedAdManager.shared.isReady {
            print("📺 Showing Rewarded Ad...")
            RewardedAdManager.shared.showIfAvailable { amount, type in
                // Изпълнява се само ако видеото е изгледано докрай
                print("✅ Ad watched! Starting training plan generation.")
                startTrainingPlanAIGeneration(
                    workoutsToGenerate: workoutsToGenerate,
                    existingWorkouts: existingForGeneration,
                    selectedPrompts: promptsForGeneration
                )
            }
        } else if InterstitialAdManager.shared.isReady {
            print("⚠️ Rewarded not ready. Showing Interstitial fallback...")
            InterstitialAdManager.shared.showIfAvailable {
                // Изпълнява се когато потребителят затвори interstitial-а
                print("✅ Interstitial closed. Starting training plan generation.")
                startTrainingPlanAIGeneration(
                    workoutsToGenerate: workoutsToGenerate,
                    existingWorkouts: existingForGeneration,
                    selectedPrompts: promptsForGeneration
                )
            }
        } else {
            print("⚠️ No ads available. Proceeding graciously.")
            // Няма никакви реклами – пускаме AI, за да не дразним потребителя
            startTrainingPlanAIGeneration(
                workoutsToGenerate: workoutsToGenerate,
                existingWorkouts: existingForGeneration,
                selectedPrompts: promptsForGeneration
            )
            
            // Подготвяме реклами за следващия път (background)
            Task {
                await RewardedAdManager.shared.loadAd()
                await InterstitialAdManager.shared.loadAd()
            }
        }
    }
    
    
    private func saveAIButtonPosition() {
        let d = UserDefaults.standard
        d.set(aiButtonOffset.width,  forKey: "\(aiButtonPositionKey)_width")
        d.set(aiButtonOffset.height, forKey: "\(aiButtonPositionKey)_height")
    }
    
    private func loadAIButtonPosition() {
        let d = UserDefaults.standard
        let w = d.double(forKey: "\(aiButtonPositionKey)_width")
        let h = d.double(forKey: "\(aiButtonPositionKey)_height")
        self.aiButtonOffset = CGSize(width: w, height: h)
    }
    
    @ViewBuilder
    private func AIButton(geometry: GeometryProxy) -> some View {
        let buttonSize: CGFloat = 60
        let radius = buttonSize / 2
        let safeArea = geometry.safeAreaInsets
        let size = geometry.size
        
        // Базова позиция (дясно-долу) с твоите "маржове"
        let baseX = size.width  - aiTrailingPadding(for: geometry) - radius
        let baseY = size.height - aiBottomPadding(for: geometry)   - radius
        
        // Център със запазения offset + текущия drag
        let rawCenterX = baseX + aiButtonOffset.width  + aiGestureDragOffset.width
        let rawCenterY = baseY + aiButtonOffset.height + aiGestureDragOffset.height
        
        // Ограничаваме центъра ВЪТРЕ в екрана (и safe area)
        let minX = radius
        let maxX = size.width  - radius
        let minY = radius + safeArea.top
        let maxY = size.height - radius - safeArea.bottom
        
        let centerX = min(max(rawCenterX, minX), maxX)
        let centerY = min(max(rawCenterY, minY), maxY)
        
        let scale = aiIsDragging ? 1.05 : (aiIsPressed ? 0.92 : 1.0)
        
        ZStack {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundColor(effectManager.currentGlobalAccentColor)
        }
        .frame(width: buttonSize, height: buttonSize)
        .glassCardStyle(cornerRadius: buttonSize / 2 + 2)
        .scaleEffect(scale)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: aiIsPressed)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: aiIsDragging)
        .contentShape(Circle())                     // само кръгчето е кликаемо
        .position(x: centerX, y: centerY)           // абсолютна позиция, вече clamp-ната
        .opacity(isAIButtonVisible ? (isAITapOnCooldown ? 0.5 : 1.0) : 0)
        .disabled(!isAIButtonVisible || isAITapOnCooldown)
        .gesture(aiDragGesture(geometry: geometry)) // жестът е върху 60x60, не върху цял екран
        .transition(.scale.combined(with: .opacity))
    }
    
    private func dismissSearchOverlay() {
        isSearchFieldFocused = false
        globalSearchText = ""
    }
    
    private func add(exerciseItem: ExerciseItem) {
        guard let trainingID = selectedTrainingID,
              let idx = dailyTrainings.firstIndex(where: { $0.id == trainingID }) else {
            return
        }
        
        let training = dailyTrainings[idx]
        
        // 1. Взимаме текущите упражнения и детайлния лог
        var currentEx = training.exercises(using: ctx)
        let currentLog = training.detailedLog(using: ctx)
        
        var lastAddedExerciseID: ExerciseItem.ID?
        
        if exerciseItem.isWorkout, let subExercises = exerciseItem.exercises, !subExercises.isEmpty {
            for link in subExercises {
                guard let subExercise = link.exercise else { continue }
                
                let duration = link.durationMinutes > 0 ? link.durationMinutes : Double(subExercise.durationMinutes ?? 15)
                
                currentEx[subExercise] = duration
                lastAddedExerciseID = subExercise.id
            }
        } else {
            let defaultDuration = Double(exerciseItem.durationMinutes ?? 15)
            currentEx[exerciseItem] = defaultDuration
            lastAddedExerciseID = exerciseItem.id
        }
        
        withAnimation {
            // 2. Използваме updateNotes, за да запазим И упражненията, И логовете
            dailyTrainings[idx].updateNotes(exercises: currentEx, detailedLog: currentLog)
            
            for (exercise, duration) in currentEx {
                if exerciseDurationTextValues[exercise.id] == nil {
                    exerciseDurationTextValues[exercise.id] = String(format: "%.0f", duration)
                }
            }
        }
        
        exerciseSearchVM.exclude(Set(currentEx.keys))
        scheduleAutosave()
        dismissSearchOverlay()
        
        if let idToScroll = lastAddedExerciseID {
            scrollToExerciseID = idToScroll
        }
    }
    
    private func update(duration: Double, for exercise: ExerciseItem) {
        guard let trainingID = selectedTrainingID,
              let idx = dailyTrainings.firstIndex(where: { $0.id == trainingID }) else { return }
        
        let training = dailyTrainings[idx]
        
        // 1. Взимаме текущите данни
        var currentEx = training.exercises(using: ctx)
        let currentLog = training.detailedLog(using: ctx)
        
        if currentEx[exercise] != nil {
            currentEx[exercise] = duration
            
            // 2. Запазваме чрез updateNotes, подавайки и стария лог
            dailyTrainings[idx].updateNotes(exercises: currentEx, detailedLog: currentLog)
            
            scheduleAutosave()
        }
    }
    
    private func delete(exercise: ExerciseItem) {
        guard let trainingID = selectedTrainingID,
              let idx = dailyTrainings.firstIndex(where: { $0.id == trainingID }) else { return }
        
        let training = dailyTrainings[idx]
        
        // 1. Взимаме текущите данни
        var currentEx = training.exercises(using: ctx)
        var currentLog = training.detailedLog(using: ctx)
        
        // 2. Премахваме упражнението
        currentEx.removeValue(forKey: exercise)
        
        // 3. (Опционално, но препоръчително) Почистваме логовете за изтритото упражнение
        if let logs = currentLog?.logs {
            let filteredLogs = logs.filter { $0.exerciseID != exercise.id }
            currentLog = DetailedTrainingLog(logs: filteredLogs)
        }
        
        withAnimation {
            // 4. Запазваме безопасно
            dailyTrainings[idx].updateNotes(exercises: currentEx, detailedLog: currentLog)
            exerciseDurationTextValues.removeValue(forKey: exercise.id)
        }
        
        exerciseSearchVM.exclude(Set(currentEx.keys))
        scheduleAutosave()
    }
    
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            do {
                try await Task.sleep(for: .seconds(1.5))
                await saveTrainingsToCalendar()
            } catch {
                print("Training autosave task cancelled.")
            }
        }
    }
    
    @MainActor
    private func saveTrainingsToCalendar() async {
        for training in dailyTrainings {
            if let oldID = training.notificationID {
                NotificationManager.shared.cancelNotification(id: oldID)
                training.notificationID = nil
            }
            
            if let minutes = training.reminderMinutes, minutes > 0 {
                let reminderDate = training.startTime.addingTimeInterval(-TimeInterval(minutes * 60))
                if reminderDate.timeIntervalSinceNow > 0 {
                    do {
                        let newID = try await NotificationManager.shared.scheduleNotification(
                            title: "🏋️ Workout Reminder",
                            body: "Time for your workout: \(training.name)!",
                            timeInterval: reminderDate.timeIntervalSinceNow,
                            userInfo: [
                                "trainingID": training.id.uuidString,
                                "trainingDate": training.startTime.timeIntervalSince1970,
                                "trainingName": training.name
                            ],
                            profileID: profile.id
                        )
                        training.notificationID = newID
                    } catch {
                        print("Error scheduling training notification: \(error)")
                    }
                }
            }
            
            // 1. Взимаме текущите активни упражнения (тези, които виждаш в списъка)
            let exercises = training.exercises(using: ctx)
            
            // 2. Взимаме текущия детайлен лог (серии/повторения)
            var detailedLog = training.detailedLog(using: ctx)
            
            // +++ НАЧАЛО НА КОРЕКЦИЯТА +++
            // 3. Филтрираме детайлния лог. Запазваме само записите, чиито exerciseID
            // съществуват в активния списък `exercises`.
            if let existingLogs = detailedLog?.logs {
                // Събираме ID-тата на активните упражнения
                let activeExerciseIDs = Set(exercises.keys.map { $0.id })
                
                // Премахваме логове за упражнения, които вече са изтрити от тренировката
                let filteredLogs = existingLogs.filter { activeExerciseIDs.contains($0.exerciseID) }
                
                // Обновяваме обекта
                detailedLog = DetailedTrainingLog(logs: filteredLogs)
            }
            // +++ КРАЙ НА КОРЕКЦИЯТА +++
            
            // 4. Записваме всичко обратно в notes полето
            training.updateNotes(exercises: exercises, detailedLog: detailedLog)
            
            let encodedPayload = OptimizedInvisibleCoder.encode(from: training.notes ?? "")
            
            let (_, newEventID) = await CalendarViewModel.shared.createOrUpdateTrainingEvent(
                forProfile: profile,
                training: training,
                exercisesPayload: encodedPayload
            )
            
            if let newID = newEventID {
                training.calendarEventID = newID
            }
        }
        if ctx.hasChanges {
            try? ctx.save()
        }
        
    }
    
    private func goalProgress(on date: Date) -> Double? { nil }
    
    private func fetchAndCalculateDailyIntake() async {
        let events = await CalendarViewModel.shared.meals(forProfile: profile, on: chosenDate)
        var total: Double = 0
        for meal in events {
            let foods = meal.foods(using: ctx)
            for (food, grams) in foods {
                total += food.calories(for: grams)
            }
        }
        await MainActor.run { self.totalCaloriesConsumedToday = total }
    }
    
    private func loadTrainings(preselect idToKeep: Training.ID? = nil) {
        Task { @MainActor in
            let calendarTrainings = await CalendarViewModel.shared.trainings(forProfile: profile, on: chosenDate)
            let template = profile.trainings(for: chosenDate)
            
            self.dailyTrainings = mergedTrainings(template: template, calendar: calendarTrainings)
            
            var trainingWasSelected = false
            if let targetName = trainingNameToPreselect,
               let foundTraining = dailyTrainings.first(where: { $0.name.caseInsensitiveCompare(targetName) == .orderedSame }) {
                selectedTrainingID = foundTraining.id
                trainingNameToPreselect = nil
                trainingWasSelected = true
            }
            
            if !trainingWasSelected {
                if let id = idToKeep, dailyTrainings.contains(where: { $0.id == id }) {
                    selectedTrainingID = id
                } else {
                    selectClosestTrainingToNow()
                }
            }
            
            exerciseSearchVM.exclude(Set(currentExercises.keys))
            
            await fetchAndCalculateDailyIntake()
        }
    }
    
    private func mergedTrainings(template: [Training], calendar events: [Training]) -> [Training] {
        var result = template.map { Training(from: $0) }
        var usedEventIDs = Set<String>()
        
        for i in result.indices {
            let templateTraining = result[i]
            
            if let matchingEvent = events.first(where: {
                $0.name == templateTraining.name &&
                $0.calendarEventID != nil &&
                !usedEventIDs.contains($0.calendarEventID!)
            }) {
                result[i].startTime = matchingEvent.startTime
                result[i].endTime   = matchingEvent.endTime
                result[i].notes     = matchingEvent.notes
                result[i].calendarEventID = matchingEvent.calendarEventID
                
                if let eventID = matchingEvent.calendarEventID {
                    usedEventIDs.insert(eventID)
                }
            }
        }
        
        let remainingEvents = events.filter {
            guard let eventID = $0.calendarEventID else { return false }
            return !usedEventIDs.contains(eventID)
        }
        result.append(contentsOf: remainingEvents)
        
        return result.sorted { $0.startTime < $1.startTime }
    }
    
    private func selectClosestTrainingToNow() {
        let nowSeconds = Double(Calendar.current.component(.hour, from: Date()) * 3600 + Calendar.current.component(.minute, from: Date()) * 60)
        let closest = dailyTrainings.min {
            let startA = $0.startTime.timeIntervalSince(Calendar.current.startOfDay(for: $0.startTime))
            let startB = $1.startTime.timeIntervalSince(Calendar.current.startOfDay(for: $1.startTime))
            return abs(startA - nowSeconds) < abs(startB - nowSeconds)
        }
        selectedTrainingID = closest?.id
    }
    
    @ViewBuilder
    private var muscleGroupsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Muscle Groups")
                    .font(.headline)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                
                Spacer()
                
                Button(action: { showAllMuscleGroups.toggle() }) {
                    Image(systemName: showAllMuscleGroups ? "rectangle.split.3x1.fill" : "rectangle.split.3x3.fill")
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        .imageScale(.medium)
                }
            }
            
            Group {
                if showAllMuscleGroups {
                    expandedMuscleGroups
                } else {
                    collapsedMuscleGroups
                }
            }
            .animation(.easeInOut, value: showAllMuscleGroups)
        }
    }
    
    @ViewBuilder
    private var collapsedMuscleGroups: some View {
        let items = allMuscleGroups
        // Използваме динамичната променлива тук
        let currentRingsPerRow = self.ringsPerRow
        
        // Разделяме на страници спрямо ширината на екрана
        let pages: [[MuscleGroup]] = stride(from: 0, to: items.count, by: currentRingsPerRow)
            .map { Array(items[$0 ..< min($0 + currentRingsPerRow, items.count)]) }
        
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: pageGap) {
                ForEach(pages.indices, id: \.self) { idx in
                    let cols = Array(
                        repeating: GridItem(.fixed(ringCellWidth), spacing: ringSpacing),
                        count: currentRingsPerRow
                    )
                    
                    LazyVGrid(columns: cols, spacing: ringSpacing) {
                        ForEach(pages[idx]) { group in
                            muscleCardButton(for: group)
                        }
                    }
                    .frame(height: ringCellHeight)
                    // Това гарантира, че групата заема правилната ширина на контейнера
                    .containerRelativeFrame(.horizontal)
                    .contentShape(Rectangle())
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .frame(height: ringCellHeight)
    }
    
    @ViewBuilder
    private var expandedMuscleGroups: some View {
        // Използваме динамичната променлива
        let currentRingsPerRow = self.ringsPerRow
        
        let cols = Array(
            repeating: GridItem(.fixed(ringCellWidth), spacing: ringSpacing),
            count: currentRingsPerRow
        )
        
        LazyVGrid(columns: cols, spacing: ringSpacing) {
            ForEach(allMuscleGroups) { group in
                muscleCardButton(for: group)
            }
        }
    }
    
    @ViewBuilder
    private var fullScreenSearchResultsView: some View {
        ZStack(alignment: .bottom) {
            (effectManager.isLightRowTextColor ? Color.black.opacity(0.4) : Color.white.opacity(0.4))
                .ignoresSafeArea()
                .onTapGesture { dismissSearchOverlay() }
            
            VStack(spacing: 0) {
                let handleContainerHeight: CGFloat = 35
                
                HStack {
                    if let group = selectedMuscleGroup {
                        Text("Selected: \(group.rawValue)")
                            .font(.body)
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    if selectedTrainingID != nil {
                        Text(selectedTrainingNameString)
                            .font(.body)
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: handleContainerHeight)
                
                filterChipsViewForSearch
                    .padding(.bottom, 20)
                
                if exerciseSearchVM.isLoading && exerciseSearchVM.items.isEmpty {
                    ProgressView()
                        .padding(14)
                        .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                }
                
                ZStack {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            if exerciseSearchVM.items.isEmpty && !exerciseSearchVM.isLoading {
                                Text("No results found.")
                                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                                    .padding(.top, 50)
                            } else {
                                ForEach(exerciseSearchVM.items) { item in
                                    Button(action: { add(exerciseItem: item) }) {
                                        HStack(spacing: 8) {
                                            if item.isFavorite {
                                                Image(systemName: "star.fill")
                                                    .foregroundColor(.yellow)
                                                    .font(.caption)
                                            }
                                            if item.isWorkout {
                                                Image(systemName: "figure.strengthtraining.traditional")
                                                    .foregroundColor(.orange)
                                                    .font(.caption)
                                            }
                                            Text(item.name)
                                            Spacer()
                                        }
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(effectManager.currentGlobalAccentColor)
                                    
                                    Divider().padding(.horizontal)
                                        .onAppear {
                                            if item.id == exerciseSearchVM.items.last?.id, exerciseSearchVM.hasMore {
                                                exerciseSearchVM.loadNextPage()
                                            }
                                        }
                                }
                                
                            }
                        }
                        Spacer(minLength: 180)
                    }
                }
            }
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, effectManager.appColorScheme) // Следва темата на приложението
            }
            .cornerRadius(20, corners: [.topLeft, .topRight])
            .frame(height: UIScreen.main.bounds.height * 0.55)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }
    
    
    @ViewBuilder
    private func muscleCardButton(for group: MuscleGroup) -> some View {
        let isSelected = (selectedMuscleGroup == group)
        
        Button {
            withAnimation(.easeInOut) {
                selectedMuscleGroup = isSelected ? nil : group
                exerciseSearchVM.muscleGroupFilter = selectedMuscleGroup
            }
        } label: {
            VStack(spacing: 4) {
                if let uiImage = UIImage(named: group.assetName(forGender: profile.gender)) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: ringCellHeight * 0.85)
                    
                    Text(group.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        .lineLimit(1)
                } else {
                    Text(group.rawValue)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(width: ringCellWidth, height: ringCellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCardStyle(cornerRadius: 15)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(
                    isSelected ? effectManager.currentGlobalAccentColor : .clear,
                    lineWidth: 2.5
                )
        )
        .animation(.easeInOut, value: isSelected)
    }
    
    @ViewBuilder
    private var filterChipsViewForSearch: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Button(action: {
                    withAnimation(.easeInOut) {
                        exerciseSearchVM.isFavoritesModeActive.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .imageScale(.medium)
                            .font(.system(size: 13, weight: .semibold))
                        if exerciseSearchVM.isFavoritesModeActive {
                            Image(systemName: "xmark")
                                .imageScale(.small)
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .accessibilityLabel("Favorites")
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(exerciseSearchVM.isFavoritesModeActive ? Color.yellow : Color.yellow.opacity(0.6))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(effectManager.currentGlobalAccentColor, lineWidth: exerciseSearchVM.isFavoritesModeActive ? 3 : 0)
                    )
                }
                .glassCardStyle(cornerRadius: 20)
                .buttonStyle(.plain)
                
                Button(action: {
                    withAnimation(.easeInOut) {
                        exerciseSearchVM.workoutFilterMode =
                        (exerciseSearchVM.workoutFilterMode == .onlyWorkouts ? .all : .onlyWorkouts)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .imageScale(.medium)
                            .font(.system(size: 13, weight: .semibold))
                        if exerciseSearchVM.workoutFilterMode == .onlyWorkouts {
                            Image(systemName: "xmark")
                                .imageScale(.small)
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .accessibilityLabel("Workouts")
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(exerciseSearchVM.workoutFilterMode == .onlyWorkouts ? Color.orange : Color.orange.opacity(0.6))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(effectManager.currentGlobalAccentColor, lineWidth: exerciseSearchVM.workoutFilterMode == .onlyWorkouts ? 3 : 0)
                    )
                }
                .glassCardStyle(cornerRadius: 20)
                .buttonStyle(.plain)
                
                
                ForEach(allMuscleGroups) { group in
                    muscleChipButton(for: group)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal)
        }
    }
    
    private var selectedTrainingNameString: String {
        guard let id = selectedTrainingID,
              let training = dailyTrainings.first(where: { $0.id == id }) else { return "" }
        return training.name
    }
    
    @ViewBuilder
    private func muscleChipButton(for group: MuscleGroup) -> some View {
        let isSelected = selectedMuscleGroup == group
        let baseColor = effectManager.currentGlobalAccentColor
        
        Button(action: {
            withAnimation(.easeInOut) {
                selectedMuscleGroup = (selectedMuscleGroup == group ? nil : group)
            }
        }) {
            HStack(spacing: 6) {
                Text(group.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                
                if isSelected {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(baseColor.opacity(isSelected ? 0.4 : 0.2))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? baseColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .glassCardStyle(cornerRadius: 20)
    }
    
    
    
    private func triggerAIGenerationToast() {
        toastTimer?.invalidate()
        toastProgress = 0.0
        withAnimation {
            showAIGenerationToast = true
        }
        
        let totalDuration = 10.0
        let updateInterval = 0.1
        let progressIncrement = updateInterval / totalDuration
        
        toastTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { timer in
            DispatchQueue.main.async {
                self.toastProgress += progressIncrement
                if self.toastProgress >= 1.0 {
                    timer.invalidate()
                    self.toastTimer = nil
                    withAnimation { self.showAIGenerationToast = false }
                }
            }
        }
    }
    
    @ViewBuilder
    private var aiGenerationToast: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Generating Workout...").fontWeight(.bold)
                    Text("AI is creating your exercises. You'll be notified.").font(.caption)
                    ProgressView(value: min(max(toastProgress, 0.0), 1.0), total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                        .animation(.linear, value: toastProgress)
                }
                Spacer()
                Button("OK") {
                    toastTimer?.invalidate()
                    toastTimer = nil
                    withAnimation { showAIGenerationToast = false }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
            }
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .padding()
            .glassCardStyle(cornerRadius: 20)
            .padding()
            .transition(.move(edge: .top).combined(with: .opacity))
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.keyboard)
    }
    
    private func ensureAIAvailableOrShowMessage() -> Bool {
        switch GlobalState.aiAvailability {
        case .available:
            return true
        case .deviceNotEligible:
            alertMsg = "This device doesn’t support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            alertMsg = "Apple Intelligence is turned off. Enable it in Settings to use AI."
        case .modelNotReady:
            alertMsg = "The model is downloading or preparing. Please try again shortly."
        case .unavailableUnsupportedOS:
            alertMsg = "Apple Intelligence requires iOS 26 or newer."
        case .unavailableOther:
            alertMsg = "Apple Intelligence is currently unavailable for an unknown reason."
        }
        showAlert = true
        return false
    }
    
    private enum PresentedNode: Identifiable, Equatable {
        case newNode
        case editNode(Node)
        
        var id: String {
            switch self {
            case .newNode:
                return "newNode"
            case .editNode(let node):
                return "editNode-\(node.id.uuidString)"
            }
        }
        
        static func == (lhs: PresentedNode, rhs: PresentedNode) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    @ViewBuilder
    private func presentedNodeView(for presented: PresentedNode) -> some View {
        let onDismissAction: () -> Void = {
            withAnimation {
                presentedNode = nil
            }
            // Re-fetch the nodes for the current day after saving or cancelling.
            Task {
                await loadNodesForDay()
            }
        }
        
        switch presented {
        case .newNode:
            NodeEditorView(profile: profile, node: nil, onDismiss: onDismissAction)
        case .editNode(let node):
            NodeEditorView(profile: profile, node: node, onDismiss: onDismissAction)
        }
    }
    
    @MainActor
    private func loadNodesForDay() async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: chosenDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            self.nodesForDay = []
            return
        }
        
        let profileID = profile.persistentModelID
        let predicate = #Predicate<Node> { node in
            node.profile?.persistentModelID == profileID &&
            node.date >= startOfDay &&
            node.date < endOfDay
        }
        let descriptor = FetchDescriptor<Node>(predicate: predicate, sortBy: [SortDescriptor(\.date, order: .reverse)])
        
        if let nodes = try? ctx.fetch(descriptor) {
            self.nodesForDay = nodes
        }
    }
    
    @ViewBuilder
    private var nodesListView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { withAnimation { trainingActionContent = .actions } }) {
                    HStack {
                        Text("Back")
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
                
                Spacer()
                Text("Notes").font(.headline)
                Spacer()
                
                Button(action: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation {
                            presentedNode = .newNode
                        }
                    }
                }) {
                    Text("Add Note")
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .padding()
            
            if nodesForDay.isEmpty {
                ContentUnavailableView("No Nodes for this Day", systemImage: "note.text")
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
            } else {
                List {
                    ForEach(nodesForDay) { node in
                        Button(action: {
                            withAnimation {
                                presentedNode = .editNode(node)
                            }
                        }) {
                            NodeRowView(node: node)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                if #available(iOS 26.0, *) {
                                    delete(node: node)
                                } else {
                                    self.nodeToDelete = node
                                    self.isShowingDeleteNodeConfirmation = true
                                }
                            } label: {
                                Image(systemName: "trash.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                            }
                            .tint(.clear)
                        }
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
            }
        }
    }
    
    private func delete(node: Node) {
        withAnimation {
            nodesForDay.removeAll { $0.id == node.id }
            ctx.delete(node)
            try? ctx.save()
        }
    }
    
    private func shouldShowAd(at index: Int) -> Bool {
        // Проверка за Premium абонамент - ако е платен, не показваме реклами
        if !AdsConfiguration.shouldShowAds {
            return false
        }
        
        // Пропускаме само първите 2 реда (0 и 1), за да не е най-горе
        if index < 2 { return false }
        
        // Алгоритъм за минимум 2 елемента разстояние:
        // Използваме цикъл от 7. Рекламите се падат на остатък 2 и 5.
        // Това създава ритъм: Реклама -> (2 елемента) -> Реклама -> (3 елемента) -> Реклама...
        // Индекси с реклами: 2, 5, 9, 12, 16, 19...
        let remainder = index % 7
        if remainder == 2 || remainder == 5 {
            return true
        }
        
        return false
    }
}
