import Foundation
import SwiftData
import UserNotifications

@MainActor
final class AIManager: ObservableObject {
    static let shared = AIManager()
    private let globalTaskManager = GlobalTaskManager.shared

    @Published var jobs: [AIGenerationJob] = []
    
    // Речник за проследяване на активните задачи.
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    
    var isGenerating: Bool {
        jobs.contains { $0.status == .pending || $0.status == .running }
    }
    
    private var modelContainer: ModelContainer?
    
    private init() {}
    
    // --- START OF CHANGE (1/2): Modify setup method ---
    func setup(container: ModelContainer) {
        self.modelContainer = container
        Task {
            await fetchJobs()
            // ДОБАВЕНО: Проверяваме за задачи, прекъснати при предишно затваряне.
            await resumeInterruptedJobs()
            await scheduleNextIfIdle() // 🧠 стартирай опашката ако сме свободни
        }
    }
    // --- END OF CHANGE (1/2) ---
    
    func fetchJobs() async {
        guard let context = modelContainer?.mainContext else { return }
        do {
            let descriptor = FetchDescriptor<AIGenerationJob>(sortBy: [SortDescriptor(\.creationDate, order: .reverse)])
            self.jobs = try context.fetch(descriptor)
        } catch {
            print("❌ AIManager: Failed to fetch jobs: \(error)")
        }
    }
    
    // Централизиран метод за стартиране и проследяване на задачи.
    // START OF CHANGE: launchGenerationTask(for:)
    // REPLACE the whole function
    private func launchGenerationTask(for job: AIGenerationJob) {
        // Ако вече има активна задача — излизаме (ще бъдем извикани пак, когато се освободи).
        guard runningTasks.isEmpty else { return }

        let jobID = job.id
        let profileID = job.profile?.persistentModelID

        let task = Task {
            guard !Task.isCancelled else {
                print("ℹ️ AIManager: Task for job \(jobID) was cancelled before starting.")
                return
            }

            await self.runGenerationTask(jobID: jobID, profileID: profileID)

            // 1) mark idle
            await MainActor.run {
                self.runningTasks[jobID] = nil
            }
            // 2) NOW schedule the next one
            await self.scheduleNextIfIdle()
        }

        self.runningTasks[jobID] = task
    }
    // END OF CHANGE

    
    // ... (всички start... методи остават непроменени, тъй като те викат launchGenerationTask) ...
    
    // START OF CHANGE: startPlanGeneration
    @discardableResult
    func startPlanGeneration(for profile: Profile, days: Int, meals: [String]?, jobType: AIGenerationJob.JobType) -> AIGenerationJob? {
        guard let context = modelContainer?.mainContext else { return nil }

        let mealNames = meals ?? profile.meals.map { $0.name }
        let mealsToFill = (1...days).reduce(into: [Int: [String]]()) { dict, dayIndex in
            dict[dayIndex] = mealNames
        }

        let input = AIGenerationJob.InputParameters(
            startDate: Date(), numberOfDays: days, specificMeals: nil, mealsToFill: mealsToFill,
            existingMeals: nil, selectedPrompts: nil, mealTimings: nil, foodNameToGenerate: nil,
            preCreatedItemID: nil
        )

        let newJob = AIGenerationJob(profile: profile, inputParams: input, jobType: jobType)
        context.insert(newJob)
        try? context.save()

        Task {
            await fetchJobs()
            await scheduleNextIfIdle() // ⬅️ вместо launchGenerationTask(for:)
        }

        return newJob
    }
    // END OF CHANGE

    // MARK: - STARTERS (serialized queue-ready)

    // 1) startPlanFill
    @discardableResult
    func startPlanFill(
        for profile: Profile,
        daysAndMeals: [Int: [String]],
        existingMeals: [Int: [MealPlanPreviewMeal]],
        selectedPrompts: [String]?,
        mealTimings: [String: Date]? = nil,
        jobType: AIGenerationJob.JobType
    ) -> AIGenerationJob? {
        guard let context = modelContainer?.mainContext else { return nil }

        let input = AIGenerationJob.InputParameters(
            startDate: Date(),
            numberOfDays: daysAndMeals.keys.count,
            specificMeals: nil,
            mealsToFill: daysAndMeals,
            existingMeals: existingMeals,
            selectedPrompts: selectedPrompts,
            mealTimings: mealTimings,
            foodNameToGenerate: nil,
            preCreatedItemID: nil
        )

        let newJob = AIGenerationJob(profile: profile, inputParams: input, jobType: jobType)
        context.insert(newJob)
        try? context.save()

        Task {
            await fetchJobs()
            await scheduleNextIfIdle()
        }

        return newJob
    }

    // 2) startFoodDetailGeneration
    @discardableResult
    func startFoodDetailGeneration(
        for profile: Profile?,
        foodName: String,
        jobType: AIGenerationJob.JobType
    ) -> AIGenerationJob? {
        guard let context = modelContainer?.mainContext else { return nil }

        let input = AIGenerationJob.InputParameters(
            startDate: nil,
            numberOfDays: nil,
            specificMeals: nil,
            mealsToFill: nil,
            existingMeals: nil,
            selectedPrompts: nil,
            mealTimings: nil,
            foodNameToGenerate: foodName,
            preCreatedItemID: nil
        )

        let newJob = AIGenerationJob(profile: profile!, inputParams: input, jobType: jobType)
        context.insert(newJob)
        try? context.save()

        Task {
            await fetchJobs()
            await scheduleNextIfIdle()
        }

        return newJob
    }

    // 4) startRecipeGeneration
    @discardableResult
    func startRecipeGeneration(
        for profile: Profile?,
        recipeName: String,
        jobType: AIGenerationJob.JobType
    ) -> AIGenerationJob? {
        guard let context = modelContainer?.mainContext else { return nil }

        let input = AIGenerationJob.InputParameters(
            startDate: nil,
            numberOfDays: nil,
            specificMeals: nil,
            mealsToFill: nil,
            existingMeals: nil,
            selectedPrompts: nil,
            mealTimings: nil,
            foodNameToGenerate: recipeName,
            preCreatedItemID: nil
        )

        let newJob = AIGenerationJob(profile: profile!, inputParams: input, jobType: jobType)
        context.insert(newJob)
        try? context.save()

        Task {
            await fetchJobs()
            await scheduleNextIfIdle()
        }

        return newJob
    }

    // 5) startEmptyFoodGeneration
    @discardableResult
    func startEmptyFoodGeneration(
        for profile: Profile?,
        foodItem: FoodItem
    ) -> AIGenerationJob? {
        guard let context = modelContainer?.mainContext else { return nil }

        let foodName = foodItem.name
        let input = AIGenerationJob.InputParameters(
            startDate: nil,
            numberOfDays: nil,
            specificMeals: nil,
            mealsToFill: nil,
            existingMeals: nil,
            selectedPrompts: nil,
            mealTimings: nil,
            foodNameToGenerate: foodName,
            preCreatedItemID: foodItem.id
        )

        let newJob = AIGenerationJob(profile: profile!, inputParams: input, jobType: .createFoodWithAI)
        context.insert(newJob)
        try? context.save()

        Task {
            await fetchJobs()
            await scheduleNextIfIdle()
        }

        return newJob
    }

    // 6) startEmptyExerciseGeneration
    @discardableResult
    func startEmptyExerciseGeneration(
        for profile: Profile?,
        exerciseItem: ExerciseItem
    ) -> AIGenerationJob? {
        guard let context = modelContainer?.mainContext else { return nil }

        let exerciseName = exerciseItem.name
        let input = AIGenerationJob.InputParameters(
            startDate: nil,
            numberOfDays: nil,
            specificMeals: nil,
            mealsToFill: nil,
            existingMeals: nil,
            selectedPrompts: nil,
            mealTimings: nil,
            foodNameToGenerate: exerciseName,
            preCreatedItemID: exerciseItem.id
        )

        let newJob = AIGenerationJob(profile: profile!, inputParams: input, jobType: .createExerciseWithAI)
        context.insert(newJob)
        try? context.save()

        Task {
            await fetchJobs()
            await scheduleNextIfIdle()
        }

        return newJob
    }

    // 7) startExerciseDetailGeneration
    @discardableResult
    func startExerciseDetailGeneration(
        for profile: Profile?,
        exerciseName: String,
        jobType: AIGenerationJob.JobType
    ) -> AIGenerationJob? {
        guard let context = modelContainer?.mainContext else { return nil }

        let input = AIGenerationJob.InputParameters(
            startDate: nil,
            numberOfDays: nil,
            specificMeals: nil,
            mealsToFill: nil,
            existingMeals: nil,
            selectedPrompts: nil,
            mealTimings: nil,
            foodNameToGenerate: exerciseName,
            preCreatedItemID: nil
        )

        let newJob = AIGenerationJob(profile: profile!, inputParams: input, jobType: jobType)
        context.insert(newJob)
        try? context.save()

        Task {
            await fetchJobs()
            await scheduleNextIfIdle()
        }

        return newJob
    }

    // 8) startTrainingPlanGeneration
    @discardableResult
    func startTrainingPlanGeneration(
        for profile: Profile,
        prompts: [String],
        days: Int? = nil,
        trainingTimes: [Int: Date]? = nil,
        plannedWorkoutTimes: [String: Date]? = nil,
        workoutsToFill: [Int: [String]]?,
        existingWorkouts: [Int: [TrainingPlanWorkoutDraft]]?,
        jobType: AIGenerationJob.JobType
    ) -> AIGenerationJob? {
        guard let context = modelContainer?.mainContext else { return nil }

        let input = AIGenerationJob.InputParameters(
            startDate: nil,
            numberOfDays: days,
            specificMeals: nil,
            mealsToFill: nil,
            existingMeals: nil,
            selectedPrompts: prompts,
            mealTimings: nil,
            foodNameToGenerate: nil,
            trainingDays: days,
            trainingTimes: trainingTimes,
            plannedWorkoutTimes: plannedWorkoutTimes,
            workoutsToFill: workoutsToFill,
            existingWorkouts: existingWorkouts,
            preCreatedItemID: nil
        )

        let newJob = AIGenerationJob(profile: profile, inputParams: input, jobType: jobType)
        context.insert(newJob)
        try? context.save()

        Task {
            await fetchJobs()
            await scheduleNextIfIdle()
        }

        return newJob
    }

    // 9) startWorkoutGeneration
    @discardableResult
    func startWorkoutGeneration(
        for profile: Profile?,
        prompts: [String],
        jobType: AIGenerationJob.JobType
    ) -> AIGenerationJob? {
        guard let context = modelContainer?.mainContext else { return nil }

        let input = AIGenerationJob.InputParameters(
            startDate: nil,
            numberOfDays: nil,
            specificMeals: nil,
            mealsToFill: nil,
            existingMeals: nil,
            selectedPrompts: prompts,
            mealTimings: nil,
            foodNameToGenerate: nil,
            preCreatedItemID: nil
        )

        let newJob = AIGenerationJob(profile: profile!, inputParams: input, jobType: jobType)
        context.insert(newJob)
        try? context.save()

        Task {
            await fetchJobs()
            await scheduleNextIfIdle()
        }

        return newJob
    }

    // 10) startMenuGeneration
    @discardableResult
    func startMenuGeneration(
        for profile: Profile,
        selectedPrompts: [String]?,
        jobType: AIGenerationJob.JobType
    ) -> AIGenerationJob? {
        guard let context = modelContainer?.mainContext else { return nil }

        let input = AIGenerationJob.InputParameters(
            startDate: nil,
            numberOfDays: nil,
            specificMeals: nil,
            mealsToFill: nil,
            existingMeals: nil,
            selectedPrompts: selectedPrompts,
            mealTimings: nil,
            foodNameToGenerate: nil,
            preCreatedItemID: nil
        )

        let newJob = AIGenerationJob(profile: profile, inputParams: input, jobType: jobType)
        context.insert(newJob)
        try? context.save()

        Task {
            await fetchJobs()
            await scheduleNextIfIdle()
        }

        return newJob
    }
    
    
    // START OF CHANGE: runGenerationTask(jobID:profileID:)
    private func runGenerationTask(jobID: UUID, profileID: PersistentIdentifier?) async {
        if Task.isCancelled {
            print("ℹ️ AIManager: Generation task for job \(jobID) cancelled before running.")
            return
        }

        guard let container = self.modelContainer else { return }
        let mainContext = container.mainContext

        do {
            guard let job = try mainContext.fetch(FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.id == jobID })).first else { return }
            job.status = .running
            try mainContext.save()
        } catch {
            print("❌ AIManager: Could not mark job \(jobID) as running: \(error)")
            return
        }

        let backgroundTask = Task.detached(priority: .background) { () -> Result<Data, Error> in
            do {
                try Task.checkCancellation()

                let bgContext = ModelContext(container)
                guard let job = try bgContext.fetch(FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.id == jobID })).first else {
                    throw NSError(domain: "AIManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Job not found on background thread."])
                }

                try Task.checkCancellation()

                if #available(iOS 26.0, *) {
                    switch job.jobType {
                        
                    case .menuGeneration:
                        guard let profileID = job.profile?.persistentModelID,
                              let profile = bgContext.model(for: profileID) as? Profile else {
                            throw NSError(domain: "AIManager", code: 6, userInfo: [NSLocalizedDescriptionKey: "Profile not found for menu generation job."])
                        }
                        
                        let generator = await AIMenuGenerator(container: container)
                        let dto = try await generator.generateMenuDetails(
                            jobID: job.persistentModelID,
                            for: profile,
                            prompts: job.inputParameters?.selectedPrompts,
                            onLog: { log in print("[AI BG Menu] \(log)") }
                        )
                        return .success(try JSONEncoder().encode(dto))
                    case .foodItemDetail:
                        guard let foodName = job.inputParameters?.foodNameToGenerate else {
                            throw NSError(domain: "AIManager", code: 4,
                                          userInfo: [NSLocalizedDescriptionKey: "Food name to generate not found in job parameters."])
                        }
                        let data = try await self.generateFoodDetailDataOnMain(container: container, foodName: foodName)
                        return .success(data)
                        
                    case .recipeGeneration:
                        guard let recipeName = job.inputParameters?.foodNameToGenerate else {
                            throw NSError(domain: "AIManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "Recipe name to generate not found."])
                        }
                        let generator = await AIRecipeGenerator(container: container)
                        let dto = try await generator.generateAndResolveRecipeDTO(
                            for: recipeName,
                            jobID: job.persistentModelID, // Pass the job ID here
                            onLog: { log in print("[AI BG Recipe] \(log)") }
                        )
                        return .success(try JSONEncoder().encode(dto))
                        
                    case .exerciseDetail:
                        guard let exerciseName = job.inputParameters?.foodNameToGenerate else {
                            throw NSError(domain: "AIManager", code: 7, userInfo: [NSLocalizedDescriptionKey: "Exercise name not found in job parameters."])
                        }
                        let data = try await self.generateExerciseDetailDataOnMain(container: container, exerciseName: exerciseName)
                        return .success(data)

                    case .trainingPlan, .trainingViewDailyPlan, .dailyTreiningPlan:
                        guard
                            let profileID = job.profile?.persistentModelID,
                            let params = job.inputParameters,
                            let workoutsToFill = params.workoutsToFill, !workoutsToFill.isEmpty
                        else {
                            throw NSError(domain: "AIManager", code: 9, userInfo: [NSLocalizedDescriptionKey: "Invalid parameters for training plan generation."])
                        }
                        
                        let generator = await AITrainingPlanGenerator(container: container)
                        
                        let generatedDraft = try await generator.fillPlanDetails(
                            jobID: job.persistentModelID,
                            profileID: profileID,
                            prompts: params.selectedPrompts ?? [],
                            workoutsToFill: workoutsToFill,
                            existingWorkouts: params.existingWorkouts,
                            plannedTimes: params.trainingTimes ?? [:],
                            plannedWorkoutTimes: params.plannedWorkoutTimes ?? [:],
                            onLog: { log in print("[AI BG TrainingPlan] \(log)") }
                        )
                        
                        return .success(try JSONEncoder().encode(generatedDraft))
                        
                    case .workoutGeneration:
                        guard let prompts = job.inputParameters?.selectedPrompts,
                              let profile = job.profile else {
                            throw NSError(domain: "AIManager", code: 10, userInfo: [NSLocalizedDescriptionKey: "Missing parameters for workout generation."])
                        }
                        
                        let generator = await AIWorkoutGenerator(container: container)
                        let dto = try await generator.generateWorkout(
                            jobID: job.persistentModelID,
                            profile: profile,
                            prompts: prompts,
                            onLog: { log in print("[AI BG Workout] \(log)") }
                        )
                        return .success(try JSONEncoder().encode(dto))
                        
                    case .mealPlan, .dailyMealPlan, .nutritionsDetailDailyMealPlan:
                        guard let profileID = profileID,
                              (bgContext.model(for: profileID) as? Profile) != nil,
                              let params = job.inputParameters,
                              let mealsToFill = params.mealsToFill, !mealsToFill.isEmpty else {
                            throw NSError(domain: "AIManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid parameters for meal planning."])
                        }
                        
                        let planner = USDAWeeklyMealPlanner(container: container)
                        let generatedPreview = try await planner.fillPlanDetails(
                            jobID: job.persistentModelID,
                            profileID: profileID,
                            daysAndMeals: mealsToFill,
                            prompts: params.selectedPrompts,
                            mealTimings: params.mealTimings,
                            onLog: { print("[AI BG MealPlan] \($0)") }
                        )
                        
                        var finalDayMealMap: [Int: [MealPlanPreviewMeal]] = params.existingMeals ?? [:]
                        for generatedDay in generatedPreview.days {
                            finalDayMealMap[generatedDay.dayIndex, default: []].append(contentsOf: generatedDay.meals)
                        }
                        let mergedDays = finalDayMealMap.keys.sorted().map { dayIndex -> MealPlanPreviewDay in
                            let sortedMeals = finalDayMealMap[dayIndex]!.sorted { $0.name < $1.name }
                            return MealPlanPreviewDay(dayIndex: dayIndex, meals: sortedMeals)
                        }
                        let finalPreview = MealPlanPreview(
                            startDate: generatedPreview.startDate,
                            prompt: generatedPreview.prompt,
                            days: mergedDays,
                            minAgeMonths: generatedPreview.minAgeMonths,
                            interpretationCaveat: generatedPreview.interpretationCaveat
                        )
                        return .success(try JSONEncoder().encode(finalPreview))
                        
                    case .createFoodWithAI:
                        guard let foodName = job.inputParameters?.foodNameToGenerate,
                              let itemID = job.inputParameters?.preCreatedItemID
                        else {
                            throw NSError(domain: "AIManager", code: 11, userInfo: [NSLocalizedDescriptionKey: "Missing food name or pre-created item ID for createFoodWithAI job."])
                        }
                        
                        let data = try await self.createFoodWithAIDataOnMain(container: container, foodName: foodName, itemID: itemID)
                        return .success(data)
                        
                    case .createExerciseWithAI:
                        guard let exerciseName = job.inputParameters?.foodNameToGenerate,
                              let itemID = job.inputParameters?.preCreatedItemID
                        else {
                            throw NSError(domain: "AIManager", code: 13, userInfo: [NSLocalizedDescriptionKey: "Missing exercise name or pre-created item ID for createExerciseWithAI job."])
                        }
                        
                        let data = try await self.createExerciseWithAIDataOnMain(container: container, exerciseName: exerciseName, itemID: itemID)
                        return .success(data)
                    }
                } else {
                    throw NSError(domain: "AIManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "AI generation requires iOS 26.0 or newer."])
                }
            } catch {
                return .failure(error)
            }
        }

        let taskResult = await withTaskCancellationHandler {
            await backgroundTask.result
        } onCancel: {
            backgroundTask.cancel()
        }

        let finalResult: Result<Data, Error>
        switch taskResult {
        case .success(let inner): finalResult = inner
        case .failure(let error): finalResult = .failure(error)
        }

        if case .failure(let error) = finalResult, error is CancellationError {
            print("ℹ️ AIManager: Task for job \(jobID) was cancelled. No update will be performed.")
            return
        }

        do {
            guard let job = try mainContext.fetch(FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.id == jobID })).first else { return }

            switch finalResult {
            case .success(let resultData):
                // `resultData` вече е от тип `Data`, което съответства на `job.resultData`.
                job.resultData = resultData
                job.status = .completed
                
                // ... останалият код за обработка на успех и нотификации е непроменен ...
                let internalUserInfo = ["jobID": job.id]
                let notificationName: Notification.Name
                let notificationTitle: String
                let notificationBody: String
                
                switch job.jobType {
                case .menuGeneration:
                    notificationName = .aiMenuJobCompleted
                    notificationTitle = "✅ Menu Generated!"
                    notificationBody = "Your new AI-generated menu '\(job.inputParameters?.foodNameToGenerate ?? "your menu")' is ready."
                    
                case .foodItemDetail:
                    notificationName = .aiFoodDetailJobCompleted
                    notificationTitle = "✅ Nutrition Data Ready!"
                    notificationBody = "AI-generated nutrition details for '\(job.inputParameters?.foodNameToGenerate ?? "your item")' are now available."
                    
                case .recipeGeneration:
                    notificationName = .aiRecipeJobCompleted
                    notificationTitle = "✅ Recipe Generated!"
                    notificationBody = "Your new AI-generated recipe for '\(job.inputParameters?.foodNameToGenerate ?? "your dish")' is ready."
                    
                case .exerciseDetail:
                    notificationName = .aiExerciseDetailJobCompleted
                    notificationTitle = "✅ Exercise Details Ready!"
                    notificationBody = "AI-generated details for '\(job.inputParameters?.foodNameToGenerate ?? "your exercise")' are now available."
                    
                case .trainingPlan:
                    notificationName = .aiTrainingPlanJobCompleted
                    notificationTitle = "✅ Training Plan Generated!"
                    notificationBody = "Your new AI-generated training plan for \(job.profile?.name ?? "your profile") is ready."
                    
                case .trainingViewDailyPlan:
                    notificationName = .aiTrainingJobCompleted
                    notificationTitle = "✅ Daily Workouts Generated!"
                    notificationBody = "Your AI-generated workouts for today in Training View are ready."
                    
                case .dailyTreiningPlan:
                    notificationName = .aiTrainingJobCompleted
                    notificationTitle = "✅ One Daily Workouts Generated!"
                    notificationBody = "Your new AI-generated daily workouts for \(job.profile?.name ?? "your profile") are ready."
                    
                case .workoutGeneration:
                    notificationName = .aiWorkoutJobCompleted
                    notificationTitle = "✅ Workout Generated!"
                    notificationBody = "Your new AI-generated workout '\(job.inputParameters?.foodNameToGenerate ?? "Workout")' is ready."
                    
                case .mealPlan:
                    notificationName = .aiJobCompletedMealPlan
                    notificationTitle = "✅ Weekly Plan Ready!"
                    notificationBody = "Your new weekly meal plan for \(job.profile?.name ?? "your profile") is ready to be saved."
                    
                case .dailyMealPlan:
                    notificationName = .aiJobCompleted
                    notificationTitle = "✅ Daily Meals Generated!"
                    notificationBody = "Your AI-generated meals for today are ready to be added to your calendar."
                case .nutritionsDetailDailyMealPlan:
                    notificationTitle = "✅ Meals Generated!"
                    notificationName = .aiJobCompleted
                    notificationBody = "Your AI-generated meals for \(job.profile?.name ?? "your profile") are ready to be added for today."
                    
                case .createFoodWithAI:
                    notificationName = .aiFoodDetailJobCompleted
                    notificationTitle = "✅ New Food Created!"
                    notificationBody = "The food item '\(job.inputParameters?.foodNameToGenerate ?? "New Food")' has been created with AI-generated data."
                case .createExerciseWithAI:
                    notificationName = .aiExerciseDetailJobCompleted
                    notificationTitle = "✅ New Exercise Created!"
                    notificationBody = "The exercise '\(job.inputParameters?.foodNameToGenerate ?? "New Exercise")' has been created with AI-generated data."
                }
                
                NotificationCenter.default.post(name: notificationName, object: nil, userInfo: internalUserInfo)
                print("▶️ AIManager: Posted internal \(notificationName.rawValue) for job \(job.id).")
                
                if let profile = job.profile {
                    _ = try? await NotificationManager.shared.scheduleNotification(
                        title: notificationTitle,
                        body: notificationBody, timeInterval: 1,
                        userInfo: [
                            "generationJobID": job.id.uuidString,
                            "jobType": job.jobType.rawValue
                        ],
                        profileID: profile.id
                    )
                }
                
            case .failure(let error):
                job.status = .failed
                job.failureReason = error.localizedDescription
                print("❌ AIManager: Generation task failed: \(error)")
            }

            try mainContext.save()

            await self.fetchJobs()
//            await self.scheduleNextIfIdle() // 🧠 пусни следващия pending ако има
            NotificationCenter.default.post(name: .aiJobStatusDidChange, object: nil)
        } catch {
            print("❌ AIManager: Could not update job \(jobID) on main thread: \(error)")
        }
    }
    // END OF CHANGE

    
    // ... (savePlanFromJob и другите помощни методи остават същите) ...
    
    func savePlanFromJob(_ job: AIGenerationJob) async throws {
        guard let result = job.result,
              let container = self.modelContainer,
              let profileID = job.profile?.persistentModelID else { return }
        
        if #available(iOS 26.0, *) {
            let planner = USDAWeeklyMealPlanner(container: container)
            _ = try await planner.savePlan(from: result, for: profileID, onLog: { print("[AI Save] \($0)") })
        } else {
            throw NSError(domain: "AIManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Saving meal plans requires iOS 26.0 or newer."])
        }
        
        await deleteJob(job)
    }
    
    // START OF CHANGE: deleteJob(_:)
    @MainActor
    func deleteJob(_ job: AIGenerationJob) async {
        guard let context = modelContainer?.mainContext else { return }

        let idToDelete = job.id

        if let taskToCancel = runningTasks[idToDelete] {
            taskToCancel.cancel()
            await globalTaskManager.cancelAllTasks()
            runningTasks[idToDelete] = nil
            print("✅ AIManager: Cancelled running task for job \(idToDelete).")
        }

        self.jobs.removeAll { $0.id == idToDelete }

        let descriptor = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.id == idToDelete })

        do {
            if let jobToDeleteInContext = try context.fetch(descriptor).first {
                context.delete(jobToDeleteInContext)
                try context.save()
                print("✅ AIManager: Successfully deleted job \(idToDelete).")
            } else {
                print("⚠️ AIManager: Job \(idToDelete) not found in context for deletion (might be already gone).")
            }
        } catch {
            print("❌ AIManager: Failed to save after deleting job \(idToDelete): \(error)")
        }

        await fetchJobs()
        await scheduleNextIfIdle() // 🧠 продължи опашката
    }
    // END OF CHANGE

    
    // START OF CHANGE: deleteJob(byID:)
    @MainActor
    func deleteJob(byID jobID: UUID) async {
        guard let context = modelContainer?.mainContext else { return }

        if let taskToCancel = runningTasks[jobID] {
            taskToCancel.cancel()
            await globalTaskManager.cancelAllTasks()
            runningTasks[jobID] = nil
            print("✅ AIManager: Cancelled running task for job with ID \(jobID).")
        }

        let descriptor = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.id == jobID })
        do {
            if let jobToDelete = try context.fetch(descriptor).first {
                await deleteJob(jobToDelete) // тук вече ще извика scheduleNextIfIdle()
            } else {
                print("⚠️ AIManager: Job with ID \(jobID) not found for deletion by ID.")
                self.jobs.removeAll { $0.id == jobID }
                await fetchJobs()
                await scheduleNextIfIdle()
            }
        } catch {
            print("❌ AIManager: Failed to fetch job by ID for deletion: \(error)")
            await fetchJobs()
            await scheduleNextIfIdle()
        }
    }
   
    // --- НАЧАЛО НА ПРОМЯНАТА ---
    @MainActor
    func pauseJob(_ job: AIGenerationJob) async {
        guard let context = modelContainer?.mainContext else { return }
        let jobID = job.id
        print("⏸️ AIManager: Attempting to pause and re-queue job \(jobID)...")

        // 1. Намираме и прекратяваме активната задача, за да освободим мениджъра
        if let taskToCancel = runningTasks[jobID] {
            taskToCancel.cancel()
            await globalTaskManager.cancelAllTasks()
            runningTasks[jobID] = nil
            print("  - Cancelled running task for job \(jobID).")
        }

        // 2. Актуализираме задачата в SwiftData, за да я преместим в края и да нулираме прогреса
        let descriptor = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.id == jobID })
        do {
            if let jobToRequeue = try context.fetch(descriptor).first {
                jobToRequeue.status = .pending
                // Преместваме я в края на опашката, като обновяваме датата на създаване
                jobToRequeue.creationDate = .now
                // Нулираме прогреса, за да започне отначало следващия път
                jobToRequeue.intermediateResultData = nil
                
                try context.save()
                print("  - Job \(jobID) status set to .pending, moved to end of queue, and progress reset.")
            }
        } catch {
            print("❌ AIManager: Failed to update job for re-queuing: \(error)")
        }

        // 3. Опресняваме списъка със задачи в UI
        await fetchJobs()

        // 4. Тъй като мениджърът вече е свободен, стартираме следващата задача в опашката
        await scheduleNextIfIdle()
    }
    // --- КРАЙ НА ПРОМЯНАТА ---

    @MainActor
    func prioritizeJob(_ job: AIGenerationJob) async {
        guard let context = modelContainer?.mainContext else { return }
        let jobToPrioritizeID = job.id
        print("▶️ AIManager: Prioritizing job \(jobToPrioritizeID)...")

        // 1. Намираме и прекратяваме текущо активната задача (ако има такава).
        if let runningJobID = runningTasks.keys.first, let runningTask = runningTasks[runningJobID] {
            runningTask.cancel()
            await globalTaskManager.cancelAllTasks()
            runningTasks.removeValue(forKey: runningJobID)
            print("  - Cancelled running task for job \(runningJobID).")
            
            // Намираме съответния обект и му сменяме статуса.
            let descriptor = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.id == runningJobID })
            if let jobToPause = try? context.fetch(descriptor).first {
                jobToPause.status = .pending
            }
        }

        // 2. Запазваме промените (ако има такива, напр. паузираната задача).
        do {
            if context.hasChanges {
                try context.save()
                print("  - Saved state changes before prioritization.")
            }
        } catch {
            print("❌ AIManager: Failed to save context during prioritization: \(error)")
        }

        // 3. Опресняваме UI-то и веднага стартираме приоритизираната задача.
        await fetchJobs()
        
        let descriptor = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.id == jobToPrioritizeID })
        if let jobToLaunch = try? context.fetch(descriptor).first {
            print("  - Immediately launching prioritized job \(jobToLaunch.id).")
            // Директно извикваме launch, тъй като сме освободили опашката.
            launchGenerationTask(for: jobToLaunch)
        } else {
            // Резервен вариант, ако задачата не бъде намерена - просто планираме следващата.
            print("  - ⚠️ Prioritized job not found, scheduling next available.")
            await scheduleNextIfIdle()
        }
    }
    
    
    @discardableResult
    func applyAndSaveDailyPlan(jobID: UUID) async -> Bool {
        print("▶️ AIManager: Starting applyAndSaveDailyPlan for job \(jobID)")
        guard let context = modelContainer?.mainContext else {
            print("❌ AIManager: Cannot apply plan, model context not available.")
            return false
        }
        
        let descriptor = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.id == jobID })
        guard let job = (try? context.fetch(descriptor))?.first,
              let preview = job.result,
              let profile = job.profile,
              let dayData = preview.days.first else {
            print("❌ AIManager: Job, profile, or plan data not found for applying daily plan.")
            if let jobToDelete = (try? context.fetch(descriptor))?.first {
                await deleteJob(jobToDelete)
            }
            return false
        }
        
        print("✅ AIManager: Applying daily plan from job \(jobID) for profile '\(profile.name)'...")
        
        let targetDate = Date()
        print("   - Target date is: \(targetDate.formatted(date: .long, time: .shortened))")
        let existingMealsForTargetDate = await CalendarViewModel.shared.meals(forProfile: profile, on: targetDate)
        print("   - Found \(existingMealsForTargetDate.count) existing meal events for the target date.")
        
        for previewMeal in dayData.meals {
            print("   - Processing generated meal: '\(previewMeal.name)'...")
            
            let mealTemplate: Meal?
            
            if let templateFromProfile = profile.meals.first(where: { $0.name == previewMeal.name }) {
                mealTemplate = templateFromProfile
                print("     - Found permanent template for '\(previewMeal.name)'.")
            } else if let templateFromExistingEvent = existingMealsForTargetDate.first(where: { $0.name == previewMeal.name }) {
                mealTemplate = templateFromExistingEvent
                print("     - Found temporary (existing event) template for '\(previewMeal.name)'.")
            } else {
                mealTemplate = previewMeal.startTime.map { Meal(name: previewMeal.name, startTime: $0, endTime: $0.addingTimeInterval(3600)) }
            }
            
            guard let finalTemplate = mealTemplate else {
                print("     - ⚠️ Skipping meal '\(previewMeal.name)', no permanent or temporary template found to determine times.")
                continue
            }
            
            let targetMeal = finalTemplate.detached(for: targetDate)
            let existingMealEvent = existingMealsForTargetDate.first { $0.name == targetMeal.name }
            
            var finalFoods: [FoodItem: Double] = [:]
            print("     - Resolving \(previewMeal.items.count) food items for this meal:")
            for item in previewMeal.items {
                let desc = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.name == item.name && !$0.isUserAdded })
                if let food = (try? context.fetch(desc))?.first {
                    finalFoods[food] = item.grams
                    print("       - ✅ Resolved '\(food.name)' (\(item.grams)g)")
                } else {
                    print("       - ❌ Could not resolve '\(item.name)' from database.")
                }
            }
            
            let payload = invisiblePayload(for: finalFoods)
            print("     - Generated payload. Calling createEvent in CalendarViewModel...")
            
            let (success, eventID) = await CalendarViewModel.shared.createEvent(
                forProfile: profile,
                startDate: targetMeal.startTime,
                endDate: targetMeal.endTime,
                title: targetMeal.name,
                invisiblePayload: payload,
                existingEventID: existingMealEvent?.calendarEventID
            )
            print("     - CalendarViewModel.createEvent finished. Success: \(success), Event ID: \(eventID ?? "N/A")")
        }
        
        print("   - Posting .mealTimeDidChange notification.")
        NotificationCenter.default.post(name: .mealTimeDidChange, object: nil)
        print("✅ AIManager: Daily plan applied successfully and job deleted.")
        return true
    }
    
    @discardableResult
    func applyAndSaveDailyTrainingPlan(jobID: UUID) async -> Bool {
        print("▶️ AIManager: Starting applyAndSaveDailyTrainingPlan for job \(jobID)")
        guard let context = modelContainer?.mainContext else {
            print("❌ AIManager: Cannot apply plan, model context not available.")
            return false
        }
        
        let descriptor = FetchDescriptor<AIGenerationJob>(predicate: #Predicate { $0.id == jobID })
        guard let job = (try? context.fetch(descriptor))?.first,
              let data = job.resultData,
              let draft = (try? JSONDecoder().decode(TrainingPlanDraft.self, from: data)),
              let profile = job.profile,
              let dayData = draft.days.first else {
            print("❌ AIManager: Job, profile, or plan data not found for applying daily training plan.")
            if let jobToDelete = (try? context.fetch(descriptor))?.first { await deleteJob(jobToDelete) }
            return false
        }
        
        print("✅ AIManager: Applying daily training plan from job \(jobID) for profile '\(profile.name)'...")
        
        let targetDate = Date()
        print("   - Target date is: \(targetDate.formatted(date: .long, time: .shortened))")
        let existingTrainingsForTargetDate = await CalendarViewModel.shared.trainings(forProfile: profile, on: targetDate)
        print("   - Found \(existingTrainingsForTargetDate.count) existing training events for the target date.")
        
        for generatedTraining in dayData.trainings {
            print("   - Processing generated workout: '\(generatedTraining.name)'...")
            
            guard let trainingTemplate = profile.trainings.first(where: { $0.name == generatedTraining.name }) else {
                print("     - ⚠️ Skipping workout '\(generatedTraining.name)', no permanent template found to determine times.")
                continue
            }
            
            let targetTraining = trainingTemplate.detached(for: targetDate)
            let existingTrainingEvent = existingTrainingsForTargetDate.first { $0.name == targetTraining.name }
            targetTraining.calendarEventID = existingTrainingEvent?.calendarEventID
            
            let exercises = generatedTraining.exercises(using: context)
            
            if exercises.isEmpty {
                if let idToDelete = existingTrainingEvent?.calendarEventID {
                    _ = await CalendarViewModel.shared.deleteEvent(withIdentifier: idToDelete)
                    print("     - 🗑️ Deleting existing empty workout event.")
                }
                continue
            }
            
            let tempTrainingForPayload = Training(name: "", startTime: Date(), endTime: Date())
            tempTrainingForPayload.updateNotes(exercises: exercises, detailedLog: nil)
            let payload = OptimizedInvisibleCoder.encode(from: tempTrainingForPayload.notes ?? "")
            
            print("     - Creating/updating event via CalendarViewModel...")
            let (success, eventID) = await CalendarViewModel.shared.createOrUpdateTrainingEvent(
                forProfile: profile,
                training: targetTraining,
                exercisesPayload: payload
            )
            print("     - CalendarViewModel.createOrUpdateTrainingEvent finished. Success: \(success), Event ID: \(eventID ?? "N/A")")
        }
        
        print("   - Posting .forceCalendarReload notification.")
        NotificationCenter.default.post(name: .forceCalendarReload, object: nil)
        
        print("✅ AIManager: Daily training plan applied successfully and job deleted.")
        return true
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
    
    @available(iOS 26.0, *)
    @MainActor
    private func generateFoodDetailDataOnMain(container: ModelContainer, foodName: String) async throws -> Data {
        let context = ModelContext(container)
        let generator = AIFoodDetailGenerator(container: container)
        // Тази функция сега ще пропусне сигнала за прекратяване надолу към generateDetails
        let response = try await generator.generateDetailsRetrying(
            for: foodName,
            ctx: context,
            onLog: { print("[AI BG FoodItem] \($0)") },
            attempts: 5,
            baseBackoffMs: 700
        )
        return try JSONEncoder().encode(response)
    }
    
    @available(iOS 26.0, *)
    @MainActor
    private func generateExerciseDetailDataOnMain(container: ModelContainer, exerciseName: String) async throws -> Data {
        let context = ModelContext(container)
        let generator = AIExerciseDetailGenerator(container: container)
        let response = try await generator.generateDetails(
            for: exerciseName,
            ctx: context,
            onLog: { logMessage in
                print("[AI BG Exercise] \(logMessage)")
            }
        )
        return try JSONEncoder().encode(response)
    }
    
    @available(iOS 26.0, *)
    @MainActor
    private func createFoodWithAIDataOnMain(container: ModelContainer, foodName: String, itemID: UUID) async throws -> Data {
        let context = ModelContext(container)
        let generator = AIFoodDetailGenerator(container: container)
        let dto = try await generator.generateDetailsRetrying(for: foodName, ctx: context, onLog: { print("[AI BG Food Create] \($0)") })

        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { $0.id == itemID }
        )
        guard let foodToUpdate = try context.fetch(descriptor).first else {
            throw NSError(domain: "AIManager", code: 12, userInfo: [NSLocalizedDescriptionKey: "Could not find pre-created FoodItem with ID \(itemID)."])
        }
        
        await foodToUpdate.update(from: dto)
        if let generatedAyurveda = dto.ayurveda {
            AyurvedaUserProfileStore.upsert(
                generated: generatedAyurveda,
                editorForm: generatedAyurveda.editorForm,
                for: foodToUpdate,
                context: context
            )
        }
        try context.save()
        
        return Data()
    }
    
    @available(iOS 26.0, *)
    @MainActor
    private func createExerciseWithAIDataOnMain(container: ModelContainer, exerciseName: String, itemID: UUID) async throws -> Data {
        let context = ModelContext(container)
        let generator = AIExerciseDetailGenerator(container: container)
        let dto = try await generator.generateDetails(for: exerciseName, ctx: context, onLog: { print("[AI BG Exercise Create] \($0)") })

        let descriptor = FetchDescriptor<ExerciseItem>(
            predicate: #Predicate { $0.id == itemID }
        )
        guard let exerciseToUpdate = try context.fetch(descriptor).first else {
            throw NSError(domain: "AIManager", code: 14, userInfo: [NSLocalizedDescriptionKey: "Could not find pre-created ExerciseItem with ID \(itemID)."])
        }
        
        await exerciseToUpdate.update(from: dto)
        try context.save()
        
        return Data()
    }
    
    // --- START OF CHANGE (2/2): New `resumeInterruptedJobs` and `scheduleNextIfIdle` ---
    // NEW private method
    private func resumeInterruptedJobs() async {
        guard let context = modelContainer?.mainContext else { return }

        // Използваме jobs масива, който вече е зареден в паметта.
        let interruptedJobs = self.jobs.filter { $0.status == .running }

        if !interruptedJobs.isEmpty {
            print(" AIManager: Found \(interruptedJobs.count) interrupted job(s) from a previous session.")
            for job in interruptedJobs {
                print("   - Resetting job \(job.id) from .running to .pending")
                job.status = .pending
            }

            do {
                try context.save()
                print(" AIManager: Successfully saved status change for interrupted jobs.")
            } catch {
                print("❌ AIManager: Failed to save status for interrupted jobs: \(error)")
            }
            // Обновяваме масива в паметта, за да отрази промяната веднага.
            await fetchJobs()
        }
    }

    @MainActor
    private func scheduleNextIfIdle() async {
        // Ако вече върви задача — нищо не правим.
        guard runningTasks.isEmpty else { return }
        guard let context = modelContainer?.mainContext else { return }

        do {
            // Взимаме по-голям сет и филтрираме в паметта, за да избегнем enum в #Predicate
            let descriptor = FetchDescriptor<AIGenerationJob>(
                sortBy: [SortDescriptor(\.creationDate, order: .forward)]
            )
            // Може да ограничиш и с .fetchLimit, ако имаш много записи
            let all = try context.fetch(descriptor)

            // Намери най-стария pending
            if let nextJob = all.first(where: { $0.status == .pending }) {
                launchGenerationTask(for: nextJob)
            }
        } catch {
            print("❌ AIManager: scheduleNextIfIdle fetch failed: \(error)")
        }
    }
    // --- END OF CHANGE (2/2) ---
}
