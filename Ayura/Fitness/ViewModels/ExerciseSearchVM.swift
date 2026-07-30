import Combine
import Foundation
import SwiftData

// MARK: - Workout filter mode
enum WorkoutFilterMode {
    case all            // показва всички упражнения
    case onlyWorkouts   // показва само workouts
    case excludeWorkouts // показва всички без workouts
}

@MainActor
final class ExerciseSearchVM: ObservableObject {
    // MARK: - Inputs from the View
    @Published var query: String = ""
    @Published var muscleGroupFilter: MuscleGroup? = nil
    
    /// Спортовете от профила на потребителя. Ако е празен – не се филтрира.
    @Published var userSportsFilter: [Sport] = []
    /// Ако е true: показва само упражнения, които съвпадат с поне един спорт.
    @Published var requireSportsMatch: Bool = false
    
    /// Филтриране по workout режим
    @Published var workoutFilterMode: WorkoutFilterMode = .all {
        didSet {
            if oldValue != workoutFilterMode {
                resetAndLoad()
            }
        }
    }
    
    @Published var isFavoritesModeActive: Bool = false {
        didSet {
            if oldValue != isFavoritesModeActive {
                resetAndLoad()
            }
        }
    }

    @Published var profileAgeInMonths: Int? = nil {
        didSet {
            if oldValue != profileAgeInMonths {
                resetAndLoad()
            }
        }
    }
    // MARK: - Outputs to the View
    @Published private(set) var items: [ExerciseItem] = []
    @Published private(set) var hasMore: Bool = false
    @Published private(set) var isLoading: Bool = false

    // MARK: - Private State
    private weak var context: ModelContext?
    private var container: ModelContainer?
    private var cancellables = Set<AnyCancellable>()
    private var excludedIDs = Set<ExerciseItem.ID>()

    // MARK: - Paging
    private let pageSize = 40
    private var currentOffset = 0
    private var currentTask: Task<Void, Never>?

    // Generation for concurrency safety
    private var generation: Int = 0

    // MARK: - Init
    init() {
        Publishers.CombineLatest3($query, $muscleGroupFilter, $userSportsFilter)
            .combineLatest($requireSportsMatch)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.resetAndLoad()
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods
    func attach(context: ModelContext) {
        guard self.context !== context else { return }
        self.context = context
        self.container = context.container
    }

    func exclude(_ exercises: Set<ExerciseItem>) {
        let newIDs = Set(exercises.map(\.id))
        guard newIDs != excludedIDs else { return }
        excludedIDs = newIDs
        resetAndLoad()
    }

    func loadNextPage() {
        guard !isLoading, hasMore else { return }
        loadPage()
    }

    func resetAndLoad() {
        currentTask?.cancel()
        currentTask = nil

        items = []
        currentOffset = 0
        hasMore = false
        isLoading = false
        generation &+= 1
        loadPage()
    }

    @MainActor
    private func loadPage() {
        guard let container, !isLoading else { return }
        isLoading = true

        let capturedPredicate = makePredicate()
        let capturedOffset = self.currentOffset
        let capturedPageSize = self.pageSize
        let capturedGeneration = self.generation
        let capturedMuscleGroup = self.muscleGroupFilter
        let capturedUserSports = self.userSportsFilter
        let capturedRequireMatch = self.requireSportsMatch

        currentTask?.cancel()
        currentTask = Task {
            let backgroundResult: (ids: [PersistentIdentifier], dbFetchCount: Int)

            do {
                backgroundResult = try await Task.detached {
                    let bgContext = ModelContext(container)

                    var descriptor = FetchDescriptor<ExerciseItem>(
                        predicate: capturedPredicate,
                        sortBy: [SortDescriptor(\.nameNormalized)]
                    )
                    descriptor.fetchOffset = capturedOffset
                    descriptor.fetchLimit = capturedPageSize

                    let fetchedItems = try bgContext.fetch(descriptor)
                    if Task.isCancelled { return ([], 0) }

                    // 1) muscle filter (in-memory)
                    let afterMuscleFilter: [ExerciseItem]
                    if let group = capturedMuscleGroup {
                        afterMuscleFilter = fetchedItems.filter { $0.muscleGroups.contains(group) }
                    } else {
                        afterMuscleFilter = fetchedItems
                    }

                    // 2) sports filter (in-memory)
                    let finalItems: [ExerciseItem]
                    if !capturedUserSports.isEmpty {
                        finalItems = afterMuscleFilter.filter { item in
                            let itemSports = item.sports ?? []
                            if capturedRequireMatch {
                                return !itemSports.isEmpty && !Set(itemSports).isDisjoint(with: capturedUserSports)
                            } else {
                                return itemSports.isEmpty || !Set(itemSports).isDisjoint(with: capturedUserSports)
                            }
                        }
                    } else {
                        finalItems = afterMuscleFilter
                    }

                    return (finalItems.map(\.persistentModelID), fetchedItems.count)
                }.value
            } catch {
                print("ExerciseSearchVM background task error: \(error)")
                self.isLoading = false
                self.hasMore = false
                return
            }

            if Task.isCancelled { return }
            guard self.generation == capturedGeneration else { return }

            var appendedCountThisPage = 0

            if !backgroundResult.ids.isEmpty {
                guard let context = self.context else { return }
                var toAppend: [ExerciseItem] = []
                toAppend.reserveCapacity(backgroundResult.ids.count)

                for id in backgroundResult.ids {
                    if let model = try? context.model(for: id) as? ExerciseItem {
                        toAppend.append(model)
                    }
                }

                appendedCountThisPage = toAppend.count
                if appendedCountThisPage > 0 {
                    self.items.append(contentsOf: toAppend)
                }
            }

            self.currentOffset += backgroundResult.dbFetchCount
            self.hasMore = backgroundResult.dbFetchCount == capturedPageSize
            self.isLoading = false

            if appendedCountThisPage == 0, self.hasMore, self.generation == capturedGeneration {
                self.loadPage()
            }
        }
    }

    // MARK: - Predicate Builder
    private func makePredicate() -> Predicate<ExerciseItem> {
        let normalizedQuery = query.foldedSearchKey
        let capturedExcludedIDs = excludedIDs
        let capturedIsFavorites = isFavoritesModeActive
        let mode = workoutFilterMode
        let capturedAge = self.profileAgeInMonths

        switch mode {
        case .all:
            return #Predicate<ExerciseItem> { exercise in
                (normalizedQuery.isEmpty || exercise.nameNormalized.contains(normalizedQuery))
                && (capturedExcludedIDs.isEmpty || !capturedExcludedIDs.contains(exercise.id))
                && (!capturedIsFavorites || exercise.isFavorite == true)
                && (capturedAge == nil || exercise.minimalAgeMonths <= capturedAge!)
            }
        case .onlyWorkouts:
            return #Predicate<ExerciseItem> { exercise in
                (normalizedQuery.isEmpty || exercise.nameNormalized.contains(normalizedQuery))
                && (capturedExcludedIDs.isEmpty || !capturedExcludedIDs.contains(exercise.id))
                && (!capturedIsFavorites || exercise.isFavorite == true)
                && exercise.isWorkout == true
                && (capturedAge == nil || exercise.minimalAgeMonths <= capturedAge!)
            }
        case .excludeWorkouts:
            return #Predicate<ExerciseItem> { exercise in
                (normalizedQuery.isEmpty || exercise.nameNormalized.contains(normalizedQuery))
                && (capturedExcludedIDs.isEmpty || !capturedExcludedIDs.contains(exercise.id))
                && (!capturedIsFavorites || exercise.isFavorite == true)
                && exercise.isWorkout == false
                && (capturedAge == nil || exercise.minimalAgeMonths <= capturedAge!)
            }
        }
    }


}
