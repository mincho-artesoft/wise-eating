import Foundation

struct AssistantProposedItem: Equatable, Sendable, Identifiable {
    var id: UUID { foodID }
    var foodID: UUID
    var name: String
    var grams: Double
    var kcal: Double
    var proteinG: Double
}

/// A write the model asked for. Nothing is written until the person confirms.
struct AssistantPendingAction: Identifiable, Equatable, Sendable {
    enum Payload: Equatable, Sendable {
        case logFoods(day: Date, meal: String, items: [AssistantProposedItem])
        case removeFood(day: Date, meal: String, foodName: String)
        case constraints([DietaryConstraint])
        case constitution(answers: [AyurvedaDosha])
        case recipe(name: String)
        case food(name: String)
        case mealPlan(days: Int, notes: [String])
    }

    let id: UUID
    var payload: Payload
    var title: String
    var lines: [String]
    var report: ConstraintReport?

    init(id: UUID = UUID(), payload: Payload, title: String, lines: [String], report: ConstraintReport? = nil) {
        self.id = id
        self.payload = payload
        self.title = title
        self.lines = lines
        self.report = report
    }

    /// Limits that are exceeded ask "Log anyway?" instead of "Confirm".
    var needsSecondConfirmation: Bool { report?.needsSecondConfirmation ?? false }
}

/// What it takes to put a day back as it was before a confirmed log.
struct AssistantUndo: Equatable, Sendable {
    var day: Date
    var before: AssistantMealRecord
    var message: String
}

struct AssistantApplyResult: Equatable, Sendable {
    var message: String
    var undo: AssistantUndo?
}
