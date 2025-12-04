
import Foundation
import SwiftData

// A Codable, non-persistent representation of an ExerciseItem, used for duplication and AI generation flows.
public final class ExerciseItemCopy: Identifiable, Codable {
    public var originalID: Int?
    public var name: String
    public var exerciseDescription: String?
    public var videoURL: String?
    public var metValue: Double?
    public var isUserAdded: Bool
    public var isFavorite: Bool
    public var photo: Data?
    public var gallery: [Data]?
    public var assetImageName: String?
    public var muscleGroups: [MuscleGroup]
    public var sports: [Sport]?
    public var durationMinutes: Int?
    public var isWorkout: Bool
    public var exercises: [ExerciseLinkCopy]?
    public var minimalAgeMonths: Int
    
    // CodingKeys to handle manual encoding/decoding if needed, especially for weak references.
    enum CodingKeys: String, CodingKey {
        case originalID, name, exerciseDescription, videoURL, metValue, isUserAdded, isFavorite, photo, gallery, assetImageName, muscleGroups, sports, durationMinutes, isWorkout, exercises, minimalAgeMonths
    }

    // Full initializer
    public init(
        originalID: Int? = nil, name: String, exerciseDescription: String? = nil, videoURL: String? = nil,
        metValue: Double? = nil, isUserAdded: Bool = true, isFavorite: Bool = false,
        photo: Data? = nil, gallery: [Data]? = nil, assetImageName: String? = nil,
        muscleGroups: [MuscleGroup], sports: [Sport]? = nil, durationMinutes: Int? = nil,
        isWorkout: Bool = false, exercises: [ExerciseLinkCopy]? = nil, minimalAgeMonths: Int = 0
    ) {
        self.originalID = originalID
        self.name = name
        self.exerciseDescription = exerciseDescription
        self.videoURL = videoURL
        self.metValue = metValue
        self.isUserAdded = isUserAdded
        self.isFavorite = isFavorite
        self.photo = photo
        self.gallery = gallery
        self.assetImageName = assetImageName
        self.muscleGroups = muscleGroups
        self.sports = sports
        self.durationMinutes = durationMinutes
        self.isWorkout = isWorkout
        self.exercises = exercises
        self.minimalAgeMonths = minimalAgeMonths
    }

    // Creates a deep copy from a persistent ExerciseItem
    @MainActor
    public convenience init(from src: ExerciseItem, cache: inout [ObjectIdentifier: ExerciseItemCopy]) {
        if let hit = cache[ObjectIdentifier(src)] {
            self.init(from: hit) // Re-use from cache to break cycles
            return
        }
        
        let exerciseLinksCopy = src.exercises?.map { ExerciseLinkCopy(from: $0, cache: &cache) }

        self.init(
            originalID: src.id, name: src.name, exerciseDescription: src.exerciseDescription,
            videoURL: src.videoURL, metValue: src.metValue, isUserAdded: src.isUserAdded,
            isFavorite: src.isFavorite, photo: src.photo, gallery: src.gallery?.map(\.data),
            assetImageName: src.assetImageName, muscleGroups: src.muscleGroups, sports: src.sports,
            durationMinutes: src.durationMinutes, isWorkout: src.isWorkout,
            exercises: exerciseLinksCopy, minimalAgeMonths: src.minimalAgeMonths
        )
        
        cache[ObjectIdentifier(src)] = self
        exercises?.forEach { $0.owner = self }
    }
    
    convenience init(from dto: ResolvedWorkoutResponseDTO, links: [ExerciseLinkCopy]) {
           self.init(
               name: dto.name,
               exerciseDescription: dto.description,
               metValue: nil, // AI не генерира обща стойност за цялата тренировка
               isUserAdded: true, // След запис, това ще е потребителски елемент
               isFavorite: false,
               photo: nil,
               gallery: nil,
               assetImageName: nil,
               muscleGroups: [], // Ще се агрегира автоматично в редактора
               sports: [],       // Ще се агрегира автоматично
               durationMinutes: dto.totalDurationMinutes,
               isWorkout: true,
               exercises: links,
               minimalAgeMonths: 0 // Ще се изчисли автоматично в редактора
           )
       }
    
    @MainActor
    public convenience init(from src: ExerciseItem) {
        var cache: [ObjectIdentifier: ExerciseItemCopy] = [:]
        self.init(from: src, cache: &cache)
    }

    // Private convenience init for re-using from cache
    private convenience init(from copy: ExerciseItemCopy) {
        self.init(
            originalID: copy.originalID, name: copy.name, exerciseDescription: copy.exerciseDescription,
            videoURL: copy.videoURL, metValue: copy.metValue, isUserAdded: copy.isUserAdded,
            isFavorite: copy.isFavorite, photo: copy.photo, gallery: copy.gallery,
            assetImageName: copy.assetImageName, muscleGroups: copy.muscleGroups, sports: copy.sports,
            durationMinutes: copy.durationMinutes, isWorkout: copy.isWorkout,
            exercises: copy.exercises, minimalAgeMonths: copy.minimalAgeMonths
        )
    }
    
    // Creates an ExerciseItemCopy from an AI-generated DTO
    convenience init(from dto: ExerciseItemDTO) {
        self.init(
            name: dto.title ?? "New Exercise",
            exerciseDescription: dto.desc,
            metValue: dto.metValue,
            isUserAdded: false, // Генерираните от AI не са "user added" по подразбиране
            isFavorite: false,
            photo: nil,
            gallery: nil,
            assetImageName: nil,
            muscleGroups: dto.muscleGroups,
            sports: dto.sports,
            durationMinutes: nil, // DTO-то не съдържа продължителност по подразбиране
            isWorkout: false, // Това е за единично упражнение, не за тренировка
            exercises: nil,
            minimalAgeMonths: dto.minimalAgeMonths ?? 0
        )
    }

}

// A Codable, non-persistent representation of an ExerciseLink
public final class ExerciseLinkCopy: Identifiable, Codable {
    public var id = UUID()
    public var exercise: ExerciseItemCopy?
    public var durationMinutes: Double
    public weak var owner: ExerciseItemCopy?

    enum CodingKeys: String, CodingKey { case id, exercise, durationMinutes }
    
    // +++ НАЧАЛО НА ПРОМЯНАТА (1/2): Добавете този нов инициализатор +++
    public init(exercise: ExerciseItemCopy?, durationMinutes: Double, owner: ExerciseItemCopy? = nil) {
        self.exercise = exercise
        self.durationMinutes = durationMinutes
        self.owner = owner
    }
    // +++ КРАЙ НА ПРОМЯНАТА (1/2) +++

    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        exercise = try c.decodeIfPresent(ExerciseItemCopy.self, forKey: .exercise)
        durationMinutes = try c.decode(Double.self, forKey: .durationMinutes)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(exercise, forKey: .exercise)
        try c.encode(durationMinutes, forKey: .durationMinutes)
    }

    @MainActor
    public init(from src: ExerciseLink, cache: inout [ObjectIdentifier: ExerciseItemCopy]) {
        self.durationMinutes = src.durationMinutes
        if let ex = src.exercise {
            self.exercise = ExerciseItemCopy(from: ex, cache: &cache)
        }
    }
}
