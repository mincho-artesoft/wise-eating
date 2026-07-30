import SwiftUI
import SwiftData
import Combine
import PhotosUI

@MainActor
struct AddEditDietView: View {
    @State private var pendingAIJobIDToDeleteOnSave: UUID? = nil
    // MARK: - AI State
    @ObservedObject private var aiManager = AIManager.shared
    @State private var hasUserMadeEdits: Bool = false
    @State private var runningGenerationJobID: UUID? = nil
    @State private var showAIGenerationToast = false
    @State private var toastTimer: Timer? = nil
    @State private var toastProgress: Double = 0.0
    @State private var isBannerAdLoaded: Bool = false
    @Query private var userSettingsArray: [UserSettings]   // 👈 ДОБАВИ ТОВА
    @Query(sort: \Prompt.creationDate, order: .reverse) private var allPrompts: [Prompt]
    @State private var selectedPromptIDs: Set<Prompt.ID> = []
    private var isAIButtonEnabledGlobally: Bool {
        userSettingsArray.first?.isAIButtonEnabled ?? true
    }
    private enum OpenMenu { case none, promptSelector }
    @State private var openMenu: OpenMenu = .none
    @State private var isAITapOnCooldown: Bool = false
    @State private var promptToDelete: Prompt? = nil
    @State private var isShowingDeletePromptConfirmation = false
    
    private let selectedPromptsKey = "AddEditDietView_SelectedPrompts"
    
    @State private var path = NavigationPath()
    private enum NavigationTarget: Hashable {
        case promptEditor
        case editPrompt(Prompt)
    }
    
    @State private var isAIButtonVisible: Bool = true
    @State private var aiButtonOffset: CGSize = .zero
    @State private var aiIsDragging: Bool = false
    @GestureState private var aiGestureDragOffset: CGSize = .zero
    @State private var aiIsPressed: Bool = false
    private let aiButtonPositionKey = "floatingDietAIButtonPosition"
    
    // MARK: - Env & Deps
    @ObservedObject private var effectManager = EffectManager.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Input
    let dietToEdit: Diet?
    let onDismiss: (Diet?) -> Void
    
    // Глобален сърч (общ с горната лента)
    @Binding var globalSearchText: String
    @FocusState.Binding var isSearchFieldFocused: Bool
    let onDismissSearch: () -> Void
    
    // MARK: - UI State
    @State private var name: String = ""
    @FocusState private var isNameFieldFocused: Bool
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    // Работна диета: при EDIT -> сочи към съществуващата; при NEW -> nil (създаваме на Save)
    @State private var workingDiet: Diet?
    
    // STAGING: локално копие на храните за тази сесия (НЕ пипа модела, докато не натиснем Save)
    @State private var stagingFoods: [FoodItem] = []
    @State private var originalNameSnapshot: String = ""
    
    @Query(sort: \Vitamin.name)  private var allVitamins: [Vitamin]
    @Query(sort: \Mineral.name)  private var allMinerals: [Mineral]
    @Query(sort: \Diet.name) private var allDiets: [Diet]
    
    // MARK: - Helpers
    private var isEditing: Bool { dietToEdit != nil }
    private var isDefaultDiet: Bool { dietToEdit?.isDefault == true }
    private var navigationTitle: String { isEditing ? "Edit Diet" : "Add New Diet" }
    private var isSaveDisabled: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Нова диета: изисква име; При edit позволяваме празно? – тук пазим твоята логика:
        if !isEditing { return trimmed.isEmpty }
        if isDefaultDiet { return false }
        return trimmed.isEmpty
    }
    
    @State var profile: Profile?
    @State private var wireDTOToFetch: AIDietResponseWireDTO?
    
    // MARK: - Init
    init(
        dietToEdit: Diet?,
        profile: Profile?,
        onDismiss: @escaping (Diet?) -> Void,
        globalSearchText: Binding<String>,
        isSearchFieldFocused: FocusState<Bool>.Binding,
        onDismissSearch: @escaping () -> Void
    ) {
        self.profile = profile
        self.dietToEdit = dietToEdit
        self.onDismiss  = onDismiss
        _name = State(initialValue: dietToEdit?.name ?? "")
        self._globalSearchText = globalSearchText
        self._isSearchFieldFocused = isSearchFieldFocused
        self.onDismissSearch = onDismissSearch
    }
    
    init(
        dto: AIDietResponseDTO,
        profile: Profile?,
        onDismiss: @escaping (Diet?) -> Void,
        globalSearchText: Binding<String>,
        isSearchFieldFocused: FocusState<Bool>.Binding,
        onDismissSearch: @escaping () -> Void
    ) {
        self.init(
            dietToEdit: nil,
            profile: profile,
            onDismiss: onDismiss,
            globalSearchText: globalSearchText,
            isSearchFieldFocused: isSearchFieldFocused,
            onDismissSearch: onDismissSearch
        )
        _name = State(initialValue: dto.suggestedName)
        _stagingFoods = State(initialValue: dto.foodItemIDs.sorted { $0.name < $1.name })
    }
    
    init(
        wireDTO: AIDietResponseWireDTO,
        profile: Profile?,
        onDismiss: @escaping (Diet?) -> Void,
        globalSearchText: Binding<String>,
        isSearchFieldFocused: FocusState<Bool>.Binding,
        onDismissSearch: @escaping () -> Void
    ) {
        self.init(
            dietToEdit: nil,
            profile: profile,
            onDismiss: onDismiss,
            globalSearchText: globalSearchText,
            isSearchFieldFocused: isSearchFieldFocused,
            onDismissSearch: onDismissSearch
        )
        _name = State(initialValue: wireDTO.suggestedName)
        _wireDTOToFetch = State(initialValue: wireDTO)
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ThemeBackgroundView().ignoresSafeArea()
                
                VStack(spacing: 0) {
                    toolbar
                        .padding(.horizontal)
                    
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            nameCard
                            bannerAdSection
                                .frame(height: isBannerAdLoaded ? 120 : 0)
                            // Секция за промптове
                            if GlobalState.aiAvailability != .deviceNotEligible && isAIButtonEnabledGlobally{
                                VStack(spacing: 12) {
                                    let dietPrompts = allPrompts.filter { $0.type == .diet }
                                    if !dietPrompts.isEmpty {
                                        promptsSection
                                            .padding(.horizontal)
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
                                    .padding(.horizontal)
                                }
                                .padding(.vertical)
                                .glassCardStyle(cornerRadius: 20)
                            }
                            foodsCard
                        }
                        .padding()
                    }
                }
                
                // +++ НАЧАЛО НА ПРОМЯНАТА: Използваме FoodSearchPanelView вместо ръчен панел +++
                if isSearchFieldFocused {
                    let focusBinding = Binding<Bool>(
                        get: { isSearchFieldFocused },
                        set: { isSearchFieldFocused = $0 }
                    )
                    
                    // Изчисляваме ID-тата, които да скрием (тези, които вече са в stagingFoods)
                    let excludedIDs = Set(stagingFoods.map { $0.id })
                    
                    FoodSearchPanelView(
                        globalSearchText: $globalSearchText,
                        isSearchFieldFocused: focusBinding,
                        profile: profile,
                        searchMode: .diets, // Или .recipes/.menus ако искате да ограничите
                        showFavoritesFilter: true,
                        showRecipesFilter: true,
                        showMenusFilter: true,
                        headerRightText: nil,
                        excludedFoodIDs: excludedIDs, // <-- ТУК става магията
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
            }
            .overlay {
                GeometryReader { geometry in
                    Group {
                        if showAIGenerationToast {
                            aiGenerationToast
                        }
                        if !isSearchFieldFocused &&
                            !showAlert &&
                            openMenu == .none &&
                            GlobalState.aiAvailability != .deviceNotEligible &&
                            isAIButtonEnabledGlobally{
                            AIButton(geometry: geometry)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .task {
                if let dto = wireDTOToFetch {
                    await populateFromWireDTO(dto)
                    wireDTOToFetch = nil
                }
            }
            .onAppear {
                setupOnce()
                loadAIButtonPosition()
                loadSelectedPromptIDs()
            }
            .onReceive(NotificationCenter.default.publisher(for: .aiDietJobCompleted)) { notification in
                guard !hasUserMadeEdits,
                      let userInfo = notification.userInfo,
                      let completedJobID = userInfo["jobID"] as? UUID,
                      completedJobID == self.runningGenerationJobID else {
                    return
                }
                print("▶️ AddEditDietView: Received .aiDietJobCompleted for job \(completedJobID). Populating data.")
                Task {
                    await populateFromCompletedJob(jobID: completedJobID)
                }
            }
            .onChange(of: name) { _, _ in hasUserMadeEdits = true }
            .onChange(of: stagingFoods) { _, _ in hasUserMadeEdits = true }
            .onChange(of: selectedPromptIDs, perform: saveSelectedPromptIDs)
            .navigationDestination(for: NavigationTarget.self) { target in
                switch target {
                case .promptEditor:
                    PromptEditorView(promptType: .diet) { newPrompt in
                        path.removeLast()
                        if let newPrompt = newPrompt {
                            selectedPromptIDs.insert(newPrompt.id)
                        }
                    }
                case .editPrompt(let prompt):
                    PromptEditorView(promptType: .diet, promptToEdit: prompt) { editedPrompt in
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
                .alert("Error", isPresented: $showAlert) {
                    Button("OK", role: .cancel) {}
                } message: { Text(alertMessage) }
        }
    }
    
    // MARK: - Setup
    private func setupOnce() {
        // EDIT: работим с копие в staging
        if let edit = dietToEdit {
            workingDiet = edit
            originalNameSnapshot = edit.name
            stagingFoods = (edit.foods ?? []).sorted { $0.name < $1.name }
        } else {
            // NEW: нямаме обект до момента на Save
            workingDiet = nil
            originalNameSnapshot = ""
            stagingFoods = []
        }
    }
    
    // MARK: - Toolbar
    private var toolbar: some View {
        HStack {
            Button("Cancel") {
                // НИЩО не сме писали в модела: просто затваряме.
                dismissKeyboardAndSearch()
                onDismiss(nil)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassCardStyle(cornerRadius: 20)
            
            Spacer()
            
            Text(navigationTitle).font(.headline)
            
            Spacer()
            
            Button("Save") { saveDiet() }
                .disabled(isSaveDisabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
                .foregroundStyle(isSaveDisabled
                                 ? effectManager.currentGlobalAccentColor.opacity(0.4)
                                 : effectManager.currentGlobalAccentColor)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding(.top, 10)
    }
    
    // MARK: - Cards
    private var nameCard: some View {
        StyledLabeledPicker(label: "Diet Name", isRequired: true) {
            TextField("",
                      text: $name,
                      prompt: Text("e.g., High-Fiber Diet")
                .foregroundColor(effectManager.currentGlobalAccentColor.opacity(0.6)))
            .font(.system(size: 16))
            .focused($isNameFieldFocused)
            .disabled(isDefaultDiet == true && isEditing)
            .onSubmit { isNameFieldFocused = false }
            .opacity((isDefaultDiet && isEditing) ? 0.7 : 1)
            .disableAutocorrection(true)
        }
    }
    
    private var foodsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Foods in this Diet")
                    .font(.headline)
                    .foregroundStyle(effectManager.currentGlobalAccentColor)
                Spacer()
            }
            
            if stagingFoods.isEmpty {
                ContentUnavailableView {
                    Label("No foods in this diet", systemImage: "fork.knife")
                } description: {
                    Text("Use the search above to add foods to this diet.")
                }
                .foregroundColor(effectManager.currentGlobalAccentColor)
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(stagingFoods) { food in
                        HStack(spacing: 12) {
                            Text(food.name)
                                .foregroundStyle(effectManager.currentGlobalAccentColor)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            
                            Spacer()
                            
                            if canRemove(food: food) {
                                Button(role: .destructive) {
                                    removeFromDiet(food)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.7))
                                        .padding(6)
                                        .glassCardStyle(cornerRadius: 10)
                                }
                                .glassCardStyle(cornerRadius: 10)
                            } else {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.7))
                                    .padding(6)
                                    .glassCardStyle(cornerRadius: 10)
                            }
                        }
                        .padding(12)
                        .glassCardStyle(cornerRadius: 20)
                    }
                    
                    Color.clear.frame(height: 150)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
    }
    
    // MARK: - Actions
    private func dismissKeyboardAndSearch() {
        isSearchFieldFocused = false
        globalSearchText = ""
    }
    
    private func addFoodItem(_ food: FoodItem) {
        // Проверка дали вече е добавена
        guard !stagingFoods.contains(where: { $0.id == food.id }) else {
            dismissKeyboardAndSearch()
            return
        }
        
        withAnimation {
            stagingFoods.append(food)
            stagingFoods.sort { $0.name < $1.name }
        }
        dismissKeyboardAndSearch()
    }
    
    private func canRemove(food: FoodItem) -> Bool {
        if isDefaultDiet { return food.isUserAdded }
        return true
    }
    
    private func removeFromDiet(_ food: FoodItem) {
        guard canRemove(food: food) else { return }
        withAnimation {
            stagingFoods.removeAll { $0.id == food.id }
        }
    }
    
    private func saveDiet() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let diet = dietToEdit {
            // DEFAULT DIET: only update foods
            if isDefaultDiet {
                diet.foods = stagingFoods
                do {
                    try modelContext.save()
                    cleanupPendingAIJobIfNeeded()
                    dismissKeyboardAndSearch()
                    onDismiss(diet)
                } catch {
                    alertMessage = "Failed to save the diet. Please try again. Error: \(error.localizedDescription)"
                    showAlert = true
                }
                return
            }
            
            // CUSTOM DIET: rename + update foods
            guard !trimmedName.isEmpty else {
                alertMessage = "The diet name cannot be empty."
                showAlert = true
                return
            }
            do {
                let existing = try modelContext.fetch(FetchDescriptor<Diet>())
                let conflict = existing.first {
                    $0.name.compare(trimmedName, options: .caseInsensitive) == .orderedSame
                    && ($0.id != diet.id)
                }
                if conflict != nil {
                    alertMessage = "A diet with this name already exists."
                    showAlert = true
                    return
                }
                diet.name = trimmedName
                diet.id   = trimmedName
                diet.foods = stagingFoods
                try modelContext.save()
                cleanupPendingAIJobIfNeeded()
                dismissKeyboardAndSearch()
                onDismiss(diet)
            } catch {
                alertMessage = "Failed to save the diet. Please try again. Error: \(error.localizedDescription)"
                showAlert = true
            }
        } else {
            // NEW DIET
            guard !trimmedName.isEmpty else {
                alertMessage = "The diet name cannot be empty."
                showAlert = true
                return
            }
            do {
                let existing = try modelContext.fetch(FetchDescriptor<Diet>())
                if existing.contains(where: { $0.name.compare(trimmedName, options: .caseInsensitive) == .orderedSame }) {
                    alertMessage = "A diet with this name already exists."
                    showAlert = true
                    return
                }
                let newDiet = Diet(name: trimmedName)
                newDiet.foods = stagingFoods
                modelContext.insert(newDiet)
                try modelContext.save()
                cleanupPendingAIJobIfNeeded()
                dismissKeyboardAndSearch()
                onDismiss(newDiet)
            } catch {
                alertMessage = "Failed to save the diet. Please try again. Error: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    private func cleanupPendingAIJobIfNeeded() {
        guard let pendingID = pendingAIJobIDToDeleteOnSave,
              let job = aiManager.jobs.first(where: { $0.id == pendingID }) else {
            return
        }
        
        // Изтриваме job-а асинхронно, за да не правим saveDiet() async
        Task {
            await aiManager.deleteJob(job)
        }
        
        pendingAIJobIDToDeleteOnSave = nil
    }
    
    // --- AI Floating Button: Helpers ---
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
                let maxY = size.height - radius - safeArea.bottom - 80
                
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
    
    /// Стартира същинската AI генерация на диета.
    /// Извиква се САМО след като потребителят вече е "платил"
    /// (с абонамент или чрез гледане на реклама).
    private func startDietAIGeneration(promptTexts: [String]) {
        hasUserMadeEdits = false
        triggerAIGenerationToast()
        
        if let newJob = aiManager.startDietGeneration(
            for: self.profile,
            prompts: promptTexts,
            jobType: .dietGeneration
        ) {
            self.runningGenerationJobID = newJob.id
        } else {
            alertMessage = "Could not start AI diet generation job."
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
        
        // 1. Проверка за наличност на AI
        guard ensureAIAvailableOrShowMessage() else { return }
        
        // 2. Проверка за избрани промптове (преди да караме потребителя да гледа реклами)
        guard !selectedPromptIDs.isEmpty else {
            alertMessage = "Please select at least one prompt for the AI."
            showAlert = true
            return
        }
        
        let promptTexts = allPrompts
            .filter { selectedPromptIDs.contains($0.id) }
            .map { $0.text }
        
        // 3. Логика за АБОНАМЕНТ / РЕКЛАМИ (както при ExerciseItemEditorView)
        
        // 3.1 Платен план – без реклами
        if !AdsConfiguration.shouldShowAds {
            print("💎 Premium user: Skipping ad.")
            startDietAIGeneration(promptTexts: promptTexts)
            return
        }
        
        // 3.2 Безплатен план – Rewarded → Interstitial → fallback
        print("📺 Free user: Checking for ads...")
        if RewardedAdManager.shared.isReady {
            print("📺 Showing Rewarded Ad for diet generation...")
            RewardedAdManager.shared.showIfAvailable { amount, type in
                // Тук влизаме САМО ако рекламата е изгледана докрай
                print("✅ Ad watched! Starting diet generation.")
                self.startDietAIGeneration(promptTexts: promptTexts)
            }
        } else if InterstitialAdManager.shared.isReady {
            print("⚠️ Rewarded not ready. Showing Interstitial fallback for diet generation...")
            InterstitialAdManager.shared.showIfAvailable {
                // Изпълнява се, когато потребителят затвори interstitial-а
                print("✅ Interstitial closed. Starting diet generation.")
                self.startDietAIGeneration(promptTexts: promptTexts)
            }
        } else {
            print("⚠️ No ads available. Proceeding graciously with diet generation.")
            // Няма реклами – пускаме AI, за да не дразним потребителя
            startDietAIGeneration(promptTexts: promptTexts)
            
            // Подготвяме реклами за следващия път
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
    
    @ViewBuilder
    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompts")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            
            let dietPrompts = allPrompts.filter { $0.type == .diet }
            
            MultiSelectButton(
                selection: $selectedPromptIDs,
                items: dietPrompts,
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
                        withAnimation { openMenu = .none }
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
                let dietPrompts = allPrompts.filter { $0.type == .diet }
                DropdownMenu(
                    selection: $selectedPromptIDs,
                    items: dietPrompts,
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
    
    private func saveSelectedPromptIDs(_ ids: Set<UUID>) {
        let idStrings = ids.map { $0.uuidString }
        UserDefaults.standard.set(idStrings, forKey: selectedPromptsKey)
    }
    
    private func loadSelectedPromptIDs() {
        guard let idStrings = UserDefaults.standard.stringArray(forKey: selectedPromptsKey) else { return }
        let ids = idStrings.compactMap { UUID(uuidString: $0) }
        self.selectedPromptIDs = Set(ids)
    }
    
    @MainActor
    private func populateFromCompletedJob(jobID: UUID) async {
        guard let job = (aiManager.jobs.first(where: { $0.id == jobID })),
              let resultData = job.resultData else {
            alertMessage = "Could not find the completed AI job (id: \(jobID))."
            showAlert = true
            runningGenerationJobID = nil
            return
        }
        
        guard !resultData.isEmpty else {
            alertMessage = "The AI job finished without data."
            showAlert = true
            runningGenerationJobID = nil
            await aiManager.deleteJob(job)   // при този кейс все още трием веднага
            return
        }
        
        struct AIDietResponseWireDTO: Codable {
            var suggestedName: String
            var foodItemIDs: [Int]
        }
        
        let payload: AIDietResponseWireDTO
        do {
            payload = try JSONDecoder().decode(AIDietResponseWireDTO.self, from: resultData)
        } catch {
            alertMessage = "Could not decode the generated diet data. \(error.localizedDescription)"
            showAlert = true
            runningGenerationJobID = nil
            await aiManager.deleteJob(job)   // при decode грешка – пак чистим
            return
        }
        
        let ids = payload.foodItemIDs
        let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { ids.contains($0.id) })
        let fetched: [FoodItem]
        do {
            fetched = try modelContext.fetch(descriptor)
        } catch {
            alertMessage = "Failed to load foods for the generated diet. \(error.localizedDescription)"
            showAlert = true
            runningGenerationJobID = nil
            await aiManager.deleteJob(job)   // при fetch грешка – чистим
            return
        }
        
        let fetchedIDs = Set(fetched.map { $0.id })
        let missing = Set(ids).subtracting(fetchedIDs)
        if !missing.isEmpty {
            print("⚠️ [AddEditDietView] Missing FoodItem IDs from DB: \(missing.sorted())")
        }
        
        withAnimation(.easeInOut) {
            self.name = payload.suggestedName
            self.stagingFoods = fetched.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        
        toastTimer?.invalidate()
        toastTimer = nil
        withAnimation { showAIGenerationToast = false }
        
        // ❗️ТУК ВЕЧЕ НЕ ТРИЕМ job-а веднага
        pendingAIJobIDToDeleteOnSave = jobID
        runningGenerationJobID = nil
    }
    
    
    private func triggerAIGenerationToast() {
        toastTimer?.invalidate()
        toastProgress = 0.0
        withAnimation { showAIGenerationToast = true }
        
        let totalDuration = 5.0
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
                Image(systemName: "sparkles")
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Generating Diet...")
                        .fontWeight(.bold)
                    Text("This may take a moment. You'll be notified.")
                        .font(.caption)
                    
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
    
    private func populateFromWireDTO(_ dto: AIDietResponseWireDTO) async {
        let ids = dto.foodItemIDs
        guard !ids.isEmpty else { return }
        
        let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { ids.contains($0.id) })
        do {
            let fetched = try modelContext.fetch(descriptor)
            self.stagingFoods = fetched.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            alertMessage = "Failed to load foods for the generated diet: \(error.localizedDescription)"
            showAlert = true
        }
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
    
    @ViewBuilder
    private var bannerAdSection: some View {
        // Показваме банер само за free (Base) потребители
        if AdsConfiguration.shouldShowAds {
            BannerAdView(adsBool: $isBannerAdLoaded, bucket: .large)
                .frame(height: 120)
                .opacity(isBannerAdLoaded ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: isBannerAdLoaded)
                .padding(.horizontal)
        }
    }
}
