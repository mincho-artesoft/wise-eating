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

    @Relationship(
        deleteRule: .nullify,
        originalName: "priorityVitamins"
    )
    var persistedPriorityVitamins: [Vitamin] = []
    public var priorityVitaminIDs: [UUID] = []

    public var priorityVitamins: [Vitamin] {
        get {
            CatalogReferenceResolver.resolveVitamins(
                stored: persistedPriorityVitamins,
                catalogIDs: priorityVitaminIDs
            )
        }
        set {
            let split = CatalogReferenceResolver.splitVitamins(newValue)
            persistedPriorityVitamins = split.stored
            priorityVitaminIDs = split.catalogIDs
        }
    }

    @Relationship(
        deleteRule: .nullify,
        originalName: "priorityMinerals"
    )
    var persistedPriorityMinerals: [Mineral] = []
    public var priorityMineralIDs: [UUID] = []

    public var priorityMinerals: [Mineral] {
        get {
            CatalogReferenceResolver.resolveMinerals(
                stored: persistedPriorityMinerals,
                catalogIDs: priorityMineralIDs
            )
        }
        set {
            let split = CatalogReferenceResolver.splitMinerals(newValue)
            persistedPriorityMinerals = split.stored
            priorityMineralIDs = split.catalogIDs
        }
    }
    
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
        let vitaminSplit = CatalogReferenceResolver.splitVitamins(priorityVitamins)
        self.persistedPriorityVitamins = vitaminSplit.stored
        self.priorityVitaminIDs = vitaminSplit.catalogIDs
        let mineralSplit = CatalogReferenceResolver.splitMinerals(priorityMinerals)
        self.persistedPriorityMinerals = mineralSplit.stored
        self.priorityMineralIDs = mineralSplit.catalogIDs
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

/// A value-only snapshot used to move profile edits out of the combined
/// catalogue/user read context. Profile graphs include relationships to
/// catalogue-shaped types, so saving them through the combined context can
/// commit the user rows and then fail on the read-only catalogue store.
struct ProfileWriteRequest {
    struct MealValues {
        let id: UUID
        let name: String
        let startTime: Date
        let endTime: Date
        let notes: String?
        let descriptiveAIName: String?
        let reminderMinutes: Int?
        let notificationID: String?
        let calendarEventID: String?

        init(_ meal: Meal) {
            id = meal.id
            name = meal.name
            startTime = meal.startTime
            endTime = meal.endTime
            notes = meal.notes
            descriptiveAIName = meal.descriptiveAIName
            reminderMinutes = meal.reminderMinutes
            notificationID = meal.notificationID
            calendarEventID = meal.calendarEventID
        }

        func makeModel() -> Meal {
            Meal(
                id: id,
                name: name,
                startTime: startTime,
                endTime: endTime,
                notes: notes,
                descriptiveAIName: descriptiveAIName,
                reminderMinutes: reminderMinutes,
                notificationID: notificationID,
                calendarEventID: calendarEventID
            )
        }

        func apply(to meal: Meal) {
            meal.name = name
            meal.startTime = startTime
            meal.endTime = endTime
            meal.notes = notes
            meal.descriptiveAIName = descriptiveAIName
            meal.reminderMinutes = reminderMinutes
            meal.notificationID = notificationID
            meal.calendarEventID = calendarEventID
        }
    }

    struct TrainingValues {
        let id: UUID
        let name: String
        let startTime: Date
        let endTime: Date
        let notes: String?
        let reminderMinutes: Int?
        let notificationID: String?
        let calendarEventID: String?

        init(_ training: Training) {
            id = training.id
            name = training.name
            startTime = training.startTime
            endTime = training.endTime
            notes = training.notes
            reminderMinutes = training.reminderMinutes
            notificationID = training.notificationID
            calendarEventID = training.calendarEventID
        }

        func makeModel(profile: Profile) -> Training {
            Training(
                id: id,
                name: name,
                startTime: startTime,
                endTime: endTime,
                notes: notes,
                reminderMinutes: reminderMinutes,
                notificationID: notificationID,
                calendarEventID: calendarEventID,
                profile: profile
            )
        }

        func apply(to training: Training, profile: Profile) {
            training.name = name
            training.startTime = startTime
            training.endTime = endTime
            training.notes = notes
            training.reminderMinutes = reminderMinutes
            training.notificationID = notificationID
            training.calendarEventID = calendarEventID
            training.profile = profile
        }
    }

    let id: UUID
    let isExisting: Bool
    let name: String
    let birthday: Date
    let gender: String
    let weight: Double
    let height: Double
    let meals: [MealValues]
    let trainings: [TrainingValues]
    let catalogVitaminIDs: [UUID]
    let userVitaminIDs: [UUID]
    let catalogMineralIDs: [UUID]
    let userMineralIDs: [UUID]
    let allergens: [Allergen]
    let photoData: Data?
    let hasSeparateStorage: Bool

    init(
        profileID: UUID? = nil,
        name: String,
        birthday: Date,
        gender: String,
        weight: Double,
        height: Double,
        meals: [Meal],
        trainings: [Training],
        priorityVitamins: [Vitamin],
        priorityMinerals: [Mineral],
        allergens: [Allergen],
        photoData: Data?,
        hasSeparateStorage: Bool
    ) {
        id = profileID ?? UUID()
        isExisting = profileID != nil
        self.name = name
        self.birthday = birthday
        self.gender = gender
        self.weight = weight
        self.height = height
        self.meals = meals.map(MealValues.init)
        self.trainings = trainings.map(TrainingValues.init)
        let vitamins = CatalogReferenceResolver.splitVitamins(priorityVitamins)
        catalogVitaminIDs = vitamins.catalogIDs
        userVitaminIDs = vitamins.stored.map(\.id)
        let minerals = CatalogReferenceResolver.splitMinerals(priorityMinerals)
        catalogMineralIDs = minerals.catalogIDs
        userMineralIDs = minerals.stored.map(\.id)
        self.allergens = allergens
        self.photoData = photoData
        self.hasSeparateStorage = hasSeparateStorage
    }
}

@MainActor
enum ProfilePersistence {
    static func upsert(
        _ request: ProfileWriteRequest,
        in context: ModelContext
    ) throws -> Profile {
        let profile: Profile
        if request.isExisting {
            guard let existing = try fetch(id: request.id, in: context) else {
                throw CatalogReferenceError.missingUserProfile(request.id)
            }
            profile = existing
        } else {
            let created = Profile(
                name: request.name,
                birthday: request.birthday,
                gender: request.gender,
                weight: request.weight,
                height: request.height,
                meals: request.meals.map { $0.makeModel() },
                trainings: []
            )
            created.id = request.id
            context.insert(created)
            profile = created
        }

        let weightChanged = abs(profile.weight - request.weight) > 0.01
        let heightChanged = abs(profile.height - request.height) > 0.1
        if request.isExisting, weightChanged || heightChanged {
            let record = WeightHeightRecord(
                date: Date(),
                weight: request.weight,
                height: request.height
            )
            record.profile = profile
            profile.weightHeightHistory.append(record)
        }

        profile.name = request.name
        profile.birthday = request.birthday
        profile.gender = request.gender
        profile.weight = request.weight
        profile.height = request.height
        profile.photoData = request.photoData
        profile.hasSeparateStorage = request.hasSeparateStorage
        profile.allergens = request.allergens
        profile.updatedAt = Date()

        syncMeals(request.meals, profile: profile, context: context)
        syncTrainings(request.trainings, profile: profile, context: context)

        let userVitaminIDs = Set(request.userVitaminIDs)
        profile.persistedPriorityVitamins = try context.fetch(
            FetchDescriptor<Vitamin>()
        ).filter { userVitaminIDs.contains($0.id) }
        profile.priorityVitaminIDs = request.catalogVitaminIDs

        let userMineralIDs = Set(request.userMineralIDs)
        profile.persistedPriorityMinerals = try context.fetch(
            FetchDescriptor<Mineral>()
        ).filter { userMineralIDs.contains($0.id) }
        profile.priorityMineralIDs = request.catalogMineralIDs

        return profile
    }

    static func fetch(id: UUID, in context: ModelContext) throws -> Profile? {
        var descriptor = FetchDescriptor<Profile>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func syncMeals(
        _ values: [ProfileWriteRequest.MealValues],
        profile: Profile,
        context: ModelContext
    ) {
        let existing = profile.meals
        let retainedIDs = Set(values.map(\.id))
        var synced: [Meal] = []
        for value in values {
            if let meal = existing.first(where: { $0.id == value.id }) {
                value.apply(to: meal)
                synced.append(meal)
            } else {
                synced.append(value.makeModel())
            }
        }
        for meal in existing where !retainedIDs.contains(meal.id) {
            context.delete(meal)
        }
        profile.meals = synced
    }

    private static func syncTrainings(
        _ values: [ProfileWriteRequest.TrainingValues],
        profile: Profile,
        context: ModelContext
    ) {
        let existing = profile.trainings
        let retainedIDs = Set(values.map(\.id))
        var synced: [Training] = []
        for value in values {
            if let training = existing.first(where: { $0.id == value.id }) {
                value.apply(to: training, profile: profile)
                synced.append(training)
            } else {
                synced.append(value.makeModel(profile: profile))
            }
        }
        for training in existing where !retainedIDs.contains(training.id) {
            context.delete(training)
        }
        profile.trainings = synced
    }
}
