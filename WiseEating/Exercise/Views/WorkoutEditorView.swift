import SwiftUI
import SwiftData
import PhotosUI

@MainActor
struct WorkoutEditorView: View {
    
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
    private let aiButtonPositionKey = "floatingWorkoutAIButtonPosition"
    
    // MARK: - Environment & Dependencies
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var modelContext
    
    // MARK: - Input
    let onDismiss: (ExerciseItem?) -> Void
    private let workoutToEdit: ExerciseItem?
    private let dubWorkout: ExerciseItemCopy?
    
    // MARK: - Global Search Integration
    @Binding var globalSearchText: String
    @FocusState.Binding var isSearchFieldFocused: Bool
    let onDismissSearch: () -> Void
    
    // MARK: - ViewModels
    @StateObject private var searchVM = ExerciseSearchVM()
    
    // MARK: - Editable State (Workout base fields)
    @State private var name: String = ""
    @State private var description: String = ""
    
    @State private var videoURL: String = ""
    
    @State private var minimalAgeMonthsTxt: String = ""
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    
    @State private var galleryData: [Data] = []
    @State private var newGalleryItems: [PhotosPickerItem] = []
    @State private var showReplacePicker = false
    @State private var replacementItem: PhotosPickerItem?
    @State private var replaceAtIndex: Int?
    @State private var tappedIndex: Int? = nil
    @State private var showPopover = false
    
    // Exercises inside the workout
    @State private var editableExercises: [EditableExerciseLink] = []
    
    // MARK: - UI State
    @State private var isSaving = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var scrollToExerciseID: EditableExerciseLink.ID? = nil
    
    @State private var calculatedMinAge: Int = 0
    
    // +++ НАЧАЛО НА ПРОМЯНАТА: Състояния за промпт +++
    // MARK: - Prompt State & Navigation
    @Query(sort: \Prompt.creationDate, order: .reverse) private var allPrompts: [Prompt]
    @State private var selectedPromptIDs: Set<Prompt.ID> = []
    @State private var path = NavigationPath()
    private enum NavigationTarget: Hashable {
        case promptEditor
        case editPrompt(Prompt)
    }
    @State private var promptToDelete: Prompt? = nil
    @State private var isShowingDeletePromptConfirmation = false
    private let selectedPromptsKey = "WorkoutEditorView_SelectedPrompts"
    // +++ КРАЙ НА ПРОМЯНАТА +++
    
    
    // MARK: - Focus State
    enum FocusableField: Hashable {
        case name, description, minAge
        case videoURL
        case duration(id: UUID)
    }
    @FocusState private var focusedField: FocusableField?
    
    // Bottom sheet for multi-selects
    fileprivate enum OpenMenu { case none, promptSelector } // ++ ПРОМЯНА ++
    @State private var openMenu: OpenMenu = .none
    
    struct EditableExerciseLink: Identifiable, Equatable {
        let id = UUID()
        var exercise: ExerciseItem
        var durationMinutes: Double
    }
    
    @State private var selectedMuscleGroup: MuscleGroup? = nil
    let profile: Profile?
    
    // MARK: - Initializer
    init(
           itemToEdit: ExerciseItem? = nil,
           dubWorkout: ExerciseItemCopy? = nil,
           profile: Profile?,
           globalSearchText: Binding<String>,
           isSearchFieldFocused: FocusState<Bool>.Binding,
           onDismissSearch: @escaping () -> Void,
           onDismiss: @escaping (ExerciseItem?) -> Void // <--- ПРОМЯНА: Типът на onDismiss
       ) {
           self.profile = profile
           self.onDismiss = onDismiss
           self._globalSearchText = globalSearchText
           self._isSearchFieldFocused = isSearchFieldFocused
           self.onDismissSearch = onDismissSearch
           
           self.workoutToEdit = itemToEdit
           self.dubWorkout = dubWorkout
           
           // Логика за попълване на полетата, с приоритет на dubWorkout
           if let copy = dubWorkout {
               _name = State(initialValue: copy.name)
               _description = State(initialValue: copy.exerciseDescription ?? "")
               _photoData = State(initialValue: copy.photo)
               _minimalAgeMonthsTxt = State(initialValue: copy.minimalAgeMonths > 0 ? String(copy.minimalAgeMonths) : "")
               _videoURL = State(initialValue: copy.videoURL ?? "")
               _galleryData = State(initialValue: copy.gallery ?? [])
               _editableExercises = State(initialValue: copy.exercises?.compactMap { link in
                   guard let exCopy = link.exercise else { return nil }
                   // Тук трябва да намерим реалния ExerciseItem от базата данни,
                   // но тъй като ExerciseItemCopy няма достъп, ще трябва да го резолвнем по-късно
                   // Засега, създаваме временна структура
                   // Тази част предполага, че ExerciseItemCopy има init(from: ExerciseItem)
                   // което не е така.
                   // Нека го направим по-просто:
                   // ExerciseLinkCopy трябва да съдържа пълния ExerciseItem
                   let context = GlobalState.modelContext!
                   let exID = exCopy.originalID!
                   let descriptor = FetchDescriptor<ExerciseItem>(predicate: #Predicate { $0.id == exID })
                   if let realItem = (try? context.fetch(descriptor))?.first {
                       return EditableExerciseLink(exercise: realItem, durationMinutes: link.durationMinutes)
                   }
                   return nil
               } ?? [])
           } else if let p = itemToEdit {
               _name = State(initialValue: p.name)
               _description = State(initialValue: p.exerciseDescription ?? "")
               _photoData = State(initialValue: p.photo)
               _minimalAgeMonthsTxt = State(initialValue: p.minimalAgeMonths > 0 ? String(p.minimalAgeMonths) : "")
               _videoURL = State(initialValue: p.videoURL ?? "")
               _galleryData = State(initialValue: p.gallery?.map(\.data) ?? [])
               _editableExercises = State(initialValue: []) // Ще се зареди в onAppear
           } else { // New workout
               _name = State(initialValue: "")
               _description = State(initialValue: "")
               _photoData = State(initialValue: nil)
               _minimalAgeMonthsTxt = State(initialValue: "")
               _videoURL = State(initialValue: "")
               _galleryData = State(initialValue: [])
               _editableExercises = State(initialValue: [])
           }
       }
    
    private var totalDuration: Double {
        editableExercises.reduce(0) { $0 + $1.durationMinutes }
    }
    
    private var averageMET: Double? {
        let metValues = editableExercises.compactMap { $0.exercise.metValue }
        guard !metValues.isEmpty else { return nil }
        return metValues.reduce(0, +) / Double(metValues.count)
    }
    
    private var aggregatedMuscleGroups: [MuscleGroup] {
        let allGroups = editableExercises.flatMap { $0.exercise.muscleGroups }
        return Array(Set(allGroups)).sorted { $0.rawValue < $1.rawValue }
    }
    
    private var aggregatedSports: [Sport] {
        let allSports = editableExercises.flatMap { $0.exercise.sports ?? [] }
        return Array(Set(allSports)).sorted { $0.rawValue < $1.rawValue }
    }
    
    private var allMuscleGroups: [MuscleGroup] {
        MuscleGroup.allCases.sorted { $0.rawValue < $1.rawValue }
    }
    
    // MARK: - Computed
    private var navigationTitle: String {
        workoutToEdit == nil ? "New Workout" : "Edit Workout"
    }
    
    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving
    }
    
    private var displayedSearchResults: [ExerciseItem] {
        return searchVM.items as [ExerciseItem]
    }
    
    var body: some View {
        bodyContent
    }
    
    private var bodyContent: some View {
        NavigationStack(path: $path) {
            ZStack {
                ThemeBackgroundView().ignoresSafeArea()
                
                VStack(spacing: 0) {
                    customToolbar
                    mainForm
                }
                .disabled(isSaving)
                .blur(radius: isSaving ? 1.5 : 0)
                
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
                    .accessibilityLabel("Saving")
                    .zIndex(1000)
                }
                
                if isSearchFieldFocused {
                    fullScreenSearchResultsView
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                        .zIndex(1)
                }
                
                if openMenu != .none {
                    bottomSheetPanel
                        .transition(.move(edge: .bottom).animation(.easeInOut(duration: 0.3)))
                        .zIndex(1)
                }
            }
            .overlay {
                if showAIGenerationToast {
                    aiGenerationToast
                }
                GeometryReader { geometry in
                    Group {
                        if openMenu == .none &&
                            !isSaving &&
                            !showAlert &&
                            !isSearchFieldFocused &&
                            !showPopover &&
                            GlobalState.aiAvailability != .deviceNotEligible { // ⬅️ ново: скрий при недопустимо устройство
                            AnyView(AIButton(geometry: geometry))
                        } else {
                            AnyView(EmptyView())
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .onAppear { loadAIButtonPosition() }
            .onReceive(NotificationCenter.default.publisher(for: .aiWorkoutJobCompleted)) { notification in
                guard !hasUserMadeEdits,
                      let userInfo = notification.userInfo,
                      let completedJobID = userInfo["jobID"] as? UUID,
                      completedJobID == self.runningGenerationJobID else {
                    return
                }
                
                print("▶️ WorkoutEditorView: Received .aiWorkoutJobCompleted for job \(completedJobID). Populating data.")
                
                Task {
                    await populateFromCompletedJob(jobID: completedJobID)
                }
            }
            .onChange(of: name) { _, _ in hasUserMadeEdits = true }
            .onChange(of: description) { _, _ in hasUserMadeEdits = true }
            .onChange(of: editableExercises) { _, _ in hasUserMadeEdits = true }
            .onChange(of: selectedPhoto) { _, _ in hasUserMadeEdits = true }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: setupOnce)
            .onAppear(perform: loadSelectedPromptIDs)
            .onChange(of: selectedPromptIDs, perform: saveSelectedPromptIDs)
            .alert("Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: { Text(alertMessage) }
                .onChange(of: globalSearchText) { _, newText in
                    searchVM.query = newText
                }
                .photosPicker(isPresented: $showReplacePicker, selection: $replacementItem, matching: .images)
                .onChange(of: replacementItem, handleReplacementItemChange)
                .onChange(of: selectedMuscleGroup) { _, newGroup in
                    searchVM.muscleGroupFilter = newGroup
                }
                .onChange(of: editableExercises) { _, _ in
                    recalculateAndValidateMinAge()
                }
                .navigationDestination(for: NavigationTarget.self) { target in
                    switch target {
                    case .promptEditor:
                        PromptEditorView(promptType: .workout) { newPrompt in
                            path.removeLast()
                            if let newPrompt = newPrompt {
                                selectedPromptIDs.insert(newPrompt.id)
                            }
                        }
                        
                    case .editPrompt(let prompt):
                        PromptEditorView(promptType: .workout, promptToEdit: prompt) { editedPrompt in
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
        }
    }
    
    // MARK: - Toolbar & Sections
    private var customToolbar: some View {
        HStack {
            Button("Cancel", action: { onDismiss(nil) })
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
            
            Spacer()
            
            Text(navigationTitle)
                .font(.headline)
            
            Spacer()
            
            Button("Save", action: saveWorkout)
                .disabled(isSaveDisabled)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
                .foregroundStyle(isSaveDisabled
                                 ? effectManager.currentGlobalAccentColor.opacity(0.4)
                                 : effectManager.currentGlobalAccentColor)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding([.horizontal, .top])
    }
    
    private var mainForm: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    generalSection
                    
                    gallerySection
                    detailsSection
                    muscleGroupSection
                    sportsSection
                    exercisesSection
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
                case .name, .description, .videoURL, .minAge:
                    idToScroll = focus
                case .duration(let id):
                    idToScroll = id
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
    
    // +++ НАЧАЛО НА ПРОМЯНАТА: Нова ViewBuilder функция +++
    @ViewBuilder
    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompts")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            
            let workoutPrompts = allPrompts.filter { $0.type == .workout }
            
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
    // +++ КРАЙ НА ПРОМЯНАТА +++
    
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .padding(.bottom, -4)
            
            VStack(spacing: 16) {
                StyledLabeledPicker(label: "Workout Name", isRequired: true) {
                    ConfigurableTextField(
                        title: "e.g., Full Body Strength",
                        value: $name,
                        type: .standard,
                        placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                        textAlignment: .leading,
                        focused: $focusedField,
                        fieldIdentifier: .name
                    )
                }
                .id(FocusableField.name)
                
                HStack(alignment: .center, spacing: 16) {
                    photoPicker
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 16) {
                            StyledLabeledPicker(label: "Total Duration") {
                                HStack {
                                    Text("\(totalDuration, specifier: "%.0f") min")
                                        .font(.system(size: 16))
                                    Spacer()
                                }
                            }
                        }
                        
                        StyledLabeledPicker(label: "Description", height: 120) {
                            descriptionEditor
                                .focused($focusedField, equals: .description)
                        }
                        .id(FocusableField.description)
                    }
                }
                StyledLabeledPicker(label: "Minimum Age (months)") {
                    ConfigurableTextField(
                        title: "e.g. 6",
                        value: $minimalAgeMonthsTxt,
                        type: .integer,
                        placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                        textAlignment: .leading,
                        focused: $focusedField,
                        fieldIdentifier: .minAge
                    )
                    .font(.system(size: 16))
                }
                .id(FocusableField.minAge)
                
                let workoutPrompts = allPrompts.filter { $0.type == .workout }
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
    }
    
    private var detailsSection: some View {
        VStack(spacing: 16) {
            StyledLabeledPicker(label: "Video URL (optional)") {
                ConfigurableTextField(
                    title: "e.g., https://youtube.com/...",
                    value: $videoURL,
                    type: .standard,
                    placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                    textAlignment: .leading,
                    focused: $focusedField,
                    fieldIdentifier: .videoURL
                )
            }
            .id(FocusableField.videoURL)
            
            StyledLabeledPicker(label: "Average MET Value") {
                HStack {
                    if let avgMET = averageMET {
                        Text(String(format: "%.1f", avgMET))
                            .font(.system(size: 16))
                    } else {
                        Text("N/A")
                            .font(.system(size: 16))
                            .italic()
                    }
                    Spacer()
                }
            }
        }
        .padding()
        .glassCardStyle(cornerRadius: 20)
    }
    
    private var muscleGroupSection: some View {
        let aggregatedIDs = Set(aggregatedMuscleGroups.map(\.id))
        
        return VStack(alignment: .leading, spacing: 8) {
            Text("Primary Muscles")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            MultiSelectButton(
                selection: .constant(aggregatedIDs),
                items: aggregatedMuscleGroups,
                label: { $0.rawValue },
                prompt: "Add exercises to see muscle groups",
                isExpanded: false,
                disabled: true
            )
            .padding(.vertical, 5).padding(.horizontal, 10)
            .glassCardStyle(cornerRadius: 20)
        }
    }
    
    private var sportsSection: some View {
        let aggregatedIDs = Set(aggregatedSports.map(\.id))
        
        return VStack(alignment: .leading, spacing: 8) {
            Text("Related Sports")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            MultiSelectButton(
                selection: .constant(aggregatedIDs),
                items: aggregatedSports,
                label: { $0.rawValue },
                prompt: "Add exercises to see related sports",
                isExpanded: false,
                disabled: true
            )
            .padding(.vertical, 5).padding(.horizontal, 10)
            .glassCardStyle(cornerRadius: 20)
        }
    }
    
    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercises")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .padding(.bottom, -4)
            
            VStack {
                if editableExercises.isEmpty {
                    ContentUnavailableView(
                        "No Exercises",
                        systemImage: "figure.run.circle",
                        description: Text("Use the search above to add exercises to this workout.")
                    )
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                    .frame(minHeight: 120)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach($editableExercises) { $link in
                            EditableExerciseRow(
                                link: $link,
                                onDelete: { delete(exerciseLink: link) },
                                focusedField: $focusedField,
                                focusCase: .duration(id: link.id)
                            )
                            .id(link.id)
                        }
                    }
                }
            }
            .padding()
            .glassCardStyle(cornerRadius: 20)
        }
    }
    
    // MARK: - Full-screen search layer
    @ViewBuilder
    private var fullScreenSearchResultsView: some View {
        ZStack(alignment: .bottom) {
            
            if effectManager.isLightRowTextColor {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { dismissKeyboardAndSearch() }
            } else {
                Color.white.opacity(0.4).ignoresSafeArea()
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { dismissKeyboardAndSearch() }
            }
            
            VStack(spacing: 0) {
                HStack { Spacer() }.frame(height: 35)
                
                filterChipsViewForSearch
                    .padding(.bottom, 20)
                
                if searchVM.isLoading {
                    ProgressView()
                        .padding(14)
                        .progressViewStyle(CircularProgressViewStyle(tint: effectManager.currentGlobalAccentColor))
                }
                
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        if displayedSearchResults.isEmpty && !searchVM.isLoading {
                            Text("No results found.")
                                .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.8))
                                .padding(.top, 50)
                        } else {
                            ForEach(displayedSearchResults) { item in
                                Button(action: { add(exercise: item) }) {
                                    HStack {
                                        if item.isFavorite {
                                            Image(systemName: "star.fill").foregroundColor(.yellow)
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
            HStack(spacing: 10) {
                Button(action: { withAnimation(.easeInOut) { searchVM.isFavoritesModeActive.toggle() } }) {
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
                
                ForEach(allMuscleGroups) { group in
                    muscleChipButton(for: group)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 5)
        }
        .transition(.opacity.animation(.easeInOut))
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
    
    private var gallerySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gallery")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            
            VStack { galleryGrid }
                .padding()
                .glassCardStyle(cornerRadius: 20)
        }
    }
    
    private var galleryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
            ForEach(Array(galleryData.enumerated()), id: \.offset) { index, data in
                if let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable().scaledToFill()
                        .frame(width: 80, height: 80).clipped().cornerRadius(8)
                        .onLongPressGesture { tappedIndex = index; showPopover = true }
                        .popover(isPresented: popoverBinding(for: index),
                                 attachmentAnchor: .rect(.bounds),
                                 arrowEdge: .bottom) {
                            galleryPopoverContent(for: index, data: data)
                        }
                }
            }
            
            let color = effectManager.currentGlobalAccentColor
            PhotosPicker(selection: $newGalleryItems, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(style: .init(lineWidth: 1, dash: [4]))
                        .frame(width: 80, height: 80)
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                }
                .foregroundColor(color)
            }
            .onChange(of: newGalleryItems, handleNewGalleryItems)
        }
    }
    
    private func galleryPopoverContent(for index: Int, data: Data) -> some View {
        HStack(spacing: 0) {
            Button("Set as main") { photoData = data; showPopover = false }
                .frame(maxWidth: .infinity)
            Divider()
            Button("Change") { replaceAtIndex = index; showPopover = false; showReplacePicker = true }
                .frame(maxWidth: .infinity)
            Divider()
            Button(role: .destructive) {
                galleryData.remove(at: index); showPopover = false
            } label: { Text("Remove") }
                .frame(maxWidth: .infinity)
        }
        .font(.footnote)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minWidth: 300)
        .presentationCompactAdaptation(.none)
    }
    
    // MARK: - Reusable Subviews
    private var photoPicker: some View {
        let imageData = photoData
        let color = effectManager.currentGlobalAccentColor
        
        return PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Group {
                if let data = imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else {
                    ZStack {
                        Circle().fill(color.opacity(0.1))
                        Image(systemName: "dumbbell.fill")
                            .resizable().scaledToFit()
                            .frame(width: 80, height: 80)
                            .foregroundStyle(color.opacity(0.6))
                    }
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    photoData = data
                }
            }
        }
    }
    
    private var descriptionEditor: some View {
        ZStack(alignment: .topLeading) {
            if description.isEmpty {
                Text("Workout notes, instructions, etc.")
                    .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6))
                    .padding(.horizontal, 3).padding(.vertical, 8)
            }
            TextEditor(text: $description)
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
        }
    }
    
    @ViewBuilder
    private var bottomSheetPanel: some View {
        ZStack(alignment: .bottom) {
            (effectManager.isLightRowTextColor ? Color.black.opacity(0.4) : Color.white.opacity(0.4))
                .ignoresSafeArea()
                .onTapGesture { withAnimation { openMenu = .none } }
            
            VStack(spacing: 8) {
                HStack {
                    Text("Select Prompts").font(.headline).foregroundColor(effectManager.currentGlobalAccentColor)
                    Spacer()
                    Button("Done") { withAnimation { openMenu = .none } }
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
            .frame(maxHeight: UIScreen.main.bounds.height * 0.85)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .zIndex(1)
        .transition(.move(edge: .bottom).animation(.easeInOut(duration: 0.3)))
    }
    
    @ViewBuilder
    private var dropDownLayer: some View {
        let workoutPrompts = allPrompts.filter { $0.type == .workout }
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
    
    private func saveSelectedPromptIDs(_ ids: Set<UUID>) {
        let idStrings = ids.map { $0.uuidString }
        UserDefaults.standard.set(idStrings, forKey: selectedPromptsKey)
    }
    
    private func loadSelectedPromptIDs() {
        guard let idStrings = UserDefaults.standard.stringArray(forKey: selectedPromptsKey) else { return }
        let ids = idStrings.compactMap { UUID(uuidString: $0) }
        self.selectedPromptIDs = Set(ids)
    }
    
    
    private func recalculateAndValidateMinAge() {
        let requiredMinAge = editableExercises.compactMap { $0.exercise.minimalAgeMonths }.max() ?? 0
        self.calculatedMinAge = requiredMinAge
        
        let currentUserAge = Int(minimalAgeMonthsTxt) ?? 0
        
        if currentUserAge < requiredMinAge || (minimalAgeMonthsTxt.isEmpty && requiredMinAge > 0) {
            minimalAgeMonthsTxt = String(requiredMinAge)
        }
    }
    
    private func validateMinAgeOnBlur() {
        let currentUserAge = Int(minimalAgeMonthsTxt) ?? 0
        if currentUserAge < calculatedMinAge {
            minimalAgeMonthsTxt = String(calculatedMinAge)
        }
    }
    
    // MARK: - Logic & Actions
    // --- НАЧАЛО НА КОРЕКЦИЯТА: Добавяме `setupExercises` ---
    private func setupExercises() {
        guard let workout = workoutToEdit, editableExercises.isEmpty else { return }
        
        if let links = workout.exercises {
            let editable = links.compactMap { link -> EditableExerciseLink? in
                guard let ex = link.exercise else { return nil }
                return EditableExerciseLink(exercise: ex, durationMinutes: link.durationMinutes)
            }
            self.editableExercises = editable
        }
    }
    // --- КРАЙ НА КОРЕКЦИЯТА ---
    
    private func setupOnce() {
        // --- НАЧАЛО НА КОРЕКЦИЯТА: Извикваме `setupExercises` тук ---
        setupExercises()
        // --- КРАЙ НА КОРЕКЦИЯТА ---
        
        searchVM.attach(context: modelContext)
        searchVM.query = globalSearchText
        searchVM.workoutFilterMode = .excludeWorkouts
        updateSearchExclusions()
        recalculateAndValidateMinAge()
    }
    
    private func dismissKeyboardAndSearch() {
        isSearchFieldFocused = false
        globalSearchText = ""
        onDismissSearch()
    }
    
    private func updateSearchExclusions() {
        let excluded = Set(editableExercises.map { $0.exercise })
        searchVM.exclude(excluded)
    }
    
    private func add(exercise: ExerciseItem) {
        let newLink = EditableExerciseLink(
            exercise: exercise,
            durationMinutes: Double(exercise.durationMinutes ?? 15)
        )
        withAnimation {
            editableExercises.append(newLink)
        }
        dismissSearchOverlay()
        scrollToExerciseID = newLink.id
        updateSearchExclusions()
    }
    
    private func dismissSearchOverlay() {
        isSearchFieldFocused = false
        globalSearchText = ""
    }
    private func delete(exerciseLink: EditableExerciseLink) {
        withAnimation {
            editableExercises.removeAll { $0.id == exerciseLink.id }
        }
        updateSearchExclusions()
    }
    
    private func saveWorkout() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            alertMessage = "Workout name cannot be empty."
            showAlert = true
            return
        }
        
        Task {
            isSaving = true
            await Task.yield()
            
            let itemToSave: ExerciseItem
            if let existing = workoutToEdit {
                itemToSave = existing
            } else {
                var desc = FetchDescriptor<ExerciseItem>(sortBy: [SortDescriptor(\.id, order: .reverse)])
                desc.fetchLimit = 1
                let maxID = (try? modelContext.fetch(desc).first?.id) ?? 0
                itemToSave = ExerciseItem(id: maxID + 1, name: "", muscleGroups: [])
                modelContext.insert(itemToSave)
            }
            
            itemToSave.name = trimmedName
            itemToSave.exerciseDescription = description.trimmingCharacters(in: .whitespaces).nilIfEmpty()
            itemToSave.photo = photoData
            itemToSave.isWorkout = true
            
            itemToSave.minimalAgeMonths = Int(minimalAgeMonthsTxt) ?? 0
            
            itemToSave.videoURL = videoURL.trimmingCharacters(in: .whitespaces).nilIfEmpty()
            
            itemToSave.metValue = averageMET
            itemToSave.durationMinutes = Int(totalDuration)
            
            itemToSave.muscleGroups = aggregatedMuscleGroups
            itemToSave.sports = aggregatedSports
            
            if itemToSave.gallery == nil { itemToSave.gallery = [] }
            itemToSave.gallery?.removeAll { photo in !galleryData.contains(photo.data) }
            for data in galleryData {
                if !(itemToSave.gallery?.contains(where: { $0.data == data }) ?? false) {
                    let newPhoto = ExercisePhoto(data: data)
                    itemToSave.gallery?.append(newPhoto)
                }
            }
            
            if let oldLinks = itemToSave.exercises {
                for link in oldLinks {
                    modelContext.delete(link)
                }
            }
            itemToSave.exercises = []
            for e in editableExercises {
                let link = ExerciseLink(exercise: e.exercise, durationMinutes: e.durationMinutes, owner: itemToSave)
                modelContext.insert(link)
                itemToSave.exercises?.append(link)
            }
            
            do {
                try modelContext.save()
                onDismiss(itemToSave)
            } catch {
                alertMessage = "Failed to save workout: \(error.localizedDescription)"
                showAlert = true
                isSaving = false
            }
        }
    }
    
    private func handleNewGalleryItems(_: [PhotosPickerItem], items: [PhotosPickerItem]) {
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run { galleryData.append(data) }
                }
            }
            await MainActor.run { newGalleryItems.removeAll() }
        }
    }
    
    private func handleReplacementItemChange(_: PhotosPickerItem?, item: PhotosPickerItem?) {
        guard let idx = replaceAtIndex, let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run { galleryData[idx] = data }
            }
            await MainActor.run {
                replacementItem = nil
                replaceAtIndex  = nil
            }
        }
    }
    
    private func popoverBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { showPopover && tappedIndex == index },
            set: { showPopover = $0 }
        )
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
    
    private func handleAITap() {
        
        guard ensureAIAvailableOrShowMessage() else { return }
        
        focusedField = nil
        hasUserMadeEdits = false
        
        triggerAIGenerationToast()
        
        let promptTexts = allPrompts.filter { selectedPromptIDs.contains($0.id) }.map { $0.text }
        
        if let newJob = aiManager.startWorkoutGeneration(
            for: self.profile,
            prompts: promptTexts,
            jobType: .workoutGeneration
        ) {
            self.runningGenerationJobID = newJob.id
        } else {
            alertMessage = "Could not start AI workout generation job."
            showAlert = true
            toastTimer?.invalidate()
            toastTimer = nil
            withAnimation { showAIGenerationToast = false }
        }
    }
    
    @MainActor
    private func populateFromCompletedJob(jobID: UUID) async {
        guard let job = aiManager.jobs.first(where: { $0.id == jobID }),
              let resultData = job.resultData else {
            alertMessage = "Could not find the completed AI job data."
            showAlert = true
            runningGenerationJobID = nil
            return
        }
        
        guard let payload = try? JSONDecoder().decode(ResolvedWorkoutResponseDTO.self, from: resultData) else {
            alertMessage = "Could not decode the generated workout data."
            showAlert = true
            runningGenerationJobID = nil
            await aiManager.deleteJob(byID: jobID)
            return
        }
        
        var newExercises: [EditableExerciseLink] = []
        let exerciseIDs = payload.exercises.map { $0.exerciseID }
        if !exerciseIDs.isEmpty {
            let descriptor = FetchDescriptor<ExerciseItem>(predicate: #Predicate { exerciseIDs.contains($0.id) })
            if let fetchedItems = try? modelContext.fetch(descriptor) {
                let itemMap = Dictionary(uniqueKeysWithValues: fetchedItems.map { ($0.id, $0) })
                for entry in payload.exercises {
                    if let exerciseItem = itemMap[entry.exerciseID] {
                        newExercises.append(EditableExerciseLink(exercise: exerciseItem, durationMinutes: entry.durationMinutes))
                    }
                }
            }
        }
        
        withAnimation(.easeInOut) {
            self.name = payload.name
            self.description = payload.description
            self.editableExercises = newExercises.sorted { $0.exercise.name < $1.exercise.name }
            self.recalculateAndValidateMinAge()
            self.updateSearchExclusions()
        }
        
        toastTimer?.invalidate()
        toastTimer = nil
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
                    Text("Generating Workout...").fontWeight(.bold)
                    Text("AI is creating your workout. You'll be notified.").font(.caption)
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
                .buttonStyle(.borderless).foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
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
        withAnimation { showAIGenerationToast = true }
        
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
    
    private func ensureAIAvailableOrShowMessage() -> Bool {
        switch GlobalState.aiAvailability {
        case .available:
            return true
        case .deviceNotEligible:
            alertMessage = "This device doesn’t support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            alertMessage = "Apple Intelligence is turned off. Enable it in Settings to use AI exercise generation."
        case .modelNotReady:
            alertMessage = "The model is downloading or preparing. Please try again in a bit."
        case .unavailableUnsupportedOS:
            alertMessage = "Apple Intelligence requires iOS 26 or newer. Update your OS to use this feature."
        case .unavailableOther:
            alertMessage = "Apple Intelligence is currently unavailable for an unknown reason."
        }
        showAlert = true
        return false
    }
}

private extension WorkoutEditorView.OpenMenu {
    var title: String {
        switch self {
        case .none: return ""
        case .promptSelector: return "Prompts"
        }
    }
}


fileprivate struct EditableExerciseRow: View {
    @ObservedObject private var effectManager = EffectManager.shared

    @Binding var link: WorkoutEditorView.EditableExerciseLink
    var onDelete: () -> Void
    @FocusState.Binding var focusedField: WorkoutEditorView.FocusableField?
    let focusCase: WorkoutEditorView.FocusableField

    @State private var textValue: String

    init(link: Binding<WorkoutEditorView.EditableExerciseLink>,
         onDelete: @escaping () -> Void,
         focusedField: FocusState<WorkoutEditorView.FocusableField?>.Binding,
         focusCase: WorkoutEditorView.FocusableField) {
        self._link = link
        self.onDelete = onDelete
        self._focusedField = focusedField
        self.focusCase = focusCase
        self._textValue = State(initialValue: String(format: "%.0f", link.wrappedValue.durationMinutes))
    }

    var body: some View {
        HStack {
            Text(link.exercise.name)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                ConfigurableTextField(
                    title: "min",
                    value: $textValue,
                    type: .integer,
                    placeholderColor: effectManager.currentGlobalAccentColor.opacity(0.6),
                    focused: $focusedField,
                    fieldIdentifier: focusCase
                )
                .multilineTextAlignment(.trailing)
                .fixedSize()
                .foregroundStyle(effectManager.currentGlobalAccentColor)

                Text("min")
                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .glassCardStyle(cornerRadius: 20)
        .onChange(of: textValue) { _, newText in
            if let newDuration = Double(newText) {
                link.durationMinutes = newDuration
            } else if newText.isEmpty {
                link.durationMinutes = 0
            }
        }
        .onChange(of: link.durationMinutes) { _, newDuration in
            let currentTextAsDouble = Double(textValue) ?? 0.0
            if abs(currentTextAsDouble - newDuration) > 0.1 {
                textValue = String(format: "%.0f", newDuration)
            }
        }
        .onChange(of: focusedField) { _, newFocus in
            if newFocus != focusCase {
                let clampedDuration = max(1, min(link.durationMinutes, 999))
                textValue = String(format: "%.0f", clampedDuration)
                link.durationMinutes = clampedDuration
            }
        }
    }
}
