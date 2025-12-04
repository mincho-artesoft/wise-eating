// ==== FILE: WiseEating/Main/Notification/NavigationCoordinator.swift ====
import Foundation
import SwiftUI

@MainActor
class NavigationCoordinator: ObservableObject {

    static let shared = NavigationCoordinator()

    // Profile & Content Navigation
    @Published var pendingProfileID: UUID?
    @Published var pendingShoppingListID: UUID?
    @Published var pendingMealID: UUID?
    @Published var pendingMealDate: Date?
    @Published var pendingTrainingID: UUID?
    @Published var pendingTrainingDate: Date?
    @Published var pendingTrainingName: String?

    // AI Plan Navigation
    @Published var pendingTab: AppTab?
    @Published var pendingAIPlanPreview: MealPlanPreview?
    @Published var profileForPendingAIPlan: Profile?
    @Published var sourceAIGenerationJobID: UUID?
    @Published var pendingAIPlanJobType: AIGenerationJob.JobType?
    @Published var pendingApplyDailyMealPlanJobID: UUID? = nil
    @Published var pendingApplyDailyTreaningPlanJobID: UUID? = nil

    // AI Food/Recipe Navigation
    @Published var pendingAIFoodDetailResponse: FoodItemDTO?
    @Published var sourceAIFoodDetailJobID: UUID?
    @Published var pendingAIRecipe: FoodItemCopy?
    @Published var sourceAIRecipeJobID: UUID?
   
    @Published var pendingAIMenu: FoodItemCopy?
    @Published var sourceAIMenuJobID: UUID?

    @Published var pendingAIExerciseDetailResponse: ExerciseItemDTO?
    @Published var sourceAIExerciseDetailJobID: UUID?
    
    @Published var pendingAIDietResponse: AIDietResponseDTO?
    @Published var sourceAIDietJobID: UUID?
    @Published var pendingAIDietWireResponse: AIDietResponseWireDTO?

    @Published var pendingAITrainingPlan: TrainingPlanDraft?
    @Published var sourceAITrainingPlanJobID: UUID?
    
    @Published var pendingAIWorkout: ExerciseItemCopy?
    @Published var sourceAIWorkoutJobID: UUID?
    
    // --- НАЧАЛО НА ПРОМЯНАТА ---
    @Published var pendingBadgeProfileID: UUID?
    // --- КРАЙ НА ПРОМЯНАТА ---

    // Daily AI Generator Trigger
    @Published var triggerDailyAIGeneratorForProfile: Profile? = nil
    
    private init() {}
}
