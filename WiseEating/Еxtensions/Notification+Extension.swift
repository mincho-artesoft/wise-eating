import Foundation

extension Notification.Name {
    static let editNutritionForEvent = Notification.Name("editNutritionForEvent")
    static let editTrainingForEvent = Notification.Name("editTrainingForEvent")
    static let calendarsSelectionChanged = Notification.Name("calendarsSelectionChanged")
    static let notificationDraggableMenuViewSub = Notification.Name("notificationDraggableMenuViewSub")
    static let newMealCreated = Notification.Name("newMealCreated")
    static let newTrainingCreated = Notification.Name("newTrainingCreated")
    static let backGroundChanged = Notification.Name("backGroundChanged")
    static let shoppingListDidChange = Notification.Name("shoppingListDidChangeNotification")
    static let foodFavoriteToggled = Notification.Name("foodFavoriteToggled")
    static let exerciseFavoriteToggled = Notification.Name("exerciseFavoriteToggled")
    static let mealTimeDidChange = Notification.Name("mealTimeDidChangeNotification")
    static let openProfilesDrawer = Notification.Name("openProfilesDrawer")
    static let forceCalendarReload = Notification.Name("forceCalendarReloadNotification")
    static let dailyMealsGenerated = Notification.Name("dailyMealsGenerated")
    static let unreadNotificationStatusChanged = Notification.Name("unreadNotificationStatusChanged")
    static let triggerAIGeneration = Notification.Name("triggerAIGeneration")
    
    static let aiJobCompleted = Notification.Name("aiJobCompletedNotification")
    static let aiJobCompletedMealPlan = Notification.Name("aiJobCompletedNotificationMealPlan")
    static let aiFoodDetailJobCompleted = Notification.Name("aiFoodDetailJobCompleted")
    static let aiRecipeJobCompleted = Notification.Name("aiRecipeJobCompleted")
    static let aiMenuJobCompleted = Notification.Name("aiRecipeJobCompleted")
    static let aiExerciseDetailJobCompleted = Notification.Name("aiExerciseDetailJobCompleted")
    static let aiDietJobCompleted = Notification.Name("aiDietJobCompleted")
    static let aiTrainingPlanJobCompleted = Notification.Name("aiTrainingPlanJobCompleted")
    static let aiWorkoutJobCompleted = Notification.Name("aiWorkoutJobCompleted")
    static let aiTrainingJobCompleted = Notification.Name("aiTrainingJobCompleted")
    static let aiJobStatusDidChange = Notification.Name("aiJobStatusDidChange")
    static let aiAvailabilityDidChange = Notification.Name("AIAvailabilityDidChange")
    static let openSubscriptionFlow = Notification.Name("openSubscriptionFlow")
}

struct EditNutritionPayload {
    let calendarID: String
    let date: Date
    let mealName: String
}
