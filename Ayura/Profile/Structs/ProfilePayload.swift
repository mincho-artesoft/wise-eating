import Foundation

struct ProfilePayload: Codable {
    
    // Основни данни
    var name:      String
    var birthday:  Date
    var gender:    String
    var weight:    Double
    var height:    Double
    
    var meals: [Meal]
    var priorityVitaminIDs: [String]
    var priorityMineralIDs: [String]
    var allergens: [Allergen]
    var ayurvedaConstitution: AyurvedaConstitutionRecord?
    var ayurvedaConstitutionDeletedAt: Date?
    
    @MainActor
    init(from profile: Profile) {
        self.name        = profile.name
        self.birthday    = profile.birthday
        self.gender      = profile.gender
        self.weight      = profile.weight
        self.height      = profile.height
        self.meals       = profile.meals
        self.priorityVitaminIDs = profile.priorityVitamins.map(\.id)
        self.priorityMineralIDs = profile.priorityMinerals.map(\.id)
        self.allergens          = profile.allergens
        self.ayurvedaConstitution = AyurvedaConstitutionStore.record(
            for: profile.id
        )
        self.ayurvedaConstitutionDeletedAt =
            AyurvedaConstitutionStore.deletionDate(for: profile.id)
    }
    
    enum CodingKeys: String, CodingKey {
        case name, birthday, gender, weight, height, meals
        case priorityVitaminIDs, priorityMineralIDs
        case allergens
        case ayurvedaConstitution
        case ayurvedaConstitutionDeletedAt
    }
}
