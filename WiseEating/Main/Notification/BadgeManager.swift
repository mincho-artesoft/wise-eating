// WiseEating/Main/Notification/BadgeManager.swift
import Foundation
import SwiftData
import UserNotifications

// +++ НАЧАЛО НА ПРОМЯНАТА (1/3): Добавяме нов мениджър за проследяване на активността +++
@MainActor
class UsageTrackingManager {
    static let shared = UsageTrackingManager()
    private let userDefaultsKey = "appUsageHistory"

    private init() {}

    /// Записва, че даден профил е бил активен на днешния ден.
    func logUsage(for profile: Profile, on date: Date = Date()) {
          let profileID = profile.id.uuidString
          // --- ПРОМЯНА: Използваме подадената дата ---
          let today = Calendar.current.startOfDay(for: date)

          var usageHistory = loadUsageHistory()
          var datesForProfile = usageHistory[profileID] ?? []

          if !datesForProfile.contains(where: { Calendar.current.isDate(today, inSameDayAs: $0) }) {
              datesForProfile.append(today)
              usageHistory[profileID] = datesForProfile
              saveUsageHistory(usageHistory)
              print("✅ Usage logged for profile '\(profile.name)' on \(today.formatted(date: .abbreviated, time: .omitted)). Total unique days: \(datesForProfile.count)")
          } else {
               print("ℹ️ Usage for profile '\(profile.name)' already logged for today.")
          }
      }

    /// Връща броя уникални дни, в които профилът е бил активен.
    func getUsageCount(for profile: Profile) -> Int {
        let profileID = profile.id.uuidString
        let usageHistory = loadUsageHistory()
        return usageHistory[profileID]?.count ?? 0
    }

    private func loadUsageHistory() -> [String: [Date]] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: [Date]].self, from: data)) ?? [:]
    }

    private func saveUsageHistory(_ history: [String: [Date]]) {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
// +++ КРАЙ НА ПРОМЯНАТА (1/3) +++


// 1. Дефинициите на значките вече са тук, за да са централизирани
struct BadgeItem: Identifiable, Sendable {
    let id: String // Използваме imageName като уникален ID
    let imageName: String
    let label: String
    let threshold: Int
}

struct BadgeGroup: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let items: [BadgeItem]
}

// --- НАЧАЛО НА ПРОМЯНАТА: actor -> @MainActor class ---
@MainActor
class BadgeManager {
// --- КРАЙ НА ПРОМЯНАТА ---
    static let shared = BadgeManager()
    private init() {}

    private let badgeGroups: [BadgeGroup] = [
        .init(title: "Foods", items: [
            .init(id: "Foods 25", imageName: "Foods 25", label: "25 Foods", threshold: 25),
            .init(id: "Foods 50", imageName: "Foods 50", label: "50 Foods", threshold: 50),
            .init(id: "Foods 100", imageName: "Foods 100", label: "100 Foods", threshold: 100)
        ]),
        .init(title: "Nutrition", items: [
            .init(id: "Nutrition 3d", imageName: "Nutrition 3d", label: "3 Day Streak", threshold: 3),
            .init(id: "Nutrition 1w", imageName: "Nutrition 1w", label: "1 Week Streak", threshold: 7),
            .init(id: "Nutrition 1m", imageName: "Nutrition 1m", label: "1 Month Streak", threshold: 30)
        ]),
        .init(title: "Exercises", items: [
            .init(id: "Exercises 10", imageName: "Exercises 10", label: "10 Exercises", threshold: 10),
            .init(id: "Exercises 25", imageName: "Exercises 25", label: "25 Exercises", threshold: 25),
            .init(id: "Exercises 50", imageName: "Exercises 50", label: "50 Exercises", threshold: 50)
        ]),
        .init(title: "Workout", items: [
            .init(id: "Workout 3d", imageName: "Workout 3d", label: "3 Days Streak", threshold: 3),
            .init(id: "Workout 1w", imageName: "Workout 1w", label: "1 Week Streak", threshold: 7),
            .init(id: "Workout 1m", imageName: "Workout 1m", label: "1 Month Streak", threshold: 30)
        ]),
        // +++ НАЧАЛО НА ПРОМЯНАТА (2/3): Коригираме праговете от nil на конкретни стойности и премахваме subtitle +++
        .init(
            title: "Usage",
            items: [
                .init(id: "Usage 3d", imageName: "Usage 3d", label: "3 Days Active", threshold: 3),
                .init(id: "Usage 1w", imageName: "Usage 1w", label: "1 Week Active", threshold: 7),
                .init(id: "Usage 1m", imageName: "Usage 1m", label: "1 Month Active", threshold: 30)
            ]
        ),
        // +++ КРАЙ НА ПРОМЯНАТА (2/3) +++
    ]

    /// Основен метод, който се извиква след запазване на данни.
    func checkAndAwardBadges(for profile: Profile, using modelContext: ModelContext) async {
        let (uniqueFoods, nutritionStreak) = await calculateNutritionStats(for: profile)
        let (uniqueExercises, workoutStreak) = await calculateExerciseStats(for: profile)
        // +++ НАЧАЛО НА ПРОМЯНАТА (3/3): Добавяме изчисляване на дните на активност +++
        let usageDays = UsageTrackingManager.shared.getUsageCount(for: profile)
        // +++ КРАЙ НА ПРОМЯНАТА (3/3) +++
        
        var newlyUnlockedBadges: [BadgeItem] = []
        let alreadyUnlocked = Set(profile.unlockedBadgeIDs)

        for group in badgeGroups {
            for item in group.items {
                // Проверяваме дали вече е отключена
                guard !alreadyUnlocked.contains(item.id) else { continue }
                
                var shouldUnlock = false
                switch group.title {
                case "Foods":
                    shouldUnlock = uniqueFoods >= item.threshold
                case "Nutrition":
                    shouldUnlock = nutritionStreak >= item.threshold
                case "Exercises":
                    shouldUnlock = uniqueExercises >= item.threshold
                case "Workout":
                    shouldUnlock = workoutStreak >= item.threshold
                // +++ НАЧАЛО НА ПРОМЯНАТА (3/3): Добавяме case за Usage +++
                case "Usage":
                    shouldUnlock = usageDays >= item.threshold
                // +++ КРАЙ НА ПРОМЯНАТА (3/3) +++
                default:
                    break
                }
                
                if shouldUnlock {
                    newlyUnlockedBadges.append(item)
                    profile.unlockedBadgeIDs.append(item.id)
                }
            }
        }

        if !newlyUnlockedBadges.isEmpty {
            do {
                try modelContext.save()
                for badge in newlyUnlockedBadges {
                    try await sendNotification(for: badge, profileID: profile.id)
                }
            } catch {
                print("BadgeManager: Failed to save profile or send notification - \(error)")
            }
        }
    }

    private func sendNotification(for badge: BadgeItem, profileID: UUID) async throws {
        _ = try await NotificationManager.shared.scheduleNotification(
            title: "Badge Unlocked!",
            body: "Congratulations! You've unlocked the '\(badge.label)' badge.",
            timeInterval: 1,
            userInfo: ["openBadges": "true", "profileID": profileID.uuidString], // Безопасен payload
            profileID: profileID
        )
    }
    
    // Всички изчислителни функции остават тук и са private
    
    func calculateNutritionStats(for profile: Profile) async -> (uniqueFoods: Int, streak: Int) {
        let startDate = Calendar.current.date(byAdding: .year, value: -10, to: Date()) ?? Date()
        let endDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        let allEvents = await CalendarViewModel.shared.fetchEvents(forProfile: profile, startDate: startDate, endDate: endDate)

        let mealTemplateNames = Set(profile.meals.map { $0.name })
        let trainingTemplateNames = Set(profile.trainings.map { $0.name })

        let mealEvents = allEvents.filter { event in
            let title = event.title ?? ""
            if let notes = event.notes, let decoded = OptimizedInvisibleCoder.decode(from: notes) {
                if decoded.trimmingCharacters(in: .whitespaces).starts(with: "{") { return false }
                if decoded.starts(with: "#TRAINING#") { return false }
            }
            if trainingTemplateNames.contains(title) { return false }
            if mealTemplateNames.contains(title) { return true }
            if let notes = event.notes, OptimizedInvisibleCoder.decode(from: notes) != nil { return true }
            return false
        }
        
        let uniqueDates = Set(mealEvents.map { Calendar.current.startOfDay(for: $0.startDate) })
        let sortedDates = uniqueDates.sorted()
        
        var longestStreak = 0
        var currentStreak = 0
        if !sortedDates.isEmpty {
            currentStreak = 1
            longestStreak = 1
            for i in 1..<sortedDates.count {
                if let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: sortedDates[i-1]), nextDay == sortedDates[i] {
                    currentStreak += 1
                } else {
                    currentStreak = 1
                }
                if currentStreak > longestStreak { longestStreak = currentStreak }
            }
        }
        
        let mealNotesList = mealEvents.compactMap { $0.notes }
        let uniqueFoods = await Task.detached(priority: .userInitiated) {
            var uniqueFoodNames = Set<String>()
            for notes in mealNotesList {
                guard !notes.isEmpty, let decoded = OptimizedInvisibleCoder.decode(from: notes) else { continue }
                decoded.split(separator: "|").forEach {
                    if let name = $0.split(separator: "=", maxSplits: 1).first {
                        uniqueFoodNames.insert(String(name).trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                    }
                }
            }
            return uniqueFoodNames.count
        }.value

        return (uniqueFoods, longestStreak)
    }

    func calculateExerciseStats(for profile: Profile) async -> (uniqueExercises: Int, streak: Int) {
        struct SendableEventInfo: Sendable { let notes: String?; let startDate: Date }

        let startDate = Calendar.current.date(byAdding: .year, value: -10, to: Date()) ?? Date()
        let endDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        let allEvents = await CalendarViewModel.shared.fetchEvents(forProfile: profile, startDate: startDate, endDate: endDate)

        let mealTemplateNames = Set(profile.meals.map { $0.name })
        let trainingTemplateNames = Set(profile.trainings.map { $0.name })
        
        let trainingEvents = allEvents.filter { event in
            let title = event.title ?? ""
            if let notes = event.notes, let decoded = OptimizedInvisibleCoder.decode(from: notes), decoded.starts(with: "#TRAINING#") { return true }
            if trainingTemplateNames.contains(title) { return true }
            if mealTemplateNames.contains(title) { return false }
            return false
        }
        
        let trainingEventInfo = trainingEvents.map { SendableEventInfo(notes: $0.notes, startDate: $0.startDate) }

        return await Task.detached(priority: .userInitiated) {
            var uniqueExerciseIDs = Set<String>()
            for eventInfo in trainingEventInfo {
                guard let notes = eventInfo.notes, let decoded = OptimizedInvisibleCoder.decode(from: notes) else { continue }
                decoded.split(separator: "|").forEach {
                    if let idPart = $0.split(separator: "=", maxSplits: 1).first {
                        let cleanID = String(idPart).replacingOccurrences(of: "#TRAINING#", with: "")
                        if !cleanID.isEmpty { uniqueExerciseIDs.insert(cleanID) }
                    }
                }
            }
            
            let uniqueDates = Set(trainingEventInfo.map { Calendar.current.startOfDay(for: $0.startDate) })
            let sortedDates = uniqueDates.sorted()
            
            var longestStreak = 0
            var currentStreak = 0
            if !sortedDates.isEmpty {
                currentStreak = 1; longestStreak = 1
                for i in 1..<sortedDates.count {
                    if let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: sortedDates[i-1]), nextDay == sortedDates[i] {
                        currentStreak += 1
                    } else {
                        currentStreak = 1
                    }
                    if currentStreak > longestStreak { longestStreak = currentStreak }
                }
            }
            
            return (uniqueExerciseIDs.count, longestStreak)
        }.value
    }
}
