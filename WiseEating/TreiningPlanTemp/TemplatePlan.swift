import Foundation
import SwiftData

// Тези модели ще живеят в отделен файл (templates.store)

@Model
final class TemplatePlan: Identifiable {
    @Attribute(.unique) public var id: String
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

    // ✅ НОВО: почивен ден (липсва в JSON като workout entry)
    public var isRestDay: Bool

    @Relationship(deleteRule: .cascade, inverse: \TemplateWorkout.day)
    public var workouts: [TemplateWorkout] = []

    public var plan: TemplatePlan?

    public init(dayIndex: Int, isRestDay: Bool = false) {
        self.dayIndex = dayIndex
        self.isRestDay = isRestDay
    }
}

@Model
final class TemplateWorkout: Identifiable {
    public var workoutName: String = "Workout"

    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.workout)
    public var exercises: [TemplateExercise] = []

    public var day: TemplateDay?

    public init(workoutName: String = "Workout") {
        self.workoutName = workoutName
    }
}

@Model
final class TemplateExercise: Identifiable {
    public var exerciseName: String
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
    public var timeUnitString: String
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
