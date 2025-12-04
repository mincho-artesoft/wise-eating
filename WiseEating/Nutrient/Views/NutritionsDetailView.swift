import SwiftUI
import SwiftData
import Combine
import EventKit

struct NutritionsDetailView: View {
    
    @State private var isShowingDeleteNodeConfirmation = false
    @State private var nodeToDelete: Node? = nil
    @State private var nodesForDay: [Node] = []
    @State private var presentedNode: PresentedNode? = nil
    @State private var expandedFoodItemID: FoodItem.ID? = nil
    // --- AI Floating Button: State ---
    @State private var isAIButtonVisible: Bool = true
    @State private var aiButtonOffset: CGSize = .zero
    @State private var aiIsDragging: Bool = false
    @GestureState private var aiGestureDragOffset: CGSize = .zero
    @State private var aiIsPressed: Bool = false
    private let aiButtonPositionKey = "floatingAIButtonPosition"
    
    @State private var isShowingDailyAIGenerator = false
    @State private var selectedNutrientID: String? = nil
    
    // --- Toast Notification State ---
    @State private var showAIGenerationToast = false
    @State private var toastTimer: Timer? = nil
    @State private var toastProgress: Double = 0.0
    // --- End Toast State ---
    
    private enum MealActionMenuContent: Equatable, Hashable {
        case actions
        case newPlanSelection
        case pickExistingPlan
        case selectMealsForPlan(targetPlan: MealPlan)
        case selectDestinationForPlan(targetPlan: MealPlan, selectedMeals: [Meal])
        case scanBarcodes
        case nodes
    }
    
    private struct TaskTrigger: Equatable {
        let date: Date
        let updatedAt: Date
    }
    
    // MARK: - Environment & Managers
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var ctx
    
    // MARK: - Input & Bindings
    let profile: Profile
    @Binding var globalSearchText: String
    @FocusState.Binding var isSearchFieldFocused: Bool
    @FocusState private var focusedGramsField: FoodItem?
    @Binding var navBarIsHiden: Bool
    @Binding var chosenDate: Date
    @Binding var selectedMealID: Meal.ID?
    let onInternalFieldFocused: () -> Void
    @Binding var isSearching: Bool
    @Binding var selectedTab: AppTab
    
    // MARK: - State
    @State private var dailyMeals: [Meal]
    
    @State private var initialFoodsByMeal: [Meal.ID: [FoodItem: Double]] = [:]
    
    @State private var mealNameToPreselect: String?
    @State private var autosaveTask: Task<Void, Never>? = nil
    @State private var isBootstrapping = true
    
    // Navigation & Sheets
    @State private var mealPlanForEditor: MealPlan? = nil
    @State private var mealPlanDraftForEditor: MealPlanDraft? = nil
    
    // Meal Action Menu State
    @State private var isShowingMealActionMenu = false
    @State private var mealActionMenuState: MenuState = .collapsed
    @State private var mealActionContent: MealActionMenuContent = .actions
    
    @State private var loadMealsTask: Task<Void, Never>? = nil
    @State private var isRingsPinned: Bool = true
    private func pinKey(for profile: Profile) -> String { "nutritions.ringsPinned.\(profile.id.uuidString)" }
    @State private var dayProgress: [DateComponents : Double] = [:]
    private func key(for d: Date) -> DateComponents { Calendar.current.dateComponents([.year, .month, .day], from: d) }
    @State private var animateStamp = false
    @State private var animateDates = Set<DateComponents>()
    @State private var showEventVC  = false
    @State private var eventToView: EKEvent?
    @State private var isShowingDeleteItemConfirmation = false
    @State private var itemToDelete: FoodItem? = nil
    @State private var selectedDetent: PresentationDetent = .large
    @State private var showAll = false
    @State private var waterGlassesConsumed: Int = 0
    @State private var waterGoal: Int = 8
    enum RingDetailType: Identifiable { case goals, calories, macros; var id: Self { self } }
    @State private var showingRingDetail: RingDetailType? = nil
    @State private var ringDetailMenuState: MenuState = .collapsed
    @State private var isShowingMealPlanPicker = false
    @State private var mealPlanMenuState: MenuState = .collapsed
    @State private var selectedPlanForPreview: MealPlan? = nil
    private enum MealAddMode { case overwrite, append }
    @State private var planDaysToAdd: [MealPlanDay]?
    @State private var isSaving = false
    @State private var collapsedItemsState: [NutriItem]? = nil
    @State private var allItemsState: [NutriItem]? = nil
    @State private var foodsByMeal: [Meal.ID: [FoodItem: Double]] = [:]
    @State private var keyboardHeight: CGFloat = 0
    private let maxRecentItems = 20
    @State private var currentTimeString: String = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var scrollToItemID: Int? = nil
    
    @State private var hasUnreadNotifications: Bool = false
    
    // --- START OF CHANGE: Add state for AI job tracking ---
    @ObservedObject private var aiManager = AIManager.shared
    @State private var runningGenerationJobID: UUID? = nil
    @State private var alertMsg: String = ""
    @State private var showAlert: Bool = false
    // --- END OF CHANGE ---
    
    // MARK: - Data & ViewModels
    @Query(sort: \Mineral.name)  private var minerals: [Mineral]
    @Query(sort: \Vitamin.name)  private var vitamins: [Vitamin]
    @Query private var mealPlans: [MealPlan]
    
    private var currentFoods: Binding<[FoodItem: Double]> {
        Binding(
            get: { foodsByMeal[selectedMealID ?? UUID()] ?? [:] },
            set: { foodsByMeal[selectedMealID ?? UUID()] = $0 }
        )
    }
    
    private var filteredMealPlans: [MealPlan] {
        let profileID = profile.persistentModelID
        return mealPlans.filter { $0.profile?.persistentModelID == profileID }
    }
    
    // MARK: - Initializer
    init(profile: Profile,
         globalSearchText: Binding<String>,
         chosenDate: Binding<Date>,
         selectedMealID: Binding<Meal.ID?>,
         preselectMealName: String? = nil,
         isSearchFieldFocused: FocusState<Bool>.Binding,
         navBarIsHiden: Binding<Bool>,
         isSearching: Binding<Bool>,
         selectedTab: Binding<AppTab>,
         onInternalFieldFocused: @escaping () -> Void)
    {
        self.profile = profile
        self._globalSearchText = globalSearchText
        self._isSearchFieldFocused = isSearchFieldFocused
        self._navBarIsHiden = navBarIsHiden
        self._isSearching = isSearching
        self._selectedTab = selectedTab
        self.onInternalFieldFocused = onInternalFieldFocused
        self._chosenDate = chosenDate
        self._selectedMealID = selectedMealID
        self._mealNameToPreselect = State(initialValue: preselectMealName)
        
        let mealsToday = profile.meals(for: chosenDate.wrappedValue)
        self._dailyMeals = State(initialValue: mealsToday)
    }
    
    private func refreshProfileDependentData() {
        dayProgress = [:]
        calculateCollapsedItems()
        if showAll {
            calculateAllItems()
        }
        Task {
            await preloadProgress(weeksRange: 4)
        }
    }
    
    private func calculateWaterGoal(for profile: Profile) -> Int {
        let weight = profile.weight
        let age = profile.age
        
        let mlPerKg: Double
        
        switch age {
        case 0...15:
            mlPerKg = 40.0
        case 16...30:
            mlPerKg = 35.0
        case 31...54:
            mlPerKg = 32.5
        case 55...65:
            mlPerKg = 30.0
        default:
            mlPerKg = 25.0
        }
        
        let totalMilliliters = weight * mlPerKg
        let numberOfGlasses = Int(round(totalMilliliters / 200.0))
        
        return max(4, numberOfGlasses)
    }
    
    private var isAIButtonCurrentlyVisible: Bool {
        if isSearchFieldFocused { return false }
        if showingRingDetail != nil { return false }
        if isShowingMealActionMenu { return false }
        if isShowingMealPlanPicker { return false }
        if mealPlanForEditor != nil { return false }
        if mealPlanDraftForEditor != nil { return false }
        if isShowingDailyAIGenerator { return false }
        if presentedNode != nil { return false }
        return true
    }
    
    private func checkForUnreadNotifications() async {
        let unread = await NotificationManager.shared.getUnreadNotifications()
        self.hasUnreadNotifications = !unread.isEmpty
    }
    
    private func handleGeneratedMeals(_ generatedMeals: [MealPlanPreviewMeal]) {
        for generatedMeal in generatedMeals {
            guard let targetMeal = dailyMeals.first(where: { $0.name == generatedMeal.name }) else {
                continue
            }
            
            var foodsToAdd: [FoodItem: Double] = [:]
            for item in generatedMeal.items {
                let itemName = item.name
                let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate {
                    $0.name == itemName && !$0.isUserAdded
                })
                
                if let foodItem = try? ctx.fetch(descriptor).first {
                    foodsToAdd[foodItem] = item.grams
                }
            }
            
            foodsByMeal[targetMeal.id] = foodsToAdd
        }
        
        scheduleAutosave()
        calculateCollapsedItems()
        calculateAllItems()
    }
    
    var body: some View {
        ZStack {
            ZStack {
                if mealPlanForEditor == nil && mealPlanDraftForEditor == nil {
                    viewWithLifeCycle
                }
                
                if let plan = mealPlanForEditor {
                    MealPlanEditorView(
                        profile: self.profile,
                        planToEdit: plan,
                        navBarIsHiden: $navBarIsHiden,
                        globalSearchText: $globalSearchText,
                        isSearchFieldFocused: self.$isSearchFieldFocused,
                        onDismiss: {
                            withAnimation(.easeInOut) {
                                mealPlanForEditor = nil
                                navBarIsHiden = false
                            }
                        }
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    .zIndex(10)
                }
                
                if let draft = mealPlanDraftForEditor {
                    MealPlanEditorView(
                        profile: self.profile,
                        planDraft: draft,
                        navBarIsHiden: $navBarIsHiden,
                        globalSearchText: $globalSearchText,
                        isSearchFieldFocused: self.$isSearchFieldFocused,
                        onDismiss: {
                            withAnimation(.easeInOut) {
                                mealPlanDraftForEditor = nil
                                navBarIsHiden = false
                                if isSearchFieldFocused {
                                    isSearchFieldFocused = false
                                    globalSearchText = ""
                                }
                            }
                        }
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    .zIndex(10)
                }
                
                if isShowingDailyAIGenerator {
                    AIDailyMealGeneratorView(
                        profile: profile,
                        date: chosenDate,
                        meals: dailyMeals,
                        onJobScheduled: {
                            triggerAIGenerationToast()
                            withAnimation {
                                isShowingDailyAIGenerator = false
                                navBarIsHiden = false
                            }
                        },
                        onDismiss: {
                            withAnimation {
                                isShowingDailyAIGenerator = false
                                navBarIsHiden = false
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
                }
            }
            .onChange(of: foodsByMeal) {
                calculateCollapsedItems()
                calculateAllItems()
                if !isBootstrapping { scheduleAutosave() }
            }
            .onChange(of: isSearchFieldFocused) { _, isFocused in
                if isFocused {
                    if allItemsState == nil { calculateAllItems() }
                    if collapsedItemsState == nil { calculateCollapsedItems() }
                }
            }
            
            if let presented = presentedNode {
                presentedNodeView(for: presented)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    .zIndex(15)
            }
            
            if showingRingDetail != nil { ringDetailOverlay }
            if isShowingMealPlanPicker { mealPlanPickerOverlay }
            if isShowingMealActionMenu { mealActionMenuOverlay }
        }
        .overlay {
            GeometryReader { geometry in
                Group {
                    if isAIButtonCurrentlyVisible && GlobalState.aiAvailability != .deviceNotEligible {
                        AIButton(geometry: geometry)
                    }
                    if showAIGenerationToast {
                        aiGenerationToast
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .onAppear {
            loadAIButtonPosition()
        }
        .alert("Error", isPresented: $showAlert, actions: {
            Button("OK", role: .cancel) {}
        }, message: { Text(alertMsg) })
        .alert("Delete Food", isPresented: $isShowingDeleteItemConfirmation, actions: {
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    withAnimation { deleteFoodFromMeal(item); scheduleAutosave() }
                }
                itemToDelete = nil
            }
            Button("Cancel", role: .cancel) { itemToDelete = nil }
        }, message: { Text("Are you sure you want to delete '\(itemToDelete?.name ?? "this food")' from the meal? This will not affect your stored items.") })
        .presentationDetents([.large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: focusedGramsField) { _, newValue in if newValue != nil { onInternalFieldFocused() } }
        .onReceive(Publishers.keyboardHeight) { height in
            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.8)) { self.keyboardHeight = height }
        }
        
        .confirmationDialog("Add Meals from Plan", isPresented: .constant(planDaysToAdd != nil), titleVisibility: .visible, actions: {
            Button("Add to Existing Meals") { processMealPlanAddition(mode: .append) }
            Button("Overwrite Existing Meals", role: .destructive) { processMealPlanAddition(mode: .overwrite) }
            Button("Cancel", role: .cancel) { planDaysToAdd = nil }
        }, message: { Text("This will add meals for \(planDaysToAdd?.count ?? 0) day(s), starting from \(chosenDate.formatted(date: .abbreviated, time: .omitted)). How should meals for a specific time slot be added?") })
        .onChange(of: aiManager.jobs) { _, newJobs in
            guard let runningID = runningGenerationJobID,
                  let completedJob = newJobs.first(where: { $0.id == runningID }) else { return }
            
            if completedJob.status == .completed {
                if let preview = completedJob.result {
                    Task {
                        await populateMealsFromPreview(preview)
                        runningGenerationJobID = nil
                        await aiManager.deleteJob(completedJob)
                    }
                }
            } else if completedJob.status == .failed {
                alertMsg = "AI generation failed: \(completedJob.failureReason ?? "Unknown error")"
                showAlert = true
                runningGenerationJobID = nil
                Task { await aiManager.deleteJob(completedJob) }
            }
        }
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
    
    @ViewBuilder
    private func presentedNodeView(for presented: PresentedNode) -> some View {
        let onDismissAction: () -> Void = {
            withAnimation {
                presentedNode = nil
                navBarIsHiden = false
            }
            // Re-fetch the nodes for the current day after saving.
            Task {
                await loadNodesForDay()
            }
        }
        
        switch presented {
        case .newNode:
            NodeEditorView(profile: profile, node: nil, onDismiss: onDismissAction)
                .onAppear { navBarIsHiden = true }
        case .editNode(let node):
            NodeEditorView(profile: profile, node: node, onDismiss: onDismissAction)
                .onAppear { navBarIsHiden = true }
        }
    }
    
    @ViewBuilder
    private var mealActionMenuOverlay: some View {
        ZStack {
            if mealActionMenuState == .full {
                (effectManager.isLightRowTextColor ? Color.black.opacity(0.4) : Color.white.opacity(0.4))
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { dismissMealActionMenu() }
            }
            DraggableMenuView(
                menuState: $mealActionMenuState,
                customTopGap: (mealActionContent == .scanBarcodes) ? UIScreen.main.bounds.height * 0.05 : UIScreen.main.bounds.height * 0.2,
                horizontalContent: { EmptyView() },
                verticalContent: {
                    // +++ НАЧАЛО НА ПРОМЯНАТА (4/5) +++
                    switch mealActionContent {
                    case .actions:
                        MealActionMenuView(
                            onDismiss: dismissMealActionMenu,
                            onCopyToNewPlan: { withAnimation { mealActionContent = .newPlanSelection } },
                            onAddToExistingPlan: { withAnimation { mealActionContent = .pickExistingPlan } },
                            onGenerateWithAI: {
                                dismissMealActionMenu()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    isShowingDailyAIGenerator = true
                                    navBarIsHiden = true
                                }
                            },
                            onScanBarcode: {
                                withAnimation { mealActionContent = .scanBarcodes }
                            },
                            // Подаваме новия callback
                            onNodesTapped: {
                                withAnimation { mealActionContent = .nodes }
                            }
                        )
                    case .newPlanSelection:
                        MealSelectionForPlanView(
                            profile: self.profile,
                            meals: updatedMealsForPicker(),
                            onBack: { withAnimation { mealActionContent = .actions } },
                            onCancel: dismissMealActionMenu,
                            onCreatePlan: { selectedMeals, planName in
                                let draft = MealPlanDraft(name: planName, meals: selectedMeals)
                                dismissMealActionMenu()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(.easeInOut) {
                                        self.mealPlanDraftForEditor = draft
                                    }
                                }
                            }
                        )
                    case .pickExistingPlan:
                        MealPlanPickerView(
                            title: "Add to Existing Plan",
                            dismissButtonLabel: "Back",
                            plans: filteredMealPlans,
                            onDismiss: {
                                withAnimation { mealActionContent = .actions }
                            },
                            onSelectPlan: { plan in
                                withAnimation {
                                    mealActionContent = .selectMealsForPlan(targetPlan: plan)
                                }
                            }
                        )
                    case .selectMealsForPlan(let targetPlan):
                        MealPlanAddMealsView(
                            sourceMeals: updatedMealsForPicker(),
                            onBack: { withAnimation { mealActionContent = .pickExistingPlan } },
                            onCancel: dismissMealActionMenu,
                            onNext: { selected in
                                withAnimation {
                                    mealActionContent = .selectDestinationForPlan(targetPlan: targetPlan, selectedMeals: selected)
                                }
                            }
                        )
                    case .selectDestinationForPlan(let targetPlan, let selectedMeals):
                        MealPlanAddDestinationView(
                            targetPlan: targetPlan,
                            selectedMeals: selectedMeals,
                            profile: self.profile,
                            onBack: {
                                withAnimation { mealActionContent = .selectMealsForPlan(targetPlan: targetPlan) }
                            },
                            onComplete: {
                                dismissMealActionMenu()
                            }
                        )
                    case .scanBarcodes:
                        BarcodeScannerView(
                            mode: .nutritionLog,
                            profile: self.profile,
                            onBarcodeSelect: { entity in
                                print("Scanned non-product code: \(entity.title)")
                            },
                            onAddFoodItem: { foodItem in
                                add(foodItem: foodItem)
                            }
                        )
                        // Добавяме новия case
                    case .nodes:
                        nodesListView
                    }
                    // +++ КРАЙ НА ПРОМЯНАТА (4/5) +++
                },
                onStateChange: { newState in
                    if newState == .collapsed { dismissMealActionMenu() }
                }
            )
            .id(mealActionContent)
        }
        .onAppear {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    mealActionMenuState = .full
                }
            }
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
    private var viewWithLifeCycle: some View {
        ZStack {
            mainContentView
            
            // --- НАЧАЛО НА ПРОМЯНАТА: Замяна на fullScreenSearchResultsView с FoodSearchPanelView ---
            if isSearchFieldFocused {
                let focusBinding = Binding<Bool>(
                    get: { isSearchFieldFocused },
                    set: { isSearchFieldFocused = $0 }
                )
                
                let excludedIDs = Set(currentFoods.wrappedValue.keys.map { $0.id })
                
                FoodSearchPanelView(
                    globalSearchText: $globalSearchText,
                    isSearchFieldFocused: focusBinding,
                    profile: profile,
                    searchMode: .nutrients,
                    showFavoritesFilter: true,
                    showRecipesFilter: true,
                    showMenusFilter: true,
                    headerRightText: selectedMealNameString,
                    excludedFoodIDs: excludedIDs,
                    selectedNutrientID: $selectedNutrientID,
                    
                    onSelectFood: { foodItem in
                        add(foodItem: foodItem)
                    },
                    onDismiss: {
                        dismissKeyboardAndSearch()
                    }
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                .zIndex(20)
            }
            
            if isSaving {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                        .scaleEffect(1.5)
                    Text("Adding Meals...")
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                        .font(.headline)
                }
                .padding(30)
                .glassCardStyle(cornerRadius: 20)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Adding Meals")
                .zIndex(1000)
            }
        }
        .background(.clear)
        .task(id: TaskTrigger(date: chosenDate, updatedAt: profile.updatedAt)) {
            loadMeals(preselect: selectedMealID)
            refreshProfileDependentData()
            await loadNodesForDay()
        }
        .onAppear {
            self.waterGoal = calculateWaterGoal(for: profile)
        }
        .onChange(of: profile.weight) { _, _ in
            self.waterGoal = calculateWaterGoal(for: profile)
        }
        .onChange(of: profile.birthday) { _, _ in
            self.waterGoal = calculateWaterGoal(for: profile)
        }
        .onChange(of: profile.priorityVitamins) { refreshProfileDependentData() }
        .onChange(of: profile.priorityMinerals) { refreshProfileDependentData() }
        .onChange(of: profile.gender) { refreshProfileDependentData() }
        .onChange(of: profile.isPregnant) { refreshProfileDependentData() }
        .onChange(of: profile.isLactating) { refreshProfileDependentData() }
        .onDisappear {
            autosaveTask?.cancel()
            Task {
                await saveMealsToCalendar()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiJobCompleted)) { notification in
            loadMeals(preselect: selectedMealID)
        }
        .onReceive(timer) { _ in
            self.currentTimeString = tFmt.string(from: Date())
        }
        .onReceive(NotificationCenter.default.publisher(for: .unreadNotificationStatusChanged)) { _ in
            Task {
                await checkForUnreadNotifications()
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
    
    @ViewBuilder
    private var nodesListView: some View {
        VStack(spacing: 0) {
            // Toolbar (остава непроменен)
            HStack {
                Button(action: { withAnimation { mealActionContent = .actions } }) {
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
            
            // Списък с бележки
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
                                if #available(iOS 26.0, *) { // Използваме същата проверка като при упражненията
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
            // Запазваме промените в базата данни
            try? ctx.save()
        }
    }
    
    private func humanReadableNotes(for foods: [FoodItem: Double]) -> String? {
        let sortedFoods = foods.keys.sorted { $0.name < $1.name }
        guard !sortedFoods.isEmpty else { return nil }
        
        return sortedFoods.map { foodItem in
            let grams = foods[foodItem] ?? 0
            return "\(foodItem.name) – \(grams.clean) g"
        }.joined(separator: "\n")
    }
    
    func updatedMealsForPicker() -> [Meal] {
        return dailyMeals.map { originalMeal in
            let updatedMeal = Meal(from: originalMeal)
            if let currentFoodsForMeal = foodsByMeal[originalMeal.id] {
                let notesString = humanReadableNotes(for: currentFoodsForMeal)
                updatedMeal.notes = notesString
            }
            return updatedMeal
        }
    }
    
    private var allConsumedFoods: [FoodItem: Double] {
        mergedFoods(foodsByMeal)
    }
    
    private var totalCalories: Double {
        allConsumedFoods.reduce(0) { sum, pair in
            let (food, grams) = pair
            return sum + food.calories(for: grams)
        }
    }
    
    private var targetCalories: Double {
        return TDEECalculator.calculate(for: profile, activityLevel: profile.activityLevel)
    }
    
    private func totalGramsForMacro(_ keyPath: KeyPath<MacronutrientsData, Nutrient?>) -> Double {
        allConsumedFoods.reduce(0) { sum, pair in
            let (food, grams) = pair
            let refWeight = food.referenceWeightG
            guard refWeight > 0 else { return sum }
            
            let macroAmountForRefWeight = food.macro(keyPath)
            return sum + (macroAmountForRefWeight / refWeight) * grams
        }
    }
    
    private var totalCarbsGrams: Double { totalGramsForMacro(\.carbohydrates) }
    private var totalProteinGrams: Double { totalGramsForMacro(\.protein) }
    private var totalFatGrams: Double { totalGramsForMacro(\.fat) }
    
    private var totalConsumedGrams: Double {
        allConsumedFoods.reduce(0) { $0 + $1.value }
    }
    
    private var macroProportionsData: [NutrientProportionData] {
        var data: [NutrientProportionData] = []
        if totalCarbsGrams > 0 {
            data.append(.init(name: "Carbs", value: totalCarbsGrams, color: Color.blue.opacity(0.8)))
        }
        if totalProteinGrams > 0 {
            data.append(.init(name: "Protein", value: totalProteinGrams, color: Color.orange.opacity(0.9)))
        }
        if totalFatGrams > 0 {
            data.append(.init(name: "Fat", value: totalFatGrams, color: Color.purple.opacity(0.7)))
        }
        return data
    }
    
    private var isDateEligibleForStorageUpdate: Bool {
        Calendar.current.isDateInToday(chosenDate) || chosenDate > Date()
    }
    
    @ViewBuilder
    private var mainContentView: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                
                userToolbar
                    .padding(.trailing, 50)
                    .padding(.leading, 40)
                    .padding(.top, headerTopPadding)
                
                UpdatePlanBanner()
                    .if(safeAreaInsets.top != 0) {view in
                        view.padding(.top, -4)
                    }else: { view in
                        view.padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                
                WeekCarouselRepresentable(
                    selectedDate: $chosenDate,
                    progressProvider: { date in goalProgress(on: date) }
                )
                .padding(.horizontal, 20)
                .frame(height: 80)
                .padding(.bottom, 35)
                .onChange(of: chosenDate) {
                    loadMeals(preselect: selectedMealID)
                }
                
                VStack(spacing: 0) {
                    MealTimelineView(
                        meals: $dailyMeals,
                        selectedMealID: $selectedMealID,
                        showOnlySelected: true
                    )
                    .frame(height: 80)
                    .padding(.horizontal, 40)
                    
                    if isRingsPinned {
                        RingsSummaryRow(
                            goalsAchieved: goalsAchieved,
                            totalGoals: totalGoals,
                            onTap: { presentRingDetail($0) },
                            calorieRing: { calorieRing },
                            macroRing:   { macroProportionRing },
                            isPinned: $isRingsPinned,
                            waterConsumed: $waterGlassesConsumed,
                            waterGoal: waterGoal,
                            onIncrementWater: incrementWater,
                            onDecrementWater: decrementWater
                        )
                        .padding(.top, -40)
                    }
                    ScrollViewReader { proxy in
                        List {
                            if !isRingsPinned {
                                RingsSummaryRow(
                                    goalsAchieved: goalsAchieved,
                                    totalGoals: totalGoals,
                                    onTap: { presentRingDetail($0) },
                                    calorieRing: { calorieRing },
                                    macroRing:   { macroProportionRing },
                                    isPinned: $isRingsPinned,
                                    waterConsumed: $waterGlassesConsumed,
                                    waterGoal: waterGoal,
                                    onIncrementWater: incrementWater,
                                    onDecrementWater: decrementWater
                                )
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                                .padding(.horizontal, -10)
                                .padding(.top, 4)
                            }
                            
                            NutrientsSection(
                                showAll: $showAll,
                                onTurnedOn: { if allItemsState == nil { calculateAllItems() } },
                                collapsed: { collapsedRings },
                                expanded:  { expandedRings }
                            )
                            .padding(.top, -16)
                            .padding(.horizontal, -4)
                            
                            if let fresh = selectedNutrientItem {
                                NutrientProgressBar(item: fresh)
                                    .padding(.bottom, 10)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }
                            
                            HStack {
                                Text("Foods")
                                    .font(.headline)
                                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                                Spacer()
                                
                                Button("Foods List") {
                                    onInternalFieldFocused()
                                    selectedTab = .foods
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .glassCardStyle(cornerRadius: 20)
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                                .buttonStyle(.plain)
                                
                                Button("Load Plan") {
                                    presentMealPlanPicker()
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .glassCardStyle(cornerRadius: 20)
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                                .buttonStyle(.plain)
                                
                                Button("Actions") {
                                    presentMealActionMenu()
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
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                            
                            ForEach(Array(currentFoods.wrappedValue.keys.sorted(by: { $0.name < $1.name })), id: \.self) { item in
                                let isSufficient = isStockSufficient(for: item, requestedGrams: currentFoods.wrappedValue[item] ?? 0)
                                
                                VStack(spacing: 0) {
                                    SelectedFoodRowView(
                                        item: item,
                                        grams: currentFoods.wrappedValue[item] ?? 0,
                                        isStockSufficient: isSufficient,
                                        onGramsChanged: { newGrams in
                                            updateStorageAndMeal(for: item, newGrams: newGrams)
                                        },
                                        focusedField: $focusedGramsField,
                                        expandedItemID: $expandedFoodItemID // Подаваме байндинг
                                    )
                                    
                                }
                                .id(item.id)
                                .padding(.bottom, 4)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        if #available(iOS 16.0, *) {
                                            withAnimation {
                                                deleteFoodFromMeal(item)
                                                scheduleAutosave()
                                            }
                                        } else {
                                            self.itemToDelete = item
                                            self.isShowingDeleteItemConfirmation = true
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
                        .onChange(of: focusedGramsField) { _, newValue in
                            guard let focusedItem = newValue else { return }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(focusedItem, anchor: .top)
                                }
                            }
                        }
                        .onChange(of: scrollToItemID) { _, newItemID in
                            guard let id = newItemID else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    proxy.scrollTo(id, anchor: .top)
                                }
                                scrollToItemID = nil
                            }
                        }
                        .modifier(ListMask(enabled: !showAll, accent: effectManager.currentGlobalAccentColor))
                        .offset(y: !isRingsPinned ? -44: 0)
                        .padding(.horizontal, 10)
                        .listStyle(.plain)
                        .listRowSpacing(0)
                        .listSectionSpacing(0)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .scrollIndicators(.hidden)
                        .modifier(ListContentMarginsZero())
                        .onAppear {
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
            }
            .padding(.horizontal, -20)
        }
        .background(Color.clear)
    }
    
    private func presentMealActionMenu() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isShowingMealActionMenu = true
            mealActionMenuState = .full
            navBarIsHiden = true
            if isSearching {
                onInternalFieldFocused()
            }
        }
    }
    
    private func dismissMealActionMenu() {
        withAnimation(.easeInOut(duration: 0.3)) {
            mealActionMenuState = .collapsed
            isShowingMealActionMenu = false
            navBarIsHiden = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                mealActionContent = .actions
            }
        }
    }
    
    @ViewBuilder
    private var mealPlanPickerOverlay: some View {
        ZStack {
            if mealPlanMenuState == .full {
                (effectManager.isLightRowTextColor ? Color.black.opacity(0.4) : Color.white.opacity(0.4))
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            dismissMealPlanPicker()
                        }
                    }
            }
            
            DraggableMenuView(
                menuState: $mealPlanMenuState,
                customTopGap: (mealActionContent == .scanBarcodes) ? UIScreen.main.bounds.height * 0.05 : UIScreen.main.bounds.height * 0.2,
                horizontalContent: { EmptyView() },
                verticalContent: {
                    if let plan = selectedPlanForPreview {
                        MealPlanPreviewView(
                            plan: plan,
                            profile: profile,
                            onDismiss: {
                                withAnimation { selectedPlanForPreview = nil }
                            },
                            onAdd: { selectedDays in
                                self.planDaysToAdd = selectedDays
                                dismissMealPlanPicker()
                            }
                        )
                    } else {
                        MealPlanPickerView(
                            title: "Add from Meal Plan",
                            plans: filteredMealPlans,
                            onDismiss: dismissMealPlanPicker,
                            onSelectPlan: { plan in
                                withAnimation { self.selectedPlanForPreview = plan }
                            }
                        )
                    }
                },
                onStateChange: { newState in
                    if newState == .collapsed {
                        dismissMealPlanPicker()
                    }
                }
            )
        }
        .onAppear {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    mealPlanMenuState = .full
                }
            }
        }
    }
    
    @ViewBuilder
    private var mealPlanPickerContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Close") { dismissMealPlanPicker() }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCardStyle(cornerRadius: 20)
                
                Spacer()
                Text("Add from Meal Plan").font(.headline)
                Spacer()
                
                Button("Close") {}.hidden().padding(.horizontal, 10).padding(.vertical, 5)
            }
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .padding()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if filteredMealPlans.isEmpty {
                        ContentUnavailableView("No Meal Plans", systemImage: "calendar.badge.clock")
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                    } else {
                        ForEach(filteredMealPlans) { plan in
                            Button(action: {
                                withAnimation { self.selectedPlanForPreview = plan }
                            }) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(plan.name)
                                        .font(.headline)
                                    
                                    HStack {
                                        Text("\(plan.days.count) day\(plan.days.count == 1 ? "" : "s")")
                                        Text("•")
                                        Text("Created: \(plan.creationDate.formatted(date: .abbreviated, time: .omitted))")
                                    }
                                    .font(.caption)
                                    .opacity(0.8)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .glassCardStyle(cornerRadius: 15)
                                .foregroundColor(effectManager.currentGlobalAccentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    private func addMealPlanToCurrentMeal(plan: MealPlan) {
        
        dismissMealPlanPicker()
    }
    
    @ViewBuilder
    private var ringDetailOverlay: some View {
        ZStack {
            if ringDetailMenuState == .full {
                (effectManager.isLightRowTextColor ? Color.black.opacity(0.4) : Color.white.opacity(0.4))
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            dismissRingDetail()
                        }
                    }
            }
            
            DraggableMenuView(
                menuState: $ringDetailMenuState,
                customTopGap: (mealActionContent == .scanBarcodes) ? UIScreen.main.bounds.height * 0.05 : UIScreen.main.bounds.height * 0.2,
                horizontalContent: { EmptyView() },
                verticalContent: {
                    if let detailType = showingRingDetail {
                        ringDetailContent(for: detailType)
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
    }
    
    private func incrementWater() {
        if waterGlassesConsumed < waterGoal * 3 {
            waterGlassesConsumed += 1
            saveWaterLog()
        }
    }
    
    private func decrementWater() {
        if waterGlassesConsumed > 0 {
            waterGlassesConsumed -= 1
            saveWaterLog()
        }
    }
    
    private func saveWaterLog() {
        let day = Calendar.current.startOfDay(for: chosenDate)
        let profileID = profile.persistentModelID
        
        var descriptor = FetchDescriptor<WaterLog>(predicate: #Predicate {
            $0.profile?.persistentModelID == profileID && $0.date == day
        })
        descriptor.fetchLimit = 1
        
        do {
            if let existingLog = try ctx.fetch(descriptor).first {
                existingLog.glassesConsumed = waterGlassesConsumed
            } else {
                let newLog = WaterLog(date: day, glassesConsumed: waterGlassesConsumed, profile: profile)
                ctx.insert(newLog)
            }
            try ctx.save()
        } catch {
            print("Грешка при запазване на WaterLog: \(error)")
        }
    }
    
    private func dismissKeyboard() {
        isSearchFieldFocused = false
    }
    
    private func dismissKeyboardAndSearch() {
        isSearchFieldFocused = false
        globalSearchText = ""
    }
    
    private func presentMealPlanPicker() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isShowingMealPlanPicker = true
            mealPlanMenuState = .full
            navBarIsHiden = true
            if isSearching {
                onInternalFieldFocused()
            }
        }
    }
    
    private func dismissMealPlanPicker() {
        withAnimation(.easeInOut(duration: 0.3)) {
            mealPlanMenuState = .collapsed
            isShowingMealPlanPicker = false
            selectedPlanForPreview = nil
            navBarIsHiden = false
        }
    }
    
    private var selectedNutrientItem: NutriItem? {
        guard let id = selectedNutrientID else { return nil }
        
        if showAll {
            return allItemsState?.first { $0.nutrientID == id }
            ?? collapsedItemsState?.first { $0.nutrientID == id }
        } else {
            return collapsedItemsState?.first { $0.nutrientID == id }
            ?? allItemsState?.first { $0.nutrientID == id }
        }
    }
    
    @ViewBuilder
    private var calorieRing: some View {
        let progress = targetCalories > 0 ? (totalCalories / targetCalories) : 0
        
        ZStack {
            Circle()
                .stroke(lineWidth: 6)
                .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.2))
            
            Circle()
                .trim(from: 0.0, to: min(progress, 1.0))
                .stroke(style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .foregroundColor(.orange)
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear(duration: 0.5), value: progress)
            
            VStack(spacing: 1) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                
                Text(String(format: "%.0f", totalCalories))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                
                Rectangle()
                    .frame(width: 25, height: 1)
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
                
                Text(String(format: "%.0f", targetCalories))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
            }
        }
    }
    
    @ViewBuilder
    private var macroProportionRing: some View {
        let diameter: CGFloat = 60
        
        let centralDiameter = diameter * 0.65
        let ringThickness = diameter * 0.11
        let canalThickness = diameter * 0.12
        
        MacroCPFRingView(
            proportions: macroProportionsData,
            centralContentDiameter: centralDiameter,
            donutRingThickness: ringThickness,
            canalRingThickness: canalThickness,
            ringTrackColor: effectManager.currentGlobalAccentColor.opacity(0.2),
            totalReferenceValue: totalConsumedGrams
        )
        .id(totalConsumedGrams)
    }
    
    private var selectedMealNameString: String {
        guard let id = selectedMealID,
              let m  = dailyMeals.first(where: { $0.id == id }) else { return "" }
        return m.name
    }
    
    private var mealLine: String {
        guard let id = selectedMealID,
              let m  = dailyMeals.first(where: { $0.id == id }) else { return "" }
        return "\(m.name) • \(tStr(secs(m.startTime))) – \(tStr(secs(m.endTime)))"
    }
    
    private func mergedFoods(_ meals: [Meal.ID : [FoodItem : Double]]) -> [FoodItem : Double] {
        var merged: [FoodItem : Double] = [:]
        for (_, foods) in meals {
            for (item, g) in foods {
                merged[item, default: 0] += g
            }
        }
        return merged
    }
    
    private var totals: [String : Double] {
        nutrientTotals(for: allConsumedFoods)
    }
    
    private func nutrientTotals(for foods: [FoodItem : Double]) -> [String : Double] {
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
    
    private func toggleRing(_ item: NutriItem) {
        if selectedNutrientID == item.nutrientID {
            selectedNutrientID = nil
        } else {
            selectedNutrientID = item.nutrientID
        }
    }
    
    private let ringsPerRow:   Int     = 6
    private let ringSize:      CGFloat = 40
    private let ringSpacing:   CGFloat = 10
    private let labelSpacing:  CGFloat = 6
    private let ringPadding:   CGFloat = 6
    
    private var ringCellWidth:  CGFloat { ringSize + ringPadding * 2 }
    private var labelHeight:    CGFloat { ringSize * 0.18 * 1.25 }
    private var ringCellHeight: CGFloat {
        ringSize + labelSpacing
        + ringSize * 0.22 * 1.25 * 2
        + ringPadding * 2 + 4
    }
    
    private func tStr(_ off: Double) -> String {
        tFmt.string(from: Calendar.current.startOfDay(for: chosenDate)
            .addingTimeInterval(off))
    }
    private func secs(_ d: Date) -> Double {
        Double(Calendar.current.dateComponents([.second],
                                               from: Calendar.current.startOfDay(for: d), to: d).second ?? 0)
    }
    private let tFmt = DateFormatter.shortTime
    
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            do {
                try await Task.sleep(for: .seconds(1.5))
                await saveMealsToCalendar()
            } catch {
                print("Autosave task cancelled.")
            }
        }
    }
    
    private func selectClosestMealToNow() {
        let nowSec = secs(Date())
        if let m = dailyMeals.min(by: {
            abs(secs($0.startTime) - nowSec) < abs(secs($1.startTime) - nowSec)
        }) {
            selectedMealID = m.id
        } else {
            selectedMealID = nil
        }
    }
    
    @ViewBuilder
    private func ringButton(for item: NutriItem, animate: Bool, useGlass: Bool) -> some View {
        let isSelected = item.nutrientID == selectedNutrientID
        
        Button(action: { toggleRing(item) }) {
            NutrientRingView(
                item: item,
                diameter: ringSize,
                isSelected: isSelected,
                animate: animate,
                accent: effectManager.currentGlobalAccentColor
            )
            .glassCardStyle(cornerRadius: 15)
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(
                    isSelected ? item.color.opacity(0.7) : Color.clear,
                    lineWidth: 2.5
                )
        )
        .animation(.easeInOut, value: isSelected)
    }
    @ViewBuilder
    private var collapsedRings: some View {
        switch collapsedItemsState {
        case .some(let items) where !items.isEmpty:
            let pages = stride(from: 0, to: items.count, by: ringsPerRow)
                .map { Array(items[$0 ..< min($0 + ringsPerRow, items.count)]) }
            
            GeometryReader { geo in
                let pageWidth = geo.size.width
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(pages.indices, id: \.self) { idx in
                            let cols = Array(repeating: GridItem(.fixed(ringCellWidth), spacing: ringSpacing), count: ringsPerRow)
                            LazyVGrid(columns: cols, spacing: ringSpacing) {
                                ForEach(pages[idx]) { item in
                                    ringButton(for: item, animate: true, useGlass: true)
                                }
                            }
                            .frame(width: pageWidth, height: ringCellHeight)
                            .contentShape(Rectangle())
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
            }
            .frame(height: ringCellHeight + ringPadding * 2)
            .padding(.top, 6)
            
        case .some:
            EmptyView()
            
        case .none:
            ProgressView()
                .frame(height: ringCellHeight + ringPadding * 2)
                .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
        }
    }
    
    private var expandedRings: some View {
        Group {
            if let items = allItemsState {
                let cols = Array(repeating: GridItem(.fixed(ringCellWidth), spacing: ringSpacing), count: ringsPerRow)
                
                LazyVGrid(columns: cols, spacing: ringSpacing) {
                    ForEach(items) { item in
                        ringButton(for: item, animate: false, useGlass: true)
                            .transaction { $0.disablesAnimations = true }
                    }
                }
                .padding(.vertical, 8)
                .transition(.opacity.animation(.easeInOut))
                
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
            }
        }
    }
    
    private func calculateCollapsedItems() {
        Task(priority: .userInitiated) {
            let d = demographicString(for: profile)
            let currentTotals = self.totals
            
            let mins = profile.priorityMinerals.map { m -> NutriItem in
                var item = NutriItem(mineral: m, demographic: d)
                if let mg = currentTotals[item.nutrientID ?? ""] { item.amount = fromMg(mg, to: item.unit) }
                return item
            }
            let vits = profile.priorityVitamins.map { v -> NutriItem in
                var item = NutriItem(vitamin: v, demographic: d)
                if let mg = currentTotals[item.nutrientID ?? ""] { item.amount = fromMg(mg, to: item.unit) }
                return item
            }
            var computedItems = mins + vits
            computedItems.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            
            let achievedCount = computedItems.filter(isGoalMet).count
            let totalCount = computedItems.count
            
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.collapsedItemsState = computedItems
                    self.goalsAchieved = achievedCount
                    self.totalGoals = totalCount
                }
            }
        }
    }
    
    private func calculateAllItems() {
        Task(priority: .userInitiated) {
            let d = demographicString(for: profile)
            let currentTotals = nutrientTotals(for: allConsumedFoods)
            
            let mins = minerals.map { m -> NutriItem in
                var item = NutriItem(mineral: m, demographic: d)
                if let mg = currentTotals[item.nutrientID ?? ""] { item.amount = fromMg(mg, to: item.unit) }
                return item
            }
            let vits = vitamins.map { v -> NutriItem in
                var item = NutriItem(vitamin: v, demographic: d)
                if let mg = currentTotals[item.nutrientID ?? ""] { item.amount = fromMg(mg, to: item.unit) }
                return item
            }
            var computedItems = mins + vits
            computedItems.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.allItemsState = computedItems
                }
            }
        }
    }
    
    private func demographicString(for p: Profile) -> String {
        let isF = p.gender.lowercased().hasPrefix("f")
        if isF {
            if p.isPregnant { return Demographic.pregnantWomen }
            if p.isLactating { return Demographic.lactatingWomen }
        }
        let m = Calendar.current.dateComponents([.month], from: p.birthday, to: Date()).month ?? 0
        if m < 6 { return Demographic.babies0_6m }
        if m < 12 { return Demographic.babies7_12m }
        switch p.age {
        case 1..<4: return Demographic.children1_3y
        case 4..<9: return Demographic.children4_8y
        case 9..<14: return Demographic.children9_13y
        case 14..<19: return isF ? Demographic.adolescentFemales14_18y : Demographic.adolescentMales14_18y
        default: return isF ? (p.age <= 50 ? Demographic.adultWomen19_50y : Demographic.adultWomen51plusY) : (p.age <= 50 ? Demographic.adultMen19_50y : Demographic.adultMen51plusY)
        }
    }
    
    private func mergedMeals(template: [Meal], calendar events: [Meal]) -> [Meal] {
        guard !events.isEmpty else {
            return template.sorted { $0.startTime < $1.startTime }
        }
        
        var result: [Meal] = []
        var usedEventIndices = Set<Int>()
        
        for t in template {
            if let idx = events.firstIndex(where: { namesMatch(t, $0) || timesClose(t, $0, minutes: 45) }) {
                result.append(events[idx])
                usedEventIndices.insert(idx)
            } else {
                result.append(t)
            }
        }
        
        for (i, ev) in events.enumerated() where !usedEventIndices.contains(i) {
            result.append(ev)
        }
        
        return result.sorted { $0.startTime < $1.startTime }
    }
    
    private func namesMatch(_ a: Meal, _ b: Meal) -> Bool {
        let an = a.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let bn = b.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return an == bn
    }
    
    private func timesClose(_ a: Meal, _ b: Meal, minutes: Int) -> Bool {
        let tol = TimeInterval(minutes * 60)
        return abs(a.startTime.timeIntervalSince1970 - b.startTime.timeIntervalSince1970) <= tol
    }
    
    private func invisiblePayload(for foods: [FoodItem: Double]) -> String? {
        let visible = foods
            .filter { $0.value > 0 }
            .sorted(by: { $0.key.name < $1.key.name })
            .map { "\($0.key.name)=\($0.value)" }
            .joined(separator: "|")
        guard !visible.isEmpty else { return nil }
        return OptimizedInvisibleCoder.encode(from: visible)
    }
    
    private func isGoalMet(_ i: NutriItem) -> Bool {
        if let dn = i.dailyNeed,  i.amount < dn { return false }
        if let ul = i.upperLimit, i.amount > ul { return false }
        return true
    }
    
    @State private var totalGoals: Int = 0
    @State private var goalsAchieved: Int = 0
    
    private func goalProgress(on date: Date) -> Double? {
        let k = key(for: date)
        if let ready = dayProgress[k] { return ready }
        
        Task {
            if let fresh = await computeProgress(for: date, profile: self.profile) {
                await MainActor.run { dayProgress[k] = fresh
                }
            }
        }
        return nil
    }
    
    
    @MainActor
    private func preloadProgress(weeksRange range: Int) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var cache: [DateComponents : Double] = [:]
        for w in -range...range {
            if let week = cal.date(byAdding: .day, value: w * 7, to: today) {
                for i in 0..<7 {
                    guard let d = cal.date(byAdding: .day, value: i, to: week) else { continue }
                    if let pr = await computeProgress(for: d, profile: self.profile) {
                        cache[key(for: d)] = pr
                    }
                }
            }
        }
        dayProgress = cache
    }
    
    private func computeProgress(for date: Date, profile: Profile) async -> Double? {
        let template = profile.meals(for: date)
        let calendarEvents = await CalendarViewModel.shared.meals(forProfile: profile, on: date)
        let meals = mergedMeals(template: template, calendar: calendarEvents)
        
        let foodsByMeal = Dictionary(
            uniqueKeysWithValues: meals.map { ($0.id, $0.foods(using: self.ctx)) }
        )
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
    private func refreshProgress(for date: Date) async {
        let comps = key(for: date)
        if let p = await computeProgress(for: date, profile: self.profile) {
            dayProgress[comps] = p
        } else {
            dayProgress.removeValue(forKey: comps)
        }
    }
    
    private func updateStorageAndMeal(for item: FoodItem, newGrams: Double) {
        let roundedGrams = (newGrams * 10000).rounded() / 10000.0
        
        let existingItemKey = currentFoods.wrappedValue.keys.first { $0.id == item.id }
        
        let oldGrams = existingItemKey != nil ? currentFoods.wrappedValue[existingItemKey!]! : 0.0
        let delta = roundedGrams - oldGrams
        let mealID = selectedMealID ?? UUID()
        
        guard abs(delta) > 0.01 else { return }
        
        if roundedGrams > 0 && oldGrams == 0 {
            logRecentlyAdded(food: item)
        }
        
        if let key = existingItemKey {
            currentFoods.wrappedValue[key] = roundedGrams
        } else {
            currentFoods.wrappedValue[item] = roundedGrams
        }
        
        guard isDateEligibleForStorageUpdate else { return }
        
        recursivelyUpdateStock(for: item, delta: delta, mealID: mealID, actingProfile: profile)
    }
    
    private func recursivelyUpdateStock(for item: FoodItem, delta: Double, mealID: UUID, actingProfile: Profile) {
        _ = actingProfile.hasSeparateStorage ? actingProfile : nil
        
        if delta > 0 {
            var remainingToConsume = delta
            
            if (item.isRecipe || item.isMenu), let storageItem = getStorageItem(for: item) {
                let availableInStock = storageItem.totalQuantity
                let amountToDeductFromStock = min(remainingToConsume, availableInStock)
                
                if amountToDeductFromStock > 0 {
                    updateStorageForSingleItem(for: item, newGrams: amountToDeductFromStock, oldGrams: 0, mealID: mealID, actingProfile: actingProfile)
                    remainingToConsume -= amountToDeductFromStock
                }
            }
            
            if remainingToConsume > 0.01, (item.isRecipe || item.isMenu) {
                handleRecipeConsumptionUpdate(recipe: item, gramsToMake: remainingToConsume, mealID: mealID, actingProfile: actingProfile)
            } else if remainingToConsume > 0.01 {
                updateStorageForSingleItem(for: item, newGrams: remainingToConsume, oldGrams: 0, mealID: mealID, actingProfile: actingProfile)
            }
        }
        else {
            let amountToReturn = abs(delta)
            
            if (item.isRecipe || item.isMenu), let ingredients = item.ingredients, !ingredients.isEmpty {
                guard let totalWeight = item.totalWeightG, totalWeight > 0 else { return }
                let returnFactor = amountToReturn / totalWeight
                
                for link in ingredients {
                    guard let ingredientFood = link.food else { continue }
                    let ingredientQtyToReturn = link.grams * returnFactor
                    recursivelyUpdateStock(for: ingredientFood, delta: -ingredientQtyToReturn, mealID: mealID, actingProfile: actingProfile)
                }
            } else {
                updateStorageForSingleItem(for: item, newGrams: 0, oldGrams: amountToReturn, mealID: mealID, actingProfile: actingProfile)
            }
        }
    }
    
    private func handleRecipeConsumptionUpdate(recipe: FoodItem, gramsToMake: Double, mealID: UUID, actingProfile: Profile) {
        guard let ingredients = recipe.ingredients, let totalRecipeWeight = recipe.totalWeightG, totalRecipeWeight > 0 else { return }
        
        let scalingFactor = gramsToMake / totalRecipeWeight
        
        for ingredientLink in ingredients {
            guard let ingredientFood = ingredientLink.food else { continue }
            let gramsNeededForIngredient = ingredientLink.grams * scalingFactor
            recursivelyUpdateStock(for: ingredientFood, delta: gramsNeededForIngredient, mealID: mealID, actingProfile: actingProfile)
        }
    }
    
    private func logRecentlyAdded(food: FoodItem) {
        if (food.isRecipe || food.isMenu), let ingredients = food.ingredients {
            for ingredientLink in ingredients {
                if let ingredientFood = ingredientLink.food {
                    logRecentlyAdded(food: ingredientFood)
                }
            }
            return
        }
        
        let foodID = food.id
        
        do {
            let predicate: Predicate<RecentlyAddedFood>
            
            if let profileToLogFor = profile.hasSeparateStorage ? profile : nil {
                let profileID = profileToLogFor.persistentModelID
                predicate = #Predicate<RecentlyAddedFood> {
                    $0.food?.id == foodID && $0.profile?.persistentModelID == profileID
                }
            } else {
                predicate = #Predicate<RecentlyAddedFood> {
                    $0.food?.id == foodID && $0.profile == nil
                }
            }
            
            let descriptor = FetchDescriptor(predicate: predicate)
            let existing = try ctx.fetch(descriptor).first
            
            if let existingEntry = existing {
                existingEntry.dateAdded = Date()
            } else {
                let profileOwner = profile.hasSeparateStorage ? profile : nil
                let newRecentEntry = RecentlyAddedFood(dateAdded: Date(), food: food, profile: profileOwner)
                ctx.insert(newRecentEntry)
            }
            
            cleanupRecentItems()
            
        } catch {
            print("Error fetching or updating recent food item: \(error)")
        }
    }
    
    private func cleanupRecentItems() {
        do {
            let predicate: Predicate<RecentlyAddedFood>
            
            if let profileToCleanFor = profile.hasSeparateStorage ? profile : nil {
                let profileID = profileToCleanFor.persistentModelID
                predicate = #Predicate<RecentlyAddedFood> {
                    $0.profile?.persistentModelID == profileID
                }
            } else {
                predicate = #Predicate<RecentlyAddedFood> {
                    $0.profile == nil
                }
            }
            
            let descriptor = FetchDescriptor(
                predicate: predicate,
                sortBy: [SortDescriptor(\.dateAdded, order: .forward)]
            )
            let allItemsForOwner = try ctx.fetch(descriptor)
            
            if allItemsForOwner.count > maxRecentItems {
                let itemsToDeleteCount = allItemsForOwner.count - maxRecentItems
                let itemsToDelete = allItemsForOwner.prefix(itemsToDeleteCount)
                for item in itemsToDelete {
                    ctx.delete(item)
                }
            }
            if ctx.hasChanges {
                try ctx.save()
            }
        } catch {
            print("Failed to cleanup recent items: \(error)")
        }
    }
    
    private func deleteFoodFromMeal(_ item: FoodItem) {
        updateStorageAndMeal(for: item, newGrams: 0)
        currentFoods.wrappedValue.removeValue(forKey: item)
        
        if let mealID = selectedMealID,
           (foodsByMeal[mealID]?.isEmpty ?? true),
           let index = dailyMeals.firstIndex(where: { $0.id == mealID }) {
            dailyMeals[index].notes = nil
        }
        
        scheduleAutosave()
    }
    
    private func isStockSufficient(for item: FoodItem, requestedGrams: Double) -> Bool {
        guard isDateEligibleForStorageUpdate else { return true }
        
        if !item.isRecipe && !item.isMenu {
            guard let storageItem = getStorageItem(for: item) else {
                return true
            }
            
            let previouslyDeducted = getLink(for: item, mealID: selectedMealID ?? UUID(), actingProfile: profile)?.deductedQuantity ?? 0
            let effectiveStock = storageItem.totalQuantity + previouslyDeducted
            return effectiveStock >= requestedGrams
        }
        
        var remainingGramsNeeded = requestedGrams
        if let recipeStorageItem = getStorageItem(for: item) {
            let previouslyDeducted = getLink(for: item, mealID: selectedMealID ?? UUID(), actingProfile: profile)?.deductedQuantity ?? 0
            let effectiveStock = recipeStorageItem.totalQuantity + previouslyDeducted
            let canTakeFromStock = min(remainingGramsNeeded, effectiveStock)
            remainingGramsNeeded -= canTakeFromStock
        }
        
        if remainingGramsNeeded <= 0.01 {
            return true
        }
        
        guard let ingredients = item.ingredients, !ingredients.isEmpty,
              let totalRecipeWeight = item.totalWeightG, totalRecipeWeight > 0 else {
            return true
        }
        
        let scalingFactor = remainingGramsNeeded / totalRecipeWeight
        
        for ingredientLink in ingredients {
            guard let ingredientFood = ingredientLink.food else { continue }
            let gramsNeededForIngredient = ingredientLink.grams * scalingFactor
            
            if !isStockSufficient(for: ingredientFood, requestedGrams: gramsNeededForIngredient) {
                return false
            }
        }
        
        return true
    }
    
    private func updateStorageForSingleItem(for food: FoodItem, newGrams: Double, oldGrams: Double, mealID: UUID, actingProfile: Profile) {
        let delta = newGrams - oldGrams
        guard abs(delta) > 0.01, let storageItem = getStorageItem(for: food) else { return }
        
        let transactionAndLinkOwner = actingProfile.hasSeparateStorage ? actingProfile : nil
        
        let existingLink = getLink(for: food, mealID: mealID, actingProfile: transactionAndLinkOwner)
        
        if delta > 0 {
            let quantityToDeduct = min(delta, storageItem.totalQuantity)
            if quantityToDeduct > 0 {
                consumeFromStorage(item: storageItem, quantity: quantityToDeduct, actingProfile: transactionAndLinkOwner)
                if let link = existingLink {
                    link.deductedQuantity += quantityToDeduct
                } else {
                    ctx.insert(MealLogStorageLink(date: chosenDate, mealID: mealID, deductedQuantity: quantityToDeduct, food: food, profile: transactionAndLinkOwner))
                }
            }
        } else if delta < 0 {
            guard let link = existingLink, link.deductedQuantity > 0 else { return }
            let quantityToReturn = min(abs(delta), link.deductedQuantity)
            if quantityToReturn > 0 {
                returnToStorage(item: storageItem, quantity: quantityToReturn, actingProfile: transactionAndLinkOwner)
                link.deductedQuantity -= quantityToReturn
                if link.deductedQuantity <= 0.01 {
                    ctx.delete(link)
                }
            }
        }
    }
    
    private func returnAllStockForFoodInMeal(food: FoodItem, mealID: UUID, actingProfile: Profile) {
        guard isDateEligibleForStorageUpdate else { return }
        
        let transactionAndLinkOwner = actingProfile.hasSeparateStorage ? actingProfile : nil
        
        guard let link = getLink(for: food, mealID: mealID, actingProfile: transactionAndLinkOwner),
              let storageItem = getStorageItem(for: food)
        else { return }
        
        if link.deductedQuantity > 0 {
            returnToStorage(item: storageItem, quantity: link.deductedQuantity, actingProfile: transactionAndLinkOwner)
        }
        ctx.delete(link)
    }
    
    private func getStorageItem(for food: FoodItem) -> StorageItem? {
        let foodID = food.id
        let ownerID: PersistentIdentifier? = profile.hasSeparateStorage ? profile.persistentModelID : nil
        
        let predicate = #Predicate<StorageItem> {
            $0.food?.id == foodID && $0.owner?.persistentModelID == ownerID
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        return try? ctx.fetch(descriptor).first
    }
    
    private func getLink(for food: FoodItem, mealID: UUID, actingProfile: Profile?) -> MealLogStorageLink? {
        let dateStart = Calendar.current.startOfDay(for: chosenDate)
        let foodID = food.id
        let profileID = actingProfile?.persistentModelID
        
        let predicate = #Predicate<MealLogStorageLink> {
            $0.food?.id == foodID &&
            $0.mealID == mealID &&
            $0.profile?.persistentModelID == profileID &&
            $0.date == dateStart
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        return try? ctx.fetch(descriptor).first
    }
    
    private func consumeFromStorage(item: StorageItem, quantity: Double, actingProfile: Profile?) {
        var remainingToConsume = quantity
        let sortedBatches = item.batches.sorted { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
        
        for batch in sortedBatches {
            if remainingToConsume <= 0 { break }
            let amountFromThisBatch = min(remainingToConsume, batch.quantity)
            batch.quantity -= amountFromThisBatch
            remainingToConsume -= amountFromThisBatch
            if batch.quantity <= 0.01 { ctx.delete(batch) }
        }
        ctx.insert(StorageTransaction(date: Date(), type: .mealConsumption, quantityChange: -quantity, profile: actingProfile, food: item.food))
    }
    
    private func returnToStorage(item: StorageItem, quantity: Double, actingProfile: Profile?) {
        if let existingBatch = item.batches.first(where: { $0.expirationDate == nil }) {
            existingBatch.quantity += quantity
        } else {
            let newBatch = Batch(quantity: quantity)
            newBatch.storageItem = item
            ctx.insert(newBatch)
        }
        ctx.insert(StorageTransaction(date: Date(), type: .mealConsumption, quantityChange: quantity, profile: actingProfile, food: item.food))
    }
    
    @ViewBuilder
    private var userToolbar: some View {
        HStack {
            Text(currentTimeString)
                .font(.system(size: 16))
                .fontWeight(.medium)
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .onAppear {
                    self.currentTimeString = tFmt.string(from: Date())
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
                            Circle()
                                .fill(effectManager.currentGlobalAccentColor.opacity(0.2))
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
    
    
    private func dismissRingDetail() {
        withAnimation(.easeInOut(duration: 0.3)) {
            ringDetailMenuState = .collapsed
            showingRingDetail = nil
            navBarIsHiden = false
        }
    }
    
    private func presentRingDetail(_ type: RingDetailType) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showingRingDetail = type
            ringDetailMenuState = .full
            navBarIsHiden = true
            if isSearching {
                onInternalFieldFocused()
            }
        }
    }
    
    private func ringDetailContent(for detailType: RingDetailType) -> some View {
        VStack(spacing: 0) {
            switch detailType {
            case .goals:
                goalsDetailView
            case .calories:
                caloriesDetailView
            case .macros:
                macrosDetailView
            }
        }
        .id(detailType)
        .transition(.opacity.animation(.easeInOut(duration: 0.15)))
    }
    
    @ViewBuilder
    private var goalsDetailView: some View {
        GoalsDetailRingView(
            achieved: goalsAchieved,
            total: totalGoals,
            onDismiss: dismissRingDetail,
            items: collapsedItemsState,
            allConsumedFoods: self.allConsumedFoods
        )
        .padding(.horizontal, -10)
    }
    
    @ViewBuilder
    private var caloriesDetailView: some View {
        CaloriesDetailRingView(
            totalCalories: totalCalories,
            targetCalories: targetCalories,
            onDismiss: dismissRingDetail,
            allConsumedFoods: self.allConsumedFoods
        )
    }
    
    @ViewBuilder
    private var macrosDetailView: some View {
        MacrosDetailRingView(
            totalProteinGrams: totalProteinGrams,
            totalCarbsGrams: totalCarbsGrams,
            totalFatGrams: totalFatGrams,
            onDismiss: dismissRingDetail,
            allConsumedFoods: self.allConsumedFoods
        )
    }
    
    private func loadMeals(preselect idToKeep: Meal.ID? = nil) {
        loadMealsTask?.cancel()
        let previousName = dailyMeals.first(where: { $0.id == idToKeep })?.name
        
        loadMealsTask = Task { @MainActor in
            if Task.isCancelled { return }
            
            let events = await CalendarViewModel.shared.meals(forProfile: profile, on: chosenDate)
            if Task.isCancelled { return }
            
            let day = Calendar.current.startOfDay(for: chosenDate)
            let profileID = profile.persistentModelID
            var descriptor = FetchDescriptor<WaterLog>(predicate: #Predicate {
                $0.profile?.persistentModelID == profileID && $0.date == day
            })
            descriptor.fetchLimit = 1
            
            if let log = try? ctx.fetch(descriptor).first {
                self.waterGlassesConsumed = log.glassesConsumed
            } else {
                self.waterGlassesConsumed = 0
            }
            
            let template = profile.meals(for: chosenDate)
            let newDailyMeals = mergedMeals(template: template, calendar: events)
            
            if Task.isCancelled { return }
            
            self.dailyMeals = newDailyMeals
            
            self.foodsByMeal = Dictionary(
                uniqueKeysWithValues: newDailyMeals.map { ($0.id, $0.foods(using: ctx)) }
            )
            
            self.initialFoodsByMeal = self.foodsByMeal
            
            calculateCollapsedItems()
            if showAll { calculateAllItems() }
            
            var mealWasSelected = false
            if let targetName = mealNameToPreselect,
               let foundMeal = dailyMeals.first(where: { $0.name.caseInsensitiveCompare(targetName) == .orderedSame }) {
                selectedMealID = foundMeal.id
                mealNameToPreselect = nil
                mealWasSelected = true
            }
            
            if !mealWasSelected {
                if let id = idToKeep, dailyMeals.contains(where: { $0.id == id }) {
                    selectedMealID = id
                } else if let name = previousName, let found = dailyMeals.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    selectedMealID = found.id
                } else {
                    selectClosestMealToNow()
                }
            }
            
            self.isBootstrapping = false
        }
    }
    
    @MainActor
    private func saveMealsToCalendar() async {
        for meal in dailyMeals {
            if let originalMealState = self.dailyMeals.first(where: { $0.id == meal.id }) {
                await saveSingleMeal(meal, originalState: originalMealState, with: invisiblePayload(for: foodsByMeal[meal.id] ?? [:]))
            }
        }
        
        NotificationCenter.default.post(name: .mealTimeDidChange, object: nil)
        await refreshProgress(for: chosenDate)
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: chosenDate)
        animateDates.insert(comps)
        animateStamp.toggle()
        await BadgeManager.shared.checkAndAwardBadges(for: profile, using: ctx)
    }
    
    @MainActor
    private func saveSingleMeal(_ meal: Meal, originalState: Meal, with notes: String?) async {
        let currentFoods = foodsByMeal[meal.id] ?? [:]
        let initialFoods = initialFoodsByMeal[meal.id] ?? [:]
        
        let hasPropertyChanged = meal.name != originalState.name ||
        meal.startTime != originalState.startTime ||
        meal.endTime != originalState.endTime ||
        meal.reminderMinutes != originalState.reminderMinutes
        
        let haveFoodsChanged = currentFoods != initialFoods
        
        guard hasPropertyChanged || haveFoodsChanged else {
            print(" Skipping save for meal '\(meal.name)', no changes detected.")
            return
        }
        
        let nonZeroFoods = currentFoods.filter { $0.value > 0 }
        
        if let oldID = meal.notificationID {
            NotificationManager.shared.cancelNotification(id: oldID)
            meal.notificationID = nil
        }
        
        let shouldDeleteEvent = !initialFoods.isEmpty && nonZeroFoods.isEmpty
        
        if shouldDeleteEvent {
            if let idToDelete = meal.calendarEventID {
                _ = await CalendarViewModel.shared.deleteEvent(withIdentifier: idToDelete)
                meal.calendarEventID = nil
            }
            meal.notes = nil
            if ctx.hasChanges { try? ctx.save() }
            return
        }
        
        if let minutes = meal.reminderMinutes, minutes > 0 {
            let reminderDate = meal.startTime.addingTimeInterval(-TimeInterval(minutes * 60))
            if reminderDate.timeIntervalSinceNow > 0 {
                do {
                    let newID = try await NotificationManager.shared.scheduleNotification(
                        title: "🍽️ Meal Reminder",
                        body: "It's time for your \(meal.name). Enjoy!",
                        timeInterval: reminderDate.timeIntervalSinceNow,
                        userInfo: [
                            "mealID": meal.id.uuidString,
                            "mealDate": meal.startTime.timeIntervalSince1970
                        ],
                        profileID: profile.id
                    )
                    meal.notificationID = newID
                } catch { print("Error scheduling notification: \(error)") }
            }
        }
        
        let start = meal.startTime
        var end = meal.endTime
        if end <= start { end = Calendar.current.date(byAdding: .hour, value: 1, to: start)! }
        
        let payloadToSave = invisiblePayload(for: nonZeroFoods) ?? (notes ?? "")
        
        let (success, newEventID) = await CalendarViewModel.shared.createEvent(
            forProfile: profile,
            startDate: start,
            endDate: end,
            title: meal.name,
            invisiblePayload: payloadToSave,
            existingEventID: meal.calendarEventID,
            reminderMinutes: nil
        )
        
        if success, let id = newEventID, meal.calendarEventID != id {
            meal.calendarEventID = id
        }
        
        if ctx.hasChanges {
            try? ctx.save()
        }
    }
    
    private func add(foodItem: FoodItem) {
        if (foodItem.isMenu), let ingredients = foodItem.ingredients, !ingredients.isEmpty {
            for link in ingredients {
                guard let ingredient = link.food else { continue }
                updateStorageAndMeal(for: ingredient, newGrams: link.grams)
            }
        } else {
            let weightG = foodItem.referenceWeightG
            updateStorageAndMeal(for: foodItem, newGrams: weightG)
        }
        
        dismissKeyboardAndSearch()
        scheduleAutosave()
        
        scrollToItemID = foodItem.id
    }
    
    private var headerTopPadding: CGFloat {
        return -safeAreaInsets.top + 10
    }
    
    private func processMealPlanAddition(mode: MealAddMode) {
        guard let daysToAdd = planDaysToAdd else { return }
        self.planDaysToAdd = nil
        isSaving = true
        
        Task(priority: .userInitiated) {
            let calendar = Calendar.current
            let startDate = chosenDate
            
            for (index, planDay) in daysToAdd.enumerated() {
                guard let targetDate = calendar.date(byAdding: .day, value: index, to: startDate) else { continue }
                
                let existingMealsForTargetDate = await CalendarViewModel.shared.meals(forProfile: profile, on: targetDate)
                
                for planMeal in planDay.meals {
                    guard let mealTemplate = profile.meals.first(where: { $0.name == planMeal.mealName }) else { continue }
                    
                    let targetMeal = mealTemplate.detached(for: targetDate)
                    let mealID = targetMeal.id
                    
                    let existingMealEvent = existingMealsForTargetDate.first { $0.name == targetMeal.name }
                    let existingEventID = existingMealEvent?.calendarEventID
                    
                    var finalFoods: [FoodItem: Double] = [:]
                    
                    if mode == .overwrite {
                        if let existing = existingMealEvent {
                            for (food, grams) in existing.foods(using: ctx) {
                                recursivelyUpdateStock(for: food, delta: -grams, mealID: mealID, actingProfile: profile)
                            }
                        }
                        finalFoods = [:]
                    } else {
                        if let existing = existingMealEvent {
                            finalFoods = existing.foods(using: ctx)
                        }
                    }
                    
                    for entry in planMeal.entries {
                        guard let food = entry.food else { continue }
                        let gramsToAdd = entry.grams
                        
                        // --- НАЧАЛО НА КОРЕКЦИЯТА ---
                        // Добавяме извикване на функцията за логване тук.
                        logRecentlyAdded(food: food)
                        // --- КРАЙ НА КОРЕКЦИЯТА ---
                        
                        recursivelyUpdateStock(for: food, delta: gramsToAdd, mealID: mealID, actingProfile: profile)
                        finalFoods[food, default: 0] += gramsToAdd
                    }
                    
                    let payload = invisiblePayload(for: finalFoods)
                    _ = await CalendarViewModel.shared.createEvent(
                        forProfile: profile,
                        startDate: targetMeal.startTime,
                        endDate: targetMeal.endTime,
                        title: targetMeal.name,
                        invisiblePayload: payload,
                        existingEventID: existingEventID
                    )
                }
            }
            
            await MainActor.run {
                self.isSaving = false
                self.loadMeals()
            }
        }
    }
    
    private func aiBottomPadding(for geometry: GeometryProxy) -> CGFloat {
        let size = geometry.size
        guard size.width > 0 else { return 75 }
        let aspectRatio = size.height / size.width
        return aspectRatio > 1.9 ? 75 : 95
    }
    
    private func aiTrailingPadding(for geometry: GeometryProxy) -> CGFloat { 45 }
    
    private func aiDragGesture(geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($aiGestureDragOffset) { value, state, _ in
                state = value.translation
                DispatchQueue.main.async { self.aiIsPressed = true }
            }
            .onChanged { value in
                if abs(value.translation.width) > 10 || abs(value.translation.height) > 10 {
                    self.aiIsDragging = true
                }
            }
            .onEnded { value in
                self.aiIsPressed = false
                if aiIsDragging {
                    var newOffset = self.aiButtonOffset
                    newOffset.width += value.translation.width
                    newOffset.height += value.translation.height
                    
                    let buttonRadius: CGFloat = 40
                    let viewSize = geometry.size
                    let safeArea = geometry.safeAreaInsets
                    
                    let minY = -viewSize.height + buttonRadius + safeArea.top
                    let maxY = -25 + safeArea.bottom
                    newOffset.height = min(maxY, max(minY, newOffset.height))
                    
                    self.aiButtonOffset = newOffset
                    self.saveAIButtonPosition()
                } else {
                    self.handleAITap()
                }
                self.aiIsDragging = false
            }
    }
    
    func ensureAIAvailableOrShowMessage() -> Bool {
        switch GlobalState.aiAvailability {
        case .available:
            return true
        case .deviceNotEligible:
            // Няма да се вижда бутон, но пазим безопасността и тук
            alertMsg = "This device doesn’t support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            alertMsg = "Apple Intelligence is turned off. Enable it in Settings to use AI meal generation."
        case .modelNotReady:
            alertMsg = "The model is downloading or preparing. Please try again in a bit."
        case .unavailableUnsupportedOS:
            alertMsg = "Apple Intelligence requires iOS 26 or newer. Update your OS to use this feature."
        case .unavailableOther:
            alertMsg = "Apple Intelligence is currently unavailable for an unknown reason."
        }
        showAlert = true
        return false
    }
    
    private func handleAITap() {
        guard ensureAIAvailableOrShowMessage() else { return }
        
        let emptyMeals = dailyMeals.filter { meal in
            foodsByMeal[meal.id]?.isEmpty ?? true
        }
        
        guard !emptyMeals.isEmpty else {
            alertMsg = "All meals for this day already have items. Clear some meals if you want to generate new ones."
            showAlert = true
            return
        }
        
        let populatedMeals = dailyMeals.filter { meal in
            !(foodsByMeal[meal.id]?.isEmpty ?? true)
        }
        
        let mealsToGenerate: [Int: [String]] = [1: emptyMeals.map { $0.name }]
        
        let existingMeals: [Int: [MealPlanPreviewMeal]] = [1: populatedMeals.map { meal -> MealPlanPreviewMeal in
            let items: [MealPlanPreviewItem] = (foodsByMeal[meal.id] ?? [:]).compactMap { (food, grams) -> MealPlanPreviewItem? in
                MealPlanPreviewItem(
                    name: food.name,
                    grams: grams,
                    kcal: food.calories(for: grams)
                )
            }
            return MealPlanPreviewMeal(name: meal.name, descriptiveTitle: meal.descriptiveAIName, items: items, startTime: nil)
        }]
        
        // --- НАЧАЛО НА ПРОМЯНАТА ---
        // 1. Дефинираме ключа, който използваме и в AIDailyMealGeneratorView.
        let selectedPromptsKey = "AIDailyMealGenerator_SelectedPrompts"
        
        // 2. Извличаме запазените ID-та (като стрингове) от UserDefaults.
        let savedPromptIDStrings = UserDefaults.standard.stringArray(forKey: selectedPromptsKey) ?? []
        let selectedPromptIDs = savedPromptIDStrings.compactMap { UUID(uuidString: $0) }
        
        var selectedPromptsText: [String]? = nil
        
        // 3. Ако имаме ID-та, извличаме съответните текстове от SwiftData.
        if !selectedPromptIDs.isEmpty {
            let predicate = #Predicate<Prompt> { prompt in
                selectedPromptIDs.contains(prompt.id)
            }
            let descriptor = FetchDescriptor<Prompt>(predicate: predicate)
            
            if let fetchedPrompts = try? ctx.fetch(descriptor), !fetchedPrompts.isEmpty {
                selectedPromptsText = fetchedPrompts.map { $0.text }
                print("Found \(selectedPromptsText?.count ?? 0) saved prompts to use for generation.")
            }
        }
        
        triggerAIGenerationToast()
        
        // 4. Подаваме извлечените текстове към AIManager.
        if let newJob = aiManager.startPlanFill(
            for: profile,
            daysAndMeals: mealsToGenerate,
            existingMeals: existingMeals,
            selectedPrompts: selectedPromptsText, // <-- ПРОМЯНАТА Е ТУК
            jobType: .nutritionsDetailDailyMealPlan
        ) {
            self.runningGenerationJobID = newJob.id
        } else {
            alertMsg = "Could not start AI generation job."
            showAlert = true
            toastTimer?.invalidate()
            toastTimer = nil
            withAnimation {
                showAIGenerationToast = false
            }
        }
        // --- КРАЙ НА ПРОМЯНАТА ---
    }
    
    private func saveAIButtonPosition() {
        let d = UserDefaults.standard
        d.set(aiButtonOffset.width, forKey: "\(aiButtonPositionKey)_width")
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
        let currentOffset = CGSize(
            width: aiButtonOffset.width + aiGestureDragOffset.width,
            height: aiButtonOffset.height + aiGestureDragOffset.height
        )
        let scale = aiIsDragging ? 1.15 : (aiIsPressed ? 0.9 : 1.0)
        
        ZStack {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundColor(effectManager.currentGlobalAccentColor)
        }
        .frame(width: 60, height: 60)
        .glassCardStyle(cornerRadius: 32)
        .scaleEffect(scale)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: aiIsDragging)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: aiIsPressed)
        .padding(.trailing, aiTrailingPadding(for: geometry))
        .padding(.bottom, aiBottomPadding(for: geometry))
        .contentShape(Rectangle())
        .offset(currentOffset)
        .opacity(isAIButtonVisible ? 1 : 0)
        .disabled(!isAIButtonVisible)
        .gesture(aiDragGesture(geometry: geometry))
        .transition(.scale.combined(with: .opacity))
    }
    
    @ViewBuilder
    private var aiGenerationToast: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Generation Scheduled")
                        .fontWeight(.bold)
                    Text("You'll be notified when your plan is ready.")
                        .font(.caption)
                    
                    ProgressView(value: min(max(toastProgress, 0.0), 1.0), total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                        .animation(.linear, value: toastProgress)
                }
                
                Spacer()
                
                Button("OK") {
                    toastTimer?.invalidate()
                    toastTimer = nil
                    withAnimation {
                        showAIGenerationToast = false
                    }
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
    
    private func triggerAIGenerationToast() {
        toastTimer?.invalidate()
        toastProgress = 0.0
        withAnimation {
            showAIGenerationToast = true
        }
        
        let totalDuration = 5.0
        let updateInterval = 0.1
        let progressIncrement = updateInterval / totalDuration
        
        toastTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { timer in
            DispatchQueue.main.async {
                self.toastProgress = min(1.0, self.toastProgress + progressIncrement)
                if self.toastProgress >= 1.0 {
                    timer.invalidate()
                    self.toastTimer = nil
                    withAnimation {
                        self.showAIGenerationToast = false
                    }
                }
            }
        }
    }
    
    private func populateMealsFromPreview(_ preview: MealPlanPreview) async {
        guard let dayData = preview.days.first else { return }
        
        for generatedMeal in dayData.meals {
            guard let targetMealIndex = dailyMeals.firstIndex(where: { $0.name == generatedMeal.name }) else {
                continue
            }
            
            // UPDATED: Set the descriptive name on the meal object in our state array.
            dailyMeals[targetMealIndex].descriptiveAIName = generatedMeal.descriptiveTitle
            
            var foodsToAdd: [FoodItem: Double] = [:]
            for item in generatedMeal.items {
                let itemName = item.name
                let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate {
                    $0.name == itemName && !$0.isUserAdded
                })
                
                if let foodItem = (try? ctx.fetch(descriptor))?.first {
                    foodsToAdd[foodItem] = item.grams
                }
            }
            
            // Use the ID from the (now updated) meal in the state array.
            let mealID = dailyMeals[targetMealIndex].id
            foodsByMeal[mealID] = foodsToAdd
        }
        
        scheduleAutosave()
    }
    
    private enum PresentedNode: Identifiable, Equatable {
        case newNode
        case editNode(Node)
        
        var id: String {
            switch self {
            case .newNode:
                return "newNode"
            case .editNode(let node):
                // Най-простият и надежден начин е да се използва собственото UUID на бележката.
                return "editNode-\(node.id.uuidString)"
            }
        }
        
        static func == (lhs: PresentedNode, rhs: PresentedNode) -> Bool {
            lhs.id == rhs.id
        }
    }
    
}

