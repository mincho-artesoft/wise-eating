import Foundation

struct ExerciseItemDTO: Codable, Sendable {
    let id: UUID
    var catalogNumber: Int? = nil
    let title: String?
    let desc: String?
    let muscleGroups: [MuscleGroup]
    let metValue: Double?
    let minimalAgeMonths: Int?
    
    func model() -> ExerciseItem {
        return ExerciseItem(
            id: id,
            catalogNumber: catalogNumber,
            name: title ?? "Unnamed Exercise",
            description: desc,
            videoURL: nil,
            metValue: metValue,
            isUserAdded: false,
            photo: nil,
            gallery: nil,
            assetImageName: nil,
            muscleGroups: muscleGroups,
            durationMinutes: nil,
            isWorkout: false,
            exercises: [],
            minimalAgeMonths: minimalAgeMonths
        )
    }
}
