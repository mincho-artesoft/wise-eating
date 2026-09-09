import Foundation

struct MealPlanDraft: Identifiable {
       let id = UUID()
       let name: String
       let meals: [Meal]
   }
