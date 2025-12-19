import Foundation
import SwiftData

// Тези модели ще живеят в отделен файл (templates.store)

@Model
final class TemplatePlan: Identifiable {
    @Attribute(.unique) public var id: String // Ще ползваме името или UUID от JSON
    public var name: String
    
    @Relationship(deleteRule: .cascade, inverse: \TemplateDay.plan)
    public var days: [TemplateDay] = []
    
    public init(name: String) {
        self.id = UUID().uuidString
        self.name = name
    }
}

@Model
final class TemplateDay: Identifiable {
    public var dayIndex: Int
    
    @Relationship(deleteRule: .cascade, inverse: \TemplateWorkout.day)
    public var workouts: [TemplateWorkout] = []
    
    public var plan: TemplatePlan?
    
    public init(dayIndex: Int) {
        self.dayIndex = dayIndex
    }
}

@Model
final class TemplateWorkout: Identifiable {
    // ✅ ПРОМЯНА: Стойност по подразбиране
    public var workoutName: String = "Workout"
    
    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.workout)
    public var exercises: [TemplateExercise] = []
    
    public var day: TemplateDay?
    
    // ✅ ПРОМЯНА: Инициализаторът вече подразбира "Workout", но позволява промяна ако е нужно
    public init(workoutName: String = "Workout") {
        self.workoutName = workoutName
    }
}

@Model
final class TemplateExercise: Identifiable {
    public var exerciseName: String // Пазим само името, за да търсим в основната DB после
    public var durationMinutes: Double
    
    @Relationship(deleteRule: .cascade, inverse: \TemplateSet.exercise)
    public var sets: [TemplateSet] = []
    
    public var workout: TemplateWorkout?
    
    public init(exerciseName: String, durationMinutes: Double) {
        self.exerciseName = exerciseName
        self.durationMinutes = durationMinutes
    }
}

@Model
final class TemplateSet: Identifiable {
    public var reps: Int?
    public var isToFailure: Bool
    public var isTimeBased: Bool
    public var timeUnitString: String // SwiftData enum съхранението е по-лесно като String тук
    public var orderIndex: Int
    
    public var exercise: TemplateExercise?
    
    public init(reps: Int?, isToFailure: Bool, isTimeBased: Bool, timeUnitString: String, orderIndex: Int) {
        self.reps = reps
        self.isToFailure = isToFailure
        self.isTimeBased = isTimeBased
        self.timeUnitString = timeUnitString
        self.orderIndex = orderIndex
    }
}
