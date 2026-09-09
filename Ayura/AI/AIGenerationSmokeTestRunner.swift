#if DEBUG
import Foundation
import FoundationModels
import SwiftData
import Darwin

@available(iOS 26.0, *)
@MainActor
enum AIGenerationSmokeTestRunner {
    private struct ProfileSnapshot: Codable {
        let name: String
        let ageYears: Int
        let ageMonths: Int
        let gender: String
        let weightKg: Double
        let heightCm: Double
        let allergens: [String]
        let priorityVitamins: [String]
        let priorityMinerals: [String]
        let trainingSchedule: [String]
        let ayurvedaConstitution: String?
    }

    private struct CaseInput: Codable {
        let entryPoint: String
        let values: [String]
        let structure: [Int: [String]]?
        let profile: ProfileSnapshot?
        let note: String
    }

    private struct CaseRecord: Codable {
        let id: String
        let generator: String
        let variant: String
        let startedAt: Date
        let finishedAt: Date
        let status: String
        let inputJSON: String
        let outputJSON: String?
        let validation: [String: String]
        let error: String?
    }

    private static let reportName = "ai-generation-smoke-report.json"
    private static let testProfilePrefix = "AI Generation Test — "

    static func run(container: ModelContainer) async {
        let arguments = ProcessInfo.processInfo.arguments
        let group = argumentValue(after: "-aiSmokeGroup", in: arguments) ?? "all"
        let shouldReset = arguments.contains("-aiSmokeReset")
        print("AI_SMOKE|BEGIN|group=\(group)|availability=\(SystemLanguageModel.default.availability)")

        guard case .available = SystemLanguageModel.default.availability else {
            writeReport([CaseRecord(
                id: "availability",
                generator: "Apple Foundation Models",
                variant: "device",
                startedAt: .now,
                finishedAt: .now,
                status: "failed",
                inputJSON: "{}",
                outputJSON: nil,
                validation: [:],
                error: "SystemLanguageModel unavailable: \(SystemLanguageModel.default.availability)"
            )])
            finish(group: group)
        }

        let context = ModelContext(container)
        context.autosaveEnabled = false
        cleanupInterruptedTests(in: context)
        let initialFoodIDs = Set(
            ((try? context.fetch(FetchDescriptor<FoodItem>())) ?? []).map(\.id)
        )
        let initialExerciseIDs = Set(
            ((try? context.fetch(FetchDescriptor<ExerciseItem>())) ?? []).map(\.id)
        )

        let profiles: (standard: Profile, ayurvedic: Profile)
        do {
            profiles = try makeProfiles(in: context)
        } catch {
            writeReport([CaseRecord(
                id: "profile-setup",
                generator: "Test setup",
                variant: group,
                startedAt: .now,
                finishedAt: .now,
                status: "failed",
                inputJSON: "{}",
                outputJSON: nil,
                validation: [:],
                error: error.localizedDescription
            )])
            finish(group: group)
        }

        var records = shouldReset ? [] : readReport()
        records.removeAll { group == "all" || groupForCase($0.id) == group }

        if group == "all" || group == "food" {
            let generator = AIFoodDetailGenerator(container: container)
            records.append(await capture(
                id: "food-standard",
                generator: "Food detail",
                variant: "standard",
                input: CaseInput(
                    entryPoint: "AIFoodDetailGenerator.generateDetailsRetrying",
                    values: ["foodName=Greek yogurt, plain"],
                    structure: nil,
                    profile: nil,
                    note: "The food name is expanded into independent structured prompts for nutrients, safety, and Ayurveda fields."
                )
            ) {
                let dto = try await generator.generateDetailsRetrying(
                    for: "Greek yogurt, plain",
                    ctx: context,
                    onLog: logger("food-standard")
                )
                return (dto, foodValidation(dto))
            })
            persist(records)

            records.append(await capture(
                id: "food-ayurvedic",
                generator: "Food detail",
                variant: "ayurvedic",
                input: CaseInput(
                    entryPoint: "AIFoodDetailGenerator.generateDetailsRetrying",
                    values: ["foodName=Ghee"],
                    structure: nil,
                    profile: nil,
                    note: "Same complete schema as regular food, with traditional fields populated when established."
                )
            ) {
                let dto = try await generator.generateDetailsRetrying(
                    for: "Ghee",
                    ctx: context,
                    onLog: logger("food-ayurvedic")
                )
                return (dto, foodValidation(dto))
            })
            persist(records)
        }

        if group == "all" || group == "recipe" {
            records.append(await recipeCase(
                id: "recipe-standard",
                name: "Mediterranean chicken and rice bowl",
                variant: "standard",
                profile: profiles.standard,
                container: container,
                context: context
            ))
            persist(records)
            records.append(await recipeCase(
                id: "recipe-ayurvedic",
                name: "Mung dal kitchari",
                variant: "ayurvedic",
                profile: profiles.ayurvedic,
                container: container,
                context: context
            ))
            persist(records)
        }

        if group == "all" || group == "menu" {
            records.append(await menuCase(
                id: "menu-standard",
                prompts: ["Balanced Mediterranean lunch", "High protein", "Avoid nuts"],
                variant: "standard",
                profile: profiles.standard,
                container: container,
                context: context
            ))
            persist(records)
            records.append(await menuCase(
                id: "menu-ayurvedic",
                prompts: ["Warm Vata-pacifying Ayurvedic dinner", "Easy to digest", "Avoid nuts"],
                variant: "ayurvedic",
                profile: profiles.ayurvedic,
                container: container,
                context: context
            ))
            persist(records)
        }

        if group == "all" || group == "meal" {
            let structure = [1: ["Breakfast", "Lunch", "Dinner"]]
            records.append(await mealPlanCase(
                id: "meal-plan-standard",
                prompts: ["Balanced one-day meal plan", "Prioritize the nutrients selected in the profile"],
                structure: structure,
                variant: "standard",
                profile: profiles.standard,
                container: container,
                context: context
            ))
            persist(records)
            records.append(await mealPlanCase(
                id: "meal-plan-ayurvedic",
                prompts: ["One-day Vata-pacifying Ayurvedic meal plan", "Warm and easy to digest"],
                structure: structure,
                variant: "ayurvedic",
                profile: profiles.ayurvedic,
                container: container,
                context: context
            ))
            persist(records)
        }

        if group == "all" || group == "exercise" {
            let generator = AIExerciseDetailGenerator(container: container)
            records.append(await capture(
                id: "exercise-standard",
                generator: "Exercise detail",
                variant: "standard",
                input: CaseInput(
                    entryPoint: "AIExerciseDetailGenerator.generateDetails",
                    values: ["exerciseName=Bodyweight squat"],
                    structure: nil,
                    profile: nil,
                    note: "The generator must populate duration, slug, level, and safety fields while leaving yoga-only fields empty."
                )
            ) {
                let dto = try await generator.generateDetails(
                    for: "Bodyweight squat",
                    ctx: context,
                    onLog: logger("exercise-standard")
                )
                return (dto, exerciseValidation(dto, expectsYoga: false))
            })
            persist(records)
            records.append(await capture(
                id: "exercise-yoga",
                generator: "Exercise detail",
                variant: "yoga",
                input: CaseInput(
                    entryPoint: "AIExerciseDetailGenerator.generateDetails",
                    values: ["exerciseName=Tree Pose (Vrikshasana)"],
                    structure: nil,
                    profile: nil,
                    note: "The generator must additionally populate Sanskrit, family, breath, drishti, contraindications, and dosha fields."
                )
            ) {
                let dto = try await generator.generateDetails(
                    for: "Tree Pose (Vrikshasana)",
                    ctx: context,
                    onLog: logger("exercise-yoga")
                )
                return (dto, exerciseValidation(dto, expectsYoga: true))
            })
            persist(records)
        }

        if group == "all" || group == "workout" {
            records.append(await workoutCase(
                id: "workout-standard",
                prompts: ["30-minute beginner full-body strength workout", "No equipment"],
                variant: "standard",
                profile: profiles.standard,
                container: container,
                context: context
            ))
            persist(records)
            records.append(await workoutCase(
                id: "workout-yoga",
                prompts: ["30-minute gentle Vata-pacifying evening yoga session", "Beginner friendly"],
                variant: "yoga",
                profile: profiles.ayurvedic,
                container: container,
                context: context
            ))
            persist(records)
        }

        if group == "all" || group == "training" {
            records.append(await trainingPlanCase(
                id: "training-plan-standard",
                prompts: ["Beginner full-body strength", "No equipment"],
                structure: [1: ["Morning Strength"]],
                variant: "standard",
                profile: profiles.standard,
                container: container,
                context: context
            ))
            persist(records)
            records.append(await trainingPlanCase(
                id: "training-plan-yoga",
                prompts: ["Gentle Vata-pacifying yoga", "Evening recovery", "Beginner friendly"],
                structure: [1: ["Evening Yoga"]],
                variant: "yoga",
                profile: profiles.ayurvedic,
                container: container,
                context: context
            ))
            persist(records)
        }

        cleanup(
            in: context,
            initialFoodIDs: initialFoodIDs,
            initialExerciseIDs: initialExerciseIDs,
            profileIDs: [profiles.standard.id, profiles.ayurvedic.id]
        )
        print("AI_SMOKE|REPORT|\(reportURL().path)")
        finish(group: group)
    }

    private static func recipeCase(
        id: String,
        name: String,
        variant: String,
        profile: Profile,
        container: ModelContainer,
        context: ModelContext
    ) async -> CaseRecord {
        let job = makeJob(profile: profile, type: .recipeGeneration, context: context)
        let generator = AIRecipeGenerator(container: container)
        return await capture(
            id: id,
            generator: "Recipe",
            variant: variant,
            input: CaseInput(
                entryPoint: "AIRecipeGenerator.generateAndResolveRecipeDTO",
                values: ["recipeName=\(name)"],
                structure: nil,
                profile: nil,
                note: "The recipe name becomes a conceptual recipe and its ingredients are resolved against the food catalogue."
            )
        ) {
            let dto = try await generator.generateAndResolveRecipeDTO(
                for: name,
                jobID: job.persistentModelID,
                onLog: logger(id)
            )
            return (dto, [
                "ingredientCount": String(dto.ingredients.count),
                "prepTimeMinutes": String(dto.prepTimeMinutes),
                "hasDescription": String(!dto.description.isEmpty)
            ])
        }
    }

    private static func menuCase(
        id: String,
        prompts: [String],
        variant: String,
        profile: Profile,
        container: ModelContainer,
        context: ModelContext
    ) async -> CaseRecord {
        let job = makeJob(profile: profile, type: .menuGeneration, context: context)
        let generator = AIMenuGenerator(container: container)
        return await capture(
            id: id,
            generator: "Menu",
            variant: variant,
            input: CaseInput(
                entryPoint: "AIMenuGenerator.generateMenuDetails",
                values: prompts,
                structure: [1: ["AI-selected meal slot"]],
                profile: snapshot(profile),
                note: "The menu delegates ingredient selection to the profile-aware meal planner."
            )
        ) {
            let dto = try await generator.generateMenuDetails(
                jobID: job.persistentModelID,
                for: profile,
                prompts: prompts,
                onLog: logger(id)
            )
            return (dto, [
                "ingredientCount": String(dto.ingredients.count),
                "prepTimeMinutes": String(dto.prepTimeMinutes),
                "hasName": String(!(dto.name ?? "").isEmpty)
            ])
        }
    }

    private static func mealPlanCase(
        id: String,
        prompts: [String],
        structure: [Int: [String]],
        variant: String,
        profile: Profile,
        container: ModelContainer,
        context: ModelContext
    ) async -> CaseRecord {
        let job = makeJob(profile: profile, type: .mealPlan, context: context)
        let planner = USDAWeeklyMealPlanner(container: container)
        return await capture(
            id: id,
            generator: "Meal plan",
            variant: variant,
            input: CaseInput(
                entryPoint: "USDAWeeklyMealPlanner.fillPlanDetails",
                values: prompts,
                structure: structure,
                profile: snapshot(profile),
                note: "Calories, protein, age safety, allergens, priority nutrients, meal structure, and Ayurveda context come from this profile/input."
            )
        ) {
            let preview = try await planner.fillPlanDetails(
                jobID: job.persistentModelID,
                profileID: profile.persistentModelID,
                daysAndMeals: structure,
                prompts: prompts,
                mealTimings: nil,
                onLog: logger(id)
            )
            return (preview, [
                "dayCount": String(preview.days.count),
                "mealCount": String(preview.days.flatMap(\.meals).count),
                "itemCount": String(preview.days.flatMap(\.meals).flatMap(\.items).count)
            ])
        }
    }

    private static func workoutCase(
        id: String,
        prompts: [String],
        variant: String,
        profile: Profile,
        container: ModelContainer,
        context: ModelContext
    ) async -> CaseRecord {
        let job = makeJob(profile: profile, type: .workoutGeneration, context: context)
        let generator = AIWorkoutGenerator(container: container)
        return await capture(
            id: id,
            generator: "Workout",
            variant: variant,
            input: CaseInput(
                entryPoint: "AIWorkoutGenerator.generateWorkout",
                values: prompts,
                structure: [1: ["Workout"]],
                profile: snapshot(profile),
                note: "The workout reuses the profile-aware training-plan generator, then generates its name and instructions."
            )
        ) {
            let dto = try await generator.generateWorkout(
                jobID: job.persistentModelID,
                profile: profile,
                prompts: prompts,
                onLog: logger(id)
            )
            return (dto, [
                "exerciseCount": String(dto.exercises.count),
                "durationSeconds": String(dto.totalDurationSeconds),
                "hasDescription": String(!dto.description.isEmpty)
            ])
        }
    }

    private static func trainingPlanCase(
        id: String,
        prompts: [String],
        structure: [Int: [String]],
        variant: String,
        profile: Profile,
        container: ModelContainer,
        context: ModelContext
    ) async -> CaseRecord {
        let job = makeJob(profile: profile, type: .trainingPlan, context: context)
        let generator = AITrainingPlanGenerator(container: container)
        return await capture(
            id: id,
            generator: "Training plan",
            variant: variant,
            input: CaseInput(
                entryPoint: "AITrainingPlanGenerator.fillPlanDetails",
                values: prompts,
                structure: structure,
                profile: snapshot(profile),
                note: "Age, weight, height, gender, usual training schedule, and yoga-specific Ayurveda preference context are supplied."
            )
        ) {
            let draft = try await generator.fillPlanDetails(
                jobID: job.persistentModelID,
                profileID: profile.persistentModelID,
                prompts: prompts,
                workoutsToFill: structure,
                existingWorkouts: nil,
                onLog: logger(id)
            )
            return (draft, [
                "dayCount": String(draft.days.count),
                "workoutCount": String(draft.days.flatMap(\.trainings).count)
            ])
        }
    }

    private static func capture<T: Encodable>(
        id: String,
        generator: String,
        variant: String,
        input: CaseInput,
        operation: () async throws -> (T, [String: String])
    ) async -> CaseRecord {
        let started = Date()
        let inputJSON = encodeString(input)
        print("AI_SMOKE|INPUT|\(id)|\(inputJSON)")
        do {
            let (output, validation) = try await operation()
            let outputJSON = encodeString(output)
            print("AI_SMOKE|OUTPUT|\(id)|\(outputJSON)")
            return CaseRecord(
                id: id,
                generator: generator,
                variant: variant,
                startedAt: started,
                finishedAt: .now,
                status: "passed",
                inputJSON: inputJSON,
                outputJSON: outputJSON,
                validation: validation,
                error: nil
            )
        } catch {
            print("AI_SMOKE|ERROR|\(id)|\(error.localizedDescription)")
            return CaseRecord(
                id: id,
                generator: generator,
                variant: variant,
                startedAt: started,
                finishedAt: .now,
                status: "failed",
                inputJSON: inputJSON,
                outputJSON: nil,
                validation: [:],
                error: error.localizedDescription
            )
        }
    }

    private static func foodValidation(_ dto: FoodItemDTO) -> [String: String] {
        [
            "isEdiblePresent": String(dto.isEdible != nil),
            "ageProvenancePresent": String(dto.ageProvenance != nil),
            "ageSourcePresent": String(dto.ageSource != nil),
            "ayurvedaPresent": String(dto.ayurveda != nil),
            "ayurvedaConfidence": dto.ayurveda.map { String(format: "%.2f", $0.confidenceAyur) } ?? "missing",
            "hasReferenceWeight": String((dto.other?.weightG?.value ?? 0) > 0)
        ]
    }

    private static func exerciseValidation(
        _ dto: ExerciseItemDTO,
        expectsYoga: Bool
    ) -> [String: String] {
        [
            "durationPresent": String(dto.durationSeconds != nil),
            "slugPresent": String(dto.slug != nil),
            "levelPresent": String(dto.level != nil),
            "contraindicationsFieldGenerated": String(dto.contraindications != nil),
            "yogaExpected": String(expectsYoga),
            "sanskritPresent": String(dto.sanskrit != nil),
            "familyPresent": String(dto.family != nil),
            "breathPresent": String(dto.breath != nil),
            "drishtiPresent": String(dto.drishti != nil),
            "doshaPresent": String(dto.dosha != nil),
            "doshaProvenancePresent": String(dto.doshaProvenance != nil)
        ]
    }

    private static func makeProfiles(
        in context: ModelContext
    ) throws -> (standard: Profile, ayurvedic: Profile) {
        let birthday = Calendar.current.date(byAdding: .year, value: -35, to: Date())
            ?? Date(timeIntervalSince1970: 0)
        let vitamins = try context.fetch(FetchDescriptor<Vitamin>())
        let minerals = try context.fetch(FetchDescriptor<Mineral>())
        let priorityVitamins = vitamins.filter { ["vitC", "vitD"].contains($0.key) }
        let priorityMinerals = minerals.filter { ["magnesium", "iron"].contains($0.key) }

        func make(_ suffix: String) -> Profile {
            Profile(
                name: testProfilePrefix + suffix,
                birthday: birthday,
                gender: "Female",
                weight: 68,
                height: 172,
                priorityVitamins: priorityVitamins,
                priorityMinerals: priorityMinerals,
                allergens: [.nuts]
            )
        }
        let standard = make("Standard")
        let ayurvedic = make("Ayurvedic")
        context.insert(standard)
        context.insert(ayurvedic)
        try context.save()

        AyurvedaConstitutionStore.save(
            AyurvedaConstitutionDraft(
                source: .selfDeclared,
                prakriti: AyurvedaDoshaDistribution(vata: 0.7, pitta: 0.2, kapha: 0.1),
                declaredTypeID: "vata",
                questionnaireAnswers: []
            ),
            for: ayurvedic.id
        )
        return (standard, ayurvedic)
    }

    private static func snapshot(_ profile: Profile) -> ProfileSnapshot {
        let clock = Date.FormatStyle(date: .omitted, time: .shortened)
        let schedule = profile.trainings.sorted { $0.startTime < $1.startTime }.map {
            let minutes = max(0, Int($0.endTime.timeIntervalSince($0.startTime) / 60))
            return "\($0.name), \($0.startTime.formatted(clock)), \(minutes) min"
        }
        let ayurveda = AyurvedaConstitutionStore.record(for: profile.id).map { record in
            let target = record.target()
            return String(
                format: "%@ — Vata %.0f%%, Pitta %.0f%%, Kapha %.0f%%",
                record.result.label,
                target.vata * 100,
                target.pitta * 100,
                target.kapha * 100
            )
        }
        return ProfileSnapshot(
            name: profile.name,
            ageYears: profile.age,
            ageMonths: profile.ageInMonths,
            gender: profile.gender,
            weightKg: profile.weight,
            heightCm: profile.height,
            allergens: profile.allergens.map(\.rawValue).sorted(),
            priorityVitamins: profile.priorityVitamins.map(\.name).sorted(),
            priorityMinerals: profile.priorityMinerals.map(\.name).sorted(),
            trainingSchedule: schedule,
            ayurvedaConstitution: ayurveda
        )
    }

    private static func makeJob(
        profile: Profile,
        type: AIGenerationJob.JobType,
        context: ModelContext
    ) -> AIGenerationJob {
        let params = AIGenerationJob.InputParameters(
            startDate: nil,
            numberOfDays: nil,
            specificMeals: nil,
            mealsToFill: nil,
            existingMeals: nil,
            selectedPrompts: nil,
            mealTimings: nil,
            foodNameToGenerate: nil,
            trainingDays: nil,
            trainingTimes: nil,
            plannedWorkoutTimes: nil,
            workoutsToFill: nil,
            existingWorkouts: nil,
            preCreatedItemID: nil
        )
        let job = AIGenerationJob(profile: profile, inputParams: params, jobType: type)
        context.insert(job)
        try? context.save()
        return job
    }

    private static func cleanupInterruptedTests(in context: ModelContext) {
        let profiles = (try? context.fetch(FetchDescriptor<Profile>())) ?? []
        for profile in profiles where profile.name.hasPrefix(testProfilePrefix) {
            AyurvedaConstitutionStore.delete(profileID: profile.id)
            context.delete(profile)
        }
        try? context.save()
    }

    private static func cleanup(
        in context: ModelContext,
        initialFoodIDs: Set<UUID>,
        initialExerciseIDs: Set<UUID>,
        profileIDs: [UUID]
    ) {
        let jobs = (try? context.fetch(FetchDescriptor<AIGenerationJob>())) ?? []
        for job in jobs where job.profile.map({ profileIDs.contains($0.id) }) == true {
            context.delete(job)
        }
        let profiles = (try? context.fetch(FetchDescriptor<Profile>())) ?? []
        for profile in profiles where profileIDs.contains(profile.id) {
            context.delete(profile)
        }
        let foods = (try? context.fetch(FetchDescriptor<FoodItem>())) ?? []
        for food in foods where !initialFoodIDs.contains(food.id) {
            context.delete(food)
        }
        let exercises = (try? context.fetch(FetchDescriptor<ExerciseItem>())) ?? []
        for exercise in exercises where !initialExerciseIDs.contains(exercise.id) {
            context.delete(exercise)
        }
        for profileID in profileIDs {
            AyurvedaConstitutionStore.delete(profileID: profileID)
        }
        do {
            try context.save()
            try SearchIndexStore.shared.rebuildIndexIfNeeded(context: context, force: true)
        } catch {
            print("AI_SMOKE|CLEANUP_ERROR|\(error.localizedDescription)")
        }
    }

    private static func logger(_ id: String) -> @Sendable (String) -> Void {
        { print("AI_SMOKE_LOG|\(id)|\($0)") }
    }

    private static func groupForCase(_ id: String) -> String {
        if id.hasPrefix("food-") { return "food" }
        if id.hasPrefix("recipe-") { return "recipe" }
        if id.hasPrefix("menu-") { return "menu" }
        if id.hasPrefix("meal-plan-") { return "meal" }
        if id.hasPrefix("exercise-") { return "exercise" }
        if id.hasPrefix("workout-") { return "workout" }
        if id.hasPrefix("training-plan-") { return "training" }
        return "other"
    }

    private static func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    private static func encodeString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func reportURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent(reportName)
    }

    private static func readReport() -> [CaseRecord] {
        guard let data = try? Data(contentsOf: reportURL()) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CaseRecord].self, from: data)) ?? []
    }

    private static func persist(_ records: [CaseRecord]) {
        writeReport(records.sorted { $0.id < $1.id })
    }

    private static func writeReport(_ records: [CaseRecord]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(records).write(to: reportURL(), options: .atomic)
        } catch {
            print("AI_SMOKE|REPORT_ERROR|\(error.localizedDescription)")
        }
    }

    private static func finish(group: String) -> Never {
        print("AI_SMOKE|COMPLETE|group=\(group)")
        fflush(stdout)
        exit(EXIT_SUCCESS)
    }
}
#endif
