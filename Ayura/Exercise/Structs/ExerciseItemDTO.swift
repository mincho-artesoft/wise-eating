import Foundation

struct ExerciseItemDTO: Codable, Sendable {
    let id: UUID
    var catalogNumber: Int? = nil
    let title: String?
    let desc: String?
    let muscleGroups: [MuscleGroup]
    let metValue: Double?
    let minimalAgeMonths: Int?
    var sanskrit: String? = nil
    var slug: String? = nil
    var family: AsanaFamily? = nil
    var level: Int? = nil
    var levelScale: String? = nil
    var durationSeconds: Int? = nil
    var breath: String? = nil
    var drishti: String? = nil
    var contraindications: [String]? = nil
    var dosha: YogaDosha? = nil
    var doshaProvenance: String? = nil
    var assetImageName: String? = nil
    
    func model() -> ExerciseItem {
        return ExerciseItem(
            id: id,
            catalogNumber: catalogNumber,
            name: title ?? "Unnamed Exercise",
            sanskrit: sanskrit,
            slug: slug,
            family: family,
            level: level,
            levelScale: levelScale,
            durationSeconds: durationSeconds,
            breath: breath,
            drishti: drishti,
            contraindications: contraindications,
            dosha: dosha,
            doshaProvenance: doshaProvenance,
            description: desc,
            videoURL: nil,
            metValue: metValue,
            isUserAdded: false,
            photo: nil,
            gallery: nil,
            assetImageName: assetImageName,
            muscleGroups: muscleGroups,
            durationMinutes: nil,
            isWorkout: false,
            exercises: [],
            minimalAgeMonths: minimalAgeMonths
        )
    }
}
