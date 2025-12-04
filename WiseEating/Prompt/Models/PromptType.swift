import Foundation
import SwiftData

enum PromptType: String, Codable, CaseIterable {
    case mealPlan = "Meal Plan"
    case trainingPlan = "Training Plan"
    case nutritionsDetailМealPlan = "Nutrition Detail Meal Plan"
    case trainingViewМealPlan = "Training View Тraining Plan"
    case menu = "Menu"
    case workout = "Workout"
    case diet = "Diet"
}

@Model
final class Prompt {
    @Attribute(.unique) var id: UUID
    var text: String
    var type: PromptType
    var creationDate: Date

    init(text: String, type: PromptType) {
        self.id = UUID()
        self.text = text
        self.type = type
        self.creationDate = Date()
    }
}
