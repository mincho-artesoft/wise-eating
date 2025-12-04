// ==== FILE: WiseEating/Main/Notification/NotificationDelegate.swift ====
import Foundation
import UserNotifications

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    
    /// Показва нотификацията, докато приложението е активно (на преден план).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        NotificationCenter.default.post(name: .unreadNotificationStatusChanged, object: nil)
        completionHandler([.banner, .sound, .badge])
    }
    
    /// Извиква се, когато потребителят натисне нотификация.
    func userNotificationCenter(
         _ center: UNUserNotificationCenter,
         didReceive response: UNNotificationResponse,
         withCompletionHandler completionHandler: @escaping () -> Void
     ) {
         let userInfo = response.notification.request.content.userInfo
         
        // Извличаме всички необходими стойности на текущия (фонов) thread.
        let profileID: UUID? = {
            if let profileIDString = userInfo["profileID"] as? String {
                return UUID(uuidString: profileIDString)
            }
            return nil
        }()
        
        let listID: UUID? = {
            if let listIDString = userInfo["shoppingListID"] as? String {
                return UUID(uuidString: listIDString)
            }
            return nil
        }()
        
        let mealID: UUID? = {
            if let mealIDString = userInfo["mealID"] as? String {
                return UUID(uuidString: mealIDString)
            }
            return nil
        }()
        
        let mealDate: Date? = {
            if let mealDateTimeInterval = userInfo["mealDate"] as? TimeInterval {
                return Date(timeIntervalSince1970: mealDateTimeInterval)
            }
            return nil
        }()
        
        let trainingID: UUID? = {
            if let trainingIDString = userInfo["trainingID"] as? String {
                return UUID(uuidString: trainingIDString)
            }
            return nil
        }()
        
        let trainingDate: Date? = {
            if let trainingDateTimeInterval = userInfo["trainingDate"] as? TimeInterval {
                return Date(timeIntervalSince1970: trainingDateTimeInterval)
            }
            return nil
        }()
        
        let trainingName = userInfo["trainingName"] as? String
        
        let generationJobID: UUID? = {
            if let jobIDString = userInfo["generationJobID"] as? String {
                return UUID(uuidString: jobIDString)
            }
            return nil
        }()
        
        let jobType: AIGenerationJob.JobType? = {
            if let jobTypeRawValue = userInfo["jobType"] as? String {
                return AIGenerationJob.JobType(rawValue: jobTypeRawValue)
            }
            return nil
        }()
        
        let openBadges = userInfo["openBadges"] as? String
        
         Task {
             await MainActor.run {
                 let coordinator = NavigationCoordinator.shared

                 // --- НАЧАЛО НА КОРЕКЦИЯТА ---
                 // ПРЕМАХВАМЕ ОБЩОТО ЗАДАВАНЕ НА PENDINGPROFILEID.
                 // ТО ЩЕ СЕ УПРАВЛЯВА ОТ ВСЕКИ КОНКРЕТЕН СЛУЧАЙ ПО-ДОЛУ.

                 // Обработваме конкретното съдържание на нотификацията с if-else if,
                 // за да сме сигурни, че се изпълнява само ЕДНА навигационна логика.
                 if let listID = listID {
                     print("DELEGATE: Потребителят натисна нотификация за Shopping List с ID: \(listID)")
                     coordinator.pendingProfileID = profileID
                     coordinator.pendingShoppingListID = listID
                 } else if let mealID = mealID, let mealDate = mealDate {
                     print("DELEGATE: Потребителят натисна нотификация за Meal с ID: \(mealID) на дата: \(mealDate)")
                     coordinator.pendingProfileID = profileID
                     coordinator.pendingMealID = mealID
                     coordinator.pendingMealDate = mealDate
                 } else if let trainingID = trainingID, let trainingDate = trainingDate, let trainingName = trainingName {
                     print("DELEGATE: Потребителят натисна нотификация за Training с ID: \(trainingID) на дата: \(trainingDate)")
                     coordinator.pendingProfileID = profileID
                     coordinator.pendingTrainingID = trainingID
                     coordinator.pendingTrainingDate = trainingDate
                     coordinator.pendingTrainingName = trainingName
                 } else if let jobID = generationJobID, let type = jobType {
                    print("DELEGATE: Потребителят натисна нотификация за AI Job с ID: \(jobID) и тип: \(type.rawValue)")
                    
                    if type == .nutritionsDetailDailyMealPlan {
                        coordinator.pendingApplyDailyMealPlanJobID = jobID
                    } else if type == .trainingViewDailyPlan {
                        coordinator.pendingApplyDailyTreaningPlanJobID = jobID
                    } else {
                        coordinator.pendingProfileID = profileID
                        coordinator.pendingTab = .aiGenerate
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            coordinator.sourceAIGenerationJobID = jobID
                            coordinator.pendingAIPlanJobType = type
                        }
                    }
                 } else if let openBadges = openBadges, openBadges == "true" {
                    print("DELEGATE: Потребителят натисна нотификация за значка.")
                    // Задаваме САМО pendingBadgeProfileID.
                    // Неговият наблюдател в RootView ще се погрижи да смени профила И таба.
                    coordinator.pendingBadgeProfileID = profileID
                 }
                 // --- КРАЙ НА КОРЕКЦИЯТА ---
             }
         }
         
         completionHandler()
     }
}
