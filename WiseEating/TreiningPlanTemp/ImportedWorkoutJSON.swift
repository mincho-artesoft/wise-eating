import Foundation
import SwiftData

// MARK: - JSON Mapping Models
struct ImportedWorkoutJSON: Codable {
    let title: String
    let exercises: [ImportedExerciseJSON]
}

struct ImportedExerciseJSON: Codable {
    let name: String
    let sets: Int
    let reps: Int
    let duration: Int
    let is_time_based: Bool
    let to_failure: Bool
    let unit: String?
}

@MainActor
final class TrainingPlanImporter {
    static let shared = TrainingPlanImporter()
    private init() {}

    func importTemplates(jsonData: Data, context: ModelContext) async throws {
        let items = try JSONDecoder().decode([ImportedWorkoutJSON].self, from: jsonData)

        // 1) Групиране по plan name (частта преди " - ")
        var groupedPlans: [String: [ImportedWorkoutJSON]] = [:]
        for item in items {
            let components = item.title.components(separatedBy: " - ")
            let planName = components.first ?? item.title
            groupedPlans[planName, default: []].append(item)
        }

        // 2) Запис в Template моделите
        for (planName, workoutsJSON) in groupedPlans {

            // Проверка дали вече е импортнат
            let existsDesc = FetchDescriptor<TemplatePlan>(predicate: #Predicate { $0.name == planName })
            if ((try? context.fetchCount(existsDesc)) ?? 0) > 0 {
                continue
            }

            let newPlan = TemplatePlan(name: planName)
            context.insert(newPlan)

            // 3) Опит: има ли calendar day в title? (Day N / Monday..Sunday)
            var dayMap: [Int: [ImportedWorkoutJSON]] = [:]
            var hasCalendarDays = false

            for w in workoutsJSON {
                if let d = parseDayIndex(from: w.title) {
                    hasCalendarDays = true
                    dayMap[d, default: []].append(w)
                }
            }

            if hasCalendarDays {
                // ✅ Създаваме дни 1..7, липсващите стават Rest day
                for dayIndex in 1...7 {
                    let dayWorkouts = dayMap[dayIndex] ?? []

                    let day = TemplateDay(dayIndex: dayIndex, isRestDay: dayWorkouts.isEmpty)
                    day.plan = newPlan
                    context.insert(day)
                    newPlan.days.append(day)

                    guard !dayWorkouts.isEmpty else { continue }

                    // Стабилна подредба в рамките на деня
                    let sortedInDay = dayWorkouts.sorted { $0.title < $1.title }

                    for workoutJSON in sortedInDay {
                        let workoutTitle = shortWorkoutName(from: workoutJSON.title)
                        let workout = TemplateWorkout(workoutName: workoutTitle)
                        workout.day = day
                        context.insert(workout)
                        day.workouts.append(workout)

                        for exJSON in workoutJSON.exercises {
                            let ex = TemplateExercise(
                                exerciseName: exJSON.name,
                                durationMinutes: Double(exJSON.duration)
                            )
                            ex.workout = workout
                            context.insert(ex)
                            workout.exercises.append(ex)

                            for i in 0..<exJSON.sets {
                                let unitString = exJSON.unit ?? "sec"

                                let set = TemplateSet(
                                    reps: exJSON.reps,
                                    isToFailure: exJSON.to_failure,
                                    isTimeBased: exJSON.is_time_based,
                                    timeUnitString: unitString,
                                    orderIndex: i
                                )
                                set.exercise = ex
                                context.insert(set)
                                ex.sets.append(set)
                            }
                        }
                    }
                }
            } else {
                // Fallback: няма weekday/Day -> последователни дни (но с natural sort)
                let ordered = workoutsJSON.sorted { lhs, rhs in
                    naturalOrderKey(lhs.title) < naturalOrderKey(rhs.title)
                }

                for (idx, workoutJSON) in ordered.enumerated() {
                    let day = TemplateDay(dayIndex: idx + 1, isRestDay: false)
                    day.plan = newPlan
                    context.insert(day)
                    newPlan.days.append(day)

                    let workoutTitle = shortWorkoutName(from: workoutJSON.title)
                    let workout = TemplateWorkout(workoutName: workoutTitle)
                    workout.day = day
                    context.insert(workout)
                    day.workouts.append(workout)

                    for exJSON in workoutJSON.exercises {
                        let ex = TemplateExercise(
                            exerciseName: exJSON.name,
                            durationMinutes: Double(exJSON.duration)
                        )
                        ex.workout = workout
                        context.insert(ex)
                        workout.exercises.append(ex)

                        for i in 0..<exJSON.sets {
                            let unitString = exJSON.unit ?? "sec"

                            let set = TemplateSet(
                                reps: exJSON.reps,
                                isToFailure: exJSON.to_failure,
                                isTimeBased: exJSON.is_time_based,
                                timeUnitString: unitString,
                                orderIndex: i
                            )
                            set.exercise = ex
                            context.insert(set)
                            ex.sets.append(set)
                        }
                    }
                }
            }
        }

        try context.save()
        print("✅ Imported \(groupedPlans.count) templates.")
    }

    // MARK: - Helpers

    /// Връща 1..7 ако намери Day N или weekday.
    private func parseDayIndex(from title: String) -> Int? {
        let t = title.lowercased()

        // "Day 7"
        if let range = t.range(of: #"(?<=\bday\s)\d{1,2}\b"#, options: .regularExpression) {
            return Int(t[range])
        }

        // Weekdays
        let map: [String: Int] = [
            "monday": 1,
            "tuesday": 2,
            "wednesday": 3,
            "thursday": 4,
            "friday": 5,
            "saturday": 6,
            "sunday": 7
        ]
        for (k, v) in map where t.contains(k) { return v }

        return nil
    }

    /// Пример: "Plan - Monday: Workout 1" -> "Monday: Workout 1"
    /// Ако няма " - ", връща "Workout"
    private func shortWorkoutName(from title: String) -> String {
        let parts = title.components(separatedBy: " - ")
        if parts.count >= 2 {
            return parts.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Workout"
        }
        return "Workout"
    }

    /// Natural sort за "Workout 2" < "Workout 10"
    private func naturalOrderKey(_ title: String) -> (String, Int) {
        let lower = title.lowercased()

        if let range = lower.range(of: #"workout\s(\d{1,3})"#, options: .regularExpression) {
            let matched = String(lower[range])                 // "workout 12"
            let n = Int(matched.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
            let prefix = lower.replacingOccurrences(of: matched, with: "workout")
            return (prefix, n)
        }

        return (lower, 0)
    }
}
