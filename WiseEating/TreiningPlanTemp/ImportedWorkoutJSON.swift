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
class TrainingPlanImporter {
    static let shared = TrainingPlanImporter()
    private init() {}
    
    func importTemplates(jsonData: Data, context: ModelContext) async throws {
        let items = try JSONDecoder().decode([ImportedWorkoutJSON].self, from: jsonData)
        
        // Групиране
        var groupedPlans: [String: [ImportedWorkoutJSON]] = [:]
        for item in items {
            let components = item.title.components(separatedBy: " - ")
            let planName = components.first ?? item.title
            groupedPlans[planName, default: []].append(item)
        }
        
        // Запис в Template моделите
        for (planName, workoutsJSON) in groupedPlans {
            // Проверка дали съществува в TemplatePlan
            let descriptor = FetchDescriptor<TemplatePlan>(predicate: #Predicate { $0.name == planName })
            if let count = try? context.fetchCount(descriptor), count > 0 {
                continue
            }
            
            let newPlan = TemplatePlan(name: planName)
            context.insert(newPlan)
            
            let sortedWorkouts = workoutsJSON.sorted { $0.title < $1.title }
            
            for (index, workoutJSON) in sortedWorkouts.enumerated() {
                // ❌ ПРЕМАХНАТО: Старата логика за извличане на име (напр. "Chest & Back")
                // let workoutNameComponents = workoutJSON.title.components(separatedBy: " - ")
                // let workoutName = workoutNameComponents.count > 1 ? workoutNameComponents.last! : workoutJSON.title
                
                let day = TemplateDay(dayIndex: index + 1)
                day.plan = newPlan
                
                // ✅ ПРОМЯНА: Винаги създаваме тренировката с име "Workout"
                let workout = TemplateWorkout(workoutName: "Workout")
                workout.day = day
                
                for exJSON in workoutJSON.exercises {
                    // Тук НЕ търсим в базата, просто записваме името (String)
                    let ex = TemplateExercise(exerciseName: exJSON.name, durationMinutes: Double(exJSON.duration))
                    ex.workout = workout
                    
                    for i in 0..<exJSON.sets {
                        let unitString = exJSON.unit ?? "sec"
                        let set = TemplateSet(
                            reps: exJSON.is_time_based ? exJSON.reps : exJSON.reps, // Reps или Secs
                            isToFailure: exJSON.to_failure,
                            isTimeBased: exJSON.is_time_based,
                            timeUnitString: unitString,
                            orderIndex: i
                        )
                        set.exercise = ex
                    }
                }
            }
        }
        
        try? context.save() // Това ще запише само в templates.store
        print("✅ Imported \(groupedPlans.count) templates into separate store.")
    }
}
