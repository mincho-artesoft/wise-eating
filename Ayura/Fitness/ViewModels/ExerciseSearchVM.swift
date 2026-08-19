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
    @Published var ayurvedaFilters: AyurvedaSearchFilters = .empty
    
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
        Publishers.CombineLatest3($query, $muscleGroupFilter, $ayurvedaFilters)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.resetAndLoad()
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods
    func attach(context: ModelContext) {
        guard self.context !== context else { return }
        self.context = context
        self.container = context.container
        try? CatalogPreferenceStore.shared.load(context: context)
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

        let parsedQuery = ExerciseAyurvedaSearch.parse(query)
        let capturedPredicate = makePredicate(
            lexicalQuery: parsedQuery.lexicalQuery
        )
        let capturedOffset = self.currentOffset
        let capturedPageSize = self.pageSize
        let capturedGeneration = self.generation
        let capturedMuscleGroup = self.muscleGroupFilter
        let capturedFavoritesOnly = self.isFavoritesModeActive
        let capturedFavoriteIDs = Set(
            CatalogPreferenceStore.shared.favoriteIDs(kind: "exercise")
        )
        let capturedAyurvedaFilters = self.ayurvedaFilters
        let capturedAyurvedaConstraints = parsedQuery.constraints
        let usesAyurvedaRanking = capturedAyurvedaFilters.isActive
            || !capturedAyurvedaConstraints.isEmpty

        currentTask?.cancel()
        currentTask = Task {
            let backgroundResult: (
                ids: [PersistentIdentifier],
                nextOffset: Int,
                hasMore: Bool
            )

            do {
                backgroundResult = try await Task.detached {
                    let bgContext = ModelContext(container)

                    var descriptor = FetchDescriptor<ExerciseItem>(
                        predicate: capturedPredicate,
                        sortBy: [SortDescriptor(\.nameNormalized)]
                    )
                    if !usesAyurvedaRanking {
                        descriptor.fetchOffset = capturedOffset
                        descriptor.fetchLimit = capturedPageSize
                    }

                    let fetchedItems = try bgContext.fetch(descriptor)
                    if Task.isCancelled { return ([], capturedOffset, false) }

                    let afterFavoriteFilter = capturedFavoritesOnly
                        ? fetchedItems.filter {
                            $0.isFavorite || capturedFavoriteIDs.contains($0.id)
                        }
                        : fetchedItems

                    // 1) muscle filter (in-memory)
                    let afterMuscleFilter: [ExerciseItem]
                    if let group = capturedMuscleGroup {
                        afterMuscleFilter = afterFavoriteFilter.filter {
                            $0.muscleGroups.contains(group)
                        }
                    } else {
                        afterMuscleFilter = afterFavoriteFilter
                    }

                    if usesAyurvedaRanking {
                        let ranked = afterMuscleFilter.sorted { lhs, rhs in
                            let lhsScore = ExerciseAyurvedaSearch.score(
                                item: lhs,
                                filters: capturedAyurvedaFilters,
                                constraints: capturedAyurvedaConstraints
                            )
                            let rhsScore = ExerciseAyurvedaSearch.score(
                                item: rhs,
                                filters: capturedAyurvedaFilters,
                                constraints: capturedAyurvedaConstraints
                            )
                            if lhsScore != rhsScore { return lhsScore > rhsScore }
                            return lhs.nameNormalized < rhs.nameNormalized
                        }
                        let page = ranked
                            .dropFirst(capturedOffset)
                            .prefix(capturedPageSize)
                        let nextOffset = capturedOffset + page.count
                        return (
                            page.map(\.persistentModelID),
                            nextOffset,
                            nextOffset < ranked.count
                        )
                    }

                    return (
                        afterMuscleFilter.map(\.persistentModelID),
                        capturedOffset + fetchedItems.count,
                        fetchedItems.count == capturedPageSize
                    )
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

            self.currentOffset = backgroundResult.nextOffset
            self.hasMore = backgroundResult.hasMore
            self.isLoading = false

            if appendedCountThisPage == 0, self.hasMore, self.generation == capturedGeneration {
                self.loadPage()
            }
        }
    }

    // MARK: - Predicate Builder
    private func makePredicate(
        lexicalQuery: String
    ) -> Predicate<ExerciseItem> {
        let normalizedQuery = lexicalQuery.foldedSearchKey
        let capturedExcludedIDs = excludedIDs
        let mode = workoutFilterMode
        let capturedAge = self.profileAgeInMonths

        switch mode {
        case .all:
            return #Predicate<ExerciseItem> { exercise in
                (normalizedQuery.isEmpty || exercise.nameNormalized.contains(normalizedQuery))
                && (capturedExcludedIDs.isEmpty || !capturedExcludedIDs.contains(exercise.id))
                && (capturedAge == nil || exercise.minimalAgeMonths <= capturedAge!)
            }
        case .onlyWorkouts:
            return #Predicate<ExerciseItem> { exercise in
                (normalizedQuery.isEmpty || exercise.nameNormalized.contains(normalizedQuery))
                && (capturedExcludedIDs.isEmpty || !capturedExcludedIDs.contains(exercise.id))
                && exercise.isWorkout == true
                && (capturedAge == nil || exercise.minimalAgeMonths <= capturedAge!)
            }
        case .excludeWorkouts:
            return #Predicate<ExerciseItem> { exercise in
                (normalizedQuery.isEmpty || exercise.nameNormalized.contains(normalizedQuery))
                && (capturedExcludedIDs.isEmpty || !capturedExcludedIDs.contains(exercise.id))
                && exercise.isWorkout == false
                && (capturedAge == nil || exercise.minimalAgeMonths <= capturedAge!)
            }
        }
    }


}
