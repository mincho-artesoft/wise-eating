import SwiftUI
import SwiftData

struct AIDailyMealGeneratorView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var effectManager = EffectManager.shared
    @ObservedObject private var aiManager = AIManager.shared
    @Query private var userSettingsArray: [UserSettings]   // 👈 ДОБАВИ ТОВА
    private var isAIButtonEnabledGlobally: Bool {
        userSettingsArray.first?.isAIButtonEnabled ?? true
    }
    @State private var isAITapOnCooldown: Bool = false
    
    // MARK: - Input
    let profile: Profile
    let date: Date
    let onJobScheduled: () -> Void
    let onDismiss: () -> Void
    
    // MARK: - State
    @State private var selectedMealNames: Set<String>
    @State private var mealsForDay: [Meal]
    
    // MARK: - Prompt State & Navigation
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
    private let selectedPromptsKey = "AIDailyMealGenerator_SelectedPrompts"
    
    // --- AI Floating Button State ---
    @State private var isAIButtonVisible: Bool = true
    @State private var aiButtonOffset: CGSize = .zero
    @State private var aiIsDragging: Bool = false
    @GestureState private var aiGestureDragOffset: CGSize = .zero
    @State private var aiIsPressed: Bool = false
    private let aiButtonPositionKey = "floatingDailyAIGenButtonPosition"
    
    // --- Toast Notification State ---
    @State private var showAIGenerationToast = false
    @State private var toastTimer: Timer? = nil
    @State private var toastProgress: Double = 0.0
    
    init(profile: Profile, date: Date, meals: [Meal]?, onJobScheduled: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.profile = profile
        self.date = date
        self.onJobScheduled = onJobScheduled
        self.onDismiss = onDismiss
        
        let mealsForDisplay: [Meal]
        if let providedMeals = meals, !providedMeals.isEmpty {
            mealsForDisplay = providedMeals.sorted { $0.startTime < $1.startTime }
        } else {
            mealsForDisplay = profile.meals(for: date)
        }
        
        self._mealsForDay = State(initialValue: mealsForDisplay)
        self._selectedMealNames = State(initialValue: Set(mealsForDisplay.map { $0.name }))
    }
    
    private var isAIButtonCurrentlyVisible: Bool {
        !showAIGenerationToast &&
        openMenu == .none &&
        isAIButtonEnabledGlobally          // 👈 ГЛОБАЛЕН ФЛАГ
    }
    
    
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ThemeBackgroundView().ignoresSafeArea()
                
                VStack(spacing: 0) {
                    toolbar
                    
                    ScrollView(showsIndicators: false) {
                        mainContent
                    }
                }
            }
            .overlay {
                GeometryReader { geometry in
                    Group {
                        if isAIButtonCurrentlyVisible {
                            AIButton(geometry: geometry)
                        }
                        if showAIGenerationToast {
                            aiGenerationToast
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
            .onAppear(perform: loadSelectedPromptIDs)
            .onAppear(perform: loadAIButtonPosition)
            .onChange(of: selectedPromptIDs, perform: saveSelectedPromptIDs)
            .navigationDestination(for: NavigationTarget.self) { target in
                switch target {
                case .promptEditor:
                    PromptEditorView(promptType: .nutritionsDetailМealPlan) { newPrompt in
                        path.removeLast()
                        if let newPrompt = newPrompt {
                            selectedPromptIDs.insert(newPrompt.id)
                        }
                    }
                    
                case .editPrompt(let prompt):
                    PromptEditorView(promptType: .nutritionsDetailМealPlan, promptToEdit: prompt) { editedPrompt in
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
        .task {
            if #available(iOS 26.0, *) {
                USDAWeeklyMealPlanner.prewarmIntentModel()
            }
        }
    }
    
    private var toolbar: some View {
        HStack {
            Button("Cancel", action: onDismiss)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassCardStyle(cornerRadius: 20)
            
            Spacer()
            Text("Generate Daily Meals").font(.headline)
            Spacer()
            
            Button("Cancel") {}.hidden()
                .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding()
    }
    
    private var mainContent: some View {
        VStack(spacing: 20) {
            let mealPlanPrompts = allPrompts.filter { $0.type == .nutritionsDetailМealPlan }
            if GlobalState.aiAvailability != .deviceNotEligible && isAIButtonEnabledGlobally{
                VStack(spacing: 12) {
                    if !mealPlanPrompts.isEmpty {
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
            VStack(spacing: 12) {
                ForEach(mealsForDay) { meal in
                    mealSelectionCard(for: meal)
                }
            }
            .padding()
        }
        .padding()
    }
    
    @ViewBuilder
    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompts")
                .font(.headline)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            
            let mealPlanPrompts = allPrompts.filter { $0.type == .nutritionsDetailМealPlan }
            
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
        let mealPlanPrompts = allPrompts.filter { $0.type == .nutritionsDetailМealPlan }
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
    
    @ViewBuilder
    private func mealSelectionCard(for meal: Meal) -> some View {
        let isSelected = selectedMealNames.contains(meal.name)
        
        // Създаваме съдържанието като HStack
        HStack {
            VStack(alignment: .leading) {
                Text(meal.name)
                    .font(.headline)
                Text("\(meal.startTime.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .opacity(0.8)
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
        }
        // Прилагаме всички стилове към HStack
        .padding()
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .glassCardStyle(cornerRadius: 15)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(isSelected ? effectManager.currentGlobalAccentColor : .clear, lineWidth: 2)
        )
        // Казваме на SwiftUI, че цялата правоъгълна форма на този HStack трябва да е кликаема
        .contentShape(Rectangle())
        // Добавяме действието при докосване
        .onTapGesture {
            withAnimation(.spring()) {
                if isSelected {
                    selectedMealNames.remove(meal.name)
                } else {
                    selectedMealNames.insert(meal.name)
                }
            }
        }
    }
    
    private func generateAndDismiss() {
        guard !selectedMealNames.isEmpty else { return }
        
        let daysAndMeals: [Int: [String]] = [1: Array(selectedMealNames)]
        let selectedPrompts = allPrompts.filter { selectedPromptIDs.contains($0.id) }.map { $0.text }
        
        // +++ НАЧАЛО НА ПРОМЯНАТА +++
        // Създаваме речник с имената на храненията и техните начални часове.
        let mealTimings = Dictionary(uniqueKeysWithValues: mealsForDay.compactMap { meal in
            return (meal.name, meal.startTime)
        })
        
        // Подаваме новия речник към мениджъра.
        if aiManager.startPlanFill(for: profile, daysAndMeals: daysAndMeals, existingMeals: [:], selectedPrompts: selectedPrompts.isEmpty ? nil : selectedPrompts, mealTimings: mealTimings, jobType: .dailyMealPlan) != nil {
            triggerAIGenerationToast()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onJobScheduled()
                onDismiss()
            }
        } else {
            print("❌ Failed to start AI generation job from daily generator.")
            onDismiss()
        }
        // +++ КРАЙ НА ПРОМЯНАТА +++
    }
    
    private func aiBottomPadding(for geometry: GeometryProxy) -> CGFloat {
        let size = geometry.size
        guard size.width > 0 else { return 75 }
        let aspectRatio = size.height / size.width
        return aspectRatio > 1.9 ? 75 : 95
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
        
        // Ако няма избрани хранения – няма какво да генерираме
        guard !selectedMealNames.isEmpty else { return }
        
        // 1) Платен план – без реклами
        if !AdsConfiguration.shouldShowAds {
            print("💎 Premium user: Skipping ad for daily meal generation.")
            generateAndDismiss()
            return
        }
        
        // 2) Безплатен план – Rewarded → Interstitial → fallback
        print("📺 Free user: Checking for ads for daily meal generation...")
        if RewardedAdManager.shared.isReady {
            print("📺 Showing Rewarded Ad for daily meal generation...")
            RewardedAdManager.shared.showIfAvailable { amount, type in
                // Влизаме тук САМО ако рекламата е изгледана докрай
                print("✅ Ad watched! Starting daily meal generation.")
                self.generateAndDismiss()
            }
        } else if InterstitialAdManager.shared.isReady {
            print("⚠️ Rewarded not ready. Showing Interstitial fallback for daily meal generation...")
            InterstitialAdManager.shared.showIfAvailable {
                // Изпълнява се, когато потребителят затвори interstitial-а
                print("✅ Interstitial closed. Starting daily meal generation.")
                self.generateAndDismiss()
            }
        } else {
            print("⚠️ No ads available. Proceeding graciously with daily meal generation.")
            // Няма реклами – да не дразним потребителя
            generateAndDismiss()
            
            // Зареждаме реклами за следващия път
            Task {
                await RewardedAdManager.shared.loadAd()
                await InterstitialAdManager.shared.loadAd()
            }
        }
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
    
    private func saveSelectedPromptIDs(_ ids: Set<UUID>) {
        let idStrings = ids.map { $0.uuidString }
        UserDefaults.standard.set(idStrings, forKey: selectedPromptsKey)
    }
    
    private func loadSelectedPromptIDs() {
        guard let idStrings = UserDefaults.standard.stringArray(forKey: selectedPromptsKey) else { return }
        let ids = idStrings.compactMap { UUID(uuidString: $0) }
        self.selectedPromptIDs = Set(ids)
    }
}
