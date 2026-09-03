import Foundation
import SwiftData

@MainActor
enum ExerciseDurationUnitMigrator {
    private static let migrationVersionKey = "exerciseDurationStorageVersion"
    private static let secondsStorageVersion = 1

    static func migrateIfNeeded(context: ModelContext) throws {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: migrationVersionKey) < secondsStorageVersion else {
            return
        }

        let exercises = try context.fetch(FetchDescriptor<ExerciseItem>())
        let cataloguedYogaDurations = exercises.compactMap { item -> Int? in
            guard let number = item.catalogNumber,
                  (800_000...800_907).contains(number) else {
                return nil
            }
            return item.durationSeconds
        }
        let yogaSeedVersion = defaults.integer(forKey: "yogaSeedVersion")
        let catalogueStillUsesMinutes = !cataloguedYogaDurations.isEmpty
            && (cataloguedYogaDurations.max() ?? 0) <= 30
        let existingInstallationUsesMinutes = (1...3).contains(yogaSeedVersion)
            || catalogueStillUsesMinutes

        guard existingInstallationUsesMinutes else {
            defaults.set(secondsStorageVersion, forKey: migrationVersionKey)
            return
        }

        try context.transaction {
            for exercise in exercises {
                if let duration = exercise.durationSeconds {
                    exercise.durationSeconds = duration * 60
                }
            }

            for link in try context.fetch(FetchDescriptor<ExerciseLink>()) {
                link.durationSeconds *= 60
            }

            for planExercise in try context.fetch(FetchDescriptor<TrainingPlanExercise>()) {
                planExercise.durationSeconds *= 60
            }

            for sequence in try context.fetch(FetchDescriptor<YogaSequence>()) {
                sequence.durationSeconds *= 60
            }

            for training in try context.fetch(FetchDescriptor<Training>()) {
                let durations = training.exercises(using: context)
                guard !durations.isEmpty else { continue }
                let seconds = durations.reduce(into: [ExerciseItem: Double]()) {
                    $0[$1.key] = $1.value * 60
                }
                training.updateNotes(
                    exercises: seconds,
                    detailedLog: training.detailedLog(using: context)
                )
            }
        }

        if context.hasChanges {
            try context.save()
        }
        defaults.set(secondsStorageVersion, forKey: migrationVersionKey)
        print("   ✅ Migrated exercise and workout durations from minutes to seconds.")
    }
}
