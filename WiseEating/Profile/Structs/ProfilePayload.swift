import Foundation

struct ProfilePayload: Codable {
    
    // Основни данни
    var name:      String
    var birthday:  Date
    var gender:    String
    var weight:    Double
    var height:    Double
    
    // --- START OF CHANGE ---
    var goal: Goal? // Add the goal
    // --- END OF CHANGE ---
    
    var activityLevel: ActivityLevel
    var meals: [Meal]
    var isPregnant:  Bool
    var isLactating: Bool
    var priorityVitaminIDs: [String]
    var priorityMineralIDs: [String]
    var dietIDs: [String]
    var allergens: [Allergen]
    var sports: [Sport]
    
    init(from profile: Profile) {
        self.name        = profile.name
        self.birthday    = profile.birthday
        self.gender      = profile.gender
        self.weight      = profile.weight
        self.height      = profile.height
        self.goal        = profile.goal // Add the goal
        self.activityLevel = profile.activityLevel
        self.meals       = profile.meals
        self.isPregnant  = profile.isPregnant
        self.isLactating = profile.isLactating
        self.priorityVitaminIDs = profile.priorityVitamins.map(\.id)
        self.priorityMineralIDs = profile.priorityMinerals.map(\.id)
        self.dietIDs = profile.diets.map(\.id)
        self.allergens          = profile.allergens
        self.sports = profile.sports
    }
    
    enum CodingKeys: String, CodingKey {
        case name, birthday, gender, weight, height, goal, activityLevel, meals, isPregnant, isLactating
        case priorityVitaminIDs, priorityMineralIDs
        case dietIDs = "diets"
        case allergens
        case sports
    }
}
