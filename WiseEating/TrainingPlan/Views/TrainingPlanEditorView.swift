import SwiftUI
import SwiftData

@MainActor
struct TrainingPlanEditorView: View {
    
    @ObservedObject private var aiManager = AIManager.shared
    @State private var hasUserMadeEdits: Bool = false
    @State private var runningGenerationJobID: UUID? = nil
    @State private var showAIGenerationToast = false
    @State private var toastTimer: Timer? = nil
    @State private var toastProgress: Double = 0.0
    
    @State private var isAIButtonVisible: Bool = true
    @State private var aiButtonOffset: CGSize = .zero
    @State private var aiIsDragging: Bool = false
    @GestureState private var aiGestureDragOffset: CGSize = .zero
    @State private var aiIsPressed: Bool = false
    private let aiButtonPositionKey = "floatingTrainingAIButtonPosition"
    
    // MARK: - Environment & Dependencies
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var effectManager = EffectManager.shared
    
    // MARK: - Input
    let profile: Profile
    let onDismiss: (TrainingPlan?) -> Void
    @Binding var globalSearchText: String
    @FocusState.Binding var isSearchFieldFocused: Bool
    
    // MARK: - Plan State
    let planToEdit: TrainingPlan?
    let planDraft: TrainingPlanDraft?
    
    @State private var name: String
    @State private var days: [TrainingPlanDay]
    // +++ НОВО (1/8): Добавяме състояния за минимална възраст +++
    @State private var minAgeMonthsTxt: String
    @State private var calculatedMinAge: Int = 0
    
    // MARK: - UI State
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isSaving = false
    @State private var selectedDayID: TrainingPlanDay.ID? = nil
    @State private var selectedWorkoutID: TrainingPlanWorkout.ID? = nil
    @State private var scrollToExerciseID: TrainingPlanExercise.ID? = nil
    
    // MARK: - Search State
    @StateObject private var searchVM = ExerciseSearchVM()
    @State private var selectedMuscleGroup: MuscleGroup? = nil
    
    // MARK: - Focus State
    enum FocusableField: Hashable {
        // +++ НОВО (2/8): Добавяме .minAge към FocusableField +++
        case name, minAge
        case exerciseDuration(id: TrainingPlanExercise.ID)
    }
    @FocusState private var focusedField: FocusableField?
    
    // MARK: - Prompt State & Navigation (+++ НАЧАЛО НА ПРОМЯНАТА +++)
    @Query(sort: \Prompt.creationDate, order: .reverse) private var allPrompts: [Prompt]
    @State private var selectedPromptIDs: Set<Prompt.ID> = []
    @State private var path = NavigationPath()
    private enum NavigationTarget: Hashable {
        case promptEditor
        case editPrompt(Prompt)
    }
    private enum OpenMenu { case none, promptSelector }
    @State private var openMenu: OpenMenu = .none
    @State private var promptToDelete: Prompt? = nil
    @State private var isShowingDeletePromptConfirmation = false
    private let selectedPromptsKey = "TrainingPlanEditorView_SelectedPrompts"
    // (+++ КРАЙ НА ПРОМЯНАТА +++)
    
    init(
          profile: Profile,
          planToEdit: TrainingPlan? = nil,
          planDraft: TrainingPlanDraft? = nil,
          globalSearchText: Binding<String>,
          isSearchFieldFocused: FocusState<Bool>.Binding,
          onDismiss: @escaping (TrainingPlan?) -> Void
    ) {
        self.profile = profile
        self.planToEdit = planToEdit
        self.planDraft = planDraft
        self.onDismiss = onDismiss
        self._globalSearchText = globalSearchText
        self._isSearchFieldFocused = isSearchFieldFocused
        
        if let plan = planToEdit {
            _name = State(initialValue: plan.name)
            _days = State(initialValue: plan.days.map { day in
                let newDay = TrainingPlanDay(dayIndex: day.dayIndex, isRestDay: day.isRestDay)
                newDay.id = day.id
                
                newDay.workouts = day.workouts.map { workout in
                    let newWorkout = TrainingPlanWorkout(workoutName: workout.workoutName)
                    newWorkout.linkedWorkoutID = workout.linkedWorkoutID
                    
                    // ВАЖНО: взимаме само упражненията, които все още имат exercise
                    let validExercises = workout.exercises.compactMap { link -> TrainingPlanExercise? in
                        guard let ex = link.exercise else {
                            // тук имало е изтрит ExerciseItem → пропускаме
                            return nil
                        }
                        return TrainingPlanExercise(
                            exercise: ex,
                            durationMinutes: link.durationMinutes,
                            workout: newWorkout
                        )
                    }
                    newWorkout.exercises = validExercises
                    return newWorkout
                }
                return newDay
            })
            
            _minAgeMonthsTxt = State(initialValue: plan.minAgeMonths > 0 ? String(plan.minAgeMonths) : "")
        } else if let draft = planDraft {
            // --- НАЧАЛО НА ФИНАЛНАТА КОРЕКЦИЯ ---
            _name = State(initialValue: draft.name)
            _minAgeMonthsTxt = State(initialValue: "") // Започваме с празно, onAppear ще го изчисли
            
            var tempDays: [TrainingPlanDay] = []
            let context = GlobalState.modelContext!
            
            // 1. Създаваме карта (dictionary) на дните от черновата за бърз достъп
            let draftDaysMap = Dictionary(grouping: draft.days, by: { $0.dayIndex }).compactMapValues { $0.first }
            
            // 2. Намираме максималния ден, който трябва да съществува в плана
            let maxDayIndex = draft.days.map { $0.dayIndex }.max() ?? 1
            
            // 3. Итерираме от 1 до максималния ден, за да създадем пълна последователност
            for index in 1...maxDayIndex {
                // 4. Проверяваме дали имаме генериран ден за този индекс
                if let dayDraft = draftDaysMap[index] {
                    // Ако да, създаваме ден с тренировки
                    let newDay = TrainingPlanDay(dayIndex: index, isRestDay: false)
                    var newWorkouts: [TrainingPlanWorkout] = []
                    for training in dayDraft.trainings {
                        let newWorkout = TrainingPlanWorkout(workoutName: training.name)
                        let exercises = training.exercises(using: context)
                        for (item, duration) in exercises {
                            newWorkout.exercises.append(TrainingPlanExercise(exercise: item, durationMinutes: duration, workout: newWorkout))
                        }
                        newWorkout.day = newDay
                        newWorkouts.append(newWorkout)
                    }
                    newDay.workouts = newWorkouts
                    tempDays.append(newDay)
                } else {
                    // Ако не, създаваме ден за почивка (isRestDay = true)
                    let restDay = TrainingPlanDay(dayIndex: index, isRestDay: true)
                    tempDays.append(restDay)
                }
            }
            
            _days = State(initialValue: tempDays)
            // --- КРАЙ НА ФИНАЛНАТА КОРЕКЦИЯ ---
        } else {
            _name = State(initialValue: "")
            _days = State(initialValue: [TrainingPlanDay(dayIndex: 1)])
            _minAgeMonthsTxt = State(initialValue: "")
        }
    }
    
    // MARK: - Computed Properties
    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving
    }
    
    private var displayedSearchResults: [ExerciseItem] {
        searchVM.items
    }
    
    private var sortedDays: [TrainingPlanDay] {
        days.sorted { $0.dayIndex < $1.dayIndex }
    }
    
    private var currentlySelectedWorkout: TrainingPlanWorkout? {
        guard let day = days.first(where: { $0.id == selectedDayID }),
              let workout = day.workouts.first(where: { $0.id == selectedWorkoutID }) else {
            return nil
        }
        return workout
    }
    
    private var allMuscleGroups: [MuscleGroup] {
        MuscleGroup.allCases.sorted { $0.rawValue < $1.rawValue }
    }
    
    // +++ НОВО (4/8): Изчисляемо свойство за всички упражнения в плана +++
    private var allExercisesInPlan: [ExerciseItem] {
        days.flatMap { $0.workouts }.flatMap { $0.exercises }.compactMap { $0.exercise }
    }
    
    // MARK: - Body
    var body: some View {
        // +++ НАЧАЛО НА ПРОМЯНАТА: Обвиваме в NavigationStack +++
        NavigationStack(path: $path) {
            ZStack {
                ThemeBackgroundView().ignoresSafeArea()
                
                VStack(spacing: 0) {
                    toolbar
                    mainContent
                }
                .blur(radius: isSaving ? 1.5 : 0)
                .disabled(isSaving)
                
                if isSearchFieldFocused {
                    fullScreenSearchResultsView
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                        .zIndex(1)
                }
                
                if isSaving {
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
                    .zIndex(1000)
                }
            }
            .task {
                if let draft = planDraft {
                    merge(draft: draft)
                }
                onAppearSetup()
                await syncStateFromLinkedWorkouts()
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if showAIGenerationToast { aiGenerationToast }
                GeometryReader { geometry in
                    Group {
                        if !isSearchFieldFocused &&
                            !isSaving &&
                            !showAlert &&
                            openMenu == .none &&
                            GlobalState.aiAvailability != .deviceNotEligible { // ⬅️ ново
                            AIButton(geometry: geometry)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .overlay {
                if openMenu != .none {
                    bottomSheetPanel
                }
            }
            .onAppear(perform: loadAIButtonPosition)
            .onReceive(NotificationCenter.default.publisher(for: .aiTrainingPlanJobCompleted)) { notification in
                guard !hasUserMadeEdits,
                      let userInfo = notification.userInfo,
                      let completedJobID = userInfo["jobID"] as? UUID,
                      completedJobID == self.runningGenerationJobID else {
                    return
                }
                
                print("▶️ TrainingPlanEditorView: Received .aiTrainingPlanJobCompleted for job \(completedJobID). Populating data.")
                
                Task {
                    await populateFromCompletedJob(jobID: completedJobID)
                }
            }
            .onChange(of: name) { _, _ in hasUserMadeEdits = true }
            .onChange(of: days) { _, _ in hasUserMadeEdits = true }
            .onAppear(perform: loadSelectedPromptIDs) // Зареждаме избраните промптове
            .alert("Error", isPresented: $showAlert) { Button("OK", role: .cancel) {} } message: { Text(alertMessage) }
            .onChange(of: globalSearchText) { _, newText in searchVM.query = newText }
            .onChange(of: selectedMuscleGroup) { _, newGroup in searchVM.muscleGroupFilter = newGroup }
            .onChange(of: isSearchFieldFocused) { _, isFocused in if isFocused { updateSearchExclusions() } }
            .onChange(of: selectedPromptIDs, perform: saveSelectedPromptIDs) // Запазваме при промяна
            .navigationDestination(for: NavigationTarget.self) { target in
                switch target {
                case .promptEditor:
                    PromptEditorView(promptType: .trainingPlan) { newPrompt in
                        path.removeLast()
                        if let newPrompt = newPrompt {
                            selectedPromptIDs.insert(newPrompt.id)
                        }
                    }
                    
                case .editPrompt(let prompt):
                    PromptEditorView(promptType: .trainingPlan, promptToEdit: prompt) { editedPrompt in
                        if let editedPrompt = editedPrompt, !selectedPromptIDs.contains(editedPrompt.id) {
                            selectedPromptIDs.insert(editedPrompt.id)
                        }
                        path.removeLast()
                    }
                }
            }
            .confirmationDialog(
                "Delete Prompt?", isPresented: $isShowingDeletePromptConfirmation, presenting: promptToDelete
            ) { prompt in
                Button("Delete", role: .destructive) {
                    modelContext.delete(prompt)
                    selectedPromptIDs.remove(prompt.id)
                }
                Button("Cancel", role: .cancel) {
                    promptToDelete = nil
                }
            } message: { _ in Text("Are you sure you want to delete this prompt? This action cannot be undone.") }
            // (+++ КРАЙ НА ПРОМЯНАТА +++)
        }
    }
    
    private var toolbar: some View {
        HStack {
            Button("Cancel", action: { onDismiss(nil) })
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
            
            Spacer()
            Text(planToEdit == nil ? "New Training Plan" : "Edit Training Plan").font(.headline)
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
    
    private var mainContent: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    nameCard
                    
                    // Итерираме по индекси и елементи
                    ForEach(Array(sortedDays.enumerated()), id: \.element.id) { index, day in
                        let dayDisplayIndex = index + 1
                        daySection(for: day, dayIndex: dayDisplayIndex)
                        
                        // +++ НАЧАЛО НА ПРОМЯНАТА +++
                        // Показваме бутона "Skip Day", ако:
                        // 1. Денят не е последен.
                        // 2. Текущият ден НЕ е ден за почивка.
                        // 3. Общият брой дни е по-малък от 7.
                        if index < sortedDays.count - 1 && !day.isRestDay && days.count < 7 {
                            skipDayButton(after: day)
                        }
                        // +++ КРАЙ НА ПРОМЯНАТА +++
                    }
                    
                    // Бутонът "Add Day" се показва само в края, ако има място
                    if days.count < 7 {
                        addDayButton
                    }
                }
                .padding()
                Spacer(minLength: 150)
            }
            .onChange(of: focusedField) { oldValue, newFocus in
                if oldValue == .minAge {
                    validateMinAgeOnBlur()
                }
                
                guard let focus = newFocus else { return }
                
                let idToScroll: AnyHashable?
                
                switch focus {
                case .name, .minAge:
                    idToScroll = focus
                case .exerciseDuration(let exerciseID):
                    idToScroll = exerciseID
                }
                
                if let id = idToScroll {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeInOut) {
                            proxy.scrollTo(id, anchor: .top)
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
        // +++ НОВО: Обвиваме в VStack, за да добавим новото поле +++
        VStack(spacing: 12) {
            StyledLabeledPicker(label: "Plan Name", isRequired: true) {
                TextField("", text: $name, prompt: Text("e.g., Strength Phase 1").foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6)))
                    .focused($focusedField, equals: .name)
            }
            .id(FocusableField.name)
            
            // +++ НОВО: Добавяме полето за минимална възраст +++
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
            let workoutPrompts = allPrompts.filter { $0.type == .trainingPlan }
            
            if !workoutPrompts.isEmpty {
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
    
    // +++ НАЧАЛО НА ПРОМЯНАТА: Добавяме изгледи за избор на промптове +++
    @ViewBuilder
    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompts")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            
            let workoutPrompts = allPrompts.filter { $0.type == .trainingPlan }
            
            MultiSelectButton(
                selection: $selectedPromptIDs,
                items: workoutPrompts,
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
                .padding(.horizontal).frame(height: 35)
                
                dropDownLayer
            }
            .padding(.top)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme,effectManager.isLightRowTextColor ? .dark : .light) // 👈 Това принуждава материала да е тъмен
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
        let workoutPrompts = allPrompts.filter { $0.type == .trainingPlan }
        DropdownMenu(
            selection: $selectedPromptIDs,
            items: workoutPrompts,
            label: { $0.text },
            selectAllBtn: false,
            isEditable: true,
            isDeletable: true,
            onEdit: { prompt in
                openMenu = .none
                path.append(NavigationTarget.editPrompt(prompt))
            },
            onDelete: { prompt in
                if #available(iOS 26.0, *) {
                    modelContext.delete(prompt)
                    selectedPromptIDs.remove(prompt.id)
                } else {
                    promptToDelete = prompt
                    isShowingDeletePromptConfirmation = true
                }
            }
        )
    }
    // (+++ КРАЙ НА ПРОМЯНАТА +++)
    
    private func daySection(for day: TrainingPlanDay, dayIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Показваме "Rest Day" в заглавието, ако е ден за почивка
                Text(day.isRestDay ? "Day \(dayIndex): Rest Day" : "Day \(dayIndex)")
                    .font(.headline)
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                
                Spacer()
                
                if days.count > 1 {
                    Button(action: { deleteDay(day) }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle( effectManager.currentGlobalAccentColor, effectManager.currentGlobalAccentColor.opacity(0.1))
                            .font(.title2)
                    }.buttonStyle(.plain)
                }
            }
            
            // Ако денят НЕ е за почивка, показваме съдържанието за тренировки
            if !day.isRestDay {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(profile.trainings.sorted { $0.startTime < $1.startTime }) { workoutTemplate in
                            let workout = getOrCreateWorkout(for: workoutTemplate.name, in: day)
                            workoutTabButton(for: workout, in: day)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                if let workoutID = selectedWorkoutID, let workout = day.workouts.first(where: { $0.id == workoutID }) {
                    workoutContent(for: workout, in: day)
                } else if selectedDayID == day.id {
                    Text("Select a workout to add exercises.")
                        .font(.caption).italic()
                        .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
                }
            }
        }
        .animation(.default, value: selectedWorkoutID)
        .padding()
        .glassCardStyle(cornerRadius: 20)
    }
    
    @ViewBuilder
    private func workoutContent(for workout: TrainingPlanWorkout, in day: TrainingPlanDay) -> some View {
        VStack {
            if !workout.exercises.isEmpty {
                if let dayIndex = days.firstIndex(where: { $0.id == day.id }),
                   let workoutIndex = days[dayIndex].workouts.firstIndex(where: { $0.id == workout.id }) {
                    
                    ForEach($days[dayIndex].workouts[workoutIndex].exercises) { $exerciseLink in
                        TrainingPlanExerciseRowView(
                            link: $exerciseLink,
                            focusedField: $focusedField,
                            focusCase: .exerciseDuration(id: exerciseLink.id),
                            onDelete: { removeExercise(exerciseLink, from: workout) }
                        )
                        .id(exerciseLink.id)
                    }
                }
            } else {
                Text("Tap search to add exercises.")
                    .font(.caption).italic()
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
            }
        }
        .contentShape(Rectangle())
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
                    
                    if let workout = currentlySelectedWorkout {
                        Text(workout.workoutName)
                            .font(.body)
                            .foregroundStyle(effectManager.currentGlobalAccentColor)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: handleContainerHeight)
                
                filterChipsViewForSearch
                    .padding(.bottom, 20)
                
                if searchVM.isLoading && searchVM.items.isEmpty {
                    ProgressView()
                        .padding(14)
                        .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                }
                
                ZStack {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            if displayedSearchResults.isEmpty && !searchVM.isLoading {
                                Text("No results found.")
                                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                                    .padding(.top, 50)
                            } else {
                                ForEach(displayedSearchResults) { item in
                                    Button(action: { addExerciseToSelectedWorkout(item) }) {
                                        HStack(spacing: 8) {
                                            if item.isFavorite {
                                                Image(systemName: "star.fill").foregroundColor(.yellow).font(.caption)
                                            }
                                            if item.isWorkout {
                                                Image(systemName: "figure.strengthtraining.traditional").foregroundColor(.orange).font(.caption)
                                            }
                                            Text(item.name).lineLimit(1)
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
                                            if item.id == searchVM.items.last?.id, searchVM.hasMore {
                                                searchVM.loadNextPage()
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
                    .environment(\.colorScheme,effectManager.isLightRowTextColor ? .dark : .light) // 👈 Това принуждава материала да е тъмен
            }
            .cornerRadius(20, corners: [.topLeft, .topRight])
            .frame(height: UIScreen.main.bounds.height * 0.55)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }
    
    @ViewBuilder
    private var filterChipsViewForSearch: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Button(action: {
                    withAnimation(.easeInOut) {
                        searchVM.isFavoritesModeActive.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .imageScale(.medium)
                            .font(.system(size: 13, weight: .semibold))
                        if searchVM.isFavoritesModeActive {
                            Image(systemName: "xmark")
                                .imageScale(.small)
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .accessibilityLabel("Favorites")
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(searchVM.isFavoritesModeActive ? Color.yellow : Color.yellow.opacity(0.6))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(effectManager.currentGlobalAccentColor, lineWidth: searchVM.isFavoritesModeActive ? 3 : 0)
                    )
                }
                .glassCardStyle(cornerRadius: 20)
                .buttonStyle(.plain)
                
                Button(action: {
                    withAnimation(.easeInOut) {
                        searchVM.workoutFilterMode =
                        (searchVM.workoutFilterMode == .onlyWorkouts ? .all : .onlyWorkouts)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .imageScale(.medium)
                            .font(.system(size: 13, weight: .semibold))
                        if searchVM.workoutFilterMode == .onlyWorkouts {
                            Image(systemName: "xmark")
                                .imageScale(.small)
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .accessibilityLabel("Workouts")
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(searchVM.workoutFilterMode == .onlyWorkouts ? Color.orange : Color.orange.opacity(0.6))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(effectManager.currentGlobalAccentColor, lineWidth: searchVM.workoutFilterMode == .onlyWorkouts ? 3 : 0)
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
    
    @ViewBuilder
    private func muscleChipButton(for group: MuscleGroup) -> some View {
        let isSelected = selectedMuscleGroup == group
        let baseColor = effectManager.currentGlobalAccentColor
        
        Button(action: {
            withAnimation(.easeInOut) {
                selectedMuscleGroup = isSelected ? nil : group
            }
        }) {
            HStack(spacing: 6) {
                Text(group.rawValue).font(.caption).fontWeight(.medium)
                if isSelected {
                    Image(systemName: "xmark").imageScale(.small).font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(baseColor.opacity(isSelected ? 0.4 : 0.2))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? baseColor : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .glassCardStyle(cornerRadius: 20)
    }
    
    private static let palette: [Color] = [
        .cyan, .green, .indigo, .orange, .pink, .purple, .blue, .red
    ]
    
    private var colorFor: [String: Color] { // Keyed by Workout Name
        let sortedTemplates = profile.trainings.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let n = Self.palette.count
        
        return Dictionary(uniqueKeysWithValues:
                            sortedTemplates.enumerated().map { idx, workoutTemplate in
            (workoutTemplate.name, Self.palette[idx % n])
        })
    }
    
    @ViewBuilder
    private func workoutTabButton(for workout: TrainingPlanWorkout, in day: TrainingPlanDay) -> some View {
        let isSelected = selectedWorkoutID == workout.id && selectedDayID == day.id
        let baseColor = colorFor[workout.workoutName] ?? effectManager.currentGlobalAccentColor
        
        Button {
            withAnimation {
                selectedDayID = day.id
                selectedWorkoutID = workout.id
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Text(workout.workoutName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isSelected ? baseColor.opacity(0.8) : baseColor.opacity(0.3))
                    )
                    .glassCardStyle(cornerRadius: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(baseColor, lineWidth: isSelected ? 2 : 0)
                    )
                    .foregroundColor(effectManager.currentGlobalAccentColor)
                
                if !workout.exercises.isEmpty {
                    ZStack {
                        Circle().fill(baseColor)
                        Text("\(workout.exercises.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(effectManager.currentGlobalAccentColor)
                    }
                    .frame(width: 16, height: 16)
                    .offset(x: 6, y: -6)
                } else {
                    ZStack {
                        Circle().fill(baseColor)
                        Text("0")
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
    
    // MARK: - Actions & Logic
    
    // +++ НОВО (6/8): Логика за изчисляване и валидиране на възрастта +++
    private func recalculateAndValidateMinAge() {
        let requiredMinAge = allExercisesInPlan.map { $0.minimalAgeMonths }.max() ?? 0
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
    
    private func onAppearSetup() {
        searchVM.attach(context: modelContext)
        searchVM.query = globalSearchText
        searchVM.workoutFilterMode = .all
        updateSearchExclusions()
        if selectedDayID == nil, let firstDay = sortedDays.first {
            selectedDayID = firstDay.id
            if let firstWorkoutTemplate = profile.trainings.sorted(by: { $0.startTime < $1.startTime }).first {
                let firstWorkout = getOrCreateWorkout(for: firstWorkoutTemplate.name, in: firstDay)
                selectedWorkoutID = firstWorkout.id
            }
        }
        loadAIButtonPosition()
        recalculateAndValidateMinAge() // +++ НОВО: Извикваме при зареждане
    }
    
    private func savePlan() {
        Task { @MainActor in
            isSaving = true
            await Task.yield()
            defer { isSaving = false }
            
            let planToSave: TrainingPlan
            
            if let existingPlan = planToEdit {
                planToSave = existingPlan
            } else {
                planToSave = TrainingPlan(name: name, profile: profile)
                modelContext.insert(planToSave)
            }
            
            planToSave.name = name
            // +++ НОВО (7/8): Запазваме стойността за минимална възраст +++
            planToSave.minAgeMonths = Int(minAgeMonthsTxt) ?? 0
            
            await createOrUpdateWorkouts(for: planToSave)
            syncDays(of: planToSave, from: self.days)
            
            do {
                try modelContext.save()
                onDismiss(planToSave)
            } catch {
                alertMessage = "Failed to save plan. Error: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    private func createOrUpdateWorkouts(for plan: TrainingPlan) async {
        for day in days {
            for workout in day.workouts {
                guard !workout.exercises.isEmpty else {
                    // ... твоята логика за чистене на oldWorkoutItem ...
                    if let oldWorkoutID = workout.linkedWorkoutID {
                        if let oldWorkoutItem = try? modelContext.fetch(
                            FetchDescriptor<ExerciseItem>(predicate: #Predicate { $0.id == oldWorkoutID })
                        ).first {
                            modelContext.delete(oldWorkoutItem)
                        }
                        workout.linkedWorkoutID = nil
                    }
                    continue
                }
                
                let workoutName = "\(plan.name) - Day \(day.dayIndex) - \(workout.workoutName)"
                let workoutToUpdate: ExerciseItem
                
                if let existingID = workout.linkedWorkoutID,
                   let found = try? modelContext.fetch(
                        FetchDescriptor<ExerciseItem>(predicate: #Predicate { $0.id == existingID })
                   ).first {
                    workoutToUpdate = found
                } else {
                    let newID = nextExerciseId()
                    workoutToUpdate = ExerciseItem(id: newID, name: workoutName, muscleGroups: [], isWorkout: true)
                    modelContext.insert(workoutToUpdate)
                    workout.linkedWorkoutID = newID
                }
                
                workoutToUpdate.name = workoutName
                workoutToUpdate.isWorkout = true
                
                // 👉 Вземаме само валидните TrainingPlanExercise, които имат exercise
                let validLinks = workout.exercises.filter { $0.exercise != nil }
                
                // Изчистваме старите ExerciseLink от Workout-а в ExerciseItem
                workoutToUpdate.exercises?.forEach { modelContext.delete($0) }
                
                // Създаваме нови ExerciseLink само за валидните упражнения
                workoutToUpdate.exercises = validLinks.map { exerciseLink in
                    ExerciseLink(
                        exercise: exerciseLink.exercise!,
                        durationMinutes: exerciseLink.durationMinutes,
                        owner: workoutToUpdate
                    )
                }
                
                let aggregatedMuscles = Array(Set(validLinks.flatMap { $0.exercise?.muscleGroups ?? [] }))
                let aggregatedSports  = Array(Set(validLinks.flatMap { $0.exercise?.sports ?? [] }))
                
                workoutToUpdate.muscleGroups = aggregatedMuscles
                workoutToUpdate.sports       = aggregatedSports
                
                let totalDuration = validLinks.reduce(0) { $0 + $1.durationMinutes }
                workoutToUpdate.durationMinutes = Int(totalDuration)
                
                let metValues   = validLinks.compactMap { $0.exercise?.metValue }
                workoutToUpdate.metValue = metValues.isEmpty ? nil : metValues.reduce(0, +) / Double(metValues.count)
                
                let requiredAge = validLinks.compactMap { $0.exercise?.minimalAgeMonths }.max() ?? 0
                workoutToUpdate.minimalAgeMonths = requiredAge
            }
        }
    }

    
    private func nextExerciseId() -> Int {
        var desc = FetchDescriptor<ExerciseItem>()
        desc.sortBy = [SortDescriptor(\.id, order: .reverse)]
        desc.fetchLimit = 1
        let maxId = ((try? modelContext.fetch(desc))?.first?.id) ?? 0
        return maxId + 1
    }
    
    private func syncDays(of plan: TrainingPlan, from stateDays: [TrainingPlanDay]) {
        // Преобразуваме за бърз достъп
        let stateDaysByID = Dictionary(uniqueKeysWithValues: stateDays.map { ($0.id, $0) })
        
        // 1. Изтриваме дни от плана, които вече не са в състоянието
        for day in plan.days {
            if stateDaysByID[day.id] == nil {
                modelContext.delete(day)
            }
        }
        
        // 2. Актуализираме съществуващи и добавяме нови дни
        for stateDay in stateDays {
            // Намираме съществуващ ден или създаваме нов
            let persistedDay = plan.days.first(where: { $0.id == stateDay.id }) ?? {
                let newDay = TrainingPlanDay(dayIndex: stateDay.dayIndex, isRestDay: stateDay.isRestDay)
                newDay.plan = plan
                modelContext.insert(newDay)
                return newDay
            }()
            
            // Актуализираме свойствата
            persistedDay.dayIndex = stateDay.dayIndex
            persistedDay.isRestDay = stateDay.isRestDay
            
            if persistedDay.isRestDay {
                // Ако е ден за почивка, изтриваме всички тренировки от него
                persistedDay.workouts.forEach { modelContext.delete($0) }
                persistedDay.workouts = []
            } else {
                // Ако не е, синхронизираме тренировките
                syncWorkouts(of: persistedDay, from: stateDay)
            }
        }
    }
    
    private func syncWorkouts(of persistedDay: TrainingPlanDay, from stateDay: TrainingPlanDay) {
        let stateWorkoutsByName = Dictionary(grouping: stateDay.workouts, by: { $0.workoutName }).compactMapValues { $0.first }
        
        for workout in persistedDay.workouts where stateWorkoutsByName[workout.workoutName] == nil {
            modelContext.delete(workout)
        }
        
        for (name, stateWorkout) in stateWorkoutsByName {
            let persistedWorkout = getOrCreateWorkout(for: name, in: persistedDay)
            persistedWorkout.exercises.forEach { modelContext.delete($0) }
            persistedWorkout.exercises = stateWorkout.exercises.map { entry in
                TrainingPlanExercise(exercise: entry.exercise!, durationMinutes: entry.durationMinutes, workout: persistedWorkout)
            }
            persistedWorkout.linkedWorkoutID = stateWorkout.linkedWorkoutID
        }
    }
    
    private func addDay() {
        withAnimation {
            let nextIndex = (days.map { $0.dayIndex }.max() ?? 0) + 1
            let newDay = TrainingPlanDay(dayIndex: nextIndex) // isRestDay е false по подразбиране
            days.append(newDay)
        }
    }
    
    private func deleteDay(_ dayToDelete: TrainingPlanDay) {
        withAnimation {
            days.removeAll { $0.id == dayToDelete.id }
            renumberDays() // Преномерираме останалите дни
            
            if selectedDayID == dayToDelete.id {
                selectedDayID = sortedDays.first?.id
                selectedWorkoutID = nil
            }
            recalculateAndValidateMinAge()
        }
    }
    
    private func getOrCreateWorkout(for workoutName: String, in day: TrainingPlanDay) -> TrainingPlanWorkout {
        if let existing = day.workouts.first(where: { $0.workoutName == workoutName }) {
            return existing
        } else {
            let newWorkout = TrainingPlanWorkout(workoutName: workoutName)
            newWorkout.day = day
            if let dayIndex = days.firstIndex(where: { $0.id == day.id }) {
                days[dayIndex].workouts.append(newWorkout)
            }
            return newWorkout
        }
    }
    
    private func addExerciseToSelectedWorkout(_ item: ExerciseItem) {
        guard let dayIndex = days.firstIndex(where: { $0.id == selectedDayID }),
              let workoutIndex = days[dayIndex].workouts.firstIndex(where: { $0.id == selectedWorkoutID })
        else {
            alertMessage = "Please select a day and a workout first."
            showAlert = true
            return
        }
        
        var exercisesToAddOrUpdate: [(exercise: ExerciseItem, duration: Double)] = []
        
        if item.isWorkout, let subExercises = item.exercises, !subExercises.isEmpty {
            for link in subExercises {
                guard let exercise = link.exercise else { continue }
                let duration = link.durationMinutes > 0 ? link.durationMinutes : Double(exercise.durationMinutes ?? 15)
                exercisesToAddOrUpdate.append((exercise, duration))
            }
        } else {
            let duration = Double(item.durationMinutes ?? 15)
            exercisesToAddOrUpdate.append((item, duration))
        }
        
        for tuple in exercisesToAddOrUpdate {
            let (exerciseToAdd, duration) = tuple
            
            if let existingExerciseIndex = days[dayIndex].workouts[workoutIndex].exercises.firstIndex(where: { $0.exercise?.id == exerciseToAdd.id }) {
                days[dayIndex].workouts[workoutIndex].exercises[existingExerciseIndex].durationMinutes = duration
            } else {
                let newLink = TrainingPlanExercise(exercise: exerciseToAdd, durationMinutes: duration)
                newLink.workout = days[dayIndex].workouts[workoutIndex]
                days[dayIndex].workouts[workoutIndex].exercises.append(newLink)
                scrollToExerciseID = newLink.id
            }
        }
        
        updateSearchExclusions()
        dismissSearchOverlay()
        recalculateAndValidateMinAge() // +++ НОВО: Преизчисляваме при добавяне
    }
    
    private func removeExercise(_ exerciseLink: TrainingPlanExercise, from workout: TrainingPlanWorkout) {
        withAnimation {
            if let dayIndex = days.firstIndex(where: { $0.id == workout.day?.id }),
               let workoutIndex = days[dayIndex].workouts.firstIndex(where: { $0.id == workout.id }) {
                days[dayIndex].workouts[workoutIndex].exercises.removeAll { $0.id == exerciseLink.id }
            }
        }
        updateSearchExclusions()
        recalculateAndValidateMinAge() // +++ НОВО: Преизчисляваме при премахване
    }
    
    private func updateSearchExclusions() {
        let excluded = Set(currentlySelectedWorkout?.exercises.compactMap { $0.exercise } ?? [])
        searchVM.exclude(excluded)
    }
    
    private func dismissSearchOverlay() {
        isSearchFieldFocused = false
        globalSearchText = ""
    }
    
    private func syncStateFromLinkedWorkouts() async {
        let context = self.modelContext
        for day in days {
            for workout in day.workouts {
                guard let workoutID = workout.linkedWorkoutID else { continue }
                let descriptor = FetchDescriptor<ExerciseItem>(predicate: #Predicate { $0.id == workoutID })
                if let workoutItem = (try? context.fetch(descriptor))?.first {
                    
                    var newExercises: [TrainingPlanExercise] = []
                    for link in workoutItem.exercises ?? [] {
                        if let exercise = link.exercise {
                            let newExercise = TrainingPlanExercise(exercise: exercise, durationMinutes: link.durationMinutes, workout: workout)
                            newExercises.append(newExercise)
                        }
                    }
                    workout.exercises = newExercises
                }
            }
        }
    }
    
    private func handleAITap() {
        
        guard ensureAIAvailableOrShowMessage() else { return }
        
        // Determine which workouts need to be generated (those with no exercises)
        let workoutsToGenerate = days.reduce(into: [Int: [String]]()) { result, day in
            // --- НАЧАЛО НА ПРОМЯНАТА: Проверяваме isRestDay ---
            // Генерираме тренировки само за дни, които не са за почивка
            if !day.isRestDay {
                let emptyWorkoutNames = day.workouts.filter { $0.exercises.isEmpty }.map { $0.workoutName }
                if !emptyWorkoutNames.isEmpty {
                    result[day.dayIndex] = emptyWorkoutNames
                }
            }
            // --- КРАЙ НА ПРОМЯНАТА ---
        }
        
        // If there are no empty workouts, inform the user.
        guard !workoutsToGenerate.isEmpty else {
            alertMessage = "All workouts for all days already have exercises. Clear some workouts if you want to generate new ones."
            showAlert = true
            return
        }
        
        // Prepare existing workouts to provide context to the AI
        let existingWorkouts = days.reduce(into: [Int: [TrainingPlanWorkoutDraft]]()) { result, day in
            let populatedWorkouts = day.workouts.filter { !$0.exercises.isEmpty }
            if !populatedWorkouts.isEmpty {
                result[day.dayIndex] = populatedWorkouts.map { workout in
                    let exercises = workout.exercises.compactMap { exerciseLink -> TrainingPlanExerciseDraft? in
                        guard let exercise = exerciseLink.exercise else { return nil }
                        return TrainingPlanExerciseDraft(
                            exerciseName: exercise.name,
                            durationMinutes: exerciseLink.durationMinutes
                        )
                    }
                    return TrainingPlanWorkoutDraft(workoutName: workout.workoutName, exercises: exercises)
                }
            }
        }
        
        let selectedPrompts = allPrompts.filter { selectedPromptIDs.contains($0.id) }.map { $0.text }
        
        triggerAIGenerationToast()
        
        // Call the updated AIManager function
        if let newJob = aiManager.startTrainingPlanGeneration(
            for: self.profile,
            prompts: selectedPrompts,
            workoutsToFill: workoutsToGenerate,
            existingWorkouts: existingWorkouts,
            jobType: .trainingPlan
        ) {
            self.runningGenerationJobID = newJob.id
            hasUserMadeEdits = false
        } else {
            alertMessage = "Could not start AI training plan generation job."
            showAlert = true
            toastTimer?.invalidate(); toastTimer = nil
            withAnimation { showAIGenerationToast = false }
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
    
    // +++ НАЧАЛО НА ПРОМЯНАТА: Добавяме функции за запазване/зареждане на ID-та на промптове +++
    private func saveSelectedPromptIDs(_ ids: Set<UUID>) {
        let idStrings = ids.map { $0.uuidString }
        UserDefaults.standard.set(idStrings, forKey: selectedPromptsKey)
    }
    
    private func loadSelectedPromptIDs() {
        guard let idStrings = UserDefaults.standard.stringArray(forKey: selectedPromptsKey) else { return }
        let ids = idStrings.compactMap { UUID(uuidString: $0) }
        self.selectedPromptIDs = Set(ids)
    }
    // (+++ КРАЙ НА ПРОМЯНАТА +++)
    
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
            .font(.title3)
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
    
    @MainActor
    private func populateFromCompletedJob(jobID: UUID) async {
        guard let job = aiManager.jobs.first(where: { $0.id == jobID }),
              let resultData = job.resultData else {
            alertMessage = "Could not find the completed AI job (id: \(jobID))."
            showAlert = true
            runningGenerationJobID = nil
            return
        }
        
        guard let draft = try? JSONDecoder().decode(TrainingPlanDraft.self, from: resultData) else {
            alertMessage = "Could not decode the generated training plan data."
            showAlert = true
            runningGenerationJobID = nil
            await aiManager.deleteJob(byID: jobID)
            return
        }
        
        // --- НАЧАЛО НА КОРЕКЦИЯТА: Извикваме новата merge функция ---
        withAnimation(.easeInOut) {
            merge(draft: draft)
        }
        // --- КРАЙ НА КОРЕКЦИЯТА ---
        
        toastTimer?.invalidate(); toastTimer = nil
        withAnimation { showAIGenerationToast = false }
        
        await aiManager.deleteJob(byID: jobID)
        runningGenerationJobID = nil
    }
    
    @ViewBuilder
    private var aiGenerationToast: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Generating Plan...").fontWeight(.bold)
                    Text("You'll be notified when your plan is ready.").font(.caption)
                    ProgressView(value: min(max(toastProgress, 0.0), 1.0), total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                        .animation(.linear, value: toastProgress)
                }
                Spacer()
                Button("OK") {
                    toastTimer?.invalidate(); toastTimer = nil
                    withAnimation { showAIGenerationToast = false }
                }
                .buttonStyle(.borderless).foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
            }
            .foregroundStyle(effectManager.currentGlobalAccentColor)
            .padding().glassCardStyle(cornerRadius: 20).padding()
            .transition(.move(edge: .top).combined(with: .opacity))
            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top).ignoresSafeArea(.keyboard)
    }
    
    private func triggerAIGenerationToast() {
        toastTimer?.invalidate()
        toastProgress = 0.0
        withAnimation { showAIGenerationToast = true }
        
        let totalDuration = 10.0 // По-дълго време за по-сложна задача
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
    
    private func addRestDay(after precedingDay: TrainingPlanDay) {
        withAnimation {
            // 1. Намираме индекса на деня, след който вмъкваме
            let insertionIndex = precedingDay.dayIndex + 1
            
            // 2. Увеличаваме индексите на всички следващи дни
            for day in days where day.dayIndex >= insertionIndex {
                day.dayIndex += 1
            }
            
            // 3. Създаваме и добавяме новия ден за почивка
            let newRestDay = TrainingPlanDay(dayIndex: insertionIndex, isRestDay: true)
            days.append(newRestDay)
            
            // 4. Пресортираме масива, за да се обнови UI правилно
            days.sort { $0.dayIndex < $1.dayIndex }
        }
    }
    
    private func renumberDays() {
        let sortedForNumbering = days.sorted { $0.dayIndex < $1.dayIndex }
        
        for (index, day) in sortedForNumbering.enumerated() {
            // Намираме деня в оригиналния @State масив по ID, за да го променим
            if let dayInState = days.first(where: { $0.id == day.id }) {
                dayInState.dayIndex = index + 1
            }
        }
    }
    
    private var addDayButton: some View {
        Button(action: addDay) {
            Label("Add Day", systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .glassCardStyle(cornerRadius: 20)
        .foregroundColor(effectManager.currentGlobalAccentColor)
    }
    
    // Изглед за бутона "Skip Day"
    private func skipDayButton(after day: TrainingPlanDay) -> some View {
        Button(action: { addRestDay(after: day) }) {
            Label("Skip Day", systemImage: "powersleep")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .glassCardStyle(cornerRadius: 20)
        .foregroundColor(effectManager.currentGlobalAccentColor)
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
    
    @MainActor
    private func merge(draft: TrainingPlanDraft) {
        self.name = draft.name
        
        // Итерираме през дните от черновата
        for dayDraft in draft.days {
            // Намираме съответния ден в текущото състояние по неговия dayIndex
            if let dayToUpdate = self.days.first(where: { $0.dayIndex == dayDraft.dayIndex }) {
                
                dayToUpdate.isRestDay = false // Вече не е ден за почивка
                
                // Изчистваме старите тренировки, за да ги заменим
                dayToUpdate.workouts.forEach { modelContext.delete($0) }
                dayToUpdate.workouts.removeAll()
                
                var newWorkoutsForDay: [TrainingPlanWorkout] = []
                
                for training in dayDraft.trainings {
                    let newWorkout = TrainingPlanWorkout(workoutName: training.name)
                    let exercises = training.exercises(using: modelContext)
                    
                    for (exerciseItem, duration) in exercises {
                        let newExercise = TrainingPlanExercise(exercise: exerciseItem, durationMinutes: duration, workout: newWorkout)
                        newWorkout.exercises.append(newExercise)
                    }
                    newWorkout.day = dayToUpdate
                    newWorkoutsForDay.append(newWorkout)
                }
                
                dayToUpdate.workouts = newWorkoutsForDay
            } else {
                // Ако такъв ден не съществува, създаваме го (случай при инициализация с празен `days`)
                let newDay = TrainingPlanDay(dayIndex: dayDraft.dayIndex)
                var newWorkoutsForDay: [TrainingPlanWorkout] = []
                for training in dayDraft.trainings {
                    let newWorkout = TrainingPlanWorkout(workoutName: training.name)
                    let exercises = training.exercises(using: modelContext)
                    for (item, duration) in exercises {
                        newWorkout.exercises.append(TrainingPlanExercise(exercise: item, durationMinutes: duration, workout: newWorkout))
                    }
                    newWorkout.day = newDay
                    newWorkoutsForDay.append(newWorkout)
                }
                newDay.workouts = newWorkoutsForDay
                self.days.append(newDay)
            }
        }
        
        // Пресортираме, за да сме сигурни, че UI е в ред
        self.days.sort { $0.dayIndex < $1.dayIndex }
        recalculateAndValidateMinAge()
    }
}
