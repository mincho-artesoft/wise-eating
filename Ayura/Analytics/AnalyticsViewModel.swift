import SwiftUI
import SwiftData
import EventKit

@MainActor
final class AnalyticsViewModel: ObservableObject {
    // MARK: - Published Properties for UI
    @Published var chartData: [String: [PlottableMetric]] = [:]
    
    // MARK: - Input State from View
    var selectedTimeRange: AnalyticsView.TimeRange = .week
    var customStartDate: Date?
    var customEndDate: Date?
    var selectedNutrientIDs: Set<String> = ["calories"]
    var usesHealthKit = false
    
    // MARK: - Dependencies
    private let profile: Profile
    private weak var modelContext: ModelContext?
    #if DEBUG && targetEnvironment(simulator)
    private var isSeedingSimulatorAnalyticsData = false
    #endif
    
    // MARK: - Initializer
    init(profile: Profile, modelContext: ModelContext) {
        self.profile = profile
        self.modelContext = modelContext
    }
    
    // MARK: - Data Processing
    
    /// Основен метод за извличане и обработка на данните. Вика се от View-то.
    func processAnalyticsData() async {
           // LOG 1: Начало на процеса
           print("📊 [ANALYTICS] Starting data processing for time range: \(selectedTimeRange.rawValue)")

           guard let modelContext else {
               print("📊 [ANALYTICS] ❌ Error: ModelContext is nil. Aborting.")
               return
           }
           
           let (conceptualStartDate, conceptualEndDate) = getDateRange()

           #if DEBUG && targetEnvironment(simulator)
           await seedSimulatorAnalyticsDataIfNeeded()
           #endif

           var standaloneMetricData = profileMetricChartData(
               from: conceptualStartDate,
               until: conceptualEndDate
           )

           let sleepHoursByDay: [Date: Double]
           if usesHealthKit && selectedNutrientIDs.contains("sleep") {
               sleepHoursByDay = await SleepHealthStore.shared
                   .sleepDurationHoursByDay(
                       from: conceptualStartDate,
                       until: conceptualEndDate
                   )
               standaloneMetricData["sleep"] = sleepHoursByDay
                   .map { date, hours in
                       PlottableMetric(
                           date: date,
                           metricName: "sleep",
                           value: hours
                       )
                   }
                   .sorted { $0.date < $1.date }
           } else {
               sleepHoursByDay = [:]
           }
           // LOG 2: Извлечен период от getDateRange
           print("📊 [ANALYTICS] Conceptual date range: \(conceptualStartDate.formatted()) to \(conceptualEndDate.formatted())")
           
           // --- ПРОМЯНА: Добавяме 'await', за да извикаме асинхронния метод ---
           let allEventsInRange = await CalendarViewModel.shared.fetchEvents(
               forProfile: profile,
               startDate: conceptualStartDate,
               endDate: conceptualEndDate
           )
           // --- КРАЙ НА ПРОМЯНАТА ---

           // LOG 3: Брой намерени събития
           print("📊 [ANALYTICS] Fetched \(allEventsInRange.count) calendar events.")
           
           let eventsByDay = Dictionary(grouping: allEventsInRange) { event in
               Calendar.current.startOfDay(for: event.startDate)
           }
           // LOG 4: Брой дни със събития
           print("📊 [ANALYTICS] Grouped events into \(eventsByDay.count) unique days.")

           let needsEnergyMetrics = selectedNutrientIDs.contains("calories_burned")
               || selectedNutrientIDs.contains("net_calorie_balance")
           let exerciseCaloriesByDay = needsEnergyMetrics
               ? exerciseCaloriesBurnedByDay(
                   from: allEventsInRange,
                   startDate: conceptualStartDate,
                   endDate: conceptualEndDate
               )
               : [:]
           let healthCaloriesByDay: [Date: Double]
           if needsEnergyMetrics && usesHealthKit {
               healthCaloriesByDay = await SleepHealthStore.shared
                   .activeEnergyKilocaloriesByDay(
                       from: conceptualStartDate,
                       until: conceptualEndDate
                   )
           } else {
               healthCaloriesByDay = [:]
           }
           let burnedCaloriesByDay = exerciseCaloriesByDay.merging(
               healthCaloriesByDay,
               uniquingKeysWith: +
           )

        // --- НОВА СТЪПКА: Извличане на данни за водата ---
        // ----- 👇 НАЧАЛО НА КОРЕКЦИЯТА 👇 -----
        // Запазваме ID-то в локална константа, преди да го използваме в предиката.
        let profileID = self.profile.persistentModelID
        let waterLogDescriptor = FetchDescriptor<WaterLog>(
            predicate: #Predicate {
                $0.profile?.persistentModelID == profileID &&
                $0.date >= conceptualStartDate &&
                $0.date < conceptualEndDate
            }
        )
        // ----- 👆 КРАЙ НА КОРЕКЦИЯТА 👆 -----

        let waterLogs = (try? modelContext.fetch(waterLogDescriptor)) ?? []
        print("📊 [ANALYTICS] Fetched \(waterLogs.count) water log entries.")

        let waterLogsByDay = Dictionary(grouping: waterLogs) { log in
            Calendar.current.startOfDay(for: log.date)
        }

        // Обединяваме всички дни, за които имаме данни (хранене или вода)
        let allDates = Set(eventsByDay.keys)
            .union(waterLogsByDay.keys)
            .union(sleepHoursByDay.keys)
            .union(burnedCaloriesByDay.keys)

        guard !allDates.isEmpty,
              let actualStartDate = allDates.min(),
              let actualEndDate = allDates.max() else {
            print("📊 [ANALYTICS] No daily logs found. Showing available standalone metrics only.")
            self.chartData = standaloneMetricData
            return
        }
           // LOG 6: Реален период на данните
           print("📊 [ANALYTICS] Actual data spans from \(actualStartDate.formatted()) to \(actualEndDate.formatted())")

        var dailyLogs: [Date: (
            foods: [FoodItem: Double],
            waterMl: Double,
            burnedCalories: Double
        )] = [:]
           var currentDate = actualStartDate
           
           while currentDate <= actualEndDate {
               let dayKey = currentDate

               var foodsForDay: [FoodItem: Double] = [:]
               if let eventsForThisDay = eventsByDay[dayKey] {
                   let mealsForDay = eventsForThisDay.map { Meal(event: $0) }
                   for meal in mealsForDay {
                       for (food, grams) in meal.foods(using: modelContext) {
                           foodsForDay[food, default: 0] += grams
                       }
                   }
               }
               
               let glasses = waterLogsByDay[dayKey]?.first?.glassesConsumed ?? 0
               let waterMilliliters = Double(glasses * 200)

               dailyLogs[dayKey] = (
                   foods: foodsForDay,
                   waterMl: waterMilliliters,
                   burnedCalories: burnedCaloriesByDay[dayKey] ?? 0
               )
               
               currentDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate)!
           }
           // LOG 7: Брой дни с обработени логове
           print("📊 [ANALYTICS] Created \(dailyLogs.count) daily logs.")
           
           updateChartData(
               from: dailyLogs,
               standaloneMetricData: standaloneMetricData
           )
       }

    /// Обновява `chartData` на базата на събраните дневни логове.
    private func updateChartData(
        from dailyLogs: [Date: (
            foods: [FoodItem: Double],
            waterMl: Double,
            burnedCalories: Double
        )],
        standaloneMetricData: [String: [PlottableMetric]]
    ) {
            var newChartData = standaloneMetricData
            
            for nutrientID in selectedNutrientIDs
            where nutrientID != "profile_weight"
                && nutrientID != "profile_height"
                && nutrientID != "sleep" {
                var nutrientPoints: [PlottableMetric] = []
                for (date, logData) in dailyLogs {
                    let totalValue: Double
                    switch nutrientID {
                    case "calories":
                        totalValue = logData.foods.reduce(0) { $0 + $1.key.calories(for: $1.value) }
                    case "calories_burned":
                        totalValue = logData.burnedCalories
                    case "net_calorie_balance":
                        let consumedCalories = logData.foods.reduce(0) {
                            $0 + $1.key.calories(for: $1.value)
                        }
                        totalValue = consumedCalories - logData.burnedCalories
                    case "water":
                        totalValue = logData.waterMl
                    case "protein":
                        totalValue = logData.foods.reduce(0.0) { acc, item in
                            let (food, grams) = item
                            let refWeight = food.referenceWeightG
                            guard refWeight > 0 else { return acc }
                            let valuePerGram = (food.totalProtein?.value ?? 0) / refWeight
                            return acc + (valuePerGram * grams)
                        }
                    case "carbohydrates":
                        totalValue = logData.foods.reduce(0.0) { acc, item in
                            let (food, grams) = item
                            let refWeight = food.referenceWeightG
                            guard refWeight > 0 else { return acc }
                            let valuePerGram = (food.totalCarbohydrates?.value ?? 0) / refWeight
                            return acc + (valuePerGram * grams)
                        }
                    case "fat":
                        totalValue = logData.foods.reduce(0.0) { acc, item in
                            let (food, grams) = item
                            let refWeight = food.referenceWeightG
                            guard refWeight > 0 else { return acc }
                            let valuePerGram = (food.totalFat?.value ?? 0) / refWeight
                            return acc + (valuePerGram * grams)
                        }
                    default:
                        totalValue = nutrientTotals(for: logData.foods)[nutrientID] ?? 0
                    }
                    nutrientPoints.append(PlottableMetric(date: date, metricName: nutrientID, value: totalValue))
                }
                newChartData[nutrientID] = nutrientPoints.sorted { $0.date < $1.date }
            }
            // LOG 8: Финални данни за графиката
            print("📊 [ANALYTICS] Updating UI with chart data for \(newChartData.count) metrics.")
            for (metric, points) in newChartData {
                print("📊 [ANALYTICS]   -> Metric '\(metric)' has \(points.count) data points.")
            }
            self.chartData = newChartData
        }

    private func exerciseCaloriesBurnedByDay(
        from events: [EKEvent],
        startDate: Date,
        endDate: Date
    ) -> [Date: Double] {
        let calendar = Calendar.current
        let eventTrainingsByDay = Dictionary(
            grouping: calendarTrainings(from: events)
        ) { training in
            calendar.startOfDay(for: training.startTime)
        }

        var result: [Date: Double] = [:]
        var caloriesByTrainingPayload: [String: Double] = [:]
        var day = calendar.startOfDay(for: startDate)
        while day < endDate {
            let trainings = mergedTrainings(
                template: profile.trainings(for: day),
                calendar: eventTrainingsByDay[day] ?? []
            )
            result[day] = trainings.reduce(0) { total, training in
                total + caloriesBurned(
                    by: training,
                    cache: &caloriesByTrainingPayload
                )
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = nextDay
        }
        return result
    }

    private func calendarTrainings(from events: [EKEvent]) -> [Training] {
        let mealTemplateNames = Set(profile.meals.map(\.name))
        let trainingTemplateNames = Set(profile.trainings.map(\.name))

        return events.filter { event in
            let title = event.title ?? ""
            if let notes = event.notes,
               let decoded = OptimizedInvisibleCoder.decode(from: notes),
               decoded.starts(with: "#TRAINING#") {
                return true
            }
            if trainingTemplateNames.contains(title) {
                return true
            }
            if mealTemplateNames.contains(title) {
                return false
            }
            return false
        }
        .map(Training.init(event:))
    }

    private func mergedTrainings(
        template: [Training],
        calendar events: [Training]
    ) -> [Training] {
        var result = template.map(Training.init(from:))
        var usedEventIDs = Set<String>()

        for index in result.indices {
            let templateTraining = result[index]
            guard let matchingEvent = events.first(where: {
                $0.name == templateTraining.name
                    && $0.calendarEventID.map { !usedEventIDs.contains($0) } == true
            }) else {
                continue
            }

            result[index].startTime = matchingEvent.startTime
            result[index].endTime = matchingEvent.endTime
            result[index].notes = matchingEvent.notes
            result[index].calendarEventID = matchingEvent.calendarEventID
            if let eventID = matchingEvent.calendarEventID {
                usedEventIDs.insert(eventID)
            }
        }

        result.append(contentsOf: events.filter {
            guard let eventID = $0.calendarEventID else { return false }
            return !usedEventIDs.contains(eventID)
        })
        return result
    }

    private func caloriesBurned(
        by training: Training,
        cache: inout [String: Double]
    ) -> Double {
        let cacheKey = training.notes ?? ""
        if let cachedValue = cache[cacheKey] {
            return cachedValue
        }
        guard let modelContext else { return 0 }
        let value = training.exercises(using: modelContext).reduce(0) { total, item in
            let (exercise, durationSeconds) = item
            guard let met = exercise.metValue,
                  met.isFinite,
                  met > 0,
                  durationSeconds.isFinite,
                  durationSeconds > 0 else {
                return total
            }
            let caloriesPerMinute = (met * 3.5 * profile.weight) / 200
            return total + caloriesPerMinute * (durationSeconds / 60)
        }
        cache[cacheKey] = value
        return value
    }

    #if DEBUG && targetEnvironment(simulator)
    private func seedSimulatorAnalyticsDataIfNeeded() async {
        let defaultsKey = "analytics.simulatorTestData.v1"
        guard !UserDefaults.standard.bool(forKey: defaultsKey),
              !isSeedingSimulatorAnalyticsData,
              let modelContext else {
            return
        }
        isSeedingSimulatorAnalyticsData = true
        defer { isSeedingSimulatorAnalyticsData = false }

        var foodDescriptor = FetchDescriptor<FoodItem>()
        foodDescriptor.fetchLimit = 500
        let food = (try? modelContext.fetch(foodDescriptor))?.first(where: {
            !$0.name.contains("=")
                && !$0.name.contains("|")
                && $0.referenceWeightG > 0
                && $0.calories(for: $0.referenceWeightG) >= 50
        })

        var exerciseDescriptor = FetchDescriptor<ExerciseItem>()
        exerciseDescriptor.fetchLimit = 500
        let exercise = (try? modelContext.fetch(exerciseDescriptor))?
            .filter { ($0.metValue ?? 0) > 0 }
            .max { ($0.metValue ?? 0) < ($1.metValue ?? 0) }

        guard food != nil || exercise != nil else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let rangeStart = calendar.date(byAdding: .day, value: -6, to: today),
              let rangeEnd = calendar.date(byAdding: .day, value: 1, to: today) else {
            return
        }
        let existingEvents = await CalendarViewModel.shared.fetchEvents(
            forProfile: profile,
            startDate: rangeStart,
            endDate: rangeEnd
        )
        let consumedTargets = [
            1_800.0, 100.0, 2_200.0, 120.0, 1_600.0, 90.0, 1_400.0
        ]
        let workoutMinutes = [55.0, 80.0, 40.0, 90.0, 50.0, 75.0, 45.0]

        for dayOffset in 0...6 {
            guard let day = calendar.date(
                byAdding: .day,
                value: -dayOffset,
                to: today
            ) else {
                continue
            }

            if let food {
                let mealTitle = "Analytics Test Meal"
                let mealExists = existingEvents.contains {
                    $0.title == mealTitle
                        && calendar.isDate($0.startDate, inSameDayAs: day)
                }
                if !mealExists {
                    let caloriesPerGram = food.calories(for: 1)
                    if caloriesPerGram > 0,
                       let start = calendar.date(
                           bySettingHour: 13,
                           minute: 0,
                           second: 0,
                           of: day
                       ) {
                        let grams = consumedTargets[dayOffset] / caloriesPerGram
                        let visiblePayload = "\(food.name)=\(grams)"
                        let payload = OptimizedInvisibleCoder.encode(
                            from: visiblePayload
                        )
                        _ = await CalendarViewModel.shared.createEvent(
                            forProfile: profile,
                            startDate: start,
                            endDate: start.addingTimeInterval(45 * 60),
                            title: mealTitle,
                            invisiblePayload: payload
                        )
                    }
                }
            }

            if let exercise {
                let workoutTitle = "Analytics Test Workout"
                let workoutExists = existingEvents.contains {
                    $0.title == workoutTitle
                        && calendar.isDate($0.startDate, inSameDayAs: day)
                }
                if !workoutExists,
                   let start = calendar.date(
                       bySettingHour: 18,
                       minute: 0,
                       second: 0,
                       of: day
                   ) {
                    let durationSeconds = workoutMinutes[dayOffset] * 60
                    let training = Training(
                        name: workoutTitle,
                        startTime: start,
                        endTime: start.addingTimeInterval(durationSeconds)
                    )
                    training.updateNotes(
                        exercises: [exercise: durationSeconds],
                        detailedLog: nil
                    )
                    let payload = OptimizedInvisibleCoder.encode(
                        from: training.notes ?? "#TRAINING#"
                    )
                    _ = await CalendarViewModel.shared.createOrUpdateTrainingEvent(
                        forProfile: profile,
                        training: training,
                        exercisesPayload: payload
                    )
                }
            }
        }
        UserDefaults.standard.set(true, forKey: defaultsKey)
    }
    #endif

    private func profileMetricChartData(
        from startDate: Date,
        until endDate: Date
    ) -> [String: [PlottableMetric]] {
        let records = profile.weightHeightHistory
            .filter { $0.date >= startDate && $0.date < endDate }
            .sorted { $0.date < $1.date }
        let isImperial = GlobalState.measurementSystem == "Imperial"
        var data: [String: [PlottableMetric]] = [:]

        if selectedNutrientIDs.contains("profile_weight") {
            data["profile_weight"] = records.map { record in
                let value = isImperial
                    ? UnitConversion.kgToLbs(record.weight)
                    : record.weight
                return PlottableMetric(
                    date: record.date,
                    metricName: "profile_weight",
                    value: value
                )
            }
        }

        if selectedNutrientIDs.contains("profile_height") {
            data["profile_height"] = records.map { record in
                let value = isImperial
                    ? UnitConversion.cmToInches(record.height)
                    : record.height
                return PlottableMetric(
                    date: record.date,
                    metricName: "profile_height",
                    value: value
                )
            }
        }

        return data
    }

    /// Изчислява общото количество на всеки нутриент за даден речник с храни.
    private func nutrientTotals(for foods: [FoodItem : Double]) -> [String : Double] {
        var sums: [String : Double] = [:]
        for (food, grams) in foods {
            let allNutrientIDs = allVitamins.map { "vit_\($0.key)" } + allMinerals.map { "min_\($0.key)" }
            for id in allNutrientIDs {
                sums[id, default: 0] += food.amount(of: id, grams: grams)
            }
        }
        return sums
    }
    
    /// Изчислява началната и крайна дата на базата на избрания период.
    private func getDateRange() -> (start: Date, end: Date) {
        let now = Date()
        let calendar = Calendar.current
        
        let conceptualStartDate: Date
        let conceptualEndDate: Date

        switch selectedTimeRange {
        case .week:
            conceptualStartDate = calendar.date(byAdding: .day, value: -6, to: now)!
            conceptualEndDate = now
        case .month:
            conceptualStartDate = calendar.date(byAdding: .month, value: -1, to: now)!
            conceptualEndDate = now
        case .year:
            conceptualStartDate = calendar.date(byAdding: .year, value: -1, to: now)!
            conceptualEndDate = now
        // ----- 👇 НАЧАЛО НА ПРОМЯНАТА 👇 -----
        case .all:
            // LOG 9: Специфично за 'All Time'
            print("📊 [ANALYTICS] Calculating date range for 'All Time' (from Jan 1, 2025).")
            // Започваме от 1-ви януари 2025 г.
            conceptualStartDate = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
            conceptualEndDate = now
        // ----- 👆 КРАЙ НА ПРОМЯНАТА 👆 -----
        case .custom:
            conceptualStartDate = customStartDate ?? calendar.date(byAdding: .month, value: -1, to: now)!
            conceptualEndDate = customEndDate ?? now
        }
        
        // Нормализираме датите за заявката
        let finalStartDate = calendar.startOfDay(for: conceptualStartDate)
        
        // За да включим всички събития от крайния ден, използваме началото на СЛЕДВАЩИЯ ден.
        let startOfFinalEndDay = calendar.startOfDay(for: conceptualEndDate)
        guard let inclusiveEndDate = calendar.date(byAdding: .day, value: 1, to: startOfFinalEndDay) else {
            // Резервен вариант, който на практика никога не трябва да се случва
            return (finalStartDate, startOfFinalEndDay)
        }
        
        return (finalStartDate, inclusiveEndDate)
    }
    
    // Тези са нужни за `nutrientTotals`, затова ги копираме и тук
    private var allVitamins: [Vitamin] { (try? modelContext?.fetch(FetchDescriptor<Vitamin>())) ?? [] }
    private var allMinerals: [Mineral] { (try? modelContext?.fetch(FetchDescriptor<Mineral>())) ?? [] }
}
