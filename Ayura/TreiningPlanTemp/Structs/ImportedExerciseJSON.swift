import Foundation

struct ImportedExerciseJSON: Decodable {
    let id: UUID
    let workoutId: UUID
    let exerciseName: String
    let durationMinutes: Double
    let sets: [ImportedSetJSON]
}
