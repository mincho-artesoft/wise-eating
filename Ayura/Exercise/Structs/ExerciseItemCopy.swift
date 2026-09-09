
import Foundation
import SwiftData
import UIKit

// A Codable, non-persistent representation of an ExerciseItem, used for duplication and AI generation flows.
public final class ExerciseItemCopy: Identifiable, Codable {
    public var originalID: UUID?
    public var name: String
    public var sanskrit: String?
    public var slug: String?
    public var family: AsanaFamily?
    public var level: Int?
    public var breath: YogaBreath?
    public var drishti: YogaDrishti?
    public var contraindications: [String]?
    public var dosha: YogaDosha?
    public var doshaProvenance: String?
    public var exerciseDescription: String?
    public var videoURL: String?
    public var metValue: Double?
    public var isUserAdded: Bool
    public var isFavorite: Bool
    public var photo: Data?
    public var gallery: [Data]?
    public var assetImageName: String?
    public var muscleGroups: [MuscleGroup]
    public var durationSeconds: Int?
    public var isWorkout: Bool
    public var exercises: [ExerciseLinkCopy]?
    public var minimalAgeMonths: Int
    
    // CodingKeys to handle manual encoding/decoding if needed, especially for weak references.
    enum CodingKeys: String, CodingKey {
        case originalID, name, sanskrit, slug, family, level
        case breath, drishti, contraindications, dosha, doshaProvenance
        case exerciseDescription, videoURL, metValue, isUserAdded, isFavorite, photo
        case gallery, assetImageName, muscleGroups, durationSeconds, isWorkout
        case exercises, minimalAgeMonths
    }

    // Full initializer
    public init(
        originalID: UUID? = nil, name: String, sanskrit: String? = nil,
        slug: String? = nil, family: AsanaFamily? = nil, level: Int? = nil,
        breath: YogaBreath? = nil, drishti: YogaDrishti? = nil,
        contraindications: [String]? = nil, dosha: YogaDosha? = nil,
        doshaProvenance: String? = nil, exerciseDescription: String? = nil,
        videoURL: String? = nil,
        metValue: Double? = nil, isUserAdded: Bool = true, isFavorite: Bool = false,
        photo: Data? = nil, gallery: [Data]? = nil, assetImageName: String? = nil,
        muscleGroups: [MuscleGroup], durationSeconds: Int? = nil,
        isWorkout: Bool = false, exercises: [ExerciseLinkCopy]? = nil, minimalAgeMonths: Int = 0
    ) {
        self.originalID = originalID
        self.name = name
        self.sanskrit = sanskrit
        self.slug = slug
        self.family = family
        self.level = level
        self.breath = breath
        self.drishti = drishti
        self.contraindications = contraindications
        self.dosha = dosha
        self.doshaProvenance = doshaProvenance
        self.exerciseDescription = exerciseDescription
        self.videoURL = videoURL
        self.metValue = metValue
        self.isUserAdded = isUserAdded
        self.isFavorite = isFavorite
        self.photo = photo
        self.gallery = gallery
        self.assetImageName = assetImageName
        self.muscleGroups = muscleGroups
        self.durationSeconds = durationSeconds
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
            originalID: src.id, name: src.name, sanskrit: src.sanskrit, slug: src.slug,
            family: src.family, level: src.level,
            breath: src.breath, drishti: src.drishti,
            contraindications: src.contraindications, dosha: src.dosha,
            doshaProvenance: src.doshaProvenance, exerciseDescription: src.exerciseDescription,
            videoURL: src.videoURL, metValue: src.metValue, isUserAdded: src.isUserAdded,
            isFavorite: src.isFavorite, photo: src.photo, gallery: src.gallery?.map(\.data),
            assetImageName: src.assetImageName, muscleGroups: src.muscleGroups,
            durationSeconds: src.durationSeconds, isWorkout: src.isWorkout,
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
               durationSeconds: dto.totalDurationSeconds,
               isWorkout: true,
               exercises: links,
               minimalAgeMonths: 0 // Ще се изчисли автоматично в редактора
           )
       }
    
    @MainActor
    public convenience init(from src: ExerciseItem) {
        var cache: [ObjectIdentifier: ExerciseItemCopy] = [:]
        self.init(from: src, cache: &cache)
        if photo == nil,
           let visibleImage = src.exerciseImage(
               preferredVariants: ["1024", "480"]
           ) {
            photo = visibleImage.jpegData(compressionQuality: 0.9)
        }
    }

    // Private convenience init for re-using from cache
    private convenience init(from copy: ExerciseItemCopy) {
        self.init(
            originalID: copy.originalID, name: copy.name, sanskrit: copy.sanskrit,
            slug: copy.slug, family: copy.family, level: copy.level,
            breath: copy.breath, drishti: copy.drishti,
            contraindications: copy.contraindications, dosha: copy.dosha,
            doshaProvenance: copy.doshaProvenance,
            exerciseDescription: copy.exerciseDescription,
            videoURL: copy.videoURL, metValue: copy.metValue, isUserAdded: copy.isUserAdded,
            isFavorite: copy.isFavorite, photo: copy.photo, gallery: copy.gallery,
            assetImageName: copy.assetImageName, muscleGroups: copy.muscleGroups,
            durationSeconds: copy.durationSeconds, isWorkout: copy.isWorkout,
            exercises: copy.exercises, minimalAgeMonths: copy.minimalAgeMonths
        )
    }
    
    // Creates an ExerciseItemCopy from an AI-generated DTO
    convenience init(from dto: ExerciseItemDTO) {
        self.init(
            name: dto.title ?? "New Exercise",
            sanskrit: dto.sanskrit,
            slug: dto.slug,
            family: dto.family,
            level: dto.level,
            breath: dto.breath,
            drishti: dto.drishti,
            contraindications: dto.contraindications,
            dosha: dto.dosha,
            doshaProvenance: dto.doshaProvenance,
            exerciseDescription: dto.desc,
            metValue: dto.metValue,
            isUserAdded: false, // Генерираните от AI не са "user added" по подразбиране
            isFavorite: false,
            photo: nil,
            gallery: nil,
            assetImageName: dto.assetImageName,
            muscleGroups: dto.muscleGroups,
            durationSeconds: dto.durationSeconds,
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
    public var durationSeconds: Double
    public weak var owner: ExerciseItemCopy?

    enum CodingKeys: String, CodingKey { case id, exercise, durationSeconds }
    
    // +++ НАЧАЛО НА ПРОМЯНАТА (1/2): Добавете този нов инициализатор +++
    public init(exercise: ExerciseItemCopy?, durationSeconds: Double, owner: ExerciseItemCopy? = nil) {
        self.exercise = exercise
        self.durationSeconds = durationSeconds
        self.owner = owner
    }
    // +++ КРАЙ НА ПРОМЯНАТА (1/2) +++

    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        exercise = try c.decodeIfPresent(ExerciseItemCopy.self, forKey: .exercise)
        durationSeconds = try c.decode(Double.self, forKey: .durationSeconds)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(exercise, forKey: .exercise)
        try c.encode(durationSeconds, forKey: .durationSeconds)
    }

    @MainActor
    public init(from src: ExerciseLink, cache: inout [ObjectIdentifier: ExerciseItemCopy]) {
        self.durationSeconds = src.durationSeconds
        if let ex = src.exercise {
            self.exercise = ExerciseItemCopy(from: ex, cache: &cache)
        }
    }
}
