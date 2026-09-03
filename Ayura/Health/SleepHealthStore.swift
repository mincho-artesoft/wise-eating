import Foundation
import Combine
import HealthKit

struct HealthWorkoutActivity: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let symbolName: String
    let startDate: Date
    let endDate: Date
    let activeEnergyKilocalories: Double
    let sourceName: String

    var duration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate))
    }
}

struct HealthActivitySummary: Equatable, Sendable {
    let activeEnergyKilocalories: Double
    let stepCount: Int
    let workouts: [HealthWorkoutActivity]

    static let zero = HealthActivitySummary(
        activeEnergyKilocalories: 0,
        stepCount: 0,
        workouts: []
    )

    var hasData: Bool {
        activeEnergyKilocalories > 0 || stepCount > 0 || !workouts.isEmpty
    }
}

@MainActor
final class SleepHealthStore: ObservableObject {
    static let shared = SleepHealthStore()

    @Published private(set) var isHealthKitEnabled = false
    private let healthStore = HKHealthStore()
    private var hasRequestedAuthorization = false

    #if DEBUG && targetEnvironment(simulator)
    private static let simulatorSeedMetadataKey = "com.ayura.debug.healthkit-seed"
    private static let simulatorSeedDefaultsPrefix = "Ayura.DebugHealthKitSeed.v1"
    #endif

    private init() {}

    func requestReadAuthorizationIfNeeded() async -> Bool {
        if hasRequestedAuthorization {
            return isHealthKitEnabled
        }

        guard HKHealthStore.isHealthDataAvailable(),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let stepCountType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            isHealthKitEnabled = false
            return false
        }

        let workoutType = HKObjectType.workoutType()
        let readTypes: Set<HKObjectType> = [
            sleepType,
            activeEnergyType,
            stepCountType,
            workoutType
        ]
        var shareTypes: Set<HKSampleType> = []

        #if DEBUG && targetEnvironment(simulator)
        shareTypes = [sleepType, activeEnergyType, stepCountType, workoutType]
        #endif

        do {
            try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
            hasRequestedAuthorization = true
            isHealthKitEnabled = true

            #if DEBUG && targetEnvironment(simulator)
            await seedSimulatorHealthKitIfNeeded(
                sleepType: sleepType,
                activeEnergyType: activeEnergyType,
                stepCountType: stepCountType,
                workoutType: workoutType
            )
            #endif

            return true
        } catch {
            isHealthKitEnabled = false
            return false
        }
    }

    func sleepIntervals(for day: Date, calendar: Calendar = .current) async -> [DateInterval] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }

        return await sleepIntervals(overlapping: dayStart, end: dayEnd)
    }

    /// Returns total recorded sleep in hours, attributed to the day on which
    /// the sleep session ends. This keeps an overnight session on one chart
    /// day instead of counting it once before and once after midnight.
    func sleepDurationHoursByDay(
        from startDate: Date,
        until endDate: Date,
        calendar: Calendar = .current
    ) async -> [Date: Double] {
        let firstDay = calendar.startOfDay(for: startDate)
        guard firstDay < endDate,
              let queryStart = calendar.date(
                byAdding: .day,
                value: -1,
                to: firstDay
              ) else {
            return [:]
        }

        let intervals = await sleepIntervals(
            overlapping: queryStart,
            end: endDate
        )
        guard !Task.isCancelled else { return [:] }

        var durationByDay: [Date: TimeInterval] = [:]
        for session in Self.groupedSleepSessions(intervals) {
            guard let sessionEnd = session.last?.end else { continue }
            let finalMoment = sessionEnd.addingTimeInterval(-1)
            let wakeDay = calendar.startOfDay(for: finalMoment)
            guard wakeDay >= firstDay, wakeDay < endDate else { continue }
            // Only the recorded asleep fragments are summed. Awake gaps help
            // associate fragments with the same night but are never counted.
            durationByDay[wakeDay, default: 0] += session.reduce(0) {
                $0 + $1.duration
            }
        }

        return durationByDay.mapValues { $0 / (60 * 60) }
    }

    private func sleepIntervals(
        overlapping startDate: Date,
        end endDate: Date
    ) async -> [DateInterval] {
        guard startDate < endDate,
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              await requestReadAuthorizationIfNeeded(),
              !Task.isCancelled else {
            return []
        }

        let datePredicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: []
        )
        let samplePredicate = HKSamplePredicate<HKCategorySample>.categorySample(
            type: sleepType,
            predicate: datePredicate
        )
        let descriptor = HKSampleQueryDescriptor<HKCategorySample>(
            predicates: [samplePredicate],
            sortDescriptors: []
        )

        do {
            let samples = try await descriptor.result(for: healthStore)
            guard !Task.isCancelled else { return [] }

            let asleepValues = HKCategoryValueSleepAnalysis.allAsleepValues
            let asleepIntervals = samples.compactMap { sample -> DateInterval? in
                guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value),
                      asleepValues.contains(value),
                      sample.startDate < sample.endDate else {
                    return nil
                }
                return DateInterval(start: sample.startDate, end: sample.endDate)
            }
            let inBedIntervals = samples.compactMap { sample -> DateInterval? in
                guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value),
                      value == .inBed,
                      sample.startDate < sample.endDate else {
                    return nil
                }
                return DateInterval(start: sample.startDate, end: sample.endDate)
            }

            // Prefer actual sleep stages for each recorded session. Keep an
            // "in bed" interval only when that particular session has no
            // overlapping staged sleep; otherwise one staged sample elsewhere
            // in the day could incorrectly hide the whole night's data.
            let inBedFallbacks = inBedIntervals.filter { inBedInterval in
                !asleepIntervals.contains { asleepInterval in
                    asleepInterval.start < inBedInterval.end
                        && asleepInterval.end > inBedInterval.start
                }
            }
            let intervals = asleepIntervals + inBedFallbacks
            return Self.mergingOverlappingIntervals(intervals)
        } catch {
            return []
        }
    }

    func activitySummary(
        for day: Date,
        calendar: Calendar = .current
    ) async -> HealthActivitySummary {
        guard await requestReadAuthorizationIfNeeded(), !Task.isCancelled else {
            return .zero
        }

        async let activeEnergy = totalQuantity(
            for: .activeEnergyBurned,
            unit: .kilocalorie(),
            day: day,
            calendar: calendar
        )
        async let steps = totalQuantity(
            for: .stepCount,
            unit: .count(),
            day: day,
            calendar: calendar
        )
        async let workouts = workoutActivities(for: day, calendar: calendar)

        let result = await (activeEnergy, steps, workouts)
        guard !Task.isCancelled else { return .zero }

        return HealthActivitySummary(
            activeEnergyKilocalories: max(0, result.0),
            stepCount: max(0, Int(result.1.rounded())),
            workouts: result.2
        )
    }

    /// Returns HealthKit active energy grouped by local calendar day. A single
    /// statistics-collection query keeps long Analytics ranges efficient.
    func activeEnergyKilocaloriesByDay(
        from startDate: Date,
        until endDate: Date,
        calendar: Calendar = .current
    ) async -> [Date: Double] {
        guard startDate < endDate,
              await requestReadAuthorizationIfNeeded(),
              !Task.isCancelled,
              let activeEnergyType = HKObjectType.quantityType(
                forIdentifier: .activeEnergyBurned
              ) else {
            return [:]
        }

        let rangePredicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: [.strictStartDate]
        )
        let samplePredicate = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: activeEnergyType,
            predicate: rangePredicate
        )
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: samplePredicate,
            options: .cumulativeSum,
            anchorDate: calendar.startOfDay(for: startDate),
            intervalComponents: DateComponents(day: 1)
        )

        do {
            let collection = try await descriptor.result(for: healthStore)
            guard !Task.isCancelled else { return [:] }

            var values: [Date: Double] = [:]
            collection.enumerateStatistics(from: startDate, to: endDate) {
                statistics,
                _ in
                let day = calendar.startOfDay(for: statistics.startDate)
                let kilocalories = statistics.sumQuantity()?
                    .doubleValue(for: .kilocalorie()) ?? 0
                values[day] = max(0, kilocalories)
            }
            return values
        } catch {
            return [:]
        }
    }

    private func workoutActivities(
        for day: Date,
        calendar: Calendar
    ) async -> [HealthWorkoutActivity] {
        let workoutType = HKObjectType.workoutType()
        guard let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return []
        }

        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }

        let datePredicate = HKQuery.predicateForSamples(
            withStart: dayStart,
            end: dayEnd,
            options: [.strictStartDate]
        )
        let samplePredicate = HKSamplePredicate<HKWorkout>.workout(datePredicate)
        let descriptor = HKSampleQueryDescriptor<HKWorkout>(
            predicates: [samplePredicate],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )

        do {
            let workouts = try await descriptor.result(for: healthStore)
            return workouts.compactMap { workout in
                let statisticsEnergy = workout
                    .statistics(for: activeEnergyType)?
                    .sumQuantity()?
                    .doubleValue(for: .kilocalorie())
                let legacyEnergy = workout.totalEnergyBurned?
                    .doubleValue(for: .kilocalorie())
                let kilocalories = max(0, statisticsEnergy ?? legacyEnergy ?? 0)
                guard kilocalories > 0 else { return nil }

                let presentation = Self.presentation(for: workout.workoutActivityType)
                let healthKitSource: String
                #if DEBUG && targetEnvironment(simulator)
                if workout.metadata?[Self.simulatorSeedMetadataKey] as? Bool == true {
                    healthKitSource = "HealthKit • Test data"
                } else {
                    healthKitSource = "HealthKit • \(workout.sourceRevision.source.name)"
                }
                #else
                healthKitSource = "HealthKit • \(workout.sourceRevision.source.name)"
                #endif

                return HealthWorkoutActivity(
                    id: workout.uuid,
                    name: presentation.name,
                    symbolName: presentation.symbolName,
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    activeEnergyKilocalories: kilocalories,
                    sourceName: healthKitSource
                )
            }
        } catch {
            return []
        }
    }

    private static func presentation(
        for activityType: HKWorkoutActivityType
    ) -> (name: String, symbolName: String) {
        switch activityType {
        case .walking:
            return ("Walking", "figure.walk.circle.fill")
        case .running:
            return ("Running", "figure.run.circle.fill")
        case .cycling:
            return ("Cycling", "figure.outdoor.cycle.circle.fill")
        case .hiking:
            return ("Hiking", "figure.hiking.circle.fill")
        case .swimming:
            return ("Swimming", "figure.pool.swim.circle.fill")
        case .traditionalStrengthTraining:
            return ("Strength Training", "dumbbell.fill")
        case .functionalStrengthTraining:
            return ("Functional Strength", "figure.strengthtraining.functional")
        case .highIntensityIntervalTraining:
            return ("High Intensity Interval Training", "figure.highintensity.intervaltraining")
        case .yoga:
            return ("Yoga", "figure.yoga")
        case .pilates:
            return ("Pilates", "figure.pilates")
        case .coreTraining:
            return ("Core Training", "figure.core.training")
        case .dance, .cardioDance, .socialDance:
            return ("Dance", "figure.dance")
        case .elliptical:
            return ("Elliptical", "figure.elliptical")
        case .rowing:
            return ("Rowing", "figure.rower")
        case .stairClimbing, .stairs, .stepTraining:
            return ("Stair Training", "figure.stair.stepper")
        case .mixedCardio:
            return ("Mixed Cardio", "figure.mixed.cardio")
        case .crossTraining:
            return ("Cross Training", "figure.cross.training")
        case .soccer:
            return ("Soccer", "figure.soccer")
        case .basketball:
            return ("Basketball", "figure.basketball")
        case .tennis:
            return ("Tennis", "figure.tennis")
        default:
            return ("Workout", "figure.run.circle.fill")
        }
    }

    private func totalQuantity(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        day: Date,
        calendar: Calendar
    ) async -> Double {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return 0
        }

        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return 0
        }

        let datePredicate = HKQuery.predicateForSamples(
            withStart: dayStart,
            end: dayEnd,
            options: [.strictStartDate]
        )
        let samplePredicate = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: quantityType,
            predicate: datePredicate
        )
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: samplePredicate,
            options: .cumulativeSum
        )

        do {
            let statistics = try await descriptor.result(for: healthStore)
            return statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
        } catch {
            return 0
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    private func seedSimulatorHealthKitIfNeeded(
        sleepType: HKCategoryType,
        activeEnergyType: HKQuantityType,
        stepCountType: HKQuantityType,
        workoutType: HKWorkoutType,
        calendar: Calendar = .current
    ) async {
        let activeEnergyValues = [286.0, 214.0, 347.0, 192.0, 265.0, 318.0, 238.0]
        let stepValues = [7_420.0, 5_830.0, 9_160.0, 4_980.0, 6_740.0, 8_350.0, 6_210.0]
        let wakeMinutes = [420, 385, 455, 410, 440, 395, 430]
        let bedtimeMinutes = [1_385, 1_350, 1_410, 1_365, 1_395, 1_340, 1_375]
        let today = calendar.startOfDay(for: Date())

        for dayOffset in 0...6 {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                continue
            }

            let defaultsKey = simulatorDefaultsKey(for: dayStart, calendar: calendar)
            if UserDefaults.standard.bool(forKey: defaultsKey) {
                continue
            }

            if await hasSimulatorSeed(
                on: dayStart,
                dayEnd: dayEnd,
                stepCountType: stepCountType
            ) {
                UserDefaults.standard.set(true, forKey: defaultsKey)
                continue
            }

            let metadata: [String: Any] = [
                Self.simulatorSeedMetadataKey: true,
                HKMetadataKeyWasUserEntered: true
            ]
            let activityEnd = min(
                dayEnd,
                dayOffset == 0 ? Date() : dayStart.addingTimeInterval(20 * 60 * 60)
            )
            guard activityEnd > dayStart else { continue }

            let activeEnergySample = HKQuantitySample(
                type: activeEnergyType,
                quantity: HKQuantity(
                    unit: .kilocalorie(),
                    doubleValue: activeEnergyValues[dayOffset]
                ),
                start: dayStart,
                end: activityEnd,
                metadata: metadata
            )
            let stepSample = HKQuantitySample(
                type: stepCountType,
                quantity: HKQuantity(unit: .count(), doubleValue: stepValues[dayOffset]),
                start: dayStart,
                end: activityEnd,
                metadata: metadata
            )

            let minutesBeforeMidnight = 24 * 60 - bedtimeMinutes[dayOffset]
            let sleepStart = dayStart.addingTimeInterval(
                -TimeInterval(minutesBeforeMidnight * 60)
            )
            let intendedSleepEnd = dayStart.addingTimeInterval(
                TimeInterval(wakeMinutes[dayOffset] * 60)
            )
            let sleepEnd = min(intendedSleepEnd, Date())
            let sleepSample = HKCategorySample(
                type: sleepType,
                value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                start: sleepStart,
                end: sleepEnd,
                metadata: metadata
            )

            do {
                try await healthStore.save([activeEnergySample, stepSample, sleepSample])
                UserDefaults.standard.set(true, forKey: defaultsKey)
            } catch {
                // Simulator seed data is optional and must never block app startup.
            }
        }

        await seedSimulatorWorkoutsIfNeeded(
            workoutType: workoutType,
            calendar: calendar
        )
    }

    private func seedSimulatorWorkoutsIfNeeded(
        workoutType: HKWorkoutType,
        calendar: Calendar
    ) async {
        let today = calendar.startOfDay(for: Date())
        let dailyWorkouts: [[(type: HKWorkoutActivityType, startMinute: Int, duration: Int, kcal: Double)]] = [
            [(.walking, 7 * 60 + 20, 42, 78), (.functionalStrengthTraining, 18 * 60 + 10, 36, 112), (.yoga, 20 * 60 + 5, 28, 42)],
            [(.running, 6 * 60 + 45, 31, 246), (.walking, 17 * 60 + 30, 24, 54)],
            [(.cycling, 8 * 60 + 10, 58, 318)],
            [(.walking, 7 * 60 + 5, 35, 72), (.pilates, 19 * 60, 44, 126)],
            [(.highIntensityIntervalTraining, 17 * 60 + 40, 27, 205)],
            [(.hiking, 9 * 60 + 15, 92, 292)],
            [(.swimming, 7 * 60 + 30, 41, 218)]
        ]

        for dayOffset in 0...6 {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
                  !(await hasSimulatorWorkoutSeed(
                    on: dayStart,
                    dayEnd: dayEnd,
                    workoutType: workoutType
                  )) else {
                continue
            }

            let metadata: [String: Any] = [
                Self.simulatorSeedMetadataKey: true,
                HKMetadataKeyWasUserEntered: true
            ]
            let workouts = dailyWorkouts[dayOffset].compactMap { item -> HKWorkout? in
                let start = dayStart.addingTimeInterval(TimeInterval(item.startMinute * 60))
                let intendedEnd = start.addingTimeInterval(TimeInterval(item.duration * 60))
                let end = min(intendedEnd, dayEnd, Date())
                guard start < end else { return nil }

                return HKWorkout(
                    activityType: item.type,
                    start: start,
                    end: end,
                    duration: end.timeIntervalSince(start),
                    totalEnergyBurned: HKQuantity(
                        unit: .kilocalorie(),
                        doubleValue: item.kcal
                    ),
                    totalDistance: nil,
                    metadata: metadata
                )
            }

            guard !workouts.isEmpty else { continue }
            do {
                try await healthStore.save(workouts)
            } catch {
                // Simulator seed data is optional and must never block app startup.
            }
        }
    }

    private func hasSimulatorWorkoutSeed(
        on dayStart: Date,
        dayEnd: Date,
        workoutType: HKWorkoutType
    ) async -> Bool {
        let datePredicate = HKQuery.predicateForSamples(
            withStart: dayStart,
            end: dayEnd,
            options: [.strictStartDate]
        )
        let metadataPredicate = HKQuery.predicateForObjects(
            withMetadataKey: Self.simulatorSeedMetadataKey
        )
        let predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [datePredicate, metadataPredicate]
        )
        let samplePredicate = HKSamplePredicate<HKWorkout>.workout(predicate)
        let descriptor = HKSampleQueryDescriptor<HKWorkout>(
            predicates: [samplePredicate],
            sortDescriptors: [],
            limit: 1
        )

        do {
            return try await !descriptor.result(for: healthStore).isEmpty
        } catch {
            return false
        }
    }

    private func hasSimulatorSeed(
        on dayStart: Date,
        dayEnd: Date,
        stepCountType: HKQuantityType
    ) async -> Bool {
        let datePredicate = HKQuery.predicateForSamples(
            withStart: dayStart,
            end: dayEnd,
            options: [.strictStartDate]
        )
        let metadataPredicate = HKQuery.predicateForObjects(
            withMetadataKey: Self.simulatorSeedMetadataKey
        )
        let predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [datePredicate, metadataPredicate]
        )
        let samplePredicate = HKSamplePredicate<HKQuantitySample>.quantitySample(
            type: stepCountType,
            predicate: predicate
        )
        let descriptor = HKSampleQueryDescriptor<HKQuantitySample>(
            predicates: [samplePredicate],
            sortDescriptors: [],
            limit: 1
        )

        do {
            return try await !descriptor.result(for: healthStore).isEmpty
        } catch {
            return false
        }
    }

    private func simulatorDefaultsKey(for day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return "\(Self.simulatorSeedDefaultsPrefix).\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
    #endif

    private static func mergingOverlappingIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.end < rhs.end
            }
            return lhs.start < rhs.start
        }

        var merged: [DateInterval] = []
        for interval in sorted {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }

            if interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    private static func groupedSleepSessions(
        _ intervals: [DateInterval],
        maximumGap: TimeInterval = 2 * 60 * 60
    ) -> [[DateInterval]] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var sessions: [[DateInterval]] = []

        for interval in sorted {
            guard let previousEnd = sessions.last?.last?.end,
                  interval.start.timeIntervalSince(previousEnd) <= maximumGap else {
                sessions.append([interval])
                continue
            }
            sessions[sessions.count - 1].append(interval)
        }
        return sessions
    }
}
