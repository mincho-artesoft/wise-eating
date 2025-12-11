// ==== FILE: /Users/aleksandarsvinarov/Desktop/as/vitahealth-clean/WiseEating/AI/Views/AIGenerationHostView.swift ====
import SwiftUI
import SwiftData
import UIKit

/// A host view that displays the status and results of AI generation jobs.
struct AIGenerationHostView: View {
    let profile: Profile
    @State private var aiAvailabilityLocal: GlobalState.AIAvailabilityStatus = GlobalState.aiAvailability
    
    @ObservedObject private var effectManager = EffectManager.shared
    @ObservedObject private var aiManager = AIManager.shared
    @ObservedObject private var coordinator = NavigationCoordinator.shared
    @Environment(\.modelContext) private var modelContext
    
    // 🔑 Drive the UI from SwiftData directly
    @Query(
        FetchDescriptor<AIGenerationJob>(
            sortBy: [SortDescriptor(\.creationDate, order: .reverse)]
        )
    )
    private var jobs: [AIGenerationJob]
    
    // 🔑 Извличаме глобалните настройки
    @Query private var userSettingsList: [UserSettings]
    
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @State private var currentTimeString: String = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let tFmt = DateFormatter.shortTime
    @State private var hasUnreadNotifications: Bool = false
    
    private var headerTopPadding: CGFloat {
        -safeAreaInsets.top + 10
    }
    
    private var activeJobsCount: Int {
        jobs.filter { $0.status == .pending || $0.status == .running }.count
    }
    
    @State private var jobToDelete: AIGenerationJob? = nil
    @State private var isShowingDeleteJobConfirmation: Bool = false
    
    // MARK: - New Tab State
    private enum AITab: String, CaseIterable, Identifiable {
        case history = "History"
        case settings = "AI Settings"
        var id: String { rawValue }
    }
    
    @State private var selectedAITab: AITab = .history
    
    /// Проверка дали устройството изобщо поддържа AI
    private var deviceSupportsAI: Bool {
        return aiAvailabilityLocal != .deviceNotEligible &&
               aiAvailabilityLocal != .unavailableUnsupportedOS
    }
    
    var body: some View {
        VStack(spacing: 0) {
            userToolbar(for: profile)
                .padding(.trailing, 50)
                .padding(.leading, 40)
                .padding(.horizontal, -20)
                .padding(.bottom, 8)
            
            UpdatePlanBanner()
            
            toolbar
            
            // Segmented Control
            if deviceSupportsAI {
                WrappingSegmentedControl(selection: $selectedAITab, layoutMode: .wrap)
                    .padding(.bottom, 10)
            }
            
            // Switch между History и Settings
            if selectedAITab == .history {
                historyContent
                    .transition(.opacity)
            } else {
                settingsContent
                    .transition(.opacity)
            }
        }
        .padding(.top, headerTopPadding)
        .onReceive(timer) { _ in
            self.currentTimeString = Self.tFmt.string(from: Date())
        }
        .task {
            await checkForUnreadNotifications()
        }
        // ... (останалите onReceive/task манипулатори се запазват както са в оригиналния код) ...
        .confirmationDialog(
            "Delete this job?",
            isPresented: $isShowingDeleteJobConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let job = jobToDelete else { return }
                Task { await aiManager.deleteJob(job) }
                jobToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                jobToDelete = nil
            }
        } message: {
            Text("This will remove the job from your history. This action cannot be undone.")
        }
    }
    
    // MARK: - Subviews
    
    private var toolbar: some View {
        HStack {
            Text("AI Generation Jobs (Demo)")
                .font(.title.bold())
                .foregroundColor(effectManager.currentGlobalAccentColor)
            
            Spacer()
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding()
    }
    
    // ИЗНЕСЕНО: Съдържанието на History таба
    @ViewBuilder
    private var historyContent: some View {
        if jobs.isEmpty {
            // ... (кодът за празното състояние се запазва непроменен) ...
            ContentUnavailableView(
                "No AI Generation History",
                systemImage: "sparkles",
                description: Text("Tap the ✨ button on diet or training screens to start a new generation.")
            )
            .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
        } else {
            List {
                let items = jobs
                
                ForEach(Array(items.enumerated()), id: \.element.id) { index, job in
                    // 👉 Реклама по ритъм
                    if shouldShowAd(at: index) {
                        AdRowView()
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 0, trailing: 16))
                            .padding(.bottom, 4)
                    }
                    
                    jobRow(for: job)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                
                Color.clear
                    .frame(height: 150)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
    
    // ✅ АКТУАЛИЗИРАНО: Съдържанието на AI Settings таба с новите полета
    @ViewBuilder
    private var settingsContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                
                // --- Advanced Nutrition Generation ---
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select which additional nutrient data to generate when creating new foods with AI. Enabling these may slightly increase generation time.")
                        .font(.caption)
                        .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.7))
                        .padding(.bottom, 4)
                    
                    Text("Food Generation")
                        .font(.headline)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                    
                    VStack(spacing: 0) {
                        
                        settingToggleRow(
                            title: "Lipids",
                            isOn: binding(for: \.generateLipids)
                        )
                        
                        Divider().background(effectManager.currentGlobalAccentColor.opacity(0.2))
                        
                        settingToggleRow(
                            title: "Amino Acids",
                            isOn: binding(for: \.generateAminoAcids)
                        )
                        
                        Divider().background(effectManager.currentGlobalAccentColor.opacity(0.2))
                        
                        settingToggleRow(
                            title: "Carbohydrate Details",
                            isOn: binding(for: \.generateCarbDetails)
                        )
                        
                        Divider().background(effectManager.currentGlobalAccentColor.opacity(0.2))
                        
                        settingToggleRow(
                            title: "Sterols",
                            isOn: binding(for: \.generateSterols)
                        )
                    }
                    .padding()
                    .glassCardStyle(cornerRadius: 20)
                }
            }
            .padding()
            Color.clear
                .frame(height: 150)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
        )    }
    
    // Помощна функция за създаване на Binding към UserSettings
    private func binding(for keyPath: ReferenceWritableKeyPath<UserSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: {
                // Връщаме текущата стойност или false, ако няма настройки
                userSettingsList.first?[keyPath: keyPath] ?? false
            },
            set: { newValue in
                // Ако няма настройки, създаваме нови (малко вероятно, тъй като RootView ги създава)
                if let settings = userSettingsList.first {
                    settings[keyPath: keyPath] = newValue
                } else {
                    let newSettings = UserSettings()
                    newSettings[keyPath: keyPath] = newValue
                    modelContext.insert(newSettings)
                }
                // Запазваме веднага
                try? modelContext.save()
            }
        )
    }
    
    @ViewBuilder
    private func settingToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(effectManager.currentGlobalAccentColor)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .environment(\.colorScheme, effectManager.isLightRowTextColor ? .dark : .light)
        }
        .padding(.vertical, 8)
    }
    
    // ... (Останалите методи: jobRow, userToolbar, checkForUnreadNotifications, shouldShowAd и др. остават същите) ...
    
    @ViewBuilder
    private func jobRow(for job: AIGenerationJob) -> some View {
        // (същият код като преди)
        if job.modelContext != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    statusIcon(for: job.status)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(job.jobType.rawValue) for \(job.profile?.name ?? "Deleted Profile")")
                            .font(.headline)
                        
                        if let contentName = jobContentName(for: job) {
                            Text(contentName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.9))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        Text("Created: \(job.creationDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .opacity(0.8)
                    }
                    
                    Spacer()

                    if job.status == .running && activeJobsCount > 1 {
                        Button(action: { Task { await aiManager.pauseJob(job) } }) {
                            Image(systemName: "pause.fill")
                                .font(.title2)
                                .foregroundColor(effectManager.currentGlobalAccentColor)
                                .frame(width: 44, height: 44)
                        }.buttonStyle(.plain)
                    } else if job.status == .pending {
                        Button(action: { Task { await aiManager.prioritizeJob(job) } }) {
                            Image(systemName: "play.fill")
                                .font(.title2)
                                .foregroundColor(effectManager.currentGlobalAccentColor)
                                .frame(width: 44, height: 44)
                        }.buttonStyle(.plain)
                    }
                }
                
                // ... (Логика за бутоните Completed - същата) ...
                 if job.status == .completed {
                    // Копирай логиката за бутоните от оригиналния файл,
                    // тя не се променя.
                     completionButtons(for: job)
                } else if job.status == .failed {
                    Text("Error: \(job.failureReason ?? "Unknown error")")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding()
            .glassCardStyle(cornerRadius: 20)
            .foregroundColor(effectManager.currentGlobalAccentColor)
            .swipeActions {
                Button(role: .destructive) {
                    Task { await aiManager.deleteJob(job) }
                } label: {
                    Image(systemName: "trash.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                }
                .tint(.clear)
            }
        }
    }
    
    // Helper за изчистване на основния body
    @ViewBuilder
    private func completionButtons(for job: AIGenerationJob) -> some View {
        switch job.jobType {
        case .mealPlan:
            Button {
                withAnimation{
                    coordinator.pendingAIPlanPreview = job.result
                    coordinator.profileForPendingAIPlan = job.profile
                    coordinator.sourceAIGenerationJobID = job.id
                    coordinator.pendingAIPlanJobType = .mealPlan
                }
            } label: {
                Label("Preview & Save Plan", systemImage: "square.and.arrow.down.on.square")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.vertical, 10)
            .glassCardStyle(cornerRadius: 20)
            
        case .dailyMealPlan:
            Button {
                withAnimation {
                    coordinator.pendingAIPlanPreview = job.result
                    coordinator.profileForPendingAIPlan = job.profile
                    coordinator.sourceAIGenerationJobID = job.id
                    coordinator.pendingAIPlanJobType = job.jobType
                }
            } label: {
                Label("Preview & Apply Day Plan", systemImage: "doc.text.image")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.vertical, 10)
            .glassCardStyle(cornerRadius: 20)
            
        case .recipeGeneration:
            Button {
                guard #available(iOS 26.0, *),
                      let data = job.resultData,
                      let payload = try? JSONDecoder().decode(ResolvedRecipeResponseDTO.self, from: data),
                      let recipeName = job.inputParameters?.foodNameToGenerate else { return }
                
                let foodCopy = FoodItemCopy(from: payload, recipeName: recipeName, context: modelContext)
                withAnimation {
                    coordinator.pendingAIRecipe = foodCopy
                    coordinator.sourceAIRecipeJobID = job.id
                    coordinator.profileForPendingAIPlan = job.profile
                }
            } label: {
                Label("Preview & Save Recipe", systemImage: "square.and.arrow.down.on.square")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.vertical, 10)
            .glassCardStyle(cornerRadius: 20)
            
        case .menuGeneration:
            Button {
                guard #available(iOS 26.0, *),
                      let data = job.resultData,
                      let payload = try? JSONDecoder().decode(ResolvedRecipeResponseDTO.self, from: data),
                      let menuName = payload.name else { return }
                
                let foodCopy = FoodItemCopy(from: payload, menuName: menuName, context: modelContext)
                withAnimation {
                    coordinator.pendingAIMenu = foodCopy
                    coordinator.sourceAIMenuJobID = job.id
                    coordinator.profileForPendingAIPlan = job.profile
                }
            } label: {
                Label("Preview & Save Menu", systemImage: "square.and.arrow.down.on.square")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.vertical, 10)
            .glassCardStyle(cornerRadius: 20)
            
        case .nutritionsDetailDailyMealPlan, .createFoodWithAI, .createExerciseWithAI, .trainingViewDailyPlan:
            EmptyView()
            
        case .foodItemDetail:
            Button {
                guard #available(iOS 26.0, *), let data = job.resultData, let response = try? JSONDecoder().decode(FoodItemDTO.self, from: data) else { return }
                withAnimation {
                    coordinator.pendingAIFoodDetailResponse = response
                    coordinator.sourceAIFoodDetailJobID = job.id
                }
            } label: {
                Label("Preview & Save Food", systemImage: "square.and.arrow.down.on.square")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.vertical, 10)
            .glassCardStyle(cornerRadius: 20)
            
        case .exerciseDetail:
            Button {
                guard #available(iOS 26.0, *), let data = job.resultData, let response = try? JSONDecoder().decode(ExerciseItemDTO.self, from: data) else { return }
                withAnimation {
                    coordinator.pendingAIExerciseDetailResponse = response
                    coordinator.sourceAIExerciseDetailJobID = job.id
                }
            } label: {
                Label("Preview & Save Exercise", systemImage: "square.and.arrow.down.on.square")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.vertical, 10)
            .glassCardStyle(cornerRadius: 20)
            
        case .dietGeneration:
            Button {
                guard #available(iOS 26.0, *), let data = job.resultData, let wire = try? JSONDecoder().decode(AIDietResponseWireDTO.self, from: data) else { return }
                withAnimation {
                    coordinator.pendingAIDietWireResponse = wire
                    coordinator.sourceAIGenerationJobID = job.id
                    coordinator.profileForPendingAIPlan = job.profile
                }
            } label: {
                Label("Review & Save Diet", systemImage: "square.and.arrow.down.on.square")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.vertical, 10)
            .glassCardStyle(cornerRadius: 20)
            
        case .trainingPlan, .dailyTreiningPlan:
            Button {
                guard #available(iOS 26.0, *), let data = job.resultData, let generatedDraft = try? JSONDecoder().decode(TrainingPlanDraft.self, from: data), let workoutsToFill = job.inputParameters?.workoutsToFill else { return }
                
                let generatedDaysMap = Dictionary(uniqueKeysWithValues: generatedDraft.days.map { ($0.dayIndex, $0) })
                let allRequestedDayIndices = workoutsToFill.keys.sorted()
                let fullDayDrafts = allRequestedDayIndices.map { dayIndex in
                    generatedDaysMap[dayIndex] ?? TrainingPlanDayDraft(dayIndex: dayIndex, trainings: [])
                }
                let completeDraft = TrainingPlanDraft(name: generatedDraft.name, days: fullDayDrafts)
                
                withAnimation {
                    coordinator.pendingAITrainingPlan = completeDraft
                    coordinator.sourceAITrainingPlanJobID = job.id
                    coordinator.profileForPendingAIPlan = job.profile
                    coordinator.pendingAIPlanJobType = job.jobType
                }
            } label: {
                let labelText = (job.jobType == .trainingPlan) ? "Preview & Save Plan" : "Preview & Apply Day Plan"
                let iconName = (job.jobType == .trainingPlan) ? "square.and.arrow.down.on.square" : "doc.text.image"
                Label(labelText, systemImage: iconName)
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.vertical, 10)
            .glassCardStyle(cornerRadius: 20)
            
        case .workoutGeneration:
            Button {
                guard #available(iOS 26.0, *), let data = job.resultData, let dto = try? JSONDecoder().decode(ResolvedWorkoutResponseDTO.self, from: data) else { return }
                
                // Тук би следвало да се възстанови WorkoutCopy (съкратено за прегледност)
                 let exerciseIDs = dto.exercises.map { $0.exerciseID }
                 let descriptor = FetchDescriptor<ExerciseItem>(predicate: #Predicate { exerciseIDs.contains($0.id) })
                 if let fetchedItems = try? modelContext.fetch(descriptor) {
                     let itemMap = Dictionary(uniqueKeysWithValues: fetchedItems.map { ($0.id, $0) })
                     let links: [ExerciseLinkCopy] = dto.exercises.compactMap { resolved in
                         guard let item = itemMap[resolved.exerciseID] else { return nil }
                         return ExerciseLinkCopy(exercise: ExerciseItemCopy(from: item), durationMinutes: resolved.durationMinutes)
                     }
                     let workoutCopy = ExerciseItemCopy(from: dto, links: links)
                     withAnimation {
                         coordinator.pendingAIWorkout = workoutCopy
                         coordinator.sourceAIWorkoutJobID = job.id
                         coordinator.profileForPendingAIPlan = job.profile
                     }
                 }
            } label: {
                Label("Preview & Save Workout", systemImage: "square.and.arrow.down.on.square")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.vertical, 10)
            .glassCardStyle(cornerRadius: 20)
        }
    }
    
    private func jobContentName(for job: AIGenerationJob) -> String? {
        if let name = job.inputParameters?.foodNameToGenerate, !name.isEmpty {
            return name
        }
        if let prompts = job.inputParameters?.selectedPrompts, !prompts.isEmpty {
            return prompts.joined(separator: ", ")
        }
        return nil
    }

    @ViewBuilder
    private func statusIcon(for status: AIGenerationJob.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "clock.arrow.circlepath").foregroundColor(.gray)
        case .running:
            ProgressView().tint(effectManager.currentGlobalAccentColor)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        }
    }
    
    @ViewBuilder
    private func userToolbar(for profile: Profile) -> some View {
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
    
    private func checkForUnreadNotifications() async {
        let unread = await NotificationManager.shared.getUnreadNotifications()
        self.hasUnreadNotifications = !unread.isEmpty
    }
    
    private func shouldShowAd(at index: Int) -> Bool {
        if SubscriptionManager.shared.subscriptionStatus != .base { return false }
        if index < 2 { return false }
        let remainder = index % 7
        return remainder == 2 || remainder == 5
    }
}
