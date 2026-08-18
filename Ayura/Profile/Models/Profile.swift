import SwiftUI
import SwiftData
import EventKit

@Model
public final class Profile {
    public var id: UUID = UUID()

    // MARK: - Personal Information
    public var name: String
    public var birthday: Date
    public var gender: String
    public var weight: Double
    public var height: Double
    
    public var updatedAt: Date = Date()
    public var createdAt: Date = Date()

    // MARK: - Feature Flags & System IDs
    public var hasSeparateStorage: Bool = false
    public var calendarID: String? = nil
    public var shoppingListCalendarID: String? = nil
    
    // MARK: - Relationships
    public var meals: [Meal]
    
    @Relationship(deleteRule: .cascade, inverse: \Training.profile)
    public var trainings: [Training]

    @Relationship(deleteRule: .nullify)
    public var priorityVitamins: [Vitamin] = []

    @Relationship(deleteRule: .nullify)
    public var priorityMinerals: [Mineral] = []
    
    public var allergens: [Allergen] = []

    @Attribute(.externalStorage)
    public var photoData: Data? = nil

    @Relationship(deleteRule: .cascade, inverse: \WeightHeightRecord.profile)
    public var weightHeightHistory: [WeightHeightRecord] = []
    
    @Relationship(deleteRule: .cascade)
    public var pantryItems: [StorageItem] = []
    
    @Relationship(deleteRule: .cascade)
    public var transactions: [StorageTransaction] = []
    
    @Relationship(deleteRule: .cascade)
    public var mealStorageLinks: [MealLogStorageLink] = []

    @Relationship(deleteRule: .cascade)
     public var waterLogs: [WaterLog] = []
    
    @Relationship(deleteRule: .cascade)
    public var shoppingLists: [ShoppingListModel] = []

    @Relationship(deleteRule: .cascade)
    public var mealPlans: [MealPlan] = []
    
    // --- START OF CHANGE ---
    @Relationship(deleteRule: .cascade)
    public var trainingPlans: [TrainingPlan] = []

    @Relationship(deleteRule: .cascade)
    public var nodes: [Node] = []

    @Relationship(deleteRule: .cascade, inverse: \PracticeSession.profile)
    public var practiceSessions: [PracticeSession] = []
    // --- END OF CHANGE ---
    
    @Relationship(deleteRule: .cascade)
    public var recentlyAddedFoods: [RecentlyAddedFood] = []
    
    @Relationship(deleteRule: .cascade, inverse: \AIGenerationJob.profile)
    var aiJobs: [AIGenerationJob] = []

    // MARK: - Computed Properties
    public var age: Int {
        Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0
    }
    
    public var ageInMonths: Int {
        Calendar.current.dateComponents([.month], from: birthday, to: Date()).month ?? 0
    }
    
    public var image: Image? {
        guard let photoData,
              let ui = UIImage(data: photoData) else { return nil }
        return Image(uiImage: ui)
    }

    // MARK: - Initializer
    public init(
        name: String,
        birthday: Date,
        gender: String,
        weight: Double,
        height: Double,
        meals: [Meal] = [],
        trainings: [Training] = [],
        calendarID: String? = nil,
        shoppingListCalendarID: String? = nil,
        priorityVitamins: [Vitamin] = [],
        priorityMinerals: [Mineral] = [],
        allergens: [Allergen] = [],
        photoData: Data? = nil,
        hasSeparateStorage: Bool = false
    ) {
        self.name = name
        self.birthday = birthday
        self.gender = gender
        self.weight = weight
        self.height = height
        self.meals = meals.isEmpty ? Meal.defaultMeals() : meals
        
        self.trainings = []
        let initialTrainings = trainings.isEmpty ? Training.defaultTrainings() : trainings
        for training in initialTrainings {
            training.profile = self
            self.trainings.append(training)
        }
        
        self.calendarID = calendarID
        self.shoppingListCalendarID = shoppingListCalendarID
        self.priorityVitamins = priorityVitamins
        self.priorityMinerals = priorityMinerals
        self.allergens = allergens
        self.photoData = photoData
        self.hasSeparateStorage = hasSeparateStorage
        self.updatedAt = Date()
    }
    
    // MARK: - Helper Methods
    public func meals(for day: Date) -> [Meal] {
        meals.map { $0.detached(for: day) }
    }

    public func trainings(for day: Date) -> [Training] {
        trainings.map { $0.detached(for: day) }
    }
}
