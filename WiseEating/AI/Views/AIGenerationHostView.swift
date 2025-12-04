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
    
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @State private var currentTimeString: String = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let tFmt = DateFormatter.shortTime
    @State private var hasUnreadNotifications: Bool = false
    
    private var headerTopPadding: CGFloat {
        -safeAreaInsets.top + 10
    }
    
    // --- START OF CHANGE ---
    private var activeJobsCount: Int {
        jobs.filter { $0.status == .pending || $0.status == .running }.count
    }
    // --- END OF CHANGE ---
    
    @State private var jobToDelete: AIGenerationJob? = nil
    @State private var isShowingDeleteJobConfirmation: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            userToolbar(for: profile)
                .padding(.trailing, 50)
                .padding(.leading, 40)
                .padding(.horizontal, -20)
                .padding(.bottom, 8)
            
            UpdatePlanBanner()
            
            toolbar
            
            
            if jobs.isEmpty {
                let emptyDescription: Text = {
                    switch aiAvailabilityLocal {
                    case .available:
                        return Text("Tap the ✨ button on diet or training screens to start a new generation.")
                    case .appleIntelligenceNotEnabled:
                        return Text("")
                    case .deviceNotEligible:
                        return Text("")
                    case .modelNotReady:
                        return Text("")
                    case .unavailableUnsupportedOS:
                        return Text("")
                    case .unavailableOther:
                        return Text("")
                    }
                }()
                
                let emptyIcon: String = {
                    switch aiAvailabilityLocal {
                    case .available: return "sparkles"
                    case .appleIntelligenceNotEnabled: return "gearshape"
                    case .deviceNotEligible: return "iphone.slash"
                    case .modelNotReady: return "arrow.down.circle"
                    case .unavailableUnsupportedOS: return "iphone.slash"
                    case .unavailableOther: return "exclamationmark.triangle"
                    }
                }()
                
                let title: String = {
                    switch aiAvailabilityLocal {
                    case .available:
                        return "No AI Generation History"
                    case .appleIntelligenceNotEnabled:
                        return "Enable Apple Intelligence in Settings to start AI generation."
                    case .deviceNotEligible:
                        return "This device doesn’t support Apple Intelligence."
                    case .modelNotReady:
                        return "The model is preparing. Once ready, you can start AI generation from the relevant screens."
                    case .unavailableUnsupportedOS:
                        return "Apple Intelligence requires iOS 26. Upgrade your OS to use AI generation."
                    case .unavailableOther:
                        return "AI is temporarily unavailable. Please try again later."
                    }
                }()
                
                ContentUnavailableView(
                    title,
                    systemImage: emptyIcon,
                    description: emptyDescription
                )
                .foregroundStyle(effectManager.currentGlobalAccentColor.opacity(0.8))
            } else {
                List {
                    ForEach(jobs) { job in
                        jobRow(for: job)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    Color.clear.frame(height: 150)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.01),
                            .init(color: .black, location: 0.9),
                            .init(color: .clear, location: 0.95)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .padding(.top, headerTopPadding)
        .onReceive(timer) { _ in
            self.currentTimeString = Self.tFmt.string(from: Date())
        }
        .task {
            await checkForUnreadNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await checkForUnreadNotifications() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .unreadNotificationStatusChanged)) { _ in
            Task { await checkForUnreadNotifications() }
        }
        .task {
            // Ensure we fetch the latest availability when the view appears
            await MainActor.run {
                GlobalState.updateAIAvailability()
                aiAvailabilityLocal = GlobalState.aiAvailability
            }
        }
        
        .onReceive(NotificationCenter.default.publisher(for: .aiAvailabilityDidChange)) { note in
            if let v = note.object as? GlobalState.AIAvailabilityStatus {
                aiAvailabilityLocal = v
            } else {
                aiAvailabilityLocal = GlobalState.aiAvailability
            }
        }
        
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await MainActor.run { GlobalState.updateAIAvailability() } }
        }
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
    
    
    
    private var toolbar: some View {
        HStack {
            Text("AI Generation Jobs")
                .font(.title.bold())
                .foregroundColor(effectManager.currentGlobalAccentColor)
            
            Spacer()
        }
        .foregroundColor(effectManager.currentGlobalAccentColor)
        .padding()
    }
    
    @ViewBuilder
    private func jobRow(for job: AIGenerationJob) -> some View {
          if job.modelContext != nil {
              VStack(alignment: .leading, spacing: 10) {
                  HStack {
                      statusIcon(for: job.status)
                      VStack(alignment: .leading) {
                          Text("\(job.jobType.rawValue) for \(job.profile?.name ?? "Deleted Profile")")
                              .font(.headline)
                          Text("Created: \(job.creationDate.formatted(date: .abbreviated, time: .shortened))")
                              .font(.caption)
                              .opacity(0.8)
                      }
                      Spacer()

                      // --- START OF CHANGE ---
                      if job.status == .running && activeJobsCount > 1 {
                      // --- END OF CHANGE ---
                          Button(action: {
                              Task { await aiManager.pauseJob(job) }
                          }) {
                              Image(systemName: "pause.fill")
                                  .font(.title2)
                                  .foregroundColor(effectManager.currentGlobalAccentColor)
                                  .frame(width: 44, height: 44)
                          }
                          .buttonStyle(.plain)
                      } else if job.status == .pending {
                          Button(action: {
                              Task { await aiManager.prioritizeJob(job) }
                          }) {
                              Image(systemName: "play.fill")
                                  .font(.title2)
                                  .foregroundColor(effectManager.currentGlobalAccentColor)
                                  .frame(width: 44, height: 44)
                          }
                          .buttonStyle(.plain)
                      }
                  }
                
                if job.status == .completed {
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
                                  let recipeName = job.inputParameters?.foodNameToGenerate else {
                                print("❌ Failed to decode ResolvedRecipeResponseDTO or get recipe name.")
                                return
                            }
                            print("payload", payload.ingredients)
                            let foodCopy = FoodItemCopy(from: payload, recipeName: recipeName, context: modelContext)
                            
                            print("foodCopy", foodCopy.ingredients)
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
                                  // За менюта, името е в самия payload
                                  let menuName = payload.name else {
                                print("❌ Failed to decode ResolvedRecipeResponseDTO or get menu name for menu generation.")
                                return
                            }
                            print("payload", payload.ingredients)
                            let foodCopy = FoodItemCopy(from: payload, menuName: menuName, context: modelContext)
                            
                            print("foodCopy", foodCopy.ingredients)
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
                            guard #available(iOS 26.0, *),
                                  let data = job.resultData,
                                  let response = try? JSONDecoder().decode(FoodItemDTO.self, from: data) else {
                                print("❌ Failed to decode AIFoodDetailsResponse or OS version is too old.")
                                return
                            }
                            
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
                        } label: {
                            Label("Preview & Save Exercise", systemImage: "square.and.arrow.down.on.square")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(.vertical, 10)
                        .glassCardStyle(cornerRadius: 20)
                    case .dietGeneration:
                        Button {
                            guard #available(iOS 26.0, *),
                                  let data = job.resultData
                            else {
                                print("❌ Diet job has no result data or OS too old.")
                                return
                            }
                            
                            guard let wire = try? JSONDecoder().decode(AIDietResponseWireDTO.self, from: data) else {
                                print("❌ Failed to decode AIDietResponseWireDTO for diet generation job.")
                                return
                            }
                            
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
                            guard #available(iOS 26.0, *),
                                  let data = job.resultData,
                                  let generatedDraft = try? JSONDecoder().decode(TrainingPlanDraft.self, from: data),
                                  let workoutsToFill = job.inputParameters?.workoutsToFill
                            else {
                                print("❌ Failed to decode TrainingPlanDraft or get input parameters.")
                                return
                            }
                            
                            let generatedDaysMap = Dictionary(uniqueKeysWithValues: generatedDraft.days.map { ($0.dayIndex, $0) })
                            let allRequestedDayIndices = workoutsToFill.keys.sorted()
                            
                            let fullDayDrafts = allRequestedDayIndices.map { dayIndex -> TrainingPlanDayDraft in
                                if let generatedDay = generatedDaysMap[dayIndex] {
                                    return generatedDay
                                } else {
                                    return TrainingPlanDayDraft(dayIndex: dayIndex, trainings: [])
                                }
                            }
                            
                            let completeDraft = TrainingPlanDraft(name: generatedDraft.name, days: fullDayDrafts)
                            
                            withAnimation {
                                coordinator.pendingAITrainingPlan = completeDraft
                                coordinator.sourceAITrainingPlanJobID = job.id
                                coordinator.profileForPendingAIPlan = job.profile
                                // ЗАДАВАМЕ И ТИПА, ЗА ДА МОЖЕ ROOTVIEW ДА РЕАГИРА
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
                            guard #available(iOS 26.0, *),
                                  let data = job.resultData,
                                  let dto = try? JSONDecoder().decode(ResolvedWorkoutResponseDTO.self, from: data)
                            else {
                                print("❌ Failed to decode ResolvedWorkoutResponseDTO for workout job.")
                                return
                            }
                            
                            let exerciseIDs = dto.exercises.map { $0.exerciseID }
                            
                            let descriptor = FetchDescriptor<ExerciseItem>(predicate: #Predicate { exerciseIDs.contains($0.id) })
                            guard let fetchedItems = try? modelContext.fetch(descriptor) else {
                                print("❌ Could not fetch exercises for workout DTO.")
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
                        } label: {
                            Label("Preview & Save Workout", systemImage: "square.and.arrow.down.on.square")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(.vertical, 10)
                        .glassCardStyle(cornerRadius: 20)
                    }
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
                    if #available(iOS 26.0, *) {
                        Task {
                            await aiManager.deleteJob(job)
                        }
                    } else {
                        self.jobToDelete = job
                        self.isShowingDeleteJobConfirmation = true
                    }
                } label: {
                    Image(systemName: "trash.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(effectManager.currentGlobalAccentColor)
                }
                .tint(.clear)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for status: AIGenerationJob.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(.gray)
        case .running:
            ProgressView().tint(effectManager.currentGlobalAccentColor)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
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
    
    // MARK: - AI Availability Banner (helpers)
    private struct AIBannerData {
        let icon: String
        let title: String
        let subtitle: String?
    }
    
    private var aiBannerData: AIBannerData {
        switch aiAvailabilityLocal {
        case .available:
            return .init(
                icon: "sparkles",
                title: "Apple Intelligence is available.",
                subtitle: "You can start AI generation from screens marked with ✨."
            )
        case .appleIntelligenceNotEnabled:
            return .init(
                icon: "gearshape",
                title: "Apple Intelligence is turned off.",
                subtitle: "Enable it in Settings to use AI features."
            )
        case .deviceNotEligible:
            return .init(
                icon: "iphone.slash",
                title: "This device doesn’t support Apple Intelligence.",
                subtitle: "AI features aren’t available on this hardware."
            )
        case .modelNotReady:
            return .init(
                icon: "arrow.down.circle",
                title: "Model is preparing/downloading.",
                subtitle: "Some AI features may be temporarily unavailable."
            )
        case .unavailableUnsupportedOS:
            return .init(
                icon: "iphone.slash",
                title: "Apple Intelligence requires iOS 26.",
                subtitle: "Upgrade your OS to use AI features."
            )
        case .unavailableOther:
            return .init(
                icon: "exclamationmark.triangle",
                title: "Apple Intelligence is unavailable right now.",
                subtitle: "Please try again later."
            )
        }
    }
    
    @ViewBuilder
    private var aiAvailabilityBanner: some View {
        let data = aiBannerData
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: data.icon).imageScale(.medium)
            VStack(alignment: .leading, spacing: 2) {
                Text(data.title).font(.footnote.weight(.semibold))
                if let sub = data.subtitle {
                    Text(sub).font(.caption2).opacity(0.8)
                }
            }
            Spacer()
        }
        .foregroundStyle(effectManager.currentGlobalAccentColor)
        .padding(12)
        .glassCardStyle(cornerRadius: 16)
    }
    
   
}
