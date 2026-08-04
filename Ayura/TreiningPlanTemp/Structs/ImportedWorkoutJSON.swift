import Foundation

struct ImportedWorkoutDocument: Decodable {
    let identitySchema: String
    let plans: [ImportedPlanJSON]
}

struct ImportedPlanJSON: Decodable {
    let id: UUID
    let name: String
    let days: [ImportedDayJSON]
}

struct ImportedDayJSON: Decodable {
    let id: UUID
    let planId: UUID
    let dayIndex: Int
    let isRestDay: Bool
    let workouts: [ImportedWorkoutJSON]
}

struct ImportedWorkoutJSON: Decodable {
    let id: UUID
    let dayId: UUID
    let workoutName: String
    let exercises: [ImportedExerciseJSON]
}

struct ImportedSetJSON: Decodable {
    let id: UUID
    let exerciseId: UUID
    let reps: Int?
    let isToFailure: Bool
    let isTimeBased: Bool
    let timeUnitString: String
    let orderIndex: Int
}
