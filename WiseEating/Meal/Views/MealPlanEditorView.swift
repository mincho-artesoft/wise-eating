import SwiftUI
import SwiftData

@MainActor
struct MealPlanEditorView: View {
    
    // MARK: - AI & Prompts State
    @Query(sort: \Prompt.creationDate, order: .reverse) private var allPrompts: [Prompt]
    @State private var selectedPromptIDs: Set<Prompt.ID> = []
    @State private var hasUserMadeEdits: Bool = false

    private enum OpenMenu { case none, promptSelector }
    @State private var openMenu: OpenMenu = .none
    
    @State private var isAIButtonVisible: Bool = true
    @State private var aiButtonOffset: CGSize = .zero
    @State private var aiIsDragging: Bool = false
    @GestureState private var aiGestureDragOffset: CGSize = .zero
    @State private var aiIsPressed: Bool = false
    private let aiButtonPositionKey = "floatingMealPlanAIButtonPosition"
    private let selectedPromptsKey = "MealPlanEditor_SelectedPromptIDs"
    
    // MARK: - Environment & Dependencies
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var effectManager = EffectManager.shared
    @ObservedObject private var aiManager = AIManager.shared
    
    let profile: Profile
    let onDismiss: () -> Void
    @Binding var navBarIsHiden: Bool
    @Binding var globalSearchText: String
    @FocusState.Binding var isSearchFieldFocused: Bool
    
    let planToEdit: MealPlan?
    let planDraft: MealPlanDraft?
    let sourceAIGenerationJobID: UUID?
    
    @State private var planPreviewToLoad: MealPlanPreview?
    
    // MARK: - Form State
    @State private var name: String
    @State private var days: [MealPlanDay]
    @State private var minAgeMonthsTxt: String = "0"
    @State private var calculatedMinAge: Int = 0
    
    // MARK: - Navigation
    @State private var path = NavigationPath()
    private enum NavigationTarget: Hashable {
        case promptEditor
        case editPrompt(Prompt)
    }

    @State private var showAlert = false
    @State private var alertMessage = ""

    @State private var selectedDayID: MealPlanDay.ID? = nil
    @State private var selectedMealID: MealPlanMeal.ID? = nil

    private enum LoadingOperation { case none, saving, generating }
    @State private var loadingOperation: LoadingOperation = .none
    
    @State private var showAIGenerationToast = false
    @State private var toastTimer: Timer? = nil
    @State private var toastProgress: Double = 0.0

    @State private var generationTask: Task<Void, Never>? = nil

    // MARK: - Focus State
    enum FocusableField: Hashable {
        case name, minAge
        case ingredientGrams(id: MealPlanEntry.ID)
    }
    @FocusState private var focusedField: FocusableField?

    @State private var runningGenerationJobID: UUID? = nil
    @State private var promptToDelete: Prompt? = nil
    @State private var isShowingDeletePromptConfirmation = false
    @State private var scrollToExerciseID: TrainingPlanExercise.ID?
    
    private let maxIngredientGrams: Double = 30000.0

    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (loadingOperation != .none)
    }

    private var sortedDays: [MealPlanDay] {
        days.sorted { $0.dayIndex < $1.dayIndex }
    }

    private var currentlySelectedMeal: MealPlanMeal? {
        guard let day = days.first(where: { $0.id == selectedDayID }),
              let meal = day.meals.first(where: { $0.id == selectedMealID }) else {
            return nil
        }
        return meal
    }

    // MARK: - Initializer
    init(
        profile: Profile,
        planToEdit: MealPlan? = nil,
        planDraft: MealPlanDraft? = nil,
        planPreview: MealPlanPreview? = nil,
        sourceAIGenerationJobID: UUID? = nil,
        navBarIsHiden: Binding<Bool>,
        globalSearchText: Binding<String>,
        isSearchFieldFocused: FocusState<Bool>.Binding,
        onDismiss: @escaping () -> Void
    ) {
        self.profile = profile
        self.planToEdit = planToEdit
        self.planDraft = planDraft
        self.onDismiss = onDismiss
        self._navBarIsHiden = navBarIsHiden
        self._globalSearchText = globalSearchText
        self._isSearchFieldFocused = isSearchFieldFocused
        self._planPreviewToLoad = State(initialValue: planPreview)
        self.sourceAIGenerationJobID = sourceAIGenerationJobID

        if let plan = planToEdit {
            _name = State(initialValue: plan.name)
            _days = State(initialValue: plan.days.map { day in
                let newDay = MealPlanDay(dayIndex: day.dayIndex)
                newDay.meals = day.meals.map { meal in
                    let newMeal = MealPlanMeal(mealName: meal.mealName)
                    newMeal.linkedMenuID = meal.linkedMenuID
                    newMeal.entries = meal.entries.map { entry in
                        let newEntry = MealPlanEntry(food: entry.food!, grams: entry.grams, meal: newMeal)
                        return newEntry
                    }
                    return newMeal
                }
                return newDay
            })
            _minAgeMonthsTxt = State(initialValue: plan.minAgeMonths > 0 ? String(plan.minAgeMonths) : "")
            recalculateAndValidateMinAge()
        } else if let draft = planDraft {
            _name = State(initialValue: draft.name)
            _minAgeMonthsTxt = State(initialValue: "")

            let newDay = MealPlanDay(dayIndex: 1)
            var newMeals: [MealPlanMeal] = []
            for meal in draft.meals {
                let newMealPlanMeal = MealPlanMeal(mealName: meal.name)
                let foods = meal.foods(using: GlobalState.modelContext!)
                for (foodItem, grams) in foods {
                    let newEntry = MealPlanEntry(food: foodItem, grams: grams)
                    newEntry.meal = newMealPlanMeal
                    newMealPlanMeal.entries.append(newEntry)
                }
                newMeals.append(newMealPlanMeal)
            }
            newDay.meals = newMeals
            _days = State(initialValue: [newDay])
            recalculateAndValidateMinAge()

        } else {
            _name = State(initialValue: "")
            _days = State(initialValue: [MealPlanDay(dayIndex: 1)])
            _minAgeMonthsTxt = State(initialValue: "")
            recalculateAndValidateMinAge()
        }
    }

    // MARK: - Body
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                   ThemeBackgroundView().ignoresSafeArea()
                   
                   VStack(spacing: 0) {
                       toolbar
                       mainContent
                   }
                   .blur(radius: loadingOperation != .none ? 1.5 : 0)
                   .disabled(loadingOperation != .none)
                   
                   // +++ НАЧАЛО НА ПРОМЯНАТА: FoodSearchPanelView +++
                   if isSearchFieldFocused {
                       let focusBinding = Binding<Bool>(
                           get: { isSearchFieldFocused },
                           set: { isSearchFieldFocused = $0 }
                       )
                       
                       // Изчисляваме кои ID-та да скрием (тези, които вече са добавени в текущото хранене)
                       let excludedIDs: Set<Int> = {
                           if let meal = currentlySelectedMeal {
                               return Set(meal.entries.compactMap { $0.food?.id })
                           }
                           return []
                       }()
                       
                       FoodSearchPanelView(
                           globalSearchText: $globalSearchText,
                           isSearchFieldFocused: focusBinding,
                           profile: profile,
                           // Може да е .foods, .recipes, .menus или nil за всичко
                           searchMode: .mealPlans,
                           showFavoritesFilter: true,
                           showRecipesFilter: true,
                           showMenusFilter: true,
                           headerRightText: currentlySelectedMeal?.mealName,
                           excludedFoodIDs: excludedIDs,
                           onSelectFood: { foodItem in
                               addFoodItem(foodItem)
                           },
                           onDismiss: {
                               dismissKeyboardAndSearch()
                           }
                       )
                       .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                       .zIndex(1)
                   }
                   // +++ КРАЙ НА ПРОМЯНАТА +++
                   
                   if openMenu != .none {
                      bottomSheetPanel
                  }
                   
                   if loadingOperation == .saving {
                       VStack(spacing: 16) {
                           ProgressView()
                               .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                               .scaleEffect(1.5)
                           Text("Saving…")
                               .foregroundStyle(effectManager.currentGlobalAccentColor)
                               .font(.headline)
                       }
                       .padding(30)
                       .glassCardStyle(cornerRadius: 20)
                       .transition(.scale.combined(with: .opacity))
                       .accessibilityLabel("Saving")
                       .zIndex(1000)
                   }
               }
            .overlay {
                if showAIGenerationToast {
                    aiGenerationToast
                }
                GeometryReader { geometry in
                    Group {
                        if !isSearchFieldFocused &&
                            loadingOperation == .none &&
                            !showAlert, openMenu == .none &&
                            GlobalState.aiAvailability != .deviceNotEligible {
                            AIButton(geometry: geometry)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .onAppear {
                   loadAIButtonPosition()
                   loadSelectedPromptIDs()
                   if planPreviewToLoad == nil {
                       Task {
                           await syncStateFromLinkedMenus()
                       }
                   }
                   
                   if selectedDayID == nil {
                       DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                           guard let firstDay = sortedDays.first else {
                               return
                           }
                           selectedDayID = firstDay.id
                           if let firstMealTemplate = profile.meals.sorted(by: { $0.startTime < $1.startTime }).first {
                               let firstMeal = getOrCreateMeal(for: firstMealTemplate.name, in: firstDay)
                               selectedMealID = firstMeal.id
                           }
                       }
                   }
                   recalculateAndValidateMinAge()
               }
            .onReceive(NotificationCenter.default.publisher(for: .aiJobCompletedMealPlan)) { notification in
                       guard !hasUserMadeEdits,
                             let userInfo = notification.userInfo,
                             let completedJobID = userInfo["jobID"] as? UUID else {
                           return
                       }

                       print("▶️ MealPlanEditorView: Received .aiJobCompletedMealPlan for job \(completedJobID).")
                       
                       let descriptor = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.id == completedJobID })
                       if let job = (try? modelContext.fetch(descriptor))?.first, let preview = job.result {
                           Task {
                               await populateFromPreview(preview)
                               await aiManager.deleteJob(job)
                           }
                       }
                   }
                   .onChange(of: name) { _, _ in hasUserMadeEdits = true }
                   .onChange(of: minAgeMonthsTxt) { _, _ in hasUserMadeEdits = true }
                   .task(id: planPreviewToLoad?.id) {
                       if let preview = planPreviewToLoad {
                           await populateFromPreview(preview)
                           planPreviewToLoad = nil
                       }
                   }
                   .onChange(of: aiManager.jobs) { _, newJobs in
                       guard let runningID = runningGenerationJobID,
                             let completedJob = newJobs.first(where: { $0.id == runningID }) else { return }
                       
                       loadingOperation = .none

                       if completedJob.status == .completed {
                           if !hasUserMadeEdits, let preview = completedJob.result {
                               Task {
                                   await populateFromPreview(preview)
                                   await aiManager.deleteJob(completedJob)
                                   runningGenerationJobID = nil
                               }
                           }
                       } else if completedJob.status == .failed {
                           alertMessage = "AI generation failed: \(completedJob.failureReason ?? "Unknown error")"
                           showAlert = true
                           runningGenerationJobID = nil
                           Task { await aiManager.deleteJob(completedJob) }
                       }
                   }
            .onChange(of: selectedPromptIDs) { _, newSelection in
                           saveSelectedPromptIDs(newSelection)
                       }
            .onDisappear { navBarIsHiden = false }
            .toolbar(.hidden, for: .navigationBar)
            .alert("Error", isPresented: $showAlert) { Button("OK", role: .cancel) {} } message: { Text(alertMessage) }
            .onChange(of: focusedField) { _, newValue in if newValue == nil { validateMinAgeOnBlur() } }
            .task(id: planPreviewToLoad?.id) {
                if let preview = planPreviewToLoad {
                    await populateFromPreview(preview)
                    planPreviewToLoad = nil
                }
            }
            .onChange(of: aiManager.jobs) { _, newJobs in
                guard let runningID = runningGenerationJobID,
                      let completedJob = newJobs.first(where: { $0.id == runningID }) else { return }
                
                if completedJob.status == .completed {
                    if let preview = completedJob.result {
                        Task {
                            await populateFromPreview(preview)
                            runningGenerationJobID = nil
                            await aiManager.deleteJob(completedJob)
                        }
                    }
                } else if completedJob.status == .failed {
                    alertMessage = "AI generation failed: \(completedJob.failureReason ?? "Unknown error")"
                    showAlert = true
                    runningGenerationJobID = nil
                    Task { await aiManager.deleteJob(completedJob) }
                }
            }
            .navigationDestination(for: NavigationTarget.self) { target in
                switch target {
                case .promptEditor:
                    PromptEditorView(promptType: .mealPlan) { newPrompt in
                        path.removeLast()
                        if let newPrompt = newPrompt {
                            selectedPromptIDs.insert(newPrompt.id)
                            saveSelectedPromptIDs(selectedPromptIDs)
                        }
                    }
                    
                case .editPrompt(let prompt):
                       PromptEditorView(promptType: .mealPlan, promptToEdit: prompt) { editedPrompt in
                           if let editedPrompt = editedPrompt {
                               if !selectedPromptIDs.contains(editedPrompt.id) {
                                   selectedPromptIDs.insert(editedPrompt.id)
                                   saveSelectedPromptIDs(selectedPromptIDs)

                               }
                           }
                           
                           path.removeLast()
                       }
                   }
            }
            .confirmationDialog(
                "Delete Prompt?",
                isPresented: $isShowingDeletePromptConfirmation,
                presenting: promptToDelete
            ) { prompt in
                Button("Delete", role: .destructive) {
                    modelContext.delete(prompt)
                    selectedPromptIDs.remove(prompt.id)
                    saveSelectedPromptIDs(selectedPromptIDs)
                }
                Button("Cancel", role: .cancel) {
                    promptToDelete = nil
                }
            } message: { _ in
                Text("Are you sure you want to delete this prompt? This action cannot be undone.")
            }
        }
    }

    private func saveSelectedPromptIDs(_ ids: Set<UUID>) {
        let idStrings = ids.map { $0.uuidString }
        UserDefaults.standard.set(idStrings, forKey: selectedPromptsKey)
    }

    private func loadSelectedPromptIDs() {
        guard let idStrings = UserDefaults.standard.stringArray(forKey: selectedPromptsKey) else { return }
        let ids = idStrings.compactMap { UUID(uuidString: $0) }
        self.selectedPromptIDs = Set(ids)
    }

    private var toolbar: some View {
        HStack {
            Button("Cancel", action: onDismiss)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)

            Spacer()
            Text(planToEdit == nil && sourceAIGenerationJobID == nil ? "New Meal Plan" : "Edit Meal Plan").font(.headline)
            Spacer()

            Button("Save", action: savePlan)
                .disabled(isSaveDisabled)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
                .foregroundStyle(isSaveDisabled ? effectManager.currentGlobalAccentColor.opacity(0.4) : effectManager.currentGlobalAccentColor)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding([.horizontal, .top])
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

    private var mainContent: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    nameCard
                    
                    ForEach(Array(sortedDays.enumerated()), id: \.element.id) { index, day in
                        daySection(for: day, dayIndex: index + 1)
                    }
                    
                    if days.count < 7 {
                        Button(action: addDay) {
                            Label("Add Day", systemImage: "plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .padding()
                        .glassCardStyle(cornerRadius: 20)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                }
                .padding()
                Color.clear.frame(height: 150)
            }
            .onChange(of: focusedField) { oldValue, newValue in
                if let oldID = oldValue, newValue != oldID {
                    switch oldID {
                    case .ingredientGrams(let entryID):
                        formatIngredientText(for: entryID)
                    case .minAge:
                        validateMinAgeOnBlur()
                    default:
                        break
                    }
                }

                guard let focus = newValue else { return }

                let idToScroll: AnyHashable
                switch focus {
                case .name, .minAge:
                    idToScroll = focus
                case .ingredientGrams(let entryID):
                    idToScroll = entryID
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeInOut) {
                        proxy.scrollTo(idToScroll, anchor: .top)
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
        }
    }

    private var nameCard: some View {
        VStack(spacing: 12) {
            StyledLabeledPicker(label: "Plan Name", isRequired: true) {
                TextField("", text: $name, prompt: Text("e.g., High-Protein Week").foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6)))
                    .focused($focusedField, equals: .name)
            }
            .id(FocusableField.name)
            
            StyledLabeledPicker(label: "Minimum Age (months)") {
                ConfigurableTextField(
                    title: "0",
                    value: $minAgeMonthsTxt,
                    type: .integer,
                    placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                    textAlignment: .leading,
                    focused: $focusedField,
                    fieldIdentifier: .minAge
                )
            }
            .id(FocusableField.minAge)
            
            let mealPlanPrompts = allPrompts.filter { $0.type == .mealPlan }

            if !mealPlanPrompts.isEmpty {
                promptsSection
            }
           
            Button {
                   path.append(NavigationTarget.promptEditor)
               } label: {
                   Label("New Prompt", systemImage: "plus.bubble")
                       .font(.subheadline.weight(.semibold))
                       .frame(maxWidth: .infinity, alignment: .center)
               }
               .padding(.vertical, 10)
               .glassCardStyle(cornerRadius: 20)
               .foregroundColor(effectManager.currentGlobalAccentColor)
        }
        .padding()
        .glassCardStyle(cornerRadius: 20)
    }

    private func daySection(for day: MealPlanDay, dayIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Day \(dayIndex)")
                    .font(.headline)
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                Spacer()

                if days.count > 1 {
                    Button(action: { deleteDay(day) }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle( effectManager.currentGlobalAccentColor, effectManager.currentGlobalAccentColor.opacity(0.1))
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(profile.meals.sorted(by: { $0.startTime < $1.startTime })) { mealTemplate in
                        let meal = getOrCreateMeal(for: mealTemplate.name, in: day)
                        mealTabButton(for: meal, in: day)
                    }
                }
                .padding(.vertical, 4)
            }

            ForEach(day.meals) { meal in
                if meal.id == selectedMealID {
                    workoutContent(for: meal, in: day)
                }
            }
        }
        .animation(.default, value: selectedMealID)
        .padding()
        .glassCardStyle(cornerRadius: 20)
    }

    private static let palette: [Color] = [
        .orange, .pink, .green, .indigo, .purple, .blue, .red, Color(hex: "#00ffff")
    ]

    private var colorFor: [MealPlanMeal.ID: Color] {
        let sortedTemplates = profile.meals.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let n = Self.palette.count

        let colorByName = Dictionary(uniqueKeysWithValues:
            sortedTemplates.enumerated().map { idx, mealTemplate in
                (mealTemplate.name, Self.palette[idx % n])
            })

        var finalMap: [MealPlanMeal.ID: Color] = [:]
        for day in days {
            for meal in day.meals {
                finalMap[meal.id] = colorByName[meal.mealName] ?? .gray
            }
        }
        return finalMap
    }
    
    @ViewBuilder
    private func mealTabButton(for meal: MealPlanMeal, in day: MealPlanDay) -> some View {
        let isSelected = selectedMealID == meal.id && selectedDayID == day.id
        let baseColor = colorFor[meal.id] ?? effectManager.currentGlobalAccentColor

        Button {
            withAnimation {
                selectedDayID = day.id
                selectedMealID = meal.id
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Text(meal.mealName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(isSelected ? baseColor.opacity(0.8) : baseColor.opacity(0.3))
                        }
                    )
                    .glassCardStyle(cornerRadius: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(baseColor, lineWidth: isSelected ? 2 : 0)
                    )
                    .foregroundColor(effectManager.currentGlobalAccentColor)

                if !meal.entries.isEmpty {
                    ZStack {
                        Circle()
                            .fill(baseColor)
                        Text("\(meal.entries.count)")
                            .font(.system(size: 10, weight: .bold))
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    .frame(width: 16, height: 16)
                    .offset(x: 6, y: -6)
                } else {
                    ZStack {
                        Circle()
                            .fill(baseColor)
                        Text("\(0)")
                            .font(.system(size: 10, weight: .bold))
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    .frame(width: 16, height: 16)
                    .offset(x: 6, y: -6)
                }
            }
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func workoutContent(for meal: MealPlanMeal, in day: MealPlanDay) -> some View {
        VStack {
            if !meal.entries.isEmpty {
                if let dayIndex = days.firstIndex(where: { $0.id == day.id }),
                   let mealIndex = days[dayIndex].meals.firstIndex(where: { $0.id == meal.id }) {

                    ForEach($days[dayIndex].meals[mealIndex].entries) { $entry in
                        MealPlanEntryRowView(
                            entry: $entry,
                            focusedField: $focusedField,
                            focusCase: .ingredientGrams(id: entry.id),
                            onDelete: {
                                removeEntry(entry, from: meal)
                            }
                        )
                        .id(entry.id)
                    }
                }
            } else {
                Text("Tap search to add")
                    .font(.caption)
                    .italic()
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
            }
        }
        .contentShape(Rectangle())
    }
    
    private func addFoodItem(_ food: FoodItem) {
        guard let meal = currentlySelectedMeal else { return }
        if food.isMenu, let menuIngredients = food.ingredients, !menuIngredients.isEmpty {
            for link in menuIngredients {
                guard let ingredientFood = link.food else { continue }
                if let existingEntry = meal.entry(for: ingredientFood) {
                    existingEntry.grams += link.grams
                } else {
                    _ = meal.ensureEntry(for: ingredientFood, defaultGrams: link.grams)
                }
            }
        } else {
            let defaultGrams = GlobalState.measurementSystem == "Imperial" ? UnitConversion.ozToG(4.0) : 100.0
            _ = meal.ensureEntry(for: food, defaultGrams: defaultGrams)
        }
        hasUserMadeEdits = true
        dismissKeyboardAndSearch()
        recalculateAndValidateMinAge()
    }

    private func removeEntry(_ entry: MealPlanEntry, from meal: MealPlanMeal) {
        withAnimation {
            if let dayIndex = days.firstIndex(where: { $0.id == meal.day?.id }),
               let mealIndex = days[dayIndex].meals.firstIndex(where: { $0.id == meal.id }) {
                days[dayIndex].meals[mealIndex].entries.removeAll { $0.id == entry.id }
            }
        }
        hasUserMadeEdits = true
        recalculateAndValidateMinAge()
    }

    private func dismissKeyboardAndSearch() {
        isSearchFieldFocused = false
        globalSearchText = ""
    }

    private func getOrCreateMeal(for mealName: String, in day: MealPlanDay) -> MealPlanMeal {
        if let existingMeal = day.meals.first(where: { $0.mealName == mealName }) {
            return existingMeal
        } else {
            let newMeal = MealPlanMeal(mealName: mealName)
            newMeal.day = day
            if let dayIndex = days.firstIndex(where: { $0.id == day.id }) {
                days[dayIndex].meals.append(newMeal)
            }
            return newMeal
        }
    }

    private func savePlan() {
        Task { @MainActor in
            loadingOperation = .saving
            await Task.yield()
            defer { loadingOperation = .none }

            let planToSave: MealPlan

            if let existingPlan = planToEdit {
                planToSave = existingPlan
            } else {
                planToSave = MealPlan(name: name, profile: profile)
                modelContext.insert(planToSave)
            }

            planToSave.name = name
            planToSave.minAgeMonths = Int(minAgeMonthsTxt) ?? 0

            await createOrUpdateMenus(for: planToSave)
            syncDays(of: planToSave, from: self.days)

            do {
                try modelContext.save()

                if let jobID = sourceAIGenerationJobID {
                    let predicate = #Predicate<AIGenerationJob> { $0.id == jobID }
                    let descriptor = FetchDescriptor(predicate: predicate)
                    if let jobToDelete = try? modelContext.fetch(descriptor).first {
                        await aiManager.deleteJob(jobToDelete)
                    }
                }

                onDismiss()
            } catch {
                alertMessage = "Failed to save the plan. Error: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    private func syncDays(of plan: MealPlan, from stateDays: [MealPlanDay]) {
        let stateDaysByIndex = Dictionary(grouping: stateDays, by: { $0.dayIndex }).compactMapValues { $0.first }

        for day in plan.days where stateDaysByIndex[day.dayIndex] == nil {
            modelContext.delete(day)
        }

        for (index, stateDay) in stateDaysByIndex {
            if let persistedDay = plan.days.first(where: { $0.dayIndex == index }) {
                syncMeals(of: persistedDay, from: stateDay)
            } else {
                let newDay = MealPlanDay(dayIndex: index)
                newDay.plan = plan
                modelContext.insert(newDay)
                syncMeals(of: newDay, from: stateDay)
            }
        }
    }

    private func syncMeals(of persistedDay: MealPlanDay, from stateDay: MealPlanDay) {
        let stateMealsByName = Dictionary(grouping: stateDay.meals, by: { $0.mealName }).compactMapValues { $0.first }

        for meal in persistedDay.meals where stateMealsByName[meal.mealName] == nil {
            modelContext.delete(meal)
        }

        for (name, stateMeal) in stateMealsByName {
            let persistedMeal = getOrCreateMeal(for: name, in: persistedDay)
            persistedMeal.entries.forEach { modelContext.delete($0) }
            persistedMeal.entries = stateMeal.entries.map { entry in
                let newEntry = MealPlanEntry(food: entry.food!, grams: entry.grams, meal: persistedMeal)
                return newEntry
            }
            persistedMeal.linkedMenuID = stateMeal.linkedMenuID
        }
    }

    private func createOrUpdateMenus(for plan: MealPlan) async {
        for (dayIndex, day) in sortedDays.enumerated() {
            for meal in day.meals {
                guard !meal.entries.isEmpty else { continue }
                let menuName = "\(plan.name) - Day \(dayIndex + 1) - \(meal.mealName)"
                let menuToUpdate: FoodItem
                if let existingMenuID = meal.linkedMenuID, let foundMenu = try? modelContext.fetch(FetchDescriptor<FoodItem>(predicate: #Predicate { $0.id == existingMenuID })).first {
                    menuToUpdate = foundMenu
                } else {
                    menuToUpdate = FoodItem(id: nextFoodId(), name: menuName, isMenu: true, isUserAdded: true)
                    modelContext.insert(menuToUpdate)
                    meal.linkedMenuID = menuToUpdate.id
                }
                menuToUpdate.name = menuName
                menuToUpdate.ingredients?.forEach { modelContext.delete($0) }
                menuToUpdate.ingredients = meal.entries.map { entry in
                    IngredientLink(food: entry.food!, grams: entry.grams, owner: menuToUpdate)
                }
                
                SearchIndexStore.shared.updateItem(menuToUpdate, context: modelContext)
            }
        }
    }

    private func nextFoodId() -> Int {
        var desc = FetchDescriptor<FoodItem>()
        desc.sortBy = [SortDescriptor(\.id, order: .reverse)]
        desc.fetchLimit = 1
        let maxId = ((try? modelContext.fetch(desc))?.first?.id) ?? 0
        return maxId + 1
    }

    private var allFoodsInPlan: [FoodItem] {
        days.flatMap { $0.meals }.flatMap { $0.entries }.compactMap { $0.food }
    }

    private func recalculateAndValidateMinAge() {
        let requiredMinAge = allFoodsInPlan.map { $0.minAgeMonths }.max() ?? 0
        self.calculatedMinAge = requiredMinAge
        let currentUserAge = Int(minAgeMonthsTxt) ?? 0
        if currentUserAge < requiredMinAge || (minAgeMonthsTxt.isEmpty && requiredMinAge > 0) {
            minAgeMonthsTxt = String(requiredMinAge)
        }
    }

    private func validateMinAgeOnBlur() {
        let currentUserAge = Int(minAgeMonthsTxt) ?? 0
        if currentUserAge < calculatedMinAge {
            minAgeMonthsTxt = String(calculatedMinAge)
        }
    }

    private func addDay() {
        withAnimation {
            let nextIndex = (days.map { $0.dayIndex }.max() ?? 0) + 1
            let newDay = MealPlanDay(dayIndex: nextIndex)
            for mealTemplate in profile.meals.sorted(by: { $0.startTime < $1.startTime }) {
                let newMeal = MealPlanMeal(mealName: mealTemplate.name)
                newMeal.day = newDay
                newDay.meals.append(newMeal)
            }
            days.append(newDay)
        }
        hasUserMadeEdits = true
    }

    private func deleteDay(_ dayToDelete: MealPlanDay) {
        withAnimation {
            days.removeAll { $0.id == dayToDelete.id }
            for (index, day) in sortedDays.enumerated() {
                day.dayIndex = index + 1
            }
            if selectedDayID == dayToDelete.id {
                if let firstDay = sortedDays.first {
                    selectedDayID = firstDay.id
                    if let firstMealTemplate = profile.meals.sorted(by: { $0.startTime < $1.startTime }).first {
                        let firstMeal = getOrCreateMeal(for: firstMealTemplate.name, in: firstDay)
                        selectedMealID = firstMeal.id
                    }
                } else {
                    selectedDayID = nil
                    selectedMealID = nil
                }
            }
        }
        hasUserMadeEdits = true
    }

    private func syncStateFromLinkedMenus() async {
        let context = self.modelContext
        for day in days {
            for meal in day.meals {
                guard let menuID = meal.linkedMenuID else { continue }
                let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.id == menuID })
                if let menuItem = (try? context.fetch(descriptor))?.first {
                    
                    var newEntries: [MealPlanEntry] = []
                    for ingredientLink in menuItem.ingredients ?? [] {
                        if let food = ingredientLink.food {
                            let newEntry = MealPlanEntry(food: food, grams: ingredientLink.grams, meal: meal)
                            newEntries.append(newEntry)
                        }
                    }
                    meal.entries = newEntries
                }
            }
        }
    }
    
    private func cancelGeneration() {
        generationTask?.cancel()
        loadingOperation = .none
    }
    
    private func formatIngredientText(for entryID: MealPlanEntry.ID) {}

    
    private func handleAITap() {
        
        guard ensureAIAvailableOrShowMessage() else { return }

        let mealsToGenerate = days.reduce(into: [Int: [String]]()) { result, day in
            let emptyMealNames = day.meals.filter { $0.entries.isEmpty }.map { $0.mealName }
            if !emptyMealNames.isEmpty {
                result[day.dayIndex] = emptyMealNames
            }
        }

        guard !mealsToGenerate.isEmpty else {
            alertMessage = "All meals for all days already have items. Clear some meals if you want to generate new ones."
            showAlert = true
            return
        }

        let existingMeals = days.reduce(into: [Int: [MealPlanPreviewMeal]]()) { result, day in
            let populatedMeals = day.meals.filter { !$0.entries.isEmpty }

            if !populatedMeals.isEmpty {
                result[day.dayIndex] = populatedMeals.map { meal in
                    let items = meal.entries.compactMap { entry -> MealPlanPreviewItem? in
                        guard let food = entry.food else { return nil }
                        return MealPlanPreviewItem(
                            name: food.name,
                            grams: entry.grams,
                            kcal: food.calories(for: entry.grams)
                        )
                    }
                    return MealPlanPreviewMeal(
                        name: meal.mealName,
                        descriptiveTitle: meal.descriptiveAIName,
                        items: items, startTime: nil
                    )
                }
            }
        }

        let selectedPrompts = allPrompts.filter { selectedPromptIDs.contains($0.id) }.map { $0.text }
        
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

        if let newJob = aiManager.startPlanFill(
            for: profile,
            daysAndMeals: mealsToGenerate,
            existingMeals: existingMeals,
            selectedPrompts: selectedPrompts.isEmpty ? nil : selectedPrompts,
            jobType: .mealPlan
        ) {
            self.runningGenerationJobID = newJob.id
        } else {
            alertMessage = "Could not start AI generation job."
            showAlert = true
            toastTimer?.invalidate()
            toastTimer = nil
            withAnimation {
                showAIGenerationToast = false
            }
        }
        
        hasUserMadeEdits = false
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

    private func aiBottomPadding(for geometry: GeometryProxy) -> CGFloat {
        let size = geometry.size
        guard size.width > 0 else { return 75 }
        let aspect = size.height / size.width
        return aspect > 1.9 ? 75 : 95
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
                    let safe = geometry.safeAreaInsets

                    let minY = -viewSize.height + buttonRadius + safe.top
                    let maxY = -25 + safe.bottom
                    newOffset.height = min(maxY, max(minY, newOffset.height))

                    self.aiButtonOffset = newOffset
                    self.saveAIButtonPosition()
                } else {
                    self.handleAITap()
                }
                self.aiIsDragging = false
            }
    }


    @ViewBuilder
    private func AIButton(geometry: GeometryProxy) -> some View {
        let currentOffset = CGSize(
            width: aiButtonOffset.width + aiGestureDragOffset.width,
            height: aiButtonOffset.height + aiGestureDragOffset.height
        )
        let scale = aiIsDragging ? 1.15 : (aiIsPressed ? 0.9 : 1.0)

        Image(systemName: "sparkles")
            .font(.title2)
            .foregroundColor(effectManager.currentGlobalAccentColor)
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

    private func populateFromPreview(_ preview: MealPlanPreview) async {
        self.name = preview.prompt
        self.minAgeMonthsTxt = String(preview.minAgeMonths)
        
        var newDays: [MealPlanDay] = []
        for previewDay in preview.days {
            let newDay = MealPlanDay(dayIndex: previewDay.dayIndex)
            var newMeals: [MealPlanMeal] = []
            for previewMeal in previewDay.meals {
                let newMealPlanMeal = MealPlanMeal(mealName: previewMeal.name)
                newMealPlanMeal.descriptiveAIName = previewMeal.descriptiveTitle
                newMealPlanMeal.startTime = previewMeal.startTime

                for item in previewMeal.items {
                    let itemName = item.name
                    let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.name == itemName })
                    if let food = (try? self.modelContext.fetch(descriptor))?.first {
                        let newEntry = MealPlanEntry(food: food, grams: item.grams, meal: newMealPlanMeal)
                        newMealPlanMeal.entries.append(newEntry)
                    }
                }
                newMeals.append(newMealPlanMeal)
            }
            newDay.meals = newMeals
            newDays.append(newDay)
        }
        self.days = newDays

        if let firstDay = self.days.sorted(by: { $0.dayIndex < $1.dayIndex }).first {
            self.selectedDayID = firstDay.id
            
            let sortedMealTemplates = profile.meals.sorted { $0.startTime < $1.startTime }
            if let firstMealTemplate = sortedMealTemplates.first,
               let firstMealInDay = firstDay.meals.first(where: { $0.mealName == firstMealTemplate.name }) {
                self.selectedMealID = firstMealInDay.id
            } else if let firstMealInDay = firstDay.meals.first {
                self.selectedMealID = firstMealInDay.id
            }
        } else {
            self.selectedDayID = nil
            self.selectedMealID = nil
        }

        recalculateAndValidateMinAge()
        self.hasUserMadeEdits = false
    }
    
    @ViewBuilder
    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompts")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            
            let mealPlanPrompts = allPrompts.filter { $0.type == .mealPlan }
            
            MultiSelectButton(
                selection: $selectedPromptIDs,
                items: mealPlanPrompts,
                label: { $0.text },
                prompt: "Select a prompt...",
                isExpanded: openMenu == .promptSelector
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    openMenu = .promptSelector
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .font(.system(size: 16))
            .glassCardStyle(cornerRadius: 20)
        }
    }

    @ViewBuilder
    private var bottomSheetPanel: some View {
        ZStack(alignment: .bottom) {
            if effectManager.isLightRowTextColor {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { withAnimation { openMenu = .none } }
            } else {
                Color.white.opacity(0.4).ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { withAnimation { openMenu = .none } }
            }
            
            VStack(spacing: 8) {
                HStack {
                    Text("Select Prompts")
                        .font(.headline)
                        .foregroundColor(effectManager.currentGlobalAccentColor)
                    
                    Spacer()
                    
                    Button("Done") {
                        withAnimation {
                            openMenu = .none
                        }
                    }
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCardStyle(cornerRadius: 20)
                }
                .padding(.horizontal)
                .frame(height: 35)
                    
                dropDownLayer
                
            }
            .padding(.top)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme,effectManager.isLightRowTextColor ? .dark : .light)
            }
            .cornerRadius(20, corners: [.topLeft, .topRight])
            .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .zIndex(1)
        .transition(.move(edge: .bottom).animation(.easeInOut(duration: 0.3)))
    }

    @ViewBuilder
    private var dropDownLayer: some View {
        Group {
            switch openMenu {
            case .promptSelector:
                let mealPlanPrompts = allPrompts.filter { $0.type == .mealPlan }
                DropdownMenu(
                    selection: $selectedPromptIDs,
                    items: mealPlanPrompts,
                    label: { $0.text },
                    selectAllBtn: false,
                    isEditable: true,
                    isDeletable: true,
                    onEdit: { prompt in
                        openMenu = .none
                        path.append(NavigationTarget.editPrompt(prompt))
                    },
                    onDelete: { prompt in
                        if #available(iOS 16.0, *) {
                            withAnimation {
                                modelContext.delete(prompt)
                                selectedPromptIDs.remove(prompt.id)
                                saveSelectedPromptIDs(selectedPromptIDs)
                            }
                        } else {
                            promptToDelete = prompt
                            isShowingDeletePromptConfirmation = true
                        }
                    }
                )
            case .none:
                EmptyView()
            }
        }
    }
    
    private func ensureAIAvailableOrShowMessage() -> Bool {
        switch GlobalState.aiAvailability {
        case .available:
            return true
        case .deviceNotEligible:
            alertMessage = "This device doesn’t support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            alertMessage = "Apple Intelligence is turned off. Enable it in Settings to use AI."
        case .modelNotReady:
            alertMessage = "The model is downloading or preparing. Please try again shortly."
        case .unavailableUnsupportedOS:
            alertMessage = "Apple Intelligence requires iOS 26 or newer."
        case .unavailableOther:
            alertMessage = "Apple Intelligence is currently unavailable for an unknown reason."
        }
        showAlert = true
        return false
    }

}
