import SwiftUI
import SwiftData

@MainActor
final class AnalyticsViewModel: ObservableObject {
    // MARK: - Published Properties for UI
    @Published var chartData: [String: [PlottableMetric]] = [:]
    
    // MARK: - Input State from View
    var selectedTimeRange: AnalyticsView.TimeRange = .week
    var customStartDate: Date?
    var customEndDate: Date?
    var selectedNutrientIDs: Set<String> = ["calories"]
    
    // MARK: - Dependencies
    private let profile: Profile
    private weak var modelContext: ModelContext?
    
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
           let profileMetricData = profileMetricChartData(
               from: conceptualStartDate,
               until: conceptualEndDate
           )
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
        let allDates = Set(eventsByDay.keys).union(waterLogsByDay.keys)

        guard !allDates.isEmpty,
              let actualStartDate = allDates.min(),
              let actualEndDate = allDates.max() else {
            print("📊 [ANALYTICS] No events or water logs found. Showing available profile metrics only.")
            self.chartData = profileMetricData
            return
        }
           // LOG 6: Реален период на данните
           print("📊 [ANALYTICS] Actual data spans from \(actualStartDate.formatted()) to \(actualEndDate.formatted())")

        var dailyLogs: [Date: (foods: [FoodItem: Double], waterMl: Double)] = [:]
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

               dailyLogs[dayKey] = (foods: foodsForDay, waterMl: waterMilliliters)
               
               currentDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate)!
           }
           // LOG 7: Брой дни с обработени логове
           print("📊 [ANALYTICS] Created \(dailyLogs.count) daily logs.")
           
           updateChartData(from: dailyLogs, profileMetricData: profileMetricData)
       }

    /// Обновява `chartData` на базата на събраните дневни логове.
    private func updateChartData(
        from dailyLogs: [Date: (foods: [FoodItem: Double], waterMl: Double)],
        profileMetricData: [String: [PlottableMetric]]
    ) {
            var newChartData = profileMetricData
            
            for nutrientID in selectedNutrientIDs
            where nutrientID != "profile_weight" && nutrientID != "profile_height" {
                var nutrientPoints: [PlottableMetric] = []
                for (date, logData) in dailyLogs {
                    let totalValue: Double
                    switch nutrientID {
                    case "calories":
                        totalValue = logData.foods.reduce(0) { $0 + $1.key.calories(for: $1.value) }
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
