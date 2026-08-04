import Foundation
import SwiftData

@MainActor
final class TrainingPlanImporter {
    static let shared = TrainingPlanImporter()
    private init() {}

    func importTemplates(jsonData: Data, context: ModelContext) async throws {
        let document = try JSONDecoder().decode(
            ImportedWorkoutDocument.self,
            from: jsonData
        )
        guard document.identitySchema == "stable-uuid-v1" else {
            throw TrainingPlanImportError.unsupportedIdentitySchema(
                document.identitySchema
            )
        }

        var insertedPlans = 0
        for planJSON in document.plans {
            let planID = planJSON.id
            let descriptor = FetchDescriptor<TemplatePlan>(
                predicate: #Predicate { $0.id == planID }
            )
            if try context.fetchCount(descriptor) > 0 {
                continue
            }

            let plan = TemplatePlan(id: planJSON.id, name: planJSON.name)
            context.insert(plan)
            insertedPlans += 1

            for dayJSON in planJSON.days {
                guard dayJSON.planId == planJSON.id else {
                    throw TrainingPlanImportError.invalidPlanRelationship(
                        child: dayJSON.id,
                        expected: planJSON.id,
                        actual: dayJSON.planId
                    )
                }
                let day = TemplateDay(
                    id: dayJSON.id,
                    dayIndex: dayJSON.dayIndex,
                    isRestDay: dayJSON.isRestDay
                )
                day.plan = plan
                context.insert(day)
                plan.days.append(day)

                for workoutJSON in dayJSON.workouts {
                    guard workoutJSON.dayId == dayJSON.id else {
                        throw TrainingPlanImportError.invalidPlanRelationship(
                            child: workoutJSON.id,
                            expected: dayJSON.id,
                            actual: workoutJSON.dayId
                        )
                    }
                    let workout = TemplateWorkout(
                        id: workoutJSON.id,
                        workoutName: workoutJSON.workoutName
                    )
                    workout.day = day
                    context.insert(workout)
                    day.workouts.append(workout)

                    for exerciseJSON in workoutJSON.exercises {
                        guard exerciseJSON.workoutId == workoutJSON.id else {
                            throw TrainingPlanImportError.invalidPlanRelationship(
                                child: exerciseJSON.id,
                                expected: workoutJSON.id,
                                actual: exerciseJSON.workoutId
                            )
                        }
                        let exercise = TemplateExercise(
                            id: exerciseJSON.id,
                            exerciseName: exerciseJSON.exerciseName,
                            durationMinutes: exerciseJSON.durationMinutes
                        )
                        exercise.workout = workout
                        context.insert(exercise)
                        workout.exercises.append(exercise)

                        for setJSON in exerciseJSON.sets {
                            guard setJSON.exerciseId == exerciseJSON.id else {
                                throw TrainingPlanImportError.invalidPlanRelationship(
                                    child: setJSON.id,
                                    expected: exerciseJSON.id,
                                    actual: setJSON.exerciseId
                                )
                            }
                            let set = TemplateSet(
                                id: setJSON.id,
                                reps: setJSON.reps,
                                isToFailure: setJSON.isToFailure,
                                isTimeBased: setJSON.isTimeBased,
                                timeUnitString: setJSON.timeUnitString,
                                orderIndex: setJSON.orderIndex
                            )
                            set.exercise = exercise
                            context.insert(set)
                            exercise.sets.append(set)
                        }
                    }
                }
            }
        }

        try context.save()
        print("✅ Imported \(insertedPlans) UUID template plans.")
    }
}

private enum TrainingPlanImportError: LocalizedError {
    case unsupportedIdentitySchema(String)
    case invalidPlanRelationship(child: UUID, expected: UUID, actual: UUID)

    var errorDescription: String? {
        switch self {
        case .unsupportedIdentitySchema(let schema):
            return "Unsupported workout identity schema: \(schema)"
        case .invalidPlanRelationship(let child, let expected, let actual):
            return "Invalid template relationship for \(child): expected \(expected), got \(actual)"
        }
    }
}
