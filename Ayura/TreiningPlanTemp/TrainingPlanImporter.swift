import Foundation
import SwiftData

// MARK: - JSON Mapping Models

@MainActor
final class TrainingPlanImporter {
    static let shared = TrainingPlanImporter()
    private init() {}

    func importTemplates(jsonData: Data, context: ModelContext) async throws {
        let items = try JSONDecoder().decode([ImportedWorkoutJSON].self, from: jsonData)

        // 1) Групиране по planName (както досега)
        //    ВАЖНО: това дава 402 unique plans на твоя файл.
        var groupedPlans: [String: [ImportedWorkoutJSON]] = [:]
        groupedPlans.reserveCapacity(512)

        for item in items {
            let components = item.title.components(separatedBy: " - ")
            let planName = components.first ?? item.title
            groupedPlans[planName, default: []].append(item)
        }

        // 2) Импорт
        for (planName, workoutsJSON) in groupedPlans {
            // Ако вече съществува TemplatePlan с това име — skip
            let descriptor = FetchDescriptor<TemplatePlan>(predicate: #Predicate { $0.name == planName })
            if let count = try? context.fetchCount(descriptor), count > 0 {
                continue
            }

            let newPlan = TemplatePlan(name: planName)
            context.insert(newPlan)

            // 3) Разпределяме workout-ите по dayIndex (парсваме Day N ако го има)
            //    Ако няма Day N, ще ги наредим последователно.
            let mapped: [(dayIndex: Int?, sortKey: String, item: ImportedWorkoutJSON)] = workoutsJSON.map { w in
                let d = Self.extractDayIndex(from: w.title) // nil ако няма
                return (d, w.title, w)
            }

            // Ако има поне един реален Day N — ползваме него, иначе fallback на enumerated
            let hasAnyExplicitDay = mapped.contains { $0.dayIndex != nil }

            var dayBuckets: [Int: [ImportedWorkoutJSON]] = [:]

            if hasAnyExplicitDay {
                for entry in mapped {
                    guard let d = entry.dayIndex else {
                        // Няма day index в заглавието — слагаме ги временно в 0,
                        // после ще ги добавим след най-големия explicit day.
                        dayBuckets[0, default: []].append(entry.item)
                        continue
                    }
                    dayBuckets[d, default: []].append(entry.item)
                }
            } else {
                // Fallback: 1..N по азбучен ред на title (детерминирано)
                let sorted = mapped.sorted { $0.sortKey.localizedCaseInsensitiveCompare($1.sortKey) == .orderedAscending }
                for (idx, entry) in sorted.enumerated() {
                    let d = idx + 1
                    dayBuckets[d, default: []].append(entry.item)
                }
            }

            // Ако има “0 bucket” (без day), закачаме ги след maxDay (детерминирано)
            if let zero = dayBuckets.removeValue(forKey: 0), !zero.isEmpty {
                let maxDay = max(dayBuckets.keys.max() ?? 0, 0)
                let sortedZero = zero.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                for (offset, w) in sortedZero.enumerated() {
                    dayBuckets[maxDay + 1 + offset, default: []].append(w)
                }
            }

            let maxDayIndex = dayBuckets.keys.max() ?? 0

            // 4) Създаваме дни 1...maxDayIndex и пълним “дупките” с Rest Day
            if maxDayIndex > 0 {
                for d in 1...maxDayIndex {
                    let workoutsForDay = dayBuckets[d] ?? []

                    let isRest = workoutsForDay.isEmpty
                    let day = TemplateDay(dayIndex: d, isRestDay: isRest)
                    day.plan = newPlan

                    context.insert(day)
                    newPlan.days.append(day)

                    // Ако е rest day — няма workouts
                    guard !isRest else { continue }

                    // Някои дни може да имат >1 workout (рядко, но да сме safe)
                    let sortedWorkouts = workoutsForDay.sorted {
                        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }

                    for workoutJSON in sortedWorkouts {
                        let workoutName = Self.extractWorkoutDisplayName(planName: planName, fullTitle: workoutJSON.title)

                        let workout = TemplateWorkout(workoutName: workoutName)
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

                            let unitString = exJSON.unit ?? "sec"

                            // sets
                            if exJSON.sets > 0 {
                                for i in 0..<exJSON.sets {
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
            }

            // по желание: ако maxDayIndex == 0 (много странно), пак поне един Rest Day
            if newPlan.days.isEmpty {
                let day = TemplateDay(dayIndex: 1, isRestDay: true)
                day.plan = newPlan
                context.insert(day)
                newPlan.days.append(day)
            }
        }

        do {
            try context.save()
            print("✅ Imported \(groupedPlans.count) template plans.")
        } catch {
            print("❌ Template import save failed: \(error)")
            throw error
        }
    }

    // MARK: - Helpers

    /// Търсим "Day 12" навсякъде в заглавието.
    private static func extractDayIndex(from title: String) -> Int? {
        // examples: " ... Day 1", " ... Day 1: Chest", " ... - Day 1"
        let pattern = #"\bDay\s*(\d+)\b"#
        if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(title.startIndex..<title.endIndex, in: title)
            if let m = re.firstMatch(in: title, options: [], range: range),
               m.numberOfRanges >= 2,
               let r1 = Range(m.range(at: 1), in: title) {
                return Int(title[r1])
            }
        }
        return nil
    }

    /// Как да кръстим workout tab-а вътре в деня.
    /// - Ако title е само "Plan - Workout A" -> "Workout A"
    /// - Ако е "Plan - Day 3: Chest" -> "Day 3: Chest"
    /// - Ако няма нищо смислено -> "Workout"
    private static func extractWorkoutDisplayName(planName: String, fullTitle: String) -> String {
        // махаме "PlanName - "
        if fullTitle.hasPrefix(planName + " - ") {
            let rest = String(fullTitle.dropFirst((planName + " - ").count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { return rest }
        }
        return "Workout"
    }
}
