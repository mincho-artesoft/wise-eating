import Foundation
import SwiftData

@Model
final class AIGenerationJob {
    @Attribute(.unique) var id: UUID
    var creationDate: Date
    var status: Status
    var jobType: JobType
    
    // ❗ ТУК: БЕЗ inverse, само deleteRule
    @Relationship(deleteRule: .nullify)
    var profile: Profile?
    
    var inputParametersData: Data?
    var resultData: Data?
    var failureReason: String?

    @Attribute var intermediateResultData: Data?

    init(profile: Profile, inputParams: InputParameters, jobType: JobType) {
        self.id = UUID()
        self.creationDate = .now
        self.status = .pending
        self.profile = profile
        self.inputParametersData = try? JSONEncoder().encode(inputParams)
        self.jobType = jobType
    }
    
    enum Status: String, Codable {
        case pending, running, completed, failed
    }

    enum JobType: String, Codable, Sendable {
        case dailyMealPlan = "Daily Meal Plan"
        case mealPlan = "Meal Plan"
        case nutritionsDetailDailyMealPlan = "Nutrition Detail Meal Plan"
        case foodItemDetail = "Food Item Detail"
        case recipeGeneration = "Recipe Generation"
        case menuGeneration = "Menu Generation"
        case exerciseDetail = "Exercise Detail"
        case dietGeneration = "Diet Generation"
        case trainingPlan = "Training Plan"
        case workoutGeneration = "Workout Generation"
        case createFoodWithAI = "Create Food With AI"
        case createExerciseWithAI = "Create Exercise With AI"
        case trainingViewDailyPlan = "Training View Daily Plan"
        case dailyTreiningPlan = "Daily Training Plan"
    }

    struct InputParameters: Codable, Sendable {
        let startDate: Date?
        let numberOfDays: Int?
        let specificMeals: [String]?
        let mealsToFill: [Int: [String]]?
        let existingMeals: [Int: [MealPlanPreviewMeal]]?
        let selectedPrompts: [String]?
        let mealTimings: [String: Date]?
        let foodNameToGenerate: String?
        public var trainingDays: Int?
        public var trainingTimes: [Int: Date]?
        public var plannedWorkoutTimes: [String: Date]?
        public var workoutsToFill: [Int: [String]]?
        public var existingWorkouts: [Int: [TrainingPlanWorkoutDraft]]?
        let preCreatedItemID: String?
    }
    
    var inputParameters: InputParameters? {
        guard let data = inputParametersData else { return nil }
        return try? JSONDecoder().decode(InputParameters.self, from: data)
    }
    
    var result: MealPlanPreview? {
        guard let data = resultData else { return nil }
        return try? JSONDecoder().decode(MealPlanPreview.self, from: data)
    }
}
